#!/usr/bin/env Rscript
# TreeisoNet (#M7) density-ladder arm. Runs the headless TreeisoNet apex driver
# (gpu/run_treeisonet.py) on the NORMALIZED frozen clip per plot x density rung
# (sealed root and declared population from freeze_clips.R), SERIALLY (single GPU -- no mclapply contention), scoring against field stems
# with the existing harness. Apex-only (treeLoc -> postPeakExtraction ->
# local-canopy-max z-snap); the treeOff crown variant is issue #20. `conf` is a
# fixed zero-shot threshold, calibrated once (NOT per plot). Normalized Z is
# already height-above-ground, so no DTM transform is needed (see the GPU-arm
# plan's implementation findings). The apex pass never runs treeOff, so the
# treeOff export corrections of the transfer audit do not change it.
#
# MASKS=1 (default) adds, per cell, the corrected treeOff driver
# (gpu/run_treeisonet_crowns.py: physical-height cutoff in the normalized frame,
# treeOff support mask, aligned export of every input row with background 0)
# and persists treeisonet_instances/<plot>_<rung>.laz (tree_pred) for the
# IoU/PQ and crown scorers. Every run writes treeisonet_run_manifest.json
# (TreeAIBox revision and local modification hash, checkpoint, config and
# driver hashes); every mask cell a receipt next to its cloud.
#
# Usage:
#   Rscript scripts/detect_treeisonet_sweep.R [SITE=SOAP] [PLOTS=ALL]
#       [CONF=0.22] [VOXEL=0] [TOL=4] [MASKS=1] [HMIN=2] [POP=adopted]
#       [FROZEN_ROOT=...]
#   VOXEL may be a scalar isotropic override or "x,y,z" (e.g. 0.8,0.8,2.0).
# Requires the venv + weights from gpu/setup_treeisonet_env.sh + gpu/mirror_weights.sh.
# Output: $CLAUDE_JOB_DIR/neon/<SITE>/treeisonet_results.csv (one row per
#         plot x rung; n_inst = mask instances, NA without a mask).
suppressMessages({ library(lidR); library(data.table) })
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
VOXEL <- if (is.null(A$VOXEL)) "0" else A$VOXEL
TOL   <- as.numeric(if (is.null(A$TOL)) 4.0 else A$TOL)
MASKS <- is.null(A$MASKS) || A$MASKS != "0"
HMIN  <- if (is.null(A$HMIN)) "2" else A$HMIN
RUNGS <- FROZEN_RUNGS
VENV  <- file.path(.ROOT, "gpu/.venv/bin/python")
DRV   <- file.path(.ROOT, "gpu/run_treeisonet.py")
DRV_MASK <- file.path(.ROOT, "gpu/run_treeisonet_crowns.py")
BOX   <- file.path(.ROOT, "gpu/TreeAIBox")
LOC   <- file.path(.ROOT, "gpu/store/treeaibox/als_treeloc.pth")
CFG   <- Sys.glob(file.path(.ROOT, "gpu/store/treeaibox/*reclamation*treeloc*.json"))[1]
OFF   <- file.path(.ROOT, "gpu/store/treeaibox/als_treeoff.pth")
OCFG  <- Sys.glob(file.path(.ROOT, "gpu/store/treeaibox/*reclamation*treeoff*.json"))[1]

# Per-cell treeOff mask with the corrected aligned export; the aligned cloud
# must carry one tree_pred per input row. Returns the instance count, or NULL
# when the driver fails (the apex row stands without a mask).
treeisonet_mask <- function(input, dest, label) {
  aligned <- file.path(tempdir(), paste0(basename(dest), ".aligned.laz"))
  unlink(aligned)
  pts <- run_python_crown_arm(VENV, DRV_MASK, input,
    file.path(tempdir(), paste0(basename(dest), ".csv")),
    extra = c(LOC, CFG, OFF, OCFG, VOXEL, CONF, HMIN, aligned), timeout = 900,
    label = label)
  if (is.null(pts) || !file.exists(aligned)) return(NULL)
  out <- lidR::readLAS(aligned)
  if (!"tree_pred" %in% names(out@data) || nrow(out@data) != lidR::npoints(lidR::readLAS(input)))
    stop("TreeisoNet aligned export does not cover every input row: ", label)
  if (!file.copy(aligned, dest, overwrite = TRUE)) stop("Cannot persist ", dest)
  length(unique(out@data$tree_pred[out@data$tree_pred > 0]))
}

run_main <- function() {
  stopifnot(file.exists(VENV), file.exists(DRV), file.exists(LOC), !is.na(CFG),
            !MASKS || (file.exists(DRV_MASK) && file.exists(OFF) && !is.na(OCFG)))
  nd  <- file.path(d, "neon", SITE)
  gt  <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc  <- read.csv(file.path(nd, "plot_centroids.csv"),     stringsAsFactors = FALSE)
  fz  <- frozen_scope(d, SITE, A, gt)     # declared population + sealed root
  gt  <- fz$gt
  invisible(neon_validate_inputs(gt, pc))
  keep   <- fz$plots
  if (!is.null(PLOTS)) keep <- intersect(keep, PLOTS)
  keep   <- intersect(keep, pc$plotID)
  cat(sprintf("[%s] treeisonet plots (%s): %d (conf=%s voxel=%s masks=%s)\n",
              SITE, fz$population, length(keep), CONF, VOXEL, MASKS))
  weights <- c(LOC, CFG, if (MASKS) c(OFF, OCFG))
  jsonlite::write_json(list(source = git_source_identity(BOX, "modules"),
      checkpoints = file_digests(weights, "md5"),
      code = file_digests(c(DRV, if (MASKS) c(DRV_MASK, file.path(.ROOT, "gpu/treeisonet_export.py")),
                            .find("detect_treeisonet_sweep.R"), .find("model_runner.R"))),
      python = system2(VENV, "--version", stdout = TRUE, stderr = TRUE),
      conf = CONF, voxel = VOXEL, masks = MASKS, hmin = HMIN,
      frozen_root = frozen_root_id(fz$root), population = fz$population),
    file.path(nd, "treeisonet_run_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
  inst_dir <- file.path(nd, "treeisonet_instances")
  if (MASKS) frozen_stamp(inst_dir, fz$root)

  out <- list()
  for (pid in keep) {                       # SERIAL -- one GPU, no contention
    ci <- pc[pc$plotID == pid, ][1, ]
    cx <- ci$easting; cy <- ci$northing; ph <- plot_half(ci$plotType)
    stems <- gt[gt$plotID == pid & abs(gt$E - cx) <= ph & abs(gt$N - cy) <= ph, ]
    if (nrow(stems) < 1) next
    native_pdens <- NA_real_; ncell <- 0L
    for (rung in c(NA, RUNGS)) {
      prep <- frozen_clip(NULL, SITE, pid, rung, cx, cy, ph, fz$root)
      if (is.null(prep)) next
      pdens <- prep$pdens; frdens <- prep$frdens
      if (is.na(rung)) native_pdens <- pdens
      else if (is.na(native_pdens) || rung >= native_pdens) next
      ocsv <- file.path(tempdir(), sprintf("ti_%s_%s.csv", pid,
                        ifelse(is.na(rung), "native", rung)))
      det <- run_python_arm(VENV, DRV, prep$normalized, ocsv,
                            extra = c(LOC, CFG, VOXEL, CONF), timeout = 900,
                            label = sprintf("%s/%s", pid,
                              ifelse(is.na(rung), "native", rung)))
      if (is.null(det)) next                # GPU crash -> skip cell (guard drops)
      tag <- ifelse(is.na(rung), "native", as.character(rung))
      n_inst <- NA_integer_
      if (MASKS) {
        dest <- file.path(inst_dir, sprintf("%s_%s.laz", pid, tag))
        n_inst <- treeisonet_mask(prep$normalized, dest, sprintf("%s/%s mask", pid, tag))
        if (is.null(n_inst)) n_inst <- NA_integer_ else
          jsonlite::write_json(list(input_sha256 = frozen_sha256(prep$normalized),
              output_sha256 = frozen_sha256(dest), instances = n_inst, hmin = HMIN),
            sub("[.]laz$", ".receipt.json", dest), auto_unbox = TRUE, pretty = TRUE)
      }
      sc <- tryCatch(score_plot(stems, det, tol_xy = TOL, core_cx = cx,
                                core_cy = cy, core_half = ph),
                     error = function(e) NULL)
      if (is.null(sc)) next
      out[[length(out) + 1]] <- cbind(data.frame(site = SITE, plot = pid,
        plotType = ci$plotType, detector = "treeisonet",
        rung = ifelse(is.na(rung), "native", as.character(rung)),
        pdens = round(pdens, 2), frdens = round(frdens, 2), n_apex = nrow(det),
        n_inst = n_inst), sc)
      ncell <- ncell + 1L
    }
    cat(sprintf("  %s: %d cells\n", pid, ncell))
  }
  results <- do.call(rbind, out)
  if (is.null(results) || !nrow(results)) { cat("no treeisonet results\n"); return(invisible()) }
  results$tp_core <- round(results$precision * results$n_det)
  write.csv(results, file.path(nd, "treeisonet_results.csv"), row.names = FALSE)
  cat(sprintf("[%s] treeisonet DONE: %d rows -> %s\n", SITE, nrow(results),
              file.path(nd, "treeisonet_results.csv")))
}

if (sys.nframe() == 0L) run_main()
