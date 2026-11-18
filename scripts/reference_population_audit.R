#!/usr/bin/env Rscript
.bs_ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (!is.null(.bs_ofile) && length(.bs_ofile) && nzchar(.bs_ofile))
    file.path(dirname(.bs_ofile), "bootstrap.R"),
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])),
                                  "bootstrap.R"),
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_ofile, .bs_file)

# Audit of the field reference behind the frozen-root benchmark (post hoc,
# read-only). For the declared population (default `adopted`) of each site it
# describes what a reference record is and when it was measured, and overlays
# the plots on public wildfire perimeters. Outputs under OUT:
#   reference_records.csv  one row per scored reference record: the NEON bole
#     identity (a trailing capital letter on a standard NEON individualID marks
#     an additional bole; the ID without it is the individual), growth form,
#     height, crown class and its source (NEON canopyPosition, the within-plot
#     height-quantile fallback of neon_ground_truth.R, or none) and the date of
#     the scored measurement (the record neon_nearest_measurements() picks,
#     re-derived from the cached NEON tables and checked field by field).
#   reference_summary.csv  per site and in total; reference_years.csv, records
#     by measurement year and gap to the 2021 flight.
#   plot_measurement_years.csv  one row per plot: type, reference stems, their
#     measurement years and dates, the last field record of the plot in the
#     cached NEON tables, the centroid in WGS84, the perimeters containing it
#     or within NEAR_M of it, and membership of the native sparse-flight
#     comparison (adopted in both epochs, as compare_sparse_epoch.R defines it).
#   fire_hits.csv  one row per plot x fire (fire years FIRE_YEARS) whose
#     perimeter contains the plot centroid in any source: name, dates, size,
#     the sources that contain it, and the timing of the fire against the
#     plot's reference dates, the site's 2021 flight and, in California, the
#     earlier sparse flight. fire_near_plots.csv: the same for perimeters
#     whose edge lies within NEAR_M of a centroid no source places inside.
#     fire_source_hits.csv: every plot x perimeter relation per source.
#   fire_source_offsets.csv  for each fire held by several sources, the area
#     of each copy and their mismatch before and after translating one copy
#     onto the other's centroid (a displaced copy shows as a large mismatch
#     that a translation removes).
#   fire_field_remarks.csv  for each fire with a hit or near plot, every plot
#     of the site (any population) with NEON records after the fire's start:
#     records whose remarks or status mention fire, burning or scorch, and
#     the plot's position against each source's copy of the perimeter.
#   fire_status_transitions.csv (+ fire_status_individuals.csv)  for each fire
#     with a hit, every population plot of the site with records on both
#     sides of the fire's start: of the individuals (NEON individualIDs) live
#     at their last record before it, how many were not live at their first
#     record after it, with the year of the last pre-fire record.
#   fire_sources.csv, fire_queries.csv, reference_audit_log.txt.
#
# Perimeter sources: public ArcGIS feature services, queried with the WGS84
# bounding box of each site's population plot centroids plus 0.01 degree, and
# with each centroid as a point (the services' own containment test, which
# must agree with the local overlay); nothing else is sent. The National
# Interagency Fire Center's Interagency Fire Perimeter History (decade layers
# for 2010-2019 and 2020-2029; the all-years view of that history omits most
# fires from 2020 on), NIFC's WFIGS Interagency Perimeters (fires discovered
# from 2016 on, with discovery and containment dates; the only NIFC source
# holding 2025), and for the California sites CAL FIRE FRAP's California Fire
# Perimeters (all). Responses are Esri JSON (ring orientation keeps unburned
# islands as holes) cached under OUT/fire_cache with a manifest (URL, access
# time, SHA-256); a re-run reads the cache and needs no network. With neither
# cache nor network the script stops; OFFLINE=1 forbids the network.
#
# Flight days of 2021 come from docs/census-support-evidence.json. The sparse
# flights are known by month (SJER 2017-03; SOAP and TEAK 2018-06; see the
# native sparse epoch study) and are compared as month-long windows.
#
#   CLAUDE_JOB_DIR=<paper job dir> Rscript scripts/reference_population_audit.R \
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [POP=adopted] [FROZEN_ROOT=...] \
#     [OUT=$CLAUDE_JOB_DIR/reference_audit] [CACHE=$OUT/fire_cache] \
#     [FIRE_YEARS=2015,2025] [NEAR_M=250] [OFFLINE=0] \
#     [SPARSE=SJER:<root>,SOAP:<root>,TEAK:<root>|none]
# SPARSE defaults to the sealed sparse-epoch roots beside the job directory
# (<job>/../sparse_2017/neon/frozen_2017 for SJER, <job>/../sparse_2018/neon/
# frozen_2018 for SOAP and TEAK). Reads the frozen root, ground truth, plot
# centroids and cached NEON woody-vegetation tables; writes only under OUT.

## ---- pure helpers (unit-tested) ----------------------------------------------

# neon_ground_truth.R maps NEON canopyPosition to crown class with this table
# and classes the remaining stems that have a height by within-plot height
# quantiles (plots with at least four such stems).
RA_CC_MAP <- c("Open grown" = "dominant", "Full sun" = "dominant",
               "Partially shaded" = "codominant", "Mostly shaded" = "intermediate",
               "Full shade" = "suppressed")
RA_NEON_ID <- "^(NEON[.]PLA[.]D[0-9]{2}[.][A-Z]{4}[.][0-9]+)([A-Z]?)$"
RA_FIRE_REMARK <- "\\bfire\\b|\\bburn|scorch|\\bcharred\\b"

# NEON tags each additional bole of a multi-bole individual with the
# individual's ID plus a trailing capital letter (vegetation structure user
# guide, sections 6.2-6.3). Non-standard IDs are their own individual.
ra_bole_parse <- function(id) {
  id <- as.character(id)
  ok <- !is.na(id) & grepl(RA_NEON_ID, id)
  base <- id; suffix <- rep("", length(id))
  base[ok] <- sub(RA_NEON_ID, "\\1", id[ok])
  suffix[ok] <- sub(RA_NEON_ID, "\\2", id[ok])
  data.frame(individualID = id, base_id = base, bole_suffix = suffix,
             additional_bole = nzchar(suffix), standard_id = ok,
             stringsAsFactors = FALSE)
}

# Per record: reference records of its individual, and whether that
# individual is multi-bole in the reference (holds an additional-bole record).
ra_bole_families <- function(site, id) {
  b <- ra_bole_parse(id)
  key <- paste(site, b$base_id)
  n <- as.vector(table(key)[key])
  multi <- key %in% key[b$additional_bole]
  cbind(b, records_of_individual = n, multi_bole_individual = multi)
}

# Crown-class provenance from canopyPosition and the assigned class.
ra_crown_source <- function(canopy_position, crown_class) {
  cc <- ifelse(is.na(crown_class) | !nzchar(crown_class), NA_character_, crown_class)
  mapped <- !is.na(canopy_position) & canopy_position %in% names(RA_CC_MAP)
  if (any(mapped & (is.na(cc) | cc != RA_CC_MAP[canopy_position])))
    stop("Crown class disagrees with the canopyPosition mapping")
  ifelse(mapped, "canopy_position", ifelse(!is.na(cc), "height_fallback", "none"))
}

# The window a fire occupies: alarm (discovery) to containment. Without a
# containment date the window runs to the end of the alarm year; without an
# alarm date it is the whole fire year.
ra_fire_window <- function(alarm, containment, year) {
  alarm <- as.Date(alarm); containment <- as.Date(containment)
  y <- ifelse(is.na(alarm), as.integer(year), as.integer(format(alarm, "%Y")))
  if (anyNA(y)) stop("A fire needs an alarm date or a fire year")
  start <- ifelse(is.na(alarm), as.Date(sprintf("%d-01-01", y)), alarm)
  end <- ifelse(is.na(containment), as.Date(sprintf("%d-12-31", y)), containment)
  if (any(end < start)) stop("Fire containment precedes its alarm")
  data.frame(fire_start = as.Date(start, origin = "1970-01-01"),
             fire_end = as.Date(end, origin = "1970-01-01"),
             window_basis = ifelse(is.na(alarm), "fire year only",
                                   ifelse(is.na(containment), "alarm to year end",
                                          "alarm to containment")),
             stringsAsFactors = FALSE)
}

# Where a fire window [start, end] lies relative to another window [w0, w1]:
# "before" it ends before w0, "after" it starts after w1, else "overlaps".
ra_relation <- function(start, end, w0, w1)
  ifelse(end < w0, "before", ifelse(start > w1, "after", "overlaps"))

# Timing of one fire at one plot. ref_dates: the plot's reference measurement
# dates (one per record). flight: the 2021 flight window; sparse: the earlier
# sparse flight window (NA outside California).
ra_classify_fire <- function(fire_start, fire_end, ref_dates, flight_start, flight_end,
                             sparse_start = NA, sparse_end = NA) {
  ref_dates <- as.Date(ref_dates)
  if (!length(ref_dates) || anyNA(ref_dates)) stop("Reference dates are required")
  fire_start <- as.Date(fire_start); fire_end <- as.Date(fire_end)
  if (is.na(fire_start) || is.na(fire_end) || fire_end < fire_start) stop("Invalid fire window")
  n_before <- sum(ref_dates < fire_start); n_after <- sum(ref_dates > fire_end)
  n_during <- length(ref_dates) - n_before - n_after
  vs_ref <- if (n_before == length(ref_dates)) "references_predate_fire" else
    if (n_after == length(ref_dates)) "references_postdate_fire" else "references_span_fire"
  vs_flight <- ra_relation(fire_start, fire_end, as.Date(flight_start), as.Date(flight_end))
  vs_sparse <- if (is.na(sparse_start)) NA_character_ else
    ra_relation(fire_start, fire_end, as.Date(sparse_start), as.Date(sparse_end))
  between <- if (is.na(vs_sparse)) NA else vs_sparse == "after" && vs_flight == "before"
  reading <- if (vs_flight == "overlaps") "fire_during_flight" else
    if (vs_flight == "before") {
      switch(vs_ref,
             references_predate_fire = "references_predate_fire_before_flight",
             references_postdate_fire = "remeasured_after_fire_before_flight",
             references_span_fire = "references_span_fire_before_flight")
    } else {
      switch(vs_ref,
             references_predate_fire = "fire_after_flight_and_references",
             references_postdate_fire = "fire_after_flight_references_after_fire",
             references_span_fire = "fire_after_flight_references_span_fire")
    }
  data.frame(ref_before_fire = n_before, ref_during_fire = n_during,
             ref_after_fire = n_after, fire_vs_reference = vs_ref,
             fire_vs_flight_2021 = vs_flight, fire_vs_sparse_flight = vs_sparse,
             between_sparse_and_2021 = between, reading = reading,
             stringsAsFactors = FALSE)
}

# Per individual of `plots`: the last record before `cutoff` (a Date) and the
# first on or after it. Individuals need records on both sides. Ties within a
# date resolve to the last row of that date (data order).
ra_status_transitions <- function(ai, plots, cutoff) {
  cutoff <- as.Date(cutoff)
  a <- ai[ai$plotID %in% plots, , drop = FALSE]
  a$d <- as.Date(substr(a$date, 1, 10))
  a <- a[!is.na(a$d), , drop = FALSE]
  a$row <- seq_len(nrow(a))
  pre <- a[a$d < cutoff, , drop = FALSE]
  pre <- pre[order(pre$plotID, pre$individualID, pre$d, pre$row), , drop = FALSE]
  pre <- pre[!duplicated(pre[c("plotID", "individualID")], fromLast = TRUE), , drop = FALSE]
  post <- a[a$d >= cutoff, , drop = FALSE]
  post <- post[order(post$plotID, post$individualID, post$d, -post$row), , drop = FALSE]
  post <- post[!duplicated(post[c("plotID", "individualID")]), , drop = FALSE]
  m <- merge(pre[c("plotID", "individualID", "d", "plantStatus", "stemDiameter")],
             post[c("plotID", "individualID", "d", "plantStatus")],
             by = c("plotID", "individualID"), suffixes = c("_pre", "_post"))
  names(m) <- c("plotID", "individualID", "pre_date", "pre_status", "pre_dbh",
                "post_date", "post_status")
  m$pre_live <- grepl("^Live", m$pre_status)
  m$post_live <- grepl("^Live", m$post_status)
  m[order(m$plotID, m$individualID), , drop = FALSE]
}

# NEON records whose remarks or status mention fire, burning or scorch.
ra_fire_remark <- function(remarks, status)
  grepl(RA_FIRE_REMARK, ifelse(is.na(remarks), "", remarks), ignore.case = TRUE) |
  grepl(RA_FIRE_REMARK, ifelse(is.na(status), "", status), ignore.case = TRUE)

# Normalised IRWIN incident identifier (upper case, no braces).
ra_irwin <- function(x) {
  x <- toupper(gsub("[{}[:space:]]", "", as.character(x)))
  ifelse(is.na(x) | !nzchar(x), NA_character_, x)
}

# Event keys across sources: the IRWIN ID where present, otherwise name and
# year, joined to an IRWIN-keyed event of the same name and year when exactly
# one exists.
ra_fire_keys <- function(name, year, irwin) {
  nm <- toupper(trimws(name)); irwin <- ra_irwin(irwin)
  ny <- paste(nm, year, sep = "|")
  key <- ifelse(is.na(irwin), paste0("NAME:", ny), paste0("IRWIN:", irwin))
  for (k in unique(ny[is.na(irwin)])) {
    cand <- unique(key[!is.na(irwin) & ny == k])
    if (length(cand) == 1L) key[is.na(irwin) & ny == k] <- cand
  }
  key
}

# ArcGIS date fields arrive as epoch milliseconds or, read through GDAL, as
# date-times. CAL FIRE's date-only fields sit at midnight UTC and keep their
# UTC date; WFIGS instants take the local calendar date of the Pacific sites.
ra_instant <- function(v) {
  if (inherits(v, "POSIXt")) return(as.POSIXct(v, tz = "UTC"))
  if (inherits(v, "Date")) return(as.POSIXct(format(v), tz = "UTC"))
  as.POSIXct(as.numeric(v) / 1000, origin = "1970-01-01", tz = "UTC")
}
ra_ms_date_utc <- function(v) as.Date(format(ra_instant(v), tz = "UTC", "%Y-%m-%d"))
ra_ms_date_local <- function(v, tz = "America/Los_Angeles")
  as.Date(format(ra_instant(v), tz = tz, "%Y-%m-%d"))

# ArcGIS REST query URL with percent-encoded parameters.
ra_query_url <- function(layer, params)
  paste0(layer, "/query?", paste(names(params),
                                  vapply(as.character(params), curl::curl_escape, ""),
                                  sep = "=", collapse = "&"))

## ---- perimeter sources ---------------------------------------------------------
RA_NIFC <- "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services"
RA_NIFC_HISTORY_FIELDS <- c("OBJECTID", "INCIDENT", "FIRE_YEAR_INT", "GIS_ACRES", "IRWINID",
                            "UNQE_FIRE_ID", "FEATURE_CA", "MAP_METHOD", "DATE_CUR", "SOURCE",
                            "AGENCY", "UNIT_ID")
RA_SOURCES <- list(
  nifc_history_2010s = list(
    label = "NIFC Interagency Fire Perimeter History, 2010s layer",
    layer = paste0(RA_NIFC, "/InteragencyFirePerimeterHistory_2010s_Read_Only/FeatureServer/0"),
    where = "FIRE_YEAR_INT >= %d AND FIRE_YEAR_INT <= %d",
    fields = RA_NIFC_HISTORY_FIELDS, states = c("CA", "WA")),
  nifc_history_2020s = list(
    label = "NIFC Interagency Fire Perimeter History, 2020s layer",
    layer = paste0(RA_NIFC, "/InterAgencyFirePerimeterHistory_2020s_Read_Only/FeatureServer/0"),
    where = "FIRE_YEAR_INT >= %d AND FIRE_YEAR_INT <= %d",
    fields = RA_NIFC_HISTORY_FIELDS, states = c("CA", "WA")),
  nifc_wfigs = list(
    label = "NIFC WFIGS Interagency Perimeters",
    layer = paste0(RA_NIFC, "/WFIGS_Interagency_Perimeters/FeatureServer/0"),
    where = paste("(attr_FireDiscoveryDateTime >= DATE '%d-01-01' AND",
                  "attr_FireDiscoveryDateTime < DATE '%d-01-01') OR attr_FireDiscoveryDateTime IS NULL"),
    fields = c("OBJECTID", "poly_IncidentName", "attr_IncidentName", "poly_FeatureCategory",
               "poly_GISAcres", "poly_IRWINID", "attr_IrwinID", "attr_FireDiscoveryDateTime",
               "attr_ContainmentDateTime", "attr_FireOutDateTime", "attr_UniqueFireIdentifier",
               "attr_IncidentTypeCategory", "poly_MapMethod", "poly_DateCurrent"),
    states = c("CA", "WA")),
  calfire_frap = list(
    label = "CAL FIRE FRAP California Fire Perimeters (all)",
    layer = paste0("https://services1.arcgis.com/jUJYIo9tSA7EHvfZ/arcgis/rest/services/",
                   "California_Historic_Fire_Perimeters/FeatureServer/0"),
    where = "YEAR_ >= %d AND YEAR_ <= %d",
    fields = c("OBJECTID", "YEAR_", "FIRE_NAME", "INC_NUM", "IRWINID", "ALARM_DATE", "CONT_DATE",
               "GIS_ACRES", "AGENCY", "UNIT_ID", "OBJECTIVE", "CAUSE", "COMPLEX_NAME"),
    states = "CA"))
RA_SITE_STATE <- c(SJER = "CA", SOAP = "CA", TEAK = "CA", WREF = "WA", ABBY = "WA")
RA_SPARSE_MONTH <- c(SJER = "2017-03", SOAP = "2018-06", TEAK = "2018-06")
RA_PAGE <- 100L
RA_UA <- "generic-research-client"

ra_where <- function(src, years) {
  y <- as.integer(years)
  if (grepl("DATE '", src$where, fixed = TRUE)) sprintf(src$where, y[1], y[2] + 1L)
  else sprintf(src$where, y[1], y[2])
}

## ---- cached network access -------------------------------------------------------
ra_manifest_path <- function(cache) file.path(cache, "manifest.csv")
ra_manifest <- function(cache) {
  f <- ra_manifest_path(cache)
  if (!file.exists(f)) return(data.frame(file = character(), url = character(),
    accessed_utc = character(), bytes = character(), sha256 = character(),
    stringsAsFactors = FALSE))
  read.csv(f, stringsAsFactors = FALSE, colClasses = "character")
}

# Returns the path of the cached response to `url`, fetching it once. A cached
# file must match its manifest hash; with no cache, OFFLINE or a failed request
# stops the run.
ra_fetch <- function(url, cache, name, offline) {
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  man <- ra_manifest(cache)
  hit <- man[man$url == url, , drop = FALSE]
  if (nrow(hit)) {
    f <- file.path(cache, hit$file[nrow(hit)])
    if (!file.exists(f)) stop("Fire cache manifest lists a missing file: ", f, call. = FALSE)
    if (!identical(digest::digest(file = f, algo = "sha256"), hit$sha256[nrow(hit)]))
      stop("Fire cache file differs from its manifest hash: ", f, call. = FALSE)
    return(f)
  }
  if (offline) stop("No cached perimeter response for\n  ", url,
                    "\nand OFFLINE=1; restore the fire cache or allow network access", call. = FALSE)
  h <- curl::new_handle(useragent = RA_UA, timeout = 600, connecttimeout = 60)
  r <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e)
    stop("Fire-perimeter query failed and no cached response exists:\n  ", url, "\n  ",
         conditionMessage(e), call. = FALSE))
  if (r$status_code != 200L)
    stop(sprintf("Fire-perimeter query returned HTTP %d:\n  %s", r$status_code, url), call. = FALSE)
  j <- tryCatch(jsonlite::fromJSON(rawToChar(r$content), simplifyVector = FALSE),
                error = function(e) stop("Fire-perimeter response is not JSON: ", url, call. = FALSE))
  if (!is.null(j$error))
    stop("Fire-perimeter service error (", j$error$code, " ", j$error$message, "):\n  ", url,
         call. = FALSE)
  if (isTRUE(j$exceededTransferLimit))
    stop("Fire-perimeter response exceeded the service's transfer limit: ", url, call. = FALSE)
  fname <- sprintf("%s_%s.json", name, substr(digest::digest(url, algo = "sha256"), 1, 12))
  f <- file.path(cache, fname)
  writeBin(r$content, f)
  row <- data.frame(file = fname, url = url,
                    accessed_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                    bytes = as.character(length(r$content)),
                    sha256 = digest::digest(file = f, algo = "sha256"), stringsAsFactors = FALSE)
  write.csv(rbind(man, row), ra_manifest_path(cache), row.names = FALSE)
  Sys.sleep(0.2)
  f
}

# Every perimeter of one source intersecting a WGS84 bounding box, as sf in
# EPSG:4326, read from the cache or fetched page by page (Esri JSON).
ra_query_box <- function(src_id, site, box, years, cache, offline) {
  src <- RA_SOURCES[[src_id]]
  geom <- sprintf("%.4f,%.4f,%.4f,%.4f", box[1], box[2], box[3], box[4])
  base <- list(where = ra_where(src, years), geometry = geom,
               geometryType = "esriGeometryEnvelope", inSR = "4326",
               spatialRel = "esriSpatialRelIntersects")
  cf <- ra_fetch(ra_query_url(src$layer, c(base, returnCountOnly = "true", f = "json")),
                 cache, paste(src_id, site, "count", sep = "_"), offline)
  n <- jsonlite::fromJSON(cf)$count
  if (is.null(n)) stop("No feature count in ", cf)
  pages <- list(); got <- 0L
  for (k in seq_len(ceiling(n / RA_PAGE))) {
    pf <- ra_fetch(ra_query_url(src$layer, c(base, outFields = paste(src$fields, collapse = ","),
                                             returnGeometry = "true", outSR = "4326",
                                             orderByFields = "OBJECTID ASC",
                                             resultOffset = (k - 1L) * RA_PAGE,
                                             resultRecordCount = RA_PAGE, f = "json")),
                   cache, sprintf("%s_%s_p%02d", src_id, site, k), offline)
    j <- jsonlite::fromJSON(pf, simplifyVector = FALSE)
    if (!length(j$features)) next
    got <- got + length(j$features)
    x <- sf::st_read(pf, quiet = TRUE)
    if (nrow(x) != length(j$features)) stop("Perimeter page read incompletely: ", pf)
    pages[[length(pages) + 1L]] <- x
  }
  if (got != n) stop(sprintf("%s %s: %d features fetched, %d counted", src_id, site, got, n))
  if (!length(pages)) return(NULL)
  x <- do.call(rbind, lapply(pages, function(p) p[, intersect(src$fields, names(p))]))
  if (is.na(sf::st_crs(x))) sf::st_crs(x) <- 4326 else x <- sf::st_transform(x, 4326)
  x[!sf::st_is_empty(x), ]
}

# OBJECTIDs of the perimeters (fire years `years`) that the service itself
# finds at one point.
ra_point_ids <- function(src_id, lon, lat, years, cache, name, offline) {
  src <- RA_SOURCES[[src_id]]
  f <- ra_fetch(ra_query_url(src$layer, list(where = ra_where(src, years),
                                             geometry = sprintf("%.6f,%.6f", lon, lat),
                                             geometryType = "esriGeometryPoint", inSR = "4326",
                                             spatialRel = "esriSpatialRelIntersects",
                                             outFields = "OBJECTID", returnGeometry = "false",
                                             f = "json")),
                cache, name, offline)
  j <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  sort(vapply(j$features, function(z) as.numeric(z$attributes$OBJECTID), 0))
}

ra_layer_info <- function(src_id, cache, offline) {
  f <- ra_fetch(paste0(RA_SOURCES[[src_id]]$layer, "?f=json"), cache,
                paste(src_id, "layer", sep = "_"), offline)
  j <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  last <- j$editingInfo$dataLastEditDate
  man <- ra_manifest(cache)
  data.frame(source = src_id, label = RA_SOURCES[[src_id]]$label,
             service_layer = RA_SOURCES[[src_id]]$layer, layer_name = j$name,
             data_last_edit_utc = if (is.null(last)) NA_character_ else
               format(as.POSIXct(last / 1000, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d"),
             accessed_utc = man$accessed_utc[match(basename(f), man$file)],
             stringsAsFactors = FALSE)
}

# One attribute table per source, normalised.
ra_normalise <- function(x, src_id) {
  a <- sf::st_drop_geometry(x)
  num <- function(v) suppressWarnings(as.numeric(v))
  out <- switch(src_id,
    calfire_frap = data.frame(fire_name = a$FIRE_NAME, fire_year = as.integer(a$YEAR_),
      irwin = a$IRWINID, acres = num(a$GIS_ACRES), category = paste0("objective ", a$OBJECTIVE),
      alarm = ra_ms_date_utc(a$ALARM_DATE), containment = ra_ms_date_utc(a$CONT_DATE),
      source_id = paste(a$UNIT_ID, a$INC_NUM), stringsAsFactors = FALSE),
    nifc_wfigs = {
      disc <- ra_ms_date_local(a$attr_FireDiscoveryDateTime)
      data.frame(fire_name = ifelse(is.na(a$poly_IncidentName), a$attr_IncidentName,
                                    a$poly_IncidentName),
        fire_year = as.integer(format(disc, "%Y")),
        irwin = ifelse(is.na(a$poly_IRWINID), a$attr_IrwinID, a$poly_IRWINID),
        acres = num(a$poly_GISAcres),
        category = ifelse(a$attr_IncidentTypeCategory %in% "RX",
                          paste(a$poly_FeatureCategory, "(incident type RX)"), a$poly_FeatureCategory),
        alarm = disc, containment = ra_ms_date_local(a$attr_ContainmentDateTime),
        source_id = a$attr_UniqueFireIdentifier, stringsAsFactors = FALSE)
    },
    data.frame(fire_name = a$INCIDENT, fire_year = as.integer(a$FIRE_YEAR_INT), irwin = a$IRWINID,
      acres = num(a$GIS_ACRES), category = a$FEATURE_CA, alarm = as.Date(NA),
      containment = as.Date(NA), source_id = a$UNQE_FIRE_ID, stringsAsFactors = FALSE))
  out$source <- src_id; out$objectid <- as.numeric(a$OBJECTID)
  out$irwin <- ra_irwin(out$irwin)
  sf::st_sf(out, geometry = sf::st_geometry(x))
}

ra_core_boxes <- function(x, crs)
  sf::st_sfc(lapply(seq_len(nrow(x)), function(i) {
    h <- x$core_half[i]; e <- x$easting[i]; n <- x$northing[i]
    sf::st_polygon(list(matrix(c(e - h, n - h, e + h, n - h, e + h, n + h, e - h, n + h,
                                 e - h, n - h), ncol = 2, byrow = TRUE)))
  }), crs = crs)

## ---- main ---------------------------------------------------------------------------
ra_main <- function() {
  suppressMessages({ library(sf) })
  sf::sf_use_s2(FALSE)                     # every overlay runs in the site's UTM frame
  source(.find("model_bench_lib.R"))     # frozen_scope, neon_nearest_measurements, ext_*
  args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
  A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
  split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
  d <- .job_dir()
  SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
  if (!all(SITES %in% names(RA_SITE_STATE))) stop("Unknown site in SITES")
  OUT <- if (is.null(A$OUT)) file.path(d, "reference_audit") else A$OUT
  YEARS <- as.integer(split_arg(A$FIRE_YEARS, "2015,2025"))
  NEAR_M <- as.numeric(if (is.null(A$NEAR_M)) 250 else A$NEAR_M)
  OFFLINE <- identical(A$OFFLINE, "1")
  if (length(YEARS) != 2L || anyNA(YEARS) || YEARS[1] > YEARS[2]) stop("FIRE_YEARS=<first>,<last>")
  if (!is.finite(NEAR_M) || NEAR_M < 0) stop("NEAR_M must be a non-negative distance in metres")
  CACHE <- if (is.null(A$CACHE)) file.path(OUT, "fire_cache") else A$CACHE
  dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
  log_lines <- character()
  say <- function(...) { x <- sprintf(...); cat(x, "\n"); log_lines <<- c(log_lines, x) }
  population <- if (is.null(A$POP)) "adopted" else A$POP
  same <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)

  ## Flight windows.
  ev <- jsonlite::read_json(file.path(.ROOT, "docs", "census-support-evidence.json"),
                            simplifyVector = FALSE)
  flights <- do.call(rbind, lapply(ev$flights, function(f) {
    days <- as.Date(unlist(f$flight_days))
    data.frame(site = f$site, flight_start = min(days), flight_end = max(days),
               stringsAsFactors = FALSE)
  }))
  if (!all(SITES %in% flights$site)) stop("A site has no 2021 flight days in the evidence file")
  sparse_win <- data.frame(site = names(RA_SPARSE_MONTH),
                           sparse_start = as.Date(paste0(RA_SPARSE_MONTH, "-01")),
                           stringsAsFactors = FALSE)
  sparse_win$sparse_end <- as.Date(vapply(sparse_win$sparse_start, function(s)
    format(seq(s, by = "month", length.out = 2)[2] - 1), ""))

  ## Sparse-flight comparison plots (adopted in both epochs).
  sp_default <- c(SJER = file.path(dirname(d), "sparse_2017", "neon", "frozen_2017"),
                  SOAP = file.path(dirname(d), "sparse_2018", "neon", "frozen_2018"),
                  TEAK = file.path(dirname(d), "sparse_2018", "neon", "frozen_2018"))
  sparse_roots <- if (identical(A$SPARSE, "none")) NULL else if (is.null(A$SPARSE)) sp_default else {
    kv <- strsplit(split_arg(A$SPARSE, ""), ":", fixed = TRUE)
    setNames(vapply(kv, function(x) paste(x[-1], collapse = ":"), ""), vapply(kv, `[`, "", 1))
  }

  ## ---- 1. reference records ----------------------------------------------------------
  recs <- list(); plots <- list(); vst <- list(); pcs <- list()
  root <- NULL
  for (site in SITES) {
    nd <- file.path(d, "neon", site)
    gt_f <- file.path(nd, "ground_truth_stems.csv"); pc_f <- file.path(nd, "plot_centroids.csv")
    gt <- read.csv(gt_f, stringsAsFactors = FALSE)
    pc <- read.csv(pc_f, stringsAsFactors = FALSE)
    fz <- frozen_scope(d, site, A, gt)
    root <- fz$root
    contract <- jsonlite::read_json(file.path(root, "freeze_contract.json"), simplifyVector = TRUE)
    if (!all(unname(tools::md5sum(c(gt_f, pc_f))) %in% contract$input_md5))
      stop(site, ": ground truth or plot centroids differ from the frozen root's inputs")
    popc <- frozen_population(root, site, fz$population)
    m <- match(popc$plotID, pc$plotID)
    if (anyNA(m) || any(abs(pc$easting[m] - popc$easting) > 1e-6 |
                        abs(pc$northing[m] - popc$northing) > 1e-6))
      stop(site, ": plot centroids differ from the frozen population")
    if (length(unique(popc$epsg)) != 1L) stop(site, ": plots in more than one CRS")
    pc$epsg <- popc$epsg[1]; pc$site <- site
    pcs[[site]] <- pc
    for (pid in fz$plots) {
      ci <- popc[popc$plotID == pid, ][1, ]
      half <- ext_core_half(ci$plotType)
      s <- fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - ci$easting) <= half &
                   abs(fz$gt$N - ci$northing) <= half, , drop = FALSE]
      plots[[length(plots) + 1L]] <- data.frame(site = site, plotID = pid, plotType = ci$plotType,
        easting = ci$easting, northing = ci$northing, epsg = ci$epsg, core_half = half,
        stringsAsFactors = FALSE)
      if (!nrow(s)) next
      s$site <- site; s$plotType <- ci$plotType
      recs[[length(recs) + 1L]] <- s
    }
    vst[[site]] <- readRDS(file.path(nd, "vst", paste0(tolower(site), "_vst_allyears.rds")))
  }
  plots <- do.call(rbind, plots)
  cols <- c("site", "plotID", "plotType", "individualID", "E", "N", "height", "stemDiameter",
            "plantStatus", "canopyPosition", "crown_class", "meas_year")
  ref <- do.call(rbind, lapply(recs, function(x) x[, cols]))
  ref$crown_class[!is.na(ref$crown_class) & !nzchar(ref$crown_class)] <- NA

  # The audit reads the same records as the sealed population.
  ps <- read.csv(file.path(root, "population_stems.csv"), stringsAsFactors = FALSE)
  ps <- ps[ps$population == population & ps$site %in% SITES, , drop = FALSE]
  k_ref <- paste(ref$site, ref$plotID, ref$individualID)
  k_ps <- paste(ps$site, ps$plotID, ps$individualID)
  if (anyDuplicated(k_ref) || !setequal(k_ref, k_ps))
    stop("Reference records differ from the frozen population_stems.csv")
  pm <- ps[match(k_ref, k_ps), ]
  pm$crown_class[!is.na(pm$crown_class) & !nzchar(pm$crown_class)] <- NA
  if (!all(same(ref$crown_class, pm$crown_class) & same(ref$height, pm$height) &
           same(ref$stemDiameter, pm$stemDiameter)))
    stop("Reference attributes differ from the frozen population_stems.csv")

  # Scored NEON measurement, re-derived and checked.
  scored <- do.call(rbind, lapply(SITES, function(site) {
    ai <- as.data.frame(vst[[site]]$vst_apparentindividual)
    nn <- neon_nearest_measurements(ai, 2021)
    r <- ref[ref$site == site, , drop = FALSE]
    x <- nn[match(r$individualID, nn$individualID), ]
    if (anyNA(x$individualID)) stop(site, ": reference record without a NEON measurement")
    ok <- x$year == r$meas_year & same(x$height, r$height) & same(x$stemDiameter, r$stemDiameter) &
      same(x$plantStatus, r$plantStatus) & same(x$canopyPosition, r$canopyPosition)
    if (!all(ok)) stop(site, ": ", sum(!ok), " reference records differ from their NEON measurement")
    same_year <- table(paste(ai$individualID, substr(ai$date, 1, 4)))
    ids <- unique(c(as.character(vst[[site]]$vst_mappingandtagging$individualID), ai$individualID))
    fam <- table(ra_bole_parse(ids)$base_id)
    b <- ra_bole_parse(r$individualID)
    data.frame(key = paste(site, r$plotID, r$individualID),
               scored_date = as.Date(substr(x$date, 1, 10)),
               scored_event = if ("eventID" %in% names(x)) x$eventID else NA_character_,
               records_in_scored_year = as.integer(same_year[paste(r$individualID, r$meas_year)]),
               growthForm = x$growthForm, neon_boles_of_individual = as.integer(fam[b$base_id]),
               stringsAsFactors = FALSE)
  }))
  ref <- cbind(ref, scored[match(k_ref, scored$key), setdiff(names(scored), "key")])
  fam <- ra_bole_families(ref$site, ref$individualID)
  if (!all(fam$standard_id)) stop("Reference records with non-standard NEON individual IDs")
  ref <- cbind(ref, fam[, c("base_id", "bole_suffix", "additional_bole", "records_of_individual",
                            "multi_bole_individual")])
  ref$crown_source <- ra_crown_source(ref$canopyPosition, ref$crown_class)
  ref$height_missing <- is.na(ref$height)
  ref <- merge(ref, flights, by = "site", sort = FALSE)
  ref$gap_years_to_2021 <- ref$meas_year - 2021L
  ref$days_to_flight <- as.integer(ref$flight_start - ref$scored_date)
  ref <- ref[order(match(ref$site, SITES), ref$plotID, ref$individualID), ]
  rownames(ref) <- NULL
  write.csv(ref, file.path(OUT, "reference_records.csv"), row.names = FALSE)

  summ <- function(x, site) {
    data.frame(site = site, plots = length(unique(paste(x$site, x$plotID))),
      reference_records = nrow(x),
      distinct_individuals = length(unique(paste(x$site, x$base_id))),
      additional_bole_records = sum(x$additional_bole),
      multi_bole_individuals = length(unique(paste(x$site, x$base_id)[x$additional_bole])),
      records_of_multi_bole_individuals = sum(x$multi_bole_individual),
      growthform_multi_bole_records = sum(x$growthForm %in% "multi-bole tree"),
      records_without_height = sum(x$height_missing),
      additional_boles_without_height = sum(x$height_missing & x$additional_bole),
      crown_canopy_position = sum(x$crown_source == "canopy_position"),
      crown_height_fallback = sum(x$crown_source == "height_fallback"),
      crown_none = sum(x$crown_source == "none"),
      additional_boles_without_class = sum(x$crown_source == "none" & x$additional_bole),
      dominant = sum(x$crown_class %in% "dominant"), codominant = sum(x$crown_class %in% "codominant"),
      intermediate = sum(x$crown_class %in% "intermediate"),
      suppressed = sum(x$crown_class %in% "suppressed"), no_class = sum(is.na(x$crown_class)),
      first_year = min(x$meas_year), last_year = max(x$meas_year),
      records_before_2021 = sum(x$meas_year < 2021L), records_2021 = sum(x$meas_year == 2021L),
      records_after_2021 = sum(x$meas_year > 2021L),
      median_abs_gap_years = median(abs(x$gap_years_to_2021)), stringsAsFactors = FALSE)
  }
  rs <- rbind(do.call(rbind, lapply(SITES, function(s) summ(ref[ref$site == s, ], s))),
              summ(ref, "All"))
  write.csv(rs, file.path(OUT, "reference_summary.csv"), row.names = FALSE)
  ry <- aggregate(list(records = rep(1L, nrow(ref))),
                  ref[c("site", "meas_year", "gap_years_to_2021")], FUN = sum)
  ry$plots <- mapply(function(s, y) length(unique(ref$plotID[ref$site == s & ref$meas_year == y])),
                     ry$site, ry$meas_year)
  ry <- ry[order(match(ry$site, SITES), ry$meas_year), ]
  write.csv(ry, file.path(OUT, "reference_years.csv"), row.names = FALSE)
  say("Population %s: %d plots, %d reference records", population, nrow(plots), nrow(ref))
  for (i in seq_len(nrow(rs))) with(rs[i, ], say(paste(
    "%s: %d records, %d individuals; %d additional-bole records of %d multi-bole individuals",
    "(%d records in all); %d without height; crown class from canopy position %d, height",
    "fallback %d, none %d"), site, reference_records, distinct_individuals, additional_bole_records,
    multi_bole_individuals, records_of_multi_bole_individuals, records_without_height,
    crown_canopy_position, crown_height_fallback, crown_none))
  odd <- ref[ref$additional_bole & !(ref$growthForm %in% "multi-bole tree"), ]
  say("additional-bole records whose scored growth form is not 'multi-bole tree': %d (%s)",
      nrow(odd), paste(odd$individualID, odd$growthForm, collapse = "; "))
  lt <- table(ref$bole_suffix[ref$additional_bole])
  say("bole suffix letters in the reference: %s; additional boles without height %d of %d records without height; without class %d of %d",
      paste(names(lt), lt, collapse = " "), sum(ref$height_missing & ref$additional_bole),
      sum(ref$height_missing), sum(ref$crown_source == "none" & ref$additional_bole),
      sum(ref$crown_source == "none"))

  ## ---- 2. plot measurement years ------------------------------------------------------
  last_rec <- do.call(rbind, lapply(SITES, function(site) {
    v <- vst[[site]]
    mx <- function(tab, q) {
      if (is.null(tab) || !nrow(tab)) return(NA_real_)
      z <- as.Date(substr(tab$date[tab$plotID == q], 1, 10)); z <- z[!is.na(z)]
      if (length(z)) as.numeric(max(z)) else NA_real_
    }
    p <- plots$plotID[plots$site == site]
    dd <- function(tab) as.Date(vapply(p, function(q) mx(tab, q), 0), origin = "1970-01-01")
    data.frame(site = site, plotID = p, last_individual_record = dd(v$vst_apparentindividual),
               last_plot_record = dd(v$vst_perplotperyear),
               last_mapping_record = dd(v$vst_mappingandtagging), stringsAsFactors = FALSE)
  }))
  last_rec$last_field_record <- as.Date(apply(
    last_rec[, c("last_individual_record", "last_plot_record", "last_mapping_record")], 1,
    function(z) if (all(is.na(z))) NA_character_ else max(z, na.rm = TRUE)))
  py <- do.call(rbind, lapply(split(ref, paste(ref$site, ref$plotID)), function(x) {
    yt <- table(x$meas_year)
    data.frame(site = x$site[1], plotID = x$plotID[1], reference_stems = nrow(x),
               meas_years = paste(names(yt), collapse = "/"),
               stems_by_year = paste(names(yt), as.vector(yt), sep = ":", collapse = ";"),
               first_reference_date = min(x$scored_date), last_reference_date = max(x$scored_date),
               stringsAsFactors = FALSE)
  }))
  pt <- merge(plots, py, by = c("site", "plotID"), all.x = TRUE)
  pt$reference_stems[is.na(pt$reference_stems)] <- 0L
  pt <- merge(pt, last_rec, by = c("site", "plotID"), all.x = TRUE)
  pt <- merge(pt, flights, by = "site")
  pt$field_record_after_flight <- pt$last_field_record > pt$flight_end
  ll <- do.call(rbind, lapply(split(pt, pt$epsg), function(x) {
    g <- sf::st_transform(sf::st_as_sf(x, coords = c("easting", "northing"), crs = x$epsg[1]), 4326)
    cbind(x[, c("site", "plotID")], lon = sf::st_coordinates(g)[, 1], lat = sf::st_coordinates(g)[, 2])
  }))
  pt <- merge(pt, ll, by = c("site", "plotID"))
  # The comparison's plots are adopted in both epochs; its stems are the
  # population stems of those plots present in both epochs' populations
  # (compare_sparse_epoch.R MODE=prepare).
  pt$in_sparse_comparison <- NA; pt$sparse_comparison_stems <- NA_integer_
  for (site in intersect(SITES, names(RA_SPARSE_MONTH))) {
    if (is.null(sparse_roots)) next
    f <- file.path(sparse_roots[[site]], c("population.csv", "population_stems.csv"))
    if (!all(file.exists(f)))
      stop("No sparse-epoch population for ", site, " (", f[1], "); pass SPARSE=... or SPARSE=none")
    sp <- read.csv(f[1], stringsAsFactors = FALSE)
    ss <- read.csv(f[2], stringsAsFactors = FALSE)
    i <- pt$site == site
    common <- intersect(pt$plotID[i], sp$plotID[sp$site == site & sp[[paste0("in_", population)]]])
    a21 <- ref[ref$site == site & ref$plotID %in% common, ]
    aS <- ss[ss$site == site & ss$population == population & ss$plotID %in% common, ]
    shared <- intersect(a21$individualID, aS$individualID)
    pt$in_sparse_comparison[i] <- pt$plotID[i] %in% common
    pt$sparse_comparison_stems[i] <- vapply(pt$plotID[i], function(q)
      sum(a21$plotID == q & a21$individualID %in% shared), 0L)
  }
  pt <- pt[order(match(pt$site, SITES), pt$plotType, pt$plotID), ]
  sc <- pt[pt$in_sparse_comparison %in% TRUE, ]
  say("sparse-flight comparison: %s", paste(sprintf("%s %d plots, %d stems", unique(sc$site),
      as.vector(table(sc$site)[unique(sc$site)]),
      as.vector(tapply(sc$sparse_comparison_stems, sc$site, sum)[unique(sc$site)])), collapse = "; "))

  ## ---- 3. fire perimeters -------------------------------------------------------------
  info <- do.call(rbind, lapply(names(RA_SOURCES), ra_layer_info, cache = CACHE, offline = OFFLINE))
  perims <- list(); fetched <- list()
  for (site in SITES) {
    x <- pt[pt$site == site, ]
    box <- c(floor((min(x$lon) - 0.01) * 1e4) / 1e4, floor((min(x$lat) - 0.01) * 1e4) / 1e4,
             ceiling((max(x$lon) + 0.01) * 1e4) / 1e4, ceiling((max(x$lat) + 0.01) * 1e4) / 1e4)
    for (src_id in names(RA_SOURCES)) {
      if (!RA_SITE_STATE[[site]] %in% RA_SOURCES[[src_id]]$states) next
      p <- ra_query_box(src_id, site, box, YEARS, CACHE, OFFLINE)
      n_bad <- 0L
      if (!is.null(p) && nrow(p)) {
        p <- sf::st_transform(ra_normalise(p, src_id), x$epsg[1])
        bad <- !sf::st_is_valid(p); n_bad <- sum(bad)
        if (n_bad) p[bad, ] <- sf::st_make_valid(p[bad, ])
        p$repaired <- bad; p$site <- site
        perims[[length(perims) + 1L]] <- p
      }
      fetched[[length(fetched) + 1L]] <- data.frame(source = src_id, site = site,
        bbox = paste(box, collapse = ","), perimeters_in_box = if (is.null(p)) 0L else nrow(p),
        repaired_geometries = n_bad, stringsAsFactors = FALSE)
    }
  }
  fetched <- do.call(rbind, fetched)
  write.csv(fetched, file.path(OUT, "fire_queries.csv"), row.names = FALSE)
  allp <- do.call(rbind, lapply(perims, function(p) sf::st_drop_geometry(p)))
  allp$fire_key <- NA_character_
  for (s in unique(allp$site)) {
    i <- allp$site == s
    allp$fire_key[i] <- ra_fire_keys(allp$fire_name[i], allp$fire_year[i], allp$irwin[i])
  }
  for (i in seq_along(perims))
    perims[[i]]$fire_key <- allp$fire_key[match(paste(perims[[i]]$site, perims[[i]]$source,
                                                      perims[[i]]$objectid),
                                                paste(allp$site, allp$source, allp$objectid))]
  # One date pair per fire: CAL FIRE's alarm and containment where it holds
  # the fire, otherwise WFIGS discovery and containment.
  fire_dates <- function(site, key) {
    z <- allp[allp$site == site & allp$fire_key == key, ]
    first <- function(v) { v <- v[!is.na(v)]; if (length(v)) min(v) else as.Date(NA) }
    cf <- z[z$source == "calfire_frap", ]; wf <- z[z$source == "nifc_wfigs", ]
    alarm <- first(cf$alarm); src <- "calfire_frap"
    if (is.na(alarm)) { alarm <- first(wf$alarm); src <- if (is.na(alarm)) "none" else "nifc_wfigs" }
    cont <- first(cf$containment); if (is.na(cont)) cont <- first(wf$containment)
    data.frame(alarm_date = alarm, containment_date = cont, date_source = src,
               calfire_alarm = first(cf$alarm), calfire_containment = first(cf$containment),
               wfigs_discovery = first(wf$alarm), wfigs_containment = first(wf$containment),
               fire_year_all = paste(sort(unique(z$fire_year)), collapse = "/"),
               stringsAsFactors = FALSE)
  }

  # Every perimeter in a site's box, with the population plot nearest to it.
  fp <- do.call(rbind, lapply(perims, function(p) {
    x <- pt[pt$site == p$site[1], ]
    pts <- sf::st_as_sf(x, coords = c("easting", "northing"), crs = x$epsg[1])
    dm <- matrix(as.numeric(sf::st_distance(p, pts)), nrow = nrow(p))
    cbind(sf::st_drop_geometry(p)[, c("site", "source", "objectid", "fire_key", "fire_name",
                                      "fire_year", "category", "acres", "alarm", "containment",
                                      "repaired")],
          nearest_plot = x$plotID[apply(dm, 1, which.min)],
          nearest_plot_distance_m = round(apply(dm, 1, min), 1))
  }))
  fp <- fp[order(match(fp$site, SITES), fp$source, fp$fire_year, fp$objectid), ]
  write.csv(fp, file.path(OUT, "fire_perimeters.csv"), row.names = FALSE)

  # Every plot x perimeter within NEAR_M of the centroid, per source.
  sh <- list()
  for (p in perims) {
    site <- p$site[1]; x <- pt[pt$site == site, ]; crs <- x$epsg[1]
    pts <- sf::st_as_sf(x, coords = c("easting", "northing"), crs = crs)
    boxes <- ra_core_boxes(x, crs)
    near <- sf::st_is_within_distance(pts, p, dist = NEAR_M)
    for (i in which(lengths(near) > 0)) for (j in near[[i]]) {
      g <- sf::st_geometry(p[j, ])
      core_in <- sum(as.numeric(sf::st_area(sf::st_intersection(boxes[i], g)))) / (2 * x$core_half[i])^2
      sh[[length(sh) + 1L]] <- data.frame(site = site, plotID = x$plotID[i], source = p$source[j],
        objectid = p$objectid[j], fire_key = p$fire_key[j], fire_name = p$fire_name[j],
        fire_year = p$fire_year[j], category = p$category[j], acres = p$acres[j],
        alarm = p$alarm[j], containment = p$containment[j], source_fire_id = p$source_id[j],
        repaired_geometry = p$repaired[j],
        centroid_inside = lengths(sf::st_intersects(pts[i, ], g)) > 0,
        centroid_distance_to_edge_m = round(as.numeric(sf::st_distance(pts[i, ], sf::st_boundary(g))), 1),
        core_share_inside = round(min(1, core_in), 3), stringsAsFactors = FALSE)
    }
  }
  sh <- if (length(sh)) do.call(rbind, sh) else NULL

  # The services' own point-in-perimeter answers for every plot centroid.
  pc_chk <- list()
  for (site in SITES) for (src_id in names(RA_SOURCES)) {
    if (!RA_SITE_STATE[[site]] %in% RA_SOURCES[[src_id]]$states) next
    x <- pt[pt$site == site, ]
    for (i in seq_len(nrow(x))) {
      srv <- ra_point_ids(src_id, x$lon[i], x$lat[i], YEARS, CACHE,
                          paste(src_id, x$plotID[i], "point", sep = "_"), OFFLINE)
      loc_rows <- if (is.null(sh)) NULL else
        sh[sh$site == site & sh$plotID == x$plotID[i] & sh$source == src_id, ]
      loc <- if (is.null(loc_rows)) numeric(0) else sort(loc_rows$objectid[loc_rows$centroid_inside])
      diff_ids <- union(setdiff(srv, loc), setdiff(loc, srv))
      edge <- if (length(diff_ids) && !is.null(loc_rows))
        loc_rows$centroid_distance_to_edge_m[loc_rows$objectid %in% diff_ids] else numeric(0)
      if (length(diff_ids) && !(length(edge) == length(diff_ids) && all(edge < 1)))
        stop(sprintf("%s %s: local overlay (%s) and service (%s) disagree", src_id, x$plotID[i],
                     paste(loc, collapse = ","), paste(srv, collapse = ",")))
      pc_chk[[length(pc_chk) + 1L]] <- data.frame(site = site, plotID = x$plotID[i], source = src_id,
        service_ids = paste(srv, collapse = ";"), local_ids = paste(loc, collapse = ";"),
        agree = !length(diff_ids), stringsAsFactors = FALSE)
    }
  }
  pc_chk <- do.call(rbind, pc_chk)
  say("service point checks: %d plot x source queries, %d agree with the local overlay, %d differ at an edge closer than 1 m",
      nrow(pc_chk), sum(pc_chk$agree), sum(!pc_chk$agree))

  man <- ra_manifest(CACHE)
  info$accessed_first_utc <- vapply(info$service_layer, function(u) {
    a <- man$accessed_utc[startsWith(man$url, u)]; if (length(a)) min(a) else NA_character_ }, "")
  info$accessed_last_utc <- vapply(info$service_layer, function(u) {
    a <- man$accessed_utc[startsWith(man$url, u)]; if (length(a)) max(a) else NA_character_ }, "")
  info <- merge(info, aggregate(perimeters_in_box ~ source, fetched, sum), by = "source", all.x = TRUE)
  info$fire_years <- paste(YEARS, collapse = "-")
  info$sites <- vapply(info$source, function(s) paste(fetched$site[fetched$source == s], collapse = ","), "")
  write.csv(info[, setdiff(names(info), "accessed_utc")], file.path(OUT, "fire_sources.csv"),
            row.names = FALSE)

  # Plot x fire aggregation over sources, with timing.
  # One source's copy of a fire at a site (union of its features), and a
  # plot centroid, in the site's UTM frame.
  copy_geom <- function(site, key, src) {
    for (p in perims) if (p$site[1] == site && p$source[1] == src) {
      q <- p[p$fire_key == key, ]
      if (nrow(q)) return(sf::st_union(sf::st_geometry(q)))
    }
    NULL
  }
  plot_point <- function(site, pid) {
    x <- pt[pt$site == site & pt$plotID == pid, ]
    sf::st_sfc(sf::st_point(c(x$easting, x$northing)), crs = x$epsg)
  }
  fire_rows <- function(z) {
    a <- allp[allp$site == z$site[1] & allp$fire_key == z$fire_key[1], ]
    acres <- function(s) { v <- a$acres[grepl(s, a$source)]; if (length(v)) max(v) else NA_real_ }
    src_in <- sort(unique(z$source[z$centroid_inside]))
    held <- sort(unique(a$source))
    p0 <- plot_point(z$site[1], z$plotID[1])
    pos <- vapply(held, function(s) {
      g <- copy_geom(z$site[1], z$fire_key[1], s)
      if (lengths(sf::st_intersects(p0, g)) > 0) "inside" else
        sprintf("%.0f m outside", as.numeric(sf::st_distance(p0, g)))
    }, "")
    cbind(data.frame(site = z$site[1], plotID = z$plotID[1], fire_name = z$fire_name[1],
      fire_year = z$fire_year[1], fire_key = z$fire_key[1],
      fire_type = if (any(grepl("prescribed|\\(incident type RX\\)", a$category, ignore.case = TRUE)))
        "prescribed" else "wildfire",
      sources_holding_fire = paste(held, collapse = ";"),
      sources_containing = paste(src_in, collapse = ";"),
      centroid_by_source = paste(held, pos, sep = ": ", collapse = "; "),
      calfire_acres = acres("calfire_frap"), nifc_history_acres = acres("^nifc_history"),
      wfigs_acres = acres("nifc_wfigs"), core_share_inside = max(z$core_share_inside),
      stringsAsFactors = FALSE), fire_dates(z$site[1], z$fire_key[1]))
  }
  timing <- function(fh) {
    if (is.null(fh) || !nrow(fh)) return(fh)
    fh <- cbind(fh, ra_fire_window(fh$alarm_date, fh$containment_date, fh$fire_year))
    fh <- merge(fh, pt[, c("site", "plotID", "plotType", "reference_stems", "meas_years",
                           "first_reference_date", "last_reference_date", "last_field_record",
                           "flight_start", "flight_end", "in_sparse_comparison")],
                by = c("site", "plotID"))
    fh <- merge(fh, sparse_win, by = "site", all.x = TRUE)
    cl <- do.call(rbind, lapply(seq_len(nrow(fh)), function(i) {
      rd <- ref$scored_date[ref$site == fh$site[i] & ref$plotID == fh$plotID[i]]
      ra_classify_fire(fh$fire_start[i], fh$fire_end[i], rd, fh$flight_start[i], fh$flight_end[i],
                       fh$sparse_start[i], fh$sparse_end[i])
    }))
    fh <- cbind(fh, cl)
    fh$field_record_after_fire <- fh$last_field_record > fh$fire_end
    fh[order(match(fh$site, SITES), fh$fire_year, fh$fire_name, fh$plotID), ]
  }
  fh <- fn <- NULL
  if (!is.null(sh)) {
    sh <- sh[order(match(sh$site, SITES), sh$plotID, sh$fire_year, sh$source, sh$objectid), ]
    write.csv(sh, file.path(OUT, "fire_source_hits.csv"), row.names = FALSE)
    grp <- split(sh, paste(sh$site, sh$plotID, sh$fire_key))
    ins <- vapply(grp, function(z) any(z$centroid_inside), TRUE)
    if (any(ins)) fh <- timing(do.call(rbind, lapply(grp[ins], fire_rows)))
    if (any(!ins)) fn <- timing(do.call(rbind, lapply(grp[!ins], fire_rows)))
    if (!is.null(fh)) write.csv(fh, file.path(OUT, "fire_hits.csv"), row.names = FALSE)
    if (!is.null(fn)) {
      fn$nearest_edge_m <- vapply(seq_len(nrow(fn)), function(i) {
        z <- sh[sh$site == fn$site[i] & sh$plotID == fn$plotID[i] & sh$fire_key == fn$fire_key[i], ]
        min(z$centroid_distance_to_edge_m) }, 0)
      write.csv(fn, file.path(OUT, "fire_near_plots.csv"), row.names = FALSE)
    }
    nc <- sh[!sh$centroid_inside & sh$core_share_inside > 0, ]
    say("perimeters overlapping a nominal core box without containing its centroid: %d (%s)",
        nrow(nc), if (nrow(nc)) paste(unique(paste(nc$plotID, nc$fire_name, nc$source)),
                                      collapse = "; ") else "none")
    rep_hits <- sh[sh$repaired_geometry, ]
    say("plot relations involving a repaired (invalid) perimeter geometry: %d", nrow(rep_hits))
  }
  lab <- function(f, plot_site, plot_id) {
    if (is.null(f)) return("")
    z <- f[f$site == plot_site & f$plotID == plot_id, ]
    if (!nrow(z)) return("")
    what <- if (is.null(z$nearest_edge_m)) z$sources_containing else paste0(z$nearest_edge_m, " m")
    paste(unique(paste0(z$fire_name, " ", z$fire_year, " [", what, "]")), collapse = "; ")
  }
  pt$fires_containing_centroid <- vapply(seq_len(nrow(pt)), function(i)
    if (is.null(fh)) 0L else sum(fh$site == pt$site[i] & fh$plotID == pt$plotID[i]), 0L)
  pt$fires <- vapply(seq_len(nrow(pt)), function(i) lab(fh, pt$site[i], pt$plotID[i]), "")
  pt$fires_within_near_m <- vapply(seq_len(nrow(pt)), function(i) lab(fn, pt$site[i], pt$plotID[i]), "")
  write.csv(pt, file.path(OUT, "plot_measurement_years.csv"), row.names = FALSE)

  for (s in SITES) {
    z <- if (is.null(fh)) NULL else fh[fh$site == s, ]
    if (is.null(z) || !nrow(z)) say("%s: no %d-%d perimeter in any source contains a %s plot centroid",
                                    s, YEARS[1], YEARS[2], population)
    else for (k in unique(z$fire_key)) {
      y <- z[z$fire_key == k, ]
      say("%s: %s (%d), alarm %s, contained %s [%s]: %d plots (%s); held by %s; containing: %s; readings: %s",
          s, y$fire_name[1], y$fire_year[1], format(y$alarm_date[1]), format(y$containment_date[1]),
          y$date_source[1], nrow(y), paste(y$plotID, collapse = ","),
          paste(unique(y$sources_holding_fire), collapse = "|"),
          paste(unique(y$sources_containing), collapse = "|"),
          paste(names(table(y$reading)), table(y$reading), sep = " x", collapse = "; "))
    }
    z <- if (is.null(fn)) NULL else fn[fn$site == s, ]
    if (!is.null(z) && nrow(z)) for (i in seq_len(nrow(z))) say(
      "%s: %s %s (%d) edge %.0f m from the centroid, no source contains it; %s", s, z$plotID[i],
      z$fire_name[i], z$fire_year[i], z$nearest_edge_m[i], z$reading[i])
  }

  # Copies of one fire in several sources: displacement diagnostic.
  rel_keys <- unique(paste(sh$site, sh$fire_key))
  off <- list()
  for (k in rel_keys) {
    cand <- lapply(perims, function(p) p[paste(p$site, p$fire_key) == k, ])
    cand <- cand[vapply(cand, nrow, 0L) > 0]
    if (!length(cand)) next
    cp <- do.call(rbind, cand)
    cp$area <- as.numeric(sf::st_area(cp))
    cp <- cp[order(cp$source, -cp$area), ]
    cp <- cp[!duplicated(cp$source), ]                      # each source's largest copy
    if (nrow(cp) < 2) next
    for (a in seq_len(nrow(cp) - 1)) for (b in (a + 1):nrow(cp)) {
      ga <- sf::st_geometry(cp[a, ]); gb <- sf::st_geometry(cp[b, ])
      ca <- sf::st_coordinates(sf::st_centroid(ga)); cb <- sf::st_coordinates(sf::st_centroid(gb))
      sd0 <- sum(as.numeric(sf::st_area(sf::st_sym_difference(ga, gb))))
      gt_ <- ga + c(cb[1] - ca[1], cb[2] - ca[2]); sf::st_crs(gt_) <- sf::st_crs(ga)
      sd1 <- sum(as.numeric(sf::st_area(sf::st_sym_difference(gt_, gb))))
      off[[length(off) + 1L]] <- data.frame(site = cp$site[1], fire_name = cp$fire_name[1],
        fire_year = cp$fire_year[1], fire_key = cp$fire_key[1], source_a = cp$source[a],
        objectid_a = cp$objectid[a], source_b = cp$source[b], objectid_b = cp$objectid[b],
        area_a_km2 = round(cp$area[a] / 1e6, 3), area_b_km2 = round(cp$area[b] / 1e6, 3),
        centroid_shift_east_m = round(cb[1] - ca[1], 1), centroid_shift_north_m = round(cb[2] - ca[2], 1),
        mismatch_km2 = round(sd0 / 1e6, 3), mismatch_after_shift_km2 = round(sd1 / 1e6, 3),
        stringsAsFactors = FALSE)
    }
  }
  if (length(off)) {
    off <- do.call(rbind, off)
    write.csv(off, file.path(OUT, "fire_source_offsets.csv"), row.names = FALSE)
    for (i in seq_len(nrow(off))) with(off[i, ], say(
      "%s %s %d: %s vs %s: areas %.1f / %.1f km2, mismatch %.2f km2; centroid shift %.0f m E, %.0f m N; mismatch after that shift %.2f km2",
      site, fire_name, fire_year, source_a, source_b, area_a_km2, area_b_km2, mismatch_km2,
      centroid_shift_east_m, centroid_shift_north_m, mismatch_after_shift_km2))
  }

  # NEON fire remarks after each related fire, every plot of the site.
  key_start <- function(site, key) {
    fd <- fire_dates(site, key)
    y <- suppressWarnings(as.integer(strsplit(fd$fire_year_all, "/")[[1]][1]))
    if (is.na(fd$alarm_date) && is.na(y)) return(NA_real_)
    as.numeric(ra_fire_window(fd$alarm_date, fd$containment_date, y)$fire_start)
  }
  fr <- list()
  for (k in rel_keys) {
    site <- sub(" .*$", "", k); key <- sub("^[^ ]+ ", "", k)
    z <- sh[sh$site == site & sh$fire_key == key, ]
    cats <- allp$category[allp$site == site & allp$fire_key == key]
    if (any(grepl("prescribed|\\(incident type RX\\)", cats, ignore.case = TRUE))) next  # wildfires only
    fd <- fire_dates(site, key)
    start <- ra_fire_window(fd$alarm_date, fd$containment_date, z$fire_year[1])$fire_start
    ai <- as.data.frame(vst[[site]]$vst_apparentindividual)
    ai$d <- as.Date(substr(ai$date, 1, 10))
    post <- ai[!is.na(ai$d) & ai$d >= start, , drop = FALSE]
    if (!nrow(post)) next
    post$fire_remark <- ra_fire_remark(post$remarks, post$plantStatus)
    pc <- pcs[[site]]
    pp <- pc[pc$plotID %in% unique(post$plotID), , drop = FALSE]
    if (!nrow(pp)) next
    pts <- sf::st_as_sf(pp, coords = c("easting", "northing"), crs = pp$epsg[1])
    rows <- data.frame(site = site, fire_name = z$fire_name[1], fire_year = z$fire_year[1],
      fire_start = start, plotID = pp$plotID, plotType = pp$plotType,
      in_population = pp$plotID %in% pt$plotID[pt$site == site], stringsAsFactors = FALSE)
    rows$post_fire_records <- as.vector(table(factor(post$plotID, levels = pp$plotID)))
    rows$fire_remark_records <- as.vector(tapply(post$fire_remark, factor(post$plotID, levels = pp$plotID), sum))
    rows$first_post_fire_record <- as.Date(as.vector(tapply(as.numeric(post$d),
      factor(post$plotID, levels = pp$plotID), min)), origin = "1970-01-01")
    for (s_id in names(RA_SOURCES)) {
      rows[[paste0("in_", s_id)]] <- NA; rows[[paste0("edge_m_", s_id)]] <- NA_real_
    }
    for (p in perims) {
      if (p$site[1] != site) next
      q <- p[p$fire_key == key, ]
      if (!nrow(q)) next
      g <- sf::st_union(sf::st_geometry(q))
      inside <- lengths(sf::st_intersects(pts, g)) > 0
      dist <- as.numeric(sf::st_distance(pts, sf::st_boundary(g)))
      rows[[paste0("in_", p$source[1])]] <- inside
      rows[[paste0("edge_m_", p$source[1])]] <- round(dist)
    }
    other <- lapply(perims, function(p) if (p$site[1] == site) p[p$fire_key != key, ] else NULL)
    other <- do.call(rbind, other[!vapply(other, is.null, TRUE)])
    rows$other_fires_containing <- if (is.null(other) || !nrow(other)) "" else {
      hit <- sf::st_intersects(pts, other)
      vapply(hit, function(j) paste(sort(unique(paste(other$fire_name[j], other$fire_year[j]))),
                                    collapse = ";"), "")
    }
    # Each source's placement of every fire that started before the plot's
    # first record after this one: inside any of them, or the distance to the
    # nearest.
    for (p in perims) {
      if (p$site[1] != site) next
      st0 <- vapply(p$fire_key, function(k) key_start(site, k), 0)
      d <- vapply(seq_len(nrow(rows)), function(i) {
        ok <- !is.na(st0) & st0 <= as.numeric(rows$first_post_fire_record[i])
        if (!any(ok)) NA_real_ else min(as.numeric(sf::st_distance(pts[i, ], p[ok, ])))
      }, 0)
      rows[[paste0("nearest_earlier_fire_m_", p$source[1])]] <- round(d)
    }
    for (s_id in setdiff(names(RA_SOURCES), sub("^nearest_earlier_fire_m_", "",
                                                 grep("^nearest_earlier", names(rows), value = TRUE))))
      rows[[paste0("nearest_earlier_fire_m_", s_id)]] <- NA_real_
    fr[[length(fr) + 1L]] <- rows
  }
  if (length(fr)) {
    fr <- do.call(rbind, fr)
    fr <- fr[order(match(fr$site, SITES), fr$fire_year, fr$fire_name, fr$plotID), ]
    write.csv(fr, file.path(OUT, "fire_field_remarks.csv"), row.names = FALSE)
    for (k in unique(paste(fr$site, fr$fire_name, fr$fire_year))) {
      z <- fr[paste(fr$site, fr$fire_name, fr$fire_year) == k, ]
      inc <- grep("^in_(nifc|calfire)", names(z), value = TRUE)
      say("%s: %d plots with records after the fire start, %d with fire remarks; inside this fire: %s", k,
          nrow(z), sum(z$fire_remark_records > 0),
          paste(vapply(inc[colSums(!is.na(z[inc])) > 0], function(cn)
            sprintf("%s %d (with remarks %d)", sub("^in_", "", cn), sum(z[[cn]] %in% TRUE),
                    sum(z[[cn]] %in% TRUE & z$fire_remark_records > 0)), ""), collapse = "; "))
      rem <- z[z$fire_remark_records > 0, ]
      for (cn in grep("^nearest_earlier_fire_m_", names(rem), value = TRUE)) {
        v <- rem[[cn]]
        if (all(is.na(v))) next
        out <- v[!is.na(v) & v > 0]
        say("  %s: of %d plots with fire remarks, %d inside an earlier perimeter of this source; the others %s",
            sub("^nearest_earlier_fire_m_", "", cn), nrow(rem), sum(v %in% 0),
            if (length(out)) sprintf("%.0f to %.0f m from the nearest", min(out), max(out)) else "none")
      }
    }
  }

  ## ---- 4. status transitions across each fire ----------------------------------------
  if (!is.null(fh) && nrow(fh)) {
    tr_all <- list()
    for (k in unique(paste(fh$site, fh$fire_key))) {
      y <- fh[paste(fh$site, fh$fire_key) == k, ]
      site <- y$site[1]
      ai <- as.data.frame(vst[[site]]$vst_apparentindividual)
      tr <- ra_status_transitions(ai, plots$plotID[plots$site == site], y$fire_start[1])
      if (!nrow(tr)) next
      tr$site <- site; tr$fire_name <- y$fire_name[1]; tr$fire_year <- y$fire_year[1]
      tr$fire_start <- y$fire_start[1]
      tr$inside_sources <- y$sources_containing[match(tr$plotID, y$plotID)]
      tr$inside_sources[is.na(tr$inside_sources)] <- ""
      tr_all[[length(tr_all) + 1L]] <- tr
    }
    if (length(tr_all)) {
      tr <- do.call(rbind, tr_all)
      lv <- tr[tr$pre_live, ]
      lv$pre_year <- as.integer(format(lv$pre_date, "%Y"))
      lv$dbh10 <- !is.na(lv$pre_dbh) & lv$pre_dbh >= 10
      st <- do.call(rbind, lapply(split(lv, paste(lv$site, lv$fire_name, lv$plotID)), function(z) {
        data.frame(site = z$site[1], fire_name = z$fire_name[1], fire_year = z$fire_year[1],
          plotID = z$plotID[1], inside_sources = z$inside_sources[1],
          live_before_and_remeasured = nrow(z), not_live_after = sum(!z$post_live),
          share_not_live = round(mean(!z$post_live), 3),
          dbh10_live_before = sum(z$dbh10), dbh10_not_live_after = sum(z$dbh10 & !z$post_live),
          last_pre_fire_years = paste(sort(unique(z$pre_year)), collapse = "/"),
          first_post_fire_dates = paste(unique(format(range(z$post_date))), collapse = " to "),
          post_status_not_live = paste(names(table(z$post_status[!z$post_live])),
                                       table(z$post_status[!z$post_live]), sep = ":", collapse = ";"),
          stringsAsFactors = FALSE)
      }))
      st <- st[order(match(st$site, SITES), st$fire_name, !nzchar(st$inside_sources), st$plotID), ]
      write.csv(st, file.path(OUT, "fire_status_transitions.csv"), row.names = FALSE)
      write.csv(lv, file.path(OUT, "fire_status_individuals.csv"), row.names = FALSE)
      for (i in seq_len(nrow(st))) with(st[i, ], say(
        "%s %s %s (inside: %s): %d live at last pre-fire record (%s), %d not live at first post-fire record (%s); DBH>=10 cm: %d, %d",
        site, fire_name, plotID, if (nzchar(inside_sources)) inside_sources else "no source",
        live_before_and_remeasured, last_pre_fire_years, not_live_after, first_post_fire_dates,
        dbh10_live_before, dbh10_not_live_after))
      for (g in c(TRUE, FALSE)) {
        z <- st[nzchar(st$inside_sources) == g, ]
        if (nrow(z)) say("  %s perimeter: %d of %d not live (%.0f%%); DBH>=10 cm %d of %d",
                         if (g) "inside a" else "outside every", sum(z$not_live_after),
                         sum(z$live_before_and_remeasured),
                         100 * sum(z$not_live_after) / sum(z$live_before_and_remeasured),
                         sum(z$dbh10_not_live_after), sum(z$dbh10_live_before))
      }
    } else say("no population plot has field records on both sides of a fire")
  }
  writeLines(log_lines, file.path(OUT, "reference_audit_log.txt"))
  say("wrote %s", OUT)
}

if (sys.nframe() == 0L) ra_main()
