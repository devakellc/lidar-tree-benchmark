source(file.path("..", "..", "scripts", "sat_radius_check.R"), local = TRUE)

test_that("the scaled radius widens the grid cell to the point spacing", {
  expect_equal(sat_radius(25, 1.5), 0.3)           # spacing 0.2 m: the upstream 0.3 m
  expect_equal(sat_radius(100, 1.5), 0.3)          # denser than the grid: the grid
  expect_equal(sat_radius(2.25, 1.5), 1.0)         # spacing 2/3 m
  expect_equal(sat_radius(c(1, 4), 3), c(3, 1.5))
})

test_that("in_polygon finds points inside a hull", {
  vx <- c(0, 4, 4, 0); vy <- c(0, 0, 4, 4)
  expect_equal(in_polygon(c(1, 3, 5, -1, 2), c(1, 3, 2, 2, 4.5), vx, vy),
               c(TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_equal(in_polygon(c(3, 1), c(1, 5), c(0, 6, 3), c(0, 0, 6)), c(TRUE, FALSE))
})

test_that("pool sums counts and corrects F1 for the null", {
  x <- data.frame(TP = c(3, 1), n_ref = c(10, 5), tp_core = c(2, 1), n_det = c(4, 2),
                  null_TP = c(1, 0.5), null_tp_core = c(0.5, 0.5), null_n_det = c(4, 2))
  p <- pool(x)
  expect_equal(p[["recall"]], 4 / 15)
  expect_equal(p[["precision"]], 0.5)
  expect_equal(p[["F1"]], 8 / 23)
  expect_equal(p[["F1_null"]], 1 / 8)
  expect_equal(p[["F1_corr"]], 41 / 161)
  expect_equal(pool(transform(x, n_det = 0, tp_core = 0))[["F1"]], 0)
})

test_that("grouping_counts counts grouped tree points and multi-stem instances", {
  # Instance 1 spans two stems, instance 2 holds one, a third instance lies
  # outside the core; one tree point and one ground point are ungrouped.
  pts <- data.frame(
    X = c(1, 3, 1, 3, 2,   6, 7, 6.5,   30, 31, 30.5,   8, 9),
    Y = c(1, 1, 3, 3, 2,   6, 6, 7,     30, 30, 31,     1, 9),
    Z = 10,
    PredSemantic = c(rep(1L, 11), 1L, 0L),
    PredInstance = c(rep(1L, 5), rep(2L, 3), rep(3L, 3), 0L, 0L))
  las <- suppressWarnings(lidR::LAS(pts))
  las <- lidR::add_lasattribute(las, pts$PredSemantic, "PredSemantic", "semantic")
  las <- lidR::add_lasattribute(las, pts$PredInstance, "PredInstance", "instance")
  f <- tempfile(fileext = ".las"); on.exit(unlink(f))
  lidR::writeLAS(las, f)
  stems <- data.frame(E = c(1.5, 2.5, 6.5, 12), N = c(2, 2, 6.4, 12))
  g <- grouping_counts(f, cx = 5, cy = 5, ph = 10, stems = stems)
  expect_equal(g[["n_core"]], 10)
  expect_equal(g[["n_tree"]], 9)
  expect_equal(g[["n_tree_assigned"]], 8)
  expect_equal(g[["n_assigned"]], 8)
  expect_equal(g[["n_inst"]], 2)
  expect_equal(g[["n_inst_2stems"]], 1)
  expect_equal(g[["n_assigned_2stems"]], 5)
  expect_equal(g[["max_stems"]], 2)
})

test_that("log_ok wants the exact radius for a changed-radius job and none for the control", {
  f <- tempfile(); on.exit(unlink(f))
  writeLines(c("Input directory: /pilot/in", "sat_compat: region_grow radius 1.0181 m", "done"), f)
  expect_true(log_ok(f, "1.0181"))
  expect_false(log_ok(f, "1.4000"))
  expect_false(log_ok(f, ""))
  writeLines(c("Input directory: /pilot/in", "done"), f)
  expect_true(log_ok(f, ""))
  expect_false(log_ok(f, "1.0181"))
  expect_false(log_ok(file.path(tempdir(), "no-such.log"), ""))
})
