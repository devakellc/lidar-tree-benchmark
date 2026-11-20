# Measured density of the scored area. The frozen-clip provider records each
# clip's density over the whole evaluation clip (nominal plot core plus a 25 m
# buffer), but detections are scored inside the nominal core only, and the
# thinning (lidR::homogenize on a 5 m grid that is not aligned with the clip)
# leaves the clip's outer cells denser than its interior. These helpers count
# first returns and all returns of a normalized clip inside the core, in the
# clip's outer 5 m ring and over the whole clip, with the provider's own height
# filter. Pure functions; driver: core_density.R.

# The provider's height filter on the normalized clip (frozen_clip(), as in
# model_bench_lib.R): Z >= -1 and Z < 80, both in metres.
CD_Z_MIN <- -1
CD_Z_MAX <- 80
# Width of the outer ring of the clip, the 5 m thinning grid's cell size.
CD_RING <- 5
# Quality-level floors of first-return (pulse) density, pulses/m².
CD_FLOORS <- c(QL2 = 2, QL1 = 8)

## ---- counts of one clip ------------------------------------------------------
# X, Y, Z and ReturnNumber of one normalized clip; the clip is the square of
# half-side core_half + buffer around (cx, cy), the core the square of
# half-side core_half (bounds included, as score_plot() cuts detections). The
# ring is the clip outside the square of half-side core_half + buffer - ring.
# Densities divide by the nominal areas, as the clip manifest does.
cd_counts <- function(X, Y, Z, ReturnNumber, cx, cy, core_half, buffer, ring = CD_RING) {
  n <- length(X)
  if (length(Y) != n || length(Z) != n || length(ReturnNumber) != n)
    stop("X, Y, Z and ReturnNumber must have the same length")
  if (!is.finite(core_half) || core_half <= 0 || !is.finite(buffer) || buffer < 0 ||
      ring <= 0 || ring > core_half + buffer)
    stop("Invalid clip geometry")
  if (anyNA(X) || anyNA(Y) || anyNA(Z) || anyNA(ReturnNumber)) stop("Missing coordinates or return numbers")
  half <- core_half + buffer
  keep <- Z >= CD_Z_MIN & Z < CD_Z_MAX
  dx <- abs(X - cx); dy <- abs(Y - cy)
  # One LAS coordinate step (0.01 m) of slack: the provider snaps coordinates
  # to the LAS grid after clipping.
  if (any(dx[keep] > half + 0.01 | dy[keep] > half + 0.01))
    stop("Points outside the clip; is (cx, cy) the clip centre?")
  first <- ReturnNumber == 1L
  core <- keep & dx <= core_half & dy <= core_half
  outer <- keep & (dx > half - ring | dy > half - ring)
  a_clip <- (2 * half)^2; a_core <- (2 * core_half)^2; a_ring <- a_clip - (2 * (half - ring))^2
  out <- data.frame(n_all_clip = sum(keep), n_fr_clip = sum(keep & first),
                    n_all_core = sum(core), n_fr_core = sum(core & first),
                    n_all_ring = sum(outer), n_fr_ring = sum(outer & first),
                    n_dropped_z = sum(!keep))
  out$clip_pdens <- out$n_all_clip / a_clip; out$clip_frdens <- out$n_fr_clip / a_clip
  out$core_pdens <- out$n_all_core / a_core; out$core_frdens <- out$n_fr_core / a_core
  out$ring_pdens <- out$n_all_ring / a_ring; out$ring_frdens <- out$n_fr_ring / a_ring
  out
}

# The same for a lidR LAS object (a normalized clip).
cd_counts_las <- function(las, cx, cy, core_half, buffer, ring = CD_RING) {
  d <- las@data
  cd_counts(d$X, d$Y, d$Z, d$ReturnNumber, cx, cy, core_half, buffer, ring)
}

## ---- agreement with the clip manifest ---------------------------------------------
# Rows whose recomputed whole-clip densities differ from the recorded ones by
# more than tol (absolute, or relative to the larger density). The per-cell
# manifest.json and clip_manifest.csv both store densities to 15 significant
# digits, so a comparison needs a relative tolerance of about 1e-13.
cd_mismatch <- function(x, recorded_fr, recorded_all, tol = 0, relative = FALSE) {
  scale <- if (relative) pmax(abs(recorded_fr), abs(recorded_all), 1) else 1
  d <- pmax(abs(x$clip_frdens - recorded_fr), abs(x$clip_pdens - recorded_all)) / scale
  which(is.na(d) | d > tol)
}

## ---- summaries --------------------------------------------------------------------
# One row per rung and scope: cells, the median, quartiles and range of core
# and whole-clip first-return density, median all-return density of the core,
# the whole clip and the outer ring, the numbers of cores and of clips below
# the QL2 (2) and QL1 (8) floors, and the median core/clip ratio of
# first-return density. `x` holds the per-cell rows (site, rung, core_frdens,
# clip_frdens, core_pdens, clip_pdens, ring_pdens); `scopes` maps a scope
# name to its sites.
cd_summary_row <- function(x) {
  q <- function(v, p) unname(stats::quantile(v, p, names = FALSE))
  data.frame(cells = nrow(x),
             core_frdens_median = stats::median(x$core_frdens),
             core_frdens_q25 = q(x$core_frdens, 0.25), core_frdens_q75 = q(x$core_frdens, 0.75),
             core_frdens_min = min(x$core_frdens), core_frdens_max = max(x$core_frdens),
             clip_frdens_median = stats::median(x$clip_frdens),
             clip_frdens_q25 = q(x$clip_frdens, 0.25), clip_frdens_q75 = q(x$clip_frdens, 0.75),
             clip_frdens_min = min(x$clip_frdens), clip_frdens_max = max(x$clip_frdens),
             core_pdens_median = stats::median(x$core_pdens),
             clip_pdens_median = stats::median(x$clip_pdens),
             ring_pdens_median = stats::median(x$ring_pdens),
             cores_below_2 = sum(x$core_frdens < CD_FLOORS[["QL2"]]),
             clips_below_2 = sum(x$clip_frdens < CD_FLOORS[["QL2"]]),
             cores_below_8 = sum(x$core_frdens < CD_FLOORS[["QL1"]]),
             clips_below_8 = sum(x$clip_frdens < CD_FLOORS[["QL1"]]),
             core_over_clip_median = stats::median(x$core_frdens / x$clip_frdens))
}
cd_summary <- function(x, scopes, rungs = unique(x$rung)) {
  x <- as.data.frame(x)
  if (!all(x$rung %in% rungs)) stop("Rows at rungs not listed: ",
                                    paste(setdiff(unique(x$rung), rungs), collapse = ", "))
  out <- do.call(rbind, lapply(rungs, function(r) do.call(rbind, lapply(names(scopes), function(sc) {
    y <- x[x$rung == r & x$site %in% scopes[[sc]], , drop = FALSE]
    if (!nrow(y)) return(NULL)
    cbind(data.frame(rung = r, scope = sc, stringsAsFactors = FALSE), cd_summary_row(y))
  }))))
  rownames(out) <- NULL
  out
}

## ---- the sparse-flight comparison ------------------------------------------------------
# `x` holds one row per plot and cell ("sparse native", "2021 8", "2021 4",
# ...) with clip_frdens and core_frdens. Per scope: plots, the median density
# of each cell, and the numbers of sparse clouds denser than their 2021
# rung-8 clip and sparser than their rung-4 clip, by whole-clip and by core
# density.
cd_sparse_summary <- function(x, scopes) {
  x <- as.data.frame(x)
  need <- c("sparse native", "2021 8", "2021 4")
  w <- function(col) {
    v <- stats::reshape(x[c("site", "plot", "cell", col)], idvar = c("site", "plot"),
                        timevar = "cell", direction = "wide")
    names(v) <- sub(paste0("^", col, "\\."), "", names(v))
    v
  }
  core <- w("core_frdens"); clip <- w("clip_frdens")
  if (!all(need %in% names(core))) stop("Each plot needs the cells ", paste(need, collapse = ", "))
  if (anyNA(core[need]) || anyNA(clip[need])) stop("A plot lacks one of the compared cells")
  cells <- intersect(c("sparse native", "2021 native", "2021 8", "2021 4"), names(core))
  out <- do.call(rbind, lapply(names(scopes), function(sc) {
    k <- core$site %in% scopes[[sc]]; kc <- clip$site %in% scopes[[sc]]
    if (!any(k)) return(NULL)
    row <- data.frame(scope = sc, plots = sum(k), stringsAsFactors = FALSE)
    for (cl in cells) {
      tag <- gsub(" ", "_", cl)
      row[[paste0("core_", tag)]] <- stats::median(core[[cl]][k])
      row[[paste0("clip_", tag)]] <- stats::median(clip[[cl]][kc])
    }
    row$denser_than_8_core <- sum(core$`sparse native`[k] > core$`2021 8`[k])
    row$denser_than_8_clip <- sum(clip$`sparse native`[kc] > clip$`2021 8`[kc])
    row$sparser_than_4_core <- sum(core$`sparse native`[k] < core$`2021 4`[k])
    row$sparser_than_4_clip <- sum(clip$`sparse native`[kc] < clip$`2021 4`[kc])
    row$bracketed_core <- row$plots - row$denser_than_8_core - row$sparser_than_4_core
    row$bracketed_clip <- row$plots - row$denser_than_8_clip - row$sparser_than_4_clip
    row
  }))
  rownames(out) <- NULL
  out
}
