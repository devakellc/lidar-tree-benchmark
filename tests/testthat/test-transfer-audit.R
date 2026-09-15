source(file.path("..", "..", "scripts", "model_bench_lib.R"))
source(file.path("..", "..", "scripts", "external_fgiemit_lib.R"))
source(file.path("..", "..", "scripts", "transfer_audit_lib.R"))

test_that("location diagnostics use one-to-one XY and symmetric Z gates", {
  ref <- data.frame(x = c(0, 0), y = 0, z = c(3, 20))
  pred <- data.frame(x = c(0, 1, 0), y = 0, z = c(3, 3, 26))
  out <- audit_apex_match(pred, ref)
  expect_equal(out$apex_TP, 1)
  expect_equal(out$apex_FP, 2)
  expect_equal(out$apex_FN, 1)
  pred$z[3] <- 25
  expect_equal(audit_apex_match(pred, ref)$apex_TP, 2)
  expect_equal(audit_apex_match(pred[0, ], ref)$apex_TP, 0)
  expect_equal(audit_apex_match(pred, ref[0, ])$apex_TP, 0)
})

test_that("split merge and background diagnostics have explicit overlap denominators", {
  points <- data.frame(X = 1:8, Y = 0, Z = rep(c(2, 5), 4), tree_index = c(1, 1, 1, 1, 2, 2, 0, 0))
  pred <- c(1, 1, 2, 2, 2, 2, 3, 3)
  out <- audit_errors(pred, points)
  expect_equal(out$split_references, 1)
  expect_equal(out$merged_predictions, 1)
  expect_equal(out$background_majority_predictions, 1)
  expect_equal(out$assigned_background_fraction, .25)
  expect_equal(out$tree_point_recall, 1)
})

test_that("XY-only legacy stitching exposes vertical and transitive collisions", {
  pts <- data.frame(block = c(0, 1, 0), inst = c(1, 1, 2),
                    X = c(0, 1, 2), Y = 0, Z = c(3, 20, 3))
  merged <- dedup_blocks(pts, merge_tol = 2)
  expect_equal(length(unique(merged$global_id)), 1)
  # This characterizes an unchanged limitation, not a newly tuned merge policy.
  expect_equal(nrow(merged[merged$block == 0, ]), 2)
})

test_that("duplicate coordinate ambiguity includes background conflicts", {
  src <- data.frame(X = c(0, 0, 1, 1), Y = 0, Z = 2, crown_id = c(1L, NA, 2L, 2L))
  out <- audit_duplicate_stats(src)
  expect_equal(out$duplicate_coordinate_groups, 2)
  expect_equal(out$conflicting_duplicate_groups, 1)
  expect_equal(out$points_in_conflicting_groups, 2)
  expect_equal(src$crown_id, c(1L, NA_integer_, 2L, 2L))
})

test_that("audit analysis rejects modified or missing successful artifacts", {
  path <- tempfile(); on.exit(unlink(path))
  writeLines("original", path)
  expected <- tools::md5sum(path)
  expect_true(audit_verify_hashes(expected))
  expect_true(audit_verify_hashes(as.list(expected)))
  writeLines("changed", path)
  expect_error(audit_verify_hashes(expected), "checksum changed")
  unlink(path)
  expect_error(audit_verify_hashes(expected), "checksum changed")
})

test_that("background-only cylinder support is a valid diagnostic result", {
  points <- data.frame(X = seq_len(80), Y = 0, Z = seq(0, 2, length.out = 80),
                       tree_index = 0L, Classification = 0L)
  out <- audit_label_stats(rep(NA_integer_, 80), points, setNames(character(), character()))
  expect_equal(out$n_ref, 0)
  expect_equal(out$n_pred, 0)
  expect_equal(out$TP, 0)
  expect_equal(out$apex_FP, 0)
  expect_equal(out$split_references, 0)
  expect_equal(out$assigned_background_fraction, 0)
})
