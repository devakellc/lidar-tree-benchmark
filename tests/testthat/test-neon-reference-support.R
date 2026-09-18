source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)

support_fixture <- function() {
  grid <- expand.grid(row = 0:4, col = 0:4)
  p <- data.frame(ptloc = paste0("HARV_033.basePlot.vst.", 21 + grid$row * 9 + grid$col),
    easting = 500000 + 10 * grid$col, northing = 4700000 + 10 * grid$row,
    epsg = 32618L, unc = 0.2)
  pp <- data.frame(plotID = "HARV_033", eventID = "vst_HARV_2022", date = "2022-07-14",
    namedLocation = "HARV_033.basePlot.vst", subplotsSampled = "21_400|23_400",
    totalSampledAreaTrees = 800, samplingImpractical = "OK", dataCollected = "allGrowthForms",
    samplingProtocolVersion = "NEON.DOC.000987vK", dataQF = NA_character_)
  ai <- data.frame(plotID = pp$plotID, individualID = "stem1", date = "2022-07-14",
    eventID = pp$eventID, subplotID = "21_400", growthForm = "single bole tree",
    plantStatus = "Live", stemDiameter = 10, height = 15, canopyPosition = "Full sun",
    dataQF = NA_character_)
  mt <- data.frame(plotID = pp$plotID, individualID = ai$individualID, date = "2019-07-01",
    namedLocation = pp$namedLocation, pointID = "21", stemDistance = sqrt(200),
    stemAzimuth = 45, dataQF = NA_character_)
  list(points = p, pp = pp, ai = ai, mt = mt)
}

support_refs <- function(f) neon_event_references(f$ai, f$pp, f$mt, f$points, 2022, 32618)
support_build <- function(f) neon_build_support(f$pp, support_refs(f), f$points, 32618)

test_that("measured corners reconstruct sampled pairs, not a tower envelope", {
  f <- support_fixture()
  expect_equal(neon_subplot_corners("21_400"), c("21", "23", "41", "39"))
  expect_equal(neon_subplot_corners("31_100"), c("31", "32", "41", "40"))
  g <- neon_event_geometry(f$pp, f$points, 32618)
  expect_equal(as.numeric(sf::st_area(g$footprint)), 800)
  expect_equal(neon_support_inside(c(500010, 500010), c(4700010, 4700030), g$footprint), c(TRUE, FALSE))
  f$pp$subplotsSampled <- "23_400|39_400"
  g <- neon_event_geometry(f$pp, f$points, 32618)
  expect_equal(as.numeric(sf::st_area(g$footprint)), 800)
  expect_equal(neon_support_inside(c(500030, 500010, 500010), c(4700010, 4700030, 4700010),
                                  g$footprint), c(TRUE, TRUE, FALSE))
  f$pp$subplotsSampled <- "31_100|32_100|40_100|41_100"
  f$pp$totalSampledAreaTrees <- 400
  f$pp$plotType <- "tower"
  expect_equal(as.numeric(sf::st_area(neon_event_geometry(f$pp, f$points, 32618)$footprint)), 400)
})

test_that("incomplete, nested, overlapping and uncertain geometry fails closed", {
  f <- support_fixture()
  expect_error(neon_subplot_corners("21_25_1"), "nested")
  expect_error(neon_subplot_corners("61_400"), "anchor")
  expect_error(neon_event_geometry(f$pp, f$points[-1, ], 32618), "Missing subplot corner")
  wrong <- f$points; wrong$epsg[1] <- 32619
  expect_error(neon_event_geometry(f$pp, wrong, 32618), "CRS")
  wrong <- f$points; wrong$unc[1] <- NA
  expect_error(neon_event_geometry(f$pp, wrong, 32618), "uncertainty")
  f$pp$subplotsSampled <- "21_400|21_400"
  expect_error(neon_event_geometry(f$pp, f$points, 32618), "duplicate")
  f$pp$subplotsSampled <- "21_400|22_400"
  expect_error(neon_event_geometry(f$pp, f$points, 32618), "Overlapping")
  f$pp$subplotsSampled <- "21_400"
  expect_error(neon_event_geometry(f$pp, f$points, 32618), "sampled-area mismatch")
  f$pp$dataCollected <- "dendrometerOnly"
  expect_error(neon_event_geometry(f$pp, f$points, 32618), "Incomplete")
})

test_that("exact event joins retain provenance and reject ambiguous records", {
  f <- support_fixture()
  a <- support_refs(f)
  expect_true(a$reference_eligible)
  expect_equal(a$census_subplotsSampled, "21_400|23_400")
  expect_equal(a$E, 500010)
  expect_equal(a$N, 4700010)
  expect_equal(a$pos_unc, 0.8)
  second <- f$pp; second$eventID <- "vst_HARV_2022_second"
  second$subplotsSampled <- "39_400|41_400"
  f$pp <- rbind(f$pp, second)
  expect_true(support_refs(f)$reference_eligible) # Exact event, not nearest-year join.
  f$ai$eventID <- second$eventID
  expect_equal(support_refs(f)$exclusion, "unresolved_measurement_subplot")
  f$ai$eventID <- "missing"
  expect_equal(support_refs(f)$exclusion, "missing_or_ambiguous_event")
  f <- support_fixture(); f$pp$date <- "2021-07-14"
  expect_equal(support_refs(f)$exclusion, "census_epoch_mismatch")
  f <- support_fixture(); other <- f$pp; other$subplotsSampled <- "39_400|41_400"
  f$pp <- rbind(f$pp, other)
  expect_equal(support_refs(f)$exclusion, "missing_or_ambiguous_event")
  f <- support_fixture(); f$ai <- rbind(f$ai, f$ai)
  expect_true(all(support_refs(f)$exclusion == "missing_or_duplicate_individual"))
})

test_that("latest mapping is explicit and conflicting ties do not pick a location", {
  f <- support_fixture(); newer <- f$mt
  newer$date <- "2023-07-01"; newer$stemDistance <- sqrt(242)
  f$mt <- rbind(newer, f$mt)
  a <- support_refs(f)
  expect_equal(a$E, 500011)
  expect_equal(a$mapping_date, "2023-07-01")
  expect_equal(support_refs(within(f, mt <- mt[2:1, ]))$E, a$E)
  conflicting <- newer; conflicting$stemDistance <- 8
  f$mt <- rbind(f$mt, conflicting)
  expect_equal(support_refs(f)$exclusion, "missing_or_ambiguous_mapping")
})

test_that("population, mapping, heights and quality exclusions remain visible", {
  f <- support_fixture(); f$ai$stemDiameter <- 9.9
  expect_equal(support_refs(f)$exclusion, "outside_target_population")
  f$ai$stemDiameter <- 20; f$ai$growthForm <- "small tree"
  expect_equal(support_refs(f)$exclusion, "outside_target_population")
  f <- support_fixture(); f$ai$plantStatus <- "Dead"
  expect_equal(support_refs(f)$exclusion, "outside_target_population")
  f <- support_fixture(); f$ai$height <- NA
  expect_equal(support_refs(f)$exclusion, "invalid_height")
  expect_true("incomplete_target_references" %in% support_build(f)$blockers)
  f <- support_fixture(); f$points <- f$points[-1, ]
  expect_equal(support_refs(f)$exclusion, "missing_mapping_coordinates")
  f <- support_fixture(); f$ai$dataQF <- "measurementError"
  expect_equal(support_refs(f)$exclusion, "measurement_quality_flag")
  f <- support_fixture(); f$mt$dataQF <- "multiPlotDuplicate"
  expect_equal(support_refs(f)$exclusion, "mapping_quality_flag")
})

test_that("boundary exclusions and admission blockers are separate from geometry", {
  f <- support_fixture(); b <- support_build(f)
  expect_equal(b$boundary_margin_m, 0.8)
  expect_lt(b$interior_area_m2, b$measured_area_m2)
  expect_true(b$references$reference_selected)
  expect_false(b$evaluation_ready)
  expect_error(score_neon_support(b, data.frame(x = 500010, y = 4700010, z = 15)), "diagnostic only")
  f$mt$stemDistance <- 0.5; f$mt$stemAzimuth <- 0
  b <- support_build(f)
  expect_true(b$references$boundary_uncertain)
  expect_false(b$references$reference_selected)
  f$points$unc <- 30
  expect_error(support_build(f), "no scoring interior")
})

test_that("a mapping in the wrong sampled quadrant remains a census conflict", {
  f <- support_fixture()
  f$mt$stemDistance <- sqrt(1000); f$mt$stemAzimuth <- atan2(30, 10) * 180 / pi
  b <- support_build(f)
  expect_true(b$references$inside_interior)
  expect_true(b$references$subplot_conflict)
  expect_false(b$references$reference_selected)
  expect_true("measurement_subplot_conflict" %in% b$blockers)
})

test_that("apex tolerance around support contributes to recall but not core precision", {
  f <- support_fixture(); f$ai$subplotID <- "23_400"
  f$mt$stemDistance <- sqrt(38.9^2 + 10^2); f$mt$stemAzimuth <- atan2(38.9, 10) * 180 / pi
  b <- support_build(f); b$evaluation_ready <- TRUE; b$blockers <- character()
  out <- score_neon_support(b, data.frame(x = 500040, y = 4700010, z = 15), det_epsg = 32618)
  expect_equal(out$recall, 1)
  expect_equal(out$n_det, 0)
  expect_equal(out$tp_core, 0)
  expect_true(is.na(out$precision))
})

test_that("optional polygon scoring ignores unsampled quadrants and preserves matching", {
  f <- support_fixture(); b <- support_build(f)
  # Synthetic admission only. Real preparation never sets this flag.
  b$evaluation_ready <- TRUE; b$blockers <- character()
  det <- data.frame(x = c(500010, 500010), y = c(4700010, 4700030), z = 15)
  spatial <- score_neon_support(b, det, det_epsg = 32618)
  expect_error(score_neon_support(b, det), "detection CRS")
  expect_error(score_neon_support(b, det, det_epsg = 32619), "detection CRS")
  rectangular <- score_plot(b$references, det, core_cx = 500020, core_cy = 4700020, core_half = 20)
  expect_equal(spatial$TP, 1)
  expect_equal(spatial$n_det, 1)
  expect_equal(rectangular$n_det, 2)
  expect_equal(spatial$tp_core, 1)
  det$z <- 25
  expect_equal(score_neon_support(b, det, det_epsg = 32618)$TP, 0) # Existing height gate.
  expect_equal(score_neon_support(b, det[FALSE, ], det_epsg = 32618)$n_det, 0)
  square <- sf::st_as_sfc(sf::st_bbox(c(xmin = 500000, ymin = 4700000,
                                      xmax = 500040, ymax = 4700040), crs = 32618))
  det$z <- 15
  same <- score_plot(b$references, det, core_cx = 500020, core_cy = 4700020,
                      core_geometry = square)
  expect_equal(same[, names(rectangular)], rectangular)
  expect_error(score_plot(b$references, det, core_cx = 0, core_cy = 0,
    core_geometry = sf::st_transform(square, 4326)), "metric CRS")
})

test_that("support provenance prevents stale identities and mixed pooling", {
  b <- support_build(support_fixture()); id <- neon_support_identity(b)
  b$boundary_margin_m <- 1
  expect_false(identical(id, neon_support_identity(b)))
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  p <- file.path(d, "contract.json")
  neon_check_manifest(p, list(support_id = id))
  expect_error(neon_check_manifest(p, list(support_id = neon_support_identity(b))), "differs")
  b$evaluation_ready <- TRUE; b$blockers <- character()
  scored <- score_neon_support(b, data.frame(x = 500010, y = 4700010, z = 15), det_epsg = 32618)
  rows <- cbind(data.frame(site = "HARV", plot = "HARV_033", rung = "native", detector = "fixture"), scored)
  expect_equal(pool(rows)$recall, 1)
  expect_equal(pool(rows)$precision, 1)
  expect_identical(pool(rows)$reference_population, b$population)
  other <- rows; other$detector <- "other"; other$support_id <- "changed"
  expect_error(equal_set_guard(rbind(rows, other), c("fixture", "other")), "Different reference support")
  other <- rows; other$support_id <- NA_character_
  expect_error(pool(rbind(rows, other)), "Missing support identity")
  other <- rows; other$support_policy <- "legacy_rectangle"
  expect_error(pool(rbind(rows, other)), "Mixed reference-support")
})

test_that("historical audit distinguishes partial, dendrometer and ambiguous events", {
  f <- support_fixture()
  g <- data.frame(plotID = "HARV_033", individualID = "stem1", meas_year = 2022,
                  E = 500010, N = 4700010, live = TRUE, is_tree = TRUE)
  pc <- data.frame(plotID = "HARV_033", plotType = "tower", easting = 500020, northing = 4700020)
  dat <- list(vst_apparentindividual = f$ai, vst_perplotperyear = f$pp)
  a <- neon_historical_support(g, pc, dat, "HARV")
  expect_equal(a$status, "partial_nominal_area")
  expect_equal(a$n_historical_core, 1)
  expect_false(a$detector_rescored)
  dat$vst_perplotperyear$dataCollected <- "dendrometerOnly"
  expect_equal(neon_historical_support(g, pc, dat, "HARV")$status, "dendrometer_only")
  other <- f$ai; other$eventID <- "second"
  dat$vst_apparentindividual <- rbind(f$ai, other)
  expect_equal(neon_historical_support(g, pc, dat, "HARV")$status, "unresolved_census_event")
})

test_that("standalone preparation replays offline and rejects tampered outputs", {
  f <- support_fixture(); f$pp$utmZone <- "18N"
  root <- tempfile(); dir.create(root)
  on.exit(unlink(root, recursive = TRUE))
  vst <- file.path(root, "neon/HARV/vst"); dir.create(vst, recursive = TRUE)
  saveRDS(list(vst_apparentindividual = f$ai, vst_perplotperyear = f$pp,
               vst_mappingandtagging = f$mt), file.path(vst, "harv_vst_allyears.rds"))
  out <- file.path(root, "audit"); locs <- file.path(out, "locations")
  dir.create(locs, recursive = TRUE)
  for (i in seq_len(nrow(f$points))) {
    p <- f$points[i, ]; name <- p$ptloc
    loc <- list(locationName = name, locationUtmEasting = p$easting,
      locationUtmNorthing = p$northing, locationUtmZone = 18L, locationUtmHemisphere = "N",
      locationProperties = data.frame(locationPropertyName = c("Value for Geodetic datum",
        "Value for Coordinate uncertainty"), locationPropertyValue = c("WGS84", as.character(p$unc))))
    jsonlite::write_json(list(location = name, status = 200L, data = loc),
      file.path(locs, paste0(name, ".json")), auto_unbox = TRUE, pretty = TRUE)
  }
  script <- normalizePath(file.path("..", "..", "scripts", "neon_reference_support.R"))
  run <- function() suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(script), "SITE=HARV", "YEAR=2022", paste0("OUT=", shQuote(out))),
    env = paste0("CLAUDE_JOB_DIR=", shQuote(root)), stdout = TRUE, stderr = TRUE))
  first <- run()
  expect_null(attr(first, "status"), info = paste(first, collapse = "\n"))
  expect_true(file.exists(file.path(out, "support_geometry.gpkg")))
  hashes <- tools::md5sum(list.files(out, full.names = TRUE, recursive = TRUE))
  second <- run()
  expect_null(attr(second, "status"), info = paste(second, collapse = "\n"))
  expect_true(any(grepl("integrity replay passed", second)))
  expect_identical(tools::md5sum(names(hashes)), hashes)
  writeLines("tampered", file.path(out, "reference_audit.csv"))
  third <- run()
  expect_equal(attr(third, "status"), 1L)
  expect_true(any(grepl("Cache contract differs", third)))
})
