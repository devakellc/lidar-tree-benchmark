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

# Analysis of the confirmation tests of the `multichm_gated` arm, as the
# protocol fixes them (docs/multichm-gated-confirmation-protocol.md). It
# changes no rule of the protocol; the library (multichm_gated_confirm_lib.R)
# documents the two places where the protocol's text admits two readings and
# reports both.
#
# Stages (STAGES=, comma-separated, default contrasts,r1,r4; tables only
# rewrites tables.md):
#   contrasts  for each dataset of the manifest, each level, scope and plot
#              subset: the five configurations' contrasts (declared minus
#              stock; declared minus floor and exemption; floor and exemption
#              minus floor; floor minus stock; declared minus gate everywhere;
#              declared minus CHM-VWF where present; floor and exemption minus
#              stock; gate everywhere minus stock) with both sides' plots,
#              stems, detections, F1 and corrected F1, and the paired change
#              with its 95% interval in corrected F1, F1, corrected precision,
#              corrected recall, precision and recall (plots resampled within
#              site, N_BOOT draws, the same draws for both sides and for
#              observed and null counts: mcg_contrast). Without a null the
#              corrected measures are NA. Each contrast is read with the
#              protocol's rule on its measure (corrected F1 with a null, F1
#              without); a scope under 10 plots is not read. Then the decision
#              table: the four conditions of "What each outcome allows" for the
#              declared configuration and for floor and exemption against stock,
#              the outcome, and the rule for which configuration is proposed,
#              with absent tests pending. -> OUT/contrasts.csv,
#              OUT/decision.csv, OUT/datasets.csv
#   r1         R1, selection with a region held out, on the calibration study's
#              cells (STUDY): the configuration with the highest corrected F1 at
#              native density on the California plots (mcg_select, ties to the
#              lowest config_id), scored against stock on the Washington plots
#              at every level, and the reverse. -> OUT/r1_selection.csv,
#              OUT/r1_ranking.csv, OUT/r1_ties.csv, OUT/r1_contrasts.csv
#   r4         R4, noise in the crown-spacing switch: every clip of the study's
#              candidate index at R4_RUNGS, read from the sealed root through
#              the study's provider, with mcg_crowns at 16 placements of the
#              1 m grid (points translated by 0, 0.25, 0.5, 0.75 m in x and y;
#              the unshifted placement must reproduce candidates.csv); the
#              declared configuration recomposed per placement from the cells
#              of gate everywhere (gated closed plots) and floor and exemption
#              (the others), first proven to reproduce the declared cells at
#              the unshifted spacing; then the spread of each clip's spacing,
#              the gated state per placement and the declared configuration's
#              pooled scores and change against stock per placement.
#              -> OUT/r4_crown_spacing.csv (+ .json, reused when it matches),
#              OUT/r4_checks.csv, OUT/r4_spread.csv, OUT/r4_state.csv,
#              OUT/r4_scores.csv, OUT/r4_ranges.csv
#   c3_share   the stand measures the protocol asks for on C3: per native clip
#              of the C3 candidate stages of the other flight (C3_EPOCH) and of
#              the 2021 clips of the same plots (C3_SHARED), the cover and
#              crown spacing of the stored candidates and the first-return
#              share of the deeper-layer peaks (mcgc_deep_shares, the
#              definition of confirm_gated_3dep.R), then per site and both
#              sites the medians on each side and the closed, widely spaced and
#              gated plots (mcgc_stand_transfer).
#              -> OUT/c3_deeper_share_plots.csv, OUT/c3_deeper_share.csv
#   c4_transfer  the same on C4 from confirm_gated_3dep.R's clips.csv in C4_DIR
#              (mcgc_c4_transfer: own density against the 2021 native clip,
#              thinned against the 2021 clip thinned to 2 points/m2), its
#              counts checked against that directory's transfer.csv.
#              -> OUT/c4_transfer.csv
#   c3_seeds   the bootstrap's own variation on C3: declared minus stock and
#              floor and exemption minus stock on the Washington scope of the
#              manifest's C3 dataset, redrawn with seeds BOOT_SEED + 1 to
#              BOOT_SEED + N_SEEDS (N_BOOT draws each), beside the reported
#              seed (offset 0). -> OUT/c3_seed_bounds.csv
# Every run then writes OUT/tables.md from the CSVs of the contrasts, r1 and
# r4 stages present in OUT.
#
# The manifest (MANIFEST=, JSON; format in multichm_gated_confirm_lib.R; the
# one the results use is docs/multichm-gated-confirmation-manifest.json):
#   {"datasets": [{"name": "calibration levels", "test": "baseline",
#     "cells": "multichm_gated_runs/neon/multichm_gated/cells.csv",
#     "levels": ["native", "8", "4", "2", "1"], "null": true,
#     "scoring": {"record": "cells.config.json", "tol": 4, "K": 200,
#                 "population": "adopted"},
#     "scopes": {"Five sites": ["SJER", "SOAP", "TEAK", "WREF", "ABBY"],
#                "California": ["SJER", "SOAP", "TEAK"],
#                "Washington": ["WREF", "ABBY"], "WREF": ["WREF"]},
#     "subsets": [{"name": "all plots"},
#                 {"name": "validation plots (seed 1)",
#                  "split": {"seed": 1, "frac": 0.5, "side": "valid"}}]}]}
# Relative cell paths resolve against CLAUDE_JOB_DIR. Before any contrast,
# each dataset's scoring record (of each of its parts, for a pooled file) is
# checked against the manifest's tol, K and population, and a pooled file
# against its parts; a missing record or a mismatch stops the run. The
# decision reads the scopes named "Five sites", "California" and
# "Washington" of the tests C1, C2, C3 and R2 on each dataset's decision
# subset (its first subset by default).
#
# Usage:
#   Rscript scripts/confirm_multichm_gated.R [STAGES=contrasts,r1,r4]
#     [MANIFEST=$CLAUDE_JOB_DIR/multichm_gated_confirmation/analysis/manifest.json]
#     [OUT=$CLAUDE_JOB_DIR/multichm_gated_confirmation/analysis]
#     [STUDY=$CLAUDE_JOB_DIR/multichm_gated_runs/neon/multichm_gated]
#     [FROZEN_ROOT=$CLAUDE_JOB_DIR/neon/frozen_2021] [N_BOOT=1000]
#     [BOOT_SEED=20261002] [SPLIT_SEED=1] [FRAC=0.5] [LEFT_OUT=C4,C5]
#     [R4_RUNGS=native,8,4,2,1] [R4_RECOMPUTE=FALSE] [N_SEEDS=40]
#     [C3_EPOCH=$CLAUDE_JOB_DIR/multichm_gated_confirmation/epoch_wa/epoch_2019]
#     [C3_EPOCH_LABEL=2019]
#     [C3_SHARED=$CLAUDE_JOB_DIR/multichm_gated_confirmation/epoch_wa/shared_2021]
#     [C4_DIR=$CLAUDE_JOB_DIR/multichm_gated_confirmation/3dep] [CORES=8]
# LEFT_OUT names tests (C4, C5) the protocol allows to be left out because
# their data could not be brought into the scorer; the decision then says so
# instead of keeping them pending. STUDY, FROZEN_ROOT, C3_EPOCH, C3_SHARED,
# C4_DIR and the cells are only read; OUT may not lie inside them.
suppressMessages({ library(data.table); library(lidR); library(sf) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))          # plot_lapply
source(.find("model_bench_lib.R"))    # frozen_clip, frozen_stamp_check, assert_detection_contract
source(.find("calval_lib.R"))         # plot_table, assign_split
source(.find("master_tables_lib.R"))  # mt_plot_weights, mt_interval, MT_N_BOOT, MT_SEED
source(.find("multichm_gated_lib.R"))
source(.find("multichm_gated_confirm_lib.R"))

CF_CA <- c("SJER", "SOAP", "TEAK")
CF_WA <- c("WREF", "ABBY")
CF_FIVE <- c(CF_CA, CF_WA)
CF_R4_SCOPES <- list(`Five sites` = list(sites = CF_FIVE), Washington = list(sites = CF_WA),
                     WREF = list(sites = "WREF"), ABBY = list(sites = "ABBY"))
CF_STAGES <- c("contrasts", "r1", "r4", "c3_share", "c4_transfer", "c3_seeds", "tables")

## ---- arguments ----------------------------------------------------------------------------
cf_settings <- function(args = commandArgs(TRUE), d = .job_dir()) {
  a <- strsplit(args, "=")
  A <- stats::setNames(lapply(a, `[`, 2), vapply(a, `[`, character(1), 1))
  get <- function(k, default) {
    v <- A[[k]]
    if (is.null(v) || is.na(v) || !nzchar(v)) default else v
  }
  split <- function(x) strsplit(x, ",")[[1]]
  out <- file.path(d, "multichm_gated_confirmation", "analysis")
  S <- list(d = d, OUT = get("OUT", out),
            STAGES = split(get("STAGES", "contrasts,r1,r4")),
            STUDY = get("STUDY", file.path(d, "multichm_gated_runs", "neon", "multichm_gated")),
            FROZEN_ROOT = get("FROZEN_ROOT", file.path(d, "neon", "frozen_2021")),
            N_BOOT = suppressWarnings(as.integer(get("N_BOOT", MT_N_BOOT))),
            BOOT_SEED = suppressWarnings(as.integer(get("BOOT_SEED", MT_SEED))),
            SPLIT_SEED = suppressWarnings(as.integer(get("SPLIT_SEED", 1L))),
            FRAC = suppressWarnings(as.numeric(get("FRAC", 0.5))),
            LEFT_OUT = if (is.null(A[["LEFT_OUT"]]) || !nzchar(A[["LEFT_OUT"]])) character()
                       else split(A[["LEFT_OUT"]]),
            R4_RUNGS = split(get("R4_RUNGS", "native,8,4,2,1")),
            R4_RECOMPUTE = toupper(get("R4_RECOMPUTE", "FALSE")) %in% c("TRUE", "1", "YES"),
            N_SEEDS = suppressWarnings(as.integer(get("N_SEEDS", 40L))),
            C3_EPOCH = get("C3_EPOCH", file.path(d, "multichm_gated_confirmation", "epoch_wa",
                                                 "epoch_2019")),
            C3_EPOCH_LABEL = get("C3_EPOCH_LABEL", "2019"),
            C3_SHARED = get("C3_SHARED", file.path(d, "multichm_gated_confirmation", "epoch_wa",
                                                   "shared_2021")),
            C4_DIR = get("C4_DIR", file.path(d, "multichm_gated_confirmation", "3dep")),
            CORES = suppressWarnings(as.integer(get("CORES", 8L))))
  S$MANIFEST <- get("MANIFEST", file.path(S$OUT, "manifest.json"))
  if (!all(S$STAGES %in% CF_STAGES))
    stop("STAGES are among ", paste(CF_STAGES, collapse = ", "), call. = FALSE)
  if (is.na(S$N_SEEDS) || S$N_SEEDS < 1) stop("N_SEEDS is a positive integer", call. = FALSE)
  if (identical(S$C3_EPOCH_LABEL, "2021"))
    stop("C3_EPOCH_LABEL names the other flight, not 2021", call. = FALSE)
  if (!all(S$LEFT_OUT %in% MCGC_QUALIFY))
    stop("LEFT_OUT may name only C4 and C5, the tests the protocol allows to leave out",
         call. = FALSE)
  if (anyNA(c(S$N_BOOT, S$BOOT_SEED, S$SPLIT_SEED, S$FRAC, S$CORES)) || S$N_BOOT < 1 ||
      S$FRAC <= 0 || S$FRAC >= 1 || S$CORES < 1)
    stop("invalid numeric argument (N_BOOT >= 1, BOOT_SEED, SPLIT_SEED, FRAC in (0, 1), ",
         "CORES >= 1)", call. = FALSE)
  # outputs never go into the study, the paper runs or a frozen root
  o <- normalizePath(S$OUT, mustWork = FALSE)
  inside <- function(p) {
    p <- normalizePath(p, mustWork = FALSE)
    identical(o, p) || startsWith(o, paste0(p, "/"))
  }
  if (inside(S$STUDY) || inside(S$FROZEN_ROOT) || inside(S$C3_EPOCH) || inside(S$C3_SHARED) ||
      inside(S$C4_DIR) ||
      grepl("/(multichm_gated_runs[^/]*|paper_runs[^/]*|neon/frozen_[^/]*)(/|$)", o))
    stop("OUT=", S$OUT, " lies inside read-only inputs", call. = FALSE)
  S
}

cf_write <- function(x, S, f) {
  write.csv(x, file.path(S$OUT, f), row.names = FALSE)
  cat(sprintf("  -> %s (%d rows)\n", file.path(S$OUT, f), nrow(x)))
}

## ---- stage: contrasts ---------------------------------------------------------------------
cf_dataset_row <- function(x, cells)
  data.frame(name = x$name, test = x$test, cells = x$cells,
             cells_sha256 = digest::digest(file = x$cells, algo = "sha256"),
             levels = paste(x$levels, collapse = ","), null = x$null,
             scopes = paste(sprintf("%s: %s%s", names(x$scopes),
                                    vapply(x$scopes, function(s) paste(s$sites, collapse = "+"), ""),
                                    vapply(x$scopes, function(s)
                                      if (is.null(s$plots)) "" else
                                        sprintf(" (%d plots)", length(s$plots)), "")),
                            collapse = "; "),
             subsets = paste(vapply(x$subsets, function(s) switch(s$kind,
               all = s$name, plots = sprintf("%s (%d plots)", s$name, length(s$plots)),
               split = sprintf("%s (seed %d, frac %g, %s)", s$name, s$seed, s$frac, s$side)), ""),
               collapse = "; "),
             decision_subset = x$decision_subset, n_rows = nrow(cells),
             n_plots = length(unique(mcgc_ids(cells))), stringsAsFactors = FALSE)

# How each dataset was scored, checked before any contrast: its record (or
# the record of each of its parts) against the manifest's scoring.
cf_check_scoring <- function(ds, tag = "contrasts") {
  for (x in ds) {
    rec <- mcgc_check_scoring(x)
    for (r in rec) cat(if (is.na(r$record))
      sprintf("[%s] %s: no scoring record (%s)\n", tag, x$name, r$why) else
        sprintf("[%s] %s: scored with K %s, tol %s, population %s (%s)\n", tag, x$name,
                format(r$K), format(r$tol), r$population, r$record))
    if (length(x$parts)) cat(sprintf("[%s] %s: the cells are the concatenation of %d parts\n",
                                     tag, x$name, length(x$parts)))
  }
  invisible(TRUE)
}

cf_stage_contrasts <- function(S) {
  ds <- mcgc_read_manifest(S$MANIFEST, base = S$d)
  cat(sprintf("[contrasts] %d dataset(s) from %s\n", length(ds), S$MANIFEST))
  cf_check_scoring(ds)
  con <- list(); info <- list()
  for (i in seq_along(ds)) {
    x <- ds[[i]]
    cells <- mcgc_read_cells(x$cells, null = x$null, levels = x$levels)
    if (is.null(x$levels)) x$levels <- unique(cells$rung)
    mcgc_check_listed(x, cells)
    ds[[i]] <- x
    sub_ids <- stats::setNames(lapply(x$subsets, mcgc_subset_ids, cells = cells),
                               vapply(x$subsets, `[[`, "", "name"))
    t0 <- Sys.time()
    r <- mcgc_dataset_contrasts(x, cells, sub_ids, S$N_BOOT, S$BOOT_SEED)
    cat(sprintf("[contrasts] %s (%s): %d plots, levels %s, %d contrast rows in %.1f s\n", x$name,
                x$test, length(unique(mcgc_ids(cells))), paste(x$levels, collapse = ","),
                if (is.null(r)) 0L else nrow(r), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    con[[i]] <- r
    info[[i]] <- cf_dataset_row(x, cells)
  }
  con <- do.call(rbind, con)
  if (is.null(con)) stop("no contrast rows", call. = FALSE)
  cf_write(do.call(rbind, info), S, "datasets.csv")
  cf_write(con, S, "contrasts.csv")
  dec <- mcgc_decide(con, ds, S$LEFT_OUT)
  cf_write(dec, S, "decision.csv")
  invisible(con)
}

## ---- stage: r1 ------------------------------------------------------------------------------
cf_study_cells <- function(S) mcgc_read_cells(file.path(S$STUDY, "cells.csv"), null = TRUE)
cf_study_index <- function(S) {
  idx <- read.csv(file.path(S$STUDY, "candidates.csv"), stringsAsFactors = FALSE,
                  colClasses = c(rung = "character", plot = "character"))
  frozen_stamp_check(file.path(S$STUDY, "candidates"), S$FROZEN_ROOT)
  idx
}

cf_stage_r1 <- function(S) {
  cells <- cf_study_cells(S)
  idx <- cf_study_index(S)
  levels <- unique(cells$rung)
  dirs <- list(list(on = "California", sites = CF_CA, held = "Washington", held_sites = CF_WA),
               list(on = "Washington", sites = CF_WA, held = "California", held_sites = CF_CA))
  sel_rows <- list(); rank_rows <- list(); tie_rows <- list(); con_rows <- list()
  for (dr in dirs) {
    s <- mcgc_r1_select(cells, dr$sites, "cF1")
    det <- mcgc_same_detections(file.path(S$STUDY, "candidates"), idx, s$plots, "native",
                                s$config_id, s$same_counts)
    R <- s$ranking
    pick <- R[R$config_id == s$config_id, ]; stock <- R[R$config == "stock", ]
    sel_rows[[length(sel_rows) + 1L]] <- data.frame(
      selected_on = dr$on, scored_on = dr$held, n_plots = length(s$plots),
      config_id = s$config_id, config = s$label, cF1_pick = pick$cF1, cF1_stock = stock$cF1,
      F1_pick = pick$F1, F1_stock = stock$F1, n_det_pick = pick$n_det, n_det_stock = stock$n_det,
      stock_rank = stock$rank, n_tied_score = length(s$tied_score),
      tied_score = paste(R$config[match(s$tied_score, R$config_id)], collapse = ";"),
      n_same_counts = length(s$same_counts), n_same_detections = length(det),
      same_detections = paste(R$config[match(det, R$config_id)], collapse = ";"),
      stringsAsFactors = FALSE)
    rank_rows[[length(rank_rows) + 1L]] <- cbind(
      data.frame(selected_on = dr$on, stringsAsFactors = FALSE),
      R[, c("rank", "config_id", "config", "cF1", "margin", "F1", "n_det", "precision", "recall")])
    # held out: the pick against stock at every level
    for (lv in levels) {
      L <- cells[cells$rung == lv, , drop = FALSE]; Lid <- mcgc_ids(L)
      plots <- unique(Lid[L$site %in% dr$held_sites])
      r <- mcgc_contrast_row(L, Lid, plots, s$label, "stock", S$N_BOOT, S$BOOT_SEED)
      if (is.null(r)) next
      rd <- mcgc_reading(r$lo_cF1, r$hi_cF1, r$n_plots)
      con_rows[[length(con_rows) + 1L]] <- cbind(
        data.frame(selected_on = dr$on, scored_on = dr$held, level = lv,
                   stringsAsFactors = FALSE), r, rd)
    }
    # the configurations tied with the pick on the selection plots, and what
    # each gives on the held-out plots at native density (point estimates)
    tied <- sort(unique(c(s$config_id, s$tied_score, s$same_counts)))
    N <- cells[cells$rung == "native" & cells$site %in% dr$held_sites &
                 cells$config_id %in% c(1L, tied), , drop = FALSE]
    P <- mcg_pool(N, "config_id")
    st <- P[P$config_id == 1L, ]
    tie_rows[[length(tie_rows) + 1L]] <- data.frame(
      selected_on = dr$on, config_id = tied, config = R$config[match(tied, R$config_id)],
      is_pick = tied == s$config_id, tied_score = tied %in% c(s$config_id, s$tied_score),
      same_counts = tied %in% c(s$config_id, s$same_counts),
      same_detections = tied %in% c(s$config_id, det),
      held_out_cF1 = P$cF1[match(tied, P$config_id)],
      held_out_d_cF1 = P$cF1[match(tied, P$config_id)] - st$cF1,
      held_out_d_F1 = P$F1[match(tied, P$config_id)] - st$F1, stringsAsFactors = FALSE)
    cat(sprintf("[r1] selected on %s (%d plots): %s, cF1 %.4f against stock %.4f; %d tied in score, %d with identical detections\n",
                dr$on, length(s$plots), s$label, pick$cF1, stock$cF1, length(s$tied_score),
                length(det)))
  }
  cf_write(do.call(rbind, sel_rows), S, "r1_selection.csv")
  cf_write(do.call(rbind, rank_rows), S, "r1_ranking.csv")
  cf_write(do.call(rbind, tie_rows), S, "r1_ties.csv")
  cf_write(do.call(rbind, con_rows), S, "r1_contrasts.csv")
}

## ---- stage: r4 ------------------------------------------------------------------------------
# The crown spacing of every clip at every placement, computed once and kept
# in OUT/r4_crown_spacing.csv with a record of what it was made from.
cf_r4_spacing <- function(S, idx, shifts) {
  f <- file.path(S$OUT, "r4_crown_spacing.csv"); fj <- paste0(f, ".json")
  rec <- list(clip_manifest_sha256 = frozen_root_id(S$FROZEN_ROOT),
              candidates_sha256 = digest::digest(file = file.path(S$STUDY, "candidates.csv"),
                                                 algo = "sha256"),
              placements = I(shifts$placement), rungs = I(sort(unique(idx$rung))),
              crown_res = MCG_CROWN_RES, crown_ws = MCG_CROWN_WS,
              cover_height = MCG_COVER_HEIGHT)
  if (!S$R4_RECOMPUTE && file.exists(f) && file.exists(fj)) {
    old <- jsonlite::read_json(fj, simplifyVector = TRUE)
    same <- identical(old$clip_manifest_sha256, rec$clip_manifest_sha256) &&
      identical(old$candidates_sha256, rec$candidates_sha256) &&
      identical(as.character(old$placements), as.character(rec$placements)) &&
      identical(as.character(old$rungs), as.character(rec$rungs)) &&
      identical(as.numeric(c(old$crown_res, old$crown_ws, old$cover_height)),
                as.numeric(c(rec$crown_res, rec$crown_ws, rec$cover_height)))
    if (same) {
      cat("[r4] crown spacing reused from ", f, "\n", sep = "")
      sp <- read.csv(f, stringsAsFactors = FALSE,
                     colClasses = c(rung = "character", plot = "character"))
      sp$crown_spacing <- mcgc_spacing(sp$crown_area, sp$n_crowns)   # full precision
      return(sp)
    }
  }
  jobs <- lapply(seq_len(nrow(idx)), function(i) idx[i, c("site", "plot", "rung", "cx", "cy",
                                                         "half")])
  cat(sprintf("[r4] %d clips x %d placements on %d workers\n", length(jobs), nrow(shifts),
              S$CORES))
  t0 <- Sys.time()
  res <- plot_lapply(jobs, mcgc_r4_worker, root = S$FROZEN_ROOT, shifts = shifts,
                     mc.cores = S$CORES)
  bad <- !vapply(res, is.data.frame, logical(1))
  if (any(bad)) stop("R4 failed on ", sum(bad), " clips", call. = FALSE)
  sp <- do.call(rbind, res)
  if (!identical(sp$crown_spacing, mcgc_spacing(sp$crown_area, sp$n_crowns)))
    stop("R4: crown spacing is not sqrt(area / n) as mcgc_spacing() assumes", call. = FALSE)
  cat(sprintf("[r4] crown spacing in %.1f min\n",
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  write.csv(sp, f, row.names = FALSE)
  jsonlite::write_json(rec, fj, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  sp
}

cf_stage_r4 <- function(S) {
  idx <- cf_study_index(S)
  idx <- idx[idx$rung %in% S$R4_RUNGS, , drop = FALSE]
  shifts <- mcgc_r4_shifts()
  sp <- cf_r4_spacing(S, idx, shifts)
  checks <- list()
  ## the unshifted placement against candidates.csv
  u <- sp[sp$dx == 0 & sp$dy == 0, , drop = FALSE]
  m <- merge(u, idx[c("site", "plot", "rung", "n_crowns", "crown_area", "crown_spacing")],
             by = c("site", "plot", "rung"), suffixes = c("", ".study"))
  # candidates.csv holds the spacing as write.csv wrote it (15 significant
  # digits): compare as that text
  dsp <- abs(m$crown_spacing - m$crown_spacing.study)
  ok_n <- sum(m$n_crowns == m$n_crowns.study & m$crown_area == m$crown_area.study)
  ok_s <- sum(sprintf("%.15g", m$crown_spacing) == sprintf("%.15g", m$crown_spacing.study))
  checks[[1]] <- data.frame(check = "unshifted crowns equal candidates.csv", n_cells = nrow(m),
                            n_pass = min(ok_n, ok_s), detail = sprintf(
                              "crown count and area identical in %d; spacing identical as stored (15 significant digits) in %d; largest absolute spacing difference %.3g",
                              ok_n, ok_s, max(dsp)), stringsAsFactors = FALSE)
  if (nrow(m) != nrow(idx) || ok_n != nrow(m) || ok_s != nrow(m))
    stop("R4: the unshifted crowns do not reproduce candidates.csv: ", checks[[1]]$detail,
         call. = FALSE)
  ## the recomposition at the unshifted spacing against the declared cells
  keep <- MCGC_CONFIGS[c("stock", "floor_exemption", "declared", "gate_everywhere")]
  cells <- cf_study_cells(S)
  cells <- cells[cells$config %in% keep & cells$rung %in% S$R4_RUNGS, , drop = FALSE]
  rec0 <- mcgc_recompose(cells, u)
  pr <- mcgc_compare_counts(rec0, cells[cells$config == MCGC_CONFIGS[["declared"]], ])
  checks[[2]] <- data.frame(check = "recomposed declared equals declared cells",
                            n_cells = pr$n_cells, n_pass = pr$n_cells - pr$n_mismatched_cells,
                            detail = sprintf("%d count columns, %d cells differ, largest absolute difference %g",
                                             pr$n_columns, pr$n_mismatched_cells,
                                             pr$max_abs_diff), stringsAsFactors = FALSE)
  if (pr$n_mismatched_cells > 0)
    stop("R4: the recomposition does not reproduce the declared cells: ", checks[[2]]$detail,
         call. = FALSE)
  cat("[r4] PASS", checks[[1]]$detail, "\n[r4] PASS", checks[[2]]$detail, "\n")
  cf_write(do.call(rbind, checks), S, "r4_checks.csv")
  ## spread and gated state
  cover <- unique(cells[c("site", "plot", "rung", "cover")])
  spread <- mcgc_r4_spread(sp, cover)
  cf_write(spread, S, "r4_spread.csv")
  cf_write(mcgc_r4_state(sp, cover), S, "r4_state.csv")
  ## scores per placement
  valid <- mcgc_split_ids(cf_study_cells(S), S$SPLIT_SEED, S$FRAC)$valid
  subsets <- list(`all plots` = NULL)
  subsets[[sprintf("validation plots (seed %d)", S$SPLIT_SEED)]] <- valid
  stock <- cells[cells$config == "stock", , drop = FALSE]
  rows <- list()
  for (p in shifts$placement) {
    rec <- mcgc_recompose(cells, sp[sp$placement == p, , drop = FALSE], label = "declared_r4")
    gated <- rec[c("site", "plot", "rung", "gated")]
    rec$gated <- NULL
    R <- rbind(rec, stock)
    for (lv in S$R4_RUNGS) {
      L <- R[R$rung == lv, , drop = FALSE]; Lid <- mcgc_ids(L)
      g <- gated[gated$rung == lv, , drop = FALSE]; gid <- mcgc_ids(g)
      for (sc in names(CF_R4_SCOPES)) for (sn in names(subsets)) {
        plots <- mcgc_scope_ids(unique(Lid), CF_R4_SCOPES[[sc]])
        if (!is.null(subsets[[sn]])) plots <- intersect(plots, subsets[[sn]])
        r <- mcgc_contrast_row(L, Lid, plots, "declared_r4", "stock", S$N_BOOT, S$BOOT_SEED)
        if (is.null(r)) next
        rows[[length(rows) + 1L]] <- cbind(
          data.frame(placement = p, dx = shifts$dx[shifts$placement == p],
                     dy = shifts$dy[shifts$placement == p], level = lv, scope = sc, subset = sn,
                     n_gated = sum(g$gated[gid %in% plots]), stringsAsFactors = FALSE), r)
      }
    }
  }
  sc <- do.call(rbind, rows)
  cf_write(sc, S, "r4_scores.csv")
  dt <- data.table::as.data.table(sc)
  rg <- dt[, list(n_plots = n_plots[1], n_gated_min = min(n_gated), n_gated_max = max(n_gated),
                  n_gated0 = n_gated[dx == 0 & dy == 0],
                  n_det_min = min(a_n_det), n_det_max = max(a_n_det),
                  F1_min = min(a_F1), F1_max = max(a_F1), F1_0 = a_F1[dx == 0 & dy == 0],
                  cF1_min = min(a_cF1), cF1_max = max(a_cF1), cF1_0 = a_cF1[dx == 0 & dy == 0],
                  d_cF1_min = min(d_cF1), d_cF1_max = max(d_cF1),
                  d_cF1_0 = d_cF1[dx == 0 & dy == 0], lo_cF1_0 = lo_cF1[dx == 0 & dy == 0],
                  hi_cF1_0 = hi_cF1[dx == 0 & dy == 0],
                  lo_cF1_min = min(lo_cF1), hi_cF1_max = max(hi_cF1),
                  d_F1_min = min(d_F1), d_F1_max = max(d_F1), d_F1_0 = d_F1[dx == 0 & dy == 0]),
           by = c("level", "subset", "scope")]
  cf_write(as.data.frame(rg), S, "r4_ranges.csv")
}

## ---- stage: c3_share ------------------------------------------------------------------------
# The first-return share of deeper-layer peaks on the C3 clips of the other
# flight and on the 2021 clips of the same plots, from the candidates the C3
# scoring stored, beside the cover and crown spacing of those candidates.
cf_stage_c3_share <- function(S) {
  sides <- c(S$C3_EPOCH, S$C3_SHARED)
  names(sides) <- c(S$C3_EPOCH_LABEL, "2021")
  plots <- do.call(rbind, lapply(names(sides), function(sd) {
    dir <- sides[[sd]]
    idx <- read.csv(file.path(dir, "candidates.csv"), stringsAsFactors = FALSE,
                    colClasses = c(rung = "character", plot = "character"))
    idx <- idx[idx$rung == "native", , drop = FALSE]
    cat(sprintf("[c3_share] %s: %d native clips from %s\n", sd, nrow(idx), dir))
    mcgc_clip_shares(idx, function(f) readRDS(file.path(dir, "candidates", f))$prep, sd)
  }))
  a <- plots[plots$side == S$C3_EPOCH_LABEL, , drop = FALSE]
  b <- plots[plots$side == "2021", , drop = FALSE]
  if (!setequal(paste(a$site, a$plot), paste(b$site, b$plot)))
    stop("C3: the two candidate sets hold different plots", call. = FALSE)
  tr <- mcgc_stand_transfer(a, b, c(stats::setNames(as.list(CF_WA), CF_WA),
                                    list(Washington = CF_WA)),
                            labels = c(S$C3_EPOCH_LABEL, "2021"))
  cf_write(plots, S, "c3_deeper_share_plots.csv")
  cf_write(tr, S, "c3_deeper_share.csv")
}

## ---- stage: c4_transfer ---------------------------------------------------------------------
# The stand measures of the 3DEP clips beside the 2021 values of the same
# plots, from the clip record of confirm_gated_3dep.R; the closed, widely
# spaced and gated counts must equal its transfer.csv.
cf_stage_c4_transfer <- function(S) {
  clips <- read.csv(file.path(S$C4_DIR, "clips.csv"), stringsAsFactors = FALSE,
                    colClasses = c(plot = "character", rung = "character"))
  scopes <- c(stats::setNames(as.list(CF_CA), CF_CA), list(California = CF_CA))
  tr <- mcgc_c4_transfer(clips, scopes)
  ref <- read.csv(file.path(S$C4_DIR, "transfer.csv"), stringsAsFactors = FALSE)
  m <- merge(tr, ref, by.x = c("variant", "scope"), by.y = c("variant", "scope"),
             suffixes = c("", ".ref"))
  cols <- c("plots", paste0(rep(c("closed", "spaced", "gated"), each = 3),
                            c("_3dep", "_2021", "_changed")))
  if (nrow(m) != nrow(tr) || nrow(m) != nrow(ref) ||
      !all(vapply(cols, function(k) all(m[[k]] == m[[paste0(k, ".ref")]]), NA)))
    stop("C4: the closed and gated counts differ from ", file.path(S$C4_DIR, "transfer.csv"),
         call. = FALSE)
  cat(sprintf("[c4_transfer] the counts of %d rows equal transfer.csv\n", nrow(tr)))
  cf_write(tr, S, "c4_transfer.csv")
}

## ---- stage: c3_seeds ------------------------------------------------------------------------
# The C3 primary contrast and floor and exemption against stock, both
# Washington sites, redrawn with the bootstrap seeds BOOT_SEED + 1 to BOOT_SEED
# + N_SEEDS (N_BOOT draws each), beside the reported seed (offset 0).
cf_stage_c3_seeds <- function(S) {
  ds <- Filter(function(d) identical(d$test, "C3"), mcgc_read_manifest(S$MANIFEST, base = S$d))
  if (length(ds) != 1L) stop("c3_seeds: the manifest needs exactly one C3 dataset", call. = FALSE)
  x <- ds[[1]]
  cf_check_scoring(list(x), "c3_seeds")
  if (is.null(x$scopes[["Washington"]])) stop("c3_seeds: the C3 dataset has no Washington scope",
                                              call. = FALSE)
  keep <- MCGC_CONFIGS[c("stock", "floor_exemption", "declared")]
  cells <- mcgc_read_cells(x$cells, null = x$null, levels = x$levels)
  cells <- cells[cells$config %in% keep, , drop = FALSE]
  sel <- mcgc_subset_ids(Filter(function(s) identical(s$name, x$decision_subset), x$subsets)[[1]],
                         cells)
  measure <- if (isTRUE(x$null)) "cF1" else "F1"
  pairs <- list(declared_stock = MCGC_CONFIGS[c("declared", "stock")],
                floor_exemption_stock = MCGC_CONFIGS[c("floor_exemption", "stock")])
  out <- list()
  for (lv in unique(cells$rung)) {
    L <- cells[cells$rung == lv, , drop = FALSE]; Lid <- mcgc_ids(L)
    plots <- mcgc_scope_ids(unique(Lid), x$scopes[["Washington"]])
    if (!is.null(sel)) plots <- intersect(plots, sel)
    r <- mcgc_seed_bounds(L, Lid, plots, pairs, S$BOOT_SEED + 0:S$N_SEEDS, S$N_BOOT, measure)
    out[[length(out) + 1L]] <- cbind(data.frame(dataset = x$name, test = x$test, level = lv,
                                                scope = "Washington", stringsAsFactors = FALSE),
                                     r)
  }
  out <- do.call(rbind, out)
  out$seed_offset <- out$seed - S$BOOT_SEED
  out$reported <- out$seed_offset == 0L
  for (k in names(pairs)) {
    v <- out[out$contrast == k & !out$reported, , drop = FALSE]
    cat(sprintf("[c3_seeds] %s, seeds +1 to +%d: lower bound %+.4f to %+.4f, above zero in %d\n",
                k, S$N_SEEDS, min(v$lo_measure), max(v$lo_measure), sum(v$lo_measure > 0)))
  }
  cf_write(out[c("dataset", "test", "level", "scope", "contrast", "config_a", "config_b",
                 "seed", "seed_offset", "reported", "n_boot", "n_plots", "measure", "d_measure",
                 "lo_measure", "hi_measure", "reading", "better", "not_worse", "worse")],
           S, "c3_seed_bounds.csv")
}

## ---- tables.md --------------------------------------------------------------------------------
cf_n <- function(x) ifelse(is.na(x), "NA", sub("^-", "−", sprintf("%+.3f", x)))
cf_p <- function(x) ifelse(is.na(x), "NA", sprintf("%.3f", x))
cf_iv <- function(lo, hi) sprintf("[%s, %s]", cf_n(lo), cf_n(hi))
cf_ci <- function(d, lo, hi) sprintf("%s %s", cf_n(d), cf_iv(lo, hi))
cf_int <- function(x) formatC(round(x), format = "d", big.mark = ",")
cf_wrap <- function(...) strwrap(paste0(...), width = 80)
cf_read <- function(S, f) {
  p <- file.path(S$OUT, f)
  if (!file.exists(p)) return(NULL)
  cc <- c(level = "character", rung = "character", plot = "character")
  hdr <- names(read.csv(p, nrows = 1L, check.names = FALSE))
  read.csv(p, stringsAsFactors = FALSE, colClasses = cc[names(cc) %in% hdr])
}
cf_md_table <- function(hdr, rows) c(paste0("| ", paste(hdr, collapse = " | "), " |"),
                                     paste0("|", paste(rep(" --- |", length(hdr)), collapse = "")),
                                     rows)

cf_md_contrasts <- function(v) {
  hdr <- c("Level", "Scope", "Plots", "Stems", "Detections, A / B", "F1, A / B",
           "Corrected F1, A / B", "Change in corrected F1", "Change in F1",
           "Change in corrected precision", "Change in corrected recall", "Change in precision",
           "Change in recall", "Reading")
  cf_md_table(hdr, sprintf(
    "| %s | %s | %d | %s | %s / %s | %s / %s | %s / %s | %s | %s | %s | %s | %s | %s | %s |",
    v$level, v$scope, as.integer(v$n_plots), cf_int(v$n_ref), cf_int(v$a_n_det),
    cf_int(v$b_n_det), cf_p(v$a_F1), cf_p(v$b_F1), cf_p(v$a_cF1), cf_p(v$b_cF1),
    cf_ci(v$d_cF1, v$lo_cF1, v$hi_cF1), cf_ci(v$d_F1, v$lo_F1, v$hi_F1),
    cf_ci(v$d_cPrecision, v$lo_cPrecision, v$hi_cPrecision),
    cf_ci(v$d_cRecall, v$lo_cRecall, v$hi_cRecall),
    cf_ci(v$d_precision, v$lo_precision, v$hi_precision),
    cf_ci(v$d_recall, v$lo_recall, v$hi_recall), v$reading))
}

cf_md <- function(S) {
  con <- cf_read(S, "contrasts.csv"); dec <- cf_read(S, "decision.csv")
  dsi <- cf_read(S, "datasets.csv")
  L <- c("# Gated multichm: confirmation analysis", "",
         cf_wrap("Made by scripts/confirm_multichm_gated.R on ", format(Sys.Date()),
                 " from the CSV files in this directory. The protocol is ",
                 "docs/multichm-gated-confirmation-protocol.md. Intervals are 95% ",
                 "percentile intervals of a paired bootstrap that resamples plots ",
                 "within site (", S$N_BOOT, " draws, seed ", S$BOOT_SEED, "), the ",
                 "same draws for both configurations and for observed and null ",
                 "counts. They are not adjusted for the number of contrasts."), "",
         cf_wrap("A contrast is read on corrected F1 where the dataset has a ",
                 "shift null and on F1 where it has none: better when its ",
                 "interval lies above zero, not worse when its lower bound is at ",
                 "least -0.02 (better included), worse when it lies below zero, ",
                 "inconclusive otherwise; a scope under 10 plots is not read. An ",
                 "interval inside [-0.02, 0) is both worse and not worse as the ",
                 "protocol words them and reads 'worse and not worse'."), "")
  if (!is.null(dsi)) L <- c(L, "## Datasets", "",
    cf_md_table(c("Dataset", "Test", "Levels", "Null", "Plots", "Scopes", "Subsets",
                  "Decision subset", "Cells"),
                sprintf("| %s | %s | %s | %s | %d | %s | %s | %s | `%s` |", dsi$name, dsi$test,
                        dsi$levels, ifelse(dsi$null, "yes", "no"), as.integer(dsi$n_plots),
                        dsi$scopes, dsi$subsets, dsi$decision_subset, dsi$cells)), "")
  if (!is.null(dec)) L <- c(L, "## Decision", "",
    cf_wrap("The conditions of 'What each outcome allows' and the rule for ",
            "which configuration is proposed, from the datasets present. ",
            "Condition 3 decides on C1 to C3, since the protocol says C4 and C5 ",
            "qualify the statement instead of deciding it; its literal wording ",
            "over C1 to C5 is reported in the row after it."), "",
    cf_md_table(c("Item", "Configuration", "Status", "Evidence"),
                sprintf("| %s | %s | %s | %s |", dec$item, dec$configuration, dec$status,
                        gsub("|", "/", dec$evidence, fixed = TRUE))), "")
  if (!is.null(con)) for (dn in unique(con$dataset)) {
    v <- con[con$dataset == dn, , drop = FALSE]
    L <- c(L, sprintf("## %s (%s)", dn, v$test[1]), "",
           cf_wrap("A minus B. Measure: ", if (v$measure[1] == "cF1") "corrected F1" else
             "F1 (no null: corrected measures are NA)", "."), "")
    for (su in unique(v$subset)) {
      L <- c(L, sprintf("### %s: %s", dn, su), "")
      for (k in MCGC_CONTRASTS$contrast) {
        w <- v[v$subset == su & v$contrast == k, , drop = FALSE]
        if (!nrow(w)) next
        ab <- MCGC_CONTRASTS[MCGC_CONTRASTS$contrast == k, ]
        L <- c(L, cf_wrap(sprintf("**%s.** A = %s (`%s`), B = %s (`%s`).", ab$what,
                                  MCGC_CONFIG_NAMES[[ab$a]], w$config_a[1],
                                  MCGC_CONFIG_NAMES[[ab$b]], w$config_b[1])), "",
               cf_md_contrasts(w), "")
      }
    }
  }
  L <- c(L, cf_md_r1(S), cf_md_r4(S))
  while (length(L) && !nzchar(L[length(L)])) L <- L[-length(L)]
  f <- file.path(S$OUT, "tables.md")
  writeLines(L, f)
  cat("  -> ", f, "\n", sep = "")
}

cf_md_r1 <- function(S) {
  s <- cf_read(S, "r1_selection.csv"); if (is.null(s)) return(character())
  rk <- cf_read(S, "r1_ranking.csv"); ti <- cf_read(S, "r1_ties.csv")
  cr <- cf_read(S, "r1_contrasts.csv")
  L <- c("## R1. Selection with a region held out", "",
         cf_wrap("The configuration with the highest corrected F1 at native ",
                 "density on one region's plots (mcg_select over the 447 grid ",
                 "configurations, ties to the lowest config_id), scored against ",
                 "stock on the other region's plots at every level. These are the ",
                 "calibration study's cells, not confirmation data; the first ",
                 "direction had been seen when the protocol was written."), "",
         cf_md_table(c("Selected on", "Plots", "Pick", "Corrected F1, pick / stock",
                       "F1, pick / stock", "Detections, pick / stock", "Stock's rank",
                       "Tied in corrected F1", "Same counts on every plot",
                       "Same detections on every plot"),
                     sprintf("| %s | %d | `%s` (id %d) | %.4f / %.4f | %.4f / %.4f | %s / %s | %d | %d | %d | %d (%s) |",
                             s$selected_on, as.integer(s$n_plots), s$config, as.integer(s$config_id),
                             s$cF1_pick, s$cF1_stock, s$F1_pick, s$F1_stock, cf_int(s$n_det_pick),
                             cf_int(s$n_det_stock), as.integer(s$stock_rank),
                             as.integer(s$n_tied_score), as.integer(s$n_same_counts),
                             as.integer(s$n_same_detections),
                             ifelse(nzchar(s$same_detections) & !is.na(s$same_detections),
                                    gsub(";", ", ", s$same_detections), "none"))), "")
  for (on in s$selected_on) {
    r <- rk[rk$selected_on == on & rk$rank <= 12, , drop = FALSE]
    L <- c(L, sprintf("Top of the ranking on the %s plots (margin = pick minus row):", on), "",
           cf_md_table(c("Rank", "config_id", "Configuration", "Corrected F1", "Margin", "F1",
                         "Detections"),
                       sprintf("| %d | %d | `%s` | %.4f | %.4f | %.4f | %s |", as.integer(r$rank),
                               as.integer(r$config_id), r$config, r$cF1, r$margin, r$F1,
                               cf_int(r$n_det))), "")
    t <- ti[ti$selected_on == on, , drop = FALSE]
    L <- c(L, cf_wrap(sprintf(paste("Configurations tied with the pick on the %s plots, and",
                                     "what each gives on the held-out plots at native density",
                                     "(point estimates against stock):"), on)), "",
           cf_md_table(c("config_id", "Configuration", "Tied in score", "Same counts",
                         "Same detections", "Held-out corrected F1", "Change in corrected F1",
                         "Change in F1"),
                       sprintf("| %d | `%s`%s | %s | %s | %s | %.4f | %s | %s |",
                               as.integer(t$config_id), t$config, ifelse(t$is_pick, " (pick)", ""),
                               ifelse(t$tied_score, "yes", "no"), ifelse(t$same_counts, "yes", "no"),
                               ifelse(t$same_detections, "yes", "no"), t$held_out_cF1,
                               cf_n(t$held_out_d_cF1), cf_n(t$held_out_d_F1))), "")
  }
  hdr <- c("Selected on", "Scored on", "Level", "Plots", "Stems", "Detections, pick / stock",
           "F1, pick / stock", "Corrected F1, pick / stock", "Change in corrected F1",
           "Change in F1", "Change in corrected precision", "Change in corrected recall",
           "Reading")
  L <- c(L, "Held-out contrasts, pick minus stock:", "",
         cf_md_table(hdr, sprintf("| %s | %s | %s | %d | %s | %s / %s | %s / %s | %s / %s | %s | %s | %s | %s | %s |",
                                  cr$selected_on, cr$scored_on, cr$level, as.integer(cr$n_plots),
                                  cf_int(cr$n_ref), cf_int(cr$a_n_det), cf_int(cr$b_n_det),
                                  cf_p(cr$a_F1), cf_p(cr$b_F1), cf_p(cr$a_cF1), cf_p(cr$b_cF1),
                                  cf_ci(cr$d_cF1, cr$lo_cF1, cr$hi_cF1),
                                  cf_ci(cr$d_F1, cr$lo_F1, cr$hi_F1),
                                  cf_ci(cr$d_cPrecision, cr$lo_cPrecision, cr$hi_cPrecision),
                                  cf_ci(cr$d_cRecall, cr$lo_cRecall, cr$hi_cRecall), cr$reading)),
         "")
  L
}

cf_md_r4 <- function(S) {
  ck <- cf_read(S, "r4_checks.csv"); if (is.null(ck)) return(character())
  sp <- cf_read(S, "r4_spread.csv"); st <- cf_read(S, "r4_state.csv")
  rg <- cf_read(S, "r4_ranges.csv")
  lv_order <- function(x) match(x, c("native", "8", "4", "2", "1"))
  L <- c("## R4. Noise in the crown-spacing switch", "",
         cf_wrap("Each clip's crown spacing (mcg_crowns, frozen) recomputed with ",
                 "its points translated by 0, 0.25, 0.5 and 0.75 m in x and in y, ",
                 "16 placements of the 1 m grid. Per placement the declared ",
                 "configuration is recomposed from existing cells: a closed plot ",
                 "(cover at least 0.6) with crowns at least 8 m apart takes the ",
                 "cells of gate everywhere, any other plot those of floor and ",
                 "exemption. Cover and crown spacing are each level's own."), "",
         cf_md_table(c("Check", "Cells", "Pass", "Detail"),
                     sprintf("| %s | %d | %d | %s |", ck$check, as.integer(ck$n_cells),
                             as.integer(ck$n_pass), gsub("|", "/", ck$detail, fixed = TRUE))),
         "")
  q <- function(x, p) unname(stats::quantile(x, p, names = FALSE, type = 7))
  rows <- character()
  for (lv in unique(sp$rung[order(lv_order(sp$rung))])) {
    s <- sp[sp$rung == lv, , drop = FALSE]
    groups <- c(list(`All plots` = rep(TRUE, nrow(s)), `Closed plots` = s$closed),
                lapply(stats::setNames(CF_FIVE, CF_FIVE), function(k) s$closed & s$site == k))
    for (g in names(groups)) {
      x <- s[groups[[g]], , drop = FALSE]
      if (!nrow(x)) next
      flip <- x$closed & x$n_gated > 0 & x$n_gated < x$n_placements
      rows <- c(rows, sprintf("| %s | %s | %d | %.2f / %.2f / %.2f / %.2f / %.2f | %.3f / %.3f / %.3f | %d | %d |",
                              lv, g, nrow(x), min(x$spacing_range), q(x$spacing_range, 0.5),
                              q(x$spacing_range, 0.75), q(x$spacing_range, 0.9),
                              max(x$spacing_range), q(x$spacing_sd, 0.5), q(x$spacing_sd, 0.9),
                              max(x$spacing_sd), sum(x$gated0 & x$closed), sum(flip)))
    }
  }
  L <- c(L, cf_wrap("A clip's spread over the 16 placements: the range (maximum ",
                    "minus minimum) and the standard deviation of its crown ",
                    "spacing, in m. Site rows hold that site's closed plots. ",
                    "'Gated unshifted' counts closed plots gated at the study's ",
                    "own grid; 'state changes' counts closed plots whose gated ",
                    "state differs from it in at least one placement."), "",
         cf_md_table(c("Level", "Group", "Clips", "Range: min / median / 75% / 90% / max",
                       "SD: median / 90% / max", "Gated unshifted", "State changes"), rows), "")
  st <- st[order(lv_order(st$rung), st$dx, st$dy), , drop = FALSE]
  L <- c(L, "Gated state per placement (closed plots that differ from the unshifted one):", "",
         cf_md_table(c("Level", "Placement (x, y in m)", "Closed", "Gated", "Differ",
                       "Gated to ungated", "Ungated to gated"),
                     sprintf("| %s | %g, %g | %d | %d | %d | %d | %d |", st$rung, st$dx, st$dy,
                             as.integer(st$n_closed), as.integer(st$n_gated),
                             as.integer(st$n_differ), as.integer(st$n_on_off),
                             as.integer(st$n_off_on))), "")
  rg <- rg[order(lv_order(rg$level), rg$subset != "all plots",
                 match(rg$scope, names(CF_R4_SCOPES))), , drop = FALSE]
  L <- c(L, cf_wrap("The declared configuration over the 16 placements: the range ",
                    "of its pooled F1 and corrected F1 and of its change against ",
                    "stock (point estimates), with the unshifted value and its ",
                    "interval, and the lowest lower bound and highest upper bound ",
                    "of the change in corrected F1 over the placements."), "",
         cf_md_table(c("Level", "Subset", "Scope", "Plots", "Gated plots, min to max (unshifted)",
                       "Detections, min to max", "F1, min to max (unshifted)",
                       "Corrected F1, min to max (unshifted)",
                       "Change in corrected F1, min to max", "Unshifted change in corrected F1",
                       "Lowest lower / highest upper bound", "Change in F1, min to max (unshifted)"),
                     sprintf("| %s | %s | %s | %d | %d to %d (%d) | %s to %s | %s to %s (%s) | %s to %s (%s) | %s to %s | %s | %s / %s | %s to %s (%s) |",
                             rg$level, rg$subset, rg$scope, as.integer(rg$n_plots),
                             as.integer(rg$n_gated_min), as.integer(rg$n_gated_max),
                             as.integer(rg$n_gated0), cf_int(rg$n_det_min), cf_int(rg$n_det_max),
                             cf_p(rg$F1_min), cf_p(rg$F1_max), cf_p(rg$F1_0), cf_p(rg$cF1_min),
                             cf_p(rg$cF1_max), cf_p(rg$cF1_0), cf_n(rg$d_cF1_min),
                             cf_n(rg$d_cF1_max), cf_ci(rg$d_cF1_0, rg$lo_cF1_0, rg$hi_cF1_0),
                             cf_n(rg$lo_cF1_min), cf_n(rg$hi_cF1_max), cf_n(rg$d_F1_min),
                             cf_n(rg$d_F1_max), cf_n(rg$d_F1_0))), "")
  L
}

## ---- main -----------------------------------------------------------------------------------
run_main <- function() {
  S <- cf_settings()
  dir.create(S$OUT, recursive = TRUE, showWarnings = FALSE)
  if ("contrasts" %in% S$STAGES) cf_stage_contrasts(S)
  if ("r1" %in% S$STAGES) cf_stage_r1(S)
  if ("r4" %in% S$STAGES) cf_stage_r4(S)
  if ("c3_share" %in% S$STAGES) cf_stage_c3_share(S)
  if ("c4_transfer" %in% S$STAGES) cf_stage_c4_transfer(S)
  if ("c3_seeds" %in% S$STAGES) cf_stage_c3_seeds(S)
  cf_md(S)
}

if (sys.nframe() == 0L) run_main()
