# Unit tests for the multichm_gated calibration/validation driver. Sourcing the
# script defines its helpers without running a stage (guarded by
# `if (sys.nframe() == 0L) run_main()`); its sources pull in the gated arm's
# library, the split helpers and the master-table resamples. Synthetic scored
# cells only: no LiDAR, no NEON data.
source(file.path("..", "..", "scripts", "calval_multichm_gated.R"), local = TRUE)

## ---- synthetic scored cells -----------------------------------------------------------------
# Four configurations per cell: stock (config_id 1), a better one (2), a worse
# one (3) and a CHM-VWF reference. `boost` lists plots ("site::plot") where the
# worse configuration is made the best, to show what selection may not see.
SYN_CONFIGS <- data.frame(
  config = c("stock", "z5_s0_c0_e0", "z8_s0_c0_e0", "chm_vwf"),
  config_id = c(1L, 2L, 3L, NA), zmin = c(0, 5, 8, NA), min_share = c(0, 0, 0, NA),
  cover_min = c(0, 0, 0, NA), surface_exempt = c(FALSE, FALSE, FALSE, NA),
  spacing_min = c(0, 0, 0, NA),
  TP = c(10, 12, 8, 9), n_det = c(30, 24, 20, 15), stringsAsFactors = FALSE)

syn_cells <- function(sites = c("SJER", "WREF"), n = 8, rungs = c("native", "1"),
                      boost = character(), configs = SYN_CONFIGS) {
  out <- list()
  for (s in sites) for (i in seq_len(n)) for (rl in rungs) for (k in seq_len(nrow(configs))) {
    cf <- configs[k, ]
    id <- paste(s, sprintf("%s_%03d", s, i), sep = "::")
    TP <- cf$TP; nd <- cf$n_det
    if (id %in% boost && cf$config == "z8_s0_c0_e0") { TP <- 19; nd <- 20 }
    out[[length(out) + 1L]] <- data.frame(
      site = s, plot = sprintf("%s_%03d", s, i),
      plotType = if (i %% 2) "tower" else "distributed", rung = rl,
      cover = 0.5 + i / 20, top_height = 30 + i, crown_spacing = 5 + i / 2, pdens = 20,
      frdens = 10,
      config = cf$config, config_id = cf$config_id, zmin = cf$zmin, min_share = cf$min_share,
      cover_min = cf$cover_min, surface_exempt = cf$surface_exempt, spacing_min = cf$spacing_min,
      n_dominant = 8 + i %% 3, n_codominant = 6, n_intermediate = if (i <= 4) 6 else 0,
      n_suppressed = 0,
      n_ref = 20 + i %% 3 + if (i <= 4) 6 else 0, n_over = 14 + i %% 3,
      n_under = if (i <= 4) 6 else 0, n_det = nd, TP = TP, tp_core = TP - 1,
      tp_over = TP - 2, tp_under = if (i <= 4) 2 else 0,
      n_det0 = 0.9 * nd, TP0 = 4, tp_core0 = 3.5, tp_over0 = 3, tp_under0 = if (i <= 4) 1 else 0,
      stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

syn_settings <- function(...) {
  S <- list(SITES = c("SJER", "WREF"), RUNGS = c("native", "1"), SEED = 1L, FRAC = 0.5,
            SEEDS = 1:3, CRITERION = "cF1", N_BOOT = 60L, K = 200L, TOL = 4)
  utils::modifyList(S, list(...))
}

## ---- arguments --------------------------------------------------------------------------------
test_that("arguments parse as KEY=VALUE with defaults, and SEED is not read from SEEDS", {
  S <- cv_settings(character(), d = tempdir())
  expect_identical(S$STAGE, "all")
  expect_identical(S$SITES, c("SJER", "SOAP", "TEAK", "WREF", "ABBY"))
  expect_identical(S$RUNGS, c("native", "8", "4", "2", "1"))
  expect_identical(S$SEEDS, 1:200)
  expect_identical(S$SEED, 1L)
  expect_identical(S$CRITERION, "cF1")
  expect_identical(c(S$K, S$TOL, S$N_BOOT), c(200, 4, 1000))
  expect_null(S$BASE)
  expect_identical(S$OUT, file.path(tempdir(), "neon", "multichm_gated"))
  expect_identical(S$root, file.path(tempdir(), "neon", "frozen_2021"))
  S <- cv_settings(c("SEEDS=3,4", "SITES=SOAP,TEAK", "RUNGS=native,2", "STAGE=analyze",
                     "CRITERION=F1", "BASE=/b", "OUT=/o", "FROZEN_ROOT=/r"), d = tempdir())
  expect_identical(S$SEED, 1L)                        # not partially matched to SEEDS
  expect_identical(S$SEEDS, 3:4)
  expect_identical(S$SITES, c("SOAP", "TEAK"))
  expect_identical(S$RUNGS, c("native", "2"))
  expect_identical(c(S$STAGE, S$CRITERION, S$BASE, S$OUT, S$root),
                   c("analyze", "F1", "/b", "/o", "/r"))
  # the censused scores: the job directory's, and the paper runs' under BASE
  ladder <- file.path("census_support_scores", "nearest_ladder", "census_support_scores.csv")
  expect_identical(c(S$CENSUS, S$BASE_CENSUS), c(file.path(tempdir(), ladder),
                                                 file.path("/b", ladder)))
  expect_null(cv_settings(character(), d = tempdir())$BASE_CENSUS)
  S <- cv_settings(c("CENSUS=/c.csv", "BASE_CENSUS=/p.csv"), d = tempdir())
  expect_identical(c(S$CENSUS, S$BASE_CENSUS), c("/c.csv", "/p.csv"))
  expect_error(cv_settings("STAGE=fit", d = tempdir()), "STAGE")
  expect_error(cv_settings("RUNGS=native,3", d = tempdir()), "RUNGS")
  expect_error(cv_settings("CRITERION=recall", d = tempdir()), "CRITERION")
  expect_error(cv_settings("FRAC=1", d = tempdir()), "FRAC")
})

test_that("REFERENCE is optional, and REFERENCE_CENSUS needs it", {
  S <- cv_settings(character(), d = tempdir())
  expect_null(S[["REFERENCE"]])
  expect_null(S[["REFERENCE_CENSUS"]])
  expect_null(cv_settings("REFERENCE=", d = tempdir())[["REFERENCE"]])
  S <- cv_settings(c("REFERENCE=z5_s0.75_c0.6_e1", "REFERENCE_CENSUS=/r.csv"), d = tempdir())
  expect_identical(c(S$REFERENCE, S$REFERENCE_CENSUS), c("z5_s0.75_c0.6_e1", "/r.csv"))
  expect_null(cv_settings("REFERENCE=z5_s0.75_c0.6_e1", d = tempdir())$REFERENCE_CENSUS)
  expect_error(cv_settings("REFERENCE_CENSUS=/r.csv", d = tempdir()),
               "REFERENCE_CENSUS= needs REFERENCE=", fixed = TRUE)
})

test_that("K must be at least 1, and explicit K= and TOL= are flagged", {
  expect_error(cv_settings("K=0", d = tempdir()), "K >= 1")
  expect_identical(cv_settings("K=1", d = tempdir())$K, 1L)
  S <- cv_settings(character(), d = tempdir())
  expect_false(S$K_given || S$TOL_given)
  S <- cv_settings(c("K=50", "TOL=3"), d = tempdir())
  expect_true(S$K_given && S$TOL_given)
  expect_identical(c(S$K, S$TOL), c(50, 3))
})

## ---- detections and checks --------------------------------------------------------------------
test_that("detection sets compare by content, not order", {
  a <- data.frame(x = c(1, 2, 3), y = c(4, 5, 6), z = c(10, 9, 8))
  expect_true(cv_same_dets(a, a[3:1, ]))
  expect_true(cv_same_dets(a, transform(a, z = z + 1e-7), tol = 1e-6))
  expect_false(cv_same_dets(a, transform(a, z = z + 1e-5), tol = 1e-6))
  expect_false(cv_same_dets(a, a[1:2, ]))
  e <- a[0, ]
  expect_true(cv_same_dets(e, e))
})

test_that("the parity check passes only when every cell reproduces the package", {
  idx <- data.frame(site = "S", plot = c("p1", "p2"), rung = "native", parity = TRUE)
  expect_output(cv_check_parity(idx), "^PASS parity")
  idx$parity[2] <- FALSE
  expect_error(cv_check_parity(idx), "differs from lidRplugins::multichm in 1 cells")
})

test_that("the null-cell comparison is cell by cell, both ways, within 1e-9", {
  cells <- syn_cells(sites = "SJER", n = 3, rungs = "native")
  st <- cells[cells$config == "stock", ]
  ref <- rbind(
    data.frame(variant = "baseline", site = st$site, plot = st$plot, rung = st$rung,
               detector = "multichm", n_ref = st$n_ref, n_det = st$n_det, TP = st$TP,
               tp_core = st$tp_core, stringsAsFactors = FALSE),
    data.frame(variant = "null", site = st$site, plot = st$plot, rung = st$rung,
               detector = "multichm", n_ref = st$n_ref, n_det = st$n_det0, TP = st$TP0,
               tp_core = st$tp_core0, stringsAsFactors = FALSE),
    data.frame(variant = "baseline", site = "SJER", plot = "SJER_001", rung = "native",
               detector = "chm_vwf", n_ref = 1, n_det = 1, TP = 1, tp_core = 1))
  r <- cv_null_compare(cells, ref, "stock", "multichm")
  expect_identical(c(r$n, nrow(r$bad)), c(3L, 0L))
  expect_equal(r$max_null_diff, 0)
  off <- ref; off$TP[off$variant == "null"][2] <- off$TP[off$variant == "null"][2] + 1e-6
  r <- cv_null_compare(cells, off, "stock", "multichm")
  expect_identical(r$bad$plot, "SJER_002")
  expect_equal(r$max_null_diff, 1e-6)
  r <- cv_null_compare(cells, ref[-1, ], "stock", "multichm")    # a cell the paper lacks
  expect_identical(r$bad$plot, "SJER_001")
  # a paper cell of the study's sites and rungs whose plot the study lacks
  r <- cv_null_compare(cells[cells$plot != "SJER_003", ], ref, "stock", "multichm")
  expect_identical(r$bad$plot, "SJER_003")
  extra <- rbind(ref, transform(ref[1, ], rung = "native", plot = "SJER_002", n_det = 99))
  expect_gt(nrow(cv_null_compare(cells, extra[-2, ], "stock", "multichm")$bad), 0)
})

## ---- the score stage --------------------------------------------------------------------------
# One plot of the shared closed stand, prepared as the candidates stage stores
# it, scored on configurations whose detection sets differ; the stand's crown
# spacing (about 16 m) is at least the grid's spacing_min 9, and below the
# spacing condition of an extra row at 20 m, whose share gate is therefore off.
test_that("the score stage scores each configuration's own detections and its own null", {
  dir <- tempfile("mcg_score"); dir.create(dir)
  prep <- mcg_prepare(synth_closed_stand(), 0.5, CV_A_VWF)
  m <- data.frame(site = "SYN", plot = "SYN_002", plotType = "tower", rung = "native",
                  cx = 16, cy = 16, half = 16, pdens = 10, frdens = 5, cover = prep$cover,
                  top_height = prep$top_height, crown_spacing = prep$crown_spacing,
                  file = cv_cell_file("SYN", "SYN_002", "native"), stringsAsFactors = FALSE)
  saveRDS(list(meta = m, prep = prep, parity = TRUE), file.path(dir, m$file))
  stems <- synth_closed_stems()
  g <- mcg_grid()
  expect_true(prep$crown_spacing >= 9 && prep$crown_spacing < 20)
  grid <- g[match(c("stock", "z5_s0.75_c0.7_e0", "z0_s0_c0.7_e1", "z5_s0.75_c0.7_e1",
                    "z5_s0.75_c0.7_e1_d9"), g$label), ]
  wide <- mcg_config(5, 0.75, 0.7, TRUE, 20)
  grid <- rbind(grid, data.frame(config_id = nrow(g) + 1L, zmin = 5, min_share = 0.75,
                                 cover_min = 0.7, surface_exempt = TRUE, spacing_min = 20,
                                 label = mcg_config_label(wide), stringsAsFactors = FALSE))
  r <- cv_score_job(list(site = "SYN", plot = "SYN_002", half = 16, cells = m, stems = stems),
                    grid, dir, K = 5L, tol = 4, base = NULL)
  expect_identical(r$config, grid$label)
  expect_identical(r$config_id, grid$config_id)
  expect_identical(r$spacing_min, c(0, 0, 0, 0, 9, 20))
  expect_identical(r$top_height, rep(prep$top_height, nrow(grid)))
  expect_identical(r$crown_spacing, rep(prep$crown_spacing, nrow(grid)))
  # top_height follows cover and crown_spacing top_height; spacing_min follows
  # surface_exempt
  expect_identical(names(r)[5:7], c("cover", "top_height", "crown_spacing"))
  expect_identical(names(r)[match("surface_exempt", names(r)) + 1L], "spacing_min")
  expect_false("top_prob" %in% names(r))
  offs <- mcg_null_offsets("SYN", "SYN_002", 16, tol = 4, k = 5)
  for (i in seq_len(nrow(grid))) {
    cfg <- mcg_config(grid$zmin[i], grid$min_share[i], grid$cover_min[i], grid$surface_exempt[i],
                      grid$spacing_min[i])
    want <- mcg_score_cell(stems, mcg_apply(prep, cfg), 16, 16, 16, offs, tol = 4)
    expect_equal(unlist(r[i, MCG_COUNT_COLS]), unlist(want[MCG_COUNT_COLS]))
  }
  # at or above its spacing_min the stand gets the share gate: the configuration
  # at spacing_min 9 scores as the one without a spacing condition; below it
  # (spacing_min 20) the stand keeps every deeper-layer candidate, and the
  # configuration scores as the same one without the share gate
  expect_identical(unlist(r[5, MCG_COUNT_COLS]), unlist(r[4, MCG_COUNT_COLS]))
  nogate <- mcg_score_cell(stems, mcg_apply(prep, mcg_config(5, 0, 0.7, TRUE)), 16, 16, 16, offs,
                           tol = 4)
  expect_equal(unlist(r[6, MCG_COUNT_COLS]), unlist(nogate[MCG_COUNT_COLS]))
  expect_false(identical(unlist(r[6, MCG_COUNT_COLS]), unlist(r[4, MCG_COUNT_COLS])))
  # the configurations do not all share one null
  expect_gt(length(unique(r$n_det0)), 1L)
  expect_identical(c(r$n_dominant[1], r$n_suppressed[1]), c(3, 1))
  # a cell whose crown spacing is unknown where the gate reads it (the stored
  # preparation) and in the index: the configurations without a spacing condition
  # score as before and carry NA; one with a spacing condition stops the cell
  # with the library's message, since the stand is closed
  unknown <- prep
  unknown$crown_spacing <- NA_real_
  m$crown_spacing <- NA
  saveRDS(list(meta = m, prep = unknown, parity = TRUE), file.path(dir, m$file))
  job <- list(site = "SYN", plot = "SYN_002", half = 16, cells = m, stems = stems)
  na <- cv_score_job(job, grid[1:4, ], dir, K = 5L, tol = 4, base = NULL)
  expect_identical(na$config, grid$label[1:4])
  expect_true(is.numeric(na$crown_spacing) && all(is.na(na$crown_spacing)))
  expect_identical(na[MCG_COUNT_COLS], r[1:4, MCG_COUNT_COLS])
  expect_identical(grid$label[5], "z5_s0.75_c0.7_e1_d9")
  expect_error(cv_score_job(job, grid, dir, K = 5L, tol = 4, base = NULL),
               "this configuration needs the clip's crown spacing, which is unavailable",
               fixed = TRUE)
  # the real preparation back for the CHM-VWF part
  m$crown_spacing <- prep$crown_spacing
  saveRDS(list(meta = m, prep = prep, parity = TRUE), file.path(dir, m$file))
  # the CHM-VWF row carries the cell's stand features and no configuration values
  base <- tempfile("mcg_base")
  bd <- file.path(base, "neon", "SYN", "chm_vwf_detections")
  dir.create(bd, recursive = TRUE)
  write.csv(data.frame(x = c(8, 21), y = c(8, 21), z = c(24, 24)),
            frozen_detections_file(bd, "SYN_002", NA), row.names = FALSE)
  rb <- cv_score_job(list(site = "SYN", plot = "SYN_002", half = 16, cells = m, stems = stems),
                     grid[1, ], dir, K = 5L, tol = 4, base = base)
  expect_identical(rb$config, c("stock", "chm_vwf"))
  ch <- rb[rb$config == "chm_vwf", ]
  expect_true(all(is.na(unlist(ch[c("config_id", "zmin", "min_share", "cover_min",
                                    "surface_exempt", "spacing_min")]))))
  expect_identical(c(ch$top_height, ch$crown_spacing), c(prep$top_height, prep$crown_spacing))
  expect_identical(names(rb), names(r))
})

## ---- analysis helpers -------------------------------------------------------------------------
test_that("scopes are all sites first, then each region holding some of them", {
  expect_identical(cv_scopes(CV_FIVE),
                   list(`Five sites` = CV_FIVE, California = c("SJER", "SOAP", "TEAK"),
                        Washington = c("WREF", "ABBY")))
  expect_identical(cv_scopes(c("SJER", "SOAP", "TEAK")),
                   list(`SJER+SOAP+TEAK` = c("SJER", "SOAP", "TEAK")))
  expect_identical(names(cv_scopes(c("SOAP", "WREF"))), c("SOAP+WREF", "California", "Washington"))
})

test_that("components reduce the selection part by part and skip stock and the selection", {
  sel <- list(zmin = 5, min_share = 0.75, cover_min = 0.7, surface_exempt = TRUE)
  comp <- cv_components(sel)
  expect_identical(names(comp), c("versus_stock", "marginal"))
  expect_identical(comp$versus_stock,
                   c(floor_only = "z5_s0_c0_e0", no_share_gate = "z5_s0_c0.7_e1",
                     no_exemption = "z5_s0.75_c0.7_e0", exemption_only = "z0_s0_c0.7_e1"))
  expect_identical(comp$marginal,
                   c(floor = "z0_s0.75_c0.7_e1", share_gate = "z5_s0_c0.7_e1",
                     exemption = "z5_s0.75_c0.7_e0", cover_switch = "z5_s0.75_c0_e1",
                     gate_and_exemption = "z5_s0_c0_e0"))
  expect_true(all(unlist(comp) %in% mcg_grid()$label))
  # the floor alone: every reduction is the selection or stock
  fl <- cv_components(list(zmin = 5, min_share = 0, cover_min = 0, surface_exempt = FALSE))
  expect_length(fl$versus_stock, 0)
  expect_length(fl$marginal, 0)
  # no share gate: no share_gate part; without the exemption the cover is moot
  # (canonical cover 0), which repeats the floor alone and is dropped, and so is
  # the floor alone, which repeats the exemption's reduction
  ns <- cv_components(list(zmin = 5, min_share = 0, cover_min = 0.6, surface_exempt = TRUE))
  expect_identical(ns$versus_stock, c(floor_only = "z5_s0_c0_e0", exemption_only = "z0_s0_c0.6_e1"))
  expect_identical(ns$marginal, c(floor = "z0_s0_c0.6_e1", exemption = "z5_s0_c0_e0",
                                  cover_switch = "z5_s0_c0_e1"))
  expect_false(any(c("share_gate", "gate_and_exemption") %in% names(ns$marginal)))
  expect_true(all(unlist(ns) %in% mcg_grid()$label))
  # the exemption alone: removing it gives stock and the floor alone is stock;
  # only the cover switch reduces it to another configuration
  ex <- cv_components(list(zmin = 0, min_share = 0, cover_min = 0.7, surface_exempt = TRUE))
  expect_length(ex$versus_stock, 0)
  expect_identical(ex$marginal, c(cover_switch = "z0_s0_c0_e1"))
  # no exemption: no exemption part, its versus-stock reduction is the selection,
  # and the floor alone repeats the share gate's reduction
  ne <- cv_components(list(zmin = 5, min_share = 0.5, cover_min = 0.8, surface_exempt = FALSE))
  expect_identical(ne$versus_stock, c(floor_only = "z5_s0_c0_e0"))
  expect_identical(ne$marginal, c(floor = "z0_s0.5_c0.8_e0", share_gate = "z5_s0_c0_e0",
                                  cover_switch = "z5_s0.5_c0_e0"))
  expect_true(all(unlist(ne) %in% mcg_grid()$label))
  expect_identical(cv_canonical_label(0, 0, 0.8, FALSE), "stock")
})

test_that("a canonical label keeps spacing_min only with a share gate", {
  expect_identical(cv_canonical_label(5, 0.75, 0.6, TRUE), "z5_s0.75_c0.6_e1")
  expect_identical(cv_canonical_label(5, 0.75, 0.6, TRUE, 0), "z5_s0.75_c0.6_e1")
  expect_identical(cv_canonical_label(5, 0.75, 0.6, TRUE, 8), "z5_s0.75_c0.6_e1_d8")
  expect_identical(cv_canonical_label(0, 0.5, 0.8, FALSE, 8.5), "z0_s0.5_c0.8_e0_d8.5")
  # without a share gate the spacing condition switches nothing
  expect_identical(cv_canonical_label(5, 0, 0.6, TRUE, 8), "z5_s0_c0.6_e1")
  expect_identical(cv_canonical_label(5, 0, 0.8, FALSE, 7), "z5_s0_c0_e0")
  expect_identical(cv_canonical_label(0, 0, 0, FALSE, 9), "stock")
  expect_identical(cv_canonical_label(0, 0, 0.7, FALSE, 9), "stock")
  # every canonical label of a grid row is that row's label
  g <- mcg_grid()
  expect_identical(vapply(seq_len(nrow(g)), function(i)
    cv_canonical_label(g$zmin[i], g$min_share[i], g$cover_min[i], g$surface_exempt[i],
                       g$spacing_min[i]), character(1)), g$label)
})

test_that("a configuration's spacing_min is 0 when it records none", {
  expect_identical(cv_spacing_min(list(zmin = 5, min_share = 0.75)), 0)
  expect_identical(cv_spacing_min(list(spacing_min = NULL)), 0)
  expect_identical(cv_spacing_min(list(spacing_min = 8.5)), 8.5)
  expect_identical(cv_spacing_min(MCG_DECLARED), MCG_DECLARED$spacing_min)
})

test_that("components of a spacing-switched selection keep its spacing_min with the share gate", {
  sel <- list(zmin = 5, min_share = 0.75, cover_min = 0.6, surface_exempt = TRUE, spacing_min = 8)
  comp <- cv_components(sel)
  expect_identical(comp$versus_stock,
                   c(floor_only = "z5_s0_c0_e0", no_share_gate = "z5_s0_c0.6_e1",
                     no_exemption = "z5_s0.75_c0.6_e0_d8",
                     no_spacing_switch = "z5_s0.75_c0.6_e1", exemption_only = "z0_s0_c0.6_e1"))
  expect_identical(comp$marginal,
                   c(floor = "z0_s0.75_c0.6_e1_d8", share_gate = "z5_s0_c0.6_e1",
                     exemption = "z5_s0.75_c0.6_e0_d8", cover_switch = "z5_s0.75_c0_e1_d8",
                     spacing_switch = "z5_s0.75_c0.6_e1", gate_and_exemption = "z5_s0_c0_e0"))
  expect_true(all(unlist(comp) %in% mcg_grid()$label))
  # without the exemption, the floor or the cover threshold: the reductions that
  # turn into the selection or stock are dropped, the spacing parts remain
  ne <- cv_components(list(zmin = 0, min_share = 0.5, cover_min = 0.8, surface_exempt = FALSE,
                           spacing_min = 7.5))
  expect_identical(ne$versus_stock, c(no_spacing_switch = "z0_s0.5_c0.8_e0"))
  expect_identical(ne$marginal, c(cover_switch = "z0_s0.5_c0_e0_d7.5",
                                  spacing_switch = "z0_s0.5_c0.8_e0"))
  expect_true(all(unlist(ne) %in% mcg_grid()$label))
  # the declared configuration's parts are grid configurations
  expect_true(all(unlist(cv_components(MCG_DECLARED)) %in% mcg_grid()$label))
  # a selection without a spacing condition, recorded with spacing_min 0 or
  # without it, has neither spacing part: today's lists
  for (s in list(list(zmin = 5, min_share = 0.75, cover_min = 0.7, surface_exempt = TRUE),
                 list(zmin = 5, min_share = 0.75, cover_min = 0.7, surface_exempt = TRUE,
                      spacing_min = 0))) {
    comp <- cv_components(s)
    expect_identical(comp$versus_stock,
                     c(floor_only = "z5_s0_c0_e0", no_share_gate = "z5_s0_c0.7_e1",
                       no_exemption = "z5_s0.75_c0.7_e0", exemption_only = "z0_s0_c0.7_e1"))
    expect_identical(comp$marginal,
                     c(floor = "z0_s0.75_c0.7_e1", share_gate = "z5_s0_c0.7_e1",
                       exemption = "z5_s0.75_c0.7_e0", cover_switch = "z5_s0.75_c0_e1",
                       gate_and_exemption = "z5_s0_c0_e0"))
  }
})

test_that("a contrast row pools the plots both configurations cover, by summed counts", {
  cells <- syn_cells()
  drop <- cells$config == "chm_vwf" & cells$plot == "SJER_001" & cells$rung == "native"
  cells <- cells[!drop, ]
  ids <- unique(cv_ids(cells))
  tag <- cv_tag("headline", "cF1", "valid", "x")
  r <- cv_contrast_row(cells, ids, "native", "z5_s0_c0_e0", "chm_vwf", 50, 7, tag)
  expect_identical(r$n_plots, length(ids) - 1L)
  keep <- cells$rung == "native" & cv_ids(cells) != "SJER::SJER_001"
  a <- cells[keep & cells$config == "z5_s0_c0_e0", ]
  b <- cells[keep & cells$config == "chm_vwf", ]
  expect_equal(r$n_ref, sum(a$n_ref))
  expect_equal(r$a_n_det, sum(a$n_det))
  expect_equal(r$a_recall, sum(a$TP) / sum(a$n_ref))
  expect_equal(r$b_precision, sum(b$tp_core) / sum(b$n_det))
  expect_equal(r$d_F1, r$a_F1 - r$b_F1)
  expect_true(all(c(paste0(c("d_", "lo_", "hi_"), rep(CV_METRICS, each = 3)),
                    paste0("a_", CV_SIDE), paste0("b_", CV_SIDE)) %in% names(r)))
  expect_true(r$lo_F1 <= r$d_F1 && r$d_F1 <= r$hi_F1)
  same <- cv_contrast_row(cells, ids, "1", "stock", "stock", 50, 7, tag)
  expect_identical(c(same$d_cF1, same$lo_cF1, same$hi_cF1), c(0, 0, 0))
  expect_null(cv_contrast_row(cells, "NONE::x", "native", "stock", "chm_vwf", 50, 7, tag))
})

## ---- the study --------------------------------------------------------------------------------
test_that("selection reads only the calibration plots at native density", {
  S <- syn_settings()
  cells <- syn_cells()
  sp <- cv_split(cells, S$SEED, S$FRAC)
  expect_setequal(c(sp$calib, sp$valid), unique(cv_ids(cells)))
  expect_length(intersect(sp$calib, sp$valid), 0)
  expect_identical(cv_select(cells, sp$calib, "cF1")$config_id, 2L)
  # making config 3 the best on every validation plot, and on every plot at rung
  # 1, changes nothing; making it the best on the calibration plots does
  boosted <- syn_cells(boost = sp$valid)
  r1 <- cells$rung == "1" & cells$config == "z8_s0_c0_e0"
  boosted[r1, c("TP", "n_det")] <- list(30, 30)
  expect_identical(cv_select(boosted, sp$calib, "cF1")$config_id, 2L)
  expect_identical(cv_select(syn_cells(boost = sp$calib), sp$calib, "cF1")$config_id, 3L)
  s <- cv_select(cells, sp$calib, "cF1")
  expect_identical(s$label, "z5_s0_c0_e0")
  expect_identical(length(s$plots), length(sp$calib))
  expect_gt(s$selected$cF1, s$stock$cF1)
})

test_that("the study writes every analysis, held-out and in-sample apart", {
  S <- syn_settings()
  cells <- syn_cells()
  res <- cv_analyze(cells, S, boot_seed = 11L)
  sel <- res$selection; v <- res$validation
  expect_identical(sel$analysis, c("headline", rep("seed", 3), rep("leave_one_site_out", 2),
                                   "criterion", "all_plots"))
  expect_identical(sel$config[sel$analysis == "headline"], "z5_s0_c0_e0")
  expect_identical(sel$held_out_site[sel$analysis == "leave_one_site_out"], c("SJER", "WREF"))
  expect_identical(sel$criterion[sel$analysis == "criterion"], "F1")
  expect_identical(sel$n_calib_plots[sel$analysis == "all_plots"], 16L)
  expect_identical(res$n_calib + res$n_valid, 16L)
  # each selection reads only its own calibration plots: a seed its split's,
  # leaving one site out the other site's
  expect_identical(sel$n_calib_plots[sel$analysis == "seed"],
                   vapply(S$SEEDS, function(sd) length(cv_split(cells, sd, S$FRAC)$calib), 1L))
  expect_identical(sel$n_calib_plots[sel$analysis == "leave_one_site_out"], c(8L, 8L))
  # ... and not their content: config 3 made the best on the plots a selection
  # must not see leaves it at config 2, while a selection that sees them picks 3
  wref <- paste("WREF", sprintf("WREF_%03d", 1:8), sep = "::")
  s <- cv_analyze(syn_cells(boost = wref), syn_settings())$selection
  expect_identical(s$config_id[s$analysis == "leave_one_site_out"], c(3L, 2L))
  for (sd in 2:3) {
    sp <- cv_split(cells, sd, 0.5)
    s <- cv_analyze(syn_cells(boost = sp$valid), syn_settings(SEEDS = sd))$selection
    expect_identical(s$config_id[s$analysis == "seed"], 2L)
    s <- cv_analyze(syn_cells(boost = sp$calib), syn_settings(SEEDS = sd))$selection
    expect_identical(s$config_id[s$analysis == "seed"], 3L)
  }
  h <- v[v$analysis == "headline", ]
  # 3 scopes x 2 rungs x (valid vs stock, calib vs stock, 2 x valid vs chm_vwf)
  expect_identical(nrow(h), 3L * 2L * 4L)
  expect_setequal(unique(h$scope), c("SJER+WREF", "California", "Washington"))
  hv <- h[h$split == "valid" & h$config_b == "stock" & h$scope == "SJER+WREF" & h$rung == "native", ]
  expect_identical(hv$n_plots, res$n_valid)
  vids <- res$split$valid
  a <- cells[cells$rung == "native" & cells$config == "z5_s0_c0_e0" & cv_ids(cells) %in% vids, ]
  expect_equal(hv$a_n_det, sum(a$n_det))
  hc <- h[h$split == "calib" & h$scope == "SJER+WREF" & h$rung == "native", ]
  expect_identical(hc$n_plots, res$n_calib)
  expect_true(all(h$config_b[h$split == "calib"] == "stock"))
  expect_identical(sort(unique(h$config_b)), c("chm_vwf", "stock"))
  # components: z5 alone is the selection (no exemption) and its gate-free part is stock
  expect_false(any(startsWith(v$analysis, "component_")))
  expect_identical(sum(v$analysis == "seed"), 3L)
  lo <- v[v$analysis == "leave_one_site_out", ]
  expect_identical(lo$scope, c("SJER", "WREF"))
  expect_identical(lo$n_plots, c(8L, 8L))
  expect_identical(nrow(v[v$analysis == "criterion", ]), 3L)
  expect_true(all(c("analysis", "criterion", "seed", "held_out_site", "split", "scope", "rung",
                    "config_a", "config_b", "n_plots", "n_ref") == names(v)[1:11]))
  # the declared configuration and the tables
  dc <- cv_declared(res, S, "abc", "adopted")
  expect_identical(dc[c("zmin", "min_share", "cover_min", "surface_exempt", "spacing_min")],
                   list(zmin = 5, min_share = 0, cover_min = 0, surface_exempt = FALSE,
                        spacing_min = 0))
  expect_identical(dc$selection, "selected on the calibration plots at native density")
  expect_identical(c(dc$a, dc$radius, dc$half_dz, dc$cover_height, dc$crown_res, dc$crown_ws),
                   c(0.1, 1, 1, 2, 1, 5))
  expect_null(dc$top_prob)                       # the top height decides nothing
  expect_identical(c(dc$n_calibration_plots, dc$n_validation_plots), c(res$n_calib, res$n_valid))
  expect_match(dc$provenance, paste("test only the selection within the grid, not the grid's",
                                    "values or the choice of features"), fixed = TRUE)
  expect_match(dc$provenance, "the selection criterion was fixed after that pass", fixed = TRUE)
  expect_match(dc$provenance, paste("The crown-spacing switch, its measure and its grid values",
                                    "were added after further exploratory passes, which read the",
                                    "scores of all plots by stand top height and by crown density,",
                                    "the validation plots' nominal cores and censused subplots",
                                    "included, and the detection counts on four closed plots",
                                    "outside the benchmark that have no field reference."),
               fixed = TRUE)
  expect_false(grepl("  ", CV_PROVENANCE, fixed = TRUE))       # one string, single spaces
  expect_identical(CV_PROVENANCE, paste(
    "The gate's form and the grid values were informed by an exploratory pass over all plots of",
    "the five sites (calibration and validation plots alike), and the selection criterion was",
    "fixed after that pass. The crown-spacing switch, its measure and its grid values were",
    "added after further exploratory passes, which read the scores of all plots by stand top",
    "height and by crown density, the validation plots' nominal cores and censused subplots",
    "included, and the detection counts on four closed plots outside the benchmark that have",
    "no field reference. The held-out scores therefore test only the selection within the",
    "grid, not the grid's values or the choice of features."))
  md <- cv_tables_md(res, S, "abc", "adopted")
  expect_true(any(grepl("calib (in-sample)", md, fixed = TRUE)))
  expect_true(any(grepl("^## All plots \\(in-sample; not a held-out result\\)$", md)))
  expect_false(any(grepl("^## All-plots selection", md)))
  expect_true(any(grepl("exploratory pass", md)))
  heads <- c("## Components of the selection (validation plots, native density)",
             "## What each part adds (the selection minus a reduction of it)",
             "## Held-out by site (validation plots, native density)",
             "## Difference between regions (validation plots)",
             "## The whole grid against stock (native density)",
             "## Seeds (validation plots, native density)")
  expect_true(all(heads %in% md))
  # sections in that order, the all-plots section last
  expect_identical(order(match(heads, md)), seq_along(heads))
  expect_gt(match("## All plots (in-sample; not a held-out result)", md), max(match(heads, md)))
  expect_true(any(grepl("The first ten splits (`selection.csv` and `validation.csv` hold all",
                        md, fixed = TRUE)))
  expect_true(any(grepl("^\\| 1 \\| Washington \\| California \\| ", md)))
  expect_true(any(grepl("of the 2 non-stock grid configurations score above stock", md,
                        fixed = TRUE)))
  expect_true(any(grepl("of the 3 splits select the headline configuration", md, fixed = TRUE)))
  # the first such row is the headline table's (seed and criterion rows follow)
  row <- grep("^\\| SJER\\+WREF \\| native \\| valid \\| z5_s0_c0_e0 \\| stock \\|", md, value = TRUE)[1]
  expect_match(row, sprintf("%.3f [%.3f, %.3f]", hv$d_cF1, hv$lo_cF1, hv$hi_cF1), fixed = TRUE)
})

test_that("the study adds all-plots, site, region and whole-grid contrasts", {
  S <- syn_settings()
  cells <- syn_cells()
  # counts that differ from plot to plot and from site to site, so a contrast on
  # the wrong plots or with the regions swapped shows
  bump <- (as.integer(sub(".*_", "", cells$plot)) + 2L * (cells$site == "WREF")) %% 3
  cells$TP <- cells$TP + bump; cells$tp_core <- cells$tp_core + bump
  res <- cv_analyze(cells, S, boot_seed = 11L)
  v <- res$validation; lab <- res$selected$label
  ids_of <- function(ids, sites) ids[sub("::.*", "", ids) %in% sites]
  pooled <- function(cfg, ids) {
    r <- cells[cells$rung == "native" & cells$config == cfg & cv_ids(cells) %in% ids, ]
    mcg_pool(r)
  }
  native <- unique(cv_ids(cells[cells$rung == "native", ]))
  # all plots: the headline selection on every native plot of each scope, then each site
  ap <- v[v$analysis == "all_plots", ]
  expect_identical(ap$scope, c("SJER+WREF", "California", "Washington", "SJER", "WREF"))
  expect_true(all(ap$split == "all (in-sample)" & ap$rung == "native" & ap$config_a == lab &
                    ap$config_b == "stock" & ap$seed == S$SEED))
  for (i in seq_len(nrow(ap))) {
    sc <- switch(ap$scope[i], `SJER+WREF` = c("SJER", "WREF"), California = "SJER",
                 Washington = "WREF", ap$scope[i])
    ids <- ids_of(native, sc)
    expect_identical(ap$n_plots[i], length(ids))
    expect_equal(ap$a_n_det[i], pooled(lab, ids)$n_det)
    expect_equal(ap$d_cF1[i], pooled(lab, ids)$cF1 - pooled("stock", ids)$cF1)
  }
  # by site: the headline selection on each site's validation plots
  st <- v[v$analysis == "site", ]
  expect_identical(st$scope, c("SJER", "WREF"))
  expect_true(all(st$split == "valid" & st$rung == "native" & st$config_a == lab &
                    st$config_b == "stock"))
  for (i in seq_len(nrow(st))) {
    ids <- ids_of(res$split$valid, st$scope[i])
    expect_identical(st$n_plots[i], length(ids))
    expect_equal(st$a_n_det[i], pooled(lab, ids)$n_det)
    expect_equal(st$a_cF1[i], pooled(lab, ids)$cF1)
    expect_equal(st$d_cF1[i], pooled(lab, ids)$cF1 - pooled("stock", ids)$cF1)
  }
  # the two regions differ here, so the order of the sets matters
  expect_false(isTRUE(all.equal(res$regions$d1_cF1, res$regions$d2_cF1)))
  # regions: Washington minus California, one row per rung, equal to the headline rows
  rg <- res$regions
  expect_identical(rg$rung, c("native", "1"))
  expect_true(all(rg$analysis == "region_difference" & rg$split == "valid" &
                    rg$scope_1 == "Washington" & rg$scope_2 == "California" &
                    rg$config_a == lab & rg$config_b == "stock"))
  expect_identical(names(rg)[1:11], c("analysis", "criterion", "seed", "held_out_site", "split",
                                      "rung", "scope_1", "scope_2", "config_a", "config_b",
                                      "n_plots_1"))
  expect_true(all(paste0(c("d1_", "d2_", "dd_", "lo_", "hi_"), rep(CV_METRICS, each = 5)) %in%
                    names(rg)))
  h <- v[v$analysis == "headline" & v$split == "valid" & v$config_b == "stock", ]
  for (i in seq_len(nrow(rg))) {
    w <- h[h$scope == "Washington" & h$rung == rg$rung[i], ]
    ca <- h[h$scope == "California" & h$rung == rg$rung[i], ]
    expect_equal(rg$d1_cF1[i], w$d_cF1)
    expect_equal(rg$d2_cF1[i], ca$d_cF1)
    expect_equal(rg$dd_cF1[i], rg$d1_cF1[i] - rg$d2_cF1[i])
    expect_equal(rg$dd_F1[i], w$d_F1 - ca$d_F1)
    expect_identical(c(rg$n_plots_1[i], rg$n_plots_2[i]), c(w$n_plots, ca$n_plots))
    expect_true(rg$lo_cF1[i] <= rg$hi_cF1[i])
  }
  # the whole grid: one valid and one calib row per non-stock configuration, apart
  # from validation.csv
  g <- res$grid
  expect_false(any(v$analysis == "grid"))
  expect_identical(g$config_a, rep(c("z5_s0_c0_e0", "z8_s0_c0_e0"), each = 2))
  expect_identical(g$split, rep(c("valid", "calib"), 2))
  expect_true(all(g$analysis == "grid" & g$config_b == "stock" & g$rung == "native" &
                    g$scope == "SJER+WREF"))
  for (i in seq_len(nrow(g))) {
    ids <- res$split[[g$split[i]]]
    expect_equal(g$d_cF1[i], pooled(g$config_a[i], ids)$cF1 - pooled("stock", ids)$cF1)
  }
  gs <- cv_grid_summary(g, lab)
  expect_identical(c(gs$n, gs$n_ranked), c(2L, 3L))
  # how each seed's calibration ranking carries over: one row per seed, each with
  # its own selection; for the headline seed (its split and selection are the
  # headline's) the pooled point estimates agree with the bootstrap rows of the grid
  sg <- res$seed_grid
  expect_identical(names(sg), c("seed", "config", "n_configs", "pearson", "n_positive_valid",
                                "rank_valid"))
  expect_identical(sg$seed, S$SEEDS)
  expect_identical(sg$config, res$selection$config[res$selection$analysis == "seed"])
  expect_identical(sg$n_configs, rep(2L, length(S$SEEDS)))
  h <- sg[sg$seed == S$SEED, ]
  expect_identical(c(h$n_positive_valid, h$rank_valid), c(gs$n_positive_valid, gs$rank_valid))
  expect_equal(h$pearson, gs$pearson)
})

test_that("the tables summarise every seed and list the first ten", {
  S <- syn_settings(SEEDS = c(12:1), N_BOOT = 20L)
  res <- cv_analyze(syn_cells(), S, boot_seed = 11L)
  expect_identical(sum(res$selection$analysis == "seed"), 12L)
  expect_identical(sum(res$validation$analysis == "seed"), 12L)
  md <- cv_tables_md(res, S, "abc", "adopted")
  expect_true(any(grepl("of the 12 splits select the headline configuration", md, fixed = TRUE)))
  # the two tables hold seeds 1 to 10 only
  expect_identical(sum(grepl("^\\| seed \\| ", md)), 10L)
  expect_identical(sort(as.integer(sub("^\\| seed \\| (\\d+) .*$", "\\1",
                                       grep("^\\| seed \\| ", md, value = TRUE)))), 1:10)
  expect_identical(sum(grepl("^\\| SJER\\+WREF \\(seed \\d+\\) ", md)), 10L)
  expect_false(any(grepl("\\(seed 1[12]\\)", md)))
})

test_that("components of an exempting selection are scored against stock and against it", {
  cf <- rbind(SYN_CONFIGS[1:2, ],
              transform(SYN_CONFIGS[2, ], config = "z5_s0.75_c0.7_e1", config_id = 60L,
                        min_share = 0.75, cover_min = 0.7, surface_exempt = TRUE, TP = 14),
              transform(SYN_CONFIGS[2, ], config = "z5_s0.75_c0.7_e0", config_id = 20L,
                        min_share = 0.75, cover_min = 0.7, TP = 11),
              transform(SYN_CONFIGS[2, ], config = "z0_s0_c0.7_e1", config_id = 50L, zmin = 0,
                        cover_min = 0.7, surface_exempt = TRUE, TP = 12, n_det = 32),
              transform(SYN_CONFIGS[2, ], config = "z5_s0_c0.7_e1", config_id = 40L,
                        cover_min = 0.7, surface_exempt = TRUE, TP = 13),
              transform(SYN_CONFIGS[2, ], config = "z0_s0.75_c0.7_e1", config_id = 55L, zmin = 0,
                        min_share = 0.75, cover_min = 0.7, surface_exempt = TRUE, TP = 13,
                        n_det = 26),
              transform(SYN_CONFIGS[2, ], config = "z5_s0.75_c0_e1", config_id = 61L,
                        min_share = 0.75, cover_min = 0, surface_exempt = TRUE, TP = 12,
                        n_det = 26))
  cells <- syn_cells(sites = "WREF", n = 10, rungs = c("native", "1"), configs = cf)
  bump <- as.integer(sub(".*_", "", cells$plot)) %% 3
  cells$TP <- cells$TP + bump; cells$tp_core <- cells$tp_core + bump
  # other counts at rung 1, so a row pooled on the wrong rung shows
  r1 <- cells$rung == "1"
  cells$TP[r1] <- cells$TP[r1] - 1; cells$tp_core[r1] <- cells$tp_core[r1] - 1
  S <- syn_settings(SITES = "WREF", RUNGS = c("native", "1"), SEEDS = 1L)
  res <- cv_analyze(cells, S)
  lab <- res$selected$label
  expect_identical(lab, "z5_s0.75_c0.7_e1")
  v <- res$validation
  comp <- v[startsWith(v$analysis, "component_"), ]
  expect_identical(comp$analysis, paste0("component_", c("floor_only", "no_share_gate",
                                                         "no_exemption", "exemption_only")))
  expect_identical(comp$config_a, c("z5_s0_c0_e0", "z5_s0_c0.7_e1", "z5_s0.75_c0.7_e0",
                                    "z0_s0_c0.7_e1"))
  expect_true(all(comp$config_b == "stock" & comp$split == "valid" & comp$rung == "native"))
  # the selection minus each reduction: at native density the validation rows,
  # then the calibration rows, then the validation rows at rung 1
  mg <- v[startsWith(v$analysis, "marginal_"), ]
  parts <- c(floor = "z0_s0.75_c0.7_e1", share_gate = "z5_s0_c0.7_e1",
             exemption = "z5_s0.75_c0.7_e0", cover_switch = "z5_s0.75_c0_e1",
             gate_and_exemption = "z5_s0_c0_e0")
  np <- length(parts)
  expect_identical(mg$analysis, rep(paste0("marginal_", names(parts)), 3))
  expect_identical(mg$rung, rep(c("native", "1"), c(2L * np, np)))
  expect_identical(mg$split, rep(c("valid", "calib", "valid"), each = np))
  expect_true(all(mg$config_a == lab))
  expect_identical(mg$config_b, unname(rep(parts, 3)))
  for (i in seq_len(nrow(mg))) {
    ids <- res$split[[mg$split[i]]]
    p <- mcg_pool(cells[cells$rung == mg$rung[i] & cv_ids(cells) %in% ids &
                          cells$config %in% c(lab, mg$config_b[i]), ], "config")
    expect_identical(mg$n_plots[i], length(ids))
    expect_equal(mg$d_cF1[i], p$cF1[p$config == lab] - p$cF1[p$config == mg$config_b[i]])
  }
  # the rung-1 rows are not the native ones
  expect_false(isTRUE(all.equal(mg$d_cF1[mg$rung == "1"], mg$d_cF1[seq_len(np)])))
  expect_identical(res$components$marginal, parts)
  # the tables name every reduction and print the decimated rungs apart
  md <- cv_tables_md(res, S, "abc", "adopted")
  red <- grep("^Reductions \\(B\\): ", md, value = TRUE)
  expect_length(red, 1L)
  for (nm in names(parts))
    expect_match(red, sprintf("%s `%s`", nm, parts[[nm]]), fixed = TRUE)
  # without a spacing condition the cover switch applies the gate and the
  # exemption in every stand
  expect_true(paste("floor, share_gate and exemption are the selection without that part;",
                    "cover_switch is the selection with its gate and exemption applied in every",
                    "stand (cover_min 0); spacing_switch is the selection with its share gate",
                    "applied in every closed stand (spacing_min 0); gate_and_exemption is its",
                    "floor alone. Native density, validation plots then calibration plots",
                    "(in-sample):") %in% md)
  expect_false(any(grepl("whose crown spacing is at least", md, fixed = TRUE)))
  ladder <- "The same on the validation plots of the decimated rungs:"
  expect_true(ladder %in% md)
  # (the headline row at rung 1 is against stock)
  expect_identical(sum(grepl("^\\| WREF \\| 1 \\| valid \\| z5_s0.75_c0.7_e1 \\| z", md)), np)
  nat <- cv_analyze(cells, utils::modifyList(S, list(RUNGS = "native")))
  expect_false(any(nat$validation$rung == "1"))
  md <- cv_tables_md(nat, S, "abc", "adopted")
  expect_true(any(startsWith(md, "Reductions (B): ")))
  expect_false(ladder %in% md)
  # a component missing from the cells is left out
  res2 <- cv_analyze(cells[cells$config != "z5_s0_c0.7_e1", ],
                     syn_settings(SITES = "WREF", RUNGS = "native", SEEDS = 1L))
  expect_false(any(res2$validation$config_a == "z5_s0_c0.7_e1" |
                     res2$validation$config_b == "z5_s0_c0.7_e1"))
  expect_false("share_gate" %in% names(res2$components$marginal))
  expect_false(any(v$analysis == "leave_one_site_out"))   # one site only
  expect_false(any(v$analysis == "site"))
  expect_false(any(v$config_b == "chm_vwf"))
  expect_null(res$regions)                                 # one region only
  ap <- v[v$analysis == "all_plots", ]
  expect_identical(ap$scope, "WREF")                       # the one site is the one scope
  expect_identical(ap$n_plots, 10L)
})

# Grid rows of the real grid as synthetic configurations (SYN_CONFIGS columns).
syn_grid_configs <- function(labels, TP, n_det) {
  g <- mcg_grid()
  r <- g[match(labels, g$label), ]
  data.frame(config = r$label, config_id = r$config_id, zmin = r$zmin, min_share = r$min_share,
             cover_min = r$cover_min, surface_exempt = r$surface_exempt,
             spacing_min = r$spacing_min, TP = TP, n_det = n_det, stringsAsFactors = FALSE)
}

test_that("a spacing-switched selection carries its spacing_min into every record of it", {
  cf <- rbind(SYN_CONFIGS[1:3, ],
              syn_grid_configs(c("z5_s0.75_c0.6_e1", "z5_s0.75_c0.6_e1_d8"), c(12, 13), 24),
              SYN_CONFIGS[4, ])
  cells <- syn_cells(configs = cf)
  S <- syn_settings()
  res <- cv_analyze(cells, S, boot_seed = 11L)
  sel <- res$selected
  expect_identical(c(sel$label, as.character(sel$config_id), as.character(sel$spacing_min)),
                   c("z5_s0.75_c0.6_e1_d8", "360", "8"))
  expect_identical(cv_config_of(cells, 360L),
                   list(config_id = 360L, label = "z5_s0.75_c0.6_e1_d8", zmin = 5,
                        min_share = 0.75, cover_min = 0.6, surface_exempt = TRUE,
                        spacing_min = 8))
  expect_identical(cv_config_of(cells, 2L)$spacing_min, 0)
  # selection.csv: spacing_min follows surface_exempt
  s <- res$selection
  expect_identical(names(s)[match("surface_exempt", names(s)) + 1L], "spacing_min")
  expect_identical(s$spacing_min[s$analysis == "headline"], 8)
  # declared_config.json: spacing_min follows surface_exempt, the crown constants
  # cover_height
  dc <- cv_declared(res, S, "abc", "adopted")
  expect_identical(names(dc)[match("surface_exempt", names(dc)) + 1L], "spacing_min")
  expect_identical(names(dc)[match("cover_height", names(dc)) + 1:2], c("crown_res", "crown_ws"))
  expect_identical(c(dc$spacing_min, dc$crown_res, dc$crown_ws),
                   c(8, MCG_CROWN_RES, MCG_CROWN_WS))
  expect_false("top_prob" %in% names(dc))
  # the declared label is the library's label of the declared values
  expect_identical(dc$label, mcg_config_label(dc[c("zmin", "min_share", "cover_min",
                                                   "surface_exempt", "spacing_min")]))
  # the parts in the cells: without the spacing switch, against stock and as the
  # selection's reduction
  v <- res$validation
  expect_identical(v$config_a[v$analysis == "component_no_spacing_switch"], "z5_s0.75_c0.6_e1")
  hs <- v[v$analysis == "marginal_spacing_switch", ]
  expect_identical(hs$split, c("valid", "calib", "valid"))
  expect_true(all(hs$config_a == sel$label & hs$config_b == "z5_s0.75_c0.6_e1"))
  # the tables name spacing_min in the headline sentence, the selection table and
  # the reductions paragraph, whose cover switch keeps the spacing condition
  md <- cv_tables_md(res, S, "abc", "adopted")
  expect_true(any(grepl(paste("Selected `z5_s0.75_c0.6_e1_d8` (config_id 360: zmin 5, min_share",
                              "0.75, cover_min 0.6, surface_exempt TRUE, spacing_min 8), selected",
                              "on"), md, fixed = TRUE)))
  expect_true(any(grepl("| surface_exempt | spacing_min | Selection plots |", md, fixed = TRUE)))
  expect_true(any(startsWith(md, paste("| headline | 1 |  | cF1 | z5_s0.75_c0.6_e1_d8 (id 360) |",
                                        "5 | 0.75 | 0.6 | TRUE | 8 | "))))
  expect_true(paste("floor, share_gate and exemption are the selection without that part;",
                    "cover_switch is the selection with its exemption applied in every stand and",
                    "its share gate in every stand whose crown spacing is at least 8 m (cover_min",
                    "0); spacing_switch is the selection with its share gate applied in every",
                    "closed stand (spacing_min 0); gate_and_exemption is its floor alone. Native",
                    "density, validation plots then calibration plots (in-sample):") %in% md)
  expect_false(any(grepl("gate and exemption applied in every stand", md, fixed = TRUE)))
  # (only the reductions present in the cells)
  expect_identical(res$components,
                   list(versus_stock = c(floor_only = "z5_s0_c0_e0",
                                         no_spacing_switch = "z5_s0.75_c0.6_e1"),
                        marginal = c(spacing_switch = "z5_s0.75_c0.6_e1",
                                     gate_and_exemption = "z5_s0_c0_e0")))
  expect_true(paste("Reductions (B): spacing_switch `z5_s0.75_c0.6_e1`; gate_and_exemption",
                    "`z5_s0_c0_e0`.") %in% md)
  # the sentence follows the selection's own spacing_min
  r85 <- res
  r85$selected <- utils::modifyList(sel, list(spacing_min = 8.5, label = "z5_s0.75_c0.6_e1_d8.5"))
  m85 <- cv_tables_md(r85, S, "abc", "adopted")
  expect_true(any(grepl("its share gate in every stand whose crown spacing is at least 8.5 m",
                        m85, fixed = TRUE)))
  expect_false(any(grepl("at least 8 m", m85, fixed = TRUE)))
})

# Counts that differ by plot and by site, so contrasts on the wrong plots show.
syn_bumped <- function(...) {
  cells <- syn_cells(...)
  bump <- (as.integer(sub(".*_", "", cells$plot)) + 2L * (cells$site == "WREF")) %% 3
  cells$TP <- cells$TP + bump * (cells$config != "z8_s0_c0_e0")
  cells$tp_core <- cells$tp_core + bump * (cells$config != "z8_s0_c0_e0")
  cells
}

test_that("REFERENCE contrasts the selection with a grid configuration", {
  cells <- syn_bumped()
  ref <- "z8_s0_c0_e0"
  S <- syn_settings(REFERENCE = ref)
  res <- cv_analyze(cells, S, boot_seed = 11L)
  lab <- res$selected$label
  expect_identical(lab, "z5_s0_c0_e0")
  expect_identical(res$reference, ref)
  v <- res$validation
  r <- v[v$analysis == "reference", ]
  # the validation plots by scope and rung, then the calibration plots at native
  expect_identical(r$split, c(rep("valid", 6), "calib"))
  expect_identical(r$scope, c(rep(c("SJER+WREF", "California", "Washington"), each = 2),
                              "SJER+WREF"))
  expect_identical(r$rung, c(rep(c("native", "1"), 3), "native"))
  rs <- v[v$analysis == "reference_site", ]
  expect_identical(c(rs$scope, rs$split, rs$rung),
                   c("SJER", "WREF", "valid", "valid", "native", "native"))
  both <- rbind(r, rs)
  expect_true(all(both$config_a == lab & both$config_b == ref))
  expect_true(all(both$criterion == "cF1" & both$seed == S$SEED))
  # selected minus reference, on the plots of each row
  pooled <- function(cfg, ids, rung) mcg_pool(cells[cells$rung == rung & cells$config == cfg &
                                                      cv_ids(cells) %in% ids, ])
  scope_sites <- list(`SJER+WREF` = c("SJER", "WREF"), California = "SJER", Washington = "WREF",
                      SJER = "SJER", WREF = "WREF")
  for (i in seq_len(nrow(both))) {
    ids <- res$split[[both$split[i]]]
    ids <- ids[sub("::.*", "", ids) %in% scope_sites[[both$scope[i]]]]
    a <- pooled(lab, ids, both$rung[i]); b <- pooled(ref, ids, both$rung[i])
    expect_identical(both$n_plots[i], length(ids))
    expect_equal(c(both$a_n_det[i], both$b_n_det[i]), c(a$n_det, b$n_det))
    expect_equal(both$d_cF1[i], a$cF1 - b$cF1)
    expect_equal(both$d_F1[i], a$F1 - b$F1)
  }
  expect_gt(abs(r$d_cF1[1]), 0)
  # in validation.csv after the rows by site, before the components and seeds
  pos <- which(v$analysis %in% c("reference", "reference_site"))
  expect_gt(min(pos), max(which(v$analysis == "site")))
  expect_lt(max(pos), min(which(v$analysis == "seed")))
  expect_identical(v$analysis[pos], c(rep("reference", 7), rep("reference_site", 2)))
  # one site: no rows by site
  one <- cv_analyze(cells[cells$site == "WREF", ],
                    syn_settings(SITES = "WREF", REFERENCE = ref, SEEDS = 1L))
  expect_identical(sum(one$validation$analysis == "reference"), 3L)
  expect_false(any(one$validation$analysis == "reference_site"))
  # without REFERENCE nothing is added; an unknown label or a reference detector
  # stops; the selection itself is skipped with a note
  none <- cv_analyze(cells, syn_settings(), boot_seed = 11L)
  expect_false(any(none$validation$analysis %in% c("reference", "reference_site")))
  expect_null(none$reference)
  rest <- v[!v$analysis %in% c("reference", "reference_site"), ]
  rownames(rest) <- NULL
  expect_identical(none$validation, rest)
  expect_error(cv_analyze(cells, syn_settings(REFERENCE = "z9_s0_c0_e0")),
               "REFERENCE=z9_s0_c0_e0 is not a grid configuration of cells.csv", fixed = TRUE)
  expect_error(cv_analyze(cells, syn_settings(REFERENCE = "chm_vwf")),
               "REFERENCE=chm_vwf is not a grid configuration", fixed = TRUE)
  expect_output(self <- cv_analyze(cells, syn_settings(REFERENCE = lab)),
                paste("REFERENCE=z5_s0_c0_e0 is the headline selection itself; the reference",
                      "contrasts are skipped"), fixed = TRUE)
  expect_false(any(self$validation$analysis %in% c("reference", "reference_site")))
  expect_null(self$reference)
})

test_that("the tables hold the reference section only with reference rows", {
  cells <- syn_bumped()
  ref <- "z8_s0_c0_e0"
  S <- syn_settings(REFERENCE = ref, N_BOOT = 20L)
  res <- cv_analyze(cells, S, boot_seed = 11L)
  md <- cv_tables_md(res, S, "abc", "adopted")
  head <- "## The selection against the reference configuration `z8_s0_c0_e0`"
  h <- match(head, md)
  expect_false(is.na(h))
  expect_identical(md[h + 1:3], c("", paste(
    "Δ = selected − reference. Validation plots by scope and rung, the calibration plots at",
    "native density (in-sample), then each site's validation plots at native density:"), ""))
  expect_gt(h, match("## Held-out by site (validation plots, native density)", md))
  expect_lt(h, match("## Difference between regions (validation plots)", md))
  rows <- grep("^\\| [^|]+ \\| [^|]+ \\| [^|]+ \\| z5_s0_c0_e0 \\| z8_s0_c0_e0 \\|", md,
               value = TRUE)
  expect_length(rows, 9L)
  expect_true(startsWith(rows[7], "| SJER+WREF | native | calib (in-sample) | "))
  expect_true(startsWith(rows[8], "| SJER | native | valid | "))
  # no censused rows without the censused results
  expect_false(any(grepl("Inside the censused subplots at native density", md, fixed = TRUE)))
  # none without reference rows: no REFERENCE, or the selection itself
  expect_false(any(startsWith(cv_tables_md(cv_analyze(cells, syn_settings(N_BOOT = 20L)), S,
                                           "abc", "adopted"),
                              "## The selection against the reference")))
  utils::capture.output(self <- cv_analyze(cells, syn_settings(REFERENCE = "z5_s0_c0_e0",
                                                                N_BOOT = 20L)))
  expect_false(any(startsWith(cv_tables_md(self, S, "abc", "adopted"),
                              "## The selection against the reference")))
})

# A spacing-switched configuration (z5_s0.75_c0.6_e1_d8, the best unless `TP`
# says otherwise), the same at spacing_min 0, 7.5 and 9, two reductions of the
# one at spacing_min 0 that keep its share gate, and a configuration at
# spacing_min 8.5 whose variant of z5_s0.75_c0.6_e1 is not in the cells; with
# stock, z5_s0_c0_e0 and CHM-VWF. Counts differ by plot and site, and at rung 1.
SYN_SPACING <- c("z5_s0.75_c0.6_e1_d8", "z5_s0.75_c0.6_e1", "z5_s0.75_c0.6_e1_d7.5",
                 "z5_s0.75_c0.6_e1_d9", "z5_s0.75_c0.6_e0", "z5_s0.75_c0_e1",
                 "z0_s0.75_c0.6_e1_d8.5")
syn_spacing_cells <- function(TP = c(15, 13, 12, 14, 11, 12, 13)) {
  cf <- rbind(SYN_CONFIGS[1:2, ],
              syn_grid_configs(SYN_SPACING, TP, c(24, 26, 28, 25, 22, 27, 26)),
              SYN_CONFIGS[4, ])
  cells <- syn_cells(configs = cf)
  bump <- (as.integer(sub(".*_", "", cells$plot)) + 2L * (cells$site == "WREF")) %% 3
  r1 <- cells$rung == "1"
  cells$TP <- cells$TP + bump - r1; cells$tp_core <- cells$tp_core + bump - r1
  cells
}

# The lines of a tables.md section, from its heading to the next one.
md_section <- function(md, head) {
  i <- match(head, md)
  if (is.na(i)) return(character())
  nxt <- which(startsWith(md, "## ") & seq_along(md) > i)
  md[i:(if (length(nxt)) nxt[1] - 1L else length(md))]
}

# The rung, split, A and B of the contrast rows of tables.md lines.
md_rows <- function(lines) {
  r <- grep("^\\| [^|]+ \\| [^|]+ \\| [^|]+ \\| [^|]+ \\| [^|]+ \\| \\d+ \\|", lines, value = TRUE)
  sub("^\\| [^|]+ \\| ([^|]+) \\| ([^|]+) \\| ([^|]+) \\| ([^|]+) \\|.*$", "\\1|\\2|\\3|\\4", r)
}

test_that("a share-gated selection is set against itself at the grid's other spacing_min values", {
  cells <- syn_spacing_cells()
  S <- syn_settings(SEEDS = 1L, N_BOOT = 40L)
  res <- cv_analyze(cells, S, boot_seed = 11L)
  lab <- res$selected$label
  expect_identical(lab, "z5_s0.75_c0.6_e1_d8")
  # 0, 7.5 and 9, increasing: not 8, the selection's own value, nor 8.5, whose
  # variant is not in the cells
  tv <- c(spacing_min_0 = "z5_s0.75_c0.6_e1", spacing_min_7.5 = "z5_s0.75_c0.6_e1_d7.5",
          spacing_min_9 = "z5_s0.75_c0.6_e1_d9")
  expect_identical(res$spacing_min_variants, tv)
  expect_false(lab %in% res$spacing_min_variants)
  v <- res$validation
  tm <- v[startsWith(v$analysis, "spacing_min_"), ]
  # native density on the validation, then the calibration plots, then rung 1
  expect_identical(tm$analysis, rep(names(tv), 3))
  expect_identical(tm$split, rep(c("valid", "calib", "valid"), each = 3))
  expect_identical(tm$rung, rep(c("native", "native", "1"), each = 3))
  expect_true(all(tm$config_a == lab & tm$scope == "SJER+WREF" & tm$criterion == "cF1" &
                    tm$seed == S$SEED & is.na(tm$held_out_site)))
  expect_identical(tm$config_b, unname(rep(tv, 3)))
  # selected minus the variant on the plots of each row
  for (i in seq_len(nrow(tm))) {
    ids <- res$split[[tm$split[i]]]
    p <- mcg_pool(cells[cells$rung == tm$rung[i] & cv_ids(cells) %in% ids &
                          cells$config %in% c(lab, tm$config_b[i]), ], "config")
    a <- p[p$config == lab, ]; b <- p[p$config == tm$config_b[i], ]
    expect_identical(tm$n_plots[i], length(ids))
    expect_equal(c(tm$a_n_det[i], tm$b_n_det[i]), c(a$n_det, b$n_det))
    expect_equal(c(tm$d_cF1[i], tm$d_recall[i]), c(a$cF1 - b$cF1, a$recall - b$recall))
  }
  expect_true(all(tm$d_cF1 != 0))
  expect_false(isTRUE(all.equal(tm$d_cF1[7:9], tm$d_cF1[1:3])))   # rung 1 is not native
  # after the selection's parts, before the seeds
  pos <- which(startsWith(v$analysis, "spacing_min_"))
  expect_gt(min(pos), max(which(startsWith(v$analysis, "marginal_"))))
  expect_lt(max(pos), min(which(v$analysis == "seed")))
  # spacing_min 0 is the spacing-switch part: the same rows under another name
  hs <- v[v$analysis == "marginal_spacing_switch", ]
  t0 <- tm[tm$analysis == "spacing_min_0", ]
  expect_identical(nrow(hs), 3L)
  rownames(hs) <- NULL; rownames(t0) <- NULL
  expect_identical(t0[setdiff(names(t0), "analysis")], hs[setdiff(names(hs), "analysis")])
  # a share gate without a spacing condition: 7.5, 8 and 9, not 0
  r0 <- cv_analyze(syn_spacing_cells(TP = c(13, 15, 12, 14, 11, 12, 13)), S, boot_seed = 11L)
  expect_identical(r0$selected$label, "z5_s0.75_c0.6_e1")
  expect_identical(r0$spacing_min_variants,
                   c(spacing_min_7.5 = "z5_s0.75_c0.6_e1_d7.5",
                     spacing_min_8 = "z5_s0.75_c0.6_e1_d8", spacing_min_9 = "z5_s0.75_c0.6_e1_d9"))
  t0 <- r0$validation[startsWith(r0$validation$analysis, "spacing_min_"), ]
  expect_identical(t0$analysis, rep(c("spacing_min_7.5", "spacing_min_8", "spacing_min_9"), 3))
  expect_true(all(t0$config_a == "z5_s0.75_c0.6_e1"))
  expect_false(any(r0$validation$analysis == "marginal_spacing_switch"))
  # no share gate: no spacing condition to vary, whatever the cells hold
  ns <- cv_analyze(syn_spacing_cells(TP = rep(10, 7)), S, boot_seed = 11L)
  expect_identical(ns$selected$label, "z5_s0_c0_e0")
  expect_false(any(startsWith(ns$validation$analysis, "spacing_min_")))
  expect_null(ns$spacing_min_variants)
  # a share gate without any variant in the cells
  nv <- cv_analyze(cells[!cells$config %in% tv, ], S, boot_seed = 11L)
  expect_identical(nv$selected$label, lab)
  expect_false(any(startsWith(nv$validation$analysis, "spacing_min_")))
  expect_null(nv$spacing_min_variants)
})

test_that("the tables hold the spacing_min section only with its rows, in ladder order", {
  cells <- syn_spacing_cells()
  S <- syn_settings(SEEDS = 1L, N_BOOT = 20L)
  res <- cv_analyze(cells, S, boot_seed = 11L)
  md <- cv_tables_md(res, S, "abc", "adopted")
  head <- "## The selection at other values of spacing_min"
  h <- match(head, md)
  expect_false(is.na(h))
  expect_identical(md[h + 1:3], c("", paste(
    "Δ = selected − the same configuration at another spacing_min (0 = the share gate in every",
    "closed stand). Native density, validation plots then calibration plots (in-sample), then",
    "the validation plots of the decimated rungs:"), ""))
  expect_gt(h, match("## What each part adds (the selection minus a reduction of it)", md))
  expect_identical(match("## Held-out by site (validation plots, native density)", md),
                   h + 16L)                   # heading, 3 lines, table of 2 + 9 lines, blank
  sec <- md_section(md, head)
  tv <- res$spacing_min_variants
  # increasing spacing_min within each block: 0, 7.5, 9
  expect_identical(unname(tv), c("z5_s0.75_c0.6_e1", "z5_s0.75_c0.6_e1_d7.5",
                                 "z5_s0.75_c0.6_e1_d9"))
  expect_identical(md_rows(sec), paste(rep(c("native", "native", "1"), each = 3),
                                       rep(c("valid", "calib (in-sample)", "valid"), each = 3),
                                       "z5_s0.75_c0.6_e1_d8", unname(rep(tv, 3)), sep = "|"))
  # the rows of validation.csv in any order make the same table
  shuffled <- res
  shuffled$validation <- res$validation[rev(seq_len(nrow(res$validation))), ]
  expect_identical(md_section(cv_tables_md(shuffled, S, "abc", "adopted"), head), sec)
  # the parts table keeps the selection's own reductions only
  parts <- md_rows(md_section(md, "## What each part adds (the selection minus a reduction of it)"))
  expect_true(all(sub("^[^|]+\\|[^|]+\\|([^|]+)\\|.*$", "\\1", parts) == "z5_s0.75_c0.6_e1_d8"))
  expect_false(any(grepl("d7.5|d9", parts)))
  # no rows, no section
  for (r in list(cv_analyze(syn_spacing_cells(TP = rep(10, 7)), S, boot_seed = 11L),
                 cv_analyze(cells[!cells$config %in% tv, ], S, boot_seed = 11L)))
    expect_false(head %in% cv_tables_md(r, S, "abc", "adopted"))
})

test_that("with REFERENCE the reference's own parts are its reductions in the cells", {
  cells <- syn_spacing_cells()
  ref <- "z5_s0.75_c0.6_e1"
  S <- syn_settings(SEEDS = 1L, N_BOOT = 40L, REFERENCE = ref)
  res <- cv_analyze(cells, S, boot_seed = 11L)
  lab <- res$selected$label
  expect_identical(lab, "z5_s0.75_c0.6_e1_d8")
  # the reference's reductions in the cells (its floor and share gate are not,
  # and without a spacing condition it has no spacing switch), and the
  # selection's own parts, which are other ones
  rc <- c(exemption = "z5_s0.75_c0.6_e0", cover_switch = "z5_s0.75_c0_e1",
          gate_and_exemption = "z5_s0_c0_e0")
  expect_identical(res$reference_components, rc)
  rcfg <- cv_config_of(cells, cells$config_id[cells$config == ref][1])
  expect_false("spacing_switch" %in% names(cv_components(rcfg)$marginal))
  expect_identical(res$components$marginal,
                   c(spacing_switch = "z5_s0.75_c0.6_e1", gate_and_exemption = "z5_s0_c0_e0"))
  v <- res$validation
  rm <- v[startsWith(v$analysis, "reference_marginal_"), ]
  expect_identical(rm$analysis, rep(paste0("reference_marginal_", names(rc)), 3))
  expect_identical(rm$split, rep(c("valid", "calib", "valid"), each = 3))
  expect_identical(rm$rung, rep(c("native", "native", "1"), each = 3))
  expect_true(all(rm$config_a == ref & rm$scope == "SJER+WREF" & rm$criterion == "cF1" &
                    rm$seed == S$SEED & is.na(rm$held_out_site)))
  expect_identical(rm$config_b, unname(rep(rc, 3)))
  # the reference minus its reduction on the plots of each row
  for (i in seq_len(nrow(rm))) {
    ids <- res$split[[rm$split[i]]]
    p <- mcg_pool(cells[cells$rung == rm$rung[i] & cv_ids(cells) %in% ids &
                          cells$config %in% c(ref, rm$config_b[i]), ], "config")
    a <- p[p$config == ref, ]; b <- p[p$config == rm$config_b[i], ]
    expect_identical(rm$n_plots[i], length(ids))
    expect_equal(c(rm$a_n_det[i], rm$b_n_det[i]), c(a$n_det, b$n_det))
    expect_equal(c(rm$d_cF1[i], rm$d_precision[i]), c(a$cF1 - b$cF1, a$precision - b$precision))
  }
  expect_true(all(rm$d_cF1 != 0))
  # after the reference rows, before the selection's parts; the selection's rows
  # are those of a run without REFERENCE
  pos <- which(startsWith(v$analysis, "reference_marginal_"))
  expect_gt(min(pos), max(which(v$analysis %in% c("reference", "reference_site"))))
  expect_lt(max(pos), min(which(startsWith(v$analysis, "marginal_"))))
  none <- cv_analyze(cells, syn_settings(SEEDS = 1L, N_BOOT = 40L), boot_seed = 11L)
  expect_false(any(startsWith(none$validation$analysis, "reference")))
  expect_null(none$reference_components)
  rest <- v[!startsWith(v$analysis, "reference"), ]
  rownames(rest) <- NULL
  expect_identical(none$validation, rest)
  # a reference none of whose reductions is in the cells: its rows, no parts
  bare <- cv_analyze(cells, utils::modifyList(S, list(REFERENCE = "z0_s0.75_c0.6_e1_d8.5")),
                     boot_seed = 11L)
  expect_true(any(bare$validation$analysis == "reference"))
  expect_false(any(startsWith(bare$validation$analysis, "reference_marginal_")))
  expect_null(bare$reference_components)
  # a reference with a spacing condition has its own spacing switch
  r9 <- cv_analyze(cells, utils::modifyList(S, list(REFERENCE = "z5_s0.75_c0.6_e1_d9")),
                   boot_seed = 11L)
  expect_identical(r9$reference_components,
                   c(spacing_switch = "z5_s0.75_c0.6_e1", gate_and_exemption = "z5_s0_c0_e0"))
  r9s <- r9$validation[r9$validation$analysis == "reference_marginal_spacing_switch", ]
  expect_identical(r9s$split, c("valid", "calib", "valid"))
  expect_true(all(r9s$config_a == "z5_s0.75_c0.6_e1_d9" & r9s$config_b == "z5_s0.75_c0.6_e1"))
  # the selection itself as the reference: nothing
  utils::capture.output(self <- cv_analyze(cells, utils::modifyList(S, list(REFERENCE = lab)),
                                           boot_seed = 11L))
  expect_false(any(startsWith(self$validation$analysis, "reference")))
  expect_null(self$reference_components)
})

test_that("the tables show the reference's own parts in the reference section when present", {
  cells <- syn_spacing_cells()
  ref <- "z5_s0.75_c0.6_e1"
  S <- syn_settings(SEEDS = 1L, N_BOOT = 20L, REFERENCE = ref)
  res <- cv_analyze(cells, S, boot_seed = 11L)
  # a censused reference contrast, so its paragraph's place shows
  cs <- list(contrasts = data.frame(split = "all", scope = "SJER+WREF", n_plots = 3L,
                                    metric = c("recall", "precision", "F1"), estimate = 0.01,
                                    lower = -0.01, upper = 0.02, stringsAsFactors = FALSE),
             scores = data.frame(split = "all", scope = "SJER+WREF",
                                 detector = rep(c("multichm_gated", "reference"), each = 3),
                                 metric = c("recall", "precision", "F1"), estimate = 0.5,
                                 n_ref = 30, n_det = 20, stringsAsFactors = FALSE))
  md <- cv_tables_md(res, S, "abc", "adopted", census_reference = cs)
  line <- paste("The reference configuration's own parts (the reference minus a reduction of it):",
                "exemption `z5_s0.75_c0.6_e0`; cover_switch `z5_s0.75_c0_e1`;",
                "gate_and_exemption `z5_s0_c0_e0`. Native density, validation plots then",
                "calibration plots (in-sample), then the validation plots of the decimated",
                "rungs:")
  i <- match(line, md)
  expect_false(is.na(i))
  sec <- md_section(md, sprintf("## The selection against the reference configuration `%s`", ref))
  expect_true(line %in% sec)
  # after the by-site table, before the censused paragraph
  lab <- res$selected$label
  site <- max(grep(sprintf("^\\| WREF \\| native \\| valid \\| %s \\| %s \\|", lab, ref), md))
  expect_identical(i, site + 2L)
  expect_identical(md[i + 1L], "")
  expect_identical(md[i + 13L], "")                       # table of 2 + 9 lines
  expect_identical(md[i + 14L], paste("Inside the censused subplots at native density, from the",
                                      "arm's persisted detections under each configuration; Δ =",
                                      "selected − reference:"))
  expect_identical(md_rows(md[i + 2:12]),
                   paste(rep(c("native", "native", "1"), each = 3),
                         rep(c("valid", "calib (in-sample)", "valid"), each = 3), ref,
                         unname(rep(res$reference_components, 3)), sep = "|"))
  # the selection's parts table does not pick them up
  parts <- md_rows(md_section(md, "## What each part adds (the selection minus a reduction of it)"))
  expect_true(all(sub("^[^|]+\\|[^|]+\\|([^|]+)\\|.*$", "\\1", parts) == lab))
  # without parts in the cells, or without reference rows, no such paragraph
  bare <- cv_analyze(cells, utils::modifyList(S, list(REFERENCE = "z0_s0.75_c0.6_e1_d8.5")),
                     boot_seed = 11L)
  mb <- cv_tables_md(bare, S, "abc", "adopted")
  expect_true("## The selection against the reference configuration `z0_s0.75_c0.6_e1_d8.5`" %in%
                mb)
  expect_false(any(startsWith(mb, "The reference configuration's own parts")))
  mn <- cv_tables_md(cv_analyze(cells, syn_settings(SEEDS = 1L, N_BOOT = 20L), boot_seed = 11L),
                     S, "abc", "adopted")
  expect_false(any(startsWith(mn, "The reference configuration's own parts")))
})

test_that("the whole-grid summary counts, ranks and correlates the configurations", {
  row <- function(split, cfg, a, b, lo, hi)
    data.frame(analysis = "grid", split = split, config_a = cfg, config_b = "stock",
               a_cF1 = a, b_cF1 = b, d_cF1 = a - b, lo_cF1 = lo, hi_cF1 = hi,
               stringsAsFactors = FALSE)
  g <- rbind(row("valid", c("a", "b", "c"), c(0.30, 0.25, 0.18), 0.20,
                 c(0.02, -0.01, -0.05), c(0.20, 0.10, -0.01)),
             row("calib", c("a", "b", "c"), c(0.28, 0.21, 0.17), 0.20,
                 c(0.01, -0.02, -0.06), c(0.15, 0.04, 0.01)))
  s <- cv_grid_summary(g, "b")
  expect_identical(c(s$n, s$n_ranked), c(3L, 4L))
  expect_identical(c(s$n_positive_valid, s$n_excludes_zero_valid, s$n_below_valid), c(2L, 1L, 1L))
  expect_equal(c(s$median_valid, s$min_valid, s$max_valid, s$selected_valid),
               c(0.05, -0.02, 0.10, 0.05))
  expect_identical(s$rank_valid, 2L)                # a 0.30, b 0.25, stock 0.20, c 0.18
  expect_identical(cv_grid_summary(g, "c")$rank_valid, 4L)
  expect_identical(cv_grid_summary(g, "stock")$rank_valid, 3L)
  expect_identical(cv_grid_summary(g, "stock")$selected_valid, 0)
  expect_identical(s$n_positive_calib, 2L)
  expect_equal(s$median_calib, 0.01)
  expect_equal(s$pearson, stats::cor(c(0.08, 0.01, -0.03), c(0.10, 0.05, -0.02)))
  expect_equal(s$spearman, 1)
  one <- cv_grid_summary(g[g$config_a == "a", ], "a")
  expect_identical(c(one$n, one$rank_valid), c(1L, 1L))
  expect_true(is.na(one$pearson) && is.na(one$spearman))
  expect_null(cv_grid_summary(NULL, "a"))
  md <- cv_md_grid(s)
  expect_match(md, "On the validation plots 2 of the 3 non-stock grid configurations", fixed = TRUE)
  expect_match(md, "ranks 2 of 4, stock included", fixed = TRUE)
})

test_that("the seed summary counts the selections and the held-out changes", {
  sel <- data.frame(analysis = c("headline", rep("seed", 5), "all_plots"),
                    seed = c(1L, 1:5, NA),
                    config = c("A", "A", "B", "C", "B", "C", "B"),
                    config_id = c(7L, 7L, 9L, 4L, 9L, 4L, 9L),
                    zmin = c(5, 5, 8, 5, 8, 5, 8), min_share = c(0.75, 0.75, 0.5, 0, 0.5, 0, 0.5),
                    cover_min = 0.6, surface_exempt = c(TRUE, TRUE, TRUE, FALSE, TRUE, FALSE, TRUE),
                    spacing_min = c(8.5, 8.5, 0, 0, 0, 0, 0), stringsAsFactors = FALSE)
  val <- data.frame(analysis = c("headline", rep("seed", 5)), seed = c(1L, 1:5),
                    d_cF1 = c(0.03, 0.03, 0.01, -0.02, 0.05, 0.03),
                    lo_cF1 = c(0.01, 0.01, -0.01, -0.04, 0.02, 0.001), stringsAsFactors = FALSE)
  s <- cv_seed_summary(sel, val, "A", 1L)
  expect_identical(c(s$n, s$n_selected), c(5L, 1L))
  # B and C are selected twice each: the tie goes to the smaller config_id (C, 4)
  expect_identical(c(s$top_label, as.character(s$top_n)), c("C", "2"))
  expect_identical(s$zmin, c(`5` = 3L, `8` = 2L))
  expect_identical(s$min_share, c(`0` = 2L, `0.5` = 2L, `0.75` = 1L))
  expect_identical(s$cover_min, c(`0.6` = 5L))
  expect_identical(s$surface_exempt, c(`FALSE` = 2L, `TRUE` = 3L))
  expect_identical(s$spacing_min, c(`0` = 4L, `8.5` = 1L))
  expect_equal(c(s$d_min, s$d_median, s$d_mean, s$d_max), c(-0.02, 0.03, 0.02, 0.05))
  expect_identical(c(s$n_positive, s$n_excludes_zero), c(4L, 3L))
  expect_equal(s$headline_d_cF1, 0.03)
  expect_identical(s$n_at_least_headline, 3L)
  expect_true(is.na(cv_seed_summary(sel, val, "A", 99L)$n_at_least_headline))
  expect_null(cv_seed_summary(sel[sel$analysis != "seed", ], val, "A", 1L))
  md <- cv_md_seeds(s, "A", 1L)
  expect_true(any(grepl("1 of the 5 splits select the headline configuration `A`", md,
                        fixed = TRUE)))
  expect_true(any(grepl("zmin 5 in 3, 8 in 2; min_share 0 in 2, 0.5 in 2, 0.75 in 1", md,
                        fixed = TRUE)))
  expect_true(any(grepl("surface_exempt FALSE in 2, TRUE in 3; spacing_min 0 in 4, 8.5 in 1.",
                        md, fixed = TRUE)))
  expect_true(any(grepl("3 of the 5 splits reach the headline split's change", md,
                        fixed = TRUE)))
})

test_that("a split's calibration ranking carries over by pooled counts at native density", {
  cf <- rbind(SYN_CONFIGS[1:3, ],
              transform(SYN_CONFIGS[2, ], config = "z5_s0.5_c0.7_e0", config_id = 12L,
                        min_share = 0.5, cover_min = 0.7, TP = 11, n_det = 22),
              transform(SYN_CONFIGS[2, ], config = "z0_s0_c0.7_e1", config_id = 50L, zmin = 0,
                        cover_min = 0.7, surface_exempt = TRUE, TP = 11, n_det = 33),
              SYN_CONFIGS[4, ])
  cells <- syn_cells(configs = cf)
  # counts that differ by plot and by configuration, so the two halves of a split
  # rank the configurations differently
  i <- as.integer(sub(".*_", "", cells$plot)) + 3L * (cells$site == "WREF")
  bump <- (i * ifelse(is.na(cells$config_id), 0L, cells$config_id)) %% 5
  cells$TP <- cells$TP + bump; cells$tp_core <- cells$tp_core + bump
  # rung 1, where config 3 is the best, must not count
  b1 <- cells$rung == "1" & cells$config_id %in% 3L
  cells[b1, c("TP", "tp_core", "n_det")] <- list(19, 18, 20)
  sp <- cv_split(cells, 1L, 0.5)
  cf1 <- function(ids) {
    P <- mcg_pool(cells[cells$rung == "native" & !is.na(cells$config_id) &
                          cv_ids(cells) %in% ids, ], "config_id")
    stats::setNames(P$cF1, P$config_id)
  }
  k <- cf1(sp$calib); v <- cf1(sp$valid)
  ids <- c("2", "3", "12", "50")
  dk <- k[ids] - k[["1"]]; dv <- v[ids] - v[["1"]]
  expect_false(isTRUE(all.equal(unname(dk), unname(dv))))
  expect_true(any(dv > 0) && any(dv < 0))
  rk <- rank(-v, ties.method = "min")
  ranks <- integer()
  for (id in c(1L, 2L, 3L, 12L, 50L)) {
    r <- cv_split_carry(cells, sp, id)
    expect_identical(names(r), c("n_configs", "pearson", "n_positive_valid", "rank_valid"))
    expect_identical(nrow(r), 1L)
    expect_identical(r$n_configs, 4L)
    expect_equal(r$pearson, stats::cor(dk, dv))
    expect_identical(r$n_positive_valid, sum(dv > 0))
    expect_identical(r$rank_valid, as.integer(rk[[as.character(id)]]))
    ranks <- c(ranks, r$rank_valid)
  }
  expect_setequal(ranks, 1:5)
  # a selection that is stock ranks below every configuration that gains
  r <- cv_split_carry(cells, sp, 1L)
  expect_identical(r$rank_valid, 1L + r$n_positive_valid)
  # one configuration: no correlation
  one <- cells[cells$config_id %in% c(1L, 12L), ]
  r <- cv_split_carry(one, sp, 12L)
  expect_identical(r$n_configs, 1L)
  expect_true(is.na(r$pearson))
  expect_identical(r$n_positive_valid, as.integer(dv[["12"]] > 0))
  expect_identical(r$rank_valid, if (dv[["12"]] > 0) 1L else 2L)
  expect_error(cv_split_carry(cells[!cells$config_id %in% 1L, ], sp, 2L),
               "stock (config_id 1) has no native rows", fixed = TRUE)
})

test_that("the carry-over paragraph gives the medians, ranges and the headline seed's place", {
  sg <- data.frame(seed = 1:5, config = "a", n_configs = 86L,
                   pearson = c(0.81, 0.5, 0.9, 0.3, 0.85),
                   n_positive_valid = c(82L, 40L, 86L, 79L, 60L),
                   rank_valid = c(5L, 10L, 2L, 68L, 12L), stringsAsFactors = FALSE)
  md <- cv_md_carry(sg, 1L)
  expect_length(md, 1L)
  expect_match(md, paste("Across the 86 non-stock grid configurations the calibration and",
                         "validation changes in cF1 correlate at a median of 0.81 over the 5",
                         "splits (10th to 90th percentile 0.38 to 0.88, range 0.30 to 0.90;",
                         "seed 1: 0.81, exceeded in 2 splits)."), fixed = TRUE)
  expect_match(md, paste("A split's own selection ranks at a median of 10 of 87 on its validation",
                         "plots, stock included (range 2 to 68), and a median of 79 of the 86",
                         "configurations score above stock there (range 40 to 86)."), fixed = TRUE)
  expect_match(md, "Every split is in `seed_grid.csv`.", fixed = TRUE)
  # a headline seed that is not among the seeds
  expect_match(cv_md_carry(sg, 99L), "seed 99: NA, exceeded in NA splits", fixed = TRUE)
  # an undefined correlation is left out; medians of an even count
  sg$pearson[2] <- NA
  md <- cv_md_carry(sg[-5, ], 1L)
  expect_match(md, "median of 0.81 over the 4 splits", fixed = TRUE)
  expect_match(md, "range 0.30 to 0.90; seed 1: 0.81, exceeded in 1 splits", fixed = TRUE)
  expect_match(md, "ranks at a median of 7.5 of 87", fixed = TRUE)
  expect_match(md, "a median of 80.5 of the 86 configurations", fixed = TRUE)
  expect_identical(cv_md_carry(NULL, 1L), "(no rows)")
  expect_identical(cv_md_carry(sg[0, ], 1L), "(no rows)")
})

test_that("calibration needs the native rung", {
  cells <- syn_cells(rungs = "1")
  expect_error(cv_analyze(cells, syn_settings(RUNGS = "1")), "native")
})

## ---- the record of the scored cells -----------------------------------------------------------
# A study directory the analyze stage reads: a sealed root (its clip manifest
# only), the candidates directory stamped with it, the cell index, the skipped
# cells, the scored cells (syn_cells) and, unless record = FALSE, the record of
# what they were scored with.
syn_study <- function(K = 200L, tol = 4, population = "adopted", grid_sha256 = NULL,
                      record = TRUE, skipped = NULL) {
  d <- tempfile("mcg_study"); dir.create(d)
  root <- file.path(d, "root"); dir.create(root)
  writeLines(c("file,sha256", "a.laz,0"), file.path(root, "clip_manifest.csv"))
  out <- file.path(d, "out")
  frozen_stamp(file.path(out, "candidates"), root)
  cells <- syn_cells()
  st <- cells[cells$config == "stock", ]
  idx <- data.frame(site = st$site, plot = st$plot, plotType = st$plotType, rung = st$rung,
                    a = CV_A_VWF, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                    cover_height = MCG_COVER_HEIGHT, top_prob = MCG_TOP_PROB,
                    crown_res = MCG_CROWN_RES, crown_ws = MCG_CROWN_WS, cover = st$cover,
                    top_height = st$top_height, crown_spacing = st$crown_spacing,
                    n_crowns = 20L, crown_area = 20 * st$crown_spacing^2, parity = TRUE,
                    population = "adopted",
                    file = cv_cell_file(st$site, st$plot, st$rung), stringsAsFactors = FALSE)
  write.csv(idx, file.path(out, "candidates.csv"), row.names = FALSE)
  write.csv(cells, file.path(out, "cells.csv"), row.names = FALSE)
  write.csv(if (is.null(skipped)) cv_skipped_cells(list()) else skipped,
            file.path(out, "candidates_skipped.csv"), row.names = FALSE)
  args <- c("STAGE=analyze", paste0("OUT=", out), paste0("FROZEN_ROOT=", root),
            "SITES=SJER,WREF", "RUNGS=native,1", "SEEDS=1", "N_BOOT=20")
  if (record) {
    S0 <- cv_settings(c(args, paste0("K=", K), paste0("TOL=", tol), paste0("POP=", population)),
                      d = d)
    rec <- cv_cells_config(S0, c("SJER", "WREF"), c("native", "1"), chm_vwf = TRUE)
    if (!is.null(grid_sha256)) rec$grid_sha256 <- grid_sha256
    cv_write_cells_config(rec, out)
  }
  list(d = d, out = out, root = root, args = args)
}
analyze_with <- function(study, ...) {
  S <- cv_settings(c(study$args, ...), d = study$d)
  out <- utils::capture.output(res <- cv_stage_analyze(S))
  list(res = res, out = out)
}

test_that("the score stage's record holds what the cells were scored with", {
  st <- syn_study(K = 50L, tol = 3)
  rec <- jsonlite::read_json(file.path(st$out, CV_CELLS_CONFIG), simplifyVector = TRUE)
  expect_identical(rec$K, 50L)
  expect_equal(rec$tol, 3)
  expect_identical(rec$population, "adopted")
  expect_identical(rec$clip_manifest_sha256, frozen_root_id(st$root))
  expect_identical(rec$grid_sha256, cv_grid_digest())
  expect_identical(rec$sites, c("SJER", "WREF"))
  expect_identical(rec$rungs, c("native", "1"))
  expect_true(rec$chm_vwf)
  # a single site stays a list of sites
  S <- cv_settings(st$args, d = st$d)
  one <- cv_cells_config(S, "SJER", "native", FALSE)
  cv_write_cells_config(one, st$d)
  back <- jsonlite::read_json(file.path(st$d, CV_CELLS_CONFIG))
  expect_true(is.list(back$sites) && is.list(back$rungs))
  # the digest follows every value of the grid, spacing_min included (the labels
  # are left as they were, so only the value changes)
  g <- mcg_grid(); g$cover_min[10] <- 0.65
  expect_false(identical(cv_grid_digest(g), cv_grid_digest()))
  for (i in c(20L, 360L)) {
    g <- mcg_grid(); g$spacing_min[i] <- g$spacing_min[i] + 1
    expect_false(identical(cv_grid_digest(g), cv_grid_digest()))
  }
  expect_identical(cv_grid_digest(mcg_grid()), cv_grid_digest())
})

test_that("the analyze stage takes K and TOL from the record of the scored cells", {
  st <- syn_study(K = 50L, tol = 3)
  a <- analyze_with(st)
  expect_true(any(grepl("cells scored with K = 50, TOL = 3", a$out, fixed = TRUE)))
  dc <- jsonlite::read_json(file.path(st$out, "declared_config.json"), simplifyVector = TRUE)
  expect_identical(dc$K, 50L)
  expect_equal(dc$tol, 3)
  md <- readLines(file.path(st$out, "tables.md"))
  expect_true(any(grepl("null K = 50 shifts, match radius 3 m", md, fixed = TRUE)))
  # an explicit value equal to the record is accepted
  b <- analyze_with(st, "K=50", "TOL=3")
  expect_identical(b$res$selected$label, a$res$selected$label)
})

test_that("the analyze stage writes the grid and region contrasts, and drops a stale region file", {
  st <- syn_study()
  a <- analyze_with(st)
  g <- read.csv(file.path(st$out, "grid_contrasts.csv"), stringsAsFactors = FALSE)
  expect_identical(nrow(g), 4L)
  expect_true(all(g$analysis == "grid"))
  rg <- read.csv(file.path(st$out, "region_differences.csv"), stringsAsFactors = FALSE,
                 colClasses = c(rung = "character"))
  expect_identical(rg$rung, c("native", "1"))
  v <- read.csv(file.path(st$out, "validation.csv"), stringsAsFactors = FALSE)
  expect_false(any(v$analysis %in% c("grid", "region_difference")))
  expect_true(any(grepl("grid_contrasts.csv, region_differences.csv", a$out, fixed = TRUE)))
  # one row per seed (SEEDS=1) of how the calibration ranking carries over
  sg <- read.csv(file.path(st$out, "seed_grid.csv"), stringsAsFactors = FALSE)
  expect_identical(nrow(sg), 1L)
  expect_identical(sg$config, a$res$selected$label)
  expect_true(any(grepl("seed_grid.csv", a$out[startsWith(a$out, "wrote ")], fixed = TRUE)))
  # one region only: no region rows, and the earlier file is removed
  st$args <- sub("^SITES=.*$", "SITES=WREF", st$args)
  b <- analyze_with(st)
  expect_null(b$res$regions)
  expect_false(file.exists(file.path(st$out, "region_differences.csv")))
  expect_true(file.exists(file.path(st$out, "grid_contrasts.csv")))
})

test_that("an explicit K= or TOL= that differs from the record stops the analysis", {
  st <- syn_study()
  expect_error(analyze_with(st, "K=50"), "scored with K = 200, not K=50")
  expect_error(analyze_with(st, "K=50", "TOL=3"), "re-run STAGE=score with K=50")
  expect_error(analyze_with(st, "TOL=3"), "scored with TOL = 4, not TOL=3")
  expect_false(file.exists(file.path(st$out, "declared_config.json")))
  a <- analyze_with(st)
  expect_true(any(grepl("cells scored with K = 200, TOL = 4", a$out, fixed = TRUE)))
  dc <- jsonlite::read_json(file.path(st$out, "declared_config.json"), simplifyVector = TRUE)
  expect_identical(c(dc$K, dc$tol), c(200L, 4L))
})

test_that("the analysis stops without a record, or for another grid, population or root", {
  expect_error(analyze_with(syn_study(record = FALSE)), "no record of how the cells were scored")
  expect_error(analyze_with(syn_study(record = FALSE)), "re-run STAGE=score")
  expect_error(analyze_with(syn_study(grid_sha256 = "0123")), "another calibration grid")
  expect_error(analyze_with(syn_study(population = "relaxed")),
               "scored for population relaxed, not adopted")
  st <- syn_study()
  writeLines(c("file,sha256", "b.laz,1"), file.path(st$root, "clip_manifest.csv"))
  expect_error(analyze_with(st), "scored on the frozen root")
  st <- syn_study()
  unlink(file.path(st$out, "candidates_skipped.csv"))
  expect_error(analyze_with(st), "re-run STAGE=candidates")
})

test_that("candidates that do not record this library's constants, or differ, stop the stages", {
  st <- syn_study()
  S <- cv_settings(st$args, d = st$d)
  f <- file.path(st$out, "candidates.csv")
  idx <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  expect_identical(nrow(cv_read_index(S)), nrow(idx))
  const <- c("a", "radius", "half_dz", "cover_height")
  write.csv(idx[setdiff(names(idx), const)], f, row.names = FALSE)
  expect_error(cv_read_index(S), paste("the candidates were not made with this library's a = 0.1",
                                       "(or do not record it); re-run STAGE=candidates"),
               fixed = TRUE)
  expect_error(analyze_with(st), "re-run STAGE=candidates")
  other <- idx; other$radius[3] <- 1.5
  write.csv(other, f, row.names = FALSE)
  expect_error(cv_read_index(S), "not made with this library's radius = 1 ", fixed = TRUE)
  expect_error(analyze_with(st), "radius = 1 ", fixed = TRUE)
  other <- idx; other$cover_height[1] <- NA
  write.csv(other, f, row.names = FALSE)
  expect_error(cv_read_index(S), "cover_height = 2 ", fixed = TRUE)
  # the top height's quantile and the crowns' cell size and window are constants
  # like the others: each one missing, or of another value, stops
  for (k in c("top_prob", "crown_res", "crown_ws")) {
    v <- c(top_prob = MCG_TOP_PROB, crown_res = MCG_CROWN_RES, crown_ws = MCG_CROWN_WS)[[k]]
    write.csv(idx[setdiff(names(idx), k)], f, row.names = FALSE)
    expect_error(cv_read_index(S), sprintf(paste("not made with this library's %s = %g (or do",
                                                 "not record it); re-run STAGE=candidates"), k, v),
                 fixed = TRUE)
    other <- idx; other[[k]][4] <- v * 1.5
    write.csv(other, f, row.names = FALSE)
    expect_error(cv_read_index(S), sprintf("not made with this library's %s = %g ", k, v),
                 fixed = TRUE)
    other <- idx; other[[k]][2] <- NA
    write.csv(other, f, row.names = FALSE)
    expect_error(cv_read_index(S), sprintf("%s = %g ", k, v), fixed = TRUE)
  }
  write.csv(idx[setdiff(names(idx), "crown_ws")], f, row.names = FALSE)
  expect_error(analyze_with(st), "crown_ws = 5 (or do not record it)", fixed = TRUE)
  # an index without the clips' top heights or crown spacings cannot serve the
  # score stage
  write.csv(idx[setdiff(names(idx), "top_height")], f, row.names = FALSE)
  expect_error(cv_read_index(S), paste("does not record the clips' top height (column",
                                       "top_height); re-run STAGE=candidates"), fixed = TRUE)
  expect_error(analyze_with(st), "column top_height", fixed = TRUE)
  write.csv(idx[setdiff(names(idx), "crown_spacing")], f, row.names = FALSE)
  expect_error(cv_read_index(S), paste("does not record the clips' crown spacing (column",
                                       "crown_spacing); re-run STAGE=candidates"), fixed = TRUE)
  expect_error(analyze_with(st), "column crown_spacing", fixed = TRUE)
  # the number of crowns and their area are recorded, not required
  write.csv(idx[setdiff(names(idx), c("n_crowns", "crown_area"))], f, row.names = FALSE)
  expect_identical(nrow(cv_read_index(S)), nrow(idx))
  # an unknown top height or crown spacing (NA) is recorded, not refused, and an
  # infinite crown spacing (interior surface without a crown) reads back as Inf
  other <- idx; other$top_height[2] <- NA; other$crown_spacing[3] <- NA
  other$crown_spacing[5] <- Inf
  write.csv(other, f, row.names = FALSE)
  back <- cv_read_index(S)
  expect_true(is.na(back$top_height[2]) && is.na(back$crown_spacing[3]))
  expect_identical(back$crown_spacing[5], Inf)
  write.csv(idx, f, row.names = FALSE)
  expect_identical(nrow(cv_read_index(S)), nrow(idx))
})

## ---- skipped candidate cells ------------------------------------------------------------------
# A small normalized stand of conical crowns (ground and crown first returns,
# later returns inside the crowns) and a flat clip, on which lidRplugins::multichm
# finds no candidate and fails.
syn_las <- function(flat = FALSE) {
  set.seed(5)
  g <- data.frame(X = runif(1500, 0, 36), Y = runif(1500, 0, 32), Z = abs(rnorm(1500, 0, 0.05)),
                  ReturnNumber = 1L)
  if (!flat) {
    tr <- data.frame(x = c(10, 20, 27, 12), y = c(10, 12, 22, 24), h = c(22, 18, 20, 15),
                     r = c(3.5, 3, 3.2, 2.8))
    g <- rbind(g, do.call(rbind, lapply(seq_len(nrow(tr)), function(i) {
      t <- tr[i, ]
      d <- t$r * sqrt(runif(700)); a <- runif(700, 0, 2 * pi)
      s <- data.frame(X = t$x + d * cos(a), Y = t$y + d * sin(a),
                      Z = t$h * (1 - 0.6 * d / t$r) + rnorm(700, 0, 0.1), ReturnNumber = 1L)
      d <- 0.8 * t$r * sqrt(runif(200)); a <- runif(200, 0, 2 * pi)
      rbind(s, data.frame(X = t$x + d * cos(a), Y = t$y + d * sin(a),
                          Z = runif(200, 0.3 * t$h, 0.9 * t$h), ReturnNumber = 2L))
    })))
  }
  g$ReturnNumber <- as.integer(g$ReturnNumber)
  g$NumberOfReturns <- g$ReturnNumber
  las <- suppressWarnings(LAS(g))
  sf::st_crs(las) <- 32611L
  las
}

test_that("cells where the package fails are recorded as skipped and counted", {
  skip_if_not_installed("lidRplugins")
  d <- tempfile("mcg_cand"); dir.create(d)
  cdir <- file.path(d, "candidates"); dir.create(cdir)
  lidR::writeLAS(syn_las(), file.path(d, "stand.las"))
  lidR::writeLAS(syn_las(flat = TRUE), file.path(d, "flat.las"))
  clips <- list(native = "stand.las", `8` = "flat.las", `4` = "stand.las")
  # the candidates job on clips served from `clips` instead of a sealed root
  job <- cv_candidates_job
  env <- new.env(parent = environment(job))
  env$frozen_root_rungs <- function(root) c(8, 4, 2)
  env$frozen_clip <- function(ctg, site, plot, rung, cx, cy, core_half, out_root) {
    f <- clips[[if (is.na(rung)) "native" else as.character(rung)]]
    if (is.null(f)) NULL else list(normalized = file.path(d, f), pdens = 20, frdens = 5)
  }
  environment(job) <- env
  j <- list(site = "SYN", plot = "SYN_001", plotType = "tower", cx = 18, cy = 16, half = 20,
            population = "adopted")
  r <- job(j, root = d, rungs = CV_RUNGS, cdir = cdir)
  expect_identical(r$rung, c("native", "4"))
  expect_true(all(r$parity))
  # every index row records the constants its candidates and crowns were made
  # with, and the clip's cover, top height and crowns (after the constants:
  # cover, top height, then crown spacing, the number of crowns and their area)
  const <- c("a", "radius", "half_dz", "cover_height", "top_prob", "crown_res", "crown_ws")
  expect_identical(unlist(unique(r[const])),
                   c(a = CV_A_VWF, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                     cover_height = MCG_COVER_HEIGHT, top_prob = MCG_TOP_PROB,
                     crown_res = MCG_CROWN_RES, crown_ws = MCG_CROWN_WS))
  expect_identical(names(r)[match("a", names(r)) + 0:12],
                   c(const, "cover", "top_height", "crown_spacing", "n_crowns", "crown_area",
                     "n_cand"))
  stand <- lidR::readLAS(file.path(d, "stand.las"))
  expect_equal(r$top_height, rep(mcg_top_height(stand), 2), tolerance = 1e-12)
  expect_gt(r$top_height[1], 2)
  cr <- mcg_crowns(stand)
  expect_identical(r$n_crowns, rep(cr$n, 2))
  expect_identical(r$crown_area, rep(cr$area, 2))
  expect_identical(r$crown_spacing, rep(cr$spacing, 2))
  expect_true(cr$n > 0L && is.finite(cr$spacing))
  expect_equal(r$crown_spacing, sqrt(r$crown_area / r$n_crowns))
  prep <- readRDS(file.path(cdir, "SYN__SYN_001__native.rds"))$prep
  expect_identical(c(prep$top_height, prep$crown_spacing, prep$n_crowns, prep$crown_area),
                   c(r$top_height[1], r$crown_spacing[1], r$n_crowns[1], r$crown_area[1]))
  sk <- attr(r, "skipped")
  expect_identical(names(sk), CV_SKIPPED_COLS)
  expect_identical(c(sk$site, sk$plot, sk$rung), c("SYN", "SYN_001", "8"))
  expect_identical(sk$reason, "lidRplugins::multichm failed")
  expect_true(nzchar(sk$error))
  expect_true(file.exists(file.path(cdir, "SYN__SYN_001__native.rds")))
  expect_false(file.exists(file.path(cdir, "SYN__SYN_001__8.rds")))
  # a plot whose only clip fails returns no index rows but still reports it
  clips <- list(native = "flat.las")
  j2 <- utils::modifyList(j, list(plot = "SYN_002"))
  only <- job(j2, root = d, rungs = CV_RUNGS, cdir = cdir)
  expect_true(is.data.frame(only))
  expect_identical(nrow(only), 0L)
  expect_identical(attr(only, "skipped")$rung, "native")
  expect_silent(stop_failed_plots(c("SYN/SYN_001", "SYN/SYN_002"), list(r, only)))
  # the stage's files and its summary
  out <- utils::capture.output(idx <- cv_write_candidates(list(r, NULL, only), d))
  expect_identical(nrow(idx), 2L)
  expect_null(attr(idx, "skipped"))
  expect_identical(read.csv(file.path(d, "candidates.csv"))$rung, c("native", "4"))
  rec <- read.csv(file.path(d, "candidates_skipped.csv"), stringsAsFactors = FALSE,
                  colClasses = "character")
  expect_identical(paste(rec$plot, rec$rung), c("SYN_001 8", "SYN_002 native"))
  expect_true(any(grepl("[candidates] 2 candidate cells skipped", out, fixed = TRUE)))
  expect_true(any(grepl("SYN/SYN_002 native: lidRplugins::multichm failed", out, fixed = TRUE)))
  # none skipped: the record is a header only
  attr(r, "skipped") <- NULL
  out <- utils::capture.output(cv_write_candidates(list(r), d))
  expect_identical(readLines(file.path(d, "candidates_skipped.csv")),
                   '"site","plot","rung","reason","error"')
  expect_true(any(grepl("[candidates] 0 candidate cells skipped", out, fixed = TRUE)))
  expect_error(utils::capture.output(cv_write_candidates(list(only), d)), "no candidate cells")
})

test_that("the analyze stage reports the skipped cells of its sites and rungs", {
  sk <- data.frame(site = c("SJER", "SJER", "TEAK"), plot = c("SJER_009", "SJER_010", "TEAK_001"),
                   rung = c("1", "8", "1"), reason = "lidRplugins::multichm failed",
                   error = "some columns are not in the data.table: [Z]",
                   stringsAsFactors = FALSE)
  a <- analyze_with(syn_study(skipped = sk))
  expect_true(any(grepl("[analyze] 1 candidate cells skipped", a$out, fixed = TRUE)))
  expect_true(any(grepl("SJER/SJER_009 1: lidRplugins::multichm failed", a$out, fixed = TRUE)))
  a <- analyze_with(syn_study())
  expect_true(any(grepl("[analyze] 0 candidate cells skipped", a$out, fixed = TRUE)))
})

## ---- censused subplots ----------------------------------------------------------------------
# Censused scores as score_census_support.R writes them (the columns the study
# reads), one row per plot ("SITE_nnn"); rect_n_det is the nominal-box
# detection count of the scored detections.
syn_census <- function(det, plots, n_ref, n_det, TP, tp_core, rung = "native",
                       rect_n_det = NA_real_)
  data.frame(site = sub("_.*", "", plots), plot = plots, rung = rung, detector = det,
             n_ref = n_ref, n_det = n_det, TP = TP, tp_core = tp_core, rect_n_det = rect_n_det,
             support_id = paste0("bundle_", plots),
             support_policy = "measured_subplots_uncertainty_interior_v1",
             reference_population = "live_mapped_boles_dbh_ge_10cm", stringsAsFactors = FALSE)

# A site's configuration stamp, as the arm driver writes it: the configuration,
# the window coefficient and the feature constants (`const`), then the label
# (none when `label` is NULL).
SYN_STAMP_CONST <- list(a = CV_A_VWF, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                        cover_height = MCG_COVER_HEIGHT, crown_res = MCG_CROWN_RES,
                        crown_ws = MCG_CROWN_WS)
syn_stamp <- function(d, site, cfg, const = SYN_STAMP_CONST, label = mcg_config_label(cfg)) {
  dd <- file.path(d, "neon", site, "multichm_gated_detections")
  dir.create(dd, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(c(cfg, const, if (!is.null(label)) list(label = label)),
                       file.path(dd, CV_ARM_CONFIG_STAMP), auto_unbox = TRUE, pretty = TRUE,
                       digits = NA)
}

test_that("the censused contrast pools summed counts on equal support, by split and scope", {
  d <- tempfile("mcg_census"); dir.create(d)
  sj <- sprintf("SJER_%03d", 1:3); wr <- sprintf("WREF_%03d", 1:3)
  gated <- rbind(
    syn_census("multichm_gated", c(sj, wr), c(10, 12, 8, 20, 15, 9), c(8, 9, 0, 18, 12, 7),
               c(6, 7, 0, 12, 10, 6), c(6, 8, NA, 13, 9, 5)),
    syn_census("multichm_gated", sj, 10, 1, 1, 1, rung = "1"))      # another rung
  base <- rbind(
    syn_census("multichm", c(sj, wr[1:2]), c(10, 12, 8, 20, 15), c(12, 11, 9, 25, 16),
               c(7, 7, 5, 13, 11), c(6, 7, 5, 12, 9)),
    syn_census("chm_vwf", c(sj, wr), 10, 5, 5, 5))                   # another detector
  write.csv(gated, file.path(d, "gated.csv"), row.names = FALSE)
  write.csv(base, file.path(d, "base.csv"), row.names = FALSE)
  sites <- c("SJER", "WREF")
  valid <- c("SJER::SJER_002", "WREF::WREF_001", "WREF::WREF_003")
  cs <- cv_census(file.path(d, "gated.csv"), file.path(d, "base.csv"), valid, cv_scopes(sites),
                  sites, n_boot = 50)
  # WREF_003 is scored by the arm only: equal support drops it
  both <- c(paste0("SJER::", sj), paste0("WREF::", wr[1:2]))
  expect_setequal(cv_ids(cs$cells), both)
  expect_setequal(cs$cells$detector, c("multichm_gated", "multichm"))
  expect_true(all(cs$cells$rung == "native"))
  k <- cs$contrasts[cs$contrasts$metric == "F1", ]
  expect_identical(k$split, rep(c("all", "valid"), each = 5))
  expect_identical(k$scope, rep(c("SJER+WREF", "California", "Washington", "SJER", "WREF"), 2))
  expect_identical(k$n_plots, c(5L, 3L, 2L, 3L, 2L, 2L, 1L, 1L, 1L, 1L))
  # pooled rates are the rates of the summed counts (tp_core 0 where nothing is detected)
  pooled <- function(det, ids) {
    x <- rbind(gated, base)
    x <- x[x$detector == det & x$rung == "native" & cv_ids(x) %in% ids, ]
    tp_core <- ifelse(x$n_det == 0, 0, x$tp_core)
    r <- sum(x$TP) / sum(x$n_ref); p <- sum(tp_core) / sum(x$n_det)
    c(recall = r, precision = p, F1 = 2 * r * p / (r + p))
  }
  m <- c("recall", "precision", "F1")
  for (spl in c("all", "valid")) for (sc in c("SJER+WREF", "Washington", "SJER")) {
    ids <- both[sub("::.*", "", both) %in% switch(sc, Washington = "WREF", SJER = "SJER", sites)]
    if (spl == "valid") ids <- intersect(ids, valid)
    for (det in c("multichm_gated", "multichm")) {
      e <- cs$scores[cs$scores$split == spl & cs$scores$scope == sc &
                       cs$scores$detector == det, ]
      expect_equal(e$estimate[match(m, e$metric)], unname(pooled(det, ids)))
      expect_true(all(e$n_plots == length(ids)))
    }
    k <- cs$contrasts[cs$contrasts$split == spl & cs$contrasts$scope == sc, ]
    expect_equal(k$estimate[match(m, k$metric)],
                 unname(pooled("multichm_gated", ids) - pooled("multichm", ids)))
    expect_true(all(k$from == "multichm" & k$to == "multichm_gated"))
    expect_true(all(k$lower <= k$estimate + 1e-12 & k$estimate <= k$upper + 1e-12))
  }
  e <- cs$scores[cs$scores$split == "valid" & cs$scores$scope == "SJER+WREF", ]
  expect_true(all(e$n_ref == 12 + 20))                  # SJER_002 and WREF_001 only
  # a file without the detector's native rows stops
  write.csv(base[base$detector != "multichm", ], file.path(d, "none.csv"), row.names = FALSE)
  expect_error(cv_census(file.path(d, "gated.csv"), file.path(d, "none.csv"), valid,
                         cv_scopes(sites), sites, n_boot = 20),
               "no censused multichm rows at native density")
  expect_error(cv_census(file.path(d, "base.csv"), file.path(d, "base.csv"), valid,
                         cv_scopes(sites), sites, n_boot = 20),
               "no censused multichm_gated rows at native density")
  # a file without the support identity (a nominal-box result file) is refused in
  # either position, so the equal-support guard cannot be bypassed by dropping it
  rect <- base[setdiff(names(base), c("support_id", "support_policy", "reference_population"))]
  write.csv(rect, file.path(d, "rect.csv"), row.names = FALSE)
  expect_error(cv_census(file.path(d, "gated.csv"), file.path(d, "rect.csv"), valid,
                         cv_scopes(sites), sites, n_boot = 20),
               "is not a censused score file")
  expect_error(cv_census(file.path(d, "rect.csv"), file.path(d, "base.csv"), valid,
                         cv_scopes(sites), sites, n_boot = 20),
               "rect.csv has no support_id, support_policy, reference_population, so it is not a",
               fixed = TRUE)
  # the tables print the section only when given the censused results
  S <- syn_settings(N_BOOT = 20L)
  res <- cv_analyze(syn_cells(), S, boot_seed = 11L)
  head <- paste("## Censused subplots (native density; the declared arm's persisted detections",
                "against the paper's multichm)")
  expect_false(head %in% cv_tables_md(res, S, "abc", "adopted"))
  expect_false(any(grepl("^\\| (all admitted|valid) \\|", cv_tables_md(res, S, "abc", "adopted"))))
  md <- cv_tables_md(res, S, "abc", "adopted", census = cs)
  expect_true(head %in% md)
  rows <- grep("^\\| (all admitted|valid) ", md, value = TRUE)
  expect_length(rows, 10L)
  g <- pooled("multichm_gated", both); b <- pooled("multichm", both)
  lead <- "| all admitted (in-sample for the selection) | SJER+WREF | 5 | 65 | 47 / 73 | "
  expect_true(startsWith(rows[1], paste0(lead, sprintf(
    "%.3f / %.3f | %.3f / %.3f | %.3f / %.3f | ", g[["recall"]], b[["recall"]],
    g[["precision"]], b[["precision"]], g[["F1"]], b[["F1"]]))))
  f1 <- cs$contrasts[cs$contrasts$split == "all" & cs$contrasts$scope == "SJER+WREF" &
                       cs$contrasts$metric == "F1", ]
  expect_match(rows[1], sprintf("| %.3f [%.3f, %.3f] |", f1$estimate, f1$lower, f1$upper),
               fixed = TRUE)
  expect_true(all(startsWith(rows[6:10], "| valid | ")))
})

test_that("the censused contrast can take the arm itself, relabelled, as its base", {
  d <- tempfile("mcg_census_ref"); dir.create(d)
  sj <- sprintf("SJER_%03d", 1:3); wr <- sprintf("WREF_%03d", 1:3)
  gated <- syn_census("multichm_gated", c(sj, wr), c(10, 12, 8, 20, 15, 9),
                      c(8, 9, 0, 18, 12, 7), c(6, 7, 0, 12, 10, 6), c(6, 8, NA, 13, 9, 5))
  # the reference run: the arm under another configuration (WREF_003 unscored),
  # and a multichm row that the reference contrast must not read
  ref <- rbind(syn_census("multichm_gated", c(sj, wr[1:2]), c(10, 12, 8, 20, 15),
                          c(10, 12, 3, 22, 14), c(7, 8, 2, 13, 10), c(7, 9, 2, 14, 10)),
               syn_census("multichm", c(sj, wr), 10, 1, 1, 1))
  base <- syn_census("multichm", c(sj, wr), c(10, 12, 8, 20, 15, 9), c(12, 11, 9, 25, 16, 8),
                     c(7, 7, 5, 13, 11, 6), c(6, 7, 5, 12, 9, 5))
  files <- file.path(d, c("gated.csv", "ref.csv", "base.csv"))
  write.csv(gated, files[1], row.names = FALSE)
  write.csv(ref, files[2], row.names = FALSE)
  write.csv(base, files[3], row.names = FALSE)
  sites <- c("SJER", "WREF")
  valid <- c("SJER::SJER_002", "WREF::WREF_001", "WREF::WREF_003")
  run <- function(b, ...) cv_census(files[1], b, valid, cv_scopes(sites), sites, n_boot = 40, ...)
  cs <- run(files[2], base_det = "multichm_gated", base_name = "reference")
  # relabelled before binding, and equal support drops the plot the reference lacks
  both <- c(paste0("SJER::", sj), paste0("WREF::", wr[1:2]))
  expect_setequal(cv_ids(cs$cells), both)
  expect_setequal(cs$cells$detector, c("multichm_gated", "reference"))
  expect_setequal(cs$scores$detector, c("multichm_gated", "reference"))
  pooled <- function(x, ids) {
    x <- x[x$rung == "native" & cv_ids(x) %in% ids, ]
    tp_core <- ifelse(x$n_det == 0, 0, x$tp_core)
    r <- sum(x$TP) / sum(x$n_ref); p <- sum(tp_core) / sum(x$n_det)
    c(recall = r, precision = p, F1 = 2 * r * p / (r + p))
  }
  m <- c("recall", "precision", "F1")
  rx <- ref[ref$detector == "multichm_gated", ]
  for (spl in c("all", "valid")) {
    ids <- if (spl == "valid") intersect(both, valid) else both
    k <- cs$contrasts[cs$contrasts$split == spl & cs$contrasts$scope == "SJER+WREF", ]
    # gated minus the reference
    expect_true(all(k$from == "reference" & k$to == "multichm_gated"))
    expect_equal(k$estimate[match(m, k$metric)], unname(pooled(gated, ids) - pooled(rx, ids)))
    expect_true(all(k$n_plots == length(ids)))
  }
  # the default call is the paper's multichm under its own name, and any other
  # base name only renames it
  def <- run(files[3])
  expect_identical(def, run(files[3], base_det = "multichm", base_name = "multichm"))
  expect_setequal(def$cells$detector, c("multichm_gated", "multichm"))
  ren <- run(files[3], base_name = "paper")
  expect_identical(ren$contrasts[setdiff(names(ren$contrasts), "from")],
                   def$contrasts[setdiff(names(def$contrasts), "from")])
  expect_true(all(ren$contrasts$from == "paper"))
  expect_identical(ren$scores$estimate, def$scores$estimate)
  # the base cannot carry the arm's own name
  expect_error(run(files[2], base_det = "multichm_gated"), "another name than multichm_gated",
               fixed = TRUE)
  expect_error(run(files[3], base_name = "multichm_gated"), "another name than multichm_gated",
               fixed = TRUE)
  # a reference file without the arm's native rows stops
  expect_error(run(files[3], base_det = "multichm_gated", base_name = "reference"),
               "no censused multichm_gated rows at native density in", fixed = TRUE)
  # the tables: the header words and the detector read as B follow the arguments,
  # and the defaults keep the table of the paper's multichm
  md <- cv_md_census(cs, base = "reference", words = c("selected", "reference"))
  expect_identical(md[1], paste(
    "| Split | Scope | Plots | Stems | Detections selected / reference | Recall selected /",
    "reference | Precision selected / reference | F1 selected / reference | ΔF1 [95% interval]",
    "| ΔPrecision [95% interval] | ΔRecall [95% interval] |"))
  g <- pooled(gated, both); b <- pooled(rx, both)
  # 65 stems; 47 detections of the selection, 61 of the reference
  expect_true(startsWith(md[3], paste0(
    "| all admitted (in-sample for the selection) | SJER+WREF | 5 | 65 | 47 / 61 | ",
    sprintf("%.3f / %.3f | %.3f / %.3f | %.3f / %.3f | ", g[["recall"]], b[["recall"]],
            g[["precision"]], b[["precision"]], g[["F1"]], b[["F1"]]))))
  md0 <- cv_md_census(def)
  expect_identical(md0[1], paste(
    "| Split | Scope | Plots | Stems | Detections gated / stock | Recall gated / stock |",
    "Precision gated / stock | F1 gated / stock | ΔF1 [95% interval] | ΔPrecision [95%",
    "interval] | ΔRecall [95% interval] |"))
  expect_identical(md0, cv_md_census(def, base = "multichm", words = c("gated", "stock")))
})

test_that("the censused contrast needs each site's stamp to hold the selection", {
  d <- tempfile("mcg_stamp"); dir.create(d)
  cfg <- mcg_config(5, 0.75, 0.6, TRUE)
  for (s in c("SJER", "WREF")) syn_stamp(d, s, cfg)
  sel <- c(cfg, list(label = mcg_config_label(cfg)))
  expect_true(cv_census_config_check(d, c("SJER", "WREF"), sel))
  other <- c(mcg_config(5, 0.75, 0.7, TRUE), list(label = "z5_s0.75_c0.7_e1"))
  expect_error(cv_census_config_check(d, c("SJER", "WREF"), other),
               paste("the censused scores are of configuration z5_s0.75_c0.6_e1, not the",
                     "selection z5_s0.75_c0.7_e1; re-run the arm and score_census_support.R"),
               fixed = TRUE)
  syn_stamp(d, "WREF", mcg_config(5, 0.75, 0.6, FALSE))
  expect_error(cv_census_config_check(d, c("SJER", "WREF"), sel),
               "configuration z5_s0.75_c0.6_e0, not the selection z5_s0.75_c0.6_e1", fixed = TRUE)
  # the same configuration made with another window coefficient, or a stamp
  # that does not record the window coefficient and the feature constants
  syn_stamp(d, "WREF", cfg, const = utils::modifyList(SYN_STAMP_CONST, list(a = 0.3)))
  expect_error(cv_census_config_check(d, c("SJER", "WREF"), sel),
               "the censused detections of WREF were not made with this study's a = 0.1, radius = 1",
               fixed = TRUE)
  syn_stamp(d, "WREF", cfg[1:4], const = list())
  expect_error(cv_census_config_check(d, c("SJER", "WREF"), sel),
               "the censused detections of WREF were not made with", fixed = TRUE)
  unlink(file.path(d, "neon", "WREF", "multichm_gated_detections", CV_ARM_CONFIG_STAMP))
  expect_error(cv_census_config_check(d, c("SJER", "WREF"), sel), "no configuration stamp at")
  expect_true(cv_census_config_check(d, "SJER", sel))
})

test_that("the stamp must hold the selection's spacing_min and the crowns' constants", {
  d <- tempfile("mcg_stamp_spacing"); dir.create(d)
  sites <- c("SJER", "WREF")
  with_label <- function(cfg) c(cfg, list(label = mcg_config_label(cfg)))
  stamp_of <- function(s) file.path(d, "neon", s, "multichm_gated_detections",
                                    CV_ARM_CONFIG_STAMP)
  c8 <- mcg_config(5, 0.75, 0.6, TRUE, 8); c0 <- mcg_config(5, 0.75, 0.6, TRUE)
  # the stamp as the arm driver writes it: the five values, the constants, the label
  for (s in sites) syn_stamp(d, s, c8)
  expect_identical(names(jsonlite::read_json(stamp_of("WREF"))),
                   c("zmin", "min_share", "cover_min", "surface_exempt", "spacing_min", "a",
                     "radius", "half_dz", "cover_height", "crown_res", "crown_ws", "label"))
  expect_true(cv_census_config_check(d, sites, with_label(c8)))
  expect_true(cv_census_config_check(d, sites, with_label(MCG_DECLARED)))
  # another spacing_min, either way
  expect_error(cv_census_config_check(d, sites, with_label(c0)),
               "configuration z5_s0.75_c0.6_e1_d8, not the selection z5_s0.75_c0.6_e1;",
               fixed = TRUE)
  syn_stamp(d, "WREF", mcg_config(5, 0.75, 0.6, TRUE, 7.5))
  expect_error(cv_census_config_check(d, sites, with_label(c8)),
               "configuration z5_s0.75_c0.6_e1_d7.5, not the selection z5_s0.75_c0.6_e1_d8;",
               fixed = TRUE)
  # a stamp that records none of spacing_min, crown_res and crown_ws is read as
  # spacing_min 0 with the library's crown constants: it serves a selection
  # without a spacing condition only
  base <- SYN_STAMP_CONST[c("a", "radius", "half_dz", "cover_height")]
  for (s in sites) syn_stamp(d, s, c0[1:4], const = base)
  expect_false(any(c("spacing_min", "crown_res", "crown_ws") %in%
                     names(jsonlite::read_json(stamp_of("WREF")))))
  expect_true(cv_census_config_check(d, sites, with_label(c0)))
  expect_true(cv_census_config_check(d, sites, c0[1:4]))   # a selection without spacing_min
  for (v in c(8, 9))
    expect_error(cv_census_config_check(d, sites, with_label(mcg_config(5, 0.75, 0.6, TRUE, v))),
                 sprintf("configuration z5_s0.75_c0.6_e1, not the selection z5_s0.75_c0.6_e1_d%g;",
                         v), fixed = TRUE)
  expect_error(cv_census_config_check(d, sites, with_label(mcg_config(5, 0.75, 0.7, TRUE))),
               "not the selection z5_s0.75_c0.7_e1;", fixed = TRUE)
  # ... also with fields this library does not read, or without a label
  for (s in sites) syn_stamp(d, s, c0[1:4], const = c(base, list(top_prob = MCG_TOP_PROB)))
  expect_true(cv_census_config_check(d, sites, with_label(c0)))
  for (s in sites) syn_stamp(d, s, c0[1:4], const = base, label = NULL)
  expect_true(cv_census_config_check(d, sites, with_label(c0)))
  expect_error(cv_census_config_check(d, sites, with_label(c8)),
               "configuration (unlabelled), not the selection z5_s0.75_c0.6_e1_d8;", fixed = TRUE)
  # a stamp that records some but not all three is refused, whatever its values
  crown <- list(spacing_min = 0, crown_res = MCG_CROWN_RES, crown_ws = MCG_CROWN_WS)
  for (k in list("spacing_min", "crown_res", "crown_ws", c("spacing_min", "crown_res"),
                 c("spacing_min", "crown_ws"), c("crown_res", "crown_ws"))) {
    for (s in sites) syn_stamp(d, s, c0[1:4], const = c(base, crown[k]))
    expect_error(cv_census_config_check(d, sites, with_label(c0)),
                 sprintf(paste("the censused scores are of configuration z5_s0.75_c0.6_e1 (its",
                               "stamp records %s but not %s), not the selection",
                               "z5_s0.75_c0.6_e1;"), paste(k, collapse = " and "),
                         paste(setdiff(names(crown), k), collapse = " and ")), fixed = TRUE)
  }
  # the stamp's label must be this library's label of the selection's values,
  # even when the values agree, and the values must agree with the label
  for (s in sites) syn_stamp(d, s, c0, label = "z5_s0.75_c0.6_e1_x9")
  expect_error(cv_census_config_check(d, sites, with_label(c0)),
               paste("the censused scores are of configuration z5_s0.75_c0.6_e1_x9, not the",
                     "selection z5_s0.75_c0.6_e1; re-run the arm and score_census_support.R"),
               fixed = TRUE)
  for (s in sites) syn_stamp(d, s, c8, label = mcg_config_label(c0))
  for (cfg in list(c0, c8))
    expect_error(cv_census_config_check(d, sites, with_label(cfg)),
                 sprintf("configuration z5_s0.75_c0.6_e1, not the selection %s;",
                         mcg_config_label(cfg)), fixed = TRUE)
  # the crowns' cell size and window: another value of either
  for (k in c("crown_res", "crown_ws")) {
    syn_stamp(d, "SJER", c8)
    syn_stamp(d, "WREF", c8, const = utils::modifyList(SYN_STAMP_CONST,
                                                       stats::setNames(list(3), k)))
    expect_error(cv_census_config_check(d, sites, with_label(c8)),
                 paste("the censused detections of WREF were not made with this study's a = 0.1,",
                       "radius = 1, half_dz = 1, cover_height = 2, crown_res = 1, crown_ws = 5",
                       "(or their stamp does not record them)"), fixed = TRUE)
  }
  syn_stamp(d, "WREF", c8)
  expect_true(cv_census_config_check(d, sites, with_label(c8)))
})

test_that("a censused file must hold the nominal-box detection counts of the study's cells", {
  d <- tempfile("mcg_rect"); dir.create(d)
  f <- file.path(d, "census.csv")
  cells <- syn_cells(sites = "SJER", n = 3)     # z5_s0_c0_e0: 24 per cell, stock 30
  sj <- sprintf("SJER_%03d", 1:3)
  ok <- syn_census("multichm_gated", sj, 10, 8, 6, 6, rect_n_det = 24)
  write.csv(ok, f, row.names = FALSE)
  expect_true(cv_census_cells_check(f, "multichm_gated", cells, "z5_s0_c0_e0"))
  expect_error(cv_census_cells_check(f, "multichm_gated", cells, "stock"),
               paste("does not score the multichm_gated detections of configuration stock: the",
                     "nominal-box detection count differs from cells.csv in 3 of 3 cells (first",
                     "SJER_001)"), fixed = TRUE)
  # rows of another detector, another rung or another site are ignored
  other <- rbind(ok, syn_census("multichm", sj, 10, 8, 6, 6, rect_n_det = 99),
                 syn_census("multichm_gated", sj, 10, 8, 6, 6, rung = "1", rect_n_det = 99),
                 syn_census("multichm_gated", "WREF_001", 10, 8, 6, 6, rect_n_det = 99))
  write.csv(other, f, row.names = FALSE)
  expect_true(cv_census_cells_check(f, "multichm_gated", cells, "z5_s0_c0_e0"))
  # a plot of the file that the cells lack, or a missing count, is a difference
  write.csv(rbind(ok, syn_census("multichm_gated", "SJER_009", 10, 8, 6, 6, rect_n_det = 24)),
            f, row.names = FALSE)
  expect_error(cv_census_cells_check(f, "multichm_gated", cells, "z5_s0_c0_e0"),
               "differs from cells.csv in 1 of 4 cells (first SJER_009)", fixed = TRUE)
  na <- ok; na$rect_n_det[2] <- NA
  write.csv(na, f, row.names = FALSE)
  expect_error(cv_census_cells_check(f, "multichm_gated", cells, "z5_s0_c0_e0"),
               "in 1 of 3 cells (first SJER_002)", fixed = TRUE)
  # a file without the count stops; a file with no row of the detector passes
  # (cv_census() reports it)
  write.csv(ok[setdiff(names(ok), "rect_n_det")], f, row.names = FALSE)
  expect_error(cv_census_cells_check(f, "multichm_gated", cells, "z5_s0_c0_e0"),
               "has no rect_n_det", fixed = TRUE)
  write.csv(syn_census("multichm", sj, 10, 8, 6, 6), f, row.names = FALSE)
  expect_true(cv_census_cells_check(f, "multichm_gated", cells, "z5_s0_c0_e0"))
})

test_that("the analyze stage adds the censused contrast with both files, and drops it otherwise", {
  st <- syn_study()
  plots <- c(sprintf("SJER_%03d", 1:8), sprintf("WREF_%03d", 1:8))
  gated <- file.path(st$d, "gated.csv"); base <- file.path(st$d, "base.csv")
  # the nominal-box counts of the synthetic cells: the selection 24, stock 30
  write_gated <- function(rect_n_det = 24)
    write.csv(syn_census("multichm_gated", plots, 10, 8, 6, 6, rect_n_det = rect_n_det), gated,
              row.names = FALSE)
  write_base <- function(rect_n_det = 30)
    write.csv(syn_census("multichm", plots, 10, 12, 7, 6, rect_n_det = rect_n_det), base,
              row.names = FALSE)
  write_gated(); write_base()
  args <- c(paste0("CENSUS=", gated), paste0("BASE_CENSUS=", base))
  # the headline selection of the synthetic cells is z5_s0_c0_e0
  for (s in c("SJER", "WREF")) syn_stamp(st$d, s, mcg_config(8, 0, 0, FALSE))
  expect_error(analyze_with(st, args), "the censused scores are of configuration z8_s0_c0_e0")
  for (s in c("SJER", "WREF")) syn_stamp(st$d, s, mcg_config(5, 0, 0, FALSE))
  # with the stamps holding the selection, censused files of other detections
  # (here the other configuration's counts) still stop the stage
  write_gated(30)
  expect_error(analyze_with(st, args),
               "does not score the multichm_gated detections of configuration z5_s0_c0_e0",
               fixed = TRUE)
  write_gated(); write_base(24)
  expect_error(analyze_with(st, args),
               "does not score the multichm detections of configuration stock", fixed = TRUE)
  write_base()
  g <- syn_census("multichm_gated", plots, 10, 8, 6, 6)
  write.csv(g[setdiff(names(g), "rect_n_det")], gated, row.names = FALSE)
  expect_error(analyze_with(st, args), "has no rect_n_det", fixed = TRUE)
  write_gated()
  a <- analyze_with(st, args)
  expect_true(any(grepl("census_scores.csv, census_contrasts.csv", a$out, fixed = TRUE)))
  k <- read.csv(file.path(st$out, "census_contrasts.csv"), stringsAsFactors = FALSE)
  expect_identical(unique(k$split), c("all", "valid"))
  expect_identical(k$n_plots[k$split == "all" & k$scope == "SJER+WREF"], rep(16L, 3))
  expect_true(file.exists(file.path(st$out, "census_scores.csv")))
  expect_true(any(startsWith(readLines(file.path(st$out, "tables.md")), "## Censused subplots")))
  # without the paper runs' file: skipped, and the earlier files are removed
  b <- analyze_with(st, args[1])
  expect_true(any(grepl(paste("no censused scores at BASE_CENSUS (neither BASE= nor",
                              "BASE_CENSUS= given); the censused contrast is skipped"),
                        b$out, fixed = TRUE)))
  expect_false(any(file.exists(file.path(st$out, c("census_scores.csv", "census_contrasts.csv")))))
  expect_false(any(startsWith(readLines(file.path(st$out, "tables.md")), "## Censused subplots")))
  # by default the arm's file is looked for under the job directory
  b <- analyze_with(st)
  expect_true(any(grepl(paste0("no censused scores at ", cv_census_csv(st$d)), b$out,
                        fixed = TRUE)))
})

test_that("the analyze stage adds the censused reference contrast only beside the main one", {
  st <- syn_study()
  plots <- c(sprintf("SJER_%03d", 1:8), sprintf("WREF_%03d", 1:8))
  gated <- file.path(st$d, "gated.csv"); base <- file.path(st$d, "base.csv")
  refc <- file.path(st$d, "reference.csv")
  # the nominal-box counts of the synthetic cells: the selection 24, stock 30, and
  # the reference z8_s0_c0_e0 20
  write.csv(syn_census("multichm_gated", plots, 10, 8, 6, 6, rect_n_det = 24), gated,
            row.names = FALSE)
  write.csv(syn_census("multichm", plots, 10, 12, 7, 6, rect_n_det = 30), base, row.names = FALSE)
  write_ref <- function(rect_n_det = 20)
    write.csv(syn_census("multichm_gated", plots, 10, 7, 5, 5, rect_n_det = rect_n_det), refc,
              row.names = FALSE)
  for (s in c("SJER", "WREF")) syn_stamp(st$d, s, mcg_config(5, 0, 0, FALSE))
  main <- c(paste0("CENSUS=", gated), paste0("BASE_CENSUS=", base))
  ref <- c("REFERENCE=z8_s0_c0_e0", paste0("REFERENCE_CENSUS=", refc))
  ref_files <- file.path(st$out, c("census_reference_scores.csv", "census_reference_contrasts.csv"))
  expect_error(analyze_with(st, main, ref), "no censused scores of the reference configuration at")
  # a file of other detections than the reference configuration's
  write_ref(24)
  expect_error(analyze_with(st, main, ref),
               "does not score the multichm_gated detections of configuration z8_s0_c0_e0",
               fixed = TRUE)
  write_ref()
  # the main censused contrast must run too
  expect_error(analyze_with(st, main[1], ref),
               paste("REFERENCE_CENSUS= needs the censused contrast of the selection, which did",
                     "not run (it needs both CENSUS and BASE_CENSUS)"), fixed = TRUE)
  a <- analyze_with(st, main, ref)
  expect_true(any(grepl(paste("census_scores.csv, census_contrasts.csv,",
                              "census_reference_scores.csv, census_reference_contrasts.csv"),
                        a$out, fixed = TRUE)))
  expect_true(all(file.exists(ref_files)))
  k <- read.csv(ref_files[2], stringsAsFactors = FALSE)
  expect_true(all(k$from == "reference" & k$to == "multichm_gated"))
  f1 <- function(TP, n_det) { r <- TP / 10; p <- TP / n_det; 2 * r * p / (r + p) }
  expect_equal(k$estimate[k$split == "all" & k$scope == "SJER+WREF" & k$metric == "F1"],
               f1(6, 8) - f1(5, 7))
  sc <- read.csv(ref_files[1], stringsAsFactors = FALSE)
  expect_setequal(sc$detector, c("multichm_gated", "reference"))
  md <- readLines(file.path(st$out, "tables.md"))
  h <- match("## The selection against the reference configuration `z8_s0_c0_e0`", md)
  i <- match(paste("Inside the censused subplots at native density, from the arm's persisted",
                   "detections under each configuration; Δ = selected − reference:"), md)
  expect_true(h < i && i < match("## Difference between regions (validation plots)", md))
  expect_true(startsWith(md[i + 2],
                         "| Split | Scope | Plots | Stems | Detections selected / reference |"))
  v <- read.csv(file.path(st$out, "validation.csv"), stringsAsFactors = FALSE)
  expect_true(any(v$analysis == "reference"))
  # without REFERENCE_CENSUS the censused reference files go, the section stays
  b <- analyze_with(st, main, ref[1])
  expect_false(any(file.exists(ref_files)))
  md <- readLines(file.path(st$out, "tables.md"))
  expect_true(any(startsWith(md, "## The selection against the reference configuration")))
  expect_false(any(startsWith(md, "Inside the censused subplots at native density")))
  # without REFERENCE neither; the other outputs stay
  analyze_with(st, main)
  md <- readLines(file.path(st$out, "tables.md"))
  expect_false(any(startsWith(md, "## The selection against the reference configuration")))
  v <- read.csv(file.path(st$out, "validation.csv"), stringsAsFactors = FALSE)
  expect_false(any(v$analysis %in% c("reference", "reference_site")))
  expect_true(all(file.exists(file.path(st$out, c("census_scores.csv", "census_contrasts.csv",
                                                  "grid_contrasts.csv", "seed_grid.csv")))))
  # the selection itself as the reference: skipped, its censused file unread
  s <- analyze_with(st, main, "REFERENCE=z5_s0_c0_e0", paste0("REFERENCE_CENSUS=", refc))
  expect_true(any(grepl("is the headline selection itself; the reference contrasts are skipped",
                        s$out, fixed = TRUE)))
  expect_false(any(file.exists(ref_files)))
})
