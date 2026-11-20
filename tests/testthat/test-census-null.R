# Unit tests for census_null_lib.R: the paper's chance-agreement null scored
# inside censused subplots (paper_census_null.R). All synthetic; no NEON data.
source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "census_null_lib.R"), local = TRUE)
suppressMessages(library(data.table))

f1 <- function(TP, n_ref, tp_core, n_det) {
  r <- TP / n_ref; p <- tp_core / n_det; 2 * r * p / (r + p)
}
cell <- function(variant, site, plot, arm, n_ref, n_det, TP, tp_core = TP, rung = "native")
  data.frame(variant = variant, site = site, plot = plot, rung = rung, detector = arm,
             n_ref = n_ref, n_det = n_det, TP = TP, tp_core = tp_core, stringsAsFactors = FALSE)
# Two sites (one per region), three plots, a baseline and one other arm.
synth_cells <- function() rbind(
  cell("observed", "SJER", c("SJER_1", "SJER_2"), "chm_vwf", c(10, 4), c(8, 5), c(6, 2)),
  cell("null", "SJER", c("SJER_1", "SJER_2"), "chm_vwf", c(10, 4), c(8.5, 4.5), c(3.5, 1.25)),
  cell("observed", "WREF", "WREF_1", "chm_vwf", 20, 15, 11),
  cell("null", "WREF", "WREF_1", "chm_vwf", 20, 15.5, 7.75),
  cell("observed", "SJER", c("SJER_1", "SJER_2"), "segmentanytree", c(10, 4), c(12, 6), c(8, 3)),
  cell("null", "SJER", c("SJER_1", "SJER_2"), "segmentanytree", c(10, 4), c(12, 6), c(4.5, 1.5)),
  cell("observed", "WREF", "WREF_1", "segmentanytree", 20, 18, 14),
  cell("null", "WREF", "WREF_1", "segmentanytree", 20, 17.5, 9.25))
SCOPES <- list(`five sites` = c("SJER", "WREF"), California = "SJER", Washington = "WREF")

test_that("the offsets are the paper's: one seed per plot and draw, a seed offset per SEED", {
  o <- cn_offsets("SJER", "SJER_050", 20, 4, K = 5)
  ref <- lapply(1:5, function(k) null_offset(48, seed_for("SJER", "SJER_050", "null") + k, min_shift = 8))
  expect_identical(o, ref)
  o1 <- cn_offsets("SJER", "SJER_050", 20, 4, K = 2, seed = 1L)
  expect_identical(o1[[2]], null_offset(48, seed_for("SJER", "SJER_050", "null") + 1000003L + 2))
  expect_identical(cn_offsets("SJER", "SJER_050", 10, 2, K = 3),
                   lapply(1:3, function(k) null_offset(24, seed_for("SJER", "SJER_050", "null") + k)))
  side <- 48
  d <- vapply(cn_offsets("WREF", "WREF_001", 20, 4, K = 50), function(v) sqrt(sum(pmin(v, side - v)^2)), 1)
  expect_true(all(d >= 8))
})

test_that("file suffixes follow the paper's null files", {
  expect_identical(cn_suffix(4), "")
  expect_identical(cn_suffix(2), "_tol2")
  expect_identical(cn_suffix(4, min_shift = 6), "_ms6")
  expect_identical(cn_suffix(4, seed = 1L), "_seed1")
  expect_identical(cn_suffix(2, 12, 1L), "_tol2_ms12_seed1")
})

test_that("crossing the wrap is flagged for exactly the detections shift_detections wraps", {
  det <- data.frame(x = c(95, 105, 112, 130), y = c(100, 109, 88, 100), z = 10)
  off <- c(9, 3)
  sh <- shift_detections(det, 100, 100, 14, off)
  x0 <- det[abs(det$x - 100) <= 14 & abs(det$y - 100) <= 14, ]
  expect_equal(nrow(sh), 3)                          # the point at x = 130 is outside
  w <- cn_wrapped(x0$x, x0$y, 100, 100, 14, off)
  plain <- abs(sh$x - (x0$x + off[1])) < 1e-9 & abs(sh$y - (x0$y + off[2])) < 1e-9
  expect_identical(w, !plain)
  expect_identical(w, c(FALSE, TRUE, TRUE))
})

test_that("a cell's shifts are the paper's null: the mean of score() over the shifted copies", {
  stems <- data.frame(E = c(98, 103, 106, 92), N = c(101, 95, 104, 92), height = c(20, 18, 15, 12),
                      crown_class = "dominant", stringsAsFactors = FALSE)
  det <- data.frame(x = c(98.5, 103, 105, 91, 112, 87), y = c(101, 95.5, 104, 93, 112, 87),
                    z = c(19, 18, 15, 12, 10, 9))
  offs <- cn_offsets("S1", "S1_001", 10, 4, K = 7)
  cols <- c("n_ref", "n_det", "TP", "tp_core")
  score <- function(dt) {
    s <- score_plot(stems, dt, tol_xy = 4, core_cx = 100, core_cy = 100, core_half = 10)
    data.frame(n_ref = s$n_ref, n_det = s$n_det, TP = s$TP,
               tp_core = if (s$n_det > 0) round(s$precision * s$n_det) else 0)
  }
  inside <- function(x, y) abs(x - 100) <= 5 & abs(y - 100) <= 5
  r <- cn_cell_shifts(det, 100, 100, 14, offs, score, cols, inside)
  expect_equal(dim(r$draws), c(7L, 4L))
  manual <- t(vapply(offs, function(o) unlist(score(shift_detections(det, 100, 100, 14, o))), numeric(4)))
  expect_equal(unname(r$draws), unname(manual))
  expect_equal(unlist(cn_null_means(r$draws)), colMeans(manual))
  expect_equal(r$n_window, 6L)
  crossed <- vapply(offs, function(o) {
    sh <- shift_detections(det, 100, 100, 14, o)
    sum(inside(sh$x, sh$y) & cn_wrapped(det$x, det$y, 100, 100, 14, o))
  }, numeric(1))
  expect_equal(r$wrapped, crossed)
  expect_true(all(is.na(cn_cell_shifts(det, 100, 100, 14, offs, score, cols)$wrapped)))
})

test_that("references outside the nominal box are measured by their Chebyshev excess", {
  expect_equal(cn_box_excess(c(100, 111, 95, 112), c(100, 100, 87.5, 113), 100, 100, 10),
               c(0, 1, 2.5, 3))
})

test_that("family rows keep the censused counts or rename the nominal-box counts", {
  x <- data.frame(variant = "observed", site = "S", plot = "P", rung = "native", detector = "a",
                  n_ref = 1, n_det = 2, TP = 3, tp_core = 4, rect_n_ref = 5, rect_n_det = 6,
                  rect_TP = 7, rect_tp_core = 8, extra = 9)
  expect_equal(unlist(cn_family_rows(x, "census")[CN_COUNTS]), c(n_ref = 1, n_det = 2, TP = 3, tp_core = 4))
  b <- cn_family_rows(x, "box")
  expect_equal(unlist(b[CN_COUNTS]), c(n_ref = 5, n_det = 6, TP = 7, tp_core = 8))
  expect_false("extra" %in% names(b))
})

test_that("pooling sums counts, corrects by the headroom and pairs the leads", {
  x <- synth_cells()
  W <- mt_plot_weights(x$site, x$plot, n_boot = 200, seed = 11)
  p <- cn_pool(x, W, SCOPES)
  e <- function(sc, a, v, m = "F1") p$est$estimate[p$est$scope == sc & p$est$detector == a &
                                                     p$est$variant == v & p$est$metric == m]
  # Five sites: summed counts, not mean per-plot rates.
  expect_equal(e("five sites", "chm_vwf", "observed", "recall"), 19 / 34)
  o <- f1(19, 34, 19, 28); n <- f1(12.5, 34, 12.5, 28.5)
  expect_equal(e("five sites", "chm_vwf", "observed"), o)
  expect_equal(e("five sites", "chm_vwf", "null"), n)
  expect_equal(e("five sites", "chm_vwf", "corrected"), (o - n) / (1 - n))
  expect_equal(e("five sites", "chm_vwf", "null_share"), n / o)
  os <- f1(25, 34, 25, 36); ns <- f1(15.25, 34, 15.25, 35.5)
  expect_equal(e("five sites", "segmentanytree", "corrected"), (os - ns) / (1 - ns))
  l <- function(sc, k) p$leads[p$leads$scope == sc & p$leads$kind == k & p$leads$metric == "F1", ]
  expect_equal(l("five sites", "corrected")$estimate, (os - ns) / (1 - ns) - (o - n) / (1 - n))
  expect_equal(l("five sites", "observed")$estimate, os - o)
  expect_equal(l("five sites", "null")$estimate, ns - n)
  # Regions use only their own plots (rows of W).
  expect_equal(p$est$n_plots[p$est$scope == "California"][1], 2L)
  expect_equal(e("Washington", "chm_vwf", "observed", "recall"), 11 / 20)
  expect_equal(nrow(l("Washington", "corrected")), 1L)
  # Intervals: every row carries its percentile interval.
  z <- p$est[p$est$scope == "five sites" & p$est$variant == "corrected" & p$est$metric == "F1", ]
  expect_true(all(z$lower <= z$estimate & z$estimate <= z$upper))
})

test_that("the corrected lead of an arm identical to the baseline is zero in every draw", {
  x <- synth_cells()
  y <- x[x$detector == "chm_vwf", ]; y$detector <- "twin"
  x <- rbind(x, y)
  W <- mt_plot_weights(x$site, x$plot, n_boot = 100, seed = 5)
  p <- cn_pool(x, W, SCOPES["five sites"])
  z <- p$leads[p$leads$detector == "twin", ]
  expect_true(all(z$estimate == 0 & z$lower == 0 & z$upper == 0))
  # The null equal to the observed gives a corrected score of zero.
  q <- x[x$detector == "twin" & x$variant == "observed", ]; q$variant <- "null"
  x2 <- rbind(x[!(x$detector == "twin" & x$variant == "null"), ], q)
  p2 <- cn_pool(x2, W, SCOPES["five sites"])
  expect_equal(p2$est$estimate[p2$est$detector == "twin" & p2$est$variant == "corrected"], c(0, 0, 0))
})

test_that("pooling refuses mixed rungs, a missing null and unequal support", {
  x <- synth_cells()
  W <- mt_plot_weights(x$site, x$plot, n_boot = 20, seed = 1)
  y <- x; y$rung[1] <- "8"
  expect_error(cn_pool(y, W, SCOPES), "one rung")
  expect_error(cn_pool(x[x$variant == "observed", ], W, SCOPES), "observed and null")
  expect_error(cn_pool(x[-1, ], W, SCOPES), "does not cover")
})

test_that("the Monte Carlo error pools each shift over plots before scoring", {
  dr <- data.frame(detector = "a", k = rep(1:4, each = 2), n_ref = 10,
                   n_det = c(5, 6, 4, 4, 6, 5, 5, 5), TP = c(2, 3, 1, 2, 3, 3, 2, 2),
                   tp_core = c(2, 3, 1, 2, 3, 3, 2, 2))
  m <- cn_mc_se(dr)
  per <- vapply(1:4, function(k) { z <- dr[dr$k == k, ]; f1(sum(z$TP), sum(z$n_ref), sum(z$tp_core), sum(z$n_det)) }, 1)
  expect_equal(m$F1_mean, mean(per))
  expect_equal(m$F1_sd, sd(per))
  expect_equal(m$F1_se, sd(per) / 2)
  expect_equal(m$shifts, 4L)
})

test_that("parity comparisons report the largest difference, NAs and missing rows", {
  a <- data.frame(k = c("x", "y", "z"), v = c(1, NA, 3), s = c("p", "q", "r"))
  b <- data.frame(k = c("y", "x"), v = c(NA, 1 + 1e-12), s = c("q", "P"))
  r <- cn_compare(a, b, "k", c("v", "s"))
  expect_equal(r$missing, 1L)
  expect_equal(r$matched, 2L)
  expect_lt(r$max_diff[["v"]], 1e-11)
  expect_equal(r$max_diff[["s"]], 1)
  b$v[1] <- 2
  expect_equal(cn_compare(a, b, "k", "v")$max_diff[["v"]], Inf)
  expect_error(cn_compare(a, rbind(b, b), "k", "v"), "Duplicate")
})

test_that("a passing parity check states its tolerance, a failing one the size", {
  expect_identical(cn_diff_text(5.55e-16, 1e-12), "within the tolerance 1e-12")
  expect_identical(cn_diff_text(c(n_ref = 0, TP = 4e-10), 1e-9), "within the tolerance 1e-09")
  expect_identical(cn_diff_text(2.5e-6, 1e-9), "2.5e-06")
  expect_identical(cn_diff_text(c(n_ref = 0, TP = 0.5, n_det = Inf), 1e-9), "n_ref 0, TP 0.5, n_det Inf")
})

test_that("numbers are formatted with three decimals and a true minus sign", {
  expect_identical(cn_num(c(0.1234, -0.0004)), c("0.123", "−0.000"))
  expect_identical(cn_num(0.0626, signed = TRUE), "+0.063")
  expect_identical(cn_ci(0.063, 0.016, 0.108, TRUE), "+0.063 [+0.016, +0.108]")
  expect_identical(cn_ci(-0.043, -0.082, -0.008, TRUE), "−0.043 [−0.082, −0.008]")
  expect_identical(cn_ci(NA_real_, NA, NA), "—")
})

## ---- combining runs: the unsmoothed baseline -------------------------------------------
test_that("run parameters and check status are read from a check file", {
  chk <- c(paste("Censused chance agreement: declaration census-support-declaration-nearest.json",
                 "(paper-2021-census-support-nearest-v2), TOL=4, K=200, SEED=0, MIN_SHIFT=8"),
           "A: ...", "CHECK A (observed parity with the committed census scores): PASS",
           "CHECK C (nominal-box null parity with null_cells.csv): PASS",
           "B: skipped (CHECK_MASTER=0; the master tables hold no contrasts for this run's arms)")
  p <- cn_run_params(chk)
  expect_identical(p, list(declaration = "paper-2021-census-support-nearest-v2", tol = 4, K = 200L,
                           seed = 0L, min_shift = 8))
  expect_identical(cn_run_params(sub("TOL=4", "TOL=2", chk))$tol, 2)
  expect_true(cn_checks_passed(chk))
  expect_false(cn_checks_passed(chk[-3]))                                  # A missing
  expect_false(cn_checks_passed(c(chk, "CHECK B (observed leads equal the master tables): FAIL")))
  expect_error(cn_run_params("something else"), "Not a census-null check file")
})

test_that("an added baseline must share the other arms' plots, references and support", {
  x <- synth_cells(); x <- x[x$variant == "observed", ]
  x$rect_n_ref <- x$n_ref + 1; x$support_id <- paste0("s_", x$plot)
  y <- x[x$detector == "chm_vwf", ]; y$detector <- "chm_vwf_nosmooth"
  z <- rbind(x, y)
  expect_length(cn_reference_mismatch(z), 0)
  expect_length(cn_unequal_rungs(z), 0)
  y2 <- y; y2$n_ref[1] <- y2$n_ref[1] + 1
  expect_identical(cn_reference_mismatch(rbind(x, y2)), "SJER::SJER_1::native")
  y3 <- y; y3$support_id[3] <- "other"
  expect_identical(cn_reference_mismatch(rbind(x, y3)), "WREF::WREF_1::native")
  expect_identical(cn_unequal_rungs(rbind(x, y[-2, ])), "native")
})

test_that("leads can be taken over another baseline, the declared one included as an arm", {
  x <- synth_cells()
  y <- x[x$detector == "chm_vwf", ]; y$detector <- "chm_vwf_nosmooth"
  y$TP <- y$TP + 1; y$tp_core <- y$TP                       # a better comparator
  z <- rbind(x, y)
  W <- mt_plot_weights(z$site, z$plot, n_boot = 100, seed = 3)
  p <- cn_pool(z, W, SCOPES["five sites"], base = "chm_vwf_nosmooth")
  expect_setequal(unique(p$leads$detector), c("chm_vwf", "segmentanytree"))
  expect_true(all(p$leads$versus == "chm_vwf_nosmooth"))
  e <- function(a, v) p$est$estimate[p$est$detector == a & p$est$variant == v & p$est$metric == "F1"]
  l <- p$leads[p$leads$detector == "chm_vwf" & p$leads$kind == "corrected" & p$leads$metric == "F1", ]
  expect_equal(l$estimate, e("chm_vwf", "corrected") - e("chm_vwf_nosmooth", "corrected"))
  expect_lt(l$estimate, 0)
  # The other arms' own scores do not depend on which baseline is the comparator.
  q <- cn_pool(z, W, SCOPES["five sites"])
  expect_equal(p$est[order(p$est$detector, p$est$variant, p$est$metric), "estimate"],
               q$est[order(q$est$detector, q$est$variant, q$est$metric), "estimate"])
})
