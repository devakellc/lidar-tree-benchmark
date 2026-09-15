source(file.path("..", "..", "scripts", "model_bench_lib.R"))
source(file.path("..", "..", "scripts", "external_fgiemit_lib.R"))

test_that("published test membership cannot leak into training preflight", {
  metadata <- setNames(rep(list(list(test = TRUE)), 6), FGI_TEST_PLOTS)
  metadata[["1001"]] <- list(test = FALSE)
  expect_identical(fgi_plots(metadata), sort(FGI_TEST_PLOTS))
  expect_identical(fgi_plots(metadata, "training"), "1001")
  expect_error(fgi_plots(metadata, "training", "1002"), "requested split")
  expect_error(fgi_plots(metadata, "test", c("1002", "1002")), "unique")
  expect_error(fgi_plots(metadata[-1]), "six-plot")
})

test_that("reference metadata is complete and model inputs contain no annotations", {
  p <- data.frame(X = 1:6, Y = 0, Z = 1:6, Classification = 0:5,
                  tree_index = c(0, 1, 0, 0, 0, 0), red = 9)
  m <- list(n_trees = list(all = 1, A = 0, B = 0, C = 0, D = 1),
            trees = list("1" = list(c = "D")))
  expect_identical(fgi_reference_classes(p, m), c("1" = "D"))
  bad <- m; bad$n_trees$all <- 2
  expect_error(fgi_reference_classes(p, bad), "disagree")
  bad <- p; bad$tree_index[1] <- NA
  expect_error(fgi_reference_classes(bad, m), "integer labels")
  bad <- p; bad$Classification[1] <- 6
  expect_error(fgi_reference_classes(bad, m), "semantic")
  deep <- fgi_model_points(p); classical <- fgi_model_points(p, classical = TRUE)
  expect_equal(deep$X, 1:5)
  expect_equal(classical$X, 1:2)
  expect_true(all(deep$Classification == 1L))
  expect_false(any(c("tree_index", "red") %in% names(deep)))
})

test_that("3D label transfer preserves vertical layers and unassigned neighbors", {
  source <- data.frame(X = c(0, 0, 2), Y = 0, Z = c(2, 20, 2),
                       crown_id = c(1L, 2L, NA_integer_))
  query <- data.frame(X = c(0, 0, 2, 100), Y = 0, Z = c(2.1, 19.9, 2.1, 2))
  mapped <- fgi_transfer_labels(source, query)
  expect_identical(mapped$labels, c(1L, 2L, NA_integer_, NA_integer_))
  expect_equal(mapped$distance[1:3], rep(0.1, 3))
  expect_true(all(is.na(fgi_transfer_labels(source[0, ], query)$labels)))
  expect_length(fgi_transfer_labels(source, query[0, ])$labels, 0L)
  source$X[1] <- Inf
  expect_error(fgi_transfer_labels(source, query), "Non-finite")
})

test_that("official small-instance filters include their exact boundary", {
  pred <- rep(1:3, c(40, 39, 40))
  z <- c(seq(0, 1.5, length.out = 40), seq(0, 3, length.out = 39),
         seq(0, 1.49, length.out = 40))
  filtered <- fgi_filter_predictions(pred, z)
  expect_equal(filtered[1:40], rep(1L, 40))
  expect_true(all(is.na(filtered[-(1:40)])))
})

test_that("aligned transfer preserves duplicate rows and rejects reordered output", {
  src <- data.frame(X = c(0, 0, 1), Y = 0, Z = c(2, 2, 20), crown_id = c(1L, 2L, 0L))
  query <- src[, c("X", "Y", "Z")]
  expect_identical(fgi_aligned_labels(src, query)$labels, c(1L, 2L, NA_integer_))
  expect_error(fgi_aligned_labels(src[c(3, 1, 2), ], query), "order or coordinates")
  expect_error(fgi_aligned_labels(src[-1, ], query), "every input row")
  src$X <- src$X + 0.0005
  expect_identical(fgi_aligned_labels(src, query)$labels, c(1L, 2L, NA_integer_))
})

test_that("scoring ignores boundary objects and retains background false positives", {
  p <- data.frame(X = seq_len(160), Y = 0, Z = rep(seq(0, 2, length.out = 40), 4),
    Classification = rep(c(1L, 1L, 0L, 5L), each = 40),
    tree_index = rep(c(1L, 2L, 0L, 0L), each = 40))
  classes <- c("1" = "A", "2" = "D")
  out <- fgi_score(rep(1:4, each = 40), p, classes)$score
  expect_equal(out$n_pred, 3)
  expect_equal(out$n_ref, 2)
  expect_equal(out$TP, 2)
  expect_equal(out$FP, 1)
  expect_equal(out$tp_D, 1)
  expect_warning(empty <- fgi_score(rep(NA_integer_, 160), p, classes)$score, NA)
  expect_equal(empty$TP, 0)
  expect_equal(empty$FN, 2)
  expect_equal(empty$F1, 0)
  expect_equal(empty$precision, 0)
  expect_equal(empty$coverage, 0)
  expect_error(fgi_score(1L, p, classes), "reference substrate")

  rows <- rbind(cbind(plot = "a", arm = "sat", out),
                cbind(plot = "a", arm = "ff", empty),
                cbind(plot = "b", arm = "sat", out))
  summary <- fgi_summary(rows, c("sat", "ff"))
  expect_equal(summary$n_ref, c(2, 2))
  expect_equal(summary$n_cells, c(1, 1))
  expect_equal(summary$F1, c(0.8, 0))
  expect_false(any(grepl("understory", names(summary))))
  expect_error(fgi_summary(rbind(rows, rows[1, ]), c("sat", "ff")), "Duplicate")
})

test_that("cache reuse requires identical provenance", {
  f <- tempfile(); on.exit(unlink(f))
  manifest <- list(protocol = "frozen", checkpoint = "hash", split = "test")
  expect_false(fgi_manifest(f, manifest))
  saveRDS(manifest, f)
  expect_true(fgi_manifest(f, manifest))
  manifest$checkpoint <- "changed"
  expect_error(fgi_manifest(f, manifest), "provenance differs")
})

test_that("downloads reject invalid splits and preserve corrupt existing archives", {
  env <- new.env(parent = globalenv())
  source(file.path("..", "..", "scripts", "download_external_fgiemit.R"), local = env)
  destination <- tempfile()
  dir.create(destination)
  on.exit(unlink(destination, recursive = TRUE))
  expect_error(env$fgi_download(destination, "validation"), "SPLITS")
  target <- file.path(destination, "plot_data.yaml")
  writeLines("unverified content", target)
  before <- tools::md5sum(target)
  expect_error(env$fgi_download(destination), "Checksum mismatch")
  expect_identical(tools::md5sum(target), before)
})
