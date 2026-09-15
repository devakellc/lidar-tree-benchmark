source(file.path("..", "..", "scripts", "fuse_detectors.R"), local = TRUE)

test_that("RGB summary compares exactly the same plots within each density rung", {
  modes <- c("union", "lidar_nms", "deepforest", "rgb_union", "rgb_nms")
  rows <- expand.grid(config = modes, plot = c("a", "b"),
                       rung = c("native", "1"), stringsAsFactors = FALSE)
  rows$site <- "SOAP"
  rows$n_ref <- 10; rows$n_det <- 12; rows$TP <- 6; rows$tp_core <- 6
  rows$recall <- 0.6; rows$precision <- 0.5
  rows$iou_TP <- 2; rows$iou_FP <- 4; rows$iou_FN <- 8
  rows$iou_n_ref <- 10; rows$iou_sum_iou <- 1.5; rows$iou_sum_maxiou <- 3
  rows <- rows[!(rows$config == "rgb_nms" & rows$plot == "b" & rows$rung == "1"), ]
  result <- rgb_summary(rows)
  expect_true(all(result$n_ref[result$rung == "native"] == 20))
  expect_true(all(result$n_ref[result$rung == "1"] == 10))
  expect_true(all(result$iou_coverage == 0.3))
  expect_true(all(result$iou_PQ == 1.5 / 8))
  empty <- rgb_summary(rows[rows$config != "union", ])
  expect_equal(nrow(empty), 0L)
  expect_identical(names(empty), names(result))

  out <- tempfile(fileext = ".csv")
  summary_path <- sub("[.]csv$", "_summary.csv", out)
  on.exit(unlink(summary_path), add = TRUE)
  write.csv(result, summary_path, row.names = FALSE)
  env <- new.env(parent = environment(run_main))
  env$SITES <- "SOAP"; env$OUT <- out
  env$run_site <- function(site) rows[rows$config == "union", ]
  env$print_report <- function(res) invisible(NULL)
  main <- run_main; environment(main) <- env
  invisible(capture.output(main()))
  expect_equal(nrow(read.csv(summary_path)), 0L)
  expect_identical(names(read.csv(summary_path)), names(result))
})
