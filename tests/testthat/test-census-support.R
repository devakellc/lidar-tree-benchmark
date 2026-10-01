source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "io_bridge.R"), local = TRUE)
source(file.path("..", "..", "scripts", "coverage_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "census_support_lib.R"), local = TRUE)
suppressMessages(library(lidR))

census_fixture <- function() {
  grid <- expand.grid(row = 0:4, col = 0:4)
  points <- data.frame(ptloc = paste0("HARV_033.basePlot.vst.", 21 + grid$row * 9 + grid$col),
    easting = 500000 + 10 * grid$col, northing = 4700000 + 10 * grid$row, epsg = 32618L, unc = 0.2)
  pp <- data.frame(plotID = "HARV_033", eventID = "vst_HARV_2022", date = "2022-07-14",
    namedLocation = "HARV_033.basePlot.vst", subplotsSampled = "21_400|23_400",
    totalSampledAreaTrees = 800, samplingImpractical = "OK", dataCollected = "allGrowthForms",
    samplingProtocolVersion = "NEON.DOC.000987vK", dataQF = NA_character_)
  ai <- data.frame(plotID = pp$plotID, individualID = "stem1", date = "2022-07-14",
    eventID = pp$eventID, subplotID = "21_400", growthForm = "single bole tree",
    plantStatus = "Live", stemDiameter = 10, height = 15, canopyPosition = "Full sun",
    dataQF = NA_character_)
  mt <- data.frame(plotID = pp$plotID, individualID = "stem1", date = "2019-07-01",
    namedLocation = pp$namedLocation, pointID = "21", stemDistance = sqrt(200),
    stemAzimuth = 45, dataQF = NA_character_)
  refs <- neon_event_references(ai, pp, mt, points, 2022, 32618)
  neon_build_support(pp, refs, points, 32618)
}

census_root <- function(d) {
  root <- file.path(d, "root"); dir.create(root)
  writeLines("manifest", file.path(root, "clip_manifest.csv"))
  root
}

test_that("persisted apexes come from stamped sources in a fixed order", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  root <- census_root(d); nd <- file.path(d, "SITE")
  expect_null(census_cell_detections(nd, "ams3d", "HARV", "HARV_033", NA, root))
  # cache: the arm's selected configuration
  cache <- file.path(nd, "best_treetop_cache"); frozen_stamp(cache, root)
  write.csv(data.frame(x = 1, y = 2, z = 3), file.path(cache, "ams3d__HARV__HARV_033__native.csv"),
            row.names = FALSE)
  det <- census_cell_detections(nd, "ams3d", "HARV", "HARV_033", NA, root)
  expect_identical(attr(det, "source"), "cache")
  # instances outrank the cache; apex = max-Z point of each instance
  inst <- file.path(nd, "ams3d_instances"); frozen_stamp(inst, root)
  las <- LAS(data.frame(X = c(0, 0.5, 9), Y = c(0, 0.5, 9), Z = c(4, 12, 7),
                        crown_id = c(1L, 1L, 2L)))
  sf::st_crs(las) <- 32618
  las <- add_lasattribute(las, las$crown_id, "crown_id", "instance")
  writeLAS(las, file.path(inst, "HARV_033_native.laz"))
  det <- census_cell_detections(nd, "ams3d", "HARV", "HARV_033", NA, root)
  expect_identical(attr(det, "source"), "instances")
  expect_equal(sort(det$z), c(7, 12))
  # persisted per-cell detections outrank both
  dd <- file.path(nd, "ams3d_detections"); frozen_stamp(dd, root)
  write.csv(data.frame(x = 5, y = 5, z = 20), file.path(dd, "HARV_033__native.csv"), row.names = FALSE)
  det <- census_cell_detections(nd, "ams3d", "HARV", "HARV_033", NA, root)
  expect_identical(attr(det, "source"), "detections")
  expect_equal(det$z, 20)
  # a source made on other clips is refused, not skipped
  writeLines("other", file.path(root, "clip_manifest.csv"))
  expect_error(census_cell_detections(nd, "ams3d", "HARV", "HARV_033", NA, root),
               "not made on the frozen root")
})

test_that("only declared bundles are loaded, each admitted once", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  b <- census_fixture()
  dir.create(file.path(d, "HARV_2022"))
  saveRDS(list(`HARV_033::vst_HARV_2022` = b), file.path(d, "HARV_2022", "support_bundles.rds"))
  decl <- list(name = "synthetic", resolved_blockers = c("datum_review_pending", "flight_provenance_pending"),
               admitted = data.frame(site = "HARV", plot = "HARV_033", event = "vst_HARV_2022",
                                     support_id = neon_support_identity(b)))
  got <- census_admitted_bundles(d, "HARV", decl, 2021:2022)
  expect_named(got, "HARV_033")
  expect_true(got$HARV_033$evaluation_ready)
  expect_length(census_admitted_bundles(d, "BART", decl, 2022), 0)
  twice <- decl; twice$admitted <- rbind(decl$admitted, decl$admitted)
  expect_error(census_admitted_bundles(d, "HARV", twice, 2022), "more than one event")
  lost <- decl; lost$admitted$event <- "vst_HARV_2021"
  expect_error(census_admitted_bundles(d, "HARV", lost, 2022), "not found")
})

test_that("census and nominal-box scores of one cell pool side by side", {
  b <- census_fixture()
  decl <- list(name = "synthetic", resolved_blockers = c("datum_review_pending", "flight_provenance_pending"),
               admitted = data.frame(plot = b$plot, event = b$event, support_id = neon_support_identity(b)))
  a <- neon_admit_support(b, decl)
  # one apex on the mapped stem, one in the unsampled half of the nominal box
  det <- data.frame(x = c(500010, 500030), y = c(4700010, 4700030), z = c(15, 15))
  stems <- data.frame(E = 500010, N = 4700010, crown_class = "dominant", height = 15)
  s <- census_score_cell(a, det, 32618, stems, cx = 500020, cy = 4700020, ph = 20)
  expect_equal(c(s$TP, s$n_det, s$precision), c(1, 1, 1))     # unsampled quadrant ignored
  expect_equal(c(s$rect_n_det, s$rect_precision), c(2, 0.5))  # nominal box counts it
  rows <- rbind(data.frame(site = "HARV", plot = "HARV_033", rung = "native", detector = "a", s),
                data.frame(site = "HARV", plot = "HARV_033", rung = "native", detector = "b", s))
  p <- census_pool(rows, c("a", "b"))
  expect_equal(nrow(p), 2L)
  expect_equal(p$precision, c(1, 1)); expect_equal(p$rect_precision, c(0.5, 0.5))
  expect_true(all(nzchar(p$support_set_id)))
})
