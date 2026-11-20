# Unit tests for the C5 confirmation driver (confirm_gated_fgiemit.R): the
# gated multichm configurations on the FGI-EMIT development plots. Sourcing the
# script defines its helpers without running it (guarded by
# `if (sys.nframe() == 0L) run_main()`). Synthetic inputs only: no FGI-EMIT
# data, no NEON data.
source(file.path("..", "..", "scripts", "confirm_gated_fgiemit.R"), local = TRUE)

# A normalized LAS from explicit points (X, Y, Z, optional return fields and
# classification).
cgf_las <- function(df) {
  for (k in intersect(c("ReturnNumber", "NumberOfReturns", "Classification"), names(df)))
    df[[k]] <- as.integer(df[[k]])
  for (k in c("X", "Y", "Z")) df[[k]] <- as.numeric(df[[k]])
  suppressWarnings(lidR::LAS(df))
}
# Conical crowns with first returns on their surfaces, later returns inside and
# first-return ground hits (class 2 at Z 0).
cgf_stand <- function(seed = 1) {
  set.seed(seed)
  tr <- data.frame(x = c(10, 18, 27, 11, 25, 19), y = c(10, 12, 9, 23, 24, 18),
                   h = c(22, 18, 20, 16, 21, 8), r = c(3.5, 3, 3.2, 2.8, 3.4, 2))
  crown <- lapply(seq_len(nrow(tr)), function(i) {
    t <- tr[i, ]
    d <- t$r * sqrt(runif(700)); a <- runif(700, 0, 2 * pi)
    s <- data.frame(X = t$x + d * cos(a), Y = t$y + d * sin(a),
                    Z = pmax(0.1, t$h * (1 - 0.6 * d / t$r) + rnorm(700, 0, 0.1)),
                    ReturnNumber = 1L, NumberOfReturns = 2L, Classification = 1L)
    d <- 0.8 * t$r * sqrt(runif(250)); a <- runif(250, 0, 2 * pi)
    n <- data.frame(X = t$x + d * cos(a), Y = t$y + d * sin(a),
                    Z = runif(250, 0.3 * t$h, 0.9 * t$h), ReturnNumber = 2L,
                    NumberOfReturns = 2L, Classification = 1L)
    rbind(s, n)
  })
  g <- data.frame(X = runif(2500, 0, 36), Y = runif(2500, 0, 32), Z = 0, ReturnNumber = 1L,
                  NumberOfReturns = 1L, Classification = 2L)
  list(las = cgf_las(do.call(rbind, c(crown, list(g)))), trees = tr)
}

## ---- arguments and paths ----------------------------------------------------------------------
test_that("arguments parse as KEY=VALUE with defaults under the job directory", {
  d <- file.path(tempdir(), "cgf_job")
  S <- cgf_settings(character(), d = d)
  expect_identical(S$STAGE, "all")
  expect_identical(S$ROOT, file.path(d, "external", "fgiemit"))
  expect_identical(S$THIN, file.path(d, "fgiemit-thinning"))
  expect_identical(S$SELECT, file.path(d, "fgiemit-thinning", "select"))
  expect_identical(S$OUT, file.path(d, "multichm_gated_confirmation", "fgiemit"))
  expect_identical(S$PLOTS, CGF_DEV)
  expect_identical(S$CORES, 6L)
  expect_true(S$PARITY)
  S <- cgf_settings(c("PLOTS=1001,1022", "CORES=2", "SELECT=/x/y", "PARITY=FALSE",
                      "STAGE=harness"), d = d)
  expect_identical(S$PLOTS, c("1001", "1022"))
  expect_identical(S$CORES, 2L)
  expect_identical(S$SELECT, "/x/y")
  expect_false(S$PARITY)
  expect_identical(S$STAGE, "harness")
})

test_that("more than six cores, an unknown stage and non-development plots stop", {
  d <- tempdir()
  expect_error(cgf_settings("CORES=7", d = d), "CORES")
  expect_error(cgf_settings("CORES=0", d = d), "CORES")
  expect_error(cgf_settings("STAGE=score", d = d), "STAGE")
  # 1003 is an evaluation-reserve plot, 1002 a historical test plot
  expect_error(cgf_settings("PLOTS=1001,1003", d = d), "development")
  expect_error(cgf_settings("PLOTS=1002", d = d), "development")
  expect_error(cgf_cloud_file("/r", "/s", "1010", "native"), "development")
  expect_error(cgf_chm_dir("/r", "/t", "1023", "pulses_9.8"), "development")
})

test_that("cloud and CHM-VWF paths follow the thinning study's layout", {
  expect_identical(cgf_cloud_file("/r", "/s", "1005", "native"),
                   file.path("/r", "development_inputs", "1005", "normalized.laz"))
  expect_identical(cgf_cloud_file("/r", "/s", "1005", "pulses_4.7"),
                   file.path("/s", "1005", "pulses_4.7", "normalized.laz"))
  expect_identical(cgf_chm_dir("/r", "/t", "1001", "native"),
                   file.path("/r", "development_pilot_v3", "1001", "chm_vwf"))
  expect_identical(cgf_chm_dir("/r", "/t", "1005", "native"),
                   file.path("/r", "development_detector_run", "1005", "chm_vwf"))
  expect_identical(cgf_chm_dir("/r", "/t", "1005", "pulses_0.6"),
                   file.path("/t", "run", "1005", "pulses_0.6", "chm_vwf"))
})

test_that("outputs may not lie in a read-only input tree", {
  d <- file.path(tempfile("cgfjob")); dir.create(d)
  ext <- tempfile("cgfext"); dir.create(file.path(ext, "fgiemit-thinning"), recursive = TRUE)
  file.symlink(file.path(ext, "fgiemit-thinning"), file.path(d, "fgiemit-thinning"))
  expect_true(cgf_check_out(file.path(d, "multichm_gated_confirmation", "fgiemit"), d))
  for (top in c("external", "fgiemit-thinning", "fgiemit-new", "paper_runs", "paper_runs_v2",
                "multichm_gated_runs", "multichm_gated_runs_2"))
    expect_error(cgf_check_out(file.path(d, top, "out"), d), "read-only")
  # the resolved path of a linked input is caught too
  expect_error(cgf_check_out(file.path(ext, "fgiemit-thinning", "x"), d,
                             inputs = file.path(d, "fgiemit-thinning")), "outside the input")
  expect_true(cgf_check_out(file.path(tempdir(), "elsewhere"), d,
                            inputs = file.path(d, "fgiemit-thinning")))
})

test_that("densities are read for development plots only, native first, dense to sparse", {
  sel <- tempfile("cgfsel"); dir.create(sel)
  x <- data.frame(plot = rep(c("1001", "1005"), each = 3), target = rep(c(0.6, NA, 9.8), 2),
                  label = rep(c("pulses_0.6", "native", "pulses_9.8"), 2), points = 1,
                  pdens = 2, frdens = c(0.7, 1500, 11.2, 0.7, 1200, 11.3), first_share = 0.8,
                  area_m2 = 1256)
  utils::write.csv(x, file.path(sel, "thinning_densities.csv"), row.names = FALSE)
  d <- cgf_densities(sel)
  expect_identical(unique(d$label), c("native", "pulses_9.8", "pulses_0.6"))
  expect_identical(d$plot[1:2], c("1001", "1005"))
  expect_identical(nrow(cgf_densities(sel, "1005")), 3L)
  x$plot[1] <- "1010"
  utils::write.csv(x, file.path(sel, "thinning_densities.csv"), row.names = FALSE)
  expect_error(cgf_densities(sel), "development")
  expect_identical(cgf_label_order(c("pulses_1.3", "native", "pulses_9.8", "pulses_4.7")),
                   c("native", "pulses_9.8", "pulses_4.7", "pulses_1.3"))
})

test_that("the native cloud's digest is the source every thinned receipt names", {
  sel <- tempfile("cgfsel")
  rc <- function(l, own, src) {
    dir.create(file.path(sel, "1001", l), recursive = TRUE)
    jsonlite::write_json(list(plot = "1001", files = list(normalized.laz = list(
      source_sha256 = src, sha256 = own))), file.path(sel, "1001", l, "receipt.json"),
      auto_unbox = TRUE)
  }
  rc("pulses_9.8", "aaa", "nat"); rc("pulses_0.6", "bbb", "nat")
  expect_identical(cgf_expected_sha(sel, "1001", "pulses_9.8"), "aaa")
  expect_identical(cgf_expected_sha(sel, "1001", "native"), "nat")
  rc("pulses_4.7", "ccc", "other")
  expect_error(cgf_expected_sha(sel, "1001", "native"), "native clouds")
})

test_that("references keep the max_agl apexes of development plots", {
  root <- tempfile("cgfroot"); dir.create(file.path(root, "development_comparison"),
                                          recursive = TRUE)
  r <- data.frame(instance = c(1, 1, 2, 1), policy = c("max_agl", "isolated_top_agl", "max_agl",
                                                       "max_agl"),
                  x = 1:4, y = 1:4, z = 10, plot = c("1001", "1001", "1001", "1005"),
                  category = "A")
  f <- file.path(root, "development_comparison", "reference_apexes.csv")
  utils::write.csv(r, f, row.names = FALSE)
  x <- cgf_references(root)
  expect_identical(nrow(x), 3L)
  expect_identical(nrow(cgf_references(root, "1001")), 2L)
  r$plot[4] <- "1003"
  utils::write.csv(r, f, row.names = FALSE)
  expect_error(cgf_references(root), "development")
})

## ---- configurations and resolution ------------------------------------------------------------
test_that("the five configurations are the frozen grid rows in protocol order", {
  g <- cgf_configs()
  expect_identical(g$config, CGF_CONFIGS)
  grid <- mcg_grid()
  expect_identical(g$config_id, grid$config_id[match(CGF_CONFIGS, grid$label)])
  expect_identical(cgf_cfg(g[1, ]), MCG_STOCK)
  expect_identical(cgf_cfg(g[g$config == "z5_s0.75_c0.6_e1_d8", ]), MCG_DECLARED)
  for (k in seq_len(nrow(g))) expect_identical(mcg_config_label(cgf_cfg(g[k, ])), g$config[k])
  expect_error(cgf_configs(grid[grid$label != "z5_s0_c0.6_e1", ]), "not in mcg_grid")
})

test_that("the canopy model is 0.25 m at 8 first returns per m2 or more, else 0.5 m", {
  expect_identical(cgf_res(1300), 0.25)
  expect_identical(cgf_res(8), 0.25)
  expect_identical(cgf_res(7.999), 0.5)
  expect_identical(cgf_res(0.7), 0.5)
  expect_error(cgf_res(NA_real_), "first-return density")
})

## ---- cloud checks -----------------------------------------------------------------------------
test_that("return numbers must be present and consistent", {
  base <- data.frame(X = c(0, 1, 2), Y = 0, Z = c(0, 5, 3), ReturnNumber = c(1, 1, 2),
                     NumberOfReturns = c(1, 2, 2), Classification = c(2, 1, 1))
  expect_true(cgf_return_check(cgf_las(base))$ok)
  expect_equal(cgf_return_check(cgf_las(base))$first_share, 2 / 3)
  bad <- base; bad$ReturnNumber[3] <- 3L
  expect_match(cgf_return_check(cgf_las(bad))$reason, "above the number of returns")
  bad <- base; bad$ReturnNumber[1] <- 0L
  expect_match(cgf_return_check(cgf_las(bad))$reason, "below 1")
  bad <- base; bad$ReturnNumber <- c(2L, 2L, 2L); bad$NumberOfReturns <- 2L
  expect_match(cgf_return_check(cgf_las(bad))$reason, "no first return")
  no <- base[, c("X", "Y", "Z")]
  r <- cgf_return_check(cgf_las(no))
  expect_false(r$ok)
  expect_match(r$reason, "no ReturnNumber")
})

test_that("a cloud is height-normalised when its ground sits at 0 m", {
  ok <- data.frame(X = 1:4, Y = 0, Z = c(0, 0, 4, 9), Classification = c(2, 2, 1, 1))
  expect_true(cgf_height_check(cgf_las(ok))$ok)
  raw <- ok; raw$Z <- raw$Z + 312
  expect_match(cgf_height_check(cgf_las(raw))$reason, "median height")
  nog <- ok; nog$Classification <- 1L
  expect_match(cgf_height_check(cgf_las(nog))$reason, "no ground")
  low <- data.frame(X = 1:10, Y = 0, Z = c(0, 0, -3, rep(5, 7)), Classification = c(2, 2, rep(1, 8)))
  expect_match(cgf_height_check(cgf_las(low))$reason, "below -1 m")
})

## ---- scoring ----------------------------------------------------------------------------------
test_that("scoring is the thinning study's 4 m / 5 m greedy one-to-one apex match", {
  ref <- data.frame(plot = "1001", instance = 1:4, x = c(0, 10, 20, 30), y = 0,
                    z = c(20, 20, 20, 20))
  det <- data.frame(x = c(1, 13.9, 24.5, 30, 30.5, 50), y = 0, z = c(19, 20, 20, 14.5, 26, 10))
  # 0 m: matched; 10: 3.9 m away, matched; 20: 4.5 m away, not; 30: dz 5.5 and 6, not
  s <- cgf_score(det, ref)
  expect_equal(unname(s), c(4, 6, 2, 2))
  expect_identical(names(s), c("n_ref", "n_det", "TP", "tp_core"))
  expect_identical(cgf_score(det[rev(seq_len(nrow(det))), ], ref), s)
  m <- audit_apex_match(det[order(det$x, det$y, det$z), ], ref)
  expect_equal(unname(s[["TP"]]), m$apex_TP)
  # one detection between two references counts once
  two <- data.frame(plot = "1001", instance = 1:2, x = c(0, 2), y = 0, z = 20)
  expect_equal(unname(cgf_score(data.frame(x = 1.2, y = 0, z = 20), two)), c(2, 1, 1, 1))
  expect_equal(unname(cgf_score(data.frame(x = numeric(), y = numeric(), z = numeric()), ref)),
               c(4, 0, 0, 0))
  expect_error(cgf_score(det, rbind(ref, transform(ref, plot = "1005"))), "one plot")
  expect_error(cgf_score(data.frame(a = 1), ref), "x, y, z")
})

test_that("a stored apex file is scored in instance order, other detections by x, y, z", {
  # Three pairs at 2 m: (tree at 0, detection at 2), (tree at 0, detection at
  # -2), (tree at 4, detection at 2). Ties go to the earlier detection row, so
  # taking the detection at 2 first leaves the tree at 4 unmatched.
  ref <- data.frame(plot = "1001", instance = 1:2, x = c(0, 4), y = 0, z = 20)
  det <- data.frame(x = c(2, -2), y = 0, z = 20, instance = c(1L, 2L))
  expect_equal(cgf_score(det, ref)[["TP"]], 1)
  det$instance <- c(2L, 1L)
  expect_equal(cgf_score(det, ref)[["TP"]], 2)
  expect_equal(cgf_score(det[, c("x", "y", "z")], ref)[["TP"]], 2)   # sorted: -2 first
})

test_that("CHM-VWF counts are read from metrics.json as the thinning summary reads them", {
  f <- tempfile(fileext = ".json")
  jsonlite::write_json(list(detection = list(
    list(policy = "isolated_top_agl", apex_TP = 1, apex_FP = 1, apex_FN = 1, apex_F1 = 0.5),
    list(policy = "max_agl", apex_TP = 34, apex_FP = 1, apex_FN = 99, apex_F1 = 0.4048)),
    mask = setNames(list(), character())), f, auto_unbox = TRUE)
  expect_equal(cgf_metrics_counts(f), c(n_ref = 133, n_det = 35, TP = 34, tp_core = 34))
  jsonlite::write_json(list(detection = list(list(policy = "isolated_top_agl", apex_TP = 1,
                                                  apex_FP = 0, apex_FN = 0))), f, auto_unbox = TRUE)
  expect_error(cgf_metrics_counts(f), "max_agl")
})

## ---- rows, pooling, qualification ---------------------------------------------------------------
cgf_meta <- function(plot = "1001", rung = "native", cover = 0.7, spacing = 9)
  list(plot = plot, rung = rung, target = NA_real_, cover = cover, top_height = 20,
       crown_spacing = spacing, pdens = 2000, frdens = 1500, res = 0.25)

test_that("rows carry the NEON cell columns, NA for the null and class columns", {
  g <- cgf_configs()
  r <- cgf_row(cgf_meta(), c(n_ref = 10, n_det = 8, TP = 6, tp_core = 6), g[4, ])
  expect_identical(names(r), CGF_COLS)
  expect_identical(names(r)[seq_along(CGF_NEON_COLS)], CGF_NEON_COLS)
  expect_true(all(is.na(r[CGF_NA_COLS])))
  expect_identical(r$site, "FGIEMIT")
  expect_identical(r$plotType, "external")
  expect_identical(r$config, "z5_s0.75_c0.6_e1_d8")
  expect_identical(r$config_id, 360L)
  expect_identical(c(r$zmin, r$min_share, r$cover_min, r$spacing_min), c(5, 0.75, 0.6, 8))
  expect_true(r$surface_exempt)
  expect_true(r$closed); expect_true(r$spaced); expect_true(r$gated)
  # an open stand is not gated; a closed stand of narrow spacing is gated only
  # by the configuration without a spacing condition
  expect_false(cgf_row(cgf_meta(cover = 0.5), c(n_ref = 1, n_det = 1, TP = 1, tp_core = 1),
                       g[4, ])$gated)
  narrow <- cgf_meta(spacing = 7)
  expect_false(cgf_row(narrow, c(n_ref = 1, n_det = 1, TP = 1, tp_core = 1), g[4, ])$gated)
  expect_true(cgf_row(narrow, c(n_ref = 1, n_det = 1, TP = 1, tp_core = 1), g[5, ])$gated)
  expect_false(cgf_row(narrow, c(n_ref = 1, n_det = 1, TP = 1, tp_core = 1), g[1, ])$gated)
  v <- cgf_row(cgf_meta(), c(n_ref = 10, n_det = 5, TP = 4, tp_core = 4))
  expect_identical(v$config, "chm_vwf")
  expect_true(is.na(v$config_id))
  expect_true(all(is.na(v[c("zmin", "min_share", "cover_min", "surface_exempt", "spacing_min",
                            "gated")])))
  expect_true(v$closed)
})

test_that("pooling sums counts: recall = TP / n_ref and precision = tp_core / n_det", {
  g <- cgf_configs()
  cells <- rbind(
    cgf_row(cgf_meta("1001"), c(n_ref = 100, n_det = 50, TP = 40, tp_core = 40), g[1, ]),
    cgf_row(cgf_meta("1019"), c(n_ref = 8, n_det = 16, TP = 8, tp_core = 8), g[1, ]),
    cgf_row(cgf_meta("1001"), c(n_ref = 100, n_det = 45, TP = 39, tp_core = 39)),
    cgf_row(cgf_meta("1019"), c(n_ref = 8, n_det = 10, TP = 8, tp_core = 8)))
  P <- cgf_pool(cells)
  s <- P[P$config == "stock", ]
  expect_equal(c(s$n_cells, s$n_ref, s$n_det, s$TP), c(2, 108, 66, 48))
  expect_equal(s$recall, 48 / 108)
  expect_equal(s$precision, 48 / 66)
  expect_equal(s$F1, 2 * 48 / (108 + 66))
  # not the mean of the per-plot rates
  expect_false(isTRUE(all.equal(s$recall, mean(c(40 / 100, 8 / 8)))))
  expect_equal(P$F1[P$config == "chm_vwf"], 2 * 47 / (108 + 55))
})

test_that("a density qualifies only when every plot has every configuration", {
  g <- cgf_configs()
  mk <- function(p, l, k) cgf_row(cgf_meta(p, l), c(n_ref = 1, n_det = 1, TP = 1, tp_core = 1),
                                  if (k == "chm_vwf") NULL else g[g$config == k, ])
  cfs <- c(g$config, "chm_vwf")
  cells <- do.call(rbind, c(
    lapply(cfs, function(k) mk("1001", "native", k)), lapply(cfs, function(k) mk("1005", "native", k)),
    lapply(cfs, function(k) mk("1001", "pulses_0.6", k)),
    lapply(setdiff(cfs, "z5_s0.75_c0.6_e1_d8"), function(k) mk("1005", "pulses_0.6", k))))
  expect_identical(cgf_qualifying(cells, c("1001", "1005"), cfs), "native")
  expect_identical(cgf_qualifying(cells, "1001", cfs), c("native", "pulses_0.6"))
})

## ---- harness proof ----------------------------------------------------------------------------
test_that("the harness re-scores stored detections beside the study's counts", {
  dir <- tempfile("cgfchm"); dir.create(dir)
  ref <- data.frame(plot = "1001", instance = 1:3, x = c(0, 10, 20), y = 0, z = 20,
                    category = "A")
  utils::write.csv(data.frame(x = c(0.5, 10.5, 40), y = 0, z = 20, instance = 1:3,
                              policy = "max_agl", confidence = 20),
                   file.path(dir, "prediction_apexes.csv"), row.names = FALSE)
  wj <- function(tp, fp, fn) jsonlite::write_json(list(detection = list(list(
    policy = "max_agl", apex_TP = tp, apex_FP = fp, apex_FN = fn))),
    file.path(dir, "metrics.json"), auto_unbox = TRUE)
  wj(2, 1, 1)
  jobs <- data.frame(plot = "1001", label = "native", chm_dir = dir, stringsAsFactors = FALSE)
  h <- cgf_harness_cells(jobs, ref)
  expect_true(h$same)
  expect_equal(c(h$rescored_n_ref, h$rescored_n_det, h$rescored_TP), c(3, 3, 2))
  hp <- cgf_harness_pooled(h, published = c(native = 0.667))
  expect_equal(hp$rescored_F1, 2 * 2 / 6)
  expect_true(hp$matches_published)
  expect_false(cgf_harness_pooled(h, published = c(native = 0.5))$matches_published)
  wj(3, 0, 0)
  expect_false(cgf_harness_cells(jobs, ref)$same)
})

## ---- the detector on a synthetic stand --------------------------------------------------------
test_that("every configuration runs on a stand and stock matches lidRplugins::multichm", {
  skip_if_not_installed("lidRplugins")
  st <- cgf_stand(1)
  g <- cgf_configs()
  run <- cgf_detect(st$las, 0.5, g)
  expect_false(inherits(run, "cgf_failed"))
  expect_identical(names(run$dets), g$config)
  for (d in run$dets) {
    expect_true(assert_detection_contract(d))
    expect_true(all(d$z >= 2))
  }
  expect_true(.cgf_same_dets(run$dets[["stock"]], .cgf_package_dets(st$las, 0.5)))
  ref <- data.frame(plot = "1001", instance = seq_len(nrow(st$trees)), x = st$trees$x,
                    y = st$trees$y, z = st$trees$h)
  s <- cgf_score(run$dets[["stock"]], ref)
  expect_equal(s[["n_det"]], nrow(run$dets[["stock"]]))
  expect_gte(s[["TP"]], 5)
})

test_that("a configuration that stops on a cloud is reported, not dropped", {
  st <- cgf_stand(2)
  las <- st$las
  las@data$ReturnNumber <- NULL
  run <- cgf_detect(las, 0.5, cgf_configs())
  expect_s3_class(run, "cgf_failed")
  expect_identical(run$config, "z5_s0_c0.6_e1")
  expect_match(run$error, "canopy cover")
})

test_that("detection sets compare by their points, in any order", {
  a <- data.frame(x = c(1, 2), y = c(3, 4), z = c(5, 6))
  expect_true(.cgf_same_dets(a, a[2:1, ]))
  expect_false(.cgf_same_dets(a, a[1, ]))
  b <- a; b$z[1] <- 5 + 1e-6
  expect_false(.cgf_same_dets(a, b))
  e <- a[0, ]
  expect_true(.cgf_same_dets(e, e))
})
