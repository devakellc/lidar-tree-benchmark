source(file.path("..", "..", "scripts", "teak_canopy_lib.R"))

test_that("manifest paths cannot escape or alias the archive", {
  for (p in c("../a", "/a", "a/../b", "a/./b", "a\\b", ""))
    expect_error(canopy_check_paths(p), "Unsafe")
  expect_error(canopy_check_paths(c("a", "a")), "duplicate")
  expect_silent(canopy_check_paths(c("nte/a.xml", "data.gpkg")))
})

test_that("publisher pixel edges project with a top-left origin", {
  r <- terra::rast(nrows = 100, ncols = 200, xmin = 1000, xmax = 1020,
                   ymin = 2000, ymax = 2010, crs = "EPSG:32611")
  b <- data.frame(xmin = 0, ymin = 20, xmax = 30, ymax = 40)
  p <- canopy_project_boxes(b, r)
  expect_equal(as.numeric(sf::st_bbox(p)), c(1000, 2006, 1003, 2008))
  expect_equal(as.numeric(sf::st_area(p)), 6)
  terra::crs(r) <- "EPSG:3857"
  expect_error(canopy_project_boxes(b, r), "UTM 11N")
})

test_that("XML identity, dimensions and malformed boxes are rejected", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  r <- terra::rast(nrows = 100, ncols = 100, nlyrs = 3, vals = 1,
                   crs = "EPSG:32611")
  rgb <- terra::writeRaster(r, file.path(d, "image.tif"))
  xml <- function(filename = "image.tif", width = 100, xmax = 30) {
    p <- file.path(d, "annotation.xml")
    writeLines(sprintf(paste0('<annotation><filename>%s</filename>',
      '<size><width>%s</width><height>100</height><depth>3</depth></size>',
      '<object><name>Tree</name><bndbox><xmin>10</xmin><ymin>20</ymin>',
      '<xmax>%s</xmax><ymax>40</ymax></bndbox></object></annotation>'),
      filename, width, xmax), p)
    p
  }
  expect_equal(canopy_boxes(xml(), rgb)$xmax, 30)
  expect_error(canopy_boxes(xml(filename = "other.tif"), rgb), "identity")
  expect_error(canopy_boxes(xml(width = 99), rgb), "dimensions")
  expect_error(canopy_boxes(xml(xmax = 101), rgb), "Invalid")
  expect_error(canopy_boxes(xml(xmax = 9), rgb), "Invalid")
})

test_that("broken return metadata and background do not become valid native density", {
  p <- data.frame(X = 1:3, Y = 1:3, Z = c(0, 1, 20),
    ReturnNumber = c(1, 2, NA), NumberOfReturns = c(1, 1, 1),
    label = c(0, 8, NA))
  q <- canopy_point_quality(p, 10)
  expect_equal(q$n_points, 3)
  expect_equal(q$invalid_return_rows, 2)
  expect_equal(q$stored_point_count_per_rgb_m2, 0.3)
  expect_equal(q$zero_label_points, 1)
  expect_equal(q$missing_label_points, 1)
  expect_equal(q$positive_label_points, 1)
  expect_equal(q$unique_positive_labels, 1)
  expect_identical(q$xml_label_correspondence, "unknown")
  p$label <- c(8, 8, 42)
  expect_equal(canopy_point_quality(p, 10)$unique_positive_labels, 2)
  expect_true(is.na(q$native_frdens) && is.na(q$native_pdens))
  expect_error(canopy_point_quality(p, 0), "fields/area")
})

test_that("unknown local plot identity is not recast as unseen", {
  inv <- data.frame(plotID = c("TEAK_001", "TEAK_049"),
                    local_derived_evidence = c(TRUE, FALSE))
  expect_equal(canopy_plot_id(c("001", "TEAK_049", NA)),
               c("TEAK_001", "TEAK_049", NA))
  expect_equal(canopy_local_use(c("TEAK_001", "TEAK_049", "unknown"), inv),
    c("historical_use", "no_use_in_pinned_local_inventory", "not_in_local_inventory"))
  expect_error(canopy_local_use("TEAK_001", rbind(inv, inv)), "Invalid")
})

test_that("paired raster offsets retain unequal footprints", {
  rgb <- terra::rast(nrows = 400, ncols = 400, xmin = 1000.5, xmax = 1040.5,
    ymin = 2000.1, ymax = 2040.1, crs = "EPSG:32611")
  chm <- terra::rast(nrows = 40, ncols = 40, xmin = 1000, xmax = 1040,
    ymin = 2000, ymax = 2040, crs = "EPSG:32611")
  q <- canopy_raster_pair(rgb, chm)
  expect_equal(q$chm_epsg, 32611)
  expect_false(q$chm_extent_matches_rgb)
  expect_equal(q$chm_minus_rgb_xmin_m, -0.5)
  expect_equal(q$chm_minus_rgb_ymax_m, -0.1)
  expect_true(canopy_raster_pair(rgb, rgb)$chm_extent_matches_rgb)
})
