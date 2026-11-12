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

# Calibration/validation study of the `multichm_gated` tree-top arm
# (multichm_gated_lib.R): lidRplugins::multichm with a cover-switched gate on
# its deeper-layer candidates and an optional exemption of surface peaks from
# the package's distance filter in closed stands.
#
# The gate's thresholds are chosen from a declared grid (mcg_grid(), 87
# configurations; config_id 1 is stock multichm) on CALIBRATION plots only, at
# native density, and reported on the held-out VALIDATION plots of the same
# stratified per-site split the other cal/val studies use (calval_lib.R).
# Provenance that every output repeats: the gate's form and the grid values
# were informed by an exploratory pass over all plots of the five sites
# (calibration and validation alike), so a held-out score tests the threshold
# selection, not the choice of features.
#
# Scores are pooled by summing counts (never averaging rates). Besides
# recall/precision/F1, every cell carries the benchmark's chance-agreement
# null (the mean counts over K random toroidal shifts of its detections, the
# shifts of paper_sensitivity.R MODE=null), and the selection criterion is by
# default the chance-corrected F1, cF1 = (F1 - null F1) / (1 - null F1).
# Intervals are paired plot-bootstrap percentiles (plots resampled within
# site, the master tables' resamples).
#
# Stages, each reading the previous stage's files:
#   candidates  per site x plot x rung of the declared population on the sealed
#               root (the stock arm's loop, native first, with its
#               no-upsampling guard): every multichm candidate with its
#               first-return share, and the clip's canopy cover. A cell where
#               the package itself fails (or whose clip cannot be read or is
#               empty) is skipped, as the stock arm skips it, and recorded with
#               the error; `parity` records whether the stock configuration
#               reproduces the package on that clip. -> OUT/candidates/*.rds
#               (stamped with the root), OUT/candidates.csv (the cell index),
#               OUT/candidates_skipped.csv (the skipped cells; header only when
#               none).
#   score       every cell x every grid configuration (memoised on the accepted
#               detection set), plus, with BASE, the paper's persisted CHM-VWF
#               detections as config "chm_vwf". -> OUT/cells.csv, OUT/grid.csv,
#               OUT/cells.config.json (what the cells were scored with: K, TOL,
#               population, the root's clip manifest, a digest of the grid, the
#               sites and rungs, and whether chm_vwf was scored).
#   analyze     checks against the paper runs, the headline split and
#               selection, held-out contrasts, components, seeds, leave one
#               site out, criterion sensitivity and the all-plots selection.
#               K and TOL come from OUT/cells.config.json; an explicit K= or
#               TOL= must equal the recorded value, and cells scored on another
#               grid, population or root stop the stage.
#               -> OUT/selection.csv, OUT/validation.csv,
#               OUT/declared_config.json, OUT/tables.md.
#
# Usage:
#   Rscript scripts/calval_multichm_gated.R [STAGE=all|candidates|score|analyze]
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [RUNGS=native,8,4,2,1] [POP=adopted]
#     [FROZEN_ROOT=...] [SEED=1] [FRAC=0.5] [SEEDS=1,2,...,10] [CRITERION=cF1]
#     [K=200] [TOL=4] [N_BOOT=1000] [CORES=8] [BASE=<paper job dir>]
#     [OUT=$CLAUDE_JOB_DIR/neon/multichm_gated]
# K is the number of null shifts and must be at least 1: the chance-corrected
# scores (and the default criterion cF1) are undefined without the null.
# BASE is a job directory of the paper runs (read only): its
# neon/<SITE>/multichm_detections and chm_vwf_detections, and its
# sensitivity/null_cells.csv.
suppressMessages({ library(lidR); library(lidRplugins); library(sf)
                   library(data.table); library(parallel) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))          # plot_half, score_plot, ws_factory, plot_lapply
source(.find("model_bench_lib.R"))    # frozen_*, seed_for, assert_detection_contract
source(.find("calval_lib.R"))         # plot_table, assign_split
source(.find("master_tables_lib.R"))  # mt_plot_weights, mt_interval, MT_REGIONS
source(.find("multichm_gated_lib.R"))

CV_RUNGS   <- c("native", "8", "4", "2", "1")
CV_FIVE    <- c("SJER", "SOAP", "TEAK", "WREF", "ABBY")
CV_CLASSES <- c("dominant", "codominant", "intermediate", "suppressed")
CV_A_VWF   <- 0.10
CV_METRICS <- c("cF1", "F1", "cPrecision", "cRecall", "precision", "recall", "det_per_ref")
CV_SIDE    <- c("n_det", "recall", "precision", "F1", "null_F1", "cF1", "cRecall",
                "cPrecision", "det_per_ref")
CV_PROVENANCE <- paste(
  "The gate's form and the grid values were informed by an exploratory pass over all",
  "plots of the five sites (calibration and validation plots alike), so the held-out",
  "scores test the threshold selection, not the choice of features.")
CV_SELECTED_ON <- "selected on the calibration plots at native density"

## ---- arguments ----------------------------------------------------------------------------
# KEY=VALUE positional arguments -> the run's settings.
cv_settings <- function(args = commandArgs(TRUE), d = .job_dir()) {
  a <- strsplit(args, "=")
  # [[ ]] below, never $: `$` would partially match SEED to SEEDS.
  A <- stats::setNames(lapply(a, `[`, 2), vapply(a, `[`, character(1), 1))
  split <- function(x, default) if (is.null(x)) default else strsplit(x, ",")[[1]]
  num <- function(x, default) if (is.null(x)) default else as.numeric(x)
  S <- list(
    A = A, d = d,
    STAGE = if (is.null(A[["STAGE"]])) "all" else A[["STAGE"]],
    SITES = split(A[["SITES"]], CV_FIVE),
    RUNGS = split(A[["RUNGS"]], CV_RUNGS),
    POP = if (is.null(A[["POP"]])) "adopted" else A[["POP"]],
    SEED = as.integer(num(A[["SEED"]], 1)),
    FRAC = num(A[["FRAC"]], 0.5),
    SEEDS = as.integer(split(A[["SEEDS"]], as.character(1:10))),
    CRITERION = if (is.null(A[["CRITERION"]])) "cF1" else A[["CRITERION"]],
    K = as.integer(num(A[["K"]], 200)),
    TOL = num(A[["TOL"]], 4),
    # explicit K= / TOL= must match what the cells were scored with
    K_given = !is.null(A[["K"]]), TOL_given = !is.null(A[["TOL"]]),
    N_BOOT = as.integer(num(A[["N_BOOT"]], MT_N_BOOT)),
    CORES = as.integer(num(A[["CORES"]], 8)),
    BASE = if (is.null(A[["BASE"]]) || !nzchar(A[["BASE"]])) NULL else A[["BASE"]],
    OUT = if (is.null(A[["OUT"]])) file.path(d, "neon", "multichm_gated") else A[["OUT"]])
  S$root <- frozen_root(d, A[["FROZEN_ROOT"]])
  if (!S$STAGE %in% c("all", "candidates", "score", "analyze"))
    stop("STAGE must be all, candidates, score or analyze", call. = FALSE)
  if (!all(S$RUNGS %in% CV_RUNGS))
    stop("RUNGS must be among ", paste(CV_RUNGS, collapse = ","), call. = FALSE)
  if (!S$CRITERION %in% c("cF1", "F1")) stop("CRITERION must be cF1 or F1", call. = FALSE)
  if (anyNA(c(S$SEED, S$FRAC, S$SEEDS, S$K, S$TOL, S$N_BOOT, S$CORES)) ||
      S$FRAC <= 0 || S$FRAC >= 1 || S$K < 1 || S$TOL <= 0 || S$N_BOOT < 1 || S$CORES < 1)
    stop("invalid numeric argument (SEED, FRAC in (0, 1), SEEDS, K >= 1, TOL > 0, ",
         "N_BOOT >= 1, CORES >= 1)", call. = FALSE)
  S
}

cv_ids <- function(r) paste(r$site, r$plot, sep = "::")
cv_rung_value <- function(rl) if (identical(rl, "native")) NA_real_ else as.numeric(rl)

## ---- the declared plots and their core stems ----------------------------------------------
# One job per plot of the declared population with at least one gated stem in
# its core, exactly as the stock arm builds them.
cv_jobs <- function(S) {
  jobs <- list()
  for (site in S$SITES) {
    nd <- file.path(S$d, "neon", site)
    gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
    fz <- frozen_scope(S$d, site, S$A, gt)
    if (!identical(normalizePath(fz$root, mustWork = FALSE),
                   normalizePath(S$root, mustWork = FALSE)))
      stop("frozen root mismatch: ", fz$root, " vs ", S$root, call. = FALSE)
    invisible(neon_validate_inputs(fz$gt, pc))
    for (pid in intersect(fz$plots, pc$plotID)) {
      ci <- pc[pc$plotID == pid, ][1, ]
      ph <- plot_half(ci$plotType)
      stems <- fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - ci$easting) <= ph &
                       abs(fz$gt$N - ci$northing) <= ph, , drop = FALSE]
      if (nrow(stems) < 1) next
      jobs[[length(jobs) + 1L]] <- list(site = site, plot = pid, plotType = ci$plotType,
                                        cx = ci$easting, cy = ci$northing, half = ph,
                                        population = fz$population, stems = stems)
    }
  }
  jobs
}

## ---- stage: candidates --------------------------------------------------------------------
# locate_trees() sf -> the x, y, z detection contract (as the stock arm reads it).
cv_tops_to_det <- function(tt) {
  if (is.null(tt) || !nrow(tt)) return(data.frame(x = numeric(), y = numeric(), z = numeric()))
  co <- sf::st_coordinates(tt)
  z <- if (ncol(co) >= 3) co[, 3] else if (!is.null(tt$Z)) tt$Z else co[, 2] * 0
  data.frame(x = unname(co[, 1]), y = unname(co[, 2]), z = unname(z))
}

# TRUE when two detection sets hold the same points: same count and, after
# sorting by x, y, z, coordinates and heights within `tol`.
cv_same_dets <- function(a, b, tol = 1e-6) {
  if (nrow(a) != nrow(b)) return(FALSE)
  if (!nrow(a)) return(TRUE)
  a <- a[order(a$x, a$y, a$z), c("x", "y", "z")]
  b <- b[order(b$x, b$y, b$z), c("x", "y", "z")]
  isTRUE(max(abs(as.matrix(a) - as.matrix(b))) <= tol)
}

cv_cell_file <- function(site, plot, rung) sprintf("%s__%s__%s.rds", site, plot, rung)

CV_SKIPPED_COLS <- c("site", "plot", "rung", "reason", "error")

# One plot: every rung of the root (native first, the stock arm's no-upsampling
# guard), the configuration-free preparation and the parity with the package.
# Returns the plot's index rows (a data.frame, 0 rows when no rung is usable),
# or NULL when nothing was attempted. Cells skipped as the stock arm skips them
# (an unreadable or empty clip, or lidRplugins::multichm failing on it) are
# attached as attribute "skipped" (CV_SKIPPED_COLS), never dropped silently.
cv_candidates_job <- function(j, root, rungs, cdir, a = CV_A_VWF) {
  out <- list(); skipped <- list(); native_pdens <- NA_real_
  skip <- function(rl, reason, error) skipped[[length(skipped) + 1L]] <<- data.frame(
    site = j$site, plot = j$plot, rung = rl, reason = reason, error = error,
    stringsAsFactors = FALSE)
  for (rung in c(NA, frozen_root_rungs(root))) {
    rl <- if (is.na(rung)) "native" else as.character(rung)
    clip <- frozen_clip(NULL, j$site, j$plot, rung, j$cx, j$cy, j$half, root)
    if (is.null(clip)) next
    if (is.na(rung)) native_pdens <- clip$pdens
    else if (is.na(native_pdens) || rung >= native_pdens) next
    if (!rl %in% rungs) next
    las <- tryCatch(lidR::readLAS(clip$normalized), error = function(e) e)
    if (inherits(las, "error")) {
      skip(rl, "the clip could not be read", conditionMessage(las)); next
    }
    if (lidR::is.empty(las)) { skip(rl, "the clip is empty", ""); next }
    res <- if (clip$frdens >= 8) 0.25 else 0.5
    pkg <- tryCatch(cv_tops_to_det(suppressWarnings(lidR::locate_trees(
      las, lidRplugins::multichm(res = res, ws = ws_factory(a))))), error = function(e) e)
    if (inherits(pkg, "error")) {              # the stock arm skips this cell too
      skip(rl, "lidRplugins::multichm failed", conditionMessage(pkg)); next
    }
    prep <- mcg_prepare(las, res, a)
    stock <- mcg_apply(prep, MCG_STOCK)
    meta <- data.frame(site = j$site, plot = j$plot, plotType = j$plotType, rung = rl,
                       cx = j$cx, cy = j$cy, half = j$half, pdens = clip$pdens,
                       frdens = clip$frdens, res = res, cover = prep$cover,
                       n_cand = nrow(prep$cand),
                       n_layers = if (nrow(prep$cand)) max(prep$cand$layer) else 0L,
                       n_stock = nrow(stock), n_package = nrow(pkg),
                       parity = cv_same_dets(stock, pkg, tol = 1e-9),
                       population = j$population, file = cv_cell_file(j$site, j$plot, rl),
                       stringsAsFactors = FALSE)
    f <- file.path(cdir, meta$file)
    tmp <- paste0(f, ".part")
    saveRDS(list(meta = meta, prep = prep, parity = meta$parity), tmp)
    if (!file.rename(tmp, f)) stop("could not write ", f)
    out[[length(out) + 1L]] <- meta
  }
  sk <- if (length(skipped)) do.call(rbind, skipped)
  if (!length(out) && is.null(sk)) return(NULL)
  idx <- if (length(out)) do.call(rbind, out) else data.frame()
  if (!is.null(sk)) attr(idx, "skipped") <- sk
  idx
}
cv_candidates_worker <- function(j, root, rungs, cdir)
  tryCatch(cv_candidates_job(j, root, rungs, cdir), error = function(e) {
    message("plot ", j$site, "/", j$plot, " failed: ", conditionMessage(e)); e })

# The skipped cells of a candidates run, from the per-plot results (attribute
# "skipped"); a 0-row frame with CV_SKIPPED_COLS when none was skipped.
cv_skipped_cells <- function(res) {
  s <- do.call(rbind, lapply(res, function(r) if (is.data.frame(r)) attr(r, "skipped")))
  if (is.null(s))
    s <- as.data.frame(stats::setNames(rep(list(character()), length(CV_SKIPPED_COLS)),
                                       CV_SKIPPED_COLS), stringsAsFactors = FALSE)
  rownames(s) <- NULL
  s[CV_SKIPPED_COLS]
}

cv_report_skipped <- function(skipped, prefix) {
  cat(sprintf("%s %d candidate cells skipped%s\n", prefix, nrow(skipped),
              if (nrow(skipped)) " (as the stock arm skips them):" else ""))
  for (i in seq_len(nrow(skipped)))
    cat(sprintf("  %s/%s %s: %s%s\n", skipped$site[i], skipped$plot[i], skipped$rung[i],
                skipped$reason[i], if (nzchar(skipped$error[i])) paste0(": ", skipped$error[i])
                else ""))
}

# Writes the per-plot results of the candidates stage: the cell index
# (OUT/candidates.csv) and the skipped cells (OUT/candidates_skipped.csv, header
# only when none), and prints the summary. Returns the index.
cv_write_candidates <- function(res, out, t0 = Sys.time()) {
  skipped <- cv_skipped_cells(res)
  write.csv(skipped, file.path(out, "candidates_skipped.csv"), row.names = FALSE)
  ok <- Filter(function(r) is.data.frame(r) && nrow(r) > 0L, res)
  idx <- if (length(ok)) do.call(rbind, lapply(ok, function(r) {
    attr(r, "skipped") <- NULL; r }))
  if (is.null(idx)) {
    cv_report_skipped(skipped, "[candidates]")
    stop("no candidate cells were produced", call. = FALSE)
  }
  rownames(idx) <- NULL
  write.csv(idx, file.path(out, "candidates.csv"), row.names = FALSE)
  cat(sprintf("[candidates] %d cells in %.1f min, parity TRUE in %d -> %s\n", nrow(idx),
              as.numeric(difftime(Sys.time(), t0, units = "mins")), sum(idx$parity),
              file.path(out, "candidates.csv")))
  cv_report_skipped(skipped, "[candidates]")
  invisible(idx)
}

cv_stage_candidates <- function(S) {
  jobs <- cv_jobs(S)
  cat(sprintf("[candidates] %d plots (%s, population %s), rungs %s\n", length(jobs),
              paste(S$SITES, collapse = ","), S$POP, paste(S$RUNGS, collapse = ",")))
  cdir <- file.path(S$OUT, "candidates")
  frozen_stamp(cdir, S$root)
  t0 <- Sys.time()
  res <- plot_lapply(jobs, cv_candidates_worker, root = S$root, rungs = S$RUNGS, cdir = cdir,
                     mc.cores = S$CORES)
  stop_failed_plots(vapply(jobs, function(j) paste(j$site, j$plot, sep = "/"), ""), res)
  cv_write_candidates(res, S$OUT, t0)
}

# The skipped cells of the requested sites and rungs, as the candidates stage
# recorded them.
cv_read_skipped <- function(S) {
  f <- file.path(S$OUT, "candidates_skipped.csv")
  if (!file.exists(f))
    stop("no record of the skipped candidate cells at ", f, "; re-run STAGE=candidates",
         call. = FALSE)
  s <- read.csv(f, stringsAsFactors = FALSE, colClasses = "character")
  if (!all(CV_SKIPPED_COLS %in% names(s)))
    stop(f, " lacks columns ", paste(setdiff(CV_SKIPPED_COLS, names(s)), collapse = ","),
         "; re-run STAGE=candidates", call. = FALSE)
  s$error[is.na(s$error)] <- ""
  s[s$site %in% S$SITES & s$rung %in% S$RUNGS, CV_SKIPPED_COLS, drop = FALSE]
}

cv_read_index <- function(S) {
  f <- file.path(S$OUT, "candidates.csv")
  if (!file.exists(f)) stop("no candidate index at ", f, "; run STAGE=candidates", call. = FALSE)
  frozen_stamp_check(file.path(S$OUT, "candidates"), S$root)
  idx <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  if (any(idx$population != S$POP))
    stop("the candidates were made for population ", paste(unique(idx$population), collapse = ","),
         ", not ", S$POP, call. = FALSE)
  idx <- idx[idx$site %in% S$SITES & idx$rung %in% S$RUNGS, , drop = FALSE]
  if (!nrow(idx)) stop("the candidate index holds no cell of the requested sites and rungs",
                       call. = FALSE)
  idx
}

## ---- stage: score -------------------------------------------------------------------------
# Every cell of one plot: each grid configuration (scored once per distinct
# detection set) and, with BASE, the paper's CHM-VWF detections.
cv_score_job <- function(j, grid, cdir, K, tol, base) {
  offs <- mcg_null_offsets(j$site, j$plot, j$half, tol = tol, k = K)
  ncls <- vapply(CV_CLASSES, function(k) sum(j$stems$crown_class == k, na.rm = TRUE), numeric(1))
  cfgs <- lapply(seq_len(nrow(grid)), function(g)
    mcg_config(grid$zmin[g], grid$min_share[g], grid$cover_min[g], grid$surface_exempt[g]))
  out <- list()
  for (i in seq_len(nrow(j$cells))) {
    m <- j$cells[i, ]
    cell <- readRDS(file.path(cdir, m$file))
    memo <- new.env(parent = emptyenv())
    score <- function(det) {
      key <- digest::digest(list(det$x, det$y, det$z))
      if (is.null(memo[[key]]))
        memo[[key]] <- mcg_score_cell(j$stems, det, m$cx, m$cy, m$half, offs, tol = tol)
      memo[[key]]
    }
    lead <- function(config, config_id, g) data.frame(
      site = j$site, plot = j$plot, plotType = m$plotType, rung = m$rung, cover = m$cover,
      pdens = m$pdens, frdens = m$frdens, config = config, config_id = config_id,
      zmin = if (is.na(g)) NA_real_ else grid$zmin[g],
      min_share = if (is.na(g)) NA_real_ else grid$min_share[g],
      cover_min = if (is.na(g)) NA_real_ else grid$cover_min[g],
      surface_exempt = if (is.na(g)) NA else grid$surface_exempt[g],
      n_dominant = ncls[["dominant"]], n_codominant = ncls[["codominant"]],
      n_intermediate = ncls[["intermediate"]], n_suppressed = ncls[["suppressed"]],
      stringsAsFactors = FALSE)
    for (g in seq_len(nrow(grid)))
      out[[length(out) + 1L]] <- cbind(lead(grid$label[g], grid$config_id[g], g),
                                       score(mcg_apply(cell$prep, cfgs[[g]])))
    if (!is.null(base)) {
      f <- frozen_detections_file(file.path(base, "neon", j$site, "chm_vwf_detections"),
                                  j$plot, cv_rung_value(m$rung))
      if (file.exists(f)) {
        det <- read.csv(f, stringsAsFactors = FALSE)
        det <- data.frame(x = as.numeric(det$x), y = as.numeric(det$y), z = as.numeric(det$z))
        assert_detection_contract(det)
        out[[length(out) + 1L]] <- cbind(lead("chm_vwf", NA_integer_, NA), score(det))
      }
    }
  }
  if (!length(out)) return(NULL)
  do.call(rbind, out)
}
cv_score_worker <- function(j, grid, cdir, K, tol, base)
  tryCatch(cv_score_job(j, grid, cdir, K, tol, base), error = function(e) {
    message("plot ", j$site, "/", j$plot, " failed: ", conditionMessage(e)); e })

## ---- what the cells were scored with ------------------------------------------------------
CV_CELLS_CONFIG <- "cells.config.json"

# A digest of the calibration grid (ids, values and labels of every row), so
# cells scored on another grid are recognised.
cv_grid_digest <- function(grid = mcg_grid()) {
  g17 <- function(v) sprintf("%.17g", as.numeric(v))
  digest::digest(paste(grid$config_id, g17(grid$zmin), g17(grid$min_share), g17(grid$cover_min),
                       as.logical(grid$surface_exempt), grid$label, sep = ",", collapse = "\n"),
                 algo = "sha256", serialize = FALSE)
}

# The record the score stage writes next to cells.csv (OUT/cells.config.json).
cv_cells_config <- function(S, sites, rungs, chm_vwf)
  list(K = as.integer(S$K), tol = S$TOL, population = S$POP,
       clip_manifest_sha256 = frozen_root_id(S$root), grid_sha256 = cv_grid_digest(),
       sites = I(as.character(sites)), rungs = I(as.character(rungs)),
       chm_vwf = isTRUE(chm_vwf))

cv_write_cells_config <- function(rec, out)
  jsonlite::write_json(rec, file.path(out, CV_CELLS_CONFIG), auto_unbox = TRUE, pretty = TRUE,
                       digits = NA)

# The analyze stage's K and TOL, read from OUT/cells.config.json. Stops when the
# record is missing, when an explicit K= or TOL= differs from it, when the grid
# has changed since the cells were scored, or when they were scored for another
# population or frozen root. Returns S with K and TOL from the record (and the
# record as S$cells_config).
cv_read_cells_config <- function(S) {
  f <- file.path(S$OUT, CV_CELLS_CONFIG)
  if (!file.exists(f))
    stop("no record of how the cells were scored at ", f, "; re-run STAGE=score",
         call. = FALSE)
  r <- jsonlite::read_json(f, simplifyVector = TRUE)
  miss <- setdiff(c("K", "tol", "population", "clip_manifest_sha256", "grid_sha256"), names(r))
  if (length(miss))
    stop(f, " lacks ", paste(miss, collapse = ", "), "; re-run STAGE=score", call. = FALSE)
  K <- as.integer(r$K); tol <- as.numeric(r$tol)
  if (isTRUE(S$K_given) && as.integer(S$K) != K)
    stop(sprintf(paste("the cells in %s were scored with K = %d, not K=%d; omit K= to use",
                       "the recorded value, or re-run STAGE=score with K=%d"),
                 S$OUT, K, as.integer(S$K), as.integer(S$K)), call. = FALSE)
  if (isTRUE(S$TOL_given) && S$TOL != tol)
    stop(sprintf(paste("the cells in %s were scored with TOL = %g, not TOL=%g; omit TOL= to",
                       "use the recorded value, or re-run STAGE=score with TOL=%g"),
                 S$OUT, tol, S$TOL, S$TOL), call. = FALSE)
  if (!identical(r$grid_sha256, cv_grid_digest()))
    stop("the cells in ", S$OUT, " were scored on another calibration grid than the current ",
         "mcg_grid(); re-run STAGE=score", call. = FALSE)
  if (!identical(r$population, S$POP))
    stop("the cells in ", S$OUT, " were scored for population ", r$population, ", not ", S$POP,
         "; re-run STAGE=score", call. = FALSE)
  root_id <- frozen_root_id(S$root)
  if (!identical(r$clip_manifest_sha256, root_id))
    stop("the cells in ", S$OUT, " were scored on the frozen root with clip manifest ",
         r$clip_manifest_sha256, ", not on ", S$root, " (", root_id, "); re-run STAGE=score",
         call. = FALSE)
  S$K <- K; S$TOL <- tol; S$cells_config <- r
  S
}

cv_stage_score <- function(S) {
  idx <- cv_read_index(S)
  # cells.csv and its record are written together; a failed run leaves no record
  unlink(file.path(S$OUT, CV_CELLS_CONFIG))
  cdir <- file.path(S$OUT, "candidates")
  if (!is.null(S$BASE)) for (site in unique(idx$site))
    frozen_stamp_check(file.path(S$BASE, "neon", site, "chm_vwf_detections"), S$root)
  stems <- list()
  for (site in unique(idx$site)) {
    gt <- read.csv(file.path(S$d, "neon", site, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    stems[[site]] <- frozen_scope(S$d, site, S$A, gt)$gt
  }
  keys <- unique(idx[c("site", "plot")])
  jobs <- lapply(seq_len(nrow(keys)), function(i) {
    cells <- idx[idx$site == keys$site[i] & idx$plot == keys$plot[i], , drop = FALSE]
    c1 <- cells[1, ]; gt <- stems[[c1$site]]
    list(site = c1$site, plot = c1$plot, half = c1$half, cells = cells,
         stems = gt[gt$plotID == c1$plot & abs(gt$E - c1$cx) <= c1$half &
                      abs(gt$N - c1$cy) <= c1$half, , drop = FALSE])
  })
  grid <- mcg_grid()
  cat(sprintf("[score] %d cells of %d plots x %d configurations%s, K = %d, TOL = %g\n",
              nrow(idx), length(jobs), nrow(grid), if (is.null(S$BASE)) "" else " + chm_vwf",
              S$K, S$TOL))
  t0 <- Sys.time()
  res <- plot_lapply(jobs, cv_score_worker, grid = grid, cdir = cdir, K = S$K, tol = S$TOL,
                     base = S$BASE, mc.cores = S$CORES)
  stop_failed_plots(vapply(jobs, function(j) paste(j$site, j$plot, sep = "/"), ""), res)
  cells <- as.data.frame(data.table::rbindlist(Filter(Negate(is.null), res)))
  write.csv(cells, file.path(S$OUT, "cells.csv"), row.names = FALSE)
  write.csv(grid, file.path(S$OUT, "grid.csv"), row.names = FALSE)
  n_ref <- sum(cells$config == "chm_vwf")
  cv_write_cells_config(cv_cells_config(S, sites = intersect(S$SITES, unique(idx$site)),
                                        rungs = intersect(S$RUNGS, unique(idx$rung)),
                                        chm_vwf = n_ref > 0), S$OUT)
  cat(sprintf("[score] %d rows in %.1f min -> %s (scored with K = %d, TOL = %g: %s)\n", nrow(cells),
              as.numeric(difftime(Sys.time(), t0, units = "mins")), file.path(S$OUT, "cells.csv"),
              as.integer(S$K), S$TOL, CV_CELLS_CONFIG))
  if (!is.null(S$BASE))
    cat(sprintf("[score] chm_vwf scored in %d of %d cells\n", n_ref, nrow(idx)))
  invisible(cells)
}

cv_read_cells <- function(S) {
  f <- file.path(S$OUT, "cells.csv")
  if (!file.exists(f)) stop("no scored cells at ", f, "; run STAGE=score", call. = FALSE)
  cells <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  cells[cells$site %in% S$SITES & cells$rung %in% S$RUNGS, , drop = FALSE]
}

## ---- checks against the paper runs --------------------------------------------------------
cv_pass <- function(fmt, ...) cat("PASS", sprintf(fmt, ...), "\n")

cv_check_parity <- function(idx) {
  bad <- idx[!idx$parity, , drop = FALSE]
  if (nrow(bad))
    stop(sprintf("parity: the stock configuration differs from lidRplugins::multichm in %d cells (%s)",
                 nrow(bad), paste(head(cv_ids(bad), 10), bad$rung[1:min(10, nrow(bad))],
                                  collapse = ", ")), call. = FALSE)
  cv_pass("parity: the stock configuration reproduces lidRplugins::multichm in all %d cells",
          nrow(idx))
}

# The stock detections of every cell against the stock arm's persisted ones
# (both directions over the plots and rungs of the index).
cv_check_detections <- function(idx, cdir, base, root) {
  bad <- character()
  for (site in unique(idx$site)) {
    ddir <- file.path(base, "neon", site, "multichm_detections")
    frozen_stamp_check(ddir, root)
    s <- idx[idx$site == site, , drop = FALSE]
    held <- sub("\\.csv$", "", list.files(ddir, "\\.csv$"))
    want <- paste(s$plot, s$rung, sep = "__")
    extra <- setdiff(held[sub("__[^_]*$", "", held) %in% s$plot &
                            sub("^.*__", "", held) %in% unique(idx$rung)], want)
    if (length(extra)) bad <- c(bad, paste0(site, "/", extra, " (only in the paper runs)"))
    for (i in seq_len(nrow(s))) {
      f <- frozen_detections_file(ddir, s$plot[i], cv_rung_value(s$rung[i]))
      if (!file.exists(f)) { bad <- c(bad, paste0(site, "/", want[i], " (missing)")); next }
      ref <- read.csv(f, stringsAsFactors = FALSE)
      ref <- data.frame(x = as.numeric(ref$x), y = as.numeric(ref$y), z = as.numeric(ref$z))
      det <- mcg_apply(readRDS(file.path(cdir, s$file[i]))$prep, MCG_STOCK)
      if (!cv_same_dets(det, ref, tol = 1e-6)) bad <- c(bad, paste0(site, "/", want[i]))
    }
  }
  if (length(bad))
    stop(sprintf("stock detections differ from the paper's multichm detections in %d cells: %s",
                 length(bad), paste(head(bad, 10), collapse = ", ")), call. = FALSE)
  cv_pass("stock detections: all %d cells equal the paper's multichm detections (1e-6 m)",
          nrow(idx))
}

# Observed counts and null means of one detector's rows against the paper's
# null cells (variant "baseline" = observed, "null" = the means), cell by cell.
cv_null_compare <- function(cells, null_cells, config, detector, tol = 1e-9) {
  mine <- cells[cells$config == config, c("site", "plot", "rung", "n_ref", "n_det", "TP",
                                          "tp_core", "n_det0", "TP0", "tp_core0")]
  nc <- null_cells[null_cells$detector == detector & null_cells$site %in% unique(cells$site) &
                     null_cells$plot %in% unique(cells$plot) &
                     null_cells$rung %in% unique(cells$rung), , drop = FALSE]
  ob <- nc[nc$variant == "baseline", c("site", "plot", "rung", "n_ref", "n_det", "TP", "tp_core")]
  nu <- nc[nc$variant == "null", c("site", "plot", "rung", "n_det", "TP", "tp_core")]
  names(ob)[4:7] <- paste0("p_", names(ob)[4:7])
  names(nu)[4:6] <- c("p_n_det0", "p_TP0", "p_tp_core0")
  ref <- merge(ob, nu, by = c("site", "plot", "rung"), all = TRUE)
  m <- merge(mine, ref, by = c("site", "plot", "rung"), all = TRUE)
  cols <- c("n_ref", "n_det", "TP", "tp_core", "n_det0", "TP0", "tp_core0")
  if (!nrow(m)) stop("null cells: no ", config, " cell to compare", call. = FALSE)
  dif <- do.call(cbind, lapply(cols, function(k) abs(m[[k]] - m[[paste0("p_", k)]])))
  bad <- !stats::complete.cases(dif) | apply(dif, 1, function(v) any(v > tol))
  list(n = nrow(m), bad = m[bad, , drop = FALSE],
       max_null_diff = suppressWarnings(max(dif[, 5:7], na.rm = TRUE)))
}

cv_check_null <- function(cells, base, config = "stock", detector = "multichm") {
  f <- file.path(base, "sensitivity", "null_cells.csv")
  if (!file.exists(f)) stop("no null cells at ", f, call. = FALSE)
  r <- cv_null_compare(cells, read.csv(f, stringsAsFactors = FALSE,
                                       colClasses = c(rung = "character")), config, detector)
  if (nrow(r$bad))
    stop(sprintf("null cells: %d of %d %s cells differ from the paper's %s null cells: %s",
                 nrow(r$bad), r$n, config, detector,
                 paste(head(paste(r$bad$site, r$bad$plot, r$bad$rung, sep = "/"), 10),
                       collapse = ", ")), call. = FALSE)
  cv_pass("null cells: %s observed and null means equal the paper's %s null cells in all %d cells (max |null diff| %.3g)",
          config, detector, r$n, r$max_null_diff)
}

## ---- analysis helpers (pure data-frame logic) ---------------------------------------------
# Pooling scopes: all requested sites, then each region with some of them.
cv_scopes <- function(sites) {
  s <- stats::setNames(list(sites), if (setequal(sites, CV_FIVE)) "Five sites" else
    paste(sites, collapse = "+"))
  for (nm in names(MT_REGIONS)) {
    k <- intersect(MT_REGIONS[[nm]], sites)
    if (length(k) && !setequal(k, sites)) s[[nm]] <- k
  }
  s
}

# Plots ("site::plot") scored at `rung` by every one of `configs`.
cv_present <- function(cells, rung, configs) {
  r <- cells[cells$rung == rung & cells$config %in% configs, , drop = FALSE]
  Reduce(intersect, lapply(unique(configs), function(k) unique(cv_ids(r[r$config == k, ]))))
}

# One plot row each (site, plot, plotType, crown-class counts) for the split.
cv_plot_rows <- function(cells)
  unique(cells[c("site", "plot", "plotType", "n_dominant", "n_codominant", "n_intermediate",
                 "n_suppressed")])

cv_split <- function(cells, seed, frac) {
  sp <- mcg_split(cv_plot_rows(cells), seed, frac)
  list(calib = cv_ids(sp[sp$split == "calib", ]), valid = cv_ids(sp[sp$split == "valid", ]),
       table = sp)
}

# Grid configuration of a config_id / label, as a list with its label.
cv_config_of <- function(cells, config_id) {
  r <- cells[!is.na(cells$config_id) & cells$config_id == config_id, , drop = FALSE][1, ]
  list(config_id = as.integer(config_id), label = r$config, zmin = r$zmin,
       min_share = r$min_share, cover_min = r$cover_min, surface_exempt = as.logical(r$surface_exempt))
}

# Select on the native rows of `plots` (those present at native) by `criterion`.
# Returns the selected configuration, the plots used and the pooled stock and
# selected scores on them.
cv_select <- function(cells, plots, criterion) {
  nat <- cells[cells$rung == "native" & !is.na(cells$config_id), , drop = FALSE]
  plots <- intersect(unique(plots), unique(cv_ids(nat)))
  if (!length(plots)) stop("no plots to select on at native density", call. = FALSE)
  id <- mcg_select(nat, plots, criterion)
  P <- mcg_pool(nat[cv_ids(nat) %in% plots & nat$config_id %in% c(1L, id), , drop = FALSE],
                "config_id")
  c(cv_config_of(cells, id), list(criterion = criterion, plots = plots,
                                  stock = P[P$config_id == 1L, ], selected = P[P$config_id == id, ]))
}

cv_selection_row <- function(sel, analysis, seed = NA_integer_, held_out_site = NA_character_)
  data.frame(analysis = analysis, seed = seed, held_out_site = held_out_site,
             criterion = sel$criterion, config_id = sel$config_id, config = sel$label,
             zmin = sel$zmin, min_share = sel$min_share, cover_min = sel$cover_min,
             surface_exempt = sel$surface_exempt, n_calib_plots = length(sel$plots),
             calib_cF1_stock = sel$stock$cF1, calib_cF1_selected = sel$selected$cF1,
             calib_F1_stock = sel$stock$F1, calib_F1_selected = sel$selected$F1,
             stringsAsFactors = FALSE)

# Paired contrast config_a - config_b on the plots of `plots` scored by both at
# `rung`: one wide row (both configurations' pooled scores, then the difference
# and interval of each metric). NULL when no plot is left.
cv_contrast_row <- function(cells, plots, rung, config_a, config_b, n_boot, seed, tag) {
  plots <- intersect(unique(plots), cv_present(cells, rung, c(config_a, config_b)))
  if (!length(plots)) return(NULL)
  rows <- cells[cells$rung == rung & cells$config %in% c(config_a, config_b) &
                  cv_ids(cells) %in% plots, , drop = FALSE]
  ct <- mcg_contrast(rows, plots, config_a, config_b, n_boot = n_boot, seed = seed,
                     metrics = CV_METRICS)
  P <- attr(ct, "pooled")
  side <- function(i, p) stats::setNames(as.list(P[i, CV_SIDE]), paste0(p, CV_SIDE))
  d <- unlist(lapply(seq_len(nrow(ct)), function(i)
    stats::setNames(c(ct$difference[i], ct$lower[i], ct$upper[i]),
                    paste0(c("d_", "lo_", "hi_"), ct$metric[i]))))
  cbind(data.frame(tag, rung = rung, config_a = config_a, config_b = config_b,
                   n_plots = length(plots), n_ref = P$n_ref[1], stringsAsFactors = FALSE),
        as.data.frame(side(1, "a_")), as.data.frame(side(2, "b_")), as.data.frame(as.list(d)))
}

cv_tag <- function(analysis, criterion, split, scope, seed = NA_integer_,
                   held_out_site = NA_character_)
  data.frame(analysis = analysis, criterion = criterion, seed = seed,
             held_out_site = held_out_site, split = split, scope = scope,
             stringsAsFactors = FALSE)

# A configuration with the cover made moot where it decides nothing (no share
# gate and no exemption), as the grid stores it.
cv_canonical_label <- function(zmin, min_share, cover_min, surface_exempt) {
  if (min_share == 0 && !surface_exempt) cover_min <- 0
  mcg_config_label(mcg_config(zmin, min_share, cover_min, surface_exempt))
}

# The selected configuration's components: without the exemption, and with
# the gate removed but the exemption kept. Components equal to stock or to the
# selection are dropped. Named labels.
cv_components <- function(sel) {
  own <- cv_canonical_label(sel$zmin, sel$min_share, sel$cover_min, sel$surface_exempt)
  comp <- c(no_exemption = cv_canonical_label(sel$zmin, sel$min_share, sel$cover_min, FALSE),
            exemption_only = cv_canonical_label(0, 0, sel$cover_min, sel$surface_exempt))
  comp <- comp[!comp %in% c("stock", own)]
  comp[!duplicated(comp)]
}

# Every analysis of the study from the scored cells. S carries SITES, RUNGS,
# SEED, FRAC, SEEDS, CRITERION, N_BOOT (and the bootstrap seed MT_SEED).
cv_analyze <- function(cells, S, boot_seed = MT_SEED) {
  sites <- intersect(S$SITES, unique(cells$site))
  rungs <- intersect(S$RUNGS, unique(cells$rung))
  if (!"native" %in% rungs) stop("calibration needs the native rung", call. = FALSE)
  scopes <- cv_scopes(sites)
  all_scope <- names(scopes)[1]
  has_ref <- "chm_vwf" %in% cells$config
  nb <- S$N_BOOT
  con <- function(plots, rung, a, b, tag) cv_contrast_row(cells, plots, rung, a, b, nb, boot_seed, tag)
  sel_rows <- list(); val_rows <- list()
  add_v <- function(x) if (!is.null(x)) val_rows[[length(val_rows) + 1L]] <<- x
  in_scope <- function(ids, sc) ids[sub("::.*", "", ids) %in% scopes[[sc]]]

  ## b. headline split and selection
  sp <- cv_split(cells, S$SEED, S$FRAC)
  sel <- cv_select(cells, sp$calib, S$CRITERION)
  sel_rows[[length(sel_rows) + 1L]] <- cv_selection_row(sel, "headline", S$SEED)
  native_ids <- cv_present(cells, "native", "stock")

  ## c. held-out table (and the in-sample calibration table)
  for (sc in names(scopes)) for (rl in rungs) {
    v <- in_scope(sp$valid, sc); k <- in_scope(sp$calib, sc)
    add_v(con(v, rl, sel$label, "stock", cv_tag("headline", S$CRITERION, "valid", sc, S$SEED)))
    add_v(con(k, rl, sel$label, "stock", cv_tag("headline", S$CRITERION, "calib", sc, S$SEED)))
    if (has_ref) {
      add_v(con(v, rl, sel$label, "chm_vwf", cv_tag("headline", S$CRITERION, "valid", sc, S$SEED)))
      add_v(con(v, rl, "stock", "chm_vwf", cv_tag("headline", S$CRITERION, "valid", sc, S$SEED)))
    }
  }

  ## d. components of the selection, on the validation plots at native density
  comp <- cv_components(sel)
  comp <- comp[comp %in% cells$config]
  for (nm in names(comp))
    add_v(con(sp$valid, "native", comp[[nm]], "stock",
              cv_tag(paste0("component_", nm), S$CRITERION, "valid", all_scope, S$SEED)))

  ## e. seeds
  for (sd in S$SEEDS) {
    s2 <- cv_split(cells, sd, S$FRAC)
    sl <- cv_select(cells, s2$calib, S$CRITERION)
    sel_rows[[length(sel_rows) + 1L]] <- cv_selection_row(sl, "seed", sd)
    add_v(con(s2$valid, "native", sl$label, "stock",
              cv_tag("seed", S$CRITERION, "valid", all_scope, sd)))
  }

  ## f. leave one site out
  if (length(sites) > 1L) for (site in sites) {
    train <- native_ids[sub("::.*", "", native_ids) != site]
    test <- native_ids[sub("::.*", "", native_ids) == site]
    sl <- cv_select(cells, train, S$CRITERION)
    sel_rows[[length(sel_rows) + 1L]] <- cv_selection_row(sl, "leave_one_site_out",
                                                          held_out_site = site)
    add_v(con(test, "native", sl$label, "stock",
              cv_tag("leave_one_site_out", S$CRITERION, "valid", site, held_out_site = site)))
  }

  ## g. criterion sensitivity: b-c at native density over all sites
  other <- setdiff(c("cF1", "F1"), S$CRITERION)
  so <- cv_select(cells, sp$calib, other)
  sel_rows[[length(sel_rows) + 1L]] <- cv_selection_row(so, "criterion", S$SEED)
  add_v(con(sp$valid, "native", so$label, "stock", cv_tag("criterion", other, "valid", all_scope, S$SEED)))
  add_v(con(sp$calib, "native", so$label, "stock", cv_tag("criterion", other, "calib", all_scope, S$SEED)))
  if (has_ref)
    add_v(con(sp$valid, "native", so$label, "chm_vwf",
              cv_tag("criterion", other, "valid", all_scope, S$SEED)))

  ## h. all-plots selection (for the record only)
  sa <- cv_select(cells, native_ids, S$CRITERION)
  sel_rows[[length(sel_rows) + 1L]] <- cv_selection_row(sa, "all_plots")

  selection <- do.call(rbind, sel_rows)
  validation <- do.call(rbind, val_rows)
  rownames(selection) <- NULL; rownames(validation) <- NULL
  list(selection = selection, validation = validation, selected = sel, split = sp,
       n_calib = length(sel$plots), n_valid = length(intersect(sp$valid, native_ids)),
       scopes = scopes, components = comp)
}

cv_declared <- function(res, S, root_id, population) {
  s <- res$selected
  list(config_id = s$config_id, label = s$label, zmin = s$zmin, min_share = s$min_share,
       cover_min = s$cover_min, surface_exempt = s$surface_exempt,
       radius = MCG_RADIUS, half_dz = MCG_HALF_DZ, cover_height = MCG_COVER_HEIGHT,
       criterion = S$CRITERION, seed = S$SEED, frac = S$FRAC, K = S$K, tol = S$TOL,
       n_calibration_plots = res$n_calib, n_validation_plots = res$n_valid,
       clip_manifest_sha256 = root_id, population = population,
       selection = CV_SELECTED_ON, provenance = CV_PROVENANCE)
}

## ---- Markdown tables ----------------------------------------------------------------------
cv_f3 <- function(x) ifelse(is.na(x), "NA", sprintf("%.3f", x))
cv_iv <- function(lo, hi) sprintf("[%s, %s]", cv_f3(lo), cv_f3(hi))

cv_md_contrasts <- function(v) {
  if (is.null(v) || !nrow(v)) return("(no rows)")
  hdr <- c("| Scope | Rung | Split | A | B | Plots | Stems | Detections A / B | F1 A / B | ΔF1 [95% interval] | cF1 A / B | ΔcF1 [95% interval] | ΔcPrecision [95% interval] | ΔcRecall [95% interval] |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
  scope <- ifelse(v$analysis == "seed", sprintf("%s (seed %s)", v$scope, v$seed), v$scope)
  c(hdr, sprintf("| %s | %s | %s | %s | %s | %d | %d | %d / %d | %s / %s | %s %s | %s / %s | %s %s | %s %s | %s %s |",
                 scope, v$rung, ifelse(v$split == "calib", "calib (in-sample)", v$split),
                 v$config_a, v$config_b, as.integer(v$n_plots), as.integer(v$n_ref),
                 as.integer(round(v$a_n_det)), as.integer(round(v$b_n_det)),
                 cv_f3(v$a_F1), cv_f3(v$b_F1), cv_f3(v$d_F1), cv_iv(v$lo_F1, v$hi_F1),
                 cv_f3(v$a_cF1), cv_f3(v$b_cF1), cv_f3(v$d_cF1), cv_iv(v$lo_cF1, v$hi_cF1),
                 cv_f3(v$d_cPrecision), cv_iv(v$lo_cPrecision, v$hi_cPrecision),
                 cv_f3(v$d_cRecall), cv_iv(v$lo_cRecall, v$hi_cRecall)))
}

cv_md_selection <- function(s) {
  hdr <- c("| Analysis | Seed | Held-out site | Criterion | Selected | zmin | min_share | cover_min | surface_exempt | Selection plots | Selection cF1 stock / selected | Selection F1 stock / selected |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|")
  c(hdr, sprintf("| %s | %s | %s | %s | %s (id %d) | %g | %g | %g | %s | %d | %s / %s | %s / %s |",
                 s$analysis, ifelse(is.na(s$seed), "", s$seed),
                 ifelse(is.na(s$held_out_site), "", s$held_out_site), s$criterion, s$config,
                 as.integer(s$config_id), s$zmin, s$min_share, s$cover_min, s$surface_exempt,
                 as.integer(s$n_calib_plots), cv_f3(s$calib_cF1_stock), cv_f3(s$calib_cF1_selected),
                 cv_f3(s$calib_F1_stock), cv_f3(s$calib_F1_selected)))
}

cv_tables_md <- function(res, S, root_id, population) {
  v <- res$validation; s <- res$selection; sel <- res$selected
  pick <- function(an, ...) {
    x <- v[v$analysis %in% an, , drop = FALSE]
    f <- list(...)
    for (k in names(f)) x <- x[x[[k]] %in% f[[k]], , drop = FALSE]
    x
  }
  c("# multichm_gated calibration and validation",
    "",
    "<!-- generated by scripts/calval_multichm_gated.R -->",
    "",
    paste("Provenance:", CV_PROVENANCE),
    "",
    sprintf(paste("Population `%s`; sealed root clip manifest SHA-256 `%s`; split seed %d,",
                  "calibration fraction %g; criterion %s; null K = %d shifts, match radius %g m;",
                  "%d plot-bootstrap draws (plots resampled within site). Δ = A − B; c-metrics",
                  "are corrected for chance: (observed − null) / (1 − null)."),
            population, root_id, S$SEED, S$FRAC, S$CRITERION, S$K, S$TOL, S$N_BOOT),
    "",
    "## Headline selection",
    "",
    sprintf(paste("Selected `%s` (config_id %d: zmin %g, min_share %g, cover_min %g,",
                  "surface_exempt %s), %s (%d calibration plots); %d validation plots at",
                  "native density."),
            sel$label, sel$config_id, sel$zmin, sel$min_share, sel$cover_min, sel$surface_exempt,
            CV_SELECTED_ON, res$n_calib, res$n_valid),
    "",
    cv_md_selection(s[s$analysis == "headline", , drop = FALSE]),
    "",
    "## Held-out: selected versus stock (validation plots)",
    "",
    cv_md_contrasts(pick("headline", split = "valid", config_b = "stock")),
    "",
    "## In-sample: selected versus stock (calibration plots)",
    "",
    cv_md_contrasts(pick("headline", split = "calib")),
    "",
    if ("chm_vwf" %in% v$config_b) c(
      "## Held-out: against CHM-VWF (validation plots)",
      "",
      cv_md_contrasts(pick("headline", split = "valid", config_b = "chm_vwf")),
      ""),
    "## Components of the selection (validation plots, native density)",
    "",
    cv_md_contrasts(v[startsWith(v$analysis, "component_"), , drop = FALSE]),
    "",
    "## Seeds (validation plots, native density)",
    "",
    cv_md_selection(s[s$analysis == "seed", , drop = FALSE]),
    "",
    cv_md_contrasts(pick("seed")),
    "",
    "## Leave one site out (held-out site, native density)",
    "",
    cv_md_selection(s[s$analysis == "leave_one_site_out", , drop = FALSE]),
    "",
    cv_md_contrasts(pick("leave_one_site_out")),
    "",
    "## Criterion sensitivity (native density)",
    "",
    cv_md_selection(s[s$analysis == "criterion", , drop = FALSE]),
    "",
    cv_md_contrasts(pick("criterion")),
    "",
    "## All-plots selection (for the record only; not a held-out result)",
    "",
    cv_md_selection(s[s$analysis == "all_plots", , drop = FALSE]),
    "")
}

## ---- stage: analyze -----------------------------------------------------------------------
cv_print_anchors <- function(cells, sel) {
  nat <- cells[cells$rung == "native", , drop = FALSE]
  show <- function(lab, cfg, sites) {
    p <- mcg_pool(nat[nat$config == cfg & nat$site %in% sites, , drop = FALSE])
    cat(sprintf("  %-28s %-18s plots %3d  n_ref %5g  n_det %5g  TP %5g  tp_core %5g  TP0 %.2f  F1 %.3f  cF1 %.3f\n",
                lab, cfg, p$n_cells, p$n_ref, p$n_det, p$TP, p$tp_core, p$TP0, p$F1, p$cF1))
  }
  cat("pooled at native density, all plots (in-sample for any selected configuration):\n")
  show("all sites", "stock", unique(cells$site))
  for (nm in names(MT_REGIONS)) {
    s <- intersect(MT_REGIONS[[nm]], unique(cells$site))
    if (!length(s)) next
    show(nm, "stock", s)
    show(nm, sel$label, s)
  }
}

cv_stage_analyze <- function(S) {
  S <- cv_read_cells_config(S)            # K and TOL as the cells were scored
  idx <- cv_read_index(S)
  cells <- cv_read_cells(S)
  skipped <- cv_read_skipped(S)
  pop <- unique(idx$population)
  root_id <- frozen_root_id(S$root)
  cat(sprintf("[analyze] cells scored with K = %d, TOL = %g (%s)\n", S$K, S$TOL,
              file.path(S$OUT, CV_CELLS_CONFIG)))
  cv_report_skipped(skipped, "[analyze]")
  ## a. checks
  cv_check_parity(idx)
  if (!is.null(S$BASE)) {
    cv_check_detections(idx, file.path(S$OUT, "candidates"), S$BASE, S$root)
    if (S$K == 200L && S$TOL == 4 && identical(pop, "adopted")) {
      cv_check_null(cells, S$BASE, "stock", "multichm")
      if ("chm_vwf" %in% cells$config) cv_check_null(cells, S$BASE, "chm_vwf", "chm_vwf")
    } else cat("SKIP null cells: the paper's null cells use K = 200, TOL = 4 and population adopted\n")
  }
  stock_cells <- unique(paste(cells$site, cells$plot, cells$rung)[cells$config == "stock"])
  if (!setequal(stock_cells, paste(idx$site, idx$plot, idx$rung)))
    stop("cells.csv and the candidate index hold different cells; re-run STAGE=score",
         call. = FALSE)
  ## b-h
  res <- cv_analyze(cells, S)
  write.csv(res$selection, file.path(S$OUT, "selection.csv"), row.names = FALSE)
  write.csv(res$validation, file.path(S$OUT, "validation.csv"), row.names = FALSE)
  jsonlite::write_json(cv_declared(res, S, root_id, pop), file.path(S$OUT, "declared_config.json"),
                       auto_unbox = TRUE, pretty = TRUE, digits = NA)
  writeLines(cv_tables_md(res, S, root_id, pop), file.path(S$OUT, "tables.md"))
  sel <- res$selected
  cat(sprintf("headline: %s (config_id %d), %s: %d calibration plots, %d validation plots\n",
              sel$label, sel$config_id, CV_SELECTED_ON, res$n_calib, res$n_valid))
  cv_print_anchors(cells, sel)
  cat(sprintf("wrote %s/{selection.csv, validation.csv, declared_config.json, tables.md}\n", S$OUT))
  invisible(res)
}

## ---- main ---------------------------------------------------------------------------------
run_main <- function() {
  S <- cv_settings()
  dir.create(S$OUT, recursive = TRUE, showWarnings = FALSE)
  if (S$STAGE %in% c("all", "candidates")) cv_stage_candidates(S)
  if (S$STAGE %in% c("all", "score")) cv_stage_score(S)
  if (S$STAGE %in% c("all", "analyze")) cv_stage_analyze(S)
  invisible()
}

if (sys.nframe() == 0L) run_main()
