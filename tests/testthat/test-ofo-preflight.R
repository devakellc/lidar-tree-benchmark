source(file.path("..", "..", "scripts", "ofo_preflight_lib.R"), local = TRUE)
suppressMessages({ library(data.table); library(sf) })

sq <- function(x0, y0, x1, y1) {
  st_polygon(list(matrix(c(x0, y0, x1, y0, x1, y1, x0, y1, x0, y0), ncol = 2, byrow = TRUE)))
}

test_that("survey dates parse YYYYMMDD, YYYYMM and YYYY stored as reals", {
  x <- c(20150414, 201910, 2008, NA, 123)
  expect_identical(ofo_survey_year(x), c(2015L, 2019L, 2008L, NA, NA))
  expect_identical(format(ofo_survey_date(x)),
                   c("2015-04-14", "2019-10-15", "2008-07-01", NA, NA))
  expect_identical(ofo_survey_year(2.0220701e7), 2022L)
})

test_that("live floor, live status and growth form follow the protocol", {
  expect_equal(ofo_live_floor(c(10, 25.4, NA, 5), c(NA, 12.7, NA, NA)), c(10, 12.7, NA, 5))
  expect_identical(ofo_is_live(c("L", "M", "D", "0", NA)), c(TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_identical(ofo_is_tree(c("tree", "intermediate", NA, "shrub")),
                   c(TRUE, TRUE, TRUE, FALSE))
  expect_equal(ofo_ref_floor(c(5, 10.2, 25.4, 12.5, NA, 10.2), c("A", "B", "C", "D", NA, NA)),
               c(10, 10, 25.4, 12.5, 10, 10))
  f <- ofo_tree_flags(c("L", "L", "L", "D", "L"), c("tree", "shrub", NA, "tree", "tree"),
                      c(12, 30, 10, 40, NA), c(TRUE, TRUE, FALSE, TRUE, TRUE), 10)
  expect_identical(f$wref, c(TRUE, FALSE, TRUE, FALSE, FALSE))
  expect_identical(f$ref, c(TRUE, FALSE, FALSE, FALSE, FALSE))
})

test_that("group edges sit at 10.2 cm and a 0.90 height share", {
  expect_identical(ofo_heights_measured(c(0.9, 9 / 10, 0.8999, NA)), c(TRUE, TRUE, FALSE, FALSE))
  s <- rep("none", 5)
  expect_identical(ofo_group(s, c(10.2, 10.2, 10.21, 10.21, 0), c(TRUE, FALSE, TRUE, FALSE, TRUE)),
                   c("A", "B", "C", "D", "A"))
  expect_identical(ofo_group(c("not_exhaustive", "none"), c(5, NA), c(TRUE, TRUE)),
                   c(NA_character_, NA_character_))
  # Share over live stems >= 10 cm; over all live stems when none has a dbh.
  expect_equal(ofo_height_share(c(TRUE, TRUE, TRUE, FALSE), c(12, 30, 5, 40),
                                c(10, NA, NA, 20)), 0.5)
  expect_equal(ofo_height_share(c(TRUE, TRUE, TRUE), c(NA, NA, NA), c(5, 6, NA)), 2 / 3)
  expect_true(is.na(ofo_height_share(c(FALSE, FALSE), c(20, 30), c(10, 12))))
})

test_that("the screen takes the first failing rule in the protocol's order", {
  sc <- ofo_screen(project_name = c("NEON2023", "X", "X", "X", "X", "X"),
                   hyperplot = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE),
                   exhaustive = c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE),
                   status_recorded = c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE),
                   live_floor = c(NA, NA, NA, NA, NA, 10))
  expect_identical(sc, c("in_benchmark", "nested_hyperplot", "not_exhaustive", "no_status",
                         "no_diameter_floor", "none"))
  expect_identical(ofo_screen("X", FALSE, NA, TRUE, 10), "not_exhaustive")
})

test_that("plot inventory counts stems and assigns screens and groups", {
  plots <- data.table(plot_id = c("0001", "0002", "0003"), project_name = "P",
                      hyperplot = FALSE, exhaustive_survey = TRUE,
                      min_dbh = c(10.2, 25.4, 10), min_dbh_live = c(NA, NA, NA))
  trees <- data.table(
    plot_id = c(rep("0001", 10), rep("0002", 4), rep("0003", 2)),
    dbh = c(rep(20, 9), 5, 30, 30, 26, 12, 15, 15),
    height = c(rep(15, 9), NA, 20, NA, NA, NA, 10, 10),
    live_dead = c(rep("L", 8), "D", "L", "L", "M", "L", "L", NA, NA),
    growth_form = c(rep("tree", 7), "shrub", "tree", "tree", "tree", "tree", NA, "tree",
                    "tree", "tree"),
    crown_position = c(rep(3, 4), rep(NA, 6), 2, 0, 5, 4, NA, NA),
    inside = c(rep(TRUE, 6), FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE))
  I <- ofo_plot_inventory(plots, trees)
  setkey(I, plot_id)
  # 0001: 8 live >= 10 cm, all measured; ref drops the outside tree and shrub.
  expect_equal(I["0001", n_live_dbh10], 8L)
  expect_equal(I["0001", height_share], 1)
  expect_equal(I["0001", n_ref], 6L)
  # A group A/B plot gates at 10 cm even with a 10.2 cm stated floor.
  expect_equal(I["0001", ref_floor_cm], 10)
  expect_equal(I["0002", ref_floor_cm], 25.4)
  expect_equal(I["0001", crown_position_share], 4 / 8)
  expect_identical(I["0001", group], "A")
  # 0002: floor 25.4 -> group C/D; one of four live stems measured -> D.
  expect_equal(I["0002", height_share], 0.25)
  expect_identical(I["0002", group], "D")
  expect_equal(I["0002", n_ref], 3L)
  expect_equal(I["0002", crown_position_share], 3 / 4)
  # 0003: no live/dead status at all.
  expect_identical(I["0003", screen], "no_status")
  expect_true(is.na(I["0003", group]))
})

test_that("each project takes the zone of its median plot longitude", {
  expect_identical(ofo_utm_epsg(c(-120, -120.0001, -119.9, -123, -117.5)),
                   c(32611L, 32610L, 32611L, 32610L, 32611L))
  P <- data.table(project_name = c(rep("EAST", 3), rep("WEST", 3)),
                  plot_lon = c(-120.3, -119.9, -119.8, -120.3, -120.2, -119.9))
  F <- ofo_project_frames(P)
  expect_identical(F[project_name == "EAST", epsg], 32611L)
  expect_identical(F[project_name == "WEST", epsg], 32610L)
  expect_equal(nrow(F), 2L)
})

test_that("WESM names resolve with the exploratory check's fallbacks", {
  W <- data.table(workunit = c("A_1", "B_2", "C_2015"), project = c("PA", "PB", "PC"),
                  ql = c("QL 1", "QL 2", "QL 1"), collect_start = c("2020/01/01", "2018/07/01",
                                                                     "2015/12/29"),
                  collect_end = c("2020/02/01", "2018/08/01", "2016/02/14"))
  m <- ofo_match_wesm(c("A_1", "USGS_LPC_B_2", "USGS_LPC_C_2015_LAS_2017", "Zzz"), W)
  setkey(m, ept)
  expect_identical(m[c("A_1", "USGS_LPC_B_2", "USGS_LPC_C_2015_LAS_2017", "Zzz"), wesm_rule],
                   c("workunit", "stripped", "prefix", "none"))
  expect_identical(m["USGS_LPC_C_2015_LAS_2017", workunit], "C_2015")
  expect_equal(ofo_ql_num(c("QL 1", "QL 0", "QL 2/QL 1", "Other", "QL 1/Other", NA)),
               c(1, 0, 2, NA, NA, NA))
  expect_identical(ofo_gap_window(c(2022, 2021, 2016), c("2021/11/03", "2020/06/02", "2018/01/01"),
                                  c("2021/12/05", "2022/09/07", "2018/02/01")), c(1L, 0L, 2L))
})

test_that("flights rank by QL, gap, later end, name and drop work-unit mirrors", {
  C <- data.table(
    plot_id = "0001",
    ept = c("USGS_LPC_X_2018", "X_2018", "Y_2021", "Z_2021", "W_2020", "Q_2020", "R_2019",
            "O_2020", "T_2021"),
    workunit = c("X_2018", "X_2018", "Y_2021", "Z_2021", "W_2020", "Q_2020", "R_2019", "O_2020",
                 "T_2021"),
    ql = c("QL 1", "QL 1", "QL 1", "QL 1", "QL 0", "QL 2", "QL 3", "Other", "QL 1"),
    collect_end = c("2018/09/01", "2018/09/01", "2021/07/01", "2021/08/01", "2020/06/01",
                    "2020/06/01", "2019/06/01", "2020/06/01", "2021/07/01"),
    gap_window_years = c(2L, 2L, 0L, 0L, 1L, 0L, 0L, 0L, 0L))
  R <- ofo_rank_flights(C)
  setkey(R, ept)
  expect_true(R["USGS_LPC_X_2018", mirror])
  expect_false(R["X_2018", mirror])
  ranked <- R[!is.na(rank)][order(rank), ept]
  # QL 0 first; Z (later end) before Y; Y before T on work-unit name; QL 2 last.
  expect_identical(ranked, c("W_2020", "Z_2021", "T_2021", "Y_2021", "X_2018", "Q_2020"))
  expect_true(all(is.na(R[c("R_2019", "O_2020", "USGS_LPC_X_2018"), rank])))
  # A measured flight year takes precedence over the work-unit window.
  C2 <- C[ept %in% c("Y_2021", "Z_2021")][, gap_flight_years := c(0L, 1L)]
  expect_identical(ofo_rank_flights(C2)[order(rank), ept], c("Y_2021", "Z_2021"))
  # The mirror kept is the one named as the work unit, whatever the order.
  R3 <- ofo_rank_flights(C[c(2, 1)])
  expect_identical(R3[mirror == FALSE, ept], "X_2018")
})

test_that("GPS times give UTC dates; week seconds give none", {
  epoch <- as.POSIXct("1980-01-06", tz = "UTC")
  t_of <- function(s) as.numeric(difftime(as.POSIXct(s, tz = "UTC"), epoch, units = "secs")) - 1e9
  expect_identical(format(ofo_gps_date(320167585.5)), "2021-11-05")
  # 10 s past midnight on the GPS clock is still the previous UTC day (18 leap s).
  expect_identical(format(ofo_gps_date(t_of("2021-11-06 00:00:10"))), "2021-11-05")
  expect_identical(format(ofo_gps_date(t_of("2021-11-06 00:00:20"))), "2021-11-06")
  expect_true(all(is.na(ofo_gps_date(c(345600, 999999, NA)))))
})

test_that("coverage counts 5 m cells of the 25 m buffer holding a return", {
  poly <- st_sfc(sq(0, 0, 100, 100), crs = 32611)
  g <- expand.grid(x = seq(-40, 49.5, by = 1), y = seq(-40, 140, by = 1))
  cv <- ofo_coverage_share(g$x, g$y, poly)
  expect_equal(cv$share, 0.5)
  expect_equal(ofo_coverage_share(c(-40, 140), c(-40, 140), poly)$share, 0)
  full <- expand.grid(x = seq(-40, 140, by = 2), y = seq(-40, 140, by = 2))
  expect_equal(ofo_coverage_share(full$x, full$y, poly)$share, 1)
})

test_that("admission returns the logical and the reasons in contract order", {
  a <- ofo_flight_admission(
    cloud_status = c("ok", "ok", "empty", "no_candidate", "ok", "failed", "ok"),
    ql = c("QL 1", "QL 2", "QL 1", NA, "QL 0", "QL 2", "QL 1"),
    gap_years = c(4, 5, NA, NA, NA, NA, 0),
    coverage_share = c(0.99, 0.98, NA, NA, 1, NA, 0.9899),
    span_days = c(365, 366, NA, NA, NA, NA, 1),
    flown_from = c("2021-11-05", "2021-11-05", NA, NA, NA, NA, "2021-11-05"))
  expect_identical(a$flight_admitted, c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(a$flight_reason, c("", "quality_level;gap;coverage;span", "no_public_cloud",
                                      "no_public_cloud", "no_flight_date",
                                      "no_public_cloud;quality_level", "coverage"))
})

test_that("geometry audit measures stems outside, duplicates and overlapping plots", {
  polys <- st_sf(plot_id = c("P1", "P2", "P3"),
                 geometry = st_sfc(sq(0, 0, 20, 20), sq(19, 0, 40, 20), sq(-10, 0, 0.04, 20),
                                   crs = 32611))
  xy <- data.frame(plot_id = "P1", x = c(5, 5, 10, 20.5, 25, 10), y = c(5, 5, 10, 10, 10, 20))
  pts <- st_as_sf(xy, coords = c("x", "y"), crs = 32611)
  pos <- ofo_tree_position(pts, polys)
  expect_identical(pos$inside, c(TRUE, TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_equal(pos$outside_m, c(0, 0, 0, 0.5, 5, 0))
  ov <- ofo_plot_overlaps(polys, min_area = 1)
  expect_identical(unname(ov), c("P2", "P1", ""))
  trees <- data.table(xy, pos, wref = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE))
  plots <- data.table(plot_id = c("P1", "P2", "P3"), project_name = "PR", polygon_valid = TRUE,
                      polygon_area_m2 = c(400, 420, 200.8), plot_area_ha = c(0.04, 0.04, 0.02),
                      hyperplot = FALSE, subplots = c(FALSE, TRUE, FALSE), n_ref = c(3L, 0L, 0L),
                      overlaps_plots = unname(ov))
  G <- ofo_geometry_audit(plots, trees)
  setkey(G, plot_id)
  expect_equal(G["P1", share_outside], 2 / 6)
  expect_equal(G["P1", share_outside_1m], 1 / 6)
  expect_equal(G["P1", max_outside_m], 5)
  expect_equal(G["P1", ref_share_inside_1m], 4 / 5)
  expect_identical(G["P1", n_duplicate_xy], 1L)
  expect_false(G["P1", geometry_consistent])
  expect_true(is.na(G["P2", geometry_consistent]))
  expect_equal(G["P2", area_ratio], 1.05)
  B <- ofo_geometry_by_project(G, trees)
  expect_equal(B$n_plots, 3L)
  expect_equal(B$n_plots_overlapping, 2L)
  expect_equal(B$ref_share_inside_1m, 4 / 5)
  expect_equal(B$n_geometry_held, 1L)
})

test_that("coordinate decimals give the stored positional step", {
  expect_lt(ofo_coord_step_m(c(-120.1234567, -120.1234561), c(39.12345678, 39.1234567)), 0.02)
  step <- ofo_coord_step_m(c(-124.035, -124.034), c(47.57525, 47.57511))
  expect_equal(step, 0.001 * 111320 * cos(47.57518 * pi / 180), tolerance = 1e-4)
})

test_that("only CC BY 4.0, CC0 1.0 and public-domain plots are redistributable", {
  expect_identical(ofo_redistributable(c("CC BY 4.0", "CC0 1.0", "Public domain", "CC BY SA 4.0",
                                         "CC BY NC SA 4.0", NA, " cc by 4.0 ")),
                   c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE))
})

test_that("the PDAL pipeline crops in the frame after reprojecting from the resource SRS", {
  box <- c(500000, 4000000, 500100, 4000100)
  b <- ofo_bounds_in_srs(box, 32611, "EPSG:3857")
  back <- st_bbox(st_transform(st_as_sfc(b), 32611))
  expect_true(back[["xmin"]] <= box[1] && back[["ymin"]] <= box[2] &&
                back[["xmax"]] >= box[3] && back[["ymax"]] >= box[4])
  p <- ofo_pdal_pipeline("https://x/ept.json", b, 32611, box, "out.las")
  expect_identical(vapply(p, `[[`, "", "type"), c("readers.ept", "filters.expression",
                                                  "filters.reprojection", "filters.crop",
                                                  "writers.las"))
  expect_identical(p[[3]]$out_srs, "EPSG:32611")
  expect_identical(p[[4]]$bounds, "([500000.000, 500100.000], [4000000.000, 4000100.000])")
  # Both classes must go: a filters.range list on one dimension would OR them.
  expect_identical(p[[2]]$expression, "Classification != 7 && Classification != 18")
  expect_equal(c(p[[5]]$offset_x, p[[5]]$offset_y, p[[5]]$scale_x), c(500000, 4000000, 0.01))
  expect_null(p[[5]]$compression)
  z <- ofo_pdal_laz_pipeline("out.las", "out.laz", box)
  expect_identical(z[[2]]$dataformat_id, 1)
  expect_identical(z[[2]]$compression, "laszip")
  expect_identical(z[[2]]$global_encoding, 1L)
  expect_identical(ofo_pdal_laz_pipeline("a", "b", box, FALSE)[[2]]$global_encoding, 0L)
})

test_that("stored polygon WKT round-trips to the frame polygon within 1e-6 m", {
  ring <- function(lon, lat, r) {
    a <- seq(0, 2 * pi, length.out = 37)
    m <- cbind(lon + r * cos(a), lat + 0.8 * r * sin(a)); m[37, ] <- m[1, ]
    st_polygon(list(m))
  }
  pl <- st_sf(plot_id = c("p1", "p2", "p3"), epsg = c(32610L, 32610L, 32611L),
              geometry = st_sfc(ring(-120.887466512345, 39.494050091234, 0.000317),
                                ring(-121.300123456789, 38.900987654321, 0.0011),
                                ring(-119.700555555555, 37.300444444444, 0.0004), crs = 4326))
  wkt <- ofo_frame_wkt(pl)
  for (i in seq_len(nrow(pl))) {
    want <- st_coordinates(st_transform(pl[i, ], pl$epsg[i]))[, 1:2]
    got <- st_coordinates(st_as_sfc(wkt[i], crs = pl$epsg[i]))[, 1:2]
    expect_lt(max(abs(got - want)), 1e-6)
  }
  # sf's default precision is what moved the boundaries.
  coarse <- st_as_text(st_geometry(st_transform(pl[1, ], 32610L)))
  expect_gt(max(abs(st_coordinates(st_as_sfc(coarse, crs = 32610L))[, 1:2] -
                      st_coordinates(st_transform(pl[1, ], 32610L))[, 1:2])), 1e-3)
})

test_that("withheld returns and classes 7 and 18 are dropped from every measurement", {
  expect_identical(ofo_keep_returns(c(1L, 2L, 7L, 18L, 2L), c(FALSE, TRUE, FALSE, FALSE, NA)),
                   c(TRUE, FALSE, FALSE, FALSE, TRUE))
  expect_identical(ofo_keep_returns(c(1L, 18L)), c(TRUE, FALSE))
  epoch <- as.POSIXct("1980-01-06", tz = "UTC")
  t_of <- function(s) as.numeric(difftime(as.POSIXct(s, tz = "UTC"), epoch, units = "secs")) - 1e9
  poly <- st_sfc(sq(0, 0, 100, 100), crs = 32611)
  kept <- expand.grid(X = seq(0.5, 99.5, by = 1), Y = seq(-39.5, 139.5, by = 1))
  n <- nrow(kept)
  D <- data.table(kept, gpstime = ifelse(seq_len(n) %% 2 == 0, t_of("2021-11-05 18:00:00"),
                                         t_of("2021-11-12 18:00:00")),
                  ReturnNumber = rep(c(1L, 2L), length.out = n),
                  Classification = rep(c(1L, 2L, 1L), length.out = n), Withheld_flag = FALSE)
  # Withheld returns inside the plot on another day, and outside it where no
  # kept return lies (they must cover no cell); a noise return.
  wh <- data.table(X = c(10, 20, 30, -20, 120), Y = c(10, 20, 30, 50, 50),
                   gpstime = t_of("2021-10-01 18:00:00"), ReturnNumber = 1L,
                   Classification = 2L, Withheld_flag = TRUE)
  noise <- data.table(X = 50, Y = 50, gpstime = t_of("2021-12-01 18:00:00"), ReturnNumber = 1L,
                      Classification = 7L, Withheld_flag = FALSE)
  m <- ofo_measure_cloud(rbind(D, wh, noise), poly, 10000, 2022L)
  inside <- D$X > 0 & D$X < 100 & D$Y > 0 & D$Y < 100
  expect_equal(m$n_points_polygon, sum(inside))
  expect_equal(m$n_first_polygon, sum(inside & D$ReturnNumber == 1L))
  expect_equal(m$dens_all, sum(inside) / 10000)
  expect_equal(m$n_points_polygon_raw, sum(inside) + 3 + 1)
  expect_equal(m$n_withheld_polygon, 3)
  expect_equal(m$withheld_share, 3 / (sum(inside) + 4))
  expect_equal(m$n_points, n)
  expect_equal(m$n_points_raw, n + 6)
  expect_equal(m$n_withheld_cloud, 5)
  expect_equal(m$n_ground, sum(D$Classification == 2L))
  expect_equal(c(m$xmin, m$xmax), c(0.5, 99.5))
  # Flight dates: kept returns only, and the days with returns only.
  expect_identical(m$flight_days, "2021-11-05;2021-11-12")
  expect_identical(c(m$flown_from, m$flown_to), c("2021-11-05", "2021-11-12"))
  expect_equal(m$span_days, 7)
  expect_equal(m$gap_years, 1)
  # Coverage from kept returns: the band x < 0 and x > 100 of the buffer is
  # empty although withheld returns lie there.
  cov <- ofo_coverage_share(D$X, D$Y, poly)
  expect_equal(m$coverage_share, cov$share)
  expect_lt(m$coverage_share, 1)
  expect_equal(ofo_flight_days(c(t_of("2021-11-12 01:00:00"), t_of("2021-11-05 23:00:00"),
                                 345600, NA)), as.Date(c("2021-11-05", "2021-11-12")))
})

test_that("a stored LAS keeps its withheld flag and every reader drops those returns", {
  n <- 40
  d <- data.table(X = 500000.5 + rep(0:9, 4) * 10, Y = 4000000.5 + rep(0:3, each = 10) * 10,
                  Z = 100 + seq_len(n), gpstime = 320167585 + seq_len(n), Intensity = 1L,
                  ReturnNumber = 1L, NumberOfReturns = 1L,
                  Classification = rep(c(1L, 2L), n / 2),
                  Withheld_flag = rep(c(FALSE, FALSE, FALSE, TRUE), n / 4))
  las <- suppressMessages(suppressWarnings(lidR::LAS(d)))
  sf::st_crs(las) <- 32611
  f <- tempfile(fileext = ".laz")
  on.exit(unlink(f), add = TRUE)
  suppressWarnings(lidR::writeLAS(las, f))
  # rlas warns that withheld returns are present: they are, by design.
  raw <- data.table::as.data.table(suppressWarnings(rlas::read.las(f, select = "xyztircnw")))
  expect_equal(sum(raw$Withheld_flag), n / 4)              # the flag is stored
  kept <- ofo_read_las(f, "xyzc")
  expect_equal(nrow(kept@data), n - n / 4)
  expect_equal(sort(kept$Z), sort(d$Z[!d$Withheld_flag]), tolerance = 1e-6)
  poly <- st_sfc(sq(500000, 4000000, 500100, 4000040), crs = 32611)
  m <- ofo_measure_cloud(raw, poly, 4000, 2021L)
  expect_equal(m$n_points_polygon, n - n / 4)
  expect_equal(m$n_withheld_polygon, n / 4)
  expect_equal(m$n_ground, sum(d$Classification == 2L & !d$Withheld_flag))
})

test_that("stage records name every table read or written that has changed", {
  dir <- tempfile("ofo-rec-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("a", file.path(dir, "in.csv")); writeLines("b", file.path(dir, "out.csv"))
  rec <- ofo_stage_record("s", dir, ofo_sha256(dir, "in.csv"), "out.csv")
  ofo_write_record(rec, file.path(dir, "s_record.json"))
  expect_length(ofo_record_mismatch(rec, dir), 0)
  expect_length(ofo_check_records(dir, c(s_record.json = "step s")), 0)
  writeLines("a2", file.path(dir, "in.csv"))
  expect_match(ofo_record_mismatch(rec, dir), "in.csv differs from the one it read")
  unlink(file.path(dir, "out.csv"))
  expect_match(ofo_record_mismatch(rec, dir)[2], "out.csv is missing")
  msg <- ofo_check_records(dir, c(s_record.json = "step s", other.json = "step o"))
  expect_match(msg[1], "^s_record.json \\(s\\): in.csv differs.*rerun step s$")
  expect_match(msg[2], "other.json is missing: rerun step o")
  expect_true(is.na(ofo_sha256(dir, "none.csv")[["none.csv"]]))
})
