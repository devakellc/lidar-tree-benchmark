source(file.path("..", "..", "scripts", "neon_spatial_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "neon_acquisition_lib.R"), local = TRUE)

test_that("the tile client passes authentication to omitted and explicit query calls", {
  env <- new.env(parent = baseenv())
  env$getTileUrls <- function(..., token = NA_character_) token
  client <- function(..., token) c(getTileUrls("first"), getTileUrls("refresh", token = token))
  environment(client) <- env
  expect_equal(neon_by_tile_aop(token = "fixture-token", client = client), rep("fixture-token", 2))
  expect_identical(environment(client), env)
  expect_true(is.na(env$getTileUrls("original"))) # No namespace/global patch.
})

test_that("archived file metadata excludes signed URLs and detects changed identities", {
  d <- tempfile(); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  f <- data.frame(name = "tile.laz", size = 123L, md5 = "abc", url = "https://example.test/?secret=hidden")
  x <- list(productCode = "DP1.30003.001", siteCode = "HARV", month = "2022-08",
            release = "RELEASE-2026", files = f)
  path <- file.path(d, "listing.json")
  neon_archive_listing(x, path)
  expect_false(any(grepl("url|secret|hidden", readLines(path))))
  expect_silent(neon_archive_listing(x, path))
  x$files$md5 <- "changed"
  expect_error(neon_archive_listing(x, path), "differs")
})

test_that("coverage requires every tile across the buffered plot extent", {
  keys <- neon_required_tiles(500990, 4700990, 45)
  expect_setequal(keys, c("500000_4700000", "501000_4700000", "500000_4701000", "501000_4701000"))
  pc <- data.frame(plotID = "HARV_001", plotType = "tower", easting = 500990, northing = 4700990)
  c <- data.frame(plot = "HARV_001", field_candidate = TRUE, lidar_coverage = "pending",
                  rgb_coverage = "pending", split_frozen = FALSE)
  tiles <- data.frame(key = keys)
  expect_true(eastern_tile_coverage(c, pc, tiles, tiles)$coverage_candidate)
  expect_false(eastern_tile_coverage(c, pc, tiles[-1, , drop = FALSE], tiles)$coverage_candidate)
  expect_false(eastern_tile_coverage(c, pc, tiles, tiles)$split_frozen)
  f <- data.frame(name = "NEON_D01_HARV_DP1_500000_4700000_classified_point_cloud_colorized.laz",
                  size = 1, md5 = "a")
  expect_equal(neon_tile_index(f, "DP1.30003.001")$key, "500000_4700000")
  f$name <- "2022_BART_6_316000_4874000_image.tif"
  expect_equal(neon_tile_index(f, "DP3.30010.001")$key, "316000_4874000")
  expect_error(neon_tile_index(rbind(f, f), "DP3.30010.001"), "duplicate")
})

test_that("actual extent checks do not fill catalog gaps with a bounding box", {
  skip_if_not_installed("sf")
  box <- function(a, b, crs = 32618) sf::st_as_sfc(sf::st_bbox(c(xmin = a, ymin = 0, xmax = b, ymax = 10), crs = crs))
  target <- box(0, 30)
  expect_false(neon_extent_covers(target, c(box(0, 10), box(20, 30))))
  expect_true(neon_extent_covers(target, c(box(0, 10), box(10, 30))))
  expect_false(neon_extent_covers(target, sf::st_sfc(crs = 32618)))
  expect_error(neon_extent_covers(target, box(0, 30, 32619)), "CRS")
})
