# Metadata policy and synthetic-only box contract. No real evaluation entry point.
policy_ids <- function(ids, label = "IDs") {
  if (!is.character(ids) || anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids))
    stop("Invalid or duplicate ", label)
}

policy_validate <- function(p) {
  # These declarations describe fixed implemented behavior, not free-form
  # annotations. A changed policy needs an explicit implementation revision.
  semantics <- list(
    target = "reviewed visible canopy 2D boxes in full published image",
    group_rule = paste("closed context rectangles intersect; transitive components;",
                       "lexicographic minimum plot ID"),
    historical_group_rule = "any historical-use member demotes whole group to development",
    support = "full 40 m by 40 m image",
    coordinate_frame = paste("zero-origin pixel edges with top-left origin;",
                             "affine mapped to EPSG:32611"),
    edge_policy = paste("clip prediction boxes to image; include every positive-area",
                       "intersection; no ignore regions or automatic reference exclusions"),
    outside_predictions = "count separately; zero-area image intersections are outside",
    invalid_predictions = "nonfinite or nonpositive area before clipping is an error",
    admission = paste("all human box, completeness, ambiguity, timing, coregistration,",
      "native-input and checkpoint-exposure reviews remain open; no real scorer"))
  if (!all(vapply(names(semantics), function(field)
      identical(p[[field]], semantics[[field]]), logical(1))) ||
      !identical(p$matching$tie_rule, "stable sorted IDs and pinned clue solver") ||
      !identical(p$checkpoint_hashes, list(
        forestformer3d = "01037a648596832238ac72ea2f5eef87ceaf5aeb399e56ff4b760ba1ed1c777e",
        segmentanytree = "0b4d74b4644e37a16f59008ad0f5c62894fc4d2d906f3abd803bbfc5b5dd803a")))
    stop("Unsupported policy semantic declaration")
  historical <- paste0("TEAK_", c("043", "044", "045", "046", "047", "050", "052"))
  candidates <- paste0("TEAK_", c("049", "051", "053", "054", "055", "057", "058",
                                  "059", "060", "061", "062"))
  if (!identical(p$schema_version, 1L) ||
      !identical(p$policy_id, "teak-visible-canopy-box-v1") ||
      !identical(p$evaluation_ready, FALSE) || !identical(p$real_scores, FALSE) ||
      !identical(p$independence_claim_supported, FALSE) ||
      !identical(p$checkpoint_exposure, "unknown") ||
      !identical(p$package_receipt_sha256,
        "79d71e4685e5c68947483fa880589ae6dbcfc1ef413f4175b945ddb6c6f9a079") ||
      !identical(p$pilot_receipt_sha256,
        "ac1e50570d2b383e517ccd3c49ca7ae543068ffd6e88ad06b5339fe971c066af") ||
      !identical(p$context_buffer_m, 25L) || !identical(p$epsg, 32611L) ||
      !identical(p$diagnostic_context_gaps_m, c(100L, 200L)) ||
      !identical(p$matching$primary_iou, 0.5) || !identical(p$matching$sensitivity_iou, 0.4) ||
      !identical(p$matching$gate, "inclusive") ||
      !identical(p$matching$objective, "maximum cardinality then maximum sum IoU") ||
      !identical(p$matching$clue_version, "0.3.68"))
    stop("Unsupported policy schema/settings/admission declaration")
  if (!is.data.frame(p$plots) || !all(c("plotID", "spatial_group", "role",
                                      "evaluation_ready") %in% names(p$plots)) ||
      anyNA(p$plots)) stop("Invalid policy plots")
  policy_ids(p$plots$plotID, "policy plot IDs")
  if (nrow(p$plots) != 18L || !setequal(p$plots$plotID, c(historical, candidates)) ||
      any(p$plots$evaluation_ready) ||
      any(p$plots$role != ifelse(p$plots$plotID %in% historical,
                                 "development", "reserved_unadmitted")) ||
      any(p$plots$spatial_group != ifelse(p$plots$plotID == "TEAK_060", "TEAK_049",
                                          p$plots$plotID))) stop("Invalid policy roles/groups")
  invisible(p)
}

policy_verify_outputs <- function(root, receipt_hash) {
  path <- file.path(root, "receipt.json")
  if (!file.exists(path) || canopy_hash(path) != receipt_hash)
    stop("Receipt hash mismatch")
  r <- jsonlite::fromJSON(path)
  if (!identical(r$schema_version, 1L) || !identical(r$evaluation_ready, FALSE))
    stop("Invalid receipt schema/readiness")
  d <- r$outputs
  if (!is.data.frame(d) || !all(c("path", "bytes", "sha256") %in% names(d)) ||
      !nrow(d) || anyNA(d) || any(!is.finite(d$bytes) | d$bytes < 0) ||
      any(!grepl("^[0-9a-f]{64}$", d$sha256))) stop("Invalid output manifest")
  canopy_check_paths(d$path)
  p <- file.path(root, d$path)
  if (any(!file.exists(p)) || any(file.info(p)$isdir)) stop("Missing output file")
  resolved <- normalizePath(p, mustWork = TRUE)
  if (any(!startsWith(resolved, paste0(normalizePath(root), "/"))) ||
      anyDuplicated(resolved)) stop("Output path escapes/aliases package")
  if (any(file.info(p)$size != d$bytes) || !identical(canopy_hash(p), d$sha256))
    stop("Output hash/size mismatch")
  r
}

policy_rectangles <- function(x) {
  needed <- c("plotID", "rgb_epsg", "rgb_xmin", "rgb_xmax", "rgb_ymin", "rgb_ymax")
  if (!all(needed %in% names(x)) || !nrow(x)) stop("Missing rectangle metadata")
  policy_ids(x$plotID, "plot IDs")
  z <- as.matrix(x[, needed[-c(1, 2)]])
  if (!is.numeric(z) || any(!is.finite(z)) || anyNA(x$rgb_epsg) ||
      any(x$rgb_epsg != 32611) ||
      any(abs(x$rgb_xmax - x$rgb_xmin - 40) > 1e-7) ||
      any(abs(x$rgb_ymax - x$rgb_ymin - 40) > 1e-7))
    stop("Expected finite 40 m square cores in EPSG:32611")
}

policy_spatial_pairs <- function(x, buffer = 25) {
  policy_rectangles(x)
  if (length(buffer) != 1L || !is.finite(buffer) || buffer < 0)
    stop("Invalid context buffer")
  x <- x[order(x$plotID), ]
  rows <- list()
  if (nrow(x) < 2L) return(data.frame(plot_a = character(), plot_b = character(),
    core_gap_m = numeric(), context_gap_m = numeric(), context_intersects = logical(),
    context_overlap_x_m = numeric(), context_overlap_y_m = numeric()))
  for (i in seq_len(nrow(x) - 1L)) for (j in seq.int(i + 1L, nrow(x))) {
    dx <- max(x$rgb_xmin[i], x$rgb_xmin[j]) - min(x$rgb_xmax[i], x$rgb_xmax[j])
    dy <- max(x$rgb_ymin[i], x$rgb_ymin[j]) - min(x$rgb_ymax[i], x$rgb_ymax[j])
    rows[[length(rows) + 1L]] <- data.frame(plot_a = x$plotID[i], plot_b = x$plotID[j],
      core_gap_m = sqrt(max(0, dx)^2 + max(0, dy)^2),
      context_gap_m = sqrt(max(0, dx - 2 * buffer)^2 + max(0, dy - 2 * buffer)^2),
      context_intersects = dx <= 2 * buffer && dy <= 2 * buffer,
      context_overlap_x_m = max(0, 2 * buffer - dx),
      context_overlap_y_m = max(0, 2 * buffer - dy))
  }
  do.call(rbind, rows)
}

policy_groups <- function(x, pairs, gap = 0) {
  policy_ids(x$plotID, "plot IDs")
  if (length(gap) != 1L || !is.finite(gap) || gap < 0 ||
      anyNA(x$local_use) || any(!x$local_use %in%
        c("historical_use", "no_use_in_pinned_local_inventory")))
    stop("Invalid group policy/local use")
  ids <- sort(x$plotID); group <- setNames(ids, ids)
  links <- pairs[pairs$context_gap_m <= gap, , drop = FALSE]
  for (i in seq_len(nrow(links))) {
    a <- links$plot_a[i]; b <- links$plot_b[i]
    if (!all(c(a, b) %in% ids)) stop("Unknown pair plot")
    old <- group[c(a, b)]; group[group %in% old] <- min(old)
  }
  historical <- x$plotID[x$local_use == "historical_use"]
  data.frame(plotID = ids, spatial_group = unname(group),
    role = ifelse(group %in% group[historical], "development", "reserved_unadmitted"),
    evaluation_ready = FALSE, independent_holdout_claim_supported = FALSE)
}

policy_box_geometry <- function(b, ids) {
  policy_ids(ids, "box IDs")
  fields <- c("xmin", "ymin", "xmax", "ymax")
  if (!all(fields %in% names(b)) || nrow(b) != length(ids)) stop("Missing box geometry")
  z <- as.matrix(b[, fields, drop = FALSE])
  if (!all(vapply(b[, fields, drop = FALSE], is.numeric, logical(1))) ||
      any(!is.finite(z)) ||
      any(b$xmin >= b$xmax | b$ymin >= b$ymax)) stop("Invalid box geometry")
}

policy_iou <- function(a, b) {
  policy_box_geometry(a, as.character(seq_len(nrow(a))))
  policy_box_geometry(b, as.character(seq_len(nrow(b))))
  result <- matrix(0, nrow(a), nrow(b))
  for (i in seq_len(nrow(a))) for (j in seq_len(nrow(b))) {
    intersection <- max(0, min(a$xmax[i], b$xmax[j]) - max(a$xmin[i], b$xmin[j])) *
      max(0, min(a$ymax[i], b$ymax[j]) - max(a$ymin[i], b$ymin[j]))
    union <- (a$xmax[i] - a$xmin[i]) * (a$ymax[i] - a$ymin[i]) +
      (b$xmax[j] - b$xmin[j]) * (b$ymax[j] - b$ymin[j]) - intersection
    result[i, j] <- intersection / union
  }
  result
}

policy_clip_predictions <- function(b, width, height) {
  policy_box_geometry(b, b$id)
  if (length(width) != 1L || length(height) != 1L ||
      any(!is.finite(c(width, height))) || min(width, height) <= 0)
    stop("Invalid image dimensions")
  z <- b
  z$xmin <- pmax(0, z$xmin); z$ymin <- pmax(0, z$ymin)
  z$xmax <- pmin(width, z$xmax); z$ymax <- pmin(height, z$ymax)
  inside <- z$xmin < z$xmax & z$ymin < z$ymax
  list(boxes = z[inside, , drop = FALSE], outside_ids = b$id[!inside])
}

# Input sorting makes the installed clue solver's tie resolution repeatable.
# The cardinality bonus exceeds every possible summed-IoU difference.
policy_match_synthetic <- function(iou, reference_ids, prediction_ids, threshold = 0.5) {
  policy_ids(reference_ids); policy_ids(prediction_ids)
  if (!is.matrix(iou) || !is.numeric(iou) ||
      !identical(dim(iou), c(length(reference_ids), length(prediction_ids))) ||
      any(!is.finite(iou)) || any(iou < 0 | iou > 1) ||
      length(threshold) != 1L || !is.finite(threshold) || !threshold %in% c(0.5, 0.4))
    stop("Invalid synthetic IoU contract")
  result <- data.frame(reference_id = character(), prediction_id = character(), iou = numeric())
  if (!length(reference_ids) || !length(prediction_ids)) return(result)
  ro <- order(reference_ids, method = "radix"); co <- order(prediction_ids, method = "radix")
  m <- iou[ro, co, drop = FALSE]; nr <- nrow(m); nc <- ncol(m)
  weights <- matrix(0, nr, nc + nr)
  weights[, seq_len(nc)] <- ifelse(m >= threshold, min(nr, nc) + 1 + m, 0)
  assigned <- as.integer(clue::solve_LSAP(weights, maximum = TRUE))
  rows <- which(assigned <= nc)
  rows <- rows[m[cbind(rows, assigned[rows])] >= threshold]
  data.frame(reference_id = reference_ids[ro[rows]],
    prediction_id = prediction_ids[co[assigned[rows]]],
    iou = m[cbind(rows, assigned[rows])])
}

policy_score_synthetic <- function(reference, prediction, width = 400, height = 400,
                                   threshold = 0.5, status = "completed") {
  if (!status %in% c("completed", "completed_empty", "missing", "failed", "not_run") ||
      length(status) != 1L) stop("Invalid synthetic status")
  policy_box_geometry(reference, reference$id)
  if (any(reference$xmin < 0 | reference$ymin < 0 |
          reference$xmax > width | reference$ymax > height)) stop("Reference outside image")
  if (!status %in% c("completed", "completed_empty")) {
    if (!is.null(prediction)) stop("Unavailable predictions must be NULL")
    return(data.frame(status = status, TP = NA_integer_, FP = NA_integer_, FN = NA_integer_,
      outside_predictions = NA_integer_, synthetic = TRUE, real_scores = FALSE,
      evaluation_ready = FALSE))
  }
  if (status == "completed_empty" && nrow(prediction) != 0L)
    stop("completed_empty has predictions")
  clipped <- policy_clip_predictions(prediction, width, height)
  matches <- policy_match_synthetic(policy_iou(reference, clipped$boxes),
    reference$id, clipped$boxes$id, threshold)
  data.frame(status = status, TP = nrow(matches), FP = nrow(clipped$boxes) - nrow(matches),
    FN = nrow(reference) - nrow(matches), outside_predictions = length(clipped$outside_ids),
    synthetic = TRUE, real_scores = FALSE, evaluation_ready = FALSE)
}

policy_audit_boxes <- function(boxes, inventory) {
  keys <- paste(boxes$image_id, boxes$object_index, sep = ":")
  policy_box_geometry(boxes, keys)
  k <- match(boxes$plotID, inventory$plotID)
  if (anyNA(k) || anyNA(boxes$object_index) ||
      any(boxes$object_index != floor(boxes$object_index) | boxes$object_index < 1) ||
      any(boxes$image_id != inventory$image_id[k]) || anyNA(boxes$evaluation_ready) ||
      any(boxes$evaluation_ready) || any(boxes$local_use != inventory$local_use[k]))
    stop("Box identity/readiness disagrees with inventory")
  w <- (inventory$rgb_xmax - inventory$rgb_xmin) / inventory$rgb_resolution_m
  h <- (inventory$rgb_ymax - inventory$rgb_ymin) / inventory$rgb_resolution_m
  if (any(!is.finite(c(w, h))) || any(abs(c(w, h) - 400) > 1e-6))
    stop("Expected 400 by 400 image dimensions from metadata")
  if (any(boxes$xmin < 0 | boxes$ymin < 0 | boxes$xmax > w[k] | boxes$ymax > h[k]))
    stop("Reference outside image")
  boxes$box_key <- keys
  boxes$image_width_px <- w[k]; boxes$image_height_px <- h[k]
  boxes$min_edge_px <- pmin(boxes$xmin, boxes$ymin, w[k] - boxes$xmax, h[k] - boxes$ymax)
  boxes$min_edge_m <- boxes$min_edge_px * inventory$rgb_resolution_m[k]
  boxes$literal_boundary <- boxes$min_edge_px <= 0
  boxes$within_1px <- boxes$min_edge_px <= 1
  boxes$within_2m <- boxes$min_edge_m <= 2
  boxes$duplicate_geometry <- FALSE; boxes$overlap_other_box <- FALSE
  for (id in inventory$plotID) {
    rows <- which(boxes$plotID == id)
    if (length(rows) != inventory$n_boxes[inventory$plotID == id] ||
        !identical(sort(boxes$object_index[rows]), seq_along(rows)))
      stop("Box counts/object indexes disagree with inventory")
    z <- boxes[rows, c("xmin", "ymin", "xmax", "ymax")]
    boxes$duplicate_geometry[rows] <- duplicated(z) | duplicated(z, fromLast = TRUE)
    overlap <- policy_iou(z, z); diag(overlap) <- 0
    boxes$overlap_other_box[rows] <- rowSums(overlap > 0) > 0
  }
  boxes$human_status <- "pending"; boxes$human_reason <- NA_character_
  boxes$review_scope <- "published visible-canopy 2D box; no apex or 3D judgment"
  boxes
}
