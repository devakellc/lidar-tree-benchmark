#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages(library(data.table))
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
source(.find("master_tables_lib.R"))
source(.find("census_null_lib.R"))

# Leads over the unsmoothed baseline inside the censused subplots (post hoc).
# paper_census_null.R scores the censused chance null of the benchmark arms in
# the paper's job directories and, with ARMS=chm_vwf, of CHM-VWF run without
# its sub-8 pulses/m² smoothing in that baseline's own job directories. This
# driver joins the two sets of cells, relabels the unsmoothed CHM-VWF, and pools
# every level with the unsmoothed baseline as the comparator: censused and
# nominal-box observed, null and corrected F1 of every arm (both baselines
# included), and each arm's observed and corrected lead over the unsmoothed
# baseline, with the master tables' paired plot resamples drawn on each level's
# plots, for five sites, California and Washington. It stops unless every run's
# checks passed, the runs used the same shifts (declaration, radius, number of
# shifts, seed offset and minimum shift), the unsmoothed baseline scores the
# same plots with the same reference counts and support as the other arms, and
# the pooled rows of every arm equal those of its own run.
#   Rscript scripts/paper_census_null_unsmoothed.R [TOL=4]
#     [JOBS=$CLAUDE_JOB_DIR,<..>/paper_runs_ql2]
#     [NOSMOOTH=<..>/paper_runs_nosmooth,<..>/paper_runs_nosmooth_ql2]
#     [OUT=$CLAUDE_JOB_DIR/sensitivity/census_null]
# Each directory must hold sensitivity/census_null/census_null[_tol<TOL>]_*.
# Writes OUT/census_null_unsmoothed[_tol<TOL>]_{pooled,leads}.csv,
# _checks.txt and _tables.md.
t_start <- Sys.time()
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d <- .job_dir()
TOL <- as.numeric(if (is.null(A$TOL)) 4 else A$TOL)
JOBS <- split_arg(A$JOBS, paste(d, file.path(dirname(d), "paper_runs_ql2"), sep = ","))
NOSMOOTH <- split_arg(A$NOSMOOTH, paste(file.path(dirname(d), c("paper_runs_nosmooth", "paper_runs_nosmooth_ql2")),
                                        collapse = ","))
OUT <- if (is.null(A$OUT)) file.path(d, "sensitivity", "census_null") else A$OUT
LABEL <- "chm_vwf_nosmooth"
RUN <- paste0("census_null", cn_suffix(TOL))
PREFIX <- paste0("census_null_unsmoothed", cn_suffix(TOL))
outf <- function(what) file.path(OUT, paste0(PREFIX, "_", what))
SCOPES <- c(list(`five sites` = unlist(MT_REGIONS, use.names = FALSE)), MT_REGIONS)
LEVELS <- c("native", "8", "4", "3.2", "2", "1")
EPS <- 1e-12
log_lines <- character()
say <- function(...) { x <- sprintf(...); cat(x, "\n"); log_lines <<- c(log_lines, x) }
rd <- function(f) {
  if (!file.exists(f)) stop("Missing input: ", f)
  read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
}

## ---- inputs and their checks ---------------------------------------------------------------
runs <- lapply(c(setNames(JOBS, rep("smoothed", length(JOBS))), setNames(NOSMOOTH, rep("unsmoothed", length(NOSMOOTH)))),
               function(j) {
  dir <- file.path(j, "sensitivity", "census_null")
  chk <- readLines(file.path(dir, paste0(RUN, "_checks.txt")))
  list(dir = dir, params = cn_run_params(chk), passed = cn_checks_passed(chk),
       cells = rd(file.path(dir, paste0(RUN, "_cells.csv"))),
       pooled = rd(file.path(dir, paste0(RUN, "_pooled.csv"))))
})
names(runs) <- paste(names(runs), basename(normalizePath(c(JOBS, NOSMOOTH))), sep = ": ")
say("Leads over the unsmoothed baseline inside the censused subplots, %g m", TOL)
for (n in names(runs)) {
  p <- runs[[n]]$params
  say("%s: declaration %s, TOL=%g, K=%d, SEED=%d, MIN_SHIFT=%g; checks %s", n, p$declaration, p$tol, p$K,
      p$seed, p$min_shift, if (runs[[n]]$passed) "passed" else "NOT PASSED")
}
if (!all(vapply(runs, `[[`, logical(1), "passed"))) stop("A run's checks did not pass; see its check file")
same <- vapply(runs, function(r) identical(r$params, runs[[1]]$params), logical(1))
if (!all(same)) stop("The runs used different shifts or declarations")
if (runs[[1]]$params$tol != TOL) stop("The runs' radius differs from TOL=", TOL)
K <- runs[[1]]$params$K
ns <- grepl("^unsmoothed", names(runs))
cells <- do.call(rbind, lapply(names(runs), function(n) {
  x <- runs[[n]]$cells
  x <- x[x$variant %in% c("observed", "null"), c("variant", "site", "plot", "rung", "detector",
                                                 "support_id", CN_COUNTS, CN_RECT, "draws")]
  if (grepl("^unsmoothed", n)) {
    if (!all(x$detector == CN_BASE)) stop("An unsmoothed run holds arms other than ", CN_BASE)
    x$detector <- LABEL
  }
  x
}))
if (anyDuplicated(cells[c("variant", "site", "plot", "rung", "detector")]))
  stop("A cell appears in more than one run")
if (any(cells$draws[cells$variant == "null"] != K)) stop("A null cell does not average ", K, " shifts")
lacking <- setdiff(unique(cells$rung), unique(cells$rung[cells$detector == LABEL]))
if (length(lacking)) stop("The unsmoothed baseline lacks rungs: ", paste(lacking, collapse = ", "))
obs <- cells[cells$variant == "observed", ]
ref_bad <- cn_reference_mismatch(obs)
uneq <- cn_unequal_rungs(cells)
say("Reference: %d cells (site, plot, rung) of %d arms; %d with differing reference counts or support; rungs with unequal plots: %s",
    length(unique(paste(obs$site, obs$plot, obs$rung))), length(unique(obs$detector)), length(ref_bad),
    if (length(uneq)) paste(uneq, collapse = ", ") else "none")
if (length(ref_bad) || length(uneq)) stop("The unsmoothed baseline does not share the other arms' plots and references")
say("Shifts: every run used the same declaration, radius, %d shifts, seed offset and minimum shift", K)
# Where the two baselines persisted byte-identical detections, the same shifts
# must give identical null counts.
det_file <- function(jobs, site, plot, rung) {
  f <- vapply(jobs, function(j) frozen_detections_file(file.path(j, "neon", site, "chm_vwf_detections"),
                                                       plot, if (rung == "native") NA else rung), "")
  f[file.exists(f)][1]
}
bn <- cells[cells$variant == "null" & cells$detector %in% c(CN_BASE, LABEL), ]
pairs <- unique(bn[c("site", "plot", "rung")])
same_det <- vapply(seq_len(nrow(pairs)), function(i) {
  a <- det_file(JOBS, pairs$site[i], pairs$plot[i], pairs$rung[i])
  b <- det_file(NOSMOOTH, pairs$site[i], pairs$plot[i], pairs$rung[i])
  !is.na(a) && !is.na(b) && unname(tools::md5sum(a)) == unname(tools::md5sum(b))
}, logical(1))
idn <- pairs[same_det, ]
mk <- function(a) { z <- bn[bn$detector == a, ]; z[match(paste(idn$site, idn$plot, idn$rung),
                                                         paste(z$site, z$plot, z$rung)), c(CN_COUNTS, CN_RECT)] }
dnull <- if (nrow(idn)) max(abs(as.matrix(mk(CN_BASE)) - as.matrix(mk(LABEL)))) else 0
okS <- nrow(idn) > 0 && dnull == 0
say("Shift identity: %d of %d cells have byte-identical detections in both baselines; their null counts differ by at most %g -> %s",
    nrow(idn), nrow(pairs), dnull, if (okS) "PASS" else "FAIL")
if (!okS) stop("The two baselines' nulls were not drawn with the same shifts")

## ---- pooling -------------------------------------------------------------------------------------
levels_run <- intersect(LEVELS, unique(cells$rung))
say("Levels pooled: %s", paste(levels_run, collapse = ", "))
est_rows <- list(); lead_rows <- list()
for (r in levels_run) {
  x <- cells[cells$rung == r, ]
  W <- mt_plot_weights(x$site, x$plot, MT_N_BOOT, MT_SEED)
  for (fam in c("census", "box")) {
    p <- cn_pool(cn_family_rows(x, fam), W, SCOPES, base = LABEL)
    est_rows[[length(est_rows) + 1]] <- cbind(family = fam, p$est)
    lead_rows[[length(lead_rows) + 1]] <- cbind(family = fam, p$leads)
  }
}
est <- do.call(rbind, est_rows); leads <- do.call(rbind, lead_rows)

# Every arm's pooled rows must equal those of its own run (same plots and resamples).
own <- do.call(rbind, lapply(names(runs), function(n) {
  y <- runs[[n]]$pooled
  y <- y[y$plot_set == "all" & y$scope %in% names(SCOPES), ]
  if (grepl("^unsmoothed", n)) y$detector <- LABEL
  y
}))
cmp <- cn_compare(own, est, c("family", "scope", "rung", "detector", "variant", "metric"),
                  c("n_plots", "n_ref", "estimate", "lower", "upper"))
okP <- cmp$missing == 0 && max(cmp$max_diff) <= EPS
say("Own-run parity: %d pooled rows of the runs, %d without a row here; largest difference %s -> %s",
    cmp$n, cmp$missing, cn_diff_text(max(cmp$max_diff), EPS), if (okP) "PASS" else "FAIL")
write.csv(est, outf("pooled.csv"), row.names = FALSE)
write.csv(leads, outf("leads.csv"), row.names = FALSE)

## ---- tables --------------------------------------------------------------------------------------
ARM_ORDER <- c("segmentanytree", "forestformer3d", "li2012", "treeisonet", "chm_vwf", "multichm",
               "lmfauto", "ptrees", "ams3d")
LAB <- CN_LABELS
LAB["chm_vwf"] <- "CHM-VWF, smoothed"; LAB[LABEL] <- "CHM-VWF, unsmoothed"
E <- function(fam, sc, r, a, v, m = "F1") est[est$family == fam & est$scope == sc & est$rung == r &
                                                est$detector == a & est$variant == v & est$metric == m, , drop = FALSE]
L <- function(fam, sc, r, a, k = "corrected", m = "F1") leads[leads$family == fam & leads$scope == sc &
  leads$rung == r & leads$detector == a & leads$kind == k & leads$metric == m, , drop = FALSE]
ci <- function(z, signed = FALSE) if (!nrow(z)) "—" else cn_ci(z$estimate, z$lower, z$upper, signed)
lvl <- function(r) if (r == "native") "native" else r
md <- character(); emit <- function(...) md <<- c(md, sprintf(...))
fam_lab <- c(census = "Censused interior", box = "Nominal box, same plots")
emit("# Leads over the unsmoothed baseline inside censused subplots, %g m", TOL)
emit("")
emit("%s", paste(log_lines, collapse = " "))
emit("")
for (fam in c("census", "box")) {
  emit("## %s: the two baselines, five sites", fam_lab[[fam]])
  emit("")
  emit("| Level | Smoothed: F1 / null F1 / null share | Smoothed: corrected F1 | Unsmoothed: F1 / null F1 / null share | Unsmoothed: corrected F1 | Smoothed minus unsmoothed, corrected F1 |")
  emit("| --- | --- | --- | --- | --- | --- |")
  for (r in levels_run) {
    trip <- function(a) sprintf("%s / %s / %s", cn_num(E(fam, "five sites", r, a, "observed")$estimate),
                                cn_num(E(fam, "five sites", r, a, "null")$estimate),
                                cn_num(E(fam, "five sites", r, a, "null_share")$estimate))
    emit("| %s | %s | %s | %s | %s | %s |", lvl(r), trip(CN_BASE), ci(E(fam, "five sites", r, CN_BASE, "corrected")),
         trip(LABEL), ci(E(fam, "five sites", r, LABEL, "corrected")), ci(L(fam, "five sites", r, CN_BASE), TRUE))
  }
  emit("")
  for (sc in names(SCOPES)) for (k in c("observed", "corrected")) {
    emit("## %s: %s F1 lead over the unsmoothed baseline, %s", fam_lab[[fam]], k, sc)
    emit("")
    emit("| Arm | %s |", paste(vapply(levels_run, lvl, ""), collapse = " | "))
    emit("|%s", strrep(" --- |", 1 + length(levels_run)))
    for (a in intersect(ARM_ORDER, unique(leads$detector)))
      emit("| %s | %s |", LAB[[a]], paste(vapply(levels_run, function(r) ci(L(fam, sc, r, a, k), TRUE), ""),
                                          collapse = " | "))
    emit("")
  }
}
writeLines(md, outf("tables.md"))
writeLines(log_lines, outf("checks.txt"))
cat(sprintf("wrote %s_* in %.1f s\n", file.path(OUT, PREFIX), as.numeric(difftime(Sys.time(), t_start, units = "secs"))))
if (!okP) stop("Pooled rows differ from the runs' own; see ", outf("checks.txt"))
