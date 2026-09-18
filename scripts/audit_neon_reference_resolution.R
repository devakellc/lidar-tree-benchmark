#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_reference_support_lib.R"))
source(.find("neon_reference_resolution_lib.R"))
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$SOURCE) || is.null(A$SUPPORT) || is.null(A$EVIDENCE))
  stop("SOURCE, SUPPORT and EVIDENCE must name the existing read-only snapshots")
root <- normalizePath(A$SOURCE, mustWork = TRUE)
support_root <- normalizePath(A$SUPPORT, mustWork = TRUE)
evidence <- normalizePath(A$EVIDENCE, mustWork = TRUE)
out <- if (is.null(A$OUT)) file.path(.job_dir(), "reference_resolution") else A$OUT
out <- file.path(normalizePath(dirname(out), mustWork = TRUE), basename(out))
protected <- c(file.path(root, "neon"), support_root, evidence)
if (any(out == protected | startsWith(out, paste0(protected, "/"))))
  stop("OUT must be separate from protected input directories")
sources <- c(file.path(evidence, "completion.json"),
             neon_verify_receipt(file.path(evidence, "completion.json")))
sites <- c("HARV", "BART")
for (site in sites) {
  d <- file.path(support_root, site)
  paths <- file.path(d, c("input_contract.json", "completion.json"))
  for (p in paths) sources <- c(sources, p, neon_verify_receipt(p))
  input <- normalizePath(file.path(root, "neon", site, "vst", paste0(tolower(site), "_vst_allyears.rds")))
  declared <- jsonlite::read_json(paths[1], simplifyVector = TRUE)$files
  if (!input %in% normalizePath(declared)) stop("SOURCE differs from prepared reference inputs")
}
code <- vapply(c("audit_neon_reference_resolution.R", "neon_reference_resolution_lib.R",
                 "neon_reference_support_lib.R", "neon_spatial_lib.R"), .find, character(1))
sources <- sort(unique(c(sources, code, file.path(.ROOT, "docs/neon-reference-resolution-protocol.md"))))
before <- unname(tools::md5sum(sources))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
neon_check_manifest(file.path(out, "input_contract.json"),
  list(schema = 1L, files = sources, md5 = before, software = neon_support_software(),
       audit_only = TRUE, gps_utc_offset_seconds_2022 = 18L))
receipt <- file.path(out, "completion.json")
if (file.exists(receipt)) {
  neon_verify_receipt(receipt)
  cat("Resolution audit replay passed; inputs and outputs unchanged.\n")
  quit(status = 0L)
}
results <- list(); bundle_sets <- list()
for (site in sites) {
  d <- file.path(support_root, site)
  bundles <- readRDS(file.path(d, "support_bundles.rds"))
  dat <- readRDS(file.path(root, "neon", site, "vst", paste0(tolower(site), "_vst_allyears.rds")))
  a <- read.csv(file.path(d, "reference_audit.csv"))
  if (any(vapply(bundles, function(b) isTRUE(b$evaluation_ready), logical(1))))
    stop("This audit expects the diagnostic support snapshot")
  results[[site]] <- neon_reference_resolution(a, dat$vst_mappingandtagging, bundles)
  bundle_sets[[site]] <- bundles
}
for (kind in c("records", "members", "plots")) {
  rows <- do.call(rbind, lapply(sites, function(s) cbind(site = s, results[[s]][[kind]])))
  write.csv(rows, file.path(out, paste0("resolution_", kind, ".csv")), row.names = FALSE)
}
dates <- read.csv(file.path(evidence, "flight_dates.csv"), colClasses = "character")
neon_support_require(dates, c("siteID", "visitNumber", "flightDate"), "Flight dates")
dates <- dates[dates$siteID %in% sites & substr(dates$flightDate, 1, 4) == "2022", ]
write.csv(dates, file.path(out, "published_flight_dates.csv"), row.names = FALSE)
b <- bundle_sets$HARV[["HARV_033::vst_HARV_2022"]]
if (is.null(b)) stop("Predeclared HARV event is absent")
region <- sf::st_buffer(b$footprint, 25)
paths <- list.files(evidence, "[.]kml$", full.names = TRUE)
if (!length(paths)) stop("Missing HARV flightline evidence")
lines <- lapply(paths, function(path) {
  id <- neon_flight_identity(basename(path))
  g <- sf::st_read(path, quiet = TRUE)
  g <- neon_flight_enclosure(g, b$epsg)
  name <- sub("DPQA", "DP1", sub("_boundary[.]kml$", "_unclassified_point_cloud.header.laz", basename(path)))
  header_path <- file.path(evidence, "flight_headers", name)
  if (!file.exists(header_path)) stop("Missing flightline header excerpt")
  h <- lidR::readLASheader(header_path)
  invisible(neon_assert_crs(h, b$epsg, "Flightline header"))
  source_id <- h@PHB[["File Source ID"]]
  if (length(source_id) != 1L || !is.finite(source_id)) stop("Missing File Source ID")
  data.frame(file = basename(path), line = id$line, date = as.character(id$date),
    file_source_id = source_id,
    intersects_sampled = any(lengths(sf::st_intersects(b$footprint, g)) > 0),
    intersects_buffer = any(lengths(sf::st_intersects(region, g)) > 0),
    contribution_proven = FALSE)
})
lines <- do.call(rbind, lines)
write.csv(lines, file.path(out, "HARV_033_flightline_candidates.csv"), row.names = FALSE)
laz <- file.path(evidence, "NEON_D01_HARV_DP1_731000_4713000_classified_point_cloud_colorized.laz")
if (file.exists(laz)) {
  header <- lidR::readLASheader(laz)
  invisible(neon_assert_crs(header, b$epsg, "HARV provenance tile"))
  if (!identical(header@PHB[["Global Encoding"]][["GPS Time Type"]], FALSE))
    stop("Expected GPS week time in the pinned HARV tile")
  bb <- sf::st_bbox(region)
  cloud <- lidR::readLAS(laz, filter = sprintf("-keep_xy %.6f %.6f %.6f %.6f", bb[1], bb[2], bb[3], bb[4]))
  if (is.null(cloud) || !lidR::npoints(cloud)) stop("HARV provenance clip is empty")
  points <- as.data.frame(cloud@data)
  neon_support_require(points, c("PointSourceID", "gpstime"), "HARV source metadata")
  points <- points[neon_support_inside(points$X, points$Y, region), ]
  published <- as.Date(substr(dates$flightDate[dates$siteID == "HARV" & dates$visitNumber == "7"], 1, 8), "%Y%m%d")
  rows <- lapply(split(points$gpstime, points$PointSourceID), function(time) {
    candidates <- neon_week_time_candidates(time, published, gps_utc_offset = 18)
    spatial <- sort(unique(lines$date[lines$intersects_buffer]))
    compatible <- intersect(as.character(candidates), spatial)
    data.frame(n_points = length(time), gps_week_min = min(time), gps_week_max = max(time),
      schedule_dates = paste(candidates, collapse = "|"),
      spatially_compatible_dates = paste(compatible, collapse = "|"),
      status = if (!length(compatible)) "inconsistent_evidence" else
        if (length(compatible) == 1L) "one_schedule_and_footprint_candidate" else "ambiguous_candidates",
      exact_point_contribution_verified = FALSE)
  })
  rows <- do.call(rbind, lapply(names(rows), function(id) cbind(point_source_id = id, rows[[id]])))
  rows$header_matched_lines <- rows$header_matched_dates <- ""
  for (i in seq_len(nrow(rows))) {
    dates_ok <- strsplit(rows$spatially_compatible_dates[i], "|", fixed = TRUE)[[1]]
    match <- neon_link_flight_source(as.numeric(rows$point_source_id[i]), dates_ok, lines)
    rows$header_matched_lines[i] <- match$lines
    rows$header_matched_dates[i] <- match$dates
    rows$exact_point_contribution_verified[i] <- match$verified
    if (rows$exact_point_contribution_verified[i]) rows$status[i] <- "source_header_and_time_consistent"
  }
  write.csv(rows, file.path(out, "HARV_033_point_source_time_audit.csv"), row.names = FALSE)
}
after <- unname(tools::md5sum(sources))
if (!identical(before, after)) stop("Protected inputs changed during the audit")
jsonlite::write_json(list(protected_files_hashed = length(sources), integrity = "unchanged",
  source_values_changed = FALSE, detector_runs = 0L, evaluation_ready = FALSE,
  spatial_scope = "HARV_033 only; BART field metadata only"), file.path(out, "integrity_summary.json"),
  auto_unbox = TRUE, pretty = TRUE)
outputs <- sort(list.files(out, "[.]csv$|^integrity_summary[.]json$", full.names = TRUE))
neon_check_manifest(receipt, list(files = outputs, md5 = unname(tools::md5sum(outputs))))
for (s in sites) { cat(s, "\n"); print(table(results[[s]]$records$classification)) }
cat("Exclusions explained, not admitted. No source measurements or scoring supports were changed.\n")
