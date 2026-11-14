# Unit tests for the multichm_gated arm driver: configuration precedence and
# parsing (the optional SPACING_MIN= included), the declared configuration file
# (its feature constants and its label), the configuration stamp of the
# detections directory, one detected and scored cell (stock parity with the
# multichm arm, the stand's cover, top height and crown spacing), the result
# columns and the pooled summary. Sourcing the script defines its helpers
# without running the sweep (guarded by `if (sys.nframe() == 0L) run_main()`).
# Synthetic data only.
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
# the stamp's fields, in the order the driver writes them
STAMP_NAMES <- c("zmin", "min_share", "cover_min", "surface_exempt", "spacing_min", "a", "radius",
                 "half_dz", "cover_height", "crown_res", "crown_ws", "label")
write_stamp <- function(x, stamp) jsonlite::write_json(x, stamp, auto_unbox = TRUE, pretty = TRUE,
                                                       digits = NA)

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

test_that("without a declared configuration the four are required and SPACING_MIN= is optional", {
  four <- c(ZMIN = "5", MIN_SHARE = "0.75", COVER_MIN = "0.7", SURFACE_EXEMPT = "TRUE")
  expect_error(mcg_arm_config(list(), declared = NULL), "SPACING_MIN= optional")
  # SPACING_MIN= alone, or with three of the four, is not a configuration
  expect_error(mcg_arm_config(args_of(SPACING_MIN = "8"), declared = NULL),
               "missing ZMIN= MIN_SHARE= COVER_MIN= SURFACE_EXEMPT=$")
  for (k in names(four))
    expect_error(mcg_arm_config(args_of(four[setdiff(names(four), k)], SPACING_MIN = "8"),
                                declared = NULL),
                 paste0("\\(SPACING_MIN= is optional\\); missing ", k, "=$"))
  r <- mcg_arm_config(args_of(four), declared = NULL)               # SPACING_MIN= absent: 0
  expect_identical(r$cfg, GATED)
  expect_identical(r$cfg$spacing_min, 0)
  expect_identical(r$source, "arguments")
  r <- mcg_arm_config(args_of(four, SPACING_MIN = "8"), declared = NULL)
  expect_identical(r$cfg, mcg_config(5, 0.75, 0.7, TRUE, 8))
  expect_identical(mcg_config_label(r$cfg), "z5_s0.75_c0.7_e1_d8")
})

test_that("SPACING_MIN= parses as a number like ZMIN= and is validated like spacing_min", {
  four <- c(ZMIN = "5", MIN_SHARE = "0.75", COVER_MIN = "0.7", SURFACE_EXEMPT = "TRUE")
  for (v in c("8", "8.0", "0.8e1"))
    expect_identical(mcg_arm_config(args_of(four, SPACING_MIN = v), NULL)$cfg$spacing_min, 8)
  expect_identical(mcg_arm_config(args_of(four, SPACING_MIN = "8.5"), NULL)$cfg$spacing_min, 8.5)
  expect_identical(mcg_config_label(mcg_arm_config(args_of(four, SPACING_MIN = "8.5"), NULL)$cfg),
                   "z5_s0.75_c0.7_e1_d8.5")
  expect_identical(mcg_arm_config(args_of(four, SPACING_MIN = "0"), NULL)$cfg, GATED)
  expect_error(mcg_arm_config(args_of(four, SPACING_MIN = "wide"), NULL),
               "SPACING_MIN= must be a number")
  expect_error(mcg_arm_config(c(as.list(four), list(SPACING_MIN = NA_character_)), NULL),
               "SPACING_MIN= needs a value")
  expect_error(mcg_arm_config(args_of(four, SPACING_MIN = ""), NULL), "SPACING_MIN= needs a value")
  expect_error(mcg_arm_config(args_of(four, SPACING_MIN = "-1"), NULL),
               "spacing_min must be one number")
  expect_error(mcg_arm_config(args_of(four, SPACING_MIN = "Inf"), NULL),
               "spacing_min must be one number")
})

test_that("without CONFIG= or explicit arguments a run uses MCG_DECLARED", {
  r <- mcg_arm_config(list(SITE = "WREF", PLOTS = "WREF_073", CORES = "2"))
  expect_identical(r$cfg, MCG_DECLARED)
  expect_identical(r$source, "MCG_DECLARED")
  expect_null(r$file)
  expect_identical(mcg_arm_config(list())$cfg, mcg_config(5, 0.75, 0.6, TRUE, 8))
  expect_identical(mcg_config_label(mcg_arm_config(list())$cfg), "z5_s0.75_c0.6_e1_d8")
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

test_that("SPACING_MIN= overrides the file's spacing_min, which overrides the declared one", {
  f <- tempfile(fileext = ".json"); g <- tempfile(fileext = ".json"); on.exit(unlink(c(f, g)))
  jsonlite::write_json(list(zmin = 8, min_share = 0.9, cover_min = 0.6, surface_exempt = FALSE,
                            spacing_min = 7.5, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                            cover_height = MCG_COVER_HEIGHT, crown_res = MCG_CROWN_RES,
                            crown_ws = MCG_CROWN_WS, label = "z8_s0.9_c0.6_e0_d7.5"),
                       f, auto_unbox = TRUE, digits = NA)
  jsonlite::write_json(list(zmin = 8, min_share = 0.9, cover_min = 0.6, surface_exempt = FALSE),
                       g, auto_unbox = TRUE, digits = NA)
  declared <- mcg_config(5, 0.5, 0.8, TRUE, 9)
  expect_identical(mcg_arm_config(list(), declared = declared)$cfg, declared)
  # the file's spacing_min, also when the file has none (no spacing condition)
  expect_identical(mcg_arm_config(list(CONFIG = f), declared = declared)$cfg,
                   mcg_config(8, 0.9, 0.6, FALSE, 7.5))
  expect_identical(mcg_arm_config(list(CONFIG = g), declared = declared)$cfg,
                   mcg_config(8, 0.9, 0.6, FALSE, 0))
  # the argument over the file and over the declared configuration
  r <- mcg_arm_config(list(CONFIG = f, SPACING_MIN = "7"), declared = declared)
  expect_identical(r$cfg, mcg_config(8, 0.9, 0.6, FALSE, 7))
  expect_identical(r$source, "config file + arguments")
  expect_identical(mcg_arm_config(list(CONFIG = f, SPACING_MIN = "0"), declared = declared)$cfg,
                   mcg_config(8, 0.9, 0.6, FALSE))
  expect_identical(mcg_arm_config(list(CONFIG = g, SPACING_MIN = "8.5"), declared = declared)$cfg,
                   mcg_config(8, 0.9, 0.6, FALSE, 8.5))
  r <- mcg_arm_config(list(SPACING_MIN = "8"), declared = declared)
  expect_identical(r$cfg, mcg_config(5, 0.5, 0.8, TRUE, 8))
  expect_identical(r$source, "MCG_DECLARED + arguments")
  # SPACING_MIN=0 drops a declared spacing condition
  r <- mcg_arm_config(list(SPACING_MIN = "0"), declared = declared)
  expect_identical(r$cfg, mcg_config(5, 0.5, 0.8, TRUE))
  expect_identical(r$source, "MCG_DECLARED + arguments")
  r <- mcg_arm_config(list(SPACING_MIN = "0"))
  expect_identical(r$cfg, mcg_config(5, 0.75, 0.6, TRUE))
  expect_identical(mcg_config_label(r$cfg), "z5_s0.75_c0.6_e1")
  # arguments for the other fields keep the base's spacing_min
  expect_identical(mcg_arm_config(list(ZMIN = "0", COVER_MIN = "0.7"), declared = declared)$cfg,
                   mcg_config(0, 0.5, 0.7, TRUE, 9))
  expect_identical(mcg_arm_config(list(CONFIG = f, ZMIN = "5"), declared = declared)$cfg,
                   mcg_config(5, 0.9, 0.6, FALSE, 7.5))
  # without a share gate spacing_min is 0, whether declared, in the file or given
  expect_identical(mcg_arm_config(list(MIN_SHARE = "0"), declared = declared)$cfg,
                   mcg_config(5, 0, 0.8, TRUE))
  expect_identical(mcg_arm_config(list(MIN_SHARE = "0"), declared = declared)$cfg$spacing_min, 0)
  expect_identical(mcg_arm_config(list(CONFIG = f, MIN_SHARE = "0"), declared = declared)$cfg,
                   mcg_config(8, 0, 0.6, FALSE))
  expect_identical(mcg_arm_config(list(CONFIG = f, MIN_SHARE = "0", SPACING_MIN = "9"),
                                  declared = declared)$cfg, mcg_config(8, 0, 0.6, FALSE))
  expect_identical(mcg_arm_config(list(MIN_SHARE = "0", SPACING_MIN = "8"),
                                  declared = declared)$cfg, mcg_config(5, 0, 0.8, TRUE))
  expect_identical(mcg_arm_config(list(MIN_SHARE = "0"), declared = MCG_DECLARED)$cfg$spacing_min,
                   0)
})

test_that("a CONFIG file must exist, hold the four values and match the library's features", {
  expect_error(mcg_arm_config(list(CONFIG = tempfile()), NULL), "not found")
  f <- tempfile(fileext = ".json"); on.exit(unlink(f))
  jsonlite::write_json(list(zmin = 5, min_share = 0.75, surface_exempt = TRUE), f,
                       auto_unbox = TRUE)
  expect_error(mcg_arm_config(list(CONFIG = f), NULL), "lacks cover_min")
  jsonlite::write_json(list(zmin = 5, min_share = 0.75, spacing_min = 8, surface_exempt = TRUE), f,
                       auto_unbox = TRUE)
  expect_error(mcg_arm_config(list(CONFIG = f), NULL), "lacks cover_min$")
  jsonlite::write_json(list(zmin = 5, min_share = 0.75, cover_min = 0.7, surface_exempt = TRUE,
                            radius = 2), f, auto_unbox = TRUE)
  expect_error(mcg_arm_config(list(CONFIG = f), NULL), "radius")
  jsonlite::write_json(list(zmin = 5, min_share = 0.75, cover_min = 0.7, surface_exempt = "yes"),
                       f, auto_unbox = TRUE)
  expect_error(mcg_arm_config(list(CONFIG = f), NULL), "true or false")
})

test_that("a CONFIG file without spacing_min has none; its crown constants must match", {
  f <- tempfile(fileext = ".json"); on.exit(unlink(f))
  four <- list(zmin = 5, min_share = 0.75, cover_min = 0.7, surface_exempt = TRUE)
  jsonlite::write_json(c(four, list(radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                                    cover_height = MCG_COVER_HEIGHT)),
                       f, auto_unbox = TRUE, digits = NA)
  expect_identical(mcg_read_config_file(f), c(four, list(spacing_min = 0)))
  expect_identical(mcg_arm_config(list(CONFIG = f), NULL)$cfg, GATED)
  jsonlite::write_json(c(four, list(spacing_min = 8, crown_res = MCG_CROWN_RES,
                                    crown_ws = MCG_CROWN_WS)), f, auto_unbox = TRUE, digits = NA)
  expect_identical(mcg_read_config_file(f), c(four, list(spacing_min = 8)))
  expect_identical(mcg_arm_config(list(CONFIG = f), NULL)$cfg, mcg_config(5, 0.75, 0.7, TRUE, 8))
  for (k in c("crown_res", "crown_ws")) for (v in c(0.5, 2, 7)) {
    x <- c(four, list(spacing_min = 8, crown_res = MCG_CROWN_RES, crown_ws = MCG_CROWN_WS))
    x[[k]] <- v
    jsonlite::write_json(x, f, auto_unbox = TRUE, digits = NA)
    expect_error(mcg_arm_config(list(CONFIG = f), NULL), paste("declared with", k))
    x$spacing_min <- NULL                                # also without a spacing condition
    jsonlite::write_json(x, f, auto_unbox = TRUE, digits = NA)
    expect_error(mcg_read_config_file(f), paste("declared with", k))
  }
  # the top height decides nothing, so the quantile a file records for it is not checked
  for (p in c(0.9, MCG_TOP_PROB)) {
    jsonlite::write_json(c(four, list(spacing_min = 8, top_prob = p)), f, auto_unbox = TRUE,
                         digits = NA)
    expect_identical(mcg_read_config_file(f), c(four, list(spacing_min = 8)))
  }
  jsonlite::write_json(c(four, list(spacing_min = -5)), f, auto_unbox = TRUE, digits = NA)
  expect_error(mcg_arm_config(list(CONFIG = f), NULL), "spacing_min must be one number")
})

test_that("a CONFIG file's label, when it has one, must be this library's label of it", {
  f <- tempfile(fileext = ".json"); on.exit(unlink(f))
  four <- list(zmin = 5, min_share = 0.75, cover_min = 0.6, surface_exempt = TRUE)
  consts <- list(a = 0.1, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                 cover_height = MCG_COVER_HEIGHT, crown_res = MCG_CROWN_RES,
                 crown_ws = MCG_CROWN_WS)
  # labelled as this library labels it: read
  jsonlite::write_json(c(list(config_id = 360, label = "z5_s0.75_c0.6_e1_d8"), four,
                         list(spacing_min = 8), consts), f, auto_unbox = TRUE, digits = NA)
  expect_identical(mcg_read_config_file(f), c(four, list(spacing_min = 8)))
  expect_identical(mcg_arm_config(list(CONFIG = f), NULL)$cfg, MCG_DECLARED)
  jsonlite::write_json(c(list(label = "z5_s0.75_c0.6_e1"), four, consts), f, auto_unbox = TRUE,
                       digits = NA)
  expect_identical(mcg_arm_config(list(CONFIG = f), NULL)$cfg, mcg_config(5, 0.75, 0.6, TRUE))
  jsonlite::write_json(c(list(label = "stock"), MCG_STOCK), f, auto_unbox = TRUE, digits = NA)
  expect_identical(mcg_arm_config(list(CONFIG = f), NULL)$cfg, MCG_STOCK)
  # the label of the canonical form: without a share gate spacing_min is 0
  jsonlite::write_json(list(zmin = 5, min_share = 0, cover_min = 0.6, surface_exempt = TRUE,
                            spacing_min = 8, label = "z5_s0_c0.6_e1"),
                       f, auto_unbox = TRUE, digits = NA)
  expect_identical(mcg_arm_config(list(CONFIG = f), NULL)$cfg, mcg_config(5, 0, 0.6, TRUE))
  # a file whose label is not its configuration's was declared by another version of the
  # library: a field this library does not read (here `crown_top`) or another spacing
  msg <- function(file_label, own)
    paste0("is labelled ", file_label, ", while this library labels its configuration ", own,
           ", so it was declared by another version of the library")
  jsonlite::write_json(c(list(label = "z5_s0.75_c0.6_e1_x30"), four, list(crown_top = 30),
                         consts), f, auto_unbox = TRUE, digits = NA)
  expect_error(mcg_read_config_file(f), msg("z5_s0.75_c0.6_e1_x30", "z5_s0.75_c0.6_e1"),
               fixed = TRUE)
  expect_error(mcg_arm_config(list(CONFIG = f), NULL), "is labelled z5_s0.75_c0.6_e1_x30")
  # ... and explicit arguments do not rescue it
  expect_error(mcg_arm_config(list(CONFIG = f, SPACING_MIN = "0"), NULL), "is labelled")
  jsonlite::write_json(c(list(label = "z5_s0.75_c0.6_e1"), four, list(spacing_min = 8), consts),
                       f, auto_unbox = TRUE, digits = NA)
  expect_error(mcg_read_config_file(f), msg("z5_s0.75_c0.6_e1", "z5_s0.75_c0.6_e1_d8"),
               fixed = TRUE)
  jsonlite::write_json(c(list(label = "z5_s0.75_c0.6_e1_d8"), four, consts), f, auto_unbox = TRUE,
                       digits = NA)
  expect_error(mcg_read_config_file(f), msg("z5_s0.75_c0.6_e1_d8", "z5_s0.75_c0.6_e1"),
               fixed = TRUE)
  jsonlite::write_json(c(list(label = "z5_s0.75_c0.6_e1_d7.5"), four, list(spacing_min = 8),
                         consts), f, auto_unbox = TRUE, digits = NA)
  expect_error(mcg_read_config_file(f), "is labelled z5_s0.75_c0.6_e1_d7.5")
  # a file without a label is read
  jsonlite::write_json(c(four, list(spacing_min = 8), consts), f, auto_unbox = TRUE, digits = NA)
  expect_identical(mcg_read_config_file(f), c(four, list(spacing_min = 8)))
})

## ---- the detections directory's configuration stamp -----------------------------------------
test_that("a detections directory holds the detections of one configuration only", {
  dir <- file.path(tempfile(), "multichm_gated_detections"); on.exit(unlink(dirname(dir), TRUE))
  stamp <- file.path(dir, MCG_ARM_CONFIG_STAMP)
  mcg_arm_stamp_config(dir, GATED, a = 0.10)
  st <- jsonlite::read_json(stamp, simplifyVector = TRUE)
  expect_identical(st$label, "z5_s0.75_c0.7_e1")
  # everything that changes the apexes is stamped
  expect_identical(names(st), STAMP_NAMES)
  expect_equal(st[c("spacing_min", "a", "radius", "half_dz", "cover_height", "crown_res",
                    "crown_ws")],
               list(spacing_min = 0, a = 0.10, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                    cover_height = MCG_COVER_HEIGHT, crown_res = MCG_CROWN_RES,
                    crown_ws = MCG_CROWN_WS))
  mcg_arm_stamp_config(dir, MCG_STOCK, a = 0.10)    # nothing persisted yet: restamped
  persist_detections(dir, "P1", NA, data.frame(x = 1, y = 2, z = 3))
  expect_silent(mcg_arm_stamp_config(dir, MCG_STOCK, a = 0.10))
  expect_error(mcg_arm_stamp_config(dir, GATED, a = 0.10), "another configuration")
  expect_error(mcg_arm_stamp_config(dir, MCG_STOCK, a = 0.3), "another configuration")
  expect_error(mcg_arm_stamp_config(dir, MCG_STOCK, a = NA_real_), "window coefficient")
  # a stamp without the window coefficient and the feature constants
  write_stamp(c(MCG_STOCK[1:4], list(label = "stock")), stamp)
  expect_error(mcg_arm_stamp_config(dir, MCG_STOCK, a = 0.10), "another configuration")
  unlink(stamp)
  expect_error(mcg_arm_stamp_config(dir, MCG_STOCK, a = 0.10), "another configuration")
})

test_that("the stamp holds spacing_min and the crown constants; one with none has spacing 0", {
  dir <- file.path(tempfile(), "multichm_gated_detections"); on.exit(unlink(dirname(dir), TRUE))
  stamp <- file.path(dir, MCG_ARM_CONFIG_STAMP)
  d8 <- mcg_config(5, 0.75, 0.6, TRUE, 8); d0 <- mcg_config(5, 0.75, 0.6, TRUE)
  mcg_arm_stamp_config(dir, d8, a = 0.10)
  st <- jsonlite::read_json(stamp, simplifyVector = TRUE)
  expect_identical(names(st), STAMP_NAMES)
  expect_identical(st$label, "z5_s0.75_c0.6_e1_d8")
  expect_equal(st$spacing_min, 8)
  expect_equal(st$crown_res, MCG_CROWN_RES); expect_equal(st$crown_ws, MCG_CROWN_WS)
  persist_detections(dir, "P1", NA, data.frame(x = 1, y = 2, z = 3))
  expect_silent(mcg_arm_stamp_config(dir, d8, a = 0.10))
  # another spacing_min is another configuration, spacing_min 0 (no spacing condition) included
  for (cfg in list(d0, mcg_config(5, 0.75, 0.6, TRUE, 7.5)))
    expect_error(mcg_arm_stamp_config(dir, cfg, a = 0.10), "another configuration")
  # another crown constant is another feature
  for (k in c("crown_res", "crown_ws")) {
    bad <- st; bad[[k]] <- bad[[k]] + 1
    write_stamp(bad, stamp)
    expect_error(mcg_arm_stamp_config(dir, d8, a = 0.10), "another configuration")
  }
  # stamps that record one or two of spacing_min, crown_res and crown_ws are refused, also
  # for a configuration without a spacing condition
  st0 <- utils::modifyList(st, list(spacing_min = 0, label = "z5_s0.75_c0.6_e1"))
  crown <- c("spacing_min", "crown_res", "crown_ws")
  for (keep in c(as.list(crown), utils::combn(crown, 2, simplify = FALSE))) {
    drop <- setdiff(crown, keep)
    write_stamp(st[setdiff(names(st), drop)], stamp)
    expect_error(mcg_arm_stamp_config(dir, d8, a = 0.10),
                 "another configuration, window coefficient or feature constants (or a stamp",
                 fixed = TRUE)
    write_stamp(st0[setdiff(names(st0), drop)], stamp)
    expect_error(mcg_arm_stamp_config(dir, d0, a = 0.10), "another configuration")
    expect_identical(intersect(crown, names(jsonlite::read_json(stamp))), keep)  # left as it was
  }
  # a stamp that records none of the three has no spacing condition: it holds spacing_min 0
  # with the library's crown constants, and is refused for a configuration with a spacing
  # condition
  pre <- c(d0[1:4], list(a = 0.10, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                         cover_height = MCG_COVER_HEIGHT, label = "z5_s0.75_c0.6_e1"))
  write_stamp(pre, stamp)
  expect_error(mcg_arm_stamp_config(dir, d8, a = 0.10), "another configuration")
  expect_equal(jsonlite::read_json(stamp, simplifyVector = TRUE), pre)     # left as it was
  for (cfg in list(mcg_config(5, 0.75, 0.6, TRUE, 7), mcg_config(5, 0.75, 0.7, TRUE)))
    expect_error(mcg_arm_stamp_config(dir, cfg, a = 0.10), "another configuration")
  expect_error(mcg_arm_stamp_config(dir, d0, a = 0.3), "another configuration")
  # accepted for its configuration, and restamped in full
  expect_silent(mcg_arm_stamp_config(dir, d0, a = 0.10))
  st <- jsonlite::read_json(stamp, simplifyVector = TRUE)
  expect_identical(names(st), STAMP_NAMES)
  expect_equal(st$spacing_min, 0)
  expect_equal(st$crown_res, MCG_CROWN_RES); expect_equal(st$crown_ws, MCG_CROWN_WS)
  expect_identical(st$label, "z5_s0.75_c0.6_e1")
  expect_error(mcg_arm_stamp_config(dir, d8, a = 0.10), "another configuration")
  expect_silent(mcg_arm_stamp_config(dir, d0, a = 0.10))
  # fields the driver does not stamp, such as the top height's quantile, do not matter
  write_stamp(c(pre, list(top_prob = MCG_TOP_PROB)), stamp)
  expect_silent(mcg_arm_stamp_config(dir, d0, a = 0.10))
  expect_identical(names(jsonlite::read_json(stamp)), STAMP_NAMES)
  # without a label the fields decide
  write_stamp(pre[setdiff(names(pre), "label")], stamp)
  expect_error(mcg_arm_stamp_config(dir, d8, a = 0.10), "another configuration")
  expect_silent(mcg_arm_stamp_config(dir, d0, a = 0.10))
  # before any detection is persisted, such a directory is simply restamped
  write_stamp(st0[c("zmin", "crown_res")], stamp)
  unlink(file.path(dir, "P1__native.csv"))
  expect_silent(mcg_arm_stamp_config(dir, d8, a = 0.10))
  st <- jsonlite::read_json(stamp, simplifyVector = TRUE)
  expect_equal(st$spacing_min, 8); expect_identical(st$label, "z5_s0.75_c0.6_e1_d8")
})

test_that("a stamp whose label is not this library's label of the configuration is refused", {
  dir <- file.path(tempfile(), "multichm_gated_detections"); on.exit(unlink(dirname(dir), TRUE))
  stamp <- file.path(dir, MCG_ARM_CONFIG_STAMP)
  d8 <- mcg_config(5, 0.75, 0.6, TRUE, 8); d0 <- mcg_config(5, 0.75, 0.6, TRUE)
  mcg_arm_stamp_config(dir, d8, a = 0.10)
  persist_detections(dir, "P1", NA, data.frame(x = 1, y = 2, z = 3))
  full <- jsonlite::read_json(stamp, simplifyVector = TRUE)
  pre <- c(d0[1:4], list(a = 0.10, radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                         cover_height = MCG_COVER_HEIGHT))
  # every field agrees, the label does not: a library that labelled another behaviour
  # (here a field `crown_top` this library does not have) wrote it
  for (lab in c("z5_s0.75_c0.6_e1_d8.0", "z5_s0.75_c0.6_e1", "z5_s0.75_c0.6_e1_d8_x30")) {
    write_stamp(utils::modifyList(full, list(label = lab)), stamp)
    expect_error(mcg_arm_stamp_config(dir, d8, a = 0.10), "another configuration")
    expect_identical(jsonlite::read_json(stamp, simplifyVector = TRUE)$label, lab)
  }
  for (lab in c("z5_s0.75_c0.6_e1_x30", "stock")) {
    write_stamp(c(pre, list(crown_top = 30, label = lab)), stamp)
    expect_error(mcg_arm_stamp_config(dir, d0, a = 0.10), "another configuration")
    write_stamp(c(pre, list(spacing_min = 0, crown_res = MCG_CROWN_RES, crown_ws = MCG_CROWN_WS,
                            label = lab)), stamp)
    expect_error(mcg_arm_stamp_config(dir, d0, a = 0.10), "another configuration")
  }
  # the same stamps with the configuration's own label are accepted
  write_stamp(c(pre, list(label = "z5_s0.75_c0.6_e1")), stamp)
  expect_silent(mcg_arm_stamp_config(dir, d0, a = 0.10))
  write_stamp(full, stamp)
  expect_silent(mcg_arm_stamp_config(dir, d8, a = 0.10))
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
  expect_identical(names(cell), c("det", "row", "cover", "closed", "top_height", "crown_spacing",
                                  "spaced"))
  expect_identical(cell$top_height, mcg_top_height(las))
  expect_identical(cell$crown_spacing, mcg_crowns(las)$spacing)
  expect_true(is.finite(cell$crown_spacing) && cell$crown_spacing > 0)
  expect_true(cell$spaced)                       # no spacing condition: every stand is spaced
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

test_that("in a closed stand the spacing condition switches the share gate and nothing else", {
  las <- synth_closed_stand(1)
  cell <- function(cfg) mcg_arm_cell(las, synth_closed_stems(), synth_closed_meta(), cfg)
  cfg <- function(d, s = 0.75) mcg_config(5, s, 0.6, TRUE, d)
  gated <- cell(cfg(0))                                # share gate in every closed stand
  ungated <- cell(cfg(0, s = 0))                       # the same without the share gate
  sp <- gated$crown_spacing
  top <- gated$top_height
  expect_identical(sp, mcg_crowns(las)$spacing)
  expect_identical(ungated$crown_spacing, sp)
  expect_identical(top, mcg_top_height(las))
  expect_true(is.finite(sp) && sp > 0)
  # the stand's top height lies above its crown spacing, so a threshold between the two
  # tells the spacing from the height
  expect_gt(top, sp + 1)
  expect_true(gated$closed); expect_true(gated$spaced); expect_true(ungated$spaced)
  expect_false(isTRUE(all.equal(gated$det, ungated$det)))   # the gate removes a deeper peak
  # spacing_min above the stand's crown spacing: not spaced, no share gate; the floor and
  # the exemption still apply
  for (d in c(sp + 0.01, (sp + top) / 2, top + 1, sp + 20)) {
    c1 <- cell(cfg(d))
    expect_identical(c1$det, ungated$det)
    expect_true(c1$closed); expect_false(c1$spaced)
    expect_identical(c1$crown_spacing, sp); expect_identical(c1$top_height, top)
    expect_identical(c1$row$n_det, ungated$row$n_det); expect_identical(c1$row$TP, ungated$row$TP)
  }
  # spacing_min at or below it: spaced, the share gate as without a spacing condition
  for (d in c(sp, sp - 0.01, 1)) {
    c1 <- cell(cfg(d))
    expect_identical(c1$det, gated$det)
    expect_true(c1$closed); expect_true(c1$spaced)
    expect_identical(c1$row$n_det, gated$row$n_det); expect_identical(c1$row$TP, gated$row$TP)
  }
  # an open stand is not gated whatever its spacing
  for (d in c(1, sp + 1)) {
    open <- cell(mcg_config(5, 0.75, 0.9, TRUE, d))
    expect_false(open$closed); expect_identical(open$spaced, sp >= d)
    expect_identical(open$det, cell(mcg_config(5, 0, 0.9, FALSE))$det)
  }
})

test_that("an unknown crown spacing fails a closed stand's cell only under a spacing condition", {
  las <- synth_closed_stand(1)
  df <- las@data[, c("X", "Y", "Z", "ReturnNumber"), with = FALSE]
  df$ReturnNumber[df$ReturnNumber == 1L] <- 3L         # no first return: no cover, no spacing
  low <- suppressWarnings(LAS(df)); st_crs(low) <- 32611L
  expect_true(is.na(mcg_crowns(low)$spacing))
  cell <- function(las, cfg) mcg_arm_cell(las, synth_closed_stems(), synth_closed_meta(), cfg)
  # cover_min 0 makes every stand closed without reading the cover
  expect_error(cell(low, mcg_config(5, 0.75, 0, TRUE, 8)), "needs the clip's crown spacing")
  ok <- cell(low, mcg_config(5, 0.75, 0, TRUE))
  expect_identical(ok$crown_spacing, NA_real_); expect_true(ok$spaced)
  # a strip 3 m wide: its cover is known, but its surface is too narrow for one crown window
  strip <- lidR::filter_poi(las, X >= 6 & X < 9)
  expect_gt(mcg_canopy_cover(strip), 0.6)
  expect_identical(mcg_crowns(strip)$spacing, NA_real_)
  expect_error(cell(strip, mcg_config(5, 0.75, 0.6, TRUE, 8)), "needs the clip's crown spacing")
  # ... which decides nothing in an open stand: the spacing stays unknown
  open <- cell(strip, mcg_config(5, 0.75, 0.9, TRUE, 8))
  expect_false(open$closed); expect_identical(open$spaced, NA)
  expect_gt(nrow(open$det), 0)
  expect_identical(open$det, cell(strip, mcg_config(5, 0, 0.9, FALSE))$det)
})

test_that("a configuration that needs return numbers fails its cell instead of skipping it", {
  las <- stand(1, with_rn = FALSE)
  expect_error(mcg_arm_cell(las, stems(), meta(), GATED), "ReturnNumber")
  ok <- mcg_arm_cell(las, stems(), meta(), mcg_config(zmin = 5))
  expect_true(is.na(ok$cover))
  expect_identical(ok$crown_spacing, NA_real_); expect_true(ok$spaced)
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
  # a surface without a crown: an infinite spacing, which counts as spaced
  expect_identical(cell$crown_spacing, Inf)
  expect_true(mcg_arm_cell(flat, stems(), meta(), mcg_config(5, 0.75, 0, TRUE, 9))$spaced)
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
    expect_identical(cell$top_height, NA_real_)
    expect_identical(cell$crown_spacing, NA_real_)
  }
  expect_true(mcg_arm_cell(empty, stems(), meta(), GATED)$spaced)       # no spacing condition
  expect_identical(mcg_arm_cell(empty, stems(), meta(), MCG_DECLARED)$spaced, NA)  # unknown
  expect_true(mcg_arm_cell(empty, stems(), meta(), MCG_STOCK)$closed)   # no cover switch
})

## ---- result columns and pooling -------------------------------------------------------------
test_that("results gain tp_core, the stand columns in order and the configuration", {
  las <- stand(1)
  sp <- mcg_crowns(las)$spacing; top <- mcg_top_height(las)
  # a threshold between the stand's crown spacing and its top height: not spaced
  expect_true(sp < 15 && top > 15)
  D15 <- mcg_config(5, 0.75, 0.6, TRUE, 15)
  rows <- do.call(rbind, lapply(c(NA, 4), function(r) {
    cell <- mcg_arm_cell(las, stems(), meta(rung = r), D15)
    cbind(cell$row, cover = cell$cover, closed = cell$closed, top_height = cell$top_height,
          crown_spacing = cell$crown_spacing, spaced = cell$spaced)
  }))
  out <- mcg_arm_finish(rows, D15)
  n <- names(out)
  expect_identical(tail(n, 11), c("tp_core", "cover", "closed", "top_height", "crown_spacing",
                                  "spaced", "zmin", "min_share", "cover_min", "surface_exempt",
                                  "spacing_min"))
  expect_identical(n[1:9], c("site", "plot", "plotType", "detector", "rung", "pdens", "frdens",
                             "chm_res", "n_apex"))
  expect_identical(setdiff(n, names(rows)), c("tp_core", "zmin", "min_share", "cover_min",
                                              "surface_exempt", "spacing_min"))
  # the stand columns move into their order whatever order they come in
  shuffled <- rows[c(rev(c("cover", "closed", "top_height", "crown_spacing", "spaced")),
                     setdiff(names(rows), c("cover", "closed", "top_height", "crown_spacing",
                                            "spaced")))]
  expect_identical(mcg_arm_finish(shuffled, D15), out)
  expect_identical(mcg_arm_finish(data.frame(precision = c(0.5, NA), n_det = c(8L, 0L),
                                             cover = 0.7, closed = TRUE, top_height = 30,
                                             crown_spacing = 9, spaced = TRUE), GATED)$tp_core,
                   c(4, NA))
  expect_identical(out$zmin, c(5, 5)); expect_identical(out$surface_exempt, c(TRUE, TRUE))
  expect_identical(out$spacing_min, c(15, 15))
  expect_identical(out$closed, rep(mcg_canopy_cover(las) >= 0.6, 2))
  expect_identical(out$top_height, rep(top, 2))
  expect_identical(out$crown_spacing, rep(sp, 2))
  expect_identical(out$spaced, c(FALSE, FALSE))          # from the crown spacing, not the height
  expect_identical(out$rung, c("native", "4"))
  expect_identical(mcg_arm_finish(rows, GATED)$spacing_min, c(0, 0))
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
