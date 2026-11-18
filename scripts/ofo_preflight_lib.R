# Pure helpers for the Open Forest Observatory (OFO) catalogue preflight
# (docs/ofo-preflight-protocol.md): survey dates, tally floors and plot
# groups, project frames, 3DEP candidate ranking, flight admission and the
# geometry audit. No side effects at source time; heavy packages are used via
# pkg::fun so the library sources cheaply in tests.

# ---- Survey dates ---------------------------------------------------------

# survey_date is stored as a real number YYYYMMDD, YYYYMM or YYYY. Format it
# without scientific notation before taking substrings.
.ofo_date_digits <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  s <- ifelse(is.na(x), NA_character_, sprintf("%.0f", x))
  s[!is.na(s) & !nchar(s) %in% c(4L, 6L, 8L)] <- NA_character_
  s
}

ofo_survey_year <- function(x) {
  as.integer(substr(.ofo_date_digits(x), 1, 4))
}

# A month-only date takes the 15th (mid-month), a year-only date 1 July, so
# the representative date is never more than half a period off.
ofo_survey_date <- function(x) {
  s <- .ofo_date_digits(x)
  full <- ifelse(is.na(s), NA_character_,
                 ifelse(nchar(s) == 8L, s,
                        ifelse(nchar(s) == 6L, paste0(s, "15"), paste0(s, "0701"))))
  as.Date(full, format = "%Y%m%d")
}

# ---- Tally rules and plot groups -----------------------------------------

ofo_live_floor <- function(min_dbh, min_dbh_live) {
  ifelse(!is.na(min_dbh_live), min_dbh_live, min_dbh)
}

ofo_is_live <- function(live_dead) !is.na(live_dead) & live_dead %in% c("L", "M")

ofo_is_tree <- function(growth_form) {
  is.na(growth_form) | growth_form %in% c("tree", "intermediate")
}

# Diameter gate of a plot's reference stems before any group harmonisation.
# Groups A and B use the benchmark's 10 cm (protocol table), even when the
# stated floor is up to 10.2 cm: 10.2 is 4 in rounded up, and stems recorded
# at 10.16 cm are at the tally floor. Groups C and D use the plot's own live
# floor; plots without a group the benchmark's 10 cm.
ofo_ref_floor <- function(live_floor, group) {
  ifelse(group %in% c("C", "D"), pmax(10, live_floor, na.rm = TRUE), 10)
}

# Share of live stems >= 10 cm with a measured height; over all live stems
# when no live stem has a diameter (height-only tallies). NA when the
# denominator is empty.
ofo_height_share <- function(live, dbh, height) {
  den <- live & !is.na(dbh) & dbh >= 10
  if (!any(live & !is.na(dbh))) den <- live
  if (!any(den)) return(NA_real_)
  mean(!is.na(height[den]))
}

OFO_FLOOR_SPLIT <- 10.2   # cm; the A/B vs C/D split of the protocol
OFO_HEIGHT_SHARE <- 0.90  # heights count as measured at or above this share
.ofo_eps <- 1e-9          # absorbs binary representation at the thresholds

ofo_heights_measured <- function(share) !is.na(share) & share >= OFO_HEIGHT_SHARE - .ofo_eps

# Screen in the protocol's order; the first failing rule names the screen.
# NEON2023 plots are already in the benchmark and are screened first.
ofo_screen <- function(project_name, hyperplot, exhaustive, status_recorded, live_floor) {
  ifelse(project_name == "NEON2023", "in_benchmark",
    ifelse(hyperplot %in% TRUE, "nested_hyperplot",
      ifelse(!(exhaustive %in% TRUE), "not_exhaustive",
        ifelse(!(status_recorded %in% TRUE), "no_status",
          ifelse(is.na(live_floor), "no_diameter_floor", "none")))))
}

ofo_group <- function(screen, live_floor, heights_measured) {
  low <- live_floor <= OFO_FLOOR_SPLIT + .ofo_eps
  hm <- heights_measured %in% TRUE
  g <- ifelse(low, ifelse(hm, "A", "B"), ifelse(hm, "C", "D"))
  ifelse(screen == "none" & !is.na(live_floor), g, NA_character_)
}

# Per-tree flags. `wref` is the would-be reference flag (ignores `inside`)
# used by the geometry audit; `ref` adds the polygon requirement.
ofo_tree_flags <- function(live_dead, growth_form, dbh, inside, ref_floor) {
  live <- ofo_is_live(live_dead)
  is_tree <- ofo_is_tree(growth_form)
  wref <- live & is_tree & !is.na(dbh) & dbh >= ref_floor - .ofo_eps
  data.frame(live = live, is_tree = is_tree, wref = wref,
             ref = wref & (inside %in% TRUE))
}

# Per-plot counts, screen and group. `plots`: plot_id, project_name,
# hyperplot (logical), exhaustive_survey, min_dbh, min_dbh_live. `trees`:
# plot_id, dbh, height, live_dead, growth_form, crown_position, inside.
ofo_plot_inventory <- function(plots, trees) {
  P <- data.table::as.data.table(plots)
  T <- data.table::as.data.table(trees)
  P[, live_floor_cm := ofo_live_floor(min_dbh, min_dbh_live)]
  T[, live := ofo_is_live(live_dead)]
  per <- T[, {
    den <- live & !is.na(dbh) & dbh >= 10
    if (!any(live & !is.na(dbh))) den <- live
    list(n_trees = .N, n_live = sum(live), n_live_dbh10 = sum(live & !is.na(dbh) & dbh >= 10),
         height_share = ofo_height_share(live, dbh, height),
         crown_position_share = if (any(den)) mean(crown_position[den] %in% 1:5) else NA_real_,
         status_recorded = any(!is.na(live_dead)))
  }, by = plot_id]
  P <- merge(P, per, by = "plot_id", all.x = TRUE)
  P[is.na(n_trees), `:=`(n_trees = 0L, n_live = 0L, n_live_dbh10 = 0L, status_recorded = FALSE)]
  P[, heights_measured := ofo_heights_measured(height_share)]
  P[, screen := ofo_screen(project_name, hyperplot, exhaustive_survey, status_recorded,
                           live_floor_cm)]
  P[, group := ofo_group(screen, live_floor_cm, heights_measured)]
  P[, ref_floor_cm := ofo_ref_floor(live_floor_cm, group)]
  T <- merge(T, P[, .(plot_id, ref_floor_cm)], by = "plot_id", all.x = TRUE)
  fl <- ofo_tree_flags(T$live_dead, T$growth_form, T$dbh, T$inside, T$ref_floor_cm)
  nr <- T[, .(n_ref = sum(fl$ref[.I])), by = plot_id]
  P <- merge(P, nr, by = "plot_id", all.x = TRUE)
  P[is.na(n_ref), n_ref := 0L]
  P[]
}

# ---- Frames ---------------------------------------------------------------

# Northern-hemisphere WGS 84 / UTM zone of a longitude. 120 W itself falls in
# zone 11, the usual floor convention.
ofo_utm_epsg <- function(lon) {
  32600L + as.integer(floor((lon + 180) / 6) + 1)
}

# One frame per project: the zone of the median plot longitude, so plots
# just across a zone boundary share their project's frame.
ofo_project_frames <- function(plots) {
  P <- data.table::as.data.table(plots)
  F <- P[, .(n_plots = .N, median_lon = stats::median(plot_lon)), by = project_name]
  F[, epsg := ofo_utm_epsg(median_lon)]
  F[order(project_name)]
}

# Significant digits of a stored WKT coordinate. sf's default (the "digits"
# option, 7) keeps UTM coordinates to whole metres in y and moved polygon
# boundaries by up to 0.5 m; 15 keeps them to about 1e-8 m.
OFO_WKT_DIGITS <- 15L

# Each polygon of `pl` (sf) as WKT in its project frame `epsg` (one transform
# per frame), at full precision.
ofo_frame_wkt <- function(pl, epsg = pl$epsg) {
  wkt <- character(nrow(pl))
  for (e in unique(epsg)) {
    i <- which(epsg == e)
    wkt[i] <- sf::st_as_text(sf::st_geometry(sf::st_transform(pl[i, ], e)),
                             digits = OFO_WKT_DIGITS)
  }
  wkt
}

# ---- 3DEP candidates ------------------------------------------------------

# WESM rows of each Entwine resource name. Rules in order (as the
# 16 November exploratory check): exact work unit; name without the
# USGS_LPC_ prefix as work unit or project; prefix match either way.
ofo_match_wesm <- function(names, wesm) {
  W <- data.table::as.data.table(wesm)
  rows <- lapply(unique(names), function(n) {
    hit <- W[workunit == n]; rule <- "workunit"
    n2 <- sub("^USGS_LPC_", "", n)
    if (!nrow(hit)) {
      hit <- W[workunit == n2 | project == n2 | project == n]; rule <- "stripped"
    }
    if (!nrow(hit)) {
      hit <- W[startsWith(n2, workunit) | startsWith(workunit, n2)]; rule <- "prefix"
    }
    if (!nrow(hit)) {
      return(data.table::data.table(ept = n, workunit = NA_character_,
                                    wesm_project = NA_character_, ql = NA_character_,
                                    collect_start = NA_character_,
                                    collect_end = NA_character_, wesm_rule = "none",
                                    wesm_rows = 0L))
    }
    data.table::data.table(
      ept = n, workunit = paste(sort(unique(hit$workunit)), collapse = ";"),
      wesm_project = hit$project[1],
      ql = paste(sort(unique(hit$ql)), collapse = "/"),
      collect_start = min(hit$collect_start), collect_end = max(hit$collect_end),
      wesm_rule = rule, wesm_rows = nrow(hit))
  })
  data.table::rbindlist(rows)
}

# Numeric quality level. Several WESM rows with different levels are read
# at the worst of them; non-QL values ("Other") are NA and never admitted.
ofo_ql_num <- function(ql) {
  vapply(strsplit(as.character(ql), "/", fixed = TRUE), function(p) {
    v <- suppressWarnings(as.numeric(sub("^QL\\s*", "", p[grepl("^QL\\s*[0-9]+$", p)])))
    if (!length(v) || length(v) != length(p)) NA_real_ else max(v)
  }, numeric(1))
}

.ofo_wesm_date <- function(x) as.Date(gsub("/", "-", as.character(x)))

# Whole years between a survey year and a collection window [y0, y1]; 0 when
# the survey year falls inside it.
ofo_gap_window <- function(survey_year, collect_start, collect_end) {
  y0 <- as.integer(substr(collect_start, 1, 4))
  y1 <- as.integer(substr(collect_end, 1, 4))
  g <- pmin(abs(survey_year - y0), abs(survey_year - y1))
  ifelse(!is.na(y0) & survey_year >= y0 & survey_year <= y1, 0L, as.integer(g))
}

# Plot x Entwine resource pairs. `plots`: sf of valid plot polygons with
# plot_id, project_name, survey_year. `ept`: sf of the Entwine index
# (name, url, count). Planar intersection in lon/lat is ample at plot scale.
ofo_ept_candidates <- function(plots, ept, wesm) {
  old <- suppressMessages(sf::sf_use_s2(FALSE))
  on.exit(suppressMessages(sf::sf_use_s2(old)))
  ept <- suppressWarnings(sf::st_make_valid(ept))
  ept <- sf::st_transform(ept, sf::st_crs(plots))
  ix <- suppressMessages(sf::st_intersects(plots, ept))
  pairs <- data.table::rbindlist(lapply(seq_along(ix), function(i) {
    if (!length(ix[[i]])) return(NULL)
    data.table::data.table(plot_id = plots$plot_id[i], project_name = plots$project_name[i],
                           survey_year = plots$survey_year[i], ept = ept$name[ix[[i]]],
                           ept_url = ept$url[ix[[i]]], ept_count = as.numeric(ept$count[ix[[i]]]))
  }))
  if (!nrow(pairs)) return(pairs)
  m <- merge(pairs, ofo_match_wesm(unique(pairs$ept), wesm), by = "ept", all.x = TRUE)
  m[, gap_window_years := ofo_gap_window(survey_year, collect_start, collect_end)]
  data.table::setcolorder(m, c("plot_id", "project_name", "ept", "ept_url", "workunit", "ql",
                               "collect_start", "collect_end", "gap_window_years"))
  m[order(plot_id, ept)]
}

# Mirror flags and rank per plot. Mirrors are resources resolving to the
# same work unit; the one named as the work unit (else the shortest name) is
# kept. Ranked: QL <= max_ql only; better QL, smaller gap, later flight,
# work-unit name. The gap and end use measured flight values where present
# (columns gap_flight_years, flown_to) and the work-unit window otherwise.
ofo_rank_flights <- function(cands, max_ql = 2) {
  C <- data.table::copy(data.table::as.data.table(cands))
  if (!nrow(C)) return(C[, `:=`(mirror = logical(), rank = integer())])
  C[, ql_num := ofo_ql_num(ql)]
  C[, .gap := gap_window_years]
  if ("gap_flight_years" %in% names(C)) C[!is.na(gap_flight_years), .gap := gap_flight_years]
  C[, .end := .ofo_wesm_date(collect_end)]
  if ("flown_to" %in% names(C)) C[!is.na(flown_to), .end := as.Date(flown_to)]
  C[, .pref := ifelse(!is.na(workunit) & ept == workunit, 0L, 1L)]
  C[, .nch := nchar(ept)]
  data.table::setorder(C, plot_id, .pref, .nch, ept)
  C[, mirror := !is.na(workunit) & duplicated(workunit), by = plot_id]
  C[, rank := NA_integer_]
  ok <- C$mirror == FALSE & !is.na(C$ql_num) & C$ql_num <= max_ql
  E <- C[ok]
  data.table::setorder(E, plot_id, ql_num, .gap, -.end, workunit, ept, na.last = TRUE)
  E[, rank := seq_len(.N), by = plot_id]
  out <- rbind(E, C[!ok])
  out[, c(".gap", ".end", ".pref", ".nch") := NULL]
  data.table::setorder(out, plot_id, rank, ept, na.last = TRUE)
  out[]
}

# ---- Flight dates, coverage and admission ---------------------------------

# Adjusted standard GPS time (seconds since GPS epoch minus 1e9) to a UTC
# date, with the GPS-UTC leap seconds removed. Values below 1e6 are GPS
# week seconds, which carry no date.
ofo_gps_date <- function(t) {
  t <- as.numeric(t)
  ok <- !is.na(t) & t >= 1e6
  epoch <- as.POSIXct("1980-01-06", tz = "UTC")
  gps <- epoch + ifelse(ok, t, 0) + 1e9
  leaps <- as.numeric(.leap.seconds); leaps <- leaps[leaps > as.numeric(epoch)]
  utc <- gps - findInterval(as.numeric(gps), leaps + seq_along(leaps))
  out <- as.Date(utc, tz = "UTC")
  out[!ok] <- NA
  out
}

# Share of the cell x cell cells (grid aligned to multiples of `cell` in the
# frame) whose centre lies in the polygon buffered by `buffer` and that hold
# at least one return. `poly`: sfc polygon in a metric frame.
ofo_coverage_share <- function(x, y, poly, cell = 5, buffer = 25) {
  b <- sf::st_union(sf::st_buffer(sf::st_geometry(poly), buffer))
  bb <- sf::st_bbox(b)
  x0 <- floor(bb[["xmin"]] / cell) * cell; y0 <- floor(bb[["ymin"]] / cell) * cell
  nx <- ceiling((bb[["xmax"]] - x0) / cell); ny <- ceiling((bb[["ymax"]] - y0) / cell)
  g <- expand.grid(i = seq_len(nx) - 1L, j = seq_len(ny) - 1L)
  ctr <- sf::st_as_sf(data.frame(cx = x0 + (g$i + 0.5) * cell, cy = y0 + (g$j + 0.5) * cell),
                      coords = c("cx", "cy"), crs = sf::st_crs(b))
  inb <- lengths(sf::st_intersects(ctr, b)) > 0
  keep <- !is.na(x) & !is.na(y)
  ix <- floor((x[keep] - x0) / cell); iy <- floor((y[keep] - y0) / cell)
  inr <- ix >= 0 & ix < nx & iy >= 0 & iy < ny
  occ <- unique(ix[inr] + iy[inr] * nx)
  cid <- g$i + g$j * nx
  n <- sum(inb)
  list(share = if (n) sum(cid[inb] %in% occ) / n else NA_real_, n_cells = n,
       n_covered = sum(cid[inb] %in% occ))
}

# Distinct UTC days of a set of GPS times, ascending; week seconds (no date)
# are left out.
ofo_flight_days <- function(gpstime) {
  d <- ofo_gps_date(gpstime)
  sort(unique(d[!is.na(d)]))
}

# ---- Returns kept and cloud measurements ----------------------------------

# Returns kept wherever a cloud is read or measured: classes 7 and 18 (noise)
# and returns flagged withheld are dropped, as the benchmark's other LiDAR
# readers do (-drop_class 7 18 -drop_withheld). The stored clouds keep the
# withheld returns, with their flag.
OFO_DROP_CLASSES <- c(7L, 18L)
OFO_LAS_FILTER <- "-drop_withheld -drop_class 7 18"

ofo_keep_returns <- function(classification, withheld = NULL) {
  n <- length(classification)
  w <- if (is.null(withheld)) rep(FALSE, n) else rep_len(as.logical(withheld), n)
  !(as.integer(classification) %in% OFO_DROP_CLASSES) & !(w %in% TRUE)
}

# A stored cloud read with lidR, kept returns only (the LASlib filter applies
# while reading, whatever `select` holds). readLAS prints progress to stdout.
ofo_read_las <- function(path, select = "xyzc") {
  las <- NULL
  invisible(utils::capture.output(
    las <- lidR::readLAS(path, select = select, filter = OFO_LAS_FILTER)))
  las
}

# Logical: points covered by the polygon (sfc in the points' frame), with a
# bounding-box prefilter.
ofo_points_in <- function(x, y, poly) {
  bb <- sf::st_bbox(poly)
  inn <- rep(FALSE, length(x))
  c0 <- which(!is.na(x) & !is.na(y) & x >= bb[["xmin"]] & x <= bb[["xmax"]] &
                y >= bb[["ymin"]] & y <= bb[["ymax"]])
  if (length(c0)) {
    pts <- sf::st_as_sf(data.frame(X = x[c0], Y = y[c0]), coords = c("X", "Y"),
                        crs = sf::st_crs(poly))
    inn[c0] <- lengths(sf::st_intersects(pts, poly)) > 0
  }
  inn
}

# Densities, GPS-time flight dates and coverage of one cloud (protocol
# "Admitted flights"), from its kept returns. `D`: X, Y, gpstime,
# ReturnNumber, Classification and Withheld_flag of every stored return;
# `poly`: the plot polygon (sfc, project frame); `area_m2` its geodesic area.
# Raw counts (every stored return) are kept beside the measured ones.
ofo_measure_cloud <- function(D, poly, area_m2, survey_year) {
  D <- data.table::as.data.table(D)
  wh <- if (is.null(D$Withheld_flag)) rep(FALSE, nrow(D)) else D$Withheld_flag %in% TRUE
  keep <- ofo_keep_returns(D$Classification, wh)
  inn <- ofo_points_in(D$X, D$Y, poly)
  K <- D[keep]
  P <- D[inn & keep]
  t <- P$gpstime
  gmin <- if (length(t)) min(t) else NA_real_
  gmax <- if (length(t)) max(t) else NA_real_
  from <- ofo_gps_date(gmin); to <- ofo_gps_date(gmax)
  days <- ofo_flight_days(t)
  fy <- as.integer(format(from, "%Y"))
  cov <- ofo_coverage_share(K$X, K$Y, poly)
  ext <- function(v, f) if (length(v)) f(v) else NA_real_
  n_in <- sum(inn)
  n_wh <- sum(wh & inn)
  list(n_points = nrow(K), n_points_raw = nrow(D), n_withheld_cloud = sum(wh),
       n_ground = sum(K$Classification == 2L),
       xmin = ext(K$X, min), ymin = ext(K$Y, min), xmax = ext(K$X, max), ymax = ext(K$Y, max),
       n_points_polygon = nrow(P), n_first_polygon = sum(P$ReturnNumber == 1L),
       n_points_polygon_raw = n_in, n_withheld_polygon = n_wh,
       withheld_share = if (n_in) n_wh / n_in else NA_real_, polygon_area_m2 = area_m2,
       dens_all = nrow(P) / area_m2, dens_first = sum(P$ReturnNumber == 1L) / area_m2,
       gps_min = gmin, gps_max = gmax, gps_median = if (length(t)) stats::median(t) else NA,
       flown_from = format(from), flown_to = format(to),
       flown_median = format(ofo_gps_date(if (length(t)) stats::median(t) else NA)),
       flight_days = paste(format(days), collapse = ";"), n_flight_days = length(days),
       span_days = if (is.na(from) || is.na(to)) NA_real_ else (gmax - gmin) / 86400,
       flight_year = fy, flight_year_to = as.integer(format(to, "%Y")),
       survey_year = survey_year, gap_years = abs(fy - survey_year),
       coverage_share = cov$share, coverage_cells = cov$n_cells,
       coverage_cells_hit = cov$n_covered)
}

OFO_MAX_QL <- 1; OFO_MAX_GAP <- 4; OFO_MIN_COVER <- 0.99; OFO_MAX_SPAN <- 365

# Admission of a plot's flight. Returns the logical and the semicolon-joined
# reasons in the contract's order (empty when admitted).
ofo_flight_admission <- function(cloud_status, ql, gap_years, coverage_share, span_days,
                                 flown_from) {
  n <- length(cloud_status)
  qn <- ofo_ql_num(ql)
  ok <- cloud_status %in% "ok"
  r <- cbind(
    no_public_cloud = !ok,
    # Unknown level fails only a pulled cloud; without one it is not judged.
    quality_level = (!is.na(qn) & qn > OFO_MAX_QL) | (is.na(qn) & ok),
    gap = ok & !is.na(gap_years) & gap_years > OFO_MAX_GAP,
    coverage = ok & (is.na(coverage_share) | coverage_share < OFO_MIN_COVER - .ofo_eps),
    span = ok & !is.na(span_days) & span_days > OFO_MAX_SPAN,
    no_flight_date = ok & is.na(flown_from))
  reason <- vapply(seq_len(n), function(i) paste(colnames(r)[r[i, ]], collapse = ";"),
                   character(1))
  data.frame(flight_admitted = reason == "", flight_reason = reason,
             stringsAsFactors = FALSE)
}

# ---- PDAL pull ------------------------------------------------------------

# Bounds of a frame-space box (xmin, ymin, xmax, ymax) in another SRS: the
# densified box is transformed so the result encloses the whole box.
ofo_bounds_in_srs <- function(bbox, from_epsg, to_crs) {
  r <- sf::st_as_sfc(sf::st_bbox(c(xmin = bbox[[1]], ymin = bbox[[2]], xmax = bbox[[3]],
                                   ymax = bbox[[4]]), crs = sf::st_crs(from_epsg)))
  r <- sf::st_segmentize(r, 5)
  sf::st_bbox(sf::st_transform(r, to_crs))
}

# Centimetre scale with offsets on a 100 m grid below the box, so stored
# coordinates stay on a round grid (PDAL's streamed "auto" offset takes the
# first point's coordinates).
.ofo_las_grid <- function(crop) {
  list(scale_x = 0.01, scale_y = 0.01, scale_z = 0.01, offset_x = floor(crop[[1]] / 100) * 100,
       offset_y = floor(crop[[2]] / 100) * 100, offset_z = 0)
}

# readers.ept over `bounds` (resource SRS) -> drop classes 7 and 18 ->
# reproject to the project frame -> crop to the frame box -> uncompressed
# LAS 1.4 (point format 6), measured before compression.
# The class filter is an expression: filters.range ORs ranges of the same
# dimension, so "Classification![7:7],Classification![18:18]" keeps every
# point.
ofo_pdal_pipeline <- function(ept_url, bounds, out_epsg, crop, out_las) {
  b <- sprintf("([%.3f, %.3f], [%.3f, %.3f])", bounds[["xmin"]], bounds[["xmax"]],
               bounds[["ymin"]], bounds[["ymax"]])
  cb <- sprintf("([%.3f, %.3f], [%.3f, %.3f])", crop[[1]], crop[[3]], crop[[2]], crop[[4]])
  list(
    list(type = "readers.ept", filename = ept_url, bounds = b),
    list(type = "filters.expression", expression = "Classification != 7 && Classification != 18"),
    list(type = "filters.reprojection", out_srs = sprintf("EPSG:%d", as.integer(out_epsg))),
    list(type = "filters.crop", bounds = cb),
    c(list(type = "writers.las", filename = out_las, minor_version = 4, dataformat_id = 6),
      .ofo_las_grid(crop)))
}

# LAS -> LAZ in point format 1. Layered LAZ (formats 6-10) written by PDAL
# 2.9 and by rlas corrupted GpsTime after a jump of about two days between
# returns of one chunk (EPT order mixes flights); format 1 uses the
# point-wise codec, which round-trips these clouds exactly. Format 1 keeps
# GpsTime, returns (up to 7), classes 0-31, intensity and the withheld flag.
# global_encoding 1 marks adjusted standard GPS time.
ofo_pdal_laz_pipeline <- function(in_las, out_laz, crop, gps_standard = TRUE) {
  list(
    list(type = "readers.las", filename = in_las),
    c(list(type = "writers.las", filename = out_laz, compression = "laszip", minor_version = 4,
           dataformat_id = 1, global_encoding = if (gps_standard) 1L else 0L),
      .ofo_las_grid(crop)))
}

# ---- Geometry audit -------------------------------------------------------

# Inside flag and distance (m, 0 inside) of each tree to its own plot
# polygon. `pts`: sf points with plot_id; `polys`: sf polygons with plot_id;
# both in the same metric frame.
ofo_tree_position <- function(pts, polys) {
  inside <- rep(NA, nrow(pts)); dist <- rep(NA_real_, nrow(pts))
  for (p in unique(pts$plot_id)) {
    i <- which(pts$plot_id == p); g <- sf::st_geometry(polys)[polys$plot_id == p]
    if (!length(g)) next
    g <- sf::st_union(g)
    inside[i] <- lengths(sf::st_intersects(sf::st_geometry(pts)[i], g)) > 0
    d <- rep(0, length(i)); o <- !inside[i]
    if (any(o)) d[o] <- as.numeric(sf::st_distance(sf::st_geometry(pts)[i][o], g))
    dist[i] <- d
  }
  data.frame(inside = inside, outside_m = dist)
}

# Ids of other plots overlapping each plot by more than `min_area` m2.
ofo_plot_overlaps <- function(polys, min_area = 1) {
  out <- setNames(rep("", nrow(polys)), polys$plot_id)
  ix <- suppressMessages(sf::st_intersects(polys))
  for (i in seq_along(ix)) {
    j <- setdiff(ix[[i]], i)
    if (!length(j)) next
    a <- vapply(j, function(k) {
      x <- suppressMessages(suppressWarnings(
        sf::st_intersection(sf::st_geometry(polys)[i], sf::st_geometry(polys)[k])))
      if (!length(x)) 0 else sum(as.numeric(sf::st_area(x)))
    }, numeric(1))
    hit <- sort(polys$plot_id[j[a > min_area]])
    out[i] <- paste(hit, collapse = ";")
  }
  out
}

# Coarsest positional step implied by the decimals stored in WGS 84
# coordinates (m): a project rounding longitude to 0.001 deg stores stems on a
# ~75 m grid in x, which shows up as duplicate positions.
ofo_coord_step_m <- function(lon, lat) {
  dec <- function(v) {
    s <- sub("0+$", "", sprintf("%.9f", abs(v[!is.na(v)])))
    if (!length(s)) return(NA_real_)
    max(nchar(sub("^[0-9]*\\.?", "", s)))
  }
  lat0 <- stats::median(lat, na.rm = TRUE)
  max(10^-dec(lon) * 111320 * cos(lat0 * pi / 180), 10^-dec(lat) * 110574)
}

# Per-plot audit. `plots`: plot_id, project_name, polygon_valid,
# polygon_area_m2, plot_area_ha, hyperplot, subplots, n_ref, overlaps_plots.
# `trees`: plot_id, x, y, inside, outside_m, wref (would-be reference stem).
ofo_geometry_audit <- function(plots, trees, min_inside = 0.95, tol_m = 1) {
  P <- data.table::as.data.table(plots)[, .(plot_id, project_name, polygon_valid,
                                             polygon_area_m2, plot_area_ha, hyperplot, subplots,
                                             n_ref, overlaps_plots)]
  T <- data.table::as.data.table(trees)
  per <- T[, .(n_trees = .N, share_outside = mean(!inside),
               share_outside_1m = mean(outside_m > tol_m),
               max_outside_m = max(outside_m),
               n_wref = sum(wref),
               ref_share_inside_1m = if (any(wref)) mean(outside_m[wref] <= tol_m) else NA_real_,
               n_duplicate_xy = sum(duplicated(cbind(round(x, 2), round(y, 2))))),
           by = plot_id]
  if (all(c("lon", "lat") %in% names(T)))
    per <- merge(per, T[, .(coord_step_m = ofo_coord_step_m(lon, lat)), by = plot_id],
                 by = "plot_id")
  A <- merge(P, per, by = "plot_id", all.x = TRUE)
  A[is.na(n_trees), `:=`(n_trees = 0L, n_wref = 0L, n_duplicate_xy = 0L)]
  A[, area_ratio := polygon_area_m2 / (plot_area_ha * 1e4)]
  A[, geometry_consistent := ifelse(is.na(ref_share_inside_1m), NA,
                                    ref_share_inside_1m >= min_inside - .ofo_eps)]
  cols <- c("plot_id", "project_name", "polygon_valid", "polygon_area_m2", "plot_area_ha",
            "area_ratio", "n_trees", "share_outside", "share_outside_1m", "max_outside_m",
            "n_ref", "n_wref", "ref_share_inside_1m", "n_duplicate_xy", "overlaps_plots",
            "hyperplot", "subplots", "geometry_consistent")
  if ("coord_step_m" %in% names(A)) cols <- c(cols, "coord_step_m")
  A[order(plot_id), ..cols]
}

# Per-project roll-up: shares are pooled over stems (sums), not averaged
# over plots.
ofo_geometry_by_project <- function(audit, trees) {
  T <- data.table::as.data.table(trees)
  A <- data.table::as.data.table(audit)
  T <- merge(T, A[, .(plot_id, project_name)], by = "plot_id")
  st <- T[, .(n_trees = .N, share_outside = mean(!inside),
              share_outside_1m = mean(outside_m > 1), max_outside_m = max(outside_m),
              n_wref = sum(wref),
              ref_share_inside_1m = if (any(wref)) mean(outside_m[wref] <= 1) else NA_real_),
          by = project_name]
  pl <- A[, .(n_plots = .N, n_invalid = sum(!polygon_valid),
              area_ratio_min = min(area_ratio), area_ratio_median = stats::median(area_ratio),
              area_ratio_max = max(area_ratio), n_ref = sum(n_ref),
              n_duplicate_xy = sum(n_duplicate_xy),
              n_plots_overlapping = sum(nzchar(overlaps_plots)),
              n_hyperplot = sum(hyperplot), n_subplots = sum(subplots),
              n_geometry_consistent = sum(geometry_consistent %in% TRUE),
              n_geometry_held = sum(geometry_consistent %in% FALSE),
              n_geometry_na = sum(is.na(geometry_consistent)),
              coord_step_m_max = if ("coord_step_m" %in% names(A)) max(coord_step_m) else NA_real_),
          by = project_name]
  out <- merge(pl, st, by = "project_name", all.x = TRUE)
  data.table::setcolorder(out, c("project_name", "n_plots", "n_invalid", "area_ratio_min",
                                 "area_ratio_median", "area_ratio_max", "n_trees",
                                 "share_outside", "share_outside_1m", "max_outside_m",
                                 "n_ref", "n_wref", "ref_share_inside_1m"))
  out[order(project_name)]
}

# ---- Licences -------------------------------------------------------------

ofo_redistributable <- function(license_short) {
  norm <- toupper(gsub("\\s+", " ", trimws(as.character(license_short))))
  !is.na(norm) & norm %in% c("CC BY 4.0", "CC0 1.0", "PUBLIC DOMAIN")
}

# ---- Stage records ----------------------------------------------------------

# Each stage records the SHA-256 of the tables it read and wrote, so a later
# stage can refuse inputs computed from superseded ones (a conditions table
# older than the clouds it describes, say).

# SHA-256 of each file `files` under `dir`, named by file; NA when missing.
ofo_sha256 <- function(dir, files) {
  vapply(stats::setNames(files, files), function(f) {
    p <- file.path(dir, f)
    if (file.exists(p)) digest::digest(file = p, algo = "sha256") else NA_character_
  }, character(1))
}

# `inputs`: digests taken when the stage read them (ofo_sha256()); `outputs`:
# names of the files written, digested now.
ofo_stage_record <- function(stage, dir, inputs, outputs, extra = list()) {
  c(list(stage = stage, created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
         dir = dir, inputs = as.list(inputs), outputs = as.list(ofo_sha256(dir, outputs))),
    extra)
}

ofo_write_record <- function(record, path) {
  jsonlite::write_json(record, path, auto_unbox = TRUE, pretty = TRUE, digits = NA,
                       na = "null", null = "null")
  invisible(path)
}

# One line per file of a record whose current digest under `dir` differs from
# the recorded one (or that is missing now). `parts`: which lists to check.
ofo_record_mismatch <- function(record, dir, parts = c("inputs", "outputs")) {
  msg <- character()
  for (w in parts) {
    rec <- record[[w]]
    if (!length(rec)) next
    cur <- ofo_sha256(dir, names(rec))
    for (f in names(rec)) {
      want <- if (is.null(rec[[f]])) NA_character_ else as.character(rec[[f]])
      if (is.na(cur[[f]])) msg <- c(msg, sprintf("%s is missing", f))
      else if (!identical(cur[[f]], want))
        msg <- c(msg, sprintf("%s differs from the one %s %s", f,
                              if (w == "inputs") "it read" else "it wrote",
                              if (is.na(want)) "(no digest recorded)" else ""))
    }
  }
  trimws(msg)
}

# Checks the records of the earlier stages that a later stage relies on:
# `records` maps a record file under `dir` to the step that writes it. Returns
# the messages (empty when every record is present and current).
ofo_check_records <- function(dir, records) {
  out <- character()
  for (f in names(records)) {
    p <- file.path(dir, f)
    if (!file.exists(p)) {
      out <- c(out, sprintf("%s is missing: rerun %s", f, records[[f]]))
      next
    }
    rec <- tryCatch(jsonlite::read_json(p), error = function(e) NULL)
    if (is.null(rec)) {
      out <- c(out, sprintf("%s is unreadable: rerun %s", f, records[[f]]))
      next
    }
    bad <- ofo_record_mismatch(rec, dir)
    if (length(bad))
      out <- c(out, sprintf("%s (%s): %s; rerun %s", f, rec$stage, paste(bad, collapse = "; "),
                            records[[f]]))
  }
  out
}
