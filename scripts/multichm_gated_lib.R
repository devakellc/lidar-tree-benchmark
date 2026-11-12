# Library of the `multichm_gated` tree-top arm: lidRplugins::multichm (Eysn-
# style multi-layer CHM local maxima) with a gate on its deeper-layer
# candidates, switched on by canopy cover, and an optional exemption of the
# surface-layer peaks from the package's distance filter in closed stands.
#
# multichm strips the top of the cloud layer by layer and re-runs local maxima
# on what is left. In closed, tall conifer stands most deeper-layer peaks are not
# trees; the ones that are tend to sit in returns that are mostly FIRST returns
# (lit from above). The package's distance filter (3 m horizontal, 5 m in 3-D)
# also deletes real neighbouring surface peaks in dense stands. The gate keeps a
# deeper-layer candidate when it is high enough (zmin) and, in a closed stand
# (canopy cover >= cover_min), when the first-return share around its own top is
# at least min_share; in a closed stand surface peaks may skip the distance
# filter (surface_exempt).
#
# Provenance: the gate's form and the calibration grid values (mcg_grid) were
# informed by an exploratory pass over all 106 frozen NEON plots of the five
# sites. A held-out score of a configuration selected on calibration plots
# therefore tests the threshold selection, not the choice of features.
#
# The stock configuration (MCG_STOCK: no floor, no share gate, no exemption)
# reproduces lidRplugins::multichm 0.4.0 exactly; mcg_candidates() is an
# instrumented, bit-identical re-implementation of its candidate search.
#
# Sourced, not run. No side effects. The caller sources sweep_lib.R
# (ws_factory, score_plot, null_offset, shift_detections), model_bench_lib.R
# (seed_for, assert_detection_contract), calval_lib.R (plot_table,
# assign_split) and master_tables_lib.R (mt_plot_weights, mt_interval,
# MT_N_BOOT, MT_SEED) first, and attaches lidR, lidRplugins and data.table.

## ---- constants and configuration --------------------------------------------------------
MCG_RADIUS       <- 1    # horizontal radius (m) of a candidate's first-return share
MCG_HALF_DZ      <- 1    # half height (m) of the band around the candidate's own top
MCG_COVER_HEIGHT <- 2    # first returns above this height (m) count as canopy

# A validated configuration. zmin: height floor (m) of deeper-layer candidates
# in every stand (0 = none); min_share: first-return share a deeper-layer
# candidate needs in a closed stand (0 = no share gate); cover_min: canopy cover
# at or above which a stand is closed (0 = every stand is closed);
# surface_exempt: surface-layer candidates skip the distance filter in closed
# stands.
mcg_config <- function(zmin = 0, min_share = 0, cover_min = 0, surface_exempt = FALSE) {
  num <- function(v, nm, lo, hi) {
    if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v < lo || v > hi)
      stop(sprintf("multichm_gated: %s must be one number in [%g, %g]", nm, lo, hi),
           call. = FALSE)
    as.numeric(v)
  }
  if (!is.logical(surface_exempt) || length(surface_exempt) != 1L || is.na(surface_exempt))
    stop("multichm_gated: surface_exempt must be TRUE or FALSE", call. = FALSE)
  list(zmin = num(zmin, "zmin", 0, Inf), min_share = num(min_share, "min_share", 0, 1),
       cover_min = num(cover_min, "cover_min", 0, 1), surface_exempt = surface_exempt)
}
.mcg_check_config <- function(cfg) {
  if (is.null(cfg))
    stop("multichm_gated: no configuration; pass one (mcg_config())", call. = FALSE)
  if (!is.list(cfg) || !all(c("zmin", "min_share", "cover_min", "surface_exempt") %in% names(cfg)))
    stop("multichm_gated: a configuration is a list(zmin, min_share, cover_min, surface_exempt)",
         call. = FALSE)
  mcg_config(cfg$zmin, cfg$min_share, cfg$cover_min, cfg$surface_exempt)
}

MCG_STOCK    <- mcg_config()
# The declared configuration: selected by calval_multichm_gated.R as the grid
# configuration with the highest chance-corrected F1 at native density on the
# 57 calibration plots of the five sites (stratified split, seed 1, calibration
# fraction 0.5; adopted population; sealed root with clip-manifest SHA-256
# 4567a247a6dd6d9630d6cea5427da3e262b1dcaac4a07a1173b3764e8a63c8d4). The 49
# validation plots are its held-out test. See results/multichm-gated-results.md.
MCG_DECLARED <- mcg_config(zmin = 5, min_share = 0.75, cover_min = 0.6, surface_exempt = TRUE)

# "stock" for the stock configuration, otherwise e.g. "z5_s0.75_c0.7_e1".
mcg_config_label <- function(cfg) {
  cfg <- .mcg_check_config(cfg)
  if (identical(cfg, MCG_STOCK)) return("stock")
  sprintf("z%g_s%g_c%g_e%d", cfg$zmin, cfg$min_share, cfg$cover_min, as.integer(cfg$surface_exempt))
}

# What a configuration reads: the first-return share iff min_share > 0; the
# canopy cover iff cover_min > 0 and the cover decides something (a share gate
# or the exemption). With cover_min == 0 every stand counts as closed.
.mcg_needs_share <- function(cfg) cfg$min_share > 0
.mcg_needs_cover <- function(cfg) cfg$cover_min > 0 && (cfg$min_share > 0 || cfg$surface_exempt)

## ---- candidates: instrumented lidRplugins::multichm 0.4.0 ---------------------------------
# The height of each candidate's own top return, `zt`, read from the layer's
# top raster at the candidate's coordinates. Upstream quirk: a one-row layer
# raster can return a maximum whose coordinates miss its own cell; such maxima
# lie on the clip's edge row, in the buffer. The raster then gives NA or the top
# of a neighbouring cell, which shows as a value below the candidate's Z (the
# highest return of its own cell is at least the cell's 95th percentile). Both
# fall back to the candidate's Z.
.mcg_ztop <- function(zt, z) {
  bad <- is.na(zt) | zt < z
  zt[bad] <- z[bad]
  zt
}

# Every layer's local maxima before the package's distance filter. Same lidR
# calls as the package (grid_metrics / find_trees are deprecated but give the
# package's rasters bit for bit). Per layer: the 95th-percentile height raster
# c95 at `res`, its local maxima above hmin with window `ws`, then every return
# below c95 - layer_thickness forms the next layer. Columns: X, Y, Z (the
# layer's p95 at the maximum, as the package reports it), layer (1 = surface),
# ztop (highest return of the maximum's cell). Sorted by descending Z (stable)
# and unique by (X, Y), as the package does.
mcg_candidates <- function(las, res, ws, layer_thickness = 0.5, hmin = 2) {
  empty <- data.table::data.table(X = numeric(), Y = numeric(), Z = numeric(),
                                  layer = integer(), ztop = numeric())
  lc <- lidR::LAS(las@data[, c("X", "Y", "Z"), with = FALSE], las@header)
  LM <- list(); i <- 1L
  while (!lidR::is.empty(lc)) {
    m <- suppressWarnings(lidR::grid_metrics(
      lc, ~list(q = stats::quantile(Z, probs = 0.95), top = max(Z)), res))
    c95 <- m[["q"]]
    if (max(c95[], na.rm = TRUE) > hmin) {
      lm <- suppressWarnings(lidR::find_trees(c95, lidR::lmf(ws = ws, hmin = hmin)))
      co <- lm@coords
      if (nrow(co)) {
        z <- lm@data$Z
        LM[[i]] <- data.table::data.table(X = unname(co[, 1]), Y = unname(co[, 2]), Z = z,
                                          layer = i,
                                          ztop = .mcg_ztop(raster::extract(m[["top"]], co), z))
      }
      lc <- lidR::merge_spatial(lc, c95, "c95")
      lc <- lidR::filter_poi(lc, Z < c95 - layer_thickness)
      i <- i + 1L
    } else lc <- methods::new("LAS")
  }
  LM <- data.table::rbindlist(c(list(empty), LM))
  data.table::setorderv(LM, "Z", order = -1L)
  unique(LM, by = c("X", "Y"))
}

## ---- candidate and stand features -------------------------------------------------------
# Share of first returns among the clip's returns within `radius` (horizontal,
# dx^2 + dy^2 <= radius^2) of each candidate's (X, Y) and within `half_dz` of its
# ztop. NA where no return qualifies, and everywhere when the clip has no
# ReturnNumber. Points are binned on a grid of cell size `radius` (inflated by a
# relative 1e-9 so rounding can never put a qualifying point two cells away);
# each candidate joins its 3 x 3 neighbouring bins, then the exact test applies.
mcg_first_return_share <- function(cand, las, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ) {
  n <- nrow(cand)
  out <- rep(NA_real_, n)
  if (!n || !"ReturnNumber" %in% names(las@data) || lidR::is.empty(las)) return(out)
  cell <- radius * (1 + 1e-9)
  x0 <- min(las@data$X); y0 <- min(las@data$Y)
  P <- data.table::data.table(px = las@data$X, py = las@data$Y, pz = las@data$Z,
                              fr = las@data$ReturnNumber == 1L)
  P[, `:=`(gx = floor((px - x0) / cell), gy = floor((py - y0) / cell))]
  data.table::setkeyv(P, c("gx", "gy"))
  Q <- data.table::data.table(cid = seq_len(n), qx = cand$X, qy = cand$Y, qz = cand$ztop)
  Q[, `:=`(gx0 = floor((qx - x0) / cell), gy0 = floor((qy - y0) / cell))]
  nb <- data.table::CJ(dx = -1:1, dy = -1:1)
  Q9 <- Q[rep(seq_len(n), each = 9L)]
  Q9[, `:=`(gx = gx0 + rep(nb$dx, n), gy = gy0 + rep(nb$dy, n))]
  J <- P[Q9, on = c("gx", "gy"), nomatch = NULL, allow.cartesian = TRUE]
  J <- J[(px - qx)^2 + (py - qy)^2 <= radius^2 & abs(pz - qz) <= half_dz]
  if (nrow(J)) {
    s <- J[, list(share = mean(fr)), by = "cid"]
    out[s$cid] <- s$share
  }
  out
}

# Canopy cover of a normalized clip: share of its first returns above `height`.
# NA when the clip has no ReturnNumber (or no first returns).
mcg_canopy_cover <- function(las, height = MCG_COVER_HEIGHT) {
  if (!"ReturnNumber" %in% names(las@data)) return(NA_real_)
  f <- las@data$ReturnNumber == 1L
  f[is.na(f)] <- FALSE
  if (!any(f)) return(NA_real_)
  mean(las@data$Z[f] > height)
}

# Everything that does not depend on the configuration (cacheable per clip):
# the candidates with their first-return share, and the clip's canopy cover.
mcg_prepare <- function(las, res, a = 0.10) {
  cand <- mcg_candidates(las, res, ws_factory(a))
  cand[, share := mcg_first_return_share(cand, las)]
  list(cand = cand, cover = mcg_canopy_cover(las),
       has_return_number = "ReturnNumber" %in% names(las@data), res = res, a = a)
}

## ---- gate, distance filter, detections --------------------------------------------------
# Whether a clip counts as a closed stand: cover >= cover_min, TRUE for every
# stand when cover_min == 0, NA when the cover is unknown. Never stops: whether
# an unknown cover matters is the caller's question (mcg_gate, mcg_apply).
mcg_closed <- function(cover, cfg) {
  cfg <- .mcg_check_config(cfg)
  if (cfg$cover_min == 0) TRUE else if (is.na(cover)) NA else cover >= cfg$cover_min
}

# keep: surface-layer candidates always; a deeper-layer candidate iff Z >= zmin
# (every stand) and, in a closed stand with a share gate, its share is known and
# >= min_share. exempt: a surface-layer candidate in a closed stand when
# surface_exempt. closed: mcg_closed() (NA only when the cover is moot and
# unknown; an unknown cover that decides something stops).
mcg_gate <- function(cand, cover, cfg) {
  cfg <- .mcg_check_config(cfg)
  closed <- mcg_closed(cover, cfg)
  if (is.na(closed) && .mcg_needs_cover(cfg))
    stop("multichm_gated: this configuration needs the canopy cover, which is unavailable ",
         "(the clip has no ReturnNumber or no first returns)", call. = FALSE)
  if (cfg$min_share > 0 && is.null(cand$share))
    stop("multichm_gated: this configuration needs the candidates' first-return share ",
         "(column `share`, from mcg_prepare)", call. = FALSE)
  surface <- cand$layer == 1L
  share_ok <- if (cfg$min_share > 0) !is.na(cand$share) & cand$share >= cfg$min_share else TRUE
  gated <- isTRUE(closed) && cfg$min_share > 0
  keep <- surface | (cand$Z >= cfg$zmin & (if (gated) share_ok else TRUE))
  exempt <- surface & isTRUE(closed) & cfg$surface_exempt
  list(keep = keep, exempt = exempt, closed = closed)
}

# The package's greedy distance filter over the kept candidates in descending Z:
# the first is accepted; a later one is accepted iff no accepted one lies within
# dist_2d horizontally (d2 < dist_2d^2) and none within dist_3d in 3-D
# (d2 + dz^2 < dist_3d^2). An exempt candidate is accepted unconditionally and
# then excludes later ones like any accepted top. Returns `accepted` in the
# row order of `cand`.
mcg_filter <- function(cand, keep, exempt, dist_2d = 3, dist_3d = 5) {
  n <- nrow(cand)
  acc <- logical(n)
  if (length(keep) != n || length(exempt) != n)
    stop("multichm_gated: keep and exempt need one value per candidate", call. = FALSE)
  if (!n) return(acc)
  d2l <- dist_2d^2; d3l <- dist_3d^2
  X <- cand$X; Y <- cand$Y; Z <- cand$Z
  ax <- numeric(n); ay <- numeric(n); az <- numeric(n); k <- 0L
  for (i in order(-Z, method = "radix")) {
    if (!keep[i]) next
    ok <- exempt[i] || k == 0L
    if (!ok) {
      s <- seq_len(k)
      d2 <- (X[i] - ax[s])^2 + (Y[i] - ay[s])^2
      ok <- !any(d2 < d2l) && !any(d2 + (Z[i] - az[s])^2 < d3l)
    }
    if (ok) { k <- k + 1L; ax[k] <- X[i]; ay[k] <- Y[i]; az[k] <- Z[i]; acc[i] <- TRUE }
  }
  acc
}

# Detections of one configuration on a prepared clip: data.frame x, y, z
# (z = the candidate's Z), in descending z; 0 rows when nothing is detected.
# A clip without candidates gives 0 rows under any configuration, before the
# share or cover a configuration reads is asked for.
mcg_apply <- function(prep, cfg) {
  cfg <- .mcg_check_config(cfg)
  C <- prep$cand
  if (!nrow(C)) {
    det <- data.frame(x = numeric(), y = numeric(), z = numeric())
    assert_detection_contract(det)
    return(det)
  }
  if (.mcg_needs_share(cfg) && isFALSE(prep$has_return_number))
    stop("multichm_gated: this configuration needs the first-return share, but the clip ",
         "has no ReturnNumber", call. = FALSE)
  if (.mcg_needs_cover(cfg) && is.na(prep$cover))
    stop("multichm_gated: this configuration needs the canopy cover, which is unavailable ",
         "(the clip has no ReturnNumber or no first returns)", call. = FALSE)
  g <- mcg_gate(C, prep$cover, cfg)
  acc <- mcg_filter(C, g$keep, g$exempt)
  C <- C[acc]
  data.table::setorderv(C, "Z", order = -1L)
  det <- data.frame(x = as.numeric(C$X), y = as.numeric(C$Y), z = as.numeric(C$Z))
  assert_detection_contract(det)
  det
}

detect_multichm_gated <- function(las, res, a = 0.10, cfg = MCG_DECLARED) {
  cfg <- .mcg_check_config(cfg)
  mcg_apply(mcg_prepare(las, res, a), cfg)
}

## ---- the declared calibration grid ------------------------------------------------------
# zmin {0, 5, 8} x min_share {0, 0.5, 0.75, 0.9} x cover_min {0, 0.6, 0.7, 0.8} x
# surface_exempt {FALSE, TRUE}; without a share gate and without the exemption
# the cover is moot, so those rows keep cover_min = 0 only: 3 * (1 + 7 * 4) = 87.
# "Least intervention first": surface_exempt (FALSE first), min_share ascending,
# zmin ascending, cover_min descending (a higher cover_min closes fewer stands).
# config_id = row number; config_id 1 is the stock configuration.
mcg_grid <- function() {
  g <- expand.grid(cover_min = c(0.8, 0.7, 0.6, 0), zmin = c(0, 5, 8),
                   min_share = c(0, 0.5, 0.75, 0.9), surface_exempt = c(FALSE, TRUE),
                   KEEP.OUT.ATTRS = FALSE)
  g <- g[!(g$min_share == 0 & !g$surface_exempt & g$cover_min > 0), , drop = FALSE]
  g <- g[order(g$surface_exempt, g$min_share, g$zmin, -g$cover_min), , drop = FALSE]
  g <- data.frame(config_id = seq_len(nrow(g)), zmin = g$zmin, min_share = g$min_share,
                  cover_min = g$cover_min, surface_exempt = g$surface_exempt,
                  stringsAsFactors = FALSE)
  g$label <- vapply(seq_len(nrow(g)), function(i)
    mcg_config_label(mcg_config(g$zmin[i], g$min_share[i], g$cover_min[i], g$surface_exempt[i])),
    character(1))
  g
}

## ---- scoring: observed counts and the chance-agreement null -----------------------------
MCG_COUNT_COLS <- c("n_ref", "n_over", "n_under", "n_det", "TP", "tp_core", "tp_over",
                    "tp_under", "n_det0", "TP0", "tp_core0", "tp_over0", "tp_under0")

# The benchmark's null shifts of one plot: k random toroidal shifts of the
# scoring window (core plus the matcher's reach), shared by every arm and rung.
mcg_null_offsets <- function(site, plot, half, tol = 4, k = 200, min_shift = 8)
  lapply(seq_len(k), function(i)
    null_offset(2 * (half + tol), seed_for(site, plot, "null") + i, min_shift = min_shift))

# Counts of one score_plot() row: core true positives recovered from precision,
# overstory (dominant + codominant) and understory (intermediate + suppressed)
# TP recovered per class as round(recall x n).
.mcg_counts <- function(sc) {
  cls <- function(k) {
    n <- vapply(k, function(c) as.numeric(sc[[paste0("n_", c)]]), numeric(1))
    r <- vapply(k, function(c) as.numeric(sc[[paste0("rec_", c)]]), numeric(1))
    c(n = sum(n), tp = sum(ifelse(n > 0 & is.finite(r), round(r * n), 0)))
  }
  o <- cls(c("dominant", "codominant")); u <- cls(c("intermediate", "suppressed"))
  c(n_ref = sc$n_ref, n_over = o[["n"]], n_under = u[["n"]], n_det = sc$n_det, TP = sc$TP,
    tp_core = if (sc$n_det > 0) round(sc$precision * sc$n_det) else 0,
    tp_over = o[["tp"]], tp_under = u[["tp"]])
}

# One cell (plot x rung x detection set): observed counts and their means over
# the shifted copies of the detections (NA without offsets). One-row data.frame
# with MCG_COUNT_COLS.
mcg_score_cell <- function(stems, det, cx, cy, half, offsets, tol = 4) {
  sc <- function(dt) .mcg_counts(score_plot(stems, dt, tol_xy = tol, core_cx = cx,
                                            core_cy = cy, core_half = half))
  o <- sc(det)
  nul <- if (length(offsets))
    rowMeans(vapply(offsets, function(of) sc(shift_detections(det, cx, cy, half + tol, of)),
                    numeric(length(o)))) else stats::setNames(rep(NA_real_, length(o)), names(o))
  data.frame(n_ref = o[["n_ref"]], n_over = o[["n_over"]], n_under = o[["n_under"]],
             n_det = o[["n_det"]], TP = o[["TP"]], tp_core = o[["tp_core"]],
             tp_over = o[["tp_over"]], tp_under = o[["tp_under"]],
             n_det0 = nul[["n_det"]], TP0 = nul[["TP"]], tp_core0 = nul[["tp_core"]],
             tp_over0 = nul[["tp_over"]], tp_under0 = nul[["tp_under"]])
}

## ---- rates from summed counts -----------------------------------------------------------
# Works elementwise on vectors or matrices of summed counts (a named list).
.mcg_rate_list <- function(cn) {
  dv <- function(a, b) ifelse(is.finite(a) & is.finite(b) & b > 0, a / b, NA_real_)
  f1 <- function(r, p) ifelse(is.finite(r) & is.finite(p) & (r + p) > 0, 2 * r * p / (r + p),
                              NA_real_)
  # excess over the null, scaled by the null's headroom
  cc <- function(o, z) ifelse(is.finite(o) & is.finite(z) & z < 1, (o - z) / (1 - z), NA_real_)
  recall <- dv(cn$TP, cn$n_ref); precision <- dv(cn$tp_core, cn$n_det)
  null_recall <- dv(cn$TP0, cn$n_ref); null_precision <- dv(cn$tp_core0, cn$n_det0)
  F1 <- f1(recall, precision); null_F1 <- f1(null_recall, null_precision)
  list(recall = recall, precision = precision, F1 = F1,
       null_recall = null_recall, null_precision = null_precision, null_F1 = null_F1,
       cF1 = cc(F1, null_F1), cRecall = cc(recall, null_recall),
       cPrecision = cc(precision, null_precision),
       cRecall_over = dv(cn$tp_over - cn$tp_over0, cn$n_over - cn$tp_over0),
       cRecall_under = dv(cn$tp_under - cn$tp_under0, cn$n_under - cn$tp_under0),
       det_per_ref = dv(cn$n_det, cn$n_ref))
}
MCG_RATE_COLS <- c("recall", "precision", "F1", "null_recall", "null_precision", "null_F1",
                   "cF1", "cRecall", "cPrecision", "cRecall_over", "cRecall_under",
                   "det_per_ref")

# counts: a data.frame of summed counts (MCG_COUNT_COLS). Returns it with the
# rate columns (MCG_RATE_COLS) appended.
mcg_rates <- function(counts) {
  counts <- as.data.frame(counts, stringsAsFactors = FALSE)
  miss <- setdiff(MCG_COUNT_COLS, names(counts))
  if (length(miss)) stop("multichm_gated: missing count columns: ", paste(miss, collapse = ","),
                         call. = FALSE)
  r <- .mcg_rate_list(lapply(counts[MCG_COUNT_COLS], as.numeric))
  cbind(counts, as.data.frame(r))
}

# Pool by summing counts (never averaging rates) within groups of `by`, then
# the rates. n_cells = rows pooled.
mcg_pool <- function(rows, by = character()) {
  dt <- data.table::as.data.table(rows)
  P <- dt[, c(list(n_cells = .N), lapply(.SD, function(v) sum(as.numeric(v)))),
          by = by, .SDcols = MCG_COUNT_COLS]
  mcg_rates(as.data.frame(P))
}

## ---- calibration helpers ----------------------------------------------------------------
.mcg_ids <- function(rows) paste(rows$site, rows$plot, sep = "::")

# rows: one per (site, plot, config_id) at ONE rung. Pools the rows of `plots`
# (ids "site::plot") per configuration and returns the config_id with the
# highest criterion; ties within 1e-12 go to the smallest config_id. Every
# configuration must cover every plot (equal support).
mcg_select <- function(rows, plots, criterion = c("cF1", "F1")) {
  criterion <- match.arg(criterion)
  rows <- as.data.frame(rows, stringsAsFactors = FALSE)
  if (!is.null(rows$rung) && length(unique(rows$rung)) > 1L)
    stop("multichm_gated: mcg_select pools one rung at a time", call. = FALSE)
  rows <- rows[!is.na(rows$config_id) & .mcg_ids(rows) %in% plots, , drop = FALSE]
  plots <- unique(plots)
  if (!nrow(rows)) stop("multichm_gated: no rows for the selection plots", call. = FALSE)
  ids <- .mcg_ids(rows)
  if (anyDuplicated(paste(rows$config_id, ids)))
    stop("multichm_gated: duplicate plot rows within a configuration", call. = FALSE)
  cover <- tapply(ids, rows$config_id, function(v) length(unique(v)))
  if (any(cover != length(plots)))
    stop("multichm_gated: every configuration must cover every selection plot (",
         length(plots), " plots)", call. = FALSE)
  P <- mcg_pool(rows, "config_id")
  v <- P[[criterion]]
  if (all(is.na(v))) stop("multichm_gated: the criterion is undefined for every configuration",
                          call. = FALSE)
  v[is.na(v)] <- -Inf
  as.integer(min(P$config_id[v >= max(v) - 1e-12]))
}

# Calibration/validation split per site: assign_split(plot_table(<one row per
# plot of the site, in plot order>), seed, frac). rows carry site, plot,
# plotType and the crown-class counts n_dominant, n_codominant, n_intermediate,
# n_suppressed. The caller's RNG state is restored.
mcg_split <- function(rows, seed, frac = 0.5) {
  rows <- as.data.frame(rows, stringsAsFactors = FALSE)
  need <- c("site", "plot", "plotType", "n_dominant", "n_codominant", "n_intermediate",
            "n_suppressed")
  miss <- setdiff(need, names(rows))
  if (length(miss)) stop("multichm_gated: mcg_split needs columns ", paste(miss, collapse = ","),
                         call. = FALSE)
  u <- unique(rows[need])
  if (anyDuplicated(.mcg_ids(u)))
    stop("multichm_gated: a plot has inconsistent plotType or crown-class counts", call. = FALSE)
  old <- get0(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit(if (is.null(old)) {
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
      rm(".Random.seed", envir = .GlobalEnv)
  } else assign(".Random.seed", old, envir = .GlobalEnv), add = TRUE)
  out <- lapply(sort(unique(u$site)), function(s) {
    r <- u[u$site == s, , drop = FALSE]
    r <- r[order(r$plot), , drop = FALSE]
    a <- assign_split(plot_table(r), seed, frac)
    data.frame(site = s, plot = a$plot, split = a$split, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

# Paired contrast config_a minus config_b over `plots` (ids "site::plot") at one
# rung. rows carry site, plot, config and MCG_COUNT_COLS; config_a / config_b
# are values of `config` (a grid label or a reference detector such as
# "chm_vwf"). Both must cover every plot exactly once. Plots are resampled
# within site (mt_plot_weights); every draw weights every count column of both
# configurations, observed and null, with the same multiplicities, then
# computes the rates. Returns one row per metric: estimate_a, estimate_b,
# difference (a - b) and its percentile interval (mt_interval); the pooled
# counts and rates of both configurations are attached as attr "pooled".
mcg_contrast <- function(rows, plots, config_a, config_b, n_boot = MT_N_BOOT, seed = MT_SEED,
                         metrics = c("cF1", "F1", "cPrecision", "cRecall", "precision",
                                     "recall", "det_per_ref")) {
  rows <- as.data.frame(rows, stringsAsFactors = FALSE)
  if (!is.null(rows$rung) && length(unique(rows$rung[rows$config %in% c(config_a, config_b) &
                                                     .mcg_ids(rows) %in% plots])) > 1L)
    stop("multichm_gated: mcg_contrast compares one rung at a time", call. = FALSE)
  bad <- setdiff(metrics, MCG_RATE_COLS)
  if (length(bad)) stop("multichm_gated: unknown metrics: ", paste(bad, collapse = ","),
                        call. = FALSE)
  plots <- unique(plots)
  if (!length(plots)) stop("multichm_gated: no plots to contrast", call. = FALSE)
  W <- mt_plot_weights(sub("::.*", "", plots), sub("^[^:]*::", "", plots), n_boot, seed)
  counts <- function(cfg) {
    r <- rows[rows$config == cfg & .mcg_ids(rows) %in% plots, , drop = FALSE]
    ids <- .mcg_ids(r)
    if (anyDuplicated(ids) || !setequal(ids, rownames(W)))
      stop(sprintf("multichm_gated: configuration %s must cover each of the %d plots once",
                   cfg, nrow(W)), call. = FALSE)
    r <- r[match(rownames(W), ids), , drop = FALSE]
    lapply(stats::setNames(MCG_COUNT_COLS, MCG_COUNT_COLS), function(k) as.numeric(r[[k]]))
  }
  ca <- counts(config_a); cb <- counts(config_b)
  est <- function(cn) lapply(cn, sum)
  ea <- .mcg_rate_list(est(ca)); eb <- .mcg_rate_list(est(cb))
  draw <- function(cn) lapply(cn, function(v) drop(crossprod(W, v)))
  da <- .mcg_rate_list(draw(ca)); db <- .mcg_rate_list(draw(cb))
  out <- do.call(rbind, lapply(metrics, function(m)
    cbind(data.frame(metric = m, config_a = config_a, config_b = config_b, n_plots = nrow(W),
                     estimate_a = ea[[m]], estimate_b = eb[[m]],
                     difference = ea[[m]] - eb[[m]], stringsAsFactors = FALSE),
          mt_interval(da[[m]] - db[[m]]))))
  rownames(out) <- NULL
  attr(out, "pooled") <- cbind(data.frame(config = c(config_a, config_b), n_plots = nrow(W),
                                          stringsAsFactors = FALSE),
                               mcg_rates(rbind(as.data.frame(est(ca)), as.data.frame(est(cb)))))
  out
}
