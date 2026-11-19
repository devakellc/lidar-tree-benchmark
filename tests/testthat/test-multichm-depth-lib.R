# Unit tests for the multichm_depth arm library: the configuration and its
# label, the declared grid, the per-candidate features (column radius, column
# top, depth, zrep) on hand-computable clouds and against a brute-force count,
# the keep rule with its floors, depth rule and lit union, the distance filter's
# three paths, the reported height, the two identities with the gated arm, the
# arm's configuration (MCD_ARM) and the one-call detector (mcd_prepare,
# detect_multichm_depth) against the long path, with its signature (the
# window slope third, frdens by name) and the lit union's stop on a clip
# without ReturnNumber. Synthetic data only (synth_closed_stand() comes from
# helper-synth.R).
suppressMessages({ library(lidR); library(data.table); library(sf) })
source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "calval_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "multichm_gated_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "multichm_depth_lib.R"), local = TRUE)

## ---- fixtures -------------------------------------------------------------------------------
# A hand-built cloud of explicit points (X, Y, Z [, ReturnNumber]). LAS()
# quantizes the coordinates to its scale factors, which can move a value by one
# unit in the last place; the exact values are put back so that hand-computed
# distances and steps hold bit for bit.
pts_las <- function(df) {
  if (!is.null(df$ReturnNumber)) df$ReturnNumber <- as.integer(df$ReturnNumber)
  las <- suppressMessages(suppressWarnings(LAS(df)))
  for (k in c("X", "Y", "Z")) data.table::set(las@data, j = k, value = as.numeric(df[[k]]))
  st_crs(las) <- 32611L
  las
}
# A copy of a candidate table with one column replaced.
with_col <- function(C, k, v) {
  C <- data.table::copy(C)
  data.table::set(C, j = k, value = v)
  C
}
# Hand-built candidates with their features (depth given; col_top = Z + depth,
# zrep = ztop = Z unless given).
dcands <- function(X, Y, Z, layer, share = NA_real_, depth = 0, zrep = Z)
  data.table(X = as.numeric(X), Y = as.numeric(Y), Z = as.numeric(Z), layer = as.integer(layer),
             ztop = as.numeric(Z), share = as.numeric(share), r_col = 1, col_top = Z + depth,
             depth = as.numeric(depth), zrep = as.numeric(zrep))
# A prepared clip of such candidates (the fields mcd_apply reads).
dprep <- function(C, cover)
  list(cand = C[, c("X", "Y", "Z", "layer", "ztop", "share"), with = FALSE], cover = cover)
# Brute force of mcd_features: every point tested against every candidate, the
# climb as an explicit loop.
brute_features <- function(cand, las, frdens) {
  r <- max(1, sqrt(8 / (pi * frdens)))
  p <- las@data
  out <- t(vapply(seq_len(nrow(cand)), function(i) {
    inside <- (p$X - cand$X[i])^2 + (p$Y - cand$Y[i])^2 <= r^2
    z <- p$Z[inside]
    top <- if (length(z)) max(z) else cand$ztop[i]
    cur <- cand$ztop[i]
    for (v in sort(z[z > cur])) if (v - cur <= 1.5) cur <- v else break
    c(top, top - cand$Z[i], cur)
  }, numeric(3)))
  list(r_col = r, col_top = out[, 1], depth = out[, 2], zrep = out[, 3])
}

## ---- configuration --------------------------------------------------------------------------
test_that("configurations are validated, stored as doubles and labelled", {
  expect_identical(MCD_STOCK, list(depth_max = Inf, near_2d = 0, zmin = 0, zmin_surface = 0,
                                   lit_union = FALSE, cover_min = Inf))
  expect_identical(mcd_config(), MCD_STOCK)
  expect_identical(mcd_config(Inf, 0, 0, 0, FALSE, Inf), MCD_STOCK)
  expect_identical(names(mcd_config(4, 0, 5, 0, TRUE, 0.6)), MCD_FIELDS)
  expect_identical(mcd_config(4L, 3L, 5L, 0L, TRUE, 0L),
                   list(depth_max = 4, near_2d = 3, zmin = 5, zmin_surface = 0, lit_union = TRUE,
                        cover_min = 0))
  # labels, numbers printed with %g
  expect_identical(mcd_config_label(MCD_STOCK), "kInf_r0_z0_f0_l0_cInf")
  expect_identical(mcd_config_label(mcd_config(4, 0, 5, 0, TRUE, 0.6)), "k4_r0_z5_f0_l1_c0.6")
  expect_identical(mcd_config_label(mcd_config(2, 3.5, 3, 3, FALSE, 0)), "k2_r3.5_z3_f3_l0_c0")
  expect_identical(mcd_config_label(mcd_config(2.25, 2.5, 0, 5, FALSE, 1.5)),
                   "k2.25_r2.5_z0_f5_l0_c1.5")
  expect_identical(mcd_config_label(mcd_config(Inf, 0, 5, 0, FALSE, 0.6)), "kInf_r0_z5_f0_l0_c0.6")
  # bounds: depth_max > 0 (Inf allowed); near_2d, zmin, zmin_surface >= 0 and
  # finite; cover_min >= 0 (Inf allowed); lit_union TRUE / FALSE
  for (bad in list(0, -1, NA, NaN, -Inf, "4", TRUE, c(2, 3), numeric(), NULL))
    expect_error(mcd_config(depth_max = bad), "multichm_depth: depth_max must be one number > 0")
  expect_identical(mcd_config(depth_max = 1e-6)$depth_max, 1e-6)
  for (nm in c("near_2d", "zmin", "zmin_surface"))
    for (bad in list(-1e-9, -1, NA, Inf, -Inf, "3", c(0, 1), NULL))
      expect_error(do.call(mcd_config, stats::setNames(list(bad), nm)),
                   sprintf("multichm_depth: %s must be one number >= 0, finite", nm), fixed = TRUE)
  for (bad in list(-0.1, NA, -Inf, "0.6", NULL))
    expect_error(mcd_config(cover_min = bad), "multichm_depth: cover_min must be one number >= 0")
  expect_identical(mcd_config(cover_min = 1.5)$cover_min, 1.5)
  expect_identical(mcd_config(cover_min = 0)$cover_min, 0)
  for (bad in list(NA, 1, "TRUE", c(TRUE, FALSE), NULL))
    expect_error(mcd_config(lit_union = bad), "lit_union must be TRUE or FALSE")
  # a recorded configuration is re-validated and put in the canonical order
  cfg <- mcd_config(3, 2.5, 5, 3, TRUE, 0)
  expect_identical(.mcd_check_config(rev(cfg)), cfg)
  expect_error(.mcd_check_config(NULL), "no configuration")
  expect_error(.mcd_check_config(cfg[-2]), "a configuration is a list(depth_max, near_2d",
               fixed = TRUE)
  expect_error(.mcd_check_config(replace(cfg, "near_2d", list(-1))), "near_2d")
  expect_error(mcd_apply(dprep(dcands(0, 0, 10, 1), 0.9), dcands(0, 0, 10, 1), NULL),
               "no configuration")
})

test_that("the constants are the specification's", {
  expect_identical(mcd_constants(), list(MCD_RADIUS = 1, MCD_MIN_FIRST = 8, MCD_GAP = 1.5,
                                         MCD_LIT_SHARE = 0.75, MCD_LIT_DEPTH = 5))
})

## ---- the declared grid ----------------------------------------------------------------------
test_that("the grid has 240 unique configurations in the declared nested order", {
  g <- mcd_grid()
  expect_identical(nrow(g), 240L)
  expect_identical(names(g), c("config_id", "depth_max", "near_2d", "zmin", "zmin_surface",
                               "lit_union", "cover_min", "label"))
  expect_identical(g$config_id, seq_len(240))
  expect_identical(anyDuplicated(g$label), 0L)
  expect_identical(anyDuplicated(g[MCD_FIELDS]), 0L)
  expect_identical(vapply(seq_len(240), function(i) mcd_config_label(mcd_grid_config(g, i)), ""),
                   g$label)
  # every row is a valid configuration with the grid's values
  expect_identical(lapply(seq_len(240), function(i) mcd_grid_config(g, i)),
                   lapply(seq_len(240), function(i)
                     list(depth_max = g$depth_max[i], near_2d = g$near_2d[i], zmin = g$zmin[i],
                          zmin_surface = g$zmin_surface[i], lit_union = g$lit_union[i],
                          cover_min = g$cover_min[i])))
  # the values and their multiplicities
  expect_identical(as.vector(table(g$cover_min)[c("0.6", "0")]), c(120L, 120L))
  expect_identical(as.vector(table(g$near_2d)), rep(60L, 4))
  expect_setequal(g$near_2d, c(0, 2.5, 3, 3.5))
  expect_identical(as.vector(table(g$lit_union)), c(120L, 120L))
  expect_identical(as.vector(table(g$depth_max)), rep(80L, 3))
  expect_setequal(g$depth_max, c(4, 3, 2))
  fl <- paste(g$zmin, g$zmin_surface)
  expect_identical(unique(fl), c("5 0", "5 3", "5 5", "3 0", "3 3"))
  expect_identical(as.vector(table(fl)), rep(48L, 5))
  # nested loops: cover_min outermost (0.6, 0), near_2d (0, 2.5, 3, 3.5),
  # lit_union (TRUE, FALSE), the floor pair as listed, depth_max (4, 3, 2) innermost
  expect_identical(order(-g$cover_min, g$near_2d, !g$lit_union, match(fl, unique(fl)),
                         -g$depth_max), seq_len(240))
  expect_identical(g$depth_max[1:6], c(4, 3, 2, 4, 3, 2))
  # spot values
  spot <- c(`1` = "k4_r0_z5_f0_l1_c0.6", `2` = "k3_r0_z5_f0_l1_c0.6", `3` = "k2_r0_z5_f0_l1_c0.6",
            `4` = "k4_r0_z5_f3_l1_c0.6", `7` = "k4_r0_z5_f5_l1_c0.6", `10` = "k4_r0_z3_f0_l1_c0.6",
            `13` = "k4_r0_z3_f3_l1_c0.6", `15` = "k2_r0_z3_f3_l1_c0.6",
            `16` = "k4_r0_z5_f0_l0_c0.6", `30` = "k2_r0_z3_f3_l0_c0.6",
            `31` = "k4_r2.5_z5_f0_l1_c0.6", `61` = "k4_r3_z5_f0_l1_c0.6",
            `91` = "k4_r3.5_z5_f0_l1_c0.6", `120` = "k2_r3.5_z3_f3_l0_c0.6",
            `121` = "k4_r0_z5_f0_l1_c0", `136` = "k4_r0_z5_f0_l0_c0",
            `152` = "k3_r2.5_z5_f0_l1_c0", `240` = "k2_r3.5_z3_f3_l0_c0")
  expect_identical(g$label[as.integer(names(spot))], unname(spot))
  expect_identical(g$config_id[g$label == "k4_r0_z5_f0_l1_c0.6"], 1L)
  # no grid configuration is one of the identities' configurations
  id_labels <- vapply(mcd_identities(), function(p) mcd_config_label(p$depth), "")
  expect_false(any(g$label %in% id_labels))
})

test_that("the arm's configuration is k4_r0_z3_f3_l0_c0.6, row 28 of the grid", {
  expect_identical(mcd_config_label(MCD_ARM), "k4_r0_z3_f3_l0_c0.6")
  expect_identical(MCD_ARM, list(depth_max = 4, near_2d = 0, zmin = 3, zmin_surface = 3,
                                 lit_union = FALSE, cover_min = 0.6))
  expect_identical(.mcd_check_config(MCD_ARM), MCD_ARM)
  g <- mcd_grid()
  expect_identical(g$config_id[g$label == mcd_config_label(MCD_ARM)], 28L)
  expect_identical(g$label[28], "k4_r0_z3_f3_l0_c0.6")
  expect_identical(mcd_grid_config(g, 28), MCD_ARM)
  expect_identical(unlist(g[28, MCD_FIELDS]), unlist(MCD_ARM))
})

## ---- features -------------------------------------------------------------------------------
test_that("the column radius holds MCD_MIN_FIRST first returns, at least MCD_RADIUS", {
  expect_identical(mcd_col_radius(16), 1)               # sqrt(8 / (16 pi)) = 0.399
  expect_identical(mcd_col_radius(8 / pi), 1)           # exactly 1
  expect_equal(mcd_col_radius(2), sqrt(4 / pi))         # 1.128
  expect_equal(mcd_col_radius(2), 1.1283792, tolerance = 1e-7)
  expect_equal(mcd_col_radius(0.5), sqrt(16 / pi))      # 2.257
  expect_equal(mcd_col_radius(0.5), 2.2567583, tolerance = 1e-7)
  for (bad in list(0, -1, NA, Inf, NaN, "2", c(1, 2), NULL))
    expect_error(mcd_col_radius(bad), "frdens must be one finite number above 0")
})

# Candidate A at (10, 10): its own top at 10, then returns at 11.49 (a step of
# 1.49, climbed), 13 (a step of 1.51, not climbed), 16 exactly 1 m away and 40
# at 1.001 m; a return 2 m away at 30. Candidate B at (20, 10): a climb of two
# steps of 1.49 to the column's top. Candidate C at (30, 10): an empty column.
feat_fixture <- function() {
  pts <- data.frame(X = c(10, 10.3, 10, 11, 10, 12, 20, 20.2, 20.1, 40),
                    Y = c(10, 10, 10.4, 10, 11.001, 10, 10, 10.2, 9.9, 40),
                    Z = c(10, 11.49, 13, 16, 40, 30, 15.5, 16.99, 18.48, 0))
  C <- data.table(X = c(10, 20, 30), Y = c(10, 10, 10), Z = c(9.8, 15, 8),
                  layer = c(2L, 1L, 3L), ztop = c(10, 15.5, 8.4), share = c(NA, 0.9, 0.5))
  list(las = pts_las(pts), cand = C)
}

test_that("features on a hand-computable cloud: column top, depth and zrep", {
  fx <- feat_fixture()
  before <- data.table::copy(fx$cand)
  f <- mcd_features(fx$cand, fx$las, 16)                         # r_col 1
  expect_identical(fx$cand, before)                              # the input is not changed
  expect_true(data.table::is.data.table(f))
  expect_identical(names(f), c(names(before), "r_col", "col_top", "depth", "zrep"))
  expect_identical(f[, names(before), with = FALSE], before)     # same rows, same order
  expect_identical(f$r_col, rep(1, 3))
  # A: the return exactly 1 m away is in the column, the one 1.001 m away is not
  expect_identical(f$col_top, c(16, 18.48, 8.4))
  expect_equal(f$depth, c(16 - 9.8, 18.48 - 15, 8.4 - 8))
  expect_identical(f$depth, f$col_top - f$Z)
  # zrep: a step of 1.49 is climbed, one of 1.51 is not; C's column is empty
  expect_identical(f$zrep, c(11.49, 18.48, 8.4))
  # a wider column (frdens 2: r_col 1.128) takes in the return 1.001 m away, not
  # the one 2 m away; frdens 0.5 (r_col 2.257) takes in both; zrep stays
  f2 <- mcd_features(fx$cand, fx$las, 2)
  expect_equal(f2$r_col, rep(sqrt(4 / pi), 3))
  expect_identical(f2$col_top, c(40, 18.48, 8.4))
  expect_identical(f2$zrep, c(11.49, 18.48, 8.4))
  f05 <- mcd_features(fx$cand, fx$las, 0.5)
  expect_equal(f05$r_col[1], sqrt(16 / pi))
  expect_identical(f05$col_top, c(40, 18.48, 8.4))
  expect_identical(f05$zrep, c(11.49, 18.48, 8.4))
  # without the return 2 m away but with one at 2.25 m, frdens 0.5 still holds it
  p <- fx$las@data[, c("X", "Y", "Z")]; p$X[6] <- 12.25; p$Z[6] <- 50
  expect_identical(mcd_features(fx$cand, pts_las(as.data.frame(p)), 0.5)$col_top[1], 50)
  expect_identical(mcd_features(fx$cand, pts_las(as.data.frame(p)), 2)$col_top[1], 40)
  # every brute-force value agrees
  for (fr in c(16, 2, 0.5)) {
    b <- brute_features(fx$cand, fx$las, fr)
    g <- mcd_features(fx$cand, fx$las, fr)
    expect_identical(g$col_top, b$col_top); expect_identical(g$depth, b$depth)
    expect_identical(g$zrep, b$zrep)
  }
})

test_that("zrep climbs only steps of at most MCD_GAP, from the candidate's top", {
  z <- function(zs, zt = 10) {
    las <- pts_las(data.frame(X = 5 + seq_along(zs) * 0.01, Y = 5, Z = zs))
    C <- data.table(X = 5, Y = 5, Z = zt - 0.5, layer = 2L, ztop = zt)
    mcd_features(C, las, 16)$zrep
  }
  expect_identical(z(c(11.49)), 11.49)                    # just under: climbed
  expect_identical(z(c(11.51)), 10)                       # just over: not climbed
  expect_identical(z(c(11.5)), 11.5)                      # exactly MCD_GAP: climbed
  expect_identical(z(c(12.9, 11.49, 14.39)), 14.39)       # sorted, then climbed: 1.49, 1.41, 1.49
  expect_identical(z(c(11.49, 13.0, 13.2)), 11.49)        # the 1.51 step stops the climb
  expect_identical(z(c(9, 8, 10)), 10)                    # nothing above ztop
  expect_identical(z(c(9, 10.5, 25)), 10.5)
  # the column's own returns at or below ztop do not move it
  expect_identical(z(c(10, 9.99, 11)), 11)
})

test_that("features of an empty cloud or of no candidate", {
  fx <- feat_fixture()
  e <- mcd_features(fx$cand, filter_poi(fx$las, Z > 1e6), 4)
  expect_identical(e$col_top, fx$cand$ztop)
  expect_identical(e$zrep, fx$cand$ztop)
  expect_identical(e$depth, fx$cand$ztop - fx$cand$Z)
  n0 <- mcd_features(fx$cand[0], fx$las, 4)
  expect_identical(nrow(n0), 0L)
  expect_identical(names(n0), c(names(fx$cand), "r_col", "col_top", "depth", "zrep"))
  expect_error(mcd_features(fx$cand[, -"ztop"], fx$las, 4), "lack columns ztop")
  expect_error(mcd_features(fx$cand, fx$las@data, 4), "LAS object")
  expect_error(mcd_features(fx$cand, fx$las, 0), "frdens")
})

test_that("features on a stand equal a brute-force computation, and depth >= 0", {
  las <- synth_closed_stand(1)
  P <- mcg_prepare(las, 0.5)
  expect_gt(nrow(P$cand), 10)
  for (fr in c(16, 5, 2, 0.5, 0.2)) {
    f <- mcd_features(P$cand, las, fr)
    b <- brute_features(P$cand, las, fr)
    expect_identical(unique(f$r_col), b$r_col)
    expect_identical(max(abs(f$col_top - b$col_top)), 0)
    expect_identical(max(abs(f$depth - b$depth)), 0)
    expect_identical(max(abs(f$zrep - b$zrep)), 0)
    expect_true(all(f$col_top >= f$ztop) && all(f$ztop >= f$Z) && all(f$depth >= 0))
    expect_true(all(f$zrep >= f$ztop & f$zrep <= f$col_top))
  }
})

## ---- the keep rule --------------------------------------------------------------------------
test_that("a closed stand is cover >= cover_min, every stand at 0, none above 1", {
  cfg <- function(c) mcd_config(4, 0, 5, 0, TRUE, c)
  expect_true(mcd_closed(0.6, cfg(0.6)))
  expect_false(mcd_closed(0.5999, cfg(0.6)))
  expect_true(mcd_closed(NA_real_, cfg(0)))
  expect_true(mcd_closed(NULL, cfg(0)))
  expect_false(mcd_closed(NA_real_, cfg(Inf)))
  expect_false(mcd_closed(1, cfg(1.5)))
  expect_false(mcd_closed(NA_real_, cfg(1.0001)))
  expect_true(mcd_closed(1, cfg(1)))
  expect_identical(mcd_closed(NA_real_, cfg(1)), NA)
  expect_identical(mcd_closed(NA_real_, cfg(0.6)), NA)
  expect_identical(mcd_closed(NULL, cfg(0.6)), NA)
  # an unknown cover that decides something stops the gate and the detections
  C <- dcands(c(0, 10), 0, c(20, 10), c(1, 2), depth = c(0, 1))
  expect_error(mcd_gate(C, NA_real_, cfg(0.6)), "needs the canopy cover")
  expect_error(mcd_gate(C, NA_real_, cfg(1)), "needs the canopy cover")
  expect_error(mcd_apply(dprep(C, NA_real_), C, cfg(0.6)), "needs the canopy cover")
  expect_identical(mcd_gate(C, NA_real_, cfg(0))$closed, TRUE)
  expect_identical(mcd_gate(C, NA_real_, cfg(Inf))$closed, FALSE)
  expect_identical(nrow(mcd_apply(dprep(C, NA_real_), C, cfg(0))), 2L)
  # no candidate: 0 rows before the cover is asked for
  E <- C[0]
  det <- mcd_apply(dprep(E, NA_real_), E, cfg(0.6))
  expect_identical(det, data.frame(x = numeric(), y = numeric(), z = numeric()))
  expect_identical(mcd_accepted(dprep(E, NA_real_), E, cfg(0.6)), logical())
})

test_that("the floors apply to their layer in open and closed stands", {
  # surface Z 20, 4, 3; deeper Z 6, 5, 4.9 (every depth 1); far apart
  C <- dcands(X = 10 * (0:5), Y = 0, Z = c(20, 4, 3, 6, 5, 4.9), layer = c(1, 1, 1, 2, 3, 2),
              depth = 1)
  for (cover in c(0.9, 0.3)) for (cmin in c(0.6, 0, Inf)) {
    g <- function(zmin, zs) mcd_gate(C, cover, mcd_config(4, 0, zmin, zs, FALSE, cmin))$keep
    expect_identical(g(5, 0), c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE))
    expect_identical(g(5, 3), c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE))    # Z == floor is kept
    expect_identical(g(5, 3.5), c(TRUE, TRUE, FALSE, TRUE, TRUE, FALSE))
    expect_identical(g(5, 5), c(TRUE, FALSE, FALSE, TRUE, TRUE, FALSE))
    expect_identical(g(3, 3), rep(TRUE, 6))
    expect_identical(g(5.5, 0), c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE))
    expect_identical(g(0, 0), rep(TRUE, 6))
    # the floors read Z, not the top return or zrep
    C2 <- with_col(with_col(C, "ztop", C$Z + 2), "zrep", C$Z + 2)
    expect_identical(mcd_gate(C2, cover, mcd_config(4, 0, 5, 5, FALSE, cmin))$keep,
                     c(TRUE, FALSE, FALSE, TRUE, TRUE, FALSE))
  }
  # the floors also hold through the filter of each stand
  P <- dprep(C, 0.9)
  for (cmin in c(0.6, 0, Inf)) for (r in c(0, 2.5))
    expect_identical(mcd_apply(P, C, mcd_config(4, r, 5, 3.5, FALSE, cmin))$z, c(20, 6, 5, 4))
})

test_that("the depth rule applies to deeper candidates in closed stands only", {
  # a surface peak 9 m deep, deeper candidates 0, 4, 4.01 and 9 m deep
  C <- dcands(X = 10 * (0:4), Y = 0, Z = c(20, 12, 11, 10, 9), layer = c(1, 2, 2, 3, 2),
              depth = c(9, 0, 4, 4.01, 9))
  cfg <- function(k, c = 0.6) mcd_config(k, 0, 5, 0, FALSE, c)
  expect_identical(mcd_gate(C, 0.9, cfg(4))$keep, c(TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_identical(mcd_gate(C, 0.9, cfg(2))$keep, c(TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_identical(mcd_gate(C, 0.9, cfg(Inf))$keep, rep(TRUE, 5))
  expect_identical(mcd_gate(C, 0.6, cfg(4))$closed, TRUE)
  # open: no depth rule
  expect_identical(mcd_gate(C, 0.59, cfg(2))$keep, rep(TRUE, 5))
  expect_identical(mcd_gate(C, NA, cfg(2, Inf))$keep, rep(TRUE, 5))
  # cover_min 0: every stand is closed
  expect_identical(mcd_gate(C, 0.1, cfg(2, 0))$keep, c(TRUE, TRUE, FALSE, FALSE, FALSE))
  # a closed stand needs the deeper candidates' depth; an open one does not
  D <- C[, -"depth"]
  expect_error(mcd_gate(D, 0.9, cfg(4)), "need their depth")
  expect_error(mcd_gate(with_col(C, "depth", c(1, NA, 1, 1, 1)), 0.9, cfg(4)),
               "need their depth")
  expect_identical(mcd_gate(D, 0.3, cfg(4))$keep, rep(TRUE, 5))
  expect_identical(mcd_gate(D[1], 0.9, cfg(4))$keep, TRUE)    # surface only: no depth read
})

test_that("lit_union keeps lit deeper candidates up to MCD_LIT_DEPTH, never an NA share", {
  # deeper candidates, depth_max 2: lit, NA share, share exactly 0.75, too deep,
  # exactly MCD_LIT_DEPTH deep, shallow with an NA share, share 0.74
  C <- dcands(X = 10 * (0:7), Y = 0, Z = c(30, 20, 19, 18, 17, 16, 15, 14),
              layer = c(1, 2, 2, 2, 2, 2, 2, 2),
              share = c(NA, 0.8, NA, 0.75, 0.9, 0.9, NA, 0.74),
              depth = c(10, 3, 3, 3, 5.5, 5, 1, 3))
  lit <- mcd_gate(C, 0.9, mcd_config(2, 0, 5, 0, TRUE, 0.6))$keep
  nolit <- mcd_gate(C, 0.9, mcd_config(2, 0, 5, 0, FALSE, 0.6))$keep
  expect_identical(lit, c(TRUE, TRUE, FALSE, TRUE, FALSE, TRUE, TRUE, FALSE))
  expect_identical(nolit, c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE))
  # a lit candidate still needs the floor
  expect_identical(mcd_gate(C, 0.9, mcd_config(2, 0, 17.5, 0, TRUE, 0.6))$keep,
                   c(TRUE, TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE))
  # open: neither rule applies
  expect_identical(mcd_gate(C, 0.5, mcd_config(2, 0, 5, 0, TRUE, 0.6))$keep, rep(TRUE, 8))
  # depth_max above MCD_LIT_DEPTH: the union adds nothing
  expect_identical(mcd_gate(C, 0.9, mcd_config(6, 0, 5, 0, TRUE, 0.6))$keep,
                   mcd_gate(C, 0.9, mcd_config(6, 0, 5, 0, FALSE, 0.6))$keep)
  # lit_union needs the share column (an NA share is simply not lit)
  expect_error(mcd_gate(C[, -"share"], 0.9, mcd_config(2, 0, 5, 0, TRUE, 0.6)), "share")
  expect_identical(mcd_gate(C[, -"share"], 0.9, mcd_config(2, 0, 5, 0, FALSE, 0.6))$keep, nolit)
  expect_identical(mcd_gate(with_col(C, "share", rep(NA_real_, 8)), 0.9,
                            mcd_config(2, 0, 5, 0, TRUE, 0.6))$keep, nolit)
})

## ---- the distance filter --------------------------------------------------------------------
test_that("near_2d: a top exactly near_2d away is accepted, just under is rejected", {
  f <- function(C, cfg, closed = TRUE) mcd_filter(C, rep(TRUE, nrow(C)), closed, cfg)
  for (r in c(2.5, 3, 3.5)) for (lay in list(c(1, 1), c(1, 2), c(2, 2), c(2, 1))) {
    cfg <- mcd_config(4, r, 0, 0, FALSE, 0.6)
    expect_identical(f(dcands(c(0, r), 0, c(20, 19.9), lay), cfg), c(TRUE, TRUE))
    expect_identical(f(dcands(c(0, r - 0.01), 0, c(20, 19.9), lay), cfg), c(TRUE, FALSE))
    expect_identical(f(dcands(0, c(0, r - 0.01), c(20, 19.9), lay), cfg), c(TRUE, FALSE))
    # no 3-D rule: a top 5 m away horizontally (r < 5) with no height difference
    expect_identical(f(dcands(c(0, 4.9), 0, c(20, 20), lay), cfg), c(TRUE, TRUE))
  }
  # the package's rule would have rejected the pair exactly 2.5 m apart (6.26 < 25)
  expect_identical(f(dcands(c(0, 2.5), 0, c(20, 19.9), c(1, 2)), MCD_STOCK, closed = FALSE),
                   c(TRUE, FALSE))
})

test_that("the filter's three paths: near_2d > 0, the exemption at near_2d 0, open stands", {
  # two surface peaks 1 m apart; deeper: 1 m from the second (rejected by every
  # path), 3.5 m from it and far below, and 3.5 m from that one 0.5 m lower
  # (rejected only by the 3-D rule)
  C <- dcands(X = c(0, 1, 2, 4.5, 8), Y = 0, Z = c(20, 19.5, 15, 10, 9.5),
              layer = c(1, 1, 2, 2, 3))
  keep <- rep(TRUE, 5)
  near0 <- mcd_config(4, 0, 0, 0, FALSE, 0.6)
  expect_identical(mcd_filter(C, keep, TRUE, near0), c(TRUE, TRUE, FALSE, TRUE, FALSE))
  expect_identical(mcd_filter(C, keep, FALSE, near0), c(TRUE, FALSE, FALSE, TRUE, FALSE))
  for (r in c(2.5, 3.5)) {
    cfg <- mcd_config(4, r, 0, 0, FALSE, 0.6)
    expect_identical(mcd_filter(C, keep, TRUE, cfg), c(TRUE, FALSE, FALSE, TRUE, TRUE))
    expect_identical(mcd_filter(C, keep, FALSE, cfg), c(TRUE, FALSE, FALSE, TRUE, FALSE))
  }
  expect_identical(mcd_filter(C, keep, TRUE, mcd_config(4, 4.5, 0, 0, FALSE, 0.6)),
                   c(TRUE, FALSE, FALSE, TRUE, FALSE))   # 3.5^2 < 4.5^2
  # the paths are mcg_filter's: the exemption with the surface exempt, the
  # package's rule without
  expect_identical(mcd_filter(C, keep, TRUE, near0), mcg_filter(C, keep, C$layer == 1L))
  expect_identical(mcd_filter(C, keep, FALSE, near0), mcg_filter(C, keep, rep(FALSE, 5)))
  # a candidate that is not kept is never accepted and never excludes
  expect_identical(mcd_filter(C, c(FALSE, TRUE, TRUE, TRUE, TRUE), FALSE, near0),
                   c(FALSE, TRUE, FALSE, TRUE, FALSE))
  expect_identical(mcd_filter(C, c(TRUE, FALSE, TRUE, FALSE, TRUE), TRUE,
                              mcd_config(4, 2.5, 0, 0, FALSE, 0.6)),
                   c(TRUE, FALSE, FALSE, FALSE, TRUE))
  # descending Z whatever the row order: the result follows the rows
  o <- c(5, 3, 1, 4, 2)
  for (cl in c(TRUE, FALSE)) for (r in c(0, 2.5))
    expect_identical(mcd_filter(C[o], keep, cl, mcd_config(4, r, 0, 0, FALSE, 0.6)),
                     mcd_filter(C, keep, cl, mcd_config(4, r, 0, 0, FALSE, 0.6))[o])
  expect_identical(mcd_filter(C[0], logical(), TRUE, near0), logical())
  expect_error(mcd_filter(C, keep, NA, near0), "closed must be TRUE or FALSE")
  expect_error(mcd_filter(C, keep[-1], TRUE, near0), "one TRUE / FALSE per candidate")
})

test_that("detections: the filter on Z, the reported height Z or zrep, rows by Z", {
  # zrep is not monotone in Z
  C <- dcands(X = c(0, 10, 20, 21), Y = 0, Z = c(20, 15, 12, 11), layer = c(1, 2, 1, 2),
              depth = c(0.5, 1, 0, 3), zrep = c(21, 22, 12.5, 14))
  P <- dprep(C, 0.9)
  cfg <- mcd_config(4, 0, 5, 0, FALSE, 0.6)
  z <- mcd_apply(P, C, cfg)
  zr <- mcd_apply(P, C, cfg, report = "zrep")
  expect_true(assert_detection_contract(z)); expect_true(assert_detection_contract(zr))
  expect_identical(z, data.frame(x = c(0, 10, 20), y = 0, z = c(20, 15, 12)))
  expect_identical(zr, data.frame(x = c(0, 10, 20), y = 0, z = c(21, 22, 12.5)))
  expect_identical(mcd_accepted(P, C, cfg), c(TRUE, TRUE, TRUE, FALSE))
  # reversed rows give the same detections
  expect_identical(mcd_apply(dprep(C[4:1], 0.9), C[4:1], cfg, report = "zrep"), zr)
  # zrep does not move the filter: the candidate at x 21 (Z 11) is 1 m from the
  # one at x 20 whatever its zrep
  C2 <- with_col(C, "zrep", c(21, 22, 12.5, 40))
  expect_identical(mcd_apply(dprep(C2, 0.9), C2, cfg, report = "zrep"), zr)
  expect_error(mcd_apply(P, C, cfg, report = "Z"), "report must be")
  expect_error(mcd_apply(P, C[, -"zrep"], cfg, report = "zrep"), "needs the column `zrep`")
  expect_identical(mcd_apply(P, C[, -"zrep"], cfg), z)
  # the feature table must be the prepared clip's candidates
  expect_error(mcd_apply(P, C[1:3], cfg), "one row per candidate")
  expect_error(mcd_apply(P, C[c(2, 1, 3, 4)], cfg), "X differs")
  expect_error(mcd_apply(P, with_col(C, "layer", c(1L, 1L, 1L, 2L)), cfg), "layer differs")
})

## ---- the identities with the gated arm ------------------------------------------------------
test_that("the identities hold on a prepared stand, closed and open", {
  las <- synth_closed_stand(1)
  P <- mcg_prepare(las, 0.5)
  f <- mcd_features(P$cand, las, 5)
  id <- mcd_identities()
  expect_identical(names(id), c("A", "B"))
  expect_identical(mcg_config_label(id$A$gated), "z5_s0_c0.6_e1")
  expect_identical(id$B$gated, MCG_STOCK)
  expect_identical(id$B$depth, MCD_STOCK)
  expect_identical(id$A$depth, mcd_config(Inf, 0, 5, 0, FALSE, 0.6))
  expect_gte(P$cover, 0.6)
  for (cover in c(P$cover, 0.6, 0.5999, 0.2)) {
    Pc <- replace(P, "cover", list(cover))
    for (k in names(id)) {
      gg <- mcg_gate(Pc$cand, cover, id[[k]]$gated)
      want <- mcg_filter(Pc$cand, gg$keep, gg$exempt)
      expect_identical(mcd_accepted(Pc, f, id[[k]]$depth), want)
      expect_identical(mcd_apply(Pc, f, id[[k]]$depth), mcg_apply(Pc, id[[k]]$gated))
    }
  }
  # the stock set is the package's
  expect_identical(mcd_apply(P, f, MCD_STOCK), mcg_apply(P, MCG_STOCK))
  # identity A differs from stock in this closed stand (the exemption and the floor)
  expect_false(identical(mcd_apply(P, f, id$A$depth), mcd_apply(P, f, MCD_STOCK)))
  # every grid configuration gives a detection table of accepted candidates
  g <- mcd_grid()
  for (i in c(1, 31, 121, 240)) {
    d <- mcd_apply(P, f, mcd_grid_config(g, i))
    expect_true(assert_detection_contract(d))
    expect_false(is.unsorted(-d$z))
    expect_true(all(paste(d$x, d$y) %in% paste(P$cand$X, P$cand$Y)))
  }
})

## ---- the one-call detector ------------------------------------------------------------------
# A lit_union configuration of the grid: k2_r0_z3_f3_l1_c0.6 (config_id 15).
lit_cfg <- function() mcd_grid_config(mcd_grid(), 15)

test_that("mcd_prepare() holds mcg_prepare's candidates and cover, and their features", {
  las <- synth_closed_stand(1)
  P <- mcg_prepare(las, 0.5)
  Q <- mcd_prepare(las, 0.5, frdens = 5)
  expect_identical(names(Q), c("cand", "cover", "feat", "res", "a", "frdens",
                               "has_return_number"))
  expect_identical(Q$cand, P$cand)
  expect_identical(Q$cover, P$cover)
  expect_identical(Q$feat, mcd_features(P$cand, las, 5))
  expect_identical(Q[c("res", "a", "frdens", "has_return_number")],
                   list(res = 0.5, a = 0.10, frdens = 5, has_return_number = TRUE))
  # another resolution, window slope and density reach the candidates and features
  P2 <- mcg_prepare(las, 0.25, 0.05)
  Q2 <- mcd_prepare(las, 0.25, 0.05, frdens = 16)
  expect_identical(Q2$cand, P2$cand)
  expect_identical(Q2$feat, mcd_features(P2$cand, las, 16))
  # without the share: no share column, the same candidates otherwise
  N <- mcd_prepare(las, 0.5, frdens = 5, share = FALSE)
  expect_false("share" %in% names(N$cand))
  expect_false("share" %in% names(N$feat))
  expect_identical(N$cand, P$cand[, -"share"])
  expect_identical(N$cover, P$cover)
  expect_identical(N$feat, Q$feat[, -"share"])
  expect_identical(mcd_apply(N, N$feat, MCD_ARM), mcd_apply(Q, Q$feat, MCD_ARM))
  # a lit_union configuration then stops with the library's message
  expect_gte(N$cover, lit_cfg()$cover_min)
  expect_true(any(N$cand$layer > 1L))
  expect_error(mcd_apply(N, N$feat, lit_cfg()),
               "multichm_depth: lit_union needs the candidates' first-return share", fixed = TRUE)
  # arguments
  expect_error(mcd_prepare(las, 0.5, frdens = 5, share = NA), "share must be TRUE or FALSE")
  expect_error(mcd_prepare(las, 0.5, frdens = 0), "frdens must be one finite number above 0")
  expect_error(detect_multichm_depth(las, 0.5, frdens = 5, cfg = NULL), "no configuration")
  expect_error(detect_multichm_depth(las, 0.5, frdens = 5, report = "Z"), "report must be")
})

test_that("detect_multichm_depth() equals mcg_prepare + mcd_features + mcd_apply", {
  las <- synth_closed_stand(1)
  P <- mcg_prepare(las, 0.5)
  f <- mcd_features(P$cand, las, 5)
  lit <- lit_cfg()
  expect_identical(mcd_config_label(lit), "k2_r0_z3_f3_l1_c0.6")
  # on this stand the lit union, the arm and stock each give other detections
  # than the configuration they are compared with, so each path is exercised
  expect_false(identical(mcd_apply(P, f, lit),
                         mcd_apply(P, f, replace(lit, "lit_union", list(FALSE)))))
  expect_false(identical(mcd_apply(P, f, MCD_ARM), mcd_apply(P, f, MCD_STOCK)))
  for (cfg in list(MCD_ARM, lit, MCD_STOCK)) for (rep in c("z", "zrep")) {
    long <- mcd_apply(P, f, cfg, report = rep)
    expect_gt(nrow(long), 0L)
    expect_identical(detect_multichm_depth(las, 0.5, cfg = cfg, report = rep, frdens = 5), long)
  }
  expect_false(identical(mcd_apply(P, f, MCD_ARM, "zrep")$z, mcd_apply(P, f, MCD_ARM)$z))
  # the default configuration is the arm's, the default report Z
  expect_identical(detect_multichm_depth(las, 0.5, frdens = 5), mcd_apply(P, f, MCD_ARM))
  # another resolution, window slope and density
  P2 <- mcg_prepare(las, 0.25, 0.05)
  expect_identical(detect_multichm_depth(las, 0.25, 0.05, frdens = 16),
                   mcd_apply(P2, mcd_features(P2$cand, las, 16), MCD_ARM))
})

test_that("a clip without candidates gives 0 rows", {
  set.seed(3)
  flat <- pts_las(data.frame(X = runif(300, 0, 20), Y = runif(300, 0, 20), Z = 0.1,
                             ReturnNumber = 1L))
  empty <- pts_las(data.frame(X = numeric(), Y = numeric(), Z = numeric(),
                              ReturnNumber = integer()))
  for (las in list(flat, empty)) {
    Q <- mcd_prepare(las, 0.5, frdens = 5)
    expect_identical(nrow(Q$cand), 0L)
    expect_identical(nrow(Q$feat), 0L)
    for (cfg in list(MCD_ARM, lit_cfg(), MCD_STOCK)) for (rep in c("z", "zrep")) {
      det <- detect_multichm_depth(las, 0.5, cfg = cfg, report = rep, frdens = 5)
      expect_true(assert_detection_contract(det))
      expect_identical(det, data.frame(x = numeric(), y = numeric(), z = numeric()))
    }
  }
  # the empty clip has no cover: the 0 rows come before the cover is asked for
  expect_identical(mcd_prepare(empty, 0.5, frdens = 5)$cover, NA_real_)
})

test_that("the window slope is third as in the gated detector; frdens must be given by name", {
  las <- synth_closed_stand(1)
  # the signatures: a third, frdens without a default
  expect_identical(names(formals(mcd_prepare)), c("las", "res", "a", "frdens", "share"))
  expect_identical(names(formals(detect_multichm_depth)),
                   c("las", "res", "a", "cfg", "report", "frdens"))
  expect_identical(names(formals(detect_multichm_depth))[1:3],
                   names(formals(detect_multichm_gated))[1:3])
  expect_identical(formals(detect_multichm_depth)$a, 0.10)
  expect_identical(formals(mcd_prepare)$a, 0.10)
  # a call written like the gated detector's stops at once: 0.10 is the slope,
  # never the density
  msg <- "frdens is missing; it is the clip's first returns per m^2 and must be given by name"
  expect_error(detect_multichm_depth(las, 0.5, 0.10), msg, fixed = TRUE)
  expect_error(detect_multichm_depth(las, 0.5), msg, fixed = TRUE)
  expect_error(detect_multichm_depth(las, 0.5, 0.10, MCD_ARM, "z"), msg, fixed = TRUE)
  expect_error(mcd_prepare(las, 0.5, 0.10), msg, fixed = TRUE)
  expect_error(mcd_prepare(las, 0.5), msg, fixed = TRUE)
  # before anything else is read: no LAS, no configuration needed to stop
  expect_error(detect_multichm_depth(NULL, 0.5, cfg = NULL), msg, fixed = TRUE)
  expect_error(mcd_prepare(NULL, 0.5, share = NA), msg, fixed = TRUE)
  # the slope given third, the density by name
  P <- mcg_prepare(las, 0.25, 0.05)
  expect_identical(detect_multichm_depth(las, 0.25, 0.05, frdens = 16),
                   mcd_apply(P, mcd_features(P$cand, las, 16), MCD_ARM))
  expect_identical(mcd_prepare(las, 0.25, 0.05, frdens = 16)[c("a", "frdens")],
                   list(a = 0.05, frdens = 16))
})

test_that("lit_union stops on a closed clip without ReturnNumber that has deeper candidates", {
  st <- synth_closed_stand(1)
  las <- pts_las(as.data.frame(st@data[, c("X", "Y", "Z")]))       # no ReturnNumber
  Q <- mcd_prepare(las, 0.5, frdens = 5)
  expect_false(Q$has_return_number)
  expect_identical(Q$cover, NA_real_)                               # no cover without it
  expect_true(any(Q$cand$layer > 1L))
  expect_true(all(is.na(Q$cand$share)))                             # every share NA
  g <- mcd_grid()
  lit0 <- mcd_grid_config(g, which(g$label == "k4_r0_z5_f0_l1_c0"))   # every stand closed
  expect_true(lit0$lit_union)
  expect_identical(lit0$cover_min, 0)
  msg <- paste("multichm_depth: this configuration (lit_union) needs the first-return share of",
               "the deeper candidates in a closed stand, but the clip has no ReturnNumber")
  expect_error(mcd_apply(Q, Q$feat, lit0), msg, fixed = TRUE)
  expect_error(detect_multichm_depth(las, 0.5, cfg = lit0, frdens = 5), msg, fixed = TRUE)
  expect_error(detect_multichm_depth(las, 0.5, cfg = lit0, report = "zrep", frdens = 5), msg,
               fixed = TRUE)
  # a prepared clip without the element behaves as before: the lit branch
  # reads the NA shares as not lit
  Q0 <- Q[setdiff(names(Q), "has_return_number")]
  nolit <- replace(lit0, "lit_union", list(FALSE))
  expect_identical(mcd_apply(Q0, Q0$feat, lit0), mcd_apply(Q0, Q0$feat, nolit))
  # without the lit union, or with no closed stand, the clip is served as before
  expect_identical(mcd_apply(Q, Q$feat, nolit), mcd_apply(Q0, Q0$feat, nolit))
  expect_gt(nrow(mcd_apply(Q, Q$feat, nolit)), 0L)
  open <- replace(lit0, "cover_min", list(Inf))
  expect_identical(mcd_apply(Q, Q$feat, open),
                   mcd_apply(Q, Q$feat, replace(open, "lit_union", list(FALSE))))
  # a cover threshold in (0, 1]: the unknown cover stops first, as before
  expect_error(mcd_apply(Q, Q$feat, mcd_grid_config(g, 1)), "needs the canopy cover")
  # surface candidates only: nothing for the lit branch to read, no stop
  C <- dcands(X = c(0, 10), Y = 0, Z = c(20, 15), layer = c(1, 1))
  P1 <- c(dprep(C, NA), list(has_return_number = FALSE))
  expect_identical(mcd_apply(P1, C, lit0), data.frame(x = c(0, 10), y = 0, z = c(20, 15)))
  # with ReturnNumber the same configuration runs (the study's clips all have it)
  R <- mcd_prepare(st, 0.5, frdens = 5)
  expect_true(R$has_return_number)
  expect_true(assert_detection_contract(mcd_apply(R, R$feat, lit0)))
})
