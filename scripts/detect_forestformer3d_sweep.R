#!/usr/bin/env Rscript
# ForestFormer3D (#M8) density-ladder arm. Runs FF3D zero-shot in the ff3d-sm120
# container on the RAW-WITH-GROUND frozen clip (sealed root and declared
# population of freeze_clips.R), reduces instances to apex detections and
# scores against field stems. Serial -- one GPU.
#
# LAYOUT=whole_scene (default) is the indexed native path of the scene-assembly
# study: the whole clip is one scene, and the export keeps every input row in
# order with its instance ID, so no outer assembly or merge is involved.
# LAYOUT=outer_cylinders reproduces the historical June runs (16 m cylinders
# over the core, cross-block apex dedup); it is kept for reproduction only.
#
#   rawground.laz (staged copy) --run_docker_arm(ff3d-sm120)--> scene.laz
#     --ff3d_scene_check--> --ff3d_collapse--> apex(x,y,z UTM)
#     --agl_guard(ground_dtm.tif)--> apex(z AGL) --score_plot.
#
# The model checkout is copied to a per-run workspace, because upstream writes
# data/ and work_dirs/ inside it. Every run writes
# forestformer3d_run_manifest.json (image ID, upstream revision and local
# modification hash, checkpoint and code hashes, frozen root, population) and
# every cell a receipt next to its persisted instance cloud.
#
# Usage:
#   Rscript scripts/detect_forestformer3d_sweep.R [SITE=SOAP] [PLOTS=ALL]
#     [LAYOUT=whole_scene|outer_cylinders] [SPACING=24] [MERGE_TOL=2.0] [TOL=4]
#     [IMAGE=ff3d-sm120] [REPO=<abs>] [CKPT=<abs>] [TIMEOUT=3600]
#     [RUNGS=native,8] [POP=adopted] [FROZEN_ROOT=...]
# Output: $CLAUDE_JOB_DIR/neon/<SITE>/forestformer3d_results.csv (row per plot x rung).
suppressMessages({ library(lidR); library(data.table) })
options(lidR.progress = FALSE)
d <- Sys.getenv("CLAUDE_JOB_DIR", file.path(getwd(), "work"))
bs <- Find(file.exists, c(
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs)
source(.find("sweep_lib.R")); source(.find("model_bench_lib.R"))
source(.find("model_runner.R")); source(.find("io_bridge.R"))

args     <- strsplit(commandArgs(TRUE), "=")
A        <- setNames(lapply(args, `[`, 2), sapply(args, `[`, 1))
SITE     <- if (is.null(A$SITE))  "SOAP" else A$SITE
PLOTS    <- if (is.null(A$PLOTS) || A$PLOTS == "ALL") NULL else strsplit(A$PLOTS, ",")[[1]]
SPACING  <- as.numeric(if (is.null(A$SPACING)) 24 else A$SPACING)
MERGE_TOL<- as.numeric(if (is.null(A$MERGE_TOL)) 2.0 else A$MERGE_TOL)
TOL      <- as.numeric(if (is.null(A$TOL)) 4.0 else A$TOL)
IMAGE    <- if (is.null(A$IMAGE)) "ff3d-sm120" else A$IMAGE
TIMEOUT  <- as.numeric(if (is.null(A$TIMEOUT)) 3600 else A$TIMEOUT)
LAYOUT   <- if (is.null(A$LAYOUT)) "whole_scene" else A$LAYOUT
if (!LAYOUT %in% c("whole_scene", "outer_cylinders"))
  stop("LAYOUT must be whole_scene or outer_cylinders", call. = FALSE)
RADIUS   <- 16
RUNGS_RAW <- if (is.null(A$RUNGS)) c("native", "8") else
  strsplit(A$RUNGS, ",")[[1]]
RUN_NATIVE <- any(tolower(RUNGS_RAW) == "native")
RUNGS <- as.numeric(RUNGS_RAW[tolower(RUNGS_RAW) != "native"])
RUNGS <- RUNGS[is.finite(RUNGS)]
REPO  <- if (is.null(A$REPO)) file.path(.ROOT, "gpu/store/forestformer3d/ForestFormer3D") else A$REPO
CKPT  <- if (is.null(A$CKPT)) file.path(REPO, "work_dirs/clean_forestformer/epoch_3000_fix.pth") else A$CKPT
ENTRY <- file.path(.ROOT, "gpu/forestformer3d-sm120/ff3d_entry.sh")
# Vendored in THIS repo (not the external FF3D checkout); dirname(ENTRY) — which is
# mounted below — is the same dir, so the container can read it.
PATCH <- file.path(.ROOT, "gpu/forestformer3d-sm120/ff3d_repo.patch")
DRIVER<- file.path(.ROOT, "gpu/forestformer3d-sm120/ff3d_arm.py")

# Cylinder centers on a square grid that EVENLY covers [-ph, ph]^2 about the plot
# center. `spacing` sets the grid density — an UPPER BOUND on the step: k =
# ceil(2*ph/spacing)+1 columns, then seq() spreads them evenly, so the actual step
# is 2*ph/(k-1) <= spacing. With spacing=24: tower ph=20 -> 3 cols, 20 m step
# (9 cylinders); distributed ph=10 -> 2 cols, 20 m step (4). Each cylinder
# processes radius RADIUS, so the actual overlap is 2*RADIUS - step (12 m here).
cyl_centers <- function(cx, cy, ph, spacing) {
  k <- max(1L, ceiling((2 * ph) / spacing) + 1L)
  off <- seq(-ph, ph, length.out = k)
  g <- expand.grid(dx = off, dy = off)
  data.frame(cx = cx + g$dx, cy = cy + g$dy)
}

run_main <- function() {
  stopifnot(file.exists(ENTRY), file.exists(DRIVER), file.exists(CKPT), file.exists(REPO))
  nd  <- file.path(d, "neon", SITE)
  gt  <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc  <- read.csv(file.path(nd, "plot_centroids.csv"),     stringsAsFactors = FALSE)
  fz  <- frozen_scope(d, SITE, A, gt)     # declared population + sealed root
  gt  <- fz$gt
  invisible(neon_validate_inputs(gt, pc))
  keep <- fz$plots
  if (!is.null(PLOTS)) keep <- intersect(keep, PLOTS)
  keep <- intersect(keep, pc$plotID)
  cat(sprintf("[%s] forestformer3d plots (%s): %d (image=%s layout=%s)\n",
              SITE, fz$population, length(keep), IMAGE, LAYOUT))

  # Run provenance, then an isolated copy of the (patched) model checkout.
  manifest <- list(layout = LAYOUT, image = IMAGE, image_id = docker_image_id(IMAGE),
    source = git_source_identity(REPO, c("configs", "oneformer3d", "tools")),
    checkpoint = list(file = basename(CKPT), md5 = unname(tools::md5sum(CKPT)),
                      sha256 = digest::digest(file = CKPT, algo = "sha256")),
    code = file_digests(c(ENTRY, PATCH, DRIVER, file.path(dirname(DRIVER), "ff3d_export.py"),
                          .find("detect_forestformer3d_sweep.R"), .find("io_bridge.R"),
                          .find("model_runner.R"))),
    frozen_root = frozen_root_id(fz$root), population = fz$population,
    rungs = RUNGS_RAW, timeout = TIMEOUT,
    cylinders = if (LAYOUT == "outer_cylinders")
      list(radius = RADIUS, spacing = SPACING, merge_tol = MERGE_TOL))
  jsonlite::write_json(manifest, file.path(nd, "forestformer3d_run_manifest.json"),
                       auto_unbox = TRUE, pretty = TRUE, digits = NA)
  ws <- file.path(tempdir(), "ff3d_model")
  if (system2("rsync", shQuote(c("-a", "--exclude=.git", "--exclude=data",
        "--exclude=work_dirs", "--exclude=__pycache__", paste0(REPO, "/"),
        paste0(ws, "/")))) != 0L)
    stop("Cannot isolate the ForestFormer3D workspace")

  # Durable per-point instance dir the #34 crown-diameter arm
  # (crown_metrics_deepmodel.R) consumes: the merged per-cylinder labelled LAZ
  # (UserData = block, PointSourceID = per-cylinder instance id) for each
  # successful (plot, rung) is persisted here as <plot>_<rung>.laz so the crown arm
  # can re-derive ff3d_crown_table (dedup_blocks + crown_diameter_table +
  # instance_apex) from the SAME labelling without re-running the container.
  # The directory records the sealed root that made it; one made on other clips
  # must be moved aside first.
  inst_dir <- file.path(nd, "forestformer3d_instances")
  frozen_stamp(inst_dir, fz$root)

  out <- list()
  for (pid in keep) {                       # SERIAL -- one GPU
    ci <- pc[pc$plotID == pid, ][1, ]
    cx <- ci$easting; cy <- ci$northing; ph <- plot_half(ci$plotType)
    stems <- gt[gt$plotID == pid & abs(gt$E - cx) <= ph & abs(gt$N - cy) <= ph, ]
    if (nrow(stems) < 1) next
    native_pdens <- NA_real_; ncell <- 0L
    for (rung in c(if (RUN_NATIVE) NA_real_ else numeric(), RUNGS)) {
      prep <- frozen_clip(NULL, SITE, pid, rung, cx, cy, ph, fz$root)
      if (is.null(prep)) next
      pdens <- prep$pdens; frdens <- prep$frdens
      if (is.na(rung)) native_pdens <- pdens
      else if (is.na(native_pdens) || rung >= native_pdens) next
      tag <- ifelse(is.na(rung), "native", as.character(rung))
      cell <- file.path(tempdir(), sprintf("ff3d_%s_%s", pid, tag))
      unlink(cell, recursive = TRUE); dir.create(cell, recursive = TRUE)
      if (LAYOUT == "whole_scene") {
        # A staged copy: the container mounts its input directory, never the root.
        input <- file.path(cell, "rawground.laz"); n_cyl <- 1L
        if (!file.copy(prep$rawground, input)) stop("Cannot stage ", prep$rawground)
      } else {                              # historical cylinder tiling
        raw <- tryCatch(lidR::readLAS(prep$rawground), error = function(e) NULL)
        if (is.null(raw) || lidR::is.empty(raw)) next
        input <- cell
        cc <- cyl_centers(cx, cy, ph, SPACING); n_cyl <- 0L
        for (i in seq_len(nrow(cc))) {
          cyl <- lidR::clip_circle(raw, cc$cx[i], cc$cy[i], RADIUS)
          if (lidR::is.empty(cyl) || lidR::npoints(cyl) < 50) next
          lidR::writeLAS(cyl, file.path(cell, sprintf("cyl_%03d.laz", n_cyl)))
          n_cyl <- n_cyl + 1L
        }
        if (n_cyl == 0L) next
      }
      out_laz <- file.path(tempdir(), sprintf("ff3d_%s_%s.laz", pid, tag))
      t0 <- Sys.time()
      # run_docker_arm passes no env, so the workspace/PATCH/DRIVER ride in
      # `extra` as positional args (entry.sh reads $3..$6); all identity-mounted.
      det_abs <- run_docker_arm(IMAGE, input, out_laz,
                   cmd    = c("bash", ENTRY),
                   extra  = c(CKPT, ws, PATCH, DRIVER),
                   mounts = c(ws, dirname(CKPT), dirname(ENTRY)),
                   reader = function(p) ff3d_collapse(p, merge_tol = MERGE_TOL),
                   gpus = "all", timeout = TIMEOUT,
                   label = sprintf("%s/%s", pid, tag))
      seconds <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
      if (is.null(det_abs)) next            # container crash/schema -> skip cell
      if (LAYOUT == "whole_scene") ff3d_scene_check(out_laz, input)   # no fallback
      # Persist the labelled cloud for the crown and IoU/PQ arms (same
      # UserData/PointSourceID schema ff3d_collapse just read), with the
      # driver's export receipt and this cell's receipt.
      dest <- file.path(inst_dir, sprintf("%s_%s.laz", pid, tag))
      if (!file.copy(out_laz, dest, overwrite = TRUE)) stop("Cannot persist ", dest)
      if (file.exists(paste0(out_laz, ".json")))
        file.copy(paste0(out_laz, ".json"), paste0(dest, ".json"), overwrite = TRUE)
      jsonlite::write_json(list(layout = LAYOUT, input_sha256 = frozen_sha256(prep$rawground),
                                output_sha256 = frozen_sha256(dest), seconds = seconds,
                                n_apex = nrow(det_abs)),
                           sub("[.]laz$", ".receipt.json", dest), auto_unbox = TRUE,
                           pretty = TRUE, digits = NA)
      det <- agl_guard(det_abs, prep$dtm)
      if (is.null(det)) next                # wholesale off-DTM (frame bug) -> skip
      sc <- tryCatch(score_plot(stems, det, tol_xy = TOL, core_cx = cx,
                                core_cy = cy, core_half = ph),
                     error = function(e) NULL)
      if (is.null(sc)) next
      out[[length(out) + 1]] <- cbind(data.frame(site = SITE, plot = pid,
        plotType = ci$plotType, detector = "forestformer3d", rung = tag,
        pdens = round(pdens, 2), frdens = round(frdens, 2), layout = LAYOUT,
        n_cyl = n_cyl, n_apex = nrow(det)), sc)
      ncell <- ncell + 1L
    }
    cat(sprintf("  %s: %d cells\n", pid, ncell))
  }
  results <- do.call(rbind, out)
  if (is.null(results) || !nrow(results)) {
    cat("no forestformer3d results\n"); return(invisible())
  }
  results$tp_core <- round(results$precision * results$n_det)
  write.csv(results, file.path(nd, "forestformer3d_results.csv"), row.names = FALSE)
  cat(sprintf("[%s] forestformer3d DONE: %d rows -> %s\n", SITE, nrow(results),
              file.path(nd, "forestformer3d_results.csv")))
}

if (sys.nframe() == 0L) run_main()
