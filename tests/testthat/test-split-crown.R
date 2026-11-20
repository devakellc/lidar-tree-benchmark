# Unit tests for split_crown_lib.R: close-pair finding, the canopy valley test,
# split-crown candidates per cell and pooling by summed counts under plot
# resamples (split_crown_diagnostic.R). All synthetic; no NEON data.
source(file.path("..", "..", "scripts", "split_crown_lib.R"), local = TRUE)

# Brute-force reference for sc_pairs.
brute_pairs <- function(x, y, rmin, rmax, keep = rep(TRUE, length(x))) {
  out <- list()
  for (i in seq_along(x)) for (j in seq_along(x)) if (i < j) {
    dd <- sqrt((x[i] - x[j])^2 + (y[i] - y[j])^2)
    if (dd >= rmin && dd <= rmax && (keep[i] || keep[j])) out[[length(out) + 1]] <- c(i, j)
  }
  if (!length(out)) return(matrix(integer(), 0, 2))
  do.call(rbind, out)
}

# Two conical crowns on a flat ground: apexes (0, 0) at 20 m and (5, 0) at 18 m,
# each falling 3 m per metre from its apex, so the canopy between them dips to
# the crossing of the two cones.
cone_canopy <- function(x, y) pmax(0, 20 - 3 * sqrt(x^2 + y^2), 18 - 3 * sqrt((x - 5)^2 + y^2))

test_that("close pairs are exactly the pairs in the annulus, as a brute force finds them", {
  set.seed(11)
  x <- runif(150, 0, 30); y <- runif(150, 0, 30)
  keep <- runif(150) < 0.5
  p <- sc_pairs(x, y, 1.5, 4, keep)
  b <- brute_pairs(x, y, 1.5, 4, keep)
  expect_equal(nrow(p), nrow(b))
  expect_equal(paste(p$i, p$j), paste(b[, 1], b[, 2])[order(b[, 1], b[, 2])])
  expect_true(all(p$i < p$j))
  expect_true(all(p$dist >= 1.5 & p$dist <= 4))
  expect_equal(p$dist, sqrt((x[p$i] - x[p$j])^2 + (y[p$i] - y[p$j])^2))
  # Boundaries are inclusive; points closer than rmin or beyond rmax are not pairs.
  q <- sc_pairs(c(0, 1.5, 0, 10, 10.5), c(0, 0, 4, 0, 0), 1.5, 4)
  expect_equal(paste(q$i, q$j), c("1 2", "1 3"))      # 2-3 is 4.27 m, 4-5 0.5 m
  expect_equal(nrow(sc_pairs(c(0, 1), c(0, 0), 1.5, 4)), 0L)
  expect_equal(nrow(sc_pairs(0, 0)), 0L)
  # A pair counts when at least one end is kept.
  expect_equal(nrow(sc_pairs(c(0, 2, 20), c(0, 0, 0), keep = c(FALSE, TRUE, FALSE))), 1L)
  expect_equal(nrow(sc_pairs(c(0, 2), c(0, 0), keep = c(FALSE, FALSE))), 0L)
  expect_identical(sc_has_neighbour(c(0, 2, 20), c(0, 0, 0)), c(TRUE, TRUE, FALSE))
})

test_that("the valley depth is the lower end minus the lowest canopy between the ends", {
  v <- sc_valley(0, 0, 5, 0, cone_canopy)
  # The cones cross at 20 - 3x = 18 - 3(5 - x), x = 2.833, height 11.5.
  expect_equal(v$top1, 20); expect_equal(v$top2, 18); expect_equal(v$lower_top, 18)
  expect_true(v$floor >= 11.5 && v$floor < 11.7)      # sampled every 0.125 m
  expect_equal(v$depth, 18 - v$floor)
  expect_true(v$valid)
  # A second detection on the flank of one crown: the profile only rises from it.
  f <- sc_valley(0, 0, 2.5, 0, function(x, y) pmax(0, 20 - 3 * sqrt(x^2 + y^2)))
  expect_equal(f$depth, 0)
  expect_equal(f$lower_top, 12.5)
  # The order of the ends does not matter.
  expect_equal(sc_valley(5, 0, 0, 0, cone_canopy)$depth, v$depth)
})

test_that("empty cells are skipped, the ends fall back to the nearest valid sample, and sparse profiles get no verdict", {
  holes <- function(x, y) ifelse(x < 0.3, NA, cone_canopy(x, y))     # first samples off the model
  h <- sc_valley(0, 0, 5, 0, holes)
  expect_true(h$valid)
  expect_lt(h$top1, 20)                       # the nearest valid sample, below the apex
  expect_equal(h$top1, cone_canopy(0.375, 0))
  sparse <- function(x, y) ifelse(x < 4, NA, cone_canopy(x, y))      # 9 of 41 samples
  s <- sc_valley(0, 0, 5, 0, sparse)
  expect_false(s$valid); expect_true(is.na(s$depth)); expect_true(is.na(s$lower_top))
  none <- sc_valley(0, 0, 5, 0, function(x, y) rep(NA_real_, length(x)))
  expect_false(none$valid); expect_equal(none$n_valid, 0L)
  expect_equal(nrow(sc_valley(numeric(), numeric(), numeric(), numeric(), cone_canopy)), 0L)
})

test_that("no valley holds at absolute and relative thresholds, never without a verdict", {
  expect_identical(sc_no_valley(c(0, 0.9, 1.1, NA), c(20, 20, 20, 20), "abs", 1),
                   c(TRUE, TRUE, FALSE, FALSE))
  # 10% of a 20 m lower end is 2 m; of a 5 m one, 0.5 m.
  expect_identical(sc_no_valley(c(1.9, 2.1, 0.6), c(20, 20, 5), "rel", 0.10), c(TRUE, FALSE, FALSE))
  expect_identical(sc_no_valley(0, NA, "rel", 0.1), TRUE)
})

test_that("a cell counts close pairs, valleys and split-crown candidates", {
  # Crown A: apex (0, 0) at 20 m; crown B: apex (6, 0) at 18 m; both fall 3 m per
  # metre, so between them the canopy dips to 10 m at x = 3.33.
  # 1: matched, A's apex; 2: unmatched on A's flank, 2.5 m from 1 (no valley);
  # 3: unmatched, B's apex, 3.5 m from 2 across the dip; 4: unmatched on A, 1 m
  # from 1 (too close for a pair) and 1.5 m from 2; 5: matched, outside the
  # focus, on A 3 m from 1; 6: unmatched, far away and beneath the canopy.
  canopy <- function(x, y) pmax(0, 20 - 3 * sqrt(x^2 + y^2), 18 - 3 * sqrt((x - 6)^2 + y^2),
                                ifelse(abs(x - 30) < 1 & abs(y) < 1, 25, 0))
  det <- data.frame(x = c(0, 2.5, 6, 1, 0, 30), y = c(0, 0, 0, 0, 3, 0),
                    z = c(20, 12.5, 18, 17, canopy(0, 3), 5))
  focus <- c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE)
  matched <- c(TRUE, FALSE, FALSE, FALSE, TRUE, FALSE)
  thr <- sc_thresholds(abs = 1, rel = numeric())
  out <- sc_cell(det, focus, matched, canopy, thr)
  k <- out$counts
  expect_equal(nrow(k), 1L)
  expect_equal(k$n_det, 5); expect_equal(k$TP, 2); expect_equal(k$tp_core, 1); expect_equal(k$n_fp, 4)
  pr <- paste(out$pairs$i, out$pairs$j)
  expect_setequal(pr, c("1 2", "1 5", "2 3", "2 4", "2 5", "4 5"))
  expect_equal(k$n_pairs, 6); expect_equal(k$n_pairs_valid, 6)
  expect_equal(k$n_close, 4)                  # 1, 2, 3 and 4 have a neighbour 1.5-4 m away
  expect_equal(k$n_near, 2)                   # 1 and 4 are 1 m apart
  # Unmatched focus detections 1.5-4 m from a matched one: 2 (from 1 and 5), 4 (from 5).
  expect_equal(k$n_split_any, 2)
  # Valleys: 2-3 crosses the dip (12.5 m down to 10 m); the other pairs stay on A.
  d <- setNames(out$pairs$depth, pr)
  expect_true(d[["2 3"]] > 2.3 && d[["2 3"]] <= 2.5)   # sampled every 0.0875 m
  expect_equal(unname(d[c("1 2", "1 5", "2 4", "2 5", "4 5")]), rep(0, 5), tolerance = 1e-9)
  expect_equal(k$n_pairs_novalley, 5); expect_equal(k$n_pairs_novalley_sub, 0)
  expect_equal(k$n_split, 2)                  # 2 and 4 lie on crown A with 1 or 5
  expect_equal(k$n_split_parents, 2)          # 1 and 5
  expect_equal(k$n_matched_pairs, 1)          # 1-5
  expect_equal(k$n_matched_pairs_novalley, 1)
  expect_equal(k$n_split_surface, 2)
  # A threshold above the dip calls 2-3 one crown too; 3 is unmatched, so the
  # candidates do not change.
  k3 <- sc_cell(det, focus, matched, canopy, sc_thresholds(abs = 3, rel = numeric()))$counts
  expect_equal(k3$n_pairs_novalley, 6); expect_equal(k3$n_split, 2)
  # Without the canopy every pair counts as one crown.
  k0 <- sc_cell(det, focus, matched, NULL, thr)$counts
  expect_equal(k0$n_pairs_novalley, 6); expect_equal(k0$n_split, k0$n_split_any)
  # Making 4 a deep sub-canopy detection moves it out of the surface count.
  det$z[4] <- 5
  expect_equal(sc_cell(det, focus, matched, canopy, thr)$counts$n_split_surface, 1)
  # A detection beyond a deep valley is not a split-crown candidate.
  far <- data.frame(x = c(0, 3.5), y = c(0, 0), z = c(20, 18))
  two <- function(x, y) pmax(0, 20 - 6 * abs(x), 18 - 6 * abs(x - 3.5))
  kf <- sc_cell(far, c(TRUE, TRUE), c(TRUE, FALSE), two, thr)$counts
  expect_equal(kf$n_split_any, 1); expect_equal(kf$n_split, 0); expect_equal(kf$n_pairs_novalley, 0)
  expect_error(sc_cell(det, focus[-1], matched, canopy, thr), "one flag")
  # An empty cell gives zero counts.
  ke <- sc_cell(det[0, ], logical(), logical(), canopy, thr)$counts
  expect_equal(ke$n_det, 0); expect_equal(ke$n_pairs, 0)
})

test_that("the reference stems' own close pairs count focus stems only", {
  r <- sc_reference_counts(c(0, 2, 10, 11, 30), c(0, 0, 0, 0, 0), c(TRUE, FALSE, TRUE, TRUE, TRUE))
  expect_equal(r$n_det, 4)
  expect_equal(r$n_close, 1)                  # stem 1 (its neighbour 2 is not in the focus)
  expect_equal(r$n_near, 2)                   # 10 and 11
})

test_that("pooling sums counts over plots, not per-plot rates, under the resamples", {
  rows <- data.frame(site = "S", plot = c("a", "b", "a", "b"), detector = c("x", "x", "y", "y"),
                     n_split = c(1, 9, 0, 0), TP = c(10, 10, 1, 9))
  W <- cbind(c(1, 1), c(2, 0), c(0, 2))
  rownames(W) <- c("S::a", "S::b")
  b <- sc_boot(rows, W, "detector", c("n_split", "TP"))
  r <- sc_ratio(b, "n_split", "TP")
  expect_equal(unname(r$e), c(0.5, 0))         # (1 + 9) / 20, not the mean of 0.1 and 0.9 (also 0.5)
  rows$TP[2] <- 30
  r <- sc_ratio(sc_boot(rows, W, "detector", c("n_split", "TP")), "n_split", "TP")
  expect_equal(unname(r$e[1]), 10 / 40)        # the mean of rates would be 0.2
  expect_equal(unname(r$d[, 1]), c(10 / 40, 2 / 20, 18 / 60))
  expect_error(sc_boot(rows[-4, ], W, "detector", c("n_split", "TP")), "does not cover")
  expect_error(sc_boot(rbind(rows, rows[1, ]), W, "detector", c("n_split", "TP")), "Duplicate")
})

test_that("canopy heights are read from the nearest raster cell", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 2, ncols = 3, xmin = 0, xmax = 3, ymin = 0, ymax = 2, vals = 1:6)
  h <- sc_height_at(r)
  expect_equal(h(c(0.5, 2.5, 1.2), c(1.5, 0.5, 0.1)), c(1, 6, 5))
  expect_true(is.na(h(10, 10)))
})
