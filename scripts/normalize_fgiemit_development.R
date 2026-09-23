#!/usr/bin/env Rscript
# Geometric normalization only; the Python driver supplies label-free inputs.
normalize_fgi_development <- function(input, output, receipt) {
  if (any(file.exists(c(output, receipt)))) stop("Preserve existing outputs")
  suppressPackageStartupMessages(library(lidR))
  lidR::set_lidr_threads(1L)
  options(lidR.progress = FALSE, lidR.verbose = FALSE)
  raw <- lidR::readLAS(input)
  required <- c("X", "Y", "Z", "source_row", "ReturnNumber", "NumberOfReturns")
  if (is.null(raw) || !all(required %in% names(raw@data)) ||
      any(raw$Classification != 1L) || "tree_index" %in% names(raw@data))
    stop("Expected label-free geometry with original return fields and row IDs")
  before <- data.table::copy(raw@data[, ..required])
  ground <- lidR::classify_ground(raw, lidR::csf(), last_returns = FALSE)
  n_ground <- sum(ground$Classification == 2L)
  if (n_ground < 10L) stop("Insufficient geometrically classified ground")
  normalized <- lidR::normalize_height(ground, lidR::tin(), na.rm = FALSE)
  exact <- setdiff(required, "Z")
  if (lidR::npoints(normalized) != nrow(before) ||
      !identical(as.data.frame(normalized@data[, ..exact]),
                 as.data.frame(before[, ..exact])) ||
      any(!is.finite(normalized$Z)))
    stop("Normalization changed row identity or produced invalid heights")
  lidR::writeLAS(normalized, output)
  jsonlite::write_json(list(method = "CSF defaults, all returns; TIN default edge extrapolation",
    lidR = as.character(utils::packageVersion("lidR")),
    RCSF = as.character(utils::packageVersion("RCSF")),
    threads = 1L, rows = lidR::npoints(normalized), ground_points = n_ground,
    independently_validated_AGL = FALSE), receipt, auto_unbox = TRUE, pretty = TRUE)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(TRUE)
  if (length(args) != 3L) stop("Usage: INPUT.las OUTPUT.laz RECEIPT.json")
  normalize_fgi_development(args[1], args[2], args[3])
}
