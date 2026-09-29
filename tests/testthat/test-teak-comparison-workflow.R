source(file.path("..", "..", "scripts", "teak_canopy_lib.R"))
source(file.path("..", "..", "scripts", "teak_canopy_policy_lib.R"))
source(file.path("..", "..", "scripts", "teak_comparison_workflow_lib.R"))

workflow_fixture <- function(root) {
  dir.create(root)
  repo <- normalizePath(file.path("..", ".."))
  original <- data.frame(box_key = c("invented:1", "invented:2"), xmin = c(10, 30),
    ymin = c(10, 30), xmax = c(20, 40), ymax = c(20, 40))
  support <- workflow_support()
  templates <- workflow_templates(original, support)
  read_template <- function(name, csv = FALSE) {
    p <- file.path(root, name); writeBin(templates[[name]], p)
    if (csv) workflow_table(p) else workflow_read(p)
  }
  review <- read_template("reference_review_template.csv", TRUE)
  review$action <- "keep"; review[, c("xmin", "ymin", "xmax", "ymax")] <- original[, -1]
  for (f in c("edge_decision", "overlap_decision", "split_merge_decision", "vegetation_decision"))
    review[[f]] <- "resolved_synthetic"
  review$rationale <- "Invented unit-test objects; no real observations"
  review$uncertainty_note <- "Synthetic exact geometry"
  review$evidence_id <- "attestation"; review$reviewer_id <- "synthetic_test_identity"
  review$reviewed_utc <- "2026-01-02T00:00:00Z"
  whole <- read_template("whole_image_review_template.json")
  whole$origin <- "human_supplied"; whole$revision_id <- "invented-revision"
  whole$reviewer_id <- "synthetic_test_identity"; whole$supplied_by <- "synthetic_test_identity"
  whole$review_started_utc <- "2026-01-02T00:00:00Z"
  whole$reviewed_utc <- "2026-01-03T00:00:00Z"; whole$predictions_seen <- "unknown"
  whole$attestation_evidence_id <- "attestation"
  whole$authenticity <- "self_attested_not_independently_authenticated"
  whole$method <- "Synthetic fixture only, not a real human review"
  whole$whole_image <- list(completeness = "resolved", unboxed_canopy = "resolved",
    ambiguous_vegetation = "resolved", edge_truncation = "resolved", rationale = "Invented complete fixture")
  tiles <- workflow_tiles(); tiles$status <- "reviewed"; tiles$observation <- "Invented full tile observation"
  tiles$reviewer_id <- "synthetic_test_identity"; tiles$reviewed_utc <- whole$reviewed_utc
  tiles$evidence_id <- "attestation"
  registration <- read_template("registration_template.json")
  registration$status <- "measured"; registration$method <- "Invented independent ground fixture"
  registration$criterion_frozen_utc <- "2026-01-01T00:00:00Z"
  registration$measured_utc <- "2026-01-01T12:00:00Z"
  registration$evidence_id <- "measurement"; registration$reviewer_id <- "synthetic_test_identity"
  registration$max_residual_m <- 1; registration$max_combined_uncertainty_m <- .5
  ties <- data.frame(id = c("a", "b", "c"), status = "accepted", feature_type = "stable_ground",
    description = "Invented ground feature", rgb_x_px = c(0, 400, 0), rgb_y_px = c(0, 0, 400),
    lidar_x_m = c(321034.5, 321074.5, 321034.5), lidar_y_m = c(4096751.1, 4096751.1, 4096711.1),
    rgb_uncertainty_m = .1, lidar_uncertainty_m = .1, independent_method = "surveyed_ground",
    stable_between_dates = "yes", evidence_id = "measurement", reviewer_id = "synthetic_test_identity",
    rejection_reason = "")
  timing <- read_template("timing_evidence_template.json")
  timing$status <- "reviewed_conditional"; timing$route <- "conditional_historical"
  timing$evidence_id <- "decision"; timing$reviewer_id <- "synthetic_test_identity"
  timing$rationale <- "Invented conditional comparison"; timing$limitations <- "Timing remains unknown"
  exposure <- read_template("checkpoint_exposure_template.csv", TRUE)
  exposure$evidence_id <- "decision"; exposure$reviewer_id <- "synthetic_test_identity"
  exposure$rationale <- "Synthetic unknown-exposure condition; no generalization"
  adapter <- read_template("crown_adapter_template.json")
  adapter$status <- "reviewed"; adapter$output_target <- "visible_canopy_crown_boxes"
  adapter$input_geometry <- "crown_geometry"; adapter$construction_rule <- "Synthetic crown boundary extents"
  adapter$frozen_utc <- "2026-01-01T00:00:00Z"; adapter$reviewer_id <- "synthetic_test_identity"
  adapter$evidence_id <- "decision"; adapter$reference_consulted <- FALSE
  adapter$code_artifact <- "adapter_code"; adapter$validation_artifact <- "adapter_validation"
  m <- read_template("admission_manifest_template.json")
  m$status <- "frozen"; m$reference_revision <- "invented-revision"
  m$temporal_route <- "conditional_historical"; m$exposure_route <- "conditional_development"
  m$limitations <- "Synthetic test; historical development only; unknown timing/exposure"
  artifacts <- list(reference_review = workflow_csv(review), whole_image_review = workflow_json(whole),
    tile_review = workflow_csv(tiles), registration = workflow_json(registration),
    registration_ties = workflow_csv(ties), timing = workflow_json(timing), exposure = workflow_csv(exposure),
    adapter = workflow_json(adapter), config = workflow_json(list(fixture = TRUE)),
    source = charToRaw("invented crown source geometry"), adapter_code = charToRaw("invented code"),
    adapter_validation = charToRaw("invented validation record"))
  predictions <- data.frame(id = c("p1", "p2", "outside"), source_prediction_id = c("s1", "s2", "s3"),
    xmin = c(10, 30, 500), ymin = c(10, 30, 500), xmax = c(20, 40, 510), ymax = c(20, 40, 510))
  artifacts$predictions <- workflow_csv(predictions)
  artifacts$empty <- workflow_csv(cbind(workflow_empty_boxes(), source_prediction_id = character()))
  for (name in names(artifacts)) {
    p <- file.path(root, paste0(name, if (name %in% c("reference_review", "tile_review", "registration_ties",
      "exposure", "predictions", "empty")) ".csv" else ".json"))
    writeBin(artifacts[[name]], p); m$artifacts[[name]] <- as.list(workflow_record(p, basename(p)))
  }
  for (name in c("attestation", "measurement", "decision")) {
    p <- file.path(root, paste0(name, ".txt")); writeLines("Synthetic evidence fixture only", p)
    m$evidence[[name]] <- c(as.list(workflow_record(p, basename(p))), list(supplied_by = "synthetic_test_identity",
      verified_by = "synthetic_test_identity", kind = switch(name, attestation = "human_attestation",
        measurement = "independent_measurement", decision = "review_record")))
  }
  checkpoints <- jsonlite::fromJSON(file.path(repo, "docs/teak-canopy-policy.json"))$checkpoint_hashes
  outputs <- list()
  add_artifact <- function(name, bytes, suffix = ".json") {
    p <- file.path(root, paste0(name, suffix)); writeBin(bytes, p)
    m$artifacts[[name]] <<- as.list(workflow_record(p, basename(p)))
  }
  for (i in seq_along(m$arms)) {
    a <- m$arms[[i]]; a$status <- if (i == 2) "completed_empty" else "completed"
    a$reference_revision <- m$reference_revision
    a$checkpoint_sha256 <- if (a$arm == "chm_vwf") "not_applicable" else checkpoints[[a$arm]]
    a$config_artifact <- "config"
    a$source_artifact <- paste0("source_", a$arm)
    a$prediction_artifact <- if (i == 2) "empty" else "predictions"
    a$adapter_artifact <- paste0("adapter_", a$arm)
    dir.create(file.path(root, a$arm))
    relative <- paste0(a$arm, if (i == 1) "/raw_treetops.csv" else "/normalized_predictions.laz")
    source_bytes <- if (i == 1) workflow_csv(data.frame(instance = c("s1", "s2", "s3"))) else
      charToRaw(paste("Synthetic", a$arm, "instance geometry"))
    add_artifact(a$source_artifact, source_bytes)
    writeBin(source_bytes, file.path(root, relative))
    source_sha <- canopy_hash(file.path(root, relative)); outputs[[relative]] <- source_sha
    memberships <- vapply(c("s1", "s2", "s3"), function(id)
      digest::digest(paste(source_sha, id, sep = ":"), algo = "sha256", serialize = FALSE), "")
    if (i != 1) {
      diag <- list(point_extent_proxies = lapply(1:3, function(j) list(instance = paste0("s", j),
        source_rows_sha256 = unname(memberships[j]), raw_pixel_box = c(-10, -10, -1, -1))))
      relative <- paste0(a$arm, "/diagnostics.json")
      writeBin(workflow_json(diag), file.path(root, relative))
      outputs[[relative]] <- canopy_hash(file.path(root, relative))
    }
    lineage <- data.frame(source_prediction_id = c("s1", "s2", "s3"),
      source_membership_sha256 = unname(memberships), status = if (i == 2) "excluded" else "boxed",
      box_id = if (i == 2) "" else predictions$id,
      exclusion_reason = if (i == 2) "Synthetic completed-empty fixture" else "")
    vertices <- if (i == 2) data.frame(id = character(), vertex = integer(), x = numeric(), y = numeric()) else
      do.call(rbind, lapply(1:3, function(j) data.frame(id = predictions$id[j], vertex = 1:4,
        x = c(predictions$xmin[j], predictions$xmax[j], predictions$xmax[j], predictions$xmin[j]),
        y = c(predictions$ymin[j], predictions$ymin[j], predictions$ymax[j], predictions$ymax[j]))))
    adapted <- adapter
    adapted$lineage_artifact <- paste0("lineage_", a$arm)
    adapted$boundary_artifact <- paste0("boundaries_", a$arm)
    adapted$validation_artifact <- paste0("validation_", a$arm)
    add_artifact(adapted$lineage_artifact, workflow_csv(lineage), ".csv")
    add_artifact(adapted$boundary_artifact, workflow_csv(vertices), ".csv")
    dependencies <- c(code = adapted$code_artifact, config = a$config_artifact,
      source = a$source_artifact, prediction = a$prediction_artifact,
      boundaries = adapted$boundary_artifact, lineage = adapted$lineage_artifact)
    validation <- list(status = "reviewed_crown_boundary_adapter", reference_consulted = FALSE,
      method = "Synthetic independent adapter fixture", limitations = "Not real validation",
      reviewer_id = "synthetic_test_identity", evidence_id = "decision",
      sha256 = lapply(dependencies, function(id) m$artifacts[[id]]$sha256))
    add_artifact(adapted$validation_artifact, workflow_json(validation))
    add_artifact(a$adapter_artifact, workflow_json(adapted))
    m$arms[[i]] <- a
    outputs[[paste0(a$arm, "/config.json")]] <- m$artifacts$config$sha256
  }
  manifest <- file.path(root, "admission_manifest.json"); writeBin(workflow_json(m), manifest)
  parents <- list(repo = repo, boxes = original, support = support,
    roots = setNames(as.list(rep(root, 6)), names(workflow_parent_spec())),
    receipts = list(smoke = list(output_sha256 = outputs)))
  list(root = root, m = m, parents = parents, hash = canopy_hash(manifest))
}
workflow_fixture_update <- function(f, artifact, value, csv = FALSE) {
  p <- file.path(f$root, f$m$artifacts[[artifact]]$path)
  writeBin(if (csv) workflow_csv(value) else workflow_json(value), p)
  f$m$artifacts[[artifact]] <- as.list(workflow_record(p, basename(p)))
  writeBin(workflow_json(f$m), file.path(f$root, "admission_manifest.json"))
  f$hash <- canopy_hash(file.path(f$root, "admission_manifest.json")); f
}
workflow_fixture_load <- function(f) workflow_bundle(f$root, f$hash)

test_that("current preflight blocks and generated review has no human decisions", {
  parent <- list(roots = setNames(as.list(rep("/unread", 6)), names(workflow_parent_spec())))
  gates <- workflow_current_gates(parent)
  expect_equal(sum(gates$status == "pass"), 2L)
  expect_true(all(c("pending", "unknown", "unsupported", "not_run") %in% gates$status))
  expect_false(any(c("TP", "FP", "FN", "evaluation_ready", "admitted") %in% names(gates)))
  expect_error(workflow_compare(list(status = "blocked"), NULL), "before reference/prediction")
})

test_that("invented admitted evidence exercises full paired scorer without real inputs", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  b <- workflow_fixture_load(f); a <- workflow_admission(b, f$parents)
  expect_equal(a$status, "admitted_historical_diagnostic", info = paste(a$gates$reason, collapse = ";"))
  products <- workflow_compare(a, b)
  rows <- read.csv(text = rawToChar(products$comparison_cells.csv))
  expect_equal(nrow(rows), 6L)
  expect_equal(rows$TP[rows$arm == "chm_vwf"], c(2L, 2L))
  expect_equal(rows$outside_predictions[rows$arm == "chm_vwf"], c(1L, 1L))
  expect_equal(rows$FN[rows$arm == "segmentanytree"], c(2L, 2L))
  expect_true(all(is.na(rows$precision[rows$arm == "segmentanytree"])))
  expect_equal(rows$F1[rows$arm == "segmentanytree"], c(0, 0))
})

test_that("generated, incomplete, changed and duplicated review records block", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  original <- f
  w <- workflow_read(file.path(root, f$m$artifacts$whole_image_review$path))
  w$origin <- "generated_template_not_evidence"; f <- workflow_fixture_update(f, "whole_image_review", w)
  a <- workflow_admission(workflow_fixture_load(f), f$parents)
  expect_equal(a$status, "blocked"); expect_match(a$gates$reason[a$gates$gate == "reference_revision"], "not a human")
  w$origin <- "human_supplied"; f <- workflow_fixture_update(f, "whole_image_review", w)
  r <- workflow_table(file.path(root, f$m$artifacts$reference_review$path))
  for (bad in list(r[-1, ], r[c(1, 1), ], transform(r, original_xmin = original_xmin + 1))) {
    z <- workflow_fixture_update(f, "reference_review", bad, TRUE)
    expect_equal(workflow_admission(workflow_fixture_load(z), z$parents)$status, "blocked")
  }
  f <- workflow_fixture_update(f, "reference_review", r, TRUE)
  t <- workflow_table(file.path(root, f$m$artifacts$tile_review$path))
  f <- workflow_fixture_update(f, "tile_review", t[-1, ], TRUE)
  expect_equal(workflow_admission(workflow_fixture_load(f), f$parents)$status, "blocked")
})

test_that("byte tampering, resealing flags and unauthorized roles cannot admit", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  f$m$evaluation_ready <- TRUE; f$m$support$plot <- "TEAK_049"
  writeBin(workflow_json(f$m), file.path(root, "admission_manifest.json"))
  expect_error(workflow_fixture_load(f), "Changed input")
  f$hash <- canopy_hash(file.path(root, "admission_manifest.json"))
  expect_equal(workflow_admission(workflow_fixture_load(f), f$parents)$status, "blocked")
  writeLines("tampered", file.path(root, f$m$evidence$attestation$path))
  expect_error(workflow_fixture_load(f), "Changed input")
})

test_that("unsupported adapters, arm status, configurations and support block pairing", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  adapter <- workflow_read(file.path(root, f$m$artifacts$adapter_chm_vwf$path))
  for (geometry in c("treetops", "sparse_point_extent_proxy")) {
    bad <- adapter; bad$input_geometry <- geometry
    z <- workflow_fixture_update(f, "adapter_chm_vwf", bad)
    expect_equal(workflow_admission(workflow_fixture_load(z), z$parents)$status, "blocked")
  }
  f <- workflow_fixture_update(f, "adapter_chm_vwf", adapter)
  base <- f$m
  for (state in c("missing", "failed", "not_run", "unsupported")) {
    f$m <- base; f$m$arms[[1]]$status <- state
    writeBin(workflow_json(f$m), file.path(root, "admission_manifest.json"))
    f$hash <- canopy_hash(file.path(root, "admission_manifest.json"))
    expect_equal(workflow_admission(workflow_fixture_load(f), f$parents)$status, "blocked")
  }
  f$m <- base; f$m$arms[[1]]$support$spatial_group <- "TEAK_049"
  writeBin(workflow_json(f$m), file.path(root, "admission_manifest.json"))
  f$hash <- canopy_hash(file.path(root, "admission_manifest.json"))
  expect_equal(workflow_admission(workflow_fixture_load(f), f$parents)$status, "blocked")
})

test_that("independent registration rejects canopy ties, residual and coverage failures", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  ties <- workflow_table(file.path(root, f$m$artifacts$registration_ties$path))
  for (bad in list(transform(ties, feature_type = "canopy"), transform(ties, lidar_x_m = lidar_x_m + 10),
                   ties[1:2, ])) {
    z <- workflow_fixture_update(f, "registration_ties", bad, TRUE)
    expect_equal(workflow_admission(workflow_fixture_load(z), z$parents)$status, "blocked")
  }
})

test_that("policy matcher, inclusive thresholds, clipping and pooled counts are retained", {
  r <- data.frame(id = "r", xmin = 0, ymin = 0, xmax = 10, ymax = 10)
  p <- data.frame(id = "p", xmin = 0, ymin = 0, xmax = 20, ymax = 10)
  expect_equal(workflow_score(r, p, .5, "completed")$counts$TP, 1L)
  p$xmax <- 25
  expect_equal(workflow_score(r, p, .5, "completed")$counts$TP, 0L)
  expect_equal(workflow_score(r, p, .4, "completed")$counts$TP, 1L)
  p$xmin <- -5; p$xmax <- 10
  expect_equal(workflow_score(r, p, .5, "completed")$counts$TP, 1L)
  p$xmax <- -10
  expect_error(workflow_score(r, p, .5, "completed"), "Invalid box")
  expect_error(workflow_score(r, workflow_empty_boxes(), .5, "completed"), "Outcome")
  cells <- expand.grid(arm = workflow_arms, plot = c("invented_A", "invented_B"), threshold = c(.5, .4),
    stringsAsFactors = FALSE)
  cells$support_key <- cells$plot; cells$reference_revision <- "synthetic"
  cells$TP <- ifelse(cells$plot == "invented_A", 1, 0); cells$FP <- ifelse(cells$plot == "invented_A", 0, 9)
  cells$FN <- 0; cells$n_ref <- cells$TP; cells$n_prediction <- cells$TP + cells$FP; cells$outside_predictions <- 0
  pooled <- workflow_pool(cells); expect_equal(pooled$precision, rep(.1, 6))
  expect_error(workflow_pool(cells[-1, ]), "Unequal")
})

test_that("receipt replay is write-free and rejects resealed product changes", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  products <- list("preflight.json" = workflow_json(list(status = "blocked")))
  workflow_emit(root, products, list(), list(), "preflight")
  paths <- list.files(root, full.names = TRUE); before <- file.info(paths)$mtime
  expect_silent(workflow_emit(root, products, list(), list(), "preflight", TRUE))
  expect_identical(file.info(paths)$mtime, before)
  bad <- list("preflight.json" = workflow_json(list(status = "admitted")))
  writeBin(bad[[1]], file.path(root, "preflight.json"))
  receipt <- workflow_read(file.path(root, "receipt.json"))
  receipt$outputs[[1]]$sha256 <- canopy_hash(file.path(root, "preflight.json"))
  writeBin(workflow_json(receipt), file.path(root, "receipt.json"))
  expect_error(workflow_emit(root, products, list(), list(), "preflight", TRUE), "Recomputed output")
})

test_that("working outputs under checkout work are allowed while source paths are protected", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE))
  dir.create(file.path(root, "work")); dir.create(file.path(root, "work", "input"))
  expect_equal(workflow_output_path(file.path(root, "work", "fresh"), file.path(root, "work"),
    root, file.path(root, "work", "input")), file.path(root, "work", "fresh"))
  for (out in c(root, file.path(root, "scripts", "new"), file.path(root, "other"),
                file.path(root, "work", "input", "new"))) {
    expect_error(workflow_output_path(out, file.path(root, "work"), root,
      file.path(root, "work", "input")), "protected")
  }
})

test_that("blocked comparison preserves report but signals failure for run and replay", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  products <- list("preflight.json" = workflow_json(list(status = "blocked")))
  workflow_emit(root, products, list(), list(), "compare")
  before <- file.info(list.files(root, full.names = TRUE))$mtime
  workflow_emit(root, products, list(), list(), "compare", verify = TRUE)
  expect_identical(file.info(list.files(root, full.names = TRUE))$mtime, before)
  expect_equal(workflow_exit_status("preflight", "blocked"), 0L)
  expect_equal(workflow_exit_status("compare", "blocked"), 2L)
  expect_equal(workflow_exit_status("compare", "admitted_historical_diagnostic"), 0L)
  expression <- sprintf('source("%s"); quit(status=workflow_exit_status("compare","blocked"),save="no")',
    normalizePath(file.path("..", "..", "scripts", "teak_comparison_workflow_lib.R")))
  expect_equal(suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c("-e", shQuote(expression)), stdout = FALSE, stderr = FALSE)), 2L)
})

test_that("near-duplicate and collinear accepted ground features remain blocked", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  t <- workflow_table(file.path(root, f$m$artifacts$registration_ties$path))
  duplicate <- rbind(t, t[1, ]); duplicate$id[4] <- "d"
  near_duplicate <- duplicate
  near_duplicate$rgb_x_px[4] <- .25; near_duplicate$lidar_x_m[4] <- 321034.525
  collinear <- t; collinear$rgb_x_px <- collinear$rgb_y_px <- c(0, 200, 400)
  collinear$lidar_x_m <- 321034.5 + .1 * collinear$rgb_x_px
  collinear$lidar_y_m <- 4096751.1 - .1 * collinear$rgb_y_px
  for (bad in list(duplicate, near_duplicate, collinear)) {
    z <- workflow_fixture_update(f, "registration_ties", bad, TRUE)
    a <- workflow_admission(workflow_fixture_load(z), z$parents)
    expect_equal(a$status, "blocked")
    expect_match(a$gates$reason[a$gates$gate == "registration"], "distinct.*noncollinear")
  }
})

test_that("preflight catches complete-empty count mismatch and substituted source files", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  for (i in 1:2) {
    z <- f; z$m$arms[[i]]$status <- if (i == 1) "completed_empty" else "completed"
    writeBin(workflow_json(z$m), file.path(root, "admission_manifest.json"))
    z$hash <- canopy_hash(file.path(root, "admission_manifest.json"))
    a <- workflow_admission(workflow_fixture_load(z), z$parents)
    expect_equal(a$status, "blocked")
    expect_match(a$gates$reason[a$gates$gate == "paired_outcomes"], "Outcome/prediction")
  }
  z <- workflow_fixture_update(f, "source_chm_vwf", list(invented_ids = c("other1", "other2")))
  a <- workflow_admission(workflow_fixture_load(z), z$parents)
  expect_equal(a$status, "blocked")
  expect_match(a$gates$reason[a$gates$gate == "crown_box_adapters"], "source differs")
})

test_that("lineage, boundary and prediction contracts reject resealed substitutions", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  reseal <- function(z, id, value, csv = TRUE) {
    z <- workflow_fixture_update(z, id, value, csv)
    validation <- workflow_read(file.path(root, z$m$artifacts$validation_chm_vwf$path))
    name <- switch(id, lineage_chm_vwf = "lineage", boundaries_chm_vwf = "boundaries", predictions = "prediction")
    validation$sha256[[name]] <- z$m$artifacts[[id]]$sha256
    workflow_fixture_update(z, "validation_chm_vwf", validation)
  }
  line <- workflow_table(file.path(root, f$m$artifacts$lineage_chm_vwf$path))
  bad <- line; bad$source_prediction_id[1] <- "not_a_source"
  z <- reseal(f, "lineage_chm_vwf", bad)
  a <- workflow_admission(workflow_fixture_load(z), z$parents)
  expect_equal(a$status, "blocked")
  expect_match(a$gates$reason[a$gates$gate == "paired_outcomes"], "omitted or invented")
  f <- reseal(f, "lineage_chm_vwf", line)
  vertices <- workflow_table(file.path(root, f$m$artifacts$boundaries_chm_vwf$path))
  bad <- vertices; bad$x[1] <- bad$x[1] - 1
  z <- reseal(f, "boundaries_chm_vwf", bad)
  a <- workflow_admission(workflow_fixture_load(z), z$parents)
  expect_equal(a$status, "blocked")
  expect_match(a$gates$reason[a$gates$gate == "paired_outcomes"], "not derived")
})

test_that("review intervals and predeclared adapter freeze reject retrospective timing", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  r <- workflow_table(file.path(root, f$m$artifacts$reference_review$path))
  old <- r; old$reviewed_utc[1] <- "2026-01-01T23:59:59Z"
  z <- workflow_fixture_update(f, "reference_review", old, TRUE)
  a <- workflow_admission(workflow_fixture_load(z), z$parents)
  expect_equal(a$status, "blocked")
  expect_match(a$gates$reason[a$gates$gate == "reference_revision"], "outside declared review interval")
  f <- workflow_fixture_update(f, "reference_review", r, TRUE)
  tile <- workflow_table(file.path(root, f$m$artifacts$tile_review$path))
  for (when in c("2026-01-01T23:59:59Z", "2026-01-03T00:00:01Z")) {
    bad <- tile; bad$reviewed_utc[1] <- when
    z <- workflow_fixture_update(f, "tile_review", bad, TRUE)
    a <- workflow_admission(workflow_fixture_load(z), z$parents)
    expect_equal(a$status, "blocked")
    expect_match(a$gates$reason[a$gates$gate == "whole_image_coverage"], "outside declared review interval")
  }
  f <- workflow_fixture_update(f, "tile_review", tile, TRUE)
  adapter <- workflow_read(file.path(root, f$m$artifacts$adapter_chm_vwf$path))
  adapter$frozen_utc <- "2026-01-02T12:00:00Z"
  f <- workflow_fixture_update(f, "adapter_chm_vwf", adapter)
  a <- workflow_admission(workflow_fixture_load(f), f$parents)
  expect_equal(a$status, "blocked")
  expect_match(a$gates$reason[a$gates$gate == "crown_box_adapters"], "not frozen before")
})

test_that("explicit additions and removals preserve original history and tile geometry", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  r <- workflow_table(file.path(root, f$m$artifacts$reference_review$path))
  r$action[2] <- "remove"
  added <- r[1, ]; added$key <- "added:canopy3"; added$original_key <- NA_character_; added$action <- "add"
  added[paste0("original_", c("xmin", "ymin", "xmax", "ymax"))] <- NA_real_
  added$xmin <- added$ymin <- 50; added$xmax <- added$ymax <- 60; added$tile_id <- "r1c1"
  f <- workflow_fixture_update(f, "reference_review", rbind(r, added), TRUE)
  tiles <- workflow_table(file.path(root, f$m$artifacts$tile_review$path))
  tiles$linked_keys[tiles$tile_id == "r1c1"] <- "added:canopy3"
  f <- workflow_fixture_update(f, "tile_review", tiles, TRUE)
  a <- workflow_admission(workflow_fixture_load(f), f$parents)
  expect_equal(a$status, "admitted_historical_diagnostic")
  expect_setequal(a$state$review$reference$id, c("invented:1", "added:canopy3"))
  expect_equal(nrow(a$state$review$review), 3L)
  added$tile_id <- "r4c4"
  f <- workflow_fixture_update(f, "reference_review", rbind(r, added), TRUE)
  tiles$linked_keys[tiles$tile_id == "r4c4"] <- "added:canopy3"
  f <- workflow_fixture_update(f, "tile_review", tiles, TRUE)
  a <- workflow_admission(workflow_fixture_load(f), f$parents)
  expect_equal(a$status, "blocked")
  expect_match(a$gates$reason[a$gates$gate == "whole_image_coverage"], "does not intersect")
})

test_that("unchanged neural point extents cannot pass under new crown labels", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE)); f <- workflow_fixture(root)
  p <- file.path(root, "forestformer3d", "diagnostics.json")
  d <- workflow_read(p); d$point_extent_proxies[[1]]$raw_pixel_box <- c(10, 10, 20, 20)
  writeBin(workflow_json(d), p)
  f$parents$receipts$smoke$output_sha256[["forestformer3d/diagnostics.json"]] <- canopy_hash(p)
  a <- workflow_admission(workflow_fixture_load(f), f$parents)
  expect_equal(a$status, "blocked")
  expect_match(a$gates$reason[a$gates$gate == "paired_outcomes"], "Unchanged sparse point extent")
})
