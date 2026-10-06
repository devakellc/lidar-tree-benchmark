#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
suppressMessages(library(lidR))

# Seeded thinning of the FGI-EMIT development plots to first-return targets
# (docs/fgiemit-thinning-protocol.md). homogenize at 5 m on all returns, as
# the NEON frozen provider decimates; the all-return target is the pulse
# target divided by the plot's share of first returns. Writes, per plot and
# target, the retained source rows (rows.csv) and the measured densities;
# fgiemit_thin_write.py cuts the model input, labels and above-ground cloud
# from them. Development plots only.
#   Rscript scripts/fgiemit_thin_select.R ROOT=<fgiemit root> OUT=<new dir>
#     [TARGETS=9.8,4.7,2.5,1.3,0.6] [PLOTS=...]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
ROOT <- normalizePath(A$ROOT, mustWork = TRUE)
OUT <- normalizePath(A$OUT, mustWork = FALSE)
if (startsWith(OUT, paste0(ROOT, "/"))) stop("OUT must be outside the FGI-EMIT root")
DEV <- c("1001", "1005", "1009", "1013", "1019", "1020", "1022", "1024", "1027", "1031")
PLOTS <- if (is.null(A$PLOTS)) DEV else strsplit(A$PLOTS, ",")[[1]]
if (length(setdiff(PLOTS, DEV))) stop("Only development plots: ", paste(DEV, collapse = ","))
TARGETS <- as.numeric(strsplit(if (is.null(A$TARGETS)) "9.8,4.7,2.5,1.3,0.6" else A$TARGETS, ",")[[1]])
set_lidr_threads(1L)

rows <- list()
for (p in PLOTS) {
  las <- readLAS(file.path(ROOT, "development_inputs", p, "geometry.las"))
  if (is.unsorted(las$source_row)) stop("geometry.las rows are not in source order for plot ", p)
  hull <- grDevices::chull(las$X, las$Y)
  area <- abs(sum(las$X[hull] * c(las$Y[hull][-1], las$Y[hull][1]) -
                  c(las$X[hull][-1], las$X[hull][1]) * las$Y[hull])) / 2
  share <- mean(las$ReturnNumber == 1L)
  native <- data.frame(plot = p, target = NA_real_, label = "native", points = npoints(las),
                       pdens = npoints(las) / area, frdens = sum(las$ReturnNumber == 1L) / area,
                       first_share = share, area_m2 = area)
  rows[[length(rows) + 1]] <- native
  for (t in TARGETS) {
    set.seed(seed_for("FGI-EMIT", p, t))
    dec <- decimate_points(las, homogenize(density = t / share, res = 5))
    lab <- sprintf("pulses_%s", format(t, nsmall = 1))
    dir <- file.path(OUT, p, lab); dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    write.csv(data.frame(source_row = sort(dec$source_row)), file.path(dir, "rows.csv"), row.names = FALSE)
    rows[[length(rows) + 1]] <- data.frame(plot = p, target = t, label = lab, points = npoints(dec),
      pdens = npoints(dec) / area, frdens = sum(dec$ReturnNumber == 1L) / area,
      first_share = share, area_m2 = area)
    cat(sprintf("%s %-12s %7d points, %.2f first returns/m2\n", p, lab, npoints(dec),
                sum(dec$ReturnNumber == 1L) / area))
  }
}
write.csv(do.call(rbind, rows), file.path(OUT, "thinning_densities.csv"), row.names = FALSE)
