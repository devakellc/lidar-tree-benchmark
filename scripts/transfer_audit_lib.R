# Training-only diagnostics on an explicit common point substrate.
audit_apex_match <- function(pred, ref, xy = 4, z = 5) {
  candidates <- lapply(seq_len(nrow(ref)), function(i) {
    distance <- sqrt((pred$x - ref$x[i])^2 + (pred$y - ref$y[i])^2)
    j <- which(distance <= xy & abs(pred$z - ref$z[i]) <= z)
    data.frame(ref = rep(i, length(j)), pred = j, distance = distance[j])
  })
  edges <- data.table::rbindlist(candidates)
  used_ref <- logical(nrow(ref)); used_pred <- logical(nrow(pred))
  if (nrow(edges)) {
    data.table::setorder(edges, distance, ref, pred)
    for (k in seq_len(nrow(edges))) {
      i <- edges$ref[k]; j <- edges$pred[k]
      if (!used_ref[i] && !used_pred[j]) { used_ref[i] <- TRUE; used_pred[j] <- TRUE }
    }
  }
  tp <- sum(used_ref)
  data.frame(apex_TP = tp, apex_FP = nrow(pred) - tp, apex_FN = nrow(ref) - tp,
             apex_F1 = if (nrow(pred) + nrow(ref)) 2 * tp / (nrow(pred) + nrow(ref)) else 0)
}

audit_errors <- function(pred, points) {
  p <- pred; p[is.na(p)] <- 0L
  r <- points$tree_index
  dt <- data.table::data.table(pred = p, ref = r)
  overlap <- dt[, .N, by = .(pred, ref)]
  ps <- dt[pred > 0, .(pred_points = .N), by = pred]
  rs <- dt[ref > 0, .(ref_points = .N), by = ref]
  edges <- merge(merge(overlap[pred > 0 & ref > 0], ps, by = "pred"), rs, by = "ref")
  # An edge needs >=10% of both instances, to avoid counting single-point noise.
  meaningful <- edges[N >= 0.1 * pred_points & N >= 0.1 * ref_points]
  splits <- meaningful[, .N, by = ref][N > 1, .N]
  merges <- meaningful[, .N, by = pred][N > 1, .N]
  bg <- merge(overlap[pred > 0 & ref == 0], ps, by = "pred")
  locp <- instance_apex(transform(points, crown_id = pred))
  locr <- instance_apex(transform(points, crown_id = ifelse(r > 0, r, NA_integer_)))
  cbind(data.frame(assigned_points = sum(p > 0), assigned_fraction = mean(p > 0),
    tree_point_recall = if (sum(r > 0)) sum(p > 0 & r > 0) / sum(r > 0) else NA_real_,
    assigned_background_fraction = if (sum(p > 0)) sum(p > 0 & r == 0) / sum(p > 0) else 0,
    background_majority_predictions = sum(bg$N > 0.5 * bg$pred_points),
    split_references = splits, merged_predictions = merges), audit_apex_match(locp, locr))
}

audit_label_stats <- function(raw, points, classes) {
  out <- fgi_score(raw, points, classes)
  p <- out$pred
  pre <- unique(raw[!is.na(raw) & raw > 0])
  cbind(out$score, data.frame(predictions_before_filter = length(pre),
    predictions_removed_by_filter = length(pre) - out$score$n_pred),
    audit_errors(p, points[out$keep, , drop = FALSE]))
}

audit_duplicate_stats <- function(src) {
  d <- data.table::as.data.table(src[, c("X", "Y", "Z", "crown_id")])
  d[is.na(crown_id), crown_id := 0L]
  groups <- d[, .(points = .N, labels = data.table::uniqueN(crown_id)), by = .(X, Y, Z)]
  data.frame(duplicate_coordinate_groups = sum(groups$points > 1),
             conflicting_duplicate_groups = sum(groups$labels > 1),
             points_in_conflicting_groups = sum(groups$points[groups$labels > 1]))
}

audit_verify_hashes <- function(expected) {
  expected <- unlist(expected, use.names = TRUE)
  actual <- tools::md5sum(names(expected))
  if (anyNA(actual) || !identical(unname(as.character(actual)), unname(expected)))
    stop("Audit input/output checksum changed")
  invisible(TRUE)
}

audit_analyze <- function(root, plots, python) {
  audit <- file.path(root, "audit"); outdir <- file.path(audit, "analysis")
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  metadata <- yaml::read_yaml(file.path(root, "source/plot_data.yaml"))
  manifest <- readRDS(file.path(audit, "corrected/run_manifest.rds"))
  audit_verify_hashes(manifest$file_md5)
  audit_verify_hashes(manifest$audit_files)
  audit_verify_hashes(manifest$prepared_md5)
  scores <- list(); cylinders <- list(); projections <- list(); seams <- list(); duplicates <- list()
  for (pid in plots) {
    for (arm in c("forestformer3d", "treeisonet"))
      audit_verify_hashes(readRDS(file.path(audit, "corrected/runs", pid, arm, "receipt.rds")))
    baseline <- if (pid == "1001") file.path(root, "training") else file.path(audit, "baseline_1019")
    ref <- lidR::readLAS(file.path(baseline, "references", paste0("plot_", pid, ".laz")))
    classes <- fgi_reference_classes(as.data.frame(ref@data), metadata[[pid]])
    ref <- ref[ref$Classification != 5L]
    points <- as.data.frame(ref@data[, .(X, Y, Z, Classification, tree_index)])
    normalized <- lidR::readLAS(file.path(baseline, "prepared", pid, "normalized.laz"))
    query <- as.data.frame(normalized@data[, .(X, Y, Z)])
    rm(normalized)
    save_score <- function(arm, raw) {
      s <- cbind(data.frame(plot = pid, split = "training", arm = arm),
                 audit_label_stats(raw, points, classes))
      scores[[length(scores) + 1L]] <<- s
      p <- fgi_filter_predictions(raw, points$Z)
      las <- lidR::add_lasattribute(ref, ifelse(is.na(p), 0L, p), "tree_pred", "Instance; zero background")
      directory <- file.path(outdir, "instances", arm, "training")
      dir.create(directory, recursive = TRUE, showWarnings = FALSE)
      lidR::writeLAS(las, file.path(directory, paste0("plot_", pid, ".laz")))
      cat(pid, arm, sprintf("TP=%d/%d F1=%.4f Cov=%.4f\n", s$TP, s$n_ref, s$F1, s$coverage))
      p
    }
    for (arm in c("segmentanytree", "treeiso", "forestformer3d", "treeisonet")) {
      old_path <- file.path(baseline, "instances", arm, "training", paste0("plot_", pid, ".laz"))
      old_receipt <- readRDS(file.path(baseline, "runs", pid, arm, "score.rds"))
      audit_verify_hashes(setNames(old_receipt$output_md5, old_path))
      old <- lidR::readLAS(old_path)
      d <- as.data.frame(old@data)
      src <- data.frame(X = d$X, Y = d$Y, Z = d$Z, crown_id = d$tree_pred)
      raw <- fgi_aligned_labels(src, points)$labels
      save_score(paste0(arm, "_frozen"), raw)
      rm(old, d, src)
    }
    supports <- list()
    for (route in c("frozen", "native")) {
      directory <- if (route == "frozen") file.path(baseline, "runs", pid, "forestformer3d") else
        file.path(audit, "corrected/runs", pid, "forestformer3d")
      path <- file.path(directory, "predictions.laz")
      src <- fgi_ff_points(path)
      duplicates[[length(duplicates) + 1L]] <- cbind(data.frame(plot = pid, arm = paste0("forestformer3d_", route)),
                                                       audit_duplicate_stats(src))
      mapped <- fgi_transfer_labels(src, points)
      stitched <- mapped$labels
      if (route == "native") save_score("forestformer3d_native", stitched)
      projections[[length(projections) + 1L]] <- data.frame(plot = pid, arm = paste0("forestformer3d_", route),
        supported_fraction = mean(mapped$distance <= .5),
        exact_fraction = mean(mapped$distance <= .002), max_nearest_distance = max(mapped$distance))
      las <- lidR::readLAS(path)
      d <- as.data.frame(las@data[, .(X, Y, Z, block = UserData, inst = PointSourceID)])
      rel <- dedup_blocks(d, merge_tol = 2)
      mapping <- unique(rel[, c("block", "inst", "global_id")])
      apex <- data.table::as.data.table(rel)[, .(Z = max(Z)), by = .(global_id, block, inst)]
      seam <- apex[, .(members = .N, blocks = data.table::uniqueN(block), dz = diff(range(Z))), by = global_id]
      seams[[length(seams) + 1L]] <- data.frame(plot = pid, route = route,
        local_instances = nrow(mapping), stitched_instances = data.table::uniqueN(mapping$global_id),
        clusters_with_same_block_collision = sum(seam$members > seam$blocks),
        merged_clusters_over_5m_z = sum(seam$members > 1 & seam$dz > 5))
      for (block in sort(unique(d$block))) {
        block_src <- d[d$block == block, c("X", "Y", "Z", "inst")]
        names(block_src)[4] <- "crown_id"
        local <- fgi_transfer_labels(block_src, points)
        keep <- local$distance <= .002
        if (route == "frozen") supports[[as.character(block)]] <- keep else
          if (!identical(keep, supports[[as.character(block)]])) stop("Cylinder comparison support changed")
        region <- points[keep, , drop = FALSE]
        full_counts <- table(points$tree_index[points$tree_index > 0])
        part_counts <- table(region$tree_index[region$tree_index > 0])
        truncated <- sum(part_counts < full_counts[names(part_counts)])
        for (mode in c("cylinder", "stitched")) {
          raw <- if (mode == "cylinder") local$labels[keep] else stitched[keep]
          cylinders[[length(cylinders) + 1L]] <- cbind(data.frame(plot = pid, route = route,
            block = block, mode = mode, support_points = sum(keep), truncated_references = truncated),
            audit_label_stats(raw, region, classes))
        }
      }
      rm(src, mapped, las, d, rel, apex); gc()
    }
    path <- file.path(audit, "corrected/runs", pid, "treeisonet/ablations.laz")
    las <- lidR::readLAS(path)
    d <- as.data.frame(las@data)
    production <- read_instance_points_laz(file.path(dirname(path), "aligned.laz"), "tree_pred")
    aligned <- fgi_aligned_labels(production, query)$labels
    expected <- d$supported; expected[expected == 0] <- NA_integer_
    if (!isTRUE(all.equal(aligned, expected))) stop("Production and diagnostic exports disagree")
    rm(production, aligned, expected)
    for (variant in c("shifted_assigned", "physical_assigned", "shifted_aligned", "physical_aligned", "supported_aligned")) {
      label <- strsplit(variant, "_", fixed = TRUE)[[1]][1]
      src <- data.frame(X = d$X, Y = d$Y, Z = d$Z, crown_id = d[[label]])
      if (variant == "supported_aligned") duplicates[[length(duplicates) + 1L]] <-
        cbind(data.frame(plot = pid, arm = "treeisonet_supported_aligned"), audit_duplicate_stats(src))
      if (endsWith(variant, "assigned")) {
        src <- src[src$crown_id > 0, ]
        transfer <- fgi_transfer_labels(src, query)
      } else transfer <- fgi_aligned_labels(src, query)
      save_score(paste0("treeisonet_", variant), transfer$labels)
      projections[[length(projections) + 1L]] <- data.frame(plot = pid, arm = paste0("treeisonet_", variant),
        supported_fraction = mean(transfer$distance <= .5), exact_fraction = mean(transfer$distance <= .002),
        max_nearest_distance = max(transfer$distance))
    }
    write.csv(data.table::rbindlist(scores), file.path(outdir, "scores.csv"), row.names = FALSE)
    write.csv(data.table::rbindlist(cylinders), file.path(outdir, "cylinders.csv"), row.names = FALSE)
    write.csv(data.table::rbindlist(projections), file.path(outdir, "projection.csv"), row.names = FALSE)
    write.csv(data.table::rbindlist(seams), file.path(outdir, "stitching.csv"), row.names = FALSE)
    write.csv(data.table::rbindlist(duplicates), file.path(outdir, "duplicates.csv"), row.names = FALSE)
    rm(ref, points, query, las, d); gc()
  }
  scores <- as.data.frame(data.table::rbindlist(scores))
  summary <- fgi_summary(scores, unique(scores$arm))
  write.csv(summary, file.path(outdir, "summary.csv"), row.names = FALSE)
  opt <- fgi_options(c("SPLIT=training", paste0("OUT_DIR=", outdir),
    paste0("DATA_DIR=", root, "/source"), paste0("EVAL_PYTHON=", python)))
  fgi_official_check(summary, opt, fgi_resources(opt))
  inputs <- c(list.files(file.path(audit, "corrected"), "receipt.rds$", recursive = TRUE, full.names = TRUE),
    file.path(root, "training/run_manifest.json"), file.path(audit, "baseline_1019/run_manifest.json"),
    file.path(audit, "declaration.json"), .find("transfer_audit_lib.R"), .find("external_fgiemit_lib.R"))
  jsonlite::write_json(as.list(tools::md5sum(inputs)), file.path(outdir, "analysis_manifest.json"),
                       auto_unbox = TRUE, pretty = TRUE)
}
