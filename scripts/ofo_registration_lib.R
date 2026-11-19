# Open Forest Observatory preflight: rigid registration of a stem map to the
# canopy surface of its flight, as declared in docs/ofo-preflight-protocol.md
# ("Registration" and "Tests of the registration"). Pure functions; the driver
# is scripts/preflight_ofo_registration.R. No tree detector runs here: the
# estimate uses only a canopy-top raster and stem-map attributes.
# ofo_register() draws its half-splits with seed_for() from model_bench_lib.R,
# which the caller sources.

# Every rule and threshold of the declared method. Fixed before any test.
OFO_REG <- list(
  max_shift = 12, step = 0.5,          # search window +/-12 m at 0.5 m steps
  res = 0.5, subcircle = 0.2,          # highest-return raster
  window = 5L,                         # 5 x 5 moving maximum -> local canopy top
  min_ground = 10L, max_height = 110,  # TIN normalisation of a raw cloud
  height_floor = 10, height_tol = 2, height_rel = 0.15,
  dbh_floor = 10,
  min_stems = 15L, min_contrast = 0.10, max_residual = 2.0, splits = 20L,
  # Objectives within this of the maximum are ties: equal Spearman values
  # reached by different rank vectors can differ in the last bits.
  tie_tol = 1e-12,
  # Threshold comparisons absorb rounding: a share difference of exactly 0.10
  # evaluates to 0.0999999999999999 in floating point.
  eps = 1e-9)

# Pass rules of the known-truth test (1) and of the agreement test (3).
OFO_TESTS <- list(
  known_truth = list(min_accepted = 20L, max_median_error = 1.0,
                     max_error = 2.0, min_share = 0.90),
  agreement = list(max_distance = 2.0, min_share = 0.80, min_plots = 10L))

## ---- surface -----------------------------------------------------------------
# Height-normalises a raw cloud with a TIN of its class-2 returns and keeps
# heights in [0, 110] m. Fewer than 10 ground returns stop with "no_ground".
# lidR runs single-threaded: TIN normalisation differs slightly by thread count.
ofo_normalize <- function(las) {
  if (sum(las$Classification == 2L, na.rm = TRUE) < OFO_REG$min_ground)
    stop("no_ground", call. = FALSE)
  threads <- lidR::get_lidr_threads()
  lidR::set_lidr_threads(1L)
  on.exit(lidR::set_lidr_threads(threads), add = TRUE)
  nrm <- lidR::normalize_height(las, lidR::tin(), na.rm = TRUE)
  keep <- nrm$Z >= 0 & nrm$Z <= OFO_REG$max_height
  lidR::filter_poi(nrm, keep)
}

# The local canopy top M: a 0.5 m highest-return raster (0.2 m subcircle,
# empty cells 0), then its 5 x 5 moving maximum. Takes an already-normalised
# LAS or that highest-return raster. Heights below 0 count as 0.
ofo_canopy_top <- function(x) {
  if (inherits(x, "LAS")) {
    threads <- lidR::get_lidr_threads()
    lidR::set_lidr_threads(1L)
    on.exit(lidR::set_lidr_threads(threads), add = TRUE)
    x <- lidR::rasterize_canopy(x, res = OFO_REG$res,
                                algorithm = lidR::p2r(OFO_REG$subcircle))
  }
  if (!inherits(x, "SpatRaster")) x <- terra::rast(x)
  v <- terra::values(x, mat = FALSE)
  v[is.na(v) | v < 0] <- 0
  terra::values(x) <- v
  terra::focal(x, w = OFO_REG$window, fun = "max", na.rm = TRUE)
}

## ---- shifts and signals --------------------------------------------------------
# All shifts over +/-max in both axes at `step` (2,401 rows by default).
ofo_shift_grid <- function(max = OFO_REG$max_shift, step = OFO_REG$step) {
  k <- seq(-round(max / step), round(max / step)) * step
  g <- expand.grid(dx = k, dy = k)
  data.frame(dx = g$dx, dy = g$dy)
}

# n x nrow(grid) matrix: M at stem i moved by shift j. Cells are half-open
# [xmin, xmax) x (ymin, ymax]; a position outside the raster gives 0.
ofo_signal_matrix <- function(M, x, y, grid) {
  stopifnot(length(x) == length(y))
  vals <- terra::as.matrix(M, wide = TRUE)            # row 1 is the top row
  vals[is.na(vals)] <- 0
  r <- terra::res(M)
  col <- floor((outer(x, grid$dx, "+") - terra::xmin(M)) / r[1]) + 1
  row <- floor((terra::ymax(M) - outer(y, grid$dy, "+")) / r[2]) + 1
  ok <- col >= 1 & col <= ncol(vals) & row >= 1 & row <= nrow(vals)
  V <- matrix(0, length(x), nrow(grid))
  V[ok] <- vals[cbind(row[ok], col[ok])]
  V
}

# Height signal: the share of stems with |M_i(s) - h_i| <= max(2, 0.15 h_i).
ofo_objective_height <- function(V, h) {
  tol <- pmax(OFO_REG$height_tol, OFO_REG$height_rel * h)
  colMeans(abs(V - h) <= tol)
}

# Diameter-rank signal: Spearman correlation of diameter and M_i(s) per shift,
# as the Pearson correlation of average ranks. A shift whose M values (or
# diameters) do not vary has no correlation: NA.
ofo_objective_rank <- function(V, d) {
  n <- length(d)
  mid <- (n + 1) / 2                                  # exact mean of average ranks
  rd <- rank(d) - mid
  R <- matrix(apply(V, 2, rank), nrow = n) - mid
  den <- sqrt(sum(rd^2) * colSums(R^2))
  out <- colSums(rd * R) / den
  out[!(den > 0)] <- NA_real_
  out
}

# The shift with the highest objective (NA counts as -Inf). Ties go to the
# shortest shift, then the smallest dx, then the smallest dy.
ofo_best_shift <- function(obj, grid) {
  o <- ifelse(is.na(obj), -Inf, obj)
  top <- max(o)
  cand <- which(o >= top - OFO_REG$tie_tol)
  len2 <- grid$dx[cand]^2 + grid$dy[cand]^2           # multiples of 0.25: exact
  i <- cand[order(len2, grid$dx[cand], grid$dy[cand])][1]
  list(index = i, dx = grid$dx[i], dy = grid$dy[i], objective = obj[i])
}

## ---- estimate, residual, acceptance -------------------------------------------------
ofo_split_seed <- function(plot, k) {
  if (!exists("seed_for", mode = "function"))
    stop("seed_for() not found; source model_bench_lib.R first")
  seed_for("registration", plot, NA, k)
}

# One random half-split of n stems: floor(n / 2) stems and the rest.
ofo_half_split <- function(n, seed) {
  set.seed(seed)
  perm <- sample.int(n)
  m <- floor(n / 2)
  list(a = perm[seq_len(m)], b = perm[seq_len(n - m) + m])
}

# Distance between the estimates of the two halves, for k = 1..splits.
ofo_split_distances <- function(V, size, grid, signal, plot, splits = OFO_REG$splits) {
  fun <- ofo_objective(signal)
  vapply(seq_len(splits), function(k) {
    h <- ofo_half_split(nrow(V), ofo_split_seed(plot, k))
    a <- ofo_best_shift(fun(V[h$a, , drop = FALSE], size[h$a]), grid)
    b <- ofo_best_shift(fun(V[h$b, , drop = FALSE], size[h$b]), grid)
    sqrt((a$dx - b$dx)^2 + (a$dy - b$dy)^2)
  }, numeric(1))
}

ofo_objective <- function(signal)
  switch(signal, height = ofo_objective_height, rank = ofo_objective_rank,
         stop("Unknown signal: ", signal))

# Registers one plot with one signal. V is the signal matrix of its signal
# stems, `size` their heights (height signal) or diameters (rank signal).
# Plots with fewer than 15 signal stems are not run. Returns one row.
ofo_register <- function(V, size, grid, signal, plot, splits = OFO_REG$splits) {
  fun <- ofo_objective(signal)
  n <- nrow(V)
  out <- data.frame(signal = signal, n_signal = n, dx = NA_real_, dy = NA_real_,
                    shift_m = NA_real_, objective_zero = NA_real_,
                    objective_best = NA_real_, objective_median = NA_real_,
                    contrast = NA_real_, residual_m = NA_real_, on_edge = NA,
                    accepted = FALSE, reject_reason = "n", stringsAsFactors = FALSE)
  if (n < OFO_REG$min_stems) return(out)
  obj <- fun(V, size)
  best <- ofo_best_shift(obj, grid)
  med <- if (all(is.na(obj))) NA_real_ else stats::median(obj, na.rm = TRUE)
  out$dx <- best$dx; out$dy <- best$dy
  out$shift_m <- sqrt(best$dx^2 + best$dy^2)
  out$objective_zero <- obj[which(grid$dx == 0 & grid$dy == 0)]
  out$objective_best <- best$objective
  out$objective_median <- med
  out$contrast <- best$objective - med
  out$residual_m <- stats::median(ofo_split_distances(V, size, grid, signal, plot, splits))
  edge <- max(abs(grid$dx), abs(grid$dy))
  out$on_edge <- abs(best$dx) == edge || abs(best$dy) == edge
  acc <- ofo_accept(n, out$on_edge, out$contrast, out$residual_m)
  out$accepted <- acc$accepted
  out$reject_reason <- acc$reason
  out
}

# Acceptance: >= 15 signal stems, estimate not on the window's edge, contrast
# >= 0.10 and residual <= 2.0 m. A missing contrast or residual fails. The
# reason lists every failed rule, joined with ";" (empty when accepted).
ofo_accept <- function(n, on_edge, contrast, residual_m) {
  fail <- c(n = !isTRUE(n >= OFO_REG$min_stems),
            on_edge = isTRUE(on_edge),
            contrast = !isTRUE(contrast >= OFO_REG$min_contrast - OFO_REG$eps),
            residual = !isTRUE(residual_m <= OFO_REG$max_residual + OFO_REG$eps))
  list(accepted = !any(fail), reason = paste(names(fail)[fail], collapse = ";"))
}

## ---- stem selection ---------------------------------------------------------------
# Height-signal stems: live, with a measured height at least the larger of
# 10 m and the median measured height of the plot's live stems.
ofo_height_stems <- function(live, height) {
  m <- live %in% TRUE & is.finite(height)
  if (!any(m)) return(m)
  m & height >= max(OFO_REG$height_floor, stats::median(height[m]))
}

# Catalogue stems of one plot for the two signals. `tr` holds the plot's rows
# of trees.csv; `status_recorded` and `live_floor_cm` come from plots.csv.
# Where no status was recorded every stem counts as live (held-out test only),
# so the reference flag is recomputed with the plot's live floor (10 if none).
ofo_catalog_stems <- function(tr, status_recorded, live_floor_cm) {
  tr <- as.data.frame(tr)[is.finite(tr$x) & is.finite(tr$y), , drop = FALSE]
  live <- tr$live %in% TRUE
  ref <- tr$ref %in% TRUE
  if (!isTRUE(as.logical(status_recorded))) {
    floor <- max(OFO_REG$dbh_floor, if (is.finite(live_floor_cm)) live_floor_cm else 10)
    live <- rep(TRUE, nrow(tr))
    ref <- tr$is_tree %in% TRUE & is.finite(tr$dbh) & tr$dbh >= floor & tr$inside %in% TRUE
  }
  data.frame(x = tr$x, y = tr$y, height = tr$height, dbh = tr$dbh, live = live,
             ref = ref, height_stem = ofo_height_stems(live, tr$height),
             rank_stem = ref & is.finite(tr$dbh))
}

## ---- declared tests ---------------------------------------------------------------
# Test 1 for one signal: >= 20 accepted plots, median error of accepted plots
# <= 1.0 m, and >= 90% of accepted plots within 2.0 m (compared in counts).
ofo_known_truth_signal <- function(accepted, error_m, run = rep(TRUE, length(accepted))) {
  r <- OFO_TESTS$known_truth
  acc <- accepted %in% TRUE
  e <- error_m[acc]
  n_acc <- sum(acc)
  n_within <- sum(e <= r$max_error + OFO_REG$eps)
  med <- if (n_acc) stats::median(e) else NA_real_
  list(n_plots = length(acc), n_run = sum(run %in% TRUE), n_accepted = n_acc,
       median_error_m = med, n_within_2m = n_within,
       share_within_2m = if (n_acc) n_within / n_acc else NA_real_,
       pass = n_acc >= r$min_accepted && isTRUE(med <= r$max_median_error + OFO_REG$eps) &&
         n_within * 100 >= round(r$min_share * 100) * n_acc)
}

# Test 1 over a registration_neon table (columns signal, n_signal, accepted,
# error_m): one entry per signal.
ofo_known_truth_test <- function(neon) {
  sapply(c("height", "rank"), function(s) {
    x <- neon[neon$signal == s, , drop = FALSE]
    ofo_known_truth_signal(x$accepted, x$error_m, x$n_signal >= OFO_REG$min_stems)
  }, simplify = FALSE)
}

# Distances between the height and rank estimates on catalogue plots with
# measured heights where both signals are accepted. `cat` is the
# registration_catalog table, `measured` the plot_ids with measured heights.
ofo_agreement_pairs <- function(cat, measured) {
  cat <- as.data.frame(cat)
  a <- cat[cat$accepted %in% TRUE & cat$plot_id %in% measured, , drop = FALSE]
  h <- a[a$signal == "height", c("plot_id", "dx", "dy")]
  r <- a[a$signal == "rank", c("plot_id", "dx", "dy")]
  m <- merge(h, r, by = "plot_id", suffixes = c("_height", "_rank"))
  m$distance_m <- sqrt((m$dx_height - m$dx_rank)^2 + (m$dy_height - m$dy_rank)^2)
  m
}

# Test 3: at least 10 such plots, and at least 80% of them within 2.0 m.
ofo_agreement_test <- function(distance_m) {
  r <- OFO_TESTS$agreement
  n <- length(distance_m)
  k <- sum(distance_m <= r$max_distance + OFO_REG$eps)
  list(n_plots = n, n_within_2m = k, share_within_2m = if (n) k / n else NA_real_,
       pass = n >= r$min_plots && k * 100 >= round(r$min_share * 100) * n)
}

# The height signal is admitted on test 1; the rank signal on tests 1 and 3.
ofo_admitted_signals <- function(known_truth, agreement)
  list(height = isTRUE(known_truth$height$pass),
       rank = isTRUE(known_truth$rank$pass) && isTRUE(agreement$pass))

## ==== Amendment 1: development/confirmation split and composites ===============
# docs/ofo-preflight-protocol.md, "Amendment 1". Every function here needs
# seed_for() from model_bench_lib.R.

# Splits the known-truth plots. Within each site x plot type, plots ordered by
# seed_for("split", plot, NA) (ties by plot ID) take ranks 1, 2, ...; odd ranks
# are development plots, even ranks confirmation plots. `pop` has columns
# site, plot, plot_type. Returns pop with split_seed, split_rank and set.
ofo_split_plots <- function(pop) {
  pop <- as.data.frame(pop, stringsAsFactors = FALSE)
  pop$split_seed <- vapply(pop$plot, function(p) seed_for("split", p, NA), integer(1))
  pop <- pop[order(pop$site, pop$plot_type, pop$split_seed, pop$plot), , drop = FALSE]
  pop$split_rank <- stats::ave(seq_len(nrow(pop)), pop$site, pop$plot_type, FUN = seq_along)
  pop$set <- ifelse(pop$split_rank %% 2L == 1L, "development", "confirmation")
  rownames(pop) <- NULL
  pop
}

# Group index of n ordered plots: consecutive groups of three, a remainder of
# one or two joining the last group. Two plots form one group of two. A single
# plot forms no composite (NA): it would repeat the plot unit with the same
# offset seed and members, adding no information.
ofo_group_threes <- function(n) {
  if (n <= 1L) return(rep(NA_integer_, n))
  if (n == 2L) return(c(1L, 1L))
  g <- (seq_len(n) - 1L) %/% 3L + 1L
  pmin(g, n %/% 3L)
}

# Composites of one split table (ofo_split_plots()). Within each set x site,
# plots ordered by seed_for("composite", plot, NA) (ties by plot ID) form
# ofo_group_threes() groups. Returns one row per composite: unit
# ("C-<first plot>"), set, site, offset_key (its first plot) and members
# (plot IDs in that order, ";"-joined).
ofo_composites <- function(split) {
  split$comp_seed <- vapply(split$plot, function(p) seed_for("composite", p, NA), integer(1))
  out <- list()
  for (key in unique(paste(split$set, split$site))) {
    x <- split[paste(split$set, split$site) == key, , drop = FALSE]
    x <- x[order(x$comp_seed, x$plot), , drop = FALSE]
    g <- ofo_group_threes(nrow(x))
    for (k in sort(unique(stats::na.omit(g)))) {
      m <- x$plot[g %in% k]
      out[[length(out) + 1L]] <- data.frame(
        unit = paste0("C-", m[1]), set = x$set[1], site = x$site[1], offset_key = m[1],
        members = paste(m, collapse = ";"), n_members = length(m), stringsAsFactors = FALSE)
    }
  }
  if (!length(out))
    return(data.frame(unit = character(), set = character(), site = character(),
                      offset_key = character(), members = character(), n_members = integer()))
  do.call(rbind, out)
}

# Every unit of Amendment 1: one per plot (kind "plot") and one per composite
# (kind "composite"). `pop` has site, plot, plot_type.
ofo_units <- function(pop) {
  sp <- ofo_split_plots(pop)
  pl <- data.frame(unit = sp$plot, set = sp$set, kind = "plot", site = sp$site,
                   members = sp$plot, offset_key = sp$plot, n_members = 1L,
                   plot_type = sp$plot_type, split_rank = sp$split_rank,
                   stringsAsFactors = FALSE)
  co <- ofo_composites(sp)
  co <- data.frame(unit = co$unit, set = co$set, kind = rep("composite", nrow(co)),
                   site = co$site, members = co$members, offset_key = co$offset_key,
                   n_members = co$n_members, plot_type = rep(NA_character_, nrow(co)),
                   split_rank = rep(NA_integer_, nrow(co)), stringsAsFactors = FALSE)
  u <- rbind(pl, co)
  u <- u[order(match(u$set, c("development", "confirmation")), u$kind != "plot",
               u$site, u$unit), , drop = FALSE]
  rownames(u) <- NULL
  u
}

# The known offset of a unit: uniform within +/-8 m per axis, seeded by
# seed_for("offset2", <plot or first plot>, NA), drawn as in test 1.
ofo_unit_offset <- function(offset_key, max = 8) {
  set.seed(seed_for("offset2", offset_key, NA))
  stats::runif(2, -max, max)
}

## ==== Amendment 1: method 2 (redesigned estimator and gate) ======================
# One rigid shift per unit from stem positions with heights (height signal) or
# diameters (diameter signal, heights ignored) and the canopy surface of the
# unit's cloud(s). No tree detector and no local-maximum search on the surface:
# the stems are compared with the surface over the whole search window.
# A unit is a plot or a composite of plots; a composite pools its members'
# contributions, each member on its own surface, under one common shift.

# Search and resampling constants shared by every method-2 variant.
OFO_REG2_SEARCH <- list(
  max_shift = 12, step = 0.5,          # +/-12 m at 0.5 m: the 2,401 declared shifts
  res = 0.5, subcircle = 0.2,          # highest-return raster, as declared
  splits = 20L,                        # half-splits for the residual, as declared
  subsamples = 20L, sub_frac = 0.8,    # 80% subsamples for the stability statistic
  far_m = 3,                           # radius outside which the second peak is sought
  centroid_tau = 0.1,                  # near-maximal set: within 10% of the contrast
  tie_tol = 1e-12, eps = 1e-9)

# Variants tried in development (STAGE=dev), per signal. `objective`: share (declared
# tolerance share), kern (Gaussian kernel of the height difference), corr
# (Pearson correlation of stem size with the surface at the stems), ncc
# (masked normalised cross-correlation of a rendered stem map with the
# surface). `surface`: raw, max<k> (k x k moving maximum) or gauss<sigma>.
# `estimator`: peak (arg-max, sub-grid refined) or centroid (centre of the
# near-maximal set). The centroid's threshold is relative to the median over
# the window, which changes with where the truth lies in the window, so it is
# not translation-equivariant: reported, never selected. NCC renders each stem
# as a paraboloid crown of amplitude `amp` (size, sqrt or unit) and radius
# max(1, r0 + r1 * size); its mask is the union of discs of `mask_m` around
# the stems.
ofo2_variant <- function(objective, surface = "raw", estimator = "peak", ...)
  c(list(objective = objective, surface = surface, estimator = estimator), list(...))

OFO_REG2_VARIANTS <- list(
  height = list(
    share_max5_peak = ofo2_variant("share", "max5"),
    share_max5_centroid = ofo2_variant("share", "max5", "centroid"),
    kern_raw = ofo2_variant("kern", "raw", sigma0 = 1.5, sigma_rel = 0.1),
    kern_max3 = ofo2_variant("kern", "max3", sigma0 = 1.5, sigma_rel = 0.1),
    kern_gauss0.5 = ofo2_variant("kern", "gauss0.5", sigma0 = 1.5, sigma_rel = 0.1),
    kern_gauss1 = ofo2_variant("kern", "gauss1", sigma0 = 1.5, sigma_rel = 0.1),
    corr_raw = ofo2_variant("corr", "raw", transform = "identity"),
    corr_gauss1 = ofo2_variant("corr", "gauss1", transform = "identity"),
    corr_gauss1.5 = ofo2_variant("corr", "gauss1.5", transform = "identity"),
    ncc = ofo2_variant("ncc", r0 = 0.5, r1 = 0.1, mask_m = 4, amp = "size"),
    ncc_r2 = ofo2_variant("ncc", r0 = 2, r1 = 0, mask_m = 4, amp = "size"),
    ncc_r015 = ofo2_variant("ncc", r0 = 0.5, r1 = 0.15, mask_m = 4, amp = "size"),
    ncc_r007 = ofo2_variant("ncc", r0 = 0.5, r1 = 0.07, mask_m = 4, amp = "size"),
    ncc_mask3 = ofo2_variant("ncc", r0 = 0.5, r1 = 0.1, mask_m = 3, amp = "size"),
    ncc_mask5 = ofo2_variant("ncc", r0 = 0.5, r1 = 0.1, mask_m = 5, amp = "size"),
    ncc_mask6 = ofo2_variant("ncc", r0 = 0.5, r1 = 0.1, mask_m = 6, amp = "size"),
    ncc_gauss0.5 = ofo2_variant("ncc", "gauss0.5", r0 = 0.5, r1 = 0.1, mask_m = 4,
                                amp = "size"),
    ncc_unit = ofo2_variant("ncc", r0 = 0.5, r1 = 0.1, mask_m = 4, amp = "unit"),
    ncc_centroid = ofo2_variant("ncc", "raw", "centroid", r0 = 0.5, r1 = 0.1, mask_m = 4,
                                amp = "size")),
  # the diameter signal keeps the declared signal name "rank"; heights ignored
  rank = list(
    corr_raw = ofo2_variant("corr", "raw", transform = "log"),
    corr_gauss1 = ofo2_variant("corr", "gauss1", transform = "log"),
    corr_gauss1.5 = ofo2_variant("corr", "gauss1.5", transform = "log"),
    corr_gauss2 = ofo2_variant("corr", "gauss2", transform = "log"),
    corr_max5 = ofo2_variant("corr", "max5", transform = "log"),
    ncc = ofo2_variant("ncc", r0 = 1, r1 = 0.05, mask_m = 4, amp = "size"),
    ncc_r01 = ofo2_variant("ncc", r0 = 0, r1 = 0.1, mask_m = 4, amp = "size"),
    ncc_r2 = ofo2_variant("ncc", r0 = 2, r1 = 0, mask_m = 4, amp = "size"),
    ncc_r004 = ofo2_variant("ncc", r0 = 1.5, r1 = 0.04, mask_m = 4, amp = "size"),
    ncc_r007 = ofo2_variant("ncc", r0 = 0.5, r1 = 0.07, mask_m = 4, amp = "size"),
    ncc_mask3 = ofo2_variant("ncc", r0 = 1, r1 = 0.05, mask_m = 3, amp = "size"),
    ncc_mask5 = ofo2_variant("ncc", r0 = 1, r1 = 0.05, mask_m = 5, amp = "size"),
    ncc_sqrt = ofo2_variant("ncc", r0 = 1, r1 = 0.05, mask_m = 4, amp = "sqrt"),
    ncc_unit = ofo2_variant("ncc", r0 = 1, r1 = 0.05, mask_m = 4, amp = "unit"),
    ncc_centroid = ofo2_variant("ncc", "raw", "centroid", r0 = 1, r1 = 0.05, mask_m = 4,
                                amp = "size")))

## ---- method 2: surface ------------------------------------------------------------
# The canopy surface of one cloud as list(m, xmin, ymax, res), m with row 1 at
# the top. Highest return per 0.5 m cell (0.2 m subcircle); heights below 0
# are 0; an empty cell takes the mean of its non-empty 3 x 3 neighbours, else
# 0 (sparse returns leave holes inside crowns). `smooth`: raw, max<k> or
# gauss<sigma> (Gaussian of sigma metres, normalised at the edges). Takes an
# already-normalised LAS or a highest-return SpatRaster.
ofo2_surface <- function(x, smooth = "raw") {
  if (inherits(x, "LAS")) {
    threads <- lidR::get_lidr_threads()
    lidR::set_lidr_threads(1L)
    on.exit(lidR::set_lidr_threads(threads), add = TRUE)
    x <- lidR::rasterize_canopy(x, res = OFO_REG2_SEARCH$res,
                                algorithm = lidR::p2r(OFO_REG2_SEARCH$subcircle))
  }
  if (!inherits(x, "SpatRaster")) x <- terra::rast(x)
  x <- x[[1]]
  v <- terra::values(x, mat = FALSE)
  v[is.finite(v) & v < 0] <- 0
  v[!is.finite(v)] <- NA
  terra::values(x) <- v
  f <- terra::focal(x, w = 3, fun = "mean", na.rm = TRUE, na.policy = "only")
  v <- terra::values(f, mat = FALSE)
  v[!is.finite(v)] <- 0
  terra::values(f) <- v
  s <- if (identical(smooth, "raw")) f
    else if (grepl("^max[0-9]+$", smooth))
      terra::focal(f, w = as.integer(sub("max", "", smooth)), fun = "max", na.rm = TRUE)
    else if (grepl("^gauss[0-9.]+$", smooth)) {
      w <- terra::focalMat(f, as.numeric(sub("gauss", "", smooth)), "Gauss")
      one <- f; terra::values(one) <- 1
      terra::focal(f, w = w, fun = "sum", na.rm = TRUE) /
        terra::focal(one, w = w, fun = "sum", na.rm = TRUE)
    } else stop("Unknown surface: ", smooth)
  m <- terra::as.matrix(s, wide = TRUE)
  m[!is.finite(m)] <- 0
  list(m = m, xmin = terra::xmin(s), ymax = terra::ymax(s), res = terra::res(s)[1])
}

## ---- method 2: point objectives (share, kern, corr) -----------------------------------
# n x nrow(grid) matrix of the surface at stem i moved by shift j, bilinear
# between cell centres; outside the raster the surface is 0.
ofo2_lookup <- function(S, x, y, grid) {
  fx <- (outer(x, grid$dx, "+") - S$xmin) / S$res - 0.5
  fy <- (S$ymax - outer(y, grid$dy, "+")) / S$res - 0.5
  nr <- nrow(S$m); nc <- ncol(S$m)
  j0 <- floor(fx); i0 <- floor(fy); wx <- fx - j0; wy <- fy - i0
  at <- function(i, j) {
    ok <- i >= 0 & i < nr & j >= 0 & j < nc
    v <- numeric(length(i))
    v[ok] <- S$m[cbind(i[ok] + 1, j[ok] + 1)]
    v
  }
  v <- (1 - wx) * (1 - wy) * at(i0, j0) + wx * (1 - wy) * at(i0, j0 + 1) +
    (1 - wx) * wy * at(i0 + 1, j0) + wx * wy * at(i0 + 1, j0 + 1)
  matrix(v, length(x), nrow(grid))
}

# Objective per shift from the stacked lookups V (rows = stems) and sizes.
ofo2_point_objective <- function(V, size, cfg) {
  switch(cfg$objective,
    share = colMeans(abs(V - size) <= pmax(OFO_REG$height_tol, OFO_REG$height_rel * size)),
    kern = {
      sg <- pmax(cfg$sigma0, cfg$sigma_rel * size)
      colMeans(exp(-0.5 * ((V - size) / sg)^2))
    },
    corr = {
      z <- if (identical(cfg$transform, "log")) log(size) else size
      z <- z - mean(z)
      Vc <- V - rep(colMeans(V), each = nrow(V))
      den <- sqrt(sum(z^2) * colSums(Vc^2))
      o <- colSums(z * Vc) / den
      o[!(den > 0)] <- NA_real_
      o
    },
    stop("Not a point objective: ", cfg$objective))
}

## ---- method 2: masked normalised cross-correlation ----------------------------------
# Stem rendering of one member: a paraboloid crown amp * (1 - d^2 / r^2) per
# stem (the canopy of overlapping crowns is their maximum) and a mask of the
# cells within mask_m of any stem, on the surface's cell grid. The window is
# fixed by all the member's stems so every subset renders on the same cells.
ofo2_ncc_member <- function(S, x, y, size, cfg, L) {
  res <- S$res
  amp <- switch(cfg$amp, size = size, sqrt = sqrt(size), unit = rep(1, length(size)),
                stop("Unknown amplitude: ", cfg$amp))
  rad <- pmax(1, cfg$r0 + cfg$r1 * size)
  ext <- max(c(rad, cfg$mask_m)) + res
  c0 <- floor((min(x) - ext - S$xmin) / res); c1 <- ceiling((max(x) + ext - S$xmin) / res)
  r0 <- floor((S$ymax - max(y) - ext) / res); r1 <- ceiling((S$ymax - min(y) + ext) / res)
  cols <- c0:(c1 - 1L); rows <- r0:(r1 - 1L)                  # 0-based raster cells
  # canopy window: the stem window grown by L cells; outside the raster 0
  rr <- (r0 - L):(r1 - 1L + L); cc <- (c0 - L):(c1 - 1L + L)
  B <- matrix(0, length(rr), length(cc))
  okr <- rr >= 0 & rr < nrow(S$m); okc <- cc >= 0 & cc < ncol(S$m)
  B[okr, okc] <- S$m[rr[okr] + 1L, cc[okc] + 1L]
  P <- c(stats::nextn(nrow(B)), stats::nextn(ncol(B)))
  pad <- function(A) { Z <- matrix(0, P[1], P[2]); Z[seq_len(nrow(A)), seq_len(ncol(A))] <- A; Z }
  list(x = x, y = y, amp = amp, rad = rad, mask_m = cfg$mask_m, L = L, P = P,
       xc = S$xmin + (cols + 0.5) * res, yc = S$ymax - (rows + 0.5) * res,
       fB = stats::fft(pad(B)), fB2 = stats::fft(pad(B^2)), pad = pad)
}

# Sufficient statistics of one member for the stems `use` (indices into the
# member): sums over the mask of S * C_s, C_s, C_s^2 per lag, and of S, S^2,
# 1, where C_s is the surface moved by the lag. Lag [k, j] samples the canopy
# (k - 1 - L) rows below and (j - 1 - L) columns right of each stem cell.
ofo2_ncc_stats <- function(mb, use) {
  S <- matrix(0, length(mb$yc), length(mb$xc))
  M <- matrix(FALSE, length(mb$yc), length(mb$xc))
  for (i in use) {
    reach <- max(mb$rad[i], mb$mask_m)
    jj <- which(abs(mb$xc - mb$x[i]) <= reach); ii <- which(abs(mb$yc - mb$y[i]) <= reach)
    if (!length(jj) || !length(ii)) next
    d2 <- outer((mb$yc[ii] - mb$y[i])^2, (mb$xc[jj] - mb$x[i])^2, "+")
    S[ii, jj] <- pmax(S[ii, jj], mb$amp[i] * pmax(0, 1 - d2 / mb$rad[i]^2))
    M[ii, jj] <- M[ii, jj] | d2 <= mb$mask_m^2
  }
  Mn <- M * 1
  MS <- Mn * S
  n <- 2L * mb$L + 1L
  xc <- function(fA, fB) Re(stats::fft(Conj(fA) * fB, inverse = TRUE))[seq_len(n), seq_len(n)] /
    prod(mb$P)
  fMS <- stats::fft(mb$pad(MS)); fM <- stats::fft(mb$pad(Mn))
  list(sMSC = xc(fMS, mb$fB), sMC = xc(fM, mb$fB), sMC2 = xc(fM, mb$fB2),
       sMS = sum(MS), sMS2 = sum(MS * S), N = sum(Mn))
}

# NCC per lag from pooled statistics; NA where either side has no variance.
ofo2_ncc_value <- function(st) {
  num <- st$sMSC - st$sMS * st$sMC / st$N
  vS <- st$sMS2 - st$sMS^2 / st$N
  vC <- st$sMC2 - st$sMC^2 / st$N
  o <- num / sqrt(pmax(vS, 0) * pmax(vC, 0))
  o[!is.finite(o) | !(vS > 0) | !(vC > 0)] <- NA_real_
  o
}

## ---- method 2: one unit -------------------------------------------------------------------
# Prepares a unit for repeated objective evaluations. `members` is a list, one
# entry per member plot, of list(S = ofo2_surface(...) with the variant's
# smoothing, x, y, size) holding the member's signal stems (already displaced
# where a test requires it). Returns a closure-holding list: n stems and
# objective(sel), the objective over `grid` for the pooled stems `sel`
# (indices 1..n in member order; NULL for all).
ofo2_prepare <- function(members, cfg, grid = ofo_shift_grid()) {
  members <- Filter(function(m) length(m$x) > 0, members)
  sizes <- lapply(members, `[[`, "size")
  n_by <- vapply(sizes, length, integer(1))
  start <- cumsum(c(0L, n_by))[seq_along(n_by)]
  pick <- function(sel, k) {
    if (is.null(sel)) return(seq_len(n_by[k]))
    s <- sel[sel > start[k] & sel <= start[k] + n_by[k]] - start[k]
    sort(s)
  }
  if (identical(cfg$objective, "ncc")) {
    res <- OFO_REG2_SEARCH$res
    if (abs(OFO_REG2_SEARCH$step - res) > 1e-12) stop("NCC needs step == raster resolution")
    L <- as.integer(round(max(abs(grid$dx), abs(grid$dy)) / res))
    if (!isTRUE(all.equal(sort(unique(grid$dx)), seq(-L, L) * res)))
      stop("NCC needs the square shift grid at the raster step")
    mbs <- lapply(members, function(m) ofo2_ncc_member(m$S, m$x, m$y, m$size, cfg, L))
    idx <- cbind(as.integer(round(-grid$dy / res)) + L + 1L,
                 as.integer(round(grid$dx / res)) + L + 1L)
    objective <- function(sel = NULL) {
      acc <- NULL
      for (k in seq_along(mbs)) {
        use <- pick(sel, k)
        if (!length(use)) next
        st <- ofo2_ncc_stats(mbs[[k]], use)
        acc <- if (is.null(acc)) st else Map(`+`, acc, st)
      }
      if (is.null(acc)) return(rep(NA_real_, nrow(grid)))
      ofo2_ncc_value(acc)[idx]
    }
  } else {
    V <- do.call(rbind, lapply(members, function(m) ofo2_lookup(m$S, m$x, m$y, grid)))
    size <- unlist(sizes, use.names = FALSE)
    objective <- function(sel = NULL) {
      if (is.null(sel)) sel <- seq_len(nrow(V))
      ofo2_point_objective(V[sel, , drop = FALSE], size[sel], cfg)
    }
  }
  list(n = sum(n_by), objective = objective, grid = grid, cfg = cfg)
}

# The estimate from an objective over `grid`. NA counts as -Inf.
# peak: the arg-max refined per axis by the vertex of the parabola through it
# and its two neighbours (at most half a step). Exact ties (within tie_tol)
# take the centre of the tied shifts, unrefined: a tie rule that favours any
# shift (such as the shortest) would break translation equivariance.
# centroid: the centre of the shifts within centroid_tau of the contrast
# (maximum - median) of the maximum.
# Returns dx, dy, the grid index of the maximum and on_edge (that maximum on
# the window's edge).
ofo2_estimate <- function(obj, grid, estimator = "peak") {
  o <- ifelse(is.na(obj), -Inf, obj)
  top <- max(o)
  edge <- max(abs(grid$dx), abs(grid$dy))
  out <- function(dx, dy, i)
    list(dx = dx, dy = dy, index = i, objective = obj[i],
         on_edge = abs(grid$dx[i]) >= edge - 1e-9 || abs(grid$dy[i]) >= edge - 1e-9)
  if (!is.finite(top)) return(list(dx = NA_real_, dy = NA_real_, index = NA_integer_,
                                   objective = NA_real_, on_edge = NA))
  tied <- which(o >= top - OFO_REG2_SEARCH$tie_tol)
  i <- tied[1]
  if (identical(estimator, "centroid")) {
    med <- stats::median(obj, na.rm = TRUE)
    near <- which(o >= top - OFO_REG2_SEARCH$centroid_tau * (top - med))
    return(out(mean(grid$dx[near]), mean(grid$dy[near]), i))
  }
  if (length(tied) > 1L) return(out(mean(grid$dx[tied]), mean(grid$dy[tied]), i))
  step <- OFO_REG2_SEARCH$step
  at <- function(dx, dy) {
    k <- which(abs(grid$dx - dx) < 1e-9 & abs(grid$dy - dy) < 1e-9)
    if (length(k)) o[k] else -Inf
  }
  vertex <- function(m, p) {
    den <- m - 2 * o[i] + p
    if (!is.finite(den) || den >= 0) return(0)
    max(-step / 2, min(step / 2, 0.5 * step * (m - p) / den))
  }
  out(grid$dx[i] + vertex(at(grid$dx[i] - step, grid$dy[i]), at(grid$dx[i] + step, grid$dy[i])),
      grid$dy[i] + vertex(at(grid$dx[i], grid$dy[i] - step), at(grid$dx[i], grid$dy[i] + step)),
      i)
}

# Registers one prepared unit: the estimate and every gate statistic.
# residual_m: median distance between the estimates of two random halves over
#   `splits` half-splits (seeds seed_for("registration", key, NA, k)), as
#   declared; it sets pos_unc.
# sub_p90_m: 90th percentile over `subsamples` random 80% subsamples (seeds
#   seed_for("subsample", key, NA, k)) of the distance from the full estimate.
# z: (maximum - median) / sd of the objective over the window.
# second_peak: (largest objective farther than far_m from the estimate -
#   median) / (maximum - median); 1 means an equal peak elsewhere.
# resample_reach_m: the largest |dx| or |dy| of any half-split or subsample
#   estimate (a diagnostic: near 12 m the window edge clips the resamples).
ofo2_register_unit <- function(prep, key, splits = OFO_REG2_SEARCH$splits,
                               subsamples = OFO_REG2_SEARCH$subsamples) {
  grid <- prep$grid; n <- prep$n; est <- prep$cfg$estimator
  obj <- prep$objective()
  e <- ofo2_estimate(obj, grid, est)
  ok <- is.finite(obj)
  med <- if (any(ok)) stats::median(obj[ok]) else NA_real_
  mx <- if (any(ok)) max(obj[ok]) else NA_real_
  far <- ok & sqrt((grid$dx - e$dx)^2 + (grid$dy - e$dy)^2) > OFO_REG2_SEARCH$far_m
  sec <- if (any(far)) max(obj[far]) else NA_real_
  reach <- function(r) max(abs(c(r$dx, r$dy)))   # how near an estimate is to the edge
  half <- vapply(seq_len(splits), function(k) {
    set.seed(seed_for("registration", key, NA, k))
    perm <- sample.int(n)
    m <- floor(n / 2)
    a <- ofo2_estimate(prep$objective(perm[seq_len(m)]), grid, est)
    b <- ofo2_estimate(prep$objective(perm[seq_len(n - m) + m]), grid, est)
    c(sqrt((a$dx - b$dx)^2 + (a$dy - b$dy)^2), max(reach(a), reach(b)))
  }, numeric(2))
  sub <- vapply(seq_len(subsamples), function(k) {
    set.seed(seed_for("subsample", key, NA, k))
    s <- ofo2_estimate(prep$objective(sort(sample.int(n, ceiling(OFO_REG2_SEARCH$sub_frac * n)))),
                       grid, est)
    c(sqrt((s$dx - e$dx)^2 + (s$dy - e$dy)^2), reach(s))
  }, numeric(2))
  resample_reach <- max(c(half[2, ], sub[2, ]))
  half <- half[1, ]; sub <- sub[1, ]
  q <- function(x, p) if (all(is.finite(x))) unname(stats::quantile(x, p, type = 7)) else NA_real_
  data.frame(n_signal = n, dx = e$dx, dy = e$dy, shift_m = sqrt(e$dx^2 + e$dy^2),
             objective_zero = obj[which(abs(grid$dx) < 1e-9 & abs(grid$dy) < 1e-9)][1],
             objective_best = mx, objective_median = med, contrast = mx - med,
             z = (mx - med) / if (sum(ok) > 1) stats::sd(obj[ok]) else NA_real_,
             second_peak = (sec - med) / (mx - med),
             residual_m = if (all(is.finite(half))) stats::median(half) else NA_real_,
             sub_p90_m = q(sub, 0.9), on_edge = e$on_edge,
             resample_reach_m = resample_reach, stringsAsFactors = FALSE)
}

## ---- method 2: gate -------------------------------------------------------------------
# Gate statistics a method-2 gate may use, and the direction that passes.
OFO_REG2_GATE_STATS <- c(residual_m = "max", sub_p90_m = "max", second_peak = "max", z = "min")

# Acceptance of one registered unit under `gate` = list(stat, threshold,
# min_stems): at least min_stems signal stems, an estimate off the window's
# edge, and the statistic on the passing side of the threshold (a missing
# statistic fails). The reason lists every failed rule, ";"-joined.
ofo2_accept <- function(n, on_edge, value, gate) {
  dir <- OFO_REG2_GATE_STATS[[gate$stat]]
  eps <- OFO_REG2_SEARCH$eps
  pass <- if (dir == "max") isTRUE(value <= gate$threshold + eps) else
    isTRUE(value >= gate$threshold - eps)
  fail <- c(n = !isTRUE(n >= gate$min_stems), on_edge = !isFALSE(on_edge))
  fail[gate$stat] <- !pass
  list(accepted = !any(fail), reason = paste(names(fail)[fail], collapse = ";"))
}

# Applies a gate to a table of registered units (columns n_signal, on_edge and
# the gate's statistic): adds accepted and reject_reason.
ofo2_apply_gate <- function(tab, gate) {
  a <- lapply(seq_len(nrow(tab)), function(i)
    ofo2_accept(tab$n_signal[i], tab$on_edge[i], tab[[gate$stat]][i], gate))
  tab$accepted <- vapply(a, `[[`, logical(1), "accepted")
  tab$reject_reason <- vapply(a, `[[`, character(1), "reason")
  tab
}

## ---- method 2: units of the known-truth tests -------------------------------------------
# Units with fewer signal stems are not run at all (two per half at least).
OFO_REG2_MIN_RUN <- 4L

# Method-2 signal stems: height = a measured height above 0 (all of them, not
# the tall half); rank (diameter signal) = a diameter of at least 10 cm.
# `st` has columns height and dbh.
ofo2_signal_stems <- function(st, signal)
  switch(signal,
         height = is.finite(st$height) & st$height > 0,
         rank = is.finite(st$dbh) & st$dbh >= OFO_REG$dbh_floor,
         stop("Unknown signal: ", signal))

# Members of one unit for ofo2_prepare(): each member plot's signal stems,
# displaced by `off`, on that plot's surface of the given smoothing. `plots`
# is a named list of list(stems = data.frame(x, y, height, dbh),
# surf = named list of ofo2_surface() results).
ofo2_unit_members <- function(members, plots, signal, surface, off = c(0, 0)) {
  lapply(members, function(p) {
    pl <- plots[[p]]
    if (is.null(pl)) stop("No data loaded for member plot ", p)
    S <- pl$surf[[surface]]
    if (is.null(S)) stop("No ", surface, " surface for plot ", p)
    k <- ofo2_signal_stems(pl$stems, signal)
    list(S = S, x = pl$stems$x[k] + off[1], y = pl$stems$y[k] + off[2],
         size = if (signal == "height") pl$stems$height[k] else pl$stems$dbh[k])
  })
}

# Registers one known-truth unit whose stems were displaced by `off`: one row
# with the gate statistics and error_m, the distance between the estimate and
# the shift that undoes the offset (-off). Units under OFO_REG2_MIN_RUN signal
# stems are returned unrun (estimate fields NA).
ofo2_run_unit <- function(unit, members, plots, signal, cfg, off, grid = ofo_shift_grid()) {
  mem <- ofo2_unit_members(members, plots, signal, cfg$surface, off)
  n <- sum(vapply(mem, function(m) length(m$x), integer(1)))
  reg <- if (n >= OFO_REG2_MIN_RUN) ofo2_register_unit(ofo2_prepare(mem, cfg, grid), unit) else
    data.frame(n_signal = n, dx = NA_real_, dy = NA_real_, shift_m = NA_real_,
               objective_zero = NA_real_, objective_best = NA_real_,
               objective_median = NA_real_, contrast = NA_real_, z = NA_real_,
               second_peak = NA_real_, residual_m = NA_real_, sub_p90_m = NA_real_,
               on_edge = NA, resample_reach_m = NA_real_)
  cbind(data.frame(unit = unit, signal = signal, offset_dx = off[1], offset_dy = off[2],
                   stringsAsFactors = FALSE),
        reg, data.frame(error_m = sqrt((reg$dx + off[1])^2 + (reg$dy + off[2])^2)))
}

## ---- method 2: development analysis -------------------------------------------------------
OFO_REG2_BANDS <- list(breaks = c(-Inf, 14, 29, 59, 119, Inf),
                       labels = c("<15", "15-29", "30-59", "60-119", "120+"))

# Accuracy of a set of errors: median and count/share within 2 m.
ofo2_accuracy <- function(e) {
  e <- e[is.finite(e)]
  list(n = length(e), median_error_m = if (length(e)) stats::median(e) else NA_real_,
       n_within_2m = sum(e <= 2 + OFO_REG2_SEARCH$eps),
       share_within_2m = if (length(e)) mean(e <= 2 + OFO_REG2_SEARCH$eps) else NA_real_)
}

# Per variant x signal x kind (all, plot, composite) x stem-count band (and
# "all"): units run, accepted, accuracy of accepted and of all run units.
# `res` holds variant, signal, kind, n_signal, dx, error_m, accepted.
ofo2_dev_summary <- function(res) {
  run <- res[is.finite(res$dx), , drop = FALSE]
  run$band <- as.character(cut(run$n_signal, OFO_REG2_BANDS$breaks, OFO_REG2_BANDS$labels))
  out <- list()
  for (key in unique(paste(run$variant, run$signal, sep = "|"))) {
    x <- run[paste(run$variant, run$signal, sep = "|") == key, , drop = FALSE]
    for (kd in c("all", "plot", "composite")) for (bd in c("all", OFO_REG2_BANDS$labels)) {
      y <- x[(kd == "all" | x$kind == kd) & (bd == "all" | x$band == bd), , drop = FALSE]
      if (!nrow(y)) next
      a <- ofo2_accuracy(y$error_m[y$accepted %in% TRUE]); r <- ofo2_accuracy(y$error_m)
      out[[length(out) + 1L]] <- data.frame(
        variant = x$variant[1], signal = x$signal[1], kind = kd, band = bd, units_run = nrow(y),
        accepted = a$n, median_error_accepted_m = a$median_error_m,
        share_within_2m_accepted = a$share_within_2m, median_error_all_m = r$median_error_m,
        share_within_2m_all = r$share_within_2m, stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, out)
}

# The gate family searched in development: one statistic, a coarse threshold
# grid fixed before the sweep, and the smallest stem count.
OFO_REG2_GATE_GRID <- list(
  residual_m = c(1, 1.5, 2, 3), sub_p90_m = c(0.5, 1, 2), second_peak = c(0.6, 0.7, 0.8),
  z = c(3, 3.5, 4), min_stems = c(10L, 15L, 20L, 30L, 40L, 60L))
# Selection margins on development data and the confirmation limits.
OFO_REG2_DEV_MARGINS <- list(max_median_error = 0.8, min_share = 0.95)
OFO_REG2_PASS <- list(min_accepted = 10L, max_median_error = 1.0, max_error = 2.0,
                      min_share = 0.90)

# Every (variant, signal, gate) of the gate family on the development table:
# among units at or above min_stems, accepted units and their accuracy,
# whether the development margins / confirmation limits are met, and (boot)
# the bootstrap chance of passing the confirmation.
ofo2_gate_sweep <- function(res, grid = OFO_REG2_GATE_GRID, boot = TRUE) {
  run <- res[is.finite(res$dx), , drop = FALSE]
  out <- list()
  for (key in unique(paste(run$variant, run$signal, sep = "|"))) {
    x <- run[paste(run$variant, run$signal, sep = "|") == key, , drop = FALSE]
    for (stat in names(OFO_REG2_GATE_STATS)) for (thr in grid[[stat]])
      for (ms in grid$min_stems) {
        g <- list(stat = stat, threshold = thr, min_stems = ms)
        y <- ofo2_apply_gate(x[x$n_signal >= ms, , drop = FALSE], g)
        a <- ofo2_accuracy(y$error_m[y$accepted])
        out[[length(out) + 1L]] <- data.frame(
          variant = x$variant[1], signal = x$signal[1],
          estimator = if (is.null(x$estimator)) NA_character_ else x$estimator[1],
          gate_stat = stat, threshold = thr,
          min_stems = ms, units_run = nrow(y), accepted = a$n,
          n_composite_accepted = sum(y$accepted & y$kind == "composite"),
          median_error_accepted_m = a$median_error_m, n_within_2m = a$n_within_2m,
          share_within_2m = a$share_within_2m,
          meets_dev_margins = ofo2_meets(a, OFO_REG2_DEV_MARGINS$max_median_error,
                                         OFO_REG2_DEV_MARGINS$min_share),
          meets_confirm_limits = ofo2_meets(a, OFO_REG2_PASS$max_median_error,
                                            OFO_REG2_PASS$min_share),
          p_pass_bootstrap = if (boot) ofo2_pass_bootstrap(
            y$accepted, y$error_m, paste(x$variant[1], x$signal[1], stat, thr, ms)) else NA_real_,
          stringsAsFactors = FALSE)
      }
  }
  do.call(rbind, out)
}

# A bootstrap estimate of the chance that a configuration passes the
# confirmation: development units at or above its stem count are resampled
# with replacement (B samples of the same size) and the Amendment 1 pass rule
# is applied to each sample. It treats the development units as a sample of
# the confirmation units; on the configuration that won a selection it is
# optimistic.
ofo2_pass_bootstrap <- function(accepted, error_m, key, B = 1000L, rules = OFO_REG2_PASS) {
  n <- length(accepted)
  if (!n) return(0)
  set.seed(seed_for("bootstrap", key, NA))
  idx <- matrix(sample.int(n, n * B, replace = TRUE), B)
  acc <- accepted %in% TRUE
  ok <- acc & error_m <= rules$max_error + OFO_REG2_SEARCH$eps
  na <- rowSums(matrix(acc[idx], B)); nw <- rowSums(matrix(ok[idx], B))
  med <- vapply(seq_len(B), function(b) {
    e <- error_m[idx[b, ]][acc[idx[b, ]]]
    if (length(e)) stats::median(e) else NA_real_
  }, numeric(1))
  mean(na >= rules$min_accepted & med <= rules$max_median_error + OFO_REG2_SEARCH$eps &
         nw * 100 >= round(rules$min_share * 100) * na, na.rm = FALSE)
}

# Accuracy limits on an ofo2_accuracy() result (shares compared in counts).
ofo2_meets <- function(a, max_median, min_share)
  a$n > 0 && isTRUE(a$median_error_m <= max_median + OFO_REG2_SEARCH$eps) &&
    a$n_within_2m * 100 >= round(min_share * 100) * a$n

# Gate statistics eligible for selection. residual_m and sub_p90_m compare
# estimates with each other, so for an equivariant estimator they change only
# when a resampled estimate is clipped by the window's edge. z, second_peak
# (and contrast) are measured against the whole window, so they change with
# where the truth lies in it: offsets of up to 8 m in the known-truth tests
# against a few metres on catalogue plots. They are swept and reported only.
OFO_REG2_SELECTABLE_STATS <- c("residual_m", "sub_p90_m")

# The selection rule, per signal, over configurations with the (equivariant)
# peak estimator, a selectable gate statistic and at least the confirmation's
# 10 accepted development units:
# those meeting the development margins, most accepted first (then fewer
# stems needed, higher share, lower median); when a signal has none, those
# meeting the confirmation limits, highest bootstrap chance of passing first.
# Returns the ranked rows with `basis` (margins | confirmation_bootstrap).
ofo2_select <- function(sweep) {
  base <- sweep[sweep$gate_stat %in% OFO_REG2_SELECTABLE_STATS &
                  sweep$accepted >= OFO_REG2_PASS$min_accepted &
                  sweep$estimator %in% "peak", , drop = FALSE]
  out <- lapply(unique(sweep$signal), function(s) {
    b <- base[base$signal == s, , drop = FALSE]
    q <- b[b$meets_dev_margins, , drop = FALSE]
    if (nrow(q)) {
      q <- q[order(-q$accepted, q$min_stems, -q$share_within_2m, q$median_error_accepted_m), ,
             drop = FALSE]
      q$basis <- rep("margins", nrow(q))
    } else {
      q <- b[b$meets_confirm_limits, , drop = FALSE]
      q <- q[order(-q$p_pass_bootstrap, -q$accepted, q$min_stems), , drop = FALSE]
      q$basis <- rep("confirmation_bootstrap", nrow(q))
    }
    q
  })
  do.call(rbind, out)
}

## ---- method 2: confirmation -----------------------------------------------------------------
# The pass rule of Amendment 1 for one signal: among units at or above the
# smallest stem count, at least 10 accepted, median error of the accepted
# units <= 1.0 m and >= 90% of them within 2.0 m (compared in counts).
ofo2_confirmation_test <- function(n_signal, accepted, error_m, min_stems,
                                   rules = OFO_REG2_PASS) {
  at <- n_signal >= min_stems
  acc <- at & accepted %in% TRUE
  a <- ofo2_accuracy(error_m[acc])
  list(n_units = length(n_signal), n_at_min_stems = sum(at), n_accepted = sum(acc),
       median_error_m = a$median_error_m, n_within_2m = a$n_within_2m,
       share_within_2m = a$share_within_2m,
       pass = sum(acc) >= rules$min_accepted &&
         isTRUE(a$median_error_m <= rules$max_median_error + OFO_REG2_SEARCH$eps) &&
         a$n_within_2m * 100 >= round(rules$min_share * 100) * sum(acc))
}

# Refuses the confirmation unless it is asked for explicitly, it has not run
# before, the method is frozen and the protocol text holds Amendment 1b with
# the digest of the frozen constants. Returns TRUE or stops with the reason.
ofo2_confirm_guard <- function(confirm, done, frozen, protocol_text,
                               digest = ofo2_config_digest()) {
  if (!identical(confirm, "YES"))
    stop("STAGE=confirm is the single confirmation run of Amendment 1; pass CONFIRM=YES",
         call. = FALSE)
  if (isTRUE(done))
    stop("registration_confirm.csv exists: the confirmation has run and is never re-run",
         call. = FALSE)
  if (!isTRUE(frozen))
    stop("OFO_REG2 is not frozen: write Amendment 1b before the confirmation", call. = FALSE)
  txt <- paste(protocol_text, collapse = "\n")
  if (!grepl("Amendment 1b", txt, fixed = TRUE) || !grepl(digest, txt, fixed = TRUE))
    stop("The protocol has no Amendment 1b quoting the method-2 digest ", digest,
         call. = FALSE)
  TRUE
}

## ---- method 2: the frozen configuration (Amendment 1b) -----------------------------------
# One configuration per signal, chosen on development units only (STAGE=dev,
# registration_dev_gates.csv, ofo2_select()): estimator, gate and smallest
# stem count.
# height: development margins met; the most accepted units (31), the raw
#   surface preferred as simpler to the smoothed one tied with it.
# rank (diameter signal): no configuration met the development margins; of
#   those meeting the confirmation limits, the highest bootstrap chance of
#   passing: a fixed 2 m crown of diameter amplitude.
# Spelled out (not referenced) so a later edit of the variant list cannot
# change the frozen method; STAGE=dev checks they still agree.
OFO_REG2 <- list(
  frozen = TRUE,
  height = list(variant = "ncc",
                cfg = ofo2_variant("ncc", "raw", "peak", r0 = 0.5, r1 = 0.1, mask_m = 4,
                                   amp = "size"),
                gate = list(stat = "sub_p90_m", threshold = 2.0, min_stems = 20L)),
  rank = list(variant = "ncc_r2",
              cfg = ofo2_variant("ncc", "raw", "peak", r0 = 2, r1 = 0, mask_m = 4,
                                 amp = "size"),
              gate = list(stat = "sub_p90_m", threshold = 1.0, min_stems = 10L)),
  offset_max = 8, pass_rules = OFO_REG2_PASS)

ofo2_frozen <- function(x = OFO_REG2) isTRUE(x$frozen)

# SHA-256 of everything that defines method 2 (search constants, smallest
# run, both frozen configurations, offsets, pass rule). Amendment 1b quotes it
# and STAGE=confirm refuses to run unless the protocol does.
ofo2_config_digest <- function(x = OFO_REG2) {
  core <- list(search = OFO_REG2_SEARCH, min_run = OFO_REG2_MIN_RUN, height = x$height,
               rank = x$rank, offset_max = x$offset_max, pass_rules = x$pass_rules)
  digest::digest(as.character(jsonlite::toJSON(core, auto_unbox = TRUE, digits = NA)),
                 algo = "sha256", serialize = FALSE)
}
