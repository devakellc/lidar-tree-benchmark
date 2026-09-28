#!/usr/bin/env Rscript
# Pinned, diagnostic canopy reference package; never enables evaluation.
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.code <- file.path(dirname(.self), c(basename(.self), "bootstrap.R",
                                    "repo_paths.R", "teak_canopy_lib.R"))
.before <- unname(vapply(.code, digest::digest, character(1), file = TRUE,
                         algo = "sha256"))
source(file.path(dirname(.self), "bootstrap.R"))
source(.find("teak_canopy_lib.R"))
suppressPackageStartupMessages({library(sf); library(terra); library(lidR)})
a <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(a, function(z) paste(z[-1], collapse = "=")),
              vapply(a, `[`, character(1), 1))
if (is.null(A$CACHE) || is.null(A$OUT) ||
    any(!names(A) %in% c("CACHE", "OUT", "FETCH")) ||
    (!is.null(A$FETCH) && !A$FETCH %in% c("0", "1")))
  stop("Usage: CACHE=source_archive OUT=new_directory [FETCH=1]")
cache <- canopy_resolve(path.expand(A$CACHE))
out <- canopy_resolve(path.expand(A$OUT))
if (file.exists(out) || out == cache || startsWith(out, paste0(cache, "/")) ||
    startsWith(cache, paste0(out, "/"))) stop("OUT must be fresh and separate from CACHE")
mp <- file.path(.ROOT, "docs/teak-canopy-sources.json")
mh <- canopy_hash(mp)
m <- jsonlite::fromJSON(mp)
s <- m$sources
canopy_check_paths(s$path)
dir.create(cache, recursive = TRUE, showWarnings = FALSE)
paths <- file.path(cache, s$path)
for (i in seq_along(paths)) {
  if (!file.exists(paths[i])) {
    if (!identical(A$FETCH, "1")) stop("Missing source: ", s$path[i])
    dir.create(dirname(paths[i]), recursive = TRUE, showWarnings = FALSE)
    if (!is.na(s$url[i]) && nzchar(s$url[i])) {
      download.file(s$url[i], paths[i], mode = "wb", quiet = TRUE)
    } else if (!is.na(s$origin[i]) && file.exists(s$origin[i])) {
      if (!file.copy(s$origin[i], paths[i])) stop("Local inventory copy failed")
    } else stop("Pinned local inventory is unavailable")
  }
  if (file.info(paths[i])$size != s$bytes[i] || canopy_hash(paths[i]) != s$sha256[i])
    stop("Source hash/size mismatch: ", s$path[i])
}
tree <- jsonlite::fromJSON(file.path(cache, "nte_tree.json"))
if (isTRUE(tree$truncated) || tree$sha != m$nte_revision) stop("Incomplete/wrong source tree")
ann <- sort(tree$tree$path[grepl("^annotations/TEAK_[0-9]{3}_2018[.]xml$",
                               tree$tree$path)])
if (length(ann) != 18L || any(!paste0("nte/", ann) %in% s$path))
  stop("Pinned named-plot scope is incomplete")
local <- read.csv(file.path(cache, "local_plot_inventory.csv"))
dir.create(out, recursive = TRUE)
dir.create(file.path(out, "previews"))
rows <- boxes <- footprints <- list()
for (i in seq_along(ann)) {
  id <- sub("[.]xml$", "", basename(ann[i])); plot <- sub("_2018$", "", id)
  rgb_path <- file.path(cache, "nte/evaluation/RGB", paste0(id, ".tif"))
  laz_path <- file.path(cache, "nte/evaluation/LiDAR", paste0(id, ".laz"))
  chm_path <- file.path(cache, "nte/evaluation/CHM", paste0(id, "_CHM.tif"))
  needed <- c(rgb_path, laz_path, chm_path)
  if (any(!needed %in% paths)) stop("Unpinned paired source")
  rgb <- rast(rgb_path); chm <- rast(chm_path)
  b <- canopy_boxes(file.path(cache, "nte", ann[i]), rgb)
  b$plotID <- plot; b$image_id <- id; b$annotation_year <- 2018L
  b$local_use <- canopy_local_use(plot, local)
  b$reference_type <- "published_visible_canopy_box"
  b$evaluation_ready <- FALSE
  projected <- canopy_project_boxes(b, rgb)
  warning_log <- character()
  las <- withCallingHandlers(readLAS(laz_path), warning = function(w) {
    warning_log <<- c(warning_log, conditionMessage(w)); invokeRestart("muffleWarning")
  })
  if (is.null(las) || nrow(las@data) == 0) stop("Empty/missing paired LiDAR")
  pts <- as.data.frame(las@data)
  area <- (xmax(rgb) - xmin(rgb)) * (ymax(rgb) - ymin(rgb))
  quality <- canopy_point_quality(pts, area)
  lcrs <- st_crs(las); rcrs <- st_crs(crs(rgb))
  f <- st_as_sfc(st_bbox(c(xmin = xmin(rgb), ymin = ymin(rgb),
    xmax = xmax(rgb), ymax = ymax(rgb)), crs = rcrs))
  footprints[[i]] <- st_sf(plotID = plot, image_id = id,
    evaluation_ready = FALSE, geometry = f)
  rows[[i]] <- cbind(data.frame(plotID = plot, image_id = id,
    local_use = canopy_local_use(plot, local), n_boxes = nrow(b),
    rgb_epsg = rcrs$epsg, rgb_area_m2 = area, rgb_resolution_m = res(rgb)[1],
    chm_matches_rgb = isTRUE(compareGeom(rgb[[1]], chm, lyrs = FALSE,
      res = FALSE, rowcol = FALSE, stopOnError = FALSE)),
    lidar_has_crs = !is.na(lcrs), lidar_matches_rgb_crs = if (is.na(lcrs)) NA else lcrs == rcrs,
    numeric_xy_outside_rgb = sum(pts$X < xmin(rgb) | pts$X > xmax(rgb) |
                                  pts$Y < ymin(rgb) | pts$Y > ymax(rgb)),
    lidar_warnings = paste(unique(warning_log), collapse = " | "),
    upstream_exposure = "unresolved", native_acquisition_verified = FALSE,
    evaluation_ready = FALSE), canopy_raster_pair(rgb, chm), quality)
  boxes[[i]] <- projected
  png(file.path(out, "previews", paste0(id, ".png")), width = 800, height = 800)
  plotRGB(rgb, axes = TRUE, mar = c(2, 2, 3, 1),
          main = paste(id, "published boxes; diagnostic only"))
  plot(st_geometry(projected), add = TRUE, border = "yellow", lwd = 1)
  dev.off()
}
inventory <- do.call(rbind, rows)
bx <- do.call(rbind, boxes)
write.csv(inventory, file.path(out, "paired_plot_inventory.csv"), row.names = FALSE)
write.csv(st_drop_geometry(bx), file.path(out, "pixel_boxes.csv"), row.names = FALSE)
st_write(bx, file.path(out, "canopy_boxes.geojson"), quiet = TRUE)
st_write(do.call(rbind, footprints), file.path(out, "image_footprints.geojson"), quiet = TRUE)
# Secondary source inventory only. Individual-selected species crowns do not
# establish a complete visible-canopy census of any plot.
dta <- st_read(file.path(cache, "neon_crowns_dta.gpkg"), quiet = TRUE)
dta <- st_drop_geometry(dta[dta$siteID == "TEAK", ])
dta$plotID <- canopy_plot_id(dta$plotID)
dta$local_use <- canopy_local_use(dta$plotID, local)
dta$evaluation_ready <- FALSE
write.csv(dta, file.path(out, "dta_teak_inventory.csv"), row.names = FALSE)
review <- inventory[, c("plotID", "image_id", "local_use", "n_boxes")]
review$annotation_review <- "pending"
review$coregistration_review <- "pending"
review$edge_policy <- "undeclared"
review$upstream_exposure_review <- "pending"
review$split <- "unassigned"
review$evaluation_ready <- FALSE
write.csv(review, file.path(out, "review_queue.csv"), row.names = FALSE)
if (!identical(canopy_hash(paths), s$sha256) || canopy_hash(mp) != mh ||
    !identical(canopy_hash(.code), .before)) stop("Sources/code changed during preparation")
outputs <- sort(list.files(out, recursive = TRUE, full.names = TRUE))
receipt <- list(schema_version = 1, evaluation_ready = FALSE,
  nte_revision = m$nte_revision, hf_revision = m$hf_revision,
  source_manifest_sha256 = mh,
  inputs = data.frame(path = s$path, bytes = s$bytes, sha256 = canopy_hash(paths)),
  code = data.frame(path = basename(.code), sha256 = .before),
  packages = as.list(vapply(c("sf", "terra", "lidR", "jsonlite", "digest", "xml2"),
    function(p) as.character(packageVersion(p)), character(1))),
  outputs = data.frame(path = substring(outputs, nchar(out) + 2L),
    bytes = file.info(outputs)$size, sha256 = canopy_hash(outputs)))
jsonlite::write_json(receipt, file.path(out, "receipt.json"), auto_unbox = TRUE,
                     pretty = TRUE, na = "null")
cat("Prepared", nrow(inventory), "plots and", nrow(bx), "published canopy boxes; no admission.\n")
