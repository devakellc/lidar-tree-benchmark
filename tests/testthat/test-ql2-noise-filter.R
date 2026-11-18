# The native 3DEP cross-check's read-time noise filter and box densities, on
# a synthetic cloud. Only the helper definitions are loaded from the script;
# nothing is pulled or detected.
ql2_env <- function() {
  e <- new.env(parent = globalenv())
  exprs <- parse(file.path("..", "..", "scripts", "native_ql2_crosscheck.R"))
  # eval() runs only the named helper definitions parsed from this
  # repository's own script (no external input), skipping its main body.
  keep <- c("QL2_NOISE_CLASSES", "PULL_FILTER_LIMITS", "ql2_noise_filter",
            "noise_filter_label", "box_density")
  for (x in exprs) {
    lhs <- if (is.call(x) && identical(x[[1]], as.name("<-"))) as.character(x[[2]]) else ""
    if (lhs %in% keep) eval(x, e)
  }
  e
}

# Ten points: classes 2, 5, 7 and 18, two of them withheld (one class 5, one
# class 7, so one withheld point is also a noise point).
synth_noisy_las <- function() {
  d <- data.frame(X = as.numeric(1:10), Y = as.numeric(1:10), Z = as.numeric(1:10),
                  Classification = c(2L, 2L, 5L, 5L, 5L, 7L, 7L, 18L, 18L, 18L),
                  ReturnNumber = c(1L, 1L, 1L, 2L, 1L, 1L, 2L, 1L, 1L, 1L),
                  NumberOfReturns = 2L,
                  Withheld_flag = c(FALSE, FALSE, FALSE, FALSE, TRUE,
                                    TRUE, FALSE, FALSE, FALSE, FALSE))
  suppressMessages(suppressWarnings(lidR::LAS(d)))
}

test_that("the filter drops classes 7 and 18 and withheld points and counts them", {
  e <- ql2_env()
  las <- synth_noisy_las()
  r <- e$ql2_noise_filter(las)
  expect_equal(sort(r$las$X), c(1, 2, 3, 4))           # classes 2 and 5, not withheld
  expect_true(all(r$las$Classification %in% c(2L, 5L)))
  expect_false(any(r$las$Withheld_flag))
  expect_equal(r$counts$n_read, 10L)
  expect_equal(r$counts$n_class7, 2L)
  expect_equal(r$counts$n_class18, 3L)
  expect_equal(r$counts$n_withheld, 2L)
  expect_equal(r$counts$n_dropped, 6L)                 # 5 noise + 1 withheld class 5
  expect_equal(lidR::npoints(r$las), r$counts$n_read - r$counts$n_dropped)
})

test_that("the diagnostic and off settings drop only what they name", {
  e <- ql2_env()
  las <- synth_noisy_las()
  cls <- e$ql2_noise_filter(las, withheld = FALSE)
  expect_equal(sort(cls$las$X), c(1, 2, 3, 4, 5))      # the withheld class 5 stays
  expect_equal(cls$counts$n_dropped, 5L)
  expect_equal(cls$counts$n_withheld, 2L)              # still counted
  off <- e$ql2_noise_filter(las, classes = integer(0), withheld = FALSE)
  expect_identical(off$las, las)                       # untouched
  expect_equal(off$counts$n_dropped, 0L)
  expect_equal(off$counts$n_class18, 3L)
  expect_equal(e$noise_filter_label(e$QL2_NOISE_CLASSES, TRUE), "7,18,withheld")
  expect_equal(e$noise_filter_label(e$QL2_NOISE_CLASSES, FALSE), "7,18")
  expect_equal(e$noise_filter_label(integer(0), FALSE), "none")
})

test_that("a clean cloud is returned untouched", {
  e <- ql2_env()
  las <- lidR::filter_poi(synth_noisy_las(), Classification %in% c(2L, 5L) & !Withheld_flag)
  r <- e$ql2_noise_filter(las)
  expect_identical(r$las, las)
  expect_equal(r$counts$n_dropped, 0L)
  expect_equal(r$counts$n_read, 4L)
})

# PDAL's filters.range ORs the two Classification ranges, so this string drops
# only the withheld points; the read-time filter drops classes 7 and 18. The
# string is kept as pulled, so fresh pulls record the same filter.
test_that("the pull's limits string is kept as pulled", {
  e <- ql2_env()
  expect_identical(e$PULL_FILTER_LIMITS,
                   "Classification![7:7],Classification![18:18],Withheld![1:1]")
})

test_that("box densities count points and area in the same box", {
  e <- ql2_env()
  las <- synth_noisy_las()
  # The 2 x 2 m box around (2, 2) holds points 1-3, all first returns.
  d <- e$box_density(las, 2, 2, 1)
  expect_equal(unname(d["pdens"]), 3 / 4)
  expect_equal(unname(d["frdens"]), 3 / 4)
  # The 6 x 6 m box around (4, 4) holds points 1-7, five of them first returns.
  d <- e$box_density(las, 4, 4, 3)
  expect_equal(unname(d["pdens"]), 7 / 36)
  expect_equal(unname(d["frdens"]), 5 / 36)
})
