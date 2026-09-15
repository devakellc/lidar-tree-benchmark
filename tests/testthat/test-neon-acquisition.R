# Exercise the standalone entry points with local data and mocked API calls.
# No network, credentials or benchmark artifacts are used by these fixtures.
test_that("year-aware reference and bounded download entry points agree", {
  skip_if_not_installed("neonUtilities")
  root <- normalizePath(file.path("..", ".."))
  d <- tempfile(); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  withr::local_envvar(NEON_TOKEN = "fixture-token")
  nd <- file.path(d, "neon", "HARV")
  dir.create(file.path(nd, "vst"), recursive = TRUE)
  ids <- paste0("tree", 1:6)
  mapping <- data.frame(individualID = ids, plotID = "HARV_001",
    stemDistance = 1:6, stemAzimuth = 90, pointID = "point1",
    namedLocation = "HARV_001.basePlot.vst", taxonID = "ACRU", scientificName = "Acer rubrum")
  individuals <- data.frame(individualID = rep(ids, 2),
    date = rep(c("2021-08-01", "2022-08-01"), each = 6),
    height = rep(c(10, 20), each = 6), stemDiameter = 30, maxCrownDiameter = 5,
    ninetyCrownDiameter = 4, plantStatus = "Live", canopyPosition = "Full sun", growthForm = "tree")
  plots <- data.frame(plotID = "HARV_001", plotType = "tower",
    date = c("2021-08-01", "2022-08-01"), easting = c(500001, 500000),
    northing = 4700000, utmZone = "18N")
  saveRDS(list(vst_mappingandtagging = mapping, vst_apparentindividual = individuals,
               vst_perplotperyear = plots), file.path(nd, "vst", "harv_vst_allyears.rds"))
  e <- new.env(parent = globalenv())
  sys.source(file.path(root, "scripts", "neon_spatial_lib.R"), envir = e)
  e$.job_dir <- function() d
  e$.find <- function(file) file.path(root, "scripts", file)
  e$source <- function(...) invisible(NULL) # Helpers above replace entry-point bootstrap.
  e$commandArgs <- function(trailingOnly) if (trailingOnly)
    c("SITE=HARV", "YEAR=2022", "MAX_YEAR_GAP=0", "PLOTS=HARV_001") else character()
  e$fromJSON <- function(url) list(data = list(locationUtmZone = 18L,
    locationUtmHemisphere = "N", locationUtmEasting = 500000, locationUtmNorthing = 4700000,
    locationProperties = data.frame(locationPropertyName = "Value for Geodetic datum",
                                    locationPropertyValue = "WGS84")))
  expect_output(sys.source(file.path(root, "scripts", "neon_ground_truth.R"), envir = e),
                "6 geolocated stems; 6 live trees")
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"))
  pc <- read.csv(file.path(nd, "plot_centroids.csv"))
  expect_true(all(gt$meas_year == 2022 & gt$acquisition_year == 2022))
  expect_true(all(gt$dist_aop == 0 & gt$dist21 == 1 & gt$epsg == 32618))
  expect_equal(gt$height, rep(20, 6))
  expect_equal(pc$easting, 500000)
  expect_equal(pc$plot_meas_year, 2022)

  calls <- list()
  e$byTileAOP <- function(...) {
    a <- list(...); calls[[length(calls) + 1L]] <<- a
    if (a$dpID == "DP1.30003.001") {
      las <- lidR::LAS(data.frame(X = c(500000, 500001), Y = c(4700000, 4700001), Z = c(1, 2)))
      sf::st_crs(las) <- 32618
      lidR::writeLAS(las, file.path(a$savepath, "fixture.laz"))
    } else {
      r <- terra::rast(nrows = 2, ncols = 2, xmin = 500000, xmax = 500002,
                       ymin = 4700000, ymax = 4700002, crs = "EPSG:32618", vals = 1:4)
      terra::writeRaster(r, file.path(a$savepath, "fixture.tif"))
    }
  }
  for (script in c("neon_download_lidar.R", "neon_download_aop.R"))
    expect_output(sys.source(file.path(root, "scripts", script), envir = e), "downloaded 1")
  expect_length(calls, 2)
  for (call in calls) {
    expect_equal(call$year, 2022)
    expect_equal(call$easting, 500000) # Centre, not the six offset stem coordinates.
    expect_equal(call$northing, 4700000)
    expect_equal(call$buffer, 50)
    expect_identical(call$token, "fixture-token")
  }
  before <- tools::md5sum(file.path(nd, c("ground_truth_stems.csv", "plot_centroids.csv")))
  e$commandArgs <- function(trailingOnly) if (trailingOnly) c("SITE=HARV", "YEAR=2021") else character()
  expect_error(sys.source(file.path(root, "scripts", "neon_ground_truth.R"), envir = e), "differs")
  expect_identical(tools::md5sum(names(before)), before)
})
