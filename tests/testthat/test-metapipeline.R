source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "metapipeline_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "metapipeline_synthetic.R"), local = TRUE)

mp_one_cell <- function() {
  b <- metapipeline_synthetic()
  b$cells <- mp_row(b$cells, 1L)
  b$results <- b$results[1:3]
  b
}

# Simulate adapters emitting new receipts after a deliberate declaration change.
# Do not use this helper in tests of stale receipts.
mp_restamp <- function(b) {
  for (i in seq_along(b$results)) {
    r <- b$results[[i]]
    b$results[[i]]$cell <- mp_row(b$cells, match(r$cell$cell_id, b$cells$cell_id))
    b$results[[i]]$arm <- mp_row(b$arms, match(r$arm$arm, b$arms$arm))
  }
  b
}

mp_weighted_fixture <- function() {
  b <- mp_one_cell()
  b$ensemble$method <- "weighted"
  b$ensemble$weight_min <- 1.5
  train <- metapipeline_synthetic()$cells[1:2, ]
  train$cell_id <- c("training_low", "training_high")
  train$plot <- c("training_low", "training_high")
  train$frdens <- c(4, 8)
  train$pdens <- train$native_pdens <- c(8, 12)
  for (j in seq_len(nrow(b$arms))) {
    id <- paste0("toy_lookup_", j)
    b$calibrations[[j]] <- list(id = id, synthetic = TRUE, arm = mp_row(b$arms, j),
      training_cells = train, lookup = data.frame(raw_min = 0, raw_max = 1,
        raw_prob = c(0, 1), calibrated = c(0.2, 1)))
    b$results[[j]]$calibration_id <- id
  }
  b
}

test_that("assembly retains every cell and separates unavailable from empty", {
  b <- metapipeline_synthetic()
  out <- assemble_metapipeline(b)
  expect_identical(out$declaration, b)
  expect_equal(nrow(out$status), 12L)
  expect_equal(table(out$status$status), table(c(rep("completed", 7),
    rep("completed_empty", 3), "failed", "missing")))
  f <- out$products[out$products$product == "fusion", ]
  expect_equal(f$status, c("completed", "completed_empty", "blocked", "blocked"))
  expect_equal(f$n_detections, c(1, 0, NA, NA))
  expect_true(all(f$n_members == 3L))
  expect_equal(out$fused$votes, 2L)
  expect_equal(out$fused$z, 20)
  expect_equal(out$status$n_detections[out$status$status == "completed_empty"], rep(0L, 3))
  expect_true(all(is.na(out$status$n_detections[out$status$status %in% c("failed", "missing")])))
  # Successful controls are still available in a cell whose fusion is blocked.
  expect_equal(out$products$status[out$products$cell_id == "synthetic_3" &
                                    out$products$product == "multichm"], "completed")
  expect_false(any(c("F1", "precision", "recall", "PQ") %in% names(out$products)))
})

test_that("a completed-empty member does not lower consensus requirements", {
  b <- mp_one_cell()
  b$ensemble$k <- 3L
  b$results[[3]]$status <- "completed_empty"
  b$results[[3]]$detections <- mp_empty_detections()
  out <- assemble_metapipeline(b)
  expect_equal(nrow(out$fused), 0L)
  expect_equal(tail(out$products$status, 1), "completed_empty")
  expect_equal(tail(out$products$n_members, 1), 3L)
  # A missing member cannot silently become a two-member consensus.
  b$results <- b$results[1:2]
  expect_equal(tail(assemble_metapipeline(b)$products$status, 1), "blocked")
})

test_that("all-empty fixtures have stable output schemas", {
  b <- metapipeline_synthetic()
  b$cells <- mp_row(b$cells, 2)
  b$results <- b$results[4:6]
  out <- assemble_metapipeline(b)
  expect_equal(nrow(out$apexes), 0)
  expect_equal(nrow(out$fused), 0)
  expect_true(all(out$products$status == "completed_empty"))
  expect_named(out$fused, c("cell_id", "cluster", "x", "y", "z", "votes", "arms", "weight"))
  b$results <- list()
  out <- assemble_metapipeline(b)
  expect_true(all(out$status$status == "missing"))
  expect_equal(tail(out$products$status, 1), "blocked")
})

test_that("explicit control-only arms do not become implicit fusion members", {
  b <- metapipeline_synthetic()
  b$ensemble$members <- c("multichm", "segmentanytree")
  out <- assemble_metapipeline(b)
  f <- out$products[out$products$product == "fusion", ]
  expect_equal(f$status, c("completed", "completed_empty", "completed", "completed"))
  expect_true(all(f$n_members == 2))
  expect_true(all(out$fused$arms == "multichm,segmentanytree"))
  # An unscored control has valid raw detections without inventing confidence.
  b$arms$score_name[3] <- b$arms$score_target[3] <- "none"
  b <- mp_restamp(b)
  for (i in seq_along(b$results)) if (b$results[[i]]$arm$arm == "deepforest")
    b$results[[i]]$detections$raw_score <- rep(NA_real_, nrow(b$results[[i]]$detections))
  expect_true(all(is.na(assemble_metapipeline(b)$apexes$probability)))
})

test_that("matrix identity, status, coordinates and receipt provenance fail closed", {
  b <- mp_one_cell()
  b$results[[4]] <- b$results[[1]]
  expect_error(assemble_metapipeline(b), "Duplicate cell/arm")
  b <- mp_one_cell(); b$results[[1]]$cell$cell_id <- "extra"
  expect_error(assemble_metapipeline(b), "outside the declared")
  b <- mp_one_cell(); b$results[[1]]$status <- "completed_empty"
  expect_error(assemble_metapipeline(b), "status and detection count")
  b <- mp_one_cell(); b$results[[1]]$detections$x <- Inf
  expect_error(assemble_metapipeline(b), "finite numeric")
  b <- mp_one_cell(); b$results[[1]]$detections$arm <- "injected"
  expect_error(assemble_metapipeline(b), "Unexpected detection columns")
  b <- mp_one_cell(); b$results[[1]]$detections <- b$results[[1]]$detections[c(1, 1), ]
  expect_error(assemble_metapipeline(b), "Duplicate detection")
  for (field in c("input_id", "support_id", "census_event", "density_support_id")) {
    b <- mp_one_cell(); b$results[[1]]$cell[[field]] <- "stale"
    expect_error(assemble_metapipeline(b), "cell provenance")
  }
  for (field in c("model_id", "runtime_id", "config_id", "adapter_id", "score_definition_id")) {
    b <- mp_one_cell(); b$results[[1]]$arm[[field]] <- "stale"
    expect_error(assemble_metapipeline(b), "arm provenance")
  }
  b <- mp_one_cell(); b$results[[1]]$reason <- "unexpected error"
  expect_error(assemble_metapipeline(b), "status and reason")
  expect_error(mp_result(metapipeline_synthetic()$cells, b$arms[1, ],
                        "missing", source_id = "test"), "one cell")
})

test_that("density measurements, CRS and AGL cannot be guessed or upsampled", {
  for (field in c("frdens", "pdens", "native_pdens")) {
    b <- mp_one_cell(); b$cells[[field]] <- NA_real_
    expect_error(assemble_metapipeline(b), "finite and positive")
  }
  b <- mp_one_cell(); b$cells$rung <- "12"
  expect_error(assemble_metapipeline(b), "No-upsampling")
  b <- mp_one_cell(); b$cells$frdens <- 11
  expect_error(assemble_metapipeline(b), "frdens <= pdens")
  for (epsg in c(3857, 4326, 2277)) {
    b <- mp_one_cell(); b$cells$epsg <- epsg
    expect_error(assemble_metapipeline(b), "projected metric CRS")
  }
  b <- mp_one_cell(); b$cells$height_datum <- "absolute"
  expect_error(assemble_metapipeline(b), "AGL")
})

test_that("support is retained across rungs and diagnostic support blocks products", {
  b <- mp_one_cell()
  b$cells$support_admitted <- FALSE
  b$cells$support_blockers <- "Unresolved reference geometry"
  b <- mp_restamp(b)
  out <- assemble_metapipeline(b)
  expect_true(all(out$products$status == "blocked"))
  expect_true(all(is.na(out$products$n_detections)))
  expect_equal(nrow(out$apexes), 3L) # raw receipts remain inspectable
  b$cells$support_admitted <- TRUE
  expect_error(assemble_metapipeline(b), "admission and blockers")
  b <- mp_one_cell()
  sparse <- b$cells; sparse$cell_id <- "sparse"; sparse$rung <- "2"
  sparse$pdens <- 2; sparse$frdens <- 1
  sparse$support_id <- "different_population"
  b$cells <- rbind(b$cells, sparse)
  expect_error(assemble_metapipeline(b), "Inconsistent plot support")
})

test_that("eligible members and controls are explicit and historical layouts stay out", {
  b <- mp_one_cell(); b$ensemble$members <- character()
  expect_error(assemble_metapipeline(b), "explicitly name")
  b <- mp_one_cell(); b$ensemble$controls <- "unknown"
  expect_error(assemble_metapipeline(b), "explicitly name")
  b <- mp_one_cell(); b$ensemble$k <- 4L
  expect_error(assemble_metapipeline(b), "consensus k")
  b <- mp_one_cell(); b$arms$arm[1] <- "treeisonet"
  expect_error(assemble_metapipeline(b), "deferred")
  b <- mp_one_cell(); b$arms$arm[1] <- "forestformer3d"
  expect_error(assemble_metapipeline(b), "indexed_whole_scene")
  b$arms$layout[1] <- "indexed_whole_scene"
  expect_silent(mp_arms(b$arms))
  b <- mp_one_cell(); b$mode <- "real"
  expect_error(assemble_metapipeline(b), "synthetic bundles")
})

test_that("mask descriptors are preserved without generating mask metrics", {
  b <- mp_one_cell()
  b$arms$mask_type <- c("reference_proxy", "predicted_instances", "none")
  b <- mp_restamp(b)
  for (j in 1:2) b$results[[j]]$mask <- list(type = b$arms$mask_type[j],
    artifact_id = paste0("synthetic_mask_", j), point_identity_id = "synthetic_row_ids",
    background_label = 0L)
  out <- assemble_metapipeline(b)
  expect_identical(out$declaration$results[[2]]$mask, b$results[[2]]$mask)
  b$results[[1]]$mask$type <- "predicted_instances"
  expect_error(assemble_metapipeline(b), "Mask type mismatch")
  b$results[[1]]$mask <- NULL
  expect_error(assemble_metapipeline(b), "lacks required fields")
})

test_that("compatible toy calibration reuses the weighted fusion helper", {
  b <- mp_weighted_fixture()
  out <- assemble_metapipeline(b)
  expect_equal(out$apexes$probability, rep(0.84, 3))
  expect_equal(nrow(out$fused), 1)
  expect_equal(out$fused$weight, 1.68)
  expect_equal(out$fused$votes, 2L)
  # Result list order cannot choose a different representative or state ordering.
  b$results <- rev(b$results)
  reordered <- assemble_metapipeline(b)
  expect_identical(reordered$fused, out$fused)
  expect_identical(reordered$status, out$status)
  for (i in seq_along(b$results)) {
    b$results[[i]]$status <- "completed_empty"
    b$results[[i]]$detections <- mp_empty_detections()
  }
  expect_equal(tail(assemble_metapipeline(b)$products$status, 1), "completed_empty")
  b$results[[1]]$calibration_id <- ""
  expect_error(assemble_metapipeline(b), "Missing compatible calibration")
})

test_that("calibration rejects leakage, unknown domains and stale score definitions", {
  for (field in c("model_id", "config_id", "adapter_id", "score_definition_id")) {
    b <- mp_weighted_fixture(); b$calibrations[[1]]$arm[[field]] <- "old"
    expect_error(assemble_metapipeline(b), "Calibration arm provenance")
  }
  b <- mp_weighted_fixture(); b$calibrations[[1]]$training_cells$plot[1] <- b$cells$plot
  # Even a different density of the target plot is leakage.
  b$calibrations[[1]]$training_cells$rung[1] <- "4"
  expect_error(assemble_metapipeline(b), "whole plot")
  for (field in c("dataset", "support_policy", "reference_population")) {
    b <- mp_weighted_fixture(); b$calibrations[[1]]$training_cells[[field]] <- "other"
    expect_error(assemble_metapipeline(b), "Calibration support mismatch")
  }
  b <- mp_weighted_fixture(); b$calibrations[[1]]$training_cells$site <- "unseen_site"
  expect_error(assemble_metapipeline(b), "site and density rung")
  b <- mp_weighted_fixture(); b$calibrations[[1]]$training_cells$rung <- "4"
  expect_error(assemble_metapipeline(b), "site and density rung")
  b <- mp_weighted_fixture(); b$calibrations[[1]]$training_cells$frdens <- c(7, 8)
  expect_error(assemble_metapipeline(b), "outside training support")
  b <- mp_weighted_fixture(); b$calibrations[[1]]$training_cells$support_admitted <- FALSE
  b$calibrations[[1]]$training_cells$support_blockers <- "diagnostic"
  expect_error(assemble_metapipeline(b), "admitted reference support")
  b <- mp_weighted_fixture(); b$results[[1]]$calibration_id <- ""
  expect_error(assemble_metapipeline(b), "Missing compatible calibration")
  b <- mp_weighted_fixture(); b$calibrations[[1]]$synthetic <- FALSE
  expect_error(assemble_metapipeline(b), "synthetic calibration")
  b <- mp_weighted_fixture(); b$arms$score_target[1] <- "instance_iou"
  b <- mp_restamp(b); b$calibrations[[1]]$arm <- mp_row(b$arms, 1)
  expect_error(assemble_metapipeline(b), "target must be apex_distance")
  b <- mp_weighted_fixture(); b$calibrations[[1]]$lookup$calibrated <- c(0.9, 0.1)
  expect_error(assemble_metapipeline(b), "monotone probability")
  b <- mp_weighted_fixture(); b$calibrations[[1]]$lookup$arm <- "different_arm"
  expect_error(assemble_metapipeline(b), "Lookup metadata")
  b <- mp_weighted_fixture(); b$calibrations[[1]]$training_cells$pdens <- c(11, 12)
  b$calibrations[[1]]$training_cells$native_pdens <- c(11, 12)
  expect_error(assemble_metapipeline(b), "outside training support: pdens")
})

test_that("the CLI writes verifiable synthetic artifacts and preserves previous runs", {
  root <- normalizePath(file.path("..", ".."))
  driver <- file.path(root, "scripts", "assemble_metapipeline.R")
  out <- tempfile("synthetic assembly=")
  on.exit(unlink(out, recursive = TRUE))
  run <- function(args) suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    shQuote(c(driver, args)), stdout = TRUE, stderr = TRUE))
  message <- run(c("MODE=synthetic", paste0("OUT=", out)))
  expect_null(attr(message, "status"), info = paste(message, collapse = "\n"))
  manifest <- jsonlite::read_json(file.path(out, "manifest.json"), simplifyVector = TRUE)
  expect_false(manifest$inference_run)
  expect_false(manifest$calibration_fitted)
  expect_false(manifest$metrics_computed)
  for (nm in names(manifest$output_sha256)) expect_identical(
    digest::digest(file = file.path(out, nm), algo = "sha256"), manifest$output_sha256[[nm]])
  before <- tools::md5sum(list.files(out, full.names = TRUE))
  again <- run(paste0("OUT=", out))
  expect_equal(attr(again, "status"), 1L)
  expect_match(paste(again, collapse = "\n"), "Output exists")
  expect_identical(tools::md5sum(names(before)), before)
  invalid <- run(c("MODE=infer", paste0("OUT=", out)))
  expect_match(paste(invalid, collapse = "\n"), "MODE must be synthetic")
  input <- tempfile("synthetic input=", fileext = ".rds")
  replay <- tempfile("synthetic replay=")
  on.exit(unlink(c(input, replay), recursive = TRUE), add = TRUE)
  bundle <- readRDS(file.path(out, "assembly.rds"))$declaration
  saveRDS(bundle, input)
  old <- getwd(); on.exit(setwd(old), add = TRUE)
  setwd(tempdir())
  message <- run(c(paste0("INPUT=", input), paste0("OUT=", replay)))
  expect_null(attr(message, "status"), info = paste(message, collapse = "\n"))
  expect_identical(readRDS(file.path(replay, "assembly.rds")), readRDS(file.path(out, "assembly.rds")))
})
