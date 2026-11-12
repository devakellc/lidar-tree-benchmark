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

# multichm_gated tree-top arm of the NEON density ladder.
#
# lidRplugins::multichm (Eysn-style multi-layer CHM local maxima) with a gate on
# its deeper-layer candidates, switched on by canopy cover, and an optional
# exemption of the surface-layer peaks from the package's distance filter in
# closed stands (multichm_gated_lib.R holds the detector and its semantics).
# The loop mirrors detect_multichm_sweep.R: the SAME sealed frozen root and
# declared population, per plot x density rung {native, then the root's
# decimated rungs} with the same no-upsampling guard (rung target vs the plot's
# native all-return density), the plot-type-aware core (plot_half), the
# density-derived res (0.25 m at >= 8 first returns per m2, else 0.5 m) and the
# clamped variable window ws_factory(A). Like detect_lidrplugins_sweep.R it
# keeps the apexes it scored per cell for re-scoring without inference.
#
# Configuration (zmin, min_share, cover_min, surface_exempt), in order of
# precedence: explicit ZMIN= MIN_SHARE= COVER_MIN= SURFACE_EXEMPT= arguments
# (each overrides one field), the CONFIG= file (a declared_config.json written by
# calval_multichm_gated.R), then MCG_DECLARED, the configuration the
# calibration study selected on its calibration plots (multichm_gated_lib.R
# records its provenance). Without arguments or a CONFIG= file the run uses
# MCG_DECLARED; were it unset, all four arguments would be required and the
# run would stop before any work. The gate's form and the calibration grid
# were informed by an exploratory pass over all 106 frozen plots, and the
# selection criterion was fixed after that pass, so held-out scores test only
# the selection within that grid, not the grid's values or the choice of
# features.
#
# The stock configuration (ZMIN=0 MIN_SHARE=0 COVER_MIN=0 SURFACE_EXEMPT=FALSE)
# reproduces lidRplugins::multichm, so its detections equal the multichm arm's.
# Unlike the package, the library also handles a clip with a single candidate
# (the package crashes there and the multichm arm skips the cell). An
# unreadable or empty frozen clip, or a detector error, fails its plot, and a
# failed plot stops the run; the multichm arm skips such a cell without a
# record.
#
# Usage:
#   Rscript scripts/detect_multichm_gated_sweep.R [SITE=SOAP] [PLOTS=ALL]
#       [CORES=8] [TOL=4] [A=0.10] [POP=adopted] [FROZEN_ROOT=...]
#       [CONFIG=<declared_config.json>]
#       [ZMIN= MIN_SHARE= COVER_MIN= SURFACE_EXEMPT=]
# Output under $CLAUDE_JOB_DIR/neon/<SITE>/:
#   multichm_gated_results.csv          one row per plot x rung (the columns of
#                                       multichm_sweep_results.csv plus detector,
#                                       cover, closed and the configuration);
#   multichm_gated_results.csv.frozen   the sealed root and population;
#   multichm_gated_results.config.json  the configuration used;
#   multichm_gated_detections/          the apexes of every cell, stamped with
#                                       the sealed root and the configuration.
suppressMessages({ library(lidR); library(lidRplugins); library(sf)
                   library(data.table); library(parallel) })
options(lidR.progress = FALSE)
d <- .job_dir()
source(.find("sweep_lib.R"))           # plot_half, score_plot, ws_factory, plot_lapply
source(.find("model_bench_lib.R"))     # frozen_*, persist_detections, assert_detection_contract
source(.find("multichm_gated_lib.R"))  # detector, MCG_* constants, MCG_DECLARED

MCG_ARM <- "multichm_gated"
MCG_CONFIG_FIELDS <- c(zmin = "ZMIN", min_share = "MIN_SHARE", cover_min = "COVER_MIN",
                       surface_exempt = "SURFACE_EXEMPT")
# Configuration stamp of a detections directory: one directory holds the
# detections of one configuration only.
MCG_ARM_CONFIG_STAMP <- "multichm_gated_config.json"

## ---- configuration ---------------------------------------------------------
.mcg_arm_value <- function(v, key, field) {
  if (is.null(v) || length(v) != 1L || is.na(v) || !nzchar(v))
    stop(sprintf("multichm_gated: %s= needs a value", key), call. = FALSE)
  if (field == "surface_exempt") {
    u <- toupper(v)
    if (u %in% c("TRUE", "T", "1", "YES")) return(TRUE)
    if (u %in% c("FALSE", "F", "0", "NO")) return(FALSE)
    stop(sprintf("multichm_gated: %s= must be TRUE or FALSE, not '%s'", key, v), call. = FALSE)
  }
  x <- suppressWarnings(as.numeric(v))
  if (is.na(x)) stop(sprintf("multichm_gated: %s= must be a number, not '%s'", key, v),
                     call. = FALSE)
  x
}

# A declared configuration file: the four values at the top level. When it
# records the feature constants (radius, half_dz, cover_height), they must be
# the library's, or the declared thresholds would be applied to other features.
mcg_read_config_file <- function(path) {
  if (!file.exists(path)) stop("multichm_gated: CONFIG file not found: ", path, call. = FALSE)
  j <- jsonlite::read_json(path, simplifyVector = TRUE)
  miss <- setdiff(names(MCG_CONFIG_FIELDS), names(j))
  if (length(miss))
    stop(sprintf("multichm_gated: CONFIG file %s lacks %s", path, paste(miss, collapse = ", ")),
         call. = FALSE)
  const <- c(radius = MCG_RADIUS, half_dz = MCG_HALF_DZ, cover_height = MCG_COVER_HEIGHT)
  for (k in names(const)) if (!is.null(j[[k]]) &&
                              !isTRUE(all.equal(as.numeric(j[[k]]), const[[k]])))
    stop(sprintf("multichm_gated: CONFIG file %s was declared with %s = %s, but this library uses %s",
                 path, k, format(j[[k]]), format(const[[k]])), call. = FALSE)
  if (!is.logical(j$surface_exempt))
    stop("multichm_gated: surface_exempt in ", path, " must be true or false", call. = FALSE)
  list(zmin = as.numeric(j$zmin), min_share = as.numeric(j$min_share),
       cover_min = as.numeric(j$cover_min), surface_exempt = j$surface_exempt)
}

# The configuration of a run from the parsed KEY=VALUE args: explicit arguments
# override the CONFIG= file, which takes precedence over `declared`
# (MCG_DECLARED by default; NULL means no declared configuration). Returns
# list(cfg, source, file).
mcg_arm_config <- function(A, declared = MCG_DECLARED) {
  given <- MCG_CONFIG_FIELDS[vapply(MCG_CONFIG_FIELDS, function(k) k %in% names(A), logical(1))]
  file <- if ("CONFIG" %in% names(A)) A[["CONFIG"]] else NULL
  if (!is.null(file) && (is.na(file) || !nzchar(file)))
    stop("multichm_gated: CONFIG= needs a path", call. = FALSE)
  base <- if (!is.null(file)) mcg_read_config_file(file) else declared
  base_src <- if (!is.null(file)) "config file" else if (!is.null(declared)) "MCG_DECLARED"
  if (is.null(base) && length(given) < length(MCG_CONFIG_FIELDS)) {
    if (!length(given))
      stop("multichm_gated: no configuration: there is no declared configuration ",
           "(MCG_DECLARED); pass CONFIG=<declared_config.json> ",
           "or all of ZMIN= MIN_SHARE= COVER_MIN= SURFACE_EXEMPT= (the stock multichm is ",
           "ZMIN=0 MIN_SHARE=0 COVER_MIN=0 SURFACE_EXEMPT=FALSE)", call. = FALSE)
    stop("multichm_gated: without CONFIG= or MCG_DECLARED all four configuration arguments ",
         "are needed; missing ",
         paste0(setdiff(MCG_CONFIG_FIELDS, given), "=", collapse = " "), call. = FALSE)
  }
  cfg <- if (is.null(base)) list() else base
  for (f in names(given)) cfg[[f]] <- .mcg_arm_value(A[[given[[f]]]], given[[f]], f)
  cfg <- .mcg_check_config(cfg[names(MCG_CONFIG_FIELDS)])
  src <- if (is.null(base)) "arguments" else if (length(given)) paste(base_src, "+ arguments")
         else base_src
  list(cfg = cfg, source = src, file = file)
}

# Stamps a detections directory, before any detection is written, with
# everything that changes the apexes it holds: the configuration, the variable-
# window coefficient `a` (it changes the candidates) and the library's feature
# constants (radius, half_dz, cover_height). A directory that already holds
# detections stamped otherwise (or not stamped with all of these) must be moved
# aside first. The matching tolerance is not stamped: it changes the scores,
# not the detections.
mcg_arm_stamp_config <- function(dir, cfg, a) {
  cfg <- .mcg_check_config(cfg)
  if (!is.numeric(a) || length(a) != 1L || !is.finite(a) || a <= 0)
    stop("multichm_gated: the window coefficient a must be one finite number > 0", call. = FALSE)
  want <- c(cfg, list(a = as.numeric(a), radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                      cover_height = MCG_COVER_HEIGHT))
  f <- file.path(dir, MCG_ARM_CONFIG_STAMP)
  held <- list.files(dir, pattern = "\\.csv$")
  if (length(held)) {
    old <- if (file.exists(f)) tryCatch(jsonlite::read_json(f, simplifyVector = TRUE),
                                        error = function(e) NULL)
    same <- !is.null(old) && all(names(want) %in% names(old)) &&
      isTRUE(all.equal(lapply(old[names(want)], unname), want, tolerance = 1e-12))
    if (!same)
      stop(sprintf(paste0("multichm_gated: %s holds detections of another configuration, ",
                          "window coefficient or feature constants; move it aside to start fresh"),
                   dir), call. = FALSE)
  }
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(c(want, list(label = mcg_config_label(cfg))), f, auto_unbox = TRUE,
                       pretty = TRUE, digits = NA)
  invisible(f)
}

## ---- one cell ----------------------------------------------------------------
# Detects and scores one plot x rung clip. `meta` carries site, plot, plotType,
# rung (NA = native), cx, cy, half, pdens, frdens. Returns list(det, row, cover,
# closed): the x,y,z detections over the whole clip, one result row, the clip's
# canopy cover and whether the configuration treats it as a closed stand.
# `closed` is NA only where the cover is unknown and decided nothing (no
# candidates, or a configuration that does not read it); mcg_apply() has
# already stopped where an unknown cover would decide a candidate.
mcg_arm_cell <- function(las, stems, meta, cfg, a = 0.10, tol = 4) {
  cfg <- .mcg_check_config(cfg)
  res <- if (meta$frdens >= 8) 0.25 else 0.5     # density-derived, like CHM-VWF
  prep <- mcg_prepare(las, res, a)                # detect_multichm_gated(), in two steps
  det <- mcg_apply(prep, cfg)                     # so the cover is reported with it
  closed <- mcg_closed(prep$cover, cfg)
  sc <- score_plot(stems, det, tol_xy = tol, core_cx = meta$cx, core_cy = meta$cy,
                   core_half = meta$half)
  row <- cbind(data.frame(site = meta$site, plot = meta$plot, plotType = meta$plotType,
                          detector = MCG_ARM,
                          rung = ifelse(is.na(meta$rung), "native", as.character(meta$rung)),
                          pdens = round(meta$pdens, 2), frdens = round(meta$frdens, 2),
                          chm_res = res, n_apex = nrow(det), stringsAsFactors = FALSE), sc)
  list(det = det, row = row, cover = prep$cover, closed = closed)
}

# Adds the recovered core true positives and the stand/configuration columns.
mcg_arm_finish <- function(results, cfg) {
  cfg <- .mcg_check_config(cfg)
  results$tp_core <- round(results$precision * results$n_det)
  results <- results[c(setdiff(names(results), c("cover", "closed")), "cover", "closed")]
  for (f in names(MCG_CONFIG_FIELDS)) results[[f]] <- cfg[[f]]
  results
}

# Pooled recall/precision/F1 by rung: sums of counts, never means of rates.
mcg_arm_pooled <- function(results) {
  do.call(rbind, lapply(c("native", "8", "4", "2", "1"), function(rl) {
    ss <- results[results$rung == rl, ]
    if (!nrow(ss)) return(NULL)
    recall    <- sum(ss$TP) / sum(ss$n_ref)
    precision <- if (sum(ss$n_det) > 0) sum(ss$tp_core, na.rm = TRUE) /
      sum(ss$n_det) else NA_real_
    f1 <- if (!is.na(precision) && (recall + precision) > 0)
      2 * recall * precision / (recall + precision) else NA_real_
    data.frame(rung = rl, n_plots = length(unique(ss$plot)),
               n_ref = sum(ss$n_ref), n_det = sum(ss$n_det),
               recall = recall, precision = precision, F1 = f1)
  }))
}

## ---- args ----------------------------------------------------------------
args  <- strsplit(commandArgs(TRUE), "=")
A     <- setNames(lapply(args, `[`, 2), sapply(args, `[`, 1))
SITE  <- if (is.null(A[["SITE"]]))  "SOAP" else A[["SITE"]]
PLOTS <- if (is.null(A[["PLOTS"]]) || A[["PLOTS"]] == "ALL") NULL else
  strsplit(A[["PLOTS"]], ",")[[1]]
CORES <- as.integer(if (is.null(A[["CORES"]])) 8 else A[["CORES"]])
TOL   <- as.numeric(if (is.null(A[["TOL"]])) 4.0 else A[["TOL"]])
A_VWF <- as.numeric(if (is.null(A[["A"]])) 0.10 else A[["A"]])

run_main <- function() {
  conf <- mcg_arm_config(A)              # stops before any work when none is available
  cfg  <- conf$cfg
  nd  <- file.path(d, "neon", SITE)
  gt  <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc  <- read.csv(file.path(nd, "plot_centroids.csv"),     stringsAsFactors = FALSE)
  fz  <- frozen_scope(d, SITE, A, gt)     # declared population + sealed root
  gt  <- fz$gt
  invisible(neon_validate_inputs(gt, pc))
  out_csv <- file.path(nd, "multichm_gated_results.csv")
  keep   <- fz$plots
  if (!is.null(PLOTS)) keep <- intersect(keep, PLOTS)
  keep   <- intersect(keep, pc$plotID)
  cat(sprintf("[%s] multichm_gated plots (%s): %d (%s)\n", SITE, fz$population, length(keep),
              paste(keep, collapse = ",")))
  cat(sprintf("[%s] configuration %s (%s): zmin=%g min_share=%g cover_min=%g surface_exempt=%s\n",
              SITE, mcg_config_label(cfg), conf$source, cfg$zmin, cfg$min_share,
              cfg$cover_min, cfg$surface_exempt))
  det_dir <- file.path(nd, paste0(MCG_ARM, "_detections"))
  frozen_stamp(det_dir, fz$root)          # detections made on other clips stop here
  mcg_arm_stamp_config(det_dir, cfg, A_VWF)  # ... and those of another configuration or A=

  run_plot <- function(pid) {
    ci <- pc[pc$plotID == pid, ][1, ]
    cx <- ci$easting; cy <- ci$northing
    ph <- plot_half(ci$plotType)            # tower +/-20 m, distributed +/-10 m
    stems <- gt[gt$plotID == pid &
                abs(gt$E - cx) <= ph & abs(gt$N - cy) <= ph, ]
    if (nrow(stems) < 1) return(NULL)
    out <- list(); native_pdens <- NA_real_
    # native first (rung = NA) -> captures native density; then decimated rungs.
    for (rung in c(NA, frozen_root_rungs(fz$root))) {
      prep <- frozen_clip(NULL, SITE, pid, rung, cx, cy, ph, fz$root)
      if (is.null(prep)) next
      pdens <- prep$pdens; frdens <- prep$frdens
      if (is.na(rung)) native_pdens <- pdens
      # no-upsampling guard: rung TARGET vs the plot's NATIVE all-return density.
      else if (is.na(native_pdens) || rung >= native_pdens) next
      las <- readLAS(prep$normalized)       # a read error fails the plot
      if (is.empty(las))
        stop(sprintf("multichm_gated: the frozen clip of %s at rung %s is empty", pid,
                     if (is.na(rung)) "native" else rung), call. = FALSE)
      cell <- mcg_arm_cell(las, stems,
                           list(site = SITE, plot = pid, plotType = ci$plotType, rung = rung,
                                cx = cx, cy = cy, half = ph, pdens = pdens, frdens = frdens),
                           cfg, a = A_VWF, tol = TOL)
      persist_detections(det_dir, pid, rung, cell$det)
      out[[length(out) + 1]] <- cbind(cell$row, cover = cell$cover, closed = cell$closed)
    }
    if (!length(out)) return(NULL)
    do.call(rbind, out)
  }

  t0 <- Sys.time()
  res_list <- plot_lapply(keep, function(p) tryCatch(run_plot(p), error = function(e) {
                message("plot ", p, " failed: ", conditionMessage(e)); e }),
                mc.cores = CORES, mc.preschedule = FALSE)
  # A failed plot (e.g. a frozen cell that no longer matches its hash) must not
  # leave the population silently smaller.
  stop_failed_plots(keep, res_list)
  results <- do.call(rbind, Filter(Negate(is.null), res_list))
  dt <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  if (is.null(results) || !nrow(results)) {
    cat("no multichm_gated results produced; check input LiDAR, ground truth, filters\n")
    return(invisible())
  }
  results <- mcg_arm_finish(results, cfg)
  write.csv(results, out_csv, row.names = FALSE)
  frozen_results_stamp(out_csv, fz)
  jsonlite::write_json(c(list(detector = MCG_ARM), cfg,
                         list(label = mcg_config_label(cfg), source = conf$source,
                              config_file = if (is.null(conf$file)) NA_character_ else
                                normalizePath(conf$file, mustWork = FALSE),
                              config_file_sha256 = if (is.null(conf$file)) NA_character_ else
                                frozen_sha256(conf$file),
                              radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                              cover_height = MCG_COVER_HEIGHT, a = A_VWF, tol = TOL,
                              population = fz$population,
                              clip_manifest_sha256 = frozen_root_id(fz$root))),
                       paste0(sub("\\.csv$", "", out_csv), ".config.json"),
                       auto_unbox = TRUE, pretty = TRUE, digits = NA)
  cat(sprintf("[%s] multichm_gated DONE: %d rows in %.1f min -> %s\n", SITE, nrow(results),
              dt, out_csv))

  cat(sprintf("\noverall recall/precision by rung (pooled; res density-derived, a=%g; %s):\n",
              A_VWF, mcg_config_label(cfg)))
  print(mcg_arm_pooled(results), row.names = FALSE, digits = 2)
}

if (sys.nframe() == 0L) run_main()
