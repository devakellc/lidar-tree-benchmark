source(file.path("..", "..", "scripts", "neon_spatial_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "neon_acquisition_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "site_extension_lib.R"), local = TRUE)

ext_fixture <- function() {
  pc <- data.frame(plotID = c("T1", "D1", "D2"), plotType = c("tower", "distributed", "distributed"),
                   easting = c(500500, 500200, 501995), northing = c(4000500, 4000200, 4000500))
  stem <- function(plot, dx, dy, dbh = 20, live = TRUE, is_tree = TRUE,
                   cp = "Full sun", cls = "dominant") {
    p <- pc[pc$plotID == plot, ]
    data.frame(individualID = paste0(plot, "_", dx, "_", dy, "_", dbh), plotID = plot,
               E = p$easting + dx, N = p$northing + dy, stemDiameter = dbh,
               live = live, is_tree = is_tree, canopyPosition = cp, crown_class = cls,
               meas_year = 2021L)
  }
  gt <- rbind(
    # Tower: six core trees (one small), one tree outside the +/-20 m core,
    # one dead and one non-tree that the sweep never admits.
    stem("T1", 0, 0), stem("T1", 5, 5), stem("T1", -5, 5), stem("T1", 10, -10),
    stem("T1", -15, 15, cp = NA, cls = "suppressed"), stem("T1", 19, 0, dbh = 5),
    stem("T1", 25, 0), stem("T1", 1, 1, live = FALSE), stem("T1", 2, 2, is_tree = FALSE),
    # Distributed: six trees, but two below 10 cm DBH and one unclassified.
    stem("D1", 0, 0), stem("D1", 1, 1), stem("D1", 2, 2), stem("D1", 3, 3, cp = NA, cls = NA),
    stem("D1", 4, 4, dbh = 8), stem("D1", 5, 5, dbh = NA),
    # Distributed, five trees: below the six-tree gate.
    stem("D2", 0, 0), stem("D2", 1, 0), stem("D2", 2, 0), stem("D2", 3, 0), stem("D2", 4, 0))
  list(gt = gt, pc = pc)
}

test_that("inventory applies the sweep gate on the whole plot and counts core stems", {
  f <- ext_fixture()
  inv <- ext_plot_inventory(f$gt, f$pc)
  expect_equal(inv$plotID, c("D1", "D2", "T1"))
  expect_equal(inv$n_live, c(6, 5, 7))
  expect_equal(inv$n_core, c(6, 5, 6))            # the 25 m stem is outside T1's core
  expect_equal(inv$admitted, c(TRUE, FALSE, TRUE))
  expect_equal(inv$core_half, c(10, 10, 20))
  expect_equal(inv$n_core_dbh10, c(4, 5, 5))      # NA DBH never counts as >= 10 cm
  expect_equal(inv$n_core_height_fallback, c(0, 0, 1))
  expect_equal(inv$n_core_no_class, c(1, 0, 0))
})

test_that("the DBH gate is applied before the six-stem gate, not after", {
  f <- ext_fixture()
  g <- ext_gate(f$gt, "dbh10")
  expect_false(any(is.na(g$stemDiameter) | g$stemDiameter < 10))
  inv <- ext_plot_inventory(g, f$pc)
  expect_equal(inv$admitted[inv$plotID == "D1"], FALSE)   # 4 large trees left
  expect_equal(inv$admitted[inv$plotID == "T1"], TRUE)    # 6 large trees left
  s <- ext_site_summary(inv, "X", "dbh10")
  expect_equal(c(s$plots_admitted, s$stems_core_admitted), c(1, 5))
  expect_identical(ext_gate(f$gt, "all_mapped"), f$gt)
  expect_error(ext_gate(f$gt, "dbh5"))
})

test_that("site summary sums admitted cores only and reports class provenance", {
  f <- ext_fixture()
  s <- ext_site_summary(ext_plot_inventory(f$gt, f$pc), "X")
  expect_equal(s$live_mapped, 18)
  expect_equal(s$plots_admitted, 2)
  expect_equal(c(s$plots_admitted_tower, s$plots_admitted_distributed), c(1, 1))
  expect_equal(s$stems_admitted, 13)
  expect_equal(s$stems_core_admitted, 12)
  expect_equal(s$core_canopy_position + s$core_height_fallback + s$core_no_class, 12)
  expect_equal(s$canopy_position_share, 10 / 12)
  cs <- ext_core_stems(f$gt, ext_plot_inventory(f$gt, f$pc))
  expect_equal(nrow(cs), s$stems_core_admitted)
  expect_false(any(cs$plotID == "D2"))
})

test_that("a clip is covered only when every intersected tile is listed", {
  f <- ext_fixture()
  inv <- ext_plot_inventory(f$gt, f$pc)
  # D2's clip (+/-10 m core + 25 m buffer) crosses the 502000 easting boundary.
  tiles <- data.frame(key = c("500000_4000000", "501000_4000000"))
  cv <- ext_tile_coverage(inv, tiles)
  expect_equal(cv$tiles_listed, c(TRUE, FALSE, TRUE))
  expect_equal(cv$tiles_needed[cv$plotID == "D2"], "501000_4000000;502000_4000000")
  cv <- ext_tile_coverage(inv, rbind(tiles, data.frame(key = "502000_4000000")))
  expect_true(all(cv$tiles_listed))
})

test_that("the header tile is the listed one wholly holding the most admitted clips", {
  f <- ext_fixture()
  inv <- ext_plot_inventory(f$gt, f$pc)
  listed <- c("500000_4000000", "501000_4000000", "502000_4000000")
  pick <- ext_header_tile(inv, listed)
  expect_equal(pick$key, "500000_4000000")
  expect_setequal(pick$plots, c("D1", "T1"))
  # The best tile unlisted: fall back to a listed single-tile clip, or NULL.
  inv2 <- rbind(inv, transform(inv[inv$plotID == "D1", ], plotID = "D3", easting = 501500))
  expect_equal(ext_header_tile(inv2, listed[-1])$key, "501000_4000000")
  expect_null(ext_header_tile(inv, listed[-1]))
  inv$admitted <- inv$plotID == "D2"              # D2 straddles two tiles
  expect_null(ext_header_tile(inv, listed))
  inv$admitted <- FALSE
  expect_null(ext_header_tile(inv, listed))
})

test_that("a gate that admits nothing yields empty tables, not an error", {
  f <- ext_fixture()
  none <- f$gt; none$live <- FALSE
  inv <- ext_plot_inventory(none, f$pc)
  expect_equal(nrow(inv), 0)
  expect_true(all(c("plotID", "n_core", "admitted") %in% names(inv)))
  s <- ext_site_summary(inv, "X", "dbh10")
  expect_equal(c(s$plots_admitted, s$stems_core_admitted), c(0, 0))
  expect_equal(nrow(ext_core_stems(none, inv)), 0)
})

test_that("the preflight clip geometry matches the sweep's", {
  skip_if_not_installed("lasR")
  env <- new.env()
  sys.source(file.path("..", "..", "scripts", "sweep_lib.R"), envir = env)
  expect_equal(EXT_CLIP_BUF, env$BUF)
  expect_equal(ext_core_half(c("tower", "distributed")), env$plot_half(c("tower", "distributed")))
})

test_that("disturbance remarks and removals are counted per plot before the cutoff", {
  ai <- data.frame(
    individualID = c("a", "a", "b", "b", "c", "d", "e"),
    plotID = c("P1", "P1", "P1", "P1", "P1", "P2", "P2"),
    date = c("2018-07-01", "2021-08-01", "2018-07-01", "2019-08-01", "2019-08-01",
             "2019-08-01", "2022-08-01"),
    plantStatus = c("Live", "Live", "Live", "Removed", "Live", "Live", "Removed"),
    remarks = c(NA, NA, NA, "Cut during forestry thinning",
                "No longer falls within reduced nested size", NA, "Thinning event"),
    stemDiameter = c(20, 21, 12, NA, 3, 15, 15), height = c(15, 16, 8.5, NA, 2, 12, 12))
  d <- ext_disturbance_by_plot(ai, c("P1", "P2"), as.Date("2021-07-01"))
  expect_equal(d$disturbance_records, c(1, 0))   # "within" is not thinning; 2022 is after
  expect_equal(d$last_disturbance, c("2019-08-01", NA))
  expect_equal(d$removed_individuals, c(1, 0))
  expect_equal(d$removed_dbh10, c(1, 0))         # b reached 12 cm before removal
  expect_equal(d$removed_max_height, c(8.5, NA))
})

test_that("the disturbance pattern reads management, not crown condition", {
  yes <- c("Cut during forestry thinning", "Thining", "Likely damaged during thinnng",
           "Thinned", "Several stems were severed during a clearing event.", "Cut",
           "Main bole cut", "Harvested", "Clear-cut event", "Lower branches thinned")
  no <- c("No longer falls within reduced nested size", "Thinning crown",
          "Thinning branches", "Thinning lower branches from tshe", "Dead - Self-thinning",
          "Lower branches cut", "thin crown", NA)
  expect_true(all(ext_is_disturbance(yes)))
  expect_false(any(ext_is_disturbance(no)))
})

test_that("a dead secondary bole does not make a live tree non-live", {
  ai <- data.frame(individualID = c("m", "m", "m"), plotID = "P1",
                   date = c("2017-10-26", "2017-10-26", "2021-03-01"),
                   plantStatus = c("Standing dead", "Live", "Live"), remarks = NA,
                   stemDiameter = c(9.8, 31, 31.5))
  cs <- data.frame(individualID = "m", plotID = "P1", meas_year = 2021L)
  h <- ext_core_status_history(ai, cs, data.frame(plotID = "P1", last_disturbance = NA),
                               as.Date("2021-07-01"))
  expect_false(h$any_nonlive_before)
  expect_equal(h$last_before_status, "Live")
  ai$date[3] <- "2017-10-26"                     # last date mixed: Live bole preferred
  h <- ext_core_status_history(ai, cs, data.frame(plotID = "P1", last_disturbance = NA),
                               as.Date("2021-07-01"))
  expect_equal(h$last_before_status, "Live")
  expect_false(h$last_before_nonlive)
})

test_that("status history flags earlier non-live records and pre-disturbance scores", {
  ai <- data.frame(
    individualID = c("a", "a", "b", "b", "c"),
    plotID = "P1",
    date = c("2018-07-01", "2021-08-01", "2017-07-01", "2019-08-01", "2019-06-01"),
    plantStatus = c("No longer qualifies", "Live", "Live", "Live", "Live"),
    remarks = NA, stemDiameter = 20)
  cs <- data.frame(individualID = c("a", "b", "c"), plotID = "P1",
                   meas_year = c(2021L, 2019L, 2019L))
  disturb <- data.frame(plotID = "P1", last_disturbance = "2019-07-01")
  h <- ext_core_status_history(ai, cs, disturb, as.Date("2021-07-01"))
  expect_equal(h$any_nonlive_before, c(TRUE, FALSE, FALSE))
  expect_equal(h$last_before_nonlive, c(TRUE, FALSE, FALSE))
  expect_equal(h$last_before_status, c("No longer qualifies", "Live", "Live"))
  # b was last scored after the remark; c only before it.
  expect_equal(h$scored_before_disturbance, c(FALSE, FALSE, TRUE))
})

test_that("occupied density ignores empty cells and counts first returns", {
  x <- c(0.5, 1.5, 2.5, 3.5, 7.5, 8.5); y <- c(0.5, 0.5, 1.5, 4.5, 0.5, 0.5)
  r <- c(1L, 2L, 1L, 1L, 1L, 3L)
  d <- ext_occupied_density(x, y, r, res = 5)
  expect_equal(d[["occupied_m2"]], 50)            # two occupied 5 m cells
  expect_equal(d[["all_returns"]], 6 / 50)
  expect_equal(d[["first_returns"]], 4 / 50)
  expect_error(ext_occupied_density(numeric(), numeric(), integer()), "Empty")
})

test_that("downloads are matched by size and crc32c, falling back to md5", {
  f <- tempfile(); on.exit(unlink(f))
  writeBin(charToRaw("123456789"), f)            # crc32c check value e3069283
  row <- data.frame(name = "t.laz", size = 9, md5 = NA_character_, crc32c = "E3069283")
  expect_true(ext_file_matches(f, row))
  expect_false(ext_file_matches(f, transform(row, crc32c = "00000000")))
  expect_false(ext_file_matches(f, transform(row, size = 10)))
  expect_false(ext_file_matches(paste0(f, ".missing"), row))
  row$crc32c <- NA_character_; row$md5 <- "25f9e794323b453885f5181f1b624d0b"
  expect_true(ext_file_matches(f, row))
  row$md5 <- NA_character_
  expect_error(ext_file_matches(f, row), "no checksum")
  # Listings print crc32c without leading zeros; "tile5" hashes to 0966948f.
  writeBin(charToRaw("tile5"), f)
  row <- data.frame(name = "t.laz", size = 5, crc32c = "966948F")
  expect_true(ext_file_matches(f, row))
  expect_equal(ext_crc_norm(c("79f3c9f", "E3069283")), c("079f3c9f", "e3069283"))
})

test_that("the download audit verifies checksums and names missing needed tiles", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  a <- file.path(d, "NEON_D16_WREF_DP1_580000_5075000_classified_point_cloud_colorized.laz")
  b <- file.path(d, "NEON_D16_WREF_DP1_581000_5075000_classified_point_cloud_colorized.laz")
  stray <- file.path(d, "unlisted.laz")
  for (f in c(a, b, stray)) writeBin(charToRaw("123456789"), f)
  tiles <- data.frame(name = basename(c(a, b)), size = 9, crc32c = c("e3069283", "deadbeef"),
                      key = c("580000_5075000", "581000_5075000"))
  au <- ext_download_audit(c(a, b, stray), tiles, c("580000_5075000", "581000_5075000",
                                                    "580000_5074000"))
  expect_equal(au$files$listed, c(TRUE, TRUE, FALSE))
  expect_equal(au$files$verified, c(TRUE, FALSE, FALSE))  # b fails its checksum
  expect_equal(au$files$needed, c(TRUE, TRUE, FALSE))
  expect_equal(au$missing, c("580000_5074000", "581000_5075000"))
})
