#!/usr/bin/env Rscript
# Synthetic contracts only. INPUT is an optional trusted local RDS bundle.
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
  if (anyDuplicated(keys) || any(!keys %in% c("MODE", "INPUT", "OUT"))) stop("Unknown or duplicate argument")
  a <- setNames(as.list(sub("^[^=]+=", "", args)), keys)
  if (!is.null(a$MODE) && a$MODE != "synthetic") stop("MODE must be synthetic")
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
  code <- c("assemble_metapipeline.R", "metapipeline_lib.R", "metapipeline_synthetic.R",
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
