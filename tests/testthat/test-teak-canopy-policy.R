source(file.path("..", "..", "scripts", "teak_canopy_lib.R"))
source(file.path("..", "..", "scripts", "teak_canopy_policy_lib.R"))

policy_test_boxes <- function() data.frame(id = c("a", "b"),
  xmin = c(0, 10), ymin = c(0, 10), xmax = c(10, 20), ymax = c(10, 20))
policy_test_plots <- function() data.frame(plotID = c("A", "B", "C", "D"),
  local_use = c("historical_use", rep("no_use_in_pinned_local_inventory", 3)),
  rgb_epsg = 32611L, rgb_xmin = c(0, 90, 180, 500),
  rgb_xmax = c(40, 130, 220, 540), rgb_ymin = 0, rgb_ymax = 40)

test_that("receipt validation binds every output and rejects escaping paths", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE))
  writeLines("content", file.path(root, "file.txt"))
  r <- list(schema_version = 1, evaluation_ready = FALSE,
    outputs = data.frame(path = "file.txt", bytes = file.info(file.path(root, "file.txt"))$size,
      sha256 = canopy_hash(file.path(root, "file.txt"))))
  save <- function() {
    jsonlite::write_json(r, file.path(root, "receipt.json"), auto_unbox = TRUE)
    canopy_hash(file.path(root, "receipt.json"))
  }
  h <- save()
  expect_silent(policy_verify_outputs(root, h))
  expect_error(policy_verify_outputs(root, paste(rep("0", 64), collapse = "")), "Receipt hash")
  writeLines("tampered", file.path(root, "file.txt"))
  expect_error(policy_verify_outputs(root, h), "hash/size")
  r$outputs$path <- "../file.txt"; h <- save()
  expect_error(policy_verify_outputs(root, h), "Unsafe")
  r$outputs$path <- "file.txt"; r$outputs <- rbind(r$outputs, r$outputs); h <- save()
  expect_error(policy_verify_outputs(root, h), "duplicate")
  r$evaluation_ready <- TRUE; h <- save()
  expect_error(policy_verify_outputs(root, h), "readiness")
})

test_that("closed context rectangles group transitively and demote history", {
  x <- policy_test_plots(); pairs <- policy_spatial_pairs(x)
  expect_equal(pairs$context_gap_m[pairs$plot_a == "A" & pairs$plot_b == "B"], 0)
  groups <- policy_groups(x, pairs)
  expect_equal(groups$spatial_group, c("A", "A", "A", "D"))
  expect_equal(groups$role, c(rep("development", 3), "reserved_unadmitted"))
  expect_false(any(groups$evaluation_ready))
  expect_false(any(groups$independent_holdout_claim_supported))
  y <- x[c(4, 3, 1, 2), ]
  expect_equal(policy_groups(y, policy_spatial_pairs(y)), groups)
  x$rgb_epsg[1] <- 3857L
  expect_error(policy_spatial_pairs(x), "EPSG")
  x <- policy_test_plots(); x$plotID[2] <- "A"
  expect_error(policy_spatial_pairs(x), "duplicate")
})

test_that("IoU geometry, boundary clipping and invalid predictions are explicit", {
  b <- policy_test_boxes()
  expect_equal(policy_iou(b, b), diag(2))
  pred <- data.frame(id = c("partial", "outside", "touching"),
    xmin = c(-2, 410, 400), ymin = 0, xmax = c(10, 420, 401), ymax = 10)
  z <- policy_clip_predictions(pred, 400, 400)
  expect_equal(z$boxes$id, "partial"); expect_equal(z$boxes$xmin, 0)
  expect_equal(z$outside_ids, c("outside", "touching"))
  pred$xmin[1] <- NA_real_
  expect_error(policy_clip_predictions(pred, 400, 400), "Invalid box")
  pred$xmin[1] <- pred$xmax[1]
  expect_error(policy_clip_predictions(pred, 400, 400), "Invalid box")
  pred <- b; pred$id[2] <- "a"
  expect_error(policy_clip_predictions(pred, 400, 400), "duplicate")
})

test_that("assignment maximizes cardinality before IoU and includes gate equality", {
  m <- matrix(c(0.9, 0.6, 0.6, 0), 2, byrow = TRUE)
  matched <- policy_match_synthetic(m, c("A", "B"), c("X", "Y"))
  expect_equal(matched$prediction_id, c("Y", "X"))
  expect_equal(nrow(policy_match_synthetic(matrix(0.5), "a", "b")), 1L)
  expect_equal(nrow(policy_match_synthetic(matrix(0.4), "a", "b", 0.4)), 1L)
  expect_equal(nrow(policy_match_synthetic(matrix(0.4), "a", "b")), 0L)
  # Equal cardinality chooses larger sum.
  m <- matrix(c(0.8, 0.5, 0.6, 0.9), 2, byrow = TRUE)
  expect_equal(policy_match_synthetic(m, c("A", "B"), c("X", "Y"))$prediction_id,
    c("X", "Y"))
  expect_error(policy_match_synthetic(matrix(NA_real_), "a", "b"), "Invalid")
  expect_error(policy_match_synthetic(matrix(0, 2, 1), c("a", "a"), "b"), "duplicate")
})

test_that("sorted stable IDs make exact ties independent of row permutation", {
  m <- matrix(0.7, 3, 3); ids <- c("a", "b", "c")
  expected <- policy_match_synthetic(m, ids, ids)
  for (order in list(c(3, 1, 2), c(2, 3, 1), c(3, 2, 1)))
    expect_equal(policy_match_synthetic(m[order, rev(order)], ids[order], ids[rev(order)]), expected)
})

test_that("empty completed predictions differ from unavailable synthetic cells", {
  b <- policy_test_boxes(); empty <- b[FALSE, ]
  completed <- policy_score_synthetic(b, empty, status = "completed_empty")
  expect_equal(completed$TP, 0); expect_equal(completed$FP, 0); expect_equal(completed$FN, 2)
  expect_true(completed$synthetic); expect_false(completed$real_scores)
  expect_false(completed$evaluation_ready)
  expect_equal(policy_score_synthetic(empty, empty)$FN, 0)
  for (status in c("missing", "failed", "not_run")) {
    result <- policy_score_synthetic(b, NULL, status = status)
    expect_true(all(is.na(result[, c("TP", "FP", "FN")])))
    expect_error(policy_score_synthetic(b, empty, status = status), "NULL")
  }
  expect_error(policy_score_synthetic(b, b, status = "completed_empty"), "has predictions")
})

test_that("metadata box flags preserve source coordinates and pending human review", {
  x <- policy_test_plots()[1, ]; x$plotID <- "TEAK_043"; x$image_id <- "TEAK_043_2018"
  x$rgb_resolution_m <- 0.1; x$n_boxes <- 3L
  b <- data.frame(xmin = c(0, 1, 20), ymin = c(10, 10, 20), xmax = c(5, 6, 30),
    ymax = c(20, 20, 30), object_index = 1:3, image_id = x$image_id,
    plotID = x$plotID, local_use = x$local_use, evaluation_ready = FALSE)
  z <- policy_audit_boxes(b, x)
  expect_equal(z[, names(b)], b)
  expect_equal(z$min_edge_px, c(0, 1, 20))
  expect_equal(z$literal_boundary, c(TRUE, FALSE, FALSE))
  expect_equal(z$within_1px, c(TRUE, TRUE, FALSE))
  expect_true(all(z$within_2m)); expect_true(all(z$human_status == "pending"))
  expect_equal(z$overlap_other_box, c(TRUE, TRUE, FALSE))
  b$object_index[2] <- 1L
  expect_error(policy_audit_boxes(b, x), "duplicate")
})

test_that("frozen policy rejects duplicate scope and promoted admission claims", {
  p <- jsonlite::fromJSON(file.path("..", "..", "docs", "teak-canopy-policy.json"))
  expect_silent(policy_validate(p))
  bad <- p; bad$plots$plotID[2] <- bad$plots$plotID[1]
  expect_error(policy_validate(bad), "duplicate")
  bad <- p; bad$plots <- bad$plots[-1, ]
  expect_error(policy_validate(bad), "roles/groups")
  bad <- p; bad$independence_claim_supported <- TRUE
  expect_error(policy_validate(bad), "admission")
  bad <- p; bad$checkpoint_exposure <- "cleared"
  expect_error(policy_validate(bad), "admission")
  bad <- p; bad$plots$evaluation_ready[1] <- TRUE
  expect_error(policy_validate(bad), "roles/groups")
})

test_that("declarations cannot claim semantics different from implemented policy", {
  p <- jsonlite::fromJSON(file.path("..", "..", "docs", "teak-canopy-policy.json"))
  mutations <- list(edge_policy = "ignore all boundary predictions", support = "20 m core",
    target = "all trees", coordinate_frame = "EPSG:3857", group_rule = "pairwise only",
    historical_group_rule = "retain candidate role", outside_predictions = "discard silently",
    invalid_predictions = "repair silently", admission = "evaluation admitted")
  for (field in names(mutations)) {
    bad <- p; bad[[field]] <- mutations[[field]]
    expect_error(policy_validate(bad), "semantic", info = field)
    bad <- p; bad[[field]] <- NULL
    expect_error(policy_validate(bad), "semantic", info = paste("missing", field))
  }
  bad <- p; bad$matching$tie_rule <- "arbitrary order"
  expect_error(policy_validate(bad), "semantic")
  bad <- p; bad$matching$tie_rule <- NULL
  expect_error(policy_validate(bad), "semantic")
  bad <- p; bad$checkpoint_hashes <- NULL
  expect_error(policy_validate(bad), "semantic")
})
