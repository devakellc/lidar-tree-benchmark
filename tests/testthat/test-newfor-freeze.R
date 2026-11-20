# Unit tests for the NEWFOR download and freeze drivers: the arguments, the
# default fetcher's handle with curl mocked (the generic user agent, no
# request), the download with an injected fetcher (kept, downloaded, retried
# and failed files, the manifest, no partial file under a file's own name),
# and the freeze of a synthetic
# two-area release end to end (files and schemas, the seal and the read-back,
# a second run into the same root refused, AREAS= selecting, a corrupted raw
# file failing rule_files, an unreadable cloud recorded without a clip, and two
# freezes of the same input giving the same manifest bytes). Each script is
# sourced into an environment of its own: sourcing defines its functions
# without running it (guarded by `if (sys.nframe() == 0L) run_main()`), and
# both define run_main. Synthetic data only, no network; nothing here reads
# the release.
FZ <- new.env(); source(file.path("..", "..", "scripts", "freeze_newfor.R"), local = FZ)
DL <- new.env(); source(file.path("..", "..", "scripts", "download_external_newfor.R"), local = DL)
RSCRIPT <- file.path(R.home("bin"), "Rscript")

## ---- download: a fake repository and an injected fetcher ------------------------------------
# Four pinned files on a fake server, by repository id.
dl_server <- function(dir) {
  dir.create(dir, recursive = TRUE)
  fn <- c("01_ALS.laz", "01_AoI.shp", "01_Metadata.pdf", "02_DTM.tif")
  id <- c(161514L, 161518L, 161542L, 161606L)
  for (i in seq_along(fn)) writeBin(as.raw((seq_len(200 * i) * 7L + i) %% 256L),
                                    file.path(dir, fn[i]))
  p <- file.path(dir, fn)
  data.frame(filename = fn, id = id, bytes = as.numeric(file.size(p)),
             md5 = unname(tools::md5sum(p)), sha256 = vapply(p, frozen_sha256, ""),
             stringsAsFactors = FALSE, row.names = NULL)
}
# fetch(url, dest) serving the server's files. `fail`: per id, how many
# attempts write a partial file and then fail; `bad`: ids always served with
# one byte changed (same size). Every call is logged with its URL.
dl_fetcher <- function(server, files, fail = list(), bad = character()) {
  log <- new.env(); log$urls <- character(); log$fail <- fail
  f <- function(url, dest) {
    log$urls <- c(log$urls, url)
    id <- sub(paste0("^https://entrepot\\.recherche\\.data\\.gouv\\.fr/api/access/datafile/",
                     "([0-9]+)\\?format=original$"), "\\1", url)
    src <- file.path(server, files$filename[match(id, as.character(files$id))])
    b <- readBin(src, "raw", file.size(src))
    n <- log$fail[[id]]
    if (!is.null(n) && n > 0) {
      log$fail[[id]] <- n - 1
      writeBin(b[seq_len(length(b) %/% 2)], dest)
      stop("connection reset")
    }
    if (id %in% bad) b[1] <- as.raw((as.integer(b[1]) + 1L) %% 256L)
    writeBin(b, dest)
  }
  list(fetch = f, log = log)
}
dl_same <- function(a, b) unname(tools::md5sum(a)) == unname(tools::md5sum(b))
# newfor_download() with its console output and messages captured: list(value
# (the manifest, or the error), stdout, messages).
dl_run <- function(...) {
  msgs <- character()
  out <- utils::capture.output(value <- tryCatch(withCallingHandlers(
    DL$newfor_download(...),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }),
    error = function(e) e))
  list(value = value, stdout = out, messages = msgs)
}
MAN_CLASSES <- c(filename = "character", id = "integer", bytes = "numeric", md5 = "character",
                 sha256 = "character", status = "character")

test_that("the access URL is the repository's, by file id", {
  expect_identical(DL$newfor_download_url(161514L), paste0(
    "https://entrepot.recherche.data.gouv.fr/api/access/datafile/161514?format=original"))
  expect_identical(DL$newfor_download_url(161514), DL$newfor_download_url(161514L))
  a <- DL$.newfor_dl_args(c("RAW=/data/x=y", "FILES=f.json"))
  expect_identical(a[["RAW"]], "/data/x=y")
  # split at the first "=": a value ending in "=" keeps it
  expect_identical(DL$.newfor_dl_args("RAW=/data/raw=")[["RAW"]], "/data/raw=")
  expect_identical(DL$.newfor_dl_args("RAW=a==")[["RAW"]], "a==")
  expect_identical(DL$.newfor_dl_args(character()), stats::setNames(list(), character()))
  expect_error(DL$.newfor_dl_args("RAW"), "arguments are KEY=VALUE, not RAW")
  expect_error(DL$.newfor_dl_args("FILE=f.json"), "unknown argument FILE=")
  expect_error(DL$.newfor_dl_args("RAW="), "RAW= needs a value")
  expect_error(DL$.newfor_dl_args(c("RAW=a", "RAW=b")), "given twice")
})

test_that("the default fetcher sends only the generic user agent (curl mocked, no request)", {
  seen <- new.env()
  local_mocked_bindings(
    new_handle = function(...) { seen$handle <- list(...); "handle" },
    curl_fetch_disk = function(url, path, handle) {
      seen$url <- url; seen$path <- path; seen$h <- handle
      list(status_code = seen$status)
    }, .package = "curl")
  seen$status <- 200L
  dest <- tempfile()
  expect_identical(DL$newfor_curl_fetch("https://example.invalid/x", dest), dest)
  expect_identical(seen$handle, list(useragent = "research-client", followlocation = TRUE,
                                     connecttimeout = 60, low_speed_limit = 1000,
                                     low_speed_time = 120))
  expect_identical(c(seen$url, seen$path, seen$h), c("https://example.invalid/x", dest, "handle"))
  seen$status <- 404L
  expect_error(DL$newfor_curl_fetch("https://example.invalid/x", dest), "HTTP status 404")
})

test_that("an empty folder is downloaded and verified, then kept as present", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  files <- dl_server(file.path(root, "server"))
  raw <- file.path(root, "release", "raw")
  ff <- dl_fetcher(file.path(root, "server"), files)
  r <- dl_run(raw, files, fetch = ff$fetch, pause = 0)
  man <- file.path(root, "release", "download_manifest.csv")
  expect_true(file.exists(man))
  expect_equal(read.csv(man, colClasses = MAN_CLASSES), transform(files, status = "downloaded"))
  expect_identical(r$value$status, rep("downloaded", 4))
  expect_match(r$stdout, "4 pinned files verified .* \\(0 present, 4 downloaded\\)", all = FALSE)
  expect_length(r$messages, 0L)
  expect_true(all(dl_same(file.path(raw, files$filename),
                          file.path(root, "server", files$filename))))
  expect_identical(sort(list.files(raw, all.files = TRUE, no.. = TRUE)), sort(files$filename))
  expect_identical(ff$log$urls, DL$newfor_download_url(files$id))      # one request per file
  # a second run fetches nothing
  ff2 <- dl_fetcher(file.path(root, "server"), files)
  r2 <- dl_run(raw, files, fetch = ff2$fetch, pause = 0)
  expect_identical(r2$value$status, rep("present", 4))
  expect_length(ff2$log$urls, 0L)
  expect_identical(read.csv(man, colClasses = MAN_CLASSES)$status, rep("present", 4))
})

test_that("a changed or missing file is fetched again; a transient failure is retried", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  files <- dl_server(file.path(root, "server"))
  raw <- file.path(root, "raw")
  dir.create(raw)
  file.copy(file.path(root, "server", files$filename), raw)
  b <- readBin(file.path(raw, "01_AoI.shp"), "raw", 400)               # same size, one byte off
  b[10] <- as.raw((as.integer(b[10]) + 1L) %% 256L)
  writeBin(b, file.path(raw, "01_AoI.shp"))
  unlink(file.path(raw, "02_DTM.tif"))
  # the terrain raster is refused twice, each time after part of it arrived
  ff <- dl_fetcher(file.path(root, "server"), files, fail = list("161606" = 2))
  r <- dl_run(raw, files, fetch = ff$fetch, pause = 0)
  expect_identical(r$value$status, c("present", "downloaded", "present", "downloaded"))
  expect_identical(ff$log$urls, DL$newfor_download_url(c(161518L, 161606L, 161606L, 161606L)))
  expect_identical(r$messages, sprintf("newfor: 02_DTM.tif, attempt %d of 3: %s\n", 1:2,
                                       "fetch failed: connection reset"))
  expect_true(all(dl_same(file.path(raw, files$filename),
                          file.path(root, "server", files$filename))))
  expect_false(any(grepl("\\.part$", list.files(raw, all.files = TRUE))))
})

test_that("a file that never verifies stops the run by name and is never left half written", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  files <- dl_server(file.path(root, "server"))
  raw <- file.path(root, "raw")
  man <- file.path(root, "download_manifest.csv")
  writeLines("stale", man)                                            # an earlier run's manifest
  ff <- dl_fetcher(file.path(root, "server"), files, bad = "161518",
                   fail = list("161542" = 5))
  r <- dl_run(raw, files, fetch = ff$fetch, pause = 0)
  expect_s3_class(r$value, "error")
  expect_match(conditionMessage(r$value),
               paste0("^newfor: 2 of 4 pinned files failed after 3 attempts each \\(no manifest ",
                      "written\\): 01_AoI.shp \\(md5 differ, sha256 differ\\); ",
                      "01_Metadata.pdf \\(fetch failed: connection reset\\)$"))
  expect_identical(sum(ff$log$urls == DL$newfor_download_url(161518L)), 3L)
  expect_identical(sum(ff$log$urls == DL$newfor_download_url(161542L)), 3L)
  expect_length(r$messages, 6L)                                       # every failed attempt
  expect_match(r$messages, "01_AoI.shp, attempt 3 of 3: md5 differ, sha256 differ", all = FALSE)
  expect_false(file.exists(man))
  # the other two are in place and verified; the failed ones are not there under any name
  expect_identical(sort(list.files(raw, all.files = TRUE, no.. = TRUE)),
                   sort(c("01_ALS.laz", "02_DTM.tif")))
  expect_true(all(dl_same(file.path(raw, c("01_ALS.laz", "02_DTM.tif")),
                          file.path(root, "server", c("01_ALS.laz", "02_DTM.tif")))))
  # a fetcher that is not a function is refused before anything is touched
  expect_error(DL$newfor_download(raw, files, fetch = NULL), "fetch must be a function")
})

test_that("the script runs from the command line; without missing files it makes no request", {
  root <- tempfile(); on.exit(unlink(root, recursive = TRUE))
  files <- dl_server(file.path(root, "raw"))
  lst <- file.path(root, "files.json")
  jsonlite::write_json(list(doi = "10.0/x", version = "1.0", n_files = nrow(files), files = files),
                       lst, auto_unbox = TRUE, digits = NA)
  script <- normalizePath(file.path("..", "..", "scripts", "download_external_newfor.R"))
  out <- suppressWarnings(system2(RSCRIPT, c(shQuote(script), shQuote(paste0("RAW=", root, "/raw")),
                                             shQuote(paste0("FILES=", lst))),
                                  stdout = TRUE, stderr = TRUE))
  expect_null(attr(out, "status"), info = paste(out, collapse = "\n"))
  expect_match(out, "4 pinned files verified .* \\(4 present, 0 downloaded\\)", all = FALSE)
  expect_identical(read.csv(file.path(root, "download_manifest.csv"))$status, rep("present", 4))
})

## ---- freeze: a synthetic two-area release ----------------------------------------------------
# Two areas in two projected systems sharing one plot sheet (as areas 15 to 18
# of the release do): a 30 m square (81) and a circle of radius 16 m (82), each
# centred in a 100 m cloud over a sloping terrain raster, so the clip reaches
# 25 m beyond the polygon's box on every side. Seven conical crowns with a stem
# below each apex (DBHRef 0.12 to 0.45 m), one stem of 5 cm inside and one stem
# outside: 9 rows, 8 inside, 7 primary, 8 inventoried.
MINI <- data.frame(id = c("81", "82"), forest = c("Synthetic A", "Synthetic B"),
                   sheet = "81-82_Metadata.pdf", epsg = c(32632L, 2154L),
                   field_date = c("2012-06", "2012-11"), flight_date = c("2012-09", "2012-07"),
                   caliper_cm = c(7.5, 4), stringsAsFactors = FALSE)
MINI_X0 <- c("81" = 600000, "82" = 950000); MINI_Y0 <- c("81" = 5100000, "82" = 6500000)
MINI_TREES <- data.frame(x = c(40, 50, 60, 40, 50, 60, 45), y = c(40, 40, 40, 52, 52, 60, 58),
                         h = c(18, 24, 21, 26, 19, 23, 20))
mini_terrain <- function(x, y) 1000 + 0.3 * x + 0.2 * y               # local coordinates

mini_aoi <- function(id) {
  x0 <- MINI_X0[[id]]; y0 <- MINI_Y0[[id]]
  if (id == "81")
    sf::st_polygon(list(rbind(c(35, 35), c(65, 35), c(65, 65), c(35, 65), c(35, 35)) +
                          matrix(c(x0, y0), 5, 2, byrow = TRUE)))
  else sf::st_buffer(sf::st_point(c(x0 + 50, y0 + 50)), 16, nQuadSegs = 8)
}

mini_las <- function(id) {
  set.seed(as.integer(id))
  g <- expand.grid(x = seq(0, 100, 2), y = seq(0, 100, 2))
  p <- data.frame(x = g$x, y = g$y, hgt = 0.05, rn = 1L, nr = 1L, cls = 2L)
  for (i in seq_len(nrow(MINI_TREES))) {
    t <- MINI_TREES[i, ]
    d <- 2.5 * sqrt(runif(300)); a <- runif(300, 0, 2 * pi)
    d2 <- 2 * sqrt(runif(80)); a2 <- runif(80, 0, 2 * pi)
    p <- rbind(p, data.frame(x = c(t$x + d * cos(a), t$x, t$x + d2 * cos(a2)),
                             y = c(t$y + d * sin(a), t$y, t$y + d2 * sin(a2)),
                             hgt = c(t$h * (1 - 0.6 * d / 2.5) - 0.05, t$h,
                                     runif(80, 2, 0.8 * t$h)),
                             rn = rep(1:2, c(301, 80)), nr = 2L, cls = 1L))
  }
  x <- round(MINI_X0[[id]] + p$x, 3); y <- round(MINI_Y0[[id]] + p$y, 3)
  df <- data.frame(X = x, Y = y, Z = mini_terrain(x - MINI_X0[[id]], y - MINI_Y0[[id]]) + p$hgt,
                   gpstime = as.numeric(seq_len(nrow(p))), ReturnNumber = as.integer(p$rn),
                   NumberOfReturns = as.integer(p$nr), Classification = as.integer(p$cls))
  suppressWarnings(suppressMessages(lidR::LAS(df)))
}

# A shapefile as the release ships them: no .prj (sf writes one for a layer
# without a CRS, which newfor_read_area would take for another CRS).
mini_shp <- function(x, path) {
  sf::st_write(x, path, quiet = TRUE, delete_dsn = file.exists(path))
  unlink(sub("\\.shp$", ".prj", path))
}

# The pinned file list of what is in raw now.
mini_pin <- function(raw, ids = MINI$id) {
  fn <- unique(unlist(lapply(ids, function(id) newfor_area_files(id, MINI$sheet[1]))))
  p <- file.path(raw, fn)
  data.frame(filename = fn, id = 900000L + seq_along(fn), bytes = as.numeric(file.size(p)),
             md5 = unname(tools::md5sum(p)), sha256 = vapply(p, frozen_sha256, ""),
             stringsAsFactors = FALSE, row.names = NULL)
}
mini_write_files <- function(pin, path)
  jsonlite::write_json(list(doi = "10.0/synthetic", version = "1.0", n_files = nrow(pin),
                            files = pin), path, auto_unbox = TRUE, digits = NA)

# The release under <dir>/raw, and META, FILES and PROTOCOL under <dir>/docs.
mini_release <- function(dir) {
  raw <- file.path(dir, "raw"); docs <- file.path(dir, "docs")
  dir.create(raw, recursive = TRUE); dir.create(docs)
  for (id in MINI$id) {
    x0 <- MINI_X0[[id]]; y0 <- MINI_Y0[[id]]
    lidR::writeLAS(mini_las(id), file.path(raw, paste0(id, "_ALS.laz")))
    r <- terra::rast(xmin = x0 - 10, xmax = x0 + 110, ymin = y0 - 10, ymax = y0 + 110,
                     resolution = 1, crs = "")
    xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
    terra::values(r) <- mini_terrain(xy[, 1] - x0, xy[, 2] - y0)
    terra::writeRaster(r, file.path(raw, paste0(id, "_DTM.tif")))
    mini_shp(sf::st_sf(id = 1L, geometry = sf::st_sfc(mini_aoi(id))),
             file.path(raw, paste0(id, "_AoI.shp")))
    E <- x0 + c(MINI_TREES$x, 55, 80); N <- y0 + c(MINI_TREES$y, 46, 80)
    mini_shp(sf::st_sf(DBHRef = c(0.31, 0.42, 0.36, 0.45, 0.12, 0.40, 0.33, 0.05, 0.25),
                       HRef = c(MINI_TREES$h, 6, 15), VolRef = 1,
                       geometry = sf::st_sfc(lapply(seq_along(E), function(i)
                         sf::st_point(c(E[i], N[i]))))),
             file.path(raw, paste0(id, "_Ref.shp")))
  }
  writeLines("plot sheet of areas 81 and 82", file.path(raw, MINI$sheet[1]))
  meta <- file.path(docs, "meta.json"); files <- file.path(docs, "files.json")
  protocol <- file.path(docs, "protocol.md")
  jsonlite::write_json(list(release = list(doi = "10.0/synthetic", version = "1.0"),
                            areas = MINI), meta, auto_unbox = TRUE, digits = NA)
  mini_write_files(mini_pin(raw), files)
  writeLines("# Synthetic protocol", protocol)
  list(raw = raw, meta = meta, files = files, protocol = protocol)
}

# A freeze of `rel` into out; returns its console output.
mini_freeze <- function(rel, out, areas = NULL)
  suppressMessages(utils::capture.output(
    FZ$newfor_freeze(rel$raw, out, rel$meta, rel$files, rel$protocol, areas)))
ADM_COLS <- c("area", "forest", "n_rows", "n_inside", "n_outside", "n_primary", "n_inventoried",
              "n_missing_dbh", "n_below_caliper", "gap_months", "reach_min", "terrain_na_share",
              "offset", "rule_files", "rule_returns", "rule_terrain", "rule_buffer",
              "rule_heights", "rule_gap", "rule_stems", "rule_registration", "admitted", "failed")
LATTICE <- seq(-8, 8, 0.5)

test_that("the freeze runs end to end: files, schemas, the seal and the read-back", {
  dir <- tempfile(); on.exit(unlink(dir, recursive = TRUE))
  rel <- mini_release(dir)
  out <- file.path(dir, "frozen")
  threads <- lidR::get_lidr_threads()
  console <- mini_freeze(rel, out)
  expect_identical(lidR::get_lidr_threads(), threads)                 # restored
  expect_match(console, "^newfor: 17 of 17 raw files verify", all = FALSE)
  expect_match(console, "2 of 2 area\\(s\\) admitted; root .* sealed", all = FALSE)
  expect_match(console, "frdens_clip", all = FALSE)                  # the density table
  expect_identical(sort(list.files(out), method = "radix"),
                   c("81", "82", "admission.csv", "freeze.json", "freeze_manifest.csv",
                     "registration_scan.csv"))
  for (id in MINI$id)
    expect_identical(sort(list.files(file.path(out, id)), method = "radix"),
                     c("aoi.wkt", "cell.json", "normalized.laz", "reference_stems.csv"))
  # the seal covers every other file, and every area reads back verified
  expect_true(newfor_sealed(out))
  m <- read.csv(file.path(out, "freeze_manifest.csv"), stringsAsFactors = FALSE)
  expect_identical(m$file, sort(setdiff(list.files(out, recursive = TRUE), "freeze_manifest.csv"),
                                method = "radix"))
  for (id in MINI$id) {
    fa <- newfor_frozen_area(out, id)
    expect_identical(fa$epsg, MINI$epsg[MINI$id == id])
    expect_identical(sum(fa$stems$primary), 7L)
  }
  # admission.csv: one row per area in id order, the library's columns, both admitted
  a <- newfor_frozen_admission(out)
  expect_identical(names(a), ADM_COLS)
  expect_identical(a$area, c("81", "82"))
  expect_identical(a$forest, MINI$forest)
  expect_identical(a$failed, c("", ""))
  expect_true(all(a$admitted))
  expect_identical(a$n_rows, c(9L, 9L)); expect_identical(a$n_inside, c(8L, 8L))
  expect_identical(a$n_primary, c(7L, 7L)); expect_identical(a$n_inventoried, c(8L, 8L))
  expect_identical(a$gap_months, c(3L, -4L))
  expect_equal(a$reach_min, c(25, 25))
  # registration_scan.csv: the whole lattice of each area, as frozen
  s <- read.csv(file.path(out, "registration_scan.csv"), colClasses = c(area = "character"))
  expect_identical(names(s), c("area", "dx", "dy", "stat"))
  expect_identical(s$area, rep(MINI$id, each = length(LATTICE)^2))
  expect_identical(s$dx, rep(rep(LATTICE, each = length(LATTICE)), 2))
  expect_identical(s$dy, rep(LATTICE, 2 * length(LATTICE)))
  expect_true(all(is.finite(s$stat)))
  for (id in MINI$id) {
    reg <- newfor_frozen_area(out, id)$cell$registration
    expect_equal(s$stat[s$area == id & s$dx == reg$dx & s$dy == reg$dy], reg$stat_best)
    expect_equal(a$offset[a$area == id], reg$offset)
  }
  # freeze.json: the run record
  j <- jsonlite::read_json(file.path(out, "freeze.json"), simplifyVector = TRUE)
  # no git commit: the root's identity depends on the inputs, the code and the versions only
  expect_identical(names(j), c("release", "meta_sha256", "files_sha256", "protocol_sha256",
                               "code_sha256", "versions", "lidr_threads", "constants", "areas",
                               "areas_frozen", "areas_not_frozen", "n_admitted"))
  expect_identical(j$release, list(doi = "10.0/synthetic", version = "1.0"))
  expect_identical(c(j$meta_sha256, j$files_sha256, j$protocol_sha256),
                   unname(vapply(c(rel$meta, rel$files, rel$protocol), frozen_sha256, "")))
  # code_sha256: every R file the freeze sources, in .FREEZE_CODE order, hashed
  expect_identical(unlist(j$code_sha256),
                   vapply(FZ$.FREEZE_CODE, function(f)
                     frozen_sha256(file.path("..", "..", "scripts", f)), ""))
  expect_false(any(grepl("git", readLines(file.path(out, "freeze.json")), fixed = TRUE)))
  expect_identical(j$versions$lidR, as.character(packageVersion("lidR")))
  expect_identical(names(j$versions), c("R", "lidR", "terra", "sf", "GEOS", "GDAL", "PROJ"))
  expect_identical(j$lidr_threads, 1L)
  const <- ls(environment(newfor_freeze_area), pattern = "^NEWFOR_")
  expect_setequal(names(j$constants), const)
  expect_true("NEWFOR_MAX_OFFSET" %in% names(j$constants))
  for (k in const) expect_equal(j$constants[[k]], get(k), info = k)
  expect_identical(j$areas, MINI$id); expect_identical(j$areas_frozen, MINI$id)
  expect_length(j$areas_not_frozen, 0L)
  expect_identical(j$n_admitted, 2L)
  # no time and no path inside the sealed files
  txt <- readLines(file.path(out, "freeze.json"))
  expect_false(any(grepl(dir, txt, fixed = TRUE)))
  expect_false(any(grepl(format(Sys.Date(), "%Y-%m-%d"), txt, fixed = TRUE)))
  # a second run into the same root is refused, and so is any folder holding something
  expect_error(mini_freeze(rel, out), "OUT already holds something")
  busy <- file.path(dir, "busy"); dir.create(busy); writeLines("x", file.path(busy, "note.txt"))
  expect_error(mini_freeze(rel, busy), "OUT already holds something")
  expect_false(newfor_sealed(busy))
})

test_that("two freezes of the same input give the same manifest bytes; an empty OUT is accepted", {
  dir <- tempfile(); on.exit(unlink(dir, recursive = TRUE))
  rel <- mini_release(dir)
  r1 <- file.path(dir, "r1"); r2 <- file.path(dir, "r2")
  dir.create(r2)                                                      # exists, empty
  mini_freeze(rel, r1); mini_freeze(rel, r2)
  m1 <- file.path(r1, "freeze_manifest.csv"); m2 <- file.path(r2, "freeze_manifest.csv")
  expect_identical(readBin(m1, "raw", file.size(m1)), readBin(m2, "raw", file.size(m2)))
  expect_identical(newfor_root_id(r1), newfor_root_id(r2))
})

test_that("a corrupted plot sheet fails rule_files; both areas are still frozen", {
  dir <- tempfile(); on.exit(unlink(dir, recursive = TRUE))
  rel <- mini_release(dir)
  writeLines("another sheet", file.path(rel$raw, MINI$sheet[1]))
  out <- file.path(dir, "frozen")
  console <- mini_freeze(rel, out)
  expect_match(console, "16 of 17 raw files verify .*; failing: 81-82_Metadata.pdf", all = FALSE)
  a <- newfor_frozen_admission(out)
  expect_identical(a$rule_files, c(FALSE, FALSE))
  expect_identical(a$failed, c("rule_files", "rule_files"))
  expect_true(all(a$rule_registration & a$rule_stems & a$rule_buffer))
  for (id in MINI$id) {
    cell <- newfor_frozen_area(out, id)$cell
    expect_identical(cell$raw_sha256[[MINI$sheet[1]]],
                     frozen_sha256(file.path(rel$raw, MINI$sheet[1])))
  }
})

test_that("a missing cloud is recorded without a clip; an area whose files verify stops", {
  dir <- tempfile(); on.exit(unlink(dir, recursive = TRUE))
  rel <- mini_release(dir)
  unlink(file.path(rel$raw, "82_ALS.laz"))                           # an incomplete download
  out <- file.path(dir, "frozen")
  console <- mini_freeze(rel, out)
  expect_match(console, "16 of 17 raw files verify .*; failing: 82_ALS.laz", all = FALSE)
  expect_match(console, "area 82 not frozen \\(its raw files fail\\)", all = FALSE)
  expect_true(newfor_sealed(out))
  expect_false(dir.exists(file.path(out, "82")))
  a <- newfor_frozen_admission(out)
  expect_identical(a$area, c("81", "82"))
  b <- a[a$area == "82", ]
  expect_false(b$admitted)
  expect_identical(b$failed, "rule_files;rule_returns;rule_terrain;rule_buffer;rule_registration")
  # the shapefiles were read: the reference counts are given, the clip's values are not
  expect_identical(c(b$n_rows, b$n_inside, b$n_primary), c(9L, 8L, 7L))
  expect_true(is.na(b$reach_min) && is.na(b$terrain_na_share) && is.na(b$offset))
  expect_true(a$admitted[a$area == "81"])
  s <- read.csv(file.path(out, "registration_scan.csv"), colClasses = c(area = "character"))
  expect_identical(unique(s$area), "81")
  j <- jsonlite::read_json(file.path(out, "freeze.json"), simplifyVector = TRUE)
  expect_identical(j$areas, MINI$id)
  expect_identical(j$areas_frozen, "81")                             # an array of one
  expect_match(readLines(file.path(out, "freeze.json")), '"areas_frozen": \\["81"\\]',
               all = FALSE)
  expect_identical(j$areas_not_frozen$area, "82")
  expect_true(nzchar(j$areas_not_frozen$error))
  expect_false(grepl(rel$raw, j$areas_not_frozen$error, fixed = TRUE))
  expect_identical(j$n_admitted, 1L)
  expect_error(newfor_frozen_area(out, "82"), "not in the root's manifest")
  # an unreadable terrain raster pinned as it is: the area's files verify, so the run stops
  # unsealed instead of recording the area
  rel2 <- mini_release(file.path(dir, "second"))
  writeBin(as.raw(seq_len(4000) %% 251L), file.path(rel2$raw, "82_DTM.tif"))
  mini_write_files(mini_pin(rel2$raw), rel2$files)
  out2 <- file.path(dir, "frozen2")
  expect_error(suppressWarnings(mini_freeze(rel2, out2)),
               "area 82, whose raw files verify, could not be frozen: .*left for inspection")
  expect_false(newfor_sealed(out2))
  expect_false(dir.exists(file.path(out2, "82")))
})

test_that("inputs are checked: AREAS= names known areas, META and FILES one release", {
  dir <- tempfile(); on.exit(unlink(dir, recursive = TRUE))
  rel <- mini_release(dir)
  expect_error(mini_freeze(rel, file.path(dir, "a"), areas = c("82", "83")),
               "unknown: 83; known: 81,82")
  expect_error(mini_freeze(rel, file.path(dir, "b"), areas = c("82", "82")), "distinct areas")
  bad <- rel; bad$protocol <- file.path(dir, "none.md")
  expect_error(mini_freeze(bad, file.path(dir, "c")), "input not found: .*none.md")
  bad <- rel; bad$files <- file.path(dir, "other.json")
  pin <- jsonlite::read_json(rel$files, simplifyVector = TRUE)
  pin$version <- "2.0"
  jsonlite::write_json(pin, bad$files, auto_unbox = TRUE, digits = NA)
  expect_error(mini_freeze(bad, file.path(dir, "d")), "gives version 2.0, .* gives 1.0")
  expect_false(any(file.exists(file.path(dir, c("a", "b", "c", "d")))))
  # the arguments
  x <- FZ$.freeze_inputs(FZ$.freeze_args(c("RAW=r", "OUT=o", "AREAS=01, 02", "META=m",
                                            "FILES=f", "PROTOCOL=p")))
  expect_identical(x, list(raw = "r", out = "o", areas = c("01", "02"), meta = "m", files = "f",
                           protocol = "p"))
  expect_null(FZ$.freeze_inputs(FZ$.freeze_args(c("RAW=r", "OUT=o", "AREAS=ALL")))$areas)
  # split at the first "=": the rest of the value is kept verbatim, a final "=" included
  expect_identical(FZ$.freeze_args(c("OUT=/data/root=", "RAW=/a=b/raw"))[c("OUT", "RAW")],
                   list(OUT = "/data/root=", RAW = "/a=b/raw"))
  expect_error(FZ$.freeze_args("OUT"), "arguments are KEY=VALUE, not OUT")
  expect_error(FZ$.freeze_args("AREA=01"), "unknown argument AREA=")
  expect_error(FZ$.freeze_args("OUT="), "OUT= needs a value")
  expect_error(FZ$.freeze_args(c("OUT=a", "OUT=b")), "given twice")
})

test_that("the script freezes from the command line, AREAS= selecting, and refuses a used root", {
  dir <- tempfile(); on.exit(unlink(dir, recursive = TRUE))
  rel <- mini_release(dir)
  out <- file.path(dir, "frozen")
  script <- normalizePath(file.path("..", "..", "scripts", "freeze_newfor.R"))
  run <- function() suppressWarnings(system2(RSCRIPT,
    c(shQuote(script), shQuote(paste0("RAW=", rel$raw)), shQuote(paste0("OUT=", out)), "AREAS=82",
      shQuote(paste0("META=", rel$meta)), shQuote(paste0("FILES=", rel$files)),
      shQuote(paste0("PROTOCOL=", rel$protocol))),
    stdout = TRUE, stderr = TRUE, env = paste0("CLAUDE_JOB_DIR=", file.path(dir, "job"))))
  first <- run()
  expect_null(attr(first, "status"), info = paste(first, collapse = "\n"))
  expect_match(first, "1 of 1 area\\(s\\) admitted", all = FALSE)
  expect_true(newfor_sealed(out))
  expect_identical(sort(list.files(out), method = "radix"),
                   c("82", "admission.csv", "freeze.json", "freeze_manifest.csv",
                     "registration_scan.csv"))
  expect_identical(newfor_frozen_admission(out)$area, "82")
  j <- jsonlite::read_json(file.path(out, "freeze.json"), simplifyVector = TRUE)
  expect_identical(j$areas, "82")
  expect_match(readLines(file.path(out, "freeze.json")), '"areas": \\["82"\\]', all = FALSE)
  expect_false(dir.exists(file.path(dir, "job")))                     # no default was needed
  second <- run()
  expect_identical(attr(second, "status"), 1L)
  expect_match(second, "OUT already holds something", all = FALSE)
})
