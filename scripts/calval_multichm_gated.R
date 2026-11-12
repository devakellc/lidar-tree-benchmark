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
# (calibration and validation alike), and the selection criterion was fixed
# after that pass, so a held-out score tests only the selection within the
# grid, not the grid's values or the choice of features.
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
#               (stamped with the root), OUT/candidates.csv (the cell index,
#               with the window coefficient and the feature constants the
#               candidates were made with; later stages stop on other values),
#               OUT/candidates_skipped.csv (the skipped cells; header only when
#               none).
#   score       every cell x every grid configuration (memoised on the accepted
#               detection set), plus, with BASE, the paper's persisted CHM-VWF
#               detections as config "chm_vwf". -> OUT/cells.csv, OUT/grid.csv,
#               OUT/cells.config.json (what the cells were scored with: K, TOL,
#               population, the root's clip manifest, a digest of the grid, the
#               sites and rungs, and whether chm_vwf was scored).
#   analyze     checks against the paper runs, the headline split and
#               selection, held-out contrasts (by scope and by site), the
#               difference between the regions, components and the selection
#               minus each reduction of it (without its floor, its share gate
#               or its exemption, with the gate and the exemption applied in
#               every stand (the cover switch), and its floor alone), at native
#               density on the validation and the calibration plots and down
#               the ladder on the validation plots, the whole grid against
#               stock, seeds (with how each split's calibration ranking
#               carries over), leave one site out, criterion sensitivity, the
#               all-plots selection and the headline selection's in-sample
#               contrasts on all plots, and, when both censused score files
#               exist, the arm's persisted detections against the paper's
#               multichm inside the censused subplots.
#               K and TOL come from OUT/cells.config.json; an explicit K= or
#               TOL= must equal the recorded value, and cells scored on another
#               grid, population or root stop the stage.
#               -> OUT/selection.csv, OUT/validation.csv,
#               OUT/grid_contrasts.csv (every grid configuration against stock,
#               validation and calibration plots), OUT/region_differences.csv
#               (only when both regions are in the study),
#               OUT/census_scores.csv and OUT/census_contrasts.csv (only with
#               the censused scores), OUT/seed_grid.csv (one row per split: the
#               correlation across the grid of the calibration and validation
#               changes, how many configurations gain on the validation plots,
#               and the rank of the split's own selection),
#               OUT/declared_config.json, OUT/tables.md.
#
# Usage:
#   Rscript scripts/calval_multichm_gated.R [STAGE=all|candidates|score|analyze]
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [RUNGS=native,8,4,2,1] [POP=adopted]
#     [FROZEN_ROOT=...] [SEED=1] [FRAC=0.5] [SEEDS=1,2,...,200] [CRITERION=cF1]
#     [K=200] [TOL=4] [N_BOOT=1000] [CORES=8] [BASE=<paper job dir>]
#     [CENSUS=$CLAUDE_JOB_DIR/census_support_scores/nearest_ladder/
#     census_support_scores.csv] [BASE_CENSUS=the same under BASE]
#     [OUT=$CLAUDE_JOB_DIR/neon/multichm_gated]
# K is the number of null shifts and must be at least 1: the chance-corrected
# scores (and the default criterion cF1) are undefined without the null.
# BASE is a job directory of the paper runs (read only): its
# neon/<SITE>/multichm_detections and chm_vwf_detections, and its
# sensitivity/null_cells.csv.
# CENSUS holds the arm's censused-subplot scores (score_census_support.R run on
# the arm's persisted detections, ARMS=multichm_gated), BASE_CENSUS the paper
# runs' (with multichm); without BASE there is no default for BASE_CENSUS, and
# the censused contrast is skipped when either file is missing. Both files must
# carry the support identity (support_id, support_policy,
# reference_population), and at native density their nominal-box detection
# counts (rect_n_det) must equal the study's cells: the arm's file the
# selection's, BASE_CENSUS stock's. The stage stops otherwise.
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
  "plots of the five sites (calibration and validation plots alike), and the selection",
  "criterion was fixed after that pass, so the held-out scores test only the selection",
  "within the grid, not the grid's values or the choice of features.")
CV_SELECTED_ON <- "selected on the calibration plots at native density"
# The regional contrast of the headline gain: set 1 minus set 2 (MT_REGIONS names).
CV_REGION_DIFFERENCE <- c("Washington", "California")

## ---- arguments ----------------------------------------------------------------------------
# Where score_census_support.R leaves the censused scores of a job directory
# (the nearest-event declaration's ladder).
cv_census_csv <- function(dir)
  file.path(dir, "census_support_scores", "nearest_ladder", "census_support_scores.csv")

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
    SEEDS = as.integer(split(A[["SEEDS"]], as.character(1:200))),
    CRITERION = if (is.null(A[["CRITERION"]])) "cF1" else A[["CRITERION"]],
    K = as.integer(num(A[["K"]], 200)),
    TOL = num(A[["TOL"]], 4),
    # explicit K= / TOL= must match what the cells were scored with
    K_given = !is.null(A[["K"]]), TOL_given = !is.null(A[["TOL"]]),
    N_BOOT = as.integer(num(A[["N_BOOT"]], MT_N_BOOT)),
    CORES = as.integer(num(A[["CORES"]], 8)),
    BASE = if (is.null(A[["BASE"]]) || !nzchar(A[["BASE"]])) NULL else A[["BASE"]],
    OUT = if (is.null(A[["OUT"]])) file.path(d, "neon", "multichm_gated") else A[["OUT"]])
  given <- function(k) !is.null(A[[k]]) && !is.na(A[[k]]) && nzchar(A[[k]])
  S$CENSUS <- if (given("CENSUS")) A[["CENSUS"]] else cv_census_csv(d)
  S$BASE_CENSUS <- if (given("BASE_CENSUS")) A[["BASE_CENSUS"]] else
    if (!is.null(S$BASE)) cv_census_csv(S$BASE)
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
                       frdens = clip$frdens, res = res, a = a, radius = MCG_RADIUS,
                       half_dz = MCG_HALF_DZ, cover_height = MCG_COVER_HEIGHT, cover = prep$cover,
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
  # the window coefficient and the feature constants change the candidates, and
  # cv_declared() reports this session's values as the ones they were made with
  const <- c(a = CV_A_VWF, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
             cover_height = MCG_COVER_HEIGHT)
  for (k in names(const)) {
    v <- if (k %in% names(idx)) suppressWarnings(as.numeric(idx[[k]])) else NA_real_
    if (anyNA(v) || any(abs(v - const[[k]]) > 1e-12))
      stop(sprintf(paste("the candidates were not made with this library's %s = %g (or do not",
                         "record it); re-run STAGE=candidates"), k, const[[k]]), call. = FALSE)
  }
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
# (both directions over the rungs of the index: a persisted cell of a plot the
# study lacks is reported).
cv_check_detections <- function(idx, cdir, base, root) {
  bad <- character()
  for (site in unique(idx$site)) {
    ddir <- file.path(base, "neon", site, "multichm_detections")
    frozen_stamp_check(ddir, root)
    s <- idx[idx$site == site, , drop = FALSE]
    held <- sub("\\.csv$", "", list.files(ddir, "\\.csv$"))
    want <- paste(s$plot, s$rung, sep = "__")
    extra <- setdiff(held[sub("^.*__", "", held) %in% unique(idx$rung)], want)
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

# The tag of a contrast between two plot sets: scope_1 and scope_2 in place of
# the single scope.
cv_region_tag <- function(analysis, criterion, split, scope_1, scope_2, seed = NA_integer_,
                          held_out_site = NA_character_)
  data.frame(analysis = analysis, criterion = criterion, seed = seed,
             held_out_site = held_out_site, split = split, scope_1 = scope_1,
             scope_2 = scope_2, stringsAsFactors = FALSE)

# How the paired contrast config_a - config_b differs between two disjoint plot
# sets (set 1 minus set 2) at `rung`, each set restricted to the plots both
# configurations scored there: one wide row (the tag of cv_region_tag() with
# its scopes after the rung, the configurations, the plot counts, then per
# metric d1_ and d2_ (a - b within each set), dd_ (set 1 minus set 2) and the
# interval lo_, hi_ of dd_). NULL when either set has no plot left.
cv_region_row <- function(cells, plots_1, plots_2, rung, config_a, config_b, n_boot, seed, tag) {
  present <- cv_present(cells, rung, c(config_a, config_b))
  plots_1 <- intersect(unique(plots_1), present)
  plots_2 <- intersect(unique(plots_2), present)
  if (!length(plots_1) || !length(plots_2)) return(NULL)
  rows <- cells[cells$rung == rung & cells$config %in% c(config_a, config_b) &
                  cv_ids(cells) %in% c(plots_1, plots_2), , drop = FALSE]
  ct <- mcg_contrast_difference(rows, plots_1, plots_2, config_a, config_b, n_boot = n_boot,
                                seed = seed, metrics = CV_METRICS)
  d <- unlist(lapply(seq_len(nrow(ct)), function(i)
    stats::setNames(c(ct$difference_1[i], ct$difference_2[i], ct$difference[i], ct$lower[i],
                      ct$upper[i]), paste0(c("d1_", "d2_", "dd_", "lo_", "hi_"), ct$metric[i]))))
  sc <- c("scope_1", "scope_2")
  cbind(tag[setdiff(names(tag), sc)], data.frame(rung = rung, stringsAsFactors = FALSE), tag[sc],
        data.frame(config_a = config_a, config_b = config_b, n_plots_1 = ct$n_plots_1[1],
                   n_plots_2 = ct$n_plots_2[1], stringsAsFactors = FALSE),
        as.data.frame(as.list(d)))
}

# A configuration with the cover made moot where it decides nothing (no share
# gate and no exemption), as the grid stores it.
cv_canonical_label <- function(zmin, min_share, cover_min, surface_exempt) {
  if (min_share == 0 && !surface_exempt) cover_min <- 0
  mcg_config_label(mcg_config(zmin, min_share, cover_min, surface_exempt))
}

# The selected configuration's parts, as two named vectors of grid labels.
# versus_stock: reduced configurations each scored against stock (the floor
# alone, without the share gate, without the exemption, the exemption alone).
# marginal: the selection reduced in one way, so that the selection minus it is
# what the reduction took away: without its floor, its share gate or its
# exemption (what that part adds to the rest); with the gate and the exemption
# applied in every stand (cover_switch: cover_min 0, what the cover threshold
# adds); and reduced to its floor alone (gate_and_exemption: what the share
# gate and the exemption add together). Labels equal to stock (that contrast
# would be the headline itself) or to the selection (the part is off), then
# repeats, are dropped; the first name of a repeat is kept.
cv_components <- function(sel) {
  lab <- function(zmin, min_share, cover_min, surface_exempt)
    cv_canonical_label(zmin, min_share, cover_min, surface_exempt)
  own <- lab(sel$zmin, sel$min_share, sel$cover_min, sel$surface_exempt)
  keep <- function(v) {
    v <- v[!v %in% c("stock", own)]
    v[!duplicated(v)]
  }
  list(
    versus_stock = keep(c(
      floor_only = lab(sel$zmin, 0, 0, FALSE),
      no_share_gate = lab(sel$zmin, 0, sel$cover_min, sel$surface_exempt),
      no_exemption = lab(sel$zmin, sel$min_share, sel$cover_min, FALSE),
      exemption_only = lab(0, 0, sel$cover_min, sel$surface_exempt))),
    marginal = keep(c(
      floor = lab(0, sel$min_share, sel$cover_min, sel$surface_exempt),
      share_gate = lab(sel$zmin, 0, sel$cover_min, sel$surface_exempt),
      exemption = lab(sel$zmin, sel$min_share, sel$cover_min, FALSE),
      cover_switch = lab(sel$zmin, sel$min_share, 0, sel$surface_exempt),
      gate_and_exemption = lab(sel$zmin, 0, 0, FALSE))))
}

# The whole grid against stock (rows of analysis "grid": one per configuration
# and split): on the validation plots, how many configurations gain in cF1, how
# many intervals lie wholly above or below zero, the spread of the gains, the
# selection's gain and its rank by validation cF1 among the configurations and
# stock (1 = best; stock's cF1 is b_cF1); on the calibration plots, how many
# gain and the median; and the correlation of the gains between the two splits
# across configurations (NA with fewer than two). NULL without rows.
cv_grid_summary <- function(grid, selected_label) {
  if (is.null(grid) || !nrow(grid)) return(NULL)
  v <- grid[grid$split == "valid", , drop = FALSE]
  k <- grid[grid$split == "calib", , drop = FALSE]
  cf1 <- c(stats::setNames(v$a_cF1, v$config_a), stock = v$b_cF1[1])
  own <- unname(cf1[selected_label])
  m <- merge(v[c("config_a", "d_cF1")], k[c("config_a", "d_cF1")], by = "config_a",
             suffixes = c("_valid", "_calib"))
  r <- function(method) if (nrow(m) < 2L) NA_real_ else
    suppressWarnings(stats::cor(m$d_cF1_calib, m$d_cF1_valid, method = method))
  n <- length(unique(grid$config_a))
  list(n = n,
       n_positive_valid = sum(v$d_cF1 > 0, na.rm = TRUE),
       n_excludes_zero_valid = sum(v$lo_cF1 > 0, na.rm = TRUE),
       n_below_valid = sum(v$hi_cF1 < 0, na.rm = TRUE),
       median_valid = stats::median(v$d_cF1, na.rm = TRUE),
       min_valid = min(v$d_cF1, na.rm = TRUE), max_valid = max(v$d_cF1, na.rm = TRUE),
       selected_valid = if (identical(selected_label, "stock")) 0 else
         v$d_cF1[match(selected_label, v$config_a)],
       rank_valid = if (is.na(own)) NA_integer_ else 1L + sum(cf1 > own, na.rm = TRUE),
       n_ranked = n + 1L,
       n_positive_calib = sum(k$d_cF1 > 0, na.rm = TRUE),
       median_calib = stats::median(k$d_cF1, na.rm = TRUE),
       pearson = r("pearson"), spearman = r("spearman"))
}

# The seeds of the split (rows of analysis "seed"): how often each seed's
# selection is the headline label, the most frequent selection (ties to the
# smaller config_id), the counts of each selected value (increasing values),
# and the held-out change in cF1 of each seed's own selection on its own
# validation plots, with how many seeds reach the headline seed's change. NULL
# without seed rows.
cv_seed_summary <- function(selection, validation, selected_label, headline_seed) {
  s <- selection[selection$analysis == "seed", , drop = FALSE]
  if (!nrow(s)) return(NULL)
  v <- validation[validation$analysis == "seed", , drop = FALSE]
  counts <- table(s$config)
  ids <- s$config_id[match(names(counts), s$config)]
  top <- order(-as.integer(counts), ids)[1]
  tb <- function(x) {
    t <- table(x)
    stats::setNames(as.integer(t), names(t))
  }
  d <- v$d_cF1
  st <- function(f) if (length(d)) f(d) else NA_real_
  hd <- d[v$seed == headline_seed]
  hd <- if (length(hd)) hd[1] else NA_real_
  list(n = nrow(s), n_selected = sum(s$config == selected_label),
       top_label = names(counts)[top], top_n = as.integer(counts[top]),
       zmin = tb(s$zmin), min_share = tb(s$min_share), cover_min = tb(s$cover_min),
       surface_exempt = tb(as.logical(s$surface_exempt)),
       d_min = st(min), d_median = st(stats::median), d_mean = st(mean), d_max = st(max),
       n_positive = sum(d > 0), n_excludes_zero = sum(v$lo_cF1 > 0),
       headline_d_cF1 = hd, n_at_least_headline = if (is.na(hd)) NA_integer_ else sum(d >= hd))
}

# How one split's calibration ranking carries over to its validation plots, at
# native density: point estimates from the pooled counts of each configuration
# (no bootstrap) on the split's calibration plots and on its validation plots.
# One row: the number of non-stock configurations compared, the correlation
# across them of their change in cF1 against stock on the two halves (NA with
# fewer than two), how many of them gain on the validation plots, and the rank
# of `selected_id` by validation cF1 among the configurations and stock (1 =
# best; ties share the better rank). Stops when stock has no native rows on
# either half.
cv_split_carry <- function(cells, split, selected_id) {
  nat <- cells[cells$rung == "native" & !is.na(cells$config_id), , drop = FALSE]
  cf1 <- function(ids, half) {
    P <- mcg_pool(nat[cv_ids(nat) %in% ids, , drop = FALSE], "config_id")
    if (!1L %in% P$config_id)
      stop("cv_split_carry: stock (config_id 1) has no native rows on the ", half,
           " plots", call. = FALSE)
    stats::setNames(P$cF1, P$config_id)
  }
  k <- cf1(split$calib, "calibration"); v <- cf1(split$valid, "validation")
  ids <- intersect(names(k), names(v))
  g <- setdiff(ids, "1")
  dk <- k[g] - k[["1"]]; dv <- v[g] - v[["1"]]
  own <- v[as.character(selected_id)]
  data.frame(n_configs = length(g),
             pearson = if (length(g) < 2L) NA_real_ else suppressWarnings(stats::cor(dk, dv)),
             n_positive_valid = sum(dv > 0, na.rm = TRUE),
             rank_valid = if (is.na(own)) NA_integer_ else 1L + sum(v[ids] > own, na.rm = TRUE))
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

  ## c2. held-out by site: the headline selection on each site's validation plots
  if (length(sites) > 1L) for (site in sites)
    add_v(con(sp$valid[sub("::.*", "", sp$valid) == site], "native", sel$label, "stock",
              cv_tag("site", S$CRITERION, "valid", site, S$SEED)))

  ## d. components of the selection against stock (validation plots, native
  ## density), and the selection minus each reduction of it (cv_components()):
  ## at native density on the validation, then the calibration plots, then on
  ## the validation plots at every other rung, rung by rung
  comp <- lapply(cv_components(sel), function(v) v[v %in% cells$config])
  for (nm in names(comp$versus_stock))
    add_v(con(sp$valid, "native", comp$versus_stock[[nm]], "stock",
              cv_tag(paste0("component_", nm), S$CRITERION, "valid", all_scope, S$SEED)))
  for (spl in c("valid", "calib")) for (nm in names(comp$marginal))
    add_v(con(sp[[spl]], "native", sel$label, comp$marginal[[nm]],
              cv_tag(paste0("marginal_", nm), S$CRITERION, spl, all_scope, S$SEED)))
  for (rl in setdiff(rungs, "native")) for (nm in names(comp$marginal))
    add_v(con(sp$valid, rl, sel$label, comp$marginal[[nm]],
              cv_tag(paste0("marginal_", nm), S$CRITERION, "valid", all_scope, S$SEED)))

  ## e. seeds, each with how its calibration ranking carries over
  carry <- list()
  for (sd in S$SEEDS) {
    s2 <- cv_split(cells, sd, S$FRAC)
    sl <- cv_select(cells, s2$calib, S$CRITERION)
    sel_rows[[length(sel_rows) + 1L]] <- cv_selection_row(sl, "seed", sd)
    carry[[length(carry) + 1L]] <- data.frame(seed = sd, config = sl$label,
                                              cv_split_carry(cells, s2, sl$config_id),
                                              stringsAsFactors = FALSE)
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

  ## h. all plots (in-sample): the all-plots selection, and the headline
  ## selection against stock on every native plot of each scope and each site
  sa <- cv_select(cells, native_ids, S$CRITERION)
  sel_rows[[length(sel_rows) + 1L]] <- cv_selection_row(sa, "all_plots")
  all_tag <- function(sc) cv_tag("all_plots", S$CRITERION, "all (in-sample)", sc, S$SEED)
  for (sc in names(scopes))
    add_v(con(in_scope(native_ids, sc), "native", sel$label, "stock", all_tag(sc)))
  for (site in setdiff(sites, names(scopes)))
    add_v(con(native_ids[sub("::.*", "", native_ids) == site], "native", sel$label, "stock",
              all_tag(site)))

  ## i. the headline gain in one region minus the other, validation plots
  reg <- list()
  if (all(CV_REGION_DIFFERENCE %in% names(scopes))) for (rl in rungs) {
    r <- cv_region_row(cells, in_scope(sp$valid, CV_REGION_DIFFERENCE[1]),
                       in_scope(sp$valid, CV_REGION_DIFFERENCE[2]), rl, sel$label, "stock", nb,
                       boot_seed, cv_region_tag("region_difference", S$CRITERION, "valid",
                                                CV_REGION_DIFFERENCE[1],
                                                CV_REGION_DIFFERENCE[2], S$SEED))
    if (!is.null(r)) reg[[length(reg) + 1L]] <- r
  }

  ## j. every non-stock grid configuration against stock, validation and
  ## calibration plots at native density (kept apart from validation.csv)
  nat <- unique(cells[cells$rung == "native" & !is.na(cells$config_id) &
                        cells$config != "stock", c("config_id", "config")])
  grid_rows <- list()
  for (k in nat$config[order(nat$config_id)]) for (spl in c("valid", "calib")) {
    r <- con(sp[[spl]], "native", k, "stock", cv_tag("grid", S$CRITERION, spl, all_scope, S$SEED))
    if (!is.null(r)) grid_rows[[length(grid_rows) + 1L]] <- r
  }

  selection <- do.call(rbind, sel_rows)
  validation <- do.call(rbind, val_rows)
  regions <- if (length(reg)) do.call(rbind, reg)
  grid <- if (length(grid_rows)) do.call(rbind, grid_rows)
  seed_grid <- if (length(carry)) do.call(rbind, carry)
  rownames(selection) <- NULL; rownames(validation) <- NULL
  if (!is.null(regions)) rownames(regions) <- NULL
  if (!is.null(grid)) rownames(grid) <- NULL
  if (!is.null(seed_grid)) rownames(seed_grid) <- NULL
  list(selection = selection, validation = validation, selected = sel, split = sp,
       n_calib = length(sel$plots), n_valid = length(intersect(sp$valid, native_ids)),
       scopes = scopes, components = comp, regions = regions, grid = grid,
       seed_grid = seed_grid)
}

# The declared configuration with what it was selected on. The window
# coefficient and the feature constants are this session's, which
# cv_read_index() has checked are the ones the candidates were made with.
cv_declared <- function(res, S, root_id, population) {
  s <- res$selected
  list(config_id = s$config_id, label = s$label, zmin = s$zmin, min_share = s$min_share,
       cover_min = s$cover_min, surface_exempt = s$surface_exempt,
       a = CV_A_VWF, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ, cover_height = MCG_COVER_HEIGHT,
       criterion = S$CRITERION, seed = S$SEED, frac = S$FRAC, K = S$K, tol = S$TOL,
       n_calibration_plots = res$n_calib, n_validation_plots = res$n_valid,
       clip_manifest_sha256 = root_id, population = population,
       selection = CV_SELECTED_ON, provenance = CV_PROVENANCE)
}

## ---- censused subplots --------------------------------------------------------------------
# The configuration stamp the arm driver (detect_multichm_gated_sweep.R) writes
# into each site's detections directory before it persists any detection.
CV_ARM_CONFIG_STAMP <- "multichm_gated_config.json"
CV_CENSUS_SPLITS <- c(all = "all admitted (in-sample for the selection)", valid = "valid")

# The censused scores are of the arm's persisted detections, which carry no
# trace of the study's selection: each site's stamp must hold the selection's
# zmin, min_share, cover_min and surface_exempt, and the window coefficient and
# feature constants of this study's candidates (they change the detections as
# much as the configuration does). Stops otherwise.
cv_census_config_check <- function(d, sites, sel) {
  want <- list(zmin = sel$zmin, min_share = sel$min_share, cover_min = sel$cover_min,
               surface_exempt = as.logical(sel$surface_exempt))
  const <- list(a = CV_A_VWF, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                cover_height = MCG_COVER_HEIGHT)
  holds <- function(j, w) all(names(w) %in% names(j)) &&
    isTRUE(all.equal(lapply(j[names(w)], unname), w, tolerance = 1e-12))
  for (site in sites) {
    f <- file.path(d, "neon", site, "multichm_gated_detections", CV_ARM_CONFIG_STAMP)
    if (!file.exists(f))
      stop("no configuration stamp at ", f, ", so the censused scores cannot be tied to the ",
           "selection ", sel$label, "; re-run the arm and score_census_support.R", call. = FALSE)
    j <- jsonlite::read_json(f, simplifyVector = TRUE)
    if (!holds(j, want)) {
      lab <- if (is.null(j$label)) "(unlabelled)" else j$label
      stop(sprintf(paste("the censused scores are of configuration %s, not the selection %s;",
                         "re-run the arm and score_census_support.R"), lab, sel$label),
           call. = FALSE)
    }
    if (!holds(j, const))
      stop(sprintf(paste("the censused detections of %s were not made with this study's %s (or",
                         "their stamp does not record them); re-run the arm and",
                         "score_census_support.R"), site,
                   paste(sprintf("%s = %g", names(const), unlist(const)), collapse = ", ")),
           call. = FALSE)
  }
  invisible(TRUE)
}

# The stamps tie the job directory's detections to the selection, not a censused
# file, which may have been scored elsewhere or before the arm was re-run. A
# censused file also holds the nominal-box count of the detections it scored
# (rect_n_det, a function of the detections and the plot core alone): at native
# density it must equal n_det of `config` in `cells` in every cell of `detector`
# at the study's sites. A necessary condition, not a proof of identical
# detections. Stops otherwise.
cv_census_cells_check <- function(csv, detector, cells, config) {
  g <- read.csv(csv, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  g <- g[g$detector %in% detector & g$rung %in% "native" & g$site %in% cells$site, ,
         drop = FALSE]
  if (!nrow(g)) return(invisible(TRUE))        # cv_census() reports a file without rows
  if (!"rect_n_det" %in% names(g))
    stop(csv, " has no rect_n_det (the nominal-box detection count), so its ", detector,
         " scores cannot be tied to configuration ", config,
         "; score the detections with score_census_support.R", call. = FALSE)
  s <- cells[cells$config == config & cells$rung == "native", , drop = FALSE]
  n <- s$n_det[match(paste(g$site, g$plot), paste(s$site, s$plot))]
  bad <- is.na(n) | is.na(g$rect_n_det) | g$rect_n_det != n
  if (any(bad))
    stop(sprintf(paste("%s does not score the %s detections of configuration %s: the",
                       "nominal-box detection count differs from cells.csv in %d of %d",
                       "cells (first %s); score that configuration's persisted detections",
                       "with score_census_support.R"), csv, detector, config, sum(bad),
                 length(bad), g$plot[which(bad)[1]]), call. = FALSE)
  invisible(TRUE)
}

# Censused-subplot scores (score_census_support.R) at native density: the arm
# (detector multichm_gated) from `gated_csv` against the paper's multichm from
# `base_csv`, on the cells both scored on the same support. For split "all"
# (every admitted plot) and "valid" (the admitted plots among `valid_ids`), and
# for every scope of `scopes` and every site that is not a scope name, with
# plots resampled within site: scores (recall, precision and F1 of each
# detector with intervals) and contrasts (gated minus stock per metric).
# Returns list(scores, contrasts, cells = the equal-support rows).
cv_census <- function(gated_csv, base_csv, valid_ids, scopes, sites, n_boot, seed = MT_SEED) {
  read <- function(f, det) {
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    # a file without the support identity holds nominal-box scores, which the
    # support guard of mt_equal_support() would let through unchecked
    gone <- setdiff(c("support_id", "support_policy", "reference_population"), names(x))
    if (length(gone))
      stop(f, " has no ", paste(gone, collapse = ", "), ", so it is not a censused score ",
           "file; score the detections with score_census_support.R", call. = FALSE)
    x <- x[x$detector %in% det & x$rung %in% "native", , drop = FALSE]
    if (!nrow(x))
      stop("there are no censused ", det, " rows at native density in ", f,
           "; score them with score_census_support.R", call. = FALSE)
    x
  }
  a <- read(gated_csv, "multichm_gated"); b <- read(base_csv, "multichm")
  cols <- intersect(names(a), names(b))
  x <- rbind(a[, cols, drop = FALSE], b[, cols, drop = FALSE])
  x$tp_core[x$n_det == 0] <- 0
  if (anyNA(x[c("TP", "n_ref", "n_det", "tp_core")]))
    stop("missing counts in the censused scores", call. = FALSE)
  eq <- mt_equal_support(x, c("multichm_gated", "multichm"))
  if (!nrow(eq))
    stop("no censused cell was scored by both detectors on the same support", call. = FALSE)
  ids <- cv_ids(eq)
  scores <- list(); contrasts <- list()
  for (spl in names(CV_CENSUS_SPLITS)) {
    keep <- if (spl == "valid") ids %in% valid_ids else rep(TRUE, nrow(eq))
    for (sc in c(names(scopes), setdiff(sites, names(scopes)))) {
      rows <- eq[keep & eq$site %in% (if (sc %in% names(scopes)) scopes[[sc]] else sc), ,
                 drop = FALSE]
      if (!nrow(rows)) next
      W <- mt_plot_weights(rows$site, rows$plot, n_boot, seed)
      s <- mt_boot_scores(rows, W, "detector")
      scores[[length(scores) + 1L]] <- cbind(data.frame(split = spl, scope = sc,
                                                        stringsAsFactors = FALSE),
                                             mt_intervals(s))
      contrasts[[length(contrasts) + 1L]] <- cbind(
        data.frame(split = spl, scope = sc, n_plots = nrow(W), stringsAsFactors = FALSE),
        do.call(rbind, lapply(c("recall", "precision", "F1"), function(m)
          mt_contrast(s, "multichm", "multichm_gated", m))))
    }
  }
  bind <- function(z) {
    z <- do.call(rbind, z)
    if (!is.null(z)) rownames(z) <- NULL
    z
  }
  list(scores = bind(scores), contrasts = bind(contrasts), cells = eq)
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

# One line per rung of the region differences (cv_region_row()).
cv_md_regions <- function(r) {
  if (is.null(r) || !nrow(r)) return("(no rows)")
  hdr <- c("| Rung | Set 1 | Set 2 | Plots 1 / 2 | ΔcF1 set 1 | ΔcF1 set 2 | Difference in ΔcF1 [95% interval] | Difference in ΔF1 [95% interval] | Difference in ΔcPrecision [95% interval] | Difference in ΔcRecall [95% interval] |",
           "|---|---|---|---|---|---|---|---|---|---|")
  c(hdr, sprintf("| %s | %s | %s | %d / %d | %s | %s | %s %s | %s %s | %s %s | %s %s |",
                 r$rung, r$scope_1, r$scope_2, as.integer(r$n_plots_1), as.integer(r$n_plots_2),
                 cv_f3(r$d1_cF1), cv_f3(r$d2_cF1), cv_f3(r$dd_cF1), cv_iv(r$lo_cF1, r$hi_cF1),
                 cv_f3(r$dd_F1), cv_iv(r$lo_F1, r$hi_F1),
                 cv_f3(r$dd_cPrecision), cv_iv(r$lo_cPrecision, r$hi_cPrecision),
                 cv_f3(r$dd_cRecall), cv_iv(r$lo_cRecall, r$hi_cRecall)))
}

# The sentences of the whole-grid summary (cv_grid_summary()).
cv_md_grid <- function(g) {
  if (is.null(g)) return("(no rows)")
  f2 <- function(x) ifelse(is.na(x), "NA", sprintf("%.2f", x))
  paste(
    sprintf(paste("On the validation plots %d of the %d non-stock grid configurations score",
                  "above stock in corrected F1 (median %s, range %s to %s); %d intervals lie",
                  "wholly above zero and %d wholly below it."),
            g$n_positive_valid, g$n, cv_f3(g$median_valid), cv_f3(g$min_valid),
            cv_f3(g$max_valid), g$n_excludes_zero_valid, g$n_below_valid),
    sprintf("The selected configuration (%s) ranks %s of %d, stock included.",
            cv_f3(g$selected_valid), ifelse(is.na(g$rank_valid), "NA", g$rank_valid),
            g$n_ranked),
    sprintf("On the calibration plots %d of the %d score above stock (median %s).",
            g$n_positive_calib, g$n, cv_f3(g$median_calib)),
    sprintf(paste("Across configurations the calibration and validation changes correlate at",
                  "%s (Spearman %s)."), f2(g$pearson), f2(g$spearman)),
    "Every row is in `grid_contrasts.csv`.")
}

# The summary lines of the seeds (cv_seed_summary()).
cv_md_seeds <- function(ss, selected_label, headline_seed) {
  if (is.null(ss)) return("(no rows)")
  cnt <- function(tb) paste(sprintf("%s in %d", names(tb), tb), collapse = ", ")
  c(sprintf(paste("%d of the %d splits select the headline configuration `%s`; the most",
                  "frequent selection is `%s` (%d splits)."),
            ss$n_selected, ss$n, selected_label, ss$top_label, ss$top_n),
    "",
    sprintf("Selected values: zmin %s; min_share %s; cover_min %s; surface_exempt %s.",
            cnt(ss$zmin), cnt(ss$min_share), cnt(ss$cover_min), cnt(ss$surface_exempt)),
    "",
    sprintf(paste("Held-out change in cF1 of each split's own selection against stock on its",
                  "own validation plots: min %s, median %s, mean %s, max %s; positive in %d of",
                  "%d; the interval excludes zero in %d."),
            cv_f3(ss$d_min), cv_f3(ss$d_median), cv_f3(ss$d_mean), cv_f3(ss$d_max),
            ss$n_positive, ss$n, ss$n_excludes_zero),
    "",
    sprintf("%s of the %d splits reach the headline split's change (seed %s: %s).",
            ifelse(is.na(ss$n_at_least_headline), "NA", ss$n_at_least_headline), ss$n,
            headline_seed, cv_f3(ss$headline_d_cF1)))
}

# The paragraph on how each split's calibration ranking carries over to its
# validation plots (rows of cv_split_carry() with their seed and selection): the
# median, percentiles and range of the correlations, the headline seed's and how
# many splits exceed it, and the median and range of each split's own rank and
# of the configurations that gain on its validation plots.
cv_md_carry <- function(sg, headline_seed) {
  if (is.null(sg) || !nrow(sg)) return("(no rows)")
  f2 <- function(x) ifelse(is.na(x), "NA", sprintf("%.2f", x))
  r <- sg$pearson[!is.na(sg$pearson)]
  st <- function(f) if (length(r)) f(r) else NA_real_
  q <- function(p) st(function(x) unname(stats::quantile(x, p)))
  h <- sg$pearson[sg$seed %in% headline_seed]
  h <- if (length(h)) h[1] else NA_real_
  # the configurations compared (one number unless the splits differ)
  n <- range(sg$n_configs)
  nc <- function(add = 0L) if (n[1] == n[2]) sprintf("%d", n[1] + add) else
    sprintf("%d to %d", n[1] + add, n[2] + add)
  sprintf(paste("Across the %s non-stock grid configurations the calibration and validation",
                "changes in cF1 correlate at a median of %s over the %d splits (10th to 90th",
                "percentile %s to %s, range %s to %s; seed %s: %s, exceeded in %s splits). A",
                "split's own selection ranks at a median of %g of %s on its validation plots,",
                "stock included (range %d to %d), and a median of %g of the %s configurations",
                "score above stock there (range %d to %d). Every split is in `seed_grid.csv`."),
          nc(), f2(st(stats::median)), nrow(sg), f2(q(0.1)), f2(q(0.9)), f2(st(min)),
          f2(st(max)), headline_seed, f2(h), if (is.na(h)) "NA" else sum(r > h),
          stats::median(sg$rank_valid), nc(1L), min(sg$rank_valid), max(sg$rank_valid),
          stats::median(sg$n_positive_valid), nc(), min(sg$n_positive_valid),
          max(sg$n_positive_valid))
}

# One line per split and scope of the censused contrast (cv_census()).
cv_md_census <- function(cs) {
  k <- cs$contrasts
  if (is.null(k) || !nrow(k)) return("(no rows)")
  hdr <- c("| Split | Scope | Plots | Stems | Detections gated / stock | Recall gated / stock | Precision gated / stock | F1 gated / stock | ΔF1 [95% interval] | ΔPrecision [95% interval] | ΔRecall [95% interval] |",
           "|---|---|---|---|---|---|---|---|---|---|---|")
  u <- unique(k[c("split", "scope", "n_plots")])
  s <- cs$scores
  one <- function(x) if (nrow(x)) x[1, ] else NULL
  est <- function(i, det, m) one(s[s$split == u$split[i] & s$scope == u$scope[i] &
                                     s$detector == det & s$metric == m, , drop = FALSE])
  pair <- function(i, m) sprintf("%s / %s", cv_f3(est(i, "multichm_gated", m)$estimate),
                                 cv_f3(est(i, "multichm", m)$estimate))
  dl <- function(i, m) {
    r <- one(k[k$split == u$split[i] & k$scope == u$scope[i] & k$metric == m, , drop = FALSE])
    sprintf("%s %s", cv_f3(r$estimate), cv_iv(r$lower, r$upper))
  }
  c(hdr, vapply(seq_len(nrow(u)), function(i) {
    g <- est(i, "multichm_gated", "F1"); b <- est(i, "multichm", "F1")
    sprintf("| %s | %s | %d | %d | %d / %d | %s | %s | %s | %s | %s | %s |",
            CV_CENSUS_SPLITS[[u$split[i]]], u$scope[i], as.integer(u$n_plots[i]),
            as.integer(g$n_ref), as.integer(round(g$n_det)), as.integer(round(b$n_det)),
            pair(i, "recall"), pair(i, "precision"), pair(i, "F1"),
            dl(i, "F1"), dl(i, "precision"), dl(i, "recall"))
  }, character(1)))
}

cv_tables_md <- function(res, S, root_id, population, census = NULL) {
  v <- res$validation; s <- res$selection; sel <- res$selected
  pick <- function(an, ...) {
    x <- v[v$analysis %in% an, , drop = FALSE]
    f <- list(...)
    for (k in names(f)) x <- x[x[[k]] %in% f[[k]], , drop = FALSE]
    x
  }
  # the selection minus each reduction: native rows (validation, then
  # calibration), and the validation rows of the decimated rungs
  red <- res$components$marginal
  marg <- v[startsWith(v$analysis, "marginal_"), , drop = FALSE]
  ladder <- marg[marg$rung != "native", , drop = FALSE]
  marg <- marg[marg$rung == "native", , drop = FALSE]
  marg <- marg[order(marg$split != "valid"), , drop = FALSE]
  # the ten lowest seeds; selection.csv and validation.csv hold every one
  first <- utils::head(sort(unique(s$seed[s$analysis == "seed"])), 10)
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
    "## What each part adds (the selection minus a reduction of it)",
    "",
    if (!length(red)) "(no rows)" else c(
      sprintf("Reductions (B): %s.", paste(sprintf("%s `%s`", names(red), red), collapse = "; ")),
      paste("floor, share_gate and exemption are the selection without that part; cover_switch",
            "is the selection with its gate and exemption applied in every stand (cover_min 0);",
            "gate_and_exemption is its floor alone. Native density, validation plots then",
            "calibration plots (in-sample):"),
      "",
      cv_md_contrasts(marg),
      if (nrow(ladder)) c(
        "",
        "The same on the validation plots of the decimated rungs:",
        "",
        cv_md_contrasts(ladder))),
    "",
    "## Held-out by site (validation plots, native density)",
    "",
    cv_md_contrasts(pick("site")),
    "",
    "## Difference between regions (validation plots)",
    "",
    paste("Δ = selected − stock within each set; the difference is set 1 minus set 2, with one",
          "bootstrap over both sets."),
    "",
    cv_md_regions(res$regions),
    "",
    "## The whole grid against stock (native density)",
    "",
    cv_md_grid(cv_grid_summary(res$grid, sel$label)),
    "",
    "## Seeds (validation plots, native density)",
    "",
    cv_md_seeds(cv_seed_summary(s, v, sel$label, S$SEED), sel$label, S$SEED),
    "",
    cv_md_carry(res$seed_grid, S$SEED),
    "",
    "The first ten splits (`selection.csv` and `validation.csv` hold all of them):",
    "",
    cv_md_selection(s[s$analysis == "seed" & s$seed %in% first, , drop = FALSE]),
    "",
    cv_md_contrasts(pick("seed", seed = first)),
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
    "## All plots (in-sample; not a held-out result)",
    "",
    cv_md_selection(s[s$analysis == "all_plots", , drop = FALSE]),
    "",
    sprintf(paste("The headline selection `%s` against stock on every plot at native density,",
                  "by scope and by site (the calibration plots are among them):"), sel$label),
    "",
    cv_md_contrasts(pick("all_plots")),
    "",
    if (!is.null(census)) c(
      paste("## Censused subplots (native density; the declared arm's persisted detections",
            "against the paper's multichm)"),
      "",
      paste("Scored inside the censused subplots (score_census_support.R) on the plots both",
            "detectors were scored on with the same support; Δ = gated − stock."),
      "",
      cv_md_census(census),
      ""))
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
  ## b-j
  res <- cv_analyze(cells, S)
  ## k. censused subplots: the arm's persisted detections against the paper's multichm
  census <- NULL
  cfiles <- c(S$CENSUS, if (is.null(S$BASE_CENSUS))
    "BASE_CENSUS (neither BASE= nor BASE_CENSUS= given)" else S$BASE_CENSUS)
  gone <- cfiles[!file.exists(cfiles)]
  if (!length(gone)) {
    sites <- intersect(S$SITES, unique(cells$site))
    cv_census_config_check(S$d, sites, res$selected)
    cv_census_cells_check(S$CENSUS, "multichm_gated", cells, res$selected$label)
    cv_census_cells_check(S$BASE_CENSUS, "multichm", cells, "stock")
    census <- cv_census(S$CENSUS, S$BASE_CENSUS, res$split$valid, res$scopes, sites, S$N_BOOT)
  } else cat(sprintf("no censused scores at %s; the censused contrast is skipped\n", gone[1]))
  write.csv(res$selection, file.path(S$OUT, "selection.csv"), row.names = FALSE)
  write.csv(res$validation, file.path(S$OUT, "validation.csv"), row.names = FALSE)
  # a file from an earlier run that this run does not produce is removed, not kept
  extra <- list(grid_contrasts.csv = res$grid, region_differences.csv = res$regions,
                census_scores.csv = census$scores, census_contrasts.csv = census$contrasts,
                seed_grid.csv = res$seed_grid)
  for (nm in names(extra)) {
    f <- file.path(S$OUT, nm)
    if (is.null(extra[[nm]]) || !nrow(extra[[nm]])) unlink(f) else
      write.csv(extra[[nm]], f, row.names = FALSE)
  }
  jsonlite::write_json(cv_declared(res, S, root_id, pop), file.path(S$OUT, "declared_config.json"),
                       auto_unbox = TRUE, pretty = TRUE, digits = NA)
  writeLines(cv_tables_md(res, S, root_id, pop, census = census), file.path(S$OUT, "tables.md"))
  sel <- res$selected
  cat(sprintf("headline: %s (config_id %d), %s: %d calibration plots, %d validation plots\n",
              sel$label, sel$config_id, CV_SELECTED_ON, res$n_calib, res$n_valid))
  cv_print_anchors(cells, sel)
  cat(sprintf("wrote %s/{%s}\n", S$OUT, paste(c(
    "selection.csv", "validation.csv", names(Filter(function(x) !is.null(x) && nrow(x) > 0, extra)),
    "declared_config.json", "tables.md"), collapse = ", ")))
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
