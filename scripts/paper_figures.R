#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("model_bench_lib.R"))

# The paper's figures, from the master tables and the study outputs of the
# paper runs. Base graphics only, so the reproduction image needs nothing
# more. Every figure also writes the numbers it plots (figure_<n>.csv), which
# the reproduction compares like any table.
#   1  sites: stems by crown class, native pulse density, stem heights
#   2  F1, recall and precision against pulse density, full-ladder arms
#   3  each arm's rank down the ladder, with the rank correlations
#   4  overstory and understory recall against pulse density
#   5  nominal-box and censused precision per arm (native), with the credited bracket
#   6  native sparse flights against the decimated 2021 rungs
#   7  sensitivity: match radius, matcher, stem-position jitter
#   Rscript scripts/paper_figures.R [FIGURES=1,2,3,4,5,6,7] [OUT=<dir>]
#     [FROZEN_ROOT=...] [SPARSE_REPORT=<dir>] [MASTER=<master_tables dir>]
# CLAUDE_JOB_DIR is the paper-run job directory (master_tables/, sensitivity/,
# neon/<SITE>/coverage_gap.csv). SPARSE_REPORT defaults to
# <job dir>/../sparse_2018/compare_report.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
d <- .job_dir()
FIGS <- as.integer(strsplit(if (is.null(A$FIGURES)) "1,2,3,4,5,6,7" else A$FIGURES, ",")[[1]])
OUT <- if (is.null(A$OUT)) file.path(d, "figures") else A$OUT
ROOT <- frozen_root(d, A$FROZEN_ROOT)
MT <- if (is.null(A$MASTER)) file.path(d, "master_tables") else A$MASTER
SPARSE <- if (is.null(A$SPARSE_REPORT)) file.path(dirname(d), "sparse_2018", "compare_report") else A$SPARSE_REPORT
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
SITES <- c("SJER", "SOAP", "TEAK", "WREF", "ABBY")

ARMS <- c(chm_vwf = "CHM-VWF", multichm = "multichm", lmfauto = "lmfauto", ptrees = "ptrees",
          ams3d = "AMS3D", li2012 = "Li 2012", forestformer3d = "ForestFormer3D",
          treeisonet = "TreeisoNet", segmentanytree = "SegmentAnyTree",
          deepforest = "DeepForest", detectree2 = "Detectree2", sam2point = "SAM2Point")
LADDER <- c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d", "forestformer3d",
            "treeisonet", "segmentanytree")
COL <- c(chm_vwf = "#000000", multichm = "#E69F00", lmfauto = "#999999", ptrees = "#56B4E9",
         ams3d = "#009E73", li2012 = "#8C564B", forestformer3d = "#D55E00",
         treeisonet = "#CC79A7", segmentanytree = "#0072B2", deepforest = "#6A3D9A",
         detectree2 = "#B15928", sam2point = "#7F7F7F")
PCH <- setNames(c(16, 17, 15, 18, 1, 2, 16, 17, 15, 0, 5, 6), names(ARMS))
QL <- c(QL2 = 2, QL1 = 8)                       # USGS aggregate nominal pulse density

read_mt <- function(f) read.csv(file.path(MT, f), stringsAsFactors = FALSE,
                                colClasses = c(rung = "character"))
long <- read_mt("master_long.csv")
long <- long[long$status == "included", , drop = FALSE]
dens <- read_mt("rung_density.csv")
pulses <- setNames(dens$pulses_median[dens$scope == "five sites"], dens$rung[dens$scope == "five sites"])

device <- function(n, w = 9, h = 5.5) {
  png(file.path(OUT, sprintf("figure_%d.png", n)), width = w, height = h, units = "in", res = 200)
}
save_data <- function(n, x) write.csv(x, file.path(OUT, sprintf("figure_%d.csv", n)), row.names = FALSE)
ql_lines <- function() {
  abline(v = QL, lty = 3, col = "grey40")
  text(QL, par("usr")[4], names(QL), pos = 1, cex = 0.7, col = "grey30")
}
legend_arms <- function(arms, where = "bottomleft", ...)
  legend(where, legend = ARMS[arms], col = COL[arms], pch = PCH[arms], lty = 1, bty = "n",
         cex = 0.7, ...)
ladder_rows <- function(tab, scope = "five sites", metric = "F1", arms = LADDER) {
  x <- long[long$table == tab & long$scope == scope & long$metric == metric &
              long$detector %in% arms & long$rung %in% names(pulses), , drop = FALSE]
  x$pulses <- unname(pulses[x$rung])
  x[order(x$detector, -x$pulses), ]
}
ci_lines <- function(x, y, lo, hi, col) segments(x, lo, x, hi, col = adjustcolor(col, 0.6))

## ---- 1: sites -----------------------------------------------------------------------
fig1 <- function() {
  st <- read.csv(file.path(ROOT, "population_stems.csv"), stringsAsFactors = FALSE)
  st <- st[st$population == "adopted", ]
  cm <- frozen_clip_manifest(ROOT)
  pop <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
  nat <- cm[cm$rung == "native" & cm$status == "ok" &
              paste(cm$site, cm$plot) %in% paste(pop$site, pop$plotID)[pop$in_adopted], ]
  cls <- c("dominant", "codominant", "intermediate", "suppressed")
  tab <- sapply(SITES, function(s) table(factor(st$crown_class[st$site == s], cls)))
  save_data(1, rbind(
    data.frame(panel = "stems", site = rep(SITES, each = 4), key = rep(cls, 5), value = as.vector(tab)),
    data.frame(panel = "native_pulses", site = nat$site, key = nat$plot, value = nat$frdens),
    data.frame(panel = "height", site = st$site, key = st$individualID, value = st$height)))
  device(1, 11, 4)
  par(mfrow = c(1, 3), mar = c(4, 4, 2.5, 1))
  barplot(tab, col = c("#1B9E77", "#66C2A5", "#FC8D62", "#E78AC3"), ylab = "Stems",
          main = "Stems by crown class")
  legend("topleft", legend = cls, fill = c("#1B9E77", "#66C2A5", "#FC8D62", "#E78AC3"),
         bty = "n", cex = 0.8)
  boxplot(frdens ~ factor(site, SITES), data = nat, log = "y", xlab = "",
          ylab = "First-return pulses/m² (native clip)", main = "Native pulse density")
  abline(h = QL, lty = 3, col = "grey40")
  boxplot(height ~ factor(site, SITES), data = st, xlab = "", ylab = "Stem height (m)",
          main = "Reference stem heights")
  dev.off()
}

## ---- 2: F1, recall, precision against pulse density ---------------------------------
fig2 <- function() {
  x <- do.call(rbind, lapply(c("F1", "recall", "precision"), function(m) ladder_rows("nominal box", metric = m)))
  save_data(2, x[, c("detector", "rung", "pulses", "metric", "estimate", "lower", "upper")])
  device(2, 12, 4.5)
  par(mfrow = c(1, 3), mar = c(4, 4, 2.5, 1))
  for (m in c("F1", "recall", "precision")) {
    y <- x[x$metric == m, ]
    plot(NA, xlim = rev(range(y$pulses)) * c(1.1, 0.9), ylim = c(0, max(y$upper, na.rm = TRUE)),
         log = "x", xlab = "First-return pulses/m²", ylab = m,
         main = c(F1 = "F1", recall = "Recall", precision = "Precision")[[m]])
    ql_lines()
    for (a in LADDER) {
      z <- y[y$detector == a, ]
      ci_lines(z$pulses, z$estimate, z$lower, z$upper, COL[a])
      lines(z$pulses, z$estimate, col = COL[a], type = "o", pch = PCH[a], cex = 0.8)
    }
    if (m == "F1") legend_arms(LADDER)
  }
  dev.off()
}

## ---- 3: rank down the ladder ----------------------------------------------------------
fig3 <- function() {
  x <- ladder_rows("nominal box")
  x <- x[x$detector %in% names(which(table(x$detector) == length(unique(x$rung)))), ]
  x$rank <- ave(-x$estimate, x$rung, FUN = function(v) rank(v, ties.method = "min"))
  rs <- read.csv(file.path(MT, "master_rank_stability.csv"), stringsAsFactors = FALSE,
                 colClasses = c(from = "character", to = "character"))
  rs <- rs[rs$table == "nominal box", ]
  # The two detectors that move most below the QL2 floor, left out together.
  lo <- read.csv(file.path(MT, "master_rank_leave_out.csv"), stringsAsFactors = FALSE,
                 colClasses = c(from = "character", to = "character"))
  lo <- lo[lo$table == "nominal box" & lo$left_out == "segmentanytree+ams3d", ]
  save_data(3, rbind(data.frame(kind = "rank", detector = x$detector, rung = x$rung, pulses = x$pulses,
                                value = x$rank, lower = NA, upper = NA),
                     data.frame(kind = "spearman", detector = NA, rung = rs$to, pulses = unname(pulses[rs$to]),
                                value = rs$estimate, lower = rs$lower, upper = rs$upper),
                     data.frame(kind = "spearman_without_segmentanytree_ams3d", detector = NA, rung = lo$to,
                                pulses = unname(pulses[lo$to]), value = lo$estimate, lower = lo$lower,
                                upper = lo$upper)))
  device(3, 10, 5.6)
  layout(matrix(c(1, 2, 3, 3), 2, byrow = TRUE), widths = c(2, 1), heights = c(5, 0.6))
  par(mar = c(4, 4, 2.5, 1))
  plot(NA, xlim = rev(range(x$pulses)) * c(1.1, 0.9), ylim = c(max(x$rank) + 0.5, 0.5), log = "x",
       xlab = "First-return pulses/m²", ylab = "Rank by F1 (1 = best)", main = "Rank down the ladder")
  ql_lines()
  for (a in unique(x$detector)) {
    z <- x[x$detector == a, ]
    lines(z$pulses, z$rank, col = COL[a], type = "o", pch = PCH[a], lwd = 1.5)
  }
  rs$pulses <- unname(pulses[rs$to])
  lo$pulses <- unname(pulses[lo$to]) * 0.92        # offset so the intervals do not overlap
  plot(rs$pulses, rs$estimate, log = "x", xlim = rev(range(rs$pulses)) * c(1.1, 0.85), ylim = c(-1, 1),
       pch = 16, xlab = "First-return pulses/m²", ylab = "Spearman ρ with native rank",
       main = "Rank stability")
  segments(rs$pulses, rs$lower, rs$pulses, rs$upper); abline(h = 0, lty = 2)
  points(lo$pulses, lo$estimate, pch = 1, col = "grey35")
  segments(lo$pulses, lo$lower, lo$pulses, lo$upper, col = "grey35", lty = 1)
  legend("bottomleft", legend = c("All eight detectors", "Without SegmentAnyTree and AMS3D"),
         pch = c(16, 1), col = c("black", "grey35"), bty = "n", cex = 0.7)
  # Neither panel has a free corner for the detectors; their legend runs below both.
  par(mar = c(0, 0, 0, 0)); plot.new()
  legend("center", legend = ARMS[unique(x$detector)], col = COL[unique(x$detector)],
         pch = PCH[unique(x$detector)], lty = 1, bty = "n", cex = 0.8, ncol = 4)
  dev.off()
}

## ---- 4: overstory and understory recall ---------------------------------------------
fig4 <- function() {
  s <- read_mt("master_strata.csv")
  s <- s[s$table == "nominal box" & s$scope == "five sites" & s$stratum %in% c("overstory", "understory") &
           s$detector %in% LADDER & s$rung %in% names(pulses), ]
  s$pulses <- unname(pulses[s$rung])
  save_data(4, s[, c("detector", "rung", "pulses", "stratum", "n_ref", "estimate", "lower", "upper")])
  device(4, 10, 4.5)
  par(mfrow = c(1, 2), mar = c(4, 4, 2.5, 1))
  for (k in c("overstory", "understory")) {
    y <- s[s$stratum == k, ]
    plot(NA, xlim = rev(range(y$pulses)) * c(1.1, 0.9), ylim = c(0, 1), log = "x",
         xlab = "First-return pulses/m²", ylab = "Recall",
         main = sprintf("%s recall (%d stems)", tools::toTitleCase(k), y$n_ref[1]))
    ql_lines()
    for (a in LADDER) {
      z <- y[y$detector == a, ]; z <- z[order(-z$pulses), ]
      ci_lines(z$pulses, z$estimate, z$lower, z$upper, COL[a])
      lines(z$pulses, z$estimate, col = COL[a], type = "o", pch = PCH[a], cex = 0.8)
    }
    if (k == "overstory") legend_arms(LADDER)
  }
  dev.off()
}

## ---- 5: nominal, censused and credited precision -------------------------------------
fig5 <- function() {
  g <- function(tab) {
    z <- long[long$table == tab & long$scope == "five sites" & long$rung == "native" & long$metric == "precision", ]
    z[match(names(ARMS), z$detector), c("detector", "estimate", "lower", "upper")]
  }
  nom <- g("nominal box"); cen <- g("census, nearest census (headline)")
  cg <- do.call(rbind, lapply(SITES, function(s) {
    f <- file.path(d, "neon", s, "coverage_gap.csv")
    if (file.exists(f)) read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character")) }))
  # The coverage-gap study scores each arm at its selected configuration
  # (CHM-VWF also down its native ladder): the credited bracket runs from raw
  # to credited precision on those cells, CHM-VWF's at native density.
  cg <- cg[cg$detector != "chm_vwf" &
             (cg$detector != "chm_vwf_ladder" | cg$rung == "native"), ]
  cg$detector[cg$detector == "chm_vwf_ladder"] <- "chm_vwf"
  cg$tp_core <- ifelse(cg$n_det > 0, round(cg$precision * cg$n_det), 0)
  cred <- aggregate(cbind(tp_core, fp_credited, n_det) ~ detector, cg, sum)
  cred$raw <- cred$tp_core / cred$n_det
  # Credited false positives leave the precision denominator, floored at the
  # pooled true positives (pool() in model_bench_lib.R; coverage-gap study).
  cred$credited <- cred$tp_core / pmax(cred$n_det - cred$fp_credited, cred$tp_core)
  # SAM2Point is not analysed in the paper and has no credited value.
  arms <- setdiff(names(ARMS), "sam2point")
  i <- match(arms, cred$detector)
  out <- data.frame(detector = arms, nominal = nom$estimate[match(arms, nom$detector)],
                    nominal_lo = nom$lower[match(arms, nom$detector)],
                    nominal_hi = nom$upper[match(arms, nom$detector)],
                    censused = cen$estimate[match(arms, cen$detector)],
                    censused_lo = cen$lower[match(arms, cen$detector)],
                    censused_hi = cen$upper[match(arms, cen$detector)],
                    selected_raw = cred$raw[i], selected_credited = cred$credited[i])
  save_data(5, out)
  device(5, 9, 5.5)
  par(mar = c(4, 9, 2.5, 1))
  o <- order(out$nominal); y <- seq_along(o)
  plot(NA, xlim = c(0, 1), ylim = c(0.5, length(o) + 0.5), yaxt = "n", ylab = "",
       xlab = "Precision", main = "Precision by reference")
  axis(2, at = y, labels = ARMS[out$detector[o]], las = 1, cex.axis = 0.8)
  segments(out$nominal_lo[o], y - 0.12, out$nominal_hi[o], y - 0.12, col = "grey40")
  points(out$nominal[o], y - 0.12, pch = 16, col = "grey20")
  segments(out$censused_lo[o], y + 0.12, out$censused_hi[o], y + 0.12, col = "#0072B2")
  points(out$censused[o], y + 0.12, pch = 17, col = "#0072B2")
  arrows(out$selected_raw[o], y, out$selected_credited[o], y, length = 0.05, col = "#D55E00")
  legend("topleft", legend = c("Nominal plot core, native", "Censused subplots, native",
                                   "Raw to credited, best density per site"),
         pch = c(16, 17, NA), lty = c(NA, NA, 1), col = c("grey20", "#0072B2", "#D55E00"),
         bty = "n", cex = 0.8)
  dev.off()
}

## ---- 6: native sparse flights ------------------------------------------------------------
fig6 <- function() {
  f <- file.path(SPARSE, "sparse_vs_2021.csv")
  if (!file.exists(f)) { message("no sparse report at ", SPARSE); return(invisible()) }
  x <- read.csv(f, stringsAsFactors = FALSE)
  x <- x[x$stratum == "shared" & x$site == "D17", ]
  x$cell <- factor(paste(x$side, x$rung), c("sparse native", "2021 4", "2021 8", "2021 native"))
  arms <- intersect(c("chm_vwf", "multichm", "forestformer3d", "treeisonet", "segmentanytree"), x$arm)
  keep <- c("arm", "cell", "frdens_median", "recall", "rec_overstory", "rec_understory", "F1")
  save_data(6, x[x$arm %in% arms, keep])
  device(6, 12, 4.5)
  par(mfrow = c(1, 3), mar = c(5, 4, 2.5, 1))
  for (m in c("recall", "rec_overstory", "rec_understory")) {
    plot(NA, xlim = c(0.5, 4.5), ylim = c(0, 1), xaxt = "n", xlab = "", ylab = "Recall",
         main = c(recall = "All stems", rec_overstory = "Overstory", rec_understory = "Understory")[m])
    axis(1, at = 1:4, labels = c("sparse\nflight", "2021, about\n2.9 pulses/m²", "2021, about\n5.4 pulses/m²", "2021\nnative"),
         padj = 0.5, cex.axis = 0.8)
    for (a in arms) {
      z <- x[x$arm == a, ]; z <- z[order(z$cell), ]
      lines(as.integer(z$cell), z[[m]], type = "o", col = COL[a], pch = PCH[a])
    }
    if (m == "recall") legend_arms(arms)
  }
  dev.off()
}

## ---- 7: sensitivity -------------------------------------------------------------------------
fig7 <- function() {
  sd <- file.path(d, "sensitivity")
  mp <- read.csv(file.path(sd, "matcher_pooled.csv"), stringsAsFactors = FALSE)
  mp <- mp[mp$scope == "five sites" & mp$rung == "native" & mp$metric == "F1", ]
  md <- read.csv(file.path(sd, "matcher_delta.csv"), stringsAsFactors = FALSE)
  md <- md[md$scope == "five sites" & md$rung == "native" & md$metric == "F1" &
             md$variant %in% c("scaled", "optimal", "optimal_scaled", "soft3d"), ]
  jb <- read.csv(file.path(sd, "jitter_bands.csv"), stringsAsFactors = FALSE)
  jb <- jb[jb$scope == "five sites" & jb$rung == "native", ]
  nb <- long[long$table == "nominal box" & long$scope == "five sites" & long$rung == "native" &
               long$metric == "F1", ]
  grid <- mp[grepl("^grid_tx[0-9]+_tz8$", mp$variant), ]
  grid$radius <- as.numeric(sub("grid_tx([0-9]+)_tz8", "\\1", grid$variant))
  save_data(7, rbind(
    data.frame(panel = "radius", detector = grid$detector, key = grid$radius, value = grid$estimate,
               lower = grid$lower, upper = grid$upper),
    data.frame(panel = "matcher", detector = md$detector, key = md$variant, value = md$estimate,
               lower = md$lower, upper = md$upper),
    data.frame(panel = "jitter_width", detector = jb$detector, key = "p95-p05",
               value = jb$F1_p95 - jb$F1_p05, lower = NA, upper = NA),
    data.frame(panel = "bootstrap_width", detector = nb$detector, key = "95% interval",
               value = nb$upper - nb$lower, lower = NA, upper = NA)))
  device(7, 13, 4.5)
  par(mfrow = c(1, 3), mar = c(4, 4, 2.5, 1))
  plot(NA, xlim = c(2, 5), ylim = range(grid$estimate), xlab = "Match radius (m)", ylab = "F1",
       main = "Match radius (native, five sites)")
  for (a in names(ARMS)) { z <- grid[grid$detector == a, ]; z <- z[order(z$radius), ]
    lines(z$radius, z$estimate, type = "o", col = COL[a], pch = PCH[a]) }
  abline(v = 4, lty = 2)
  vs <- c("scaled", "optimal", "optimal_scaled", "soft3d")
  plot(NA, xlim = c(0.5, 4.5), ylim = range(c(md$lower, md$upper)), xaxt = "n", xlab = "",
       ylab = "Change in F1 from greedy 4 m", main = "Matcher")
  axis(1, at = 1:4, labels = c("crown-scaled", "Hungarian", "Hungarian,\nscaled", "soft 3-D"),
       padj = 0.5, cex.axis = 0.8)
  abline(h = 0, lty = 2)
  for (i in seq_along(names(ARMS))) { a <- names(ARMS)[i]; z <- md[md$detector == a, ]
    xx <- match(z$variant, vs) + (i - 6.5) * 0.04
    segments(xx, z$lower, xx, z$upper, col = COL[a]); points(xx, z$estimate, col = COL[a], pch = PCH[a]) }
  w <- merge(data.frame(detector = jb$detector, jitter = jb$F1_p95 - jb$F1_p05),
             data.frame(detector = nb$detector, boot = nb$upper - nb$lower))
  plot(w$boot, w$jitter, xlim = c(0, max(w$boot) * 1.05), ylim = c(0, max(w$boot) * 1.05),
       col = COL[w$detector], pch = PCH[w$detector], xlab = "Plot-bootstrap 95% interval width (F1)",
       ylab = "Stem-jitter 90% band width (F1)", main = "Position jitter against plot sampling")
  abline(0, 1, lty = 2)
  legend_arms(w$detector, "topleft")
  dev.off()
}

for (n in FIGS) {
  get(paste0("fig", n))()
  cat(sprintf("figure %d -> %s\n", n, file.path(OUT, sprintf("figure_%d.png", n))))
}
