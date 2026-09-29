source(file.path("..", "..", "scripts", "teak_native_pilot_lib.R"))

pilot_fixture <- function() data.frame(X = c(0, 10, 20), Y = c(0, 10, 20),
  Z = c(100, 110, 120), ReturnNumber = c(1L, 2L, 1L),
  NumberOfReturns = c(1L, 2L, 2L), PointSourceID = c(12L, 13L, 14L),
  gpstime = c(411275, 411691, 412087), Classification = c(2L, 5L, 7L),
  Withheld_flag = FALSE, pilot_row = 0:2)

test_that("duplicate coordinate tuples never acquire arbitrary native identities", {
  p <- pilot_fixture()
  n <- rbind(p, p[1, ])
  c <- pilot_point_correspondence(p, n)
  expect_equal(c$status, c("ambiguous_duplicate_tuple", rep("unique_coordinate_tuple", 2)))
  expect_true(is.na(c$native_context_row[1]))
  expect_equal(c$native_context_row[2:3], 1:2)
  pub <- rbind(p, p[2, ]); pub$X[3] <- 99
  c <- pilot_point_correspondence(pub, p)
  expect_equal(c$status, c("unique_coordinate_tuple", "ambiguous_duplicate_tuple",
                           "unmatched", "ambiguous_duplicate_tuple"))
  expect_true(all(is.na(c$native_context_row[-1])))
})

test_that("all-return and first-return density preserve zero cells and outer boundaries", {
  p <- pilot_fixture()
  d <- pilot_density(p, c(0, 20, 0, 20), "context")
  expect_equal(d$n_points, 3)
  expect_equal(d$frdens, 2 / 400)
  expect_equal(d$pdens, 3 / 400)
  expect_equal(d$noise_class7, 1)
  g <- pilot_density_grid(p, c(0, 20, 0, 20))
  expect_equal(nrow(g), 4)
  expect_equal(sum(g$n_points), 3)
  expect_equal(sum(g$first_returns), 2)
  expect_equal(sum(g$n_points == 0), 2)
  expect_error(pilot_density_grid(p, c(0, 19, 0, 20)), "completely cover")
})

test_that("native fields and normalization row preservation fail closed", {
  p <- pilot_fixture()
  expect_silent(pilot_return_checks(p))
  broken <- p; broken$NumberOfReturns[2] <- 1
  expect_error(pilot_return_checks(broken), "return fields")
  broken <- p; broken$gpstime[2] <- NA
  expect_error(pilot_return_checks(broken), "native point fields")
  n <- p; n$Z <- c(0, 10, -5)
  expect_silent(pilot_preserved(p, n)) # Retain negative and noise-class heights.
  expect_error(pilot_preserved(p, n[3:1, ]), "order or non-height")
  expect_error(pilot_preserved(p, n[-1, ]), "rows or source fields")
  n$Z[1] <- NA
  expect_error(pilot_preserved(p, n), "unknown heights")
  n <- p; n$Z[1] <- n$Z[1] + .002
  expect_error(pilot_preserved(p, n, .001), "LAS precision")
})

test_that("CHM values and missingness discrepancies are retained", {
  p <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2,
                   ymin = 0, ymax = 2, crs = "EPSG:32611", vals = c(0, 10, NA, 5))
  n <- p; terra::values(n) <- c(0, 20, 0, 5)
  d <- pilot_compare_chm(p, n)
  expect_equal(d$valid_pairs, 3)
  expect_equal(d$equal_values, 2)
  expect_equal(d$missingness_disagreements, 1)
  expect_equal(d$max_abs_difference_m, 10)
  expect_false(d$identical_values)
})


test_that("normalization exports original elevations and preserves every source field", {
  p <- data.frame(X = c(0, 10, 0, 10, 5, 6), Y = c(0, 0, 10, 10, 5, 6),
    Z = c(100, 100, 100, 100, 95, 110), Classification = c(2L, 2L, 2L, 2L, 7L, 9L))
  las <- lidR::LAS(p)
  las <- pilot_add_rows(las)
  before <- as.data.frame(las@data)
  normalized <- pilot_normalize(las)
  expect_equal(normalized$Z, c(0, 0, 0, 0, -5, 10))
  expect_identical(normalized$Zref, before$Z)
  path <- tempfile(fileext = ".laz")
  on.exit(unlink(path), add = TRUE)
  expect_silent(lidR::writeLAS(normalized, path))
  restored <- lidR::readLAS(path)
  expect_silent(pilot_preserved(as.data.frame(normalized@data),
                               as.data.frame(restored@data), .001))
  expect_identical(restored$Zref, before$Z)
  expect_equal(restored$Classification, p$Classification)
  expect_equal(restored$pilot_row, 0:5)
  expect_error(pilot_add_rows(las), "reserved pilot fields")
  collision <- lidR::add_lasattribute(lidR::LAS(p), p$Z, "Zref", "Existing source field")
  expect_error(pilot_add_rows(collision), "reserved pilot fields")
  expect_error(pilot_normalize(collision), "reserved pilot fields")
})


test_that("coordinate correspondence retains source-field disagreements without identity claims", {
  native <- pilot_fixture()
  published <- native
  published$NumberOfReturns[2] <- 1L
  published$Classification[3] <- 5L
  published$Z <- published$Z - 100
  published$gpstime[1] <- NA_real_
  published$Intensity <- 1L
  native$UserData <- 0L
  published <- rbind(published, published[1, ])
  crosswalk <- pilot_point_correspondence(published, native)
  d <- pilot_field_discrepancies(published, native, crosswalk)
  expect_equal(d$unique_tuple_pairs[d$field == "NumberOfReturns"], 2)
  expect_equal(d$differing_values[d$field == "NumberOfReturns"], 1)
  expect_equal(d$differing_values[d$field == "Classification"], 1)
  expect_equal(d$interpretation[d$field == "Z"], "different_height_frames")
  expect_false(d$native_present[d$field == "Intensity"])
  expect_false(d$published_present[d$field == "UserData"])
  expect_true(is.na(d$differing_values[d$field == "Intensity"]))
  expect_false("pilot_row" %in% d$field[!d$published_present])
})
