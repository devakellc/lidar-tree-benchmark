# Open Forest Observatory (OFO) second preflight (docs/ofo-preflight-protocol-2.md)
# for groups A and B: "Disturbance between survey and flight" (fire
# perimeters, Forest Service activity records, canopy over mapped trees),
# the two further gates of "Registering catalogue plots" (one clear peak,
# signals agree) and the protocol-2 tables the decision stage reads
# (registration.csv, conditions.csv). Pure functions; file reads take
# explicit paths, and the drivers (preflight_ofo_disturbance.R,
# preflight_ofo2_assemble.R) query the services, read the clouds and write
# the tables. Score-blind: no detector runs; the canopy check reads the frozen
# method's surface at mapped stems.
# Needs ofo_preflight_lib.R, ofo_reference_lib.R, ofo_registration_lib.R and
# ofo_conditions_lib.R sourced first (ofo_stage_record, OFO_GROUP_SIGNAL,
# OFO_REG2, ofo_flight_dates, ofo_conditions_admitted, ofo_lgl).

## ---- record sources ----------------------------------------------------------------

OFO_FIRE_HISTORY_URL <- paste0("https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/",
  "services/InterAgencyFirePerimeterHistory_All_Years_View/FeatureServer/0")
OFO_WFIGS_URL <- paste0("https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/",
  "services/WFIGS_Interagency_Perimeters/FeatureServer/0")
OFO_EDW_URL <- "https://apps.fs.usda.gov/arcx/rest/services/EDW"
.ofo_edw <- function(service, layer) sprintf("%s/%s/MapServer/%d", OFO_EDW_URL, service, layer)

# Every layer queried per plot. `record`: fire, harvest, fuels, tsi or
# ownership. `date_rule`: fire_year (history: FIRE_YEAR_INT, else the FIRE_YEAR
# string), discovery_date (WFIGS attr_FireDiscoveryDateTime) or date_completed
# (the Forest Service layers' completion date, FACTS DATE_ACCOMPLISHED; every
# feature of these layers carries one, and the stage_desc field says at
# which stage its polygon was mapped, not whether the activity is done).
# The harvest and stand-improvement layers are split by fiscal year (the
# 2011-2020 layers end on 30 September 2020), so both are queried. The
# hazardous-fuel layers are the five of the group "Treatments - Completed".
# NFS land: the surface-ownership parcels of the Land Status Record System
# (owner "USDA FOREST SERVICE"), the land the activity records describe.
OFO_DIST_SOURCES <- data.frame(
  source = c("fire_history", "fire_wfigs", "harvest_2011_2020", "harvest_2021_current",
             "fuels_fire", "fuels_other", "fuels_mechanical", "fuels_wildfire_nontreatment",
             "fuels_all_other", "tsi_2011_2020", "tsi_2021_current", "nfs_surface_ownership"),
  record = c("fire", "fire", "harvest", "harvest", rep("fuels", 5), "tsi", "tsi", "ownership"),
  url = c(OFO_FIRE_HISTORY_URL, OFO_WFIGS_URL,
          .ofo_edw("EDW_TimberHarvest_01", 0L), .ofo_edw("EDW_TimberHarvest_01", 11L),
          vapply(3:7, function(l) .ofo_edw("EDW_HazardousFuelsTreatments_01", l), ""),
          .ofo_edw("EDW_SilvicultureTimberstandImprovement_01", 0L),
          .ofo_edw("EDW_SilvicultureTimberstandImprovement_01", 9L),
          .ofo_edw("EDW_SurfaceOwnership_01", 0L)),
  layer_name = c("InteragencyFirePerimeterHistory", "WFIGS Interagency Perimeters",
                 "Timber Harvest 2011 - 2020", "Timber Harvest 2021 - Current",
                 "Treatments - Completed: Fire", "Treatments - Completed: Other",
                 "Treatments - Completed: Mechanical",
                 "Treatments - Completed: Wildfire Non-Treatment",
                 "Treatments - Completed: All Other Values",
                 "Silviculture Timber Stand Improvement 2011 - 2020",
                 "Silviculture Timber Stand Improvement 2021 - Current",
                 "BdyOwn_LSRS_SurfaceOwnership"),
  oid = c("OBJECTID", "OBJECTID", rep("objectid", 10)),
  date_rule = c("fire_year", "discovery_date", rep("date_completed", 9), "none"),
  date_field = c("FIRE_YEAR_INT", "attr_FireDiscoveryDateTime", rep("date_completed", 9), ""),
  name_field = c("INCIDENT", "poly_IncidentName", "activity_name", "activity_name",
                 rep("activity", 5), "activity_name", "activity_name", "ownerclassification"),
  category_field = c("FEATURE_CA", "attr_IncidentTypeCategory", rep("treatment_type", 9),
                     "nfslandunitname"),
  stringsAsFactors = FALSE)

OFO_DIST_QUERY_BUFFER_M <- 1000   # envelope of the plot buffered by this, in WGS 84
OFO_DIST_FIRE_BUFFER_M <- 50      # fire perimeters: the plot polygon buffered by 50 m
OFO_DIST_NFS_OWNER <- "USDA FOREST SERVICE"
# Dates before this are placeholders. Fire years have their own rule
# (ofo_dist_fire_year): reconstructed fires older than this are years.
OFO_DIST_MIN_DATE <- as.Date("1800-01-01")
OFO_DIST_GROUPS <- c("A", "B")

## ---- interval --------------------------------------------------------------------------

# 1 January of the survey year to the plot's last flight day (the latest of
# flights.csv `flight_days`, the UTC days with returns in the plot). Without
# flight days the end is NA, and a last flight day before the start (a flight
# before the survey year) leaves the declared interval empty: in both cases no
# record check can be made (`interval_problem`: no_interval or
# interval_reversed; empty when the interval exists).
ofo_dist_interval <- function(survey_year, flight_days) {
  sy <- suppressWarnings(as.integer(survey_year))
  fd <- rep_len(as.character(flight_days), length(sy))
  start <- as.Date(ifelse(is.na(sy), NA_character_, sprintf("%04d-01-01", sy)))
  end <- as.Date(vapply(fd, function(f) {
    d <- ofo_flight_dates(f)
    if (length(d)) format(max(d)) else NA_character_
  }, character(1), USE.NAMES = FALSE))
  problem <- ifelse(is.na(start) | is.na(end), "no_interval",
                    ifelse(end < start, "interval_reversed", ""))
  data.frame(interval_start = start, interval_end = end, interval_problem = problem,
             stringsAsFactors = FALSE)
}

## ---- dates ---------------------------------------------------------------------------------

.ofo_dist_vec <- function(x, mode = "numeric") {
  if (is.list(x)) x <- lapply(x, function(z) if (is.null(z) || !length(z)) NA else z[[1]])
  v <- unlist(x, use.names = FALSE)
  if (is.null(v)) v <- vector(mode, 0)
  v
}

# ArcGIS date fields (epoch milliseconds, UTC) as UTC dates. Missing values
# and placeholders (before 1800 or after `latest`, the retrieval date, such
# as 9999-12-31) are NA: such a record cannot be placed in or out of an
# interval.
ofo_dist_epoch_date <- function(ms, latest = Sys.Date()) {
  v <- suppressWarnings(as.numeric(.ofo_dist_vec(ms)))
  d <- as.Date(as.POSIXct(ifelse(is.finite(v), v, 0) / 1000, origin = "1970-01-01", tz = "UTC"),
               tz = "UTC")
  d[!is.finite(v) | d < OFO_DIST_MIN_DATE | d > as.Date(latest)] <- NA
  d
}

# Fire year of a history record: FIRE_YEAR_INT where it is a year, else the
# FIRE_YEAR string where that is one. The placeholders 0, 1000 and 9999 and
# years after the retrieval year are NA. Years before 1800 are years: the
# layer holds reconstructed fires (1250, 1308, ...), and treating them as
# unknown would leave a plot's fire check unmade for a fire centuries old.
OFO_DIST_YEAR_PLACEHOLDERS <- c(0L, 1000L, 9999L)
ofo_dist_fire_year <- function(year_int, year_str = NULL, latest = Sys.Date()) {
  ly <- as.integer(format(as.Date(latest), "%Y"))
  ok <- function(y) !is.na(y) & y >= 1L & y <= ly & !y %in% OFO_DIST_YEAR_PLACEHOLDERS
  y1 <- suppressWarnings(as.integer(.ofo_dist_vec(year_int)))
  y2 <- if (is.null(year_str)) rep(NA_integer_, length(y1)) else
    suppressWarnings(as.integer(trimws(as.character(.ofo_dist_vec(year_str, "character")))))
  y2 <- rep_len(y2, length(y1))
  ifelse(ok(y1), y1, ifelse(ok(y2), y2, NA_integer_))
}

# Whether a date (or a year) lies in [start, end], both ends included; NA when
# either the value or the interval is unknown.
ofo_dist_in_dates <- function(date, start, end) {
  date <- as.Date(date); start <- as.Date(start); end <- as.Date(end)
  out <- date >= start & date <= end
  out[is.na(date) | is.na(start) | is.na(end)] <- NA
  out
}

# The interval's years are those of its start and end: the history layer
# gives a year only.
ofo_dist_in_years <- function(year, start, end) {
  y0 <- as.integer(format(as.Date(start), "%Y")); y1 <- as.integer(format(as.Date(end), "%Y"))
  year <- as.integer(year)
  out <- year >= y0 & year <= y1
  out[is.na(year) | is.na(y0) | is.na(y1)] <- NA
  out
}

## ---- queries and responses ------------------------------------------------------------

# WGS 84 envelope (xmin, ymin, xmax, ymax) of the plot polygon (sfc, project
# frame) buffered by `buffer_m`; the buffer is densified before the
# transform so the envelope holds all of it.
ofo_dist_envelope <- function(poly, buffer_m = OFO_DIST_QUERY_BUFFER_M) {
  b <- sf::st_buffer(sf::st_union(sf::st_geometry(poly)), buffer_m)
  bb <- sf::st_bbox(sf::st_transform(sf::st_segmentize(b, 25), 4326))
  c(xmin = bb[["xmin"]], ymin = bb[["ymin"]], xmax = bb[["xmax"]], ymax = bb[["ymax"]])
}

# Query URL of one layer: every feature intersecting the envelope, all fields,
# geometry in WGS 84, ordered by object ID so pages (resultOffset) are stable.
ofo_dist_query_url <- function(layer_url, envelope, oid, offset = 0L) {
  p <- c(where = "1=1",
         geometry = sprintf("%.7f,%.7f,%.7f,%.7f", envelope[["xmin"]], envelope[["ymin"]],
                            envelope[["xmax"]], envelope[["ymax"]]),
         geometryType = "esriGeometryEnvelope", inSR = "4326",
         spatialRel = "esriSpatialRelIntersects", outFields = "*", returnGeometry = "true",
         outSR = "4326", orderByFields = oid, f = "json")
  if (offset > 0) p <- c(p, resultOffset = as.character(as.integer(offset)))
  paste0(layer_url, "/query?", paste(names(p), curl::curl_escape(p), sep = "=", collapse = "&"))
}

# Attributes of Esri JSON features (a list, as jsonlite parses it without
# simplification) as a data frame, one row per feature: numeric where every
# value is a number (dates stay epoch milliseconds), character otherwise.
ofo_dist_attributes <- function(features) {
  if (!length(features)) return(data.frame())
  keys <- unique(unlist(lapply(features, function(f) names(f$attributes))))
  cols <- lapply(stats::setNames(keys, keys), function(k) {
    v <- lapply(features, function(f) f$attributes[[k]])
    if (all(vapply(v, function(z) is.null(z) || is.numeric(z), logical(1))))
      vapply(v, function(z) if (is.null(z)) NA_real_ else as.numeric(z), numeric(1))
    else vapply(v, function(z) if (is.null(z)) NA_character_ else as.character(z[[1]]),
                character(1))
  })
  as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE)
}

# A column by name, ignoring case (the Forest Service layers name fields in
# lower case), or NA.
ofo_dist_field <- function(attrs, name) {
  if (!nrow(attrs) || is.na(name) || !nzchar(name)) return(rep(NA, nrow(attrs)))
  k <- match(tolower(name), tolower(names(attrs)))
  if (is.na(k)) rep(NA, nrow(attrs)) else attrs[[k]]
}

# One kept response (Esri JSON): attributes parsed here, geometry by GDAL's
# ESRIJSON driver, which organises rings into polygons and holes (a plot in
# an unburned island lies outside its perimeter). Stops on a service error.
ofo_dist_read_response <- function(path) {
  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  js <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  if (!is.null(js$error))
    stop("service error in ", basename(path), ": ", js$error$code, " ", js$error$message,
         call. = FALSE)
  if (!"features" %in% names(js)) stop("no features array in ", basename(path), call. = FALSE)
  feats <- js$features
  attrs <- ofo_dist_attributes(feats)
  geom <- sf::st_sfc(crs = 4326)
  if (length(feats)) {
    x <- withCallingHandlers(sf::st_read(path, drivers = "ESRIJSON", quiet = TRUE),
      warning = function(w) if (grepl("organizePolygons", conditionMessage(w)))
        invokeRestart("muffleWarning"))
    geom <- sf::st_geometry(x)
    if (length(geom) != nrow(attrs))
      stop("geometry and attribute counts differ in ", basename(path), call. = FALSE)
  }
  list(attrs = attrs, geom = geom, exceeded = isTRUE(js$exceededTransferLimit))
}

## ---- intersection and per-feature evaluation ------------------------------------------

# Which features (sfc, any CRS) intersect the plot polygon (sfc, project
# frame) buffered by `buffer_m` (0: the polygon itself), and their distance
# to the polygon (m). Features are carried to the project frame first, so the
# buffer is metric.
ofo_dist_hits <- function(geom, poly, buffer_m = 0) {
  if (!length(geom)) return(data.frame(hit = logical(), distance_m = numeric()))
  crs <- sf::st_crs(poly)
  g <- sf::st_make_valid(sf::st_transform(geom, crs))
  p <- sf::st_union(sf::st_geometry(poly))
  target <- if (buffer_m > 0) sf::st_buffer(p, buffer_m) else p
  data.frame(hit = lengths(sf::st_intersects(g, target)) > 0,
             distance_m = as.numeric(sf::st_distance(g, p))[seq_along(g)])
}

OFO_DIST_DETAIL_COLS <- c("plot_id", "source", "record", "oid", "name", "category",
                          "date_field", "date_raw", "event_date", "event_year", "date_known",
                          "in_interval", "hit", "buffer_m", "distance_m")

# One row per feature of one source for one plot. `resp` is
# ofo_dist_read_response(); `src` one row of OFO_DIST_SOURCES; `poly` the plot
# polygon (sfc, project frame); `start`, `end` the interval; `latest` the
# retrieval date (later dates are placeholders). in_interval is NA where the
# date or the interval is unknown, and for ownership parcels.
ofo_dist_features <- function(resp, src, poly, plot_id, start, end, latest) {
  a <- resp$attrs
  n <- nrow(a)
  if (!n) {
    out <- as.data.frame(stats::setNames(replicate(length(OFO_DIST_DETAIL_COLS), logical(),
                                                   simplify = FALSE), OFO_DIST_DETAIL_COLS))
    return(out)
  }
  buf <- if (src$record == "fire") OFO_DIST_FIRE_BUFFER_M else 0
  h <- ofo_dist_hits(resp$geom, poly, buf)
  date <- as.Date(rep(NA_character_, n)); year <- rep(NA_integer_, n)
  raw <- rep(NA_character_, n); inint <- rep(NA, n)
  if (src$date_rule == "fire_year") {
    yi <- ofo_dist_field(a, "FIRE_YEAR_INT"); ys <- ofo_dist_field(a, "FIRE_YEAR")
    year <- ofo_dist_fire_year(yi, ys, latest)
    raw <- paste0(ifelse(is.na(yi), "NA", format(yi, scientific = FALSE, trim = TRUE)), "|",
                  ifelse(is.na(ys), "NA", as.character(ys)))
    inint <- ofo_dist_in_years(year, start, end)
  } else if (src$date_rule %in% c("discovery_date", "date_completed")) {
    v <- ofo_dist_field(a, src$date_field)
    date <- ofo_dist_epoch_date(v, latest)
    year <- as.integer(format(date, "%Y"))
    raw <- ifelse(is.na(v), NA_character_, format(suppressWarnings(as.numeric(v)),
                                                  scientific = FALSE, trim = TRUE))
    inint <- ofo_dist_in_dates(date, start, end)
  }
  nm <- ofo_dist_field(a, src$name_field)
  if (src$source == "fire_wfigs") {
    alt <- ofo_dist_field(a, "attr_IncidentName")
    nm <- ifelse(is.na(nm) | !nzchar(trimws(nm)), alt, nm)
  }
  data.frame(plot_id = plot_id, source = src$source, record = src$record,
             oid = as.character(ofo_dist_field(a, src$oid)), name = as.character(nm),
             category = as.character(ofo_dist_field(a, src$category_field)),
             date_field = src$date_field, date_raw = raw,
             event_date = format(date), event_year = year,
             date_known = src$date_rule == "none" | !is.na(year),
             in_interval = inint, hit = h$hit, buffer_m = buf, distance_m = h$distance_m,
             stringsAsFactors = FALSE)
}

## ---- per-plot summary of the record checks --------------------------------------------

# A record check of one kind (fire, or the Forest Service activities) from
# the detail rows of its sources for one plot. `failed`: sources of that kind
# whose query failed; `interval_problem`: ofo_dist_interval()'s, empty when
# the interval exists. Without an interval the check cannot be made (NA).
# Otherwise a record intersecting the target with its date in the interval is
# evidence (FALSE); the check cannot be made (NA) when a query failed or an
# intersecting record's date is unknown (placeholder); else it passes (TRUE).
ofo_dist_check <- function(det, failed = character(), interval_problem = "") {
  has_interval <- is.na(interval_problem) || !nzchar(interval_problem)
  hit <- det$hit %in% TRUE
  inn <- hit & det$in_interval %in% TRUE & has_interval
  # Unknown: the record's own date is a placeholder (not merely that the plot
  # has no interval to compare it with).
  unknown <- hit & !(det$date_known %in% TRUE)
  label <- function(k) {
    if (!any(k)) return("")
    y <- ifelse(is.na(det$event_date[k]) | det$event_date[k] %in% "NA",
                as.character(det$event_year[k]), det$event_date[k])
    s <- sprintf("%s (%s, %s)", ifelse(is.na(det$name[k]), "unnamed", det$name[k]),
                 ifelse(is.na(y), "date unknown", y), det$source[k])
    paste(sort(unique(s), method = "radix"), collapse = "; ")
  }
  clear <- if (!has_interval) NA else if (any(inn)) FALSE
           else if (length(failed) || any(unknown)) NA else TRUE
  why <- if (!has_interval) interval_problem else if (any(inn)) "record_in_interval"
         else if (length(failed)) paste0("query_failed:", paste(failed, collapse = ","))
         else if (any(unknown)) "record_date_unknown" else ""
  list(n = if (has_interval) sum(inn) else NA_integer_, names = label(inn), clear = clear,
       n_hit = sum(hit), n_unknown = sum(unknown),
       n_outside = sum(hit & det$in_interval %in% FALSE), why = why)
}

# Whether the plot polygon intersects National Forest System land: TRUE when
# a surface-ownership parcel of the Forest Service intersects it, FALSE when
# none does, NA when the ownership query failed.
ofo_dist_nfs <- function(det, failed = FALSE) {
  if (failed) return(list(nfs = NA, units = ""))
  k <- det$hit %in% TRUE & toupper(trimws(det$name)) %in% OFO_DIST_NFS_OWNER
  list(nfs = any(k), units = paste(sort(unique(stats::na.omit(det$category[k])),
                                        method = "radix"), collapse = "; "))
}

OFO_DIST_RECORD_COLS <- c("plot_id", "project_name", "group", "interval_start", "interval_end",
                          "n_fire_records", "fire_names", "fire_clear", "n_activity_records",
                          "activity_names", "nfs_records_source", "activities_clear")

# Records of the detail rows `d` matching `keep` that intersect their target
# with a date in the interval.
.ofo_dist_count <- function(d, keep) sum(keep & d$hit %in% TRUE & d$in_interval %in% TRUE)

# Per-plot record checks from the detail rows of every source (`det`, all
# plots) and the failed queries (`fail`: data frame of plot_id, source).
# `plots` holds plot_id, project_name, group and ofo_dist_interval()'s columns.
ofo_dist_record_table <- function(plots, det, fail) {
  rk <- OFO_DIST_SOURCES$record[match(det$source, OFO_DIST_SOURCES$source)]
  fk <- OFO_DIST_SOURCES$record[match(fail$source, OFO_DIST_SOURCES$source)]
  rows <- lapply(seq_len(nrow(plots)), function(i) {
    pid <- plots$plot_id[i]
    ip <- plots$interval_problem[i]
    d <- det[det$plot_id == pid, , drop = FALSE]; r <- rk[det$plot_id == pid]
    fs <- fail$source[fail$plot_id == pid]; fr <- fk[fail$plot_id == pid]
    fire <- ofo_dist_check(d[r == "fire", , drop = FALSE], fs[fr == "fire"], ip)
    act <- ofo_dist_check(d[r %in% c("harvest", "fuels", "tsi"), , drop = FALSE],
                          fs[fr %in% c("harvest", "fuels", "tsi")], ip)
    nfs <- ofo_dist_nfs(d[r == "ownership", , drop = FALSE], any(fr == "ownership"))
    data.frame(plot_id = pid, project_name = plots$project_name[i], group = plots$group[i],
               interval_start = format(plots$interval_start[i]),
               interval_end = format(plots$interval_end[i]),
               n_fire_records = fire$n, fire_names = fire$names, fire_clear = fire$clear,
               n_activity_records = act$n, activity_names = act$names,
               nfs_records_source = nfs$nfs, activities_clear = act$clear,
               n_fire_history = .ofo_dist_count(d, d$source == "fire_history"),
               n_fire_wfigs = .ofo_dist_count(d, d$source == "fire_wfigs"),
               n_fire_intersecting = fire$n_hit, n_fire_outside_interval = fire$n_outside,
               n_fire_date_unknown = fire$n_unknown, fire_check = fire$why,
               n_harvest = .ofo_dist_count(d, r == "harvest"),
               n_fuels = .ofo_dist_count(d, r == "fuels"), n_tsi = .ofo_dist_count(d, r == "tsi"),
               n_activity_intersecting = act$n_hit, n_activity_outside_interval = act$n_outside,
               n_activity_date_unknown = act$n_unknown, activity_check = act$why,
               nfs_units = nfs$units, queries_failed = paste(fs, collapse = ";"),
               interval_problem = if (is.na(ip)) "" else ip, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out$interval_start[out$interval_start %in% "NA"] <- NA
  out$interval_end[out$interval_end %in% "NA"] <- NA
  out
}

## ---- canopy over mapped trees -----------------------------------------------------------

OFO_PRESENCE <- list(
  radius_m = 2,                 # canopy maximum within 2 m of the registered stem
  min_stems = 10L,              # fewer test stems: not checked, held
  max_missing_share = 0.10,     # a plot passes with no more than 10% missing
  height_floor_m = 10,          # group A: height >= max(10 m, the plot's median)
  height_share = 0.5,           # group A: present when the maximum >= half the height
  min_dbh_cm = 30,              # group B: diameter >= 30 cm
  min_canopy_m = 5,             # group B: present when the maximum >= 5 m
  eps = 1e-9)

# Test stems of one plot. Group A: reference stems (trees.csv `ref`: live
# trees of at least 10 cm inside the polygon) with a measured height of at
# least the larger of 10 m and the plot's median, read as the first
# protocol's "median measured live height" (all live stems with a measured
# height; ofo_height_stems()). Group B: reference stems of at least 30 cm.
ofo_presence_test_stems <- function(group, live, ref, height, dbh) {
  ref <- ref %in% TRUE
  if (identical(group, "A")) {
    m <- live %in% TRUE & is.finite(height)
    if (!any(m)) return(rep(FALSE, length(ref)))
    return(ref & m & height >= max(OFO_PRESENCE$height_floor_m, stats::median(height[m])))
  }
  if (identical(group, "B"))
    return(ref & is.finite(dbh) & dbh >= OFO_PRESENCE$min_dbh_cm - OFO_PRESENCE$eps)
  stop("Presence test stems are defined for groups A and B only: ", group)
}

# Maximum of the surface S (ofo2_surface(): m, xmin, ymax, res) over the
# cells whose centre lies within `radius` of each position. Cells outside the
# raster count as 0, as in the method's objective; a position with no cell of
# the raster in reach gets 0.
ofo_presence_canopy_max <- function(S, x, y, radius = OFO_PRESENCE$radius_m) {
  nr <- nrow(S$m); nc <- ncol(S$m); res <- S$res
  vapply(seq_along(x), function(i) {
    if (!is.finite(x[i]) || !is.finite(y[i])) return(NA_real_)
    j <- seq(floor((x[i] - radius - S$xmin) / res) - 1, ceiling((x[i] + radius - S$xmin) / res))
    k <- seq(floor((S$ymax - y[i] - radius) / res) - 1, ceiling((S$ymax - y[i] + radius) / res))
    j <- j[j >= 0 & j < nc]; k <- k[k >= 0 & k < nr]
    if (!length(j) || !length(k)) return(0)
    d2 <- outer((S$ymax - (k + 0.5) * res - y[i])^2, (S$xmin + (j + 0.5) * res - x[i])^2, "+")
    use <- which(d2 <= radius^2 + 1e-9, arr.ind = TRUE)
    if (!nrow(use)) return(0)
    max(0, S$m[cbind(k[use[, 1]] + 1, j[use[, 2]] + 1)])
  }, numeric(1))
}

# A test stem is present when the canopy maximum within 2 m reaches half its
# measured height (group A) or 5 m (group B).
ofo_presence_present <- function(group, canopy_max, height = NULL) {
  e <- OFO_PRESENCE$eps
  out <- if (identical(group, "A")) canopy_max >= OFO_PRESENCE$height_share * height - e
         else if (identical(group, "B")) canopy_max >= OFO_PRESENCE$min_canopy_m - e
         else stop("Presence is defined for groups A and B only: ", group)
  out %in% TRUE
}

# pass: at least 10 test stems and no more than 10% of them missing (compared
# in counts, so exactly 10% passes); fail: more missing; not_checked: fewer
# than 10 test stems (held).
ofo_presence_status <- function(n_test, n_missing) {
  share <- round(OFO_PRESENCE$max_missing_share * 100)
  ifelse(n_test < OFO_PRESENCE$min_stems, "not_checked",
         ifelse(n_missing * 100 <= share * n_test, "pass", "fail"))
}

## ---- disturbance table -------------------------------------------------------------------

OFO_PRESENCE_STATUS <- c("pass", "fail", "not_checked", "not_run")

OFO_DIST_COLS <- c(OFO_DIST_RECORD_COLS, "presence_test_stems", "presence_missing",
                   "presence_missing_share", "presence_status", "disturbance_admitted",
                   "disturbance_reason")

# Cleared only when all three checks pass. A record in the interval or a
# failed canopy check is evidence ("disturbed"); otherwise a check that could
# not be made leaves the plot "not_checked" (the decision's hold rule).
ofo_dist_status <- function(fire_clear, activities_clear, presence_status) {
  fc <- ofo_lgl(fire_clear); ac <- ofo_lgl(activities_clear)
  ev <- fc %in% FALSE | ac %in% FALSE | presence_status %in% "fail"
  ok <- fc %in% TRUE & ac %in% TRUE & presence_status %in% "pass"
  ifelse(ev, "disturbed", ifelse(ok, "undisturbed", "not_checked"))
}

# Semicolon-joined failed checks: fire, activity and presence_fail are
# evidence; fire_unchecked, activity_unchecked, presence_not_checked and
# presence_not_run are checks that could not be made. Empty when cleared.
ofo_dist_reason <- function(fire_clear, activities_clear, presence_status) {
  fc <- ofo_lgl(fire_clear); ac <- ofo_lgl(activities_clear)
  vapply(seq_along(fc), function(i) paste(c(
    if (fc[i] %in% FALSE) "fire" else if (is.na(fc[i])) "fire_unchecked",
    if (ac[i] %in% FALSE) "activity" else if (is.na(ac[i])) "activity_unchecked",
    switch(as.character(presence_status[i]), pass = NULL, fail = "presence_fail",
           not_checked = "presence_not_checked", not_run = "presence_not_run",
           "presence_unknown")), collapse = ";"), character(1))
}

# disturbance.csv: the per-plot record checks joined with the canopy check.
# `rec` from ofo_dist_record_table(); `pres` holds plot_id,
# presence_test_stems, presence_missing, presence_status and extras.
ofo_dist_table <- function(rec, pres) {
  p <- pres[match(rec$plot_id, pres$plot_id), , drop = FALSE]
  if (anyNA(p$plot_id)) stop("No presence row for plot(s): ",
                             paste(rec$plot_id[is.na(p$plot_id)], collapse = ", "))
  bad <- setdiff(p$presence_status, OFO_PRESENCE_STATUS)
  if (length(bad)) stop("Unknown presence status: ", paste(bad, collapse = ", "))
  out <- rec[, OFO_DIST_RECORD_COLS]
  out$presence_test_stems <- as.integer(p$presence_test_stems)
  out$presence_missing <- as.integer(p$presence_missing)
  out$presence_missing_share <- ifelse(out$presence_test_stems > 0,
                                       out$presence_missing / out$presence_test_stems, NA_real_)
  out$presence_status <- p$presence_status
  out$disturbance_admitted <- ofo_dist_status(out$fire_clear, out$activities_clear,
                                              out$presence_status) == "undisturbed"
  out$disturbance_reason <- ofo_dist_reason(out$fire_clear, out$activities_clear,
                                            out$presence_status)
  extra_rec <- setdiff(names(rec), OFO_DIST_RECORD_COLS)
  extra_pres <- setdiff(names(pres), c("plot_id", "presence_test_stems", "presence_missing",
                                       "presence_status", names(out), extra_rec))
  cbind(out, rec[, extra_rec, drop = FALSE], p[, extra_pres, drop = FALSE])
}

## ---- registration gates of the second protocol ------------------------------------------

OFO_P2_GATES <- list(second_peak_max = 0.8, agreement_max_m = 2.0, eps = 1e-9)

# One clear peak: second_peak at most 0.8; a missing statistic fails.
ofo_p2_second_peak_ok <- function(second_peak) {
  v <- suppressWarnings(as.numeric(second_peak))
  is.finite(v) & v <= OFO_P2_GATES$second_peak_max + OFO_P2_GATES$eps
}

# Signals agree: within 2.0 m where the check applies (a missing distance
# where it applies fails).
ofo_p2_agreement_ok <- function(distance_m, applies) {
  d <- suppressWarnings(as.numeric(distance_m))
  !(applies %in% TRUE) | (is.finite(d) & d <= OFO_P2_GATES$agreement_max_m + OFO_P2_GATES$eps)
}

OFO_P2_REG_COLS <- c("plot_id", "project_name", "group", "signal_used", "signal_admitted", "dx",
                     "dy", "shift_m", "residual_m", "contrast", "n_signal", "registered",
                     "reason", "pos_unc", "flight_admitted", "set", "method")

# registration.csv of the second protocol for the candidate plots (screened in,
# a group in `groups`, not NEON2023) in the first protocol's contract, with
# the gates: the group's signal admitted (`admitted`, c(height, rank)), its
# method-2 estimate accepted by the frozen gate at no fewer than the smallest
# stem count (registration_catalog.csv rows of method "amendment1", `cat`),
# second_peak at most 0.8 and, in group A where the diameter estimate is also
# accepted by its frozen gate, the two estimates within 2.0 m. The flight
# gate is the first protocol's (registered needs an admitted flight).
# `inconclusive`: per signal, TRUE when its crown-frame test could not be made
# (fewer than 10 units). A plot failing only because such a signal is not
# admitted gets registration_check "unchecked" (hold-eligible); any other
# failure is "evidence".
ofo_p2_registration <- function(plots, flights, cat, admitted, groups = OFO_DIST_GROUPS,
                                inconclusive = c(height = FALSE, rank = FALSE)) {
  p <- plots[plots$screen %in% "none" & plots$group %in% groups &
               plots$project_name != OFO_NEON_PROJECT, , drop = FALSE]
  p <- p[order(p$plot_id), , drop = FALSE]
  m2 <- cat[cat$method %in% "amendment1", , drop = FALSE]
  key <- paste(m2$plot_id, m2$signal)
  if (anyDuplicated(key)) stop("registration_catalog.csv: more than one method-2 row for ",
                               paste(unique(key[duplicated(key)]), collapse = ", "))
  num <- function(v) suppressWarnings(as.numeric(v))
  rows <- lapply(seq_len(nrow(p)), function(i) {
    pid <- p$plot_id[i]; g <- p$group[i]; used <- OFO_GROUP_SIGNAL[[g]]
    f <- flights[match(pid, flights$plot_id), , drop = FALSE]
    cand <- ofo_lgl(f$flight_admitted) %in% TRUE
    cloud <- f$cloud_status %in% "ok"
    r <- m2[m2$plot_id == pid & m2$signal == used, , drop = FALSE]
    rk <- m2[m2$plot_id == pid & m2$signal == "rank", , drop = FALSE]
    has <- nrow(r) == 1L
    sig_ok <- isTRUE(admitted[[used]])
    acc <- has && ofo_lgl(r$accepted) %in% TRUE
    ms <- OFO_REG2[[used]]$gate$min_stems
    at_min <- has && isTRUE(num(r$n_signal) >= ms)
    sp <- if (has) num(r$second_peak) else NA_real_
    sp_ok <- has && ofo_p2_second_peak_ok(sp)
    rk_acc <- g == "A" && nrow(rk) == 1L && ofo_lgl(rk$accepted) %in% TRUE
    dist <- if (has && nrow(rk) == 1L) sqrt((num(r$dx) - num(rk$dx))^2 +
                                              (num(r$dy) - num(rk$dy))^2) else NA_real_
    ag_ok <- ofo_p2_agreement_ok(dist, rk_acc)
    rej <- if (has && !acc && !ofo_blank(r$reject_reason))
      strsplit(as.character(r$reject_reason), ";", fixed = TRUE)[[1]] else character()
    why <- c(if (!cand) "flight_not_admitted", if (!cloud) "no_cloud",
             if (!sig_ok) "signal_not_admitted", if (!has && cloud) "not_run",
             if (has && !acc) rej, if (has && acc && !at_min) "n",
             if (has && !sp_ok) "second_peak", if (has && !ag_ok) "signals_disagree")
    res <- if (has) num(r$residual_m) else NA_real_
    g1 <- function(col) if (has) num(r[[col]]) else NA_real_
    data.frame(plot_id = pid, project_name = p$project_name[i], group = g,
               signal_used = used, signal_admitted = sig_ok, dx = g1("dx"), dy = g1("dy"),
               shift_m = g1("shift_m"), residual_m = res, contrast = g1("contrast"),
               n_signal = if (has) as.integer(r$n_signal) else NA_integer_,
               registered = cand && sig_ok && has && acc && at_min && sp_ok && ag_ok,
               reason = paste(why, collapse = ";"),
               pos_unc = if (is.finite(res)) max(0.5, res) else NA_real_,
               flight_admitted = cand, set = if (has) as.character(r$set) else "",
               method = "protocol2",
               accepted = acc,
               frozen_reject_reason = if (has) as.character(r$reject_reason) else NA,
               min_stems = ms, at_min_stems = at_min, sub_p90_m = g1("sub_p90_m"),
               on_edge = if (has) ofo_lgl(r$on_edge) else NA, second_peak = sp,
               second_peak_ok = sp_ok, rank_accepted = if (g == "A") rk_acc else NA,
               rank_dx = if (g == "A" && nrow(rk) == 1L) num(rk$dx) else NA_real_,
               rank_dy = if (g == "A" && nrow(rk) == 1L) num(rk$dy) else NA_real_,
               agreement_m = if (g == "A") dist else NA_real_,
               agreement_applies = g == "A" && rk_acc, agreement_ok = ag_ok,
               cloud_status = if (nrow(f)) as.character(f$cloud_status) else NA_character_,
               registration_check = if (cand && sig_ok && has && acc && at_min && sp_ok && ag_ok)
                 "registered" else if (cand && !sig_ok && isTRUE(inconclusive[[used]]) && has &&
                                       acc && at_min && sp_ok && ag_ok) "unchecked"
                 else "evidence",
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out$frozen_reject_reason[is.na(out$frozen_reject_reason)] <- ""
  rownames(out) <- NULL
  out
}

## ---- conditions of the second protocol --------------------------------------------------

# The first protocol's conditions columns (its contract, in order); the drone
# comparison's own columns are empty here, since this protocol replaces that
# check for groups A and B.
OFO_P2_COND_COLS <- c("plot_id", "project_name", "mission_id", "mission_date", "mission_pitch",
                      "chm_url", "n_canopy_cells_early", "loss_share", "reverse_share",
                      "interval_covered", "disturbance_status", "same_year",
                      "disturbance_admitted", "snow_window", "snow_dates_checked",
                      "snow_depth_max_m", "snow_status", "deciduous_share", "leafoff_window",
                      "leafoff_status", "conditions_admitted", "conditions_reason")
OFO_P2_DRONE_COLS <- c("mission_id", "mission_date", "mission_pitch", "chm_url",
                       "n_canopy_cells_early", "loss_share", "reverse_share")
OFO_P2_COPY_COLS <- c("plot_id", "project_name", "same_year", "snow_window",
                      "snow_dates_checked", "snow_depth_max_m", "snow_status",
                      "deciduous_share", "leafoff_window", "leafoff_status")

# conditions.csv of the second protocol: one row per plot of `dist`
# (disturbance.csv) that has a first-protocol conditions row (`cond1`, the
# plots with a cloud). Snow and leaf-off are copied; disturbance comes from
# the three checks: disturbance_status "disturbed" on evidence, "undisturbed"
# when cleared, "not_checked" when a check could not be made, which
# ofo_conditions_check() reads as unchecked (the hold rule).
# interval_covered: the records cover the interval by construction, so it is
# TRUE where the interval exists (known and not reversed). The first
# protocol's disturbance fields are kept as p1_ columns.
ofo_p2_conditions <- function(cond1, dist) {
  miss <- setdiff(OFO_P2_COPY_COLS, names(cond1))
  if (length(miss)) stop("conditions.csv lacks column(s): ", paste(miss, collapse = ", "))
  d <- dist[dist$plot_id %in% cond1$plot_id, , drop = FALSE]
  d <- d[order(d$plot_id), , drop = FALSE]
  c1 <- cond1[match(d$plot_id, cond1$plot_id), , drop = FALSE]
  out <- c1[, OFO_P2_COPY_COLS, drop = FALSE]
  for (k in OFO_P2_DRONE_COLS) out[[k]] <- NA
  s <- as.Date(as.character(d$interval_start)); e <- as.Date(as.character(d$interval_end))
  out$interval_covered <- !is.na(s) & !is.na(e) & e >= s
  out$disturbance_status <- ofo_dist_status(d$fire_clear, d$activities_clear, d$presence_status)
  out$disturbance_admitted <- out$disturbance_status == "undisturbed"
  out$conditions_admitted <- ofo_conditions_admitted(out$disturbance_admitted, out$snow_status,
                                                     out$leafoff_status)
  out$conditions_reason <- vapply(seq_len(nrow(out)), function(i) {
    r <- d$disturbance_reason[i]
    r <- if (is.na(r) || !nzchar(r)) character() else strsplit(r, ";", fixed = TRUE)[[1]]
    s <- out$snow_status[i]; l <- out$leafoff_status[i]
    paste(c(r, if (s %in% "snow") "snow", if (s %in% "unknown") "snow_unknown",
            if (l %in% "leaf_off_held") "leaf_off"), collapse = ";")
  }, character(1))
  out <- out[, OFO_P2_COND_COLS]
  out$group <- d$group
  out$interval_start <- d$interval_start
  out$interval_end <- d$interval_end
  out$fire_clear <- d$fire_clear
  out$activities_clear <- d$activities_clear
  out$nfs_records_source <- d$nfs_records_source
  out$presence_status <- d$presence_status
  out$disturbance_reason <- d$disturbance_reason
  p1 <- intersect(c("disturbance_status", "disturbance_admitted", "conditions_admitted",
                    "conditions_reason"), names(c1))
  for (k in p1) out[[paste0("p1_", k)]] <- c1[[k]]
  rownames(out) <- NULL
  out
}

## ---- stage records ------------------------------------------------------------------------

# A stage record of the second protocol: digests of the files read in `p2`
# (`inputs`) and in the first protocol's directory (`inputs_preflight`, under
# `preflight_dir`), and of the files written in `p2` (`outputs`).
ofo_p2_record <- function(stage, p2, inputs, outputs, pre = NULL, inputs_pre = NULL,
                          extra = list()) {
  more <- if (is.null(pre)) list() else
    list(preflight_dir = pre, inputs_preflight = as.list(inputs_pre))
  ofo_stage_record(stage, p2, inputs, outputs, c(more, extra))
}

# Messages for every file of such a record that differs from the one it read
# or wrote, or that is missing (empty when current).
ofo_p2_record_mismatch <- function(record, p2, pre) {
  msg <- ofo_record_mismatch(record, p2)
  if (length(record$inputs_preflight)) {
    if (is.null(record$preflight_dir) ||
        !identical(ofo_path_resolve(record$preflight_dir), ofo_path_resolve(pre)))
      msg <- c(msg, sprintf("its first-protocol inputs were read in %s, not %s",
                            record$preflight_dir, pre))
    msg <- c(msg, ofo_record_mismatch(list(inputs = record$inputs_preflight), pre))
  }
  msg
}
