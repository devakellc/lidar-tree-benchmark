#!/usr/bin/env Rscript
# ForestMamba density-ladder arm. Runs the released ForestMamba checkpoint
# zero-shot in the forestmamba-sm120 container on a staged copy of each
# RAW-WITH-GROUND frozen clip (sealed root and declared population of
# freeze_clips.R), reduces instances to apex detections and scores them against
# field stems. Serial within a site -- one container per cell.
#
# ForestMamba is a fork of the ForestFormer3D code with the same native test
# route, so each clip is one whole scene and the export is ForestFormer3D's
# row-indexed schema (gpu/forestmamba-sm120/README.md):
#   clip_rawground.laz (staged copy) --run_docker_arm(forestmamba-sm120)-->
#     scene.laz --ff3d_scene_check--> --ff3d_collapse--> apex(x,y,z UTM)
#     --agl_guard(ground_dtm.tif)--> apex(z AGL) --score_plot.
#
# The checkpoint must be the one pinned in gpu/CHECKSUMS.sha256. The checkout
# is copied to a per-run workspace, because upstream writes data/ and
# work_dirs/ inside it. The driver loads the checkpoint strictly, leaves
# classified noise out of the scene, measures height from the lowest ground
# return and seeds torch, numpy and Python with SEED before every scene: the
# query supplement's farthest-point sampling draws a random start. Every run
# writes forestmamba_run_manifest.json, whose identity (image ID, upstream
# revision and local modification hash, configuration, checkpoint hash, code
# hashes, the hashes of the site's reference stems and plot centroids, seed,
# match tolerance, frozen root, population) a resumed run must repeat, and
# every cell a receipt next to its persisted instance cloud.
#
# Usage:
#   Rscript scripts/detect_forestmamba_sweep.R [SITE=SOAP] [PLOTS=ALL]
#     [RUNGS=native,8,4,2,1] [POP=adopted] [FROZEN_ROOT=...] [TOL=4]
#     [IMAGE=forestmamba-sm120] [REPO=<abs>] [CKPT=<abs>] [SEED=0] [TIMEOUT=3600]
# Output: $CLAUDE_JOB_DIR/neon/<SITE>/forestmamba_results.csv (row per plot x
#         rung) and forestmamba_instances/<plot>_<rung>.laz with the driver's
#         receipt (.laz.json) and the cell receipt (.receipt.json).
suppressMessages({ library(lidR); library(data.table) })
options(lidR.progress = FALSE)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_file)
source(.find("sweep_lib.R")); source(.find("model_bench_lib.R"))
source(.find("model_runner.R")); source(.find("io_bridge.R"))

FM_CONFIG <- "configs/ForAINetv2/forestmamba_chm_radius16_qp300_2many_v6.py"

# "native,8,4,2,1" -> list(native = TRUE, rungs = c(8, 4, 2, 1)).
fm_parse_rungs <- function(x) {
  parts <- trimws(strsplit(x, ",", fixed = TRUE)[[1]])
  native <- tolower(parts) == "native"
  rungs <- suppressWarnings(as.numeric(parts[!native]))
  if (anyNA(rungs) || any(rungs <= 0))
    stop("Unknown rung in ", x, call. = FALSE)
  list(native = any(native), rungs = rungs)
}

# Files a result row depends on besides the model: the code that makes and
# scores it, with the libraries that gate the reference stems, and the site's
# reference stems and plot centroids. Their digests join the run identity, so a
# resumed pass cannot mix rows from edited code or another reference.
fm_identity_files <- function(entry, driver, ff3d, nd) list(
  code = c(entry, driver, file.path(dirname(driver), c("fm_export.py", "fm_checkpoint.py")),
           file.path(ff3d, "ff3d_export.py"),
           vapply(c("detect_forestmamba_sweep.R", "io_bridge.R", "model_runner.R", "sweep_lib.R",
                    "model_bench_lib.R", "site_extension_lib.R", "neon_spatial_lib.R",
                    "neon_reference_support_lib.R"), .find, "", USE.NAMES = FALSE)),
  reference = file.path(nd, c("ground_truth_stems.csv", "plot_centroids.csv")))

# One cell: `run(input, out)` runs the container on a staged copy of the frozen
# raw clip and returns ff3d_collapse()'s apexes, or NULL when the container
# crashed or wrote an unreadable file (the cell is then skipped). A readable
# export that breaks the row-indexed contract stops the run instead. The checked
# export is persisted at `dest` with the driver's receipt and a cell receipt,
# then its apexes are height-normalised and scored.
fm_run_cell <- function(prep, stems, cx, cy, ph, dest, run, tol = 4, config = NULL) {
  cell <- tempfile("fm_cell_"); dir.create(cell)
  on.exit(unlink(cell, recursive = TRUE), add = TRUE)
  cell <- container_path(cell)              # the mounts resolve symlinks; so must the paths
  input <- file.path(cell, "rawground.laz")   # the container mounts this copy, never the root
  if (!file.copy(prep$rawground, input)) stop("Cannot stage ", prep$rawground)
  out_laz <- file.path(cell, "scene.laz")
  t0 <- Sys.time()
  det_abs <- run(input, out_laz)
  seconds <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (is.null(det_abs)) return(NULL)
  ff3d_scene_check(out_laz, input)
  if (!is.null(config)) {
    rc <- jsonlite::read_json(paste0(out_laz, ".json"))
    if (!identical(rc$config, config))
      stop("The driver ran configuration ", rc$config, ", not ", config)
  }
  if (!file.copy(out_laz, dest, overwrite = TRUE)) stop("Cannot persist ", dest)
  if (file.exists(paste0(out_laz, ".json")))
    file.copy(paste0(out_laz, ".json"), paste0(dest, ".json"), overwrite = TRUE)
  jsonlite::write_json(list(layout = "whole_scene", input_sha256 = frozen_sha256(prep$rawground),
                            output_sha256 = frozen_sha256(dest), seconds = seconds,
                            n_apex = nrow(det_abs)),
                       sub("[.]laz$", ".receipt.json", dest), auto_unbox = TRUE,
                       pretty = TRUE, digits = NA)
  det <- agl_guard(det_abs, prep$dtm)
  if (is.null(det)) return(NULL)              # wholesale off-DTM (frame bug) -> skip
  sc <- tryCatch(score_plot(stems, det, tol_xy = tol, core_cx = cx, core_cy = cy,
                            core_half = ph),
                 error = function(e) NULL)
  if (is.null(sc)) return(NULL)
  cbind(data.frame(n_apex = nrow(det), seconds = round(seconds, 1)), sc)
}

# The checkpoint's SHA-256, provided its basename is pinned with that hash in
# the checksum manifest (gpu/CHECKSUMS.sha256); anything else stops the run.
fm_checkpoint_pinned <- function(path, manifest) {
  if (!file.exists(manifest)) stop("Missing checksum manifest ", manifest)
  m <- read.table(manifest, stringsAsFactors = FALSE, col.names = c("sha256", "file"))
  want <- m$sha256[m$file == basename(path)]
  if (length(want) != 1L) stop(basename(path), " is not pinned in ", manifest)
  got <- digest::digest(file = path, algo = "sha256")
  if (!identical(got, want)) stop(basename(path), " does not match its pinned SHA-256")
  got
}

# Run the container as the invoking user, so its outputs and the workspace it
# writes stay deletable (as root they outlive the R session's temp cleanup).
fm_docker_user <- function() {
  id <- function(flag) system2("id", flag, stdout = TRUE)
  c("--user", paste0(id("-u"), ":", id("-g")), "-e", "HOME=/tmp")
}

run_main <- function() {
  args  <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
  A     <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")),
                    sapply(args, `[`, 1))
  d       <- .job_dir()
  SITE    <- if (is.null(A$SITE)) "SOAP" else A$SITE
  PLOTS   <- if (is.null(A$PLOTS) || A$PLOTS == "ALL") NULL else strsplit(A$PLOTS, ",")[[1]]
  TOL     <- as.numeric(if (is.null(A$TOL)) 4 else A$TOL)
  IMAGE   <- if (is.null(A$IMAGE)) "forestmamba-sm120" else A$IMAGE
  TIMEOUT <- as.numeric(if (is.null(A$TIMEOUT)) 3600 else A$TIMEOUT)
  SEED    <- as.integer(if (is.null(A$SEED)) 0L else A$SEED)
  RUNGS   <- if (is.null(A$RUNGS)) "native,8,4,2,1" else A$RUNGS
  rg      <- fm_parse_rungs(RUNGS)
  gpu     <- file.path(.ROOT, "gpu")
  REPO    <- if (is.null(A$REPO)) file.path(gpu, "store", "forestmamba", "ForestMamba") else A$REPO
  CKPT    <- if (is.null(A$CKPT)) file.path(gpu, "store", "forestmamba",
                                            "v6_epoch_1500_fix.pth") else A$CKPT
  ENTRY   <- file.path(gpu, "forestmamba-sm120", "fm_entry.sh")
  DRIVER  <- file.path(gpu, "forestmamba-sm120", "fm_arm.py")
  FF3D    <- file.path(gpu, "forestformer3d-sm120")   # the shared whole-scene export
  for (f in c(ENTRY, DRIVER, CKPT, REPO, file.path(FF3D, "ff3d_export.py")))
    if (!file.exists(f)) stop("Missing ", f, call. = FALSE)
  CKPT_SHA256 <- fm_checkpoint_pinned(CKPT, file.path(gpu, "CHECKSUMS.sha256"))
  # Arguments the container sees must resolve like run_docker_arm's mounts.
  CKPT <- container_path(CKPT); ENTRY <- container_path(ENTRY)
  DRIVER <- container_path(DRIVER); FF3D <- container_path(FF3D)

  nd  <- file.path(d, "neon", SITE)
  gt  <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc  <- read.csv(file.path(nd, "plot_centroids.csv"),     stringsAsFactors = FALSE)
  fz  <- frozen_scope(d, SITE, A, gt)     # declared population + sealed root
  gt  <- fz$gt
  invisible(neon_validate_inputs(gt, pc))
  keep <- fz$plots
  if (!is.null(PLOTS)) keep <- intersect(keep, PLOTS)
  keep <- intersect(keep, pc$plotID)
  cat(sprintf("[%s] forestmamba plots (%s): %d (image=%s seed=%d rungs=%s)\n",
              SITE, fz$population, length(keep), IMAGE, SEED, RUNGS))

  # Resumable: the results file is tied to its sealed root and population, the
  # model identity must match the one that made the existing rows, and each
  # pass is appended to the manifest.
  result_file <- file.path(nd, "forestmamba_results.csv")
  frozen_resume_guard(result_file, fz)
  results <- if (file.exists(result_file))
    read.csv(result_file, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  # The code that makes and scores a row and the reference it is scored against
  # are part of the identity, so a resumed run cannot mix rows from edited code,
  # another reference, a changed tolerance or another config.
  files <- fm_identity_files(ENTRY, DRIVER, FF3D, nd)
  update_run_manifest(file.path(nd, "forestmamba_run_manifest.json"),
    identity = list(layout = "whole_scene", image = IMAGE, image_id = docker_image_id(IMAGE),
      source = git_source_identity(REPO, c("configs", "oneformer3d", "tools")),
      config = FM_CONFIG,
      checkpoint = list(file = basename(CKPT), md5 = unname(tools::md5sum(CKPT)),
                        sha256 = CKPT_SHA256),
      code = file_digests(files$code), reference = file_digests(files$reference),
      seed = SEED, tol = TOL,
      frozen_root = frozen_root_id(fz$root), population = fz$population),
    pass = list(rungs = as.list(c(if (rg$native) "native", as.character(rg$rungs))),
                timeout = TIMEOUT, started = format(Sys.time(), tz = "UTC", usetz = TRUE)),
    resuming = !is.null(results))
  done <- if (is.null(results)) character() else paste(results$plot, results$rung)
  ws <- file.path(tempdir(), "fm_model")
  if (system2("rsync", shQuote(c("-a", "--exclude=.git", "--exclude=data",
        "--exclude=work_dirs", "--exclude=__pycache__", paste0(REPO, "/"),
        paste0(ws, "/")))) != 0L)
    stop("Cannot isolate the ForestMamba workspace")
  ws <- container_path(ws)

  # Durable per-point instance clouds for the crown and IoU/PQ readers, stamped
  # with the sealed root that made them.
  inst_dir <- file.path(nd, "forestmamba_instances")
  frozen_stamp(inst_dir, fz$root)
  container <- function(label) function(input, out)
    run_docker_arm(IMAGE, input, out, cmd = c("bash", ENTRY),
                   extra = c(CKPT, ws, DRIVER, SEED),
                   mounts = c(ws, dirname(CKPT), dirname(ENTRY), FF3D),
                   reader = ff3d_collapse, gpus = "all", timeout = TIMEOUT,
                   extra_docker = fm_docker_user(), label = label)

  for (pid in keep) {                       # serial -- one container at a time
    ci <- pc[pc$plotID == pid, ][1, ]
    cx <- ci$easting; cy <- ci$northing; ph <- plot_half(ci$plotType)
    stems <- gt[gt$plotID == pid & abs(gt$E - cx) <= ph & abs(gt$N - cy) <= ph, ]
    if (nrow(stems) < 1) next
    # Native density from the sealed root, so a pass without native still
    # applies the no-upsampling guard.
    np <- frozen_clip(NULL, SITE, pid, NA, cx, cy, ph, fz$root)
    native_pdens <- if (is.null(np)) NA_real_ else np$pdens
    ncell <- 0L; nskip <- 0L; out <- list()
    for (rung in c(if (rg$native) NA_real_ else numeric(), rg$rungs)) {
      prep <- frozen_clip(NULL, SITE, pid, rung, cx, cy, ph, fz$root)
      if (is.null(prep)) next
      if (!is.na(rung) && (is.na(native_pdens) || rung >= native_pdens)) next
      tag <- ifelse(is.na(rung), "native", as.character(rung))
      dest <- file.path(inst_dir, sprintf("%s_%s.laz", pid, tag))
      if (paste(pid, tag) %in% done && file.exists(dest) &&
          file.exists(sub("[.]laz$", ".receipt.json", dest))) {
        nskip <- nskip + 1L; next           # finished in an earlier pass
      }
      row <- fm_run_cell(prep, stems, cx, cy, ph, dest,
                         container(sprintf("%s/%s", pid, tag)), tol = TOL, config = FM_CONFIG)
      if (is.null(row)) next
      out[[length(out) + 1]] <- cbind(data.frame(site = SITE, plot = pid,
        plotType = ci$plotType, detector = "forestmamba", rung = tag,
        pdens = round(prep$pdens, 2), frdens = round(prep$frdens, 2),
        layout = "whole_scene", tol = TOL), row)
      ncell <- ncell + 1L
    }
    cat(sprintf("  %s: %d cells, %d already done\n", pid, ncell, nskip))
    if (length(out)) {                      # write after every plot: a crash loses one plot
      new <- do.call(rbind, out)
      new$tp_core <- round(new$precision * new$n_det)
      results <- if (is.null(results)) new else
        rbind(results[!paste(results$plot, results$rung) %in% paste(new$plot, new$rung), ,
                      drop = FALSE], new)
      done <- paste(results$plot, results$rung)
      tmp <- paste0(result_file, ".tmp")
      write.csv(results, tmp, row.names = FALSE)
      if (!file.rename(tmp, result_file)) stop("Cannot write ", result_file)
    }
  }
  if (is.null(results) || !nrow(results)) {
    cat("no forestmamba results\n"); return(invisible())
  }
  cat(sprintf("[%s] forestmamba DONE: %d rows -> %s\n", SITE, nrow(results), result_file))
}

if (sys.nframe() == 0L) run_main()
