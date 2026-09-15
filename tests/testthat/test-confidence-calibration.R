# Unit tests for the #P4 confidence-calibration helpers in model_bench_lib.R:
# reliability_table, expected_calibration_error, isotonic_calibrate, and
# precision_at_recall. All synthetic; every expected value hand-computed.
source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)

## ---- reliability_table ----------------------------------------------------
# probs 0.05,0.15 (label 0,0) and 0.85,0.95 (label 1,1); bins=2.
#   bin [0,0.5): n=2 mean_prob=0.10 obs_acc=0
#   bin [0.5,1]: n=2 mean_prob=0.90 obs_acc=1
test_that("reliability_table bins probabilities and reports observed accuracy", {
  rt <- reliability_table(c(0.05, 0.15, 0.85, 0.95), c(0L, 0L, 1L, 1L), bins = 2)
  expect_identical(names(rt), c("bin", "n", "mean_prob", "obs_acc"))
  rt <- rt[rt$n > 0, ]
  expect_equal(nrow(rt), 2L)
  expect_equal(rt$mean_prob, c(0.10, 0.90))
  expect_equal(rt$obs_acc, c(0, 1))
  expect_equal(rt$n, c(2L, 2L))
})

test_that("reliability_table is 0-row safe", {
  rt <- reliability_table(numeric(0), integer(0), bins = 5)
  expect_identical(names(rt), c("bin", "n", "mean_prob", "obs_acc"))
  expect_true(all(rt$n == 0))
})

## ---- expected_calibration_error -------------------------------------------
# Same data, bins=2: ECE = (2/4)|0-0.1| + (2/4)|1-0.9| = 0.10.
test_that("expected_calibration_error is the n-weighted gap of the reliability table", {
  ece <- expected_calibration_error(c(0.05, 0.15, 0.85, 0.95),
                                    c(0L, 0L, 1L, 1L), bins = 2)
  expect_equal(ece, 0.10)
})

test_that("a perfectly calibrated predictor has ~0 ECE", {
  # 100 points at prob 0.0 (all label 0) and 100 at prob 1.0 (all label 1)
  p <- c(rep(0, 100), rep(1, 100)); y <- c(rep(0L, 100), rep(1L, 100))
  expect_equal(expected_calibration_error(p, y, bins = 10), 0)
})

## ---- isotonic_calibrate ---------------------------------------------------
# Monotone, maps the lowest score toward 0 and the highest toward 1, and
# isotonic recalibration never INCREASES ECE on the training data.
test_that("isotonic_calibrate returns a monotone calibrator mapping score->prob", {
  set.seed(1)
  raw <- c(0.05, 0.15, 0.25, 0.85, 0.90, 0.95)
  y   <- c(0L,   0L,   1L,   1L,   1L,   1L)
  cal <- isotonic_calibrate(raw, y)
  expect_true(is.function(cal))
  out <- cal(raw)
  expect_true(all(diff(out) >= -1e-9))             # non-decreasing in score
  expect_true(all(out >= 0 & out <= 1))
  # calibration must not worsen training-set ECE
  expect_lte(expected_calibration_error(cal(raw), y, bins = 5),
             expected_calibration_error(raw, y, bins = 5) + 1e-9)
})

test_that("isotonic_calibrate handles a single class without error", {
  cal <- isotonic_calibrate(c(0.2, 0.4, 0.6), c(0L, 0L, 0L))
  expect_true(is.function(cal))
  expect_true(all(cal(c(0.2, 0.5, 0.6)) == 0))     # no positives -> calibrates to 0
})

test_that("constant mixed-label scores calibrate to the base rate", {
  cal <- isotonic_calibrate(c(0.5, 0.5, 0.5, NA), c(0, 1, 1, 0))
  expect_equal(cal(c(-1, 0.5, 10, NA)), c(2 / 3, 2 / 3, 2 / 3, NA))
})

test_that("tied calibration scores retain sample weights without label-order bias", {
  score <- c(0, 0, 1)
  expected <- rep(1 / 3, 2)
  expect_equal(isotonic_calibrate(score, c(0, 1, 0))(c(0, 1)), expected)
  expect_equal(isotonic_calibrate(score, c(1, 0, 0))(c(0, 1)), expected)
  expect_equal(isotonic_calibrate(c(0, 0, 1, 1), c(0, 1, 1, 1))(c(0, 1)),
               c(0.5, 1))
})

test_that("saved confidence lookups reproduce predictions on the raw scale", {
  raw <- c(10, 20, 30, 40); label <- c(0, 0, 1, 1)
  lookup <- confidence_lookup(raw, label)
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  write.csv(lookup, path, row.names = FALSE)
  restored <- read.csv(path)
  expect_equal(apply_confidence_lookup(c(0, 25, 100, NA), restored), c(0, 0.5, 1, NA))
  expect_equal(apply_confidence_lookup(c(3, 8, NA),
               confidence_lookup(c(5, 5), c(0, 1))), c(0.5, 0.5, NA))
  expect_error(apply_confidence_lookup(1, restored[, c("raw_prob", "calibrated")]),
               "normalization metadata")
  mixed <- rbind(transform(restored, arm = "a"), transform(restored, arm = "b"))
  expect_error(apply_confidence_lookup(1, mixed), "multiple arms")
  mixed$arm <- "a"; mixed$rung <- rep(c("native", "1"), each = nrow(restored))
  expect_error(apply_confidence_lookup(1, mixed), "multiple arms")
})

test_that("calibration holds out whole plots and their labels and score ranges", {
  dat <- data.frame(site = "S", plot = rep(c("a", "b", "c"), each = 2),
                     arm = "x", raw = c(100, 200, 0, 1, 0, 1),
                     label = c(1, 1, 0, 0, 0, 0))
  cv <- oos_calibrated(dat)
  expect_equal(cv$cal[1:2], c(0, 0))
  expect_equal(cv$prob_cv[1:2], c(1, 1))  # held-out extremes do not set the scale
  changed <- dat; changed$label[1:2] <- 0
  expect_equal(oos_calibrated(changed)$cal[1:2], cv$cal[1:2])
  second <- dat; second$arm <- "y"; second$rung <- "1"; dat$rung <- "native"
  both <- oos_calibrated(rbind(dat, second))
  expect_equal(both$fold[1:6], both$fold[7:12])
  expect_true(all(is.na(oos_calibrated(dat[1:2, ])$cal)))
})

## ---- precision_at_recall --------------------------------------------------
# scores 0.9,0.8,0.7,0.6,0.5 ; labels 1,0,1,1,0 (3 positives). Sorted desc,
# cumulative recall hits 2/3 at the 3rd item (precision 2/3) and 3/3 at the 4th
# (precision 3/4).
test_that("precision_at_recall thresholds the ranking to a target recall", {
  s <- c(0.9, 0.8, 0.7, 0.6, 0.5); y <- c(1L, 0L, 1L, 1L, 0L)
  expect_equal(precision_at_recall(s, y, target_recall = 0.6), 2 / 3)
  expect_equal(precision_at_recall(s, y, target_recall = 1.0), 0.75)
  # a tiny target is satisfied by the top (TP) detection alone -> precision 1
  expect_equal(precision_at_recall(s, y, target_recall = 0.01), 1.0)
})

test_that("precision_at_recall returns NA when there are no positives", {
  expect_true(is.na(precision_at_recall(c(0.9, 0.1), c(0L, 0L), 0.5)))
})

test_that("precision at recall includes complete tied confidence groups", {
  expect_equal(precision_at_recall(c(0.5, 0.5), c(1, 0), 0.5), 0.5)
  expect_equal(precision_at_recall(c(0.5, 0.5), c(0, 1), 0.5), 0.5)
})

test_that("calibrated cross-arm ranking can beat raw ranking at fixed recall", {
  # Arm A raw scores live in [0,1], arm B in [0,100] (not comparable). The two
  # FP from arm B (raw 90,80) outrank arm A's TP (raw 0.9) under raw pooling, but
  # after per-arm calibration to empirical precision the ranking is comparable.
  rawA <- c(0.9, 0.8);  yA <- c(1L, 1L)
  rawB <- c(90, 80, 5); yB <- c(0L, 0L, 1L)
  calA <- isotonic_calibrate(rawA, yA); calB <- isotonic_calibrate(rawB, yB)
  pooled_raw  <- c(rawA, rawB)
  pooled_cal  <- c(calA(rawA), calB(rawB))
  y           <- c(yA, yB)
  pr_raw <- precision_at_recall(pooled_raw, y, target_recall = 0.6)
  pr_cal <- precision_at_recall(pooled_cal, y, target_recall = 0.6)
  expect_gte(pr_cal, pr_raw)                        # calibration never hurts here
})
