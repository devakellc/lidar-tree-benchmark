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

# Check R5 of the gated multichm confirmation protocol
# (docs/multichm-gated-confirmation-protocol.md): inside the censused subplots
# at native density, are the deeper-layer peaks the first-return share gate
# removes less often real trees than the peaks it keeps? It re-analyses data
# already used; it is not a confirmation test.
#
# On every plot the censused-subplot declaration admits (score_census_support.R
# with the nearest-event declaration, as results/multichm-gated-results.md
# runs it for the arm), the detections of floor and exemption
# (z5_s0_c0.6_e1: no share gate) are regenerated from the calibration study's
# stored candidates with mcg_apply(). Each detection is joined to its candidate
# row on its exact (X, Y) (the candidates are unique by X, Y) and labelled from
# that row's `layer` and `share` (mcg_candidates, mcg_first_return_share):
#   surface         layer 1
#   deeper_kept     layer > 1 and share >= 0.75 (MCG_DECLARED$min_share): the
#                   gate, where it applies, keeps it (mcg_gate: share known and
#                   at least min_share)
#   deeper_removed  layer > 1 and share < 0.75 or unknown (NA): the gate removes it
# The whole detection set is scored once with the censused scorer's one-to-one
# matching (score_neon_support: greedy within 4 m with the height gate, recall
# against the admitted references, precision from the detections inside the
# conservative interior), so no stem is claimed twice. score_neon_support()
# returns counts only, so cgr_match_labels() repeats its region, interior and
# greedy_match() call to keep each detection's matched flag; every observed and
# shifted set is also scored with score_neon_support() and the counts must
# agree (the script stops otherwise). Per class: the detections inside the
# interior and the share of them matched to a census stem. The shift null:
# the 200 offsets of mcg_null_offsets(site, plot, half, tol = 4) applied to the
# whole detection set with shift_detections() (core plus 4 m, wrapped), labels
# travelling with the detections, scored inside the same support; per class the
# mean matched share under the shifts (pooled: summed mean matched over summed
# mean inside) and the excess (observed - null) / (1 - null).
#
# Checks before any class is reported: the declared configuration's regenerated
# detections reproduce the arm's censused scores (CENSUS_CHECK: n_ref, n_det,
# TP, tp_core and the nominal-box rect_n_det, rect_TP of every admitted plot),
# and floor and exemption's nominal-box counts equal cells.csv.
#
# Usage:
#   Rscript scripts/confirm_gated_removed_peaks.R [BASE=work/paper_runs]
#     [CANDIDATES=work/multichm_gated_runs/neon/multichm_gated]
#     [FROZEN_ROOT=work/neon/frozen_2021]
#     [DECLARATION=docs/census-support-declaration-nearest.json]
#     [SUPPORT=$BASE/reference_support_census_event] [YEARS=2019,...,2024]
#     [CENSUS_CHECK=<CANDIDATES>/../../census_support_scores/nearest_ladder/
#     census_support_scores.csv] [SITES=...] [POP=adopted] [K=200] [TOL=4]
#     [N_BOOT=1000] [CORES=4] [OUT=$CLAUDE_JOB_DIR/removed_peaks]
# Writes under OUT: detections.csv (one row per detection), plot_classes.csv
# (one row per plot x class), checks.csv, scopes.csv, differences.csv,
# run.json, tables.md.
suppressMessages({ library(data.table); library(parallel); library(sf) })
source(.find("sweep_lib.R"))          # score_plot, greedy_match, shift_detections, plot_lapply
source(.find("model_bench_lib.R"))    # frozen_*, seed_for, assert_detection_contract
source(.find("census_support_lib.R")) # census_admitted_bundles, census_score_cell
source(.find("master_tables_lib.R"))  # mt_plot_weights, mt_interval, MT_*
source(.find("multichm_gated_lib.R")) # mcg_apply, mcg_null_offsets, mcg_closed, mcg_spaced

CGR_CONFIG <- mcg_config(zmin = 5, min_share = 0, cover_min = 0.6, surface_exempt = TRUE)
CGR_LABEL <- "z5_s0_c0.6_e1"
CGR_SHARE_MIN <- MCG_DECLARED$min_share
CGR_CLASSES <- c("surface", "deeper_kept", "deeper_removed")
CGR_CLASS_WORDS <- c(surface = "(a) Surface-layer peaks",
                     deeper_kept = "(b) Deeper-layer, share >= 0.75 (gate keeps)",
                     deeper_removed = "(c) Deeper-layer, share < 0.75 (gate removes)")
CGR_FIVE <- c("SJER", "SOAP", "TEAK", "WREF", "ABBY")
CGR_TZ <- 8   # the censused scorer's height gate (score_plot's default tol_z_up)

## ---- arguments ----------------------------------------------------------------------------
cgr_settings <- function(args = commandArgs(TRUE), d = .job_dir()) {
  a <- strsplit(args, "=", fixed = TRUE)
  A <- stats::setNames(lapply(a, function(x) paste(x[-1], collapse = "=")),
                       vapply(a, `[`, character(1), 1))
  get <- function(k, default) if (is.null(A[[k]]) || !nzchar(A[[k]])) default else A[[k]]
  root <- if (exists(".ROOT")) .ROOT else getwd()
  base <- get("BASE", file.path(root, "work", "paper_runs"))
  cand <- get("CANDIDATES", file.path(root, "work", "multichm_gated_runs", "neon",
                                      "multichm_gated"))
  S <- list(
    A = A, d = d, BASE = base, CANDIDATES = cand,
    FROZEN_ROOT = get("FROZEN_ROOT", file.path(root, "work", "neon", "frozen_2021")),
    DECLARATION = get("DECLARATION", file.path(root, "docs",
                                               "census-support-declaration-nearest.json")),
    SUPPORT = get("SUPPORT", file.path(base, "reference_support_census_event")),
    YEARS = as.integer(strsplit(get("YEARS", paste(2019:2024, collapse = ",")), ",")[[1]]),
    CENSUS_CHECK = get("CENSUS_CHECK", file.path(dirname(dirname(cand)), "census_support_scores",
                                                 "nearest_ladder", "census_support_scores.csv")),
    SITES = strsplit(get("SITES", paste(CGR_FIVE, collapse = ",")), ",")[[1]],
    POP = get("POP", "adopted"),
    K = suppressWarnings(as.integer(get("K", "200"))),
    TOL = suppressWarnings(as.numeric(get("TOL", "4"))),
    N_BOOT = suppressWarnings(as.integer(get("N_BOOT", as.character(MT_N_BOOT)))),
    CORES = suppressWarnings(as.integer(get("CORES", "4"))),
    OUT = get("OUT", file.path(d, "removed_peaks")))
  if (anyNA(c(S$K, S$TOL, S$N_BOOT, S$CORES, S$YEARS)) || S$K < 1 || S$TOL <= 0 ||
      S$N_BOOT < 1 || S$CORES < 1)
    stop("K, N_BOOT, CORES must be positive integers and TOL positive", call. = FALSE)
  if (!all(S$SITES %in% CGR_FIVE))
    stop("SITES must be among ", paste(CGR_FIVE, collapse = ","), call. = FALSE)
  o <- normalizePath(S$OUT, mustWork = FALSE)
  for (p in c(S$BASE, S$CANDIDATES, S$FROZEN_ROOT, S$SUPPORT)) {
    q <- normalizePath(p, mustWork = FALSE)
    if (identical(o, q) || startsWith(o, paste0(q, .Platform$file.sep)))
      stop("OUT (", S$OUT, ") lies inside a read-only input (", p, ")", call. = FALSE)
  }
  S
}

## ---- labels ---------------------------------------------------------------------------------
# det: detections (x, y, z) of one configuration; cand: the clip's candidate
# table (X, Y, Z, layer, share). Each detection is joined to the one candidate
# with the same X and Y (exact; mcg_candidates keeps candidates unique by X, Y)
# and must carry its Z. Returns det with layer, share and class.
cgr_label_detections <- function(det, cand, min_share = CGR_SHARE_MIN) {
  det <- as.data.frame(det)
  n <- nrow(det)
  i <- vapply(seq_len(n), function(k) {
    w <- which(cand$X == det$x[k] & cand$Y == det$y[k])
    if (length(w) != 1L) NA_integer_ else w
  }, integer(1))
  if (anyNA(i)) stop(sum(is.na(i)), " detections match no single candidate on (X, Y)",
                     call. = FALSE)
  if (n && any(cand$Z[i] != det$z)) stop("a detection's z differs from its candidate's Z",
                                         call. = FALSE)
  det$layer <- as.integer(cand$layer[i])
  det$share <- as.numeric(cand$share[i])
  det$class <- ifelse(det$layer == 1L, "surface",
                      ifelse(!is.na(det$share) & det$share >= min_share, "deeper_kept",
                             "deeper_removed"))
  det
}

## ---- matched flags under the censused scorer --------------------------------------------------
# The censused scorer's match of a labelled detection set, kept per detection:
# score_neon_support() -> score_plot(core_geometry = support$core) with the
# admitted references, recall region = interior buffered by tol, precision from
# the detections inside the interior, greedy_match() within tol with the
# height gate. `region` may hold the buffered interior (st_buffer(core, tol)),
# computed once per plot. Returns the detections in the recall region with
# `inside` and `matched`, and the counts n_ref, n_det (inside), TP (stems
# matched), tp_core (inside and matched).
cgr_match_labels <- function(support, det, tol = 4, region = NULL) {
  refs <- support$references[support$references$reference_selected, , drop = FALSE]
  if (is.null(region)) region <- sf::st_buffer(support$core, tol)
  in_reg <- neon_support_inside(det$x, det$y, region)
  detr <- det[in_reg, , drop = FALSE]
  inside <- neon_support_inside(detr$x, detr$y, support$core)
  m <- greedy_match(refs$E, refs$N, detr$x, detr$y, tol, az = refs$height, bz = detr$z,
                    tol_z_up = CGR_TZ)
  detr$inside <- inside
  detr$matched <- seq_len(nrow(detr)) %in% m[m > 0]
  list(det = detr, n_ref = nrow(refs), n_det = sum(inside), TP = sum(m > 0),
       tp_core = sum(inside & detr$matched))
}

# Per class: detections inside the interior and those matched.
cgr_class_counts <- function(detr, classes = CGR_CLASSES) {
  k <- factor(detr$class, levels = classes)
  data.frame(class = classes,
             n_in = as.numeric(tabulate(k[detr$inside], length(classes))),
             n_match = as.numeric(tabulate(k[detr$inside & detr$matched], length(classes))),
             stringsAsFactors = FALSE)
}

# Equal counts from the repeated match and score_neon_support itself.
cgr_same_counts <- function(lab, sc)
  lab$n_ref == sc$n_ref && lab$n_det == sc$n_det && lab$TP == sc$TP &&
    lab$tp_core == sc$tp_core

## ---- one plot ---------------------------------------------------------------------------------
cgr_plot_job <- function(j, cdir, K, tol) {
  cell <- readRDS(file.path(cdir, j$file))
  m <- cell$meta
  if (!identical(m$site, j$site) || !identical(m$plot, j$plot) || !identical(m$rung, "native"))
    stop("candidate file ", j$file, " does not hold ", j$site, "/", j$plot, " native")
  xyz <- c("x", "y", "z")
  # the declared configuration against the arm's censused scores
  decl <- census_score_cell(j$bundle, mcg_apply(cell$prep, MCG_DECLARED), j$epsg, j$stems,
                            j$cx, j$cy, j$half, tol)
  det <- mcg_apply(cell$prep, CGR_CONFIG)
  rect <- score_plot(j$stems, det, tol_xy = tol, core_cx = j$cx, core_cy = j$cy,
                     core_half = j$half)
  lab <- cgr_label_detections(det, cell$prep$cand)
  lab$det_id <- seq_len(nrow(lab))
  region <- sf::st_buffer(j$bundle$core, tol)
  obs <- cgr_match_labels(j$bundle, lab, tol, region)
  ok_obs <- cgr_same_counts(obs, score_neon_support(j$bundle, lab[, xyz], det_epsg = j$epsg,
                                                    tol_xy = tol))
  offs <- mcg_null_offsets(j$site, j$plot, j$half, tol = tol, k = K)
  nul <- matrix(0, length(CGR_CLASSES), 2, dimnames = list(CGR_CLASSES, c("n_in", "n_match")))
  ok_null <- 0L; null_tp <- 0
  for (of in offs) {
    sd <- shift_detections(lab, j$cx, j$cy, j$half + tol, of)
    r <- cgr_match_labels(j$bundle, sd, tol, region)
    ok_null <- ok_null + cgr_same_counts(r, score_neon_support(j$bundle, sd[, xyz],
                                                               det_epsg = j$epsg, tol_xy = tol))
    cc <- cgr_class_counts(r$det)
    nul <- nul + as.matrix(cc[, c("n_in", "n_match")])
    null_tp <- null_tp + r$TP
  }
  nul <- nul / length(offs)
  oc <- cgr_class_counts(obs$det)
  # how much of the recall region lies outside the window the shifts wrap in
  win <- sf::st_as_sfc(sf::st_bbox(c(xmin = j$cx - j$half - tol, ymin = j$cy - j$half - tol,
                                     xmax = j$cx + j$half + tol, ymax = j$cy + j$half + tol),
                                   crs = sf::st_crs(region)))
  out_area <- sum(as.numeric(sf::st_area(sf::st_difference(region, win))))
  core_box <- sf::st_as_sfc(sf::st_bbox(c(xmin = j$cx - j$half, ymin = j$cy - j$half,
                                          xmax = j$cx + j$half, ymax = j$cy + j$half),
                                        crs = sf::st_crs(region)))
  core_out <- sum(as.numeric(sf::st_area(sf::st_difference(j$bundle$core, core_box))))
  dets <- lab
  dets$in_region <- FALSE; dets$inside <- FALSE; dets$matched <- FALSE
  w <- obs$det$det_id
  dets$in_region[w] <- TRUE; dets$inside[w] <- obs$det$inside; dets$matched[w] <- obs$det$matched
  list(
    classes = data.frame(site = j$site, plot = j$plot, class = CGR_CLASSES,
                         n_in = oc$n_in, n_match = oc$n_match,
                         null_in = nul[, "n_in"], null_match = nul[, "n_match"],
                         stringsAsFactors = FALSE),
    detections = cbind(data.frame(site = rep(j$site, nrow(dets)), plot = rep(j$plot, nrow(dets)),
                                  stringsAsFactors = FALSE), dets),
    check = data.frame(
      site = j$site, plot = j$plot, n_ref = obs$n_ref, n_det = obs$n_det, TP = obs$TP,
      tp_core = obs$tp_core, null_TP = null_tp / length(offs), n_shifts = length(offs),
      label_match_obs = ok_obs, label_match_null = ok_null,
      decl_n_ref = decl$n_ref, decl_n_det = decl$n_det, decl_TP = decl$TP,
      decl_tp_core = decl$tp_core, decl_rect_n_det = decl$rect_n_det, decl_rect_TP = decl$rect_TP,
      fe_rect_n_det = rect$n_det, fe_rect_TP = rect$TP, n_det_clip = nrow(det),
      deeper_share_na = sum(lab$layer > 1L & is.na(lab$share)),
      region_outside_window_m2 = out_area, interior_outside_core_box_m2 = core_out,
      stringsAsFactors = FALSE))
}
cgr_plot_worker <- function(j, cdir, K, tol)
  tryCatch(cgr_plot_job(j, cdir, K, tol), error = function(e) {
    message("plot ", j$site, "/", j$plot, " failed: ", conditionMessage(e)); e })

## ---- scopes and pooling -----------------------------------------------------------------------
# Stand top-height band of a clip: under 30 m, 30 to 45 m, 45 m and over.
cgr_height_band <- function(h)
  as.character(cut(h, c(-Inf, 30, 45, Inf), right = FALSE,
                   labels = c("under 30 m", "30 to 45 m", "45 m and over")))

# plots: one row per plot with site, plot, cover, crown_spacing, top_height.
# Adds closed and gated (as the declared configuration decides them:
# mcg_closed, mcg_spaced) and the height band, and returns the scopes as a
# named list of plot ids ("site::plot").
cgr_scopes <- function(plots, cfg = MCG_DECLARED) {
  id <- paste(plots$site, plots$plot, sep = "::")
  closed <- vapply(plots$cover, function(v) isTRUE(mcg_closed(v, cfg)), logical(1))
  spaced <- vapply(plots$crown_spacing, function(v) isTRUE(mcg_spaced(v, cfg)), logical(1))
  gated <- closed & spaced
  band <- cgr_height_band(plots$top_height)
  s <- list(`All admitted plots` = id,
            `Gated (closed, crown spacing >= 8 m)` = id[gated],
            `Closed, not gated` = id[closed & !gated],
            `Open` = id[!closed],
            California = id[plots$site %in% MT_REGIONS$California],
            WREF = id[plots$site == "WREF"], ABBY = id[plots$site == "ABBY"],
            `Top height under 30 m` = id[band == "under 30 m"],
            `Top height 30 to 45 m` = id[band == "30 to 45 m"],
            `Top height 45 m and over` = id[band == "45 m and over"])
  s[vapply(s, length, integer(1)) > 0L]
}

# Matched share, null share and excess from summed counts (vectors or
# matrices, elementwise): share = n_match / n_in, null = null_match / null_in,
# excess = (share - null) / (1 - null).
cgr_rates <- function(n_in, n_match, null_in, null_match) {
  dv <- function(a, b) ifelse(is.finite(a) & is.finite(b) & b > 0, a / b, NA_real_)
  share <- dv(n_match, n_in); null <- dv(null_match, null_in)
  excess <- ifelse(is.finite(share) & is.finite(null) & null < 1, (share - null) / (1 - null),
                   NA_real_)
  list(share = share, null = null, excess = excess)
}

# pc: one row per plot x class (site, plot, class, n_in, n_match, null_in,
# null_match); every plot must carry every class. For each scope (plot ids):
# per class the counts, matched share, null share and excess with 95% plot
# bootstrap intervals (mt_plot_weights: plots resampled within site), and the
# differences b - c (deeper_kept minus deeper_removed) and a - c of the matched
# share and the excess, on the same draws.
cgr_scope_summary <- function(pc, scopes, n_boot = MT_N_BOOT, seed = MT_SEED,
                              classes = CGR_CLASSES,
                              diffs = list(c("deeper_kept", "deeper_removed"),
                                           c("surface", "deeper_removed"),
                                           c("surface", "deeper_kept"))) {
  pc <- as.data.frame(pc)
  pc$id <- paste(pc$site, pc$plot, sep = "::")
  cnt <- c("n_in", "n_match", "null_in", "null_match")
  rows <- list(); drows <- list()
  for (sc in names(scopes)) {
    x <- pc[pc$id %in% scopes[[sc]], , drop = FALSE]
    if (!nrow(x)) next
    W <- mt_plot_weights(x$site, x$plot, n_boot, seed)
    get <- function(k) {
      y <- x[x$class == k, , drop = FALSE]
      if (anyDuplicated(y$id) || !setequal(y$id, rownames(W)))
        stop("class ", k, " must cover each plot of scope ", sc, " once", call. = FALSE)
      y <- y[match(rownames(W), y$id), , drop = FALSE]
      lapply(stats::setNames(cnt, cnt), function(c) as.numeric(y[[c]]))
    }
    est <- list(); drw <- list()
    for (k in classes) {
      v <- get(k)
      est[[k]] <- cgr_rates(sum(v$n_in), sum(v$n_match), sum(v$null_in), sum(v$null_match))
      dv <- lapply(v, function(z) drop(crossprod(W, z)))
      drw[[k]] <- cgr_rates(dv$n_in, dv$n_match, dv$null_in, dv$null_match)
      iv <- function(m) mt_interval(drw[[k]][[m]])
      rows[[length(rows) + 1L]] <- data.frame(
        scope = sc, n_plots = nrow(W), class = k, n_in = sum(v$n_in), n_match = sum(v$n_match),
        null_in = sum(v$null_in), null_match = sum(v$null_match),
        share = est[[k]]$share, share_lower = iv("share")$lower, share_upper = iv("share")$upper,
        null_share = est[[k]]$null, null_lower = iv("null")$lower, null_upper = iv("null")$upper,
        excess = est[[k]]$excess, excess_lower = iv("excess")$lower,
        excess_upper = iv("excess")$upper, defined_draws = iv("share")$defined_draws,
        stringsAsFactors = FALSE)
    }
    for (dd in diffs) {
      for (m in c("share", "excess")) {
        iv <- mt_interval(drw[[dd[1]]][[m]] - drw[[dd[2]]][[m]])
        drows[[length(drows) + 1L]] <- cbind(data.frame(
          scope = sc, n_plots = nrow(W), difference = paste(dd, collapse = "_minus_"),
          metric = m, estimate = est[[dd[1]]][[m]] - est[[dd[2]]][[m]],
          stringsAsFactors = FALSE), iv)
      }
    }
  }
  list(scopes = do.call(rbind, rows), differences = do.call(rbind, drows))
}

## ---- Markdown -------------------------------------------------------------------------------
cgr_f3 <- function(x) ifelse(is.na(x), "NA", sprintf("%.3f", x))
cgr_s3 <- function(x) ifelse(is.na(x), "NA", sub("^-", "−", sprintf("%+.3f", x)))
cgr_md_row <- function(...) paste0("| ", paste(unlist(list(...)), collapse = " | "), " |")

cgr_tables_md <- function(sm, df, meta) {
  L <- c("# Gated multichm: the peaks the share gate removes (check R5)", "",
         sprintf(paste("Detections of floor and exemption (%s) at native density on the %d",
                       "plots the declaration %s admits (%s censused references), scored",
                       "inside the censused subplots with the censused scorer's one-to-one",
                       "matching; shift null of %d offsets per plot (mcg_null_offsets, tol 4 m)."),
                 CGR_LABEL, meta$n_plots, meta$declaration, format(meta$n_ref, big.mark = ","),
                 meta$K),
         sprintf(paste("Matched share: detections inside the censused interior matched to a",
                       "census stem, over those inside. Null: the same under the shifts (summed",
                       "mean matched over summed mean inside). Excess: (observed - null) / (1 -",
                       "null). Intervals: 95%% plot-bootstrap percentiles (plots resampled within",
                       "site, %d draws, MT_SEED)."), meta$n_boot), "",
         cgr_md_row("Scope", "Plots", "Class", "Inside", "Matched", "Matched share",
                    "Null share", "Excess"),
         cgr_md_row("---", "---", "---", "---", "---", "---", "---", "---"))
  iv <- function(e, lo, hi, f = cgr_f3) sprintf("%s [%s, %s]", f(e), f(lo), f(hi))
  for (i in seq_len(nrow(sm))) {
    r <- sm[i, ]
    L <- c(L, cgr_md_row(r$scope, r$n_plots, CGR_CLASS_WORDS[[r$class]], r$n_in, r$n_match,
                         iv(r$share, r$share_lower, r$share_upper),
                         iv(r$null_share, r$null_lower, r$null_upper),
                         iv(r$excess, r$excess_lower, r$excess_upper, cgr_s3)))
  }
  L <- c(L, "", "Differences between classes, same draws:", "",
         cgr_md_row("Scope", "Plots", "Difference", "Matched share", "Excess"),
         cgr_md_row("---", "---", "---", "---", "---"))
  dn <- c(deeper_kept_minus_deeper_removed = "(b) − (c)",
          surface_minus_deeper_removed = "(a) − (c)",
          surface_minus_deeper_kept = "(a) − (b)")
  for (sc in unique(df$scope)) for (d in names(dn)) {
    x <- df[df$scope == sc & df$difference == d, , drop = FALSE]
    if (!nrow(x)) next
    s <- x[x$metric == "share", ]; e <- x[x$metric == "excess", ]
    L <- c(L, cgr_md_row(sc, x$n_plots[1], dn[[d]], iv(s$estimate, s$lower, s$upper, cgr_s3),
                         iv(e$estimate, e$lower, e$upper, cgr_s3)))
  }
  c(L, "")
}

## ---- main -----------------------------------------------------------------------------------
run_main <- function() {
  t0 <- Sys.time()
  S <- cgr_settings()
  dir.create(S$OUT, recursive = TRUE, showWarnings = FALSE)
  cdir <- file.path(S$CANDIDATES, "candidates")
  frozen_stamp_check(cdir, S$FROZEN_ROOT)
  declaration <- jsonlite::read_json(S$DECLARATION, simplifyVector = TRUE)
  if (grepl("DRAFT", declaration$name)) stop("Refusing a draft declaration", call. = FALSE)
  if (!identical(mcg_config_label(CGR_CONFIG), CGR_LABEL)) stop("CGR_CONFIG is not ", CGR_LABEL)
  idx <- read.csv(file.path(S$CANDIDATES, "candidates.csv"), stringsAsFactors = FALSE,
                  colClasses = c(rung = "character"))
  idx <- idx[idx$rung == "native" & idx$site %in% S$SITES, , drop = FALSE]
  if (any(idx$population != S$POP) || any(abs(idx$a - 0.10) > 1e-12))
    stop("the candidates were not made for population ", S$POP, " with a = 0.10", call. = FALSE)
  jobs <- list()
  for (site in S$SITES) {
    nd <- file.path(S$BASE, "neon", site)
    gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
    fz <- frozen_scope(S$BASE, site, list(FROZEN_ROOT = S$FROZEN_ROOT, POP = S$POP), gt)
    epsg <- neon_validate_inputs(fz$gt, pc)
    bundles <- census_admitted_bundles(S$SUPPORT, site, declaration, S$YEARS)
    plots <- intersect(names(bundles), fz$plots)
    cat(sprintf("[%s] admitted plots in population %s: %d of %d\n", site, fz$population,
                length(plots), length(fz$plots)))
    for (pid in plots) {
      r <- idx[idx$site == site & idx$plot == pid, , drop = FALSE]
      if (nrow(r) != 1L) stop("no single native candidate cell for ", site, "/", pid, call. = FALSE)
      ci <- pc[pc$plotID == pid, ][1, ]
      ph <- plot_half(ci$plotType)
      if (abs(ci$easting - r$cx) > 1e-9 || abs(ci$northing - r$cy) > 1e-9 || ph != r$half)
        stop("plot frame of ", pid, " differs from the candidate cell", call. = FALSE)
      jobs[[length(jobs) + 1L]] <- list(
        site = site, plot = pid, file = r$file, cx = r$cx, cy = r$cy, half = r$half,
        epsg = epsg, bundle = bundles[[pid]],
        stems = fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - ci$easting) <= ph &
                        abs(fz$gt$N - ci$northing) <= ph, , drop = FALSE],
        cover = r$cover, crown_spacing = r$crown_spacing, top_height = r$top_height)
    }
  }
  cat(sprintf("[removed_peaks] %d admitted plots, %d shifts each, %d cores\n", length(jobs),
              S$K, S$CORES))
  res <- plot_lapply(jobs, cgr_plot_worker, cdir = cdir, K = S$K, tol = S$TOL,
                     mc.cores = S$CORES)
  bad <- vapply(res, function(r) inherits(r, "error"), logical(1))
  if (any(bad)) stop("plots failed: ", paste(vapply(jobs[bad], function(j)
    paste(j$site, j$plot, sep = "/"), ""), collapse = ","), call. = FALSE)
  classes <- as.data.frame(data.table::rbindlist(lapply(res, `[[`, "classes")))
  dets <- as.data.frame(data.table::rbindlist(lapply(res, `[[`, "detections")))
  checks <- as.data.frame(data.table::rbindlist(lapply(res, `[[`, "check")))
  plots <- data.frame(site = vapply(jobs, `[[`, "", "site"), plot = vapply(jobs, `[[`, "", "plot"),
                      cover = vapply(jobs, `[[`, 0, "cover"),
                      crown_spacing = vapply(jobs, `[[`, 0, "crown_spacing"),
                      top_height = vapply(jobs, `[[`, 0, "top_height"), stringsAsFactors = FALSE)
  plots$closed <- vapply(plots$cover, function(v) isTRUE(mcg_closed(v, MCG_DECLARED)), logical(1))
  plots$gated <- plots$closed & vapply(plots$crown_spacing, function(v)
    isTRUE(mcg_spaced(v, MCG_DECLARED)), logical(1))
  plots$top_band <- cgr_height_band(plots$top_height)
  checks <- merge(checks, plots, by = c("site", "plot"))
  ## checks: the declared configuration against the arm's censused scores, and
  ## floor and exemption's nominal box against cells.csv
  cs <- read.csv(S$CENSUS_CHECK, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  cs <- cs[cs$detector == "multichm_gated" & cs$rung == "native", , drop = FALSE]
  w <- match(paste(checks$site, checks$plot), paste(cs$site, cs$plot))
  checks$census_file_row <- !is.na(w)
  cmp <- c(n_ref = "decl_n_ref", n_det = "decl_n_det", TP = "decl_TP", tp_core = "decl_tp_core",
           rect_n_det = "decl_rect_n_det", rect_TP = "decl_rect_TP")
  checks$decl_equals_census_file <- !is.na(w) & Reduce(`&`, lapply(names(cmp), function(k)
    !is.na(cs[[k]][w]) & cs[[k]][w] == checks[[cmp[[k]]]]))
  cells <- data.table::fread(file.path(S$CANDIDATES, "cells.csv"),
                             select = c("site", "plot", "rung", "config", "n_det", "TP"),
                             colClasses = list(character = "rung"))
  cells <- as.data.frame(cells[cells$rung == "native" & cells$config == CGR_LABEL])
  w2 <- match(paste(checks$site, checks$plot), paste(cells$site, cells$plot))
  checks$fe_equals_cells <- !is.na(w2) & cells$n_det[w2] == checks$fe_rect_n_det &
    cells$TP[w2] == checks$fe_rect_TP
  write.csv(checks, file.path(S$OUT, "checks.csv"), row.names = FALSE)
  cat(sprintf("[check] declared configuration equals the arm's censused scores in %d of %d plots (%s)\n",
              sum(checks$decl_equals_census_file), nrow(checks), S$CENSUS_CHECK))
  cat(sprintf("[check] floor and exemption's nominal-box n_det and TP equal cells.csv in %d of %d plots\n",
              sum(checks$fe_equals_cells), nrow(checks)))
  cat(sprintf("[check] the labelled match equals score_neon_support in %d of %d observed sets and %d of %d shifted sets\n",
              sum(checks$label_match_obs), nrow(checks), sum(checks$label_match_null),
              sum(checks$n_shifts)))
  if (!all(checks$decl_equals_census_file) || !all(checks$fe_equals_cells) ||
      !all(checks$label_match_obs) || any(checks$label_match_null != checks$n_shifts))
    stop("a check failed; see checks.csv", call. = FALSE)
  write.csv(classes, file.path(S$OUT, "plot_classes.csv"), row.names = FALSE)
  write.csv(dets, file.path(S$OUT, "detections.csv"), row.names = FALSE)
  scopes <- cgr_scopes(plots)
  sm <- cgr_scope_summary(classes, scopes, S$N_BOOT, MT_SEED)
  write.csv(sm$scopes, file.path(S$OUT, "scopes.csv"), row.names = FALSE)
  write.csv(sm$differences, file.path(S$OUT, "differences.csv"), row.names = FALSE)
  meta <- list(n_plots = nrow(plots), declaration = declaration$name, n_ref = sum(checks$n_ref),
               K = S$K, n_boot = S$N_BOOT)
  writeLines(cgr_tables_md(sm$scopes, sm$differences, meta), file.path(S$OUT, "tables.md"))
  jsonlite::write_json(c(meta, list(
    config = CGR_LABEL, share_min = CGR_SHARE_MIN, tol = S$TOL, seed = MT_SEED, base = S$BASE, candidates = S$CANDIDATES, frozen_root = S$FROZEN_ROOT,
    root_id = frozen_root_id(S$FROZEN_ROOT), support = S$SUPPORT, census_check = S$CENSUS_CHECK,
    sites = I(S$SITES), cores = S$CORES,
    scope_plots = lapply(scopes, length),
    minutes_total = as.numeric(difftime(Sys.time(), t0, units = "mins")))),
    file.path(S$OUT, "run.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
  cat(sprintf("[removed_peaks] done in %.1f min -> %s/{detections,plot_classes,checks,scopes,differences}.csv, tables.md, run.json\n",
              as.numeric(difftime(Sys.time(), t0, units = "mins")), S$OUT))
  invisible(sm)
}

if (sys.nframe() == 0L) run_main()
