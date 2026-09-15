source(file.path("..", "..", "scripts", "neon_spatial_lib.R"), local = TRUE)

field_fixture <- function(zone = "18N", year = 2022L) {
  epsg <- neon_zone_epsg(zone)
  list(pc = data.frame(plotID = "HARV_001", plotType = "tower", easting = 732184,
                       northing = 4713266, utmZone = zone, epsg = epsg, datum = "WGS84"),
       gt = data.frame(plotID = "HARV_001", E = 732184, N = 4713266,
                       utmZone = zone, epsg = epsg, acquisition_year = year))
}

test_that("UTM parsing requires an unambiguous zone and hemisphere", {
  expect_equal(neon_zone_epsg(c("11N", "18n", "19N", "60S")), c(32611, 32618, 32619, 32760))
  expect_equal(neon_zone_epsg(c(18, 19), "N"), c(32618, 32619))
  for (bad in list(NA, "18", "0N", "61N", "18E", character()))
    expect_error(neon_zone_epsg(bad), "zone")
  expect_error(neon_zone_epsg(NA, "N"), "zone")
  expect_error(neon_zone_epsg("18N", "S"), "Conflicting")
  expect_error(neon_zone_epsg(18, NA), "hemisphere")
  expect_error(neon_zone_epsg(c(18, 19, 20), c("N", "S")), "hemisphere")
})

test_that("field metadata and spatial headers must agree", {
  f <- field_fixture()
  expect_equal(neon_validate_inputs(f$gt, f$pc, sf::st_crs(32618)), 32618)
  expect_error(neon_validate_inputs(f$gt, f$pc, sf::st_crs(32611)), "differs")
  for (bad in c(4326, 3857, 2276, NA))
    expect_error(neon_assert_crs(sf::st_crs(bad)), "projected metric")
  f$gt$epsg <- 32619
  expect_error(neon_validate_inputs(f$gt, f$pc), "Stem and plot")
  f <- field_fixture()
  f$pc <- rbind(f$pc, field_fixture("19N")$pc)
  expect_error(neon_field_epsg(f$pc), "Mixed")
  f <- field_fixture()
  f$pc$datum <- "NAD83"
  expect_error(neon_field_epsg(f$pc), "datum")
  f <- field_fixture()
  f$pc$utmZone <- NULL
  expect_error(neon_field_epsg(f$pc), "UTM")
  f <- field_fixture()
  expect_equal(neon_validate_inputs(f$gt[FALSE, ], f$pc), 32618)
})

test_that("cross-zone transformations preserve HARV and BART locations", {
  for (site in list(c(-72.17266, 42.53691, 32618), c(-71.28737, 44.06389, 32619))) {
    xy <- neon_transform_xy(site[1], site[2], 4326, site[3])
    other <- neon_transform_xy(xy[, 1], xy[, 2], site[3], 32611)
    back <- neon_transform_xy(other[, 1], other[, 2], 32611, site[3])
    ll <- neon_transform_xy(back[, 1], back[, 2], site[3], 4326)
    expect_equal(as.numeric(back), as.numeric(xy), tolerance = 1e-6)
    expect_equal(as.numeric(ll), site[1:2], tolerance = 1e-8)
    expect_gt(abs(other[1, 1] - xy[1, 1]), 1e6)
  }
})

test_that("reference selection follows acquisition year and preserves dist21", {
  ai <- data.frame(individualID = c("a", "a", "a", "b"),
                   date = c("2020-08-01", "2022-08-01", "2024-08-01", NA))
  chosen <- neon_nearest_measurements(ai, 2022)
  expect_equal(chosen$year, 2022L)
  expect_equal(chosen$dist_aop, 0)
  expect_equal(chosen$dist21, 1)
  legacy <- neon_nearest_measurements(ai, 2021)
  expect_equal(legacy$year, 2020L) # Stable original row order breaks equal gaps.
  for (bad in list(NA, "no", 2022.5, c(2021, 2022), 1900)) expect_error(neon_year(bad), "YEAR")
  f <- field_fixture()
  expect_silent(neon_reference_epoch(f$gt, 2022))
  expect_error(neon_reference_epoch(f$gt, 2021), "differ")
  f$gt$acquisition_year <- NULL
  expect_silent(neon_reference_epoch(f$gt, 2021))
  expect_error(neon_reference_epoch(f$gt, 2022), "lacks")
})

test_that("acquisition caches reject changed epoch, CRS and unversioned files", {
  d <- tempfile(); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  neon_acquisition_manifest(d, "DP1.30003.001", 2022, 32618)
  path <- file.path(d, "acquisition_manifest.json")
  before <- tools::md5sum(path)
  expect_silent(neon_acquisition_manifest(d, "DP1.30003.001", 2022, 32618))
  expect_error(neon_acquisition_manifest(d, "DP1.30003.001", 2021, 32618), "differs")
  expect_error(neon_acquisition_manifest(d, "DP1.30003.001", 2022, 32619), "differs")
  expect_error(neon_acquisition_manifest(d, "DP1.30003.001", 2022, 32618, TRUE), "differs")
  expect_identical(tools::md5sum(path), before)
  legacy <- file.path(d, "legacy"); dir.create(legacy)
  file.create(file.path(legacy, "old.LAZ"))
  expect_error(neon_acquisition_manifest(legacy, "DP1.30003.001", 2022, 32618), "Unversioned")
  expect_false(file.exists(file.path(legacy, "acquisition_manifest.json")))
  f <- field_fixture()
  expect_silent(neon_validate_acquisition(d, f$gt, f$pc, "DP1.30003.001"))
  expect_error(neon_validate_acquisition(legacy, f$gt, f$pc, "DP1.30003.001"), "Missing")
  expect_error(neon_validate_acquisition(d, f$gt, f$pc, "DP3.30010.001"), "disagrees")
})

test_that("missing tokens fail without exposing credentials", {
  withr::local_envvar(NEON_TOKEN = "")
  expect_error(neon_token(), "require NEON_TOKEN")
  Sys.setenv(NEON_TOKEN = " test-only-token ")
  expect_identical(neon_token(), "test-only-token")
})

test_that("LiDAR and RGB headers reject a mismatched site frame", {
  d <- tempfile(); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  las <- lidR::LAS(data.frame(X = c(732180, 732185), Y = c(4713260, 4713265), Z = c(1, 2)))
  sf::st_crs(las) <- 32618
  laz <- file.path(d, "test.laz"); lidR::writeLAS(las, laz)
  r <- terra::rast(nrows = 2, ncols = 2, xmin = 732180, xmax = 732190,
                   ymin = 4713260, ymax = 4713270, crs = "EPSG:32618", vals = 1:4)
  tif <- file.path(d, "test.tif"); terra::writeRaster(r, tif)
  expect_silent(neon_validate_files(c(laz, tif), 32618))
  expect_error(neon_validate_files(c(laz, tif), 32619), "differs")
  sf::st_crs(las) <- 32619
  wrong <- file.path(d, "wrong.laz"); lidR::writeLAS(las, wrong)
  f <- field_fixture()
  neon_acquisition_manifest(file.path(d, "lidar"), "DP1.30003.001", 2022, 32618)
  expect_error(neon_read_catalog(c(laz, wrong), f$gt, f$pc, file.path(d, "lidar")), "differs")
})
