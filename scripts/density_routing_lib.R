# Density-routed detection: each cell (one plot at one density level) is
# routed to a detector by its measured first-return density, each band's
# detector is chosen on the development region, and the routes are scored
# with the master tables' paired plot resamples. Pure functions; sourced after
# master_tables_lib.R (mt_boot_scores, mt_interval). Driver:
# paper_density_routing.R.

# Bands of measured first-return density in pulses/m², at the USGS aggregate
# nominal pulse density floors of quality levels 1 (8) and 2 (2).
DR_BANDS <- data.frame(
  band  = c("A", "B", "C"),
  lower = c(8, 2, 0),
  upper = c(Inf, 8, 2),
  label = c("QL1 or denser", "QL2 to QL1", "below QL2"),
  stringsAsFactors = FALSE)
DR_COUNTS <- c("TP", "n_ref", "n_det", "tp_core")
# Candidates: the eight detectors run at every density level. A route with a
# GPU may use all of them; a route with only a CPU the five classical ones.
DR_CANDIDATES <- list(
  gpu = c("forestformer3d", "segmentanytree", "treeisonet", "multichm", "chm_vwf",
          "ams3d", "ptrees", "lmfauto"),
  cpu = c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d"))

## ---- bands ---------------------------------------------------------------------
# Band of each cell: A at 8 pulses/m² or more, B from 2 to below 8, C below 2.
dr_band <- function(frdens) {
  if (!length(frdens) || anyNA(frdens) || any(!is.finite(frdens)) || any(frdens < 0))
    stop("Every cell needs a finite, non-negative measured first-return density")
  DR_BANDS$band[match(findInterval(frdens, c(0, 2, 8)), 3:1)]
}

## ---- selection -----------------------------------------------------------------
# Per band, the candidate with the highest value (the pooled F1 of the
# selection cells). `scores` holds one row per band and detector. Every
# candidate must be scored in every band. The design declares no tie-break, so
# an exact tie for the best stops. Returns one row per band with the pick, its
# value, the runner-up and the margin.
dr_pick <- function(scores, candidates, value = "F1") {
  scores <- as.data.frame(scores)
  x <- scores[scores$detector %in% candidates, , drop = FALSE]
  if (!nrow(x)) stop("No candidate is scored")
  out <- lapply(split(x, x$band), function(b) {
    if (anyDuplicated(b$detector) || !setequal(b$detector, candidates))
      stop("Band ", b$band[1], " does not score every candidate exactly once")
    v <- b[[value]]
    if (anyNA(v)) stop("Undefined ", value, " in band ", b$band[1])
    o <- order(-v)
    if (length(o) > 1 && v[o[1]] == v[o[2]])
      stop("Tie for the best ", value, " in band ", b$band[1], ": ",
           b$detector[o[1]], " and ", b$detector[o[2]], " (no tie-break is declared)")
    two <- length(o) > 1
    data.frame(band = b$band[1], pick = b$detector[o[1]], value = v[o[1]],
               runner_up = if (two) b$detector[o[2]] else NA_character_,
               runner_up_value = if (two) v[o[2]] else NA_real_,
               margin = if (two) v[o[1]] - v[o[2]] else NA_real_,
               stringsAsFactors = FALSE)
  })
  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}

## ---- routed cells --------------------------------------------------------------
# The rows a policy scores: for every cell, the row of the detector its band
# is routed to (`picks`: band -> pick). Every band present needs a pick, and
# every cell and variant must then hold exactly one row, so a route never
# drops or duplicates a cell.
dr_route_cells <- function(cells, picks, policy) {
  cells <- as.data.frame(cells)
  p <- setNames(picks$pick, picks$band)
  if (anyDuplicated(names(p))) stop("A band has more than one pick")
  miss <- setdiff(unique(cells$band), names(p))
  if (length(miss)) stop("No pick for band ", paste(miss, collapse = ", "))
  x <- cells[cells$detector == unname(p[cells$band]), , drop = FALSE]
  key <- function(z) paste(z$variant, z$site, z$plot, z$level, sep = "::")
  want <- unique(key(cells))
  if (anyDuplicated(key(x)) || !setequal(key(x), want))
    stop("Policy ", policy, " does not hold exactly one row per cell")
  x$policy <- rep(policy, nrow(x))
  rownames(x) <- NULL
  x
}

## ---- pooled rows for the plot resamples -----------------------------------------
# Per-plot sums of the counts of each group, with a zero row for every plot of
# `plot_ids` ("site::plot", the row names of the resample matrix) in which a
# group has no cell, so that every group covers the resampled plots as
# mt_boot_scores() requires. A plot's cells at several density levels are
# summed, so they move together under the plot resamples.
dr_plot_rows <- function(cells, group_cols, plot_ids) {
  cells <- as.data.frame(cells)
  if (!nrow(cells)) stop("No cells to pool")
  id <- paste(cells$site, cells$plot, sep = "::")
  if (!all(id %in% plot_ids)) stop("Cells outside the resampled plots: ",
                                   paste(head(setdiff(id, plot_ids)), collapse = ", "))
  if (anyNA(cells[DR_COUNTS])) stop("Missing counts")
  grp <- do.call(paste, c(cells[group_cols], sep = "|"))
  groups <- unique(grp)
  sums <- rowsum(as.matrix(cells[DR_COUNTS]), paste(grp, id, sep = "\r"), reorder = FALSE)
  full <- paste(rep(groups, each = length(plot_ids)), rep(plot_ids, length(groups)), sep = "\r")
  m <- matrix(0, length(full), length(DR_COUNTS), dimnames = list(NULL, DR_COUNTS))
  m[match(rownames(sums), full), ] <- sums
  keys <- cells[match(groups, grp), group_cols, drop = FALSE]
  ids <- rep(plot_ids, length(groups))
  out <- data.frame(site = sub("::.*$", "", ids), plot = sub("^[^:]*::", "", ids),
                    keys[rep(seq_along(groups), each = length(plot_ids)), , drop = FALSE],
                    m, row.names = NULL, stringsAsFactors = FALSE, check.names = FALSE)
  out
}

## ---- metrics, intervals and paired differences ------------------------------------
# One group's estimate and per-draw values. Groups of the score set are keyed
# "<variant>|<key>", with the variants "baseline" (observed) and "null" (each
# cell's mean counts over the random shifts). F1_null is the null variant's
# F1; F1_corrected is (F1 - null F1) / (1 - null F1), for the estimate and
# for every draw, as paper_sensitivity.R scales it.
DR_METRICS <- c("recall", "precision", "F1", "F1_null", "F1_corrected")
dr_metric <- function(s, key, metric = "F1") {
  get <- function(variant, m) {
    i <- match(paste(variant, key, sep = "|"), s$groups)
    if (is.na(i)) stop("Unknown group: ", paste(variant, key, sep = "|"))
    list(e = unname(s$estimate[[m]][i]), d = unname(s$draws[[m]][, i]))
  }
  switch(metric,
         F1_corrected = {
           o <- get("baseline", "F1"); n <- get("null", "F1")
           list(e = (o$e - n$e) / (1 - n$e), d = (o$d - n$d) / (1 - n$d))
         },
         F1_null = get("null", "F1"),
         get("baseline", metric))
}
dr_estimate <- function(s, key, metric = "F1") {
  m <- dr_metric(s, key, metric)
  cbind(data.frame(metric = metric, estimate = m$e, stringsAsFactors = FALSE),
        mt_interval(m$d))
}
# Paired difference key - versus on the same resamples.
dr_contrast <- function(s, key, versus, metric = "F1") {
  a <- dr_metric(s, key, metric); b <- dr_metric(s, versus, metric)
  cbind(data.frame(metric = metric, estimate = a$e - b$e, stringsAsFactors = FALSE),
        mt_interval(a$d - b$d))
}

## ---- agreement with a reference table ----------------------------------------------
# Rows of `here` and `ref` (joined on `by`) whose `cols` differ by more than
# `tol`, or that are missing on either side. An empty result means agreement.
dr_mismatch <- function(here, ref, by, cols, tol = 1e-9) {
  m <- merge(here, ref, by = by, all = TRUE, suffixes = c("", "_ref"))
  bad <- rep(FALSE, nrow(m))
  for (k in cols) {
    a <- m[[k]]; b <- m[[paste0(k, "_ref")]]
    bad <- bad | is.na(a) | is.na(b) | abs(a - b) > tol
  }
  m[bad, , drop = FALSE]
}

## ---- formatting --------------------------------------------------------------------
dr_fmt <- function(e, l, u, signed = FALSE) {
  f <- if (signed) "%+.3f [%+.3f, %+.3f]" else "%.3f [%.3f, %.3f]"
  out <- ifelse(is.na(e), "—", sprintf(f, e, l, u))
  gsub("-", "−", out, fixed = TRUE)
}
