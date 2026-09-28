#!/usr/bin/env Rscript
# Recover target-specific TP/FP labels from sealed cells, then calibrate by plot.
args <- commandArgs(TRUE)
if (length(args) != 1L) stop("Usage: calibrate_fgiemit_development.R outdir")
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
source(file.path(dirname(script), "repo_paths.R"))
source(.find("model_bench_lib.R"))
source(.find("transfer_audit_lib.R"))
source(.find("fgiemit_development_summary_lib.R"))
source(.find("fgiemit_calibration_lib.R"))
out <- args[1]
cells <- read.csv(file.path(out, "cells.csv"), colClasses = c(plot = "character"))
folds <- read.csv(file.path(out, "folds.csv"), colClasses = c(plot = "character"))
labels <- list()
for (plot in FGI_DEVELOPMENT_PLOTS) {
  reference_labels <- NULL
  for (arm in c("chm_vwf", "segmentanytree", "forestformer3d")) {
    cell <- cells[cells$plot == plot & cells$arm == arm & cells$target == "apex_max_agl", ]
    if (nrow(cell) != 1L) stop("Missing or duplicated source cell")
    pred <- read.csv(file.path(cell$source_directory, "prediction_apexes.csv"))
    ref <- read.csv(file.path(cell$source_directory, "reference_apexes.csv"))
    pred <- pred[pred$policy == "max_agl", , drop = FALSE]
    ref <- ref[ref$policy == "max_agl", , drop = FALSE]
    pred <- pred[order(pred$instance), , drop = FALSE]
    ref <- ref[order(ref$instance), , drop = FALSE]
    if (nrow(pred) != cell$n_pred || nrow(ref) != cell$n_ref ||
        anyDuplicated(pred$instance) || anyDuplicated(ref$instance) ||
        any(!is.finite(as.matrix(pred[, c("x", "y", "z", "confidence")]))) ||
        any(!is.finite(as.matrix(ref[, c("x", "y", "z")]))) ||
        any(pred$confidence < 0)) stop("Invalid sealed apex/feature population")
    if (arm == "chm_vwf" && !isTRUE(all.equal(pred$confidence, pred$z)))
      stop("CHM feature differs from its AGL height")
    apex <- fgi_apex_labels(pred, ref)
    baseline <- audit_apex_match(pred, ref)
    if (sum(apex$label) != baseline$apex_TP || baseline$apex_TP != cell$TP)
      stop("Apex labels differ from the unchanged default matcher")
    attach_cell <- function(rows, target) cbind(
      data.frame(plot = rep(plot, nrow(rows)), arm = rep(arm, nrow(rows)),
                 target = rep(target, nrow(rows))), rows)
    labels[[paste(plot, arm, "apex")]] <- attach_cell(apex, "apex_max_agl")
    if (arm != "chm_vwf") {
      if (is.null(reference_labels)) {
        cloud <- lidR::readLAS(cell$reference_path)
        if (is.null(cloud)) stop("Missing full reference substrate")
        reference_labels <- cloud$tree_index
        rm(cloud)
      }
      predicted_labels <- data.table::fread(
        file.path(cell$source_directory, "prediction_labels.csv"))$pred_instance
      if (arm == "segmentanytree") {
        sizes <- table(predicted_labels[predicted_labels > 0])
        if (!isTRUE(all.equal(pred$confidence,
            as.numeric(sizes[as.character(pred$instance)]))))
          stop("SAT feature differs from retained instance point count")
      }
      mask <- fgi_mask_labels(predicted_labels, reference_labels, pred, ref$instance)
      labels[[paste(plot, arm, "mask")]] <- attach_cell(mask, "mask_iou_0.5")
    }
    cat("Recovered labels:", plot, arm, nrow(pred), "predictions\n")
  }
}
labels <- do.call(rbind, labels)
result <- fgi_calibrate_complete(labels, cells, folds)
for (name in names(result))
  write.csv(result[[name]], file.path(out, paste0(name, ".csv")), row.names = FALSE, na = "NA")
jsonlite::write_json(list(cells = nrow(result$status),
  fitted_cells = sum(result$status$fit_state == "fitted"),
  unavailable_fit_cells = sum(result$status$fit_state == "unavailable"),
  validation_predictions = nrow(result$predictions),
  calibrated_predictions = sum(!is.na(result$predictions$probability)),
  R = as.character(getRversion()), resamples = 1000L, seed = 20260923L,
  unit = "paired_whole_plot_fixed_out_of_fold_predictions", refit_in_bootstrap = FALSE,
  interval = "95_percentile_type7", bins = seq(0, 1, .1),
  bins_closed = "left_except_final_includes_one", plot_order = FGI_DEVELOPMENT_PLOTS,
  fitting = "raw_score_tie_aggregated_count_weighted_PAVA",
  interpolation = "linear_with_no_extrapolation", reserve_evaluation_enabled = FALSE),
  file.path(out, "analysis.json"), pretty = TRUE, auto_unbox = TRUE, digits = 16)
