#!/usr/bin/env Rscript
# Historical TEAK_043 packet, fail-closed preflight, and dormant box comparison.
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
source(file.path(dirname(.self), "repo_paths.R"))
source(.find("teak_canopy_lib.R"))
source(.find("teak_canopy_policy_lib.R"))
source(.find("teak_comparison_workflow_lib.R"))
a <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(a, function(z) paste(z[-1], collapse = "=")), vapply(a, `[`, "", 1))
workflow_require(all(c("MODE", "OUT") %in% names(A)) && !anyDuplicated(names(A)) &&
  all(names(A) %in% c("MODE", "BASE", "OUT", "BUNDLE", "ADMISSION_SHA256", "VERIFY")) &&
  all(nzchar(unlist(A))) && A$MODE %in% c("packet", "preflight", "compare"),
  "Usage: MODE=packet|preflight|compare BASE=work OUT=fresh [BUNDLE=directory ADMISSION_SHA256=hash] [VERIFY=1]")
verify <- !is.null(A$VERIFY)
workflow_require(!verify || identical(A$VERIFY, "1"), "VERIFY must equal 1")
workflow_require(is.null(A$BUNDLE) == is.null(A$ADMISSION_SHA256) &&
  (A$MODE != "packet" || is.null(A$BUNDLE)), "BUNDLE and ADMISSION_SHA256 must be paired outside packet mode")
base <- workflow_safe(if (is.null(A$BASE)) .job_dir(FALSE) else A$BASE)
out <- workflow_safe(A$OUT, exists = verify)
code_paths <- file.path(.ROOT, "scripts", c("run_teak_comparison_workflow.R", "repo_paths.R",
  "teak_canopy_lib.R", "teak_canopy_policy_lib.R", "teak_comparison_workflow_lib.R"))
code <- do.call(rbind, lapply(code_paths, workflow_record))
workflow_require(as.character(packageVersion("clue")) == "0.3.68", "Pinned clue solver differs")
parents <- workflow_parents(base, .ROOT); parents$repo <- .ROOT
out <- workflow_output_path(out, base, .ROOT,
  c(unlist(parents$roots), file.path(base, "teak-native-pilot"),
    if (!is.null(A$BUNDLE)) workflow_safe(A$BUNDLE)), verify)
inputs <- parents$inputs
if (A$MODE == "packet") {
  products <- workflow_packet(parents); status <- "blocked"
} else {
  bundle <- NULL
  if (is.null(A$BUNDLE)) admission <- list(status = "blocked", gates = workflow_current_gates(parents)) else {
    bundle <- workflow_bundle(A$BUNDLE, A$ADMISSION_SHA256)
    inputs <- rbind(inputs, bundle$inputs)
    admission <- workflow_admission(bundle, parents)
  }
  status <- admission$status
  summary <- list(schema_version = 1L, plot = "TEAK_043", status = status,
    claim = "historical_development_diagnostic_only", gates = admission$gates,
    evidence_authenticity = "software checks structure/bytes, not human identity or actual inspection",
    exact_rgb_pixel_provenance = "unknown", exact_lidar_rgb_lag = "unknown",
    independent_holdout_claim = "unavailable_for_historical_model_observed_plot",
    reserved_plots_processed = list())
  products <- list("preflight.json" = workflow_json(summary), "preflight.csv" = workflow_csv(admission$gates))
  if (A$MODE == "compare" && status == "admitted_historical_diagnostic") {
    products <- c(products, workflow_compare(admission, bundle))
  }
  if (!is.null(bundle)) workflow_require(identical(bundle$inputs,
    workflow_bundle(A$BUNDLE, A$ADMISSION_SHA256)$inputs), "Evidence changed during run")
}
workflow_require(identical(parents$inputs, workflow_parents(base, .ROOT)$inputs) &&
  identical(code, do.call(rbind, lapply(code_paths, workflow_record))), "Inputs/code changed during run")
workflow_emit(out, products, inputs, code, A$MODE, verify)
cat("TEAK_043", A$MODE, status, if (verify) "verified without writes" else "written", "\n")
quit(status = workflow_exit_status(A$MODE, status), save = "no")
