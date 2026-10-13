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
#     [REPEATS=<job dir>,...] [REPEAT_RUNGS=native,1] [N_BOOT=1000]
#     [SEED=20261002] [NULL_CELLS=<BASE>/sensitivity/null_cells.csv] [K=200]
#     [CORES=4] [OUT=<RUNS>/neon/forestmamba_analysis]
# With the paper's chance-agreement cells (paper_sensitivity.R MODE=null at its
# defaults: 200 shifts, 4 m, at least 8 m), ForestMamba's own null is scored on
# the same per-plot shifts and every arm's corrected F1, (F1 - null) /
# (1 - null), is compared on the same resamples.
# Writes status.csv, scores.csv, contrasts.csv, strata.csv, strata_contrasts.csv,
# rung_change.csv, compute.csv, repeats.csv (with REPEATS), null_cells.csv,
# corrected.csv and corrected_contrasts.csv (with the null cells), masks.csv
# (when score_instances_iou.R has scored the ForestMamba clouds) and tables.md
# (the report's tables) under OUT.
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

# Rows of `a` whose (site, plot, rung) counts differ from `b`'s, or are missing there.
fma_count_mismatch <- function(a, b) {
  k <- c("site", "plot", "rung")
  m <- merge(a[, c(k, "n_ref", "n_det", "TP")], b[, c(k, "n_ref", "n_det", "TP")],
             by = k, all.x = TRUE, suffixes = c("", ".own"))
  m[is.na(m$TP.own) | m$n_ref != m$n_ref.own | m$n_det != m$n_det.own |
      m$TP != m$TP.own, , drop = FALSE]
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

# Repeated ForestMamba runs (a named list of result rows) on the cells every
# run and every comparison arm scored: each run's pooled recall, precision and
# F1 per rung, and its F1 minus each arm's (columns d_F1_<arm>).
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
  do.call(rbind, lapply(names(runs), function(n) {
    x <- runs[[n]][key(runs[[n]]) %in% common, , drop = FALSE]
    do.call(rbind, lapply(unique(x$rung), function(r) {
      p <- pooled(x[x$rung == r, , drop = FALSE])
      a <- arms[arms$rung == r & key(arms) %in% common, , drop = FALSE]
      d <- vapply(split(a, a$detector), function(y) p$F1 - pooled(y)$F1, numeric(1))
      cbind(data.frame(run = n, rung = r, stringsAsFactors = FALSE), p,
            as.data.frame(as.list(setNames(d, paste0("d_F1_", names(d))))))
    }))
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

# "est [lo, hi]"; signed values (differences) carry their sign, with a true minus.
fma_fmt <- function(est, lo, hi, k = 3, signed = FALSE) {
  f <- paste0(if (signed) "%+." else "%.", k, "f")
  out <- ifelse(is.na(est), "—", sprintf(paste0(f, " [", f, ", ", f, "]"), est, lo, hi))
  if (signed) gsub("-", "\u2212", out, fixed = TRUE) else out
}

# The report's tables as Markdown lines.
fma_tables <- function(long, con, strata, scon, change, compute, arms, focus, rungs,
                       repeats = NULL, corrected = NULL, masks = NULL) {
  tab <- function(head, rows) c(paste0("| ", paste(head, collapse = " | "), " |"),
    paste0("|", paste(rep(" --- |", length(head)), collapse = "")),
    vapply(rows, function(r) paste0("| ", paste(r, collapse = " | "), " |"), ""), "")
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
  sites <- setdiff(unique(long$scope), c("five sites", names(MT_REGIONS)))
  for (r in intersect(c("native", "1"), rungs)) {
    fr <- long[long$metric == "F1" & long$rung == r, ]
    out <- c(out, sprintf("F1 per site at rung %s:", r), "",
      tab(c("Arm", sites), lapply(c(focus, arms), function(a) c(a, vapply(sites, function(s)
        cell(fr[fr$scope == s & fr$detector == a, ]), "")))))
  }
  for (r in intersect(c("native", "1"), rungs)) {
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
  if (!is.null(masks)) {
    mm <- intersect(c(focus, arms), unique(masks$model))
    for (k in c("F1", "PQ", "coverage")) out <- c(out,
      sprintf("Point-mask %s against the Voronoi-on-stems proxy, five sites:", k), "",
      tab(c("Model", rungs), lapply(mm, function(a) c(a, vapply(rungs, function(r) {
        v <- masks[[k]][masks$model == a & masks$rung == r]
        if (length(v)) sprintf("%.3f", v) else "—" }, "")))))
  }
  if (!is.null(repeats)) out <- c(out,
    "Repeated ForestMamba runs on the shared cells (F1, and F1 minus each arm):", "",
    tab(c("Run", "Rung", "Cells", "F1", paste("minus", arms)),
        lapply(seq_len(nrow(repeats)), function(i) c(repeats$run[i], repeats$rung[i],
          repeats$cells[i], sprintf("%.3f", repeats$F1[i]), vapply(arms, function(a)
            gsub("-", "\u2212", sprintf("%+.3f", repeats[[paste0("d_F1_", a)]][i]),
                 fixed = TRUE), "")))))
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
  rungs <- MT_RUNGS
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
  ch <- mt_rung_contrasts(eq, list("five sites" = SITES), n_boot = N_BOOT, seed = SEED)
  cp <- fma_compute(file.path(RUNS, "neon", SITES, "forestmamba_instances"))
  write.csv(sc$long, file.path(OUT, "scores.csv"), row.names = FALSE)
  write.csv(sc$contrasts, file.path(OUT, "contrasts.csv"), row.names = FALSE)
  write.csv(st$long, file.path(OUT, "strata.csv"), row.names = FALSE)
  write.csv(st$contrasts, file.path(OUT, "strata_contrasts.csv"), row.names = FALSE)
  write.csv(ch, file.path(OUT, "rung_change.csv"), row.names = FALSE)
  if (!is.null(cp)) write.csv(cp, file.path(OUT, "compute.csv"), row.names = FALSE)
  rp <- NULL
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
  }
  cr <- NULL
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
    write.csv(fmn, file.path(OUT, "null_cells.csv"), row.names = FALSE)
    write.csv(cr$scores, file.path(OUT, "corrected.csv"), row.names = FALSE)
    write.csv(cr$contrasts, file.path(OUT, "corrected_contrasts.csv"), row.names = FALSE)
  } else cat("no chance-agreement cells at ", NULL_CELLS, "; corrected F1 skipped\n", sep = "")
  mk <- fma_masks(RUNS, BASE, SITES,
                  intersect(ARMS, c("forestformer3d", "segmentanytree", "treeisonet")), need_key)
  if (!is.null(mk)) write.csv(mk, file.path(OUT, "masks.csv"), row.names = FALSE)
  md <- fma_tables(sc$long, sc$contrasts, st$long, st$contrasts, ch, cp, ARMS,
                   FMA_FOCUS$arm, rungs, rp, cr, mk)
  writeLines(c(sprintf("Population %s, %d plots, %d cells per arm; root %s; %d draws, seed %d.",
                       POP, length(unique(paste(eq$site, eq$plot))), nrow(eq) /
                         length(unique(eq$detector)), substr(root_id, 1, 12), N_BOOT, SEED),
               "", md), file.path(OUT, "tables.md"))
  cat(sprintf("forestmamba analysis -> %s\n", OUT))
}

if (sys.nframe() == 0L) run_main()
