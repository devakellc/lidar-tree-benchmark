# Library of the confirmation analysis of the `multichm_gated` arm
# (docs/multichm-gated-confirmation-protocol.md). It turns scored cells (the
# cells.csv of calval_multichm_gated.R, or a file with the same columns made on
# another dataset) into the protocol's contrasts, reads each contrast with the
# protocol's rule, evaluates the protocol's outcome conditions and its rule for
# which configuration is proposed, and runs two of its checks on the
# calibration study's data: R1 (selection with a region held out) and R4 (noise
# in the crown-spacing switch). It also checks how each dataset was scored
# against the scorer's record, sets the stand measures of C3 and C4 beside
# their 2021 values, and redraws the C3 contrasts with other bootstrap seeds.
#
# Nothing here changes a rule of the protocol. Where the protocol's text admits
# two readings, both are reported (see mcgc_reading and mcgc_decide).
#
# Sourced, not run. No side effects. The caller sources calval_lib.R
# (plot_table, assign_split), master_tables_lib.R (mt_plot_weights,
# mt_interval, MT_N_BOOT, MT_SEED) and multichm_gated_lib.R (frozen; mcg_*),
# and attaches data.table. R1's detection check also needs model_bench_lib.R
# (assert_detection_contract); R4 needs sweep_lib.R (plot_lapply),
# model_bench_lib.R (frozen_clip) and lidR.

## ---- the protocol's configurations and contrasts -------------------------------------------
# The five configurations the protocol names, by grid label, and the CHM-VWF
# baseline as the study's cells record it. The labels are the protocol's; the
# tests check that the frozen library gives the same labels.
MCGC_CONFIGS <- c(stock = "stock", floor = "z5_s0_c0_e0", floor_exemption = "z5_s0_c0.6_e1",
                  declared = "z5_s0.75_c0.6_e1_d8", gate_everywhere = "z5_s0.75_c0.6_e1",
                  chm_vwf = "chm_vwf")
MCGC_CONFIG_NAMES <- c(stock = "Stock", floor = "Floor", floor_exemption = "Floor and exemption",
                       declared = "Declared", gate_everywhere = "Gate everywhere",
                       chm_vwf = "CHM-VWF")

# Every contrast is a minus b on one dataset, level, scope and plot subset.
MCGC_CONTRASTS <- data.frame(
  contrast = c("declared_stock", "declared_floor_exemption", "floor_exemption_floor",
               "floor_stock", "declared_gate_everywhere", "declared_chm_vwf",
               "floor_exemption_stock", "gate_everywhere_stock"),
  a = c("declared", "declared", "floor_exemption", "floor", "declared", "declared",
        "floor_exemption", "gate_everywhere"),
  b = c("stock", "floor_exemption", "floor", "stock", "gate_everywhere", "chm_vwf", "stock",
        "stock"),
  what = c("Declared minus stock (primary)", "What the share gate adds",
           "What the exemption adds", "What the floor adds",
           "What the crown-spacing switch adds", "Declared minus CHM-VWF",
           "Floor and exemption minus stock", "Gate everywhere minus stock"),
  stringsAsFactors = FALSE)

MCGC_METRICS <- c("cF1", "F1", "cPrecision", "cRecall", "precision", "recall")
# Pooled scores of each side reported with every contrast.
MCGC_SIDE <- c("n_det", "F1", "cF1", "precision", "recall", "cPrecision", "cRecall", "null_F1")
MCGC_MIN_PLOTS <- 10      # a scope with fewer plots is reported and not read
MCGC_MARGIN    <- -0.02   # "not worse": the interval's lower bound is at least this
MCGC_TESTS     <- c("C1", "C2", "C3", "C4", "C5", "R2", "R3", "baseline")
MCGC_DECIDING  <- c("C1", "C2", "C3")   # condition 3: tests that decide
MCGC_QUALIFY   <- c("C4", "C5")         # tests that qualify the statement

mcgc_ids <- function(r) paste(r$site, r$plot, sep = "::")

## ---- the reading rule -----------------------------------------------------------------------
# The protocol's reading of a contrast from the 95% interval [lo, hi] of its
# measure (vectorised). better: the interval lies above zero (lo > 0); worse:
# it lies below zero (hi < 0); not worse: lo >= -0.02. "Better" also satisfies
# "not worse". An interval inside [-0.02, 0) satisfies both "worse" and "not
# worse" as the protocol words them; it is labelled "worse and not worse" and
# both flags are set, so a condition reads the flag it names. A scope with
# fewer than 10 plots is "not read" and an undefined interval "undefined";
# both have NA flags. Returns data.frame(reading, better, not_worse, worse).
mcgc_reading <- function(lo, hi, n_plots, min_plots = MCGC_MIN_PLOTS, margin = MCGC_MARGIN) {
  n <- length(lo)
  if (length(hi) != n || length(n_plots) != n)
    stop("mcgc_reading: lo, hi and n_plots need one value per contrast", call. = FALSE)
  better <- lo > 0; worse <- hi < 0; not_worse <- lo >= margin
  reading <- ifelse(better, "better",
             ifelse(worse & not_worse, "worse and not worse",
             ifelse(worse, "worse", ifelse(not_worse, "not worse", "inconclusive"))))
  undefined <- !is.finite(lo) | !is.finite(hi)
  unread <- !is.finite(n_plots) | n_plots < min_plots
  reading[undefined] <- "undefined"
  reading[unread] <- "not read"
  off <- undefined | unread
  better[off] <- NA; worse[off] <- NA; not_worse[off] <- NA
  data.frame(reading = reading, better = better, not_worse = not_worse, worse = worse,
             stringsAsFactors = FALSE)
}

## ---- the manifest ---------------------------------------------------------------------------
# A JSON file: {"datasets": [<dataset>, ...]}. Each dataset is an object with
#   name     unique non-empty string (e.g. "calibration levels", "ql2")
#   test     one of C1, C2, C3, C4, C5, R2, R3, baseline
#   cells    path of the scored cells (absolute, or relative to `base`, the job
#            directory)
#   levels   optional array of values of the cells' `rung` column to read (all
#            levels of the file when absent; a level absent from it stops)
#   null     true when the cells carry the shift null (n_det0, TP0, tp_core0),
#            false when they do not (the null columns are then ignored and the
#            measure is F1)
#   scopes   object mapping a scope name to an array of sites, or to an object
#            {"sites": [...], "plots": ["SITE::PLOT", ...]} restricted to those
#            plots. The decision reads the scopes "Five sites", "California" and
#            "Washington" by these names.
#   subsets  optional array of plot subsets, each {"name": ...} (all plots), or
#            {"name": ..., "plots": ["SITE::PLOT", ...]}, or {"name": ...,
#            "split": {"seed": 1, "frac": 0.5, "side": "valid", "cells": <path>}}
#            (one side of the stratified split of calval_lib.R as mcg_split()
#            draws it on the plots of `cells`, default the dataset's own cells).
#            Default: [{"name": "all plots"}].
#   decision_subset  optional name of the subset the decision reads (default:
#            the first subset)
#   scoring  required object: how the cells were scored, checked against the
#            scorer's record before any contrast is computed (mcgc_check_record):
#            {"record": "cells.config.json", "tol": 4, "K": 200,
#             "population": "adopted"}. `record` is the file name of the record
#            in the directory of the cells file (of each part, with `parts`),
#            or "none" for a scorer that writes no record of these fields, with
#            `why` saying so; `tol` (match radius, m) and `population` are
#            required, `K` (shift-null offsets) with a null and never without.
#   parts    optional array of cells files (paths as for `cells`) of which
#            `cells` is the concatenation: the first part's header, then every
#            part's rows in order (mcgc_check_pooled). Each part's record is
#            checked; the pooled file is read.
#   note     optional free text
MCGC_DATASET_KEYS <- c("name", "test", "cells", "levels", "null", "scopes", "subsets",
                       "decision_subset", "scoring", "parts", "note")
MCGC_SCORING_KEYS <- c("record", "tol", "K", "population", "why")

.mcgc_str <- function(v, what) {
  if (!is.character(v) || length(v) != 1L || is.na(v) || !nzchar(v))
    stop("manifest: ", what, " must be one non-empty string", call. = FALSE)
  v
}
.mcgc_strs <- function(v, what) {
  v <- unlist(v)
  if (!is.character(v) || !length(v) || anyNA(v) || any(!nzchar(v)) || anyDuplicated(v))
    stop("manifest: ", what, " must be a non-empty array of distinct strings", call. = FALSE)
  v
}
mcgc_resolve_path <- function(p, base)
  if (grepl("^(/|~)", p)) path.expand(p) else file.path(base, p)

mcgc_scope_spec <- function(x, nm) {
  if (is.list(x) && !is.null(names(x))) {
    bad <- setdiff(names(x), c("sites", "plots"))
    if (length(bad)) stop(sprintf("manifest: scope %s has unknown keys %s", nm,
                                  paste(bad, collapse = ",")), call. = FALSE)
    plots <- if (!is.null(x$plots)) .mcgc_strs(x$plots, paste("plots of scope", nm))
    if (!is.null(plots) && !all(grepl("::", plots, fixed = TRUE)))
      stop("manifest: plots of scope ", nm, " are SITE::PLOT ids", call. = FALSE)
    list(sites = .mcgc_strs(x$sites, paste("sites of scope", nm)), plots = plots)
  } else list(sites = .mcgc_strs(x, paste("sites of scope", nm)), plots = NULL)
}

mcgc_subset_spec <- function(x, base) {
  if (!is.list(x) || is.null(names(x)))
    stop("manifest: a subset is an object with a name", call. = FALSE)
  bad <- setdiff(names(x), c("name", "split", "plots"))
  if (length(bad)) stop("manifest: a subset has unknown keys ", paste(bad, collapse = ","),
                        call. = FALSE)
  nm <- .mcgc_str(x$name, "a subset's name")
  if (!is.null(x$split) && !is.null(x$plots))
    stop("manifest: subset ", nm, " has both split and plots", call. = FALSE)
  if (!is.null(x$plots)) {
    p <- .mcgc_strs(x$plots, paste("plots of subset", nm))
    if (!all(grepl("::", p, fixed = TRUE)))
      stop("manifest: plots of subset ", nm, " are SITE::PLOT ids", call. = FALSE)
    return(list(name = nm, kind = "plots", plots = p))
  }
  if (!is.null(x$split)) {
    s <- x$split
    bad <- setdiff(names(s), c("seed", "frac", "side", "cells"))
    if (!is.list(s) || length(bad))
      stop("manifest: the split of subset ", nm, " takes seed, frac, side and cells",
           call. = FALSE)
    seed <- s$seed; frac <- if (is.null(s$frac)) 0.5 else s$frac
    side <- if (is.null(s$side)) "valid" else s$side
    if (!is.numeric(seed) || length(seed) != 1L || seed != round(seed))
      stop("manifest: the split of subset ", nm, " needs an integer seed", call. = FALSE)
    if (!is.numeric(frac) || length(frac) != 1L || frac <= 0 || frac >= 1)
      stop("manifest: the split fraction of subset ", nm, " must lie in (0, 1)", call. = FALSE)
    if (!identical(side, "valid") && !identical(side, "calib"))
      stop("manifest: the split side of subset ", nm, " is valid or calib", call. = FALSE)
    return(list(name = nm, kind = "split", seed = as.integer(seed), frac = as.numeric(frac),
                side = side, cells = if (!is.null(s$cells))
                  mcgc_resolve_path(.mcgc_str(s$cells, "a split's cells"), base)))
  }
  list(name = nm, kind = "all")
}

# The `scoring` object of dataset `nm` (see the manifest format above).
mcgc_scoring_spec <- function(x, nm, null) {
  if (is.null(x) || !is.list(x) || is.null(names(x)))
    stop("manifest: dataset ", nm, " needs a scoring object (record, tol, population, ",
         "and K with a null)", call. = FALSE)
  bad <- setdiff(names(x), MCGC_SCORING_KEYS)
  if (length(bad)) stop(sprintf("manifest: the scoring of dataset %s has unknown keys %s", nm,
                                paste(bad, collapse = ",")), call. = FALSE)
  rec <- .mcgc_str(x$record, sprintf("the scoring record of dataset %s", nm))
  if (!identical(basename(rec), rec) || rec %in% c(".", ".."))
    stop("manifest: the scoring record of dataset ", nm, " is a file name beside the cells ",
         "file, or none", call. = FALSE)
  tol <- x$tol
  if (!is.numeric(tol) || length(tol) != 1L || !is.finite(tol) || tol <= 0)
    stop("manifest: the scoring of dataset ", nm, " needs a positive tol (m)", call. = FALSE)
  pop <- .mcgc_str(x$population, sprintf("the scoring population of dataset %s", nm))
  K <- x$K
  if (isTRUE(null)) {
    if (!is.numeric(K) || length(K) != 1L || !is.finite(K) || K != round(K) || K < 1)
      stop("manifest: dataset ", nm, " has a null, so its scoring needs an integer K",
           call. = FALSE)
  } else if (!is.null(K))
    stop("manifest: dataset ", nm, " has no null, so its scoring takes no K", call. = FALSE)
  why <- if (!is.null(x$why)) .mcgc_str(x$why, sprintf("the scoring why of dataset %s", nm))
  if (identical(rec, "none") && is.null(why))
    stop("manifest: dataset ", nm, " declares no scoring record and must say why",
         call. = FALSE)
  list(record = rec, tol = as.numeric(tol), K = if (!is.null(K)) as.integer(K),
       population = pop, why = why)
}

mcgc_dataset_spec <- function(x, base) {
  if (!is.list(x) || is.null(names(x))) stop("manifest: a dataset is an object", call. = FALSE)
  bad <- setdiff(names(x), MCGC_DATASET_KEYS)
  if (length(bad)) stop("manifest: a dataset has unknown keys ", paste(bad, collapse = ","),
                        call. = FALSE)
  nm <- .mcgc_str(x$name, "a dataset's name")
  test <- .mcgc_str(x$test, sprintf("the test of dataset %s", nm))
  if (!test %in% MCGC_TESTS)
    stop(sprintf("manifest: dataset %s has test %s; tests are %s", nm, test,
                 paste(MCGC_TESTS, collapse = ", ")), call. = FALSE)
  if (!is.logical(x$null) || length(x$null) != 1L || is.na(x$null))
    stop("manifest: dataset ", nm, " must say null: true or false", call. = FALSE)
  if (!is.list(x$scopes) || !length(x$scopes) || is.null(names(x$scopes)) ||
      any(!nzchar(names(x$scopes))) || anyDuplicated(names(x$scopes)))
    stop("manifest: dataset ", nm, " needs an object of uniquely named scopes", call. = FALSE)
  scopes <- lapply(stats::setNames(names(x$scopes), names(x$scopes)), function(s)
    mcgc_scope_spec(x$scopes[[s]], s))
  subsets <- if (is.null(x$subsets)) list(list(name = "all plots", kind = "all")) else {
    if (!is.list(x$subsets) || !length(x$subsets) || !is.null(names(x$subsets)))
      stop("manifest: the subsets of dataset ", nm, " are an array", call. = FALSE)
    lapply(x$subsets, mcgc_subset_spec, base = base)
  }
  sn <- vapply(subsets, `[[`, "", "name")
  if (anyDuplicated(sn)) stop("manifest: subset names repeat in dataset ", nm, call. = FALSE)
  dec <- if (is.null(x$decision_subset)) sn[1] else
    .mcgc_str(x$decision_subset, "decision_subset")
  if (!dec %in% sn)
    stop(sprintf("manifest: decision_subset %s is not a subset of dataset %s", dec, nm),
         call. = FALSE)
  scoring <- mcgc_scoring_spec(x$scoring, nm, x$null)
  parts <- if (!is.null(x$parts)) {
    p <- .mcgc_strs(x$parts, paste("parts of dataset", nm))
    if (length(p) < 2L) stop("manifest: the parts of dataset ", nm, " are at least two files",
                             call. = FALSE)
    vapply(p, mcgc_resolve_path, "", base = base, USE.NAMES = FALSE)
  }
  list(name = nm, test = test,
       cells = mcgc_resolve_path(.mcgc_str(x$cells, paste("the cells of dataset", nm)), base),
       levels = if (!is.null(x$levels)) .mcgc_strs(x$levels, paste("levels of dataset", nm)),
       null = isTRUE(x$null), scopes = scopes, subsets = subsets, decision_subset = dec,
       scoring = scoring, parts = parts,
       note = if (!is.null(x$note)) as.character(x$note))
}

# Reads the manifest at `path`; relative cell paths resolve against `base`.
# Returns a list of dataset specifications (mcgc_dataset_spec).
mcgc_read_manifest <- function(path, base) {
  if (!file.exists(path)) stop("manifest: no file at ", path, call. = FALSE)
  m <- jsonlite::read_json(path, simplifyVector = FALSE)
  if (!is.list(m) || is.null(m$datasets) || !length(m$datasets) || !is.null(names(m$datasets)))
    stop("manifest: ", path, " needs a non-empty array `datasets`", call. = FALSE)
  ds <- lapply(m$datasets, mcgc_dataset_spec, base = base)
  nm <- vapply(ds, `[[`, "", "name")
  if (anyDuplicated(nm)) stop("manifest: dataset names repeat: ",
                              paste(unique(nm[duplicated(nm)]), collapse = ", "), call. = FALSE)
  ds
}

## ---- scored cells ---------------------------------------------------------------------------
MCGC_KEY_COLS <- c("site", "plot", "rung", "config")
MCGC_REQUIRED_COUNTS <- c("n_ref", "n_det", "TP", "tp_core")
MCGC_NULL_COLS <- c("n_det0", "TP0", "tp_core0", "tp_over0", "tp_under0")
MCGC_NULL_CORE <- c("n_det0", "TP0", "tp_core0")

# Checks and completes a cells data.frame for one dataset: the key and the four
# core count columns are required; other count columns of the library are added
# as NA; without a null (null = FALSE) the null columns are set to NA, and with
# one the core null columns must be known on the rows of the protocol's
# configurations. One row per site, plot, level and configuration; stock and
# the declared configuration must be present. `levels` (NULL = all) keeps those
# levels and stops when one is absent.
mcgc_prepare_cells <- function(cells, null, levels = NULL, what = "cells") {
  cells <- as.data.frame(cells, stringsAsFactors = FALSE)
  miss <- setdiff(c(MCGC_KEY_COLS, MCGC_REQUIRED_COUNTS), names(cells))
  if (length(miss)) stop(what, " lacks columns ", paste(miss, collapse = ","), call. = FALSE)
  for (k in MCGC_KEY_COLS) cells[[k]] <- as.character(cells[[k]])
  for (k in setdiff(MCG_COUNT_COLS, names(cells))) cells[[k]] <- NA_real_
  if (!"config_id" %in% names(cells)) cells$config_id <- NA_integer_
  if (!isTRUE(null)) {
    for (k in MCGC_NULL_COLS) cells[[k]] <- NA_real_
  } else {
    own <- cells$config %in% MCGC_CONFIGS
    if (anyNA(cells[own, MCGC_NULL_CORE]))
      stop(what, " is declared with a null, but its null columns (",
           paste(MCGC_NULL_CORE, collapse = ","), ") are missing on some rows", call. = FALSE)
  }
  if (anyDuplicated(cells[MCGC_KEY_COLS]))
    stop(what, " holds more than one row per site, plot, level and configuration",
         call. = FALSE)
  if (!is.null(levels)) {
    gone <- setdiff(levels, unique(cells$rung))
    if (length(gone)) stop(what, " has no level ", paste(gone, collapse = ","), call. = FALSE)
    cells <- cells[cells$rung %in% levels, , drop = FALSE]
  }
  gone <- setdiff(MCGC_CONFIGS[c("stock", "declared")], cells$config)
  if (length(gone)) stop(what, " lacks configuration ", paste(gone, collapse = ","),
                         call. = FALSE)
  rownames(cells) <- NULL
  cells
}

## ---- how the cells were scored ---------------------------------------------------------------
# Checks the scorer's record beside the cells file `cells` against the
# dataset's `scoring` (mcgc_scoring_spec): the record must exist and hold tol
# and population, and K when the dataset has a null, each equal to the
# manifest's. Stops on a missing record, a missing field or a mismatch.
# Returns list(record, sha256, K, tol, population, clip_manifest_sha256,
# grid_sha256), the record's path and fields (NA when absent), or with record
# "none" list(record = NA, why).
mcgc_check_record <- function(scoring, cells, what = cells) {
  if (identical(scoring$record, "none"))
    return(list(record = NA_character_, why = scoring$why))
  f <- file.path(dirname(cells), scoring$record)
  if (!file.exists(f)) stop(what, ": no scoring record at ", f, call. = FALSE)
  r <- tryCatch(jsonlite::read_json(f, simplifyVector = TRUE), error = function(e)
    stop(what, ": the scoring record ", f, " is not readable JSON", call. = FALSE))
  want <- list(tol = scoring$tol, population = scoring$population)
  if (!is.null(scoring$K)) want$K <- scoring$K
  for (k in names(want)) {
    got <- r[[k]]
    if (is.null(got) || length(got) != 1L || is.na(got))
      stop(sprintf("%s: the scoring record %s holds no %s", what, f, k), call. = FALSE)
    same <- if (is.character(want[[k]])) identical(as.character(got), want[[k]]) else
      isTRUE(suppressWarnings(as.numeric(got)) == want[[k]])
    if (!same) stop(sprintf("%s: scored with %s = %s (%s), the manifest expects %s", what, k,
                            format(got), f, format(want[[k]])), call. = FALSE)
  }
  one <- function(k) if (is.null(r[[k]]) || length(r[[k]]) != 1L) NA else r[[k]]
  list(record = f, sha256 = digest::digest(file = f, algo = "sha256"), K = one("K"),
       tol = one("tol"), population = one("population"),
       clip_manifest_sha256 = one("clip_manifest_sha256"), grid_sha256 = one("grid_sha256"))
}

# A pooled cells file must be the concatenation of its parts as the shell
# makes it: the first part's header, then the rows of every part in order. The
# parts must share one header. Stops otherwise.
mcgc_check_pooled <- function(cells, parts) {
  for (p in c(cells, parts)) if (!file.exists(p)) stop("no cells at ", p, call. = FALSE)
  L <- lapply(parts, readLines, warn = FALSE)
  hdr <- vapply(L, function(x) if (length(x)) x[1] else NA_character_, "")
  if (anyNA(hdr) || length(unique(hdr)) != 1L)
    stop("the parts of ", cells, " do not share one header", call. = FALSE)
  want <- c(hdr[1], unlist(lapply(L, `[`, -1L)))
  if (!identical(readLines(cells, warn = FALSE), want))
    stop(cells, " is not the concatenation of its parts ", paste(parts, collapse = ", "),
         call. = FALSE)
  invisible(TRUE)
}

# Every check of how a manifest dataset was scored: the pooled file against
# its parts, then the record of each file the dataset was scored in (its parts,
# or its cells file). Returns one record (mcgc_check_record) per file.
mcgc_check_scoring <- function(ds) {
  if (length(ds$parts)) mcgc_check_pooled(ds$cells, ds$parts)
  src <- if (length(ds$parts)) ds$parts else ds$cells
  lapply(src, function(p) mcgc_check_record(ds$scoring, p,
                                            what = sprintf("dataset %s (%s)", ds$name, p)))
}

mcgc_read_cells <- function(path, null = TRUE, levels = NULL) {
  if (!file.exists(path)) stop("no cells at ", path, call. = FALSE)
  cells <- data.table::fread(path, colClasses = c(site = "character", plot = "character",
                                                  rung = "character", config = "character"),
                             showProgress = FALSE)
  mcgc_prepare_cells(cells, null, levels, what = path)
}

## ---- plot sets ------------------------------------------------------------------------------
# The calibration and validation plots of the stratified split, drawn as the
# study draws them (cv_split: mcg_split on one row per plot of the cells).
mcgc_split_ids <- function(cells, seed = 1L, frac = 0.5) {
  need <- c("site", "plot", "plotType", "n_dominant", "n_codominant", "n_intermediate",
            "n_suppressed")
  miss <- setdiff(need, names(cells))
  if (length(miss)) stop("the split needs columns ", paste(miss, collapse = ","), call. = FALSE)
  sp <- mcg_split(unique(as.data.frame(cells)[need]), seed, frac)
  ids <- mcgc_ids(sp)
  list(calib = ids[sp$split == "calib"], valid = ids[sp$split == "valid"])
}

# The columns of a cells file the split reads (one row per plot after unique).
mcgc_read_plot_rows <- function(path) {
  if (!file.exists(path)) stop("no cells at ", path, call. = FALSE)
  as.data.frame(data.table::fread(
    path, select = c("site", "plot", "plotType", "n_dominant", "n_codominant",
                     "n_intermediate", "n_suppressed"),
    colClasses = c(site = "character", plot = "character", plotType = "character"),
    showProgress = FALSE))
}

# The plot ids of one subset (NULL = every plot), with `read` reading another
# cells file for a split drawn on it.
mcgc_subset_ids <- function(sub, cells, read = mcgc_read_plot_rows) {
  switch(sub$kind,
         all = NULL,
         plots = sub$plots,
         split = {
           src <- if (is.null(sub$cells)) cells else read(sub$cells)
           mcgc_split_ids(src, sub$seed, sub$frac)[[sub$side]]
         },
         stop("unknown subset kind ", sub$kind, call. = FALSE))
}

# Plots a dataset lists explicitly (in a scope or a subset of kind "plots")
# must be in its cells, so a mistyped id cannot shrink a scope unseen. A plot
# may still be missing at one level (the row's plot count shows it).
mcgc_check_listed <- function(ds, cells) {
  have <- unique(mcgc_ids(cells))
  listed <- c(unlist(lapply(ds$scopes, `[[`, "plots")),
              unlist(lapply(ds$subsets, function(s) if (identical(s$kind, "plots")) s$plots)))
  gone <- setdiff(listed, have)
  if (length(gone))
    stop(sprintf("dataset %s lists plots that are not in its cells: %s", ds$name,
                 paste(utils::head(gone, 10), collapse = ", ")), call. = FALSE)
  invisible(TRUE)
}

# The ids of `ids` ("site::plot") that lie in a scope (sites, optional plots).
mcgc_scope_ids <- function(ids, scope) {
  keep <- sub("::.*", "", ids) %in% scope$sites
  if (!is.null(scope$plots)) keep <- keep & ids %in% scope$plots
  ids[keep]
}

## ---- contrasts ------------------------------------------------------------------------------
# a minus b on the plots of `plots` that both configurations scored in the
# one-level rows L (ids Lid): one wide row with the plots, stems, both sides'
# pooled scores (MCGC_SIDE, prefixed a_ / b_) and, per metric, the difference
# d_ and its percentile interval lo_, hi_ from mcg_contrast (plots resampled
# within site, the same draws for both sides and for observed and null
# counts). NULL when no plot is left.
mcgc_contrast_row <- function(L, Lid, plots, a, b, n_boot = MT_N_BOOT, seed = MT_SEED,
                              metrics = MCGC_METRICS) {
  if (length(unique(L$rung)) > 1L) stop("mcgc_contrast_row compares one level at a time",
                                         call. = FALSE)
  plots <- sort(intersect(intersect(unique(plots), Lid[L$config == a]), Lid[L$config == b]))
  if (!length(plots)) return(NULL)
  keep <- L$config %in% c(a, b) & Lid %in% plots
  ct <- mcg_contrast(L[keep, , drop = FALSE], plots, a, b, n_boot = n_boot, seed = seed,
                     metrics = metrics)
  P <- attr(ct, "pooled")
  if (!isTRUE(all.equal(P$n_ref[1], P$n_ref[2])))
    stop(sprintf("%s and %s were scored against different stems (%g and %g)", a, b,
                 P$n_ref[1], P$n_ref[2]), call. = FALSE)
  side <- function(i, p) stats::setNames(as.list(P[i, MCGC_SIDE]), paste0(p, MCGC_SIDE))
  d <- unlist(lapply(seq_len(nrow(ct)), function(i)
    stats::setNames(c(ct$difference[i], ct$lower[i], ct$upper[i]),
                    paste0(c("d_", "lo_", "hi_"), ct$metric[i]))))
  cbind(data.frame(config_a = a, config_b = b, n_plots = length(plots), n_ref = P$n_ref[1],
                   stringsAsFactors = FALSE),
        as.data.frame(side(1, "a_")), as.data.frame(side(2, "b_")), as.data.frame(as.list(d)))
}

# Every contrast of MCGC_CONTRASTS for one dataset, at each of its levels, on
# each scope and subset. `subset_ids` maps each subset name to its plot ids
# (NULL = all). A contrast whose configurations share no plot there (CHM-VWF
# absent, say) is left out. The reading columns apply mcgc_reading to the
# dataset's measure: corrected F1 with a null, F1 without.
mcgc_dataset_contrasts <- function(ds, cells, subset_ids, n_boot = MT_N_BOOT, seed = MT_SEED,
                                   contrasts = MCGC_CONTRASTS) {
  measure <- if (isTRUE(ds$null)) "cF1" else "F1"
  levels <- if (is.null(ds$levels)) unique(cells$rung) else ds$levels
  out <- list()
  for (lv in levels) {
    L <- cells[cells$rung == lv, , drop = FALSE]
    Lid <- mcgc_ids(L)
    for (sc in names(ds$scopes)) {
      sp <- mcgc_scope_ids(unique(Lid), ds$scopes[[sc]])
      for (su in ds$subsets) {
        sel <- subset_ids[[su$name]]
        plots <- if (is.null(sel)) sp else intersect(sp, sel)
        for (k in seq_len(nrow(contrasts))) {
          r <- mcgc_contrast_row(L, Lid, plots, MCGC_CONFIGS[[contrasts$a[k]]],
                                 MCGC_CONFIGS[[contrasts$b[k]]], n_boot, seed)
          if (is.null(r)) next
          out[[length(out) + 1L]] <- cbind(
            data.frame(dataset = ds$name, test = ds$test, level = lv, scope = sc,
                       subset = su$name, contrast = contrasts$contrast[k],
                       what = contrasts$what[k], measure = measure, stringsAsFactors = FALSE), r)
        }
      }
    }
  }
  if (!length(out)) return(NULL)
  res <- do.call(rbind, out)
  rd <- mcgc_reading(res[[paste0("lo_", measure)]], res[[paste0("hi_", measure)]], res$n_plots)
  res <- cbind(res, data.frame(d_measure = res[[paste0("d_", measure)]],
                               lo_measure = res[[paste0("lo_", measure)]],
                               hi_measure = res[[paste0("hi_", measure)]]), rd)
  rownames(res) <- NULL
  res
}

## ---- the decision ---------------------------------------------------------------------------
.mcgc_and <- function(v) if (any(v %in% FALSE)) FALSE else if (anyNA(v)) NA else TRUE
.mcgc_or  <- function(v) if (any(v %in% TRUE)) TRUE else if (anyNA(v)) NA else FALSE
.mcgc_status <- function(v) if (is.na(v)) "pending" else if (v) "holds" else "fails"
.mcgc_num <- function(x) ifelse(is.na(x), "NA", sub("^-", "−", sprintf("%+.3f", x)))

# One piece of evidence for the decision: the contrast `contrast` read on the
# decision subset of every dataset of test `test`, on scope `scope`, at
# `levels` (NULL = every level of the dataset). `need`: "better" (better at
# every level), "not_worse" (not worse, better included, at every level) or
# "worse" (worse at some level). A scope not read cannot be better or not
# worse, and does not count as worse. No dataset of the test: NA (pending).
# Returns list(value, detail).
mcgc_evidence <- function(con, datasets, test, scope, contrast, need, levels = NULL) {
  ds <- Filter(function(d) identical(d$test, test), datasets)
  if (!length(ds)) return(list(value = NA, detail = sprintf("%s: not run", test)))
  rows <- do.call(rbind, lapply(ds, function(d) {
    k <- con$dataset == d$name & con$subset == d$decision_subset & con$scope == scope &
      con$contrast == contrast
    if (!is.null(levels)) k <- k & con$level %in% levels
    con[k, , drop = FALSE]
  }))
  if (is.null(rows) || !nrow(rows))
    return(list(value = NA, detail = sprintf("%s: no %s row on scope %s", test, contrast, scope)))
  v <- switch(need,
              better = all(rows$better %in% TRUE),
              not_worse = all(rows$not_worse %in% TRUE),
              worse = any(rows$worse %in% TRUE),
              stop("unknown need ", need, call. = FALSE))
  list(value = v, detail = paste(sprintf("%s %s %s %s: %s %s [%s, %s], %d plots", test,
                                         rows$dataset, rows$level, scope, rows$reading,
                                         .mcgc_num(rows$d_measure), .mcgc_num(rows$lo_measure),
                                         .mcgc_num(rows$hi_measure), as.integer(rows$n_plots)),
                                 collapse = "; "))
}

# Whether `contrast` is worse on any scope read of the tests `tests` (every
# level, decision subsets). FALSE when no scope is worse and every test has a
# dataset (or, among `left_out`, was left out); NA when one is missing.
mcgc_no_worse <- function(con, datasets, tests, contrast, left_out = character()) {
  have <- unique(vapply(datasets, `[[`, "", "test"))
  worse <- character()
  for (d in Filter(function(d) d$test %in% tests, datasets)) {
    k <- con$dataset == d$name & con$subset == d$decision_subset & con$contrast == contrast &
      con$worse %in% TRUE
    r <- con[k, , drop = FALSE]
    worse <- c(worse, sprintf("%s %s %s %s: %s %s [%s, %s]", d$test, d$name, r$level, r$scope,
                              r$reading, .mcgc_num(r$d_measure), .mcgc_num(r$lo_measure),
                              .mcgc_num(r$hi_measure)))
  }
  missing <- setdiff(tests, c(have, left_out))
  v <- if (length(worse)) FALSE else if (length(missing)) NA else TRUE
  detail <- c(if (length(worse)) paste("worse on", paste(worse, collapse = "; ")),
              if (!length(worse)) "worse on no scope read",
              if (length(missing)) paste("not run:", paste(missing, collapse = ", ")),
              if (length(intersect(tests, left_out)))
                paste("left out:", paste(intersect(tests, left_out), collapse = ", ")))
  list(value = v, detail = paste(detail, collapse = "; "))
}

# The four conditions of "What each outcome allows" for one configuration
# against stock (contrast `contrast`, e.g. "declared_stock"). Condition 3 is
# read on C1 to C3, the tests that decide; the protocol's text names C1 to C5
# and also says C4 and C5 qualify the statement instead of deciding it, so the
# literal reading over C1 to C5 is returned as `cond3_literal` and the
# qualifications of C4 and C5 as `qualify`.
mcgc_conditions <- function(con, datasets, contrast, left_out = character()) {
  e <- function(...) mcgc_evidence(con, datasets, ...)
  c1 <- list(e("C1", "Five sites", contrast, "better"), e("C3", "Washington", contrast, "better"))
  c2 <- list(e("C1", "California", contrast, "not_worse"),
             e("C2", "California", contrast, "not_worse"))
  c3 <- mcgc_no_worse(con, datasets, MCGC_DECIDING, contrast)
  c3l <- mcgc_no_worse(con, datasets, c(MCGC_DECIDING, MCGC_QUALIFY), contrast, left_out)
  c4 <- e("R2", "Five sites", contrast, "better", levels = "native")
  q <- lapply(stats::setNames(MCGC_QUALIFY, MCGC_QUALIFY), function(t) {
    r <- mcgc_no_worse(con, datasets, t, contrast, left_out)
    limit <- c(C4 = "limits the statement to the NEON instruments",
               C5 = "limits the statement to the forest types of the benchmark")[[t]]
    list(value = r$value, detail = if (t %in% left_out) paste(t, "left out: not tested") else
      if (isFALSE(r$value)) paste0(r$detail, " (", limit, ")") else r$detail)
  })
  pieces <- function(l) paste(vapply(l, `[[`, "", "detail"), collapse = " | ")
  list(cond1 = list(value = .mcgc_and(vapply(c1, function(x) x$value, NA)), detail = pieces(c1)),
       cond2 = list(value = .mcgc_and(vapply(c2, function(x) x$value, NA)), detail = pieces(c2)),
       cond3 = c3, cond3_literal = c3l, cond4 = c4, qualify = q)
}

# A part of the configuration is kept when its contrast is better on C1 over
# the five sites or on C3 over both Washington sites, and worse on neither.
mcgc_part_kept <- function(con, datasets, contrast) {
  e <- function(...) mcgc_evidence(con, datasets, ...)
  b1 <- e("C1", "Five sites", contrast, "better"); b3 <- e("C3", "Washington", contrast, "better")
  w1 <- e("C1", "Five sites", contrast, "worse"); w3 <- e("C3", "Washington", contrast, "worse")
  better <- .mcgc_or(c(b1$value, b3$value))
  worse <- .mcgc_or(c(w1$value, w3$value))
  list(value = .mcgc_and(c(better, !worse)), detail = paste(b1$detail, b3$detail, sep = " | "))
}

# The decision table: the four conditions for the declared configuration and
# for floor and exemption against stock, the outcome, the parts kept and the
# configuration proposed. Absent tests leave a row pending. Returns a
# data.frame(item, configuration, status, evidence).
mcgc_decide <- function(con, datasets, left_out = character()) {
  rows <- list()
  add <- function(item, cfg, status, evidence) rows[[length(rows) + 1L]] <<- data.frame(
    item = item, configuration = cfg, status = status, evidence = evidence,
    stringsAsFactors = FALSE)
  lab <- c(cond1 = "1. Better on C1 (five sites) and C3 (Washington)",
           cond2 = "2. Not worse in California on C1 and C2",
           cond3 = "3. Worse on no scope read in C1 to C3",
           cond3_literal = "3 as worded: worse on no scope read in C1 to C5",
           cond4 = "4. Better at 2 m, native density, five sites (R2)")
  cond <- list()
  for (cf in c("declared", "floor_exemption")) {
    k <- mcgc_conditions(con, datasets, paste0(cf, "_stock"), left_out)
    cond[[cf]] <- k
    for (nm in names(lab)) add(lab[[nm]], MCGC_CONFIG_NAMES[[cf]], .mcgc_status(k[[nm]]$value),
                               k[[nm]]$detail)
    for (t in names(k$qualify)) add(sprintf("%s qualifies (worse limits the statement)", t),
                                    MCGC_CONFIG_NAMES[[cf]],
                                    if (t %in% left_out) "left out" else
                                      .mcgc_status(k$qualify[[t]]$value),
                                    k$qualify[[t]]$detail)
  }
  v <- function(cf) vapply(c("cond1", "cond2", "cond3", "cond4"), function(n)
    cond[[cf]][[n]]$value, NA)
  d <- v("declared"); f <- v("floor_exemption")
  outcome <- if (isTRUE(.mcgc_and(d))) "supported for the declared configuration" else
    if (anyNA(d) && !any(d %in% FALSE)) "pending" else {
      fails13 <- .mcgc_or(!d[c("cond1", "cond3")])
      if (isTRUE(.mcgc_and(f))) {
        if (is.na(fails13)) "pending (conditions 1 and 3 of the declared configuration)"
        else if (fails13) "made for floor and exemption" else paste(
          "not covered by the protocol: the declared configuration fails only condition",
          paste(sub("cond", "", names(d)[d %in% FALSE]), collapse = " and "),
          "and floor and exemption passes all four")
      } else if (anyNA(f) && !any(f %in% FALSE)) "pending (floor and exemption)"
      else "no general statement: the arm stays a post hoc result for closed stands"
    }
  qual <- unlist(lapply(c("declared", "floor_exemption"), function(cf)
    vapply(names(cond[[cf]]$qualify), function(t)
      if (isFALSE(cond[[cf]]$qualify[[t]]$value)) paste(MCGC_CONFIG_NAMES[[cf]], t, "worse")
      else NA_character_, "")))
  add("Outcome", "", outcome, paste(c(
    sprintf("declared: %s", paste(names(d), vapply(d, .mcgc_status, ""), collapse = ", ")),
    sprintf("floor and exemption: %s", paste(names(f), vapply(f, .mcgc_status, ""),
                                              collapse = ", ")),
    if (any(!is.na(qual))) paste("qualified:", paste(qual[!is.na(qual)], collapse = "; "))),
    collapse = "; "))
  gate <- mcgc_part_kept(con, datasets, "declared_floor_exemption")
  exem <- mcgc_part_kept(con, datasets, "floor_exemption_floor")
  add("Share gate kept (declared minus floor and exemption)", "", .mcgc_status(gate$value),
      gate$detail)
  add("Exemption kept (floor and exemption minus floor)", "", .mcgc_status(exem$value),
      exem$detail)
  proposal <- if (is.na(gate$value)) "pending" else if (gate$value) {
    if (isFALSE(exem$value)) paste("declared (the share gate is kept; the exemption's own rule",
                                   "fails, which the protocol does not resolve)")
    else "declared"
  } else if (is.na(exem$value)) "pending (exemption)" else if (exem$value)
    "floor and exemption" else "floor"
  add("Configuration proposed", "", proposal, "share gate first, then the exemption")
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

## ---- R1: selection with a region held out ---------------------------------------------------
# Selects on the native-density grid rows (config_id known) of the plots of
# `sites` with mcg_select (ties to the lowest config_id). Returns the pick, the
# selection plots, the whole ranking (criterion descending, then config_id)
# with each configuration's margin below the pick, the configurations tied
# with the pick in the pooled criterion, and those with the pick's count
# columns (observed and null) on every selection plot.
mcgc_r1_select <- function(cells, sites, criterion = "cF1") {
  nat <- cells[cells$rung == "native" & !is.na(cells$config_id), , drop = FALSE]
  ids <- mcgc_ids(nat)
  plots <- sort(unique(ids[nat$site %in% sites]))
  if (!length(plots)) stop("R1: no native plots at ", paste(sites, collapse = ","), call. = FALSE)
  id <- mcg_select(nat, plots, criterion)
  R <- nat[ids %in% plots, , drop = FALSE]
  P <- mcg_pool(R, "config_id")
  labs <- unique(nat[c("config_id", "config")])
  P$config <- labs$config[match(P$config_id, labs$config_id)]
  v <- P[[criterion]]
  P$margin <- v[P$config_id == id] - v
  P <- P[order(-v, P$config_id), , drop = FALSE]
  P$rank <- seq_len(nrow(P))
  rownames(P) <- NULL
  list(config_id = id, label = P$config[P$config_id == id], criterion = criterion,
       sites = sites, plots = plots, ranking = P,
       tied_score = P$config_id[abs(P$margin) <= 1e-12 & P$config_id != id],
       same_counts = setdiff(mcgc_same_counts(R, id), id))
}

# The config_ids whose count columns (MCG_COUNT_COLS, NA equal to NA) equal
# those of config `id` on every plot of `rows` (one level, grid rows).
mcgc_same_counts <- function(rows, id) {
  dt <- data.table::as.data.table(rows)[, c("site", "plot", "config_id", MCG_COUNT_COLS),
                                        with = FALSE]
  ref <- dt[config_id == id]
  m <- merge(dt, ref, by = c("site", "plot"), suffixes = c("", ".ref"))
  same <- Reduce(`&`, lapply(MCG_COUNT_COLS, function(k) {
    a <- m[[k]]; b <- m[[paste0(k, ".ref")]]
    (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
  }))
  n <- m[, list(n = .N), by = "config_id"]
  ok <- m[same, list(n_same = .N), by = "config_id"]
  ok <- merge(ok, n, by = "config_id")
  sort(ok$config_id[ok$n_same == ok$n & ok$n == nrow(ref)])
}

# Of the configurations `config_ids`, those whose detections equal the pick's
# (`id`) on every selection plot at `rung`, from the study's stored
# preparations (candidates/<file>, mcg_apply). `index` is candidates.csv.
mcgc_same_detections <- function(cand_dir, index, plots, rung, id, config_ids,
                                 grid = mcg_grid()) {
  cfg <- function(k) mcg_config(grid$zmin[k], grid$min_share[k], grid$cover_min[k],
                                grid$surface_exempt[k], grid$spacing_min[k])
  same <- stats::setNames(rep(TRUE, length(config_ids)), config_ids)
  idx <- index[index$rung == rung & mcgc_ids(index) %in% plots, , drop = FALSE]
  if (nrow(idx) != length(plots)) stop("R1: the candidate index lacks some selection plots",
                                       call. = FALSE)
  key <- function(d) { d <- d[order(d$x, d$y, d$z), ]; paste(d$x, d$y, d$z, collapse = ";") }
  for (i in seq_len(nrow(idx))) {
    prep <- readRDS(file.path(cand_dir, idx$file[i]))$prep
    k0 <- key(mcg_apply(prep, cfg(id)))
    for (k in config_ids[same[as.character(config_ids)]])
      if (!identical(key(mcg_apply(prep, cfg(k))), k0)) same[[as.character(k)]] <- FALSE
  }
  config_ids[same]
}

## ---- R4: noise in the crown-spacing switch -------------------------------------------------
MCGC_R4_STEPS <- c(0, 0.25, 0.5, 0.75)

# The 16 placements of the 1 m grid: every combination of the steps in x and
# y, the unshifted one first.
mcgc_r4_shifts <- function(steps = MCGC_R4_STEPS) {
  g <- expand.grid(dx = steps, dy = steps, KEEP.OUT.ATTRS = FALSE)
  g <- g[order(g$dx != 0 | g$dy != 0, g$dx, g$dy), , drop = FALSE]
  g$placement <- sprintf("x%g_y%g", g$dx, g$dy)
  rownames(g) <- NULL
  g
}

# The clip translated by (dx, dy) m: every point moves and the grid, fixed by
# the coordinates (multiples of the cell size), stays, so the grid falls
# elsewhere on the stand. Unshifted, the clip is returned as read. A shifted
# copy is re-quantized to the header's scale and its header updated.
mcgc_translate <- function(las, dx, dy) {
  if (dx == 0 && dy == 0) return(las)
  l <- las
  l@data <- data.table::copy(las@data)
  data.table::set(l@data, j = "X", value = l@data$X + dx)
  data.table::set(l@data, j = "Y", value = l@data$Y + dy)
  lidR::las_quantize(l, by_reference = TRUE)
  lidR::las_update(l)
}

# Crown spacing from the crown count and area as mcg_crowns computes it
# (sqrt(area / n); NA without a surface or with area 0, Inf with no crown), so
# a table read back from CSV regains full precision.
mcgc_spacing <- function(area, n)
  ifelse(is.na(area) | is.na(n) | area == 0, NA_real_, sqrt(area / n))

# Crowns (the frozen library's mcg_crowns) of one clip at every placement.
mcgc_crowns_placements <- function(las, shifts = mcgc_r4_shifts()) {
  do.call(rbind, lapply(seq_len(nrow(shifts)), function(i) {
    r <- mcg_crowns(mcgc_translate(las, shifts$dx[i], shifts$dy[i]))
    data.frame(placement = shifts$placement[i], dx = shifts$dx[i], dy = shifts$dy[i],
               n_crowns = r$n, crown_area = r$area, crown_spacing = r$spacing,
               stringsAsFactors = FALSE)
  }))
}

# One clip of the candidate index: read from the sealed root through the
# study's provider (frozen_clip with no catalog) and counted at every
# placement. lidR runs on one thread (mcg_crowns pins it).
mcgc_r4_job <- function(cell, root, shifts = mcgc_r4_shifts()) {
  rung <- if (identical(cell$rung, "native")) NA else as.numeric(cell$rung)
  clip <- frozen_clip(NULL, cell$site, cell$plot, rung, cell$cx, cell$cy, cell$half, root)
  if (is.null(clip)) stop(sprintf("R4: %s/%s/%s is not usable in the sealed root", cell$site,
                                  cell$plot, cell$rung), call. = FALSE)
  las <- lidR::readLAS(clip$normalized)
  cbind(data.frame(site = cell$site, plot = cell$plot, rung = cell$rung,
                   stringsAsFactors = FALSE), mcgc_crowns_placements(las, shifts))
}
mcgc_r4_worker <- function(cell, root, shifts)
  tryCatch(mcgc_r4_job(cell, root, shifts), error = function(e) {
    message("R4 ", cell$site, "/", cell$plot, "/", cell$rung, " failed: ", conditionMessage(e))
    e })

# Whether each cell's closed stand gets the declared share gate at a given
# crown spacing, with the frozen library's switches (mcg_closed, mcg_spaced on
# MCG_DECLARED). NA cover or spacing where it decides stops.
mcgc_gated <- function(cover, spacing, cfg = MCG_DECLARED) {
  vapply(seq_along(cover), function(i) {
    closed <- mcg_closed(cover[i], cfg)
    if (is.na(closed)) stop("R4: a cell's canopy cover is unknown", call. = FALSE)
    if (!closed) return(FALSE)
    spaced <- mcg_spaced(spacing[i], cfg)
    if (is.na(spaced)) stop("R4: a closed cell's crown spacing is unknown", call. = FALSE)
    spaced
  }, logical(1))
}

# The declared configuration recomposed from existing cells at a placement's
# crown spacing: a closed cell whose spacing reaches the declared spacing_min
# takes the rows of gate everywhere, any other cell those of floor and
# exemption. `spacing` holds site, plot, rung and crown_spacing, one row per
# cell; the cover is the cell's own (cells$cover). Returns the recomposed rows
# under config `label` (config_id NA, crown_spacing the placement's) with a
# logical column `gated`.
mcgc_recompose <- function(cells, spacing, label = "declared_recomposed",
                           gated_config = MCGC_CONFIGS[["gate_everywhere"]],
                           ungated_config = MCGC_CONFIGS[["floor_exemption"]]) {
  key <- function(r) paste(r$site, r$plot, r$rung, sep = "::")
  g <- cells[cells$config == gated_config, , drop = FALSE]
  u <- cells[cells$config == ungated_config, , drop = FALSE]
  if (!nrow(g) || anyDuplicated(key(g)) || !setequal(key(g), key(u)) || anyDuplicated(key(u)))
    stop("R4: gate everywhere and floor and exemption must cover the same cells once each",
         call. = FALSE)
  u <- u[match(key(g), key(u)), , drop = FALSE]
  s <- spacing[match(key(g), key(spacing)), , drop = FALSE]
  if (anyNA(s$site)) stop("R4: the spacing table lacks some cells", call. = FALSE)
  gated <- mcgc_gated(g$cover, s$crown_spacing)
  out <- u
  out[gated, ] <- g[gated, ]
  out$config <- label
  out$config_id <- NA_integer_
  out$crown_spacing <- s$crown_spacing
  out$gated <- gated
  rownames(out) <- NULL
  out
}

# Cell-by-cell comparison of every count column between two row sets of one
# configuration each (same cells). Returns list(n_cells, n_columns,
# n_mismatched_cells, max_abs_diff).
mcgc_compare_counts <- function(x, y) {
  key <- function(r) paste(r$site, r$plot, r$rung, sep = "::")
  if (!setequal(key(x), key(y)) || anyDuplicated(key(x)) || anyDuplicated(key(y)))
    stop("the two row sets cover different cells", call. = FALSE)
  y <- y[match(key(x), key(y)), , drop = FALSE]
  dif <- sapply(MCG_COUNT_COLS, function(k) {
    a <- as.numeric(x[[k]]); b <- as.numeric(y[[k]])
    ifelse(is.na(a) & is.na(b), 0, abs(a - b))
  })
  dif <- matrix(dif, ncol = length(MCG_COUNT_COLS))
  bad <- apply(dif, 1, function(v) any(is.na(v) | v > 0))
  list(n_cells = nrow(x), n_columns = length(MCG_COUNT_COLS), n_mismatched_cells = sum(bad),
       max_abs_diff = if (all(is.na(dif))) NA_real_ else max(dif, na.rm = TRUE))
}

# Per cell, the spread of its crown spacing over the placements: the unshifted
# value, min, max, range and standard deviation, the cell's cover and closed
# state, whether it is gated unshifted and in how many placements it is.
mcgc_r4_spread <- function(sp, cover) {
  dt <- data.table::as.data.table(sp)
  cv <- data.table::as.data.table(cover)[, c("site", "plot", "rung", "cover"), with = FALSE]
  dt <- merge(dt, unique(cv), by = c("site", "plot", "rung"))
  dt[, gated := mcgc_gated(cover, crown_spacing)]
  dt[, closed := cover >= MCG_DECLARED$cover_min]
  out <- dt[, list(cover = cover[1], closed = closed[1],
                   spacing0 = crown_spacing[dx == 0 & dy == 0],
                   spacing_min = min(crown_spacing), spacing_max = max(crown_spacing),
                   spacing_range = max(crown_spacing) - min(crown_spacing),
                   spacing_sd = stats::sd(crown_spacing),
                   n_crowns_min = min(n_crowns), n_crowns_max = max(n_crowns),
                   gated0 = gated[dx == 0 & dy == 0], n_gated = sum(gated), n_placements = .N),
            by = c("site", "plot", "rung")]
  as.data.frame(out)
}

# Per level and placement: closed cells, gated cells, and the closed cells whose
# gated state differs from the unshifted one (both directions).
mcgc_r4_state <- function(sp, cover) {
  dt <- data.table::as.data.table(sp)
  cv <- unique(data.table::as.data.table(cover)[, c("site", "plot", "rung", "cover"),
                                                with = FALSE])
  dt <- merge(dt, cv, by = c("site", "plot", "rung"))
  dt[, gated := mcgc_gated(cover, crown_spacing)]
  dt[, closed := cover >= MCG_DECLARED$cover_min]
  g0 <- dt[dx == 0 & dy == 0, list(site, plot, rung, gated0 = gated)]
  dt <- merge(dt, g0, by = c("site", "plot", "rung"))
  as.data.frame(dt[, list(n_cells = .N, n_closed = sum(closed), n_gated = sum(gated),
                          n_differ = sum(closed & gated != gated0),
                          n_on_off = sum(closed & gated0 & !gated),
                          n_off_on = sum(closed & !gated0 & gated)),
                   by = c("rung", "placement", "dx", "dy")])
}

## ---- stand measures on another flight (C3, C4) --------------------------------------------
# The protocol asks, on C3 and C4, for canopy cover, crown spacing and the
# first-return share of deeper-layer peaks beside their 2021 values on the same
# plots, and for the plots whose closed or gated state differs.

# One clip's deeper-layer candidates (layer > 1 of a preparation's `cand`,
# which holds `layer` and `share`) and their first-return shares, with the
# definition confirm_gated_3dep.R records beside the 3DEP stand measures
# (c3_deep_shares): the number of candidates and of deeper-layer ones, the
# median of their first-return share (NA shares dropped; NA without a
# deeper-layer candidate) and the fraction at or above `min_share` (the
# declared gate's 0.75).
mcgc_deep_shares <- function(cand, min_share = MCG_DECLARED$min_share) {
  if (!all(c("layer", "share") %in% names(cand)))
    stop("deeper-layer shares need the candidates' layer and share", call. = FALSE)
  d <- cand[cand$layer > 1L, , drop = FALSE]
  list(n_cand = nrow(cand), n_deep = nrow(d),
       deep_share_median = if (nrow(d)) stats::median(d$share, na.rm = TRUE) else NA_real_,
       deep_share_ge = if (nrow(d)) mean(!is.na(d$share) & d$share >= min_share) else NA_real_)
}

# Per clip of one candidate directory (a calval_multichm_gated.R candidate
# stage: `index` is its candidates.csv, `read(file)` returns the stored
# preparation): the clip's cover, crown spacing and top height as the index
# records them, and its deeper-layer shares (mcgc_deep_shares). The
# preparation's candidate count must equal the index's.
mcgc_clip_shares <- function(index, read, side) {
  rows <- lapply(seq_len(nrow(index)), function(i) {
    prep <- read(index$file[i])
    if (nrow(prep$cand) != index$n_cand[i])
      stop(sprintf("%s/%s: %d candidates stored, %d in the index", index$site[i], index$plot[i],
                   nrow(prep$cand), index$n_cand[i]), call. = FALSE)
    sh <- mcgc_deep_shares(prep$cand)
    data.frame(side = side, site = index$site[i], plot = index$plot[i], rung = index$rung[i],
               cover = index$cover[i], crown_spacing = index$crown_spacing[i],
               top_height = index$top_height[i], n_cand = sh$n_cand, n_deep = sh$n_deep,
               deep_share_median = sh$deep_share_median, deep_share_ge = sh$deep_share_ge,
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# Closed (cover at least the declared cover_min) and widely spaced (crown
# spacing at least its spacing_min) per clip; unknown values count as neither,
# as confirm_gated_3dep.R counts them (c3_state).
mcgc_stand_state <- function(cover, spacing, cfg = MCG_DECLARED) {
  closed <- !is.na(cover) & cover >= cfg$cover_min
  spaced <- !is.na(spacing) & spacing >= cfg$spacing_min
  data.frame(closed = closed, spaced = spaced, gated = closed & spaced)
}

# The stand measures of the same plots on two clips side by side: `a` and `b`
# hold one row per site and plot with cover, crown_spacing and
# deep_share_median (the new flight and the 2021 clip). Per scope (a named list
# of site vectors): the plots in both, the median over plots of each measure
# on each side, the closed, widely spaced and gated plots on each side and the
# plots whose state differs. Every plot of `a` must have a row in `b`.
mcgc_stand_transfer <- function(a, b, scopes, labels = c("new", "2021")) {
  key <- function(x) paste(x$site, x$plot, sep = "::")
  if (anyDuplicated(key(a)) || anyDuplicated(key(b)))
    stop("the stand measures hold a plot twice", call. = FALSE)
  gone <- setdiff(key(a), key(b))
  if (length(gone)) stop("no 2021 stand measures for ", paste(utils::head(gone, 5), collapse = ", "),
                         call. = FALSE)
  b <- b[match(key(a), key(b)), , drop = FALSE]
  sa <- mcgc_stand_state(a$cover, a$crown_spacing); sb <- mcgc_stand_state(b$cover, b$crown_spacing)
  med <- function(v) if (length(v) && any(!is.na(v))) stats::median(v, na.rm = TRUE) else NA_real_
  out <- lapply(names(scopes), function(sc) {
    k <- a$site %in% scopes[[sc]]
    if (!any(k)) return(NULL)
    r <- data.frame(scope = sc, plots = sum(k), stringsAsFactors = FALSE)
    for (m in c("cover", "crown_spacing", "deep_share_median")) {
      r[[paste0(m, "_", labels[1])]] <- med(a[[m]][k])
      r[[paste0(m, "_", labels[2])]] <- med(b[[m]][k])
    }
    r[[paste0("n_deep_", labels[1])]] <- sum(a$n_deep[k])
    r[[paste0("n_deep_", labels[2])]] <- sum(b$n_deep[k])
    r[[paste0("deep_share_missing_", labels[1])]] <- sum(is.na(a$deep_share_median[k]))
    r[[paste0("deep_share_missing_", labels[2])]] <- sum(is.na(b$deep_share_median[k]))
    for (s in c("closed", "spaced", "gated")) {
      r[[paste0(s, "_", labels[1])]] <- sum(sa[[s]][k])
      r[[paste0(s, "_", labels[2])]] <- sum(sb[[s]][k])
      r[[paste0(s, "_changed")]] <- sum(sa[[s]][k] != sb[[s]][k])
    }
    r
  })
  do.call(rbind, out)
}

# C4: the 3DEP clips (confirm_gated_3dep.R's clips.csv, scored rows) beside
# the 2021 values it records for the same plots: at the clouds' own density
# against the 2021 native clip (neon_native_*), thinned against the 2021 clip
# thinned to the same all-return target (neon_rung2_*). One block of
# mcgc_stand_transfer rows per variant.
MCGC_C4_VARIANTS <- c(`3dep_native` = "neon_native_", `3dep_dec2` = "neon_rung2_")
mcgc_c4_transfer <- function(clips, scopes, variants = MCGC_C4_VARIANTS) {
  x <- clips[clips$scored %in% TRUE, , drop = FALSE]
  out <- lapply(names(variants), function(v) {
    y <- x[x$rung == v, , drop = FALSE]
    if (!nrow(y)) return(NULL)
    p <- variants[[v]]
    a <- data.frame(site = y$site, plot = y$plot, cover = y$cover,
                    crown_spacing = y$crown_spacing, n_deep = y$n_deep,
                    deep_share_median = y$deep_share_median, stringsAsFactors = FALSE)
    b <- data.frame(site = y$site, plot = y$plot, cover = y[[paste0(p, "cover")]],
                    crown_spacing = y[[paste0(p, "crown_spacing")]],
                    n_deep = y[[paste0(p, "n_deep")]],
                    deep_share_median = y[[paste0(p, "deep_share_median")]],
                    stringsAsFactors = FALSE)
    cbind(data.frame(variant = v, stringsAsFactors = FALSE),
          mcgc_stand_transfer(a, b, scopes, labels = c("3dep", "2021")))
  })
  do.call(rbind, out)
}

## ---- the bootstrap's own variation -----------------------------------------------------------
# The same contrasts redrawn with other seeds of the bootstrap: for each seed
# and each pair (a list of c(a, b) configuration labels, named by contrast),
# mcgc_contrast_row on the one-level rows L (ids Lid) and plots `plots`, and
# the reading of `measure`. Returns one row per seed and contrast.
mcgc_seed_bounds <- function(L, Lid, plots, pairs, seeds, n_boot = MT_N_BOOT,
                             measure = "cF1") {
  rows <- list()
  for (s in seeds) for (k in names(pairs)) {
    r <- mcgc_contrast_row(L, Lid, plots, pairs[[k]][1], pairs[[k]][2], n_boot, s,
                           metrics = unique(c(measure, "F1")))
    if (is.null(r)) stop("no plot to contrast for ", k, call. = FALSE)
    lo <- r[[paste0("lo_", measure)]]; hi <- r[[paste0("hi_", measure)]]
    rows[[length(rows) + 1L]] <- cbind(
      data.frame(seed = as.integer(s), contrast = k, config_a = r$config_a, config_b = r$config_b,
                 n_plots = r$n_plots, n_boot = as.integer(n_boot), measure = measure,
                 d_measure = r[[paste0("d_", measure)]], lo_measure = lo, hi_measure = hi,
                 stringsAsFactors = FALSE),
      mcgc_reading(lo, hi, r$n_plots))
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
