#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(lidR); library(data.table) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
source(.find("io_bridge.R"))
source(.find("coverage_lib.R"))           # read_arm_cache
source(.find("census_support_lib.R"))

# Precision inside censused NEON subplots, from persisted detections only.
# For each plot whose support bundle a reviewed declaration admits
# (neon_admit_support), every arm and rung with persisted apexes is scored
# inside the bundle's conservative interior (score_neon_support: recall with
# the matching tolerance around the interior, precision from interior
# detections only), next to the nominal-box score of the same detections
# against the declared population (rect_*). Support identities are kept
# through equal_set_guard and pool(). Nothing is re-inferred; a cell without
# persisted apexes is reported as missing.
#   Rscript scripts/score_census_support.R DECLARATION=<reviewed.json>
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [ARMS=...] [RUNGS=native,8,4,2,1]
#     [YEARS=2019,...,2024] [SUPPORT=$CLAUDE_JOB_DIR/reference_support_v1]
#     [POP=adopted] [FROZEN_ROOT=...] [TOL=4] [OUT=...]
# Writes OUT/census_support_scores.csv (one row per site x plot x rung x arm),
# census_support_pooled.csv (per arm x rung, equal cells) and
# census_support_missing.csv (admitted cells without persisted apexes).
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d <- .job_dir()
if (is.null(A$DECLARATION)) stop("DECLARATION= (a reviewed admission declaration) is required")
declaration <- jsonlite::read_json(A$DECLARATION, simplifyVector = TRUE)
if (grepl("DRAFT", declaration$name)) stop("Refusing a draft declaration; review and rename it first")
SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
ARMS  <- split_arg(A$ARMS, paste(names(FAMILY_MAP)[!FAMILY_MAP %in% "rgb"], collapse = ","))
RUNGS <- split_arg(A$RUNGS, "native,8,4,2,1")
YEARS <- as.integer(split_arg(A$YEARS, paste(2019:2024, collapse = ",")))
SUPPORT <- if (is.null(A$SUPPORT)) file.path(d, "reference_support_v1") else A$SUPPORT
TOL <- as.numeric(if (is.null(A$TOL)) 4 else A$TOL)
OUT <- if (is.null(A$OUT)) file.path(d, "census_support_scores") else A$OUT

rows <- list(); missing <- list()
for (site in SITES) {
  nd <- file.path(d, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  fz <- frozen_scope(d, site, A, gt)
  epsg <- invisible(neon_validate_inputs(fz$gt, pc))
  bundles <- census_admitted_bundles(SUPPORT, site, declaration, YEARS)
  plots <- intersect(names(bundles), fz$plots)
  cat(sprintf("[%s] admitted plots in population %s: %d of %d\n", site, fz$population,
              length(plots), length(fz$plots)))
  for (pid in plots) {
    ci <- pc[pc$plotID == pid, ][1, ]
    ph <- plot_half(ci$plotType)
    stems <- fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - ci$easting) <= ph &
                     abs(fz$gt$N - ci$northing) <= ph, , drop = FALSE]
    for (r in RUNGS) {
      rung <- if (r == "native") NA else as.numeric(r)
      cell <- frozen_clip(NULL, site, pid, rung, ci$easting, ci$northing, ph, fz$root)
      if (is.null(cell)) next                       # upsampled or unusable cell
      for (arm in ARMS) {
        det <- census_cell_detections(nd, arm, site, pid, rung, fz$root, cell)
        if (is.null(det)) {
          missing[[length(missing) + 1]] <- data.frame(site = site, plot = pid, rung = r, detector = arm)
          next
        }
        sc <- census_score_cell(bundles[[pid]], det, epsg, stems, ci$easting, ci$northing, ph, TOL)
        rows[[length(rows) + 1]] <- data.frame(site = site, plot = pid, rung = r, detector = arm,
                                               source = attr(det, "source"), sc)
      }
    }
  }
}
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
miss <- if (length(missing)) do.call(rbind, missing) else
  data.frame(site = character(), plot = character(), rung = character(), detector = character())
write.csv(miss, file.path(OUT, "census_support_missing.csv"), row.names = FALSE)
if (!length(rows)) stop("No admitted cell had persisted detections; see census_support_missing.csv")
scores <- do.call(rbind, rows)
write.csv(scores, file.path(OUT, "census_support_scores.csv"), row.names = FALSE)
arms <- intersect(ARMS, unique(scores$detector))
pooled <- census_pool(scores, arms)
write.csv(pooled, file.path(OUT, "census_support_pooled.csv"), row.names = FALSE)
print(pooled[, c("detector", "rung", "n_plots", "n_ref", "recall", "precision", "F1",
                 "rect_recall", "rect_precision", "rect_F1")], row.names = FALSE, digits = 3)
cat(sprintf("%d scored cells, %d admitted cells without persisted apexes\n",
            nrow(scores), nrow(miss)))
