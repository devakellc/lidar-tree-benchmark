#!/usr/bin/env Rscript
# SegmentAnyTree with a grouping radius scaled to the point spacing: a check
# run after the paper's tables were fixed (Section S18 of the supplement).
# SegmentAnyTree's clustering region-grows the offset-shifted tree points within
# cluster_radius_search, 1.5 grid cells (0.3 m), and on sparse clouds the share
# of tree points it groups falls towards zero (instance_audit.R). The check
# widens that radius with the clip's mean point spacing and asks whether the
# detector's collapse goes away.
#
#   Rscript scripts/sat_radius_check.R MODE=prep  RUNS=<paper job dir> [OUT=...]
#   bash gpu/run_sat_radius_check.sh <OUT> [PARALLEL]
#   Rscript scripts/sat_radius_check.R MODE=score RUNS=<paper job dir> [OUT=...]
#
# RUNS, the job directory of the paper runs (work/paper_runs, its sealed root at
# neon/frozen_2021), is required and read only; OUT defaults to
# $CLAUDE_JOB_DIR/sat_radius_check and MODE to score.
#
# Cells: 10 California plots of the adopted population, per site evenly spaced
# in plot-ID order among the plots with zero-shot results at both levels (SJER
# 2, SOAP 4, TEAK 4), at the 2 and 1 point/m2 levels; Washington is not used.
# Arms: `scaled`, radius 1.5 x max(0.2 m, s) with s = 1 / sqrt(all-return
# density) of the clip, the repository's mean point spacing (1.5 grid cells,
# the cell widened to the spacing); `double`, twice that; and `default`, the
# upstream radius on two cells, a control. MODE=prep exports the fixed
# evaluation clips of the sealed root as PLY and writes manifest.csv and
# jobs.tsv under a fresh (missing or empty) OUT. MODE=score checks each job's
# log (the radius it ran with, or no override for the control) and scores it as
# detect_segmentanytree_sweep.R scores a cell (instance apexes, height above
# the clip DTM, 4 m on the plot core) with the paper's 200-shift chance null,
# and compares with RUNS's zero-shot SegmentAnyTree, ForestFormer3D, multichm
# and CHM-VWF rows and null cells on the same cells: pooled summed counts,
# paired plot-bootstrap intervals (2,000 draws) over the 10 plots. It stops
# when the control does not reproduce the paper's rows. Writes under OUT:
# scores.csv (one row per job and per comparison cell), control.csv,
# summary.csv (pooled per level and arm), contrasts.csv and grouping.csv (core
# points grouped into instances, and the instances whose outline holds two or
# more mapped stems, pooled per level and arm, with the zero-shot clouds of the
# same plots at native density and at 8 and 4 points/m2 as a baseline).
suppressMessages({ library(lidR); library(data.table) })
options(lidR.progress = FALSE)
d <- Sys.getenv("CLAUDE_JOB_DIR", file.path(getwd(), "work"))
bs <- Find(file.exists, c(
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs)
source(.find("sweep_lib.R")); source(.find("model_bench_lib.R")); source(.find("io_bridge.R"))

args <- strsplit(commandArgs(TRUE), "=")
A    <- setNames(lapply(args, `[`, 2), sapply(args, `[`, 1))
MODE <- if (is.null(A$MODE)) "score" else A$MODE
RUNS <- A$RUNS
OUT  <- if (is.null(A$OUT)) file.path(d, "sat_radius_check") else A$OUT
NPLOT <- c(SJER = 2L, SOAP = 4L, TEAK = 4L)
RUNGS <- c(2, 1)
GRID  <- 0.2
ARMS  <- c(scaled = 1.5, double = 3)
N_BOOT <- 2000L
SEED   <- 20261023L

# The arm's radius: k grid cells, the cell widened to the clip's mean point
# spacing 1 / sqrt(all-return density) where that exceeds the grid.
sat_radius <- function(pdens, k, grid = GRID) k * pmax(grid, 1 / sqrt(pdens))

prep <- function() {
  if (dir.exists(OUT) && length(list.files(OUT, all.files = TRUE, no.. = TRUE)))
    stop(OUT, " is not empty; use a fresh OUT")
  dir.create(file.path(OUT, "in"), recursive = TRUE)
  rows <- list()
  for (site in names(NPLOT)) {
    nd <- file.path(RUNS, "neon", site)
    gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
    fz <- frozen_scope(RUNS, site, list(POP = "adopted"), gt)
    sat <- read.csv(file.path(nd, "segmentanytree_results.csv"), stringsAsFactors = FALSE)
    both <- names(which(table(sat$plot[sat$rung %in% as.character(RUNGS)]) == length(RUNGS)))
    cand <- sort(intersect(intersect(fz$plots, pc$plotID), both))
    pick <- cand[unique(round(seq(1, length(cand), length.out = NPLOT[[site]])))]
    cat(sprintf("%s: %d candidate plots, picked %s\n", site, length(cand),
                paste(pick, collapse = ", ")))
    for (pid in pick) {
      ci <- pc[pc$plotID == pid, ][1, ]
      cx <- ci$easting; cy <- ci$northing; ph <- plot_half(ci$plotType)
      for (rung in RUNGS) {
        clip <- frozen_clip(NULL, site, pid, rung, cx, cy, ph, fz$root)
        if (is.null(clip)) stop("no frozen clip for ", pid, " at ", rung)
        s <- 1 / sqrt(clip$pdens)
        ply <- file.path(OUT, "in", sprintf("sat_%s_%s.ply", pid, rung))
        laz_to_ply(clip$rawground, ply)
        rows[[length(rows) + 1L]] <- data.frame(
          site = site, plot = pid, plotType = ci$plotType, rung = as.character(rung),
          pdens = clip$pdens, frdens = clip$frdens, spacing = s,
          r_scaled = sat_radius(clip$pdens, ARMS[["scaled"]]),
          r_double = sat_radius(clip$pdens, ARMS[["double"]]),
          ply = ply, dtm = clip$dtm, cx = cx, cy = cy, ph = ph)
      }
    }
  }
  m <- do.call(rbind, rows)
  write.csv(m, file.path(OUT, "manifest.csv"), row.names = FALSE)
  # Every cell in both arms, after the control: the upstream radius on the
  # first SOAP cell at 1 point/m2 and the first TEAK cell at 2 points/m2.
  cell <- sprintf("%s_%s", m$plot, m$rung)
  jobs <- rbind(
    data.frame(job = paste0(cell, "__scaled"), ply = m$ply, radius = sprintf("%.4f", m$r_scaled)),
    data.frame(job = paste0(cell, "__double"), ply = m$ply, radius = sprintf("%.4f", m$r_double)))
  ctl <- c(which(m$site == "SOAP" & m$rung == "1")[1], which(m$site == "TEAK" & m$rung == "2")[1])
  jobs <- rbind(data.frame(job = paste0(cell[ctl], "__default"), ply = m$ply[ctl], radius = ""), jobs)
  write.table(jobs, file.path(OUT, "jobs.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
  print(m[, c("site", "plot", "plotType", "rung", "pdens", "frdens", "spacing",
              "r_scaled", "r_double")], digits = 3)
  cat(sprintf("%d cells, %d jobs -> %s\n", nrow(m), nrow(jobs), OUT))
}

# Chance agreement of one cell as analyze_forestmamba.R's fma_null_counts and
# paper_sensitivity.R MODE=null score it: the mean counts over the same 200
# toroidal shifts per plot, at least 8 m, matched at 4 m.
null_counts <- function(stems, det, cx, cy, ph, site, plot, K = 200, tol = 4, min_shift = 8) {
  counts <- function(x) {
    sc <- score_plot(stems, x, tol_xy = tol, core_cx = cx, core_cy = cy, core_half = ph)
    c(n_ref = sc$n_ref, n_det = sc$n_det, TP = sc$TP,
      tp_core = if (sc$n_det > 0) round(sc$precision * sc$n_det) else 0)
  }
  shifted <- vapply(seq_len(K), function(k) counts(shift_detections(det, cx, cy, ph + tol,
    null_offset(2 * (ph + tol), seed_for(site, plot, "null") + k, min_shift = min_shift))),
    numeric(4))
  rowMeans(shifted)
}

# Core points of an instance cloud: tree-labelled, grouped into an instance,
# and the instances they form; and the instances whose outline (the convex hull
# of their core points) holds two or more mapped reference stems, with the
# grouped points in them.
# Points (px, py) inside the polygon with vertices (vx, vy), even-odd rule.
in_polygon <- function(px, py, vx, vy) {
  inside <- logical(length(px)); j <- length(vx)
  for (i in seq_along(vx)) {
    cross <- ((vy[i] > py) != (vy[j] > py)) &
      (px < (vx[j] - vx[i]) * (py - vy[i]) / (vy[j] - vy[i]) + vx[i])
    inside <- xor(inside, cross); j <- i
  }
  inside
}
GROUP_KEYS <- c("n_core", "n_tree", "n_tree_assigned", "n_assigned", "n_inst",
                "n_inst_2stems", "n_assigned_2stems", "max_stems")
grouping_counts <- function(las, cx, cy, ph, stems) {
  p <- suppressWarnings(lidR::readLAS(las))@data
  core <- abs(p$X - cx) <= ph & abs(p$Y - cy) <= ph
  tree <- p$PredSemantic[core] == 1; inst <- p$PredInstance[core]
  grouped <- !is.na(inst) & inst > 0
  ids <- inst[grouped]
  x <- p$X[core][grouped]; y <- p$Y[core][grouped]
  n_stems <- vapply(unique(ids), function(id) {
    k <- ids == id
    if (sum(k) < 3 || !nrow(stems)) return(0L)
    h <- grDevices::chull(x[k], y[k])
    sum(in_polygon(stems$E, stems$N, x[k][h], y[k][h]))
  }, integer(1))
  multi <- unique(ids)[n_stems >= 2]
  c(n_core = sum(core), n_tree = sum(tree), n_tree_assigned = sum(tree & grouped),
    n_assigned = length(ids), n_inst = length(unique(ids)),
    n_inst_2stems = length(multi), n_assigned_2stems = sum(ids %in% multi),
    max_stems = if (length(n_stems)) max(n_stems) else 0L)
}

# A job's log holds the shim's line for exactly its radius; the control's log
# holds no override line.
SHIM_LINE <- "sat_compat: region_grow radius"
log_ok <- function(log, radius) {
  if (!file.exists(log)) return(FALSE)
  txt <- readLines(log, warn = FALSE)
  if (nzchar(radius)) any(grepl(sprintf("%s %s m", SHIM_LINE, radius), txt, fixed = TRUE))
  else !any(grepl(SHIM_LINE, txt, fixed = TRUE))
}

f1 <- function(TP, n_ref, tp_core, n_det) {
  r <- sum(TP) / sum(n_ref); p <- if (sum(n_det) > 0) sum(tp_core) / sum(n_det) else NA
  c(recall = r, precision = p, F1 = if (is.na(p) || r + p == 0) 0 else 2 * r * p / (r + p))
}
pool <- function(x) {
  o <- f1(x$TP, x$n_ref, x$tp_core, x$n_det)
  z <- f1(x$null_TP, x$n_ref, x$null_tp_core, x$null_n_det)[["F1"]]
  c(n_cells = nrow(x), n_ref = sum(x$n_ref), n_det = sum(x$n_det), o,
    F1_null = z, F1_corr = (o[["F1"]] - z) / (1 - z))
}

score <- function() {
  m    <- read.csv(file.path(OUT, "manifest.csv"), stringsAsFactors = FALSE)
  jobs <- read.delim(file.path(OUT, "jobs.tsv"), stringsAsFactors = FALSE, colClasses = "character")
  m$cell <- sprintf("%s_%s", m$plot, m$rung)
  gts <- list()
  stems_of <- function(site, pid, cx, cy, ph) {
    if (is.null(gts[[site]])) {
      gt <- read.csv(file.path(RUNS, "neon", site, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
      gts[[site]] <<- frozen_scope(RUNS, site, list(POP = "adopted"), gt)$gt
    }
    g <- gts[[site]]
    g[g$plotID == pid & abs(g$E - cx) <= ph & abs(g$N - cy) <= ph, ]
  }

  rows <- list()
  for (i in seq_len(nrow(jobs))) {
    las <- file.path(OUT, "out", paste0(jobs$job[i], ".las"))
    if (!file.exists(las)) stop("no output for job ", jobs$job[i], "; run gpu/run_sat_radius_check.sh")
    if (!log_ok(file.path(OUT, "logs", paste0(jobs$job[i], ".log")), jobs$radius[i]))
      stop("the log of job ", jobs$job[i], " does not show the radius it should have run with")
    cell <- sub("__.*$", "", jobs$job[i]); arm <- sub("^.*__", "", jobs$job[i])
    c1 <- m[m$cell == cell, ]
    det_abs <- read_instances_laz(las, id_field = "PredInstance")
    if (is.null(det_abs)) stop("no PredInstance in ", las)
    det <- det_to_agl(det_abs, c1$dtm)
    stems <- stems_of(c1$site, c1$plot, c1$cx, c1$cy, c1$ph)
    sc <- score_plot(stems, det, tol_xy = 4, core_cx = c1$cx, core_cy = c1$cy, core_half = c1$ph)
    nc <- null_counts(stems, det, c1$cx, c1$cy, c1$ph, c1$site, c1$plot)
    rows[[length(rows) + 1L]] <- data.frame(
      site = c1$site, plot = c1$plot, rung = c1$rung, arm = arm,
      radius = if (nzchar(jobs$radius[i])) as.numeric(jobs$radius[i]) else 1.5 * GRID,
      n_ref = sc$n_ref, n_det = sc$n_det, TP = sc$TP,
      tp_core = if (sc$n_det > 0) round(sc$precision * sc$n_det) else 0,
      recall = sc$recall, precision = sc$precision, F1 = sc$F1,
      null_TP = nc[["TP"]], null_tp_core = nc[["tp_core"]], null_n_det = nc[["n_det"]],
      t(grouping_counts(las, c1$cx, c1$cy, c1$ph, stems)))
  }
  S <- do.call(rbind, rows)

  # The paper's rows and null cells on the same cells.
  ref <- list()
  for (site in unique(m$site)) {
    nd <- file.path(RUNS, "neon", site)
    for (f in c("segmentanytree_results.csv", "forestformer3d_results.csv", "lidrplugins_results.csv")) {
      x <- read.csv(file.path(nd, f), stringsAsFactors = FALSE)
      x <- x[x$detector %in% c("segmentanytree", "forestformer3d", "multichm", "chm_vwf"), ]
      x <- x[sprintf("%s_%s", x$plot, x$rung) %in% m$cell, ]
      if (is.null(x$tp_core)) x$tp_core <- round(x$precision * x$n_det)
      x$tp_core[x$n_det == 0] <- 0
      ref[[length(ref) + 1L]] <- data.frame(site = x$site, plot = x$plot, rung = as.character(x$rung),
        arm = ifelse(x$detector == "segmentanytree", "zero_shot", x$detector), radius = NA,
        n_ref = x$n_ref, n_det = x$n_det, TP = x$TP, tp_core = x$tp_core,
        recall = x$recall, precision = x$precision, F1 = x$F1)
    }
  }
  R <- do.call(rbind, ref)
  nul <- read.csv(file.path(RUNS, "sensitivity", "null_cells.csv"), stringsAsFactors = FALSE)
  nul <- nul[nul$variant == "null", ]
  nul$arm <- ifelse(nul$detector == "segmentanytree", "zero_shot", nul$detector)
  k <- match(paste(R$plot, R$rung, R$arm), paste(nul$plot, nul$rung, nul$arm))
  if (anyNA(k)) stop("comparison cells without a null row")
  R$null_TP <- nul$TP[k]; R$null_tp_core <- nul$tp_core[k]; R$null_n_det <- nul$n_det[k]
  # The zero-shot instance clouds the paper persisted, for the grouping counts.
  g0 <- t(vapply(seq_len(nrow(R)), function(i) {
    if (R$arm[i] != "zero_shot") return(rep(NA_real_, length(GROUP_KEYS)))
    c1 <- m[m$cell == sprintf("%s_%s", R$plot[i], R$rung[i]), ]
    las <- file.path(RUNS, "neon", c1$site, "segmentanytree_instances",
                     sprintf("%s_%s.laz", c1$plot, c1$rung))
    grouping_counts(las, c1$cx, c1$cy, c1$ph, stems_of(c1$site, c1$plot, c1$cx, c1$cy, c1$ph))
  }, numeric(length(GROUP_KEYS))))
  colnames(g0) <- GROUP_KEYS
  R <- cbind(R, g0)
  A <- rbind(S, R)
  write.csv(A, file.path(OUT, "scores.csv"), row.names = FALSE)

  # Control: the upstream radius re-run must reproduce the paper's rows.
  z <- merge(S[S$arm == "default", ], R[R$arm == "zero_shot", ], by = c("plot", "rung"),
             suffixes = c("_rerun", "_paper"))
  keys <- c("TP", "n_det", "tp_core", "null_TP", "null_tp_core", "null_n_det")
  z <- z[, c("plot", "rung", as.vector(rbind(paste0(keys, "_rerun"), paste0(keys, "_paper"))))]
  z$identical <- vapply(seq_len(nrow(z)), function(i)
    all(abs(unlist(z[i, paste0(keys, "_rerun")]) - unlist(z[i, paste0(keys, "_paper")])) < 1e-9),
    logical(1))
  write.csv(z, file.path(OUT, "control.csv"), row.names = FALSE)
  cat("== control: upstream radius re-run against the paper's rows\n"); print(z, digits = 4)
  if (nrow(z) != sum(S$arm == "default") || !all(z$identical))
    stop("the control does not reproduce the paper's rows (control.csv); the check is void")

  arms <- c("zero_shot", "scaled", "double", "forestformer3d", "multichm", "chm_vwf")
  out <- list(); boot <- list(); grp <- list()
  for (rg in c("2", "1")) {
    plots <- intersect(unique(S$plot[S$rung == rg & S$arm == "scaled"]),
                       unique(S$plot[S$rung == rg & S$arm == "double"]))
    for (a in arms) {
      x <- A[A$rung == rg & A$arm == a & A$plot %in% plots, ]
      out[[length(out) + 1L]] <- data.frame(rung = rg, arm = a, t(pool(x)))
      if (a %in% c("zero_shot", "scaled", "double")) {
        s <- colSums(x[, GROUP_KEYS]); s[["max_stems"]] <- max(x$max_stems)
        grp[[length(grp) + 1L]] <- data.frame(rung = rg, arm = a, t(s),
          tree_share = s[["n_tree"]] / s[["n_core"]],
          assigned_of_tree = s[["n_tree_assigned"]] / s[["n_tree"]],
          points_per_instance = s[["n_assigned"]] / s[["n_inst"]],
          share_inst_2stems = s[["n_inst_2stems"]] / s[["n_inst"]],
          share_assigned_2stems = s[["n_assigned_2stems"]] / s[["n_assigned"]])
      }
    }
  }
  # Paired plot bootstrap of the F1 and corrected-F1 differences, by level.
  set.seed(SEED)
  for (rg in c("2", "1")) {
    plots <- intersect(unique(S$plot[S$rung == rg & S$arm == "scaled"]),
                       unique(S$plot[S$rung == rg & S$arm == "double"]))
    get <- function(a) { x <- A[A$rung == rg & A$arm == a, ]; x[match(plots, x$plot), ] }
    for (pair in list(c("scaled", "zero_shot"), c("double", "zero_shot"), c("scaled", "forestformer3d"),
                      c("scaled", "multichm"), c("double", "forestformer3d"), c("double", "multichm"))) {
      xa <- get(pair[1]); xb <- get(pair[2])
      if (anyNA(xa$TP) || anyNA(xb$TP)) stop("missing cells for ", paste(pair, collapse = " - "))
      dd <- replicate(N_BOOT, { i <- sample(length(plots), replace = TRUE)
        a <- pool(xa[i, ]); b <- pool(xb[i, ])
        c(a[["F1"]] - b[["F1"]], a[["F1_corr"]] - b[["F1_corr"]]) })
      a <- pool(xa); b <- pool(xb)
      boot[[length(boot) + 1L]] <- data.frame(rung = rg, contrast = paste(pair, collapse = " - "),
        F1 = a[["F1"]] - b[["F1"]], lower = quantile(dd[1, ], 0.025), upper = quantile(dd[1, ], 0.975),
        F1_corr = a[["F1_corr"]] - b[["F1_corr"]], corr_lower = quantile(dd[2, ], 0.025, na.rm = TRUE),
        corr_upper = quantile(dd[2, ], 0.975, na.rm = TRUE))
    }
  }
  # Baseline: the paper's zero-shot clouds of the same plots at the denser levels.
  pl <- m[!duplicated(m$plot), ]
  for (rg in c("native", "8", "4")) {
    x <- t(vapply(seq_len(nrow(pl)), function(i) {
      las <- file.path(RUNS, "neon", pl$site[i], "segmentanytree_instances",
                       sprintf("%s_%s.laz", pl$plot[i], rg))
      if (!file.exists(las)) stop("no zero-shot instance cloud ", las)
      grouping_counts(las, pl$cx[i], pl$cy[i], pl$ph[i],
                      stems_of(pl$site[i], pl$plot[i], pl$cx[i], pl$cy[i], pl$ph[i]))
    }, numeric(length(GROUP_KEYS))))
    colnames(x) <- GROUP_KEYS
    s <- colSums(x); s[["max_stems"]] <- max(x[, "max_stems"])
    grp[[length(grp) + 1L]] <- data.frame(rung = rg, arm = "zero_shot", t(s),
      tree_share = s[["n_tree"]] / s[["n_core"]],
      assigned_of_tree = s[["n_tree_assigned"]] / s[["n_tree"]],
      points_per_instance = s[["n_assigned"]] / s[["n_inst"]],
      share_inst_2stems = s[["n_inst_2stems"]] / s[["n_inst"]],
      share_assigned_2stems = s[["n_assigned_2stems"]] / s[["n_assigned"]])
  }
  P <- do.call(rbind, out); B <- do.call(rbind, boot); G <- do.call(rbind, grp)
  rownames(P) <- rownames(B) <- rownames(G) <- NULL
  write.csv(P, file.path(OUT, "summary.csv"), row.names = FALSE)
  write.csv(B, file.path(OUT, "contrasts.csv"), row.names = FALSE)
  write.csv(G, file.path(OUT, "grouping.csv"), row.names = FALSE)
  cat("\n== pooled per level and arm\n"); print(P, digits = 3)
  cat("\n== paired plot bootstrap, differences\n"); print(B, digits = 3)
  cat("\n== grouping, core points pooled\n"); print(G, digits = 3)
}

if (sys.nframe() == 0L) {
  if (is.null(RUNS)) stop("RUNS=<job directory of the paper runs> is required")
  switch(MODE, prep = prep(), score = score(), stop("MODE must be prep or score"))
}
