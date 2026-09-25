# Frozen whole-plot FGI calibration; no changes to historical calibrators.
fgi_calibration_groups <- function() {
  groups <- fgi_summary_groups()
  groups[groups$target %in% c("apex_max_agl", "mask_iou_0.5"), ]
}

fgi_apex_labels <- function(pred, ref) {
  # Preserve audit_apex_match's distance/ref-row/pred-row tie order exactly.
  # Callers sort by instance ID, as the sealed external scorer does.
  candidates <- lapply(seq_len(nrow(ref)), function(i) {
    distance <- sqrt((pred$x - ref$x[i])^2 + (pred$y - ref$y[i])^2)
    j <- which(distance <= 4 & abs(pred$z - ref$z[i]) <= 5)
    data.frame(ref = rep(i, length(j)), pred = j, distance = distance[j])
  })
  edges <- data.table::rbindlist(candidates)
  used_ref <- logical(nrow(ref))
  matched <- rep(NA_integer_, nrow(pred))
  if (nrow(edges)) {
    data.table::setorder(edges, distance, ref, pred)
    for (k in seq_len(nrow(edges))) {
      i <- edges$ref[k]; j <- edges$pred[k]
      if (!used_ref[i] && is.na(matched[j])) {
        used_ref[i] <- TRUE
        matched[j] <- ref$instance[i]
      }
    }
  }
  data.frame(instance = pred$instance, raw_score = pred$confidence,
             label = as.integer(!is.na(matched)), matched_reference = matched)
}

fgi_mask_labels <- function(pred, ref, features, reference_ids) {
  valid_ids <- function(x) all(is.finite(x) & x >= 0 & x == floor(x))
  if (length(pred) != length(ref) || !valid_ids(pred) || !valid_ids(ref))
    stop("Invalid or misaligned full-row mask labels")
  if (!setequal(unique(pred[pred > 0]), features$instance) ||
      anyDuplicated(features$instance) ||
      !setequal(unique(ref[ref > 0]), reference_ids))
    stop("Mask IDs differ from the sealed apex/reference population")
  pred[pred == 0] <- NA_integer_; ref[ref == 0] <- NA_integer_
  matched <- iou_match(point_set_iou(pred, ref), gate = .5)
  ids <- matched$ref_id[match(features$instance, matched$pred_id)]
  data.frame(instance = features$instance, raw_score = features$confidence,
             label = as.integer(!is.na(ids)), matched_reference = ids)
}

fgi_fit_isotonic <- function(score, label) {
  if (length(score) != length(label) || any(!is.finite(score)) ||
      anyNA(label) || any(!label %in% 0:1)) stop("Invalid training scores or labels")
  knots <- data.frame(raw_score = numeric(), n = integer(), tp = integer(),
                      probability = numeric())
  reason <- if (!length(score)) "no_training_predictions" else
    if (length(unique(score)) < 2L) "fewer_than_two_scores" else
    if (length(unique(label)) < 2L) "single_class_training" else ""
  if (nzchar(reason)) return(list(state = "unavailable", reason = reason, knots = knots))
  scores <- sort(unique(score))
  index <- match(score, scores)
  counts <- tabulate(index, length(scores))
  tp <- tabulate(index[label == 1], length(scores))
  # Weighted PAVA on unique raw scores, after aggregating ties by TP and count.
  starts <- ends <- weights <- totals <- numeric(length(scores))
  blocks <- 0L
  for (i in seq_along(scores)) {
    blocks <- blocks + 1L
    starts[blocks] <- ends[blocks] <- i
    weights[blocks] <- counts[i]; totals[blocks] <- tp[i]
    while (blocks > 1L && totals[blocks - 1L] / weights[blocks - 1L] >
           totals[blocks] / weights[blocks]) {
      weights[blocks - 1L] <- weights[blocks - 1L] + weights[blocks]
      totals[blocks - 1L] <- totals[blocks - 1L] + totals[blocks]
      ends[blocks - 1L] <- ends[blocks]
      blocks <- blocks - 1L
    }
  }
  probability <- numeric(length(scores))
  for (b in seq_len(blocks))
    probability[starts[b]:ends[b]] <- totals[b] / weights[b]
  list(state = "fitted", reason = "", knots = data.frame(raw_score = scores,
    n = counts, tp = tp, probability = probability))
}

fgi_apply_isotonic <- function(fit, score) {
  if (any(!is.finite(score))) stop("Invalid validation scores")
  if (fit$state == "unavailable") return(rep(NA_real_, length(score)))
  # rule=1 leaves scores outside the training range uncalibrated.
  approx(fit$knots$raw_score, fit$knots$probability, xout = score,
         method = "linear", rule = 1, ties = "ordered")$y
}

fgi_calibration_metrics <- function(rows) {
  p <- rows$probability; label <- rows$label
  if (any(!is.na(p) & (!is.finite(p) | p < 0 | p > 1)) ||
      anyNA(label) || any(!label %in% 0:1)) stop("Invalid probabilities or labels")
  available <- !is.na(p)
  data.frame(n_pred = nrow(rows), calibrated = sum(available),
    unavailable = sum(!available), TP = sum(label),
    calibrated_TP = sum(label[available]), unavailable_TP = sum(label[!available]),
    calibration_coverage = if (length(p)) mean(available) else NA_real_,
    Brier = if (any(available)) mean((p[available] - label[available])^2) else NA_real_,
    ECE = expected_calibration_error(p[available], label[available], bins = 10))
}

fgi_validate_calibration_inputs <- function(labels, cells, folds) {
  groups <- fgi_calibration_groups()
  keys <- function(x) paste(x$plot, x$arm, x$target, sep = "/")
  expected <- merge(data.frame(plot = FGI_DEVELOPMENT_PLOTS), groups)
  if (nrow(cells) != 50L || anyDuplicated(keys(cells)) ||
      !setequal(keys(cells), keys(expected))) stop("Require all fifty calibration cells")
  if (nrow(folds) != 50L || anyDuplicated(keys(folds)) ||
      !setequal(keys(folds), keys(expected))) stop("Require all fifty declared folds")
  for (i in seq_len(nrow(folds))) {
    fold <- folds[i, ]
    train <- strsplit(fold$calibration_plots, ";", fixed = TRUE)[[1]]
    if (fold$fold != paste0("leave_", fold$plot, "_out") || length(train) != 9L ||
        anyDuplicated(train) || !setequal(train, setdiff(FGI_DEVELOPMENT_PLOTS, fold$plot)))
      stop("Training plots must be the exact nine whole-plot complement")
  }
  required <- c("plot", "arm", "target", "instance", "raw_score", "label")
  if (!all(required %in% names(labels)) || anyNA(labels[, required]) ||
      any(!is.finite(labels$raw_score)) || any(!labels$label %in% 0:1) ||
      any(!is.finite(labels$instance) | labels$instance <= 0 |
          labels$instance != floor(labels$instance)) ||
      anyDuplicated(paste(keys(labels), labels$instance)) ||
      any(!keys(labels) %in% keys(expected))) stop("Invalid per-prediction population")
  for (name in c("n_pred", "n_ref", "TP", "FP", "FN"))
    if (any(!is.finite(cells[[name]]) | cells[[name]] < 0 |
            cells[[name]] != floor(cells[[name]]))) stop("Invalid baseline counts")
  if (any(cells$TP + cells$FP != cells$n_pred | cells$TP + cells$FN != cells$n_ref))
    stop("Baseline count denominators disagree")
  for (plot in FGI_DEVELOPMENT_PLOTS)
    if (length(unique(cells$n_ref[cells$plot == plot])) != 1L)
      stop("Reference populations differ")
  for (i in seq_len(nrow(cells))) {
    selected <- keys(labels) == keys(cells[i, ])
    if (sum(selected) != cells$n_pred[i] || sum(labels$label[selected]) != cells$TP[i])
      stop("Prediction labels disagree with sealed baseline counts")
  }
  invisible(TRUE)
}

fgi_calibrate_complete <- function(labels, cells, folds, n_boot = 1000L) {
  fgi_validate_calibration_inputs(labels, cells, folds)
  predictions <- list(); status <- list(); knots <- list()
  empty_knots <- data.frame(fold = character(), plot = character(), arm = character(),
    target = character(), raw_score = numeric(), n = integer(), tp = integer(),
    probability = numeric())
  for (i in seq_len(nrow(folds))) {
    fold <- folds[i, ]
    group <- labels[labels$arm == fold$arm & labels$target == fold$target, , drop = FALSE]
    training <- group[group$plot != fold$plot, , drop = FALSE]
    validation <- group[group$plot == fold$plot, , drop = FALSE]
    fit <- fgi_fit_isotonic(training$raw_score, training$label)
    validation$fold <- rep(fold$fold, nrow(validation))
    validation$probability <- fgi_apply_isotonic(fit, validation$raw_score)
    validation$unavailable_reason <- ifelse(!is.na(validation$probability), "",
      if (fit$state == "unavailable") fit$reason else "outside_training_range")
    predictions[[i]] <- validation
    bounds <- if (nrow(training)) range(training$raw_score) else c(NA_real_, NA_real_)
    status[[i]] <- cbind(fold, data.frame(
      state = if (nrow(validation)) "successful_nonempty" else "successful_empty",
      fit_state = fit$state, fit_reason = fit$reason, training_predictions = nrow(training),
      training_TP = sum(training$label), training_FP = sum(training$label == 0),
      training_distinct_scores = length(unique(training$raw_score)),
      raw_min = bounds[1], raw_max = bounds[2]), fgi_calibration_metrics(validation))
    if (nrow(fit$knots)) knots[[i]] <- cbind(
      fold[rep(1L, nrow(fit$knots)), c("fold", "plot", "arm", "target")], fit$knots)
  }
  predictions <- do.call(rbind, predictions)
  groups <- fgi_calibration_groups()
  pooled <- bins <- intervals <- list()
  indices <- fgi_bootstrap_indices(n_boot)
  for (i in seq_len(nrow(groups))) {
    group <- groups[i, ]
    block <- predictions[predictions$arm == group$arm &
                         predictions$target == group$target, , drop = FALSE]
    baseline <- cells[cells$arm == group$arm & cells$target == group$target, ]
    metrics <- fgi_calibration_metrics(block)
    pooled[[i]] <- cbind(group, data.frame(n_cells = nrow(baseline),
      n_ref = sum(baseline$n_ref), FP = sum(baseline$FP), FN = sum(baseline$FN)), metrics)
    available <- block[!is.na(block$probability), , drop = FALSE]
    bins[[i]] <- cbind(group[rep(1L, 10L), ],
      reliability_table(available$probability, available$label, bins = 10))
    # Conditional uncertainty of the fixed out-of-fold predictions; no refits.
    samples <- lapply(seq_len(n_boot), function(b) {
      sampled <- do.call(rbind, lapply(FGI_DEVELOPMENT_PLOTS[indices[, b]],
        function(plot) block[block$plot == plot, , drop = FALSE]))
      fgi_calibration_metrics(sampled)
    })
    samples <- do.call(rbind, samples)
    for (metric in c("calibration_coverage", "Brier", "ECE"))
      intervals[[paste(i, metric)]] <- cbind(group,
        data.frame(metric = metric, estimate = metrics[[metric]]),
        fgi_interval(samples[[metric]]))
  }
  list(predictions = predictions, status = do.call(rbind, status),
    knots = if (length(knots)) do.call(rbind, knots) else empty_knots,
    pooled = do.call(rbind, pooled), reliability = do.call(rbind, bins),
    intervals = do.call(rbind, intervals), bootstrap_indices = t(indices))
}
