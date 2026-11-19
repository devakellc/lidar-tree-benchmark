#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages(library(data.table))
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
source(.find("master_tables_lib.R"))
source(.find("chance_simulation_lib.R"))

# How the paper's chance-corrected scores behave when the truth is known
# (post hoc, added after an internal review). Synthetic tower plots: trees
# with mild inhibition (no two closer than 1.5 m) at D trees/ha over the 40 m
# core, its 4 m matching margin and a 6 m buffer; heights lognormal (median
# 15 m, clamped to 3-60 m). A detector with skill s and commission f detects
# each tree with probability s, at the tree's position plus an isotropic
# Gaussian offset (sd 1.2 m) and its height plus a 1 m error, and adds
# round(f x trees) commission points, uniform over the simulated square with
# tree-like heights. Detectors on a plot share one random stream (a tree
# detected at skill s is detected at every higher skill, at the same place).
# The reference is every tree in the core (complete) or the trees in two of
# its four 20 m quadrants (half, the pair drawn per plot), and the detectors
# act on all trees either way. The truth is the skilled share within r: the
# reference stems whose own skilled detection lies within r. Beside the null
# recall, the share of the other (missed) stems that the observed matcher
# pairs is counted: the correction assumes they match at the null's rate.
#
# Scoring is the paper's (paper_sensitivity.R MODE=null): score_plot with the
# greedy matcher at radius r and the height gate; K toroidal shifts per plot
# and radius, null_offset(2 (20 + r), seed_k, min_shift = 8) and
# shift_detections within 20 + r, shared by every detector and reference; a
# cell's null is its mean counts over the shifts; scores pool summed counts
# over the plots; corrected = (observed - null) / (1 - null) for recall,
# precision and F1. Intervals: the master tables' paired plot bootstrap
# (mt_plot_weights / mt_boot_scores, 1000 resamples, seed MT_SEED), shared by
# every detector of a setting. Seeds: plot "D<DDD>_<iiii>" draws everything
# from cs_seed(seed_for("chance_sim", plot, "plot"), SEED) and its shift k
# from cs_seed(seed_for("chance_sim", plot, "null"), SEED, k).
#
# Scenarios: (1) single detectors s in {0.2,0.4,0.6,0.8} x f in {0.3,1.0},
# complete and half references, r = 4 and 2 m, 240 trees/ha; (2) paired
# detectors against a baseline (s 0.45, f 0.45): (a) s 0.60 f 0.70, (b) s 0.55
# f 0.45, (c) s 0.45 f 1.0, same settings; (3) (a) against the baseline at 60,
# 150 and 300 trees/ha, complete, 4 m. A detector without skill (s 0, f 1)
# runs in every setting and must score zero above the null.
#
# (4) Stand structure and reference completeness (added the same day, after a
# review of the first version): the inhibited pattern and two Matern cluster
# processes (clusters of radius 4 m with 6 trees on average, radius 8 m with
# 4), each tree a reference stem with probability p in {1, 0.8, 0.6} while
# every tree stays detectable. Total density 240 trees/ha for every p, and
# reference density 240 stems/ha (300 and 400 trees/ha at p 0.8 and 0.6).
# Detectors: the baseline and (a), (b), (c) of scenario 2, a skilled one
# (s 0.8, f 0.3), the uniform detector without skill, and two detectors
# without skill on the reference whose detections follow the trees: one that
# detects 0.8 of the unmapped trees only (f 0.3), and one that detects 0.8 of
# all trees 5-10 m from the tree (f 0.3). Complete and half references, 4 and
# 2 m. Inhibited plots reuse the plot ids, and so the trees, detections and
# shifts, of scenarios 2 and 3 (D240, D300); clustered plots are
# "M4_D<DDD>_<iiii>" and "M8_D<DDD>_<iiii>", seeded the same way.
# Added after a review of scenario 4: two split-crown detectors, the baseline
# plus, for a share 0.5 or 0.8 of the trees it detects, a second detection
# 1.5-4 m from the tree at the tree's height (commission that follows the
# trees, no extra skill), compared with the baseline as (d) on the grid of
# (a) to (c); and (e), the displaced detector minus the uniform detector
# without skill, on complete references. Their draws come after all others,
# so every earlier row reproduces.
#   Rscript scripts/simulate_chance_correction.R [N=200] [K=200] [SEED=0]
#     [CORES=6] [OUT=$CLAUDE_JOB_DIR/sensitivity/chance_simulation]
# Writes OUT/chance_simulation_{cells,detectors,table1_single,table2_paired,
# table3_density,table4_zero_skill}.csv, the structure scenario's
# chance_simulation_structure_{cells,neighbours,detectors,leads}.csv and
# chance_simulation_table{5_structure_settings,6_structure_single,
# 7_structure_paired,8_structure_zero_skill,9_structure_half}.csv,
# chance_simulation_tables.md and chance_simulation_settings.txt. Output files
# hold nothing that varies between runs with the same N, K and SEED (no wall
# time, core count or path); timing goes to the console only.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
d     <- .job_dir()
N     <- as.integer(if (is.null(A$N)) 200 else A$N)
K     <- as.integer(if (is.null(A$K)) 200 else A$K)
SEED  <- as.integer(if (is.null(A$SEED)) 0 else A$SEED)
CORES <- as.integer(if (is.null(A$CORES)) 6 else A$CORES)
OUT   <- if (is.null(A$OUT)) file.path(d, "sensitivity", "chance_simulation") else A$OUT
MIN_SHIFT <- 8
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
t_start <- Sys.time()

## ---- detectors and settings -------------------------------------------------------
GRID <- expand.grid(s = c(0.2, 0.4, 0.6, 0.8), f = c(0.3, 1.0))
GRID$detector <- sprintf("s%.2f_f%.2f", GRID$s, GRID$f)
PAIRS <- data.frame(detector = c("baseline", "a_more_skill_more_commission",
                                 "b_more_skill", "c_more_commission"),
                    s = c(0.45, 0.60, 0.55, 0.45), f = c(0.45, 0.70, 0.45, 1.0))
ZERO <- data.frame(detector = "zero_skill", s = 0, f = 1)
DET_240 <- rbind(GRID[c("detector", "s", "f")], PAIRS, ZERO)
DET_DENS <- rbind(PAIRS[1:2, ], ZERO)
DENSITIES <- c(240, 60, 150, 300)
COMPARISONS <- c(a_more_skill_more_commission = "(a) more skill, more commission",
                 b_more_skill = "(b) more skill, equal commission",
                 c_more_commission = "(c) equal skill, more commission")
# Every paired comparison: leader minus base on the same plots, shifts and
# resamples. (a) to (c) run wherever their detectors do, (d) and (e) in
# scenario 4 only; `half` says whether a comparison is also made on half
# references; `short` is its tag in the scenario-4 tables.
CMP <- data.frame(
  comparison = c(names(COMPARISONS), "d_split_crowns_050", "d_split_crowns_080",
                 "e_displaced_minus_uniform"),
  leader = c(names(COMPARISONS), "split_050", "split_080", "zero_displaced"),
  base = c(rep("baseline", 5), "zero_skill"),
  label = c(unname(COMPARISONS), "(d) equal skill, split crowns at rate 0.5",
            "(d) equal skill, split crowns at rate 0.8",
            "(e) no skill: displaced minus uniform"),
  short = c("(a)", "(b)", "(c)", "(d) 0.5", "(d) 0.8", "(e)"),
  half = c(rep(TRUE, 5), FALSE), stringsAsFactors = FALSE)

plot_id <- function(D, i) sprintf("D%03d_%04d", D, i)
jobs <- do.call(rbind, lapply(DENSITIES, function(D) data.frame(D = D, i = seq_len(N))))
run_job <- function(j) {
  D <- jobs$D[j]; pid <- plot_id(D, jobs$i[j])
  pl <- cs_plot(D, cs_seed(seed_for("chance_sim", pid, "plot"), SEED))
  null_base <- seed_for("chance_sim", pid, "null")
  res <- if (D == 240)
    cs_score_plot(pl, DET_240, c("complete", "half"), c(4, 2), K,
                  function(k) cs_seed(null_base, SEED, k), MIN_SHIFT)
  else cs_score_plot(pl, DET_DENS, "complete", 4, K,
                     function(k) cs_seed(null_base, SEED, k), MIN_SHIFT)
  if (is.null(res)) return(NULL)
  cbind(plot = pid, n_trees = nrow(pl$trees), res, stringsAsFactors = FALSE)
}
cat(sprintf("simulating %d plots x %d densities, K = %d, SEED = %d, %d cores\n",
            N, length(DENSITIES), K, SEED, CORES))
res <- parallel::mclapply(seq_len(nrow(jobs)), function(j)
  tryCatch(run_job(j), error = function(e) e), mc.cores = CORES)
bad <- which(vapply(res, function(r) inherits(r, "error") || inherits(r, "try-error"), TRUE))
if (length(bad)) stop("plots failed: ", paste(plot_id(jobs$D[bad], jobs$i[bad]), collapse = ","),
                      "; first error: ", conditionMessage(res[[bad[1]]]))
cells <- as.data.frame(rbindlist(Filter(Negate(is.null), res)))
cells$site <- "SIM"
write.csv(cells, file.path(OUT, "chance_simulation_cells.csv"), row.names = FALSE)
t_sim <- Sys.time()
cat(sprintf("scored in %.1f min\n", as.numeric(t_sim - t_start, units = "mins")))

## ---- scenario 4: stand structure and reference completeness ----------------------
# Per pattern, the plots at 240 trees/ha carry the references at p = 1, 0.8
# and 0.6 (total density held), and the plots at 300 and 400 trees/ha those
# at p = 0.8 and 0.6 (reference density held at 240 stems/ha).
STRUCT_P <- list(`240` = c(1, 0.8, 0.6), `300` = 0.8, `400` = 0.6)
# The split-crown detectors come last, so that every earlier row of a plot
# keeps its place among the others.
DET_STRUCT <- rbind(
  cbind(PAIRS, mode = "all", rate = 0),
  data.frame(detector = c("skilled", "zero_skill", "zero_unmapped", "zero_displaced",
                          "split_050", "split_080"),
             s = c(0.8, 0, 0.8, 0.8, 0.45, 0.45), f = c(0.3, 1, 0.3, 0.3, 0.45, 0.45),
             mode = c("all", "all", "unmapped", "displaced", "split", "split"),
             rate = c(0, 0, 0, 0, 0.5, 0.8)))
ZERO_STRUCT <- c(zero_skill = "uniform commission (s 0, f 1)",
                 zero_unmapped = "unmapped trees only (0.8 of them, f 0.3)",
                 zero_displaced = "displaced 5-10 m (0.8 of all trees, f 0.3)")
struct_id <- function(pattern, D, i) cs_plot_id(D, i, pattern)
jobs2 <- do.call(rbind, lapply(names(CS_PATTERNS), function(pt)
  do.call(rbind, lapply(as.numeric(names(STRUCT_P)), function(D)
    data.frame(pattern = pt, D = D, i = seq_len(N), stringsAsFactors = FALSE)))))
run_job2 <- function(j) {
  pt <- jobs2$pattern[j]; D <- jobs2$D[j]; pid <- struct_id(pt, D, jobs2$i[j])
  pl <- cs_plot(D, cs_seed(seed_for("chance_sim", pid, "plot"), SEED), pattern = pt)
  null_base <- seed_for("chance_sim", pid, "null")
  ps <- STRUCT_P[[as.character(D)]]
  refs <- expand.grid(ref = c("complete", "half"), p = ps, stringsAsFactors = FALSE)
  res <- cs_score_structure(pl, DET_STRUCT, refs, c(4, 2), K,
                            function(k) cs_seed(null_base, SEED, k), MIN_SHIFT)
  nb <- do.call(rbind, lapply(ps, function(p)
    data.frame(plot = pid, pattern = pt, D = D, p = p, t(cs_neighbours(pl, p)))))
  list(cells = if (!is.null(res)) cbind(plot = pid, n_trees = nrow(pl$trees), res,
                                        stringsAsFactors = FALSE),
       nb = nb)
}
cat(sprintf("structure scenario: %d plots, K = %d\n", nrow(jobs2), K))
res2 <- parallel::mclapply(seq_len(nrow(jobs2)), function(j)
  tryCatch(run_job2(j), error = function(e) e), mc.cores = CORES)
bad <- which(vapply(res2, function(r) inherits(r, "error") || inherits(r, "try-error"), TRUE))
if (length(bad)) stop(length(bad), " structure plots failed, first ",
                      struct_id(jobs2$pattern[bad[1]], jobs2$D[bad[1]], jobs2$i[bad[1]]),
                      ": ", conditionMessage(res2[[bad[1]]]))
cells2 <- as.data.frame(rbindlist(lapply(res2, `[[`, "cells")))
cells2$site <- "SIM"
nb2 <- as.data.frame(rbindlist(lapply(res2, `[[`, "nb")))
write.csv(cells2, file.path(OUT, "chance_simulation_structure_cells.csv"), row.names = FALSE)
write.csv(nb2, file.path(OUT, "chance_simulation_structure_neighbours.csv"), row.names = FALSE)
t_sim2 <- Sys.time()
cat(sprintf("structure scenario scored in %.1f min\n", as.numeric(t_sim2 - t_sim, units = "mins")))

## ---- pooling with paired plot resamples ------------------------------------------
# Per setting (density, reference, radius; for scenario 4 also pattern and
# p): the plots with reference stems, one resample matrix for every detector
# and variant. `key` is the setting as a one-row data.frame; `extra` adds the
# observed core detections per reference stem.
settings <- unique(cells[c("D", "ref", "tol")])
ci <- function(v) { q <- mt_interval(v); c(lower = q$lower, upper = q$upper) }
pool_setting <- function(D, ref, tol)
  pool_cells(cells[cells$D == D & cells$ref == ref & cells$tol == tol, , drop = FALSE],
             data.frame(D = D, ref = ref, tol = tol, stringsAsFactors = FALSE))
pool_cells <- function(x, key, extra = FALSE) {
  W <- mt_plot_weights(x$site, x$plot, MT_N_BOOT, MT_SEED)
  s <- mt_boot_scores(x, W, c("variant", "detector"))
  E <- function(m, v, a) s$estimate[[m]][match(paste(v, a, sep = "|"), s$groups)]
  Dr <- function(m, v, a) s$draws[[m]][, paste(v, a, sep = "|")]
  dets <- unique(x[c("detector", "s", "f")])
  per <- lapply(seq_len(nrow(dets)), function(i) {
    a <- dets$detector[i]
    est <- function(m, v) E(m, v, a)
    cor_e <- function(m) cs_corrected(est(m, "observed"), est(m, "null"))
    cor_d <- function(m) cs_corrected(Dr(m, "observed", a), Dr(m, "null", a))
    bias_d <- cor_d("recall") - Dr("recall", "truth", a)
    ob <- x[x$variant == "observed" & x$detector == a, , drop = FALSE]
    row <- data.frame(key, detector = a, s = dets$s[i], f = dets$f[i],
                      plots = nrow(W), n_ref = s$estimate$n_ref[match(paste("observed", a, sep = "|"), s$groups)],
                      recall = est("recall", "observed"), precision = est("precision", "observed"),
                      F1 = est("F1", "observed"),
                      null_recall = est("recall", "null"), null_precision = est("precision", "null"),
                      null_F1 = est("F1", "null"),
                      null_share = est("F1", "null") / est("F1", "observed"),
                      missed_match_rate = sum(ob$tp_missed) / sum(ob$n_missed),
                      true_share = est("recall", "truth"), oracle_precision = est("precision", "truth"),
                      oracle_F1 = est("F1", "truth"),
                      corr_recall = cor_e("recall"), corr_precision = cor_e("precision"),
                      corr_F1 = cor_e("F1"),
                      corr_recall_minus_truth = cor_e("recall") - est("recall", "truth"),
                      stringsAsFactors = FALSE)
    iv <- rbind(corr_recall = ci(cor_d("recall")), corr_precision = ci(cor_d("precision")),
                corr_F1 = ci(cor_d("F1")), corr_recall_minus_truth = ci(bias_d))
    for (k in rownames(iv)) {
      row[[paste0(k, "_lower")]] <- iv[k, "lower"]; row[[paste0(k, "_upper")]] <- iv[k, "upper"]
    }
    if (extra) {
      row$n_det <- s$estimate$n_det[match(paste("observed", a, sep = "|"), s$groups)]
      row$det_per_ref <- row$n_det / row$n_ref
    }
    row
  })
  per <- do.call(rbind, per)
  # Paired leads (same plots, shifts and resamples): (a) to (d) over the
  # baseline, (e) over the uniform detector without skill.
  leads <- cs_paired_leads(s, CMP[key$ref == "complete" | CMP$half, , drop = FALSE], key)
  list(per = per, leads = leads)
}
pooled <- lapply(seq_len(nrow(settings)), function(i)
  pool_setting(settings$D[i], settings$ref[i], settings$tol[i]))
per <- do.call(rbind, lapply(pooled, `[[`, "per"))
leads <- do.call(rbind, lapply(pooled, `[[`, "leads"))
per <- per[order(-(per$D == 240), per$D, per$ref, -per$tol, per$detector), ]
write.csv(per, file.path(OUT, "chance_simulation_detectors.csv"), row.names = FALSE)

t1 <- per[per$D == 240 & per$detector %in% GRID$detector, ]
t1 <- t1[order(t1$ref, -t1$tol, t1$f, t1$s), ]
t2 <- leads[leads$D == 240, ]
t2 <- t2[order(t2$comparison, t2$ref, -t2$tol), ]
t3 <- leads[leads$ref == "complete" & leads$tol == 4 & leads$comparison == "a_more_skill_more_commission", ]
t3 <- merge(t3, per[per$detector == "baseline", c("D", "ref", "tol", "n_ref", "null_share")],
            by = c("D", "ref", "tol"))
t3 <- t3[order(t3$D), ]
t4 <- per[per$detector == "zero_skill", ]
write.csv(t1, file.path(OUT, "chance_simulation_table1_single.csv"), row.names = FALSE)
write.csv(t2, file.path(OUT, "chance_simulation_table2_paired.csv"), row.names = FALSE)
write.csv(t3, file.path(OUT, "chance_simulation_table3_density.csv"), row.names = FALSE)
write.csv(t4, file.path(OUT, "chance_simulation_table4_zero_skill.csv"), row.names = FALSE)

## ---- scenario 4 pooling ----------------------------------------------------------------
# Settings in order: pattern; within it 240 trees/ha at p = 1, 0.8, 0.6, then
# 300 trees/ha (p 0.8) and 400 trees/ha (p 0.6); complete before half; 4 m
# before 2 m.
sord <- function(df, ...) order(match(df$pattern, names(CS_PATTERNS)), df$D != 240, -df$p, df$D,
                                df$ref, -df$tol, ...)
settings2 <- unique(cells2[c("pattern", "D", "p", "ref", "tol")])
settings2 <- settings2[sord(settings2), ]
pooled2 <- lapply(seq_len(nrow(settings2)), function(i) {
  k <- settings2[i, ]
  x <- cells2[cells2$pattern == k$pattern & cells2$D == k$D & cells2$p == k$p &
              cells2$ref == k$ref & cells2$tol == k$tol, , drop = FALSE]
  pool_cells(x, data.frame(pattern = k$pattern, D = k$D, p = k$p, ref = k$ref, tol = k$tol,
                           stringsAsFactors = FALSE), extra = TRUE)
})
per2 <- do.call(rbind, lapply(pooled2, `[[`, "per"))
leads2 <- do.call(rbind, lapply(pooled2, `[[`, "leads"))
per2 <- per2[sord(per2, match(per2$detector, DET_STRUCT$detector)), ]
leads2 <- leads2[sord(leads2, leads2$comparison), ]
per2$design <- ifelse(per2$D != 240, "reference density", ifelse(per2$p == 1, "both", "total density"))
leads2$design <- ifelse(leads2$D != 240, "reference density", ifelse(leads2$p == 1, "both", "total density"))

# Check: the inhibited plots at 240 trees/ha with every tree mapped are
# scenario 2's plots, so their rows must reproduce Tables 1-2's settings. A
# failed check stops the run before any pooled output of scenario 4 is
# written (the per-plot counts above are kept for diagnosis).
CHECK_TOL <- 1e-12
chk_cols_per <- setdiff(names(per), c("D", "ref", "tol", "detector", "s", "f"))
chk_cols_lead <- setdiff(names(leads), c("D", "ref", "tol", "comparison"))
p_new <- per2[per2$pattern == "inhibited" & per2$D == 240 & per2$p == 1 &
              per2$detector %in% per$detector, ]
p_old <- per[per$D == 240, ][match(paste(p_new$ref, p_new$tol, p_new$detector),
                                   with(per[per$D == 240, ], paste(ref, tol, detector))), ]
l_new <- leads2[leads2$pattern == "inhibited" & leads2$D == 240 & leads2$p == 1 &
                leads2$comparison %in% names(COMPARISONS), ]
l_old <- t2[match(paste(l_new$ref, l_new$tol, l_new$comparison),
                  paste(t2$ref, t2$tol, t2$comparison)), ]
check_ok <- nrow(p_new) == 5 * 4 && nrow(l_new) == 3 * 4 && !anyNA(p_old$detector) &&
  !anyNA(l_old$comparison) &&
  isTRUE(all.equal(unname(as.matrix(p_new[chk_cols_per])), unname(as.matrix(p_old[chk_cols_per])),
                   tolerance = CHECK_TOL)) &&
  isTRUE(all.equal(unname(as.matrix(l_new[chk_cols_lead])), unname(as.matrix(l_old[chk_cols_lead])),
                   tolerance = CHECK_TOL))
check_line <- sprintf(paste("check: the inhibited plots at 240 trees/ha with every tree mapped",
                            "reproduce scenario 2's pooled rows (relative tolerance %g): %s"),
                      CHECK_TOL, if (check_ok) "passed" else "FAILED")
cat(check_line, "\n")
if (!check_ok) stop("the structure scenario does not reproduce scenario 2; ",
                    "its pooled outputs were not written")
write.csv(per2, file.path(OUT, "chance_simulation_structure_detectors.csv"), row.names = FALSE)
write.csv(leads2, file.path(OUT, "chance_simulation_structure_leads.csv"), row.names = FALSE)

# Table 5: the settings. Reference stems per hectare over all N plots of the
# setting (a plot without reference stems adds none); mean neighbours from the
# edge-free counts; core detections per reference stem and null shares from
# the complete reference.
core_ha <- (2 * CS_PH)^2 / 1e4
pick <- function(df, pt, D, p, ref, tol, det) df[df$pattern == pt & df$D == D & df$p == p &
                                                df$ref == ref & df$tol == tol & df$detector == det, ]
s5 <- unique(per2[c("pattern", "D", "p", "design")])
t5 <- do.call(rbind, lapply(seq_len(nrow(s5)), function(i) {
  k <- s5[i, ]
  b4 <- pick(per2, k$pattern, k$D, k$p, "complete", 4, "baseline")
  b2 <- pick(per2, k$pattern, k$D, k$p, "complete", 2, "baseline")
  sk <- pick(per2, k$pattern, k$D, k$p, "complete", 4, "skilled")
  bh <- pick(per2, k$pattern, k$D, k$p, "half", 4, "baseline")
  nb <- nb2[nb2$pattern == k$pattern & nb2$D == k$D & nb2$p == k$p, ]
  data.frame(k, plots = b4$plots, plots_half = bh$plots,
             ref_per_ha = b4$n_ref / (N * core_ha),
             nb2 = sum(nb$nb2) / sum(nb$n_ref), nb4 = sum(nb$nb4) / sum(nb$n_ref),
             det_per_ref_baseline = b4$det_per_ref, det_per_ref_skilled = sk$det_per_ref,
             null_share_baseline_4m = b4$null_share, null_share_baseline_2m = b2$null_share,
             stringsAsFactors = FALSE)
}))
t6 <- per2[per2$ref == "complete" & per2$detector %in% c("baseline", "skilled"), ]
t7 <- leads2[leads2$ref == "complete", ]
t8 <- per2[per2$ref == "complete" & per2$detector %in% names(ZERO_STRUCT), ]
# Table 9: the leads on the half reference beside the complete one.
t9 <- merge(leads2[leads2$ref == "complete", ], leads2[leads2$ref == "half", ],
            by = c("pattern", "D", "p", "tol", "comparison", "design"), suffixes = c("", "_half"))
t9 <- merge(t9, setNames(per2[per2$detector == "baseline" & per2$ref == "complete",
                              c("pattern", "D", "p", "tol", "corr_recall_minus_truth")],
                         c("pattern", "D", "p", "tol", "baseline_bias")),
            by = c("pattern", "D", "p", "tol"))
t9 <- merge(t9, setNames(per2[per2$detector == "baseline" & per2$ref == "half",
                              c("pattern", "D", "p", "tol", "corr_recall_minus_truth")],
                         c("pattern", "D", "p", "tol", "baseline_bias_half")),
            by = c("pattern", "D", "p", "tol"))
t9$ref <- NULL; t9$ref_half <- NULL
t9 <- t9[order(match(t9$pattern, names(CS_PATTERNS)), t9$D != 240, -t9$p, t9$D, -t9$tol,
               t9$comparison), ]
write.csv(t5, file.path(OUT, "chance_simulation_table5_structure_settings.csv"), row.names = FALSE)
write.csv(t6, file.path(OUT, "chance_simulation_table6_structure_single.csv"), row.names = FALSE)
write.csv(t7, file.path(OUT, "chance_simulation_table7_structure_paired.csv"), row.names = FALSE)
write.csv(t8, file.path(OUT, "chance_simulation_table8_structure_zero_skill.csv"), row.names = FALSE)
write.csv(t9, file.path(OUT, "chance_simulation_table9_structure_half.csv"), row.names = FALSE)

## ---- markdown tables ------------------------------------------------------------------
f3 <- function(x) sprintf("%.3f", x)
fci <- function(e, lo, hi) sprintf("%+.3f [%+.3f, %+.3f]", e, lo, hi)
md_table <- function(header, rows) c(
  paste("|", paste(header, collapse = " | "), "|"),
  paste("|", paste(rep("---", length(header)), collapse = " | "), "|"),
  vapply(rows, function(r) paste("|", paste(r, collapse = " | "), "|"), ""))
tab1 <- md_table(
  c("Reference", "r (m)", "s", "f", "Recall", "Precision", "F1", "Null F1", "Null share",
    "True skilled share", "Corrected recall", "Corrected recall - truth [95% CI]",
    "Corrected F1", "Null recall", "Missed stems matched"),
  lapply(seq_len(nrow(t1)), function(i) with(t1[i, ], c(
    ref, tol, sprintf("%.1f", s), sprintf("%.1f", f), f3(recall), f3(precision), f3(F1),
    f3(null_F1), sprintf("%.0f%%", 100 * null_share), f3(true_share), f3(corr_recall),
    fci(corr_recall_minus_truth, corr_recall_minus_truth_lower, corr_recall_minus_truth_upper),
    f3(corr_F1), f3(null_recall), f3(missed_match_rate)))))
tab2 <- md_table(
  c("Comparison", "Reference", "r (m)", "True skill difference", "Observed F1 lead",
    "Corrected F1 lead", "Corrected recall lead", "Oracle F1 lead"),
  lapply(seq_len(nrow(t2)), function(i) with(t2[i, ], c(
    COMPARISONS[[comparison]], ref, tol, sprintf("%+.3f", true_diff),
    fci(obs_F1_lead, obs_F1_lead_lower, obs_F1_lead_upper),
    fci(corr_F1_lead, corr_F1_lead_lower, corr_F1_lead_upper),
    fci(corr_recall_lead, corr_recall_lead_lower, corr_recall_lead_upper),
    sprintf("%+.3f", oracle_F1_lead)))))
tab3 <- md_table(
  c("Trees/ha", "Reference stems", "Baseline null share", "True skill difference",
    "Observed F1 lead", "Corrected F1 lead", "Corrected recall lead", "Oracle F1 lead"),
  lapply(seq_len(nrow(t3)), function(i) with(t3[i, ], c(
    D, n_ref, sprintf("%.0f%%", 100 * null_share), sprintf("%+.3f", true_diff),
    fci(obs_F1_lead, obs_F1_lead_lower, obs_F1_lead_upper),
    fci(corr_F1_lead, corr_F1_lead_lower, corr_F1_lead_upper),
    fci(corr_recall_lead, corr_recall_lead_lower, corr_recall_lead_upper),
    sprintf("%+.3f", oracle_F1_lead)))))
tab4 <- md_table(
  c("Trees/ha", "Reference", "r (m)", "Observed F1", "Null F1", "Corrected recall [95% CI]",
    "Corrected F1 [95% CI]"),
  lapply(seq_len(nrow(t4)), function(i) with(t4[i, ], c(
    D, ref, tol, f3(F1), f3(null_F1), fci(corr_recall, corr_recall_lower, corr_recall_upper),
    fci(corr_F1, corr_F1_lower, corr_F1_upper)))))
PATTERN_LABEL <- c(inhibited = "inhibited", clustered_4m = "clustered 4 m",
                   clustered_8m = "clustered 8 m")
DET_LABEL <- c(baseline = "baseline", skilled = "skilled")
f2 <- function(x) sprintf("%.2f", x)
fs <- function(x) sprintf("%+.3f", x)
pct <- function(x) sprintf("%.0f%%", 100 * x)
tab5 <- md_table(
  c("Pattern", "p", "Trees/ha", "Density held", "Reference stems/ha",
    "Other stems within 2 m", "Other stems within 4 m",
    "Core detections per stem: baseline", "Core detections per stem: skilled",
    "Baseline null share 4 m", "Baseline null share 2 m"),
  lapply(seq_len(nrow(t5)), function(i) with(t5[i, ], c(
    PATTERN_LABEL[[pattern]], sprintf("%.1f", p), D, design, sprintf("%.0f", ref_per_ha),
    f2(nb2), f2(nb4), f2(det_per_ref_baseline), f2(det_per_ref_skilled),
    pct(null_share_baseline_4m), pct(null_share_baseline_2m)))))
tab6 <- md_table(
  c("Pattern", "p", "Trees/ha", "r (m)", "Detector", "Recall", "Null recall",
    "True skilled share", "Corrected recall - truth [95% CI]", "Missed stems matched",
    "Corrected F1"),
  lapply(seq_len(nrow(t6)), function(i) with(t6[i, ], c(
    PATTERN_LABEL[[pattern]], sprintf("%.1f", p), D, tol, DET_LABEL[[detector]], f3(recall),
    f3(null_recall), f3(true_share),
    fci(corr_recall_minus_truth, corr_recall_minus_truth_lower, corr_recall_minus_truth_upper),
    f3(missed_match_rate), f3(corr_F1)))))
# The leader's core detections per reference stem against its base's.
det_vs_base <- function(pt, D, p, tol, cmp) {
  k <- match(cmp, CMP$comparison)
  pick(per2, pt, D, p, "complete", tol, CMP$leader[k])$det_per_ref /
    pick(per2, pt, D, p, "complete", tol, CMP$base[k])$det_per_ref - 1
}
tab7 <- md_table(
  c("Pattern", "p", "Trees/ha", "r (m)", "Comparison", "Detections vs base",
    "True skill difference", "Observed F1 lead", "Corrected F1 lead", "Corrected recall lead",
    "Oracle F1 lead"),
  lapply(seq_len(nrow(t7)), function(i) with(t7[i, ], c(
    PATTERN_LABEL[[pattern]], sprintf("%.1f", p), D, tol, CMP$short[match(comparison, CMP$comparison)],
    sprintf("%+.0f%%", 100 * det_vs_base(pattern, D, p, tol, comparison)),
    fs(true_diff), fci(obs_F1_lead, obs_F1_lead_lower, obs_F1_lead_upper),
    fci(corr_F1_lead, corr_F1_lead_lower, corr_F1_lead_upper),
    fci(corr_recall_lead, corr_recall_lead_lower, corr_recall_lead_upper),
    # (e): neither detector has an own detection, so neither has an oracle F1.
    if (is.na(oracle_F1_lead)) "n/a" else fs(oracle_F1_lead)))))
z8 <- function(pt, D, p, tol, det, col) {
  r <- pick(t8, pt, D, p, "complete", tol, det)
  fci(r[[col]], r[[paste0(col, "_lower")]], r[[paste0(col, "_upper")]])
}
s8 <- unique(t8[c("pattern", "D", "p", "tol")])
tab8 <- md_table(
  c("Pattern", "p", "Trees/ha", "r (m)",
    unlist(lapply(c("Uniform", "Unmapped only", "Displaced"), function(z)
      paste0(z, ": corrected ", c("recall", "F1"))))),
  lapply(seq_len(nrow(s8)), function(i) with(s8[i, ], c(
    PATTERN_LABEL[[pattern]], sprintf("%.1f", p), D, tol,
    unlist(lapply(names(ZERO_STRUCT), function(z)
      c(z8(pattern, D, p, tol, z, "corr_recall"), z8(pattern, D, p, tol, z, "corr_F1"))))))))
arrow <- function(a, b) sprintf("%+.3f → %+.3f", a, b)
s9 <- unique(t9[c("pattern", "D", "p", "tol")])
g9 <- function(pt, D, p, tol, cmp) t9[t9$pattern == pt & t9$D == D & t9$p == p & t9$tol == tol &
                                      t9$comparison == cmp, ]
arrow_ci <- function(x) sprintf("%s [%+.3f, %+.3f]", arrow(x$corr_F1_lead, x$corr_F1_lead_half),
                                x$corr_F1_lead_lower_half, x$corr_F1_lead_upper_half)
tab9 <- md_table(
  c("Pattern", "p", "Trees/ha", "r (m)", "(b) observed F1 lead", "(b) corrected F1 lead [half: 95% CI]",
    "(b) corrected recall lead", "(a) corrected F1 lead [half: 95% CI]",
    "(c) corrected F1 lead", "(d) 0.5 corrected F1 lead [half: 95% CI]",
    "(d) 0.8 corrected F1 lead [half: 95% CI]", "Baseline corrected recall - truth"),
  lapply(seq_len(nrow(s9)), function(i) with(s9[i, ], {
    b <- g9(pattern, D, p, tol, "b_more_skill")
    a <- g9(pattern, D, p, tol, "a_more_skill_more_commission")
    cc <- g9(pattern, D, p, tol, "c_more_commission")
    c(PATTERN_LABEL[[pattern]], sprintf("%.1f", p), D, tol,
      arrow(b$obs_F1_lead, b$obs_F1_lead_half), arrow_ci(b),
      arrow(b$corr_recall_lead, b$corr_recall_lead_half), arrow_ci(a),
      arrow(cc$corr_F1_lead, cc$corr_F1_lead_half),
      arrow_ci(g9(pattern, D, p, tol, "d_split_crowns_050")),
      arrow_ci(g9(pattern, D, p, tol, "d_split_crowns_080")),
      arrow(b$baseline_bias, b$baseline_bias_half))
  })))
t_end <- Sys.time()
md <- c("# Chance-correction simulation tables", "",
        sprintf("Generated by simulate_chance_correction.R: N = %d plots per density, K = %d shifts, SEED = %d, %d bootstrap resamples (seed %d).",
                N, K, SEED, MT_N_BOOT, MT_SEED), "",
        "## Table 1: single detectors (240 trees/ha)", "", tab1, "",
        "## Table 2: paired leads over the baseline (s 0.45, f 0.45; 240 trees/ha)", "", tab2, "",
        "## Table 3: lead (a) over the baseline by tree density (complete reference, 4 m)", "", tab3, "",
        "## Table 4: detector without skill (s 0, f 1)", "", tab4, "",
        "## Table 5: stand structure and reference completeness, the settings", "", tab5, "",
        "## Table 6: baseline (s 0.45, f 0.45) and skilled (s 0.8, f 0.3) detectors by setting (complete reference)",
        "", tab6, "",
        paste("## Table 7: paired leads by setting (complete reference; over the baseline:",
              "(a) s 0.60 f 0.70, (b) s 0.55 f 0.45, (c) s 0.45 f 1.0, (d) the baseline plus",
              "split crowns at rate 0.5 and 0.8; (e) the displaced detector over the uniform",
              "detector without skill)"), "", tab7, "",
        "## Table 8: detectors without skill on the reference by setting (complete reference)", "",
        tab8, "",
        "## Table 9: leads on the complete reference and on the half reference (complete → half)", "",
        tab9, "")
writeLines(md, file.path(OUT, "chance_simulation_tables.md"))
st2 <- settings2
st2$plots <- vapply(seq_len(nrow(st2)), function(i) length(unique(cells2$plot[
  cells2$pattern == st2$pattern[i] & cells2$D == st2$D[i] & cells2$p == st2$p[i] &
  cells2$ref == st2$ref[i] & cells2$tol == st2$tol[i]])), 1L)
writeLines(c(
  sprintf("N=%d K=%d SEED=%d MIN_SHIFT=%g", N, K, SEED, MIN_SHIFT),
  sprintf("bootstrap: %d resamples, seed %d", MT_N_BOOT, MT_SEED),
  "plot seed: cs_seed(seed_for(\"chance_sim\", plot, \"plot\"), SEED); shift k: cs_seed(seed_for(\"chance_sim\", plot, \"null\"), SEED, k)",
  sprintf("pattern: hard core %.1f m, simulated half-width %g m, core half-width %g m", CS_R_MIN, CS_SIM_HALF, CS_PH),
  sprintf("heights: lognormal median %g m, sdlog %g, clamped %g-%g m; sigma %.1f m, sigma_z %.1f m",
          CS_H_MEDIAN, CS_H_SDLOG, CS_H_RANGE[1], CS_H_RANGE[2], CS_SIGMA, CS_SIGMA_Z),
  sprintf("plots with reference stems per setting: %s", paste(sprintf("D%d/%s/%gm=%d", settings$D, settings$ref,
          settings$tol, vapply(seq_len(nrow(settings)), function(i) length(unique(cells$plot[
            cells$D == settings$D[i] & cells$ref == settings$ref[i] & cells$tol == settings$tol[i]])), 1L)),
          collapse = " ")),
  sprintf(paste("structure scenario: patterns %s; mapped share p and trees/ha %s; displaced detector",
                "%g-%g m; split crowns %g-%g m"),
          paste(vapply(names(CS_PATTERNS), function(k) {
            pt <- CS_PATTERNS[[k]]
            if (pt$type == "inhibited") sprintf("%s (hard core %.1f m)", k, CS_R_MIN)
            else sprintf("%s (Matern cluster, radius %g m, mean %g trees per cluster)", k, pt$R, pt$mu)
          }, ""), collapse = ", "),
          paste(vapply(names(STRUCT_P), function(D) sprintf("D%s: p %s", D,
                                                             paste(STRUCT_P[[D]], collapse = "/")), ""),
                collapse = ", "),
          CS_RING[1], CS_RING[2], CS_SPLIT[1], CS_SPLIT[2]),
  sprintf("structure detectors: %s", paste(sprintf("%s (s %g, f %g, %s%s)", DET_STRUCT$detector,
                                                   DET_STRUCT$s, DET_STRUCT$f, DET_STRUCT$mode,
                                                   ifelse(DET_STRUCT$mode == "split",
                                                          sprintf(", rate %g", DET_STRUCT$rate), "")),
                                           collapse = ", ")),
  sprintf("comparisons (leader - base): %s", paste(sprintf("%s = %s - %s%s", CMP$comparison, CMP$leader,
                                                            CMP$base, ifelse(CMP$half, "",
                                                                             " (complete references only)")),
                                                    collapse = ", ")),
  sprintf("structure plots with reference stems per setting: %s",
          paste(sprintf("%s/D%d/p%g/%s/%gm=%d", st2$pattern, st2$D, st2$p, st2$ref, st2$tol,
                        st2$plots), collapse = " ")),
  check_line,
  R.version.string), file.path(OUT, "chance_simulation_settings.txt"))
cat(sprintf("wrote %s (scoring %.1f min, structure scenario %.1f min, total %.1f min)\n",
            file.path(OUT, "chance_simulation_tables.md"),
            as.numeric(t_sim - t_start, units = "mins"), as.numeric(t_sim2 - t_sim, units = "mins"),
            as.numeric(t_end - t_start, units = "mins")))
