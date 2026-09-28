#!/usr/bin/env Rscript
args <- commandArgs(TRUE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value=TRUE)[1])
source(file.path(dirname(script), "repo_paths.R"))
source(.find("sweep_lib.R")); source(.find("model_bench_lib.R"))
source(.find("transfer_audit_lib.R")); source(.find("fgiemit_development_summary_lib.R"))
source(.find("fgiemit_pipeline_lib.R"))
if (length(args) != 2L) stop("Usage: OUT STAGE")
out <- args[1]; stage <- args[2]
read <- function(name) read.csv(file.path(out, name), stringsAsFactors=FALSE)
cal <- if (stage == "development") read("input_calibration.csv") else NULL
fit_status <- if (stage == "development") read("input_calibration_status.csv") else NULL
result <- fgi_pipeline_analyze(read("input_cells.csv"), read("input_predictions.csv"),
                               read("input_references.csv"), stage, cal, fit_status)
for (name in c("status", "products", "pooled", "detections", "calibration"))
  write.csv(result[[name]], file.path(out, paste0(name, ".csv")), row.names=FALSE, na="")
jsonlite::write_json(list(complete=result$complete, stage=stage, selection_changed=FALSE,
  selected_arm="forestformer3d", merge_tol_m=2, z_tol_m=5, weighted_threshold=1,
  weighted_score_extrapolation=FALSE, reserve_fusion_enabled=FALSE,
  deployment_calibration_fitted=FALSE), file.path(out, "analysis.json"), auto_unbox=TRUE, pretty=TRUE)
