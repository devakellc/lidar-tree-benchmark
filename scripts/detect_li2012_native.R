#!/usr/bin/env Rscript
.bs_ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (!is.null(.bs_ofile) && length(.bs_ofile) && nzchar(.bs_ofile))
    file.path(dirname(.bs_ofile), "bootstrap.R"),
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])),
                                  "bootstrap.R"),
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_ofile, .bs_file)

# Native-only Li 2012 arm (#R10) of the NEON model benchmark. Runs lidR's
# li2012 point-cloud segmenter on the SAME native frozen clip per plot (the
# sealed root from freeze_clips.R, over its declared population),
# collapses per-point treeID through the bridge's reduce_instances(), and
# scores against field stems with the existing harness. Native-only by design:
# li2012 is the dense-input sub-canopy test; decimated rungs are meaningless for
# a point segmenter, and CHM-VWF/ptrees/ams3d already carry the full ladder.
#
# Usage:  Rscript scripts/detect_li2012_native.R [SITE=SOAP] [PLOTS=ALL]
#             [CORES=6] [TOL=4] [POP=adopted] [FROZEN_ROOT=...]
# Output: $CLAUDE_JOB_DIR/neon/<SITE>/li2012_results.csv (one row per plot,
#         detector "li2012", rung "native").
suppressMessages({ library(lidR); library(data.table); library(parallel) })
options(lidR.progress = FALSE)
d <- .job_dir()
.find <- function(rel) Find(file.exists, c(file.path("scripts", rel),
                                           file.path("..", "..", "scripts", rel),
                                           file.path(getwd(), "scripts", rel)))
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
source(.find("io_bridge.R"))        # write_instances_laz (#V6)

# li2012 on a normalized clip -> per-point treeID -> reduce_instances apex set.
# Guard the no-canopy case (parity with ptrees): too few returns above hmin
# means no trees anyway, so return a 0-row frame without entering the segmenter.
# inst_path (#V6): when set, the segmented cloud is persisted (treeID as an
# integer extra dim, 0 = unassigned) BEFORE the apex collapse, so the IoU/PQ
# board and mask-aware fusion can reuse the labelling.
det_li2012 <- function(las, hmin = 2, dt1 = 1.5, dt2 = 2, R = 2,
                       inst_path = NULL) {
  empty <- data.frame(x = numeric(), y = numeric(), z = numeric())
  if (sum(las$Z >= hmin) < 1) { assert_detection_contract(empty); return(empty) }
  seg <- tryCatch(lidR::segment_trees(las,
                    lidR::li2012(dt1 = dt1, dt2 = dt2, R = R, hmin = hmin)),
                  error = function(e) NULL)
  if (is.null(seg)) return(NULL)               # crash -> skip (guard drops cell)
  if (!"treeID" %in% names(seg@data)) return(NULL)
  if (!is.null(inst_path))
    tryCatch(write_instances_laz(seg, inst_path, id_col = "treeID"),
             error = function(e) warning("instance persist failed: ",
                                         conditionMessage(e), call. = FALSE))
  det <- reduce_instances(seg@data, id_col = "treeID", x = "X", y = "Y", z = "Z")
  assert_detection_contract(det)
  det
}

args  <- strsplit(commandArgs(TRUE), "=")
A     <- setNames(lapply(args, `[`, 2), sapply(args, `[`, 1))
SITE  <- if (is.null(A$SITE))  "SOAP" else A$SITE
PLOTS <- if (is.null(A$PLOTS) || A$PLOTS == "ALL") NULL else strsplit(A$PLOTS, ",")[[1]]
CORES <- as.integer(if (is.null(A$CORES)) 6 else A$CORES)
TOL   <- as.numeric(if (is.null(A$TOL)) 4.0 else A$TOL)

run_main <- function() {
  nd  <- file.path(d, "neon", SITE)
  gt  <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc  <- read.csv(file.path(nd, "plot_centroids.csv"),     stringsAsFactors = FALSE)
  fz  <- frozen_scope(d, SITE, A, gt)     # declared population + sealed root
  gt  <- fz$gt
  invisible(neon_validate_inputs(gt, pc))
  keep   <- fz$plots
  if (!is.null(PLOTS)) keep <- intersect(keep, PLOTS)
  keep   <- intersect(keep, pc$plotID)
  cat(sprintf("[%s] li2012 plots (%s): %d (%s)\n", SITE, fz$population, length(keep),
              paste(keep, collapse = ",")))
  # Instance clouds record the sealed root that made them; a directory made on
  # other clips must be moved aside first.
  frozen_stamp(file.path(nd, "li2012_instances"), fz$root)

  run_plot <- function(pid) {
    ci <- pc[pc$plotID == pid, ][1, ]
    cx <- ci$easting; cy <- ci$northing
    ph <- plot_half(ci$plotType)
    stems <- gt[gt$plotID == pid & abs(gt$E - cx) <= ph & abs(gt$N - cy) <= ph, ]
    if (nrow(stems) < 1) return(NULL)
    prep <- frozen_clip(NULL, SITE, pid, NA, cx, cy, ph, fz$root)
    if (is.null(prep)) return(NULL)
    las <- tryCatch(readLAS(prep$normalized), error = function(e) NULL)
    if (is.null(las) || is.empty(las)) return(NULL)
    det <- det_li2012(las, hmin = 2,
                      inst_path = file.path(nd, "li2012_instances",
                                            paste0(pid, "_native.laz")))
    if (is.null(det)) return(NULL)
    sc <- tryCatch(score_plot(stems, det, tol_xy = TOL, core_cx = cx,
                              core_cy = cy, core_half = ph),
                   error = function(e) NULL)
    if (is.null(sc)) return(NULL)
    cbind(data.frame(site = SITE, plot = pid, plotType = ci$plotType,
                     detector = "li2012", rung = "native",
                     pdens = round(prep$pdens, 2), frdens = round(prep$frdens, 2),
                     n_apex = nrow(det)), sc)
  }

  res_list <- plot_lapply(keep, function(p)
                tryCatch(run_plot(p), error = function(e) {
                  message("plot ", p, " failed: ", conditionMessage(e)); e }),
                mc.cores = CORES, mc.preschedule = FALSE)
  # A failed plot (e.g. a frozen cell that no longer matches its hash) must not
  # leave the population silently smaller.
  stop_failed_plots(keep, res_list)
  results <- do.call(rbind, Filter(Negate(is.null), res_list))
  if (is.null(results) || !nrow(results)) { cat("no li2012 results\n"); return(invisible()) }
  results$tp_core <- round(results$precision * results$n_det)
  write.csv(results, file.path(nd, "li2012_results.csv"), row.names = FALSE)
  cat(sprintf("[%s] li2012 DONE: %d rows -> %s\n", SITE, nrow(results),
              file.path(nd, "li2012_results.csv")))
}

if (sys.nframe() == 0L) run_main()
