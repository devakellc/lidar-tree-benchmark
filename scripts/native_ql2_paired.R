#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("model_bench_lib.R"))
source(.find("master_tables_lib.R"))

# Paired comparison of the native QL2 cross-check (native_ql2_crosscheck.R
# POP=adopted): the 3DEP cloud decimated to 2 points/m² against the NEON
# frozen 2 points/m² rung, per detector, on the plots both scored. NEON side:
# CHM-VWF at 0.5 m and a = 0.10 (sweep_results.csv) and multichm
# (lidrplugins_results.csv). Pooled by summed counts with the master tables'
# paired plot bootstrap (MT_N_BOOT resamples, MT_SEED).
#   Rscript scripts/native_ql2_paired.R [SITES=SJER,SOAP,TEAK]
# Writes $CLAUDE_JOB_DIR/neon/native_ql2_paired.csv.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
SITES <- strsplit(if (is.null(A$SITES)) "SJER,SOAP,TEAK" else A$SITES, ",")[[1]]
nd <- file.path(.job_dir(), "neon")
cols <- c("site", "plot", "detector", "variant", "n_ref", "n_det", "TP", "precision")

rows <- do.call(rbind, lapply(SITES, function(s) {
  q <- read.csv(file.path(nd, s, "ql2", "ql2_detect_results.csv"), stringsAsFactors = FALSE)
  q <- q[q$variant == "native_dec2", ]
  q$site <- s; q$variant <- "3dep_dec2"
  sw <- read.csv(file.path(nd, s, "sweep_results.csv"), stringsAsFactors = FALSE)
  sw <- sw[sw$rung == "2" & sw$chm_res == 0.5 & sw$vwf_a == 0.10, ]
  sw$detector <- "chm_vwf"
  lp <- read.csv(file.path(nd, s, "lidrplugins_results.csv"), stringsAsFactors = FALSE)
  lp <- lp[lp$rung == "2" & lp$detector == "multichm", ]
  nb <- rbind(sw[, cols[c(2:3, 5:8)]], lp[, cols[c(2:3, 5:8)]])
  nb$site <- s; nb$variant <- "neon_dec2"
  rbind(q[, cols], nb[, cols])
}))
rows$tp_core <- ifelse(rows$n_det > 0, round(rows$precision * rows$n_det), 0)
rows$rung <- "2"

out <- do.call(rbind, lapply(c("chm_vwf", "multichm"), function(a) {
  x <- rows[rows$detector == a, ]
  key <- paste(x$site, x$plot)
  common <- intersect(key[x$variant == "3dep_dec2"], key[x$variant == "neon_dec2"])
  x <- x[key %in% common, ]
  W <- mt_plot_weights(x$site, x$plot, MT_N_BOOT, MT_SEED)
  s <- mt_boot_scores(x, W, c("variant", "detector"))
  e <- s$estimate
  est <- data.frame(detector = a, row = e$variant, plots = nrow(W), n_ref = e$n_ref,
                    recall = e$recall, precision = e$precision, F1 = e$F1,
                    lower = NA_real_, upper = NA_real_)
  dif <- do.call(rbind, lapply(c("recall", "precision", "F1"), function(m) {
    z <- mt_contrast(s, paste("neon_dec2", a, sep = "|"), paste("3dep_dec2", a, sep = "|"), m)
    data.frame(detector = a, row = paste("3DEP minus NEON", m), plots = nrow(W), n_ref = e$n_ref[1],
               recall = NA_real_, precision = NA_real_, F1 = NA_real_,
               lower = z$lower, upper = z$upper, estimate = z$estimate)
  }))
  est$estimate <- NA_real_
  rbind(est, dif)
}))
write.csv(out, file.path(nd, "native_ql2_paired.csv"), row.names = FALSE)
print(out, row.names = FALSE, digits = 3)
