#!/usr/bin/env Rscript
# Synthetic interfaces or the verified real FGI pipeline; modes stay separate.
.mp_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.mp_bootstrap <- Find(file.exists, c(
  if (length(.mp_file)) file.path(dirname(sub("^--file=", "", .mp_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(.mp_bootstrap)) stop("bootstrap.R not found")
source(.mp_bootstrap); rm(.mp_bootstrap, .mp_file)
source(.find("model_bench_lib.R"))
source(.find("metapipeline_lib.R"))
source(.find("metapipeline_synthetic.R"))

metapipeline_main <- function(args = commandArgs(TRUE)) {
  # Split only at the first equals sign, including for paths containing '='.
  if (any(!grepl("^[A-Z_]+=.+$", args))) stop("Use KEY=VALUE arguments")
  keys <- sub("=.*$", "", args)
  if (anyDuplicated(keys)) stop("Unknown or duplicate argument")
  a <- setNames(as.list(sub("^[^=]+=", "", args)), keys)
  if (identical(a$MODE, "fgiemit")) {
    allowed <- c("MODE", "ROOT", "PREPARED", "RUN", "OUT", "PYTHON", "STAGE", "METHOD", "EXECUTE", "VERIFY")
    if (any(!keys %in% allowed) || is.null(a$ROOT) || is.null(a$OUT))
      stop("FGI mode requires ROOT and OUT with only documented arguments")
    for (flag in c("EXECUTE", "VERIFY"))
      if (!is.null(a[[flag]]) && !a[[flag]] %in% c("true", "false")) stop(flag, " must be true or false")
    python <- if (!is.null(a$PYTHON)) a$PYTHON else Sys.getenv("FGIEMIT_PYTHON", file.path(.ROOT, "gpu/.venv/bin/python"))
    if (!file.exists(python)) stop("Set PYTHON to the existing GPU Python environment")
    command <- c(.find("run_ensemble_pipeline_v2.py"), "--root", a$ROOT, "--out", a$OUT)
    for (key in c("PREPARED", "RUN", "STAGE", "METHOD"))
      if (!is.null(a[[key]])) command <- c(command, paste0("--", tolower(key)), a[[key]])
    for (key in c("EXECUTE", "VERIFY"))
      if (identical(a[[key]], "true")) command <- c(command, paste0("--", tolower(key)))
    status <- system2(python, shQuote(command))
    if (status != 0L) stop("FGI pipeline failed or remains incomplete; inspect preserved output")
    return(invisible(status))
  }
  if (any(!keys %in% c("MODE", "INPUT", "OUT"))) stop("Unknown or duplicate argument")
  if (!is.null(a$MODE) && a$MODE != "synthetic") stop("MODE must be synthetic or fgiemit")
  bundle <- if (is.null(a$INPUT)) metapipeline_synthetic() else readRDS(a$INPUT)
  result <- assemble_metapipeline(bundle)
  out <- if (is.null(a$OUT)) file.path(.job_dir(), "metapipeline-synthetic") else path.expand(a$OUT)
  if (file.exists(out)) stop("Output exists; preserve it and choose a distinct OUT")
  if (!dir.create(out, recursive = TRUE)) stop("Cannot create output directory")
  saveRDS(result, file.path(out, "assembly.rds"), version = 3)
  for (nm in c("status", "products", "apexes", "fused"))
    write.csv(result[[nm]], file.path(out, paste0(nm, ".csv")), row.names = FALSE)
  write.csv(bundle$cells, file.path(out, "cells.csv"), row.names = FALSE)
  write.csv(bundle$arms, file.path(out, "arms.csv"), row.names = FALSE)
  outputs <- list.files(out, full.names = TRUE)
  code <- c("assemble_metapipeline_v2.R", "assemble_metapipeline.R", "metapipeline_lib.R", "metapipeline_synthetic.R",
            "model_bench_lib.R", "neon_spatial_lib.R", "neon_reference_support_lib.R",
            "bootstrap.R", "repo_paths.R")
  hashes <- function(paths) setNames(lapply(paths, function(p)
    digest::digest(file = p, algo = "sha256")), basename(paths))
  manifest <- list(schema_version = 1L, mode = "synthetic", inference_run = FALSE,
    calibration_fitted = FALSE, metrics_computed = FALSE,
    bundle_sha256 = digest::digest(bundle, algo = "sha256"),
    code_sha256 = hashes(vapply(code, .find, character(1))),
    output_sha256 = hashes(outputs), R = R.version.string,
    packages = setNames(lapply(c("sf", "lidR", "terra", "data.table", "jsonlite", "digest"),
      function(p) as.character(packageVersion(p))),
      c("sf", "lidR", "terra", "data.table", "jsonlite", "digest")))
  jsonlite::write_json(manifest, file.path(out, "manifest.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  cat("Synthetic assembly:", nrow(result$status), "arm states;",
      sum(result$products$product == "fusion" & result$products$status == "blocked"),
      "blocked fusion cells. Output:", normalizePath(out), "\n")
  invisible(result)
}

if (sys.nframe() == 0L) metapipeline_main()
