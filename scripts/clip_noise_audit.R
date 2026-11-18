#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("model_bench_lib.R"))   # frozen_root, frozen_population, frozen_read

# Noise-class points in the frozen NEON evaluation clips. The native 3DEP
# cross-check drops classes 7 (low noise) and 18 (high noise) and withheld
# points from the 3DEP clouds; the NEON clips keep whatever the NEON tiles
# hold. For every clip of the declared population and every frozen rung this
# counts, in the raw clip with ground (clip_rawground.laz, the file the learned
# detectors read), the points of classes 7 and 18, how many of them lie inside
# the plot core, and the withheld-flagged points; and the noise-class points
# left in the height-normalized clip (clip_normalized.laz, Z in [-1, 80) m,
# the file the CHM detectors read), all of them and those at least 2 m above
# ground, the minimum tree-top height of the CHM detectors. Every cell is read through frozen_read,
# which checks its bytes against the clip manifest; nothing is written to the
# frozen root.
#   Rscript scripts/clip_noise_audit.R [POP=adopted] [SITES=ABBY,SJER,...] \
#       [FROZEN_ROOT=<root>]
# Writes $CLAUDE_JOB_DIR/neon/clip_noise_audit.csv (one row per clip) and
# clip_noise_audit_summary.csv (per site and rung).
suppressMessages({ library(lidR); library(data.table) })
lidR::set_lidr_threads(1L)
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
JOB  <- .job_dir()
ROOT <- frozen_root(JOB, A$FROZEN_ROOT)        # default <job>/neon/frozen_2021
if (!frozen_sealed(ROOT)) stop("No sealed frozen root at ", ROOT)
POP <- if (is.null(A$POP)) "adopted" else A$POP
NOISE <- c(7L, 18L)

cm <- frozen_clip_manifest(ROOT)
SITES <- if (is.null(A$SITES)) sort(unique(cm$site)) else strsplit(A$SITES, ",")[[1]]
RUNG_ORDER <- c("native", as.character(frozen_root_rungs(ROOT)))

rows <- list()
for (site in SITES) {
  plots <- frozen_population(ROOT, site, POP)$plotID
  cells <- cm[cm$site == site & cm$plot %in% plots & cm$status == "ok", , drop = FALSE]
  cells <- cells[order(cells$plot, match(cells$rung, RUNG_ORDER)), , drop = FALSE]
  cat(sprintf("%s: %d plots, %d clips\n", site, length(plots), nrow(cells)))
  for (i in seq_len(nrow(cells))) {
    r <- cells[i, ]
    rung <- if (r$rung == "native") NA else as.numeric(r$rung)
    fp <- frozen_read(ROOT, site, r$plot, rung, r$cx, r$cy, r$core_half, r$buffer, manifest = cm)
    raw <- suppressWarnings(readLAS(fp$rawground, select = "xyzcw"))
    nrm <- suppressWarnings(readLAS(fp$normalized, select = "xyzc"))
    cl <- raw$Classification
    noise <- cl %in% NOISE
    core <- abs(raw$X - r$cx) <= r$core_half & abs(raw$Y - r$cy) <= r$core_half
    wh <- if (is.null(raw$Withheld_flag)) logical(length(cl)) else raw$Withheld_flag %in% TRUE
    rows[[length(rows) + 1L]] <- data.table(
      site = site, plot = r$plot, rung = r$rung, core_half = r$core_half,
      n_raw = length(cl), n_class7 = sum(cl == 7L), n_class18 = sum(cl == 18L),
      n_noise = sum(noise), pct_noise = 100 * sum(noise) / length(cl),
      n_core = sum(core), n_noise_core = sum(noise & core),
      n_withheld = sum(wh), n_normalized = npoints(nrm),
      n_noise_normalized = sum(nrm$Classification %in% NOISE),
      n_noise_normalized_2m = sum(nrm$Classification %in% NOISE & nrm$Z >= 2))
  }
}
x <- rbindlist(rows)
s <- x[, .(plots = .N, n_raw = sum(n_raw), n_class7 = sum(n_class7),
           n_class18 = sum(n_class18), n_noise = sum(n_noise),
           pct_noise = 100 * sum(n_noise) / sum(n_raw),
           n_noise_core = sum(n_noise_core), n_withheld = sum(n_withheld),
           n_noise_normalized = sum(n_noise_normalized),
           n_noise_normalized_2m = sum(n_noise_normalized_2m),
           plots_with_noise = sum(n_noise > 0), max_noise_plot = max(n_noise)),
       by = .(site, rung)]
s <- s[order(site, match(rung, RUNG_ORDER))]
out <- file.path(JOB, "neon")
dir.create(out, showWarnings = FALSE, recursive = TRUE)
fwrite(x, file.path(out, "clip_noise_audit.csv"))
fwrite(s, file.path(out, "clip_noise_audit_summary.csv"))
options(width = 200)
print(s, digits = 3)
cat("\nMost noise points (native clips):\n")
print(x[rung == "native"][order(-n_noise)][1:8], digits = 3)
cat("\nWROTE", file.path(out, "clip_noise_audit.csv"), "and clip_noise_audit_summary.csv\n")
