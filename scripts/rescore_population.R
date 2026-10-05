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
source(.find("coverage_lib.R"))
source(.find("census_support_lib.R"))
# Scores the learned arms' persisted per-cell detections against another
# declared population of the same sealed root (the sensitivity rows of the
# master tables), without inference. A cell's clip, and so its detections, do
# not depend on the population; only the reference stems do. Detections come
# from the arm's persisted outputs in the SOURCES job directories (the
# headline run, plus runs on the plots only the other populations hold), read
# exactly as the arm reduced them (census_cell_detections). Each cell is
# scored with the arm's own harness: score_plot with the 4 m tolerance in the
# plot core, the same no-upsampling guard as the sweeps.
#   CLAUDE_JOB_DIR=<the population's job dir> Rscript scripts/rescore_population.R \
#     POP=relaxed SOURCES=<job dir>,<job dir> \
#     [ARMS=forestformer3d,treeisonet,segmentanytree,sam2point]
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [FROZEN_ROOT=...] [TOL=4] [ALLOW_MISSING=1]
# Writes neon/<SITE>/<arm>_results.csv in the target job directory, with the
# <results>.frozen sidecar of the root and population, and stops listing any
# cell whose detections no source holds.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d <- .job_dir()
if (is.null(A$POP) || is.null(A$SOURCES)) stop("POP= and SOURCES= are required")
SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
ARMS <- split_arg(A$ARMS, "forestformer3d,treeisonet,segmentanytree,sam2point")
SOURCES <- normalizePath(split_arg(A$SOURCES, ""), mustWork = TRUE)
TOL <- as.numeric(if (is.null(A$TOL)) 4 else A$TOL)

# SAM2Point's per-point labels are already heights above ground; it scores the
# max-Z point of each label, as read_instances_laz reduces them.
CENSUS_INSTANCE_SOURCES$sam2point <- list(dir = "sam2point_instances", id = "sam2point",
                                          agl = FALSE)
RESCORE_ARMS <- list(
  forestformer3d = list(detector = "forestformer3d", rungs = c(NA, FROZEN_RUNGS)),
  treeisonet     = list(detector = "treeisonet", rungs = c(NA, FROZEN_RUNGS)),
  segmentanytree = list(detector = "segmentanytree", rungs = c(NA, FROZEN_RUNGS)),
  sam2point      = list(detector = "sam2point_seeded", rungs = NA_real_))
bad <- setdiff(ARMS, names(RESCORE_ARMS))
if (length(bad)) stop("No re-scoring rule for: ", paste(bad, collapse = ", "))

missing <- character()
for (site in SITES) {
  nd <- file.path(d, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  fz <- frozen_scope(d, site, A, gt)
  plots <- intersect(fz$plots, pc$plotID)
  for (arm in ARMS) {
    spec <- RESCORE_ARMS[[arm]]; rows <- list()
    for (pid in plots) {
      ci <- pc[pc$plotID == pid, ][1, ]; cx <- ci$easting; cy <- ci$northing
      ph <- plot_half(ci$plotType)
      stems <- fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - cx) <= ph &
                       abs(fz$gt$N - cy) <= ph, , drop = FALSE]
      if (!nrow(stems)) next
      native <- frozen_clip(NULL, site, pid, NA, cx, cy, ph, fz$root)
      for (rung in spec$rungs) {
        cell <- if (is.na(rung)) native else frozen_clip(NULL, site, pid, rung, cx, cy, ph, fz$root)
        if (is.null(cell)) next
        if (!is.na(rung) && (is.null(native) || rung >= native$pdens)) next
        det <- NULL
        for (src in SOURCES) {
          det <- census_cell_detections(file.path(src, "neon", site), arm, site, pid, rung,
                                        fz$root, cell)
          if (!is.null(det)) break
        }
        tag <- census_rung_label(rung)
        if (is.null(det) || !attr(det, "source") %in% c("detections", "instances")) {
          missing <- c(missing, sprintf("%s %s %s %s", arm, site, pid, tag)); next
        }
        sc <- score_plot(stems, det, tol_xy = TOL, core_cx = cx, core_cy = cy, core_half = ph)
        rows[[length(rows) + 1]] <- cbind(data.frame(site = site, plot = pid,
          plotType = ci$plotType, detector = spec$detector, rung = tag,
          pdens = round(cell$pdens, 2), frdens = round(cell$frdens, 2),
          n_apex = nrow(det), stringsAsFactors = FALSE), sc)
      }
    }
    res <- rbindlist(rows, fill = TRUE)
    if (!nrow(res)) next
    res$tp_core <- round(res$precision * res$n_det)
    out <- file.path(nd, paste0(arm, "_results.csv"))
    write.csv(res, out, row.names = FALSE)
    frozen_results_stamp(out, fz)
    p <- pool(res[res$rung == "native", , drop = FALSE])
    cat(sprintf("[%s] %-15s %s: %d cells; native F1 %.3f (n_ref %d)\n", site, arm,
                fz$population, nrow(res), p$F1, p$n_ref))
  }
}
# ALLOW_MISSING=1 lists such cells and exits cleanly: the arm's results then
# lack them, and master_tables.R reports the arm as pending on that population.
if (length(missing)) {
  msg <- paste0(length(missing), " cells have no persisted detections in SOURCES: ",
                paste(head(missing, 20), collapse = "; "))
  if (!identical(A$ALLOW_MISSING, "1")) stop(msg, call. = FALSE)
  message(msg)
}
