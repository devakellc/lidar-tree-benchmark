# Synthetic detection assembly contracts. Source model_bench_lib.R first.
# This layer performs no inference, fitting, reference scoring or mask fusion.

mp_require <- function(x, fields, label) {
  if (!is.list(x) || !all(fields %in% names(x)))
    stop(label, " lacks required fields: ", paste(fields, collapse = ", "))
}

mp_text <- function(x, label, empty = FALSE) {
  if (!is.character(x) || anyNA(x) || (!empty && any(!nzchar(trimws(x)))))
    stop(label, " must contain non-missing text")
}

mp_scalar <- function(x, label) {
  mp_text(x, label)
  if (length(x) != 1L) stop(label, " must be one value")
}

mp_row <- function(x, i) {
  out <- x[i, , drop = FALSE]
  rownames(out) <- NULL
  out
}

mp_cells <- function(cells) {
  text <- c("cell_id", "dataset", "site", "plot", "rung", "input_id",
    "density_support_id", "height_datum", "support_id", "support_policy",
    "reference_population", "census_event", "support_geometry_id")
  numbers <- c("epsg", "frdens", "pdens", "native_pdens")
  mp_require(cells, c(text, numbers, "support_admitted", "support_blockers"), "Cells")
  if (!is.data.frame(cells) || !nrow(cells)) stop("Cells must be a nonempty table")
  for (nm in text) mp_text(cells[[nm]], nm)
  for (nm in numbers)
    if (!is.numeric(cells[[nm]]) || any(!is.finite(cells[[nm]]) | cells[[nm]] <= 0))
      stop(nm, " must be finite and positive")
  if (anyDuplicated(cells$cell_id) ||
      anyDuplicated(cells[c("dataset", "site", "plot", "rung")]))
    stop("Duplicate cell identity")
  if (any(cells$height_datum != "AGL")) stop("Detection heights must be AGL")
  for (epsg in unique(cells$epsg)) neon_assert_crs(sf::st_crs(epsg))
  if (any(cells$frdens > cells$pdens) || any(cells$pdens > cells$native_pdens))
    stop("Density must satisfy frdens <= pdens <= native_pdens")
  sparse <- cells$rung != "native"
  target <- suppressWarnings(as.numeric(cells$rung[sparse]))
  if (any(!is.finite(target) | target <= 0)) stop("Invalid density rung")
  if (any(target > cells$native_pdens[sparse])) stop("No-upsampling guard: rung exceeds native pdens")
  if (any(cells$pdens[!sparse] != cells$native_pdens[!sparse]))
    stop("Native rung must retain measured native pdens")
  if (!is.logical(cells$support_admitted) || anyNA(cells$support_admitted))
    stop("support_admitted must be explicit logical values")
  mp_text(cells$support_blockers, "support_blockers", empty = TRUE)
  if (any(cells$support_admitted & nzchar(cells$support_blockers)) ||
      any(!cells$support_admitted & !nzchar(cells$support_blockers)))
    stop("Support admission and blockers disagree")
  # Support for the same plot must not change when density changes.
  plots <- unique(cells[c("dataset", "site", "plot")])
  fields <- c("support_id", "support_policy", "reference_population",
              "census_event", "support_geometry_id", "epsg", "support_admitted",
              "support_blockers", "native_pdens")
  for (i in seq_len(nrow(plots))) {
    ix <- cells$dataset == plots$dataset[i] & cells$site == plots$site[i] &
      cells$plot == plots$plot[i]
    for (nm in fields)
      if (length(unique(cells[[nm]][ix])) != 1L) stop("Inconsistent plot support: ", nm)
  }
  invisible(cells)
}

mp_arms <- function(arms) {
  fields <- c("arm", "model_id", "config_id", "runtime_id", "adapter_id", "layout",
              "score_name", "score_target", "score_definition_id", "mask_type")
  mp_require(arms, fields, "Arms")
  if (!is.data.frame(arms) || !nrow(arms)) stop("Arms must be a nonempty table")
  for (nm in fields) mp_text(arms[[nm]], nm)
  if (anyDuplicated(arms$arm) || any(!grepl("^[a-z][a-z0-9_]*$", arms$arm)))
    stop("Arm names must be unique identifiers")
  if ("fusion" %in% arms$arm) stop("fusion is a reserved product name")
  if ("treeisonet" %in% arms$arm) stop("TreeisoNet remains deferred")
  if (any(arms$arm == "forestformer3d" & arms$layout != "indexed_whole_scene"))
    stop("ForestFormer3D requires indexed_whole_scene layout")
  if (any(!arms$score_target %in% c("none", "apex_distance", "instance_iou")))
    stop("Unknown score target")
  if (any((arms$score_name == "none") != (arms$score_target == "none")))
    stop("Score name and target disagree")
  if (any(!arms$mask_type %in% c("none", "predicted_instances", "reference_proxy")))
    stop("Unknown mask type")
  invisible(arms)
}

mp_empty_detections <- function() {
  data.frame(detection_id = character(), x = numeric(), y = numeric(),
             z = numeric(), raw_score = numeric())
}

# An adapter records the declaration at the time it produces a result. Assembly
# compares these snapshots to the requested cells/arms; it never re-stamps caches.
mp_result <- function(cell, arm, status, detections = mp_empty_detections(),
                      reason = "", source_id, calibration_id = "", mask = NULL) {
  if (!is.data.frame(cell) || nrow(cell) != 1L ||
      !is.data.frame(arm) || nrow(arm) != 1L) stop("Result requires one cell and one arm")
  list(cell = mp_row(cell, 1L), arm = mp_row(arm, 1L), status = status,
       reason = reason, source_id = source_id, calibration_id = calibration_id,
       detections = detections, mask = mask)
}

mp_validate_result <- function(result, cell, arm) {
  mp_require(result, c("cell", "arm", "status", "reason", "source_id",
                      "calibration_id", "detections", "mask"), "Result")
  if (!identical(result$cell, cell)) stop("Result cell provenance mismatch")
  if (!identical(result$arm, arm)) stop("Result arm provenance mismatch")
  mp_scalar(result$status, "status")
  if (!result$status %in% c("completed", "completed_empty", "missing", "failed"))
    stop("Unknown result status")
  for (nm in c("reason", "calibration_id")) {
    mp_text(result[[nm]], nm, empty = TRUE)
    if (length(result[[nm]]) != 1L) stop(nm, " must be one value")
  }
  mp_scalar(result$source_id, "source_id")
  complete <- result$status %in% c("completed", "completed_empty")
  if ((!complete && !nzchar(result$reason)) || (complete && nzchar(result$reason)))
    stop("Result status and reason disagree")
  det <- result$detections
  mp_require(det, names(mp_empty_detections()), "Detections")
  if (!is.data.frame(det)) stop("Detections must be a table")
  if (anyDuplicated(names(det)) || !setequal(names(det), names(mp_empty_detections())))
    stop("Unexpected detection columns")
  mp_text(det$detection_id, "detection_id")
  if (anyDuplicated(det$detection_id)) stop("Duplicate detection identity")
  for (nm in c("x", "y", "z"))
    if (!is.numeric(det[[nm]]) || any(!is.finite(det[[nm]])))
      stop("Detection coordinates must be finite numeric values")
  if (!is.numeric(det$raw_score)) stop("raw_score must be numeric")
  if (arm$score_target == "none") {
    if (any(!is.na(det$raw_score))) stop("Unscored arm must use NA raw_score")
  } else if (any(!is.finite(det$raw_score))) stop("Missing or nonfinite raw score")
  if ((result$status == "completed" && !nrow(det)) ||
      (result$status != "completed" && nrow(det))) stop("Result status and detection count disagree")
  if (!complete && (!is.null(result$mask) || nzchar(result$calibration_id)))
    stop("Unavailable result cannot carry masks or calibration")
  if (complete && arm$mask_type != "none") {
    mp_require(result$mask, c("type", "artifact_id", "point_identity_id",
                             "background_label"), "Mask descriptor")
    for (nm in c("type", "artifact_id", "point_identity_id")) mp_scalar(result$mask[[nm]], nm)
    if (!identical(result$mask$type, arm$mask_type)) stop("Mask type mismatch")
    if (!is.numeric(result$mask$background_label) ||
        length(result$mask$background_label) != 1L ||
        !is.finite(result$mask$background_label)) stop("Missing mask background label")
  } else if (!is.null(result$mask)) stop("Unexpected mask descriptor")
  invisible(result)
}

# All scores in this phase are invented fixtures, not fitted probabilities.
# Reuse the existing lookup application only after checking its provenance.
mp_calibration <- function(calibration, cell, arm) {
  mp_require(calibration, c("id", "synthetic", "arm", "training_cells", "lookup"),
             "Calibration")
  mp_scalar(calibration$id, "calibration id")
  if (!isTRUE(calibration$synthetic)) stop("Only synthetic calibration fixtures are supported")
  if (!identical(calibration$arm, arm)) stop("Calibration arm provenance mismatch")
  if (arm$score_target != "apex_distance") stop("Calibration target must be apex_distance")
  train <- calibration$training_cells
  mp_cells(train)
  if (!cell$support_admitted || any(!train$support_admitted))
    stop("Calibration requires admitted reference support")
  for (nm in c("dataset", "support_policy", "reference_population", "height_datum"))
    if (any(train[[nm]] != cell[[nm]])) stop("Calibration support mismatch: ", nm)
  if (any(train$dataset == cell$dataset & train$site == cell$site & train$plot == cell$plot))
    stop("Calibration leakage: hold out the whole plot across all rungs")
  density <- train[train$rung == cell$rung & train$site == cell$site, , drop = FALSE]
  if (!nrow(density)) stop("Calibration does not support this site and density rung")
  for (nm in c("frdens", "pdens"))
    if (cell[[nm]] < min(density[[nm]]) || cell[[nm]] > max(density[[nm]]))
      stop("Calibration density outside training support: ", nm)
  lookup <- calibration$lookup
  fields <- c("raw_min", "raw_max", "raw_prob", "calibrated")
  mp_require(lookup, fields, "Calibration lookup")
  if (!is.data.frame(lookup) || !nrow(lookup)) stop("Empty calibration lookup")
  if (anyDuplicated(names(lookup)) || !setequal(names(lookup), fields))
    stop("Lookup metadata belongs in the calibration declaration")
  for (nm in fields)
    if (!is.numeric(lookup[[nm]]) || any(!is.finite(lookup[[nm]])))
      stop("Invalid calibration lookup values")
  if (length(unique(lookup$raw_min)) != 1L || length(unique(lookup$raw_max)) != 1L ||
      lookup$raw_min[1] > lookup$raw_max[1] ||
      any(lookup$raw_prob < 0 | lookup$raw_prob > 1) ||
      any(lookup$calibrated < 0 | lookup$calibrated > 1) ||
      any(diff(lookup$raw_prob) <= 0) || any(diff(lookup$calibrated) < 0))
    stop("Invalid monotone probability lookup")
  invisible(calibration)
}

mp_ensemble <- function(ensemble, arms) {
  mp_require(ensemble, c("members", "controls", "method", "merge_tol", "z_tol"), "Ensemble")
  for (nm in c("members", "controls")) {
    x <- ensemble[[nm]]
    mp_text(x, nm)
    if (!length(x) || anyDuplicated(x) || any(!x %in% arms$arm))
      stop(nm, " must explicitly name declared arms without duplicates")
  }
  if (!setequal(union(ensemble$members, ensemble$controls), arms$arm))
    stop("Every declared arm must be an ensemble member or a control")
  mp_scalar(ensemble$method, "method")
  if (!ensemble$method %in% c("union", "consensus", "weighted")) stop("Unknown fusion method")
  positive <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x > 0
  for (nm in c("merge_tol", "z_tol"))
    if (!positive(ensemble[[nm]])) stop(nm, " must be positive")
  if (ensemble$method == "consensus" &&
      (!positive(ensemble$k) || ensemble$k != floor(ensemble$k) ||
       ensemble$k > length(ensemble$members))) stop("Invalid fixed consensus k")
  if (ensemble$method == "weighted" &&
      (!positive(ensemble$weight_min) || ensemble$weight_min > length(ensemble$members)))
    stop("Invalid weighted threshold")
  invisible(ensemble)
}

assemble_metapipeline <- function(bundle) {
  mp_require(bundle, c("schema_version", "mode", "cells", "arms", "results",
                       "ensemble", "calibrations"), "Bundle")
  if (!identical(bundle$schema_version, 1L) || !identical(bundle$mode, "synthetic"))
    stop("Only schema 1 synthetic bundles are supported; real-data admission is separate")
  cells <- bundle$cells; arms <- bundle$arms; ensemble <- bundle$ensemble
  mp_cells(cells); mp_arms(arms); mp_ensemble(ensemble, arms)
  if (!is.list(bundle$results) || !is.list(bundle$calibrations)) stop("Results and calibrations must be lists")
  # Match on two columns, not a delimiter-dependent composite key.
  used <- matrix(FALSE, nrow(cells), nrow(arms))
  indexed <- vector("list", nrow(cells) * nrow(arms))
  slot <- function(i, j) (i - 1L) * nrow(arms) + j
  for (result in bundle$results) {
    mp_require(result, c("cell", "arm"), "Result")
    mp_scalar(result$cell$cell_id, "result cell_id")
    mp_scalar(result$arm$arm, "result arm")
    i <- match(result$cell$cell_id, cells$cell_id); j <- match(result$arm$arm, arms$arm)
    if (is.na(i) || is.na(j)) stop("Result is outside the declared cell/arm matrix")
    if (used[i, j]) stop("Duplicate cell/arm result")
    used[i, j] <- TRUE
    mp_validate_result(result, mp_row(cells, i), mp_row(arms, j))
    indexed[[slot(i, j)]] <- result
  }
  calibration_ids <- vapply(bundle$calibrations, function(x) {
    mp_scalar(x$id, "calibration id"); x$id
  }, character(1))
  if (anyDuplicated(calibration_ids)) stop("Duplicate calibration id")
  statuses <- products <- apexes <- fused <- list()
  empty_fused <- data.frame(cell_id = character(), cluster = integer(), x = numeric(),
    y = numeric(), z = numeric(), votes = integer(), arms = character(), weight = numeric())
  empty_apexes <- data.frame(cell_id = character(), arm = character(),
    mp_empty_detections(), probability = numeric())
  for (i in seq_len(nrow(cells))) {
    cell <- mp_row(cells, i)
    runs <- setNames(vector("list", nrow(arms)), arms$arm)
    for (j in seq_len(nrow(arms))) {
      arm <- mp_row(arms, j)
      result <- indexed[[slot(i, j)]]
      if (is.null(result)) result <- mp_result(cell, arm, "missing",
        reason = "No result supplied", source_id = "not_supplied")
      probability <- rep(NA_real_, nrow(result$detections))
      complete <- result$status %in% c("completed", "completed_empty")
      if (complete && (nzchar(result$calibration_id) ||
          (ensemble$method == "weighted" && arm$arm %in% ensemble$members))) {
        cal_ix <- match(result$calibration_id, calibration_ids)
        if (is.na(cal_ix)) stop("Missing compatible calibration for ", arm$arm, "/", cell$cell_id)
        cal <- bundle$calibrations[[cal_ix]]
        mp_calibration(cal, cell, arm)
        probability <- apply_confidence_lookup(result$detections$raw_score, cal$lookup)
      }
      result$probability <- probability
      runs[[arm$arm]] <- result
      statuses[[length(statuses) + 1L]] <- data.frame(cell_id = cell$cell_id,
        arm = arm$arm, status = result$status, reason = result$reason,
        n_detections = if (complete) nrow(result$detections) else NA_integer_,
        source_id = result$source_id, calibration_id = result$calibration_id,
        cell_provenance_id = digest::digest(cell, algo = "sha256"),
        arm_provenance_id = digest::digest(arm, algo = "sha256"))
      if (nrow(result$detections)) apexes[[length(apexes) + 1L]] <- data.frame(
        cell_id = cell$cell_id, arm = arm$arm, result$detections, probability = probability)
    }
    product <- function(name, status, reason, count, members) {
      data.frame(cell_id = cell$cell_id, product = name, status = status,
                 reason = reason, n_detections = count, members = paste(members, collapse = ","),
                 n_members = length(members), support_id = cell$support_id)
    }
    for (name in ensemble$controls) {
      r <- runs[[name]]
      complete <- r$status %in% c("completed", "completed_empty")
      products[[length(products) + 1L]] <- product(name,
        if (!cell$support_admitted) "blocked" else r$status,
        if (!cell$support_admitted) cell$support_blockers else r$reason,
        if (cell$support_admitted && complete) nrow(r$detections) else NA_integer_, name)
    }
    unavailable <- ensemble$members[!vapply(runs[ensemble$members], function(r)
      r$status %in% c("completed", "completed_empty"), logical(1))]
    if (!cell$support_admitted || length(unavailable)) {
      reason <- if (!cell$support_admitted) cell$support_blockers else
        paste("Unavailable ensemble members:", paste(unavailable, collapse = ","))
      products[[length(products) + 1L]] <- product("fusion", "blocked", reason,
                                                  NA_integer_, ensemble$members)
      next
    }
    # Stable declaration order makes tie handling independent of input list order.
    stack <- do.call(rbind, lapply(ensemble$members, function(name) {
      r <- runs[[name]]
      data.frame(arm = rep(name, nrow(r$detections)), r$detections,
                 probability = r$probability)
    }))
    weights <- if (ensemble$method == "weighted") stack$probability else NULL
    f <- fuse_apexes(stack$arm, stack$x, stack$y, stack$z,
                     ensemble$merge_tol, ensemble$z_tol, weights = weights)
    if (ensemble$method == "consensus") f <- f[f$votes >= ensemble$k, , drop = FALSE]
    if (ensemble$method == "weighted") f <- f[f$weight >= ensemble$weight_min, , drop = FALSE]
    if (!"weight" %in% names(f)) f$weight <- rep(NA_real_, nrow(f))
    if (nrow(f)) fused[[length(fused) + 1L]] <- data.frame(cell_id = cell$cell_id, f)
    products[[length(products) + 1L]] <- product("fusion",
      if (nrow(f)) "completed" else "completed_empty", "", nrow(f), ensemble$members)
  }
  list(schema_version = 1L, mode = "synthetic", declaration = bundle,
       status = do.call(rbind, statuses), products = do.call(rbind, products),
       apexes = if (length(apexes)) do.call(rbind, apexes) else empty_apexes,
       fused = if (length(fused)) do.call(rbind, fused) else empty_fused)
}
