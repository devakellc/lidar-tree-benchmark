#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("sweep_lib.R")); source(.find("model_bench_lib.R")); source(.find("io_bridge.R"))
source(.find("census_support_lib.R"))
suppressMessages(library(lidR))

# Audit of the learned detectors' persisted outputs (no detector re-run):
#  (a) SegmentAnyTree and ForestFormer3D per rung: the share of core points
#      the model labels as tree (SegmentAnyTree's semantic head), the share
#      assigned to an instance, and points per core instance, which separates
#      a failure of the semantic features from a failure of instance grouping;
#  (b) the share of core apexes below 2 m for the learned detectors, which
#      carry no height floor on NEON, against CHM-VWF's 2 m floor;
#  (c) how many of CHM-VWF's and TreeisoNet's native false positives lie
#      within 4 m and 2 m of a mapped dead stem (DBH >= 10 cm, measured within
#      the four-year window), against their true positives and the live stems.
#   CLAUDE_JOB_DIR=<paper_runs> Rscript scripts/instance_audit.R [OUT=<dir>] [CORES=8]
# Writes <OUT>/instance_audit_{instances,apex_below2,dead_fp}.csv per plot and
# cell, and instance_audit_summary.csv pooled over the five sites; OUT
# defaults to $CLAUDE_JOB_DIR/sensitivity.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
d <- .job_dir(); CORES <- as.integer(if (is.null(A[["CORES"]])) 8 else A[["CORES"]])
OUT <- if (is.null(A[["OUT"]])) file.path(d, "sensitivity") else A[["OUT"]]
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
SITES <- c("SJER", "SOAP", "TEAK", "WREF", "ABBY"); RUNGS <- c("native", "8", "4", "2", "1")
CENSUS_INSTANCE_SOURCES$sam2point <- list(dir = "sam2point_instances", id = "sam2point", agl = FALSE)
rows_a <- list(); rows_b <- list(); rows_c <- list()
for (site in SITES) {
  nd <- file.path(d, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  fz <- frozen_scope(d, site, list(), gt)
  plots <- intersect(fz$plots, pc$plotID)
  res <- parallel::mclapply(plots, mc.cores = CORES, function(pid) {
    ci <- pc[pc$plotID == pid, ][1, ]; cx <- ci$easting; cy <- ci$northing; ph <- plot_half(ci$plotType)
    stems <- fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - cx) <= ph & abs(fz$gt$N - cy) <= ph, , drop = FALSE]
    dead <- gt[gt$plotID == pid & !is.na(gt$live) & !gt$live & !is.na(gt$stemDiameter) & gt$stemDiameter >= 10 &
                 !is.na(gt$dist21) & gt$dist21 <= 4 & abs(gt$E - cx) <= ph + 4 & abs(gt$N - cy) <= ph + 4, , drop = FALSE]
    a <- list(); b <- list(); cc <- list()
    for (rung in RUNGS) {
      rv <- if (rung == "native") NA_real_ else as.numeric(rung)
      cell <- frozen_clip(NULL, site, pid, rv, cx, cy, ph, fz$root)
      if (is.null(cell)) next
      # (a) instance decomposition from the persisted clouds
      for (arm in c("segmentanytree", "forestformer3d")) {
        f <- file.path(nd, paste0(arm, "_instances"), sprintf("%s_%s.laz", pid, rung))
        if (!file.exists(f)) next
        las <- tryCatch(readLAS(f), error = function(e) NULL); if (is.null(las) || is.empty(las)) next
        p <- as.data.frame(las@data); core <- abs(p$X - cx) <= ph & abs(p$Y - cy) <= ph
        p <- p[core, , drop = FALSE]
        if (arm == "segmentanytree") { tree <- p$PredSemantic == 1; inst <- p$PredInstance } else { tree <- rep(NA, nrow(p)); inst <- p$PointSourceID }
        sz <- table(inst[inst > 0])
        a[[length(a) + 1]] <- data.frame(site = site, plot = pid, rung = rung, detector = arm, n_core_points = nrow(p),
                                         n_tree = sum(tree), n_assigned = sum(inst > 0), n_tree_assigned = sum(tree & inst > 0),
                                         n_instances = length(sz), pts_med = if (length(sz)) median(sz) else NA,
                                         pts_p10 = if (length(sz)) unname(quantile(sz, 0.1)) else NA, pts_sum = sum(sz))
      }
      # (b) apexes below 2 m
      for (arm in c("segmentanytree", "forestformer3d", "treeisonet", "chm_vwf")) {
        det <- tryCatch(census_cell_detections(nd, arm, site, pid, rv, fz$root, cell), error = function(e) NULL)
        if (is.null(det)) next
        inc <- abs(det$x - cx) <= ph & abs(det$y - cy) <= ph
        b[[length(b) + 1]] <- data.frame(site = site, plot = pid, rung = rung, detector = arm, n_core = sum(inc),
                                         n_core_below2 = sum(inc & det$z < 2), zmin = suppressWarnings(min(det$z[inc])))
        # (c) native false positives near mapped dead stems
        if (rung == "native" && arm %in% c("chm_vwf", "treeisonet") && nrow(stems)) {
          win <- abs(det$x - cx) <= ph + 4 & abs(det$y - cy) <= ph + 4
          dw <- det[win, , drop = FALSE]
          m <- greedy_match(stems$E, stems$N, dw$x, dw$y, tol = 4, az = stems$height, bz = dw$z, tol_z_up = 8)
          matched <- rep(FALSE, nrow(dw)); matched[m[m > 0]] <- TRUE
          incw <- abs(dw$x - cx) <= ph & abs(dw$y - cy) <= ph
          fp <- dw[incw & !matched, , drop = FALSE]; tp <- dw[incw & matched, , drop = FALSE]
          near <- function(q, r) if (!nrow(q) || !nrow(dead)) rep(FALSE, nrow(q)) else
            apply(q, 1, function(z) any(sqrt((dead$E - z[["x"]])^2 + (dead$N - z[["y"]])^2) <= r))
          live_near <- if (nrow(dead)) sum(apply(stems, 1, function(z) any(sqrt((dead$E - as.numeric(z[["E"]]))^2 + (dead$N - as.numeric(z[["N"]]))^2) <= 4))) else 0
          cc[[length(cc) + 1]] <- data.frame(site = site, plot = pid, detector = arm, n_stems = nrow(stems), n_dead = nrow(dead),
                                             n_dead_core = sum(abs(dead$E - cx) <= ph & abs(dead$N - cy) <= ph),
                                             n_fp = nrow(fp), fp_near4 = sum(near(fp, 4)), fp_near2 = sum(near(fp, 2)),
                                             n_tp = nrow(tp), tp_near4 = sum(near(tp, 4)), live_near4 = live_near)
        }
      }
    }
    list(a = do.call(rbind, a), b = do.call(rbind, b), c = do.call(rbind, cc))
  })
  for (r in res) { if (inherits(r, "try-error")) stop(r); rows_a[[length(rows_a) + 1]] <- r$a; rows_b[[length(rows_b) + 1]] <- r$b; rows_c[[length(rows_c) + 1]] <- r$c }
  cat(site, "done\n")
}
A1 <- do.call(rbind, rows_a); B1 <- do.call(rbind, rows_b); C1 <- do.call(rbind, rows_c)
# (d) stand descriptors of the reference per site: stems and basal area per
# hectare of core, heights, DBH and the three most frequent species.
ps <- read.csv(file.path(frozen_root(d), "population_stems.csv"), stringsAsFactors = FALSE)
ps <- ps[ps$population == "adopted", ]
pp <- read.csv(file.path(frozen_root(d), "population.csv"), stringsAsFactors = FALSE)
stands <- do.call(rbind, lapply(SITES, function(site) {
  gt <- read.csv(file.path(d, "neon", site, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  x <- ps[ps$site == site, ]; x$species <- gt$scientificName[match(x$individualID, gt$individualID)]
  plots <- unique(x$plotID); half <- plot_half(pp$plotType[match(plots, pp$plotID)])
  area <- sum((2 * half)^2)
  sp <- sort(table(sub("^(\\w+ \\w+).*$", "\\1", x$species)), decreasing = TRUE)[1:3]
  data.frame(site = site, plots = length(plots), core_ha = area / 1e4, stems = nrow(x),
             stems_per_ha = nrow(x) / area * 1e4,
             basal_area_m2_ha = sum(pi * (x$stemDiameter / 200)^2, na.rm = TRUE) / area * 1e4,
             n_height = sum(!is.na(x$height)), height_median = median(x$height, na.rm = TRUE),
             height_max = max(x$height, na.rm = TRUE), dbh_median = median(x$stemDiameter, na.rm = TRUE),
             species = paste(sprintf("%s (%d)", names(sp), sp), collapse = "; "))
}))
write.csv(stands, file.path(OUT, "instance_audit_stands.csv"), row.names = FALSE)
cat("\n== reference stands\n"); print(stands, row.names = FALSE, digits = 3)
write.csv(A1, file.path(OUT, "instance_audit_instances.csv"), row.names = FALSE)
write.csv(B1, file.path(OUT, "instance_audit_apex_below2.csv"), row.names = FALSE)
write.csv(C1, file.path(OUT, "instance_audit_dead_fp.csv"), row.names = FALSE)
cat("\n== instance decomposition, five sites (pooled counts)\n")
agg <- aggregate(cbind(n_core_points, n_tree, n_assigned, n_tree_assigned, n_instances, pts_sum) ~ detector + rung, A1, sum,
                 na.action = na.pass)
agg$tree_share <- agg$n_tree / agg$n_core_points; agg$assigned_share <- agg$n_assigned / agg$n_core_points
agg$assigned_of_tree <- agg$n_tree_assigned / agg$n_tree; agg$mean_pts_per_inst <- agg$pts_sum / agg$n_instances
med <- aggregate(cbind(pts_med, pts_p10) ~ detector + rung, A1, median)
agg <- merge(agg, med); agg <- agg[order(agg$detector, match(agg$rung, RUNGS)), ]
print(agg, digits = 3)
bb0 <- aggregate(cbind(n_core, n_core_below2) ~ detector + rung, B1, sum); bb0$share_below2 <- bb0$n_core_below2 / bb0$n_core
summ <- merge(agg, bb0, all = TRUE)
write.csv(summ[order(summ$detector, match(summ$rung, RUNGS)), ], file.path(OUT, "instance_audit_summary.csv"), row.names = FALSE)
cat("\n== apexes below 2 m (share of core detections)\n")
bb <- aggregate(cbind(n_core, n_core_below2) ~ detector + rung, B1, sum); bb$share <- bb$n_core_below2 / bb$n_core
print(bb[order(bb$detector, match(bb$rung, RUNGS)), ], digits = 3)
cat("\n== native false positives near mapped dead stems (DBH >= 10, within 4 yr)\n")
cs <- aggregate(cbind(n_stems, n_dead, n_dead_core, n_fp, fp_near4, fp_near2, n_tp, tp_near4, live_near4) ~ detector, C1, sum)
cs$fp_near4_share <- cs$fp_near4 / cs$n_fp; cs$fp_near2_share <- cs$fp_near2 / cs$n_fp; cs$tp_near4_share <- cs$tp_near4 / cs$n_tp; cs$live_near4_share <- cs$live_near4 / cs$n_stems
print(cs, digits = 3)
print(aggregate(cbind(n_dead_core, n_fp, fp_near4) ~ detector + site, C1, sum))
