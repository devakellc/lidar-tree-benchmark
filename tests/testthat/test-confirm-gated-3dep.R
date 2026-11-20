# Unit tests for scripts/confirm_gated_3dep.R (confirmation test C4 of the
# multichm_gated arm on USGS 3DEP clouds): the configuration table, the output
# guard, the clip box and its EPT bounds, the choice of a tile set per plot,
# the PDAL pipeline, the HTTP volume, return-number and density records,
# acquisition dates from GPS time, the frozen-clip path on a synthetic cloud
# (seeded thinning, the no-upsampling guard, the cache), one detected and
# scored cell (stock parity with the package, the cells.csv columns), the rule
# that leaves out clips without return numbers, the stand-state transfer, the
# pooled summary and the harness comparison. Sourcing the script defines its
# helpers without running it (guarded by `if (sys.nframe() == 0L) run_main()`).
# Synthetic data only; no network.
source(file.path("..", "..", "scripts", "confirm_gated_3dep.R"), local = TRUE)

## ---- synthetic data -------------------------------------------------------------------------
TREES <- data.frame(x = c(10, 18, 27, 11, 25, 19), y = c(10, 12, 9, 23, 24, 18),
                    h = c(22, 18, 20, 16, 21, 8), r = c(3.5, 3, 3.2, 2.8, 3.4, 2),
                    cls = c("dominant", "codominant", "dominant", "intermediate",
                            "codominant", "suppressed"))
# A normalized stand of conical crowns (first returns on the crowns, later
# returns inside them, first-return ground hits).
stand <- function(seed = 1) {
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
  df$NumberOfReturns <- 2L
  las <- suppressWarnings(LAS(df))
  st_crs(las) <- 32611L
  las
}
stems <- function() data.frame(E = TREES$x + 0.3, N = TREES$y - 0.2, height = TREES$h,
                               crown_class = TREES$cls, stringsAsFactors = FALSE)
plot_job <- function() list(site = "SYN", plot = "SYN_001", plotType = "tower", cx = 18,
                            cy = 16, half = 20, epsg = 32611L, stems = stems())

# A raw (not normalized) cloud in UTM 11N: a sloping ground with class 2 hits
# and a few conical crowns, every point a single return with a GPS time.
CX <- 500100; CY <- 4100100
raw_cloud <- function(seed = 2, side = 80, dens = 3) {
  set.seed(seed)
  n <- side^2 * dens
  g <- data.frame(X = CX - side / 2 + runif(n, 0, side), Y = CY - side / 2 + runif(n, 0, side))
  g$Z <- 100 + 0.05 * (g$X - CX) + rnorm(n, 0, 0.03); g$Classification <- 2L
  tr <- do.call(rbind, lapply(seq(-30, 30, by = 10), function(dx) {
    m <- 600; d <- 3 * sqrt(runif(m)); a <- runif(m, 0, 2 * pi)
    data.frame(X = CX + dx + d * cos(a), Y = CY + dx / 2 + d * sin(a),
               Z = 100 + 0.05 * dx + 15 * (1 - d / 3) + 2, Classification = 1L)
  }))
  df <- rbind(g, tr)
  df$ReturnNumber <- 1L; df$NumberOfReturns <- 1L
  df$gpstime <- 2.5e8 + seq_len(nrow(df)) * 1e-4
  las <- suppressWarnings(LAS(df))
  st_crs(las) <- 32611L
  las
}
syn_settings <- function(out, rung = 2)
  list(OUT = out, BUFFER = 25, RUNG = rung, SEED_KEY = "3DEP-2", TOL = 4, K = 5)
write_raw <- function(S, site = "SYN", plot = "SYN_002") {
  f <- c3_cloud_file(S, site, plot)
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  writeLAS(raw_cloud(), f)
  f
}
clip_job_of <- function(plot = "SYN_002")
  list(site = "SYN", plot = plot, plotType = "distributed", cx = CX, cy = CY, half = 10,
       epsg = 32611L, tileset = "SYN_TILESET", url = "https://example.invalid/SYN/ept.json",
       gps_adjusted = TRUE)

## ---- configurations and the output guard ------------------------------------------------
test_that("the five configurations are grid rows in the protocol's order", {
  g <- c3_config_table()
  expect_identical(g$label, C3_CONFIGS)
  expect_identical(g$config_id[1], 1L)                     # stock is config_id 1
  d <- g[g$label == mcg_config_label(MCG_DECLARED), ]
  expect_equal(nrow(d), 1L)
  expect_equal(c(d$zmin, d$min_share, d$cover_min, d$spacing_min), c(5, 0.75, 0.6, 8))
  expect_true(d$surface_exempt)
  expect_identical(c3_config_table(c("z5_s0_c0_e0", "stock"))$label, c("z5_s0_c0_e0", "stock"))
  expect_error(c3_config_table(c("stock", "nonsense")), "not grid labels: nonsense")
})

test_that("the output root may not lie in a read-only input tree", {
  expect_error(c3_check_out("/x/work/paper_runs/neon/3dep"), "read-only")
  expect_error(c3_check_out("/x/work/paper_runs_ql2"), "read-only")
  expect_error(c3_check_out("/x/work/neon/frozen_2021/out"), "read-only")
  expect_error(c3_check_out("/x/work/multichm_gated_runs/neon"), "read-only")
  expect_silent(c3_check_out("/x/work/multichm_gated_confirmation/3dep"))
  expect_silent(c3_check_out("/x/work/neon/SOAP/ql2"))
})

## ---- geometry and discovery -------------------------------------------------------------
test_that("the clip box is the core plus the buffer and its EPT bounds enclose it", {
  b <- c3_clip_box(1000, 2000, 20, 25)
  expect_equal(unname(b), c(955, 1955, 1045, 2045))
  b10 <- c3_clip_box(1000, 2000, 10)                       # distributed core, default buffer
  expect_equal(unname(b10[c("xmax")] - b10[c("xmin")]), 70)
  box <- c3_clip_box(297800, 4101500, 10, 25)
  wm <- c3_box_in(box, 32611, 3857)
  wm1 <- c3_box_in(box, 32611, 3857, margin = 1)
  expect_equal(unname(wm1 - wm), c(-1, -1, 1, 1))
  # every corner of the UTM box, in Web Mercator, lies inside the bounds
  corners <- sf::st_coordinates(sf::st_transform(sf::st_cast(c3_box_polygon(box, 32611),
                                                             "POINT"), 3857))
  expect_true(all(corners[, 1] >= wm[["xmin"]] & corners[, 1] <= wm[["xmax"]] &
                    corners[, 2] >= wm[["ymin"]] & corners[, 2] <= wm[["ymax"]]))
  # Web Mercator inflates distances at this latitude (about 1.27 at 37 N)
  expect_gt((wm[["xmax"]] - wm[["xmin"]]) / 70, 1.2)
  expect_identical(c3_bounds_string(c(xmin = 1, ymin = 2, xmax = 3.5, ymax = 4)),
                   "([1.000, 3.500], [2.000, 4.000])")
})

test_that("candidates record which footprints cover a plot's whole clip box", {
  pf <- data.frame(site = "SYN", plot = c("P1", "P2"), cx = c(CX, CX + 5000), cy = CY,
                   half = 20, epsg = 32611L, stringsAsFactors = FALSE)
  box1 <- c3_box_in(c3_clip_box(CX, CY, 20, 25), 32611, 4326)
  big <- sf::st_as_sfc(sf::st_bbox(c(xmin = box1[["xmin"]] - 0.01, ymin = box1[["ymin"]] - 0.01,
                                     xmax = box1[["xmax"]] + 0.01, ymax = box1[["ymax"]] + 0.01),
                                   crs = 4326))
  half_cover <- sf::st_as_sfc(sf::st_bbox(c(xmin = mean(box1[c("xmin", "xmax")]),
                                            ymin = box1[["ymin"]] - 0.01,
                                            xmax = box1[["xmax"]] + 0.01,
                                            ymax = box1[["ymax"]] + 0.01), crs = 4326))
  bnd <- sf::st_sf(name = c("A_2019", "B_2022"), url = c("u/A/ept.json", "u/B/ept.json"),
                   geometry = c(big, half_cover))
  cand <- c3_candidates(pf, bnd, 25)
  expect_equal(nrow(cand), 2L)                             # P2 meets no footprint
  expect_true(all(cand$plot == "P1"))
  expect_identical(cand$covers[cand$name == "A_2019"], TRUE)
  expect_identical(cand$covers[cand$name == "B_2022"], FALSE)
  ch <- c3_choose_tileset(pf, cand)
  expect_identical(ch$tileset, c("A_2019", NA))
  expect_identical(ch$rule[2], "none covers the clip box")
})

test_that("a plot takes the covering tile set ranked first by score_candidate", {
  pf <- data.frame(site = c("SJER", "SJER", "SOAP"), plot = c("S1", "S2", "P1"),
                   stringsAsFactors = FALSE)
  cand <- data.frame(site = c("SJER", "SJER", "SJER", "SOAP"),
                     plot = c("S1", "S1", "S2", "P1"),
                     name = c("CA_FEMAR9Fresno_2_2019", "CA_SierraNevada_11_B22",
                              "CA_SierraNevada_11_B22", "CA_SierraNevada_14_B22"),
                     url = c("f/ept.json", "s11/ept.json", "s11/ept.json", "s14/ept.json"),
                     covers = c(TRUE, TRUE, TRUE, TRUE), stringsAsFactors = FALSE)
  ch <- c3_choose_tileset(pf, cand)
  expect_identical(ch$tileset, c("CA_FEMAR9Fresno_2_2019", "CA_SierraNevada_11_B22",
                                 "CA_SierraNevada_14_B22"))
  expect_identical(ch$others[1], "CA_SierraNevada_11_B22")
  expect_identical(ch$n_covering, c(2L, 1L, 1L))
  # a footprint that does not cover the whole box is never chosen
  cand$covers[1] <- FALSE
  expect_identical(c3_choose_tileset(pf, cand)$tileset[1], "CA_SierraNevada_11_B22")
  # an override applies to every plot of its site
  ov <- c3_choose_tileset(pf, cand, list(SJER = "https://h/X_2020/ept.json"))
  expect_identical(ov$tileset[1:2], c("X_2020", "X_2020"))
  expect_identical(ov$rule[1:2], c("override", "override"))
  expect_identical(ov$tileset[3], "CA_SierraNevada_14_B22")
})

## ---- pull ---------------------------------------------------------------------------------
test_that("the PDAL pipeline drops noise and withheld points and reprojects to the site frame", {
  p <- c3_pdal_pipeline("https://h/X/ept.json", "([0, 1], [2, 3])", "EPSG:32610", "o.laz", 3)
  expect_identical(vapply(p, `[[`, "", "type"),
                   c("readers.ept", "filters.range", "filters.reprojection", "writers.las"))
  expect_identical(p[[1]]$bounds, "([0, 1], [2, 3])")
  expect_identical(p[[1]]$threads, 3L)
  expect_identical(p[[2]]$limits, "Classification![7:7],Classification![18:18],Withheld![1:1]")
  expect_identical(p[[3]]$out_srs, "EPSG:32610")
  expect_identical(c(p[[4]]$minor_version, p[[4]]$dataformat_id, p[[4]]$global_encoding),
                   c(4L, 6L, 17L))
  j <- jsonlite::toJSON(p, auto_unbox = TRUE)
  expect_match(as.character(j), '"filename":"o.laz"')
})

test_that("the HTTP volume sums response lengths and counts GET requests", {
  log <- c("* Connected", "> GET /b/X/ept.json HTTP/1.1", "< HTTP/1.1 200 OK",
           "< Content-Length: 2533", "> GET /b/X/ept-data/1-0-0-0.laz HTTP/1.1",
           "< content-length: 100000", "(pdal Debug) Wrote 10 points")
  v <- c3_http_volume(log)
  expect_equal(v[["gets"]], 2)
  expect_equal(v[["bytes"]], 102533)
  expect_equal(c3_http_volume(character())[["bytes"]], 0)
})

## ---- clip records -------------------------------------------------------------------------
test_that("return numbers are populated when at least 99% of the points carry them", {
  expect_true(c3_returns_populated(c(1L, 2L, 1L), c(2L, 2L, 1L)))
  expect_false(c3_returns_populated(c(0L, 0L), c(0L, 0L)))       # a cloud without them
  expect_false(c3_returns_populated(c(1L, 0L), c(1L, 1L)))
  expect_false(c3_returns_populated(c(1L, NA), c(1L, 1L)))
  expect_false(c3_returns_populated(integer(), integer()))
  # a few invalid records (0.5%) do not unpopulate a cloud; 2% do
  rn <- rep(1L, 1000); nr <- rep(1L, 1000)
  rn[1:3] <- 0L; nr[4:5] <- 0L
  expect_true(c3_returns_populated(rn, nr))
  rn[1:20] <- 0L
  expect_false(c3_returns_populated(rn, nr))
  # a return number above the number of returns is counted, not refused
  s <- c3_clip_stats(c(1L, 2L, 3L, 1L, 0L), c(2L, 2L, 2L, 1L, 0L), area = 2)
  expect_false(s$returns_populated)                        # 1 of 5 invalid
  expect_equal(c(s$n_return_gt_number, s$n_return_zero, s$n_number_zero), c(1, 1, 1))
  expect_equal(s$share_valid_returns, 0.8)
  s <- c3_clip_stats(c(1L, 2L, 3L, 1L), c(2L, 2L, 2L, 1L), area = 2)
  expect_true(s$returns_populated)
  expect_equal(c(s$pdens, s$frdens, s$returns_per_pulse, s$mean_returns_first), c(2, 1, 2, 1.5))
  z <- c3_clip_stats(c(0L, 0L), c(0L, 0L), area = 1)
  expect_false(z$returns_populated)
  expect_true(is.na(z$returns_per_pulse))
})

test_that("acquisition dates come from adjusted standard GPS time", {
  t <- function(s) as.numeric(difftime(as.POSIXct(s, tz = "UTC"), C3_GPS_EPOCH,
                                       units = "secs")) - 1e9
  g <- c(t("2019-12-12 18:30:00"), t("2019-12-12 19:00:00"), t("2022-07-03 10:00:00"))
  d <- c3_gps_dates(g)
  expect_identical(format(d), c("2019-12-12", "2019-12-12", "2022-07-03"))
  s <- c3_date_summary(d)
  expect_identical(s$acq_first, "2019-12-12"); expect_identical(s$acq_last, "2022-07-03")
  expect_identical(s$acq_years, "2019;2022"); expect_identical(s$acq_days, 2L)
  expect_null(c3_gps_dates(g, adjusted = FALSE))           # GPS week time: no date
  expect_true(is.na(c3_date_summary(NULL)$acq_years))
})

## ---- the frozen-clip path on a synthetic cloud --------------------------------------------
test_that("a plot's clips follow the frozen-clip definition with a recorded seed", {
  out <- tempfile("c3clips"); S <- syn_settings(out)
  raw <- write_raw(S)
  r <- as.data.frame(c3_clip_job(clip_job_of(), S))
  expect_identical(r$rung, C3_VARIANTS)
  expect_identical(r$status, c("ok", "ok"))
  expect_equal(r$clip_half, c(35, 35))
  expect_equal(r$seed[2], seed_for("SYN", "SYN_002", "3DEP-2"))
  expect_true(is.na(r$seed[1]))
  expect_identical(r$decimation, c("none", "homogenize(density = 2, res = 5)"))
  expect_true(r$pdens[1] > 2 && r$pdens[2] <= 2.2)
  expect_true(all(as.logical(r$returns_populated)))
  # 2.5e8 s of adjusted standard GPS time: 1.25e9 s after the GPS epoch
  expect_identical(r$acq_first, rep(format(as.Date(C3_GPS_EPOCH + 1.25e9, tz = "UTC")), 2))
  nat <- readLAS(r$normalized[1])
  expect_true(all(nat$X >= CX - 35 & nat$X <= CX + 35 & nat$Y >= CY - 35 & nat$Y <= CY + 35))
  expect_lt(abs(stats::median(nat$Z[nat$Classification == 2L])), 0.05)   # height-normalised
  expect_true(all(nat$Z >= -1 & nat$Z < 80))
  # the cache is reused, and a fresh build gives the same bytes (seeded thinning)
  h1 <- digest::digest(file = r$normalized[2], algo = "sha256")
  r2 <- as.data.frame(c3_clip_job(clip_job_of(), S))
  expect_equal(r2$pdens, r$pdens)
  unlink(file.path(out, "clips"), recursive = TRUE)
  r3 <- as.data.frame(c3_clip_job(clip_job_of(), S))
  expect_identical(digest::digest(file = r3$normalized[2], algo = "sha256"), h1)
  unlink(out, recursive = TRUE)
})

test_that("no thinned clip is made at or above the native all-return density", {
  out <- tempfile("c3clips"); S <- syn_settings(out, rung = 50)
  write_raw(S)
  r <- as.data.frame(c3_clip_job(clip_job_of(), S))
  expect_identical(r$status, c("ok", "upsampled"))
  expect_false(dir.exists(c3_clip_dir(S, "SYN", "SYN_002", "3dep_dec2")))
  unlink(out, recursive = TRUE)
})

## ---- cells --------------------------------------------------------------------------------
test_that("a cell is detected and scored as the calibration study scores one", {
  las <- stand()
  j <- plot_job()
  cfgs <- c3_config_table()
  offs <- mcg_null_offsets(j$site, j$plot, j$half, tol = 4, k = 3)
  cell <- c3_cell(las, frdens = 5, pdens = 12.5, j = j, rung = "3dep_native", cfgs = cfgs,
                  offs = offs, tol = 4)
  expect_true(cell$parity)                                 # stock == lidRplugins::multichm
  expect_equal(cell$res, 0.5)
  expect_identical(names(cell$rows), C3_CELL_COLS)
  expect_identical(cell$rows$config, C3_CONFIGS)
  expect_true(all(cell$rows$rung == "3dep_native"))
  expect_equal(cell$rows$n_ref, rep(nrow(TREES), 5))
  expect_equal(cell$rows$n_dominant[1], 2)
  stock <- mcg_apply(mcg_prepare(las, 0.5, 0.10), MCG_STOCK)
  ref <- mcg_score_cell(j$stems, stock, j$cx, j$cy, j$half, offs, tol = 4)
  expect_equal(unlist(cell$rows[1, MCG_COUNT_COLS]), unlist(ref[1, MCG_COUNT_COLS]))
  expect_equal(c3_res(8), 0.25); expect_equal(c3_res(7.99), 0.5)
})

test_that("a clip without return numbers is left out for every configuration", {
  out <- tempfile("c3score"); S <- syn_settings(out)
  S$K <- 3
  las <- stand()
  f <- file.path(out, "syn.laz"); dir.create(out); writeLAS(las, f)
  j <- plot_job()
  j$clips <- data.frame(rung = c("3dep_native", "3dep_dec2"), normalized = f, frdens = 5,
                        pdens = 12.5, returns_populated = c(TRUE, FALSE),
                        stringsAsFactors = FALSE)
  res <- c3_score_job(j, S, c3_config_table())
  expect_identical(unique(res$rows$rung), "3dep_native")
  expect_equal(nrow(res$rows), 5L)
  expect_identical(res$meta$scored, c(TRUE, FALSE))
  expect_identical(res$meta$reason[2], "return numbers not populated")
  expect_true(file.exists(file.path(out, "candidates", "SYN__SYN_001__3dep_native.rds")))
  idx <- data.frame(site = "SYN", plot = c("A", "B"), rung = "3dep_dec2", status = c("ok", "ok"),
                    returns_populated = c("TRUE", "FALSE"), stringsAsFactors = FALSE)
  expect_identical(c3_no_returns(idx)$plot, "B")
  unlink(out, recursive = TRUE)
})

test_that("detections convert and compare as the calibration study's helpers do", {
  a <- data.frame(x = c(1, 2), y = c(3, 4), z = c(5, 6))
  expect_true(c3_same_dets(a, a[2:1, ]))
  expect_false(c3_same_dets(a, a[1, ]))
  b <- a; b$z[1] <- 5 + 1e-3
  expect_false(c3_same_dets(a, b)); expect_true(c3_same_dets(a, b, tol = 1e-2))
  expect_equal(nrow(c3_tops_to_det(NULL)), 0L)
  sh <- c3_deep_shares(data.frame(layer = c(1L, 2L, 2L, 3L), share = c(1, 0.8, 0.5, NA)))
  expect_equal(c(sh$n_cand, sh$n_deep), c(4, 3))
  expect_equal(sh$deep_share_ge, 1 / 3)
  expect_equal(sh$deep_share_median, 0.65)
})

## ---- summaries ----------------------------------------------------------------------------
test_that("closed and widely spaced states are compared with the 2021 clip of the same rung", {
  st <- c3_state(c(0.7, 0.5, NA, 0.6), c(9, 9, 9, 7.9))
  expect_identical(st$closed, c(TRUE, FALSE, FALSE, TRUE))
  expect_identical(st$spaced, c(TRUE, TRUE, TRUE, FALSE))
  expect_identical(st$gated, c(TRUE, FALSE, FALSE, FALSE))
  clips <- data.frame(site = c("SOAP", "SOAP", "TEAK", "SOAP"), plot = c("a", "b", "c", "a"),
                      rung = c("3dep_native", "3dep_native", "3dep_native", "3dep_dec2"),
                      scored = TRUE, cover = c(0.7, 0.4, 0.8, 0.7),
                      crown_spacing = c(9, 6, 8.5, 7),
                      neon_native_cover = c(0.65, 0.7, 0.8, 0.65),
                      neon_native_crown_spacing = c(7, 6, 9, 7),
                      neon_rung2_cover = c(0.5, 0.5, 0.5, 0.5),
                      neon_rung2_crown_spacing = c(9, 9, 9, 9), stringsAsFactors = FALSE)
  tr <- c3_transfer(clips)
  soap <- tr[tr$variant == "3dep_native" & tr$scope == "SOAP", ]
  expect_equal(c(soap$plots, soap$closed_3dep, soap$closed_2021, soap$closed_changed),
               c(2, 1, 2, 1))
  expect_equal(c(soap$gated_3dep, soap$gated_2021, soap$gated_changed), c(1, 0, 1))
  ca <- tr[tr$variant == "3dep_native" & tr$scope == "California", ]
  expect_equal(ca$plots, 3)
  dec <- tr[tr$variant == "3dep_dec2" & tr$scope == "SOAP", ]   # against the 2021 thinned rung
  expect_equal(c(dec$closed_3dep, dec$closed_2021, dec$spaced_3dep, dec$spaced_2021),
               c(1, 0, 0, 1))
})

test_that("the summary pools counts by summing them", {
  cnt <- function(ref, det, tp) as.list(c(n_ref = ref, n_over = ref, n_under = 0, n_det = det,
                                          TP = tp, tp_core = tp, tp_over = tp, tp_under = 0,
                                          n_det0 = det, TP0 = 1, tp_core0 = 1, tp_over0 = 1,
                                          tp_under0 = 0))
  rows <- rbind(data.frame(site = "SOAP", plot = "a", rung = "3dep_native", config = "stock",
                           cnt(10, 10, 5)),
                data.frame(site = "TEAK", plot = "b", rung = "3dep_native", config = "stock",
                           cnt(30, 10, 5)))
  s <- c3_summary(rows)
  ca <- s[s$scope == "California", ]
  expect_equal(ca$n_plots, 2L)
  expect_equal(ca$recall, 10 / 40)                         # not the mean of 0.5 and 1/6
  expect_equal(ca$precision, 10 / 20)
  expect_equal(nrow(s[s$scope == "Washington", ]), 0L)
  expect_true(all(c("cF1", "F1", "null_F1") %in% names(s)))
})

test_that("the harness compares every count and feature with the calibration cells", {
  mk <- function(v) cbind(data.frame(site = "SOAP", plot = "a", rung = "native",
                                     config = c("stock", "z5_s0_c0_e0"), cover = 0.7,
                                     top_height = 30, crown_spacing = 8.2, pdens = 20,
                                     frdens = 10),
                          as.data.frame(stats::setNames(as.list(rep(v, length(MCG_COUNT_COLS))),
                                                        MCG_COUNT_COLS)))
  ref <- mk(3)
  same <- c3_compare_cells(mk(3), ref)
  expect_true(all(same$found)); expect_equal(same$max_abs_diff, c(0, 0))
  off <- mk(3); off$TP0[2] <- 3.5
  cmp <- c3_compare_cells(off, ref)
  expect_equal(cmp$max_abs_diff[cmp$config == "z5_s0_c0_e0"], 0.5)
  expect_identical(cmp$cols_differing[cmp$config == "z5_s0_c0_e0"], "TP0")
  miss <- mk(3); miss$plot <- "b"
  expect_false(any(c3_compare_cells(miss, ref)$found))
  pl <- list(list(site = "S1", plot = "S1_1"), list(site = "S1", plot = "S1_2"),
             list(site = "S2", plot = "S2_1"))
  expect_equal(length(c3_harness_plots(pl, "ALL")), 3L)
  expect_identical(vapply(c3_harness_plots(pl, "1"), `[[`, "", "plot"), c("S1_1", "S2_1"))
  expect_identical(vapply(c3_harness_plots(pl, "S1_2"), `[[`, "", "plot"), "S1_2")
})
