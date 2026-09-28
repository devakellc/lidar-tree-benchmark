source(file.path("..", "..", "scripts", "neon_spatial_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "neon_reference_support_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "teak_reference_lib.R"), local = TRUE)

teak_fixture <- function() {
  plots <- teak_plots()
  pp <- data.frame(plotID = plots, eventID = "vst_TEAK_2022", date = "2022-06-30",
    namedLocation = paste0(plots, ".basePlot.vst"),
    subplotsSampled = "31_100|32_100|40_100|41_100", totalSampledAreaTrees = 400,
    samplingImpractical = "OK", dataCollected = "allGrowthForms",
    samplingProtocolVersion = "NEON.DOC.000987vJ", dataQF = NA_character_)
  ai <- data.frame(plotID = plots, individualID = paste0("tree", seq_along(plots)),
    date = "2022-07-01", eventID = pp$eventID, subplotID = "31_100",
    growthForm = "single bole tree", plantStatus = "Live", stemDiameter = 20,
    height = 15, canopyPosition = "Full sun", dataQF = NA_character_)
  ai$growthForm[1] <- "small shrub"; ai$stemDiameter[1] <- NA
  ai$height[2] <- NA
  mt <- data.frame(plotID = plots, individualID = ai$individualID, date = "2022-07-01",
    namedLocation = pp$namedLocation, pointID = "31", stemDistance = sqrt(50),
    stemAzimuth = 45, dataQF = NA_character_)
  points <- do.call(rbind, lapply(seq_along(plots), function(i) {
    grid <- expand.grid(row = 0:4, col = 0:4)
    data.frame(ptloc = paste0(plots[i], ".basePlot.vst.", 21 + grid$row * 9 + grid$col),
      easting = 320000 + i * 100 + grid$col * 10, northing = 4090000 + grid$row * 10,
      epsg = 32611L, unc = 0.2)
  }))
  list(dat = list(vst_perplotperyear = pp, vst_apparentindividual = ai,
                 vst_mappingandtagging = mt), points = points)
}

test_that("the fixed seven-event scope rejects missing and duplicate identities", {
  f <- teak_fixture()
  expect_equal(teak_events(f$dat)$plotID, teak_plots())
  missing <- f$dat; missing$vst_perplotperyear <- missing$vst_perplotperyear[-1, ]
  expect_error(teak_events(missing), "exactly one")
  duplicate <- f$dat; other <- duplicate$vst_perplotperyear[1, ]; other$eventID <- "other"
  duplicate$vst_perplotperyear <- rbind(duplicate$vst_perplotperyear, other)
  expect_error(teak_events(duplicate), "exactly one")
  f$dat$vst_perplotperyear$dataCollected[1] <- "dendrometerOnly"
  expect_equal(teak_events(f$dat)$plotID, teak_plots())
  b <- teak_build(f$dat, teak_events(f$dat), f$points, 32611L, list())
  expect_equal(b$summaries$status[1], "geometry_failed")
  expect_match(b$summaries$blockers[1], "Incomplete")
})

test_that("failed geometry and zero targets retain explicit seven-plot statuses", {
  f <- teak_fixture()
  f$points <- f$points[f$points$ptloc != "TEAK_010.basePlot.vst.31", ]
  b <- teak_build(f$dat, teak_events(f$dat), f$points, 32611L, list(test = TRUE))
  expect_equal(b$summaries$plot, teak_plots())
  expect_equal(b$summaries$status[3], "geometry_failed")
  expect_true(is.na(b$summaries$n_selected[3]))
  failed <- b$references[b$references$plotID == "TEAK_010", ]
  expect_true(all(is.na(failed$reference_selected)))
  expect_true(all(is.na(failed$inside_sampled)))
  expect_true(all(is.na(failed$subplot_conflict)))
  expect_equal(b$summaries$n_target[1], 0)
  expect_equal(b$summaries$n_selected[1], 0)
  expect_match(b$summaries$blockers[1], "empty_reference_interior")
  expect_match(b$summaries$blockers[2], "incomplete_target_references")
  expect_true(all(!b$summaries$evaluation_ready))
  expect_true(all(vapply(b$bundles, function(x) !x$evaluation_ready, logical(1))))
  expect_true(is.na(b$references$height[2]))
  expect_equal(b$references$exclusion[2], "invalid_height")
  expect_true(all(b$references$mapping_after_event))
  expect_true(all(!b$references$mapping_after_measurement))
  expect_error(score_neon_support(b$bundles[[1]], data.frame()), "diagnostic only")
})


test_that("malformed subplot scope retains all seven statuses", {
  f <- teak_fixture()
  f$dat$vst_perplotperyear$subplotsSampled[1] <- "bad"
  events <- teak_events(f$dat)
  expect_silent(teak_needed_locations(f$dat, events))
  b <- teak_build(f$dat, events, f$points, 32611L, list())
  expect_equal(b$summaries$plot, teak_plots())
  expect_equal(b$summaries$status, c("geometry_failed", rep("measured_corners_diagnostic", 6)))
  expect_match(b$summaries$blockers[1], "Unsupported")
})

teak_location_fixture <- function() {
  name <- "TEAK_004.basePlot.vst.31"
  h <- list(current = TRUE, locationStartDate = "2010-01-01T00:00:00Z", locationEndDate = NULL,
    locationUtmZone = 11, locationUtmHemisphere = "N", locationUtmEasting = 320000,
    locationUtmNorthing = 4090000, locationProperties = data.frame(
      locationPropertyName = c("Value for Geodetic datum", "Value for Coordinate uncertainty"),
      locationPropertyValue = c("WGS84", "0.2")))
  list(locationName = name, locationHistory = list(h))
}
teak_wrap_location <- function(loc) {
  body <- as.character(jsonlite::toJSON(list(data = loc), auto_unbox = TRUE, null = "null"))
  list(location = loc$locationName, url = teak_location_url(loc$locationName), status = 200L,
    response_body = body, response_sha256 = digest::digest(charToRaw(body), algo = "sha256", serialize = FALSE),
    data = loc)
}
teak_read_location <- function(rec, dates = "2022-06-30") {
  teak_location_row(rec, "TEAK_004.basePlot.vst.31", 32611L, dates)
}

test_that("replay uses verified raw history rather than mutable derived data", {
  r <- teak_wrap_location(teak_location_fixture())
  expect_equal(teak_read_location(r)$easting, 320000)
  r$data$locationHistory[[1]]$locationUtmEasting <- 320100
  expect_equal(teak_read_location(r)$easting, 320000)
  wrong <- r; wrong$response_sha256 <- "invalid"
  expect_error(teak_read_location(wrong), "SHA-256")
  wrong <- r; wrong$response_body <- paste0(wrong$response_body, " ")
  expect_error(teak_read_location(wrong), "SHA-256")
  wrong <- r; wrong$url <- sub("[?].*", "", wrong$url)
  expect_error(teak_read_location(wrong), "URL")
  wrong <- r; wrong$status <- 404L
  expect_error(teak_read_location(wrong), "Unsuccessful")
})

test_that("history identity frame uncertainty and epoch coverage fail closed", {
  loc <- teak_location_fixture()
  wrong <- loc; wrong$locationName <- "TEAK_005.basePlot.vst.31"
  rec <- teak_wrap_location(wrong); rec$location <- loc$locationName; rec$url <- teak_location_url(loc$locationName)
  expect_error(teak_read_location(rec), "Returned location identity")
  wrong <- loc; wrong$locationHistory[[1]]$locationUtmZone <- 10
  expect_error(teak_read_location(teak_wrap_location(wrong)), "CRS")
  wrong <- loc; wrong$locationHistory[[1]]$locationProperties$locationPropertyValue[2] <- NA
  expect_error(teak_read_location(teak_wrap_location(wrong)), "uncertainty")
  wrong <- loc; wrong$locationHistory <- NULL
  expect_error(teak_read_location(teak_wrap_location(wrong)), "Missing location history")
  wrong <- loc; wrong$locationHistory[[2]] <- wrong$locationHistory[[1]]
  expect_error(teak_read_location(teak_wrap_location(wrong)), "ambiguous")
  wrong <- loc; wrong$locationHistory[[1]]$locationStartDate <- "2023-01-01T00:00:00Z"
  expect_error(teak_read_location(teak_wrap_location(wrong)), "field epoch")
  wrong <- loc; wrong$locationHistory[[1]]$locationStartDate <- "2022-06-30T12:00:00Z"
  expect_error(teak_read_location(teak_wrap_location(wrong)), "field epoch")
})

test_that("surveyed history at all required epochs must agree", {
  loc <- teak_location_fixture()
  old <- loc$locationHistory[[1]]
  old$current <- FALSE; old$locationEndDate <- "2022-07-01T00:00:00Z"
  loc$locationHistory[[1]]$locationStartDate <- old$locationEndDate
  loc$locationHistory[[2]] <- old
  loc$locationUtmEasting <- 999999
  expect_equal(teak_read_location(teak_wrap_location(loc))$easting, 320000)
  expect_equal(teak_read_location(teak_wrap_location(loc), c("2022-06-30", "2022-07-01"))$history_indices, "2|1")
  loc$locationHistory[[1]]$locationUtmEasting <- 320001
  expect_error(teak_read_location(teak_wrap_location(loc), c("2022-06-30", "2022-07-01")), "differ across")
  f <- teak_fixture()
  expect_equal(teak_location_dates(f$dat, teak_events(f$dat), "TEAK_004.basePlot.vst.31"),
               c("2022-06-30", "2022-07-01"))
})
