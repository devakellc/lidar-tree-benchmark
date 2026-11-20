#!/usr/bin/env Rscript
.bs_ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (!is.null(.bs_ofile) && length(.bs_ofile) && nzchar(.bs_ofile))
    file.path(dirname(.bs_ofile), "bootstrap.R"),
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])),
                                  "bootstrap.R"),
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_ofile, .bs_file)

# Check R3 of the gated multichm confirmation protocol
# (docs/multichm-gated-confirmation-protocol.md): the five frozen
# configurations of `multichm_gated` re-scored at native density under the
# scoring variants the benchmark paper uses for its other detectors
# (paper_sensitivity.R MODE=matcher, MODE=exact2021 and MODE=jitter). It
# re-scores data already used; it is not a confirmation test.
#
# Detections are regenerated from the candidate search the calibration study
# stored per clip (calval_multichm_gated.R STAGE=candidates, one .rds per site x
# plot x rung) with mcg_apply(); there is no new candidate search. Each
# detection set is scored with the benchmark's own scorer and matchers
# (sweep_lib.R: score_plot, greedy_match, optimal_match, match_tol,
# perturb_positions), with the stems and tolerances paper_sensitivity.R builds:
#   baseline        greedy, 4 m, height gate [0.5 h, h + 8 m]
#   scaled          greedy, per-stem tolerance max(4, maxCrownDiameter / 2,
#                   pos_unc) capped at 12 m (crown widths: the vst record
#                   nearest to 2021, as paper_sensitivity.R reads them)
#   optimal         Hungarian, 4 m, height gate
#   optimal_scaled  Hungarian, the scaled tolerance
#   soft3d          Hungarian, 4 m, soft 3-D cost (lambda 0.5)
#   grid_tx<r>_tz8  greedy at radius r = 2, 3 or 5 m, height gate
#   exact2021       baseline against the core stems measured in 2021 only (the
#                   plots holding at least one)
#   jitter          K draws of stem positions, sigma = pos_unc, baseline
#                   matcher; draw k uses seed seed_for(site, plot, "native") + k
# The baseline must reproduce the study's cells.csv exactly (n_ref, n_det, TP,
# tp_core) for the five configurations in every native cell; the script stops
# otherwise. It is checked with the variants' stems and with the stems the
# study scored with (the declared population's core stems in file order).
#
# These variants have no shift null: plain recall, precision and F1 from
# pooled counts (summed, never averaged). Per variant and scope (five sites,
# California, Washington): each configuration's pooled scores with paired
# plot-bootstrap intervals (mt_plot_weights / mt_boot_scores, MT_SEED), and five
# paired contrasts with mcg_contrast() (the same draws for both sides). Jitter:
# the 5th, 50th and 95th percentile over draws of each configuration's pooled
# scores and of each contrast.
#
# Usage:
#   Rscript scripts/confirm_gated_scoring_variants.R [BASE=work/paper_runs]
#     [CANDIDATES=work/multichm_gated_runs/neon/multichm_gated]
#     [FROZEN_ROOT=work/neon/frozen_2021] [SITES=SJER,SOAP,TEAK,WREF,ABBY]
#     [POP=adopted] [K=200] [N_BOOT=1000] [CORES=4]
#     [OUT=$CLAUDE_JOB_DIR/variants]
# BASE (read only) holds neon/<SITE>/{ground_truth_stems.csv,plot_centroids.csv,
# vst/<site>_vst_allyears.rds}; CANDIDATES (read only) the study's candidates/,
# candidates.csv, cells.csv and cells.config.json. Writes under OUT:
# cells.csv (one row per variant x plot x configuration), jitter_cells.csv (one
# row per draw x plot x configuration), baseline_check.csv, pooled.csv,
# contrasts.csv, jitter_bands.csv, jitter_contrasts.csv, run.json, tables.md.
suppressMessages({ library(data.table); library(parallel) })
source(.find("sweep_lib.R"))          # score_plot, match_tol, perturb_positions, plot_lapply
source(.find("model_bench_lib.R"))    # frozen_*, seed_for, assert_detection_contract
source(.find("master_tables_lib.R"))  # mt_plot_weights, mt_boot_scores, mt_interval, MT_*
source(.find("multichm_gated_lib.R")) # mcg_apply, mcg_contrast, .mcg_counts, mcg_grid

## ---- what is scored -------------------------------------------------------------------------
# The five configurations of the protocol, by short name and grid label.
CGV_CONFIGS <- c(stock = "stock", floor = "z5_s0_c0_e0", floor_exempt = "z5_s0_c0.6_e1",
                 declared = "z5_s0.75_c0.6_e1_d8", gate_everywhere = "z5_s0.75_c0.6_e1")
CGV_CONFIG_WORDS <- c(stock = "Stock", floor = "Floor", floor_exempt = "Floor and exemption",
                      declared = "Declared", gate_everywhere = "Gate everywhere")
# The protocol's contrasts, a minus b.
CGV_CONTRASTS <- list(c("declared", "stock"), c("declared", "floor_exempt"),
                      c("floor_exempt", "floor"), c("floor", "stock"),
                      c("declared", "gate_everywhere"))
CGV_BASE_TOL <- 4; CGV_TOL_CAP <- 12; CGV_LAMBDA <- 0.5
# paper_sensitivity.R's matcher configurations (MODE=matcher) and the greedy
# radii of its grid at the baseline's height gate.
CGV_VARIANTS <- list(
  list(name = "baseline",       method = "greedy",  scaled = FALSE, tx = 4, tz = 8, lambda = NULL),
  list(name = "optimal",        method = "optimal", scaled = FALSE, tx = 4, tz = 8, lambda = NULL),
  list(name = "scaled",         method = "greedy",  scaled = TRUE,  tx = 4, tz = 8, lambda = NULL),
  list(name = "optimal_scaled", method = "optimal", scaled = TRUE,  tx = 4, tz = 8, lambda = NULL),
  list(name = "soft3d",         method = "optimal", scaled = FALSE, tx = 4, tz = 8,
       lambda = CGV_LAMBDA),
  list(name = "grid_tx2_tz8",   method = "greedy",  scaled = FALSE, tx = 2, tz = 8, lambda = NULL),
  list(name = "grid_tx3_tz8",   method = "greedy",  scaled = FALSE, tx = 3, tz = 8, lambda = NULL),
  list(name = "grid_tx5_tz8",   method = "greedy",  scaled = FALSE, tx = 5, tz = 8, lambda = NULL))
CGV_BASELINE <- CGV_VARIANTS[[1]]
CGV_VARIANT_WORDS <- c(
  baseline = "Baseline (greedy, 4 m, height gate)", optimal = "Hungarian",
  scaled = "Crown-scaled tolerance", optimal_scaled = "Hungarian with the scaled tolerance",
  soft3d = "Soft 3-D cost", grid_tx2_tz8 = "Greedy, 2 m", grid_tx3_tz8 = "Greedy, 3 m",
  grid_tx5_tz8 = "Greedy, 5 m", exact2021 = "Core stems measured in 2021 only",
  baseline_exact2021_plots = "Baseline on the exact-2021 plots")
CGV_COUNTS <- c("n_ref", "n_over", "n_under", "n_det", "TP", "tp_core", "tp_over", "tp_under")
CGV_JITTER_COUNTS <- c("n_ref", "n_det", "TP", "tp_core")
CGV_CHECK_COLS <- c("n_ref", "n_det", "TP", "tp_core")
CGV_FIVE <- c("SJER", "SOAP", "TEAK", "WREF", "ABBY")

## ---- arguments ----------------------------------------------------------------------------
cgv_settings <- function(args = commandArgs(TRUE), d = .job_dir()) {
  a <- strsplit(args, "=", fixed = TRUE)
  A <- stats::setNames(lapply(a, function(x) paste(x[-1], collapse = "=")),
                       vapply(a, `[`, character(1), 1))
  get <- function(k, default) if (is.null(A[[k]]) || !nzchar(A[[k]])) default else A[[k]]
  root <- if (exists(".ROOT")) .ROOT else getwd()
  S <- list(
    A = A, d = d,
    BASE = get("BASE", file.path(root, "work", "paper_runs")),
    CANDIDATES = get("CANDIDATES", file.path(root, "work", "multichm_gated_runs", "neon",
                                             "multichm_gated")),
    FROZEN_ROOT = get("FROZEN_ROOT", file.path(root, "work", "neon", "frozen_2021")),
    SITES = strsplit(get("SITES", paste(CGV_FIVE, collapse = ",")), ",")[[1]],
    POP = get("POP", "adopted"),
    K = suppressWarnings(as.integer(get("K", "200"))),
    N_BOOT = suppressWarnings(as.integer(get("N_BOOT", as.character(MT_N_BOOT)))),
    CORES = suppressWarnings(as.integer(get("CORES", "4"))),
    OUT = get("OUT", file.path(d, "variants")))
  if (anyNA(c(S$K, S$N_BOOT, S$CORES)) || S$K < 1 || S$N_BOOT < 1 || S$CORES < 1)
    stop("K, N_BOOT and CORES must be positive integers", call. = FALSE)
  if (!all(S$SITES %in% CGV_FIVE))
    stop("SITES must be among ", paste(CGV_FIVE, collapse = ","), call. = FALSE)
  cgv_out_guard(S$OUT, c(S$BASE, S$CANDIDATES, S$FROZEN_ROOT))
  S
}

# OUT must not lie inside a read-only input.
cgv_out_guard <- function(out, inputs) {
  o <- normalizePath(out, mustWork = FALSE)
  for (p in inputs) {
    q <- normalizePath(p, mustWork = FALSE)
    if (identical(o, q) || startsWith(o, paste0(q, .Platform$file.sep)))
      stop("OUT (", out, ") lies inside a read-only input (", p, ")", call. = FALSE)
  }
  invisible(TRUE)
}

# The five configurations as library configurations, from the grid by label.
cgv_configs <- function(grid = mcg_grid()) {
  i <- match(CGV_CONFIGS, grid$label)
  if (anyNA(i)) stop("labels not in mcg_grid(): ", paste(CGV_CONFIGS[is.na(i)], collapse = ","),
                     call. = FALSE)
  if (!identical(mcg_config_label(MCG_DECLARED), CGV_CONFIGS[["declared"]]))
    stop("MCG_DECLARED is not ", CGV_CONFIGS[["declared"]], call. = FALSE)
  cfgs <- lapply(i, function(g) mcg_config(grid$zmin[g], grid$min_share[g], grid$cover_min[g],
                                           grid$surface_exempt[g], grid$spacing_min[g]))
  stats::setNames(cfgs, CGV_CONFIGS)
}

## ---- stems --------------------------------------------------------------------------------
# Field crown widths for the scaled tolerance, as paper_sensitivity.R reads them:
# per individual, the vst record nearest to 2021 (ties in file order).
cgv_field_crowns <- function(base, site) {
  rds <- file.path(base, "neon", site, "vst", paste0(tolower(site), "_vst_allyears.rds"))
  if (!file.exists(rds)) return(data.frame(individualID = character(), maxCrownDiameter = numeric()))
  ai <- as.data.frame(readRDS(rds)$vst_apparentindividual)
  ai$year <- as.integer(substr(ai$date, 1, 4))
  ai <- ai[!is.na(ai$year), ]
  ai <- ai[order(ai$individualID, abs(ai$year - 2021)), ]
  ai[!duplicated(ai$individualID), c("individualID", "maxCrownDiameter")]
}

# One site's reference: `cells` the declared population's stems as the study
# scored them, `paper` the same stems as paper_sensitivity.R builds them (its
# maxCrownDiameter replaced by the field crowns, merged by individualID).
cgv_site_reference <- function(base, site, frozen_root, pop) {
  nd <- file.path(base, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  fz <- frozen_scope(base, site, list(FROZEN_ROOT = frozen_root, POP = pop), gt)
  g <- fz$gt[, setdiff(names(fz$gt), "maxCrownDiameter"), drop = FALSE]
  g <- merge(g, cgv_field_crowns(base, site), by = "individualID", all.x = TRUE)
  list(cells = fz$gt, paper = g, plots = fz$plots, root = fz$root, population = fz$population,
       pc = pc)
}

# A plot's core stems: within `half` of (cx, cy) in x and y.
cgv_core <- function(gt, plot, cx, cy, half)
  gt[gt$plotID == plot & abs(gt$E - cx) <= half & abs(gt$N - cy) <= half, , drop = FALSE]

## ---- scoring --------------------------------------------------------------------------------
# One detection set against one stem set under one matcher variant: the counts
# of mcg_score_cell's observed side (.mcg_counts of a score_plot row).
cgv_counts <- function(stems, det, v, cx, cy, half, tol) {
  sc <- score_plot(stems, det, tol_xy = tol, core_cx = cx, core_cy = cy, core_half = half,
                   method = v$method, tol_z_up = v$tz, lambda = v$lambda)
  .mcg_counts(sc)
}

# Every variant of one native cell. j: site, plot, cx, cy, half, stems (the
# variants' stems), stems_cells (the study's); dets: detection sets named by
# configuration label. Identical detection sets are scored once. Returns
# list(rows = one row per variant x configuration, jitter = one row per draw x
# configuration). Variant "baseline_cells" is the baseline against the study's
# stems (the reproduction check only).
cgv_score_cell <- function(j, dets, K) {
  st <- j$stems
  tol_vec <- match_tol(st$maxCrownDiameter, st$pos_unc, base_tol = CGV_BASE_TOL, k = 1,
                       tol_cap = CGV_TOL_CAP)
  st21 <- st[!is.na(st$meas_year) & st$meas_year == 2021, , drop = FALSE]
  seed0 <- seed_for(j$site, j$plot, "native")
  jit <- lapply(seq_len(K), function(k) perturb_positions(st$E, st$N, st$pos_unc, seed0 + k))
  keys <- vapply(dets, function(d) digest::digest(list(d$x, d$y, d$z)), character(1))
  memo <- list()
  for (key in unique(keys)) {
    det <- dets[[match(key, keys)]]
    sc <- function(stems, v) cgv_counts(stems, det, v, j$cx, j$cy, j$half,
                                        if (v$scaled) tol_vec else v$tx)
    r <- lapply(CGV_VARIANTS, function(v) sc(st, v))
    names(r) <- vapply(CGV_VARIANTS, `[[`, character(1), "name")
    r$baseline_cells <- sc(j$stems_cells, CGV_BASELINE)
    if (nrow(st21)) r$exact2021 <- sc(st21, CGV_BASELINE)
    jr <- vapply(jit, function(p) {
      s2 <- st; s2$E <- p$E; s2$N <- p$N
      sc(s2, CGV_BASELINE)[CGV_JITTER_COUNTS]
    }, numeric(length(CGV_JITTER_COUNTS)))
    memo[[key]] <- list(rows = r, jitter = matrix(jr, nrow = length(CGV_JITTER_COUNTS),
                                                  dimnames = list(CGV_JITTER_COUNTS, NULL)))
  }
  rows <- list(); jitter <- list()
  for (cfg in names(dets)) {
    m <- memo[[keys[[cfg]]]]
    for (v in names(m$rows))
      rows[[length(rows) + 1L]] <- cbind(
        data.frame(variant = v, site = j$site, plot = j$plot, config = cfg,
                   stringsAsFactors = FALSE),
        as.data.frame(as.list(m$rows[[v]][CGV_COUNTS])))
    jitter[[length(jitter) + 1L]] <- cbind(
      data.frame(draw = seq_len(K), site = j$site, plot = j$plot, config = cfg,
                 stringsAsFactors = FALSE),
      as.data.frame(t(m$jitter)))
  }
  list(rows = do.call(rbind, rows), jitter = do.call(rbind, jitter))
}

# One plot: the stored candidates of its native cell, the five configurations'
# detections, every variant.
cgv_plot_job <- function(j, cdir, cfgs, K) {
  cell <- readRDS(file.path(cdir, j$file))
  m <- cell$meta
  if (!identical(m$site, j$site) || !identical(m$plot, j$plot) || !identical(m$rung, "native"))
    stop("candidate file ", j$file, " does not hold ", j$site, "/", j$plot, " native")
  dets <- lapply(cfgs, function(cfg) mcg_apply(cell$prep, cfg))
  cgv_score_cell(j, dets, K)
}
cgv_plot_worker <- function(j, cdir, cfgs, K)
  tryCatch(cgv_plot_job(j, cdir, cfgs, K), error = function(e) {
    message("plot ", j$site, "/", j$plot, " failed: ", conditionMessage(e)); e })

## ---- the reproduction check -----------------------------------------------------------------
# base: rows of one baseline variant (site, plot, config, CGV_CHECK_COLS); cells:
# the study's native rows of the five configurations. Every (site, plot,
# config) must be in both, once, with equal counts. Returns the merged table
# with a `same` column; attr "ok" says whether every row agrees and both sides
# hold the same cells.
cgv_baseline_check <- function(base, cells) {
  key <- c("site", "plot", "config")
  b <- as.data.frame(base)[c(key, CGV_CHECK_COLS)]
  c0 <- as.data.frame(cells)[c(key, CGV_CHECK_COLS)]
  if (anyDuplicated(b[key]) || anyDuplicated(c0[key]))
    stop("duplicate cells in the reproduction check", call. = FALSE)
  names(c0)[match(CGV_CHECK_COLS, names(c0))] <- paste0("cells_", CGV_CHECK_COLS)
  x <- merge(b, c0, by = key, all = TRUE)
  same <- Reduce(`&`, lapply(CGV_CHECK_COLS, function(k) {
    a <- x[[k]]; z <- x[[paste0("cells_", k)]]
    !is.na(a) & !is.na(z) & a == z
  }))
  x$same <- same
  attr(x, "ok") <- all(same)
  x
}

## ---- pooling --------------------------------------------------------------------------------
cgv_ids <- function(r) paste(r$site, r$plot, sep = "::")
cgv_with_null <- function(rows) {
  rows <- as.data.frame(rows)
  for (k in setdiff(MCG_COUNT_COLS, names(rows))) rows[[k]] <- NA_real_
  rows
}

# Scopes over the sites present: five sites, then the master tables' regions.
cgv_scopes <- function(sites) {
  s <- c(list(`Five sites` = sites), MT_REGIONS)
  s <- lapply(s, function(v) intersect(v, sites))
  s[vapply(s, length, integer(1)) > 0L]
}

# One variant's rows (site, plot, config label, counts) over the scopes: each
# configuration's pooled scores with plot-bootstrap intervals and every
# contrast (mcg_contrast: plots resampled within site, the same draws for both
# configurations). Every configuration must cover the same plots.
cgv_pool_variant <- function(rows, variant, scopes, n_boot = MT_N_BOOT, seed = MT_SEED,
                             configs = CGV_CONFIGS, contrasts = CGV_CONTRASTS) {
  rows <- as.data.frame(rows)
  pooled <- list(); con <- list()
  for (sc in names(scopes)) {
    xs <- rows[rows$site %in% scopes[[sc]] & rows$config %in% configs, , drop = FALSE]
    if (!nrow(xs)) next
    plots <- unique(cgv_ids(xs))
    W <- mt_plot_weights(xs$site, xs$plot, n_boot, seed)
    s <- mt_boot_scores(xs, W, "config")
    est <- mt_intervals(s)
    est$name <- names(configs)[match(est$config, configs)]
    pooled[[length(pooled) + 1L]] <- cbind(data.frame(variant = variant, scope = sc,
                                                      stringsAsFactors = FALSE), est)
    xn <- cgv_with_null(xs)
    for (ct in contrasts) {
      r <- mcg_contrast(xn, plots, configs[[ct[1]]], configs[[ct[2]]], n_boot = n_boot,
                        seed = seed, metrics = c("F1", "precision", "recall"))
      con[[length(con) + 1L]] <- cbind(
        data.frame(variant = variant, scope = sc, contrast = paste(ct, collapse = "_minus_"),
                   stringsAsFactors = FALSE), r)
    }
  }
  list(pooled = do.call(rbind, pooled), contrasts = do.call(rbind, con))
}

# Percentiles over draws of pooled scores (jitter). jit: one row per draw x
# plot x configuration with CGV_JITTER_COUNTS. Returns list(bands = per scope x
# configuration, contrasts = per scope x contrast), each with the 5th, 50th and
# 95th percentile (type 7) of recall, precision and F1.
cgv_jitter_bands <- function(jit, scopes, configs = CGV_CONFIGS, contrasts = CGV_CONTRASTS,
                             probs = c(0.05, 0.5, 0.95)) {
  dt <- data.table::as.data.table(jit)
  q <- function(v) stats::quantile(v, probs, type = 7, names = FALSE, na.rm = TRUE)
  qcols <- function(prefix, v) stats::setNames(as.list(q(v)),
                                               paste0(prefix, c("_p05", "_p50", "_p95")))
  bands <- list(); con <- list()
  for (sc in names(scopes)) {
    x <- dt[dt$site %in% scopes[[sc]] & dt$config %in% configs]
    if (!nrow(x)) next
    p <- x[, list(n_plots = data.table::uniqueN(paste(site, plot)), n_ref = sum(n_ref),
                  n_det = sum(n_det), TP = sum(TP), tp_core = sum(tp_core)),
           by = c("draw", "config")]
    p[, recall := TP / n_ref]
    p[, precision := ifelse(n_det > 0, tp_core / n_det, NA_real_)]
    p[, F1 := ifelse(recall + precision > 0, 2 * recall * precision / (recall + precision),
                     NA_real_)]
    for (cfg in unname(configs)) {
      y <- p[p$config == cfg]
      if (!nrow(y)) next
      bands[[length(bands) + 1L]] <- data.frame(
        scope = sc, config = cfg, name = names(configs)[match(cfg, configs)],
        n_plots = y$n_plots[1], draws = nrow(y), qcols("F1", y$F1),
        qcols("precision", y$precision), qcols("recall", y$recall), stringsAsFactors = FALSE)
    }
    for (ct in contrasts) {
      a <- p[p$config == configs[[ct[1]]]]; b <- p[p$config == configs[[ct[2]]]]
      if (!nrow(a) || !nrow(b)) next
      b <- b[match(a$draw, b$draw)]
      con[[length(con) + 1L]] <- data.frame(
        scope = sc, contrast = paste(ct, collapse = "_minus_"), draws = nrow(a),
        qcols("F1", a$F1 - b$F1), qcols("precision", a$precision - b$precision),
        qcols("recall", a$recall - b$recall), stringsAsFactors = FALSE)
    }
  }
  list(bands = do.call(rbind, bands), contrasts = do.call(rbind, con))
}

## ---- Markdown -------------------------------------------------------------------------------
cgv_f3 <- function(x) ifelse(is.na(x), "NA", sprintf("%.3f", x))
cgv_s3 <- function(x) ifelse(is.na(x), "NA", sub("^-", "−", sprintf("%+.3f", x)))
cgv_iv <- function(e, lo, hi, f = cgv_s3) sprintf("%s [%s, %s]", f(e), f(lo), f(hi))
cgv_md_row <- function(...) paste0("| ", paste(unlist(list(...)), collapse = " | "), " |")

cgv_tables_md <- function(pooled, contrasts, bands, jcon, meta) {
  L <- c("# Gated multichm: scoring variants at native density (check R3)", "",
         sprintf("Population %s, %d plots, sealed root %s (clip manifest %s).",
                 meta$population, meta$n_plots, meta$frozen_root, meta$root_id),
         sprintf(paste("Detections regenerated from the stored candidates of %s; the",
                       "baseline reproduces cells.csv in %d of %d native cells x",
                       "configurations."), meta$candidates, meta$n_same, meta$n_check),
         sprintf(paste("Plain scores from pooled counts; no shift null. Intervals: 95%% paired",
                       "plot-bootstrap percentiles (plots resampled within site, %d draws,",
                       "MT_SEED), the same draws for both sides of a contrast."), meta$n_boot),
         "")
  vars <- unique(pooled$variant)
  cfgs <- names(CGV_CONFIGS)
  for (m in c("F1", "precision", "recall")) {
    L <- c(L, sprintf("## Pooled %s", m), "",
           cgv_md_row("Variant", "Scope", "Plots", "Stems", CGV_CONFIG_WORDS[cfgs]),
           cgv_md_row("---", "---", "---", "---", rep("---", length(cfgs))))
    for (v in vars) for (sc in unique(pooled$scope)) {
      x <- pooled[pooled$variant == v & pooled$scope == sc & pooled$metric == m, , drop = FALSE]
      if (!nrow(x)) next
      x <- x[match(cfgs, x$name), , drop = FALSE]
      L <- c(L, cgv_md_row(CGV_VARIANT_WORDS[[v]], sc, x$n_plots[1], x$n_ref[1],
                           cgv_iv(x$estimate, x$lower, x$upper, cgv_f3)))
    }
    L <- c(L, "")
  }
  L <- c(L, "## Detections in the plot cores", "",
         cgv_md_row("Plots", "Scope", CGV_CONFIG_WORDS[cfgs]),
         cgv_md_row("---", "---", rep("---", length(cfgs))))
  for (v in c("baseline", "exact2021")) for (sc in unique(pooled$scope)) {
    x <- pooled[pooled$variant == v & pooled$scope == sc & pooled$metric == "F1", , drop = FALSE]
    if (!nrow(x)) next
    x <- x[match(cfgs, x$name), , drop = FALSE]
    L <- c(L, cgv_md_row(sprintf("%d (%s)", x$n_plots[1], if (v == "baseline") "all" else
                                   "exact-2021 plots"), sc,
                         format(x$n_det, big.mark = ",")))
  }
  L <- c(L, "")
  cons <- vapply(CGV_CONTRASTS, paste, character(1), collapse = "_minus_")
  cwords <- vapply(CGV_CONTRASTS, function(ct)
    paste(CGV_CONFIG_WORDS[[ct[1]]], "−", tolower(CGV_CONFIG_WORDS[[ct[2]]])), character(1))
  for (m in c("F1", "precision", "recall")) {
    L <- c(L, sprintf("## Paired change in %s", m), "",
           cgv_md_row("Variant", "Scope", "Plots", cwords),
           cgv_md_row("---", "---", "---", rep("---", length(cons))))
    for (v in unique(contrasts$variant)) for (sc in unique(contrasts$scope)) {
      x <- contrasts[contrasts$variant == v & contrasts$scope == sc & contrasts$metric == m, ,
                     drop = FALSE]
      if (!nrow(x)) next
      x <- x[match(cons, x$contrast), , drop = FALSE]
      L <- c(L, cgv_md_row(CGV_VARIANT_WORDS[[v]], sc, x$n_plots[1],
                           cgv_iv(x$difference, x$lower, x$upper)))
    }
    L <- c(L, "")
  }
  L <- c(L, sprintf("## Jittered stem positions (%d draws)", meta$K), "",
         "Percentiles over draws of the pooled score: 5th / 50th / 95th.", "",
         cgv_md_row("Scope", "Configuration", "F1", "Precision", "Recall"),
         cgv_md_row("---", "---", "---", "---", "---"))
  p3 <- function(x, k) sprintf("%s / %s / %s", cgv_f3(x[[paste0(k, "_p05")]]),
                               cgv_f3(x[[paste0(k, "_p50")]]), cgv_f3(x[[paste0(k, "_p95")]]))
  s3 <- function(x, k) sprintf("%s / %s / %s", cgv_s3(x[[paste0(k, "_p05")]]),
                               cgv_s3(x[[paste0(k, "_p50")]]), cgv_s3(x[[paste0(k, "_p95")]]))
  for (i in seq_len(nrow(bands)))
    L <- c(L, cgv_md_row(bands$scope[i], CGV_CONFIG_WORDS[[bands$name[i]]],
                         p3(bands[i, ], "F1"), p3(bands[i, ], "precision"),
                         p3(bands[i, ], "recall")))
  L <- c(L, "", cgv_md_row("Scope", "Contrast", "Change in F1", "Change in precision",
                           "Change in recall"),
         cgv_md_row("---", "---", "---", "---", "---"))
  for (i in seq_len(nrow(jcon)))
    L <- c(L, cgv_md_row(jcon$scope[i], cwords[match(jcon$contrast[i], cons)],
                         s3(jcon[i, ], "F1"), s3(jcon[i, ], "precision"), s3(jcon[i, ], "recall")))
  c(L, "")
}

## ---- main -----------------------------------------------------------------------------------
cgv_read_cells_config <- function(cand, root, pop) {
  f <- file.path(cand, "cells.config.json")
  if (!file.exists(f)) stop("no ", f, call. = FALSE)
  r <- jsonlite::read_json(f, simplifyVector = TRUE)
  if (!identical(r$clip_manifest_sha256, frozen_root_id(root)))
    stop("cells.csv was scored on another frozen root than ", root, call. = FALSE)
  if (!identical(r$population, pop)) stop("cells.csv was scored for population ", r$population,
                                          call. = FALSE)
  if (!identical(as.numeric(r$tol), CGV_BASE_TOL))
    stop("cells.csv was scored at TOL ", r$tol, call. = FALSE)
  r
}

run_main <- function() {
  t0 <- Sys.time()
  S <- cgv_settings()
  dir.create(S$OUT, recursive = TRUE, showWarnings = FALSE)
  cdir <- file.path(S$CANDIDATES, "candidates")
  frozen_stamp_check(cdir, S$FROZEN_ROOT)
  rec <- cgv_read_cells_config(S$CANDIDATES, S$FROZEN_ROOT, S$POP)
  cfgs <- cgv_configs()
  idx <- read.csv(file.path(S$CANDIDATES, "candidates.csv"), stringsAsFactors = FALSE,
                  colClasses = c(rung = "character"))
  idx <- idx[idx$rung == "native" & idx$site %in% S$SITES, , drop = FALSE]
  if (any(idx$population != S$POP) || any(abs(idx$a - 0.10) > 1e-12))
    stop("the candidates were not made for population ", S$POP, " with a = 0.10", call. = FALSE)
  jobs <- list(); refs <- list()
  for (site in S$SITES) {
    refs[[site]] <- cgv_site_reference(S$BASE, site, S$FROZEN_ROOT, S$POP)
    x <- idx[idx$site == site, , drop = FALSE]
    if (!all(x$plot %in% refs[[site]]$plots))
      stop("candidate plots outside the declared population at ", site, call. = FALSE)
    for (i in seq_len(nrow(x))) {
      r <- x[i, ]
      jobs[[length(jobs) + 1L]] <- list(
        site = site, plot = r$plot, file = r$file, cx = r$cx, cy = r$cy, half = r$half,
        stems = cgv_core(refs[[site]]$paper, r$plot, r$cx, r$cy, r$half),
        stems_cells = cgv_core(refs[[site]]$cells, r$plot, r$cx, r$cy, r$half))
    }
  }
  cat(sprintf("[variants] %d native cells (%s), %d configurations, %d matcher variants + exact2021 + %d jitter draws, %d cores\n",
              length(jobs), paste(S$SITES, collapse = ","), length(cfgs), length(CGV_VARIANTS),
              S$K, S$CORES))
  res <- plot_lapply(jobs, cgv_plot_worker, cdir = cdir, cfgs = cfgs, K = S$K,
                     mc.cores = S$CORES)
  bad <- vapply(res, function(r) inherits(r, "error"), logical(1))
  if (any(bad)) stop("plots failed: ", paste(vapply(jobs[bad], function(j)
    paste(j$site, j$plot, sep = "/"), ""), collapse = ","), call. = FALSE)
  rows <- as.data.frame(data.table::rbindlist(lapply(res, `[[`, "rows")))
  jit <- as.data.frame(data.table::rbindlist(lapply(res, `[[`, "jitter")))
  t_score <- Sys.time()
  write.csv(rows, file.path(S$OUT, "cells.csv"), row.names = FALSE)
  data.table::fwrite(jit, file.path(S$OUT, "jitter_cells.csv"))
  ## the reproduction check, before anything is pooled
  cells <- data.table::fread(file.path(S$CANDIDATES, "cells.csv"),
                             select = c("site", "plot", "rung", "config", CGV_CHECK_COLS),
                             colClasses = list(character = "rung"))
  cells <- as.data.frame(cells[cells$rung == "native" & cells$config %in% CGV_CONFIGS &
                                 cells$site %in% S$SITES])
  chk <- list()
  for (v in c("baseline", "baseline_cells")) {
    k <- cgv_baseline_check(rows[rows$variant == v, , drop = FALSE], cells)
    chk[[v]] <- cbind(stems = if (v == "baseline") "variants" else "study", k)
    cat(sprintf("[check] baseline with the %s stems: %d of %d native cell x configuration rows equal cells.csv (n_ref, n_det, TP, tp_core)%s\n",
                if (v == "baseline") "variants'" else "study's", sum(k$same), nrow(k),
                if (attr(k, "ok")) "" else " -- MISMATCH"))
  }
  ck <- do.call(rbind, chk)
  write.csv(ck, file.path(S$OUT, "baseline_check.csv"), row.names = FALSE)
  if (!all(ck$same)) stop("the baseline does not reproduce cells.csv; see baseline_check.csv",
                          call. = FALSE)
  ## pooling
  scopes <- cgv_scopes(S$SITES)
  rows$variant[rows$variant == "baseline_cells"] <- NA
  rows <- rows[!is.na(rows$variant), , drop = FALSE]
  # exact2021 runs on the plots holding a 2021 core stem; the baseline on the
  # same plots is pooled beside it
  p21 <- unique(cgv_ids(rows[rows$variant == "exact2021", ]))
  b21 <- rows[rows$variant == "baseline" & cgv_ids(rows) %in% p21, , drop = FALSE]
  if (nrow(b21)) {
    b21$variant <- "baseline_exact2021_plots"
    rows <- rbind(rows, b21)
  }
  vars <- c(vapply(CGV_VARIANTS, `[[`, character(1), "name"), "exact2021",
            "baseline_exact2021_plots")
  parts <- lapply(vars, function(v) cgv_pool_variant(rows[rows$variant == v, , drop = FALSE], v,
                                                     scopes, S$N_BOOT, MT_SEED))
  pooled <- do.call(rbind, lapply(parts, `[[`, "pooled"))
  contrasts <- do.call(rbind, lapply(parts, `[[`, "contrasts"))
  jb <- cgv_jitter_bands(jit, scopes)
  write.csv(pooled, file.path(S$OUT, "pooled.csv"), row.names = FALSE)
  write.csv(contrasts, file.path(S$OUT, "contrasts.csv"), row.names = FALSE)
  write.csv(jb$bands, file.path(S$OUT, "jitter_bands.csv"), row.names = FALSE)
  write.csv(jb$contrasts, file.path(S$OUT, "jitter_contrasts.csv"), row.names = FALSE)
  meta <- list(population = S$POP, n_plots = length(jobs), frozen_root = S$FROZEN_ROOT,
               root_id = frozen_root_id(S$FROZEN_ROOT), candidates = S$CANDIDATES,
               n_same = sum(chk$baseline$same), n_check = nrow(chk$baseline), K = S$K,
               n_boot = S$N_BOOT)
  writeLines(cgv_tables_md(pooled, contrasts, jb$bands, jb$contrasts, meta),
             file.path(S$OUT, "tables.md"))
  jsonlite::write_json(c(meta, list(
    configs = as.list(CGV_CONFIGS), base = S$BASE, sites = I(S$SITES), seed = MT_SEED, cores = S$CORES, cells_config = rec,
    n_exact2021_plots = length(p21),
    minutes_scoring = as.numeric(difftime(t_score, t0, units = "mins")),
    minutes_total = as.numeric(difftime(Sys.time(), t0, units = "mins")))),
    file.path(S$OUT, "run.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
  cat(sprintf("[variants] done in %.1f min -> %s/{cells,jitter_cells,baseline_check,pooled,contrasts,jitter_bands,jitter_contrasts}.csv, tables.md, run.json\n",
              as.numeric(difftime(Sys.time(), t0, units = "mins")), S$OUT))
  invisible(list(pooled = pooled, contrasts = contrasts, jitter = jb))
}

if (sys.nframe() == 0L) run_main()
