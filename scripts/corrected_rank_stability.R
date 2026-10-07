#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("master_tables_lib.R"))

# Rank stability in chance-corrected F1. Reads the per-draw corrected F1 that
# paper_sensitivity.R MODE=null writes for the five sites (null_corrected_draws
# .csv and, at 2 m, null_tol2_corrected_draws.csv), from the main job directory
# and, when present, the QL2 rung's, and gives the Spearman correlation between
# the eight ladder arms' corrected F1 at native density and at each rung, with
# the percentile interval over the shared plot resamples (the observed-F1
# version is master_rank_stability.csv).
#   CLAUDE_JOB_DIR=<paper_runs> Rscript scripts/corrected_rank_stability.R
#     [QL2_SENSITIVITY=<dir>] [OUT=<dir>]
# Writes <OUT>/null_corrected_rank.csv; OUT defaults to $CLAUDE_JOB_DIR/sensitivity.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
d <- .job_dir()
SD <- file.path(d, "sensitivity")
QS <- if (is.null(A[["QL2_SENSITIVITY"]])) file.path(dirname(d), "paper_runs_ql2", "sensitivity") else A[["QL2_SENSITIVITY"]]
OUT <- if (is.null(A[["OUT"]])) SD else A[["OUT"]]
LADDER <- c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d", "forestformer3d", "treeisonet", "segmentanytree")
read_both <- function(f) {
  x <- read.csv(file.path(SD, f), stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  q <- file.path(QS, f)
  if (file.exists(q)) x <- rbind(x, read.csv(q, stringsAsFactors = FALSE, colClasses = c(rung = "character")))
  x
}
out <- do.call(rbind, lapply(c("null", "null_tol2"), function(pre) {
  radius <- if (pre == "null") 4 else 2
  dr <- read_both(paste0(pre, "_corrected_draws.csv")); dr <- dr[dr$detector %in% LADDER, ]
  de <- read_both(paste0(pre, "_delta.csv"))
  de <- de[de$scope == "five sites" & de$stratum == "all" & de$metric == "F1_scaled" & de$detector %in% LADDER, ]
  est <- function(r) setNames(de$estimate[de$rung == r], de$detector[de$rung == r])[LADDER]
  nat <- split(dr$value[dr$rung == "native"], dr$draw[dr$rung == "native"])
  do.call(rbind, lapply(setdiff(unique(dr$rung), "native"), function(r) {
    e <- cor(est("native"), est(r), method = "spearman")
    rr <- split(dr$value[dr$rung == r], dr$draw[dr$rung == r])
    rho <- vapply(names(rr), function(k) cor(nat[[k]], rr[[k]], method = "spearman"), numeric(1))
    cbind(data.frame(radius_m = radius, metric = "F1_corrected",
                     from = "native", to = r, arms = length(LADDER), estimate = e), mt_interval(rho))
  }))
}))
rownames(out) <- NULL
write.csv(out, file.path(OUT, "null_corrected_rank.csv"), row.names = FALSE)
print(out, digits = 3)
