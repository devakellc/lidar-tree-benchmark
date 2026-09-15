#!/usr/bin/env Rscript
# Pure helpers for the #V5 coverage-gap crediting study (coverage_gap.R):
# modality-family mapping, best_treetop_cache readers, and optical-box ->
# detection conversion. No I/O beyond the explicit readers; unit-tested with
# synthetic fixtures in tests/testthat/test-coverage-gap.R.

## ---- modality families -----------------------------------------------------
# Crediting independence is defined at the FAMILY level, not the arm level:
# errors correlate strongly within a family (all CHM local-maxima share the
# same surface artefacts; the RGB arms share the same imagery), so "co-detected
# by >= min_fam families" is the meaningful independence test, and a target
# arm's own family never testifies for it.
FAMILY_MAP <- c(
  chm_vwf = "chm", lmfauto = "chm", multichm = "chm",
  ptrees = "pc", ams3d = "pc", li2012 = "pc", lidr_li2012 = "pc",
  lidr_lmf_pc = "pc", lasr_lmax_pc = "pc",
  treeisonet = "deep", segmentanytree = "deep", forestformer3d = "deep",
  deepforest = "rgb", detectree2 = "rgb")

arm_family <- function(arm) unname(FAMILY_MAP[as.character(arm)])

## ---- best_treetop_cache reader ---------------------------------------------
# Reads one arm's cached (x, y, z-AGL) detections for a (site, plot, rung) cell
# as written by export_best_treetops_geojson.R: either the plain
# <arm>__<site>__<plot>__<rung>.csv or the param-suffixed
# <arm>__<site>__<plot>__<rung>__<params...>.csv (chm_vwf / treeisonet / the
# GPU arms). The arm name anchors the whole basename, so "li2012" can never
# swallow a "lidr_li2012" file. NULL = no cache / unreadable / wrong schema.
read_arm_cache <- function(dir, arm, site, plot, rung, params = NULL) {
  stem <- sprintf("%s__%s__%s__%s", arm, site, plot, rung)
  candidates <- c(file.path(dir, paste0(stem, ".csv")),
                   Sys.glob(file.path(dir, paste0(stem, "__*.csv"))))
  candidates <- unique(candidates[file.exists(candidates)])
  if (!is.null(params)) {
    suffix <- if (length(params)) paste0("__", paste(params, collapse = "__")) else ""
    hit <- file.path(dir, paste0(stem, suffix, ".csv"))
    if (!file.exists(hit)) {
      if (length(candidates)) warning("read_arm_cache: pinned variant missing: ",
                                      basename(hit), "; cell skipped", call. = FALSE)
      return(NULL)
    }
  } else {
    if (!length(candidates)) return(NULL)
    if (length(candidates) > 1L) {
      warning("read_arm_cache: ambiguous variants for ", stem,
              "; regenerate the selection manifest", call. = FALSE)
      return(NULL)
    }
    hit <- candidates[1]
  }
  det <- tryCatch(read.csv(hit, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(det) || !all(c("x", "y", "z") %in% names(det))) return(NULL)
  data.frame(x = as.numeric(det$x), y = as.numeric(det$y), z = as.numeric(det$z))
}

## ---- per-cell crediting orchestration ---------------------------------------
# Counts how many of a target arm's ISOLATED core FPs (fps: x, y, isolated from
# fp_points) are co-detected by witness FPs (wit: x, y, fam, isolated pooled
# over the other arms). Only isolated witnesses testify (a near-FP is over-seg
# of a mapped tree, not evidence of an unmapped one) and the target arm's own
# family is struck from the witness pool before co_detect_credit runs.
credit_isolated <- function(fps, wit, target_fam, r = 2.0, min_fam = 2) {
  # Prefer the hardened credit_eligible flag (isolated AND not near ANY mapped
  # stem) on both sides when present; fall back to the #V4 isolated split.
  et <- if (!is.null(fps$credit_eligible)) fps$credit_eligible else fps$isolated
  iso <- fps[et, , drop = FALSE]
  if (!nrow(iso)) return(0L)
  ew <- if (!is.null(wit$credit_eligible)) wit$credit_eligible else wit$isolated
  w <- wit[ew & wit$fam != target_fam, , drop = FALSE]
  cr <- co_detect_credit(iso$x, iso$y, w$x, w$y, w$fam, r = r, min_fam = min_fam)
  if (!any(cr)) return(0L)
  # One credit per probable tree, not per duplicate detection: credited FPs
  # within r of an already-counted credit are over-segmentation of the SAME
  # unmapped tree and must stay in the precision denominator. Greedy
  # suppression in deterministic (x, y) order.
  cx <- iso$x[cr]; cy <- iso$y[cr]
  o <- order(cx, cy)
  n <- 0L; kx <- numeric(0); ky <- numeric(0)
  for (i in o) {
    if (!length(kx) || all(sqrt((kx - cx[i])^2 + (ky - cy[i])^2) > r)) {
      n <- n + 1L; kx <- c(kx, cx[i]); ky <- c(ky, cy[i])
    }
  }
  n
}

## ---- best-configuration selection manifest -----------------------------------
# Reads export_best_treetops_geojson.R's best_treetop_selection.csv and returns
# the (method, rung) rows selected for `site` -- the authoritative "each arm at
# its best tested configuration" manifest, so stale extra cache files can never
# add cells. NULL when the manifest is absent/unreadable (legacy discovery).
# A valid manifest without this site returns zero rows and selects no cells.
read_selection <- function(path, site) {
  if (!file.exists(path)) return(NULL)
  s <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(s) || !all(c("site", "method", "rung") %in% names(s))) return(NULL)
  keep <- intersect(c("site", "method", "rung", "chm_res", "vwf_a", "cache_suffix"), names(s))
  s <- s[s$site == site, keep, drop = FALSE]
  s$rung <- as.character(s$rung)
  s
}

# Empty suffix pins a plain cache; NULL is reserved for legacy unpinned reads.
selection_cache_params <- function(sel) {
  if ("cache_suffix" %in% names(sel) && !is.na(sel$cache_suffix[1])) {
    suffix <- as.character(sel$cache_suffix[1])
    return(if (nzchar(suffix)) suffix else character(0))
  }
  if (sel$method[1] == "chm_vwf" &&
      all(c("chm_res", "vwf_a") %in% names(sel)) &&
      is.finite(sel$chm_res[1]) && is.finite(sel$vwf_a[1]))
    return(c(sprintf("res%s", sel$chm_res[1]), sprintf("a%s", sel$vwf_a[1])))
  NULL
}

read_selected_cache <- function(dir, arm, site, plot, rung, selection) {
  if (is.null(selection)) return(read_arm_cache(dir, arm, site, plot, rung))
  sel <- selection[selection$method == arm & selection$rung == rung, , drop = FALSE]
  if (!nrow(sel)) return(NULL)
  if (nrow(sel) != 1L) stop("multiple selected configurations for ", arm, call. = FALSE)
  read_arm_cache(dir, arm, site, plot, rung, selection_cache_params(sel))
}

# Enumerate the rungs an arm has cached for one plot (each arm is cached at
# its best tested rung, so this is usually one row). Returns data.frame(arm,
# rung); 0 rows when the arm never cached this plot. rung is the 4th "__"
# token with any param suffix and the .csv extension stripped.
cached_rungs <- function(dir, arm, site, plot) {
  none <- data.frame(arm = character(), rung = character(),
                     stringsAsFactors = FALSE)
  g <- basename(Sys.glob(file.path(dir, sprintf("%s__%s__%s__*.csv",
                                                arm, site, plot))))
  if (!length(g)) return(none)
  rung <- vapply(strsplit(sub("\\.csv$", "", g), "__", fixed = TRUE),
                 function(p) if (length(p) >= 4) p[4] else NA_character_,
                 character(1))
  rung <- unique(rung[!is.na(rung)])
  if (!length(rung)) return(none)
  data.frame(arm = arm, rung = rung, stringsAsFactors = FALSE)
}

## ---- optical boxes -> apex detections ---------------------------------------
# Converts an RGB crown-box table (x, y = box centre in UTM; optional score) to
# the (x, y, z) detection contract, mirroring detect_deepforest_sweep.R: apex z
# is read from the plot's native frozen CHM at the box centre and floored at
# z_floor (the detector min_height) where the box falls off the CHM. chm = NULL
# floors everything (callers should treat that as a degraded fallback).
boxes_to_dets <- function(boxes, chm, score_min = 0, z_floor = 2.0, keep_score = FALSE) {
  empty <- data.frame(x = numeric(), y = numeric(), z = numeric())
  if (keep_score) empty$score <- numeric()
  if (is.null(boxes) || !nrow(boxes)) return(empty)
  keep <- is.finite(boxes$x) & is.finite(boxes$y)
  if (!is.null(boxes$score)) keep <- keep & is.finite(boxes$score) & boxes$score >= score_min
  b <- boxes[keep, , drop = FALSE]
  if (!nrow(b)) return(empty)
  z <- if (!is.null(chm))
    as.numeric(terra::extract(chm, cbind(b$x, b$y))[, 1]) else rep(NA_real_, nrow(b))
  z[!is.finite(z)] <- z_floor
  out <- data.frame(x = b$x, y = b$y, z = z)
  if (keep_score) out$score <- if (is.null(b$score)) NA_real_ else b$score
  out
}

# Require completed RGB tiles over the whole scoring window. An empty CSV is a
# completed detector run; an absent CSV or missing tile is unavailable evidence.
deepforest_plot_boxes <- function(nd, site, cx, cy, half, year = "2021") {
  tifs <- list.files(file.path(nd, "rgb"), pattern = "\\.tif$", recursive = TRUE,
                     full.names = TRUE)
  tifs <- tifs[startsWith(basename(tifs), paste0(year, "_", site, "_"))]
  if (!length(tifs)) return(NULL)
  extents <- lapply(tifs, function(f) as.vector(terra::ext(terra::rast(f))))
  hit <- vapply(extents, function(e) e[1] < cx + half && e[2] > cx - half &&
                  e[3] < cy + half && e[4] > cy - half, logical(1))
  if (!any(hit)) return(NULL)
  corners <- expand.grid(x = cx + c(-half, half), y = cy + c(-half, half))
  covered <- vapply(seq_len(nrow(corners)), function(i)
    any(vapply(extents[hit], function(e) corners$x[i] >= e[1] && corners$x[i] <= e[2] &&
                 corners$y[i] >= e[3] && corners$y[i] <= e[4], logical(1))), logical(1))
  if (!all(covered)) return(NULL)
  paths <- file.path(nd, "deepforest_boxes", sub("\\.tif$", ".csv", basename(tifs[hit])))
  if (!all(file.exists(paths))) return(NULL)
  boxes <- lapply(paths, function(p) read.csv(p, stringsAsFactors = FALSE))
  if (!all(vapply(boxes, function(b) all(c("x", "y", "score") %in% names(b)), logical(1))))
    stop("invalid DeepForest box cache", call. = FALSE)
  b <- as.data.frame(data.table::rbindlist(boxes, fill = TRUE))
  b[is.finite(b$x) & is.finite(b$y) & abs(b$x - cx) <= half &
      abs(b$y - cy) <= half, , drop = FALSE]
}

deepforest_plot_detections <- function(nd, site, pid, cx, cy, half, year = "2021") {
  boxes <- deepforest_plot_boxes(nd, site, cx, cy, half, year)
  if (is.null(boxes)) return(NULL)
  clip <- file.path(nd, "frozen", site, pid, "native", "clip_normalized.laz")
  if (!file.exists(clip)) return(NULL)
  las <- suppressWarnings(lidR::readLAS(clip))
  if (is.null(las) || lidR::is.empty(las)) return(NULL)
  chm <- suppressWarnings(lidR::rasterize_canopy(las, res = 0.5, algorithm = lidR::p2r()))
  if (is.null(chm)) return(NULL)
  boxes_to_dets(boxes, chm, keep_score = TRUE)
}
