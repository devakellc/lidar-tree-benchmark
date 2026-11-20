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

# Analysis of the NEWFOR Alpine validation of the gated multichm arm
# (docs/newfor-validation-protocol.md, section Analysis) from the run root of
# detect_newfor_multichm.R. Nothing is detected or scored here: the cells are
# pooled by summing counts, never by averaging rates (mcg_pool, mcg_rates), and
# every contrast is paired over the same plots with one set of plot resamples
# per pool (mcg_contrast, mt_plot_weights; NEWFOR is one stratum). Intervals are
# 95% percentile intervals, given for pools of five plots or more; smaller pools
# get estimates only.
#
# Pools (sets of areas): admitted; all (every area run, plot 02 included);
# density_inside and density_outside (admitted areas whose clip-wide
# first-return density lies inside, bounds included, or outside
# NEWFOR_DEV_FRDENS); gate_gated, gate_closed and gate_open (admitted areas by
# gate state under the declared configuration); without_<forest> per forest of
# the admitted areas (forest lower-cased, non-alphanumerics as "_").
# Contrasts (a minus b): declared - stock (the primary contrast),
# floor - stock, floor_exempt - stock, gate_all - stock and
# declared - floor_exempt (the share gate's own change), for scenario primary
# on every pool, inventoried and tol2 on the admitted pool, and registered on
# the admitted pool and on all areas.
# The reading of the primary contrast (pooled F1 of declared minus stock,
# primary population, admitted areas) is fixed by the protocol: better when the
# interval's lower bound is above 0, worse when its upper bound is below 0,
# not worse when neither and the lower bound is above -0.02, inconclusive
# otherwise.
#
# The run must hold run.json, features.csv and cells.csv. Cells whose
# configurations, or whose scenarios, do not cover the same areas exactly once
# (equal support) are refused, as are cells and features that disagree on an
# area's admission or forest.
#
# A run outside the protocol's fixed settings is analysed, not refused, and
# says so: protocol_settings is TRUE only when run.json records K =
# NEWFOR_NULL_K null shifts, the pinned detector library without
# ALLOW_UNPINNED=1, the pinned lidR and lidRplugins versions and every frozen
# area run (areas equal to root_areas), and the analysis uses N_BOOT = MT_N_BOOT
# and SEED = MT_SEED. A setting that run.json does not record counts as not
# met. reading.csv carries the flag, analysis.json the flag and its reasons,
# and the header of tables.md states the settings and, when they are not met,
# why.
#
# Usage:
#   Rscript scripts/analyze_newfor_multichm.R [RUN=<run root>] [N_BOOT=1000]
#       [SEED=20261002]
# Default RUN=$CLAUDE_JOB_DIR/newfor/multichm_runs. Output under RUN/analysis/:
#   pools.csv                 pool, n_plots, areas
#   pooled.csv                scenario x pool x configuration: summed counts,
#                             rates and height-band recall with its null and
#                             chance-corrected values
#   contrasts.csv             scenario x pool x pair x metric
#   reading.csv               the primary contrast and its reading (F1, cF1),
#                             with protocol_settings
#   per_plot.csv              one row per area (rates for reading the table only)
#                             with in_dev_range (clip-wide first-return density
#                             inside NEWFOR_DEV_FRDENS, bounds included)
#   leave_one_forest_out.csv  declared - stock without each forest, and the range
#   tables.md                 the tables the report quotes
#   analysis.json             the run's identity (run.json's SHA-256, the root
#                             id, the protocol's SHA-256); code_sha256, the
#                             SHA-256 of every R file the analysis sources,
#                             directly or through another file, by base name
#                             (NFA_CODE; one that cannot be found stops the
#                             analysis before anything is written); the
#                             bootstrap settings and protocol_settings with its
#                             reasons
suppressMessages({ library(data.table); library(jsonlite) })
d <- .job_dir()
source(.find("sweep_lib.R"))           # neon_* helpers that newfor_lib.R uses
source(.find("model_bench_lib.R"))     # seed_for, frozen_sha256
source(.find("master_tables_lib.R"))   # mt_plot_weights, mt_interval, MT_N_BOOT, MT_SEED
source(.find("multichm_gated_lib.R"))  # mcg_pool, mcg_rates, mcg_contrast, MCG_*_COLS
source(.find("newfor_lib.R"))          # NEWFOR_* constants

## ---- constants ---------------------------------------------------------------------------------
NFA_KEYS <- c("RUN", "N_BOOT", "SEED")
# The R files the analysis runs, by base name, in the order it first sources
# them (depth first): this script; bootstrap.R and the repo_paths.R it
# sources; sweep_lib.R and the neon_spatial_lib.R and
# neon_reference_support_lib.R it sources; model_bench_lib.R and the
# site_extension_lib.R it adds; master_tables_lib.R; multichm_gated_lib.R;
# newfor_lib.R. analysis.json's code_sha256 holds the SHA-256 of each.
# tests/testthat/test-newfor-detect.R checks the list against the source() calls.
NFA_CODE <- c("analyze_newfor_multichm.R", "bootstrap.R", "repo_paths.R", "sweep_lib.R",
              "neon_spatial_lib.R", "neon_reference_support_lib.R", "model_bench_lib.R",
              "site_extension_lib.R", "master_tables_lib.R", "multichm_gated_lib.R",
              "newfor_lib.R")
NFA_SCENARIOS <- c("primary", "inventoried", "registered", "tol2")
NFA_CONFIG_NAMES <- c("stock", "declared", "floor", "floor_exempt", "gate_all")
# The contrasts a minus b, by configuration name; the first is the primary one.
NFA_PAIRS <- data.frame(a = c("declared", "floor", "floor_exempt", "gate_all", "declared"),
                        b = c("stock", "stock", "stock", "stock", "floor_exempt"),
                        stringsAsFactors = FALSE)
NFA_METRICS <- c("F1", "cF1", "precision", "recall", "cPrecision", "cRecall", "det_per_ref")
NFA_MIN_INTERVAL <- 5L      # plots a pool needs for an interval
NFA_NOT_WORSE <- -0.02      # the lower bound "not worse" must exceed
# Columns of features.csv the analysis reads.
NFA_FEATURE_COLS <- c("area", "forest", "admitted", "failed", "n_rows", "n_inside", "n_outside",
                      "n_primary", "n_inventoried", "n_missing_dbh", "n_below_caliper",
                      "gap_months", "reach_min", "terrain_na_share", "aoi_area", "pdens_aoi",
                      "frdens_aoi", "covered_area", "pdens_clip", "frdens_clip", "res", "cover",
                      "crown_spacing", "gate_state", "parity_ok", "parity_n_package",
                      "parity_n_stock", "parity_max_abs_diff", "dx", "dy", "offset")
.nfa_band_cols <- function(b = NEWFOR_HEIGHT_BANDS)
  c(paste0("n_h_", b), paste0("tp_h_", b), paste0("tp_h_", b, "0"))

## ---- arguments ---------------------------------------------------------------------------------
# KEY=VALUE arguments split at the first "="; unknown, repeated or empty ones stop.
nfa_args <- function(x = commandArgs(TRUE)) {
  if (!length(x)) return(list())
  if (any(!grepl("=", x, fixed = TRUE)))
    stop("newfor: arguments are KEY=VALUE, not ", paste(x[!grepl("=", x, fixed = TRUE)],
                                                          collapse = " "), call. = FALSE)
  key <- sub("=.*$", "", x); val <- sub("^[^=]*=", "", x)
  bad <- setdiff(key, NFA_KEYS)
  if (length(bad))
    stop("newfor: unknown argument ", paste0(bad, "=", collapse = " "), " (known: ",
         paste0(NFA_KEYS, "=", collapse = " "), ")", call. = FALSE)
  if (anyDuplicated(key)) stop("newfor: ", key[duplicated(key)][1], "= is given twice",
                               call. = FALSE)
  if (any(!nzchar(val))) stop("newfor: ", key[!nzchar(val)][1], "= needs a value", call. = FALSE)
  stats::setNames(as.list(val), key)
}

nfa_options <- function(A) {
  int <- function(key, default, lo) {
    v <- A[[key]]
    if (is.null(v)) return(as.integer(default))
    n <- suppressWarnings(as.numeric(v))
    if (is.na(n) || n != round(n) || n < lo || n > .Machine$integer.max)
      stop(sprintf("newfor: %s= must be a whole number of at least %d, not '%s'", key, lo, v),
           call. = FALSE)
    as.integer(n)
  }
  list(run = if (is.null(A[["RUN"]])) file.path(d, "newfor", "multichm_runs") else A[["RUN"]],
       n_boot = int("N_BOOT", MT_N_BOOT, 1L), seed = int("SEED", MT_SEED, 0L))
}

## ---- reading the run ---------------------------------------------------------------------------
# list(record (run.json), configs (name, label in run order), cells, features).
nfa_read_run <- function(run) {
  f <- file.path(run, "run.json")
  if (!file.exists(f))
    stop("newfor: ", run, " holds no run.json, so it is not a run of detect_newfor_multichm.R",
         call. = FALSE)
  rec <- jsonlite::read_json(f, simplifyVector = TRUE)
  cfg <- rec$configurations
  if (!is.data.frame(cfg) || !all(c("name", "label") %in% names(cfg)))
    stop("newfor: ", f, " records no configuration table", call. = FALSE)
  miss <- setdiff(NFA_CONFIG_NAMES, cfg$name)
  if (length(miss)) stop("newfor: ", f, " lacks the configurations ",
                         paste(miss, collapse = ", "), call. = FALSE)
  if (anyDuplicated(cfg$name) || anyDuplicated(cfg$label))
    stop("newfor: ", f, " repeats a configuration name or label", call. = FALSE)
  for (k in c("cells.csv", "features.csv"))
    if (!file.exists(file.path(run, k))) stop("newfor: ", run, " holds no ", k, call. = FALSE)
  cells <- utils::read.csv(file.path(run, "cells.csv"), stringsAsFactors = FALSE,
                           colClasses = c(site = "character", plot = "character",
                                          forest = "character", config = "character",
                                          config_name = "character", scenario = "character"))
  features <- utils::read.csv(file.path(run, "features.csv"), stringsAsFactors = FALSE,
                              colClasses = c(area = "character", forest = "character",
                                             failed = "character", gate_state = "character"))
  miss <- setdiff(NFA_FEATURE_COLS, names(features))
  if (length(miss)) stop("newfor: features.csv lacks ", paste(miss, collapse = ", "),
                         call. = FALSE)
  need <- c("site", "plot", "forest", "admitted", "config", "config_name", "scenario",
            MCG_COUNT_COLS, .nfa_band_cols())
  miss <- setdiff(need, names(cells))
  if (length(miss)) stop("newfor: cells.csv lacks ", paste(miss, collapse = ", "), call. = FALSE)
  features$admitted <- as.logical(features$admitted)
  cells$admitted <- as.logical(cells$admitted)
  list(record = rec, configs = data.frame(name = cfg$name, label = cfg$label,
                                          stringsAsFactors = FALSE),
       cells = cells, features = features)
}

# Equal support: in every scenario every configuration of the run covers the
# same areas exactly once, every scenario covers the same areas, and these are
# the areas of features.csv, one row each; the cells agree with features.csv on
# each area's admission and forest. Stops otherwise.
nfa_check_support <- function(cells, features, configs) {
  if (anyDuplicated(features$area)) stop("newfor: features.csv lists an area twice", call. = FALSE)
  if (any(cells$site != NEWFOR_SITE)) stop("newfor: cells of another site than ", NEWFOR_SITE,
                                           call. = FALSE)
  bad <- setdiff(unique(cells$scenario), NFA_SCENARIOS)
  if (length(bad)) stop("newfor: unknown scenarios in cells.csv: ", paste(bad, collapse = ", "),
                        call. = FALSE)
  pair <- unique(cells[c("config", "config_name")])
  if (!setequal(pair$config, configs$label) || nrow(pair) != nrow(configs) ||
      !identical(configs$name[match(pair$config, configs$label)], pair$config_name))
    stop("newfor: the configurations of cells.csv are not those of run.json", call. = FALSE)
  areas <- sort(features$area, method = "radix")
  for (s in NFA_SCENARIOS) {
    x <- cells[cells$scenario == s, , drop = FALSE]
    if (!nrow(x)) stop("newfor: cells.csv has no cell of scenario ", s, call. = FALSE)
    if (anyDuplicated(paste(x$config, x$plot, sep = "\r")))
      stop("newfor: a configuration covers an area twice in scenario ", s, call. = FALSE)
    for (lab in configs$label) {
      have <- sort(x$plot[x$config == lab], method = "radix")
      if (!identical(have, areas))
        stop(sprintf(paste0("newfor: unequal support: in scenario %s configuration %s covers ",
                            "%d of the %d areas (%s); every configuration must cover the same ",
                            "areas"), s, lab, length(intersect(have, areas)), length(areas),
                     paste(setdiff(union(areas, have), intersect(areas, have)), collapse = ", ")),
             call. = FALSE)
    }
  }
  k <- match(cells$plot, features$area)
  if (!identical(cells$admitted, features$admitted[k]) ||
      !identical(cells$forest, features$forest[k]))
    stop("newfor: cells.csv and features.csv disagree on an area's admission or forest",
         call. = FALSE)
  invisible(TRUE)
}

## ---- the protocol's settings -------------------------------------------------------------------
# Whether the run (record: run.json as read) and the analysis (n_boot, seed)
# meet the protocol's fixed settings: list(met, reasons), reasons naming each
# setting that is not met or that run.json does not record ("not recorded").
nfa_protocol_settings <- function(record, n_boot, seed) {
  has <- function(x) !is.null(x) && length(x) > 0L && !anyNA(x)
  why <- character()
  K <- record$K
  if (!has(K)) why <- c(why, "K: not recorded")
  else if (!identical(as.numeric(K), as.numeric(NEWFOR_NULL_K)))
    why <- c(why, sprintf("K is %s, not %d", paste(K, collapse = ","), NEWFOR_NULL_K))
  lib <- record$detector_library
  if (!is.list(lib) || !has(lib$pin_matches) || !has(lib$allow_unpinned))
    why <- c(why, "detector pin: not recorded")
  else {
    if (!isTRUE(lib$pin_matches)) why <- c(why, "the detector library is not the pinned one")
    if (!isFALSE(lib$allow_unpinned)) why <- c(why, "ALLOW_UNPINNED=1 was given")
  }
  if (!has(record$versions_match)) why <- c(why, "package versions: not recorded")
  else if (!isTRUE(record$versions_match))
    why <- c(why, "lidR or lidRplugins is not the pinned version")
  if (!has(record$areas) || !has(record$root_areas)) why <- c(why, "frozen areas: not recorded")
  else if (!identical(sort(as.character(record$areas), method = "radix"),
                      sort(as.character(record$root_areas), method = "radix")))
    why <- c(why, sprintf("%d of the %d frozen areas were run",
                          length(intersect(record$areas, record$root_areas)),
                          length(record$root_areas)))
  if (!identical(as.integer(n_boot), MT_N_BOOT))
    why <- c(why, sprintf("N_BOOT is %d, not %d", as.integer(n_boot), MT_N_BOOT))
  if (!identical(as.integer(seed), MT_SEED))
    why <- c(why, sprintf("SEED is %d, not %d", as.integer(seed), MT_SEED))
  list(met = !length(why), reasons = why)
}

## ---- pools -------------------------------------------------------------------------------------
nfa_slug <- function(x) gsub("[^a-z0-9]", "_", tolower(x))

# TRUE when a clip-wide first-return density lies inside NEWFOR_DEV_FRDENS
# (bounds included), FALSE outside it, NA when unknown.
nfa_in_dev_range <- function(frdens)
  ifelse(is.finite(frdens), frdens >= NEWFOR_DEV_FRDENS[1] & frdens <= NEWFOR_DEV_FRDENS[2], NA)

# The pools as a named list of area ids (sorted), in their output order; a pool
# may be empty.
nfa_pools <- function(features) {
  f <- features[order(features$area, method = "radix"), , drop = FALSE]
  adm <- f$admitted %in% TRUE
  dev <- nfa_in_dev_range(f$frdens_clip)
  pools <- list(admitted = f$area[adm], all = f$area,
                density_inside = f$area[adm & dev %in% TRUE],
                density_outside = f$area[adm & dev %in% FALSE],
                gate_gated = f$area[adm & f$gate_state %in% "gated"],
                gate_closed = f$area[adm & f$gate_state %in% "closed"],
                gate_open = f$area[adm & f$gate_state %in% "open"])
  forests <- sort(unique(f$forest[adm]), method = "radix")
  slug <- nfa_slug(forests)
  if (anyDuplicated(slug)) stop("newfor: two forests give the pool name without_",
                                slug[duplicated(slug)][1], call. = FALSE)
  for (i in seq_along(forests))
    pools[[paste0("without_", slug[i])]] <- f$area[adm & f$forest != forests[i]]
  pools
}

nfa_pool_table <- function(pools)
  data.frame(pool = names(pools), n_plots = unname(lengths(pools)),
             areas = unname(vapply(pools, paste, "", collapse = ";")), stringsAsFactors = FALSE)

## ---- pooled scores -----------------------------------------------------------------------------
# Height-band recall of summed counts: rec = tp_h / n_h, its null tp_h0 / n_h
# and the chance-corrected (rec - null) / (1 - null); NA for an empty band.
.nfa_band_rates <- function(x) {
  out <- list()
  for (b in NEWFOR_HEIGHT_BANDS) {
    n <- x[[paste0("n_h_", b)]]; tp <- x[[paste0("tp_h_", b)]]; tp0 <- x[[paste0("tp_h_", b, "0")]]
    rec <- ifelse(is.finite(n) & n > 0, tp / n, NA_real_)
    nul <- ifelse(is.finite(n) & n > 0, tp0 / n, NA_real_)
    out[[paste0("rec_h_", b)]] <- rec
    out[[paste0("null_rec_h_", b)]] <- nul
    out[[paste0("cRec_h_", b)]] <- ifelse(is.finite(rec) & is.finite(nul) & nul < 1,
                                          (rec - nul) / (1 - nul), NA_real_)
  }
  as.data.frame(out)
}

# Scenario x pool x configuration: n_plots, the summed MCG_COUNT_COLS and band
# counts, MCG_RATE_COLS and the height-band rates. Empty pools give no row.
nfa_pooled <- function(cells, pools, configs) {
  out <- list()
  for (s in NFA_SCENARIOS) for (p in names(pools)) {
    ids <- pools[[p]]
    if (!length(ids)) next
    x <- cells[cells$scenario == s & cells$plot %in% ids, , drop = FALSE]
    P <- mcg_pool(x, "config")
    B <- data.table::as.data.table(x)[, lapply(.SD, function(v) sum(as.numeric(v))),
                                      by = "config", .SDcols = .nfa_band_cols()]
    B <- as.data.frame(B)[match(P$config, B$config), .nfa_band_cols(), drop = FALSE]
    r <- cbind(data.frame(scenario = s, pool = p,
                          config_name = configs$name[match(P$config, configs$label)],
                          config = P$config, n_plots = P$n_cells, stringsAsFactors = FALSE),
               P[MCG_COUNT_COLS], B, P[MCG_RATE_COLS], .nfa_band_rates(B))
    out[[length(out) + 1L]] <- r[order(match(r$config, configs$label)), , drop = FALSE]
  }
  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

## ---- contrasts ---------------------------------------------------------------------------------
# The scenario x pool combinations that get contrasts.
nfa_plan <- function(pools)
  data.frame(scenario = c(rep("primary", length(pools)), "inventoried", "registered",
                          "registered", "tol2"),
             pool = c(names(pools), "admitted", "admitted", "all", "admitted"),
             stringsAsFactors = FALSE)

# Every pair of NFA_PAIRS on every non-empty combination of nfa_plan(): one row
# per metric with scenario, pool, pair ("a - b" by name), name_a, name_b,
# config_a, config_b (labels), metric, n_plots, estimate_a, estimate_b,
# difference (a - b), lower, upper and defined_draws. Pools of fewer than
# NFA_MIN_INTERVAL plots are not resampled: their bounds are NA and
# defined_draws 0. Every pair of a pool is resampled with the same draws.
nfa_contrasts <- function(cells, pools, configs, n_boot = MT_N_BOOT, seed = MT_SEED) {
  plan <- nfa_plan(pools)
  lab <- function(nm) configs$label[match(nm, configs$name)]
  out <- list()
  for (i in seq_len(nrow(plan))) {
    s <- plan$scenario[i]; p <- plan$pool[i]; ids <- pools[[p]]
    if (!length(ids)) next
    rows <- cells[cells$scenario == s & cells$plot %in% ids, , drop = FALSE]
    nb <- if (length(ids) >= NFA_MIN_INTERVAL) n_boot else 0L
    for (j in seq_len(nrow(NFA_PAIRS))) {
      a <- NFA_PAIRS$a[j]; b <- NFA_PAIRS$b[j]
      ct <- mcg_contrast(rows, paste0(NEWFOR_SITE, "::", ids), lab(a), lab(b), n_boot = nb,
                         seed = seed, metrics = NFA_METRICS)
      attr(ct, "pooled") <- NULL
      out[[length(out) + 1L]] <- cbind(
        data.frame(scenario = s, pool = p, pair = paste(a, "-", b), name_a = a, name_b = b,
                   stringsAsFactors = FALSE),
        ct[c("config_a", "config_b", "metric", "n_plots", "estimate_a", "estimate_b",
             "difference", "lower", "upper", "defined_draws")])
    }
  }
  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

# The protocol's reading of a difference's interval: "better" (lower > 0),
# "worse" (upper < 0), "not worse" (neither, and lower > -0.02),
# "inconclusive" otherwise; NA without an interval.
nfa_reading <- function(lower, upper)
  ifelse(is.na(lower) | is.na(upper), NA_character_,
         ifelse(lower > 0, "better",
                ifelse(upper < 0, "worse",
                       ifelse(lower > NFA_NOT_WORSE, "not worse", "inconclusive"))))

# The primary contrast (scenario primary, pool admitted, declared - stock) for
# F1 and cF1 with its reading; the F1 row is the primary one.
nfa_reading_table <- function(contrasts) {
  x <- contrasts[contrasts$scenario == "primary" & contrasts$pool == "admitted" &
                   contrasts$pair == "declared - stock" & contrasts$metric %in% c("F1", "cF1"), ,
                 drop = FALSE]
  if (nrow(x) != 2L) stop("newfor: the primary contrast is missing (no admitted area?)",
                          call. = FALSE)
  x <- x[match(c("F1", "cF1"), x$metric), c("scenario", "pool", "pair", "config_a", "config_b",
                                             "metric", "n_plots", "estimate_a", "estimate_b",
                                             "difference", "lower", "upper")]
  x$reading <- nfa_reading(x$lower, x$upper)
  x$primary <- x$metric == "F1"
  rownames(x) <- NULL
  x
}

## ---- per plot ----------------------------------------------------------------------------------
# One row per area: its admission, stem counts, areas, densities, stand
# features, parity and registration estimate (features.csv), in_dev_range
# (nfa_in_dev_range of frdens_clip), then for stock and declared in scenario
# primary n_ref (shared), n_det, TP, tp_core, recall, precision and F1 (rates of
# one plot, for reading the table only), and the declared minus stock changes
# d_n_det, d_TP, d_fp (unmatched detections inside the polygon, n_det -
# tp_core) and d_F1.
nfa_per_plot <- function(cells, features) {
  f <- features[order(features$area, method = "radix"), NFA_FEATURE_COLS, drop = FALSE]
  x <- mcg_rates(cells[cells$scenario == "primary", , drop = FALSE])
  get <- function(nm) {
    r <- x[x$config_name == nm, , drop = FALSE]
    r[match(f$area, r$plot), , drop = FALSE]
  }
  s <- get("stock"); dcl <- get("declared")
  out <- f
  out$in_dev_range <- nfa_in_dev_range(f$frdens_clip)
  out$n_ref <- s$n_ref
  for (who in c("stock", "declared")) {
    r <- if (who == "stock") s else dcl
    for (k in c("n_det", "TP", "tp_core", "recall", "precision", "F1"))
      out[[paste0(who, "_", k)]] <- r[[k]]
  }
  out$d_n_det <- dcl$n_det - s$n_det
  out$d_TP <- dcl$TP - s$TP
  out$d_fp <- (dcl$n_det - dcl$tp_core) - (s$n_det - s$tp_core)
  out$d_F1 <- dcl$F1 - s$F1
  rownames(out) <- NULL
  out
}

## ---- leave one forest out ----------------------------------------------------------------------
# The primary contrast's F1 and cF1 differences in each without_<forest> pool
# (metric, pool, left_out, n_plots, difference, lower, upper), then per metric
# a row "minimum" and a row "maximum" naming the forest whose omission gives it.
nfa_lofo <- function(contrasts, features) {
  adm <- features[features$admitted %in% TRUE, , drop = FALSE]
  forests <- sort(unique(adm$forest), method = "radix")
  slug <- paste0("without_", nfa_slug(forests))
  x <- contrasts[contrasts$scenario == "primary" & contrasts$pair == "declared - stock" &
                   contrasts$pool %in% slug & contrasts$metric %in% c("F1", "cF1"), , drop = FALSE]
  cols <- c("metric", "pool", "left_out", "n_plots", "difference", "lower", "upper")
  if (!nrow(x)) return(stats::setNames(data.frame(matrix(nrow = 0, ncol = length(cols))), cols))
  x$left_out <- forests[match(x$pool, slug)]
  x <- x[order(match(x$metric, c("F1", "cF1")), x$pool, method = "radix"), cols, drop = FALSE]
  ext <- do.call(rbind, lapply(c("F1", "cF1"), function(m) {
    y <- x[x$metric == m & is.finite(x$difference), , drop = FALSE]
    if (!nrow(y)) return(NULL)
    lo <- y[which.min(y$difference), ]; hi <- y[which.max(y$difference), ]
    lo$pool <- "minimum"; hi$pool <- "maximum"
    rbind(lo, hi)
  }))
  out <- rbind(x, ext)
  rownames(out) <- NULL
  out
}

## ---- tables.md ---------------------------------------------------------------------------------
# Count columns are written as integers; every other number to three decimals.
.nfa_count <- function(col) {
  base <- sub("^(stock|declared)_", "", col)
  base %in% c("n_plots", "n_ref", "n_det", "TP", "tp_core", "n_rows", "n_inside", "n_outside",
              "n_primary", "n_inventoried", "n_missing_dbh", "n_below_caliper", "gap_months",
              "defined_draws", "d_n_det", "d_TP", "d_fp", "parity_n_package", "parity_n_stock",
              "n_apex") || grepl("^(n_h|tp_h)_(short|mid|tall)$", base)
}

.nfa_cell <- function(v, col) {
  if (is.logical(v)) return(ifelse(is.na(v), "NA", ifelse(v, "TRUE", "FALSE")))
  if (is.numeric(v)) {
    whole <- is.finite(v) & abs(v - round(v)) < 1e-9
    r <- round(v, 3); r[r == 0] <- 0                 # no "-0.000"
    out <- if (.nfa_count(col) && all(whole | !is.finite(v))) sprintf("%.0f", v)
           else sprintf("%.3f", r)
    out[is.na(v)] <- "NA"
    return(out)
  }
  v <- as.character(v)
  ifelse(is.na(v), "NA", gsub("|", "\\|", v, fixed = TRUE))
}

# A GitHub markdown table of `cols` of df (header names `head`), numbers right
# aligned; "(no rows)" for an empty table.
nfa_md_table <- function(df, cols, head = cols) {
  if (!nrow(df)) return("(no rows)")
  body <- matrix(vapply(cols, function(k) .nfa_cell(df[[k]], k), character(nrow(df))),
                 nrow = nrow(df))
  num <- vapply(cols, function(k) is.numeric(df[[k]]), logical(1))
  c(paste0("| ", paste(head, collapse = " | "), " |"),
    paste0("| ", paste(ifelse(num, "---:", "---"), collapse = " | "), " |"),
    apply(body, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}

# The header lines of tables.md that state the run's settings (each at most 80
# characters): root and protocol, the detector library's pin, the package
# versions, K, the resamples and seed, the areas run against the areas frozen,
# and, when settings$met is FALSE, why the run does not meet the protocol's
# settings (wrapped).
nfa_settings_lines <- function(record, settings, n_boot, seed) {
  txt <- function(x) if (is.null(x) || !length(x) || anyNA(x)) "not recorded"
                     else paste(x, collapse = ",")
  lib <- record$detector_library
  pin <- if (!is.list(lib) || is.null(lib$pin_matches) || is.null(lib$allow_unpinned))
    "pin not recorded"
    else if (isTRUE(lib$pin_matches) && isFALSE(lib$allow_unpinned)) "pinned"
    else if (isTRUE(lib$pin_matches)) "pinned, ALLOW_UNPINNED=1 given"
    else "unpinned, ALLOW_UNPINNED=1 given"
  vm <- record$versions_match
  ver <- if (is.null(vm) || anyNA(vm)) "pins not recorded"
    else if (isTRUE(vm)) "the pinned versions" else "not the pinned versions"
  areas <- if (is.null(record$root_areas))
    sprintf("Areas run: %d; the frozen areas are not recorded.", length(record$areas))
    else sprintf("Areas run: %d of the %d frozen.", length(record$areas),
                 length(record$root_areas))
  c(sprintf("Run with root %s, protocol %s.", substr(txt(record$frozen$root_id), 1, 12),
            substr(txt(record$protocol$sha256), 1, 12)),
    sprintf("Detector library blob %s: %s.", substr(txt(lib$git_blob), 1, 12), pin),
    sprintf("Packages: lidR %s, lidRplugins %s (%s).", txt(record$versions$lidR),
            txt(record$versions$lidRplugins), ver),
    sprintf("Null shifts per plot K = %s; %d resamples, seed %d.", txt(record$K),
            as.integer(n_boot), as.integer(seed)),
    areas,
    if (!isTRUE(settings$met))
      strwrap(paste0("This run does not meet the protocol's settings: ",
                     paste(settings$reasons, collapse = "; "), "."), width = 80))
}

# The report's tables, each preceded by a line naming the CSV it came from,
# under the header of nfa_settings_lines.
nfa_tables_md <- function(per_plot, pooled, contrasts, reading, lofo, pools, record, settings,
                          n_boot, seed) {
  sec <- function(title, source, tab) c(paste("##", title), "", source, "", tab, "")
  pa <- pooled[pooled$pool == "admitted", , drop = FALSE]
  pa <- pa[order(match(pa$scenario, NFA_SCENARIOS)), , drop = FALSE]
  ds <- contrasts[contrasts$pair == "declared - stock", , drop = FALSE]
  bands <- pa[pa$scenario %in% c("primary", "inventoried"), , drop = FALSE]
  band_cols <- unlist(lapply(NEWFOR_HEIGHT_BANDS, function(b)
    paste0(c("n_h_", "rec_h_", "null_rec_h_", "cRec_h_"), b)))
  c("# NEWFOR multichm: analysis tables", "",
    nfa_settings_lines(record, settings, n_boot, seed),
    "Counts are sums over plots; rates come from the summed counts.", "",
    sec("Admission", "From per_plot.csv.",
        nfa_md_table(per_plot, c("area", "forest", "n_rows", "n_inside", "n_outside", "n_primary",
                                 "n_inventoried", "n_missing_dbh", "n_below_caliper",
                                 "gap_months", "reach_min", "terrain_na_share", "offset",
                                 "admitted", "failed"))),
    sec("Density", paste("From per_plot.csv (per m2; clip-wide over the kept points'",
                         "convex hull)."),
        nfa_md_table(per_plot, c("area", "aoi_area", "frdens_aoi", "pdens_aoi", "covered_area",
                                 "frdens_clip", "pdens_clip", "res", "in_dev_range"))),
    sec("Pools", "From pools.csv.", nfa_md_table(nfa_pool_table(pools),
                                                 c("pool", "n_plots", "areas"))),
    sec("Per plot, primary population", "From per_plot.csv (per-plot rates are for reading only).",
        nfa_md_table(per_plot, c("area", "forest", "admitted", "frdens_clip", "cover",
                                 "crown_spacing", "gate_state", "parity_ok", "n_ref", "stock_n_det",
                                 "stock_TP", "stock_F1", "declared_n_det", "declared_TP",
                                 "declared_F1", "d_n_det", "d_TP", "d_fp", "d_F1"))),
    sec("Pooled, admitted areas", "From pooled.csv, pool admitted.",
        nfa_md_table(pa, c("scenario", "config_name", "n_plots", "n_ref", "n_det", "TP", "tp_core",
                           "recall", "precision", "F1", "null_F1", "cF1", "cRecall", "cPrecision",
                           "det_per_ref"))),
    sec("Primary contrast and its reading", "From reading.csv.",
        nfa_md_table(reading, c("metric", "n_plots", "estimate_a", "estimate_b", "difference",
                                "lower", "upper", "reading", "primary"))),
    sec("Declared minus stock, every metric",
        "From contrasts.csv, scenario primary, pool admitted.",
        nfa_md_table(ds[ds$scenario == "primary" & ds$pool == "admitted", , drop = FALSE],
                     c("metric", "n_plots", "estimate_a", "estimate_b", "difference", "lower",
                       "upper", "defined_draws"))),
    sec("Declared minus stock by scenario and pool", "From contrasts.csv, metrics F1 and cF1.",
        nfa_md_table(ds[ds$metric %in% c("F1", "cF1"), , drop = FALSE],
                     c("scenario", "pool", "metric", "n_plots", "estimate_a", "estimate_b",
                       "difference", "lower", "upper"))),
    sec("Decomposition", "From contrasts.csv, scenario primary, pool admitted.",
        nfa_md_table(contrasts[contrasts$scenario == "primary" & contrasts$pool == "admitted" &
                                 contrasts$metric %in% c("F1", "cF1", "precision", "recall"), ,
                               drop = FALSE],
                     c("pair", "metric", "n_plots", "estimate_a", "estimate_b", "difference",
                       "lower", "upper"))),
    sec("Leave one forest out", "From leave_one_forest_out.csv (declared minus stock, primary).",
        nfa_md_table(lofo, c("metric", "pool", "left_out", "n_plots", "difference", "lower",
                             "upper"))),
    sec("Recall by height band", "From pooled.csv, pool admitted (bands as score_plot cuts them).",
        nfa_md_table(bands, c("scenario", "config_name", band_cols))))
}

## ---- main --------------------------------------------------------------------------------------
.nfa_write_csv <- function(x, path) {
  tmp <- paste0(path, ".part")
  utils::write.csv(x, tmp, row.names = FALSE)
  if (!file.rename(tmp, path)) stop("newfor: could not write ", path, call. = FALSE)
  invisible(path)
}

run_main <- function(A = nfa_args()) {
  o <- nfa_options(A)
  code <- newfor_code_sha256(NFA_CODE, .find)        # a missing file stops before any write
  r <- nfa_read_run(o$run)
  nfa_check_support(r$cells, r$features, r$configs)
  pools <- nfa_pools(r$features)
  if (!length(pools$admitted)) stop("newfor: no admitted area in ", o$run, call. = FALSE)
  pooled <- nfa_pooled(r$cells, pools, r$configs)
  contrasts <- nfa_contrasts(r$cells, pools, r$configs, o$n_boot, o$seed)
  settings <- nfa_protocol_settings(r$record, o$n_boot, o$seed)
  reading <- nfa_reading_table(contrasts)
  reading$protocol_settings <- settings$met
  per_plot <- nfa_per_plot(r$cells, r$features)
  lofo <- nfa_lofo(contrasts, r$features)
  out <- file.path(o$run, "analysis")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  .nfa_write_csv(nfa_pool_table(pools), file.path(out, "pools.csv"))
  .nfa_write_csv(pooled, file.path(out, "pooled.csv"))
  .nfa_write_csv(contrasts, file.path(out, "contrasts.csv"))
  .nfa_write_csv(reading, file.path(out, "reading.csv"))
  .nfa_write_csv(per_plot, file.path(out, "per_plot.csv"))
  .nfa_write_csv(lofo, file.path(out, "leave_one_forest_out.csv"))
  writeLines(nfa_tables_md(per_plot, pooled, contrasts, reading, lofo, pools, r$record, settings,
                           o$n_boot, o$seed),
             file.path(out, "tables.md"))
  jsonlite::write_json(list(run_json_sha256 = frozen_sha256(file.path(o$run, "run.json")),
                            root_id = r$record$frozen$root_id,
                            protocol_sha256 = r$record$protocol$sha256,
                            code_sha256 = as.list(code),
                            n_boot = o$n_boot, seed = o$seed, min_interval_plots = NFA_MIN_INTERVAL,
                            not_worse_margin = NFA_NOT_WORSE, dev_frdens = NEWFOR_DEV_FRDENS,
                            protocol_settings = settings$met,
                            protocol_settings_reasons = I(settings$reasons),
                            pools = lapply(pools, I)),
                       file.path(out, "analysis.json"), auto_unbox = TRUE, pretty = TRUE,
                       digits = NA, na = "null")
  cat(sprintf("NEWFOR multichm analysis: %d areas, %d admitted; %d resamples, seed %d -> %s\n",
              length(pools$all), length(pools$admitted), o$n_boot, o$seed, out))
  if (!settings$met)
    cat("This run does not meet the protocol's settings:",
        paste(settings$reasons, collapse = "; "), "\n")
  print(reading[c("metric", "n_plots", "estimate_a", "estimate_b", "difference", "lower", "upper",
                  "reading")], row.names = FALSE, digits = 3)
  invisible(list(pools = pools, pooled = pooled, contrasts = contrasts, reading = reading,
                 per_plot = per_plot, lofo = lofo, settings = settings))
}

if (sys.nframe() == 0L) run_main()
