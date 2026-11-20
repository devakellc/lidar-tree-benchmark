# Chance agreement inside censused subplots and on plot subsets: pure helpers
# for paper_census_null.R and paper_null_subsets.R. Sourced after sweep_lib.R
# (null_offset), model_bench_lib.R (seed_for) and master_tables_lib.R
# (mt_boot_scores, mt_interval).
#
# The null is the paper's (paper_sensitivity.R MODE=null): per plot, K
# toroidal shifts of every cell's detections inside the nominal box plus the
# match radius, the same shifts for every arm and rung; a cell's null is its
# mean counts over the K shifts, pooled by summed counts like an observed
# variant on the same plots and plot resamples. Corrected scores are
# (observed - null) / (1 - null), for the estimate and for every paired draw.

CN_ARMS <- c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d", "li2012",
             "forestformer3d", "treeisonet", "segmentanytree")
CN_BASE <- "chm_vwf"
CN_COUNTS <- c("n_ref", "n_det", "TP", "tp_core")
CN_RECT <- paste0("rect_", CN_COUNTS)
CN_METRICS <- c("recall", "precision", "F1")
CN_LABELS <- c(segmentanytree = "SegmentAnyTree", forestformer3d = "ForestFormer3D",
               li2012 = "Li 2012", treeisonet = "TreeisoNet", chm_vwf = "CHM-VWF",
               multichm = "`multichm`", lmfauto = "`lmfauto`", ptrees = "`ptrees`",
               ams3d = "AMS3D", deepforest = "DeepForest", detectree2 = "Detectree2",
               sam2point = "SAM2Point")

## ---- the paper's shifts ---------------------------------------------------------
# K offsets for one plot, shared by every arm and rung: the torus has side
# 2 (ph + tol); draw k uses seed seed_for(site, plot, "null") + seed * 1000003 + k.
cn_offsets <- function(site, plot, ph, tol, K, seed = 0L, min_shift = 8)
  lapply(seq_len(K), function(k)
    null_offset(2 * (ph + tol), seed_for(site, plot, "null") + seed * 1000003L + k,
                min_shift = min_shift))

# File suffix of a non-default radius, minimum shift or seed (as the paper's
# null_tol2_*, null_ms6_*, null_seed1_* files).
cn_suffix <- function(tol, min_shift = 8, seed = 0L, base_tol = 4)
  paste0("", if (tol != base_tol) sprintf("_tol%g", tol),
         if (min_shift != 8) sprintf("_ms%g", min_shift),
         if (seed != 0) sprintf("_seed%d", seed))

# For the in-window detections (x, y) before a shift: TRUE where the shift
# carried them across the window edge (shift_detections wraps them).
cn_wrapped <- function(x, y, cx, cy, half, offset)
  (x - (cx - half) + offset[1]) >= 2 * half | (y - (cy - half) + offset[2]) >= 2 * half

# The K shifted copies of one cell's detections: `offs` from cn_offsets(), the
# window of half-width `half` (ph + tol) around (cx, cy) as shift_detections()
# wraps it, each copy scored by `score` (a function of a detection table that
# returns a one-row data.frame holding `cols`). `inside`, if given, flags
# positions inside the censused interior, to count the interior detections of
# each copy that crossed the window edge. Returns the K x cols count matrix,
# the per-copy crossed counts and the number of detections in the window.
cn_cell_shifts <- function(det, cx, cy, half, offs, score, cols, inside = NULL) {
  x0 <- det[abs(det$x - cx) <= half & abs(det$y - cy) <= half, , drop = FALSE]
  m <- matrix(NA_real_, length(offs), length(cols), dimnames = list(NULL, cols))
  wrapped <- rep(NA_real_, length(offs))
  for (k in seq_along(offs)) {
    sh <- shift_detections(det, cx, cy, half, offs[[k]])    # keeps x0's row order
    m[k, ] <- unlist(score(sh)[1, cols])
    if (!is.null(inside))
      wrapped[k] <- sum(inside(sh$x, sh$y) & cn_wrapped(x0$x, x0$y, cx, cy, half, offs[[k]]))
  }
  list(draws = m, wrapped = wrapped, n_window = nrow(x0))
}

# Distance by which each reference lies outside the nominal box (0 inside).
# A reference outside the box has part of its match disc beyond the shift
# window, where observed detections can lie but shifted ones never do.
cn_box_excess <- function(E, N, cx, cy, ph) pmax(0, pmax(abs(E - cx), abs(N - cy)) - ph)

## ---- cells ------------------------------------------------------------------------------
# One family's counts in the master tables' form: "census" keeps the censused
# counts, "box" renames the nominal-box counts (rect_*).
cn_family_rows <- function(x, family = c("census", "box")) {
  family <- match.arg(family)
  keys <- intersect(c("variant", "site", "plot", "rung", "detector"), names(x))
  src <- if (family == "census") CN_COUNTS else CN_RECT
  y <- as.data.frame(x)[, c(keys, src), drop = FALSE]
  names(y) <- c(keys, CN_COUNTS)
  y
}

# Mean counts of a cell over its shifts (a K x counts matrix).
cn_null_means <- function(m) {
  if (!nrow(m)) stop("No shifts")
  as.list(colMeans(m))
}

cn_corrected <- function(observed, null) (observed - null) / (1 - null)

## ---- pooling ----------------------------------------------------------------------------
# Pools one rung's observed and null cells (variant "observed" / "null"; site,
# plot, rung, detector and the four counts) over every scope, on the plot
# resamples W (plots x draws, rownames "site::plot"; a scope uses the rows of
# its sites). Returns the estimates (variants observed, null, corrected and
# null_share = null F1 / observed F1) and the leads over `base` (kinds
# observed, null and corrected), each with a paired percentile interval.
cn_pool <- function(x, W, scopes, base = CN_BASE, metrics = CN_METRICS) {
  x <- as.data.frame(x)
  if (length(unique(x$rung)) != 1L) stop("cn_pool pools one rung at a time")
  if (!setequal(unique(x$variant), c("observed", "null")))
    stop("cn_pool needs the observed and null variants")
  r <- x$rung[1]
  arms <- unique(x$detector)
  site_of <- sub("::.*", "", rownames(W))
  est <- list(); leads <- list()
  for (sc in names(scopes)) {
    keep <- site_of %in% scopes[[sc]]
    if (!any(keep)) next
    xs <- x[x$site %in% scopes[[sc]], , drop = FALSE]
    s <- mt_boot_scores(xs, W[keep, , drop = FALSE], c("variant", "detector", "rung"))
    g <- function(v, a) paste(v, a, r, sep = "|")
    E <- function(m, v, a) s$estimate[[m]][match(g(v, a), s$groups)]
    D <- function(m, v, a) s$draws[[m]][, g(v, a)]
    corr <- function(m, a) list(e = cn_corrected(E(m, "observed", a), E(m, "null", a)),
                                d = cn_corrected(D(m, "observed", a), D(m, "null", a)))
    cnt <- function(v, a) s$estimate[match(g(v, a), s$groups), c("n_plots", "n_ref", "n_det", "TP")]
    row <- function(a, v, m, e, d, from = v)
      cbind(data.frame(scope = sc, rung = r, detector = a, cnt(from, a), variant = v,
                       metric = m, estimate = e, stringsAsFactors = FALSE, row.names = NULL),
            mt_interval(d))
    for (a in arms) {
      for (m in metrics) {
        for (v in c("observed", "null"))
          est[[length(est) + 1]] <- row(a, v, m, E(m, v, a), D(m, v, a))
        k <- corr(m, a)
        est[[length(est) + 1]] <- row(a, "corrected", m, k$e, k$d, "observed")
      }
      if ("F1" %in% metrics)
        est[[length(est) + 1]] <- row(a, "null_share", "F1",
                                      E("F1", "null", a) / E("F1", "observed", a),
                                      D("F1", "null", a) / D("F1", "observed", a), "observed")
    }
    if (base %in% arms) for (a in setdiff(arms, base)) for (m in metrics) {
      lead <- function(kind, e, d)
        cbind(data.frame(scope = sc, rung = r, detector = a, versus = base,
                         n_plots = sum(keep), kind = kind, metric = m, estimate = e,
                         stringsAsFactors = FALSE), mt_interval(d))
      for (v in c("observed", "null"))
        leads[[length(leads) + 1]] <- lead(v, E(m, v, a) - E(m, v, base),
                                           D(m, v, a) - D(m, v, base))
      ka <- corr(m, a); kb <- corr(m, base)
      leads[[length(leads) + 1]] <- lead("corrected", ka$e - kb$e, ka$d - kb$d)
    }
  }
  list(est = do.call(rbind, est), leads = do.call(rbind, leads))
}

# Monte Carlo error of the pooled null: each shift's counts summed over the
# plots and scored, then the standard deviation over the shifts and its
# standard error (sd / sqrt(K)). `draws`: detector, k and the four counts.
cn_mc_se <- function(draws) {
  dt <- data.table::as.data.table(draws)[, list(n_ref = sum(n_ref), n_det = sum(n_det),
                                                TP = sum(TP), tp_core = sum(tp_core)),
                                         by = c("detector", "k")]
  dt[, recall := TP / n_ref]
  dt[, precision := ifelse(n_det > 0, tp_core / n_det, NA_real_)]
  dt[, F1 := 2 * recall * precision / (recall + precision)]
  as.data.frame(dt[, list(shifts = .N, F1_mean = mean(F1), F1_sd = stats::sd(F1),
                          F1_se = stats::sd(F1) / sqrt(.N)), by = "detector"])
}

## ---- parity checks ------------------------------------------------------------------------
# Largest absolute difference per column between `a` and the rows of `b` with
# the same keys (numeric: two NAs agree, one NA is Inf; other types: the
# number of differing rows), and the number of rows of `a` without a match.
cn_compare <- function(a, b, keys, cols, b_cols = cols) {
  a <- as.data.frame(a); b <- as.data.frame(b)
  ka <- do.call(paste, c(lapply(a[keys], as.character), sep = "\r"))
  kb <- do.call(paste, c(lapply(b[keys], as.character), sep = "\r"))
  if (anyDuplicated(kb)) stop("Duplicate keys in the reference table")
  i <- match(ka, kb); hit <- !is.na(i)
  diff <- vapply(seq_along(cols), function(j) {
    x <- a[[cols[j]]][hit]; y <- b[[b_cols[j]]][i[hit]]
    if (!length(x)) return(0)
    if (is.numeric(x) && is.numeric(y)) {
      dd <- abs(x - y)
      dd[is.na(x) & is.na(y)] <- 0
      dd[xor(is.na(x), is.na(y))] <- Inf
      max(dd)
    } else as.numeric(sum(as.character(x) != as.character(y), na.rm = TRUE) +
                        sum(xor(is.na(x), is.na(y))))
  }, numeric(1))
  list(n = length(ka), matched = sum(hit), missing = sum(!hit), max_diff = setNames(diff, cols))
}
# The largest difference of a parity check as a check file states it: within
# the tolerance, the tolerance, not the residual, whose last digits depend on
# the BLAS and the build (the rebuild compares check files byte for byte);
# beyond it, the size, per column when the differences are named.
cn_diff_text <- function(d, tol) {
  if (length(d) && all(d <= tol)) return(sprintf("within the tolerance %g", tol))
  if (is.null(names(d))) sprintf("%.3g", max(d)) else paste(sprintf("%s %.3g", names(d), d), collapse = ", ")
}

## ---- combining runs ---------------------------------------------------------------------------
# The shift parameters a paper_census_null.R run states in the first line of its
# check file, and whether its checks passed (A and C pass, B passes or does not
# apply or is skipped, nothing fails).
cn_run_params <- function(lines) {
  m <- regmatches(lines[1], regexec(paste0("declaration (\\S+) \\((.*)\\), TOL=([0-9.]+), K=([0-9]+), ",
                                           "SEED=(-?[0-9]+), MIN_SHIFT=([0-9.]+)"), lines[1]))[[1]]
  if (length(m) != 7) stop("Not a census-null check file: ", lines[1])
  list(declaration = m[3], tol = as.numeric(m[4]), K = as.integer(m[5]), seed = as.integer(m[6]),
       min_shift = as.numeric(m[7]))
}
cn_checks_passed <- function(lines)
  any(grepl("^CHECK A .*: PASS$", trimws(lines))) && any(grepl("^CHECK C .*: PASS$", trimws(lines))) &&
    !any(grepl("FAIL", lines))

# Cells (site, plot, rung) whose arms disagree on the reference: the censused
# and nominal-box reference counts and the support identity must be the same
# for every arm of a cell. Returns the disagreeing cell keys.
cn_reference_mismatch <- function(cells, cols = c("n_ref", "rect_n_ref", "support_id")) {
  key <- paste(cells$site, cells$plot, cells$rung, sep = "::")
  bad <- vapply(split(cells[cols], key), function(z)
    any(vapply(z, function(v) length(unique(v)) > 1L, logical(1))), logical(1))
  names(bad)[bad]
}

# Rungs on which the arms do not all score the same plots.
cn_unequal_rungs <- function(cells) {
  r <- split(cells, cells$rung)
  names(r)[!vapply(r, function(x) {
    s <- lapply(split(paste(x$site, x$plot), x$detector), function(v) sort(unique(v)))
    all(vapply(s, identical, logical(1), s[[1]]))
  }, logical(1))]
}

## ---- plot subsets and reference geometry ----------------------------------------------------
# Plot keys ("site::plot") of a named subset of `plots` (site, plot, plotType):
# "all", "tower", "distributed", or "exclude" (every plot not in `exclude`).
ns_subset_keys <- function(plots, subset, exclude = character()) {
  keep <- switch(subset,
                 all = rep(TRUE, nrow(plots)),
                 tower = plots$plotType == "tower",
                 distributed = plots$plotType == "distributed",
                 exclude = !plots$plot %in% exclude,
                 stop("Unknown subset: ", subset))
  if (subset == "exclude" && !all(exclude %in% plots$plot))
    stop("Excluded plots not in the population: ",
         paste(setdiff(exclude, plots$plot), collapse = ", "))
  sort(paste(plots$site, plots$plot, sep = "::")[keep])
}

# Stems per 20 m quadrant of a tower core (offsets dx, dy from the centroid):
# the number of stems, of quadrants holding any, and in the two fullest.
ns_quadrants <- function(dx, dy) {
  q <- factor(paste0(ifelse(dy >= 0, "N", "S"), ifelse(dx >= 0, "E", "W")),
              levels = c("NE", "NW", "SE", "SW"))
  n <- as.vector(table(q))
  data.frame(stems = length(dx), quadrants_with_stems = sum(n > 0),
             top2_stems = sum(sort(n, decreasing = TRUE)[1:2]))
}

## ---- formatting -------------------------------------------------------------------------------
# Three decimals, Unicode minus; signed adds "+" to non-negative values.
cn_num <- function(x, signed = FALSE) {
  s <- ifelse(is.finite(x), sprintf(if (signed) "%+.3f" else "%.3f", x), "—")
  gsub("-", "−", s, fixed = TRUE)
}
cn_ci <- function(e, lo, hi, signed = FALSE) {
  if (!length(e) || !is.finite(e)) return("—")
  sprintf("%s [%s, %s]", cn_num(e, signed), cn_num(lo, signed), cn_num(hi, signed))
}
