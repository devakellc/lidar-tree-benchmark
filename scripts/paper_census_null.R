#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(lidR); library(data.table) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
source(.find("io_bridge.R"))
source(.find("coverage_lib.R"))           # read_arm_cache
source(.find("census_support_lib.R"))
source(.find("master_tables_lib.R"))
source(.find("census_null_lib.R"))

# The paper's chance-agreement null scored inside censused subplots (post hoc).
# paper_sensitivity.R MODE=null shifts each cell's detections and scores them
# in the nominal plot box only; NEON censuses two of the four 20 m subplots of
# a tower plot, so most of a tower box was never surveyed. Here every admitted
# plot of a reviewed census declaration (score_census_support.R) gets the same
# K offsets as the paper's null, null_offset(2 (ph + TOL), seed_for(site,
# plot, "null") + SEED * 1000003 + k, MIN_SHIFT), the same shifted detections
# (shift_detections within ph + TOL) for every arm and rung, and the same
# greedy matcher at radius TOL with the height gate; each shifted set is scored
# by census_score_cell, which gives the censused counts (interior) and the
# nominal-box counts (rect_*) of the same detections. A cell's null is its
# mean counts over the K shifts. Pooling sums counts over plots; corrected F1
# = (F1 - null F1) / (1 - null F1) for the estimate and every paired draw of
# the master tables' plot resamples (W drawn on each rung's admitted plots);
# leads are each arm minus CHM-VWF, paired. Every pooled row is repeated
# without the plots holding a censused reference outside the nominal box (part
# of its match disc lies beyond the shift window, which can only lower its
# null).
#
# Checks (written to <prefix>_checks.txt; the script stops on a failure):
#   A  the observed censused and nominal-box counts of every cell (at 4 m)
#      equal the committed census_support_scores rows, and no committed cell
#      of the run's arms and rungs is missing;
#   B  (headline declaration, 4 m) the observed censused and nominal-box F1
#      leads over CHM-VWF equal master_tables/master_contrasts.csv; a missing
#      file fails it. CHECK_MASTER=0 skips it for a run whose arms the master
#      tables do not hold (the unsmoothed baseline in its own job directory);
#   C  the nominal-box observed counts and null mean counts of every cell
#      equal the paper's null cells (sensitivity/null[_tol..]_cells.csv).
#
#   Rscript scripts/paper_census_null.R
#     [DECLARATION=docs/census-support-declaration-nearest.json]
#     [ARMS=chm_vwf,multichm,lmfauto,ptrees,ams3d,li2012,forestformer3d,treeisonet,segmentanytree]
#     [RUNGS=native,8,4,2,1] [TOL=4] [K=200] [SEED=0] [MIN_SHIFT=8] [CORES=8]
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [YEARS=2019,...,2024] [FROZEN_ROOT=...]
#     [SUPPORT=$CLAUDE_JOB_DIR/reference_support_census_event]
#     [OUT=$CLAUDE_JOB_DIR/sensitivity/census_null]
#     [CENSUS_SCORES=<dir>,...] [NULL_CELLS=<csv>] [MASTER_TABLES=<master_contrasts.csv>]
#     [DRAWS=1 (also write the per-shift counts)] [CHECK_MASTER=0 (skip check B)]
# Li 2012 exists at native density only. The QL2 rung runs from its own job
# directory: CLAUDE_JOB_DIR=<paper_runs_ql2> ... RUNGS=3.2 FROZEN_ROOT=<root>
# MASTER_TABLES=<paper_runs>/master_tables/master_contrasts.csv.
# Writes OUT/<prefix>_{cells,pooled,leads,geometry,detections,mcse,missing}.csv,
# <prefix>_checks.txt, <prefix>_tables.md and, with DRAWS=1,
# <prefix>_draws.csv.gz (per-shift counts); <prefix> is census_null, plus
# _<declaration> for a non-headline declaration and _tol<TOL>,
# _ms<MIN_SHIFT>, _seed<SEED> for non-default values (as the paper's null
# files).
t_start <- Sys.time()
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d <- .job_dir()
BASE_TOL <- 4
DECLARATION <- if (is.null(A$DECLARATION))
  file.path(.ROOT, "docs", "census-support-declaration-nearest.json") else A$DECLARATION
declaration <- jsonlite::read_json(DECLARATION, simplifyVector = TRUE)
if (grepl("DRAFT", declaration$name)) stop("Refusing a draft declaration; review and rename it first")
DECL_TAG <- sub("^census-support-declaration-", "", sub("\\.json$", "", basename(DECLARATION)))
HEADLINE <- DECL_TAG == "nearest"
SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
ARMS  <- split_arg(A$ARMS, paste(CN_ARMS, collapse = ","))
RUNGS <- split_arg(A$RUNGS, "native,8,4,2,1")
YEARS <- as.integer(split_arg(A$YEARS, paste(2019:2024, collapse = ",")))
SUPPORT <- if (is.null(A$SUPPORT)) file.path(d, "reference_support_census_event") else A$SUPPORT
TOL <- as.numeric(if (is.null(A$TOL)) BASE_TOL else A$TOL)
K <- as.integer(if (is.null(A$K)) 200 else A$K)
SEED <- as.integer(if (is.null(A$SEED)) 0 else A$SEED)
MIN_SHIFT <- as.numeric(if (is.null(A$MIN_SHIFT)) 8 else A$MIN_SHIFT)
CORES <- as.integer(if (is.null(A$CORES)) 8 else A$CORES)
DRAWS <- identical(A$DRAWS, "1")
CHECK_MASTER <- !identical(A$CHECK_MASTER, "0")
OUT <- if (is.null(A$OUT)) file.path(d, "sensitivity", "census_null") else A$OUT
SFX <- cn_suffix(TOL, MIN_SHIFT, SEED, BASE_TOL)
PREFIX <- paste0("census_null", if (!HEADLINE) paste0("_", gsub("-", "_", DECL_TAG)), SFX)
NULL_CELLS <- if (is.null(A$NULL_CELLS))
  file.path(d, "sensitivity", paste0("null", SFX, "_cells.csv")) else A$NULL_CELLS
score_dirs <- function() {
  base <- file.path(d, if (grepl("-strict$", DECL_TAG)) "census_support_scores_strict" else
    "census_support_scores")
  rule <- sub("-strict$", "", DECL_TAG)
  x <- c(file.path(base, paste0(rule, "_ladder")), Sys.glob(file.path(base, paste0(rule, "_native*"))))
  x[dir.exists(x) & !grepl(".", basename(x), fixed = TRUE)]
}
CENSUS_SCORES <- if (is.null(A$CENSUS_SCORES)) score_dirs() else split_arg(A$CENSUS_SCORES, "")
MASTER_TABLES <- if (is.null(A$MASTER_TABLES))
  file.path(d, "master_tables", "master_contrasts.csv") else A$MASTER_TABLES
if (length(setdiff(ARMS, CN_ARMS))) stop("Unknown arms: ", paste(setdiff(ARMS, CN_ARMS), collapse = ", "))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
outf <- function(what) file.path(OUT, paste0(PREFIX, "_", what))
cat(sprintf(paste0("job dir: %s\ndeclaration: %s (%s)\nOUT: %s (prefix %s)\nARMS: %s\nRUNGS: %s\n",
                   "TOL=%g K=%d SEED=%d MIN_SHIFT=%g CORES=%d\n"),
            d, DECLARATION, declaration$name, OUT, PREFIX, paste(ARMS, collapse = ","),
            paste(RUNGS, collapse = ","), TOL, K, SEED, MIN_SHIFT, CORES))

## ---- phase 1 (sequential): bundles, stems and persisted detections -------------------
jobs <- list(); missing <- list(); scopes_used <- character()
for (site in SITES) {
  nd <- file.path(d, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  fz <- frozen_scope(d, site, A, gt)
  epsg <- invisible(neon_validate_inputs(fz$gt, pc))
  bundles <- census_admitted_bundles(SUPPORT, site, declaration, YEARS)
  plots <- intersect(names(bundles), fz$plots)
  cat(sprintf("[%s] admitted plots in population %s: %d of %d\n", site, fz$population,
              length(plots), length(fz$plots)))
  for (pid in plots) {
    ci <- pc[pc$plotID == pid, ][1, ]
    ph <- plot_half(ci$plotType)
    stems <- fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - ci$easting) <= ph &
                     abs(fz$gt$N - ci$northing) <= ph, , drop = FALSE]
    cells <- list()
    for (r in RUNGS) {
      rung <- if (r == "native") NA else as.numeric(r)
      cell <- frozen_clip(NULL, site, pid, rung, ci$easting, ci$northing, ph, fz$root)
      if (is.null(cell)) next                          # upsampled or unusable cell
      for (arm in ARMS) {
        if (arm == "li2012" && r != "native") next     # Li 2012 exists at native only
        det <- census_cell_detections(nd, arm, site, pid, rung, fz$root, cell)
        if (is.null(det)) {
          missing[[length(missing) + 1]] <- data.frame(site = site, plot = pid, rung = r, detector = arm)
          next
        }
        cells[[length(cells) + 1]] <- list(rung = r, arm = arm, source = attr(det, "source"),
                                           det = data.frame(x = det$x, y = det$y, z = det$z))
      }
    }
    jobs[[length(jobs) + 1]] <- list(site = site, pid = pid, plot_type = ci$plotType,
                                     cx = ci$easting, cy = ci$northing, ph = ph, stems = stems,
                                     bundle = bundles[[pid]], epsg = epsg, cells = cells)
  }
  if (length(plots)) scopes_used <- c(scopes_used, site)
}
miss <- if (length(missing)) do.call(rbind, missing) else
  data.frame(site = character(), plot = character(), rung = character(), detector = character())
write.csv(miss, outf("missing.csv"), row.names = FALSE)
if (nrow(miss)) {
  print(utils::head(miss, 20), row.names = FALSE)
  stop(nrow(miss), " admitted cells have no persisted detections; see ", outf("missing.csv"))
}
cat(sprintf("phase 1: %d plots, %d cells, %.1f s\n", length(jobs),
            sum(vapply(jobs, function(j) length(j$cells), 1L)),
            as.numeric(difftime(Sys.time(), t_start, units = "secs"))))

## ---- phase 2 (parallel over plots): observed and K shifted copies per cell ------------
CNT <- c(CN_COUNTS, CN_RECT)
run_job <- function(j) {
  offs <- cn_offsets(j$site, j$pid, j$ph, TOL, K, SEED, MIN_SHIFT)
  h <- j$ph + TOL
  core <- j$bundle$core
  square <- function(half) sf::st_sfc(sf::st_polygon(list(rbind(
    c(j$cx - half, j$cy - half), c(j$cx + half, j$cy - half), c(j$cx + half, j$cy + half),
    c(j$cx - half, j$cy + half), c(j$cx - half, j$cy - half)))), crs = sf::st_crs(core))
  area <- function(g) if (length(g) && !all(sf::st_is_empty(g))) sum(as.numeric(sf::st_area(g))) else 0
  win <- square(h); box <- square(j$ph); reach <- sf::st_buffer(core, TOL)
  refs <- j$bundle$references[j$bundle$references$reference_selected, , drop = FALSE]
  excess <- cn_box_excess(refs$E, refs$N, j$cx, j$cy, j$ph)
  geo <- data.frame(site = j$site, plot = j$pid, plot_type = j$plot_type, ph = j$ph, tol = TOL,
                    window_area_m2 = (2 * h)^2, box_area_m2 = (2 * j$ph)^2,
                    interior_area_m2 = area(core),
                    interior_outside_box_m2 = area(sf::st_difference(core, box)),
                    interior_outside_window_m2 = area(sf::st_difference(core, win)),
                    reach_area_m2 = area(reach),
                    reach_outside_window_m2 = area(sf::st_difference(reach, win)),
                    n_ref_census = nrow(refs), n_ref_box = nrow(j$stems),
                    n_ref_outside_box = sum(excess > 0), n_ref_outside_window = sum(excess > TOL),
                    max_ref_excess_m = max(c(0, excess)), stringsAsFactors = FALSE)
  cells <- list(); draws <- list()
  for (cl in j$cells) {
    key <- data.frame(site = j$site, plot = j$pid, rung = cl$rung, detector = cl$arm,
                      source = cl$source, stringsAsFactors = FALSE)
    one <- function(variant, sc, draws_n = NA_integer_, wrapped = NA_real_)
      data.frame(variant = variant, key, support_id = sc$support_id[1], as.list(unlist(sc[1, CNT])),
                 draws = draws_n, n_det_window = n_win, n_wrapped_interior = wrapped,
                 stringsAsFactors = FALSE)
    score <- function(dt, tol = TOL)
      census_score_cell(j$bundle, dt, j$epsg, j$stems, j$cx, j$cy, j$ph, tol)
    sh <- cn_cell_shifts(cl$det, j$cx, j$cy, h, offs, score, CNT,
                         inside = function(x, y) neon_support_inside(x, y, core))
    n_win <- sh$n_window
    sc <- score(cl$det)
    cells[[length(cells) + 1]] <- one("observed", sc)
    # At another radius the 4 m observed score is kept for check A.
    if (TOL != BASE_TOL) cells[[length(cells) + 1]] <- one("observed_tol4", score(cl$det, BASE_TOL))
    cells[[length(cells) + 1]] <- one("null", as.data.frame(c(list(support_id = sc$support_id[1]),
                                                              cn_null_means(sh$draws))), K, mean(sh$wrapped))
    draws[[length(draws) + 1]] <- data.frame(key[, c("site", "plot", "rung", "detector")],
                                             k = seq_len(K), sh$draws, wrapped_interior = sh$wrapped)
  }
  list(cells = rbindlist(cells), draws = rbindlist(draws), geo = geo)
}
t1 <- Sys.time()
res <- plot_lapply(jobs, function(j)
  tryCatch(run_job(j), error = function(e)
    structure(list(message = conditionMessage(e)), class = "census_null_error", plot = j$pid)),
  mc.cores = CORES, mc.preschedule = FALSE)
bad <- Filter(function(r) inherits(r, "census_null_error") || is.null(r), res)
if (length(bad)) {
  for (b in bad) cat("FAILED:", attr(b, "plot"), b$message, "\n")
  stop(length(bad), " plots failed")
}
cat(sprintf("phase 2: %.1f s\n", as.numeric(difftime(Sys.time(), t1, units = "secs"))))
cells <- as.data.frame(rbindlist(lapply(res, `[[`, "cells")))
draws <- rbindlist(lapply(res, `[[`, "draws"))
geo <- as.data.frame(rbindlist(lapply(res, `[[`, "geo")))
write.csv(cells, outf("cells.csv"), row.names = FALSE)
if (DRAWS) fwrite(draws, outf("draws.csv.gz"))
write.csv(geo, outf("geometry.csv"), row.names = FALSE)
obs <- cells[cells$variant == "observed", , drop = FALSE]
nul <- cells[cells$variant == "null", , drop = FALSE]

## ---- checks ------------------------------------------------------------------------------
log_lines <- character()
say <- function(...) { x <- sprintf(...); cat(x, "\n"); log_lines <<- c(log_lines, x) }
KEYS <- c("site", "plot", "rung", "detector")
EPS <- 1e-9
say("Censused chance agreement: declaration %s (%s), TOL=%g, K=%d, SEED=%d, MIN_SHIFT=%g",
    basename(DECLARATION), declaration$name, TOL, K, SEED, MIN_SHIFT)
say("cells: %d (%d plots; rungs %s; arms %s)", nrow(obs), length(unique(paste(obs$site, obs$plot))),
    paste(unique(obs$rung), collapse = ","), paste(unique(obs$detector), collapse = ","))
for (r in unique(obs$rung)) {
  o <- obs[obs$rung == r, ]
  sets <- lapply(split(paste(o$site, o$plot), o$detector), sort)
  if (!all(vapply(sets, identical, logical(1), sets[[1]])))
    stop("Unequal plot support at rung ", r, ": every arm must score the same admitted plots")
}

# A: observed counts at 4 m against the committed census scores.
okA <- FALSE
A_obs <- cells[cells$variant == (if (TOL == BASE_TOL) "observed" else "observed_tol4"), , drop = FALSE]
files <- file.path(CENSUS_SCORES, "census_support_scores.csv")
if (!length(files) || !all(file.exists(files))) {
  say("CHECK A: FAIL (committed census scores not found: %s)", paste(files, collapse = ", "))
} else {
  com <- do.call(rbind, lapply(files, function(f)
    read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))[, c(KEYS, CNT, "support_id", "source")]))
  ck <- do.call(paste, com[KEYS]); colA <- c(CNT, "support_id", "source")
  dup <- ck[duplicated(ck)]
  agree <- all(vapply(dup, function(k) {
    z <- com[ck == k, colA]; all(vapply(z, function(v) length(unique(v)) == 1L, logical(1)))
  }, logical(1)))
  com <- com[!duplicated(ck), , drop = FALSE]
  cA <- cn_compare(A_obs, com, KEYS, colA)
  extra <- com[com$site %in% SITES & com$detector %in% unique(obs$detector) &
                 com$rung %in% unique(obs$rung) & !do.call(paste, com[KEYS]) %in%
                 do.call(paste, A_obs[KEYS]), , drop = FALSE]
  okA <- agree && cA$missing == 0 && nrow(extra) == 0 && all(cA$max_diff == 0)
  say("A: %d cells against %d committed rows from %s; %d duplicated committed cells %s",
      cA$n, nrow(com), paste(basename(CENSUS_SCORES), collapse = ", "), length(dup),
      if (agree) "agree" else "DISAGREE")
  say("A: %d cells without a committed row; %d committed cells of these arms and rungs not scored here",
      cA$missing, nrow(extra))
  say("A: largest difference per column (counts at 4 m; support_id and source: differing rows): %s",
      paste(sprintf("%s %g", names(cA$max_diff), cA$max_diff), collapse = ", "))
  say("CHECK A (observed parity with the committed census scores): %s", if (okA) "PASS" else "FAIL")
}

# C: nominal-box observed and null counts against the paper's null cells.
okC <- FALSE
if (!file.exists(NULL_CELLS)) {
  say("CHECK C: FAIL (the paper's null cells %s do not exist)", NULL_CELLS)
} else {
  pn <- read.csv(NULL_CELLS, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  cC <- cn_compare(nul, pn[pn$variant == "null", ], KEYS, CN_RECT, CN_COUNTS)
  cO <- cn_compare(obs, pn[pn$variant == "baseline", ], KEYS, CN_RECT, CN_COUNTS)
  okC <- cC$missing == 0 && cO$missing == 0 && max(cC$max_diff, cO$max_diff) <= EPS
  say("C: %d null cells, %d found in %s; largest difference of the mean nominal-box counts: %s",
      cC$n, cC$matched, basename(NULL_CELLS), cn_diff_text(setNames(cC$max_diff, CN_COUNTS), EPS))
  say("C: %d observed cells, %d found among its baseline rows; largest difference: %s",
      cO$n, cO$matched, cn_diff_text(setNames(cO$max_diff, CN_COUNTS), EPS))
  say("CHECK C (nominal-box null parity with %s): %s", basename(NULL_CELLS), if (okC) "PASS" else "FAIL")
}

## ---- pooling ------------------------------------------------------------------------------
REG <- lapply(MT_REGIONS, intersect, scopes_used)
SCOPES <- c(list(`five sites` = scopes_used), REG[lengths(REG) > 0], setNames(as.list(scopes_used), scopes_used))
outside <- geo[geo$n_ref_outside_box > 0, , drop = FALSE]
PLOT_SETS <- list(all = unique(paste(geo$site, geo$plot, sep = "::")),
                  inside_box = with(geo[geo$n_ref_outside_box == 0, ], unique(paste(site, plot, sep = "::"))))
est_rows <- list(); lead_rows <- list()
for (ps in names(PLOT_SETS)) for (r in unique(obs$rung)) {
  keep <- function(x) x[x$rung == r & paste(x$site, x$plot, sep = "::") %in% PLOT_SETS[[ps]], , drop = FALSE]
  o <- keep(obs); n <- keep(nul)
  W <- mt_plot_weights(o$site, o$plot, MT_N_BOOT, MT_SEED)
  for (fam in c("census", "box")) {
    x <- rbind(cn_family_rows(o, fam), cn_family_rows(n, fam))
    p <- cn_pool(x, W, SCOPES)
    est_rows[[length(est_rows) + 1]] <- cbind(plot_set = ps, family = fam, p$est)
    if (!is.null(p$leads))                  # a run of CHM-VWF alone has no leads
      lead_rows[[length(lead_rows) + 1]] <- cbind(plot_set = ps, family = fam, p$leads)
  }
}
est <- do.call(rbind, est_rows); leads <- do.call(rbind, lead_rows)
if (is.null(leads)) leads <- data.frame(plot_set = character(), family = character(),
  scope = character(), rung = character(), detector = character(), versus = character(),
  n_plots = integer(), kind = character(), metric = character(), estimate = numeric(),
  lower = numeric(), upper = numeric(), defined_draws = integer())
write.csv(est, outf("pooled.csv"), row.names = FALSE)
write.csv(leads, outf("leads.csv"), row.names = FALSE)

# B: observed leads against the master tables' censused contrasts.
okB <- NA
if (!HEADLINE || TOL != BASE_TOL) {
  say("B: not applicable (the master tables hold the headline declaration at 4 m only)")
} else if (!CHECK_MASTER) {
  say("B: skipped (CHECK_MASTER=0; the master tables hold no contrasts for this run's arms)")
} else if (!file.exists(MASTER_TABLES) || !nrow(leads)) {
  okB <- FALSE
  say("CHECK B: FAIL (%s; pass MASTER_TABLES=, or CHECK_MASTER=0 for arms outside the master tables)",
      if (!file.exists(MASTER_TABLES)) paste(MASTER_TABLES, "does not exist") else "no leads over CHM-VWF")
} else {
  mc <- read.csv(MASTER_TABLES, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  lab <- c(census = "census, nearest census (headline)",
           box = "census, nearest census (headline) - nominal box on the same plots")
  lb <- leads[leads$plot_set == "all" & leads$kind == "observed" & leads$metric == "F1", ]
  nB <- 0; dB <- 0; unmatched <- character()
  for (i in seq_len(nrow(lb))) {
    l <- lb[i, ]
    fa <- paste0(l$detector, "|", l$rung); fb <- paste0(CN_BASE, "|", l$rung)
    z <- mc[mc$table == lab[[l$family]] & mc$scope == l$scope & mc$rung == l$rung & mc$metric == "F1" &
              ((mc$from == fb & mc$to == fa) | (mc$from == fa & mc$to == fb)), ]
    if (nrow(z) != 1) { unmatched <- c(unmatched, paste(l$family, l$scope, l$rung, l$detector)); next }
    theirs <- if (z$to == fa) c(z$estimate, z$lower, z$upper) else -c(z$estimate, z$upper, z$lower)
    dB <- max(dB, abs(c(l$estimate, l$lower, l$upper) - theirs)); nB <- nB + 1
  }
  pooled_scopes <- unmatched[grepl(" (five sites|California|Washington) ", unmatched)]
  okB <- nB > 0 && dB <= EPS && !length(pooled_scopes)
  say("B: %d observed F1 lead rows compared with %s; largest difference in estimate/lower/upper %s; %d rows without a contrast (%s)",
      nB, basename(MASTER_TABLES), cn_diff_text(dB, EPS), length(unmatched),
      if (length(unmatched)) paste(utils::head(unmatched, 6), collapse = "; ") else "none")
  say("CHECK B (observed leads equal the master tables): %s", if (okB) "PASS" else "FAIL")
}

## ---- diagnostics: detections in the scored areas, Monte Carlo error ------------------------
dg <- merge(obs[, c(KEYS, "n_det", "rect_n_det", "n_det_window")],
            nul[, c(KEYS, "n_det", "rect_n_det", "n_wrapped_interior")],
            by = KEYS, suffixes = c("_obs", "_null"))
dg <- merge(dg, geo[, c("site", "plot", "interior_area_m2", "window_area_m2")], by = c("site", "plot"))
dsum <- as.data.frame(as.data.table(dg)[, list(
  interior_det_obs = sum(n_det_obs), interior_det_null = sum(n_det_null),
  ratio_interior = sum(n_det_null) / sum(n_det_obs),
  box_det_obs = sum(rect_n_det_obs), box_det_null = sum(rect_n_det_null),
  ratio_box = sum(rect_n_det_null) / sum(rect_n_det_obs),
  dens_interior_obs = sum(n_det_obs) / sum(interior_area_m2),
  dens_window = sum(n_det_window) / sum(window_area_m2),
  wrapped_share_interior = sum(n_wrapped_interior) / sum(n_det_null)), by = c("rung", "detector")])
write.csv(dsum, outf("detections.csv"), row.names = FALSE)
POOLED_SCOPES <- intersect(c("five sites", names(MT_REGIONS)), names(SCOPES))
mcse <- do.call(rbind, lapply(unique(obs$rung), function(r) do.call(rbind, lapply(c("census", "box"), function(fam) {
  src <- if (fam == "census") CN_COUNTS else CN_RECT
  x <- as.data.frame(draws[draws$rung == r, c("site", "plot", "detector", "k", src), with = FALSE])
  names(x) <- c("site", "plot", "detector", "k", CN_COUNTS)
  do.call(rbind, lapply(POOLED_SCOPES, function(sc)
    cbind(rung = r, family = fam, scope = sc, cn_mc_se(x[x$site %in% SCOPES[[sc]], ]))))
}))))
write.csv(mcse, outf("mcse.csv"), row.names = FALSE)

## ---- tables --------------------------------------------------------------------------------
ARM_ORDER <- c("segmentanytree", "forestformer3d", "li2012", "treeisonet", "chm_vwf",
               "multichm", "lmfauto", "ptrees", "ams3d")
E <- function(ps, fam, sc, r, a, v, m = "F1")
  est[est$plot_set == ps & est$family == fam & est$scope == sc & est$rung == r & est$detector == a &
        est$variant == v & est$metric == m, , drop = FALSE]
L <- function(ps, fam, sc, r, a, k = "corrected", m = "F1")
  leads[leads$plot_set == ps & leads$family == fam & leads$scope == sc & leads$rung == r &
          leads$detector == a & leads$kind == k & leads$metric == m, , drop = FALSE]
ci <- function(z, signed = FALSE) if (!nrow(z)) "—" else cn_ci(z$estimate, z$lower, z$upper, signed)
rpf <- function(ps, fam, sc, r, a, v) paste(vapply(CN_METRICS, function(m)
  cn_num(E(ps, fam, sc, r, a, v, m)$estimate), ""), collapse = " / ")
md <- character(); emit <- function(...) md <<- c(md, sprintf(...))
fam_lab <- c(census = "Censused interior", box = "Nominal box, same plots")
rung_lab <- function(r) if (r == "native") "native density" else sprintf("rung %s", r)
emit("# Censused chance agreement: generated tables")
emit("")
emit("Declaration %s (%s); radius %g m; %d shifts; seed offset %d; minimum shift %g m.",
     basename(DECLARATION), declaration$name, TOL, K, SEED, MIN_SHIFT)
emit("Checks: %s.", paste(grep("^CHECK", log_lines, value = TRUE), collapse = "; "))
emit("")
for (r in unique(obs$rung)) {
  arms <- intersect(ARM_ORDER, unique(obs$detector[obs$rung == r]))
  for (fam in c("census", "box")) {
    np <- E("all", fam, "five sites", r, arms[1], "observed")$n_plots
    nr <- E("all", fam, "five sites", r, arms[1], "observed")$n_ref
    emit("## %s, %s, %g m, %d plots, %d references", fam_lab[[fam]], rung_lab(r), TOL, np, nr)
    emit("")
    emit("| Arm | Observed R / P / F1 | Null R / P / F1 | Null share of F1 | Corrected F1 | Corrected lead | Observed lead |")
    emit("| --- | --- | --- | --- | --- | --- | --- |")
    for (a in arms) emit("| %s | %s | %s | %s | %s | %s | %s |", CN_LABELS[[a]],
      rpf("all", fam, "five sites", r, a, "observed"), rpf("all", fam, "five sites", r, a, "null"),
      cn_num(E("all", fam, "five sites", r, a, "null_share")$estimate),
      ci(E("all", fam, "five sites", r, a, "corrected")),
      if (a == CN_BASE) "—" else ci(L("all", fam, "five sites", r, a), TRUE),
      if (a == CN_BASE) "—" else ci(L("all", fam, "five sites", r, a, "observed"), TRUE))
    emit("")
  }
  regs <- intersect(names(MT_REGIONS), names(SCOPES))
  if (length(regs)) {
    emit("## By region, %s, %g m (%s)", rung_lab(r), TOL, paste(sprintf("%s %d plots", regs,
      vapply(regs, function(g) E("all", "census", g, r, arms[1], "observed")$n_plots, 1)), collapse = ", "))
    emit("")
    emit("| Arm | %s |", paste(c(sprintf("Censused corrected F1, %s", regs), sprintf("Censused corrected lead, %s", regs),
                                  sprintf("Box corrected lead, %s", regs), sprintf("Censused observed lead, %s", regs)),
                                collapse = " | "))
    emit("|%s", strrep(" --- |", 1 + 4 * length(regs)))
    for (a in arms) emit("| %s | %s |", CN_LABELS[[a]], paste(c(
      vapply(regs, function(g) ci(E("all", "census", g, r, a, "corrected")), ""),
      vapply(regs, function(g) if (a == CN_BASE) "—" else ci(L("all", "census", g, r, a), TRUE), ""),
      vapply(regs, function(g) if (a == CN_BASE) "—" else ci(L("all", "box", g, r, a), TRUE), ""),
      vapply(regs, function(g) if (a == CN_BASE) "—" else ci(L("all", "census", g, r, a, "observed"), TRUE), "")),
      collapse = " | "))
    emit("")
  }
  emit("## Detections in the scored areas, %s, %g m (sums over plots)", rung_lab(r), TOL)
  emit("")
  emit("| Arm | Interior, observed | Interior, null mean | Null / observed | Box, observed | Box, null mean | Null / observed | Observed per m² in the interior | Per m² over the shift window | Interior null detections across the wrap |")
  emit("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
  for (a in arms) {
    z <- dsum[dsum$rung == r & dsum$detector == a, ]
    emit("| %s | %d | %.1f | %s | %d | %.1f | %s | %.4f | %.4f | %s |", CN_LABELS[[a]],
         as.integer(z$interior_det_obs), z$interior_det_null, cn_num(z$ratio_interior),
         as.integer(z$box_det_obs), z$box_det_null, cn_num(z$ratio_box), z$dens_interior_obs,
         z$dens_window, cn_num(z$wrapped_share_interior))
  }
  emit("")
}
rungs <- unique(obs$rung)
if (length(rungs) > 1) for (fam in c("census", "box")) for (what in c("corrected", "lead", "obs_null")) {
  emit("## %s, %s, %g m, by rung", fam_lab[[fam]], switch(what, corrected = "corrected F1",
       lead = "corrected F1 lead over CHM-VWF", obs_null = "observed F1 / null F1"), TOL)
  emit("")
  emit("| Arm | %s |", paste(vapply(rungs, rung_lab, ""), collapse = " | "))
  emit("|%s", strrep(" --- |", 1 + length(rungs)))
  for (a in ARM_ORDER[ARM_ORDER %in% obs$detector & ARM_ORDER != "li2012"]) emit("| %s | %s |", CN_LABELS[[a]],
    paste(vapply(rungs, function(r) switch(what,
      corrected = ci(E("all", fam, "five sites", r, a, "corrected")),
      lead = if (a == CN_BASE) "—" else ci(L("all", fam, "five sites", r, a), TRUE),
      obs_null = sprintf("%s / %s", cn_num(E("all", fam, "five sites", r, a, "observed")$estimate),
                         cn_num(E("all", fam, "five sites", r, a, "null")$estimate))), ""), collapse = " | "))
  emit("")
}
emit("## Plots with a censused reference outside the nominal box")
emit("")
emit("%d references in %d plots lie outside the nominal box (at most %.2f m); %d of them lie beyond the shift window (box + %g m).",
     sum(geo$n_ref_outside_box), nrow(outside), max(c(0, geo$max_ref_excess_m)),
     sum(geo$n_ref_outside_window), TOL)
emit("")
emit("| Plot | References outside the box | Largest distance outside (m) | Censused references |")
emit("| --- | --- | --- | --- |")
for (i in seq_len(nrow(outside))) emit("| %s | %d | %.2f | %d |", outside$plot[i],
  as.integer(outside$n_ref_outside_box[i]), outside$max_ref_excess_m[i], as.integer(outside$n_ref_census[i]))
emit("")
for (r in rungs) {
  arms <- intersect(ARM_ORDER, unique(obs$detector[obs$rung == r]))
  np <- E("inside_box", "census", "five sites", r, arms[1], "observed")$n_plots
  emit("### Without them, %s, %g m (%d plots)", rung_lab(r), TOL, np)
  emit("")
  emit("| Arm | Censused corrected F1, all | Censused corrected F1, without | Censused corrected lead, all | Censused corrected lead, without | Box corrected lead, all | Box corrected lead, without |")
  emit("| --- | --- | --- | --- | --- | --- | --- |")
  for (a in arms) emit("| %s | %s | %s | %s | %s | %s | %s |", CN_LABELS[[a]],
    ci(E("all", "census", "five sites", r, a, "corrected")),
    ci(E("inside_box", "census", "five sites", r, a, "corrected")),
    if (a == CN_BASE) "—" else ci(L("all", "census", "five sites", r, a), TRUE),
    if (a == CN_BASE) "—" else ci(L("inside_box", "census", "five sites", r, a), TRUE),
    if (a == CN_BASE) "—" else ci(L("all", "box", "five sites", r, a), TRUE),
    if (a == CN_BASE) "—" else ci(L("inside_box", "box", "five sites", r, a), TRUE))
  emit("")
}
emit("## Monte Carlo error of the pooled null F1 (five sites)")
emit("")
emit("| Rung | Scored area | Standard deviation over shifts | Standard error of the %d-shift mean |", K)
emit("| --- | --- | --- | --- |")
for (r in rungs) for (fam in c("census", "box")) {
  z <- mcse[mcse$rung == r & mcse$family == fam & mcse$scope == "five sites", ]
  emit("| %s | %s | %.4f to %.4f | %.4f to %.4f |", rung_lab(r), fam_lab[[fam]],
       min(z$F1_sd), max(z$F1_sd), min(z$F1_se), max(z$F1_se))
}
emit("")
emit("## Geometry")
emit("")
for (pt in unique(geo$plot_type)) {
  z <- geo[geo$plot_type == pt, ]
  emit("- %s plots (%d): interior %.0f m² on average (%.0f to %.0f), %.0f%% of the %.0f m² shift window (%.0f%% to %.0f%%); the nominal box is %.0f%% of it.",
       pt, nrow(z), mean(z$interior_area_m2), min(z$interior_area_m2), max(z$interior_area_m2),
       100 * mean(z$interior_area_m2 / z$window_area_m2), z$window_area_m2[1],
       100 * min(z$interior_area_m2 / z$window_area_m2), 100 * max(z$interior_area_m2 / z$window_area_m2),
       100 * z$box_area_m2[1] / z$window_area_m2[1])
}
emit("- Interior outside the shift window: %d plots, %.2f m² in total; interior plus %g m outside it: up to %.1f m² per plot.",
     sum(geo$interior_outside_window_m2 > 1e-6), sum(geo$interior_outside_window_m2), TOL,
     max(geo$reach_outside_window_m2))
writeLines(md, outf("tables.md"))
writeLines(log_lines, outf("checks.txt"))
cat(sprintf("wrote %s_* (%d cells) in %.1f s\n", file.path(OUT, PREFIX), nrow(obs),
            as.numeric(difftime(Sys.time(), t_start, units = "secs"))))
fails <- c(A = !okA, B = isFALSE(okB), C = !okC)
if (any(fails)) stop("Parity check ", paste(names(fails)[fails], collapse = ", "),
                     " failed; see ", outf("checks.txt"))
