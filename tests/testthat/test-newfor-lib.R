# Unit tests for the NEWFOR validation library: the five configurations and
# their pins, metadata and file checks, one area read from shapefiles, the
# reference flags, the clip over a sloping terrain raster and its covered area
# (the kept points' convex hull), densities and the resolution gate, the
# registration diagnostic, each admission rule, the freeze
# with its seal and read-back, the code hashes of a run record, the null's
# offsets and shifts, scoring on a
# polygon, and the detection wrapper with its package parity. Synthetic data
# only; nothing here reads the release.
suppressMessages({ library(lidR); library(data.table); library(sf); library(terra) })
source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "multichm_gated_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "newfor_lib.R"), local = TRUE)

## ---- a synthetic study area ------------------------------------------------------------------
# A projected frame (UTM 32N numbers), a plane terrain with a block of missing
# cells, a square scoring polygon (35 to 65 m on both axes) and a cloud that
# reaches 0 to 80 m east and 0 to 100 m north, so that it ends inside the
# clip's box on the east side.
SYN_X0 <- 600000; SYN_Y0 <- 5100000; SYN_EPSG <- 32632L
syn_terrain <- function(x, y) 1000 + 0.3 * (x - SYN_X0) + 0.2 * (y - SYN_Y0)
syn_square <- function(x0, y0, x1, y1, crs = SYN_EPSG)
  sf::st_sfc(sf::st_polygon(list(rbind(c(x0, y0), c(x1, y0), c(x1, y1), c(x0, y1), c(x0, y0)))),
             crs = crs)
SYN_AOI <- syn_square(SYN_X0 + 35, SYN_Y0 + 35, SYN_X0 + 65, SYN_Y0 + 65)
# Crowns; the last stands on the polygon's eastern edge.
SYN_TREES <- data.frame(x = c(40, 50, 60, 40, 50, 60, 45, 65),
                        y = c(40, 40, 40, 52, 52, 52, 61, 50),
                        h = c(18, 24, 21, 26, 19, 23, 20, 12))

# 1 m terrain raster without a CRS; cells centred 15.5 to 24.5 m east and 70.5
# to 79.5 m north have no value, so bilinear terrain is NA between their centres
# and defined one cell away from the block.
syn_dtm <- function() {
  r <- terra::rast(xmin = SYN_X0 - 10, xmax = SYN_X0 + 110, ymin = SYN_Y0 - 10,
                   ymax = SYN_Y0 + 110, resolution = 1, crs = "")
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  v <- syn_terrain(xy[, 1], xy[, 2])
  v[xy[, 1] > SYN_X0 + 15 & xy[, 1] < SYN_X0 + 25 & xy[, 2] > SYN_Y0 + 70 &
      xy[, 2] < SYN_Y0 + 80] <- NA
  terra::values(r) <- v
  r
}

# Points relative to the frame's origin with their true height above terrain
# (hgt) and the reason each would be dropped (why): a 2 m ground grid that
# keeps clear of the terrain gap, a cone per tree with its apex point and some
# second returns, and five points of each special kind inside the box.
syn_points <- function(seed = 1) {
  set.seed(seed)
  pt <- function(x, y, hgt, rn = 1L, nr = 1L, cls = 1L, wh = FALSE, why = "kept")
    data.frame(x = x, y = y, hgt = hgt, rn = rn, nr = nr, cls = cls, wh = wh, why = why,
               stringsAsFactors = FALSE)
  g <- expand.grid(x = seq(0, 80, 2), y = seq(0, 100, 2))
  g <- g[!(g$x >= 14 & g$x <= 26 & g$y >= 69 & g$y <= 81), ]
  cones <- do.call(rbind, lapply(seq_len(nrow(SYN_TREES)), function(i) {
    t <- SYN_TREES[i, ]
    d <- 2.5 * sqrt(runif(300)); a <- runif(300, 0, 2 * pi)
    d2 <- 2 * sqrt(runif(80)); a2 <- runif(80, 0, 2 * pi)
    rbind(pt(t$x + d * cos(a), t$y + d * sin(a), t$h * (1 - 0.6 * d / 2.5) - 0.05, nr = 2L),
          pt(t$x, t$y, t$h, nr = 2L),
          pt(t$x + d2 * cos(a2), t$y + d2 * sin(a2), runif(80, 2, 0.8 * t$h), rn = 2L, nr = 2L))
  }))
  rbind(pt(g$x, g$y, 0.05, cls = 2L), cones,
        pt(30:34, 20, 3, cls = 7L, why = "class"),
        pt(5, 50, 3, cls = 7L, why = "outside"),          # class 7 outside the box
        pt(70:73, 20, 4, wh = TRUE, why = "withheld"),
        pt(c(17, 19, 21, 23, 20, 18), c(72, 74, 76, 78, 75, 73), 1, why = "no_terrain"),
        pt(c(30, 40, 50), 85, -2, why = "below"),
        pt(c(30, 40), 88, 85, why = "above"))
}
# Coordinates are put on the 1 mm grid of the LAS first, so that the terrain
# under each stored point is the plane at its stored position. East of 50 m
# the scan angle is above 90 degrees, as in some clouds of the release.
syn_las <- function(p) {
  x <- round(SYN_X0 + p$x, 3); y <- round(SYN_Y0 + p$y, 3)
  df <- data.frame(X = x, Y = y, Z = syn_terrain(x, y) + p$hgt,
                   gpstime = as.numeric(seq_len(nrow(p))), ReturnNumber = p$rn,
                   NumberOfReturns = p$nr, Classification = p$cls, Withheld_flag = p$wh,
                   ScanAngleRank = ifelse(p$x > 50, 100L, -5L))
  suppressWarnings(suppressMessages(lidR::LAS(df)))
}

SYN_AREA <- data.frame(id = "91", forest = "Synthetic", sheet = "91_Metadata.pdf",
                       epsg = SYN_EPSG, field_date = "2012-06", flight_date = "2012-09",
                       caliper_cm = 7.5, gap_months = 3L, stringsAsFactors = FALSE)

# The inventory of the synthetic area: a stem below each crown's apex (the
# one on the polygon's eastern edge with DBHRef 0.10), one with DBHRef 0
# (missing), one below the 7.5 cm caliper and one outside the polygon.
syn_ref <- function() {
  data.frame(E = SYN_X0 + c(SYN_TREES$x, 45, 55, 80),
             N = SYN_Y0 + c(SYN_TREES$y, 45, 46, 80),
             DBHRef = c(0.31, 0.42, 0.36, 0.45, 0.30, 0.40, 0.33, 0.10, 0, 0.05, 0.25),
             HRef = c(SYN_TREES$h, 8, 6, 15),
             VolRef = c(0.9, 1.4, 1.1, 1.6, 0.8, 1.3, 1, 0.05, 0.02, 0.01, 0.4))
}

# A shapefile as the release ships them: without a .prj when the layer has no
# CRS (sf would write one for an undefined Cartesian system).
write_shp <- function(x, path) {
  sf::st_write(x, path, quiet = TRUE, delete_dsn = file.exists(path))
  if (is.na(sf::st_crs(x))) unlink(sub("\\.shp$", ".prj", path))
}

# Writes a release of the synthetic area into `dir`: cloud, terrain raster
# without a CRS, inventory and polygon shapefiles without a CRS (inventory
# fields in another order and case), the plot sheet; returns its pinned file
# list. aoi_crs gives the polygon shapefile a CRS.
syn_release <- function(dir, aoi_crs = NA) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  id <- SYN_AREA$id
  lidR::writeLAS(syn_las(syn_points()), file.path(dir, paste0(id, "_ALS.laz")))
  terra::writeRaster(syn_dtm(), file.path(dir, paste0(id, "_DTM.tif")))
  aoi <- sf::st_sf(id = 1L, geometry = sf::st_set_crs(sf::st_set_crs(SYN_AOI, NA), aoi_crs))
  write_shp(aoi, file.path(dir, paste0(id, "_AoI.shp")))
  r <- syn_ref()
  ref <- sf::st_sf(hRef = r$HRef, volref = r$VolRef, DBHREF = r$DBHRef,
                   geometry = sf::st_sfc(lapply(seq_len(nrow(r)), function(i)
                     sf::st_point(c(r$E[i], r$N[i])))))
  write_shp(ref, file.path(dir, paste0(id, "_Ref.shp")))
  writeLines("plot sheet", file.path(dir, SYN_AREA$sheet))
  fn <- newfor_area_files(id, SYN_AREA$sheet)
  p <- file.path(dir, fn)
  data.frame(filename = fn, id = seq_along(fn), bytes = file.size(p),
             md5 = unname(tools::md5sum(p)), sha256 = vapply(p, frozen_sha256, ""),
             stringsAsFactors = FALSE, row.names = NULL)
}

## ---- configurations --------------------------------------------------------------------------
test_that("the five configurations come in order with their pinned labels", {
  cfg <- newfor_configs()
  expect_identical(names(cfg), c("stock", "declared", "floor", "floor_exempt", "gate_all"))
  expect_identical(vapply(cfg, mcg_config_label, ""),
                   c(stock = "stock", declared = "z5_s0.75_c0.6_e1_d8", floor = "z5_s0_c0_e0",
                     floor_exempt = "z5_s0_c0.6_e1", gate_all = "z5_s0.75_c0.6_e1"))
  expect_identical(cfg$stock, MCG_STOCK)
  expect_identical(cfg$declared, MCG_DECLARED)
  # a floor alone has cover_min 0, and the library labels it z5_s0_c0_e0
  expect_identical(cfg$floor, mcg_config(zmin = 5))
  expect_identical(cfg$floor$cover_min, 0)
  expect_identical(cfg$gate_all$spacing_min, 0)
})

test_that("a changed pin of the detector library fails loudly", {
  # the same function evaluated where MCG_DECLARED, MCG_STOCK or the labels differ
  with_pin <- function(...) {
    e <- list2env(list(...), parent = environment(newfor_configs))
    f <- newfor_configs; environment(f) <- e
    f
  }
  expect_error(with_pin(MCG_DECLARED = mcg_config(5, 0.75, 0.7, TRUE, 8))(), "MCG_DECLARED")
  expect_error(with_pin(MCG_STOCK = mcg_config(zmin = 1))(), "MCG_STOCK")
  expect_error(with_pin(mcg_config_label = function(cfg) "x")(), "not the pinned")
})

## ---- metadata and files ----------------------------------------------------------------------
meta_json <- function(areas, release = list(doi = "10.0/x", version = "1.0")) {
  f <- tempfile(fileext = ".json")
  jsonlite::write_json(list(release = release, areas = areas), f, auto_unbox = TRUE, digits = NA)
  f
}
META_AREAS <- data.frame(id = c("01", "02"), forest = c("A", "B"),
                         sheet = c("01_M.pdf", "02_M.pdf"),
                         epsg = c(2154, 32632), field_date = c("2010-07", "2012-11"),
                         flight_date = c("2010-09", "2012-07"), caliper_cm = c(7.5, 4),
                         notes = c("x", "y"), stringsAsFactors = FALSE)

test_that("metadata keep ids as strings and gain the flight-minus-field gap in months", {
  f <- meta_json(META_AREAS); on.exit(unlink(f))
  m <- newfor_metadata(f)
  expect_identical(m$release$doi, "10.0/x")
  expect_identical(m$areas$id, c("01", "02"))
  expect_identical(m$areas$epsg, c(2154L, 32632L))
  expect_identical(m$areas$gap_months, c(2L, -4L))
  expect_identical(m$areas$notes, c("x", "y"))
  a <- META_AREAS; a$field_date <- c("2008-11", "2013-08"); a$flight_date <- c("2009-10", "2012-09")
  f2 <- meta_json(a); on.exit(unlink(f2), add = TRUE)
  expect_identical(newfor_metadata(f2)$areas$gap_months, c(11L, -11L))
})

test_that("metadata validation stops on each kind of bad record", {
  bad <- function(mutate, msg, release = list(doi = "d", version = "1")) {
    a <- META_AREAS; a <- mutate(a)
    f <- meta_json(a, release); on.exit(unlink(f))
    expect_error(newfor_metadata(f), msg)
  }
  bad(function(a) { a$id[2] <- "01"; a }, "duplicate area ids: 01")
  bad(function(a) { a$caliper_cm <- NULL; a }, "lack caliper_cm")
  bad(function(a) { a$sheet <- NULL; a }, "lack sheet")
  bad(function(a) { a$epsg[1] <- 2154.5; a }, "epsg must be a positive whole number")
  bad(function(a) { a$epsg[1] <- -1; a }, "epsg must be a positive whole number")
  bad(function(a) { a$caliper_cm[2] <- 0; a }, "caliper_cm must be positive")
  bad(function(a) { a$field_date[1] <- "2010-7"; a }, "field_date must be YYYY-MM")
  bad(function(a) { a$flight_date[2] <- "2012-13"; a }, "flight_date must be YYYY-MM")
  bad(function(a) { a$id <- c(1, 2); a }, "ids must be non-empty strings")
  bad(function(a) a, "doi and version", release = list(doi = "d"))
  expect_error(newfor_metadata(tempfile()), "not found")
})

test_that("the file list, an area's nine files and the raw verification", {
  expect_identical(newfor_area_files("15", "15-18_Metadata.pdf"),
                   c("15_ALS.laz", "15_DTM.tif", "15_Ref.shp", "15_Ref.shx", "15_Ref.dbf",
                     "15_AoI.shp", "15_AoI.shx", "15_AoI.dbf", "15-18_Metadata.pdf"))
  dir <- tempfile(); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))
  writeLines("aaa", file.path(dir, "a.txt")); writeLines("bbb", file.path(dir, "b.txt"))
  p <- file.path(dir, c("a.txt", "b.txt"))
  pinned <- data.frame(filename = c("a.txt", "b.txt", "c.txt"), id = 1:3,
                       bytes = c(file.size(p), 9),
                       md5 = toupper(c(tools::md5sum(p), strrep("0", 32))),
                       sha256 = c(vapply(p, frozen_sha256, ""), strrep("1", 64)))
  lst <- file.path(dir, "files.json")
  jsonlite::write_json(list(n_files = 3, files = pinned), lst, auto_unbox = TRUE, digits = NA)
  files <- newfor_release_files(lst)
  expect_identical(names(files), c("filename", "id", "bytes", "md5", "sha256"))
  expect_identical(files$md5, tolower(pinned$md5))                 # case-insensitive MD5
  v <- newfor_verify_raw(dir, files)
  expect_identical(names(v), c("filename", "present", "bytes_ok", "md5_ok", "sha256_ok"))
  expect_identical(v$present, c(TRUE, TRUE, FALSE))
  expect_identical(v$md5_ok, c(TRUE, TRUE, FALSE))
  expect_identical(v$sha256_ok, c(TRUE, TRUE, FALSE))
  expect_identical(v$bytes_ok, c(TRUE, TRUE, FALSE))
  writeLines("abb", file.path(dir, "b.txt"))                       # same size, other bytes
  v <- newfor_verify_raw(dir, files)
  expect_identical(v$bytes_ok, c(TRUE, TRUE, FALSE))
  expect_identical(v$md5_ok, c(TRUE, FALSE, FALSE))
  expect_identical(v$sha256_ok, c(TRUE, FALSE, FALSE))
  jsonlite::write_json(list(n_files = 4, files = pinned), lst, auto_unbox = TRUE, digits = NA)
  expect_error(newfor_release_files(lst), "says n_files = 4")
  jsonlite::write_json(list(files = pinned[c(1, 1), ]), lst, auto_unbox = TRUE, digits = NA)
  expect_error(newfor_release_files(lst), "duplicate file names")
})

## ---- reading one area and its reference ------------------------------------------------------
test_that("an area reads with fields in any order and case and its CRS assigned", {
  dir <- tempfile(); on.exit(unlink(dir, recursive = TRUE))
  syn_release(dir)
  rd <- newfor_read_area(dir, SYN_AREA)
  expect_identical(names(rd), c("aoi", "ref", "las_file", "dtm_file"))
  expect_s3_class(rd$aoi, "sfc")
  expect_length(rd$aoi, 1L)
  expect_true(sf::st_crs(rd$aoi) == sf::st_crs(SYN_EPSG))
  expect_equal(as.numeric(sf::st_area(rd$aoi)), 900)
  expect_identical(names(rd$ref), c("row", "E", "N", "dbh_m", "dbh_cm", "height", "vol"))
  r <- syn_ref()
  expect_identical(rd$ref$row, seq_len(nrow(r)))
  expect_equal(rd$ref$E, r$E); expect_equal(rd$ref$N, r$N)
  expect_equal(rd$ref$dbh_m, r$DBHRef); expect_equal(rd$ref$height, r$HRef)
  expect_equal(rd$ref$vol, r$VolRef)
  expect_identical(rd$ref$dbh_cm, round(100 * rd$ref$dbh_m, 6))     # metres to centimetres
  expect_identical(rd$ref$dbh_cm[8], 10)
  expect_identical(basename(c(rd$las_file, rd$dtm_file)), c("91_ALS.laz", "91_DTM.tif"))
})

test_that("a shapefile with another CRS or without DBHRef or HRef stops", {
  dir <- tempfile(); on.exit(unlink(dir, recursive = TRUE))
  syn_release(dir, aoi_crs = 32633L)
  expect_error(newfor_read_area(dir, SYN_AREA), "91_AoI.shp carries a CRS other than EPSG:32632")
  unlink(dir, recursive = TRUE)
  syn_release(dir, aoi_crs = SYN_EPSG)                               # the same CRS is accepted
  expect_true(sf::st_crs(newfor_read_area(dir, SYN_AREA)$aoi) == sf::st_crs(SYN_EPSG))
  ref <- sf::st_sf(HRef = 10, VolRef = 1, geometry = sf::st_sfc(sf::st_point(c(SYN_X0 + 50,
                                                                              SYN_Y0 + 50))))
  write_shp(ref, file.path(dir, "91_Ref.shp"))
  expect_error(newfor_read_area(dir, SYN_AREA), "91_Ref.shp has no field DBHRef")
  ref <- sf::st_sf(DBHRef = 0.2, geometry = sf::st_geometry(ref))
  write_shp(ref, file.path(dir, "91_Ref.shp"))
  expect_error(newfor_read_area(dir, SYN_AREA), "91_Ref.shp has no field HRef")
  ref <- sf::st_sf(DBHRef = 0.2, HRef = 12, geometry = sf::st_geometry(ref))  # no VolRef: NA
  write_shp(ref, file.path(dir, "91_Ref.shp"))
  expect_identical(newfor_read_area(dir, SYN_AREA)$ref$vol, NA_real_)
})

test_that("reference flags: the boundary is inside, 0.10 m is primary, 0 is missing", {
  aoi <- syn_square(0, 0, 20, 20)
  ref <- data.frame(row = 1:9,
                    E = c(20, 5, 5, 10, 10, 15, 25, 12, 8),
                    N = c(10, 5, 15, 10, 4, 15, 10, 0, 8),
                    dbh_m = c(0.10, 0.0999994, 0, NA, 0.064, 0.30, 0.30, 0.20, 0.25),
                    height = c(12, 11, 9, 7, 5, NA, 20, 0, 18), vol = NA_real_)
  ref$dbh_cm <- round(100 * ref$dbh_m, 6)
  out <- newfor_reference(ref, aoi, caliper_cm = 7.5)
  # stem 1 on the eastern edge and stem 8 on the southern edge are inside; stem 7 is outside
  expect_identical(out$inside, c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE))
  # 0.0999994 m is 9.99994 cm: under 10 cm, over the caliper less 0.5 cm
  expect_identical(out$dbh_status, c("ok", "ok", "missing", "missing", "below_caliper", "ok", "ok",
                                     "ok", "ok"))
  expect_identical(out$has_height, c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, FALSE, TRUE))
  expect_identical(out$primary, c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE))
  expect_identical(out$inventoried, c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE))
  # the caliper threshold: below it less 0.5 cm, and not at it
  r2 <- data.frame(E = 5, N = 5, dbh_cm = c(6.99, 7, 3.4, 3.5), height = 5)
  expect_identical(newfor_reference(r2, aoi, 7.5)$dbh_status[1:2], c("below_caliper", "ok"))
  expect_identical(newfor_reference(r2, aoi, 4)$dbh_status[3:4], c("below_caliper", "ok"))
  expect_identical(newfor_stems(out)$E, c(20, 8))
  expect_identical(newfor_stems(out, "inventoried")$E, c(20, 5, 5, 10, 10, 8))
  expect_identical(names(newfor_stems(out)), c("E", "N", "height", "crown_class"))
  expect_true(all(is.na(newfor_stems(out)$crown_class)))
  expect_identical(nrow(newfor_stems(out[0, ])), 0L)
})

## ---- clip and density ------------------------------------------------------------------------
test_that("the clip over a sloping terrain recovers heights and counts every drop", {
  p <- syn_points()
  las <- syn_las(p)
  cl <- newfor_clip(las, syn_dtm(), SYN_AOI, SYN_EPSG)
  expect_identical(names(cl), c("las", "box", "clip", "reach", "covered_area", "clip_area",
                                "n_box", "dropped", "terrain_na_share"))
  # the polygon's box (35 to 65 m) widened by 25 m; the cloud ends at 80 m east
  expect_equal(cl$box, c(xmin = SYN_X0 + 10, ymin = SYN_Y0 + 10, xmax = SYN_X0 + 90,
                         ymax = SYN_Y0 + 90))
  expect_equal(cl$clip, c(xmin = SYN_X0 + 10, ymin = SYN_Y0 + 10, xmax = SYN_X0 + 80,
                          ymax = SYN_Y0 + 90))
  expect_identical(cl$reach, c(west = 25, south = 25, east = 15, north = 25))
  expect_identical(cl$clip_area, 70 * 80)
  # the kept ground grid fills the clip, so its convex hull is the clip rectangle
  expect_identical(cl$covered_area, 70 * 80)
  expect_identical(cl$covered_area, newfor_covered_area(cl$las$X, cl$las$Y))
  in_box <- p$x >= 10 & p$x <= 90 & p$y >= 10 & p$y <= 90
  expect_identical(cl$n_box, sum(in_box))
  expect_identical(cl$dropped, c(class = 5L, withheld = 4L, no_terrain = 6L, below = 3L,
                                 above = 2L))
  expect_identical(cl$terrain_na_share, 6 / sum(in_box))
  keep <- which(in_box & p$why == "kept")
  expect_identical(lidR::npoints(cl$las), length(keep))
  # canonical order: by gpstime, which is the point's row in p
  expect_identical(as.integer(cl$las$gpstime), keep)
  scale <- cl$las@header@PHB[["Z scale factor"]]
  expect_lte(max(abs(cl$las$Z - p$hgt[keep])), scale + 1e-9)       # heights within the LAS scale
  expect_identical(cl$las$X, las$X[keep]); expect_identical(cl$las$Y, las$Y[keep])
  expect_identical(sf::st_crs(cl$las)$epsg, SYN_EPSG)
  expect_identical(cl$las@header@PHB[["Number of point records"]], length(keep))
  # the header is valid for writing, and the file reads back unchanged
  f <- tempfile(fileext = ".laz"); on.exit(unlink(f))
  lidR::writeLAS(cl$las, f)
  b <- suppressWarnings(lidR::readLAS(f))
  for (k in c("X", "Y", "Z", "ReturnNumber", "NumberOfReturns", "Classification",
              "ScanAngleRank"))
    expect_identical(b@data[[k]], cl$las@data[[k]])
  # the caller's cloud is untouched
  expect_identical(lidR::npoints(las), nrow(p))
  expect_identical(las$Z, syn_las(p)$Z)
})

test_that("a clip without withheld flags and one missing the box", {
  p <- syn_points()
  las <- syn_las(p)
  las@data[, Withheld_flag := NULL]
  cl <- newfor_clip(las, syn_dtm(), SYN_AOI, SYN_EPSG)
  expect_identical(cl$dropped[["withheld"]], 0L)
  expect_identical(lidR::npoints(cl$las), sum(p$x >= 10 & p$x <= 90 & p$y >= 10 & p$y <= 90 &
                                                p$why %in% c("kept", "withheld")))
  far <- syn_square(SYN_X0 + 500, SYN_Y0 + 500, SYN_X0 + 510, SYN_Y0 + 510)
  out <- newfor_clip(syn_las(p), syn_dtm(), far, SYN_EPSG)
  expect_identical(out$n_box, 0L)
  expect_identical(out$covered_area, 0)
  expect_identical(out$clip_area, 0)
  expect_true(lidR::is.empty(out$las))
  expect_true(is.na(out$terrain_na_share))
  expect_error(newfor_clip(syn_las(p[0, ]), syn_dtm(), SYN_AOI, SYN_EPSG), "no points")
})

test_that("the covered area is the convex hull's, exact at projected magnitudes", {
  # a 3 x 2 m rectangle with interior and edge points, at UTM magnitudes
  x <- SYN_X0 + c(0, 3, 3, 0, 1.5, 1, 3, 2.2)
  y <- SYN_Y0 + c(0, 0, 2, 2, 1, 0.5, 1, 2)
  expect_identical(newfor_covered_area(x, y), 6)
  # a right triangle with legs 0.123 and 0.456 m
  expect_identical(newfor_covered_area(SYN_X0 + c(0, 0.123, 0), SYN_Y0 + c(0, 0, 0.456)),
                   round(0.123 * 0.456 / 2, 6))
  # fewer than three points, or all on one line: no area
  expect_identical(newfor_covered_area(numeric(), numeric()), 0)
  expect_identical(newfor_covered_area(SYN_X0 + 1:2, SYN_Y0 + 1:2), 0)
  expect_identical(newfor_covered_area(SYN_X0 + 1:5, SYN_Y0 + 2 * (1:5)), 0)
})

# A plane terrain raster over the synthetic frame, without missing cells.
plane_dtm <- function() {
  r <- syn_dtm()
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  terra::values(r) <- syn_terrain(xy[, 1], xy[, 2])
  r
}

test_that("a disc-shaped cloud gets its density over its hull, not over the clip rectangle", {
  # 75,000 first returns uniform on a disc of radius 50 m that touches the four
  # sides of the 100 m box (a 50 m square polygon widened by 25 m): the true
  # density is 75000 / (pi 50^2) = 9.55 per m2; over the clip rectangle it would
  # be pi / 4 of that (7.5), about 21% low and below the resolution gate
  set.seed(4)
  n <- 75000L; R <- 50
  d <- R * sqrt(runif(n)); a <- runif(n, 0, 2 * pi)
  x <- round(SYN_X0 + 50 + d * cos(a), 3); y <- round(SYN_Y0 + 50 + d * sin(a), 3)
  las <- suppressMessages(lidR::LAS(data.frame(
    X = x, Y = y, Z = syn_terrain(x, y) + 10, gpstime = as.numeric(seq_len(n)), ReturnNumber = 1L,
    NumberOfReturns = 1L, Classification = 1L)))
  aoi <- syn_square(SYN_X0 + 25, SYN_Y0 + 25, SYN_X0 + 75, SYN_Y0 + 75)
  cl <- newfor_clip(las, plane_dtm(), aoi, SYN_EPSG)
  expect_identical(lidR::npoints(cl$las), n)
  truth <- n / (pi * R^2)
  dens <- newfor_density(cl$las, aoi, cl$covered_area)
  expect_lt(abs(dens$frdens_clip / truth - 1), 0.02)
  expect_identical(dens$pdens_clip, dens$frdens_clip)               # first returns only
  expect_gt(cl$clip_area, 0.99 * 100^2)
  rect <- newfor_density(cl$las, aoi, cl$clip_area)$frdens_clip
  expect_lt(rect / truth, 0.8)
  # the resolution follows the hull's density: 0.25 m, where the rectangle's
  # density would give 0.5 m
  expect_identical(newfor_res(dens$frdens_clip), 0.25)
  expect_identical(newfor_res(rect), 0.5)
  # the written clip and cell.json's 15 significant digits give the area back exactly
  f <- tempfile(fileext = ".laz"); on.exit(unlink(f))
  lidR::writeLAS(cl$las, f)
  back <- lidR::readLAS(f, select = "xy")
  expect_identical(newfor_covered_area(back$X, back$Y), cl$covered_area)
  j <- jsonlite::toJSON(list(covered_area = cl$covered_area), auto_unbox = TRUE, digits = NA)
  expect_identical(jsonlite::fromJSON(j)$covered_area, cl$covered_area)
  expect_false(cl$covered_area == round(cl$covered_area))           # not a trivial value
})

test_that("dropped points beyond the kept cloud widen the clip but not the covered area", {
  p <- syn_points()
  base <- newfor_clip(syn_las(p), syn_dtm(), SYN_AOI, SYN_EPSG)
  # a class-7 point and a point 85 m above the terrain, both in the box 8 to 9 m
  # east of where the kept cloud ends (80 m), both dropped
  extra <- data.frame(x = c(89, 88), y = c(12, 60), hgt = c(3, 85), rn = 1L, nr = 1L,
                      cls = c(7L, 1L), wh = FALSE, why = c("class", "above"),
                      stringsAsFactors = FALSE)
  cl <- newfor_clip(syn_las(rbind(p, extra)), syn_dtm(), SYN_AOI, SYN_EPSG)
  expect_identical(cl$dropped - base$dropped, c(class = 1L, withheld = 0L, no_terrain = 0L,
                                                below = 0L, above = 1L))
  expect_identical(lidR::npoints(cl$las), lidR::npoints(base$las))
  expect_identical(cl$covered_area, base$covered_area)
  # clip and reach still come from the raw cloud's range, dropped points included
  expect_identical(cl$reach[["east"]], 24)
  expect_identical(cl$clip_area, 79 * 80)
})

test_that("densities inside the polygon and over the clip; the resolution gate at exactly 8", {
  aoi <- syn_square(0, 0, 10, 10)
  # 30 first and 20 second returns inside (two of them on the boundary), 10 and 10 outside
  df <- data.frame(X = c(seq(0.5, 9.5, length.out = 48), 10, 0, rep(15, 20)),
                   Y = c(rep(5, 48), 3, 10, seq(1, 19, length.out = 20)),
                   Z = 5, ReturnNumber = c(rep(1L, 29), rep(2L, 20), 1L, rep(1:2, 10)))
  las <- suppressMessages(lidR::LAS(df))
  d <- newfor_density(las, aoi, covered_area = 400)
  expect_identical(names(d), c("n_aoi", "n_first_aoi", "aoi_area", "pdens_aoi", "frdens_aoi",
                               "n_clip", "n_first_clip", "pdens_clip", "frdens_clip"))
  expect_identical(c(d$n_aoi, d$n_first_aoi, d$n_clip, d$n_first_clip), c(50L, 30L, 70L, 40L))
  expect_equal(d$aoi_area, 100)
  expect_equal(c(d$pdens_aoi, d$frdens_aoi), c(0.5, 0.3))
  expect_equal(c(d$pdens_clip, d$frdens_clip), c(70 / 400, 40 / 400))
  expect_true(is.na(newfor_density(las, aoi, 0)$frdens_clip))
  las@data[, ReturnNumber := NULL]
  d <- newfor_density(las, aoi, 400)
  expect_identical(d$n_first_aoi, NA_integer_); expect_true(is.na(d$frdens_clip))
  expect_identical(d$n_aoi, 50L)
  expect_identical(newfor_res(8), 0.25)
  expect_identical(newfor_res(8 - 1e-12), 0.5)
  expect_identical(newfor_res(57.2), 0.25)
  expect_identical(newfor_res(c(7.99, 8, NA)), c(0.5, 0.25, NA))
})

## ---- registration ----------------------------------------------------------------------------
# Six crowns 15 m apart, each a cone whose single apex point sits at a cell
# centre of the 0.5 m canopy raster, and stems displaced by (-2.0, +1.5) m from
# the apexes, so that the canopy lies at the stems moved by (2.0, -1.5). A max
# filter of 1.5 m radius finds the same apex from every lattice offset within
# 1.5 m of the true one, so on cones alone the minimum is flat; a ring of taller
# returns 2 m from each apex (eight cells at 4 cells and 3 x sqrt(2) cells)
# breaks it, because every other offset of that disc brings a ring cell into
# the window.
REG_TREES <- data.frame(ax = SYN_X0 + c(20.25, 35.25, 50.25, 20.25, 35.25, 50.25),
                        ay = SYN_Y0 + c(20.25, 20.25, 20.25, 40.25, 40.25, 40.25),
                        h = c(18, 22, 25, 20, 24, 19))
REG_BOX <- c(xmin = SYN_X0, ymin = SYN_Y0, xmax = SYN_X0 + 70, ymax = SYN_Y0 + 60)
reg_cloud <- function(ring) {
  set.seed(3)
  crowns <- lapply(seq_len(nrow(REG_TREES)), function(i) {
    t <- REG_TREES[i, ]
    d <- 3 * sqrt(runif(800)); a <- runif(800, 0, 2 * pi)
    out <- rbind(data.frame(X = t$ax + d * cos(a), Y = t$ay + d * sin(a),
                            Z = t$h * (1 - 0.6 * d / 3) - 0.05),
                 data.frame(X = t$ax, Y = t$ay, Z = t$h))
    if (ring) out <- rbind(out, data.frame(X = t$ax + 0.5 * c(4, -4, 0, 0, 3, 3, -3, -3),
                                           Y = t$ay + 0.5 * c(0, 0, 4, -4, 3, -3, 3, -3),
                                           Z = t$h + 5))
    out
  })
  ground <- expand.grid(X = SYN_X0 + seq(0.25, 69.75, 0.5), Y = SYN_Y0 + seq(0.25, 59.75, 0.5))
  ground$Z <- 0
  df <- rbind(do.call(rbind, crowns), ground)
  df$ReturnNumber <- 1L
  # a later return above the first apex: only first returns build the canopy
  df <- rbind(df, data.frame(X = REG_TREES$ax[1] + 0.5, Y = REG_TREES$ay[1], Z = 60,
                             ReturnNumber = 2L))
  suppressMessages(lidR::LAS(df))
}
# Stems: one per crown, plus a shorter stem 3 m from the first, which is not
# locally dominant and takes no part in the statistic.
reg_stems <- function()
  data.frame(E = c(REG_TREES$ax - 2.0, REG_TREES$ax[1] + 1), N = c(REG_TREES$ay + 1.5,
                                                                  REG_TREES$ay[1] + 1.5),
             height = c(REG_TREES$h, 10))

test_that("the registration scan recovers a known offset of (2.0, -1.5)", {
  r <- newfor_registration(reg_cloud(ring = TRUE), reg_stems(), REG_BOX)
  expect_identical(names(r), c("dx", "dy", "offset", "stat_zero", "stat_best", "ratio",
                               "n_dominant", "scan"))
  expect_identical(c(r$dx, r$dy), c(2.0, -1.5))
  expect_identical(r$offset, 2.5)
  expect_identical(r$n_dominant, 6L)
  expect_lt(r$stat_best, 1e-9)                       # every dominant stem meets its own apex
  expect_gt(r$stat_zero, 1)
  expect_lt(r$ratio, 1e-9)
  # the scan: the 0.5 m lattice within +-8 m, dx outer, dy inner
  L <- seq(-8, 8, 0.5)
  expect_identical(nrow(r$scan), length(L) * length(L))
  expect_identical(r$scan$dx, rep(L, each = length(L)))
  expect_identical(r$scan$dy, rep(L, times = length(L)))
  expect_identical(sum(r$scan$stat < 0.01), 1L)      # a unique minimum
  expect_identical(r$scan$stat[r$scan$dx == 0 & r$scan$dy == 0], r$stat_zero)
})

test_that("a flat minimum resolves to the shortest offset; too few dominant stems give NA", {
  r <- newfor_registration(reg_cloud(ring = FALSE), reg_stems(), REG_BOX)
  # every lattice offset within 1.5 m of (2.0, -1.5) finds the apexes; (1.0, -0.5) is the
  # shortest of them (length^2 1.25; (0.5, -1.0) is 1.58 m from the true offset)
  expect_identical(r$scan$stat[r$scan$dx == 2 & r$scan$dy == -1.5], r$stat_best)
  expect_lt(r$stat_best, 1e-9)
  expect_identical(c(r$dx, r$dy), c(1.0, -0.5))
  tied <- r$scan[r$scan$stat <= r$stat_best + 1e-12, ]
  expect_true(all((tied$dx - 2)^2 + (tied$dy + 1.5)^2 <= 1.5^2 + 1e-9))
  expect_gt(nrow(tied), 20)
  # two dominant stems: no estimate
  r2 <- newfor_registration(reg_cloud(ring = TRUE), reg_stems()[1:2, ], REG_BOX)
  expect_identical(r2$n_dominant, 2L)
  expect_true(all(is.na(unlist(r2[c("dx", "dy", "offset", "stat_zero", "stat_best", "ratio")]))))
  expect_identical(nrow(r2$scan), 33L * 33L)
  expect_true(all(is.na(r2$scan$stat)))
  expect_identical(newfor_registration(reg_cloud(TRUE), reg_stems()[0, ], REG_BOX)$n_dominant, 0L)
})

## ---- admission -------------------------------------------------------------------------------
adm_inputs <- function() {
  las <- suppressMessages(lidR::LAS(data.frame(X = as.numeric(1:10), Y = as.numeric(1:10), Z = 1,
                                               ReturnNumber = rep(1:2, 5))))
  ref <- data.frame(inside = c(rep(TRUE, 7), FALSE), dbh_cm = c(rep(20, 6), 5, 30),
                    has_height = TRUE, dbh_status = c(rep("ok", 6), "below_caliper", "ok"),
                    stringsAsFactors = FALSE)
  ref$primary <- ref$inside & ref$dbh_cm >= 10
  ref$inventoried <- ref$inside
  list(area = SYN_AREA,
       verify = data.frame(filename = newfor_area_files("91", SYN_AREA$sheet), present = TRUE,
                           bytes_ok = TRUE, md5_ok = TRUE, sha256_ok = TRUE),
       clip = list(las = las, reach = c(west = 25, south = 25, east = 10, north = 25),
                   terrain_na_share = 0.0099),
       density = list(n_first_clip = 5L), ref = ref, reg = list(offset = 4.0))
}
adm <- function(x) do.call(newfor_admission, x)

test_that("the admission row has its columns, and passes at every rule's edge", {
  a <- adm(adm_inputs())
  expect_identical(names(a), c("area", "forest", "n_rows", "n_inside", "n_outside", "n_primary",
                               "n_inventoried", "n_missing_dbh", "n_below_caliper", "gap_months",
                               "reach_min", "terrain_na_share", "offset", .NEWFOR_RULES,
                               "admitted", "failed"))
  expect_identical(nrow(a), 1L)
  expect_true(a$admitted); expect_identical(a$failed, "")
  counts <- c("n_rows", "n_inside", "n_outside", "n_primary", "n_inventoried", "n_missing_dbh",
              "n_below_caliper", "gap_months")
  expect_identical(unlist(a[counts], use.names = FALSE),
                   c(8L, 7L, 1L, 6L, 7L, 0L, 1L, 3L))
  expect_identical(a$reach_min, 10); expect_identical(a$offset, 4)
  # a time gap of exactly four years, either way, passes
  for (g in c(48L, -48L)) {
    x <- adm_inputs(); x$area$gap_months <- g
    b <- adm(x)
    expect_true(b$rule_gap, info = as.character(g))
    expect_true(b$admitted, info = as.character(g))
    expect_identical(b$gap_months, g)
  }
})

test_that("each admission rule fails alone", {
  fails <- function(change, rule) {
    x <- adm_inputs(); x <- change(x)
    a <- adm(x)
    expect_false(a$admitted)
    expect_identical(a$failed, rule)
    expect_false(a[[rule]])
    expect_true(all(unlist(a[setdiff(.NEWFOR_RULES, rule)])))
  }
  fails(function(x) { x$verify$md5_ok[3] <- FALSE; x }, "rule_files")
  fails(function(x) { x$verify$present[9] <- FALSE; x }, "rule_files")
  fails(function(x) { x$verify <- x$verify[-5, ]; x }, "rule_files")      # a file without a row
  fails(function(x) { x$density$n_first_clip <- 0L; x }, "rule_returns")
  fails(function(x) { x$clip$las@data[, ReturnNumber := NULL]; x }, "rule_returns")
  fails(function(x) { data.table::set(x$clip$las@data, 2L, "ReturnNumber", NA_integer_); x },
        "rule_returns")
  fails(function(x) { x$clip$terrain_na_share <- 0.01; x }, "rule_terrain")
  fails(function(x) { x$clip$reach[["east"]] <- 9.99; x }, "rule_buffer")
  # an inside stem of 15 cm without a height (it is not primary, so the stem count holds)
  fails(function(x) {
    x$ref <- rbind(x$ref, data.frame(inside = TRUE, dbh_cm = 15, has_height = FALSE,
                                     dbh_status = "ok", primary = FALSE, inventoried = FALSE))
    x
  }, "rule_heights")
  fails(function(x) { x$area$gap_months <- 49L; x }, "rule_gap")
  fails(function(x) { x$area$gap_months <- -49L; x }, "rule_gap")
  fails(function(x) { x$ref <- x$ref[-1, ]; x }, "rule_stems")
  fails(function(x) { x$reg$offset <- 4.0001; x }, "rule_registration")
  fails(function(x) { x$reg$offset <- NA_real_; x }, "rule_registration")
  # the gap is computed from the dates when the area does not carry it
  x <- adm_inputs(); x$area$gap_months <- NULL; x$area$flight_date <- "2016-07"
  expect_identical(adm(x)$gap_months, 49L)
  expect_identical(adm(x)$failed, "rule_gap")
})

test_that("an area without a clip, inventory or registration fails the rules that need them", {
  x <- adm_inputs(); x[c("clip", "density", "reg")] <- list(NULL)
  a <- adm(x)
  expect_identical(a$failed, "rule_returns;rule_terrain;rule_buffer;rule_registration")
  x["ref"] <- list(NULL)
  a <- adm(x)
  expect_identical(a$failed, paste(c("rule_returns", "rule_terrain", "rule_buffer", "rule_heights",
                                     "rule_stems", "rule_registration"), collapse = ";"))
  expect_true(is.na(a$n_primary)); expect_true(is.na(a$reach_min)); expect_true(a$rule_files)
})

## ---- freeze, seal, read back -----------------------------------------------------------------
test_that("freezing writes the four files, byte for byte the same twice", {
  raw <- tempfile(); r1 <- tempfile(); r2 <- tempfile()
  on.exit(unlink(c(raw, r1, r2), recursive = TRUE))
  files <- syn_release(raw)
  threads <- lidR::get_lidr_threads()
  out <- newfor_freeze_area(raw, SYN_AREA, files, r1)
  expect_identical(lidR::get_lidr_threads(), threads)                 # restored
  expect_identical(names(out), c("admission", "scan"))
  expect_true(out$admission$admitted)
  expect_identical(out$admission$n_primary, 8L)                       # the edge stem included
  expect_identical(out$admission$n_outside, 1L)
  expect_identical(out$admission$n_missing_dbh, 1L)
  expect_identical(out$admission$n_below_caliper, 1L)
  expect_identical(names(out$scan), c("area", "dx", "dy", "stat"))
  expect_identical(unique(out$scan$area), "91")
  expect_identical(sort(list.files(file.path(r1, "91"))),
                   sort(c("normalized.laz", "aoi.wkt", "reference_stems.csv", "cell.json")))
  newfor_freeze_area(raw, SYN_AREA, files, r2)
  for (f in c("normalized.laz", "aoi.wkt", "reference_stems.csv", "cell.json"))
    expect_identical(frozen_sha256(file.path(r1, "91", f)), frozen_sha256(file.path(r2, "91", f)),
                     info = f)
  # the cell record
  cell <- jsonlite::read_json(file.path(r1, "91", "cell.json"), simplifyVector = TRUE)
  expect_true(all(c("id", "epsg", "box", "clip", "reach", "covered_area", "clip_area", "n_box",
                    "dropped", "terrain_na_share", "density", "res", "registration", "admission",
                    "raw_sha256", "lidr_threads") %in% names(cell)))
  expect_identical(as.numeric(cell$clip_area), 70 * 80)            # whole numbers read as integers
  expect_equal(cell$density$frdens_clip, cell$density$n_first_clip / cell$covered_area,
               tolerance = 1e-12)
  expect_identical(cell$id, "91"); expect_identical(cell$epsg, SYN_EPSG)
  expect_identical(cell$lidr_threads, 1L)
  expect_null(cell$registration$scan)
  expect_equal(c(cell$registration$dx, cell$registration$dy), c(0, 0))
  expect_identical(cell$res, newfor_res(cell$density$frdens_clip))
  expect_identical(unlist(cell$raw_sha256), stats::setNames(files$sha256, files$filename))
  expect_identical(cell$admission$failed, "")
  expect_identical(unlist(cell$dropped), c(class = 5L, withheld = 4L, no_terrain = 6L, below = 3L,
                                           above = 2L))
  # the stems file holds every inventory row with its flags
  st <- read.csv(file.path(r1, "91", "reference_stems.csv"), stringsAsFactors = FALSE)
  expect_identical(names(st), c("row", "E", "N", "dbh_m", "dbh_cm", "height", "vol", "inside",
                                "dbh_status", "has_height", "primary", "inventoried"))
  expect_identical(nrow(st), nrow(syn_ref()))
  # the written clip carries the CRS, the canonical order and scan angles above 90 degrees,
  # whose warning at the raw read is recorded
  las <- suppressWarnings(lidR::readLAS(file.path(r1, "91", "normalized.laz")))
  expect_identical(sf::st_crs(las)$epsg, SYN_EPSG)
  expect_false(is.unsorted(las$gpstime))
  expect_identical(range(las$ScanAngleRank), c(-5L, 100L))
  expect_match(cell$read_warnings, "ScanAngleRank greater than 90", all = FALSE)
})

test_that("a sealed root reads back, and refuses tampering and new areas", {
  raw <- tempfile(); root <- tempfile(); on.exit(unlink(c(raw, root), recursive = TRUE))
  files <- syn_release(raw)
  out <- newfor_freeze_area(raw, SYN_AREA, files, root)
  expect_error(newfor_freeze_area(raw, SYN_AREA, files, root), "area folder already exists")
  expect_false(newfor_sealed(root))
  expect_true(is.na(newfor_root_id(root)))
  expect_error(newfor_frozen_area(root, "91"), "not sealed")
  fa <- newfor_frozen_area(root, "91", verify = FALSE)                # unsealed, unverified
  expect_identical(fa$id, "91")
  write.csv(out$admission, file.path(root, "admission.csv"), row.names = FALSE)
  m <- newfor_seal(root)
  expect_true(newfor_sealed(root))
  expect_identical(m$file, sort(c("admission.csv", file.path("91", c("aoi.wkt", "cell.json",
                                                                     "normalized.laz",
                                                                     "reference_stems.csv"))),
                                method = "radix"))
  expect_identical(newfor_root_id(root), frozen_sha256(file.path(root, "freeze_manifest.csv")))
  expect_identical(names(read.csv(file.path(root, "freeze_manifest.csv"))),
                   c("file", "bytes", "sha256"))
  expect_error(newfor_seal(root), "already sealed")
  expect_error(newfor_freeze_area(raw, transform(SYN_AREA, id = "92"), files, root), "sealed")
  fa <- newfor_frozen_area(root, "91")
  expect_identical(names(fa), c("id", "epsg", "aoi", "stems", "cell", "las_file"))
  expect_identical(fa$epsg, SYN_EPSG)
  expect_true(sf::st_crs(fa$aoi) == sf::st_crs(SYN_EPSG))
  expect_equal(as.numeric(sf::st_area(fa$aoi)), 900)
  expect_identical(fa$stems$dbh_status[8:10], c("ok", "missing", "below_caliper"))
  expect_type(fa$stems$primary, "logical")
  expect_identical(sum(fa$stems$primary), 8L)
  expect_identical(fa$cell$admission$n_primary, 8L)
  expect_true(file.exists(fa$las_file))
  # the covered area and the density counts come back from the frozen files exactly
  las <- suppressWarnings(lidR::readLAS(fa$las_file))
  expect_identical(newfor_covered_area(las$X, las$Y), as.numeric(fa$cell$covered_area))
  expect_identical(newfor_density(las, fa$aoi, fa$cell$covered_area)[c("n_aoi", "n_first_clip")],
                   fa$cell$density[c("n_aoi", "n_first_clip")])
  a <- newfor_frozen_admission(root)
  expect_identical(a$area, "91")
  expect_type(a$rule_files, "logical"); expect_type(a$admitted, "logical")
  expect_identical(a$failed, "")
  # tampering with any of the area's files, or the admission table, is caught
  f <- file.path(root, "91", "reference_stems.csv")
  keep <- readLines(f)
  writeLines(sub("TRUE", "FALSE", keep), f)
  expect_error(newfor_frozen_area(root, "91"), "91/reference_stems.csv differs from the root")
  writeLines(keep, f)
  expect_identical(newfor_frozen_area(root, "91")$id, "91")
  write.csv(transform(out$admission, admitted = FALSE), file.path(root, "admission.csv"),
            row.names = FALSE)
  expect_error(newfor_frozen_admission(root), "admission.csv differs")
  unlink(file.path(root, "91", "aoi.wkt"))
  expect_error(newfor_frozen_area(root, "91"), "91/aoi.wkt differs")
  expect_error(newfor_frozen_area(root, "93"), "93/normalized.laz is not in the root's manifest")
})

test_that("a corrupted raw file fails rule_files; a missing one stops the freeze", {
  raw <- tempfile(); root <- tempfile(); on.exit(unlink(c(raw, root), recursive = TRUE))
  files <- syn_release(raw)
  writeLines("another sheet", file.path(raw, SYN_AREA$sheet))
  out <- newfor_freeze_area(raw, SYN_AREA, files, root)
  expect_false(out$admission$rule_files)
  expect_identical(out$admission$failed, "rule_files")
  expect_false(identical(jsonlite::read_json(file.path(root, "91", "cell.json"))$raw_sha256[[9]],
                         files$sha256[9]))
  unlink(file.path(raw, "91_DTM.tif"))
  expect_error(suppressWarnings(newfor_freeze_area(raw, SYN_AREA, files, file.path(root, "x"))))
  expect_false(dir.exists(file.path(root, "x", "91")))
})

test_that("a failure after the area folder was created leaves no area folder", {
  raw <- tempfile(); root <- tempfile(); on.exit(unlink(c(raw, root), recursive = TRUE))
  files <- syn_release(raw)
  dir.create(root)
  # writing the clip is the first step inside the new folder
  local_mocked_bindings(writeLAS = function(las, file, ...) {
    expect_true(dir.exists(dirname(file)))                         # the folder exists by now
    stop("disk full")
  }, .package = "lidR")
  expect_error(newfor_freeze_area(raw, SYN_AREA, files, root), "disk full")
  expect_false(dir.exists(file.path(root, "91")))
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), character())
})

test_that("code hashes: named by base name in the order given; a file not found stops", {
  dir <- tempfile(); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))
  writeLines("a <- 1", file.path(dir, "b.R")); writeLines("a <- 2", file.path(dir, "a.R"))
  find <- function(f) Find(file.exists, file.path(dir, f))
  h <- newfor_code_sha256(c("b.R", "a.R"), find)
  expect_identical(h, c(b.R = frozen_sha256(file.path(dir, "b.R")),
                        a.R = frozen_sha256(file.path(dir, "a.R"))))
  expect_false(anyNA(h))
  expect_error(newfor_code_sha256(c("a.R", "gone.R", "lost.R"), find),
               "R file the run record must hash is not found: gone.R, lost.R")
})

## ---- the null: offsets and shifts ------------------------------------------------------------
test_that("null offsets: deterministic, min_shift kept on a non-square window, RNG restored", {
  o <- newfor_null_offsets("07", w = 40, h = 20, k = 50)
  expect_length(o, 50L)
  expect_identical(o, newfor_null_offsets("07", 40, 20, k = 50))
  expect_false(identical(o, newfor_null_offsets("08", 40, 20, k = 50)))
  M <- do.call(rbind, o)
  expect_true(all(M[, 1] >= 0 & M[, 1] < 40 & M[, 2] >= 0 & M[, 2] < 20))
  expect_true(all(sqrt(pmin(M[, 1], 40 - M[, 1])^2 + pmin(M[, 2], 20 - M[, 2])^2) >= 8))
  # offset i is the first accepted draw after set.seed(seed_for(site, plot, "null") + i)
  manual <- function(i, w, h) {
    set.seed(seed_for("NEWFOR", "07", "null") + i)
    repeat {
      ox <- runif(1, 0, w); oy <- runif(1, 0, h)
      if (sqrt(min(ox, w - ox)^2 + min(oy, h - oy)^2) >= 8) return(c(ox, oy))
    }
  }
  expect_identical(o[[1]], manual(1L, 40, 20))
  expect_identical(o[[37]], manual(37L, 40, 20))
  # the first k of a longer list are the k offsets
  expect_identical(newfor_null_offsets("07", 40, 20, k = 60)[1:50], o)
  expect_length(newfor_null_offsets("07", 40, 20), NEWFOR_NULL_K)
  # the caller's RNG state and kind are restored, also when it had no state
  set.seed(11); a <- runif(3)
  set.seed(11); invisible(newfor_null_offsets("07", 40, 20, k = 5)); b <- runif(3)
  expect_identical(a, b)
  old <- get0(".Random.seed", envir = globalenv())
  rm(".Random.seed", envir = globalenv())
  invisible(newfor_null_offsets("07", 40, 20, k = 2))
  expect_false(exists(".Random.seed", envir = globalenv()))
  assign(".Random.seed", old, envir = globalenv())
  kind <- RNGkind(); on.exit(do.call(RNGkind, as.list(kind)), add = TRUE)
  RNGkind("L'Ecuyer-CMRG")
  expect_identical(newfor_null_offsets("07", 40, 20, k = 50), o)
  expect_identical(RNGkind()[1], "L'Ecuyer-CMRG")
  # a min_shift as long as the half diagonal cannot be met
  expect_error(newfor_null_offsets("07", 10, 6, k = 1, min_shift = sqrt(34)), "too large")
  expect_length(newfor_null_offsets("07", 10, 6, k = 3, min_shift = 5), 3L)
})

test_that("newfor_window and newfor_shift keep every shifted detection inside the window", {
  aoi <- syn_square(0, 0, 20, 30)
  win <- newfor_window(aoi, 4)
  expect_identical(win, list(xmin = -4, ymin = -4, w = 28, h = 38))
  set.seed(2)
  det <- data.frame(x = runif(300, -15, 35), y = runif(300, -15, 45), z = runif(300, 2, 30))
  inside <- det$x >= -4 & det$x <= 24 & det$y >= -4 & det$y <= 34
  for (of in list(c(0, 0), c(13.7, 0), c(27.9, 37.9), c(5, 20))) {
    s <- newfor_shift(det, win, of)
    expect_identical(nrow(s), sum(inside))
    expect_true(all(s$x >= -4 & s$x <= 24 & s$y >= -4 & s$y <= 34))
    expect_identical(s$z, det$z[inside])
  }
  expect_equal(newfor_shift(det, win, c(0, 0))[, c("x", "y")], det[inside, c("x", "y")])
  # by hand: x = 22 shifted by 14 wraps to -4 + (26 + 14) %% 28 = 8
  one <- data.frame(x = c(22, 30), y = c(10, 10), z = 5)
  expect_equal(newfor_shift(one, win, c(14, 0)), data.frame(x = 8, y = 10, z = 5))
})

## ---- scoring on a polygon --------------------------------------------------------------------
# A 20 m square; four stems (S4 on the eastern edge, inside), five detections:
#   D1 (5.5, 5, 19.5) matches S1 (0.5 m, height in [10, 28]);
#   D2 (15, 8, 30)    inside, 3 m from S2 but above its gate [6, 20]: a commission;
#   D3 (22, 10, 18)   outside the square, within 4 m of it: matches S4 (2 m), not counted
#                     towards precision;
#   D4 (10, 30, 10)   10 m outside: never read;
#   D5 (10, 16, 5)    matches S3 (1 m, height in [3, 14]).
# n_ref 4, n_det (inside) 3 (D1, D2, D5), TP 3 (S1, S3, S4), tp_core 2 (D1, D5).
# Bands: S3 (6 m) short, matched; S2 (12 m) mid, not; S1 (20 m), S4 (18 m) tall, both.
SC_AOI <- syn_square(0, 0, 20, 20)
SC_STEMS <- data.frame(E = c(5, 15, 10, 20), N = c(5, 5, 15, 10), height = c(20, 12, 6, 18),
                       crown_class = NA_character_, stringsAsFactors = FALSE)
SC_DET <- data.frame(x = c(5.5, 15, 22, 10, 10), y = c(5, 8, 10, 30, 16),
                     z = c(19.5, 30, 18, 10, 5))

test_that("newfor_score counts a hand-checked case, crown class NA", {
  s <- newfor_score(SC_STEMS, SC_DET, SC_AOI, 4)
  expect_identical(s, c(n_ref = 4, n_det = 3, TP = 3, tp_core = 2, n_h_short = 1, n_h_mid = 1,
                        n_h_tall = 2, tp_h_short = 1, tp_h_mid = 0, tp_h_tall = 2))
  # score_plot takes the all-NA crown class: no crown-class stem
  sc <- score_plot(SC_STEMS, SC_DET, tol_xy = 4, core_cx = NA, core_cy = NA, core_geometry = SC_AOI)
  expect_identical(c(sc$n_dominant, sc$n_suppressed), c(0L, 0L))
  expect_true(is.na(sc$rec_dominant))
  # within 1.5 m, D3 (2 m from S4 and from the square) is out of reach: S4 is missed
  expect_identical(newfor_score(SC_STEMS, SC_DET, SC_AOI, 1.5)[["TP"]], 2)
  e <- newfor_score(SC_STEMS, SC_DET[0, ], SC_AOI, 4)
  expect_identical(unname(e[c("n_det", "TP", "tp_core", "tp_h_short", "tp_h_mid", "tp_h_tall")]),
                   rep(0, 6))
  expect_error(newfor_score(transform(SC_STEMS[c(1, 4), ], E = c(5, 21)), SC_DET, SC_AOI, 4),
               "outside declared scoring footprint")
})

test_that("newfor_score_cell averages hand-checked shifted copies; an empty set scores 0", {
  # window: (-4, -4), 28 x 28. Shift (14, 0): D1 -> (19.5, 5), D2 -> (1, 8), D3 -> (8, 10),
  # D5 -> (-4, 16), D4 dropped (y 30 > 24). No stem lies within 4 m of a shifted detection
  # (nearest: S1 to (1, 8) at 5 m, S4 to (19.5, 5) at 5.02 m): TP 0; inside: three, none
  # matched. Shift (0, 0) is the observed scoring: TP 3, n_det 3, tp_core 2.
  cell <- newfor_score_cell(SC_STEMS, SC_DET, SC_AOI, "01", offsets = list(c(14, 0), c(0, 0)))
  expect_identical(names(cell), c(MCG_COUNT_COLS, "n_h_short", "n_h_mid", "n_h_tall", "tp_h_short",
                                  "tp_h_mid", "tp_h_tall", "tp_h_short0", "tp_h_mid0",
                                  "tp_h_tall0"))
  expect_identical(unlist(cell[MCG_COUNT_COLS]),
                   c(n_ref = 4, n_over = 0, n_under = 0, n_det = 3, TP = 3, tp_core = 2,
                     tp_over = 0, tp_under = 0, n_det0 = 3, TP0 = 1.5, tp_core0 = 1,
                     tp_over0 = 0, tp_under0 = 0))
  expect_identical(unlist(cell[c("n_h_short", "n_h_mid", "n_h_tall", "tp_h_short", "tp_h_mid",
                                 "tp_h_tall", "tp_h_short0", "tp_h_mid0", "tp_h_tall0")],
                          use.names = FALSE), c(1, 1, 2, 1, 0, 2, 0.5, 0, 1))
  # without offsets the null is undefined
  na <- newfor_score_cell(SC_STEMS, SC_DET, SC_AOI, "01", offsets = list())
  expect_true(all(is.na(unlist(na[c("n_det0", "TP0", "tp_core0", "tp_h_tall0")]))))
  expect_identical(na$TP, 3)
  # the default offsets are the plot's null offsets of the window
  def <- newfor_score_cell(SC_STEMS, SC_DET, SC_AOI, "01")
  expect_identical(def, newfor_score_cell(SC_STEMS, SC_DET, SC_AOI, "01",
                                          offsets = newfor_null_offsets("01", 28, 28)))
  expect_lt(def$TP0, def$TP)
  empty <- newfor_score_cell(SC_STEMS, SC_DET[0, ], SC_AOI, "01")
  expect_identical(empty$n_ref, 4)
  zero <- setdiff(names(empty), c("n_ref", "n_h_short", "n_h_mid", "n_h_tall"))
  expect_identical(unlist(empty[zero], use.names = FALSE), rep(0, length(zero)))
  # detections only outside the window: the same zeros
  far <- data.frame(x = 100, y = 100, z = 10)
  expect_identical(newfor_score_cell(SC_STEMS, far, SC_AOI, "01"), empty)
})

test_that("mcg_rates, mcg_pool and mcg_contrast accept the cells", {
  offs <- list(c(14, 0), c(0, 0))
  plots <- sprintf("%02d", 1:6)
  # configuration a: the hand case; b: the hand case without D1
  rows <- do.call(rbind, lapply(plots, function(p) rbind(
    cbind(site = NEWFOR_SITE, plot = p, config = "a",
          newfor_score_cell(SC_STEMS, SC_DET, SC_AOI, p, offsets = offs)),
    cbind(site = NEWFOR_SITE, plot = p, config = "b",
          newfor_score_cell(SC_STEMS, SC_DET[-1, ], SC_AOI, p, offsets = offs)))))
  r <- mcg_rates(rows)
  expect_equal(r$recall[1], 3 / 4); expect_equal(r$precision[1], 2 / 3)
  P <- mcg_pool(rows, "config")
  # pooled a: recall 18/24, precision 12/18; b: recall 12/24 (S1 lost), precision 6/12
  expect_equal(P$F1[P$config == "a"], 2 * 0.75 * (2 / 3) / (0.75 + 2 / 3))
  expect_equal(P$F1[P$config == "b"], 2 * 0.5 * 0.5 / (0.5 + 0.5))
  ct <- mcg_contrast(rows, paste0(NEWFOR_SITE, "::", plots), "a", "b", n_boot = 20, seed = 1)
  f1 <- ct[ct$metric == "F1", ]
  expect_equal(f1$difference, 2 * 0.75 * (2 / 3) / (0.75 + 2 / 3) - 0.5)
  expect_identical(f1$n_plots, 6L)
  expect_true(all(c("cF1", "cPrecision", "cRecall") %in% ct$metric))
  expect_true(is.finite(ct$difference[ct$metric == "cF1"]))
})

## ---- detection -------------------------------------------------------------------------------
test_that("newfor_detect runs every configuration once prepared; stock matches the package", {
  skip_if_not_installed("lidRplugins")
  las <- synth_closed_stand(1)
  threads <- lidR::get_lidr_threads()
  out <- newfor_detect(las, frdens_clip = 5)
  expect_identical(lidR::get_lidr_threads(), threads)
  expect_identical(names(out), c("res", "features", "det", "parity"))
  expect_identical(out$res, 0.5)
  expect_identical(names(out$det), names(newfor_configs()))
  for (d in out$det) expect_true(assert_detection_contract(d))
  prep <- mcg_prepare(las, 0.5, NEWFOR_A)
  for (k in names(out$det)) expect_identical(out$det[[k]], mcg_apply(prep, newfor_configs()[[k]]))
  f <- out$features
  expect_identical(names(f), c("res", "cover", "top_height", "crown_spacing", "n_crowns",
                               "crown_area", "n_candidates", "n_surface", "n_deeper", "closed",
                               "spaced", "gate_state"))
  expect_identical(nrow(f), 1L)
  expect_identical(f$cover, prep$cover); expect_identical(f$crown_spacing, prep$crown_spacing)
  expect_identical(f$n_candidates, nrow(prep$cand))
  expect_identical(f$n_surface + f$n_deeper, f$n_candidates)
  expect_gt(f$n_deeper, 0L)
  expect_identical(f$closed, prep$cover >= 0.6)
  expect_identical(f$spaced, prep$crown_spacing >= 8)
  expect_identical(f$gate_state, if (f$closed && f$spaced) "gated" else if (f$closed) "closed"
                   else "open")
  # the stand is closed: the exemption keeps the second of two tall crowns 4 m apart, which
  # the distance filter removes otherwise
  expect_true(f$closed)
  near <- function(det, x, y) any((det$x - x)^2 + (det$y - y)^2 <= 1)
  expect_true(near(out$det$floor_exempt, 12, 8)); expect_false(near(out$det$floor, 12, 8))
  expect_identical(out$parity$ok, TRUE)
  expect_identical(out$parity$n_package, nrow(out$det$stock))
  expect_identical(out$parity$n_stock, nrow(out$det$stock))
  expect_identical(out$parity$max_abs_diff, 0)
  expect_true(is.na(out$parity$error))
  # at 8 first returns per m2 or more the raster is 0.25 m, parity still holds
  hi <- newfor_detect(las, frdens_clip = 8, configs = newfor_configs()[c("stock", "declared")])
  expect_identical(hi$res, 0.25)
  expect_identical(names(hi$det), c("stock", "declared"))
  expect_identical(hi$parity$ok, TRUE)
  expect_null(newfor_detect(las, 5, configs = newfor_configs()["declared"], parity = FALSE)$parity)
  # without a stock configuration the parity uses MCG_STOCK
  expect_identical(newfor_detect(las, 5, configs = newfor_configs()["floor"])$parity$n_stock,
                   nrow(out$det$stock))
  expect_error(newfor_detect(las, NA), "density is unknown")
  expect_error(newfor_detect(las, 5, configs = list(MCG_STOCK)), "distinct names")
})

test_that("a package error in the parity check is recorded, not raised", {
  skip_if_not_installed("lidRplugins")
  las <- synth_closed_stand(1)
  p <- .newfor_parity(las, res = -1, a = NEWFOR_A, stock = data.frame(x = 1, y = 2, z = 3))
  expect_identical(p$ok, NA)
  expect_true(is.character(p$error) && nzchar(p$error))
  expect_identical(p$n_stock, 1L)
  # a different set: the counts or the coordinates differ
  out <- newfor_detect(las, 5, configs = newfor_configs()["stock"], parity = FALSE)
  st <- out$det$stock
  p <- .newfor_parity(las, 0.5, NEWFOR_A, st[-1, ])
  expect_false(p$ok); expect_true(is.na(p$max_abs_diff))
  moved <- st
  i <- which.max(moved$x); moved$x[i] <- moved$x[i] + 0.25           # stays the largest x
  p <- .newfor_parity(las, 0.5, NEWFOR_A, moved)
  expect_false(p$ok); expect_equal(p$max_abs_diff, 0.25)
})
