# Keep the installed tile selector, but supply authentication to its first
# getTileUrls call too (neonUtilities 3.0.3 omits token on that call).
neon_by_tile_aop <- function(..., token = neon_token(), client = neonUtilities::byTileAOP) {
  original <- environment(client)
  query <- get("getTileUrls", envir = original)
  authenticated <- new.env(parent = original)
  supplied <- token
  authenticated$getTileUrls <- function(..., token = NA_character_) {
    if (is.na(token) || !nzchar(token)) token <- supplied
    query(..., token = token)
  }
  environment(client) <- authenticated
  client(..., token = token)
}

neon_released_files <- function(product, site, month, release = "RELEASE-2026") {
  if (!grepl("^DP[1-4][.][0-9]{5}[.]00[12]$", product) ||
      !grepl("^[A-Z]{4}$", site) || !grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", month) ||
      !grepl("^RELEASE-[0-9]{4}$", release)) stop("Invalid released-file query")
  url <- paste0("https://data.neonscience.org/api/v0/data/", product, "/", site,
                "/", month, "?release=", release)
  h <- curl::new_handle(timeout = 120)
  curl::handle_setheaders(h, "X-API-Token" = neon_token())
  response <- curl::curl_fetch_memory(url, h)
  if (response$status_code != 200L) stop("NEON file-list HTTP ", response$status_code)
  data <- jsonlite::fromJSON(rawToChar(response$content))$data
  if (!identical(data$productCode, product) || !identical(data$siteCode, site) ||
      !identical(data$month, month) || !identical(data$release, release))
    stop("NEON file list differs from requested product/site/month/release")
  data
}

neon_archive_listing <- function(data, path) {
  # Signed cloud URLs are credentials: archive file identities, never the URLs.
  files <- data$files[order(data$files$name), c("name", "size", "md5")]
  rownames(files) <- NULL
  manifest <- list(product = data$productCode, site = data$siteCode,
    month = data$month, release = data$release, files = files)
  neon_check_manifest(path, manifest)
  invisible(manifest)
}

neon_tile_index <- function(files, product) {
  pattern <- if (product == "DP1.30003.001")
    "^NEON_[A-Z0-9]+_[A-Z]{4}_DP1_([0-9]+)_([0-9]+)_.*[.]laz$" else
    "^[0-9]{4}_[A-Z]{4}_[0-9]+_([0-9]+)_([0-9]+)_image[.]tif$"
  matches <- regexec(pattern, files$name)
  parts <- regmatches(files$name, matches)
  keep <- lengths(parts) == 3L
  if (!any(keep)) stop("No spatial tiles recognized in file list")
  out <- files[keep, c("name", "size", "md5")]
  out$tile_e <- as.numeric(vapply(parts[keep], `[`, character(1), 2))
  out$tile_n <- as.numeric(vapply(parts[keep], `[`, character(1), 3))
  out$key <- sprintf("%.0f_%.0f", out$tile_e, out$tile_n)
  if (anyDuplicated(out$key)) stop("Ambiguous duplicate acquisition tiles")
  out
}

neon_required_tiles <- function(cx, cy, half) {
  if (any(!is.finite(c(cx, cy, half))) || half <= 0) stop("Invalid coverage extent")
  grid <- expand.grid(e = seq(floor((cx - half) / 1000), floor((cx + half) / 1000)),
                       n = seq(floor((cy - half) / 1000), floor((cy + half) / 1000)))
  sprintf("%.0f_%.0f", grid$e * 1000, grid$n * 1000)
}

eastern_tile_coverage <- function(candidates, pc, lidar, rgb) {
  for (i in seq_len(nrow(candidates))) {
    p <- pc[match(candidates$plot[i], pc$plotID), ]
    if (!p$plotType %in% c("tower", "distributed")) next
    half <- if (p$plotType == "tower") 20 else 10
    needed <- neon_required_tiles(p$easting, p$northing, half + 25)
    candidates$lidar_coverage[i] <- if (all(needed %in% lidar$key)) "listed" else "missing_tiles"
    candidates$rgb_coverage[i] <- if (all(needed %in% rgb$key)) "listed" else "missing_tiles"
  }
  candidates$coverage_candidate <- candidates$field_candidate &
    candidates$lidar_coverage == "listed" & candidates$rgb_coverage == "listed"
  candidates
}

neon_extent_covers <- function(box, extents) {
  if (is.na(sf::st_crs(box)) || is.na(sf::st_crs(extents)) ||
      sf::st_crs(box) != sf::st_crs(extents)) stop("Coverage CRS is missing or mismatched")
  if (length(box) != 1L || !length(extents) || any(sf::st_is_empty(box)) ||
      any(sf::st_is_empty(extents))) return(FALSE)
  isTRUE(sf::st_covered_by(box, sf::st_union(extents), sparse = FALSE)[1, 1])
}
