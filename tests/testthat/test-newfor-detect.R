# Unit tests for the NEWFOR detection and analysis drivers
# (detect_newfor_multichm.R, analyze_newfor_multichm.R): arguments, the
# detector pins (library blob and package versions), the git record, exact
# detection files, the registration move, a two-area freeze root built through
# the freeze driver and run end to end, the refusals of a foreign run root and
# of a root frozen under another protocol, the guards that keep the population
# whole (the admission table against the area folders and cell.json, an area
# whose scoring fails, a rerun leaving nothing of the earlier one), re-scoring
# from the written detections in one and two workers and with explicit null
# offsets, the analysis's outputs and refusals, its statement of the
# protocol's settings, its pools, the protocol's reading rule and a hand-made
# cells table pooled by hand in every scenario, the after-run checks
# (check_newfor_run.R: arguments, forest weights, forest-resampled contrasts on
# hand-made cells, registration moves on hand-placed detections over the
# synthetic root, and run_main on the synthetic run), and the R files that the
# records of the four scripts (the freeze's included) hash, checked against
# the files their source() calls reach. Synthetic data only; nothing
# here reads the release. Sourcing a script defines its helpers without
# running it (guarded by `if (sys.nframe() == 0L) run_main()`); each script
# gets its own environment, so the run_main() functions do not collide.
#
# Sourcing a script evaluates its default job directory, so CLAUDE_JOB_DIR is
# a fresh temporary folder while this file runs: testthat restores the
# variable and removes the folder when the file ends, and nothing is created
# in the checkout.
#
# Where the installed lidR or lidRplugins is not the version the protocol
# pins, the end-to-end fixture runs with ALLOW_UNPINNED=1, and the assertions
# that hold only for a pinned run assert the unpinned outcome instead
# (NF_PINNED). The tests of the pins themselves set the pins they need.
suppressMessages({ library(lidR); library(data.table); library(sf); library(terra) })
NF_JOB <- withr::local_tempdir("newfor-job-")
withr::local_envvar(CLAUDE_JOB_DIR = NF_JOB)
DET <- new.env()
source(file.path("..", "..", "scripts", "detect_newfor_multichm.R"), local = DET)
ANA <- new.env()
source(file.path("..", "..", "scripts", "analyze_newfor_multichm.R"), local = ANA)
FRZ <- new.env()
source(file.path("..", "..", "scripts", "freeze_newfor.R"), local = FRZ)
CHK <- new.env()
source(file.path("..", "..", "scripts", "check_newfor_run.R"), local = CHK)
# TRUE when the installed lidR and lidRplugins are the protocol's pins.
NF_PINNED <- isTRUE(DET$nfd_check_versions(allow_unpinned = TRUE)$versions_match)
# A run's arguments, with ALLOW_UNPINNED=1 added where the installed versions
# are not the pins (an argument list that sets it is kept as it is).
nf_args <- function(...) {
  A <- list(...)
  if (!NF_PINNED && is.null(A[["ALLOW_UNPINNED"]])) A[["ALLOW_UNPINNED"]] <- "1"
  A
}

## ---- a synthetic two-area release, frozen through the library ---------------------------------
NF_X0 <- 600000; NF_Y0 <- 5100000; NF_EPSG <- 32632L
nf_terrain <- function(x, y) 1000 + 0.2 * (x - NF_X0) + 0.1 * (y - NF_Y0)

# Crowns on an 8 m grid around (cx, cy), 12 to 28 m tall, and one 6 m tree
# between them; heights cycle so that both mid and tall bands are filled.
nf_trees <- function(cx, cy) {
  g <- expand.grid(i = -3:3, j = -3:3)
  rbind(data.frame(x = cx + 8 * g$i, y = cy + 8 * g$j, h = 12 + (seq_len(nrow(g)) * 7) %% 17,
                   r = 2.8),
        data.frame(x = cx + 4, y = cy + 4, h = 6, r = 1.5))
}

# The cloud: a ground grid of `step` m over the polygon's box widened by 40 m,
# a cone of first returns per crown with its apex point, and later returns
# inside each crown.
nf_las <- function(cx, cy, step, n, seed) {
  set.seed(seed)
  g <- expand.grid(x = seq(cx - 40, cx + 40, step), y = seq(cy - 40, cy + 40, step))
  pts <- list(data.frame(x = g$x, y = g$y, hgt = 0.05, rn = 1L, nr = 1L, cls = 2L))
  t <- nf_trees(cx, cy)
  for (i in seq_len(nrow(t))) {
    d <- t$r[i] * sqrt(runif(n)); a <- runif(n, 0, 2 * pi)
    d2 <- 0.8 * t$r[i] * sqrt(runif(n %/% 4)); a2 <- runif(n %/% 4, 0, 2 * pi)
    pts <- c(pts, list(
      data.frame(x = t$x[i] + d * cos(a), y = t$y[i] + d * sin(a),
                 hgt = t$h[i] * (1 - 0.6 * d / t$r[i]) - 0.05, rn = 1L, nr = 2L, cls = 1L),
      data.frame(x = t$x[i], y = t$y[i], hgt = t$h[i], rn = 1L, nr = 2L, cls = 1L),
      data.frame(x = t$x[i] + d2 * cos(a2), y = t$y[i] + d2 * sin(a2),
                 hgt = runif(n %/% 4, 2, 0.8 * t$h[i]), rn = 2L, nr = 2L, cls = 1L)))
  }
  p <- do.call(rbind, pts)
  x <- round(p$x, 3); y <- round(p$y, 3)
  suppressWarnings(suppressMessages(lidR::LAS(data.frame(
    X = x, Y = y, Z = nf_terrain(x, y) + p$hgt, gpstime = as.numeric(seq_len(nrow(p))),
    ReturnNumber = p$rn, NumberOfReturns = p$nr, Classification = p$cls))))
}

# A shapefile as the release ships them: no .prj for a layer without a CRS.
nf_write_shp <- function(x, path) {
  sf::st_write(x, path, quiet = TRUE, delete_dsn = file.exists(path))
  if (is.na(sf::st_crs(x))) unlink(sub("\\.shp$", ".prj", path))
}

# Two areas 1 km apart: 91 (square polygon, sparse cloud, admitted) and 92
# (circular polygon, dense cloud, flown 84 months after its field survey, so
# it fails the time-gap rule only).
NF_AREAS <- data.frame(id = c("91", "92"), forest = c("Alpha Wood", "Beta-Forest"),
                       sheet = c("91_Metadata.pdf", "92_Metadata.pdf"), epsg = NF_EPSG,
                       field_date = c("2012-06", "2005-01"), flight_date = c("2012-09", "2012-01"),
                       caliper_cm = c(7.5, 5), gap_months = c(3L, 84L),
                       cx = NF_X0 + c(50, 1050), cy = NF_Y0 + 50, step = c(1, 0.5),
                       n = c(500L, 1200L), stringsAsFactors = FALSE)

# Inventory: a stem below each crown, plus an 8 cm stem without a crown
# (inventoried, not primary).
nf_ref <- function(cx, cy) {
  t <- nf_trees(cx, cy)
  data.frame(E = c(t$x, cx - 4), N = c(t$y, cy + 4), DBHRef = c(0.15 + t$h / 100, 0.08),
             HRef = c(t$h, 4), VolRef = 1)
}

nf_release <- function(dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  fn <- character()
  for (i in seq_len(nrow(NF_AREAS))) {
    a <- NF_AREAS[i, ]; id <- a$id; cx <- a$cx; cy <- a$cy
    lidR::writeLAS(nf_las(cx, cy, a$step, a$n, seed = i), file.path(dir, paste0(id, "_ALS.laz")))
    r <- terra::rast(xmin = cx - 60, xmax = cx + 60, ymin = cy - 60, ymax = cy + 60,
                     resolution = 1, crs = "")
    xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
    terra::values(r) <- nf_terrain(xy[, 1], xy[, 2])
    terra::writeRaster(r, file.path(dir, paste0(id, "_DTM.tif")))
    poly <- if (id == "91")
      sf::st_sfc(sf::st_polygon(list(rbind(c(cx - 15, cy - 15), c(cx + 15, cy - 15),
                                           c(cx + 15, cy + 15), c(cx - 15, cy + 15),
                                           c(cx - 15, cy - 15)))))
      else sf::st_buffer(sf::st_sfc(sf::st_point(c(cx, cy))), 15, nQuadSegs = 16)
    nf_write_shp(sf::st_sf(id = 1L, geometry = poly), file.path(dir, paste0(id, "_AoI.shp")))
    ref <- nf_ref(cx, cy)
    nf_write_shp(sf::st_sf(DBHRef = ref$DBHRef, HRef = ref$HRef, VolRef = ref$VolRef,
                           geometry = sf::st_sfc(lapply(seq_len(nrow(ref)), function(k)
                             sf::st_point(c(ref$E[k], ref$N[k]))))),
                 file.path(dir, paste0(id, "_Ref.shp")))
    writeLines(paste("plot sheet", id), file.path(dir, a$sheet))
    fn <- c(fn, newfor_area_files(id, a$sheet))
  }
  p <- file.path(dir, fn)
  data.frame(filename = fn, id = seq_along(fn), bytes = file.size(p),
             md5 = unname(tools::md5sum(p)), sha256 = vapply(p, frozen_sha256, ""),
             stringsAsFactors = FALSE, row.names = NULL)
}

NF_K <- 4L
# The value of expr, with what it prints to the console discarded.
quiet <- function(expr) {
  val <- NULL
  utils::capture.output(val <- expr)
  val
}

# A sealed root of the two areas, frozen by the freeze driver (newfor_freeze)
# under `protocol`, with the metadata and the pinned file list written beside
# the root in <dirname(root)>/docs.
nf_root <- function(raw, root, protocol) {
  files <- nf_release(raw)
  docs <- file.path(dirname(root), "docs")
  dir.create(docs, showWarnings = FALSE)
  meta <- file.path(docs, "meta.json"); lst <- file.path(docs, "files.json")
  jsonlite::write_json(list(release = list(doi = "10.0/synthetic", version = "1.0"),
                            areas = NF_AREAS[c("id", "forest", "sheet", "epsg", "field_date",
                                               "flight_date", "caliper_cm")]),
                       meta, auto_unbox = TRUE, digits = NA)
  jsonlite::write_json(list(doi = "10.0/synthetic", version = "1.0", n_files = nrow(files),
                            files = files), lst, auto_unbox = TRUE, digits = NA)
  quiet(suppressMessages(FRZ$newfor_freeze(raw, root, meta, lst, protocol)))
  root
}

# SHA-256 of every file under a folder, named by relative path.
nf_hashes <- function(dir) {
  f <- sort(list.files(dir, recursive = TRUE, all.files = TRUE), method = "radix")
  stats::setNames(vapply(file.path(dir, f), frozen_sha256, ""), f)
}

# One end-to-end run, shared by the tests below: root, protocol copy, run root
# and the detection run's return value (built on first use; with
# ALLOW_UNPINNED=1 where the installed versions are not the pins).
nf_e2e <- local({
  cache <- NULL
  function() {
    if (!is.null(cache)) return(cache)
    base <- tempfile("newfor-detect-")
    dir.create(base)
    proto <- file.path(base, "protocol.md")
    file.copy(DET$.nfd_repo_file(file.path("docs", "newfor-validation-protocol.md")), proto)
    root <- nf_root(file.path(base, "raw"), file.path(base, "frozen"), proto)
    out <- file.path(base, "run")
    res <- quiet(DET$run_main(nf_args(FROZEN = root, OUT = out, PROTOCOL = proto,
                                      K = as.character(NF_K))))
    cache <<- list(base = base, root = root, protocol = proto, out = out, res = res)
    cache
  }
})

# The run's areas rebuilt from the root and the written detection files.
nf_items <- function(e) {
  feats <- read.csv(file.path(e$out, "features.csv"), stringsAsFactors = FALSE,
                    colClasses = c(area = "character"))
  lab <- vapply(newfor_configs(), mcg_config_label, "")
  stats::setNames(lapply(feats$area, function(id) {
    fa <- newfor_frozen_area(e$root, id)
    f <- feats[feats$area == id, ]
    list(id = id, forest = f$forest, admitted = f$admitted, aoi = fa$aoi, stems = fa$stems,
         det = lapply(lab, function(l)
           DET$nfd_read_detections(file.path(e$out, "detections", id, paste0(l, ".csv")))),
         reg = c(dx = f$dx, dy = f$dy, offset = f$offset))
  }), feats$area)
}

## ---- arguments ---------------------------------------------------------------------------------
test_that("arguments are KEY=VALUE split at the first '='; unknown or repeated keys stop", {
  expect_identical(DET$nfd_args(character()), list())
  expect_identical(DET$nfd_args(c("FROZEN=/a=b/root", "K=5")), list(FROZEN = "/a=b/root", K = "5"))
  expect_error(DET$nfd_args("FROZEN_ROOT=/x"), "unknown argument FROZEN_ROOT=")
  expect_error(DET$nfd_args("FROZEN"), "KEY=VALUE")
  expect_error(DET$nfd_args(c("K=1", "K=2")), "K= is given twice")
  expect_error(DET$nfd_args("OUT="), "OUT= needs a value")
  expect_error(ANA$nfa_args("RUNS=/x"), "unknown argument RUNS=")
  expect_identical(ANA$nfa_args(c("RUN=/r", "N_BOOT=10")), list(RUN = "/r", N_BOOT = "10"))
  # no key extends another, so no prefix can be read as a longer key
  for (keys in list(DET$NFD_KEYS, ANA$NFA_KEYS))
    for (k in keys) expect_false(any(startsWith(setdiff(keys, k), k)), info = k)
})

test_that("options: defaults under the job directory, validated numbers and areas", {
  # the job directory is this file's CLAUDE_JOB_DIR, set before the scripts were sourced
  job <- normalizePath(NF_JOB, mustWork = TRUE)
  expect_identical(Sys.getenv("CLAUDE_JOB_DIR"), NF_JOB)
  expect_identical(c(DET$d, ANA$d), c(job, job))
  o <- DET$nfd_options(list())
  expect_identical(o$frozen, file.path(job, "newfor", "frozen_v1"))
  expect_identical(o$out, file.path(job, "newfor", "multichm_runs"))
  expect_true(file.exists(o$protocol))
  expect_identical(basename(o$protocol), "newfor-validation-protocol.md")
  expect_null(o$areas)
  expect_identical(c(o$cores, o$K), c(1L, as.integer(NEWFOR_NULL_K)))
  expect_false(o$allow_unpinned)
  o <- DET$nfd_options(list(AREAS = "01, 02,01", CORES = "4", K = "0", ALLOW_UNPINNED = "1"))
  expect_identical(o$areas, c("01", "02"))
  expect_identical(c(o$cores, o$K), c(4L, 0L))
  expect_true(o$allow_unpinned)
  expect_null(DET$nfd_options(list(AREAS = "ALL"))$areas)
  expect_error(DET$nfd_options(list(CORES = "0")), "CORES= must be a whole number of at least 1")
  expect_error(DET$nfd_options(list(K = "2.5")), "K= must be a whole number")
  # not finite, or beyond the integer range: refused rather than read as NA
  for (v in c("Inf", "-Inf", "NaN", "3e9")) {
    expect_error(DET$nfd_options(list(K = v)), "K= must be a whole number", info = v)
    expect_error(DET$nfd_options(list(CORES = v)), "CORES= must be a whole number", info = v)
  }
  expect_identical(DET$nfd_options(list(K = "2147483647"))$K, .Machine$integer.max)
  expect_error(DET$nfd_options(list(ALLOW_UNPINNED = "yes")), "0 or 1")
  expect_error(DET$nfd_options(list(AREAS = ",")), "comma-separated")
  a <- ANA$nfa_options(list())
  expect_identical(a$run, file.path(job, "newfor", "multichm_runs"))
  expect_identical(c(a$n_boot, a$seed), c(1000L, 20261002L))
  expect_error(ANA$nfa_options(list(N_BOOT = "0")), "N_BOOT= must be")
})

## ---- the detector pin --------------------------------------------------------------------------
test_that("the pinned library's git blob is the protocol's; another library stops the run", {
  lib <- .find("multichm_gated_lib.R")
  expect_identical(DET$nfd_git_blob(lib), DET$NFD_PIN_BLOB)
  git <- tryCatch(suppressWarnings(system2("git", c("hash-object", shQuote(lib)), stdout = TRUE,
                                           stderr = FALSE)), error = function(e) character())
  if (length(git) == 1L) expect_identical(DET$nfd_git_blob(lib), git)    # what git says
  p <- DET$nfd_check_pin(lib)
  expect_true(p$pin_matches); expect_false(p$allow_unpinned)
  expect_identical(p$sha256, frozen_sha256(lib))
  changed <- tempfile(fileext = ".R"); on.exit(unlink(changed))
  file.copy(lib, changed)
  cat("# one more line\n", file = changed, append = TRUE)
  expect_error(DET$nfd_check_pin(changed), "the detector pin changed")
  q <- DET$nfd_check_pin(changed, allow_unpinned = TRUE)              # tests only, recorded
  expect_false(q$pin_matches); expect_true(q$allow_unpinned)
  expect_false(identical(q$git_blob, DET$NFD_PIN_BLOB))
})

test_that("the package versions are the protocol's; another version stops the run", {
  expect_identical(DET$NFD_PIN_VERSIONS, c(lidR = "4.3.2", lidRplugins = "0.4.0"))
  fake <- function(v) function(pkg) v[[pkg]]
  ok <- DET$nfd_check_versions(installed = fake(c(lidR = "4.3.2", lidRplugins = "0.4.0")))
  expect_identical(ok, list(pinned = list(lidR = "4.3.2", lidRplugins = "0.4.0"),
                            installed = list(lidR = "4.3.2", lidRplugins = "0.4.0"),
                            versions_match = TRUE))
  # the error names each package that differs, with its version and the pin
  expect_error(DET$nfd_check_versions(installed = fake(c(lidR = "4.3.3", lidRplugins = "0.4.0"))),
               "lidR is 4.3.3, the protocol pins 4.3.2; install")
  expect_error(DET$nfd_check_versions(installed = fake(c(lidR = "4.3.1", lidRplugins = "0.5.0"))),
               paste("lidR is 4.3.1, the protocol pins 4.3.2; lidRplugins is 0.5.0, the",
                     "protocol pins 0.4.0"))
  # ALLOW_UNPINNED=1 lets it run, recorded
  un <- DET$nfd_check_versions(TRUE, installed = fake(c(lidR = "4.3.3", lidRplugins = "0.4.0")))
  expect_false(un$versions_match)
  expect_identical(un$installed$lidR, "4.3.3")
})

test_that("the run record refuses a changed library or other package versions", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  configs <- newfor_configs()
  o <- DET$nfd_options(list(FROZEN = e$root, OUT = file.path(e$base, "unused"),
                            PROTOCOL = e$protocol))
  fz <- DET$nfd_frozen_areas(e$root)
  changed <- tempfile(fileext = ".R"); on.exit(unlink(changed))
  file.copy(.find("multichm_gated_lib.R"), changed)
  cat("# one more line\n", file = changed, append = TRUE)
  expect_false(o$allow_unpinned)
  expect_error(DET$nfd_run_record(o, fz, fz$ids, configs, lib = changed),
               "the detector pin changed")
  expect_error(DET$nfd_run_record(o, fz, fz$ids, configs,
                                  pin_versions = c(lidR = "9.9.9", lidRplugins = "0.4.0")),
               paste("the package versions differ from the protocol's: lidR is .*, the",
                     "protocol pins 9.9.9"))
  # with ALLOW_UNPINNED=1 both are recorded instead
  o$allow_unpinned <- TRUE
  rec <- DET$nfd_run_record(o, fz, fz$ids, configs, lib = changed,
                            pin_versions = c(lidR = "9.9.9", lidRplugins = "0.4.0"))
  expect_false(rec$detector_library$pin_matches); expect_true(rec$detector_library$allow_unpinned)
  expect_false(rec$versions_match)
  expect_identical(rec$pinned_versions, list(lidR = "9.9.9", lidRplugins = "0.4.0"))
  # pins that are the installed versions pass without ALLOW_UNPINNED=1, on any machine
  here <- vapply(names(DET$NFD_PIN_VERSIONS), DET$.nfd_installed, "")
  o$allow_unpinned <- FALSE
  rec <- DET$nfd_run_record(o, fz, fz$ids, configs, pin_versions = here)
  expect_true(rec$versions_match); expect_false(rec$detector_library$allow_unpinned)
  expect_true(rec$detector_library$pin_matches)
  expect_identical(rec$pinned_versions, as.list(here))
  expect_false(dir.exists(file.path(e$base, "unused")))
  # run_main checks the pins before it writes anything: pins that are not the
  # installed versions stop it without ALLOW_UNPINNED=1
  pins <- DET$NFD_PIN_VERSIONS
  on.exit(DET$NFD_PIN_VERSIONS <- pins, add = TRUE)
  DET$NFD_PIN_VERSIONS <- c(lidR = "0.0.1", lidRplugins = "0.0.1")
  expect_error(quiet(DET$run_main(list(FROZEN = e$root, OUT = file.path(e$base, "unused"),
                                       PROTOCOL = e$protocol))),
               paste("the package versions differ from the protocol's: lidR is .*, the",
                     "protocol pins 0.0.1"))
  expect_false(dir.exists(file.path(e$base, "unused")))
})

test_that(paste("git_clean: TRUE for a clean tree, FALSE with a new file there, NA outside",
                "a repository"), {
  skip_if(!nzchar(Sys.which("git")), "git is not installed")
  dir <- tempfile("newfor-git-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))
  withr::local_envvar(GIT_CEILING_DIRECTORIES = normalizePath(dirname(dir)))
  expect_identical(DET$.nfd_git_clean(dir), NA)                      # not a repository
  expect_identical(DET$.nfd_git_head(dir), NA_character_)
  system2("git", c("-C", shQuote(dir), "init", "-q"), stdout = FALSE, stderr = FALSE)
  expect_identical(DET$.nfd_git_clean(dir), TRUE)
  writeLines("x", file.path(dir, "notes.txt"))                         # outside the three folders
  expect_identical(DET$.nfd_git_clean(dir), TRUE)
  for (sub in c("scripts", "docs", "tests")) {
    d <- file.path(dir, sub); dir.create(d)
    writeLines("x", file.path(d, "a.R"))
    expect_identical(DET$.nfd_git_clean(dir), FALSE, info = sub)
    unlink(d, recursive = TRUE)
  }
  expect_identical(DET$.nfd_git_head(dir), NA_character_)            # no commit yet
  # an untracked file still counts where the repository hides untracked files
  # from a plain `git status`
  system2("git", c("-C", shQuote(dir), "config", "status.showUntrackedFiles", "no"),
          stdout = FALSE, stderr = FALSE)
  dir.create(file.path(dir, "scripts")); writeLines("x", file.path(dir, "scripts", "a.R"))
  plain <- system2("git", c("-C", shQuote(dir), "status", "--porcelain"), stdout = TRUE,
                   stderr = FALSE)
  expect_length(plain, 0L)                                            # hidden from git status
  expect_identical(DET$.nfd_git_clean(dir), FALSE)
  unlink(file.path(dir, "scripts"), recursive = TRUE)
  expect_identical(DET$.nfd_git_clean(dir), TRUE)
})

## ---- detection files and the registration move -------------------------------------------------
test_that("detection files read back as the same doubles; an empty set has a header only", {
  set.seed(5)
  det <- data.frame(x = 600000 + runif(500, 0, 80), y = 5100000 + runif(500, 0, 80),
                    z = runif(500, 2, 40))
  det$x[1] <- 600012.375; det$z[2] <- 0.1                            # short decimals stay short
  f <- tempfile(fileext = ".csv"); on.exit(unlink(f))
  DET$nfd_write_detections(det, f)
  expect_identical(DET$nfd_read_detections(f), det)
  expect_identical(readLines(f, n = 2), c("x,y,z", paste0("600012.375,",
                                                          DET$.nfd_num_text(det$y[1]), ",",
                                                          DET$.nfd_num_text(det$z[1]))))
  expect_identical(strsplit(readLines(f)[3], ",")[[1]][3], "0.1")
  DET$nfd_write_detections(det[0, ], f)
  expect_identical(readLines(f), "x,y,z")
  expect_identical(nrow(DET$nfd_read_detections(f)), 0L)
  expect_false(file.exists(paste0(f, ".part")))
  expect_error(DET$nfd_write_detections(data.frame(x = 1, y = 2), f), "exactly columns x, y, z")
})

test_that("the registered scenario moves detections by minus the estimate, or not at all", {
  reg <- c(dx = 1.5, dy = -2, offset = 2.5)
  expect_identical(DET$nfd_registration_shift(TRUE, reg), c(-1.5, 2))
  expect_identical(DET$nfd_registration_shift(FALSE, reg), c(0, 0))
  expect_identical(DET$nfd_registration_shift(TRUE, c(dx = NA, dy = NA, offset = NA)), c(0, 0))
  expect_identical(DET$NFD_SCENARIOS$scenario, c("primary", "inventoried", "registered", "tol2"))
  expect_identical(DET$NFD_SCENARIOS$tol, c(4, 4, 4, 2))
})

## ---- end to end: detection ---------------------------------------------------------------------
test_that("a two-area root runs end to end: run.json, its pins and the detections", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  rec <- jsonlite::read_json(file.path(e$out, "run.json"), simplifyVector = TRUE)
  expect_identical(rec$protocol$sha256, frozen_sha256(e$protocol))
  expect_identical(rec$frozen$root_id, newfor_root_id(e$root))
  expect_identical(rec$detector_library$git_blob, DET$NFD_PIN_BLOB)
  expect_true(rec$detector_library$pin_matches)
  # ALLOW_UNPINNED=1 only where the installed versions are not the pins, and recorded
  expect_identical(rec$detector_library$allow_unpinned, !NF_PINNED)
  expect_identical(rec$configurations$name, names(newfor_configs()))
  expect_identical(rec$configurations$label, c("stock", "z5_s0.75_c0.6_e1_d8", "z5_s0_c0_e0",
                                               "z5_s0_c0.6_e1", "z5_s0.75_c0.6_e1"))
  expect_equal(c(rec$a, rec$tol, rec$K, rec$null_min_shift), c(0.10, 4, NF_K, 8))
  expect_identical(rec$areas, c("91", "92"))
  expect_identical(rec$root_areas, c("91", "92"))
  expect_length(rec$not_frozen, 0L)
  expect_identical(rec$lidr_threads, 1L)
  expect_identical(rec$pinned_versions, as.list(DET$NFD_PIN_VERSIONS))
  expect_identical(rec$versions_match, NF_PINNED)
  expect_true(is.null(rec$git_clean) || is.logical(rec$git_clean))   # null without git
  expect_true(is.null(rec$git_head) || grepl("^[0-9a-f]{40}$", rec$git_head))
  # the root was frozen under the run's protocol
  expect_identical(newfor_frozen_record(e$root)$protocol_sha256, rec$protocol$sha256)
  expect_identical(names(rec$features), c("radius", "half_dz", "cover_height", "top_prob",
                                          "crown_res", "crown_ws"))
  expect_identical(rec$scenarios$scenario, DET$NFD_SCENARIOS$scenario)
  expect_identical(names(rec$versions), c("R", "lidR", "lidRplugins", "terra", "sf", "data.table"))
  # sources: every other R file the run sources, in NFD_SOURCES order, hashed
  expect_identical(unlist(rec$sources),
                   vapply(DET$NFD_SOURCES, function(f) frozen_sha256(.find(f)), ""))
  # one file per area and configuration, holding exactly the detections scored
  for (id in c("91", "92"))
    expect_setequal(list.files(file.path(e$out, "detections", id)),
                    paste0(rec$configurations$label, ".csv"))
  items <- nf_items(e)
  cells <- e$res$cells
  for (id in names(items)) for (nm in names(newfor_configs()))
    expect_identical(unique(cells$n_apex[cells$plot == id & cells$config_name == nm]),
                     nrow(items[[id]]$det[[nm]]))
  expect_gt(nrow(items[["91"]]$det$stock), 20L)
})

test_that("features.csv: one row per area with admission, densities, features and parity", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  f <- read.csv(file.path(e$out, "features.csv"), stringsAsFactors = FALSE,
                colClasses = c(area = "character", failed = "character"))
  expect_identical(names(f), c("area", "forest", "admitted", "failed", "n_rows", "n_inside",
                               "n_outside", "n_primary", "n_inventoried", "n_missing_dbh",
                               "n_below_caliper", "gap_months", "reach_min", "terrain_na_share",
                               "aoi_area", "pdens_aoi", "frdens_aoi", "covered_area", "pdens_clip",
                               "frdens_clip", "res", "cover", "top_height", "crown_spacing",
                               "n_crowns", "crown_area", "n_candidates", "n_surface", "n_deeper",
                               "closed", "spaced", "gate_state", "parity_ok", "parity_n_package",
                               "parity_n_stock", "parity_max_abs_diff", "parity_error", "dx", "dy",
                               "offset"))
  expect_identical(f$area, c("91", "92"))
  expect_identical(f$admitted, c(TRUE, FALSE))
  expect_identical(f$failed, c("", "rule_gap"))
  expect_identical(f$n_primary, c(10L, 10L))                # nine crowns and the 6 m tree
  expect_identical(f$n_inventoried, c(11L, 11L))            # and the 8 cm stem
  # the admission table's stem counts, as the root records them
  adm <- newfor_frozen_admission(e$root)
  for (k in c("n_rows", "n_inside", "n_outside", "n_missing_dbh", "n_below_caliper"))
    expect_identical(f[[k]], adm[[k]], info = k)
  # 49 crowns on the 8 m grid, the 6 m tree and the 8 cm stem; 11 of them inside
  expect_identical(f$n_rows, c(51L, 51L)); expect_identical(f$n_inside, c(11L, 11L))
  expect_identical(f$n_outside, c(40L, 40L))
  # the sparse cloud gets the 0.5 m raster, the dense one 0.25 m
  expect_true(f$frdens_clip[1] < 8 && f$frdens_clip[2] >= 8)
  expect_identical(f$res, c(0.5, 0.25))
  for (id in f$area) {
    cell <- newfor_frozen_area(e$root, id)$cell
    expect_equal(f$frdens_clip[f$area == id], cell$density$frdens_clip, tolerance = 1e-12)
    expect_identical(as.numeric(f$covered_area[f$area == id]), as.numeric(cell$covered_area))
    expect_equal(f$aoi_area[f$area == id], cell$density$aoi_area, tolerance = 1e-12)
    expect_equal(f$frdens_clip[f$area == id], cell$density$n_first_clip / cell$covered_area,
                 tolerance = 1e-12)
    expect_equal(c(f$dx[f$area == id], f$dy[f$area == id]),
                 c(cell$registration$dx, cell$registration$dy))
  }
  # stock detections equal lidRplugins::multichm on every clip
  expect_identical(f$parity_ok, c(TRUE, TRUE))
  expect_identical(f$parity_n_package, f$parity_n_stock)
  expect_equal(f$parity_max_abs_diff, c(0, 0))
  expect_true(all(is.na(f$parity_error)))
  expect_true(all(f$gate_state %in% c("gated", "closed", "open")))
  expect_identical(f$n_surface + f$n_deeper, f$n_candidates)
})

test_that("cells.csv: one row per area x configuration x scenario, sharing nulls and stems", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  cells <- read.csv(file.path(e$out, "cells.csv"), stringsAsFactors = FALSE,
                    colClasses = c(plot = "character"))
  b <- NEWFOR_HEIGHT_BANDS
  expect_identical(names(cells), c("site", "plot", "forest", "admitted", "config", "config_name",
                                   "scenario", "tol", "n_apex", "shift_x", "shift_y",
                                   MCG_COUNT_COLS, paste0("n_h_", b), paste0("tp_h_", b),
                                   paste0("tp_h_", b, "0")))
  expect_identical(nrow(cells), 2L * 5L * 4L)
  expect_identical(unique(cells$site), "NEWFOR")
  expect_identical(unique(cells$scenario), c("primary", "inventoried", "registered", "tol2"))
  expect_identical(nrow(unique(cells[c("plot", "config", "scenario")])), nrow(cells))
  expect_equal(cells$tol, ifelse(cells$scenario == "tol2", 2, 4))
  # the reference of a scenario does not depend on the configuration
  for (s in unique(cells$scenario)) for (id in c("91", "92"))
    expect_length(unique(cells$n_ref[cells$scenario == s & cells$plot == id]), 1L)
  pr <- cells[cells$scenario == "primary", ]; inv <- cells[cells$scenario == "inventoried", ]
  expect_equal(unique(pr$n_ref), 10)
  expect_equal(unique(inv$n_ref), 11)
  expect_true(all(pr$TP > 0))
  # with K null shifts every null count is a multiple of 1 / K
  expect_true(all(abs(cells$TP0 * NF_K - round(cells$TP0 * NF_K)) < 1e-9))
  expect_true(all(cells$n_over == 0 & cells$tp_under0 == 0))
  expect_identical(cells$admitted, cells$plot == "91")
  # every primary, inventoried and tol2 cell is newfor_score_cell with the null
  # offsets of its own window: the box widened by 4 m, or by 2 m for tol2
  items <- nf_items(e)
  cell_of <- function(id, nm, s) {
    x <- cells[cells$plot == id & cells$config_name == nm & cells$scenario == s, , drop = FALSE]
    expect_identical(nrow(x), 1L)
    x
  }
  for (id in names(items)) {
    it <- items[[id]]
    w4 <- newfor_window(it$aoi, 4); w2 <- newfor_window(it$aoi, 2)
    o4 <- newfor_null_offsets(id, w4$w, w4$h, k = NF_K)
    o2 <- newfor_null_offsets(id, w2$w, w2$h, k = NF_K)
    expect_false(identical(o4, o2))
    for (nm in names(newfor_configs())) {
      det <- it$det[[nm]]
      want <- list(
        primary = newfor_score_cell(newfor_stems(it$stems, "primary"), det, it$aoi, id, tol = 4,
                                    offsets = o4),
        inventoried = newfor_score_cell(newfor_stems(it$stems, "inventoried"), det, it$aoi, id,
                                        tol = 4, offsets = o4),
        tol2 = newfor_score_cell(newfor_stems(it$stems, "primary"), det, it$aoi, id, tol = 2,
                                 offsets = o2))
      for (s in names(want)) {
        got <- cell_of(id, nm, s)[names(want[[s]])]
        expect_identical(vapply(got, as.numeric, 0), unlist(want[[s]]),
                         info = paste(id, nm, s))
      }
      # the detections and their shifts do not depend on the stems: the null's
      # detection count is shared by the primary and inventoried scenarios
      expect_identical(cell_of(id, nm, "inventoried")$n_det0, cell_of(id, nm, "primary")$n_det0)
    }
  }
})

test_that("registered equals primary where the estimate is (0, 0)", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  f <- read.csv(file.path(e$out, "features.csv"), colClasses = c(area = "character"))
  cells <- read.csv(file.path(e$out, "cells.csv"), stringsAsFactors = FALSE,
                    colClasses = c(plot = "character"))
  zero <- f$area[f$dx == 0 & f$dy == 0]
  expect_identical(zero, c("91", "92"))                     # stems on the crowns' apexes
  cnt <- c(MCG_COUNT_COLS, grep("^(n|tp)_h_", names(cells), value = TRUE))
  key <- function(x) {
    x <- x[order(x$plot, x$config), ]
    rownames(x) <- NULL
    x
  }
  p <- key(cells[cells$scenario == "primary" & cells$plot %in% zero, ])
  r <- key(cells[cells$scenario == "registered" & cells$plot %in% zero, ])
  expect_identical(r[cnt], p[cnt])
  expect_true(all(r$shift_x == 0 & r$shift_y == 0))
})

test_that("re-scoring the written detections reproduces cells.csv, in one or two workers", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  items <- nf_items(e)
  cells <- read.csv(file.path(e$out, "cells.csv"), stringsAsFactors = FALSE,
                    colClasses = c(plot = "character"))
  one <- DET$nfd_score_all(items, newfor_configs(), NF_K, cores = 1L)
  two <- DET$nfd_score_all(items, newfor_configs(), NF_K, cores = 2L)
  expect_identical(two, one)
  expect_equal(one, cells, tolerance = 1e-12)
  # a nonzero estimate moves the detections against it in the registered scenario only
  it <- items[["91"]]; it$reg <- c(dx = 2, dy = -1, offset = sqrt(5))
  s <- DET$nfd_score_area(it, newfor_configs()["declared"], NF_K)
  reg <- s[s$scenario == "registered", ]
  expect_identical(c(reg$shift_x, reg$shift_y), c(-2, 1))
  moved <- it$det$declared; moved$x <- moved$x - 2; moved$y <- moved$y + 1
  win <- newfor_window(it$aoi, 4)
  want <- newfor_score_cell(newfor_stems(it$stems), moved, it$aoi, "91",
                            offsets = newfor_null_offsets("91", win$w, win$h, k = NF_K))
  expect_identical(unlist(reg[names(want)]), unlist(want))
  expect_identical(unlist(s[s$scenario == "primary", names(want)]),
                   unlist(one[one$plot == "91" & one$scenario == "primary" &
                                one$config_name == "declared", names(want)]))
})

test_that("a foreign run root, an unsealed root and unknown areas are refused", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  configs <- newfor_configs()
  o <- DET$nfd_options(nf_args(FROZEN = e$root, OUT = e$out, PROTOCOL = e$protocol))
  fz <- DET$nfd_frozen_areas(e$root)
  rec <- DET$nfd_run_record(o, fz, fz$ids, configs)
  expect_silent(DET$nfd_check_out(e$out, rec))              # the same pins: accepted
  bad <- rec; bad$protocol$sha256 <- strrep("0", 64)
  expect_error(DET$nfd_check_out(e$out, bad), "another protocol; move it aside")
  bad <- rec; bad$frozen$root_id <- strrep("1", 64)
  expect_error(DET$nfd_check_out(e$out, bad), "another freeze root")
  bad <- rec; bad$detector_library$git_blob <- strrep("2", 40)
  expect_error(DET$nfd_check_out(e$out, bad), "another detector library")
  bad <- rec; bad$configurations <- bad$configurations[1:2, ]
  expect_error(DET$nfd_check_out(e$out, bad), "another configuration set")
  # the run itself: another protocol file is refused before any detection, and
  # the earlier run's files are left as they were
  other <- file.path(e$base, "protocol-edited.md")
  file.copy(e$protocol, other)
  cat("\nEdited after the run.\n", file = other, append = TRUE)
  before <- nf_hashes(e$out)
  expect_true(all(c("run.json", "features.csv", "cells.csv") %in% names(before)))
  expect_true(any(startsWith(names(before), "detections/")))
  expect_error(quiet(DET$run_main(nf_args(FROZEN = e$root, OUT = e$out, PROTOCOL = other,
                                          K = "1"))),
               "holds a run with another protocol; move it aside")
  expect_identical(nf_hashes(e$out), before)
  # into a fresh OUT, a root frozen under another protocol is refused (no override)
  fresh <- file.path(e$base, "fresh")
  expect_error(quiet(DET$run_main(list(FROZEN = e$root, OUT = fresh, PROTOCOL = other, K = "1",
                                       ALLOW_UNPINNED = "1"))),
               "the root was frozen under another protocol")
  expect_false(dir.exists(fresh))
  # a root sealed without freeze.json is refused
  bare <- file.path(e$base, "bare"); dir.create(bare)
  file.copy(list.files(e$root, full.names = TRUE), bare, recursive = TRUE)
  unlink(file.path(bare, c("freeze.json", "freeze_manifest.csv")))
  newfor_seal(bare)
  expect_error(quiet(DET$run_main(nf_args(FROZEN = bare, OUT = fresh, PROTOCOL = e$protocol,
                                          K = "1"))),
               "the root holds no freeze.json")
  expect_false(dir.exists(fresh))
  # a freeze.json added or changed after the seal is refused
  writeLines("{}", file.path(bare, "freeze.json"))
  expect_error(DET$nfd_check_freeze_protocol(bare, rec$protocol$sha256),
               "freeze.json is not in the root's manifest")
  edited <- file.path(e$base, "edited"); dir.create(edited)
  file.copy(list.files(e$root, full.names = TRUE), edited, recursive = TRUE)
  j <- readLines(file.path(edited, "freeze.json"))
  writeLines(sub(rec$protocol$sha256, frozen_sha256(other), j, fixed = TRUE),
             file.path(edited, "freeze.json"))
  expect_error(DET$nfd_check_freeze_protocol(edited, frozen_sha256(other)),
               "freeze.json differs from the root's manifest")
  expect_silent(DET$nfd_check_freeze_protocol(e$root, rec$protocol$sha256))
  # files without a run.json
  stray <- file.path(e$base, "stray"); dir.create(stray)
  writeLines("x", file.path(stray, "cells.csv"))
  expect_error(DET$nfd_check_out(stray, rec), "holds files but no run.json")
  # an unsealed root, and areas that are not frozen
  open <- file.path(e$base, "open"); dir.create(open)
  expect_error(DET$nfd_frozen_areas(open), "not sealed")
  expect_error(quiet(DET$run_main(list(FROZEN = e$root, OUT = file.path(e$base, "new"),
                                       PROTOCOL = e$protocol, AREAS = "91,93"))),
               "AREAS= names areas that are not frozen.*: 93")
  expect_false(dir.exists(file.path(e$base, "new")))
})

test_that("AREAS= runs a subset of the root", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  out <- file.path(e$base, "only91")
  res <- quiet(DET$run_main(nf_args(FROZEN = e$root, OUT = out, PROTOCOL = e$protocol,
                                    AREAS = "91", K = "1")))
  expect_identical(res$features$area, "91")
  expect_identical(unique(res$cells$plot), "91")
  rj <- jsonlite::read_json(file.path(out, "run.json"), simplifyVector = TRUE)
  expect_identical(rj$areas, "91")
  expect_identical(rj$root_areas, c("91", "92"))                     # every frozen area
  expect_identical(list.files(file.path(out, "detections")), "91")
  # the same detections as in the full run
  for (l in vapply(newfor_configs(), mcg_config_label, ""))
    expect_identical(DET$nfd_read_detections(file.path(out, "detections", "91", paste0(l, ".csv"))),
                     DET$nfd_read_detections(file.path(e$out, "detections", "91",
                                                       paste0(l, ".csv"))))
  # a rerun with the same pins starts afresh: nothing of an earlier run is left,
  # its analysis and after-run checks included
  dir.create(file.path(out, "analysis")); writeLines("old", file.path(out, "analysis", "x.csv"))
  dir.create(file.path(out, "after_run"))
  writeLines("old", file.path(out, "after_run", "after_run.json"))
  dir.create(file.path(out, "detections", "92"))
  writeLines("old", file.path(out, "detections", "92", "stock.csv"))
  rerun <- quiet(DET$run_main(nf_args(FROZEN = e$root, OUT = out, PROTOCOL = e$protocol,
                                      AREAS = "91", K = "1")))
  expect_false(dir.exists(file.path(out, "analysis")))
  expect_false(dir.exists(file.path(out, "after_run")))
  expect_setequal(list.files(out), c("run.json", "features.csv", "cells.csv", "detections"))
  expect_identical(list.files(file.path(out, "detections")), "91")
  expect_identical(rerun$cells, res$cells)
})

## ---- the guards that keep the population whole -------------------------------------------------
# A copy of the e2e freeze root, changed by change(dir) and sealed again.
nf_resealed <- function(e, name, change) {
  dst <- file.path(e$base, name)
  dir.create(dst)
  file.copy(list.files(e$root, full.names = TRUE), dst, recursive = TRUE)
  unlink(file.path(dst, "freeze_manifest.csv"))
  change(dst)
  newfor_seal(dst)
  dst
}

test_that("a root whose admission table and area folders disagree is refused", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  adm <- newfor_frozen_admission(e$root)
  write_adm <- function(a) function(dir)
    utils::write.csv(a, file.path(dir, "admission.csv"), row.names = FALSE)
  same <- DET$nfd_frozen_areas(nf_resealed(e, "fz-same", write_adm(adm)))
  expect_identical(same$ids, c("91", "92")); expect_length(same$not_frozen, 0L)
  expect_error(DET$nfd_frozen_areas(nf_resealed(e, "fz-twice", write_adm(adm[c(1, 2, 2), ]))),
               "admission.csv lists an area twice")
  expect_error(DET$nfd_frozen_areas(nf_resealed(e, "fz-missing",
                                                write_adm(adm[adm$area == "91", ]))),
               "frozen areas missing from admission.csv: 92")
  # an area of the table without a folder cannot be run: it is listed as not frozen
  one <- DET$nfd_frozen_areas(nf_resealed(e, "fz-one", function(dir)
    unlink(file.path(dir, "92"), recursive = TRUE)))
  expect_identical(one$ids, "91"); expect_identical(one$not_frozen, "92")
  expect_error(DET$nfd_frozen_areas(nf_resealed(e, "fz-none", function(dir)
    unlink(file.path(dir, c("91", "92")), recursive = TRUE))),
    "the freeze root holds no area")
})

test_that("an admission row that disagrees with cell.json stops the area before detection", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  cfg <- newfor_configs()
  row <- newfor_frozen_admission(e$root)
  row <- row[row$area == "91", , drop = FALSE]
  expect_true(row$admitted); expect_identical(row$failed, "")
  flip <- row; flip$admitted <- FALSE
  expect_error(DET$nfd_detect_area(e$root, "91", flip, cfg),
               "area 91: admission.csv and cell.json disagree")
  other <- row; other$failed <- "rule_gap"
  expect_error(DET$nfd_detect_area(e$root, "91", other, cfg),
               "area 91: admission.csv and cell.json disagree")
  expect_error(DET$nfd_detect_area(e$root, "91", row[0, ], cfg), "area 91 needs one admission row")
  expect_error(DET$nfd_detect_area(e$root, "91", rbind(row, row), cfg),
               "area 91 needs one admission row")
})

# A hand-made area to score: three primary stems in the 20 m square at (x0, y0)
# of the frame, unless aoi is another polygon, and one detection 0.5 m from
# each stem under every configuration.
nf_hand_item <- function(id, aoi = NULL) {
  x0 <- NF_X0; y0 <- NF_Y0
  sq <- sf::st_sfc(sf::st_polygon(list(rbind(c(x0, y0), c(x0 + 20, y0), c(x0 + 20, y0 + 20),
                                             c(x0, y0 + 20), c(x0, y0)))), crs = NF_EPSG)
  stems <- data.frame(E = x0 + c(5, 10, 15), N = y0 + c(5, 12, 8), height = c(20, 15, 18),
                      primary = TRUE, inventoried = TRUE)
  det <- data.frame(x = stems$E + 0.5, y = stems$N, z = stems$height)
  list(id = id, forest = "F", admitted = TRUE, aoi = if (is.null(aoi)) sq else aoi,
       stems = stems, det = lapply(newfor_configs(), function(cfg) det),
       reg = c(dx = 0, dy = 0, offset = 0))
}

test_that("an area whose scoring fails stops the run, named, in one worker or two", {
  ok <- nf_hand_item("A")
  cfg <- newfor_configs()
  good <- DET$nfd_score_all(list(A = ok), cfg, 2L)
  expect_identical(nrow(good), 4L * length(cfg))
  expect_true(all(good$TP == 3))
  # area B's polygon lies 1 km east of its stems, so its scoring stops
  far <- nf_hand_item("B")$aoi
  far <- sf::st_sfc(sf::st_geometry(far)[[1]] + c(1000, 0), crs = NF_EPSG)
  items <- list(A = ok, B = nf_hand_item("B", aoi = far))
  for (cores in 1:2) {
    msg <- tryCatch(suppressWarnings(DET$nfd_score_all(items, cfg, 2L, cores = cores)),
                    error = conditionMessage)
    expect_match(msg, "^newfor: scoring failed for area B: .*outside declared scoring footprint",
                 info = cores)
    expect_false(grepl("area A", msg), info = cores)
  }
})

## ---- end to end: analysis ----------------------------------------------------------------------
test_that("the analysis of the two-area run writes every output with its schema", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  res <- quiet(ANA$run_main(list(RUN = e$out, N_BOOT = "20")))
  out <- file.path(e$out, "analysis")
  expect_setequal(list.files(out), c("pools.csv", "pooled.csv", "contrasts.csv", "reading.csv",
                                     "per_plot.csv", "leave_one_forest_out.csv", "tables.md",
                                     "analysis.json"))
  pools <- read.csv(file.path(out, "pools.csv"), stringsAsFactors = FALSE)
  expect_identical(pools$pool, c("admitted", "all", "density_inside", "density_outside",
                                 "gate_gated", "gate_closed", "gate_open", "without_alpha_wood"))
  expect_identical(pools$n_plots[1:2], c(1L, 2L))
  b <- NEWFOR_HEIGHT_BANDS
  pooled <- read.csv(file.path(out, "pooled.csv"), stringsAsFactors = FALSE)
  expect_identical(names(pooled),
                   c("scenario", "pool", "config_name", "config", "n_plots", MCG_COUNT_COLS,
                     paste0("n_h_", b), paste0("tp_h_", b), paste0("tp_h_", b, "0"),
                     MCG_RATE_COLS, as.vector(t(outer(b, c("rec_h_", "null_rec_h_", "cRec_h_"),
                                                      function(x, p) paste0(p, x))))))
  expect_identical(unique(pooled$config_name), names(newfor_configs()))
  # every scenario x non-empty pool x configuration
  nonempty <- sum(pools$n_plots > 0)
  expect_identical(nrow(pooled), 4L * nonempty * 5L)
  con <- read.csv(file.path(out, "contrasts.csv"), stringsAsFactors = FALSE)
  expect_identical(names(con), c("scenario", "pool", "pair", "name_a", "name_b", "config_a",
                                 "config_b", "metric", "n_plots", "estimate_a", "estimate_b",
                                 "difference", "lower", "upper", "defined_draws"))
  expect_identical(unique(con$pair), c("declared - stock", "floor - stock", "floor_exempt - stock",
                                       "gate_all - stock", "declared - floor_exempt"))
  expect_identical(unique(con$metric), c("F1", "cF1", "precision", "recall", "cPrecision",
                                         "cRecall", "det_per_ref"))
  combos <- unique(con[c("scenario", "pool")])
  expect_identical(paste(combos$scenario, combos$pool),
                   c(paste("primary", pools$pool[pools$n_plots > 0]), "inventoried admitted",
                     "registered admitted", "registered all", "tol2 admitted"))
  # fewer than five plots: estimates without an interval
  expect_true(all(is.na(con$lower) & is.na(con$upper) & con$defined_draws == 0))
  expect_true(all(is.finite(con$estimate_a[con$metric == "F1"])))
  rd <- read.csv(file.path(out, "reading.csv"), stringsAsFactors = FALSE)
  expect_identical(names(rd), c("scenario", "pool", "pair", "config_a", "config_b", "metric",
                                "n_plots", "estimate_a", "estimate_b", "difference", "lower",
                                "upper", "reading", "primary", "protocol_settings"))
  expect_identical(rd$metric, c("F1", "cF1")); expect_identical(rd$primary, c(TRUE, FALSE))
  expect_true(all(is.na(rd$reading)))                       # one admitted plot: no interval
  # K = 4 and 20 resamples are not the protocol's settings, and the run says so
  expect_identical(rd$protocol_settings, c(FALSE, FALSE))
  pp <- read.csv(file.path(out, "per_plot.csv"), stringsAsFactors = FALSE,
                 colClasses = c(area = "character"))
  expect_identical(names(pp), c(ANA$NFA_FEATURE_COLS, "in_dev_range", "n_ref",
                                paste0(rep(c("stock_", "declared_"), each = 6),
                                       c("n_det", "TP", "tp_core", "recall", "precision", "F1")),
                                "d_n_det", "d_TP", "d_fp", "d_F1"))
  expect_identical(pp$area, c("91", "92"))
  expect_identical(pp$in_dev_range, pp$frdens_clip >= 5.2 & pp$frdens_clip <= 17.8)
  lofo <- read.csv(file.path(out, "leave_one_forest_out.csv"), stringsAsFactors = FALSE)
  expect_identical(names(lofo), c("metric", "pool", "left_out", "n_plots", "difference", "lower",
                                  "upper"))
  md <- readLines(file.path(out, "tables.md"))
  # every table is preceded by a line naming the CSV it came from
  starts <- which(startsWith(md, "| ") & !startsWith(c("", md[-length(md)]), "| "))
  expect_gt(length(starts), 8L)
  expect_true(all(grepl("^From [a-z_]+\\.csv", md[starts - 2L])))
  expect_true(all(md[starts - 1L] == ""))
  aj <- jsonlite::read_json(file.path(out, "analysis.json"), simplifyVector = TRUE)
  expect_identical(names(aj), c("run_json_sha256", "root_id", "protocol_sha256", "code_sha256",
                                "n_boot", "seed", "min_interval_plots", "not_worse_margin",
                                "dev_frdens", "protocol_settings", "protocol_settings_reasons",
                                "pools"))
  expect_identical(aj$run_json_sha256, frozen_sha256(file.path(e$out, "run.json")))
  # code_sha256: every R file the analysis sources, in NFA_CODE order, hashed
  expect_identical(unlist(aj$code_sha256),
                   vapply(ANA$NFA_CODE, function(f) frozen_sha256(.find(f)), ""))
  expect_identical(c(aj$n_boot, aj$seed), c(20L, 20261002L))
  expect_false(aj$protocol_settings)
  # K = 4 and 20 resamples; where the installed versions are not the pins, also
  # the ALLOW_UNPINNED=1 the run needed and the versions. The run's sources and
  # the analysis's code are the same files, and a, tol and null_min_shift the
  # protocol's, so none of them is named.
  why <- c("K is 4, not 200",
           if (!NF_PINNED) c("ALLOW_UNPINNED=1 was given",
                             "lidR or lidRplugins is not the pinned version"),
           "N_BOOT is 20, not 1000")
  expect_identical(aj$protocol_settings_reasons, why)
  # the header states the settings and why the run does not meet them
  expect_true("Null shifts per plot K = 4; 20 resamples, seed 20261002." %in% md)
  expect_true("Areas run: 2 of the 2 frozen." %in% md)
  expect_true(paste0("Detector library blob ", substr(DET$NFD_PIN_BLOB, 1, 12), ": ",
                     if (NF_PINNED) "pinned." else "pinned, ALLOW_UNPINNED=1 given.") %in% md)
  expect_true(sprintf("Packages: lidR %s, lidRplugins %s (%s).",
                      as.character(packageVersion("lidR")),
                      as.character(packageVersion("lidRplugins")),
                      if (NF_PINNED) "the pinned versions" else "not the pinned versions") %in% md)
  i <- grep("^This run does not meet", md); j <- grep("^Counts are sums", md)
  expect_identical(paste(md[i:(j - 1L)], collapse = " "),
                   paste0("This run does not meet the protocol's settings: ",
                          paste(why, collapse = "; "), "."))
  expect_true(all(nchar(md[!startsWith(md, "|")]) <= 80))
  # the admission and density tables
  i <- grep("^## Density", md)
  expect_identical(md[i + 2L], paste("From per_plot.csv (per m2; clip-wide over the kept",
                                     "points' convex hull)."))
  expect_identical(md[i + 4L], paste("| area | aoi_area | frdens_aoi | pdens_aoi | covered_area |",
                                     "frdens_clip | pdens_clip | res | in_dev_range |"))
  expect_identical(grep("^## ", md)[1:2], c(grep("^## Admission", md), i))
  a <- grep("^## Admission", md)
  expect_identical(md[a + 4L], paste("| area | forest | n_rows | n_inside | n_outside | n_primary",
                                     "| n_inventoried | n_missing_dbh | n_below_caliper |",
                                     "gap_months | reach_min | terrain_na_share | offset |",
                                     "admitted | failed |"))
  expect_true(startsWith(md[a + 6L], "| 91 | Alpha Wood | 51 | 11 | 40 | 10 | 11 | 0 | 0 | 3 |"))
})

test_that("the analysis refuses a run without run.json and cells of unequal support", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  copy <- function(name) {
    dst <- file.path(e$base, name); dir.create(dst)
    file.copy(file.path(e$out, c("run.json", "features.csv", "cells.csv")), dst)
    dst
  }
  a <- copy("no-run-json"); unlink(file.path(a, "run.json"))
  expect_error(ANA$run_main(list(RUN = a)), "holds no run.json")
  cells <- read.csv(file.path(e$out, "cells.csv"), stringsAsFactors = FALSE,
                    colClasses = c(plot = "character"))
  b <- copy("unequal")
  drop <- which(cells$scenario == "inventoried" & cells$config_name == "floor" &
                  cells$plot == "92")
  write.csv(cells[-drop, ], file.path(b, "cells.csv"), row.names = FALSE)
  expect_error(ANA$run_main(list(RUN = b)),
               paste("unequal support: in scenario inventoried configuration z5_s0_c0_e0",
                     "covers 1 of the 2"))
  write.csv(rbind(cells, cells[drop, ]), file.path(b, "cells.csv"), row.names = FALSE)
  expect_error(ANA$run_main(list(RUN = b)), "covers an area twice in scenario inventoried")
  x <- cells; x$admitted[x$plot == "92" & x$scenario == "tol2"] <- TRUE
  write.csv(x, file.path(b, "cells.csv"), row.names = FALSE)
  expect_error(ANA$run_main(list(RUN = b)), "disagree on an area's admission")
  x <- cells[cells$config_name != "gate_all", ]
  write.csv(x, file.path(b, "cells.csv"), row.names = FALSE)
  expect_error(ANA$run_main(list(RUN = b)), "not those of run.json")
  expect_false(dir.exists(file.path(b, "analysis")))
})

## ---- pools, the reading rule, a hand-made run --------------------------------------------------
test_that("pool membership follows admission, density bounds, gate state and forest", {
  f <- data.frame(area = c("01", "02", "03", "04", "05", "06", "07", "08"),
                  forest = c("Saint-Agnan", "Cotolivier", "Cotolivier", "Leskova dolina",
                             "Leskova dolina", "Pellizzano", "Asiago", "Asiago"),
                  admitted = c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
                  frdens_clip = c(5.2, 7, 4, 17.8, 17.81, 49.4, NA, 8.4),
                  gate_state = c("gated", "gated", "closed", "open", "closed", "gated", NA, "open"),
                  stringsAsFactors = FALSE)
  p <- ANA$nfa_pools(f[c(5, 1, 8, 2, 3, 7, 4, 6), ])            # row order does not matter
  expect_identical(names(p), c("admitted", "all", "density_inside", "density_outside",
                               "gate_gated", "gate_closed", "gate_open", "without_asiago",
                               "without_cotolivier", "without_leskova_dolina",
                               "without_pellizzano", "without_saint_agnan"))
  expect_identical(p$admitted, c("01", "03", "04", "05", "06", "07", "08"))
  expect_identical(p$all, f$area)
  # bounds inclusive: 5.2 and 17.8 are inside, 17.81 outside; an unknown density is in neither
  expect_identical(p$density_inside, c("01", "04", "08"))
  expect_identical(p$density_outside, c("03", "05", "06"))
  expect_identical(p$gate_gated, c("01", "06"))               # 02 is gated but not admitted
  expect_identical(p$gate_closed, c("03", "05"))
  expect_identical(p$gate_open, c("04", "08"))
  expect_identical(p$without_cotolivier, c("01", "04", "05", "06", "07", "08"))
  expect_identical(p$without_asiago, c("01", "03", "04", "05", "06"))
  expect_identical(p$without_saint_agnan, c("03", "04", "05", "06", "07", "08"))
  expect_identical(ANA$nfa_slug(c("Saint-Agnan", "Leskova dolina")),
                   c("saint_agnan", "leskova_dolina"))
  t <- ANA$nfa_pool_table(p)
  expect_identical(t$n_plots[t$pool == "gate_gated"], 2L)
  expect_identical(t$areas[t$pool == "gate_gated"], "01;06")
})

test_that("the reading rule gives each of its four readings, and none without an interval", {
  lower <- c(0.001, -0.10, -0.019, -0.03, 0, -0.02, -0.01, NA, -0.05)
  upper <- c(0.20, -0.001, 0.05, 0.08, 0.04, 0.01, -0.0001, 0.1, NA)
  expect_identical(ANA$nfa_reading(lower, upper),
                   c("better", "worse", "not worse", "inconclusive", "not worse", "inconclusive",
                     "worse", NA, NA))
  # the table of the primary contrast, from hand-made contrast rows
  con <- data.frame(scenario = "primary", pool = c("admitted", "admitted", "admitted", "all"),
                    pair = c("declared - stock", "declared - stock", "floor - stock",
                             "declared - stock"),
                    config_a = "a", config_b = "b", metric = c("cF1", "F1", "F1", "F1"),
                    n_plots = 13L, estimate_a = 0.6, estimate_b = 0.5, difference = 0.1,
                    lower = c(-0.03, 0.02, -1, -1), upper = c(0.2, 0.18, -0.5, -0.5),
                    defined_draws = 1000L, stringsAsFactors = FALSE)
  r <- ANA$nfa_reading_table(con)
  expect_identical(r$metric, c("F1", "cF1"))
  expect_identical(r$reading, c("better", "inconclusive"))
  expect_identical(r$primary, c(TRUE, FALSE))
  expect_error(ANA$nfa_reading_table(con[3:4, ]), "primary contrast is missing")
})

# Six areas, five admitted (A1..A5), all of forest F except A5 (G); A6 is not
# admitted. Every area has 10 primary stems. Primary scenario, per area:
#   stock    n_det 10, TP 6, tp_core 5 (A1..A5), and n_det 10, TP 2, tp_core 2 (A6);
#   declared n_det  8, TP 6, tp_core 6 (A1..A4), n_det 8, TP 4, tp_core 4 (A5),
#            and n_det 8, TP 2, tp_core 2 (A6).
# Admitted pool: stock recall 30/50 = 0.6, precision 25/50 = 0.5,
#   F1 = 2 * 0.6 * 0.5 / 1.1 = 0.545454...;
# declared recall 28/50 = 0.56, precision 28/40 = 0.7,
#   F1 = 2 * 0.56 * 0.7 / 1.26 = 0.622222...; difference 0.076767...
# Pool all adds A6: stock recall 32/60, precision 27/60, F1 = 2*(32/60)*(27/60)/(59/60)
#   = 2 * 32 * 27 / (60 * 59) = 0.488135...; declared recall 30/60, precision 30/48,
#   F1 = 2 * 0.5 * 0.625 / 1.125 = 0.555555...
# Nulls: n_det0 = n_det, TP0 = 1, tp_core0 = 1 everywhere. Height bands of every area:
#   short 2 stems (none matched), mid 2 (one matched), tall 6 (TP - 1 matched); band
#   nulls 0, 0.5, 0.5.
# The other scenarios change the primary counts of every area (n_det stays):
#   inventoried  two more short stems (n_ref 12), one of them matched: TP and
#                tp_core + 1;
#   registered   A1..A5 TP and tp_core + 1; A6 TP 5, tp_core 5 under both;
#   tol2         one match fewer: TP and tp_core - 1.
# run.json meets the protocol's settings (K 200, a 0.1, tol 4, null_min_shift
# 8, pinned library and versions, every frozen area run, and the sources the
# run would record from the files the analysis hashes too) unless `record`
# overrides fields (modifyList: NULL removes one).
hand_run <- function(dir, record = list()) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  cfg <- newfor_configs()
  tab <- DET$nfd_config_table(cfg)
  areas <- paste0("A", 1:6)
  rec <- list(configurations = tab, frozen = list(root_id = strrep("a", 64)),
              protocol = list(sha256 = strrep("b", 64)),
              detector_library = list(git_blob = DET$NFD_PIN_BLOB, pin_matches = TRUE,
                                      allow_unpinned = FALSE),
              sources = as.list(newfor_code_sha256(DET$NFD_SOURCES, .find)),
              versions = list(lidR = "4.3.2", lidRplugins = "0.4.0"),
              pinned_versions = list(lidR = "4.3.2", lidRplugins = "0.4.0"),
              versions_match = TRUE, a = 0.1, tol = 4, K = 200L, null_min_shift = 8,
              areas = I(areas), root_areas = I(areas))
  jsonlite::write_json(utils::modifyList(rec, record), file.path(dir, "run.json"),
                       auto_unbox = TRUE, digits = NA)
  feats <- data.frame(area = areas, forest = c("F", "F", "F", "F", "G", "F"),
                      admitted = c(rep(TRUE, 5), FALSE), failed = c(rep("", 5), "rule_gap"),
                      n_rows = 13L, n_inside = 12L, n_outside = 1L, n_primary = 10L,
                      n_inventoried = 12L, n_missing_dbh = 0L, n_below_caliper = 1L,
                      gap_months = 3L, reach_min = 25, terrain_na_share = 0, aoi_area = 1000,
                      pdens_aoi = 20, frdens_aoi = 12, covered_area = 9000, pdens_clip = 20,
                      frdens_clip = c(10, 10, 10, 30, 30, 10), res = 0.25, cover = 0.7,
                      crown_spacing = 6, gate_state = "closed", parity_ok = TRUE,
                      parity_n_package = 10L, parity_n_stock = 10L, parity_max_abs_diff = 0,
                      dx = 0, dy = 0, offset = 0, stringsAsFactors = FALSE)
  write.csv(feats, file.path(dir, "features.csv"), row.names = FALSE)
  one <- function(area, nm, s) {
    k <- match(area, areas)
    n_det <- if (nm == "stock") 10 else 8
    TP <- if (k == 6) 2 else if (nm == "stock") 6 else if (k == 5) 4 else 6
    tp_core <- if (k == 6) 2 else if (nm == "stock") 5 else TP
    n_ref <- 10; n_short <- 2; tp_short <- 0
    if (s == "inventoried") {
      n_ref <- 12; n_short <- 4; tp_short <- 1; TP <- TP + 1; tp_core <- tp_core + 1
    } else if (s == "registered") {
      if (k == 6) { TP <- 5; tp_core <- 5 } else { TP <- TP + 1; tp_core <- tp_core + 1 }
    } else if (s == "tol2") {
      TP <- TP - 1; tp_core <- tp_core - 1
    }
    data.frame(site = "NEWFOR", plot = area, forest = feats$forest[k], admitted = feats$admitted[k],
               config = mcg_config_label(cfg[[nm]]), config_name = nm, scenario = s,
               tol = if (s == "tol2") 2 else 4, n_apex = 30, shift_x = 0, shift_y = 0,
               n_ref = n_ref, n_over = 0, n_under = 0, n_det = n_det, TP = TP, tp_core = tp_core,
               tp_over = 0, tp_under = 0, n_det0 = n_det, TP0 = 1, tp_core0 = 1, tp_over0 = 0,
               tp_under0 = 0, n_h_short = n_short, n_h_mid = 2, n_h_tall = 6,
               tp_h_short = tp_short, tp_h_mid = 1, tp_h_tall = TP - 1 - tp_short,
               tp_h_short0 = 0, tp_h_mid0 = 0.5, tp_h_tall0 = 0.5, stringsAsFactors = FALSE)
  }
  cells <- do.call(rbind, lapply(areas, function(a) do.call(rbind, lapply(ANA$NFA_SCENARIOS,
    function(s) do.call(rbind, lapply(names(cfg), function(nm) one(a, nm, s)))))))
  write.csv(cells, file.path(dir, "cells.csv"), row.names = FALSE)
  dir
}

test_that("a hand-made cells table pools to the F1 and difference computed by hand", {
  run <- hand_run(tempfile("newfor-hand-")); on.exit(unlink(run, recursive = TRUE))
  res <- quiet(ANA$run_main(list(RUN = run, N_BOOT = "200", SEED = "7")))
  P <- res$pooled
  pa <- P[P$scenario == "primary" & P$pool == "admitted", ]
  f1 <- function(r, p) 2 * r * p / (r + p)
  expect_equal(pa$F1[pa$config_name == "stock"], f1(0.6, 0.5))
  expect_equal(pa$F1[pa$config_name == "declared"], f1(0.56, 0.7))
  expect_identical(pa$n_plots, rep(5L, 5))
  expect_identical(pa$n_det[pa$config_name == "declared"], 40)
  all <- P[P$scenario == "primary" & P$pool == "all", ]
  expect_equal(all$F1[all$config_name == "stock"], 2 * 32 * 27 / (60 * 59))
  expect_equal(all$F1[all$config_name == "declared"], f1(0.5, 0.625))
  # height bands, stock: tall recall sum(TP - 1) / 30 = 25 / 30, null 5 x 0.5 / 30,
  # corrected (25 - 2.5) / (30 - 2.5); mid recall 5 / 10
  st <- pa[pa$config_name == "stock", ]
  expect_equal(c(st$rec_h_tall, st$null_rec_h_tall, st$cRec_h_tall),
               c(25 / 30, 2.5 / 30, 22.5 / 27.5))
  expect_equal(st$rec_h_mid, 0.5)
  expect_identical(pa$rec_h_short, rep(0, 5))
  # the contrast: estimates by hand, a percentile interval from the 200 draws
  C <- res$contrasts
  ds <- C[C$scenario == "primary" & C$pool == "admitted" & C$pair == "declared - stock", ]
  expect_equal(ds$difference[ds$metric == "F1"], f1(0.56, 0.7) - f1(0.6, 0.5))
  expect_equal(ds$estimate_b[ds$metric == "recall"], 0.6)
  expect_equal(ds$difference[ds$metric == "det_per_ref"], 40 / 50 - 50 / 50)
  expect_identical(ds$defined_draws[ds$metric == "F1"], 200L)
  expect_true(ds$lower[ds$metric == "F1"] <= ds$upper[ds$metric == "F1"])
  # the interval is mcg_contrast's own on the admitted plots
  cells <- read.csv(file.path(run, "cells.csv"), stringsAsFactors = FALSE)
  direct <- mcg_contrast(cells[cells$scenario == "primary" & cells$admitted, ],
                         paste0("NEWFOR::A", 1:5), "z5_s0.75_c0.6_e1_d8", "stock", n_boot = 200,
                         seed = 7, metrics = ANA$NFA_METRICS)
  expect_equal(ds$lower, direct$lower); expect_equal(ds$upper, direct$upper)
  # the reading follows the rule on that interval
  rd <- res$reading
  expect_identical(rd$reading, ANA$nfa_reading(rd$lower, rd$upper))
  expect_false(anyNA(rd$reading))
  # without_f leaves one admitted area (A5): an estimate without an interval
  lf <- C[C$pool == "without_f" & C$pair == "declared - stock" & C$metric == "F1", ]
  expect_identical(lf$n_plots, 1L)
  expect_true(is.na(lf$lower))
  expect_equal(lf$difference, f1(0.4, 0.5) - f1(0.6, 0.5))
  # without_g holds four plots, one short of an interval: estimates only
  wg4 <- C[C$pool == "without_g", ]
  expect_identical(nrow(wg4), nrow(ANA$NFA_PAIRS) * length(ANA$NFA_METRICS))
  expect_identical(unique(wg4$n_plots), 4L)
  expect_true(all(is.na(wg4$lower) & is.na(wg4$upper)))
  expect_identical(unique(wg4$defined_draws), 0L)
  expect_true(all(is.finite(wg4$difference[wg4$metric == "F1"])))
  # every scenario is pooled from its own cells (counts in hand_run): pooled F1
  # of the admitted areas by configuration, and declared - stock
  pool_f1 <- function(s, p, nm) P$F1[P$scenario == s & P$pool == p & P$config_name == nm]
  diff_f1 <- function(s, p) {
    x <- C[C$scenario == s & C$pool == p & C$pair == "declared - stock" & C$metric == "F1", ]
    expect_identical(nrow(x), 1L)
    x$difference
  }
  want <- list(inventoried = c(stock = f1(35 / 60, 30 / 50), declared = f1(33 / 60, 33 / 40)),
               registered = c(stock = f1(35 / 50, 30 / 50), declared = f1(33 / 50, 33 / 40)),
               tol2 = c(stock = f1(25 / 50, 20 / 50), declared = f1(23 / 50, 23 / 40)))
  for (s in names(want)) {
    expect_equal(pool_f1(s, "admitted", "stock"), want[[s]][["stock"]], info = s)
    expect_equal(pool_f1(s, "admitted", "declared"), want[[s]][["declared"]], info = s)
    expect_equal(diff_f1(s, "admitted"), want[[s]][["declared"]] - want[[s]][["stock"]],
                 info = s)
  }
  expect_identical(P$n_ref[P$scenario == "inventoried" & P$pool == "admitted"], rep(60, 5))
  # registered on every area brings in A6 (TP 5, tp_core 5 under both):
  # stock recall 40/60, precision 35/60; declared recall 38/60, precision 38/48
  expect_equal(diff_f1("registered", "all"), f1(38 / 60, 38 / 48) - f1(40 / 60, 35 / 60))
  # the scenarios differ from one another, so none can stand in for another
  d <- vapply(c("primary", "inventoried", "registered", "tol2"), diff_f1, 0, p = "admitted")
  expect_false(anyDuplicated(round(d, 12)) > 0)
  # 200 resamples and seed 7 are not the protocol's settings
  expect_false(res$settings$met)
  expect_identical(res$settings$reasons, c("N_BOOT is 200, not 1000", "SEED is 7, not 20261002"))
  expect_identical(res$reading$protocol_settings, c(FALSE, FALSE))
  # leave-one-forest-out: one row per forest and metric, then the range
  lo <- res$lofo
  expect_identical(lo$pool, c("without_f", "without_g", "without_f", "without_g", "minimum",
                              "maximum", "minimum", "maximum"))
  expect_identical(lo$left_out[1:2], c("F", "G"))
  wg <- f1(24 / 40, 24 / 32) - f1(24 / 40, 20 / 40)          # A1..A4
  expect_equal(lo$difference[lo$metric == "F1" & lo$pool == "without_g"], wg)
  expect_equal(lo$difference[lo$metric == "F1" & lo$pool == "minimum"],
               min(wg, f1(0.4, 0.5) - f1(0.6, 0.5)))
  expect_identical(lo$left_out[lo$metric == "F1" & lo$pool == "minimum"], "F")
  # per plot: A5 loses two detections, two matches and one commission
  # (unmatched inside: stock 10 - 5, declared 8 - 4)
  pp <- res$per_plot
  a5 <- pp[pp$area == "A5", ]
  expect_equal(c(a5$d_n_det, a5$d_TP, a5$d_fp), c(-2, -2, -1))
  expect_equal(a5$stock_F1, f1(0.6, 0.5)); expect_equal(a5$declared_F1, f1(0.4, 0.5))
  expect_equal(a5$d_F1, f1(0.4, 0.5) - f1(0.6, 0.5))
  a1 <- pp[pp$area == "A1", ]
  expect_equal(c(a1$d_n_det, a1$d_TP, a1$d_fp), c(-2, 0, -3))
  # the pools by density and gate state
  expect_identical(res$pools$density_inside, paste0("A", c(1:3)))
  expect_identical(res$pools$density_outside, c("A4", "A5"))
  expect_identical(res$pools$gate_closed, paste0("A", 1:5))
  expect_length(res$pools$gate_gated, 0L)
  expect_false("gate_gated" %in% res$pooled$pool)            # an empty pool has no row
})

test_that("the analysis states whether a run meets the protocol's settings", {
  # a conforming run: K 200, pinned library and versions, every frozen area, and
  # the protocol's resamples and seed (the defaults)
  run <- hand_run(tempfile("newfor-hand-")); on.exit(unlink(run, recursive = TRUE))
  res <- quiet(ANA$run_main(list(RUN = run)))
  expect_true(res$settings$met); expect_length(res$settings$reasons, 0L)
  rd <- read.csv(file.path(run, "analysis", "reading.csv"))
  expect_identical(rd$protocol_settings, c(TRUE, TRUE))
  aj <- jsonlite::read_json(file.path(run, "analysis", "analysis.json"), simplifyVector = TRUE)
  expect_true(aj$protocol_settings); expect_length(aj$protocol_settings_reasons, 0L)
  md <- readLines(file.path(run, "analysis", "tables.md"))
  expect_identical(md[3:8], c("Run with root aaaaaaaaaaaa, protocol bbbbbbbbbbbb.",
                              paste0("Detector library blob ", substr(DET$NFD_PIN_BLOB, 1, 12),
                                     ": pinned."),
                              "Packages: lidR 4.3.2, lidRplugins 0.4.0 (the pinned versions).",
                              "Null shifts per plot K = 200; 1000 resamples, seed 20261002.",
                              "Areas run: 6 of the 6 frozen.",
                              "Counts are sums over plots; rates come from the summed counts."))
  expect_false(any(grepl("does not meet", md)))
  # a run that breaks every setting: each is named, in the files and in tables.md
  bad <- hand_run(tempfile("newfor-hand-"), record = list(
    K = 4L, a = 0.2, tol = 3, null_min_shift = 6,
    detector_library = list(pin_matches = FALSE, allow_unpinned = TRUE),
    sources = list(newfor_lib.R = strrep("0", 64)),
    versions = list(lidR = "4.3.3"), versions_match = FALSE, root_areas = I(paste0("A", 1:8))))
  on.exit(unlink(bad, recursive = TRUE), add = TRUE)
  r2 <- quiet(ANA$run_main(list(RUN = bad, N_BOOT = "50", SEED = "1")))
  why <- c("K is 4, not 200", "a is 0.2, not 0.1", "tol is 3, not 4",
           "null_min_shift is 6, not 8", "the detector library is not the pinned one",
           "ALLOW_UNPINNED=1 was given", "lidR or lidRplugins is not the pinned version",
           "6 of the 8 frozen areas were run",
           "newfor_lib.R changed between the run and the analysis", "N_BOOT is 50, not 1000",
           "SEED is 1, not 20261002")
  expect_false(r2$settings$met)
  expect_identical(r2$settings$reasons, why)
  expect_identical(read.csv(file.path(bad, "analysis", "reading.csv"))$protocol_settings,
                   c(FALSE, FALSE))
  aj <- jsonlite::read_json(file.path(bad, "analysis", "analysis.json"), simplifyVector = TRUE)
  expect_false(aj$protocol_settings); expect_identical(aj$protocol_settings_reasons, why)
  md <- readLines(file.path(bad, "analysis", "tables.md"))
  expect_true(all(nchar(md[!startsWith(md, "|")]) <= 80))
  expect_true(paste0("Detector library blob ", substr(DET$NFD_PIN_BLOB, 1, 12),
                     ": unpinned, ALLOW_UNPINNED=1 given.") %in% md)
  expect_true("Packages: lidR 4.3.3, lidRplugins 0.4.0 (not the pinned versions)." %in% md)
  expect_true("Areas run: 6 of the 8 frozen." %in% md)
  i <- grep("^This run does not meet the protocol's settings: ", md)
  j <- grep("^Counts are sums over plots", md)
  expect_identical(length(i), 1L)
  expect_identical(paste(md[i:(j - 1L)], collapse = " "),
                   paste0("This run does not meet the protocol's settings: ",
                          paste(why, collapse = "; "), "."))
  # a setting that run.json does not record counts as not met
  rec <- jsonlite::read_json(file.path(run, "run.json"), simplifyVector = TRUE)
  code <- newfor_code_sha256(ANA$NFA_CODE, .find)                    # the analysis's own hashes
  settings <- function(r, cd = code) ANA$nfa_protocol_settings(r, 1000L, 20261002L, cd)
  expect_true(settings(rec)$met)
  expect_length(settings(rec)$reasons, 0L)
  gone <- list(K = "K: not recorded", a = "a: not recorded", tol = "tol: not recorded",
               null_min_shift = "null_min_shift: not recorded",
               versions_match = "package versions: not recorded",
               areas = "frozen areas: not recorded", root_areas = "frozen areas: not recorded",
               detector_library = "detector pin: not recorded", sources = "sources: not recorded")
  for (k in names(gone)) {
    r <- rec; r[[k]] <- NULL
    s <- settings(r)
    expect_false(s$met, info = k); expect_identical(s$reasons, gone[[k]], info = k)
  }
  # a is read by its full name: without it, areas is not taken for it
  expect_false(is.null(rec$areas))
  r <- rec; r$sources <- list()
  expect_identical(settings(r)$reasons, "sources: not recorded")
  r <- rec; r$sources <- unname(rec$sources)
  expect_identical(settings(r)$reasons, "sources: not recorded")
  # each setting off the protocol's value, alone
  off <- list(K = list(201L, "K is 201, not 200"), a = list(0.11, "a is 0.11, not 0.1"),
              tol = list(2, "tol is 2, not 4"),
              null_min_shift = list(8.5, "null_min_shift is 8.5, not 8"))
  for (k in names(off)) {
    r <- rec; r[[k]] <- off[[k]][[1]]
    expect_identical(settings(r)$reasons, off[[k]][[2]], info = k)
  }
  # a file hashed by both the run's sources and the analysis must not differ;
  # files that only one of them hashes are not compared
  expect_true(all(c("detect_newfor_multichm.R", "newfor_lib.R") %in% names(rec$sources)))
  expect_false("detect_newfor_multichm.R" %in% names(code))
  r <- rec; r$sources$detect_newfor_multichm.R <- strrep("1", 64)
  expect_true(settings(r)$met)
  r <- rec; r$sources$newfor_lib.R <- strrep("0", 64); r$sources$sweep_lib.R <- strrep("0", 64)
  expect_identical(settings(r)$reasons,                              # in the analysis's order
                   c("sweep_lib.R changed between the run and the analysis",
                     "newfor_lib.R changed between the run and the analysis"))
  cd <- code; cd[["bootstrap.R"]] <- strrep("2", 64)                 # the analysis's side changed
  expect_identical(settings(rec, cd)$reasons,
                   "bootstrap.R changed between the run and the analysis")
  r <- rec; r$detector_library$allow_unpinned <- NULL
  expect_identical(settings(r)$reasons, "detector pin: not recorded")
  r <- rec; r$detector_library$allow_unpinned <- TRUE
  expect_identical(settings(r)$reasons, "ALLOW_UNPINNED=1 was given")
  r <- rec; r[c("versions_match", "root_areas")] <- NULL
  head <- ANA$nfa_settings_lines(r, settings(r), 1000L, 20261002L)
  expect_true("Packages: lidR 4.3.2, lidRplugins 0.4.0 (pins not recorded)." %in% head)
  expect_identical(head[5], "Areas run: 6; the frozen areas are not recorded.")
  expect_identical(paste(head[-(1:5)], collapse = " "),
                   paste("This run does not meet the protocol's settings: package versions: not",
                         "recorded; frozen areas: not recorded."))
  expect_true(all(nchar(head) <= 80))
})

test_that("the protocol's values the analysis holds are the library's constants", {
  # the analysis compares run.json with literals, so a constant changed in the
  # library would otherwise go unnoticed
  expect_identical(names(ANA$NFA_PROTOCOL), c("K", "a", "tol", "null_min_shift"))
  expect_identical(vapply(ANA$NFA_PROTOCOL, as.numeric, 0),
                   c(K = NEWFOR_NULL_K, a = NEWFOR_A, tol = NEWFOR_TOL,
                     null_min_shift = NEWFOR_NULL_MIN_SHIFT))
  expect_identical(ANA$NFA_PROTOCOL$K, 200L)
  expect_identical(c(ANA$NFA_PROTOCOL$a, ANA$NFA_PROTOCOL$tol, ANA$NFA_PROTOCOL$null_min_shift),
                   c(0.10, 4, 8))
})

test_that("tables.md rounds to three decimals, writes counts as integers and names sources", {
  run <- hand_run(tempfile("newfor-hand-")); on.exit(unlink(run, recursive = TRUE))
  quiet(ANA$run_main(list(RUN = run, N_BOOT = "50")))
  md <- readLines(file.path(run, "analysis", "tables.md"))
  expect_identical(md[1], "# NEWFOR multichm: analysis tables")
  expect_true(all(nchar(md[!startsWith(md, "|")]) <= 80))     # prose within rumdl's limit
  i <- grep("^## Pooled, admitted areas", md)
  expect_identical(md[i + 2L], "From pooled.csv, pool admitted.")
  row <- md[i + 6L]                                            # primary, stock
  expect_true(startsWith(row, paste("| primary | stock | 5 | 50 | 50 | 30 | 25 | 0.600 | 0.500",
                                    "| 0.545 |")))
  expect_identical(ANA$.nfa_cell(c(-0.0001, 1 / 3, NA), "F1"), c("0.000", "0.333", "NA"))
  expect_identical(ANA$.nfa_cell(c(3, 12), "stock_TP"), c("3", "12"))
  expect_identical(ANA$.nfa_cell(c(1.25, 2), "TP"), c("1.250", "2.000"))  # not whole: decimals
  expect_identical(ANA$nfa_md_table(data.frame(a = 1)[0, , drop = FALSE], "a"), "(no rows)")
})

## ---- the after-run checks (check_newfor_run.R) -------------------------------------------------
CHK_MOVES_COLS <- c("area", "forest", "admitted", "config_name", "tol", "dx", "dy", "n_ref", "TP",
                    "TP_moved", "null_mean", "null_max", "shifts_reaching_released",
                    "shifts_reaching_moved")
CHK_FOREST_COLS <- c("pair", "metric", "n_forests", "n_plots", "difference", "lower", "upper",
                     "defined_draws")

test_that("check: arguments are KEY=VALUE; unknown, repeated or empty keys and bad numbers stop", {
  expect_identical(CHK$nfc_args(character()), list())
  expect_identical(CHK$nfc_args(c("RUN=/a=b/run", "N_BOOT=10")),
                   list(RUN = "/a=b/run", N_BOOT = "10"))
  expect_error(CHK$nfc_args("RUNS=/x"), "unknown argument RUNS=")
  expect_error(CHK$nfc_args("RUN"), "KEY=VALUE")
  expect_error(CHK$nfc_args(c("SEED=1", "SEED=2")), "SEED= is given twice")
  expect_error(CHK$nfc_args("FROZEN="), "FROZEN= needs a value")
  # no key extends another, so no prefix can be read as a longer key
  for (k in CHK$NFC_KEYS) expect_false(any(startsWith(setdiff(CHK$NFC_KEYS, k), k)), info = k)
  expect_identical(CHK$.nfc_int(list(), "N_BOOT", 1000L, 1L), 1000L)
  expect_identical(CHK$.nfc_int(list(N_BOOT = "25"), "N_BOOT", 1000L, 1L), 25L)
  expect_identical(CHK$.nfc_int(list(SEED = "0"), "SEED", 1L, 0L), 0L)
  for (v in c("0", "2.5", "x", "Inf", "NaN", "3e9"))
    expect_error(CHK$.nfc_int(list(N_BOOT = v), "N_BOOT", 1000L, 1L),
                 "N_BOOT= must be a whole number of at least 1", info = v)
  # flags are read as logical or as the strings TRUE and FALSE; anything else stops
  expect_identical(CHK$.nfc_flag(c(TRUE, FALSE), "x"), c(TRUE, FALSE))
  expect_identical(CHK$.nfc_flag(c("FALSE", "TRUE"), "x"), c(FALSE, TRUE))
  for (v in list(c(TRUE, NA), c("TRUE", "yes"), c("1", "0"), NA_character_))
    expect_error(CHK$.nfc_flag(v, "cells.csv: admitted"), "must be TRUE or FALSE in every row")
})

test_that("check: forest weights are constant within a forest, as many forests drawn as exist", {
  forest <- c("b", "a", "b", "c", "b", "a")                  # forests of 3, 2 and 1 plots
  W <- CHK$nfc_forest_weights(forest, n_boot = 60, seed = 7)
  expect_identical(dim(W), c(6L, 60L))
  expect_true(all(W >= 0 & W == round(W)))
  # each column is constant within a forest ...
  for (f in unique(forest))
    expect_true(all(t(W[forest == f, , drop = FALSE]) == W[match(f, forest), ]), info = f)
  # ... and the per-forest counts of a column sum to the number of forests
  expect_true(all(colSums(W[match(c("a", "b", "c"), forest), ]) == 3))
  # a column sums to the number of plots only when the forests are of equal size
  expect_true(any(colSums(W) != length(forest)))
  eq <- rep(c("a", "b", "c"), each = 2)
  expect_true(all(colSums(CHK$nfc_forest_weights(eq, 60, 7)) == length(eq)))
  # the same seed gives the same matrix, another seed another one
  expect_identical(CHK$nfc_forest_weights(forest, 60, 7), W)
  expect_false(identical(CHK$nfc_forest_weights(forest, 60, 8), W))
  expect_error(CHK$nfc_forest_weights(c("a", NA), 5, 1), "every plot needs a forest")
  expect_error(CHK$nfc_forest_weights(c("a", ""), 5, 1), "every plot needs a forest")
})

test_that("check: forest weights leave the caller's RNG kind and state as they were", {
  old_kind <- RNGkind()
  withr::local_preserve_seed()
  withr::defer(do.call(RNGkind, as.list(old_kind)))       # runs first: the kind, then the seed
  seed_now <- function() get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  set.seed(99); s <- seed_now(); k <- RNGkind()
  CHK$nfc_forest_weights(c("a", "b"), 10, 1)
  expect_identical(seed_now(), s); expect_identical(RNGkind(), k)
  # another generator set by the caller is kept, with its state
  RNGkind("L'Ecuyer-CMRG", "Box-Muller"); set.seed(3); s <- seed_now(); k <- RNGkind()
  CHK$nfc_forest_weights(c("a", "b"), 10, 1)
  expect_identical(seed_now(), s); expect_identical(RNGkind(), k)
  # no seed before, none after
  rm(".Random.seed", envir = globalenv())
  CHK$nfc_forest_weights(c("a", "b"), 10, 1)
  expect_null(seed_now())
})

# Cells of five plots for every configuration of NFC_PAIRS in two scenarios.
# Primary cells of the admitted plots P1..P4 (forests as given): n_ref 10;
# stock n_det 10 and TP = tp_core = 6; every other configuration n_det 8 and
# TP = tp_core = 6, except P4 with 4; nulls n_det0 = n_det, TP0 = tp_core0 = 1.
# The inventoried cells and P5 (not admitted) carry counts that would change
# every estimate if they were read.
chk_cells <- function(forest = c(P1 = "F", P2 = "F", P3 = "G", P4 = "G")) {
  cfg <- unique(c(CHK$NFC_PAIRS$a, CHK$NFC_PAIRS$b))
  g <- expand.grid(plot = c(names(forest), "P5"), config_name = cfg,
                   scenario = c("primary", "inventoried"), stringsAsFactors = FALSE)
  g$forest <- unname(c(forest, P5 = "F")[g$plot]); g$admitted <- g$plot != "P5"
  stock <- g$config_name == "stock"
  g$n_ref <- 10; g$n_det <- ifelse(stock, 10, 8)
  g$TP <- ifelse(!stock & g$plot == "P4", 4, 6)
  junk <- g$scenario != "primary" | !g$admitted
  g$TP[junk] <- 0; g$n_det[junk] <- 30
  g$tp_core <- g$TP; g$n_det0 <- g$n_det; g$TP0 <- 1; g$tp_core0 <- 1
  for (k in c("n_over", "n_under", "tp_over", "tp_under", "tp_over0", "tp_under0")) g[[k]] <- 0
  g$site <- NEWFOR_SITE; g$config <- g$config_name
  g
}

test_that("check: forest-resampled contrasts give the estimates and the draws worked by hand", {
  cells <- chk_cells()
  fc <- CHK$nfc_forest_contrasts(cells, n_boot = 100, seed = 11)
  expect_identical(names(fc), CHK_FOREST_COLS)
  expect_identical(fc$pair, rep(paste(CHK$NFC_PAIRS$a, "-", CHK$NFC_PAIRS$b), each = 4))
  expect_identical(fc$metric, rep(CHK$NFC_METRICS, 5))
  expect_true(all(fc$n_forests == 2L & fc$n_plots == 4L))
  ds <- fc[fc$pair == "declared - stock", ]
  # Summed over P1..P4: stock matches 24 of 40 stems with 24 of 40 detections,
  # declared 22 of 40 with 22 of 32. F1 = 2 TP / (n_ref + n_det): 44/72 against
  # 48/80. The nulls: recall 4/40, precision 4/40 (stock) and 4/32 (declared),
  # so null F1 1/10 and 1/9, and cF1 = (F1 - null) / (1 - null) is 5/9 and 9/16.
  expect_equal(ds$difference, c(44 / 72 - 0.6, 9 / 16 - 5 / 9, 22 / 32 - 0.6, 22 / 40 - 0.6))
  expect_true(all(fc$difference[fc$pair == "declared - floor_exempt"] == 0))
  # The draws by hand: a resample draws forest F twice (P1 and P2 twice, P3 and P4
  # never), once (every plot once) or never (P3 and P4 twice); W[1, ] counts F.
  # Stock's recall and F1 are 0.6 in every draw; declared matches 24, 22 or 20 of 40
  # stems with 32 detections.
  nF <- CHK$nfc_forest_weights(c("F", "F", "G", "G"), 100, 11)[1, ]
  by_hand <- list(recall = c(20 / 40, 22 / 40, 24 / 40)[nF + 1] - 0.6,
                  F1 = c(40 / 72, 44 / 72, 48 / 72)[nF + 1] - 0.6,
                  precision = c(20 / 32, 22 / 32, 24 / 32)[nF + 1] - 0.6)
  for (m in names(by_hand)) {
    iv <- mt_interval(by_hand[[m]])
    row <- ds[ds$metric == m, ]
    expect_equal(c(row$lower, row$upper), c(iv$lower, iv$upper), info = m)
    expect_identical(row$defined_draws, iv$defined_draws, info = m)
  }
  expect_true(any(nF == 0) && any(nF == 1) && any(nF == 2))     # every case is drawn
})

test_that("check: forest contrasts: admitted as text, no interval for one forest, gaps stop", {
  cells <- chk_cells()
  fc <- CHK$nfc_forest_contrasts(cells, 50, 3)
  txt <- cells; txt$admitted <- as.character(txt$admitted)        # "TRUE" and "FALSE"
  expect_identical(CHK$nfc_forest_contrasts(txt, 50, 3), fc)
  bad <- cells; bad$admitted[1] <- NA
  expect_error(CHK$nfc_forest_contrasts(bad, 50, 3), "must be TRUE or FALSE in every row")
  # one forest: the same estimates, and no interval, since every draw would repeat them
  one <- CHK$nfc_forest_contrasts(chk_cells(c(P1 = "F", P2 = "F", P3 = "F", P4 = "F")), 50, 3)
  expect_identical(names(one), CHK_FOREST_COLS)
  expect_identical(one$difference, fc$difference)
  expect_true(all(one$n_forests == 1L & is.na(one$lower) & is.na(one$upper) &
                    one$defined_draws == 0L))
  # unequal support: a missing cell, a repeated one, a configuration missing altogether
  pri <- cells$scenario == "primary"
  expect_error(CHK$nfc_forest_contrasts(
    cells[!(pri & cells$plot == "P2" & cells$config_name == "declared"), ], 50, 3),
    "configuration declared must cover each of the 4 admitted areas once")
  expect_error(CHK$nfc_forest_contrasts(
    rbind(cells, cells[pri & cells$plot == "P1" & cells$config_name == "stock", ]), 50, 3),
    "configuration stock must cover each of the 4 admitted areas once")
  expect_error(CHK$nfc_forest_contrasts(cells[cells$config_name != "gate_all", ], 50, 3),
               "configuration gate_all must cover")
  # an admitted area needs one forest
  two <- cells; two$forest[two$plot == "P1" & two$config_name == "stock"] <- "G"
  expect_error(CHK$nfc_forest_contrasts(two, 50, 3), "needs one forest")
  none <- cells; none$forest[none$plot == "P3"] <- NA
  expect_error(CHK$nfc_forest_contrasts(none, 50, 3), "needs one forest")
  expect_error(CHK$nfc_forest_contrasts(cells[0, ], 50, 3), "no admitted area")
  expect_error(CHK$nfc_forest_contrasts(cells[setdiff(names(cells), "TP0")], 50, 3),
               "the cells lack TP0")
  expect_error(CHK$nfc_forest_contrasts(cells, 50, 3, metrics = "G-mean"), "unknown metrics")
})

test_that("check: with one plot per forest the draws are mcg_contrast's when the orders agree", {
  # mcg_contrast draws mt_plot_weights, which for one site sets the same
  # generators and seed and makes one sample.int(n, n, replace = TRUE) call per
  # draw over the sorted plot ids, as nfc_forest_weights does over the sorted
  # forests. So with one plot per forest the two weight matrices are equal when
  # the forests sort as their plots do (checked below, not assumed), and then so
  # are the intervals. When they sort otherwise the rows are permuted and the
  # draws differ; only the estimates must agree.
  ids <- paste0("P", 1:4)
  pw <- mt_plot_weights(rep(NEWFOR_SITE, 4), ids, 200, 5)
  storage.mode(pw) <- "double"
  pair <- data.frame(a = "declared", b = "stock", stringsAsFactors = FALSE)
  m <- c("F1", "recall", "precision")
  primary <- function(cells) cells[cells$scenario == "primary" & cells$admitted, ]
  same <- chk_cells(c(P1 = "F1", P2 = "F2", P3 = "F3", P4 = "F4"))
  expect_identical(CHK$nfc_forest_weights(c("F1", "F2", "F3", "F4"), 200, 5), unname(pw))
  fc <- CHK$nfc_forest_contrasts(same, 200, 5, pair, m)
  mc <- mcg_contrast(primary(same), paste(NEWFOR_SITE, ids, sep = "::"), "declared", "stock",
                     200, 5, metrics = m)
  expect_equal(fc$difference, mc$difference)
  expect_equal(c(fc$lower, fc$upper), c(mc$lower, mc$upper))
  expect_identical(fc$defined_draws, mc$defined_draws)
  # forests in the reverse order of their plots: P1's forest sorts last
  rev <- chk_cells(c(P1 = "F4", P2 = "F3", P3 = "F2", P4 = "F1"))
  expect_identical(CHK$nfc_forest_weights(c("F4", "F3", "F2", "F1"), 200, 5), unname(pw[4:1, ]))
  expect_equal(CHK$nfc_forest_contrasts(rev, 200, 5, pair, m)$difference, mc$difference)
})

# A run written by hand over the e2e freeze root: the given stock and declared
# detections per area under <dir>/detections, and the labels and features the
# registration check reads.
chk_hand_moves <- function(dir, dets, features) {
  lab <- stats::setNames(DET$nfd_config_table(newfor_configs())$label, names(newfor_configs()))
  for (id in names(dets)) for (nm in names(dets[[id]])) {
    d <- file.path(dir, "detections", id)
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    DET$nfd_write_detections(dets[[id]][[nm]], file.path(d, paste0(lab[[nm]], ".csv")))
  }
  list(labels = lab, features = features)
}

test_that("check: registration moves on detections placed by hand over the synthetic root", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  ids <- c("91", "92")
  fa <- stats::setNames(lapply(ids, function(id) newfor_frozen_area(e$root, id)), ids)
  stems <- lapply(fa, function(a) newfor_stems(a$stems, "primary"))
  at <- function(s, dx = 0) data.frame(x = s$E + dx, y = s$N, z = s$height)
  P <- nrow(stems[["91"]]); Q <- nrow(stems[["92"]])
  expect_gte(P, 4L); expect_gte(Q, 2L)
  # Area 91, estimate (3, 0): stock has a detection on every stem but the first
  # two, whose detections lie 3 m east of them; declared has one on every stem.
  # The stems are at least 5.6 m apart, so no detection comes within 2 m of
  # another stem when moved by 3 m: moving by minus the estimate matches stock's
  # two offset detections and loses every other. Area 92, estimate (0, 0): stock
  # on every stem, declared on every stem but the first; nothing moves.
  s91 <- stems[["91"]]
  dets <- list(`91` = list(stock = rbind(at(s91[1:2, ], 3), at(s91[-(1:2), ])),
                           declared = at(s91)),
               `92` = list(stock = at(stems[["92"]]), declared = at(stems[["92"]][-1, ])))
  feats <- data.frame(area = ids, forest = c("Alpha Wood", "Beta-Forest"),
                      admitted = c(TRUE, FALSE), dx = c(3, 0), dy = c(0, 0),
                      stringsAsFactors = FALSE)
  run <- file.path(e$base, "check-hand")
  r <- chk_hand_moves(run, dets, feats)
  mv <- CHK$nfc_registration_moves(e$root, run, r, tol = 2, k = NF_K)
  expect_identical(names(mv), CHK_MOVES_COLS)
  expect_identical(mv$area, rep(ids, each = 2))
  expect_identical(mv$config_name, rep(c("stock", "declared"), 2))
  expect_identical(mv$admitted, c(TRUE, TRUE, FALSE, FALSE))
  expect_equal(mv$n_ref, c(P, P, Q, Q))
  expect_equal(mv$TP, c(P - 2, P, Q, Q - 1))
  expect_equal(mv$TP_moved, c(2, 0, Q, Q - 1))       # 91 lowered by P - 4 and by P; 92 unmoved
  # the null: null_mean is newfor_score_cell's TP0 for the same K offsets of the 2 m window
  for (i in seq_len(nrow(mv))) {
    id <- mv$area[i]
    det <- dets[[id]][[mv$config_name[i]]]
    win <- newfor_window(fa[[id]]$aoi, 2)
    offs <- newfor_null_offsets(id, win$w, win$h, k = NF_K)
    cell <- newfor_score_cell(stems[[id]], det, fa[[id]]$aoi, id, tol = 2, offsets = offs)
    expect_equal(mv$TP[i], cell$TP, info = i)
    expect_equal(mv$null_mean[i], cell$TP0, info = i)
    tps <- vapply(offs, function(o)
      newfor_score(stems[[id]], newfor_shift(det, win, o), fa[[id]]$aoi, 2)[["TP"]], 0)
    expect_equal(mv$null_max[i], max(tps), info = i)
    expect_identical(mv$shifts_reaching_released[i], sum(tps >= mv$TP[i]), info = i)
    expect_identical(mv$shifts_reaching_moved[i], sum(tps >= mv$TP_moved[i]), info = i)
  }
  # no estimate (either coordinate NA): nothing moves; K = 0: no null
  na <- feats; na$dx <- c(3, NA); na$dy <- c(NA, NA)
  mv0 <- CHK$nfc_registration_moves(e$root, run, list(labels = r$labels, features = na),
                                    tol = 2, k = 0)
  expect_equal(mv0$TP, mv$TP); expect_equal(mv0$TP_moved, mv0$TP)
  expect_identical(mv0$dy, rep(NA_real_, 4))
  expect_true(all(is.na(mv0[c("null_mean", "null_max", "shifts_reaching_released",
                              "shifts_reaching_moved")])))
  # admitted read as text gives the same rows
  txt <- feats; txt$admitted <- as.character(txt$admitted)
  expect_identical(CHK$nfc_registration_moves(e$root, run, list(labels = r$labels,
                                                                features = txt), 2, k = NF_K),
                   mv)
  # refusals
  expect_error(CHK$nfc_registration_moves(e$root, run, list(labels = r$labels["stock"],
                                                            features = feats), k = 1),
               "the run has no configuration declared")
  expect_error(CHK$nfc_registration_moves(e$root, run, list(labels = r$labels,
                                                            features = feats[c(1, 1, 2), ]),
                                          k = 1), "list every area of the run once")
  expect_error(CHK$nfc_registration_moves(e$root, run, list(labels = r$labels,
                                                            features = feats[-5]), k = 1),
               "features.csv lacks dy")
  bad <- feats; bad$admitted <- c("TRUE", "maybe")
  expect_error(CHK$nfc_registration_moves(e$root, run, list(labels = r$labels, features = bad),
                                          k = 1), "must be TRUE or FALSE")
  expect_error(CHK$nfc_registration_moves(e$root, run, r, k = 1.5), "k must be a whole number")
  unlink(file.path(run, "detections", "92", paste0(r$labels[["declared"]], ".csv")))
  expect_error(CHK$nfc_registration_moves(e$root, run, r, k = 1), "holds no detections")
  unlink(run, recursive = TRUE)
})

# A copy of the e2e run's run.json, features.csv, cells.csv and detections.
chk_copy_run <- function(e, name) {
  d <- file.path(e$base, name)
  dir.create(d)
  file.copy(file.path(e$out, c("run.json", "features.csv", "cells.csv", "detections")), d,
            recursive = TRUE)
  d
}

test_that("check: run_main writes its two tables and after_run.json, and never touches analysis/", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  run <- chk_copy_run(e, "check-run")
  inputs <- nf_hashes(run)
  quiet(CHK$run_main(list(FROZEN = e$root, RUN = run, N_BOOT = "20")))
  expect_false(dir.exists(file.path(run, "analysis")))                # not created
  out <- file.path(run, "after_run")
  expect_setequal(list.files(out, all.files = TRUE, no.. = TRUE),
                  c("registration_moves.csv", "forest_resampled.csv", "after_run.json"))
  expect_identical(nf_hashes(run)[names(inputs)], inputs)            # the run's files as they were
  mv <- read.csv(file.path(out, "registration_moves.csv"), stringsAsFactors = FALSE,
                 colClasses = c(area = "character"))
  expect_identical(names(mv), CHK_MOVES_COLS)
  expect_identical(mv$area, rep(c("91", "92"), each = 2))
  expect_identical(mv$config_name, rep(c("stock", "declared"), 2))
  # as released, the check scores what the run's tol2 scenario scored, against its K offsets
  cells <- read.csv(file.path(run, "cells.csv"), stringsAsFactors = FALSE,
                    colClasses = c(plot = "character"))
  t2 <- cells[cells$scenario == "tol2", ]
  j <- match(paste(mv$area, mv$config_name), paste(t2$plot, t2$config_name))
  expect_false(anyNA(j))
  expect_equal(mv$n_ref, t2$n_ref[j]); expect_equal(mv$TP, t2$TP[j])
  expect_equal(mv$null_mean, t2$TP0[j])
  fr <- read.csv(file.path(out, "forest_resampled.csv"), stringsAsFactors = FALSE)
  expect_identical(names(fr), CHK_FOREST_COLS)
  expect_identical(nrow(fr), 20L)
  # one admitted area, so one forest: estimates without an interval
  expect_true(all(fr$n_forests == 1L & fr$n_plots == 1L & is.na(fr$lower) & is.na(fr$upper) &
                    fr$defined_draws == 0L))
  aj <- jsonlite::read_json(file.path(out, "after_run.json"), simplifyVector = TRUE)
  expect_identical(names(aj), c("run_json_sha256", "root_id", "code_sha256", "tol", "K", "n_boot",
                                "seed"))
  expect_identical(aj$run_json_sha256, frozen_sha256(file.path(run, "run.json")))
  expect_identical(aj$root_id, newfor_root_id(e$root))
  expect_identical(unlist(aj$code_sha256),
                   vapply(CHK$NFC_CODE, function(f) frozen_sha256(.find(f)), ""))
  expect_equal(c(aj$tol, aj$K, aj$n_boot, aj$seed), c(2, NF_K, 20, 20261002))
  txt <- readLines(file.path(out, "after_run.json"))                 # no path and no date
  expect_false(any(grepl(e$base, txt, fixed = TRUE)))
  expect_false(any(grepl(format(Sys.Date(), "%Y-%m-%d"), txt, fixed = TRUE)))
  # the declared analysis, run next, is left as it is by a second check, which
  # writes the same bytes again
  quiet(ANA$run_main(list(RUN = run, N_BOOT = "20")))
  ana <- nf_hashes(file.path(run, "analysis"))
  first <- nf_hashes(out)
  quiet(CHK$run_main(list(FROZEN = e$root, RUN = run, N_BOOT = "20")))
  expect_identical(nf_hashes(file.path(run, "analysis")), ana)
  expect_identical(nf_hashes(out), first)
  # the estimates are the analysis's own primary contrasts on the admitted pool
  con <- read.csv(file.path(run, "analysis", "contrasts.csv"), stringsAsFactors = FALSE)
  con <- con[con$scenario == "primary" & con$pool == "admitted", ]
  k <- match(paste(fr$pair, fr$metric), paste(con$pair, con$metric))
  expect_false(anyNA(k))
  expect_equal(fr$difference, con$difference[k])
  unlink(run, recursive = TRUE)
})

test_that("check: run_main refuses another root, a run without K and tables that disagree", {
  skip_if_not_installed("lidRplugins")
  e <- nf_e2e()
  edit_run_json <- function(run, f) {
    rj <- jsonlite::read_json(file.path(run, "run.json"), simplifyVector = TRUE)
    jsonlite::write_json(f(rj), file.path(run, "run.json"), auto_unbox = TRUE, digits = NA,
                         na = "null", pretty = TRUE)
  }
  a <- chk_copy_run(e, "check-root")
  expect_error(CHK$run_main(list(FROZEN = file.path(e$base, "nowhere"), RUN = a)),
               "no sealed freeze root at")
  edit_run_json(a, function(rj) { rj$frozen$root_id <- strrep("0", 64); rj })
  expect_error(CHK$run_main(list(FROZEN = e$root, RUN = a)),
               "was run on the freeze root 000000000000, not on")
  edit_run_json(a, function(rj) { rj$frozen$root_id <- NULL; rj })
  expect_error(CHK$run_main(list(FROZEN = e$root, RUN = a)), "records no freeze root id")
  b <- chk_copy_run(e, "check-k")
  edit_run_json(b, function(rj) { rj$K <- NULL; rj })
  expect_error(CHK$run_main(list(FROZEN = e$root, RUN = b)), "run.json records no K")
  edit_run_json(b, function(rj) { rj$K <- -1L; rj })
  expect_error(CHK$run_main(list(FROZEN = e$root, RUN = b)), "run.json records no K")
  c3 <- chk_copy_run(e, "check-agree")
  f <- read.csv(file.path(c3, "features.csv"), stringsAsFactors = FALSE,
                colClasses = c(area = "character"))
  f$admitted <- TRUE                                                  # area 92 was not admitted
  write.csv(f, file.path(c3, "features.csv"), row.names = FALSE)
  expect_error(CHK$run_main(list(FROZEN = e$root, RUN = c3)),
               "features.csv and cells.csv disagree on the admitted areas")
  for (d in c(a, b, c3)) {
    expect_false(dir.exists(file.path(d, "after_run")), info = d)
    unlink(d, recursive = TRUE)
  }
})

## ---- the R files each run record hashes ---------------------------------------------------------
# The R files that `script` (a base name under scripts/) sources, directly or
# through the files it sources, by base name in the order each is first
# reached (depth first), `script` first. It scans the parsed code of each file
# (comments and strings that merely mention source( are ignored) for calls
# source(x): x names the files whose "*.R" string constants it holds
# (source(.find("newfor_lib.R"))); when it holds none (source(bs[1])), the "*.R"
# constants of the right-hand sides of the file's assignments to the variables
# x uses, followed through further variables (bs <- Find(file.exists,
# c(..., "bootstrap.R")) in the same file). Every such call is found, whatever
# branch or function body holds it, and a named file missing from scripts/
# stops the scan. It does not catch a file loaded by sys.source(), base::source()
# or other means, a name built at run time (paste0) or held in another file's
# variable, or a source() call in a function's default argument; and it lists
# a file whose source() call never runs.
nf_scan_sources <- function(script, dir = file.path("..", "..", "scripts")) {
  calls <- function(e) {                       # every call inside e, outermost first
    if (!is.call(e)) return(list())
    c(list(e), unlist(lapply(seq_along(e)[-1], function(i) if (is.call(e[[i]])) calls(e[[i]])),
                      recursive = FALSE))
  }
  r_files <- function(e) {                     # the "*.R" string constants in e
    d <- paste(deparse(e, width.cutoff = 500L), collapse = " ")
    unique(basename(gsub('"', "", regmatches(d, gregexpr('"[^"]*\\.R"', d))[[1]])))
  }
  seen <- character()
  visit <- function(f) {
    p <- file.path(dir, f)
    if (!file.exists(p)) stop("nf_scan_sources: ", f, " is not in ", dir, call. = FALSE)
    seen <<- c(seen, f)
    cl <- unlist(lapply(as.list(parse(p, keep.source = FALSE)), calls), recursive = FALSE)
    rhs <- function(v) Filter(Negate(is.null), lapply(cl, function(k)
      if (as.character(k[[1]])[1] %in% c("<-", "=", "<<-") && identical(k[[2]], as.name(v)))
        k[[3]]))
    named <- function(e, done = character()) {
      nm <- r_files(e)
      if (length(nm)) return(nm)
      for (v in setdiff(all.vars(e), done)) {
        done <- c(done, v)
        nm <- c(nm, unlist(lapply(rhs(v), named, done = done)))
      }
      unique(nm)
    }
    for (k in cl) {
      if (!identical(k[[1]], as.name("source")) || length(k) < 2L) next
      x <- if ("file" %in% names(k)) k[["file"]] else k[[2]]
      for (g in named(x)) if (!g %in% seen) visit(g)
    }
  }
  visit(script)
  seen
}

test_that("freeze.json's code_sha256 names every R file the freeze sources; a missing one stops", {
  expect_identical(FRZ$.FREEZE_CODE, nf_scan_sources("freeze_newfor.R"))
  # a file that cannot be found stops the freeze before anything is written
  dir <- tempfile("newfor-code-"); dir.create(file.path(dir, "raw"), recursive = TRUE)
  old <- FRZ$.FREEZE_CODE
  on.exit({ FRZ$.FREEZE_CODE <- old; unlink(dir, recursive = TRUE) })
  inp <- file.path(dir, c("meta.json", "files.json", "protocol.md")); file.create(inp)
  FRZ$.FREEZE_CODE <- c(old, "no_such_file.R")
  expect_error(FRZ$newfor_freeze(file.path(dir, "raw"), file.path(dir, "frozen"), inp[1], inp[2],
                                 inp[3]),
               "R file the run record must hash is not found: no_such_file.R")
  expect_false(file.exists(file.path(dir, "frozen")))
})

test_that("run.json's sources name every R file the run sources but the pinned library", {
  got <- nf_scan_sources("detect_newfor_multichm.R")
  expect_true("multichm_gated_lib.R" %in% got)                # recorded under detector_library
  expect_identical(DET$NFD_SOURCES, setdiff(got, "multichm_gated_lib.R"))
  # a file that cannot be found stops the run record, which is built before any write
  proto <- tempfile(fileext = ".md"); writeLines("# protocol", proto)
  old <- DET$NFD_SOURCES
  on.exit({ DET$NFD_SOURCES <- old; unlink(proto) })
  DET$NFD_SOURCES <- c(old, "no_such_file.R")
  expect_error(DET$nfd_run_record(list(protocol = proto, allow_unpinned = TRUE), NULL,
                                  character(), list()),
               "R file the run record must hash is not found: no_such_file.R")
})

test_that("analysis.json's code_sha256 names every R file the analysis sources", {
  expect_identical(ANA$NFA_CODE, nf_scan_sources("analyze_newfor_multichm.R"))
  # a file that cannot be found stops the analysis before anything is written
  run <- hand_run(tempfile("newfor-hand-"))
  old <- ANA$NFA_CODE
  on.exit({ ANA$NFA_CODE <- old; unlink(run, recursive = TRUE) })
  ANA$NFA_CODE <- c(old, "no_such_file.R")
  expect_error(quiet(ANA$run_main(list(RUN = run))),
               "R file the run record must hash is not found: no_such_file.R")
  expect_false(dir.exists(file.path(run, "analysis")))
})

test_that("after_run.json's code_sha256 names every R file the after-run check sources", {
  expect_identical(CHK$NFC_CODE, nf_scan_sources("check_newfor_run.R"))
  # a file that cannot be found stops the check before anything is written
  run <- hand_run(tempfile("newfor-hand-"))
  old <- CHK$NFC_CODE
  on.exit({ CHK$NFC_CODE <- old; unlink(run, recursive = TRUE) })
  CHK$NFC_CODE <- c(old, "no_such_file.R")
  expect_error(CHK$run_main(list(FROZEN = run, RUN = run)),
               "R file the run record must hash is not found: no_such_file.R")
  expect_false(dir.exists(file.path(run, "after_run")))
})
