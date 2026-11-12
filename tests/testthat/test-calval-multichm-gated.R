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
      cover = 0.5 + i / 20, pdens = 20, frdens = 10,
      config = cf$config, config_id = cf$config_id, zmin = cf$zmin, min_share = cf$min_share,
      cover_min = cf$cover_min, surface_exempt = cf$surface_exempt,
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
# it, scored on four configurations whose detection sets differ.
test_that("the score stage scores each configuration's own detections and its own null", {
  dir <- tempfile("mcg_score"); dir.create(dir)
  prep <- mcg_prepare(synth_closed_stand(), 0.5, CV_A_VWF)
  m <- data.frame(site = "SYN", plot = "SYN_002", plotType = "tower", rung = "native",
                  cx = 16, cy = 16, half = 16, pdens = 10, frdens = 5, cover = prep$cover,
                  file = cv_cell_file("SYN", "SYN_002", "native"), stringsAsFactors = FALSE)
  saveRDS(list(meta = m, prep = prep, parity = TRUE), file.path(dir, m$file))
  stems <- synth_closed_stems()
  g <- mcg_grid()
  grid <- g[match(c("stock", "z5_s0.75_c0.7_e0", "z0_s0_c0.7_e1", "z5_s0.75_c0.7_e1"), g$label), ]
  r <- cv_score_job(list(site = "SYN", plot = "SYN_002", half = 16, cells = m, stems = stems),
                    grid, dir, K = 5L, tol = 4, base = NULL)
  expect_identical(r$config, grid$label)
  expect_identical(r$config_id, grid$config_id)
  offs <- mcg_null_offsets("SYN", "SYN_002", 16, tol = 4, k = 5)
  for (i in seq_len(nrow(grid))) {
    cfg <- mcg_config(grid$zmin[i], grid$min_share[i], grid$cover_min[i], grid$surface_exempt[i])
    want <- mcg_score_cell(stems, mcg_apply(prep, cfg), 16, 16, 16, offs, tol = 4)
    expect_equal(unlist(r[i, MCG_COUNT_COLS]), unlist(want[MCG_COUNT_COLS]))
  }
  # the configurations do not all share one null
  expect_gt(length(unique(r$n_det0)), 1L)
  expect_identical(c(r$n_dominant[1], r$n_suppressed[1]), c(3, 1))
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
                     exemption = "z5_s0.75_c0.7_e0"))
  expect_true(all(unlist(comp) %in% mcg_grid()$label))
  # the floor alone: every reduction is the selection or stock
  fl <- cv_components(list(zmin = 5, min_share = 0, cover_min = 0, surface_exempt = FALSE))
  expect_length(fl$versus_stock, 0)
  expect_length(fl$marginal, 0)
  # no share gate: no share_gate part; without the exemption the cover is moot
  # (canonical cover 0), which repeats the floor alone and is dropped
  ns <- cv_components(list(zmin = 5, min_share = 0, cover_min = 0.6, surface_exempt = TRUE))
  expect_identical(ns$versus_stock, c(floor_only = "z5_s0_c0_e0", exemption_only = "z0_s0_c0.6_e1"))
  expect_identical(ns$marginal, c(floor = "z0_s0_c0.6_e1", exemption = "z5_s0_c0_e0"))
  expect_false("share_gate" %in% names(ns$marginal))
  expect_true(all(unlist(ns) %in% mcg_grid()$label))
  # the exemption alone: removing it gives stock, every other reduction the selection
  ex <- cv_components(list(zmin = 0, min_share = 0, cover_min = 0.7, surface_exempt = TRUE))
  expect_length(ex$versus_stock, 0)
  expect_length(ex$marginal, 0)
  # no exemption: no exemption part, and its versus-stock reduction is the selection
  ne <- cv_components(list(zmin = 5, min_share = 0.5, cover_min = 0.8, surface_exempt = FALSE))
  expect_identical(ne$versus_stock, c(floor_only = "z5_s0_c0_e0"))
  expect_identical(ne$marginal, c(floor = "z0_s0.5_c0.8_e0", share_gate = "z5_s0_c0_e0"))
  expect_true(all(unlist(ne) %in% mcg_grid()$label))
  expect_identical(cv_canonical_label(0, 0, 0.8, FALSE), "stock")
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
  expect_identical(dc[c("zmin", "min_share", "cover_min", "surface_exempt")],
                   list(zmin = 5, min_share = 0, cover_min = 0, surface_exempt = FALSE))
  expect_identical(dc$selection, "selected on the calibration plots at native density")
  expect_identical(c(dc$a, dc$radius, dc$half_dz, dc$cover_height), c(0.1, 1, 1, 2))
  expect_identical(c(dc$n_calibration_plots, dc$n_validation_plots), c(res$n_calib, res$n_valid))
  expect_match(dc$provenance, paste("test only the selection within the grid, not the grid's",
                                    "values or the choice of features"), fixed = TRUE)
  md <- cv_tables_md(res, S, "abc", "adopted")
  expect_true(any(grepl("calib (in-sample)", md, fixed = TRUE)))
  expect_true(any(grepl("^## All plots \\(in-sample; not a held-out result\\)$", md)))
  expect_false(any(grepl("^## All-plots selection", md)))
  expect_true(any(grepl("exploratory pass", md)))
  heads <- c("## Components of the selection (validation plots, native density)",
             paste("## What each part adds to the other two (the selection minus the selection",
                   "without that part, native density)"),
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
                        n_det = 26))
  cells <- syn_cells(sites = "WREF", n = 10, rungs = "native", configs = cf)
  bump <- as.integer(sub(".*_", "", cells$plot)) %% 3
  cells$TP <- cells$TP + bump; cells$tp_core <- cells$tp_core + bump
  res <- cv_analyze(cells, syn_settings(SITES = "WREF", RUNGS = "native", SEEDS = 1L))
  lab <- res$selected$label
  expect_identical(lab, "z5_s0.75_c0.7_e1")
  v <- res$validation
  comp <- v[startsWith(v$analysis, "component_"), ]
  expect_identical(comp$analysis, paste0("component_", c("floor_only", "no_share_gate",
                                                         "no_exemption", "exemption_only")))
  expect_identical(comp$config_a, c("z5_s0_c0_e0", "z5_s0_c0.7_e1", "z5_s0.75_c0.7_e0",
                                    "z0_s0_c0.7_e1"))
  expect_true(all(comp$config_b == "stock" & comp$split == "valid" & comp$rung == "native"))
  # what each part adds: the selection minus the selection without it, validation
  # rows then calibration rows
  mg <- v[startsWith(v$analysis, "marginal_"), ]
  parts <- c(floor = "z0_s0.75_c0.7_e1", share_gate = "z5_s0_c0.7_e1",
             exemption = "z5_s0.75_c0.7_e0")
  expect_identical(mg$analysis, rep(paste0("marginal_", names(parts)), 2))
  expect_identical(mg$split, rep(c("valid", "calib"), each = 3))
  expect_true(all(mg$config_a == lab & mg$rung == "native"))
  expect_identical(mg$config_b, unname(rep(parts, 2)))
  for (i in seq_len(nrow(mg))) {
    ids <- res$split[[mg$split[i]]]
    p <- mcg_pool(cells[cv_ids(cells) %in% ids & cells$config %in% c(lab, mg$config_b[i]), ],
                  "config")
    expect_identical(mg$n_plots[i], length(ids))
    expect_equal(mg$d_cF1[i], p$cF1[p$config == lab] - p$cF1[p$config == mg$config_b[i]])
  }
  expect_identical(res$components$marginal, parts)
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
                    stringsAsFactors = FALSE)
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
  expect_true(any(grepl("3 of the 5 splits reach the headline split's change", md,
                        fixed = TRUE)))
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
                    cover_height = MCG_COVER_HEIGHT, parity = TRUE, population = "adopted",
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
  # the digest follows every value of the grid
  g <- mcg_grid(); g$cover_min[10] <- 0.65
  expect_false(identical(cv_grid_digest(g), cv_grid_digest()))
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
  # every index row records the constants its candidates were made with
  expect_identical(unlist(unique(r[c("a", "radius", "half_dz", "cover_height")])),
                   c(a = CV_A_VWF, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                     cover_height = MCG_COVER_HEIGHT))
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
# reads), one row per plot ("SITE_nnn").
syn_census <- function(det, plots, n_ref, n_det, TP, tp_core, rung = "native")
  data.frame(site = sub("_.*", "", plots), plot = plots, rung = rung, detector = det,
             n_ref = n_ref, n_det = n_det, TP = TP, tp_core = tp_core,
             support_id = paste0("bundle_", plots),
             support_policy = "measured_subplots_uncertainty_interior_v1",
             reference_population = "live_mapped_boles_dbh_ge_10cm", stringsAsFactors = FALSE)

# A site's configuration stamp, as the arm driver writes it: the configuration,
# the window coefficient and the feature constants (`const`), then the label.
syn_stamp <- function(d, site, cfg,
                      const = list(a = CV_A_VWF, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                                   cover_height = MCG_COVER_HEIGHT)) {
  dd <- file.path(d, "neon", site, "multichm_gated_detections")
  dir.create(dd, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(c(cfg, const, list(label = mcg_config_label(cfg))),
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
  syn_stamp(d, "WREF", cfg, const = list(a = 0.3, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                                         cover_height = MCG_COVER_HEIGHT))
  expect_error(cv_census_config_check(d, c("SJER", "WREF"), sel),
               "the censused detections of WREF were not made with this study's a = 0.1, radius = 1",
               fixed = TRUE)
  syn_stamp(d, "WREF", cfg, const = list())
  expect_error(cv_census_config_check(d, c("SJER", "WREF"), sel),
               "the censused detections of WREF were not made with", fixed = TRUE)
  unlink(file.path(d, "neon", "WREF", "multichm_gated_detections", CV_ARM_CONFIG_STAMP))
  expect_error(cv_census_config_check(d, c("SJER", "WREF"), sel), "no configuration stamp at")
  expect_true(cv_census_config_check(d, "SJER", sel))
})

test_that("the analyze stage adds the censused contrast with both files, and drops it otherwise", {
  st <- syn_study()
  plots <- c(sprintf("SJER_%03d", 1:8), sprintf("WREF_%03d", 1:8))
  gated <- file.path(st$d, "gated.csv"); base <- file.path(st$d, "base.csv")
  write.csv(syn_census("multichm_gated", plots, 10, 8, 6, 6), gated, row.names = FALSE)
  write.csv(syn_census("multichm", plots, 10, 12, 7, 6), base, row.names = FALSE)
  args <- c(paste0("CENSUS=", gated), paste0("BASE_CENSUS=", base))
  # the headline selection of the synthetic cells is z5_s0_c0_e0
  for (s in c("SJER", "WREF")) syn_stamp(st$d, s, mcg_config(8, 0, 0, FALSE))
  expect_error(analyze_with(st, args), "the censused scores are of configuration z8_s0_c0_e0")
  for (s in c("SJER", "WREF")) syn_stamp(st$d, s, mcg_config(5, 0, 0, FALSE))
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
