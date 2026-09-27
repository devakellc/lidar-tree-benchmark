# Real, verified FGI assembly. All fusion settings are development diagnostics.
fgi_pipeline_candidates <- function(stage) {
  baseline <- c("chm_vwf", "segmentanytree", "forestformer3d")
  if (stage == "reserve") return(baseline)
  if (stage != "development") stop("Unknown pipeline stage")
  c(baseline, "union_all", "consensus_2of3", "union_point", "consensus_point", "weighted_all")
}

fgi_pipeline_fuse <- function(pred, method) {
  if (method %in% c("chm_vwf", "segmentanytree", "forestformer3d"))
    return(pred[pred$arm == method, c("instance", "x", "y", "z"), drop = FALSE])
  members <- if (method %in% c("union_point", "consensus_point"))
    c("segmentanytree", "forestformer3d") else c("chm_vwf", "segmentanytree", "forestformer3d")
  pred <- pred[pred$arm %in% members, , drop = FALSE]
  weighted <- method == "weighted_all"
  if (weighted && any(!is.finite(pred$probability))) stop("Unsupported calibration scores")
  f <- fuse_apexes(pred$arm, pred$x, pred$y, pred$z, merge_tol = 2, z_tol = 5,
                  weights = if (weighted) pred$probability else NULL)
  if (method %in% c("consensus_2of3", "consensus_point")) f <- f[f$votes >= 2L, , drop = FALSE]
  if (weighted) f <- f[f$weight >= 1, , drop = FALSE]
  f$instance <- seq_len(nrow(f))
  f[, c("instance", "x", "y", "z"), drop = FALSE]
}

fgi_pipeline_calibration <- function(pred, cal, cells) {
  pred$probability <- rep(NA_real_, nrow(pred))
  pred$calibration_status <- rep("not_requested", nrow(pred))
  if (is.null(cal)) return(pred)
  cal <- cal[cal$target == "apex_max_agl", , drop = FALSE]
  key <- function(x) paste(x$plot, x$arm, x$instance, sep = "/")
  if (anyDuplicated(key(pred)) || anyDuplicated(key(cal)) || !setequal(key(pred), key(cal)))
    stop("Calibration must cover the exact apex population")
  cal <- cal[match(key(pred), key(cal)), , drop = FALSE]
  if (any(cal$fold != paste0("leave_", cal$plot, "_out")) ||
      any(!is.finite(cal$raw_score)) || any(abs(cal$raw_score - pred$confidence) > 1e-10) ||
      any(!is.na(cal$probability) & (!is.finite(cal$probability) | cal$probability < 0 | cal$probability > 1)))
    stop("Incompatible whole-plot calibration or raw-score identity")
  pred$probability <- cal$probability
  pred$calibration_status <- ifelse(is.finite(cal$probability), "available", "outside_score_support")
  # No native-density transfer beyond the other nine plots' observed ranges.
  for (plot in unique(cells$plot)) {
    row <- cells[cells$plot == plot, ][1, ]
    train <- cells[cells$plot != plot, ]
    if (any(vapply(c("frdens", "pdens"), function(k)
      row[[k]] < min(train[[k]]) || row[[k]] > max(train[[k]]), logical(1)))) {
      pred$probability[pred$plot == plot] <- NA_real_
      pred$calibration_status[pred$plot == plot] <- "outside_density_support"
    }
  }
  pred
}

fgi_pipeline_analyze <- function(cells, pred, ref, stage, calibration = NULL, fit_status = NULL) {
  arms <- c("chm_vwf", "segmentanytree", "forestformer3d")
  plots <- if (stage == "reserve") c("1003", "1010", "1023") else FGI_DEVELOPMENT_PLOTS
  expected <- expand.grid(plot = plots, arm = arms, stringsAsFactors = FALSE)
  key <- function(x) paste(x$plot, x$arm, sep = "/")
  if (nrow(cells) != nrow(expected) || anyDuplicated(key(cells)) ||
      !setequal(key(cells), key(expected))) stop("Incomplete or foreign pipeline matrix")
  if (any(!cells$state %in% c("successful_empty", "successful_nonempty", "failed", "planned")))
    stop("Unknown pipeline cell state")
  if (stage == "reserve" && !is.null(calibration)) stop("Reserve calibration is not admitted")
  complete <- all(cells$state %in% c("successful_empty", "successful_nonempty"))
  empty <- data.frame()
  if (!complete) return(list(status = cells, products = empty, pooled = empty,
                            detections = empty, calibration = empty, complete = FALSE))
  if (any(!is.finite(cells$frdens) | !is.finite(cells$pdens) | cells$frdens <= 0 |
          cells$pdens < cells$frdens)) stop("Invalid measured density")
  if (any(!key(pred) %in% key(cells)) || any(!as.character(ref$plot) %in% plots) ||
      anyDuplicated(paste(ref$plot, ref$instance)) ||
      any(!ref$category %in% LETTERS[1:4])) stop("Invalid reference or prediction scope")
  for (i in seq_len(nrow(cells))) {
    c <- cells[i, ]; p <- pred[key(pred) == key(c), , drop = FALSE]
    r <- ref[ref$plot == c$plot, , drop = FALSE]
    if (nrow(p) != c$predictions || nrow(r) != c$reference_count ||
        anyDuplicated(p$instance) || any(!is.finite(as.matrix(p[, c("x", "y", "z", "confidence")]))))
      stop("Pipeline support differs from accepted detector output")
  }
  pred <- fgi_pipeline_calibration(pred, calibration, cells)
  if (!is.null(fit_status)) {
    fit_status <- fit_status[fit_status$target == "apex_max_agl", , drop=FALSE]
    if (anyDuplicated(key(fit_status)) || !setequal(key(fit_status), key(cells)) ||
        any(fit_status$fold != paste0("leave_", fit_status$plot, "_out")))
      stop("Calibration fit receipts do not match complete whole-plot support")
  }
  products <- detections <- list()
  for (plot in plots) {
    p <- pred[as.character(pred$plot) == plot, , drop = FALSE]
    p <- p[order(match(p$arm, arms), p$instance), , drop = FALSE]
    r <- ref[as.character(ref$plot) == plot, , drop = FALSE]
    r <- r[order(r$instance), , drop = FALSE]
    for (method in fgi_pipeline_candidates(stage)) {
      train <- cells[as.character(cells$plot) != plot, , drop=FALSE]
      cell <- cells[as.character(cells$plot) == plot, , drop=FALSE]
      density_supported <- nrow(train) > 0 && all(vapply(c("frdens", "pdens"), function(k)
        cell[[k]][1] >= min(train[[k]]) && cell[[k]][1] <= max(train[[k]]), logical(1)))
      fitted <- !is.null(fit_status) && all(fit_status$fit_state[as.character(fit_status$plot) == plot] == "fitted")
      blocked <- method == "weighted_all" &&
        (!fitted || !density_supported || any(!is.finite(p$probability)))
      if (blocked) {
        products[[length(products) + 1L]] <- data.frame(plot = plot, product = method,
          state = "blocked", reason = "unsupported_score_or_density_calibration", n_pred = NA_integer_,
          n_ref = nrow(r), TP = NA_integer_, FP = NA_integer_, FN = NA_integer_,
          precision = NA_real_, recall = NA_real_, F1 = NA_real_)
        next
      }
      f <- fgi_pipeline_fuse(p, method)
      metrics <- audit_apex_match(f, r)
      products[[length(products) + 1L]] <- data.frame(plot = plot, product = method,
        state = if (nrow(f)) "completed" else "completed_empty", reason = "", n_pred = nrow(f),
        n_ref = nrow(r), TP = metrics$apex_TP, FP = metrics$apex_FP, FN = metrics$apex_FN,
        precision = if (nrow(f)) metrics$apex_TP / nrow(f) else NA_real_,
        recall = metrics$apex_TP / nrow(r), F1 = 2 * metrics$apex_TP / (nrow(f) + nrow(r)))
      if (nrow(f)) detections[[length(detections) + 1L]] <- data.frame(plot = plot, product = method, f)
    }
  }
  products <- do.call(rbind, products)
  pooled <- lapply(fgi_pipeline_candidates(stage), function(method) {
    p <- products[products$product == method, ]
    admitted <- nrow(p) == length(plots) && all(p$state %in% c("completed", "completed_empty"))
    counts <- if (admitted) colSums(p[, c("n_pred", "n_ref", "TP", "FP", "FN")]) else
      setNames(rep(NA_real_, 5), c("n_pred", "n_ref", "TP", "FP", "FN"))
    data.frame(product = method, complete = admitted, declared_plots = length(plots),
      completed_plots = sum(p$state %in% c("completed", "completed_empty")),
      as.list(counts), precision = if (is.finite(counts["n_pred"]) && counts["n_pred"] > 0)
        counts["TP"] / counts["n_pred"] else NA_real_,
      recall = counts["TP"] / counts["n_ref"], F1 = 2 * counts["TP"] / (counts["n_pred"] + counts["n_ref"]))
  })
  list(status = cells, products = products, pooled = do.call(rbind, pooled),
       detections = if (length(detections)) do.call(rbind, detections) else
         data.frame(plot=character(), product=character(), instance=integer(), x=numeric(), y=numeric(), z=numeric()),
       calibration = pred, complete = TRUE)
}
