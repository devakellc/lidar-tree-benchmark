#!/usr/bin/env Rscript
# Download the immutable public release; verify every archive before extraction.
# Usage: Rscript scripts/download_external_fgiemit.R [SPLITS=test,training]
bs <- Find(file.exists, c("scripts/bootstrap.R", "../../scripts/bootstrap.R"))
if (!length(bs)) stop("Run from the repository root")
source(bs[1])

fgi_download <- function(destination, splits = "test") {
  if (!length(splits) || !all(splits %in% c("test", "training")))
    stop("SPLITS must contain test and/or training")
  checksums <- c("plot_data.yaml" = "0e5f69c28be31374bb3cf8faa03bded0",
                 "accuracy.zip" = "368c1b7228b1ca63ae16eae3dddc8388",
                 "test.zip" = "c67b80c1e7f8a2ea28f54ed364aceea2",
                 "training.zip" = "b1c5ee7e9c166dd7ff377539944e5002")
  files <- c("plot_data.yaml", "accuracy.zip", paste0(unique(splits), ".zip"))
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  old_timeout <- getOption("timeout"); on.exit(options(timeout = old_timeout))
  options(timeout = max(3600, old_timeout))
  for (name in files) {
    target <- file.path(destination, name)
    if (!file.exists(target)) {
      partial <- paste0(target, ".part")
      url <- paste0("https://zenodo.org/api/records/19351234/files/", name, "/content")
      utils::download.file(url, partial, mode = "wb")
      if (unname(tools::md5sum(partial)) != checksums[[name]])
        stop("Checksum mismatch: ", partial)
      if (!file.rename(partial, target)) stop("Cannot finalize download: ", target)
    }
    if (unname(tools::md5sum(target)) != checksums[[name]])
      stop("Checksum mismatch: ", target, "; existing data was not overwritten")
    if (endsWith(name, ".zip")) utils::unzip(target, exdir = destination)
    cat("Verified ", name, "\n", sep = "")
  }
  jsonlite::write_json(list(record = "https://doi.org/10.5281/zenodo.19351234",
    license = "CC-BY-NC-SA-4.0", md5 = as.list(checksums[files])),
    file.path(destination, "source_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
}

run_main <- function() {
  args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
  a <- setNames(lapply(args, `[`, 2L), vapply(args, `[`, character(1), 1L))
  splits <- if (is.null(a$SPLITS)) "test" else strsplit(a$SPLITS, ",", fixed = TRUE)[[1]]
  destination <- if (is.null(a$DATA_DIR)) file.path(.job_dir(), "external/fgiemit/source") else a$DATA_DIR
  fgi_download(destination, splits)
}

if (sys.nframe() == 0L) run_main()
