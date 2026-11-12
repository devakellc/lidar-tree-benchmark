# Unit tests for the multichm_gated arm library: the instrumented multichm
# candidate search (parity with lidRplugins::multichm), the first-return share
# and canopy cover, the gate, the distance filter, the calibration grid and the
# count-pooling, selection, split and contrast helpers. Synthetic data only.
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

## ---- configuration ------------------------------------------------------------------------
test_that("configurations are validated and labelled", {
  expect_identical(MCG_STOCK, list(zmin = 0, min_share = 0, cover_min = 0, surface_exempt = FALSE))
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
  expect_identical(MCG_DECLARED, mcg_config(5, 0.75, 0.6, TRUE))
  expect_identical(.mcg_check_config(MCG_DECLARED), MCG_DECLARED)
  expect_false(identical(MCG_DECLARED, MCG_STOCK))
  g <- mcg_grid()
  row <- g[g$label == mcg_config_label(MCG_DECLARED), , drop = FALSE]
  expect_identical(nrow(row), 1L)
  expect_identical(list(zmin = row$zmin, min_share = row$min_share, cover_min = row$cover_min,
                        surface_exempt = row$surface_exempt), MCG_DECLARED)
  expect_false(row$config_id == 1L)
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
  expect_false(anyNA(C$ztop))
  expect_true(all(C$ztop >= C$Z))                             # a cell's top is above its p95
  expect_true(all(sort(unique(C$layer)) == seq_len(max(C$layer))))
  P <- mcg_prepare(las, 0.5)
  expect_identical(names(P$cand), c("X", "Y", "Z", "layer", "ztop", "share"))
  expect_true(all(is.na(P$cand$share) | (P$cand$share >= 0 & P$cand$share <= 1)))
  expect_equal(P$cover, mcg_canopy_cover(las))
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

## ---- the gate -------------------------------------------------------------------------------
test_that("the height floor applies to deeper layers only, in every stand", {
  C <- cands(X = 1:4, Y = 0, Z = c(9, 4.9, 5, 3), layer = c(2, 2, 3, 1))
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
  expect_true(all(is.na(P$cand$share)))
  expect_error(mcg_apply(P, mcg_config(min_share = 0.5)), "ReturnNumber")
  expect_error(mcg_apply(P, mcg_config(cover_min = 0.7, surface_exempt = TRUE)), "canopy cover")
  expect_error(mcg_apply(P, mcg_config(5, 0.75, 0.7, TRUE)), "ReturnNumber")
  for (cfg in list(MCG_STOCK, mcg_config(zmin = 5), mcg_config(surface_exempt = TRUE),
                   mcg_config(zmin = 5, cover_min = 0.7)))
    expect_true(assert_detection_contract(mcg_apply(P, cfg)))
  P1 <- mcg_prepare(synth_stand(1), 0.5)
  expect_identical(mcg_apply(P, MCG_STOCK), mcg_apply(P1, MCG_STOCK))
})

## ---- the calibration grid -------------------------------------------------------------------
test_that("the declared grid has 87 unique rows, stock first, least intervention first", {
  g <- mcg_grid()
  expect_identical(nrow(g), 87L)
  expect_identical(names(g), c("config_id", "zmin", "min_share", "cover_min", "surface_exempt",
                               "label"))
  expect_identical(g$config_id, seq_len(87))
  expect_identical(g$label[1], "stock")
  expect_identical(anyDuplicated(g$label), 0L)
  expect_identical(anyDuplicated(g[c("zmin", "min_share", "cover_min", "surface_exempt")]), 0L)
  expect_false(any(g$min_share == 0 & !g$surface_exempt & g$cover_min > 0))
  expect_identical(sum(!g$surface_exempt), 39L)
  expect_identical(order(g$surface_exempt, g$min_share, g$zmin, -g$cover_min), seq_len(87))
  expect_setequal(unique(g$zmin), c(0, 5, 8))
  expect_setequal(unique(g$min_share), c(0, 0.5, 0.75, 0.9))
  expect_setequal(unique(g$cover_min), c(0, 0.6, 0.7, 0.8))
  expect_identical(g$cover_min[2:5], c(0, 0, 0.8, 0.7))   # z5, z8, then z0 s0.5 c0.8, c0.7
  expect_identical(g$label[40], "z0_s0_c0.8_e1")
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
