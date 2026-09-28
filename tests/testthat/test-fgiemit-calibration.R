source(file.path("..", "..", "scripts", "model_bench_lib.R"))
source(file.path("..", "..", "scripts", "transfer_audit_lib.R"))
source(file.path("..", "..", "scripts", "fgiemit_development_summary_lib.R"))
source(file.path("..", "..", "scripts", "fgiemit_calibration_lib.R"))

test_that("prediction labels preserve the default apex matcher including ties", {
  pred <- data.frame(instance = c(3L, 8L, 20L), x = c(0, 0, 4), y = 0,
                     z = c(10, 10, 15), confidence = c(10, 10, 15))
  ref <- data.frame(instance = c(7L, 40L), x = c(0, 8), y = 0, z = 10)
  labels <- fgi_apex_labels(pred, ref)
  expect_equal(labels$matched_reference, c(7L, NA_integer_, 40L))
  expect_equal(sum(labels$label), audit_apex_match(pred, ref)$apex_TP)
  pred$z[3] <- 15.00001
  expect_equal(fgi_apex_labels(pred, ref)$label, c(1L, 0L, 0L))
  expect_equal(nrow(fgi_apex_labels(pred[FALSE, ], ref)), 0L)
  expect_equal(fgi_apex_labels(pred, ref[FALSE, ])$label, rep(0L, 3L))
  set.seed(123)
  for (i in 1:20) {
    pred$x <- runif(3, 0, 12); pred$y <- runif(3, 0, 4)
    pred$z <- runif(3, 5, 20)
    expect_equal(sum(fgi_apex_labels(pred, ref)$label), audit_apex_match(pred, ref)$apex_TP)
  }
})

test_that("mask labels retain background, unmatched and noncontiguous identities", {
  pred <- c(3, 3, 8, 8, 20, 20, 0, 0)
  ref <- c(7, 7, 40, 40, 0, 0, 60, 60)
  features <- data.frame(instance = c(3, 8, 20), confidence = c(2, 2, 2))
  labels <- fgi_mask_labels(pred, ref, features, c(7, 40, 60))
  expect_equal(labels$label, c(1L, 1L, 0L))
  expect_equal(labels$matched_reference, c(7L, 40L, NA_integer_))
  p <- pred; r <- ref; p[p == 0] <- NA; r[r == 0] <- NA
  expect_equal(sum(labels$label), score_instance_cell(p, r,
    c(`7` = "A", `40` = "B", `60` = "C"))$TP)
  expect_error(fgi_mask_labels(pred[-1], ref, features, c(7, 40, 60)), "misaligned")
  expect_error(fgi_mask_labels(pred, ref, features[-1, ], c(7, 40, 60)), "IDs differ")
  expect_error(fgi_mask_labels(pred, ref, features, c(7, 40)), "IDs differ")
  pred[1] <- -1
  expect_error(fgi_mask_labels(pred, ref, features, c(7, 40, 60)), "Invalid")
})

test_that("weighted PAVA aggregates raw score ties before fitting", {
  score <- c(0, 0, 1); label <- c(0, 1, 0)
  fit <- fgi_fit_isotonic(score, label)
  expect_equal(fit$knots$probability, rep(1 / 3, 2))
  expect_equal(fit$knots$n, c(2L, 1L))
  expect_equal(fit$knots$tp, c(1L, 0L))
  expect_equal(fit, fgi_fit_isotonic(score[c(2, 3, 1)], label[c(2, 3, 1)]))
  fit <- fgi_fit_isotonic(c(10, 10, 20, 30, 40, 40), c(1, 1, 0, 0, 1, 1))
  expect_equal(fit$knots$probability, c(.5, .5, .5, 1))
  expect_equal(fgi_apply_isotonic(fit, c(10, 20, 35, 40)), c(.5, .5, .75, 1))
  expect_true(all(is.na(fgi_apply_isotonic(fit, c(9.99999, 40.00001)))))
  expect_equal(fgi_apply_isotonic(fit, numeric()), numeric())
  expect_error(fgi_fit_isotonic(c(1, Inf), c(0, 1)), "Invalid")
  expect_error(fgi_fit_isotonic(1:2, c(0, NA)), "Invalid")
  expect_error(fgi_apply_isotonic(fit, NA_real_), "Invalid")
})

test_that("unsupported training cells are explicit and never have fallback probabilities", {
  for (pair in list(list(numeric(), numeric(), "no_training_predictions"),
                    list(c(2, 2), c(0, 1), "fewer_than_two_scores"),
                    list(1:3, c(1, 1, 1), "single_class_training"))) {
    fit <- fgi_fit_isotonic(pair[[1]], pair[[2]])
    expect_equal(fit$state, "unavailable")
    expect_equal(fit$reason, pair[[3]])
    expect_equal(nrow(fit$knots), 0)
    expect_true(all(is.na(fgi_apply_isotonic(fit, 1:3))))
  }
})

test_that("calibration metrics pool predictions and expose coverage and undefined cells", {
  rows <- data.frame(probability = c(.25, rep(.25, 9), NA), label = c(1, rep(0, 9), 1))
  metrics <- fgi_calibration_metrics(rows)
  expect_equal(metrics$calibrated, 10)
  expect_equal(metrics$unavailable, 1)
  expect_equal(metrics$unavailable_TP, 1)
  expect_equal(metrics$calibration_coverage, 10 / 11)
  expect_equal(metrics$Brier, (.75^2 + 9 * .25^2) / 10)
  expect_equal(metrics$ECE, .15)
  # Averaging the two per-plot ECEs would give .5, not .15.
  expect_true(is.na(fgi_calibration_metrics(rows[FALSE, ])$ECE))
  expect_true(is.na(fgi_calibration_metrics(rows[11, , drop = FALSE])$Brier))
  rows$probability[1] <- 1.01
  expect_error(fgi_calibration_metrics(rows), "Invalid")
  bins <- reliability_table(c(0, .1, 1), c(0, 0, 1), bins = 10)
  expect_equal(which(bins$n > 0), c(1L, 2L, 10L))
})

fgi_calibration_fixture <- function() {
  cells <- merge(data.frame(plot = FGI_DEVELOPMENT_PLOTS), fgi_calibration_groups())
  cells$n_pred <- cells$n_ref <- 2L
  cells$TP <- cells$FP <- cells$FN <- 1L
  labels <- cells[rep(seq_len(nrow(cells)), each = 2), c("plot", "arm", "target")]
  labels$instance <- rep(c(1L, 9L), nrow(cells))
  labels$raw_score <- rep(c(10, 20), nrow(cells))
  labels$label <- rep(c(0L, 1L), nrow(cells))
  folds <- cells[, c("plot", "arm", "target")]
  folds$fold <- paste0("leave_", folds$plot, "_out")
  folds$calibration_plots <- vapply(folds$plot,
    function(p) paste(setdiff(FGI_DEVELOPMENT_PLOTS, p), collapse = ";"), character(1))
  list(labels = labels, cells = cells, folds = folds)
}

test_that("all fifty whole-plot folds hold out scores and labels and separate targets", {
  fixture <- fgi_calibration_fixture()
  run <- function(x) do.call(fgi_calibrate_complete, c(x, list(n_boot = 5)))
  result <- run(fixture)
  expect_equal(nrow(result$status), 50)
  expect_true(all(result$status$training_predictions == 18))
  expect_true(all(result$pooled$Brier == 0 & result$pooled$ECE == 0))
  expect_equal(result$bootstrap_indices, t(fgi_bootstrap_indices(5)))
  changed <- fixture
  selected <- changed$labels$plot == "1001" & changed$labels$arm == "segmentanytree" &
    changed$labels$target == "apex_max_agl"
  changed$labels$raw_score[selected] <- c(-100, 100)
  changed$labels$label[selected] <- c(1L, 0L) # TP total remains frozen.
  after <- run(changed)
  target_knots <- function(x) x$knots[x$knots$plot == "1001" &
    x$knots$arm == "segmentanytree" & x$knots$target == "apex_max_agl", ]
  expect_equal(target_knots(result), target_knots(after))
  expect_true(all(is.na(after$predictions$probability[after$predictions$plot == "1001" &
    after$predictions$arm == "segmentanytree" & after$predictions$target == "apex_max_agl"])))
  mask_knots <- function(x) x$knots[x$knots$target == "mask_iou_0.5", ]
  expect_equal(mask_knots(result), mask_knots(after))
  bad <- fixture; bad$folds$calibration_plots[1] <- paste(FGI_DEVELOPMENT_PLOTS[-10], collapse = ";")
  expect_error(run(bad), "complement")
  bad <- fixture; bad$cells <- bad$cells[-1, ]
  expect_error(run(bad), "fifty")
  bad <- fixture; bad$labels$plot[1] <- "1003"
  expect_error(run(bad), "population")
  bad <- fixture; bad$labels$label[1] <- 1L
  expect_error(run(bad), "sealed baseline")
})

test_that("empty validation and wholly unavailable fits keep every declared cell", {
  fixture <- fgi_calibration_fixture()
  # All arms/targets have an empty plot, so no prediction row can carry its fold.
  fixture$labels <- fixture$labels[fixture$labels$plot != "1001", ]
  empty <- fixture$cells$plot == "1001"
  fixture$cells[empty, c("n_pred", "TP", "FP")] <- 0L
  fixture$cells$FN[empty] <- fixture$cells$n_ref[empty]
  fixture$labels$raw_score <- rep(10, nrow(fixture$labels))
  result <- do.call(fgi_calibrate_complete, c(fixture, list(n_boot = 2)))
  expect_equal(nrow(result$status), 50)
  expect_equal(sum(result$status$state == "successful_empty"), 5)
  expect_true(all(result$status$fit_state == "unavailable"))
  expect_equal(nrow(result$knots), 0)
  expect_true(all(result$pooled$calibrated == 0))
  expect_true(all(is.na(result$pooled$Brier)))
  expect_true(all(result$intervals$defined_draws[result$intervals$metric == "Brier"] == 0))
})
