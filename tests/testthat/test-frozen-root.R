source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
suppressMessages(library(lidR))

# A synthetic 2 m grid with ground and a 15 m canopy layer (single returns).
frozen_fixture <- function(d) {
  grid <- expand.grid(X = seq(499950, 500050, by = 2), Y = seq(4699950, 4700050, by = 2))
  pts <- rbind(transform(grid, Z = 100, Classification = 2L),
               transform(grid, Z = 115, Classification = 5L))
  pts$ReturnNumber <- 1L; pts$NumberOfReturns <- 1L
  las <- LAS(pts); sf::st_crs(las) <- 32618
  src <- file.path(d, "source.laz"); writeLAS(las, src)
  readLAScatalog(src, progress = FALSE)
}

seal_fixture <- function(root, ctg, rungs = c(NA, 0.25)) {
  rows <- lapply(rungs, function(r) {
    p <- frozen_clip(ctg, "HARV", "HARV_001", r, 500000, 4700000, 20, root)
    data.frame(site = "HARV", plot = "HARV_001", rung = if (is.na(r)) "native" else as.character(r),
               status = "ok", cx = 500000, cy = 4700000, core_half = 20, buffer = 25,
               seed = p$seed, seed_salt = 0L, pdens = p$pdens, frdens = p$frdens,
               native_pdens = NA_real_, native_frdens = NA_real_, stringsAsFactors = FALSE)
  })
  up <- rows[[1]]; up$rung <- "8"; up$status <- "upsampled"; up$pdens <- up$frdens <- NA
  frozen_seal(root, do.call(rbind, c(rows, list(up))))
}

test_that("salt 0 keeps every historical seed; a salt draws another realization", {
  expect_identical(seed_for("SOAP", "SOAP_001", NA), 273735632L)  # June SOAP manifest
  expect_identical(seed_for("SOAP", "SOAP_001", 4, 0L), seed_for("SOAP", "SOAP_001", 4))
  expect_false(seed_for("SOAP", "SOAP_001", 4, 1L) == seed_for("SOAP", "SOAP_001", 4))
  expect_false(seed_for("SOAP", "SOAP_001", 4, 1L) == seed_for("SOAP", "SOAP_001", 4, 2L))
})

test_that("frozen clips run lidR single-threaded and restore the caller's threads", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  withr::local_options(lidR.progress = FALSE, lidR.verbose = FALSE)
  old <- get_lidr_threads(); on.exit(set_lidr_threads(old), add = TRUE)
  set_lidr_threads(2L)
  p <- frozen_clip(frozen_fixture(d), "HARV", "HARV_001", NA, 500000, 4700000, 20,
                   file.path(d, "frozen"))
  expect_identical(get_lidr_threads(), 2L)
  mf <- jsonlite::read_json(p$manifest, simplifyVector = TRUE)
  expect_identical(mf$lidr_threads, FROZEN_LIDR_THREADS)
  expect_identical(mf$seed_salt, 0L)
  expect_identical(mf$frdens, p$frdens)      # full precision: a cache hit matches
})

test_that("a cached cell refuses a different seed salt", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  withr::local_options(lidR.progress = FALSE, lidR.verbose = FALSE)
  ctg <- frozen_fixture(d)
  frozen_clip(ctg, "HARV", "HARV_001", 0.25, 500000, 4700000, 20, file.path(d, "frozen"))
  expect_error(frozen_clip(ctg, "HARV", "HARV_001", 0.25, 500000, 4700000, 20,
                           file.path(d, "frozen"), salt = 1L), "seed differs")
})

test_that("a sealed root serves verified bytes without the catalog", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  withr::local_options(lidR.progress = FALSE, lidR.verbose = FALSE)
  root <- file.path(d, "frozen")
  ctg <- frozen_fixture(d)
  first <- frozen_clip(ctg, "HARV", "HARV_001", NA, 500000, 4700000, 20, root)
  cm <- seal_fixture(root, ctg)
  expect_true(frozen_sealed(root))
  expect_identical(cm$rung, c("native", "8", "0.25"))
  expect_true(all(nchar(cm$normalized_sha256[cm$status == "ok"]) == 64))
  got <- frozen_clip(NULL, "HARV", "HARV_001", NA, 500000, 4700000, 20, root)
  expect_identical(got$normalized, first$normalized)
  expect_identical(got$frdens, first$frdens)
  expect_null(frozen_clip(NULL, "HARV", "HARV_001", 8, 500000, 4700000, 20, root))
  expect_error(frozen_clip(NULL, "HARV", "HARV_001", 4, 500000, 4700000, 20, root),
               "not in its clip manifest")
  expect_error(frozen_clip(NULL, "HARV", "HARV_002", NA, 500000, 4700000, 20, root),
               "not in its clip manifest")
  expect_error(frozen_clip(NULL, "HARV", "HARV_001", NA, 500000, 4700000, 10, root),
               "geometry differs")
  expect_error(frozen_clip(NULL, "HARV", "HARV_001", NA, 500001, 4700000, 20, root),
               "geometry differs")
  expect_error(frozen_seal(root, cm), "already sealed")
  con <- file(first$dtm, "ab"); writeBin(as.raw(0), con); close(con)
  expect_error(frozen_clip(NULL, "HARV", "HARV_001", NA, 500000, 4700000, 20, root),
               "bytes differ")
  unlink(first$normalized)
  expect_error(frozen_read(root, "HARV", "HARV_001", NA, 500000, 4700000, 20), "bytes differ")
})

test_that("sealing refuses missing files and duplicate cells", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  cells <- data.frame(site = "HARV", plot = "HARV_001", rung = "native", status = "ok",
                      stringsAsFactors = FALSE)
  expect_error(frozen_seal(d, cells), "missing")
  expect_error(frozen_seal(d, rbind(cells, cells)), "Duplicate")
  expect_false(frozen_sealed(d))
})

test_that("populations gate stems and plots as declared", {
  gt <- data.frame(plotID = c("P1", "P1", "P1", "P2", "P2"), live = c(TRUE, TRUE, TRUE, TRUE, FALSE),
                   is_tree = TRUE, E = c(1, 2, NA, 4, 5), N = 1,
                   stemDiameter = c(12, 9.9, 30, NA, 40))
  expect_equal(nrow(frozen_reference(gt, "all_mapped")), 3L)
  expect_equal(frozen_reference(gt, "adopted")$stemDiameter, 12)
  expect_equal(frozen_reference(gt, "relaxed")$stemDiameter, 12)
  expect_error(frozen_reference(gt, "dbh5"), "Unknown population")
  expect_identical(FROZEN_POPULATIONS$min_trees[FROZEN_POPULATIONS$gate == "dbh10"], c(6L, 1L))
})

test_that("frozen_scope reads the declared plots from a sealed root only", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  root <- frozen_root(d)
  expect_identical(root, file.path(d, "neon", "frozen_2021"))
  expect_identical(frozen_root(d, "/elsewhere"), "/elsewhere")
  gt <- data.frame(plotID = "A_001", live = TRUE, is_tree = TRUE, E = 1, N = 1, stemDiameter = 5)
  expect_error(frozen_scope(d, "A", list(), gt), "No sealed frozen root")
  dir.create(root, recursive = TRUE)
  write.csv(data.frame(site = c("A", "A", "B"), plotID = c("A_001", "A_002", "B_001"),
                       in_adopted = c(TRUE, FALSE, TRUE), in_all_mapped = TRUE),
            file.path(root, "population.csv"), row.names = FALSE)
  write.csv(data.frame(site = "A", plot = "A_001", rung = "native", status = "unusable"),
            file.path(root, "clip_manifest.csv"), row.names = FALSE)
  s <- frozen_scope(d, "A", list(), gt)
  expect_identical(s$plots, "A_001")
  expect_identical(s$population, "adopted")
  expect_equal(nrow(s$gt), 0L)                     # 5 cm stem is outside the DBH gate
  s <- frozen_scope(d, "A", list(POP = "all_mapped"), gt)
  expect_identical(s$plots, c("A_001", "A_002"))
  expect_equal(nrow(s$gt), 1L)
  expect_error(frozen_scope(d, "A", list(POP = "relaxed"), gt), "not declared")
})

test_that("resumable results are tied to one sealed root and population", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  root <- file.path(d, "root"); dir.create(root)
  writeLines("a", file.path(root, "clip_manifest.csv"))
  scope <- list(root = root, population = "adopted")
  res <- file.path(d, "results.csv")
  frozen_resume_guard(res, scope)                       # fresh: writes the sidecar
  expect_true(file.exists(paste0(res, ".frozen")))
  writeLines("x", res)
  expect_silent(frozen_resume_guard(res, scope))
  expect_error(frozen_resume_guard(res, list(root = root, population = "relaxed")),
               "another frozen root")
  writeLines("b", file.path(root, "clip_manifest.csv"))
  expect_error(frozen_resume_guard(res, scope), "another frozen root")
  unlink(paste0(res, ".frozen"))                        # legacy results, no sidecar
  expect_error(frozen_resume_guard(res, scope), "move them aside")
})

test_that("rewritten results record the root and population behind them", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  root <- file.path(d, "root"); dir.create(root)
  writeLines("a", file.path(root, "clip_manifest.csv"))
  res <- file.path(d, "deepforest_results.csv"); writeLines("x", res)
  frozen_results_stamp(res, list(root = root, population = "adopted"))
  id <- jsonlite::read_json(paste0(res, ".frozen"), simplifyVector = TRUE)
  expect_identical(id$clip_manifest_sha256, frozen_root_id(root))
  expect_identical(id$population, "adopted")
  # Same sidecar as the resume guard writes, so consumers read both alike.
  expect_silent(frozen_resume_guard(res, list(root = root, population = "adopted")))
  frozen_results_stamp(res, list(root = root, population = "relaxed"))   # overwritten
  expect_identical(jsonlite::read_json(paste0(res, ".frozen"))$population, "relaxed")
})

test_that("artifact directories carry the stamp of the root that made them", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  root <- file.path(d, "root"); dir.create(root)
  writeLines("a", file.path(root, "clip_manifest.csv"))
  inst <- file.path(d, "ams3d_instances")
  expect_false(frozen_stamp_check(inst, root, strict = FALSE))
  expect_error(frozen_stamp_check(inst, root), "re-run the arm")
  frozen_stamp(inst, root)                               # new directory
  writeLines("x", file.path(inst, "P_native.laz"))
  expect_true(frozen_stamp_check(inst, root))
  expect_silent(frozen_stamp(inst, root))                # same root: keep writing
  writeLines("b", file.path(root, "clip_manifest.csv"))  # another freeze
  expect_error(frozen_stamp_check(inst, root), "not made on the frozen root")
  expect_error(frozen_stamp(inst, root), "move it aside")
  legacy <- file.path(d, "legacy"); dir.create(legacy)
  writeLines("x", file.path(legacy, "P_native.laz"))    # historical, unstamped
  expect_error(frozen_stamp(legacy, root), "move it aside")
  empty <- file.path(d, "empty"); dir.create(empty)
  expect_silent(frozen_stamp(empty, root))
  expect_error(frozen_stamp(inst, file.path(d, "none")), "No sealed frozen root")
})

test_that("a clip is canonical whatever order and gpstime ulps it was read with", {
  set.seed(7)
  pts <- data.frame(X = round(runif(400, 0, 50), 3), Y = round(runif(400, 0, 50), 3),
                    Z = round(runif(400, 0, 30), 3), gpstime = 3e5 + runif(400),
                    ReturnNumber = 1L, NumberOfReturns = 1L, Classification = 1L)
  a <- LAS(pts); sf::st_crs(a) <- 32611
  shuffled <- pts[sample(nrow(pts)), ]
  shuffled$gpstime <- shuffled$gpstime * (1 + 2e-16)       # one-ulp read noise
  b <- LAS(shuffled); sf::st_crs(b) <- 32611
  frozen_canonical(a); frozen_canonical(b)
  expect_identical(a@data, b@data)
  set.seed(1); da <- decimate_points(a, homogenize(density = 0.05, res = 5))
  set.seed(1); db <- decimate_points(b, homogenize(density = 0.05, res = 5))
  expect_identical(da@data, db@data)
})

test_that("integrity failures stop arms that otherwise skip a failed plot", {
  env <- new.env(); sys.source(file.path("..", "..", "scripts", "sweep_lib.R"), envir = env)
  bad <- tryCatch(frozen_stop("bytes differ for %s", "A_001"), error = identity)
  expect_s3_class(bad, "frozen_integrity_error")
  expect_error(env$skip_failed_plot("A_001")(bad), "bytes differ")
  expect_message(out <- env$skip_failed_plot("A_001")(simpleError("detector crashed")),
                 "plot A_001 failed: detector crashed")
  expect_null(out)
  ok <- list(NULL, data.frame(x = 1))
  expect_silent(env$stop_failed_plots(c("A", "B"), ok))
  expect_error(env$stop_failed_plots(c("A", "B", "C"), c(ok, list(simpleError("x")))),
               "plots failed: C")
})

test_that("consumers check every present artifact directory", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  root <- file.path(d, "root"); dir.create(root)
  writeLines("a", file.path(root, "clip_manifest.csv"))
  frozen_stamp(file.path(d, "ams3d_instances"), root)
  expect_true(frozen_check_artifacts(d, c("ams3d_instances", "absent_instances"), root))
  dir.create(file.path(d, "legacy_instances"))
  err <- tryCatch(frozen_check_artifacts(d, "legacy_instances", root), error = identity)
  expect_s3_class(err, "frozen_integrity_error")
})

test_that("plot_lapply keeps the integrity class across worker processes", {
  env <- new.env(); sys.source(file.path("..", "..", "scripts", "sweep_lib.R"), envir = env)
  f <- function(i) if (i == 2) frozen_stop("bytes differ for cell %d", i) else i
  environment(f) <- list2env(list(frozen_stop = frozen_stop), parent = globalenv())
  err <- tryCatch(env$plot_lapply(1:3, f, mc.cores = 2), error = identity)
  expect_s3_class(err, "frozen_integrity_error")
  expect_match(conditionMessage(err), "bytes differ for cell 2")
  expect_identical(env$plot_lapply(c(1, 3), f, mc.cores = 2), list(1, 3))
})
