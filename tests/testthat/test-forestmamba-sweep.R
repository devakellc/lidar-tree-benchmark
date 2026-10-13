suppressMessages({ library(lidR); library(terra) })
source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "io_bridge.R"), local = TRUE)
source(file.path("..", "..", "scripts", "model_runner.R"), local = TRUE)
source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "detect_forestmamba_sweep.R"), local = TRUE)

# A frozen-clip stand-in at SOAP-like UTM: flat ground at 1100 m and three cone
# crowns, with the DTM the provider writes next to the clip.
fm_synth_prep <- function(dir) {
  set.seed(11); cx <- 299680; cy <- 4101160; gz <- 1100
  cone <- function(tx, ty, h, n = 400) { z <- runif(n, 0, h); r <- (1 - z / h) * 3
    a <- runif(n, 0, 2 * pi)
    data.frame(X = tx + r * cos(a), Y = ty + r * sin(a), Z = gz + z) }
  pts <- rbind(data.frame(X = runif(2000, cx - 15, cx + 15),
                          Y = runif(2000, cy - 15, cy + 15), Z = gz),
               cone(cx - 6, cy - 4, 18), cone(cx + 5, cy + 6, 15), cone(cx, cy, 20))
  pts[] <- lapply(pts, round, 3)
  raw <- file.path(dir, "clip_rawground.laz")
  suppressWarnings(lidR::writeLAS(lidR::LAS(pts), raw))
  dtm <- file.path(dir, "ground_dtm.tif")
  terra::writeRaster(terra::rast(xmin = cx - 40, xmax = cx + 40, ymin = cy - 40,
                                 ymax = cy + 40, resolution = 1, vals = gz), dtm)
  list(prep = list(rawground = raw, dtm = dtm, pdens = 10, frdens = 6),
       cx = cx, cy = cy,
       stems = data.frame(individualID = c("a", "b", "c"), E = cx + c(-6, 5, 0),
                          N = cy + c(-4, 6, 0), height = c(18, 15, 20),
                          crown_class = "dominant", stringsAsFactors = FALSE))
}

# What the container writes: the input rows in order, UserData 0, the instance
# in PointSourceID and the source row in ff3d_row. Instances follow the cones.
fm_fake_export <- function(input, out, scramble = FALSE, config = "cfg.py") {
  las <- suppressWarnings(lidR::readLAS(input))
  n <- nrow(las@data); ids <- integer(n); ids[2001:n] <- rep(1:3, each = 400)
  las@data$UserData <- 0L
  las@data$PointSourceID <- ids
  las@data$ff3d_row <- if (scramble) rev(seq_len(n) - 1L) else seq_len(n) - 1L
  las <- lidR::add_lasattribute(las, las@data$ff3d_row, "ff3d_row", "source row")
  suppressWarnings(lidR::writeLAS(las, out))
  jsonlite::write_json(list(scene = "test_rawground", config = config),
                       paste0(out, ".json"), auto_unbox = TRUE)
  ff3d_collapse(out)
}

test_that("a cell stages a copy, checks the export, persists it and scores apexes", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  s <- fm_synth_prep(d)
  before <- tools::md5sum(s$prep$rawground)
  seen <- NULL
  run <- function(input, out) {
    seen <<- input
    expect_false(identical(normalizePath(input), normalizePath(s$prep$rawground)))
    fm_fake_export(input, out)
  }
  dest <- file.path(d, "inst", "P_native.laz"); dir.create(dirname(dest))
  row <- fm_run_cell(s$prep, s$stems, s$cx, s$cy, 20, dest, run)
  expect_false(file.exists(seen))                       # the staged copy is cleaned up
  expect_identical(tools::md5sum(s$prep$rawground), before)
  expect_true(file.exists(dest) && file.exists(paste0(dest, ".json")))
  rc <- jsonlite::read_json(sub("[.]laz$", ".receipt.json", dest))
  expect_identical(rc$input_sha256, frozen_sha256(s$prep$rawground))
  expect_identical(rc$output_sha256, frozen_sha256(dest))
  expect_equal(rc$n_apex, 3L)
  expect_equal(row$n_apex, 3L)
  expect_equal(c(row$n_ref, row$TP), c(3L, 3L))         # apexes match the three stems
  expect_true(row$seconds >= 0)
})

test_that("a container crash skips the cell; a broken export stops the run", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  s <- fm_synth_prep(d)
  dest <- file.path(d, "P_native.laz")
  expect_null(fm_run_cell(s$prep, s$stems, s$cx, s$cy, 20, dest,
                          function(input, out) NULL))
  expect_false(file.exists(dest))
  expect_error(fm_run_cell(s$prep, s$stems, s$cx, s$cy, 20, dest,
                           function(input, out) fm_fake_export(input, out, scramble = TRUE)),
               "in order")
  expect_false(file.exists(dest))                       # nothing persisted on a breach
})

test_that("a driver that ran another configuration stops the run", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  s <- fm_synth_prep(d)
  dest <- file.path(d, "P_native.laz")
  expect_error(fm_run_cell(s$prep, s$stems, s$cx, s$cy, 20, dest,
                           function(input, out) fm_fake_export(input, out, config = "other.py"),
                           config = "cfg.py"), "configuration")
  expect_false(file.exists(dest))
  row <- fm_run_cell(s$prep, s$stems, s$cx, s$cy, 20, dest,
                     function(input, out) fm_fake_export(input, out), config = "cfg.py")
  expect_equal(row$TP, 3L)
})

test_that("only the checkpoint pinned in the checksum manifest is accepted", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  ck <- file.path(d, "model.pth"); writeLines("weights", ck)
  sha <- digest::digest(file = ck, algo = "sha256")
  man <- file.path(d, "CHECKSUMS.sha256")
  writeLines(c(paste0(strrep("0", 64), "  other.pth"), paste0(sha, "  model.pth")), man)
  expect_identical(fm_checkpoint_pinned(ck, man), sha)
  writeLines("tampered", ck)
  expect_error(fm_checkpoint_pinned(ck, man), "does not match")
  file.copy(ck, file.path(d, "unlisted.pth"))
  expect_error(fm_checkpoint_pinned(file.path(d, "unlisted.pth"), man), "not pinned")
})

test_that("rung arguments keep native first and refuse unknown rungs", {
  expect_identical(fm_parse_rungs("native,8,4,2,1"),
                   list(native = TRUE, rungs = c(8, 4, 2, 1)))
  expect_identical(fm_parse_rungs("4"), list(native = FALSE, rungs = 4))
  expect_error(fm_parse_rungs("native,eight"), "Unknown rung")
})

# Gated live run: a synthetic UTM scene through fm_entry.sh / fm_arm.py in the
# image. Proves the row-indexed export, the strict checkpoint load, the UTM
# restore and the determinism settings; a repeat with the same seed must agree
# closely (the sparse-convolution kernels keep runs from being bit-identical).
# Skips unless FM_REPO and FM_CKPT point at the pinned checkout and checkpoint.
test_that("LIVE (gated): a scene through fm_arm.py is indexed, restored and repeatable", {
  IMG  <- Sys.getenv("FM_IMAGE", "forestmamba-sm120")
  REPO <- Sys.getenv("FM_REPO"); CKPT <- Sys.getenv("FM_CKPT")
  skip_if(REPO == "" || CKPT == "" || !dir.exists(REPO) || !file.exists(CKPT),
          "set FM_REPO + FM_CKPT to run the live ForestMamba smoke")
  skip_if(Sys.which("docker") == "", "docker not on PATH")
  skip_if(tryCatch(system2("docker", c("image", "inspect", IMG),
                           stdout = FALSE, stderr = FALSE) != 0,
                   error = function(e) TRUE), paste("image", IMG, "absent"))
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  s <- fm_synth_prep(d)
  gpu <- normalizePath(file.path("..", "..", "gpu"))
  ws <- file.path(d, "ws")
  expect_equal(system2("rsync", shQuote(c("-a", "--exclude=.git", "--exclude=data",
    "--exclude=work_dirs", paste0(REPO, "/"), paste0(ws, "/")))), 0L)
  run <- function(out) run_docker_arm(IMG, s$prep$rawground, out,
    cmd = c("bash", file.path(gpu, "forestmamba-sm120", "fm_entry.sh")),
    extra = c(container_path(CKPT), normalizePath(ws),
              file.path(gpu, "forestmamba-sm120", "fm_arm.py"), "0"),
    mounts = c(normalizePath(ws), dirname(container_path(CKPT)),
               file.path(gpu, "forestmamba-sm120"), file.path(gpu, "forestformer3d-sm120")),
    reader = ff3d_collapse, gpus = "all", timeout = 1800,
    extra_docker = fm_docker_user())
  a <- file.path(d, "a.laz"); b <- file.path(d, "b.laz")
  expect_false(is.null(run(a)))
  expect_true(ff3d_scene_check(a, s$prep$rawground))
  rc <- jsonlite::read_json(paste0(a, ".json"))
  expect_identical(rc$checkpoint_load, "strict")
  expect_identical(rc$seed, 0L)
  expect_true(rc$deterministic_algorithms)
  expect_identical(rc$pythonhashseed, "0")
  la <- suppressWarnings(lidR::readLAS(a))@data
  expect_equal(rc$instances, length(unique(la$PointSourceID[la$PointSourceID > 0])))
  expect_true(all(la$X > s$cx - 20 & la$X < s$cx + 20))   # UTM restored, not ~0
  expect_false(is.null(run(b)))
  lb <- suppressWarnings(lidR::readLAS(b))@data
  expect_gt(mean((la$PointSourceID > 0) == (lb$PointSourceID > 0)), 0.8)
  left <- list.files(ws, recursive = TRUE, full.names = TRUE)   # written as this user
  expect_true(all(file.access(left, 2) == 0))
})
