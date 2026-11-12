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
  expect_identical(S$SEEDS, 1:10)
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
  extra <- rbind(ref, transform(ref[1, ], rung = "native", plot = "SJER_002", n_det = 99))
  expect_gt(nrow(cv_null_compare(cells, extra[-2, ], "stock", "multichm")$bad), 0)
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

test_that("components drop the exemption or the gate and skip stock and the selection", {
  sel <- list(zmin = 5, min_share = 0.75, cover_min = 0.7, surface_exempt = TRUE)
  expect_identical(cv_components(sel),
                   c(no_exemption = "z5_s0.75_c0.7_e0", exemption_only = "z0_s0_c0.7_e1"))
  # no share gate: without the exemption the cover is moot (canonical cover 0)
  expect_identical(cv_components(list(zmin = 5, min_share = 0, cover_min = 0.6, surface_exempt = TRUE)),
                   c(no_exemption = "z5_s0_c0_e0", exemption_only = "z0_s0_c0.6_e1"))
  # exemption only: removing it gives stock, removing the gate gives the selection
  expect_length(cv_components(list(zmin = 0, min_share = 0, cover_min = 0.7, surface_exempt = TRUE)), 0)
  # no exemption: the first component is the selection, the second is stock
  expect_length(cv_components(list(zmin = 5, min_share = 0.5, cover_min = 0.8,
                                   surface_exempt = FALSE)), 0)
  expect_identical(cv_canonical_label(0, 0, 0.8, FALSE), "stock")
  expect_true(all(c(cv_components(sel)) %in% mcg_grid()$label))
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
  expect_identical(c(dc$radius, dc$half_dz, dc$cover_height), c(1, 1, 2))
  expect_identical(c(dc$n_calibration_plots, dc$n_validation_plots), c(res$n_calib, res$n_valid))
  expect_match(dc$provenance, "threshold selection, not the choice of features")
  md <- cv_tables_md(res, S, "abc", "adopted")
  expect_true(any(grepl("calib (in-sample)", md, fixed = TRUE)))
  expect_true(any(grepl("^## All-plots selection \\(for the record only", md)))
  expect_true(any(grepl("exploratory pass", md)))
  # the first such row is the headline table's (seed and criterion rows follow)
  row <- grep("^\\| SJER\\+WREF \\| native \\| valid \\| z5_s0_c0_e0 \\| stock \\|", md, value = TRUE)[1]
  expect_match(row, sprintf("%.3f [%.3f, %.3f]", hv$d_cF1, hv$lo_cF1, hv$hi_cF1), fixed = TRUE)
})

test_that("components of an exempting selection are scored against stock", {
  cf <- rbind(SYN_CONFIGS[1, ],
              transform(SYN_CONFIGS[2, ], config = "z5_s0.75_c0.7_e1", config_id = 60L,
                        min_share = 0.75, cover_min = 0.7, surface_exempt = TRUE, TP = 14),
              transform(SYN_CONFIGS[2, ], config = "z5_s0.75_c0.7_e0", config_id = 20L,
                        min_share = 0.75, cover_min = 0.7, TP = 11),
              transform(SYN_CONFIGS[2, ], config = "z0_s0_c0.7_e1", config_id = 50L, zmin = 0,
                        cover_min = 0.7, surface_exempt = TRUE, TP = 12, n_det = 32))
  cells <- syn_cells(sites = "WREF", n = 10, rungs = "native", configs = cf)
  res <- cv_analyze(cells, syn_settings(SITES = "WREF", RUNGS = "native", SEEDS = 1L))
  expect_identical(res$selected$label, "z5_s0.75_c0.7_e1")
  comp <- res$validation[startsWith(res$validation$analysis, "component_"), ]
  expect_identical(comp$analysis, c("component_no_exemption", "component_exemption_only"))
  expect_identical(comp$config_a, c("z5_s0.75_c0.7_e0", "z0_s0_c0.7_e1"))
  expect_true(all(comp$config_b == "stock" & comp$split == "valid" & comp$rung == "native"))
  expect_false(any(res$validation$analysis == "leave_one_site_out"))   # one site only
  expect_false(any(res$validation$config_b == "chm_vwf"))
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
                    parity = TRUE, population = "adopted",
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
