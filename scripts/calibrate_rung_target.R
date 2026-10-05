#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))

# Measured density of candidate all-return rung targets, before a rung is
# frozen. Each sealed native clip of the population is decimated as the frozen
# provider would decimate it (same seed per site, plot and target; homogenize
# at 5 m; TIN normalization; the same height filter and clip area), and its
# all-return and first-return densities are measured. Reads the sealed root
# only; writes nothing to it.
#   Rscript scripts/calibrate_rung_target.R TARGETS=3.0,3.2,3.4 [POP=adopted]
#     [FROZEN_ROOT=...] [CORES=6] [OUT=<csv>]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$TARGETS)) stop("TARGETS= is required")
TARGETS <- as.numeric(strsplit(A$TARGETS, ",")[[1]])
POP   <- if (is.null(A$POP)) "adopted" else A$POP
ROOT  <- frozen_root(.job_dir(), A$FROZEN_ROOT)
CORES <- as.integer(if (is.null(A$CORES)) 6 else A$CORES)
if (!frozen_sealed(ROOT)) stop("No sealed frozen root at ", ROOT)
suppressMessages(library(lidR))

pop <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
pop <- pop[pop[[paste0("in_", POP)]], , drop = FALSE]
measure <- function(i) {
  s <- pop$site[i]; p <- pop$plotID[i]
  dir <- file.path(ROOT, s, p, "native")
  if (!file.exists(file.path(dir, "clip_rawground.laz"))) return(NULL)
  mf <- jsonlite::read_json(file.path(dir, "manifest.json"))
  area <- (2 * (mf$core_half + mf$buffer))^2
  las0 <- readLAS(file.path(dir, "clip_rawground.laz"))
  do.call(rbind, lapply(TARGETS, function(t) {
    if (t >= mf$pdens) return(NULL)                         # would upsample
    set.seed(seed_for(s, p, t))
    las <- decimate_points(las0, homogenize(density = t, res = 5))
    nrm <- filter_poi(normalize_height(las, tin(), na.rm = TRUE), Z >= -1, Z < 80)
    data.frame(site = s, plot = p, target = t, pdens = npoints(nrm) / area,
               frdens = sum(nrm$ReturnNumber == 1L) / area)
  }))
}
x <- do.call(rbind, plot_lapply(seq_len(nrow(pop)), measure, mc.cores = CORES))
if (!is.null(A$OUT)) write.csv(x, A$OUT, row.names = FALSE)
summ <- do.call(rbind, lapply(split(x, x$target), function(y) data.frame(
  target = y$target[1], cells = nrow(y), points_median = median(y$pdens),
  pulses_median = median(y$frdens), pulses_min = min(y$frdens), pulses_max = max(y$frdens))))
print(summ, row.names = FALSE, digits = 3)
