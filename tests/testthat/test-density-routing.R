# Unit tests for density_routing_lib.R: bands of measured density, the
# selection rule, routed cells, per-plot pooling under the master tables' plot
# resamples, corrected F1 and paired differences. Synthetic counts only.
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "density_routing_lib.R"), local = TRUE)

# Two sites, three plots, two levels; plot p1 is dense at native density
# (band A) and plot p3 below 2 pulses/m² even at native density (band C).
dr_fix <- function() {
  cell <- data.frame(site = c("S", "S", "T", "S", "S", "T"),
                     plot = c("p1", "p2", "p3", "p1", "p2", "p3"),
                     level = rep(c("native", "1"), each = 3),
                     frdens = c(9, 5, 1.5, 1.2, 0.8, 0.5), stringsAsFactors = FALSE)
  cell$band <- dr_band(cell$frdens)
  arms <- c("x", "y")
  out <- do.call(rbind, lapply(c("baseline", "null"), function(v) do.call(rbind, lapply(arms,
    function(a) {
      k <- seq_len(nrow(cell)) + if (a == "y") 2 else 0
      tp <- if (v == "baseline") k else k / 4
      data.frame(variant = v, cell, detector = a, TP = tp, n_ref = 10,
                 n_det = 12 + k, tp_core = tp, stringsAsFactors = FALSE)
    }))))
  out
}

test_that("bands follow the QL1 and QL2 floors of measured first-return density", {
  expect_identical(dr_band(c(20, 8, 7.999, 2, 1.999, 0)), c("A", "A", "B", "B", "C", "C"))
  expect_error(dr_band(c(3, NA)), "finite")
  expect_error(dr_band(-1), "non-negative")
  expect_error(dr_band(numeric()), "finite")
})

test_that("the pick is the highest score among the candidates, with no tie-break", {
  sc <- data.frame(band = rep(c("A", "B"), each = 3), detector = rep(c("x", "y", "z"), 2),
                   F1 = c(0.40, 0.45, 0.50, 0.30, 0.20, 0.10), stringsAsFactors = FALSE)
  p <- dr_pick(sc, c("x", "y", "z"))
  expect_identical(p$pick, c("z", "x"))
  expect_identical(p$runner_up, c("y", "y"))
  expect_equal(p$margin, c(0.05, 0.10))
  expect_identical(dr_pick(sc, c("x", "y"))$pick, c("y", "x"))       # candidates restrict
  one <- dr_pick(sc, "x")
  expect_identical(one$pick, c("x", "x")); expect_true(all(is.na(one$runner_up)))
  tie <- transform(sc, F1 = c(0.5, 0.5, 0.1, 0.3, 0.2, 0.1))
  expect_error(dr_pick(tie, c("x", "y", "z")), "Tie")
  expect_error(dr_pick(sc[-1, ], c("x", "y", "z")), "every candidate")
  expect_error(dr_pick(transform(sc, F1 = replace(F1, 2, NA)), c("x", "y", "z")), "Undefined")
})

test_that("a route takes, in every cell, the detector its band is routed to", {
  x <- dr_fix()
  picks <- data.frame(band = c("A", "B", "C"), pick = c("y", "x", "y"), stringsAsFactors = FALSE)
  r <- dr_route_cells(x, picks, "route")
  expect_equal(nrow(r), nrow(x) / 2)                       # one detector per cell and variant
  expect_true(all(r$detector == c(A = "y", B = "x", C = "y")[r$band]))
  expect_true(all(r$policy == "route"))
  expect_error(dr_route_cells(x, picks[-3, ], "route"), "No pick for band C")
  expect_error(dr_route_cells(x[!(x$detector == "x" & x$band == "B"), ], picks, "route"),
               "exactly one row")
})

test_that("per-plot rows sum a plot's cells and zero-fill plots without cells", {
  x <- dr_fix()[dr_fix()$variant == "baseline" & dr_fix()$detector == "x", ]
  W <- mt_plot_weights(x$site, x$plot, n_boot = 50, seed = 11)
  rows <- dr_plot_rows(transform(x, policy = "x", slice = band), c("policy", "slice"),
                       rownames(W))
  expect_equal(nrow(rows), 3 * nrow(W))                   # three bands x three plots
  c_rows <- rows[rows$slice == "C", ]
  # Band C: p1 and p2 at level 1 (k = 4, 5) and p3 at both levels (k = 3, 6).
  expect_equal(c_rows$TP[match(c("p1", "p2", "p3"), c_rows$plot)], c(4, 5, 9))
  expect_equal(c_rows$n_ref[match(c("p1", "p2", "p3"), c_rows$plot)], c(10, 10, 20))
  a_rows <- rows[rows$slice == "A", ]
  expect_equal(a_rows$TP[match(c("p1", "p2", "p3"), a_rows$plot)], c(1, 0, 0))
  expect_error(dr_plot_rows(x, "band", "S::p1"), "outside")
  s <- mt_boot_scores(rows, W, c("policy", "slice"))
  xc <- x[x$band == "C", ]
  expect_equal(s$estimate$recall[s$groups == "x|C"], sum(xc$TP) / sum(xc$n_ref))
  # Under a resample a plot's cells move together: draw 1 by hand.
  w <- W[paste(xc$site, xc$plot, sep = "::"), 1]
  expect_equal(unname(s$draws$recall[1, "x|C"]), sum(w * xc$TP) / sum(w * xc$n_ref))
})

test_that("corrected F1 scales the excess over the null, per draw, and contrasts are paired", {
  x <- dr_fix()
  x$policy <- x$detector; x$slice <- "all"
  W <- mt_plot_weights(x$site, x$plot, n_boot = 100, seed = 5)
  s <- mt_boot_scores(dr_plot_rows(x, c("variant", "policy", "slice"), rownames(W)), W,
                      c("variant", "policy", "slice"))
  # By hand: x holds TP = tp_core = 1 + ... + 6 = 21 observed and 21 / 4 under
  # the null, of n_ref = 60 stems and n_det = 93 detections in both, so F1 =
  # 2 TP / (n_ref + n_det) is 42 / 153 = 14 / 51 observed and 10.5 / 153 =
  # 7 / 102 under the null, and corrected F1 (14 / 51 - 7 / 102) /
  # (1 - 7 / 102) = 21 / 95.
  obs <- dr_metric(s, "x|all", "F1"); nul <- dr_metric(s, "x|all", "F1_null")
  cor <- dr_metric(s, "x|all", "F1_corrected")
  expect_equal(obs$e, 14 / 51)
  expect_equal(nul$e, 7 / 102)                            # the null variant's counts
  expect_equal(cor$e, 21 / 95)
  # Draw 1 by hand: each cell's counts weighted by its plot's multiplicity.
  w <- W[paste(x$site, x$plot, sep = "::"), 1]
  f1_draw <- function(v) {
    z <- x$variant == v & x$detector == "x"
    2 * sum(w[z] * x$TP[z]) / sum(w[z] * (x$n_ref[z] + x$n_det[z]))
  }
  expect_equal(unname(cor$d[1]),
               (f1_draw("baseline") - f1_draw("null")) / (1 - f1_draw("null")))
  expect_equal(cor$d, (obs$d - nul$d) / (1 - nul$d))
  rec <- sum(x$TP[x$variant == "null" & x$detector == "x"]) / sum(x$n_ref[x$variant == "null" & x$detector == "x"])
  expect_equal(dr_metric(s, "x|all", "recall")$e,
               sum(x$TP[x$variant == "baseline" & x$detector == "x"]) / 60)
  expect_equal(s$estimate$recall[s$groups == "null|x|all"], rec)
  same <- dr_contrast(s, "x|all", "x|all", "F1_corrected")
  expect_equal(c(same$estimate, same$lower, same$upper), c(0, 0, 0))
  d <- dr_contrast(s, "y|all", "x|all", "F1")
  expect_equal(d$estimate, dr_metric(s, "y|all")$e - obs$e)
  expect_gt(d$lower, 0)                                   # y holds more TP in every plot
  e <- dr_estimate(s, "x|all", "F1_corrected")
  expect_true(e$lower <= e$estimate && e$estimate <= e$upper)
  expect_error(dr_metric(s, "z|all"), "Unknown group")
})

test_that("a route pools the summed counts of its picks, not their band scores", {
  x <- dr_fix()[dr_fix()$variant == "baseline", ]
  picks <- data.frame(band = c("A", "B", "C"), pick = c("y", "x", "y"), stringsAsFactors = FALSE)
  r <- dr_route_cells(x, picks, "route")
  W <- mt_plot_weights(x$site, x$plot, n_boot = 20, seed = 2)
  s <- mt_boot_scores(dr_plot_rows(transform(r, slice = "all"), c("policy", "slice"), rownames(W)),
                      W, c("policy", "slice"))
  expect_equal(s$estimate$recall, sum(r$TP) / sum(r$n_ref))
  expect_equal(s$estimate$precision, sum(r$tp_core) / sum(r$n_det))
})

test_that("agreement with a reference table is exact up to the tolerance", {
  a <- data.frame(k = c("x", "y"), v = c(0.5, 0.25))
  expect_equal(nrow(dr_mismatch(a, transform(a, v = v + 1e-12), "k", "v")), 0L)
  expect_equal(dr_mismatch(a, transform(a, v = c(0.5, 0.26)), "k", "v")$k, "y")
  expect_equal(dr_mismatch(a, a[1, ], "k", "v")$k, "y")    # a missing row is a mismatch
})

test_that("formatting uses the minus sign and a dash for undefined values", {
  expect_identical(dr_fmt(-0.0126, -0.031, 0.0098, TRUE), "−0.013 [−0.031, +0.010]")
  expect_identical(dr_fmt(0.5, 0.4, 0.6), "0.500 [0.400, 0.600]")
  expect_identical(dr_fmt(NA, NA, NA), "—")
})
