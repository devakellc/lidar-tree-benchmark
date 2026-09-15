#!/usr/bin/env Rscript
# Frozen detector transfer on FGI-EMIT's published split. No training or tuning.
# Usage: Rscript scripts/detect_external_fgiemit.R [SPLIT=test] [PLOTS=ALL]
#   [ARMS=segmentanytree,forestformer3d,treeisonet,treeiso] [OUT_DIR=...]
#   [DATA_DIR=work/external/fgiemit/source] [EVAL_PYTHON=python3]
.bs_ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (!is.null(.bs_ofile)) file.path(dirname(.bs_ofile), "bootstrap.R"),
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_ofile, .bs_file)
suppressMessages({ library(lidR); library(data.table) })
source(.find("model_runner.R")); source(.find("io_bridge.R"))
source(.find("external_fgiemit_lib.R"))
options(lidR.progress = FALSE, lidR.verbose = FALSE)

fgi_options <- function(args = commandArgs(TRUE)) {
  pieces <- strsplit(args, "=", fixed = TRUE)
  if (length(pieces) && any(lengths(pieces) != 2L)) stop("Use KEY=VALUE arguments")
  a <- setNames(lapply(pieces, `[`, 2L), vapply(pieces, `[`, character(1), 1L))
  get <- function(k, default) if (is.null(a[[k]])) default else a[[k]]
  root <- file.path(.job_dir(), "external", "fgiemit")
  split <- get("SPLIT", "test")
  list(data = normalizePath(get("DATA_DIR", file.path(root, "source")), mustWork = TRUE),
       out = normalizePath(get("OUT_DIR", if (split == "test") root else
         file.path(root, split)), mustWork = FALSE),
       split = split, plots = if (get("PLOTS", "ALL") == "ALL") NULL else
         strsplit(a$PLOTS, ",", fixed = TRUE)[[1]],
       arms = strsplit(get("ARMS", "segmentanytree,forestformer3d,treeisonet,treeiso"),
                        ",", fixed = TRUE)[[1]],
       eval_python = get("EVAL_PYTHON", "python3"),
       treeiso_python = path.expand(get("TREEISO_PYTHON", "~/miniconda3/envs/treeiso/bin/python")),
       timeout = as.numeric(get("TIMEOUT", "3600")))
}

fgi_resources <- function(opt) {
  gpu <- file.path(.ROOT, "gpu")
  repo <- normalizePath(file.path(gpu, "store", "forestformer3d", "ForestFormer3D"), mustWork = FALSE)
  box <- normalizePath(file.path(gpu, "store", "treeaibox"), mustWork = FALSE)
  list(sat_driver = file.path(gpu, "run_segmentanytree.py"),
       ff_entry = file.path(gpu, "forestformer3d-sm120", "ff3d_entry.sh"),
       ff_driver = file.path(gpu, "forestformer3d-sm120", "ff3d_arm.py"),
       ff_patch = file.path(gpu, "forestformer3d-sm120", "ff3d_repo.patch"),
       ff_repo = repo, ff_ckpt = file.path(repo, "work_dirs/clean_forestformer/epoch_3000_fix.pth"),
       ti_python = file.path(gpu, ".venv", "bin", "python"),
       ti_driver = file.path(gpu, "run_treeisonet_crowns.py"),
       loc = file.path(box, "als_treeloc.pth"), off = file.path(box, "als_treeoff.pth"),
       lcfg = Sys.glob(file.path(box, "*reclamation*treeloc*.json"))[1],
       ocfg = Sys.glob(file.path(box, "*reclamation*treeoff*.json"))[1],
       treeiso_driver = file.path(.ROOT, "external", "treeiso", "run_treeiso.py"),
       reference_driver = file.path(gpu, "prepare_fgiemit_reference.py"),
       evaluator = file.path(gpu, "evaluate_fgiemit.py"))
}

fgi_image_id <- function(image) {
  out <- system2("docker", shQuote(c("image", "inspect", image, "--format", "{{.Id}}")),
                 stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(out, "status")) || length(out) != 1L || !startsWith(out, "sha256:"))
    stop("Missing Docker image: ", image)
  out
}

fgi_provenance <- function(opt, resources) {
  files <- c(.find("detect_external_fgiemit.R"), .find("external_fgiemit_lib.R"),
             .find("model_bench_lib.R"), .find("model_runner.R"), .find("io_bridge.R"),
             file.path(opt$data, "plot_data.yaml"), resources$evaluator, resources$reference_driver,
             list.files(file.path(opt$data, "accuracy"), "[.]py$", full.names = TRUE),
             file.path(opt$data, "accuracy", "cfgs", "accuracy.yaml"))
  images <- list()
  if ("segmentanytree" %in% opt$arms) {
    images$segmentanytree <- fgi_image_id("sat-sm120-test")
    files <- c(files, resources$sat_driver,
      list.files(file.path(.ROOT, "gpu", "sat_compat"), "[.]py$", full.names = TRUE))
  }
  if ("forestformer3d" %in% opt$arms) {
    images$forestformer3d <- fgi_image_id("ff3d-sm120")
    files <- c(files, resources$ff_entry, resources$ff_driver, resources$ff_patch,
                resources$ff_ckpt,
                list.files(file.path(resources$ff_repo, "configs"), "[.]py$",
                           recursive = TRUE, full.names = TRUE),
                list.files(file.path(resources$ff_repo, "oneformer3d"), "[.]py$",
                           recursive = TRUE, full.names = TRUE),
                list.files(file.path(resources$ff_repo, "tools"), "[.]py$",
                           recursive = TRUE, full.names = TRUE))
  }
  if ("treeisonet" %in% opt$arms)
    files <- c(files, resources$ti_driver, resources$loc, resources$off,
               resources$lcfg, resources$ocfg,
               list.files(file.path(.ROOT, "gpu/TreeAIBox/modules/treeisonet"),
                          "[.]py$", recursive = TRUE, full.names = TRUE))
  if ("treeiso" %in% opt$arms)
    files <- c(files, resources$treeiso_driver, file.path(.ROOT, "external/treeiso/treeiso.py"))
  if (anyNA(files) || any(!file.exists(files))) stop("Missing model or evaluator resource")
  versions <- vapply(c("lidR", "dbscan", "data.table", "yaml"),
                      function(p) as.character(utils::packageVersion(p)), character(1))
  list(protocol = "fgi-emit-19351234-native-xyz-v1", split = opt$split, arms = opt$arms,
       images = images, file_md5 = as.list(tools::md5sum(files)),
       package_versions = as.list(versions),
       parameters = list(transfer_xyz_m = 0.5, iou_gate = 0.5, min_points = 40L,
         min_vertical_extent_m = 1.5, treeisonet_conf = 0.22, treeisonet_hmin = 2,
         treeisonet_voxel = 0, ff_radius_m = 16, ff_spacing_m = 24, ff_merge_m = 2,
         ground = "CSF defaults, then TIN normalization", input_features = "XYZ only"))
}

fgi_prepare <- function(ref, directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  raw <- lidR::LAS(fgi_model_points(as.data.frame(ref@data)))
  raw <- lidR::classify_ground(raw, lidR::csf())
  if (sum(raw$Classification == 2L) < 10L) stop("Insufficient geometrically classified ground")
  normalized <- lidR::normalize_height(raw, lidR::tin(), na.rm = FALSE)
  if (lidR::npoints(normalized) != lidR::npoints(raw) || any(!is.finite(normalized$Z)))
    stop("Height normalization changed the scoring substrate")
  if (!identical(normalized$X, raw$X) || !identical(normalized$Y, raw$Y))
    stop("Height normalization reordered the scoring substrate")
  paths <- list(raw = file.path(directory, "raw.laz"),
                normalized = file.path(directory, "normalized.laz"),
                classical = file.path(directory, "classical.laz"))
  lidR::writeLAS(raw, paths$raw); lidR::writeLAS(normalized, paths$normalized)
  classical <- raw[!ref$Classification %in% 2:4]
  lidR::writeLAS(classical, paths$classical)
  paths$query <- as.data.frame(normalized@data[, .(X, Y, Z)])
  paths$ground_points <- sum(raw$Classification == 2L)
  paths
}

fgi_ff_points <- function(path) {
  las <- lidR::readLAS(path)
  if (is.null(las) || !all(c("UserData", "PointSourceID") %in% names(las@data)))
    stop("Invalid ForestFormer3D instance cloud")
  d <- as.data.frame(las@data)
  src <- data.frame(block = d$UserData, inst = d$PointSourceID, X = d$X, Y = d$Y, Z = d$Z)
  rel <- dedup_blocks(src, merge_tol = 2)
  mapping <- unique(rel[, c("block", "inst", "global_id")])
  key <- function(x) paste(x$block, x$inst, sep = ":")
  src$crown_id <- mapping$global_id[match(key(src), key(mapping))]
  src[, c("X", "Y", "Z", "crown_id")]
}

fgi_run_arm <- function(arm, prep, directory, opt, resources, images) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  if (arm == "treeisonet") {
    return(run_python_crown_arm(resources$ti_python, resources$ti_driver,
      prep$normalized, file.path(directory, "crowns.csv"),
      extra = c(resources$loc, resources$lcfg, resources$off, resources$ocfg,
                "0", "0.22", "2"), timeout = opt$timeout, label = arm))
  }
  output <- file.path(directory, "predictions.laz")
  if (arm == "treeiso") {
    if (file.exists(output)) unlink(output)
    code <- system2(opt$treeiso_python,
      shQuote(c(resources$treeiso_driver, prep$classical, output)),
      stdout = file.path(directory, "inference.log"), stderr = "", timeout = opt$timeout)
    if (code != 0L || !file.exists(output)) return(NULL)
    return(read_instance_points_laz(output, "treeiso"))
  }
  if (arm == "segmentanytree") {
    input <- file.path(directory, "input.ply")
    laz_to_ply(prep$raw, input)
    ok <- run_docker_arm(images[[arm]], input, output,
      cmd = c("python3", resources$sat_driver), mounts = dirname(resources$sat_driver),
      extra_docker = c("--shm-size=8g", "--ipc=host"), timeout = opt$timeout,
      label = arm, reader = function(p) read_instances_laz(p, "PredInstance"))
    if (is.null(ok)) return(NULL)
    return(read_instance_points_laz(output, "PredInstance"))
  }
  if (arm != "forestformer3d") stop("Unknown detector arm: ", arm)
  input <- file.path(directory, "cylinders"); dir.create(input, showWarnings = FALSE)
  raw <- lidR::readLAS(prep$raw)
  xs <- seq(min(raw$X), max(raw$X), length.out = ceiling(diff(range(raw$X)) / 24) + 1L)
  ys <- seq(min(raw$Y), max(raw$Y), length.out = ceiling(diff(range(raw$Y)) / 24) + 1L)
  centers <- expand.grid(x = xs, y = ys); nc <- 0L
  for (i in seq_len(nrow(centers))) {
    cyl <- lidR::clip_circle(raw, centers$x[i], centers$y[i], 16)
    if (is.null(cyl) || lidR::npoints(cyl) < 50L) next
    lidR::writeLAS(cyl, file.path(input, sprintf("cyl_%03d.laz", nc))); nc <- nc + 1L
  }
  if (!nc) stop("No usable ForestFormer3D cylinders")
  # The upstream driver writes data/ and work_dirs/ inside its checkout.
  # Give this cell its own code copy so existing benchmark runs stay untouched.
  model_dir <- file.path(directory, "model")
  dir.create(model_dir, showWarnings = FALSE)
  copied <- system2("rsync", shQuote(c("-a", "--exclude=.git", "--exclude=data",
    "--exclude=work_dirs", "--exclude=__pycache__", paste0(resources$ff_repo, "/"),
    paste0(model_dir, "/"))))
  if (copied != 0L) stop("Cannot isolate ForestFormer3D workspace")
  ok <- run_docker_arm(images[[arm]], input, output, cmd = c("bash", resources$ff_entry),
    extra = c(resources$ff_ckpt, model_dir, resources$ff_patch, resources$ff_driver),
    mounts = c(model_dir, dirname(resources$ff_ckpt), dirname(resources$ff_entry)),
    timeout = opt$timeout, label = arm, reader = ff3d_collapse)
  if (is.null(ok)) return(NULL)
  fgi_ff_points(output)
}

fgi_official_check <- function(summary, opt, resources) {
  for (i in seq_len(nrow(summary))) {
    arm <- summary$arm[i]
    output <- file.path(opt$out, paste0("official_", arm, ".json"))
    if (file.exists(output)) unlink(output)
    status <- system2(opt$eval_python, shQuote(c(resources$evaluator,
      "--accuracy-dir", file.path(opt$data, "accuracy"),
      "--metadata-dir", opt$data, "--data-dir", file.path(opt$out, "instances", arm),
      "--split", opt$split, "--plots", summary$plots[i], "--out", output)),
      stdout = file.path(opt$out, paste0("official_", arm, ".log")), stderr = "")
    if (status != 0L || !file.exists(output)) stop("Official evaluator failed for ", arm)
    official <- jsonlite::read_json(output, simplifyVector = TRUE)
    keys <- c(precision = "precision", recall = "recall", f1 = "F1", cov = "coverage",
              recall_a = "rec_A", recall_b = "rec_B", recall_c = "rec_C", recall_d = "rec_D")
    for (k in intersect(names(keys), names(official)))
      if (!isTRUE(all.equal(as.numeric(official[[k]]) / 100,
                            as.numeric(summary[[keys[[k]]]][i]), tolerance = 1e-8)))
        stop("Official/repository metric disagreement: ", arm, "/", k)
  }
}

run_main <- function() {
  opt <- fgi_options(); resources <- fgi_resources(opt)
  valid_arms <- c("segmentanytree", "forestformer3d", "treeisonet", "treeiso")
  if (!length(opt$arms) || anyDuplicated(opt$arms) || !all(opt$arms %in% valid_arms))
    stop("ARMS must name unique supported detectors")
  if (!is.finite(opt$timeout) || opt$timeout <= 0) stop("TIMEOUT must be positive")
  metadata <- yaml::read_yaml(file.path(opt$data, "plot_data.yaml"))
  plots <- fgi_plots(metadata, opt$split, opt$plots)
  inputs <- file.path(opt$data, opt$split, paste0("plot_", plots, ".las"))
  if (any(!file.exists(inputs))) stop("Missing input plots: ", paste(inputs[!file.exists(inputs)], collapse = ", "))
  dir.create(opt$out, recursive = TRUE, showWarnings = FALSE)
  provenance <- fgi_provenance(opt, resources)
  manifest <- file.path(opt$out, "run_manifest.rds")
  if (!fgi_manifest(manifest, provenance)) {
    saveRDS(provenance, manifest)
    jsonlite::write_json(provenance, file.path(opt$out, "run_manifest.json"),
                         auto_unbox = TRUE, pretty = TRUE)
  }
  scores <- list(); states <- list()
  for (pid in plots) {
    cat("Preparing ", opt$split, "/", pid, "\n", sep = "")
    input <- file.path(opt$data, opt$split, paste0("plot_", pid, ".las"))
    input_md5 <- unname(tools::md5sum(input))
    ref_path <- file.path(opt$out, "references", paste0("plot_", pid, ".laz"))
    dir.create(dirname(ref_path), recursive = TRUE, showWarnings = FALSE)
    prepared <- system2(opt$eval_python,
      shQuote(c(resources$reference_driver, input, ref_path)))
    if (prepared != 0L) stop("Cannot prepare reference labels: ", input)
    ref <- lidR::readLAS(ref_path)
    if (is.null(ref) || lidR::is.empty(ref)) stop("Empty reference: ", input)
    classes <- fgi_reference_classes(as.data.frame(ref@data), metadata[[pid]])
    ref <- ref[ref$Classification != 5L]
    points <- as.data.frame(ref@data[, .(X, Y, Z, Classification, tree_index)])
    prep <- NULL
    for (arm in opt$arms) {
      directory <- file.path(opt$out, "runs", pid, arm)
      cache <- file.path(directory, "score.rds")
      labeled <- file.path(opt$out, "instances", arm, opt$split, paste0("plot_", pid, ".laz"))
      t0 <- Sys.time()
      result <- tryCatch({
        if (file.exists(cache)) {
          old <- readRDS(cache)
          if (!identical(old$input_md5, input_md5) || !file.exists(labeled) ||
              !identical(old$output_md5, unname(tools::md5sum(labeled))))
            stop("Cached input/output checksum changed; use a new OUT_DIR")
          old$score
        } else {
          if (is.null(prep)) prep <- fgi_prepare(ref, file.path(opt$out, "prepared", pid))
          src <- fgi_run_arm(arm, prep, directory, opt, resources, provenance$images)
          if (is.null(src)) stop("Inference failed or produced invalid instance output")
          query <- if (arm == "treeisonet") prep$query else points
          transfer <- fgi_transfer_labels(src, query)
          if (nrow(src) && !any(is.finite(transfer$distance) & transfer$distance <= 0.5))
            stop("Prediction coordinate frame does not overlap the reference")
          scored <- fgi_score(transfer$labels, points, classes)
          det <- reduce_instances(src)
          scored$score <- cbind(data.frame(plot = pid, split = opt$split, arm = arm,
            input_md5 = input_md5, n_points = nrow(points), n_apex = nrow(det),
            transferred_fraction = mean(transfer$distance <= 0.5),
            ground_points = prep$ground_points,
            seconds = as.numeric(difftime(Sys.time(), t0, units = "secs"))), scored$score)
          export <- lidR::add_lasattribute(ref, ifelse(is.na(scored$pred), 0L, scored$pred),
                                           "tree_pred", "Predicted instance, zero is background")
          dir.create(dirname(labeled), recursive = TRUE, showWarnings = FALSE)
          lidR::writeLAS(export, labeled)
          saveRDS(list(input_md5 = input_md5, output_md5 = unname(tools::md5sum(labeled)),
                       score = scored$score), cache)
          scored$score
        }
      }, error = function(e) {
        message(pid, "/", arm, ": ", conditionMessage(e)); conditionMessage(e)
      })
      ok <- is.data.frame(result)
      states[[length(states) + 1L]] <- data.frame(plot = pid, arm = arm,
        status = if (ok) "ok" else "failed", error = if (ok) "" else result)
      if (ok) scores[[length(scores) + 1L]] <- result
      write.csv(rbindlist(states), file.path(opt$out, "status.csv"), row.names = FALSE)
      write.csv(rbindlist(scores), file.path(opt$out, "scores.csv"), row.names = FALSE)
      cat(pid, arm, if (ok) sprintf("TP=%d/%d F1=%.3f", result$TP, result$n_ref, result$F1) else "failed", "\n")
    }
    rm(ref, points, prep); gc()
  }
  summary <- fgi_summary(as.data.frame(rbindlist(scores)), opt$arms)
  if (is.null(summary)) summary <- data.frame()
  write.csv(summary, file.path(opt$out, "summary.csv"), row.names = FALSE)
  if (nrow(summary)) fgi_official_check(summary, opt, resources)
  if (any(vapply(states, function(s) s$status != "ok", logical(1))))
    stop("Some requested cells failed; see status.csv. Failures were not scored as empty detections.")
  print(summary)
}

if (sys.nframe() == 0L) run_main()
