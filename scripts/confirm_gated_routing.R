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
source(.find("model_bench_lib.R"))
source(.find("master_tables_lib.R"))

# Check R6 of the multichm_gated confirmation protocol
# (docs/multichm-gated-confirmation-protocol.md): the density routing of the
# benchmark paper recomputed with one configuration of the gated variant added
# as one more candidate of both the GPU and the CPU route, at the six density
# levels (native and all-return targets 8, 4, 3.2, 2 and 1 points/m2).
#
# The routing itself is the paper's (paper_density_routing.R with
# density_routing_lib.R, on the paper branch): each cell, one plot at one
# level, falls in a band of its measured first-return density (A >= 8, B 2 to
# < 8, C < 2 pulses/m2, from the frozen roots' clip manifests); in each band a
# route runs the candidate with the highest pooled F1 on the band's California
# cells; Washington is the held-out check. Counts are the chance-agreement
# re-scores (observed and each cell's mean over 200 shifts); corrected F1 is
# (F1 - null F1) / (1 - null F1); every interval comes from the master tables'
# plot resamples (mt_plot_weights with their N_BOOT and SEED), so the added
# candidate shares every draw with the paper's detectors and routes.
#
# The routing library is sourced from ROUTING_LIB (it is not on this branch).
# Before anything with the candidate is computed, the same code is run without
# it (the harness) and must reproduce, to 1e-9, every row of the paper's
# routing_cells/bands/picks/scores/contrasts.csv, every detector's per-level
# F1 and corrected F1 against the master tables and the null re-score, and
# (when MANUSCRIPT is readable) the text of every row of Table 7. The
# candidate's cells come from the gated cells files (one row per site x plot x
# rung x config, with the null means n_det0, TP0, tp_core0); its `stock`
# configuration must equal the paper's null cells of `multichm` in every cell,
# and the candidate is banded by the routing's own densities (the gated files'
# densities are compared and reported, never used).
#
#   Rscript scripts/confirm_gated_routing.R CONFIG=<grid label> NAME=<set>
#     HELD_OUT=yes|no [SELECTION=<text>] [LABEL=multichm_gated]
#     [ROUTING_LIB=work/paper-novelty-checkout/scripts/density_routing_lib.R]
#     [PAPER_RUNS=work/paper_runs] [PAPER_ROUTING=<PAPER_RUNS>/density_routing]
#     [MASTER=<PAPER_RUNS>/master_tables] [FROZEN_ROOT=<PAPER_RUNS>/neon/frozen_2021]
#     [RUNG_JOBS=<job dir>:<root>,...] [POP=adopted] [N_BOOT=1000] [SEED=20261002]
#     [MANUSCRIPT=work/paper-novelty-checkout/paper/manuscript.md]
#     [GATED_CELLS=<five-level cells.csv>,<QL2 cells.csv>]
#     [OUT=work/multichm_gated_confirmation/routing/<NAME>]
# Every input is read only. OUT may not lie under work/paper_runs*,
# work/multichm_gated_runs*, a neon/frozen_* root or the routing library's
# checkout. Writes to OUT: harness/ (the reproduced paper tables and
# table7_rows.md), harness_check.csv, routing_check.csv, stock_parity.csv,
# density_agreement.csv, selection_check.csv, routing_cells.csv,
# routing_bands.csv, routing_picks.csv, routing_scores.csv,
# routing_contrasts.csv, washington_bands.csv, route_versus.csv,
# candidate_levels.csv, table7.csv, confirm_gated_routing.md and
# routing_contract.json.

CGR_KNOWN <- c("ROUTING_LIB", "PAPER_RUNS", "PAPER_ROUTING", "MASTER", "FROZEN_ROOT", "RUNG_JOBS",
               "POP", "N_BOOT", "SEED", "MANUSCRIPT", "GATED_CELLS", "CONFIG", "LABEL", "NAME",
               "HELD_OUT", "SELECTION", "OUT")
CGR_TOL <- 1e-9
CGR_GROUP <- c("variant", "policy", "slice")
CGR_MAIN <- c("gpu_route", "cpu_route", "gpu_native", "cpu_native", "gpu_single", "cpu_single")
CGR_NAMES <- c(forestformer3d = "ForestFormer3D", segmentanytree = "SegmentAnyTree",
               treeisonet = "TreeisoNet", multichm = "`multichm`", chm_vwf = "CHM-VWF",
               ams3d = "AMS3D", ptrees = "`ptrees`", lmfauto = "`lmfauto`")
CGR_POLICY_LABEL <- c(gpu_route = "GPU route", cpu_route = "CPU route",
                      gpu_native = "Native-only choice, GPU", cpu_native = "Native-only choice, CPU",
                      gpu_single = "Single choice, GPU", cpu_single = "Single choice, CPU",
                      gpu_wa_best = "Washington best per band, GPU (descriptive)",
                      cpu_wa_best = "Washington best per band, CPU (descriptive)",
                      paper_gpu_route = "Paper's GPU route", paper_cpu_route = "Paper's CPU route")
CGR_ROLE <- c(`five sites` = "both regions", California = "selection data, in sample",
              Washington = "held out")
# Counts of a gated cells row, by variant of the routing cells.
CGR_GATED_COUNTS <- list(baseline = c(n_ref = "n_ref", n_det = "n_det", TP = "TP", tp_core = "tp_core"),
                         null = c(n_ref = "n_ref", n_det = "n_det0", TP = "TP0", tp_core = "tp_core0"))
CGR_COUNTS <- c("TP", "n_ref", "n_det", "tp_core")

## ---- arguments and the output guard ------------------------------------------------------------
cgr_args <- function(argv, known = CGR_KNOWN) {
  args <- strsplit(argv, "=", fixed = TRUE)
  A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")),
                vapply(args, function(x) x[1], character(1)))
  bad <- setdiff(names(A), known)
  if (length(bad)) stop("Unknown arguments: ", paste(bad, collapse = ", "), call. = FALSE)
  if (anyDuplicated(names(A))) stop("Repeated arguments", call. = FALSE)
  A
}

# A path with symlinks resolved through its deepest existing ancestor.
cgr_resolve <- function(path) {
  p <- normalizePath(path.expand(path), mustWork = FALSE)
  rest <- character()
  while (!file.exists(p) && dirname(p) != p) { rest <- c(basename(p), rest); p <- dirname(p) }
  do.call(file.path, as.list(c(normalizePath(p, mustWork = FALSE), rest)))
}

# OUT may not lie under the paper runs, the calibration runs, a frozen root or
# any of the `protected` directories (the routing library's checkout).
cgr_check_out <- function(out, protected = character()) {
  p <- cgr_resolve(out)
  bad <- grepl("(^|/)paper_runs[^/]*(/|$)", p) || grepl("(^|/)multichm_gated_runs[^/]*(/|$)", p) ||
    grepl("(^|/)frozen_[^/]*(/|$)", p)
  for (r in protected[nzchar(protected)]) {
    r <- cgr_resolve(r)
    if (identical(p, r) || startsWith(p, paste0(r, "/"))) bad <- TRUE
  }
  if (bad) stop("OUT=", out, " lies under a protected input directory", call. = FALSE)
  p
}

## ---- the candidate's cells ---------------------------------------------------------------------------
# Rows of one configuration of the gated cells files in the routing's form: one
# baseline and one null row per site x plot x level (the null row carries the
# null means n_det0, TP0 and tp_core0 as its n_det, TP and tp_core).
cgr_gated_rows <- function(g, config, label) {
  g <- as.data.frame(g, stringsAsFactors = FALSE)
  need <- c("site", "plot", "rung", "config", unique(unlist(CGR_GATED_COUNTS)))
  miss <- setdiff(need, names(g))
  if (length(miss)) stop("The gated cells lack columns: ", paste(miss, collapse = ", "))
  x <- g[g$config == config, , drop = FALSE]
  if (!nrow(x)) stop("Configuration ", config, " is not in the gated cells")
  if (anyDuplicated(paste(x$site, x$plot, x$rung))) stop("Duplicate gated cells for ", config)
  out <- do.call(rbind, lapply(names(CGR_GATED_COUNTS), function(v) {
    m <- CGR_GATED_COUNTS[[v]]
    data.frame(variant = v, site = x$site, plot = x$plot, level = as.character(x$rung),
               detector = label, n_ref = as.numeric(x[[m[["n_ref"]]]]),
               n_det = as.numeric(x[[m[["n_det"]]]]), TP = as.numeric(x[[m[["TP"]]]]),
               tp_core = as.numeric(x[[m[["tp_core"]]]]), stringsAsFactors = FALSE)
  }))
  if (anyNA(out[CGR_COUNTS])) stop("Missing counts in the gated cells of ", config)
  out
}

# Cell-by-cell agreement of two sets of routing rows (variant, site, plot,
# level and the counts). One row per variant x level x count: cells on either
# side, cells missing from one side, the largest absolute difference and the
# cells differing by more than `tol`.
cgr_cell_parity <- function(a, b, tol = CGR_TOL) {
  k <- c("variant", "site", "plot", "level")
  m <- merge(a[c(k, CGR_COUNTS)], b[c(k, CGR_COUNTS)], by = k, all = TRUE, suffixes = c("", "_ref"))
  out <- do.call(rbind, lapply(split(m, list(m$variant, m$level), drop = TRUE), function(z)
    do.call(rbind, lapply(CGR_COUNTS, function(cc) {
      d <- abs(z[[cc]] - z[[paste0(cc, "_ref")]])
      data.frame(variant = z$variant[1], level = z$level[1], count = cc, cells = nrow(z),
                 missing = sum(is.na(d)), max_abs_diff = if (all(is.na(d))) NA_real_ else max(d, na.rm = TRUE),
                 differing = sum(is.na(d) | d > tol), stringsAsFactors = FALSE)
    }))))
  rownames(out) <- NULL
  out
}

# The gated files' densities against the routing's (from the clip manifests)
# per cell, with both bands. `band_of` maps first-return density to a band.
cgr_density_agreement <- function(gated, dens, band_of) {
  k <- c("site", "plot", "level")
  m <- merge(dens[c(k, "pdens", "frdens", "band")], gated[c(k, "pdens", "frdens")], by = k,
             all = TRUE, suffixes = c("", "_gated"))
  if (anyNA(m$frdens) || anyNA(m$frdens_gated))
    stop("The gated cells and the routing cells cover different cells")
  m$frdens_diff <- m$frdens_gated - m$frdens
  m$pdens_diff <- m$pdens_gated - m$pdens
  m$band_gated <- band_of(m$frdens_gated)
  m$band_agrees <- m$band == m$band_gated
  m
}

# Pooled F1, null F1 and corrected F1 of every configuration over the cells of
# `sites` at one rung (summed counts, as .mcg_rate_list of multichm_gated_lib.R),
# ranked by corrected F1 with ties to the smallest config_id (mcg_select's rule).
cgr_selection <- function(g, sites, rung = "native", plots = NULL) {
  # rows without a config_id (the files' CHM-VWF baseline) are not configurations
  x <- g[g$rung == rung & g$site %in% sites & !is.na(g$config_id), , drop = FALSE]
  if (!is.null(plots)) x <- x[paste(x$site, x$plot, sep = "::") %in% plots, , drop = FALSE]
  if (!nrow(x)) stop("No gated cells at ", rung, " in ", paste(sites, collapse = ", "))
  cov <- tapply(paste(x$site, x$plot), x$config_id, function(v) paste(sort(v), collapse = ";"))
  if (length(unique(cov)) != 1) stop("The configurations cover different plots")
  cols <- c("n_ref", "n_det", "TP", "tp_core", "n_det0", "TP0", "tp_core0")
  s <- rowsum(as.matrix(x[cols]), x$config_id, reorder = TRUE)
  f1 <- function(r, p) ifelse(r + p > 0, 2 * r * p / (r + p), NA_real_)
  out <- data.frame(config_id = as.integer(rownames(s)), s, row.names = NULL)
  out$config <- x$config[match(out$config_id, x$config_id)]
  out$F1 <- f1(out$TP / out$n_ref, out$tp_core / out$n_det)
  out$F1_null <- f1(out$TP0 / out$n_ref, out$tp_core0 / out$n_det0)
  out$F1_corrected <- (out$F1 - out$F1_null) / (1 - out$F1_null)
  out <- out[order(-out$F1_corrected, out$config_id), c("config", "config_id", cols, "F1", "F1_null",
                                                         "F1_corrected")]
  out$rank <- seq_len(nrow(out))
  out$plots <- length(unique(paste(x$site, x$plot)))
  rownames(out) <- NULL
  out
}

## ---- the routing (paper_density_routing.R, with the candidate set as an argument) ------------------
# Each cell is scored in three slices: its band, "all" and its level.
cgr_slices <- function(x) rbind(transform(x, slice = band), transform(x, slice = "all"),
                                transform(x, slice = paste("level", level)))
cgr_score_scope <- function(rows, sites, W) {
  keep <- sub("::.*$", "", rownames(W)) %in% sites
  Ws <- W[keep, , drop = FALSE]
  x <- cgr_slices(rows[rows$site %in% sites, , drop = FALSE])
  mt_boot_scores(dr_plot_rows(x, CGR_GROUP, rownames(Ws)), Ws, CGR_GROUP)
}
cgr_band_scores <- function(s, detectors, slice_of = function(b) b, bands = DR_BANDS$band)
  do.call(rbind, lapply(bands, function(b) data.frame(
    band = b, detector = detectors,
    F1 = vapply(detectors, function(a) dr_metric(s, paste(a, slice_of(b), sep = "|"), "F1")$e, numeric(1)),
    stringsAsFactors = FALSE)))

# The routing of `cells` (variant, site, plot, level, detector, frdens, band and
# the counts) for the candidate sets `candidates` (list(gpu = , cpu = )),
# scored on `scopes` with the resamples W. `extra` adds fixed policies (band ->
# pick tables) to the score set. Returns the picks of every policy and the
# score sets per scope.
cgr_route <- function(cells, W, scopes, candidates, extra = list()) {
  if (!identical(names(candidates), c("gpu", "cpu"))) stop("Candidates are list(gpu = , cpu = )")
  if (!all(c("California", "Washington") %in% names(scopes))) stop("Scopes need California and Washington")
  detectors <- unique(unlist(candidates, use.names = FALSE))
  if (!setequal(detectors, unique(cells$detector)))
    stop("The cells must hold exactly the candidates: ", paste(detectors, collapse = ", "))
  fixed <- transform(cells, policy = detector)
  fixed_ca <- cgr_score_scope(fixed, scopes$California, W)
  fixed_wa <- cgr_score_scope(fixed, scopes$Washington, W)
  sel <- cgr_band_scores(fixed_ca, detectors)
  routes <- lapply(candidates, function(cand) dr_pick(sel, cand))
  one_choice <- function(slice, cand) {
    p <- dr_pick(cgr_band_scores(fixed_ca, detectors, function(b) slice, "all"), cand)
    list(choice = p, picks = data.frame(band = DR_BANDS$band, pick = p$pick, stringsAsFactors = FALSE))
  }
  native <- lapply(candidates, function(cand) one_choice("level native", cand))
  single <- lapply(candidates, function(cand) one_choice("all", cand))
  wa_best <- lapply(candidates, function(cand) dr_pick(cgr_band_scores(fixed_wa, detectors), cand))
  policies <- list(gpu_route = routes$gpu, cpu_route = routes$cpu,
                   gpu_native = native$gpu$picks, cpu_native = native$cpu$picks,
                   gpu_single = single$gpu$picks, cpu_single = single$cpu$picks,
                   gpu_wa_best = wa_best$gpu, cpu_wa_best = wa_best$cpu)
  if (length(extra) && (is.null(names(extra)) || any(names(extra) %in% c(names(policies), detectors))))
    stop("Extra policies need names distinct from the routing's policies and detectors")
  policies <- c(policies, extra)
  routed <- do.call(rbind, lapply(names(policies), function(p) dr_route_cells(cells, policies[[p]], p)))
  S <- lapply(scopes, function(sites) cgr_score_scope(rbind(fixed, routed), sites, W))
  if (max(abs(sel$F1 - cgr_band_scores(S$California, detectors)$F1)) > 1e-12)
    stop("Selection scores changed")
  list(candidates = candidates, detectors = detectors, sel = sel, routes = routes, native = native,
       single = single, wa_best = wa_best, policies = policies, S = S)
}

# routing_scores.csv: every group x metric of every scope, with the pooled
# counts and the plots of the slice.
cgr_scores <- function(run, dens, scopes, role = CGR_ROLE) {
  keys_of <- function(s) unique(sub("^[^|]*\\|", "", s$groups))
  slice_plots <- function(sc, slice) {
    x <- dens[dens$site %in% scopes[[sc]], , drop = FALSE]
    keep <- if (slice %in% DR_BANDS$band) x$band == slice else
      if (startsWith(slice, "level ")) x$level == sub("^level ", "", slice) else
        if (identical(slice, "all")) rep(TRUE, nrow(x)) else stop("Unknown slice: ", slice)
    length(unique(paste(x$site, x$plot)[keep]))
  }
  scores <- do.call(rbind, lapply(names(scopes), function(sc) {
    s <- run$S[[sc]]
    est <- split(s$estimate, s$estimate$variant)
    do.call(rbind, lapply(keys_of(s), function(k) do.call(rbind, lapply(DR_METRICS, function(m) {
      v <- est[[if (m == "F1_null") "null" else "baseline"]]
      e <- v[paste(v$policy, v$slice, sep = "|") == k, , drop = FALSE]
      if (nrow(e) != 1) stop("Expected one pooled row for ", k)
      cbind(data.frame(scope = sc, role = role[[sc]], policy = e$policy, slice = e$slice,
                       n_plots = slice_plots(sc, e$slice), n_ref = e$n_ref, n_det = e$n_det,
                       TP = e$TP, stringsAsFactors = FALSE), dr_estimate(s, k, m))
    }))))
  }))
  scores$kind <- ifelse(scores$policy %in% run$detectors, "detector", "policy")
  scores <- scores[c("scope", "role", "kind", "policy", "slice", "n_plots", "n_ref", "n_det", "TP",
                     "metric", "estimate", "lower", "upper", "defined_draws")]
  rownames(scores) <- NULL
  scores
}

# The paper's pairs: each main policy against every detector, and the route
# against its native-only choice, the other route, the single choice and the
# Washington best. `more` appends pairs.
cgr_pairs <- function(detectors, more = NULL)
  rbind(expand.grid(policy = CGR_MAIN, versus = detectors, stringsAsFactors = FALSE),
        data.frame(policy = c("gpu_route", "cpu_route", "gpu_route", "gpu_route", "cpu_route",
                              "gpu_route", "cpu_route"),
                   versus = c("gpu_native", "cpu_native", "cpu_route", "gpu_single",
                              "cpu_single", "gpu_wa_best", "cpu_wa_best"),
                   stringsAsFactors = FALSE),
        more)

# Paired differences policy - versus in F1 and corrected F1, per scope and slice.
cgr_contrasts <- function(S, scopes, pairs, slices, role = CGR_ROLE) {
  out <- do.call(rbind, lapply(names(scopes), function(sc) do.call(rbind, lapply(slices,
    function(sl) do.call(rbind, lapply(seq_len(nrow(pairs)), function(i) do.call(rbind, lapply(
      c("F1", "F1_corrected"), function(m) cbind(
        data.frame(scope = sc, role = role[[sc]], slice = sl, policy = pairs$policy[i],
                   versus = pairs$versus[i], stringsAsFactors = FALSE),
        dr_contrast(S[[sc]], paste(pairs$policy[i], sl, sep = "|"),
                    paste(pairs$versus[i], sl, sep = "|"), m))))))))))
  out$descriptive <- grepl("_wa_best$", out$versus)
  rownames(out) <- NULL
  out
}
cgr_get <- function(tab, ...) {
  f <- list(...)
  keep <- Reduce(`&`, lapply(names(f), function(k) tab[[k]] == f[[k]]))
  x <- tab[keep, , drop = FALSE]
  if (nrow(x) != 1) stop("Expected one row for ", paste(names(f), unlist(f), sep = "=", collapse = ", "),
                         "; found ", nrow(x))
  x
}

# routing_picks.csv: per route and band the pick, its California score and
# margin, its Washington scores and its paired difference to the Washington best.
cgr_picks <- function(run, scores, contrasts) {
  sc <- function(scope, det, b, m) cgr_get(scores, scope = scope, policy = det, slice = b, metric = m)
  ct <- function(scope, b, p, v, m) cgr_get(contrasts, scope = scope, slice = b, policy = p, versus = v,
                                            metric = m)
  out <- do.call(rbind, lapply(names(run$candidates), function(r) {
    p <- run$routes[[r]]; wb <- run$wa_best[[r]]
    do.call(rbind, lapply(seq_len(nrow(p)), function(i) {
      b <- p$band[i]; a <- p$pick[i]; best <- wb$pick[wb$band == b]
      ca <- sc("California", a, b, "F1"); wa <- sc("Washington", a, b, "F1")
      wac <- sc("Washington", a, b, "F1_corrected"); fv <- sc("five sites", a, b, "F1")
      bw <- sc("Washington", best, b, "F1"); bwc <- sc("Washington", best, b, "F1_corrected")
      df <- ct("Washington", b, paste0(r, "_route"), paste0(r, "_wa_best"), "F1")
      dfc <- ct("Washington", b, paste0(r, "_route"), paste0(r, "_wa_best"), "F1_corrected")
      data.frame(route = r, band = b, label = DR_BANDS$label[DR_BANDS$band == b], pick = a,
                 ca_F1 = ca$estimate, ca_F1_lower = ca$lower, ca_F1_upper = ca$upper,
                 ca_runner_up = p$runner_up[i], ca_runner_up_F1 = p$runner_up_value[i],
                 ca_margin = p$margin[i],
                 wa_F1 = wa$estimate, wa_F1_lower = wa$lower, wa_F1_upper = wa$upper,
                 wa_F1c = wac$estimate, wa_F1c_lower = wac$lower, wa_F1c_upper = wac$upper,
                 wa_best = best, wa_best_F1 = bw$estimate, wa_best_F1_lower = bw$lower,
                 wa_best_F1_upper = bw$upper, wa_best_F1c = bwc$estimate,
                 wa_best_F1c_lower = bwc$lower, wa_best_F1c_upper = bwc$upper,
                 pick_minus_best = df$estimate, pick_minus_best_lower = df$lower,
                 pick_minus_best_upper = df$upper, pick_minus_best_c = dfc$estimate,
                 pick_minus_best_c_lower = dfc$lower, pick_minus_best_c_upper = dfc$upper,
                 five_F1 = fv$estimate, five_F1_lower = fv$lower, five_F1_upper = fv$upper,
                 stringsAsFactors = FALSE)
    }))
  }))
  rownames(out) <- NULL
  out
}
# The margin's paired interval: route minus runner-up on the band's
# California cells (in a band the route's cells are the pick's).
cgr_margins <- function(picks, contrasts) {
  m <- do.call(rbind, lapply(seq_len(nrow(picks)), function(i) {
    if (is.na(picks$ca_runner_up[i])) return(data.frame(e = NA_real_, l = NA_real_, u = NA_real_))
    x <- cgr_get(contrasts, scope = "California", slice = picks$band[i],
                 policy = paste0(picks$route[i], "_route"), versus = picks$ca_runner_up[i], metric = "F1")
    data.frame(e = x$estimate, l = x$lower, u = x$upper)
  }))
  if (any(abs(m$e - picks$ca_margin) > 1e-12, na.rm = TRUE)) stop("Margins disagree with the contrasts")
  picks$ca_margin_lower <- m$l
  picks$ca_margin_upper <- m$u
  picks
}

# routing_cells.csv and routing_bands.csv.
cgr_cells_out <- function(dens, levels, level_pulses, policies) {
  out <- dens[order(dens$site, dens$plot, match(dens$level, levels)),
              c("site", "plot", "region", "level", "pdens", "frdens", "band")]
  out$level_pulses <- as.numeric(level_pulses[out$level])
  for (p in names(policies)) out[[p]] <- policies[[p]]$pick[match(out$band, policies[[p]]$band)]
  rownames(out) <- NULL
  out
}
cgr_bands_out <- function(dens, cells, scopes, levels) {
  nref_cell <- unique(cells[cells$variant == "baseline", c("site", "plot", "level", "n_ref")])
  do.call(rbind, lapply(names(scopes), function(sc) do.call(rbind, lapply(DR_BANDS$band, function(b) {
    x <- dens[dens$site %in% scopes[[sc]] & dens$band == b, , drop = FALSE]
    r <- nref_cell[paste(nref_cell$site, nref_cell$plot, nref_cell$level) %in%
                     paste(x$site, x$plot, x$level), , drop = FALSE]
    out <- data.frame(scope = sc, band = b, label = DR_BANDS$label[DR_BANDS$band == b],
                      lower = DR_BANDS$lower[DR_BANDS$band == b], upper = DR_BANDS$upper[DR_BANDS$band == b],
                      cells = nrow(x), plots = length(unique(paste(x$site, x$plot))),
                      stems = sum(r$n_ref), frdens_median = median(x$frdens),
                      frdens_min = min(x$frdens), frdens_max = max(x$frdens), stringsAsFactors = FALSE)
    for (l in levels) out[[paste0("cells_level_", l)]] <- sum(x$level == l)
    out
  }))))
}

# Every detector's F1 per level and scope against the master tables, and its
# corrected F1 against the null re-score (paper_density_routing.R's check).
cgr_master_check <- function(S, scopes, detectors, levels, ml, nd, interval_check, tol = CGR_TOL) {
  here <- do.call(rbind, lapply(names(scopes), function(sc) do.call(rbind, lapply(detectors, function(a)
    do.call(rbind, lapply(levels, function(l) {
      k <- paste(a, paste("level", l), sep = "|")
      f <- dr_estimate(S[[sc]], k, "F1"); cf <- dr_estimate(S[[sc]], k, "F1_corrected")
      data.frame(scope = sc, detector = a, level = l, F1 = f$estimate, F1_lower = f$lower,
                 F1_upper = f$upper, F1c = cf$estimate, F1c_lower = cf$lower, F1c_upper = cf$upper,
                 stringsAsFactors = FALSE)
    }))))))
  ref_master <- data.frame(scope = ml$scope, detector = ml$detector, level = ml$rung,
                           F1 = ml$estimate, F1_lower = ml$lower, F1_upper = ml$upper,
                           stringsAsFactors = FALSE)
  ref_null <- data.frame(scope = nd$scope, detector = nd$detector, level = nd$rung,
                         F1c = nd$estimate, F1c_lower = nd$lower, F1c_upper = nd$upper,
                         stringsAsFactors = FALSE)
  k <- c("scope", "detector", "level")
  cols_f1 <- if (interval_check) c("F1", "F1_lower", "F1_upper") else "F1"
  cols_c <- if (interval_check) c("F1c", "F1c_lower", "F1c_upper") else "F1c"
  bad_master <- dr_mismatch(here[c(k, cols_f1)], ref_master[c(k, cols_f1)], k, cols_f1, tol)
  bad_null <- dr_mismatch(here[c(k, cols_c)], ref_null[c(k, cols_c)], k, cols_c, tol)
  chk <- merge(merge(here, setNames(ref_master, c(k, "master_F1", "master_F1_lower", "master_F1_upper")),
                     all = TRUE),
               setNames(ref_null, c(k, "null_F1c", "null_F1c_lower", "null_F1c_upper")), all = TRUE)
  chk$max_abs_diff_F1 <- pmax(abs(chk$F1 - chk$master_F1), abs(chk$F1_lower - chk$master_F1_lower),
                              abs(chk$F1_upper - chk$master_F1_upper))
  chk$max_abs_diff_F1c <- pmax(abs(chk$F1c - chk$null_F1c), abs(chk$F1c_lower - chk$null_F1c_lower),
                               abs(chk$F1c_upper - chk$null_F1c_upper))
  chk <- chk[order(match(chk$scope, names(scopes)), match(chk$detector, detectors),
                   match(chk$level, levels)), ]
  rownames(chk) <- NULL
  list(check = chk, rows = nrow(here), bad_master = nrow(bad_master), bad_null = nrow(bad_null))
}

## ---- comparison with the paper's outputs -------------------------------------------------------------
# A table against its reference: the same columns, the same keys, numbers
# within `tol` (NA only where the reference has NA) and every other column
# identical. One row per column with the rows differing and the largest
# absolute difference.
cgr_compare <- function(here, ref, keys, tol = CGR_TOL, table = "") {
  here <- as.data.frame(here, stringsAsFactors = FALSE); ref <- as.data.frame(ref, stringsAsFactors = FALSE)
  if (!setequal(names(here), names(ref)))
    stop(table, ": columns differ: ", paste(c(setdiff(names(here), names(ref)), setdiff(names(ref), names(here))),
                                            collapse = ", "))
  kh <- do.call(paste, c(here[keys], sep = "\r")); kr <- do.call(paste, c(ref[keys], sep = "\r"))
  if (anyDuplicated(kh) || anyDuplicated(kr)) stop(table, ": keys are not unique")
  only <- length(setdiff(kh, kr)) + length(setdiff(kr, kh))
  i <- match(kr, kh)
  cols <- setdiff(names(ref), keys)
  badrow <- is.na(i)
  out <- do.call(rbind, lapply(cols, function(cc) {
    a <- here[[cc]][i]; b <- ref[[cc]]
    if (is.numeric(b) && (is.numeric(a) || is.logical(a))) {
      a <- as.numeric(a); b <- as.numeric(b)
      d <- abs(a - b)
      same <- (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & (a == b | (!is.na(d) & d <= tol)))
      md <- if (any(is.finite(d))) max(d[is.finite(d)]) else 0
    } else {
      a <- as.character(a); b <- as.character(b)
      same <- (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
      md <- NA_real_
    }
    badrow <<- badrow | !same
    data.frame(table = table, column = cc, rows = length(b), differing = sum(!same | is.na(i)),
               max_abs_diff = md, stringsAsFactors = FALSE)
  }))
  out$rows_differing <- sum(badrow)
  out$keys_unmatched <- only
  out$same_row_order <- identical(kh, kr)
  out
}

## ---- Table 7 of the manuscript ------------------------------------------------------------------------
# The manuscript joins the comparison sign to its number with a no-break space.
cgr_band_text <- function(b) {
  i <- match(b, DR_BANDS$band)
  lab <- DR_BANDS$label[i]
  lab <- paste0(toupper(substr(lab, 1, 1)), substr(lab, 2, nchar(lab)))
  rng <- ifelse(is.infinite(DR_BANDS$upper[i]), sprintf("≥ %g", DR_BANDS$lower[i]),
                ifelse(DR_BANDS$lower[i] == 0, sprintf("< %g", DR_BANDS$upper[i]),
                       sprintf("%g to < %g", DR_BANDS$lower[i], DR_BANDS$upper[i])))
  sprintf("%s (%s: %s)", lab, b, rng)
}
# The rows of Table 7 built from the picks and the contrasts: band, compute,
# pick, California F1 with the margin over the runner-up (paired interval),
# Washington F1 and corrected F1, the candidates level with the pick in
# Washington (paired F1 difference whose interval includes zero, in candidate
# order) and the pick minus the Washington best.
cgr_table7 <- function(picks, contrasts, candidates, names = CGR_NAMES) {
  nm <- function(a) unname(names[a])
  ct <- function(sc, b, r, v, m = "F1") cgr_get(contrasts, scope = sc, slice = b, policy = paste0(r, "_route"),
                                                versus = v, metric = m)
  fmt <- function(x, signed = FALSE) dr_fmt(x$estimate, x$lower, x$upper, signed)
  p <- picks[order(match(picks$band, DR_BANDS$band), match(picks$route, names(candidates))), , drop = FALSE]
  rows <- vapply(seq_len(nrow(p)), function(i) {
    r <- p$route[i]; b <- p$band[i]; a <- p$pick[i]
    margin <- if (is.na(p$ca_runner_up[i])) "—" else
      sprintf("%s over %s", fmt(ct("California", b, r, p$ca_runner_up[i]), TRUE), nm(p$ca_runner_up[i]))
    level <- Filter(function(v) { x <- ct("Washington", b, r, v); x$lower <= 0 && x$upper >= 0 },
                    setdiff(candidates[[r]], a))
    best <- if (identical(p$wa_best[i], a)) "—" else
      sprintf("%s: %s; %s", nm(p$wa_best[i]),
              dr_fmt(p$pick_minus_best[i], p$pick_minus_best_lower[i], p$pick_minus_best_upper[i], TRUE),
              dr_fmt(p$pick_minus_best_c[i], p$pick_minus_best_c_lower[i], p$pick_minus_best_c_upper[i], TRUE))
    sprintf("| %s | %s | %s | %s; %s | %s | %s | %s | %s |", cgr_band_text(b), toupper(r), nm(a),
            dr_fmt(p$ca_F1[i], p$ca_F1_lower[i], p$ca_F1_upper[i]), margin,
            dr_fmt(p$wa_F1[i], p$wa_F1_lower[i], p$wa_F1_upper[i]),
            dr_fmt(p$wa_F1c[i], p$wa_F1c_lower[i], p$wa_F1c_upper[i]),
            if (length(level)) paste(nm(level), collapse = ", ") else "none", best)
  }, character(1))
  data.frame(band = p$band, route = p$route, row = rows, stringsAsFactors = FALSE)
}
CGR_TABLE7_HEADER <- paste(
  "| Band (first-return pulses/m²) | Compute | Detector to run |",
  "California F1; margin over the runner-up | Washington F1 | Washington corrected F1 |",
  "Level with the pick in Washington | Pick minus Washington best: F1; corrected F1 |")
# The body rows of Table 7 in the manuscript's lines.
cgr_manuscript_table7 <- function(lines) {
  i <- grep("^\\*\\*Table 7\\.\\*\\*", lines)
  if (length(i) != 1) stop("Table 7 not found once in the manuscript")
  h <- i + which(startsWith(lines[(i + 1):length(lines)], "| Band"))[1]
  if (is.na(h)) stop("Table 7 has no header row")
  k <- h + 2; rows <- character()
  while (k <= length(lines) && startsWith(lines[k], "|")) { rows <- c(rows, lines[k]); k <- k + 1 }
  rows
}

## ---- the requested tables ------------------------------------------------------------------------------
# Per route, band and candidate on one scope: the candidate's F1 and corrected
# F1, and the pick minus the candidate (paired), with the pick and the scope's
# best marked.
cgr_band_table <- function(run, scores, contrasts, scope) {
  best_of <- if (scope == "Washington") run$wa_best else NULL
  do.call(rbind, lapply(names(run$candidates), function(r) do.call(rbind, lapply(DR_BANDS$band, function(b) {
    a <- run$routes[[r]]$pick[run$routes[[r]]$band == b]
    best <- if (is.null(best_of)) NA_character_ else best_of[[r]]$pick[best_of[[r]]$band == b]
    do.call(rbind, lapply(run$candidates[[r]], function(v) {
      f <- cgr_get(scores, scope = scope, policy = v, slice = b, metric = "F1")
      fc <- cgr_get(scores, scope = scope, policy = v, slice = b, metric = "F1_corrected")
      d <- cgr_get(contrasts, scope = scope, slice = b, policy = paste0(r, "_route"), versus = v, metric = "F1")
      dc <- cgr_get(contrasts, scope = scope, slice = b, policy = paste0(r, "_route"), versus = v,
                    metric = "F1_corrected")
      data.frame(scope = scope, route = r, band = b, pick = a, scope_best = best, candidate = v,
                 is_pick = v == a, is_scope_best = !is.na(best) & v == best,
                 F1 = f$estimate, F1_lower = f$lower, F1_upper = f$upper,
                 F1c = fc$estimate, F1c_lower = fc$lower, F1c_upper = fc$upper,
                 pick_minus_F1 = d$estimate, pick_minus_F1_lower = d$lower, pick_minus_F1_upper = d$upper,
                 pick_minus_F1c = dc$estimate, pick_minus_F1c_lower = dc$lower,
                 pick_minus_F1c_upper = dc$upper, stringsAsFactors = FALSE)
    }))
  }))))
}
# Every route against the policies and detectors `versus`, over every cell
# (slice "all") of each scope, with both sides' scores.
cgr_route_versus <- function(scores, contrasts, routes, versus) {
  sc <- function(scope, p, m) cgr_get(scores, scope = scope, policy = p, slice = "all", metric = m)
  do.call(rbind, lapply(unique(scores$scope), function(scope) do.call(rbind, lapply(routes, function(r)
    do.call(rbind, lapply(setdiff(versus, r), function(v) {
      d <- cgr_get(contrasts, scope = scope, slice = "all", policy = r, versus = v, metric = "F1")
      dc <- cgr_get(contrasts, scope = scope, slice = "all", policy = r, versus = v, metric = "F1_corrected")
      a <- sc(scope, r, "F1"); ac <- sc(scope, r, "F1_corrected")
      b <- sc(scope, v, "F1"); bc <- sc(scope, v, "F1_corrected")
      data.frame(scope = scope, route = r, versus = v,
                 route_F1 = a$estimate, route_F1_lower = a$lower, route_F1_upper = a$upper,
                 route_F1c = ac$estimate, route_F1c_lower = ac$lower, route_F1c_upper = ac$upper,
                 versus_F1 = b$estimate, versus_F1_lower = b$lower, versus_F1_upper = b$upper,
                 versus_F1c = bc$estimate, versus_F1c_lower = bc$lower, versus_F1c_upper = bc$upper,
                 diff_F1 = d$estimate, diff_F1_lower = d$lower, diff_F1_upper = d$upper,
                 diff_F1c = dc$estimate, diff_F1c_lower = dc$lower, diff_F1c_upper = dc$upper,
                 stringsAsFactors = FALSE)
    }))))))
}
# The candidate against every other detector on each slice of each scope.
cgr_candidate_levels <- function(scores, contrasts, label, others, slices) {
  sc <- function(scope, p, sl, m) cgr_get(scores, scope = scope, policy = p, slice = sl, metric = m)
  do.call(rbind, lapply(unique(scores$scope), function(scope) do.call(rbind, lapply(slices, function(sl)
    do.call(rbind, lapply(others, function(v) {
      a <- sc(scope, label, sl, "F1"); ac <- sc(scope, label, sl, "F1_corrected")
      b <- sc(scope, v, sl, "F1"); bc <- sc(scope, v, sl, "F1_corrected")
      d <- cgr_get(contrasts, scope = scope, slice = sl, policy = label, versus = v, metric = "F1")
      dc <- cgr_get(contrasts, scope = scope, slice = sl, policy = label, versus = v, metric = "F1_corrected")
      data.frame(scope = scope, slice = sl, n_plots = a$n_plots, candidate = label, versus = v,
                 cand_F1 = a$estimate, cand_F1_lower = a$lower, cand_F1_upper = a$upper,
                 cand_F1c = ac$estimate, cand_F1c_lower = ac$lower, cand_F1c_upper = ac$upper,
                 versus_F1 = b$estimate, versus_F1_lower = b$lower, versus_F1_upper = b$upper,
                 versus_F1c = bc$estimate, versus_F1c_lower = bc$lower, versus_F1c_upper = bc$upper,
                 diff_F1 = d$estimate, diff_F1_lower = d$lower, diff_F1_upper = d$upper,
                 diff_F1c = dc$estimate, diff_F1c_lower = dc$lower, diff_F1c_upper = dc$upper,
                 stringsAsFactors = FALSE)
    }))))))
}

## ---- markdown ------------------------------------------------------------------------------------------
cgr_para <- function(...) c(strwrap(paste(...), width = 80), "")
cgr_f <- function(e, l, u, signed = FALSE) dr_fmt(e, l, u, signed)

cgr_markdown <- function(o) {
  nm <- function(a) unname(o$names[a])
  lab <- function(p) ifelse(p %in% names(o$names), nm(p), unname(CGR_POLICY_LABEL[p]))
  lv <- function(sl) ifelse(startsWith(sl, "level "),
                            sprintf("%s (%s)", sub("^level ", "", sl), o$level_label(sub("^level ", "", sl))),
                            ifelse(sl == "all", "every level", sl))
  sc <- function(scope, p, sl, m) cgr_get(o$scores, scope = scope, policy = p, slice = sl, metric = m)
  fx <- function(x, signed = FALSE) cgr_f(x$estimate, x$lower, x$upper, signed)
  num <- function(v, signed = FALSE) gsub("-", "−", sprintf(if (signed) "%+.3f" else "%.3f", v), fixed = TRUE)
  md <- c("<!-- generated by scripts/confirm_gated_routing.R -->", "",
          sprintf("# Density routing with the gated candidate: %s", o$name), "")
  md <- c(md, cgr_para(sprintf(
    "The candidate `%s` is configuration `%s` (config_id %s) of the gated variant, added as a ninth",
    o$label, o$config, o$config_id),
    "candidate of the GPU route and a sixth of the CPU route of the paper's density routing,",
    "at the six density levels. Stock `multichm` stays a candidate. Every other part of the",
    "routing is the paper's: bands of measured first-return density, selection by the highest",
    "pooled F1 on the band's California cells, the chance-agreement counts and the master",
    "tables' plot resamples, so the candidate shares every draw with the paper's detectors and",
    "routes. Intervals are 95% percentile intervals over 1,000 plot resamples and are not",
    "adjusted for the number of contrasts. Post hoc, as the paper's routing."))
  md <- c(md, cgr_para(sprintf("Configuration: %s", o$selection)))
  md <- c(md, cgr_para(if (o$held_out)
    "Washington is held out from the configuration's selection as well as from the routes' picks." else
    paste("Washington is not held out for this configuration: its thresholds were calibrated on",
          "plots of both regions, so the Washington rows are not a held-out check of the candidate.")))

  ## harness and checks
  hc <- o$harness
  md <- c(md, "## Harness proof", "",
          cgr_para("Without the candidate the same code reproduces the paper's routing outputs.",
                   "Rows: rows of the paper's table; differing: rows whose value differs by more",
                   "than 1e-9 (numbers) or at all (text), or whose key is missing on either side."),
          "| Paper output | Rows | Columns compared | Rows differing | Largest absolute difference | Same row order |",
          "| --- | ---: | ---: | ---: | --- | --- |",
          sprintf("| %s | %d | %d | %d | %s | %s |", hc$table, hc$rows, hc$columns, hc$differing,
                  ifelse(is.na(hc$max_abs_diff), "—", sprintf("%.1e", hc$max_abs_diff)),
                  ifelse(is.na(hc$same_row_order), "—", ifelse(hc$same_row_order, "yes", "no"))), "")
  md <- c(md, cgr_para(sprintf(paste(
    "With the candidate added, the eight detectors' and the paper routes' pooled counts and",
    "scores equal the harness run in every one of the %d draws (largest absolute difference",
    "%s over %d groups)."), o$n_boot, format(o$shared_diff, digits = 3), o$shared_groups)))
  pc <- o$parity
  md <- c(md, "### Stock configuration against the paper's `multichm` cells", "",
          cgr_para("The gated files' `stock` rows against the paper's chance-agreement cells of",
                   "`multichm`, cell by cell; null rows compare n_det0, TP0 and tp_core0 with the",
                   "null variant's n_det, TP and tp_core."),
          "| Level | Variant | Cells | Missing | Largest absolute difference (n_ref, n_det, TP, tp_core) | Cells differing |",
          "| --- | --- | ---: | ---: | --- | ---: |")
  pa <- aggregate(cbind(cells, missing, differing) ~ level + variant, data = pc, FUN = max)
  pm <- aggregate(max_abs_diff ~ level + variant, pc, max)
  pa <- merge(pa, pm)
  pa <- pa[order(match(pa$level, o$levels), pa$variant), ]
  md <- c(md, sprintf("| %s | %s | %d | %d | %.1e | %d |", pa$level, pa$variant, pa$cells, pa$missing,
                      pa$max_abs_diff, pa$differing), "")
  da <- o$density
  ds <- do.call(rbind, lapply(o$levels, function(l) {
    x <- da[da$level == l, , drop = FALSE]
    data.frame(level = l, cells = nrow(x), fr = max(abs(x$frdens_diff)), pd = max(abs(x$pdens_diff)),
               band = sum(!x$band_agrees), stringsAsFactors = FALSE)
  }))
  md <- c(md, "### Densities of the gated files against the routing's", "",
          cgr_para("The routing bands every cell by the clip manifest's first-return density; the",
                   "gated files carry their own copy, compared here and not used."),
          "| Level | Cells | Largest absolute difference, first-return density | Largest absolute difference, all-return density | Cells banded differently |",
          "| --- | ---: | --- | --- | ---: |",
          sprintf("| %s | %d | %.1e | %.1e | %d |", ds$level, ds$cells, ds$fr, ds$pd, ds$band), "")
  sl <- o$selection_check
  top <- head(sl, 6)
  me <- sl[sl$config == o$config, , drop = FALSE]
  md <- c(md, "### The configuration's rank on the California native cells", "",
          cgr_para(sprintf(paste("Pooled corrected F1 of every configuration of the gated files on the",
                                 "California cells at native density (%d plots), ties to the smallest",
                                 "config_id. `%s` ranks %d of %d."),
                         sl$plots[1], o$config, me$rank, nrow(sl))),
          "| Rank | Configuration | config_id | F1 | Null F1 | Corrected F1 |",
          "| ---: | --- | ---: | --- | --- | --- |",
          sprintf("| %d | `%s` | %d | %.4f | %.4f | %.4f |", c(top$rank, if (me$rank > 6) me$rank),
                  c(top$config, if (me$rank > 6) me$config), c(top$config_id, if (me$rank > 6) me$config_id),
                  c(top$F1, if (me$rank > 6) me$F1), c(top$F1_null, if (me$rank > 6) me$F1_null),
                  c(top$F1_corrected, if (me$rank > 6) me$F1_corrected)), "")

  ## bands
  bt <- o$bands
  md <- c(md, "## Bands of measured first-return density", "",
          paste0("| Band | Pulses/m² | Scope | Cells | Plots | Stems | Median pulses/m² [range] | ",
                 paste(sprintf("Cells at %s", o$level_label(o$levels)), collapse = " | "), " |"),
          paste0("| --- | --- | --- | ---: | ---: | ---: | --- |", strrep(" ---: |", length(o$levels))),
          sprintf("| %s (%s) | %s | %s | %d | %d | %s | %.1f [%.2f, %.2f] | %s |", bt$band, bt$label,
                  ifelse(is.infinite(bt$upper), sprintf("≥ %g", bt$lower),
                         ifelse(bt$lower == 0, sprintf("< %g", bt$upper),
                                sprintf("%g to < %g", bt$lower, bt$upper))),
                  bt$scope, bt$cells, bt$plots, formatC(bt$stems, big.mark = ",", format = "d"),
                  bt$frdens_median, bt$frdens_min, bt$frdens_max,
                  apply(bt[paste0("cells_level_", o$levels)], 1, paste, collapse = " | ")), "")

  ## decision table
  md <- c(md, "## Decision table and held-out check", "",
          cgr_para("In the format of the paper's Table 7, with the candidate in both candidate sets.",
                   "Margin: the pick's paired F1 difference to the runner-up on the band's",
                   "California cells. Level with the pick: the candidates whose paired F1",
                   "difference to the pick on the Washington cells has an interval that includes",
                   "zero. Pick minus Washington best: paired differences, F1; corrected F1, to the",
                   "candidate with the highest F1 on the Washington cells (chosen on those cells,",
                   "descriptive); — when the pick is that candidate."),
          CGR_TABLE7_HEADER, "| --- | --- | --- | --- | --- | --- | --- | --- |", o$table7$row, "")
  pk <- o$picks
  f4 <- function(e, l, u) gsub("-", "−", sprintf("%+.4f [%+.4f, %+.4f]", e, l, u), fixed = TRUE)
  md <- c(md, "## Picks on the California cells", "",
          cgr_para("Margin: pick minus runner-up on the band's California cells, paired, to four",
                   "decimals."),
          "| Band | Route | Paper's pick | Pick | California F1 | Runner-up | Runner-up F1 | Margin, paired |",
          "| --- | --- | --- | --- | --- | --- | --- | --- |",
          sprintf("| %s | %s | %s | %s | %s | %s | %s | %s |", pk$band, toupper(pk$route),
                  nm(o$paper_picks$pick[match(paste(pk$route, pk$band), paste(o$paper_picks$route, o$paper_picks$band))]),
                  nm(pk$pick), cgr_f(pk$ca_F1, pk$ca_F1_lower, pk$ca_F1_upper), nm(pk$ca_runner_up),
                  sprintf("%.4f", pk$ca_runner_up_F1), f4(pk$ca_margin, pk$ca_margin_lower, pk$ca_margin_upper)), "")
  ch <- o$choices
  md <- c(md, "Choices made once for every density, by the same rule:", "",
          "| Choice | Candidates | Selected on | Pick | Its F1 | Runner-up (margin) |",
          "| --- | --- | --- | --- | --- | --- |",
          sprintf("| %s | %s | %s | %s | %s | %s (%s) |", sub(", (GPU|CPU)$", "", CGR_POLICY_LABEL[ch$policy]),
                  toupper(sub("_.*", "", ch$policy)), ch$selected_on, nm(ch$pick), num(ch$value),
                  nm(ch$runner_up), num(ch$margin, TRUE)), "")

  ## every candidate by band
  for (scope in c("Washington", "California", "five sites")) {
    cand <- o$run$candidates$gpu
    mark <- function(a) paste(c(
      if (a %in% o$run$routes$gpu$pick) paste0("GPU ", paste(o$run$routes$gpu$band[o$run$routes$gpu$pick == a], collapse = "")),
      if (a %in% o$run$routes$cpu$pick) paste0("CPU ", paste(o$run$routes$cpu$band[o$run$routes$cpu$pick == a], collapse = ""))),
      collapse = ", ")
    rows <- vapply(cand, function(a) paste(vapply(DR_BANDS$band, function(b)
      paste(fx(sc(scope, a, b, "F1")), fx(sc(scope, a, b, "F1_corrected")), sep = " | "), character(1)),
      collapse = " | "), character(1))
    md <- c(md, sprintf("## Every candidate by band, %s (%s)", scope, CGR_ROLE[[scope]]), "",
            "| Detector | Picked in | A: F1 | A: corrected F1 | B: F1 | B: corrected F1 | C: F1 | C: corrected F1 |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
            sprintf("| %s | %s | %s |", nm(cand), vapply(cand, mark, character(1)), rows), "")
  }
  wb <- o$wa_bands
  md <- c(md, "## Washington: each pick against every other candidate of its band", "",
          cgr_para("Paired differences, pick minus candidate, on the band's Washington cells; the",
                   "Washington best (highest F1 there, descriptive) is marked."),
          "| Band | Route | Pick | Versus | Its F1 | Its corrected F1 | Pick minus candidate, F1 | Pick minus candidate, corrected F1 |",
          "| --- | --- | --- | --- | --- | --- | --- | --- |")
  w <- wb[!wb$is_pick, , drop = FALSE]
  w <- w[order(match(w$band, DR_BANDS$band), match(w$route, c("gpu", "cpu"))), , drop = FALSE]
  md <- c(md, sprintf("| %s | %s | %s | %s%s | %s | %s | %s | %s |", w$band, toupper(w$route), nm(w$pick),
                      nm(w$candidate), ifelse(w$is_scope_best, " (Washington best)", ""),
                      cgr_f(w$F1, w$F1_lower, w$F1_upper), cgr_f(w$F1c, w$F1c_lower, w$F1c_upper),
                      cgr_f(w$pick_minus_F1, w$pick_minus_F1_lower, w$pick_minus_F1_upper, TRUE),
                      cgr_f(w$pick_minus_F1c, w$pick_minus_F1c_lower, w$pick_minus_F1c_upper, TRUE)), "")
  pol <- c("gpu_route", "cpu_route", "paper_gpu_route", "paper_cpu_route", "gpu_native", "cpu_native",
           "gpu_single", "cpu_single", "gpu_wa_best", "cpu_wa_best", o$run$candidates$gpu)
  md <- c(md, "## Every cell pooled: routes and detectors", "",
          "| Policy or detector | Five sites, F1 | Five sites, corrected F1 | California, F1 | California, corrected F1 | Washington, F1 | Washington, corrected F1 |",
          "| --- | --- | --- | --- | --- | --- | --- |",
          sprintf("| %s | %s |", lab(pol), vapply(pol, function(p) paste(unlist(lapply(names(o$scopes),
            function(s) c(fx(sc(s, p, "all", "F1")), fx(sc(s, p, "all", "F1_corrected"))))), collapse = " | "),
            character(1))), "")
  rv <- o$route_versus
  for (r in c("gpu_route", "cpu_route")) {
    x <- rv[rv$route == r, , drop = FALSE]
    vs <- unique(x$versus)
    md <- c(md, sprintf("## %s with the candidate against other choices, every cell", CGR_POLICY_LABEL[[r]]), "",
            cgr_para("Paired differences, route minus the policy or detector run at every density."),
            "| Versus | Five sites, F1 | Five sites, corrected F1 | California, F1 | California, corrected F1 | Washington, F1 | Washington, corrected F1 |",
            "| --- | --- | --- | --- | --- | --- | --- |",
            sprintf("| %s | %s |", lab(vs), vapply(vs, function(v) paste(unlist(lapply(names(o$scopes), function(s) {
              z <- x[x$scope == s & x$versus == v, ]
              c(cgr_f(z$diff_F1, z$diff_F1_lower, z$diff_F1_upper, TRUE),
                cgr_f(z$diff_F1c, z$diff_F1c_lower, z$diff_F1c_upper, TRUE))
            })), collapse = " | "), character(1))), "")
  }
  cl <- o$cand_levels
  for (s in names(o$scopes)) {
    x <- cl[cl$scope == s, , drop = FALSE]
    md <- c(md, sprintf("## The candidate against each other detector by level, %s", s), "",
            cgr_para(sprintf(paste("The candidate's scores, the other detector's, and the candidate minus",
                                   "the other detector (paired), per density level and over every level.",
                                   "A level is named by its all-return target in points/m², with the",
                                   "five-site median of its measured first-return density in pulses/m²",
                                   "in brackets. Plots: %s."), paste(unique(x$n_plots), collapse = ", "))),
            "| Level | Candidate F1 | Candidate corrected F1 | Versus | Its F1 | Its corrected F1 | Candidate minus it, F1 | Candidate minus it, corrected F1 |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
            sprintf("| %s | %s | %s | %s | %s | %s | %s | %s |", lv(x$slice),
                    cgr_f(x$cand_F1, x$cand_F1_lower, x$cand_F1_upper),
                    cgr_f(x$cand_F1c, x$cand_F1c_lower, x$cand_F1c_upper), nm(x$versus),
                    cgr_f(x$versus_F1, x$versus_F1_lower, x$versus_F1_upper),
                    cgr_f(x$versus_F1c, x$versus_F1c_lower, x$versus_F1c_upper),
                    cgr_f(x$diff_F1, x$diff_F1_lower, x$diff_F1_upper, TRUE),
                    cgr_f(x$diff_F1c, x$diff_F1c_lower, x$diff_F1c_upper, TRUE)), "")
  }
  c(md, "## Reproduce", "", "```sh", o$command, "```")
}

## ---- main ----------------------------------------------------------------------------------------------
run_main <- function(argv = commandArgs(TRUE)) {
  A <- cgr_args(argv)
  arg <- function(k, default) if (is.null(A[[k]]) || !nzchar(A[[k]])) default else A[[k]]
  work <- file.path(.ROOT, "work")
  LIB <- normalizePath(arg("ROUTING_LIB", file.path(work, "paper-novelty-checkout", "scripts",
                                                    "density_routing_lib.R")), mustWork = FALSE)
  if (!file.exists(LIB)) stop("No routing library at ", LIB, " (set ROUTING_LIB=)", call. = FALSE)
  source(LIB)
  d <- normalizePath(arg("PAPER_RUNS", file.path(work, "paper_runs")), mustWork = TRUE)
  POP <- arg("POP", "adopted")
  ROOT <- frozen_root(d, A[["FROZEN_ROOT"]])
  MASTER <- arg("MASTER", file.path(d, "master_tables"))
  REF <- arg("PAPER_ROUTING", file.path(d, "density_routing"))
  MS <- arg("MANUSCRIPT", file.path(work, "paper-novelty-checkout", "paper", "manuscript.md"))
  GATED <- strsplit(arg("GATED_CELLS", paste(
    file.path(work, "multichm_gated_runs", "neon", "multichm_gated", "cells.csv"),
    file.path(work, "multichm_gated_confirmation", "ql2", "cells.csv"), sep = ",")), ",", fixed = TRUE)[[1]]
  CONFIG <- arg("CONFIG", "")
  if (!nzchar(CONFIG) || CONFIG == "stock") stop("CONFIG= names a gated configuration other than stock",
                                                 call. = FALSE)
  LABEL <- arg("LABEL", "multichm_gated")
  NAME <- arg("NAME", CONFIG)
  HELD <- tolower(arg("HELD_OUT", ""))
  if (!HELD %in% c("yes", "no")) stop("HELD_OUT= is yes or no", call. = FALSE)
  HELD <- HELD == "yes"
  SELECTION <- arg("SELECTION", if (HELD)
    "selected on the California plots alone (highest corrected F1 at native density)." else
      "calibrated on plots of both regions (not held out).")
  N_BOOT <- as.integer(arg("N_BOOT", MT_N_BOOT))
  SEED <- as.integer(arg("SEED", MT_SEED))
  RUNG_JOBS <- strsplit(arg("RUNG_JOBS", paste0(file.path(dirname(d), "paper_runs_ql2"), ":",
                                                file.path(dirname(d), "neon", "frozen_2021_ql2"))),
                        ",", fixed = TRUE)[[1]]
  lib_root <- dirname(dirname(LIB))
  OUT <- cgr_check_out(arg("OUT", file.path(work, "multichm_gated_confirmation", "routing", NAME)),
                       c(if (!identical(cgr_resolve(lib_root), cgr_resolve(.ROOT))) lib_root, d, MASTER, REF,
                         ROOT))
  GPU <- DR_CANDIDATES$gpu
  if (LABEL %in% GPU) stop("LABEL= must differ from the paper's detectors", call. = FALSE)
  SCOPES <- c(list(`five sites` = unlist(MT_REGIONS, use.names = FALSE)), MT_REGIONS)
  if (!frozen_sealed(ROOT)) stop("No sealed frozen root at ", ROOT)
  dir.create(file.path(OUT, "harness"), recursive = TRUE, showWarnings = FALSE)
  t0 <- Sys.time()

  ## inputs: one part per frozen root (paper_density_routing.R)
  parts <- list(list(dir = d, root = ROOT, rungs = MT_RUNGS))
  for (x in RUNG_JOBS) {
    p <- strsplit(x, ":", fixed = TRUE)[[1]]
    if (length(p) != 2) stop("RUNG_JOBS entries are <job dir>:<root>")
    if (!frozen_sealed(p[2])) stop("No sealed frozen root at ", p[2], " (set RUNG_JOBS=)")
    if (!identical(frozen_sha256(file.path(p[2], "population.csv")),
                   frozen_sha256(file.path(ROOT, "population.csv"))))
      stop("Root ", p[2], " declares a different population from ", ROOT)
    rr <- as.character(frozen_root_rungs(p[2]))
    if (any(rr %in% MT_RUNGS)) stop("Root ", p[2], " repeats levels of ", ROOT)
    parts[[length(parts) + 1]] <- list(dir = p[1], root = p[2], rungs = rr)
  }
  LEVELS <- c("native", as.character(sort(unique(as.numeric(c(
    MT_RUNGS[-1], unlist(lapply(parts[-1], `[[`, "rungs"))))), decreasing = TRUE)))
  null_file <- function(part) file.path(part$dir, "sensitivity", "null_cells.csv")
  read_part <- function(part) {
    f <- null_file(part)
    if (!file.exists(f)) stop("No chance-agreement cells at ", f)
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x <- x[x$rung %in% part$rungs & x$detector %in% GPU, , drop = FALSE]
    cm <- frozen_clip_manifest(part$root)
    cm <- cm[cm$rung %in% part$rungs, c("site", "plot", "rung", "status", "pdens", "frdens")]
    list(cells = x, manifest = cm)
  }
  raw <- lapply(parts, read_part)
  cells <- do.call(rbind, lapply(raw, `[[`, "cells"))
  manifest <- do.call(rbind, lapply(raw, `[[`, "manifest"))
  names(cells)[names(cells) == "rung"] <- "level"
  names(manifest)[names(manifest) == "rung"] <- "level"
  contract <- jsonlite::read_json(file.path(MASTER, "master_contract.json"), simplifyVector = TRUE)
  if (!identical(contract$population, POP))
    stop("The master tables in ", MASTER, " are for population ", contract$population)
  if (!identical(contract$clip_manifest_sha256, frozen_root_id(ROOT)))
    stop("The master tables were built on another root than ", ROOT)
  for (part in parts[-1]) {
    rr <- contract$rung_roots
    hit <- if (is.null(rr)) integer() else
      which(vapply(seq_len(NROW(rr)), function(i) identical(as.character(unlist(rr$rungs[i])), part$rungs),
                   logical(1)))
    if (length(hit) != 1 || !identical(rr$clip_manifest_sha256[hit], frozen_root_id(part$root)))
      stop("The master tables do not record the root ", part$root)
  }
  interval_check <- N_BOOT == contract$n_boot && SEED == contract$seed
  if (!interval_check) stop("N_BOOT and SEED must be the master tables' (", contract$n_boot, ", ",
                            contract$seed, ") for the candidate to share their draws")

  ## cells, population and bands
  pop <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
  inpop <- pop[pop[[paste0("in_", POP)]], , drop = FALSE]
  plots <- sort(unique(paste(inpop$site, inpop$plotID, sep = "::")))
  if (!setequal(unique(paste(cells$site, cells$plot, sep = "::")), plots))
    stop("The chance-agreement cells do not cover the declared ", POP, " population")
  if (!setequal(unique(cells$variant), c("baseline", "null"))) stop("Expected baseline and null variants")
  grid <- expand.grid(variant = c("baseline", "null"), plot = plots, level = LEVELS, detector = GPU,
                      stringsAsFactors = FALSE)
  have <- paste(cells$variant, paste(cells$site, cells$plot, sep = "::"), cells$level, cells$detector)
  want <- paste(grid$variant, grid$plot, grid$level, grid$detector)
  if (anyDuplicated(have)) stop("Duplicate chance-agreement cells")
  if (!setequal(have, want)) stop("Incomplete chance-agreement cells")
  nref <- tapply(cells$n_ref, paste(cells$site, cells$plot), function(v) length(unique(v)))
  if (any(nref != 1)) stop("A plot's reference differs between detectors, variants or levels")
  dens <- merge(unique(cells[c("site", "plot", "level")]), manifest, by = c("site", "plot", "level"),
                all.x = TRUE)
  if (anyNA(dens$status) || any(dens$status != "ok"))
    stop("A scored cell is not an ok cell of its root's clip manifest")
  dens$band <- dr_band(dens$frdens)
  dens$region <- ifelse(dens$site %in% MT_REGIONS$California, "California",
                        ifelse(dens$site %in% MT_REGIONS$Washington, "Washington", NA))
  if (anyNA(dens$region)) stop("A site belongs to no region")
  cells <- merge(cells, dens[c("site", "plot", "level", "frdens", "band")], by = c("site", "plot", "level"))
  cells <- cells[c("variant", "site", "plot", "level", "detector", "frdens", "band", CGR_COUNTS)]
  level_pulses <- tapply(dens$frdens, dens$level, median)[LEVELS]
  rd <- read.csv(file.path(MASTER, "rung_density.csv"), stringsAsFactors = FALSE,
                 colClasses = c(rung = "character"))
  rd <- rd[rd$scope == "five sites", , drop = FALSE]
  rd_pulses <- rd$pulses_median[match(LEVELS, rd$rung)]
  if (anyNA(rd_pulses) || any(abs(rd_pulses - level_pulses) > CGR_TOL))
    stop("Level densities differ from the master tables' rung_density.csv")
  level_label <- function(l) sprintf("%.1f", level_pulses[l])
  W <- mt_plot_weights(sub("::.*$", "", plots), sub("^[^:]*::", "", plots), N_BOOT, SEED)
  cat(sprintf("[inputs] %d plots, %d levels, %d cells x detectors x variants\n", length(plots),
              length(LEVELS), nrow(cells)))

  ## the gated candidate's cells
  g <- do.call(rbind, lapply(GATED, function(f) {
    if (!file.exists(f)) stop("No gated cells at ", f)
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x$source <- f
    x
  }))
  lev_src <- unique(g[c("rung", "source")])
  if (anyDuplicated(lev_src$rung)) stop("A level is in more than one gated cells file")
  g <- g[paste(g$site, g$plot, sep = "::") %in% plots, , drop = FALSE]
  if (!setequal(unique(g$rung), LEVELS)) stop("The gated cells hold levels ", paste(unique(g$rung), collapse = ","),
                                              ", the routing ", paste(LEVELS, collapse = ","))
  config_id <- unique(g$config_id[g$config == CONFIG])
  if (length(config_id) != 1) stop("Configuration ", CONFIG, " has no single config_id")
  cand <- cgr_gated_rows(g, CONFIG, LABEL)
  stock <- cgr_gated_rows(g, "stock", "multichm")
  key3 <- function(z) paste(z$site, z$plot, z$level)
  if (!setequal(key3(cand), key3(dens)) || nrow(cand) != 2 * nrow(dens))
    stop("The candidate's cells are not the routing's cells")
  paper_m <- cells[cells$detector == "multichm", c("variant", "site", "plot", "level", CGR_COUNTS)]
  parity <- cgr_cell_parity(stock, paper_m)
  write.csv(parity, file.path(OUT, "stock_parity.csv"), row.names = FALSE)
  if (any(parity$differing > 0)) stop("The gated stock cells differ from the paper's multichm cells")
  pref <- unique(cells[c("site", "plot", "n_ref")])          # one per plot (checked above)
  if (any(cand$n_ref != pref$n_ref[match(paste(cand$site, cand$plot), paste(pref$site, pref$plot))]))
    stop("The candidate's reference differs from the paper's")
  gd <- unique(g[g$config == CONFIG, c("site", "plot", "rung", "pdens", "frdens")])
  names(gd)[names(gd) == "rung"] <- "level"
  density <- cgr_density_agreement(gd, dens, dr_band)
  write.csv(density, file.path(OUT, "density_agreement.csv"), row.names = FALSE)
  cand <- merge(cand, dens[c("site", "plot", "level", "frdens", "band")], by = c("site", "plot", "level"))
  cand <- cand[names(cells)]
  sel_check <- cgr_selection(g, MT_REGIONS$California, "native", plots)
  write.csv(sel_check, file.path(OUT, "selection_check.csv"), row.names = FALSE)
  cat(sprintf("[candidate] %s = %s (config_id %d); stock parity: %d count comparisons, 0 differing;",
              LABEL, CONFIG, config_id, nrow(parity)),
      sprintf("band disagreements with the gated files: %d; California native rank %d of %d\n",
              sum(!density$band_agrees), sel_check$rank[sel_check$config == CONFIG], nrow(sel_check)))

  ## harness: the paper's routing without the candidate
  run0 <- cgr_route(cells, W, SCOPES, DR_CANDIDATES)
  ml <- read.csv(file.path(MASTER, "master_long.csv"), stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  ml <- ml[ml$table == "nominal box" & ml$population == POP & ml$metric == "F1" &
             ml$status == "included" & ml$scope %in% names(SCOPES) & ml$detector %in% GPU, , drop = FALSE]
  nd <- do.call(rbind, lapply(parts, function(part) {
    f <- file.path(part$dir, "sensitivity", "null_delta.csv")
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x[x$rung %in% part$rungs & x$stratum == "all" & x$metric == "F1_scaled" &
        x$scope %in% names(SCOPES) & x$detector %in% GPU, , drop = FALSE]
  }))
  mc <- cgr_master_check(run0$S, SCOPES, GPU, LEVELS, ml, nd, interval_check)
  write.csv(mc$check, file.path(OUT, "routing_check.csv"), row.names = FALSE)
  h_cells <- cgr_cells_out(dens, LEVELS, level_pulses, run0$policies)
  h_bands <- cgr_bands_out(dens, cells, SCOPES, LEVELS)
  h_scores <- cgr_scores(run0, dens, SCOPES)
  SLICES <- c(DR_BANDS$band, "all")
  h_contrasts <- cgr_contrasts(run0$S, SCOPES, cgr_pairs(GPU), SLICES)
  h_picks <- cgr_picks(run0, h_scores, h_contrasts)
  h_t7 <- cgr_table7(h_picks, h_contrasts, DR_CANDIDATES)
  for (nmx in c("cells", "bands", "picks", "scores", "contrasts"))
    write.csv(get(paste0("h_", nmx)), file.path(OUT, "harness", paste0("routing_", nmx, ".csv")), row.names = FALSE)
  writeLines(c(CGR_TABLE7_HEADER, "| --- | --- | --- | --- | --- | --- | --- | --- |", h_t7$row),
             file.path(OUT, "harness", "table7_rows.md"))
  rd_ref <- function(f) read.csv(file.path(REF, f), stringsAsFactors = FALSE,
                                 colClasses = c(level = "character"))
  rd_ref2 <- function(f) read.csv(file.path(REF, f), stringsAsFactors = FALSE)
  cmp <- rbind(
    cgr_compare(h_cells, rd_ref("routing_cells.csv"), c("site", "plot", "level"), table = "routing_cells.csv"),
    cgr_compare(h_bands, rd_ref2("routing_bands.csv"), c("scope", "band"), table = "routing_bands.csv"),
    cgr_compare(h_picks, rd_ref2("routing_picks.csv"), c("route", "band"), table = "routing_picks.csv"),
    cgr_compare(h_scores, rd_ref2("routing_scores.csv"), c("scope", "policy", "slice", "metric"),
                table = "routing_scores.csv"),
    cgr_compare(h_contrasts, rd_ref2("routing_contrasts.csv"), c("scope", "slice", "policy", "versus", "metric"),
                table = "routing_contrasts.csv"))
  hc <- do.call(rbind, lapply(split(cmp, cmp$table), function(x) data.frame(
    table = x$table[1], rows = x$rows[1], columns = nrow(x), differing = x$rows_differing[1] + x$keys_unmatched[1],
    max_abs_diff = suppressWarnings(max(x$max_abs_diff, na.rm = TRUE)), same_row_order = x$same_row_order[1],
    stringsAsFactors = FALSE)))
  hc <- hc[match(c("routing_cells.csv", "routing_bands.csv", "routing_picks.csv", "routing_scores.csv",
                   "routing_contrasts.csv"), hc$table), ]
  mcx <- max(c(mc$check$max_abs_diff_F1, mc$check$max_abs_diff_F1c), na.rm = TRUE)
  hc <- rbind(hc, data.frame(table = "master tables (F1) and null re-score (corrected F1), with intervals",
                             rows = mc$rows, columns = 6, differing = mc$bad_master + mc$bad_null,
                             max_abs_diff = mcx, same_row_order = NA))
  t7_ok <- NA
  if (file.exists(MS)) {
    ms_rows <- cgr_manuscript_table7(readLines(MS, encoding = "UTF-8", warn = FALSE))
    t7_diff <- if (length(ms_rows) != nrow(h_t7)) max(length(ms_rows), nrow(h_t7)) else sum(ms_rows != h_t7$row)
    t7_ok <- t7_diff == 0
    hc <- rbind(hc, data.frame(table = "manuscript Table 7, text of every body row", rows = length(ms_rows),
                               columns = 8, differing = t7_diff, max_abs_diff = NA, same_row_order = NA))
    if (!t7_ok) {
      writeLines(c("manuscript:", ms_rows, "here:", h_t7$row), file.path(OUT, "harness", "table7_mismatch.txt"))
    }
  }
  write.csv(cmp, file.path(OUT, "harness_check.csv"), row.names = FALSE)
  print(hc, row.names = FALSE)
  if (any(hc$differing > 0)) stop("The harness does not reproduce the paper's routing; see ", OUT, "/harness_check.csv")
  cat("[harness] the paper's routing is reproduced\n")

  ## the routing with the candidate
  CAND <- list(gpu = c(GPU, LABEL), cpu = c(DR_CANDIDATES$cpu, LABEL))
  extra <- list(paper_gpu_route = run0$routes$gpu, paper_cpu_route = run0$routes$cpu)
  run1 <- cgr_route(rbind(cells, cand), W, SCOPES, CAND, extra)
  # Shared draws: every group of the harness run (paper detectors and routes)
  # has the same counts and draws in the run with the candidate.
  map <- c(setNames(GPU, GPU), gpu_route = "paper_gpu_route", cpu_route = "paper_cpu_route")
  shared <- unlist(lapply(names(SCOPES), function(sc) {
    s0 <- run0$S[[sc]]; s1 <- run1$S[[sc]]
    gr <- s0$groups[sub("^[^|]*\\|([^|]*)\\|.*$", "\\1", s0$groups) %in% names(map)]
    g1 <- vapply(strsplit(gr, "|", fixed = TRUE), function(z) paste(z[1], map[[z[2]]], z[3], sep = "|"),
                 character(1))
    if (anyNA(match(g1, s1$groups))) stop("A harness group is missing from the run with the candidate")
    c(unlist(lapply(c("recall", "precision", "F1"), function(m)
      abs(s0$draws[[m]][, gr] - s1$draws[[m]][, g1]))),
      unlist(lapply(c("n_ref", "n_det", "TP", "recall", "precision", "F1"), function(m)
        abs(s0$estimate[[m]][match(gr, s0$groups)] - s1$estimate[[m]][match(g1, s1$groups)]))))
  }))
  shared_diff <- max(shared, na.rm = TRUE)
  shared_groups <- sum(vapply(names(SCOPES), function(sc) sum(sub("^[^|]*\\|([^|]*)\\|.*$", "\\1",
                                                                     run0$S[[sc]]$groups) %in% names(map)), numeric(1)))
  if (shared_diff > 0) stop("Adding the candidate changed the paper's scores")
  scores <- cgr_scores(run1, dens, SCOPES)
  more <- data.frame(policy = c("gpu_route", "gpu_route", "cpu_route", "cpu_route"),
                     versus = c("paper_gpu_route", "paper_cpu_route", "paper_gpu_route", "paper_cpu_route"),
                     stringsAsFactors = FALSE)
  contrasts <- cgr_contrasts(run1$S, SCOPES, cgr_pairs(CAND$gpu, more), SLICES)
  picks <- cgr_margins(cgr_picks(run1, scores, contrasts), contrasts)
  t7 <- cgr_table7(picks, contrasts, CAND, c(CGR_NAMES, setNames(sprintf("`%s`", LABEL), LABEL)))
  others <- setdiff(CAND$gpu, LABEL)
  LSLICES <- c(paste("level", LEVELS), "all")
  cand_ct <- cgr_contrasts(run1$S, SCOPES, data.frame(policy = LABEL, versus = others, stringsAsFactors = FALSE),
                           LSLICES)
  cand_levels <- cgr_candidate_levels(scores, cand_ct, LABEL, others, LSLICES)
  wa_bands <- rbind(cgr_band_table(run1, scores, contrasts, "Washington"),
                    cgr_band_table(run1, scores, contrasts, "California"))
  route_versus <- cgr_route_versus(scores, contrasts, c("gpu_route", "cpu_route"),
                                   c("paper_gpu_route", "paper_cpu_route", "forestformer3d", LABEL, "multichm",
                                     "chm_vwf"))
  cells_out <- cgr_cells_out(dens, LEVELS, level_pulses, run1$policies)
  choices <- do.call(rbind, c(
    lapply(names(CAND), function(r) cbind(policy = paste0(r, "_native"), selected_on = "California, native level",
                                          run1$native[[r]]$choice[c("pick", "value", "runner_up", "runner_up_value",
                                                                    "margin")])),
    lapply(names(CAND), function(r) cbind(policy = paste0(r, "_single"), selected_on = "California, all cells",
                                          run1$single[[r]]$choice[c("pick", "value", "runner_up", "runner_up_value",
                                                                    "margin")]))))
  write.csv(cells_out, file.path(OUT, "routing_cells.csv"), row.names = FALSE)
  write.csv(h_bands, file.path(OUT, "routing_bands.csv"), row.names = FALSE)
  write.csv(picks, file.path(OUT, "routing_picks.csv"), row.names = FALSE)
  write.csv(scores, file.path(OUT, "routing_scores.csv"), row.names = FALSE)
  write.csv(contrasts, file.path(OUT, "routing_contrasts.csv"), row.names = FALSE)
  write.csv(wa_bands, file.path(OUT, "washington_bands.csv"), row.names = FALSE)
  write.csv(route_versus, file.path(OUT, "route_versus.csv"), row.names = FALSE)
  write.csv(cand_levels, file.path(OUT, "candidate_levels.csv"), row.names = FALSE)
  write.csv(t7, file.path(OUT, "table7.csv"), row.names = FALSE)
  cmd <- paste(c("Rscript scripts/confirm_gated_routing.R", sprintf("%s=%s", names(A), unlist(A))), collapse = " ")
  md <- cgr_markdown(list(
    name = NAME, label = LABEL, config = CONFIG, config_id = config_id, held_out = HELD, selection = SELECTION,
    names = c(CGR_NAMES, setNames(sprintf("`%s`", LABEL), LABEL)), levels = LEVELS, level_label = level_label,
    harness = hc, n_boot = N_BOOT, shared_diff = shared_diff, shared_groups = shared_groups, parity = parity,
    density = density, selection_check = sel_check, bands = h_bands, table7 = t7, picks = picks,
    paper_picks = h_picks, choices = choices, run = run1, scores = scores, wa_bands = wa_bands[
      wa_bands$scope == "Washington", ], scopes = SCOPES, route_versus = route_versus, cand_levels = cand_levels,
    command = cmd))
  writeLines(md, file.path(OUT, "confirm_gated_routing.md"))
  inputs <- c(GATED, unlist(lapply(parts, function(p) c(null_file(p), file.path(p$dir, "sensitivity", "null_delta.csv"),
                                                         file.path(p$root, "clip_manifest.csv")))),
              file.path(MASTER, c("master_long.csv", "master_contract.json", "rung_density.csv")),
              file.path(ROOT, "population.csv"),
              file.path(REF, paste0("routing_", c("cells", "bands", "picks", "scores", "contrasts"), ".csv")),
              if (file.exists(MS)) MS)
  jsonlite::write_json(list(
    post_hoc = TRUE, name = NAME, label = LABEL, config = CONFIG, config_id = config_id,
    washington_held_out_from_configuration = HELD, selection = SELECTION, population = POP, n_boot = N_BOOT,
    seed = SEED, levels = LEVELS, candidates = CAND,
    picks = lapply(run1$policies, function(p) setNames(as.list(p$pick), p$band)),
    harness = list(reproduced = TRUE, tables = hc, table7_text = t7_ok, shared_draws_max_abs_diff = shared_diff),
    inputs = data.frame(input = inputs, sha256 = vapply(inputs, frozen_sha256, character(1)), row.names = NULL),
    routing_lib = list(path = LIB, md5 = unname(tools::md5sum(LIB))),
    code_md5 = unname(tools::md5sum(c(.find("confirm_gated_routing.R"), .find("master_tables_lib.R"))))),
    file.path(OUT, "routing_contract.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
  print(picks[c("route", "band", "pick", "ca_F1", "ca_runner_up", "ca_margin", "ca_margin_lower", "ca_margin_upper",
                "wa_F1", "wa_best", "pick_minus_best")], row.names = FALSE, digits = 3)
  cat(sprintf("[done] %s in %.1f min -> %s\n", NAME, as.numeric(difftime(Sys.time(), t0, units = "mins")), OUT))
  invisible()
}

if (sys.nframe() == 0L) run_main()
