# TEAK-only diagnostic reconstruction, using unchanged NEON support semantics.
teak_plots <- function() c("TEAK_004", "TEAK_005", "TEAK_010", "TEAK_016",
                           "TEAK_018", "TEAK_024", "TEAK_025")
teak_events <- function(dat) {
  pp <- unique(as.data.frame(dat$vst_perplotperyear))
  pp <- pp[pp$plotID %in% teak_plots() & !is.na(pp$date) & substr(pp$date, 1, 4) == "2022", ]
  if (nrow(pp) != 7L || anyDuplicated(pp$plotID) || !setequal(pp$plotID, teak_plots()))
    stop("Require exactly one 2022 event for each of the seven declared plots")
  pp[match(teak_plots(), pp$plotID), ]
}
teak_measurements <- function(dat) {
  ai <- as.data.frame(dat$vst_apparentindividual)
  ai[ai$plotID %in% teak_plots() & !is.na(ai$date) & substr(ai$date, 1, 4) == "2022", ]
}
teak_needed_locations <- function(dat, events) {
  a <- teak_measurements(dat)
  m <- neon_latest_mapping(dat$vst_mappingandtagging)
  m <- m[neon_support_key(m$plotID, m$individualID) %in%
    neon_support_key(a$plotID, a$individualID), ]
  mapped <- paste(m$namedLocation[!is.na(m$pointID)], m$pointID[!is.na(m$pointID)], sep = ".")
  corners <- unlist(lapply(seq_len(nrow(events)), function(i)
    tryCatch(paste(events$namedLocation[i], unlist(neon_event_subplots(events[i, ])), sep = "."),
             error = function(e) character())))
  needed <- sort(unique(c(mapped, corners)))
  if (any(!grepl("^TEAK_[0-9]{3}[.]basePlot[.]vst[.][0-9]+$", needed)))
    stop("Unexpected named-point identity")
  needed
}
teak_location_url <- function(name) {
  paste0("https://data.neonscience.org/api/v0/locations/", name, "?history=true")
}
teak_location_dates <- function(dat, events, name) {
  plot <- sub("[.].*$", "", name)
  a <- teak_measurements(dat)
  m <- neon_latest_mapping(dat$vst_mappingandtagging)
  idx <- match(neon_support_key(a$plotID, a$individualID),
               neon_support_key(m$plotID, m$individualID))
  use <- which(paste(m$namedLocation[idx], m$pointID[idx], sep = ".") == name)
  dates <- unique(c(as.character(events$date[events$plotID == plot]),
                    as.character(a$date[use]), as.character(m$date[idx[use]])))
  if (!length(dates) || anyNA(dates)) stop("Missing named-point epoch")
  sort(dates)
}
teak_location_row <- function(record, name, epsg, dates) {
  if (!identical(record$location, name)) stop("Cached request identity mismatch")
  if (!identical(record$url, teak_location_url(name))) stop("Cached history request URL mismatch")
  if (!identical(as.integer(record$status), 200L)) stop("Unsuccessful location response")
  if (!is.character(record$response_body) || length(record$response_body) != 1L ||
      !identical(digest::digest(charToRaw(record$response_body), algo = "sha256",
                               serialize = FALSE), record$response_sha256))
    stop("Raw response SHA-256 mismatch or missing body")
  # Only verified raw response data are authoritative; ignore derived wrapper.data.
  loc <- jsonlite::fromJSON(record$response_body, simplifyVector = FALSE)$data
  if (!identical(loc$locationName, name)) stop("Returned location identity mismatch")
  history <- loc$locationHistory
  if (!is.list(history) || !length(history)) stop("Missing location history")
  parse_time <- function(x) {
    if (!is.character(x) || length(x) != 1L ||
        !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", x))
      stop("Malformed location history interval")
    value <- as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    if (is.na(value)) stop("Malformed location history interval")
    as.numeric(value)
  }
  starts <- vapply(history, function(h) parse_time(h$locationStartDate), numeric(1))
  ends <- vapply(history, function(h) {
    if (is.null(h$locationEndDate)) {
      if (!isTRUE(h$current)) stop("Unbounded noncurrent location history")
      Inf
    } else parse_time(h$locationEndDate)
  }, numeric(1))
  if (any(ends <= starts)) stop("Malformed location history interval")
  if (!length(dates) || anyNA(dates) ||
      any(!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", dates))) stop("Missing or invalid named-point epoch")
  epochs <- as.numeric(as.POSIXct(dates, format = "%Y-%m-%d", tz = "UTC"))
  if (anyNA(epochs)) stop("Missing or invalid named-point epoch")
  selected <- vapply(epochs, function(day) {
    # Dates have day resolution: reject any interval transition within that day.
    overlaps <- which(starts < day + 86400 & ends > day)
    if (length(overlaps) != 1L || starts[overlaps] > day || ends[overlaps] < day + 86400)
      stop("Missing or ambiguous location history at field epoch")
    overlaps
  }, integer(1))
  rows <- lapply(unique(selected), function(i) {
    h <- history[[i]]
    h$locationProperties <- do.call(rbind, lapply(h$locationProperties, function(p) {
      value <- p$locationPropertyValue
      data.frame(locationPropertyName = p$locationPropertyName,
                 locationPropertyValue = if (is.null(value)) NA_character_ else as.character(value))
    }))
    frame <- neon_location_frame(h)
    if (frame$epsg != epsg) stop("Named-point CRS differs from field frame")
    props <- h$locationProperties
    unc <- props$locationPropertyValue[props$locationPropertyName == "Value for Coordinate uncertainty"]
    if (length(unc) != 1L || !is.finite(suppressWarnings(as.numeric(unc))) || as.numeric(unc) < 0)
      stop("Missing or invalid coordinate uncertainty")
    xy <- c(h$locationUtmEasting, h$locationUtmNorthing)
    if (length(xy) != 2L || any(!is.finite(xy))) stop("Missing named-point coordinates")
    data.frame(ptloc = name, easting = xy[1], northing = xy[2],
      zone = paste0(h$locationUtmZone, h$locationUtmHemisphere), unc = as.numeric(unc), epsg = epsg)
  })
  if (nrow(unique(do.call(rbind, rows))) != 1L)
    stop("Named-point coordinates or uncertainty differ across field and mapping epochs")
  row <- rows[[1]]
  row$epoch_dates <- paste(dates, collapse = "|")
  row$history_indices <- paste(selected, collapse = "|")
  row$history_start <- paste(vapply(history[unique(selected)], `[[`, character(1), "locationStartDate"), collapse = "|")
  row$history_end <- paste(vapply(history[unique(selected)], function(h)
    if (is.null(h$locationEndDate)) "open" else h$locationEndDate, character(1)), collapse = "|")
  row
}
teak_build <- function(dat, events, points, epsg, contract) {
  a <- teak_measurements(dat)
  pp <- as.data.frame(dat$vst_perplotperyear)
  pp <- pp[pp$plotID %in% teak_plots(), ]
  refs <- neon_event_references(a, pp, dat$vst_mappingandtagging, points, 2022L, epsg)
  refs$mapping_after_event <- as.Date(refs$mapping_date) > as.Date(refs$census_date)
  refs$mapping_after_measurement <- as.Date(refs$mapping_date) > as.Date(refs$measurement_date)
  cols <- c("inside_sampled", "inside_interior", "boundary_uncertain", "subplot_conflict", "reference_selected")
  for (col in cols) refs[[col]] <- NA
  bundles <- list(); rows <- list()
  for (i in seq_len(nrow(events))) {
    ev <- events[i, ]; key <- neon_support_key(ev$plotID, ev$eventID)
    b <- tryCatch(neon_build_support(ev, refs, points, epsg), error = function(e) e)
    row <- data.frame(plot = ev$plotID, event = ev$eventID, status = "geometry_failed",
      nominal_area_m2 = ev$totalSampledAreaTrees, measured_area_m2 = NA_real_,
      interior_area_m2 = NA_real_, boundary_margin_m = NA_real_,
      n_records = sum(refs$plotID == ev$plotID), n_target = sum(refs$plotID == ev$plotID & refs$target_population),
      n_eligible = sum(refs$plotID == ev$plotID & refs$reference_eligible), n_selected = NA_integer_, n_boundary = NA_integer_,
      n_outside = NA_integer_, n_subplot_conflict = NA_integer_,
      blockers = "", support_id = NA_character_, evaluation_ready = FALSE)
    if (inherits(b, "error")) {
      row$blockers <- conditionMessage(b)
    } else {
      b$input_contract <- contract
      b$blockers <- unique(c(b$blockers, "native_density_coverage_pending", "checkpoint_exposure_pending"))
      b$evaluation_ready <- FALSE
      bundles[[key]] <- b
      rr <- b$references
      refs[match(rr$reference_row, refs$reference_row), cols] <- rr[cols]
      row$status <- "measured_corners_diagnostic"
      row$measured_area_m2 <- b$measured_area_m2; row$interior_area_m2 <- b$interior_area_m2
      row$boundary_margin_m <- b$boundary_margin_m
      row$n_eligible <- sum(rr$reference_eligible); row$n_selected <- sum(rr$reference_selected)
      row$n_boundary <- sum(rr$boundary_uncertain)
      row$n_outside <- sum(rr$reference_eligible & !rr$inside_sampled)
      row$n_subplot_conflict <- sum(rr$subplot_conflict)
      row$blockers <- paste(b$blockers, collapse = "|")
      row$support_id <- neon_support_identity(b)
    }
    rows[[key]] <- row
  }
  list(references = refs, summaries = do.call(rbind, rows), bundles = bundles)
}
teak_exposure_paths <- function(root) {
  nd <- file.path(root, "neon/TEAK")
  csv <- sort(unique(c(list.files(nd, "[.]csv$", full.names = TRUE),
    file.path(nd, "ql2/ql2_detect_results.csv"),
    list.files(file.path(root, "neon"), "[.]csv$", full.names = TRUE))))
  csv <- csv[file.exists(csv) & !basename(csv) %in% c("ground_truth_stems.csv",
    "plot_centroids.csv", "point_locations.csv", "tiles_needed.csv")]
  roots <- unique(c(file.path(nd, c("best_treetop_cache", "frozen")),
                    list.dirs(nd, recursive = FALSE, full.names = TRUE)))
  roots <- roots[grepl("(cache|frozen|instances)$", roots)]
  paths <- sort(unique(unlist(lapply(roots, list.files, recursive = TRUE, full.names = TRUE))))
  data.frame(path = c(csv, paths), kind = c(rep("csv", length(csv)), rep("artifact_path", length(paths))))
}
