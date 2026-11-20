# Unit tests for the confirmation analysis of the multichm_gated arm
# (multichm_gated_confirm_lib.R): the protocol's labels and reading rule, the
# manifest and cells handling, the checks of how each dataset was scored (its
# record and a pooled file's parts, on temporary files), the contrasts, the
# decision table, the R1 selection wrapper, the R4 recomposition, placements
# and spread, the stand measures of C3 and C4 and the C3 seed bounds; and the
# driver (confirm_multichm_gated.R): its keys, its default manifest, its
# output guard, the scoring check of the contrasts stage and the count check of
# the c4_transfer stage, on temporary trees. Sourcing the driver runs nothing
# (it ends with `if (sys.nframe() == 0L) run_main()`).
# Synthetic data only: no LiDAR files, no NEON data.
suppressMessages({ library(lidR); library(data.table); library(sf) })
source(file.path("..", "..", "scripts", "calval_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "multichm_gated_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "multichm_gated_confirm_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "confirm_multichm_gated.R"), local = TRUE)

## ---- synthetic cells ------------------------------------------------------------------------
# The five configurations and CHM-VWF on every plot of `sites` (named plot
# counts) at `rungs`; counts vary a little by plot so the bootstrap has spread.
SYN_CFG <- data.frame(config = unname(MCGC_CONFIGS), config_id = c(1L, 2L, 30L, 360L, 70L, NA),
                      TP = c(10, 11, 12, 13, 12, 11), n_det = c(30, 26, 32, 27, 24, 22),
                      stringsAsFactors = FALSE)
syn_confirm_cells <- function(sites = c(SJER = 4, SOAP = 4, TEAK = 4, WREF = 6, ABBY = 6),
                              rungs = c("native", "8"), cfg = SYN_CFG) {
  out <- list()
  for (s in names(sites)) for (i in seq_len(sites[[s]])) for (rl in rungs) for (k in seq_len(nrow(cfg))) {
    TP <- cfg$TP[k] + (i %% 3) - (rl != "native"); nd <- cfg$n_det[k] + 2 * (i %% 2)
    out[[length(out) + 1L]] <- data.frame(
      site = s, plot = sprintf("%s_%03d", s, i), plotType = if (i %% 2) "tower" else "distributed",
      rung = rl, cover = if (s %in% c("WREF", "ABBY")) 0.9 else 0.4, crown_spacing = 6 + i,
      config = cfg$config[k], config_id = cfg$config_id[k],
      n_dominant = 8 + i %% 3, n_codominant = 6, n_intermediate = if (i <= 2) 6 else 0,
      n_suppressed = 0, n_ref = 20 + i, n_over = 14, n_under = 6, n_det = nd, TP = TP,
      tp_core = TP - 1, tp_over = TP - 2, tp_under = 2, n_det0 = 0.9 * nd, TP0 = 4 + i / 10,
      tp_core0 = 3.5, tp_over0 = 3, tp_under0 = 1, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

syn_spec <- function(null = TRUE, levels = c("native", "8")) list(
  name = "syn", test = "baseline", cells = "x", levels = levels, null = null,
  scopes = list(`Five sites` = list(sites = c("SJER", "SOAP", "TEAK", "WREF", "ABBY"),
                                    plots = NULL),
                California = list(sites = c("SJER", "SOAP", "TEAK"), plots = NULL),
                SJER = list(sites = "SJER", plots = NULL)),
  subsets = list(list(name = "all plots", kind = "all")), decision_subset = "all plots")

## ---- labels and the reading rule ------------------------------------------------------------
test_that("the protocol's configuration labels are the frozen library's", {
  expect_identical(MCGC_CONFIGS[["stock"]], mcg_config_label(MCG_STOCK))
  expect_identical(MCGC_CONFIGS[["floor"]], mcg_config_label(mcg_config(zmin = 5)))
  expect_identical(MCGC_CONFIGS[["floor_exemption"]],
                   mcg_config_label(mcg_config(zmin = 5, cover_min = 0.6, surface_exempt = TRUE)))
  expect_identical(MCGC_CONFIGS[["declared"]], mcg_config_label(MCG_DECLARED))
  expect_identical(MCGC_CONFIGS[["gate_everywhere"]],
                   mcg_config_label(mcg_config(5, 0.75, 0.6, TRUE, 0)))
  expect_true(all(MCGC_CONFIGS[1:5] %in% mcg_grid()$label))
  expect_true(all(c(MCGC_CONTRASTS$a, MCGC_CONTRASTS$b) %in% names(MCGC_CONFIGS)))
})

test_that("the reading rule labels each interval with the protocol's words", {
  r <- mcgc_reading(lo = c(0.01, -0.01, -0.05, -0.015, -0.05, -0.02, 0, 0.01, NA),
                    hi = c(0.05, 0.03, -0.03, -0.001, 0.02, 0.01, 0.02, 0.05, 0.1),
                    n_plots = c(10, 49, 30, 30, 30, 30, 30, 9, 30))
  expect_identical(r$reading, c("better", "not worse", "worse", "worse and not worse",
                                "inconclusive", "not worse", "not worse", "not read",
                                "undefined"))
  # better also satisfies not worse; the boundary -0.02 is not worse; a lower
  # bound on zero is not better
  expect_identical(r$better[1:7], c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(r$not_worse[1:7], c(TRUE, TRUE, FALSE, TRUE, FALSE, TRUE, TRUE))
  expect_identical(r$worse[1:7], c(FALSE, FALSE, TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_true(all(is.na(unlist(r[8:9, c("better", "not_worse", "worse")]))))
  expect_error(mcgc_reading(1, 1:2, 10), "one value per contrast")
})

## ---- manifest and cells ---------------------------------------------------------------------
write_manifest <- function(x) {
  f <- tempfile(fileext = ".json")
  jsonlite::write_json(x, f, auto_unbox = TRUE)
  f
}

SCORED_4 <- list(record = "cells.config.json", tol = 4, K = 200, population = "adopted")

test_that("the manifest reads datasets with defaults and resolves relative paths", {
  f <- write_manifest(list(datasets = list(
    list(name = "ql2", test = "C1", cells = "ql2/cells.csv", levels = list("ql2"), null = TRUE,
         scopes = list(`Five sites` = list("SJER", "WREF"), Washington = list("WREF"),
                       Few = list(sites = list("WREF"), plots = list("WREF::WREF_001"))),
         scoring = SCORED_4),
    list(name = "fgiemit", test = "C5", cells = "/abs/cells.csv", null = FALSE,
         scopes = list(`FGI-EMIT` = list("FGI")),
         subsets = list(list(name = "all plots"),
                        list(name = "half", split = list(seed = 3, side = "calib")),
                        list(name = "two", plots = list("FGI::p1", "FGI::p2"))),
         decision_subset = "two",
         scoring = list(record = "none", tol = 4, population = "labels",
                        why = "the scorer writes no such record")),
    list(name = "pooled", test = "C2", cells = "p/cells.csv", null = TRUE,
         scopes = list(California = list("SOAP")), scoring = SCORED_4,
         parts = list("a/cells.csv", "/abs/b/cells.csv")))))
  ds <- mcgc_read_manifest(f, base = "/job")
  expect_length(ds, 3L)
  expect_identical(ds[[1]]$scoring, list(record = "cells.config.json", tol = 4, K = 200L,
                                         population = "adopted", why = NULL))
  expect_null(ds[[1]]$parts)
  expect_identical(ds[[2]]$scoring$record, "none")
  expect_null(ds[[2]]$scoring$K)
  expect_identical(ds[[3]]$parts, c(file.path("/job", "a/cells.csv"), "/abs/b/cells.csv"))
  expect_identical(ds[[1]]$cells, file.path("/job", "ql2/cells.csv"))
  expect_identical(ds[[1]]$levels, "ql2")
  expect_identical(names(ds[[1]]$scopes), c("Five sites", "Washington", "Few"))
  expect_identical(ds[[1]]$scopes$Few$plots, "WREF::WREF_001")
  expect_null(ds[[1]]$scopes$Washington$plots)
  expect_identical(ds[[1]]$subsets, list(list(name = "all plots", kind = "all")))
  expect_identical(ds[[1]]$decision_subset, "all plots")
  expect_identical(ds[[2]]$cells, "/abs/cells.csv")
  expect_null(ds[[2]]$levels)
  expect_false(ds[[2]]$null)
  expect_identical(ds[[2]]$subsets[[2]][c("kind", "seed", "frac", "side")],
                   list(kind = "split", seed = 3L, frac = 0.5, side = "calib"))
  expect_identical(ds[[2]]$subsets[[3]]$plots, c("FGI::p1", "FGI::p2"))
  expect_identical(ds[[2]]$decision_subset, "two")
})

test_that("the manifest stops on what it cannot read unambiguously", {
  ok <- list(name = "a", test = "C1", cells = "c.csv", null = TRUE,
             scopes = list(`Five sites` = list("SJER")), scoring = SCORED_4)
  bad <- function(...) write_manifest(list(datasets = list(utils::modifyList(ok, list(...)))))
  expect_error(mcgc_read_manifest(bad(test = "C9"), "/j"), "tests are")
  expect_error(mcgc_read_manifest(bad(null = NULL), "/j"), "null: true or false")
  no_scopes <- ok; no_scopes$scopes <- list()
  expect_error(mcgc_read_manifest(write_manifest(list(datasets = list(no_scopes))), "/j"),
               "named scopes")
  unnamed <- ok; unnamed$scopes <- list(list("SJER"))
  expect_error(mcgc_read_manifest(write_manifest(list(datasets = list(unnamed))), "/j"),
               "named scopes")
  expect_error(mcgc_read_manifest(bad(nul = TRUE), "/j"), "unknown keys")
  expect_error(mcgc_read_manifest(bad(subsets = list(list(name = "x", splt = 1))), "/j"),
               "unknown keys")
  expect_error(mcgc_read_manifest(bad(subsets = list(list(name = "x", plots = list("p1")))),
                                  "/j"), "SITE::PLOT")
  expect_error(mcgc_read_manifest(bad(decision_subset = "nope"), "/j"), "decision_subset")
  expect_error(mcgc_read_manifest(write_manifest(list(datasets = list(ok, ok))), "/j"),
               "names repeat")
  expect_error(mcgc_read_manifest(write_manifest(list(sets = list(ok))), "/j"), "datasets")
  expect_error(mcgc_read_manifest(tempfile(), "/j"), "no file")
})

test_that("every dataset says how it was scored, and nothing passes unsaid", {
  ok <- list(name = "a", test = "R2", cells = "c.csv", null = TRUE,
             scopes = list(`Five sites` = list("SJER")), scoring = SCORED_4)
  rd <- function(d) mcgc_read_manifest(write_manifest(list(datasets = list(d))), "/j")
  sc <- function(...) { d <- ok; d$scoring <- utils::modifyList(SCORED_4, list(...)); d }
  no_scoring <- ok; no_scoring$scoring <- NULL
  expect_error(rd(no_scoring), "needs a scoring object")
  expect_error(rd(sc(radius = 4)), "unknown keys radius")
  expect_error(rd(sc(record = "../cells.config.json")), "file name beside")
  expect_error(rd(sc(tol = 0)), "positive tol")
  expect_error(rd(sc(tol = "4")), "positive tol")
  no_k <- ok; no_k$scoring$K <- NULL
  expect_error(rd(no_k), "needs an integer K")
  expect_error(rd(sc(K = 2.5)), "needs an integer K")
  without_null <- ok; without_null$null <- FALSE
  expect_error(rd(without_null), "takes no K")
  no_pop <- ok; no_pop$scoring$population <- NULL
  expect_error(rd(no_pop), "population")
  expect_error(rd(sc(record = "none")), "must say why")
  expect_identical(rd(sc(record = "none", why = "none written"))[[1]]$scoring$why,
                   "none written")
  one_part <- ok; one_part$parts <- list("x/cells.csv")
  expect_error(rd(one_part), "at least two files")
})

## ---- how the cells were scored ---------------------------------------------------------------
# A cells file with a scorer's record beside it, in its own temporary directory.
scored_dir <- function(record = list(K = 200, tol = 4, population = "adopted",
                                     clip_manifest_sha256 = "abc", grid_sha256 = "def"),
                       cells = data.frame(site = "S", plot = "p1", n = 1:2)) {
  d <- tempfile("scored_"); dir.create(d)
  f <- file.path(d, "cells.csv")
  write.csv(cells, f, row.names = FALSE)
  if (!is.null(record)) jsonlite::write_json(record, file.path(d, "cells.config.json"),
                                             auto_unbox = TRUE)
  f
}

test_that("the scoring record must match the manifest's tol, K and population", {
  f4 <- scored_dir()
  r <- mcgc_check_record(SCORED_4, f4)
  expect_identical(r$record, file.path(dirname(f4), "cells.config.json"))
  expect_identical(c(r$K, r$tol), c(200L, 4L))
  expect_identical(r$population, "adopted")
  expect_identical(r$clip_manifest_sha256, "abc")
  expect_identical(r$sha256, digest::digest(file = r$record, algo = "sha256"))
  # an R2 entry scored at 4 m, a C1 entry scored at 2 m
  expect_error(mcgc_check_record(utils::modifyList(SCORED_4, list(tol = 2)), f4),
               "scored with tol = 4 .* expects 2")
  f2 <- scored_dir(list(K = 200, tol = 2, population = "adopted"))
  expect_error(mcgc_check_record(SCORED_4, f2), "scored with tol = 2 .* expects 4")
  expect_error(mcgc_check_record(utils::modifyList(SCORED_4, list(K = 100L)), f4),
               "K = 200 .* expects 100")
  expect_error(mcgc_check_record(utils::modifyList(SCORED_4, list(population = "relaxed")), f4),
               "population = adopted .* expects relaxed")
  expect_error(mcgc_check_record(SCORED_4, scored_dir(record = NULL)), "no scoring record")
  expect_error(mcgc_check_record(SCORED_4, scored_dir(list(K = 200, tol = 4))),
               "holds no population")
  expect_error(mcgc_check_record(SCORED_4, scored_dir(list(tol = 4, population = "adopted"))),
               "holds no K")
  # without a null the record's K is not asked for
  no_null <- list(record = "cells.config.json", tol = 4, K = NULL, population = "adopted")
  expect_identical(mcgc_check_record(no_null, scored_dir(list(tol = 4, population = "adopted")))$tol,
                   4L)
  bad <- scored_dir(record = NULL)
  writeLines("{not json", file.path(dirname(bad), "cells.config.json"))
  expect_error(mcgc_check_record(SCORED_4, bad), "not readable JSON")
  # "none" reads nothing and says why
  none <- mcgc_check_record(list(record = "none", tol = 4, population = "labels",
                                 why = "no such record"), scored_dir(record = NULL))
  expect_true(is.na(none$record))
  expect_identical(none$why, "no such record")
})

test_that("a pooled file must be its parts' concatenation, each part's record checked", {
  a <- scored_dir(cells = data.frame(site = "SOAP", plot = c("p1", "p2"), n = 1:2))
  b <- scored_dir(cells = data.frame(site = "SJER", plot = "p3", n = 3L))
  pooled <- file.path(tempfile("pooled_"), "cells.csv"); dir.create(dirname(pooled))
  writeLines(c(readLines(a), readLines(b)[-1]), pooled)   # what the shell's cat and tail make
  expect_true(mcgc_check_pooled(pooled, c(a, b)))
  ds <- list(name = "C2", cells = pooled, parts = c(a, b), scoring = SCORED_4)
  rec <- mcgc_check_scoring(ds)
  expect_length(rec, 2L)
  expect_identical(vapply(rec, `[[`, "", "record"),
                   file.path(dirname(c(a, b)), "cells.config.json"))
  # the pooled file has no record of its own and is not asked for one
  expect_false(file.exists(file.path(dirname(pooled), "cells.config.json")))
  # a part scored otherwise stops, naming it
  jsonlite::write_json(list(K = 200, tol = 2, population = "adopted"),
                       file.path(dirname(b), "cells.config.json"), auto_unbox = TRUE)
  expect_error(mcgc_check_scoring(ds), "dataset C2 .*scored with tol = 2")
  # the parts in the other order, a missing row, a part with other columns
  expect_error(mcgc_check_pooled(pooled, c(b, a)), "not the concatenation")
  short <- tempfile(fileext = ".csv"); writeLines(readLines(pooled)[-3], short)
  expect_error(mcgc_check_pooled(short, c(a, b)), "not the concatenation")
  other <- scored_dir(cells = data.frame(site = "TEAK", plot = "p4", m = 4L))
  expect_error(mcgc_check_pooled(pooled, c(a, other)), "share one header")
  expect_error(mcgc_check_pooled(pooled, c(a, tempfile())), "no cells at")
  # a dataset without parts checks its own record
  expect_length(mcgc_check_scoring(list(name = "C1", cells = a, parts = NULL,
                                        scoring = SCORED_4)), 1L)
})

test_that("cells are completed, checked and cut to the declared levels", {
  cells <- syn_confirm_cells()
  x <- mcgc_prepare_cells(cells[setdiff(names(cells), c("n_over", "tp_over0"))], null = FALSE,
                          levels = "native")
  expect_identical(unique(x$rung), "native")
  expect_true(all(is.na(x$n_over)) && all(is.na(x$n_det0)) && all(is.na(x$TP0)))
  expect_error(mcgc_prepare_cells(cells, TRUE, levels = "ql2"), "no level ql2")
  expect_error(mcgc_prepare_cells(rbind(cells, cells[1, ]), TRUE), "more than one row")
  expect_error(mcgc_prepare_cells(cells[cells$config != MCGC_CONFIGS[["declared"]], ], TRUE),
               "lacks configuration")
  nn <- cells; nn$TP0[nn$config == "stock"][1] <- NA
  expect_error(mcgc_prepare_cells(nn, TRUE), "null columns")
  expect_error(mcgc_prepare_cells(cells[setdiff(names(cells), "tp_core")], TRUE), "tp_core")
  f <- tempfile(fileext = ".csv"); write.csv(cells, f, row.names = FALSE)
  y <- mcgc_read_cells(f, null = TRUE)
  expect_identical(y$rung, cells$rung)
  expect_type(y$plot, "character")
})

test_that("the split subset is the study's stratified split", {
  cells <- syn_confirm_cells()
  s <- mcgc_split_ids(cells, 1L, 0.5)
  sp <- mcg_split(unique(cells[c("site", "plot", "plotType", "n_dominant", "n_codominant",
                                 "n_intermediate", "n_suppressed")]), 1L, 0.5)
  expect_setequal(s$valid, mcgc_ids(sp[sp$split == "valid", ]))
  expect_length(intersect(s$valid, s$calib), 0L)
  f <- tempfile(fileext = ".csv"); write.csv(cells, f, row.names = FALSE)
  sub <- list(name = "v", kind = "split", seed = 1L, frac = 0.5, side = "valid", cells = f)
  expect_setequal(mcgc_subset_ids(sub, cells[0, ]), s$valid)
  expect_null(mcgc_subset_ids(list(name = "a", kind = "all"), cells))
})

## ---- contrasts ------------------------------------------------------------------------------
test_that("dataset contrasts equal mcg_contrast and are read on the dataset's measure", {
  cells <- mcgc_prepare_cells(syn_confirm_cells(), null = TRUE)
  ds <- syn_spec()
  con <- mcgc_dataset_contrasts(ds, cells, list(`all plots` = NULL), n_boot = 60, seed = 7)
  expect_setequal(unique(con$contrast), MCGC_CONTRASTS$contrast)
  expect_identical(nrow(con), 2L * 3L * nrow(MCGC_CONTRASTS))
  r <- con[con$level == "native" & con$scope == "Five sites" & con$contrast == "declared_stock", ]
  nat <- cells[cells$rung == "native", ]
  ct <- mcg_contrast(nat, unique(mcgc_ids(nat)), MCGC_CONFIGS[["declared"]], "stock",
                     n_boot = 60, seed = 7, metrics = MCGC_METRICS)
  expect_equal(r$d_cF1, ct$difference[ct$metric == "cF1"])
  expect_equal(c(r$lo_cF1, r$hi_cF1), unname(unlist(ct[ct$metric == "cF1",
                                                        c("lower", "upper")])))
  expect_equal(r$lo_recall, ct$lower[ct$metric == "recall"])
  expect_identical(r$n_plots, 24L)
  expect_identical(r$measure, "cF1")
  expect_identical(r$d_measure, r$d_cF1)
  expect_identical(r$reading, mcgc_reading(r$lo_cF1, r$hi_cF1, 24)$reading)
  # SJER holds 4 plots: reported, not read
  expect_true(all(con$reading[con$scope == "SJER"] == "not read"))
  expect_true(all(con$n_plots[con$scope == "SJER"] == 4L))
})

test_that("without a null the corrected measures are NA and F1 is read", {
  cells <- mcgc_prepare_cells(syn_confirm_cells(), null = FALSE)
  con <- mcgc_dataset_contrasts(syn_spec(null = FALSE), cells, list(`all plots` = NULL),
                                n_boot = 40, seed = 3)
  expect_true(all(con$measure == "F1"))
  expect_true(all(is.na(con$d_cF1)) && all(is.na(con$lo_cF1)) && all(is.na(con$a_cF1)))
  expect_identical(con$d_measure, con$d_F1)
  expect_false(any(con$reading == "undefined"))
})

test_that("a contrast without its baseline at a level is left out, and subsets cut plots", {
  cells <- syn_confirm_cells()
  cells <- cells[!(cells$config == "chm_vwf" & cells$rung == "8"), ]
  cells <- mcgc_prepare_cells(cells, null = TRUE)
  ds <- syn_spec()
  ds$subsets <- list(list(name = "all plots", kind = "all"),
                     list(name = "two", kind = "plots", plots = c("WREF::WREF_001", "SJER::SJER_002")))
  con <- mcgc_dataset_contrasts(ds, cells, list(`all plots` = NULL,
                                                two = c("WREF::WREF_001", "SJER::SJER_002")),
                                n_boot = 30, seed = 1)
  expect_false(any(con$contrast == "declared_chm_vwf" & con$level == "8"))
  expect_true(any(con$contrast == "declared_chm_vwf" & con$level == "native"))
  expect_true(mcgc_check_listed(ds, cells))
  typo <- ds; typo$scopes$SJER$plots <- c("SJER::SJER_001", "SJER::SJER_099")
  expect_error(mcgc_check_listed(typo, cells), "SJER::SJER_099")
  two <- con[con$subset == "two", ]
  expect_identical(unique(two$n_plots[two$scope == "Five sites"]), 2L)
  expect_identical(unique(two$n_plots[two$scope == "California"]), 1L)
  expect_false(any(two$scope == "SJER" & two$n_plots != 1L))
})

## ---- the decision ---------------------------------------------------------------------------
# A contrasts table from (test, scope, contrast, lo, hi[, level]) rows; one
# dataset per test, named after it, read on its "all plots" subset.
syn_con <- function(rows, n_plots = 30L) {
  r <- do.call(rbind, lapply(rows, function(x) data.frame(
    dataset = x[[1]], test = x[[1]], level = if (length(x) >= 6) x[[6]] else "native",
    scope = x[[2]], subset = "all plots", contrast = x[[3]], d_measure = (x[[4]] + x[[5]]) / 2,
    lo_measure = x[[4]], hi_measure = x[[5]], n_plots = n_plots, stringsAsFactors = FALSE)))
  cbind(r, mcgc_reading(r$lo_measure, r$hi_measure, r$n_plots))
}
syn_ds <- function(tests) lapply(tests, function(t) list(name = t, test = t,
                                                          decision_subset = "all plots"))
# Every contrast the decision reads, at one interval per configuration.
syn_all <- function(decl = c(0.01, 0.05), fe = c(0.01, 0.05), gate = c(0.01, 0.04),
                    exem = c(0.01, 0.04), extra = list()) {
  rows <- list()
  for (t in c("C1", "C2", "C3", "C4", "C5", "R2")) {
    sc <- switch(t, C1 = c("Five sites", "California", "Washington"), C2 = "California",
                 C3 = "Washington", C4 = c("California", "Washington"), C5 = "FGI-EMIT",
                 R2 = "Five sites")
    for (s in sc) {
      rows <- c(rows, list(list(t, s, "declared_stock", decl[1], decl[2]),
                           list(t, s, "floor_exemption_stock", fe[1], fe[2]),
                           list(t, s, "declared_floor_exemption", gate[1], gate[2]),
                           list(t, s, "floor_exemption_floor", exem[1], exem[2])))
    }
  }
  syn_con(c(rows, extra))
}
status <- function(dec, item, cfg = "") dec$status[startsWith(dec$item, item) &
                                                     dec$configuration == cfg]

test_that("the decision supports the declared configuration when all four conditions hold", {
  dec <- mcgc_decide(syn_all(), syn_ds(c("C1", "C2", "C3", "C4", "C5", "R2")))
  expect_identical(status(dec, "1.", "Declared"), "holds")
  expect_identical(status(dec, "Outcome"), "supported for the declared configuration")
  expect_identical(status(dec, "Share gate kept"), "holds")
  expect_identical(status(dec, "Configuration proposed"), "declared")
})

test_that("absent tests leave the decision pending, and left-out tests are named", {
  con <- syn_all()
  dec <- mcgc_decide(con[con$test == "C1", ], syn_ds("C1"))
  expect_identical(status(dec, "1.", "Declared"), "pending")
  expect_identical(status(dec, "Outcome"), "pending")
  expect_identical(status(dec, "Configuration proposed"), "pending")
  dec <- mcgc_decide(con[!con$test %in% c("C4", "C5"), ], syn_ds(c("C1", "C2", "C3", "R2")),
                     left_out = c("C4", "C5"))
  expect_identical(status(dec, "Outcome"), "supported for the declared configuration")
  expect_identical(status(dec, "C4 qualifies", "Declared"), "left out")
  expect_identical(status(dec, "3 as worded", "Declared"), "holds")
})

test_that("a worse C4 qualifies the statement instead of deciding it", {
  con <- syn_all(extra = list(list("C4", "Washington", "declared_stock", -0.06, -0.01,
                                   "thinned")))
  dec <- mcgc_decide(con, syn_ds(c("C1", "C2", "C3", "C4", "C5", "R2")))
  expect_identical(status(dec, "3. Worse", "Declared"), "holds")
  expect_identical(status(dec, "3 as worded", "Declared"), "fails")
  expect_identical(status(dec, "C4 qualifies", "Declared"), "fails")
  expect_match(dec$evidence[dec$item == "Outcome"], "Declared C4 worse")
  expect_match(dec$evidence[startsWith(dec$item, "C4 qualifies") &
                              dec$configuration == "Declared"], "NEON instruments")
})

test_that("the statement falls back to floor and exemption, or is not made", {
  # declared not better on C3 (condition 1 fails); floor and exemption passes
  con <- syn_all(gate = c(-0.01, 0.02))
  con[con$test == "C3" & con$contrast == "declared_stock", c("lo_measure", "hi_measure")] <-
    list(-0.01, 0.03)
  con <- cbind(con[1:10], mcgc_reading(con$lo_measure, con$hi_measure, con$n_plots))
  ds <- syn_ds(c("C1", "C2", "C3", "C4", "C5", "R2"))
  dec <- mcgc_decide(con, ds)
  expect_identical(status(dec, "1.", "Declared"), "fails")
  expect_identical(status(dec, "Outcome"), "made for floor and exemption")
  expect_identical(status(dec, "Share gate kept"), "fails")
  expect_identical(status(dec, "Configuration proposed"), "floor and exemption")
  # floor and exemption worse in California on C2: neither passes
  con2 <- con
  k <- con2$test == "C2" & con2$contrast == "floor_exemption_stock"
  con2[k, c("lo_measure", "hi_measure")] <- list(-0.05, -0.01)
  con2 <- cbind(con2[1:10], mcgc_reading(con2$lo_measure, con2$hi_measure, con2$n_plots))
  dec2 <- mcgc_decide(con2, ds)
  expect_identical(status(dec2, "3. Worse", "Floor and exemption"), "fails")
  expect_match(status(dec2, "Outcome"), "^no general statement")
  # the exemption not supported either: the proposal is the floor
  con3 <- syn_all(gate = c(-0.01, 0.02), exem = c(-0.03, 0.02))
  expect_identical(status(mcgc_decide(con3, ds), "Configuration proposed"), "floor")
})

test_that("a scope that is not read cannot carry a condition", {
  con <- syn_all()
  con$n_plots[con$test == "C2"] <- 8L
  con <- cbind(con[1:10], mcgc_reading(con$lo_measure, con$hi_measure, con$n_plots))
  dec <- mcgc_decide(con, syn_ds(c("C1", "C2", "C3", "C4", "C5", "R2")))
  expect_identical(status(dec, "2.", "Declared"), "fails")
  expect_match(dec$evidence[startsWith(dec$item, "2.") & dec$configuration == "Declared"],
               "not read")
})

## ---- R1: the selection wrapper --------------------------------------------------------------
# Grid rows at native density: configurations 1 (stock) to 4 on 3 California
# and 3 Washington plots; 3 and 4 are identical in California (4 is better in
# Washington), so a California selection ties them and keeps 3.
syn_grid_cells <- function() {
  cfg <- data.frame(config = c("stock", "z5_s0_c0_e0", "z5_s0.5_c0.6_e1", "z5_s0.5_c0.6_e1_d8"),
                    config_id = 1:4, stringsAsFactors = FALSE)
  out <- list()
  for (s in c("SJER", "WREF")) for (i in 1:3) for (k in 1:4) {
    TP <- c(10, 11, 13, 13)[k] + if (s == "WREF" && k == 4) 3 else 0
    out[[length(out) + 1L]] <- data.frame(
      site = s, plot = sprintf("%s_%03d", s, i), rung = c("native", "8"), config = cfg$config[k],
      config_id = cfg$config_id[k], n_ref = 20, n_over = 14, n_under = 6, n_det = 25, TP = TP,
      tp_core = TP, tp_over = TP - 2, tp_under = 2, n_det0 = 22, TP0 = 4, tp_core0 = 4,
      tp_over0 = 3, tp_under0 = 1, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

test_that("the R1 wrapper selects within one region with ties to the lowest config_id", {
  cells <- syn_grid_cells()
  s <- mcgc_r1_select(cells, "SJER")
  expect_identical(s$config_id, 3L)
  expect_identical(s$label, "z5_s0.5_c0.6_e1")
  expect_identical(s$plots, sprintf("SJER::SJER_%03d", 1:3))
  expect_identical(s$tied_score, 4L)
  expect_identical(s$same_counts, 4L)
  expect_identical(s$ranking$config_id, c(3L, 4L, 2L, 1L))
  expect_identical(s$ranking$margin[1:2], c(0, 0))
  expect_true(all(s$ranking$margin >= 0))
  expect_identical(s$config_id, mcg_select(cells[cells$rung == "native", ], s$plots, "cF1"))
  w <- mcgc_r1_select(cells, "WREF")
  expect_identical(w$config_id, 4L)
  expect_length(w$tied_score, 0L)
  expect_length(w$same_counts, 0L)
  # the native rows only: the other level does not enter the selection
  expect_identical(mcgc_r1_select(cells[cells$rung == "native", ], "SJER")$ranking,
                   s$ranking)
})

## ---- R4: recomposition, placements, spread --------------------------------------------------
# Three cells per level: a closed plot with crowns 9 m apart (gated), a closed
# plot at 7 m (not gated) and an open plot at 12 m; the declared rows are what
# the switch gives.
syn_r4_cells <- function() {
  cells <- syn_confirm_cells(sites = c(WREF = 3), rungs = c("native", "8"))
  cells$cover <- ifelse(cells$plot == "WREF_003", 0.4, 0.8)
  cells$crown_spacing <- c(WREF_001 = 9, WREF_002 = 7, WREF_003 = 12)[cells$plot]
  ge <- cells$config == MCGC_CONFIGS[["gate_everywhere"]]
  fe <- cells$config == MCGC_CONFIGS[["floor_exemption"]]
  de <- cells$config == MCGC_CONFIGS[["declared"]]
  cells$TP[ge] <- 20 + seq_len(sum(ge)); cells$n_det0[ge] <- 30 + seq_len(sum(ge))
  key <- function(r) paste(r$site, r$plot, r$rung)
  for (i in which(de)) {
    src <- if (cells$plot[i] == "WREF_001") ge else fe
    j <- which(src & key(cells) == key(cells[i, ]))
    cells[i, MCG_COUNT_COLS] <- cells[j, MCG_COUNT_COLS]
  }
  cells
}
syn_spacing <- function(cells, values = c(WREF_001 = 9, WREF_002 = 7, WREF_003 = 12)) {
  u <- unique(cells[c("site", "plot", "rung")])
  u$crown_spacing <- unname(values[u$plot])
  u
}

test_that("the recomposition reproduces the declared cells at the study's spacing", {
  cells <- syn_r4_cells()
  rec <- mcgc_recompose(cells, syn_spacing(cells))
  pr <- mcgc_compare_counts(rec, cells[cells$config == MCGC_CONFIGS[["declared"]], ])
  expect_identical(pr$n_mismatched_cells, 0L)
  expect_identical(pr$n_cells, 6L)
  expect_identical(rec$gated, rep(c(TRUE, FALSE, FALSE), each = 2))
  expect_true(all(rec$config == "declared_recomposed") && all(is.na(rec$config_id)))
})

test_that("a placement that moves a closed plot across 8 m switches its cells", {
  cells <- syn_r4_cells()
  ge <- cells[cells$config == MCGC_CONFIGS[["gate_everywhere"]], ]
  fe <- cells[cells$config == MCGC_CONFIGS[["floor_exemption"]], ]
  rec <- mcgc_recompose(cells, syn_spacing(cells, c(WREF_001 = 7.9, WREF_002 = 8,
                                                    WREF_003 = 3)))
  expect_identical(rec$gated, rep(c(FALSE, TRUE, FALSE), each = 2))
  expect_identical(rec$TP[rec$plot == "WREF_001"], fe$TP[fe$plot == "WREF_001"])
  expect_identical(rec$TP[rec$plot == "WREF_002"], ge$TP[ge$plot == "WREF_002"])
  expect_identical(rec$crown_spacing[rec$plot == "WREF_002"], c(8, 8))
  pr <- mcgc_compare_counts(rec, cells[cells$config == MCGC_CONFIGS[["declared"]], ])
  expect_identical(pr$n_mismatched_cells, 4L)
  # an unknown spacing stops in a closed plot and is moot in an open one
  expect_error(mcgc_recompose(cells, syn_spacing(cells, c(WREF_001 = NA, WREF_002 = 7,
                                                          WREF_003 = 12))), "unknown")
  expect_silent(mcgc_recompose(cells, syn_spacing(cells, c(WREF_001 = 9, WREF_002 = 7,
                                                           WREF_003 = NA))))
  # an interior surface without a crown (infinite spacing) counts as spaced
  expect_true(mcgc_gated(0.8, Inf))
  expect_error(mcgc_recompose(cells[cells$config != MCGC_CONFIGS[["floor_exemption"]], ],
                              syn_spacing(cells)), "same cells")
})

test_that("the placements are the 16 grid offsets, unshifted first", {
  sh <- mcgc_r4_shifts()
  expect_identical(nrow(sh), 16L)
  expect_identical(unlist(sh[1, c("dx", "dy")]), c(dx = 0, dy = 0))
  expect_false(anyDuplicated(sh$placement) > 0)
  expect_setequal(paste(sh$dx, sh$dy), paste(rep(MCGC_R4_STEPS, 4), rep(MCGC_R4_STEPS, each = 4)))
})

# A normalized stand of cones on a lattice, first returns only, quantized.
syn_cone_las <- function(spacing = 6, side = 48, n = 12000, seed = 2) {
  set.seed(seed)
  x <- runif(n, 0, side); y <- runif(n, 0, side)
  cx <- round(x / spacing) * spacing; cy <- round(y / spacing) * spacing
  h <- 20 + 3 * sin(cx) + 2 * cos(cy)
  z <- pmax(0, h - 2.5 * sqrt((x - cx)^2 + (y - cy)^2)) + runif(n, 0, 0.05)
  las <- lidR::LAS(data.frame(X = x + 500000, Y = y + 4000000, Z = z, ReturnNumber = 1L))
  lidR::las_quantize(las, by_reference = TRUE)
  lidR::las_update(las)
}

test_that("translating a clip moves the grid on the stand and nothing else", {
  las <- syn_cone_las()
  expect_identical(mcgc_translate(las, 0, 0), las)
  t1 <- mcgc_translate(las, 0.25, 0.5)
  expect_equal(t1@data$X - las@data$X, rep(0.25, lidR::npoints(las)), tolerance = 1e-9)
  expect_equal(t1@data$Y - las@data$Y, rep(0.5, lidR::npoints(las)), tolerance = 1e-9)
  expect_equal(t1@header@PHB[["Min X"]], las@header@PHB[["Min X"]] + 0.25, tolerance = 1e-9)
  expect_identical(las@data$X[1:5], las@data$X[1:5])   # the original is untouched
  pl <- mcgc_crowns_placements(las, mcgc_r4_shifts()[1:3, ])
  r0 <- mcg_crowns(las)
  expect_identical(pl$n_crowns[1], r0$n)
  expect_identical(pl$crown_area[1], r0$area)
  expect_identical(pl$crown_spacing[1], r0$spacing)
  # a whole-cell translation puts the grid where it was
  r1 <- mcg_crowns(mcgc_translate(las, 1, 0))
  expect_identical(r1$n, r0$n)
  expect_identical(r1$area, r0$area)
})

test_that("the spread and the gated state per placement are counted per cell", {
  sh <- mcgc_r4_shifts()
  sp <- do.call(rbind, lapply(c("P1", "P2", "P3"), function(p) data.frame(
    site = "WREF", plot = p, rung = "native", placement = sh$placement, dx = sh$dx, dy = sh$dy,
    n_crowns = 50L, crown_area = 4000,
    crown_spacing = switch(p, P1 = c(8.1, rep(7.9, 3), rep(8.2, 12)), P2 = rep(9, 16),
                           P3 = c(7.5, rep(8.5, 15))), stringsAsFactors = FALSE)))
  cover <- data.frame(site = "WREF", plot = c("P1", "P2", "P3"), rung = "native",
                      cover = c(0.8, 0.8, 0.3))
  s <- mcgc_r4_spread(sp, cover)
  s <- s[order(s$plot), ]
  expect_equal(s$spacing_range, c(0.3, 0, 1))
  expect_equal(s$spacing0, c(8.1, 9, 7.5))
  expect_equal(s$spacing_sd[2], 0)
  expect_identical(s$gated0, c(TRUE, TRUE, FALSE))
  expect_identical(s$n_gated, c(13L, 16L, 0L))           # P3 is open: never gated
  expect_identical(s$closed, c(TRUE, TRUE, FALSE))
  st <- mcgc_r4_state(sp, cover)
  expect_identical(nrow(st), 16L)
  expect_identical(st$n_differ[st$dx == 0 & st$dy == 0], 0L)
  expect_identical(sum(st$n_differ), 3L)
  expect_identical(sum(st$n_on_off), 3L)
  expect_identical(sum(st$n_off_on), 0L)
  expect_true(all(st$n_closed == 2L))
})

## ---- stand measures on another flight (C3, C4) --------------------------------------------
# Candidates of one clip: surface peaks (layer 1) and deeper-layer peaks with
# their first-return shares, one share unknown.
syn_cand <- function(shares = c(0.2, 0.4, 0.8, NA), n_surface = 3L)
  data.table::data.table(X = seq_len(n_surface + length(shares)), Y = 0, Z = 10,
                         layer = c(rep(1L, n_surface),
                                   if (length(shares)) c(rep(2L, length(shares) - 1L), 3L)),
                         ztop = 12, share = c(rep(1, n_surface), shares))

test_that("deeper-layer shares follow the definition of confirm_gated_3dep.R", {
  c4 <- new.env()
  suppressMessages(source(file.path("..", "..", "scripts", "confirm_gated_3dep.R"), local = c4))
  for (cand in list(syn_cand(), syn_cand(c(0.75, 0.9)), syn_cand(numeric()),
                    syn_cand(c(NA, NA)), syn_cand(c(0.1, 0.5), n_surface = 0L)))
    expect_identical(mcgc_deep_shares(cand), c4$c3_deep_shares(cand))
  s <- mcgc_deep_shares(syn_cand())
  expect_identical(c(s$n_cand, s$n_deep), c(7L, 4L))
  expect_identical(s$deep_share_median, 0.4)     # the NA share dropped
  expect_identical(s$deep_share_ge, 0.25)        # one of four at or above 0.75
  expect_true(is.na(mcgc_deep_shares(syn_cand(numeric()))$deep_share_median))
  expect_error(mcgc_deep_shares(data.frame(layer = 1L)), "layer and share")
})

test_that("clip shares read each stored preparation and check its candidate count", {
  idx <- data.frame(site = "WREF", plot = c("WREF_001", "WREF_002"), rung = "native",
                    cover = c(0.9, 0.5), crown_spacing = c(8.5, 6), top_height = c(40, 30),
                    n_cand = c(7L, 5L), file = c("a.rds", "b.rds"), stringsAsFactors = FALSE)
  store <- list(a.rds = list(cand = syn_cand()), b.rds = list(cand = syn_cand(c(0.6, 0.7))))
  x <- mcgc_clip_shares(idx, function(f) store[[f]], "2019")
  expect_identical(x$side, c("2019", "2019"))
  expect_equal(x$deep_share_median, c(0.4, 0.65))
  expect_identical(x$cover, idx$cover)
  idx$n_cand[2] <- 6L
  expect_error(mcgc_clip_shares(idx, function(f) store[[f]], "2019"),
               "WREF_002: 5 candidates stored, 6 in the index")
})

syn_sides <- function() {
  a <- data.frame(site = c("WREF", "WREF", "ABBY", "ABBY"), plot = c("w1", "w2", "a1", "a2"),
                  cover = c(0.9, 0.8, 0.59, 0.7), crown_spacing = c(8.1, 7, 6, 9),
                  n_deep = c(10L, 20L, 5L, 0L), deep_share_median = c(0.2, 0.4, 0.3, NA),
                  stringsAsFactors = FALSE)
  b <- data.frame(site = c("ABBY", "ABBY", "WREF", "WREF"), plot = c("a2", "a1", "w2", "w1"),
                  cover = c(0.75, 0.65, 0.85, 0.95), crown_spacing = c(9.5, 6.5, 7.2, 7.9),
                  n_deep = c(3L, 6L, 22L, 12L), deep_share_median = c(0.5, 0.45, 0.5, 0.3),
                  stringsAsFactors = FALSE)
  list(a = a, b = b)
}

test_that("the stand transfer pairs plots and counts the states that differ", {
  s <- syn_sides()
  tr <- mcgc_stand_transfer(s$a, s$b, list(WREF = "WREF", ABBY = "ABBY",
                                           Washington = c("WREF", "ABBY")),
                            labels = c("2019", "2021"))
  expect_identical(tr$scope, c("WREF", "ABBY", "Washington"))
  expect_identical(tr$plots, c(2L, 2L, 4L))
  w <- tr[tr$scope == "WREF", ]
  expect_equal(c(w$cover_2019, w$cover_2021), c(0.85, 0.9))
  expect_equal(c(w$deep_share_median_2019, w$deep_share_median_2021), c(0.3, 0.4))
  # WREF: both closed on both sides; w1 is gated on 2019 only (8.1 against 7.9)
  expect_identical(unlist(w[c("closed_2019", "closed_2021", "closed_changed", "gated_2019",
                              "gated_2021", "gated_changed")], use.names = FALSE),
                   c(2L, 2L, 0L, 1L, 0L, 1L))
  ab <- tr[tr$scope == "ABBY", ]
  # a1 is open on 2019 (0.59) and closed on 2021; a2 is gated on both
  expect_identical(unlist(ab[c("closed_2019", "closed_2021", "closed_changed", "gated_2019",
                               "gated_2021", "gated_changed")], use.names = FALSE),
                   c(1L, 2L, 1L, 1L, 1L, 0L))
  expect_identical(ab$deep_share_median_2019, 0.3)   # a2 has no deeper-layer peak
  expect_identical(ab$deep_share_missing_2019, 1L)
  expect_identical(tr$n_deep_2021[tr$scope == "Washington"], 43L)
  expect_error(mcgc_stand_transfer(s$a, s$b[-1, ], list(ABBY = "ABBY")), "no 2021 stand")
  expect_error(mcgc_stand_transfer(rbind(s$a, s$a[1, ]), s$b, list(WREF = "WREF")), "twice")
})

test_that("the C4 transfer reads the 3DEP clip record as confirm_gated_3dep.R counts it", {
  s <- syn_sides()
  b <- s$b[match(paste(s$a$site, s$a$plot), paste(s$b$site, s$b$plot)), ]
  one <- function(rung, shift) data.frame(
    site = s$a$site, plot = s$a$plot, rung = rung, scored = TRUE, cover = s$a$cover + shift,
    crown_spacing = s$a$crown_spacing, n_deep = s$a$n_deep,
    deep_share_median = s$a$deep_share_median,
    neon_native_cover = b$cover, neon_native_crown_spacing = b$crown_spacing,
    neon_native_n_deep = b$n_deep, neon_native_deep_share_median = b$deep_share_median,
    neon_rung2_cover = b$cover - 0.3, neon_rung2_crown_spacing = b$crown_spacing,
    neon_rung2_n_deep = 1L, neon_rung2_deep_share_median = 0.1, stringsAsFactors = FALSE)
  clips <- rbind(one("3dep_native", 0), one("3dep_dec2", -0.2))
  clips$scored[1] <- FALSE   # an unscored clip is left out
  scopes <- list(WREF = "WREF", ABBY = "ABBY", California = c("WREF", "ABBY"))
  tr <- mcgc_c4_transfer(clips, scopes)
  expect_identical(tr$variant, rep(c("3dep_native", "3dep_dec2"), each = 3))
  expect_identical(tr$plots, c(1L, 2L, 3L, 2L, 2L, 4L))
  # the thinned clips are set against the 2021 thinned clip
  expect_identical(tr$deep_share_median_2021[tr$variant == "3dep_dec2"], rep(0.1, 3))
  expect_equal(tr$cover_2021[tr$variant == "3dep_native" & tr$scope == "WREF"], 0.85)
  # the counts equal confirm_gated_3dep.R's transfer table on the same clips
  c4 <- new.env()
  suppressMessages(source(file.path("..", "..", "scripts", "confirm_gated_3dep.R"), local = c4))
  ref <- c4$c3_transfer(clips)
  m <- merge(tr, ref, by = c("variant", "scope"), suffixes = c("", ".ref"))
  for (k in c("plots", "closed_3dep", "closed_2021", "closed_changed", "spaced_3dep",
              "spaced_2021", "spaced_changed", "gated_3dep", "gated_2021", "gated_changed"))
    expect_identical(as.integer(m[[k]]), as.integer(m[[paste0(k, ".ref")]]), info = k)
})

## ---- the bootstrap's own variation -----------------------------------------------------------
test_that("seed bounds redraw each contrast with the given seeds", {
  cells <- mcgc_prepare_cells(syn_confirm_cells(sites = c(WREF = 8, ABBY = 6),
                                                rungs = "native"), null = TRUE)
  Lid <- mcgc_ids(cells)
  pairs <- list(declared_stock = MCGC_CONFIGS[c("declared", "stock")],
                floor_exemption_stock = MCGC_CONFIGS[c("floor_exemption", "stock")])
  sb <- mcgc_seed_bounds(cells, Lid, unique(Lid), pairs, seeds = 11:13, n_boot = 50)
  expect_identical(nrow(sb), 6L)
  expect_identical(sb$seed, rep(11:13, each = 2))
  expect_identical(sb$contrast, rep(names(pairs), 3))
  for (i in seq_len(nrow(sb))) {
    r <- mcgc_contrast_row(cells, Lid, unique(Lid), sb$config_a[i], sb$config_b[i], 50,
                           sb$seed[i])
    expect_identical(c(sb$d_measure[i], sb$lo_measure[i], sb$hi_measure[i]),
                     c(r$d_cF1, r$lo_cF1, r$hi_cF1))
    expect_identical(sb$reading[i], mcgc_reading(r$lo_cF1, r$hi_cF1, r$n_plots)$reading)
  }
  # the point estimate is the same under every seed; the interval is not
  d <- sb[sb$contrast == "declared_stock", ]
  expect_identical(length(unique(d$d_measure)), 1L)
  expect_gt(length(unique(d$lo_measure)), 1L)
  expect_identical(unique(sb$n_boot), 50L)
  expect_error(mcgc_seed_bounds(cells, Lid, character(), pairs, 1L, 10), "no plot")
})

## ---- the driver: arguments ------------------------------------------------------------------
test_that("the driver reads only its keys; any other stops with the list of keys", {
  expect_true(is.function(run_main))
  d <- normalizePath(tempfile("cf_job_"), mustWork = FALSE)
  expect_identical(CF_KEYS, c("STAGES", "MANIFEST", "OUT", "STUDY", "FROZEN_ROOT", "N_BOOT",
                              "BOOT_SEED", "SPLIT_SEED", "FRAC", "LEFT_OUT", "R4_RUNGS",
                              "R4_RECOMPUTE", "N_SEEDS", "C3_EPOCH", "C3_EPOCH_LABEL",
                              "C3_SHARED", "C4_DIR", "CORES"))
  every <- c("STAGES=contrasts,c4_transfer", "MANIFEST=/m.json", "OUT=/o", "STUDY=/st",
             "FROZEN_ROOT=/fr", "N_BOOT=10", "BOOT_SEED=3", "SPLIT_SEED=2", "FRAC=0.4",
             "LEFT_OUT=C4", "R4_RUNGS=native,8", "R4_RECOMPUTE=TRUE", "N_SEEDS=5",
             "C3_EPOCH=/ep", "C3_EPOCH_LABEL=2019", "C3_SHARED=/sh", "C4_DIR=/c4", "CORES=2")
  expect_identical(sub("=.*", "", every), CF_KEYS)
  S <- cf_settings(every, d = d)
  expect_identical(S[c("STAGES", "MANIFEST", "OUT", "STUDY", "FROZEN_ROOT", "N_BOOT", "BOOT_SEED",
                       "SPLIT_SEED", "FRAC", "LEFT_OUT", "R4_RUNGS", "R4_RECOMPUTE", "N_SEEDS",
                       "C3_EPOCH", "C3_EPOCH_LABEL", "C3_SHARED", "C4_DIR", "CORES")],
                   list(STAGES = c("contrasts", "c4_transfer"), MANIFEST = "/m.json", OUT = "/o",
                        STUDY = "/st", FROZEN_ROOT = "/fr", N_BOOT = 10L, BOOT_SEED = 3L,
                        SPLIT_SEED = 2L, FRAC = 0.4, LEFT_OUT = "C4",
                        R4_RUNGS = c("native", "8"), R4_RECOMPUTE = TRUE, N_SEEDS = 5L,
                        C3_EPOCH = "/ep", C3_EPOCH_LABEL = "2019", C3_SHARED = "/sh",
                        C4_DIR = "/c4", CORES = 2L))
  # the keys of the results' Reproduce command
  S <- cf_settings(c("CORES=8", "MANIFEST=docs/multichm-gated-confirmation-manifest.json",
                     "STAGES=contrasts,r1,r4,c3_share,c4_transfer,c3_seeds"), d = d)
  expect_identical(S$STAGES, c("contrasts", "r1", "r4", "c3_share", "c4_transfer", "c3_seeds"))
  expect_identical(S$CORES, 8L)
  # a mistyped key no longer falls back to the analysis run of record
  keys <- paste(CF_KEYS, collapse = ", ")
  expect_error(cf_settings("OUTDIR=x", d = d),
               paste0("unknown argument OUTDIR; the keys are ", keys), fixed = TRUE)
  for (k in c("OUTPUT=x", "out=x", "STAGE=contrasts", "MANIFESTS=x", "N_SEED=3", "WORK=x",
              "UNBLIND=1"))
    expect_error(cf_settings(c("STAGES=contrasts", k), d = d),
                 paste0("unknown argument ", sub("=.*", "", k), ";"), fixed = TRUE)
  expect_error(cf_settings(c("A=1", "B=2"), d = d), "unknown argument A, B;", fixed = TRUE)
  # the other checks still stop
  expect_error(cf_settings("STAGES=contrasts,r9", d = d), "STAGES are among")
  expect_error(cf_settings("LEFT_OUT=C1", d = d), "LEFT_OUT may name only C4 and C5")
  expect_error(cf_settings("FRAC=1", d = d), "invalid numeric argument")
})

test_that("the default manifest is the committed one, found from the repository root", {
  d <- normalizePath(tempfile("cf_job_"), mustWork = FALSE)
  S <- cf_settings(character(), d = d)
  committed <- normalizePath(file.path("..", "..", "docs",
                                       "multichm-gated-confirmation-manifest.json"))
  expect_identical(S$MANIFEST, CF_MANIFEST)
  expect_identical(normalizePath(S$MANIFEST), committed)
  # not the analysis run's own copy under OUT
  expect_identical(S$OUT, file.path(d, "multichm_gated_confirmation", "analysis"))
  expect_false(identical(S$MANIFEST, file.path(S$OUT, "manifest.json")))
  # it reads, and every dataset says how it was scored
  ds <- mcgc_read_manifest(S$MANIFEST, base = d)
  expect_gt(length(ds), 0L)
  expect_true(all(vapply(ds, function(x) is.list(x$scoring) && !is.null(x$scoring$tol), NA)))
  # an explicit MANIFEST= still wins
  expect_identical(cf_settings("MANIFEST=/m.json", d = d)$MANIFEST, "/m.json")
  # run from another working directory, the driver reads the committed manifest
  # (and stops at its first dataset, whose cells this empty job directory lacks)
  skip_on_os("windows")
  rs <- file.path(R.home("bin"), "Rscript")
  skip_if_not(file.exists(rs))
  drv <- normalizePath(file.path("..", "..", "scripts", "confirm_multichm_gated.R"))
  wd <- normalizePath(tempfile("cf_wd_"), mustWork = FALSE)
  dir.create(wd)
  withr::local_dir(wd)
  withr::local_envvar(CLAUDE_JOB_DIR = file.path(wd, "job"))
  got <- suppressWarnings(system2(rs, c(shQuote(drv), "STAGES=contrasts",
                                        shQuote(paste0("OUT=", file.path(wd, "out")))),
                                  stdout = TRUE, stderr = TRUE))
  expect_true(sprintf("[contrasts] %d dataset(s) from %s", length(ds), committed) %in% got)
  expect_true(any(grepl("no scoring record", got, fixed = TRUE)))
  expect_false(file.exists(file.path(wd, "out", "contrasts.csv")))
})

test_that("OUT may not lie inside the study, the frozen root or the C3 and C4 inputs", {
  base <- normalizePath(tempfile("cf_tree_"), mustWork = FALSE)
  d <- file.path(base, "job")
  dirs <- c(STUDY = "study", FROZEN_ROOT = "root", C3_EPOCH = "epoch", C3_SHARED = "shared",
            C4_DIR = "c4")
  given <- paste0(names(dirs), "=", file.path(base, dirs))
  ro <- "lies inside read-only inputs"
  for (k in dirs) for (o in c(file.path(base, k), file.path(base, k, "analysis", "x")))
    expect_error(cf_settings(c(given, paste0("OUT=", o)), d = d), ro, fixed = TRUE)
  # the defaults under the job directory are read-only too
  for (o in c(file.path(d, "multichm_gated_confirmation", "epoch_wa", "epoch_2019", "x"),
              file.path(d, "multichm_gated_confirmation", "epoch_wa", "shared_2021"),
              file.path(d, "multichm_gated_confirmation", "3dep", "out"),
              file.path(d, "multichm_gated_runs", "neon", "multichm_gated", "x"),
              file.path(d, "neon", "frozen_2021", "x")))
    expect_error(cf_settings(paste0("OUT=", o), d = d), ro, fixed = TRUE)
  # beside them: accepted, and nothing is written
  for (o in c(file.path(base, "out"), file.path(base, "c4_out"),
              file.path(d, "multichm_gated_confirmation", "analysis"))) {
    expect_identical(cf_settings(c(given, paste0("OUT=", o)), d = d)$OUT, o)
    expect_false(dir.exists(o))
  }
  expect_identical(cf_settings(character(), d = d)$OUT,
                   file.path(d, "multichm_gated_confirmation", "analysis"))
})

## ---- the driver: stages -------------------------------------------------------------------
test_that("the contrasts stage stops before any contrast on a record of another tol", {
  d <- normalizePath(tempfile("cf_job_"), mustWork = FALSE)
  cells <- file.path(d, "baseline", "cells.csv")
  dir.create(dirname(cells), recursive = TRUE)
  write.csv(syn_confirm_cells(sites = c(SJER = 4, WREF = 6), rungs = "native"), cells,
            row.names = FALSE)
  record <- function(tol) jsonlite::write_json(list(K = 200, tol = tol, population = "adopted"),
                                               file.path(dirname(cells), "cells.config.json"),
                                               auto_unbox = TRUE)
  m <- write_manifest(list(datasets = list(list(
    name = "syn baseline", test = "baseline", cells = "baseline/cells.csv",
    levels = list("native"), null = TRUE,
    scopes = list(`Five sites` = list("SJER", "WREF"), WREF = list("WREF")),
    scoring = SCORED_4))))
  out <- file.path(d, "out")
  dir.create(out)
  S <- cf_settings(c(paste0("MANIFEST=", m), paste0("OUT=", out), "N_BOOT=20"), d = d)
  # scored with tol 2, the manifest says 4: nothing is written
  record(2)
  expect_error(capture.output(cf_stage_contrasts(S)), "scored with tol = 2 .* expects 4")
  expect_identical(list.files(out), character())
  # no record at all
  file.remove(file.path(dirname(cells), "cells.config.json"))
  expect_error(capture.output(cf_stage_contrasts(S)), "no scoring record")
  expect_identical(list.files(out), character())
  # scored as the manifest says: the stage runs
  record(4)
  capture.output(con <- cf_stage_contrasts(S))
  expect_setequal(list.files(out), c("contrasts.csv", "datasets.csv", "decision.csv"))
  expect_identical(unique(con$dataset), "syn baseline")
  expect_setequal(unique(con$scope), c("Five sites", "WREF"))
})

test_that("the c4_transfer stage stops when transfer.csv disagrees with its counts", {
  d <- normalizePath(tempfile("cf_job_"), mustWork = FALSE)
  c4 <- file.path(d, "c4")
  out <- file.path(d, "out")
  dir.create(c4, recursive = TRUE)
  dir.create(out)
  # 3DEP clips of three California plots at both variants, with the 2021
  # values the clip record carries
  one <- function(rung, shift) data.frame(
    site = c("SJER", "SOAP", "TEAK"), plot = c("s1", "o1", "t1"), rung = rung, scored = TRUE,
    cover = c(0.4, 0.7, 0.8) + shift, crown_spacing = c(9, 8.5, 6), n_deep = c(2L, 10L, 12L),
    deep_share_median = c(0.2, 0.4, 0.3), neon_native_cover = c(0.5, 0.65, 0.85),
    neon_native_crown_spacing = c(9.2, 7.5, 6.5), neon_native_n_deep = c(3L, 9L, 14L),
    neon_native_deep_share_median = c(0.25, 0.35, 0.3), neon_rung2_cover = c(0.3, 0.6, 0.7),
    neon_rung2_crown_spacing = c(9, 8.2, 6.1), neon_rung2_n_deep = c(1L, 4L, 6L),
    neon_rung2_deep_share_median = c(0.1, 0.2, 0.2), stringsAsFactors = FALSE)
  clips <- rbind(one("3dep_native", 0), one("3dep_dec2", -0.1))
  write.csv(clips, file.path(c4, "clips.csv"), row.names = FALSE)
  ref <- mcgc_c4_transfer(clips, c(stats::setNames(as.list(CF_CA), CF_CA),
                                   list(California = CF_CA)))
  S <- cf_settings(c(paste0("C4_DIR=", c4), paste0("OUT=", out)), d = d)
  # the record agrees: the stage writes its table
  write.csv(ref, file.path(c4, "transfer.csv"), row.names = FALSE)
  capture.output(cf_stage_c4_transfer(S))
  got <- read.csv(file.path(out, "c4_transfer.csv"), stringsAsFactors = FALSE)
  expect_identical(nrow(got), nrow(ref))
  expect_identical(got$gated_3dep, ref$gated_3dep)
  file.remove(file.path(out, "c4_transfer.csv"))
  # a count that differs, a row that is missing: the stage stops, writing nothing
  for (bad in list(within(ref, gated_3dep[nrow(ref)] <- gated_3dep[nrow(ref)] + 1L),
                   within(ref, closed_changed[1] <- closed_changed[1] + 1L),
                   within(ref, plots[2] <- plots[2] - 1L),
                   ref[-1, , drop = FALSE])) {
    write.csv(bad, file.path(c4, "transfer.csv"), row.names = FALSE)
    expect_error(capture.output(cf_stage_c4_transfer(S)),
                 "C4: the closed and gated counts differ")
    expect_false(file.exists(file.path(out, "c4_transfer.csv")))
  }
})
