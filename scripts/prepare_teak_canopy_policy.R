#!/usr/bin/env Rscript
# Read pinned derived packages only; no fetch, inference, or real metric input.
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.code <- file.path(dirname(.self), c(basename(.self), "bootstrap.R", "repo_paths.R",
                                    "teak_canopy_lib.R", "teak_canopy_policy_lib.R"))
.before <- unname(vapply(.code, digest::digest, character(1), file = TRUE, algo = "sha256"))
source(file.path(dirname(.self), "bootstrap.R"))
source(.find("teak_canopy_lib.R"))
source(.find("teak_canopy_policy_lib.R"))
a <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(a, function(z) paste(z[-1], collapse = "=")),
              vapply(a, `[`, character(1), 1))
if (!setequal(names(A), c("PACKAGE", "PILOT", "OUT")) || anyDuplicated(names(A)) ||
    any(!nzchar(unlist(A)))) stop("Usage: PACKAGE=prepared_package PILOT=prepared_pilot OUT=fresh_directory")
package <- canopy_resolve(path.expand(A$PACKAGE))
pilot <- canopy_resolve(path.expand(A$PILOT))
out <- canopy_resolve(path.expand(A$OUT))
if (file.exists(out) || any(vapply(c(package, pilot), function(p)
    out == p || startsWith(out, paste0(p, "/")) || startsWith(p, paste0(out, "/")), logical(1))))
  stop("OUT must be fresh and separate from both inputs")
policy_path <- file.path(.ROOT, "docs/teak-canopy-policy.json")
policy_hash <- canopy_hash(policy_path)
p <- jsonlite::fromJSON(policy_path)
policy_validate(p)
if (p$matching$clue_version != as.character(packageVersion("clue")))
  stop("Unsupported clue version")
manifest_paths <- file.path(.ROOT, "docs", c("teak-canopy-sources.json", "teak-native-pilot-sources.json"))
manifest_hashes <- canopy_hash(manifest_paths)
verify <- function() {
  r <- policy_verify_outputs(package, p$package_receipt_sha256)
  n <- policy_verify_outputs(pilot, p$pilot_receipt_sha256)
  if (!identical(canopy_hash(manifest_paths), manifest_hashes) ||
      r$source_manifest_sha256 != manifest_hashes[1] ||
      n$manifest_sha256 != manifest_hashes[2] ||
      n$parent_manifest_sha256 != r$source_manifest_sha256)
    stop("Linked source manifests disagree")
  m <- jsonlite::fromJSON(manifest_paths[1]); nm <- jsonlite::fromJSON(manifest_paths[2])
  if (nm$parent_manifest_sha256 != manifest_hashes[1] || nm$plot != "TEAK_043" ||
      nm$context_buffer_m != p$context_buffer_m ||
      r$nte_revision != m$nte_revision || r$hf_revision != m$hf_revision)
    stop("Source revision/pilot linkage mismatch")
  list(package = r, pilot = n, source_manifest = m)
}
parents <- verify()
read_package <- function(name) read.csv(file.path(package, name), stringsAsFactors = FALSE)
x <- read_package("paired_plot_inventory.csv")
policy_rectangles(x); policy_ids(x$image_id, "image IDs")
if (nrow(x) != 18L || sum(x$n_boxes) != 734L || anyNA(x$evaluation_ready) ||
    any(x$evaluation_ready) || !setequal(x$plotID, p$plots$plotID)) stop("Unexpected package scope")
queue <- read_package("review_queue.csv")
policy_ids(queue$plotID, "review plot IDs")
qi <- match(x$plotID, queue$plotID)
if (nrow(queue) != nrow(x) || anyNA(qi) ||
    !identical(queue$image_id[qi], x$image_id) ||
    !identical(queue$n_boxes[qi], x$n_boxes) ||
    !identical(queue$local_use[qi], x$local_use) ||
    any(queue$annotation_review != "pending" | queue$evaluation_ready))
  stop("Parent review queue disagrees")
boxes <- policy_audit_boxes(read_package("pixel_boxes.csv"), x)
footprints <- sf::st_read(file.path(package, "image_footprints.geojson"), quiet = TRUE)
projected <- sf::st_read(file.path(package, "canopy_boxes.geojson"), quiet = TRUE)
if (is.na(sf::st_crs(footprints)) || is.na(sf::st_crs(projected)) ||
    sf::st_crs(footprints)$epsg != 32611L || sf::st_crs(projected)$epsg != 32611L)
  stop("Projected geometry CRS mismatch")
policy_ids(footprints$plotID, "footprint plot IDs")
projected_keys <- paste(projected$image_id, projected$object_index, sep = ":")
policy_ids(projected_keys, "projected box IDs")
if (!setequal(footprints$plotID, x$plotID) || !setequal(projected_keys, boxes$box_key))
  stop("Projected identities disagree")
# Check every polygon against the same pixel-edge affine mapping, not just bounds.
for (i in seq_len(nrow(x))) {
  r <- terra::rast(nrows = 400, ncols = 400, xmin = x$rgb_xmin[i], xmax = x$rgb_xmax[i],
    ymin = x$rgb_ymin[i], ymax = x$rgb_ymax[i], crs = "EPSG:32611")
  rows <- which(boxes$plotID == x$plotID[i]); b <- boxes[rows, ]
  expected <- canopy_project_boxes(b, r)
  observed <- projected[match(b$box_key, projected_keys), ]
  same <- sf::st_equals_exact(expected, observed, par = 1e-7)
  if (!all(vapply(seq_along(same), function(j) j %in% same[[j]], logical(1))))
    stop("Projected box mapping disagrees")
  actual <- footprints[match(x$plotID[i], footprints$plotID), ]
  expected_core <- sf::st_as_sfc(sf::st_bbox(c(xmin = x$rgb_xmin[i], ymin = x$rgb_ymin[i],
    xmax = x$rgb_xmax[i], ymax = x$rgb_ymax[i]), crs = sf::st_crs(32611)))
  if (!isTRUE(sf::st_equals_exact(actual, expected_core, par = 1e-7,
                                 sparse = FALSE)[1, 1]))
    stop("Footprint geometry disagrees")
}
pairs <- policy_spatial_pairs(x, p$context_buffer_m)
groups <- policy_groups(x, pairs)
pi <- match(groups$plotID, p$plots$plotID)
if (any(groups$spatial_group != p$plots$spatial_group[pi]) ||
    any(groups$role != p$plots$role[pi]) || any(p$plots$evaluation_ready))
  stop("Computed roles/groups disagree with frozen policy")
x <- x[match(groups$plotID, x$plotID), ]
plot_policy <- cbind(x[, c("plotID", "image_id", "local_use", "n_boxes", "rgb_epsg",
  "rgb_resolution_m", "rgb_xmin", "rgb_xmax", "rgb_ymin", "rgb_ymax")], groups[, -1])
for (field in c("literal_boundary", "within_1px", "within_2m", "duplicate_geometry", "overlap_other_box"))
  plot_policy[[paste0("n_", field)]] <- vapply(x$plotID, function(id)
    sum(boxes[[field]][boxes$plotID == id]), integer(1))
for (gap in p$diagnostic_context_gaps_m)
  plot_policy[[paste0("diagnostic_group_gap_", gap, "m")]] <- policy_groups(x, pairs, gap)$spatial_group
for (field in c("box_review", "completeness_review", "ambiguity_review", "edge_review",
                "timing_review", "coregistration_review", "native_input_review"))
  plot_policy[[field]] <- "pending"
plot_policy$review_scope <- "whole published 40 m image; completeness includes all unlabeled canopy"
plot_policy$forestformer3d_exposure <- "unknown"; plot_policy$segmentanytree_exposure <- "unknown"
plot_policy$edge_policy <- "full_image_clip_positive_area_no_ignore"
summary <- jsonlite::fromJSON(file.path(pilot, "pilot_summary.json"))
if (summary$plot != "TEAK_043" || !identical(summary$evaluation_ready, FALSE) ||
    !identical(summary$reference_review_complete, FALSE) || summary$detector_runs != 0L ||
    !identical(summary$checkpoint_review$independent_holdout_claim_supported, FALSE))
  stop("Unexpected pilot state")
for (arm in names(p$checkpoint_hashes)) {
  if (summary$checkpoint_review$checkpoints[[arm]]$sha256 != p$checkpoint_hashes[[arm]])
    stop("Checkpoint identity mismatch")
  exposure <- summary$checkpoint_review$upstream_training_overlap[[arm]]
  candidates <- groups$plotID[groups$role == "reserved_unadmitted"]
  if (!setequal(names(exposure), candidates) || any(unlist(exposure) != "unknown"))
    stop("Unexpected checkpoint exposure state")
}
# Per-row lineage binds original XML metadata; source payloads are not reread.
xml_paths <- paste0("nte/annotations/", boxes$image_id, ".xml")
xml_i <- match(xml_paths, parents$source_manifest$sources$path)
if (anyNA(xml_i)) stop("Missing annotation provenance")
boxes$annotation_source_path <- xml_paths
boxes$annotation_source_sha256 <- parents$source_manifest$sources$sha256[xml_i]
boxes$package_receipt_sha256 <- p$package_receipt_sha256
boxes$policy_sha256 <- policy_hash
plot_policy$package_receipt_sha256 <- p$package_receipt_sha256
plot_policy$policy_sha256 <- policy_hash
# Render only the historical pilot. Candidate RGB pixels are never decoded.
pilot_row <- x[x$plotID == "TEAK_043", ]
rgb <- terra::rast(file.path(pilot, "native_rgb_context.tif"))
if (is.na(sf::st_crs(terra::crs(rgb))) || sf::st_crs(terra::crs(rgb))$epsg != 32611L)
  stop("Pilot RGB CRS mismatch")
rgb <- terra::crop(rgb, terra::ext(pilot_row$rgb_xmin, pilot_row$rgb_xmax,
                                  pilot_row$rgb_ymin, pilot_row$rgb_ymax))
if (nrow(rgb) != 400 || ncol(rgb) != 400 || terra::nlyr(rgb) < 3L ||
    max(abs(as.vector(terra::ext(rgb)) - unlist(pilot_row[, c("rgb_xmin", "rgb_xmax",
      "rgb_ymin", "rgb_ymax")], use.names = FALSE))) > 1e-7) stop("Pilot crop mismatch")
if (!dir.create(out, recursive = TRUE)) stop("Cannot create fresh output directory")
write.csv(boxes, file.path(out, "box_review.csv"), row.names = FALSE)
write.csv(plot_policy, file.path(out, "plot_policy.csv"), row.names = FALSE)
write.csv(pairs, file.path(out, "spatial_pairs.csv"), row.names = FALSE)
png(file.path(out, "review_panel.png"), width = 1800, height = 1000, res = 120)
par(mfrow = c(1, 2))
for (overlay in c(FALSE, TRUE)) {
  terra::plotRGB(rgb, axes = TRUE, mar = c(3, 3, 4, 1),
    main = if (overlay) "TEAK_043 published boxes and object IDs\nHuman review pending; development only"
      else "TEAK_043 native RGB crop\nHistorical development pilot; no evaluation")
  if (overlay) {
    b <- boxes[boxes$plotID == "TEAK_043", ]
    projected_b <- canopy_project_boxes(b, rgb)
    plot(sf::st_geometry(projected_b), add = TRUE, border = "yellow", lwd = 1.2)
    cx <- pilot_row$rgb_xmin + (b$xmin + b$xmax) / 2 * pilot_row$rgb_resolution_m
    cy <- pilot_row$rgb_ymax - (b$ymin + b$ymax) / 2 * pilot_row$rgb_resolution_m
    text(cx, cy, b$object_index, col = "yellow", cex = 0.85, font = 2)
  }
}
dev.off()
# Small synthetic crossing graph exercises cardinality; no real boxes are scored.
fixture <- matrix(c(0.9, 0.6, 0.6, 0), 2, byrow = TRUE)
synthetic <- policy_match_synthetic(fixture, c("A", "B"), c("X", "Y"))
synthetic$synthetic <- TRUE; synthetic$real_scores <- FALSE; synthetic$evaluation_ready <- FALSE
write.csv(synthetic, file.path(out, "synthetic_contract.csv"), row.names = FALSE)
policy_summary <- list(schema_version = 1, evaluation_ready = FALSE, real_scores = FALSE,
  plots = nrow(x), boxes = nrow(boxes), spatial_groups = length(unique(groups$spatial_group)),
  development_plots = sum(groups$role == "development"),
  reserved_unadmitted_plots = sum(groups$role == "reserved_unadmitted"),
  literal_boundary_boxes = sum(boxes$literal_boundary), within_1px_boxes = sum(boxes$within_1px),
  within_2m_boxes = sum(boxes$within_2m), duplicate_geometry_boxes = sum(boxes$duplicate_geometry),
  overlap_other_box_count = sum(boxes$overlap_other_box),
  human_review = "pending", checkpoint_exposure = "unknown", independent_holdout_claim_supported = FALSE,
  pixels_decoded = "historical TEAK_043 native RGB only", synthetic_contract_matches = nrow(synthetic),
  verification_scope = "all advertised parent-derived outputs and linked manifests; original source payloads not reread",
  policy = p)
jsonlite::write_json(policy_summary, file.path(out, "policy_summary.json"), pretty = TRUE,
                     auto_unbox = TRUE, na = "null", digits = NA)
parents_after <- verify()
if (!identical(canopy_hash(.code), .before) || canopy_hash(policy_path) != policy_hash)
  stop("Code/policy changed during preparation")
outputs <- sort(list.files(out, full.names = TRUE, recursive = TRUE))
receipt <- list(schema_version = 1, evaluation_ready = FALSE, real_scores = FALSE,
  verification_scope = policy_summary$verification_scope,
  inputs = data.frame(path = c(file.path(package, "receipt.json"), file.path(pilot, "receipt.json"),
    manifest_paths, policy_path), sha256 = c(p$package_receipt_sha256, p$pilot_receipt_sha256,
    manifest_hashes, policy_hash), bytes = file.info(c(file.path(package, "receipt.json"),
      file.path(pilot, "receipt.json"), manifest_paths, policy_path))$size),
  verified_parent_outputs = list(package = parents_after$package$outputs, pilot = parents_after$pilot$outputs),
  code = data.frame(path = basename(.code), sha256 = .before),
  packages = as.list(vapply(c("sf", "terra", "jsonlite", "digest", "clue"),
    function(z) as.character(packageVersion(z)), character(1))),
  outputs = data.frame(path = basename(outputs), bytes = file.info(outputs)$size,
    sha256 = canopy_hash(outputs)))
jsonlite::write_json(receipt, file.path(out, "receipt.json"), pretty = TRUE, auto_unbox = TRUE)
cat("Prepared", nrow(boxes), "box review rows across", nrow(x), "plots; all unadmitted.\n")
