# Open Forest Observatory second preflight: the crown-frame truth of NEON plots
# and the test of the frozen registration method against it, as declared in
# docs/ofo-preflight-protocol-2.md ("Crown-frame truth", "Test units", "Pass
# rule"). Pure functions; the driver is scripts/preflight_ofo_crowntruth.R.
# Score-blind: no detector runs. The truth of a plot is the rigid shift that
# moves its mapped stems onto crown boxes drawn by people on a camera image
# (NeonTreeEvaluation), carried into the frame of the method's canopy surface
# by a frame tie between the annotation year's canopy height model and that
# surface. The method is not changed: its estimates are read from the first
# protocol's tables, and its surface is ofo2_surface() with the frozen
# configuration.
# Needs seed_for() (model_bench_lib.R) and ofo_registration_lib.R
# (ofo_shift_grid, ofo2_lookup, ofo2_surface, ofo2_accept, OFO_REG2), which the
# caller sources.

# Every rule and threshold of protocol 2's truth and test, declared before any
# crown position was compared with a stem.
OFO_CT <- list(
  sites = c("ABBY", "WREF", "SOAP", "TEAK", "SJER", "NIWO"),
  max_shift = 12, step = 0.25,          # truth search: +/-12 m at 0.25 m
  sigma_min = 0.5, sigma_frac = 0.25,   # sigma = max(0.5 m, mean half-side / 4)
  dbh_min = 10, image_margin = 2,       # truth stems: DBH >= 10 cm, image shrunk by 2 m
  visible = c("Open grown", "Full sun", "Partially shaded"),
  height_frac = 0.6,                    # no position: height >= 0.6 x tallest live tree
  tie_max = 3, tie_step = 0.25,         # frame tie: +/-3 m at 0.25 m
  tie_margin = 3,                       # over the image shrunk by 3 m
  boot = 200L,                          # bootstrap resamples of the truth stems
  min_stems = 8L, max_s90 = 1.0, min_tie_ncc = 0.5,
  pass = list(min_units = 10L, max_median = 1.0, max_error = 2.0, min_share = 0.90),
  # Objectives within this of the maximum are exact ties (as OFO_REG2_SEARCH).
  tie_tol = 1e-12,
  # Threshold comparisons absorb rounding (a share of exactly 0.9, say).
  eps = 1e-9)

ofo_ct_grid <- function() ofo_shift_grid(OFO_CT$max_shift, OFO_CT$step)
ofo_ct_tie_grid <- function() ofo_shift_grid(OFO_CT$tie_max, OFO_CT$tie_step)

## ---- NeonTreeEvaluation files ----------------------------------------------------
# The git blob SHA-1 of a file: what a git tree lists for it. A cached file
# whose blob SHA-1 equals the pinned tree's entry holds the pinned bytes, so its
# SHA-256 is the pinned file's.
ofo_git_blob_sha1 <- function(path) {
  n <- file.size(path)
  raw <- if (n > 0) readBin(path, "raw", n) else raw(0)
  digest::digest(c(charToRaw(sprintf("blob %.0f", n)), as.raw(0L), raw), algo = "sha1",
                 serialize = FALSE)
}

# Annotations of the protocol's sites named <SITE>_<NNN>_<YEAR>.xml in a list of
# repository paths, with the image and the annotation year's canopy height
# model each needs, and whether the repository holds them.
ofo_ct_nte_files <- function(paths, sites = OFO_CT$sites) {
  pat <- sprintf("^annotations/(%s)_[0-9]{3}_[0-9]{4}[.]xml$", paste(sites, collapse = "|"))
  xml <- sort(grep(pat, paths, value = TRUE))
  id <- sub("^annotations/(.*)[.]xml$", "\\1", xml)
  rgb <- sprintf("evaluation/RGB/%s.tif", id)
  chm <- sprintf("evaluation/CHM/%s_CHM.tif", id)
  data.frame(annotation = id, plot = sub("_[0-9]{4}$", "", id), site = substr(id, 1, 4),
             ann_year = as.integer(sub("^.*_", "", id)), xml = xml, rgb = rgb, chm = chm,
             has_rgb = rgb %in% paths, has_chm = chm %in% paths, stringsAsFactors = FALSE)
}

## ---- crown boxes ------------------------------------------------------------------
# Boxes of a Pascal VOC annotation in pixels (xmin, ymin, xmax, ymax), with the
# object names; the image size it declares rides along as attributes.
ofo_ct_read_voc <- function(path) {
  doc <- xml2::read_xml(path)
  obj <- xml2::xml_find_all(doc, ".//object")
  bb <- xml2::xml_find_first(obj, "bndbox")
  num <- function(node, tag) as.numeric(xml2::xml_text(xml2::xml_find_first(node, tag)))
  out <- data.frame(name = trimws(xml2::xml_text(xml2::xml_find_first(obj, "name"))),
                    xmin = num(bb, "xmin"), ymin = num(bb, "ymin"), xmax = num(bb, "xmax"),
                    ymax = num(bb, "ymax"), stringsAsFactors = FALSE)
  size <- function(tag) suppressWarnings(as.numeric(xml2::xml_text(
    xml2::xml_find_first(doc, paste0("/annotation/size/", tag)))))
  attr(out, "width") <- size("width")
  attr(out, "height") <- size("height")
  out
}

# Pixel boxes to map coordinates with the image's geotransform. Pixel
# coordinates lie on the pixel-edge lattice with the origin at the image's
# top-left corner, x to the right and y down, as NeonTreeEvaluation and
# DeepForest convert them: x = x0 + col * res_x, y = y0 - row * res_y, where
# (x0, y0) is the top-left corner of the top-left pixel (not its centre).
# Adds the box centre, its mean half-side (the mean of half the width and half
# the height) and the objective's sigma: the larger of 0.5 m and a quarter of
# that mean half-side.
ofo_ct_boxes_map <- function(px, x0, y0, res_x, res_y = res_x) {
  xa <- x0 + px$xmin * res_x; xb <- x0 + px$xmax * res_x
  ya <- y0 - px$ymax * res_y; yb <- y0 - px$ymin * res_y
  half <- (abs(xb - xa) / 2 + abs(yb - ya) / 2) / 2
  data.frame(bxmin = pmin(xa, xb), bxmax = pmax(xa, xb), bymin = pmin(ya, yb),
             bymax = pmax(ya, yb), cx = (xa + xb) / 2, cy = (ya + yb) / 2,
             half_side = half, sigma = pmax(OFO_CT$sigma_min, OFO_CT$sigma_frac * half))
}

## ---- truth stems ------------------------------------------------------------------------
# Truth stems of one plot: live trees with a diameter of at least 10 cm, inside
# the image shrunk by 2 m, that should be visible from above: a NEON canopy
# position of open grown, full sun or partially shaded, or, where no position
# is recorded (missing or blank), a height of at least 0.6 times the height of
# the plot's tallest live tree. `st` holds the plot's stems (E, N, live,
# is_tree, stemDiameter, height, canopyPosition); `ext` is the image extent
# c(xmin, xmax, ymin, ymax). Returns, per stem, "position", "height" or ""
# (not a truth stem); the tallest live height rides along as an attribute.
ofo_ct_truth_rule <- function(st, ext) {
  live <- st$live %in% TRUE & st$is_tree %in% TRUE
  pos <- trimws(as.character(st$canopyPosition))
  pos[is.na(pos)] <- ""
  h <- suppressWarnings(as.numeric(st$height))
  hl <- h[live & is.finite(h)]
  tallest <- if (length(hl)) max(hl) else NA_real_
  m <- OFO_CT$image_margin
  inside <- is.finite(st$E) & is.finite(st$N) & st$E >= ext[1] + m & st$E <= ext[2] - m &
    st$N >= ext[3] + m & st$N <= ext[4] - m
  base <- live & is.finite(st$stemDiameter) & st$stemDiameter >= OFO_CT$dbh_min & inside
  by_pos <- base & pos %in% OFO_CT$visible
  by_h <- base & !nzchar(pos) & is.finite(h) & is.finite(tallest) &
    h >= OFO_CT$height_frac * tallest - OFO_CT$eps
  rule <- ifelse(by_pos, "position", ifelse(by_h, "height", ""))
  attr(rule, "tallest_live_m") <- tallest
  attr(rule, "n_live10_in_image") <- sum(base)
  rule
}

## ---- the estimate rule ------------------------------------------------------------------
# The estimate rule of Amendment 1b (ofo2_estimate's peak estimator) at any
# step: ofo2_estimate() refines with OFO_REG2_SEARCH$step (0.5 m), so it cannot
# serve the 0.25 m grids of protocol 2. The shift with the highest objective
# (NA counts as -Inf) is refined on each axis to the vertex of the parabola
# through it and its two neighbours, by at most half a step; exact ties take
# the centre of the tied shifts, unrefined. on_edge: that maximum (the first
# tied shift for a tie, as in ofo2_estimate) on the window's edge.
ofo_ct_estimate <- function(obj, grid, step) {
  o <- ifelse(is.na(obj), -Inf, obj)
  top <- max(o)
  edge <- max(abs(grid$dx), abs(grid$dy))
  out <- function(dx, dy, i)
    list(dx = dx, dy = dy, index = i, objective = obj[i],
         on_edge = abs(grid$dx[i]) >= edge - 1e-9 || abs(grid$dy[i]) >= edge - 1e-9)
  if (!is.finite(top)) return(list(dx = NA_real_, dy = NA_real_, index = NA_integer_,
                                   objective = NA_real_, on_edge = NA))
  tied <- which(o >= top - OFO_CT$tie_tol)
  i <- tied[1]
  if (length(tied) > 1L) return(out(mean(grid$dx[tied]), mean(grid$dy[tied]), i))
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

## ---- the truth ------------------------------------------------------------------------
# Best score of each stem over the boxes, per shift: an n x nrow(grid) matrix.
# A stem moved by shift s scores exp(-d^2 / (2 sigma_b^2)) against box b, d the
# distance from the moved stem to the box centre, and keeps its best score.
ofo_ct_scores <- function(x, y, boxes, grid) {
  S <- matrix(0, length(x), nrow(grid))
  for (b in seq_len(nrow(boxes))) {
    X <- outer(x - boxes$cx[b], grid$dx, "+")
    Y <- outer(y - boxes$cy[b], grid$dy, "+")
    S <- pmax(S, exp(-(X^2 + Y^2) / (2 * boxes$sigma[b]^2)))
  }
  S
}

# The truth of one plot in the annotation frame: the shift that moves the
# truth stems (x, y) onto the box centres, where the objective (the sum of the
# stems' best scores) peaks, by the estimate rule. Its stability: the stems are
# resampled with replacement B times (seeds seed_for("crowntruth", plot, NA,
# k)); a resample's objective weights each stem by how often it was drawn.
# s90_m is the 90th percentile (type 7) of the distances from the resampled
# estimates to the full one.
ofo_ct_truth <- function(x, y, boxes, plot, grid = ofo_ct_grid(), B = OFO_CT$boot) {
  n <- length(x)
  none <- list(dx = NA_real_, dy = NA_real_, on_edge = NA, objective = NA_real_,
               s90_m = NA_real_, boot_m = rep(NA_real_, B), n = n)
  if (!n || !nrow(boxes)) return(none)
  S <- ofo_ct_scores(x, y, boxes, grid)
  e <- ofo_ct_estimate(colSums(S), grid, OFO_CT$step)
  d <- vapply(seq_len(B), function(k) {
    set.seed(seed_for("crowntruth", plot, NA, k))
    w <- tabulate(sample.int(n, n, replace = TRUE), n)
    b <- ofo_ct_estimate(drop(w %*% S), grid, OFO_CT$step)
    sqrt((b$dx - e$dx)^2 + (b$dy - e$dy)^2)
  }, numeric(1))
  list(dx = e$dx, dy = e$dy, on_edge = e$on_edge, objective = e$objective,
       s90_m = if (all(is.finite(d))) unname(stats::quantile(d, 0.9, type = 7)) else NA_real_,
       boot_m = d, n = n)
}

## ---- the frame tie ----------------------------------------------------------------------
# Cells of the annotation year's canopy height model whose centres lie inside
# the image extent `ext` (c(xmin, xmax, ymin, ymax)) shrunk by `margin` metres,
# with a height recorded (non-finite and negative values are no-data).
ofo_ct_chm_cells <- function(chm, ext, margin = OFO_CT$tie_margin) {
  chm <- chm[[1]]
  xy <- terra::xyFromCell(chm, seq_len(terra::ncell(chm)))
  v <- terra::values(chm, mat = FALSE)
  keep <- is.finite(v) & v >= 0 & xy[, 1] >= ext[1] + margin & xy[, 1] <= ext[2] - margin &
    xy[, 2] >= ext[3] + margin & xy[, 2] <= ext[4] - margin
  data.frame(x = xy[keep, 1], y = xy[keep, 2], z = v[keep])
}

# The frame tie: the Pearson correlation, per shift t of `grid`, between the
# canopy height model at its cell centres q (the annotation frame) and the
# method's surface S (ofo2_surface() form) sampled bilinearly at q + t; the tie
# is the estimate rule's shift. A feature at p in the annotation frame lies at
# p + tie in the method's frame, so a truth T found there is T + tie in the
# method's frame. ncc is the peak correlation on the grid.
ofo_ct_tie <- function(cells, S, grid = ofo_ct_tie_grid()) {
  na <- list(dx = NA_real_, dy = NA_real_, ncc = NA_real_, on_edge = NA,
             n_cells = nrow(cells), r = rep(NA_real_, nrow(grid)))
  if (nrow(cells) < 3L) return(na)
  V <- ofo2_lookup(S, cells$x, cells$y, grid)
  a <- cells$z - mean(cells$z)
  Vc <- V - rep(colMeans(V), each = nrow(V))
  den <- sqrt(sum(a^2) * colSums(Vc^2))
  r <- colSums(a * Vc) / den
  r[!(den > 0) | !is.finite(r)] <- NA_real_
  e <- ofo_ct_estimate(r, grid, OFO_CT$tie_step)
  list(dx = e$dx, dy = e$dy, ncc = e$objective, on_edge = e$on_edge,
       n_cells = nrow(cells), r = r)
}

# The frozen method's canopy surface of a normalised clip (Amendment 1b): the
# surface both frozen signals use, built as the registration stages build it.
ofo_ct_method_surface <- function(las) {
  sm <- unique(c(OFO_REG2$height$cfg$surface, OFO_REG2$rank$cfg$surface))
  if (length(sm) != 1L) stop("The frozen signals use different surfaces")
  ofo2_surface(las, sm)
}

## ---- credibility ---------------------------------------------------------------------------
# A truth is credible when it has at least 8 truth stems, its estimate is off
# the window's edge, its bootstrap s90 is at most 1.0 m, and the frame tie's
# peak correlation is at least 0.5 with the tie off the +/-3 m edge. A missing
# value fails its rule. The reason lists every failed rule, ";"-joined (empty
# when credible).
ofo_ct_credible <- function(n, on_edge, s90_m, tie_ncc, tie_on_edge) {
  fail <- c(n = !isTRUE(n >= OFO_CT$min_stems),
            on_edge = !isFALSE(on_edge),
            s90 = !isTRUE(s90_m <= OFO_CT$max_s90 + OFO_CT$eps),
            tie_ncc = !isTRUE(tie_ncc >= OFO_CT$min_tie_ncc - OFO_CT$eps),
            tie_on_edge = !isFALSE(tie_on_edge))
  list(credible = !any(fail), reason = paste(names(fail)[fail], collapse = ";"))
}

## ---- test units ------------------------------------------------------------------------------
OFO_CT_UNIT_COLS <- c("source", "half", "plot", "signal", "variant", "n_signal", "at_min_stems",
                      "accepted", "est_dx", "est_dy", "truth_m_dx", "truth_m_dy", "credible",
                      "error_crown_m", "error_zero_m", "in_test")

# Test units from one table of the frozen method's registrations (the first
# protocol's registration_dev.csv or registration_confirm.csv, or protocol 2's
# registration_niwo.csv): the frozen variant's rows for single plots whose
# truth is in `truth` (crown_truth.csv). The estimate in the crown frame is the
# estimated shift plus the known offset; error_crown_m is its distance to the
# truth in the method's frame, error_zero_m its distance to zero (the first
# protocol's error). Acceptance is recomputed with the frozen gate and must
# agree with the table's. in_test: a credible truth, at least the frozen
# smallest stem count, accepted.
ofo_ct_units <- function(reg, source, half, truth) {
  reg <- as.data.frame(reg, stringsAsFactors = FALSE)
  truth <- as.data.frame(truth, stringsAsFactors = FALSE)
  reg <- reg[reg$frozen_variant %in% TRUE & reg$kind == "plot" & reg$unit %in% truth$plot, ,
             drop = FALSE]
  if (!nrow(reg)) return(NULL)
  frozen <- vapply(reg$signal, function(s) OFO_REG2[[s]]$variant, character(1))
  if (any(reg$variant != frozen))
    stop("Rows marked frozen_variant are not the frozen variants of OFO_REG2")
  if (anyDuplicated(paste(reg$unit, reg$signal)))
    stop("A plot has more than one frozen row per signal")
  min_st <- vapply(reg$signal, function(s) OFO_REG2[[s]]$gate$min_stems, integer(1))
  at_min <- reg$n_signal >= min_st
  if (!is.null(reg$at_min_stems) && any(as.logical(reg$at_min_stems) != at_min, na.rm = TRUE))
    stop("at_min_stems of the table differs from the frozen smallest stem count")
  run <- is.finite(reg$dx) & is.finite(reg$dy)
  acc <- vapply(seq_len(nrow(reg)), function(i) {
    g <- OFO_REG2[[reg$signal[i]]]$gate
    run[i] && ofo2_accept(reg$n_signal[i], reg$on_edge[i], reg[[g$stat]][i], g)$accepted
  }, logical(1))
  if (any(acc != (reg$accepted %in% TRUE)))
    stop("accepted of the table differs from the frozen gate for ",
         paste(reg$unit[acc != (reg$accepted %in% TRUE)], collapse = ","))
  t <- truth[match(reg$unit, truth$plot), , drop = FALSE]
  est_dx <- reg$dx + reg$offset_dx; est_dy <- reg$dy + reg$offset_dy
  err_c <- sqrt((est_dx - t$truth_m_dx)^2 + (est_dy - t$truth_m_dy)^2)
  credible <- t$credible %in% TRUE
  out <- data.frame(source = source, half = half, plot = reg$unit, signal = reg$signal,
                    variant = reg$variant, n_signal = reg$n_signal, at_min_stems = at_min,
                    accepted = acc, est_dx = est_dx, est_dy = est_dy,
                    truth_m_dx = t$truth_m_dx, truth_m_dy = t$truth_m_dy, credible = credible,
                    error_crown_m = err_c, error_zero_m = sqrt(est_dx^2 + est_dy^2),
                    in_test = credible & at_min & acc & is.finite(err_c),
                    site = reg$site, offset_dx = reg$offset_dx, offset_dy = reg$offset_dy,
                    dx = reg$dx, dy = reg$dy, sub_p90_m = reg$sub_p90_m, on_edge = reg$on_edge,
                    reject_reason = reg$reject_reason, error_m = reg$error_m,
                    truth_reason = t$reason, stringsAsFactors = FALSE)
  rownames(out) <- NULL
  out
}

## ---- pass rule ------------------------------------------------------------------------------
# The pass rule over one signal's test units: at least 10 units, a median error
# of at most 1.0 m and at least 90% of units within 2.0 m (shares compared in
# counts). With fewer than 10 units the test is inconclusive and does not pass.
ofo_ct_pass <- function(error_m, rules = OFO_CT$pass) {
  e <- error_m[is.finite(error_m)]
  n <- length(e)
  med <- if (n) stats::median(e) else NA_real_
  k <- sum(e <= rules$max_error + OFO_CT$eps)
  inconclusive <- n < rules$min_units
  list(units = n, median_error_m = med, n_within_2m = k,
       share_within_2m = if (n) k / n else NA_real_,
       pass = !inconclusive && isTRUE(med <= rules$max_median + OFO_CT$eps) &&
         k * 100 >= round(rules$min_share * 100) * n,
       inconclusive = inconclusive)
}

OFO_CT_SUBSETS <- list(
  benchmark_development = function(u) u$source == "benchmark" & u$half == "development",
  benchmark_confirmation = function(u) u$source == "benchmark" & u$half == "confirmation",
  benchmark = function(u) u$source == "benchmark",
  niwo = function(u) u$source == "niwo")

# Per signal: the pass rule over every test unit (the admission), the same
# figures per subset (reported apart, not tested), the first protocol's error
# over the same units for comparison, and the units left out with the first
# rule each fails.
ofo_ct_test <- function(units, signals = c("height", "rank")) {
  sapply(signals, function(s) {
    u <- units[units$signal == s, , drop = FALSE]
    t <- u[u$in_test %in% TRUE, , drop = FALSE]
    out <- ofo_ct_pass(t$error_crown_m)
    why <- ifelse(!is.finite(u$est_dx), "not_run",
                  ifelse(!u$at_min_stems, "below_min_stems",
                         ifelse(!u$accepted, "not_accepted",
                                ifelse(!u$credible, "truth_not_credible", "in_test"))))
    c(list(variant = OFO_REG2[[s]]$variant, min_stems = OFO_REG2[[s]]$gate$min_stems),
      out, list(admitted = isTRUE(out$pass),
                subsets = lapply(OFO_CT_SUBSETS, function(f)
                  ofo_ct_pass(t$error_crown_m[f(t)])),
                error_zero_same_units = ofo_ct_pass(t$error_zero_m),
                units_by_outcome = as.list(table(factor(why, c(
                  "in_test", "truth_not_credible", "not_accepted", "below_min_stems",
                  "not_run"))))))
  }, simplify = FALSE)
}
