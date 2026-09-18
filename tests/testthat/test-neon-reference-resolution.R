source(file.path("..", "..", "scripts", "neon_spatial_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "neon_reference_support_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "neon_reference_resolution_lib.R"), local = TRUE)

resolution_fixture <- function() {
  ids <- paste0("NEON.PLA.D01.HARV.00001", c("", "A"))
  a <- data.frame(uid = c("measurement1", "measurement2"), plotID = "HARV_033",
    eventID = "vst_HARV_2022", individualID = ids, growthForm = "multi-bole tree",
    plantStatus = "Live", subplotID = "21_400", height = c(20, NA), breakHeight = NA_real_,
    stemDiameter = c(30, 15), dataQF = NA_character_, target_population = TRUE,
    reference_eligible = c(TRUE, FALSE), reference_selected = c(TRUE, FALSE),
    subplot_conflict = FALSE, exclusion = c("", "missing_mapping_coordinates"),
    E = c(500010, NA), N = c(4700010, NA), pos_unc = c(0.8, NA))
  mt <- data.frame(uid = c("mapping1", "mapping2"), recordType = c("map and tag", "tag only"),
    plotID = a$plotID, individualID = ids, date = "2023-07-01", namedLocation = "HARV_033.basePlot.vst",
    pointID = c("21", NA), stemDistance = c(sqrt(200), NA), stemAzimuth = c(45, NA),
    supportingStemIndividualID = NA_character_, dataQF = NA_character_)
  g <- sf::st_as_sfc(sf::st_bbox(c(xmin = 500000, ymin = 4700000,
                                  xmax = 500020, ymax = 4700020), crs = 32618))
  b <- list(plot = "HARV_033", event = "vst_HARV_2022", epsg = 32618,
    references = a, subplots = sf::st_sf(subplotID = "21_400", geometry = g),
    blockers = c("incomplete_target_references", "datum_review_pending"), evaluation_ready = FALSE)
  list(a = a, mt = mt, bundles = setNames(list(b), "HARV_033::vst_HARV_2022"))
}

resolve_fixture <- function(f) neon_reference_resolution(f$a, f$mt, f$bundles)

test_that("only documented permanent multi-bole IDs define a family", {
  x <- neon_bole_identity(c("NEON.PLA.D01.HARV.00001A", "NEON.PLA.D01.HARV.00001A",
                           "TEMP.PLA.HARV.2022.001", "unknownA", NA),
                         c("multi-bole tree", "single bole tree", "multi-bole tree",
                           "multi-bole tree", "multi-bole tree"))
  expect_equal(x$family_id[1:2], c("NEON.PLA.D01.HARV.00001", "NEON.PLA.D01.HARV.00001A"))
  expect_true(all(is.na(x$family_id[3:5])))
  expect_identical(x$secondary_bole, c(TRUE, FALSE, FALSE, FALSE, FALSE))
})

test_that("additional-bole explanations do not recover or admit per-bole references", {
  f <- resolution_fixture(); before <- serialize(f, NULL)
  x <- resolve_fixture(f)
  expect_equal(x$records$classification, "additional_bole_individual_measurements")
  expect_equal(x$records$height_evidence_ids, f$a$individualID[1])
  expect_equal(x$records$observed_missing_or_conflicting, "coordinates|uncertainty|height")
  expect_true(is.na(x$records$source_height))
  expect_false(any(x$plots$evaluation_ready))
  expect_false(any(x$records$source_values_changed))
  expect_identical(serialize(f, NULL), before)
  expect_equal(x$members[, names(f$a)], f$a)
})

test_that("family links require unique same-event and same-plot evidence", {
  f <- resolution_fixture(); f$a$plotID[1] <- "HARV_034"
  expect_equal(resolve_fixture(f)$records$family_relation, "missing_primary")
  f <- resolution_fixture(); f$a$eventID[1] <- "vst_HARV_2021"
  expect_equal(resolve_fixture(f)$records$family_relation, "missing_primary")
  f <- resolution_fixture(); f$a <- rbind(f$a, f$a[1, ])
  expect_equal(resolve_fixture(f)$records$family_relation, "ambiguous_primary")
  f <- resolution_fixture(); f$a$subplotID[1] <- "23_400"
  expect_equal(resolve_fixture(f)$records$family_relation, "inconsistent_subplots")
  f <- resolution_fixture(); f$a$dataQF[1] <- "measurementError"
  expect_equal(resolve_fixture(f)$records$classification, "unresolved_family_evidence")
  f <- resolution_fixture(); f$mt$dataQF[1] <- "multiPlotDuplicate"
  expect_equal(resolve_fixture(f)$records$family_relation, "quality_or_mapping_unresolved")
  f <- resolution_fixture(); f$a <- f$a[2, ]
  f$mt$supportingStemIndividualID[2] <- "NEON.PLA.D01.HARV.00001"
  expect_equal(resolve_fixture(f)$records$family_relation, "missing_primary")
})

test_that("broken primary boles retain evidence from relatives below the target DBH", {
  f <- resolution_fixture()
  f$a$height <- c(NA, 12); f$a$breakHeight[1] <- 5
  f$a$plantStatus[1] <- "Live, broken bole"
  f$a$reference_eligible[1] <- FALSE; f$a$exclusion[1] <- "invalid_height"
  f$a$stemDiameter[2] <- 8; f$a$target_population[2] <- FALSE
  x <- resolve_fixture(f)$records
  expect_equal(x$classification, "broken_primary_height_on_relative")
  expect_equal(x$height_evidence_dbh, "8")
  expect_equal(x$source_break_height, 5)
  expect_true(is.na(x$source_height))
  expect_false(x$evaluation_ready)
})

test_that("a dead primary with a live height-bearing secondary needs its own policy", {
  f <- resolution_fixture()
  f$a$plantStatus[1] <- "Dead, broken bole"; f$a$target_population[1] <- FALSE
  f$a$height <- c(NA, 14.5)
  x <- resolve_fixture(f)$records
  expect_equal(x$classification, "live_secondary_with_dead_primary")
  expect_equal(x$height_evidence_ids, f$a$individualID[2])
  expect_false(x$source_values_changed)
})

test_that("unknown uncertainty and small subplot discrepancies are not cleared", {
  f <- resolution_fixture(); f$a <- f$a[1, ]
  f$a$reference_eligible <- FALSE; f$a$pos_unc <- NA
  f$a$exclusion <- "missing_mapping_uncertainty"
  expect_equal(resolve_fixture(f)$records$classification, "unknown_anchor_uncertainty")
  f <- resolution_fixture(); f$a <- f$a[1, ]
  f$a$subplot_conflict <- TRUE; f$a$E <- 500020.85
  x <- resolve_fixture(f)$records
  expect_equal(x$distance_to_recorded_subplot_m, 0.85, tolerance = 1e-7)
  expect_equal(x$excess_over_margin_m, 0.05, tolerance = 1e-7)
  expect_equal(x$disposition, "unresolved_source_review")
  expect_false(x$evaluation_ready)
})

test_that("flight boundary lines form candidate interiors, not just boundary hits", {
  coords <- rbind(c(0, 0), c(20, 0), c(20, 20), c(0, 20), c(0, 0))
  lines <- sf::st_sfc(sf::st_multilinestring(list(coords)), crs = 32618)
  q <- neon_flight_enclosure(lines, 32618)
  expect_true(neon_support_inside(10, 10, q))
  expect_false(neon_support_inside(25, 10, q))
  expect_equal(as.numeric(sf::st_area(q)), 400)
  open <- sf::st_sfc(sf::st_linestring(coords[1:3, ]), crs = 32618)
  expect_error(suppressWarnings(neon_flight_enclosure(open, 32618)), "valid enclosure")
  id <- neon_flight_identity("NEON_D01_HARV_DPQA_L007-1_2022080412_boundary.kml")
  expect_equal(id$line, "L007-1")
  expect_equal(id$date, as.Date("2022-08-04"))
  expect_error(neon_flight_identity("unlabelled.kml"), "Unsupported")
})

test_that("week-time inference retains repeated weekdays and midnight ambiguity", {
  dates <- as.Date(c("2022-08-03", "2022-08-04", "2022-08-11", "2022-08-14"))
  expect_equal(neon_week_time_candidates(397530, dates, 18), dates[2:3])
  expect_equal(neon_week_time_candidates(4 * 86400 + 5, dates, 18), dates[1:3])
  expect_length(neon_week_time_candidates(c(3 * 86400 + 100, 4 * 86400 + 100), dates, 18), 0)
  expect_error(neon_week_time_candidates(604800, dates, 18), "week seconds")
  expect_error(neon_week_time_candidates(1, dates, NA_real_), "offset")
})

test_that("source attribution rejects zero, unknown, duplicate and incompatible IDs", {
  lines <- data.frame(file_source_id = 7, line = "L007-1", date = "2022-08-04", intersects_buffer = TRUE)
  expect_true(neon_link_flight_source(7, "2022-08-04", lines)$verified)
  expect_false(neon_link_flight_source(7, "2022-08-03", lines)$verified)
  expect_false(neon_link_flight_source(8, "2022-08-04", lines)$verified)
  expect_false(neon_link_flight_source(7, "2022-08-04", rbind(lines, lines))$verified)
  lines$file_source_id <- 0
  expect_false(neon_link_flight_source(0, "2022-08-04", lines)$verified)
  expect_false(neon_link_flight_source(7, "2022-08-04", lines)$verified)
  lines$file_source_id <- 7; lines$intersects_buffer <- FALSE
  expect_false(neon_link_flight_source(7, "2022-08-04", lines)$verified)
})

test_that("receipts reject changed and missing evidence", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  p <- file.path(d, "evidence.txt"); writeLines("source", p)
  receipt <- file.path(d, "receipt.json")
  # Two inputs exercise the JSON vector shape used by actual snapshots.
  q <- file.path(d, "second.txt"); writeLines("second", q)
  neon_check_manifest(receipt, list(files = c(p, q), md5 = unname(tools::md5sum(c(p, q)))))
  expect_equal(neon_verify_receipt(receipt), c(p, q))
  writeLines("changed", p)
  expect_error(neon_verify_receipt(receipt), "receipt failed")
  unlink(p)
  expect_error(neon_verify_receipt(receipt), "receipt failed")
})
