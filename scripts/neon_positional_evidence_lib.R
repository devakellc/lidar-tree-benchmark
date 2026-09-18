# Diagnostic hypotheses only: never update a reference or an admission flag.
neon_offset_hypotheses <- function(easting, northing, distance, azimuth, epsg) {
  values <- c(easting, northing, distance, azimuth, epsg)
  if (length(values) != 5L || any(!is.finite(values)) || distance < 0 ||
      azimuth < 0 || azimuth > 360 || !epsg %in% c(32618L, 32619L))
    stop("Invalid eastern offset inputs")
  theta <- azimuth * pi / 180
  delta <- c(distance * sin(theta), distance * cos(theta))
  anchor <- sf::st_sfc(sf::st_point(c(easting, northing)), crs = epsg)
  ll <- sf::st_coordinates(sf::st_transform(anchor, 4326))[1, ]
  local <- sprintf("+proj=aeqd +lat_0=%.12f +lon_0=%.12f +datum=WGS84 +units=m +no_defs", ll[2], ll[1])
  alternative <- sf::st_transform(sf::st_sfc(sf::st_point(delta), crs = local), epsg)
  xy <- sf::st_coordinates(alternative)[1, ]
  grid <- c(easting, northing) + delta
  data.frame(grid_E = grid[1], grid_N = grid[2], true_north_E = unname(xy[1]),
    true_north_N = unname(xy[2]), hypothesis_shift_m = sqrt(sum((xy - grid)^2)),
    correction_applied = FALSE, evaluation_ready = FALSE)
}

neon_trajectory_interval <- function(lines, name) {
  if (!grepl("^2022[0-9]{6}_P3C1_SBET_QAQC[.]pdf$", name)) stop("Unexpected trajectory report identity")
  stamp <- substr(name, 1, 10)
  date <- as.Date(substr(stamp, 1, 8), "%Y%m%d")
  if (is.na(date) || !any(grepl(paste("flown on", stamp), lines, fixed = TRUE)))
    stop("Trajectory report date mismatch")
  number <- function(label) {
    pattern <- paste0("^\\s*", label, ":\\s*([0-9]+[.][0-9]+)\\s*$")
    matched <- grep(pattern, lines, value = TRUE)
    if (length(matched) != 1L) stop("Missing or ambiguous ", label)
    as.numeric(sub(pattern, "\\1", matched))
  }
  start <- number("Trajectory start time"); end <- number("Trajectory end time")
  if (!is.finite(start) || !is.finite(end) || start < 0 || end >= 604800 || end <= start)
    stop("Unsupported trajectory week-time interval")
  data.frame(report = name, date = as.character(date), start_week_seconds = start,
             end_week_seconds = end, exact_flightline_verified = FALSE)
}

neon_trajectory_compatibility <- function(intervals, point_time) {
  neon_support_require(intervals, c("date", "start_week_seconds", "end_week_seconds"), "Trajectory intervals")
  neon_support_require(point_time, c("gps_week_min", "gps_week_max", "schedule_dates"), "Point times")
  if (nrow(point_time) != 1L || any(!is.finite(c(point_time$gps_week_min, point_time$gps_week_max))) ||
      point_time$gps_week_min < 0 || point_time$gps_week_max >= 604800 ||
      point_time$gps_week_max < point_time$gps_week_min || is.na(point_time$schedule_dates))
    stop("Invalid bounded point-time evidence")
  dates <- strsplit(point_time$schedule_dates, "|", fixed = TRUE)[[1]]
  intervals$time_range_contained <- point_time$gps_week_min >= intervals$start_week_seconds &
    point_time$gps_week_max <= intervals$end_week_seconds
  intervals$schedule_compatible <- intervals$date %in% dates
  intervals$mission_interval_compatible <- intervals$time_range_contained & intervals$schedule_compatible
  intervals$exact_flightline_verified <- FALSE
  intervals
}

neon_named_point_evidence <- function(record) {
  if (!is.null(record$status) && record$status != 200L) stop("Unavailable named-point snapshot")
  loc <- record$data
  if (is.null(loc$locationName) || length(loc$locationName) != 1L || !nzchar(loc$locationName))
    stop("Missing named-point identity")
  p <- loc$locationProperties
  neon_support_require(p, c("locationPropertyName", "locationPropertyValue"), "Named-point properties")
  if (anyNA(p$locationPropertyName) || anyDuplicated(p$locationPropertyName))
    stop("Ambiguous named-point properties")
  get <- function(name) {
    x <- p$locationPropertyValue[p$locationPropertyName == paste("Value for", name)]
    if (length(x)) as.character(x) else NA_character_
  }
  raw_unc <- get("Coordinate uncertainty")
  unc <- suppressWarnings(as.numeric(raw_unc))
  data.frame(location = loc$locationName, coordinate_source = get("Coordinate source"),
    datum_label = get("Geodetic datum"), coordinate_uncertainty_raw = raw_unc,
    coordinate_uncertainty_m = unc, uncertainty_available = is.finite(unc) && unc >= 0,
    epoch_property_present = any(grepl("epoch|survey date", p$locationPropertyName, ignore.case = TRUE)),
    realization_property_present = any(grepl("realization", p$locationPropertyName, ignore.case = TRUE)),
    evaluation_ready = FALSE)
}
