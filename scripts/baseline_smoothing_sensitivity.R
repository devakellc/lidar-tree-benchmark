#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("sweep_lib.R")); source(.find("model_bench_lib.R")); source(.find("master_tables_lib.R"))

# Baseline smoothing sensitivity. The paper's CHM-VWF smooths its 0.5 m canopy
# model with a circular 3 m moving mean below 8 first returns/m² (a rule fixed
# before the runs and never tested without the smoothing). This pools a second
# CHM-VWF run on the same sealed clips with the smoothing disabled
# (detect_lidrplugins_sweep.R ARMS=chm_vwf SMOOTH_BELOW=0, in its own job
# directory) against the paper's CHM-VWF and the leading arms, per rung, with
# the master-table resamples: the unsmoothed minus smoothed change in recall,
# precision and F1, each arm's lead over either baseline, and the dominant-class
# recall of both baselines. A post hoc sensitivity, not a change of baseline.
#   CLAUDE_JOB_DIR=<paper_runs> Rscript scripts/baseline_smoothing_sensitivity.R
#     NOSMOOTH=<job dir of the unsmoothed run> [OUT=<dir>]
# Writes <OUT>/baseline_smoothing_{pooled,contrasts,dominant}.csv; OUT defaults
# to $CLAUDE_JOB_DIR/sensitivity.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
d <- .job_dir()
NS <- A[["NOSMOOTH"]]; if (is.null(NS)) stop("NOSMOOTH=<job dir> is required")
OUT <- if (is.null(A[["OUT"]])) file.path(d, "sensitivity") else A[["OUT"]]
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
SITES <- c("SJER", "SOAP", "TEAK", "WREF", "ABBY")
ARMS <- c("multichm", "forestformer3d", "treeisonet", "segmentanytree")
read_arm <- function(job, file, det, label) do.call(rbind, lapply(SITES, function(s) {
  f <- file.path(job, "neon", s, file); if (!file.exists(f)) return(NULL)
  x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  x <- x[x$detector == det, c("site", "plot", "rung", "n_ref", "n_det", "TP", "precision",
                              "rec_dominant", "n_dominant")]
  x$detector <- label; x
}))
rows <- rbind(read_arm(NS, "lidrplugins_results.csv", "chm_vwf", "chm_vwf_unsmoothed"),
              read_arm(d, "lidrplugins_results.csv", "chm_vwf", "chm_vwf"),
              read_arm(d, "lidrplugins_results.csv", "multichm", "multichm"),
              read_arm(d, "forestformer3d_results.csv", "forestformer3d", "forestformer3d"),
              read_arm(d, "treeisonet_results.csv", "treeisonet", "treeisonet"),
              read_arm(d, "segmentanytree_results.csv", "segmentanytree", "segmentanytree"))
if (!any(rows$detector == "chm_vwf_unsmoothed")) stop("No unsmoothed CHM-VWF results under ", NS)
rows$tp_core <- round(rows$precision * rows$n_det)
out <- lapply(split(rows, rows$rung), function(x) {
  r <- x$rung[1]
  key <- paste(x$site, x$plot, sep = "::")
  common <- Reduce(intersect, lapply(split(key, x$detector), unique))
  x <- x[key %in% common, ]
  W <- mt_plot_weights(x$site, x$plot, MT_N_BOOT, MT_SEED)
  s <- mt_boot_scores(x, W, c("detector", "rung"))
  est <- cbind(scope = "five sites", mt_intervals(s))
  g <- function(a) paste(a, r, sep = "|")
  con <- rbind(
    do.call(rbind, lapply(c("recall", "precision", "F1"), function(m)
      cbind(contrast = "unsmoothed minus smoothed", mt_contrast(s, g("chm_vwf"), g("chm_vwf_unsmoothed"), m)))),
    do.call(rbind, lapply(ARMS, function(a)
      rbind(cbind(contrast = "lead over smoothed", mt_contrast(s, g("chm_vwf"), g(a), "F1")),
            cbind(contrast = "lead over unsmoothed", mt_contrast(s, g("chm_vwf_unsmoothed"), g(a), "F1"))))))
  con <- cbind(scope = "five sites", rung = r, n_plots = nrow(W), con)
  b <- x[x$detector %in% c("chm_vwf", "chm_vwf_unsmoothed") & !is.na(x$rec_dominant), ]
  dom <- aggregate(cbind(tp = round(rec_dominant * n_dominant), n = n_dominant) ~ detector, b, sum)
  dom <- cbind(scope = "five sites", rung = r, dom); dom$recall <- dom$tp / dom$n
  list(est = est, con = con, dom = dom)
})
est <- do.call(rbind, lapply(out, `[[`, "est")); con <- do.call(rbind, lapply(out, `[[`, "con"))
dom <- do.call(rbind, lapply(out, `[[`, "dom"))
write.csv(est, file.path(OUT, "baseline_smoothing_pooled.csv"), row.names = FALSE)
write.csv(con, file.path(OUT, "baseline_smoothing_contrasts.csv"), row.names = FALSE)
write.csv(dom, file.path(OUT, "baseline_smoothing_dominant.csv"), row.names = FALSE)
ord <- c("native", "8", "4", "3.2", "2", "1")
cat("\n== pooled scores by rung (five sites)\n")
for (r in intersect(ord, est$rung)) for (a in c("chm_vwf", "chm_vwf_unsmoothed", ARMS)) {
  e <- est[est$detector == a & est$rung == r, ]
  if (nrow(e)) cat(sprintf("%-7s %-19s F1 %.3f [%.3f, %.3f]  recall %.3f  precision %.3f  n_det %d\n", r, a,
                           e$estimate[e$metric == "F1"], e$lower[e$metric == "F1"], e$upper[e$metric == "F1"],
                           e$estimate[e$metric == "recall"], e$estimate[e$metric == "precision"], e$n_det[1]))
}
cat("\n== contrasts\n")
for (r in intersect(ord, con$rung)) { z <- con[con$rung == r, ]
  for (i in seq_len(nrow(z))) cat(sprintf("%-7s %-26s %-28s %-9s %+.3f [%+.3f, %+.3f]\n", r, z$contrast[i],
                                          z$to[i], z$metric[i], z$estimate[i], z$lower[i], z$upper[i])) }
cat("\n== dominant-class recall of the two baselines\n"); print(dom, row.names = FALSE, digits = 3)
cat(sprintf("wrote %s\n", file.path(OUT, "baseline_smoothing_{pooled,contrasts,dominant}.csv")))
