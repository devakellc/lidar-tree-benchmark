# Bounded TEAK_043 metadata audit; no imagery, inference or scoring.
timing_check_files <- function(root, rows, exact = FALSE, extras = character()) {
  canopy_check_paths(rows$path)
  if (any(grepl("//|/$", rows$path))) stop("Unsafe noncanonical paths")
  root <- normalizePath(root, mustWork = TRUE)
  paths <- file.path(root, rows$path)
  if (any(!file.exists(paths)) || any(dir.exists(paths))) stop("Missing input/output file")
  resolved <- normalizePath(paths, mustWork = TRUE)
  if (any(!startsWith(resolved, paste0(root, "/"))) ||
      any(resolved != paths) || anyDuplicated(resolved) ||
      any(nzchar(Sys.readlink(paths)))) stop("Escaping or aliased input/output path")
  if (exact && !setequal(list.files(root, recursive = TRUE, all.files = TRUE,
                                   no.. = TRUE), c(rows$path, extras)))
    stop("Missing or extra output paths")
  if (any(file.info(paths)$size != rows$bytes) ||
      any(canopy_hash(paths) != rows$sha256)) stop("Input/output hash or byte mismatch")
  invisible(paths)
}


# Fixed declaration semantics keep this audit bounded to the pinned pilot.
timing_declaration <- function(m) {
  expected <- list(schema_version = 1L, plot = "TEAK_043",
    scope = "metadata_only_historical_development_pilot", gps_week = 2005L,
    gps_week_start = "2018-06-10", gps_minus_utc_seconds = 18L,
    calendar_basis = "conditional_inference_from_report_mission_context_not_week_seconds_alone",
    camera_timestamp_basis = "parenthesized_filename_token_documented_as_UTC_collection_time",
    expected_l1_table_rows = 213L, expected_l3_table_rows = 118L,
    expected_l1_missions = c("2018061416", "2018061515", "2018061517", "2018061615", "2018061617"))
  if (!all(vapply(names(expected), function(k) identical(m[[k]], expected[[k]]), logical(1))))
    stop("Unsupported timing declaration semantics")
  sources <- m$sources
  required <- c("path", "bytes", "sha256", "product", "site", "month", "release", "name", "source_url", "retrieved_utc")
  if (!is.data.frame(sources) || !all(required %in% names(sources)) ||
      nrow(sources) != 7L || anyNA(sources[, required]) ||
      any(sources$site != "TEAK" | sources$month != "2018-06" |
          sources$release != "RELEASE-2026") ||
      any(!is.finite(sources$bytes) | sources$bytes <= 0) ||
      any(!grepl("^[a-f0-9]{64}$", sources$sha256)))
    stop("Invalid timing source declaration")
  canopy_check_paths(sources$path)
  products <- c("DP1.30010.001", "DP3.30010.001")
  official_name <- "2018_TEAK_3_mosaic.kmz"
  sizes <- c(23807048, 24120301)
  for (product in products) {
    for (i in seq_along(sizes)) {
      path <- paste(product, sizes[i], official_name, sep = "_")
      row <- sources[sources$path == path, ]
      url <- paste0("https://storage.googleapis.com/neon-aop-products/2018/FullSite/",
        "D17/2018_TEAK_3/Metadata/Camera/", c("Reports", "kmz")[i], "/", official_name)
      if (nrow(row) != 1L || row$product != product || row$name != official_name ||
          row$bytes != sizes[i] || row$source_url != url)
        stop("Unsupported KMZ source identity")
    }
    path <- paste0(product, "_TEAK_2018-06.json")
    row <- sources[sources$path == path, ]
    url <- paste0("https://data.neonscience.org/api/v0/data/", product,
                  "/TEAK/2018-06?release=RELEASE-2026")
    if (nrow(row) != 1L || row$product != product || row$name != path || row$source_url != url)
      stop("Unsupported camera inventory source identity")
  }
  row <- sources[sources$path == "retrieval.json", ]
  if (nrow(row) != 1L || row$product != "retrieval_receipt" ||
      row$name != "retrieval.json" || row$source_url != "local retrieval receipt")
    stop("Unsupported retrieval source identity")
  invisible(TRUE)
}

timing_camera_inventory <- function(listing) {
  if (!identical(listing$product, "DP1.30010.001") ||
      !identical(listing$site, "TEAK") || !identical(listing$month, "2018-06") ||
      !identical(listing$release, "RELEASE-2026") ||
      !is.data.frame(listing$files) || !all(c("name", "size") %in% names(listing$files)))
    stop("Invalid camera product inventory")
  frames <- listing$files[grepl("_ort[.]tif$", listing$files$name), ]
  # The two same-named KMZ records have different byte identities, not duplicate
  # frame IDs. Validate uniqueness only in the orthorectified L1 image subset.
  if (!nrow(frames) || anyNA(frames$name) || anyDuplicated(frames$name) ||
      any(!is.finite(frames$size) | frames$size <= 0))
    stop("Invalid or duplicate camera frame inventory")
  sub("_ort[.]tif$", "", frames$name)
}

timing_record <- function(root, paths) data.frame(path = paths,
  bytes = unname(file.info(file.path(root, paths))$size),
  sha256 = canopy_hash(file.path(root, paths)), stringsAsFactors = FALSE)

timing_gates <- function() list(evaluation_ready = FALSE, real_scores = FALSE,
  reference_review_complete = FALSE, exact_rgb_pixel_provenance = FALSE,
  temporal_agreement_verified = FALSE, registration_verified = FALSE,
  checkpoint_exposure = "unknown", reserved_plots_processed = character())

timing_week_utc <- function(seconds, week, offset, gps_type = "gps_week") {
  if (!identical(gps_type, "gps_week") || length(week) != 1L ||
      !is.finite(week) || week != 2005 || length(offset) != 1L ||
      !is.finite(offset) || offset != 18 || any(!is.finite(seconds)) ||
      any(seconds < 0 | seconds >= 604800)) stop("Unsupported GPS week/time conversion")
  format(as.POSIXct("1980-01-06", tz = "UTC") + week * 604800 + seconds - offset,
         "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC")
}

timing_pdf <- function(path) {
  if (!nzchar(Sys.which("pdftotext"))) stop("pdftotext is required")
  txt <- system2("pdftotext", c("-layout", shQuote(path), "-"), stdout = TRUE)
  if (!is.null(attr(txt, "status"))) stop("PDF extraction failed")
  txt
}

timing_table <- function(text, table, next_table) {
  first <- grep(paste0("Table ", table, ":"), text)
  last <- grep(paste0("Table ", next_table, ":"), text)
  if (length(first) != 1L || length(last) != 1L || last <= first)
    stop("Missing or ambiguous PDF table boundaries")
  idx <- seq.int(first + 1L, last - 1L)
  # The footer on the same page supplies the printed report-page number.
  page <- vapply(idx, function(i) {
    j <- grep("Page [0-9]+ of", text[seq.int(i, length(text))])[1]
    if (is.na(j)) stop("Missing report page")
    as.integer(sub(".*Page ([0-9]+) of.*", "\\1", text[i + j - 1L]))
  }, integer(1))
  data.frame(text = trimws(text[idx]), report_page = page)
}

timing_interval_rows <- function(tab, pattern) {
  selected <- grepl(pattern, tab$text)
  # Numeric body columns still identify a row when its leading label is damaged.
  tokens <- strsplit(tab$text, "[[:space:]]+")
  numeric_count <- vapply(tokens, function(z)
    sum(is.finite(suppressWarnings(as.numeric(z)))), integer(1))
  row_like <- numeric_count >= 3L | grepl("^([0-9]{4}|[Ll][0-9])", tab$text)
  if (any(row_like & !selected)) stop("Unparsed row-like PDF table line")
  tab[selected, , drop = FALSE]
}

timing_check_interval_inventory <- function(l1, l3, declaration) {
  if (nrow(l1) != declaration$expected_l1_table_rows ||
      nrow(l3) != declaration$expected_l3_table_rows ||
      !setequal(unique(l1$mission), declaration$expected_l1_missions))
    stop("Incomplete pinned interval inventory or unexpected mission set")
  invisible(TRUE)
}

timing_l1 <- function(text) {
  tab <- timing_table(text, 10, 11)
  rows <- timing_interval_rows(tab, "^[0-9]{10}\\s")
  tok <- strsplit(rows$text, "[[:space:]]+")
  if (!length(tok) || any(lengths(tok) != 7L)) stop("Malformed L1 interval row")
  z <- as.data.frame(do.call(rbind, tok), stringsAsFactors = FALSE)
  names(z) <- c("mission", "trajectory_strip_id", "lms_line",
                "trajectory_start", "trajectory_end", "lms_start", "lms_end")
  for (n in names(z)[c(2, 4:7)]) z[[n]] <- suppressWarnings(as.numeric(z[[n]]))
  if (any(!is.finite(as.matrix(z[, c(2, 4:7)]))) ||
      any(z$trajectory_start > z$trajectory_end | z$lms_start > z$lms_end) ||
      any(!grepl("^[0-9]+-[0-9]+$", z$lms_line)) ||
      anyDuplicated(paste(z$mission, z$trajectory_strip_id, z$lms_line)))
    stop("Invalid or duplicate L1 interval")
  z$report_page <- rows$report_page
  z$table <- 10L
  z$flight_date <- vapply(z$mission, function(m) {
    i <- grep(paste0("^Mission Name: ", m, "$"), trimws(text))
    if (length(i) != 1L) stop("Missing or duplicate mission block")
    tail <- text[seq.int(i + 1L, length(text))]
    end <- grep("^Mission Name:", trimws(tail))[1]
    if (!is.na(end)) tail <- head(tail, end - 1L)
    d <- grep("^Flight Date:", trimws(tail), value = TRUE)
    if (length(d) != 1L) stop("Missing or ambiguous flight date")
    sub("^Flight Date: *", "", trimws(d))
  }, character(1))
  z
}

timing_l3 <- function(text) {
  tab <- timing_table(text, 4, 5)
  rows <- timing_interval_rows(tab, "^L[0-9]+-[0-9]+\\s")
  tok <- strsplit(rows$text, "[[:space:]]+")
  if (!length(tok) || any(lengths(tok) != 5L)) stop("Malformed L3 processed interval")
  z <- as.data.frame(do.call(rbind, tok), stringsAsFactors = FALSE)
  names(z) <- c("processed_line", "points", "gps_start", "gps_end", "density")
  for (n in names(z)[-1]) z[[n]] <- suppressWarnings(as.numeric(z[[n]]))
  if (any(!is.finite(as.matrix(z[, -1]))) || any(z$gps_start > z$gps_end))
    stop("Invalid L3 processed interval")
  # Labels repeat across missions; source row and page identify each interval.
  z$source_table_row <- seq_len(nrow(z))
  z$lms_line <- sub("^L0*", "", z$processed_line)
  z$report_page <- rows$report_page
  z$table <- 4L
  z
}

timing_associate <- function(gps, l1, week = 2005, offset = 18) {
  fields <- c("PointSourceID", "points", "gps_min", "gps_max")
  if (!identical(names(gps), fields) || !nrow(gps) ||
      any(!is.finite(as.matrix(gps))) || anyDuplicated(gps$PointSourceID) ||
      any(gps$points <= 0 | gps$points != floor(gps$points)) ||
      any(gps$gps_min > gps$gps_max)) stop("Invalid GPS source groups")
  timing_week_utc(c(gps$gps_min, gps$gps_max), week, offset)
  do.call(rbind, lapply(seq_len(nrow(gps)), function(i) {
    g <- gps[i, , drop = FALSE]
    k <- which(l1$trajectory_start <= g$gps_min & l1$trajectory_end >= g$gps_max)
    n <- length(k)
    candidates <- if (n) l1[k, , drop = FALSE] else l1[NA_integer_, , drop = FALSE]
    rownames(candidates) <- NULL
    ans <- cbind(g[rep(1, max(1L, n)), , drop = FALSE], candidates)
    ans$candidate_count <- n
    ans$association_status <- if (n == 1L) "unique_interval_association" else
      if (n == 0L) "unmatched_unknown" else "ambiguous_unknown"
    ans$match_rule <- "whole_group_within_closed_trajectory_interval"
    mission_day <- if (n == 1L) as.Date(substr(candidates$mission, 1, 8),
                                      format = "%Y%m%d") else as.Date(NA_character_)
    anchor <- as.Date("1980-01-06") + week * 7
    anchored <- n == 1L && isTRUE(mission_day >= anchor & mission_day < anchor + 7)
    ans$utc_conversion_status <- if (anchored) "conditional_mission_anchored_week" else
      "unknown_missing_unique_mission_week_association"
    ans$utc_min_conditional <- if (anchored) timing_week_utc(g$gps_min, week, offset) else NA_character_
    ans$utc_max_conditional <- if (anchored) timing_week_utc(g$gps_max, week, offset) else NA_character_
    ans
  }))
}

timing_l3_corroboration <- function(gps, l1_associations, l3) {
  do.call(rbind, lapply(seq_len(nrow(gps)), function(i) {
    k <- which(l3$gps_start <= gps$gps_min[i] & l3$gps_end >= gps$gps_max[i])
    prior <- l1_associations[l1_associations$PointSourceID == gps$PointSourceID[i], ]
    unique_l1 <- nrow(prior) == 1L && isTRUE(prior$candidate_count == 1L)
    line <- if (unique_l1) prior$lms_line else NA_character_
    z <- if (length(k)) l3[k, , drop = FALSE] else l3[NA_integer_, , drop = FALSE]
    status <- if (!length(k)) "unknown_no_l3_interval" else
      if (length(k) != 1L) "unknown_ambiguous_l3_intervals" else
      if (!unique_l1) "unknown_nonunique_l1_association" else
      if (!isTRUE(z$lms_line == line)) "unknown_line_disagreement" else
      "corroborated_unique_interval_and_line"
    cbind(PointSourceID = gps$PointSourceID[i], candidate_count = length(k),
      l1_lms_line = line, corroboration_status = status, z)
  }))
}

timing_rectangle <- function(bounds, epsg = 32611) {
  if (length(bounds) != 4L || any(!is.finite(bounds)) ||
      bounds[1] >= bounds[2] || bounds[3] >= bounds[4] || epsg != 32611)
    stop("Invalid TEAK metric bounds/CRS")
  sf::st_as_sfc(sf::st_bbox(c(xmin = bounds[1], ymin = bounds[3],
                            xmax = bounds[2], ymax = bounds[4]), crs = sf::st_crs(epsg)))
}

timing_kml <- function(doc, core, context) {
  if (!"http://www.opengis.net/kml/2.2" %in% unname(xml2::xml_ns(doc)))
    stop("Unknown KML namespace/CRS")
  xml2::xml_ns_strip(doc)
  nodes <- xml2::xml_find_all(doc, ".//Placemark[styleUrl='#imageStyle']")
  if (!length(nodes)) stop("No imageStyle frame footprints")
  scalar <- function(node, field) {
    v <- xml2::xml_find_all(node, field)
    if (length(v) != 1L) stop("Missing or duplicate frame field")
    trimws(xml2::xml_text(v))
  }
  records <- lapply(nodes, function(node) {
    id <- scalar(node, "Snippet")
    description <- scalar(node, "description")
    lines <- trimws(strsplit(description, "\n", fixed = TRUE)[[1]])
    fn <- grep("^Filename: ", lines, value = TRUE)
    if (length(fn) != 1L || sub("^Filename: ", "", fn) != id ||
        !grepl("^[A-Za-z0-9_]+\\([0-9]{14}\\)-[0-9]+$", id))
      stop("Malformed or ambiguous full frame filename")
    stamp <- sub(".*\\(([0-9]{14})\\).*", "\\1", id)
    utc <- as.POSIXct(stamp, format = "%Y%m%d%H%M%S", tz = "UTC")
    if (is.na(utc) || format(utc, "%Y%m%d%H%M%S", tz = "UTC") != stamp)
      stop("Invalid filename timestamp")
    polygon <- xml2::xml_find_all(node, ".//Polygon")
    if (length(polygon) != 1L || length(xml2::xml_find_all(polygon, ".//innerBoundaryIs")))
      stop("Missing or unsupported frame Polygon")
    coords <- scalar(polygon, "outerBoundaryIs/LinearRing/coordinates")
    xyz <- strsplit(strsplit(trimws(coords), "[[:space:]]+")[[1]], ",", fixed = TRUE)
    if (any(lengths(xyz) != 3L)) stop("Malformed KML coordinates")
    xyz <- matrix(suppressWarnings(as.numeric(unlist(xyz))), ncol = 3L, byrow = TRUE)
    if (nrow(xyz) < 4L || any(!is.finite(xyz)) || any(abs(xyz[, 1]) > 180) ||
        any(abs(xyz[, 2]) > 90) || !identical(xyz[1, ], xyz[nrow(xyz), ]))
      stop("Invalid or unclosed KML geometry")
    list(row = data.frame(frame_id = id, placemark_name = scalar(node, "name"),
      timestamp_token = stamp, filename_utc = format(utc, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      timestamp_basis = "filename_derived_documented_UTC", geometry_type = "Polygon",
      source_epsg = 4326L, target_epsg = 32611L,
      coordinates_lon_lat_alt = coords), geom = sf::st_polygon(list(xyz[, 1:2])))
  })
  rows <- do.call(rbind, lapply(records, `[[`, "row"))
  if (anyDuplicated(rows$frame_id)) stop("Duplicate full frame IDs")
  geom <- sf::st_sfc(lapply(records, `[[`, "geom"), crs = 4326)
  # Planar validity is checked after projection; intersections include touches.
  geom <- sf::st_transform(geom, 32611)
  if (any(!sf::st_is_valid(geom)) || any(sf::st_is_empty(geom)) ||
      any(!is.finite(sf::st_coordinates(geom)))) stop("Invalid projected Polygon")
  rows$intersects_core <- lengths(sf::st_intersects(geom, core)) > 0L
  rows$intersects_context <- lengths(sf::st_intersects(geom, context)) > 0L
  rows$covers_core <- lengths(sf::st_covers(geom, core)) > 0L
  rows[order(rows$frame_id), ]
}

timing_kmz <- function(path, core, context) {
  entries <- utils::unzip(path, list = TRUE)$Name
  if (sum(entries == "doc.kml") != 1L) stop("KMZ must contain exactly one doc.kml")
  con <- unz(path, "doc.kml", open = "rb")
  on.exit(close(con))
  timing_kml(xml2::read_xml(con, options = "NONET"), core, context)
}
