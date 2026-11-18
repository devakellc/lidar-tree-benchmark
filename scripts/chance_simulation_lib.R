# Helpers for the chance-correction simulation (simulate_chance_correction.R):
# synthetic plots with a known detector skill, scored by the benchmark's own
# matcher and chance-agreement null. The pattern, detector and truth helpers
# are pure (their RNG use is local and the caller's state is restored);
# cs_score_plot() and cs_score_structure() need sweep_lib.R (score_plot,
# null_offset, shift_detections) sourced first, and cs_pool_pairs() and
# cs_paired_leads() need master_tables_lib.R. The neighbour helpers also
# serve reference_stem_clustering.R.
#
# Geometry: one plot centred on (0, 0), a 40 m core (CS_PH = 20) scored with
# the paper's matching margin, and trees simulated over a square of half-width
# CS_SIM_HALF = 30 m, so the detections near the edge of the 48 m scoring
# window come from trees inside and outside it, as in the benchmark's clips.

CS_PH        <- 20      # core half-width (tower plot)
CS_SIM_HALF  <- 30      # simulated square: core + 4 m margin + 6 m buffer
CS_R_MIN     <- 1.5     # hard-core distance of the tree pattern (m)
CS_H_MEDIAN  <- 15      # tree height median (m)
CS_H_SDLOG   <- 0.4     # tree height log-scale spread
CS_H_RANGE   <- c(3, 60)
CS_SIGMA     <- 1.2     # skilled detection: horizontal offset sd per axis (m)
CS_SIGMA_Z   <- 1.0     # skilled detection: height error sd (m)
CS_F_MAX     <- 2       # commission pool, as a multiple of the tree count
# The six ways to sample two of the four 20 m quadrants of a tower core.
# Quadrants: 1 = south-west, 2 = south-east, 3 = north-west, 4 = north-east.
CS_QUAD_PAIRS <- utils::combn(4, 2)
# Stand structures of the structure scenario. "inhibited" is the sequential
# inhibition of the other scenarios; the clustered patterns are Matern
# cluster processes: parents at D / mu per unit area, a Poisson(mu) number of
# trees per parent, uniform in a disc of radius R around it.
CS_PATTERNS <- list(
  inhibited    = list(type = "inhibited"),
  clustered_4m = list(type = "matern", R = 4, mu = 6),
  clustered_8m = list(type = "matern", R = 8, mu = 4))
# Displaced detector: a tree's detection lies this far from it (m), uniform
# over the annulus, so it never lies within either matching radius.
CS_RING <- c(5, 10)
# Split-crown detector: the second detection of a split crown lies this far
# from its tree (m), uniform in distance.
CS_SPLIT <- c(1.5, 4)

# Seeds as the paper derives them: a key hashed by seed_for() plus
# SEED x 1000003 plus k, wrapped to a valid seed (the paper's sum without the
# wrap whenever it does not overflow).
cs_seed <- function(base, SEED = 0, k = 0) {
  as.integer((as.numeric(base) + as.numeric(SEED) * 1000003 + k) %% 2^31)
}

# Run expr with set.seed(seed), restoring the caller's RNG state.
cs_with_seed <- function(seed, expr) {
  old <- get0(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit(if (is.null(old)) {
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
      rm(".Random.seed", envir = .GlobalEnv)
  } else assign(".Random.seed", old, envir = .GlobalEnv))
  set.seed(seed)
  expr
}

cs_heights <- function(u) {
  pmin(pmax(stats::qlnorm(u, log(CS_H_MEDIAN), CS_H_SDLOG), CS_H_RANGE[1]),
       CS_H_RANGE[2])
}

## ---- tree pattern -----------------------------------------------------------
# Simple sequential inhibition on the square [-half, half]^2: a Poisson number
# of trees at D trees/ha, each placed uniformly and rejected while it lies
# closer than r_min to a tree already placed. Uses the current RNG stream.
cs_pattern <- function(D, half = CS_SIM_HALF, r_min = CS_R_MIN, max_tries = 10000L) {
  n <- stats::rpois(1, D / 1e4 * (2 * half)^2)
  x <- numeric(n); y <- numeric(n); k <- 0L; tries <- 0L
  while (k < n) {
    px <- stats::runif(1, -half, half); py <- stats::runif(1, -half, half)
    if (k == 0L || min((x[seq_len(k)] - px)^2 + (y[seq_len(k)] - py)^2) >= r_min^2) {
      k <- k + 1L; x[k] <- px; y[k] <- py; tries <- 0L
    } else if ((tries <- tries + 1L) > max_tries) stop("Inhibition too strong for the density")
  }
  data.frame(id = seq_len(n), x = x, y = y)
}

# Matern cluster process on the square [-half, half]^2 at D trees/ha: parents
# Poisson at D / mu per unit area over the square widened by R (so clusters
# straddling its edge are kept in part), each with a Poisson(mu) number of
# trees uniform in the disc of radius R around it; trees outside the square
# are dropped. Uses the current RNG stream.
cs_pattern_matern <- function(D, R, mu, half = CS_SIM_HALF) {
  ext <- half + R
  np <- stats::rpois(1, D / 1e4 / mu * (2 * ext)^2)
  px <- stats::runif(np, -ext, ext); py <- stats::runif(np, -ext, ext)
  k <- stats::rpois(np, mu)
  rr <- R * sqrt(stats::runif(sum(k))); th <- stats::runif(sum(k), 0, 2 * pi)
  x <- rep(px, k) + rr * cos(th); y <- rep(py, k) + rr * sin(th)
  keep <- abs(x) <= half & abs(y) <= half
  data.frame(id = seq_len(sum(keep)), x = x[keep], y = y[keep])
}

## ---- one simulated plot -----------------------------------------------------
# Everything random about a plot, drawn once from `seed` in a fixed order:
# the sampled quadrant pair, the trees (pattern from CS_PATTERNS) and their
# heights, and the detector stream shared by every detector on the plot
# (common random numbers): per tree a skill draw u and standard-normal offsets
# (zx, zy, zz), and a pool of commission points of which a detector with
# commission f takes the first round(f x trees). Pool rows are drawn
# row-wise, so the first rows do not depend on the pool size. Drawn last, so
# that everything before is unchanged from the first scenarios: per tree a
# mapping draw v (the tree is a reference stem at completeness p when v < p,
# so the references nest across p) and the displaced detector's distance
# (uniform over the area of the annulus CS_RING) and direction. Drawn after
# those, so that everything before is unchanged from the first runs of the
# structure scenario: per tree the split-crown draws, a draw split_w (a
# detected tree's crown is split at rate `rate` when split_w < rate, so split
# crowns nest across rates), a distance split_d uniform in CS_SPLIT, a
# direction split_a and a standard-normal height error split_z.
cs_plot <- function(D, seed, f_max = CS_F_MAX, pattern = "inhibited") {
  pat <- CS_PATTERNS[[pattern]]
  if (is.null(pat)) stop("Unknown pattern: ", pattern)
  cs_with_seed(seed, {
    quads <- CS_QUAD_PAIRS[, sample.int(ncol(CS_QUAD_PAIRS), 1)]
    tr <- if (pat$type == "inhibited") cs_pattern(D) else cs_pattern_matern(D, pat$R, pat$mu)
    n <- nrow(tr)
    tr$h <- cs_heights(stats::runif(n))
    u <- stats::runif(n)
    zx <- stats::rnorm(n); zy <- stats::rnorm(n); zz <- stats::rnorm(n)
    M <- ceiling(f_max * n)
    pu <- matrix(stats::runif(3 * M), ncol = 3, byrow = TRUE)
    pool <- data.frame(x = -CS_SIM_HALF + 2 * CS_SIM_HALF * pu[, 1],
                       y = -CS_SIM_HALF + 2 * CS_SIM_HALF * pu[, 2],
                       z = cs_heights(pu[, 3]))
    v <- stats::runif(n)
    ring_d <- sqrt(stats::runif(n, CS_RING[1]^2, CS_RING[2]^2))
    ring_a <- stats::runif(n, 0, 2 * pi)
    split_w <- stats::runif(n); split_d <- stats::runif(n, CS_SPLIT[1], CS_SPLIT[2])
    split_a <- stats::runif(n, 0, 2 * pi); split_z <- stats::rnorm(n)
    list(D = D, seed = seed, pattern = pattern, quadrants = quads, trees = tr, u = u,
         zx = zx, zy = zy, zz = zz, pool = pool, v = v, ring_d = ring_d, ring_a = ring_a,
         split_w = split_w, split_d = split_d, split_a = split_a, split_z = split_z)
  })
}

## ---- detector -----------------------------------------------------------------
# Detector with skill s and commission f on a simulated plot: tree i is
# detected when u_i < s, at its position plus sigma x (zx_i, zy_i) and its
# height plus sigma_z x zz_i; plus round(f x trees) commission points, uniform
# over the simulated square with heights from the tree-height distribution.
# Column `tree` is the source tree's id (0 for commission).
# mode "unmapped": only the trees that are not reference stems at
# completeness p (v_i >= p) can be detected, so the detector has no skill on
# the reference; mode "displaced": the detection of tree i lies ring_d_i
# (5-10 m) from it in direction ring_a_i, so no stem's own detection is
# within either radius. Both keep the same draws u, zz and commission points.
# Mode "unmapped" keys on the mapping draw, not on the reference: on a half
# reference it does not detect the mapped trees (v_i < p) of the unsampled
# quadrants, which lie outside the reference too, so it is not a detector of
# every tree outside a half reference (scenario 4 reports it on complete
# references only).
# mode "split": the detections of mode "all" (same rows, same order), then,
# for each detected tree i (u_i < s) with split_w_i < rate, a second
# detection of its crown, split_d_i (1.5-4 m, CS_SPLIT) from the tree in
# direction split_a_i, at its height plus sigma_z x split_z_i, with tree = 0:
# commission that follows the trees, in every score and in the oracle. With
# rate 0 it returns mode "all"'s detections.
cs_detector <- function(plot, s, f, sigma = CS_SIGMA, sigma_z = CS_SIGMA_Z,
                        mode = c("all", "unmapped", "displaced", "split"), p = 1, rate = 0) {
  mode <- match.arg(mode)
  if (mode == "split" && (!is.numeric(rate) || length(rate) != 1 || is.na(rate) ||
                          rate < 0 || rate > 1)) stop("rate must lie in [0, 1]")
  tr <- plot$trees
  hit <- plot$u < s
  if (mode == "unmapped") hit <- hit & plot$v >= p
  sk <- if (mode == "displaced")
    data.frame(x = tr$x[hit] + plot$ring_d[hit] * cos(plot$ring_a[hit]),
               y = tr$y[hit] + plot$ring_d[hit] * sin(plot$ring_a[hit]),
               z = tr$h[hit] + sigma_z * plot$zz[hit], tree = tr$id[hit])
  else data.frame(x = tr$x[hit] + sigma * plot$zx[hit], y = tr$y[hit] + sigma * plot$zy[hit],
                  z = tr$h[hit] + sigma_z * plot$zz[hit], tree = tr$id[hit])
  m <- round(f * nrow(tr))
  if (m > nrow(plot$pool)) stop("Commission exceeds the plot's pool; raise f_max")
  fp <- plot$pool[seq_len(m), , drop = FALSE]
  fp$tree <- rep(0L, m)
  out <- rbind(sk, fp)
  if (mode == "split") {
    if (is.null(plot$split_w)) stop("The plot has no split-crown draws")
    sp <- hit & plot$split_w < rate
    if (any(sp))
      out <- rbind(out, data.frame(x = tr$x[sp] + plot$split_d[sp] * cos(plot$split_a[sp]),
                                   y = tr$y[sp] + plot$split_d[sp] * sin(plot$split_a[sp]),
                                   z = tr$h[sp] + sigma_z * plot$split_z[sp],
                                   tree = rep(0L, sum(sp))))
  }
  out
}

## ---- reference ----------------------------------------------------------------
cs_quadrant <- function(x, y) 1L + (x >= 0) + 2L * (y >= 0)

# Reference stems in the core (score_plot's columns): every tree in the core
# ("complete") or only those in the plot's two sampled quadrants ("half").
# With p < 1 only the trees with mapping draw v < p are reference stems (each
# tree mapped with probability p); the others stay in the plot, detectable.
cs_reference <- function(plot, ref = c("complete", "half"), half = CS_PH, p = 1) {
  ref <- match.arg(ref)
  if (!is.numeric(p) || length(p) != 1 || p <= 0 || p > 1) stop("p must lie in (0, 1]")
  tr <- plot$trees
  keep <- abs(tr$x) <= half & abs(tr$y) <= half
  if (ref == "half") keep <- keep & cs_quadrant(tr$x, tr$y) %in% plot$quadrants
  if (p < 1) keep <- keep & plot$v < p
  data.frame(E = tr$x[keep], N = tr$y[keep], height = tr$h[keep],
             crown_class = rep("codominant", sum(keep)), tree = tr$id[keep],
             stringsAsFactors = FALSE)
}

## ---- truth --------------------------------------------------------------------
# Per reference stem: the row of its own skilled detection in det (NA when
# the tree was not detected by skill) and whether that detection lies within r.
cs_own_detection <- function(stems, det, r) {
  sk <- which(det$tree > 0)
  j <- sk[match(stems$tree, det$tree[sk])]
  d <- sqrt((det$x[j] - stems$E)^2 + (det$y[j] - stems$N)^2)
  list(j = j, within = !is.na(j) & d <= r)
}

# The skilled share's counts within radius r: `ref`, the reference stems whose
# own skilled detection lies within r of the stem; `det`, how many of those
# detections lie in the core (the oracle's true positives for precision).
# The truth ignores the matcher's height gate (a detection between half the
# stem's height and that height plus 8 m): an own detection fails it only
# when its height error is below minus half the tree's height, which with a
# 1 m error happens for trees of about 3-5 m only, for under 0.01% of own
# detections.
cs_true_skilled <- function(stems, det, r, half = CS_PH) {
  o <- cs_own_detection(stems, det, r)
  in_core <- abs(det$x[o$j]) <= half & abs(det$y[o$j]) <= half
  c(ref = sum(o$within), det = sum(o$within & in_core))
}

# How often the observed matcher pairs the stems a detector truly missed (no
# own skilled detection within r): the greedy matcher with the height gate on
# the detections score_plot reads (core plus r). Returns n (missed stems), tp
# (those matched) and tp_all (all matched stems, score_plot's TP).
cs_missed_matches <- function(stems, det, r, half = CS_PH, tol_z_up = 8) {
  dr <- det[abs(det$x) <= half + r & abs(det$y) <= half + r, , drop = FALSE]
  m <- greedy_match(stems$E, stems$N, dr$x, dr$y, r, az = stems$height, bz = dr$z,
                    tol_z_up = tol_z_up)
  own <- cs_own_detection(stems, det, r)$within
  c(n = sum(!own), tp = sum(!own & m > 0), tp_all = sum(m > 0))
}

## ---- scoring one plot (needs sweep_lib.R) -------------------------------------
# For each reference, radius and detector: the observed counts from
# score_plot (greedy matcher with the height gate, tol_z_up = 8), the null as
# the mean counts over K toroidal shifts with the paper's offsets
# null_offset(2 (ph + r), null_seed(k), min_shift) and shift_detections(det,
# 0, 0, ph + r, offset), and the truth counts. One set of offsets per plot
# and radius serves every detector and reference. tp_core is recovered as the
# paper does, round(precision x n_det). The observed row also carries the
# missed stems and their chance matches (n_missed, tp_missed; NA on the other
# rows), and the matcher behind them must reproduce score_plot's TP.
# `detectors` is a data.frame with columns detector, s and f. A reference
# without stems in the core gives no rows (the paper skips such plots).
cs_score_plot <- function(plot, detectors, refs, tols, K, null_seed, min_shift = 8,
                          ph = CS_PH) {
  dets <- lapply(seq_len(nrow(detectors)), function(i)
    cs_detector(plot, detectors$s[i], detectors$f[i]))
  rows <- list()
  for (r in tols) {
    offs <- cs_offsets(r, K, null_seed, min_shift, ph)
    for (ref in refs) {
      st <- cs_reference(plot, ref, ph)
      if (!nrow(st)) next
      for (i in seq_len(nrow(detectors))) {
        rows[[length(rows) + 1]] <- data.frame(
          D = plot$D, ref = ref, tol = r, detector = detectors$detector[i],
          s = detectors$s[i], f = detectors$f[i],
          cs_score_cell(st, dets[[i]], r, offs, ph), stringsAsFactors = FALSE)
      }
    }
  }
  if (length(rows)) do.call(rbind, rows) else NULL
}

# The K shifts of one plot and radius: null_offset(2 (ph + r), null_seed(k)).
cs_offsets <- function(r, K, null_seed, min_shift = 8, ph = CS_PH)
  lapply(seq_len(K), function(k) null_offset(2 * (ph + r), null_seed(k), min_shift = min_shift))

# One cell (reference, detections, radius): observed, null (mean over the
# shifts `offs`) and truth counts, with the missed stems on the observed row.
cs_score_cell <- function(st, det, r, offs, ph = CS_PH) {
  counts <- function(sc) {
    n_det <- sc$n_det
    c(n_ref = sc$n_ref, n_det = n_det, TP = sc$TP,
      tp_core = if (n_det > 0) round(sc$precision * n_det) else 0)
  }
  score <- function(det) counts(score_plot(st, det, tol_xy = r, core_cx = 0, core_cy = 0,
                                           core_half = ph, method = "greedy", tol_z_up = 8))
  obs <- score(det)
  nul <- rowMeans(vapply(offs, function(o)
    score(shift_detections(det, 0, 0, ph + r, o)), numeric(4)))
  tru <- cs_true_skilled(st, det, r, ph)
  mm <- cs_missed_matches(st, det, r, ph)
  if (mm[["tp_all"]] != obs[["TP"]]) stop("Missed-stem matcher differs from score_plot")
  data.frame(variant = c("observed", "null", "truth"),
             n_ref = obs[["n_ref"]], n_det = c(obs[["n_det"]], nul[["n_det"]], obs[["n_det"]]),
             TP = c(obs[["TP"]], nul[["TP"]], tru[["ref"]]),
             tp_core = c(obs[["tp_core"]], nul[["tp_core"]], tru[["det"]]),
             n_missed = c(mm[["n"]], NA, NA), tp_missed = c(mm[["tp"]], NA, NA),
             stringsAsFactors = FALSE)
}

## ---- structure scenario: completeness and stand structure ----------------------
# Like cs_score_plot, for references at completeness p: `refs` is a
# data.frame with columns ref ("complete" or "half") and p, and `detectors`
# has columns detector, s, f and mode (cs_detector's; a detector of mode
# "unmapped" depends on p, so detections are built per reference), and
# optionally rate (mode "split"'s; 0 when absent). Rows carry the plot's
# pattern and the reference's p and mode beside the counts; a split
# detector's rate is carried by its name only.
cs_score_structure <- function(plot, detectors, refs, tols, K, null_seed, min_shift = 8,
                               ph = CS_PH) {
  rate <- if (is.null(detectors$rate)) rep(0, nrow(detectors)) else detectors$rate
  rows <- list()
  for (r in tols) {
    offs <- cs_offsets(r, K, null_seed, min_shift, ph)
    for (k in seq_len(nrow(refs))) {
      st <- cs_reference(plot, refs$ref[k], ph, p = refs$p[k])
      if (!nrow(st)) next
      for (i in seq_len(nrow(detectors))) {
        det <- cs_detector(plot, detectors$s[i], detectors$f[i], mode = detectors$mode[i],
                           p = refs$p[k], rate = rate[i])
        rows[[length(rows) + 1]] <- data.frame(
          D = plot$D, pattern = plot$pattern, ref = refs$ref[k], p = refs$p[k], tol = r,
          detector = detectors$detector[i], s = detectors$s[i], f = detectors$f[i],
          mode = detectors$mode[i], cs_score_cell(st, det, r, offs, ph),
          stringsAsFactors = FALSE)
      }
    }
  }
  if (length(rows)) do.call(rbind, rows) else NULL
}

# Mean neighbours without edge loss: for the reference stems in the core at
# completeness p, the summed number of other mapped trees (v < p, anywhere in
# the simulated square, which reaches 10 m beyond the core) within each
# distance d. With every core stem at least d from the square's edge
# (d <= CS_SIM_HALF - CS_PH), sum / n_ref is the mean number of other
# reference stems within d of a reference stem.
cs_neighbours <- function(plot, p = 1, d = c(2, 4), ph = CS_PH) {
  if (any(d > CS_SIM_HALF - ph)) stop("d reaches beyond the simulated square")
  tr <- plot$trees
  mapped <- if (p < 1) plot$v < p else rep(TRUE, nrow(tr))
  core <- mapped & abs(tr$x) <= ph & abs(tr$y) <= ph
  mx <- tr$x[mapped]; my <- tr$y[mapped]
  dd <- vapply(which(core), function(i) sqrt((mx - tr$x[i])^2 + (my - tr$y[i])^2),
               numeric(sum(mapped)))
  dd <- matrix(dd, nrow = sum(mapped))
  # Each stem is its own neighbour at distance 0; subtract it.
  c(n_ref = sum(core), setNames(vapply(d, function(r) sum(dd <= r) - sum(core), 1),
                                paste0("nb", d)))
}

## ---- neighbour counts in a square window (benchmark and simulation) ----------
# P(|X - Y| <= d) for X, Y independent and uniform in a w x w square (d <= w):
# (pi d^2 w^2 - 8/3 w d^3 + d^4 / 2) / w^4.
cs_square_pair_prob <- function(d, w) {
  if (any(d > w)) stop("d must not exceed the window side")
  (pi * d^2 * w^2 - 8 / 3 * w * d^3 + d^4 / 2) / w^4
}

# Pairs of points closer than or as close as d in a w x w square window, and
# the pairs expected under complete spatial randomness with the same number
# of points in the same window, n (n - 1) / 2 x P(|X - Y| <= d). The mean
# number of other points within d of a point is 2 pairs / n (2 expected / n
# for the random pattern), and pairs / expected is the window's ratio to
# random. One row per d.
cs_window_pairs <- function(x, y, d, w) {
  n <- length(x)
  dd <- if (n > 1) as.vector(stats::dist(cbind(x, y))) else numeric(0)
  data.frame(d = d, n = n, pairs = vapply(d, function(r) sum(dd <= r), 1),
             expected = n * (n - 1) / 2 * cs_square_pair_prob(d, w))
}

# Pools window pair counts per group and distance by summing counts, never
# averaging per-window ratios: mean other stems within d of a stem
# 2 sum(pairs) / sum(n), its random value 2 sum(expected) / sum(n), the
# ratio sum(pairs) / sum(expected) and the excess, observed minus random mean,
# 2 (sum(pairs) - sum(expected)) / sum(n), each of the last two with a 95%
# percentile interval from the master tables' plot resamples
# (mt_plot_weights, master_tables_lib.R; the same resamples for both): units
# (plots) resampled within strata (sites). For a cluster process with
# clusters of a fixed size the ratio falls as density rises and the excess
# does not; a random share of the trees mapped scales the excess by that
# share and leaves the ratio unchanged. `rows` has
# columns group, stratum, unit, d, n, pairs and expected, one row per window
# and distance; a unit may hold several windows, which are resampled together.
cs_pool_pairs <- function(rows, n_boot = MT_N_BOOT, seed = MT_SEED) {
  out <- list()
  for (g in unique(rows$group)) for (d in unique(rows$d)) {
    x <- rows[rows$group == g & rows$d == d, , drop = FALSE]
    id <- paste(x$stratum, x$unit, sep = "::")
    W <- mt_plot_weights(x$stratum, x$unit, n_boot, seed)
    agg <- rowsum(cbind(n = x$n, pairs = x$pairs, expected = x$expected), id)[rownames(W), , drop = FALSE]
    ratio_draws <- crossprod(W, agg[, "pairs"]) / crossprod(W, agg[, "expected"])
    iv <- mt_interval(as.vector(ratio_draws))
    excess_draws <- 2 * (crossprod(W, agg[, "pairs"]) - crossprod(W, agg[, "expected"])) /
      crossprod(W, agg[, "n"])
    ive <- mt_interval(as.vector(excess_draws))
    tot <- colSums(agg)
    out[[length(out) + 1]] <- data.frame(
      group = g, d = d, units = nrow(W), windows = nrow(x), n = tot[["n"]],
      pairs = tot[["pairs"]], expected = tot[["expected"]],
      mean_observed = 2 * tot[["pairs"]] / tot[["n"]], mean_random = 2 * tot[["expected"]] / tot[["n"]],
      ratio = tot[["pairs"]] / tot[["expected"]], ratio_lower = iv$lower, ratio_upper = iv$upper,
      excess = 2 * (tot[["pairs"]] - tot[["expected"]]) / tot[["n"]],
      excess_lower = ive$lower, excess_upper = ive$upper,
      stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

# Plot ids of the simulation: "D<DDD>_<iiii>" for the inhibited pattern (the
# plots of scenarios 1-3), prefixed "M4_" or "M8_" for the clustered ones.
CS_PATTERN_CODE <- c(inhibited = "", clustered_4m = "M4_", clustered_8m = "M8_")
cs_plot_id <- function(D, i, pattern = "inhibited")
  paste0(CS_PATTERN_CODE[[pattern]], sprintf("D%03d_%04d", D, i))

## ---- corrected scores -----------------------------------------------------------
# (observed - null) / (1 - null), elementwise (estimates or bootstrap draws).
cs_corrected <- function(obs, null) (obs - null) / (1 - null)

## ---- paired leads (needs master_tables_lib.R) ------------------------------------
# Paired leads on one setting's pooled scores `s` (mt_boot_scores over the
# groups "variant|detector", one resample matrix shared by every detector):
# for each row of `cmp` (columns comparison, leader and base) whose two
# detectors are both scored, leader minus base of the true skilled share
# (true_diff), observed F1, corrected F1, corrected recall, observed recall
# and oracle F1, each with the 95% percentile interval of the same
# difference over the shared plot resamples (a paired interval). `key` is
# the setting as a one-row data.frame. NULL when no comparison applies.
cs_paired_leads <- function(s, cmp, key) {
  E <- function(m, v, a) s$estimate[[m]][match(paste(v, a, sep = "|"), s$groups)]
  Dr <- function(m, v, a) s$draws[[m]][, paste(v, a, sep = "|")]
  dets <- unique(sub("^[^|]*\\|", "", s$groups))
  q <- list(
    true_diff = list(function(b) E("recall", "truth", b), function(b) Dr("recall", "truth", b)),
    obs_F1_lead = list(function(b) E("F1", "observed", b), function(b) Dr("F1", "observed", b)),
    corr_F1_lead = list(function(b) cs_corrected(E("F1", "observed", b), E("F1", "null", b)),
                        function(b) cs_corrected(Dr("F1", "observed", b), Dr("F1", "null", b))),
    corr_recall_lead = list(function(b) cs_corrected(E("recall", "observed", b), E("recall", "null", b)),
                            function(b) cs_corrected(Dr("recall", "observed", b), Dr("recall", "null", b))),
    obs_recall_lead = list(function(b) E("recall", "observed", b), function(b) Dr("recall", "observed", b)),
    oracle_F1_lead = list(function(b) E("F1", "truth", b), function(b) Dr("F1", "truth", b)))
  do.call(rbind, lapply(which(cmp$leader %in% dets & cmp$base %in% dets), function(i) {
    a <- cmp$leader[i]; b0 <- cmp$base[i]
    row <- data.frame(key, comparison = cmp$comparison[i], plots = s$estimate$n_plots[1],
                      stringsAsFactors = FALSE)
    for (k in names(q)) {
      row[[k]] <- q[[k]][[1]](a) - q[[k]][[1]](b0)
      iv <- mt_interval(q[[k]][[2]](a) - q[[k]][[2]](b0))
      row[[paste0(k, "_lower")]] <- iv$lower; row[[paste0(k, "_upper")]] <- iv$upper
    }
    row
  }))
}
