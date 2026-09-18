source(file.path("..", "..", "scripts", "neon_reference_support_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "neon_positional_evidence_lib.R"), local = TRUE)

test_that("true-north hypothesis uses ellipsoidal PROJ offsets without changing the grid recipe", {
  # At the equator/central meridian, UTM scale is 0.9996.
  n <- neon_offset_hypotheses(500000, 0, 10, 0, 32618)
  expect_equal(n$grid_E, 500000)
  expect_equal(n$grid_N, 10)
  expect_equal(n$true_north_E, 500000, tolerance = 1e-7)
  expect_equal(n$true_north_N, 9.996, tolerance = 1e-7)
  expect_equal(n$hypothesis_shift_m, 0.004, tolerance = 1e-7)
  e <- neon_offset_hypotheses(500000, 0, 10, 90, 32618)
  expect_equal(e$true_north_E - 500000, 9.996, tolerance = 1e-7)
  expect_equal(e$true_north_N, 0, tolerance = 1e-7)
  zero <- neon_offset_hypotheses(731000, 4713000, 0, 87.4, 32618)
  expect_lt(zero$hypothesis_shift_m, 1e-6)
  expect_false(n$correction_applied)
  expect_false(n$evaluation_ready)
  expect_error(neon_offset_hypotheses(500000, 0, 10, NA, 32618), "Invalid")
  expect_error(neon_offset_hypotheses(500000, 0, -1, 0, 32618), "Invalid")
  expect_error(neon_offset_hypotheses(500000, 0, 10, 0, 4326), "Invalid")
})

trajectory_fixture <- function() c("Sensors flown on 2022080412 as part of P3C1.",
  "Trajectory start time: 393613.0024", "Trajectory end time: 405306.0009")

test_that("trajectory text requires exact report identity and unique bounded times", {
  name <- "2022080412_P3C1_SBET_QAQC.pdf"
  x <- neon_trajectory_interval(trajectory_fixture(), name)
  expect_equal(x$date, "2022-08-04")
  expect_equal(x$start_week_seconds, 393613.0024)
  expect_equal(x$end_week_seconds, 405306.0009)
  expect_false(x$exact_flightline_verified)
  expect_error(neon_trajectory_interval(trajectory_fixture()[-2], name), "Missing or ambiguous")
  expect_error(neon_trajectory_interval(c(trajectory_fixture(), trajectory_fixture()[2]), name), "ambiguous")
  expect_error(neon_trajectory_interval(trajectory_fixture(), "2022080312_P3C1_SBET_QAQC.pdf"), "date mismatch")
  expect_error(neon_trajectory_interval(trajectory_fixture(), "unlabelled.pdf"), "identity")
  bad <- trajectory_fixture(); bad[3] <- "Trajectory end time: 604800.1"
  expect_error(neon_trajectory_interval(bad, name), "week-time")
  bad[3] <- "Trajectory end time: 123.4"
  expect_error(neon_trajectory_interval(bad, name), "week-time")
})

test_that("mission interval compatibility is not exact flightline attribution", {
  intervals <- neon_trajectory_interval(trajectory_fixture(), "2022080412_P3C1_SBET_QAQC.pdf")
  point <- data.frame(gps_week_min = 397530.4, gps_week_max = 397531.7, schedule_dates = "2022-08-04")
  x <- neon_trajectory_compatibility(intervals, point)
  expect_true(x$mission_interval_compatible)
  expect_false(x$exact_flightline_verified)
  point$schedule_dates <- "2022-08-11"
  expect_false(neon_trajectory_compatibility(intervals, point)$mission_interval_compatible)
  point$schedule_dates <- "2022-08-04"; point$gps_week_max <- 405307
  expect_false(neon_trajectory_compatibility(intervals, point)$mission_interval_compatible)
  point$gps_week_min <- NA_real_
  expect_error(neon_trajectory_compatibility(intervals, point), "Invalid")
})

test_that("named-point evidence preserves unknown uncertainty and datum limits", {
  p <- data.frame(locationPropertyName = c("Value for Coordinate source", "Value for Geodetic datum"),
                  locationPropertyValue = c("GIS", "WGS84"))
  record <- list(data = list(locationName = "BART_040.basePlot.vst.51", locationProperties = p))
  x <- neon_named_point_evidence(record)
  expect_equal(x$coordinate_source, "GIS")
  expect_equal(x$datum_label, "WGS84")
  expect_true(is.na(x$coordinate_uncertainty_m))
  expect_false(x$uncertainty_available)
  expect_false(x$epoch_property_present)
  expect_false(x$realization_property_present)
  expect_false(x$evaluation_ready)
  record$data$locationProperties <- rbind(p, data.frame(locationPropertyName = "Value for Coordinate uncertainty",
                                                       locationPropertyValue = "0.19"))
  expect_true(neon_named_point_evidence(record)$uncertainty_available)
  record$data$locationProperties$locationPropertyValue[3] <- "unknown"
  expect_false(neon_named_point_evidence(record)$uncertainty_available)
  record$data$locationProperties <- rbind(p, p[1, ])
  expect_error(neon_named_point_evidence(record), "Ambiguous")
  record$status <- 404L
  expect_error(neon_named_point_evidence(record), "Unavailable")
})
