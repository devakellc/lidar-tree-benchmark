# Explanatory audits only. These helpers never admit or rewrite support bundles.
neon_verify_receipt <- function(path) {
  x <- jsonlite::read_json(path, simplifyVector = TRUE)
  if (!is.character(x$files) || !length(x$files) || anyNA(x$files) ||
      anyDuplicated(x$files) || length(x$files) != length(x$md5) ||
      anyNA(x$md5) || !all(file.exists(x$files)) ||
      !identical(unname(tools::md5sum(x$files)), unname(x$md5)))
    stop("Evidence receipt failed: ", basename(path))
  x$files
}

neon_bole_identity <- function(id, growth_form) {
  standard <- !is.na(id) & grepl("^NEON[.]PLA[.]D[0-9]{2}[.][A-Z]{4}[.][0-9]+[A-Z]?$", id)
  secondary <- standard & growth_form %in% "multi-bole tree" & grepl("[A-Z]$", id)
  family <- ifelse(standard, id, NA_character_)
  family[secondary] <- sub("[A-Z]$", "", id[secondary])
  data.frame(family_id = family, secondary_bole = secondary)
}

neon_reference_resolution <- function(a, mt, bundles) {
  required <- c("uid", "plotID", "eventID", "individualID", "growthForm", "plantStatus",
    "subplotID", "height", "breakHeight", "stemDiameter", "dataQF", "target_population",
    "reference_eligible", "reference_selected", "subplot_conflict", "exclusion", "E", "N", "pos_unc")
  neon_support_require(a, required, "Reference audit")
  flags <- c("target_population", "reference_eligible", "reference_selected", "subplot_conflict")
  if (anyNA(a[flags])) stop("Missing reference audit flags")
  neon_support_require(mt, c("uid", "recordType"), "Mapping evidence")
  identity <- neon_bole_identity(a$individualID, a$growthForm)
  a$family_id <- identity$family_id
  a$secondary_bole <- identity$secondary_bole
  key <- function(plot, event, id) paste(plot, event, id, sep = "::")
  family_key <- key(a$plotID, a$eventID, a$family_id)
  individual_key <- key(a$plotID, a$eventID, a$individualID)
  latest <- neon_latest_mapping(mt)
  mi <- match(neon_support_key(a$plotID, a$individualID),
              neon_support_key(latest$plotID, latest$individualID))
  a$source_mapping_uid <- latest$uid[mi]
  a$mapping_record_type <- latest$recordType[mi]
  flagged <- which(a$target_population & (!a$reference_eligible | a$subplot_conflict))
  if (!length(flagged)) stop("No flagged target records to resolve")
  live <- function(x) !is.na(x) & grepl("^Live($|[ ,;])", x)
  rows <- lapply(flagged, function(i) {
    related <- which(!is.na(a$family_id) & family_key == family_key[i])
    primary <- related[a$individualID[related] == a$family_id[i]]
    relation <- if (is.na(a$family_id[i])) "unsupported_identity" else
      if (!length(primary)) "missing_primary" else
      if (length(primary) != 1L) "ambiguous_primary" else
      if (anyDuplicated(individual_key[related])) "duplicate_family_records" else
      if (any(a$secondary_bole[related]) && !all(a$growthForm[related] %in% "multi-bole tree"))
        "inconsistent_growth_form" else
      if (anyNA(a$subplotID[related]) || length(unique(a$subplotID[related])) != 1L)
        "inconsistent_subplots" else
      if (any(neon_support_flagged(a$dataQF[related])) ||
          any(is.na(mi[related])) || any(neon_support_flagged(latest$dataQF[mi[related]])))
        "quality_or_mapping_unresolved" else "documented_family"
    heights <- related[live(a$plantStatus[related]) & is.finite(a$height[related]) &
      a$height[related] > 0 & !neon_support_flagged(a$dataQF[related])]
    own_height <- is.finite(a$height[i]) && a$height[i] > 0
    broken <- grepl("broken", a$plantStatus[i], fixed = TRUE) &&
      is.finite(a$breakHeight[i]) && a$breakHeight[i] > 0
    p <- if (length(primary) == 1L) primary else NA_integer_
    primary_live <- !is.na(p) && live(a$plantStatus[p])
    primary_height <- !is.na(p) && is.finite(a$height[p]) && a$height[p] > 0
    classification <- if (a$subplot_conflict[i]) "subplot_boundary_discrepancy" else
      if (a$exclusion[i] == "missing_mapping_uncertainty") "unknown_anchor_uncertainty" else
      if (!a$exclusion[i] %in% c("missing_mapping_coordinates", "invalid_height"))
        "unresolved_required_measurement" else
      if (relation != "documented_family") "unresolved_family_evidence" else
      if (a$secondary_bole[i] && !primary_live && own_height)
        "live_secondary_with_dead_primary" else
      if (a$secondary_bole[i] && primary_live && primary_height)
        "additional_bole_individual_measurements" else
      if (!a$secondary_bole[i] && broken && any(heights != i))
        "broken_primary_height_on_relative" else "unresolved_required_measurement"
    explained <- classification %in% c("additional_bole_individual_measurements",
      "live_secondary_with_dead_primary", "broken_primary_height_on_relative")
    failures <- c(if (!is.finite(a$E[i]) || !is.finite(a$N[i])) "coordinates",
                  if (!is.finite(a$pos_unc[i])) "uncertainty", if (!own_height) "height",
                  if (a$subplot_conflict[i]) "subplot")
    distance <- NA_real_
    b <- bundles[[neon_support_key(a$plotID[i], a$eventID[i])]]
    if (!is.null(b) && is.finite(a$E[i]) && is.finite(a$N[i])) {
      g <- sf::st_geometry(b$subplots)[which(b$subplots$subplotID == a$subplotID[i])]
      if (length(g) == 1L) {
        point <- sf::st_sfc(sf::st_point(c(a$E[i], a$N[i])), crs = b$epsg)
        distance <- as.numeric(sf::st_distance(point, g))
      }
    }
    data.frame(plot = a$plotID[i], event = a$eventID[i], individual_id = a$individualID[i],
      measurement_uid = a$uid[i], mapping_uid = a$source_mapping_uid[i],
      original_exclusion = a$exclusion[i], observed_missing_or_conflicting = paste(failures, collapse = "|"),
      family_id = a$family_id[i], family_relation = relation, secondary_bole = a$secondary_bole[i],
      family_records = length(related), primary_id = a$individualID[p],
      primary_status = a$plantStatus[p], primary_height = a$height[p],
      source_record_type = a$mapping_record_type[i], source_height = a$height[i],
      source_break_height = a$breakHeight[i],
      height_evidence_ids = paste(a$individualID[heights], collapse = "|"),
      height_evidence_values = paste(a$height[heights], collapse = "|"),
      height_evidence_dbh = paste(a$stemDiameter[heights], collapse = "|"),
      distance_to_recorded_subplot_m = distance, positional_margin_m = a$pos_unc[i],
      excess_over_margin_m = if (is.finite(distance) && is.finite(a$pos_unc[i]))
        max(0, distance - a$pos_unc[i]) else NA_real_,
      classification = classification,
      disposition = if (explained) "explained_population_policy_required" else "unresolved_source_review",
      evaluation_ready = FALSE, source_values_changed = FALSE)
  })
  records <- do.call(rbind, rows)
  members <- a[!is.na(a$family_id) & family_key %in% family_key[flagged], ]
  plots <- do.call(rbind, lapply(bundles, function(b) {
    r <- records[records$plot == b$plot & records$event == b$event, ]
    data.frame(plot = b$plot, event = b$event, support_id = neon_support_identity(b),
      n_selected_unchanged = sum(b$references$reference_selected), n_flagged_records = nrow(r),
      n_explained_not_admitted = sum(r$disposition == "explained_population_policy_required"),
      n_unresolved_source_review = sum(r$disposition == "unresolved_source_review"),
      blockers = paste(b$blockers, collapse = "|"), evaluation_ready = FALSE,
      population_policy_review = TRUE)
  }))
  list(records = records, members = members, plots = plots)
}

neon_flight_identity <- function(name) {
  parts <- regmatches(name, regexec(
    "^NEON_D01_HARV_DPQA_(L[0-9]+-[0-9]+)_([0-9]{8})[0-9]{2}_boundary[.]kml$", name))[[1]]
  if (length(parts) != 3L) stop("Unsupported HARV flightline identity")
  date <- as.Date(parts[3], "%Y%m%d")
  if (is.na(date)) stop("Invalid flight date")
  list(line = parts[2], date = date)
}

neon_flight_enclosure <- function(geometry, epsg) {
  if (is.na(sf::st_crs(geometry))) stop("Flight boundary lacks CRS")
  g <- sf::st_transform(sf::st_zm(sf::st_geometry(geometry)), epsg)
  if (all(sf::st_geometry_type(g) %in% c("LINESTRING", "MULTILINESTRING"))) {
    # KML boundary rings contain self-intersections. Noding gives conservative
    # candidate enclosures, including hole faces; this is not verified coverage.
    g <- sf::st_collection_extract(sf::st_polygonize(sf::st_node(g)), "POLYGON")
  }
  if (!length(g) || any(sf::st_is_empty(g)) || any(!sf::st_is_valid(g)) ||
      !all(sf::st_geometry_type(g) %in% c("POLYGON", "MULTIPOLYGON")))
    stop("Flight boundary does not form a valid enclosure")
  sf::st_union(g)
}

neon_week_time_candidates <- function(gps, dates, gps_utc_offset) {
  if (!length(gps) || any(!is.finite(gps) | gps < 0 | gps >= 604800))
    stop("Invalid GPS week seconds")
  dates <- sort(unique(as.Date(dates)))
  if (!length(dates) || anyNA(dates)) stop("Flight candidates require explicit dates")
  if (length(gps_utc_offset) != 1L || !is.finite(gps_utc_offset) || gps_utc_offset < 0 ||
      gps_utc_offset >= 86400) stop("Explicit GPS/UTC offset required")
  # UTC calendar day can differ near GPS midnight. Include both
  # possibilities, never manufacture an exact timestamp from a missing week.
  gps_days <- floor(gps / 86400)
  utc_days <- floor(((gps - gps_utc_offset) %% 604800) / 86400)
  weekday <- as.POSIXlt(dates, tz = "UTC")$wday
  dates[vapply(weekday, function(day) all(day == gps_days | day == utc_days), logical(1))]
}

neon_link_flight_source <- function(source_id, candidate_dates, lines) {
  neon_support_require(lines, c("file_source_id", "line", "date", "intersects_buffer"), "Flight headers")
  if (length(source_id) != 1L || !is.finite(source_id) || source_id < 0 || source_id > 65535)
    stop("Invalid Point Source ID")
  matched <- lines[which(!is.na(lines$file_source_id) & lines$file_source_id == source_id), ]
  verified <- source_id != 0 && nrow(matched) == 1L &&
    isTRUE(matched$intersects_buffer) && matched$date %in% candidate_dates
  list(lines = paste(matched$line, collapse = "|"),
       dates = paste(sort(unique(matched$date)), collapse = "|"), verified = verified)
}
