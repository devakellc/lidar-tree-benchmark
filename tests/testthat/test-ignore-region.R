# Unit tests for the ignore-region scoring in sweep_lib.R: score_plot's
# optional matching pairs and drop_ignored_detections, as
# paper_sensitivity.R MODE=exact2021 uses them for variant exact2021_ignore.
# Stems flagged "don't care" leave the reference, and the detections the full
# greedy matching pairs with them are dropped. All synthetic; no NEON data.
source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)

# Core: the square of half-width 10 m around (0, 0); the recall region adds
# the 4 m match radius. `keep` marks the stems measured in the flight year.
#   s1 (ignored) and s2 (kept) compete for d1; s1 is nearer and wins it.
#   s3 (kept) and s4 (ignored) compete for d2; s3 wins it and s4 takes d3.
#   s5 (ignored) matches d4, which lies outside the core (not in n_det).
#   s6 (kept) matches d5. s7 (kept) fails the height gate against d7.
#   d6 is an isolated false positive.
ir_stems <- function() data.frame(
  E = c(0, 1.5, -6, -4.5, 9, 5, 3), N = c(0, 0, 5, 5, -9, -5, 7),
  height = c(20, 20, 18, 18, 15, 12, 25),
  crown_class = c("dominant", "codominant", "dominant", "intermediate",
                  "codominant", "suppressed", "dominant"),
  keep = c(FALSE, TRUE, TRUE, FALSE, FALSE, TRUE, TRUE),
  stringsAsFactors = FALSE)
ir_dets <- function() data.frame(
  x = c(0.5, -5.6, -2, 11, 5.5, -8, 3.5), y = c(0, 5, 5, -9, -5, -8, 7),
  z = c(20, 18, 18, 15, 12, 10, 5))
ir_score <- function(stems, det, ...)
  score_plot(stems, det, tol_xy = 4, core_cx = 0, core_cy = 0, core_half = 10, ...)
ir_drop <- function(stems, det, ignore, ...)
  drop_ignored_detections(stems, det, ignore, tol_xy = 4, core_cx = 0, core_cy = 0,
                          core_half = 10, ...)
tp_core <- function(s) if (s$n_det > 0) round(s$precision * s$n_det) else 0

test_that("score_plot keeps its default output and exposes the matching on request", {
  st <- ir_stems(); dt <- ir_dets()
  a <- ir_score(st, dt)
  expect_null(attr(a, "pairs"))
  expect_identical(ir_score(st, dt, return_pairs = FALSE), a)
  b <- ir_score(st, dt, return_pairs = TRUE)
  pr <- attr(b, "pairs")
  attr(b, "pairs") <- NULL
  expect_identical(b, a)
  expect_equal(pr$stem, c(1L, 3L, 4L, 5L, 6L))
  expect_equal(pr$det, c(1L, 2L, 3L, 4L, 5L))
  expect_equal(pr$core, c(TRUE, TRUE, TRUE, FALSE, TRUE))
  expect_equal(nrow(pr), a$TP)
  expect_equal(sum(pr$core), tp_core(a))
})

test_that("pairs index the caller's rows when detections fall outside the region", {
  st <- ir_stems(); dt <- rbind(data.frame(x = 40, y = 40, z = 20), ir_dets())
  pr <- attr(ir_score(st, dt, return_pairs = TRUE), "pairs")
  expect_equal(pr$det, c(2L, 3L, 4L, 5L, 6L))
  expect_equal(dt$x[pr$det], c(0.5, -5.6, -2, 11, 5.5))
})

test_that("an ignored stem that wins a contested detection takes it out of the scoring", {
  st <- ir_stems(); dt <- ir_dets(); ign <- !st$keep
  base <- ir_score(st, dt)
  rem <- ir_drop(st, dt, ign)
  pr <- attr(rem, "pairs")
  # d1 (won by ignored s1), d3 (s4) and d4 (s5, outside the core) are dropped.
  expect_equal(pr$ignored, c(TRUE, FALSE, TRUE, TRUE, FALSE))
  expect_equal(rem$x, c(-5.6, 5.5, -8, 3.5))
  ig <- ir_score(st[st$keep, ], rem)
  cut <- ir_score(st[st$keep, ], dt)
  # The plain cut re-matches d1 to s2; the ignore variant cannot.
  expect_equal(cut$TP, 3)
  expect_equal(ig$TP, 2)
  expect_equal(ig$TP, sum(!pr$ignored))
  expect_equal(ig$n_ref, cut$n_ref)
  expect_equal(ig$n_ref, 4)
  # d4 lies outside the core, so only d1 and d3 leave n_det.
  expect_equal(base$n_det, 6)
  expect_equal(ig$n_det, base$n_det - sum(pr$core & pr$ignored))
  expect_equal(ig$n_det, 4)
  expect_equal(tp_core(ig), sum(pr$core & !pr$ignored))
  # Core false positives: the baseline's under the ignore variant (d6, d7);
  # the plain cut adds d3, the detection of ignored s4.
  expect_equal(ig$n_det - tp_core(ig), base$n_det - tp_core(base))
  expect_equal(ig$n_det - tp_core(ig), 2)
  expect_equal(cut$n_det - tp_core(cut), 3)
  # The kept stem that wins its contest keeps its detection.
  pr_ig <- attr(ir_score(st[st$keep, ], rem, return_pairs = TRUE), "pairs")
  expect_equal(which(st$keep)[pr_ig$stem], c(3L, 6L))
  expect_equal(rem$x[pr_ig$det], c(-5.6, 5.5))
})

test_that("nothing changes when no stem is ignored, and flags are checked", {
  st <- ir_stems(); dt <- ir_dets()
  rem <- ir_drop(st, dt, rep(FALSE, nrow(st)))
  expect_equal(nrow(rem), nrow(dt))
  expect_identical(ir_score(st, rem), ir_score(st, dt))
  expect_error(ir_drop(st, dt, c(NA, rep(FALSE, nrow(st) - 1))), "logical flag")
  expect_error(ir_drop(st, dt, rep(FALSE, 3)), "logical flag")
  expect_error(ir_drop(st, dt, rep(0, nrow(st))), "logical flag")
  rem0 <- ir_drop(st, dt[0, ], !st$keep)
  expect_equal(nrow(rem0), 0L)
  expect_equal(ir_score(st[st$keep, ], rem0)$TP, 0)
  # Every detection matched to an ignored stem: the core keeps the others.
  all_ign <- ir_drop(st, dt, rep(TRUE, nrow(st)))
  expect_equal(all_ign$x, c(-8, 3.5))
})

test_that("the greedy matching on the remainder is the full matching restricted to kept stems", {
  # Random scenes on a 0.5 m grid, so equal distances (ties) occur often.
  checked <- 0L
  for (seed in 1:300) {
    set.seed(seed)
    ns <- sample(2:30, 1); nd <- sample(1:35, 1)
    st <- data.frame(E = round(runif(ns, -10, 10) * 2) / 2, N = round(runif(ns, -10, 10) * 2) / 2,
                     height = round(runif(ns, 3, 35)),
                     crown_class = sample(c("dominant", "codominant", "intermediate",
                                            "suppressed"), ns, replace = TRUE),
                     stringsAsFactors = FALSE)
    dt <- data.frame(x = round(runif(nd, -14, 14) * 2) / 2, y = round(runif(nd, -14, 14) * 2) / 2,
                     z = round(runif(nd, 2, 40)))
    tol <- sample(c(2, 3, 4), 1)
    ign <- runif(ns) < 0.4
    full <- score_plot(st, dt, tol_xy = tol, core_cx = 0, core_cy = 0, core_half = 10)
    rem <- drop_ignored_detections(st, dt, ign, tol_xy = tol, core_cx = 0, core_cy = 0,
                                   core_half = 10)
    pr <- attr(rem, "pairs")
    kept_det <- which(!seq_len(nrow(dt)) %in% pr$det[pr$ignored])
    sub <- score_plot(st[!ign, , drop = FALSE], rem, tol_xy = tol, core_cx = 0, core_cy = 0,
                      core_half = 10, return_pairs = TRUE)
    ps <- attr(sub, "pairs")
    got <- data.frame(stem = which(!ign)[ps$stem], det = kept_det[ps$det])
    want <- pr[!pr$ignored, c("stem", "det")]
    rownames(got) <- rownames(want) <- NULL
    expect_equal(got, want, info = paste("seed", seed))
    expect_equal(nrow(pr), full$TP, info = paste("seed", seed))
    expect_equal(sub$TP, sum(!pr$ignored), info = paste("seed", seed))
    expect_equal(sub$n_det, full$n_det - sum(pr$core & pr$ignored), info = paste("seed", seed))
    expect_equal(sub$n_det - tp_core(sub), full$n_det - tp_core(full), info = paste("seed", seed))
    checked <- checked + 1L
  }
  expect_equal(checked, 300L)
})
