#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(lidR); library(sf); library(data.table); library(parallel) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))           # plot_lapply
source(.find("model_bench_lib.R"))     # frozen_read, frozen_clip_manifest
source(.find("sparse_epoch_lib.R"))    # se_common_plots
source(.find("multichm_gated_lib.R"))  # mcg_canopy_cover, mcg_crowns, mcg_top_height, MCG_DECLARED

# Score-blind stand measures of a native epoch's sealed root beside the 2021
# root on the same plots. For every "ok" cell of the epoch root (native and
# decimated rungs) and the 2021 native cell of each of its plots: canopy cover
# (mcg_canopy_cover), crowns (mcg_crowns: number, interior area and spacing)
# and top height (mcg_top_height), all with the frozen multichm_gated library
# as the calibration study calls it on the normalized clip, plus the clip's
# all-return and first-return density (pdens, frdens, from the freeze) and
# returns per pulse (pdens / frdens), and the share of its scoring core that
# holds first returns (se_core_cover; below 1 at the edge of a flight). A clip is closed when its cover reaches
# MCG_DECLARED's cover_min and widely spaced when its crown spacing reaches its
# spacing_min (mcg_closed, mcg_spaced). No detector runs and no stem is read;
# the shared-stem directories of compare_sparse_epoch.R, when present, only
# flag which plots hold shared stems. Writes to OUT:
#   cells.csv         one row per measured cell
#   side_by_side.csv  one row per plot with an epoch native clip, its 2021
#                     native values beside it
#   summary.csv       per site, on the plots adopted in both roots with a
#                     native clip in both (and on those holding shared stems):
#                     medians and counts of closed and widely spaced plots
#   Rscript scripts/epoch_stand_measures.R EPOCHS=WREF:<job dir>:2019,ABBY:<job dir>:2019 \
#     [ROOT2021=<work>/neon/frozen_2021] [OUT=<first job dir>/stand_measures] [CORES=4]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$EPOCHS)) stop("EPOCHS=SITE:<job dir>:<year>[,...] is required")
ep <- do.call(rbind, lapply(strsplit(strsplit(A$EPOCHS, ",")[[1]], ":"), function(x)
  data.frame(site = x[1], job = x[2], year = as.integer(x[3]), stringsAsFactors = FALSE)))
root21 <- if (is.null(A$ROOT2021)) file.path(.job_dir(), "neon", "frozen_2021") else A$ROOT2021
out <- if (is.null(A$OUT)) file.path(ep$job[1], "stand_measures") else A$OUT
CORES <- as.integer(if (is.null(A$CORES)) 4 else A$CORES)
dir.create(out, recursive = TRUE, showWarnings = FALSE)
sroot <- function(i) file.path(ep$job[i], "neon", sprintf("frozen_%d", ep$year[i]))

## ---- the cells ------------------------------------------------------------------------
pop21 <- read.csv(file.path(root21, "population.csv"), stringsAsFactors = FALSE)
cm21 <- frozen_clip_manifest(root21)
jobs <- list(); plots <- list()
for (i in seq_len(nrow(ep))) {
  s <- ep$site[i]; root <- sroot(i)
  popS <- read.csv(file.path(root, "population.csv"), stringsAsFactors = FALSE)
  cmS <- frozen_clip_manifest(root)
  sh <- file.path(ep$job[i], "compare_shared", "neon", s, "ground_truth_stems.csv")
  shared <- if (file.exists(sh)) unique(read.csv(sh, stringsAsFactors = FALSE)$plotID)
  common <- se_common_plots(pop21, popS, s, cm21, cmS)
  p <- popS[popS$site == s, c("site", "plotID", "plotType", "in_adopted")]
  names(p)[4] <- "adopted_epoch"
  p$adopted_2021 <- p$plotID %in% pop21$plotID[pop21$site == s & pop21$in_adopted]
  p$common <- p$plotID %in% common
  p$shared <- if (is.null(shared)) NA else p$plotID %in% shared
  plots[[s]] <- p
  add <- function(cm, side, root) for (k in seq_len(nrow(cm)))
    jobs[[length(jobs) + 1L]] <<- list(side = side, root = root, row = cm[k, ])
  add(cmS[cmS$site == s & cmS$status == "ok", ], as.character(ep$year[i]), root)
  add(cm21[cm21$site == s & cm21$rung == "native" & cm21$status == "ok" &
             cm21$plot %in% p$plotID, ], "2021", root21)
}
plots <- do.call(rbind, plots)

measure <- function(j) {
  r <- j$row
  clip <- frozen_read(j$root, r$site, r$plot, r$rung, r$cx, r$cy, r$core_half, r$buffer)
  las <- lidR::readLAS(clip$normalized)
  crowns <- mcg_crowns(las)
  f <- las$ReturnNumber == 1L
  data.frame(side = j$side, site = r$site, plot = r$plot, rung = r$rung,
             pdens = clip$pdens, frdens = clip$frdens, returns_per_pulse = clip$pdens / clip$frdens,
             core_cover = se_core_cover(las$X[f], las$Y[f], r$cx, r$cy, r$core_half),
             cover = mcg_canopy_cover(las), top_height = mcg_top_height(las),
             n_crowns = crowns$n, crown_area = crowns$area, crown_spacing = crowns$spacing,
             stringsAsFactors = FALSE)
}
t0 <- Sys.time()
res <- plot_lapply(jobs, measure, mc.cores = CORES)
cells <- do.call(rbind, res)
cells$closed <- vapply(cells$cover, mcg_closed, logical(1), cfg = MCG_DECLARED)
cells$spaced <- vapply(cells$crown_spacing, mcg_spaced, logical(1), cfg = MCG_DECLARED)
cells$gated <- cells$closed & cells$spaced
cells <- merge(cells, plots, by.x = c("site", "plot"), by.y = c("site", "plotID"), all.x = TRUE)
cells <- cells[order(match(cells$site, ep$site), cells$plot, cells$side != "2021",
                     match(cells$rung, c("native", FROZEN_RUNGS))), ]
write.csv(cells, file.path(out, "cells.csv"), row.names = FALSE)
cat(sprintf("measured %d cells (%.1f min)\n", nrow(cells),
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

## ---- native beside 2021 native ----------------------------------------------------------
vars <- c("pdens", "frdens", "returns_per_pulse", "core_cover", "cover", "top_height", "n_crowns",
          "crown_area", "crown_spacing", "closed", "spaced", "gated")
nat <- cells[cells$rung == "native", ]
e <- nat[nat$side != "2021", c("site", "plot", "plotType", "adopted_epoch", "adopted_2021",
                               "common", "shared", "side", vars)]
names(e)[names(e) == "side"] <- "epoch"
c2 <- nat[nat$side == "2021", c("site", "plot", vars)]
names(e)[names(e) %in% vars] <- paste0(vars, "_epoch")
names(c2)[names(c2) %in% vars] <- paste0(vars, "_2021")
sbs <- merge(e, c2, by = c("site", "plot"), all.x = TRUE)
sbs$closed_differs <- sbs$closed_epoch != sbs$closed_2021
sbs$gated_differs <- sbs$gated_epoch != sbs$gated_2021
sbs <- sbs[order(match(sbs$site, ep$site), sbs$plot), ]
write.csv(sbs, file.path(out, "side_by_side.csv"), row.names = FALSE)

## ---- per site summary -------------------------------------------------------------------
med <- function(v) if (length(v)) stats::median(v, na.rm = TRUE) else NA_real_
summ <- function(x, scope) {
  rr <- function(r) {
    y <- cm21[cm21$site == x$site[1] & cm21$rung == r & cm21$status == "ok" &
                cm21$plot %in% x$plot, ]
    med(y$frdens)
  }
  data.frame(site = x$site[1], epoch = x$epoch[1], scope = scope, plots = nrow(x),
    frdens_epoch = med(x$frdens_epoch), frdens_2021 = med(x$frdens_2021),
    frdens_2021_rung8 = rr("8"), frdens_2021_rung4 = rr("4"),
    pdens_epoch = med(x$pdens_epoch), pdens_2021 = med(x$pdens_2021),
    returns_per_pulse_epoch = med(x$returns_per_pulse_epoch),
    returns_per_pulse_2021 = med(x$returns_per_pulse_2021),
    cover_epoch = med(x$cover_epoch), cover_2021 = med(x$cover_2021),
    crown_spacing_epoch = med(x$crown_spacing_epoch), crown_spacing_2021 = med(x$crown_spacing_2021),
    closed_epoch = sum(x$closed_epoch, na.rm = TRUE), closed_2021 = sum(x$closed_2021, na.rm = TRUE),
    spaced_epoch = sum(x$spaced_epoch, na.rm = TRUE), spaced_2021 = sum(x$spaced_2021, na.rm = TRUE),
    gated_epoch = sum(x$gated_epoch, na.rm = TRUE), gated_2021 = sum(x$gated_2021, na.rm = TRUE),
    closed_differs = sum(x$closed_differs, na.rm = TRUE),
    gated_differs = sum(x$gated_differs, na.rm = TRUE), stringsAsFactors = FALSE)
}
sm <- list()
for (s in ep$site) {
  x <- sbs[sbs$site == s, ]
  sm[[paste(s, "common")]] <- summ(x[x$common, ], "adopted in both, native clip in both")
  if (!all(is.na(x$shared)))
    sm[[paste(s, "shared")]] <- summ(x[x$common & x$shared %in% TRUE, ], "holding shared stems")
}
sm <- do.call(rbind, sm); rownames(sm) <- NULL
write.csv(sm, file.path(out, "summary.csv"), row.names = FALSE)
print(sm, row.names = FALSE, digits = 3)
cat(sprintf("closed: cover >= %g; widely spaced: crown spacing >= %g m (MCG_DECLARED)\n",
            MCG_DECLARED$cover_min, MCG_DECLARED$spacing_min))
