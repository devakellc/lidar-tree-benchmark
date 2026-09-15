# NEON field coordinates use the site's declared WGS84 UTM frame, not one zone.
neon_zone_epsg <- function(zone, hemisphere = NULL) {
  z <- toupper(trimws(as.character(zone)))
  if (!length(z) || anyNA(z)) stop("Missing NEON UTM zone")
  if (!is.null(hemisphere)) {
    h <- toupper(trimws(as.character(hemisphere)))
    if (!length(h) || anyNA(h) || !length(h) %in% c(1L, length(z)))
      stop("Missing or incompatible NEON UTM hemisphere")
    h <- rep_len(h, length(z))
    bare <- grepl("^[0-9]{1,2}$", z)
    if (any(!h %in% c("N", "S"))) stop("Invalid NEON UTM hemisphere")
    if (any(!bare & substr(z, nchar(z), nchar(z)) != h)) stop("Conflicting NEON UTM hemisphere")
    z[bare] <- paste0(z[bare], h[bare])
  }
  if (!length(z) || anyNA(z) || any(!grepl("^([1-9]|[1-5][0-9]|60)[NS]$", z)))
    stop("NEON UTM zone must include a valid zone and N/S hemisphere")
  n <- as.integer(substr(z, 1L, nchar(z) - 1L))
  ifelse(endsWith(z, "S"), 32700L, 32600L) + n
}

neon_field_epsg <- function(pc) {
  if (!"utmZone" %in% names(pc) || !nrow(pc)) stop("Missing plot UTM metadata")
  epsg <- neon_zone_epsg(pc$utmZone)
  if (length(unique(epsg)) != 1L) stop("Mixed plot coordinate systems; separate site frames")
  if ("epsg" %in% names(pc) && anyNA(pc$epsg)) stop("Missing plot EPSG metadata")
  if ("epsg" %in% names(pc) && any(pc$epsg != epsg)) stop("Plot EPSG and UTM metadata disagree")
  if ("datum" %in% names(pc) && any(is.na(pc$datum) |
      !toupper(gsub(" ", "", pc$datum, fixed = TRUE)) %in% c("WGS84", "WGS1984")))
    stop("Unsupported NEON field datum")
  unique(epsg)
}

neon_location_frame <- function(location) {
  props <- location$locationProperties
  datum <- props$locationPropertyValue[props$locationPropertyName == "Value for Geodetic datum"]
  if (length(datum) != 1L || is.na(datum) ||
      !toupper(gsub(" ", "", datum, fixed = TRUE)) %in% c("WGS84", "WGS1984"))
    stop("Missing or unsupported location datum")
  epsg <- neon_zone_epsg(location$locationUtmZone, location$locationUtmHemisphere)
  if (length(epsg) != 1L) stop("Ambiguous location frame")
  list(epsg = as.integer(epsg), datum = "WGS84")
}

neon_assert_crs <- function(spatial, expected = NULL, label = "Spatial input") {
  crs <- sf::st_crs(spatial)
  if (is.na(crs) || isTRUE(sf::st_is_longlat(crs)) ||
      !crs$units_gdal %in% c("metre", "meter", "m") ||
      isTRUE(crs == sf::st_crs(3857)))
    stop(label, " requires a declared projected metric CRS")
  if (!is.null(expected) && !isTRUE(crs == sf::st_crs(expected)))
    stop(label, " CRS differs from the field frame; explicitly reproject before reuse")
  crs
}

neon_validate_inputs <- function(gt, pc, spatial = NULL) {
  epsg <- neon_field_epsg(pc)
  if (!all(c("plotID", "easting", "northing") %in% names(pc)) ||
      anyDuplicated(pc$plotID) || anyNA(pc$plotID) ||
      any(!is.finite(pc$easting) | !is.finite(pc$northing)))
    stop("Invalid or duplicate plot coordinates")
  if (!all(c("plotID", "E", "N") %in% names(gt))) stop("Missing stem coordinates")
  mapped <- is.finite(gt$E) & is.finite(gt$N)
  if (any(!gt$plotID[mapped] %in% pc$plotID)) stop("Mapped stems lack plot coordinate metadata")
  if ("epsg" %in% names(gt) && any(is.na(gt$epsg[mapped]) | gt$epsg[mapped] != epsg))
    stop("Stem and plot coordinate systems disagree")
  if (any(mapped) && "utmZone" %in% names(gt) &&
      any(neon_zone_epsg(gt$utmZone[mapped]) != epsg))
    stop("Stem and plot UTM zones disagree")
  if (!is.null(spatial)) neon_assert_crs(spatial, epsg, "LiDAR/RGB")
  epsg
}

neon_transform_xy <- function(x, y, from, to) {
  if (length(x) != length(y) || any(!is.finite(x) | !is.finite(y)))
    stop("Invalid coordinates for transformation")
  if (is.na(sf::st_crs(from)) || is.na(sf::st_crs(to))) stop("Missing transform CRS")
  pts <- sf::st_as_sf(data.frame(x = x, y = y), coords = c("x", "y"), crs = from)
  sf::st_coordinates(sf::st_transform(pts, to))[, 1:2, drop = FALSE]
}

neon_token <- function() {
  token <- trimws(Sys.getenv("NEON_TOKEN", unset = ""))
  if (!nzchar(token)) stop("NEON downloads require NEON_TOKEN; configure it outside the repository")
  token
}

neon_year <- function(year) {
  n <- suppressWarnings(as.numeric(year))
  if (length(n) != 1L || !is.finite(n) || n != floor(n) || n < 2013 || n > 2100)
    stop("YEAR must be a four-digit NEON acquisition year")
  as.integer(n)
}

neon_reference_epoch <- function(gt, year) {
  year <- neon_year(year)
  if (!"acquisition_year" %in% names(gt)) {
    if (year != 2021L) stop("Reference lacks acquisition year; rebuild in a separate CLAUDE_JOB_DIR")
  } else if (!nrow(gt) || anyNA(gt$acquisition_year) || any(gt$acquisition_year != year)) {
    stop("Reference and requested acquisition year differ")
  }
  invisible(year)
}

neon_nearest_measurements <- function(ai, year) {
  ai$year <- suppressWarnings(as.integer(substr(ai$date, 1, 4)))
  ai <- ai[!is.na(ai$year), , drop = FALSE]
  ai$dist_aop <- abs(ai$year - neon_year(year))
  ai$dist21 <- abs(ai$year - 2021L) # Preserve the historical temporal-study column.
  ai <- ai[order(ai$individualID, ai$dist_aop), , drop = FALSE]
  ai[!duplicated(ai$individualID), , drop = FALSE]
}

neon_check_manifest <- function(path, expected, existing = character()) {
  if (file.exists(path)) {
    old <- jsonlite::read_json(path, simplifyVector = TRUE)
    if (!isTRUE(all.equal(old, expected, check.attributes = TRUE)))
      stop("Cache contract differs; use a separate CLAUDE_JOB_DIR or output root")
  } else {
    if (any(file.exists(existing)))
      stop("Unversioned cache; use a separate CLAUDE_JOB_DIR or output root")
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(expected, path, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  }
  invisible(expected)
}

neon_acquisition_manifest <- function(directory, product, year, epsg, provisional = FALSE) {
  path <- file.path(directory, "acquisition_manifest.json")
  expected <- list(product = product, year = neon_year(year), epsg = as.integer(epsg),
                   provisional = provisional)
  existing <- list.files(directory, "[.](las|laz|tif)$", recursive = TRUE,
                         full.names = TRUE, ignore.case = TRUE)
  neon_check_manifest(path, expected, existing)
}

neon_validate_files <- function(files, epsg) {
  if (!length(files) || any(!file.exists(files))) stop("Missing spatial input files")
  for (path in files) {
    spatial <- if (grepl("[.](las|laz)$", path, ignore.case = TRUE))
      lidR::readLASheader(path) else terra::rast(path)
    neon_assert_crs(spatial, epsg, basename(path))
  }
  invisible(TRUE)
}

neon_validate_acquisition <- function(directory, gt, pc, product) {
  path <- file.path(directory, "acquisition_manifest.json")
  year <- if ("acquisition_year" %in% names(gt)) unique(gt$acquisition_year) else 2021L
  neon_reference_epoch(gt, year)
  if (!file.exists(path)) {
    if (year != 2021L) stop("Missing acquisition manifest; use the NEON downloader")
    return(invisible(NULL)) # Read-only compatibility for the historical 2021 inputs.
  }
  mf <- jsonlite::read_json(path, simplifyVector = TRUE)
  if (!identical(mf$product, product) || !identical(mf$year, as.integer(year)) ||
      !identical(mf$epsg, as.integer(neon_field_epsg(pc))))
    stop("Acquisition manifest disagrees with reference epoch or CRS")
  invisible(mf)
}

neon_read_catalog <- function(files, gt, pc, directory) {
  epsg <- neon_validate_inputs(gt, pc)
  neon_validate_acquisition(directory, gt, pc, "DP1.30003.001")
  neon_validate_files(files, epsg) # Check every header; catalog CRS can hide mixed tiles.
  lidR::readLAScatalog(files, progress = FALSE)
}

neon_clip_contract <- function(ctg, site, plot, rung, cx, cy, core_half, buffer) {
  crs <- neon_assert_crs(ctg, label = "Frozen LiDAR")
  if (any(!is.finite(c(cx, cy, core_half, buffer))) || core_half <= 0 || buffer < 0)
    stop("Invalid frozen clip geometry")
  list(site = site, plot = plot, rung = if (is.na(rung)) "native" else as.character(rung),
       cx = as.numeric(cx), cy = as.numeric(cy), core_half = as.numeric(core_half),
       buffer = as.numeric(buffer), crs_wkt = crs$wkt,
       source_signature = neon_source_signature(ctg))
}

neon_source_signature <- function(ctg) {
  if (!inherits(ctg, "LAScatalog")) stop("Frozen clips require a LAScatalog")
  neon_file_signature(ctg@data$filename)
}

neon_file_signature <- function(files) {
  files <- sort(normalizePath(files, mustWork = TRUE))
  info <- file.info(files)
  # Header/epoch protection without hashing multi-gigabyte tiles on every plot.
  unname(vapply(seq_along(files), function(i)
    paste(files[i], info$size[i], as.numeric(info$mtime[i]), sep = "|"), character(1)))
}

neon_verify_clip <- function(manifest, expected, files) {
  if (is.null(manifest$coordinate_contract) ||
      !isTRUE(all.equal(manifest$coordinate_contract, expected, check.attributes = TRUE)))
    stop("Frozen coordinate cache differs or lacks provenance; use a separate output root")
  if (any(!file.exists(files))) stop("Incomplete frozen coordinate cache")
  neon_validate_files(files, expected$crs_wkt)
  invisible(TRUE)
}
