#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
source(.find("neon_acquisition_lib.R"))
options(lidR.progress = FALSE, lidR.verbose = FALSE)

# Inspect only the score-blind selected HARV plot. No detector or calibration call.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
d <- .job_dir()
audit <- if (is.null(A$AUDIT)) file.path(d, "authenticated_preflight") else A$AUDIT
selection_path <- file.path(audit, "smoke_selection.json")
selection <- jsonlite::read_json(selection_path, simplifyVector = TRUE)
coverage_path <- file.path(audit, "plot_coverage_candidates.csv")
if (!identical(selection$site, "HARV") ||
    !identical(selection$coverage_md5, unname(tools::md5sum(coverage_path))))
  stop("Smoke selection or coverage inventory changed")
candidates <- read.csv(coverage_path)
first <- sort(candidates$plot[candidates$site == "HARV" & candidates$coverage_candidate])[1]
if (!identical(selection$plot, first)) stop("Smoke plot does not follow the declared selection rule")
nd <- file.path(d, "neon", "HARV")
gt <- read.csv(file.path(nd, "ground_truth_stems.csv"))
pc <- read.csv(file.path(nd, "plot_centroids.csv"))
ci <- pc[pc$plotID == selection$plot, ]
stopifnot(nrow(ci) == 1L)
half <- plot_half(ci$plotType); reach <- half + BUF
laz <- list.files(file.path(nd, "lidar"), "[.]laz$", recursive = TRUE, full.names = TRUE)
tifs <- list.files(file.path(nd, "rgb"), "[.]tif$", recursive = TRUE, full.names = TRUE)
ctg <- neon_read_catalog(laz, gt, pc, file.path(nd, "lidar"))
epsg <- neon_validate_inputs(gt, pc)
neon_validate_acquisition(file.path(nd, "rgb"), gt, pc, "DP3.30010.001")
neon_validate_files(tifs, epsg)
box <- sf::st_as_sfc(sf::st_bbox(c(xmin = ci$easting - reach, ymin = ci$northing - reach,
                                 xmax = ci$easting + reach, ymax = ci$northing + reach), crs = epsg))
if (!neon_extent_covers(box, sf::st_geometry(ctg@data)))
  stop("LiDAR tile extents do not cover the buffered smoke plot")
rgb <- Filter(function(f) {
  e <- as.vector(terra::ext(terra::rast(f)))
  ci$easting - reach >= e[1] && ci$easting + reach <= e[2] &&
    ci$northing - reach >= e[3] && ci$northing + reach <= e[4]
}, tifs)
if (length(rgb) != 1L) stop("Smoke RGB extent is missing or ambiguous")
out <- if (is.null(A$OUT)) file.path(audit, "smoke", selection$plot) else A$OUT
inputs <- c(selection_path, coverage_path, file.path(nd, c("ground_truth_stems.csv", "plot_centroids.csv")), laz, rgb)
neon_check_manifest(file.path(out, "input_contract.json"),
  list(plot = selection$plot, files = inputs, md5 = unname(tools::md5sum(inputs)),
       code_md5 = unname(tools::md5sum(vapply(c("preflight_harv_smoke.R", "sweep_lib.R",
         "model_bench_lib.R", "neon_acquisition_lib.R", "neon_spatial_lib.R"), .find, character(1))))))
prep <- frozen_clip(ctg, "HARV", selection$plot, NA, ci$easting, ci$northing,
                    half, file.path(out, "frozen"))
if (is.null(prep)) stop("Native smoke clip is unusable")
raw <- lidR::readLAS(prep$rawground)
nrm <- lidR::readLAS(prep$normalized)
area <- (2 * reach)^2
stems <- gt[gt$live & gt$is_tree & gt$meas_year == 2022 & is.finite(gt$height) & gt$height > 0 &
              gt$plotID == selection$plot & abs(gt$E - ci$easting) <= half &
              abs(gt$N - ci$northing) <= half, ]
pdens <- lidR::npoints(nrm) / area
frdens <- sum(nrm$ReturnNumber == 1L) / area
summary <- list(site = "HARV", plot = selection$plot, acquisition_month = selection$month,
  epsg = epsg, n_exact_core = nrow(stems), core_half = half, buffer = BUF, area_m2 = area,
  n_raw = lidR::npoints(raw), n_normalized = lidR::npoints(nrm),
  n_ground = sum(raw$Classification == 2L),
  n_raw_withheld = sum(raw$Withheld_flag), n_normalized_withheld = sum(nrm$Withheld_flag),
  raw_class_counts = as.list(table(raw$Classification)),
  raw_pdens = lidR::npoints(raw) / area, raw_frdens = sum(raw$ReturnNumber == 1L) / area,
  pdens = pdens, frdens = frdens, normalized_height_range = range(nrm$Z),
  raw_gps_time_range = range(raw$gpstime),
  gps_time_type = if (raw@header@PHB[["Global Encoding"]][["GPS Time Type"]]) "adjusted_standard" else "week",
  rgb_resolution = terra::res(terra::rast(rgb[[1]])),
  permitted_rungs = c("native", as.character(c(8, 4, 2, 1)[c(8, 4, 2, 1) < pdens])),
  leaf_on = "requires_visual_review", reference_support_verified = FALSE,
  detector_runs = 0L, split_frozen = FALSE)
jsonlite::write_json(summary, file.path(out, "smoke_summary.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
r <- terra::crop(terra::rast(rgb[[1]]), terra::ext(ci$easting - reach, ci$easting + reach,
                                               ci$northing - reach, ci$northing + reach))
grDevices::png(file.path(out, "rgb_core_review.png"), width = 1000, height = 1000)
terra::plotRGB(r, axes = FALSE)
graphics::rect(ci$easting - half, ci$northing - half, ci$easting + half, ci$northing + half,
               border = "white", lwd = 2)
graphics::points(stems$E, stems$N, pch = 21, bg = "white", col = "black", cex = .7)
grDevices::dev.off()
print(summary)
cat("No detector run. Review RGB/flight evidence and resolve sampled-subplot support\n")
cat("before treating the nominal core as a scoring footprint or freezing a split.\n")
