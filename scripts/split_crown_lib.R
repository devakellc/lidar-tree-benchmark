# Split-crown diagnostic: pure helpers for split_crown_diagnostic.R (post hoc).
# A split crown is a second detection of one crown beside the tree's own
# detection. The chance-correction simulation shows that such detections, which
# follow the trees without finding the mapped stems, lift chance-corrected
# scores; this diagnostic asks how often the benchmark's detectors place them.
#
# Per cell (one arm's persisted detections on one plot):
#   close pairs   unordered pairs of detections 1.5-4 m apart (SC_RMIN, SC_RMAX)
#                 with at least one in the scored area (the "focus");
#   valley test   the canopy height model sampled along the segment between the
#                 two detections; the pair has no valley when the profile never
#                 drops more than a threshold below the lower of the two ends
#                 (an absolute drop in metres or a share of that end's height);
#   split-crown   an unmatched detection in the scored area lying 1.5-4 m from
#   candidates    a matched detection of the same arm with no valley between.
# Counts are summed over plots and pooled as ratios of sums, with the master
# tables' paired plot resamples (sc_boot). Sourced after master_tables_lib.R
# when intervals are wanted (mt_interval).

SC_RMIN <- 1.5         # close-pair annulus, inner radius (m): the simulation's CS_SPLIT
SC_RMAX <- 4           # outer radius (m), also the matching radius
SC_SUB_GAP <- 2        # a detection more than this below the canopy surface lies beneath it (m)
SC_N_PROFILE <- 41     # samples along a pair's segment (spacing <= 0.1 m at 4 m)
SC_MIN_VALID <- 0.5    # share of profile samples on the canopy model needed for a verdict

# Valley thresholds: absolute drops (m) and drops relative to the lower end's height.
sc_thresholds <- function(abs = c(0.5, 1, 2), rel = c(0.05, 0.10, 0.20)) {
  data.frame(threshold = c(sprintf("abs_%gm", abs), sprintf("rel_%g%%", 100 * rel)),
             type = c(rep("abs", length(abs)), rep("rel", length(rel))),
             value = c(abs, rel), stringsAsFactors = FALSE)
}

## ---- pairs ---------------------------------------------------------------------
# Unordered pairs (i < j, indices into x/y) at a distance in [rmin, rmax], keeping
# the pairs with at least one `keep` point. A sweep over x sorted, so memory stays
# linear in the number of points.
sc_pairs <- function(x, y, rmin = SC_RMIN, rmax = SC_RMAX, keep = rep(TRUE, length(x))) {
  empty <- data.frame(i = integer(), j = integer(), dist = numeric())
  n <- length(x)
  if (length(y) != n || length(keep) != n) stop("x, y and keep must have one value per point")
  if (anyNA(x) || anyNA(y)) stop("Points need coordinates")
  if (n < 2) return(empty)
  o <- order(x); xs <- x[o]; ys <- y[o]
  out <- vector("list", n - 1L)
  for (k in seq_len(n - 1L)) {
    hi <- findInterval(xs[k] + rmax, xs)
    if (hi <= k) next
    jj <- (k + 1L):hi
    dd <- sqrt((xs[jj] - xs[k])^2 + (ys[jj] - ys[k])^2)
    ok <- dd >= rmin & dd <= rmax
    if (any(ok)) out[[k]] <- cbind(o[k], o[jj[ok]], dd[ok])
  }
  m <- do.call(rbind, out)
  if (is.null(m)) return(empty)
  p <- data.frame(i = as.integer(pmin(m[, 1], m[, 2])), j = as.integer(pmax(m[, 1], m[, 2])),
                  dist = m[, 3])
  p <- p[keep[p$i] | keep[p$j], , drop = FALSE]
  p <- p[order(p$i, p$j), , drop = FALSE]
  rownames(p) <- NULL
  p
}

# Per point: TRUE when another point lies in [rmin, rmax].
sc_has_neighbour <- function(x, y, rmin = SC_RMIN, rmax = SC_RMAX) {
  p <- sc_pairs(x, y, rmin, rmax)
  seq_along(x) %in% c(p$i, p$j)
}

## ---- canopy profile between two detections ---------------------------------------
# height_at(x, y) returns canopy heights (NA off the model or in an empty cell).
# Per pair: the heights at the two ends (the nearest valid sample to each end),
# the lowest sample between them (ends included) and the valley depth, lower end
# minus lowest sample. A profile with fewer than min_valid of its samples on the
# model gives no verdict (valid FALSE, depth NA).
sc_valley <- function(x1, y1, x2, y2, height_at, n = SC_N_PROFILE, min_valid = SC_MIN_VALID) {
  m <- length(x1)
  na <- rep(NA_real_, m)
  out <- data.frame(top1 = na, top2 = na, lower_top = na, floor = na, depth = na,
                    n_valid = integer(m), valid = logical(m))
  if (!m) return(out)
  t <- seq(0, 1, length.out = n)
  X <- x1 + outer(x2 - x1, t)                 # m x n; x1 recycles down the columns
  Y <- y1 + outer(y2 - y1, t)
  H <- matrix(as.numeric(height_at(as.vector(X), as.vector(Y))), m, n)
  H[!is.finite(H)] <- NA
  ok <- !is.na(H)
  nv <- rowSums(ok)
  has <- nv > 0
  if (any(has)) {
    r <- which(has)
    okr <- ok[r, , drop = FALSE] * 1
    first <- max.col(okr, ties.method = "first")
    last <- max.col(okr, ties.method = "last")
    out$top1[r] <- H[cbind(r, first)]
    out$top2[r] <- H[cbind(r, last)]
    out$floor[r] <- apply(H[r, , drop = FALSE], 1, min, na.rm = TRUE)
  }
  out$n_valid <- as.integer(nv)
  out$valid <- nv >= min_valid * n
  out$lower_top <- pmin(out$top1, out$top2)
  out$depth <- ifelse(out$valid, out$lower_top - out$floor, NA_real_)
  out$lower_top[!out$valid] <- NA_real_
  out
}

# TRUE where a pair has no valley at the threshold: the profile never drops more
# than `value` metres (type "abs") or `value` x the lower end's height (type
# "rel") below the lower end. Pairs without a verdict are FALSE.
sc_no_valley <- function(depth, lower_top, type, value) {
  thr <- if (type == "abs") rep(value, length(depth)) else value * pmax(lower_top, 0)
  thr[is.na(thr)] <- 0
  !is.na(depth) & depth <= thr
}

# Canopy heights of a SpatRaster as a function of position (nearest cell).
sc_height_at <- function(r) {
  v <- terra::values(r, mat = FALSE)
  function(x, y) v[terra::cellFromXY(r, cbind(x, y))]
}

## ---- one cell ------------------------------------------------------------------
# det: the arm's detections inside the scoring region (data.frame x, y, z, z the
# height above ground); focus: the detections counted as the arm's detections
# (the core, or the censused interior); matched: the detections the matcher
# paired with a reference stem (any in the region). height_at: the canopy model
# (sc_height_at), or NULL for points without one (every close pair then counts
# as one crown and every detection as at the surface). Returns
#   counts  one row per threshold:
#     n_det          focus detections
#     n_close        focus detections with another detection 1.5-4 m away
#     n_near         focus detections with another detection closer than rmin
#     TP, tp_core    matched detections, and those in the focus
#     n_fp           unmatched focus detections (n_det - tp_core)
#     n_pairs        close pairs (at least one end in the focus)
#     n_pairs_valid  close pairs with a verdict
#     n_pairs_novalley      pairs with no valley at the threshold
#     n_pairs_novalley_sub  of those, pairs whose lower detection (by z) lies
#                           more than sub_gap below the canopy surface
#     n_split_any    unmatched focus detections 1.5-4 m from a matched detection
#     n_split        of those, with no valley to it (split-crown candidates)
#     n_split_surface  candidates at the canopy surface (within sub_gap of it)
#     n_split_parents  matched detections with at least one candidate
#     n_matched_pairs, n_matched_pairs_novalley  close pairs of two matched
#                    detections, and those with no valley between them
#   pairs   the close pairs with their profiles (i, j index det's rows)
sc_cell <- function(det, focus, matched, height_at, thresholds = sc_thresholds(),
                    rmin = SC_RMIN, rmax = SC_RMAX, sub_gap = SC_SUB_GAP) {
  n <- nrow(det)
  if (length(focus) != n || length(matched) != n) stop("focus and matched need one flag per detection")
  focus <- as.logical(focus); matched <- as.logical(matched)
  if (anyNA(focus) || anyNA(matched)) stop("focus and matched must not be NA")
  p <- sc_pairs(det$x, det$y, rmin, rmax, keep = focus)
  near <- sc_has_neighbour(det$x, det$y, 0, rmin - 1e-9)
  gap <- if (is.null(height_at)) rep(0, n) else
    as.numeric(height_at(det$x, det$y)) - det$z
  if (is.null(height_at)) {
    na <- rep(NA_real_, nrow(p))
    v <- data.frame(top1 = na, top2 = na, lower_top = na, floor = na, depth = numeric(nrow(p)),
                    n_valid = rep(NA_integer_, nrow(p)), valid = rep(TRUE, nrow(p)))
  } else {
    v <- sc_valley(det$x[p$i], det$y[p$i], det$x[p$j], det$y[p$j], height_at)
  }
  pairs <- data.frame(p, focus_i = focus[p$i], focus_j = focus[p$j],
                      matched_i = matched[p$i], matched_j = matched[p$j],
                      z_i = det$z[p$i], z_j = det$z[p$j], gap_i = gap[p$i], gap_j = gap[p$j], v)
  lower <- ifelse(pairs$z_i <= pairs$z_j, pairs$i, pairs$j)
  sub <- !is.na(gap[lower]) & gap[lower] > sub_gap
  # Candidate i (unmatched, focus) beside matched j, and the reverse.
  ci <- pairs$focus_i & !pairs$matched_i & pairs$matched_j
  cj <- pairs$focus_j & !pairs$matched_j & pairs$matched_i
  both <- pairs$matched_i & pairs$matched_j
  at_surface <- function(k) !is.na(gap[k]) & gap[k] <= sub_gap
  base <- data.frame(n_det = sum(focus), n_close = sum(focus & seq_len(n) %in% c(p$i, p$j)),
                     n_near = sum(focus & near), TP = sum(matched), tp_core = sum(matched & focus),
                     n_fp = sum(focus & !matched), n_pairs = nrow(pairs),
                     n_pairs_valid = sum(pairs$valid),
                     n_split_any = length(unique(c(pairs$i[ci], pairs$j[cj]))),
                     n_matched_pairs = sum(both))
  counts <- do.call(rbind, lapply(seq_len(nrow(thresholds)), function(k) {
    nv <- sc_no_valley(pairs$depth, pairs$lower_top, thresholds$type[k], thresholds$value[k])
    cand <- unique(c(pairs$i[ci & nv], pairs$j[cj & nv]))
    parents <- unique(c(pairs$j[ci & nv], pairs$i[cj & nv]))
    data.frame(threshold = thresholds$threshold[k], base,
               n_pairs_novalley = sum(nv), n_pairs_novalley_sub = sum(nv & sub),
               n_split = length(cand), n_split_surface = sum(at_surface(cand)),
               n_split_parents = length(parents),
               n_matched_pairs_novalley = sum(both & nv), stringsAsFactors = FALSE)
  }))
  list(counts = counts, pairs = pairs)
}

# Reference stems' own close pairs: focus stems with another stem (of all the
# stems given, focus or not) 1.5-4 m away, and closer than rmin.
sc_reference_counts <- function(E, N, focus, rmin = SC_RMIN, rmax = SC_RMAX) {
  focus <- as.logical(focus)
  data.frame(n_det = sum(focus), n_close = sum(focus & sc_has_neighbour(E, N, rmin, rmax)),
             n_near = sum(focus & sc_has_neighbour(E, N, 0, rmin - 1e-9)))
}

## ---- pooling under the plot resamples ----------------------------------------------
# rows: one per site x plot x group with count columns. W: the master tables'
# plots x draws resample matrix (mt_plot_weights), rownames "site::plot". Every
# group must cover W's plots exactly. Returns the groups, their key columns, and
# per count column the pooled total (est) and the draws x groups totals (draws).
sc_boot <- function(rows, W, group_cols, counts) {
  rows <- as.data.frame(rows)
  cell <- paste(rows$site, rows$plot, sep = "::")
  grp <- do.call(paste, c(rows[group_cols], sep = "|"))
  if (anyDuplicated(paste(grp, cell))) stop("Duplicate plot cells within a group")
  groups <- unique(grp)
  for (g in groups) if (!setequal(cell[grp == g], rownames(W)))
    stop("Group ", g, " does not cover the resampled plots")
  if (anyNA(rows[counts])) stop("Missing counts")
  key <- rows[match(groups, grp), group_cols, drop = FALSE]
  rownames(key) <- NULL
  est <- list(); draws <- list()
  for (cl in counts) {
    m <- matrix(0, nrow(W), length(groups), dimnames = list(rownames(W), groups))
    m[cbind(match(cell, rownames(W)), match(grp, groups))] <- rows[[cl]]
    est[[cl]] <- colSums(m)
    draws[[cl]] <- crossprod(W, m)
  }
  list(groups = groups, key = key, est = est, draws = draws)
}

# A ratio of pooled counts: the estimate per group and its draws x groups matrix.
sc_ratio <- function(b, num, den) {
  e <- b$est[[num]] / b$est[[den]]
  d <- b$draws[[num]] / b$draws[[den]]
  e[!is.finite(e)] <- NA_real_
  d[!is.finite(d)] <- NA_real_
  list(e = e, d = d)
}
