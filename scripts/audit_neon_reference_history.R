#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_reference_support_lib.R"))
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$SOURCE)) stop("SOURCE must name the historical job directory; it is read-only")
source_root <- normalizePath(A$SOURCE, mustWork = TRUE)
out <- if (is.null(A$OUT)) file.path(.job_dir(), "reference_support_history") else A$OUT
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(out, mustWork = TRUE)
sites <- c("SJER", "SOAP", "TEAK")
roots <- file.path(source_root, "neon", sites)
if (any(out == roots | startsWith(out, paste0(roots, "/")))) stop("OUT must not modify historical site directories")
protected <- sort(list.files(c(roots, file.path(source_root, "external/fgiemit")),
                             recursive = TRUE, full.names = TRUE))
snapshot <- function() {
  info <- file.info(protected)
  small <- !is.na(info$size) & info$size <= 20 * 1024^2 & grepl("[.](csv|json|rds)$", protected)
  hashes <- rep(NA_character_, length(protected))
  hashes[small] <- unname(tools::md5sum(protected[small]))
  data.frame(path = protected, bytes = info$size, mtime = as.numeric(info$mtime), md5 = hashes)
}
before <- snapshot()
inputs <- unlist(lapply(sites, function(site) file.path(source_root, "neon", site,
  c("ground_truth_stems.csv", "plot_centroids.csv", paste0("vst/", tolower(site), "_vst_allyears.rds")))))
if (!all(file.exists(inputs))) stop("Historical field inputs are incomplete")
sources <- c(inputs, .find("audit_neon_reference_history.R"), .find("neon_reference_support_lib.R"))
neon_check_manifest(file.path(out, "input_contract.json"),
  list(files = sources, md5 = unname(tools::md5sum(sources)), detector_rescored = FALSE))
rows <- lapply(sites, function(site) {
  nd <- file.path(source_root, "neon", site)
  neon_historical_support(read.csv(file.path(nd, "ground_truth_stems.csv")),
    read.csv(file.path(nd, "plot_centroids.csv")),
    readRDS(file.path(nd, "vst", paste0(tolower(site), "_vst_allyears.rds"))), site)
})
audit <- do.call(rbind, rows)
after <- snapshot()
if (!identical(before, after)) stop("Historical artifact metadata or small-file hashes changed during audit")
write.csv(audit, file.path(out, "historical_support_audit.csv"), row.names = FALSE)
write.csv(before, file.path(out, "protected_artifact_inventory.csv"), row.names = FALSE)
jsonlite::write_json(list(files_checked = nrow(before), content_hashes_checked = sum(!is.na(before$md5)),
  integrity = "unchanged", detector_rescored = FALSE), file.path(out, "integrity_summary.json"),
  auto_unbox = TRUE, pretty = TRUE)
print(aggregate(n_historical_core ~ site + status, audit, sum), row.names = FALSE)
cat("Historical inputs, cached predictions and published metrics were not modified or rescored.\n")
