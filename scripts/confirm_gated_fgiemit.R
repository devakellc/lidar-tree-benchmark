#!/usr/bin/env Rscript
.bs_ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (!is.null(.bs_ofile) && length(.bs_ofile) && nzchar(.bs_ofile))
    file.path(dirname(.bs_ofile), "bootstrap.R"),
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])),
                                  "bootstrap.R"),
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_ofile, .bs_file)

# Test C5 of the gated multichm confirmation protocol
# (docs/multichm-gated-confirmation-protocol.md): the five frozen
# configurations of `multichm_gated` (multichm_gated_lib.R, not edited) on the
# ten FGI-EMIT development plots, at native density and at each thinned density
# of the thinning study (docs/fgiemit-thinning-protocol.md), scored against the
# manual tree labels. The evaluation reserve and the historical test plots are
# never read: every path this script builds names a development plot.
#
# Same clouds, support and scoring as the thinning study's CHM-VWF apex scores:
#   cloud      native: ROOT/development_inputs/<plot>/normalized.laz; thinned:
#              SELECT/<plot>/<density>/normalized.laz (the files the CHM-VWF
#              cells ran on; each file's SHA-256 must equal the thinning
#              receipts': the thinned file's own, the native file as the source
#              every variant was cut from).
#   support    the whole plot cylinder: every detection on the plot's cloud
#              against every labelled tree of the plot (no core, no buffer).
#   reference  the dense reference apexes (maximum above-ground point of each
#              true tree; policy max_agl of
#              ROOT/development_comparison/reference_apexes.csv), all 841 at
#              every density.
#   matcher    audit_apex_match (transfer_audit_lib.R): greedy 1:1 within 4 m
#              horizontally and 5 m in height, detections in the order
#              fgiemit_pilot_cell.R gives them (sorted by x, y, z).
# The detector runs as in the calibration study (cv_candidates_job): canopy
# model resolution 0.25 m at 8 or more first returns per m2, else 0.5 m, from
# the thinning study's measured first-return density (thinning_densities.csv);
# window ws_factory(0.10) (3 to 5 m); mcg_prepare once per cloud, then
# mcg_apply per configuration; lidR on one thread. Its detections are the
# multichm local maxima, which are at least 2 m high (hmin 2), the same 2 m
# floor as CHM-VWF's local maxima; no further rule is applied.
#
# Counts per cell follow the NEON cells: TP = labelled trees matched, tp_core =
# detections matched (equal under 1:1 matching on the whole plot), so recall =
# TP / n_ref and precision = tp_core / n_det as in .mcg_rate_list. The dataset
# has no shift null and no NEON crown classes: those columns are NA. CHM-VWF
# rows (config "chm_vwf") carry the thinning study's own counts (its
# metrics.json files), beside the stand features of the same cloud.
#
# Harness proof, before any detector runs: the stored CHM-VWF detections of
# every cell are re-scored with the function that scores the new detections and
# must give the study's counts cell by cell and its published pooled apex F1.
#
# The configurations read return numbers (first-return share, canopy cover,
# crown spacing). Each cloud must carry ReturnNumber and NumberOfReturns with
# 1 <= ReturnNumber <= NumberOfReturns and at least one first return, and be
# height-normalised (ground returns at a median of 0 m, at most 0.1% of returns
# below -1 m). A cloud that fails, or a configuration that stops on it, leaves
# the cell out (skipped.csv), and a density keeps its rows only when every plot
# was scored under every configuration.
#
# Outputs (OUT):
#   cells.csv          one row per plot x density x configuration (the five and
#                      chm_vwf) with the columns of the NEON gated cells, then
#                      target (the NEON first-return target of the density, NA
#                      at native), res (canopy model resolution), closed (cover
#                      >= 0.6), spaced (crown spacing >= 8 m), both at the
#                      declared thresholds, and gated (the share gate applied
#                      under the row's configuration; NA for chm_vwf).
#   features.csv       per plot x density: the cloud's checks, stand features,
#                      candidate counts and the stock configuration's parity
#                      with lidRplugins::multichm.
#   detections.csv     every detection of every configuration.
#   harness_cells.csv, harness_pooled.csv   the harness proof.
#   pooled.csv         counts and rates pooled by density and configuration.
#   skipped.csv        cells left out, with the reason (header only when none).
#   cells.config.json  inputs, their digests, settings and wall time.
#
# Usage:
#   Rscript scripts/confirm_gated_fgiemit.R [STAGE=all|harness] [ROOT=<fgiemit root>]
#     [THIN=<thinning out dir>] [SELECT=<THIN>/select] [PLOTS=<development plots>]
#     [CORES=6] [PARITY=TRUE] [NEON_CELLS=<NEON gated cells.csv, header check>]
#     [OUT=$CLAUDE_JOB_DIR/multichm_gated_confirmation/fgiemit]
# Defaults: ROOT=$CLAUDE_JOB_DIR/external/fgiemit,
# THIN=$CLAUDE_JOB_DIR/fgiemit-thinning. STAGE=harness writes the harness proof
# only. CORES is at most 6. OUT may not lie in a read-only input tree
# (external, fgiemit-*, paper_runs*, multichm_gated_runs*).
suppressMessages({ library(lidR); library(lidRplugins); library(data.table) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))          # ws_factory, plot_lapply
source(.find("model_bench_lib.R"))    # assert_detection_contract
source(.find("transfer_audit_lib.R")) # audit_apex_match, the thinning study's matcher
source(.find("multichm_gated_lib.R")) # mcg_grid, mcg_config, mcg_prepare, mcg_apply

CGF_SITE      <- "FGIEMIT"
CGF_PLOT_TYPE <- "external"
CGF_DEV       <- c("1001", "1005", "1009", "1013", "1019", "1020", "1022", "1024", "1027", "1031")
CGF_PILOT     <- c("1001", "1019", "1027")   # their native cells are the pilot run's
CGF_CONFIGS   <- c("stock", "z5_s0_c0_e0", "z5_s0_c0.6_e1", "z5_s0.75_c0.6_e1_d8",
                   "z5_s0.75_c0.6_e1")
CGF_A         <- 0.10
CGF_MAX_CORES <- 6L
CGF_TOL_XY    <- 4   # audit_apex_match defaults, recorded with the outputs
CGF_TOL_Z     <- 5
# Published pooled CHM-VWF apex F1 (results/fgiemit-thinning-results.md).
CGF_PUBLISHED_F1 <- c(native = 0.513, pulses_9.8 = 0.507, pulses_4.7 = 0.366,
                      pulses_2.5 = 0.354, pulses_1.3 = 0.361, pulses_0.6 = 0.344)
CGF_NEON_COLS <- c("site", "plot", "plotType", "rung", "cover", "top_height", "crown_spacing",
                   "pdens", "frdens", "config", "config_id", "zmin", "min_share", "cover_min",
                   "surface_exempt", "spacing_min", "n_dominant", "n_codominant",
                   "n_intermediate", "n_suppressed", "n_ref", "n_over", "n_under", "n_det",
                   "TP", "tp_core", "tp_over", "tp_under", "n_det0", "TP0", "tp_core0",
                   "tp_over0", "tp_under0")
CGF_COLS <- c(CGF_NEON_COLS, "target", "res", "closed", "spaced", "gated")
# No shift null and no NEON crown classes on this dataset.
CGF_NA_COLS <- c("n_dominant", "n_codominant", "n_intermediate", "n_suppressed", "n_over",
                 "n_under", "tp_over", "tp_under", "n_det0", "TP0", "tp_core0", "tp_over0",
                 "tp_under0")
CGF_SKIPPED_COLS <- c("plot", "rung", "config", "reason")
CGF_READ_ONLY <- "^(external|fgiemit-.*|paper_runs.*|multichm_gated_runs.*)$"

## ---- arguments ----------------------------------------------------------------------------
cgf_settings <- function(args = commandArgs(TRUE), d = .job_dir(create = FALSE)) {
  a <- strsplit(args, "=", fixed = TRUE)
  A <- stats::setNames(lapply(a, function(x) paste(x[-1], collapse = "=")),
                       vapply(a, `[`, character(1), 1))
  arg <- function(k, default) if (is.null(A[[k]]) || !nzchar(A[[k]])) default else A[[k]]
  S <- list(d = d,
            STAGE = arg("STAGE", "all"),
            ROOT = arg("ROOT", file.path(d, "external", "fgiemit")),
            THIN = arg("THIN", file.path(d, "fgiemit-thinning")),
            OUT = arg("OUT", file.path(d, "multichm_gated_confirmation", "fgiemit")),
            NEON_CELLS = arg("NEON_CELLS", file.path(d, "multichm_gated_runs", "neon",
                                                     "multichm_gated", "cells.csv")),
            CORES = suppressWarnings(as.integer(arg("CORES", "6"))),
            PARITY = as.logical(arg("PARITY", "TRUE")),
            PLOTS = strsplit(arg("PLOTS", paste(CGF_DEV, collapse = ",")), ",")[[1]])
  S$SELECT <- arg("SELECT", file.path(S$THIN, "select"))
  if (!S$STAGE %in% c("all", "harness"))
    stop("STAGE must be all or harness", call. = FALSE)
  if (is.na(S$CORES) || S$CORES < 1L || S$CORES > CGF_MAX_CORES)
    stop("CORES must be an integer from 1 to ", CGF_MAX_CORES, call. = FALSE)
  if (is.na(S$PARITY)) stop("PARITY must be TRUE or FALSE", call. = FALSE)
  .cgf_dev(S$PLOTS)
  S
}

# Stops unless every plot is a development plot.
.cgf_dev <- function(plot) {
  bad <- setdiff(plot, CGF_DEV)
  if (length(bad) || !length(plot))
    stop("only the development plots (", paste(CGF_DEV, collapse = ","), "), not: ",
         paste(bad, collapse = ","), call. = FALSE)
  invisible(TRUE)
}

# An absolute path with every symbolic link of its existing part resolved; the
# part that does not exist yet is appended as given.
.cgf_real <- function(p) {
  p <- path.expand(p)
  if (!startsWith(p, "/")) p <- file.path(getwd(), p)
  rest <- character()
  while (!file.exists(p) && dirname(p) != p) { rest <- c(basename(p), rest); p <- dirname(p) }
  do.call(file.path, as.list(c(normalizePath(p, mustWork = TRUE), rest)))
}
.cgf_lexical <- function(p) {
  p <- path.expand(p)
  if (!startsWith(p, "/")) p <- file.path(getwd(), p)
  gsub("/+", "/", gsub("/\\./", "/", p))
}
.cgf_under <- function(x, root) startsWith(paste0(x, "/"), paste0(sub("/+$", "", root), "/"))

# Stops when OUT lies in a read-only tree: a top-level directory of the job
# directory `d` named external, fgiemit-*, paper_runs* or multichm_gated_runs*
# (by the given path and by the resolved one), or inside any of `inputs`
# (resolved: the FGI-EMIT trees are links to another drive).
cgf_check_out <- function(out, d, inputs = character()) {
  first <- function(x, root) if (.cgf_under(x, root))
    strsplit(substring(x, nchar(sub("/+$", "", root)) + 2L), "/", fixed = TRUE)[[1]][1] else ""
  for (pair in list(c(.cgf_lexical(out), .cgf_lexical(d)), c(.cgf_real(out), .cgf_real(d)))) {
    top <- first(pair[1], pair[2])
    if (!is.na(top) && grepl(CGF_READ_ONLY, top))
      stop("OUT must not lie in the read-only input tree ", top, "/: ", out, call. = FALSE)
  }
  for (i in inputs[file.exists(inputs)])
    if (.cgf_under(.cgf_real(out), .cgf_real(i)) || identical(.cgf_real(out), .cgf_real(i)))
      stop("OUT must lie outside the input ", i, call. = FALSE)
  invisible(TRUE)
}

## ---- configurations -----------------------------------------------------------------------
# The five frozen configurations as rows of mcg_grid(), in protocol order.
cgf_configs <- function(grid = mcg_grid()) {
  i <- match(CGF_CONFIGS, grid$label)
  if (anyNA(i)) stop("not in mcg_grid(): ", paste(CGF_CONFIGS[is.na(i)], collapse = ","),
                     call. = FALSE)
  g <- grid[i, c("config_id", "zmin", "min_share", "cover_min", "surface_exempt", "spacing_min",
                 "label")]
  names(g)[names(g) == "label"] <- "config"
  rownames(g) <- NULL
  if (!identical(cgf_cfg(g[g$config == mcg_config_label(MCG_DECLARED), ]), MCG_DECLARED))
    stop("the declared grid row does not rebuild MCG_DECLARED", call. = FALSE)
  g
}
cgf_cfg <- function(row) mcg_config(row$zmin, row$min_share, row$cover_min,
                                    as.logical(row$surface_exempt), row$spacing_min)

# Canopy model resolution from the measured first-return density (the NEON rule).
cgf_res <- function(frdens) {
  if (length(frdens) != 1L || !is.finite(frdens)) stop("no first-return density", call. = FALSE)
  if (frdens >= 8) 0.25 else 0.5
}

## ---- inputs -------------------------------------------------------------------------------
# The thinning study's measured densities, development plots only.
cgf_densities <- function(select, plots = CGF_DEV) {
  f <- file.path(select, "thinning_densities.csv")
  x <- utils::read.csv(f, stringsAsFactors = FALSE,
                       colClasses = c(plot = "character", label = "character"))
  .cgf_dev(unique(x$plot))
  x <- x[x$plot %in% plots, c("plot", "target", "label", "points", "pdens", "frdens",
                              "first_share", "area_m2"), drop = FALSE]
  if (anyDuplicated(paste(x$plot, x$label))) stop("duplicate densities in ", f, call. = FALSE)
  x[order(match(x$label, cgf_label_order(x$label)), x$plot), , drop = FALSE]
}
# native first, then the thinned densities from dense to sparse.
cgf_label_order <- function(labels) {
  thin <- setdiff(unique(labels), "native")
  c(if ("native" %in% labels) "native", thin[order(-as.numeric(sub("^pulses_", "", thin)))])
}

cgf_cloud_file <- function(root, select, plot, label) {
  .cgf_dev(plot)
  if (identical(label, "native")) file.path(root, "development_inputs", plot, "normalized.laz")
  else file.path(select, plot, label, "normalized.laz")
}
# The thinning study's CHM-VWF cell directory.
cgf_chm_dir <- function(root, thin, plot, label) {
  .cgf_dev(plot)
  if (identical(label, "native"))
    file.path(root, if (plot %in% CGF_PILOT) "development_pilot_v3" else "development_detector_run",
              plot, "chm_vwf")
  else file.path(thin, "run", plot, label, "chm_vwf")
}
# The SHA-256 the thinning receipts give the cloud: a thinned variant's own,
# and for the native cloud the source of every variant (they must agree).
cgf_expected_sha <- function(select, plot, label) {
  .cgf_dev(plot)
  rd <- function(f) jsonlite::read_json(f)$files[["normalized.laz"]]
  if (!identical(label, "native")) return(rd(file.path(select, plot, label, "receipt.json"))$sha256)
  v <- unique(vapply(Sys.glob(file.path(select, plot, "*", "receipt.json")),
                     function(f) rd(f)$source_sha256, character(1)))
  if (length(v) != 1L) stop("the receipts of plot ", plot, " name ", length(v),
                            " native clouds", call. = FALSE)
  v
}

# The dense reference apexes (policy max_agl) of the given development plots.
cgf_references <- function(root, plots = CGF_DEV) {
  f <- file.path(root, "development_comparison", "reference_apexes.csv")
  r <- utils::read.csv(f, stringsAsFactors = FALSE, colClasses = c(plot = "character"))
  .cgf_dev(unique(r$plot))
  r <- r[r$policy == "max_agl" & r$plot %in% plots, c("plot", "instance", "x", "y", "z",
                                                       "category"), drop = FALSE]
  if (anyDuplicated(paste(r$plot, r$instance))) stop("duplicate reference apexes", call. = FALSE)
  r
}

## ---- cloud checks -------------------------------------------------------------------------
# Whether a cloud carries usable return numbers.
cgf_return_check <- function(las) {
  d <- las@data
  has <- all(c("ReturnNumber", "NumberOfReturns") %in% names(d))
  why <- if (!has) "no ReturnNumber or NumberOfReturns"
    else if (anyNA(d$ReturnNumber) || anyNA(d$NumberOfReturns)) "missing return numbers"
    else if (any(d$ReturnNumber < 1L)) "a return number below 1"
    else if (any(d$ReturnNumber > d$NumberOfReturns)) "a return number above the number of returns"
    else if (!any(d$ReturnNumber == 1L)) "no first return"
    else ""
  list(ok = !nzchar(why), reason = why,
       first_share = if ("ReturnNumber" %in% names(d) && nrow(d)) mean(d$ReturnNumber == 1L)
                     else NA_real_)
}
# Whether a cloud is height-normalised: ground returns (class 2) at a median of
# 0 m within `tol`, and at most `max_low` of the returns below `low`.
cgf_height_check <- function(las, tol = 0.1, low = -1, max_low = 1e-3) {
  z <- las@data$Z
  g <- if ("Classification" %in% names(las@data)) z[las@data$Classification == 2L] else numeric()
  gm <- if (length(g)) stats::median(g) else NA_real_
  why <- if (!length(z) || any(!is.finite(z))) "missing or non-finite heights"
    else if (!length(g)) "no ground-classified return"
    else if (abs(gm) > tol) sprintf("ground returns at a median height of %.3f m", gm)
    else if (mean(z < low) > max_low) sprintf("%.2f%% of returns below %g m", 100 * mean(z < low), low)
    else ""
  list(ok = !nzchar(why), reason = why, ground_median = gm,
       z_min = if (length(z)) min(z) else NA_real_,
       share_below0 = if (length(z)) mean(z < 0) else NA_real_)
}

## ---- scoring ------------------------------------------------------------------------------
# Counts of one detection set against one plot's reference apexes with the
# thinning study's matcher. Detections carrying `instance` (a stored apex file)
# are taken in instance order, as fgiemit_pilot_cell.R scores them; others are
# sorted by x, y, z, the order fgiemit_pilot_cell.R gives its CHM detections.
cgf_score <- function(det, ref) {
  if (!is.data.frame(det) || !all(c("x", "y", "z") %in% names(det)))
    stop("detections need columns x, y, z", call. = FALSE)
  if (length(unique(ref$plot)) > 1L) stop("references of one plot only", call. = FALSE)
  p <- if ("instance" %in% names(det)) det[order(det$instance), , drop = FALSE]
       else det[order(det$x, det$y, det$z), , drop = FALSE]
  r <- ref[order(ref$instance), , drop = FALSE]
  m <- audit_apex_match(p, r, xy = CGF_TOL_XY, z = CGF_TOL_Z)
  c(n_ref = nrow(r), n_det = nrow(p), TP = m$apex_TP, tp_core = m$apex_TP)
}

# A CHM-VWF cell's counts as the thinning study's summary reads its
# metrics.json (the max_agl detection score).
cgf_metrics_counts <- function(file) {
  m <- jsonlite::fromJSON(file, simplifyVector = FALSE)
  det <- Filter(function(d) identical(d$policy, "max_agl"), m$detection)
  if (length(det) != 1L) stop("no single max_agl detection score in ", file, call. = FALSE)
  d <- det[[1]]
  c(n_ref = d$apex_TP + d$apex_FN, n_det = d$apex_TP + d$apex_FP, TP = d$apex_TP,
    tp_core = d$apex_TP)
}

# One row of cells.csv. meta: plot, rung, target, cover, top_height,
# crown_spacing, pdens, frdens, res; counts: n_ref, n_det, TP, tp_core; cfg: a
# row of cgf_configs(), or NULL for the CHM-VWF row.
cgf_row <- function(meta, counts, cfg = NULL) {
  num <- function(v) if (is.null(v) || !length(v)) NA_real_ else as.numeric(v)
  closed <- num(meta$cover) >= MCG_DECLARED$cover_min
  spaced <- num(meta$crown_spacing) >= MCG_DECLARED$spacing_min
  gated <- NA
  if (!is.null(cfg)) {
    cc <- cgf_cfg(cfg)
    cl <- mcg_closed(num(meta$cover), cc); sp <- mcg_spaced(num(meta$crown_spacing), cc)
    gated <- isTRUE(cl) && isTRUE(sp) && cc$min_share > 0
  }
  pick <- function(k) if (is.null(cfg)) NA_real_ else as.numeric(cfg[[k]])
  out <- data.frame(
    site = CGF_SITE, plot = as.character(meta$plot), plotType = CGF_PLOT_TYPE,
    rung = as.character(meta$rung), cover = num(meta$cover), top_height = num(meta$top_height),
    crown_spacing = num(meta$crown_spacing), pdens = num(meta$pdens), frdens = num(meta$frdens),
    config = if (is.null(cfg)) "chm_vwf" else as.character(cfg$config),
    config_id = if (is.null(cfg)) NA_integer_ else as.integer(cfg$config_id),
    zmin = pick("zmin"), min_share = pick("min_share"), cover_min = pick("cover_min"),
    surface_exempt = if (is.null(cfg)) NA else as.logical(cfg$surface_exempt),
    spacing_min = pick("spacing_min"),
    n_ref = num(counts[["n_ref"]]), n_det = num(counts[["n_det"]]), TP = num(counts[["TP"]]),
    tp_core = num(counts[["tp_core"]]), target = num(meta$target), res = num(meta$res),
    closed = closed, spaced = spaced, gated = gated, stringsAsFactors = FALSE)
  for (k in CGF_NA_COLS) out[[k]] <- NA_real_
  out[CGF_COLS]
}

# Counts pooled by summing over the plots of each density and configuration,
# with recall, precision and F1 from the library's rates (.mcg_rate_list).
cgf_pool <- function(cells, by = c("rung", "config")) {
  P <- mcg_pool(cells, by)
  P[, c(by, "n_cells", "n_ref", "n_det", "TP", "tp_core", "recall", "precision", "F1")]
}

# Densities that every plot and configuration covers. cells: the scored rows;
# plots, configs: what each density must hold (rows of other plots are not
# read). Returns the qualifying labels.
cgf_qualifying <- function(cells, plots, configs) {
  labs <- unique(cells$rung)
  ok <- vapply(labs, function(l) {
    x <- cells[cells$rung == l & cells$plot %in% plots, , drop = FALSE]
    all(vapply(configs, function(cf) setequal(x$plot[x$config == cf], plots) &&
                                      !anyDuplicated(x$plot[x$config == cf]), logical(1)))
  }, logical(1))
  labs[ok]
}

## ---- harness proof ------------------------------------------------------------------------
# Re-scores the stored CHM-VWF detections of every cell with cgf_score and sets
# them beside the study's counts. jobs: data.frame plot, label, chm_dir.
cgf_harness_cells <- function(jobs, refs) {
  rows <- lapply(seq_len(nrow(jobs)), function(i) {
    p <- jobs$plot[i]; l <- jobs$label[i]; dir <- jobs$chm_dir[i]
    study <- cgf_metrics_counts(file.path(dir, "metrics.json"))
    pred <- utils::read.csv(file.path(dir, "prediction_apexes.csv"), stringsAsFactors = FALSE)
    pred <- pred[pred$policy == "max_agl", , drop = FALSE]
    mine <- cgf_score(pred, refs[refs$plot == p, , drop = FALSE])
    data.frame(plot = p, rung = l, study_n_ref = study[["n_ref"]],
               study_n_det = study[["n_det"]], study_TP = study[["TP"]],
               rescored_n_ref = mine[["n_ref"]], rescored_n_det = mine[["n_det"]],
               rescored_TP = mine[["TP"]], same = all(study == mine[names(study)]),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}
# Pooled apex F1 per density from the study's and the re-scored counts, beside
# the published value.
cgf_harness_pooled <- function(h, published = CGF_PUBLISHED_F1) {
  f1 <- function(tp, nr, nd) 2 * tp / (nr + nd)
  out <- do.call(rbind, lapply(unique(h$rung), function(l) {
    x <- h[h$rung == l, , drop = FALSE]
    data.frame(rung = l, plots = nrow(x),
               study_F1 = f1(sum(x$study_TP), sum(x$study_n_ref), sum(x$study_n_det)),
               rescored_F1 = f1(sum(x$rescored_TP), sum(x$rescored_n_ref), sum(x$rescored_n_det)),
               published_F1 = if (l %in% names(published)) published[[l]] else NA_real_,
               stringsAsFactors = FALSE)
  }))
  out$cells_same <- vapply(out$rung, function(l) all(h$same[h$rung == l]), logical(1))
  out$matches_published <- !is.na(out$published_F1) &
    round(out$rescored_F1, 3) == round(out$published_F1, 3) &
    round(out$study_F1, 3) == round(out$published_F1, 3)
  out
}

## ---- the detector on one plot -------------------------------------------------------------
# The stock configuration's detections from lidRplugins::multichm itself, and
# whether two detection sets hold the same points (as cv_candidates_job checks).
.cgf_package_dets <- function(las, res) {
  tt <- suppressWarnings(lidR::locate_trees(las, lidRplugins::multichm(res = res,
                                                                       ws = ws_factory(CGF_A))))
  if (is.null(tt) || !nrow(tt)) return(data.frame(x = numeric(), y = numeric(), z = numeric()))
  co <- sf::st_coordinates(tt)
  z <- if (ncol(co) >= 3) co[, 3] else if (!is.null(tt$Z)) tt$Z else co[, 2] * 0
  data.frame(x = unname(co[, 1]), y = unname(co[, 2]), z = unname(z))
}
.cgf_same_dets <- function(a, b, tol = 1e-9) {
  if (nrow(a) != nrow(b)) return(FALSE)
  if (!nrow(a)) return(TRUE)
  a <- a[order(a$x, a$y, a$z), c("x", "y", "z")]; b <- b[order(b$x, b$y, b$z), c("x", "y", "z")]
  isTRUE(max(abs(as.matrix(a) - as.matrix(b))) <= tol)
}

# Every configuration on one prepared cloud: list(prep, dets) with dets named by
# configuration, or the error of the first configuration that stops.
cgf_detect <- function(las, res, cfgs) {
  prep <- mcg_prepare(las, res, CGF_A)
  dets <- list()
  for (k in seq_len(nrow(cfgs))) {
    d <- tryCatch(mcg_apply(prep, cgf_cfg(cfgs[k, ])), error = function(e) e)
    if (inherits(d, "error"))
      return(structure(list(prep = prep, config = cfgs$config[k], error = conditionMessage(d)),
                       class = "cgf_failed"))
    dets[[cfgs$config[k]]] <- d
  }
  list(prep = prep, dets = dets)
}

# One plot, every density: rows, features, detections and skipped cells.
# job: list(plot, cells = data.frame(label, target, pdens, frdens, file, sha,
# chm_dir), refs).
cgf_plot_job <- function(job, cfgs, parity = TRUE) {
  rows <- list(); feats <- list(); dets <- list(); skipped <- list()
  skip <- function(l, cf, why) skipped[[length(skipped) + 1L]] <<- data.frame(
    plot = job$plot, rung = l, config = cf, reason = why, stringsAsFactors = FALSE)
  for (i in seq_len(nrow(job$cells))) {
    m <- job$cells[i, ]
    sha <- digest::digest(file = m$file, algo = "sha256")
    if (!identical(sha, m$sha))
      stop("plot ", job$plot, " ", m$label, ": the cloud differs from the thinning study's (",
           m$file, ")", call. = FALSE)
    las <- lidR::readLAS(m$file)
    rc <- cgf_return_check(las); hc <- cgf_height_check(las)
    res <- cgf_res(m$frdens)
    f <- data.frame(plot = job$plot, rung = m$label, target = m$target, file = m$file,
                    sha256 = sha, points = lidR::npoints(las), pdens = m$pdens,
                    frdens = m$frdens, res = res, first_share = rc$first_share,
                    returns_ok = rc$ok, returns_reason = rc$reason, height_ok = hc$ok,
                    height_reason = hc$reason, ground_median = hc$ground_median,
                    z_min = hc$z_min, share_below0 = hc$share_below0,
                    stringsAsFactors = FALSE)
    if (!rc$ok || !hc$ok) {
      skip(m$label, "all", paste(c(rc$reason, hc$reason)[nzchar(c(rc$reason, hc$reason))],
                                 collapse = "; "))
      feats[[length(feats) + 1L]] <- f
      next
    }
    run <- cgf_detect(las, res, cfgs)
    prep <- run$prep
    f$cover <- prep$cover; f$top_height <- prep$top_height
    f$crown_spacing <- as.numeric(prep$crown_spacing); f$n_crowns <- prep$n_crowns
    f$crown_area <- prep$crown_area; f$n_cand <- nrow(prep$cand)
    f$n_layers <- if (nrow(prep$cand)) max(prep$cand$layer) else 0L
    f$n_cand_deeper <- sum(prep$cand$layer > 1L)
    if (inherits(run, "cgf_failed")) {
      skip(m$label, run$config, run$error)
      feats[[length(feats) + 1L]] <- f
      next
    }
    f$n_stock <- nrow(run$dets[["stock"]])
    f$min_det_z <- suppressWarnings(min(unlist(lapply(run$dets, `[[`, "z"))))
    if (parity) {
      pkg <- tryCatch(.cgf_package_dets(las, res), error = function(e) e)
      f$n_package <- if (inherits(pkg, "error")) NA_integer_ else nrow(pkg)
      f$parity <- if (inherits(pkg, "error")) NA else .cgf_same_dets(run$dets[["stock"]], pkg)
    } else { f$n_package <- NA_integer_; f$parity <- NA }
    feats[[length(feats) + 1L]] <- f
    meta <- list(plot = job$plot, rung = m$label, target = m$target, cover = prep$cover,
                 top_height = prep$top_height, crown_spacing = prep$crown_spacing,
                 pdens = m$pdens, frdens = m$frdens, res = res)
    for (k in seq_len(nrow(cfgs))) {
      d <- run$dets[[cfgs$config[k]]]
      rows[[length(rows) + 1L]] <- cgf_row(meta, cgf_score(d, job$refs), cfgs[k, ])
      if (nrow(d)) dets[[length(dets) + 1L]] <- data.frame(
        plot = job$plot, rung = m$label, config = cfgs$config[k], x = d$x, y = d$y, z = d$z,
        stringsAsFactors = FALSE)
    }
    mf <- file.path(m$chm_dir, "metrics.json")
    if (file.exists(mf)) rows[[length(rows) + 1L]] <- cgf_row(meta, cgf_metrics_counts(mf))
    else skip(m$label, "chm_vwf", paste("no CHM-VWF metrics at", mf))
    rm(las, run, prep); invisible(gc())
  }
  bind <- function(x) if (length(x)) do.call(rbind, x)
  list(rows = bind(rows), features = if (length(feats)) data.table::rbindlist(feats, fill = TRUE),
       detections = bind(dets), skipped = bind(skipped))
}
cgf_plot_worker <- function(job, cfgs, parity)
  tryCatch(cgf_plot_job(job, cfgs, parity), error = function(e) {
    message("plot ", job$plot, " failed: ", conditionMessage(e)); e })

## ---- main ---------------------------------------------------------------------------------
cgf_write <- function(x, f) utils::write.csv(x, f, row.names = FALSE)

run_main <- function() {
  t0 <- Sys.time()
  options(width = 160)
  S <- cgf_settings()
  cgf_check_out(S$OUT, S$d, c(S$ROOT, S$THIN, S$SELECT, S$NEON_CELLS))
  if (file.exists(S$NEON_CELLS)) {
    h <- names(utils::read.csv(S$NEON_CELLS, nrows = 1L, check.names = FALSE))
    if (!identical(h, CGF_NEON_COLS))
      stop("the NEON gated cells have other columns than this script writes: ", S$NEON_CELLS,
           call. = FALSE)
  }
  dir.create(S$OUT, recursive = TRUE, showWarnings = FALSE)
  set_lidr_threads(1L)
  cfgs <- cgf_configs()
  dens <- cgf_densities(S$SELECT, S$PLOTS)
  refs <- cgf_references(S$ROOT, S$PLOTS)
  labels <- cgf_label_order(dens$label)
  dens$chm_dir <- mapply(cgf_chm_dir, S$ROOT, S$THIN, dens$plot, dens$label, USE.NAMES = FALSE)

  # Harness proof: the stored CHM-VWF detections re-scored by cgf_score.
  h <- cgf_harness_cells(dens[, c("plot", "label", "chm_dir")], refs)
  hp <- cgf_harness_pooled(h)
  hp <- hp[order(match(hp$rung, labels)), ]
  cgf_write(h, file.path(S$OUT, "harness_cells.csv"))
  cgf_write(hp, file.path(S$OUT, "harness_pooled.csv"))
  cat("Harness proof: stored CHM-VWF detections re-scored with cgf_score\n")
  print(data.frame(rung = hp$rung, plots = hp$plots, study = round(hp$study_F1, 4),
                   rescored = round(hp$rescored_F1, 4), published = hp$published_F1,
                   cells_same = hp$cells_same, matches = hp$matches_published), row.names = FALSE)
  if (!all(h$same)) stop("re-scored CHM-VWF counts differ from the study's in ",
                         sum(!h$same), " cells", call. = FALSE)
  if (length(S$PLOTS) == length(CGF_DEV) && !all(hp$matches_published))
    stop("the pooled CHM-VWF apex F1 does not reproduce the published values", call. = FALSE)
  if (S$STAGE == "harness") return(invisible(h))

  # The detector, one job per plot.
  dens$file <- mapply(cgf_cloud_file, S$ROOT, S$SELECT, dens$plot, dens$label, USE.NAMES = FALSE)
  dens$sha <- mapply(cgf_expected_sha, S$SELECT, dens$plot, dens$label, USE.NAMES = FALSE)
  jobs <- lapply(S$PLOTS, function(p) list(
    plot = p, cells = dens[dens$plot == p, c("label", "target", "pdens", "frdens", "file", "sha",
                                             "chm_dir")],
    refs = refs[refs$plot == p, , drop = FALSE]))
  cat(sprintf("[detector] %d plots x %d densities x %d configurations on %d cores\n",
              length(jobs), length(labels), nrow(cfgs), min(S$CORES, length(jobs))))
  t1 <- Sys.time()
  res <- plot_lapply(jobs, cgf_plot_worker, cfgs = cfgs, parity = S$PARITY,
                     mc.cores = min(S$CORES, length(jobs)))
  failed <- S$PLOTS[vapply(res, inherits, logical(1), "error")]
  if (length(failed)) stop("plots failed: ", paste(failed, collapse = ","), call. = FALSE)
  t_det <- as.numeric(difftime(Sys.time(), t1, units = "secs"))

  cells <- do.call(rbind, lapply(res, `[[`, "rows"))
  feats <- data.table::rbindlist(lapply(res, `[[`, "features"), fill = TRUE)
  detections <- do.call(rbind, lapply(res, `[[`, "detections"))
  skipped <- do.call(rbind, lapply(res, `[[`, "skipped"))
  if (is.null(skipped)) skipped <- as.data.frame(
    stats::setNames(rep(list(character()), length(CGF_SKIPPED_COLS)), CGF_SKIPPED_COLS))
  keep <- if (is.null(cells)) character() else
    cgf_qualifying(cells, S$PLOTS, c(cfgs$config, "chm_vwf"))
  for (l in setdiff(labels, keep)) skipped <- rbind(skipped, data.frame(
    plot = "all", rung = l, config = "all",
    reason = "the density is left out: not every plot was scored under every configuration",
    stringsAsFactors = FALSE))
  if (!is.null(cells)) {
    cells <- cells[cells$rung %in% keep, , drop = FALSE]
    cells <- cells[order(match(cells$rung, labels), cells$plot,
                         match(cells$config, c(cfgs$config, "chm_vwf"))), , drop = FALSE]
    rownames(cells) <- NULL
  }
  if (is.null(cells) || !nrow(cells)) stop("no density qualified; see skipped cells", call. = FALSE)
  feats <- as.data.frame(feats)
  feats <- feats[order(match(feats$rung, labels), feats$plot), , drop = FALSE]
  cgf_write(cells, file.path(S$OUT, "cells.csv"))
  cgf_write(feats, file.path(S$OUT, "features.csv"))
  cgf_write(if (is.null(detections)) data.frame(plot = character(), rung = character(),
                                                config = character(), x = numeric(),
                                                y = numeric(), z = numeric()) else detections,
            file.path(S$OUT, "detections.csv"))
  cgf_write(skipped, file.path(S$OUT, "skipped.csv"))
  pooled <- cgf_pool(cells)
  pooled <- pooled[order(match(pooled$rung, labels),
                         match(pooled$config, c(cfgs$config, "chm_vwf"))), , drop = FALSE]
  cgf_write(pooled, file.path(S$OUT, "pooled.csv"))

  sha <- function(f) digest::digest(file = f, algo = "sha256")
  rec <- list(
    test = "C5 (docs/multichm-gated-confirmation-protocol.md)", site = CGF_SITE,
    created = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    inputs = list(root = .cgf_real(S$ROOT), thin = .cgf_real(S$THIN),
                  select = .cgf_real(S$SELECT),
                  reference_apexes_sha256 = sha(file.path(S$ROOT, "development_comparison",
                                                          "reference_apexes.csv")),
                  thinning_densities_sha256 = sha(file.path(S$SELECT, "thinning_densities.csv"))),
    plots = S$PLOTS, densities = labels, densities_written = keep,
    configs = cfgs, a = CGF_A, resolution_rule = "0.25 m at frdens >= 8, else 0.5 m",
    matcher = sprintf("audit_apex_match(xy = %g, z = %g), whole plot, max_agl apexes",
                      CGF_TOL_XY, CGF_TOL_Z),
    lidR = as.character(utils::packageVersion("lidR")),
    lidRplugins = as.character(utils::packageVersion("lidRplugins")),
    library_sha256 = sha(.find("multichm_gated_lib.R")),
    script_sha256 = sha(.find("confirm_gated_fgiemit.R")),
    cores = min(S$CORES, length(jobs)), parity_checked = S$PARITY,
    harness_matches_published = all(hp$matches_published), harness_cells_same = all(h$same),
    detector_seconds = t_det,
    wall_seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  jsonlite::write_json(rec, file.path(S$OUT, "cells.config.json"), auto_unbox = TRUE,
                       pretty = TRUE, digits = NA, na = "null")

  cat(sprintf("\n[detector] %.1f min; parity with lidRplugins::multichm TRUE in %d of %d cells\n",
              t_det / 60, sum(feats$parity %in% TRUE), nrow(feats)))
  if (nrow(skipped)) { cat("Skipped:\n"); print(skipped, row.names = FALSE) }
  cat("\nPooled over the plots (recall = TP / n_ref, precision = tp_core / n_det)\n")
  print(transform(pooled, recall = round(recall, 3), precision = round(precision, 3),
                  F1 = round(F1, 3)), row.names = FALSE)
  cat(sprintf("\nwrote %s/{cells.csv, features.csv, detections.csv, pooled.csv, skipped.csv, ",
              S$OUT), "harness_cells.csv, harness_pooled.csv, cells.config.json} in ",
      sprintf("%.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))), sep = "")
  invisible(cells)
}

if (sys.nframe() == 0L) run_main()
