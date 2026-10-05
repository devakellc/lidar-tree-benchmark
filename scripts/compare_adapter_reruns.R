#!/usr/bin/env Rscript
# Before/after comparison for the corrected ForestFormer3D and TreeisoNet
# adapters. The June 2026 NEON artifacts are re-scored on the SAME declared
# population, plots, frozen substrate and scorers as the re-runs, so what
# differs is the adapter (plus the models' run-to-run variability):
#   ForestFormer3D apex  -- June outer-cylinder native clouds vs re-run
#                           whole-scene native clouds: ff3d_collapse ->
#                           agl_guard(frozen native DTM) -> score_plot, pooled
#                           by summed counts on the plots both runs scored.
#   ForestFormer3D masks -- the same clouds through score_instances_iou.R's
#                           run_plot (Voronoi-on-stems proxy, native rung).
#   TreeisoNet crowns    -- June crown rows (pre-fix driver) vs re-run rows,
#                           paired by individualID: d_eq vs ninetyCrownDiameter
#                           and d_caliper vs maxCrownDiameter.
#   TreeisoNet apex      -- the treeLoc pass does not run treeOff; June rows are
#                           listed as reported, with the share of common cells
#                           whose apex count is unchanged.
#   TreeisoNet voxel     -- with VOXEL0=<job dir> (a native-rung re-run at the
#                           checkpoint's own voxel), the June native rows are
#                           compared with both re-run voxel settings, so an
#                           apex change is traced to the voxel, not the adapter.
# June persisted only native ForestFormer3D clouds; its rung-8 rows (historical
# all-mapped population) are reported separately and are not an equal set.
#   Rscript scripts/compare_adapter_reruns.R BEFORE=<job dir> AFTER=<job dir>
#     [SITES=SJER,SOAP,TEAK] [LADDER_SITES=SJER,SOAP,TEAK,WREF,ABBY] [POP=adopted]
#     [VOXEL0=<job dir>] [OUT=<AFTER>/neon/adapter_before_after]
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(lidR); library(data.table) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R")); source(.find("model_bench_lib.R"))
source(.find("io_bridge.R"))

args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$BEFORE) || is.null(A$AFTER)) stop("BEFORE= and AFTER= job dirs are required")
BEFORE <- normalizePath(A$BEFORE); AFTER <- normalizePath(A$AFTER)
SITES <- strsplit(if (is.null(A$SITES)) "SJER,SOAP,TEAK" else A$SITES, ",")[[1]]
VOXEL0 <- if (is.null(A$VOXEL0)) NULL else normalizePath(A$VOXEL0)
OUT <- if (is.null(A$OUT)) file.path(AFTER, "neon", "adapter_before_after") else A$OUT
TOL <- 4; MERGE_TOL <- 2
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# The IoU/PQ scorer's functions, pointed at both clouds of each plot.
iou <- new.env()
sys.source(.find("score_instances_iou.R"), envir = iou, keep.source = FALSE)
iou$RUNGS <- "native"; iou$APEX_PROXY <- FALSE; iou$MINTREES <- 1L

site_inputs <- function(site) {
  nd <- file.path(AFTER, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  fz <- frozen_scope(AFTER, site, A, gt)
  list(nd = nd, gt = fz$gt, pc = pc, fz = fz)
}

score_ff3d <- function(cloud, stems, ci, dtm) {
  det <- ff3d_collapse(cloud, merge_tol = MERGE_TOL)
  if (is.null(det)) stop("Unreadable ForestFormer3D cloud: ", cloud)
  det <- agl_guard(det, dtm)
  if (is.null(det)) stop("ForestFormer3D apexes fall off the DTM: ", cloud)
  ph <- plot_half(ci$plotType)
  score_plot(stems, det, tol_xy = TOL, core_cx = ci$easting, core_cy = ci$northing,
             core_half = ph)
}

pooled_row <- function(df, label) {
  if (is.null(df) || !nrow(df)) return(NULL)
  p <- pool(df)
  data.frame(run = label, plots = p$n_plots, n_ref = p$n_ref, n_det = p$n_det, TP = p$TP,
             recall = p$recall, precision = p$precision, F1 = p$F1,
             rec_overstory = with(df, (sum(round(rec_dominant * n_dominant), na.rm = TRUE) +
               sum(round(rec_codominant * n_codominant), na.rm = TRUE)) /
               (sum(n_dominant) + sum(n_codominant))),
             rec_understory = p$rec_understory)
}

ff3d_apex <- list(); ff3d_mask <- list(); ti_apex <- list(); ti_crown <- list()
ti_voxel <- list()
for (site in SITES) {
  s <- site_inputs(site)
  before_dir <- file.path(BEFORE, "neon", site, "forestformer3d_instances")
  after_dir <- file.path(s$nd, "forestformer3d_instances")
  if (dir.exists(after_dir)) frozen_stamp_check(after_dir, s$fz$root)
  plots <- s$fz$plots[file.exists(file.path(before_dir, paste0(s$fz$plots, "_native.laz"))) &
                      file.exists(file.path(after_dir, paste0(s$fz$plots, "_native.laz")))]
  rows <- list(before = list(), after = list())
  for (pid in plots) {
    ci <- s$pc[s$pc$plotID == pid, ][1, ]; ph <- plot_half(ci$plotType)
    stems <- s$gt[s$gt$plotID == pid & abs(s$gt$E - ci$easting) <= ph &
                    abs(s$gt$N - ci$northing) <= ph, , drop = FALSE]
    cell <- frozen_clip(NULL, site, pid, NA, ci$easting, ci$northing, ph, s$fz$root)
    for (run in c("before", "after")) {
      dir <- if (run == "before") before_dir else after_dir
      sc <- score_ff3d(file.path(dir, paste0(pid, "_native.laz")), stems, ci, cell$dtm)
      rows[[run]][[pid]] <- cbind(data.frame(site = site, plot = pid, rung = "native"), sc)
    }
  }
  for (run in names(rows)) {
    r <- pooled_row(do.call(rbind, rows[[run]]),
                    if (run == "before") "June outer cylinders" else "Whole scene re-run")
    if (!is.null(r)) ff3d_apex[[length(ff3d_apex) + 1]] <- cbind(site = site, r)
  }

  # Masks: the scorer's run_plot over both clouds of the same plots.
  if (length(plots)) {
    gt <- s$gt
    fc <- iou$field_crowns(site)
    gt$maxCrownDiameter <- if (is.null(gt$maxCrownDiameter)) NA_real_ else as.numeric(gt$maxCrownDiameter)
    m <- match(gt$individualID, fc$individualID)
    ok <- !is.na(m) & is.finite(fc$maxCrownDiameter[m])
    gt$maxCrownDiameter[ok] <- fc$maxCrownDiameter[m][ok]
    iou$MODELS <- list(
      june = list(dir = file.path("neon", site, "forestformer3d_instances"),
                  load = iou$load_ff3d_points, base = BEFORE),
      rerun = list(dir = file.path("neon", site, "forestformer3d_instances"),
                   load = iou$load_ff3d_points, base = AFTER))
    mask_rows <- lapply(names(iou$MODELS), function(mname) {
      saved <- iou$MODELS; iou$MODELS <- saved[mname]
      on.exit(iou$MODELS <- saved)
      do.call(rbind, lapply(plots, function(pid)
        iou$run_plot(site, pid, s$pc, gt, saved[[mname]]$base, s$fz$root, NULL)))
    })
    mr <- do.call(rbind, mask_rows)
    if (!is.null(mr) && nrow(mr)) for (mname in unique(mr$model)) {
      p <- pool_pq(mr[mr$model == mname, , drop = FALSE])
      ff3d_mask[[length(ff3d_mask) + 1]] <- data.frame(site = site,
        run = if (mname == "june") "June outer cylinders" else "Whole scene re-run",
        plots = length(unique(mr$plot[mr$model == mname])), n_ref = p$n_ref, n_pred = p$n_pred,
        TP = p$TP, precision = p$precision, recall = p$recall, F1 = p$F1, SQ = p$SQ,
        RQ = p$RQ, PQ = p$PQ, coverage = p$coverage)
    }
  }

  # TreeisoNet apex: June as reported vs re-run, with per-cell apex identity.
  bf <- file.path(BEFORE, "neon", site, "treeisonet_results.csv")
  af <- file.path(s$nd, "treeisonet_results.csv")
  if (file.exists(bf) && file.exists(af)) {
    b <- read.csv(bf, colClasses = c(rung = "character")); a <- read.csv(af, colClasses = c(rung = "character"))
    common <- merge(b[, c("plot", "rung", "n_apex")], a[, c("plot", "rung", "n_apex")],
                    by = c("plot", "rung"), suffixes = c("_june", "_rerun"))
    for (rg in c("native", "8", "4", "2", "1")) {
      bb <- b[b$rung == rg, ]; aa <- a[a$rung == rg, ]; cc <- common[common$rung == rg, ]
      if (!nrow(bb) && !nrow(aa)) next
      pb <- if (nrow(bb)) pool(bb) else NULL; pa <- if (nrow(aa)) pool(aa) else NULL
      ti_apex[[length(ti_apex) + 1]] <- data.frame(site = site, rung = rg,
        june_plots = nrow(bb), june_n_ref = if (nrow(bb)) pb$n_ref else NA,
        june_F1 = if (nrow(bb)) pb$F1 else NA,
        rerun_plots = nrow(aa), rerun_n_ref = if (nrow(aa)) pa$n_ref else NA,
        rerun_F1 = if (nrow(aa)) pa$F1 else NA,
        common_cells = nrow(cc), same_apex_count = sum(cc$n_apex_june == cc$n_apex_rerun))
    }
    # Native rung only: which re-run voxel reproduces the June apex counts.
    vf <- if (is.null(VOXEL0)) "" else file.path(VOXEL0, "neon", site, "treeisonet_results.csv")
    if (file.exists(vf)) {
      v <- read.csv(vf, colClasses = c(rung = "character"))
      runs <- list(june = b, voxel0 = v, configured = a)
      runs <- lapply(runs, function(x) x[x$rung == "native", , drop = FALSE])
      cells <- Reduce(intersect, lapply(runs, `[[`, "plot"))
      runs <- lapply(runs, function(x) x[match(cells, x$plot), , drop = FALSE])
      same <- function(x) sum(runs$june$n_apex == x$n_apex)
      for (run in names(runs)) {
        p <- pool(runs[[run]])
        ti_voxel[[length(ti_voxel) + 1]] <- data.frame(site = site, run = run,
          plots = length(cells), n_ref = p$n_ref, n_det = p$n_det, F1 = p$F1,
          same_apex_count_as_june = same(runs[[run]]))
      }
    }
  }

  # TreeisoNet crowns: paired by individualID on stems both runs matched.
  bc <- file.path(BEFORE, "neon", site, "treeisonet_crown_metrics.csv")
  ac <- file.path(s$nd, "treeisonet_crown_metrics.csv")
  if (file.exists(bc) && file.exists(ac)) {
    b <- read.csv(bc); a <- read.csv(ac)
    pr <- merge(b, a, by = "individualID", suffixes = c("_june", "_rerun"))
    rmse <- function(x, y) { ok <- is.finite(x) & is.finite(y); sqrt(mean((x[ok] - y[ok])^2)) }
    ti_crown[[length(ti_crown) + 1]] <- data.frame(site = site,
      june_matched = nrow(b), rerun_matched = nrow(a), paired = nrow(pr),
      june_rmse_eq = rmse(pr$d_eq_june, pr$field_ninetyCD_june),
      rerun_rmse_eq = rmse(pr$d_eq_rerun, pr$field_ninetyCD_rerun),
      june_rmse_caliper = rmse(pr$d_caliper_june, pr$field_maxCD_june),
      rerun_rmse_caliper = rmse(pr$d_caliper_rerun, pr$field_maxCD_rerun))
  }
}

# Re-run ladder on the declared population: ForestFormer3D and TreeisoNet on
# the cells both arms scored (equal_set_guard), pooled per site and rung and
# over all requested sites.
LADDER_SITES <- strsplit(if (is.null(A$LADDER_SITES)) "SJER,SOAP,TEAK,WREF,ABBY" else
  A$LADDER_SITES, ",")[[1]]
arm_rows <- do.call(rbind, lapply(LADDER_SITES, function(site) {
  nd <- file.path(AFTER, "neon", site)
  do.call(rbind, lapply(c(forestformer3d = "forestformer3d_results.csv",
                          treeisonet = "treeisonet_results.csv"), function(f) {
    path <- file.path(nd, f)
    if (!file.exists(path)) return(NULL)
    x <- read.csv(path, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x$site <- site
    x[, intersect(c("site", "plot", "rung", "detector", "n_ref", "n_det", "TP", "precision",
                    "recall", "F1", paste0(c("n_", "rec_"), rep(POOL_CLASSES, each = 2))),
                  names(x))]
  }))
}))
ladder <- list()
if (!is.null(arm_rows) && length(unique(arm_rows$detector)) == 2L) {
  eq <- equal_set_guard(arm_rows, c("forestformer3d", "treeisonet"))
  cat(sprintf("re-run ladder: %d equal-set cells, %d dropped (%s)\n",
              length(unique(paste(eq$site, eq$plot, eq$rung))), length(attr(eq, "dropped")),
              paste(head(attr(eq, "dropped"), 20), collapse = " ")))
  for (grp in c(LADDER_SITES, "all")) for (rg in c("native", "8", "4", "2", "1"))
    for (det in c("forestformer3d", "treeisonet")) {
      x <- eq[eq$detector == det & eq$rung == rg & (grp == "all" | eq$site == grp), , drop = FALSE]
      if (!nrow(x)) next
      p <- pool(x)
      ladder[[length(ladder) + 1]] <- data.frame(site = grp, rung = rg, detector = det,
        plots = p$n_plots, n_ref = p$n_ref, n_det = p$n_det, recall = p$recall,
        precision = p$precision, F1 = p$F1, rec_understory = p$rec_understory)
    }
}

tables <- list(ff3d_apex_before_after = ff3d_apex, ff3d_mask_before_after = ff3d_mask,
               rerun_ladder = ladder,
               treeisonet_apex_before_after = ti_apex,
               treeisonet_voxel_attribution = ti_voxel,
               treeisonet_crowns_before_after = ti_crown)
for (name in names(tables)) {
  x <- do.call(rbind, tables[[name]])
  if (is.null(x)) { cat(name, ": no rows\n"); next }
  write.csv(x, file.path(OUT, paste0(name, ".csv")), row.names = FALSE)
  cat("\n==", name, "\n"); print(x, row.names = FALSE, digits = 3)
}
