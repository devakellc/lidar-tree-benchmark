# Master tables for the paper: pooled detection scores with paired plot-level
# bootstrap intervals, arm-versus-arm contrasts, and the reference accounting.
# Pure functions; sourced after model_bench_lib.R. Driver: master_tables.R.

MT_N_BOOT <- 1000L
MT_SEED   <- 20261002L
MT_RUNGS  <- c("native", "8", "4", "2", "1")
MT_LEVEL  <- c(0.025, 0.975)

## ---- plot resamples ---------------------------------------------------------
# Adapted from the FGI-EMIT paired whole-plot percentile bootstrap
# (fgiemit_development_summary_lib.R: fgi_bootstrap_indices, fgi_interval).
# The plot is the resampling unit, and one set of resamples is drawn once and
# shared by every arm, rung and metric, so contrasts between them are paired.
# NEON plots are resampled with replacement within each site (sites are fixed
# strata of different sizes). Returns a plots x draws matrix of multiplicities
# with rownames "site::plot"; the caller's RNG state is restored.
mt_plot_weights <- function(site, plot, n_boot = MT_N_BOOT, seed = MT_SEED) {
  ids <- sort(unique(paste(site, plot, sep = "::")))
  if (!length(ids)) stop("No plots to resample")
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
  members <- split(seq_along(ids), sub("::.*", "", ids))
  W <- matrix(0L, length(ids), n_boot, dimnames = list(ids, NULL))
  for (b in seq_len(n_boot)) for (m in members)
    W[, b] <- W[, b] + tabulate(m[sample.int(length(m), length(m), replace = TRUE)],
                                length(ids))
  W
}

mt_interval <- function(values) {
  values <- values[is.finite(values)]
  q <- if (length(values)) unname(quantile(values, MT_LEVEL, type = 7)) else
    c(NA_real_, NA_real_)
  data.frame(lower = q[1], upper = q[2], defined_draws = length(values))
}

## ---- pooled scores under the resamples -------------------------------------
# rows: one per site x plot x group cell with TP, n_ref, n_det and tp_core (or
# precision, from which tp_core is recovered as pool() does). Every group must
# cover exactly the plots of W: equal support is enforced before, never here.
# Scores pool summed counts (recall = sum TP / sum n_ref, precision = sum
# tp_core / sum n_det), never per-plot rates. Returns the point estimates per
# group and, per metric, a draws x groups matrix.
mt_boot_scores <- function(rows, W, group_cols) {
  rows <- as.data.frame(rows)
  if (is.null(rows$tp_core)) rows$tp_core <- round(rows$precision * rows$n_det)
  rows$tp_core[rows$n_det == 0] <- 0
  if (anyNA(rows[c("TP", "n_ref", "n_det", "tp_core")])) stop("Missing counts")
  cell <- paste(rows$site, rows$plot, sep = "::")
  grp <- do.call(paste, c(rows[group_cols], sep = "|"))
  if (anyDuplicated(paste(grp, cell))) stop("Duplicate plot cells within a group")
  groups <- unique(grp)
  for (g in groups) if (!setequal(cell[grp == g], rownames(W)))
    stop("Group ", g, " does not cover the resampled plots; enforce equal support first")
  count_matrix <- function(col) {
    m <- matrix(0, nrow(W), length(groups), dimnames = list(rownames(W), groups))
    m[cbind(match(cell, rownames(W)), match(grp, groups))] <- rows[[col]]
    m
  }
  M <- lapply(c(TP = "TP", n_ref = "n_ref", tp_core = "tp_core", n_det = "n_det"),
              count_matrix)
  rates <- function(TP, n_ref, tp_core, n_det) {
    r <- TP / n_ref
    p <- ifelse(n_det > 0, tp_core / n_det, NA_real_)
    f <- ifelse(is.finite(r) & is.finite(p) & (r + p) > 0, 2 * r * p / (r + p), NA_real_)
    list(recall = r, precision = p, F1 = f)
  }
  tot <- lapply(M, colSums)
  est <- rates(tot$TP, tot$n_ref, tot$tp_core, tot$n_det)
  key <- unique(data.frame(rows[group_cols], .group = grp, stringsAsFactors = FALSE))
  key <- key[match(groups, key$.group), , drop = FALSE]
  estimate <- data.frame(key[group_cols], n_plots = nrow(W),
                         n_ref = tot$n_ref, n_det = tot$n_det, TP = tot$TP,
                         recall = est$recall, precision = est$precision, F1 = est$F1,
                         row.names = NULL, stringsAsFactors = FALSE)
  bt <- lapply(M, function(m) crossprod(W, m))     # draws x groups
  draws <- rates(bt$TP, bt$n_ref, bt$tp_core, bt$n_det)
  draws <- lapply(draws, function(x) { dim(x) <- dim(bt$TP); colnames(x) <- groups; x })
  list(estimate = estimate, draws = draws, groups = groups, group_cols = group_cols)
}

# Long table of estimates with percentile intervals, one row per group x metric.
mt_intervals <- function(scores, metrics = c("recall", "precision", "F1")) {
  key <- scores$estimate[setdiff(names(scores$estimate), c("recall", "precision", "F1"))]
  do.call(rbind, lapply(metrics, function(m) do.call(rbind, lapply(seq_along(scores$groups),
    function(i) cbind(key[i, , drop = FALSE], metric = m,
                      estimate = scores$estimate[[m]][i],
                      mt_interval(scores$draws[[m]][, i]))))))
}

# Paired contrast to - from within one score set (same resamples).
mt_contrast <- function(scores, from, to, metric = "F1") {
  i <- match(c(from, to), scores$groups)
  if (anyNA(i)) stop("Unknown group in contrast: ", paste(c(from, to)[is.na(i)], collapse = ", "))
  delta <- scores$draws[[metric]][, i[2]] - scores$draws[[metric]][, i[1]]
  cbind(data.frame(from = from, to = to, metric = metric,
                   estimate = scores$estimate[[metric]][i[2]] - scores$estimate[[metric]][i[1]],
                   stringsAsFactors = FALSE), mt_interval(delta))
}

## ---- equal support -----------------------------------------------------------
# Within each rung, keep only the (site, plot) cells every listed arm scored, via
# the canonical equal_set_guard(); report what was dropped.
mt_equal_support <- function(rows, arms) {
  out <- list(); dropped <- character()
  for (r in unique(rows$rung)) {
    x <- rows[rows$rung == r & rows$detector %in% arms, , drop = FALSE]
    present <- intersect(arms, unique(x$detector))
    if (!length(present)) next
    g <- equal_set_guard(x, present)
    dropped <- c(dropped, attr(g, "dropped"))
    out[[r]] <- g
  }
  res <- do.call(rbind, out)
  rownames(res) <- NULL
  attr(res, "dropped") <- dropped
  res
}

## ---- reference accounting ----------------------------------------------------
# Core stems per plot under a stem gate and a plot rule. `plot_rule` "whole"
# counts gated live mapped trees over the whole plot (the historical six-stem
# gate); "core" counts them inside the nominal core (native cross-check rule).
mt_reference_counts <- function(gt, pc, gate = "all_mapped", min_trees = 6L,
                                plot_rule = c("whole", "core")) {
  plot_rule <- match.arg(plot_rule)
  inv <- ext_plot_inventory(ext_gate(ext_live_trees(gt), gate), pc, min_trees)
  n_core <- if (gate == "dbh10") inv$n_core_dbh10 else inv$n_core
  keep <- if (plot_rule == "whole") inv$admitted else n_core >= min_trees
  keep <- keep & n_core > 0
  data.frame(plotID = inv$plotID[keep], n_core = n_core[keep], stringsAsFactors = FALSE)
}

# Stems with a NEON field crown diameter, joined from the VST apparent
# individuals nearest to 2021 exactly as crown_metrics_sweep.R::field_crowns().
mt_field_crown_ids <- function(vst_rds) {
  ai <- as.data.frame(readRDS(vst_rds)$vst_apparentindividual)
  ai$year <- suppressWarnings(as.integer(substr(ai$date, 1, 4)))
  ai <- ai[!is.na(ai$year), , drop = FALSE]
  ai <- ai[order(ai$individualID, abs(ai$year - 2021)), , drop = FALSE]
  ai <- ai[!duplicated(ai$individualID), , drop = FALSE]
  ai$individualID[!is.na(ai$maxCrownDiameter) | !is.na(ai$ninetyCrownDiameter)]
}
