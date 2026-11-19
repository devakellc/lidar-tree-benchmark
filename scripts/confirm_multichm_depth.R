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

# Confirmation of the `multichm_depth` selection on other densities and flights:
# section A8 of docs/multichm-depth-protocol.md. The configurations are
# FIXED: the selection S and its low-floor sibling S_low as the study recorded
# them (declared_depth_config.json of the study's run: `label` and
# `low_floor`), never re-selected or tuned, against the declared gated arm
# (z5_s0.75_c0.6_e1_d8) and stock multichm. They are applied to other clips of
# the same NEON plots that the confirmation campaign of the multichm_gated arm
# prepared (docs/multichm-gated-confirmation-protocol.md): each dataset is a run
# of calval_multichm_gated.R (stages candidates and score) with its candidate
# cache, its scored cells, its record (K, TOL, population, root) and its job
# directory (stems and plot centroids). Each is scored exactly as its own
# cells.csv was scored, and the contrasts use the study's paired plot bootstrap.
#
# Datasets (CFD_DATASETS; dataset directories under CAMPAIGN, roots under WORK):
#   ql2            T2  the frozen QL2 clips of the 106 plots (rung 3.2)
#   wa2019         T3  the 2019 Washington clips, stems live in both epochs
#   wa2021_shared  T3  comparison: the same stems on the 2021 clips (native)
#   ca2018         T4  the 2018 SOAP and TEAK clips, stems live in both epochs
#   ca2017         T4  the 2017 SJER clips, stems live in both epochs
#   ca2021_shared  T4  comparison: the same stems on the 2021 clips (native only)
# The contrasts read five units (CFD_UNITS): T4 is ca2018 and ca2017 pooled, as
# the campaign pooled them. T1 (the density ladder on the validation plots) is
# read from the study's own ladder.csv; nothing of it is recomputed here.
#
# Stages (STAGE=features|score|contrasts|all), per dataset (DATASETS=):
#   features   every cell of the dataset's candidates index: its frozen clip read
#              as the gated candidates stage read it (frozen_clip(NULL, site,
#              plot, rung, cx, cy, half, root), unfiltered lidR::readLAS), the
#              clip must hold points, the cached candidate table must have the
#              index's n_cand rows and the clip's frdens must be the cell's; then
#              mcd_features() of every candidate with that frdens (the study's
#              cd_features_cell, stamped with the constants' digest).
#              -> OUT/<dataset>/features/*.rds, OUT/<dataset>/features.csv
#   score      every cell: S and S_low (cd_score_job with those two grid rows),
#              and the four gated reference configurations re-derived from the
#              same candidates (stock, z5_s0_c0.6_e1, z5_s0.75_c0.6_e1,
#              z5_s0.75_c0.6_e1_d8), each scored as the dataset's cells.csv was
#              scored: the cell's core stems from the dataset's job directory, K
#              and TOL from its cells.config.json, the plot's mcg_null_offsets,
#              mcg_score_cell. CHECK S1 stops the run when a re-derived reference
#              row differs from the dataset's row of the same cell and label
#              (observed counts exactly, null means within 1e-9). The two
#              identities of the depth library are checked on every cell and
#              counted (mcd_config(Inf, 0, 5, 0, FALSE, 0.6) accepts exactly the
#              candidates of the gated z5_s0_c0.6_e1, MCD_STOCK exactly the stock
#              set). -> OUT/<dataset>/cells.csv (the study's columns, `family`
#              "depth" or "gated"), OUT/<dataset>/identities.csv,
#              OUT/<dataset>/cells.config.json (K, TOL, root, the record read,
#              S1, identities, the declared configurations' file hash)
#   contrasts  per unit, plot subset ("validation half": the unit's plots that
#              are validation plots of the study's headline split, split.csv;
#              "all plots"), scope (every one of Five sites, California,
#              Washington and each site whose sites the unit holds) and pair (S
#              minus declared, the primary pair; S minus stock; S_low minus
#              declared; S_low minus S; declared minus stock, a check): one
#              cv_contrast_row (mcg_contrast: plots resampled within site,
#              N_BOOT draws, MT_SEED) with the metrics of the study's analysis a
#              and the reading of A2 on cF1 (cd_add_verdicts). The declared minus
#              stock rows on all plots are compared with the campaign's rows of
#              the same data and scope (CAMPAIGN/analysis/contrasts.csv). T1 is
#              taken from STUDY/ladder.csv, which stops the stage until
#              STUDY/tables.md exists (the study's held-out run has finished).
#              Then the reading of A8. -> OUT/contrasts.csv,
#              OUT/campaign_check.csv, OUT/a8_reading.csv, OUT/datasets.csv,
#              OUT/tables.md
#
# The reading of A8 (cfd_a8_reading): each test is read on its widest scope (T1
# and T2 Five sites, T3 Washington, T4 California) with the reading of A2 on
# the primary pair, in each of the two subsets (T1 exists for the validation
# plots only). The selection "carries over" when T2 and T3 read "better" or
# "not worse" and none of T1 to T4 reads "worse", in either subset; otherwise
# the failing tests are named. No other verdict is drawn.
#
# Usage (from the repository root; inputs are read only):
#   Rscript scripts/confirm_multichm_depth.R [STAGE=all|features|score|contrasts]
#     [DATASETS=ql2,wa2019,wa2021_shared,ca2018,ca2017,ca2021_shared]
#     [CORES=4 (at most 8)] [N_BOOT=1000] [WORK=work]
#     [STUDY=$WORK/multichm_depth_runs/neon/multichm_depth]
#     [CAMPAIGN=$WORK/multichm_gated_confirmation]
#     [OUT=$WORK/multichm_depth_runs/confirm]
# The contrasts stage reads every unit, so it needs every dataset scored. OUT
# has no `..` component and does not equal, lie inside or contain the given
# study, the study's run of record, the campaign or a frozen root (compared in
# canonical absolute form, cfd_check_out).
suppressMessages({ library(lidR); library(lidRplugins); library(sf)
                   library(data.table); library(parallel) })
options(lidR.progress = FALSE)
# The depth study's driver: sourcing it runs nothing (it ends with
# `if (sys.nframe() == 0L) cd_main()`); it sources the gated study's driver
# (and through it sweep_lib.R, model_bench_lib.R, calval_lib.R,
# master_tables_lib.R and multichm_gated_lib.R) and multichm_depth_lib.R.
source(.find("calval_multichm_depth.R"))

## ---- constants ----------------------------------------------------------------------------
CFD_MAX_CORES     <- 8L                  # at most 8 R worker processes
CFD_DEFAULT_CORES <- 4L
CFD_POP           <- "adopted"           # the population every dataset was scored for
CFD_SUBSETS       <- c("validation half", "all plots")
CFD_PRIMARY       <- "S_minus_declared"
CFD_CHECK         <- "declared_minus_stock"
CFD_GOOD          <- c("better", "not worse")
CFD_LADDER_RUNGS  <- c("8", "4", "2", "1")
CFD_CAMPAIGN_PAIR <- "declared_stock"    # the campaign's name of declared minus stock
# The runs of record under WORK: the study's and this driver's default OUT.
CFD_STUDY_DIR     <- file.path("multichm_depth_runs", "neon", "multichm_depth")
CFD_CONFIRM_DIR   <- file.path("multichm_depth_runs", "confirm")
CFD_SCOPES <- c(list(`Five sites` = CV_FIVE), MT_REGIONS,
                stats::setNames(as.list(CV_FIVE), CV_FIVE))

# The prepared datasets: directory under CAMPAIGN, frozen root under WORK, the
# sites and the one rung read (ca2021_shared also holds rungs 8 and 4; only its
# native rung is the comparison).
CFD_DATASETS <- data.frame(
  name = c("ql2", "wa2019", "wa2021_shared", "ca2018", "ca2017", "ca2021_shared"),
  test = c("T2", "T3", "T3", "T4", "T4", "T4"),
  role = c("test", "test", "comparison", "test", "test", "comparison"),
  dir = c("ql2", "epoch_wa/epoch_2019", "epoch_wa/shared_2021", "sparse_ca/sparse_2018",
          "sparse_ca/sparse_2017", "sparse_ca/shared_2021"),
  root = c("neon/frozen_2021_ql2", "epoch_wa_2019/neon/frozen_2019", "neon/frozen_2021",
           "sparse_2018/neon/frozen_2018", "sparse_2017/neon/frozen_2017", "neon/frozen_2021"),
  sites = c("SJER,SOAP,TEAK,WREF,ABBY", "WREF,ABBY", "WREF,ABBY", "SOAP,TEAK", "SJER",
            "SJER,SOAP,TEAK"),
  rung = c("3.2", "native", "native", "native", "native", "native"),
  stringsAsFactors = FALSE)

# The units the contrasts read: one dataset each, T4 the two sparse flights
# pooled. `campaign` names the same data in the campaign's contrasts.csv;
# `reading_scope` is the scope the A8 reading reads.
CFD_UNITS <- data.frame(
  unit = c("ql2", "wa2019", "wa2021_shared", "ca_sparse_pooled", "ca2021_shared"),
  parts = c("ql2", "wa2019", "wa2021_shared", "ca2018,ca2017", "ca2021_shared"),
  test = c("T2", "T3", "T3", "T4", "T4"),
  role = c("test", "test", "comparison", "test", "comparison"),
  label = c("QL2 level (rung 3.2)", "Washington 2019 flight",
            "Washington shared stems on the 2021 clips",
            "California native sparse flights (2017 SJER, 2018 SOAP and TEAK)",
            "California shared stems on the 2021 clips"),
  campaign = c("QL2 level", "Washington 2019 flight", "Washington shared stems on the 2021 clips",
               "California native sparse flights", "California shared stems on the 2021 clips"),
  reading_scope = c("Five sites", "Washington", "Washington", "California", "California"),
  stringsAsFactors = FALSE)

CFD_A8_TEXT <- paste(
  "A8: the selection \"carries over\" when it is \"better\" or \"not worse\" against",
  "the declared arm on T2 and on T3 and \"worse\" on none of T1 to T4, in either",
  "subset; otherwise the result is stated for the 2021 native clips only, with the",
  "failing tests named. Each test is read on its widest scope (T1 and T2: Five",
  "sites; T3: Washington; T4: California) with the reading of A2 on the primary",
  "pair (S minus declared, cF1), in each subset (validation half and all plots); T1",
  "is the study's ladder on its validation plots (rungs 8, 4, 2 and 1) and has no",
  "all-plots counterpart.")

## ---- paths --------------------------------------------------------------------------------
# A path for messages: relative to the repository root when it lies under it,
# else as given.
cfd_rel <- function(p) {
  p <- as.character(p)
  r <- normalizePath(.ROOT, mustWork = FALSE)
  q <- normalizePath(p, mustWork = FALSE)
  ifelse(startsWith(q, paste0(r, "/")), substring(q, nchar(r) + 2L), ifelse(q == r, ".", p))
}

# The components of a path made absolute against the working directory ("."
# and empty components dropped).
cfd_path_parts <- function(p) {
  p <- path.expand(p)
  if (!startsWith(p, "/")) p <- file.path(getwd(), p)
  x <- strsplit(p, "/", fixed = TRUE)[[1]]
  x[nzchar(x) & x != "."]
}

# The canonical absolute form of a path, whether it exists or not: made
# absolute against the working directory, its longest existing ancestor
# resolved with normalizePath(mustWork = TRUE) (a symbolic link in it is
# followed), the components that do not exist yet appended. A `..` among those
# is applied to what precedes it (a component that does not exist is no link)
# and the result is canonicalized again. A dangling symbolic link stops.
cfd_canon_path <- function(p) {
  if (!is.character(p) || length(p) != 1L || is.na(p) || !nzchar(p))
    stop("a path must be one non-empty string", call. = FALSE)
  parts <- cfd_path_parts(p)
  path_of <- function(x) paste0("/", paste(x, collapse = "/"))
  k <- length(parts)
  while (k > 0L && !file.exists(path_of(parts[seq_len(k)]))) k <- k - 1L
  if (k < length(parts)) {
    lk <- Sys.readlink(path_of(parts[seq_len(k + 1L)]))   # "" or NA unless a link
    if (!is.na(lk) && nzchar(lk))
      stop(cfd_rel(p), " holds a symbolic link that points nowhere", call. = FALSE)
  }
  base <- cfd_path_parts(normalizePath(path_of(parts[seq_len(k)]), mustWork = TRUE))
  rest <- parts[seq_len(length(parts) - k) + k]
  if (!".." %in% rest) return(path_of(c(base, rest)))
  for (x in rest) base <- if (x == "..") base[-length(base)] else c(base, x)
  cfd_canon_path(path_of(base))
}

# TRUE when the canonical paths a and b are equal or one lies inside the other.
cfd_path_overlap <- function(a, b) {
  dir_of <- function(p) if (endsWith(p, "/")) p else paste0(p, "/")
  identical(a, b) || startsWith(a, dir_of(b)) || startsWith(b, dir_of(a))
}

# OUT in canonical form (cfd_canon_path). Stops when OUT has a `..` component,
# or when it equals, lies inside or contains one of the read-only directories
# `ro` (a character vector named by what each is, canonicalized the same way).
cfd_check_out <- function(out, ro) {
  if (".." %in% strsplit(path.expand(out), "/", fixed = TRUE)[[1]])
    stop("OUT=", cfd_rel(out), " has a `..` component; give the directory without one",
         call. = FALSE)
  o <- cfd_canon_path(out)
  for (k in seq_along(ro))
    if (cfd_path_overlap(o, cfd_canon_path(ro[[k]])))
      stop("OUT=", cfd_rel(o), " overlaps a read-only input (", names(ro)[k], ", ",
           cfd_rel(ro[[k]]), ")", call. = FALSE)
  o
}

# Paths named by what they are, for cfd_check_out.
cfd_named <- function(what, p) stats::setNames(as.character(p), rep(what, length(p)))

## ---- arguments ----------------------------------------------------------------------------
# KEY=VALUE positional arguments -> the run's settings. `work` is the work
# directory the dataset roots and the default paths hang from. OUT is kept in
# canonical absolute form (cfd_check_out).
cfd_settings <- function(args = commandArgs(TRUE), work = file.path(.ROOT, "work")) {
  a <- strsplit(args, "=")
  A <- stats::setNames(lapply(a, `[`, 2), vapply(a, `[`, character(1), 1))
  given <- function(k) !is.null(A[[k]]) && !is.na(A[[k]]) && nzchar(A[[k]])
  get <- function(k, default) if (given(k)) A[[k]] else default
  num <- function(k, default) suppressWarnings(as.numeric(get(k, default)))
  S <- list(A = A, WORK = get("WORK", work), STAGE = get("STAGE", "all"),
            DATASETS = strsplit(get("DATASETS", paste(CFD_DATASETS$name, collapse = ",")),
                                ",")[[1]],
            CORES = num("CORES", CFD_DEFAULT_CORES), N_BOOT = num("N_BOOT", MT_N_BOOT))
  S$OUT <- get("OUT", file.path(S$WORK, CFD_CONFIRM_DIR))
  S$STUDY <- get("STUDY", file.path(S$WORK, CFD_STUDY_DIR))
  S$CAMPAIGN <- get("CAMPAIGN", file.path(S$WORK, "multichm_gated_confirmation"))
  if (!S$STAGE %in% c("all", "features", "score", "contrasts"))
    stop("STAGE must be all, features, score or contrasts", call. = FALSE)
  bad <- setdiff(S$DATASETS, CFD_DATASETS$name)
  if (length(bad) || !length(S$DATASETS) || anyDuplicated(S$DATASETS))
    stop("DATASETS must be distinct names among ", paste(CFD_DATASETS$name, collapse = ","),
         call. = FALSE)
  if (anyNA(c(S$CORES, S$N_BOOT)) || S$CORES < 1 || S$N_BOOT < 1 ||
      S$CORES != round(S$CORES) || S$N_BOOT != round(S$N_BOOT))
    stop("CORES and N_BOOT must be whole numbers >= 1", call. = FALSE)
  if (S$CORES > CFD_MAX_CORES)
    stop(sprintf("CORES must be at most %d (R worker processes)", CFD_MAX_CORES), call. = FALSE)
  S$CORES <- as.integer(S$CORES); S$N_BOOT <- as.integer(S$N_BOOT)
  # outputs never go into, or around, the inputs: the given study, the study's
  # run of record whatever STUDY= says (under WORK and under `work`), the
  # campaign and the frozen roots
  S$OUT <- cfd_check_out(S$OUT, c(
    cfd_named("the study", S$STUDY),
    cfd_named("the study's run of record", unique(file.path(c(S$WORK, work), CFD_STUDY_DIR))),
    cfd_named("the campaign", S$CAMPAIGN),
    cfd_named("a frozen root", file.path(S$WORK, unique(CFD_DATASETS$root)))))
  S
}

# One dataset's paths: the campaign's dataset directory, its candidates and job
# directory, its frozen root, sites, rung and this run's output directory.
cfd_dataset <- function(S, name) {
  r <- CFD_DATASETS[CFD_DATASETS$name == name, , drop = FALSE]
  if (nrow(r) != 1L) stop("unknown dataset ", name, call. = FALSE)
  dir <- file.path(S$CAMPAIGN, r$dir)
  list(name = r$name, test = r$test, role = r$role, dir = dir,
       cdir = file.path(dir, "candidates"), job = file.path(dir, "job"),
       root = file.path(S$WORK, r$root), sites = strsplit(r$sites, ",")[[1]], rung = r$rung,
       out = file.path(S$OUT, r$name))
}

## ---- fixed configurations, split, scopes and pairs (pure) ---------------------------------
# S and S_low as the study recorded them (declared_depth_config.json): their
# labels must be labels of mcd_grid() with the recorded config_ids, and the
# record must name this library's constants and grid. S_low is NULL when the
# record says there is none. Returns list(S, S_id, S_low, S_low_id, grid (the
# two grid rows, S first), file, sha256).
cfd_read_declared <- function(study, grid = mcd_grid()) {
  f <- file.path(study, "declared_depth_config.json")
  if (!file.exists(f)) stop("no declared depth configuration at ", cfd_rel(f), call. = FALSE)
  r <- jsonlite::read_json(f, simplifyVector = TRUE)
  if (!identical(r$constants_sha256, cd_constants_digest()))
    stop(cfd_rel(f), " was made with other constants than mcd_constants()", call. = FALSE)
  if (!identical(r$grid_sha256, cd_grid_digest(grid)))
    stop(cfd_rel(f), " was made on another grid than mcd_grid()", call. = FALSE)
  one <- function(label, id, what) {
    if (!is.character(label) || length(label) != 1L || !label %in% grid$label)
      stop(cfd_rel(f), ": ", what, " is not a label of mcd_grid()", call. = FALSE)
    if (!isTRUE(as.integer(id) == grid$config_id[grid$label == label]))
      stop(cfd_rel(f), ": ", what, " ", label, " is not config_id ", id, " of mcd_grid()",
           call. = FALSE)
    label
  }
  s <- one(r$label, r$config_id, "the selection S")
  lf <- r$low_floor
  if (is.null(lf) || is.null(lf$exists)) stop(cfd_rel(f), " has no low_floor record", call. = FALSE)
  sl <- if (isTRUE(lf$exists)) one(lf$label, lf$config_id, "the low-floor sibling S_low")
  if (identical(sl, s)) stop(cfd_rel(f), ": S_low equals S", call. = FALSE)
  g <- grid[match(c(s, sl), grid$label), , drop = FALSE]
  rownames(g) <- NULL
  list(S = s, S_id = as.integer(r$config_id), S_low = sl,
       S_low_id = if (!is.null(sl)) as.integer(lf$config_id), grid = g, file = f,
       sha256 = cd_file_sha(f))
}

# The validation plots ("site::plot") of the study's headline split.
cfd_valid_ids <- function(study) {
  f <- file.path(study, "split.csv")
  if (!file.exists(f)) stop("no split at ", cfd_rel(f), call. = FALSE)
  x <- read.csv(f, stringsAsFactors = FALSE)
  if (!all(c("site", "plot", "split") %in% names(x)) || !all(x$split %in% c("calib", "valid")))
    stop(cfd_rel(f), " is not a split table (site, plot, split calib / valid)", call. = FALSE)
  if (anyDuplicated(cv_ids(x))) stop(cfd_rel(f), " lists a plot twice", call. = FALSE)
  cv_ids(x[x$split == "valid", , drop = FALSE])
}

# The scopes a unit can form: every one of CFD_SCOPES whose sites it holds
# (Five sites needs all five, a region all of its sites), in that order.
cfd_scopes <- function(sites) Filter(function(s) all(s %in% sites), CFD_SCOPES)

# The plot subsets of a unit with plots `ids`: its validation plots, all plots.
cfd_subset_ids <- function(ids, valid)
  stats::setNames(list(intersect(ids, valid), ids), CFD_SUBSETS)

# The contrasts (a minus b) of A8 and the check, in order; without S_low its
# pairs are dropped.
cfd_pairs <- function(s, s_low = NULL) {
  p <- data.frame(
    pair = c(CFD_PRIMARY, "S_minus_stock", "S_low_minus_declared", "S_low_minus_S", CFD_CHECK),
    a = c(s, s, if (is.null(s_low)) NA else s_low, if (is.null(s_low)) NA else s_low,
          CD_DECLARED),
    b = c(CD_DECLARED, "stock", CD_DECLARED, s, "stock"),
    what = c("S minus declared (primary)", "S minus stock", "S_low minus declared",
             "S_low minus S", "declared minus stock (check)"),
    stringsAsFactors = FALSE)
  p <- p[!is.na(p$a), , drop = FALSE]
  rownames(p) <- NULL
  p
}

## ---- the datasets (read only) -------------------------------------------------------------
cfd_index_settings <- function(ds)
  list(CANDIDATES = ds$dir, OUT = ds$dir, root = ds$root, POP = CFD_POP, SITES = ds$sites,
       RUNGS = ds$rung)

# The dataset's candidates index at its rung, checked as the gated study checks
# it (cv_read_index: the candidates' root stamp, population and constants);
# its skipped cells are printed. Every site of the dataset must be present.
cfd_index <- function(ds) {
  Sg <- cfd_index_settings(ds)
  idx <- cv_read_index(Sg)
  sk <- cv_read_skipped(Sg)
  if (nrow(sk)) cv_report_skipped(sk, sprintf("[%s]", ds$name))
  if (!setequal(unique(idx$site), ds$sites))
    stop(ds$name, ": the index holds sites ", paste(unique(idx$site), collapse = ","), ", not ",
         paste(ds$sites, collapse = ","), call. = FALSE)
  if (anyDuplicated(paste(idx$site, idx$plot, idx$rung)))
    stop(ds$name, ": the index lists a cell twice", call. = FALSE)
  idx
}

# The dataset's record (cells.config.json): K and TOL its cells were scored
# with, checked for the population, the frozen root and the gated grid (the
# reference labels must mean what they meant then).
cfd_dataset_record <- function(ds) {
  f <- file.path(ds$dir, "cells.config.json")
  if (!file.exists(f)) stop("no cells record at ", cfd_rel(f), call. = FALSE)
  r <- jsonlite::read_json(f, simplifyVector = TRUE)
  miss <- setdiff(c("K", "tol", "population", "clip_manifest_sha256", "grid_sha256"), names(r))
  if (length(miss)) stop(cfd_rel(f), " lacks ", paste(miss, collapse = ", "), call. = FALSE)
  if (!identical(r$population, CFD_POP))
    stop(cfd_rel(f), ": the cells were scored for population ", r$population, call. = FALSE)
  if (!identical(r$clip_manifest_sha256, frozen_root_id(ds$root)))
    stop(cfd_rel(f), ": the cells were scored on another frozen root than ", cfd_rel(ds$root),
         call. = FALSE)
  if (!identical(r$grid_sha256, cv_grid_digest()))
    stop(cfd_rel(f), ": the cells were scored on another grid than the current mcg_grid()",
         call. = FALSE)
  K <- as.integer(r$K); tol <- as.numeric(r$tol)
  if (!isTRUE(K >= 1L) || !isTRUE(tol > 0)) stop(cfd_rel(f), ": invalid K or TOL", call. = FALSE)
  list(K = K, tol = tol, record = r, file = f,
       cells_sha256 = cd_file_sha(file.path(ds$dir, "cells.csv")))
}

# The stems of the dataset's job directory, as its score stage read them.
cfd_stems <- function(ds)
  cd_read_stems(list(d = ds$job, A = list(FROZEN_ROOT = ds$root, POP = CFD_POP), root = ds$root),
                ds$sites)

## ---- stage: features ----------------------------------------------------------------------
cfd_stage_features <- function(S, ds) {
  idx <- cfd_index(ds)
  fdir <- file.path(ds$out, "features")
  dir.create(ds$out, recursive = TRUE, showWarnings = FALSE)
  frozen_stamp(fdir, ds$root)
  keys <- unique(idx[c("site", "plot")])
  jobs <- lapply(seq_len(nrow(keys)), function(i) list(
    site = keys$site[i], plot = keys$plot[i],
    cells = idx[idx$site == keys$site[i] & idx$plot == keys$plot[i], , drop = FALSE]))
  cat(sprintf("[features] %s: %d cells of %d plots, rung %s, %d workers\n", ds$name, nrow(idx),
              length(jobs), ds$rung, min(S$CORES, length(jobs))))
  t0 <- Sys.time()
  res <- plot_lapply(jobs, cd_features_worker, root = ds$root, cdir = ds$cdir, fdir = fdir,
                     mc.cores = S$CORES)
  stop_failed_plots(vapply(jobs, function(j) paste(j$site, j$plot, sep = "/"), ""), res)
  tab <- do.call(rbind, res)
  rownames(tab) <- NULL
  if (nrow(tab) != nrow(idx) || any(tab$npoints <= 0) || any(tab$n_cand != tab$n_cand_index))
    stop(ds$name, ": features of ", nrow(tab), " cells of ", nrow(idx), call. = FALSE)
  write.csv(tab, file.path(ds$out, "features.csv"), row.names = FALSE)
  cat(sprintf(paste("[features] %s: %d cells in %.1f min; every clip has points (min %d) and",
                    "every cached table the index's n_cand rows (%d candidates, %d deeper)\n"),
              ds$name, nrow(tab), as.numeric(difftime(Sys.time(), t0, units = "mins")),
              as.integer(min(tab$npoints)), sum(tab$n_cand), sum(tab$n_deeper)))
  invisible(tab)
}

## ---- stage: score -------------------------------------------------------------------------
# The candidates a gated configuration accepts on a prepared clip (mcg_apply's
# gate and filter, in the row order of prep$cand).
cfd_gated_accepted <- function(prep, cfg) {
  C <- prep$cand
  if (!nrow(C)) return(logical())
  sp <- prep[["crown_spacing"]]
  g <- mcg_gate(C, prep$cover, cfg, if (is.null(sp)) NA_real_ else sp)
  mcg_filter(C, g$keep, g$exempt)
}

# The identities of the depth library on one prepared clip and its features:
# A (mcd_config(Inf, 0, 5, 0, FALSE, 0.6) and the gated z5_s0_c0.6_e1) and B
# (MCD_STOCK and MCG_STOCK) accept exactly the same candidates. Returns a
# one-row data.frame: A, B (TRUE when equal) and each side's accepted count.
cfd_identities_cell <- function(prep, feat) {
  id <- mcd_identities()
  one <- function(k) {
    d <- mcd_accepted(prep, feat, id[[k]]$depth)
    g <- cfd_gated_accepted(prep, id[[k]]$gated)
    c(ok = as.numeric(identical(d, g)), n_depth = as.numeric(sum(d)),
      n_gated = as.numeric(sum(g)))
  }
  a <- one("A"); b <- one("B")
  data.frame(A = as.logical(a[["ok"]]), A_n_depth = a[["n_depth"]], A_n_gated = a[["n_gated"]],
             B = as.logical(b[["ok"]]), B_n_depth = b[["n_depth"]], B_n_gated = b[["n_gated"]])
}

# One plot: its cells scored (cd_score_job: the grid rows of S and S_low and the
# four references) and the identities of each cell.
cfd_score_job <- function(j, grid, cdir, fdir, K, tol) {
  cells <- cd_score_job(j, grid, cdir, fdir, K, tol)
  ids <- do.call(rbind, lapply(seq_len(nrow(j$cells)), function(i) {
    m <- j$cells[i, ]
    cell <- readRDS(file.path(cdir, m$file))
    fe <- cd_read_feature(fdir, m$site, m$plot, m$rung, cell$prep)
    cbind(data.frame(site = m$site, plot = m$plot, rung = m$rung, n_cand = nrow(fe$feat),
                     stringsAsFactors = FALSE), cfd_identities_cell(cell$prep, fe$feat))
  }))
  list(cells = cells, identities = ids)
}
cfd_score_worker <- function(j, grid, cdir, fdir, K, tol)
  tryCatch(cfd_score_job(j, grid, cdir, fdir, K, tol), error = function(e) {
    message("plot ", j$site, "/", j$plot, " failed: ", conditionMessage(e)); e })

cfd_stage_score <- function(S, ds, D) {
  G <- cfd_dataset_record(ds)
  idx <- cfd_index(ds)
  cd_read_features(list(OUT = ds$out, root = ds$root), idx)   # stamp and every cell present
  stems <- cfd_stems(ds)
  jobs <- cd_plot_jobs(idx, stems)
  fdir <- file.path(ds$out, "features")
  cfgf <- file.path(ds$out, "cells.config.json")
  unlink(cfgf)                         # cells.csv and its record are written together
  cat(sprintf(paste("[score] %s: %d cells of %d plots x (%s) + %d references, K = %d, TOL = %g,",
                    "%d workers\n"), ds$name, nrow(idx), length(jobs),
              paste(D$grid$label, collapse = ", "), length(CD_REFERENCES), G$K, G$tol,
              min(S$CORES, length(jobs))))
  t0 <- Sys.time()
  res <- plot_lapply(jobs, cfd_score_worker, grid = D$grid, cdir = ds$cdir, fdir = fdir,
                     K = G$K, tol = G$tol, mc.cores = S$CORES)
  failed <- vapply(res, function(r) inherits(r, "error"), logical(1))
  if (any(failed))
    stop(ds$name, ": plots failed: ", paste(vapply(jobs[failed], function(j)
      paste(j$site, j$plot, sep = "/"), ""), collapse = ","), call. = FALSE)
  cells <- as.data.frame(data.table::rbindlist(lapply(res, `[[`, "cells")))
  idn <- as.data.frame(data.table::rbindlist(lapply(res, `[[`, "identities")))
  keys <- unique(paste(cells$site, cells$plot, cells$rung))
  if (length(keys) != nrow(idx) || nrow(idn) != nrow(idx))
    stop(ds$name, ": scored ", length(keys), " cells of ", nrow(idx), call. = FALSE)
  ## CHECK S1
  gref <- cd_gated_rows(list(GATED = ds$dir), keys, CD_REFERENCES)
  s1 <- cd_s1_compare(cells[cells$family == "gated", , drop = FALSE], gref)
  want <- length(keys) * length(CD_REFERENCES)
  if (s1$n != want || s1$n_bad) {
    write.csv(s1$bad, file.path(ds$out, "s1_failures.csv"), row.names = FALSE)
    stop(sprintf(paste("%s: CHECK S1 failed: %d of %d reference rows differ from the dataset's",
                       "cells.csv (expected %d rows); see %s"), ds$name, s1$n_bad, s1$n, want,
                 cfd_rel(file.path(ds$out, "s1_failures.csv"))), call. = FALSE)
  }
  unlink(file.path(ds$out, "s1_failures.csv"))
  cv_pass(paste("CHECK S1 %s: %d re-derived reference rows (%d cells x %d) equal the dataset's",
                "cells.csv rows: observed counts exactly, null means within 1e-9 (max |diff| %.3g)"),
          ds$name, s1$n, length(keys), length(CD_REFERENCES), s1$max_null_diff)
  cat(sprintf("[score] %s: identity A in %d of %d cells, identity B in %d of %d cells\n",
              ds$name, sum(idn$A), nrow(idn), sum(idn$B), nrow(idn)))
  cells <- cd_order_cells(cells)
  write.csv(cells, file.path(ds$out, "cells.csv"), row.names = FALSE)
  write.csv(idn, file.path(ds$out, "identities.csv"), row.names = FALSE)
  rec <- list(dataset = ds$name, test = ds$test, role = ds$role,
              dataset_dir = normalizePath(ds$dir, mustWork = FALSE),
              job_dir = normalizePath(ds$job, mustWork = FALSE),
              root = normalizePath(ds$root, mustWork = FALSE),
              clip_manifest_sha256 = frozen_root_id(ds$root), population = CFD_POP,
              sites = I(ds$sites), rung = ds$rung, K = G$K, tol = G$tol,
              dataset_cells_csv_sha256 = G$cells_sha256, dataset_cells_config = G$record,
              gated_grid_sha256 = cv_grid_digest(), depth_grid_sha256 = cd_grid_digest(),
              constants = mcd_constants(), constants_sha256 = cd_constants_digest(),
              declared_depth_config = list(file = normalizePath(D$file, mustWork = FALSE),
                                           sha256 = D$sha256, S = D$S, S_id = D$S_id,
                                           S_low = if (is.null(D$S_low)) NA else D$S_low,
                                           S_low_id = if (is.null(D$S_low_id)) NA else D$S_low_id),
              references = I(CD_REFERENCES),
              n_cells = length(keys), n_plots = length(unique(cv_ids(cells))),
              S1 = list(status = "pass", n = s1$n, n_cells = length(keys),
                        max_null_diff = s1$max_null_diff),
              identities = list(n_cells = nrow(idn), A_agree = sum(idn$A), B_agree = sum(idn$B)))
  cd_write_json(rec, cfgf)
  cat(sprintf("[score] %s: %d rows (%d cells) in %.1f min -> %s\n", ds$name, nrow(cells),
              length(keys), as.numeric(difftime(Sys.time(), t0, units = "mins")),
              cfd_rel(file.path(ds$out, "cells.csv"))))
  invisible(cells)
}

## ---- stage: contrasts (pure parts) --------------------------------------------------------
# The contrasts of one unit: for each subset (CFD_SUBSETS), scope it can form
# (cfd_scopes) and pair (cfd_pairs) one cv_contrast_row at `rung`, tagged with
# the unit, test, role, subset (also as `split`, for cd_md_contrasts), scope
# and pair, read with A2 on cF1 (cd_add_verdicts); `reading` marks the rows of
# the unit's reading scope. NULL when no row is formed.
cfd_unit_contrasts <- function(cells, unit, rung, valid, pairs, n_boot = MT_N_BOOT,
                               seed = MT_SEED) {
  ids <- unique(cv_ids(cells[cells$rung == rung, , drop = FALSE]))
  scopes <- cfd_scopes(unique(cells$site))
  subs <- cfd_subset_ids(ids, valid)
  out <- list()
  for (su in names(subs)) for (sc in names(scopes)) for (k in seq_len(nrow(pairs))) {
    plots <- cd_in_scope(subs[[su]], scopes[[sc]])
    if (!length(plots)) next
    tag <- data.frame(unit = unit$unit, test = unit$test, role = unit$role, subset = su,
                      split = su, scope = sc, pair = pairs$pair[k], stringsAsFactors = FALSE)
    r <- cv_contrast_row(cells, plots, rung, pairs$a[k], pairs$b[k], n_boot, seed, tag)
    if (!is.null(r)) out[[length(out) + 1L]] <- r
  }
  if (!length(out)) return(NULL)
  v <- do.call(rbind, out)
  rownames(v) <- NULL
  v <- cd_add_verdicts(v)
  v$reading <- v$scope == unit$reading_scope
  v
}

# The declared minus stock rows on all plots (`con`) against the campaign's
# rows of the same data, level and scope (`camp`, its contrasts.csv): plots,
# stems and detections must agree; per row the absolute differences of the
# point estimate and of each interval bound in cF1, and the largest over the
# other metrics. A row without a campaign counterpart has matched = FALSE.
CFD_CHECK_METRICS <- c("cF1", "F1", "cPrecision", "cRecall", "precision", "recall")
cfd_campaign_check <- function(con, camp, units = CFD_UNITS) {
  mine <- con[con$pair == CFD_CHECK & con$subset == "all plots", , drop = FALSE]
  camp <- camp[camp$contrast == CFD_CAMPAIGN_PAIR & camp$subset == "all plots", , drop = FALSE]
  if (!nrow(mine)) return(NULL)
  out <- lapply(seq_len(nrow(mine)), function(i) {
    m <- mine[i, ]
    name <- units$campaign[match(m$unit, units$unit)]
    k <- which(camp$dataset == name & as.character(camp$level) == m$rung & camp$scope == m$scope)
    if (length(k) > 1L) stop("the campaign holds ", length(k), " rows of ", name, " / ", m$scope,
                             call. = FALSE)
    base <- data.frame(unit = m$unit, campaign_dataset = name, rung = m$rung, scope = m$scope,
                       n_plots = m$n_plots, n_ref = m$n_ref, matched = length(k) == 1L,
                       stringsAsFactors = FALSE)
    if (!length(k))
      return(cbind(base, data.frame(same_plots_stems_dets = NA, d_cF1 = m$d_cF1,
                                    campaign_d_cF1 = NA_real_, abs_d = NA_real_,
                                    abs_lo = NA_real_, abs_hi = NA_real_,
                                    max_abs_other = NA_real_)))
    c1 <- camp[k, ]
    same <- isTRUE(c1$config_a == m$config_a) && isTRUE(c1$config_b == m$config_b) &&
      isTRUE(c1$n_plots == m$n_plots) && isTRUE(c1$n_ref == m$n_ref) &&
      isTRUE(abs(c1$a_n_det - m$a_n_det) < 1e-9) && isTRUE(abs(c1$b_n_det - m$b_n_det) < 1e-9)
    dif <- function(p, mt) abs(as.numeric(m[[paste0(p, mt)]]) - as.numeric(c1[[paste0(p, mt)]]))
    other <- unlist(lapply(setdiff(CFD_CHECK_METRICS, "cF1"), function(mt)
      c(dif("d_", mt), dif("lo_", mt), dif("hi_", mt))))
    cbind(base, data.frame(same_plots_stems_dets = same, d_cF1 = m$d_cF1,
                           campaign_d_cF1 = c1$d_cF1, abs_d = dif("d_", "cF1"),
                           abs_lo = dif("lo_", "cF1"), abs_hi = dif("hi_", "cF1"),
                           max_abs_other = max(other)))
  })
  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

# T1: the study's ladder rows of S minus the declared arm on its validation
# plots at rungs 8, 4, 2 and 1 (ladder.csv, analysis "ladder"), all scopes.
cfd_t1 <- function(ladder, s) {
  x <- ladder[ladder$analysis == "ladder" & ladder$config_a == s &
                ladder$config_b == CD_DECLARED & ladder$split == "valid" &
                as.character(ladder$rung) %in% CFD_LADDER_RUNGS, , drop = FALSE]
  x <- x[order(match(x$scope, names(CFD_SCOPES)), match(as.character(x$rung),
                                                         CFD_LADDER_RUNGS)), , drop = FALSE]
  rownames(x) <- NULL
  x
}

# The rows the A8 reading reads: T1 (the ladder's Five sites rows, validation
# half) and the primary pair on each test unit's reading scope in each subset.
# data.frame(test, unit, subset, scope, rung, n_plots, d_cF1, lo_cF1, hi_cF1,
# verdict_cF1, verdict_note_cF1).
CFD_A8_COLS <- c("test", "unit", "subset", "scope", "rung", "n_plots", "d_cF1", "lo_cF1",
                 "hi_cF1", "verdict_cF1", "verdict_note_cF1")
cfd_a8_rows <- function(t1, con, units = CFD_UNITS) {
  a <- t1[t1$scope == "Five sites", , drop = FALSE]
  a <- if (nrow(a)) data.frame(test = "T1", unit = "study ladder", subset = "validation half",
                               scope = a$scope, rung = as.character(a$rung), n_plots = a$n_plots,
                               d_cF1 = a$d_cF1, lo_cF1 = a$lo_cF1, hi_cF1 = a$hi_cF1,
                               verdict_cF1 = a$verdict_cF1,
                               verdict_note_cF1 = ifelse(is.na(a$verdict_note_cF1), "",
                                                         a$verdict_note_cF1),
                               stringsAsFactors = FALSE)
  tu <- units[units$role == "test", , drop = FALSE]
  rs <- tu$reading_scope[match(con$unit, tu$unit)]          # NA for a comparison unit
  b <- con[con$pair == CFD_PRIMARY & !is.na(rs) & con$scope == ifelse(is.na(rs), "", rs), ,
           drop = FALSE]
  b <- if (nrow(b)) data.frame(test = b$test, unit = b$unit, subset = b$subset, scope = b$scope,
                               rung = as.character(b$rung), n_plots = b$n_plots, d_cF1 = b$d_cF1,
                               lo_cF1 = b$lo_cF1, hi_cF1 = b$hi_cF1, verdict_cF1 = b$verdict_cF1,
                               verdict_note_cF1 = b$verdict_note_cF1, stringsAsFactors = FALSE)
  x <- rbind(a, b)
  if (is.null(x)) return(as.data.frame(stats::setNames(
    replicate(length(CFD_A8_COLS), character(), simplify = FALSE), CFD_A8_COLS)))
  x <- x[order(x$test, match(x$subset, CFD_SUBSETS), match(x$rung, CFD_LADDER_RUNGS)), ,
         drop = FALSE]
  rownames(x) <- NULL
  x[CFD_A8_COLS]
}

# The reading of A8 on its rows (cfd_a8_rows). In each subset: T2 and T3 must
# read "better" or "not worse"; none of T1 to T4 may read "worse". T2, T3 and
# T4 need a row in each subset and T1 one row per ladder rung in the
# validation half; a missing row fails its test. Returns list(carries,
# failing (one string per failing test, naming the subset, rung and reading),
# sentence).
cfd_a8_reading <- function(rows, s_label = "S") {
  prob <- list()
  add <- function(t, msg) prob[[t]] <<- c(prob[[t]], msg)
  txt <- function(x) cd_verdict_text(x$verdict_cF1, x$verdict_note_cF1)
  for (su in CFD_SUBSETS) {
    r <- rows[rows$subset == su, , drop = FALSE]
    for (t in c("T2", "T3", "T4")) {
      x <- r[r$test == t, , drop = FALSE]
      if (nrow(x) != 1L) { add(t, sprintf("%s: %s", su, if (!nrow(x)) "no contrast" else
        "more than one row")); next }
      bad <- if (t %in% c("T2", "T3")) !x$verdict_cF1 %in% CFD_GOOD else
        x$verdict_cF1 %in% "worse"
      if (bad) add(t, sprintf("%s: %s", su, txt(x)))
    }
    if (su == CFD_SUBSETS[1]) {
      x <- r[r$test == "T1", , drop = FALSE]
      gone <- setdiff(CFD_LADDER_RUNGS, x$rung)
      if (length(gone) || anyDuplicated(x$rung))
        add("T1", sprintf("%s: no single row at rung %s", su,
                          paste(c(gone, x$rung[duplicated(x$rung)]), collapse = ", ")))
      w <- x[x$verdict_cF1 %in% "worse", , drop = FALSE]
      for (i in seq_len(nrow(w))) add("T1", sprintf("%s, rung %s: %s", su, w$rung[i], txt(w[i, ])))
    }
  }
  tests <- intersect(c("T1", "T2", "T3", "T4"), names(prob))
  failing <- vapply(tests, function(t) sprintf("%s (%s)", t, paste(prob[[t]], collapse = "; ")),
                    character(1), USE.NAMES = FALSE)
  carries <- !length(failing)
  sentence <- if (carries)
    sprintf(paste("The selection `%s` carries over (A8): it reads \"better\" or \"not worse\"",
                  "against the declared arm on T2 and on T3 and \"worse\" on none of T1 to T4,",
                  "in either subset."), s_label)
  else sprintf(paste("The selection `%s` does not carry over (A8); the result is stated for the",
                     "2021 native clips only. Failing tests: %s."), s_label,
               paste(failing, collapse = "; "))
  list(carries = carries, failing = failing, sentence = sentence)
}

# Cells of several datasets pooled into one unit: their plots must be disjoint.
cfd_pool_cells <- function(parts) {
  ids <- lapply(parts, function(x) unique(cv_ids(x)))
  all_ids <- unlist(ids)
  if (anyDuplicated(all_ids))
    stop("pooled datasets share plots: ", paste(utils::head(unique(all_ids[duplicated(all_ids)]), 5),
                                                collapse = ", "), call. = FALSE)
  x <- do.call(rbind, parts)
  rownames(x) <- NULL
  x
}

## ---- stage: contrasts ---------------------------------------------------------------------
# One dataset's scored cells, refused unless its record says S1 passed with
# the current declared configurations and the dataset's cells.csv is unchanged.
cfd_read_scored <- function(S, ds, D) {
  f <- file.path(ds$out, "cells.config.json")
  if (!file.exists(f))
    stop(ds$name, ": no scored cells record at ", cfd_rel(f), "; run STAGE=score", call. = FALSE)
  r <- jsonlite::read_json(f, simplifyVector = TRUE)
  dc <- r$declared_depth_config
  na_null <- function(v) if (!length(v) || (length(v) == 1L && is.na(v))) NULL else v
  # the labels and ids decide (the study's analyze stage rewrites its record,
  # with the same configurations, when it is run again)
  if (!identical(r$S1$status, "pass") || !identical(dc$S, D$S) ||
      !identical(as.integer(dc$S_id), D$S_id) || !identical(na_null(dc$S_low), D$S_low) ||
      !identical(na_null(as.integer(dc$S_low_id)), D$S_low_id))
    stop(ds$name, ": the scored cells were made with other declared configurations or without ",
         "a passed S1; re-run STAGE=score", call. = FALSE)
  if (!identical(r$dataset_cells_csv_sha256, cd_file_sha(file.path(ds$dir, "cells.csv"))) ||
      !identical(r$clip_manifest_sha256, frozen_root_id(ds$root)))
    stop(ds$name, ": the dataset's cells.csv or root changed since scoring; re-run STAGE=score",
         call. = FALSE)
  cells <- read.csv(file.path(ds$out, "cells.csv"), stringsAsFactors = FALSE,
                    colClasses = c(rung = "character"))
  list(cells = cells, record = r)
}

# One row of OUT/datasets.csv.
cfd_dataset_row <- function(ds, x, valid) {
  r <- x$record; cells <- x$cells
  ids <- unique(cv_ids(cells))
  st <- cells[cells$config == "stock", , drop = FALSE]
  data.frame(dataset = ds$name, test = ds$test, role = ds$role, campaign_dir = r$dataset_dir,
             root = r$root, clip_manifest_sha256 = r$clip_manifest_sha256, rung = r$rung,
             sites = paste(r$sites, collapse = ","), n_cells = r$n_cells, n_plots = length(ids),
             n_validation_plots = length(intersect(ids, valid)), n_stems = sum(st$n_ref),
             K = r$K, tol = r$tol, dataset_cells_csv_sha256 = r$dataset_cells_csv_sha256,
             S1_rows = r$S1$n, S1_max_null_diff = r$S1$max_null_diff,
             identity_A = sprintf("%d / %d", r$identities$A_agree, r$identities$n_cells),
             identity_B = sprintf("%d / %d", r$identities$B_agree, r$identities$n_cells),
             stringsAsFactors = FALSE)
}

cfd_stage_contrasts <- function(S, D) {
  valid <- cfd_valid_ids(S$STUDY)
  tm <- file.path(S$STUDY, "tables.md")
  if (!file.exists(tm))
    stop("T1 needs the study's held-out run: ", cfd_rel(tm), " does not exist yet", call. = FALSE)
  ladder <- read.csv(file.path(S$STUDY, "ladder.csv"), stringsAsFactors = FALSE,
                     colClasses = c(rung = "character"))
  pairs <- cfd_pairs(D$S, D$S_low)
  t0 <- Sys.time()
  con <- list(); drows <- list()
  for (u in seq_len(nrow(CFD_UNITS))) {
    unit <- CFD_UNITS[u, ]
    parts <- strsplit(unit$parts, ",")[[1]]
    got <- lapply(parts, function(p) {
      ds <- cfd_dataset(S, p)
      x <- cfd_read_scored(S, ds, D)
      drows[[p]] <<- cfd_dataset_row(ds, x, valid)
      x$cells
    })
    cells <- cfd_pool_cells(got)
    rung <- unique(cells$rung)
    if (length(rung) != 1L) stop(unit$unit, ": cells of several rungs", call. = FALSE)
    v <- cfd_unit_contrasts(cells, unit, rung, valid, pairs, S$N_BOOT, MT_SEED)
    cat(sprintf("[contrasts] %s (%s): %d plots (%d validation), %d rows\n", unit$unit,
                unit$test, length(unique(cv_ids(cells))),
                length(intersect(unique(cv_ids(cells)), valid)), if (is.null(v)) 0L else nrow(v)))
    con[[u]] <- v
  }
  con <- as.data.frame(data.table::rbindlist(con, fill = TRUE))
  ds_tab <- do.call(rbind, drows[CFD_DATASETS$name[CFD_DATASETS$name %in% names(drows)]])
  rownames(ds_tab) <- NULL
  ## the check against the campaign (declared minus stock, all plots)
  camp <- read.csv(file.path(S$CAMPAIGN, "analysis", "contrasts.csv"), stringsAsFactors = FALSE,
                   colClasses = c(level = "character"))
  chk <- cfd_campaign_check(con, camp)
  cm <- chk[chk$matched, , drop = FALSE]
  cat(sprintf(paste("[contrasts] campaign check: %d of %d declared-minus-stock rows on all plots",
                    "have a campaign row; plots, stems and detections agree in %d; max |diff|",
                    "of cF1 point %.3g, lower %.3g, upper %.3g; other metrics %.3g\n"),
              nrow(cm), nrow(chk), sum(cm$same_plots_stems_dets), max(cm$abs_d), max(cm$abs_lo),
              max(cm$abs_hi), max(cm$max_abs_other)))
  ## T1 and the reading of A8
  t1 <- cfd_t1(ladder, D$S)
  a8rows <- cfd_a8_rows(t1, con)
  a8 <- cfd_a8_reading(a8rows, D$S)
  a8rows$read_as <- cd_verdict_text(a8rows$verdict_cF1, a8rows$verdict_note_cF1)
  w <- function(x, f) write.csv(x, file.path(S$OUT, f), row.names = FALSE)
  w(con, "contrasts.csv")
  # the same check on contrasts.csv as written: the campaign's numbers are read
  # from its own CSV (15 significant digits), so the written rows compare text
  # with text
  back <- read.csv(file.path(S$OUT, "contrasts.csv"), stringsAsFactors = FALSE,
                   colClasses = c(rung = "character"))
  cw <- cfd_campaign_check(back, camp)
  chk$max_abs_as_written <- ifelse(chk$matched, pmax(cw$abs_d, cw$abs_lo, cw$abs_hi,
                                                     cw$max_abs_other), NA_real_)
  cat(sprintf("[contrasts] campaign check on contrasts.csv as written: max |diff| %.3g\n",
              max(chk$max_abs_as_written, na.rm = TRUE)))
  w(chk, "campaign_check.csv")
  w(a8rows, "a8_reading.csv")
  w(ds_tab, "datasets.csv")
  writeLines(cfd_tables_md(S, D, con, chk, t1, a8rows, a8, ds_tab, valid),
             file.path(S$OUT, "tables.md"))
  cat(sprintf("[contrasts] %d rows in %.1f min -> %s\n", nrow(con),
              as.numeric(difftime(Sys.time(), t0, units = "mins")),
              cfd_rel(file.path(S$OUT, "tables.md"))))
  cat(a8$sentence, "\n")
  invisible(list(contrasts = con, check = chk, t1 = t1, a8 = a8))
}

## ---- Markdown -----------------------------------------------------------------------------
cfd_md_primary <- function(v) {
  if (is.null(v) || !nrow(v)) return(c("(no rows)", ""))
  dl <- function(m) sprintf("%s %s", cd_f3(v[[paste0("d_", m)]]),
                            cd_iv(v[[paste0("lo_", m)]], v[[paste0("hi_", m)]]))
  cd_md(c("Test", "Dataset", "Subset", "Scope", "Plots", "Stems", "Detections S / declared",
          "cF1 S / declared", "ΔcF1 [95% interval]", "Reading (A2)", "Δrecall [95% interval]",
          "Δprecision [95% interval]"),
        sprintf("| %s | %s | %s | %s | %d | %d | %d / %d | %s / %s | %s | %s | %s | %s |",
                ifelse(v$role == "comparison", paste(v$test, "comparison"), v$test), v$unit,
                v$subset, v$scope, as.integer(v$n_plots), as.integer(v$n_ref),
                as.integer(round(v$a_n_det)), as.integer(round(v$b_n_det)), cd_f3(v$a_cF1),
                cd_f3(v$b_cF1), dl("cF1"), cd_verdict_text(v$verdict_cF1, v$verdict_note_cF1),
                dl("recall"), dl("precision")))
}

cfd_tables_md <- function(S, D, con, chk, t1, a8rows, a8, ds_tab, valid) {
  ord <- function(v) v[order(match(v$unit, CFD_UNITS$unit), match(v$subset, CFD_SUBSETS),
                             match(v$scope, names(CFD_SCOPES))), , drop = FALSE]
  prim <- ord(con[con$pair == CFD_PRIMARY, , drop = FALSE])
  readp <- prim[prim$reading, , drop = FALSE]
  units_md <- unlist(lapply(seq_len(nrow(CFD_UNITS)), function(u) {
    x <- CFD_UNITS[u, ]
    v <- ord(con[con$unit == x$unit, , drop = FALSE])
    v <- v[order(match(v$pair, cfd_pairs(D$S, D$S_low)$pair), match(v$subset, CFD_SUBSETS),
                 match(v$scope, names(CFD_SCOPES))), , drop = FALSE]
    c(sprintf("### %s: %s (%s%s)", x$test, x$unit, x$label,
              if (x$role == "comparison") ", comparison" else ""), "",
      cd_md_contrasts(v))
  }))
  cm <- chk[chk$matched, , drop = FALSE]
  t1r <- if (nrow(t1)) sprintf("| %s | %s | %d | %d | %d / %d | %s / %s | %s %s | %s |", t1$scope,
                               t1$rung, as.integer(t1$n_plots), as.integer(t1$n_ref),
                               as.integer(round(t1$a_n_det)), as.integer(round(t1$b_n_det)),
                               cd_f3(t1$a_cF1), cd_f3(t1$b_cF1), cd_f3(t1$d_cF1),
                               cd_iv(t1$lo_cF1, t1$hi_cF1),
                               cd_verdict_text(t1$verdict_cF1, ifelse(is.na(t1$verdict_note_cF1),
                                                                      "", t1$verdict_note_cF1)))
  c("# multichm_depth: confirmation on other densities and flights (A8)", "",
    "<!-- generated by scripts/confirm_multichm_depth.R -->", "",
    cd_para("Provenance:", CD_PROVENANCE),
    cd_para(sprintf(paste("Fixed configurations, never re-selected: S = `%s` (config_id %d)%s,",
                          "read from %s (SHA-256 `%s`); the declared gated arm `%s` and stock.",
                          "Same scorer, K, match radius and shift null as each dataset's own",
                          "cells (S1 below); %d paired plot-bootstrap draws (plots resampled",
                          "within site, seed %d). Validation half: the dataset's plots that are",
                          "validation plots of the study's headline split (%s, %d plots)."),
                    D$S, D$S_id, if (is.null(D$S_low)) ", no S_low" else
                      sprintf(", S_low = `%s` (config_id %d)", D$S_low, D$S_low_id),
                    D$file, D$sha256, CD_DECLARED, S$N_BOOT, MT_SEED,
                    file.path(S$STUDY, "split.csv"), length(valid))),
    "## Reading rule", "",
    cd_para(CD_READING_TEXT),
    cd_para(CFD_A8_TEXT),
    "## The reading of A8", "",
    "T1, the density ladder (the study's ladder.csv, validation plots, S minus declared):", "",
    cd_md(c("Scope", "Rung", "Plots", "Stems", "Detections S / declared", "cF1 S / declared",
            "ΔcF1 [95% interval]", "Reading (A2)"), t1r),
    "T2, T3 and T4 (S minus declared, the reading scope of each dataset), with the same stems",
    "on the 2021 clips beside T3 and T4:", "",
    cfd_md_primary(readp),
    "The rows the reading reads:", "",
    cd_md(c("Test", "Subset", "Scope", "Rung", "Plots", "ΔcF1 [95% interval]", "Reading (A2)"),
          sprintf("| %s | %s | %s | %s | %d | %s %s | %s |", a8rows$test, a8rows$subset,
                  a8rows$scope, a8rows$rung, as.integer(a8rows$n_plots), cd_f3(a8rows$d_cF1),
                  cd_iv(a8rows$lo_cF1, a8rows$hi_cF1), a8rows$read_as)),
    cd_para(sprintf("**%s**", a8$sentence)),
    "## The primary pair in every scope", "",
    cfd_md_primary(prim),
    "## Datasets", "",
    cd_md(c("Dataset", "Test", "Role", "Rung", "Sites", "Cells", "Plots", "Validation plots",
            "Stems", "K / TOL", "S1 rows (max null diff)", "Identity A", "Identity B"),
          sprintf("| %s | %s | %s | %s | %s | %d | %d | %d | %d | %d / %g | %d (%.3g) | %s | %s |",
                  ds_tab$dataset, ds_tab$test, ds_tab$role, ds_tab$rung, ds_tab$sites,
                  as.integer(ds_tab$n_cells), as.integer(ds_tab$n_plots),
                  as.integer(ds_tab$n_validation_plots), as.integer(ds_tab$n_stems),
                  as.integer(ds_tab$K), ds_tab$tol, as.integer(ds_tab$S1_rows),
                  ds_tab$S1_max_null_diff, ds_tab$identity_A, ds_tab$identity_B)),
    cd_para("T4 pools ca2018 and ca2017 (unit ca_sparse_pooled), as the campaign pooled them."),
    "## Check against the earlier campaign (declared minus stock, all plots)", "",
    cd_md(c("Unit", "Campaign dataset", "Scope", "Plots", "Stems", "Same plots, stems, detections",
            "ΔcF1 here", "ΔcF1 campaign", "Abs. diff point", "Abs. diff lower", "Abs. diff upper",
            "Max abs. diff other metrics", "Max abs. diff as written"),
          sprintf("| %s | %s | %s | %d | %d | %s | %s | %s | %.3g | %.3g | %.3g | %.3g | %.3g |",
                  cm$unit, cm$campaign_dataset, cm$scope, as.integer(cm$n_plots),
                  as.integer(cm$n_ref), cm$same_plots_stems_dets, cd_f3(cm$d_cF1),
                  cd_f3(cm$campaign_d_cF1), cm$abs_d, cm$abs_lo, cm$abs_hi, cm$max_abs_other,
                  cm$max_abs_as_written)),
    cd_para(sprintf(paste("Differences in cF1 (point, lower and upper bound) of this run's",
                          "rows against the campaign's contrasts.csv; other metrics: F1,",
                          "cPrecision, cRecall, precision and recall, all three numbers. As",
                          "written: this run's contrasts.csv (15 significant digits, as the",
                          "campaign's) against the campaign's. %d declared-minus-stock rows on",
                          "all plots have no campaign row (the campaign did not form those",
                          "scopes)."), sum(!chk$matched))),
    "## Every contrast", "",
    units_md)
}

## ---- main ---------------------------------------------------------------------------------
cfd_main <- function() {
  S <- cfd_settings()
  lidR::set_lidr_threads(1L)            # one thread; parallelism by processes
  dir.create(S$OUT, recursive = TRUE, showWarnings = FALSE)
  D <- cfd_read_declared(S$STUDY)
  cat(sprintf(paste("[confirm_multichm_depth] STAGE=%s CORES=%d DATASETS=%s; S = %s (id %d), S_low =",
                    "%s; OUT %s\n"), S$STAGE, S$CORES, paste(S$DATASETS, collapse = ","), D$S,
              D$S_id, if (is.null(D$S_low)) "none" else sprintf("%s (id %d)", D$S_low, D$S_low_id),
              cfd_rel(S$OUT)))
  for (nm in S$DATASETS) {
    ds <- cfd_dataset(S, nm)
    if (S$STAGE %in% c("all", "features")) cfd_stage_features(S, ds)
    if (S$STAGE %in% c("all", "score")) cfd_stage_score(S, ds, D)
  }
  if (S$STAGE %in% c("all", "contrasts")) cfd_stage_contrasts(S, D)
  invisible()
}

if (sys.nframe() == 0L) cfd_main()
