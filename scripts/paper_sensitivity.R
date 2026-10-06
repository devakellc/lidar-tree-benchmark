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
#   null       chance agreement: K random toroidal shifts of each cell's
#              detections within the core plus the match radius, at least
#              8 m from no shift (greedy matcher at radius TOL, default the
#              baseline's 4 m); draw k uses seed seed_for(site, plot, "null")
#              + k for every arm and rung
# The baseline must reproduce every arm's own result row (n_ref, n_det, TP);
# the script stops on any difference. Matcher and exact-2021 variants are
# pooled by summed counts with paired plot-bootstrap intervals (the master
# tables' resamples) over five sites, each region and each site, with each
# arm's paired lead over CHM-VWF within a variant; jitter is pooled per draw
# into 5th/50th/95th-percentile bands. The null pools each cell's mean counts
# over the K shifts as a "null" variant beside the observed one, with the
# observed score above the null and the lead over CHM-VWF above the null,
# overall and for overstory and understory stems.
#   Rscript scripts/paper_sensitivity.R MODE=matcher|exact2021|jitter|null
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [ARMS=...] [RUNGS=native,8,4,2,1]
#     [POP=adopted] [FROZEN_ROOT=...] [K=200] [CORES=8] [OUT=<dir>]
#     [TOL=4] (null only; another radius writes null_tol<TOL>_*.csv)
# Writes <OUT>/<mode>_cells.csv, <OUT>/<mode>_pooled.csv and
# <OUT>/<mode>_leads.csv (jitter: <mode>_draws.csv and <mode>_bands.csv;
# null: null_cells.csv, null_pooled.csv, null_delta.csv, null_leads.csv and
# null_strata.csv); OUT defaults to $CLAUDE_JOB_DIR/sensitivity.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d     <- .job_dir()
MODE  <- match.arg(A$MODE, c("matcher", "exact2021", "jitter", "null"))
SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
ARMS  <- split_arg(A$ARMS, paste(MT_ARMS$arm, collapse = ","))
RUNGS <- split_arg(A$RUNGS, "native,8,4,2,1")
K     <- as.integer(if (is.null(A$K)) 200 else A$K)
CORES <- as.integer(if (is.null(A$CORES)) 8 else A$CORES)
OUT   <- if (is.null(A$OUT)) file.path(d, "sensitivity") else A$OUT
POP   <- if (is.null(A$POP)) "adopted" else A$POP
BASE_TOL <- 4; TOL_CAP <- 12; LAMBDA <- 0.5
NULL_TOL <- as.numeric(if (is.null(A$TOL)) BASE_TOL else A$TOL)
NULL_SFX <- if (NULL_TOL == BASE_TOL) "null" else sprintf("null_tol%g", NULL_TOL)
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
NULL_CFG <- list(name = "null", method = "greedy", scaled = FALSE, tx = NULL_TOL, tz = 8, lambda = NULL)

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
  # Null shifts: one set per plot, shared by every arm and rung.
  offs <- if (MODE == "null") lapply(seq_len(K), function(k)
    null_offset(2 * (ph + NULL_TOL), seed_for(site, pid, "null") + k)) else NULL
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
      score <- function(st, cfg, variant, dt = det) {
        sc <- score_plot(st, dt, tol_xy = if (cfg$scaled) tol_vec else cfg$tx, core_cx = cx,
                         core_cy = cy, core_half = ph, method = cfg$method,
                         tol_z_up = cfg$tz, lambda = cfg$lambda)
        sc$tp_core <- ifelse(sc$n_det > 0, round(sc$precision * sc$n_det), 0)
        # Overstory (dominant, codominant) and understory (intermediate,
        # suppressed) counts, per-class TP recovered as round(recall x n).
        cls <- function(k) {
          n <- vapply(k, function(c) sc[[paste0("n_", c)]], numeric(1))
          r <- vapply(k, function(c) sc[[paste0("rec_", c)]], numeric(1))
          c(n = sum(n), tp = sum(ifelse(n > 0 & is.finite(r), round(r * n), 0)))
        }
        o <- cls(c("dominant", "codominant")); u <- cls(c("intermediate", "suppressed"))
        sc$n_over <- o[["n"]]; sc$tp_over <- o[["tp"]]
        sc$n_under <- u[["n"]]; sc$tp_under <- u[["tp"]]
        cbind(data.frame(variant = variant, site = site, plot = pid, rung = rung,
                         detector = arm, stringsAsFactors = FALSE), sc)
      }
      if (MODE == "matcher") {
        for (cfg in CONFIGS) rows[[length(rows) + 1]] <- score(stems, cfg, cfg$name)
      } else if (MODE == "exact2021") {
        rows[[length(rows) + 1]] <- score(stems, BASELINE, "baseline")
        st21 <- stems[!is.na(stems$meas_year) & stems$meas_year == 2021, , drop = FALSE]
        if (nrow(st21)) rows[[length(rows) + 1]] <- score(st21, BASELINE, "exact2021")
      } else if (MODE == "null") {
        rows[[length(rows) + 1]] <- score(stems, BASELINE, "baseline")
        # At another radius the observed score is a variant of its own; the
        # 4 m baseline stays for the check against the arms' own results.
        if (NULL_TOL != BASE_TOL) rows[[length(rows) + 1]] <- score(stems, NULL_CFG, "observed")
        for (k in seq_len(K)) {
          r <- score(stems, NULL_CFG, sprintf("null%03d", k),
                     shift_detections(det, cx, cy, ph + NULL_TOL, offs[[k]]))
          rows[[length(rows) + 1]] <- r[, c("variant", "site", "plot", "rung", "detector",
                                            "n_ref", "n_det", "TP", "tp_core", "n_over",
                                            "tp_over", "n_under", "tp_under")]
        }
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

if (MODE == "null") {
  # Each cell's null is its mean count over the K shifts, pooled like an
  # observed variant on the same plots and resamples.
  cl <- as.data.table(cells)
  if (NULL_TOL != BASE_TOL) {
    cl <- cl[variant != "baseline"]
    cl[variant == "observed", variant := "baseline"]
  }
  cnt <- c("n_ref", "n_det", "TP", "tp_core", "n_over", "tp_over", "n_under", "tp_under")
  nul <- cl[variant != "baseline", c(lapply(.SD, mean), list(draws = .N)),
            by = .(site, plot, rung, detector), .SDcols = cnt]
  if (any(nul$draws != K)) stop("A cell is missing null draws")
  nul[, variant := "null"]
  cn <- rbind(cl[variant == "baseline", c("variant", "site", "plot", "rung", "detector", cnt), with = FALSE],
              nul[, c("variant", "site", "plot", "rung", "detector", cnt), with = FALSE])
  cn <- as.data.frame(cn)
  write.csv(cn, file.path(OUT, paste0(NULL_SFX, "_cells.csv")), row.names = FALSE)
  strata <- list(all = c("n_ref", "TP"), overstory = c("n_over", "tp_over"),
                 understory = c("n_under", "tp_under"))
  pool_null <- function(x) {
    key <- paste(x$site, x$plot, sep = "::")
    common <- Reduce(intersect, lapply(split(key, paste(x$variant, x$detector)), unique))
    x <- x[key %in% common, , drop = FALSE]
    W <- mt_plot_weights(x$site, x$plot, MT_N_BOOT, MT_SEED)
    site_of <- sub("::.*", "", rownames(W))
    r <- x$rung[1]; arms <- unique(x$detector)
    g <- function(v, a) paste(v, a, r, sep = "|")
    out <- list()
    for (sc in names(scopes)) {
      keep <- site_of %in% scopes[[sc]]
      if (!any(keep)) next
      xs <- x[x$site %in% scopes[[sc]], , drop = FALSE]
      for (st in names(strata)) {
        xx <- xs; xx$n_ref <- xs[[strata[[st]][1]]]; xx$TP <- xs[[strata[[st]][2]]]
        s <- mt_boot_scores(xx, W[keep, , drop = FALSE], c("variant", "detector", "rung"))
        mets <- if (st == "all") c("recall", "precision", "F1") else "recall"
        est <- cbind(scope = sc, stratum = st, mt_intervals(s, mets))
        # Observed minus null, per arm; for F1 also the share of the headroom
        # above the null, (observed - null) / (1 - null), as in Cohen's kappa.
        E1 <- s$estimate$F1; names(E1) <- s$groups; D1 <- s$draws$F1
        scaled <- function(v, a) list(e = (E1[g(v, a)] - E1[g("null", a)]) / (1 - E1[g("null", a)]),
                                      d = (D1[, g(v, a)] - D1[, g("null", a)]) / (1 - D1[, g("null", a)]))
        dl <- do.call(rbind, lapply(arms, function(a) rbind(
          do.call(rbind, lapply(mets, function(m)
            cbind(scope = sc, stratum = st, detector = a, rung = r,
                  mt_contrast(s, g("null", a), g("baseline", a), m)))),
          if (st == "all") { k <- scaled("baseline", a)
            cbind(data.frame(scope = sc, stratum = st, detector = a, rung = r,
                             from = g("null", a), to = g("baseline", a), metric = "F1_scaled",
                             estimate = unname(k$e)), mt_interval(k$d)) })))
        # Lead over CHM-VWF: observed, under the null, and above the null.
        ld <- if ("chm_vwf" %in% arms) do.call(rbind, lapply(setdiff(arms, "chm_vwf"), function(a)
          do.call(rbind, lapply(mets, function(m) {
            E <- s$estimate[[m]]; names(E) <- s$groups; D <- s$draws[[m]]
            lead <- function(v) c(E[g(v, a)] - E[g(v, "chm_vwf")])
            dd <- function(v) D[, g(v, a)] - D[, g(v, "chm_vwf")]
            rbind(
              cbind(data.frame(scope = sc, stratum = st, detector = a, rung = r, metric = m,
                               kind = "observed", estimate = lead("baseline")), mt_interval(dd("baseline"))),
              cbind(data.frame(scope = sc, stratum = st, detector = a, rung = r, metric = m,
                               kind = "null", estimate = lead("null")), mt_interval(dd("null"))),
              cbind(data.frame(scope = sc, stratum = st, detector = a, rung = r, metric = m,
                               kind = "above_null", estimate = lead("baseline") - lead("null")),
                    mt_interval(dd("baseline") - dd("null"))),
              if (m == "F1") {
                ka <- scaled("baseline", a); kc <- scaled("baseline", "chm_vwf")
                cbind(data.frame(scope = sc, stratum = st, detector = a, rung = r, metric = m,
                                 kind = "above_null_scaled", estimate = unname(ka$e - kc$e)),
                      mt_interval(ka$d - kc$d))
              })
          })))) else NULL
        out[[length(out) + 1]] <- list(est = est, delta = dl, leads = ld)
      }
    }
    out
  }
  parts <- unlist(lapply(split(cn, cn$rung), pool_null), recursive = FALSE)
  est <- do.call(rbind, lapply(parts, `[[`, "est"))
  write.csv(est[est$stratum == "all", setdiff(names(est), "stratum")],
            file.path(OUT, paste0(NULL_SFX, "_pooled.csv")), row.names = FALSE)
  write.csv(est[est$stratum != "all", ], file.path(OUT, paste0(NULL_SFX, "_strata.csv")), row.names = FALSE)
  write.csv(do.call(rbind, lapply(parts, `[[`, "delta")), file.path(OUT, paste0(NULL_SFX, "_delta.csv")),
            row.names = FALSE)
  write.csv(do.call(rbind, lapply(parts, `[[`, "leads")), file.path(OUT, paste0(NULL_SFX, "_leads.csv")),
            row.names = FALSE)
  cat(sprintf("wrote %s and %s_delta/leads/strata.csv\n", file.path(OUT, paste0(NULL_SFX, "_pooled.csv")),
              NULL_SFX))
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
    # Paired lead of each arm over CHM-VWF within a variant.
    ld <- do.call(rbind, lapply(unique(xs$variant), function(v)
      do.call(rbind, lapply(setdiff(unique(xs$detector), "chm_vwf"), function(a) {
        from <- paste(v, "chm_vwf", x$rung[1], sep = "|"); to <- paste(v, a, x$rung[1], sep = "|")
        if (!all(c(from, to) %in% s$groups)) return(NULL)
        cbind(scope = sc, variant = v, detector = a, rung = x$rung[1], mt_contrast(s, from, to, "F1"))
      }))))
    list(est = est, delta = vs, leads = ld)
  }))
}
parts <- lapply(split(cells, cells$rung), pool_rung)
pooled <- do.call(rbind, lapply(parts, function(p) do.call(rbind, p[, "est"])))
delta <- do.call(rbind, lapply(parts, function(p) do.call(rbind, p[, "delta"])))
leads <- do.call(rbind, lapply(parts, function(p) do.call(rbind, p[, "leads"])))
write.csv(leads, file.path(OUT, paste0(MODE, "_leads.csv")), row.names = FALSE)
# Isolated share of core false positives (score_plot's fp structure), baseline.
fps <- as.data.table(cells)[variant == "baseline", .(fp_near = sum(fp_near, na.rm = TRUE),
  fp_isolated = sum(fp_isolated, na.rm = TRUE)), by = .(detector, rung)]
fps[, isolated_share := fp_isolated / (fp_near + fp_isolated)]
write.csv(pooled, file.path(OUT, paste0(MODE, "_pooled.csv")), row.names = FALSE)
write.csv(delta, file.path(OUT, paste0(MODE, "_delta.csv")), row.names = FALSE)
write.csv(fps, file.path(OUT, paste0(MODE, "_fp_structure.csv")), row.names = FALSE)
cat(sprintf("wrote %s (%d rows), %s_delta.csv (%d rows)\n", file.path(OUT, paste0(MODE, "_pooled.csv")),
            nrow(pooled), MODE, nrow(delta)))
