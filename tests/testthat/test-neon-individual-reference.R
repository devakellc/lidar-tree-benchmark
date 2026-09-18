source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "neon_reference_resolution_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "neon_individual_reference_lib.R"), local = TRUE)

individual_fixture <- function() {
  ids <- paste0("NEON.PLA.D01.HARV.00001", c("", "A"))
  ai <- data.frame(uid = c("m1", "m2"), plotID = "HARV_033", eventID = "vst_HARV_2022",
    date = "2022-07-14", individualID = ids, growthForm = "multi-bole tree", plantStatus = "Live",
    subplotID = "21_400", height = c(20, NA), heightQualifier = NA_character_, breakHeight = NA_real_,
    stemDiameter = c(30, 15), dataQF = NA_character_, canopyPosition = c("Full sun", NA))
  mt <- data.frame(uid = c("map1", "map2"), recordType = c("map and tag", "tag only"),
    plotID = ai$plotID, individualID = ids, date = "2023-07-01", namedLocation = "HARV_033.basePlot.vst",
    pointID = c("21", NA), stemDistance = c(sqrt(200), NA), stemAzimuth = c(45, NA), dataQF = NA_character_)
  pp <- data.frame(plotID = "HARV_033", eventID = "vst_HARV_2022", date = "2022-07-14",
    namedLocation = "HARV_033.basePlot.vst", subplotsSampled = "21_400", totalSampledAreaTrees = 400,
    samplingImpractical = "OK", dataCollected = "allGrowthForms", samplingProtocolVersion = "NEON.DOC.000987vK",
    dataQF = NA_character_)
  points <- data.frame(ptloc = paste0(pp$namedLocation, ".", c(21, 23, 41, 39)),
    easting = c(500000, 500020, 500020, 500000), northing = c(4700000, 4700000, 4700020, 4700020),
    epsg = 32618, unc = 0.2)
  list(ai = ai, mt = mt, pp = pp, points = points)
}

individual_source <- function(f) neon_build_support(f$pp,
  neon_event_references(f$ai, f$pp, f$mt, f$points, 2022, 32618), f$points, 32618)
individual_run <- function(f) neon_individual_references(individual_source(f), f$mt)

test_that("one apparent individual preserves original bole rows and geometry", {
  f <- individual_fixture(); b <- individual_source(f)
  before <- serialize(list(b, f), NULL)
  x <- neon_individual_references(b, f$mt)
  u <- x$support$references
  expect_equal(nrow(u), 1)
  expect_equal(u$n_boles, 2)
  expect_true(u$reference_selected)
  expect_equal(u$location_mapping_uid, "map1")
  expect_equal(u$height_source_uid, "m1")
  expect_equal(u$height, 20)
  expect_equal(u$location_mapping_date, "2023-07-01")
  expect_identical(serialize(list(b, f), NULL), before)
  expect_equal(x$members[, names(b$references)], b$references)
  for (g in c("footprint", "core", "subplots", "boundary_margin_m")) expect_identical(x$support[[g]], b[[g]])
  expect_true(all(b$blockers %in% x$support$blockers))
  expect_false(x$support$evaluation_ready)
  expect_false(identical(neon_support_identity(x$support), neon_support_identity(b)))
  expect_error(score_neon_support(x$support, data.frame(x = 500010, y = 4700010, z = 20)), "diagnostic")
})

test_that("broken primary uses one explicit intact relative including below-threshold boles", {
  f <- individual_fixture(); f$ai$plantStatus[1] <- "Live, broken bole"
  f$ai$height <- c(NA, 12); f$ai$breakHeight[1] <- 5; f$ai$stemDiameter[2] <- 8
  f$ai$canopyPosition <- c(NA, "Mostly shaded")
  x <- individual_run(f); u <- x$support$references
  expect_true(u$reference_selected)
  expect_equal(u$height_source_uid, "m2")
  expect_equal(u$location_source_uid, "m1")
  expect_equal(u$height_source_dbh, 8)
  expect_equal(u$crown_class, "intermediate")
  expect_equal(u$height, 12)
  expect_equal(x$comparison$n_new_selected_units, 1)
  expect_true(is.na(x$members$height[1]))
  f$ai$height[2] <- NA
  expect_match(individual_run(f)$support$references$exclusion, "missing_live_height")
  f$ai$height <- c(NA, 12); f$ai$plantStatus[1] <- "Live"
  expect_match(individual_run(f)$support$references$exclusion, "height_source_requires_review")
})

test_that("height ambiguity and quality never select a convenient donor", {
  f <- individual_fixture(); f$ai$height <- c(20, 20)
  u <- individual_run(f)$support$references
  expect_match(u$exclusion, "multiple_live_height_records")
  expect_true(is.na(u$height))
  expect_false(u$reference_selected)
  f <- individual_fixture(); f$ai$height[2] <- -1
  expect_match(individual_run(f)$support$references$exclusion, "invalid_recorded_height")
  f <- individual_fixture(); f$ai$heightQualifier[1] <- "estimated"
  expect_match(individual_run(f)$support$references$exclusion, "height_qualifier_review")
  f <- individual_fixture(); f$ai$dataQF[2] <- "measurementError"
  expect_match(individual_run(f)$support$references$exclusion, "measurement_quality_flag")
  f <- individual_fixture(); f$mt$dataQF[2] <- "mappingError"
  expect_match(individual_run(f)$support$references$exclusion, "mapping_quality_flag")
})

test_that("dead-primary coordinates and dead-bole diameters are not borrowed", {
  f <- individual_fixture(); f$ai$plantStatus[1] <- "Dead, broken bole"
  f$ai$height <- c(NA, 14.5)
  u <- individual_run(f)$support$references
  expect_true(u$target_population)
  expect_match(u$exclusion, "primary_not_live")
  expect_true(is.na(u$E))
  expect_false(u$reference_selected)
  f$ai$stemDiameter[2] <- 8
  expect_equal(individual_run(f)$support$references$population_status, "outside")
  f <- individual_fixture(); f$ai$stemDiameter <- NA_real_
  expect_equal(individual_run(f)$support$references$population_status, "undetermined")
})

test_that("identity requires the exact unique primary without cross-event rescue", {
  f <- individual_fixture(); f$ai <- f$ai[2, ]
  expect_match(individual_run(f)$support$references$exclusion, "missing_or_ambiguous_primary")
  f <- individual_fixture(); extra <- f$ai[1, ]; extra$uid <- "m3"
  f$ai <- rbind(f$ai, extra)
  expect_match(individual_run(f)$support$references$exclusion, "duplicate_bole_records")
  f <- individual_fixture(); f$ai$individualID[2] <- "unknownA"
  expect_true(any(grepl("unsupported_identity", individual_run(f)$support$references$exclusion)))
  f <- individual_fixture(); f$ai$growthForm[1] <- "single bole tree"
  expect_match(individual_run(f)$support$references$exclusion, "inconsistent_growth_forms")
  f <- individual_fixture(); b <- individual_source(f); b$references$eventID[2] <- "other"
  expect_error(neon_individual_references(b, f$mt), "plot/event mismatch")
  f <- individual_fixture(); b <- individual_source(f); b$references$uid[2] <- "m1"
  expect_error(neon_individual_references(b, f$mt), "provenance")
  f <- individual_fixture(); newer <- f$mt[1, ]; newer$uid <- "map3"; newer$stemDistance <- 10
  f$mt <- rbind(f$mt, newer)
  expect_match(individual_run(f)$support$references$exclusion, "missing_or_ambiguous_mapping")
  f <- individual_fixture(); f$mt$uid[2] <- f$mt$uid[1]
  expect_match(individual_run(f)$support$references$exclusion, "duplicate_mapping_provenance")
  f <- individual_fixture(); b <- individual_source(f); b$event_metadata$date <- NA_character_
  expect_error(neon_individual_references(b, f$mt), "Missing census date")
})

test_that("spatial checks remain independent of earlier missing-height exclusions", {
  f <- individual_fixture(); f$points$unc[1] <- NA_real_
  b <- individual_source(individual_fixture()); b$references$pos_unc[1] <- NA_real_
  expect_match(neon_individual_references(b, f$mt)$support$references$exclusion, "missing_primary_uncertainty")
  f <- individual_fixture(); f$ai$plantStatus[1] <- "Live, broken bole"
  f$ai$height <- c(NA, 12); f$ai$breakHeight[1] <- 5
  b <- individual_source(f); b$references$E[1] <- 500020.85
  expect_false(b$references$subplot_conflict[1])
  u <- neon_individual_references(b, f$mt)$support$references
  expect_match(u$exclusion, "primary_subplot_conflict")
  expect_equal(u$distance_to_subplot_m, 0.85, tolerance = 1e-7)
  expect_false(u$reference_selected)
  f <- individual_fixture(); f$ai$subplotID[2] <- "23_400"
  expect_match(individual_run(f)$support$references$exclusion, "inconsistent_or_unsampled_subplot")
})

test_that("single trees and source order preserve equivalent diagnostic selection", {
  f <- individual_fixture(); f$ai <- f$ai[1, ]; f$ai$growthForm <- "single bole tree"
  x <- individual_run(f)
  expect_equal(x$comparison$n_source_selected_boles, x$comparison$n_selected_individuals)
  expect_equal(x$support$references$height, f$ai$height)
  f <- individual_fixture(); x <- individual_run(f)
  f$ai <- f$ai[2:1, ]; f$mt <- f$mt[2:1, ]
  expect_equal(individual_run(f)$support$references, x$support$references)
  p <- neon_individual_policy(); p$id <- "modified"
  expect_error(neon_individual_references(individual_source(f), f$mt, p), "Unsupported individual policy")
  b <- individual_source(f); b$evaluation_ready <- TRUE
  expect_error(neon_individual_references(b, f$mt), "diagnostic predecessor")
  d <- data.frame(site = "HARV", plot = "HARV_033", rung = "native", support_id = "one",
                  support_policy = x$support$policy, reference_population = x$support$population)
  old <- d; old$support_policy <- b$policy; old$reference_population <- b$population
  expect_error(neon_check_support_rows(rbind(d, old)), "Mixed reference-support")
})

test_that("multiple old selected boles never become multiple individual denominators", {
  f <- individual_fixture(); f$ai$height[2] <- 20
  f$mt$recordType[2] <- "map and tag"; f$mt$pointID[2] <- "21"
  f$mt$stemDistance[2] <- sqrt(242); f$mt$stemAzimuth[2] <- 45
  x <- individual_run(f)
  expect_equal(x$comparison$n_source_selected_boles, 2)
  expect_equal(x$comparison$n_old_selected_units, 1)
  expect_equal(x$comparison$n_multiple_old_selected_boles, 1)
  expect_equal(x$comparison$n_target_individuals, 1)
  expect_equal(x$comparison$n_lost_selected_units, 1)
  expect_equal(x$comparison$n_selected_individuals, 0)
  expect_match(x$support$references$exclusion, "multiple_live_height_records")
})

test_that("standalone policy preparation replays offline and rejects changed contracts", {
  f <- individual_fixture(); b <- individual_source(f)
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE))
  vst <- file.path(root, "neon/HARV/vst"); dir.create(vst, recursive = TRUE)
  input <- file.path(vst, "harv_vst_allyears.rds")
  saveRDS(list(vst_mappingandtagging = f$mt, vst_apparentindividual = f$ai,
               vst_perplotperyear = f$pp), input)
  support <- file.path(root, "support"); d <- file.path(support, "HARV")
  dir.create(d, recursive = TRUE)
  declaration <- file.path(d, "declaration.txt"); writeLines("pinned fixture", declaration)
  neon_check_manifest(file.path(d, "input_contract.json"),
    list(files = c(input, declaration), md5 = unname(tools::md5sum(c(input, declaration)))))
  bundle_path <- file.path(d, "support_bundles.rds")
  saveRDS(setNames(list(b), neon_support_key(b$plot, b$event)), bundle_path)
  audit <- file.path(d, "reference_audit.csv"); write.csv(b$references, audit, row.names = FALSE)
  neon_check_manifest(file.path(d, "completion.json"),
    list(files = c(bundle_path, audit), md5 = unname(tools::md5sum(c(bundle_path, audit)))))
  inputs <- c(input, list.files(support, full.names = TRUE, recursive = TRUE))
  before <- tools::md5sum(inputs)
  out <- file.path(root, "individual")
  script <- normalizePath(file.path("..", "..", "scripts", "prepare_neon_individual_references.R"))
  run <- function(output = out) suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(script), "SITE=HARV", shQuote(paste0("SOURCE=", root)),
      shQuote(paste0("SUPPORT=", support)), shQuote(paste0("OUT=", output))), stdout = TRUE, stderr = TRUE))
  first <- run()
  expect_null(attr(first, "status"), info = paste(first, collapse = "\n"))
  expect_identical(tools::md5sum(inputs), before)
  x <- readRDS(file.path(out, "individual_support_bundles.rds"))[[1]]
  expect_false(x$evaluation_ready)
  expect_equal(sum(x$references$reference_selected), 1)
  hashes <- tools::md5sum(list.files(out, full.names = TRUE))
  second <- run()
  expect_null(attr(second, "status"), info = paste(second, collapse = "\n"))
  expect_true(any(grepl("replay passed", second)))
  expect_identical(tools::md5sum(names(hashes)), hashes)
  bad <- run(d)
  expect_equal(attr(bad, "status"), 1L)
  expect_true(any(grepl("separate from protected", bad)))
  contract_path <- file.path(out, "input_contract.json")
  original <- readLines(contract_path)
  contract <- jsonlite::read_json(contract_path, simplifyVector = TRUE)
  contract$policy$id <- "silently_changed"
  jsonlite::write_json(contract, contract_path, auto_unbox = TRUE)
  bad <- run()
  expect_equal(attr(bad, "status"), 1L)
  expect_true(any(grepl("Cache contract differs", bad)))
  writeLines(original, contract_path)
  writeLines("tampered", file.path(out, "individual_references.csv"))
  bad <- run()
  expect_equal(attr(bad, "status"), 1L)
  expect_true(any(grepl("Evidence receipt failed", bad)))
  expect_identical(tools::md5sum(inputs), before)
})
