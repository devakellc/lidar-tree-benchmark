source(file.path("..", "..", "scripts", "model_bench_lib.R"))
source(file.path("..", "..", "scripts", "fgiemit_development_summary_lib.R"))

fgi_summary_fixture <- function(vary = FALSE) {
  groups <- fgi_summary_groups()
  rows <- merge(groups, data.frame(plot = FGI_DEVELOPMENT_PLOTS), sort = FALSE)
  rows$n_ref <- rows$n_pred <- match(rows$plot, FGI_DEVELOPMENT_PLOTS) * 10
  rows$TP <- if (vary) match(rows$plot, FGI_DEVELOPMENT_PLOTS)^2 else rows$n_ref / 2
  rows$FP <- rows$FN <- rows$n_ref - rows$TP
  rows$sum_iou <- rows$TP * .8
  rows$sum_maxiou <- rows$n_ref * .6
  for (category in LETTERS[1:4]) {
    present <- as.numeric(category == "A")
    for (pair in list(c("n_", "n_ref"), c("tp_", "TP"), c("fn_", "FN"),
                     c("sumiou_", "sum_iou"), c("sumcov_", "sum_maxiou")))
      rows[[paste0(pair[1], category)]] <- rows[[pair[2]]] * present
  }
  rows
}

test_that("development pooling uses summed counts and mask accumulators", {
  rows <- fgi_summary_fixture()
  apex <- rows[rows$target == "apex_max_agl" & rows$arm == "chm_vwf", ][1:2, ]
  apex$n_ref <- c(1, 100); apex$n_pred <- c(1, 100)
  apex$TP <- c(1, 0); apex$FP <- apex$FN <- c(0, 100)
  expect_equal(fgi_pool_counts(apex)$F1, 1 / 101)
  expect_false(isTRUE(all.equal(fgi_pool_counts(apex)$F1, .5)))
  masks <- rows[rows$target == "mask_iou_0.5" & rows$arm == "segmentanytree", ]
  pooled <- fgi_pool_counts(masks)
  expect_equal(pooled$TP, 275)
  expect_equal(pooled$coverage, .6)
  expect_equal(pooled$SQ, .8)
  expect_equal(pooled$PQ, .4)
  expect_equal(pooled$tp_A, 275)
  expect_true(is.na(pooled$rec_B))
})

test_that("primary summaries reject incomplete or incompatible denominators", {
  rows <- fgi_summary_fixture()
  expect_silent(fgi_validate_summary_rows(rows))
  expect_error(fgi_summarize_complete(rows[-1, ]), "all nine")
  bad <- rows; bad$plot[1] <- "1003"
  expect_error(fgi_validate_summary_rows(bad), "foreign")
  bad <- rows; bad[1, ] <- bad[2, ]
  expect_error(fgi_validate_summary_rows(bad), "duplicated")
  bad <- rows; bad$n_ref[1] <- bad$n_ref[1] + 1
  expect_error(fgi_validate_summary_rows(bad), "denominators")
  bad$FN[1] <- bad$FN[1] + 1
  expect_error(fgi_validate_summary_rows(bad), "populations differ")
  bad <- rows
  changed <- which(rows$target == "apex_isolated_top_agl")[1]
  bad$n_pred[changed] <- bad$n_pred[changed] + 1
  bad$FP[changed] <- bad$FP[changed] + 1
  expect_error(fgi_validate_summary_rows(bad), "Prediction populations")
  bad <- rows; bad$sum_iou[bad$target == "mask_iou_0.5"] <- NA
  expect_error(fgi_validate_summary_rows(bad), "mask accumulator")
  expect_error(fgi_validate_summary_rows(rows[, names(rows) != "TP"]), "Missing")
})

test_that("bootstrap draws are deterministic, paired and preserve caller RNG", {
  set.seed(314)
  before <- .Random.seed
  kind <- RNGkind()
  draws <- fgi_bootstrap_indices(40)
  expect_identical(.Random.seed, before)
  expect_identical(RNGkind(), kind)
  expect_identical(draws, fgi_bootstrap_indices(40))
  expect_equal(dim(draws), c(10L, 40L))
  expect_true(all(draws %in% 1:10))
  rows <- fgi_summary_fixture(vary = TRUE)
  # Plot-specific rates vary from .1 to 1; independent arm draws would not
  # yield zero differences even though the arms have identical cell counts.
  result <- fgi_summarize_complete(rows, n_boot = 40)
  expect_equal(result$contrasts$estimate, rep(0, 8))
  expect_equal(result$contrasts$lower, rep(0, 8))
  expect_equal(result$contrasts$upper, rep(0, 8))
  expect_equal(result$contrasts$defined_draws, rep(40, 8))
  missing <- result$intervals[result$intervals$metric == "rec_B", ]
  expect_true(all(is.na(missing$estimate) & is.na(missing$lower)))
  expect_equal(missing$defined_draws, c(0L, 0L))
  improved <- rows$target == "apex_isolated_top_agl" & rows$arm == "segmentanytree"
  rows$TP[improved] <- rows$n_ref[improved]
  rows$FP[improved] <- rows$FN[improved] <- 0
  result <- fgi_summarize_complete(rows, n_boot = 20)
  delta <- result$contrasts[result$contrasts$to == "apex_isolated_top_agl/segmentanytree", ]
  expect_equal(delta$estimate, .3)
  expect_gt(delta$lower, 0)
  expect_lt(delta$upper, .9)
})
