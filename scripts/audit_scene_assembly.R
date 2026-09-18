#!/usr/bin/env Rscript
# Whole-scene inference on the two predeclared training plots; no fallback.
source("scripts/detect_external_fgiemit.R")
source(.find("transfer_audit_lib.R"))

scene_baseline <- function(root, pid) {
  if (pid == "1001") file.path(root, "training") else file.path(root, "audit/baseline_1019")
}

scene_verify <- function(root, python) {
  status <- system2(python, shQuote(c(file.path(.ROOT, "gpu/declare_scene_assembly.py"),
                                     "--root", root, "--verify")))
  if (status != 0L) stop("Scene declaration/integrity check failed")
}

scene_infer <- function(root, plots, python) {
  opt <- fgi_options(c("SPLIT=training", "ARMS=forestformer3d", "FF_LAYOUT=whole_scene",
    paste0("DATA_DIR=", root, "/source"), paste0("OUT_DIR=", root, "/scene_assembly")))
  res <- fgi_resources(opt)
  provenance <- fgi_provenance(opt, res)
  provenance$protocol <- "forestformer-native-whole-scene-v1"
  provenance$declared_plots <- c("1001", "1019")
  extra <- c(.find("audit_scene_assembly.R"), .find("transfer_audit_lib.R"),
    file.path(.ROOT, "gpu/declare_scene_assembly.py"),
    file.path(.ROOT, "gpu/declare_transfer_audit.py"),
    file.path(.ROOT, "docs/forestformer-scene-assembly-protocol.md"),
    file.path(opt$out, "declaration.json"))
  provenance$scene_files <- as.list(tools::md5sum(extra))
  prepared <- vapply(provenance$declared_plots, function(pid)
    file.path(scene_baseline(root, pid), "prepared", pid, "raw.laz"), character(1))
  if (any(!file.exists(prepared))) stop("Missing frozen plot preparation")
  provenance$prepared_md5 <- as.list(tools::md5sum(unname(prepared)))
  manifest <- file.path(opt$out, "run_manifest.rds")
  if (!fgi_manifest(manifest, provenance)) {
    saveRDS(provenance, manifest)
    jsonlite::write_json(provenance, file.path(opt$out, "run_manifest.json"),
                         auto_unbox = TRUE, pretty = TRUE)
  }
  for (pid in plots) {
    directory <- file.path(opt$out, "runs", pid, "forestformer3d")
    receipt <- file.path(directory, "receipt.rds")
    if (file.exists(receipt)) {
      audit_verify_hashes(readRDS(receipt)$output_md5)
      cat(pid, "verified cached whole-scene output\n")
      next
    }
    if (dir.exists(directory)) stop("Unreceipted attempt exists; preserve it and investigate: ", directory)
    t0 <- Sys.time()
    result <- tryCatch({
      src <- fgi_run_arm("forestformer3d", list(raw = prepared[[pid]]), directory,
                          opt, res, provenance$images)
      if (is.null(src)) stop("Whole-scene inference failed; no outer-cylinder fallback")
      raw <- lidR::readLAS(prepared[[pid]])
      fgi_indexed_labels(src, as.data.frame(raw@data), tol = 0)
      audit_verify_hashes(provenance$prepared_md5)
      outputs <- file.path(directory, c("predictions.laz", "predictions.laz.json"))
      if (any(!file.exists(outputs))) stop("Incomplete whole-scene export")
      saved <- list(output_md5 = as.list(tools::md5sum(outputs)),
        input_md5 = unname(tools::md5sum(prepared[[pid]])), rows = nrow(src),
        seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")))
      saveRDS(saved, receipt)
      jsonlite::write_json(saved, file.path(directory, "receipt.json"),
                           auto_unbox = TRUE, pretty = TRUE)
      cat(pid, "whole-scene complete:", saved$rows, "rows in", saved$seconds, "seconds\n")
      TRUE
    }, error = function(e) {
      dir.create(directory, recursive = TRUE, showWarnings = FALSE)
      jsonlite::write_json(list(error = conditionMessage(e),
        seconds = as.numeric(difftime(Sys.time(), t0, units = "secs"))),
        file.path(directory, "failure.json"), auto_unbox = TRUE, pretty = TRUE)
      stop(e)
    })
    gc()
  }
}

scene_main <- function() {
  args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
  if (any(lengths(args) != 2L)) stop("Use KEY=VALUE arguments")
  args <- setNames(lapply(args, `[`, 2L), vapply(args, `[`, character(1), 1L))
  get <- function(k, default) if (is.null(args[[k]])) default else args[[k]]
  root <- normalizePath(get("ROOT", file.path(.job_dir(), "external/fgiemit")), mustWork = TRUE)
  plots <- strsplit(get("PLOTS", "1001,1019"), ",", fixed = TRUE)[[1]]
  if (!length(plots) || anyDuplicated(plots) || !all(plots %in% c("1001", "1019")))
    stop("Scene assembly is restricted to training plots 1001 and 1019")
  python <- get("EVAL_PYTHON", "python3")
  mode <- get("MODE", "infer")
  if (!mode %in% c("infer", "analyze")) stop("MODE must be infer or analyze")
  scene_verify(root, python)
  on.exit(scene_verify(root, python))
  if (mode == "infer") scene_infer(root, plots, python) else {
    source(.find("scene_assembly_lib.R"))
    scene_analyze(root, plots, python)
  }
}

if (sys.nframe() == 0L) scene_main()
