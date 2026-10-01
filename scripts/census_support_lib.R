# Censused-subplot scoring of persisted detections (no inference). Pure helpers
# for score_census_support.R: load the support bundles a reviewed declaration
# admits, read one arm's persisted apexes for a (plot, rung) cell, and score
# them inside the admitted interior next to the nominal-box score. Sourced
# after sweep_lib.R, model_bench_lib.R, neon_reference_support_lib.R and
# io_bridge.R.

# Where each arm's per-cell apexes are persisted, in order of preference:
#   detections -- <nd>/<arm>_detections/<plot>__<rung>.csv with x, y, z AGL,
#                 written by an arm that persists the apexes it scores;
#   instances  -- <nd>/<dir>/<plot>_<rung>.laz instance clouds, reduced to the
#                 max-Z point per instance exactly as the arm does (`agl`: the
#                 cloud keeps absolute Z, so the frozen DTM converts it);
#   cache      -- best_treetop_cache, the selected configuration of each arm.
# Every directory read must carry the sealed root's stamp.
CENSUS_INSTANCE_SOURCES <- list(
  segmentanytree = list(dir = "segmentanytree_instances", id = "PredInstance", agl = TRUE),
  ams3d   = list(dir = "ams3d_instances",   id = "crown_id", agl = FALSE),
  ptrees  = list(dir = "ptrees_instances",  id = "treeID",   agl = FALSE),
  li2012  = list(dir = "li2012_instances",  id = "treeID",   agl = FALSE),
  treeiso = list(dir = "treeiso_instances", id = "treeiso",  agl = FALSE))

census_rung_label <- function(rung) if (is.na(rung)) "native" else as.character(rung)

# One arm's apexes for one cell, or NULL when no persisted source holds it.
# `cell` is the frozen cell (frozen_clip) for the DTM; `root` the sealed root.
census_cell_detections <- function(nd, arm, site, plot, rung, root, cell = NULL) {
  r <- census_rung_label(rung)
  ddir <- file.path(nd, paste0(arm, "_detections"))
  f <- frozen_detections_file(ddir, plot, rung)
  if (file.exists(f)) {
    frozen_stamp_check(ddir, root)
    det <- read.csv(f, stringsAsFactors = FALSE)
    det <- data.frame(x = as.numeric(det$x), y = as.numeric(det$y), z = as.numeric(det$z))
    assert_detection_contract(det)
    return(structure(det, source = "detections"))
  }
  src <- CENSUS_INSTANCE_SOURCES[[arm]]
  if (!is.null(src)) {
    idir <- file.path(nd, src$dir)
    f <- file.path(idir, sprintf("%s_%s.laz", plot, r))
    if (file.exists(f)) {
      frozen_stamp_check(idir, root)
      det <- read_instances_laz(f, id_field = src$id)
      if (!is.null(det) && src$agl) {
        if (is.null(cell)) return(NULL)
        det <- agl_guard(det, cell$dtm)
      }
      if (!is.null(det)) return(structure(det, source = "instances"))
    }
  }
  cdir <- file.path(nd, "best_treetop_cache")
  if (dir.exists(cdir)) {
    frozen_stamp_check(cdir, root)
    det <- read_arm_cache(cdir, arm, site, plot, r)
    if (!is.null(det)) return(structure(det, source = "cache"))
  }
  NULL
}

# The bundles a declaration admits for one site, keyed by plot. Each admitted
# row names its plot and event; the bundle is found in the per-year
# preparation outputs <support>/<SITE>_<YEAR>/support_bundles.rds, the
# declaration's missing-reference policy is applied, and the result must pass
# neon_admit_support(). A plot admitted twice is an error.
census_apply_policy <- function(bundle, policy) {
  if (is.null(policy) || identical(policy, "none")) return(bundle)
  if (!policy %in% NEON_MISSING_POLICIES) stop("Unknown missing-reference policy: ", policy)
  neon_subplot_exclusion(bundle, strict = identical(policy, "subplot_exclusion_strict"))
}
census_admitted_bundles <- function(support, site, declaration, years) {
  adm <- as.data.frame(declaration$admitted, stringsAsFactors = FALSE)
  if (!"site" %in% names(adm)) stop("Declaration rows need a site")
  adm <- adm[adm$site == site, , drop = FALSE]
  if (anyDuplicated(adm$plot)) stop("A plot is admitted with more than one event")
  out <- list()
  for (y in years) {
    f <- file.path(support, paste0(site, "_", y), "support_bundles.rds")
    if (!file.exists(f)) next
    b <- readRDS(f)
    for (k in names(b)) {
      if (!any(adm$plot == b[[k]]$plot & adm$event == b[[k]]$event)) next
      out[[b[[k]]$plot]] <- neon_admit_support(
        census_apply_policy(b[[k]], declaration$missing_reference_policy), declaration)
    }
  }
  missing <- setdiff(adm$plot, names(out))
  if (length(missing)) stop("Admitted bundles not found for ", paste(missing, collapse = ", "))
  out
}

# Support-aware row for one cell, with the nominal-box score of the same
# detections against the population's core reference alongside (rect_*), so
# raw and censused precision are read on identical detections.
census_score_cell <- function(bundle, det, epsg, stems, cx, cy, ph, tol = 4) {
  s <- score_neon_support(bundle, det, det_epsg = epsg, tol_xy = tol)
  r <- score_plot(stems, det, tol_xy = tol, core_cx = cx, core_cy = cy, core_half = ph)
  for (m in c("n_ref", "n_det", "TP", "recall", "precision", "F1"))
    s[[paste0("rect_", m)]] <- r[[m]]
  s$rect_tp_core <- if (r$n_det > 0) round(r$precision * r$n_det) else 0
  s
}

# Pooled support-aware and nominal-box rates per arm x rung, summing counts
# over the cells every arm scored (equal_set_guard keeps support identities).
census_pool <- function(rows, arms) {
  rows <- equal_set_guard(rows, arms)
  do.call(rbind, lapply(split(rows, paste(rows$detector, rows$rung)), function(x) {
    p <- pool(x)
    rect <- with(x, c(sum(rect_TP) / sum(rect_n_ref),
                      if (sum(rect_n_det)) sum(rect_tp_core) / sum(rect_n_det) else NA_real_))
    data.frame(detector = x$detector[1], rung = x$rung[1], p,
               rect_n_ref = sum(x$rect_n_ref), rect_n_det = sum(x$rect_n_det),
               rect_recall = rect[1], rect_precision = rect[2],
               rect_F1 = if (all(is.finite(rect)) && sum(rect) > 0) 2 * prod(rect) / sum(rect) else NA_real_)
  }))
}
