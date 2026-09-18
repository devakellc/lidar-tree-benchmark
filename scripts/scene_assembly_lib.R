# Compare archived outer assembly and new indexed native scenes, training only.
scene_confidence <- function(src, points, retained) {
  fgi_indexed_labels(src, points)
  src <- src[order(src$ff3d_row), , drop = FALSE]
  d <- data.table::as.data.table(src)
  if (!"ff3d_score" %in% names(d) || any(!is.finite(d$ff3d_score)) ||
      any(d$ff3d_score < 0) || any(d$crown_id == 0 & d$ff3d_score != 0))
    stop("Invalid native confidence features")
  if (!any(d$crown_id > 0)) return(data.frame(crown_id = numeric(), points = integer(),
    score_mean = numeric(), score_min = numeric(), score_max = numeric(),
    apex_x = numeric(), apex_y = numeric(), apex_z = numeric(), retained = logical()))
  out <- d[crown_id > 0, .(points = .N, score_mean = mean(ff3d_score),
    score_min = min(ff3d_score), score_max = max(ff3d_score),
    apex_x = X[which.max(Z)], apex_y = Y[which.max(Z)], apex_z = max(Z)), by = crown_id]
  out$retained <- out$crown_id %in% retained[!is.na(retained)]
  as.data.frame(out)
}

scene_check_reproduction <- function(current, archived, keys) {
  if (nrow(current) != 1L || nrow(archived) != 1L ||
      !isTRUE(all.equal(unname(unlist(current[, keys, drop = FALSE])),
                        unname(unlist(archived[, keys, drop = FALSE])), tolerance = 1e-8)))
    stop("Archived comparison changed")
}

scene_official_keys <- function(row) {
  present <- vapply(FGI_CLASSES, function(cl) row[[paste0("n_", cl)]] > 0, logical(1))
  for (cl in FGI_CLASSES[!present])
    if (!is.na(row[[paste0("rec_", cl)]])) stop("Absent category recall must be undefined")
  c("precision", "recall", "f1", "cov", paste0("recall_", tolower(FGI_CLASSES[present])))
}

scene_official <- function(summary, opt, resources, suffix = "") {
  fgi_official_check(summary, opt, resources)
  checks <- 0L
  for (i in seq_len(nrow(summary))) {
    arm <- summary$arm[i]
    keys <- scene_official_keys(summary[i, ])
    path <- file.path(opt$out, paste0("official_", arm, ".json"))
    official <- jsonlite::read_json(path)
    if (!all(keys %in% names(official))) stop("Incomplete official metric verification")
    checks <- checks + length(keys)
    if (nzchar(suffix)) for (ext in c("json", "log")) {
      from <- file.path(opt$out, paste0("official_", arm, ".", ext))
      to <- file.path(opt$out, paste0("official_", arm, "_", suffix, ".", ext))
      if (!file.rename(from, to)) stop("Cannot preserve per-plot official verification")
    }
  }
  checks
}

scene_analyze <- function(root, plots, python) {
  directory <- file.path(root, "scene_assembly")
  outdir <- file.path(directory, "analysis")
  dir.create(outdir, showWarnings = FALSE)
  manifest <- readRDS(file.path(directory, "run_manifest.rds"))
  for (field in c("file_md5", "scene_files", "prepared_md5"))
    audit_verify_hashes(manifest[[field]])
  metadata <- yaml::read_yaml(file.path(root, "source/plot_data.yaml"))
  fgi_plots(metadata, "training", plots)
  old_scores <- read.csv(file.path(root, "audit/analysis/scores.csv"))
  old_cylinders <- read.csv(file.path(root, "audit/analysis/cylinders.csv"))
  keys <- c("n_ref", "n_pred", "TP", "FP", "FN", "F1", "coverage")
  scores <- cylinders <- duplicates <- contracts <- confidence <- list()
  checks <- 0L
  opt <- fgi_options(c("SPLIT=training", paste0("OUT_DIR=", outdir),
    paste0("DATA_DIR=", root, "/source"), paste0("EVAL_PYTHON=", python)))
  resources <- fgi_resources(opt)
  for (pid in plots) {
    run <- file.path(directory, "runs", pid, "forestformer3d")
    receipt <- readRDS(file.path(run, "receipt.rds"))
    audit_verify_hashes(receipt$output_md5)
    ref <- lidR::readLAS(file.path(scene_baseline(root, pid), "references", paste0("plot_", pid, ".laz")))
    classes <- fgi_reference_classes(as.data.frame(ref@data), metadata[[pid]])
    ref <- ref[ref$Classification != 5L]
    points <- as.data.frame(ref@data[, .(X, Y, Z, Classification, tree_index)])
    native <- fgi_ff_points(file.path(run, "predictions.laz"))
    aligned <- fgi_indexed_labels(native, points)
    outer_path <- file.path(root, "audit/corrected/runs", pid, "forestformer3d/predictions.laz")
    outer <- fgi_ff_points(outer_path)
    mapped <- fgi_transfer_labels(outer, points)
    labels <- list(outer_cylinders = mapped$labels, whole_scene = aligned$labels)
    for (arm in names(labels)) {
      raw <- labels[[arm]]
      s <- cbind(data.frame(plot = pid, split = "training", arm = arm),
                   audit_label_stats(raw, points, classes))
      if (arm == "outer_cylinders") scene_check_reproduction(s,
        old_scores[old_scores$plot == pid & old_scores$arm == "forestformer3d_native", ], keys)
      scores[[length(scores) + 1L]] <- s
      p <- fgi_filter_predictions(raw, points$Z)
      las <- lidR::add_lasattribute(ref, ifelse(is.na(p), 0L, p), "tree_pred", "Instance; zero background")
      output <- file.path(outdir, "instances", arm, "training", paste0("plot_", pid, ".laz"))
      dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
      lidR::writeLAS(las, output)
      if (arm == "whole_scene") {
        features <- scene_confidence(native, points, p)
        confidence[[length(confidence) + 1L]] <- cbind(data.frame(plot = rep(pid, nrow(features))), features)
      }
      src <- if (arm == "whole_scene") native else outer
      duplicates[[length(duplicates) + 1L]] <- cbind(data.frame(plot = pid, arm = arm),
        audit_duplicate_stats(src))
      cat(pid, arm, sprintf("TP=%d/%d F1=%.4f Cov=%.4f\n", s$TP, s$n_ref, s$F1, s$coverage))
    }
    per_plot <- as.data.frame(data.table::rbindlist(scores))
    per_plot <- fgi_summary(per_plot[per_plot$plot == pid, ], names(labels))
    checks <- checks + scene_official(per_plot, opt, resources, pid)
    export <- jsonlite::read_json(file.path(run, "predictions.laz.json"), simplifyVector = TRUE)
    if (nrow(export) != 1L || export$source_rows != nrow(points) || export$layout != "whole_scene")
      stop("Invalid whole-scene receipt")
    contracts[[length(contracts) + 1L]] <- data.frame(plot = pid,
      reference_rows = nrow(points), output_rows = nrow(native),
      unique_source_rows = length(unique(native$ff3d_row)), max_coordinate_delta_m = max(aligned$distance),
      outer_rows = nrow(outer), outer_exact_fraction = mean(mapped$distance <= .002),
      seconds = receipt$seconds, peak_cuda_allocated_bytes = export$peak_cuda_allocated_bytes,
      peak_cuda_reserved_bytes = export$peak_cuda_reserved_bytes, peak_host_rss_kib = export$peak_host_rss_kib)
    old <- lidR::readLAS(outer_path)
    blocks <- as.data.frame(old@data[, .(X, Y, Z, block = UserData, crown_id = PointSourceID)])
    for (block in sort(unique(blocks$block))) {
      local <- fgi_transfer_labels(blocks[blocks$block == block, ], points)
      keep <- local$distance <= .002
      region <- points[keep, , drop = FALSE]
      full <- table(points$tree_index[points$tree_index > 0])
      part <- table(region$tree_index[region$tree_index > 0])
      for (mode in c("cylinder", "stitched", "whole_scene")) {
        raw <- switch(mode, cylinder = local$labels[keep], stitched = mapped$labels[keep],
                       whole_scene = aligned$labels[keep])
        s <- cbind(data.frame(plot = pid, block = block, mode = mode,
          support_points = sum(keep), truncated_references = sum(part < full[names(part)])),
          audit_label_stats(raw, region, classes))
        if (mode != "whole_scene") scene_check_reproduction(s,
          old_cylinders[old_cylinders$plot == pid & old_cylinders$route == "native" &
            old_cylinders$block == block & old_cylinders$mode == mode, ],
          c(keys, "support_points", "truncated_references"))
        cylinders[[length(cylinders) + 1L]] <- s
      }
    }
    rm(ref, points, native, outer, aligned, mapped, old, blocks, las); gc()
  }
  tables <- list(scores = scores, cylinders = cylinders, duplicates = duplicates,
                  contracts = contracts, confidence_features = confidence)
  for (name in names(tables)) write.csv(data.table::rbindlist(tables[[name]]),
    file.path(outdir, paste0(name, ".csv")), row.names = FALSE)
  scores <- as.data.frame(data.table::rbindlist(scores))
  summary <- fgi_summary(scores, c("outer_cylinders", "whole_scene"))
  write.csv(summary, file.path(outdir, "summary.csv"), row.names = FALSE)
  checks <- checks + scene_official(summary, opt, resources)
  inputs <- c(.find("scene_assembly_lib.R"), .find("audit_scene_assembly.R"),
    file.path(directory, c("run_manifest.json", "declaration.json")),
    file.path(directory, "runs", plots, "forestformer3d/receipt.rds"))
  outputs <- list.files(outdir, "[.](csv|json|laz)$", recursive = TRUE, full.names = TRUE)
  outputs <- outputs[basename(outputs) != "analysis_manifest.json"]
  jsonlite::write_json(list(protocol = manifest$protocol, plots = plots, split = "training",
    official_metric_checks = checks, input_md5 = as.list(tools::md5sum(inputs)),
    output_md5 = as.list(tools::md5sum(outputs)), calibration_fitted = FALSE),
    file.path(outdir, "analysis_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
  print(summary)
}
