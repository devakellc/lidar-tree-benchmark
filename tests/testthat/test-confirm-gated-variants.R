# Unit tests for the gated multichm confirmation checks R3 (scoring variants,
# confirm_gated_scoring_variants.R) and R5 (the peaks the share gate removes,
# confirm_gated_removed_peaks.R). Sourcing a script defines its helpers without
# running it (guarded by `if (sys.nframe() == 0L) run_main()`). Synthetic
# stems, detections, candidates and supports only: no LiDAR, no NEON data.
source(file.path("..", "..", "scripts", "confirm_gated_scoring_variants.R"), local = TRUE)
source(file.path("..", "..", "scripts", "confirm_gated_removed_peaks.R"), local = TRUE)

## ---- synthetic inputs -----------------------------------------------------------------------
syn_stems <- function() data.frame(
  individualID = sprintf("i%02d", 1:6), plotID = "P1",
  E = c(0, 5, -6, 8, -3, 1), N = c(0, 4, 3, -7, -8, 9),
  height = c(20, 18, 12, 25, 8, 15),
  crown_class = c("dominant", "codominant", "intermediate", "dominant", "suppressed",
                  "codominant"),
  pos_unc = c(0.5, 1, 0.8, NA, 0.6, 1.2), maxCrownDiameter = c(6, 4, 3, 30, NA, 5),
  meas_year = c(2021, 2020, 2021, 2019, NA, 2021), stringsAsFactors = FALSE)
syn_det <- function(dx = 0) data.frame(x = c(0.5, 5.5, -5, 11, 2, -9) + dx,
                                       y = c(0.3, 3.5, 2.5, -6, 9.5, -9),
                                       z = c(19, 17, 11, 24, 14, 7))
syn_job <- function() list(site = "SJER", plot = "P1", cx = 0, cy = 0, half = 10,
                           stems = syn_stems(), stems_cells = syn_stems())
counts_of <- function(stems, det, keep = CGV_COUNTS, ...)
  unname(.mcg_counts(score_plot(stems, det, core_cx = 0, core_cy = 0, core_half = 10, ...))[keep])

# Per-plot rows of the five configurations: counts chosen so the pooled rates
# are known.
syn_rows <- function(sites = c("SJER", "WREF"), n = 4) {
  out <- list()
  for (s in sites) for (i in seq_len(n)) for (k in seq_along(CGV_CONFIGS)) {
    out[[length(out) + 1L]] <- data.frame(
      variant = "baseline", site = s, plot = sprintf("%s_%02d", s, i), config = CGV_CONFIGS[[k]],
      n_ref = 20 + i, n_over = 12, n_under = 8 + i, n_det = 18 + k + i %% 2, TP = 8 + k + i %% 3,
      tp_core = 7 + k, tp_over = 6, tp_under = 2, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

## ---- R3: arguments and configurations -------------------------------------------------------
test_that("variant arguments parse as KEY=VALUE with defaults, and OUT stays out of the inputs", {
  S <- cgv_settings(character(), d = tempdir())
  expect_identical(c(S$K, S$N_BOOT, S$CORES), c(200L, 1000L, 4L))
  expect_identical(S$SITES, c("SJER", "SOAP", "TEAK", "WREF", "ABBY"))
  expect_identical(S$POP, "adopted")
  expect_identical(S$OUT, file.path(tempdir(), "variants"))
  S <- cgv_settings(c("K=7", "SITES=SJER,WREF", "N_BOOT=50", "OUT=/tmp/x=y"), d = tempdir())
  expect_identical(c(S$K, S$N_BOOT), c(7L, 50L))
  expect_identical(S$SITES, c("SJER", "WREF"))
  expect_identical(S$OUT, "/tmp/x=y")
  expect_error(cgv_settings("K=0", d = tempdir()), "positive")
  expect_error(cgv_settings("SITES=HARV", d = tempdir()), "SITES")
  expect_error(cgv_settings(c("BASE=/a/b", "OUT=/a/b/c"), d = tempdir()), "read-only")
  expect_error(cgv_settings(c("CANDIDATES=/a/b", "OUT=/a/b"), d = tempdir()), "read-only")
})

test_that("the five configurations are the grid's, and the declared one is MCG_DECLARED", {
  cfgs <- cgv_configs()
  expect_identical(names(cfgs), unname(CGV_CONFIGS))
  expect_identical(unname(vapply(cfgs, mcg_config_label, "")), unname(CGV_CONFIGS))
  expect_identical(cfgs[[CGV_CONFIGS[["declared"]]]], MCG_DECLARED)
  expect_identical(cfgs[["stock"]], MCG_STOCK)
  expect_identical(mcg_config_label(CGR_CONFIG), CGR_LABEL)
  expect_identical(CGR_LABEL, CGV_CONFIGS[["floor_exempt"]])
  expect_identical(CGR_SHARE_MIN, 0.75)
})

## ---- R3: scoring ----------------------------------------------------------------------------
test_that("every variant scores a cell with the benchmark's scorer and matchers", {
  j <- syn_job(); st <- j$stems; d1 <- syn_det(); d2 <- syn_det()[-2, ]
  dets <- list(stock = d1, z5_s0_c0_e0 = d1, z5_s0.75_c0.6_e1_d8 = d2)
  r <- cgv_score_cell(j, dets, K = 3)
  rows <- r$rows
  expect_setequal(unique(rows$variant),
                  c(vapply(CGV_VARIANTS, `[[`, "", "name"), "baseline_cells", "exact2021"))
  expect_equal(nrow(rows), 3 * (length(CGV_VARIANTS) + 2))
  get <- function(v, cfg) unname(unlist(rows[rows$variant == v & rows$config == cfg, CGV_COUNTS]))
  tol <- match_tol(st$maxCrownDiameter, st$pos_unc, base_tol = 4, k = 1, tol_cap = 12)
  expect_equal(max(tol), 12)                                   # the cap clips the 30 m crown
  expect_equal(get("baseline", "stock"), counts_of(st, d1))
  expect_equal(get("optimal", "stock"), counts_of(st, d1, method = "optimal"))
  expect_equal(get("scaled", "stock"), counts_of(st, d1, tol_xy = tol))
  expect_equal(get("optimal_scaled", "z5_s0.75_c0.6_e1_d8"),
               counts_of(st, d2, tol_xy = tol, method = "optimal"))
  expect_equal(get("soft3d", "stock"),
               counts_of(st, d1, method = "optimal", lambda = 0.5))
  expect_equal(get("grid_tx2_tz8", "stock"), counts_of(st, d1, tol_xy = 2))
  expect_equal(get("grid_tx5_tz8", "z5_s0.75_c0.6_e1_d8"),
               counts_of(st, d2, tol_xy = 5))
  st21 <- st[st$meas_year %in% 2021, ]
  expect_equal(get("exact2021", "stock"), counts_of(st21, d1))
  expect_equal(get("exact2021", "stock")[1], 3)                # n_ref
  # identical detection sets give identical rows
  expect_identical(get("soft3d", "stock"), get("soft3d", "z5_s0_c0_e0"))
  # jitter: draw k moves the stems with seed seed_for(site, plot, "native") + k
  jt <- r$jitter
  expect_equal(nrow(jt), 3 * 3)
  p <- perturb_positions(st$E, st$N, st$pos_unc, seed_for("SJER", "P1", "native") + 2)
  s2 <- st; s2$E <- p$E; s2$N <- p$N
  expect_equal(unname(unlist(jt[jt$draw == 2 & jt$config == "z5_s0.75_c0.6_e1_d8",
                                CGV_JITTER_COUNTS])),
               counts_of(s2, d2, keep = CGV_JITTER_COUNTS))
  expect_equal(unname(as.matrix(jt[jt$config == "stock", CGV_JITTER_COUNTS])),
               unname(as.matrix(jt[jt$config == "z5_s0_c0_e0", CGV_JITTER_COUNTS])))
})

test_that("a cell without 2021 stems has no exact2021 rows", {
  j <- syn_job(); j$stems$meas_year <- 2019
  r <- cgv_score_cell(j, list(stock = syn_det()), K = 1)
  expect_false("exact2021" %in% r$rows$variant)
})

test_that("the reproduction check needs every cell on both sides with equal counts", {
  b <- syn_rows()
  cells <- b[c("site", "plot", "config", CGV_CHECK_COLS)]
  expect_true(attr(cgv_baseline_check(b, cells), "ok"))
  c2 <- cells; c2$TP[3] <- c2$TP[3] + 1
  k <- cgv_baseline_check(b, c2)
  expect_false(attr(k, "ok"))
  expect_equal(sum(!k$same), 1)
  expect_false(attr(cgv_baseline_check(b, cells[-1, ]), "ok"))
  expect_false(attr(cgv_baseline_check(b[-1, ], cells), "ok"))
  expect_error(cgv_baseline_check(rbind(b, b[1, ]), cells), "duplicate")
})

## ---- R3: pooling ------------------------------------------------------------------------------
test_that("pooled scores sum counts and contrasts are mcg_contrast on the same draws", {
  rows <- syn_rows()
  sc <- cgv_scopes(c("SJER", "WREF"))
  expect_identical(names(sc), c("Five sites", "California", "Washington"))
  expect_identical(sc$California, "SJER")
  r <- cgv_pool_variant(rows, "baseline", sc, n_boot = 40)
  p <- r$pooled[r$pooled$scope == "Five sites" & r$pooled$config == "stock", ]
  x <- rows[rows$config == "stock", ]
  rec <- sum(x$TP) / sum(x$n_ref); pre <- sum(x$tp_core) / sum(x$n_det)
  expect_equal(p$estimate[p$metric == "recall"], rec)
  expect_equal(p$estimate[p$metric == "precision"], pre)
  expect_equal(p$estimate[p$metric == "F1"], 2 * rec * pre / (rec + pre))
  expect_equal(unique(p$n_plots), 8)
  ct <- r$contrasts[r$contrasts$scope == "Washington" &
                      r$contrasts$contrast == "declared_minus_stock", ]
  ids <- unique(cgv_ids(rows[rows$site == "WREF", ]))
  ref <- mcg_contrast(cgv_with_null(rows[rows$site == "WREF", ]), ids, CGV_CONFIGS[["declared"]],
                      "stock", n_boot = 40, metrics = c("F1", "precision", "recall"))
  expect_equal(ct$difference, ref$difference)
  expect_equal(ct$lower, ref$lower)
  expect_equal(ct$upper, ref$upper)
  f <- function(cfg, m) r$pooled$estimate[r$pooled$scope == "Washington" &
                                            r$pooled$config == cfg & r$pooled$metric == m]
  expect_equal(ct$difference[ct$metric == "F1"], f(CGV_CONFIGS[["declared"]], "F1") -
                 f("stock", "F1"))
  expect_setequal(unique(r$contrasts$contrast),
                  vapply(CGV_CONTRASTS, paste, "", collapse = "_minus_"))
  # every configuration must cover the same plots
  expect_error(cgv_pool_variant(rows[-1, ], "baseline", sc, n_boot = 10), "cover")
})

test_that("jitter bands are percentiles over draws of pooled scores and of contrasts", {
  set.seed(3)
  jit <- do.call(rbind, lapply(1:20, function(k) {
    r <- syn_rows(); r$draw <- k; r$TP <- r$TP + (k %% 4); r }))
  b <- cgv_jitter_bands(jit, cgv_scopes(c("SJER", "WREF")))
  x <- data.table::as.data.table(jit)[config == "stock", list(TP = sum(TP), n_ref = sum(n_ref),
                                                             tp = sum(tp_core), nd = sum(n_det)),
                                     by = "draw"]
  f1 <- with(x, { r <- TP / n_ref; p <- tp / nd; 2 * r * p / (r + p) })
  got <- b$bands[b$bands$scope == "Five sites" & b$bands$config == "stock", ]
  expect_equal(c(got$F1_p05, got$F1_p50, got$F1_p95),
               unname(quantile(f1, c(0.05, 0.5, 0.95), type = 7)))
  expect_equal(got$draws, 20)
  d <- b$contrasts[b$contrasts$scope == "Five sites" & b$contrasts$contrast ==
                     "declared_minus_stock", ]
  y <- data.table::as.data.table(jit)[config == CGV_CONFIGS[["declared"]],
                                     list(TP = sum(TP), n_ref = sum(n_ref), tp = sum(tp_core),
                                          nd = sum(n_det)), by = "draw"]
  f1d <- with(y, { r <- TP / n_ref; p <- tp / nd; 2 * r * p / (r + p) })
  expect_equal(d$F1_p50, unname(median(f1d - f1)))
})

test_that("Markdown rows join cells, and signed values use a minus sign", {
  expect_identical(cgv_md_row("a", c("b", "c")), "| a | b | c |")
  expect_identical(cgv_s3(c(-0.0123, 0.5)), c("−0.012", "+0.500"))
  expect_identical(cgv_iv(0.1, -0.2, 0.3, cgv_f3), "0.100 [-0.200, 0.300]")
})

## ---- R5: labels -------------------------------------------------------------------------------
syn_cand <- function() data.frame(
  X = c(1, 2, 3, 4, 5, 6), Y = c(1, 2, 3, 4, 5, 6), Z = c(30, 25, 20, 15, 12, 9),
  layer = c(1L, 2L, 3L, 2L, 1L, 4L), share = c(0.2, 0.75, 0.74, NA, 1, 0.9))

test_that("each detection takes its candidate's layer and share by exact (X, Y)", {
  cand <- syn_cand()
  det <- data.frame(x = cand$X[c(5, 2, 3, 4, 1, 6)], y = cand$Y[c(5, 2, 3, 4, 1, 6)],
                    z = cand$Z[c(5, 2, 3, 4, 1, 6)])
  lab <- cgr_label_detections(det, cand)
  expect_identical(lab$layer, cand$layer[c(5, 2, 3, 4, 1, 6)])
  expect_identical(lab$class, c("surface", "deeper_kept", "deeper_removed", "deeper_removed",
                                "surface", "deeper_kept"))
  expect_identical(lab[c("x", "y", "z")], det)
  expect_equal(nrow(cgr_label_detections(det[0, ], cand)), 0)
  expect_error(cgr_label_detections(data.frame(x = 1.5, y = 1, z = 30), cand), "no single")
  expect_error(cgr_label_detections(data.frame(x = 1, y = 1, z = 31), cand), "z differs")
  dup <- rbind(cand, cand[1, ])
  expect_error(cgr_label_detections(det, dup), "no single")
})

test_that("labels follow the share threshold the gate uses", {
  cand <- syn_cand()
  det <- data.frame(x = cand$X, y = cand$Y, z = cand$Z)
  lab <- cgr_label_detections(det, cand, min_share = 0.75)
  g <- mcg_gate(cand, cover = 0.9, cfg = MCG_DECLARED, crown_spacing = 9)
  # in a gated stand the gate keeps exactly the surface and deeper_kept peaks
  # above the floor
  above <- cand$layer == 1L | cand$Z >= MCG_DECLARED$zmin
  expect_identical(g$keep[above], (lab$class != "deeper_removed")[above])
})

## ---- R5: the censused match -------------------------------------------------------------------
syn_support <- function() {
  core <- sf::st_sfc(sf::st_polygon(list(rbind(c(0, 0), c(20, 0), c(20, 20), c(0, 20),
                                               c(0, 0)))), crs = 32611)
  refs <- data.frame(E = c(5, 10, 15, 3, 18, 30), N = c(5, 12, 4, 17, 18, 30),
                     height = c(20, 15, NA, 10, 25, 20),
                     crown_class = c("dominant", "codominant", "intermediate", "suppressed",
                                     "dominant", "dominant"),
                     epsg = 32611, reference_selected = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
                     stringsAsFactors = FALSE)
  list(evaluation_ready = TRUE, blockers = character(), references = refs, core = core,
       epsg = 32611, policy = "synthetic", population = "synthetic", interior_area_m2 = 400)
}
syn_labelled <- function() data.frame(
  x = c(5.5, 10.4, 14, 3.2, 21, 18.5, -2, 40, 9, 16),
  y = c(5.2, 11, 4.5, 16.5, 10, 21.5, 5, 40, 9, 16),
  z = c(19, 14, 9, 9.5, 18, 24, 12, 20, 6, 30),
  class = c("surface", "deeper_kept", "deeper_removed", "surface", "surface", "deeper_kept",
            "deeper_removed", "surface", "deeper_removed", "surface"),
  stringsAsFactors = FALSE)

test_that("the labelled match repeats score_neon_support's counts", {
  sup <- syn_support(); det <- syn_labelled()
  sc <- score_neon_support(sup, det[c("x", "y", "z")], det_epsg = 32611, tol_xy = 4)
  r <- cgr_match_labels(sup, det, tol = 4)
  expect_true(cgr_same_counts(r, sc))
  expect_equal(r$n_ref, 5)
  expect_equal(sum(r$det$matched), r$TP)          # one detection per matched stem
  cc <- cgr_class_counts(r$det)
  expect_identical(cc$class, CGR_CLASSES)
  expect_equal(sum(cc$n_in), sc$n_det)
  expect_equal(sum(cc$n_match), sc$tp_core)
  # a precomputed region gives the same result
  r2 <- cgr_match_labels(sup, det, tol = 4, region = sf::st_buffer(sup$core, 4))
  expect_identical(r2$det, r$det)
  # shifted copies keep their labels and still repeat the scorer
  for (k in 1:5) {
    sd <- shift_detections(det, 10, 10, 14, null_offset(28, 100 + k))
    expect_identical(sort(sd$class), sort(det$class[abs(det$x - 10) <= 14 &
                                                      abs(det$y - 10) <= 14]))
    rk <- cgr_match_labels(sup, sd, tol = 4)
    expect_true(cgr_same_counts(rk, score_neon_support(sup, sd[c("x", "y", "z")],
                                                       det_epsg = 32611, tol_xy = 4)))
  }
})

## ---- R5: scopes and pooling -------------------------------------------------------------------
test_that("height bands and the declared configuration's gated plots", {
  expect_identical(cgr_height_band(c(29.99, 30, 44.9, 45, NA)),
                   c("under 30 m", "30 to 45 m", "30 to 45 m", "45 m and over", NA))
  plots <- data.frame(site = c("SJER", "WREF", "WREF", "ABBY", "ABBY"),
                      plot = c("S1", "W1", "W2", "A1", "A2"),
                      cover = c(0.4, 0.9, 0.95, 0.6, 0.59),
                      crown_spacing = c(12, 8, 7.99, 9, 10),
                      top_height = c(20, 50, 35, 29, 31), stringsAsFactors = FALSE)
  s <- cgr_scopes(plots)
  expect_identical(s$`Gated (closed, crown spacing >= 8 m)`, c("WREF::W1", "ABBY::A1"))
  expect_identical(s$`Closed, not gated`, "WREF::W2")
  expect_identical(s$Open, c("SJER::S1", "ABBY::A2"))
  expect_identical(s$California, "SJER::S1")
  expect_identical(s$`Top height 45 m and over`, "WREF::W1")
  expect_identical(s$`Top height under 30 m`, c("SJER::S1", "ABBY::A1"))
})

test_that("matched share, null and excess pool summed counts per class", {
  r <- cgr_rates(c(10, 0, 5), c(6, 0, 5), c(8, 4, 2), c(2, 1, 2))
  expect_equal(r$share, c(0.6, NA, 1))
  expect_equal(r$null, c(0.25, 0.25, 1))
  expect_equal(r$excess, c((0.6 - 0.25) / 0.75, NA, NA))
  pc <- do.call(rbind, lapply(c("SJER", "WREF"), function(s) do.call(rbind, lapply(1:3,
    function(i) data.frame(site = s, plot = paste0(s, i), class = CGR_CLASSES,
                           n_in = c(10 + i, 3, 4 + i), n_match = c(7 + i, 2, 1),
                           null_in = c(9 + i, 2.5, 4), null_match = c(4, 0.8, 1.5),
                           stringsAsFactors = FALSE)))))
  ids <- unique(paste(pc$site, pc$plot, sep = "::"))
  sm <- cgr_scope_summary(pc, list(all = ids, wref = ids[4:6]), n_boot = 50)
  a <- sm$scopes[sm$scopes$scope == "all", ]
  k <- pc[pc$class == "deeper_kept", ]; c0 <- pc[pc$class == "deeper_removed", ]
  sh <- function(x) sum(x$n_match) / sum(x$n_in)
  nl <- function(x) sum(x$null_match) / sum(x$null_in)
  expect_equal(a$share[a$class == "deeper_kept"], sh(k))
  expect_equal(a$null_share[a$class == "deeper_removed"], nl(c0))
  expect_equal(a$excess[a$class == "deeper_kept"], (sh(k) - nl(k)) / (1 - nl(k)))
  expect_equal(a$n_plots[1], 6)
  expect_true(all(a$share_lower <= a$share & a$share <= a$share_upper))
  d <- sm$differences[sm$differences$scope == "all" &
                        sm$differences$difference == "deeper_kept_minus_deeper_removed", ]
  expect_equal(d$estimate[d$metric == "share"], sh(k) - sh(c0))
  expect_equal(d$estimate[d$metric == "excess"],
               (sh(k) - nl(k)) / (1 - nl(k)) - (sh(c0) - nl(c0)) / (1 - nl(c0)))
  expect_equal(unique(sm$scopes$n_plots[sm$scopes$scope == "wref"]), 3)
  expect_error(cgr_scope_summary(pc[-1, ], list(all = ids), n_boot = 5), "cover each plot")
})
