source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_registration_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_crowntruth_lib.R"), local = TRUE)

# Cone canopy heights at points xy (two columns): the maximum over cones of
# apex height h_k falling `slope` m per m from (cx_k, cy_k), floored at 0.
cones <- function(xy, cx, cy, h, slope = 2) {
  v <- numeric(nrow(xy))
  for (k in seq_along(cx))
    v <- pmax(v, h[k] - slope * sqrt((xy[, 1] - cx[k])^2 + (xy[, 2] - cy[k])^2))
  pmax(v, 0)
}
cone_raster <- function(ext, res, cx, cy, h) {
  r <- terra::rast(xmin = ext[1], xmax = ext[2], ymin = ext[3], ymax = ext[4],
                   resolution = res, crs = "EPSG:32611")
  terra::values(r) <- cones(terra::xyFromCell(r, seq_len(terra::ncell(r))), cx, cy, h)
  r
}
# Stems on a jittered 6 m lattice inside [8, 32] m, so that no two crowns are
# close enough to trade places under a few metres of shift.
lattice_stems <- function(seed = 1) {
  set.seed(seed)
  g <- expand.grid(x = seq(8, 32, by = 6), y = seq(8, 32, by = 6))
  list(x = g$x + runif(nrow(g), -1, 1), y = g$y + runif(nrow(g), -1, 1),
       h = runif(nrow(g), 15, 30))
}
# Absolute closeness of two positions (testthat's tolerance is relative).
near <- function(a, b, tol) expect_lt(max(abs(a - b)), tol)
boxes_at <- function(x, y, half = 2) {
  data.frame(cx = x, cy = y, half_side = half,
             sigma = pmax(OFO_CT$sigma_min, OFO_CT$sigma_frac * half))
}

test_that("the declared constants are those of the protocol", {
  expect_equal(c(OFO_CT$max_shift, OFO_CT$step, OFO_CT$tie_max, OFO_CT$tie_step),
               c(12, 0.25, 3, 0.25))
  expect_equal(c(OFO_CT$sigma_min, OFO_CT$sigma_frac, OFO_CT$dbh_min, OFO_CT$image_margin,
                 OFO_CT$height_frac, OFO_CT$tie_margin), c(0.5, 0.25, 10, 2, 0.6, 3))
  expect_identical(OFO_CT$visible, c("Open grown", "Full sun", "Partially shaded"))
  expect_equal(c(OFO_CT$boot, OFO_CT$min_stems, OFO_CT$max_s90, OFO_CT$min_tie_ncc),
               c(200, 8, 1.0, 0.5))
  expect_equal(unlist(OFO_CT$pass), c(min_units = 10, max_median = 1.0, max_error = 2.0,
                                      min_share = 0.9))
  expect_equal(nrow(ofo_ct_grid()), 97L^2)
  expect_equal(range(ofo_ct_grid()$dx), c(-12, 12))
  expect_equal(nrow(ofo_ct_tie_grid()), 25L^2)
  # the frozen method is untouched by this library
  expect_identical(ofo2_config_digest(),
                   "eede36eb4afc37a385dc3b204f0dcf660c29cc60bcf893293c8a546bb54803b6")
})

test_that("annotations of the six sites are selected with their image and CHM", {
  paths <- c("annotations/TEAK_046_2018.xml", "annotations/NIWO_011_2018.xml",
             "annotations/HARV_001_2019.xml", "annotations/SJER_052_2018.xml",
             "annotations/2018_SJER_3_252000_4104000_image_628.xml",
             "evaluation/RGB/TEAK_046_2018.tif", "evaluation/CHM/TEAK_046_2018_CHM.tif",
             "evaluation/RGB/NIWO_011_2018.tif", "evaluation/RGB/SJER_052_2018.tif",
             "evaluation/CHM/SJER_052_2018_CHM.tif", "LICENSE")
  f <- ofo_ct_nte_files(paths)
  expect_identical(f$annotation, c("NIWO_011_2018", "SJER_052_2018", "TEAK_046_2018"))
  expect_identical(f$plot, c("NIWO_011", "SJER_052", "TEAK_046"))
  expect_identical(f$ann_year, c(2018L, 2018L, 2018L))
  expect_identical(f$has_rgb, c(TRUE, TRUE, TRUE))
  expect_identical(f$has_chm, c(FALSE, TRUE, TRUE))
  expect_identical(f$chm[3], "evaluation/CHM/TEAK_046_2018_CHM.tif")
})

test_that("the git blob SHA-1 is git's object name of the file", {
  f <- tempfile(); on.exit(unlink(f))
  writeBin(raw(0), f)
  expect_identical(ofo_git_blob_sha1(f), "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")
  writeBin(charToRaw("hello\n"), f)
  expect_identical(ofo_git_blob_sha1(f), "ce013625030ba8dba906f756967f9e9ca394464a")
})

test_that("Pascal VOC boxes are read and mapped on the pixel-edge lattice", {
  xml <- tempfile(fileext = ".xml"); tif <- tempfile(fileext = ".tif")
  on.exit(unlink(c(xml, tif)))
  writeLines(c("<annotation><filename>SYN_001_2018.tif</filename>",
               "<size><width>400</width><height>400</height><depth>3</depth></size>",
               "<object><name>Tree</name><bndbox><xmin>100</xmin><ymin>50</ymin>",
               "<xmax>150</xmax><ymax>90</ymax></bndbox></object>",
               "<object><name> Tree </name><bndbox><xmin>7</xmin><ymin>0</ymin>",
               "<xmax>8</xmax><ymax>1</ymax></bndbox></object></annotation>"), xml)
  px <- ofo_ct_read_voc(xml)
  expect_identical(px$name, c("Tree", "Tree"))
  expect_equal(unname(unlist(px[1, c("xmin", "ymin", "xmax", "ymax")])), c(100, 50, 150, 90))
  expect_equal(c(attr(px, "width"), attr(px, "height")), c(400, 400))
  # a 0.1 m image whose top-left corner is (1000, 5040), written and read back
  r <- terra::rast(xmin = 1000, xmax = 1040, ymin = 5000, ymax = 5040, resolution = 0.1,
                   crs = "EPSG:32611")
  terra::values(r) <- 1
  terra::writeRaster(r, tif)
  g <- terra::rast(tif); e <- as.vector(terra::ext(g))
  b <- ofo_ct_boxes_map(px, e[1], e[4], terra::res(g)[1], terra::res(g)[2])
  expect_equal(unname(unlist(b[1, c("bxmin", "bxmax", "bymin", "bymax", "cx", "cy")])),
               c(1010, 1015, 5031, 5035, 1012.5, 5033))
  expect_equal(b$half_side[1], (2.5 + 2) / 2)
  expect_equal(b$sigma[1], 0.25 * 2.25)
  # a box over exactly one pixel (column 8, row 1, 1-based) is centred on that
  # pixel's centre: pixel coordinates are edges, not centres
  expect_equal(b$cx[2], terra::xFromCol(g, 8))
  expect_equal(b$cy[2], terra::yFromRow(g, 1))
  expect_equal(b$sigma[2], 0.5)                     # floor of 0.5 m for small boxes
  big <- ofo_ct_boxes_map(data.frame(xmin = 0, ymin = 0, xmax = 80, ymax = 80), 0, 0, 0.1)
  expect_equal(big$sigma, 1)                        # a quarter of a 4 m half-side
})

test_that("truth stems follow the declared selection, including missing positions", {
  ext <- c(0, 40, 0, 40)
  st <- data.frame(
    id = letters[1:16],
    E = c(10, 10, 10, 10, 1.9, 2, 10, 10, 10, 10, 10, 10, 10, 10, 50, 10),
    N = 20,
    live = c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE,
             TRUE, TRUE, FALSE),
    is_tree = c(TRUE, TRUE, TRUE, FALSE, rep(TRUE, 12)),
    stemDiameter = c(10, 9.9, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 8, 40),
    height = c(5, 5, 5, 5, 5, 5, 5, 5, 5, 18, 17.9, 25, NA, 20, 30, 50),
    canopyPosition = c("Full sun", "Full sun", "Full sun", "Full sun", "Full sun",
                       "Open grown", "Partially shaded", "Mostly shaded", "Full shade",
                       NA, "", "  ", NA, "Full sun", "Full sun", "Full sun"),
    stringsAsFactors = FALSE)
  rule <- ofo_ct_truth_rule(st, ext)
  # tallest live tree: 30 m (the live stem outside the image with DBH 8 counts;
  # the dead 50 m tree does not), so a height-only stem needs >= 18 m
  expect_equal(attr(rule, "tallest_live_m"), 30)
  expect_identical(setNames(as.vector(rule), st$id), c(
    a = "position",  # DBH exactly 10, full sun
    b = "",          # DBH 9.9
    c = "",          # dead
    d = "",          # not a tree
    e = "",          # 1.9 m from the image edge: outside the image shrunk by 2 m
    f = "position",  # exactly 2 m from the edge; open grown
    g = "position",  # partially shaded
    h = "",          # mostly shaded
    i = "",          # full shade
    j = "height",    # no position, height 18 = 0.6 x 30
    k = "",          # empty position, height 17.9 < 18
    l = "height",    # blank position, height 25
    m = "",          # no position and no height
    n = "position",
    o = "",          # outside the image, DBH 8
    p = ""))         # dead
  expect_equal(attr(rule, "n_live10_in_image"), 10)
  # a position, even an invisible one, is never overridden by the height rule
  st2 <- st[8, ]; st2$height <- 40
  expect_identical(as.vector(ofo_ct_truth_rule(st2, ext)), "")
})

test_that("the estimate rule equals ofo2_estimate on the 0.5 m grid", {
  g <- ofo_shift_grid()
  set.seed(11)
  for (k in 1:30) {
    obj <- rnorm(nrow(g))
    if (k %% 5 == 0) obj[sample(nrow(g), 3)] <- max(obj) + 1        # exact ties
    if (k %% 7 == 0) obj[which(g$dx == 12 & g$dy == 3)] <- max(obj) + 2   # on the edge
    if (k %% 9 == 0) obj[sample(nrow(g), 50)] <- NA
    a <- ofo_ct_estimate(obj, g, 0.5); b <- ofo2_estimate(obj, g)
    expect_identical(a[c("dx", "dy", "index", "on_edge")], b[c("dx", "dy", "index", "on_edge")])
  }
})

test_that("on a 0.25 m grid the refinement finds a parabola's vertex within half a step", {
  g <- ofo_ct_grid()
  e <- ofo_ct_estimate(-(g$dx - 1.1)^2 - 2 * (g$dy + 2.03)^2, g, 0.25)
  near(c(e$dx, e$dy), c(1.1, -2.03), 1e-9)
  expect_false(e$on_edge)
  # a sharp peak moves at most half a step
  obj <- rep(0, nrow(g)); i <- which(g$dx == 1 & g$dy == -2)
  obj[i] <- 1; obj[which(g$dx == 1.25 & g$dy == -2)] <- 0.999
  e <- ofo_ct_estimate(obj, g, 0.25)
  expect_lte(abs(e$dx - 1), 0.125 + 1e-12)
  expect_equal(e$dy, -2)
  # exact ties take the centre of the tied shifts
  obj <- rep(0, nrow(g))
  obj[which(g$dx %in% c(-1, 2) & g$dy == 0.5)] <- 3
  e <- ofo_ct_estimate(obj, g, 0.25)
  expect_equal(c(e$dx, e$dy), c(0.5, 0.5))
  # the edge is the edge of this window
  obj <- -((g$dx - 12)^2 + g$dy^2)
  expect_true(ofo_ct_estimate(obj, g, 0.25)$on_edge)
})

test_that("the objective recovers a planted shift", {
  s <- lattice_stems(2)
  for (T in list(c(2.25, -3.5), c(2.4, -3.65), c(-7.1, 5.3))) {
    b <- boxes_at(s$x + T[1], s$y + T[2], half = runif(length(s$x), 1.5, 4))
    b <- rbind(b, boxes_at(c(1, 39), c(39, 1)))                # boxes without a stem
    tr <- ofo_ct_truth(s$x, s$y, b, "SYN_001", B = 20)
    near(c(tr$dx, tr$dy), T, 0.01)
    expect_false(tr$on_edge)
    expect_lt(tr$s90_m, 0.01)
  }
  # on the grid and with identical boxes the parabola is symmetric: exact
  b <- boxes_at(s$x + 2.25, s$y - 3.5)
  tr <- ofo_ct_truth(s$x, s$y, b, "SYN_001", B = 5)
  near(c(tr$dx, tr$dy), c(2.25, -3.5), 1e-6)
  # the objective at the peak is the number of stems (each scores 1 there)
  expect_equal(tr$objective, length(s$x))
  # one stem's score: its best box only
  S <- ofo_ct_scores(0, 0, boxes_at(c(1, 3), c(0, 0), half = c(2, 8)),
                     data.frame(dx = c(0, 1), dy = 0))
  expect_equal(drop(S), c(max(exp(-1 / (2 * 0.5^2)), exp(-9 / (2 * 2^2))), 1))
  # no stems or no boxes: no truth
  expect_true(is.na(ofo_ct_truth(numeric(), numeric(), b, "SYN_001", B = 2)$dx))
  expect_true(is.na(ofo_ct_truth(1, 1, b[0, ], "SYN_001", B = 2)$s90_m))
})

test_that("the bootstrap is deterministic by seed and its s90 is the type-7 percentile", {
  set.seed(5)
  x <- runif(12, 5, 35); y <- runif(12, 5, 35)
  b <- boxes_at(x + 1 + rnorm(12, 0, 1.2), y - 2 + rnorm(12, 0, 1.2), half = 2.5)
  a1 <- ofo_ct_truth(x, y, b, "SYN_007", B = 30)
  a2 <- ofo_ct_truth(x, y, b, "SYN_007", B = 30)
  expect_identical(a1$boot_m, a2$boot_m)
  expect_identical(a1$s90_m, a2$s90_m)
  expect_equal(a1$s90_m, unname(quantile(a1$boot_m, 0.9, type = 7)))
  expect_gt(max(a1$boot_m), 0)
  # the third resample by hand: stems drawn with seed_for("crowntruth", plot, NA, 3)
  set.seed(seed_for("crowntruth", "SYN_007", NA, 3))
  idx <- sample.int(12, 12, replace = TRUE)
  g <- ofo_ct_grid()
  e3 <- ofo_ct_estimate(colSums(ofo_ct_scores(x[idx], y[idx], b, g)), g, 0.25)
  expect_equal(a1$boot_m[3], sqrt((e3$dx - a1$dx)^2 + (e3$dy - a1$dy)^2), tolerance = 1e-9)
  # another plot draws other resamples
  expect_false(identical(ofo_ct_truth(x, y, b, "SYN_008", B = 30)$boot_m, a1$boot_m))
})

test_that("the frame tie recovers a known displacement with the declared sign", {
  set.seed(3)
  cx <- runif(25, -2, 42); cy <- runif(25, -2, 42); h <- runif(25, 10, 35)
  chm <- cone_raster(c(0, 40, 0, 40), 1, cx, cy, h)          # annotation frame, 1 m
  cells <- ofo_ct_chm_cells(chm, c(0, 40, 0, 40))
  expect_equal(nrow(cells), 34L^2)                          # image shrunk by 3 m
  expect_true(all(cells$x > 3 & cells$x < 37))
  # the method's frame: every feature at p lies at p + D
  for (D in list(c(1.25, -0.75), c(-2.1, 0.6))) {
    S <- ofo2_surface(cone_raster(c(-20, 60, -20, 60), 0.5, cx + D[1], cy + D[2], h), "raw")
    tie <- ofo_ct_tie(cells, S)
    near(c(tie$dx, tie$dy), D, 0.01)
    expect_gt(tie$ncc, 0.95)
    expect_false(tie$on_edge)
  }
  # a displacement beyond the window ends on its edge
  S <- ofo2_surface(cone_raster(c(-20, 60, -20, 60), 0.5, cx + 4.5, cy, h), "raw")
  expect_true(ofo_ct_tie(cells, S)$on_edge)
  # cells without a height are not used
  chm2 <- chm; v <- terra::values(chm2); v[c(500, 610)] <- NA; v[700] <- -9999   # all inside
  terra::values(chm2) <- v
  expect_equal(nrow(ofo_ct_chm_cells(chm2, c(0, 40, 0, 40))), 34L^2 - 3L)
})

test_that("truth plus tie is the crown-frame truth the method should find", {
  s <- lattice_stems(4)
  Tr <- c(1.5, -2.25)       # stems -> crowns as drawn (annotation frame)
  D <- c(0.75, 1.0)         # annotation frame -> method frame
  b <- boxes_at(s$x + Tr[1], s$y + Tr[2])
  chm <- cone_raster(c(0, 40, 0, 40), 1, s$x + Tr[1], s$y + Tr[2], s$h)
  S <- ofo2_surface(cone_raster(c(-20, 60, -20, 60), 0.5, s$x + Tr[1] + D[1],
                                s$y + Tr[2] + D[2], s$h), "raw")
  tr <- ofo_ct_truth(s$x, s$y, b, "SYN_CHAIN", B = 10)
  tie <- ofo_ct_tie(ofo_ct_chm_cells(chm, c(0, 40, 0, 40)), S)
  truth_m <- c(tr$dx + tie$dx, tr$dy + tie$dy)
  near(truth_m, Tr + D, 0.01)
  # The method's estimate for stems displaced by `off` is the shift that puts
  # them on the surface's crowns; plus the offset it is Tr + D, so its error
  # against truth + tie is near 0 and against truth - tie it is 2 |D|.
  off <- c(3, -4)
  est <- Tr + D
  reg <- data.frame(variant = "ncc", signal = "height", unit = "SYN_CHAIN", kind = "plot",
                    site = "SYN", n_signal = 25L, offset_dx = off[1], offset_dy = off[2],
                    dx = est[1] - off[1], dy = est[2] - off[2], error_m = sqrt(sum(est^2)),
                    sub_p90_m = 0.2, on_edge = FALSE, accepted = TRUE, reject_reason = NA,
                    frozen_variant = TRUE, stringsAsFactors = FALSE)
  truth <- data.frame(plot = "SYN_CHAIN", truth_m_dx = truth_m[1], truth_m_dy = truth_m[2],
                      credible = TRUE, reason = "")
  u <- ofo_ct_units(reg, "benchmark", "development", truth)
  expect_lt(u$error_crown_m, 0.01)
  expect_equal(c(u$est_dx, u$est_dy), est)
  wrong <- c(tr$dx - tie$dx, tr$dy - tie$dy)
  expect_gt(sqrt(sum((est - wrong)^2)), 2)
})

test_that("credibility rules hold at their boundaries", {
  ok <- function(...) {
    a <- list(n = 8L, on_edge = FALSE, s90_m = 1.0, tie_ncc = 0.5, tie_on_edge = FALSE)
    a[names(list(...))] <- list(...)
    do.call(ofo_ct_credible, a)
  }
  expect_identical(ok(), list(credible = TRUE, reason = ""))
  expect_identical(ok(n = 7L)$reason, "n")
  expect_identical(ok(on_edge = TRUE)$reason, "on_edge")
  expect_identical(ok(on_edge = NA)$reason, "on_edge")
  expect_identical(ok(s90_m = 1.0 + 1e-6)$reason, "s90")
  expect_identical(ok(s90_m = NA)$reason, "s90")
  expect_identical(ok(tie_ncc = 0.5 - 1e-6)$reason, "tie_ncc")
  expect_identical(ok(tie_ncc = NA_real_)$reason, "tie_ncc")
  expect_identical(ok(tie_on_edge = TRUE)$reason, "tie_on_edge")
  expect_identical(ok(n = 3L, s90_m = 2, tie_on_edge = NA),
                   list(credible = FALSE, reason = "n;s90;tie_on_edge"))
})

test_that("the pass rule holds at its boundaries", {
  e10 <- c(rep(0.5, 4), 1.0, 1.0, rep(1.5, 3), 2.5)        # median exactly 1.0, 9 of 10
  p <- ofo_ct_pass(e10)
  expect_identical(p[c("units", "n_within_2m", "pass", "inconclusive")],
                   list(units = 10L, n_within_2m = 9L, pass = TRUE, inconclusive = FALSE))
  expect_equal(p$median_error_m, 1.0)
  expect_equal(p$share_within_2m, 0.9)
  expect_false(ofo_ct_pass(replace(e10, 9, 2.01))$pass)    # 8 of 10 within 2 m
  expect_true(ofo_ct_pass(replace(e10, 10, 2.0))$pass)     # an error of exactly 2 m is within
  expect_false(ofo_ct_pass(e10 + c(rep(0, 4), 1e-6, 1e-6, rep(0, 4)))$pass)   # median > 1
  p9 <- ofo_ct_pass(rep(0.1, 9))
  expect_true(p9$inconclusive)
  expect_false(p9$pass)
  p0 <- ofo_ct_pass(numeric())
  expect_true(p0$inconclusive); expect_false(p0$pass); expect_true(is.na(p0$median_error_m))
  expect_identical(ofo_ct_pass(c(e10, NA))$units, 10L)     # missing errors are not units
})

# Registration rows as the first protocol writes them (frozen and other variants).
reg_rows <- function() data.frame(
  variant = c("ncc", "ncc_r2", "ncc", "ncc_r2", "ncc_r2", "ncc", "ncc_r2"),
  signal = c("height", "rank", "height", "rank", "height", "height", "rank"),
  unit = c("P_A", "P_A", "P_B", "P_B", "P_A", "P_C", "P_C"),
  kind = "plot", site = "SYN",
  n_signal = c(25L, 9L, 30L, 12L, 25L, 2L, 14L),
  offset_dx = c(-0.5, -0.5, 1, 1, -0.5, 2, 2), offset_dy = c(0.5, 0.5, 2, 2, 0.5, 3, 3),
  dx = c(1, 4, -1, -1.2, 9, NA, -1.9), dy = c(2, 4, -2, -1.9, 9, NA, -3.1),
  error_m = NA_real_, sub_p90_m = c(0.3, 0.2, 2.5, 0.4, 0.1, NA, 0.5),
  on_edge = c(FALSE, FALSE, FALSE, FALSE, FALSE, NA, FALSE),
  accepted = c(TRUE, FALSE, FALSE, TRUE, TRUE, FALSE, TRUE),
  reject_reason = c("", "n", "sub_p90_m", "", "", "not_run", ""),
  frozen_variant = c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE), stringsAsFactors = FALSE)
truth_rows <- function() data.frame(
  plot = c("P_A", "P_B", "P_C"), truth_m_dx = c(0.4, 0, 0.1), truth_m_dy = c(2.3, 0, -0.2),
  credible = c(TRUE, FALSE, TRUE), reason = c("", "s90", ""), stringsAsFactors = FALSE)

test_that("test units take the frozen rows, the frozen gate and a credible truth", {
  u <- ofo_ct_units(reg_rows(), "benchmark", "confirmation", truth_rows())
  expect_identical(names(u)[seq_along(OFO_CT_UNIT_COLS)], OFO_CT_UNIT_COLS)
  expect_equal(nrow(u), 6L)                                  # the non-frozen row is left out
  a <- u[u$plot == "P_A" & u$signal == "height", ]
  expect_equal(c(a$est_dx, a$est_dy), c(0.5, 2.5))
  expect_equal(a$error_crown_m, sqrt(0.1^2 + 0.2^2))
  expect_equal(a$error_zero_m, sqrt(0.5^2 + 2.5^2))
  expect_true(a$in_test)
  key <- paste(u$plot, u$signal)
  expect_identical(setNames(u$in_test, key), c(
    "P_A height" = TRUE, "P_A rank" = FALSE,                 # rank: 9 < 10 stems
    "P_B height" = FALSE, "P_B rank" = FALSE,                # not accepted; truth not credible
    "P_C height" = FALSE, "P_C rank" = TRUE))                # not run
  expect_identical(setNames(u$at_min_stems, key), c(
    "P_A height" = TRUE, "P_A rank" = FALSE, "P_B height" = TRUE, "P_B rank" = TRUE,
    "P_C height" = FALSE, "P_C rank" = TRUE))
  expect_true(is.na(u$error_crown_m[key == "P_C height"]))
  # a table whose acceptance disagrees with the frozen gate is refused
  bad <- reg_rows(); bad$accepted[3] <- TRUE
  expect_error(ofo_ct_units(bad, "benchmark", "confirmation", truth_rows()), "frozen gate")
  bad <- reg_rows(); bad$variant[1] <- "ncc_r2"
  expect_error(ofo_ct_units(bad, "benchmark", "confirmation", truth_rows()), "frozen variants")
  bad <- reg_rows(); bad$at_min_stems <- TRUE
  expect_error(ofo_ct_units(bad, "benchmark", "confirmation", truth_rows()), "smallest stem")
  # plots without a truth row are not units
  expect_null(ofo_ct_units(reg_rows(), "niwo", "niwo", truth_rows()[0, ]))
})

test_that("the test pools every unit per signal and reports the subsets apart", {
  mk <- function(source, half, n, err, signal = "height") data.frame(
    source = source, half = half, plot = paste0(half, seq_len(n)), signal = signal,
    variant = "ncc", n_signal = 30L, at_min_stems = TRUE, accepted = TRUE, est_dx = 0,
    est_dy = 0, truth_m_dx = 0, truth_m_dy = 0, credible = TRUE, error_crown_m = err,
    error_zero_m = err + 1, in_test = TRUE, stringsAsFactors = FALSE)
  u <- rbind(mk("benchmark", "development", 4, c(0.2, 0.4, 0.6, 3)),
             mk("benchmark", "confirmation", 3, c(0.5, 0.7, 0.9)),
             mk("niwo", "niwo", 3, c(0.3, 1.1, 1.2)),
             mk("benchmark", "development", 9, rep(0.1, 9), "rank"))
  u$in_test[2] <- FALSE; u$credible[2] <- FALSE              # left out: truth not credible
  t <- ofo_ct_test(u)
  expect_equal(t$height$units, 9L)
  expect_true(t$height$inconclusive)
  expect_false(t$height$admitted)
  expect_equal(t$height$subsets$benchmark_development$units, 3L)
  expect_equal(t$height$subsets$benchmark_confirmation$units, 3L)
  expect_equal(t$height$subsets$benchmark$units, 6L)
  expect_equal(t$height$subsets$niwo$units, 3L)
  expect_equal(t$height$units_by_outcome$truth_not_credible, 1L)
  expect_equal(t$height$error_zero_same_units$median_error_m, 0.7 + 1)
  expect_true(t$rank$inconclusive)
  u <- rbind(u, mk("niwo", "niwo", 1, 0.2, "rank"))
  t <- ofo_ct_test(u)
  expect_true(t$rank$pass)
  expect_true(t$rank$admitted)
  expect_identical(t$rank$variant, "ncc_r2")
  expect_identical(t$rank$min_stems, 10L)
})
