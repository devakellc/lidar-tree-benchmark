# FGI-EMIT adapters. Model inputs and the labelled scoring substrate are separate.
FGI_CLASSES <- c("A", "B", "C", "D")
FGI_TEST_PLOTS <- c("1002", "1004", "1008", "1012", "1018", "1028")

fgi_plots <- function(metadata, split = "test", plots = NULL) {
  if (!split %in% c("test", "training")) stop("SPLIT must be test or training")
  test <- vapply(metadata, function(x) isTRUE(x$test), logical(1))
  available <- names(metadata)[test == (split == "test")]
  if (split == "test" && !setequal(available, FGI_TEST_PLOTS))
    stop("Metadata does not match the published six-plot test split")
  if (is.null(plots)) return(sort(available))
  if (!length(plots) || anyDuplicated(plots) || !all(plots %in% available))
    stop("PLOTS must be unique members of the requested split")
  plots
}

fgi_reference_classes <- function(points, metadata) {
  required <- c("X", "Y", "Z", "Classification", "tree_index")
  if (!all(required %in% names(points))) stop("Missing FGI-EMIT annotation fields")
  if (any(!is.finite(as.matrix(points[, c("X", "Y", "Z"), drop = FALSE]))))
    stop("Non-finite reference coordinates")
  ids <- points$tree_index
  if (any(!is.finite(ids) | ids < 0 | ids != floor(ids)))
    stop("Reference tree_index must contain non-negative integer labels")
  if (any(is.na(points$Classification) | !points$Classification %in% 0:5))
    stop("Unknown FGI-EMIT semantic category")
  ids <- unique(ids[points$Classification != 5 & ids > 0])
  classes <- vapply(metadata$trees, function(x) as.character(x$c), character(1))
  if (!setequal(as.character(ids), names(classes)) ||
      any(!classes %in% FGI_CLASSES) || length(ids) != metadata$n_trees$all)
    stop("Reference instances and plot metadata disagree")
  for (cl in FGI_CLASSES)
    if (sum(classes == cl) != metadata$n_trees[[cl]])
      stop("Crown category counts and metadata disagree")
  classes
}

fgi_model_points <- function(points, classical = FALSE) {
  keep <- points$Classification != 5
  if (classical) keep <- keep & !points$Classification %in% 2:4
  out <- points[keep, c("X", "Y", "Z"), drop = FALSE]
  # FGI semantic class 2 is a building, never an ASPRS ground label.
  out$Classification <- 1L
  out$ReturnNumber <- 1L
  out$NumberOfReturns <- 1L
  out
}

fgi_transfer_labels <- function(source, query, tol = 0.5) {
  xyz <- c("X", "Y", "Z")
  if (!all(c(xyz, "crown_id") %in% names(source)) || !all(xyz %in% names(query)))
    stop("Label transfer requires XYZ and source crown_id")
  if (length(tol) != 1L || !is.finite(tol) || tol < 0)
    stop("Label transfer tolerance must be finite and non-negative")
  sx <- as.matrix(source[, xyz, drop = FALSE]); qx <- as.matrix(query[, xyz, drop = FALSE])
  if (any(!is.finite(sx)) || any(!is.finite(qx))) stop("Non-finite prediction coordinates")
  ids <- source$crown_id
  if (any(!is.na(ids) & (!is.finite(ids) | ids < 0 | ids != floor(ids))))
    stop("Invalid predicted instance labels")
  out <- rep(NA_integer_, nrow(query)); distance <- rep(Inf, nrow(query))
  if (nrow(source) && nrow(query)) {
    # Include unassigned source points: dropping them would expand nearby crowns.
    nn <- dbscan::kNN(sx, k = 1L, query = qx)
    distance <- as.numeric(nn$dist)
    ok <- distance <= tol
    out[ok] <- ids[as.integer(nn$id)[ok]]
    out[!is.na(out) & out == 0] <- NA_integer_
  }
  list(labels = out, distance = distance)
}

fgi_aligned_labels <- function(source, query, tol = 0.001) {
  xyz <- c("X", "Y", "Z")
  if (!all(c(xyz, "crown_id") %in% names(source)) || !all(xyz %in% names(query)) ||
      nrow(source) != nrow(query)) stop("Aligned labels require every input row")
  delta <- as.matrix(source[, xyz, drop = FALSE]) - as.matrix(query[, xyz, drop = FALSE])
  distance <- sqrt(rowSums(delta^2))
  if (any(!is.finite(distance) | distance > tol))
    stop("Aligned output changed point order or coordinates")
  ids <- source$crown_id
  if (any(!is.na(ids) & (!is.finite(ids) | ids < 0 | ids != floor(ids))))
    stop("Invalid aligned instance labels")
  ids[!is.na(ids) & ids == 0] <- NA_integer_
  list(labels = ids, distance = distance)
}

fgi_indexed_labels <- function(source, query, tol = 0.001) {
  rows <- source$ff3d_row
  if (is.null(rows) || length(rows) != nrow(query) || anyNA(rows) ||
      any(!is.finite(rows) | rows < 0 | rows != floor(rows)) || anyDuplicated(rows) ||
      !identical(sort(as.numeric(rows)), as.numeric(seq_len(nrow(query)) - 1L)))
    stop("Whole-scene output requires unique complete source row IDs")
  fgi_aligned_labels(source[order(rows), , drop = FALSE], query, tol)
}

fgi_filter_predictions <- function(pred, z, min_points = 40L, min_height = 1.5) {
  if (length(pred) != length(z) || any(!is.finite(z))) stop("Invalid scoring substrate")
  pred[pred == 0 & !is.na(pred)] <- NA_integer_
  if (all(is.na(pred))) return(pred)
  d <- data.table::data.table(id = pred, z = z)
  size <- d[!is.na(id), .(n = .N, height = max(z) - min(z)), by = id]
  keep <- size$id[size$n >= min_points & size$height >= min_height]
  pred[!pred %in% keep] <- NA_integer_
  pred
}

fgi_score <- function(pred, points, classes) {
  if (length(pred) != nrow(points)) stop("Predictions must cover the reference substrate")
  keep <- points$Classification != 5
  pred <- fgi_filter_predictions(pred[keep], points$Z[keep])
  ref <- points$tree_index[keep]; ref[ref == 0] <- NA_integer_
  score <- score_instance_cell(pred, ref, classes, classes = FGI_CLASSES)
  if (score$n_pred == 0L) score$precision <- 0
  # The common pooler leaves undefined F1 at zero TP; the external protocol uses 0.
  score$F1 <- if (score$n_pred + score$n_ref > 0)
    2 * score$TP / (score$n_pred + score$n_ref) else NA_real_
  list(score = score, pred = pred, keep = keep)
}

fgi_summary <- function(scores, arms) {
  if (!nrow(scores)) return(data.frame())
  if (anyDuplicated(paste(scores$plot, scores$arm))) stop("Duplicate plot/arm scores")
  common <- Reduce(intersect, lapply(arms, function(a) scores$plot[scores$arm == a]))
  rows <- lapply(arms, function(arm) {
    s <- scores[scores$arm == arm & scores$plot %in% common, , drop = FALSE]
    if (!nrow(s)) return(NULL)
    p <- pool_pq(s, classes = FGI_CLASSES)
    if (p$n_pred == 0L) p$precision <- 0
    p <- p[, !grepl("understory", names(p)), drop = FALSE]
    p$F1 <- if (p$n_pred + p$n_ref > 0) 2 * p$TP / (p$n_pred + p$n_ref) else NA_real_
    cbind(data.frame(arm = arm, plots = paste(sort(common), collapse = ",")), p)
  })
  do.call(rbind, rows)
}

fgi_manifest <- function(path, expected) {
  if (!file.exists(path)) return(FALSE)
  old <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!identical(old, expected)) stop("Cache provenance differs: ", path,
                                     "; use a new OUT_DIR")
  TRUE
}
