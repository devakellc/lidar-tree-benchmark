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

# The paper's nominal-box chance-agreement null on subsets of plots (post
# hoc). No shifts are repeated: the per-cell observed ("baseline") and null
# mean counts of paper_sensitivity.R MODE=null (sensitivity/null_cells.csv at
# 4 m, null_tol2_cells.csv at 2 m) are pooled by summed counts on each subset,
# with the master tables' plot resamples drawn on the subset's plots
# (mt_plot_weights(..., 1000, 20261002)); corrected F1 = (F1 - null F1) /
# (1 - null F1) per estimate and draw; leads are each arm minus CHM-VWF,
# paired. Subsets: all plots (which must reproduce the paper's null_pooled,
# null_delta and null_leads rows exactly; the script stops otherwise), tower
# plots, distributed plots, and every plot except EXCLUDE (by default the
# three SOAP plots inside the 2020 Creek Fire perimeter whose references were
# measured only in 2019). Also the reference geometry of the tower plots: the
# share of reference stems in the two fullest 20 m quadrants of each 40 m core,
# and the cores' share of the nominal area.
#   Rscript scripts/paper_null_subsets.R [EXCLUDE=SOAP_002,SOAP_008,SOAP_013]
#     [TOLS=4,2] [RUNG=native] [SITES=SJER,SOAP,TEAK,WREF,ABBY] [POP=adopted]
#     [FROZEN_ROOT=...] [IN=$CLAUDE_JOB_DIR/sensitivity]
#     [OUT=$CLAUDE_JOB_DIR/sensitivity/null_subsets]
# Writes OUT/null_subsets_{pooled,leads,plots}.csv, null_subsets_checks.txt
# and null_subsets_tables.md.
t_start <- Sys.time()
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d <- .job_dir()
SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
EXCLUDE <- split_arg(A$EXCLUDE, "SOAP_002,SOAP_008,SOAP_013")
TOLS <- as.numeric(split_arg(A$TOLS, "4,2"))
RUNG <- if (is.null(A$RUNG)) "native" else A$RUNG
IN <- if (is.null(A$IN)) file.path(d, "sensitivity") else A$IN
OUT <- if (is.null(A$OUT)) file.path(d, "sensitivity", "null_subsets") else A$OUT
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
outf <- function(what) file.path(OUT, paste0("null_subsets_", what))
log_lines <- character()
say <- function(...) { x <- sprintf(...); cat(x, "\n"); log_lines <<- c(log_lines, x) }
EPS <- 1e-9

## ---- the population's plots and core reference stems ---------------------------------
plots <- list(); stems <- list()
for (site in SITES) {
  nd <- file.path(d, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  fz <- frozen_scope(d, site, A, gt)
  for (pid in intersect(fz$plots, pc$plotID)) {
    ci <- pc[pc$plotID == pid, ][1, ]
    ph <- plot_half(ci$plotType)
    s <- fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - ci$easting) <= ph &
                 abs(fz$gt$N - ci$northing) <= ph, , drop = FALSE]
    if (!nrow(s)) next                                 # paper_sensitivity.R skips such plots
    plots[[length(plots) + 1]] <- data.frame(site = site, plot = pid, plotType = ci$plotType,
                                             ph = ph, stems = nrow(s), stringsAsFactors = FALSE)
    stems[[length(stems) + 1]] <- data.frame(site = site, plot = pid, plotType = ci$plotType,
                                             dx = s$E - ci$easting, dy = s$N - ci$northing,
                                             meas_year = s$meas_year, stringsAsFactors = FALSE)
  }
}
plots <- do.call(rbind, plots); stems <- do.call(rbind, stems)
plots$key <- paste(plots$site, plots$plot, sep = "::")
say("Population %s: %d plots (%d tower, %d distributed), %d core reference stems",
    if (is.null(A$POP)) "adopted" else A$POP, nrow(plots), sum(plots$plotType == "tower"),
    sum(plots$plotType == "distributed"), sum(plots$stems))

## ---- reference geometry ---------------------------------------------------------------------
tw <- stems[stems$plotType == "tower", ]
quad <- do.call(rbind, lapply(split(tw, tw$plot), function(z)
  cbind(z[1, c("site", "plot")], ns_quadrants(z$dx, z$dy))))
quad$top2_share <- quad$top2_stems / quad$stems
plots <- merge(plots, quad[, c("plot", "quadrants_with_stems", "top2_stems", "top2_share")],
               by = "plot", all.x = TRUE)
plots <- plots[order(plots$site, plots$plot), ]
area <- tapply((2 * plots$ph)^2, plots$plotType, sum) / 1e4
say("Tower plots: %d of %d stems (%.1f%%) lie in the two fullest 20 m quadrants of the 40 m core; %d of %d plots hold 95%% or more there (median plot %.3f); quadrants holding stems: %s",
    sum(quad$top2_stems), sum(quad$stems), 100 * sum(quad$top2_stems) / sum(quad$stems),
    sum(quad$top2_share >= 0.95), nrow(quad), stats::median(quad$top2_share),
    paste(sprintf("%d in %d plots", as.integer(names(table(quad$quadrants_with_stems))),
                  as.vector(table(quad$quadrants_with_stems))), collapse = ", "))
say("Nominal core area: tower %.2f ha of %.2f ha (%.1f%%); distributed %.2f ha",
    area[["tower"]], sum(area), 100 * area[["tower"]] / sum(area), area[["distributed"]])
fire <- stems[stems$plot %in% EXCLUDE, ]
say("Excluded plots %s: %d core stems, measured in %s",
    paste(EXCLUDE, collapse = ", "), nrow(fire),
    paste(sprintf("%s (%d)", names(table(fire$meas_year)), as.vector(table(fire$meas_year))), collapse = ", "))
write.csv(plots[, setdiff(names(plots), "key")], outf("plots.csv"), row.names = FALSE)

## ---- pooling on the subsets -----------------------------------------------------------------
# Scopes pooled per subset (all plots: every scope, as the paper's null files).
EXCL_SITES <- unique(sub("_.*", "", EXCLUDE))
SUBSETS <- list(all = list(kind = "all", scopes = NULL),
                tower = list(kind = "tower", scopes = c("five sites", names(MT_REGIONS))),
                distributed = list(kind = "distributed", scopes = c("five sites", names(MT_REGIONS))),
                exclude = list(kind = "exclude", scopes = c("five sites", names(MT_REGIONS), EXCL_SITES)))
scopes_for <- function(sites, keep = NULL) {
  reg <- lapply(MT_REGIONS, intersect, sites)
  s <- c(list(`five sites` = sites), reg[lengths(reg) > 0], setNames(as.list(sites), sites))
  if (is.null(keep)) s else s[names(s) %in% keep]
}
rd <- function(f) read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
est_rows <- list(); lead_rows <- list(); ok_all <- TRUE
for (tol in TOLS) {
  pre <- paste0("null", cn_suffix(tol))
  f <- file.path(IN, paste0(pre, "_cells.csv"))
  if (!file.exists(f)) stop("The paper's null cells are missing: ", f)
  cells <- rd(f)
  cells <- cells[cells$rung == RUNG & cells$site %in% SITES, , drop = FALSE]
  cells$variant[cells$variant == "baseline"] <- "observed"
  key <- paste(cells$site, cells$plot, sep = "::")
  if (!setequal(unique(key), plots$key))
    stop(sprintf("%s holds %d plots at rung %s, the population %d", basename(f), length(unique(key)), RUNG, nrow(plots)))
  nref <- unique(cells[cells$variant == "observed", c("site", "plot", "n_ref")])
  if (anyDuplicated(nref[c("site", "plot")]) ||
      any(nref$n_ref != plots$stems[match(paste(nref$site, nref$plot, sep = "::"), plots$key)]))
    stop("Observed n_ref in ", basename(f), " differs from the population's core stems")
  say("%g m: %s, rung %s: %d cells of %d arms on %d plots; n_ref equals the core stems of every plot",
      tol, basename(f), RUNG, sum(cells$variant == "observed"), length(unique(cells$detector)),
      length(unique(key)))
  for (sb in names(SUBSETS)) {
    keys <- ns_subset_keys(plots, SUBSETS[[sb]]$kind, EXCLUDE)
    x <- cells[key %in% keys, , drop = FALSE]
    W <- mt_plot_weights(x$site, x$plot, MT_N_BOOT, MT_SEED)
    p <- cn_pool(x, W, scopes_for(intersect(SITES, unique(x$site)), SUBSETS[[sb]]$scopes))
    est_rows[[length(est_rows) + 1]] <- cbind(tol = tol, subset = sb, p$est)
    lead_rows[[length(lead_rows) + 1]] <- cbind(tol = tol, subset = sb, p$leads)
    if (sb != "all") next
    # Hard check: all plots must reproduce the paper's pooled, corrected and lead rows.
    pp <- rd(file.path(IN, paste0(pre, "_pooled.csv"))); pp <- pp[pp$rung == RUNG, ]
    pd <- rd(file.path(IN, paste0(pre, "_delta.csv")))
    pd <- pd[pd$rung == RUNG & pd$stratum == "all" & grepl("_scaled$", pd$metric), ]
    pl <- rd(file.path(IN, paste0(pre, "_leads.csv")))
    pl <- pl[pl$rung == RUNG & pl$stratum == "all" & pl$kind %in% c("observed", "null", "above_null_scaled"), ]
    e <- p$est; e$variant[e$variant == "observed"] <- "baseline"
    ek <- c("scope", "variant", "detector", "rung", "metric")
    c1 <- cn_compare(pp, e[e$variant %in% c("baseline", "null"), ], ek,
                     c("n_plots", "n_ref", "n_det", "TP", "estimate", "lower", "upper"))
    ec <- e[e$variant == "corrected", ]; ec$metric <- paste0(ec$metric, "_scaled")
    c2 <- cn_compare(pd, ec, c("scope", "detector", "rung", "metric"), c("estimate", "lower", "upper"))
    l <- p$leads; l$kind[l$kind == "corrected"] <- "above_null_scaled"
    c3 <- cn_compare(pl[pl$scope != "California minus Washington", ], l,
                     c("scope", "detector", "rung", "metric", "kind"), c("estimate", "lower", "upper"))
    ok <- all(c(c1$missing, c2$missing, c3$missing) == 0) &&
      max(c(c1$max_diff, c2$max_diff, c3$max_diff)) <= EPS
    ok_all <- ok_all && ok
    say("%g m, all plots against %s_pooled/_delta/_leads: %d, %d and %d paper rows (every scope), %d, %d and %d without a row here; largest difference %s -> %s",
        tol, pre, c1$n, c2$n, c3$n, c1$missing, c2$missing, c3$missing,
        cn_diff_text(max(c(c1$max_diff, c2$max_diff, c3$max_diff)), EPS), if (ok) "PASS" else "FAIL")
  }
}
est <- do.call(rbind, est_rows); leads <- do.call(rbind, lead_rows)
write.csv(est, outf("pooled.csv"), row.names = FALSE)
write.csv(leads, outf("leads.csv"), row.names = FALSE)
say("CHECK (all plots reproduce the paper's null): %s", if (ok_all) "PASS" else "FAIL")

## ---- tables ---------------------------------------------------------------------------------
ARM_ORDER <- c("segmentanytree", "forestformer3d", "li2012", "treeisonet", "chm_vwf", "deepforest",
               "multichm", "detectree2", "lmfauto", "ptrees", "ams3d", "sam2point")
E <- function(tol, sb, sc, a, v, m = "F1")
  est[est$tol == tol & est$subset == sb & est$scope == sc & est$detector == a & est$variant == v &
        est$metric == m, , drop = FALSE]
L <- function(tol, sb, sc, a, k = "corrected", m = "F1")
  leads[leads$tol == tol & leads$subset == sb & leads$scope == sc & leads$detector == a &
          leads$kind == k & leads$metric == m, , drop = FALSE]
ci <- function(z, signed = FALSE) if (!nrow(z)) "—" else cn_ci(z$estimate, z$lower, z$upper, signed)
md <- character(); emit <- function(...) md <<- c(md, sprintf(...))
lab <- c(all = "All plots", tower = "Tower plots", distributed = "Distributed plots",
         exclude = sprintf("Without %s", paste(EXCLUDE, collapse = ", ")))
emit("# Nominal-box chance agreement on plot subsets: generated tables")
emit("")
emit("Rung %s. %s", RUNG, paste(log_lines, collapse = " "))
emit("")
MD_SCOPES <- c("five sites", names(MT_REGIONS), EXCL_SITES)
for (tol in TOLS) for (sb in names(SUBSETS)) for (sc in intersect(MD_SCOPES, est$scope[est$tol == tol & est$subset == sb])) {
  arms <- intersect(ARM_ORDER, unique(est$detector[est$tol == tol & est$subset == sb]))
  z0 <- E(tol, sb, sc, arms[1], "observed")
  emit("## %s, %s, %g m (%d plots, %d stems)", lab[[sb]], sc, tol, z0$n_plots, as.integer(z0$n_ref))
  emit("")
  emit("| Arm | Observed F1 | Null F1 | Null share of F1 | Corrected F1 | Corrected lead | Observed lead |")
  emit("| --- | --- | --- | --- | --- | --- | --- |")
  for (a in arms) emit("| %s | %s | %s | %s | %s | %s | %s |", CN_LABELS[[a]],
    cn_num(E(tol, sb, sc, a, "observed")$estimate), cn_num(E(tol, sb, sc, a, "null")$estimate),
    cn_num(E(tol, sb, sc, a, "null_share")$estimate), ci(E(tol, sb, sc, a, "corrected")),
    if (a == CN_BASE) "—" else ci(L(tol, sb, sc, a), TRUE),
    if (a == CN_BASE) "—" else ci(L(tol, sb, sc, a, "observed"), TRUE))
  emit("")
}
writeLines(md, outf("tables.md"))
writeLines(log_lines, outf("checks.txt"))
cat(sprintf("wrote %s in %.1f s\n", file.path(OUT, "null_subsets_*"),
            as.numeric(difftime(Sys.time(), t_start, units = "secs"))))
if (!ok_all) stop("The all-plot pooling does not reproduce the paper's null; see ", outf("checks.txt"))
