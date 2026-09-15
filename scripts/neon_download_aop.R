#!/usr/bin/env Rscript
.bs_ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (!is.null(.bs_ofile) && length(.bs_ofile) && nzchar(.bs_ofile))
    file.path(dirname(.bs_ofile), "bootstrap.R"),
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])),
                                  "bootstrap.R"),
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_ofile, .bs_file)

# #X1: download NEON high-res RGB camera mosaics (DP3.30010.001) for the tiles
# that overlap a site's live field stems, via byTileAOP -- the RGB the DeepForest
# arm (detect_deepforest_sweep.R) runs predict_tile on. Queries are centred on
# plots containing live mapped stems. YEAR defaults to 2021 to match the 2021
# LiDAR/ground-truth epoch the rest of the benchmark uses (RGB exists for SOAP/
# SJER/TEAK at 2021). A manifest binds the download directory to its year/CRS.
#   Rscript scripts/neon_download_aop.R SITE=SOAP YEAR=2021
# Reads work/neon/<SITE>/ground_truth_stems.csv; writes work/neon/<SITE>/rgb/.
suppressMessages(library(neonUtilities))
source(.find("neon_spatial_lib.R"))
args <- strsplit(commandArgs(TRUE), "=")
A    <- setNames(lapply(args, `[`, 2), sapply(args, `[`, 1))
site <- if (is.null(A$SITE)) "SOAP" else A$SITE
year <- neon_year(if (is.null(A$YEAR)) 2021 else A$YEAR)
prov <- isTRUE(as.logical(if (is.null(A$PROVISIONAL)) "FALSE" else A$PROVISIONAL))
d  <- .job_dir(); nd <- file.path(d, "neon", site)
gt <- read.csv(file.path(nd, "ground_truth_stems.csv"))
pc <- read.csv(file.path(nd, "plot_centroids.csv"))
epsg <- neon_validate_inputs(gt, pc)
neon_reference_epoch(gt, year)
lt <- gt[gt$live & gt$is_tree & is.finite(gt$E) & is.finite(gt$N), ]
if (!is.null(A$PLOTS)) lt <- lt[lt$plotID %in% strsplit(A$PLOTS, ",")[[1]], ]
if (!nrow(lt)) stop("No live mapped trees in requested plots")
centres <- pc[pc$plotID %in% lt$plotID, ]
token <- neon_token()
cat(sprintf("[%s] live trees: %d (RGB DP3.30010 %s, provisional=%s)\n",
            site, nrow(lt), year, prov))
savep <- file.path(nd, "rgb"); dir.create(savep, showWarnings = FALSE, recursive = TRUE)
neon_acquisition_manifest(savep, "DP3.30010.001", year, epsg, prov)
options(timeout = 7200)
byTileAOP(dpID = "DP3.30010.001", site = site, year = year,
          easting = centres$easting, northing = centres$northing, buffer = 50,
          check.size = FALSE, savepath = savep, include.provisional = prov, token = token)
tif <- list.files(savep, pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
neon_validate_files(tif, epsg)
cat(sprintf("[%s] downloaded %d RGB tiles -> %s\n", site, length(tif), savep))
