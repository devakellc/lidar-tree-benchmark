#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)

# Native sparse versus decimated 2021 on one reference. MODE=prepare writes,
# per site, job directories whose ground truth holds only the comparison
# stems, for each side's sealed root:
#   <sparse job>/compare_shared and <C21>/shared      stems live in both
#     epochs' adopted references on plots adopted in both (2021 rows on both
#     sides, so positions, heights and crown classes are identical);
#   <sparse job>/compare_2015only and <C21>/only2015   sparse-epoch stems last
#     recorded in 2015 on the same plots (their sparse-epoch rows);
#   <sparse job>/strata_2015only and strata_remeasured  the whole sparse-epoch
#     reference split into those two strata, on every sparse adopted plot.
# Plot centroids are each side's own (they must match its root); the cores
# coincide on every common plot. CHM-VWF (run_sweep.R) and multichm then run
# in each directory (see the results document). MODE=report pools them by
# crown class on the plots every compared cell shares.
#   Rscript scripts/compare_sparse_epoch.R MODE=prepare|report \
#     EPOCHS=SJER:<sparse job>:2017,SOAP:<sparse job>:2018,TEAK:<sparse job>:2018 \
#     C21=<2021 comparison job dir> [ROOT2021=<work>/neon/frozen_2021] [OUT=<dir>]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
mode <- match.arg(A$MODE, c("prepare", "report"))
ep <- do.call(rbind, lapply(strsplit(strsplit(A$EPOCHS, ",")[[1]], ":"), function(x)
  data.frame(site = x[1], job = x[2], year = as.integer(x[3]), stringsAsFactors = FALSE)))
c21 <- A$C21
root21 <- if (is.null(A$ROOT2021)) file.path(.job_dir(), "neon", "frozen_2021") else A$ROOT2021
nd21 <- file.path(dirname(root21))                      # <work>/neon
sroot <- function(i) file.path(ep$job[i], "neon", sprintf("frozen_%d", ep$year[i]))

write_job <- function(dir, site, gt, pc) {
  d <- file.path(dir, "neon", site); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  write.csv(gt, file.path(d, "ground_truth_stems.csv"), row.names = FALSE)
  write.csv(pc, file.path(d, "plot_centroids.csv"), row.names = FALSE)
}

if (mode == "prepare") {
  pop21 <- read.csv(file.path(root21, "population.csv"))
  st21 <- read.csv(file.path(root21, "population_stems.csv"))
  for (i in seq_len(nrow(ep))) {
    s <- ep$site[i]
    popS <- read.csv(file.path(sroot(i), "population.csv"))
    stS <- read.csv(file.path(sroot(i), "population_stems.csv"))
    common <- intersect(pop21$plotID[pop21$site == s & pop21$in_adopted],
                        popS$plotID[popS$site == s & popS$in_adopted])
    a21 <- st21[st21$site == s & st21$population == "adopted" & st21$plotID %in% common, ]
    aS <- stS[stS$site == s & stS$population == "adopted" & stS$plotID %in% common, ]
    shared <- intersect(a21$individualID, aS$individualID)
    gt21 <- read.csv(file.path(nd21, s, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    pc21 <- read.csv(file.path(nd21, s, "plot_centroids.csv"), stringsAsFactors = FALSE)
    gtS <- read.csv(file.path(ep$job[i], "neon", s, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    pcS <- read.csv(file.path(ep$job[i], "neon", s, "plot_centroids.csv"), stringsAsFactors = FALSE)
    m <- merge(pc21[pc21$plotID %in% common, c("plotID", "easting", "northing")],
               pcS[pcS$plotID %in% common, c("plotID", "easting", "northing")], by = "plotID")
    if (any(abs(m$easting.x - m$easting.y) > 1e-6 | abs(m$northing.x - m$northing.y) > 1e-6))
      stop(s, ": a common plot has different centroids in the two references")
    key21 <- paste(gt21$plotID, gt21$individualID); keyS <- paste(gtS$plotID, gtS$individualID)
    sh <- gt21[key21 %in% paste(a21$plotID, a21$individualID) & gt21$individualID %in% shared &
               gt21$live & gt21$is_tree, ]
    # 2015-only: sparse-epoch adopted stems with no record after 2015.
    vst <- readRDS(file.path(ep$job[i], "neon", s, "vst", sprintf("%s_vst_allyears.rds", tolower(s))))
    ai <- vst$vst_apparentindividual
    last <- tapply(as.integer(substr(ai$date, 1, 4)), ai$individualID, max, na.rm = TRUE)
    only <- aS$individualID[as.integer(last[aS$individualID]) <= 2015]
    o15 <- gtS[keyS %in% paste(aS$plotID, aS$individualID) & gtS$individualID %in% only &
               gtS$live & gtS$is_tree, ]
    write_job(file.path(ep$job[i], "compare_shared"), s, sh, pcS)
    write_job(file.path(c21, "shared"), s, sh, pc21)
    if (nrow(o15)) {
      write_job(file.path(ep$job[i], "compare_2015only"), s, o15, pcS)
      write_job(file.path(c21, "only2015"), s, o15, pc21)
    }
    # Whole sparse-epoch reference split by stratum, on every sparse adopted plot.
    allS <- stS[stS$site == s & stS$population == "adopted", ]
    old <- allS$individualID[as.integer(last[allS$individualID]) <= 2015]
    keyA <- keyS %in% paste(allS$plotID, allS$individualID) & gtS$live & gtS$is_tree
    if (length(old)) {
      write_job(file.path(ep$job[i], "strata_2015only"), s, gtS[keyA & gtS$individualID %in% old, ], pcS)
      rem <- gtS[keyA & !gtS$individualID %in% old, ]
      write_job(file.path(ep$job[i], "strata_remeasured"), s, rem, pcS)
      # 2015-only stems carry no height (DBH-only census), so they match on
      # position alone; the re-measured stratum is scored the same way too.
      rem$height <- NA_real_
      write_job(file.path(ep$job[i], "strata_remeasured_noheight"), s, rem, pcS)
    }
    cat(sprintf("%s: common adopted plots %d, shared stems %d (on %d plots), 2015-only stems %d (on %d plots)\n",
                s, length(common), nrow(sh), length(unique(sh$plotID)), nrow(o15),
                length(unique(o15$plotID))))
  }
  quit(save = "no")
}

## ---- report ----------------------------------------------------------------
out <- if (is.null(A$OUT)) file.path(ep$job[1], "compare_report") else A$OUT
dir.create(out, recursive = TRUE, showWarnings = FALSE)
CLASSES <- c("dominant", "codominant", "intermediate", "suppressed")
# Result file per arm; SegmentAnyTree joins when its GPU runs have been made.
ARM_FILES <- c(chm_vwf = "sweep.csv", multichm = "multichm.csv",
               segmentanytree = "segmentanytree_results.csv")
read_side <- function(path, arm, side) {
  if (!file.exists(path)) return(NULL)
  x <- read.csv(path, stringsAsFactors = FALSE); x$rung <- as.character(x$rung)
  if (arm == "chm_vwf") {
    fine <- paste(x$plot, x$rung) %in% unique(paste(x$plot, x$rung)[x$chm_res == 0.25])
    x <- x[x$vwf_a == 0.10 & x$chm_res == ifelse(fine, 0.25, 0.5), ]   # density-derived res
  }
  x$arm <- arm; x$side <- side; x
}
pool_cls <- function(x) {
  tpc <- round(x$precision * x$n_det)
  r <- sum(x$TP) / sum(x$n_ref); p <- if (sum(x$n_det)) sum(tpc, na.rm = TRUE) / sum(x$n_det) else NA
  row <- data.frame(plots = length(unique(x$plot)), n_ref = sum(x$n_ref), n_det = sum(x$n_det),
                    recall = r, precision = p, F1 = if (is.finite(p) && r + p > 0) 2 * r * p / (r + p) else NA)
  cls <- function(k) { n <- x[[paste0("n_", k)]]; sum(ifelse(n > 0, round(x[[paste0("rec_", k)]] * n), 0), na.rm = TRUE) }
  for (k in CLASSES) {
    row[[paste0("n_", k)]] <- sum(x[[paste0("n_", k)]])
    row[[paste0("rec_", k)]] <- if (row[[paste0("n_", k)]]) cls(k) / row[[paste0("n_", k)]] else NA
  }
  n_over <- sum(x$n_dominant + x$n_codominant); n_under <- sum(x$n_intermediate + x$n_suppressed)
  row$rec_overstory <- if (n_over) (cls("dominant") + cls("codominant")) / n_over else NA
  row$rec_understory <- if (n_under) (cls("intermediate") + cls("suppressed")) / n_under else NA
  row$n_overstory <- n_over; row$n_understory <- n_under
  row
}
res <- list()
for (stratum in c("shared", "only2015")) {
  for (i in seq_len(nrow(ep))) {
    s <- ep$site[i]
    sdir <- file.path(ep$job[i], if (stratum == "shared") "compare_shared" else "compare_2015only", "neon", s)
    cdir <- file.path(c21, stratum, "neon", s)
    runs <- Filter(Negate(is.null), c(
      lapply(names(ARM_FILES), function(a) read_side(file.path(sdir, ARM_FILES[[a]]), a, "sparse")),
      lapply(names(ARM_FILES), function(a) read_side(file.path(cdir, ARM_FILES[[a]]), a, "2021"))))
    if (!length(runs)) next
    cols <- Reduce(intersect, lapply(runs, names)); x <- do.call(rbind, lapply(runs, `[`, cols))
    cells <- list(sparse = "native", `2021` = c("native", "8", "4"))
    for (a in unique(x$arm)) {
      xa <- x[x$arm == a, ]
      sets <- c(list(xa$plot[xa$side == "sparse" & xa$rung == "native"]),
                lapply(cells$`2021`, function(r) xa$plot[xa$side == "2021" & xa$rung == r]))
      eq <- Reduce(intersect, sets)                         # equal plot set across all cells
      for (cell in list(c("sparse", "native"), c("2021", "native"), c("2021", "8"), c("2021", "4"))) {
        y <- xa[xa$side == cell[1] & xa$rung == cell[2] & xa$plot %in% eq, ]
        if (!nrow(y)) next
        res[[length(res) + 1]] <- data.frame(stratum = stratum, site = s, arm = a, side = cell[1],
          rung = cell[2], frdens_median = median(y$frdens), pool_cls(y))
      }
    }
  }
}
# Whole sparse-epoch reference by stratum, on the sparse native clouds.
for (i in seq_len(nrow(ep))) for (st in c("strata_2015only", "strata_remeasured_noheight",
                                         "strata_remeasured")) {
  s <- ep$site[i]; dir <- file.path(ep$job[i], st, "neon", s)
  for (a in names(ARM_FILES)) {
    y <- read_side(file.path(dir, ARM_FILES[[a]]), a, "sparse")
    if (is.null(y)) next
    y <- y[y$rung == "native", ]
    if (nrow(y)) res[[length(res) + 1]] <- data.frame(stratum = st, site = s, arm = a,
      side = "sparse", rung = "native", frdens_median = median(y$frdens), pool_cls(y))
  }
}
tab <- do.call(rbind, res)
# D17 rows: pool the per-site counts again.
d17 <- do.call(rbind, lapply(split(tab, paste(tab$stratum, tab$arm, tab$side, tab$rung)), function(t) {
  r <- t[1, ]; r$site <- "D17"; r$frdens_median <- NA
  tp <- t$recall * t$n_ref; tpc <- t$precision * t$n_det
  r$plots <- sum(t$plots); r$n_ref <- sum(t$n_ref); r$n_det <- sum(t$n_det)
  r$recall <- sum(tp) / sum(t$n_ref); r$precision <- sum(tpc) / sum(t$n_det)
  r$F1 <- 2 * r$recall * r$precision / (r$recall + r$precision)
  for (k in c(CLASSES, "overstory", "understory")) {
    n <- t[[paste0("n_", k)]]; r[[paste0("n_", k)]] <- sum(n)
    r[[paste0("rec_", k)]] <- if (sum(n)) sum(t[[paste0("rec_", k)]] * n, na.rm = TRUE) / sum(n) else NA
  }
  r
}))
tab <- rbind(tab, d17)
tab <- tab[order(tab$stratum, tab$arm, match(tab$site, c("SJER", "SOAP", "TEAK", "D17")),
                 match(paste(tab$side, tab$rung), c("sparse native", "2021 native", "2021 8", "2021 4"))), ]
write.csv(tab, file.path(out, "sparse_vs_2021.csv"), row.names = FALSE)

# Paired plot bootstrap of sparse native minus each 2021 cell on the shared
# stems (all sites, equal plot sets), resampling plots within site.
boot <- list(); set.seed(2026)
for (a in names(ARM_FILES)) {
  rows <- list()
  for (i in seq_len(nrow(ep))) {
    s <- ep$site[i]
    sp <- read_side(file.path(ep$job[i], "compare_shared", "neon", s, ARM_FILES[[a]]), a, "sparse")
    c2 <- read_side(file.path(c21, "shared", "neon", s, ARM_FILES[[a]]), a, "2021")
    if (is.null(sp) || is.null(c2)) next
    sp <- sp[sp$rung == "native", ]
    eq <- Reduce(intersect, c(list(sp$plot), lapply(c("native", "8", "4"), function(r) c2$plot[c2$rung == r])))
    rows[[s]] <- rbind(sp[sp$plot %in% eq, ], c2[c2$rung %in% c("native", "8", "4") & c2$plot %in% eq, ])[,
      c("plot", "side", "rung", "n_ref", "n_det", "TP", "precision")]
    rows[[s]]$site <- s
  }
  if (!length(rows)) next
  d <- do.call(rbind, rows); d$tpc <- round(d$precision * d$n_det); d$tpc[is.na(d$tpc)] <- 0
  d$cell <- paste(d$side, d$rung)
  met <- function(x) { r <- sum(x$TP) / sum(x$n_ref); p <- sum(x$tpc) / sum(x$n_det)
                       c(recall = r, precision = p, F1 = 2 * r * p / (r + p)) }
  delta <- function(dd, ref) met(dd[dd$cell == "sparse native", ]) - met(dd[dd$cell == ref, ])
  plots <- split(unique(d[, c("site", "plot")]), unique(d[, c("site", "plot")])$site)
  for (ref in c("2021 native", "2021 8", "2021 4")) {
    est <- delta(d, ref)
    reps <- replicate(2000, {
      pick <- do.call(rbind, lapply(plots, function(pp) pp[sample(nrow(pp), replace = TRUE), , drop = FALSE]))
      dd <- do.call(rbind, lapply(seq_len(nrow(pick)), function(k)
        d[d$site == pick$site[k] & d$plot == pick$plot[k], ]))
      delta(dd, ref)
    })
    for (m in names(est)) boot[[length(boot) + 1]] <- data.frame(arm = a, versus = ref, metric = m,
      delta = est[[m]], lo = quantile(reps[m, ], 0.025), hi = quantile(reps[m, ], 0.975))
  }
}
bt <- do.call(rbind, boot); rownames(bt) <- NULL
write.csv(bt, file.path(out, "sparse_minus_2021_bootstrap.csv"), row.names = FALSE)
cat("\n## Sparse native minus 2021, shared stems, D17 (paired plot bootstrap, 95%)\n\n")
cat("| Arm | Versus | Metric | Delta | 95% interval |\n| --- | --- | --- | ---: | --- |\n")
cat(sprintf("| %s | %s | %s | %+.3f | %+.3f to %+.3f |\n", bt$arm, bt$versus, bt$metric, bt$delta,
            bt$lo, bt$hi), sep = "")
f <- function(v, k = 2) ifelse(is.na(v), "—", formatC(v, format = "f", digits = k))
for (st in unique(tab$stratum)) {
  t <- tab[tab$stratum == st, ]
  cat(sprintf("\n## %s\n\n", st))
  cat("| Arm | Site | Cell | Plots | Stems | First ret./m² | Recall | Precision | F1 | Overstory | Understory |\n")
  cat("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
  cat(sprintf("| %s | %s | %s | %d | %d | %s | %s | %s | %s | %s | %s |\n", t$arm, t$site,
              paste(t$side, t$rung), t$plots, t$n_ref, f(t$frdens_median, 1), f(t$recall), f(t$precision),
              f(t$F1), f(t$rec_overstory), f(t$rec_understory)), sep = "")
}
