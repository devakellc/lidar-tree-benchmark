# Master tables for the paper: pooled detection scores with paired plot-level
# bootstrap intervals, arm-versus-arm contrasts, and the reference accounting.
# Pure functions; sourced after model_bench_lib.R. Driver: master_tables.R.

MT_N_BOOT <- 1000L
MT_SEED   <- 20261002L
MT_RUNGS  <- c("native", "8", "4", "2", "1")
MT_LEVEL  <- c(0.025, 0.975)
# Recall strata: the scorer's crown classes and height bands, plus overstory
# (dominant + codominant) and understory (intermediate + suppressed).
MT_STRATA <- list(dominant = "dominant", codominant = "codominant",
                  intermediate = "intermediate", suppressed = "suppressed",
                  overstory = c("dominant", "codominant"),
                  understory = c("intermediate", "suppressed"),
                  h_short = "h_short", h_mid = "h_mid", h_tall = "h_tall")
MT_STRATUM_COLS <- unlist(lapply(unique(unlist(MT_STRATA)), function(k)
  paste0(c("rec_", "n_"), k)))
# Regions: development (California, D17) and replication (Washington, D16).
MT_REGIONS <- list(California = c("SJER", "SOAP", "TEAK"), Washington = c("WREF", "ABBY"))

## ---- benchmark arms --------------------------------------------------------------
# One row per benchmark arm: the results file it writes, the rungs it is run
# at, and the stamped directory or resume sidecar that ties it to the root.
MT_ARMS <- data.frame(
  arm = c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d", "li2012",
          "forestformer3d", "treeisonet", "segmentanytree", "deepforest",
          "detectree2", "sam2point"),
  file = c(rep("lidrplugins_results.csv", 4), "ams3d_results.csv", "li2012_results.csv",
           "forestformer3d_results.csv", "treeisonet_results.csv",
           "segmentanytree_results.csv", "deepforest_results.csv",
           "detectree2_results.csv", "sam2point_results.csv"),
  rungs = c(rep("native,8,4,2,1", 5), "native", rep("native,8,4,2,1", 3),
            "native", "native", "native"),
  provenance = c("chm_vwf_detections", "multichm_detections", "lmfauto_detections",
                 "ptrees_detections", "ams3d_instances", "li2012_instances",
                 "forestformer3d_results.csv.frozen", "treeisonet_instances",
                 "segmentanytree_results.csv.frozen", "deepforest_results.csv.frozen",
                 "detectree2_results.csv.frozen", "sam2point_instances"),
  # The RGB arms have no density ladder: they write rung "rgb", scored once
  # per plot against the same reference, and join the native rung here.
  result_rung = c(rep(NA, 9), "rgb", "rgb", NA),
  # SAM2Point writes its arm as "sam2point_seeded", next to the bare CHM-VWF
  # seeds it was prompted with ("chm_vwf_seeds", a diagnostic, not an arm).
  detector = c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d", "li2012",
               "forestformer3d", "treeisonet", "segmentanytree", "deepforest",
               "detectree2", "sam2point_seeded"),
  stringsAsFactors = FALSE)

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

## ---- recall strata -------------------------------------------------------------
# One row per cell and stratum, with the stratum's stems as the reference and
# its true positives recovered as round(rec * n) per class, as the sweeps pool
# them. Recall only: detections carry no crown class. Cells of an arm without
# the stratum columns are dropped.
mt_stratum_rows <- function(rows) {
  if (!all(MT_STRATUM_COLS %in% names(rows))) return(NULL)
  do.call(rbind, lapply(names(MT_STRATA), function(g) {
    ks <- MT_STRATA[[g]]
    n  <- Reduce(`+`, lapply(ks, function(k) rows[[paste0("n_", k)]]))
    tp <- Reduce(`+`, lapply(ks, function(k) {
      nk <- rows[[paste0("n_", k)]]
      ifelse(nk > 0, round(rows[[paste0("rec_", k)]] * nk), 0)
    }))
    data.frame(site = rows$site, plot = rows$plot, rung = rows$rung,
               detector = rows$detector, stratum = g, TP = tp, n_ref = n,
               n_det = 0, tp_core = 0, stringsAsFactors = FALSE)
  }))
}

## ---- rank stability --------------------------------------------------------------
# Spearman correlation between the arms' F1 at rung `from` and at rung `to`,
# on the plots both rungs share, with a percentile interval over the shared
# plot resamples (each draw ranks the arms again). `rows` holds every arm at
# both rungs; arms missing either rung are dropped.
mt_rank_stability <- function(rows, from, to, n_boot = MT_N_BOOT, seed = MT_SEED,
                              metric = "F1", exclude = character()) {
  x <- rows[rows$rung %in% c(from, to), , drop = FALSE]
  arms <- Reduce(intersect, lapply(c(from, to), function(r) unique(x$detector[x$rung == r])))
  arms <- setdiff(arms, exclude)       # leave-out checks: the resamples are plots, not arms
  x <- x[x$detector %in% arms, , drop = FALSE]
  key <- paste(x$site, x$plot, sep = "::")
  plots <- Reduce(intersect, lapply(split(key, paste(x$detector, x$rung)), unique))
  x <- x[key %in% plots, , drop = FALSE]
  if (length(arms) < 3 || !length(plots)) return(NULL)
  W <- mt_plot_weights(x$site, x$plot, n_boot, seed)
  s <- mt_boot_scores(x, W, c("detector", "rung"))
  g <- function(r) paste(arms, r, sep = "|")
  est <- s$estimate[[metric]]; names(est) <- s$groups
  rho <- function(a, b) suppressWarnings(stats::cor(a, b, method = "spearman"))
  draws <- vapply(seq_len(ncol(W)), function(b)
    rho(s$draws[[metric]][b, g(from)], s$draws[[metric]][b, g(to)]), numeric(1))
  cbind(data.frame(from = from, to = to, metric = metric, arms = length(arms),
                   n_plots = length(plots), estimate = rho(est[g(from)], est[g(to)]),
                   stringsAsFactors = FALSE), mt_interval(draws))
}

## ---- regional leads ----------------------------------------------------------------
# Lead of each arm over `base` within each region, and the difference of leads
# between the two regions, paired over the same plot resamples (W rows are
# split by region; a draw resamples plots within every site at once).
mt_region_leads <- function(rows, W, base, regions = MT_REGIONS, metric = "F1") {
  site_of <- sub("::.*", "", rownames(W))
  sc <- lapply(regions, function(sites) {
    keep <- site_of %in% sites
    if (!any(keep)) return(NULL)
    mt_boot_scores(rows[rows$site %in% sites, , drop = FALSE], W[keep, , drop = FALSE],
                   c("detector", "rung"))
  })
  if (any(vapply(sc, is.null, logical(1)))) return(NULL)
  out <- list()
  for (r in unique(rows$rung)) for (a in setdiff(unique(rows$detector[rows$rung == r]), base)) {
    ga <- paste(a, r, sep = "|"); gb <- paste(base, r, sep = "|")
    if (!all(vapply(sc, function(s) all(c(ga, gb) %in% s$groups), logical(1)))) next
    lead <- lapply(sc, function(s) list(
      est = s$estimate[[metric]][match(ga, s$groups)] - s$estimate[[metric]][match(gb, s$groups)],
      draw = s$draws[[metric]][, ga] - s$draws[[metric]][, gb]))
    out[[length(out) + 1]] <- cbind(data.frame(
      rung = r, arm = a, versus = base, metric = metric,
      lead_first = lead[[1]]$est, lead_second = lead[[2]]$est,
      estimate = lead[[1]]$est - lead[[2]]$est, stringsAsFactors = FALSE),
      mt_interval(lead[[1]]$draw - lead[[2]]$draw))
  }
  res <- do.call(rbind, out)
  if (!is.null(res)) names(res)[names(res) %in% c("lead_first", "lead_second")] <-
    paste0("lead_", tolower(names(regions)))
  res
}

## ---- change across the ladder ----------------------------------------------------
# Each arm's change from `base` (native) to every other rung it was run at,
# on the plots both rungs share, paired over one set of plot resamples.
# `scopes` maps a scope name to its sites; W rows are split by site.
mt_rung_contrasts <- function(rows, scopes, base = "native", n_boot = MT_N_BOOT,
                              seed = MT_SEED, metrics = c("recall", "precision", "F1")) {
  out <- list()
  for (a in unique(rows$detector)) {
    xa <- rows[rows$detector == a, , drop = FALSE]
    if (!base %in% xa$rung) next
    for (r in setdiff(unique(xa$rung), base)) {
      x <- xa[xa$rung %in% c(base, r), , drop = FALSE]
      key <- paste(x$site, x$plot, sep = "::")
      common <- intersect(key[x$rung == base], key[x$rung == r])
      x <- x[key %in% common, , drop = FALSE]
      if (!nrow(x)) next
      W <- mt_plot_weights(x$site, x$plot, n_boot, seed)
      site_of <- sub("::.*", "", rownames(W))
      for (sc in names(scopes)) {
        keep <- site_of %in% scopes[[sc]]
        if (!any(keep)) next
        s <- mt_boot_scores(x[x$site %in% scopes[[sc]], , drop = FALSE], W[keep, , drop = FALSE],
                            c("detector", "rung"))
        for (m in metrics) out[[length(out) + 1]] <- cbind(scope = sc, detector = a, rung = r,
          mt_contrast(s, paste(a, base, sep = "|"), paste(a, r, sep = "|"), m))
      }
    }
  }
  do.call(rbind, out)
}
