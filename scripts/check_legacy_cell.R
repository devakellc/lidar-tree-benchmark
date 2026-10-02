#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(lidR); library(parallel) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))

# Diagnostic for the frozen-clip acceptance check: draws K realizations of one
# historical CHM-VWF ladder cell through the LEGACY clip path (prepare_clip:
# unseeded decimation of the clip as read, default lidR threads) and pools the
# headline configuration (res 0.5 m, a 0.10) over the all_mapped plots. If the
# legacy draws centre where the frozen seeded draws do, a cached value outside
# the noise band is a tail draw of the old pipeline, not a pipeline difference.
# Reads the LiDAR tiles; writes nothing into the job directory.
#   Rscript scripts/check_legacy_cell.R SITE=SOAP RUNG=4 [K=10] [CORES=16] [OUT=...]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
d <- .job_dir()
SITE  <- if (is.null(A$SITE)) "SOAP" else A$SITE
RUNG  <- as.numeric(if (is.null(A$RUNG)) 4 else A$RUNG)
K     <- as.integer(if (is.null(A$K)) 10 else A$K)
CORES <- as.integer(if (is.null(A$CORES)) 16 else A$CORES)
OUT   <- if (is.null(A$OUT)) file.path(tempdir(), sprintf("legacy_%s_%s.csv", SITE, RUNG)) else A$OUT

nd <- file.path(d, "neon", SITE)
pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
fz <- frozen_scope(d, SITE, list(POP = "all_mapped", FROZEN_ROOT = A$FROZEN_ROOT),
                   read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE))
gt <- fz$gt
laz <- list.files(file.path(nd, "lidar"), pattern = "\\.laz$", recursive = TRUE, full.names = TRUE)
ctg <- neon_read_catalog(laz, gt, pc, file.path(nd, "lidar"))
opt_progress(ctg) <- FALSE

cell <- function(job) {
  set.seed(job$seed)                      # reproducible draw of the unseeded path
  ci <- pc[pc$plotID == job$plot, ][1, ]; ph <- plot_half(ci$plotType)
  prep <- prepare_clip(ctg, ci$easting, ci$northing, RUNG, tempdir(), core_half = ph)
  on.exit(unlink(prep$file))
  stems <- gt[gt$plotID == job$plot & abs(gt$E - ci$easting) <= ph &
                abs(gt$N - ci$northing) <= ph, ]
  det <- detect_lasr(prep$file, 0.5, 0.10, prep$frdens)
  sc <- score_plot(stems, det, tol_xy = 4, core_cx = ci$easting, core_cy = ci$northing,
                   core_half = ph)
  data.frame(draw = job$draw, plot = job$plot, sc[, c("n_ref", "n_det", "TP", "precision")])
}
jobs <- do.call(c, lapply(seq_len(K), function(k) lapply(seq_along(fz$plots), function(i)
  list(draw = k, plot = fz$plots[i], seed = 5000L + 100L * k + i))))
res <- do.call(rbind, plot_lapply(jobs, cell, mc.cores = CORES))
pooled <- do.call(rbind, lapply(split(res, res$draw), function(x) {
  r <- sum(x$TP) / sum(x$n_ref)
  p <- sum(round(x$precision * x$n_det), na.rm = TRUE) / sum(x$n_det)
  data.frame(site = SITE, rung = RUNG, draw = x$draw[1], recall = r, precision = p,
             F1 = 2 * r * p / (r + p))
}))
write.csv(pooled, OUT, row.names = FALSE)
print(pooled, row.names = FALSE, digits = 3)
cat(sprintf("legacy path %s rung %s, %d draws: F1 mean %.3f sd %.3f (range %.3f-%.3f) -> %s\n",
            SITE, RUNG, K, mean(pooled$F1), sd(pooled$F1), min(pooled$F1), max(pooled$F1), OUT))
