#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_acquisition_lib.R"))
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
out <- if (is.null(A$OUT)) file.path(.job_dir(), "reference_resolution_evidence") else A$OUT
lidar <- identical(A$HARV_LIDAR, "TRUE")
if (!is.null(A$HARV_LIDAR) && !A$HARV_LIDAR %in% c("TRUE", "FALSE")) stop("Invalid HARV_LIDAR")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(out)
code <- vapply(c("collect_neon_reference_evidence.R", "neon_spatial_lib.R",
                 "neon_acquisition_lib.R"), .find, character(1))
neon_check_manifest(file.path(out, "collection_contract.json"),
  list(site = "HARV", month = "2022-08", release = "RELEASE-2026", lidar = lidar,
       code = unname(code), md5 = unname(tools::md5sum(code))))
receipt <- file.path(out, "completion.json")
if (file.exists(receipt)) {
  old <- jsonlite::read_json(receipt, simplifyVector = TRUE)
  if (!all(file.exists(old$files))) stop("Evidence files are missing")
  neon_check_manifest(receipt, list(files = old$files, md5 = unname(tools::md5sum(old$files))))
  cat("Evidence replay passed; no network request made.\n")
  quit(status = 0L)
}
fetch <- function(url, name, size = NULL) {
  path <- file.path(out, name)
  if (!file.exists(path)) {
    temp <- paste0(path, ".part")
    response <- tryCatch(curl::curl_fetch_disk(url, temp, curl::new_handle(timeout = 1200)),
      error = function(e) stop("Download failed for ", name, call. = FALSE))
    if (response$status_code != 200L) stop("Download HTTP ", response$status_code, " for ", name)
    if (!is.null(size) && file.info(temp)$size != as.numeric(size)) stop("Byte count differs for ", name)
    if (!file.rename(temp, path)) stop("Could not finalize ", name)
  }
  if (file.info(path)$size <= 0 || (!is.null(size) && file.info(path)$size != as.numeric(size)))
    stop("Invalid cached evidence: ", name)
  invisible(path)
}
public <- c(
  vegetation_guide.pdf = "https://data.neonscience.org/api/v0/documents/NEON_vegStructure_userGuide_vE.1",
  vegetation_protocol_k.pdf = "https://data.neonscience.org/api/v0/documents/NEON.DOC.000987vK",
  lidar_datum_report.pdf = "https://data.neonscience.org/api/v0/documents/NEON.DOC.002293vB",
  lidar_atbd.pdf = "https://data.neonscience.org/api/v0/documents/NEON.DOC.001292vB",
  lidar_product.json = "https://data.neonscience.org/api/v0/products/DP1.30003.001",
  flight_dates.csv = "https://www.neonscience.org/sites/default/files/AOP_NIS_FlightDates_2013_2025.csv",
  BART_040_point51.json = "https://data.neonscience.org/api/v0/locations/BART_040.basePlot.vst.51")
for (i in seq_along(public)) fetch(public[i], names(public)[i])
write.csv(data.frame(file = names(public), url = unname(public)),
          file.path(out, "public_sources.csv"), row.names = FALSE)
listing <- neon_released_files("DP1.30003.001", "HARV", "2022-08")
neon_archive_listing(listing, file.path(out, "harv_file_identities.json"))
files <- listing$files
keep <- grepl("^NEON_D01_HARV_DPQA_L[0-9]+-[0-9]+_[0-9]{10}_boundary[.]kml$", files$name) |
  grepl("^202208[0-9]{4}_P3C1_SBET_QAQC[.]pdf$", files$name)
if (lidar) keep <- keep | files$name ==
  "NEON_D01_HARV_DP1_731000_4713000_classified_point_cloud_colorized.laz"
selected <- files[keep, ]
if (!nrow(selected) || anyDuplicated(selected$name)) stop("Missing or ambiguous HARV evidence")
if (lidar && sum(grepl("[.]laz$", selected$name)) != 1L) stop("Declared HARV tile missing")
for (i in seq_len(nrow(selected))) fetch(selected$url[i], selected$name[i], selected$size[i])
headers <- files[grepl("^NEON_D01_HARV_DP1_L[0-9]+-[0-9]+_[0-9]{10}_unclassified_point_cloud[.]laz$",
                      files$name), ]
if (!nrow(headers) || anyDuplicated(headers$name)) stop("Missing or ambiguous flightline headers")
header_dir <- file.path(out, "flight_headers")
dir.create(header_dir, showWarnings = FALSE)
for (i in seq_len(nrow(headers))) {
  name <- paste0(sub("[.]laz$", "", headers$name[i]), ".header.laz")
  path <- file.path(header_dir, name)
  bytes <- min(65536, as.numeric(headers$size[i]))
  if (!file.exists(path)) {
    temp <- paste0(path, ".part")
    response <- tryCatch(curl::curl_fetch_disk(headers$url[i], temp,
      curl::new_handle(timeout = 120, range = paste0("0-", bytes - 1), maxfilesize = bytes)),
      error = function(e) stop("Header range request failed for ", name, call. = FALSE))
    if (response$status_code != 206L || file.info(temp)$size != bytes)
      stop("Expected bounded partial content for ", name)
    if (!file.rename(temp, path)) stop("Could not finalize header ", name)
  }
  if (file.info(path)$size != bytes) stop("Invalid cached header excerpt")
}
rm(listing, files, selected, headers) # Never persist signed URLs or response headers.
outputs <- sort(list.files(out, full.names = TRUE, recursive = TRUE))
outputs <- outputs[!grepl("[.]part$", outputs)]
neon_check_manifest(receipt, list(files = outputs, md5 = unname(tools::md5sum(outputs))))
cat("Reference evidence collected. HARV LiDAR:", lidar, "; BART spatial data: none.\n")
