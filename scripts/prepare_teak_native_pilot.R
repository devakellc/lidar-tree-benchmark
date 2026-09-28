#!/usr/bin/env Rscript
# One declared historical plot, no detector, matching or split selection.
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.code <- file.path(dirname(.self), c(basename(.self), "bootstrap.R", "repo_paths.R",
  "teak_canopy_lib.R", "teak_native_pilot_lib.R", "neon_spatial_lib.R",
  "neon_acquisition_lib.R", "compare_teak_rgb.py"))
.before <- unname(vapply(.code, digest::digest, character(1), file = TRUE, algo = "sha256"))
source(file.path(dirname(.self), "bootstrap.R"))
source(.find("teak_canopy_lib.R")); source(.find("teak_native_pilot_lib.R"))
source(.find("neon_spatial_lib.R")); source(.find("neon_acquisition_lib.R"))
suppressPackageStartupMessages({library(lidR); library(terra); library(sf)})
options(lidR.progress = FALSE, lidR.verbose = FALSE)
a <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(a, function(z) paste(z[-1], collapse = "=")),
              vapply(a, `[`, character(1), 1))
if (!all(c("CACHE", "PUBLISHED", "OUT") %in% names(A)) || anyDuplicated(names(A)) ||
    any(!names(A) %in% c("CACHE", "PUBLISHED", "OUT", "FETCH")) ||
    (!is.null(A$FETCH) && !A$FETCH %in% c("0", "1")))
  stop("Required CACHE=pilot_archive PUBLISHED=canopy_archive OUT=new_directory [FETCH=1]")
cache <- normalizePath(A$CACHE, mustWork = TRUE)
published <- normalizePath(A$PUBLISHED, mustWork = TRUE)
out <- canopy_resolve(path.expand(A$OUT))
protected <- c(cache, published)
if (file.exists(out) || any(out == protected | startsWith(out, paste0(protected, "/"))) ||
    any(startsWith(protected, paste0(out, "/")))) stop("OUT must be fresh and outside inputs")
mp <- file.path(.ROOT, "docs/teak-native-pilot-sources.json")
parent <- file.path(.ROOT, "docs/teak-canopy-sources.json")
manifest_hashes <- canopy_hash(c(mp, parent))
m <- jsonlite::fromJSON(mp)
if (m$parent_manifest_sha256 != manifest_hashes[2] || m$plot != "TEAK_043" ||
    m$context_buffer_m != 25) stop("Pilot declaration or parent identity differs")
canopy_check_paths(m$sources$path); canopy_check_paths(m$published$path)
paths <- c(file.path(cache, m$sources$path), file.path(published, m$published$path))
hashes <- c(m$sources$sha256, m$published$sha256)
sizes <- c(m$sources$bytes, m$published$bytes)
for (i in seq_along(paths)) {
  if (!file.exists(paths[i])) {
    if (!identical(A$FETCH, "1") || i > nrow(m$sources) ||
        m$sources$kind[i] != "neon_file") stop("Missing pinned archive input: ", paths[i])
    row <- m$sources[i, ]
    listing <- neon_released_files(row$product, row$site, row$month, row$release)
    entry <- listing$files[listing$files$name == row$name, ]
    if (nrow(entry) != 1L || as.numeric(entry$size) != sizes[i])
      stop("Declared native file is unavailable or changed")
    part <- paste0(paths[i], ".part")
    if (file.exists(part)) stop("Prior partial download exists: ", basename(part))
    dir.create(dirname(paths[i]), recursive = TRUE, showWarnings = FALSE)
    response <- tryCatch(curl::curl_fetch_disk(entry$url, part,
      curl::new_handle(timeout = 900)), error = function(e)
        stop("Native download failed; access URL withheld"))
    if (response$status_code != 200L || file.info(part)$size != sizes[i] ||
        canopy_hash(part) != hashes[i]) stop("Native download bytes differ")
    if (!file.rename(part, paths[i])) stop("Native download finalization failed")
    rm(listing, entry, response)
  }
  if (file.info(paths[i])$size != sizes[i] || canopy_hash(paths[i]) != hashes[i])
    stop("Pinned input mismatch: ", basename(paths[i]))
}
inventory <- read.csv(file.path(published, "local_plot_inventory.csv"))
selected <- sort(inventory$plotID[inventory$local_derived_evidence &
  inventory$plotID %in% c("TEAK_043", "TEAK_044", "TEAK_045", "TEAK_046",
                        "TEAK_047", "TEAK_050", "TEAK_052")])[1]
if (!identical(selected, m$plot)) stop("Pilot does not satisfy historical-use selection")
native <- function(product) {
  row <- which(m$sources$kind == "neon_file" & m$sources$product == product &
                 grepl("[.](laz|tif)$", m$sources$name))
  if (length(row) != 1L) stop("Ambiguous native spatial source")
  paths[row]
}
pub <- function(modality, suffix) file.path(published, "nte/evaluation", modality,
                                           paste0(m$plot, "_2018", suffix))
rgb <- rast(pub("RGB", ".tif")); nrgb <- rast(native("DP3.30010.001"))
core <- as.vector(ext(rgb)); context <- core + c(-1, 1, -1, 1) * m$context_buffer_m
invisible(neon_assert_crs(rgb, 32611, "Published RGB"))
invisible(neon_assert_crs(nrgb, 32611, "Native RGB"))
hdr <- readLASheader(native("DP1.30003.001"))
invisible(neon_assert_crs(hdr, 32611, "Native LAS"))
if (hdr@PHB[["Version Major"]] != 1L || hdr@PHB[["Version Minor"]] != 3L)
  stop("Pilot expects the declared LAS 1.3 source")
h <- hdr@PHB
if (h[["Min X"]] > context[1] || h[["Max X"]] < context[2] ||
    h[["Min Y"]] > context[3] || h[["Max Y"]] < context[4])
  stop("Native tile header does not cover the complete context footprint")
las <- readLAS(native("DP1.30003.001"), filter = sprintf(
  "-keep_xy %.3f %.3f %.3f %.3f", context[1], context[3], context[2], context[4]))
if (is.null(las) || is.empty(las)) stop("No native pilot points")
p <- as.data.frame(las@data); pilot_return_checks(p)
if (any(!pilot_xy_inside(p, context))) stop("Native reader returned outside points")
las <- pilot_add_rows(las)
p <- as.data.frame(las@data)
density <- rbind(pilot_density(p, core, "image_core"),
                 pilot_density(p, context, "context_25m"))
grid <- pilot_density_grid(p, context)
old <- suppressWarnings(readLAS(pub("LiDAR", ".laz")))
if (is.null(old) || any(unlist(old@header@PHB[c("X scale factor", "Y scale factor")]) != .001) ||
    any(unlist(h[c("X scale factor", "Y scale factor")]) != .001))
  stop("Point comparison requires declared 0.001 m XY precision")
old_points <- as.data.frame(old@data)
crosswalk <- pilot_point_correspondence(old_points, p)
field_discrepancies <- pilot_field_discrepancies(old_points, p, crosswalk)
chm_comparison <- pilot_compare_chm(rast(pub("CHM", "_CHM.tif")),
                                   rast(native("DP3.30015.001")))
if (sum(p$Classification == 2L) < 10L) stop("Insufficient native ground classification")
dtm <- rasterize_terrain(las, res = 1, algorithm = tin(), use_class = 2L)
nrm <- pilot_normalize(las)
pilot_preserved(p, as.data.frame(nrm@data))
dir.create(out, recursive = TRUE)
rgb_json <- file.path(out, "rgb_comparison.json")
status <- system2(Sys.which("python3"), shQuote(c(.find("compare_teak_rgb.py"),
  pub("RGB", ".tif"), native("DP3.30010.001"), rgb_json)))
if (status != 0L) stop("Decoded RGB comparison failed")
rgb_comparison <- jsonlite::fromJSON(rgb_json)
writeLAS(las, file.path(out, "native_context.laz"))
writeLAS(nrm, file.path(out, "normalized_context.laz"))
raw_read <- readLAS(file.path(out, "native_context.laz"))
norm_read <- readLAS(file.path(out, "normalized_context.laz"))
pilot_preserved(p, as.data.frame(raw_read@data), z_tolerance = 0)
pilot_preserved(as.data.frame(nrm@data), as.data.frame(norm_read@data), z_tolerance = .001)
writeRaster(dtm, file.path(out, "ground_dtm.tif"))
writeRaster(crop(nrgb, ext(context)), file.path(out, "native_rgb_context.tif"))
write.csv(density, file.path(out, "density.csv"), row.names = FALSE)
write.csv(grid, file.path(out, "density_grid_10m.csv"), row.names = FALSE)
write.csv(crosswalk, file.path(out, "published_point_correspondence.csv"), row.names = FALSE)
write.csv(field_discrepancies, file.path(out, "published_field_discrepancies.csv"),
          row.names = FALSE)
gps <- do.call(rbind, lapply(sort(unique(p$PointSourceID)), function(id) {
  v <- p$gpstime[p$PointSourceID == id]
  data.frame(PointSourceID = id, points = length(v), gps_min = min(v), gps_max = max(v))
}))
write.csv(gps, file.path(out, "gps_by_source.csv"), row.names = FALSE)
b <- canopy_boxes(file.path(published, "nte/annotations/TEAK_043_2018.xml"), rgb)
boxes <- canopy_project_boxes(b, rgb)
png(file.path(out, "native_rgb_review.png"), width = 1000, height = 1000)
plotRGB(crop(nrgb, ext(context)), axes = TRUE, mar = c(3, 3, 3, 1),
        main = "TEAK_043 native RGB; published image boxes in yellow")
plot(st_geometry(boxes), add = TRUE, border = "yellow")
rect(core[1], core[3], core[2], core[4], border = "white", lwd = 2)
dev.off()
png(file.path(out, "native_height_review.png"), width = 1000, height = 1000)
pal <- hcl.colors(62, "Viridis")
z <- norm_read$Z
plot(norm_read$X, norm_read$Y, pch = 16, cex = .2, asp = 1,
  col = pal[pmax(1, pmin(62, floor(z) + 2))], xlab = "UTM easting (m)",
  ylab = "UTM northing (m)", main = "TIN-normalized returns; colour clipped to -1..60 m")
plot(st_geometry(boxes), add = TRUE, border = "red")
legend("topright", legend = c("0 m", "20 m", "40 m", "60 m"),
       col = pal[c(2, 22, 42, 62)], pch = 16, bg = "white")
dev.off()
ground_z <- z[norm_read$Classification == 2L]
summary <- list(plot = m$plot, role = "historical_development_pilot",
  core_extent = core, context_extent = context, epsg = 32611,
  input_height = "absolute elevation; vertical frame discussed in source report",
  output_height = "TIN height above native class-2 ground; no independent accuracy claim",
  source_point_rows = nrow(p), normalized_point_rows = nrow(norm_read@data),
  point_fields_and_order_preserved = TRUE, invalid_native_returns = 0L,
  n_zero_point_grid_cells = sum(grid$n_points == 0L),
  n_zero_ground_grid_cells = sum(grid$ground_points == 0L),
  normalized_height_range = range(z), ground_abs_z_max = max(abs(ground_z)),
  heights_outside_historical_filter = sum(z < -1 | z >= 80),
  height_filter_applied = FALSE,
  gps_time_type = if (isTRUE(h[["Global Encoding"]][["GPS Time Type"]]))
    "adjusted_standard" else "gps_week",
  rgb_comparison = rgb_comparison, chm_comparison = chm_comparison,
  point_correspondence = as.list(table(crosswalk$status)),
  correspondence_scope = "coordinate tuples only; not verified point identity",
  published_invalid_return_rows = sum(is.na(old_points$ReturnNumber) |
    is.na(old_points$NumberOfReturns) | old_points$ReturnNumber < 1 |
    old_points$ReturnNumber > old_points$NumberOfReturns),
  published_field_discrepancies = field_discrepancies,
  checkpoint_review = jsonlite::fromJSON(file.path(cache, "checkpoint_identity.json")),
  independent_agl_verified = FALSE, acquisition_day_verified = FALSE,
  reference_review_complete = FALSE, evaluation_ready = FALSE, detector_runs = 0L)
jsonlite::write_json(summary, file.path(out, "pilot_summary.json"),
                     pretty = TRUE, auto_unbox = TRUE, digits = NA, na = "null",
                     null = "null")
if (!identical(canopy_hash(paths), hashes) ||
    !identical(canopy_hash(c(mp, parent)), manifest_hashes) ||
    !identical(canopy_hash(.code), .before)) stop("Pilot inputs/code changed during run")
outputs <- sort(list.files(out, recursive = TRUE, full.names = TRUE))
receipt <- list(schema_version = 1, evaluation_ready = FALSE,
  manifest_sha256 = manifest_hashes[1], parent_manifest_sha256 = manifest_hashes[2],
  inputs = data.frame(archive = c(rep("pilot", nrow(m$sources)), rep("published", nrow(m$published))),
    path = c(m$sources$path, m$published$path), sha256 = hashes, bytes = sizes),
  code = data.frame(path = basename(.code), sha256 = .before),
  packages = as.list(vapply(c("lidR", "terra", "sf", "jsonlite", "digest", "xml2"),
    function(x) as.character(packageVersion(x)), character(1))),
  outputs = data.frame(path = substring(outputs, nchar(out) + 2L),
    sha256 = canopy_hash(outputs), bytes = file.info(outputs)$size))
jsonlite::write_json(receipt, file.path(out, "receipt.json"), pretty = TRUE, auto_unbox = TRUE)
cat("Native pilot prepared with", nrow(p), "points; no scoring or evaluation admission.\n")
