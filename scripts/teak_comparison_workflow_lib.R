# Bounded historical TEAK_043 handoff. Evidence authenticity remains human-attested.
workflow_require <- function(x, why) if (!isTRUE(x)) stop(why, call. = FALSE)
workflow_text <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
workflow_sha <- function(x) workflow_text(x) && grepl("^[0-9a-f]{64}$", x)
workflow_json <- function(x) charToRaw(paste0(jsonlite::toJSON(x, auto_unbox = TRUE,
  pretty = TRUE, digits = 16, na = "null", null = "null", dataframe = "rows"), "\n"))
workflow_csv <- function(x) {
  con <- textConnection("text", "w", local = TRUE); on.exit(close(con))
  write.csv(x, con, row.names = FALSE, na = "")
  charToRaw(paste0(paste(text, collapse = "\n"), "\n"))
}
workflow_read <- function(path) jsonlite::fromJSON(path, simplifyVector = FALSE)
workflow_table <- function(path) read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
  na.strings = "", colClasses = NA)
workflow_safe <- function(path, exists = TRUE) {
  path <- path.expand(path)
  if (!startsWith(path, "/")) path <- file.path(getwd(), path)
  workflow_require(!any(strsplit(path, "/", fixed = TRUE)[[1]] %in% c(".", "..")),
                   "Dot path components are unsupported")
  p <- path
  repeat {
    link <- Sys.readlink(p)
    workflow_require(is.na(link) || !nzchar(link), "Symlink path rejected")
    if (dirname(p) == p) break
    p <- dirname(p)
  }
  if (exists) workflow_require(file.exists(path), paste("Missing input", path))
  canopy_resolve(path)
}
workflow_child <- function(root, relative) {
  canopy_check_paths(relative)
  workflow_safe(file.path(root, relative))
}
workflow_record <- function(path, relative = path) data.frame(path = relative,
  bytes = file.info(path)$size, sha256 = canopy_hash(path), stringsAsFactors = FALSE)
workflow_check <- function(root, record) {
  workflow_require(workflow_text(record$path) && workflow_sha(record$sha256), "Invalid file record")
  path <- workflow_child(root, record$path)
  workflow_require(!file.info(path)$isdir && canopy_hash(path) == record$sha256 &&
    (is.null(record$bytes) || file.info(path)$size == record$bytes), paste("Changed input", path))
  path
}
workflow_parent_spec <- function() list(
  policy = list(root = "teak-canopy-policy-output/final-run", hash =
    "3dcfd975bff6dc5492a6c3430fc0e8e5ef816c87e18145aa30b262cb8a694ff4"),
  pilot = list(root = "teak-native-pilot-output/final-run", hash =
    "ac1e50570d2b383e517ccd3c49ca7ae543068ffd6e88ad06b5339fe971c066af"),
  reference = list(root = "teak-canopy-reference/final-run", hash =
    "79d71e4685e5c68947483fa880589ae6dbcfc1ef413f4175b945ddb6c6f9a079"),
  timing = list(root = "teak-acquisition-timing-output/final-run", hash =
    "41ebec99909fe29719bb52c5e1606738980132cbbf416ae608aa52fd78653bec"),
  mosaic = list(root = "teak-mosaic-provenance-output/final-run", hash =
    "b6301ab5ad88d476321768683f531235b38b309dda1955fd8d9234774da65692"),
  smoke = list(root = "teak-detector-smoke-output/run-v1", hash =
    "3a4f162c78713b9772026b8d2356731376a66cfb9cd4326896e28235169dde03"))
workflow_arms <- c("chm_vwf", "segmentanytree", "forestformer3d")
workflow_support <- function() list(plot = "TEAK_043", image = "TEAK_043_2018",
  spatial_group = "TEAK_043", role = "historical_development", width = 400L, height = 400L,
  epsg = 32611L, affine = c(0.1, 0, 321034.5, 0, -0.1, 4096751.1),
  native_sha256 = "2eb5334a946c06dc05163be0c2eb122018fcdd1e17fc6e74cfb5dcad8c4005b6",
  rgb_sha256 = "c22f591c82fb8a080512a3b84f947c01c6c0273362e6b014b3f3ebe992b7d0c2",
  annotation_sha256 = "98410b3a01d0d7bfd3fd55f2809935642a5701449665d04159ecba7994c11034",
  exclusions = list())
workflow_equal <- function(a, b) identical(
  jsonlite::fromJSON(rawToChar(workflow_json(a))),
  jsonlite::fromJSON(rawToChar(workflow_json(b))))
workflow_parents <- function(base, repo) {
  specs <- workflow_parent_spec(); inputs <- list(); receipts <- list(); roots <- list()
  for (name in names(specs)) {
    root <- workflow_safe(file.path(base, specs[[name]]$root)); roots[[name]] <- root
    path <- workflow_check(root, list(path = "receipt.json", sha256 = specs[[name]]$hash))
    r <- workflow_read(path); receipts[[name]] <- r; inputs[[length(inputs) + 1L]] <- workflow_record(path)
    workflow_require(identical(r$evaluation_ready, FALSE), "Parent readiness changed")
    output <- if (name == "smoke") lapply(names(r$output_sha256), function(p)
      list(path = p, sha256 = r$output_sha256[[p]])) else r$outputs
    workflow_require(length(output) > 0L, "Missing parent output manifest")
    canopy_check_paths(vapply(output, `[[`, "", "path"))
    for (row in output) {
      p <- workflow_check(root, row); inputs[[length(inputs) + 1L]] <- workflow_record(p)
    }
  }
  # Manifests are verified from pinned timing receipt, not accepted by name alone.
  for (row in receipts$timing$manifests) {
    p <- workflow_check(repo, row); inputs[[length(inputs) + 1L]] <- workflow_record(p)
  }
  pp <- file.path(repo, "docs/teak-canopy-policy.json")
  workflow_require(canopy_hash(pp) == "d523866908a4cc2e5a53ce920ec865d118f0d1038b9e28352d89ea1379457888",
                   "Original policy declaration changed")
  policy_validate(jsonlite::fromJSON(pp)); inputs[[length(inputs) + 1L]] <- workflow_record(pp)
  boxes <- workflow_table(file.path(roots$policy, "box_review.csv"))
  boxes <- boxes[boxes$plotID == "TEAK_043", , drop = FALSE]
  workflow_require(nrow(boxes) == 24L && identical(boxes$object_index, seq_len(24L)) &&
    all(boxes$human_status == "pending") && all(boxes$annotation_source_sha256 ==
      workflow_support()$annotation_sha256), "Original box queue differs")
  policy_box_geometry(boxes, boxes$box_key)
  native <- workflow_check(file.path(base, "teak-native-pilot"), list(
    path = "sources/2018_TEAK_3_321000_4096000_image.tif", bytes = 66339823,
    sha256 = workflow_support()$rgb_sha256))
  inputs[[length(inputs) + 1L]] <- workflow_record(native)
  pilot <- workflow_read(file.path(roots$pilot, "pilot_summary.json"))
  workflow_require(identical(unlist(pilot$core_extent), c(321034.5, 321074.5, 4096711.1, 4096751.1)) &&
    pilot$source_point_rows == 43460L && pilot$normalized_point_rows == 43460L,
    "Native support differs")
  density <- workflow_table(file.path(roots$pilot, "density.csv"))
  workflow_require(all(abs(density$frdens - density$first_returns / density$area_m2) < 1e-9) &&
    all(abs(density$pdens - density$n_points / density$area_m2) < 1e-9), "Native density differs")
  workflow_require(identical(receipts$smoke$model_observed, TRUE) &&
    length(receipts$smoke$reserved_plots_processed) == 0L, "Historical model-observed scope changed")
  inputs <- unique(do.call(rbind, inputs)); inputs <- inputs[order(inputs$path), ]
  rownames(inputs) <- NULL
  list(inputs = inputs, roots = roots, receipts = receipts, boxes = boxes,
       native_rgb = native, support = workflow_support(), density = density)
}
workflow_tiles <- function() {
  x <- expand.grid(column = 0:3, row = 0:3)
  data.frame(tile_id = paste0("r", x$row + 1L, "c", x$column + 1L),
    xmin = x$column * 100, ymin = x$row * 100, xmax = (x$column + 1L) * 100,
    ymax = (x$row + 1L) * 100, status = "pending", observation = "", linked_keys = "",
    evidence_id = "", reviewer_id = "", reviewed_utc = "")
}
workflow_empty_boxes <- function() data.frame(id = character(), xmin = numeric(),
  ymin = numeric(), xmax = numeric(), ymax = numeric(), stringsAsFactors = FALSE)
workflow_templates <- function(boxes, support) {
  review <- data.frame(key = boxes$box_key, original_key = boxes$box_key,
    action = "pending", original_xmin = boxes$xmin, original_ymin = boxes$ymin,
    original_xmax = boxes$xmax, original_ymax = boxes$ymax,
    xmin = NA_real_, ymin = NA_real_, xmax = NA_real_, ymax = NA_real_,
    tile_id = "", edge_decision = "pending", overlap_decision = "pending",
    split_merge_decision = "pending", vegetation_decision = "pending", uncertainty_note = "", rationale = "",
    evidence_id = "", reviewer_id = "", reviewed_utc = "")
  attestation <- list(schema_version = 1L, origin = "generated_template_not_evidence",
    revision_id = "", reviewer_id = "", supplied_by = "", review_started_utc = "", reviewed_utc = "",
    predictions_seen = "unknown", attestation_evidence_id = "",
    authenticity = "not_independently_authenticated", method = "",
    whole_image = list(completeness = "pending", unboxed_canopy = "pending",
      ambiguous_vegetation = "pending", edge_truncation = "pending", rationale = ""))
  ties <- data.frame(id = character(), status = character(), feature_type = character(),
    description = character(), rgb_x_px = numeric(), rgb_y_px = numeric(),
    lidar_x_m = numeric(), lidar_y_m = numeric(), rgb_uncertainty_m = numeric(),
    lidar_uncertainty_m = numeric(), independent_method = character(),
    stable_between_dates = character(), evidence_id = character(), reviewer_id = character(),
    rejection_reason = character())
  registration <- list(status = "unknown", method = "", criterion_frozen_utc = "", measured_utc = "",
    evidence_id = "", reviewer_id = "", min_ties = 3L, min_span_px = 100,
    max_residual_m = NULL, max_combined_uncertainty_m = NULL)
  timing <- list(status = "unknown", lidar_anchor = "conditional_mission_week",
    rgb_exposure = "unknown", exact_lag = "unknown", temporal_agreement = "unverified",
    rgb_candidate_days = c("2018-06-14", "2018-06-15"), evidence_id = "",
    reviewer_id = "", rationale = "", limitations = "",
    spatial_coverage = "full_400x400_image", route = "pending")
  exposure <- expand.grid(arm = workflow_arms[-1], phase = c("pretraining", "training",
    "tuning", "model_selection"), stringsAsFactors = FALSE)
  exposure$status <- "unknown"; exposure$evidence_id <- ""; exposure$reviewer_id <- ""
  exposure$rationale <- ""
  adapter <- list(status = "unsupported", output_target = "", input_geometry = "",
    construction_rule = "", frozen_utc = "", reviewer_id = "", evidence_id = "",
    reference_consulted = NULL, code_artifact = "", validation_artifact = "",
    boundary_artifact = "", lineage_artifact = "",
    affine = support$affine, epsg = support$epsg)
  admission <- list(schema_version = 1L, claim = "historical_development_diagnostic",
    status = "pending", support = support, reference_revision = "",
    parent_receipts = lapply(workflow_parent_spec(), `[[`, "hash"),
    temporal_route = "pending", exposure_route = "pending", limitations = "",
    evidence = list(), artifacts = list(),
    arms = lapply(workflow_arms, function(arm) list(arm = arm, status = "not_run",
      support = support, reference_revision = "", checkpoint_sha256 = "",
      config_artifact = "", source_artifact = "", prediction_artifact = "",
      adapter_artifact = "")))
  list("reference_review_template.csv" = workflow_csv(review),
    "whole_image_review_template.json" = workflow_json(attestation),
    "tile_review_template.csv" = workflow_csv(workflow_tiles()),
    "registration_ties_template.csv" = workflow_csv(ties),
    "registration_template.json" = workflow_json(registration),
    "timing_evidence_template.json" = workflow_json(timing),
    "checkpoint_exposure_template.csv" = workflow_csv(exposure),
    "crown_adapter_template.json" = workflow_json(adapter),
    "admission_manifest_template.json" = workflow_json(admission))
}
workflow_current_gates <- function(parents) {
  names <- c("parent_integrity", "native_input", "study_declaration", "reference_revision",
    "whole_image_coverage", "registration", "timing", "checkpoint_exposure",
    "crown_box_adapters", "paired_outcomes")
  state <- c("pass", "pass", "pending", "pending", "pending", "unknown", "unknown",
             "unknown", "unsupported", "not_run")
  need <- c("Pinned receipts and every advertised output verified",
    "Frozen native support and measured density verified; does not establish registration",
    "Separate frozen historical-development declaration; independent holdout unavailable",
    "Human-attested original/add/edit/remove decisions with evidence and uncertainty",
    "Observations for all 16 image tiles; settle unboxed canopy, ambiguity and edges",
    "Independent stable-ground correspondences, residuals and predeclared uncertainty limits",
    "Production provenance or explicitly reviewed bounded conditional temporal claim",
    "Phase-specific records or explicit conditional development limitation",
    "Reviewed frozen visible-canopy crown adapters; treetops and sparse point proxies rejected",
    "All three crown-box arms completed on identical reference and native support")
  parent <- c("policy", "pilot", "policy", "policy", "policy", "pilot", "mosaic", "pilot", "smoke", "smoke")
  data.frame(gate = names, status = state, evidence_path = vapply(parent,
    function(p) file.path(parents$roots[[p]], "receipt.json"), ""),
    evidence_sha256 = vapply(parent, function(p) workflow_parent_spec()[[p]]$hash, ""),
    reason = need, stringsAsFactors = FALSE)
}
workflow_rgb <- function(path) {
  old <- Sys.getenv(c("GDAL_DISABLE_READDIR_ON_OPEN", "GDAL_PAM_ENABLED"), unset = NA)
  on.exit(for (i in seq_along(old)) if (is.na(old[i])) Sys.unsetenv(names(old)[i]) else
    do.call(Sys.setenv, setNames(list(old[i]), names(old)[i])))
  Sys.setenv(GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR", GDAL_PAM_ENABLED = "NO")
  r <- terra::rast(path)
  workflow_require(terra::nlyr(r) == 3L && all(terra::res(r) == c(.1, .1)) &&
    !terra::is.rotated(r) && sf::st_crs(terra::crs(r))$epsg == 32611L,
    "Native RGB grid differs")
  r <- terra::crop(r, terra::ext(321034.5, 321074.5, 4096711.1, 4096751.1), snap = "near")
  workflow_require(nrow(r) == 400L && ncol(r) == 400L &&
    max(abs(as.vector(terra::ext(r)) - c(321034.5, 321074.5, 4096711.1, 4096751.1))) < 1e-7,
    "Unexpected image core")
  v <- terra::values(r); workflow_require(all(is.finite(v)) && all(v >= 0 & v <= 255),
    "Missing or non-byte RGB samples; never hide value 255")
  rgb <- array(0, c(400, 400, 3))
  for (i in 1:3) rgb[, , i] <- matrix(v[, i] / 255, 400, 400, byrow = TRUE)
  png::writePNG(rgb, target = raw())
}
workflow_packet <- function(parents) {
  rgb <- workflow_rgb(parents$native_rgb); b <- parents$boxes
  shape <- vapply(seq_len(nrow(b)), function(i) sprintf(paste0(
    '<rect x="%g" y="%g" width="%g" height="%g" fill="none" stroke="yellow"/>',
    '<text x="%g" y="%g" fill="white" stroke="black" stroke-width="0.3" ',
    'font-size="10" font-family="sans-serif">%d</text>'), b$xmin[i], b$ymin[i],
    b$xmax[i] - b$xmin[i], b$ymax[i] - b$ymin[i], b$xmin[i] + 1,
    min(395, b$ymin[i] + 10), b$object_index[i]), "")
  svg <- paste0('<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" ',
    'viewBox="0 0 400 400"><image width="400" height="400" href="data:image/png;base64,',
    jsonlite::base64_enc(rgb), '"/>', paste(shape, collapse = ""), '</svg>\n')
  gates <- workflow_current_gates(parents)
  manifest <- list(schema_version = 1L, plot = "TEAK_043", status = "blocked",
    support = parents$support, parent_receipts = lapply(workflow_parent_spec(), `[[`, "hash"),
    pixel_source = "original native L3 uint8 RGB; full 400x400; 255 opaque; no nodata suppression",
    original_boxes = nrow(b), model_observed = TRUE,
    reviewer_blinding = "unknown; ask each reviewer; project has already run models",
    reserved_plots_processed = list(), authenticity = "templates are not human evidence")
  readme <- c("# Historical TEAK_043 review packet", "",
    "Status: blocked. No accuracy metrics or model overlays are included.", "",
    "1. Inspect original_rgb.png and every cell in tile_review_template.csv.",
    "2. Inspect numbered_boxes.svg and all 24 original_boxes.csv rows.",
    "3. Copy templates into a new evidence bundle; preserve this packet unchanged.",
    "4. Record human decisions, additions and evidence. Never infer completeness",
    "   from automatic keep decisions. Each tile includes unboxed space.",
    "5. Complete independent registration, timing, checkpoint and adapter records.", "",
    "This is historical model-observed development data, never independent holdout.",
    "Source exposure/lag and registration remain unresolved. RGB agreement is",
    "compatibility only. Existing treetops and sparse point extents are not crowns.",
    "Software verifies hashes and structure; it cannot authenticate human inspection.")
  c(list("original_rgb.png" = rgb, "numbered_boxes.svg" = charToRaw(svg),
    "original_boxes.csv" = workflow_csv(b), "review_packet_manifest.json" = workflow_json(manifest),
    "preflight.csv" = workflow_csv(gates), "preflight.json" = workflow_json(list(
      plot = "TEAK_043", status = "blocked", gates = gates, reserved_plots_processed = list())),
    "START_HERE.md" = charToRaw(paste0(paste(readme, collapse = "\n"), "\n"))),
    workflow_templates(b, parents$support))
}
workflow_time <- function(x) {
  workflow_require(workflow_text(x) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", x),
                   "Expected explicit UTC timestamp")
  z <- as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  workflow_require(!is.na(z), "Invalid UTC timestamp"); z
}
workflow_bundle <- function(root, manifest_sha256) {
  root <- workflow_safe(root)
  path <- workflow_check(root, list(path = "admission_manifest.json", sha256 = manifest_sha256))
  m <- workflow_read(path)
  workflow_require(identical(m$schema_version, 1L) && is.list(m$artifacts) && is.list(m$evidence),
                   "Invalid admission schema")
  workflow_require(length(m$artifacts) > 0L && length(m$evidence) > 0L,
                   "Missing bound artifacts/evidence; templates cannot admit data")
  policy_ids(names(m$artifacts), "artifact IDs"); policy_ids(names(m$evidence), "evidence IDs")
  paths <- c(vapply(m$artifacts, `[[`, "", "path"), vapply(m$evidence, `[[`, "", "path"))
  canopy_check_paths(paths)
  inputs <- list(workflow_record(path)); artifacts <- list()
  for (id in names(m$artifacts)) {
    p <- workflow_check(root, m$artifacts[[id]]); artifacts[[id]] <- p
    inputs[[length(inputs) + 1L]] <- workflow_record(p)
  }
  for (id in names(m$evidence)) {
    e <- m$evidence[[id]]
    workflow_require(all(vapply(e[c("supplied_by", "verified_by", "kind")], workflow_text, logical(1))) &&
      all(c("supplied_by", "verified_by", "kind") %in% names(e)) &&
      e$kind %in% c("human_attestation", "independent_measurement", "production_record", "review_record"),
      "Evidence needs supplier, verifier and explicit human/source kind")
    p <- workflow_check(root, e); inputs[[length(inputs) + 1L]] <- workflow_record(p)
  }
  list(manifest = m, artifacts = artifacts, inputs = do.call(rbind, inputs), root = root)
}
workflow_evidence <- function(bundle, id, reviewer, kind = NULL) {
  workflow_require(workflow_text(id) && id %in% names(bundle$manifest$evidence) && workflow_text(reviewer),
                   "Missing evidence ID or reviewer identity")
  e <- bundle$manifest$evidence[[id]]
  workflow_require(identical(e$verified_by, reviewer) &&
    (is.null(kind) || e$kind %in% kind), "Evidence verifier/kind differs from decision")
  invisible(e)
}
workflow_artifact <- function(bundle, id) {
  workflow_require(workflow_text(id) && id %in% names(bundle$artifacts), "Missing declared artifact")
  bundle$artifacts[[id]]
}
workflow_review <- function(bundle, original) {
  r <- workflow_read(workflow_artifact(bundle, "whole_image_review"))
  workflow_require(identical(r$origin, "human_supplied") &&
    identical(r$authenticity, "self_attested_not_independently_authenticated") &&
    workflow_text(r$revision_id) && workflow_text(r$supplied_by) && workflow_text(r$method) &&
    r$predictions_seen %in% c("yes", "no", "unknown"),
    "Generated/pending review is not a human attestation")
  workflow_require(workflow_time(r$review_started_utc) <= workflow_time(r$reviewed_utc),
                   "Reference completion precedes review start")
  workflow_evidence(bundle, r$attestation_evidence_id, r$reviewer_id, "human_attestation")
  workflow_require(identical(bundle$manifest$reference_revision, r$revision_id),
                   "Reference revision identity differs")
  review <- workflow_table(workflow_artifact(bundle, "reference_review"))
  fields <- c("key", "original_key", "action", paste0("original_", c("xmin", "ymin", "xmax", "ymax")),
    "xmin", "ymin", "xmax", "ymax", "tile_id", "edge_decision", "overlap_decision",
    "split_merge_decision", "vegetation_decision", "uncertainty_note", "rationale", "evidence_id", "reviewer_id", "reviewed_utc")
  workflow_require(all(fields %in% names(review)), "Missing reference review fields")
  policy_ids(review$key, "review keys")
  source <- !is.na(review$original_key) & nzchar(review$original_key)
  workflow_require(setequal(review$original_key[source], original$box_key) &&
    !anyDuplicated(review$original_key[source]) && sum(source) == nrow(original),
    "Duplicate, unknown or silently removed original box key")
  ii <- match(review$original_key[source], original$box_key)
  original_fields <- c("xmin", "ymin", "xmax", "ymax")
  workflow_require(isTRUE(all.equal(unname(as.matrix(review[source, paste0("original_", original_fields)])),
    unname(as.matrix(original[ii, original_fields])), check.attributes = FALSE)),
    "Original reference geometry was edited in place")
  workflow_require(all(review$key[source] == review$original_key[source]) &&
    all(grepl("^added:[A-Za-z0-9_-]+$", review$key[!source])) &&
    all(review$action[source] %in% c("keep", "edit", "remove")) &&
    all(review$action[!source] == "add"), "Pending/unresolved or invalid reference operation")
  for (i in seq_len(nrow(review))) {
    row <- review[i, ]
    workflow_require(all(vapply(as.list(row[c("edge_decision", "overlap_decision", "split_merge_decision",
      "vegetation_decision", "uncertainty_note", "rationale")]), workflow_text, logical(1))) &&
      !any(unlist(row[c("edge_decision", "overlap_decision", "split_merge_decision", "vegetation_decision")]) %in%
        c("pending", "unknown", "unresolved")), "Unresolved reference adjudication")
    workflow_require(row$reviewer_id == r$reviewer_id, "Reference reviewer differs")
    workflow_require(workflow_time(row$reviewed_utc) >= workflow_time(r$review_started_utc) &&
      workflow_time(row$reviewed_utc) <= workflow_time(r$reviewed_utc),
      "Box decision outside declared review interval")
    workflow_evidence(bundle, row$evidence_id, row$reviewer_id)
    if (row$action == "keep") workflow_require(all(as.numeric(row[original_fields]) ==
      as.numeric(row[paste0("original_", original_fields)])), "Keep decision changed geometry")
    if (row$action == "add") workflow_require(row$tile_id %in% workflow_tiles()$tile_id,
                                             "Addition lacks image tile")
  }
  reference <- review[review$action != "remove", c("key", original_fields)]
  names(reference)[1] <- "id"; policy_box_geometry(reference, reference$id)
  workflow_require(all(reference$xmin >= 0 & reference$ymin >= 0 & reference$xmax <= 400 &
    reference$ymax <= 400), "Reviewed reference outside full image")
  list(reference = reference, review = review, attestation = r)
}
workflow_coverage <- function(bundle, review) {
  w <- review$attestation$whole_image
  fields <- c("completeness", "unboxed_canopy", "ambiguous_vegetation", "edge_truncation")
  workflow_require(all(fields %in% names(w)) && all(vapply(w[fields], identical, logical(1), "resolved")) &&
    workflow_text(w$rationale), "Whole-image decisions pending")
  tiles <- workflow_table(workflow_artifact(bundle, "tile_review")); frozen <- workflow_tiles()
  workflow_require(all(names(frozen) %in% names(tiles)), "Incomplete tile review schema")
  policy_ids(tiles$tile_id, "tile IDs")
  workflow_require(setequal(tiles$tile_id, frozen$tile_id), "Incomplete whole-image tile coverage")
  tiles <- tiles[match(frozen$tile_id, tiles$tile_id), ]
  workflow_require(isTRUE(all.equal(as.matrix(tiles[, 2:5]), as.matrix(frozen[, 2:5]), check.attributes = FALSE)), "Tile grid changed")
  workflow_require(all(tiles$status == "reviewed") &&
    all(vapply(as.list(tiles$observation), workflow_text, logical(1))), "Unobserved image tile")
  for (i in seq_len(nrow(tiles))) {
    workflow_require(tiles$reviewer_id[i] == review$attestation$reviewer_id, "Tile reviewer differs")
    workflow_require(workflow_time(tiles$reviewed_utc[i]) >= workflow_time(review$attestation$review_started_utc) &&
      workflow_time(tiles$reviewed_utc[i]) <= workflow_time(review$attestation$reviewed_utc),
      "Tile decision outside declared review interval")
    workflow_evidence(bundle, tiles$evidence_id[i], tiles$reviewer_id[i])
    keys <- if (is.na(tiles$linked_keys[i])) character() else strsplit(tiles$linked_keys[i], ";", fixed = TRUE)[[1]]
    workflow_require(all(keys %in% review$review$key), "Tile links unknown review object")
  }
  additions <- review$review[review$review$action == "add", , drop = FALSE]
  for (i in seq_len(nrow(additions))) {
    ti <- match(additions$tile_id[i], tiles$tile_id)
    workflow_require(additions$key[i] %in% strsplit(tiles$linked_keys[ti], ";", fixed = TRUE)[[1]],
                     "New crown missing from whole-image tile log")
    workflow_require(max(additions$xmin[i], tiles$xmin[ti]) < min(additions$xmax[i], tiles$xmax[ti]) &&
      max(additions$ymin[i], tiles$ymin[ti]) < min(additions$ymax[i], tiles$ymax[ti]),
      "Added crown does not intersect its recorded discovery tile")
  }
  tiles
}
workflow_registration <- function(bundle, review) {
  r <- workflow_read(workflow_artifact(bundle, "registration"))
  workflow_require(identical(r$status, "measured") && workflow_text(r$method) &&
    is.numeric(r$min_ties) && r$min_ties >= 3 && is.numeric(r$min_span_px) &&
    r$min_span_px >= 100 && is.numeric(r$max_residual_m) && r$max_residual_m > 0 &&
    is.numeric(r$max_combined_uncertainty_m) && r$max_combined_uncertainty_m > 0,
    "Missing predeclared registration criterion")
  workflow_require(workflow_time(r$criterion_frozen_utc) < workflow_time(r$measured_utc) &&
    workflow_time(r$measured_utc) <= workflow_time(review$attestation$review_started_utc),
                   "Registration criterion must precede measurements and reference review")
  workflow_evidence(bundle, r$evidence_id, r$reviewer_id, "independent_measurement")
  t <- workflow_table(workflow_artifact(bundle, "registration_ties"))
  fields <- c("id", "status", "feature_type", "description", "rgb_x_px", "rgb_y_px", "lidar_x_m",
    "lidar_y_m", "rgb_uncertainty_m", "lidar_uncertainty_m", "independent_method",
    "stable_between_dates", "evidence_id", "reviewer_id", "rejection_reason")
  workflow_require(all(fields %in% names(t)), "Missing registration tie fields"); policy_ids(t$id)
  workflow_require(all(t$status %in% c("accepted", "rejected")), "Unresolved ground tie")
  for (i in seq_len(nrow(t))) {
    workflow_evidence(bundle, t$evidence_id[i], t$reviewer_id[i], "independent_measurement")
    if (t$status[i] == "rejected") workflow_require(workflow_text(t$rejection_reason[i]), "Undocumented tie rejection")
  }
  keep <- t$status == "accepted"; a <- t[keep, ]
  workflow_require(nrow(a) >= r$min_ties && all(a$feature_type == "stable_ground") &&
    all(a$stable_between_dates == "yes") &&
    all(a$independent_method %in% c("surveyed_ground", "lidar_geometry", "lidar_intensity")) &&
    all(vapply(as.list(a$description), workflow_text, logical(1))), "Insufficient independent ground features")
  numeric <- c("rgb_x_px", "rgb_y_px", "lidar_x_m", "lidar_y_m", "rgb_uncertainty_m", "lidar_uncertainty_m")
  workflow_require(all(vapply(a[numeric], is.numeric, logical(1))) && all(is.finite(as.matrix(a[numeric]))) &&
    all(a$rgb_x_px >= 0 & a$rgb_x_px <= 400 & a$rgb_y_px >= 0 & a$rgb_y_px <= 400) &&
    all(a$rgb_uncertainty_m >= 0 & a$lidar_uncertainty_m >= 0) &&
    diff(range(a$rgb_x_px)) >= r$min_span_px && diff(range(a$rgb_y_px)) >= r$min_span_px,
    "Invalid or spatially concentrated registration ties")
  hull_area <- function(x, y) {
    x <- x - mean(x); y <- y - mean(y)
    k <- grDevices::chull(x, y)
    if (length(k) < 3L) return(0)
    k <- c(k, k[1]); abs(sum(x[k[-length(k)]] * y[k[-1]] - x[k[-1]] * y[k[-length(k)]])) / 2
  }
  workflow_require(min(stats::dist(a[c("rgb_x_px", "rgb_y_px")])) > 1 &&
    min(stats::dist(a[c("lidar_x_m", "lidar_y_m")])) > .1 &&
    hull_area(a$rgb_x_px, a$rgb_y_px) > 1 && hull_area(a$lidar_x_m, a$lidar_y_m) > .01,
    "Ground ties must be distinct, separated and noncollinear in both sensors")
  a$dx_m <- a$lidar_x_m - (321034.5 + .1 * a$rgb_x_px)
  a$dy_m <- a$lidar_y_m - (4096751.1 - .1 * a$rgb_y_px)
  a$residual_m <- sqrt(a$dx_m^2 + a$dy_m^2)
  a$combined_uncertainty_m <- sqrt(a$rgb_uncertainty_m^2 + a$lidar_uncertainty_m^2)
  workflow_require(all(a$residual_m <= r$max_residual_m) &&
    all(a$combined_uncertainty_m <= r$max_combined_uncertainty_m), "Registration criterion failed")
  a
}
workflow_timing <- function(bundle) {
  t <- workflow_read(workflow_artifact(bundle, "timing"))
  # This bounded driver supports a transparent conditional development claim.
  # Definitive source attribution requires a separately implemented spatial map audit.
  workflow_require(identical(bundle$manifest$temporal_route, "conditional_historical") &&
    identical(t$route, "conditional_historical") && identical(t$status, "reviewed_conditional") &&
    identical(t$rgb_exposure, "unknown") && identical(t$exact_lag, "unknown") &&
    identical(t$temporal_agreement, "unverified") && identical(t$spatial_coverage, "full_400x400_image") &&
    workflow_text(t$rationale) && workflow_text(t$limitations), "Temporal evidence/conditional claim incomplete")
  workflow_evidence(bundle, t$evidence_id, t$reviewer_id, c("review_record", "production_record")); t
}
workflow_exposure <- function(bundle) {
  e <- workflow_table(workflow_artifact(bundle, "exposure"))
  fields <- c("arm", "phase", "status", "evidence_id", "reviewer_id", "rationale")
  workflow_require(all(fields %in% names(e)), "Missing checkpoint exposure fields")
  keys <- paste(e$arm, e$phase); policy_ids(keys, "exposure phase keys")
  required <- expand.grid(arm = workflow_arms[-1], phase = c("pretraining", "training", "tuning", "model_selection"))
  workflow_require(setequal(keys, paste(required$arm, required$phase)) &&
    all(e$status %in% c("unknown", "known_exposure", "verified_non_exposure")) &&
    identical(bundle$manifest$exposure_route, "conditional_development"), "Exposure claim/phase coverage differs")
  for (i in seq_len(nrow(e))) {
    workflow_require(workflow_text(e$rationale[i]), "Missing exposure rationale")
    workflow_evidence(bundle, e$evidence_id[i], e$reviewer_id[i])
  }
  e
}
workflow_adapters <- function(bundle, review, parents) {
  arms <- bundle$manifest$arms
  workflow_require(length(arms) == 3L && setequal(vapply(arms, `[[`, "", "arm"), workflow_arms),
                   "Missing, duplicate or extra comparison arm")
  policy_ids(vapply(arms, `[[`, "", "arm"), "arm IDs")
  checkpoints <- jsonlite::fromJSON(file.path(parents$repo, "docs/teak-canopy-policy.json"))$checkpoint_hashes
  for (arm in arms) {
    workflow_require(workflow_equal(arm$support, bundle$manifest$support) &&
      identical(arm$reference_revision, bundle$manifest$reference_revision), "Unpaired support/reference revision")
    expected <- if (arm$arm == "chm_vwf") "not_applicable" else checkpoints[[arm$arm]]
    workflow_require(identical(arm$checkpoint_sha256, expected), "Checkpoint identity differs")
    config <- workflow_artifact(bundle, arm$config_artifact)
    expected_config <- parents$receipts$smoke$output_sha256[[paste0(arm$arm, "/config.json")]]
    workflow_require(canopy_hash(config) == expected_config, "Frozen arm configuration differs")
    source <- workflow_source_inventory(parents, arm$arm)
    workflow_require(canopy_hash(workflow_artifact(bundle, arm$source_artifact)) == source$source_sha256,
                     "Adapter source differs from frozen arm output")
    workflow_artifact(bundle, arm$prediction_artifact)
    adapter <- workflow_read(workflow_artifact(bundle, arm$adapter_artifact))
    workflow_require(identical(adapter$status, "reviewed") &&
      identical(adapter$output_target, "visible_canopy_crown_boxes") &&
      identical(adapter$input_geometry, "crown_geometry") &&
      identical(adapter$reference_consulted, FALSE) && workflow_text(adapter$construction_rule) &&
      workflow_equal(adapter$affine, bundle$manifest$support$affine) &&
      identical(adapter$epsg, 32611L), "Unsupported crown adapter: treetops and sparse point proxies are not crowns")
    workflow_require(workflow_time(adapter$frozen_utc) < workflow_time(review$attestation$review_started_utc),
                     "Adapter not frozen before reference review")
    workflow_evidence(bundle, adapter$evidence_id, adapter$reviewer_id, "review_record")
    workflow_artifact(bundle, adapter$code_artifact)
    validation <- workflow_read(workflow_artifact(bundle, adapter$validation_artifact))
    workflow_require(identical(validation$status, "reviewed_crown_boundary_adapter") &&
      identical(validation$reference_consulted, FALSE) && workflow_text(validation$method) &&
      workflow_text(validation$limitations), "Missing substantive crown adapter validation record")
    workflow_evidence(bundle, validation$evidence_id, validation$reviewer_id, "review_record")
    dependencies <- c(code = adapter$code_artifact, config = arm$config_artifact,
      source = arm$source_artifact, prediction = arm$prediction_artifact,
      boundaries = adapter$boundary_artifact, lineage = adapter$lineage_artifact)
    for (name in names(dependencies)) workflow_require(
      identical(validation$sha256[[name]], canopy_hash(workflow_artifact(bundle, dependencies[[name]]))),
      paste("Adapter validation dependency differs", name))
  }
  arms
}
workflow_admission <- function(bundle, parents) {
  gates <- workflow_current_gates(parents); state <- list()
  check <- function(gate, fun) {
    i <- match(gate, gates$gate)
    tryCatch({ value <- fun(); gates$status[i] <<- "pass"; gates$reason[i] <<- "Evidence structure and bytes verified"
      gates$evidence_path[i] <<- file.path(bundle$root, "admission_manifest.json")
      gates$evidence_sha256[i] <<- canopy_hash(gates$evidence_path[i]); value },
      error = function(e) { gates$status[i] <<- "fail"; gates$reason[i] <<- conditionMessage(e); NULL })
  }
  state$declaration <- check("study_declaration", function() {
    m <- bundle$manifest
    workflow_require(identical(m$status, "frozen") && identical(m$claim, "historical_development_diagnostic") &&
      workflow_equal(m$support, parents$support) &&
      workflow_equal(m$parent_receipts, lapply(workflow_parent_spec(), `[[`, "hash")) &&
      workflow_text(m$limitations), "Only explicitly frozen historical TEAK_043 development is supported")
    m
  })
  state$review <- check("reference_revision", function() workflow_review(bundle, parents$boxes))
  state$tiles <- check("whole_image_coverage", function() {
    workflow_require(!is.null(state$review), "Reference revision blocked"); workflow_coverage(bundle, state$review)
  })
  state$registration <- check("registration", function() {
    workflow_require(!is.null(state$review), "Reference revision blocked"); workflow_registration(bundle, state$review)
  })
  state$timing <- check("timing", function() workflow_timing(bundle))
  state$exposure <- check("checkpoint_exposure", function() workflow_exposure(bundle))
  state$arms <- check("crown_box_adapters", function() {
    workflow_require(!is.null(state$review), "Reference revision blocked"); workflow_adapters(bundle, state$review, parents)
  })
  state$predictions <- check("paired_outcomes", function() {
    workflow_require(!is.null(state$arms) && all(vapply(state$arms, function(a)
      a$status %in% c("completed", "completed_empty"), logical(1))),
      "Unavailable or unsupported arm is unknown, not completed_empty")
    setNames(lapply(state$arms, function(a) workflow_predictions(bundle, a, parents)),
      vapply(state$arms, `[[`, "", "arm"))
  })
  list(status = if (all(gates$status == "pass")) "admitted_historical_diagnostic" else "blocked",
       gates = gates, state = state)
}
workflow_rates <- function(tp, fp, fn) list(precision = if (tp + fp) tp / (tp + fp) else NA_real_,
  recall = if (tp + fn) tp / (tp + fn) else NA_real_,
  F1 = if (2 * tp + fp + fn) 2 * tp / (2 * tp + fp + fn) else NA_real_)
workflow_score <- function(reference, prediction, threshold, status) {
  workflow_require(status %in% c("completed", "completed_empty"), "Unavailable arm blocks scoring")
  policy_box_geometry(reference, reference$id)
  workflow_require(all(reference$xmin >= 0 & reference$ymin >= 0 & reference$xmax <= 400 & reference$ymax <= 400),
                   "Reference outside support")
  policy_box_geometry(prediction, prediction$id)
  workflow_require((status == "completed_empty") == (nrow(prediction) == 0L), "Outcome/prediction count differs")
  clipped <- policy_clip_predictions(prediction, 400, 400)
  matches <- policy_match_synthetic(policy_iou(reference, clipped$boxes), reference$id, clipped$boxes$id, threshold)
  tp <- nrow(matches); fp <- nrow(clipped$boxes) - tp; fn <- nrow(reference) - tp
  list(counts = data.frame(threshold = threshold, status = status, TP = tp, FP = fp, FN = fn,
    n_ref = nrow(reference), n_prediction = nrow(clipped$boxes), n_prediction_before_clip = nrow(prediction),
    outside_predictions = length(clipped$outside_ids), workflow_rates(tp, fp, fn)),
    matches = matches, outside_ids = clipped$outside_ids)
}
workflow_pool <- function(cells) {
  workflow_require(all(c("arm", "plot", "threshold", "support_key", "reference_revision", "TP", "FP", "FN") %in%
    names(cells)) && !anyNA(cells[, c("TP", "FP", "FN")]), "Unknown or incomplete paired cells")
  workflow_require(!anyDuplicated(paste(cells$arm, cells$plot, cells$threshold)), "Duplicate scoring cell")
  out <- list()
  for (threshold in c(.5, .4)) {
    z <- cells[cells$threshold == threshold, ]; groups <- split(z, z$arm)
    workflow_require(setequal(names(groups), workflow_arms), "Missing paired arm")
    support <- lapply(groups, function(x) { x <- x[order(x$plot), ]; x[, c("plot", "support_key", "reference_revision")] })
    workflow_require(all(vapply(support, function(x) isTRUE(all.equal(unname(as.matrix(x)),
      unname(as.matrix(support[[1]])))), logical(1))), "Unequal paired plot support")
    for (arm in names(groups)) {
      x <- groups[[arm]]; tp <- sum(x$TP); fp <- sum(x$FP); fn <- sum(x$FN)
      out[[length(out) + 1L]] <- data.frame(arm = arm, threshold = threshold, plots = nrow(x),
        TP = tp, FP = fp, FN = fn, n_ref = sum(x$n_ref), n_prediction = sum(x$n_prediction),
        outside_predictions = sum(x$outside_predictions), workflow_rates(tp, fp, fn))
    }
  }
  do.call(rbind, out)
}
workflow_compare <- function(admission, bundle) {
  workflow_require(identical(admission$status, "admitted_historical_diagnostic"),
                   "Real comparison blocked before reference/prediction pair consumption")
  cells <- list(); pairs <- list(); outside <- list()
  for (arm in admission$state$arms) {
    p <- admission$state$predictions[[arm$arm]]$boxes
    for (threshold in c(.5, .4)) {
      score <- workflow_score(admission$state$review$reference, p, threshold, arm$status)
      row <- cbind(data.frame(plot = "TEAK_043", arm = arm$arm,
        support_key = digest::digest(workflow_json(bundle$manifest$support), algo = "sha256", serialize = FALSE),
        reference_revision = bundle$manifest$reference_revision), score$counts)
      cells[[length(cells) + 1L]] <- row
      if (nrow(score$matches)) pairs[[length(pairs) + 1L]] <- cbind(
        data.frame(arm = arm$arm, threshold = threshold), score$matches)
      if (length(score$outside_ids)) outside[[length(outside) + 1L]] <- data.frame(
        arm = arm$arm, threshold = threshold, prediction_id = score$outside_ids)
    }
  }
  cells <- do.call(rbind, cells)
  matches <- if (length(pairs)) do.call(rbind, pairs) else data.frame(arm = character(), threshold = numeric(),
    reference_id = character(), prediction_id = character(), iou = numeric())
  excluded <- if (length(outside)) do.call(rbind, outside) else data.frame(arm = character(), threshold = numeric(),
    prediction_id = character())
  dispositions <- do.call(rbind, lapply(names(admission$state$predictions), function(arm) {
    x <- admission$state$predictions[[arm]]$lineage
    cbind(arm = arm, x)
  }))
  list("adapter_dispositions.csv" = workflow_csv(dispositions),
    "comparison_cells.csv" = workflow_csv(cells), "pooled_counts.csv" = workflow_csv(workflow_pool(cells)),
    "matched_boxes.csv" = workflow_csv(matches), "outside_predictions.csv" = workflow_csv(excluded),
    "registration_residuals.csv" = workflow_csv(admission$state$registration),
    "reviewed_reference.csv" = workflow_csv(admission$state$review$reference))
}
workflow_emit <- function(out, products, inputs, code, mode, verify = FALSE) {
  hashes <- vapply(products, digest::digest, "", algo = "sha256", serialize = FALSE)
  outputs <- data.frame(path = names(products), bytes = lengths(products), sha256 = unname(hashes))
  receipt <- list(schema_version = 1L, plot = "TEAK_043", mode = mode, inputs = inputs, code = code,
    packages = setNames(lapply(c("terra", "sf", "png", "jsonlite", "clue", "digest"), function(p)
      as.character(packageVersion(p))), c("terra", "sf", "png", "jsonlite", "clue", "digest")),
    R_version = R.version.string, outputs = outputs, reserved_plots_processed = list())
  products[["receipt.json"]] <- workflow_json(receipt)
  if (verify) {
    workflow_require(setequal(list.files(out, all.files = TRUE, no.. = TRUE), names(products)), "Output inventory differs")
    for (name in names(products)) {
      p <- workflow_child(out, name)
      workflow_require(identical(readBin(p, "raw", n = file.info(p)$size), products[[name]]),
                       paste("Recomputed output differs", name))
    }
  } else {
    workflow_require(!file.exists(out), "Output must be fresh")
    workflow_require(dir.create(out, recursive = TRUE, showWarnings = FALSE), "Could not create output")
    for (name in names(products)) { con <- file(file.path(out, name), "wb"); writeBin(products[[name]], con); close(con) }
  }
  invisible(receipt)
}
workflow_source_inventory <- function(parents, arm) {
  relative <- paste0(arm, if (arm == "chm_vwf") "/raw_treetops.csv" else "/normalized_predictions.laz")
  hash <- parents$receipts$smoke$output_sha256[[relative]]
  workflow_require(workflow_sha(hash), "Missing frozen source output identity")
  root <- parents$roots$smoke
  if (arm == "chm_vwf") {
    p <- workflow_check(root, list(path = relative, sha256 = hash))
    raw <- workflow_table(p); ids <- as.character(raw$instance); policy_ids(ids, "frozen treetop IDs")
    rows <- data.frame(source_prediction_id = ids, source_membership_sha256 = vapply(ids, function(id)
      digest::digest(paste(hash, id, sep = ":"), algo = "sha256", serialize = FALSE), ""))
    proxies <- NULL
  } else {
    relative <- paste0(arm, "/diagnostics.json")
    p <- workflow_check(root, list(path = relative, sha256 = parents$receipts$smoke$output_sha256[[relative]]))
    proxy <- workflow_read(p)$point_extent_proxies
    workflow_require(length(proxy) > 0L, "Missing frozen instance inventory")
    rows <- data.frame(source_prediction_id = vapply(proxy, function(x) as.character(x$instance), ""),
      source_membership_sha256 = vapply(proxy, `[[`, "", "source_rows_sha256"))
    policy_ids(rows$source_prediction_id, "frozen instance IDs")
    proxies <- do.call(rbind, lapply(proxy, function(x) unlist(x$raw_pixel_box)))
    rownames(proxies) <- rows$source_prediction_id
  }
  list(rows = rows, proxies = proxies, source_sha256 = hash)
}
workflow_predictions <- function(bundle, arm, parents) {
  p <- workflow_table(workflow_artifact(bundle, arm$prediction_artifact))
  fields <- c("id", "source_prediction_id", "xmin", "ymin", "xmax", "ymax")
  workflow_require(all(fields %in% names(p)), "Prediction lacks source-instance lineage")
  if (!nrow(p)) p <- cbind(workflow_empty_boxes(), source_prediction_id = character())
  p$id <- as.character(p$id); p$source_prediction_id <- as.character(p$source_prediction_id)
  policy_ids(p$source_prediction_id, "source prediction IDs"); policy_box_geometry(p, p$id)
  workflow_require((arm$status == "completed_empty") == (nrow(p) == 0L), "Outcome/prediction count differs")
  adapter <- workflow_read(workflow_artifact(bundle, arm$adapter_artifact))
  source <- workflow_source_inventory(parents, arm$arm)
  lineage <- workflow_table(workflow_artifact(bundle, adapter$lineage_artifact))
  workflow_require(all(c("source_prediction_id", "source_membership_sha256", "status", "box_id",
    "exclusion_reason") %in% names(lineage)), "Missing complete source disposition schema")
  lineage$source_prediction_id <- as.character(lineage$source_prediction_id)
  policy_ids(lineage$source_prediction_id, "source disposition IDs")
  workflow_require(setequal(lineage$source_prediction_id, source$rows$source_prediction_id),
                   "Source instances omitted or invented")
  k <- match(lineage$source_prediction_id, source$rows$source_prediction_id)
  workflow_require(identical(lineage$source_membership_sha256, source$rows$source_membership_sha256[k]) &&
    all(lineage$status %in% c("boxed", "excluded")), "Source point membership/disposition differs")
  boxed <- lineage$status == "boxed"
  workflow_require(setequal(lineage$source_prediction_id[boxed], p$source_prediction_id) &&
    !anyDuplicated(lineage$box_id[boxed]) &&
    identical(as.character(lineage$box_id[boxed]), p$id[match(lineage$source_prediction_id[boxed], p$source_prediction_id)]),
    "Prediction/source crosswalk differs")
  workflow_require(all(vapply(as.list(lineage$exclusion_reason[!boxed]), workflow_text, logical(1))),
                   "Undocumented source-instance exclusion")
  vertices <- workflow_table(workflow_artifact(bundle, adapter$boundary_artifact))
  workflow_require(all(c("id", "vertex", "x", "y") %in% names(vertices)), "Missing crown boundary vertices")
  vertices$id <- as.character(vertices$id)
  workflow_require(setequal(vertices$id, p$id), "Boundary/prediction IDs differ")
  if (nrow(vertices)) workflow_require(all(vapply(vertices[c("vertex", "x", "y")], is.numeric, logical(1))) &&
    all(is.finite(as.matrix(vertices[c("vertex", "x", "y")]))), "Invalid boundary coordinates")
  for (i in seq_len(nrow(p))) {
    v <- vertices[vertices$id == p$id[i], ]; v <- v[order(v$vertex), ]
    workflow_require(nrow(v) >= 3L && identical(as.integer(v$vertex), seq_len(nrow(v))) &&
      all(v$vertex == floor(v$vertex)), "Invalid boundary vertex order")
    coords <- as.matrix(v[c("x", "y")]); ring <- rbind(coords, coords[1, ])
    polygon <- sf::st_sfc(sf::st_polygon(list(ring)))
    workflow_require(isTRUE(sf::st_is_valid(polygon)[1]) && as.numeric(sf::st_area(polygon)) > 0,
                     "Invalid/nonpositive crown boundary")
    expected <- c(min(v$x), min(v$y), max(v$x), max(v$y))
    actual <- as.numeric(p[i, c("xmin", "ymin", "xmax", "ymax")])
    workflow_require(max(abs(expected - actual)) <= 1e-8, "Boxes not derived from retained crown boundaries")
    if (!is.null(source$proxies)) workflow_require(
      max(abs(actual - source$proxies[p$source_prediction_id[i], ])) > 1e-8,
      "Unchanged sparse point extent cannot be relabelled as a crown box")
  }
  list(boxes = p, lineage = lineage)
}
workflow_output_path <- function(out, base, repo, roots, verify = FALSE) {
  out <- workflow_safe(out, exists = verify)
  protected <- c(roots, file.path(repo, c("scripts", "docs", "tests", "results", ".git", "gpu")))
  workflow_require(out != repo && !startsWith(repo, paste0(out, "/")) &&
    !any(vapply(protected, function(p) out == p || startsWith(out, paste0(p, "/")) ||
      startsWith(p, paste0(out, "/")), logical(1))) &&
    (!startsWith(out, paste0(repo, "/")) || startsWith(out, paste0(repo, "/work/"))) &&
    (verify || !file.exists(out)), "OUT must be fresh and separate from protected inputs/code")
  out
}
workflow_exit_status <- function(mode, status) if (mode == "compare" && status == "blocked") 2L else 0L
