source(file.path("..", "..", "scripts", "ofo_conditions_lib.R"), local = TRUE)

missions_fixture <- function() {
  data.frame(
    mission_id = c("000010", "000011", "000012", "000013", "000014", "000015", "000016"),
    camera_pitch_derived = c("0.1", NA, "30", "9.9", NA, "abc", "10"),
    camera_pitch_nominal = c("0", "0, 30", "0", "30", NA, "0", "0"),
    earliest_date_derived = as.Date(c("2021-06-01", "2021-07-01", "2021-07-02", NA,
                                      "2021-07-02", "2022-07-01", "2021-08-01")),
    date = c(NA, NA, NA, "2021-09-15, 2021-07-20", NA, NA, NA),
    stringsAsFactors = FALSE)
}

test_that("mission pitch uses the derived value, else the largest nominal value", {
  m <- missions_fixture()
  expect_equal(ofo_mission_pitch(m$camera_pitch_derived, m$camera_pitch_nominal),
               c(0.1, 30, 30, 9.9, NA, 0, 10))
  expect_equal(ofo_mission_pitch(c(5.5, NA), c("30", "15")), c(5.5, 15))
})

test_that("mission date falls back to the earliest contributor date", {
  m <- missions_fixture()
  d <- ofo_mission_date(m$earliest_date_derived, m$date)
  expect_equal(d[4], as.Date("2021-07-20"))
  expect_equal(d[1], as.Date("2021-06-01"))
})

test_that("candidates need cover and a near-nadir pitch, closest to the survey first", {
  m <- missions_fixture()
  covers <- c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE)
  cand <- ofo_mission_candidates(m, covers, as.Date("2021-07-10"))
  # 000011: nominal "0, 30" -> 30 (too oblique); 000012: 30; 000014: no pitch;
  # 000016: does not cover. 000013 (9.9) is 10 days away, 000010 39, 000015 356.
  expect_equal(cand$mission_id, c("000013", "000010", "000015"))
  expect_equal(cand$dt_days, c(10, 39, 356))
  # The 10-degree limit is inclusive.
  cand2 <- ofo_mission_candidates(m, rep(TRUE, 7), as.Date("2021-08-01"))
  expect_true("000016" %in% cand2$mission_id)
  expect_equal(cand2$mission_id[1], "000016")
})

test_that("ties in time go to the lower mission ID", {
  m <- data.frame(mission_id = c("000020", "000019"), camera_pitch_derived = c(0, 0),
                  camera_pitch_nominal = NA, earliest_date_derived = as.Date(c("2021-07-05",
                  "2021-07-15")), date = NA)
  cand <- ofo_mission_candidates(m, c(TRUE, TRUE), as.Date("2021-07-10"))
  expect_equal(cand$mission_id, c("000019", "000020"))
})

test_that("an unreadable model falls back to the next closest candidate", {
  cand <- data.frame(mission_id = c("A", "B", "C"), pitch = 0,
                     mission_date = as.Date("2021-01-01") + 0:2, dt_days = 0:2)
  reader <- function(id) switch(id, A = stop("HTTP 404"), B = NULL, C = list(z = 1))
  ch <- ofo_choose_mission(cand, reader)
  expect_equal(ch$row$mission_id, "C")
  expect_equal(ch$tried, c("A:error", "B:unusable", "C:used"))
  expect_equal(ch$errors, c(A = "HTTP 404"))
  none <- ofo_choose_mission(cand[1:2, ], reader)
  expect_null(none$row)
  expect_null(ofo_choose_mission(cand[0, ], reader)$row)
})

test_that("plot cells keep centres inside the polygon on the 5 m frame grid", {
  sq <- sf::st_sfc(sf::st_polygon(list(rbind(c(100, 200), c(112, 200), c(112, 210),
                                               c(100, 210), c(100, 200)))), crs = 32610)
  cells <- ofo_plot_cells(sq)
  # Centres 102.5, 107.5 (112.5 is outside) by 202.5, 207.5.
  expect_equal(nrow(cells), 4)
  expect_equal(sort(unique(cells$cx)), c(102.5, 107.5))
  mx <- ofo_cell_max(x = c(101, 104, 106, 113, 101), y = c(201, 204, 206, 201, 201),
                     z = c(3, 7, 12, 50, NA), cells = cells)
  k <- match(c("20 40", "21 41", "20 41", "21 40"), cells$key)
  expect_equal(mx[k], c(7, 12, NA, NA))
})

test_that("loss and reverse shares exclude cells missing in either surface", {
  early <- matrix(c(20, 20, 10, 4, NA, 30, 8, 2, 20), 3)
  late <- matrix(c(8, 19, 10, 15, 25, NA, 3, 2, 9), 3)
  s <- ofo_change_shares(as.vector(early), as.vector(late))
  # Both present: 7 cells. Early canopy (>= 5): 20, 20, 10, 8, 20 -> 5 cells;
  # late below half: 8 < 10, 3 < 4, 9 < 10 -> 3 of 5.
  expect_equal(s$n_compared, 7)
  expect_equal(s$n_canopy_early, 5)
  expect_equal(s$loss_share, 3 / 5)
  # Late canopy: 8, 19, 10, 15, 9 -> early below half: 4 < 7.5 -> 1 of 5.
  expect_equal(s$n_canopy_late, 5)
  expect_equal(s$reverse_share, 1 / 5)
  bare <- ofo_change_shares(c(1, 2, NA), c(1, NA, 9))
  expect_true(is.na(bare$loss_share))
  expect_true(is.na(bare$reverse_share))
  expect_equal(bare$n_compared, 1)
})

test_that("unresolved takes precedence over disturbed", {
  st <- ofo_disturbance_status(usable = c(FALSE, TRUE, TRUE, TRUE, TRUE, TRUE),
                               loss_share = c(0.5, 0.5, 0.5, 0.10, 0.11, NA),
                               reverse_share = c(0.5, 0.11, 0.10, 0.10, 0, NA))
  expect_equal(st, c("not_checked", "unresolved", "disturbed", "undisturbed",
                     "disturbed", "undisturbed"))
})

test_that("interval coverage: within a year of the survey or beyond it", {
  s <- as.Date("2022-07-01")
  # Mission before the survey, flight after it: the survey lies between.
  expect_true(ofo_interval_covered(as.Date("2021-01-01"), s, as.Date("2023-06-01")))
  # Mission after the survey (flight before it).
  expect_true(ofo_interval_covered(as.Date("2024-05-01"), s, as.Date("2020-08-01")))
  # Mission after the survey within a year, flight later still.
  expect_true(ofo_interval_covered(as.Date("2023-06-30"), s, as.Date("2025-08-01")))
  # Mission two years before the survey, flight after it.
  expect_true(ofo_interval_covered(as.Date("2020-07-01"), s, as.Date("2023-06-01")))
  # Mission two years before the survey, flight one year before: not covered.
  expect_false(ofo_interval_covered(as.Date("2020-07-01"), s, as.Date("2021-07-01")))
  # Mission two years after the survey, flight after the mission: not covered.
  expect_false(ofo_interval_covered(as.Date("2024-07-01"), s, as.Date("2025-07-01")))
  expect_true(is.na(ofo_interval_covered(as.Date(NA), s, as.Date("2023-06-01"))))
})

test_that("disturbance admission: undisturbed and covered, or same calendar year", {
  adm <- ofo_disturbance_admitted(
    status = c("not_checked", "not_checked", "undisturbed", "undisturbed",
               "undisturbed", "disturbed", "unresolved"),
    covered = c(NA, NA, TRUE, FALSE, FALSE, TRUE, FALSE),
    flight_year = c(2022, 2021, 2019, 2022, 2021, 2022, 2022),
    survey_year = c(2022, 2022, 2022, 2022, 2022, 2022, 2022))
  expect_equal(adm, c(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE, FALSE))
  # A check that broke on our side is not a missing drone model.
  expect_false(ofo_disturbance_admitted("not_checked", NA, 2022, 2022, failed = TRUE))
})

test_that("the dates checked are exactly the flight days, never the days between", {
  # Returns on 5, 8 and 12 November only: the days between are not flight dates.
  expect_equal(ofo_flight_dates("2021-11-05;2021-11-08;2021-11-12"),
               as.Date(c("2021-11-05", "2021-11-08", "2021-11-12")))
  expect_equal(ofo_flight_dates("2021-11-12;2021-11-05"), as.Date(c("2021-11-05", "2021-11-12")))
  expect_equal(ofo_flight_dates("2022-06-02"), as.Date("2022-06-02"))
  expect_false(exists("OFO_SPAN_DAYS"))
  for (none in list(NA, NA_character_, "", " ")) expect_length(ofo_flight_dates(none), 0)
  expect_error(ofo_flight_dates("2021-11-05;soon"), "not an ISO date")
  # Snow: only the winter flight days are read; leaf-off: any flight day in the window.
  d <- ofo_flight_dates("2021-10-10;2021-11-08")
  expect_equal(ofo_snow_dates(d), as.Date("2021-11-08"))
  expect_true(ofo_leafoff_window(d))
  expect_false(ofo_leafoff_window(ofo_flight_dates("2021-10-10;2021-10-14")))
  expect_true(ofo_leafoff_window(ofo_flight_dates("2021-10-14;2021-10-15")))
})

test_that("snow and leaf-off windows cross the year boundary", {
  d <- as.Date(c("2021-10-14", "2021-10-15", "2021-10-31", "2021-11-01", "2021-12-31",
                 "2022-01-01", "2022-04-30", "2022-05-01"))
  expect_equal(ofo_in_window(d, OFO_SNOW_WINDOW),
               c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE, FALSE))
  expect_equal(ofo_in_window(d, OFO_LEAF_WINDOW),
               c(FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE))
  expect_equal(ofo_snow_dates(d[c(3, 4, 8)]), d[4])
  expect_false(ofo_leafoff_window(d[c(1, 8)]))
  expect_true(ofo_leafoff_window(d[c(1, 2)]))
  expect_false(ofo_leafoff_window(as.Date(character())))
})

test_that("snow status: any snow decides, else an unreadable date is unknown", {
  expect_equal(ofo_snow_status(FALSE, numeric()), "not_winter")
  expect_equal(ofo_snow_status(TRUE, c(0, 0)), "snow_free")
  expect_equal(ofo_snow_status(TRUE, c(0, 0.004)), "snow")
  expect_equal(ofo_snow_status(TRUE, c(NA, 0.3)), "snow")
  expect_equal(ofo_snow_status(TRUE, c(0, NA)), "unknown")
})

test_that("deciduous share counts reference stems only", {
  sp <- c("QUKE", "PSME", "ALRU2", "ABCO", "QUKE", NA, "LAOC")
  ref <- c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, NA)
  expect_equal(ofo_deciduous_share(sp, ref), 2 / 5)
  expect_true(is.na(ofo_deciduous_share(sp, rep(FALSE, 7))))
  expect_equal(ofo_leafoff_status(c(FALSE, TRUE, TRUE, TRUE, TRUE),
                                  c(0.5, 0.099, 0.10, 0.4, NA)),
               c("leaf_on", "leaf_off_minor", "leaf_off_held", "leaf_off_held",
                 "leaf_off_minor"))
  expect_false(any(c("PSME", "QUWI2", "QUCH2", "ARME", "NODE3", "UMCA", "QUAG") %in%
                     OFO_WINTER_DECIDUOUS))
})

test_that("conditions admission and reasons list every failed check", {
  ds <- c("undisturbed", "disturbed", "not_checked", "unresolved", "undisturbed")
  da <- c(TRUE, FALSE, FALSE, FALSE, FALSE)
  sn <- c("snow_free", "not_winter", "snow", "unknown", "not_winter")
  lo <- c("leaf_off_minor", "leaf_off_held", "leaf_on", "leaf_on", "leaf_on")
  expect_equal(ofo_conditions_admitted(da, sn, lo), c(TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_equal(ofo_conditions_reason(ds, da, sn, lo),
               c("", "disturbed;leaf_off", "no_usable_drone_model;snow",
                 "unresolved;snow_unknown", "interval_not_covered"))
  expect_equal(ofo_conditions_reason("not_checked", FALSE, "not_winter", "leaf_on",
                                     failed = TRUE), "disturbance_check_failed")
})

# A tiny NOHRSC-style grid: 3 columns x 2 rows of 0.5 degree cells from
# (-121, 41) to (-119.5, 40), big-endian signed 16-bit, millimetres.
snodas_fixture <- function(dir) {
  hdr <- c("Format version: NOHRSC GIS/RS raster file v1.1",
           "Description: Modeled snow layer thickness, total of snow layers",
           "Data units: Meters / 1000.000000", "Product code: 159239965",
           "Data type: integer", "Data bytes per pixel: 2",
           "Data intercept: 0.00000000000000", "Data slope: 1.00000000000000",
           "No data value: -9999.00000000000", "Number of columns: 3", "Number of rows: 2",
           "Minimum x-axis coordinate: -121.000", "Maximum x-axis coordinate: -119.500",
           "Minimum y-axis coordinate: 40.000", "Maximum y-axis coordinate: 41.000",
           "X-axis resolution: 0.5", "Y-axis resolution: 0.5")
  vals <- c(0L, 1500L, -9999L,   # top row, latitude 41 to 40.5
            32000L, 12L, 0L)     # bottom row, 40.5 to 40
  hp <- file.path(dir, "us_ssmv11036tS__T0001TTNATS2022010105HP001.txt.gz")
  dp <- file.path(dir, "us_ssmv11036tS__T0001TTNATS2022010105HP001.dat.gz")
  other <- file.path(dir, "us_ssmv11034tS__T0001TTNATS2022010105HP001.dat.gz")
  con <- gzfile(hp, "w"); writeLines(hdr, con); close(con)
  con <- gzfile(dp, "wb"); writeBin(vals, con, size = 2, endian = "big"); close(con)
  con <- gzfile(other, "wb"); writeBin(rep(7L, 6), con, size = 2, endian = "big"); close(con)
  list(hdr = hdr, vals = vals, hp = hp, dp = dp, files = basename(c(hp, dp, other)))
}

test_that("SNODAS reader decodes a synthetic big-endian grid from its header", {
  dir <- tempfile("snodas_fx_"); dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  fx <- snodas_fixture(dir)
  g <- snodas_grid(snodas_parse_header(fx$hdr))
  expect_equal(c(g$ncol, g$nrow, g$xres, g$divisor, g$nodata), c(3, 2, 0.5, 1000, -9999))
  lon <- c(-120.9, -120.4, -119.6, -120.9, -120.1, -119.6, -122, -120.4)
  lat <- c(40.9, 40.6, 40.7, 40.1, 40.4, 40.2, 40.5, 41.5)
  v <- snodas_read_values(fx$dp, g, lon, lat)
  expect_equal(v, c(0, 1.5, NA, 32, 0.012, 0, NA, NA))
  # A negative value survives the signed decode.
  con <- gzfile(fx$dp, "wb"); writeBin(c(-5L, 0L, 0L, 0L, 0L, 0L), con, size = 2,
                                       endian = "big"); close(con)
  expect_equal(snodas_read_values(fx$dp, g, -120.9, 40.9), -0.005)
  # A grid shorter than the header is refused.
  con <- gzfile(fx$dp, "wb"); writeBin(1:5, con, size = 2, endian = "big"); close(con)
  expect_error(snodas_read_values(fx$dp, g, -120.9, 40.9), "header implies")
})

test_that("SNODAS tar reader picks the snow-depth member by its file name", {
  dir <- tempfile("snodas_tar_"); dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  fx <- snodas_fixture(dir)
  tarf <- file.path(dir, "SNODAS_20220101.tar")
  old <- setwd(dir); on.exit(setwd(old), add = TRUE)
  utils::tar(tarf, files = fx$files, tar = "internal")
  setwd(old)
  expect_equal(snodas_depth_from_tar(tarf, c(-120.4, -120.1), c(40.6, 40.4)), c(1.5, 0.012))
  expect_error(snodas_member(c("a.dat.gz", "b.txt.gz"), ext = "dat"), "found 0")
  expect_equal(snodas_url("2021-11-05"), paste0(OFO_SNODAS_BASE,
                                                "/2021/11_Nov/SNODAS_20211105.tar"))
  bad <- fx$hdr
  bad[3] <- "Data units: Kelvin"
  expect_error(snodas_grid(snodas_parse_header(bad)), "not metres")
})

test_that("missions covering a plot are found in WGS 84", {
  sq <- function(x0, y0, d) sf::st_polygon(list(rbind(c(x0, y0), c(x0 + d, y0),
                                                       c(x0 + d, y0 + d), c(x0, y0 + d),
                                                       c(x0, y0))))
  plot <- sf::st_sfc(sq(500000, 4400000, 50), crs = 32610)
  fp <- sf::st_sfc(sq(499990, 4399990, 100), sq(500020, 4399990, 100),
                   sq(400000, 4400000, 10), crs = 32610)
  m <- sf::st_sf(mission_id = c("a", "b", "c"), geometry = sf::st_transform(fp, 4326))
  expect_equal(ofo_missions_covering(m, plot), c(TRUE, FALSE, FALSE))
})
