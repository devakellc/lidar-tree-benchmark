# Unit tests for the confirmation analysis of the multichm_gated arm
# (multichm_gated_confirm_lib.R): the protocol's labels and reading rule, the
# manifest and cells handling, the contrasts, the decision table, the R1
# selection wrapper and the R4 recomposition, placements and spread. Synthetic
# data only: no LiDAR files, no NEON data.
suppressMessages({ library(lidR); library(data.table); library(sf) })
source(file.path("..", "..", "scripts", "calval_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "multichm_gated_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "multichm_gated_confirm_lib.R"), local = TRUE)

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

test_that("the manifest reads datasets with defaults and resolves relative paths", {
  f <- write_manifest(list(datasets = list(
    list(name = "ql2", test = "C1", cells = "ql2/cells.csv", levels = list("ql2"), null = TRUE,
         scopes = list(`Five sites` = list("SJER", "WREF"), Washington = list("WREF"),
                       Few = list(sites = list("WREF"), plots = list("WREF::WREF_001")))),
    list(name = "fgiemit", test = "C5", cells = "/abs/cells.csv", null = FALSE,
         scopes = list(`FGI-EMIT` = list("FGI")),
         subsets = list(list(name = "all plots"),
                        list(name = "half", split = list(seed = 3, side = "calib")),
                        list(name = "two", plots = list("FGI::p1", "FGI::p2"))),
         decision_subset = "two"))))
  ds <- mcgc_read_manifest(f, base = "/job")
  expect_length(ds, 2L)
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
             scopes = list(`Five sites` = list("SJER")))
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
