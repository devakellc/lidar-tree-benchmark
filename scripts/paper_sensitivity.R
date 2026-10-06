#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(data.table); library(lidR) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
source(.find("io_bridge.R"))
source(.find("census_support_lib.R"))
source(.find("coverage_lib.R"))
source(.find("master_tables_lib.R"))

# Scoring sensitivity of every benchmark arm on the sealed frozen root, from
# the arms' persisted per-cell detections (no inference): the paper runs'
# detections, instance clouds and optical box caches, read as the censused
# scorer reads them. Each cell is re-scored against the declared population's
# core stems under one MODE:
#   matcher    the matcher-robustness configurations (baseline greedy 4 m,
#              crown-scaled tolerance, Hungarian, Hungarian scaled, soft 3-D)
#              and the greedy tol_xy x tol_z_up grid
#   exact2021  only the core stems measured in 2021 (baseline matcher)
#   jitter     K draws of stem positions, sigma = pos_unc (baseline matcher);
#              draw k uses seed seed_for(site, plot, "native") + k
# The baseline must reproduce every arm's own result row (n_ref, n_det, TP);
# the script stops on any difference. Matcher and exact-2021 variants are
# pooled by summed counts with paired plot-bootstrap intervals (the master
# tables' resamples) over five sites, each region and each site; jitter is
# pooled per draw into 5th/50th/95th-percentile bands.
#   Rscript scripts/paper_sensitivity.R MODE=matcher|exact2021|jitter
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [ARMS=...] [RUNGS=native,8,4,2,1]
#     [POP=adopted] [FROZEN_ROOT=...] [K=200] [CORES=8] [OUT=<dir>]
# Writes <OUT>/<mode>_cells.csv and <OUT>/<mode>_pooled.csv (jitter:
# <mode>_draws.csv and <mode>_bands.csv); OUT defaults to
# $CLAUDE_JOB_DIR/sensitivity.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d     <- .job_dir()
MODE  <- match.arg(A$MODE, c("matcher", "exact2021", "jitter"))
SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
ARMS  <- split_arg(A$ARMS, paste(MT_ARMS$arm, collapse = ","))
RUNGS <- split_arg(A$RUNGS, "native,8,4,2,1")
K     <- as.integer(if (is.null(A$K)) 200 else A$K)
CORES <- as.integer(if (is.null(A$CORES)) 8 else A$CORES)
OUT   <- if (is.null(A$OUT)) file.path(d, "sensitivity") else A$OUT
POP   <- if (is.null(A$POP)) "adopted" else A$POP
BASE_TOL <- 4; TOL_CAP <- 12; LAMBDA <- 0.5
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
if (length(setdiff(ARMS, MT_ARMS$arm))) stop("Unknown arms: ", paste(setdiff(ARMS, MT_ARMS$arm), collapse = ", "))

# The matcher-robustness configurations (matcher_robustness.R).
CONFIGS <- c(list(
  list(name = "baseline",       method = "greedy",  scaled = FALSE, tx = BASE_TOL, tz = 8, lambda = NULL),
  list(name = "scaled",         method = "greedy",  scaled = TRUE,  tx = BASE_TOL, tz = 8, lambda = NULL),
  list(name = "optimal",        method = "optimal", scaled = FALSE, tx = BASE_TOL, tz = 8, lambda = NULL),
  list(name = "optimal_scaled", method = "optimal", scaled = TRUE,  tx = BASE_TOL, tz = 8, lambda = NULL),
  list(name = "soft3d",         method = "optimal", scaled = FALSE, tx = BASE_TOL, tz = 8, lambda = LAMBDA)),
  unlist(lapply(c(2, 3, 4, 5), function(tx) lapply(c(5, 8, 12), function(tz)
    list(name = sprintf("grid_tx%g_tz%g", tx, tz), method = "greedy", scaled = FALSE,
         tx = tx, tz = tz, lambda = NULL))), recursive = FALSE))
BASELINE <- CONFIGS[[1]]

# SAM2Point's per-point labels are heights above ground (rescore_population.R).
CENSUS_INSTANCE_SOURCES$sam2point <- list(dir = "sam2point_instances", id = "sam2point", agl = FALSE)

## ---- field crown widths for the scaled tolerance (matcher_robustness.R) ----------
field_crowns <- function(site) {
  rds <- file.path(d, "neon", site, "vst", paste0(tolower(site), "_vst_allyears.rds"))
  if (!file.exists(rds)) return(data.frame(individualID = character(), maxCrownDiameter = numeric()))
  ai <- as.data.frame(readRDS(rds)$vst_apparentindividual)
  ai$year <- as.integer(substr(ai$date, 1, 4))
  ai <- ai[!is.na(ai$year), ]
  ai <- ai[order(ai$individualID, abs(ai$year - 2021)), ]
  ai[!duplicated(ai$individualID), c("individualID", "maxCrownDiameter")]
}

## ---- optical inputs, as the optical sweeps and coverage_gap.R read them ---------------
plot_chm <- function(cell) {
  if (is.null(cell)) return(NULL)
  las <- tryCatch(suppressWarnings(lidR::readLAS(cell$normalized)), error = function(e) NULL)
  if (is.null(las) || lidR::is.empty(las)) return(NULL)
  tryCatch(suppressWarnings(lidR::rasterize_canopy(las, res = 0.5, algorithm = lidR::p2r())),
           error = function(e) NULL)
}
site_deepforest_boxes <- function(nd) {
  fs <- Sys.glob(file.path(nd, "deepforest_boxes", "*.csv"))
  if (!length(fs)) return(NULL)
  b <- rbindlist(lapply(fs, function(f)
    tryCatch(read.csv(f, stringsAsFactors = FALSE), error = function(e) NULL)), fill = TRUE)
  if (!nrow(b)) NULL else as.data.frame(b)
}

## ---- one arm's detections for one cell ------------------------------------------------
# Optical arms: their cached boxes inside the plot window, with apex heights
# from the native frozen canopy model (coverage_gap.R). Others: the persisted
# detections or instance clouds (census_cell_detections).
optical_dets <- function(nd, arm, pid, cx, cy, ph, chm, df_boxes) {
  bp <- if (arm == "deepforest") df_boxes else {
    f <- file.path(nd, "detectree2_boxes", paste0(pid, ".csv"))
    if (file.exists(f)) read.csv(f, stringsAsFactors = FALSE) else NULL }
  if (is.null(bp) || is.null(chm)) return(NULL)
  bp <- bp[abs(bp$x - cx) <= ph + BASE_TOL & abs(bp$y - cy) <= ph + BASE_TOL, , drop = FALSE]
  boxes_to_dets(bp, chm)
}

## ---- one plot ----------------------------------------------------------------------------
run_plot <- function(site, pid, ctx) {
  ci <- ctx$pc[ctx$pc$plotID == pid, ][1, ]
  cx <- ci$easting; cy <- ci$northing; ph <- plot_half(ci$plotType)
  stems <- ctx$gt[ctx$gt$plotID == pid & abs(ctx$gt$E - cx) <= ph & abs(ctx$gt$N - cy) <= ph, , drop = FALSE]
  if (!nrow(stems)) return(NULL)
  native <- frozen_clip(NULL, site, pid, NA, cx, cy, ph, ctx$root)
  chm <- if (any(ARMS %in% c("deepforest", "detectree2")) && !is.null(native)) plot_chm(native) else NULL
  tol_vec <- match_tol(stems$maxCrownDiameter, stems$pos_unc, base_tol = BASE_TOL, k = 1, tol_cap = TOL_CAP)
  rows <- list()
  for (rung in RUNGS) {
    rv <- if (rung == "native") NA_real_ else as.numeric(rung)
    cell <- if (is.na(rv)) native else frozen_clip(NULL, site, pid, rv, cx, cy, ph, ctx$root)
    if (is.null(cell)) next
    for (arm in ARMS) {
      a <- MT_ARMS[MT_ARMS$arm == arm, ]
      if (!rung %in% strsplit(a$rungs, ",")[[1]]) next
      det <- if (arm %in% c("deepforest", "detectree2"))
        optical_dets(ctx$nd, arm, pid, cx, cy, ph, chm, ctx$df_boxes) else
        census_cell_detections(ctx$nd, arm, site, pid, rv, ctx$root, cell)
      if (is.null(det)) next
      score <- function(st, cfg, variant) {
        sc <- score_plot(st, det, tol_xy = if (cfg$scaled) tol_vec else cfg$tx, core_cx = cx,
                         core_cy = cy, core_half = ph, method = cfg$method,
                         tol_z_up = cfg$tz, lambda = cfg$lambda)
        sc$tp_core <- ifelse(sc$n_det > 0, round(sc$precision * sc$n_det), 0)
        cbind(data.frame(variant = variant, site = site, plot = pid, rung = rung,
                         detector = arm, stringsAsFactors = FALSE), sc)
      }
      if (MODE == "matcher") {
        for (cfg in CONFIGS) rows[[length(rows) + 1]] <- score(stems, cfg, cfg$name)
      } else if (MODE == "exact2021") {
        rows[[length(rows) + 1]] <- score(stems, BASELINE, "baseline")
        st21 <- stems[!is.na(stems$meas_year) & stems$meas_year == 2021, , drop = FALSE]
        if (nrow(st21)) rows[[length(rows) + 1]] <- score(st21, BASELINE, "exact2021")
      } else {
        rows[[length(rows) + 1]] <- score(stems, BASELINE, "baseline")
        seed0 <- seed_for(site, pid, "native")
        for (k in seq_len(K)) {
          pj <- perturb_positions(stems$E, stems$N, stems$pos_unc, seed0 + k)
          st <- stems; st$E <- pj$E; st$N <- pj$N
          r <- score(st, BASELINE, sprintf("draw%03d", k))
          rows[[length(rows) + 1]] <- r[, c("variant", "site", "plot", "rung", "detector",
                                            "n_ref", "n_det", "TP", "tp_core")]
        }
      }
    }
  }
  if (length(rows)) rbindlist(rows, fill = TRUE) else NULL
}

## ---- cells -------------------------------------------------------------------------------
cells <- rbindlist(lapply(SITES, function(site) {
  nd <- file.path(d, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  fz <- frozen_scope(d, site, A, gt)
  g <- fz$gt[, setdiff(names(fz$gt), "maxCrownDiameter"), drop = FALSE]
  g <- merge(g, field_crowns(site), by = "individualID", all.x = TRUE)
  ctx <- list(nd = nd, gt = g, pc = pc, root = fz$root,
              df_boxes = if ("deepforest" %in% ARMS) site_deepforest_boxes(nd) else NULL)
  plots <- intersect(fz$plots, pc$plotID)
  cat(sprintf("[%s] %s: %d plots, %d arms\n", site, MODE, length(plots), length(ARMS)))
  res <- plot_lapply(plots, function(p) tryCatch(run_plot(site, p, ctx), error = skip_failed_plot(p)),
                     mc.cores = CORES, mc.preschedule = FALSE)
  rbindlist(Filter(Negate(is.null), res), fill = TRUE)
}), fill = TRUE)
cells <- as.data.frame(cells)

## ---- the baseline must be each arm's own result ------------------------------------------
own <- do.call(rbind, lapply(ARMS, function(arm) {
  a <- MT_ARMS[MT_ARMS$arm == arm, ]
  do.call(rbind, lapply(SITES, function(site) {
    f <- file.path(d, "neon", site, a$file)
    if (!file.exists(f)) return(NULL)
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x <- x[x$detector == a$detector, , drop = FALSE]
    if (!is.na(a$result_rung)) x$rung[x$rung == a$result_rung] <- "native"
    if (!nrow(x)) return(NULL)
    data.frame(site = site, plot = x$plot, rung = x$rung, detector = arm,
               own_n_ref = x$n_ref, own_n_det = x$n_det, own_TP = x$TP, stringsAsFactors = FALSE)
  }))
}))
base <- cells[cells$variant == "baseline", c("site", "plot", "rung", "detector", "n_ref", "n_det", "TP")]
chk <- merge(base, own, by = c("site", "plot", "rung", "detector"), all.x = TRUE)
bad <- chk[is.na(chk$own_TP) | chk$n_ref != chk$own_n_ref | chk$n_det != chk$own_n_det |
             chk$TP != chk$own_TP, , drop = FALSE]
write.csv(bad, file.path(OUT, paste0(MODE, "_baseline_mismatch.csv")), row.names = FALSE)
cat(sprintf("baseline check: %d cells, %d differ from the arms' own results\n", nrow(chk), nrow(bad)))
if (nrow(bad)) {
  print(utils::head(bad, 20), row.names = FALSE)
  stop("The re-scored baseline differs from the arms' own results; see ", MODE, "_baseline_mismatch.csv")
}

## ---- pooling --------------------------------------------------------------------------------
scopes <- c(list(`five sites` = SITES), MT_REGIONS[vapply(MT_REGIONS, function(s) any(s %in% SITES), TRUE)],
            setNames(as.list(SITES), SITES))
if (MODE == "jitter") {
  draws <- cells[cells$variant != "baseline", , drop = FALSE]
  write.csv(cells[cells$variant == "baseline", , drop = FALSE], file.path(OUT, "jitter_cells.csv"), row.names = FALSE)
  pooled <- rbindlist(lapply(names(scopes), function(sc) {
    x <- as.data.table(draws[draws$site %in% scopes[[sc]], , drop = FALSE])
    if (!nrow(x)) return(NULL)
    p <- x[, .(n_ref = sum(n_ref), n_det = sum(n_det), TP = sum(TP), tp_core = sum(tp_core)),
           by = .(variant, detector, rung)]
    p[, `:=`(recall = TP / n_ref, precision = tp_core / n_det)]
    p[, F1 := 2 * recall * precision / (recall + precision)]
    p[, scope := sc]
    p
  }))
  write.csv(pooled, file.path(OUT, "jitter_draws.csv"), row.names = FALSE)
  bands <- pooled[, .(draws = .N,
                      recall_p05 = quantile(recall, 0.05), recall_p50 = median(recall), recall_p95 = quantile(recall, 0.95),
                      precision_p05 = quantile(precision, 0.05, na.rm = TRUE), precision_p50 = median(precision, na.rm = TRUE),
                      precision_p95 = quantile(precision, 0.95, na.rm = TRUE),
                      F1_p05 = quantile(F1, 0.05, na.rm = TRUE), F1_p50 = median(F1, na.rm = TRUE),
                      F1_p95 = quantile(F1, 0.95, na.rm = TRUE)), by = .(scope, detector, rung)]
  write.csv(bands, file.path(OUT, "jitter_bands.csv"), row.names = FALSE)
  cat(sprintf("wrote %s (%d rows)\n", file.path(OUT, "jitter_bands.csv"), nrow(bands)))
  quit(save = "no")
}

write.csv(cells, file.path(OUT, paste0(MODE, "_cells.csv")), row.names = FALSE)
# Per rung, the plots every arm-variant scored (exact-2021 drops plots without
# 2021 stems for both cuts, so the baseline is compared on the same plots).
pool_rung <- function(x) {
  key <- paste(x$site, x$plot, sep = "::")
  common <- Reduce(intersect, lapply(split(key, paste(x$variant, x$detector)), unique))
  x <- x[key %in% common, , drop = FALSE]
  W <- mt_plot_weights(x$site, x$plot, MT_N_BOOT, MT_SEED)
  site_of <- sub("::.*", "", rownames(W))
  do.call(rbind, lapply(names(scopes), function(sc) {
    keep <- site_of %in% scopes[[sc]]
    if (!any(keep)) return(NULL)
    xs <- x[x$site %in% scopes[[sc]], , drop = FALSE]
    s <- mt_boot_scores(xs, W[keep, , drop = FALSE], c("variant", "detector", "rung"))
    est <- cbind(scope = sc, mt_intervals(s))
    # Paired change from the baseline variant, per arm and metric.
    vs <- do.call(rbind, lapply(setdiff(unique(xs$variant), "baseline"), function(v)
      do.call(rbind, lapply(unique(xs$detector), function(a) do.call(rbind, lapply(
        c("recall", "precision", "F1"), function(m) {
          from <- paste("baseline", a, x$rung[1], sep = "|"); to <- paste(v, a, x$rung[1], sep = "|")
          if (!all(c(from, to) %in% s$groups)) return(NULL)
          cbind(scope = sc, variant = v, detector = a, rung = x$rung[1], mt_contrast(s, from, to, m))
        }))))))
    list(est = est, delta = vs)
  }))
}
parts <- lapply(split(cells, cells$rung), pool_rung)
pooled <- do.call(rbind, lapply(parts, function(p) do.call(rbind, p[, "est"])))
delta <- do.call(rbind, lapply(parts, function(p) do.call(rbind, p[, "delta"])))
# Isolated share of core false positives (score_plot's fp structure), baseline.
fps <- as.data.table(cells)[variant == "baseline", .(fp_near = sum(fp_near, na.rm = TRUE),
  fp_isolated = sum(fp_isolated, na.rm = TRUE)), by = .(detector, rung)]
fps[, isolated_share := fp_isolated / (fp_near + fp_isolated)]
write.csv(pooled, file.path(OUT, paste0(MODE, "_pooled.csv")), row.names = FALSE)
write.csv(delta, file.path(OUT, paste0(MODE, "_delta.csv")), row.names = FALSE)
write.csv(fps, file.path(OUT, paste0(MODE, "_fp_structure.csv")), row.names = FALSE)
cat(sprintf("wrote %s (%d rows), %s_delta.csv (%d rows)\n", file.path(OUT, paste0(MODE, "_pooled.csv")),
            nrow(pooled), MODE, nrow(delta)))
