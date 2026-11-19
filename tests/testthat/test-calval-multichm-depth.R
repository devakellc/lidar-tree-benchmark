# Unit tests for the multichm_depth calibration/validation driver
# (scripts/calval_multichm_depth.R). Sourcing the script defines its helpers
# without running a stage (guarded by `if (sys.nframe() == 0L) cd_main()`); it
# sources the gated study's driver, which pulls in the gated library, the split
# helpers and the master-table resamples, and the depth library. Synthetic data
# only: no LiDAR, no NEON data, no file of a study run. The held-out (UNBLIND)
# analyses are exercised on synthetic cells with a mock validation set made of
# calibration plots.
source(file.path("..", "..", "scripts", "calval_multichm_depth.R"), local = TRUE)

## ---- synthetic scored cells -----------------------------------------------------------------
GRID <- mcd_grid()
# Rows of every grid configuration, the four gated references and chm_vwf for
# each site x plot x rung. Counts depend on the configuration so that pooled
# scores have no ties; config_id `best` is the best on every plot, and on the
# plots of `boost` the configuration `boost_id` is made far better (what a
# selection on other plots must not see).
syn_cells <- function(sites = c("SJER", "WREF"), n = 8, rungs = c("native", "1"), best = 17L,
                      boost = character(), boost_id = 200L) {
  out <- list()
  labels <- c(GRID$label, CD_REFERENCES, CD_CHM)
  fam <- c(rep("depth", nrow(GRID)), rep("gated", length(CD_REFERENCES)), "chm_vwf")
  cid <- c(GRID$config_id, rep(NA_integer_, length(CD_REFERENCES) + 1L))
  for (s in sites) for (i in seq_len(n)) for (rl in rungs) {
    pid <- sprintf("%s_%03d", s, i)
    id <- paste(s, pid, sep = "::")
    TP <- ifelse(fam == "depth", 10 + (cid %% 5) / 10, c(rep(9, 4), 8)[match(labels, c(
      CD_REFERENCES, CD_CHM))])
    TP[fam == "depth" & cid == best] <- 14
    TP[labels == CD_DECLARED] <- 11
    nd <- ifelse(fam == "depth", 30 + (cid %% 7), 32)
    if (id %in% boost) { TP[cid %in% boost_id] <- 24; nd[cid %in% boost_id] <- 24 }
    TP <- round(TP)
    nu <- if (i <= 4) 6 else 0
    k <- length(labels)
    out[[length(out) + 1L]] <- data.frame(
      site = s, plot = pid, plotType = if (i %% 2) "tower" else "distributed", rung = rl,
      cover = 0.5 + i / 20, top_height = 30 + i, crown_spacing = 5 + i / 2, pdens = 20,
      frdens = 10, family = fam, config = labels, config_id = cid,
      gated_config_id = c(rep(NA_integer_, nrow(GRID)), cd_gated_ids(), NA_integer_),
      depth_max = c(GRID$depth_max, rep(NA, 5)), near_2d = c(GRID$near_2d, rep(NA, 5)),
      zmin = c(GRID$zmin, rep(NA, 5)), zmin_surface = c(GRID$zmin_surface, rep(NA, 5)),
      lit_union = c(GRID$lit_union, rep(NA, 5)), cover_min = c(GRID$cover_min, rep(NA, 5)),
      n_dominant = 8 + i %% 3, n_codominant = 6, n_intermediate = nu, n_suppressed = 0,
      n_ref = 20 + i %% 3 + nu, n_over = 14 + i %% 3, n_under = nu, n_det = nd, TP = TP,
      tp_core = TP - 1, tp_over = TP - 2, tp_under = if (nu) 2 else 0, n_det0 = 0.9 * nd,
      TP0 = rep(4, k), tp_core0 = rep(3.5, k), tp_over0 = rep(3, k),
      tp_under0 = rep(if (nu) 1 else 0, k), stringsAsFactors = FALSE)
  }
  x <- do.call(rbind, out)
  rownames(x) <- NULL
  x
}
syn_settings <- function(...)
  utils::modifyList(list(SITES = c("SJER", "WREF"), RUNGS = c("native", "1"), SEED = 1L,
                         FRAC = 0.5, SEEDS = 1:3, N_BOOT = 40L, POP = "adopted"), list(...))
syn_plot_rows <- function(cells) unique(cells[CD_PLOT_COLS])

## ---- arguments --------------------------------------------------------------------------------
# A job directory whose gated run records the headline split (declared_config.json).
syn_job_dir <- function(seed = 1, frac = 0.5, drop = character()) {
  d <- tempfile("cd_job_")
  g <- file.path(d, "neon", "multichm_gated")
  dir.create(g, recursive = TRUE)
  r <- list(config_id = 360L, label = CD_DECLARED, seed = seed, frac = frac)
  r[drop] <- NULL
  jsonlite::write_json(r, file.path(g, "declared_config.json"), auto_unbox = TRUE)
  d
}

test_that("arguments parse as KEY=VALUE with blind defaults and at most 8 workers", {
  d <- syn_job_dir()
  S <- cd_settings(character(), d = d)
  expect_identical(S$STAGE, "all")
  expect_false(S$UNBLIND)
  expect_identical(S$SITES, CV_FIVE)
  expect_identical(S$RUNGS, c("native", "8", "4", "2", "1"))
  expect_identical(S$SEEDS, 1:200)
  expect_identical(c(S$SEED, S$CORES), c(1L, 8L))
  expect_identical(S$FRAC, 0.5)
  expect_identical(S$N_BOOT, MT_N_BOOT)
  expect_identical(S$OUT, CD_DEFAULT_OUT)
  expect_identical(S$GATED, file.path(d, "neon", "multichm_gated"))
  expect_true(cd_settings("UNBLIND=1", d = d)$UNBLIND)
  expect_false(cd_settings("UNBLIND=0", d = d)$UNBLIND)
  expect_identical(cd_settings("SEEDS=4,5", d = d)$SEEDS, 4:5)
  expect_error(cd_settings("UNBLIND=yes", d = d), "UNBLIND must be 0 or 1")
  expect_error(cd_settings("CORES=9", d = d), "at most 8")
  expect_error(cd_settings("STAGE=candidates", d = d), "STAGE must be")
  expect_error(cd_settings("RUNGS=8,4", d = d), "must include native")
  expect_error(cd_settings("RUNGS=native,3", d = d), "RUNGS must be among")
  expect_error(cd_settings("SEEDS=a", d = d), "invalid numeric")
  expect_error(cd_settings("SITES=HARV", d = d), "SITES must be among")
})

test_that("the headline split is the gated run's record, never an argument (A1)", {
  d <- syn_job_dir()
  # SEED= and FRAC= may only repeat the recorded values, whatever UNBLIND is
  for (u in c("0", "1")) {
    ub <- paste0("UNBLIND=", u)
    expect_error(cd_settings(c("SEED=2", ub), d = d), "SEED=2: the headline split")
    expect_error(cd_settings(c("FRAC=0.9", ub), d = d), "FRAC=0.9: the headline split")
    expect_error(cd_settings(c("SEED=7", "FRAC=0.5", ub), d = d), "SEED=7")
    expect_error(cd_settings(c("SEED=1.5", ub), d = d), "SEED=1.5")
    expect_error(cd_settings(c("FRAC=1", ub), d = d), "FRAC=1: the headline split")
    expect_error(cd_settings(c("SEED=one", ub), d = d), "SEED=one")
    S <- cd_settings(c("SEED=1", "FRAC=0.5", ub), d = d)
    expect_identical(c(S$SEED, S$FRAC), c(1L, 0.5))
  }
  expect_identical(cd_settings(c("SEED=1", "SEEDS=4,5"), d = d)$SEEDS, 4:5)
  # the values come from the record: another record moves them, arguments cannot
  d2 <- syn_job_dir(seed = 3, frac = 0.4)
  S2 <- cd_settings(character(), d = d2)
  expect_identical(c(S2$SEED, S2$FRAC), c(3L, 0.4))
  expect_error(cd_settings("SEED=1", d = d2), "SEED=1: the headline split")
  # GATED= names the run whose record is read
  expect_identical(cd_settings(paste0("GATED=", file.path(d2, "neon", "multichm_gated")),
                               d = d)$SEED, 3L)
  # no record, a missing or an invalid field: stop
  expect_error(cd_settings(character(), d = tempfile("cd_none_")), "no gated declared")
  expect_error(cd_settings(character(), d = syn_job_dir(drop = "seed")), "lacks a numeric `seed`")
  expect_error(cd_settings(character(), d = syn_job_dir(drop = "frac")), "lacks a numeric `frac`")
  expect_error(cd_settings(character(), d = syn_job_dir(seed = 1.5)), "whole seed")
  expect_error(cd_settings(character(), d = syn_job_dir(frac = 1)), "frac in \\(0, 1\\)")
})

test_that("a cells record of another split is refused (A1)", {
  S <- list(SEED = 1L, FRAC = 0.5)
  sp <- list(calib = c("SJER::SJER_001", "SJER::SJER_003", "WREF::WREF_002"),
             valid = c("SJER::SJER_002", "WREF::WREF_001"))
  r <- list(split = list(seed = 1L, frac = 0.5, plot_sets = cd_split_digests(sp)))
  expect_silent(cd_check_record_split(r, S, sp))
  expect_silent(cd_check_record_split(r, S))
  # the digests name no plot, and a site's sets are checked on their own
  expect_false(any(grepl("SJER_0", unlist(r$split$plot_sets))))
  expect_identical(names(r$split$plot_sets), c("SJER", "WREF"))
  sj <- lapply(sp, function(x) x[startsWith(x, "SJER")])
  expect_silent(cd_check_record_split(r, S, sj))
  bad <- r; bad$split$seed <- 2L
  expect_error(cd_check_record_split(bad, S, sp), "split seed 2, frac 0.5, not the headline")
  expect_error(cd_check_record_split(bad, S), "not the headline")
  bad <- r; bad$split$frac <- 0.6
  expect_error(cd_check_record_split(bad, S), "frac 0.6")
  bad <- r; bad$split <- NULL
  expect_error(cd_check_record_split(bad, S), "no record of their split")
  bad <- r; bad$split$plot_sets <- NULL
  expect_error(cd_check_record_split(bad, S, sp), "no record of the split's plot sets")
  expect_silent(cd_check_record_split(bad, S))
  # another plot set of the same seed and frac (a plot moved between the halves)
  sp2 <- list(calib = c(sp$calib[-1], sp$valid[1]), valid = c(sp$calib[1], sp$valid[-1]))
  expect_error(cd_check_record_split(r, S, sp2), "other calibration or validation plots of SJER")
  # a site the record does not hold
  sp3 <- list(calib = c(sp$calib, "ABBY::ABBY_001"), valid = sp$valid)
  expect_error(cd_check_record_split(r, S, sp3), "plots of ABBY")
})

## ---- the blind rule ---------------------------------------------------------------------------
test_that("the blind filter keeps only calibration plots until UNBLIND=1", {
  sp <- list(calib = c("A::1", "A::2", "B::1"), valid = c("A::3", "B::2"))
  expect_identical(cd_allowed_plots(sp), sp$calib)
  expect_identical(cd_allowed_plots(sp, TRUE), c(sp$calib, sp$valid))
  cells <- data.frame(site = c("A", "A", "A", "B", "B"), plot = c("1", "2", "3", "1", "2"),
                      v = 1:5)
  b <- cd_blind_filter(cells, sp)
  expect_identical(cv_ids(b), sp$calib)
  expect_identical(nrow(cd_blind_filter(cells, sp, TRUE)), 5L)
  # the score stage: blind -> the calibration plots (all again); unblinded ->
  # the plots not yet scored
  ids <- c("A::1", "A::2", "A::3", "B::1", "B::2")
  expect_identical(cd_plots_to_score(ids, sp), sp$calib)
  expect_identical(cd_plots_to_score(ids, sp, FALSE, done = sp$calib), sp$calib)
  expect_identical(cd_plots_to_score(ids, sp, TRUE, done = sp$calib), sp$valid)
  expect_identical(cd_plots_to_score(ids, sp, TRUE), ids)
  expect_error(cd_plots_to_score(c(ids, "C::9"), sp), "outside the split")
  expect_silent(cd_assert_blind(b, sp, FALSE))
  expect_error(cd_assert_blind(cells, sp, FALSE), "BLIND RULE")
  expect_silent(cd_assert_blind(cells, sp, TRUE))
})

test_that("UNBLIND=1 appends only to earlier cells of the same settings, else stops (A1)", {
  want <- list(grid = "g", constants = "k", root = "r", population = "adopted",
               gated_cells = "c", K = 200L, TOL = 4)
  r <- list(grid_sha256 = "g", constants_sha256 = "k", clip_manifest_sha256 = "r",
            population = "adopted", gated = list(cells_csv_sha256 = "c"), K = 200L, tol = 4L)
  expect_identical(cd_prior_mismatch(r, want), character())
  r2 <- r; r2$grid_sha256 <- "x"; r2$K <- 100L
  expect_identical(cd_prior_mismatch(r2, want), c("grid", "K"))
  r3 <- r; r3$gated <- NULL; r3$population <- "relaxed"
  expect_identical(cd_prior_mismatch(r3, want), c("population", "gated_cells"))
  # neither file: a first unblinded run scores every plot; one of the two: stop
  out <- tempfile("cd_prior_"); dir.create(out)
  S <- list(OUT = out, SEED = 1L, FRAC = 0.5, POP = "adopted")
  sp <- list(calib = "SJER::SJER_001", valid = "SJER::SJER_002")
  expect_null(cd_prior_cells(S, list(), sp))
  writeLines("site,plot", file.path(out, "cells.csv"))
  expect_error(cd_prior_cells(S, list(), sp), "is there without")
  unlink(file.path(out, "cells.csv"))
  writeLines("{}", file.path(out, CD_CELLS_CONFIG))
  expect_error(cd_prior_cells(S, list(), sp), "is there without")
  unlink(out, recursive = TRUE)
})

test_that("the cells check stops on a validation row while blind and counts chm_vwf rows", {
  cells <- syn_cells(n = 8)
  sp <- cv_split(syn_plot_rows(cells), 1L, 0.5)
  idx <- unique(cells[c("site", "plot", "rung")])
  key <- function(x) paste(x$site, x$plot, x$rung)
  chm <- unique(key(cells)[cells$family == "chm_vwf"])
  blind <- cd_blind_filter(cells, sp)
  expect_true(cd_check_cells(blind, idx, GRID, sp, FALSE, chm))
  expect_true(cd_check_cells(cells, idx, GRID, sp, TRUE, chm))
  # one row of a validation plot, of any family, stops a blind analysis
  vrow <- cells[cv_ids(cells) %in% sp$valid & cells$family == "depth", ][1, ]
  expect_error(cd_check_cells(rbind(blind, vrow), idx, GRID, sp, FALSE, chm), "BLIND RULE")
  vchm <- cells[cv_ids(cells) %in% sp$valid & cells$family == "chm_vwf", ][1, ]
  expect_error(cd_check_cells(rbind(blind, vchm), idx, GRID, sp, FALSE, chm), "BLIND RULE")
  # chm_vwf: exactly one row where the gated cells.csv has one, none elsewhere
  i <- which(blind$family == "chm_vwf")[1]
  expect_error(cd_check_cells(blind[-i, ], idx, GRID, sp, FALSE, chm), "chm_vwf row count")
  expect_error(cd_check_cells(rbind(blind, blind[i, ]), idx, GRID, sp, FALSE, chm),
               "chm_vwf row count")
  expect_error(cd_check_cells(blind, idx, GRID, sp, FALSE, setdiff(chm, key(blind[i, ]))),
               "chm_vwf row count")
  expect_true(cd_check_cells(blind[-i, ], idx, GRID, sp, FALSE, setdiff(chm, key(blind[i, ]))))
  # missing grid or reference rows
  j <- which(blind$family == "depth")[1]
  expect_error(cd_check_cells(blind[-j, ], idx, GRID, sp, FALSE, chm), "incomplete")
})

test_that("the score memo keys a detection set by x, y and z", {
  d1 <- data.frame(x = c(1, 2), y = c(3, 4), z = c(10, 20))
  d2 <- d1; d2$z[2] <- 20.5                       # the same tops at another height
  d3 <- d1; d3$x[1] <- 1.125
  expect_false(identical(cd_det_key(d1), cd_det_key(d2)))
  expect_false(identical(cd_det_key(d1), cd_det_key(d3)))
  expect_identical(cd_det_key(d1), cd_det_key(data.frame(x = c(1, 2), y = c(3, 4),
                                                        z = c(10, 20))))
  calls <- 0L
  f <- cd_memo(function(det) { calls <<- calls + 1L; sum(det$z) })
  expect_identical(f(d1), 30)
  expect_identical(f(d2), 30.5)                   # scored apart, not served from d1's entry
  expect_identical(calls, 2L)
  expect_identical(f(d1), 30)
  expect_identical(calls, 2L)
  expect_identical(f(d3), 30)
  expect_identical(calls, 3L)
})

test_that("features are refused without the current constants stamp or column radius (A7)", {
  fdir <- tempfile("cd_feat_"); dir.create(fdir)
  C <- data.table::data.table(X = c(0, 4), Y = c(0, 0), Z = c(20, 8), layer = c(1L, 2L),
                              ztop = c(20, 8.2), share = c(NA, 0.5))
  prep <- list(cand = C, cover = 0.8)
  rc <- mcd_col_radius(2)
  feat <- data.table::copy(C)
  feat[, `:=`(r_col = rc, col_top = c(20.5, 19), depth = c(0.5, 11), zrep = c(20.5, 8.2))]
  f <- cd_feature_file(fdir, "SJER", "SJER_001", "native")
  put <- function(...) {
    l <- list(site = "SJER", plot = "SJER_001", rung = "native", frdens = 2, r_col = rc,
              constants = mcd_constants(), constants_sha256 = cd_constants_digest(), feat = feat)
    a <- list(...)
    for (k in names(a)) l[[k]] <- a[[k]]
    saveRDS(l, f)
  }
  put()
  expect_equal(cd_read_feature(fdir, "SJER", "SJER_001", "native", prep)$feat, feat)
  fe <- readRDS(f); fe$constants_sha256 <- NULL; fe$constants <- NULL; saveRDS(fe, f)
  expect_error(cd_read_feature(fdir, "SJER", "SJER_001", "native", prep), "constants stamp")
  k <- mcd_constants(); k$MCD_MIN_FIRST <- 16
  put(constants = k, constants_sha256 = cd_constants_digest(k))
  expect_error(cd_read_feature(fdir, "SJER", "SJER_001", "native", prep), "other constants")
  put(r_col = mcd_col_radius(4))
  expect_error(cd_read_feature(fdir, "SJER", "SJER_001", "native", prep), "column radius")
  put(frdens = 1)
  expect_error(cd_read_feature(fdir, "SJER", "SJER_001", "native", prep), "column radius")
  f2 <- feat; f2$r_col <- 1
  put(feat = f2)
  expect_error(cd_read_feature(fdir, "SJER", "SJER_001", "native", prep), "column radius")
  put()
  expect_error(cd_read_feature(fdir, "SJER", "SJER_002", "native", prep), "no features")
  unlink(fdir, recursive = TRUE)
})

test_that("the analysis needs the specification and its addendum (A7, A9)", {
  dir <- tempfile("cd_spec_"); dir.create(dir)
  expect_error(cd_spec_record(dir), "not found")
  writeLines("spec", file.path(dir, CD_SPEC))
  expect_error(cd_spec_record(dir), "SPEC_ADDENDUM_1.txt")
  writeLines("addendum", file.path(dir, CD_ADDENDUM))
  expect_error(cd_spec_record(dir), "no recorded hash of the addendum")
  sha <- function(f) digest::digest(file = f, algo = "sha256")
  writeLines(c(paste0(sha(file.path(dir, CD_ADDENDUM)), "  ", CD_ADDENDUM), "2026-11-18"),
             file.path(dir, "SPEC_ADDENDUM_1.sha256"))
  r <- cd_spec_record(dir)
  expect_identical(r, list(specification_sha256 = sha(file.path(dir, CD_SPEC)),
                           addendum_sha256 = sha(file.path(dir, CD_ADDENDUM))))
  writeLines(paste0(strrep("0", 64), "  SPEC.txt"), file.path(dir, "SPEC.sha256"))
  expect_error(cd_spec_record(dir), "its record says")
  unlink(file.path(dir, "SPEC.sha256"))
  writeLines("addendum, changed", file.path(dir, CD_ADDENDUM))
  expect_error(cd_spec_record(dir), "its record says")
  unlink(dir, recursive = TRUE)
  # the provenance the outputs repeat carries the addendum's sentence (A9)
  expect_true(grepl(paste("The precedence of the reading rule, the chance-corrected reading of",
                          "the lowest-tree guard, the low-floor sibling, the closed- and",
                          "open-stand scopes and the confirmation datasets were fixed in",
                          "work/multichm_depth/SPEC_ADDENDUM_1.txt after the blind calibration",
                          "results and the code review had been read, and before any",
                          "validation cell of the depth family was scored."), CD_PROVENANCE,
                    fixed = TRUE))
  expect_true(startsWith(CD_PROVENANCE, "The family's form, its constants and its grid values"))
})

test_that("a selection on the calibration plots does not see the validation rows", {
  cells <- syn_cells()
  sp <- cv_split(syn_plot_rows(cells), 1L, 0.5)
  sel <- cd_select(cells, sp$calib)
  expect_identical(sel$config_id, 17L)
  expect_identical(sel$label, GRID$label[17])
  expect_setequal(sel$plots, sp$calib)
  # making another configuration best on every validation plot changes nothing,
  # and the blind filter drops those rows altogether
  boosted <- syn_cells(boost = sp$valid)
  expect_identical(cd_select(boosted, sp$calib)$config_id, 17L)
  expect_identical(cd_select(boosted, sp$valid)$config_id, 200L)
  blind <- cd_blind_filter(boosted, sp)
  expect_true(all(cv_ids(blind) %in% sp$calib))
  expect_identical(cd_select(blind, sp$calib)$config_id, 17L)
  expect_error(cd_select(blind, sp$valid), "no plots to select on")
})

test_that("selection ties go to the smaller config_id", {
  cells <- syn_cells(sites = "SJER", n = 4, rungs = "native", best = 999L)
  d <- cells$family == "depth"
  cells$TP[d] <- 10; cells$n_det[d] <- 30; cells$n_det0[d] <- 27
  expect_identical(cd_select(cells, unique(cv_ids(cells)))$config_id, 1L)
  cells$TP[d & cells$config_id %in% c(120L, 30L)] <- 15
  expect_identical(cd_select(cells, unique(cv_ids(cells)))$config_id, 30L)
})

test_that("the selection criterion is cF1, not F1, when the two disagree", {
  cells <- syn_cells(sites = "SJER", n = 4, rungs = "native", best = 999L)
  d <- cells$family == "depth"
  cells$TP[d] <- 10; cells$tp_core[d] <- 9; cells$n_det[d] <- 30; cells$n_det0[d] <- 27
  # id 30: fewer matches, little chance agreement; id 120: more matches, most by chance
  a <- d & cells$config_id == 30L; b <- d & cells$config_id == 120L
  cells$TP[a] <- 15; cells$tp_core[a] <- 14; cells$TP0[a] <- 4; cells$tp_core0[a] <- 3.5
  cells$TP[b] <- 16; cells$tp_core[b] <- 15; cells$TP0[b] <- 14; cells$tp_core0[b] <- 13
  plots <- unique(cv_ids(cells))
  nat <- cells[d, ]
  P <- mcg_pool(nat, "config_id")
  expect_identical(P$config_id[which.max(P$F1)], 120L)         # the F1 winner
  expect_identical(P$config_id[which.max(P$cF1)], 30L)         # the cF1 winner
  expect_identical(mcg_select(nat, plots, "F1"), 120L)
  expect_identical(CD_CRITERION, "cF1")
  sel <- cd_select(cells, plots)
  expect_identical(sel$config_id, 30L)
  expect_identical(cd_grid_ranking(cells, plots, GRID, sel)$config_id[1], 30L)
  # a fixed configuration in the selection's form (S_low's selection row)
  fx <- cd_config_of(cells, plots, 120L)
  expect_identical(c(fx$config_id, fx$label), c(120L, GRID$label[120]))
  expect_equal(fx$selected$F1, P$F1[P$config_id == 120L])
  expect_equal(fx$declared$cF1, sel$declared$cF1)
  row <- cd_selection_row(fx, CD_LOW_FLOOR, 1L, n_valid = 3L, criterion = CD_LOW_CRITERION)
  expect_identical(c(row$analysis, row$criterion, row$config), c("low_floor",
                                                                 "cRecall_under_10m",
                                                                 GRID$label[120]))
  expect_error(cd_config_of(cells, plots, 241L), "not in the grid")
})

## ---- grid ranking and components --------------------------------------------------------------
test_that("the calibration ranking ranks every grid configuration, the selection first", {
  cells <- syn_cells()
  sp <- cv_split(syn_plot_rows(cells), 1L, 0.5)
  sel <- cd_select(cells, sp$calib)
  r <- cd_grid_ranking(cells, sp$calib, GRID, sel)
  d <- r[r$family == "depth", ]
  expect_identical(nrow(d), 240L)
  expect_identical(d$rank, 1:240)
  expect_identical(d$config_id[1], 17L)
  expect_true(all(diff(d$cF1) <= 0))
  expect_identical(r$label[r$family != "depth"], c(CD_REFERENCES, CD_CHM))
  expect_true(all(is.na(r$rank[r$family != "depth"])))
  expect_true(all(r$n_cells == length(sp$calib)))
})

test_that("each configuration has eleven neighbours, one parameter changed each", {
  key <- function(i) c(near_2d = GRID$near_2d[i], depth_max = GRID$depth_max[i],
                       floor = paste(GRID$zmin[i], GRID$zmin_surface[i]),
                       lit_union = GRID$lit_union[i], cover_min = GRID$cover_min[i])
  for (id in c(1L, 2L, 16L, 61L, 120L, 121L, 177L, 240L)) {
    nb <- cd_component_neighbours(id)
    expect_identical(nrow(nb), 11L)
    expect_identical(as.vector(table(factor(nb$parameter, levels = CD_PARAMS))),
                     c(3L, 2L, 4L, 1L, 1L))
    expect_false(id %in% nb$config_id)
    expect_identical(nb$label, GRID$label[nb$config_id])
    for (i in seq_len(nrow(nb))) {
      differ <- names(which(key(id) != key(nb$config_id[i])))
      expect_identical(differ, nb$parameter[i])
    }
  }
  nb <- cd_component_neighbours(1L)
  expect_identical(nb$value[nb$parameter == "near_2d"], c("2.5", "3", "3.5"))
  expect_identical(nb$value[nb$parameter == "floor"], c("5/3", "5/5", "3/0", "3/3"))
  expect_identical(nb$config_id[nb$parameter == "cover_min"], 121L)
  expect_identical(nb$config_id[nb$parameter == "lit_union"], 16L)
  expect_error(cd_component_neighbours(241L), "not in the grid")
})

test_that("the lowest-tree configurations are stock, declared, S and S's other floors", {
  sel <- list(config_id = 1L, label = GRID$label[1])
  lc <- cd_lowest_configs(sel)
  expect_identical(vapply(lc, `[[`, "", "role"),
                   c("stock", "declared", "selected", "floor_5/3", "floor_5/5", "floor_3/0",
                     "floor_3/3"))
  expect_identical(vapply(lc, `[[`, "", "label"),
                   c("stock", CD_DECLARED, GRID$label[c(1, 4, 7, 10, 13)]))
  expect_identical(lc[[2]]$cfg, MCG_DECLARED)
  expect_identical(lc[[5]]$cfg, mcd_grid_config(GRID, 7))
})

## ---- reading rule -----------------------------------------------------------------------------
test_that("the reading rule applies A2's precedence: better, worse, not worse, inconclusive", {
  expect_identical(cd_verdict(0.001, 0.05), "better")
  expect_identical(cd_verdict(-0.019, 0.02), "not worse")
  expect_identical(cd_verdict(-0.02, 0.02), "inconclusive")
  expect_identical(cd_verdict(-0.05, -0.001), "worse")
  # an interval wholly below 0 reads "worse" whatever its lower bound (A2)
  expect_identical(cd_verdict(-0.015, -0.001), "worse")
  expect_identical(cd_verdict_note(-0.015, -0.001), "(within the 0.02 margin)")
  expect_identical(cd_verdict_note(-0.05, -0.001), "")
  expect_identical(cd_verdict_note(-0.019, 0.02), "")
  # boundaries: 0 is neither above nor below 0; -0.02 is not above -0.02
  expect_identical(cd_verdict(0, 0.03), "not worse")
  expect_identical(cd_verdict(-0.03, 0), "inconclusive")
  expect_identical(cd_verdict(-0.0199, 0), "not worse")
  expect_identical(cd_verdict(-0.02, -0.001), "worse")
  expect_identical(cd_verdict_note(-0.02, -0.001), "")
  expect_identical(cd_verdict_note(-0.0199, -1e-9), "(within the 0.02 margin)")
  expect_identical(cd_verdict(1e-12, 1), "better")
  expect_identical(cd_verdict(-1, -1e-12), "worse")
  expect_identical(cd_verdict(NA, 0.1), "undefined")
  expect_identical(cd_verdict(0.1, NA), "undefined")
  expect_identical(cd_verdict_note(NA, -0.01), "")
  expect_identical(cd_verdict(c(0.01, -0.01, -0.03), c(0.02, -0.001, 0.01)),
                   c("better", "worse", "inconclusive"))
  expect_true(cd_below_zero(-0.001))
  expect_false(cd_below_zero(0))
  # a scope of fewer than 10 plots is reported and not read
  expect_identical(cd_contrast_verdict(0.01, 0.02, 9), "not read (fewer than 10 plots)")
  expect_identical(cd_contrast_verdict(0.01, 0.02, 10), "better")
  expect_identical(cd_contrast_verdict(c(-0.015, -0.015), c(-0.001, -0.001), c(10, 3)),
                   c("worse", "not read (fewer than 10 plots)"))
  # every contrast row carries the reading
  v <- data.frame(lo_cF1 = c(0.01, -0.015, -0.015, NA, -0.03), hi_cF1 = c(0.02, -0.001, -0.001,
                                                                          0.1, 0.01),
                  n_plots = c(49, 49, 5, 49, 49))
  w <- cd_add_verdicts(v)
  expect_identical(w$verdict_cF1, c("better", "worse", "not read (fewer than 10 plots)",
                                    "undefined", "inconclusive"))
  expect_identical(w$verdict_note_cF1, c("", "(within the 0.02 margin)", "", "", ""))
  expect_identical(w$below_zero_cF1, c(FALSE, TRUE, TRUE, FALSE, FALSE))
  expect_identical(cd_verdict_text(w$verdict_cF1[1:2], w$verdict_note_cF1[1:2]),
                   c("better", "worse (within the 0.02 margin)"))
})

test_that("the lowest-tree guard is read on its chance-corrected interval (A3.c)", {
  expect_identical(cd_guard_reading(TRUE, -0.10, 0.05), "fewer chance matches, no detectable loss")
  expect_identical(cd_guard_reading(TRUE, -0.10, -0.01), "loses low trees")
  expect_identical(cd_guard_reading(FALSE, -0.10, -0.01), "loses low trees")
  expect_identical(cd_guard_reading(FALSE, -0.10, 0.10), "no detectable loss of low trees")
  expect_identical(cd_guard_reading(FALSE, 0.01, 0.10), "no detectable loss of low trees")
  expect_identical(cd_guard_reading(TRUE, -0.1, 0), "fewer chance matches, no detectable loss")
  expect_match(cd_guard_reading(TRUE, NA, NA), "^undefined")
})

test_that("S_low is offered only as A4 reads (i) and (ii)", {
  r <- cd_low_floor_reading("better", 0.01)
  expect_identical(c(r$i, r$ii), c(TRUE, TRUE))
  expect_identical(r$sentence, "S_low is offered as the lowest-tree variant")
  r <- cd_low_floor_reading("not worse", -0.01)
  expect_identical(c(r$i, r$ii), c(TRUE, FALSE))
  expect_match(r$sentence, "a matter of what counts as a tree, not of accuracy")
  expect_identical(cd_low_floor_reading("not worse", 0)$ii, FALSE)
  for (v in c("worse", "inconclusive", "undefined", CD_NOT_READ, NA))
    expect_identical(cd_low_floor_reading(v, 0.05)$sentence, "no low-floor variant is offered")
  expect_identical(cd_low_floor_reading("better", NA)$ii, FALSE)
})

## ---- per-stem matches -------------------------------------------------------------------------
test_that("stem matches follow score_plot on a hand-made plot", {
  stems <- data.frame(E = c(0, 5, 10, 0.8), N = c(0, 0, 0, 3.5), height = c(20, 4, 10, NA),
                      crown_class = c("dominant", "suppressed", "codominant", NA))
  det <- data.frame(x = c(0.5, 5.2, 5.5, 13.9, 30), y = c(0, 0, 0, 0, 0),
                    z = c(20, 25, 6, 10, 15))
  m <- mcd_stem_matches(stems, det, cx = 0, cy = 0, half = 10, tol = 4)
  # stem 1 takes the closest detection (0.5 m); stem 2 (4 m tall) cannot take
  # the 25 m apex (above 4 + 8) and takes the 6 m one; stem 3 the one 3.9 m
  # away; stem 4 (no height) is left with nothing within 4 m of an unused apex
  expect_identical(m$matched, c(TRUE, TRUE, TRUE, FALSE))
  expect_identical(m$det, c(1L, 3L, 4L, NA))
  expect_identical(m$det_z, c(20, 6, 10, NA))
  expect_identical(sum(m$matched), as.integer(score_plot(stems, det, tol_xy = 4, core_cx = 0,
                                                         core_cy = 0, core_half = 10)$TP))
  # the closest pair goes first: a stem without height 0.42 m from the first
  # apex takes it from the 20 m stem 0.5 m away, which is then left unmatched
  s2 <- stems; s2$N[4] <- 0.3
  m2 <- mcd_stem_matches(s2, det, 0, 0, 10, 4)
  expect_identical(m2$det, c(NA, 3L, 4L, 1L))
  expect_identical(sum(m2$matched), as.integer(score_plot(s2, det, tol_xy = 4, core_cx = 0,
                                                          core_cy = 0, core_half = 10)$TP))
  # a stem without height matches on position alone, whatever the apex height
  m3 <- mcd_stem_matches(stems[4, ], data.frame(x = 0.8, y = 3, z = 60), 0, 0, 10, 4)
  expect_true(m3$matched)
  # no detection: nothing matched
  m0 <- mcd_stem_matches(stems, det[0, ], 0, 0, 10, 4)
  expect_identical(m0$matched, rep(FALSE, 4))
})

test_that("stem matches equal score_plot's TP on random plots and the null means its TP0", {
  for (s in 1:12) {
    set.seed(s)
    n <- sample(5:30, 1); k <- sample(0:40, 1)
    stems <- data.frame(E = 500 + runif(n, -10, 10), N = 900 + runif(n, -10, 10),
                        height = ifelse(runif(n) < 0.2, NA, runif(n, 2, 35)),
                        crown_class = sample(c(CV_CLASSES, NA), n, TRUE))
    det <- data.frame(x = 500 + runif(k, -16, 16), y = 900 + runif(k, -16, 16),
                      z = runif(k, 2, 40))
    sc <- score_plot(stems, det, tol_xy = 4, core_cx = 500, core_cy = 900, core_half = 10)
    m <- mcd_stem_matches(stems, det, 500, 900, 10, 4)
    expect_identical(sum(m$matched), as.integer(sc$TP))
    offs <- mcg_null_offsets("SJER", sprintf("SJER_%03d", s), 10, tol = 4, k = 6)
    cell <- mcg_score_cell(stems, det, 500, 900, 10, offs, tol = 4)
    expect_identical(sum(m$matched), as.integer(cell$TP))
    expect_equal(sum(cd_null_matches(stems, det, 500, 900, 10, 4, offs)), cell$TP0,
                 tolerance = 1e-12)
  }
  expect_true(all(is.na(cd_null_matches(data.frame(E = 0, N = 0, height = 3),
                                        data.frame(x = 0, y = 0, z = 3), 0, 0, 10, 4,
                                        list()))))
})

test_that("CHECK S3 compares the stem table with the cells' TP, n_ref and TP0", {
  st <- data.frame(site = "SJER", plot = rep(c("P1", "P2"), c(3, 2)), config = "stock",
                   matched = c(TRUE, FALSE, TRUE, TRUE, TRUE), tp0 = c(0.5, 0.25, 0, 1, 0.5))
  cells <- data.frame(site = "SJER", plot = c("P1", "P2"), rung = "native", config = "stock",
                      n_ref = c(3, 2), TP = c(2, 2), TP0 = c(0.75, 1.5))
  ok <- cd_s3_compare(st, cells, data.frame(TP = 2, matched = 2, n_ref = 3, n_stems = 3))
  expect_identical(c(ok$n, ok$n_bad, ok$n_zrep_bad), c(2L, 0L, 0L))
  bad <- cells; bad$TP[2] <- 1
  expect_identical(cd_s3_compare(st, bad)$n_bad, 1L)
  bad <- cells; bad$TP0[1] <- 0.75 + 1e-6
  expect_identical(cd_s3_compare(st, bad)$n_bad, 1L)
  bad <- cells; bad$n_ref[1] <- 4
  expect_identical(cd_s3_compare(st, bad)$n_bad, 1L)
  expect_identical(cd_s3_compare(st, cells[1, ])$n_bad, 1L)     # a cell missing from cells
  expect_identical(cd_s3_compare(st, cells, data.frame(TP = 2, matched = 1, n_ref = 3,
                                                       n_stems = 3))$n_zrep_bad, 1L)
})

## ---- detections with their layers -------------------------------------------------------------
test_that("detections carry their candidates' layers and equal mcd_apply / mcg_apply", {
  C <- data.table::data.table(X = c(0, 1, 8, 8.5, 20, 30), Y = c(0, 0, 0, 0, 0, 5),
                              Z = c(20, 12, 15, 9, 6, 2.5), layer = c(1L, 2L, 1L, 3L, 2L, 1L),
                              ztop = c(20.2, 12.1, 15.3, 9, 6.4, 2.5),
                              share = c(NA, 0.8, NA, 0.2, 0.9, NA))
  feat <- data.table::copy(C)
  feat[, `:=`(r_col = 1, col_top = c(20.4, 19, 15.4, 15, 6.4, 2.5))]
  feat[, `:=`(depth = col_top - Z, zrep = c(20.4, 12.1, 15.4, 10, 6.4, 2.5))]
  prep <- list(cand = C, cover = 0.8, has_return_number = TRUE, crown_spacing = 10)
  for (cfg in list(mcd_config(4, 0, 5, 0, TRUE, 0.6), mcd_config(2, 3, 3, 3, FALSE, 0),
                   MCD_STOCK)) {
    d <- cd_detections(prep, feat, list(kind = "depth", cfg = cfg))
    expect_identical(d$det, mcd_apply(prep, feat, cfg))
    acc <- mcd_accepted(prep, feat, cfg)
    A <- feat[acc][order(-Z)]
    expect_identical(d$layer, A$layer)
    dr <- cd_detections(prep, feat, list(kind = "depth", cfg = cfg), "zrep")
    expect_identical(dr$det$z, A$zrep)
    expect_identical(dr$det[c("x", "y")], d$det[c("x", "y")])
  }
  g <- cd_detections(prep, feat, list(kind = "gated", cfg = MCG_STOCK))
  expect_identical(g$det, mcg_apply(prep, MCG_STOCK))
  expect_identical(g$layer, C$layer[match(g$det$x, C$X)])
  expect_error(cd_detections(prep, feat, list(kind = "gated", cfg = MCG_STOCK), "zrep"),
               "reports z = Z")
})

## ---- bands, lowest-tree and height tables -----------------------------------------------------
test_that("field heights fall in half-open bands; missing, negative and infinite are unknown", {
  expect_identical(cd_band(c(0, 4.999, 5, 9.999, 10, 19.99, 20, 70, NA, -0.1, Inf, NaN)),
                   c("[0,5)", "[0,5)", "[5,10)", "[5,10)", "[10,20)", "[10,20)", "[20,Inf)",
                     "[20,Inf)", "unknown", "unknown", "unknown", "unknown"))
  expect_identical(cd_band(logical(3)), rep("[0,5)", 3))
  expect_identical(cd_band(NA), "unknown")
  expect_identical(cd_class(c("dominant", "suppressed", NA, "other")),
                   c("dominant", "suppressed", "unknown", "unknown"))
})

# Stem rows of three configurations on four plots of two sites.
syn_stems <- function() {
  h <- c(3, 4, 7, 12, 25, NA)
  cc <- c("suppressed", "intermediate", "intermediate", "codominant", "dominant", NA)
  out <- list()
  for (s in c("SJER", "WREF")) for (p in 1:2) for (cfg in c("stock", CD_DECLARED, "S")) {
    m <- switch(cfg, stock = c(FALSE, FALSE, TRUE, TRUE, TRUE, FALSE),
                S = c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE),
                c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE))
    role <- if (cfg == "stock") "stock" else if (cfg == "S") "selected" else "declared"
    out[[length(out) + 1L]] <- data.frame(
      site = s, plot = sprintf("%s_%d", s, p), stem_id = paste0("t", 1:6), height = h,
      crown_class = cc, band = cd_band(h), class = cd_class(cc), role = role, config = cfg,
      matched = m, tp0 = rep(0.25, 6), stringsAsFactors = FALSE)
  }
  x <- do.call(rbind, out); rownames(x) <- NULL
  x
}

test_that("lowest-tree scores pool summed counts per band and class", {
  st <- syn_stems()
  plots <- unique(cv_ids(st))
  sc <- cd_lowest_scores(st, plots, "calib")
  one <- function(cfg, type, k) sc[sc$config == cfg & sc$type == type & sc$stratum == k, ]
  expect_identical(nrow(sc), 3L * nrow(cd_strata()))
  # S: [0,5) holds stems 1 and 2 of 4 plots, stem 1 matched
  r <- one("S", "band", "[0,5)")
  expect_identical(c(r$stems, r$matched), c(8L, 4L))
  expect_equal(r$recall, 0.5)
  expect_equal(r$TP0, 2)
  expect_equal(r$cRecall, (4 - 2) / (8 - 2))
  r <- one("S", "band_pooled", CD_LOW)
  expect_identical(c(r$stems, r$matched), c(12L, 8L))
  r <- one("stock", "band", "unknown")
  expect_identical(c(r$stems, r$matched), c(4L, 0L))
  r <- one(CD_DECLARED, "class", "intermediate")
  expect_identical(c(r$stems, r$matched), c(8L, 0L))
  expect_identical(one(CD_DECLARED, "all", "all")$stems, 24L)
  expect_identical(one("stock", "class", "unknown")$stems, 4L)
  expect_identical(unique(sc$role[sc$config == "S"]), "selected")
})

test_that("lowest-tree contrasts give the pooled difference and a paired interval", {
  st <- syn_stems()
  plots <- unique(cv_ids(st))
  k <- cd_lowest_contrast(st, plots, "S", CD_DECLARED, "calib", n_boot = 50)
  r <- k[k$stratum == CD_LOW, ]
  # S matches stems 1 and 3 of the three under 10 m on every plot, the declared arm none
  expect_equal(c(r$recall_a, r$recall_b, r$d_recall), c(8 / 12, 0, 8 / 12))
  expect_equal(r$d_cRecall, (8 - 3) / (12 - 3) - (0 - 3) / (12 - 3))
  # every plot holds the same stems and matches: every draw gives the same difference
  expect_equal(c(r$lo_recall, r$hi_recall), c(2 / 3, 2 / 3))
  expect_equal(k$d_recall[k$stratum == "[20,Inf)"], 0)
  self <- cd_lowest_contrast(st, plots, "S", "S", "calib", n_boot = 20)
  expect_true(all(self$d_recall[!is.na(self$d_recall)] == 0))
  # plots that differ between configurations give a real interval
  st2 <- st
  st2$matched[st2$config == "S" & st2$plot == "SJER_1" & st2$stem_id == "t2"] <- TRUE
  k2 <- cd_lowest_contrast(st2, plots, "S", CD_DECLARED, "calib", n_boot = 200)
  r2 <- k2[k2$stratum == "[0,5)", ]
  expect_equal(r2$d_recall, 5 / 8 - 0)
  expect_true(r2$lo_recall <= r2$d_recall && r2$hi_recall >= r2$d_recall)
  expect_true(r2$hi_recall > r2$lo_recall)
  # stems of another plot set stop the contrast when the configurations differ in stems
  bad <- st[!(st$config == "S" & st$stem_id == "t1"), ]
  expect_error(cd_lowest_contrast(bad, plots, "S", CD_DECLARED, "calib", n_boot = 10),
               "different stems")
})

test_that("lowest-tree scores carry plot-bootstrap intervals and the above-chance mark (A3)", {
  st <- syn_stems()
  plots <- unique(cv_ids(st))
  sc <- cd_lowest_scores(st, plots, "calib", n_boot = 50)
  new <- c("recall_lo", "recall_hi", "recall_draws", "cRecall_lo", "cRecall_hi", "cRecall_draws",
           "above_chance")
  expect_true(all(new %in% names(sc)))
  # the old columns come first and keep their values (A7: no score changes)
  expect_identical(names(sc)[1:12], c("kind", "split", "type", "stratum", "role", "config",
                                      "n_plots", "stems", "matched", "recall", "TP0", "cRecall"))
  one <- function(x, cfg, k) x[x$config == cfg & x$stratum == k, ]
  # every plot holds the same stems and matches: every draw gives the point estimate
  r <- one(sc, "S", CD_LOW)
  expect_equal(c(r$recall_lo, r$recall_hi), c(8 / 12, 8 / 12))
  expect_equal(c(r$cRecall, r$cRecall_lo, r$cRecall_hi), rep((8 - 3) / (12 - 3), 3))
  expect_identical(c(r$recall_draws, r$cRecall_draws), c(50L, 50L))
  expect_true(r$above_chance)
  r <- one(sc, CD_DECLARED, CD_LOW)                       # nothing under 10 m matched
  expect_equal(r$cRecall_hi, -3 / 9)
  expect_false(r$above_chance)
  r <- sc[sc$config == "stock" & sc$type == "band" & sc$stratum == "unknown", ]
  expect_false(r$above_chance)                            # n - TP0 = 3 > 0, none matched
  # plots that differ give a real interval around the estimate, from the same
  # weights as the contrasts (same plots, draws and seed)
  st2 <- st
  st2$matched[st2$config == "S" & st2$plot == "SJER_1" & st2$stem_id %in% c("t2", "t3")] <-
    c(TRUE, FALSE)
  sc2 <- cd_lowest_scores(st2, plots, "calib", n_boot = 200)
  r2 <- one(sc2, "S", "[0,5)")
  expect_true(r2$recall_lo <= r2$recall && r2$recall <= r2$recall_hi && r2$recall_hi > r2$recall_lo)
  expect_true(r2$cRecall_lo <= r2$cRecall && r2$cRecall <= r2$cRecall_hi)
  W <- mt_plot_weights(sub("::.*", "", plots), sub("^[^:]*::", "", plots), 200, MT_SEED)
  pc <- cd_plot_counts(st2, plots)
  pc <- pc[pc$config == "S" & pc$stratum == "[0,5)", ]
  pc <- pc[match(rownames(W), paste(pc$site, pc$plot, sep = "::")), ]
  iv <- mt_interval(drop(crossprod(W, pc$TP)) / drop(crossprod(W, pc$n)))
  expect_equal(c(r2$recall_lo, r2$recall_hi), c(iv$lower, iv$upper))
  expect_identical(cd_lowest_scores(st2, plots, "calib", n_boot = 200), sc2)
  # the contrasts carry the null recall TP0 / n of each side and its change
  k <- cd_lowest_contrast(st, plots, "S", CD_DECLARED, "calib", n_boot = 20)
  r <- k[k$stratum == CD_LOW, ]
  expect_equal(c(r$null_recall_a, r$null_recall_b, r$d_null_recall), c(0.25, 0.25, 0))
  st3 <- st; st3$tp0[st3$config == "S"] <- 0.5
  r3 <- cd_lowest_contrast(st3, plots, "S", CD_DECLARED, "calib", n_boot = 20)
  r3 <- r3[r3$stratum == CD_LOW, ]
  expect_equal(c(r3$null_recall_a, r3$d_null_recall), c(0.5, 0.25))
})

# Stem rows of S (config_id 52), its four floor siblings, the declared arm and
# stock on four plots; m: named list label -> matched flags of the six stems
# (heights 3, 4, 7, 12, 25, NA), the same on every plot.
syn_floor_stems <- function(m) {
  h <- c(3, 4, 7, 12, 25, NA)
  out <- list()
  for (s in c("SJER", "WREF")) for (p in 1:2) for (cfg in names(m)) {
    out[[length(out) + 1L]] <- data.frame(
      site = s, plot = sprintf("%s_%d", s, p), stem_id = paste0("t", 1:6), height = h,
      crown_class = "dominant", band = cd_band(h), class = "dominant",
      role = if (cfg == GRID$label[52]) "selected" else cfg, config = cfg, matched = m[[cfg]],
      tp0 = rep(0.25, 6), stringsAsFactors = FALSE)
  }
  x <- do.call(rbind, out); rownames(x) <- NULL
  x
}

test_that("S_low is S's floor sibling with the best chance-corrected recall under 10 m (A4)", {
  sel <- list(config_id = 52L, label = GRID$label[52])
  nb <- cd_component_neighbours(52L)
  fl <- nb[nb$parameter == "floor", ]
  expect_identical(fl$value, c("5/0", "5/3", "3/0", "3/3"))
  lab <- stats::setNames(c(sel$label, fl$label), c("5/5", fl$value))
  base <- c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE)
  mk <- function(...) {
    m <- stats::setNames(rep(list(base), 5), unname(lab))
    a <- list(...)
    for (k in names(a)) m[[lab[[k]]]] <- a[[k]]
    c(m, stats::setNames(list(base, base), c("stock", CD_DECLARED)))
  }
  plots <- c("SJER::SJER_1", "SJER::SJER_2", "WREF::WREF_1", "WREF::WREF_2")
  # S best: no S_low
  expect_null(cd_low_floor(syn_floor_stems(mk(`5/5` = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE))),
                           plots, sel))
  # all equal: the tie goes to the smaller zmin, then the smaller zmin_surface: 3/0
  s <- cd_low_floor(syn_floor_stems(mk()), plots, sel)
  expect_identical(c(s$label, s$config_id), c(lab[["3/0"]], GRID$config_id[GRID$label ==
                                                                                lab[["3/0"]]]))
  # 3/3 best: S_low is 3/3, with its value and the five candidates
  st <- syn_floor_stems(mk(`3/3` = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE)))
  s <- cd_low_floor(st, plots, sel)
  expect_identical(s$label, lab[["3/3"]])
  expect_identical(s$config_id, GRID$config_id[GRID$label == lab[["3/3"]]])
  expect_identical(c(s$zmin, s$zmin_surface, s$depth_max, s$near_2d, s$cover_min),
                   c(3, 3, 4, 2.5, 0.6))
  expect_false(s$lit_union)
  expect_equal(s$value, (12 - 3) / (12 - 3))
  expect_identical(s$candidates$label, unname(lab))
  expect_equal(s$candidates$cRecall_under_10m, c(rep((8 - 3) / 9, 4), 1))
  # a tie between S (5/5) and 5/0 goes to 5/0 (smaller zmin_surface): an S_low
  s <- cd_low_floor(syn_floor_stems(mk(`5/5` = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
                                       `5/0` = c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE))),
                    plots, sel)
  expect_identical(s$label, lab[["5/0"]])
  # a tie between 5/3 and 3/3 goes to 3/3 (smaller zmin)
  s <- cd_low_floor(syn_floor_stems(mk(`5/3` = rep(TRUE, 6), `3/3` = rep(TRUE, 6))), plots, sel)
  expect_identical(s$label, lab[["3/3"]])
  # only the calibration plots given are read: S_low of other plots may differ
  st <- syn_floor_stems(mk(`3/3` = rep(TRUE, 6)))
  st$matched[st$config == sel$label & st$site == "WREF"] <- TRUE
  st$matched[st$config == lab[["3/3"]] & st$site == "WREF"] <- FALSE
  expect_null(cd_low_floor(st, plots[3:4], sel))
  expect_identical(cd_low_floor(st, plots[1:2], sel)$label, lab[["3/3"]])
  # a sibling missing from the stem table stops
  expect_error(cd_low_floor(st[st$config != lab[["5/3"]], ], plots, sel), "lack")
  # the record of S_low in declared_depth_config.json
  r <- cd_low_floor_record(cd_low_floor(syn_floor_stems(mk(`3/3` = rep(TRUE, 6))), plots, sel))
  expect_true(r$exists)
  expect_identical(c(r$label, r$criterion), c(lab[["3/3"]], CD_LOW_CRITERION))
  expect_false(cd_low_floor_record(NULL)$exists)
})

test_that("closed and open stands are plot sets of the native cover (A5)", {
  cells <- syn_cells(n = 8)                       # cover 0.5 + i / 20: i = 1 open, i >= 2 closed
  plots <- unique(cv_ids(cells))
  sp <- cd_stand_plots(cells, plots)
  expect_identical(names(sp), CD_STAND_SCOPES)
  expect_setequal(sp[["Open stands"]], c("SJER::SJER_001", "WREF::WREF_001"))
  expect_identical(length(sp[["Closed stands"]]), 14L)  # cover exactly 0.6 (i = 2) is closed
  expect_true("SJER::SJER_002" %in% sp[["Closed stands"]])
  # the cover of the native cell decides; an unknown cover is open; a plot
  # without a native cell is in neither
  c2 <- cells
  c2$cover[c2$plot == "SJER_003" & c2$rung == "1"] <- 0.1
  c2$cover[c2$plot == "SJER_004" & c2$rung == "native"] <- NA
  c2 <- c2[!(c2$plot == "SJER_005" & c2$rung == "native"), ]
  s2 <- cd_stand_plots(c2, plots)
  expect_true("SJER::SJER_003" %in% s2[["Closed stands"]])
  expect_true("SJER::SJER_004" %in% s2[["Open stands"]])
  expect_false("SJER::SJER_005" %in% unlist(s2))
  expect_identical(cd_stand_plots(cells, plots[1:3]),
                   list(`Closed stands` = plots[2:3], `Open stands` = plots[1]))
  c3 <- cells; c3$cover[c3$plot == "SJER_006" & c3$rung == "native"][1] <- 0.99
  expect_error(cd_stand_plots(c3, plots), "disagree")
  # in the contrasts: native rows of both stand scopes; the other scopes as before
  S <- syn_settings()
  sel <- cd_select(cells, plots)
  rc <- cd_reference_contrasts(cells, plots, sel, S, "calib")
  st_rows <- rc$native[rc$native$scope %in% CD_STAND_SCOPES, ]
  expect_setequal(unique(st_rows$scope), CD_STAND_SCOPES)
  expect_true(all(st_rows$rung == "native"))
  expect_setequal(unique(st_rows$config_b), c(CD_REFERENCES, CD_CHM))
  expect_identical(unique(st_rows$n_plots[st_rows$scope == "Closed stands"]), 14L)
  expect_false(any(rc$ladder$scope %in% CD_STAND_SCOPES))
  ref <- cv_contrast_row(cells, cd_in_scope(plots, "SJER"), "native", sel$label, "stock",
                         S$N_BOOT, MT_SEED, cv_tag("reference", "cF1", "calib", "SJER", 1L))
  got <- rc$native[rc$native$scope == "SJER" & rc$native$config_b == "stock", ]
  rownames(got) <- NULL
  expect_identical(got[names(ref)], ref)
  cl <- cv_contrast_row(cells, sp[["Closed stands"]], "native", sel$label, CD_DECLARED,
                        S$N_BOOT, MT_SEED, cv_tag("reference", "cF1", "calib", "Closed stands",
                                                  1L))
  got <- rc$native[rc$native$scope == "Closed stands" & rc$native$config_b == CD_DECLARED, ]
  rownames(got) <- NULL
  expect_identical(got[names(cl)], cl)
  # the scopes of fewer than 10 plots are reported, not read; the others are read
  expect_true(all(rc$native$verdict_cF1[rc$native$n_plots < 10] == CD_NOT_READ))
  expect_false(any(rc$native$verdict_cF1[rc$native$n_plots >= 10] == CD_NOT_READ))
  expect_true(all(c("verdict_cF1", "verdict_note_cF1", "below_zero_cF1") %in% names(rc$ladder)))
})

test_that("stem height quantiles are per site and pooled, from one row per stem", {
  st <- syn_stems()
  q <-cd_stem_quantiles(st, unique(cv_ids(st)), "calib")
  expect_identical(q$site, c("SJER", "WREF", "all"))
  expect_identical(q$stems, c(12L, 12L, 24L))
  expect_identical(q$with_height, c(10L, 10L, 20L))
  expect_equal(q$min, c(3, 3, 3))
  h <- rep(c(3, 4, 7, 12, 25), 4)
  expect_equal(q$median[3], stats::median(h))
  expect_equal(q$q05[3], unname(stats::quantile(h, 0.05, type = 7)))
})

test_that("height errors are summarised by report and layer class", {
  pairs <- data.frame(site = "SJER", plot = "P", stem_id = paste0("t", 1:5),
                      report = c("z", "z", "z", "zrep", "zrep_on_z_matches"),
                      field_height = c(10, 20, 5, 10, 10), det_z = c(9, 22, 5.5, 10.5, 11),
                      layer = c(1L, 1L, 2L, 1L, 1L),
                      layer_class = c("surface", "surface", "deeper", "surface", "surface"))
  pairs$error <- pairs$det_z - pairs$field_height
  h <- cd_height_stats(pairs, "calib")
  expect_identical(nrow(h), 9L)
  a <- h[h$report == "z" & h$layer_class == "all", ]
  expect_identical(a$n, 3L)
  expect_equal(c(a$mean, a$median, a$rmse), c(0.5, 0.5, sqrt((1 + 4 + 0.25) / 3)))
  s <- h[h$report == "z" & h$layer_class == "surface", ]
  expect_equal(c(s$n, s$mean), c(2, 0.5))
  d <- h[h$report == "zrep" & h$layer_class == "deeper", ]
  expect_identical(d$n, 0L)
  expect_true(is.na(d$rmse))
})

## ---- CHECK S1 -----------------------------------------------------------------------------------
test_that("CHECK S1 wants observed counts equal and null means within 1e-9", {
  g <- syn_cells(sites = "SJER", n = 2, rungs = "native")
  g <- g[g$family == "gated", ]
  ok <- cd_s1_compare(g, g)
  expect_identical(c(ok$n, ok$n_bad), c(8L, 0L))
  m <- g; m$TP0[1] <- m$TP0[1] + 1e-10
  expect_identical(cd_s1_compare(m, g)$n_bad, 0L)
  m <- g; m$TP0[1] <- m$TP0[1] + 1e-7
  expect_identical(cd_s1_compare(m, g)$n_bad, 1L)
  m <- g; m$tp_core[2] <- m$tp_core[2] + 1
  expect_identical(cd_s1_compare(m, g)$n_bad, 1L)
  expect_identical(cd_s1_compare(g[-3, ], g)$n_bad, 1L)        # a row only in the gated cells
  expect_error(cd_s1_compare(rbind(g, g[1, ]), g), "duplicate")
})

## ---- the held-out analyses on a mock validation set (calibration plots only) ------------------
test_that("the UNBLIND analyses run on a mock split made of calibration plots only", {
  cells <- syn_cells(n = 16)        # enough plots for every stratum to split twice
  # every other plot an open stand (native cover under 0.6), so both stand
  # scopes hold plots of the mock validation set
  cells$cover[as.integer(sub(".*_", "", cells$plot)) %% 2 == 0] <- 0.3
  pr <- syn_plot_rows(cells)
  real <- cv_split(pr, 1L, 0.5)
  # the study's blind view: only the calibration plots, split again into a mock
  # calibration and a mock validation set
  blind <- cd_blind_filter(cells, real)
  prb <- pr[cv_ids(pr) %in% real$calib, ]
  mock <- cv_split(prb, 2L, 0.5)
  expect_true(length(mock$valid) > 0)
  expect_true(all(c(mock$calib, mock$valid) %in% real$calib))
  S <- syn_settings()
  sel <- cd_select(blind, mock$calib)
  # S_low: a floor sibling of S (its derivation from stems is tested above)
  fl <- cd_component_neighbours(sel$config_id)
  fl <- fl[fl$parameter == "floor", ][1, ]
  slow <- list(config_id = fl$config_id, label = fl$label)
  val <- cd_validation(blind, prb, mock, sel, S, slow = slow)
  v <- val$validation
  expect_true(all(v$split == "valid"))
  expect_identical(sum(v$primary), 1L)
  p <- v[v$primary, ]
  expect_identical(c(p$analysis, p$config_a, p$config_b, p$rung),
                   c("validation", sel$label, CD_DECLARED, "native"))
  expect_identical(p$n_plots, length(mock$valid))
  expect_identical(p$verdict_cF1, cd_contrast_verdict(p$lo_cF1, p$hi_cF1, p$n_plots))
  expect_true(all(c("verdict_cF1", "verdict_note_cF1", "below_zero_cF1") %in% names(v)))
  expect_true(all(c("verdict_cF1", "verdict_note_cF1", "below_zero_cF1") %in%
                    names(val$ladder)))
  # every reference in every scope at native density, the stand scopes included
  vs <- v[v$analysis == "validation", ]
  sc <- names(cd_scopes(S$SITES))
  expect_setequal(unique(vs$scope), c(sc, CD_STAND_SCOPES))
  expect_setequal(unique(vs$config_b), c(CD_REFERENCES, CD_CHM))
  expect_true(all(v$rung == "native"))
  # S_low against the declared arm, stock and S in every scope ("low_floor")
  vl <- v[v$analysis == CD_LOW_FLOOR, ]
  expect_true(all(vl$config_a == slow$label))
  expect_setequal(unique(vl$config_b), c(CD_DECLARED, "stock", sel$label))
  expect_setequal(unique(vl$scope), c(sc, CD_STAND_SCOPES))
  expect_false(any(vl$primary))
  # the ladder: the declared arm and stock at the other rung, and S_low's three
  ls <- val$ladder[val$ladder$analysis == "ladder", ]
  expect_true(all(val$ladder$rung == "1"))
  expect_setequal(unique(ls$config_b), c(CD_DECLARED, "stock"))
  ll <- val$ladder[val$ladder$analysis == "low_floor_ladder", ]
  expect_setequal(unique(ll$config_b), c(CD_DECLARED, "stock", sel$label))
  expect_true(all(ll$config_a == slow$label))
  expect_false(any(c(ls$scope, ll$scope) %in% CD_STAND_SCOPES))
  # components on the mock validation plots
  expect_identical(nrow(val$components), 11L)
  expect_true(all(val$components$split == "valid"))
  # seeds: one row per seed, drawn from the plots given (the calibration plots)
  expect_identical(val$seeds$seed, S$SEEDS)
  expect_true(all(val$seeds$n_calib_plots + val$seeds$n_valid_plots == nrow(prb)))
  expect_equal(val$seeds$d_declared_cF1,
               val$seeds$selected_cF1 - val$seeds$declared_cF1)
  ss <- val$seed_summary
  expect_identical(nrow(ss[ss$kind == "difference", ]), 8L)
  expect_setequal(unique(ss$parameter[ss$kind == "parameter"]),
                  c("cover_min", "near_2d", "lit_union", "floor", "depth_max"))
  for (pp in unique(ss$parameter[ss$kind == "parameter"]))
    expect_identical(sum(ss$n[ss$kind == "parameter" & ss$parameter == pp]), length(S$SEEDS))
  # leave one site out: each site against the declared arm and stock
  so <- val$site_out
  expect_identical(nrow(so), 4L)
  expect_setequal(so$held_out_site, S$SITES)
  # nothing outside the calibration plots was read: the mock validation plots
  # are calibration plots, and no analysis reaches a real validation plot
  expect_true(all(v$n_plots <= length(mock$valid)))
})

test_that("the blind analyses and their Markdown hold calibration rows only", {
  cells <- syn_cells(n = 16)
  cells$cover[as.integer(sub(".*_", "", cells$plot)) %% 2 == 0] <- 0.3   # open stands
  pr <- syn_plot_rows(cells)
  sp <- cv_split(pr, 1L, 0.5)
  blind <- cd_blind_filter(cells, sp)
  S <- syn_settings()
  sel <- cd_select(blind, sp$calib)
  cal <- cd_reference_contrasts(blind, sp$calib, sel, S, "calib")
  expect_true(all(cal$native$split == "calib"))
  expect_true(all(cal$native$n_plots <= length(sp$calib)))
  expect_identical(cal$native$config_b[1], CD_DECLARED)
  comp <- cd_component_rows(blind, sp$calib, sel, cd_component_neighbours(sel$config_id), S,
                            "calib")
  expect_identical(nrow(comp), 11L)
  expect_identical(comp$config_b, cd_component_neighbours(sel$config_id)$label)
  st <- syn_stems()
  st$config[st$config == "S"] <- sel$label
  # S_low (a floor sibling of S) matches every stem under 10 m
  fl <- cd_component_neighbours(sel$config_id)
  fl <- fl[fl$parameter == "floor", ][1, ]
  sl <- st[st$config == sel$label, ]
  sl$config <- fl$label; sl$role <- "floor_x"; sl$matched[sl$band %in% CD_BANDS[1:2]] <- TRUE
  st <- rbind(st, sl)
  slow <- list(config_id = fl$config_id, label = fl$label)
  low <- cd_lowest_tables(st, unique(cv_ids(st)), "calib", sel$label, 30, slow_label = slow$label)
  expect_setequal(unique(low$kind), c("score", "contrast", "stem_heights"))
  k <- low[low$kind == "contrast", ]
  expect_identical(unique(paste(k$config_a, k$config_b)),
                   paste(c(sel$label, sel$label, slow$label, slow$label, slow$label),
                         c(CD_DECLARED, "stock", CD_DECLARED, sel$label, "stock")))
  calibration_low <- cd_low_floor_contrasts(blind, sp$calib, slow, sel, S, "calib")
  expect_true(all(calibration_low$native$analysis == CD_LOW_FLOOR))
  expect_true(all(calibration_low$native$split == "calib"))
  expect_null(cd_low_floor_contrasts(blind, sp$calib, NULL, sel, S, "calib")$native)
  zc <- blind[blind$rung == "native" & blind$config == sel$label, ]
  zz <- zc; zz$config <- paste0(sel$label, CD_ZREP); zz$TP <- zz$TP - 1
  hk <- cv_contrast_row(rbind(zc, zz), sp$calib, "native", paste0(sel$label, CD_ZREP),
                        sel$label, 30, MT_SEED, cv_tag("zrep_minus_z", "cF1", "calib", "all", 1))
  expect_equal(hk$d_recall, -length(sp$calib) / sum(zc$n_ref))
  hk$kind <- "contrast"
  pairs <- data.frame(site = "SJER", plot = "SJER_001", stem_id = "t", report = "z",
                      field_height = 10, det_z = 11, layer = 1L, layer_class = "surface",
                      error = 1)
  heights <- as.data.frame(data.table::rbindlist(list(cd_height_stats(pairs, "calib"), hk),
                                                 fill = TRUE))
  selection <- rbind(cd_selection_row(sel, "headline", 1L, n_valid = 8L),
                     cd_selection_row(cd_config_of(blind, sp$calib, slow$config_id), CD_LOW_FLOOR,
                                      1L, n_valid = 8L, criterion = CD_LOW_CRITERION))
  res <- list(selected = sel, selection = selection,
              ranking = cd_grid_ranking(blind, sp$calib, GRID, sel), calibration = cal,
              components = comp, lowest = low, heights = heights, n_calib = length(sp$calib),
              n_valid = length(sp$valid), low_floor = c(slow, list(candidates = data.frame(
                config_id = c(sel$config_id, slow$config_id), label = c(sel$label, slow$label),
                zmin = 5, zmin_surface = 0, cRecall_under_10m = c(0.1, 0.2)))),
              calibration_low = calibration_low)
  md <- cd_tables_blind(res, S, list(clip_manifest_sha256 = "abc", K = 200L, tol = 4))
  flat <- function(x) gsub("\\s+", " ", paste(x, collapse = " "))
  expect_type(md, "character")
  expect_true(any(grepl("The family's form", md, fixed = TRUE)))
  expect_true(grepl("were fixed in work/multichm_depth/SPEC_ADDENDUM_1.txt", flat(md),
                    fixed = TRUE))
  expect_false(any(grepl("\\| valid \\|", md)))
  prose <- md[!startsWith(md, "|")]
  expect_true(all(nchar(prose) <= 80))
  expect_true(any(grepl(sprintf("`%s`", sel$label), md, fixed = TRUE)))
  # the in-sample guard (three lines), the lowest-tree intervals, S_low and the stands
  expect_true(grepl("In-sample (calibration plots): Guard (a), as fixed in section 6", flat(md),
                    fixed = TRUE))
  expect_true(grepl("Guard (b), chance-corrected (A3.b)", flat(md), fixed = TRUE))
  expect_true(grepl("Reading (A3.c): **", flat(md), fixed = TRUE))
  expect_true(any(grepl("| Above chance |", md, fixed = TRUE)))
  expect_true(any(grepl("## S_low, the low-floor sibling", md, fixed = TRUE)))
  expect_true(grepl(sprintf("S_low = `%s`", slow$label), flat(md), fixed = TRUE))
  expect_true(grepl("not the reading of A4", flat(md), fixed = TRUE))
  expect_true(any(grepl("| Closed stands |", md, fixed = TRUE)))
  expect_true(any(grepl("Reading of ΔcF1 (A2)", md, fixed = TRUE)))
  expect_true(any(grepl("| low_floor |", md, fixed = TRUE)))
  # without S_low the section says so
  res0 <- res; res0$low_floor <- NULL; res0$calibration_low <- NULL
  expect_true(grepl("No S_low", flat(cd_tables_blind(res0, S, list(clip_manifest_sha256 = "abc",
                                                                    K = 200L, tol = 4))),
                    fixed = TRUE))
  # the unblinded tables, on the mock split, carry the reading rule, the guard
  # read as A3 says and the reading of A4
  mock <- cv_split(pr[cv_ids(pr) %in% sp$calib, ], 2L, 0.5)
  val <- cd_validation(blind, pr[cv_ids(pr) %in% sp$calib, ], mock, sel, S, slow = slow)
  low2 <- rbind(low, transform(low, split = "valid"))
  res2 <- res; res2$lowest <- low2
  res2$heights <- rbind(heights, transform(heights, split = "valid"))
  md2 <- cd_tables_unblind(res2, val, S, list(clip_manifest_sha256 = "abc", K = 200L, tol = 4))
  expect_true(any(grepl("^Primary: selection minus the declared", md2)))
  expect_true(any(grepl("^Guard \\(a\\), as fixed in section 6: recall of the reference", md2)))
  expect_true(any(grepl("^Guard \\(b\\), chance-corrected", md2)))
  expect_true(any(grepl("^Reading \\(A3.c\\): \\*\\*", md2)))
  expect_true(grepl("Reading (A4): (i)", flat(md2), fixed = TRUE))
  expect_true(any(grepl("## S_low, the low-floor sibling (A4; validation plots)", md2,
                        fixed = TRUE)))
  expect_true(any(grepl("| Open stands |", md2, fixed = TRUE)))
  expect_true(all(nchar(md2[!startsWith(md2, "|")]) <= 80))
})

## ---- digests ------------------------------------------------------------------------------------
test_that("the grid and constants digests change with the grid and the constants", {
  d <- cd_grid_digest()
  expect_match(d, "^[0-9a-f]{64}$")
  g <- GRID; g$depth_max[5] <- 5
  expect_false(identical(cd_grid_digest(g), d))
  k <- mcd_constants(); expect_match(cd_constants_digest(k), "^[0-9a-f]{64}$")
  k$MCD_GAP <- 1.6
  expect_false(identical(cd_constants_digest(k), cd_constants_digest()))
  expect_identical(names(cd_ref_configs()), CD_REFERENCES)
  expect_identical(unname(cd_gated_ids()), c(1L, 46L, 70L, 360L))
})
