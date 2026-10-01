suppressMessages({ library(lidR); library(terra) })
source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "io_bridge.R"), local = TRUE)
source(file.path("..", "..", "scripts", "model_runner.R"), local = TRUE)

# Write a merged labelled LAZ (UTM): UserData = cylinder/block, PointSourceID =
# per-cylinder instance id. Same geometry as synth_block_points().
write_ff3d_laz <- function(path) {
  p <- synth_block_points()
  las <- LAS(data.frame(X = p$X, Y = p$Y, Z = p$Z,
                        UserData = as.integer(p$block),
                        PointSourceID = as.integer(p$inst)))
  lidR::writeLAS(las, path)
}

test_that("ff3d_collapse reads UserData/PointSourceID, dedups across blocks, reduces", {
  f <- tempfile(fileext = ".laz"); write_ff3d_laz(f)
  det <- ff3d_collapse(f, merge_tol = 2.0)
  expect_identical(names(det), c("x", "y", "z"))
  expect_equal(nrow(det), 4L)                          # A, B, merged-C, D
  c_row <- det[abs(det$x - 40) < 1 & abs(det$y - 40) < 1, ]
  expect_equal(nrow(c_row), 1L); expect_equal(c_row$z, 12)
})

test_that("ff3d_collapse returns NULL on an unreadable file (schema failure -> skip)", {
  expect_null(ff3d_collapse(tempfile(fileext = ".laz")))
})

test_that("agl_guard: empty in -> 0-row; partial off-DTM -> AGL; all off-DTM -> NULL", {
  dtm <- tempfile(fileext = ".tif")
  r <- terra::rast(xmin = 0, xmax = 100, ymin = 0, ymax = 100,
                   resolution = 1, vals = 5)            # flat ground at z=5
  terra::writeRaster(r, dtm, overwrite = TRUE)
  # empty in -> empty out (legit ran-but-empty)
  e <- data.frame(x = numeric(), y = numeric(), z = numeric())
  expect_equal(nrow(agl_guard(e, dtm)), 0L)
  # on-DTM apex -> AGL (z - 5)
  on <- data.frame(x = 50, y = 50, z = 25)
  g <- agl_guard(on, dtm); expect_equal(g$z, 20)
  # all apexes off the raster -> wholesale drop -> NULL (skip the cell)
  off <- data.frame(x = c(1e6, 1e6), y = c(1e6, 1e6), z = c(25, 30))
  expect_null(agl_guard(off, dtm))
})

# A whole-scene export as ff3d_arm.py writes it: the input rows in order, one
# block (UserData 0), instance IDs in PointSourceID (0 = background) and the
# source row index in ff3d_row.
write_scene_pair <- function(dir) {
  set.seed(3)
  src <- data.frame(X = round(runif(60, 0, 30), 3), Y = round(runif(60, 0, 30), 3),
                    Z = round(runif(60, 0, 20), 3))
  src$Z[1:20] <- pmin(src$Z[1:20], 17); src$Z[21:40] <- pmin(src$Z[21:40], 11)
  src$Z[c(1, 31)] <- c(18, 12)                       # one apex per instance
  src$Z[41:60] <- 19                                 # taller background rows
  base <- suppressMessages(lidR::LAS(src))
  inp <- file.path(dir, "rawground.laz")
  lidR::writeLAS(base, inp)
  las <- base                                        # lidR registers extra bytes
  las@data$UserData <- 0L                            # reliably only on in-memory LAS
  las@data$PointSourceID <- as.integer(rep(c(1, 2, 0), each = 20))
  las@data$ff3d_row <- 0:59
  las <- lidR::add_lasattribute(las, las@data$ff3d_row, "ff3d_row", "source row")
  out <- file.path(dir, "scene.laz")
  lidR::writeLAS(las, out)
  list(input = inp, output = out, las = las)
}

test_that("ff3d_scene_check accepts an indexed whole-scene export and rejects breaches", {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  x <- write_scene_pair(d)
  expect_true(ff3d_scene_check(x$output, x$input))
  det <- ff3d_collapse(x$output)                     # one block: no cross-block merge
  expect_equal(nrow(det), 2L)
  expect_setequal(det$z, c(18, 12))                  # background rows never form a tree
  bad <- function(edit, msg) {
    las <- edit(x$las); f <- tempfile(fileext = ".laz", tmpdir = d)
    lidR::writeLAS(las, f); expect_error(ff3d_scene_check(f, x$input), msg)
  }
  bad(function(l) { l@data$ff3d_row <- rev(l@data$ff3d_row); l }, "in order")
  bad(function(l) { l@data$UserData[5] <- 1L; l }, "single block")
  bad(function(l) { l@data$Z[7] <- l@data$Z[7] + 0.01; l }, "changed coordinates")
  bad(function(l) l[2:60], "row count")
})

test_that("run provenance pins the source revision, its code changes and file hashes", {
  skip_if(Sys.which("git") == "", "git not on PATH")
  d <- tempfile(); dir.create(file.path(d, "configs"), recursive = TRUE)
  on.exit(unlink(d, recursive = TRUE))
  writeLines("a = 1", file.path(d, "configs", "model.py"))
  git <- function(...) system2("git", c("-C", d, ...), stdout = FALSE, stderr = FALSE)
  git("init", "-q"); git("add", "."); git("-c", "user.email=t@t", "-c", "user.name=t",
                                          "commit", "-q", "-m", "init")
  clean <- git_source_identity(d, "configs")
  expect_match(clean$commit, "^[0-9a-f]{40}$")
  expect_false(clean$modified)
  dir.create(file.path(d, "data")); writeLines("scratch", file.path(d, "data", "list.txt"))
  expect_identical(git_source_identity(d, "configs"), clean)   # run scratch is ignored
  writeLines("a = 2", file.path(d, "configs", "model.py"))     # an applied patch
  patched <- git_source_identity(d, "configs")
  expect_true(patched$modified)
  expect_false(identical(patched$modification_md5, clean$modification_md5))
  expect_error(git_source_identity(file.path(d, "missing")), "source revision")
  h <- file_digests(file.path(d, "configs", "model.py"))
  expect_identical(names(h), "model.py"); expect_match(h[[1]], "^[0-9a-f]{64}$")
  expect_error(file_digests(file.path(d, "none.pth")), "Missing run input")
})

# Spec §6 gated live smoke: push one real cylinder through the container and prove
# the centering-offset round-trip (the "fragile step", §5) — output coords land in
# the input UTM bbox, not centered near 0. Portable + opt-in: skips unless the
# operator points FF3D_REPO/FF3D_CKPT at a checkout and the ff3d-sm120 image exists.
test_that("LIVE (gated): a cylinder through ff3d_arm.py is restored to input UTM", {
  IMG  <- Sys.getenv("FF3D_IMAGE", "ff3d-sm120")
  REPO <- Sys.getenv("FF3D_REPO"); CKPT <- Sys.getenv("FF3D_CKPT")
  skip_if(REPO == "" || CKPT == "" || !dir.exists(REPO) || !file.exists(CKPT),
          "set FF3D_REPO + FF3D_CKPT to run the live FF3D smoke")
  skip_if(Sys.which("docker") == "", "docker not on PATH")
  skip_if(tryCatch(system2("docker", c("image", "inspect", IMG),
                           stdout = FALSE, stderr = FALSE) != 0,
                   error = function(e) TRUE), paste("image", IMG, "absent"))
  gpu <- file.path("..", "..", "gpu", "forestformer3d-sm120")
  ENTRY <- normalizePath(file.path(gpu, "ff3d_entry.sh"))
  DRIVER <- normalizePath(file.path(gpu, "ff3d_arm.py"))
  PATCH  <- normalizePath(file.path(gpu, "ff3d_repo.patch"))
  # synthetic raw-with-ground cloud at SOAP-ish UTM (easting ~3e5, northing ~4.1e6)
  set.seed(7); cx <- 299680; cy <- 4101160; gz <- 1100
  cone <- function(tx, ty, h, n = 500) { z <- runif(n, 0, h); r <- (1 - z / h) * 3
    data.frame(X = tx + r * cos(runif(n, 0, 2 * pi)),
               Y = ty + r * sin(runif(n, 0, 2 * pi)), Z = gz + z) }
  df <- rbind(
    data.frame(X = runif(4000, cx - 16, cx + 16), Y = runif(4000, cy - 16, cy + 16), Z = gz),
    cone(cx - 6, cy - 4, 18), cone(cx + 5, cy + 6, 15), cone(cx, cy, 20))
  ind <- tempfile("ffin"); dir.create(ind)
  suppressWarnings(lidR::writeLAS(lidR::LAS(df), file.path(ind, "cyl_000.laz")))
  outl <- tempfile(fileext = ".laz")
  det <- run_docker_arm(IMG, ind, outl, cmd = c("bash", ENTRY),
                        extra = c(CKPT, REPO, PATCH, DRIVER),
                        mounts = c(REPO, dirname(CKPT), dirname(ENTRY)),
                        reader = function(p) ff3d_collapse(p, merge_tol = 2),
                        gpus = "all", timeout = 1200)
  expect_false(is.null(det))                       # container ran (NULL = crash/missing)
  out <- suppressWarnings(lidR::readLAS(outl))      # read the merged LAZ directly
  expect_gt(nrow(out@data), 0L)
  expect_true("UserData" %in% names(out@data))      # block id carried
  expect_true(all(out@data$X > cx - 20 & out@data$X < cx + 20))  # UTM restored, not ~0
  expect_true(all(out@data$Y > cy - 20 & out@data$Y < cy + 20))
})

test_that("container arguments resolve symlinks like the identity mounts do", {
  d <- tempfile(); dir.create(file.path(d, "store"), recursive = TRUE)
  on.exit(unlink(d, recursive = TRUE))
  writeLines("w", file.path(d, "store", "model.pth"))
  file.symlink(file.path(d, "store"), file.path(d, "linked"))
  via <- file.path(d, "linked", "model.pth")
  expect_identical(container_path(via), normalizePath(file.path(d, "store", "model.pth")))
  expect_identical(dirname(container_path(via)), normalizePath(dirname(via)))
  expect_error(container_path(file.path(d, "missing.pth")))
})

test_that("a resumable run manifest keeps one identity and appends passes", {
  f <- tempfile(fileext = ".json"); on.exit(unlink(f))
  id <- list(image_id = "sha256:abc", source = list(commit = "c1", modified = TRUE),
             checkpoint = list(md5 = "m1"), population = "adopted")
  p1 <- list(rungs = list("native", "8"), code = list(a.R = "h1"))
  update_run_manifest(f, id, p1, resuming = FALSE)
  update_run_manifest(f, id, list(rungs = list("4"), code = list(a.R = "h2")), resuming = TRUE)
  m <- jsonlite::read_json(f)
  expect_length(m$passes, 2L)
  expect_identical(unlist(m$passes[[1]]$rungs), c("native", "8"))
  expect_identical(m$passes[[2]]$code$a.R, "h2")
  expect_error(update_run_manifest(f, modifyList(id, list(checkpoint = list(md5 = "m2"))),
                                   p1, resuming = TRUE), "another model identity")
  expect_error(update_run_manifest(tempfile(), id, p1, resuming = TRUE), "another model identity")
  update_run_manifest(f, id, p1, resuming = FALSE)          # fresh run: new manifest
  expect_length(jsonlite::read_json(f)$passes, 1L)
})
