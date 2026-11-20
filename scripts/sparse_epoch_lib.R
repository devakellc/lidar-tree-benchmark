# Helpers of the native-epoch scripts (prepare_sparse_epoch.R,
# compare_sparse_epoch.R, epoch_stand_measures.R): which listed 1 km tiles the
# plot clips need when a flight does not cover every plot, and which plots two
# sealed roots share. Pure functions; the caller sources neon_acquisition_lib.R
# (neon_required_tiles) and site_extension_lib.R (EXT_CLIP_BUF) first.

# Tiles of each clip box (core half-extent h plus `buffer`) and whether every
# one is listed. `boxes` holds plotID, x, y, h; one plot may have several boxes
# (its centroid in each reference). Adds needed and missing (";"-joined keys)
# and covered.
se_box_coverage <- function(boxes, listed, buffer = EXT_CLIP_BUF) {
  keys <- lapply(seq_len(nrow(boxes)), function(j)
    neon_required_tiles(boxes$x[j], boxes$y[j], boxes$h[j] + buffer))
  boxes$needed <- vapply(keys, paste, character(1), collapse = ";")
  boxes$missing <- vapply(keys, function(k) paste(setdiff(k, listed), collapse = ";"),
                          character(1))
  boxes$covered <- !nzchar(boxes$missing)
  boxes
}

# The tiles to acquire when plots without listed tiles are dropped. A plot is
# uncovered when any of its boxes needs a tile the listing lacks; the tiles of
# the covered plots are needed. An uncovered plot whose boxes reach a needed
# tile would freeze a partial clip from the tiles that are present, so that
# stops. Returns list(needed = sorted keys, uncovered = one row per uncovered
# plot with its missing tiles).
se_drop_uncovered <- function(boxes, listed, buffer = EXT_CLIP_BUF) {
  cov <- se_box_coverage(boxes, listed, buffer)
  bad <- sort(unique(cov$plotID[!cov$covered]))
  keep <- !cov$plotID %in% bad
  split_keys <- function(v) unlist(strsplit(v, ";", fixed = TRUE))
  needed <- sort(unique(split_keys(cov$needed[keep])))
  partial <- vapply(bad, function(p)
    any(split_keys(cov$needed[cov$plotID == p]) %in% needed), logical(1))
  if (any(partial))
    stop("Plots partly covered by the needed tiles would freeze partial clips: ",
         paste(bad[partial], collapse = ","))
  uncovered <- data.frame(plotID = bad, missing_tiles = vapply(bad, function(p)
    paste(sort(unique(split_keys(cov$missing[cov$plotID == p]))), collapse = ";"),
    character(1)), stringsAsFactors = FALSE)
  rownames(uncovered) <- NULL
  list(needed = needed, uncovered = uncovered)
}

# Share of a clip's scoring core (half-extent `half` around cx, cy) whose
# `res` m cells hold at least one of the points (x, y): how much of the core
# the flight covered. A plot at the edge of a flight can freeze an "ok" clip
# that holds no return over part of its core.
se_core_cover <- function(x, y, cx, cy, half, res = 2) {
  n <- ceiling(2 * half / res)
  i <- floor((x - (cx - half)) / res); j <- floor((y - (cy - half)) / res)
  k <- i >= 0 & i < n & j >= 0 & j < n
  length(unique(i[k] * n + j[k])) / n^2
}

# Plots of `site` adopted in both populations (population.csv of each root),
# in the order of the 2021 population. With manifests (clip_manifest.csv of
# each root), only plots whose native clip is "ok" in both roots are kept: a
# plot the flight did not cover has no clip to score on that side.
se_common_plots <- function(pop21, popS, site, cm21 = NULL, cmS = NULL) {
  common <- intersect(pop21$plotID[pop21$site == site & pop21$in_adopted],
                      popS$plotID[popS$site == site & popS$in_adopted])
  if (is.null(cm21) && is.null(cmS)) return(common)
  if (is.null(cm21) || is.null(cmS)) stop("Give the clip manifests of both roots")
  ok <- function(cm) cm$plot[cm$site == site & cm$rung == "native" & cm$status == "ok"]
  intersect(common, intersect(ok(cm21), ok(cmS)))
}
