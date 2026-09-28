# Count-based summaries on complete, paired whole-plot development support.
FGI_DEVELOPMENT_PLOTS <- c("1001", "1005", "1009", "1013", "1019", "1020",
                         "1022", "1024", "1027", "1031")

fgi_summary_groups <- function() {
  arms <- c("chm_vwf", "segmentanytree", "forestformer3d")
  rbind(data.frame(target = "apex_max_agl", arm = arms),
        data.frame(target = "apex_isolated_top_agl", arm = arms[-1]),
        data.frame(target = "apex_historical_raw", arm = arms[-1]),
        data.frame(target = "mask_iou_0.5", arm = arms[-1]))
}

fgi_pool_counts <- function(rows) {
  stopifnot(length(unique(rows$target)) == 1L)
  fields <- c("n_cells", "n_pred", "n_ref", "TP", "FP", "FN", "precision",
              "recall", "F1", "sum_iou", "sum_maxiou", "coverage", "SQ", "PQ",
              paste0("n_", LETTERS[1:4]), paste0("tp_", LETTERS[1:4]),
              paste0("rec_", LETTERS[1:4]))
  if (rows$target[1] == "mask_iou_0.5") {
    # Reuse the benchmark's accumulator pooling and zero-denominator rules.
    pooled <- pool_pq(rows, classes = LETTERS[1:4])
    for (category in LETTERS[1:4])
      pooled[[paste0("tp_", category)]] <- sum(rows[[paste0("tp_", category)]])
    return(pooled[, fields, drop = FALSE])
  }
  sums <- vapply(c("n_pred", "n_ref", "TP", "FP", "FN"),
                 function(k) sum(rows[[k]]), numeric(1))
  result <- as.list(setNames(rep(NA_real_, length(fields)), fields))
  result[c("n_pred", "n_ref", "TP", "FP", "FN")] <- as.list(sums)
  result$n_cells <- nrow(rows)
  result$precision <- if (sums["n_pred"] > 0) sums["TP"] / sums["n_pred"] else NA_real_
  result$recall <- if (sums["n_ref"] > 0) sums["TP"] / sums["n_ref"] else NA_real_
  denom <- sums["n_pred"] + sums["n_ref"]
  result$F1 <- if (denom > 0) 2 * sums["TP"] / denom else 0
  as.data.frame(result)
}

fgi_validate_summary_rows <- function(rows) {
  required <- c("plot", "target", "arm", "TP", "FP", "FN", "n_pred", "n_ref",
                "sum_iou", "sum_maxiou", as.vector(outer(
                  c("n_", "tp_", "fn_", "sumiou_", "sumcov_"), LETTERS[1:4], paste0)))
  if (!all(required %in% names(rows)) || anyNA(rows[, c("plot", "target", "arm")]))
    stop("Missing summary fields")
  groups <- fgi_summary_groups()
  expected <- paste(groups$target, groups$arm, sep = "/")
  actual <- paste(rows$target, rows$arm, sep = "/")
  if (nrow(rows) != 90L || !setequal(unique(actual), expected))
    stop("Primary pooling requires all nine target/arm groups and all ten plots")
  for (group in expected) {
    plots <- as.character(rows$plot[actual == group])
    if (length(plots) != 10L || anyDuplicated(plots) ||
        !setequal(plots, FGI_DEVELOPMENT_PLOTS))
      stop("Missing, duplicated or foreign plot support")
  }
  for (field in c("TP", "FP", "FN", "n_pred", "n_ref")) {
    values <- rows[[field]]
    if (any(!is.finite(values) | values < 0 | values != floor(values)))
      stop("Invalid count accumulator")
  }
  if (any(rows$TP + rows$FP != rows$n_pred | rows$TP + rows$FN != rows$n_ref))
    stop("Count denominators disagree")
  for (plot in FGI_DEVELOPMENT_PLOTS)
    if (length(unique(rows$n_ref[rows$plot == plot])) != 1L)
      stop("Reference populations differ across arms or targets")
  for (plot in FGI_DEVELOPMENT_PLOTS)
    for (arm in unique(rows$arm))
      if (length(unique(rows$n_pred[rows$plot == plot & rows$arm == arm])) != 1L)
        stop("Prediction populations differ across targets")
  masks <- rows[rows$target == "mask_iou_0.5", , drop = FALSE]
  for (field in c("sum_iou", "sum_maxiou")) {
    limit <- masks[[if (field == "sum_iou") "TP" else "n_ref"]]
    if (any(!is.finite(masks[[field]]) | masks[[field]] < 0 |
            masks[[field]] > limit + .000051)) stop("Invalid mask accumulator")
  }
  for (category in LETTERS[1:4]) {
    ref <- masks[[paste0("n_", category)]]
    tp <- masks[[paste0("tp_", category)]]
    fn <- masks[[paste0("fn_", category)]]
    counts <- c(ref, tp, fn)
    if (any(!is.finite(counts) | counts < 0 | counts != floor(counts)) ||
        any(tp + fn != ref)) stop("Invalid category counts")
    for (prefix in c("sumiou_", "sumcov_")) {
      values <- masks[[paste0(prefix, category)]]
      limit <- if (prefix == "sumiou_") tp else ref
      if (any(!is.finite(values) | values < 0 | values > limit + .000051))
        stop("Invalid category accumulator")
    }
    for (plot in FGI_DEVELOPMENT_PLOTS)
      if (length(unique(ref[masks$plot == plot])) != 1L)
        stop("Category populations differ across arms")
  }
  for (pair in list(c("n_", "n_ref"), c("tp_", "TP"), c("fn_", "FN"),
                   c("sumiou_", "sum_iou"), c("sumcov_", "sum_maxiou")))
    if (any(abs(rowSums(masks[, paste0(pair[1], LETTERS[1:4])]) - masks[[pair[2]]]) > .000251))
      stop("Category accumulators differ from the full population")
  invisible(TRUE)
}

fgi_bootstrap_indices <- function(n = 1000L, seed = 20260923L) {
  old_kind <- RNGkind()
  old_seed <- get0(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
        rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", old_seed, envir = .GlobalEnv)
  })
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
  replicate(n, sample.int(10L, size = 10L, replace = TRUE))
}

fgi_interval <- function(values) {
  values <- values[is.finite(values)]
  q <- if (length(values)) unname(quantile(values, c(.025, .975), type = 7)) else
    c(NA_real_, NA_real_)
  data.frame(lower = q[1], upper = q[2], defined_draws = length(values))
}

fgi_summarize_complete <- function(rows, n_boot = 1000L, seed = 20260923L) {
  fgi_validate_summary_rows(rows)
  groups <- fgi_summary_groups()
  indices <- fgi_bootstrap_indices(n_boot, seed)
  pooled <- list(); intervals <- list(); draws <- list()
  for (i in seq_len(nrow(groups))) {
    group <- groups[i, ]
    id <- paste(group$target, group$arm, sep = "/")
    block <- rows[rows$target == group$target & rows$arm == group$arm, , drop = FALSE]
    block <- block[match(FGI_DEVELOPMENT_PLOTS, as.character(block$plot)), , drop = FALSE]
    score <- fgi_pool_counts(block)
    pooled[[id]] <- cbind(group, score)
    metrics <- c("precision", "recall", "F1", if (group$target == "mask_iou_0.5")
      c("coverage", "SQ", "PQ", paste0("rec_", LETTERS[1:4])))
    samples <- vapply(seq_len(n_boot), function(b)
      unlist(fgi_pool_counts(block[indices[, b], , drop = FALSE])[metrics], use.names = FALSE),
      numeric(length(metrics)))
    rownames(samples) <- metrics
    draws[[id]] <- samples
    for (metric in metrics)
      intervals[[paste(id, metric)]] <- cbind(group, data.frame(metric = metric,
        estimate = score[[metric]]), fgi_interval(samples[metric, ]))
  }
  contrasts <- list()
  add_contrast <- function(from, to, kind, metric = "F1") {
    delta <- draws[[to]][metric, ] - draws[[from]][metric, ]
    contrasts[[paste(from, to, metric)]] <<- cbind(data.frame(kind = kind,
      from = from, to = to, metric = metric,
      estimate = pooled[[to]][[metric]] - pooled[[from]][[metric]]), fgi_interval(delta))
  }
  for (target in c("apex_max_agl", "mask_iou_0.5")) {
    ids <- names(pooled)[vapply(pooled, function(x) x$target == target, logical(1))]
    pairs <- combn(ids, 2L)
    for (i in seq_len(ncol(pairs))) add_contrast(pairs[1, i], pairs[2, i], "paired_arm")
  }
  for (arm in c("segmentanytree", "forestformer3d"))
    for (policy in c("isolated_top_agl", "historical_raw"))
      add_contrast(paste0("apex_max_agl/", arm), paste0("apex_", policy, "/", arm),
                   "paired_height")
  list(pooled = do.call(rbind, pooled), intervals = do.call(rbind, intervals),
       contrasts = do.call(rbind, contrasts), bootstrap_indices = t(indices))
}
