source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "analyze_forestmamba.R"), local = TRUE)

# A sealed root stand-in: the stamp and sidecars name its clip manifest's hash.
fma_root <- function(dir) {
  root <- file.path(dir, "root"); dir.create(root)
  writeLines(c("site,plot,rung", "S1,P1,native"), file.path(root, "clip_manifest.csv"))
  root
}

# Rows as the sweeps write them: counts per cell plus the crown-class columns.
fma_cells <- function(arm, site, plots, rung, TP, n_det, tp_core, n_ref = 10) {
  x <- data.frame(site = site, plot = plots, rung = rung, detector = arm,
                  n_ref = n_ref, n_det = n_det, TP = TP,
                  precision = ifelse(n_det > 0, tp_core / n_det, NA_real_),
                  tp_core = tp_core, stringsAsFactors = FALSE)
  for (k in c("dominant", "codominant", "intermediate", "suppressed",
              "h_short", "h_mid", "h_tall")) {
    x[[paste0("n_", k)]] <- if (k %in% c("dominant", "intermediate")) n_ref / 2 else 0
    x[[paste0("rec_", k)]] <- if (k == "dominant") pmin(1, TP / (n_ref / 2)) else
      if (k == "intermediate") 0 else NA_real_
  }
  x
}

test_that("outputs count only when stamped with the sealed root and population", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  root <- fma_root(d); id <- frozen_root_id(root)
  side <- file.path(d, "r.csv.frozen")
  jsonlite::write_json(list(clip_manifest_sha256 = id, population = "adopted"), side,
                       auto_unbox = TRUE)
  expect_true(fma_stamped(side, root, id, "adopted"))
  expect_false(fma_stamped(side, root, id, "relaxed"))
  expect_false(fma_stamped(file.path(d, "none.frozen"), root, id, "adopted"))
  inst <- file.path(d, "inst"); frozen_stamp(inst, root)
  expect_true(fma_stamped(inst, root, id, "adopted"))
  expect_false(fma_stamped(file.path(d, "unstamped"), root, id, "adopted"))
})

test_that("an arm enters only with every declared cell and the declared reference", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  root <- fma_root(d); id <- frozen_root_id(root)
  nd <- file.path(d, "job", "neon", "S1"); dir.create(nd, recursive = TRUE)
  rows <- fma_cells("forestmamba", "S1", c("P1", "P2"), "native", c(5, 6), c(8, 9), c(5, 5))
  write.csv(rows, file.path(nd, "forestmamba_results.csv"), row.names = FALSE)
  need <- c("S1::P1::native", "S1::P2::native")
  nref <- c("S1::P1" = 10L, "S1::P2" = 10L)
  get <- function(...) fma_arm_rows(file.path(d, "job"), "S1", FMA_FOCUS, root, id,
                                    "adopted", ...)
  expect_identical(get(need, nref)$status$status, "outputs not stamped with the sealed root")
  jsonlite::write_json(list(clip_manifest_sha256 = id, population = "adopted"),
                       file.path(nd, "forestmamba_results.csv.frozen"), auto_unbox = TRUE)
  ok <- get(need, nref)
  expect_identical(ok$status$status, "included")
  expect_equal(nrow(ok$rows), 2L)
  expect_true(all(MT_STRATUM_COLS %in% names(ok$rows)))
  short <- get(c(need, "S1::P3::native"), c(nref, "S1::P3" = 10L))
  expect_identical(short$status$status, "2 of 3 cells")
  expect_null(short$rows)
  expect_error(get(need, c("S1::P1" = 10L, "S1::P2" = 11L)), "differs from the declared")
})

test_that("scores pool summed counts and contrasts are focus minus arm on shared draws", {
  eq <- rbind(fma_cells("forestmamba", "S1", c("P1", "P2"), "native", c(6, 4), c(8, 8), c(6, 4)),
              fma_cells("forestmamba", "S2", "P3", "native", 9, 10, 9),
              fma_cells("other", "S1", c("P1", "P2"), "native", c(3, 5), c(6, 6), c(3, 5)),
              fma_cells("other", "S2", "P3", "native", 4, 5, 4))
  s <- fma_scores(eq, "forestmamba", c("S1", "S2"), n_boot = 200, seed = 1,
                  regions = list(R1 = "S1", R2 = "S2"))
  f1 <- function(TP, n_ref, tp_core, n_det) {
    r <- TP / n_ref; p <- tp_core / n_det; 2 * r * p / (r + p) }
  all <- s$long[s$long$scope == "five sites" & s$long$metric == "F1", ]
  fm <- all$estimate[all$detector == "forestmamba"]; ot <- all$estimate[all$detector == "other"]
  expect_equal(fm, f1(19, 30, 19, 26))
  expect_equal(ot, f1(12, 30, 12, 17))
  con <- s$contrasts[s$contrasts$scope == "five sites" & s$contrasts$metric == "F1", ]
  expect_identical(con$from, "other|native"); expect_identical(con$to, "forestmamba|native")
  expect_equal(con$estimate, fm - ot)
  expect_true(con$lower <= con$estimate && con$estimate <= con$upper)
  expect_setequal(unique(s$long$scope), c("five sites", "S1", "S2"))   # R1/R2 repeat S1/S2
})

test_that("stratum recall pools the classes' recovered true positives", {
  eq <- rbind(fma_cells("forestmamba", "S1", c("P1", "P2"), "native", c(4, 2), c(5, 5), c(4, 2)),
              fma_cells("other", "S1", c("P1", "P2"), "native", c(1, 3), c(5, 5), c(1, 3)))
  st <- fma_strata(eq, "forestmamba", n_boot = 100, seed = 2)
  dom <- st$long[st$long$stratum == "dominant", ]
  expect_equal(dom$estimate[dom$detector == "forestmamba"], (4 + 2) / 10)
  expect_equal(dom$estimate[dom$detector == "other"], (1 + 3) / 10)
  ov <- st$long[st$long$stratum == "overstory" & st$long$detector == "forestmamba", ]
  expect_equal(ov$estimate, (4 + 2) / 10)       # codominant has no stems here
  dc <- st$contrasts[st$contrasts$stratum == "dominant", ]
  expect_equal(dc$estimate, (6 - 4) / 10)
})

test_that("compute summarises cell receipts and driver phases per rung", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  put <- function(key, wall, infer) {
    jsonlite::write_json(list(seconds = wall), file.path(d, paste0(key, ".receipt.json")),
                         auto_unbox = TRUE)
    jsonlite::write_json(list(infer_seconds = infer, model_seconds = 9, points = 1000,
                              peak_cuda_allocated_bytes = 2^30),
                         file.path(d, paste0(key, ".laz.json")), auto_unbox = TRUE)
  }
  put("SOAP_031_native", 50, 37); put("SOAP_001_native", 30, 20); put("SOAP_031_1", 40, 31)
  cp <- fma_compute(d)
  expect_identical(cp$rung, c("all", "native", "1"))
  expect_equal(cp$cells, c(3L, 2L, 1L))
  expect_equal(cp$median_wall_s[cp$rung == "native"], 40)
  expect_equal(cp$median_infer_s[cp$rung == "1"], 31)
  expect_equal(cp$max_gpu_mib[1], 1024)
  expect_null(fma_compute(file.path(d, "none")))
})

test_that("repeat runs pool their shared cells and restate each arm contrast", {
  f1 <- function(TP, n_ref, tp_core, n_det) {
    r <- TP / n_ref; p <- tp_core / n_det; 2 * r * p / (r + p) }
  run1 <- fma_cells("forestmamba", "S1", c("P1", "P2"), "native", c(6, 4), c(8, 8), c(6, 4))
  run2 <- fma_cells("forestmamba", "S1", c("P1", "P2"), "native", c(5, 4), c(8, 7), c(5, 4))
  arms <- rbind(fma_cells("ff", "S1", c("P1", "P2"), "native", c(3, 5), c(6, 6), c(3, 5)),
                fma_cells("sat", "S1", c("P1", "P2"), "native", c(4, 4), c(5, 5), c(4, 4)))
  r <- fma_repeats(list(seed0 = run1, repeat1 = run2), arms)
  expect_identical(r$run, c("seed0", "repeat1"))
  expect_equal(r$cells, c(2L, 2L))
  expect_equal(r$F1[1], f1(10, 20, 10, 16))
  expect_equal(r$F1[2], f1(9, 20, 9, 15))
  expect_equal(r$d_F1_ff[2], f1(9, 20, 9, 15) - f1(8, 20, 8, 12))
  expect_equal(r$d_F1_sat[1], f1(10, 20, 10, 16) - f1(8, 20, 8, 10))
  short <- fma_repeats(list(seed0 = run1, repeat1 = run2[1, ]), arms)  # P2 missing once
  expect_equal(short$cells, c(1L, 1L))
  expect_equal(short$F1[1], f1(6, 10, 6, 8))
})

test_that("the chance null uses the paper's per-plot shifts and averages K draws", {
  source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
  stems <- data.frame(E = c(105, 112, 95), N = c(103, 92, 108), height = c(20, 18, 25),
                      crown_class = c("dominant", "intermediate", "codominant"))
  det <- data.frame(x = stems$E + .5, y = stems$N - .5, z = stems$height)
  cnt <- fma_null_counts(stems, det, 100, 100, 10, "S1", "S1_001", K = 5)
  expect_identical(cnt$variant, c("baseline", "null"))
  base <- score_plot(stems, det, tol_xy = 4, core_cx = 100, core_cy = 100, core_half = 10)
  expect_equal(cnt$TP[1], base$TP); expect_equal(cnt$n_det[1], base$n_det)
  expect_equal(c(cnt$n_over[1], cnt$tp_over[1], cnt$n_under[1], cnt$tp_under[1]), c(2, 2, 1, 1))
  one <- function(k) score_plot(stems, shift_detections(det, 100, 100, 14,
           null_offset(28, seed_for("S1", "S1_001", "null") + k, min_shift = 8)),
           tol_xy = 4, core_cx = 100, core_cy = 100, core_half = 10)$TP
  expect_equal(cnt$TP[2], mean(vapply(1:5, one, numeric(1))))
  expect_lt(cnt$TP[2], cnt$TP[1])
})

test_that("corrected F1 scales the excess over the null by the headroom", {
  cell <- function(variant, arm, plot, TP, n_det) data.frame(variant = variant, site = "S1",
    plot = plot, rung = "native", detector = arm, n_ref = 10, n_det = n_det, TP = TP,
    tp_core = TP, n_over = 10, tp_over = TP, n_under = 0, tp_under = 0)
  x <- rbind(cell("baseline", "forestmamba", c("P1", "P2"), c(6, 5), c(8, 8)),
             cell("null", "forestmamba", c("P1", "P2"), c(3, 2), c(8, 8)),
             cell("baseline", "ff", c("P1", "P2"), c(5, 5), c(9, 9)),
             cell("null", "ff", c("P1", "P2"), c(2, 2), c(9, 9)))
  r <- fma_corrected(x, "forestmamba", n_boot = 100, seed = 3)
  f1 <- function(TP, n_ref, n_det) { a <- TP / n_ref; b <- TP / n_det; 2 * a * b / (a + b) }
  k <- function(o, n) (o - n) / (1 - n)
  fm <- k(f1(11, 20, 16), f1(5, 20, 16)); ff <- k(f1(10, 20, 18), f1(4, 20, 18))
  expect_equal(r$scores$estimate[r$scores$detector == "forestmamba"], fm)
  expect_equal(r$scores$estimate[r$scores$detector == "ff"], ff)
  expect_equal(r$contrasts$estimate, fm - ff)
  expect_identical(r$contrasts$from, "ff|native")
})

test_that("count checks catch a differing or a missing cell", {
  a <- data.frame(site = "S1", plot = c("P1", "P2"), rung = "native", n_ref = 10,
                  n_det = c(5, 6), TP = c(3, 4), stringsAsFactors = FALSE)
  b <- a; b$TP[2] <- 5
  expect_equal(nrow(fma_count_mismatch(a, a)), 0L)
  expect_identical(fma_count_mismatch(a, b)$plot, "P2")
  expect_identical(fma_count_mismatch(a, a[1, ])$plot, "P2")
})

test_that("masks pool the harness rows of every model on their shared cells", {
  d <- tempfile(); on.exit(unlink(d, recursive = TRUE))
  put <- function(job, rows) {
    nd <- file.path(d, job, "neon", "S1"); dir.create(nd, recursive = TRUE, showWarnings = FALSE)
    write.csv(rows, file.path(nd, "instance_iou_pq.csv"), row.names = FALSE)
  }
  row <- function(model, plot, TP, FP, FN, sum_iou, source = "native")
    data.frame(site = "S1", plot = plot, rung = "native", model = model,
               mask_source = source, n_pred = TP + FP, n_ref = TP + FN, TP = TP, FP = FP,
               FN = FN, sum_iou = sum_iou, sum_maxiou = sum_iou + 1)
  put("runs", rbind(row("forestmamba", c("P1", "P2"), c(3, 2), c(2, 1), c(1, 2), c(2.1, 1.4))))
  put("base", rbind(row("forestformer3d", c("P1", "P2", "P3"), c(2, 2, 5), c(1, 1, 0), c(2, 2, 0),
                        c(1.2, 1.2, 4)),
                    row("forestformer3d", "P1", 9, 0, 0, 9, source = "voronoi_apex")))
  m <- fma_masks(file.path(d, "runs"), file.path(d, "base"), "S1", "forestformer3d",
                 c("S1::P1::native", "S1::P2::native", "S1::P3::native"))
  fm <- m[m$model == "forestmamba", ]; ff <- m[m$model == "forestformer3d", ]
  expect_equal(c(fm$n_cells, ff$n_cells), c(2L, 2L))      # P3 lacks ForestMamba
  expect_equal(fm$F1, 2 * 5 / (2 * 5 + 3 + 3))            # TP 5, FP 3, FN 3
  expect_equal(ff$TP, 4)                                  # the apex proxy row is ignored
  expect_equal(fm$SQ, 3.5 / 5)
})

test_that("a cell without core detections counts zero true positives everywhere", {
  run <- fma_cells("forestmamba", "S1", c("P1", "P2"), "1", c(4, 3), c(6, 5), c(4, 3))
  arm <- fma_cells("sat", "S1", c("P1", "P2"), "1", c(0, 2), c(0, 4), c(NA, 2))
  arm$precision[1] <- NA                              # the sweeps write NA when n_det = 0
  r <- fma_repeats(list(seed0 = run), arm)
  p <- 2 / 4; rc <- 2 / 20
  expect_equal(r$d_F1_sat, r$F1 - 2 * p * rc / (p + rc))
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  root <- fma_root(d); id <- frozen_root_id(root)
  nd <- file.path(d, "job", "neon", "S1"); dir.create(nd, recursive = TRUE)
  write.csv(arm, file.path(nd, "forestmamba_results.csv"), row.names = FALSE)
  jsonlite::write_json(list(clip_manifest_sha256 = id, population = "adopted"),
                       file.path(nd, "forestmamba_results.csv.frozen"), auto_unbox = TRUE)
  spec <- FMA_FOCUS; spec$detector <- "sat"
  got <- fma_arm_rows(file.path(d, "job"), "S1", spec, root, id, "adopted",
                      c("S1::P1::1", "S1::P2::1"), c("S1::P1" = 10L, "S1::P2" = 10L))
  expect_identical(got$rows$tp_core, c(0, 2))
})

test_that("the rungs default to the sealed root's and must be among them", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  root <- fma_root(d)
  expect_identical(fma_rungs(NULL, root), MT_RUNGS)        # no contract: the ladder rungs
  jsonlite::write_json(list(rungs = 3.2), file.path(root, "freeze_contract.json"))
  expect_identical(fma_rungs(NULL, root), c("native", "3.2"))
  expect_identical(fma_rungs("3.2", root), "3.2")
  expect_identical(fma_rungs("native,3.2", root), c("native", "3.2"))
  expect_error(fma_rungs("8", root), "not a rung of")
})

test_that("tables follow the analysed rungs, with sites and strata at the end rungs", {
  cells <- function(r) rbind(
    fma_cells("forestmamba", "S1", c("P1", "P2"), r, c(6, 4), c(8, 8), c(6, 4)),
    fma_cells("other", "S1", c("P1", "P2"), r, c(3, 5), c(6, 6), c(3, 5)))
  md <- function(eq, rungs) {
    sc <- fma_scores(eq, "forestmamba", "S1", n_boot = 50, seed = 1, regions = list())
    st <- fma_strata(eq, "forestmamba", n_boot = 50, seed = 1)
    fma_tables(sc$long, sc$contrasts, st$long, st$contrasts, NULL, NULL, "other",
               "forestmamba", rungs)
  }
  q <- md(cells("3.2"), "3.2")
  expect_true(all(c("F1 per site at rung 3.2:",
                    "Recall by stratum at rung 3.2, five sites:") %in% q))
  expect_false(any(grepl("Change in F1 from native", q)))
  l <- md(rbind(cells("native"), cells("4"), cells("1")), c("native", "4", "1"))
  expect_true(all(c("F1 per site at rung native:", "F1 per site at rung 1:") %in% l))
  expect_false("F1 per site at rung 4:" %in% l)
})

test_that("semantics pool the driver's label counts and instances per rung", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  put <- function(key, sem, inst, bg, noise = 0) {
    jsonlite::write_json(list(seconds = 1), file.path(d, paste0(key, ".receipt.json")),
                         auto_unbox = TRUE)
    jsonlite::write_json(list(points = sum(unlist(sem)), semantic_counts = sem,
                              instances = inst, background = bg,
                              noise_rows_excluded = noise),
                         file.path(d, paste0(key, ".laz.json")), auto_unbox = TRUE)
  }
  # Excluded noise rows are exported as background but were never labelled.
  put("S1_P1_native", list(`0` = 50, `1` = 10, `2` = 40), 5, 62, noise = 2)
  put("S1_P2_native", list(`0` = 30, `1` = 10, `2` = 60), 9, 40)
  put("S1_P1_1", list(`0` = 20, `1` = 80), 30, 25)                # no leaf label at all
  put("S1_P1_3.2", list(`0` = 10, `1` = 5, `2` = 5), 2, 12)
  s <- fma_semantics(d)
  expect_identical(s$rung, c("native", "3.2", "1"))
  expect_equal(s$cells, c(2L, 1L, 1L))
  expect_equal(s$ground[1], 80 / 200)
  expect_equal(s$wood[1], 20 / 200)
  expect_equal(s$leaf[3], 0)
  expect_equal(s$wood_of_vegetation[3], 1)
  expect_equal(s$unassigned[1], 100 / 200)
  expect_equal(s$median_instances[1], 7)
  expect_null(fma_semantics(file.path(d, "none")))
})

test_that("the label table gives each rung's shares in percent", {
  eq <- rbind(fma_cells("forestmamba", "S1", c("P1", "P2"), "native", c(6, 4), c(8, 8), c(6, 4)),
              fma_cells("other", "S1", c("P1", "P2"), "native", c(3, 5), c(6, 6), c(3, 5)))
  sc <- fma_scores(eq, "forestmamba", "S1", n_boot = 20, seed = 1, regions = list())
  st <- fma_strata(eq, "forestmamba", n_boot = 20, seed = 1)
  sm <- data.frame(rung = c("native", "1"), cells = c(2L, 1L), ground = c(.4, .2),
                   wood = c(.1, .8), leaf = c(.5, 0), wood_of_vegetation = c(1 / 6, 1),
                   unassigned = c(.5, .25), median_instances = c(7, 30))
  md <- fma_tables(sc$long, sc$contrasts, st$long, st$contrasts, NULL, NULL, "other",
                   "forestmamba", "native", semantics = sm)
  expect_true("| native | 2 | 40.0 | 10.0 | 50.0 | 16.7 | 50.0 | 7 |" %in% md)
  expect_true("| 1 | 1 | 20.0 | 80.0 | 0.0 | 100.0 | 25.0 | 30 |" %in% md)
})

test_that("censused scores pool the shared admitted cells and refuse mixed support", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  cen <- function(arm, plots, TP, n_det, tp_core) {
    x <- fma_cells(arm, "S1", plots, "native", TP, n_det, tp_core)
    x$support_id <- paste0("bundle_", plots); x$support_policy <- "subplot_exclusion"
    x$reference_population <- "adopted"; x
  }
  fm <- cen("forestmamba", c("P1", "P2"), c(6, 4), c(8, 8), c(6, 4))
  ot <- rbind(cen("other", c("P1", "P2", "P3"), c(3, 5, 2), c(6, 6, 4), c(3, 5, 2)),
              cen("unused", "P1", 1, 1, 1))
  write.csv(fm, file.path(d, "fm.csv"), row.names = FALSE)
  put_base <- function(x) write.csv(x, file.path(d, "base.csv"), row.names = FALSE)
  put_base(ot)
  s <- fma_census(file.path(d, "fm.csv"), file.path(d, "base.csv"), "other", "forestmamba",
                  n_boot = 50, seed = 1)
  f1 <- s$long[s$long$metric == "F1", ]
  expect_true(all(f1$scope == "five sites"))
  expect_setequal(f1$detector, c("forestmamba", "other"))
  expect_equal(f1$estimate[f1$detector == "other"], 0.5)        # P1 and P2 only
  con <- s$contrasts[s$contrasts$metric == "F1", ]
  expect_equal(con$estimate, f1$estimate[f1$detector == "forestmamba"] - 0.5)
  eq <- s$cells[s$cells$detector %in% c("forestmamba", "other"), ]
  sc <- fma_scores(eq, "forestmamba", "S1", n_boot = 20, seed = 1, regions = list())
  st <- fma_strata(eq, "forestmamba", n_boot = 20, seed = 1)
  md <- fma_tables(sc$long, sc$contrasts, st$long, st$contrasts, NULL, NULL, "other",
                   "forestmamba", "native", census = s)
  one <- fma_census(file.path(d, "fm.csv"), file.path(d, "base.csv"), "other", "forestmamba",
                    n_boot = 50, seed = 1, keys = "S1::P1::native")   # the declared cells only
  expect_setequal(paste(one$cells$plot, one$cells$detector),
                  c("P1 forestmamba", "P1 other"))
  i <- match("Censused F1 inside the admitted subplots, 2 plots:", md)
  expect_false(is.na(i))                     # heading, blank, header, rule, then the arms
  expect_true(startsWith(md[i + 5], "| other | 0.500 ["))
  ot$support_id[ot$detector == "other" & ot$plot == "P1"] <- "another_bundle"
  put_base(ot)
  expect_error(fma_census(file.path(d, "fm.csv"), file.path(d, "base.csv"), "other",
                          "forestmamba", n_boot = 50, seed = 1),
               "Different reference support")
})

test_that("detections per reference stem pool summed counts per arm and rung", {
  eq <- rbind(fma_cells("forestmamba", "S1", c("P1", "P2"), "native", c(6, 4), c(8, 12), c(6, 4)),
              fma_cells("forestmamba", "S1", c("P1", "P2"), "1", c(6, 4), c(30, 10), c(6, 4)),
              fma_cells("other", "S1", c("P1", "P2"), "native", c(3, 5), c(6, 6), c(3, 5)))
  r <- fma_detection_ratio(eq)
  expect_equal(r$per_stem[r$detector == "forestmamba" & r$rung == "native"], 20 / 20)
  expect_equal(r$per_stem[r$detector == "forestmamba" & r$rung == "1"], 40 / 20)
  expect_equal(r$per_stem[r$detector == "other"], 12 / 20)
  md <- fma_ratio_table(r, "other", "forestmamba", c("native", "1"))
  expect_identical(md[1], "Core detections per reference stem, five sites:")
  expect_true("| forestmamba | 1.00 | 2.00 |" %in% md)
  expect_true("| other | 0.60 | — |" %in% md)
})

test_that("the report carries the detection ratio and prints undefined mask scores as a dash", {
  eq <- rbind(fma_cells("forestmamba", "S1", c("P1", "P2"), "native", c(6, 4), c(8, 8), c(6, 4)),
              fma_cells("other", "S1", c("P1", "P2"), "native", c(3, 5), c(6, 6), c(3, 5)))
  sc <- fma_scores(eq, "forestmamba", "S1", n_boot = 20, seed = 1, regions = list())
  st <- fma_strata(eq, "forestmamba", n_boot = 20, seed = 1)
  mk <- data.frame(model = c("forestmamba", "other"), rung = "native", F1 = c(0.2, NA),
                   PQ = c(0.1, 0), coverage = c(0.3, 0.01))
  md <- fma_tables(sc$long, sc$contrasts, st$long, st$contrasts, NULL, NULL, "other",
                   "forestmamba", "native", masks = mk, ratio = fma_detection_ratio(eq))
  expect_true("Core detections per reference stem, five sites:" %in% md)
  i <- match("Point-mask F1 against the Voronoi-on-stems proxy, five sites:", md)
  expect_identical(md[i + 5], "| other | — |")
})

test_that("pulse density per rung is the median over the declared cells", {
  cm <- data.frame(site = "S1", plot = c("P1", "P2", "P3", "P1"),
                   rung = c("native", "native", "native", "1"), frdens = c(8, 10, 30, 0.6))
  p <- fma_pulses(cm, c("S1::P1::native", "S1::P2::native", "S1::P1::1"))
  expect_equal(p[["native"]], 9)
  expect_equal(p[["1"]], 0.6)
})

test_that("the figure data join scores, corrected F1 and each rung's pulse density", {
  long <- data.frame(scope = c("five sites", "five sites", "S1"), detector = "forestmamba",
                     rung = c("native", "1", "native"), metric = "F1",
                     estimate = c(.5, .4, .6), lower = c(.45, .35, .5), upper = c(.55, .45, .7))
  cor <- data.frame(detector = "forestmamba", rung = "native", estimate = .2, lower = -.1,
                    upper = .3)
  x <- fma_figure_data(long, cor, c(native = 9.8, `1` = 0.6))
  expect_equal(nrow(x), 3L)                                   # the site scope is left out
  expect_equal(x$pulses[x$metric == "F1" & x$rung == "1"], 0.6)
  expect_equal(x$estimate[x$metric == "F1_corrected"], .2)
  f <- tempfile(fileext = ".png"); on.exit(unlink(f))
  fma_figure(x, f)                                            # recall and precision absent
  expect_gt(file.size(f), 0)
})

test_that("stratum recall above the null is the pooled difference, with paired contrasts", {
  cell <- function(variant, arm, plot, tp_under, tp_over) data.frame(variant = variant,
    site = "S1", plot = plot, rung = "native", detector = arm, n_ref = 10, n_det = 8, TP = 5,
    tp_core = 5, n_over = 6, tp_over = tp_over, n_under = 4, tp_under = tp_under)
  x <- rbind(cell("baseline", "forestmamba", c("P1", "P2"), c(3, 2), c(4, 4)),
             cell("null", "forestmamba", c("P1", "P2"), c(1, 1.5), c(2, 3)),
             cell("baseline", "ff", c("P1", "P2"), c(2, 2), c(5, 4)),
             cell("null", "ff", c("P1", "P2"), c(1, 1), c(3, 3)))
  r <- fma_null_strata(x, "forestmamba", n_boot = 100, seed = 3)
  u <- r$scores[r$scores$stratum == "understory", ]
  expect_equal(u$recall[u$detector == "forestmamba"], 5 / 8)
  expect_equal(u$null_recall[u$detector == "forestmamba"], 2.5 / 8)
  expect_equal(u$estimate[u$detector == "forestmamba"], (5 - 2.5) / 8)
  expect_equal(u$scaled[u$detector == "ff"], (4 / 8 - 2 / 8) / (1 - 2 / 8))
  o <- r$contrasts[r$contrasts$stratum == "overstory", ]
  expect_equal(o$estimate, (8 - 5) / 12 - (9 - 6) / 12)
  expect_identical(o$from, "ff|native")
  expect_true(all(r$scores$lower <= r$scores$estimate & r$scores$estimate <= r$scores$upper))
  eq <- rbind(fma_cells("forestmamba", "S1", c("P1", "P2"), "native", c(6, 4), c(8, 8), c(6, 4)),
              fma_cells("ff", "S1", c("P1", "P2"), "native", c(3, 5), c(6, 6), c(3, 5)))
  sc <- fma_scores(eq, "forestmamba", "S1", n_boot = 20, seed = 1, regions = list())
  st <- fma_strata(eq, "forestmamba", n_boot = 20, seed = 1)
  md <- fma_tables(sc$long, sc$contrasts, st$long, st$contrasts, NULL, NULL, "ff",
                   "forestmamba", "native", null_strata = r)
  i <- match("Recall above the chance null at rung native, five sites:", md)
  expect_false(is.na(i))
  expect_identical(md[i + 2], "| Arm | Overstory | Understory | Understory, scaled |")
  expect_true(startsWith(md[i + 4], "| forestmamba | +0.250 ["))   # an excess, signed
  j <- match("ForestMamba minus arm, recall above the chance null at rung native:", md)
  expect_true(startsWith(md[j + 4], "| ff | +0.000 ["))
})

test_that("values that round to zero print without a minus sign", {
  expect_identical(fma_fmt(-5.6e-17, -1e-4, 0.2, signed = TRUE), "+0.000 [+0.000, +0.200]")
  expect_identical(fma_fmt(-0.0123, -0.05, 0.01, signed = TRUE), "−0.012 [−0.050, +0.010]")
  expect_identical(fma_fmt(NA, NA, NA), "—")
  expect_identical(fma_num(c(-4e-17, -0.0204, NA), signed = TRUE), c("+0.000", "\u22120.020", "—"))
})
