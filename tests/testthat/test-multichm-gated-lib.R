# Unit tests for the multichm_gated arm library: the instrumented multichm
# candidate search (parity with lidRplugins::multichm), the first-return share,
# canopy cover, top height and the crowns with their spacing, the configuration
# and its label, the gate with its cover and crown-spacing switches, the
# distance filter, the calibration grid and the count-pooling, selection, split
# and contrast helpers. Synthetic data only.
suppressMessages({ library(lidR); library(data.table); library(sf) })
source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "calval_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "multichm_gated_lib.R"), local = TRUE)

## ---- synthetic clouds ---------------------------------------------------------------------
# A normalized stand of conical crowns: first returns on each crown surface,
# later returns inside the crowns, first-return ground hits, and one short tree
# among the tall ones (deeper-layer peaks).
synth_stand <- function(seed = 1, with_rn = TRUE) {
  set.seed(seed)
  tr <- data.frame(x = c(10, 18, 27, 11, 25, 19), y = c(10, 12, 9, 23, 24, 18),
                   h = c(22, 18, 20, 16, 21, 8), r = c(3.5, 3, 3.2, 2.8, 3.4, 2))
  crown <- lapply(seq_len(nrow(tr)), function(i) {
    t <- tr[i, ]
    ns <- 700; ni <- 250
    d <- t$r * sqrt(runif(ns)); a <- runif(ns, 0, 2 * pi)
    s <- data.frame(X = t$x + d * cos(a), Y = t$y + d * sin(a),
                    Z = pmax(0, t$h * (1 - 0.6 * d / t$r) + rnorm(ns, 0, 0.1)), ReturnNumber = 1L)
    d <- 0.8 * t$r * sqrt(runif(ni)); a <- runif(ni, 0, 2 * pi)
    n <- data.frame(X = t$x + d * cos(a), Y = t$y + d * sin(a),
                    Z = runif(ni, 0.3 * t$h, 0.9 * t$h), ReturnNumber = 2L)
    rbind(s, n)
  })
  g <- data.frame(X = runif(2500, 0, 36), Y = runif(2500, 0, 32), Z = abs(rnorm(2500, 0, 0.05)),
                  ReturnNumber = 1L)
  df <- do.call(rbind, c(crown, list(g)))
  df$ReturnNumber <- as.integer(df$ReturnNumber)
  if (!with_rn) df$ReturnNumber <- NULL
  las <- suppressWarnings(LAS(df))
  st_crs(las) <- 32611L
  las
}
# A hand-built cloud of explicit points (X, Y, Z [, ReturnNumber]).
pts_las <- function(df) {
  if (!is.null(df$ReturnNumber)) df$ReturnNumber <- as.integer(df$ReturnNumber)
  las <- suppressWarnings(LAS(df))
  st_crs(las) <- 32611L
  las
}
# Hand-built candidates (already in descending Z).
cands <- function(X, Y, Z, layer, share = NA_real_)
  data.table(X = X, Y = Y, Z = Z, layer = as.integer(layer), ztop = Z, share = share)
# Conical crowns 20 m high and 2.5 m in radius on a square lattice of step sp:
# first returns on a 0.5 m grid over a side x side clip, each on the cone of its
# own lattice cell (Z 0 outside the cone).
cone_lattice <- function(sp, side) {
  g <- seq(0.25, side - 0.25, by = 0.5)
  df <- expand.grid(X = g, Y = g)
  cx <- floor(df$X / sp) * sp + sp / 2; cy <- floor(df$Y / sp) * sp + sp / 2
  df$Z <- pmax(0, 20 * (1 - sqrt((df$X - cx)^2 + (df$Y - cy)^2) / 2.5))
  df$ReturnNumber <- 1L
  df
}
UNKNOWN_CROWNS <- list(n = NA_integer_, area = NA_real_, spacing = NA_real_)

## ---- configuration ------------------------------------------------------------------------
test_that("configurations are validated and labelled", {
  expect_identical(MCG_STOCK, list(zmin = 0, min_share = 0, cover_min = 0, surface_exempt = FALSE,
                                   spacing_min = 0))
  expect_identical(mcg_config_label(MCG_STOCK), "stock")
  expect_identical(mcg_config_label(mcg_config(5, 0.75, 0.7, TRUE)), "z5_s0.75_c0.7_e1")
  expect_identical(mcg_config_label(mcg_config(zmin = 8)), "z8_s0_c0_e0")
  expect_error(mcg_config(min_share = 1.5), "min_share")
  expect_error(mcg_config(zmin = -1), "zmin")
  expect_error(mcg_config(cover_min = NA), "cover_min")
  expect_error(mcg_config(surface_exempt = NA), "surface_exempt")
  expect_error(detect_multichm_gated(synth_stand(), 0.5, cfg = NULL), "no configuration")
})

test_that("the declared configuration is a gated grid configuration", {
  expect_identical(MCG_DECLARED, mcg_config(5, 0.75, 0.6, TRUE, 8))
  expect_identical(.mcg_check_config(MCG_DECLARED), MCG_DECLARED)
  expect_false(identical(MCG_DECLARED, MCG_STOCK))
  g <- mcg_grid()
  row <- g[g$label == mcg_config_label(MCG_DECLARED), , drop = FALSE]
  expect_identical(nrow(row), 1L)
  expect_identical(list(zmin = row$zmin, min_share = row$min_share, cover_min = row$cover_min,
                        surface_exempt = row$surface_exempt, spacing_min = row$spacing_min),
                   MCG_DECLARED)
  expect_identical(row$config_id, 360L)
})

test_that("spacing_min is validated, stored last and normalised to 0 without a share gate", {
  expect_identical(names(mcg_config()),
                   c("zmin", "min_share", "cover_min", "surface_exempt", "spacing_min"))
  expect_identical(mcg_config(5, 0.75, 0.6, TRUE, 8),
                   list(zmin = 5, min_share = 0.75, cover_min = 0.6, surface_exempt = TRUE,
                        spacing_min = 8))
  expect_identical(mcg_config(min_share = 0.5, spacing_min = 8L)$spacing_min, 8)  # a double
  expect_identical(mcg_config(min_share = 0.5, spacing_min = 8.5)$spacing_min, 8.5)
  for (bad in list(-1, -1e-9, NA, NA_real_, Inf, NaN, "8", TRUE, c(7, 9), numeric(), NULL))
    expect_error(mcg_config(min_share = 0.5, spacing_min = bad),
                 "multichm_gated: spacing_min must be one number in [0, Inf]", fixed = TRUE)
  expect_error(mcg_config(spacing_min = -1), "spacing_min")   # validated without a share gate too
  # spacing_min switches only the share gate: without one it is stored as 0
  expect_identical(mcg_config(zmin = 5, cover_min = 0.6, surface_exempt = TRUE, spacing_min = 8),
                   mcg_config(zmin = 5, cover_min = 0.6, surface_exempt = TRUE))
  expect_identical(mcg_config(spacing_min = 8), MCG_STOCK)
  expect_identical(mcg_config(min_share = 0.5, spacing_min = 0)$spacing_min, 0)
  # a configuration recorded without spacing_min (or with spacing_min NULL) has no
  # spacing condition
  four <- list(zmin = 5, min_share = 0.75, cover_min = 0.6, surface_exempt = TRUE)
  expect_identical(.mcg_check_config(four), mcg_config(5, 0.75, 0.6, TRUE, 0))
  expect_identical(.mcg_check_config(four)$spacing_min, 0)
  expect_identical(.mcg_check_config(c(four, list(spacing_min = NULL))), .mcg_check_config(four))
  expect_identical(.mcg_check_config(c(four, spacing_min = 8)), MCG_DECLARED)
  # the canonical field order whatever the input's order
  expect_identical(.mcg_check_config(rev(c(four, spacing_min = 8))), MCG_DECLARED)
  expect_identical(.mcg_check_config(c(list(spacing_min = 8), four[c(4, 1, 3, 2)])), MCG_DECLARED)
  expect_identical(.mcg_check_config(c(four[-2], min_share = 0, spacing_min = 8))$spacing_min, 0)
  expect_error(.mcg_check_config(c(four, spacing_min = NA)), "spacing_min must be one number")
  expect_error(.mcg_check_config(four[-1]),
               "list(zmin, min_share, cover_min, surface_exempt, spacing_min)", fixed = TRUE)
  expect_error(.mcg_check_config(list(spacing_min = 8)), "spacing_min may be absent")
  # what a configuration reads: the crown spacing only with a spacing condition
  expect_true(.mcg_needs_spacing(MCG_DECLARED))
  expect_true(.mcg_needs_spacing(mcg_config(min_share = 0.5, spacing_min = 7)))
  expect_false(.mcg_needs_spacing(mcg_config(5, 0.75, 0.6, TRUE)))
  expect_false(.mcg_needs_spacing(mcg_config(5, 0, 0.6, TRUE, 8)))
  expect_false(.mcg_needs_spacing(MCG_STOCK))
})

test_that("a label carries the spacing_min suffix only with a spacing condition", {
  expect_identical(mcg_config_label(MCG_DECLARED), "z5_s0.75_c0.6_e1_d8")
  expect_identical(mcg_config_label(mcg_config(5, 0.75, 0.6, TRUE, 8.5)), "z5_s0.75_c0.6_e1_d8.5")
  expect_identical(mcg_config_label(mcg_config(5, 0.75, 0.6, TRUE)), "z5_s0.75_c0.6_e1")
  expect_identical(mcg_config_label(mcg_config(5, 0.75, 0.6, TRUE, 0)), "z5_s0.75_c0.6_e1")
  expect_identical(mcg_config_label(mcg_config(0, 0.5, 0, FALSE, 7.5)), "z0_s0.5_c0_e0_d7.5")
  expect_identical(mcg_config_label(mcg_config(8, 0.9, 0.8, FALSE, 7)), "z8_s0.9_c0.8_e0_d7")
  # normalised away without a share gate
  expect_identical(mcg_config_label(mcg_config(5, 0, 0.6, TRUE, 8)), "z5_s0_c0.6_e1")
  expect_identical(mcg_config_label(mcg_config(spacing_min = 8)), "stock")
  expect_identical(mcg_config_label(MCG_STOCK), "stock")
  # a four-field list labels as its spacing_min 0 form
  expect_identical(mcg_config_label(list(zmin = 0, min_share = 0, cover_min = 0,
                                         surface_exempt = FALSE)), "stock")
  expect_identical(mcg_config_label(list(zmin = 5, min_share = 0.75, cover_min = 0.6,
                                         surface_exempt = TRUE)), "z5_s0.75_c0.6_e1")
  expect_identical(mcg_config_label(list(zmin = 5, min_share = 0.75, cover_min = 0.6,
                                         surface_exempt = TRUE, spacing_min = 8)),
                   "z5_s0.75_c0.6_e1_d8")
})

## ---- candidates -----------------------------------------------------------------------------
test_that("the stock configuration reproduces lidRplugins::multichm exactly", {
  skip_if_not_installed("lidRplugins")
  for (sd in 1:2) for (res in c(0.25, 0.5)) {
    las <- synth_stand(sd)
    tt <- suppressWarnings(lidR::locate_trees(las, lidRplugins::multichm(res = res,
                                                                         ws = ws_factory(0.10))))
    co <- sf::st_coordinates(tt)
    pkg <- data.frame(x = co[, 1], y = co[, 2], z = if (!is.null(tt$Z)) tt$Z else co[, 3])
    det <- mcg_apply(mcg_prepare(las, res), MCG_STOCK)
    expect_gt(nrow(det), 3)
    a <- pkg[order(pkg$x, pkg$y, pkg$z), ]; b <- det[order(det$x, det$y, det$z), ]
    expect_identical(nrow(a), nrow(b))
    expect_identical(unname(a$x), b$x)
    expect_identical(unname(a$y), b$y)
    expect_identical(unname(a$z), b$z)
    expect_identical(det, detect_multichm_gated(las, res, cfg = MCG_STOCK))
  }
})

test_that("candidate tables keep the package's invariants", {
  las <- synth_stand(1)
  C <- mcg_candidates(las, 0.5, ws_factory(0.10))
  expect_identical(names(C), c("X", "Y", "Z", "layer", "ztop"))
  expect_true(is.integer(C$layer))
  expect_false(is.unsorted(-C$Z))                             # descending Z
  expect_false(anyDuplicated(C[, .(X, Y)]) > 0)               # unique positions
  expect_true(any(C$layer == 1L) && any(C$layer > 1L))        # surface and deeper layers
  expect_true(all(C$Z > 2))                                   # hmin
  # ztop is the highest return of the candidate's own 0.5 m cell, not its p95
  p <- las@data
  S1 <- C[C$layer == 1L]
  top1 <- vapply(seq_len(nrow(S1)), function(i)
    max(p$Z[floor(p$X / 0.5) == floor(S1$X[i] / 0.5) & floor(p$Y / 0.5) == floor(S1$Y[i] / 0.5)]),
    numeric(1))
  expect_identical(S1$ztop, top1)
  expect_true(any(C$ztop[C$layer > 1L] > C$Z[C$layer > 1L]))  # deeper layers carry a top too
  expect_true(all(sort(unique(C$layer)) == seq_len(max(C$layer))))
  P <- mcg_prepare(las, 0.5)
  expect_identical(names(P), c("cand", "cover", "top_height", "crown_spacing", "n_crowns",
                               "crown_area", "has_return_number", "res", "a"))
  expect_identical(names(P$cand), c("X", "Y", "Z", "layer", "ztop", "share"))
  expect_true(all(is.na(P$cand$share) | (P$cand$share >= 0 & P$cand$share <= 1)))
  expect_equal(P$cover, mcg_canopy_cover(las))
  expect_identical(P$top_height, mcg_top_height(las))
})

test_that("an empty or flat cloud yields the 0-row detection contract", {
  flat <- pts_las(data.frame(X = runif(300, 0, 20), Y = runif(300, 0, 20), Z = 0.1,
                             ReturnNumber = 1L))
  P <- mcg_prepare(flat, 0.5)
  expect_identical(nrow(P$cand), 0L)
  for (cfg in list(MCG_STOCK, mcg_config(5, 0.75, 0.7, TRUE))) {
    det <- mcg_apply(P, cfg)
    expect_true(assert_detection_contract(det))
    expect_identical(nrow(det), 0L)
  }
  expect_identical(nrow(detect_multichm_gated(flat, 0.5, cfg = MCG_STOCK)), 0L)
})

test_that("an empty cloud gives 0 rows even for a configuration that reads the cover", {
  empty <- pts_las(data.frame(X = numeric(), Y = numeric(), Z = numeric(),
                              ReturnNumber = integer()))
  P <- mcg_prepare(empty, 0.5)
  expect_identical(nrow(P$cand), 0L)
  expect_true(P$has_return_number)
  expect_true(is.na(P$cover))                          # no first returns
  expect_identical(P$crown_spacing, NA_real_)          # nor a crown spacing
  for (cfg in list(MCG_STOCK, mcg_config(5, 0.75, 0.7, TRUE), MCG_DECLARED)) {
    det <- mcg_apply(P, cfg)
    expect_true(assert_detection_contract(det))
    expect_identical(nrow(det), 0L)
    expect_identical(names(det), c("x", "y", "z"))
  }
  expect_identical(nrow(detect_multichm_gated(empty, 0.5)), 0L)
})

test_that("a candidate's top falls back to its Z when the raster misses its own cell", {
  expect_identical(.mcg_ztop(c(NA, 9.99, 10, 12), c(10, 10, 10, 10)), c(10, 10, 10, 12))
  expect_identical(.mcg_ztop(numeric(), numeric()), numeric())
  # the p95 read at the candidate's coordinates: another cell's value (q != Z)
  # or NA means the coordinates miss its cell, whatever the top raster reads there
  expect_identical(.mcg_ztop(c(12, 12, 12), c(10, 10, 10), c(10.5, NA, 10)), c(10, 10, 12))
  expect_identical(.mcg_ztop(c(9, 12), c(10, 10), c(10, 10)), c(10, 12))
})

test_that("the candidate search runs on one lidR thread and restores the caller's setting", {
  old <- lidR::get_lidr_threads(); on.exit(lidR::set_lidr_threads(old), add = TRUE)
  las <- synth_stand(1)
  lidR::set_lidr_threads(1L)
  one <- mcg_candidates(las, 0.5, ws_factory(0.10))
  lidR::set_lidr_threads(2L)
  before <- lidR::get_lidr_threads()
  # lmf() calls the window function inside the search: record the thread count there
  seen <- integer()
  ws <- function(x) {
    seen <<- c(seen, lidR::get_lidr_threads())
    ws_factory(0.10)(x)
  }
  two <- mcg_candidates(las, 0.5, ws)
  expect_gt(length(seen), 0L)
  expect_true(all(seen == 1L))
  expect_identical(lidR::get_lidr_threads(), before)
  expect_identical(two, one)
})

## ---- first-return share and canopy cover ----------------------------------------------------
test_that("the first-return share counts returns inside the radius and the vertical band", {
  df <- data.frame(
    X = c(0.99, 1.01, 0,    0,     0.6, 0.71, 0,  4.1, 5.9, 5,   5),
    Y = c(0,    0,    0,    0,     0.6, 0.71, 0,  5,   5,   5,   6.01),
    Z = c(10,   10,   11,   11.01, 9.5, 10,   9,  20,  20.5, 19.6, 20),
    ReturnNumber = c(1, 1, 2, 1, 2, 1, 1, 1, 2, 2, 1))
  # Candidate 1 at (0, 0), top 10: inside are (0.99, 0) RN1, (0, 0, 11) RN2 on
  # the band's upper edge, (0.6, 0.6) RN2 and (0, 0, 9) RN1 on its lower edge.
  # Outside: (1.01, 0) and (0.71, 0.71), 1.004 m away, and (0, 0, 11.01).
  C <- data.table(X = c(0, 5, 30), Y = c(0, 5, 30), Z = c(10, 20, 15), layer = 1L,
                  ztop = c(10, 20, 15))
  s <- mcg_first_return_share(C, pts_las(df))
  expect_equal(s[1], 2 / 4)          # RN1 (0.99, 0), RN2 (0, 0, 11), RN2 (0.6, 0.6), RN1 (0, 0, 9)
  # Candidate 2 at (5, 5), top 20: (4.1, 5) RN1 and (5.9, 5) RN2 lie in other
  # bins; (5, 5, 19.6) RN2 inside; (5, 6.01) is 1.01 m away.
  expect_equal(s[2], 1 / 3)
  expect_true(is.na(s[3]))           # nothing near
  # radius 1.5 adds (1.01, 0) RN1 and (0.71, 0.71) RN1
  expect_equal(mcg_first_return_share(C, pts_las(df), radius = 1.5)[1], 4 / 6)
  expect_equal(mcg_first_return_share(C, pts_las(df), half_dz = 0.5)[1], 1 / 2)
  df$ReturnNumber <- NULL
  expect_true(all(is.na(mcg_first_return_share(C, pts_las(df)))))
  expect_identical(mcg_first_return_share(C[0], pts_las(df)), numeric())
})

test_that("a return at exactly the radius counts (dx^2 + dy^2 <= r^2)", {
  # Every coordinate is exactly representable: three returns lie exactly 1 m
  # from the candidate at (0, 0), one just beyond.
  df <- data.frame(X = c(1, 0, -1, 0), Y = c(0, 1, 0, -1.001), Z = 10,
                   ReturnNumber = c(1, 2, 2, 1))
  C <- data.table(X = 0, Y = 0, Z = 10, layer = 2L, ztop = 10)
  expect_equal(mcg_first_return_share(C, pts_las(df)), 1 / 3)
  expect_equal(mcg_first_return_share(C, pts_las(df[1, ])), 1)       # alone, on the circle
  expect_true(is.na(mcg_first_return_share(C, pts_las(df[1, ]), radius = 0.999)))
})

test_that("the first-return share matches a brute-force count on a stand", {
  las <- synth_stand(3)
  C <- mcg_candidates(las, 0.5, ws_factory(0.10))
  s <- mcg_first_return_share(C, las)
  p <- las@data
  brute <- vapply(seq_len(nrow(C)), function(i) {
    q <- (p$X - C$X[i])^2 + (p$Y - C$Y[i])^2 <= 1 & abs(p$Z - C$ztop[i]) <= 1
    if (any(q)) mean(p$ReturnNumber[q] == 1L) else NA_real_
  }, numeric(1))
  expect_identical(s, brute)
})

test_that("canopy cover is the share of first returns above 2 m", {
  df <- data.frame(X = as.numeric(1:6), Y = as.numeric(1:6), Z = c(0.5, 2, 2.01, 10, 10, 30),
                   ReturnNumber = c(1, 1, 1, 1, 2, 3))
  expect_equal(mcg_canopy_cover(pts_las(df)), 2 / 4)
  expect_equal(mcg_canopy_cover(pts_las(df), height = 0.4), 1)
  df$ReturnNumber <- NULL
  expect_true(is.na(mcg_canopy_cover(pts_las(df))))
})

test_that("the top height is the type-7 95th percentile of the first returns above 2 m", {
  # First returns above 2 m: 3, 5, 10, 20, 40. Not counted: the first returns at
  # 0.5, 1 and exactly 2 m, and the later returns at 60 and 50 m.
  df <- data.frame(X = as.numeric(1:10), Y = as.numeric(1:10),
                   Z = c(0.5, 2, 3, 5, 10, 20, 40, 60, 50, 1),
                   ReturnNumber = c(1, 1, 1, 1, 1, 1, 1, 2, 3, 1))
  las <- pts_las(df)
  # type 7, p = 0.95, n = 5: h = 1 + 4 * 0.95 = 4.8, so 20 + 0.8 * (40 - 20) = 36
  # (counting the first return at exactly 2 m would give 35, counting the later
  # returns 57)
  expect_equal(mcg_top_height(las), 36)
  expect_identical(mcg_top_height(las), unname(stats::quantile(c(3, 5, 10, 20, 40), 0.95,
                                                               type = 7)))
  expect_null(names(mcg_top_height(las)))
  # `height` and `prob` are honoured: above 4 m, h = 1 + 3 * 0.95 = 3.85 -> 37;
  # above 1.5 m the 2 m return counts -> 35; the median of the five -> 10
  expect_equal(mcg_top_height(las, height = 4), 37)
  expect_equal(mcg_top_height(las, height = 1.5), 35)
  expect_equal(mcg_top_height(las, prob = 0.5), 10)
  expect_equal(mcg_top_height(las, height = 4, prob = 1), 40)
  # a return number of NA counts as not first
  las_na <- pts_las(df)
  las_na@data$ReturnNumber[7] <- NA_integer_                 # the 40 m first return
  expect_equal(mcg_top_height(las_na), unname(stats::quantile(c(3, 5, 10, 20), 0.95)))
  # NA without ReturnNumber, and without a first return above the height
  df0 <- df; df0$ReturnNumber <- NULL
  expect_identical(mcg_top_height(pts_las(df0)), NA_real_)
  low <- data.frame(X = c(1, 2, 3, 4), Y = c(1, 2, 3, 4), Z = c(0.5, 2, 30, 25),
                    ReturnNumber = c(1, 1, 2, 2))
  expect_identical(mcg_top_height(pts_las(low)), NA_real_)
  expect_identical(mcg_top_height(las, height = 40), NA_real_)  # 40 is not above 40
  expect_identical(mcg_top_height(pts_las(data.frame(X = numeric(), Y = numeric(), Z = numeric(),
                                                     ReturnNumber = integer()))), NA_real_)
})

## ---- crowns and their spacing ---------------------------------------------------------------
# n, area and spacing agree with one another: whole 1 m cells, n an integer and
# spacing the side of the square each crown would occupy.
expect_coherent_crowns <- function(r) {
  expect_identical(names(r), c("n", "area", "spacing"))
  expect_true(is.integer(r$n) && is.double(r$area) && is.double(r$spacing))
  expect_identical(r$area %% (MCG_CROWN_RES^2), 0)
  expect_identical(r$spacing, sqrt(r$area / r$n))
}
# An independent count of mcg_crowns()'s n and area, made from coordinates rather
# than from the raster's matrix: the same surface (lidR::dsmtin(highest =
# highest), on one thread), its lmf maxima, and a cell interior when the centre
# of every cell within ws / 2 of its centre (by distance in metres, with a
# tolerance of 1e-9) is on the raster and not NA.
crowns_from_coordinates <- function(las, res = MCG_CROWN_RES, ws = MCG_CROWN_WS,
                                    hmin = MCG_COVER_HEIGHT, highest = TRUE) {
  old <- lidR::get_lidr_threads(); on.exit(lidR::set_lidr_threads(old), add = TRUE)
  lidR::set_lidr_threads(1L)
  first <- lidR::filter_poi(las, ReturnNumber == 1L)
  chm <- lidR::rasterize_canopy(first, res, lidR::dsmtin(highest = highest), pkg = "terra")
  v <- terra::values(chm, mat = FALSE)
  xy <- terra::xyFromCell(chm, seq_len(terra::ncell(chm)))
  m <- ceiling(ws / 2 / res) + 1
  off <- expand.grid(i = -m:m, j = -m:m)
  off <- off[sqrt((off$i * res)^2 + (off$j * res)^2) <= ws / 2 + 1e-9, ]
  inner <- which(!is.na(v))                      # the cells interior for every offset so far
  for (o in seq_len(nrow(off))) {
    cc <- terra::cellFromXY(chm, cbind(xy[inner, 1] + off$i[o] * res,
                                       xy[inner, 2] + off$j[o] * res))
    inner <- inner[!is.na(cc) & !is.na(v[cc])]
  }
  p <- sf::st_coordinates(lidR::locate_trees(chm, lidR::lmf(ws = ws, hmin = hmin)))
  n <- if (nrow(p)) sum(terra::cellFromXY(chm, p[, 1:2, drop = FALSE]) %in% inner) else 0L
  list(n = n, area = length(inner) * res^2)
}

test_that("the crown spacing of a lattice of cones is the lattice step", {
  expect_identical(c(MCG_CROWN_RES, MCG_CROWN_WS), c(1, 5))
  d <- cone_lattice(6, 60)
  r <- mcg_crowns(pts_las(d))
  expect_coherent_crowns(r)
  # about one crown per 36 m^2 of a 55 x 55 m interior: neither 0 nor the whole clip
  expect_gt(r$n, 60L); expect_gt(r$area, 0); expect_lte(r$area, 60^2)
  expect_lt(abs(r$spacing / 6 - 1), 0.05)
  # fewer returns: every second point, and one in sixteen (every fourth point
  # along each axis, a 2 m grid)
  ix <- round((d$X - 0.25) / 0.5); iy <- round((d$Y - 0.25) / 0.5)
  for (sub in list(d[seq(1, nrow(d), by = 2), ], d[ix %% 4 == 0 & iy %% 4 == 0, ])) {
    s <- mcg_crowns(pts_las(sub))
    expect_coherent_crowns(s)
    expect_lt(abs(s$spacing / 6 - 1), 0.05)
  }
})

test_that("the clip's size does not bias the crown spacing", {
  for (side in c(40, 60, 90)) {
    r <- mcg_crowns(pts_las(cone_lattice(6, side)))
    expect_coherent_crowns(r)
    expect_lt(abs(r$spacing / 6 - 1), 0.05)
  }
  for (side in c(60, 90)) {
    r <- mcg_crowns(pts_las(cone_lattice(8, side)))
    expect_coherent_crowns(r)
    expect_lt(abs(r$spacing / 8 - 1), 0.05)
  }
})

test_that("returns that are not first returns change nothing", {
  d <- cone_lattice(6, 60)
  set.seed(1)
  second <- data.frame(X = runif(2000, 0, 60), Y = runif(2000, 0, 60), Z = 40, ReturnNumber = 2L)
  expect_identical(mcg_crowns(pts_las(rbind(d, second))), mcg_crowns(pts_las(d)))
  # a return number of NA counts as not first, without an error or a warning
  na <- pts_las(d); as2 <- pts_las(d)
  k <- seq(1, nrow(d), by = 7)
  na@data$ReturnNumber[k] <- NA_integer_
  as2@data$ReturnNumber[k] <- 2L
  expect_no_warning(r <- mcg_crowns(na))
  expect_coherent_crowns(r)
  expect_identical(r, mcg_crowns(as2))
})

test_that("flat ground has interior cells but no crown, and a narrow clip has no interior", {
  set.seed(2)
  flat <- pts_las(data.frame(X = runif(2000, 0, 30), Y = runif(2000, 0, 30),
                             Z = runif(2000, 0, 1.9), ReturnNumber = 1L))
  r <- mcg_crowns(flat)
  expect_identical(r$n, 0L); expect_gt(r$area, 0); expect_identical(r$spacing, Inf)
  expect_coherent_crowns(r)
  # 4 m wide: no cell has its whole 5 m window on the surface, so no area and no
  # crown, tall returns or not
  set.seed(3)
  narrow <- pts_las(data.frame(X = runif(2000, 0, 4), Y = runif(2000, 0, 40),
                               Z = runif(2000, 0, 20), ReturnNumber = 1L))
  expect_identical(mcg_crowns(narrow), list(n = 0L, area = 0, spacing = NA_real_))
})

test_that("the surface is triangulated from the highest first return of each cell", {
  # a low first return (1 m) at the centre of every 1 m cell of a cone lattice:
  # wherever a cone stands it lies below its cell's highest return, so the
  # surface of the cell maxima keeps the cones, while a surface of all first
  # returns passes through the low returns at every cell centre
  d <- cone_lattice(6, 40)
  ctr <- seq(0.5, 39.5, by = 1)
  las <- pts_las(rbind(d, data.frame(expand.grid(X = ctr, Y = ctr), Z = 1, ReturnNumber = 1L)))
  highest <- crowns_from_coordinates(las)
  all_first <- crowns_from_coordinates(las, highest = FALSE)
  expect_gt(highest$n, 0L)
  expect_false(identical(all_first$n, highest$n))   # the cloud tells the two surfaces apart
  r <- mcg_crowns(las)
  expect_coherent_crowns(r)
  expect_identical(r[c("n", "area")], highest)
})

test_that("crowns on footprints that are not squares match a count from coordinates", {
  # a triangle (X > Y) and a disc cut from the cone lattice: unlike a square,
  # fully covered clip, they tell a mirrored row lookup or a square window apart
  d <- cone_lattice(6, 60)
  feet <- list(triangle = d[d$X > d$Y, ], disc = d[(d$X - 30)^2 + (d$Y - 30)^2 <= 29^2, ])
  want <- list(triangle = list(n = 40L, area = 1349), disc = list(n = 62L, area = 2230))
  for (nm in names(feet)) {
    las <- pts_las(feet[[nm]])
    r <- mcg_crowns(las)
    expect_coherent_crowns(r)
    expect_identical(r[c("n", "area")], crowns_from_coordinates(las))
    expect_identical(r[c("n", "area")], want[[nm]])
  }
})

test_that("the window holds the cells exactly ws / 2 away at a cell size of 0.1 m", {
  # at 0.1 m the window's edge lies exactly 2.5 m (25 cells) away along the axes
  # and at offsets such as (15, 20) cells, where a comparison in metres can lose
  # a cell to rounding
  las <- pts_las(cone_lattice(6, 30))
  r <- mcg_crowns(las, res = 0.1)
  expect_gt(r$n, 0L)
  expect_identical(r$spacing, sqrt(r$area / r$n))
  expect_identical(r[c("n", "area")], crowns_from_coordinates(las, res = 0.1))
})

test_that("the crown spacing is unknown without enough first returns to triangulate", {
  d <- cone_lattice(6, 30)
  no_rn <- d; no_rn$ReturnNumber <- NULL
  expect_identical(mcg_crowns(pts_las(no_rn)), UNKNOWN_CROWNS)
  later <- d; later$ReturnNumber <- 2L
  expect_identical(mcg_crowns(pts_las(later)), UNKNOWN_CROWNS)                 # no first return
  expect_identical(mcg_crowns(pts_las(data.frame(X = numeric(), Y = numeric(), Z = numeric(),
                                                 ReturnNumber = integer()))), UNKNOWN_CROWNS)
  two <- data.frame(X = c(1, 9, 5, 2), Y = c(1, 2, 9, 8), Z = c(5, 6, 7, 3),
                    ReturnNumber = c(1, 1, 2, 2))                             # two first returns
  expect_identical(mcg_crowns(pts_las(two)), UNKNOWN_CROWNS)
  # five first returns in one 1 m cell: a single cell maximum to triangulate
  one_cell <- data.frame(X = c(0.1, 0.9, 0.5, 0.2, 0.8), Y = c(0.1, 0.2, 0.9, 0.7, 0.6),
                         Z = c(5, 6, 7, 3, 4), ReturnNumber = 1L)
  expect_identical(mcg_crowns(pts_las(one_cell)), UNKNOWN_CROWNS)
  # three collinear first returns (the later returns off the line do not count):
  # lidR cannot triangulate them
  line <- data.frame(X = c(1, 5, 9, 2, 8), Y = c(1, 5, 9, 9, 1), Z = c(5, 6, 7, 3, 4),
                     ReturnNumber = c(1, 1, 1, 2, 2))
  expect_identical(mcg_crowns(pts_las(line)), UNKNOWN_CROWNS)
})

test_that("the crowns are counted on one lidR thread and the caller's setting is restored", {
  old <- lidR::get_lidr_threads(); on.exit(lidR::set_lidr_threads(old), add = TRUE)
  las <- pts_las(cone_lattice(6, 40))
  lidR::set_lidr_threads(1L)
  one <- mcg_crowns(las)
  # record the thread count inside lidR's calls that build the surface and find
  # its maxima, then run the real functions
  seen <- integer()
  real_rasterize <- lidR::rasterize_canopy
  real_locate <- lidR::locate_trees
  local_mocked_bindings(
    rasterize_canopy = function(...) {
      seen <<- c(seen, lidR::get_lidr_threads())
      real_rasterize(...)
    },
    locate_trees = function(...) {
      seen <<- c(seen, lidR::get_lidr_threads())
      real_locate(...)
    },
    .package = "lidR")
  lidR::set_lidr_threads(2L)
  expect_identical(mcg_crowns(las), one)
  expect_gte(length(seen), 2L)
  expect_true(all(seen == 1L))
  expect_identical(lidR::get_lidr_threads(), 2L)
  # also when the triangulation fails
  line <- pts_las(data.frame(X = c(1, 5, 9), Y = c(1, 5, 9), Z = c(5, 6, 7), ReturnNumber = 1L))
  expect_identical(mcg_crowns(line), UNKNOWN_CROWNS)
  expect_true(all(seen == 1L))
  expect_identical(lidR::get_lidr_threads(), 2L)
})

test_that("a prepared clip carries the crowns of mcg_crowns", {
  las <- synth_closed_stand(1)
  P <- mcg_prepare(las, 0.5)
  cr <- mcg_crowns(las)
  expect_identical(c(P$crown_spacing, P$n_crowns, P$crown_area), c(cr$spacing, cr$n, cr$area))
  expect_identical(P$n_crowns, cr$n)
  expect_true(is.finite(P$crown_spacing) && P$n_crowns > 0L)
  expect_no_warning(mcg_crowns(las))
})

## ---- the gate -------------------------------------------------------------------------------
test_that("the height floor applies to deeper layers only, in every stand", {
  C <- cands(X = 1:4, Y = 0, Z = c(9, 4.9, 5, 3), layer = c(2, 2, 3, 1))
  C$ztop <- C$Z + 1        # the floor reads Z, not the top return
  for (cover in c(0.1, 0.9, NA)) {
    g <- mcg_gate(C, cover, mcg_config(zmin = 5))
    expect_identical(g$keep, c(TRUE, FALSE, TRUE, TRUE))
    expect_identical(g$exempt, rep(FALSE, 4))
  }
  expect_true(all(mcg_gate(C, NA, MCG_STOCK)$keep))
})

test_that("the share gate applies only in closed stands and an unknown share fails it", {
  C <- cands(X = 1:5, Y = 0, Z = c(20, 15, 14, 13, 12), layer = c(1, 2, 2, 2, 2),
             share = c(0.1, 0.8, 0.75, 0.2, NA))
  cfg <- mcg_config(min_share = 0.75, cover_min = 0.7)
  expect_identical(mcg_gate(C, 0.69, cfg)$keep, rep(TRUE, 5))           # open: no gate
  expect_identical(mcg_gate(C, 0.70, cfg)$keep, c(TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_false(mcg_gate(C, 0.69, cfg)$closed)
  expect_true(mcg_gate(C, 0.70, cfg)$closed)
  # cover_min = 0: every stand is closed, the cover is not read
  expect_identical(mcg_gate(C, NA, mcg_config(min_share = 0.75))$keep,
                   c(TRUE, TRUE, TRUE, FALSE, FALSE))
  # floor and share together
  expect_identical(mcg_gate(C, 0.9, mcg_config(zmin = 14.5, min_share = 0.75, cover_min = 0.7))$keep,
                   c(TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_error(mcg_gate(C, NA, cfg), "canopy cover")
})

test_that("surface peaks are exempt only in closed stands and only when asked", {
  C <- cands(X = 1:3, Y = 0, Z = c(20, 15, 10), layer = c(1, 2, 1))
  cfg <- mcg_config(cover_min = 0.7, surface_exempt = TRUE)
  expect_identical(mcg_gate(C, 0.8, cfg)$exempt, c(TRUE, FALSE, TRUE))
  expect_identical(mcg_gate(C, 0.6, cfg)$exempt, rep(FALSE, 3))
  expect_identical(mcg_gate(C, NA, mcg_config(surface_exempt = TRUE))$exempt, c(TRUE, FALSE, TRUE))
  expect_identical(mcg_gate(C, 0.8, mcg_config(cover_min = 0.7))$exempt, rep(FALSE, 3))
  expect_error(mcg_gate(C, NA, cfg), "canopy cover")
  # a cover threshold with neither a share gate nor the exemption is moot
  expect_identical(mcg_gate(C, NA, mcg_config(zmin = 5, cover_min = 0.7))$keep, rep(TRUE, 3))
})

test_that("mcg_closed compares the cover with cover_min and never stops", {
  cfg <- mcg_config(5, 0.75, 0.6, TRUE)
  expect_true(mcg_closed(0.6, cfg))                    # the threshold itself is closed
  expect_true(mcg_closed(0.95, cfg))
  expect_false(mcg_closed(0.59, cfg))
  expect_identical(mcg_closed(NA_real_, cfg), NA)      # unknown cover: the gate stops, this does not
  expect_true(mcg_closed(NA_real_, MCG_STOCK))         # cover_min = 0: every stand is closed
  expect_true(mcg_closed(0, mcg_config(min_share = 0.75)))
  C <- cands(X = 1:2, Y = 0, Z = c(20, 15), layer = c(1, 2), share = c(1, 1))
  for (cover in c(0.2, 0.6, 0.9))
    expect_identical(mcg_gate(C, cover, cfg)$closed, mcg_closed(cover, cfg))
})

test_that("mcg_spaced compares the crown spacing with spacing_min and never stops", {
  d8 <- mcg_config(5, 0.75, 0.6, TRUE, 8)
  # spacing_min 0: every stand is spaced, an unknown spacing included
  for (s in list(NA_real_, NA, NULL, 0, 3, Inf))
    expect_identical(mcg_spaced(s, mcg_config(5, 0.75, 0.6, TRUE)), TRUE)
  expect_identical(mcg_spaced(NA_real_, MCG_STOCK), TRUE)
  expect_identical(mcg_spaced(NULL, mcg_config(5, 0, 0.6, TRUE, 8)), TRUE)   # normalised to 0
  expect_identical(mcg_spaced(8, d8), TRUE)                # the threshold itself is spaced
  expect_identical(mcg_spaced(8.001, d8), TRUE)
  expect_identical(mcg_spaced(7.999, d8), FALSE)
  expect_identical(mcg_spaced(Inf, d8), TRUE)              # interior surface without a crown
  expect_identical(mcg_spaced(NA_real_, d8), NA)           # unknown spacing: NA, no stop
  expect_identical(mcg_spaced(NaN, d8), NA)
  expect_identical(mcg_spaced(NULL, d8), NA)
  # a four-field configuration has no spacing condition
  expect_identical(mcg_spaced(NA_real_, list(zmin = 5, min_share = 0.75, cover_min = 0.6,
                                             surface_exempt = TRUE)), TRUE)
})

test_that("the share gate applies only in closed stands of crowns spaced at least spacing_min", {
  # surface Z 30 and 13; deeper layers: share 0.8 (passes), 0.2 (fails), NA
  # (fails), and one below the 5 m floor
  C <- cands(X = 1:6, Y = 0, Z = c(30, 20, 15, 14, 13, 4), layer = c(1, 2, 2, 3, 1, 2),
             share = c(0.1, 0.8, 0.2, NA, 0.1, 0.9))
  cfg <- mcg_config(zmin = 5, min_share = 0.75, cover_min = 0.6, surface_exempt = TRUE,
                    spacing_min = 8)
  gated <- c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE)
  floor_only <- c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE)
  surface <- c(TRUE, FALSE, FALSE, FALSE, TRUE, FALSE)
  # closed and spaced: the share gate, and the exemption
  for (s in c(8, 12, Inf)) {
    g <- mcg_gate(C, 0.9, cfg, crown_spacing = s)
    expect_identical(g$keep, gated)
    expect_identical(g$exempt, surface)
    expect_true(g$closed); expect_identical(g$spaced, TRUE)
  }
  expect_identical(names(g), c("keep", "exempt", "closed", "spaced"))
  # closed and not spaced: every deeper candidate that passes the floor is kept
  # and the surface candidates stay exempt
  g <- mcg_gate(C, 0.9, cfg, crown_spacing = 7.9)
  expect_identical(g$keep, floor_only)
  expect_identical(g$exempt, surface)
  expect_true(g$closed); expect_identical(g$spaced, FALSE)
  # open: neither the gate nor the exemption, spaced or not, and an unknown
  # spacing does not stop
  for (s in list(5, 10, NA_real_, NULL)) {
    g <- mcg_gate(C, 0.5, cfg, crown_spacing = s)
    expect_identical(g$keep, floor_only)
    expect_identical(g$exempt, rep(FALSE, 6))
    expect_false(g$closed)
  }
  expect_identical(mcg_gate(C, 0.5, cfg)$spaced, NA)     # the default: an unknown spacing
  expect_identical(mcg_gate(C, 0.5, cfg, crown_spacing = 10)$spaced, TRUE)
  # closed with an unknown spacing: stops when spacing_min > 0 ...
  expect_error(mcg_gate(C, 0.9, cfg), "needs the clip's crown spacing")
  expect_error(mcg_gate(C, 0.9, cfg, crown_spacing = NA_real_), "needs the clip's crown spacing")
  expect_error(mcg_gate(C, 0.9, cfg, crown_spacing = NULL), "needs the clip's crown spacing")
  expect_error(mcg_gate(C, 0.9, cfg), "prepared without the crown spacing")
  # ... and not when spacing_min == 0 (no spacing condition)
  d0 <- mcg_config(5, 0.75, 0.6, TRUE)
  g0 <- mcg_gate(C, 0.9, d0, crown_spacing = NA_real_)
  expect_identical(g0$keep, gated)
  expect_identical(g0$exempt, surface)
  expect_identical(g0$spaced, TRUE)
  expect_identical(mcg_gate(C, 0.9, d0), g0)
  expect_identical(mcg_gate(C, 0.9, d0, crown_spacing = 3), g0)
  # cover_min 0: every stand is closed, the spacing alone switches the share gate
  d8_all <- mcg_config(5, 0.75, 0, FALSE, 8)
  expect_identical(mcg_gate(C, NA, d8_all, crown_spacing = 9)$keep, gated)
  expect_identical(mcg_gate(C, NA, d8_all, crown_spacing = 7)$keep, floor_only)
  expect_error(mcg_gate(C, NA, d8_all), "needs the clip's crown spacing")
  # an unknown cover that decides something still stops first
  expect_error(mcg_gate(C, NA, cfg, crown_spacing = 9), "canopy cover")
})

## ---- the distance filter --------------------------------------------------------------------
test_that("the distance filter rejects within 3 m and within 5 m in 3-D", {
  f <- function(C) mcg_filter(C, rep(TRUE, nrow(C)), rep(FALSE, nrow(C)))
  expect_identical(f(cands(c(0, 2.9), 0, c(20, 20), 1)), c(TRUE, FALSE))       # inside 3 m
  expect_identical(f(cands(c(0, 4), 0, c(20, 18), 1)), c(TRUE, FALSE))         # 16 + 4 < 25
  expect_identical(f(cands(c(0, 4), 0, c(20, 16), 1)), c(TRUE, TRUE))          # 16 + 16 >= 25
  expect_identical(f(cands(c(0, 3), 0, c(20, 16), 1)), c(TRUE, TRUE))          # 9 is not < 9
  expect_identical(f(cands(0, 0, 20, 1)), TRUE)
  expect_identical(mcg_filter(cands(numeric(), numeric(), numeric(), integer()),
                              logical(), logical()), logical())
})

test_that("an exempt candidate is accepted and then excludes lower ones", {
  C <- cands(X = c(0, 3.5, 5), Y = 0, Z = c(20, 19, 18), layer = c(1, 1, 2))
  expect_identical(mcg_filter(C, rep(TRUE, 3), rep(FALSE, 3)), c(TRUE, FALSE, TRUE))
  expect_identical(mcg_filter(C, rep(TRUE, 3), c(TRUE, TRUE, FALSE)), c(TRUE, TRUE, FALSE))
  # a candidate that is not kept is never accepted and never excludes
  expect_identical(mcg_filter(C, c(FALSE, TRUE, TRUE), rep(FALSE, 3)), c(FALSE, TRUE, FALSE))
  expect_identical(mcg_filter(C, c(TRUE, FALSE, TRUE), rep(FALSE, 3)), c(TRUE, FALSE, TRUE))
})

test_that("gated configurations change the detections of a stand coherently", {
  P <- mcg_prepare(synth_stand(1), 0.5)
  stock <- mcg_apply(P, MCG_STOCK)
  surf <- mcg_apply(P, mcg_config(zmin = 1e6))         # no deeper-layer candidate survives
  S <- P$cand[P$cand$layer == 1L]
  expect_true(all(paste(surf$x, surf$y) %in% paste(S$X, S$Y)))
  ex <- mcg_apply(P, mcg_config(zmin = 1e6, surface_exempt = TRUE))
  expect_identical(nrow(ex), nrow(S))                   # every surface peak, unfiltered
  expect_false(is.unsorted(-ex$z))
})

test_that("a gate that needs return numbers stops on a cloud without them", {
  P <- mcg_prepare(synth_stand(1, with_rn = FALSE), 0.5)
  expect_false(P$has_return_number)
  expect_true(is.na(P$cover))
  expect_identical(P$top_height, NA_real_)
  expect_identical(P[c("crown_spacing", "n_crowns", "crown_area")],
                   list(crown_spacing = NA_real_, n_crowns = NA_integer_, crown_area = NA_real_))
  expect_true(all(is.na(P$cand$share)))
  expect_error(mcg_apply(P, MCG_DECLARED), "ReturnNumber")
  expect_error(mcg_apply(P, mcg_config(min_share = 0.5)), "ReturnNumber")
  expect_error(mcg_apply(P, mcg_config(cover_min = 0.7, surface_exempt = TRUE)), "canopy cover")
  expect_error(mcg_apply(P, mcg_config(5, 0.75, 0.7, TRUE)), "ReturnNumber")
  for (cfg in list(MCG_STOCK, mcg_config(zmin = 5), mcg_config(surface_exempt = TRUE),
                   mcg_config(zmin = 5, cover_min = 0.7)))
    expect_true(assert_detection_contract(mcg_apply(P, cfg)))
  P1 <- mcg_prepare(synth_stand(1), 0.5)
  expect_identical(mcg_apply(P, MCG_STOCK), mcg_apply(P1, MCG_STOCK))
})

# synth_closed_stand() (helper-synth.R): a closed stand with an understory peak
# under a wide crown that the share gate removes.
test_that("on a closed stand the spacing condition switches the share gate and nothing else", {
  las <- synth_closed_stand(1)
  P <- mcg_prepare(las, 0.5)
  sp <- P$crown_spacing
  expect_identical(sp, mcg_crowns(las)$spacing)
  expect_true(is.finite(sp) && sp > 1)
  cfg <- function(d, s = 0.75) mcg_config(5, s, 0.6, TRUE, d)
  expect_true(mcg_closed(P$cover, cfg(0)))
  gated <- mcg_apply(P, cfg(0))                    # no spacing condition
  ungated <- mcg_apply(P, cfg(0, s = 0))           # the same without the share gate
  expect_false(isTRUE(all.equal(gated, ungated)))
  near <- function(det, x, y, r = 1) any((det$x - x)^2 + (det$y - y)^2 <= r^2)
  expect_true(near(ungated, 25.5, 21))             # the understory peak
  expect_false(near(gated, 25.5, 21))
  # spacing_min above the stand's crown spacing: no share gate (the floor and
  # the exemption still apply)
  for (d in c(sp + 0.01, sp + 20)) expect_identical(mcg_apply(P, cfg(d)), ungated)
  # spacing_min at or below it: the share gate as without a spacing condition
  for (d in c(sp, sp - 0.01, 1)) expect_identical(mcg_apply(P, cfg(d)), gated)
  expect_identical(detect_multichm_gated(las, 0.5, cfg = cfg(sp + 0.01)), ungated)
  expect_identical(detect_multichm_gated(las, 0.5, cfg = cfg(sp)), gated)
  # an infinite spacing (interior surface without a crown) counts as spaced
  Pinf <- P; Pinf$crown_spacing <- Inf
  expect_identical(mcg_apply(Pinf, cfg(sp + 20)), gated)
})

test_that("a clip prepared without the crown spacing serves configurations that do not need it", {
  P <- mcg_prepare(synth_closed_stand(1), 0.5)
  Q <- P[setdiff(names(P), "crown_spacing")]
  expect_false("crown_spacing" %in% names(Q))
  for (cfg in list(MCG_STOCK, mcg_config(5, 0.75, 0.6, TRUE), mcg_config(5, 0, 0.6, TRUE, 8),
                   mcg_config(5, 0.75, 0.99, TRUE, 8)))    # the last: an open stand
    expect_identical(mcg_apply(Q, cfg), mcg_apply(P, cfg))
  expect_error(mcg_apply(Q, mcg_config(5, 0.75, 0.6, TRUE, 10)), "needs the clip's crown spacing")
  expect_error(mcg_apply(Q, MCG_DECLARED), "needs the clip's crown spacing")
  # an unknown crown spacing in the prepared clip behaves the same way
  R <- P; R$crown_spacing <- NA_real_
  d0 <- mcg_config(5, 0.75, 0.6, TRUE)
  expect_identical(mcg_apply(R, d0), mcg_apply(P, d0))
  expect_error(mcg_apply(R, MCG_DECLARED), "needs the clip's crown spacing")
  # the top height is recorded only: without it, or unknown, nothing changes
  for (Pt in list(P[setdiff(names(P), "top_height")], replace(P, "top_height", list(NA_real_))))
    for (cfg in list(MCG_STOCK, d0, MCG_DECLARED, mcg_config(5, 0.75, 0.6, TRUE, 30)))
      expect_identical(mcg_apply(Pt, cfg), mcg_apply(P, cfg))
})

## ---- the calibration grid -------------------------------------------------------------------
test_that("the declared grid has 447 unique rows, stock first, least intervention first", {
  g <- mcg_grid()
  expect_identical(nrow(g), 447L)
  expect_identical(names(g), c("config_id", "zmin", "min_share", "cover_min", "surface_exempt",
                               "spacing_min", "label"))
  expect_identical(g$config_id, seq_len(447))
  expect_identical(anyDuplicated(g$label), 0L)
  fields <- c("zmin", "min_share", "cover_min", "surface_exempt", "spacing_min")
  expect_identical(anyDuplicated(g[fields]), 0L)
  # every row is a canonical configuration with its own label
  cfgs <- lapply(seq_len(nrow(g)), function(i)
    mcg_config(g$zmin[i], g$min_share[i], g$cover_min[i], g$surface_exempt[i], g$spacing_min[i]))
  expect_identical(lapply(cfgs, unlist), lapply(seq_len(nrow(g)), function(i) unlist(g[i, fields])))
  expect_identical(vapply(cfgs, mcg_config_label, ""), g$label)
  # rows 1..87: the configurations without a spacing condition, with the order,
  # ids and labels of the 87-configuration grid (cells scored on it stay
  # comparable)
  o <- g[1:87, ]
  expect_true(all(o$spacing_min == 0))
  expect_false(any(grepl("_d", o$label, fixed = TRUE)))
  expect_identical(o$label[1], "stock")
  expect_false(any(o$min_share == 0 & !o$surface_exempt & o$cover_min > 0))
  expect_identical(sum(!o$surface_exempt), 39L)
  expect_identical(order(o$surface_exempt, o$min_share, o$zmin, -o$cover_min), seq_len(87))
  expect_setequal(unique(o$zmin), c(0, 5, 8))
  expect_setequal(unique(o$min_share), c(0, 0.5, 0.75, 0.9))
  expect_setequal(unique(o$cover_min), c(0, 0.6, 0.7, 0.8))
  expect_identical(o$cover_min[2:5], c(0, 0, 0.8, 0.7))   # z5, z8, then z0 s0.5 c0.8, c0.7
  expect_identical(o$label[c(2, 4, 40, 70, 87)],
                   c("z5_s0_c0_e0", "z0_s0.5_c0.8_e0", "z0_s0_c0.8_e1", "z5_s0.75_c0.6_e1",
                     "z8_s0.9_c0_e1"))
  # rows 88..447: each of the 72 configurations with a share gate, in the order
  # of rows 1..87, as one block of five rows with spacing_min descending 9..7
  n <- g[88:447, ]
  expect_identical(nrow(n), 360L)
  expect_true(all(n$min_share > 0))
  expect_true(all(n$spacing_min %in% c(7, 7.5, 8, 8.5, 9)))
  expect_true(all(grepl("_d[0-9.]+$", n$label)))
  gate <- o[o$min_share > 0, setdiff(fields, "spacing_min")]
  expect_identical(nrow(gate), 72L)
  expect_identical(n$spacing_min, rep(c(9, 8.5, 8, 7.5, 7), 72))
  for (f in setdiff(fields, "spacing_min"))             # constant within each block of five
    expect_identical(n[[f]], gate[[f]][rep(seq_len(72), each = 5)])
  expect_identical(n$label[1:5], paste0("z0_s0.5_c0.8_e0_d", c(9, 8.5, 8, 7.5, 7)))
  expect_identical(g$config_id[g$label == "z5_s0.75_c0.6_e1_d8"], 360L)
  expect_identical(g$config_id[g$label == "z5_s0.75_c0.6_e1_d8.5"], 359L)
  expect_identical(g$config_id[g$label == "z5_s0.75_c0.6_e1"], 70L)
  expect_identical(g$label[447], "z8_s0.9_c0_e1_d7")
})

## ---- scoring --------------------------------------------------------------------------------
stems_fixture <- function() data.frame(
  E = c(0, 5, -6, 8, -3), N = c(0, 4, 2, -7, -8), height = c(20, 18, 9, 15, 6),
  crown_class = c("dominant", "codominant", "intermediate", "dominant", "suppressed"),
  stringsAsFactors = FALSE)

test_that("mcg_score_cell recovers the counts score_plot implies, and the null means", {
  st <- stems_fixture()
  det <- data.frame(x = c(0.5, 5, -6, 9.5, 3), y = c(0, 4.5, 2, 9.5, -3), z = c(19, 17, 8, 12, 14))
  offs <- mcg_null_offsets("SITE", "SITE_001", half = 10, k = 5)
  expect_length(offs, 5)
  expect_identical(offs, mcg_null_offsets("SITE", "SITE_001", half = 10, k = 5))
  expect_identical(offs[[3]], null_offset(28, seed_for("SITE", "SITE_001", "null") + 3, min_shift = 8))
  r <- mcg_score_cell(st, det, 0, 0, 10, offs)
  expect_identical(names(r), MCG_COUNT_COLS)
  sp <- score_plot(st, det, tol_xy = 4, core_cx = 0, core_cy = 0, core_half = 10)
  expect_equal(r$TP, sp$TP); expect_equal(r$n_det, sp$n_det); expect_equal(r$n_ref, 5)
  expect_equal(r$tp_core, round(sp$precision * sp$n_det))
  expect_equal(c(r$n_over, r$n_under), c(3, 2))
  expect_equal(r$tp_over, round(sp$rec_dominant * 2) + round(sp$rec_codominant * 1))
  null1 <- sapply(offs, function(o) {
    s <- score_plot(st, shift_detections(det, 0, 0, 14, o), tol_xy = 4, core_cx = 0, core_cy = 0,
                    core_half = 10)
    c(s$TP, s$n_det, if (s$n_det > 0) round(s$precision * s$n_det) else 0)
  })
  expect_equal(c(r$TP0, r$n_det0, r$tp_core0), rowMeans(null1))
  e <- mcg_score_cell(st, det[0, ], 0, 0, 10, offs)
  expect_equal(c(e$n_det, e$TP, e$tp_core, e$n_det0, e$TP0), c(0, 0, 0, 0, 0))
  expect_true(is.na(mcg_score_cell(st, det, 0, 0, 10, list())$TP0))
})

count_row <- function(...) {
  base <- as.list(setNames(rep(0, length(MCG_COUNT_COLS)), MCG_COUNT_COLS))
  v <- list(...); base[names(v)] <- v
  as.data.frame(base)
}

test_that("mcg_rates computes the rates and the chance-corrected rates from counts", {
  cn <- count_row(n_ref = 10, n_over = 6, n_under = 4, n_det = 8, TP = 6, tp_core = 4,
                  tp_over = 5, tp_under = 1, n_det0 = 8, TP0 = 2, tp_core0 = 1,
                  tp_over0 = 1, tp_under0 = 1)
  r <- mcg_rates(cn)
  f1 <- function(a, b) 2 * a * b / (a + b)
  expect_equal(r$recall, 0.6); expect_equal(r$precision, 0.5)
  expect_equal(r$F1, f1(0.6, 0.5))
  expect_equal(r$null_recall, 0.2); expect_equal(r$null_precision, 0.125)
  expect_equal(r$null_F1, f1(0.2, 0.125))
  expect_equal(r$cF1, (f1(0.6, 0.5) - f1(0.2, 0.125)) / (1 - f1(0.2, 0.125)))
  expect_equal(r$cRecall, (0.6 - 0.2) / 0.8)
  expect_equal(r$cPrecision, (0.5 - 0.125) / 0.875)
  expect_equal(r$cRecall_over, (5 - 1) / (6 - 1))
  expect_equal(r$cRecall_under, 0)
  expect_equal(r$det_per_ref, 0.8)
  z <- mcg_rates(count_row(n_ref = 4, TP = 0))
  expect_true(is.na(z$precision) && is.na(z$F1) && is.na(z$cF1))
  expect_error(mcg_rates(data.frame(TP = 1)), "missing count columns")
})

test_that("mcg_pool sums counts before computing rates", {
  rows <- rbind(cbind(site = "A", count_row(n_ref = 2, TP = 2, n_det = 2, tp_core = 2)),
                cbind(site = "A", count_row(n_ref = 18, TP = 0, n_det = 2, tp_core = 0)),
                cbind(site = "B", count_row(n_ref = 5, TP = 1, n_det = 5, tp_core = 1)))
  p <- mcg_pool(rows, "site")
  expect_equal(p$recall[p$site == "A"], 2 / 20)     # not mean(1, 0) = 0.5
  expect_equal(p$n_cells, c(2L, 1L))
  expect_equal(mcg_pool(rows)$TP, 3)
})

## ---- selection, split and contrast ----------------------------------------------------------
grid_rows <- function(tp_by_config, plots = c("A::p1", "A::p2", "B::p3")) {
  do.call(rbind, lapply(seq_along(tp_by_config), function(k) do.call(rbind, lapply(plots, function(id)
    cbind(data.frame(site = sub("::.*", "", id), plot = sub(".*::", "", id), rung = "native",
                     config_id = k, config = if (k == 1) "stock" else paste0("c", k),
                     stringsAsFactors = FALSE),
          count_row(n_ref = 10, n_det = 10, TP = tp_by_config[k], tp_core = tp_by_config[k],
                    n_det0 = 10, TP0 = 2, tp_core0 = 2))))))
}

test_that("mcg_select picks the best pooled criterion and breaks ties to stock", {
  ids <- c("A::p1", "A::p2", "B::p3")
  expect_identical(mcg_select(grid_rows(c(5, 5, 5)), ids), 1L)
  expect_identical(mcg_select(grid_rows(c(5, 7, 7)), ids), 2L)
  expect_identical(mcg_select(grid_rows(c(5, 6, 8)), ids, criterion = "F1"), 3L)
  r <- grid_rows(c(5, 6, 8)); r$TP[r$config_id == 3 & r$plot == "p3"] <- 0
  r$tp_core[r$config_id == 3 & r$plot == "p3"] <- 0
  expect_identical(mcg_select(r, ids[1:2]), 3L)      # only the selection plots count
  expect_identical(mcg_select(r, ids[3]), 2L)
  expect_error(mcg_select(r[!(r$config_id == 2 & r$plot == "p1"), ], ids), "every configuration")
  r2 <- rbind(r, transform(r, rung = "4"))
  expect_error(mcg_select(r2, ids), "one rung")
})

test_that("grid ties go to no spacing condition, then to the higher spacing_min", {
  g <- mcg_grid()
  ids <- c("A::p1", "A::p2", "B::p3")
  for (lab in c("z5_s0.75_c0.6_e1", "z0_s0.5_c0.8_e0", "z8_s0.9_c0_e1")) {
    base <- g[g$label == lab, ]
    blk <- g[g$spacing_min > 0 & g$zmin == base$zmin & g$min_share == base$min_share &
               g$cover_min == base$cover_min & g$surface_exempt == base$surface_exempt, ]
    expect_identical(blk$spacing_min, c(9, 8.5, 8, 7.5, 7))
    expect_identical(diff(blk$config_id), rep(1L, 4))
    expect_true(all(blk$config_id > base$config_id))
    # every configuration of the family scores the same: grid_rows gives
    # config_id k to the k-th entry, so map those ids onto the grid's
    tied <- function(cid) {
      r <- grid_rows(rep(5, length(cid)), ids)
      r$config_id <- cid[r$config_id]
      r
    }
    expect_identical(mcg_select(tied(c(rev(blk$config_id), base$config_id)), ids), base$config_id)
    expect_identical(mcg_select(tied(rev(blk$config_id)), ids), blk$config_id[1])  # spacing 9
    expect_identical(mcg_select(tied(blk$config_id[3:5]), ids), blk$config_id[3])  # spacing 8
  }
})

test_that("mcg_split is deterministic and stratified per site", {
  rows <- data.frame(site = rep(c("A", "B"), c(8, 5)), plot = c(paste0("A_", 1:8), paste0("B_", 1:5)),
                     plotType = c(rep(c("tower", "distributed"), each = 4), rep("distributed", 5)),
                     n_dominant = 10, n_codominant = 0, n_intermediate = 0, n_suppressed = 0,
                     stringsAsFactors = FALSE)
  set.seed(42); before <- runif(1); set.seed(42)
  s1 <- mcg_split(rows, seed = 1)
  expect_identical(runif(1), before)                   # caller's RNG untouched
  expect_identical(names(s1), c("site", "plot", "split"))
  s2 <- mcg_split(rows[c(13:1, 1:13), ], seed = 1)     # order and duplicates do not matter
  expect_identical(s1, s2)
  expect_identical(table(s1$site, s1$split)["A", "calib"], 4L)   # 2 of 4 per plotType
  expect_identical(table(s1$site, s1$split)["B", "calib"], 3L)   # ceiling(0.5 * 5)
  ta <- s1[s1$site == "A", ]
  expect_identical(sum(ta$split == "calib" & ta$plot %in% paste0("A_", 1:4)), 2L)
  a <- assign_split(plot_table(rows[rows$site == "B", ]), 1, 0.5)
  expect_identical(s1$split[s1$site == "B"], a$split)
  expect_false(identical(mcg_split(rows, seed = 2)$split, s1$split) &&
               identical(mcg_split(rows, seed = 3)$split, s1$split))
  expect_error(mcg_split(rows[, -3], 1), "plotType")
})

# Plots of two sites whose counts differ widely from plot to plot, so the rates
# of one resample differ from those of another; config "b" plus `gain` true
# positives (and core true positives) on every plot is config "a".
paired_rows <- function(gain = 0) {
  base <- data.frame(site = rep(c("A", "B"), each = 4), plot = paste0("p", 1:8),
                     n_ref = c(4, 40, 10, 60, 6, 30, 50, 12),
                     TP = c(3, 8, 9, 15, 5, 6, 45, 2), stringsAsFactors = FALSE)
  base$n_det <- base$n_ref + c(2, 10, 1, 20, 0, 15, 5, 8)
  base$tp_core <- base$TP
  one <- function(config, g) do.call(rbind, lapply(seq_len(nrow(base)), function(i) {
    b <- base[i, ]
    cbind(data.frame(site = b$site, plot = b$plot, rung = "native", config = config,
                     stringsAsFactors = FALSE),
          count_row(n_ref = b$n_ref, n_det = b$n_det, TP = b$TP + g, tp_core = b$tp_core + g,
                    n_det0 = b$n_det, TP0 = 0.2 * b$n_ref, tp_core0 = 0.15 * b$n_det))
  }))
  rbind(one("a", gain), one("b", 0))
}

test_that("mcg_contrast pairs the resamples of both configurations", {
  ids <- paste0(rep(c("A", "B"), each = 4), "::p", 1:8)
  # identical rows but plots of different sizes and rates: paired draws give
  # exactly zero, unpaired ones would not
  same <- mcg_contrast(paired_rows(0), ids, "a", "b", n_boot = 300, seed = 1)
  expect_identical(same$metric, c("cF1", "F1", "cPrecision", "cRecall", "precision", "recall",
                                  "det_per_ref"))
  expect_true(all(is.finite(same$estimate_a)))
  expect_true(all(same$difference == 0 & same$lower == 0 & same$upper == 0))
  # one more true positive on every plot: every paired draw improves
  r <- paired_rows(1)
  up <- mcg_contrast(r, ids, "a", "b", n_boot = 300, seed = 1)
  for (m in c("recall", "precision", "F1", "cF1", "cRecall", "cPrecision"))
    expect_gt(up$lower[up$metric == m], 0)
  rec <- up[up$metric == "recall", ]
  expect_equal(rec$difference, 8 / 212)
  # the same improvement scored with independent resamples straddles zero, and
  # the paired interval is much narrower than either configuration's own spread
  W1 <- mt_plot_weights(sub("::.*", "", ids), sub(".*::", "", ids), 300, 1)
  W2 <- mt_plot_weights(sub("::.*", "", ids), sub(".*::", "", ids), 300, 2)
  b <- r[r$config == "b", ]
  b <- b[match(rownames(W1), paste(b$site, b$plot, sep = "::")), ]
  recall_of <- function(W, g) drop(crossprod(W, b$TP + g)) / drop(crossprod(W, b$n_ref))
  unpaired <- mt_interval(recall_of(W1, 1) - recall_of(W2, 0))
  expect_lt(unpaired$lower, 0)
  own <- mt_interval(recall_of(W1, 0))
  expect_lt(rec$upper - rec$lower, 0.25 * (own$upper - own$lower))
  # the interval is the one computed by hand from the same weight matrix, and
  # each configuration's counts stay aligned with their plots whatever the row order
  paired <- mt_interval(recall_of(W1, 1) - recall_of(W1, 0))
  expect_equal(c(rec$lower, rec$upper), c(paired$lower, paired$upper))
  mixed <- rbind(r[r$config == "a", ][c(8, 3, 1, 6, 2, 7, 5, 4), ],
                 r[r$config == "b", ][c(2, 5, 8, 1, 4, 3, 7, 6), ])
  expect_identical(mcg_contrast(mixed, ids, "a", "b", n_boot = 300, seed = 1), up)
})

test_that("mcg_contrast is signed by the better configuration", {
  ids <- c("A::p1", "A::p2", "B::p3")
  r <- grid_rows(c(5, 5, 8))
  better <- mcg_contrast(r, ids, "c3", "stock", n_boot = 200, seed = 1)
  b <- better[better$metric == "F1", ]
  expect_equal(b$estimate_a, 0.8); expect_equal(b$estimate_b, 0.5)
  expect_equal(b$difference, 0.3)
  expect_true(b$lower > 0 && b$upper > 0)
  expect_true(all(mcg_contrast(r, ids, "stock", "c3", n_boot = 200, seed = 1)$upper[1:2] < 0))
  pooled <- attr(better, "pooled")
  expect_identical(pooled$config, c("c3", "stock"))
  expect_equal(pooled$TP, c(24, 15))
  # identical resamples: the same seed gives the same interval
  expect_identical(better, mcg_contrast(r, ids, "c3", "stock", n_boot = 200, seed = 1))
  expect_error(mcg_contrast(r[!(r$config == "c3" & r$plot == "p1"), ], ids, "c3", "stock",
                            n_boot = 10), "cover each")
})

# Two sites whose contrast a - b differs in sign: config "a" is config "b" plus
# `gain` true positives (and core true positives) per plot, gains on site A's
# plots and losses on site B's.
region_rows <- function() {
  base <- data.frame(site = rep(c("A", "B"), c(5, 4)), plot = paste0("q", 1:9),
                     n_ref = c(12, 30, 8, 45, 20, 25, 6, 40, 15),
                     TP = c(8, 14, 5, 30, 9, 15, 2, 22, 10), stringsAsFactors = FALSE)
  base$n_det <- base$n_ref + c(3, 6, 0, 10, 4, 5, 2, 12, 1)
  one <- function(config, gain) do.call(rbind, lapply(seq_len(nrow(base)), function(i) {
    b <- base[i, ]
    cbind(data.frame(site = b$site, plot = b$plot, rung = "native", config = config,
                     stringsAsFactors = FALSE),
          count_row(n_ref = b$n_ref, n_det = b$n_det, TP = b$TP + gain[i],
                    tp_core = b$TP + gain[i], n_det0 = b$n_det, TP0 = 0.2 * b$n_ref,
                    tp_core0 = 0.15 * b$n_det))
  }))
  rbind(one("a", c(2, 3, 1, 4, 2, 0, -1, -3, -2)), one("b", rep(0, 9)))
}

test_that("mcg_contrast_difference compares a contrast between two plot sets on shared resamples", {
  r <- region_rows()
  ids <- paste(r$site, r$plot, sep = "::")[r$config == "a"]
  p1 <- ids[startsWith(ids, "A::")]; p2 <- ids[startsWith(ids, "B::")]
  d <- mcg_contrast_difference(r, p1, p2, "a", "b", n_boot = 300, seed = 1)
  expect_identical(d$metric, c("cF1", "F1", "cPrecision", "cRecall", "precision", "recall",
                               "det_per_ref"))
  expect_identical(c(d$n_plots_1[1], d$n_plots_2[1]), c(5L, 4L))
  # each set's estimate is the contrast on that set alone
  expect_equal(d$difference_1, mcg_contrast(r, p1, "a", "b", n_boot = 300, seed = 1)$difference)
  expect_equal(d$difference_2, mcg_contrast(r, p2, "a", "b", n_boot = 300, seed = 1)$difference)
  expect_equal(d$difference, d$difference_1 - d$difference_2)
  rec <- d[d$metric == "recall", ]
  expect_equal(c(rec$difference_1, rec$difference_2), c(12 / 115, -6 / 86))
  # recall by hand: one weight matrix over the union, each set from its own rows
  W <- mt_plot_weights(sub("::.*", "", ids), sub("^[^:]*::", "", ids), 300, 1)
  at <- function(config) {
    x <- r[r$config == config, ]
    x[match(rownames(W), paste(x$site, x$plot, sep = "::")), ]
  }
  ra <- at("a"); rb <- at("b"); in1 <- rownames(W) %in% p1
  recall_of <- function(x, k) drop(crossprod(W[k, , drop = FALSE], x$TP[k])) /
    drop(crossprod(W[k, , drop = FALSE], x$n_ref[k]))
  hand <- mt_interval((recall_of(ra, in1) - recall_of(rb, in1)) -
                        (recall_of(ra, !in1) - recall_of(rb, !in1)))
  expect_equal(c(rec$lower, rec$upper, rec$defined_draws),
               c(hand$lower, hand$upper, hand$defined_draws))
  expect_gt(rec$lower, 0)
  # swapping the sets negates the difference and mirrors the interval
  s <- mcg_contrast_difference(r, p2, p1, "a", "b", n_boot = 300, seed = 1)
  expect_equal(s$difference, -d$difference)
  expect_equal(s$lower, -d$upper); expect_equal(s$upper, -d$lower)
  # the row order does not matter
  shuffled <- r[c(18, 3, 11, 7, 1, 15, 9, 13, 5, 2, 17, 8, 12, 4, 16, 6, 10, 14), ]
  expect_identical(mcg_contrast_difference(shuffled, p1, p2, "a", "b", n_boot = 300, seed = 1), d)
  cd <- function(rows = r, plots_1 = p1, plots_2 = p2, ...)
    mcg_contrast_difference(rows, plots_1, plots_2, "a", "b", n_boot = 300, seed = 1, ...)
  expect_error(cd(plots_2 = c(p2, p1[1])), "disjoint")
  expect_error(cd(plots_2 = character()), "both plot sets")
  expect_error(cd(rows = rbind(r, transform(r, rung = "4"))), "one rung at a time")
  expect_error(cd(metrics = c("recall", "accuracy")), "unknown metrics")
  expect_error(cd(rows = r[!(r$config == "b" & r$plot == "q7"), ]), "must cover each of the")
})
