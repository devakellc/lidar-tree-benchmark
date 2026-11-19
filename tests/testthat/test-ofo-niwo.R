source(file.path("..", "..", "scripts", "preflight_ofo_niwo.R"), local = TRUE)
suppressMessages(library(lidR))

# A synthetic plot: crowns of the method's own paraboloid shape on a 0.5 m
# raster, so the stem map and the surface agree at the true shift.
crown_plot <- function(seed = 1, n = 25) {
  set.seed(seed)
  r <- terra::rast(xmin = 1000, xmax = 1100, ymin = 5000, ymax = 5100, resolution = 0.5,
                   crs = "EPSG:32613")
  x <- 1020 + stats::runif(n, 0, 60); y <- 5020 + stats::runif(n, 0, 60)
  h <- stats::runif(n, 8, 30)
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  v <- numeric(nrow(xy))
  for (i in seq_len(n)) {
    rad <- max(1, 0.5 + 0.1 * h[i])
    v <- pmax(v, h[i] * pmax(0, 1 - ((xy[, 1] - x[i])^2 + (xy[, 2] - y[i])^2) / rad^2))
  }
  terra::values(r) <- v
  list(r = r, stems = data.frame(x = x, y = y, height = h, dbh = 1.5 * h + 4))
}

test_that("NIWO plots come from annotation files named <plot>_<year>.xml only", {
  paths <- c("annotations/2018_NIWO_2_450000_4426000_image_crop.xml",
             "annotations/NIWO_001_2018.xml", "annotations/NIWO_042_2018.xml",
             "annotations/NIWO_010_2019.xml", "annotations/NIWO_010_2018.xml",
             "annotations/SJER_052_2018.xml", "evaluation/RGB/NIWO_002_2018.tif",
             "annotations/NIWO_003_2018.xml.bak", "annotations/NIWO_04_2018.xml",
             "training/annotations/NIWO_005_2018.xml", "evaluation/CHM/NIWO_011_2019_CHM.tif")
  a <- niwo_annotated_plots(paths)
  expect_identical(names(a), c("plot", "annotation", "ann_year"))
  expect_identical(a$plot, c("NIWO_001", "NIWO_010", "NIWO_042"))
  # a plot annotated in two years is one unit; its files and years are kept
  expect_identical(a$ann_year, c("2018", "2018;2019", "2018"))
  expect_identical(a$annotation[2],
                   "annotations/NIWO_010_2018.xml;annotations/NIWO_010_2019.xml")
  expect_identical(niwo_annotated_plots(paths, "SJER")$plot, "SJER_052")
  expect_identical(nrow(niwo_annotated_plots(c("annotations/x.xml", paths[1]))), 0L)
  # the task's twelve plots, as the repository names their files
  task <- c(paste0("annotations/", rev(NIWO_TASK_PLOTS), "_2018.xml"), paths[1])
  expect_identical(niwo_annotated_plots(task)$plot, NIWO_TASK_PLOTS)
  expect_identical(length(NIWO_TASK_PLOTS), 12L)
})

test_that("the clip geometry is the provider's: plot centroid, nominal core, 25 m buffer", {
  pc <- data.frame(plotID = c("NIWO_001", "NIWO_042", "NIWO_005"),
                   plotType = c("distributed", "tower", "distributed"),
                   easting = c(449990, 451500.5, NA), northing = c(4433500, 4432030, 4433000),
                   epsg = 32613L, stringsAsFactors = FALSE)
  g <- niwo_clip_geometry(c("NIWO_001", "NIWO_042", "NIWO_005", "NIWO_999"), pc)
  expect_identical(names(g), c("plot", "plot_type", "cx", "cy", "core_half", "epsg", "buffer",
                               "tiles"))
  expect_equal(g$core_half, c(10, 20, NA, NA))
  expect_equal(g$buffer, rep(25, 4))
  expect_equal(g$cx[1:2], c(449990, 451500.5))
  expect_identical(g$epsg, c(32613L, 32613L, NA, NA))
  expect_identical(g$plot_type, c("distributed", "tower", NA, NA))
  # 449990 +/- 35 m crosses the 450 km tile line; 4432030 - 45 m crosses 4432 km
  expect_identical(g$tiles[1], "449000_4433000;450000_4433000")
  expect_identical(g$tiles[2], "451000_4431000;451000_4432000")
  expect_true(all(is.na(g$tiles[3:4])))
  # a box is covered only when every tile it touches was downloaded
  cv <- niwo_coverage(g, c("449000_4433000", "451000_4431000", "451000_4432000"))
  expect_identical(cv$covered, c(FALSE, TRUE, FALSE, FALSE))
  expect_identical(cv$tiles_missing[1:2], c("450000_4433000", ""))
  expect_identical(vapply(seq_len(4), function(i) niwo_missing_reason(g[i, ]), ""),
                   c("no_tiles", "no_tiles", "no_plot_record", "no_plot_record"))
})

test_that("NIWO offsets are Amendment 1's draw with the offset2 seed of the plot", {
  for (p in c("NIWO_001", "NIWO_042")) {
    set.seed(seed_for("offset2", p, NA))
    ref <- stats::runif(2, -8, 8)
    expect_identical(niwo_offset(p), ref)
  }
  expect_false(identical(niwo_offset("NIWO_001"), niwo_offset("NIWO_002")))
  expect_true(all(abs(unlist(lapply(NIWO_TASK_PLOTS, niwo_offset))) <= 8))
  # values of the first protocol's registration_units.csv (15 significant digits)
  expect_equal(niwo_offset("ABBY_001"), c(4.56538046523929, -0.387596800923347),
               tolerance = 1e-13)
  expect_equal(niwo_offset("ABBY_006"), c(4.55877708271146, -7.00603174045682),
               tolerance = 1e-13)
})

test_that("the stem pool is the first protocol's: live trees with a position, in file order", {
  gt <- data.frame(plotID = c("NIWO_001", "NIWO_001", "NIWO_001", "NIWO_002", "NIWO_001",
                              "NIWO_001", "NIWO_001"),
                   live = c(TRUE, FALSE, TRUE, TRUE, NA, TRUE, TRUE),
                   is_tree = c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, TRUE),
                   E = c(5, 2, 3, 4, 5, NA, 1), N = c(1, 2, 3, 4, 5, 6, 7),
                   height = c(10, 11, 12, 13, 14, 15, NA),
                   stemDiameter = c(20, 21, 22, 23, 24, 25, 8))
  st <- niwo_stems(gt, "NIWO_001")
  expect_identical(names(st), c("x", "y", "height", "dbh"))
  expect_equal(st$x, c(5, 1))
  expect_equal(st$dbh, c(20, 8))
  expect_identical(sum(ofo2_signal_stems(st, "height")), 1L)
  expect_identical(sum(ofo2_signal_stems(st, "rank")), 1L)
  expect_identical(nrow(niwo_stems(gt, "NIWO_003")), 0L)
})

test_that("NIWO rows carry registration_confirm.csv's columns and the frozen gates", {
  cp <- crown_plot(1)
  surf <- list(raw = ofo2_surface(cp$r, "raw"))
  off <- c(2.3, -3.1)
  res <- niwo_unit_rows("NIWO_901", "NIWO", cp$stems, surf, off)
  expect_identical(names(res), NIWO_REG_COLUMNS)
  expect_identical(res$signal, c("height", "rank"))
  expect_identical(res$variant, c(OFO_REG2$height$variant, OFO_REG2$rank$variant))
  expect_true(all(res$kind == "plot" & res$site == "NIWO" & res$unit == "NIWO_901"))
  expect_true(all(res$frozen_variant))
  expect_identical(unname(res$at_min_stems), c(TRUE, TRUE))
  expect_identical(res$n_signal, c(25L, 25L))
  expect_equal(res$offset_dx, rep(2.3, 2))
  expect_equal(res$error_m, sqrt((res$dx + off[1])^2 + (res$dy + off[2])^2))
  expect_lt(max(res$error_m), 0.5)                # the canopy is the stem map, displaced
  for (i in 1:2) {                                # the frozen gate decides
    g <- OFO_REG2[[res$signal[i]]]$gate
    a <- ofo2_accept(res$n_signal[i], res$on_edge[i], res[[g$stat]][i], g)
    expect_identical(res$accepted[i], a$accepted)
    expect_identical(res$reject_reason[i], a$reason)
  }
  expect_true(all(res$accepted))
  # under four signal stems a unit is not run; under the gate's count it is rejected
  few <- niwo_unit_rows("NIWO_902", "NIWO", cp$stems[1:3, ], surf, off)
  expect_identical(few$reject_reason, c("not_run", "not_run"))
  expect_true(all(is.na(few$dx)) && !any(few$accepted) && !any(few$at_min_stems))
  mid <- niwo_unit_rows("NIWO_903", "NIWO", cp$stems[1:12, ], surf, off)
  expect_identical(unname(mid$at_min_stems), c(FALSE, TRUE))
  expect_false(mid$accepted[1])
  expect_match(mid$reject_reason[1], "^n(;|$)")
  # the unit's name seeds only the resamples: the estimate does not depend on it
  other <- niwo_unit_rows("NIWO_905", "NIWO", cp$stems[1:12, ], surf, off)
  expect_equal(c(other$dx, other$dy), c(mid$dx, mid$dy))
})

test_that("a plot without a clip keeps its rows, rejected with the reason", {
  st <- data.frame(x = 1:5, y = 1:5, height = c(10, NA, 12, 0, 15), dbh = c(12, 9, NA, 20, 30))
  u <- niwo_unrun_rows("NIWO_904", "NIWO", st, c(1, -1), "no_tiles")
  expect_identical(names(u), NIWO_REG_COLUMNS)
  expect_identical(u$n_signal, c(3L, 3L))
  expect_identical(u$reject_reason, c("no_tiles", "no_tiles"))
  expect_false(any(u$accepted))
  expect_true(all(is.na(u$dx) & is.na(u$error_m)))
  expect_identical(unname(u$frozen_variant), c(TRUE, TRUE))
  expect_equal(u$offset_dy, c(-1, -1))
})

test_that("niwo_units.csv rows follow the contract", {
  pc <- data.frame(plotID = c("NIWO_001", "NIWO_002"), plotType = c("distributed", "tower"),
                   easting = c(449500, 450500), northing = c(4433500, 4432500), epsg = 32613L,
                   stringsAsFactors = FALSE)
  geo <- niwo_clip_geometry(c("NIWO_001", "NIWO_002", "NIWO_003"), pc)
  gt <- data.frame(plotID = "NIWO_001", live = TRUE, is_tree = TRUE, E = 449500 + 1:4,
                   N = 4433500, height = c(5, NA, 7, 9), stemDiameter = c(9, 12, 15, NA))
  clips <- data.frame(plot = c("NIWO_001", "NIWO_002"), status = c("ok", "unusable"),
                      normalized_laz = c("ofo/c/NIWO_001.laz", NA), pdens = c(12.5, NA),
                      frdens = c(6.25, NA), stringsAsFactors = FALSE)
  ann <- data.frame(plot = c("NIWO_001", "NIWO_002", "NIWO_003"),
                    annotation = paste0("annotations/NIWO_00", 1:3, "_2018.xml"),
                    ann_year = "2018", stringsAsFactors = FALSE)
  u <- niwo_units_table(geo, gt, clips, ann, "ofo/preflight2/niwo/neon/frozen_niwo_2020")
  expect_identical(names(u)[seq_along(NIWO_UNIT_COLUMNS)], NIWO_UNIT_COLUMNS)
  expect_identical(u$plot, c("NIWO_001", "NIWO_002", "NIWO_003"))
  expect_identical(u$n_live_height, c(3L, 0L, 0L))
  expect_identical(u$n_dbh10, c(2L, 0L, 0L))
  expect_identical(u$normalized_laz, c("ofo/c/NIWO_001.laz", NA, NA))
  expect_identical(u$clip_status, c("ok", "unusable", "no_plot_record"))
  expect_equal(u$core_half, c(10, 20, NA))
  expect_equal(c(u$offset_dx[1], u$offset_dy[1]), niwo_offset("NIWO_001"))
  expect_equal(u$frdens, c(6.25, NA, NA))
})

test_that("a row's CSV text does not depend on the rows written with it", {
  df <- data.frame(a = c(1 / 3, 2, NA), b = c("", "x;y", NA), c = c(TRUE, NA, FALSE),
                   d = c(1L, 2L, NA), stringsAsFactors = FALSE)
  all <- niwo_csv_lines(df)
  for (i in 1:3) {
    one <- niwo_csv_lines(df[i, ])
    expect_identical(one, all[c(1L, i + 1L)])
  }
})

test_that("signed query strings never reach the download record", {
  u <- c(paste0("https://storage.googleapis.com/neon-aop-products/2020/NEON_D13_NIWO_DP1_",
                "449000_4433000_classified_point_cloud_colorized.laz?X-Goog-Algorithm=G&",
                "X-Goog-Credential=abc&X-Goog-Signature=def"),
         "https://data.neonscience.org/api/v0/data/DP1.10098.001/NIWO/2019-08?release=RELEASE-2026",
         "https://s3.example/x.zip?AWSAccessKeyId=1&Signature=2&Expires=3",
         "https://api.github.com/repos/a/b/git/trees/abc?recursive=1", NA,
         "https://x.org/y?package=basic&token=secret", "https://x.org/plain")
  s <- niwo_safe_url(u)
  expect_identical(s[1], sub("[?].*$", "", u[1]))
  expect_identical(s[c(2, 4, 7)], u[c(2, 4, 7)])
  expect_identical(s[3], "https://s3.example/x.zip")
  expect_true(is.na(s[5]))
  expect_identical(s[6], "https://x.org/y")
})

test_that("the runner inlines self-contained recorders before the unchanged script", {
  e <- niwo_runner_expr("/repo/scripts/neon_ground_truth.R", "/job/logs/calls.jsonl")
  ex <- parse(text = e)
  expect_identical(deparse(ex[[length(ex)]]), 'source("/repo/scripts/neon_ground_truth.R")')
  # Evaluates only the two function definitions the driver generated, in an
  # environment that sees base R alone: they must not need the driver.
  env <- new.env(parent = baseenv())
  eval(ex[[1]], env)
  eval(ex[[2]], env)
  expect_true(is.function(env$.niwo_safe) && is.function(env$.niwo_trace))
  expect_identical(env$.niwo_safe("https://a/b?X-Goog-Signature=1"), "https://a/b")
  expect_match(deparse(ex[[3]]), "/job/logs/calls.jsonl", fixed = TRUE)
})

test_that("recorded calls are read back with files relative to the job directory", {
  d <- tempfile("job")
  dir.create(file.path(d, "ofo"), recursive = TRUE)
  f_in <- file.path(d, "ofo", "tile.laz")
  writeLines("x", f_in)
  log <- tempfile(fileext = ".jsonl")
  js <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
  writeLines(c(js(list(kind = "download", url = "https://a/tile.laz", file = f_in, bytes = 2)),
               js(list(kind = "download", url = "https://a/z.zip", file = "/tmp/Rtmp1/z.zip",
                       bytes = 3)),
               js(list(kind = "json", url = "https://a/loc", file = NULL, status = 200L))), log)
  x <- niwo_read_trace(log, d)
  expect_identical(x$file, c("ofo/tile.laz", "z.zip", NA))
  expect_identical(x$kept, c(TRUE, FALSE, FALSE))
  expect_identical(x$kind, c("download", "download", "json"))
  expect_null(niwo_read_trace(tempfile(), d))
})

test_that("a written file holding the NEON token is scrubbed and refused", {
  old <- Sys.getenv("NEON_TOKEN", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("NEON_TOKEN") else Sys.setenv(NEON_TOKEN = old))
  Sys.setenv(NEON_TOKEN = "tok-123-secret")
  f <- tempfile()
  writeLines(c("ok", "a tok-123-secret b"), f)
  expect_error(niwo_assert_no_token(f), "token")
  expect_false(any(grepl("tok-123-secret", readLines(f), fixed = TRUE)))
  g <- tempfile()
  writeLines("clean", g)
  expect_true(niwo_assert_no_token(g))
})

test_that("the NIWO job directory lies under <job>/ofo and never under <job>/neon", {
  d <- normalizePath(tempfile("job"), mustWork = FALSE)
  dir.create(file.path(d, "neon"), recursive = TRUE)
  ctx <- niwo_context(d)
  expect_identical(niwo_rel(ctx, ctx$root), "ofo/preflight2/niwo/neon/frozen_niwo_2020")
  expect_identical(niwo_rel(ctx, ctx$nd), "ofo/preflight2/niwo/neon/NIWO")
  expect_identical(ctx$equiv, NIWO_EQUIV)
  expect_identical(niwo_context(d, list(EQUIV = "A_001,B_002", CORES = "2"))$equiv,
                   c("A_001", "B_002"))
  dir.create(file.path(d, "ofo"))
  file.symlink(file.path(d, "neon"), file.path(d, "ofo", "preflight2"))
  expect_error(niwo_context(d))
})

test_that("the geolocation count is read from neon_ground_truth.R's log", {
  f <- tempfile()
  writeLines(c("mappable stems: 120 across 9 plots; 40 unique point locations",
               "geolocated 117 / 120 stems", "=== ground truth ==="), f)
  expect_identical(niwo_geolocated(f), c(117L, 120L))
  writeLines("nothing", f)
  expect_null(niwo_geolocated(f))
})

test_that("neon_ground_truth.R's crown-class fallback stops on tied quantiles; the guard skips", {
  lines <- readLines(file.path("..", "..", "scripts", "neon_ground_truth.R"), warn = FALSE)
  # The fallback block of the script as written (crown_class from canopy
  # position first, then height quantiles for plots of four stems or more).
  block <- function(src) {
    a <- which(startsWith(src, "need_cc <- "))
    b <- which(startsWith(src, "## ---- 4.")) - 1L
    expect_length(a, 1L)
    parse(text = src[a:b], keep.source = FALSE)
  }
  run <- function(src, g) {
    env <- new.env()
    env$g <- g
    for (e in block(src)) eval(e, env)   # the script's own fallback, on synthetic stems
    env$g$crown_class
  }
  # P_TIE: heights 8.1, 8.1, 8.6, 8.6, 8.6 give 33/66/90% quantiles 8.26, 8.6, 8.6
  g <- data.frame(plotID = rep(c("P_TIE", "P_OK"), each = 5),
                  height = c(8.1, 8.1, 8.6, 8.6, 8.6, 3, 9, 14, 20, 27),
                  crown_class = NA_character_, stringsAsFactors = FALSE)
  expect_error(run(lines, g), "not unique")
  patched <- niwo_patch_ground_truth(lines)
  expect_identical(sum(patched != lines), 1L)
  expect_identical(patched[patched != lines], NIWO_GT_GUARD)
  out <- run(patched, g)
  expect_true(all(is.na(out[1:5])))                 # no class rather than a stop
  # elsewhere the guarded fallback assigns exactly what the original does
  ok <- g[g$plotID == "P_OK", ]
  expect_identical(out[6:10], run(lines, ok))
  # quantiles 10.6, 17.84, 24.2 of heights 3, 9, 14, 20, 27
  expect_identical(out[6:10], c("suppressed", "suppressed", "intermediate", "codominant",
                                "dominant"))
  # the copy is made only from the inspected version, and only once
  expect_error(niwo_patch_ground_truth(patched), "not as inspected")
  expect_identical(digest::digest(file = file.path("..", "..", "scripts", "neon_ground_truth.R"),
                                  algo = "sha256"), NIWO_GT_SHA256)
})

test_that("the frozen method is the one protocol 2 names", {
  expect_identical(ofo2_config_digest(), NIWO_DIGEST)
  expect_identical(NIWO_SMOOTHS, "raw")
})
