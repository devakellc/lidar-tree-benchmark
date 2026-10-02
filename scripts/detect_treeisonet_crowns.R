#!/usr/bin/env Rscript
# TreeisoNet treeOff crown arm (#20). Runs the treeOff crown driver
# (gpu/run_treeisonet_crowns.py) on the native normalized frozen clip per SOAP
# plot (sealed root and declared population from freeze_clips.R; SERIAL, single
# GPU), reduces the per-point instances to apexes + crown
# diameters (the bridge's reduce_instances + crown_diameter_table on the labeled
# CANOPY points), matches apexes to field stems (greedy_match with a height
# gate), and joins NEON field crown diameter. Output is schema-compatible with
# crown_metrics_results.csv (algo = "treeisonet") so analyze_crown_metrics.R can
# union it with the five CHM segmenters from #7.
#
# Crown geometry caveat: the CHM arms take diameters from a dissolved label-
# raster polygon; here it is the convex hull of the crown's canopy points
# (crown_diameter_table). d_eq -> ninetyCrownDiameter, d_caliper -> maxCrownDiameter.
#
# Usage:
#   Rscript scripts/detect_treeisonet_crowns.R [SITE=SOAP] [PLOTS=ALL]
#       [CONF=0.22] [TOL=4] [HMIN=2] [POP=adopted] [FROZEN_ROOT=...] [BATCH=1]
#   BATCH=1 (default) runs every plot in ONE Python process
#   (gpu/run_treeisonet_batch.py); BATCH=0 starts one process per plot.
# Output: $CLAUDE_JOB_DIR/neon/<SITE>/treeisonet_crown_metrics.csv
suppressMessages({ library(lidR); library(data.table); library(grDevices) })
options(lidR.progress = FALSE)
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
d <- .job_dir()
source(.find("sweep_lib.R")); source(.find("model_bench_lib.R"))
source(.find("model_runner.R"))

args  <- strsplit(commandArgs(TRUE), "=")
A     <- setNames(lapply(args, `[`, 2), sapply(args, `[`, 1))
SITE  <- if (is.null(A$SITE))  "SOAP" else A$SITE
PLOTS <- if (is.null(A$PLOTS) || A$PLOTS == "ALL") NULL else strsplit(A$PLOTS, ",")[[1]]
CONF  <- if (is.null(A$CONF))  "0.22" else A$CONF
TOL   <- as.numeric(if (is.null(A$TOL)) 4.0 else A$TOL)
HMIN  <- if (is.null(A$HMIN)) "2" else A$HMIN
MINTREES <- 6    # field-crown-diameter stems per plot (crown sub-population)
VENV  <- file.path(.ROOT, "gpu/.venv/bin/python")
DRV   <- file.path(.ROOT, "gpu/run_treeisonet_crowns.py")
DRV_BATCH <- file.path(.ROOT, "gpu/run_treeisonet_batch.py")
BATCH <- is.null(A$BATCH) || A$BATCH != "0"   # one GPU process per site (default)
LOC   <- file.path(.ROOT, "gpu/store/treeaibox/als_treeloc.pth")
LCFG  <- Sys.glob(file.path(.ROOT, "gpu/store/treeaibox/*reclamation*treeloc*.json"))[1]
OFF   <- file.path(.ROOT, "gpu/store/treeaibox/als_treeoff.pth")
OCFG  <- Sys.glob(file.path(.ROOT, "gpu/store/treeaibox/*reclamation*treeoff*.json"))[1]

# Field crown diameter per individualID, nearest-to-2021 measurement (mirrors
# crown_metrics_sweep.R::field_crowns -- the vst rds is the canonical source).
field_crowns <- function(site) {
  rds <- file.path(d, "neon", site, "vst", paste0(tolower(site), "_vst_allyears.rds"))
  ai  <- as.data.frame(readRDS(rds)$vst_apparentindividual)
  ai$year <- as.integer(substr(ai$date, 1, 4))
  ai <- ai[!is.na(ai$year), ]; ai$dist21 <- abs(ai$year - 2021)
  ai <- ai[order(ai$individualID, ai$dist21), ]
  ai[!duplicated(ai$individualID),
     c("individualID", "maxCrownDiameter", "ninetyCrownDiameter")]
}

run_main <- function() {
  stopifnot(file.exists(VENV), file.exists(DRV), file.exists(LOC), !is.na(LCFG),
            file.exists(OFF), !is.na(OCFG), !BATCH || file.exists(DRV_BATCH))
  nd <- file.path(d, "neon", SITE)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"),     stringsAsFactors = FALSE)
  fz <- frozen_scope(d, SITE, A, gt)      # declared population + sealed root
  gt <- fz$gt
  invisible(neon_validate_inputs(gt, pc))
  gt <- gt[, setdiff(names(gt), c("maxCrownDiameter", "ninetyCrownDiameter")), drop = FALSE]
  neon_reference_epoch(gt, 2021) # This historical crown join is still nearest-to-2021.
  gt <- merge(gt, field_crowns(SITE), by = "individualID", all.x = TRUE)
  gt <- gt[!is.na(gt$maxCrownDiameter) | !is.na(gt$ninetyCrownDiameter), ]
  # Crown sub-population: the declared plots that also hold >= MINTREES gated
  # stems with a field crown diameter.
  counts <- table(gt$plotID); keep <- names(counts)[counts >= MINTREES]
  keep <- intersect(fz$plots, keep)
  if (!is.null(PLOTS)) keep <- intersect(keep, PLOTS)
  keep <- intersect(keep, pc$plotID)
  cat(sprintf("[%s] treeisonet crowns (%s): %d plots w/ field CD (conf=%s)\n",
              SITE, fz$population, length(keep), CONF))

  # Collect the plots, run the crown driver once per site (BATCH=1: one GPU
  # process, CUDA started once), then match each plot's crowns.
  cells <- list()
  for (pid in keep) {
    ci <- pc[pc$plotID == pid, ][1, ]; cx <- ci$easting; cy <- ci$northing
    ph <- plot_half(ci$plotType)
    stems <- gt[gt$plotID == pid & abs(gt$E - cx) <= ph & abs(gt$N - cy) <= ph, ]
    if (nrow(stems) < 1) next
    prep <- frozen_clip(NULL, SITE, pid, NA, cx, cy, ph, fz$root)
    if (is.null(prep)) next
    cells[[pid]] <- list(stems = stems, input = prep$normalized,
                         ocsv = file.path(tempdir(), sprintf("ticr_%s.csv", pid)))
  }
  if (BATCH) {
    jobs <- lapply(cells, function(cl) list(kind = "crowns", input = cl$input,
      output = cl$ocsv, loc_pth = LOC, loc_cfg = LCFG, off_pth = OFF, off_cfg = OCFG,
      voxel = "0", conf = as.numeric(CONF), hmin = as.numeric(HMIN)))
    cat(sprintf("[%s] batch: %d plots in one process\n", SITE, length(jobs)))
    run_python_batch(VENV, DRV_BATCH, unname(jobs), timeout = 900 * max(1L, length(jobs)),
                     label = sprintf("%s crowns batch", SITE))
  }
  rows <- list()
  for (pid in names(cells)) {
    stems <- cells[[pid]]$stems
    pts <- if (BATCH) .read_crown_csv(cells[[pid]]$ocsv) else
      run_python_crown_arm(VENV, DRV, cells[[pid]]$input, cells[[pid]]$ocsv,
        extra = c(LOC, LCFG, OFF, OCFG, "0", CONF, HMIN), timeout = 900, label = pid)
    if (is.null(pts) || !nrow(pts)) next
    dt  <- as.data.table(pts)
    ap  <- dt[, .(x = X[which.max(Z)], y = Y[which.max(Z)], z = max(Z)), by = crown_id]
    cd  <- crown_diameter_table(pts, id_col = "crown_id", min_pts = 5)
    ap  <- merge(ap, cd, by.x = "crown_id", by.y = "id", all.x = TRUE)
    m <- greedy_match(stems$E, stems$N, ap$x, ap$y, TOL,
                      az = stems$height, bz = ap$z)
    for (si in which(m > 0)) {
      cr <- ap[m[si], ]
      rows[[length(rows) + 1]] <- data.frame(site = SITE, plot = pid,
        algo = "treeisonet", crown_class = stems$crown_class[si],
        individualID = stems$individualID[si], d_eq = cr$d_eq,
        d_caliper = cr$d_caliper, area = if (is.na(cr$d_eq)) NA_real_
          else pi * (cr$d_eq / 2)^2,
        field_maxCD = stems$maxCrownDiameter[si],
        field_ninetyCD = stems$ninetyCrownDiameter[si], stringsAsFactors = FALSE)
    }
    cat(sprintf("  %s: %d crowns, %d matched\n", pid, nrow(ap), sum(m > 0)))
  }
  res <- do.call(rbind, rows)
  if (is.null(res) || !nrow(res)) { cat("no treeisonet crowns matched\n"); return(invisible()) }
  out <- file.path(nd, "treeisonet_crown_metrics.csv")
  write.csv(res, out, row.names = FALSE)
  cat(sprintf("[%s] treeisonet crowns DONE: %d matched-tree rows -> %s\n",
              SITE, nrow(res), out))
}

if (sys.nframe() == 0L) run_main()
