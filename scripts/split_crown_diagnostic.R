#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(lidR); library(data.table) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
source(.find("io_bridge.R"))
source(.find("coverage_lib.R"))           # read_arm_cache
source(.find("census_support_lib.R"))
source(.find("master_tables_lib.R"))
source(.find("census_null_lib.R"))        # CN_LABELS
source(.find("chance_simulation_lib.R"))
source(.find("split_crown_lib.R"))

# Split-crown diagnostic (post hoc): do the benchmark's detectors place second
# detections beside the trees they detect, the split crowns that the
# chance-correction simulation shows lift chance-corrected scores? From every
# arm's persisted native-density detections (no inference), read as the paper's
# scorers read them (census_cell_detections), on the declared population's
# plots of the sealed root, in two scopes:
#   all_plots  the nominal plot cores, matched as paper_sensitivity.R's baseline
#              (greedy 4 m, height gate) against the core stems;
#   censused   the censused subplots of the headline census declaration, matched
#              as the censused scorer does (score_neon_support).
# Per cell and scope (split_crown_lib.R): close pairs of detections 1.5-4 m
# apart; a valley test on the native canopy model between the two (no valley:
# the profile never drops more than a threshold below the lower end); and
# split-crown candidates, unmatched counted detections 1.5-4 m from a matched
# detection of the same arm with no valley between. Two canopy models of the
# native clip, both 0.5 m: "p2r", the highest point per cell, as the paper builds
# the canopy model for the optical arms (paper_sensitivity.R plot_chm), and
# "pitfree", lidR's pit-free model (thresholds 0, 2, 5, 10, 15 m, max edge 0 and
# 1.5 m, subcircle 0.15 m), which closes the laser pits that read as false
# valleys. The mapped reference stems' own close-pair rate rides along.
# Pooling sums counts over plots; intervals are 95% percentile intervals of the
# master tables' paired plot bootstrap (1,000 resamples, seed 20261002, drawn on
# each scope's plots), shared by every arm, so leads over CHM-VWF are paired.
# A calibration (SIM=1) applies the same counts, without a canopy model, to the
# chance-correction simulation's plots (240 trees/ha, complete reference) with
# the baseline detector and its split crowns at rates 0, 0.5 and 0.8.
#
# Checks (written to split_crowns_checks.txt; the script stops on a failure):
#   A  every all_plots cell's n_ref, n_det and TP equal the arm's own results;
#   B  every censused cell's n_ref, n_det, TP and tp_core equal the committed
#      censused scores (census_support_scores nearest_ladder and nearest_native);
#   C  each arm and scope covers the same plots (equal support).
#
#   Rscript scripts/split_crown_diagnostic.R
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [POP=adopted] [FROZEN_ROOT=...]
#     [ARMS=chm_vwf,multichm,lmfauto,ptrees,ams3d,li2012,forestformer3d,treeisonet,segmentanytree]
#     [DECLARATION=docs/census-support-declaration-nearest.json]
#     [SUPPORT=$CLAUDE_JOB_DIR/reference_support_census_event] [YEARS=2019,...,2024]
#     [CENSUS_SCORES=<dir>,...] [TOL=4] [RMIN=1.5] [RMAX=4] [ABS=0.5,1,2]
#     [REL=0.05,0.1,0.2] [SUB_GAP=2] [CORES=8] [SIM=1] [SIM_N=200]
#     [OUT=$CLAUDE_JOB_DIR/sensitivity/split_crowns]
# Writes OUT/split_crowns_{cells,pairs,pooled,leads,surplus,reference,
# simulation,checks}.* and split_crowns_tables.md. lidR runs single-threaded in
# every worker (plot_lapply); no lasR is used.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
num_arg <- function(x, default) as.numeric(split_arg(x, default))
d <- .job_dir()
SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
ARMS <- split_arg(A$ARMS, paste(CN_ARMS, collapse = ","))
BASE <- "chm_vwf"
DECLARATION <- if (is.null(A$DECLARATION))
  file.path(.ROOT, "docs", "census-support-declaration-nearest.json") else A$DECLARATION
declaration <- jsonlite::read_json(DECLARATION, simplifyVector = TRUE)
if (grepl("DRAFT", declaration$name)) stop("Refusing a draft declaration; review and rename it first")
SUPPORT <- if (is.null(A$SUPPORT)) file.path(d, "reference_support_census_event") else A$SUPPORT
YEARS <- as.integer(split_arg(A$YEARS, paste(2019:2024, collapse = ",")))
CENSUS_SCORES <- split_arg(A$CENSUS_SCORES, paste(file.path(d, "census_support_scores",
  c("nearest_ladder", "nearest_native")), collapse = ","))
TOL <- num_arg(A$TOL, "4")
RMIN <- num_arg(A$RMIN, "1.5"); RMAX <- num_arg(A$RMAX, "4")
THR <- sc_thresholds(abs = num_arg(A$ABS, "0.5,1,2"), rel = num_arg(A$REL, "0.05,0.1,0.2"))
SUB_GAP <- num_arg(A$SUB_GAP, "2")
CORES <- as.integer(if (is.null(A$CORES)) 8 else A$CORES)
SIM <- !identical(A$SIM, "0")
SIM_N <- as.integer(if (is.null(A$SIM_N)) 200 else A$SIM_N)
OUT <- if (is.null(A$OUT)) file.path(d, "sensitivity", "split_crowns") else A$OUT
if (!BASE %in% ARMS) stop("ARMS must include ", BASE)
if (length(setdiff(ARMS, CN_ARMS))) stop("Unknown arms: ", paste(setdiff(ARMS, CN_ARMS), collapse = ", "))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
outf <- function(what) file.path(OUT, paste0("split_crowns_", what))
CHMS <- c("p2r", "pitfree")
cat(sprintf("job dir: %s\nOUT: %s\nARMS: %s\nTOL=%g RMIN=%g RMAX=%g SUB_GAP=%g CORES=%d SIM=%s\n",
            d, OUT, paste(ARMS, collapse = ","), TOL, RMIN, RMAX, SUB_GAP, CORES, SIM))

# The native canopy models of one frozen cell (see the header).
native_chms <- function(cell) {
  las <- suppressWarnings(lidR::readLAS(cell$normalized))
  if (is.null(las) || lidR::is.empty(las)) stop("Empty native clip")
  list(p2r = suppressWarnings(lidR::rasterize_canopy(las, res = 0.5, algorithm = lidR::p2r())),
       pitfree = suppressWarnings(lidR::rasterize_canopy(las, res = 0.5,
         algorithm = lidR::pitfree(c(0, 2, 5, 10, 15), c(0, 1.5), subcircle = 0.15))))
}

## ---- phase 1 (sequential): plots, stems and support bundles ----------------------------
jobs <- list()
for (site in SITES) {
  nd <- file.path(d, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  fz <- frozen_scope(d, site, A, gt)
  epsg <- invisible(neon_validate_inputs(fz$gt, pc))
  bundles <- census_admitted_bundles(SUPPORT, site, declaration, YEARS)
  plots <- intersect(fz$plots, pc$plotID)
  cat(sprintf("[%s] %d plots, %d admitted to the censused scope\n", site, length(plots),
              length(intersect(plots, names(bundles)))))
  for (pid in plots) {
    ci <- pc[pc$plotID == pid, ][1, ]
    cx <- ci$easting; cy <- ci$northing; ph <- plot_half(ci$plotType)
    g <- fz$gt[fz$gt$plotID == pid, , drop = FALSE]
    stems <- g[abs(g$E - cx) <= ph & abs(g$N - cy) <= ph, , drop = FALSE]
    if (!nrow(stems)) next
    jobs[[length(jobs) + 1]] <- list(
      site = site, pid = pid, plot_type = ci$plotType, cx = cx, cy = cy, ph = ph, nd = nd,
      root = fz$root, epsg = epsg, stems = stems,
      region_stems = g[is.finite(g$E) & is.finite(g$N) & abs(g$E - cx) <= ph + TOL &
                         abs(g$N - cy) <= ph + TOL, c("E", "N")],
      bundle = if (pid %in% names(bundles)) bundles[[pid]] else NULL)
  }
}
cat(sprintf("phase 1: %d plots\n", length(jobs)))

## ---- phase 2 (parallel over plots) -----------------------------------------------------
run_job <- function(j) {
  native <- frozen_clip(NULL, j$site, j$pid, NA, j$cx, j$cy, j$ph, j$root)
  if (is.null(native)) stop("No native cell for ", j$pid)
  H <- lapply(native_chms(native), sc_height_at)
  key <- function(scope) data.frame(scope = scope, site = j$site, plot = j$pid,
                                    plot_type = j$plot_type, stringsAsFactors = FALSE)
  cells <- list(); pairs <- list(); scores <- list(); missing <- character()
  # The reference stems' own close pairs: all_plots, the core stems among the
  # population's stems of the plot in the scoring region; censused, the
  # selected references of the admitted bundle.
  ref <- list(cbind(key("all_plots"), detector = "reference", sc_reference_counts(
    j$region_stems$E, j$region_stems$N,
    abs(j$region_stems$E - j$cx) <= j$ph & abs(j$region_stems$N - j$cy) <= j$ph, RMIN, RMAX)))
  if (!is.null(j$bundle)) {
    refs <- j$bundle$references[j$bundle$references$reference_selected, , drop = FALSE]
    ref[[2]] <- cbind(key("censused"), detector = "reference",
                      sc_reference_counts(refs$E, refs$N, rep(TRUE, nrow(refs)), RMIN, RMAX))
  }
  one_scope <- function(scope, arm, det, sc, in_reg, focus) {
    matched <- seq_len(nrow(det)) %in% attr(sc, "pairs")$det
    if (any(matched & !in_reg)) stop("A matched detection lies outside the scoring region")
    dr <- det[in_reg, , drop = FALSE]
    res <- lapply(CHMS, function(m) sc_cell(dr, focus[in_reg], matched[in_reg], H[[m]], THR,
                                             RMIN, RMAX, SUB_GAP))
    names(res) <- CHMS
    tp_core <- if (scope == "censused") sc$tp_core else
      if (sc$n_det > 0) round(sc$precision * sc$n_det) else 0
    k <- res$p2r$counts[1, ]
    if (k$n_det != sc$n_det || k$TP != sc$TP || k$tp_core != tp_core)
      stop(sprintf("%s %s %s: counted detections differ from the score", scope, j$pid, arm))
    cells[[length(cells) + 1]] <<- do.call(rbind, lapply(CHMS, function(m)
      cbind(key(scope), detector = arm, chm = m, n_ref = sc$n_ref, res[[m]]$counts)))
    p <- res$p2r$pairs
    if (nrow(p)) {
      q <- res$pitfree$pairs
      p <- data.frame(key(scope)[rep(1, nrow(p)), ], detector = arm,
                      x_i = dr$x[p$i], y_i = dr$y[p$i], x_j = dr$x[p$j], y_j = dr$y[p$j],
                      p[c("dist", "focus_i", "focus_j", "matched_i", "matched_j", "z_i", "z_j")],
                      gap_i_p2r = p$gap_i, gap_j_p2r = p$gap_j, lower_top_p2r = p$lower_top,
                      depth_p2r = p$depth, gap_i_pitfree = q$gap_i, gap_j_pitfree = q$gap_j,
                      lower_top_pitfree = q$lower_top, depth_pitfree = q$depth,
                      stringsAsFactors = FALSE)
      pairs[[length(pairs) + 1]] <<- p
    }
    scores[[length(scores) + 1]] <<- data.frame(key(scope), detector = arm,
      source = attr(det, "source"), n_ref = sc$n_ref, n_det = sc$n_det, TP = sc$TP,
      tp_core = tp_core, stringsAsFactors = FALSE)
  }
  for (arm in ARMS) {
    det <- suppressWarnings(census_cell_detections(j$nd, arm, j$site, j$pid, NA, j$root, native))
    if (is.null(det)) { missing <- c(missing, arm); next }
    src <- attr(det, "source")
    det <- data.frame(x = det$x, y = det$y, z = det$z)
    attr(det, "source") <- src
    # all_plots: paper_sensitivity.R's baseline matching in the nominal core.
    sc <- score_plot(j$stems, det, tol_xy = TOL, core_cx = j$cx, core_cy = j$cy,
                     core_half = j$ph, return_pairs = TRUE)
    one_scope("all_plots", arm, det, sc,
              abs(det$x - j$cx) <= j$ph + TOL & abs(det$y - j$cy) <= j$ph + TOL,
              abs(det$x - j$cx) <= j$ph & abs(det$y - j$cy) <= j$ph)
    # censused: the censused scorer's matching inside the admitted interior.
    if (!is.null(j$bundle)) {
      core <- j$bundle$core
      s <- score_neon_support(j$bundle, det, det_epsg = j$epsg, tol_xy = TOL, return_pairs = TRUE)
      one_scope("censused", arm, det, s,
                neon_support_inside(det$x, det$y, sf::st_buffer(core, TOL)),
                neon_support_inside(det$x, det$y, core))
    }
  }
  list(cells = do.call(rbind, cells), pairs = if (length(pairs)) do.call(rbind, pairs),
       scores = do.call(rbind, scores), reference = do.call(rbind, ref),
       missing = if (length(missing)) data.frame(site = j$site, plot = j$pid, detector = missing))
}
t0 <- Sys.time()
res <- plot_lapply(jobs, function(j) tryCatch(run_job(j), error = function(e)
  structure(list(msg = conditionMessage(e), plot = j$pid), class = "sc_failed")),
  mc.cores = CORES)
failed <- Filter(function(r) inherits(r, "sc_failed"), res)
if (length(failed)) stop(length(failed), " plots failed; first ", failed[[1]]$plot, ": ", failed[[1]]$msg)
cat(sprintf("phase 2: %d plots in %.1f min\n", length(res), as.numeric(Sys.time() - t0, units = "mins")))
bind <- function(k) as.data.frame(rbindlist(lapply(res, `[[`, k), fill = TRUE))
cells <- bind("cells"); pairs <- bind("pairs"); scores <- bind("scores")
reference <- bind("reference"); missing <- bind("missing")

## ---- checks --------------------------------------------------------------------------
chk <- character()
note <- function(...) { chk <<- c(chk, sprintf(...)); cat(sprintf(...), "\n") }
fail <- FALSE
note("Split-crown diagnostic checks")
note("arms: %s; sites: %s; plots: %d (censused: %d)", paste(ARMS, collapse = ","),
     paste(SITES, collapse = ","), length(unique(paste(scores$site, scores$plot))),
     length(unique(paste(scores$site, scores$plot)[scores$scope == "censused"])))
if (nrow(missing)) {
  note("missing detections: %d cells (%s)", nrow(missing),
       paste(utils::head(paste(missing$plot, missing$detector), 10), collapse = ", "))
  fail <- TRUE
}
# A: the arms' own results.
own <- do.call(rbind, lapply(ARMS, function(arm) {
  a <- MT_ARMS[MT_ARMS$arm == arm, ]
  do.call(rbind, lapply(SITES, function(site) {
    f <- file.path(d, "neon", site, a$file)
    if (!file.exists(f)) return(NULL)
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x <- x[x$detector == a$detector & x$rung == "native", , drop = FALSE]
    if (!nrow(x)) return(NULL)
    data.frame(site = site, plot = x$plot, detector = arm, own_n_ref = x$n_ref,
               own_n_det = x$n_det, own_TP = x$TP, stringsAsFactors = FALSE)
  }))
}))
ca <- merge(scores[scores$scope == "all_plots", ], own, by = c("site", "plot", "detector"), all.x = TRUE)
bad_a <- ca[is.na(ca$own_TP) | ca$n_ref != ca$own_n_ref | ca$n_det != ca$own_n_det |
              ca$TP != ca$own_TP, , drop = FALSE]
note("A. all_plots counts against the arms' own results: %d cells, %d differ", nrow(ca), nrow(bad_a))
if (nrow(bad_a)) fail <- TRUE
# B: the committed censused scores.
cs <- do.call(rbind, lapply(CENSUS_SCORES, function(dd) {
  f <- file.path(dd, "census_support_scores.csv")
  if (!file.exists(f)) return(NULL)
  x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  x[x$rung == "native", c("site", "plot", "detector", "n_ref", "n_det", "TP", "tp_core")]
}))
cs <- unique(cs[cs$site %in% SITES & cs$detector %in% ARMS, , drop = FALSE])
if (!nrow(cs) || anyDuplicated(cs[c("site", "plot", "detector")])) {
  note("B. censused scores missing or inconsistent across %s", paste(basename(CENSUS_SCORES), collapse = ", "))
  fail <- TRUE
} else {
  names(cs)[4:7] <- paste0("cs_", names(cs)[4:7])
  cb <- merge(scores[scores$scope == "censused", ], cs, by = c("site", "plot", "detector"), all.x = TRUE)
  bad_b <- cb[is.na(cb$cs_TP) | cb$n_ref != cb$cs_n_ref | cb$n_det != cb$cs_n_det |
                cb$TP != cb$cs_TP | cb$tp_core != cb$cs_tp_core, , drop = FALSE]
  unscored <- cs[!paste(cs$site, cs$plot, cs$detector) %in%
                   paste(cb$site, cb$plot, cb$detector), , drop = FALSE]
  note("B. censused counts against the committed censused scores: %d cells, %d differ, %d committed cells not scored",
       nrow(cb), nrow(bad_b), nrow(unscored))
  if (nrow(bad_b) || nrow(unscored)) fail <- TRUE
}
# C: equal support.
for (sc in c("all_plots", "censused")) {
  x <- scores[scores$scope == sc, ]
  per <- split(paste(x$site, x$plot), x$detector)
  common <- Reduce(intersect, per)
  note("C. %s: %d plots for every arm (per arm %s)", sc, length(common),
       paste(sprintf("%s %d", names(per), lengths(per)), collapse = ", "))
  if (any(lengths(per) != length(common)) || !setequal(names(per), ARMS)) fail <- TRUE
}
writeLines(chk, outf("checks.txt"))
if (fail) stop("A check failed; see ", outf("checks.txt"))

## ---- per-cell outputs ------------------------------------------------------------------
ord <- function(x, cols) x[do.call(order, unname(as.list(x[cols]))), , drop = FALSE]
cells <- ord(cells, c("scope", "site", "plot", "detector", "chm", "threshold"))
write.csv(cells, outf("cells.csv"), row.names = FALSE)
pairs <- ord(pairs, c("scope", "site", "plot", "detector", "x_i", "y_i", "x_j", "y_j"))
num <- vapply(pairs, is.numeric, TRUE)
pairs[num] <- lapply(pairs[num], function(v) round(v, 4))
write.csv(pairs, outf("pairs.csv"), row.names = FALSE)

## ---- pooling with paired plot resamples ------------------------------------------------
COUNTS <- c("n_det", "n_close", "n_near", "TP", "tp_core", "n_fp", "n_pairs", "n_pairs_valid",
            "n_pairs_novalley", "n_pairs_novalley_sub", "n_split_any", "n_split",
            "n_split_surface", "n_split_parents", "n_matched_pairs", "n_matched_pairs_novalley")
RATIOS <- list(close_rate = c("n_close", "n_det"), near_rate = c("n_near", "n_det"),
               novalley_share = c("n_pairs_novalley", "n_pairs_valid"),
               novalley_sub_share = c("n_pairs_novalley_sub", "n_pairs_novalley"),
               split_any_per_tp = c("n_split_any", "TP"), split_per_tp = c("n_split", "TP"),
               split_surface_per_tp = c("n_split_surface", "TP"),
               split_parent_share = c("n_split_parents", "TP"),
               split_share_of_fp = c("n_split", "n_fp"),
               onecrown_matched_pairs_per_tp = c("n_matched_pairs_novalley", "TP"),
               matched_pairs_per_tp = c("n_matched_pairs", "TP"),
               det_per_tp = c("n_det", "TP"))
pooled <- list(); leads <- list(); surplus <- list(); refpool <- list(); lead_draws <- list()
for (sc in c("all_plots", "censused")) {
  x <- cells[cells$scope == sc, , drop = FALSE]
  W <- mt_plot_weights(x$site, x$plot, MT_N_BOOT, MT_SEED)
  b <- sc_boot(x, W, c("detector", "chm", "threshold"), COUNTS)
  k <- b$key
  for (nm in names(RATIOS)) {
    r <- sc_ratio(b, RATIOS[[nm]][1], RATIOS[[nm]][2])
    pooled[[length(pooled) + 1]] <- cbind(
      data.frame(scope = sc, k, n_plots = nrow(W), metric = nm, numerator = b$est[[RATIOS[[nm]][1]]],
                 denominator = b$est[[RATIOS[[nm]][2]]], estimate = unname(r$e), stringsAsFactors = FALSE),
      do.call(rbind, lapply(seq_along(b$groups), function(i) mt_interval(r$d[, i]))))
    for (i in which(k$detector != BASE)) {
      i0 <- which(k$detector == BASE & k$chm == k$chm[i] & k$threshold == k$threshold[i])
      leads[[length(leads) + 1]] <- cbind(
        data.frame(scope = sc, k[i, ], metric = nm, estimate = unname(r$e[i] - r$e[i0]),
                   stringsAsFactors = FALSE), mt_interval(r$d[, i] - r$d[, i0]))
      if (nm %in% c("split_per_tp", "split_any_per_tp"))
        lead_draws[[length(lead_draws) + 1]] <- list(
          key = data.frame(scope = sc, k[i, ], metric = nm, stringsAsFactors = FALSE),
          e = unname(r$e[i] - r$e[i0]), d = r$d[, i] - r$d[, i0])
    }
  }
  # The detection surplus over CHM-VWF and the part of it that split-crown
  # candidates account for: surplus (n_det - n_det_base) / n_det_base, split
  # excess (n_split - n_split_base) / n_det_base, and their ratio.
  for (i in which(k$detector != BASE)) {
    i0 <- which(k$detector == BASE & k$chm == k$chm[i] & k$threshold == k$threshold[i])
    for (what in c("n_split", "n_split_any")) {
      E <- b$est; D <- b$draws
      sp_e <- (E$n_det[i] - E$n_det[i0]) / E$n_det[i0]
      sp_d <- (D$n_det[, i] - D$n_det[, i0]) / D$n_det[, i0]
      ex_e <- (E[[what]][i] - E[[what]][i0]) / E$n_det[i0]
      ex_d <- (D[[what]][, i] - D[[what]][, i0]) / D$n_det[, i0]
      sh_d <- (D[[what]][, i] - D[[what]][, i0]) / (D$n_det[, i] - D$n_det[, i0])
      sh_d[!is.finite(sh_d)] <- NA
      mk <- function(m, e, dd) cbind(data.frame(scope = sc, k[i, ], count = what, metric = m,
                                                estimate = unname(e), stringsAsFactors = FALSE),
                                     mt_interval(dd))
      surplus[[length(surplus) + 1]] <- rbind(
        mk("detection_surplus", sp_e, sp_d), mk("split_excess", ex_e, ex_d),
        mk("split_share_of_surplus", (E[[what]][i] - E[[what]][i0]) / (E$n_det[i] - E$n_det[i0]), sh_d))
    }
  }
  rf <- reference[reference$scope == sc, , drop = FALSE]
  br <- sc_boot(rf, W, "detector", c("n_det", "n_close", "n_near"))
  for (nm in c("close_rate", "near_rate")) {
    r <- sc_ratio(br, RATIOS[[nm]][1], RATIOS[[nm]][2])
    refpool[[length(refpool) + 1]] <- cbind(data.frame(
      scope = sc, detector = "reference", n_plots = nrow(W), metric = nm,
      numerator = br$est[[RATIOS[[nm]][1]]], denominator = br$est[[RATIOS[[nm]][2]]],
      estimate = unname(r$e), stringsAsFactors = FALSE), mt_interval(r$d[, 1]))
  }
}
pooled <- do.call(rbind, pooled); leads <- do.call(rbind, leads)
surplus <- do.call(rbind, surplus); refpool <- do.call(rbind, refpool)
write.csv(pooled, outf("pooled.csv"), row.names = FALSE)
write.csv(leads, outf("leads.csv"), row.names = FALSE)
write.csv(surplus, outf("surplus.csv"), row.names = FALSE)
write.csv(refpool, outf("reference.csv"), row.names = FALSE)

## ---- calibration on the chance-correction simulation's plots ---------------------------
# The simulation's plots at 240 trees/ha with every tree in the reference
# (simulate_chance_correction.R's seeds), the baseline detector (s 0.45, f 0.45)
# and its split crowns at rates 0.5 and 0.8, matched by the same greedy 4 m
# matcher in the 40 m core. Without a canopy model every close pair counts as one
# crown, so split-crown candidates are the distance-only count; the split pieces
# the detector placed are known, so the share it flags is reported too.
simpool <- NULL
if (SIM) {
  SIM_RATES <- c(0, 0.5, 0.8)
  sim_one <- function(pt, i) {
    pid <- cs_plot_id(240, i, pt)
    pl <- cs_plot(240, cs_seed(seed_for("chance_sim", pid, "plot"), 0), pattern = pt)
    st <- cs_reference(pl, "complete")
    if (!nrow(st)) return(NULL)
    n_base <- nrow(cs_detector(pl, 0.45, 0.45))
    do.call(rbind, lapply(SIM_RATES, function(rate) {
      det <- cs_detector(pl, 0.45, 0.45, mode = "split", rate = rate)
      sc <- score_plot(st, det[c("x", "y", "z")], tol_xy = TOL, core_cx = 0, core_cy = 0,
                       core_half = CS_PH, return_pairs = TRUE)
      in_reg <- abs(det$x) <= CS_PH + TOL & abs(det$y) <= CS_PH + TOL
      focus <- abs(det$x) <= CS_PH & abs(det$y) <= CS_PH
      matched <- seq_len(nrow(det)) %in% attr(sc, "pairs")$det
      dr <- det[in_reg, , drop = FALSE]
      cl <- sc_cell(dr, focus[in_reg], matched[in_reg], NULL,
                    data.frame(threshold = "distance_only", type = "abs", value = Inf),
                    RMIN, RMAX, SUB_GAP)
      piece <- seq_len(nrow(det)) > n_base             # the split pieces
      pr <- cl$pairs
      ci <- pr$focus_i & !pr$matched_i & pr$matched_j
      cj <- pr$focus_j & !pr$matched_j & pr$matched_i
      cand <- unique(which(in_reg)[c(pr$i[ci], pr$j[cj])])
      data.frame(site = pt, plot = pid, rate = rate, cl$counts,
                 n_piece = sum(piece & focus), n_piece_flagged = sum(piece & focus & seq_len(nrow(det)) %in% cand),
                 n_piece_matched = sum(piece & focus & matched), stringsAsFactors = FALSE)
    }))
  }
  sim <- do.call(rbind, lapply(names(CS_PATTERNS), function(pt)
    do.call(rbind, lapply(seq_len(SIM_N), function(i) sim_one(pt, i)))))
  simpool <- do.call(rbind, lapply(names(CS_PATTERNS), function(pt) {
    x <- sim[sim$site == pt, , drop = FALSE]
    W <- mt_plot_weights(x$site, x$plot, MT_N_BOOT, MT_SEED)
    b <- sc_boot(x, W, "rate", c(COUNTS, "n_piece", "n_piece_flagged", "n_piece_matched"))
    rat <- c(RATIOS[c("close_rate", "split_any_per_tp", "split_parent_share",
                      "matched_pairs_per_tp", "det_per_tp")],
             list(piece_flagged_share = c("n_piece_flagged", "n_piece"),
                  piece_matched_share = c("n_piece_matched", "n_piece")))
    i0 <- which(b$key$rate == 0)
    do.call(rbind, lapply(names(rat), function(nm) {
      r <- sc_ratio(b, rat[[nm]][1], rat[[nm]][2])
      do.call(rbind, lapply(seq_along(b$groups), function(i) cbind(data.frame(
        pattern = pt, rate = b$key$rate[i], n_plots = nrow(W), metric = nm, estimate = unname(r$e[i]),
        minus_rate0 = unname(r$e[i] - r$e[i0]), stringsAsFactors = FALSE),
        mt_interval(r$d[, i]), setNames(mt_interval(r$d[, i] - r$d[, i0])[1:2],
                                        c("minus_rate0_lower", "minus_rate0_upper")))))
    }))
  }))
  write.csv(simpool, outf("simulation.csv"), row.names = FALSE)
  # Equivalent split rate: an arm's lead over CHM-VWF in candidates per
  # detected tree divided by the simulation's response of the same count to the
  # split rate in the loose clusters (the stand nearest the benchmark's stems),
  # the least-squares slope through the origin of its increments at rates 0.5
  # and 0.8. The slope's Monte Carlo error is not propagated.
  inc <- simpool[simpool$pattern == "clustered_8m" & simpool$metric == "split_any_per_tp" &
                   simpool$rate > 0, ]
  SLOPE <- sum(inc$rate * inc$minus_rate0) / sum(inc$rate^2)
  equivalent <- do.call(rbind, lapply(lead_draws, function(x) {
    if (x$key$metric == "split_any_per_tp" && !(x$key$chm == "p2r" && x$key$threshold == THR$threshold[1]))
      return(NULL)                                   # distance only: one row per arm
    cbind(x$key, slope = SLOPE, lead = x$e, setNames(mt_interval(x$d)[1:2], c("lead_lower", "lead_upper")),
          equivalent_rate = x$e / SLOPE,
          setNames(mt_interval(x$d / SLOPE)[1:2], c("equivalent_lower", "equivalent_upper")))
  }))
  write.csv(equivalent, outf("equivalent.csv"), row.names = FALSE)
}

## ---- markdown tables -------------------------------------------------------------------
lab <- function(a) ifelse(a %in% names(CN_LABELS), CN_LABELS[a], a)
f3 <- function(v) ifelse(is.na(v), "NA", sprintf("%.3f", v))
s3 <- function(v) ifelse(is.na(v), "NA", sprintf("%+.3f", v))
ci <- function(e, lo, hi, s = f3) sprintf("%s [%s, %s]", s(e), s(lo), s(hi))
get <- function(tab, ...) {
  f <- list(...); x <- tab
  for (n in names(f)) x <- x[x[[n]] == f[[n]], , drop = FALSE]
  if (nrow(x) != 1) stop("Expected one row for ", paste(names(f), f, collapse = " "))
  x
}
HEAD_CHM <- "p2r"; HEAD_THR <- THR$threshold[THR$type == "abs" & THR$value == 1][1]
if (is.na(HEAD_THR)) HEAD_THR <- THR$threshold[1]
md <- c("# Split-crown diagnostic tables", "",
        sprintf("Native density, %s; matching radius %g m; close pairs %g-%g m apart.",
                paste(SITES, collapse = ", "), TOL, RMIN, RMAX),
        "Pooled by summed counts; 95% paired plot-bootstrap intervals (1,000 resamples).", "")
arms_order <- ARMS
for (sc in c("all_plots", "censused")) {
  np <- unique(pooled$n_plots[pooled$scope == sc])
  md <- c(md, sprintf("## %s (%d plots)", if (sc == "all_plots") "All scored plots, nominal cores" else
    "Censused subplots", np), "",
    "### Close pairs", "",
    "| Arm | Detections | Close-pair rate | Lead over CHM-VWF | Closer than 1.5 m |",
    "| --- | --- | --- | --- | --- |")
  for (a in arms_order) {
    p <- get(pooled, scope = sc, detector = a, chm = HEAD_CHM, threshold = HEAD_THR, metric = "close_rate")
    nr <- get(pooled, scope = sc, detector = a, chm = HEAD_CHM, threshold = HEAD_THR, metric = "near_rate")
    l <- if (a == BASE) "—" else {
      q <- get(leads, scope = sc, detector = a, chm = HEAD_CHM, threshold = HEAD_THR, metric = "close_rate")
      ci(q$estimate, q$lower, q$upper, s3) }
    md <- c(md, sprintf("| %s | %d | %s | %s | %s |", lab(a), as.integer(p$denominator),
                        ci(p$estimate, p$lower, p$upper), l, f3(nr$estimate)))
  }
  rp <- get(refpool, scope = sc, metric = "close_rate"); rn <- get(refpool, scope = sc, metric = "near_rate")
  md <- c(md, sprintf("| Reference stems | %d | %s | — | %s |", as.integer(rp$denominator),
                      ci(rp$estimate, rp$lower, rp$upper), f3(rn$estimate)), "")
  for (m in CHMS) {
    md <- c(md, sprintf("### No-valley share of close pairs, %s canopy model", m), "",
            paste0("| Arm | Close pairs | ", paste(THR$threshold, collapse = " | "),
                   " | Beneath canopy (", HEAD_THR, ") |"),
            paste0("| --- | --- | ", paste(rep("---", nrow(THR) + 1), collapse = " | "), " |"))
    for (a in arms_order) {
      v <- vapply(THR$threshold, function(t) {
        p <- get(pooled, scope = sc, detector = a, chm = m, threshold = t, metric = "novalley_share")
        if (t == HEAD_THR) ci(p$estimate, p$lower, p$upper) else f3(p$estimate) }, "")
      sub <- get(pooled, scope = sc, detector = a, chm = m, threshold = HEAD_THR, metric = "novalley_sub_share")
      np2 <- get(pooled, scope = sc, detector = a, chm = m, threshold = HEAD_THR, metric = "novalley_share")
      md <- c(md, sprintf("| %s | %d | %s | %s |", lab(a), as.integer(np2$denominator),
                          paste(v, collapse = " | "), f3(sub$estimate)))
    }
    md <- c(md, "")
  }
  for (m in CHMS) {
    md <- c(md, sprintf("### Split-crown candidates per detected tree, %s canopy model", m), "",
            paste0("| Arm | Detected trees (TP) | Distance only | ",
                   paste(THR$threshold, collapse = " | "), " | At the surface (", HEAD_THR,
                   ") | Trees with a candidate (", HEAD_THR, ") | Lead over CHM-VWF (", HEAD_THR,
                   ") | Share of false positives (", HEAD_THR, ") |"),
            paste0("| --- | --- | --- | ", paste(rep("---", nrow(THR) + 4), collapse = " | "), " |"))
    for (a in arms_order) {
      g <- function(met, t = HEAD_THR) get(pooled, scope = sc, detector = a, chm = m, threshold = t,
                                           metric = met)
      any_ <- g("split_any_per_tp")
      v <- vapply(THR$threshold, function(t) {
        p <- g("split_per_tp", t)
        if (t == HEAD_THR) ci(p$estimate, p$lower, p$upper) else f3(p$estimate) }, "")
      l <- if (a == BASE) "—" else {
        q <- get(leads, scope = sc, detector = a, chm = m, threshold = HEAD_THR, metric = "split_per_tp")
        ci(q$estimate, q$lower, q$upper, s3) }
      md <- c(md, sprintf("| %s | %d | %s | %s | %s | %s | %s | %s |", lab(a), as.integer(any_$denominator),
                          ci(any_$estimate, any_$lower, any_$upper), paste(v, collapse = " | "),
                          f3(g("split_surface_per_tp")$estimate), f3(g("split_parent_share")$estimate),
                          l, f3(g("split_share_of_fp")$estimate)))
    }
    md <- c(md, "")
  }
  md <- c(md, sprintf("### Matched pairs 1.5-4 m apart on one crown, per detected tree (%s)", HEAD_THR), "",
          "| Arm | All matched pairs | Lead over CHM-VWF | No valley, p2r | Lead over CHM-VWF | No valley, pitfree | Lead over CHM-VWF |",
          "| --- | --- | --- | --- | --- | --- | --- |")
  for (a in arms_order) {
    row <- unlist(lapply(list(c("p2r", "matched_pairs_per_tp"), c("p2r", "onecrown_matched_pairs_per_tp"),
                              c("pitfree", "onecrown_matched_pairs_per_tp")), function(cm) {
      p <- get(pooled, scope = sc, detector = a, chm = cm[1], threshold = HEAD_THR, metric = cm[2])
      l <- if (a == BASE) "—" else {
        q <- get(leads, scope = sc, detector = a, chm = cm[1], threshold = HEAD_THR, metric = cm[2])
        ci(q$estimate, q$lower, q$upper, s3) }
      c(ci(p$estimate, p$lower, p$upper), l) }))
    md <- c(md, sprintf("| %s | %s |", lab(a), paste(row, collapse = " | ")))
  }
  md <- c(md, "")
  md <- c(md, sprintf("### Detection surplus over CHM-VWF and split-crown candidates (%s, %s)",
                      HEAD_CHM, HEAD_THR), "",
          "| Arm | Detection surplus | Split excess, no valley | Share of surplus, no valley | Split excess, distance only | Share of surplus, distance only |",
          "| --- | --- | --- | --- | --- | --- |")
  for (a in setdiff(arms_order, BASE)) {
    g <- function(cnt, met) get(surplus, scope = sc, detector = a, chm = HEAD_CHM, threshold = HEAD_THR,
                                count = cnt, metric = met)
    sp <- g("n_split", "detection_surplus")
    cells_ <- c(ci(sp$estimate, sp$lower, sp$upper, s3),
                unlist(lapply(c("n_split", "n_split_any"), function(cnt) {
                  e <- g(cnt, "split_excess"); s <- g(cnt, "split_share_of_surplus")
                  c(ci(e$estimate, e$lower, e$upper, s3), ci(s$estimate, s$lower, s$upper, s3)) })))
    md <- c(md, sprintf("| %s | %s |", lab(a), paste(cells_, collapse = " | ")))
  }
  md <- c(md, "")
}
if (!is.null(simpool)) {
  md <- c(md, "## Calibration on the chance-correction simulation's plots", "",
          sprintf("240 trees/ha, complete reference, %d plots per pattern; baseline s 0.45, f 0.45; distance only.", SIM_N), "",
          "| Pattern | Split rate | Detections per detected tree | Close-pair rate | Candidates per detected tree | Minus rate 0 | Trees with a candidate | Matched pairs per detected tree | Minus rate 0 | Split pieces that are candidates | Split pieces matched |",
          "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
  for (pt in names(CS_PATTERNS)) for (rt in c(0, 0.5, 0.8)) {
    g <- function(m) simpool[simpool$pattern == pt & simpool$rate == rt & simpool$metric == m, ]
    cr <- g("close_rate"); sa <- g("split_any_per_tp"); sp <- g("split_parent_share")
    mp <- g("matched_pairs_per_tp"); dt <- g("det_per_tp")
    pf <- g("piece_flagged_share"); pm <- g("piece_matched_share")
    inc <- function(x) if (rt == 0) "—" else ci(x$minus_rate0, x$minus_rate0_lower, x$minus_rate0_upper, s3)
    md <- c(md, sprintf("| %s | %.1f | %s | %s | %s | %s | %s | %s | %s | %s | %s |", pt, rt, f3(dt$estimate),
                        f3(cr$estimate), ci(sa$estimate, sa$lower, sa$upper), inc(sa), f3(sp$estimate),
                        f3(mp$estimate), inc(mp), if (rt == 0) "—" else f3(pf$estimate),
                        if (rt == 0) "—" else f3(pm$estimate)))
  }
  md <- c(md, "")
  TOP_THR <- THR$threshold[THR$type == "abs"][which.max(THR$value[THR$type == "abs"])]
  sets <- list(c("split_any_per_tp", "p2r", THR$threshold[1], "Distance only"),
               c("split_per_tp", "p2r", HEAD_THR, paste("No valley, p2r", HEAD_THR)),
               c("split_per_tp", "pitfree", HEAD_THR, paste("No valley, pitfree", HEAD_THR)),
               c("split_per_tp", "pitfree", TOP_THR, paste("No valley, pitfree", TOP_THR)))
  md <- c(md, sprintf(paste("## Equivalent split rate: lead over CHM-VWF in candidates per detected tree,",
                            "divided by the loose clusters' response (%.3f per unit split rate)"), SLOPE), "")
  for (sc in c("all_plots", "censused")) {
    md <- c(md, sprintf("### %s", if (sc == "all_plots") "All scored plots" else "Censused subplots"), "",
            paste0("| Arm | ", paste(vapply(sets, `[`, "", 4), collapse = " | "), " |"),
            paste0("| --- | ", paste(rep("---", length(sets)), collapse = " | "), " |"))
    for (a in setdiff(arms_order, BASE)) {
      v <- vapply(sets, function(s) {
        x <- get(equivalent, scope = sc, detector = a, metric = s[1], chm = s[2], threshold = s[3])
        sprintf("%s; rate %s", ci(x$lead, x$lead_lower, x$lead_upper, s3),
                ci(x$equivalent_rate, x$equivalent_lower, x$equivalent_upper, f3)) }, "")
      md <- c(md, sprintf("| %s | %s |", lab(a), paste(v, collapse = " | ")))
    }
    md <- c(md, "")
  }
}
writeLines(md, outf("tables.md"))
cat(sprintf("wrote %s and split_crowns_*.csv\n", outf("tables.md")))
