# The Detectree2 arm's crop geometry, checked against the default grid of
# detectree2's tile_data (40 m tiles, 10 m buffer; tiles only where tile plus
# buffer fit inside the image). Only the crop helpers are loaded from the
# sweep script; nothing runs the model.
dt2_env <- function() {
  e <- new.env(parent = globalenv())
  exprs <- parse(file.path("..", "..", "scripts", "detect_detectree2_sweep.R"))
  # eval() runs only the named helper definitions parsed from this
  # repository's own sweep script (no external input), skipping its main body.
  for (x in exprs) {
    lhs <- if (is.call(x) && identical(x[[1]], as.name("<-"))) as.character(x[[2]]) else ""
    if (lhs %in% c("DT2_TILE", "DT2_BUFFER", "dt2_crop_half", "dt2_window")) eval(x, e)
  }
  e
}

# tile_data's grid: x starts at ceil(min) + buffer and steps by the tile width
# while below max - width - buffer; each tile's centre spans one tile width.
grid_cover <- function(lo, hi, width = 40, buffer = 10) {
  starts <- seq(ceiling(lo) + buffer, by = width, length.out = 1000)
  starts <- starts[starts < floor(hi - width - buffer)]
  if (!length(starts)) return(c(NA, NA))
  c(min(starts), max(starts) + width)
}

test_that("the crop puts tile centres over the whole plot core", {
  e <- dt2_env()
  for (ph in c(10, 20)) for (cx in c(255123.4, 300000, 4107580.7)) {
    h <- e$dt2_crop_half(ph)
    cov <- grid_cover(cx - h, cx + h)
    expect_false(anyNA(cov))
    expect_lte(cov[1], cx - ph)
    expect_gte(cov[2], cx + ph)
  }
  expect_equal(e$dt2_crop_half(10), 35)
  expect_equal(e$dt2_crop_half(20), 55)
  # The old crop (core plus 20 m) held no tile for a distributed plot.
  expect_true(anyNA(grid_cover(1000 - 30, 1000 + 30)))
})

test_that("a window across two RGB tiles is mosaicked, not cut off", {
  e <- dt2_env()
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  mk <- function(xmin, name) {
    r <- terra::rast(nrows = 10, ncols = 10, xmin = xmin, xmax = xmin + 10,
                     ymin = 0, ymax = 10, crs = "EPSG:32611", vals = xmin)
    f <- file.path(d, name); terra::writeRaster(r, f); f
  }
  tiles <- c(mk(0, "a.tif"), mk(10, "b.tif"))
  w <- e$dt2_window(tiles, 5, 15, 2, 8)
  expect_equal(as.vector(terra::ext(w)), c(xmin = 5, xmax = 15, ymin = 2, ymax = 8))
  expect_setequal(unique(as.vector(terra::values(w))), c(0, 10))
  expect_null(e$dt2_window(tiles, 50, 60, 2, 8))
})
