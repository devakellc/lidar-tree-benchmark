# Unit tests for the multichm_gated arm driver: configuration precedence and
# parsing, the configuration stamp of the detections directory, one detected
# and scored cell (stock parity with the multichm arm), the result columns and
# the pooled summary. Sourcing the script defines its helpers without running
# the sweep (guarded by `if (sys.nframe() == 0L) run_main()`). Synthetic data
# only.
source(file.path("..", "..", "scripts", "detect_multichm_gated_sweep.R"), local = TRUE)

## ---- synthetic data -------------------------------------------------------------------------
# A normalized stand of conical crowns with first returns on the crown surfaces,
# later returns inside them, first-return ground hits and one short tree.
TREES <- data.frame(x = c(10, 18, 27, 11, 25, 19), y = c(10, 12, 9, 23, 24, 18),
                    h = c(22, 18, 20, 16, 21, 8), r = c(3.5, 3, 3.2, 2.8, 3.4, 2),
                    cls = c("dominant", "codominant", "dominant", "intermediate",
                            "codominant", "suppressed"))
stand <- function(seed = 1, with_rn = TRUE) {
  set.seed(seed)
  crown <- lapply(seq_len(nrow(TREES)), function(i) {
    t <- TREES[i, ]
    d <- t$r * sqrt(runif(700)); a <- runif(700, 0, 2 * pi)
    s <- data.frame(X = t$x + d * cos(a), Y = t$y + d * sin(a),
                    Z = pmax(0, t$h * (1 - 0.6 * d / t$r) + rnorm(700, 0, 0.1)), ReturnNumber = 1L)
    d <- 0.8 * t$r * sqrt(runif(250)); a <- runif(250, 0, 2 * pi)
    n <- data.frame(X = t$x + d * cos(a), Y = t$y + d * sin(a),
                    Z = runif(250, 0.3 * t$h, 0.9 * t$h), ReturnNumber = 2L)
    rbind(s, n)
  })
  g <- data.frame(X = runif(2500, 0, 36), Y = runif(2500, 0, 32), Z = abs(rnorm(2500, 0, 0.05)),
                  ReturnNumber = 1L)
  df <- do.call(rbind, c(crown, list(g)))
  df$ReturnNumber <- as.integer(df$ReturnNumber)
  if (!with_rn) df$ReturnNumber <- NULL
  las <- suppressWarnings(LAS(df))
  st_crs(las) <- 32611L
  las
}
stems <- function() data.frame(E = TREES$x + 0.3, N = TREES$y - 0.2, height = TREES$h,
                               crown_class = TREES$cls, stringsAsFactors = FALSE)
meta <- function(frdens = 5, rung = NA)
  list(site = "SYN", plot = "SYN_001", plotType = "tower", rung = rung, cx = 18, cy = 16,
       half = 20, pdens = 12.345, frdens = frdens)
args_of <- function(...) { a <- c(...); setNames(as.list(unname(a)), names(a)) }
GATED <- mcg_config(5, 0.75, 0.7, TRUE)

## ---- configuration --------------------------------------------------------------------------
test_that("no configuration stops with a message naming the ways to give one", {
  # the declared configuration is passed as NULL: these hold whatever MCG_DECLARED is
  expect_error(mcg_arm_config(list(), declared = NULL), "no configuration")
  expect_error(mcg_arm_config(list(), declared = NULL), "CONFIG=")
  expect_error(mcg_arm_config(list(SITE = "SOAP", A = "0.1"), declared = NULL),
               "no declared configuration")
  expect_error(mcg_arm_config(args_of(ZMIN = "5", MIN_SHARE = "0.75"), declared = NULL),
               "missing COVER_MIN= SURFACE_EXEMPT=")
})

test_that("without CONFIG= or explicit arguments a run uses MCG_DECLARED", {
  r <- mcg_arm_config(list(SITE = "WREF", PLOTS = "WREF_073", CORES = "2"))
  expect_identical(r$cfg, MCG_DECLARED)
  expect_identical(r$source, "MCG_DECLARED")
  expect_null(r$file)
  expect_identical(mcg_arm_config(list())$cfg, mcg_config(5, 0.75, 0.6, TRUE))
})

test_that("explicit arguments give a validated configuration", {
  r <- mcg_arm_config(args_of(ZMIN = "5", MIN_SHARE = "0.75", COVER_MIN = "0.7",
                              SURFACE_EXEMPT = "TRUE"), declared = NULL)
  expect_identical(r$cfg, GATED)
  expect_identical(r$source, "arguments")
  expect_null(r$file)
  s <- mcg_arm_config(args_of(ZMIN = "0", MIN_SHARE = "0", COVER_MIN = "0",
                              SURFACE_EXEMPT = "FALSE"), declared = NULL)
  expect_identical(s$cfg, MCG_STOCK)
  for (v in c("true", "T", "1", "yes"))
    expect_true(mcg_arm_config(args_of(ZMIN = "0", MIN_SHARE = "0", COVER_MIN = "0",
                                       SURFACE_EXEMPT = v), NULL)$cfg$surface_exempt)
  expect_error(mcg_arm_config(args_of(ZMIN = "0", MIN_SHARE = "0", COVER_MIN = "0",
                                      SURFACE_EXEMPT = "maybe"), NULL), "TRUE or FALSE")
  expect_error(mcg_arm_config(args_of(ZMIN = "five", MIN_SHARE = "0", COVER_MIN = "0",
                                      SURFACE_EXEMPT = "0"), NULL), "ZMIN= must be a number")
  expect_error(mcg_arm_config(list(ZMIN = NA_character_, MIN_SHARE = "0", COVER_MIN = "0",
                                   SURFACE_EXEMPT = "0"), NULL), "ZMIN= needs a value")
  expect_error(mcg_arm_config(args_of(ZMIN = "0", MIN_SHARE = "1.5", COVER_MIN = "0",
                                      SURFACE_EXEMPT = "0"), NULL), "min_share")
})

test_that("explicit arguments override the CONFIG file, which overrides MCG_DECLARED", {
  f <- tempfile(fileext = ".json"); on.exit(unlink(f))
  jsonlite::write_json(list(zmin = 8, min_share = 0.9, cover_min = 0.6, surface_exempt = FALSE,
                            radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                            cover_height = MCG_COVER_HEIGHT, criterion = "cF1"),
                       f, auto_unbox = TRUE, digits = NA)
  declared <- mcg_config(5, 0.5, 0.8, TRUE)
  r <- mcg_arm_config(list(), declared = declared)
  expect_identical(r$cfg, declared); expect_identical(r$source, "MCG_DECLARED")
  r <- mcg_arm_config(list(CONFIG = f), declared = declared)
  expect_identical(r$cfg, mcg_config(8, 0.9, 0.6, FALSE))
  expect_identical(r$source, "config file"); expect_identical(r$file, f)
  r <- mcg_arm_config(list(CONFIG = f, SURFACE_EXEMPT = "TRUE", ZMIN = "0"), declared = declared)
  expect_identical(r$cfg, mcg_config(0, 0.9, 0.6, TRUE))
  expect_identical(r$source, "config file + arguments")
  r <- mcg_arm_config(list(MIN_SHARE = "0"), declared = declared)
  expect_identical(r$cfg, mcg_config(5, 0, 0.8, TRUE))
  expect_identical(r$source, "MCG_DECLARED + arguments")
})

test_that("a CONFIG file must exist, hold the four values and match the library's features", {
  expect_error(mcg_arm_config(list(CONFIG = tempfile()), NULL), "not found")
  f <- tempfile(fileext = ".json"); on.exit(unlink(f))
  jsonlite::write_json(list(zmin = 5, min_share = 0.75, surface_exempt = TRUE), f,
                       auto_unbox = TRUE)
  expect_error(mcg_arm_config(list(CONFIG = f), NULL), "lacks cover_min")
  jsonlite::write_json(list(zmin = 5, min_share = 0.75, cover_min = 0.7, surface_exempt = TRUE,
                            radius = 2), f, auto_unbox = TRUE)
  expect_error(mcg_arm_config(list(CONFIG = f), NULL), "radius")
  jsonlite::write_json(list(zmin = 5, min_share = 0.75, cover_min = 0.7, surface_exempt = "yes"),
                       f, auto_unbox = TRUE)
  expect_error(mcg_arm_config(list(CONFIG = f), NULL), "true or false")
})

## ---- the detections directory's configuration stamp -----------------------------------------
test_that("a detections directory holds the detections of one configuration only", {
  dir <- file.path(tempfile(), "multichm_gated_detections"); on.exit(unlink(dirname(dir), TRUE))
  stamp <- file.path(dir, MCG_ARM_CONFIG_STAMP)
  mcg_arm_stamp_config(dir, GATED, a = 0.10)
  st <- jsonlite::read_json(stamp, simplifyVector = TRUE)
  expect_identical(st$label, "z5_s0.75_c0.7_e1")
  # everything that changes the apexes is stamped
  expect_equal(st[c("a", "radius", "half_dz", "cover_height")],
               list(a = 0.10, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                    cover_height = MCG_COVER_HEIGHT))
  mcg_arm_stamp_config(dir, MCG_STOCK, a = 0.10)    # nothing persisted yet: restamped
  persist_detections(dir, "P1", NA, data.frame(x = 1, y = 2, z = 3))
  expect_silent(mcg_arm_stamp_config(dir, MCG_STOCK, a = 0.10))
  expect_error(mcg_arm_stamp_config(dir, GATED, a = 0.10), "another configuration")
  expect_error(mcg_arm_stamp_config(dir, MCG_STOCK, a = 0.3), "another configuration")
  expect_error(mcg_arm_stamp_config(dir, MCG_STOCK, a = NA_real_), "window coefficient")
  # a stamp written before the window coefficient and the feature constants were stamped
  jsonlite::write_json(c(MCG_STOCK, list(label = "stock")), stamp, auto_unbox = TRUE,
                       pretty = TRUE, digits = NA)
  expect_error(mcg_arm_stamp_config(dir, MCG_STOCK, a = 0.10), "another configuration")
  unlink(stamp)
  expect_error(mcg_arm_stamp_config(dir, MCG_STOCK, a = 0.10), "another configuration")
})

## ---- one cell ------------------------------------------------------------------------------
test_that("the stock configuration detects exactly what the multichm arm detects", {
  skip_if_not_installed("lidRplugins")
  las <- stand(1)
  for (fr in c(5, 9)) {
    res <- if (fr >= 8) 0.25 else 0.5
    cell <- mcg_arm_cell(las, stems(), meta(frdens = fr), MCG_STOCK)
    tt <- suppressWarnings(lidR::locate_trees(las, lidRplugins::multichm(res = res,
                                                                         ws = ws_factory(0.10))))
    co <- sf::st_coordinates(tt)
    pkg <- data.frame(x = co[, 1], y = co[, 2], z = if (!is.null(tt$Z)) tt$Z else co[, 3])
    a <- pkg[order(pkg$x, pkg$y), ]; b <- cell$det[order(cell$det$x, cell$det$y), ]
    expect_gt(nrow(b), 3)
    expect_identical(unname(a$x), b$x); expect_identical(unname(a$y), b$y)
    expect_identical(unname(a$z), b$z)
    expect_identical(cell$row$chm_res, res)
    sc <- score_plot(stems(), pkg, tol_xy = 4, core_cx = 18, core_cy = 16, core_half = 20)
    expect_identical(cell$row$n_det, sc$n_det); expect_identical(cell$row$TP, sc$TP)
  }
})

test_that("a cell row carries the arm, the rung, the cover and the closed flag", {
  las <- stand(2)
  cover <- mcg_canopy_cover(las)
  cell <- mcg_arm_cell(las, stems(), meta(rung = 4), GATED)
  expect_true(assert_detection_contract(cell$det))
  expect_identical(cell$row$detector, "multichm_gated")
  expect_identical(cell$row$rung, "4")
  expect_identical(cell$row$pdens, 12.35)
  expect_identical(cell$row$n_apex, nrow(cell$det))
  expect_equal(cell$cover, cover)
  expect_identical(cell$closed, cover >= 0.7)
  open <- mcg_arm_cell(las, stems(), meta(), mcg_config(5, 0.75, 1, TRUE))
  expect_false(open$closed)
  expect_identical(cell$row$n_ref, nrow(stems()))
  expect_identical(cell$row$n_det, score_plot(stems(), cell$det, tol_xy = 4, core_cx = 18,
                                              core_cy = 16, core_half = 20)$n_det)
})

test_that("in a closed stand the share gate and the exemption change the detections", {
  las <- synth_closed_stand(1)
  cover <- mcg_canopy_cover(las)
  expect_gt(cover, 0.6)
  near <- function(det, x, y, r = 1) any((det$x - x)^2 + (det$y - y)^2 <= r^2)
  cell <- function(cfg) mcg_arm_cell(las, synth_closed_stems(), synth_closed_meta(), cfg)
  gated <- cell(mcg_config(5, 0.75, 0.6, TRUE))
  plain <- cell(mcg_config(5, 0, 0.6, FALSE))        # the same without share gate and exemption
  expect_equal(gated$cover, cover)
  expect_true(gated$closed)
  expect_true(assert_detection_contract(gated$det))
  expect_false(isTRUE(all.equal(gated$det, plain$det)))
  # the understory peak under the wide crown: kept without the gate, gated out
  expect_true(near(plain$det, 25.5, 21))
  expect_false(near(gated$det, 25.5, 21))
  expect_false(near(cell(mcg_config(5, 0.75, 0.6, FALSE))$det, 25.5, 21))
  # the second of the two tall crowns: filtered out unless surface peaks are exempt
  expect_false(near(plain$det, 12, 8))
  expect_true(near(gated$det, 12, 8))
  expect_true(near(cell(mcg_config(5, 0, 0.6, TRUE))$det, 12, 8))
  expect_identical(gated$row$n_apex, nrow(gated$det))
  # with a cover threshold above the stand's cover the stand is open: no gate,
  # no exemption
  open <- cell(mcg_config(5, 0.75, 0.9, TRUE))
  expect_false(open$closed)
  expect_identical(open$det, plain$det)
})

test_that("a configuration that needs return numbers fails its cell instead of skipping it", {
  las <- stand(1, with_rn = FALSE)
  expect_error(mcg_arm_cell(las, stems(), meta(), GATED), "ReturnNumber")
  ok <- mcg_arm_cell(las, stems(), meta(), mcg_config(zmin = 5))
  expect_true(is.na(ok$cover))
  expect_true(assert_detection_contract(ok$det))
})

test_that("a flat clip gives an empty, persistable detection set", {
  flat <- suppressWarnings(LAS(data.frame(X = runif(300, 0, 36), Y = runif(300, 0, 32), Z = 0.1,
                                          ReturnNumber = 1L)))
  st_crs(flat) <- 32611L
  cell <- mcg_arm_cell(flat, stems(), meta(), GATED)
  expect_identical(nrow(cell$det), 0L)
  expect_identical(cell$row$n_apex, 0L)
  expect_identical(cell$row$TP, 0L)
  dir <- tempfile(); on.exit(unlink(dir, TRUE)); dir.create(dir)
  f <- persist_detections(dir, "SYN_001", NA, cell$det)
  expect_identical(basename(f), "SYN_001__native.csv")
  expect_identical(nrow(read.csv(f)), 0L)
})

# The driver stops on an empty clip before it calls mcg_arm_cell(); this is the
# function alone.
test_that("mcg_arm_cell on an empty clip returns no detections and an unknown cover", {
  empty <- suppressWarnings(LAS(data.frame(X = numeric(), Y = numeric(), Z = numeric(),
                                           ReturnNumber = integer())))
  st_crs(empty) <- 32611L
  for (cfg in list(GATED, MCG_DECLARED)) {             # both read the cover
    cell <- mcg_arm_cell(empty, stems(), meta(), cfg)
    expect_identical(nrow(cell$det), 0L)
    expect_identical(cell$row$n_apex, 0L)
    expect_identical(cell$row$TP, 0L)
    expect_true(is.na(cell$cover))
    expect_true(is.na(cell$closed))
  }
  expect_true(mcg_arm_cell(empty, stems(), meta(), MCG_STOCK)$closed)   # no cover switch
})

## ---- result columns and pooling -------------------------------------------------------------
test_that("results gain tp_core, then cover, closed and the configuration", {
  las <- stand(1)
  rows <- do.call(rbind, lapply(c(NA, 4), function(r) {
    cell <- mcg_arm_cell(las, stems(), meta(rung = r), GATED)
    cbind(cell$row, cover = cell$cover, closed = cell$closed)
  }))
  out <- mcg_arm_finish(rows, GATED)
  n <- names(out)
  expect_identical(tail(n, 7), c("tp_core", "cover", "closed", "zmin", "min_share", "cover_min",
                                 "surface_exempt"))
  expect_identical(n[1:9], c("site", "plot", "plotType", "detector", "rung", "pdens", "frdens",
                             "chm_res", "n_apex"))
  expect_identical(mcg_arm_finish(data.frame(precision = c(0.5, NA), n_det = c(8L, 0L),
                                             cover = 0.7, closed = TRUE), GATED)$tp_core,
                   c(4, NA))
  expect_identical(out$zmin, c(5, 5)); expect_identical(out$surface_exempt, c(TRUE, TRUE))
  expect_identical(out$rung, c("native", "4"))
})

test_that("the pooled summary sums counts by rung", {
  r <- data.frame(plot = c("a", "b", "a", "b"), rung = c("native", "native", "4", "4"),
                  n_ref = c(10, 2, 10, 2), TP = c(5, 2, 4, 0), n_det = c(8, 2, 0, 0),
                  tp_core = c(4, 2, NA, NA))
  p <- mcg_arm_pooled(r)
  expect_identical(p$rung, c("native", "4"))
  expect_equal(p$recall, c(7 / 12, 4 / 12))
  expect_equal(p$precision[1], 6 / 10)               # not mean(4/8, 2/2)
  expect_true(is.na(p$precision[2]))
  expect_equal(p$F1[1], 2 * (7 / 12) * 0.6 / (7 / 12 + 0.6))
  expect_identical(p$n_plots, c(2L, 2L))
})
