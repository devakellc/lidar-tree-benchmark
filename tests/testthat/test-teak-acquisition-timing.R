source(file.path("..", "..", "scripts", "teak_canopy_lib.R"))
source(file.path("..", "..", "scripts", "teak_acquisition_timing_lib.R"))

timing_test_l1 <- function() c("Mission Name: 2018061416", "Flight Date: 10-Jun-2018",
  "Table 10: Association", "2018061416 9 13-1 411175.6 411382.9 411177 411382",
  "Page 13 of 65", "2018061416 10 14-1 411570.8 411791.9 411572 411791",
  "Page 14 of 65", "Table 11: Trajectory")

test_that("complete L1 parsing preserves mission contradiction, bounds and pages", {
  x <- timing_l1(timing_test_l1())
  expect_equal(x$lms_line, c("13-1", "14-1"))
  expect_equal(x$report_page, 13:14)
  expect_equal(x$flight_date, rep("10-Jun-2018", 2))
  expect_equal(x$trajectory_start[1], 411175.6)
  expect_equal(x$lms_start[1], 411177)
  bad <- timing_test_l1(); bad[4] <- "2018061416 9 13-1 missing"
  expect_error(timing_l1(bad), "Malformed")
  bad <- timing_test_l1(); bad[6] <- bad[4]
  expect_error(timing_l1(bad), "duplicate")
  expect_error(timing_l1(head(timing_test_l1(), -1)), "boundaries")
  expect_error(timing_l1(c(timing_test_l1(), "Mission Name: 2018061416")), "mission")
})

test_that("GPS associations use whole closed intervals and preserve every candidate", {
  x <- timing_l1(timing_test_l1())
  g <- data.frame(PointSourceID = 12, points = 100, gps_min = x$trajectory_start[1],
                  gps_max = x$trajectory_end[1])
  z <- timing_associate(g, x)
  expect_equal(z$lms_line, "13-1")
  expect_equal(z$candidate_count, 1)
  expect_match(z$association_status, "unique")
  y <- x; y$trajectory_start[2] <- g$gps_min; y$trajectory_end[2] <- g$gps_max
  z <- timing_associate(g, y)
  expect_equal(nrow(z), 2)
  expect_true(all(z$candidate_count == 2))
  expect_true(all(is.na(z$utc_min_conditional)))
  g$gps_max <- g$gps_max + 1
  expect_equal(timing_associate(g, x)$association_status, "unmatched_unknown")
  g$gps_min <- NA_real_
  expect_error(timing_associate(g, x), "Invalid GPS")
})

test_that("GPS conversion requires declared historical week, offset and finite week seconds", {
  expect_equal(timing_week_utc(411274.553760119, 2005, 18),
               "2018-06-14T18:14:16.553760Z")
  expect_equal(timing_week_utc(0, 2005, 18), "2018-06-09T23:59:42.000000Z")
  for (x in c(-1, 604800, Inf, NA_real_))
    expect_error(timing_week_utc(x, 2005, 18), "Unsupported")
  expect_error(timing_week_utc(1, 2005, 18, "adjusted_standard"), "Unsupported")
  expect_error(timing_week_utc(1, 2004, 18), "Unsupported")
  expect_error(timing_week_utc(1, 2005, 17), "Unsupported")
})

timing_test_kml <- function(ids = "18061416_EH021537(20180614181536)-0001",
                            polygon = TRUE, coords = "-119,37,0 -118.99,37,0 -118.99,37.01,0 -119,37.01,0 -119,37,0") {
  p <- paste0("<Placemark><name>0001</name><styleUrl>#imageStyle</styleUrl>",
    "<Snippet>", ids, "</Snippet><description>\nFilename: ", ids,
    "\nLat (deg): 37\nLon (deg): -119\nZ (m agl): 948\nHeading (deg): 0\n</description>",
    "<MultiGeometry><Point><coordinates>-119,37,0</coordinates></Point>",
    if (polygon) paste0("<Polygon><outerBoundaryIs><LinearRing><coordinates>", coords,
      "</coordinates></LinearRing></outerBoundaryIs></Polygon>") else "",
    "</MultiGeometry></Placemark>")
  xml2::read_xml(paste0('<kml xmlns="http://www.opengis.net/kml/2.2"><Document>',
                       paste(p, collapse = ""), "</Document></kml>"))
}

test_that("KML uses Polygon and full filename identity, retaining timestamp origin", {
  skip_if_not_installed("sf"); skip_if_not_installed("xml2")
  p <- sf::st_transform(sf::st_sfc(sf::st_point(c(-118.995, 37.005)), crs = 4326), 32611)
  xy <- sf::st_coordinates(p)
  core <- timing_rectangle(c(xy[1] - 20, xy[1] + 20, xy[2] - 20, xy[2] + 20))
  context <- timing_rectangle(c(xy[1] - 45, xy[1] + 45, xy[2] - 45, xy[2] + 45))
  z <- timing_kml(timing_test_kml(), core, context)
  expect_true(z$intersects_core); expect_true(z$covers_core)
  expect_equal(z$filename_utc, "2018-06-14T18:15:36Z")
  expect_equal(z$geometry_type, "Polygon")
  ids <- c(z$frame_id, "18061515_EH021537(20180615180759)-0001")
  expect_equal(nrow(timing_kml(timing_test_kml(ids), core, context)), 2)
  expect_error(timing_kml(timing_test_kml(rep(ids[1], 2)), core, context), "Duplicate")
  expect_error(timing_kml(timing_test_kml(polygon = FALSE), core, context), "Polygon")
  expect_error(timing_kml(timing_test_kml("bad-id"), core, context), "filename")
  expect_error(timing_kml(timing_test_kml(sub("20180614", "20180230", ids[1])), core, context), "timestamp")
  expect_error(timing_kml(timing_test_kml(coords = "-119,37,0 -118,37,NaN -118,38,0 -119,37,0"), core, context), "geometry")
  doc <- xml2::read_xml('<kml xmlns="urn:unknown"><Document/></kml>')
  expect_error(timing_kml(doc, core, context), "namespace")
})

test_that("metric intersection includes edge touches and rejects invalid bounds", {
  a <- timing_rectangle(c(0, 1, 0, 1))
  b <- timing_rectangle(c(1, 2, 0, 1))
  expect_equal(lengths(sf::st_intersects(a, b)), 1L)
  expect_error(timing_rectangle(c(1, 0, 0, 1)), "bounds")
  expect_error(timing_rectangle(c(0, 1, 0, 1), 3857), "CRS")
})

test_that("file contract rejects tampering, extra files, escapes and aliases", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  writeLines("original", file.path(d, "one"))
  rows <- timing_record(d, "one")
  expect_silent(timing_check_files(d, rows, exact = TRUE))
  writeLines("extra", file.path(d, "two"))
  expect_error(timing_check_files(d, rows, exact = TRUE), "extra")
  writeLines("tampered", file.path(d, "one"))
  expect_error(timing_check_files(d, rows), "mismatch")
  bad <- rows; bad$path <- "../one"
  expect_error(timing_check_files(d, bad), "Unsafe")
  expect_error(timing_check_files(d, rbind(rows, rows)), "duplicate")
  file.symlink(file.path(d, "one"), file.path(d, "alias"))
  bad <- timing_record(d, "alias")
  expect_error(timing_check_files(d, bad), "aliased")
  gates <- timing_gates()
  expect_true(all(vapply(gates[1:6], identical, logical(1), FALSE)))
  expect_equal(gates$checkpoint_exposure, "unknown")
  expect_length(gates$reserved_plots_processed, 0L)
})


test_that("L3 repeated labels retain distinct source rows and GPS intervals", {
  text <- c("Table 4: Processed lines",
    "L041-1 100 499346.0 499482.0 2.0", "Page 6 of 65",
    "L041-1 200 580846.0 580981.0 3.0", "Page 7 of 65",
    "Table 5: Bounds")
  z <- timing_l3(text)
  expect_equal(nrow(z), 2L)
  expect_equal(z$processed_line, rep("L041-1", 2))
  expect_equal(z$gps_start, c(499346, 580846))
  expect_equal(z$source_table_row, 1:2)
  expect_equal(z$report_page, 6:7)
})

test_that("unique GPS interval cannot anchor an unrelated mission calendar week", {
  x <- timing_l1(timing_test_l1())
  g <- data.frame(PointSourceID = 12, points = 100, gps_min = 411274, gps_max = 411276)
  expect_match(timing_associate(g, x)$utc_conversion_status, "conditional")
  x$mission[1] <- "2018071416"
  z <- timing_associate(g, x)
  expect_equal(z$candidate_count, 1L)
  expect_true(is.na(z$utc_min_conditional))
  expect_match(z$utc_conversion_status, "unknown")
})


test_that("camera inventory accepts distinct KMZ variants but rejects duplicate frames", {
  x <- list(product = "DP1.30010.001", site = "TEAK", month = "2018-06",
    release = "RELEASE-2026", files = data.frame(
      name = c("18061416_EH021537(20180614181536)-0001_ort.tif",
               "2018_TEAK_3_mosaic.kmz", "2018_TEAK_3_mosaic.kmz"),
      size = c(123, 23807048, 24120301)))
  expect_equal(timing_camera_inventory(x), "18061416_EH021537(20180614181536)-0001")
  x$files <- rbind(x$files, x$files[1, ])
  expect_error(timing_camera_inventory(x), "duplicate")
})

test_that("unsupported declaration claims and source identities fail closed", {
  m <- jsonlite::fromJSON(file.path("..", "..", "docs", "teak-acquisition-timing-sources.json"))
  expect_silent(timing_declaration(m))
  for (key in c("schema_version", "scope", "calendar_basis", "camera_timestamp_basis")) {
    bad <- m; bad[[key]] <- "unsupported"
    expect_error(timing_declaration(bad), "semantics")
  }
  for (key in c("product", "site", "month", "release", "name", "source_url")) {
    bad <- m; bad$sources[[key]][1] <- "unsupported"
    expect_error(timing_declaration(bad), "declaration|identity")
  }
  bad <- m; bad$sources$path[1] <- "../escape.kmz"
  expect_error(timing_declaration(bad), "Unsafe")
})


test_that("damaged leading table tokens cannot hide interval candidates", {
  text <- timing_test_l1()
  text[4] <- sub("2018061416", "2018x61416", text[4], fixed = TRUE)
  expect_error(timing_l1(text), "Unparsed row-like")
  text <- c("Table 4: Processed lines", "X041-1 100 499346.0 499482.0 2.0",
            "Page 6 of 65", "Table 5: Bounds")
  expect_error(timing_l3(text), "Unparsed row-like")
})

test_that("pinned interval completeness includes row counts and mission set", {
  x <- timing_l1(timing_test_l1())
  d <- list(expected_l1_table_rows = 2L, expected_l3_table_rows = 2L,
            expected_l1_missions = "2018061416")
  expect_silent(timing_check_interval_inventory(x, x, d))
  expect_error(timing_check_interval_inventory(x[1, ], x, d), "Incomplete")
  expect_error(timing_check_interval_inventory(x, x[1, ], d), "Incomplete")
  x$mission[2] <- "2018061515"
  expect_error(timing_check_interval_inventory(x, x, d), "mission set")
})

test_that("L3 corroboration requires unique intervals and the same normalized line", {
  l1 <- timing_l1(timing_test_l1())
  gps <- data.frame(PointSourceID = 12, points = 100, gps_min = 411274, gps_max = 411276)
  a <- timing_associate(gps, l1)
  l3 <- data.frame(lms_line = "13-1", gps_start = 411177, gps_end = 411382)
  z <- timing_l3_corroboration(gps, a, l3)
  expect_equal(z$corroboration_status, "corroborated_unique_interval_and_line")
  l3$lms_line <- "99-1"
  expect_equal(timing_l3_corroboration(gps, a, l3)$corroboration_status,
               "unknown_line_disagreement")
  z <- timing_l3_corroboration(gps, a, rbind(l3, l3))
  expect_equal(nrow(z), 2L)
  expect_true(all(z$corroboration_status == "unknown_ambiguous_l3_intervals"))
  l3$gps_start <- 411300
  expect_equal(timing_l3_corroboration(gps, a, l3)$corroboration_status,
               "unknown_no_l3_interval")
  l3$gps_start <- 411177; a$candidate_count <- 2L
  expect_equal(timing_l3_corroboration(gps, a, l3)$corroboration_status,
               "unknown_nonunique_l1_association")
})
