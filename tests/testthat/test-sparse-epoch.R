source(file.path("..", "..", "scripts", "neon_spatial_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "neon_acquisition_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "site_extension_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "sparse_epoch_lib.R"), local = TRUE)

rscript <- function(script, args, job) suppressWarnings(system2(
  file.path(R.home("bin"), "Rscript"),
  c(shQuote(normalizePath(file.path("..", "..", "scripts", script))), args),
  env = paste0("CLAUDE_JOB_DIR=", shQuote(job)), stdout = TRUE, stderr = TRUE))

## ---- tile coverage ---------------------------------------------------------------------
# Three 1 km tiles listed; P1 (distributed) sits inside one, P2 (tower) spans
# two listed tiles, P3 lies on an unlisted tile.
cov_boxes <- function() data.frame(
  plotID = c("P1", "P2", "P3"), x = c(580500, 581010, 590500), y = c(5075500, 5074500, 5075500),
  h = c(10, 20, 10))
cov_listed <- c("580000_5075000", "580000_5074000", "581000_5074000")

test_that("box coverage lists every tile a clip needs and the ones the listing lacks", {
  cov <- se_box_coverage(cov_boxes(), cov_listed)
  expect_equal(cov$needed, c("580000_5075000", "580000_5074000;581000_5074000",
                             "590000_5075000"))
  expect_equal(cov$missing, c("", "", "590000_5075000"))
  expect_equal(cov$covered, c(TRUE, TRUE, FALSE))
  # the buffer widens the clip: P1 reaches the tile to its south at 600 m
  expect_true(grepl("580000_5074000", se_box_coverage(cov_boxes()[1, ], cov_listed,
                                                       buffer = 600)$needed))
})

test_that("dropping uncovered plots keeps the covered plots' tiles and names what is missing", {
  dr <- se_drop_uncovered(cov_boxes(), cov_listed)
  expect_equal(dr$needed, c("580000_5074000", "580000_5075000", "581000_5074000"))
  expect_equal(dr$uncovered, data.frame(plotID = "P3", missing_tiles = "590000_5075000",
                                        stringsAsFactors = FALSE))
  # a plot is uncovered when any of its boxes (one per reference) is
  b <- rbind(cov_boxes(), data.frame(plotID = "P1", x = 579995, y = 5075500, h = 10))
  dr2 <- se_drop_uncovered(b, cov_listed)
  expect_equal(dr2$uncovered$plotID, c("P1", "P3"))
  expect_equal(dr2$uncovered$missing_tiles[1], "579000_5075000")
  expect_false("580000_5075000" %in% dr2$needed)
  # every plot covered: nothing dropped, the needed tiles of the stop mode
  all <- se_drop_uncovered(cov_boxes()[1:2, ], cov_listed)
  expect_equal(nrow(all$uncovered), 0L)
  expect_equal(all$needed, sort(unique(unlist(strsplit(
    se_box_coverage(cov_boxes()[1:2, ], cov_listed)$needed, ";")))))
})

test_that("a plot partly covered by the needed tiles stops instead of freezing a partial clip", {
  b <- rbind(cov_boxes(), data.frame(plotID = "P4", x = 580990, y = 5075500, h = 20))
  expect_error(se_drop_uncovered(b, cov_listed), "partial clips: P4")
})

## ---- common plots of two roots -----------------------------------------------------------
pop_fixture <- function() list(
  pop21 = data.frame(site = c("WREF", "WREF", "WREF", "ABBY"), plotID = c("W1", "W2", "W3", "A1"),
                     in_adopted = c(TRUE, TRUE, FALSE, TRUE)),
  popS = data.frame(site = c("WREF", "WREF", "WREF", "ABBY"), plotID = c("W2", "W1", "W3", "A1"),
                    in_adopted = c(TRUE, TRUE, TRUE, TRUE)),
  cm = function(ok) data.frame(site = "WREF", plot = c("W1", "W1", "W2", "W3"),
                               rung = c("native", "8", "native", "native"), status = ok))

test_that("common plots are adopted in both roots, with an ok native clip when asked", {
  f <- pop_fixture()
  expect_equal(se_common_plots(f$pop21, f$popS, "WREF"), c("W1", "W2"))
  both <- f$cm(c("ok", "ok", "ok", "ok"))
  expect_equal(se_common_plots(f$pop21, f$popS, "WREF", both, both), c("W1", "W2"))
  # W2 has no clip on the epoch side (the flight missed it); a decimated cell
  # does not stand in for the native one
  epoch <- f$cm(c("unusable", "ok", "unusable", "ok"))
  expect_equal(se_common_plots(f$pop21, f$popS, "WREF", both, epoch), character())
  epoch <- f$cm(c("ok", "ok", "unusable", "ok"))
  expect_equal(se_common_plots(f$pop21, f$popS, "WREF", both, epoch), "W1")
  expect_error(se_common_plots(f$pop21, f$popS, "WREF", both, NULL), "both roots")
})

## ---- compare_sparse_epoch.R MODE=prepare -----------------------------------------------
# Two plots adopted in both roots; W2 has no native clip in the epoch root.
# Stem s4 is adopted only in the epoch; s5 was last recorded in 2015.
compare_fixture <- function(root) {
  w <- file.path(root, "work"); ep <- file.path(w, "epoch")
  r21 <- file.path(w, "neon", "frozen_2021"); rS <- file.path(ep, "neon", "frozen_2019")
  for (p in c(r21, rS, file.path(w, "neon", "WREF"), file.path(ep, "neon", "WREF", "vst")))
    dir.create(p, recursive = TRUE, showWarnings = FALSE)
  pop <- data.frame(site = "WREF", plotID = c("W1", "W2"), plotType = "distributed",
                    easting = c(580500, 581500), northing = 5075500, core_half = 10,
                    epsg = 32610, in_adopted = TRUE, in_all_mapped = TRUE, in_relaxed = TRUE)
  stems <- function(ids, plots) data.frame(site = "WREF", population = "adopted",
                                           plotID = plots, individualID = ids)
  write.csv(pop, file.path(r21, "population.csv"), row.names = FALSE)
  write.csv(pop, file.path(rS, "population.csv"), row.names = FALSE)
  write.csv(stems(c("s1", "s2", "s3"), c("W1", "W1", "W2")),
            file.path(r21, "population_stems.csv"), row.names = FALSE)
  write.csv(stems(c("s1", "s2", "s3", "s4", "s5"), c("W1", "W1", "W2", "W1", "W1")),
            file.path(rS, "population_stems.csv"), row.names = FALSE)
  cm <- function(st) data.frame(site = "WREF", plot = c("W1", "W2"), rung = "native", status = st)
  write.csv(cm(c("ok", "ok")), file.path(r21, "clip_manifest.csv"), row.names = FALSE)
  write.csv(cm(c("ok", "unusable")), file.path(rS, "clip_manifest.csv"), row.names = FALSE)
  gt <- function(ids, plots, yr) data.frame(individualID = ids, plotID = plots, E = 580500,
    N = 5075500, height = 30, live = TRUE, is_tree = TRUE, acquisition_year = yr)
  pc <- data.frame(plotID = c("W1", "W2"), plotType = "distributed", easting = c(580500, 581500),
                   northing = 5075500, utmZone = "10N")
  write.csv(gt(c("s1", "s2", "s3"), c("W1", "W1", "W2"), 2021),
            file.path(w, "neon", "WREF", "ground_truth_stems.csv"), row.names = FALSE)
  write.csv(pc, file.path(w, "neon", "WREF", "plot_centroids.csv"), row.names = FALSE)
  write.csv(gt(c("s1", "s2", "s3", "s4", "s5"), c("W1", "W1", "W2", "W1", "W1"), 2019),
            file.path(ep, "neon", "WREF", "ground_truth_stems.csv"), row.names = FALSE)
  write.csv(pc, file.path(ep, "neon", "WREF", "plot_centroids.csv"), row.names = FALSE)
  ai <- data.frame(individualID = c("s1", "s2", "s3", "s4", "s5"),
                   date = c("2019-07-01", "2021-07-01", "2022-07-01", "2019-07-01", "2015-07-01"))
  saveRDS(list(vst_apparentindividual = ai),
          file.path(ep, "neon", "WREF", "vst", "wref_vst_allyears.rds"))
  list(work = w, epoch = ep, c21 = file.path(w, "c21"))
}

test_that("compare prepare keeps its defaults and can require clips and skip the strata", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE))
  f <- compare_fixture(root)
  run <- function(...) rscript("compare_sparse_epoch.R", c("MODE=prepare",
    paste0("EPOCHS=WREF:", f$epoch, ":2019"), paste0("C21=", f$c21), ...), f$work)
  ids <- function(dir) sort(read.csv(file.path(dir, "neon", "WREF",
                                               "ground_truth_stems.csv"))$individualID)
  out <- run()
  expect_null(attr(out, "status"), info = paste(out, collapse = "\n"))
  expect_equal(ids(file.path(f$epoch, "compare_shared")), c("s1", "s2", "s3"))
  expect_equal(ids(file.path(f$c21, "shared")), c("s1", "s2", "s3"))
  expect_equal(ids(file.path(f$epoch, "compare_2015only")), "s5")
  expect_true(dir.exists(file.path(f$epoch, "strata_remeasured")))
  # the 2021 rows on both sides
  expect_equal(unique(read.csv(file.path(f$epoch, "compare_shared", "neon", "WREF",
                                         "ground_truth_stems.csv"))$acquisition_year), 2021)
  unlink(c(file.path(f$epoch, c("compare_shared", "compare_2015only", "strata_2015only",
                                "strata_remeasured", "strata_remeasured_noheight")), f$c21),
         recursive = TRUE)
  out <- run("CLIPPED=TRUE", "STRATA=FALSE")
  expect_null(attr(out, "status"), info = paste(out, collapse = "\n"))
  expect_equal(ids(file.path(f$epoch, "compare_shared")), c("s1", "s2"))
  expect_equal(ids(file.path(f$c21, "shared")), c("s1", "s2"))
  expect_true(any(grepl("common adopted plots 1, shared stems 2", out)))
  expect_false(dir.exists(file.path(f$epoch, "compare_2015only")))
  expect_false(dir.exists(file.path(f$epoch, "strata_remeasured")))
  expect_false(dir.exists(file.path(f$c21, "only2015")))
  bad <- run("CLIPPED=maybe")
  expect_equal(attr(bad, "status"), 1L)
})

## ---- prepare_sparse_epoch.R on a UTM 10N fixture ---------------------------------------
# Two tiny tiles stand in for the listed 1 km tiles; plot D3's tile is not
# listed. The cached listing carries their sizes and CRC32C, so nothing is
# downloaded.
prepare_fixture <- function(root) {
  w <- file.path(root, "work"); j <- file.path(w, "epoch"); nd <- file.path(j, "neon", "WREF")
  dir.create(file.path(nd, "lidar"), recursive = TRUE)
  dir.create(file.path(w, "neon", "frozen_2021"), recursive = TRUE)
  pc <- data.frame(plotID = c("D1", "D2", "D3"), plotType = "distributed",
                   easting = c(580500, 581500, 590500), northing = 5075500, utmZone = "10N",
                   epsg = 32610L, datum = "WGS84", acquisition_year = 2019L)
  gt <- data.frame(individualID = paste0("s", 1:3), plotID = pc$plotID, E = pc$easting,
                   N = pc$northing, stemDiameter = 20, live = TRUE, is_tree = TRUE,
                   acquisition_year = 2019L, utmZone = "10N", epsg = 32610L)
  write.csv(pc, file.path(nd, "plot_centroids.csv"), row.names = FALSE)
  write.csv(gt, file.path(nd, "ground_truth_stems.csv"), row.names = FALSE)
  pop <- data.frame(site = "WREF", plotID = c("D1", "D2"), plotType = "distributed",
                    easting = c(580500, 581500), northing = 5075500, core_half = 10)
  write.csv(pop, file.path(w, "neon", "frozen_2021", "population.csv"), row.names = FALSE)
  # as a download would have left it: the manifest first, then the tiles
  neon_acquisition_manifest(file.path(nd, "lidar"), "DP1.30003.001", 2019, 32610)
  files <- list()
  for (e in c(580000, 581000)) {
    name <- sprintf("NEON_D16_WREF_DP1_%d_5075000_classified_point_cloud_colorized.laz", e)
    las <- lidR::LAS(data.frame(X = e + c(400, 500, 600), Y = 5075500, Z = c(1, 2, 3)))
    sf::st_crs(las) <- 32610L
    lidR::writeLAS(las, file.path(nd, "lidar", name))
    files[[name]] <- data.frame(name = name, size = file.size(file.path(nd, "lidar", name)),
      crc32c = digest::digest(file = file.path(nd, "lidar", name), algo = "crc32c"))
  }
  jsonlite::write_json(list(product = "DP1.30003.001", site = "WREF", month = "2019-07",
                            release = "RELEASE-2026", files = do.call(rbind, files)),
                       file.path(nd, "lidar_files.json"), auto_unbox = TRUE, digits = NA)
  list(work = w, job = j, nd = nd)
}

test_that("prepare drops plots without listed tiles only when asked, in the site's own frame", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE))
  f <- prepare_fixture(root)
  run <- function(...) rscript("prepare_sparse_epoch.R",
                               c("MONTHS=WREF:2019-07", "DOWNLOAD=FALSE", ...), f$job)
  out <- run()
  expect_equal(attr(out, "status"), 1L)
  expect_true(any(grepl("lists no tile for 590000_5075000", out)))
  out <- run("MISSING_TILES=drop")
  expect_null(attr(out, "status"), info = paste(out, collapse = "\n"))
  unc <- read.csv(file.path(f$nd, "uncovered_plots.csv"))
  expect_equal(unc$plotID, "D3")
  expect_equal(unc$missing_tiles, "590000_5075000")
  dl <- read.csv(file.path(f$nd, "downloaded_tiles.csv"))
  expect_true(all(dl$verified & dl$needed))
  mf <- jsonlite::read_json(file.path(f$nd, "lidar", "acquisition_manifest.json"))
  expect_equal(mf$epsg, 32610L)
  expect_equal(mf$year, 2019L)
  expect_true(any(grepl("uncovered_plots", out)))
})

## ---- core coverage -----------------------------------------------------------------------
test_that("core coverage is the share of the core's cells holding a point", {
  g <- expand.grid(x = seq(-9.5, 9.5, by = 1), y = seq(-9.5, 9.5, by = 1))
  expect_equal(se_core_cover(g$x + 500, g$y + 700, 500, 700, 10), 1)
  half <- g$x >= 0                                   # the flight's edge runs through the core
  expect_equal(se_core_cover(g$x[half] + 500, g$y[half] + 700, 500, 700, 10), 0.5)
  # points outside the core never count, and a 4 m grid has 25 cells
  expect_equal(se_core_cover(c(500, 530), c(700, 700), 500, 700, 10, res = 4), 1 / 25)
  expect_equal(se_core_cover(numeric(), numeric(), 500, 700, 10), 0)
})

# Two sealed roots of real (tiny) clips; the epoch's W2 clip covers only the
# eastern half of its core, as at the edge of a flight.
seal_fixture_root <- function(root, epoch_side) {
  source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
  cells <- list()
  for (p in c("W1", "W2")) {
    cx <- if (p == "W1") 580500 else 581500; cy <- 5075500
    g <- expand.grid(X = cx + seq(-34.5, 34.5, by = 1), Y = cy + seq(-34.5, 34.5, by = 1))
    if (epoch_side && p == "W2") g <- g[g$X >= cx, ]
    g$Z <- 10; g$ReturnNumber <- 1L; g$NumberOfReturns <- 1L; g$Classification <- 2L
    las <- lidR::LAS(g); sf::st_crs(las) <- 32610L
    fp <- frozen_files(frozen_dir(root, "WREF", p, NA))
    dir.create(dirname(fp$normalized), recursive = TRUE)
    lidR::writeLAS(las, fp$normalized); lidR::writeLAS(las, fp$rawground)
    terra::writeRaster(terra::rast(nrows = 2, ncols = 2, vals = 0), fp$dtm)
    jsonlite::write_json(list(pdens = 1, frdens = 1, seed = 1), fp$manifest, auto_unbox = TRUE)
    cells[[p]] <- data.frame(site = "WREF", plot = p, rung = "native", status = "ok", cx = cx,
                             cy = cy, core_half = 10, buffer = 25)
  }
  file.remove(file.path(root, "clip_manifest.csv"))
  frozen_seal(root, do.call(rbind, cells))
}

test_that("compare prepare drops plots whose clip misses part of the core when asked", {
  root <- tempfile(); dir.create(root); on.exit(unlink(root, recursive = TRUE))
  f <- compare_fixture(root)
  seal_fixture_root(file.path(f$work, "neon", "frozen_2021"), FALSE)
  seal_fixture_root(file.path(f$epoch, "neon", "frozen_2019"), TRUE)
  run <- function(...) rscript("compare_sparse_epoch.R", c("MODE=prepare",
    paste0("EPOCHS=WREF:", f$epoch, ":2019"), paste0("C21=", f$c21), "STRATA=FALSE", ...), f$work)
  out <- run("CLIPPED=TRUE", "MIN_CORE_COVER=0.9")
  expect_null(attr(out, "status"), info = paste(out, collapse = "\n"))
  expect_true(any(grepl("core coverage below 0.9 drops W2", out)))
  gt <- read.csv(file.path(f$epoch, "compare_shared", "neon", "WREF", "ground_truth_stems.csv"))
  expect_equal(sort(gt$individualID), c("s1", "s2"))
  for (dir in c(file.path(f$epoch, "compare_shared"), file.path(f$c21, "shared"))) {
    cov <- read.csv(file.path(dir, "neon", "WREF", "core_cover.csv"))
    expect_equal(cov$plotID, c("W1", "W2"))
    expect_equal(cov$core_cover_epoch, c(1, 0.5))
    expect_equal(cov$core_cover_2021, c(1, 1))
    expect_equal(cov$kept, c(TRUE, FALSE))
  }
  expect_equal(attr(run("MIN_CORE_COVER=0.9"), "status"), 1L)      # needs CLIPPED=TRUE
  expect_equal(attr(run("CLIPPED=TRUE", "MIN_CORE_COVER=2"), "status"), 1L)
})
