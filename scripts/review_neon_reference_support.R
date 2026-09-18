#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_acquisition_lib.R"))
source(.find("neon_reference_support_lib.R"))
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$SUPPORT)) stop("SUPPORT must name the HARV support_bundles.rds file")
out <- if (is.null(A$OUT)) file.path(.job_dir(), "reference_support_rgb_review") else A$OUT
dir.create(out, recursive = TRUE, showWarnings = FALSE)
bundles <- readRDS(A$SUPPORT)
selected <- Filter(function(x) identical(x$plot, "HARV_033") && identical(x$event, "vst_HARV_2022"), bundles)
if (length(selected) != 1L) stop("The predeclared HARV smoke event is missing or ambiguous")
b <- selected[[1]]
name <- "2022_HARV_7_731000_4713000_image.tif"
rgb <- file.path(out, name)
listing_path <- file.path(out, "rgb_file_identities.json")
if (!file.exists(rgb)) {
  listing <- neon_released_files("DP3.30010.001", "HARV", "2022-08")
  neon_archive_listing(listing, listing_path)
  file <- listing$files[listing$files$name == name, ]
  if (nrow(file) != 1L) stop("Declared RGB tile is missing or ambiguous")
  temp <- paste0(rgb, ".part")
  response <- curl::curl_fetch_disk(file$url, temp, curl::new_handle(timeout = 1200))
  if (response$status_code != 200L || file.info(temp)$size != as.numeric(file$size))
    stop("RGB download failed or byte count differs; partial input retained separately")
  if (!file.rename(temp, rgb)) stop("Could not finalize RGB download")
  rm(listing, file, response) # Never persist signed URLs or response headers.
}
listing <- jsonlite::read_json(listing_path, simplifyVector = TRUE)
entry <- listing$files[listing$files$name == name, ]
if (nrow(entry) != 1L || file.info(rgb)$size != as.numeric(entry$size)) stop("RGB identity mismatch")
r <- terra::rast(rgb)
invisible(neon_assert_crs(r, b$epsg, "Review RGB"))
files <- c(A$SUPPORT, rgb, listing_path, .find("review_neon_reference_support.R"))
neon_check_manifest(file.path(out, "input_contract.json"),
  list(plot = b$plot, event = b$event, support_id = neon_support_identity(b),
       files = files, md5 = unname(tools::md5sum(files)), detector_runs = 0L))
bbox <- sf::st_bbox(sf::st_buffer(b$footprint, 15))
r <- terra::crop(r, terra::ext(bbox[c("xmin", "xmax", "ymin", "ymax")]))
grDevices::png(file.path(out, "HARV_033_sampled_support.png"), width = 1100, height = 900)
graphics::par(fig = c(0, 1, 0.12, 1), mar = c(0, 0, 0, 0))
terra::plotRGB(r, axes = FALSE)
plot(b$footprint, add = TRUE, border = "white", col = NA, lwd = 3)
plot(b$core, add = TRUE, border = "cyan", col = NA, lwd = 2)
refs <- b$references
mapped <- refs$target_population & is.finite(refs$E) & is.finite(refs$N)
graphics::points(refs$E[mapped], refs$N[mapped], pch = 21,
  bg = ifelse(refs$reference_selected[mapped], "white", "red"), col = "black", cex = 1)
graphics::par(fig = c(0, 1, 0, 0.12), new = TRUE, mar = c(0, 0, 0, 0))
graphics::plot.new()
graphics::rect(-1, -1, 2, 2, col = "gray25", border = NA)
graphics::legend(0.5, 0.5, c("Measured sampled area", "Uncertainty interior", "Selected reference", "Excluded target record"),
  xjust = 0.5, yjust = 0.5, ncol = 2, bty = "n",
  col = c("white", "cyan", "black", "black"), lty = c(1, 1, NA, NA),
  pch = c(NA, NA, 21, 21), pt.bg = c(NA, NA, "white", "red"), bg = "gray25", text.col = "white")
grDevices::dev.off()
cat("HARV_033 RGB/support overlay written. Visual review is required; no scoring or alignment fitting ran.\n")
