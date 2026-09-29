#!/usr/bin/env Rscript
# Offline, metadata-only TEAK_043 audit. VERIFY=1 recomputes without writing.
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.code <- file.path(dirname(.self), c(basename(.self), "repo_paths.R",
  "teak_canopy_lib.R", "teak_acquisition_timing_lib.R"))
.before <- unname(vapply(.code, digest::digest, character(1), file = TRUE, algo = "sha256"))
source(file.path(dirname(.self), "repo_paths.R"))
source(.find("teak_canopy_lib.R"))
source(.find("teak_acquisition_timing_lib.R"))
a <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(a, function(z) paste(z[-1], collapse = "=")),
              vapply(a, `[`, character(1), 1))
if (!all(c("NATIVE", "PILOT", "ARCHIVE", "OUT") %in% names(A)) ||
    anyDuplicated(names(A)) || any(!names(A) %in%
      c("NATIVE", "PILOT", "ARCHIVE", "OUT", "VERIFY")) ||
    (!is.null(A$VERIFY) && !A$VERIFY %in% c("0", "1")))
  stop("Required NATIVE=archive PILOT=accepted_run ARCHIVE=timing_sources OUT=directory [VERIFY=1]")
verify <- identical(A$VERIFY, "1")
roots <- vapply(A[c("NATIVE", "PILOT", "ARCHIVE")], normalizePath,
                character(1), mustWork = TRUE)
out <- canopy_resolve(path.expand(A$OUT))
if (any(out == roots | startsWith(out, paste0(roots, "/"))) ||
    any(startsWith(roots, paste0(out, "/"))) || (!verify && file.exists(out)))
  stop("OUT must be fresh and outside all inputs")
if (verify && !dir.exists(out)) stop("VERIFY requires an existing output directory")
mp <- file.path(.ROOT, "docs/teak-acquisition-timing-sources.json")
nmp <- file.path(.ROOT, "docs/teak-native-pilot-sources.json")
pmp <- file.path(.ROOT, "docs/teak-canopy-sources.json")
manifest_paths <- c(mp, nmp, pmp)
manifest_hashes <- canopy_hash(manifest_paths)
m <- jsonlite::fromJSON(mp)
timing_declaration(m)
nm <- jsonlite::fromJSON(nmp)
receipt_path <- file.path(roots["PILOT"], "receipt.json")
if (canopy_hash(receipt_path) != m$pilot_receipt_sha256 ||
    manifest_hashes[2] != m$native_manifest_sha256 ||
    manifest_hashes[3] != m$parent_manifest_sha256 ||
    nm$parent_manifest_sha256 != manifest_hashes[3] ||
    m$plot != "TEAK_043" || nm$plot != m$plot || nm$context_buffer_m != 25 ||
    m$gps_week != 2005 || m$gps_week_start != "2018-06-10" ||
    m$gps_minus_utc_seconds != 18) stop("Pinned declaration/parent identity mismatch")
pr <- jsonlite::fromJSON(receipt_path)
if (!identical(pr$evaluation_ready, FALSE) ||
    pr$manifest_sha256 != manifest_hashes[2] ||
    pr$parent_manifest_sha256 != manifest_hashes[3]) stop("Pilot receipt linkage mismatch")
timing_check_files(roots["PILOT"], pr$outputs, exact = TRUE, extras = "receipt.json")
timing_check_files(roots["ARCHIVE"], m$sources)
native_rows <- nm$sources[grepl("(classified_point_cloud_colorized[.]laz|discrete_lidar_processing[.]pdf)$",
                               nm$sources$path), c("path", "bytes", "sha256")]
if (nrow(native_rows) != 3L) stop("Expected one native LAS and two report PDFs")
timing_check_files(roots["NATIVE"], native_rows)
summary <- jsonlite::fromJSON(file.path(roots["PILOT"], "pilot_summary.json"))
if (summary$plot != m$plot || summary$epsg != 32611 ||
    summary$gps_time_type != "gps_week" || !identical(summary$evaluation_ready, FALSE) ||
    !identical(summary$reference_review_complete, FALSE) || summary$detector_runs != 0 ||
    !identical(summary$role, "historical_development_pilot") ||
    any(abs(summary$context_extent - summary$core_extent - c(-25, 25, -25, 25)) > 1e-8) ||
    any(abs(diff(summary$core_extent[1:2]) - 40) > 1e-8) ||
    any(abs(diff(summary$core_extent[3:4]) - 40) > 1e-8)) stop("Pilot scope/geometry differs")
core <- timing_rectangle(summary$core_extent, summary$epsg)
context <- timing_rectangle(summary$context_extent, summary$epsg)
# LAS header only: bytes 6-7 are global encoding; bytes 24-25 are version.
las_path <- file.path(roots["NATIVE"], native_rows$path[grepl("[.]laz$", native_rows$path)])
h <- readBin(las_path, "raw", n = 26L)
if (length(h) != 26L || rawToChar(h[1:4]) != "LASF" ||
    as.integer(h[25]) != 1L || as.integer(h[26]) != 3L ||
    bitwAnd(as.integer(h[7]), 1L) != 0L) stop("Unsupported native LAS GPS time flag/version")
gps <- read.csv(file.path(roots["PILOT"], "gps_by_source.csv"))
if (sum(gps$points) != summary$source_point_rows) stop("Pilot GPS groups do not cover context")
pdf <- function(level) file.path(roots["NATIVE"], native_rows$path[
  grepl(paste0("_", level, "_discrete"), native_rows$path)])
l1 <- timing_l1(timing_pdf(pdf("L1")))
l3 <- timing_l3(timing_pdf(pdf("L3")))
timing_check_interval_inventory(l1, l3, m)
assoc <- timing_associate(gps, l1, m$gps_week, m$gps_minus_utc_seconds)
# L3 corroboration inventories every interval that contains each whole range.
l3_assoc <- timing_l3_corroboration(gps, assoc, l3)
listing <- jsonlite::fromJSON(file.path(roots["ARCHIVE"], "DP1.30010.001_TEAK_2018-06.json"))
listed_ids <- timing_camera_inventory(listing)
kmz_rows <- m$sources[grepl("[.]kmz$", m$sources$path), ]
if (nrow(kmz_rows) != 4L || length(unique(kmz_rows$sha256)) != 2L ||
    any(table(kmz_rows$sha256) != 2L)) stop("Expected both independently pinned KMZ variants")
variants <- kmz_rows[!duplicated(kmz_rows$sha256), ]
frames <- do.call(rbind, lapply(seq_len(nrow(variants)), function(i) {
  z <- timing_kmz(file.path(roots["ARCHIVE"], variants$path[i]), core, context)
  z$variant_sha256 <- variants$sha256[i]
  z$variant_source_url <- variants$source_url[i]
  z$in_dp1_product_inventory <- z$frame_id %in% listed_ids
  z
}))
variants_summary <- do.call(rbind, lapply(seq_len(nrow(variants)), function(i) {
  z <- frames[frames$variant_sha256 == variants$sha256[i], ]
  data.frame(variant_sha256 = variants$sha256[i], frames = nrow(z),
    core_candidates = sum(z$intersects_core), context_candidates = sum(z$intersects_context),
    absent_from_dp1 = sum(!z$in_dp1_product_inventory),
    dp1_frames_absent_from_kmz = length(setdiff(listed_ids, z$frame_id)))
}))
missing <- do.call(rbind, lapply(seq_len(nrow(variants)), function(i) {
  ids <- setdiff(listed_ids, frames$frame_id[frames$variant_sha256 == variants$sha256[i]])
  data.frame(variant_sha256 = rep(variants$sha256[i], length(ids)), frame_id = ids)
}))
local <- frames[frames$intersects_context, ]
local1 <- local[local$variant_sha256 == variants$sha256[1], ]
local2 <- local[local$variant_sha256 == variants$sha256[2], ]
cmp <- setdiff(names(local), c("variant_sha256", "variant_source_url"))
rownames(local1) <- rownames(local2) <- NULL
local_identical <- identical(local1[, cmp], local2[, cmp])
result <- c(list(schema_version = 1L, plot = m$plot,
  scope = "metadata_only_historical_development_pilot",
  pilot_receipt_sha256 = m$pilot_receipt_sha256,
  gps_group_verification = "pinned_pilot_receipt_all_outputs_rehashed_native_LAS_header_checked",
  native_las_global_encoding = as.integer(h[7]) + 256L * as.integer(h[8]),
  gps_time_type = "gps_week", gps_week = m$gps_week,
  gps_week_start = m$gps_week_start, gps_minus_utc_seconds = m$gps_minus_utc_seconds,
  utc_conversion_status = m$calendar_basis,
  l1_complete_table_rows = nrow(l1), l3_complete_table_rows = nrow(l3),
  l1_missions = unique(l1$mission), l1_flight_dates = unique(l1$flight_date),
  l1_date_contradiction = "unresolved; Flight Date is not silently corrected",
  lidar_interval_association_unique = all(assoc$candidate_count == 1L),
  l3_corroboration_complete = all(l3_assoc$corroboration_status ==
    "corroborated_unique_interval_and_line"),
  camera_time_status = "filename_derived_documented_UTC_candidate_exposures_only",
  candidate_footprint_status = "closed_polygon_intersection_including_edge_touches",
  local_variants_identical = local_identical,
  core_extent = summary$core_extent, context_extent = summary$context_extent,
  epsg = summary$epsg, camera_variants = variants_summary,
  core_candidate_days = sort(unique(substr(local$filename_utc[local$intersects_core], 1, 10))),
  context_candidate_days = sort(unique(substr(local$filename_utc, 1, 10))),
  mosaic_pixel_exposure = "unknown", exact_lidar_rgb_lag = "unknown",
  rgb_tiff_datetime = summary$rgb_comparison$native_processing_datetime,
  rgb_tiff_datetime_interpretation = "file_timestamp_not_camera_exposure",
  chm_acquisition_linkage = "not_established_by_this_audit"), timing_gates())
# Serialize once, so verify mode checks recomputed assertions and exact bytes.
csv_bytes <- function(x) {
  con <- textConnection("s", "w", local = TRUE)
  write.csv(x, con, row.names = FALSE, na = "")
  close(con)
  charToRaw(paste0(paste(s, collapse = "\n"), "\n"))
}
json_bytes <- function(x) charToRaw(paste0(jsonlite::toJSON(x,
  auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null"), "\n"))
payloads <- list("l1_intervals.csv" = csv_bytes(l1),
  "l3_intervals.csv" = csv_bytes(l3), "gps_associations.csv" = csv_bytes(assoc),
  "l3_associations.csv" = csv_bytes(l3_assoc), "camera_frame_inventory.csv" = csv_bytes(frames),
  "camera_context_candidates.csv" = csv_bytes(local),
  "camera_variant_inventory.csv" = csv_bytes(variants_summary),
  "dp1_frames_missing_from_kmz.csv" = csv_bytes(missing),
  "timing_summary.json" = json_bytes(result))
# Rehash every source/code dependency after analysis, before any output writes.
timing_check_files(roots["PILOT"], pr$outputs, exact = TRUE, extras = "receipt.json")
timing_check_files(roots["ARCHIVE"], m$sources)
timing_check_files(roots["NATIVE"], native_rows)
if (!identical(canopy_hash(.code), .before) ||
    !identical(canopy_hash(manifest_paths), manifest_hashes) ||
    canopy_hash(receipt_path) != m$pilot_receipt_sha256) stop("Source/code changed during audit")
input_records <- rbind(
  cbind(archive = "PILOT", timing_record(roots["PILOT"], c("receipt.json", pr$outputs$path))),
  cbind(archive = "NATIVE", native_rows),
  cbind(archive = "ARCHIVE", m$sources[, c("path", "bytes", "sha256")]))
receipt <- c(list(schema_version = 1L, plot = m$plot,
  inputs = input_records,
  manifests = timing_record(.ROOT, sub(paste0(.ROOT, "/"), "", manifest_paths, fixed = TRUE)),
  code = timing_record(dirname(.self), basename(.code)),
  packages = setNames(lapply(c("sf", "xml2", "jsonlite", "digest"), function(p)
    as.character(utils::packageVersion(p))), c("sf", "xml2", "jsonlite", "digest")),
  external_tools = list(pdftotext = list(
    command = "pdftotext -layout; read-only stdout",
    sha256 = canopy_hash(Sys.which("pdftotext")),
    bytes = unname(file.info(Sys.which("pdftotext"))$size),
    version = system2("pdftotext", "-v", stdout = TRUE, stderr = TRUE)[1])),
  outputs = data.frame(path = names(payloads), bytes = lengths(payloads),
    sha256 = vapply(payloads, digest::digest, character(1), algo = "sha256", serialize = FALSE))),
  timing_gates())
payloads[["receipt.json"]] <- json_bytes(receipt)
if (verify) {
  expected <- data.frame(path = names(payloads), bytes = lengths(payloads),
    sha256 = vapply(payloads, digest::digest, character(1), algo = "sha256", serialize = FALSE))
  timing_check_files(out, expected, exact = TRUE)
  if (!setequal(names(payloads), list.files(out, all.files = TRUE, recursive = TRUE, no.. = TRUE)))
    stop("Unexpected verified output inventory")
  for (p in names(payloads)) {
    got <- readBin(file.path(out, p), "raw", n = file.info(file.path(out, p))$size)
    if (!identical(got, payloads[[p]])) stop("Recomputed output differs: ", p)
  }
  cat("Verified timing audit and recomputed all derived outputs; no files written.\n")
} else {
  if (!dir.create(out, recursive = TRUE, showWarnings = FALSE)) stop("Cannot create fresh OUT")
  for (p in names(payloads)) writeBin(payloads[[p]], file.path(out, p))
  cat("Prepared metadata-only timing audit: ", out, "\n", sep = "")
}
