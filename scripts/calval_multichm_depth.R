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

# Calibration/validation study of the `multichm_depth` tree-top arm
# (multichm_depth_lib.R), a depth-gated variant of the multichm_gated arm, as
# the specification docs/multichm-depth-protocol.md (sections 5 to 7) fixes it
# before any NEON score of its rules was read. The family keeps a deeper-layer
# candidate of a closed stand when it sits at most depth_max metres under the
# local canopy surface (or, with lit_union, when it is lit and at most
# MCD_LIT_DEPTH deep), floors every candidate by height, and in closed stands
# applies one horizontal spacing rule (near_2d) to every top. Its 240
# configurations (mcd_grid()) are scored on the gated study's cached candidates
# (the same clips, stems, split, null shifts and scorer), a configuration is
# selected on the CALIBRATION plots of the gated study's headline split at
# native density by pooled chance-corrected F1 (ties to the smaller config_id),
# and the selection is contrasted on the held-out VALIDATION plots with the
# declared gated arm (z5_s0.75_c0.6_e1_d8) and with three other gated
# configurations re-derived from the same candidates, stock multichm and the
# CHM-VWF baseline. The selection is not the configuration the arm uses
# (MCD_ARM, chosen after the held-out results had been read).
#
# The specification and its addendum were written as two working files, which
# docs/multichm-depth-protocol.md reproduces; the outputs carry the working
# files' hashes and the document's (cd_spec_record). Addendum 1 (fixed after
# the blind calibration results and the code review, before any validation
# cell of the depth family was scored) wins over the specification where they
# differ: the headline split is read from the gated run, never taken as an
# argument (A1); the reading rule's precedence is better, worse, not worse,
# inconclusive, and a scope of fewer than 10 plots is not read (A2); the
# lowest-tree guard is read with its chance-corrected counterpart, and every
# lowest-tree score carries a chance-corrected interval (A3); the low-floor
# sibling S_low is derived from the calibration plots and contrasted (A4);
# closed and open stands are two more native scopes (A5); the features carry
# the constants' stamp (A7); the provenance text gains the addendum's sentence
# (A9).
#
# Provenance (section 7 and A9, repeated in declared_depth_config.json,
# tables_blind.md and tables.md): CD_PROVENANCE below, with one sentence added
# that names the protocol document.
#
# BLIND RULE (section 5, A1). With UNBLIND=0, the default: the score stage
# scores only the cells of the calibration plots of the headline split (the
# gated study's: seed and calibration fraction of its declared_config.json,
# seed 1 and frac 0.5); no validation cell of the depth family is scored,
# printed or written; the analyze stage keeps only the calibration plots' rows
# of cells.csv and reads nothing else of the validation plots but their
# identity (the split's plot ids and strata, split.csv). UNBLIND=1 scores the
# remaining cells and appends them (score stage) and adds the held-out analyses
# (analyze stage). The append stops, rather than rescoring, when the earlier
# cells were scored under another split or other settings.
#
# Stages (STAGE=features|score|analyze|all), each reading the previous one's
# files and the gated study's run (GATED, read only):
#   features  every cell of the gated candidates index: the same frozen clip the
#             candidates were made from, mcd_features() of every candidate ->
#             OUT/features/<site>__<plot>__<rung>.rds (list with the candidate
#             table and its feature columns, r_col, frdens) and OUT/features.csv
#             (one row per cell: counts, r_col, depth quantiles of the deeper
#             candidates). Stops when a clip is empty, or a cached candidate
#             table does not have the index's n_cand rows. Each file carries
#             mcd_constants() and their digest (A7); every run rewrites every
#             cell's file, so a file without that stamp is replaced, and the
#             later stages refuse a file whose stamp or r_col does not match.
#   score     every allowed cell (blind rule) x every grid configuration, plus
#             the four reference configurations re-derived through the gated
#             library (CD_REFERENCES), scored as the gated study scores them
#             (mcg_score_cell with the cell's core stems, K and TOL of the gated
#             cells.config.json, the plot's mcg_null_offsets, memoised per
#             detection set); chm_vwf rows copied from the gated cells.csv.
#             CHECK S1 stops the stage when a re-derived reference row differs
#             from the gated row of the same cell and label (observed counts
#             exactly, null means within 1e-9). -> OUT/cells.csv, OUT/grid.csv,
#             OUT/split.csv (the headline split: plot ids and strata, after
#             CHECK S2), OUT/cells.config.json.
#   analyze   Stops without the protocol document (docs/multichm-depth-protocol.md,
#             holding both working files' hashes). CHECK S2 (the split equals the
#             gated study's: 57 calibration and 49 validation plots), the
#             record's split (seed, frac, plot sets) equals it, the selection on
#             the calibration plots, S_low (A4) from their per-stem matches, and
#             the in-sample tables on them: the selection against each reference
#             (with the closed- and open-stand scopes, A5), S_low against the
#             declared arm, stock and S, the components, the grid's calibration
#             ranking, the lowest-tree tables (with CHECK S3: the per-stem
#             matches give each cell's TP of cells.csv; each score with its
#             plot-bootstrap intervals, A3) and the height tables. Every
#             contrast row of calibration.csv carries the A2 verdict on cF1.
#             -> OUT/selection.csv (the headline row and, when S_low exists, a
#             "low_floor" row), OUT/declared_depth_config.json,
#             OUT/calibration.csv, OUT/grid_calibration.csv, OUT/components.csv,
#             OUT/lowest_trees.csv, OUT/heights.csv, OUT/tables_blind.md, and
#             for audit OUT/stem_matches.csv, OUT/height_pairs.csv,
#             OUT/zrep_cells.csv, OUT/analyze_checks.json. UNBLIND=1 adds the
#             held-out analyses a to h of section 5 and those of A3 to A5 ->
#             OUT/validation.csv, OUT/ladder.csv, OUT/seeds.csv,
#             OUT/seed_summary.csv, OUT/site_out.csv, OUT/tables.md (every
#             table, the reading rule of section 6 with A2's precedence, the
#             guard read as A3 says, the S_low reading of A4 and the
#             provenance), and the validation rows of components.csv,
#             lowest_trees.csv and heights.csv.
#
# Usage (from the repository root; the job directory is the gated study's, for
# its stems, plot centroids and frozen root):
#   CLAUDE_JOB_DIR=work/multichm_gated_runs Rscript scripts/calval_multichm_depth.R
#     [STAGE=all|features|score|analyze] [UNBLIND=0|1] [CORES=8 (at most 8)]
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [RUNGS=native,8,4,2,1] [POP=adopted]
#     [FROZEN_ROOT=...] [SEEDS=1,...,200] [N_BOOT=1000]
#     [GATED=$CLAUDE_JOB_DIR/neon/multichm_gated]
#     [OUT=work/multichm_depth_runs/neon/multichm_depth]
# The headline split's seed and calibration fraction are read from
# GATED/declared_config.json (A1); SEED= and FRAC= are accepted only when they
# repeat those values and stop the run otherwise, whatever UNBLIND is. K and
# TOL are those the gated cells were scored with (its cells.config.json); an
# explicit K= or TOL= must equal them. The criterion is cF1 (fixed).
suppressMessages({ library(lidR); library(lidRplugins); library(sf)
                   library(data.table); library(parallel) })
options(lidR.progress = FALSE)
# The gated study's driver: sourcing it runs nothing (it ends with
# `if (sys.nframe() == 0L) run_main()`); it sources sweep_lib.R, model_bench_lib.R,
# calval_lib.R, master_tables_lib.R and multichm_gated_lib.R and defines the cv_*
# helpers reused here (cv_read_index, cv_split, cv_scopes, cv_contrast_row,
# cv_tag, cv_present, cv_ids, cv_cell_file, cv_rung_value, cv_grid_digest, ...).
source(.find("calval_multichm_gated.R"))
source(.find("multichm_depth_lib.R"))

## ---- constants ----------------------------------------------------------------------------
CD_DECLARED   <- "z5_s0.75_c0.6_e1_d8"   # the declared gated arm (MCG_DECLARED)
CD_REFERENCES <- c("stock", "z5_s0_c0.6_e1", "z5_s0.75_c0.6_e1", CD_DECLARED)
CD_CHM        <- "chm_vwf"
CD_CRITERION  <- "cF1"                   # fixed by the specification (section 5)
CD_METRICS    <- CV_METRICS              # cF1, F1, cPrecision, cRecall, precision, recall, det_per_ref
CD_SEED_METRICS <- c("cF1", "F1", "recall", "precision")
CD_MAX_CORES  <- 8L                      # at most 8 R worker processes (specification section 1)
CD_ZREP       <- "@zrep"                 # suffix of the selection reported with z = zrep
CD_BANDS      <- c("[0,5)", "[5,10)", "[10,20)", "[20,Inf)", "unknown")
CD_BAND_BREAKS <- c(0, 5, 10, 20, Inf)
CD_LOW        <- "[0,10)"                # the two lowest bands pooled (the guard, section 6)
CD_CLASSES    <- c(CV_CLASSES, "unknown")
CD_NOT_WORSE  <- -0.02                   # reading rule: "not worse" lower bound (section 6)
CD_MIN_READ   <- 10L                     # a scope with fewer plots is reported, not read (A2)
CD_NOT_READ   <- "not read (fewer than 10 plots)"
CD_MARGIN_NOTE <- "(within the 0.02 margin)"   # a "worse" whose lower bound is above -0.02 (A2)
CD_CLOSED_COVER <- 0.6                   # native cover >= this: a closed stand (A5)
CD_STAND_SCOPES <- c("Closed stands", "Open stands")
CD_LOW_CRITERION <- "cRecall_under_10m"  # S_low: chance-corrected recall of the [0,10) stems (A4)
CD_LOW_FLOOR  <- "low_floor"             # analysis tag of S_low's contrasts (A4)
CD_PLOT_COLS  <- c("site", "plot", "plotType", "n_dominant", "n_codominant", "n_intermediate",
                   "n_suppressed")
CD_LEAD_COLS  <- c("site", "plot", "plotType", "rung", "cover", "top_height", "crown_spacing",
                   "pdens", "frdens", "family", "config", "config_id", "gated_config_id",
                   "depth_max", "near_2d", "zmin", "zmin_surface", "lit_union", "cover_min",
                   "n_dominant", "n_codominant", "n_intermediate", "n_suppressed")
CD_FAMILIES   <- c("depth", "gated", "chm_vwf")
CD_PROVENANCE <- paste(
  "The family's form, its constants and its grid values were informed by an",
  "exploratory look at 60 plots outside the benchmark that have no field",
  "reference (three ML segmenters as referees). No NEON score of these rules",
  "was read before the features, the grid and the selection criterion were",
  "fixed (work/multichm_depth/SPEC.txt). The split, the scoring and the",
  "reference configurations are those of the multichm_gated study, whose own",
  "provenance stands. Validation cells of the depth family were scored only",
  "after the code had been reviewed (UNBLIND=1).",
  # Addendum 1, A9: added to the text of section 7
  "The precedence of the reading rule, the chance-corrected reading of the",
  "lowest-tree guard, the low-floor sibling, the closed- and open-stand scopes",
  "and the confirmation datasets were fixed in",
  "work/multichm_depth/SPEC_ADDENDUM_1.txt after the blind calibration results",
  "and the code review had been read, and before any validation cell of the",
  "depth family was scored.",
  # where the two working files named above are now read
  "Both files are reproduced in docs/multichm-depth-protocol.md.")
CD_SELECTED_ON <- paste("selected on the calibration plots at native density",
                        "(highest pooled cF1, ties to the smaller config_id)")
CD_LOW_ON <- paste("among S and its four floor-pair siblings, the highest chance-corrected",
                   "recall of the reference stems under 10 m on the calibration plots at",
                   "native density (ties to the smaller zmin, then the smaller",
                   "zmin_surface); none when that is S")
CD_READING_TEXT <- paste(
  "Reading of a contrast's ΔcF1 (section 6 with the precedence of A2): \"better\"",
  "when the 95% interval lies above 0; else \"worse\" when it lies below 0 (with",
  "\"(within the 0.02 margin)\" when its lower bound is above -0.02); else \"not",
  "worse\" when its lower bound is above -0.02; else \"inconclusive\". A scope with",
  "fewer than 10 plots is reported and not read.")
CD_STANDS_TEXT <- paste(
  "Closed stands: the plots whose native cell has canopy cover >= 0.6; open stands:",
  "the others (A5; native density only).")
CD_DEFAULT_OUT <- file.path(.ROOT, "work", "multichm_depth_runs", "neon", "multichm_depth")
CD_CELLS_CONFIG <- "cells.config.json"
# The protocol document, which reproduces the specification and its addendum:
# the analyze stage stops without it (A7). The outputs print the label, never
# an absolute path. It is looked for as .find() looks for a script: under the
# repository root, then from the working directory and from two levels below
# the root (tests/testthat, where .ROOT falls back to the working directory);
# the root's path when none exists.
CD_PROTOCOL_LABEL <- "docs/multichm-depth-protocol.md"
CD_PROTOCOL       <- local({
  rel <- file.path("docs", "multichm-depth-protocol.md")
  hit <- Find(file.exists, c(file.path(.ROOT, rel), rel, file.path("..", "..", rel)))
  if (length(hit)) hit else file.path(.ROOT, rel)
})
# The sha256 of the two working files the protocol document reproduces, the
# specification (SPEC.txt) and its addendum (SPEC_ADDENDUM_1.txt), as the run
# of record wrote them; the document must quote both (cd_spec_record).
CD_SPEC_SHA256     <- "671ca6aac794ba8ae34688d75ae1717bc054d53265fd82791ef17bce186fbc4a"
CD_ADDENDUM_SHA256 <- "e9b854f821f2956538640057de6ff10af4a7654aa4fa2da1b8c532cd483924e7"

## ---- arguments ----------------------------------------------------------------------------
# The headline split (A1): the seed and calibration fraction the gated study
# recorded in its declared_config.json (seed 1, frac 0.5). It is read from that
# file, never taken from an argument, so that no argument can move a validation
# plot into the cells a blind run scores. Stops when the file or a field is
# missing or invalid. Returns list(seed, frac, file).
cd_headline_split <- function(gated) {
  f <- file.path(gated, "declared_config.json")
  if (!file.exists(f))
    stop("no gated declared configuration at ", f, " (the headline split's seed and frac ",
         "are read from it)", call. = FALSE)
  r <- jsonlite::read_json(f, simplifyVector = TRUE)
  one <- function(k) {
    v <- r[[k]]
    if (is.null(v) || length(v) != 1L || !is.numeric(v) || !is.finite(v))
      stop(f, " lacks a numeric `", k, "` (the headline split's ", k, ")", call. = FALSE)
    as.numeric(v)
  }
  seed <- one("seed"); frac <- one("frac")
  if (seed != round(seed) || frac <= 0 || frac >= 1)
    stop(f, ": the headline split needs a whole seed and a frac in (0, 1)", call. = FALSE)
  list(seed = as.integer(seed), frac = frac, file = f)
}

# KEY=VALUE positional arguments -> the run's settings. d is the job directory
# the gated study ran in (stems, plot centroids, frozen root). S$SEED and S$FRAC
# always hold the headline split's values (cd_headline_split); SEED= and FRAC=
# are accepted only when they repeat them, whatever UNBLIND is (A1). SEEDS= (the
# splits of analysis f) is free.
cd_settings <- function(args = commandArgs(TRUE), d = .job_dir()) {
  a <- strsplit(args, "=")
  # [[ ]] below, never $: `$` would partially match SEED to SEEDS
  A <- stats::setNames(lapply(a, `[`, 2), vapply(a, `[`, character(1), 1))
  given <- function(k) !is.null(A[[k]]) && !is.na(A[[k]]) && nzchar(A[[k]])
  split <- function(x, default) if (is.null(x)) default else strsplit(x, ",")[[1]]
  num <- function(x, default) if (is.null(x)) default else suppressWarnings(as.numeric(x))
  root <- frozen_root(d, A[["FROZEN_ROOT"]])
  gated <- if (given("GATED")) A[["GATED"]] else file.path(d, "neon", "multichm_gated")
  H <- cd_headline_split(gated)
  for (k in c("SEED", "FRAC")) if (!is.null(A[[k]])) {
    v <- num(A[[k]], NA)
    want <- if (k == "SEED") H$seed else H$frac
    if (is.na(v) || v != want)
      stop(sprintf(paste("%s=%s: the headline split is the gated study's (seed %d, frac %g,",
                         "from %s) and is not an argument; %s= may only repeat %g. Use",
                         "SEEDS= for the splits of analysis f."), k, A[[k]], H$seed, H$frac,
                   H$file, k, want), call. = FALSE)
  }
  S <- list(
    A = A, d = d, root = root,
    STAGE = if (given("STAGE")) A[["STAGE"]] else "all",
    SITES = split(A[["SITES"]], CV_FIVE),
    RUNGS = split(A[["RUNGS"]], cv_root_rungs(root)),
    POP = if (given("POP")) A[["POP"]] else "adopted",
    SEED = H$seed,
    FRAC = H$frac,
    SEEDS = suppressWarnings(as.integer(split(A[["SEEDS"]], as.character(1:200)))),
    N_BOOT = as.integer(num(A[["N_BOOT"]], MT_N_BOOT)),
    CORES = as.integer(num(A[["CORES"]], CD_MAX_CORES)),
    K_arg = if (given("K")) as.integer(num(A[["K"]], NA)) else NULL,
    TOL_arg = if (given("TOL")) num(A[["TOL"]], NA) else NULL,
    UNBLIND_arg = if (given("UNBLIND")) A[["UNBLIND"]] else "0",
    GATED = gated,
    OUT = if (given("OUT")) A[["OUT"]] else CD_DEFAULT_OUT)
  if (!S$STAGE %in% c("all", "features", "score", "analyze"))
    stop("STAGE must be all, features, score or analyze", call. = FALSE)
  if (!S$UNBLIND_arg %in% c("0", "1")) stop("UNBLIND must be 0 or 1", call. = FALSE)
  S$UNBLIND <- identical(S$UNBLIND_arg, "1")
  held <- cv_root_rungs(root)
  if (!all(S$RUNGS %in% held))
    stop("RUNGS must be among ", paste(held, collapse = ","), " (the rungs of the frozen root ",
         root, ")", call. = FALSE)
  if (!"native" %in% S$RUNGS) stop("RUNGS must include native (the selection's rung)",
                                   call. = FALSE)
  if (!all(S$SITES %in% CV_FIVE)) stop("SITES must be among ", paste(CV_FIVE, collapse = ","),
                                       call. = FALSE)
  if (anyNA(c(S$SEED, S$FRAC, S$SEEDS, S$N_BOOT, S$CORES)) || !length(S$SEEDS) ||
      S$FRAC <= 0 || S$FRAC >= 1 || S$N_BOOT < 1 || S$CORES < 1)
    stop("invalid numeric argument (SEEDS, N_BOOT >= 1, CORES >= 1)", call. = FALSE)
  if (S$CORES > CD_MAX_CORES)
    stop(sprintf("CORES must be at most %d (R worker processes)", CD_MAX_CORES), call. = FALSE)
  if ((!is.null(S$K_arg) && is.na(S$K_arg)) || (!is.null(S$TOL_arg) && is.na(S$TOL_arg)))
    stop("K and TOL must be numbers", call. = FALSE)
  S
}

## ---- the blind rule (pure) ----------------------------------------------------------------
# The plots ("site::plot") whose cells may be scored or read: the calibration
# plots of the headline split while blind, every plot of the split once
# unblinded.
cd_allowed_plots <- function(sp, unblind = FALSE)
  if (isTRUE(unblind)) unique(c(sp$calib, sp$valid)) else unique(sp$calib)

# The rows of `cells` (site, plot, ...) an analysis may read: those of the
# allowed plots.
cd_blind_filter <- function(cells, sp, unblind = FALSE)
  cells[cv_ids(cells) %in% cd_allowed_plots(sp, unblind), , drop = FALSE]

# The plots the score stage scores now, of the candidate plots `ids`: blind,
# the calibration plots (all of them again, so a blind re-run rebuilds the
# calibration cells); unblinded, every plot not already scored (`done`). A
# plot outside the split stops (it would be neither calibration nor
# validation).
cd_plots_to_score <- function(ids, sp, unblind = FALSE, done = character()) {
  stray <- setdiff(ids, c(sp$calib, sp$valid))
  if (length(stray))
    stop("plots outside the split: ", paste(utils::head(stray, 5), collapse = ", "), call. = FALSE)
  todo <- ids[ids %in% cd_allowed_plots(sp, unblind)]
  if (isTRUE(unblind)) todo <- setdiff(todo, done)
  unique(todo)
}

# Stops when `cells` hold a row of a plot the blind rule does not allow.
cd_assert_blind <- function(cells, sp, unblind, what = "cells") {
  bad <- setdiff(unique(cv_ids(cells)), cd_allowed_plots(sp, unblind))
  if (length(bad))
    stop(sprintf("BLIND RULE: %s hold %d plots outside the allowed set (first %s)", what,
                 length(bad), bad[1]), call. = FALSE)
  invisible(TRUE)
}

## ---- reference configurations, grid and constants digests ---------------------------------
# The four gated configurations re-derived from the cached candidates, named by
# their gated labels (CD_REFERENCES).
cd_ref_configs <- function() {
  cf <- list(MCG_STOCK, mcg_config(5, 0, 0.6, TRUE), mcg_config(5, 0.75, 0.6, TRUE), MCG_DECLARED)
  lab <- vapply(cf, mcg_config_label, character(1))
  if (!identical(lab, CD_REFERENCES))
    stop("the gated library labels the reference configurations ", paste(lab, collapse = ","),
         call. = FALSE)
  stats::setNames(cf, lab)
}

# Their config_ids in the gated grid (mcg_grid()).
cd_gated_ids <- function() {
  g <- mcg_grid()
  id <- g$config_id[match(CD_REFERENCES, g$label)]
  if (anyNA(id)) stop("a reference configuration is not in the gated grid", call. = FALSE)
  stats::setNames(as.integer(id), CD_REFERENCES)
}

cd_grid_digest <- function(grid = mcd_grid()) {
  g17 <- function(v) sprintf("%.17g", as.numeric(v))
  digest::digest(paste(grid$config_id, g17(grid$depth_max), g17(grid$near_2d), g17(grid$zmin),
                       g17(grid$zmin_surface), as.logical(grid$lit_union), g17(grid$cover_min),
                       grid$label, sep = ",", collapse = "\n"),
                 algo = "sha256", serialize = FALSE)
}

cd_constants_digest <- function(k = mcd_constants())
  digest::digest(paste(names(k), sprintf("%.17g", unlist(k)), sep = "=", collapse = ";"),
                 algo = "sha256", serialize = FALSE)

cd_file_sha <- function(f) if (file.exists(f)) digest::digest(file = f, algo = "sha256") else NA

# The specification and its addendum (A7, A9) for the outputs' provenance: the
# sha256 of the two working files (CD_SPEC_SHA256, CD_ADDENDUM_SHA256, the values
# the run of record wrote), the protocol document that reproduces them (its
# repository path, CD_PROTOCOL_LABEL) and the document's own sha256. Stops when
# the document is missing, so no output names a document that is not there,
# and when its text does not quote both working files' hashes, so the constants
# and the document cannot drift apart.
cd_spec_record <- function(protocol = CD_PROTOCOL) {
  if (!file.exists(protocol))
    stop("the analyze stage needs the protocol document (the specification and its ",
         "addendum); not found: ", protocol, call. = FALSE)
  txt <- paste(readLines(protocol, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  want <- c(specification = CD_SPEC_SHA256, addendum = CD_ADDENDUM_SHA256)
  miss <- names(want)[!vapply(want, grepl, logical(1), x = txt, fixed = TRUE)]
  if (length(miss))
    stop(sprintf("%s does not quote the sha256 of the %s (%s); the protocol document and the ",
                 protocol, paste(miss, collapse = " and "),
                 paste(want[miss], collapse = ", ")),
         "driver's hashes must agree", call. = FALSE)
  list(specification_sha256 = CD_SPEC_SHA256, addendum_sha256 = CD_ADDENDUM_SHA256,
       protocol = CD_PROTOCOL_LABEL, protocol_sha256 = cd_file_sha(protocol))
}

## ---- the gated study's run (read only) ----------------------------------------------------
# Its record (cells.config.json): K and TOL, checked against the population,
# the frozen root and the current gated grid (the reference labels must mean
# what they meant when the gated cells were scored).
cd_read_gated <- function(S) {
  f <- file.path(S$GATED, "cells.config.json")
  if (!file.exists(f)) stop("no gated cells record at ", f, call. = FALSE)
  r <- jsonlite::read_json(f, simplifyVector = TRUE)
  miss <- setdiff(c("K", "tol", "population", "clip_manifest_sha256", "grid_sha256"), names(r))
  if (length(miss)) stop(f, " lacks ", paste(miss, collapse = ", "), call. = FALSE)
  if (!identical(r$population, S$POP))
    stop("the gated cells were scored for population ", r$population, ", not ", S$POP,
         call. = FALSE)
  if (!identical(r$clip_manifest_sha256, frozen_root_id(S$root)))
    stop("the gated cells were scored on another frozen root than ", S$root, call. = FALSE)
  if (!identical(r$grid_sha256, cv_grid_digest()))
    stop("the gated cells were scored on another grid than the current mcg_grid()",
         call. = FALSE)
  K <- as.integer(r$K); tol <- as.numeric(r$tol)
  if (!is.null(S$K_arg) && S$K_arg != K)
    stop(sprintf("K=%d differs from the gated cells' K = %d", S$K_arg, K), call. = FALSE)
  if (!is.null(S$TOL_arg) && S$TOL_arg != tol)
    stop(sprintf("TOL=%g differs from the gated cells' TOL = %g", S$TOL_arg, tol), call. = FALSE)
  if (K < 1L) stop("the gated cells have no null (K < 1)", call. = FALSE)
  list(record = r, K = K, tol = tol, out = normalizePath(S$GATED, mustWork = TRUE),
       cells_sha256 = cd_file_sha(file.path(S$GATED, "cells.csv")),
       candidates_sha256 = cd_file_sha(file.path(S$GATED, "candidates.csv")))
}

# The gated candidates index of the requested sites and rungs, checked as the
# gated study checks it (cv_read_index: population, root stamp, constants).
cd_read_gated_index <- function(S) {
  Sg <- list(CANDIDATES = S$GATED, OUT = S$GATED, root = S$root, POP = S$POP, SITES = S$SITES,
             RUNGS = S$RUNGS)
  idx <- cv_read_index(Sg)
  sk <- cv_read_skipped(Sg)
  if (nrow(sk)) cv_report_skipped(sk, "[gated]")
  idx
}

# The gated study's declared configuration record (its split's plot counts).
cd_gated_declared <- function(S) {
  f <- file.path(S$GATED, "declared_config.json")
  if (!file.exists(f)) stop("no gated declared configuration at ", f, call. = FALSE)
  jsonlite::read_json(f, simplifyVector = TRUE)
}

# The plot rows (identity and split strata only) of the gated cells.csv: the
# columns site, plot, plotType and the crown-class counts, nothing else.
cd_gated_plot_rows <- function(S) {
  x <- data.table::fread(file.path(S$GATED, "cells.csv"), select = CD_PLOT_COLS,
                         showProgress = FALSE)
  x <- unique(as.data.frame(x))
  x[x$site %in% S$SITES, , drop = FALSE]
}

# Rows of the gated cells.csv with config in `configs`, for the cells (site,
# plot, rung) of `keys`.
cd_gated_rows <- function(S, keys, configs) {
  x <- data.table::fread(file.path(S$GATED, "cells.csv"), colClasses = list(character = "rung"),
                         showProgress = FALSE)
  x <- x[x$config %in% configs]
  x <- x[paste(x$site, x$plot, x$rung) %in% keys]
  as.data.frame(x)
}

## ---- stems, plots and the split -----------------------------------------------------------
# The declared reference of each site (frozen_scope: the population's stem
# gate), as the gated score stage reads it.
cd_read_stems <- function(S, sites) {
  out <- list()
  for (site in sites) {
    gt <- read.csv(file.path(S$d, "neon", site, "ground_truth_stems.csv"),
                   stringsAsFactors = FALSE)
    fz <- frozen_scope(S$d, site, S$A, gt)
    if (!identical(normalizePath(fz$root, mustWork = FALSE),
                   normalizePath(S$root, mustWork = FALSE)))
      stop("frozen root mismatch: ", fz$root, " vs ", S$root, call. = FALSE)
    out[[site]] <- fz$gt
  }
  out
}

# The stems of a plot's core (the gated score stage's rule).
cd_core_stems <- function(gt, plot, cx, cy, half)
  gt[gt$plotID == plot & abs(gt$E - cx) <= half & abs(gt$N - cy) <= half, , drop = FALSE]

cd_class_counts <- function(st)
  vapply(CV_CLASSES, function(k) sum(st$crown_class == k, na.rm = TRUE), numeric(1))

# One job per plot of the index: its cells, core stems and crown-class counts.
cd_plot_jobs <- function(idx, stems) {
  keys <- unique(idx[c("site", "plot")])
  lapply(seq_len(nrow(keys)), function(i) {
    cells <- idx[idx$site == keys$site[i] & idx$plot == keys$plot[i], , drop = FALSE]
    c1 <- cells[1, ]
    st <- cd_core_stems(stems[[c1$site]], c1$plot, c1$cx, c1$cy, c1$half)
    list(site = c1$site, plot = c1$plot, plotType = c1$plotType, cx = c1$cx, cy = c1$cy,
         half = c1$half, cells = cells, stems = st, ncls = cd_class_counts(st))
  })
}

cd_plot_rows <- function(jobs)
  do.call(rbind, lapply(jobs, function(j) data.frame(
    site = j$site, plot = j$plot, plotType = j$plotType, n_dominant = j$ncls[["dominant"]],
    n_codominant = j$ncls[["codominant"]], n_intermediate = j$ncls[["intermediate"]],
    n_suppressed = j$ncls[["suppressed"]], stringsAsFactors = FALSE)))

cd_split_of <- function(plot_rows, seed, frac) cv_split(plot_rows, seed, frac)

# CHECK S2: the split made from this job directory's plots equals the gated
# study's (made from its cells.csv's plot rows), and, for the gated study's own
# seed, fraction and five sites, has its recorded numbers of calibration and
# validation plots. Stops otherwise; returns the split with its record.
cd_check_split <- function(mine, gated, declared = NULL, S) {
  same <- setequal(mine$calib, gated$calib) && setequal(mine$valid, gated$valid) &&
    length(mine$calib) == length(gated$calib) && length(mine$valid) == length(gated$valid)
  if (!same)
    stop(sprintf(paste("CHECK S2 failed: the split differs from the gated study's (%d / %d",
                       "calibration and %d / %d validation plots)"), length(mine$calib),
                 length(gated$calib), length(mine$valid), length(gated$valid)), call. = FALSE)
  counted <- !is.null(declared) && setequal(S$SITES, CV_FIVE) &&
    identical(as.integer(declared$seed), as.integer(S$SEED)) &&
    isTRUE(all.equal(as.numeric(declared$frac), S$FRAC))
  if (counted && (length(mine$calib) != declared$n_calibration_plots ||
                  length(mine$valid) != declared$n_validation_plots))
    stop(sprintf(paste("CHECK S2 failed: %d calibration and %d validation plots, the gated",
                       "study recorded %d and %d"), length(mine$calib), length(mine$valid),
                 declared$n_calibration_plots, declared$n_validation_plots), call. = FALSE)
  msg <- sprintf(paste("split seed %d, frac %g: %d calibration and %d validation plots,",
                       "equal to the gated study's%s"), S$SEED, S$FRAC, length(mine$calib),
                 length(mine$valid), if (counted) " (and to its declared_config.json counts)"
                 else "")
  cv_pass("CHECK S2: %s", msg)
  mine$record <- paste("pass:", msg)
  mine
}

# The split table written by the score stage (identity and strata only).
cd_split_table <- function(plot_rows, sp) {
  x <- plot_rows[CD_PLOT_COLS]
  x$split <- ifelse(cv_ids(x) %in% sp$calib, "calib", ifelse(cv_ids(x) %in% sp$valid,
                                                              "valid", NA))
  x[order(match(x$site, CV_FIVE), x$plot), , drop = FALSE]
}

# A digest of a plot set (its "site::plot" ids sorted in C order).
cd_plots_digest <- function(ids)
  digest::digest(paste(sort(unique(as.character(ids)), method = "radix"), collapse = "\n"),
                 algo = "sha256", serialize = FALSE)

# The split's plot sets as digests per site: list(<site> = list(
# calibration_sha256, validation_sha256)). cells.config.json records them, so
# the analyze stage and the UNBLIND=1 append can check the plot sets (A1),
# also for a run restricted to some sites, without the record naming a
# validation plot.
cd_split_digests <- function(sp) {
  site_of <- function(ids) sub("::.*", "", ids)
  sites <- intersect(CV_FIVE, unique(site_of(c(sp$calib, sp$valid))))
  sites <- c(sites, setdiff(unique(site_of(c(sp$calib, sp$valid))), sites))
  stats::setNames(lapply(sites, function(s)
    list(calibration_sha256 = cd_plots_digest(sp$calib[site_of(sp$calib) == s]),
         validation_sha256 = cd_plots_digest(sp$valid[site_of(sp$valid) == s]))), sites)
}

# The split of a cells record (cells.config.json, r) must be the headline
# split (A1): its seed and frac those of S (cd_headline_split), and, given the
# headline split sp, the calibration and validation plot sets of each of its
# sites. Stops otherwise.
cd_check_record_split <- function(r, S, sp = NULL, what = "the scored cells") {
  s <- r$split
  if (is.null(s) || is.null(s$seed) || is.null(s$frac))
    stop(what, " carry no record of their split; re-run STAGE=score", call. = FALSE)
  if (!isTRUE(as.numeric(s$seed) == S$SEED) || !isTRUE(as.numeric(s$frac) == S$FRAC))
    stop(sprintf(paste("%s were scored under split seed %s, frac %s, not the headline split's",
                       "(seed %d, frac %g); re-run STAGE=score"), what, format(s$seed),
                 format(s$frac), S$SEED, S$FRAC), call. = FALSE)
  if (!is.null(sp)) {
    if (is.null(s$plot_sets))
      stop(what, " carry no record of the split's plot sets; re-run STAGE=score", call. = FALSE)
    want <- cd_split_digests(sp)
    for (site in names(want)) {
      got <- s$plot_sets[[site]]
      if (is.null(got) || !identical(got$calibration_sha256, want[[site]]$calibration_sha256) ||
          !identical(got$validation_sha256, want[[site]]$validation_sha256))
        stop(what, " were scored under other calibration or validation plots of ", site,
             " than the headline split's; re-run STAGE=score", call. = FALSE)
    }
  }
  invisible(TRUE)
}

## ---- stage: features ----------------------------------------------------------------------
cd_feature_file <- function(fdir, site, plot, rung) file.path(fdir, cv_cell_file(site, plot, rung))

# Reads one cell's features and checks they belong to the cached candidates and
# were made with the current constants (A7): the file's constants stamp must
# equal cd_constants_digest() (a file written before the stamp existed has
# none and is refused), and its column radius must be mcd_col_radius(frdens),
# so features of other constants are never scored under this record.
cd_read_feature <- function(fdir, site, plot, rung, prep) {
  f <- cd_feature_file(fdir, site, plot, rung)
  if (!file.exists(f)) stop("no features at ", f, "; run STAGE=features", call. = FALSE)
  fe <- readRDS(f)
  if (!identical(c(fe$site, fe$plot, fe$rung), c(site, plot, rung)))
    stop("the features at ", f, " are of another cell", call. = FALSE)
  if (!identical(fe$constants_sha256, cd_constants_digest()))
    stop("the features at ", f, " carry no constants stamp or were made with other ",
         "constants than mcd_constants(); run STAGE=features", call. = FALSE)
  rc <- mcd_col_radius(fe$frdens)
  if (!identical(fe$r_col, rc) || !isTRUE(all(fe$feat$r_col == rc)))
    stop("the features at ", f, " have a column radius other than mcd_col_radius(frdens); ",
         "run STAGE=features", call. = FALSE)
  .mcd_check_feat(prep, fe$feat)
  fe
}

cd_q <- function(v, p) if (length(v)) unname(stats::quantile(v, p, type = 7)) else NA_real_

# One cell of the gated index: the frozen clip as cv_candidates_job() reads it,
# the checks, the features, the file. Returns the cell's features.csv row.
cd_features_cell <- function(m, root, cdir, fdir) {
  cell <- readRDS(file.path(cdir, m$file))
  meta <- cell$meta; prep <- cell$prep
  if (!identical(c(meta$site, meta$plot, meta$rung), c(m$site, m$plot, m$rung)))
    stop("the cached candidates ", m$file, " are of another cell", call. = FALSE)
  clip <- frozen_clip(NULL, m$site, m$plot, cv_rung_value(m$rung), m$cx, m$cy, m$half, root)
  if (is.null(clip)) stop("no frozen clip for ", m$file, call. = FALSE)
  # readLAS prints a progress line (spaces and carriage returns); kept out of the log
  utils::capture.output(las <- suppressWarnings(lidR::readLAS(clip$normalized)))
  np <- lidR::npoints(las)
  if (np <= 0) stop("the clip of ", m$file, " is empty", call. = FALSE)
  if (nrow(prep$cand) != m$n_cand)
    stop(sprintf("%s: %d cached candidates, the index records %d", m$file, nrow(prep$cand),
                 m$n_cand), call. = FALSE)
  if (!identical(clip$frdens, meta$frdens))
    stop(m$file, ": the clip's frdens differs from the cached cell's", call. = FALSE)
  feat <- mcd_features(prep$cand, las, clip$frdens)
  rc <- mcd_col_radius(clip$frdens)
  f <- cd_feature_file(fdir, m$site, m$plot, m$rung)
  tmp <- paste0(f, ".part")
  # the constants and their digest stamp the file (cd_read_feature checks them)
  saveRDS(list(site = m$site, plot = m$plot, rung = m$rung, gated_file = m$file,
               frdens = clip$frdens, r_col = rc, npoints = np, n_cand = nrow(feat),
               constants = mcd_constants(), constants_sha256 = cd_constants_digest(),
               feat = feat),
          tmp)
  if (!file.rename(tmp, f)) stop("could not write ", f, call. = FALSE)
  deep <- feat$layer > 1L
  dd <- feat$depth[deep]
  surf_gain <- (feat$zrep - feat$ztop)[!deep]
  data.frame(site = m$site, plot = m$plot, plotType = m$plotType, rung = m$rung,
             file = basename(f), npoints = np, frdens = clip$frdens, r_col = rc,
             cover = prep$cover, n_cand = nrow(feat), n_cand_index = m$n_cand,
             n_surface = sum(!deep), n_deeper = sum(deep),
             n_depth_negative = sum(feat$depth < 0),
             depth_min = if (length(dd)) min(dd) else NA_real_, depth_q05 = cd_q(dd, 0.05),
             depth_q25 = cd_q(dd, 0.25), depth_q50 = cd_q(dd, 0.5), depth_q75 = cd_q(dd, 0.75),
             depth_q95 = cd_q(dd, 0.95), depth_max = if (length(dd)) max(dd) else NA_real_,
             n_deeper_depth_le_2 = sum(dd <= 2), n_deeper_depth_le_3 = sum(dd <= 3),
             n_deeper_depth_le_4 = sum(dd <= 4),
             n_zrep_above_ztop = sum(feat$zrep > feat$ztop),
             surface_zrep_gain_q50 = cd_q(surf_gain, 0.5),
             surface_zrep_gain_max = if (length(surf_gain)) max(surf_gain) else NA_real_,
             stringsAsFactors = FALSE)
}

cd_features_job <- function(j, root, cdir, fdir)
  do.call(rbind, lapply(seq_len(nrow(j$cells)), function(i)
    cd_features_cell(j$cells[i, ], root, cdir, fdir)))
cd_features_worker <- function(j, root, cdir, fdir)
  tryCatch(cd_features_job(j, root, cdir, fdir), error = function(e) {
    message("plot ", j$site, "/", j$plot, " failed: ", conditionMessage(e)); e })

cd_stage_features <- function(S) {
  idx <- cd_read_gated_index(S)
  cdir <- file.path(S$GATED, "candidates")
  fdir <- file.path(S$OUT, "features")
  frozen_stamp(fdir, S$root)
  keys <- unique(idx[c("site", "plot")])
  jobs <- lapply(seq_len(nrow(keys)), function(i) list(
    site = keys$site[i], plot = keys$plot[i],
    cells = idx[idx$site == keys$site[i] & idx$plot == keys$plot[i], , drop = FALSE]))
  cat(sprintf("[features] %d cells of %d plots (%s), rungs %s, %d workers\n", nrow(idx),
              length(jobs), paste(S$SITES, collapse = ","), paste(S$RUNGS, collapse = ","),
              min(S$CORES, length(jobs))))
  t0 <- Sys.time()
  res <- plot_lapply(jobs, cd_features_worker, root = S$root, cdir = cdir, fdir = fdir,
                     mc.cores = S$CORES)
  stop_failed_plots(vapply(jobs, function(j) paste(j$site, j$plot, sep = "/"), ""), res)
  tab <- do.call(rbind, res)
  rownames(tab) <- NULL
  if (nrow(tab) != nrow(idx)) stop("features: ", nrow(tab), " cells of ", nrow(idx), call. = FALSE)
  write.csv(tab, file.path(S$OUT, "features.csv"), row.names = FALSE)
  cat(sprintf(paste("[features] %d cells in %.1f min: %d candidates (%d deeper), npoints > 0 and",
                    "n_cand as indexed in all; depth < 0 for %d candidates -> %s\n"),
              nrow(tab), as.numeric(difftime(Sys.time(), t0, units = "mins")), sum(tab$n_cand),
              sum(tab$n_deeper), sum(tab$n_depth_negative), file.path(S$OUT, "features.csv")))
  invisible(tab)
}

# The features index, checked against the gated index (every cell present).
cd_read_features <- function(S, idx) {
  f <- file.path(S$OUT, "features.csv")
  if (!file.exists(f)) stop("no features index at ", f, "; run STAGE=features", call. = FALSE)
  frozen_stamp_check(file.path(S$OUT, "features"), S$root)
  fx <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  miss <- setdiff(paste(idx$site, idx$plot, idx$rung), paste(fx$site, fx$plot, fx$rung))
  if (length(miss))
    stop(length(miss), " cells lack features (first ", miss[1], "); run STAGE=features",
         call. = FALSE)
  fx
}

## ---- stage: score -------------------------------------------------------------------------
# The lead columns of one cell's rows: the gated row's stand columns, the
# family, the configuration and the crown-class counts.
cd_lead <- function(j, m, family, config, config_id, gated_config_id, grid_rows = NULL) {
  n <- length(config)
  pick <- function(k, na) if (is.null(grid_rows)) rep(na, n) else grid_rows[[k]]
  data.table::data.table(
    site = j$site, plot = j$plot, plotType = m$plotType, rung = m$rung, cover = m$cover,
    top_height = m$top_height, crown_spacing = as.numeric(m$crown_spacing), pdens = m$pdens,
    frdens = m$frdens, family = family, config = config, config_id = as.integer(config_id),
    gated_config_id = as.integer(gated_config_id),
    depth_max = pick("depth_max", NA_real_), near_2d = pick("near_2d", NA_real_),
    zmin = pick("zmin", NA_real_), zmin_surface = pick("zmin_surface", NA_real_),
    lit_union = pick("lit_union", NA), cover_min = pick("cover_min", NA_real_),
    n_dominant = j$ncls[["dominant"]], n_codominant = j$ncls[["codominant"]],
    n_intermediate = j$ncls[["intermediate"]], n_suppressed = j$ncls[["suppressed"]])
}

# The score memo's key of a detection set: x, y and z, so two sets that differ
# only in height (the matcher's height gate reads z) are scored apart.
cd_det_key <- function(det) digest::digest(list(det$x, det$y, det$z))

# A memoised scorer of one cell: fun(det) is called once per distinct detection
# set (cd_det_key) and its result reused for every configuration giving it.
cd_memo <- function(fun) {
  memo <- new.env(parent = emptyenv())
  function(det) {
    key <- cd_det_key(det)
    if (is.null(memo[[key]])) memo[[key]] <- fun(det)
    memo[[key]]
  }
}

# Every cell of one plot: each grid configuration (scored once per distinct
# detection set) and the four reference configurations.
cd_score_job <- function(j, grid, cdir, fdir, K, tol) {
  offs <- mcg_null_offsets(j$site, j$plot, j$half, tol = tol, k = K)
  dcfg <- lapply(seq_len(nrow(grid)), function(g) mcd_grid_config(grid, g))
  rcfg <- cd_ref_configs()
  gid <- cd_gated_ids()
  out <- list()
  for (i in seq_len(nrow(j$cells))) {
    m <- j$cells[i, ]
    cell <- readRDS(file.path(cdir, m$file))
    fe <- cd_read_feature(fdir, m$site, m$plot, m$rung, cell$prep)
    score <- cd_memo(function(det) mcg_score_cell(j$stems, det, m$cx, m$cy, m$half, offs,
                                                  tol = tol))
    sd <- lapply(dcfg, function(cf) score(mcd_apply(cell$prep, fe$feat, cf)))
    sr <- lapply(rcfg, function(cf) score(mcg_apply(cell$prep, cf)))
    out[[length(out) + 1L]] <- cbind(
      cd_lead(j, m, "depth", grid$label, grid$config_id, NA_integer_, grid),
      data.table::rbindlist(sd))
    out[[length(out) + 1L]] <- cbind(
      cd_lead(j, m, "gated", names(rcfg), NA_integer_, gid[names(rcfg)]),
      data.table::rbindlist(sr))
  }
  as.data.frame(data.table::rbindlist(out))
}
cd_score_worker <- function(j, grid, cdir, fdir, K, tol)
  tryCatch(cd_score_job(j, grid, cdir, fdir, K, tol), error = function(e) {
    message("plot ", j$site, "/", j$plot, " failed: ", conditionMessage(e)); e })

# CHECK S1 (pure): every re-derived reference row of `mine` against the gated
# row of the same cell and label: the observed count columns exactly, the null
# means within `tol`. Returns list(n, n_bad, bad, max_null_diff).
CD_OBS_COLS  <- c("n_ref", "n_over", "n_under", "n_det", "TP", "tp_core", "tp_over", "tp_under")
CD_NULL_COLS <- c("n_det0", "TP0", "tp_core0", "tp_over0", "tp_under0")
cd_s1_compare <- function(mine, gated, tol = 1e-9) {
  key <- c("site", "plot", "rung", "config")
  a <- as.data.frame(mine)[c(key, CD_OBS_COLS, CD_NULL_COLS)]
  b <- as.data.frame(gated)[c(key, CD_OBS_COLS, CD_NULL_COLS)]
  if (anyDuplicated(do.call(paste, a[key])) || anyDuplicated(do.call(paste, b[key])))
    stop("CHECK S1: duplicate rows of a cell and label", call. = FALSE)
  m <- merge(a, b, by = key, all = TRUE, suffixes = c("", ".gated"))
  bad <- rep(FALSE, nrow(m))
  for (k in CD_OBS_COLS) {
    x <- m[[k]]; y <- m[[paste0(k, ".gated")]]
    bad <- bad | is.na(x) | is.na(y) | x != y
  }
  nd <- 0
  for (k in CD_NULL_COLS) {
    x <- m[[k]]; y <- m[[paste0(k, ".gated")]]
    d <- abs(x - y)
    bad <- bad | xor(is.na(x), is.na(y)) | (!is.na(d) & d > tol)
    if (any(!is.na(d))) nd <- max(nd, d, na.rm = TRUE)
  }
  list(n = nrow(m), n_bad = sum(bad), bad = m[bad, , drop = FALSE], max_null_diff = nd)
}

# chm_vwf rows of the gated cells.csv in this study's columns.
cd_chm_rows <- function(g) {
  if (!nrow(g)) return(NULL)
  ids <- cv_ids(g)
  out <- data.frame(site = g$site, plot = g$plot, plotType = g$plotType, rung = g$rung,
                    cover = g$cover, top_height = g$top_height,
                    crown_spacing = as.numeric(g$crown_spacing), pdens = g$pdens,
                    frdens = g$frdens, family = "chm_vwf", config = CD_CHM,
                    config_id = NA_integer_, gated_config_id = NA_integer_,
                    depth_max = NA_real_, near_2d = NA_real_, zmin = NA_real_,
                    zmin_surface = NA_real_, lit_union = NA, cover_min = NA_real_,
                    n_dominant = g$n_dominant, n_codominant = g$n_codominant,
                    n_intermediate = g$n_intermediate, n_suppressed = g$n_suppressed,
                    stringsAsFactors = FALSE)
  cbind(out, g[MCG_COUNT_COLS])
}

cd_order_cells <- function(cells) {
  o <- order(match(cells$site, CV_FIVE), cells$plot, match(cells$rung, CV_RUNGS),
             match(cells$family, CD_FAMILIES), cells$config_id, cells$gated_config_id,
             na.last = TRUE)
  x <- cells[o, c(CD_LEAD_COLS, MCG_COUNT_COLS), drop = FALSE]
  rownames(x) <- NULL
  x
}

cd_read_cells_file <- function(f) {
  if (!file.exists(f)) stop("no scored cells at ", f, "; run STAGE=score", call. = FALSE)
  read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
}

cd_cells_config <- function(S, G, sp, blind, cells, checks) {
  list(K = G$K, tol = G$tol, population = S$POP,
       clip_manifest_sha256 = frozen_root_id(S$root),
       root = normalizePath(S$root, mustWork = FALSE),
       job_dir = normalizePath(S$d, mustWork = FALSE),
       grid_sha256 = cd_grid_digest(), n_grid = nrow(mcd_grid()),
       constants = mcd_constants(), constants_sha256 = cd_constants_digest(),
       references = I(CD_REFERENCES), reference_gated_ids = as.list(cd_gated_ids()),
       chm_vwf = "rows copied from the gated cells.csv (not re-scored)",
       gated = list(out = G$out, cells_csv_sha256 = G$cells_sha256,
                    candidates_csv_sha256 = G$candidates_sha256, cells_config = G$record),
       split = list(seed = S$SEED, frac = S$FRAC, n_calibration = length(sp$calib),
                    n_validation = length(sp$valid),
                    source = "the gated study's declared_config.json (A1)",
                    plot_sets = cd_split_digests(sp)),
       blind = isTRUE(blind),
       scored = if (isTRUE(blind)) "the calibration plots of the headline split only" else
         "every plot (UNBLIND=1)",
       n_plots_scored = length(unique(cv_ids(cells))),
       n_cells_scored = length(unique(paste(cells$site, cells$plot, cells$rung))),
       sites = I(as.character(intersect(S$SITES, unique(cells$site)))),
       rungs = I(as.character(intersect(S$RUNGS, unique(cells$rung)))),
       checks = checks)
}

cd_write_json <- function(x, f)
  jsonlite::write_json(x, f, auto_unbox = TRUE, pretty = TRUE, digits = NA)

# The settings an earlier cells record (r, cells.config.json) does not share
# with this run (want: the current grid, constants, root, population, gated
# cells, K and TOL): their names, character(0) when its cells can be reused.
cd_prior_mismatch <- function(r, want) {
  got <- list(grid = r$grid_sha256, constants = r$constants_sha256,
              root = r$clip_manifest_sha256, population = r$population,
              gated_cells = r$gated$cells_csv_sha256,
              K = if (!is.null(r$K)) as.integer(r$K), TOL = if (!is.null(r$tol)) as.numeric(r$tol))
  names(want)[!vapply(names(want), function(k) identical(got[[k]], want[[k]]), logical(1))]
}

# UNBLIND=1: the cells of the earlier run in S$OUT that the remaining plots are
# appended to; NULL when S$OUT holds neither cells.csv nor its record (a first,
# unblinded run scores every plot). Earlier cells that cannot be reused stop
# the stage (A1): one of the two files without the other, another grid,
# constants, root, population, gated run, K or TOL (cd_prior_mismatch), another
# split (cd_check_record_split: seed, frac and plot sets), or rows outside the
# plots their record allows. The stage never falls back to rescoring every plot
# under another split or setting.
cd_prior_cells <- function(S, G, sp) {
  cfgf <- file.path(S$OUT, CD_CELLS_CONFIG); cellf <- file.path(S$OUT, "cells.csv")
  if (!file.exists(cfgf) && !file.exists(cellf)) return(NULL)
  if (!file.exists(cfgf) || !file.exists(cellf))
    stop("UNBLIND=1: ", if (file.exists(cellf)) cellf else cfgf, " is there without ",
         if (file.exists(cellf)) cfgf else cellf, "; re-run the blind score stage (UNBLIND=0)",
         call. = FALSE)
  r <- jsonlite::read_json(cfgf, simplifyVector = TRUE)
  bad <- cd_prior_mismatch(r, list(grid = cd_grid_digest(), constants = cd_constants_digest(),
                                   root = frozen_root_id(S$root), population = S$POP,
                                   gated_cells = G$cells_sha256, K = G$K, TOL = G$tol))
  if (length(bad))
    stop("UNBLIND=1: the earlier cells at ", cellf, " were scored with another ",
         paste(bad, collapse = ", "), "; they are not appended to and nothing is rescored. ",
         "Re-run the blind score stage (UNBLIND=0) first", call. = FALSE)
  cd_check_record_split(r, S, sp, "UNBLIND=1: the earlier cells")
  prior <- cd_read_cells_file(cellf)
  cd_assert_blind(prior, sp, !isTRUE(r$blind), "the earlier cells")
  prior
}

cd_stage_score <- function(S) {
  G <- cd_read_gated(S)
  idx <- cd_read_gated_index(S)
  cd_read_features(S, idx)
  stems <- cd_read_stems(S, unique(idx$site))
  jobs <- cd_plot_jobs(idx, stems)
  pr <- cd_plot_rows(jobs)
  sp <- cd_check_split(cd_split_of(pr, S$SEED, S$FRAC),
                       cd_split_of(cd_gated_plot_rows(S), S$SEED, S$FRAC),
                       cd_gated_declared(S), S)
  write.csv(cd_split_table(pr, sp), file.path(S$OUT, "split.csv"), row.names = FALSE)
  cfgf <- file.path(S$OUT, CD_CELLS_CONFIG); cellf <- file.path(S$OUT, "cells.csv")
  # UNBLIND=1 appends the remaining plots to the calibration cells of an
  # earlier blind run (cd_prior_cells; it stops rather than rescoring)
  prior <- if (S$UNBLIND) cd_prior_cells(S, G, sp) else NULL
  ids <- vapply(jobs, function(j) paste(j$site, j$plot, sep = "::"), "")
  done <- if (is.null(prior)) character() else unique(cv_ids(prior))
  todo <- cd_plots_to_score(ids, sp, S$UNBLIND, done)
  if (!length(todo)) stop("nothing to score: every allowed plot is scored already", call. = FALSE)
  grid <- mcd_grid()
  unlink(cfgf)                         # cells.csv and its record are written together
  cat(sprintf(paste("[score] %s: %d plots of %d (%d already scored) x %d configurations +",
                    "%d references + chm_vwf (copied), K = %d, TOL = %g, %d workers\n"),
              if (S$UNBLIND) "UNBLIND=1" else "BLIND (calibration plots only)", length(todo),
              length(ids), length(done), nrow(grid), length(CD_REFERENCES), G$K, G$tol,
              min(S$CORES, max(1L, length(todo)))))
  t0 <- Sys.time()
  sel_jobs <- jobs[ids %in% todo]
  res <- plot_lapply(sel_jobs, cd_score_worker, grid = grid,
                     cdir = file.path(S$GATED, "candidates"), fdir = file.path(S$OUT, "features"),
                     K = G$K, tol = G$tol, mc.cores = S$CORES)
  stop_failed_plots(vapply(sel_jobs, function(j) paste(j$site, j$plot, sep = "/"), ""), res)
  new <- as.data.frame(data.table::rbindlist(Filter(Negate(is.null), res)))
  cd_assert_blind(new, sp, S$UNBLIND, "the scored cells")
  keys <- unique(paste(new$site, new$plot, new$rung))
  ## CHECK S1
  gref <- cd_gated_rows(S, keys, c(CD_REFERENCES, CD_CHM))
  s1 <- cd_s1_compare(new[new$family == "gated", , drop = FALSE],
                      gref[gref$config %in% CD_REFERENCES, , drop = FALSE])
  if (s1$n != length(keys) * length(CD_REFERENCES) || s1$n_bad) {
    write.csv(s1$bad, file.path(S$OUT, "s1_failures.csv"), row.names = FALSE)
    stop(sprintf(paste("CHECK S1 failed: %d of %d reference rows differ from the gated cells.csv",
                       "(expected %d rows); see %s"), s1$n_bad, s1$n,
                 length(keys) * length(CD_REFERENCES), file.path(S$OUT, "s1_failures.csv")),
         call. = FALSE)
  }
  unlink(file.path(S$OUT, "s1_failures.csv"))
  cv_pass(paste("CHECK S1: %d re-derived reference rows (%d cells x %s) equal the gated",
                "cells.csv rows: observed counts exactly, null means within 1e-9 (max |diff| %.3g)"),
          s1$n, length(keys), paste(CD_REFERENCES, collapse = ", "), s1$max_null_diff)
  chm <- cd_chm_rows(gref[gref$config == CD_CHM, , drop = FALSE])
  cells <- cd_order_cells(rbind(if (!is.null(prior)) prior[c(CD_LEAD_COLS, MCG_COUNT_COLS)], new,
                                chm))
  blind <- !S$UNBLIND
  cd_assert_blind(cells, sp, S$UNBLIND, "cells.csv")
  write.csv(cells, cellf, row.names = FALSE)
  write.csv(grid, file.path(S$OUT, "grid.csv"), row.names = FALSE)
  checks <- list(
    S1 = sprintf("pass: %d reference rows of %d cells (max null diff %.3g)%s", s1$n,
                 length(keys), s1$max_null_diff,
                 if (length(done)) sprintf("; %d earlier plots checked before", length(done))
                 else ""),
    S2 = sp$record, chm_vwf_rows = sum(cells$family == "chm_vwf"))
  cd_write_json(cd_cells_config(S, G, sp, blind, cells, checks), cfgf)
  cat(sprintf("[score] %d rows (%d cells of %d plots) in %.1f min -> %s; blind %s\n",
              nrow(cells), length(unique(paste(cells$site, cells$plot, cells$rung))),
              length(unique(cv_ids(cells))),
              as.numeric(difftime(Sys.time(), t0, units = "mins")), cellf, blind))
  invisible(cells)
}

## ---- reading the scored cells -------------------------------------------------------------
# The analyze stage's record: the cells must have been scored on this grid,
# with these constants, on this root, from the gated run as it is now and under
# the headline split (A1: its seed and frac, and with sp its plot sets).
cd_read_cells_config <- function(S, G, sp = NULL) {
  f <- file.path(S$OUT, CD_CELLS_CONFIG)
  if (!file.exists(f)) stop("no record of how the cells were scored at ", f,
                            "; re-run STAGE=score", call. = FALSE)
  r <- jsonlite::read_json(f, simplifyVector = TRUE)
  if (!identical(r$grid_sha256, cd_grid_digest()))
    stop("the cells were scored on another grid than mcd_grid(); re-run STAGE=score",
         call. = FALSE)
  if (!identical(r$constants_sha256, cd_constants_digest()))
    stop("the cells were scored with other constants than mcd_constants(); re-run STAGE=score",
         call. = FALSE)
  if (!identical(r$clip_manifest_sha256, frozen_root_id(S$root)))
    stop("the cells were scored on another frozen root; re-run STAGE=score", call. = FALSE)
  if (!identical(r$population, S$POP))
    stop("the cells were scored for population ", r$population, call. = FALSE)
  if (!identical(r$gated$cells_csv_sha256, G$cells_sha256))
    stop("the gated cells.csv has changed since the cells were scored; re-run STAGE=score",
         call. = FALSE)
  if (as.integer(r$K) != G$K || as.numeric(r$tol) != G$tol)
    stop("the cells' K or TOL differ from the gated run's", call. = FALSE)
  cd_check_record_split(r, S, sp)
  r$K <- as.integer(r$K); r$tol <- as.numeric(r$tol)
  r
}

# The cells ("site plot rung", of `keys`) for which the gated cells.csv holds a
# chm_vwf row. Reads only the identity columns (site, plot, rung, config) of
# the gated file, no score, and keeps only `keys`.
cd_gated_chm_keys <- function(S, keys) {
  x <- data.table::fread(file.path(S$GATED, "cells.csv"),
                         select = c("site", "plot", "rung", "config"),
                         colClasses = list(character = "rung"), showProgress = FALSE)
  k <- paste(x$site, x$plot, x$rung)[x$config == CD_CHM]
  unique(k[k %in% keys])
}

# Every allowed cell of the index holds the 240 grid configurations (labels as
# the grid gives them for their config_id), the four references, and exactly
# one chm_vwf row when the gated cells.csv has one for it (chm_keys,
# cd_gated_chm_keys) and none otherwise; no row of another plot. Stops
# otherwise.
cd_check_cells <- function(cells, idx, grid, sp, unblind, chm_keys) {
  cd_assert_blind(cells, sp, unblind, "the analysed cells")
  allowed <- cd_allowed_plots(sp, unblind)
  want <- idx[cv_ids(idx) %in% allowed, , drop = FALSE]
  wk <- paste(want$site, want$plot, want$rung)
  d <- cells[cells$family == "depth", , drop = FALSE]
  if (any(grid$label[d$config_id] != d$config))
    stop("cells.csv labels a depth configuration otherwise than mcd_grid()", call. = FALSE)
  key <- paste(cells$site, cells$plot, cells$rung)
  nd <- table(factor(paste(d$site, d$plot, d$rung), levels = wk))
  ng <- table(factor(key[cells$family == "gated"], levels = wk))
  nc <- table(factor(key[cells$family == "chm_vwf"], levels = wk))
  if (any(nd != nrow(grid)) || any(ng != length(CD_REFERENCES)))
    stop(sprintf(paste("cells.csv is incomplete: %d of %d cells lack grid rows and %d lack",
                       "reference rows; re-run STAGE=score"), sum(nd != nrow(grid)), length(wk),
                 sum(ng != length(CD_REFERENCES))), call. = FALSE)
  bad <- as.integer(nc) != as.integer(wk %in% chm_keys)
  if (any(bad))
    stop(sprintf(paste("cells.csv holds a chm_vwf row count other than the gated cells.csv's",
                       "(one where it has one, none otherwise) in %d of %d cells (first %s);",
                       "re-run STAGE=score"), sum(bad), length(wk), wk[bad][1]), call. = FALSE)
  invisible(TRUE)
}

## ---- selection and ranking (pure) ---------------------------------------------------------
# Select on the native depth rows of `plots` (those present at native) by pooled
# cF1, ties to the smaller config_id (mcg_select). Returns the configuration
# (its grid row), the plots, and the pooled scores of the selection, stock and
# the declared gated arm on them.
cd_select <- function(cells, plots, grid = mcd_grid()) {
  nat <- cells[cells$rung == "native" & cells$family == "depth", , drop = FALSE]
  plots <- intersect(unique(plots), unique(cv_ids(nat)))
  if (!length(plots)) stop("no plots to select on at native density", call. = FALSE)
  id <- mcg_select(nat, plots, CD_CRITERION)
  g <- grid[grid$config_id == id, , drop = FALSE]
  r <- cells[cells$rung == "native" & cv_ids(cells) %in% plots &
               cells$config %in% c(g$label, "stock", CD_DECLARED), , drop = FALSE]
  P <- mcg_pool(r, "config")
  if (any(P$n_cells != length(plots)))
    stop("cd_select: the selection, stock and the declared arm must cover every plot",
         call. = FALSE)
  list(config_id = as.integer(id), label = g$label, depth_max = g$depth_max,
       near_2d = g$near_2d, zmin = g$zmin, zmin_surface = g$zmin_surface,
       lit_union = as.logical(g$lit_union), cover_min = g$cover_min, plots = plots,
       selected = P[P$config == g$label, ], stock = P[P$config == "stock", ],
       declared = P[P$config == CD_DECLARED, ])
}

# A fixed grid configuration (config_id) in cd_select()'s form: its grid row,
# the native plots of `plots`, and the pooled scores of it, stock and the
# declared gated arm on them (S_low's selection row).
cd_config_of <- function(cells, plots, config_id, grid = mcd_grid()) {
  g <- grid[grid$config_id == config_id, , drop = FALSE]
  if (nrow(g) != 1L) stop("cd_config_of: config_id ", config_id, " is not in the grid",
                          call. = FALSE)
  nat <- cells[cells$rung == "native" & cells$family == "depth", , drop = FALSE]
  plots <- intersect(unique(plots), unique(cv_ids(nat)))
  r <- cells[cells$rung == "native" & cv_ids(cells) %in% plots &
               cells$config %in% c(g$label, "stock", CD_DECLARED), , drop = FALSE]
  P <- mcg_pool(r, "config")
  if (!length(plots) || nrow(P) != 3L || any(P$n_cells != length(plots)))
    stop("cd_config_of: the configuration, stock and the declared arm must cover every plot",
         call. = FALSE)
  list(config_id = as.integer(config_id), label = g$label, depth_max = g$depth_max,
       near_2d = g$near_2d, zmin = g$zmin, zmin_surface = g$zmin_surface,
       lit_union = as.logical(g$lit_union), cover_min = g$cover_min, plots = plots,
       selected = P[P$config == g$label, ], stock = P[P$config == "stock", ],
       declared = P[P$config == CD_DECLARED, ])
}

cd_selection_row <- function(sel, analysis, seed = NA_integer_, held_out_site = NA_character_,
                             n_valid = NA_integer_, criterion = CD_CRITERION)
  data.frame(analysis = analysis, seed = seed, held_out_site = held_out_site,
             criterion = criterion, config_id = sel$config_id, config = sel$label,
             depth_max = sel$depth_max, near_2d = sel$near_2d, zmin = sel$zmin,
             zmin_surface = sel$zmin_surface, lit_union = sel$lit_union,
             cover_min = sel$cover_min, n_calib_plots = length(sel$plots),
             n_valid_plots = n_valid,
             calib_cF1_selected = sel$selected$cF1, calib_cF1_declared = sel$declared$cF1,
             calib_cF1_stock = sel$stock$cF1,
             calib_F1_selected = sel$selected$F1, calib_F1_declared = sel$declared$F1,
             calib_F1_stock = sel$stock$F1,
             calib_recall_selected = sel$selected$recall,
             calib_precision_selected = sel$selected$precision, stringsAsFactors = FALSE)

# Every grid configuration's pooled scores on `plots` at native density, ranked
# by cF1 (1 = best; ties to the smaller config_id, mcg_select's rule), then the
# reference configurations' rows (rank NA). Stops when rank 1 is not the
# selection.
cd_grid_ranking <- function(cells, plots, grid, sel) {
  nat <- cells[cells$rung == "native" & cv_ids(cells) %in% plots, , drop = FALSE]
  P <- mcg_pool(nat[nat$family == "depth", , drop = FALSE], "config_id")
  P <- merge(grid, P, by = "config_id")
  P <- P[order(-P$cF1, P$config_id), , drop = FALSE]
  P$rank <- seq_len(nrow(P))
  if (P$config_id[1] != sel$config_id)
    stop("cd_grid_ranking: rank 1 is not the selection", call. = FALSE)
  P$family <- "depth"
  keep <- c("rank", "family", "config_id", "label", "depth_max", "near_2d", "zmin",
            "zmin_surface", "lit_union", "cover_min", "n_cells", MCG_COUNT_COLS, MCG_RATE_COLS)
  out <- P[keep]
  ref <- nat[nat$family != "depth", , drop = FALSE]
  if (nrow(ref)) {
    R <- mcg_pool(ref, "config")
    R$family <- ifelse(R$config == CD_CHM, "chm_vwf", "gated")
    R$label <- R$config
    for (k in setdiff(keep, names(R))) R[[k]] <- NA
    R <- R[match(intersect(c(CD_REFERENCES, CD_CHM), R$config), R$config), , drop = FALSE]
    out <- rbind(out, R[keep])
  }
  rownames(out) <- NULL
  out
}

# The selection's neighbours in the grid: S with one parameter (near_2d,
# depth_max, the floor pair, lit_union, cover_min) changed to each other value
# the grid holds, the rest kept. One row per neighbour: parameter, value (as the
# grid holds it; the floor pair as "zmin/zmin_surface"), config_id, label.
CD_PARAMS <- c("near_2d", "depth_max", "floor", "lit_union", "cover_min")
cd_component_neighbours <- function(config_id, grid = mcd_grid()) {
  key <- data.frame(near_2d = grid$near_2d, depth_max = grid$depth_max,
                    floor = sprintf("%g/%g", grid$zmin, grid$zmin_surface),
                    lit_union = as.character(grid$lit_union), cover_min = grid$cover_min,
                    stringsAsFactors = FALSE)
  s <- which(grid$config_id == config_id)
  if (length(s) != 1L) stop("cd_component_neighbours: config_id ", config_id, " is not in the grid",
                            call. = FALSE)
  out <- list()
  for (p in CD_PARAMS) {
    same <- Reduce(`&`, lapply(setdiff(CD_PARAMS, p), function(q) key[[q]] == key[[q]][s]))
    hit <- which(same & key[[p]] != key[[p]][s])
    if (length(hit))
      out[[length(out) + 1L]] <- data.frame(parameter = p, value = as.character(key[[p]][hit]),
                                            selected_value = as.character(key[[p]][s]),
                                            config_id = grid$config_id[hit],
                                            label = grid$label[hit], stringsAsFactors = FALSE)
  }
  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

## ---- contrasts (pure) ---------------------------------------------------------------------
cd_scopes <- function(sites) {
  s <- cv_scopes(sites)
  for (x in sites) if (!x %in% names(s)) s[[x]] <- x
  s
}
cd_in_scope <- function(ids, sites) ids[sub("::.*", "", ids) %in% sites]

# The closed and open stands among `plots` (A5), plot sets used at native
# density only: a plot is a closed stand when the cover of its native cell in
# `cells` is at least CD_CLOSED_COVER, an open stand otherwise (an unknown cover
# included: "the others"). A plot without a native cell is in neither. Named
# list (CD_STAND_SCOPES) of "site::plot" ids.
cd_stand_plots <- function(cells, plots) {
  nat <- cells[cells$rung == "native", c("site", "plot", "cover"), drop = FALSE]
  u <- unique(data.frame(id = cv_ids(nat), cover = as.numeric(nat$cover),
                         stringsAsFactors = FALSE))
  if (anyDuplicated(u$id))
    stop("cd_stand_plots: the native rows of a plot disagree on its cover", call. = FALSE)
  p <- intersect(unique(plots), u$id)
  closed <- u$id[!is.na(u$cover) & u$cover >= CD_CLOSED_COVER]
  stats::setNames(list(intersect(p, closed), setdiff(p, closed)), CD_STAND_SCOPES)
}

# Contrasts of configuration label_a on `plots` with the paired plot-bootstrap
# interval (cv_contrast_row): native density in every scope (all sites, each
# region, each site, then the closed and open stands of A5) against each of
# `refs`, then the decimated rungs in the all-sites and region scopes against
# each of `ladder_refs`. Rows are tagged `analysis` (native) and
# `ladder_analysis`, and carry the reading of A2 on cF1 (cd_add_verdicts).
# Returns list(native, ladder).
cd_contrast_set <- function(cells, plots, label_a, refs, ladder_refs, S, split, analysis,
                            ladder_analysis, boot_seed = MT_SEED) {
  sites <- intersect(S$SITES, unique(cells$site))
  scopes <- cd_scopes(sites)
  con <- function(p, rl, b, tag) cv_contrast_row(cells, p, rl, label_a, b, S$N_BOOT,
                                                 boot_seed, tag)
  nat <- list(); lad <- list()
  sets <- c(lapply(scopes, function(sc) cd_in_scope(plots, sc)), cd_stand_plots(cells, plots))
  for (sc in names(sets)) for (b in refs) {
    r <- con(sets[[sc]], "native", b, cv_tag(analysis, CD_CRITERION, split, sc, S$SEED))
    if (!is.null(r)) nat[[length(nat) + 1L]] <- r
  }
  main <- intersect(names(scopes), c(names(scopes)[1], names(MT_REGIONS)))
  for (rl in setdiff(intersect(S$RUNGS, unique(cells$rung)), "native"))
    for (sc in main) for (b in ladder_refs) {
      r <- con(cd_in_scope(plots, scopes[[sc]]), rl, b,
               cv_tag(ladder_analysis, CD_CRITERION, split, sc, S$SEED))
      if (!is.null(r)) lad[[length(lad) + 1L]] <- r
    }
  bind <- function(z) {
    z <- do.call(rbind, z)
    if (!is.null(z)) { rownames(z) <- NULL; z <- cd_add_verdicts(z) }
    z
  }
  list(native = bind(nat), ladder = bind(lad))
}

# The selection against each reference on `plots`: native density in every
# scope against every reference (the declared arm first), then the decimated
# rungs in the all-sites and region scopes against the declared arm and stock.
# Returns list(native, ladder).
cd_reference_contrasts <- function(cells, plots, sel, S, split, analysis = "reference",
                                   boot_seed = MT_SEED) {
  refs <- c(CD_DECLARED, setdiff(CD_REFERENCES, CD_DECLARED), CD_CHM)
  refs <- refs[refs %in% cells$config]
  cd_contrast_set(cells, plots, sel$label, refs, c(CD_DECLARED, "stock"), S, split, analysis,
                  "ladder", boot_seed)
}

# S_low (A4) against the declared arm, stock and the selection S on `plots`:
# the metrics of analysis a at native density in every scope (tag "low_floor")
# and down the ladder in the scopes of analysis d (tag "low_floor_ladder").
# NULL parts when there is no S_low.
cd_low_floor_contrasts <- function(cells, plots, slow, sel, S, split, boot_seed = MT_SEED) {
  if (is.null(slow)) return(list(native = NULL, ladder = NULL))
  refs <- c(CD_DECLARED, "stock", sel$label)
  cd_contrast_set(cells, plots, slow$label, refs, refs, S, split, CD_LOW_FLOOR,
                  paste0(CD_LOW_FLOOR, "_ladder"), boot_seed)
}

# The selection minus each neighbour (cd_component_neighbours) at native
# density on `plots`.
cd_component_rows <- function(cells, plots, sel, nb, S, split, boot_seed = MT_SEED) {
  out <- list()
  for (i in seq_len(nrow(nb))) {
    r <- cv_contrast_row(cells, plots, "native", sel$label, nb$label[i], S$N_BOOT, boot_seed,
                         cv_tag(paste0("component_", nb$parameter[i]), CD_CRITERION, split,
                                names(cd_scopes(intersect(S$SITES, unique(cells$site))))[1],
                                S$SEED))
    if (!is.null(r))
      out[[length(out) + 1L]] <- cbind(data.frame(parameter = nb$parameter[i],
                                                  value = nb$value[i],
                                                  selected_value = nb$selected_value[i],
                                                  stringsAsFactors = FALSE), r)
  }
  if (!length(out)) return(NULL)
  out <- do.call(rbind, out); rownames(out) <- NULL
  out
}

# The reading rule of section 6 with the precedence of A2: "undefined" without
# an interval; else "better" when the 95% interval lies above 0 (lo > 0); else
# "worse" when it lies below 0 (hi < 0), whatever its lower bound; else "not
# worse" when its lower bound is above -0.02; else "inconclusive".
cd_verdict <- function(lo, hi)
  ifelse(is.na(lo) | is.na(hi), "undefined",
         ifelse(lo > 0, "better", ifelse(hi < 0, "worse",
                                         ifelse(lo > CD_NOT_WORSE, "not worse",
                                                "inconclusive"))))
# The note the tables add to a "worse" whose lower bound is above -0.02 (A2),
# "" otherwise.
cd_verdict_note <- function(lo, hi)
  ifelse(cd_verdict(lo, hi) == "worse" & !is.na(lo) & lo > CD_NOT_WORSE, CD_MARGIN_NOTE, "")
# The reading of one contrast row: a scope of fewer than CD_MIN_READ plots is
# reported and not read (A2), every other one reads cd_verdict().
cd_contrast_verdict <- function(lo, hi, n_plots)
  ifelse(!is.na(n_plots) & n_plots < CD_MIN_READ, CD_NOT_READ, cd_verdict(lo, hi))
cd_below_zero <- function(hi) !is.na(hi) & hi < 0

# Every contrast row's reading on cF1: verdict_cF1 (cd_contrast_verdict),
# verdict_note_cF1 (the A2 margin note of a read "worse", else "") and
# below_zero_cF1 (the interval lies below 0).
cd_add_verdicts <- function(v) {
  if (is.null(v) || !nrow(v)) return(v)
  v$verdict_cF1 <- cd_contrast_verdict(v$lo_cF1, v$hi_cF1, v$n_plots)
  v$verdict_note_cF1 <- ifelse(v$verdict_cF1 == "worse", cd_verdict_note(v$lo_cF1, v$hi_cF1), "")
  v$below_zero_cF1 <- cd_below_zero(v$hi_cF1)
  v
}
cd_verdict_text <- function(verdict, note) trimws(paste(verdict, note))

# The guard of the lowest trees (section 6 and A3): flag_a, the fixed guard's
# flag (the raw-recall interval under 10 m lies below 0), with the
# chance-corrected interval [lo_c, hi_c] of the same contrast. "loses low
# trees" only when the chance-corrected interval lies below 0; a flag with a
# chance-corrected interval that does not lie below 0 reads "fewer chance
# matches, no detectable loss"; otherwise "no detectable loss of low trees".
cd_guard_reading <- function(flag_a, lo_c, hi_c)
  ifelse(is.na(lo_c) | is.na(hi_c), "undefined (no chance-corrected interval)",
         ifelse(hi_c < 0, "loses low trees",
                ifelse(flag_a, "fewer chance matches, no detectable loss",
                       "no detectable loss of low trees")))

# The reading of A4: (i) S_low minus declared in cF1 at native density over the
# five sites reads "better" or "not worse" (verdict_i, A2); (ii) the
# chance-corrected recall under 10 m of S_low minus S has an interval above 0
# (lo_ii > 0). Returns list(i, ii, sentence).
cd_low_floor_reading <- function(verdict_i, lo_ii) {
  i <- isTRUE(verdict_i %in% c("better", "not worse"))
  ii <- isTRUE(!is.na(lo_ii) && lo_ii > 0)
  list(i = i, ii = ii,
       sentence = if (i && ii) "S_low is offered as the lowest-tree variant" else
         if (i) paste("the floor is reported as a matter of what counts as a tree, not of",
                      "accuracy") else "no low-floor variant is offered")
}

## ---- per-stem matches ---------------------------------------------------------------------
# score_plot()'s matching (sweep_lib.R): the detections within the core
# expanded by the match radius, then greedy_match with the stems' heights and
# tol_z_up 8 as score_plot calls it. The index of each stem's detection in
# `det` (0 when unmatched).
.cd_match_index <- function(stems, det, cx, cy, half, tol) {
  reg <- max(tol)
  in_reg <- which(abs(det$x - cx) <= half + reg & abs(det$y - cy) <= half + reg)
  detr <- det[in_reg, , drop = FALSE]
  m <- greedy_match(stems$E, stems$N, detr$x, detr$y, tol, az = stems$height, bz = detr$z,
                    tol_z_up = 8)
  out <- integer(length(m))
  out[m > 0] <- in_reg[m[m > 0]]
  out
}

# One row per reference stem (in the order of `stems`): matched TRUE / FALSE
# with score_plot()'s matching, the matched detection's row in `det` (NA when
# unmatched) and its height. sum(matched) is score_plot()'s TP.
mcd_stem_matches <- function(stems, det, cx, cy, half, tol = 4) {
  k <- .cd_match_index(stems, det, cx, cy, half, tol)
  dz <- rep(NA_real_, length(k))
  dz[k > 0] <- det$z[k[k > 0]]
  data.frame(stem = seq_len(nrow(stems)), matched = k > 0,
             det = ifelse(k > 0, k, NA_integer_), det_z = dz)
}

# Each stem's mean match over the shifted copies of the detections (the
# benchmark's null, as mcg_score_cell shifts them): summed over stems it is the
# cell's TP0.
cd_null_matches <- function(stems, det, cx, cy, half, tol, offsets) {
  if (!length(offsets)) return(rep(NA_real_, nrow(stems)))
  acc <- numeric(nrow(stems))
  for (of in offsets)
    acc <- acc + (.cd_match_index(stems, shift_detections(det, cx, cy, half + tol, of), cx, cy,
                                  half, tol) > 0)
  acc / length(offsets)
}

# Field-height band of a reference stem: [0,5), [5,10), [10,20), [20,Inf), and
# "unknown" for a missing, negative or infinite height.
cd_band <- function(h) {
  h <- suppressWarnings(as.numeric(h))
  b <- rep("unknown", length(h))
  ok <- is.finite(h) & h >= 0
  b[ok] <- as.character(cut(h[ok], CD_BAND_BREAKS, right = FALSE, labels = CD_BANDS[1:4]))
  b
}
cd_class <- function(cc) {
  x <- as.character(cc)
  x[is.na(x) | !x %in% CV_CLASSES] <- "unknown"
  x
}

# The detections of one configuration on a prepared clip with the layer of each:
# cf is list(kind = "depth" | "gated", cfg). A depth configuration's rows are
# mcd_apply()'s (checked identical), a gated one's mcg_apply()'s, whose layer is
# read from the candidate of the same X, Y (candidates are unique by X, Y).
cd_detections <- function(prep, feat, cf, report = "z") {
  if (identical(cf$kind, "depth")) {
    acc <- mcd_accepted(prep, feat, cf$cfg)
    C <- data.table::as.data.table(feat)[acc]
    data.table::setorderv(C, "Z", order = -1L)
    det <- data.frame(x = as.numeric(C$X), y = as.numeric(C$Y),
                      z = as.numeric(if (report == "z") C$Z else C$zrep))
    if (!identical(det, mcd_apply(prep, feat, cf$cfg, report)))
      stop("cd_detections: the detections differ from mcd_apply()", call. = FALSE)
    return(list(det = det, layer = as.integer(C$layer)))
  }
  if (!identical(report, "z")) stop("cd_detections: a gated configuration reports z = Z",
                                    call. = FALSE)
  det <- mcg_apply(prep, cf$cfg)
  key <- function(x, y) paste(sprintf("%.17g", x), sprintf("%.17g", y))
  layer <- prep$cand$layer[match(key(det$x, det$y), key(prep$cand$X, prep$cand$Y))]
  list(det = det, layer = as.integer(layer))
}

# The configurations of the lowest-tree tables: stock, the declared gated arm,
# the selection S and S with each other floor pair of the grid.
cd_lowest_configs <- function(sel, grid = mcd_grid()) {
  out <- list(list(role = "stock", label = "stock", kind = "gated", cfg = MCG_STOCK),
              list(role = "declared", label = CD_DECLARED, kind = "gated", cfg = MCG_DECLARED),
              list(role = "selected", label = sel$label, kind = "depth",
                   cfg = mcd_grid_config(grid, which(grid$config_id == sel$config_id))))
  nb <- cd_component_neighbours(sel$config_id, grid)
  nb <- nb[nb$parameter == "floor", , drop = FALSE]
  for (i in seq_len(nrow(nb)))
    out[[length(out) + 1L]] <- list(role = paste0("floor_", nb$value[i]), label = nb$label[i],
                                    kind = "depth",
                                    cfg = mcd_grid_config(grid, which(grid$config_id ==
                                                                        nb$config_id[i])))
  out
}

# One native cell: per-stem matches and null means of each lowest-tree
# configuration, the selection's matched pairs reported with z = Z and z = zrep,
# and the selection reported with zrep scored like any configuration.
cd_stem_job <- function(j, cfgs, sel, cdir, fdir, K, tol) {
  cell <- readRDS(file.path(cdir, j$m$file))
  prep <- cell$prep
  feat <- cd_read_feature(fdir, j$site, j$plot, "native", prep)$feat
  st <- j$stems
  offs <- mcg_null_offsets(j$site, j$plot, j$half, tol = tol, k = K)
  base <- data.frame(site = j$site, plot = j$plot, stem_id = as.character(st$individualID),
                     height = suppressWarnings(as.numeric(st$height)),
                     crown_class = as.character(st$crown_class), stringsAsFactors = FALSE)
  base$band <- cd_band(base$height)
  base$class <- cd_class(base$crown_class)
  rows <- list()
  for (cf in cfgs) {
    d <- cd_detections(prep, feat, cf)
    mm <- mcd_stem_matches(st, d$det, j$cx, j$cy, j$half, tol)
    rows[[length(rows) + 1L]] <- cbind(
      base, role = cf$role, config = cf$label, matched = mm$matched,
      tp0 = cd_null_matches(st, d$det, j$cx, j$cy, j$half, tol, offs), det_z = mm$det_z,
      det_layer = d$layer[mm$det], stringsAsFactors = FALSE)
  }
  scf <- Filter(function(cf) identical(cf$role, "selected"), cfgs)[[1]]
  dz <- cd_detections(prep, feat, scf, "z"); dr <- cd_detections(prep, feat, scf, "zrep")
  if (!identical(dz$det[c("x", "y")], dr$det[c("x", "y")]))
    stop("the selection's detections differ between report z and zrep", call. = FALSE)
  mz <- mcd_stem_matches(st, dz$det, j$cx, j$cy, j$half, tol)
  mr <- mcd_stem_matches(st, dr$det, j$cx, j$cy, j$half, tol)
  pair <- function(report, mm, zsrc) {
    ok <- mm$matched & !is.na(base$height)
    i <- mm$det[ok]
    data.frame(site = rep(j$site, sum(ok)), plot = rep(j$plot, sum(ok)),
               stem_id = base$stem_id[ok], report = rep(report, sum(ok)),
               field_height = base$height[ok], det_z = zsrc[i], layer = dz$layer[i],
               layer_class = ifelse(dz$layer[i] == 1L, "surface", "deeper"),
               error = zsrc[i] - base$height[ok], stringsAsFactors = FALSE)
  }
  pairs <- rbind(pair("z", mz, dz$det$z), pair("zrep", mr, dr$det$z),
                 pair("zrep_on_z_matches", mz, dr$det$z))
  sc <- mcg_score_cell(st, dr$det, j$cx, j$cy, j$half, offs, tol = tol)
  g <- data.frame(depth_max = sel$depth_max, near_2d = sel$near_2d, zmin = sel$zmin,
                  zmin_surface = sel$zmin_surface, lit_union = sel$lit_union,
                  cover_min = sel$cover_min)
  zrep <- cbind(as.data.frame(cd_lead(j, j$m, "depth_zrep", paste0(sel$label, CD_ZREP),
                                      sel$config_id, NA_integer_, g)), sc)
  list(stems = do.call(rbind, rows), pairs = pairs, zrep = zrep,
       zrep_check = data.frame(site = j$site, plot = j$plot, TP = sc$TP,
                               matched = sum(mr$matched), n_ref = sc$n_ref, n_stems = nrow(st)))
}
cd_stem_worker <- function(j, cfgs, sel, cdir, fdir, K, tol)
  tryCatch(cd_stem_job(j, cfgs, sel, cdir, fdir, K, tol), error = function(e) {
    message("plot ", j$site, "/", j$plot, " failed: ", conditionMessage(e)); e })

cd_stem_jobs <- function(idx, stems, plots) {
  nat <- idx[idx$rung == "native" & cv_ids(idx) %in% plots, , drop = FALSE]
  lapply(seq_len(nrow(nat)), function(i) {
    m <- nat[i, ]
    st <- cd_core_stems(stems[[m$site]], m$plot, m$cx, m$cy, m$half)
    list(site = m$site, plot = m$plot, cx = m$cx, cy = m$cy, half = m$half, m = m, stems = st,
         ncls = cd_class_counts(st))
  })
}

# CHECK S3 (pure): for every cell and configuration of the stem table, the
# number of stems equals n_ref, sum(matched) equals TP of that row of `cells`
# (native) and the summed null means equal its TP0 within `tol`; for the
# selection reported with zrep, sum(matched) equals its own scored TP.
cd_s3_compare <- function(st, cells, zchk = NULL, tol = 1e-9) {
  a <- data.table::as.data.table(st)[, list(n = .N, matched = sum(matched), tp0 = sum(tp0)),
                                      by = c("site", "plot", "config")]
  r <- cells[cells$rung == "native", c("site", "plot", "config", "n_ref", "TP", "TP0")]
  m <- merge(as.data.frame(a), r, by = c("site", "plot", "config"), all.x = TRUE)
  bad <- is.na(m$TP) | m$matched != m$TP | m$n != m$n_ref | abs(m$tp0 - m$TP0) > tol
  zb <- if (is.null(zchk)) logical() else zchk$TP != zchk$matched | zchk$n_ref != zchk$n_stems
  list(n = nrow(m), n_bad = sum(bad), bad = m[bad, , drop = FALSE],
       max_tp0_diff = if (nrow(m)) max(abs(m$tp0 - m$TP0), na.rm = TRUE) else NA_real_,
       n_zrep = length(zb), n_zrep_bad = sum(zb))
}

## ---- lowest-tree and height tables (pure) -------------------------------------------------
cd_strata <- function()
  data.frame(type = c("all", rep("band", length(CD_BANDS)), "band_pooled",
                      rep("class", length(CD_CLASSES))),
             stratum = c("all", CD_BANDS, CD_LOW, CD_CLASSES), stringsAsFactors = FALSE)

# Per plot, configuration and stratum: stems n, matched TP, summed null means TP0.
cd_plot_counts <- function(st, plots) {
  st <- as.data.frame(st)[cv_ids(st) %in% plots, , drop = FALSE]
  base <- st[c("site", "plot", "config", "matched", "tp0")]
  low <- st$band %in% CD_BANDS[1:2]
  L <- data.table::rbindlist(list(
    cbind(base, type = "all", stratum = "all"),
    cbind(base, type = "band", stratum = st$band),
    cbind(base[low, , drop = FALSE], type = rep("band_pooled", sum(low)),
          stratum = rep(CD_LOW, sum(low))),
    cbind(base, type = "class", stratum = st$class)), use.names = TRUE)
  as.data.frame(L[, list(n = .N, TP = sum(matched), TP0 = sum(tp0)),
                  by = c("site", "plot", "config", "type", "stratum")])
}

cd_rec <- function(tp, n) ifelse(n > 0, tp / n, NA_real_)
cd_crec <- function(tp, tp0, n) ifelse(n - tp0 > 0, (tp - tp0) / (n - tp0), NA_real_)

# Pooled per configuration and stratum (summed counts): stems, matched, recall,
# TP0 and (TP - TP0) / (n - TP0), each rate with the 95% interval of the plot
# bootstrap cd_lowest_contrast() uses (the same weights: mt_plot_weights over
# `plots`, resampled within site, n_boot draws, seed; counts summed per draw)
# and its number of defined draws (A3.d). above_chance: the chance-corrected
# interval lies above 0, i.e. the configuration finds the stratum's trees above
# chance (FALSE when the interval is undefined).
cd_lowest_scores <- function(st, plots, split, n_boot = MT_N_BOOT, seed = MT_SEED) {
  plots <- unique(plots)
  pc <- cd_plot_counts(st, plots)
  pc$id <- paste(pc$site, pc$plot, sep = "::")
  W <- mt_plot_weights(sub("::.*", "", plots), sub("^[^:]*::", "", plots), n_boot, seed)
  ids <- rownames(W)
  dr <- function(v) drop(crossprod(W, v))
  roles <- unique(as.data.frame(st)[c("config", "role")])
  s <- cd_strata()
  out <- list()
  for (cfg in roles$config) for (k in seq_len(nrow(s))) {
    r <- pc[pc$config == cfg & pc$type == s$type[k] & pc$stratum == s$stratum[k], , drop = FALSE]
    n <- sum(r$n); tp <- sum(r$TP); tp0 <- sum(r$TP0)
    vec <- function(col) { v <- numeric(length(ids)); v[match(r$id, ids)] <- r[[col]]; v }
    nW <- dr(vec("n")); tW <- dr(vec("TP")); t0W <- dr(vec("TP0"))
    iv_r <- mt_interval(cd_rec(tW, nW))
    iv_c <- mt_interval(cd_crec(tW, t0W, nW))
    out[[length(out) + 1L]] <- data.frame(
      kind = "score", split = split, type = s$type[k], stratum = s$stratum[k],
      role = roles$role[match(cfg, roles$config)], config = cfg, n_plots = length(plots),
      stems = n, matched = tp, recall = cd_rec(tp, n), TP0 = tp0,
      cRecall = cd_crec(tp, tp0, n), recall_lo = iv_r$lower, recall_hi = iv_r$upper,
      recall_draws = iv_r$defined_draws, cRecall_lo = iv_c$lower, cRecall_hi = iv_c$upper,
      cRecall_draws = iv_c$defined_draws,
      above_chance = !is.na(iv_c$lower) & iv_c$lower > 0, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

# S_low (A4), from the per-stem matches `st` of `plots` (the calibration plots,
# native density): among the selection S and its four floor-pair siblings (S's
# other parameters kept, cd_component_neighbours), the configuration with the
# highest pooled chance-corrected recall of the reference stems under 10 m (the
# [0,10) stratum, (TP - TP0) / (n - TP0) from summed counts). Ties (within
# 1e-12, mcg_select's tolerance) go to the smaller zmin, then the smaller
# zmin_surface. NULL when that is S itself, or when no candidate has a defined
# value; otherwise S_low's grid row as a list (config_id, label, parameters)
# with `value` (its value) and `candidates` (the five configurations' values).
cd_low_floor <- function(st, plots, sel, grid = mcd_grid()) {
  nb <- cd_component_neighbours(sel$config_id, grid)
  ids <- c(sel$config_id, nb$config_id[nb$parameter == "floor"])
  g <- grid[match(ids, grid$config_id), , drop = FALSE]
  miss <- setdiff(g$label, unique(as.character(st$config)))
  if (length(miss))
    stop("cd_low_floor: the per-stem matches lack ", paste(miss, collapse = ", "), call. = FALSE)
  pc <- cd_plot_counts(st, plots)
  low <- pc[pc$type == "band_pooled" & pc$stratum == CD_LOW, , drop = FALSE]
  cr <- vapply(g$label, function(l) {
    r <- low[low$config == l, , drop = FALSE]
    cd_crec(sum(r$TP), sum(r$TP0), sum(r$n))
  }, numeric(1), USE.NAMES = FALSE)
  cand <- data.frame(config_id = g$config_id, label = g$label, zmin = g$zmin,
                     zmin_surface = g$zmin_surface, cRecall_under_10m = cr,
                     stringsAsFactors = FALSE)
  if (all(is.na(cr))) return(NULL)
  v <- ifelse(is.na(cr), -Inf, cr)
  top <- which(v >= max(v) - 1e-12)
  b <- top[order(g$zmin[top], g$zmin_surface[top])][1]
  if (g$config_id[b] == sel$config_id) return(NULL)
  list(config_id = as.integer(g$config_id[b]), label = g$label[b], depth_max = g$depth_max[b],
       near_2d = g$near_2d[b], zmin = g$zmin[b], zmin_surface = g$zmin_surface[b],
       lit_union = as.logical(g$lit_union[b]), cover_min = g$cover_min[b], value = cr[b],
       candidates = cand)
}

# config_a minus config_b per stratum on `plots`, with the paired plot-bootstrap
# interval (plots resampled within site, mt_plot_weights, as mcg_contrast does):
# recall and (TP - TP0) / (n - TP0); and the null recall TP0 / n of each side
# with its difference (A3.b: how much of a change in recall is chance).
cd_lowest_contrast <- function(st, plots, config_a, config_b, split, n_boot = MT_N_BOOT,
                               seed = MT_SEED) {
  plots <- unique(plots)
  W <- mt_plot_weights(sub("::.*", "", plots), sub("^[^:]*::", "", plots), n_boot, seed)
  ids <- rownames(W)
  pc <- cd_plot_counts(st, plots)
  pc$id <- paste(pc$site, pc$plot, sep = "::")
  s <- cd_strata()
  out <- list()
  for (k in seq_len(nrow(s))) {
    vec <- function(cfg, col) {
      r <- pc[pc$config == cfg & pc$type == s$type[k] & pc$stratum == s$stratum[k], ,
              drop = FALSE]
      v <- numeric(length(ids)); v[match(r$id, ids)] <- r[[col]]; v
    }
    n <- vec(config_a, "n")
    if (!identical(n, vec(config_b, "n")))
      stop("cd_lowest_contrast: the two configurations hold different stems", call. = FALSE)
    ta <- vec(config_a, "TP"); t0a <- vec(config_a, "TP0")
    tb <- vec(config_b, "TP"); t0b <- vec(config_b, "TP0")
    dr <- function(v) drop(crossprod(W, v))
    nW <- dr(n)
    rec_a <- cd_rec(sum(ta), sum(n)); rec_b <- cd_rec(sum(tb), sum(n))
    cr_a <- cd_crec(sum(ta), sum(t0a), sum(n)); cr_b <- cd_crec(sum(tb), sum(t0b), sum(n))
    iv_r <- mt_interval(cd_rec(dr(ta), nW) - cd_rec(dr(tb), nW))
    iv_c <- mt_interval(cd_crec(dr(ta), dr(t0a), nW) - cd_crec(dr(tb), dr(t0b), nW))
    nr_a <- cd_rec(sum(t0a), sum(n)); nr_b <- cd_rec(sum(t0b), sum(n))
    out[[length(out) + 1L]] <- data.frame(
      kind = "contrast", split = split, type = s$type[k], stratum = s$stratum[k],
      config_a = config_a, config_b = config_b, n_plots = length(ids), stems = sum(n),
      recall_a = rec_a, recall_b = rec_b, d_recall = rec_a - rec_b, lo_recall = iv_r$lower,
      hi_recall = iv_r$upper, cRecall_a = cr_a, cRecall_b = cr_b, d_cRecall = cr_a - cr_b,
      lo_cRecall = iv_c$lower, hi_cRecall = iv_c$upper, null_recall_a = nr_a,
      null_recall_b = nr_b, d_null_recall = nr_a - nr_b, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

# Height quantiles of the reference stems per site (and all sites): stems, with
# a field height, min, 1%, 5%, 10%, median (quantile type 7).
cd_stem_quantiles <- function(st, plots, split) {
  u <- as.data.frame(st)
  u <- u[u$role == "stock" & cv_ids(u) %in% plots, , drop = FALSE]
  one <- function(lab, h, n) {
    h <- h[!is.na(h)]
    q <- function(p) cd_q(h, p)
    data.frame(kind = "stem_heights", split = split, site = lab, stems = n,
               with_height = length(h), min = if (length(h)) min(h) else NA_real_,
               q01 = q(0.01), q05 = q(0.05), q10 = q(0.10), median = q(0.5),
               stringsAsFactors = FALSE)
  }
  sites <- intersect(CV_FIVE, unique(u$site))
  do.call(rbind, c(lapply(sites, function(s) one(s, u$height[u$site == s], sum(u$site == s))),
                   list(one("all", u$height, nrow(u)))))
}

# The lowest-tree tables of one split: scores of every configuration (with
# their intervals), S minus the declared arm and S minus stock, with S_low
# (slow_label, A4) S_low minus the declared arm, minus S and minus stock, and
# the stems' height quantiles.
cd_lowest_tables <- function(st, plots, split, sel_label, n_boot, seed = MT_SEED,
                             slow_label = NULL) {
  bind_fill <- function(z) as.data.frame(data.table::rbindlist(z, fill = TRUE))
  lo <- if (!is.null(slow_label))
    lapply(c(CD_DECLARED, sel_label, "stock"), function(b)
      cd_lowest_contrast(st, plots, slow_label, b, split, n_boot, seed))
  bind_fill(c(list(cd_lowest_scores(st, plots, split, n_boot, seed),
                   cd_lowest_contrast(st, plots, sel_label, CD_DECLARED, split, n_boot, seed),
                   cd_lowest_contrast(st, plots, sel_label, "stock", split, n_boot, seed)),
              lo, list(cd_stem_quantiles(st, plots, split))))
}

# Errors of the matched pairs (detection height minus field height) by report
# and layer class (surface; deeper; all): n, mean, median, RMSE.
cd_height_stats <- function(pairs, split) {
  out <- list()
  for (rp in c("z", "zrep", "zrep_on_z_matches")) for (lc in c("surface", "deeper", "all")) {
    e <- pairs$error[pairs$report == rp & (lc == "all" | pairs$layer_class == lc)]
    out[[length(out) + 1L]] <- data.frame(
      kind = "error", split = split, report = rp, layer_class = lc, n = length(e),
      mean = if (length(e)) mean(e) else NA_real_,
      median = if (length(e)) stats::median(e) else NA_real_,
      rmse = if (length(e)) sqrt(mean(e^2)) else NA_real_, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

## ---- held-out analyses (UNBLIND=1, pure) --------------------------------------------------
# Seeds: each split's selection on its calibration plots and the point
# estimates (pooled counts, no bootstrap) of the selection minus the declared
# arm and minus stock on its validation plots at native density.
cd_seeds <- function(cells, plot_rows, S, grid = mcd_grid()) {
  nat <- cells[cells$rung == "native", , drop = FALSE]
  ids_nat <- cv_ids(nat)
  rows <- lapply(S$SEEDS, function(sd) {
    s2 <- cv_split(plot_rows, sd, S$FRAC)
    sl <- cd_select(cells, s2$calib, grid)
    v <- intersect(s2$valid, cv_present(cells, "native", c(sl$label, CD_DECLARED, "stock")))
    P <- mcg_pool(nat[ids_nat %in% v & nat$config %in% c(sl$label, CD_DECLARED, "stock"), ,
                      drop = FALSE], "config")
    g <- function(cfg, m) {                # NA when the split has no validation plot
      x <- P[[m]][P$config == cfg]
      if (length(x)) x else NA_real_
    }
    r <- data.frame(seed = sd, config_id = sl$config_id, config = sl$label,
                    depth_max = sl$depth_max, near_2d = sl$near_2d, zmin = sl$zmin,
                    zmin_surface = sl$zmin_surface, lit_union = sl$lit_union,
                    cover_min = sl$cover_min, n_calib_plots = length(sl$plots),
                    n_valid_plots = length(v), stringsAsFactors = FALSE)
    for (m in CD_SEED_METRICS) {
      r[[paste0("selected_", m)]] <- g(sl$label, m)
      r[[paste0("declared_", m)]] <- g(CD_DECLARED, m)
      r[[paste0("stock_", m)]] <- g("stock", m)
    }
    for (m in CD_SEED_METRICS) {
      r[[paste0("d_declared_", m)]] <- g(sl$label, m) - g(CD_DECLARED, m)
      r[[paste0("d_stock_", m)]] <- g(sl$label, m) - g("stock", m)
    }
    r
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# Summary of the seeds: per contrast and metric the median, mean, range and
# share of splits above 0; how often each value of each grid parameter is
# selected; and the selected configurations' counts.
cd_seed_summary <- function(seeds) {
  out <- list()
  for (b in c("declared", "stock")) for (m in CD_SEED_METRICS) {
    d <- seeds[[sprintf("d_%s_%s", b, m)]]
    d <- d[!is.na(d)]
    out[[length(out) + 1L]] <- data.frame(
      kind = "difference", contrast = paste("selected minus", b), metric = m, parameter = NA,
      value = NA, n = length(d), median = if (length(d)) stats::median(d) else NA_real_,
      mean = if (length(d)) mean(d) else NA_real_, min = if (length(d)) min(d) else NA_real_,
      max = if (length(d)) max(d) else NA_real_,
      share_above_0 = if (length(d)) mean(d > 0) else NA_real_, stringsAsFactors = FALSE)
  }
  vals <- list(cover_min = seeds$cover_min, near_2d = seeds$near_2d, lit_union = seeds$lit_union,
               floor = sprintf("%g/%g", seeds$zmin, seeds$zmin_surface),
               depth_max = seeds$depth_max)
  for (p in names(vals)) {
    t <- table(as.character(vals[[p]]))
    out[[length(out) + 1L]] <- data.frame(
      kind = "parameter", contrast = NA, metric = NA, parameter = p, value = names(t),
      n = as.integer(t), median = NA, mean = NA, min = NA, max = NA,
      share_above_0 = NA, stringsAsFactors = FALSE)
  }
  t <- table(seeds$config)
  ids <- seeds$config_id[match(names(t), seeds$config)]
  o <- order(-as.integer(t), ids)
  out[[length(out) + 1L]] <- data.frame(
    kind = "configuration", contrast = NA, metric = NA, parameter = "config",
    value = names(t)[o], n = as.integer(t)[o], median = NA, mean = NA, min = NA, max = NA,
    share_above_0 = NA, stringsAsFactors = FALSE)
  out <- do.call(rbind, out)
  out$share <- ifelse(out$kind == "difference", NA_real_, out$n / nrow(seeds))
  rownames(out) <- NULL
  out
}

# Leave one site out: select on the headline calibration plots of the other
# sites, contrast against the declared arm and stock on every native plot of
# the held-out site (paired plot-bootstrap intervals).
cd_site_out <- function(cells, sp, S, grid = mcd_grid(), boot_seed = MT_SEED) {
  sites <- intersect(S$SITES, unique(cells$site))
  if (length(sites) < 2L) return(NULL)
  nat_ids <- cv_present(cells, "native", "stock")
  out <- list()
  for (site in sites) {
    train <- intersect(sp$calib[sub("::.*", "", sp$calib) != site], nat_ids)
    test <- nat_ids[sub("::.*", "", nat_ids) == site]
    sl <- cd_select(cells, train, grid)
    for (b in c(CD_DECLARED, "stock")) {
      r <- cv_contrast_row(cells, test, "native", sl$label, b, S$N_BOOT, boot_seed,
                           cv_tag("site_out", CD_CRITERION, "all plots of the held-out site",
                                  site, held_out_site = site))
      if (!is.null(r))
        out[[length(out) + 1L]] <- cbind(r, data.frame(
          selected_config_id = sl$config_id, n_train_plots = length(sl$plots),
          train_cF1_selected = sl$selected$cF1, stringsAsFactors = FALSE))
    }
  }
  out <- do.call(rbind, out); rownames(out) <- NULL
  out
}

# Every held-out analysis of section 5 (a to g; h is made with the stem tables)
# and of A4 and A5: the selection against each reference on the validation
# plots in every scope, the closed and open stands included (a to c), the
# ladder (d), the components (e), the seeds (f), leave one site out (g), and
# S_low (`slow`, cd_low_floor; NULL: none) against the declared arm, stock and
# S in every scope and down the ladder (rows tagged "low_floor" in validation,
# "low_floor_ladder" in ladder). `sel` is the headline selection, `sp` the
# split, `plot_rows` the plots the seeds' splits are drawn from. Every contrast
# row of validation and ladder carries the A2 reading on cF1; `primary` marks
# the one row of section 6.
cd_validation <- function(cells, plot_rows, sp, sel, S, grid = mcd_grid(), boot_seed = MT_SEED,
                          slow = NULL) {
  rc <- cd_reference_contrasts(cells, sp$valid, sel, S, "valid", "validation", boot_seed)
  lf <- cd_low_floor_contrasts(cells, sp$valid, slow, sel, S, "valid", boot_seed)
  bind <- function(z) as.data.frame(data.table::rbindlist(z, fill = TRUE))
  v <- bind(list(rc$native, lf$native))
  all_scope <- names(cd_scopes(intersect(S$SITES, unique(cells$site))))[1]
  v$primary <- v$analysis == "validation" & v$scope == all_scope & v$config_a == sel$label &
    v$config_b == CD_DECLARED & v$rung == "native"
  nb <- cd_component_neighbours(sel$config_id, grid)
  comp <- cd_component_rows(cells, sp$valid, sel, nb, S, "valid", boot_seed)
  seeds <- cd_seeds(cells, plot_rows, S, grid)
  list(validation = v, ladder = bind(list(rc$ladder, lf$ladder)), components = comp,
       seeds = seeds, seed_summary = cd_seed_summary(seeds),
       site_out = cd_site_out(cells, sp, S, grid, boot_seed))
}

## ---- Markdown -----------------------------------------------------------------------------
cd_f3 <- function(x) ifelse(is.na(x), "NA", sprintf("%.3f", x))
cd_iv <- function(lo, hi) sprintf("[%s, %s]", cd_f3(lo), cd_f3(hi))
cd_para <- function(...) c(strwrap(paste(...), width = 80), "")
cd_md <- function(header, rows)
  c(paste0("| ", paste(header, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(header)), collapse = "|"), "|"), rows, "")

# Contrast rows as a table; rows that carry the A2 reading (verdict_cF1) get a
# column with it and its margin note.
cd_md_contrasts <- function(v, extra = NULL) {
  if (is.null(v) || !nrow(v)) return(c("(no rows)", ""))
  dl <- function(m) sprintf("%s %s", cd_f3(v[[paste0("d_", m)]]),
                            cd_iv(v[[paste0("lo_", m)]], v[[paste0("hi_", m)]]))
  body <- sprintf(paste("| %s | %s | %s | `%s` | `%s` | %d | %d | %d / %d | %s / %s | %s | %s |",
                        "%s | %s | %s | %s | %s |"),
                  v$scope, v$rung, ifelse(v$split == "calib", "calib (in-sample)", v$split),
                  v$config_a, v$config_b, as.integer(v$n_plots), as.integer(v$n_ref),
                  as.integer(round(v$a_n_det)), as.integer(round(v$b_n_det)), cd_f3(v$a_cF1),
                  cd_f3(v$b_cF1), dl("cF1"), dl("F1"), dl("recall"), dl("precision"),
                  dl("cRecall"), dl("cPrecision"), dl("det_per_ref"))
  read <- "verdict_cF1" %in% names(v)
  if (read) body <- paste0(body, " ", cd_verdict_text(v$verdict_cF1, v$verdict_note_cF1), " |")
  if (!is.null(extra)) body <- paste0("| ", v[[extra]], " ", body)
  cd_md(c(extra, "Scope", "Rung", "Split", "A", "B", "Plots", "Stems", "Detections A / B",
          "cF1 A / B", "ΔcF1 [95% interval]", "ΔF1 [95% interval]", "Δrecall [95% interval]",
          "Δprecision [95% interval]", "ΔcRecall [95% interval]", "ΔcPrecision [95% interval]",
          "Δdet/ref [95% interval]", if (read) "Reading of ΔcF1 (A2)"), body)
}

cd_md_selection <- function(s)
  cd_md(c("Analysis", "Selected", "depth_max", "near_2d", "zmin / zmin_surface", "lit_union",
          "cover_min", "Calibration plots", "cF1 selected / declared / stock",
          "F1 selected / declared / stock", "Recall / precision selected"),
        sprintf("| %s | `%s` (id %d) | %g | %g | %g / %g | %s | %g | %d | %s / %s / %s | %s / %s / %s | %s / %s |",
                s$analysis, s$config, as.integer(s$config_id), s$depth_max, s$near_2d, s$zmin,
                s$zmin_surface, s$lit_union, s$cover_min, as.integer(s$n_calib_plots),
                cd_f3(s$calib_cF1_selected), cd_f3(s$calib_cF1_declared),
                cd_f3(s$calib_cF1_stock), cd_f3(s$calib_F1_selected),
                cd_f3(s$calib_F1_declared), cd_f3(s$calib_F1_stock),
                cd_f3(s$calib_recall_selected), cd_f3(s$calib_precision_selected)))

cd_md_ranking <- function(g, n = 10L) {
  d <- g[g$family == "depth", , drop = FALSE]
  d <- utils::head(d[order(d$rank), , drop = FALSE], n)
  r <- g[g$family != "depth", , drop = FALSE]
  row <- function(x, rank) sprintf("| %s | `%s` | %s | %s | %s | %s | %s | %s | %d | %s | %s | %s | %s | %s |",
                                   rank, x$label, ifelse(is.na(x$config_id), "", x$config_id),
                                   ifelse(is.na(x$depth_max), "", sprintf("%g", x$depth_max)),
                                   ifelse(is.na(x$near_2d), "", sprintf("%g", x$near_2d)),
                                   ifelse(is.na(x$zmin), "",
                                          sprintf("%g / %g", x$zmin, x$zmin_surface)),
                                   ifelse(is.na(x$lit_union), "", as.character(x$lit_union)),
                                   ifelse(is.na(x$cover_min), "", sprintf("%g", x$cover_min)),
                                   as.integer(round(x$n_det)), cd_f3(x$cF1), cd_f3(x$F1),
                                   cd_f3(x$precision), cd_f3(x$recall), cd_f3(x$det_per_ref))
  cd_md(c("Rank", "Configuration", "config_id", "depth_max", "near_2d", "zmin / zmin_surface",
          "lit_union", "cover_min", "Detections", "cF1", "F1", "Precision", "Recall",
          "Det/ref"),
        c(row(d, d$rank), row(r, rep("ref", nrow(r)))))
}

# Lowest-tree contrast rows (kind "contrast") as a table: raw recall, null
# recall TP0 / n and chance-corrected recall of both sides, the differences and
# the paired intervals.
cd_md_lowest_contrasts <- function(k) {
  if (is.null(k) || !nrow(k)) return(c("(no rows)", ""))
  cd_md(c("Stratum", "A − B", "Stems", "Recall A / B", "Δrecall [95% interval]",
          "Null recall TP0/n A / B (Δ)", "(TP − TP0) / (n − TP0) A / B", "Δ [95% interval]"),
        sprintf("| %s | `%s` − `%s` | %d | %s / %s | %s %s | %s / %s (%s) | %s / %s | %s %s |",
                k$stratum, k$config_a, k$config_b, as.integer(k$stems), cd_f3(k$recall_a),
                cd_f3(k$recall_b), cd_f3(k$d_recall), cd_iv(k$lo_recall, k$hi_recall),
                cd_f3(k$null_recall_a), cd_f3(k$null_recall_b), cd_f3(k$d_null_recall),
                cd_f3(k$cRecall_a), cd_f3(k$cRecall_b), cd_f3(k$d_cRecall),
                cd_iv(k$lo_cRecall, k$hi_cRecall)))
}

# The lowest-tree tables of one split: every configuration's scores per
# stratum with their plot-bootstrap intervals and the above-chance mark (A3.d),
# the selection (sel_label) minus the declared arm and minus stock per
# stratum, and the stems' height quantiles. S_low's contrasts are in its own
# section (cd_md_low_floor).
cd_md_lowest <- function(L, split, sel_label) {
  s <- L[L$kind == "score" & L$split == split, , drop = FALSE]
  k <- L[L$kind == "contrast" & L$split == split & L$config_a == sel_label, , drop = FALSE]
  q <- L[L$kind == "stem_heights" & L$split == split, , drop = FALSE]
  if (!nrow(s)) return(c("(no rows)", ""))
  sc <- function(type) {
    x <- s[s$type %in% type, , drop = FALSE]
    cd_md(c("Stratum", "Role", "Configuration", "Stems", "Matched", "Recall [95% interval]",
            "TP0 (null)", "(TP − TP0) / (n − TP0) [95% interval]", "Above chance"),
          sprintf("| %s | %s | `%s` | %d | %d | %s %s | %s | %s %s | %s |", x$stratum, x$role,
                  x$config, as.integer(x$stems), as.integer(x$matched), cd_f3(x$recall),
                  cd_iv(x$recall_lo, x$recall_hi), cd_f3(x$TP0), cd_f3(x$cRecall),
                  cd_iv(x$cRecall_lo, x$cRecall_hi), ifelse(x$above_chance, "yes", "no")))
  }
  c(cd_para("By field-height band of the reference stem (native density). The intervals",
            "are those of the plot bootstrap (plots resampled within site, counts summed);",
            "\"Above chance\": the chance-corrected interval lies above 0, i.e. the",
            "configuration finds the stratum's trees above chance (A3.d)."),
    sc(c("all", "band", "band_pooled")),
    "By crown class:", "", sc("class"),
    "The selection minus the declared gated arm and minus stock, per stratum:", "",
    cd_md_lowest_contrasts(k),
    "Field heights of the reference stems (m):", "",
    cd_md(c("Site", "Stems", "With height", "Min", "1%", "5%", "10%", "Median"),
          sprintf("| %s | %d | %d | %s | %s | %s | %s | %s |", q$site, as.integer(q$stems),
                  as.integer(q$with_height), cd_f3(q$min), cd_f3(q$q01), cd_f3(q$q05),
                  cd_f3(q$q10), cd_f3(q$median))))
}

# The guard of the lowest trees on one split (section 6 read as A3 says), three
# paragraphs: (a) the guard as fixed (raw recall of the stems under 10 m,
# selection minus the declared arm, flagged when its interval lies below 0);
# (b) the same contrast in chance-corrected recall with its interval and the
# change in null recall; (c) the reading of A3.c. `label` opens each paragraph
# (the in-sample tables say so).
cd_guard_lines <- function(L, split, sel_label, label = NULL) {
  g <- L[L$kind == "contrast" & L$split == split & L$type == "band_pooled" &
           L$stratum == CD_LOW & L$config_a == sel_label & L$config_b == CD_DECLARED, ,
         drop = FALSE]
  if (!nrow(g)) return(cd_para(label, "Guard: no rows."))
  g <- g[1, , drop = FALSE]
  flag <- cd_below_zero(g$hi_recall)
  c(cd_para(label, sprintf(paste("Guard (a), as fixed in section 6: recall of the reference",
                                 "stems under 10 m, selection minus the declared arm: %s %s",
                                 "(%d stems)%s."), cd_f3(g$d_recall),
                           cd_iv(g$lo_recall, g$hi_recall), as.integer(g$stems),
                           if (flag) " -- FLAGGED: the interval lies below 0" else
                             "; not flagged")),
    cd_para(label, sprintf(paste("Guard (b), chance-corrected (A3.b): (TP − TP0) / (n − TP0)",
                                 "of the same stems, selection minus the declared arm: %s %s;",
                                 "null recall TP0 / n %s and %s, change %s."),
                           cd_f3(g$d_cRecall), cd_iv(g$lo_cRecall, g$hi_cRecall),
                           cd_f3(g$null_recall_a), cd_f3(g$null_recall_b),
                           cd_f3(g$d_null_recall))),
    cd_para(label, sprintf("Reading (A3.c): **%s**.",
                           cd_guard_reading(flag, g$lo_cRecall, g$hi_cRecall))))
}

# The S_low section (A4) of one split: how S_low was derived (the calibration
# values of S and its floor siblings), items (i) and (ii) of A4 on the split,
# the resulting sentence, S_low's contrasts at native density in every scope
# (`native`) and down the ladder (`ladder`), and its lowest-tree contrasts per
# stratum. in_sample: the calibration plots, on which S_low was chosen by the
# statistic of (ii); the sentence is then withheld (A4 is read on the
# validation plots).
cd_md_low_floor <- function(res, native, ladder, split, in_sample = FALSE) {
  slow <- res$low_floor; sel <- res$selected
  if (is.null(slow))
    return(cd_para("No S_low: S itself has the highest chance-corrected recall of the",
                   "reference stems under 10 m among its floor-pair siblings on the",
                   "calibration plots (or none is defined); the low-floor analyses are",
                   "skipped."))
  cand <- slow$candidates
  L <- res$lowest
  k <- L[L$kind == "contrast" & L$split == split & L$config_a == slow$label, , drop = FALSE]
  kii <- k[k$type == "band_pooled" & k$stratum == CD_LOW & k$config_b == sel$label, ,
           drop = FALSE]
  ri <- if (!is.null(native) && nrow(native))
    native[native$scope == native$scope[1] & native$config_b == CD_DECLARED &
             native$rung == "native", , drop = FALSE] else native
  vi <- if (!is.null(ri) && nrow(ri)) ri$verdict_cF1[1] else NA_character_
  lo_ii <- if (nrow(kii)) kii$lo_cRecall[1] else NA_real_
  rd <- cd_low_floor_reading(vi, lo_ii)
  where <- if (in_sample) "calibration plots, in-sample" else "validation plots"
  c(cd_para(sprintf("S_low = `%s` (config_id %d): %s.", slow$label, slow$config_id, CD_LOW_ON)),
    cd_md(c("Configuration", "config_id", "zmin / zmin_surface",
            "(TP − TP0) / (n − TP0) under 10 m (calibration plots)", "Role"),
          sprintf("| `%s` | %d | %g / %g | %s | %s |", cand$label, as.integer(cand$config_id),
                  cand$zmin, cand$zmin_surface, cd_f3(cand$cRecall_under_10m),
                  ifelse(cand$config_id == sel$config_id, "S",
                         ifelse(cand$config_id == slow$config_id, "S_low", "")))),
    if (!is.null(ri) && nrow(ri))
      cd_para(sprintf(paste("(i) S_low minus the declared arm, cF1, native density, %s (%s,",
                            "%d plots): %s %s -> %s."), ri$scope[1], where,
                      as.integer(ri$n_plots[1]), cd_f3(ri$d_cF1[1]),
                      cd_iv(ri$lo_cF1[1], ri$hi_cF1[1]),
                      cd_verdict_text(ri$verdict_cF1[1], ri$verdict_note_cF1[1])))
    else cd_para("(i) S_low minus the declared arm: no rows."),
    if (nrow(kii))
      cd_para(sprintf(paste("(ii) chance-corrected recall of the reference stems under 10 m,",
                            "S_low minus S (%s, %d stems): %s %s; the interval lies above 0:",
                            "%s."), where, as.integer(kii$stems[1]), cd_f3(kii$d_cRecall[1]),
                      cd_iv(kii$lo_cRecall[1], kii$hi_cRecall[1]), if (rd$ii) "yes" else "no"))
    else cd_para("(ii) S_low minus S under 10 m: no rows."),
    if (in_sample)
      cd_para("In-sample: S_low was chosen on these plots by the statistic of (ii), so these",
              "values are not the reading of A4, which is made on the validation plots",
              "(UNBLIND=1).")
    else cd_para(sprintf("Reading (A4): (i) %s, (ii) %s: **%s**.",
                         if (rd$i) "holds" else "does not hold",
                         if (rd$ii) "holds" else "does not hold", rd$sentence)),
    cd_para(sprintf("S_low against the declared arm, stock and S (%s, native density):",
                    where)),
    cd_md_contrasts(native),
    cd_para(sprintf("Down the ladder (%s):", where)),
    cd_md_contrasts(ladder),
    cd_para(sprintf("Lowest trees, S_low minus the declared arm, minus S and minus stock (%s):",
                    where)),
    cd_md_lowest_contrasts(k))
}

cd_md_heights <- function(H, split) {
  e <- H[H$kind == "error" & H$split == split, , drop = FALSE]
  k <- H[H$kind == "contrast" & H$split == split, , drop = FALSE]
  c(cd_para("Detection height minus field height of the selection's detections matched",
            "to a stem with a field height (native density). z: the candidate's Z, matched",
            "as scored; zrep: the re-measured height, matched with it (the height gate",
            "of the matcher reads it); zrep_on_z_matches: zrep on the pairs matched with Z."),
    cd_md(c("Report", "Layer", "Pairs", "Mean error", "Median error", "RMSE"),
          sprintf("| %s | %s | %d | %s | %s | %s |", e$report, e$layer_class, as.integer(e$n),
                  cd_f3(e$mean), cd_f3(e$median), cd_f3(e$rmse))),
    "The selection reported with zrep minus the selection reported with Z:", "",
    cd_md_contrasts(k))
}

# The blind tables (calibration plots only; every number in-sample).
cd_tables_blind <- function(res, S, rec) {
  sel <- res$selected
  c("# multichm_depth calibration (blind)", "",
    "<!-- generated by scripts/calval_multichm_depth.R -->", "",
    cd_para("Provenance:", CD_PROVENANCE),
    cd_para(sprintf(paste("Blind run (UNBLIND=0): only the %d calibration plots of the gated",
                          "study's headline split (seed %d, calibration fraction %g) were",
                          "scored and read; every number below is in-sample. %d validation",
                          "plots are held out. Population `%s`; sealed root clip manifest",
                          "SHA-256 `%s`; null K = %d shifts, match radius %g m; %d",
                          "plot-bootstrap draws (plots resampled within site). Δ = A − B;",
                          "c-metrics are corrected for chance."), res$n_calib, S$SEED, S$FRAC,
                    res$n_valid, S$POP, rec$clip_manifest_sha256, rec$K, rec$tol, S$N_BOOT)),
    "## Selection", "",
    cd_para(sprintf("Selected `%s` (config_id %d), %s.", sel$label, sel$config_id,
                    CD_SELECTED_ON),
            if (!is.null(res$low_floor))
              sprintf("S_low (A4): `%s` (config_id %d), %s.", res$low_floor$label,
                      res$low_floor$config_id, CD_LOW_ON)
            else paste("No S_low (A4): S itself has the highest chance-corrected recall of",
                       "the stems under 10 m among its floor-pair siblings.")),
    cd_md_selection(res$selection),
    "## Calibration ranking of the grid (top ten, native density)", "",
    cd_md_ranking(res$ranking),
    "## The selection against each reference (calibration plots, in-sample)", "",
    cd_para(CD_READING_TEXT, CD_STANDS_TEXT, "Here every reading is in-sample."),
    cd_md_contrasts(res$calibration$native),
    "Down the ladder (calibration plots, in-sample):", "",
    cd_md_contrasts(res$calibration$ladder),
    "## Components (calibration plots, native density, in-sample)", "",
    cd_para("Δ = the selection minus the selection with one parameter changed to another",
            "grid value (the parameter and its other value in the first column)."),
    cd_md_contrasts(cd_component_label(res$components[res$components$split == "calib", ,
                                                      drop = FALSE]), "Parameter = value"),
    "## Lowest trees (calibration plots, in-sample)", "",
    cd_guard_lines(res$lowest, "calib", sel$label, "In-sample (calibration plots):"),
    cd_md_lowest(res$lowest, "calib", sel$label),
    "## S_low, the low-floor sibling (calibration plots, in-sample)", "",
    cd_md_low_floor(res, res$calibration_low$native, res$calibration_low$ladder, "calib",
                    in_sample = TRUE),
    "## Heights (calibration plots, in-sample)", "",
    cd_md_heights(res$heights, "calib"))
}

cd_component_label <- function(x) {
  if (is.null(x) || !nrow(x)) return(x)
  x$`Parameter = value` <- sprintf("%s = %s (selected %s)", x$parameter, x$value,
                                   x$selected_value)
  x
}

# The full tables after unblinding: the reading rule (the primary contrast, the
# guard read as A3 says), every held-out table, S_low (A4), then the blind
# tables.
cd_tables_unblind <- function(res, val, S, rec) {
  sel <- res$selected
  v <- val$validation
  p <- v[v$primary, , drop = FALSE]
  vs <- v[v$analysis != CD_LOW_FLOOR, , drop = FALSE]
  vl <- v[v$analysis == CD_LOW_FLOOR, , drop = FALSE]
  ld <- val$ladder
  lds <- ld[ld$analysis != paste0(CD_LOW_FLOOR, "_ladder"), , drop = FALSE]
  ldl <- ld[ld$analysis == paste0(CD_LOW_FLOOR, "_ladder"), , drop = FALSE]
  L <- res$lowest
  ss <- val$seed_summary
  dif <- ss[ss$kind == "difference", , drop = FALSE]
  par <- ss[ss$kind == "parameter", , drop = FALSE]
  cfg <- utils::head(ss[ss$kind == "configuration", , drop = FALSE], 10)
  so <- val$site_out
  c("# multichm_depth calibration and validation", "",
    "<!-- generated by scripts/calval_multichm_depth.R -->", "",
    cd_para("Provenance:", CD_PROVENANCE),
    cd_para(sprintf(paste("Selection `%s` (config_id %d), %s; %d calibration plots, %d",
                          "validation plots. Population `%s`; sealed root clip manifest",
                          "SHA-256 `%s`; null K = %d, match radius %g m; %d plot-bootstrap",
                          "draws."), res$selected$label, res$selected$config_id, CD_SELECTED_ON,
                    res$n_calib, res$n_valid, S$POP, rec$clip_manifest_sha256, rec$K, rec$tol,
                    S$N_BOOT)),
    "## Reading rule (section 6 with addendum 1)", "",
    cd_para(CD_READING_TEXT),
    if (nrow(p)) cd_para(sprintf(paste("Primary: selection minus the declared gated arm `%s`,",
                                       "cF1, native density, validation plots of %s (%d",
                                       "plots): %s %s -> **%s**."), CD_DECLARED, p$scope[1],
                                 as.integer(p$n_plots[1]), cd_f3(p$d_cF1[1]),
                                 cd_iv(p$lo_cF1[1], p$hi_cF1[1]),
                                 cd_verdict_text(p$verdict_cF1[1], p$verdict_note_cF1[1])))
    else cd_para("Primary contrast: no rows."),
    cd_guard_lines(L, "valid", sel$label),
    "## a-c. The selection against each reference (validation plots, native density)", "",
    cd_para(CD_STANDS_TEXT),
    cd_md_contrasts(vs),
    "## d. The ladder (validation plots)", "",
    cd_md_contrasts(lds),
    "## e. Components (validation plots, native density)", "",
    cd_md_contrasts(cd_component_label(val$components), "Parameter = value"),
    "## f. Seeds (validation plots of each split, native density, point estimates)", "",
    cd_md(c("Contrast", "Metric", "Splits", "Median", "Mean", "Min", "Max", "Share above 0"),
          sprintf("| %s | %s | %d | %s | %s | %s | %s | %s |", dif$contrast, dif$metric,
                  as.integer(dif$n), cd_f3(dif$median), cd_f3(dif$mean), cd_f3(dif$min),
                  cd_f3(dif$max), cd_f3(dif$share_above_0))),
    "How often each value of each grid parameter is selected:", "",
    cd_md(c("Parameter", "Value", "Splits", "Share"),
          sprintf("| %s | %s | %d | %s |", par$parameter, par$value, as.integer(par$n),
                  cd_f3(par$share))),
    "The most frequent selections:", "",
    cd_md(c("Configuration", "Splits"),
          sprintf("| `%s` | %d |", cfg$value, as.integer(cfg$n))),
    "## g. Leave one site out (every plot of the held-out site, native density)", "",
    cd_md_contrasts(so),
    "## h. Lowest trees (validation plots)", "",
    cd_md_lowest(L, "valid", sel$label),
    "## h. Heights (validation plots)", "",
    cd_md_heights(res$heights, "valid"),
    "## S_low, the low-floor sibling (A4; validation plots)", "",
    cd_md_low_floor(res, vl, ldl, "valid"),
    "## Calibration (in-sample)", "",
    cd_md_selection(res$selection),
    cd_md_ranking(res$ranking),
    cd_md_contrasts(res$calibration$native),
    cd_md_contrasts(cd_component_label(res$components[res$components$split == "calib", ,
                                                      drop = FALSE]), "Parameter = value"),
    cd_guard_lines(L, "calib", sel$label, "In-sample (calibration plots):"),
    cd_md_lowest(L, "calib", sel$label),
    cd_md_low_floor(res, res$calibration_low$native, res$calibration_low$ladder, "calib",
                    in_sample = TRUE),
    cd_md_heights(res$heights, "calib"))
}

## ---- stage: analyze -----------------------------------------------------------------------
# S_low (A4) as declared_depth_config.json records it: its configuration, the
# rule and the calibration values of S and its floor siblings; exists = FALSE
# when there is none.
cd_low_floor_record <- function(slow) {
  if (is.null(slow)) return(list(exists = FALSE, rule = CD_LOW_ON))
  list(exists = TRUE, config_id = slow$config_id, label = slow$label,
       depth_max = slow$depth_max, near_2d = slow$near_2d, zmin = slow$zmin,
       zmin_surface = slow$zmin_surface, lit_union = slow$lit_union,
       cover_min = slow$cover_min, criterion = CD_LOW_CRITERION, rule = CD_LOW_ON,
       calibration_cRecall_under_10m = slow$value, candidates = slow$candidates)
}

cd_declared <- function(res, S, rec, unblind) {
  s <- res$selected
  spec <- res$spec
  list(config_id = s$config_id, label = s$label, depth_max = s$depth_max, near_2d = s$near_2d,
       zmin = s$zmin, zmin_surface = s$zmin_surface, lit_union = s$lit_union,
       cover_min = s$cover_min, constants = mcd_constants(),
       constants_sha256 = cd_constants_digest(), grid_sha256 = cd_grid_digest(),
       criterion = CD_CRITERION, seed = S$SEED, frac = S$FRAC, K = rec$K, tol = rec$tol,
       n_calibration_plots = res$n_calib, n_validation_plots = res$n_valid,
       calibration_cF1 = s$selected$cF1, calibration_F1 = s$selected$F1,
       calibration_cF1_declared_gated = s$declared$cF1, calibration_cF1_stock = s$stock$cF1,
       clip_manifest_sha256 = rec$clip_manifest_sha256, population = S$POP,
       gated_run = rec$gated$out, declared_gated = CD_DECLARED,
       selection = CD_SELECTED_ON, low_floor = cd_low_floor_record(res$low_floor),
       blind = !isTRUE(unblind), provenance = CD_PROVENANCE,
       specification_sha256 = spec$specification_sha256,
       addendum_sha256 = spec$addendum_sha256,
       protocol = spec$protocol, protocol_sha256 = spec$protocol_sha256)
}

# Every analysis from explicit inputs: cells (already restricted to the
# allowed plots), the plot rows of the split's universe, the split, the gated
# candidates index and the stems. unblind adds the validation analyses.
# fdir: the features directory; out: where the files go; chm_keys: the cells
# for which the gated cells.csv has a chm_vwf row (read from S$GATED when
# NULL). Stops first when the protocol document is missing (A7).
cd_run_analysis <- function(S, rec, cells, plot_rows, sp, idx, stems, unblind = FALSE,
                            out = S$OUT, fdir = file.path(S$OUT, "features"),
                            cdir = file.path(S$GATED, "candidates"), chm_keys = NULL) {
  spec <- cd_spec_record()
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  grid <- mcd_grid()
  if (is.null(chm_keys)) {
    w <- idx[cv_ids(idx) %in% cd_allowed_plots(sp, unblind), , drop = FALSE]
    chm_keys <- cd_gated_chm_keys(S, paste(w$site, w$plot, w$rung))
  }
  cd_check_cells(cells, idx, grid, sp, unblind, chm_keys)
  sel <- cd_select(cells, sp$calib, grid)
  n_valid <- length(sp$valid)
  selection <- cd_selection_row(sel, "headline", S$SEED, n_valid = n_valid)
  ranking <- cd_grid_ranking(cells, sp$calib, grid, sel)
  calibration <- cd_reference_contrasts(cells, sp$calib, sel, S, "calib")
  nb <- cd_component_neighbours(sel$config_id, grid)
  comp <- cd_component_rows(cells, sp$calib, sel, nb, S, "calib")
  ## per-stem matches (native density) of the allowed plots
  plots <- cd_allowed_plots(sp, unblind)
  lcfg <- cd_lowest_configs(sel, grid)
  sj <- cd_stem_jobs(idx, stems, plots)
  t0 <- Sys.time()
  rs <- plot_lapply(sj, cd_stem_worker, cfgs = lcfg, sel = sel, cdir = cdir, fdir = fdir,
                    K = rec$K, tol = rec$tol, mc.cores = S$CORES)
  failed <- vapply(rs, function(r) inherits(r, "error"), logical(1))
  if (any(failed))
    stop("stem matches failed for plots: ", paste(vapply(sj[failed], function(j)
      paste(j$site, j$plot, sep = "/"), ""), collapse = ","), call. = FALSE)
  st <- as.data.frame(data.table::rbindlist(lapply(rs, `[[`, "stems")))
  pairs <- as.data.frame(data.table::rbindlist(lapply(rs, `[[`, "pairs")))
  zrep <- as.data.frame(data.table::rbindlist(lapply(rs, `[[`, "zrep")))
  zchk <- as.data.frame(data.table::rbindlist(lapply(rs, `[[`, "zrep_check")))
  cd_assert_blind(st, sp, unblind, "the stem matches")
  ## CHECK S3
  s3 <- cd_s3_compare(st, cells, zchk)
  if (s3$n != length(sj) * length(lcfg) || s3$n_bad || s3$n_zrep_bad) {
    write.csv(s3$bad, file.path(out, "s3_failures.csv"), row.names = FALSE)
    stop(sprintf(paste("CHECK S3 failed: %d of %d cell x configuration rows differ (expected %d",
                       "rows); %d of %d zrep cells differ"), s3$n_bad, s3$n,
                 length(sj) * length(lcfg), s3$n_zrep_bad, s3$n_zrep), call. = FALSE)
  }
  unlink(file.path(out, "s3_failures.csv"))      # a failure file of an earlier run is stale
  cv_pass(paste("CHECK S3: in %d native cells x %d configurations (%s) sum(matched) = TP and",
                "stems = n_ref of cells.csv, summed null means = TP0 (max |diff| %.3g); the",
                "zrep report's matches = its TP in %d cells (%.1f min)"),
          length(sj), length(lcfg), paste(vapply(lcfg, `[[`, "", "label"), collapse = ", "),
          s3$max_tp0_diff, s3$n_zrep, as.numeric(difftime(Sys.time(), t0, units = "mins")))
  ## S_low (A4): from the calibration plots' per-stem matches only, whatever
  ## the split being analysed; its row in selection.csv and its contrasts on
  ## the calibration plots (in-sample)
  slow <- cd_low_floor(st, sp$calib, sel, grid)
  if (!is.null(slow))
    selection <- rbind(selection, cd_selection_row(cd_config_of(cells, sp$calib, slow$config_id,
                                                                grid),
                                                   CD_LOW_FLOOR, S$SEED, n_valid = n_valid,
                                                   criterion = CD_LOW_CRITERION))
  calibration_low <- cd_low_floor_contrasts(cells, sp$calib, slow, sel, S, "calib")
  ## lowest trees and heights of each split
  splits <- list(calib = sp$calib)
  if (unblind) splits$valid <- sp$valid
  low <- list(); hts <- list()
  zcells <- rbind(cells[cells$rung == "native" & cells$config == sel$label,
                        c(CD_LEAD_COLS, MCG_COUNT_COLS)], zrep[c(CD_LEAD_COLS, MCG_COUNT_COLS)])
  for (nm in names(splits)) {
    p <- splits[[nm]]
    low[[nm]] <- cd_lowest_tables(st, p, nm, sel$label, S$N_BOOT, slow_label = slow$label)
    hk <- cv_contrast_row(zcells, p, "native", paste0(sel$label, CD_ZREP), sel$label, S$N_BOOT,
                          MT_SEED, cv_tag("zrep_minus_z", CD_CRITERION, nm,
                                          names(cd_scopes(intersect(S$SITES,
                                                                    unique(cells$site))))[1],
                                          S$SEED))
    if (!is.null(hk)) hk$kind <- "contrast"
    hts[[nm]] <- as.data.frame(data.table::rbindlist(
      list(cd_height_stats(pairs[cv_ids(pairs) %in% p, , drop = FALSE], nm), hk), fill = TRUE))
  }
  lowest <- as.data.frame(data.table::rbindlist(low, fill = TRUE))
  heights <- as.data.frame(data.table::rbindlist(hts, fill = TRUE))
  res <- list(selected = sel, selection = selection, ranking = ranking,
              calibration = calibration, components = comp, lowest = lowest, heights = heights,
              n_calib = length(sel$plots), n_valid = n_valid, low_floor = slow,
              calibration_low = calibration_low, spec = spec)
  val <- NULL
  if (unblind) {
    val <- cd_validation(cells, plot_rows, sp, sel, S, grid, slow = slow)
    res$components <- rbind(comp, val$components)
  }
  ## files (calibration.csv: the selection's rows, then S_low's)
  calib_rows <- as.data.frame(data.table::rbindlist(list(calibration$native, calibration$ladder,
                                                         calibration_low$native,
                                                         calibration_low$ladder), fill = TRUE))
  w <- function(x, f) write.csv(x, file.path(out, f), row.names = FALSE)
  w(selection, "selection.csv")
  w(ranking, "grid_calibration.csv")
  w(calib_rows, "calibration.csv")
  w(res$components, "components.csv")
  w(lowest, "lowest_trees.csv")
  w(heights, "heights.csv")
  w(st, "stem_matches.csv")
  w(pairs, "height_pairs.csv")
  w(zrep, "zrep_cells.csv")
  cd_write_json(cd_declared(res, S, rec, unblind), file.path(out, "declared_depth_config.json"))
  cd_write_json(list(S2 = sp$record,
                     S3 = sprintf(paste("pass: %d native cells x %d configurations; max TP0 diff",
                                        "%.3g; zrep matches = TP in %d cells"), length(sj),
                                  length(lcfg), s3$max_tp0_diff, s3$n_zrep),
                     blind = !isTRUE(unblind)),
                file.path(out, "analyze_checks.json"))
  writeLines(cd_tables_blind(res, S, rec), file.path(out, "tables_blind.md"))
  extra <- c("validation.csv", "ladder.csv", "seeds.csv", "seed_summary.csv", "site_out.csv",
             "tables.md")
  if (unblind) {
    w(val$validation, "validation.csv")
    w(val$ladder, "ladder.csv")
    w(val$seeds, "seeds.csv")
    w(val$seed_summary, "seed_summary.csv")
    w(val$site_out, "site_out.csv")
    writeLines(cd_tables_unblind(res, val, S, rec), file.path(out, "tables.md"))
  } else unlink(file.path(out, extra))     # a blind run leaves no held-out file behind
  res$validation <- val
  invisible(res)
}

cd_print_blind <- function(res) {
  sel <- res$selected
  cat(sprintf(paste("selection: %s (config_id %d), %s; %d calibration plots (in-sample cF1 %.3f,",
                    "F1 %.3f; declared %s cF1 %.3f, stock cF1 %.3f)\n"), sel$label, sel$config_id,
              CD_SELECTED_ON, res$n_calib, sel$selected$cF1, sel$selected$F1, CD_DECLARED,
              sel$declared$cF1, sel$stock$cF1))
  cat(if (is.null(res$low_floor)) "S_low: none (S has the highest cRecall under 10 m)\n" else
    sprintf("S_low: %s (config_id %d), in-sample cRecall of the stems under 10 m %.4f\n",
            res$low_floor$label, res$low_floor$config_id, res$low_floor$value))
  top <- utils::head(res$ranking[res$ranking$family == "depth", , drop = FALSE], 10)
  cat("calibration ranking (top ten, native density, in-sample):\n")
  for (i in seq_len(nrow(top)))
    cat(sprintf("  %2d  %-24s id %3d  cF1 %.4f  F1 %.4f  precision %.4f  recall %.4f  det/ref %.3f\n",
                top$rank[i], top$label[i], top$config_id[i], top$cF1[i], top$F1[i],
                top$precision[i], top$recall[i], top$det_per_ref[i]))
}

cd_stage_analyze <- function(S) {
  cd_spec_record()                     # no analysis without the protocol document (A7)
  G <- cd_read_gated(S)
  # the split: identity and strata only (split.csv), checked against the gated
  # study's (CHECK S2)
  f <- file.path(S$OUT, "split.csv")
  if (!file.exists(f)) stop("no split at ", f, "; run STAGE=score", call. = FALSE)
  tab <- read.csv(f, stringsAsFactors = FALSE)
  tab <- tab[tab$site %in% S$SITES, , drop = FALSE]
  pr <- tab[CD_PLOT_COLS]
  sp <- cd_check_split(cd_split_of(pr, S$SEED, S$FRAC),
                       cd_split_of(cd_gated_plot_rows(S), S$SEED, S$FRAC),
                       cd_gated_declared(S), S)
  if (!setequal(cv_ids(tab)[tab$split == "calib"], sp$calib) ||
      !setequal(cv_ids(tab)[tab$split == "valid"], sp$valid))
    stop("split.csv records another split; re-run STAGE=score", call. = FALSE)
  # the cells' record: this grid, constants, root, gated run and headline split
  rec <- cd_read_cells_config(S, G, sp)
  if (S$UNBLIND && isTRUE(rec$blind))
    stop("UNBLIND=1: the validation cells have not been scored; run STAGE=score UNBLIND=1 first",
         call. = FALSE)
  # the cells: the calibration plots' rows only while blind
  cells <- cd_read_cells_file(file.path(S$OUT, "cells.csv"))
  cells <- cells[cells$site %in% S$SITES & cells$rung %in% S$RUNGS, , drop = FALSE]
  cells <- cd_blind_filter(cells, sp, S$UNBLIND)
  # the candidates index and the stems of the allowed plots only (while blind,
  # nothing of a validation plot but its identity in split.csv is kept)
  allowed <- cd_allowed_plots(sp, S$UNBLIND)
  idx <- cd_read_gated_index(S)
  idx <- idx[cv_ids(idx) %in% allowed, , drop = FALSE]
  stems <- cd_read_stems(S, unique(idx$site))
  for (site in names(stems))
    stems[[site]] <- stems[[site]][paste(site, stems[[site]]$plotID, sep = "::") %in% allowed, ,
                                   drop = FALSE]
  cat(sprintf("[analyze] %s: %d plots, %d cells read (K = %d, TOL = %g)\n",
              if (S$UNBLIND) "UNBLIND=1" else "BLIND (calibration plots only)",
              length(unique(cv_ids(cells))),
              length(unique(paste(cells$site, cells$plot, cells$rung))), rec$K, rec$tol))
  t0 <- Sys.time()
  res <- cd_run_analysis(S, rec, cells, pr, sp, idx, stems, unblind = S$UNBLIND)
  cd_print_blind(res)
  cat(sprintf("[analyze] done in %.1f min -> %s\n",
              as.numeric(difftime(Sys.time(), t0, units = "mins")), S$OUT))
  invisible(res)
}

## ---- main ---------------------------------------------------------------------------------
cd_main <- function() {
  S <- cd_settings()
  lidR::set_lidr_threads(1L)            # one thread, parallel processes (specification section 1)
  dir.create(S$OUT, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("[multichm_depth] STAGE=%s UNBLIND=%d CORES=%d job dir %s, gated run %s, OUT %s\n",
              S$STAGE, as.integer(S$UNBLIND), S$CORES, S$d, S$GATED, S$OUT))
  if (S$STAGE %in% c("all", "features")) cd_stage_features(S)
  if (S$STAGE %in% c("all", "score")) cd_stage_score(S)
  if (S$STAGE %in% c("all", "analyze")) cd_stage_analyze(S)
  invisible()
}

if (sys.nframe() == 0L) cd_main()
