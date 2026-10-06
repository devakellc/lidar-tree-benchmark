#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)

# One classical detector on one native frozen cell, timed alone: the
# detector's own function from its sweep script (sourced without running the
# sweep), single-threaded, on the cell the paper runs read. Prints one CSV
# row: arm, site, plot, points, detection seconds, apexes. compute_cost.sh
# wraps it in /usr/bin/time for the peak resident memory.
#   Rscript scripts/compute_cost_cell.R ARM=<arm> SITE=<site> PLOT=<plot>
#     [FROZEN_ROOT=...]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
ARGS <- A
ARM <- A$ARM; SITE <- A$SITE; PLOT <- A$PLOT
CLASSICAL <- c(lmfauto = "detect_lidrplugins_sweep.R", multichm = "detect_lidrplugins_sweep.R",
               ptrees = "detect_lidrplugins_sweep.R", chm_vwf = "detect_lidrplugins_sweep.R",
               ams3d = "detect_ams3d_sweep.R", li2012 = "detect_li2012_native.R")
if (is.null(ARM) || !ARM %in% names(CLASSICAL)) stop("ARM must be one of ", paste(names(CLASSICAL), collapse = ", "))
suppressMessages({ library(lidR); library(lidRplugins) })
source(.find(CLASSICAL[[ARM]]))             # functions only: the sweep runs under sys.nframe() == 0
A <- ARGS; ARM <- A$ARM; SITE <- A$SITE; PLOT <- A$PLOT  # the sweep's own argument parsing may reassign these
lidR::set_lidr_threads(1L)

d <- .job_dir()
root <- frozen_root(d, A$FROZEN_ROOT)
pop <- read.csv(file.path(root, "population.csv"), stringsAsFactors = FALSE)
ci <- pop[pop$site == SITE & pop$plotID == PLOT, ][1, ]
cell <- frozen_clip(NULL, SITE, PLOT, NA, ci$easting, ci$northing, ci$core_half, root)
las <- readLAS(cell$normalized)
res <- if (cell$frdens >= 8) 0.25 else 0.5
call <- switch(ARM,
  lmfauto  = function() det_lmfauto(las, hmin = 2),
  multichm = function() det_multichm(las, res = res, a = 0.10),
  ptrees   = function() det_ptrees(las, hmin = 2),
  chm_vwf  = function() detect_lasr(cell$normalized, res, 0.10, cell$frdens),
  ams3d    = function() det_ams3d(las),
  li2012   = function() det_li2012(las, hmin = 2))
t0 <- proc.time()[["elapsed"]]
det <- call()
secs <- proc.time()[["elapsed"]] - t0
cat(sprintf("COST,%s,%s,%s,%d,%.3f,%d\n", ARM, SITE, PLOT, npoints(las), secs,
            if (is.null(det)) 0L else nrow(det)))
