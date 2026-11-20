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

# Two checks of a NEWFOR run that its protocol did not declare
# (docs/newfor-validation-protocol.md). Both were written after the run's
# results had been seen, to test how far two of its readings can be trusted.
# They decide nothing and change no output of the run.
#
# 1. The registration estimates against the detections. The protocol's
#    detector-free registration check estimates an offset per area and excludes
#    an area whose estimate exceeds the matching radius. Here the stock and the
#    declared detections of every area of the run (features.csv, admitted or
#    not) are scored at a 2 m radius twice: as released, and with stems and
#    polygon moved by the area's estimate (dx, dy of features.csv; computed by
#    moving the detections the opposite way, as the run's "registered" scenario
#    does; an area without an estimate is not moved). If an estimate were a real
#    misregistration the move would raise the matched stems. The matched stems
#    are also set against the run's own chance null: its K shifted copies of the
#    released detections in the 2 m window (newfor_null_offsets, newfor_shift;
#    the offsets of the run's tol2 scenario).
# 2. Intervals with forests as the resampling unit. The run's intervals
#    resample plots as independent units in one stratum. The plots sit in a few
#    forests whose plots share a flight, a sensor and a survey, so each
#    declared contrast is recomputed on the admitted areas' primary cells with
#    the forests resampled instead: every plot of a drawn forest enters as
#    often as the forest was drawn. With one forest every draw would repeat
#    the estimate, so no interval is given.
#
# The run must hold run.json (its configurations, K and the id of the freeze
# root it ran on, which must be FROZEN's), features.csv, cells.csv and the
# detection files of the two configurations; features.csv and the primary
# cells must agree on the admitted areas and their forests. Unknown arguments
# are refused.
#
# Usage:
#   Rscript scripts/check_newfor_run.R [FROZEN=<root>] [RUN=<run root>]
#       [N_BOOT=1000] [SEED=20261002]
# Defaults: FROZEN=$CLAUDE_JOB_DIR/newfor/frozen_v1,
# RUN=$CLAUDE_JOB_DIR/newfor/multichm_runs. Output under RUN/after_run/ (never
# under RUN/analysis/, which holds the declared analysis only):
#   registration_moves.csv  one row per area x configuration (stock, declared):
#                           area, forest, admitted, config_name, tol, dx, dy
#                           (the estimate, NA without one), n_ref (primary
#                           stems), TP (as released), TP_moved, null_mean and
#                           null_max (mean and maximum TP of the K shifted
#                           copies) and how many copies reach TP and TP_moved
#                           (shifts_reaching_released, shifts_reaching_moved);
#                           the four null columns are NA when K is 0
#   forest_resampled.csv    one row per pair x metric: pair, metric, n_forests,
#                           n_plots, difference (a - b, from the summed counts),
#                           lower, upper and defined_draws (mt_interval over
#                           the forest resamples; NA, NA and 0 with one forest)
#   after_run.json          run_json_sha256, root_id, code_sha256 (the SHA-256
#                           of every R file the check sources, directly or
#                           through another file, by base name: NFC_CODE; one
#                           that cannot be found stops the check before
#                           anything is written), tol, K, n_boot and seed; no
#                           time and no path
suppressMessages({ library(lidR); library(sf); library(terra); library(data.table)
                   library(jsonlite) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))           # score_plot
source(.find("model_bench_lib.R"))     # seed_for, frozen_sha256
source(.find("master_tables_lib.R"))   # mt_interval, MT_N_BOOT, MT_SEED
source(.find("multichm_gated_lib.R"))  # .mcg_rate_list, MCG_COUNT_COLS, MCG_RATE_COLS
source(.find("newfor_lib.R"))          # frozen areas, scoring, the null, newfor_code_sha256

NFC_KEYS <- c("FROZEN", "RUN", "N_BOOT", "SEED")
NFC_TOL <- 2                                        # radius of the registration check (m)
NFC_CONFIGS <- c("stock", "declared")               # configurations of the registration check
# The contrasts a minus b of the forest-resampled intervals, by name.
NFC_PAIRS <- data.frame(a = c("declared", "floor", "floor_exempt", "gate_all", "declared"),
                        b = c("stock", "stock", "stock", "stock", "floor_exempt"),
                        stringsAsFactors = FALSE)
NFC_METRICS <- c("F1", "cF1", "precision", "recall")
# Columns the checks read from features.csv and cells.csv.
NFC_FEATURE_COLS <- c("area", "forest", "admitted", "dx", "dy")
NFC_CELL_COLS <- c("plot", "forest", "admitted", "config_name", "scenario", MCG_COUNT_COLS)
# The R files the check runs, by base name, in the order it first sources them
# (depth first): this script; bootstrap.R and the repo_paths.R it sources;
# sweep_lib.R and the neon_spatial_lib.R and neon_reference_support_lib.R it
# sources; model_bench_lib.R and the site_extension_lib.R it adds;
# master_tables_lib.R; multichm_gated_lib.R; newfor_lib.R. after_run.json's
# code_sha256 holds the SHA-256 of each.
# tests/testthat/test-newfor-detect.R checks the list against the source() calls.
NFC_CODE <- c("check_newfor_run.R", "bootstrap.R", "repo_paths.R", "sweep_lib.R",
              "neon_spatial_lib.R", "neon_reference_support_lib.R", "model_bench_lib.R",
              "site_extension_lib.R", "master_tables_lib.R", "multichm_gated_lib.R",
              "newfor_lib.R")

# KEY=VALUE arguments split at the first "="; unknown, repeated or empty ones stop.
nfc_args <- function(x = commandArgs(TRUE)) {
  if (!length(x)) return(list())
  if (any(!grepl("=", x, fixed = TRUE)))
    stop("newfor: arguments are KEY=VALUE, not ", paste(x[!grepl("=", x, fixed = TRUE)],
                                                          collapse = " "), call. = FALSE)
  key <- sub("=.*$", "", x); val <- sub("^[^=]*=", "", x)
  bad <- setdiff(key, NFC_KEYS)
  if (length(bad))
    stop("newfor: unknown argument ", paste0(bad, "=", collapse = " "), " (known: ",
         paste0(NFC_KEYS, "=", collapse = " "), ")", call. = FALSE)
  if (anyDuplicated(key)) stop("newfor: ", key[duplicated(key)][1], "= is given twice",
                               call. = FALSE)
  if (any(!nzchar(val))) stop("newfor: ", key[!nzchar(val)][1], "= needs a value", call. = FALSE)
  stats::setNames(as.list(val), key)
}

.nfc_int <- function(A, key, default, lo) {
  v <- A[[key]]
  if (is.null(v)) return(as.integer(default))
  n <- suppressWarnings(as.numeric(v))
  if (is.na(n) || !is.finite(n) || n != round(n) || n < lo || n > .Machine$integer.max)
    stop(sprintf("newfor: %s= must be a whole number of at least %d, not '%s'", key, lo, v),
         call. = FALSE)
  as.integer(n)
}

# A column of TRUE/FALSE flags as logical, whether it was read as logical or as
# the strings "TRUE"/"FALSE"; any other value (NA included) stops, so an area
# is never silently left out of, or counted in, the admitted areas.
.nfc_flag <- function(v, what) {
  out <- unname(c("TRUE" = TRUE, "FALSE" = FALSE)[as.character(v)])
  if (anyNA(out)) stop("newfor: ", what, " must be TRUE or FALSE in every row", call. = FALSE)
  out
}

# The run's K (null shifts per area) from run.json: a whole number, 0 or more.
.nfc_k <- function(record) {
  k <- record$K
  if (!is.numeric(k) || length(k) != 1L || !is.finite(k) || k < 0 || k != round(k))
    stop("newfor: run.json records no K (a whole number of null shifts, 0 or more)",
         call. = FALSE)
  as.integer(k)
}

# The run's files: list(record (run.json), labels (configuration name -> label),
# features, cells), admitted read as logical in both tables. Stops when a file,
# the configuration table or a column the checks read is missing, or when a
# configuration name or label repeats.
nfc_read_run <- function(run) {
  for (k in c("run.json", "features.csv", "cells.csv"))
    if (!file.exists(file.path(run, k))) stop("newfor: ", run, " holds no ", k, call. = FALSE)
  rec <- jsonlite::read_json(file.path(run, "run.json"), simplifyVector = TRUE)
  cfg <- rec$configurations
  if (!is.data.frame(cfg) || !all(c("name", "label") %in% names(cfg)))
    stop("newfor: run.json records no configuration table", call. = FALSE)
  if (anyDuplicated(cfg$name) || anyDuplicated(cfg$label))
    stop("newfor: run.json repeats a configuration name or label", call. = FALSE)
  features <- utils::read.csv(file.path(run, "features.csv"), stringsAsFactors = FALSE,
                              colClasses = c(area = "character", forest = "character"))
  cells <- utils::read.csv(file.path(run, "cells.csv"), stringsAsFactors = FALSE,
                           colClasses = c(plot = "character", forest = "character",
                                          config = "character", config_name = "character",
                                          scenario = "character"))
  for (t in list(list("features.csv", features, NFC_FEATURE_COLS),
                 list("cells.csv", cells, NFC_CELL_COLS))) {
    miss <- setdiff(t[[3]], names(t[[2]]))
    if (length(miss)) stop("newfor: ", t[[1]], " lacks ", paste(miss, collapse = ", "),
                           call. = FALSE)
  }
  features$admitted <- .nfc_flag(features$admitted, "features.csv: admitted")
  cells$admitted <- .nfc_flag(cells$admitted, "cells.csv: admitted")
  list(record = rec, labels = stats::setNames(cfg$label, cfg$name), features = features,
       cells = cells)
}

## ---- 1. the registration estimates against the detections --------------------------------------
# The detections of one configuration (by label) of one area, as written by the
# run: x, y, z. Stops when the file is missing or has other columns.
.nfc_detections <- function(run, id, label) {
  f <- file.path(run, "detections", id, paste0(label, ".csv"))
  if (!file.exists(f)) stop("newfor: the run holds no detections ", label, " of area ", id,
                            call. = FALSE)
  det <- utils::read.csv(f, colClasses = "numeric")
  if (!identical(names(det), c("x", "y", "z"))) stop("newfor: ", f, " is not x, y, z",
                                                     call. = FALSE)
  det
}

# One row per area of r$features (in id order) x configuration of `configs`
# (names of the run's configurations): the primary stems matched within tol as
# released (TP) and with the detections moved by minus the area's estimate
# (TP_moved; the estimate is dx, dy of features.csv, and an area with either
# one NA is not moved, so TP_moved equals TP), the mean and maximum TP of the k
# shifted copies of the released detections (newfor_null_offsets of the area's
# window at tol; null_mean is newfor_score_cell's TP0 for the same offsets),
# and how many copies reach TP and TP_moved. With k = 0 the four null columns
# are NA. run_main passes the run's K as k.
nfc_registration_moves <- function(frozen, run, r = nfc_read_run(run), tol = NFC_TOL,
                                   configs = NFC_CONFIGS, k = NEWFOR_NULL_K) {
  if (!is.numeric(k) || length(k) != 1L || !is.finite(k) || k < 0 || k != round(k))
    stop("newfor: k must be a whole number of shifted copies, 0 or more", call. = FALSE)
  miss <- setdiff(configs, names(r$labels))
  if (length(miss)) stop("newfor: the run has no configuration ", paste(miss, collapse = ", "),
                         call. = FALSE)
  feats <- r$features
  miss <- setdiff(NFC_FEATURE_COLS, names(feats))
  if (length(miss)) stop("newfor: features.csv lacks ", paste(miss, collapse = ", "),
                         call. = FALSE)
  if (!nrow(feats) || anyDuplicated(feats$area))
    stop("newfor: features.csv must list every area of the run once", call. = FALSE)
  admitted <- .nfc_flag(feats$admitted, "features.csv: admitted")
  out <- list()
  for (id in sort(feats$area, method = "radix")) {
    i <- match(id, feats$area)
    fa <- newfor_frozen_area(frozen, id, verify = TRUE)
    stems <- newfor_stems(fa$stems, "primary")
    win <- newfor_window(fa$aoi, tol)
    offsets <- newfor_null_offsets(id, win$w, win$h, k = k)
    dx <- as.numeric(feats$dx[i]); dy <- as.numeric(feats$dy[i])
    shift <- if (is.finite(dx) && is.finite(dy)) c(dx, dy) else c(0, 0)
    for (nm in configs) {
      det <- .nfc_detections(run, id, r$labels[[nm]])
      moved <- det
      moved$x <- det$x - shift[1]; moved$y <- det$y - shift[2]
      tp <- newfor_score(stems, det, fa$aoi, tol)[["TP"]]
      tp_moved <- newfor_score(stems, moved, fa$aoi, tol)[["TP"]]
      nul <- vapply(offsets, function(of)
        newfor_score(stems, newfor_shift(det, win, of), fa$aoi, tol)[["TP"]], numeric(1))
      none <- !length(nul)
      out[[length(out) + 1L]] <- data.frame(
        area = id, forest = feats$forest[i], admitted = admitted[i], config_name = nm,
        tol = tol, dx = dx, dy = dy, n_ref = nrow(stems), TP = tp, TP_moved = tp_moved,
        null_mean = if (none) NA_real_ else mean(nul),
        null_max = if (none) NA_real_ else max(nul),
        shifts_reaching_released = if (none) NA_integer_ else sum(nul >= tp),
        shifts_reaching_moved = if (none) NA_integer_ else sum(nul >= tp_moved),
        stringsAsFactors = FALSE)
    }
  }
  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

## ---- 2. intervals with forests as the resampling unit ------------------------------------------
# Weights of n_boot resamples of the forests of `forest` (one entry per plot):
# a plots x n_boot matrix whose entry is how often the plot's forest was drawn,
# the forests (sorted in C-locale order) drawn with replacement, as many as
# there are, with one sample.int() call per draw. Draws use R's default
# generators; the caller's RNG kind and state are restored. A missing or empty
# forest stops.
nfc_forest_weights <- function(forest, n_boot = MT_N_BOOT, seed = MT_SEED) {
  if (anyNA(forest) || any(!nzchar(forest)))
    stop("newfor: every plot needs a forest to resample", call. = FALSE)
  fs <- sort(unique(forest), method = "radix")
  if (!length(fs)) stop("newfor: no forest to resample", call. = FALSE)
  old_kind <- RNGkind()
  old_seed <- get0(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
        rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", old_seed, envir = .GlobalEnv)
  }, add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
  k <- match(forest, fs)
  W <- matrix(0, length(forest), n_boot)
  for (b in seq_len(n_boot))
    W[, b] <- tabulate(sample.int(length(fs), length(fs), replace = TRUE), length(fs))[k]
  W
}

# Every pair of `pairs` x metric (rate names of MCG_RATE_COLS) on the admitted
# areas' primary cells: difference (a - b, from the summed counts) and its
# percentile interval over the forest resamples (mt_interval), with n_forests
# and n_plots. Each configuration of `pairs` must cover every admitted area
# once, and every admitted area needs one forest. With one forest the interval
# is not drawn: lower and upper are NA and defined_draws is 0.
nfc_forest_contrasts <- function(cells, n_boot = MT_N_BOOT, seed = MT_SEED, pairs = NFC_PAIRS,
                                 metrics = NFC_METRICS) {
  miss <- setdiff(NFC_CELL_COLS, names(cells))
  if (length(miss)) stop("newfor: the cells lack ", paste(miss, collapse = ", "), call. = FALSE)
  bad <- setdiff(metrics, MCG_RATE_COLS)
  if (length(bad)) stop("newfor: unknown metrics: ", paste(bad, collapse = ", "), call. = FALSE)
  adm <- .nfc_flag(cells$admitted, "cells: admitted")
  x <- cells[cells$scenario %in% "primary" & adm, , drop = FALSE]
  plots <- sort(unique(x$plot), method = "radix")
  if (!length(plots)) stop("newfor: no admitted area in the cells", call. = FALSE)
  pf <- unique(x[c("plot", "forest")])
  if (anyDuplicated(pf$plot) || anyNA(pf$forest) || any(!nzchar(pf$forest)))
    stop("newfor: every admitted area needs one forest in its primary cells", call. = FALSE)
  forest <- pf$forest[match(plots, pf$plot)]
  n_forests <- length(unique(forest))
  W <- if (n_forests > 1L) nfc_forest_weights(forest, n_boot, seed) else NULL
  counts <- function(nm) {
    r <- x[x$config_name == nm, , drop = FALSE]
    if (anyDuplicated(r$plot) || !setequal(r$plot, plots))
      stop(sprintf("newfor: configuration %s must cover each of the %d admitted areas once",
                   nm, length(plots)), call. = FALSE)
    r <- r[match(plots, r$plot), , drop = FALSE]
    lapply(stats::setNames(MCG_COUNT_COLS, MCG_COUNT_COLS), function(k) as.numeric(r[[k]]))
  }
  rates <- function(cn, w) .mcg_rate_list(lapply(cn, function(v) drop(crossprod(w, v))))
  one <- matrix(1, length(plots), 1)
  no_interval <- data.frame(lower = NA_real_, upper = NA_real_, defined_draws = 0L)
  out <- list()
  for (i in seq_len(nrow(pairs))) {
    ca <- counts(pairs$a[i]); cb <- counts(pairs$b[i])
    ea <- rates(ca, one); eb <- rates(cb, one)
    if (!is.null(W)) { da <- rates(ca, W); db <- rates(cb, W) }
    for (m in metrics)
      out[[length(out) + 1L]] <- cbind(
        data.frame(pair = paste(pairs$a[i], "-", pairs$b[i]), metric = m,
                   n_forests = n_forests, n_plots = length(plots),
                   difference = ea[[m]] - eb[[m]], stringsAsFactors = FALSE),
        if (is.null(W)) no_interval else mt_interval(da[[m]] - db[[m]]))
  }
  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

## ---- main --------------------------------------------------------------------------------------
.nfc_write_csv <- function(x, path) {
  tmp <- paste0(path, ".part")
  utils::write.csv(x, tmp, row.names = FALSE)
  if (!file.rename(tmp, path)) stop("newfor: could not write ", path, call. = FALSE)
  invisible(path)
}

.nfc_write_json <- function(x, path) {
  tmp <- paste0(path, ".part")
  jsonlite::write_json(x, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
  if (!file.rename(tmp, path)) stop("newfor: could not write ", path, call. = FALSE)
  invisible(path)
}

# Stops unless `frozen` is a sealed root and run.json records its id.
.nfc_check_root <- function(record, frozen, run) {
  if (!newfor_sealed(frozen)) stop("newfor: no sealed freeze root at ", frozen, call. = FALSE)
  rid <- record$frozen$root_id
  if (!is.character(rid) || length(rid) != 1L || is.na(rid))
    stop("newfor: ", run, "/run.json records no freeze root id", call. = FALSE)
  here <- newfor_root_id(frozen)
  if (!identical(rid, here))
    stop(sprintf("newfor: %s was run on the freeze root %s, not on %s (%s)", run,
                 substr(rid, 1, 12), frozen, substr(here, 1, 12)), call. = FALSE)
  invisible(TRUE)
}

# Stops unless features.csv and the primary cells name the same admitted areas
# with the same forests (the two checks read one table each).
.nfc_check_agree <- function(cells, features) {
  key <- function(a, f) sort(unique(paste(a, f, sep = "\t")), method = "radix")
  ce <- cells[cells$scenario %in% "primary" & cells$admitted, , drop = FALSE]
  if (!identical(key(features$area[features$admitted], features$forest[features$admitted]),
                 key(ce$plot, ce$forest)))
    stop("newfor: features.csv and cells.csv disagree on the admitted areas or their forests",
         call. = FALSE)
  invisible(TRUE)
}

run_main <- function(A = nfc_args()) {
  d <- .job_dir()
  frozen <- if (is.null(A[["FROZEN"]])) file.path(d, "newfor", "frozen_v1") else A[["FROZEN"]]
  run <- if (is.null(A[["RUN"]])) file.path(d, "newfor", "multichm_runs") else A[["RUN"]]
  n_boot <- .nfc_int(A, "N_BOOT", MT_N_BOOT, 1L); seed <- .nfc_int(A, "SEED", MT_SEED, 0L)
  code <- newfor_code_sha256(NFC_CODE, .find)        # a missing file stops before any write
  r <- nfc_read_run(run)
  k <- .nfc_k(r$record)
  .nfc_check_root(r$record, frozen, run)
  .nfc_check_agree(r$cells, r$features)
  moves <- nfc_registration_moves(frozen, run, r, k = k)
  forests <- nfc_forest_contrasts(r$cells, n_boot, seed)
  out <- file.path(run, "after_run")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  .nfc_write_csv(moves, file.path(out, "registration_moves.csv"))
  .nfc_write_csv(forests, file.path(out, "forest_resampled.csv"))
  .nfc_write_json(list(run_json_sha256 = frozen_sha256(file.path(run, "run.json")),
                       root_id = r$record$frozen$root_id, code_sha256 = as.list(code),
                       tol = NFC_TOL, K = k, n_boot = n_boot, seed = seed),
                  file.path(out, "after_run.json"))
  cat(sprintf(paste0("NEWFOR after-run checks -> %s\n\nmatched stems at %g m, as released and ",
                     "moved by the registration estimate\n"), out, NFC_TOL))
  print(moves[c("area", "admitted", "config_name", "n_ref", "TP", "TP_moved", "null_mean",
                "null_max", "shifts_reaching_released", "shifts_reaching_moved")],
        row.names = FALSE, digits = 4)
  for (nm in NFC_CONFIGS) {
    m <- moves[moves$config_name == nm & moves$admitted, , drop = FALSE]
    cat(sprintf(paste("%s, admitted areas: %d matched as released, %d moved; the move lowers",
                      "%d areas and raises %d\n"),
                nm, sum(m$TP), sum(m$TP_moved), sum(m$TP_moved < m$TP), sum(m$TP_moved > m$TP)))
  }
  cat(sprintf("\nintervals with the %d forests resampled (%d draws, seed %d)\n",
              forests$n_forests[1], n_boot, seed))
  print(forests[c("pair", "metric", "difference", "lower", "upper", "defined_draws")],
        row.names = FALSE, digits = 3)
  invisible(list(moves = moves, forests = forests))
}

if (sys.nframe() == 0L) run_main()
