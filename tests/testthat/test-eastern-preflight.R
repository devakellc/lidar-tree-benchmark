source(file.path("..", "..", "scripts", "neon_spatial_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "eastern_preflight_lib.R"), local = TRUE)

location_fixture <- function(zone) list(locationUtmZone = zone, locationUtmHemisphere = "N",
  locationProperties = data.frame(locationPropertyName = "Value for Geodetic datum",
                                  locationPropertyValue = "WGS84"))

metadata_fixture <- function() {
  p <- data.frame(dataProductCode = c("DP1.30003.001", "DP3.30010.001", "DP1.10098.001"))
  p$availableMonths <- list(c("2019-08", "2022-08", "2024-08"),
                           c("2019-08", "2022-08", "2024-08"), c("2022-07", "2022-08"))
  list(sites = list(HARV = list(dataProducts = p), BART = list(dataProducts = p)),
       locations = list(HARV = location_fixture(18), BART = location_fixture(19)))
}

test_that("metadata chooses earliest common AOP year without implying eligibility", {
  f <- metadata_fixture()
  inv <- eastern_inventory(f$sites, f$locations)
  expect_equal(inv$year, 2022L)
  expect_equal(inv$inventory$epsg, c(32618L, 32619L))
  expect_equal(inv$inventory$role, c("development", "held_out"))
  expect_true(all(is.na(inv$inventory$native_pdens)))
  expect_true(all(inv$inventory$leaf_on == "pending"))
  expect_false(any(inv$inventory$eligible_plots_frozen))
  f$sites$BART$dataProducts$availableMonths[[2]] <- "2024-08"
  expect_equal(eastern_inventory(f$sites, f$locations)$year, 2024L)
  f$sites$BART$dataProducts$availableMonths[[2]] <- "2025-08"
  expect_error(eastern_inventory(f$sites, f$locations), "No common")
})

test_that("missing products and location datum fail closed", {
  f <- metadata_fixture()
  f$sites$HARV$dataProducts <- f$sites$HARV$dataProducts[-1, ]
  expect_error(eastern_inventory(f$sites, f$locations), "Missing.*product")
  bad <- location_fixture(18)
  bad$locationProperties$locationPropertyValue <- "NAD83"
  expect_error(neon_location_frame(bad), "datum")
  bad$locationProperties <- NULL
  expect_error(neon_location_frame(bad), "datum")
})

test_that("field candidates require exact-year trees in known plot cores", {
  pc <- data.frame(plotID = c("HARV_002", "HARV_001", "HARV_003"),
    plotType = c("distributed", "tower", "unknown"), easting = 500000,
    northing = 4700000, utmZone = "18N")
  gt <- data.frame(plotID = rep(pc$plotID, each = 7), E = 500015, N = 4700000,
    height = 15, live = TRUE, is_tree = TRUE, meas_year = 2022L, acquisition_year = 2022L)
  gt$meas_year[8] <- 2021L
  candidates <- eastern_field_candidates(gt, pc, 2022)
  expect_equal(candidates$plot, c("HARV_001", "HARV_002", "HARV_003"))
  expect_equal(candidates$n_exact_core, c(6L, 0L, 0L))
  expect_equal(candidates$field_candidate, c(TRUE, FALSE, FALSE))
  expect_false(any(candidates$split_frozen))
  gt$height[9] <- NA
  expect_false(any(eastern_field_candidates(gt, pc, 2022)$field_candidate))
})
