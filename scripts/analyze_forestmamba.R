#!/usr/bin/env Rscript
# ForestMamba against the deep and classical arms, on equal support. Reads the
# ForestMamba results of its own job directory and the comparison arms of the
# re-run job directory (master_tables.R's arm registry), both made on the same
# sealed frozen root and declared population. An arm enters only when its
# outputs carry the root's stamp and cover every usable (site, plot, rung)
# cell; missing cells are reported, never filled. Per rung the cells every arm
# scored are kept, scores pool summed counts, and paired plot-level bootstrap
# intervals (plots resampled within site, one shared set of draws per rung, as
# in the master tables) are attached to every score and to each
# ForestMamba-minus-arm contrast. Also pools recall by crown-class stratum,
# each arm's change from native along the ladder, and the per-cell compute of
# the ForestMamba receipts. REPEATS names job directories that re-ran some rungs
# with the same settings; their scores and contrasts on the shared cells show
# the run-to-run variation the sparse-convolution kernels leave.
#   Rscript scripts/analyze_forestmamba.R RUNS=<ForestMamba job dir>
#     BASE=<comparison job dir> [SITES=SJER,SOAP,TEAK,WREF,ABBY] [POP=adopted]
#     [ARMS=forestformer3d,segmentanytree,treeisonet,chm_vwf] [FROZEN_ROOT=...]
#     [RUNGS=<the root's rungs>] [REPEATS=<job dir>,...] [REPEAT_RUNGS=native,1]
#     [N_BOOT=1000] [SEED=20261002] [NULL_CELLS=<BASE>/sensitivity/null_cells.csv]
#     [K=200] [CORES=4] [CENSUS=<RUNS>/census_support_scores/nearest_ladder/
#     census_support_scores.csv] [BASE_CENSUS=the same under BASE]
#     [QL2=<the QL2 rung's analysis OUT>] [OUT=<RUNS>/neon/forestmamba_analysis]
# A rung frozen into its own root (the QL2 rung) is analysed the same way, from
# the job directories run on that root: FROZEN_ROOT=<root> RUNGS=3.2.
# With the paper's chance-agreement cells (paper_sensitivity.R MODE=null at its
# defaults: 200 shifts, 4 m, at least 8 m), ForestMamba's own null is scored on
# the same per-plot shifts and every arm's corrected F1, (F1 - null) /
# (1 - null), is compared on the same resamples.
# Writes status.csv, scores.csv, contrasts.csv, strata.csv, strata_contrasts.csv,
# rung_change.csv (with native and another rung), detection_ratio.csv,
# compute.csv, semantics.csv (the model's point labels per rung), repeats.csv
# and repeat_contrasts.csv (with REPEATS), null_cells.csv, corrected.csv, corrected_contrasts.csv,
# null_strata.csv and null_strata_contrasts.csv (with the null cells),
# census_scores.csv and census_contrasts.csv (when
# score_census_support.R has scored the ForestMamba clouds), masks.csv (when
# score_instances_iou.R has), pulses.csv (each rung's median pulse density),
# figure.png with figure.csv (the scores against pulse density, with the QL2
# rung's from QL2=) and tables.md (the report's tables) under OUT.
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(lidR); library(data.table) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R")); source(.find("io_bridge.R"))
source(.find("model_bench_lib.R"))
source(.find("master_tables_lib.R"))

FMA_FOCUS <- data.frame(arm = "forestmamba", file = "forestmamba_results.csv",
                        rungs = "native,8,4,2,1",
                        provenance = "forestmamba_results.csv.frozen",
                        result_rung = NA, detector = "forestmamba",
                        stringsAsFactors = FALSE)
FMA_STRATA <- c("overstory", "understory", "dominant", "codominant",
                "intermediate", "suppressed")

# An output tied to the sealed root and population: a <results>.frozen sidecar
# naming both, or a directory stamped with the root.
fma_stamped <- function(path, root, root_id, pop) {
  if (grepl("\\.frozen$", path)) {
    if (!file.exists(path)) return(FALSE)
    id <- jsonlite::read_json(path, simplifyVector = TRUE)
    return(identical(id$clip_manifest_sha256, root_id) && identical(id$population, pop))
  }
  dir.exists(path) && isTRUE(frozen_stamp_check(path, root, strict = FALSE))
}

# One arm's rows over `sites` of job directory `dir`: the cells `need_key`
# (site::plot::rung) requires, or a status saying why the arm cannot enter.
# `spec` is one row of MT_ARMS (or FMA_FOCUS); `nref` maps site::plot to the
# declared population's reference count.
fma_arm_rows <- function(dir, sites, spec, root, root_id, pop, need_key, nref) {
  rows <- do.call(rbind, lapply(sites, function(site) {
    f <- file.path(dir, "neon", site, spec$file)
    if (!file.exists(f)) return(NULL)
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x <- x[x$detector == spec$detector, , drop = FALSE]
    x$detector <- rep(spec$arm, nrow(x))
    if (!is.na(spec$result_rung)) x$rung[x$rung == spec$result_rung] <- "native"
    if (nrow(x) && is.null(x$site)) x$site <- site
    x
  }))
  have <- if (is.null(rows)) character() else paste(rows$site, rows$plot, rows$rung, sep = "::")
  stamped <- all(vapply(sites, function(site) {
    nd <- file.path(dir, "neon", site)
    fma_stamped(file.path(nd, spec$provenance), root, root_id, pop) ||
      fma_stamped(file.path(nd, paste0(spec$file, ".frozen")), root, root_id, pop)
  }, logical(1)))
  present <- length(intersect(need_key, have))
  status <- if (is.null(rows)) "no output on the root" else
    if (!stamped) "outputs not stamped with the sealed root" else
    if (present < length(need_key)) sprintf("%d of %d cells", present, length(need_key)) else
    "included"
  out <- data.frame(arm = spec$arm, file = spec$file, status = status,
                    cells_present = present, cells_required = length(need_key),
                    stringsAsFactors = FALSE)
  if (status != "included") return(list(status = out, rows = NULL))
  rows <- rows[paste(rows$site, rows$plot, rows$rung, sep = "::") %in% need_key, , drop = FALSE]
  if (anyDuplicated(paste(rows$site, rows$plot, rows$rung)))
    stop("Duplicate cells for ", spec$arm)
  # A cell without core detections counts zero true positives (the sweeps
  # write NA precision there), as pool() and mt_boot_scores() take it.
  if (is.null(rows$tp_core)) rows$tp_core <- round(rows$precision * rows$n_det)
  rows$tp_core[rows$n_det == 0] <- 0
  if (anyNA(rows[c("TP", "n_ref", "n_det", "tp_core")]))
    stop("Missing counts for ", spec$arm)
  expect <- as.integer(nref[paste(rows$site, rows$plot, sep = "::")])
  if (any(is.na(expect) | rows$n_ref != expect))
    stop("Reference of ", spec$arm, " differs from the declared ", pop, " population")
  for (k in setdiff(MT_STRATUM_COLS, names(rows))) rows[[k]] <- NA_real_
  list(status = out, rows = rows[, c("site", "plot", "rung", "detector", "n_ref", "n_det",
                                     "TP", "precision", "tp_core", MT_STRATUM_COLS)])
}

# The rungs to analyse: RUNGS= (comma-separated), by default every rung the
# sealed root holds, native first.
fma_rungs <- function(arg, root) {
  held <- c("native", as.character(frozen_root_rungs(root)))
  if (is.null(arg)) return(held)
  rungs <- trimws(strsplit(arg, ",", fixed = TRUE)[[1]])
  bad <- setdiff(rungs, held)
  if (length(bad)) stop("Rung ", paste(bad, collapse = ","), " is not a rung of ", root)
  rungs
}

# Bootstrap scores of each rung's equal set: the plots of that rung are
# resampled within site once, and every scope (all sites, each region, each
# site) and the focus-minus-arm contrasts use those draws.
fma_scores <- function(eq, focus, sites, n_boot = MT_N_BOOT, seed = MT_SEED,
                       metrics = c("recall", "precision", "F1"),
                       regions = MT_REGIONS) {
  long <- list(); con <- list()
  for (r in unique(eq$rung)) {
    x <- eq[eq$rung == r, , drop = FALSE]
    W <- mt_plot_weights(x$site, x$plot, n_boot, seed)
    site_of <- sub("::.*", "", rownames(W))
    # All sites, each site, then each region that is neither of those.
    here <- intersect(sites, unique(x$site))
    scopes <- c(list("five sites" = unique(x$site)), setNames(as.list(here), here),
                lapply(regions, function(s) intersect(s, unique(x$site))))
    scopes <- scopes[vapply(scopes, length, integer(1)) > 0]
    scopes <- scopes[!duplicated(lapply(scopes, sort))]
    for (sc in names(scopes)) {
      keep <- site_of %in% scopes[[sc]]
      s <- mt_boot_scores(x[x$site %in% scopes[[sc]], , drop = FALSE],
                          W[keep, , drop = FALSE], c("detector", "rung"))
      long[[length(long) + 1]] <- cbind(scope = sc, mt_intervals(s, metrics))
      for (a in setdiff(unique(x$detector), focus)) for (m in metrics)
        con[[length(con) + 1]] <- cbind(scope = sc, rung = r, mt_contrast(
          s, paste(a, r, sep = "|"), paste(focus, r, sep = "|"), m))
    }
  }
  list(long = do.call(rbind, long), contrasts = do.call(rbind, con))
}

# Recall by stratum, all sites pooled, with focus-minus-arm recall contrasts.
fma_strata <- function(eq, focus, strata = FMA_STRATA, n_boot = MT_N_BOOT,
                       seed = MT_SEED) {
  long <- list(); con <- list()
  for (r in unique(eq$rung)) {
    x <- eq[eq$rung == r, , drop = FALSE]
    st <- mt_stratum_rows(x)
    if (is.null(st)) next
    st <- st[st$stratum %in% strata, , drop = FALSE]
    W <- mt_plot_weights(x$site, x$plot, n_boot, seed)
    s <- mt_boot_scores(st, W, c("detector", "rung", "stratum"))
    long[[length(long) + 1]] <- mt_intervals(s, "recall")
    for (k in strata) for (a in setdiff(unique(x$detector), focus))
      con[[length(con) + 1]] <- cbind(rung = r, stratum = k, mt_contrast(
        s, paste(a, r, k, sep = "|"), paste(focus, r, k, sep = "|"), "recall"))
  }
  list(long = do.call(rbind, long), contrasts = do.call(rbind, con))
}

# Chance agreement of one cell, as paper_sensitivity.R MODE=null scores the
# paper's arms: the same K toroidal shifts per plot (seed_for(site, plot,
# "null") + k, at least `min_shift` m) of the detections within the core plus
# the match radius, greedy matching at `tol`. Returns the observed counts
# ("baseline") and their mean over the shifts ("null"), with overstory
# (dominant, codominant) and understory counts as the paper pools them.
fma_null_counts <- function(stems, det, cx, cy, ph, site, plot, K = 200, tol = 4,
                            min_shift = 8, seed = 0L) {
  counts <- function(d) {
    sc <- score_plot(stems, d, tol_xy = tol, core_cx = cx, core_cy = cy, core_half = ph)
    cls <- function(k) {
      n <- vapply(k, function(c) sc[[paste0("n_", c)]], numeric(1))
      r <- vapply(k, function(c) sc[[paste0("rec_", c)]], numeric(1))
      c(sum(n), sum(ifelse(n > 0 & is.finite(r), round(r * n), 0)))
    }
    o <- cls(c("dominant", "codominant")); u <- cls(c("intermediate", "suppressed"))
    c(n_ref = sc$n_ref, n_det = sc$n_det, TP = sc$TP,
      tp_core = if (sc$n_det > 0) round(sc$precision * sc$n_det) else 0,
      n_over = o[1], tp_over = o[2], n_under = u[1], tp_under = u[2])
  }
  shifted <- vapply(seq_len(K), function(k) counts(shift_detections(det, cx, cy, ph + tol,
    null_offset(2 * (ph + tol), seed_for(site, plot, "null") + seed * 1000003L + k,
                min_shift = min_shift))), numeric(8))
  cbind(data.frame(variant = c("baseline", "null"), stringsAsFactors = FALSE),
        as.data.frame(rbind(counts(det), rowMeans(shifted))))
}

# ForestMamba's null cells from its persisted instance clouds, read as the
# census scorer reads ForestFormer3D's (ff3d_collapse, then agl_guard on the
# frozen cell's DTM), for every plot of the population at `rungs`.
fma_null_cells <- function(job, sites, pop, rungs, root = NULL, K = 200, cores = 4) {
  do.call(rbind, lapply(sites, function(site) {
    nd <- file.path(job, "neon", site)
    gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
    fz <- frozen_scope(job, site, list(POP = pop, FROZEN_ROOT = root), gt)
    idir <- file.path(nd, "forestmamba_instances")
    frozen_stamp_check(idir, fz$root)
    res <- parallel::mclapply(intersect(fz$plots, pc$plotID), function(pid) {
      ci <- pc[pc$plotID == pid, ][1, ]
      cx <- ci$easting; cy <- ci$northing; ph <- plot_half(ci$plotType)
      stems <- fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - cx) <= ph &
                       abs(fz$gt$N - cy) <= ph, , drop = FALSE]
      if (!nrow(stems)) return(NULL)
      do.call(rbind, lapply(rungs, function(r) {
        f <- file.path(idir, sprintf("%s_%s.laz", pid, r))
        cell <- frozen_clip(NULL, site, pid, if (r == "native") NA_real_ else as.numeric(r),
                            cx, cy, ph, fz$root)
        if (is.null(cell) || !file.exists(f)) return(NULL)
        det <- ff3d_collapse(f, merge_tol = 2.0)
        if (!is.null(det)) det <- agl_guard(det, cell$dtm)
        if (is.null(det)) return(NULL)
        cbind(data.frame(site = site, plot = pid, rung = r, detector = "forestmamba",
                         stringsAsFactors = FALSE),
              fma_null_counts(stems, det, cx, cy, ph, site, pid, K = K))
      }))
    }, mc.cores = cores, mc.preschedule = FALSE)
    if (any(vapply(res, inherits, logical(1), "try-error")))
      stop("A plot failed while scoring the ForestMamba null at ", site)
    do.call(rbind, res)
  }))
}

# Rows of `a` whose (site, plot, rung) counts (references, detections, matched
# stems and matched detections) differ from `b`'s, or are missing there.
fma_count_mismatch <- function(a, b) {
  k <- c("site", "plot", "rung"); v <- c("n_ref", "n_det", "TP", "tp_core")
  m <- merge(a[, c(k, v)], b[, c(k, v)], by = k, all.x = TRUE, suffixes = c("", ".own"))
  m[is.na(m$TP.own) | m$n_ref != m$n_ref.own | m$n_det != m$n_det.own |
      m$TP != m$TP.own | m$tp_core != m$tp_core.own, , drop = FALSE]
}

# Corrected F1, (observed - null) / (1 - null), per arm and rung on the cells
# where every arm has both variants, and focus-minus-arm contrasts of it. The
# draws are the master tables' plot resamples, five sites pooled.
fma_corrected <- function(cells, focus, n_boot = MT_N_BOOT, seed = MT_SEED) {
  sc <- list(); con <- list()
  for (r in unique(cells$rung)) {
    x <- cells[cells$rung == r, , drop = FALSE]
    key <- paste(x$site, x$plot, sep = "::")
    x <- x[key %in% Reduce(intersect, lapply(split(key, paste(x$variant, x$detector)),
                                             unique)), , drop = FALSE]
    W <- mt_plot_weights(x$site, x$plot, n_boot, seed)
    s <- mt_boot_scores(x, W, c("variant", "detector", "rung"))
    E <- s$estimate$F1; names(E) <- s$groups; D <- s$draws$F1
    g <- function(v, a) paste(v, a, r, sep = "|")
    k <- function(a) list(
      e = unname((E[g("baseline", a)] - E[g("null", a)]) / (1 - E[g("null", a)])),
      d = (D[, g("baseline", a)] - D[, g("null", a)]) / (1 - D[, g("null", a)]))
    arms <- unique(x$detector)
    for (a in arms) sc[[length(sc) + 1]] <- cbind(data.frame(detector = a, rung = r,
      n_plots = nrow(W), observed_F1 = unname(E[g("baseline", a)]),
      null_F1 = unname(E[g("null", a)]), estimate = k(a)$e), mt_interval(k(a)$d))
    for (a in setdiff(arms, focus)) con[[length(con) + 1]] <- cbind(data.frame(rung = r,
      from = paste(a, r, sep = "|"), to = paste(focus, r, sep = "|"),
      metric = "F1_scaled", estimate = k(focus)$e - k(a)$e), mt_interval(k(focus)$d - k(a)$d))
  }
  list(scores = do.call(rbind, sc), contrasts = do.call(rbind, con))
}

# Recall of each crown-class stratum above the chance null, as the paper reads
# understory recall: pooled baseline minus pooled null recall per arm, rung and
# stratum (overstory: dominant and codominant; understory: intermediate and
# suppressed), its scaled form, excess / (1 - null), and focus-minus-arm
# contrasts of the excess, on the same plot resamples as fma_corrected().
fma_null_strata <- function(cells, focus, n_boot = MT_N_BOOT, seed = MT_SEED) {
  sc <- list(); con <- list()
  for (r in unique(cells$rung)) {
    x <- cells[cells$rung == r, , drop = FALSE]
    key <- paste(x$site, x$plot, sep = "::")
    x <- x[key %in% Reduce(intersect, lapply(split(key, paste(x$variant, x$detector)),
                                             unique)), , drop = FALSE]
    W <- mt_plot_weights(x$site, x$plot, n_boot, seed)
    arms <- unique(x$detector)
    for (k in c("overstory", "understory")) {
      cnt <- if (k == "overstory") c("n_over", "tp_over") else c("n_under", "tp_under")
      y <- data.frame(site = x$site, plot = x$plot, rung = x$rung, detector = x$detector,
                      variant = x$variant, n_ref = x[[cnt[1]]], TP = x[[cnt[2]]],
                      n_det = x$n_det, tp_core = x$tp_core, stringsAsFactors = FALSE)
      s <- mt_boot_scores(y, W, c("variant", "detector", "rung"))
      E <- s$estimate$recall; names(E) <- s$groups; D <- s$draws$recall
      g <- function(v, a) paste(v, a, r, sep = "|")
      ex <- function(a) list(e = unname(E[g("baseline", a)] - E[g("null", a)]),
                             d = D[, g("baseline", a)] - D[, g("null", a)])
      for (a in arms) sc[[length(sc) + 1]] <- cbind(data.frame(detector = a, rung = r,
        stratum = k, n_ref = sum(y$n_ref[y$detector == a & y$variant == "baseline"]),
        recall = unname(E[g("baseline", a)]), null_recall = unname(E[g("null", a)]),
        estimate = ex(a)$e, scaled = ex(a)$e / (1 - unname(E[g("null", a)])),
        stringsAsFactors = FALSE), mt_interval(ex(a)$d))
      for (a in setdiff(arms, focus)) con[[length(con) + 1]] <- cbind(data.frame(rung = r,
        stratum = k, from = paste(a, r, sep = "|"), to = paste(focus, r, sep = "|"),
        metric = "recall_above_null", estimate = ex(focus)$e - ex(a)$e,
        stringsAsFactors = FALSE), mt_interval(ex(focus)$d - ex(a)$d))
    }
  }
  list(scores = do.call(rbind, sc), contrasts = do.call(rbind, con))
}

# Point-mask scores of score_instances_iou.R (Voronoi-on-stems proxy masks):
# ForestMamba's rows from `runs`, the `models` from `base`, native masks only,
# on the declared cells every model scored, pooled per rung by summed counts.
fma_masks <- function(runs, base, sites, models, need_key) {
  read <- function(dir, keep) do.call(rbind, lapply(sites, function(site) {
    f <- file.path(dir, "neon", site, "instance_iou_pq.csv")
    if (!file.exists(f)) return(NULL)
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x[x$model %in% keep & x$mask_source == "native", , drop = FALSE]
  }))
  x <- rbind(read(runs, FMA_FOCUS$arm), read(base, models))
  if (is.null(x) || !nrow(x)) return(NULL)
  key <- paste(x$site, x$plot, x$rung, sep = "::")
  x <- x[key %in% need_key, , drop = FALSE]
  key <- paste(x$site, x$plot, x$rung, sep = "::")
  common <- Reduce(intersect, lapply(split(key, x$model), unique))
  x <- x[key %in% common, , drop = FALSE]
  do.call(rbind, lapply(split(x, paste(x$model, x$rung)), function(y)
    cbind(data.frame(model = y$model[1], rung = y$rung[1], stringsAsFactors = FALSE),
          pool_pq(y))))
}

# Censused-subplot scores (score_census_support.R) of the focus arm from
# `focus_csv` and of `arms` from `base_csv`, on the admitted cells every arm
# scored among `keys` (site::plot::rung, the declared cells; all when NULL),
# pooled over all sites with paired plot resamples per rung. The rows keep
# their support identity, so cells scored on different support stop
# (equal_set_guard checks it through mt_equal_support).
fma_census <- function(focus_csv, base_csv, arms, focus = FMA_FOCUS$arm,
                       n_boot = MT_N_BOOT, seed = MT_SEED, keys = NULL) {
  read <- function(f, keep) {
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x[x$detector %in% keep, , drop = FALSE]
  }
  a <- read(focus_csv, focus); b <- read(base_csv, arms)
  cols <- intersect(names(a), names(b))
  x <- rbind(a[, cols, drop = FALSE], b[, cols, drop = FALSE])
  if (!is.null(keys)) x <- x[paste(x$site, x$plot, x$rung, sep = "::") %in% keys, , drop = FALSE]
  miss <- setdiff(unique(x$rung), unique(x$rung[x$detector == focus]))
  if (length(miss)) stop("There are no censused ", focus, " rows at rung ",
                         paste(miss, collapse = ", "), "; score them with score_census_support.R")
  x$tp_core[x$n_det == 0] <- 0
  if (anyNA(x[c("TP", "n_ref", "n_det", "tp_core")])) stop("Missing counts in the censused scores")
  eq <- mt_equal_support(x, c(focus, arms))
  s <- fma_scores(eq, focus, character(), n_boot, seed, regions = list())
  list(long = s$long[s$long$scope == "five sites", , drop = FALSE],
       contrasts = s$contrasts[s$contrasts$scope == "five sites", , drop = FALSE], cells = eq)
}

# Repeated ForestMamba runs (a named list of result rows) on the cells every
# run and every comparison arm scored: each run's pooled recall, precision and
# F1 per rung, its F1 minus each arm's (columns d_F1_<arm>), and the share of
# cells whose counts (detections, matched stems, matched detections) equal the
# first run's (same_counts).
fma_repeats <- function(runs, arms) {
  key <- function(x) paste(x$site, x$plot, x$rung, sep = "::")
  common <- Reduce(intersect, c(lapply(runs, key), lapply(split(arms, arms$detector), key)))
  pooled <- function(x) {
    tp_core <- if (is.null(x$tp_core)) round(x$precision * x$n_det) else x$tp_core
    tp_core[x$n_det == 0] <- 0
    if (anyNA(tp_core)) stop("Missing counts in a repeat comparison")
    r <- sum(x$TP) / sum(x$n_ref)
    p <- if (sum(x$n_det)) sum(tp_core) / sum(x$n_det) else NA_real_
    data.frame(cells = nrow(x), recall = r, precision = p,
               F1 = if (isTRUE(r + p > 0)) 2 * r * p / (r + p) else NA_real_)
  }
  counts <- function(x) {
    tp_core <- if (is.null(x$tp_core)) round(x$precision * x$n_det) else x$tp_core
    tp_core[x$n_det == 0] <- 0
    setNames(paste(x$n_det, x$TP, tp_core), key(x))
  }
  first <- counts(runs[[1]])
  do.call(rbind, lapply(names(runs), function(n) {
    x <- runs[[n]][key(runs[[n]]) %in% common, , drop = FALSE]
    do.call(rbind, lapply(unique(x$rung), function(r) {
      xr <- x[x$rung == r, , drop = FALSE]
      p <- pooled(xr)
      p$same_counts <- mean(counts(xr) == first[key(xr)])
      a <- arms[arms$rung == r & key(arms) %in% common, , drop = FALSE]
      d <- vapply(split(a, a$detector), function(y) p$F1 - pooled(y)$F1, numeric(1))
      cbind(data.frame(run = n, rung = r, stringsAsFactors = FALSE), p,
            as.data.frame(as.list(setNames(d, paste0("d_F1_", names(d))))))
    }))
  }))
}

# Contrasts of each repeated run (a named list of the focus arm's rows): its
# rows replace the focus arm's in the equal-support set `eq` (the repeated
# rungs), and the focus-minus-arm F1 contrasts of every scope and the focus
# arm's change from native are drawn on the same plot resamples as the first
# run's (run "seed0"). A repeat must cover the first run's cells.
fma_repeat_contrasts <- function(eq, reps, focus, sites, n_boot = MT_N_BOOT, seed = MT_SEED,
                                 regions = MT_REGIONS) {
  key <- function(x) paste(x$site, x$plot, x$rung, sep = "::")
  first <- eq[eq$detector == focus, , drop = FALSE]
  cols <- c("scope", "rung", "from", "to", "metric", "estimate", "lower", "upper")
  runs <- c(list(seed0 = first), reps)
  do.call(rbind, lapply(names(runs), function(n) {
    x <- runs[[n]][key(runs[[n]]) %in% key(first), names(first), drop = FALSE]
    if (!setequal(key(x), key(first)))
      stop("Repeat ", n, " does not cover the first run's cells")
    s <- fma_scores(rbind(eq[eq$detector != focus, , drop = FALSE], x), focus, sites,
                    n_boot, seed, metrics = "F1", regions = regions)
    ch <- mt_rung_contrasts(x, list("five sites" = sites), n_boot = n_boot, seed = seed,
                            metrics = "F1")
    rbind(cbind(data.frame(run = n, kind = "contrast", stringsAsFactors = FALSE),
                s$contrasts[, cols]),
          if (!is.null(ch)) cbind(data.frame(run = n, kind = "rung_change",
                                             stringsAsFactors = FALSE), ch[, cols]))
  }))
}

# Per-cell compute of the ForestMamba run from its receipts: the cell receipt's
# wall time (container start to export) and the driver receipt's phases.
fma_compute <- function(inst_dirs) {
  rows <- do.call(rbind, lapply(inst_dirs, function(dir) {
    files <- list.files(dir, pattern = "[.]receipt[.]json$", full.names = TRUE)
    do.call(rbind, lapply(files, function(f) {
      key <- sub("[.]receipt[.]json$", "", basename(f))
      cell <- jsonlite::read_json(f)
      drv <- file.path(dir, paste0(key, ".laz.json"))
      drv <- if (file.exists(drv)) jsonlite::read_json(drv) else list()
      num <- function(v) if (is.null(v)) NA_real_ else as.numeric(v)
      data.frame(plot = sub("_[^_]+$", "", key), rung = sub(".*_", "", key),
                 wall_s = num(cell$seconds), infer_s = num(drv$infer_seconds),
                 model_s = num(drv$model_seconds), points = num(drv$points),
                 gpu_mib = num(drv$peak_cuda_allocated_bytes) / 2^20,
                 stringsAsFactors = FALSE)
    }))
  }))
  if (is.null(rows)) return(NULL)
  agg <- function(x) data.frame(cells = nrow(x), median_points = median(x$points),
    median_wall_s = median(x$wall_s), median_infer_s = median(x$infer_s, na.rm = TRUE),
    median_model_s = median(x$model_s, na.rm = TRUE), total_wall_h = sum(x$wall_s) / 3600,
    max_gpu_mib = max(x$gpu_mib, na.rm = TRUE))
  rbind(cbind(rung = "all", agg(rows)),
        do.call(rbind, lapply(split(rows, factor(rows$rung, levels = unique(rows$rung))),
                              function(x) cbind(rung = x$rung[1], agg(x)))))
}

# ForestMamba's point labels per rung, pooled from the driver receipts: the
# shares of staged clip points labelled ground, wood and leaf (FOR-instanceV2's
# classes 0, 1 and 2), wood's share of the vegetation labels, the share in no
# instance, and the median instance count per clip. Rungs run native first,
# then from dense to sparse.
fma_semantics <- function(inst_dirs) {
  rows <- do.call(rbind, lapply(inst_dirs, function(dir) {
    files <- list.files(dir, pattern = "[.]receipt[.]json$", full.names = TRUE)
    do.call(rbind, lapply(files, function(f) {
      key <- sub("[.]receipt[.]json$", "", basename(f))
      drv <- file.path(dir, paste0(key, ".laz.json"))
      if (!file.exists(drv)) return(NULL)
      drv <- jsonlite::read_json(drv)
      num <- function(v) if (is.null(v)) 0 else as.numeric(v)
      lab <- function(k) num(drv$semantic_counts[[k]])
      # Excluded noise rows are exported as background but were never labelled.
      data.frame(rung = sub(".*_", "", key), points = num(drv$points),
                 ground = lab("0"), wood = lab("1"), leaf = lab("2"),
                 unassigned = num(drv$background) - num(drv$noise_rows_excluded),
                 instances = num(drv$instances), stringsAsFactors = FALSE)
    }))
  }))
  if (is.null(rows)) return(NULL)
  sparse <- setdiff(unique(rows$rung), "native")
  rungs <- c(intersect("native", rows$rung), sparse[order(-as.numeric(sparse))])
  do.call(rbind, lapply(rungs, function(r) {
    x <- rows[rows$rung == r, , drop = FALSE]
    n <- sum(x$points)
    data.frame(rung = r, cells = nrow(x), ground = sum(x$ground) / n,
               wood = sum(x$wood) / n, leaf = sum(x$leaf) / n,
               wood_of_vegetation = sum(x$wood) / (sum(x$wood) + sum(x$leaf)),
               unassigned = sum(x$unassigned) / n,
               median_instances = median(x$instances), stringsAsFactors = FALSE)
  }))
}

# Core detections per reference stem per arm and rung, from summed counts:
# above 1 an arm reports more trees than the field maps.
fma_detection_ratio <- function(eq) {
  do.call(rbind, lapply(split(eq, paste(eq$detector, eq$rung)), function(x)
    data.frame(detector = x$detector[1], rung = x$rung[1], cells = nrow(x),
               per_stem = sum(x$n_det) / sum(x$n_ref), stringsAsFactors = FALSE)))
}

# A Markdown table: a header row, the rule and one row per element of `rows`.
fma_tab <- function(head, rows) c(paste0("| ", paste(head, collapse = " | "), " |"),
  paste0("|", paste(rep(" --- |", length(head)), collapse = "")),
  vapply(rows, function(r) paste0("| ", paste(r, collapse = " | "), " |"), "",
         USE.NAMES = FALSE), "")

fma_ratio_table <- function(ratio, arms, focus, rungs)
  c("Core detections per reference stem, five sites:", "",
    fma_tab(c("Arm", rungs), lapply(c(focus, arms), function(a) c(a, vapply(rungs, function(r) {
      v <- ratio$per_stem[ratio$detector == a & ratio$rung == r]
      if (length(v)) sprintf("%.2f", v) else "—" }, "")))))

# Median first-return pulse density per rung over the declared cells `keys`
# (site::plot::rung) of a sealed root's clip manifest.
fma_pulses <- function(cm, keys) {
  x <- cm[paste(cm$site, cm$plot, cm$rung, sep = "::") %in% keys, , drop = FALSE]
  vapply(split(as.numeric(x$frdens), x$rung), median, numeric(1))
}

# The figure's points: pooled F1, recall and precision (all sites) and the
# corrected F1 of every arm and rung, at the rung's median pulse density.
fma_figure_data <- function(long, corrected, pulses) {
  keep <- c("detector", "rung", "metric", "estimate", "lower", "upper")
  a <- long[long$scope == "five sites" & long$metric %in% c("F1", "recall", "precision"),
            keep, drop = FALSE]
  b <- if (length(corrected) && nrow(corrected))
    data.frame(detector = corrected$detector, rung = corrected$rung, metric = "F1_corrected",
               estimate = corrected$estimate, lower = corrected$lower, upper = corrected$upper,
               stringsAsFactors = FALSE)
  x <- rbind(a, b)
  x$pulses <- unname(pulses[as.character(x$rung)])
  x[!is.na(x$pulses), , drop = FALSE]
}

# F1, recall, precision and corrected F1 against pulse density with the 95%
# intervals, drawn as the paper's Figure 3 draws its ladder arms (base
# graphics; the paper's colours and symbols for its arms).
FMA_COL <- c(forestmamba = "#117733", forestformer3d = "#D55E00", segmentanytree = "#0072B2",
             treeisonet = "#CC79A7", chm_vwf = "#000000")
FMA_PCH <- c(forestmamba = 8, forestformer3d = 16, segmentanytree = 15, treeisonet = 17,
             chm_vwf = 16)
FMA_LABEL <- c(forestmamba = "ForestMamba", forestformer3d = "ForestFormer3D",
               segmentanytree = "SegmentAnyTree", treeisonet = "TreeisoNet", chm_vwf = "CHM-VWF")
fma_figure <- function(x, png_file) {
  png(png_file, width = 9, height = 8, units = "in", res = 200)
  on.exit(dev.off())
  par(mfrow = c(2, 2), mar = c(4, 4, 2.5, 1))
  mains <- c(F1 = "(a) F1", recall = "(b) Recall", precision = "(c) Precision",
             F1_corrected = "(d) F1 corrected for chance (4 m)")
  ticks <- sort(unique(x$pulses), decreasing = TRUE)
  arms <- intersect(names(FMA_COL), unique(x$detector))
  dodge <- setNames(exp(seq(-0.03, 0.03, length.out = length(arms))), arms)  # readable intervals
  for (m in names(mains)) {
    y <- x[x$metric == m, , drop = FALSE]
    if (!nrow(y)) { plot.new(); next }
    plot(NA, xlim = rev(range(x$pulses)) * c(1.1, 0.9), log = "x", xaxt = "n",
         ylim = c(min(0, y$lower, na.rm = TRUE), max(y$upper, na.rm = TRUE)),
         xlab = "First-return pulses/m²", ylab = sub("^\\(.\\) ", "", mains[[m]]),
         main = mains[[m]])
    axis(1, at = ticks, labels = formatC(ticks, format = "f", digits = 1), cex.axis = 0.8)
    abline(v = c(2, 8), lty = 3, col = "grey40")          # the QL2 and QL1 floors
    text(c(2, 8), par("usr")[4], c("QL2", "QL1"), pos = 1, cex = 0.7, col = "grey30")
    for (a in intersect(arms, unique(y$detector))) {
      z <- y[y$detector == a, , drop = FALSE]; z <- z[order(-z$pulses), , drop = FALSE]
      px <- z$pulses * dodge[[a]]
      segments(px, z$lower, px, z$upper, col = adjustcolor(FMA_COL[[a]], 0.6))
      lines(px, z$estimate, col = FMA_COL[[a]], type = "o", pch = FMA_PCH[[a]],
            cex = 0.8, lwd = if (a == "forestmamba") 2 else 1)
    }
    if (m == "F1") legend("bottomleft", legend = FMA_LABEL[arms], col = FMA_COL[arms],
                          pch = FMA_PCH[arms], lty = 1, bty = "n", cex = 0.7)
  }
  invisible(png_file)
}

# "est [lo, hi]"; signed values (differences) carry their sign, with a true minus.
# Floating-point noise (|v| < 1e-9, as when two equal scores are subtracted)
# prints as zero; any other value keeps its sign, so a negative bound that
# rounds to zero prints as -0.000, as the paper prints it.
fma_denoise <- function(v) { v[!is.na(v) & abs(v) < 1e-9] <- 0; v }
fma_fmt <- function(est, lo, hi, k = 3, signed = FALSE) {
  f <- paste0(if (signed) "%+." else "%.", k, "f")
  out <- ifelse(is.na(est), "\u2014", sprintf(paste0(f, " [", f, ", ", f, "]"),
                fma_denoise(est), fma_denoise(lo), fma_denoise(hi)))
  if (signed) gsub("-", "\u2212", out, fixed = TRUE) else out
}
fma_num <- function(v, k = 3, signed = FALSE) {
  out <- ifelse(is.na(v), "\u2014", sprintf(paste0(if (signed) "%+." else "%.", k, "f"),
                                             fma_denoise(v)))
  if (signed) gsub("-", "\u2212", out, fixed = TRUE) else out
}

# The report's tables as Markdown lines.
fma_tables <- function(long, con, strata, scon, change, compute, arms, focus, rungs,
                       repeats = NULL, corrected = NULL, masks = NULL, semantics = NULL,
                       census = NULL, ratio = NULL, null_strata = NULL,
                       repeat_contrasts = NULL) {
  tab <- fma_tab
  cell <- function(d, signed = FALSE)
    if (nrow(d)) fma_fmt(d$estimate, d$lower, d$upper, signed = signed) else "—"
  dcell <- function(d) cell(d, signed = TRUE)
  f1 <- long[long$scope == "five sites" & long$metric == "F1", ]
  out <- c("F1 over the five sites, per rung (paired bootstrap 95% interval):", "",
    tab(c("Arm", rungs), lapply(c(focus, arms), function(a) c(a, vapply(rungs, function(r)
      cell(f1[f1$detector == a & f1$rung == r, ]), "")))))
  c5 <- con[con$scope == "five sites", ]
  for (m in c("F1", "recall", "precision"))
    out <- c(out, sprintf("ForestMamba minus arm, %s, five sites:", m), "",
      tab(c("Arm", rungs), lapply(arms, function(a) c(a, vapply(rungs, function(r)
        dcell(c5[c5$from == paste(a, r, sep = "|") & c5$metric == m, ]), "")))))
  if (!is.null(ratio)) out <- c(out, fma_ratio_table(ratio, arms, focus, rungs))
  sites <- setdiff(unique(long$scope), c("five sites", names(MT_REGIONS)))
  ends <- unique(rungs[c(1, length(rungs))])        # native and the sparsest rung
  for (r in ends) {
    fr <- long[long$metric == "F1" & long$rung == r, ]
    out <- c(out, sprintf("F1 per site at rung %s:", r), "",
      tab(c("Arm", sites), lapply(c(focus, arms), function(a) c(a, vapply(sites, function(s)
        cell(fr[fr$scope == s & fr$detector == a, ]), "")))))
  }
  for (r in ends) {
    st <- strata[strata$rung == r, ]
    out <- c(out, sprintf("Recall by stratum at rung %s, five sites:", r), "",
      tab(c("Arm", FMA_STRATA), lapply(c(focus, arms), function(a) c(a, vapply(FMA_STRATA,
        function(k) cell(st[st$detector == a & st$stratum == k, ]), "")))))
  }
  if (!is.null(change)) {
    ch <- change[change$scope == "five sites" & change$metric == "F1", ]
    out <- c(out, "Change in F1 from native, five sites (paired over plots):", "",
      tab(c("Arm", setdiff(rungs, "native")), lapply(c(focus, arms), function(a)
        c(a, vapply(setdiff(rungs, "native"), function(r)
          dcell(ch[ch$detector == a & ch$rung == r, ]), "")))))
  }
  if (!is.null(corrected)) {
    cs <- corrected$scores; cc <- corrected$contrasts
    out <- c(out, "Corrected F1, (F1 - null) / (1 - null), five sites:", "",
      tab(c("Arm", rungs), lapply(c(focus, arms), function(a) c(a, vapply(rungs, function(r)
        cell(cs[cs$detector == a & cs$rung == r, ]), "")))),
      "ForestMamba minus arm, corrected F1, five sites:", "",
      tab(c("Arm", rungs), lapply(arms, function(a) c(a, vapply(rungs, function(r)
        dcell(cc[cc$from == paste(a, r, sep = "|"), ]), "")))))
  }
  if (!is.null(null_strata)) for (r in ends) {
    ns <- null_strata$scores[null_strata$scores$rung == r, ]
    nc <- null_strata$contrasts[null_strata$contrasts$rung == r, ]
    v <- function(d, signed = FALSE)
      if (nrow(d)) fma_fmt(d$estimate, d$lower, d$upper, signed = signed) else "—"
    out <- c(out, sprintf("Recall above the chance null at rung %s, five sites:", r), "",
      tab(c("Arm", "Overstory", "Understory", "Understory, scaled"),
          lapply(c(focus, arms), function(a) {
            o <- ns[ns$detector == a & ns$stratum == "overstory", ]
            u <- ns[ns$detector == a & ns$stratum == "understory", ]
            c(a, v(o, TRUE), v(u, TRUE), if (nrow(u)) fma_num(u$scaled, signed = TRUE) else "—")
          })),
      sprintf("ForestMamba minus arm, recall above the chance null at rung %s:", r), "",
      tab(c("Arm", "Overstory", "Understory"), lapply(arms, function(a) {
        k <- nc[nc$from == paste(a, r, sep = "|"), ]
        c(a, v(k[k$stratum == "overstory", ], TRUE), v(k[k$stratum == "understory", ], TRUE))
      })))
  }
  if (!is.null(census)) {
    cl <- census$long[census$long$metric == "F1", ]
    cc <- census$contrasts[census$contrasts$metric == "F1", ]
    out <- c(out, sprintf("Censused F1 inside the admitted subplots, %d plots:",
                          length(unique(paste(census$cells$site, census$cells$plot)))), "",
      tab(c("Arm", rungs), lapply(c(focus, arms), function(a) c(a, vapply(rungs, function(r)
        cell(cl[cl$detector == a & cl$rung == r, ]), "")))),
      "ForestMamba minus arm, censused F1:", "",
      tab(c("Arm", rungs), lapply(arms, function(a) c(a, vapply(rungs, function(r)
        dcell(cc[cc$from == paste(a, r, sep = "|"), ]), "")))))
  }
  if (!is.null(masks)) {
    mm <- intersect(c(focus, arms), unique(masks$model))
    for (k in c("F1", "PQ", "coverage")) out <- c(out,
      sprintf("Point-mask %s against the Voronoi-on-stems proxy, five sites:", k), "",
      tab(c("Model", rungs), lapply(mm, function(a) c(a, vapply(rungs, function(r) {
        v <- masks[[k]][masks$model == a & masks$rung == r]   # NA: no mask matched
        if (length(v) && !is.na(v)) sprintf("%.3f", v) else "—" }, "")))))
  }
  if (!is.null(semantics)) out <- c(out,
    "ForestMamba's point labels per rung, percent of staged clip points:", "",
    tab(c("Rung", "Cells", "Ground", "Wood", "Leaf", "Wood of vegetation",
          "In no instance", "Median instances per clip"),
        lapply(seq_len(nrow(semantics)), function(i) with(semantics[i, ], c(rung, cells,
          sprintf("%.1f", 100 * c(ground, wood, leaf, wood_of_vegetation, unassigned)),
          sprintf("%.0f", median_instances))))))
  if (!is.null(repeats)) out <- c(out,
    "Repeated ForestMamba runs on the shared cells (F1, and F1 minus each arm):", "",
    tab(c("Run", "Rung", "Cells", "Cells with the first run's counts", "F1",
          paste("minus", arms)),
        lapply(seq_len(nrow(repeats)), function(i) c(repeats$run[i], repeats$rung[i],
          repeats$cells[i], sprintf("%.0f%%", 100 * repeats$same_counts[i]),
          fma_num(repeats$F1[i]), vapply(arms, function(a)
            fma_num(repeats[[paste0("d_F1_", a)]][i], signed = TRUE), "")))))
  if (!is.null(repeat_contrasts)) {
    rc <- repeat_contrasts[repeat_contrasts$scope == "five sites", , drop = FALSE]
    runs <- unique(rc$run)
    con <- rc[rc$kind == "contrast", , drop = FALSE]
    con$arm <- sub("[|].*", "", con$from)
    ch <- rc[rc$kind == "rung_change", , drop = FALSE]
    v <- function(d) if (nrow(d)) fma_fmt(d$estimate, d$lower, d$upper, signed = TRUE) else "—"
    out <- c(out, "ForestMamba minus arm, F1, five sites, in each run of the repeated rungs:", "",
      tab(c("Arm", "Rung", runs), lapply(split(con, paste(con$arm, con$rung)), function(d)
        c(d$arm[1], d$rung[1], vapply(runs, function(n) v(d[d$run == n, ]), "")))),
      "ForestMamba's change in F1 from native, five sites, in each run:", "",
      tab(c("Rung", runs), lapply(unique(ch$rung), function(r)
        c(r, vapply(runs, function(n) v(ch[ch$run == n & ch$rung == r, ]), "")))))
  }
  if (!is.null(compute)) out <- c(out, "ForestMamba compute per cell:", "",
    tab(c("Rung", "Cells", "Median points", "Median wall, s", "Median inference, s",
          "Median model load, s", "Total wall, h", "Max GPU allocated, MiB"),
        lapply(seq_len(nrow(compute)), function(i) with(compute[i, ], c(rung, cells,
          sprintf("%.0f", median_points), sprintf("%.1f", median_wall_s),
          sprintf("%.1f", median_infer_s), sprintf("%.1f", median_model_s),
          sprintf("%.2f", total_wall_h), sprintf("%.0f", max_gpu_mib))))))
  out
}

run_main <- function() {
  args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
  A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
  split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
  if (is.null(A$RUNS) || is.null(A$BASE)) stop("RUNS= and BASE= job directories are required")
  RUNS   <- normalizePath(A$RUNS); BASE <- normalizePath(A$BASE)
  SITES  <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
  POP    <- if (is.null(A$POP)) "adopted" else A$POP
  ARMS   <- split_arg(A$ARMS, "forestformer3d,segmentanytree,treeisonet,chm_vwf")
  ROOT   <- frozen_root(RUNS, A$FROZEN_ROOT)
  N_BOOT <- as.integer(if (is.null(A$N_BOOT)) MT_N_BOOT else A$N_BOOT)
  SEED   <- as.integer(if (is.null(A$SEED)) MT_SEED else A$SEED)
  OUT    <- if (is.null(A$OUT)) file.path(RUNS, "neon", "forestmamba_analysis") else A$OUT
  REPEATS <- if (is.null(A$REPEATS)) character() else normalizePath(split_arg(A$REPEATS, ""))
  REPEAT_RUNGS <- split_arg(A$REPEAT_RUNGS, "native,1")
  NULL_CELLS <- if (is.null(A$NULL_CELLS)) file.path(BASE, "sensitivity", "null_cells.csv") else
    A$NULL_CELLS
  K      <- as.integer(if (is.null(A$K)) 200 else A$K)
  census_csv <- function(dir) file.path(dir, "census_support_scores", "nearest_ladder",
                                        "census_support_scores.csv")
  CENSUS <- if (is.null(A$CENSUS)) census_csv(RUNS) else A$CENSUS
  BASE_CENSUS <- if (is.null(A$BASE_CENSUS)) census_csv(BASE) else A$BASE_CENSUS
  QL2    <- A$QL2                         # the QL2 rung's analysis OUT, for the figure
  CORES  <- as.integer(if (is.null(A$CORES)) 4 else A$CORES)
  if (!frozen_sealed(ROOT)) stop("No sealed frozen root at ", ROOT)
  if (!all(ARMS %in% MT_ARMS$arm)) stop("Unknown arm in ", paste(ARMS, collapse = ","))
  dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
  root_id <- frozen_root_id(ROOT)
  pop <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
  pst <- read.csv(file.path(ROOT, "population_stems.csv"), stringsAsFactors = FALSE)
  cm  <- frozen_clip_manifest(ROOT)
  inpop <- pop[pop$site %in% SITES & pop[[paste0("in_", POP)]], , drop = FALSE]
  nref <- table(paste(pst$site[pst$population == POP], pst$plotID[pst$population == POP],
                      sep = "::"))
  rungs <- fma_rungs(A$RUNGS, ROOT)
  need <- cm[cm$status == "ok" & cm$rung %in% rungs &
               paste(cm$site, cm$plot) %in% paste(inpop$site, inpop$plotID), , drop = FALSE]
  need_key <- paste(need$site, need$plot, need$rung, sep = "::")

  loaded <- c(list(fma_arm_rows(RUNS, SITES, FMA_FOCUS, ROOT, root_id, POP, need_key, nref)),
              lapply(ARMS, function(a) fma_arm_rows(BASE, SITES, MT_ARMS[MT_ARMS$arm == a, ],
                                                    ROOT, root_id, POP, need_key, nref)))
  status <- do.call(rbind, lapply(loaded, `[[`, "status"))
  write.csv(status, file.path(OUT, "status.csv"), row.names = FALSE)
  print(status, row.names = FALSE)
  if (any(status$status != "included"))
    stop("Every arm must cover the declared cells on the sealed root; see status.csv")
  rows <- do.call(rbind, lapply(loaded, `[[`, "rows"))
  eq <- mt_equal_support(rows, c(FMA_FOCUS$arm, ARMS))
  if (length(attr(eq, "dropped")))
    stop("Arms disagree on support: ", paste(head(attr(eq, "dropped")), collapse = ", "))

  sc <- fma_scores(eq, FMA_FOCUS$arm, SITES, N_BOOT, SEED)
  st <- fma_strata(eq, FMA_FOCUS$arm, n_boot = N_BOOT, seed = SEED)
  ch <- if ("native" %in% rungs && length(rungs) > 1)
    mt_rung_contrasts(eq, list("five sites" = SITES), n_boot = N_BOOT, seed = SEED)
  cp <- fma_compute(file.path(RUNS, "neon", SITES, "forestmamba_instances"))
  sm <- fma_semantics(file.path(RUNS, "neon", SITES, "forestmamba_instances"))
  dr <- fma_detection_ratio(eq)
  write.csv(sc$long, file.path(OUT, "scores.csv"), row.names = FALSE)
  write.csv(sc$contrasts, file.path(OUT, "contrasts.csv"), row.names = FALSE)
  write.csv(st$long, file.path(OUT, "strata.csv"), row.names = FALSE)
  write.csv(st$contrasts, file.path(OUT, "strata_contrasts.csv"), row.names = FALSE)
  if (!is.null(ch)) write.csv(ch, file.path(OUT, "rung_change.csv"), row.names = FALSE)
  if (!is.null(cp)) write.csv(cp, file.path(OUT, "compute.csv"), row.names = FALSE)
  if (!is.null(sm)) write.csv(sm, file.path(OUT, "semantics.csv"), row.names = FALSE)
  write.csv(dr, file.path(OUT, "detection_ratio.csv"), row.names = FALSE)
  rp <- NULL; rc <- NULL
  if (length(REPEATS)) {
    rkey <- need_key[sub(".*::", "", need_key) %in% REPEAT_RUNGS]
    reps <- lapply(REPEATS, function(dir)
      fma_arm_rows(dir, SITES, FMA_FOCUS, ROOT, root_id, POP, rkey, nref))
    rstat <- do.call(rbind, lapply(reps, `[[`, "status"))
    if (any(rstat$status != "included"))
      stop("A repeat run does not cover rungs ", paste(REPEAT_RUNGS, collapse = ","), ": ",
           paste(rstat$status, collapse = "; "))
    runs <- c(list(seed0 = eq[eq$detector == FMA_FOCUS$arm & eq$rung %in% REPEAT_RUNGS, ]),
              setNames(lapply(reps, `[[`, "rows"), paste0("repeat", seq_along(reps))))
    rp <- fma_repeats(runs, eq[eq$detector != FMA_FOCUS$arm & eq$rung %in% REPEAT_RUNGS, ])
    write.csv(rp, file.path(OUT, "repeats.csv"), row.names = FALSE)
    rc <- fma_repeat_contrasts(eq[eq$rung %in% REPEAT_RUNGS, ], runs[-1], FMA_FOCUS$arm, SITES,
                               N_BOOT, SEED)
    write.csv(rc, file.path(OUT, "repeat_contrasts.csv"), row.names = FALSE)
  }
  cr <- NULL; ns <- NULL
  if (file.exists(NULL_CELLS)) {
    fmn <- fma_null_cells(RUNS, SITES, POP, rungs, root = ROOT, K = K, cores = CORES)
    own <- eq[eq$detector == FMA_FOCUS$arm, , drop = FALSE]
    bad <- fma_count_mismatch(own, fmn[fmn$variant == "baseline", , drop = FALSE])
    if (nrow(bad)) stop("Re-scored ForestMamba detections differ from its results at ",
                        paste(head(paste(bad$plot, bad$rung)), collapse = ", "))
    pn <- read.csv(NULL_CELLS, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    pn <- pn[pn$detector %in% ARMS &
               paste(pn$site, pn$plot, pn$rung, sep = "::") %in% need_key, names(fmn)]
    for (a in ARMS) {                       # the null file must hold these very results
      ra <- eq[eq$detector == a, , drop = FALSE]
      bad <- fma_count_mismatch(ra, pn[pn$detector == a & pn$variant == "baseline", , drop = FALSE])
      if (nrow(bad)) stop("The null cells of ", a, " do not match its results; re-run ",
                          "paper_sensitivity.R MODE=null on this root")
    }
    cr <- fma_corrected(rbind(fmn, pn), FMA_FOCUS$arm, N_BOOT, SEED)
    ns <- fma_null_strata(rbind(fmn, pn), FMA_FOCUS$arm, N_BOOT, SEED)
    write.csv(ns$scores, file.path(OUT, "null_strata.csv"), row.names = FALSE)
    write.csv(ns$contrasts, file.path(OUT, "null_strata_contrasts.csv"), row.names = FALSE)
    write.csv(fmn, file.path(OUT, "null_cells.csv"), row.names = FALSE)
    write.csv(cr$scores, file.path(OUT, "corrected.csv"), row.names = FALSE)
    write.csv(cr$contrasts, file.path(OUT, "corrected_contrasts.csv"), row.names = FALSE)
  } else cat("no chance-agreement cells at ", NULL_CELLS, "; corrected F1 skipped\n", sep = "")
  cs <- NULL
  if (file.exists(CENSUS) && file.exists(BASE_CENSUS)) {
    cs <- fma_census(CENSUS, BASE_CENSUS, ARMS, FMA_FOCUS$arm, N_BOOT, SEED, keys = need_key)
    write.csv(cs$long, file.path(OUT, "census_scores.csv"), row.names = FALSE)
    write.csv(cs$contrasts, file.path(OUT, "census_contrasts.csv"), row.names = FALSE)
  } else cat("no censused scores at ", if (file.exists(CENSUS)) BASE_CENSUS else CENSUS,
             "; censused F1 skipped\n", sep = "")
  pulses <- fma_pulses(cm, need_key)
  write.csv(data.frame(rung = names(pulses), pulses = unname(pulses)),
            file.path(OUT, "pulses.csv"), row.names = FALSE)
  fg <- fma_figure_data(sc$long, if (!is.null(cr)) cr$scores, pulses)
  if (!is.null(QL2)) {
    q <- function(f) read.csv(file.path(QL2, f), stringsAsFactors = FALSE,
                              colClasses = c(rung = "character"))
    qp <- q("pulses.csv")
    fg <- rbind(fg, fma_figure_data(q("scores.csv"), if (file.exists(file.path(QL2,
      "corrected.csv"))) q("corrected.csv"), setNames(qp$pulses, qp$rung)))
  }
  write.csv(fg, file.path(OUT, "figure.csv"), row.names = FALSE)
  fma_figure(fg, file.path(OUT, "figure.png"))
  mk <- fma_masks(RUNS, BASE, SITES,
                  intersect(ARMS, c("forestformer3d", "segmentanytree", "treeisonet")), need_key)
  if (!is.null(mk)) write.csv(mk, file.path(OUT, "masks.csv"), row.names = FALSE)
  md <- fma_tables(sc$long, sc$contrasts, st$long, st$contrasts, ch, cp, ARMS,
                   FMA_FOCUS$arm, rungs, rp, cr, mk, sm, cs, dr, ns, rc)
  writeLines(c(sprintf("Population %s, %d plots, %d cells per arm; root %s; %d draws, seed %d.",
                       POP, length(unique(paste(eq$site, eq$plot))), nrow(eq) /
                         length(unique(eq$detector)), substr(root_id, 1, 12), N_BOOT, SEED),
               "", md), file.path(OUT, "tables.md"))
  cat(sprintf("forestmamba analysis -> %s\n", OUT))
}

if (sys.nframe() == 0L) run_main()
