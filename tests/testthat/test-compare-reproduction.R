# The reproduction comparator's column rules (compare_reproduction.R). Only
# the named definitions are loaded from the script; nothing is compared on disk.
cmp_env <- function() {
  e <- new.env(parent = globalenv())
  e$TOL <- 1e-8; e$LENGTH_TOL <- 0.01; e$OVERLAP_TOL <- 0.01
  exprs <- parse(file.path("..", "..", "scripts", "compare_reproduction.R"))
  # eval() runs only the named definitions parsed from this repository's own
  # script (no external input), skipping its main body.
  keep <- c("LENGTH_COL", "OVERLAP_COL", "num_diff")
  for (x in exprs) {
    lhs <- if (is.call(x) && identical(x[[1]], as.name("<-"))) as.character(x[[2]]) else ""
    if (lhs %in% keep) eval(x, e)
  }
  e
}

test_that("lengths in metres get the 1 cm allowance and F1-scale biases do not", {
  e <- cmp_env()
  for (col in c("x", "Z", "height", "height_rmse", "rmse", "mae", "bias", "d_eq", "d_caliper",
                "june_rmse_eq", "h_m", "max_ref_excess_m"))
    expect_match(e$num_diff(c(1, 2), c(1.005, 2), col), "^length ", info = col)
  for (col in c("baseline_bias", "baseline_bias_half", "F1", "recall"))
    expect_match(e$num_diff(c(-0.127, 0.2), c(-0.122, 0.2), col), "^max difference", info = col)
  expect_identical(e$num_diff(c(1, 2), c(1, 2), "baseline_bias"), "")
  expect_match(e$num_diff(1, 1.02, "height"), "^max difference")    # beyond the allowance
  expect_match(e$num_diff(1, 1.005, "iou_sum_tp"), "^length .* IoU")
})
