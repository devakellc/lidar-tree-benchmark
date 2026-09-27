# Small invented example, shared by the CLI smoke run and regression fixtures.
# Numeric scores and lookup values are arbitrary; no calibrator is fitted.
metapipeline_synthetic <- function() {
  cells <- data.frame(cell_id = paste0("synthetic_", 1:4), dataset = "synthetic",
    site = "example", plot = paste0("plot_", 1:4), rung = "native",
    input_id = paste0("invented_cloud_", 1:4), density_support_id = "invented_area",
    epsg = 32611, height_datum = "AGL", frdens = 6, pdens = 10, native_pdens = 10,
    support_id = paste0("invented_support_", 1:4), support_policy = "synthetic_census_v1",
    reference_population = "invented_trees", census_event = "synthetic_event",
    support_geometry_id = paste0("invented_geometry_", 1:4), support_admitted = TRUE,
    support_blockers = "")
  arms <- data.frame(arm = c("multichm", "segmentanytree", "deepforest"),
    model_id = "synthetic_model", config_id = "synthetic_config", runtime_id = "fixture_runtime",
    adapter_id = "fixture_v1", score_definition_id = "invented_apex_xy4_z5",
    layout = "apex_table", score_name = "invented_score", score_target = "apex_distance",
    mask_type = "none")
  ensemble <- list(members = arms$arm, controls = arms$arm, method = "consensus",
                   k = 2L, merge_tol = 2, z_tol = 5)
  results <- list()
  for (i in seq_len(nrow(cells))) for (j in seq_len(nrow(arms))) {
    # Plot 1: two-arm overlap + a height-separated singleton. Plot 2: empty.
    # Plot 3: a failed member. Plot 4: a missing member (omitted receipt).
    if (i == 4L && j == 3L) next
    det <- if (i == 2L || (i == 3L && j == 3L)) mp_empty_detections() else
      data.frame(detection_id = "tree_1", x = 500000 + c(0, 0.1, 0)[j],
                 y = 4100000, z = c(20, 20, 5)[j], raw_score = 0.8)
    status <- if (i == 3L && j == 3L) "failed" else
      if (nrow(det)) "completed" else "completed_empty"
    results[[length(results) + 1L]] <- mp_result(mp_row(cells, i), mp_row(arms, j),
      status, det, reason = if (status == "failed") "Synthetic driver failure" else "",
      source_id = paste0("invented_predictions_", i, "_", j))
  }
  list(schema_version = 1L, mode = "synthetic", cells = cells, arms = arms,
       results = results, ensemble = ensemble, calibrations = list())
}
