source(file.path("..", "..", "scripts", "model_bench_lib.R"), local=TRUE)
source(file.path("..", "..", "scripts", "transfer_audit_lib.R"), local=TRUE)
source(file.path("..", "..", "scripts", "fgiemit_development_summary_lib.R"), local=TRUE)
source(file.path("..", "..", "scripts", "fgiemit_pipeline_lib.R"), local=TRUE)

pipeline_fixture <- function() {
  cells <- expand.grid(plot=FGI_DEVELOPMENT_PLOTS,
    arm=c("chm_vwf", "segmentanytree", "forestformer3d"), stringsAsFactors=FALSE)
  cells$state <- "successful_nonempty"; cells$predictions <- 1L
  cells$reference_count <- 1L; cells$frdens <- 100; cells$pdens <- 150
  pred <- cells[, c("plot", "arm")]
  pred$instance <- 1L; pred$x <- match(pred$arm, unique(pred$arm))*.1
  pred$y <- 0; pred$z <- 10; pred$confidence <- .5
  ref <- data.frame(plot=FGI_DEVELOPMENT_PLOTS, instance=1L, x=0, y=0, z=10, category="A")
  cal <- transform(pred[, c("plot", "arm", "instance")], target="apex_max_agl",
    raw_score=.5, probability=.6, fold=paste0("leave_", plot, "_out"))
  status <- transform(cells[, c("plot", "arm")], target="apex_max_agl",
    fit_state="fitted", fold=paste0("leave_", plot, "_out"))
  list(cells=cells, pred=pred, ref=ref, stage="development", calibration=cal, fit_status=status)
}

test_that("real assembly pools counts and keeps weighted vote semantics separate", {
  b <- pipeline_fixture()
  b$ref <- rbind(b$ref, transform(b$ref[1, ], instance=2L, x=30))
  b$cells$reference_count[b$cells$plot == b$ref$plot[1]] <- 2L
  r <- do.call(fgi_pipeline_analyze, b)
  expect_true(r$complete)
  expect_equal(nrow(r$products), 80L)
  expect_true(all(r$pooled$complete))
  expect_equal(r$pooled$TP, rep(10, 8))
  expect_equal(r$pooled$recall, rep(10/11, 8))
  expect_equal(r$pooled$F1, rep(20/21, 8))
  expect_true(all(r$calibration$probability == .6))
})

test_that("missing support blocks products and cannot change ensemble membership", {
  b <- pipeline_fixture(); b$cells$state[1] <- "failed"; b$cells$predictions[1] <- NA
  r <- do.call(fgi_pipeline_analyze, b)
  expect_false(r$complete); expect_equal(nrow(r$products), 0L)
  expect_equal(nrow(r$status), 30L)
  b$cells <- b$cells[-1, ]
  expect_error(do.call(fgi_pipeline_analyze, b), "Incomplete")
})

test_that("unsupported calibration is explicit even for empty members", {
  b <- pipeline_fixture(); b$calibration$probability[1] <- NA
  r <- do.call(fgi_pipeline_analyze, b)
  weighted <- r$pooled[r$pooled$product == "weighted_all", ]
  expect_false(weighted$complete); expect_equal(weighted$completed_plots, 9L)
  expect_true(is.na(weighted$TP)); expect_equal(sum(r$products$state == "blocked"), 1L)
  b <- pipeline_fixture(); b$cells$frdens[b$cells$plot == "1001"] <- 200
  b$cells$pdens[b$cells$plot == "1001"] <- 250
  r <- do.call(fgi_pipeline_analyze, b)
  expect_true(all(r$calibration$calibration_status[r$calibration$plot == "1001"] == "outside_density_support"))
  b <- pipeline_fixture(); b$cells$predictions <- 0L; b$cells$state <- "successful_empty"
  b$pred <- b$pred[FALSE, ]; b$calibration <- b$calibration[FALSE, ]
  b$fit_status$fit_state[1] <- "unavailable"
  r <- do.call(fgi_pipeline_analyze, b)
  expect_equal(sum(r$products$state == "blocked"), 1L)
  expect_equal(r$pooled$TP[r$pooled$product == "forestformer3d"], 0)
})

test_that("score target, fold leakage and confidence identity cannot be relabelled", {
  for (change in c("target", "fold", "score")) {
    b <- pipeline_fixture()
    if (change == "target") b$calibration$target[1] <- "mask_iou_0.5"
    if (change == "fold") b$calibration$fold[1] <- "leave_1005_out"
    if (change == "score") b$calibration$raw_score[1] <- .8
    expect_error(do.call(fgi_pipeline_analyze, b), "Calibration|calibration")
  }
})

test_that("fusion preserves height gates and fixed two-arm consensus", {
  p <- data.frame(arm=c("segmentanytree", "forestformer3d"), instance=1:2,
                  x=0, y=0, z=c(2, 10), probability=.7)
  expect_equal(nrow(fgi_pipeline_fuse(p, "union_point")), 2L)
  expect_equal(nrow(fgi_pipeline_fuse(p, "consensus_point")), 0L)
  p$z <- c(9, 10)
  expect_equal(nrow(fgi_pipeline_fuse(p, "consensus_point")), 1L)
  expect_equal(fgi_pipeline_fuse(p, "consensus_point")$z, 10)
})

test_that("reserve analysis cannot accept development calibration or fusion policies", {
  expect_identical(fgi_pipeline_candidates("reserve"), c("chm_vwf", "segmentanytree", "forestformer3d"))
  b <- pipeline_fixture(); b$stage <- "reserve"
  keep <- c("1001", "1005", "1009")
  for (name in c("cells", "pred", "ref", "calibration", "fit_status")) {
    b[[name]] <- b[[name]][b[[name]]$plot %in% keep, ]
    b[[name]]$plot <- c("1003", "1010", "1023")[match(b[[name]]$plot, keep)]
  }
  expect_error(do.call(fgi_pipeline_analyze, b), "Reserve calibration")
  b$calibration <- NULL; b$fit_status <- NULL
  r <- do.call(fgi_pipeline_analyze, b)
  expect_equal(nrow(r$products), 9L)
  expect_equal(nrow(r$pooled), 3L)
})
