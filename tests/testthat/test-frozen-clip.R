source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
suppressMessages(library(lidR))

test_that("frozen clips verify CRS, geometry, source identity and complete files", {
  d <- tempfile(); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  withr::local_options(lidR.progress = FALSE, lidR.verbose = FALSE)
  grid <- expand.grid(X = seq(499950, 500050, by = 5), Y = seq(4699950, 4700050, by = 5))
  pts <- rbind(transform(grid, Z = 100, Classification = 2L),
               transform(grid, Z = 115, Classification = 5L))
  pts$ReturnNumber <- 1L; pts$NumberOfReturns <- 1L
  las <- LAS(pts); sf::st_crs(las) <- 32618
  src <- file.path(d, "source.laz"); writeLAS(las, src)
  ctg <- readLAScatalog(src, progress = FALSE)
  call_clip <- function(cx = 500000, buffer = 25, catalog = ctg)
    frozen_clip(catalog, "HARV", "HARV_001", NA, cx, 4700000, 20, file.path(d, "frozen"), buffer)
  first <- call_clip()
  expect_true(all(file.exists(unlist(first[c("rawground", "normalized", "dtm", "manifest")]))))
  before <- tools::md5sum(unlist(first[c("rawground", "normalized", "dtm", "manifest")]))
  again <- call_clip()
  expect_equal(again$seed, first$seed)
  expect_error(call_clip(cx = 500001), "coordinate cache differs")
  expect_error(call_clip(buffer = 20), "coordinate cache differs")
  wrong <- ctg; sf::st_crs(wrong) <- 32619
  expect_error(call_clip(catalog = wrong), "coordinate cache differs")
  Sys.setFileTime(src, Sys.time() + 60)
  expect_error(call_clip(), "coordinate cache differs")
  expect_identical(tools::md5sum(names(before)), before)
  mf <- jsonlite::read_json(first$manifest, simplifyVector = TRUE)
  expect_error(neon_verify_clip(list(), mf$coordinate_contract, first$rawground), "lacks provenance")
  unlink(first$dtm)
  expect_error(neon_verify_clip(mf, mf$coordinate_contract, c(first$rawground, first$dtm)), "Incomplete")
})

test_that("seed_for is deterministic and varies by key", {
  expect_equal(seed_for("SOAP", "SOAP_001", 8), seed_for("SOAP", "SOAP_001", 8))
  expect_false(seed_for("SOAP", "SOAP_001", 8) == seed_for("SOAP", "SOAP_001", 4))
  expect_false(seed_for("SOAP", "SOAP_001", 8) == seed_for("SOAP", "SOAP_002", 8))
  expect_type(seed_for("SOAP", "SOAP_001", 8), "integer")
})

test_that("seeded homogenize decimation is reproducible", {
  set.seed(123)
  big <- LAS(data.frame(X = runif(5000, 0, 50), Y = runif(5000, 0, 50),
                        Z = runif(5000, 0, 30)))
  s <- seed_for("SOAP", "SOAP_001", 8)
  set.seed(s); a <- decimate_points(big, homogenize(density = 8, res = 5))
  set.seed(s); b <- decimate_points(big, homogenize(density = 8, res = 5))
  expect_equal(npoints(a), npoints(b))
  expect_equal(a@data$X, b@data$X)     # identical point subset, not just count
})

# Regression guard for issue #33: the crown density-robustness PNGs were never
# emitted because crown_metrics_sweep's frdens reader rebuilt the frozen manifest
# path with one fewer "site" segment than frozen_clip() actually writes (the
# detection ladder passes out_root = d/neon/<SITE>/frozen, so the realized layout
# is out_root/<SITE>/<plot>/<rung> -- the site segment appears under out_root).
# frozen_dir() is now the SINGLE source of truth both sides share; these tests
# pin the doubled-site layout and the reader/writer round-trip so a path drift
# cannot regress silently behind the plotter's no-op branch.

test_that("frozen_dir matches frozen_clip's realized layout (doubled site seg)", {
  # out_root exactly as the run_site() caller passes it for the crown ladder.
  out_root <- file.path("/work", "neon", "SOAP", "frozen")
  expect_equal(frozen_dir(out_root, "SOAP", "SOAP_001", 4),
               file.path("/work/neon/SOAP/frozen/SOAP/SOAP_001/4"))
  # NA and the literal "native" both collapse to the "native" rung segment,
  # exactly as frozen_clip writes ifelse(is.na(rung), "native", rung).
  expect_equal(frozen_dir(out_root, "SOAP", "SOAP_001", NA),
               file.path("/work/neon/SOAP/frozen/SOAP/SOAP_001/native"))
  expect_equal(frozen_dir(out_root, "SOAP", "SOAP_001", "native"),
               frozen_dir(out_root, "SOAP", "SOAP_001", NA))
})

test_that("a manifest written under frozen_dir is found by reconstructing it", {
  # Mirror the bug's exact failure mode end-to-end: write a manifest at the
  # frozen_dir path (where frozen_clip would), then reconstruct the read path the
  # SAME way the frdens reader does, and assert file.exists() is TRUE (it was
  # always FALSE before the fix because the read path dropped the inner site).
  d <- file.path(tempdir(), paste0("frzn-", as.integer(runif(1, 1, 1e9))))
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  out_root <- file.path(d, "neon", "SOAP", "frozen")
  wdir <- frozen_dir(out_root, "SOAP", "SOAP_001", 4)
  dir.create(wdir, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(list(pdens = 12.5, frdens = 3.9, seed = 1L),
                       file.path(wdir, "manifest.json"), auto_unbox = TRUE)

  # The frdens reader's reconstruction: froot = d/neon/<site>/frozen, then
  # frozen_dir(froot, site, plot, rung).
  froot <- file.path(d, "neon", "SOAP", "frozen")
  mf <- file.path(frozen_dir(froot, "SOAP", "SOAP_001", 4), "manifest.json")
  expect_true(file.exists(mf))
  expect_equal(jsonlite::read_json(mf, simplifyVector = TRUE)$frdens, 3.9)

  # And the pre-fix WRONG path (missing the inner site segment) must NOT exist,
  # so the regression itself is pinned.
  wrong <- file.path(d, "neon", "SOAP", "frozen", "SOAP_001", "4",
                     "manifest.json")
  expect_false(file.exists(wrong))
})
