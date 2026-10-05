#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_acquisition_lib.R"))
source(.find("site_extension_lib.R"))

# Acquires one earlier NEON LiDAR epoch over the D17 plots, for the native
# sparse validation. Run it in a job directory of its own, after
# neon_ground_truth.R YEAR=<year> has built that epoch's reference there. For
# each site it archives the released file list (identities only, never the
# signed URLs), lists the 1 km tiles that every clip needs (nominal core plus
# 25 m) for the plots with live mapped stems in this epoch's reference and in
# the declared 2021 population, writes the acquisition manifest, downloads the
# missing tiles and verifies each against the listed size and CRC32C or MD5.
#   Rscript scripts/prepare_sparse_epoch.R MONTHS=SOAP:2018-06,TEAK:2018-06 \
#     [RELEASE=RELEASE-2026] [POPULATION=<2021 frozen root>/population.csv] [DOWNLOAD=TRUE]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$MONTHS)) stop("MONTHS=SITE:YYYY-MM[,...] is required")
months <- do.call(rbind, lapply(strsplit(strsplit(A$MONTHS, ",")[[1]], ":"), function(x)
  data.frame(site = x[1], month = x[2], stringsAsFactors = FALSE)))
release <- if (is.null(A$RELEASE)) "RELEASE-2026" else A$RELEASE
download <- isTRUE(as.logical(if (is.null(A$DOWNLOAD)) "TRUE" else A$DOWNLOAD))
product <- "DP1.30003.001"
d <- .job_dir()
pop21 <- read.csv(if (is.null(A$POPULATION))
  file.path(dirname(d), "neon", "frozen_2021", "population.csv") else A$POPULATION,
  stringsAsFactors = FALSE)

rows <- list()
for (i in seq_len(nrow(months))) {
  site <- months$site[i]; month <- months$month[i]
  nd <- file.path(d, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  year <- neon_year(substr(month, 1, 4))
  neon_reference_epoch(gt, year)
  epsg <- neon_validate_inputs(ext_live_trees(gt), pc)

  # Clips of this epoch's plots and of the 2021 population; centroids can move
  # slightly between census years, so both geometries are covered.
  live <- unique(ext_live_trees(gt)$plotID)
  here <- pc[pc$plotID %in% live, ]
  there <- pop21[pop21$site == site, ]
  boxes <- rbind(data.frame(x = here$easting, y = here$northing, h = ext_core_half(here$plotType)),
                 data.frame(x = there$easting, y = there$northing, h = there$core_half))
  needed <- sort(unique(unlist(lapply(seq_len(nrow(boxes)), function(j)
    neon_required_tiles(boxes$x[j], boxes$y[j], boxes$h[j] + EXT_CLIP_BUF)))))

  path <- file.path(nd, "lidar_files.json")
  fresh <- NULL
  if (!file.exists(path)) {
    fresh <- neon_released_files(product, site, month, release)
    neon_archive_listing(fresh, path)
  }
  snap <- jsonlite::read_json(path, simplifyVector = TRUE)
  if (!identical(snap$month, month) || !identical(snap$release, release))
    stop("Cached file list does not match the declared acquisition")
  tiles <- neon_tile_index(snap$files, product)
  missing_listed <- setdiff(needed, tiles$key)
  if (length(missing_listed)) stop(site, " ", month, " lists no tile for ", paste(missing_listed, collapse = ","))

  savep <- file.path(nd, "lidar")
  dir.create(savep, recursive = TRUE, showWarnings = FALSE)
  neon_acquisition_manifest(savep, product, year, epsg)
  want <- tiles[tiles$key %in% needed, ]
  for (j in seq_len(nrow(want))) {
    dest <- file.path(savep, want$name[j])
    if (ext_file_matches(dest, want[j, ]) || !download) next
    if (is.null(fresh)) fresh <- neon_released_files(product, site, month, release)
    url <- fresh$files$url[fresh$files$name == want$name[j]]
    options(timeout = 3600)
    utils::download.file(url, dest, mode = "wb", quiet = TRUE)
    rm(url)
    if (!ext_file_matches(dest, want[j, ])) stop("Checksum differs: ", want$name[j])
  }
  laz <- list.files(savep, "[.]laz$", full.names = TRUE)
  au <- ext_download_audit(laz, tiles, needed)
  write.csv(au$files, file.path(nd, "downloaded_tiles.csv"), row.names = FALSE)
  if (length(au$missing)) stop(site, " lacks verified tiles: ", paste(au$missing, collapse = ","))
  neon_validate_files(laz, epsg)
  rows[[site]] <- data.frame(site = site, month = month, release = release,
    listed_tiles = nrow(tiles), needed_tiles = length(needed),
    verified = sum(au$files$verified), needed_gb = round(sum(as.numeric(want$size)) / 1e9, 2))
}
print(do.call(rbind, rows), row.names = FALSE)
