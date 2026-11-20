source(file.path("..", "..", "scripts", "ofo_preflight_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_reference_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_registration_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_conditions_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_disturbance_lib.R"), local = TRUE)

## ---- synthetic geometry ------------------------------------------------------------
OX <- 500000; OY <- 4200000          # multiples of 40 m, UTM 10N
sq <- function(x0, y0, w, h = w, crs = 32610)
  sf::st_sfc(sf::st_polygon(list(matrix(c(x0, y0, x0 + w, y0, x0 + w, y0 + h, x0, y0 + h, x0, y0),
                                        ncol = 2, byrow = TRUE))), crs = crs)
ms <- function(d) as.numeric(as.POSIXct(d, tz = "UTC")) * 1000   # epoch milliseconds
LATEST <- as.Date("2026-11-17")

# Esri JSON of polygon features: `geoms` an sfc (any CRS), `attrs` a data
# frame; written in WGS 84 as the services return it.
esri_json <- function(path, attrs = NULL, geoms = NULL, oid = "OBJECTID", fields = NULL) {
  feats <- list()
  if (!is.null(geoms) && length(geoms)) {
    g <- sf::st_transform(geoms, 4326)
    feats <- lapply(seq_along(g), function(i) {
      rings <- lapply(sf::st_cast(g[i], "POLYGON")[[1]], function(r)
        lapply(seq_len(nrow(r)), function(k) unname(r[k, 1:2])))
      a <- as.list(attrs[i, , drop = FALSE])
      a <- lapply(a, function(v) if (is.na(v)) NULL else v)
      list(attributes = a, geometry = list(rings = rings))
    })
  }
  fl <- if (is.null(fields)) list(list(name = oid, type = "esriFieldTypeOID")) else fields
  js <- list(objectIdFieldName = oid, geometryType = "esriGeometryPolygon",
             spatialReference = list(wkid = 4326, latestWkid = 4326), fields = fl,
             features = feats)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(jsonlite::toJSON(js, auto_unbox = TRUE, digits = NA, null = "null"), path)
  invisible(path)
}
src_of <- function(s) OFO_DIST_SOURCES[OFO_DIST_SOURCES$source == s, ]

## ---- interval and dates --------------------------------------------------------------
test_that("the interval runs from 1 January of the survey year to the last flight day", {
  iv <- ofo_dist_interval(c(2019, 2021, 2019, NA, 2020),
                          c("2022-06-02;2022-08-19;2022-07-01", "2021-07-06",
                            "2013-11-27;2013-11-28", "2022-06-10", NA))
  expect_equal(iv$interval_start,
               as.Date(c("2019-01-01", "2021-01-01", "2019-01-01", NA, "2020-01-01")))
  expect_equal(iv$interval_end,
               as.Date(c("2022-08-19", "2021-07-06", "2013-11-28", "2022-06-10", NA)))
  # A flight before the survey year leaves the declared interval empty.
  expect_equal(iv$interval_problem, c("", "", "interval_reversed", "no_interval", "no_interval"))
  expect_error(ofo_dist_interval(2019, "2022-13-01"), "not an ISO date")
  # Both ends are included; unknown values or ends give NA.
  s <- as.Date("2019-01-01"); e <- as.Date("2022-08-19")
  expect_equal(ofo_dist_in_dates(as.Date(c("2018-12-31", "2019-01-01", "2022-08-19", "2022-08-20",
                                           NA)), s, e), c(FALSE, TRUE, TRUE, FALSE, NA))
  expect_equal(ofo_dist_in_years(c(2018L, 2019L, 2022L, 2023L, NA), s, e),
               c(FALSE, TRUE, TRUE, FALSE, NA))
  expect_true(is.na(ofo_dist_in_dates(as.Date("2020-01-01"), as.Date(NA), e)))
  expect_true(is.na(ofo_dist_in_years(2020L, s, as.Date(NA))))
})

test_that("dates: epoch milliseconds, nulls and placeholders", {
  v <- c(1600000000000, 0, -86400000, NA, ms("9999-12-31"))
  expect_equal(ofo_dist_epoch_date(v, LATEST),
               as.Date(c("2020-09-13", "1970-01-01", "1969-12-31", NA, NA)))
  # As jsonlite returns them: NULL for null, numbers or strings.
  expect_equal(ofo_dist_epoch_date(list(1600000000000, NULL, "1600000000000"), LATEST),
               as.Date(c("2020-09-13", NA, "2020-09-13")))
  # After the retrieval date, or before 1800: a placeholder.
  expect_true(is.na(ofo_dist_epoch_date(ms("2027-01-01"), LATEST)))
  expect_true(is.na(ofo_dist_epoch_date(ms("1799-12-31"), LATEST)))
  expect_equal(ofo_dist_epoch_date(ms("2026-11-17"), LATEST), LATEST)
  # The date is the UTC day.
  expect_equal(ofo_dist_epoch_date(ms("2021-08-01 23:30:00"), LATEST), as.Date("2021-08-01"))
  # Fire years: FIRE_YEAR_INT, else the FIRE_YEAR string; 9999, 0, 1000 unknown.
  expect_equal(ofo_dist_fire_year(c(2019, 9999, 0, NA, NA, 1000, 2030),
                                  c("2019", "9999", "0", "2018", NA, "1000", "2030"), LATEST),
               c(2019L, NA, NA, 2018L, NA, NA, NA))
  expect_equal(ofo_dist_fire_year(list(2016L, NULL), list(NULL, " 2015 "), LATEST), c(2016L, 2015L))
  expect_equal(ofo_dist_fire_year(c(1799, 1800, 2026), NULL, LATEST), c(1799L, 1800L, 2026L))
  # Reconstructed fires centuries old are years, not placeholders.
  expect_equal(ofo_dist_fire_year(c(1308, 1250, 1000, 0, 9999), NULL, LATEST),
               c(1308L, 1250L, NA, NA, NA))
})

## ---- responses and intersection -------------------------------------------------------
test_that("kept responses: attributes, geometry with holes, service errors", {
  d <- tempfile("esri-"); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  outer <- sq(OX, OY, 200)
  hole <- sq(OX + 20, OY + 20, 160)
  donut <- sf::st_difference(outer, hole)                  # an unburned island
  path <- esri_json(file.path(d, "a.json"),
                    data.frame(OBJECTID = c(7, 8), INCIDENT = c("RING", NA),
                               FIRE_YEAR_INT = c(2020, 9999), FIRE_YEAR = c("2020", "9999"),
                               stringsAsFactors = FALSE),
                    c(donut, sq(OX + 500, OY, 10)))
  r <- ofo_dist_read_response(path)
  expect_equal(nrow(r$attrs), 2L)
  expect_equal(r$attrs$OBJECTID, c(7, 8))
  expect_true(is.na(r$attrs$INCIDENT[2]))                   # null attribute
  expect_equal(length(r$geom), 2L)
  expect_equal(sf::st_crs(r$geom)$epsg, 4326L)
  # A plot inside the hole lies outside the perimeter, even with the 50 m
  # buffer (70 m from its inner ring); 30 m from the ring, it is within it.
  inside <- sq(OX + 100, OY + 100, 10)
  h <- ofo_dist_hits(r$geom, inside, OFO_DIST_FIRE_BUFFER_M)
  expect_equal(h$hit, c(FALSE, FALSE))
  expect_equal(h$distance_m[1], 70, tolerance = 1e-3)
  expect_equal(ofo_dist_hits(r$geom, sq(OX + 50, OY + 100, 10), 50)$hit, c(TRUE, FALSE))
  expect_equal(ofo_dist_hits(r$geom, sq(OX + 50, OY + 100, 10), 0)$hit, c(FALSE, FALSE))
  # An empty response reads as no feature; a service error stops.
  e <- esri_json(file.path(d, "e.json"))
  expect_equal(nrow(ofo_dist_read_response(e)$attrs), 0L)
  writeLines('{"error": {"code": 400, "message": "Invalid query"}}', file.path(d, "x.json"))
  expect_error(ofo_dist_read_response(file.path(d, "x.json")), "service error.*Invalid query")
  writeLines('{"fields": []}', file.path(d, "y.json"))
  expect_error(ofo_dist_read_response(file.path(d, "y.json")), "no features array")
})

test_that("intersection: fires within 50 m of the polygon, activities on it", {
  plot <- sq(OX, OY, 100)
  # Squares whose west edge lies 49 m and 51 m east of the plot, and one 1 m
  # east, carried through WGS 84 as the services return them.
  g <- sf::st_transform(c(sq(OX + 149, OY, 20), sq(OX + 151, OY, 20), sq(OX + 101, OY, 20)), 4326)
  fire <- ofo_dist_hits(g, plot, OFO_DIST_FIRE_BUFFER_M)
  expect_equal(fire$hit, c(TRUE, FALSE, TRUE))
  expect_equal(fire$distance_m, c(49, 51, 1), tolerance = 1e-3)
  expect_equal(ofo_dist_hits(g, plot, 0)$hit, c(FALSE, FALSE, FALSE))
  # Exactly 50 m away, and touching the polygon itself, count (in the
  # project frame, where these boundaries are exact).
  expect_true(ofo_dist_hits(sq(OX + 150, OY, 20), plot, OFO_DIST_FIRE_BUFFER_M)$hit)
  expect_true(ofo_dist_hits(sq(OX + 100, OY, 20), plot, 0)$hit)
  expect_false(ofo_dist_hits(sq(OX + 100.01, OY, 20), plot, 0)$hit)
  expect_equal(nrow(ofo_dist_hits(sf::st_sfc(crs = 4326), plot, 0)), 0L)
})

test_that("the envelope holds the buffered polygon and the query asks for everything in it", {
  plot <- sq(OX, OY, 100)
  env <- ofo_dist_envelope(plot, 1000)
  b <- sf::st_transform(sf::st_buffer(plot, 1000), 4326)
  bb <- sf::st_bbox(b)
  expect_true(env[["xmin"]] <= bb[["xmin"]] && env[["xmax"]] >= bb[["xmax"]] &&
                env[["ymin"]] <= bb[["ymin"]] && env[["ymax"]] >= bb[["ymax"]])
  u <- ofo_dist_query_url("https://h/x/FeatureServer/0", env, "OBJECTID")
  expect_match(u, "^https://h/x/FeatureServer/0/query\\?where=1%3D1&geometry=")
  for (k in c("geometryType=esriGeometryEnvelope", "inSR=4326", "outSR=4326", "outFields=%2A",
              "returnGeometry=true", "orderByFields=OBJECTID", "f=json"))
    expect_match(u, k, fixed = TRUE)
  expect_false(grepl("resultOffset", u))
  expect_match(ofo_dist_query_url("https://h/x/0", env, "objectid", 2000), "resultOffset=2000")
})

## ---- record checks -----------------------------------------------------------------------
test_that("fire records: years, discovery dates, unknown dates and failed queries", {
  plot <- sq(OX, OY, 100)
  s <- as.Date("2019-01-01"); e <- as.Date("2022-08-19")
  over <- sf::st_transform(sq(OX + 90, OY, 30), 4326)     # overlaps the plot
  far <- sf::st_transform(sq(OX + 160, OY, 30), 4326)     # 60 m east
  fh <- list(attrs = data.frame(OBJECTID = 1:4, INCIDENT = c("A", "B", "C", "D"),
                                FIRE_YEAR_INT = c(2018, 2022, 9999, 2020),
                                FIRE_YEAR = c("2018", "2022", "9999", "2020"),
                                FEATURE_CA = "Prescribed Fire", stringsAsFactors = FALSE),
             geom = c(over, over, over, far))
  d <- ofo_dist_features(fh, src_of("fire_history"), plot, "P1", s, e, LATEST)
  expect_equal(names(d), OFO_DIST_DETAIL_COLS)
  expect_equal(d$hit, c(TRUE, TRUE, TRUE, FALSE))
  # Fire year within the interval's years: 2022 counts although after the
  # flight day, since the history layer gives a year only.
  expect_equal(d$in_interval, c(FALSE, TRUE, NA, TRUE))
  expect_equal(d$event_year, c(2018L, 2022L, NA, 2020L))
  expect_equal(d$date_raw, c("2018|2018", "2022|2022", "9999|9999", "2020|2020"))
  expect_equal(d$buffer_m, rep(50, 4))
  ck <- ofo_dist_check(d)
  expect_false(ck$clear); expect_equal(ck$n, 1L)
  expect_equal(ck$names, "B (2022, fire_history)")
  expect_equal(ck$why, "record_in_interval")
  # Without that record, the placeholder year leaves the check unmade.
  ck2 <- ofo_dist_check(d[-2, ])
  expect_true(is.na(ck2$clear)); expect_equal(ck2$why, "record_date_unknown")
  expect_equal(ck2$n, 0L); expect_equal(ck2$n_unknown, 1L)
  expect_true(ofo_dist_check(d[c(1, 4), ])$clear)
  # A failed query also leaves it unmade, unless evidence was found anyway.
  ck4 <- ofo_dist_check(d[c(1, 4), ], failed = "fire_wfigs")
  expect_true(is.na(ck4$clear)); expect_equal(ck4$why, "query_failed:fire_wfigs")
  expect_false(ofo_dist_check(d, failed = "fire_wfigs")$clear)
  # No interval: no check, whatever intersects.
  r <- ofo_dist_check(d, interval_problem = "interval_reversed")
  expect_true(is.na(r$clear)); expect_true(is.na(r$n)); expect_equal(r$why, "interval_reversed")
  # WFIGS: the discovery date, both interval ends included; the incident name
  # falls back to the attribute table's.
  wf <- list(attrs = data.frame(OBJECTID = 1:4, poly_IncidentName = c("W1", NA, "W3", "W4"),
                                attr_IncidentName = c("x", "W2", "y", "z"),
                                attr_FireDiscoveryDateTime = c(ms("2018-12-31 23:59:00"),
                                  ms("2019-01-01 00:00:01"), ms("2022-08-19 12:00:00"),
                                  ms("2022-08-20")),
                                stringsAsFactors = FALSE), geom = c(over, over, over, over))
  dw <- ofo_dist_features(wf, src_of("fire_wfigs"), plot, "P1", s, e, LATEST)
  expect_equal(dw$in_interval, c(FALSE, TRUE, TRUE, FALSE))
  expect_equal(dw$name, c("W1", "W2", "W3", "W4"))
  expect_equal(ofo_dist_check(dw)$names, "W2 (2019-01-01, fire_wfigs); W3 (2022-08-19, fire_wfigs)")
})

test_that("activity records: completion date in the interval, on the polygon itself", {
  plot <- sq(OX, OY, 100)
  s <- as.Date("2019-01-01"); e <- as.Date("2022-08-19")
  over <- sf::st_transform(sq(OX + 90, OY, 30), 4326)
  edge <- sf::st_transform(sq(OX + 101, OY, 30), 4326)    # 1 m off the polygon
  act <- list(attrs = data.frame(objectid = 1:6,
                                 activity_name = c("Thin", "Salvage", "Burn", "Late", "Edge",
                                                   "Odd"),
                                 treatment_type = "x",
                                 date_completed = c(ms("2018-12-31"), ms("2019-01-01"),
                                                    ms("2022-08-19"), ms("2022-08-20"),
                                                    ms("2020-05-01"), ms("9999-12-31")),
                                 stringsAsFactors = FALSE),
              geom = c(over, over, over, over, edge, over))
  d <- ofo_dist_features(act, src_of("harvest_2021_current"), plot, "P1", s, e, LATEST)
  expect_equal(d$in_interval, c(FALSE, TRUE, TRUE, FALSE, TRUE, NA))
  expect_equal(d$hit, c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE))
  expect_equal(d$buffer_m, rep(0, 6))
  expect_equal(d$event_date[1:5], c("2018-12-31", "2019-01-01", "2022-08-19", "2022-08-20",
                                    "2020-05-01"))
  ck <- ofo_dist_check(d)
  expect_false(ck$clear); expect_equal(ck$n, 2L)
  # Only records outside the interval: clear; the placeholder date alone: unmade.
  expect_true(ofo_dist_check(d[c(1, 4, 5), ])$clear)
  expect_true(is.na(ofo_dist_check(d[c(1, 6), ])$clear))
})

test_that("record table: counts, names, NFS coverage and the check made per plot", {
  mk <- function(pid, source, hit, inint, name = "n", date = "2020-01-01", category = NA)
    data.frame(plot_id = pid, source = source,
               record = OFO_DIST_SOURCES$record[match(source, OFO_DIST_SOURCES$source)],
               oid = "1", name = name, category = category, date_field = "", date_raw = "",
               event_date = date, event_year = as.integer(substr(date, 1, 4)), date_known = TRUE,
               in_interval = inint, hit = hit, buffer_m = 0, distance_m = 0,
               stringsAsFactors = FALSE)
  det <- rbind(
    mk("P1", "fire_wfigs", TRUE, TRUE, "Big"),
    mk("P1", "harvest_2011_2020", TRUE, FALSE, "Old thin"),
    mk("P1", "nfs_surface_ownership", TRUE, NA, "USDA FOREST SERVICE", NA, "Test NF"),
    mk("P2", "fuels_mechanical", TRUE, TRUE, "Thin"),
    mk("P2", "tsi_2021_current", TRUE, TRUE, "Release"),
    mk("P2", "nfs_surface_ownership", TRUE, NA, "NON-FS", NA, "x"),
    mk("P3", "nfs_surface_ownership", FALSE, NA, "USDA FOREST SERVICE", NA, "Near NF"))
  plots <- data.frame(plot_id = c("P1", "P2", "P3", "P4", "P5"), project_name = "X",
                      group = c("A", "A", "B", "B", "B"),
                      interval_start = as.Date("2019-01-01"),
                      interval_end = as.Date(c("2022-01-01", "2022-01-01", "2022-01-01",
                                               "2022-01-01", NA)),
                      interval_problem = c("", "", "", "", "no_interval"),
                      stringsAsFactors = FALSE)
  fail <- data.frame(plot_id = c("P4", "P4"), source = c("tsi_2011_2020", "nfs_surface_ownership"))
  t <- ofo_dist_record_table(plots, det, fail)
  expect_equal(names(t)[seq_along(OFO_DIST_RECORD_COLS)], OFO_DIST_RECORD_COLS)
  expect_equal(t$fire_clear, c(FALSE, TRUE, TRUE, TRUE, NA))
  expect_equal(t$n_fire_records, c(1L, 0L, 0L, 0L, NA))
  expect_equal(t$fire_names[1], "Big (2020-01-01, fire_wfigs)")
  expect_equal(t$activities_clear, c(TRUE, FALSE, TRUE, NA, NA))
  expect_equal(t$n_activity_records, c(0L, 2L, 0L, 0L, NA))
  expect_equal(t$n_activity_outside_interval[1], 1L)
  expect_equal(t$n_fuels[2], 1L); expect_equal(t$n_tsi[2], 1L)
  # NFS: a Forest Service parcel on the polygon; a non-FS parcel, or a parcel
  # off the polygon, is not; a failed ownership query is unknown.
  expect_equal(t$nfs_records_source, c(TRUE, FALSE, FALSE, NA, FALSE))
  expect_equal(t$nfs_units[1], "Test NF")
  expect_equal(t$queries_failed[4], "tsi_2011_2020;nfs_surface_ownership")
  expect_equal(t$activity_check[4], "query_failed:tsi_2011_2020")
  expect_equal(t$interval_problem, c("", "", "", "", "no_interval"))
  expect_equal(t$fire_check[5], "no_interval")
})

## ---- canopy over mapped trees -------------------------------------------------------------
test_that("presence: the test stems of groups A and B", {
  live <- c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE)
  ref <- c(TRUE, TRUE, FALSE, TRUE, FALSE, TRUE)
  h <- c(30, 12, 40, 8, 50, NA)
  dbh <- c(50, 20, 60, 30, 70, 29.99)
  # The median of the live measured heights (30, 12, 40, 8) is 21: reference
  # stems at 21 m or more.
  expect_equal(ofo_presence_test_stems("A", live, ref, h, dbh),
               c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_equal(ofo_presence_test_stems("A", live, ref, h, dbh), ref & ofo_height_stems(live, h))
  # 10 m when the median is lower.
  expect_equal(ofo_presence_test_stems("A", rep(TRUE, 5), rep(TRUE, 5), c(5, 6, 10, 9.99, 4),
                                       rep(20, 5)), c(FALSE, FALSE, TRUE, FALSE, FALSE))
  expect_equal(ofo_presence_test_stems("A", rep(TRUE, 2), rep(TRUE, 2), c(NA, NA), c(40, 40)),
               c(FALSE, FALSE))
  # Group B: reference stems of 30 cm or more.
  expect_equal(ofo_presence_test_stems("B", live, ref, h, dbh),
               c(TRUE, FALSE, FALSE, TRUE, FALSE, FALSE))
  expect_error(ofo_presence_test_stems("C", live, ref, h, dbh), "groups A and B")
})

test_that("presence: canopy maximum within 2 m, and the rules at their boundaries", {
  S <- list(m = matrix(0, 40, 40), xmin = 0, ymax = 20, res = 0.5)
  S$m[21, 21] <- 12                   # cell centre (10.25, 9.75)
  expect_equal(ofo_presence_canopy_max(S, 8.25, 9.75), 12)          # exactly 2 m
  expect_equal(ofo_presence_canopy_max(S, 8.24, 9.75), 0)           # 2.01 m
  expect_equal(ofo_presence_canopy_max(S, 10.25 + 1.2, 9.75 + 1.6), 12)
  expect_equal(ofo_presence_canopy_max(S, c(-5, 30), c(-5, 30)), c(0, 0))   # off the raster
  expect_equal(ofo_presence_canopy_max(S, 19.9, 10), 0)             # partly off the raster
  expect_true(is.na(ofo_presence_canopy_max(S, NA, 1)))
  # Group A: at least half the measured height; group B: at least 5 m.
  expect_equal(ofo_presence_present("A", c(10, 9.99, 15, NA), rep(20, 4)),
               c(TRUE, FALSE, TRUE, FALSE))
  expect_equal(ofo_presence_present("B", c(5, 4.99, 30, NA)), c(TRUE, FALSE, TRUE, FALSE))
  # Exactly 10% missing passes; fewer than 10 test stems: not checked.
  expect_equal(ofo_presence_status(c(10, 10, 20, 20, 21, 9, 9, 0), c(1, 2, 2, 3, 2, 0, 9, 0)),
               c("pass", "fail", "pass", "fail", "pass", "not_checked", "not_checked",
                 "not_checked"))
})

## ---- disturbance table and conditions -----------------------------------------------------
dist_fixture <- function() {
  data.frame(plot_id = sprintf("%04d", 1:8), project_name = "P", group = "A",
             interval_start = "2019-01-01",
             interval_end = c(rep("2022-06-01", 6), NA, "2018-06-01"),
             n_fire_records = 0L, fire_names = "",
             fire_clear = c(TRUE, FALSE, TRUE, TRUE, NA, TRUE, NA, NA),
             n_activity_records = 0L, activity_names = "",
             nfs_records_source = TRUE,
             activities_clear = c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, NA, NA),
             stringsAsFactors = FALSE)
}

test_that("disturbance: cleared only when all three checks pass; evidence vs checks not made", {
  rec <- dist_fixture()
  pres <- data.frame(plot_id = rec$plot_id, presence_test_stems = c(20, 20, 20, 20, 20, 9, 30, 30),
                     presence_missing = c(2, 0, 0, 3, 0, NA, NA, NA),
                     presence_status = c("pass", "pass", "pass", "fail", "pass", "not_checked",
                                         "not_run", "not_run"),
                     presence_note = "", stringsAsFactors = FALSE)
  d <- ofo_dist_table(rec, pres)
  expect_equal(names(d)[seq_along(OFO_DIST_COLS)], OFO_DIST_COLS)
  expect_equal(d$disturbance_admitted, c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_equal(d$disturbance_reason, c("", "fire", "activity", "presence_fail", "fire_unchecked",
                                       "presence_not_checked",
                                       "fire_unchecked;activity_unchecked;presence_not_run",
                                       "fire_unchecked;activity_unchecked;presence_not_run"))
  expect_equal(d$presence_missing_share[1:4], c(0.1, 0, 0, 0.15))
  expect_true(is.na(d$presence_missing_share[6]))
  expect_equal(ofo_dist_status(d$fire_clear, d$activities_clear, d$presence_status),
               c("undisturbed", "disturbed", "disturbed", "disturbed", "not_checked",
                 "not_checked", "not_checked", "not_checked"))
  expect_true("presence_note" %in% names(d))
  bad <- pres; bad$presence_status[1] <- "maybe"
  expect_error(ofo_dist_table(rec, bad), "Unknown presence status")
  expect_error(ofo_dist_table(rec, pres[-1, ]), "No presence row")
})

test_that("conditions: record or canopy failures are evidence, checks not made unchecked", {
  rec <- dist_fixture()
  pres <- data.frame(plot_id = rec$plot_id, presence_test_stems = 20, presence_missing = 0,
                     presence_status = c("pass", "pass", "pass", "fail", "pass", "not_checked",
                                         "not_run", "not_run"), stringsAsFactors = FALSE)
  dist <- ofo_dist_table(rec, pres)
  # The first protocol's rows: plot 0008 has no cloud and so no row; 0001 is
  # snow-free, 0009 (not in disturbance.csv) is ignored.
  cond1 <- data.frame(plot_id = c(sprintf("%04d", 1:7), "0009"), project_name = "P",
                      same_year = FALSE, snow_window = FALSE, snow_dates_checked = "",
                      snow_depth_max_m = NA_real_, snow_status = "not_winter",
                      deciduous_share = 0, leafoff_window = FALSE, leafoff_status = "leaf_on",
                      disturbance_status = "not_checked", disturbance_admitted = FALSE,
                      conditions_admitted = FALSE, conditions_reason = "no_usable_drone_model",
                      stringsAsFactors = FALSE)
  cond <- ofo_p2_conditions(cond1, dist)
  expect_equal(cond$plot_id, sprintf("%04d", 1:7))
  expect_equal(names(cond)[seq_along(OFO_P2_COND_COLS)], OFO_P2_COND_COLS)
  expect_true(all(is.na(as.matrix(cond[, OFO_P2_DRONE_COLS]))))
  expect_equal(cond$disturbance_status, c("undisturbed", "disturbed", "disturbed", "disturbed",
                                          "not_checked", "not_checked", "not_checked"))
  expect_equal(cond$conditions_admitted, c(TRUE, rep(FALSE, 6)))
  expect_equal(ofo_conditions_check(cond),
               c("pass", "evidence", "evidence", "evidence", "unchecked", "unchecked",
                 "unchecked"))
  expect_equal(cond$conditions_reason, c("", "fire", "activity", "presence_fail", "fire_unchecked",
                                         "presence_not_checked",
                                         "fire_unchecked;activity_unchecked;presence_not_run"))
  expect_equal(cond$interval_covered, c(rep(TRUE, 6), FALSE))
  expect_equal(cond$p1_conditions_reason, rep("no_usable_drone_model", 7))
  # Snow and leaf-off are the first protocol's: snow is evidence even on a
  # cleared plot, an unknown depth is a check not made.
  cond1$snow_status[1] <- "snow"; cond1$snow_status[5] <- "unknown"
  cond1$leafoff_status[2] <- "leaf_off_held"
  c2 <- ofo_p2_conditions(cond1, dist)
  expect_equal(ofo_conditions_check(c2)[c(1, 2, 5)], c("evidence", "evidence", "unchecked"))
  expect_equal(c2$conditions_reason[c(1, 2, 5)], c("snow", "fire;leaf_off",
                                                   "fire_unchecked;snow_unknown"))
  # A reversed interval is not covered.
  d3 <- dist; d3$interval_end[1] <- "2018-01-01"
  expect_false(ofo_p2_conditions(cond1, d3)$interval_covered[1])
  # The decision's hold rule sees the unchecked plots that pass every other gate.
  plots <- data.frame(plot_id = cond$plot_id, project_name = "P", group = "A", screen = "none",
                      stringsAsFactors = FALSE)
  ok <- data.frame(plot_id = cond$plot_id, flight_admitted = TRUE, geometry_consistent = TRUE,
                   registered = TRUE, flight_reason = NA, reason = NA)
  adm <- ofo_plot_admission(plots, ok, ok, cond, ok)
  expect_equal(adm$admitted, c(TRUE, rep(FALSE, 6)))
  expect_equal(adm$unchecked_only, c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE))
  expect_error(ofo_p2_conditions(cond1[, setdiff(names(cond1), "snow_status")], dist),
               "lacks column")
})

## ---- registration gates -------------------------------------------------------------------
gate_fixture <- function() {
  plots <- data.frame(plot_id = sprintf("%04d", 1:10), project_name = "P",
                      screen = c(rep("none", 9), "not_exhaustive"),
                      group = c("A", "A", "A", "A", "A", "B", "B", "B", "B", NA),
                      stringsAsFactors = FALSE)
  plots <- rbind(plots, data.frame(plot_id = "0011", project_name = "NEON2023",
                                   screen = "in_benchmark", group = NA))
  flights <- data.frame(plot_id = plots$plot_id,
                        flight_admitted = c(rep(TRUE, 7), FALSE, FALSE, TRUE, TRUE),
                        cloud_status = c(rep("ok", 8), "no_candidate", "ok", "ok"),
                        stringsAsFactors = FALSE)
  row <- function(pid, signal, dx = 0, dy = 0, sp = 0.5, acc = TRUE, n = 50, rr = "")
    data.frame(plot_id = pid, project_name = "P", set = "candidate", signal = signal,
               n_signal = n, dx = dx, dy = dy, shift_m = sqrt(dx^2 + dy^2),
               objective_zero = 0.1, objective_best = 0.6, objective_median = 0.1,
               contrast = 0.5, residual_m = 0.3, on_edge = FALSE, accepted = acc,
               reject_reason = rr, method = "amendment1", screen = "none", group = "",
               heights_measured = TRUE, status_recorded = TRUE, ql = "QL 1",
               flight_year = 2022, gap_years = 2, flight_admitted = TRUE, surface_error = "",
               z = 5, second_peak = sp, sub_p90_m = 0.2, variant = "ncc",
               stringsAsFactors = FALSE)
  cat <- rbind(
    row("0001", "height", 1, 0, sp = 0.8), row("0001", "rank", 1, 2),        # 0.8 and 2.0 m
    row("0002", "height", sp = 0.8 + 1e-6), row("0002", "rank"),
    row("0003", "height"), row("0003", "rank", 2.01, 0),                     # 2.01 m apart
    row("0004", "height"), row("0004", "rank", 5, 0, acc = FALSE, rr = "sub_p90_m"),
    row("0005", "height", acc = FALSE, n = 19, rr = "n"),
    row("0006", "rank", n = 10),                                             # smallest count
    row("0007", "rank", sp = NA),
    row("0008", "rank"))                                                     # flight not admitted
  # A declared row for the same plot and signal is ignored.
  dec <- row("0006", "rank", acc = FALSE, sp = 0.99); dec$method <- "declared"
  list(plots = plots, flights = flights, cat = rbind(cat, dec))
}

test_that("registration gates: one clear peak, signals agree, at their boundaries", {
  f <- gate_fixture()
  r <- ofo_p2_registration(f$plots, f$flights, f$cat, c(height = TRUE, rank = TRUE))
  expect_equal(names(r)[seq_along(OFO_P2_REG_COLS)], OFO_P2_REG_COLS)
  expect_equal(r$plot_id, sprintf("%04d", 1:9))             # candidates of A and B only
  expect_equal(r$signal_used, c(rep("height", 5), rep("rank", 4)))
  expect_equal(r$registered, c(TRUE, FALSE, FALSE, TRUE, FALSE, TRUE, FALSE, FALSE, FALSE))
  expect_equal(r$reason, c("", "second_peak", "signals_disagree", "", "n", "", "second_peak",
                           "flight_not_admitted", "flight_not_admitted;no_cloud"))
  # second_peak exactly 0.8 passes; agreement exactly 2.0 m passes.
  expect_true(r$second_peak_ok[1]); expect_false(r$second_peak_ok[2])
  expect_equal(r$agreement_m[1], 2)
  expect_true(r$agreement_ok[1]); expect_false(r$agreement_ok[3])
  # In A, a diameter estimate not accepted is not compared (0004); in B the
  # check does not apply.
  expect_equal(r$rank_accepted[1:5], c(TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_equal(r$agreement_applies, c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_equal(r$agreement_m[4], 5)
  expect_true(all(is.na(r$rank_accepted[6:9])))
  # pos_unc as the first protocol: the larger of 0.5 m and the residual.
  expect_equal(r$pos_unc[1], 0.5)
  expect_equal(r$at_min_stems, c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, FALSE))
  expect_equal(r$method, rep("protocol2", 9))
  # The group's signal must be admitted.
  r2 <- ofo_p2_registration(f$plots, f$flights, f$cat, c(height = FALSE, rank = TRUE))
  expect_false(any(r2$registered[1:5]))
  expect_equal(r2$reason[1], "signal_not_admitted")
  expect_equal(r2$registered[6:9], r$registered[6:9])
  # Two method-2 rows for one plot and signal are refused.
  dup <- f$cat[f$cat$plot_id == "0001" & f$cat$signal == "height", ]
  expect_error(ofo_p2_registration(f$plots, f$flights, rbind(f$cat, dup),
                                   c(height = TRUE, rank = TRUE)), "more than one method-2 row")
})

test_that("stage records of the second protocol notice changes in either directory", {
  base <- tempfile("p2rec-"); p2 <- file.path(base, "p2"); pre <- file.path(base, "pre")
  dir.create(p2, recursive = TRUE); dir.create(pre)
  on.exit(unlink(base, recursive = TRUE), add = TRUE)
  writeLines("a", file.path(p2, "in.json")); writeLines("b", file.path(pre, "t.csv"))
  writeLines("c", file.path(p2, "out.csv"))
  rec <- ofo_p2_record("s", p2, ofo_sha256(p2, "in.json"), "out.csv", pre,
                       ofo_sha256(pre, "t.csv"), list(note = 1))
  ofo_write_record(rec, file.path(p2, "s_record.json"))
  back <- jsonlite::read_json(file.path(p2, "s_record.json"))
  expect_length(ofo_p2_record_mismatch(back, p2, pre), 0)
  writeLines("B", file.path(pre, "t.csv"))
  expect_match(ofo_p2_record_mismatch(back, p2, pre), "t.csv differs from the one it read")
  writeLines("b", file.path(pre, "t.csv")); writeLines("C", file.path(p2, "out.csv"))
  expect_match(ofo_p2_record_mismatch(back, p2, pre), "out.csv differs from the one it wrote")
  writeLines("c", file.path(p2, "out.csv"))
  expect_true(any(grepl("were read in", ofo_p2_record_mismatch(back, p2, p2))))
})

## ---- drivers end to end on a synthetic job -------------------------------------------------
run_driver <- function(script, job, args = character()) {
  out <- suppressWarnings(system2("Rscript", c(normalizePath(file.path("..", "..", "scripts",
    script)), args), env = paste0("CLAUDE_JOB_DIR=", job), stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"),
       out = paste(out, collapse = "\n"))
}
rd <- function(path) as.data.frame(data.table::fread(path, na.strings = c("", "NA"),
  colClasses = list(character = intersect(c("plot_id", "interval_start", "interval_end"),
                                          names(data.table::fread(path, nrows = 0))))))

# A cloud: flat ground at 100 m, a cone crown of height h (apex at the
# registered position) for each tree in `keep`.
write_cloud <- function(path, E, N, h, keep, x0, y0) {
  gx <- seq(-30, 130, by = 1)
  g <- expand.grid(X = x0 + gx, Y = y0 + gx)
  o <- expand.grid(dx = seq(-2.4, 2.4, 0.3), dy = seq(-2.4, 2.4, 0.3))
  o <- o[o$dx^2 + o$dy^2 <= 2.5^2, ]
  cr <- do.call(rbind, lapply(which(keep), function(k)
    data.frame(X = E[k] + o$dx, Y = N[k] + o$dy, Z = 100 + h[k] - 0.5 * sqrt(o$dx^2 + o$dy^2),
               Classification = 1L)))
  d <- rbind(data.frame(X = g$X, Y = g$Y, Z = 100, Classification = 2L), cr)
  d$ReturnNumber <- 1L; d$NumberOfReturns <- 1L
  las <- suppressMessages(lidR::LAS(d, crs = sf::st_crs(32610)))
  lidR::writeLAS(las, path)
}

# Groups A (0101-0103) and B (0201-0205) and one C plot (0301), 100 m squares
# with stems on a 10 m grid; method-2 shifts of (1.5, -1). 0102: a WFIGS fire
# in the interval and a third of its tall crowns gone; 0103: second_peak 0.85;
# 0201: an old harvest on National Forest land; 0202: nine stems of 30 cm and
# a fire of unknown year; 0203: no flight.
p2_world <- function(job) {
  ofo <- file.path(job, "ofo")
  pre <- file.path(ofo, "preflight"); p2 <- file.path(ofo, "preflight2")
  for (d in c(pre, p2, file.path(ofo, "clouds"))) dir.create(d, recursive = TRUE)
  ids <- c("0101", "0102", "0103", "0201", "0202", "0203", "0204", "0205", "0301")
  grp <- c("A", "A", "A", "B", "B", "B", "B", "B", "C")
  x0 <- OX + 1000 * seq_along(ids); y0 <- rep(OY, length(ids))
  P <- data.frame(plot_id = ids, project_name = paste0("P", grp), screen = "none", group = grp,
                  live_floor_cm = ifelse(grp == "C", 25.4, 10), license_short = "CC BY 4.0",
                  withhold_from_training = FALSE, survey_year = 2019L, epsg = 32610L,
                  polygon_wkt = vapply(seq_along(ids), function(i)
                    sf::st_as_text(sq(x0[i], y0[i], 100)), ""),
                  polygon_area_m2 = 10000, heights_measured = grp %in% c("A", "C"),
                  status_recorded = TRUE, stringsAsFactors = FALSE)
  shift <- c(1.5, -1)
  trees <- do.call(rbind, lapply(seq_along(ids), function(i) {
    g <- expand.grid(a = 0:9, b = 0:9)
    dbh <- rep(c(12, 25, 35, 45), length.out = 100)
    if (ids[i] == "0202") dbh <- ifelse(seq_len(100) <= 9, 45, 20)
    data.frame(plot_id = ids[i], tree_n = 1:100,
               individual_id = sprintf("OFO.%s.%d", ids[i], 1:100), contributor_tree_id = 1:100, x = x0[i] + 5 + 10 * g$a, y = y0[i] + 5 + 10 * g$b,
               dbh = dbh, height = if (grp[i] == "B") NA_real_ else 10 + 0.4 * dbh,
               species_code = "PSME", live_dead = "L", crown_position = NA, crown_width_1 = NA,
               crown_width_2 = NA, live = TRUE, is_tree = TRUE, inside = TRUE,
               ref = dbh >= ifelse(grp[i] == "C", 25.4, 10), stringsAsFactors = FALSE)
  }))
  cloud <- ids[!ids %in% c("0203", "0301")]
  fl <- data.frame(plot_id = ids, project_name = P$project_name, flight_year = 2022L,
                   flight_admitted = ids %in% cloud, flight_reason = ifelse(ids %in% cloud, NA,
                                                                            "no_public_cloud"),
                   cloud_status = ifelse(ids %in% cloud, "ok", "no_candidate"),
                   flight_days = ifelse(ids %in% cloud, "2022-06-10", NA),
                   flown_from = ifelse(ids %in% cloud, "2022-06-10", NA), gap_years = 3L,
                   stringsAsFactors = FALSE)
  for (i in which(ids %in% cloud)) {
    tr <- trees[trees$plot_id == ids[i], ]
    h <- if (grp[i] == "B") rep(15, 100) else tr$height
    keep <- rep(TRUE, 100)
    if (ids[i] == "0102") {
      tall <- which(tr$height >= 22)
      keep[tall[seq(1, length(tall), by = 3)]] <- FALSE
    }
    write_cloud(file.path(ofo, "clouds", paste0(ids[i], ".laz")), tr$x + shift[1],
                tr$y + shift[2], h, keep, x0[i], y0[i])
  }
  clouds <- data.frame(plot_id = cloud, path = file.path("clouds", paste0(cloud, ".laz")),
                       epsg = 32610L, status = "ok", stringsAsFactors = FALSE)
  clouds$sha256 <- vapply(file.path(ofo, clouds$path), function(f)
    digest::digest(file = f, algo = "sha256"), "")
  cond <- data.frame(plot_id = cloud, project_name = P$project_name[match(cloud, ids)],
                     disturbance_status = "not_checked", interval_covered = NA, same_year = FALSE,
                     disturbance_admitted = FALSE, snow_window = FALSE, snow_dates_checked = "",
                     snow_depth_max_m = NA, snow_status = "not_winter", deciduous_share = 0,
                     leafoff_window = FALSE, leafoff_status = "leaf_on",
                     conditions_admitted = FALSE, conditions_reason = "no_usable_drone_model",
                     stringsAsFactors = FALSE)
  m2 <- function(pid, signal, sp = 0.6)
    data.frame(plot_id = pid, project_name = P$project_name[match(pid, ids)], set = "candidate",
               signal = signal, n_signal = 100L, dx = shift[1], dy = shift[2],
               shift_m = sqrt(sum(shift^2)), objective_zero = 0.1, objective_best = 0.7,
               objective_median = 0.1, contrast = 0.6, residual_m = 0.3, on_edge = FALSE,
               accepted = TRUE, reject_reason = "", method = "amendment1", screen = "none",
               group = P$group[match(pid, ids)], heights_measured = signal == "height",
               status_recorded = TRUE, ql = "QL 1", flight_year = 2022L, gap_years = 3L,
               flight_admitted = TRUE, surface_error = "", z = 6, second_peak = sp,
               sub_p90_m = 0.2, variant = if (signal == "height") "ncc" else "ncc_r2",
               stringsAsFactors = FALSE)
  cat <- rbind(m2("0101", "height"), m2("0101", "rank", 0.55), m2("0102", "height"),
               m2("0103", "height", 0.85), m2("0201", "rank"), m2("0202", "rank"),
               m2("0204", "rank"), m2("0205", "rank"))
  reg1 <- data.frame(plot_id = ids, project_name = P$project_name, group = grp,
                     signal_used = ifelse(grp == "B", "rank", "height"), signal_admitted = FALSE,
                     dx = NA, dy = NA, shift_m = NA, residual_m = NA, contrast = NA,
                     n_signal = NA, registered = FALSE, reason = "signal_not_admitted",
                     pos_unc = NA, flight_admitted = ids %in% cloud, set = "",
                     method = "amendment1", stringsAsFactors = FALSE)
  w <- function(x, f) data.table::fwrite(x, file.path(pre, f))
  w(P, "plots.csv"); w(trees, "trees.csv"); w(fl, "flights.csv"); w(clouds, "clouds.csv")
  w(data.frame(plot_id = ids, geometry_consistent = TRUE), "geometry_audit.csv")
  w(data.frame(plot_id = ids, project_name = P$project_name, license_short = "CC BY 4.0",
               redistribute_reference = TRUE), "licences.csv")
  w(cond, "conditions.csv"); w(cat, "registration_catalog.csv"); w(reg1, "registration.csv")
  jsonlite::write_json(list(admitted = list(height = FALSE, rank = FALSE)),
                       file.path(pre, "registration_tests.json"), auto_unbox = TRUE)
  p1_records(pre)
  jsonlite::write_json(list(admitted = list(height = TRUE, rank = TRUE), rule = "fixture"),
                       file.path(p2, "crowntruth_test.json"), auto_unbox = TRUE)
  p2_responses(p2, P[P$group %in% c("A", "B"), ])
  list(ofo = ofo, pre = pre, p2 = p2)
}

p1_records <- function(pre) {
  rec <- function(stage, inputs, outputs, file)
    ofo_write_record(ofo_stage_record(stage, pre, ofo_sha256(pre, inputs), outputs),
                     file.path(pre, file))
  rec("catalog flights", "plots.csv", "flights.csv", "flights_record.json")
  rec("catalog geometry", c("plots.csv", "trees.csv"), "geometry_audit.csv", "geometry_record.json")
  rec("conditions", c("plots.csv", "trees.csv", "flights.csv", "clouds.csv"), "conditions.csv",
      "conditions_record.json")
  rec("registration catalog", c("plots.csv", "trees.csv", "flights.csv", "clouds.csv"),
      c("registration_catalog.csv", "registration.csv", "registration_tests.json"),
      "registration_catalog_record.json")
}

# Kept responses and layer metadata as STAGE=records leaves them, so OFFLINE
# re-evaluates them without network.
p2_responses <- function(p2, plots) {
  rec <- file.path(p2, "records")
  when <- "2026-11-17T12:00:00Z"
  layers <- lapply(seq_len(nrow(OFO_DIST_SOURCES)), function(i) {
    s <- OFO_DIST_SOURCES[i, ]
    ty <- if (s$date_rule %in% c("discovery_date", "date_completed")) "esriFieldTypeDate" else
      "esriFieldTypeSmallInteger"
    f <- list(list(name = s$oid, type = "esriFieldTypeOID"),
              list(name = s$name_field, type = "esriFieldTypeString"))
    if (nzchar(s$date_field)) f <- c(f, list(list(name = s$date_field, type = ty)))
    path <- file.path(rec, "layers", paste0(s$source, ".json"))
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines(jsonlite::toJSON(list(name = s$layer_name, fields = f), auto_unbox = TRUE), path)
    list(source = s$source, url = paste0(s$url, "?f=json"),
         file = file.path("records", "layers", paste0(s$source, ".json")), status = "ok",
         http_status = 200L, retrieved_utc = when, bytes = file.size(path),
         sha256 = digest::digest(file = path, algo = "sha256"), n_features = 0L,
         exceeded_transfer_limit = FALSE, error = NA)
  })
  special <- function(pid, source) {
    p <- plots[plots$plot_id == pid, ]
    poly <- sf::st_as_sfc(p$polygon_wkt, crs = 32610)
    bb <- sf::st_bbox(poly)
    cover <- sq(bb[["xmin"]] - 10, bb[["ymin"]] - 10, 120)
    key <- paste(pid, source)
    switch(key,
      "0102 fire_wfigs" = list(data.frame(OBJECTID = 1, poly_IncidentName = "TESTFIRE",
        attr_FireDiscoveryDateTime = ms("2021-08-01"), attr_IncidentTypeCategory = "WF"), cover),
      "0101 fire_history" = list(data.frame(OBJECTID = 1, INCIDENT = "FAR", FIRE_YEAR_INT = 2020,
        FIRE_YEAR = "2020", FEATURE_CA = "Wildfire"), sq(bb[["xmax"]] + 60, bb[["ymin"]], 30)),
      "0201 harvest_2011_2020" = list(data.frame(objectid = 1, activity_name = "Commercial Thin",
        treatment_type = "Thinning", date_completed = ms("2012-05-01")), cover),
      "0201 nfs_surface_ownership" = list(data.frame(objectid = 1,
        ownerclassification = "USDA FOREST SERVICE", nfslandunitname = "Test NF"), cover),
      "0202 fire_history" = list(data.frame(OBJECTID = 1, INCIDENT = "OLD", FIRE_YEAR_INT = 9999,
        FIRE_YEAR = "9999", FEATURE_CA = "Wildfire"), cover),
      NULL)
  }
  resp <- list()
  for (pid in plots$plot_id) for (i in seq_len(nrow(OFO_DIST_SOURCES))) {
    s <- OFO_DIST_SOURCES[i, ]
    path <- file.path(rec, pid, paste0(s$source, ".json"))
    sp <- special(pid, s$source)
    if (is.null(sp)) esri_json(path, oid = s$oid) else esri_json(path, sp[[1]], sp[[2]], s$oid)
    resp[[length(resp) + 1L]] <- list(
      plot_id = pid, source = s$source, page = 1L, url = paste0(s$url, "/query?fixture"),
      file = file.path("records", pid, paste0(s$source, ".json")), envelope_wgs84 = "",
      status = "ok", http_status = 200L, retrieved_utc = when, bytes = file.size(path),
      sha256 = digest::digest(file = path, algo = "sha256"),
      n_features = if (is.null(sp)) 0L else 1L, exceeded_transfer_limit = FALSE, error = NA)
  }
  jsonlite::write_json(list(created_utc = when, sources = OFO_DIST_SOURCES, layers = layers,
                            responses = resp),
                       file.path(rec, "records_sources.json"), auto_unbox = TRUE, digits = NA,
                       na = "null", pretty = TRUE)
}

test_that("records, presence, assembly, decision and reference run on a synthetic job", {
  skip_if_not_installed("lidR")
  job <- tempfile("ofo-p2-job-")
  on.exit(unlink(job, recursive = TRUE), add = TRUE)
  W <- p2_world(job)
  pre_files <- sort(list.files(W$pre))
  pre_sha <- ofo_sha256(W$pre, pre_files)

  # Records: re-evaluated from the kept responses (no network).
  r1 <- run_driver("preflight_ofo_disturbance.R", job, c("STAGE=records", "OFFLINE=TRUE"))
  expect_equal(r1$status, 0L, info = r1$out)
  rec <- rd(file.path(W$p2, "disturbance_records.csv"))
  expect_equal(rec$plot_id, c("0101", "0102", "0103", "0201", "0202", "0203", "0204", "0205"))
  expect_equal(rec$fire_clear, c(TRUE, FALSE, TRUE, TRUE, NA, NA, TRUE, TRUE))
  expect_equal(rec$fire_names[2], "TESTFIRE (2021-08-01, fire_wfigs)")
  expect_equal(rec$fire_check[c(1, 5, 6)], c("", "record_date_unknown", "no_interval"))
  expect_equal(rec$activities_clear, c(TRUE, TRUE, TRUE, TRUE, TRUE, NA, TRUE, TRUE))
  expect_equal(rec$n_activity_outside_interval[4], 1L)
  expect_equal(rec$nfs_records_source, c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_true(file.exists(file.path(W$p2, "records_record.json")))
  # A second online run would query again: refused without REQUERY.
  r1b <- run_driver("preflight_ofo_disturbance.R", job, "STAGE=records")
  expect_true(r1b$status != 0); expect_match(r1b$out, "REQUERY=TRUE")
  # A kept response edited after retrieval is refused.
  f <- file.path(W$p2, "records", "0101", "fire_wfigs.json")
  keep <- readLines(f); writeLines(c(keep, " "), f)
  r1c <- run_driver("preflight_ofo_disturbance.R", job, c("STAGE=records", "OFFLINE=TRUE"))
  expect_true(r1c$status != 0); expect_match(r1c$out, "differ from records_sources.json")
  writeLines(keep, f)

  # Presence needs the crown-frame test's final admission.
  ct <- file.path(W$p2, "crowntruth_test.json")
  jsonlite::write_json(list(admitted = list(height = NULL, rank = NULL)), ct, auto_unbox = TRUE,
                       null = "null")
  r2a <- run_driver("preflight_ofo_disturbance.R", job, "STAGE=presence")
  expect_true(r2a$status != 0); expect_match(r2a$out, "lacks a true/false value")
  jsonlite::write_json(list(admitted = list(height = TRUE, rank = TRUE), rule = "fixture"), ct,
                       auto_unbox = TRUE)
  r2 <- run_driver("preflight_ofo_disturbance.R", job, c("STAGE=presence", "CORES=2"))
  expect_equal(r2$status, 0L, info = r2$out)
  d <- rd(file.path(W$p2, "disturbance.csv"))
  expect_equal(names(d)[seq_along(OFO_DIST_COLS)], OFO_DIST_COLS)
  expect_equal(d$presence_status, c("pass", "fail", "not_run", "pass", "not_checked", "not_run",
                                    "pass", "pass"))
  expect_equal(d$presence_note[c(3, 6)], c("not_registered", "not_registered"))
  expect_equal(d$presence_test_stems[c(1, 4, 5)], c(50L, 50L, 9L))
  expect_equal(d$presence_missing[c(1, 2, 4)], c(0L, 17L, 0L))
  expect_equal(d$disturbance_admitted, c(TRUE, FALSE, FALSE, TRUE, FALSE, FALSE, TRUE, TRUE))
  expect_equal(d$disturbance_reason[c(2, 5)], c("fire;presence_fail",
                                                "fire_unchecked;presence_not_checked"))
  st <- rd(file.path(W$p2, "presence_stems.csv"))
  expect_true(all(abs(st$E - st$x - 1.5) < 1e-9 & abs(st$N - st$y + 1) < 1e-9))
  expect_equal(sum(!st$present & st$plot_id == "0102"), 17L)

  # Assembly and the decision with the second protocol's inputs, A and B only.
  r3 <- run_driver("preflight_ofo2_assemble.R", job)
  expect_equal(r3$status, 0L, info = r3$out)
  reg <- rd(file.path(W$p2, "registration.csv"))
  expect_equal(names(reg)[seq_along(OFO_P2_REG_COLS)], OFO_P2_REG_COLS)
  expect_equal(reg$registered, c(TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, TRUE, TRUE))
  expect_equal(reg$reason[3], "second_peak")
  cond <- rd(file.path(W$p2, "conditions.csv"))
  expect_equal(cond$plot_id, c("0101", "0102", "0103", "0201", "0202", "0204", "0205"))
  expect_equal(ofo_conditions_check(cond),
               c("pass", "evidence", "unchecked", "pass", "unchecked", "pass", "pass"))
  tests <- jsonlite::read_json(file.path(W$p2, "registration_tests.json"))
  expect_equal(tests$admitted, list(height = TRUE, rank = TRUE))
  expect_equal(tests$protocol2$crowntruth_test$rule, "fixture")
  dec <- rd(file.path(W$p2, "group_decision.csv"))
  expect_equal(dec$group, c("A", "B"))
  expect_equal(dec$decision, c("no-go", "go"))
  pa <- rd(file.path(W$p2, "plot_admission.csv"))
  expect_setequal(pa$plot_id, reg$plot_id)
  expect_equal(pa$unchecked_only[pa$plot_id == "0202"], TRUE)
  expect_false(any(rd(file.path(W$p2, "cells.csv"))$group %in% c("C", "D")))
  drec <- jsonlite::read_json(file.path(W$p2, "decision_record.json"))
  expect_equal(normalizePath(drec$inputs2_dir), normalizePath(W$p2))
  expect_setequal(names(drec$inputs2), c("conditions.csv", "registration.csv",
                                         "registration_tests.json"))
  expect_equal(unlist(drec$groups), c("A", "B"))
  expect_false("registration.csv" %in% names(drec$inputs))
  # The first protocol's directory is unchanged.
  expect_equal(sort(list.files(W$pre)), pre_files)
  expect_identical(ofo_sha256(W$pre, pre_files), pre_sha)

  # Decision arguments: the default run is the first protocol's, in place.
  r4 <- run_driver("preflight_ofo_decision.R", job)
  expect_equal(r4$status, 0L, info = r4$out)
  d1 <- rd(file.path(W$pre, "group_decision.csv"))
  expect_equal(d1$group, c("A", "B", "C", "D"))
  expect_equal(d1$decision, rep("no-go", 4))
  rec1 <- jsonlite::read_json(file.path(W$pre, "decision_record.json"))
  expect_false(any(c("inputs2_dir", "inputs2", "groups") %in% names(rec1)))
  expect_equal(names(rec1$inputs), c(names(OFO_INPUT_COLUMNS), "registration_tests.json"))
  expect_true("0301" %in% rd(file.path(W$pre, "plot_admission.csv"))$plot_id)
  # GROUPS alone restricts the tables, not the numbers.
  out_g <- file.path(job, "ofo", "groups_only")
  r5 <- run_driver("preflight_ofo_decision.R", job, c(paste0("OUT=", out_g), "GROUPS=B,C"))
  expect_equal(r5$status, 0L, info = r5$out)
  dg <- rd(file.path(out_g, "group_decision.csv"))
  expect_equal(dg$group, c("B", "C"))
  d1bc <- d1[d1$group %in% c("B", "C"), ]; rownames(d1bc) <- NULL
  expect_equal(dg, d1bc)
  expect_setequal(unique(rd(file.path(out_g, "plot_admission.csv"))$group), c("B", "C"))
  # IN2 never writes over the first protocol's decision; bad groups and stale
  # assembled inputs are refused.
  r6 <- run_driver("preflight_ofo_decision.R", job, paste0("IN2=", W$p2))
  expect_true(r6$status != 0); expect_match(r6$out, "never rewritten")
  r7 <- run_driver("preflight_ofo_decision.R", job, c(paste0("OUT=", W$p2), "GROUPS=A,E"))
  expect_true(r7$status != 0); expect_match(r7$out, "GROUPS must be")
  r8 <- run_driver("preflight_ofo_decision.R", job, c("OUT=x", "SITE=y"))
  expect_true(r8$status != 0); expect_match(r8$out, "Unknown argument\\(s\\): SITE")
  cnd <- file.path(W$p2, "conditions.csv")
  keep <- readLines(cnd); writeLines(sub("TRUE", "FALSE", keep), cnd)
  r9 <- run_driver("preflight_ofo_decision.R", job, c(paste0("IN2=", W$p2), paste0("OUT=", W$p2)))
  expect_true(r9$status != 0)
  expect_match(r9$out, "assemble_record.json in .*conditions.csv differs from the one it wrote")
  writeLines(keep, cnd)
  # The assembly refuses a canopy check computed under another crown-frame test.
  r10 <- run_driver("preflight_ofo_disturbance.R", job, "STAGE=presence")
  expect_equal(r10$status, 0L)
  jsonlite::write_json(list(admitted = list(height = FALSE, rank = TRUE)), ct, auto_unbox = TRUE)
  r11 <- run_driver("preflight_ofo2_assemble.R", job)
  expect_true(r11$status != 0)
  expect_match(r11$out, "disturbance_record.json.*crowntruth_test.json")
  jsonlite::write_json(list(admitted = list(height = TRUE, rank = TRUE), rule = "fixture"), ct,
                       auto_unbox = TRUE)
  expect_equal(run_driver("preflight_ofo_disturbance.R", job, "STAGE=presence")$status, 0L)
  expect_equal(run_driver("preflight_ofo2_assemble.R", job)$status, 0L)

  # The reference of a go group from the second protocol's decision.
  r12 <- run_driver("prepare_ofo_reference.R", job, c(paste0("PRE=", W$p2), "GROUPS=A"))
  expect_true(r12$status != 0); expect_match(r12$out, "A=no-go")
  r13 <- run_driver("prepare_ofo_reference.R", job, paste0("PRE=", W$p2))
  expect_equal(r13$status, 0L, info = r13$out)
  gt <- read.csv(file.path(W$p2, "reference", "neon", "PB", "ground_truth_stems.csv"),
                 stringsAsFactors = FALSE)
  expect_equal(sprintf("%04d", sort(unique(gt$ofo_plot_id))), c("0201", "0204", "0205"))
  expect_true(all(abs(gt$E - gt$E_raw - 1.5) < 1e-9))
  expect_true(all(is.na(gt$height)))
  rr <- jsonlite::read_json(file.path(W$p2, "reference", "reference_record.json"))
  expect_equal(normalizePath(rr$decision_dir), normalizePath(W$p2))
  expect_false(dir.exists(file.path(W$ofo, "reference")))
  # Without PRE= the first protocol's decision authorises nothing.
  r14 <- run_driver("prepare_ofo_reference.R", job)
  expect_equal(r14$status, 0L); expect_match(r14$out, "No go group")
  expect_false(dir.exists(file.path(W$ofo, "reference")))
  # PRE= must lie under OFO and hold a current decision of its own outputs.
  r15 <- run_driver("prepare_ofo_reference.R", job, paste0("PRE=", tempdir()))
  expect_true(r15$status != 0); expect_match(r15$out, "PRE must lie under")
  pa2 <- file.path(W$p2, "plot_admission.csv")
  writeLines(sub("TRUE", "FALSE", readLines(pa2)), pa2)
  r16 <- run_driver("prepare_ofo_reference.R", job, c(paste0("PRE=", W$p2), "FORCE=TRUE"))
  expect_true(r16$status != 0)
  expect_match(r16$out, "plot_admission.csv differs from the one it wrote")
  expect_false(dir.exists(file.path(job, "neon")))
})

test_that("an inconclusive crown-frame test places unchecked plots and holds the group", {
  skip_if_not_installed("lidR")
  job <- tempfile("ofo-p2-inc-")
  on.exit(unlink(job, recursive = TRUE), add = TRUE)
  W <- p2_world(job)
  ct <- file.path(W$p2, "crowntruth_test.json")
  jsonlite::write_json(list(admitted = list(height = FALSE, rank = FALSE),
                            signals = list(height = list(inconclusive = TRUE),
                                           rank = list(inconclusive = TRUE)),
                            rule = "fixture"), ct, auto_unbox = TRUE)
  expect_equal(run_driver("preflight_ofo_disturbance.R", job,
                          c("STAGE=records", "OFFLINE=TRUE"))$status, 0L)
  r <- run_driver("preflight_ofo_disturbance.R", job, "STAGE=presence")
  expect_equal(r$status, 0L, info = r$out)
  r <- run_driver("preflight_ofo2_assemble.R", job)
  expect_equal(r$status, 0L, info = r$out)
  reg <- rd(file.path(W$p2, "registration.csv"))
  expect_equal(reg$registration_check[reg$plot_id %in% c("0201", "0202", "0204", "0205")],
               rep("unchecked", 4))
  expect_equal(reg$registration_check[reg$plot_id %in% c("0103", "0203")],
               c("evidence", "evidence"))
  r <- run_driver("preflight_ofo_decision.R", job,
                  c(paste0("IN2=", W$p2), paste0("OUT=", W$p2), "GROUPS=A,B"))
  expect_equal(r$status, 0L, info = r$out)
  cells <- rd(file.path(W$p2, "cells.csv"))
  expect_true(all(cells$provisional[cells$group == "B"]))
  expect_gt(sum(cells$group == "B"), 0)
  pa <- rd(file.path(W$p2, "plot_admission.csv"))
  expect_true(all(pa$n_ref_headline_hold[pa$group == "B" & pa$unchecked_only] > 0))
  dec <- rd(file.path(W$p2, "group_decision.csv"))
  expect_equal(dec$decision[dec$group == "B"], "hold")
  expect_true(dec$signal_inconclusive[dec$group == "B"])
  # A held group authorises nothing: no reference table is written for it.
  r <- run_driver("prepare_ofo_reference.R", job, c(paste0("PRE=", W$p2), "GROUPS=B"))
  expect_true(r$status != 0)
  expect_match(r$out, "B=hold")
  expect_false(dir.exists(file.path(W$p2, "reference")))
})
