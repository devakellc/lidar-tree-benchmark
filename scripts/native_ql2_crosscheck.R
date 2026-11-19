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

# Native USGS 3DEP QL2 cross-check for the density-ladder sweep (issues #4, #39).
#
# The density-ladder sweep DECIMATES a dense NEON cloud to simulate sparse
# acquisitions ("decimation-as-simulation", a stated caveat). This script pulls
# the *native* USGS 3DEP cloud over the same NEON plots, runs the SAME detection
# pipeline natively, and compares it to the cached DECIMATED 2-pts/m^2 rung by
# crown class. Deliverable: does decimation faithfully predict native-sparse
# (QL2 ~2 pulses/m^2) behaviour?
#
# Two detectors are run on the SAME per-plot native clip (issue #39):
#   * chm_vwf  -- the CHM-VWF baseline (detect_lasr + score_plot), compared to
#     the cached NEON dec2 rung in sweep_results.csv (issue #4, original arm).
#   * multichm -- lidRplugins::multichm (detect_on_multichm), compared to the
#     cached NEON dec2 rung in multichm_sweep_results.csv (#37 ladder arm).
# Each detector is tested against its OWN cached NEON dec2 baseline, so the
# native-vs-decimated equivalence is judged within detector, never across.
#
# HONESTY ON COVERAGE. The entwine/USGS public catalog does NOT have a QL2
# acquisition over every NEON site. Each site's covering EPT is verified by its
# *measured* first-return (pulse) density over a probe AOI, not by its name:
#   * "native_ql2" -- native pulse density falls in the QL2 band ~[1.5, 4]:
#     this is the real native-vs-decimated equivalence test. `native_full` is
#     the native-QL2 detection.
#   * "dense"       -- native pulse density is well above QL2 (a high-density
#     survey, e.g. CA_SierraNevada_*_B22 at ~30-40 pulses/m^2). There is NO
#     public native QL2 here; we report that honestly. `native_full` is the
#     dense detection (context only) and `native_dec2` (the dense cloud
#     decimated to 2) is a SECONDARY cross-source diagnostic, NOT native QL2.
#
# Pipeline per plot:
#   centroid (UTM 11N) -> +/-PAD m box -> reproject box to EPT native SRS ->
#   PDAL readers.ept(bounds) -> filters.range (drops withheld points only; see
#   PULL_FILTER_LIMITS) -> filters.reprojection out_srs=OUTCRS -> writers.las
#   -> per-plot laz.
#   Read laz -> drop noise (class 7/18) + withheld points (ql2_noise_filter, the
#   filter that removes the noise classes; clouds cached before the pull's
#   withheld clause was added still hold withheld points, and the cache test
#   does not key on the filter) -> Step-0 density ->
#   detect_lasr(res-by-density, a=A) -> score_plot (stems reprojected
#   32611 -> OUTCRS so they share the detection CRS).
# Densities are counted inside a box and divided by that box's area
# (box_density): the pulled cloud covers more than the nominal +/-PAD box,
# because the query box is the bounding box of the UTM box reprojected to the
# EPT's Web Mercator SRS. Each plot reports all-return and first-return
# density inside the +/-PAD box and first-return density inside the plot
# core; the never-upsample guard and the CHM-resolution rule use the box
# densities. Detection still reads the whole pulled cloud.
# Pool per site exactly like the sweep: recall = sum(TP)/sum(n_ref); per-class
# TP recovered as round(rec_class * n_class).
#
# Usage:
#   export CLAUDE_JOB_DIR=.../work
#   Rscript scripts/native_ql2_crosscheck.R SITES=SOAP,SJER,TEAK \
#       [EPT_SOAP=<url>] [EPT_SJER=<url>] [EPT_TEAK=<url>] [OUTCRS=EPSG:32611] \
#       [TOL=4] [A=0.10] [PAD=45] [MAXPLOTS=ALL] [PLOTS=SJER_050,...] \
#       [QL2_LO=1.5] [QL2_HI=4] [NOISE_FILTER=1|classes|0]
#
# If EPT_<SITE> is not given, the script auto-discovers via ept_discovery.R
# (writes work/neon/<SITE>/ql2/ept_candidates.csv) and uses the preferred one.
suppressMessages({
  library(lidR); library(lasR); library(lidRplugins); library(terra)
  library(sf); library(jsonlite)
})
options(lidR.progress = FALSE)
lidR::set_lidr_threads(1L)    # TIN normalization moves by ~1 cm with the thread count

src_dir <- dirname(sub("^--file=", "",
                       grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(src_dir) || !nzchar(src_dir)) src_dir <- "scripts"
source(file.path(src_dir, "sweep_lib.R"))     # detect_lasr, score_plot, plot_half
source(file.path(src_dir, "model_bench_lib.R")) # frozen_scope (POP=)
source(file.path(src_dir, "ept_discovery.R")) # discover_ept (for auto-resolution)

JOB <- .job_dir()
NEON_EPSG <- 32611                            # SOAP/SJER/TEAK = UTM 11N

## ---- args ----------------------------------------------------------------
args <- strsplit(commandArgs(TRUE), "=")
A <- setNames(lapply(args, function(z) paste(z[-1], collapse = "=")),
              sapply(args, `[`, 1))
SITES <- if (is.null(A$SITES)) c("SOAP", "SJER", "TEAK") else
  strsplit(A$SITES, ",")[[1]]
if (any(!SITES %in% c("SOAP", "SJER", "TEAK")))
  stop("Native QL2 cross-check is restricted to the historical D17 sites")
OUTCRS <- if (is.null(A$OUTCRS)) "EPSG:32611" else A$OUTCRS
OUT_EPSG <- as.integer(sub("EPSG:", "", OUTCRS))
TOL  <- as.numeric(if (is.null(A$TOL)) 4.0 else A$TOL)
AVWF <- as.numeric(if (is.null(A$A)) 0.10 else A$A)
PAD  <- as.numeric(if (is.null(A$PAD)) 45 else A$PAD)
QL2_LO <- as.numeric(if (is.null(A$QL2_LO)) 1.5 else A$QL2_LO)
QL2_HI <- as.numeric(if (is.null(A$QL2_HI)) 4.0 else A$QL2_HI)
MAXPLOTS <- if (is.null(A$MAXPLOTS) || A$MAXPLOTS == "ALL") NA_integer_ else
  as.integer(A$MAXPLOTS)
ONLY_PLOTS <- if (is.null(A$PLOTS)) NULL else strsplit(A$PLOTS, ",")[[1]]
# POP= scores against that declared population of the sealed frozen root (its
# plots and gated stems, frozen_scope) instead of the historical six-stem
# D17 reference. CACHE_JOB= reads (and adds) the EPT candidates and per-plot
# clouds under another job directory, so a re-score reuses the cached pulls.
POP_SCOPED <- !is.null(A$POP)
CACHE <- if (is.null(A$CACHE_JOB)) JOB else A$CACHE_JOB
# NOISE_FILTER= sets what is dropped when a cloud is read: 1 (default) classes
# 7 and 18 and withheld points (the pull drops only the withheld ones);
# `classes` classes 7 and 18 only (a diagnostic); 0 nothing, the clouds as
# cached (reproduces outputs made before the read-time filter existed).
NOISE_FILTER <- if (is.null(A$NOISE_FILTER)) "1" else A$NOISE_FILTER
if (!NOISE_FILTER %in% c("1", "classes", "0"))
  stop("NOISE_FILTER must be 1, classes or 0")

# Per-site EPT override argument: EPT_<SITE>=<url>.
ept_override <- function(site) {
  k <- paste0("EPT_", site)
  if (!is.null(A[[k]]) && nzchar(A[[k]])) return(A[[k]]) else NA_character_
}

# Resolve the EPT URL for a site: explicit override, else cached candidate, else
# run discovery now. Returns the preferred EPT URL or NA.
resolve_ept <- function(site) {
  ov <- ept_override(site)
  if (!is.na(ov)) return(ov)
  cand_path <- file.path(CACHE, "neon", site, "ql2", "ept_candidates.csv")
  if (!file.exists(cand_path)) {
    discover_ept(site, CACHE, site_epsg = NEON_EPSG)   # writes candidates csv
  }
  if (!file.exists(cand_path)) return(NA_character_)
  cand <- read.csv(cand_path, stringsAsFactors = FALSE)
  pick <- cand$url[which(cand$preferred %in% TRUE)]
  if (length(pick) && !is.na(pick[1]) && nzchar(pick[1])) return(pick[1])
  ok <- cand$url[!is.na(cand$url) & nzchar(cand$url)]
  if (length(ok)) ok[1] else NA_character_
}

# Read the native horizontal SRS (EPSG code) from an ept.json. The value is
# recorded beside the EPT candidates (ept_srs.json, keyed by URL) on first
# read, so a re-score of cached clouds runs offline.
ept_srs <- function(url, cache_dir) {
  f <- file.path(cache_dir, "ept_srs.json")
  if (file.exists(f)) {
    rec <- jsonlite::fromJSON(f)
    if (identical(rec$url, url)) return(as.integer(rec$srs))
  }
  j <- tryCatch(jsonlite::fromJSON(url), error = function(e) NULL)
  if (is.null(j)) return(NA_integer_)
  s <- j$srs
  if (is.null(s$horizontal) || !nzchar(as.character(s$horizontal))) return(NA_integer_)
  code <- as.integer(s$horizontal)
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  writeLines(jsonlite::toJSON(list(url = url, srs = code), auto_unbox = TRUE, pretty = TRUE), f)
  code
}

# Provenance manifest for a cached per-plot laz. The cache key is NOT just the
# plot id: a laz pulled under a different EPT/PAD/OUTCRS is a different cloud and
# must be re-pulled. We write a sidecar `<laz>.json` recording (ept_url, pad,
# outcrs) and only reuse the cached laz when all three match. This prevents a
# stale laz (e.g. from a prior EPT or a different reprojection target) from being
# silently reused.
manifest_path <- function(out_laz) paste0(out_laz, ".json")

# Noise classes (7 low noise, 18 high noise). The read-time filter
# (ql2_noise_filter) is the one that removes them. The pull's PDAL
# filters.range limits do not: filters.range ORs ranges that name the same
# dimension and ANDs different dimensions, so `Classification![7:7]` and
# `Classification![18:18]` together keep every point and only `Withheld![1:1]`
# (keep points whose Withheld flag is not 1) removes any. In these surveys
# every class 7 or 18 point is also withheld. The string is kept as pulled, so
# that fresh pulls record the same filter in their manifests as earlier ones,
# the cached clouds stay valid and nothing is pulled again.
QL2_NOISE_CLASSES <- c(7L, 18L)
PULL_FILTER_LIMITS <- paste(c(sprintf("Classification![%d:%d]", QL2_NOISE_CLASSES,
                                      QL2_NOISE_CLASSES), "Withheld![1:1]"),
                            collapse = ",")

# Fresh pulls also record the pull's limits string. Clouds cached before that
# record was added have no `filter` field; cache_valid does not key on it (the
# cached clouds are reused as they are), so the read-time filter below covers
# them.
write_manifest <- function(out_laz, ept_url, pad, outcrs) {
  writeLines(jsonlite::toJSON(
    list(ept_url = ept_url, pad = pad, outcrs = outcrs, filter = PULL_FILTER_LIMITS),
    auto_unbox = TRUE, pretty = TRUE), manifest_path(out_laz))
}

# Read-time noise filter: drops points of `classes` and, when `withheld`, every
# point flagged Withheld, whatever the age of the cached cloud. Returns the
# filtered cloud and one row of counts: points read, points in class 7, in
# class 18 and flagged withheld (whether dropped or not), and points dropped.
# With nothing to drop the cloud is returned untouched. A cloud read without
# the withheld flag (readLAS select without "w") stops the run (an error of
# class ql2_read_error, which the per-site handler re-raises), since its
# withheld points could be neither dropped nor counted.
ql2_noise_filter <- function(las, classes = QL2_NOISE_CLASSES, withheld = TRUE) {
  cl <- las$Classification
  if (is.null(las$Withheld_flag))
    stop(structure(class = c("ql2_read_error", "error", "condition"), list(
      message = "The cloud was read without the withheld flag; read it with readLAS select including \"w\"",
      call = sys.call())))
  wh <- las$Withheld_flag %in% TRUE
  drop <- (cl %in% classes) | (withheld & wh)
  counts <- data.frame(n_read = length(cl), n_class7 = sum(cl == 7L),
                       n_class18 = sum(cl == 18L), n_withheld = sum(wh),
                       n_dropped = sum(drop))
  if (any(drop)) las <- lidR::filter_poi(las, !drop)
  list(las = las, counts = counts)
}

# Label of a read-time filter setting, recorded with every per-plot row.
noise_filter_label <- function(classes, withheld) {
  lab <- c(if (length(classes)) paste(classes, collapse = ","), if (withheld) "withheld")
  if (length(lab)) paste(lab, collapse = ",") else "none"
}

# All-return and first-return density (points/m^2) inside the axis-aligned box
# of half-width `half` centred on (cx, cy): points and area from the same box.
box_density <- function(las, cx, cy, half) {
  inb <- abs(las$X - cx) <= half & abs(las$Y - cy) <= half
  area <- (2 * half)^2
  c(pdens = sum(inb) / area, frdens = sum(inb & las$ReturnNumber == 1L) / area)
}

NF_CLASSES  <- if (NOISE_FILTER == "0") integer(0) else QL2_NOISE_CLASSES
NF_WITHHELD <- NOISE_FILTER == "1"
NF_LABEL    <- noise_filter_label(NF_CLASSES, NF_WITHHELD)

# TRUE iff a cached laz exists AND its sidecar manifest matches the provenance
# we are about to use (ept_url + pad + outcrs). Missing/mismatched manifest -> not
# a valid cache hit -> caller re-pulls.
cache_valid <- function(out_laz, ept_url, pad, outcrs) {
  if (!file.exists(out_laz) || file.info(out_laz)$size < 500) return(FALSE)
  mp <- manifest_path(out_laz)
  if (!file.exists(mp)) return(FALSE)
  m <- tryCatch(jsonlite::fromJSON(mp), error = function(e) NULL)
  if (is.null(m)) return(FALSE)
  identical(as.character(m$ept_url), as.character(ept_url)) &&
    isTRUE(as.numeric(m$pad) == as.numeric(pad)) &&
    identical(as.character(m$outcrs), as.character(outcrs))
}

# Reproject a set of NEON-native points (E,N in EPSG:32611, the woody-veg stem
# CRS) into OUTCRS for scoring (fix 2). Detections come out of detect_lasr in
# OUTCRS (the laz is reprojected by filters.reprojection out_srs=OUTCRS), so the
# field stems MUST be moved into the SAME CRS before matching -- otherwise any
# non-default OUTCRS silently mismatches stems against detections. When OUTCRS is
# the native EPSG:32611 this is an identity transform. Returns a 2-col matrix.
to_outcrs <- function(e, n) {
  if (OUT_EPSG == NEON_EPSG) return(cbind(x = e, y = n))   # identity fast-path
  p <- st_as_sf(data.frame(x = e, y = n), coords = c("x", "y"), crs = NEON_EPSG)
  xy <- st_coordinates(st_transform(p, OUT_EPSG))
  cbind(x = xy[, 1], y = xy[, 2])
}

# Pull a single plot's native cloud via PDAL readers.ept, reproject to OUTCRS.
# box (UTM) -> EPT SRS bounds -> ept reader -> drop withheld -> reproject -> laz.
pull_plot <- function(cx, cy, pad, ept_url, ept_epsg, out_laz) {
  box <- st_as_sf(data.frame(id = 1:4,
                             x = c(cx - pad, cx + pad, cx + pad, cx - pad),
                             y = c(cy - pad, cy - pad, cy + pad, cy + pad)),
                  coords = c("x", "y"), crs = NEON_EPSG)
  box_ept <- st_transform(box, ept_epsg)
  bb <- st_bbox(box_ept)
  bounds <- sprintf("([%f, %f], [%f, %f])",
                    bb["xmin"], bb["xmax"], bb["ymin"], bb["ymax"])
  # PULL_FILTER_LIMITS drops only the points flagged Withheld (its class
  # clauses cancel; see there); the read-time filter drops classes 7 and 18.
  pipe <- list(
    list(type = "readers.ept", filename = ept_url, bounds = bounds),
    list(type = "filters.range",                       # drops withheld points
         limits = PULL_FILTER_LIMITS),
    list(type = "filters.reprojection", out_srs = OUTCRS),
    list(type = "writers.las", filename = out_laz, compression = "laszip")
  )
  pj <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(pipe, auto_unbox = TRUE, pretty = TRUE), pj)
  rc <- suppressWarnings(system2("pdal", c("pipeline", shQuote(pj)),
                                 stdout = TRUE, stderr = TRUE))
  st <- attr(rc, "status")
  unlink(pj)
  if (!is.null(st) && st != 0)
    return(list(ok = FALSE, msg = paste(tail(rc, 4), collapse = " | ")))
  if (!file.exists(out_laz) || file.info(out_laz)$size < 500)
    return(list(ok = FALSE, msg = "empty/no output laz"))
  write_manifest(out_laz, ept_url, pad, OUTCRS)   # record provenance for cache
  list(ok = TRUE, msg = "")
}

# Shared preparation of both detectors: optional decimation of the (noise-
# filtered) native cloud to all-return density `rung`, TIN normalization and
# the Z window. `native_pdens` is the native all-return density inside the
# +/-PAD box, the unit of the never-upsample guard. The returned densities are
# counted inside the +/-pad box (all-return, first-return) and the plot core
# (first-return), centred on (cx, cy) in the cloud's CRS.
prep_cloud <- function(src_las, rung, native_pdens, cx, cy, pad, core_half, seed = NA) {
  l <- src_las
  if (!is.na(rung)) {
    if (native_pdens <= rung) return(NULL)             # never upsample
    if (!is.na(seed)) set.seed(seed)
    l <- decimate_points(l, homogenize(density = rung, res = 5))
  }
  if (sum(l$Classification == 2L) < 10) return(NULL)
  nrm <- tryCatch(normalize_height(l, tin(), na.rm = TRUE),
                  error = function(e) NULL)
  if (is.null(nrm)) return(NULL)
  nrm <- filter_poi(nrm, Z >= -1, Z < 80)
  bd  <- box_density(nrm, cx, cy, pad)
  list(nrm = nrm, pdens = bd[["pdens"]], frdens = bd[["frdens"]],
       frdens_core = box_density(nrm, cx, cy, core_half)[["frdens"]])
}

# Run detect_lasr on a (possibly decimated) LAS; returns det + measured density.
# res_override: when non-NA, pin the CHM resolution instead of deriving it from
# the (decimated) first-return density. Used by the decimated-2 arm so its CHM
# resolution MATCHES the NEON dec2 arm it is compared against (chm_res=0.5).
# Without this, a native cloud decimated to ~2 ppsm would fall into the res=1.0
# branch (frdens<4) while NEON dec2 is pooled at res=0.5 -- a resolution confound
# that contaminates the "sensor difference" delta. With it, the residual delta is
# genuinely sensor/return-structure, not CHM resolution.
detect_on <- function(src_las, rung, native_pdens, cx, cy, pad, core_half,
                      res_override = NA_real_, seed = NA) {
  p <- prep_cloud(src_las, rung, native_pdens, cx, cy, pad, core_half, seed)
  if (is.null(p)) return(NULL)
  frdn <- p$frdens
  fn   <- tempfile(fileext = ".laz"); writeLAS(p$nrm, fn)
  res  <- if (!is.na(res_override)) res_override else
          if (frdn >= 8) 0.25 else if (frdn >= 4) 0.5 else 1.0
  # NB the <8 ppsm pre-LM smoothing branch in detect_lasr keys on dens=frdn, not
  # on res, so pinning res does not change which smoothing path the dec2 arm
  # takes -- only the CHM grid is matched to the NEON dec2 arm.
  det  <- tryCatch(detect_lasr(fn, res = res, a = AVWF, dens = frdn),
                   error = function(e) { message(conditionMessage(e)); NULL })
  unlink(fn)
  if (is.null(det)) return(NULL)
  list(det = det, res = res, pdens = p$pdens, frdens = frdn,
       frdens_core = p$frdens_core)
}

# multichm counterpart of detect_on (issue #39): the SAME decimate/normalize/
# density prep, but detection is lidRplugins::multichm (Eysn-style multi-layer
# CHM local maxima) at the multichm ladder-arm res rule (0.25 m if first-returns
# >= 8 else 0.5 m -- detect_multichm_sweep.R::run_plot) with the clamped window
# ws_factory(AVWF). No res_override is needed: at the decimated pdens=2 arm the
# first-return density falls below 8, so the rule lands at 0.5 m -- already
# matching the cached multichm dec2 rung (multichm_sweep_results.csv rung==2,
# which is itself density-derived at 0.5 m), so the equivalence test stays
# resolution-consistent the same way the CHM-VWF arm is res-pinned to 0.5 m.
detect_on_multichm <- function(src_las, rung, native_pdens, cx, cy, pad, core_half,
                               seed = NA) {
  p <- prep_cloud(src_las, rung, native_pdens, cx, cy, pad, core_half, seed)
  if (is.null(p)) return(NULL)
  res  <- if (p$frdens >= 8) 0.25 else 0.5
  tt <- tryCatch(lidR::locate_trees(p$nrm, lidRplugins::multichm(res = res,
                   ws = ws_factory(AVWF))), error = function(e) NULL)
  if (is.null(tt) || nrow(tt) == 0) return(NULL)
  co <- sf::st_coordinates(tt)                          # 2-D tops; apex z from Z
  z  <- if (ncol(co) >= 3) co[, 3] else if (!is.null(tt$Z)) tt$Z else co[, 2] * 0
  list(det = data.frame(x = co[, 1], y = co[, 2], z = z),
       res = res, pdens = p$pdens, frdens = p$frdens, frdens_core = p$frdens_core)
}

## ---- per-site run ---------------------------------------------------------
run_site <- function(site) {
  ept_url <- resolve_ept(site)
  cat(sprintf("\n########## %s  EPT=%s\n", site, ept_url))
  if (is.na(ept_url)) { cat("  no EPT URL resolved; skipping\n"); return(NULL) }
  ept_epsg <- ept_srs(ept_url, file.path(CACHE, "neon", site, "ql2"))
  if (is.na(ept_epsg)) { cat("  could not read SRS from ept.json; skipping\n")
    return(NULL) }
  cat(sprintf("  native EPT SRS = EPSG:%d ; reproject -> %s\n", ept_epsg, OUTCRS))

  nd  <- file.path(JOB, "neon", site)
  pc  <- read.csv(file.path(nd, "plot_centroids.csv"))
  gt  <- read.csv(file.path(nd, "ground_truth_stems.csv"))
  if (POP_SCOPED) {
    fz <- frozen_scope(JOB, site, A, gt)      # declared population + sealed root
    gt <- fz$gt; MINTREES <- 1
  }
  if (neon_validate_inputs(gt, pc) != NEON_EPSG)
    stop("Historical D17 field CRS must be EPSG:32611")
  if (!POP_SCOPED) {
    gt  <- gt[gt$live & gt$is_tree & !is.na(gt$E), ]
    MINTREES <- 6
  }
  ql2 <- file.path(nd, "ql2")                  # results
  clouds <- file.path(CACHE, "neon", site, "ql2")
  dir.create(ql2, showWarnings = FALSE, recursive = TRUE)
  dir.create(clouds, showWarnings = FALSE, recursive = TRUE)

  rows <- list()
  pids <- pc$plotID
  if (POP_SCOPED) pids <- intersect(pids, fz$plots)
  if (!is.null(ONLY_PLOTS)) pids <- intersect(pids, ONLY_PLOTS)
  done <- 0L
  for (pid in pids) {
    if (!is.na(MAXPLOTS) && done >= MAXPLOTS) break
    ci <- pc[pc$plotID == pid, ][1, ]
    cx <- ci$easting; cy <- ci$northing
    ph <- plot_half(ci$plotType)                       # tower +/-20, dist +/-10
    stems <- gt[gt$plotID == pid &
                abs(gt$E - cx) <= ph & abs(gt$N - cy) <= ph, ]
    if (nrow(stems) < MINTREES) next

    out_laz <- file.path(clouds, sprintf("%s.laz", pid))
    # Cache reuse is provenance-gated (fix 1): a pre-existing laz is a cache HIT
    # ONLY when its sidecar manifest exists AND matches (ept_url, pad, outcrs).
    # Provenance is NEVER inferred from file size -- a manifest-less laz (or one
    # whose manifest records a different EPT/PAD/OUTCRS) is treated as a cache
    # MISS and re-pulled, which writes a fresh manifest. This closes the stale-
    # data hole: a laz from an earlier EPT/pad/reprojection target can never be
    # silently reused just because it is non-empty on disk.
    if (!cache_valid(out_laz, ept_url, PAD, OUTCRS)) {
      if (file.exists(out_laz))
        cat(sprintf("  %s: cache miss (no/invalid manifest) -> re-pull\n", pid))
      pr <- pull_plot(cx, cy, PAD, ept_url, ept_epsg, out_laz)
      if (!pr$ok) { cat(sprintf("  %s: PULL FAILED (%s)\n", pid, pr$msg)); next }
    } else {
      cat(sprintf("  %s: cache HIT (provenance match)\n", pid))
    }
    las <- tryCatch(readLAS(out_laz), error = function(e) NULL)
    # Noise classes and withheld points are dropped before any measurement or
    # detection, whatever the pull of the cached cloud dropped.
    nf <- NULL
    if (!is.null(las) && !is.empty(las)) {
      nf  <- ql2_noise_filter(las, classes = NF_CLASSES, withheld = NF_WITHHELD)
      las <- nf$las
      cat(sprintf("  %s: read %d points; dropped %d (class 7: %d, class 18: %d, withheld: %d; filter %s)\n",
                  pid, nf$counts$n_read, nf$counts$n_dropped, nf$counts$n_class7,
                  nf$counts$n_class18, nf$counts$n_withheld, NF_LABEL))
    }
    if (is.null(las) || is.empty(las) || npoints(las) < 200) {
      cat(sprintf("  %s: too few native points; skip\n", pid)); next }
    if (sum(las$Classification == 2L) < 10) {
      cat(sprintf("  %s: <10 ground pts; skip\n", pid)); next }

    # Move stems + core centre from native EPSG:32611 into OUTCRS so they share
    # the detection CRS (fix 2). Stem-core SELECTION above stayed native (matches
    # the AOI pull); SCORING below is done entirely in OUTCRS.
    stems_o <- stems
    s_xy <- to_outcrs(stems$E, stems$N)
    stems_o$E <- s_xy[, "x"]; stems_o$N <- s_xy[, "y"]
    c_xy <- to_outcrs(cx, cy)
    cx_o <- c_xy[1, "x"]; cy_o <- c_xy[1, "y"]

    # Native densities, each counted inside the box it is divided by: the
    # +/-PAD box (all-return + first-return/pulse) and the plot core
    # (first-return). The pulled cloud is larger than the +/-PAD box.
    bd_n     <- box_density(las, cx_o, cy_o, PAD)
    pdens_n  <- bd_n[["pdens"]]
    frdens_n <- bd_n[["frdens"]]
    frdens_core_n <- box_density(las, cx_o, cy_o, ph)[["frdens"]]

    # native_full = detection at the survey's native density (its true sparsity);
    #   CHM resolution derived from its (high) native first-return density.
    # native_dec2 = native cloud decimated to ALL-RETURN density 2 (pdens, the
    #   sweep's homogenize unit), CHM resolution PINNED to 0.5 to match the NEON
    #   dec2 arm (round-1 fix: resolution-matched equivalence). Each arm carries a
    #   (rung, res_override) pair.
    variants <- list(native_full = list(rung = NA_real_, res = NA_real_),
                     native_dec2 = list(rung = 2,        res = 0.5))
    got_any <- FALSE
    # Two detectors per variant (issue #39): the CHM-VWF baseline (detect_on, res
    # pinned per the variant) and multichm (detect_on_multichm). Both read the
    # same seeded native_dec2 realization (seed_for(site, plot, "3DEP-2"), so a
    # rerun decimates identically), and each is compared only to its OWN cached
    # NEON dec2 rung downstream -- a within-detector equivalence test, never
    # cross-detector.
    for (vn in names(variants)) {
      seed <- if (is.na(variants[[vn]]$rung)) NA else
        seed_for(site, pid, paste0("3DEP-", variants[[vn]]$rung))
      for (dn in c("chm_vwf", "multichm")) {
        v <- if (dn == "chm_vwf")
          detect_on(las, variants[[vn]]$rung, pdens_n, cx_o, cy_o, PAD, ph,
                    res_override = variants[[vn]]$res, seed = seed)
        else
          detect_on_multichm(las, variants[[vn]]$rung, pdens_n, cx_o, cy_o, PAD, ph,
                             seed = seed)
        if (is.null(v)) { cat(sprintf("  %s [%s/%s]: skip\n", pid, vn, dn)); next }
        sc <- score_plot(stems_o, v$det, tol_xy = TOL, core_cx = cx_o,
                         core_cy = cy_o, core_half = ph)
        sc <- cbind(data.frame(site = site, plot = pid, plotType = ci$plotType,
                               variant = vn, detector = dn,
                               native_pdens = round(pdens_n, 2),
                               native_frdens = round(frdens_n, 2),
                               native_frdens_core = round(frdens_core_n, 2),
                               pdens = round(v$pdens, 2), frdens = round(v$frdens, 2),
                               frdens_core = round(v$frdens_core, 2),
                               chm_res = v$res, vwf_a = AVWF), sc,
                    data.frame(noise_filter = NF_LABEL), nf$counts)
        rows[[length(rows) + 1]] <- sc
        got_any <- TRUE
        cat(sprintf("  %s [%s/%s]: native_fr=%.2f -> fr=%.2f res=%.2f n_ref=%d TP=%d recall=%.2f prec=%.2f\n",
                    pid, vn, dn, frdens_n, v$frdens, v$res, sc$n_ref, sc$TP,
                    sc$recall, sc$precision))
      }
    }
    if (got_any) done <- done + 1L
  }
  if (!length(rows)) { cat(sprintf("  %s: NO plots scored\n", site)); return(NULL) }
  res_df <- do.call(rbind, rows)
  res_df$ept_url <- ept_url
  res_df$ept_srs <- ept_epsg
  # classify the site by MEDIAN native first-return density at the probe AOIs
  med_fr <- median(unique(res_df[, c("plot", "native_frdens")])$native_frdens)
  cls <- if (med_fr >= QL2_LO && med_fr <= QL2_HI) "native_ql2" else
    if (med_fr > QL2_HI) "dense" else "sub_ql2"
  res_df$site_class <- cls
  res_df$native_frdens_median <- round(med_fr, 2)
  write.csv(res_df, file.path(ql2, "ql2_detect_results.csv"), row.names = FALSE)
  pl <- unique(res_df[, c("plot", "native_frdens_core", "n_read", "n_dropped")])
  cat(sprintf("  --> %s native median first-return density = %.2f pulses/m^2 in the +/-%g m box, %.2f in the core (class=%s)\n",
              site, med_fr, PAD, median(pl$native_frdens_core), cls))
  cat(sprintf("  --> %s noise filter %s: dropped %d of %d points read (%.2f%%) over %d plots\n",
              site, NF_LABEL, sum(pl$n_dropped), sum(pl$n_read),
              100 * sum(pl$n_dropped) / sum(pl$n_read), nrow(pl)))
  res_df
}

## ---- pooling (matches the sweep's count-summing rule) ---------------------
# Pooling rules (matched to analyze_sweep.R):
#  * recall    = sum(TP) / sum(n_ref)  -- TP is the global match count (incl.
#                boundary matches), n_ref is all core stems. This is correct.
#  * precision = sum(tp_core) / sum(n_det). The PER-ROW precision from score_plot
#                is already tp_core/n_det (core-only numerator). Pooling
#                sum(TP)/sum(n_det) would mix a boundary-inclusive numerator with
#                a core-only denominator and INFLATE precision (round-1 fix). So
#                we recover tp_core = round(precision * n_det) per row -- exactly as
#                analyze_sweep.R:17 does -- and pool that.
pool_native <- function(df) {
  classes <- c("dominant", "codominant", "intermediate", "suppressed")
  hbands  <- c("short", "mid", "tall")
  tp_core <- round(df$precision * df$n_det); tp_core[is.na(tp_core)] <- 0
  out <- list()
  out[["overall"]] <- data.frame(
    scope = "overall",
    n_ref = sum(df$n_ref), TP = sum(df$TP),
    recall = sum(df$TP) / sum(df$n_ref),
    n_det = sum(df$n_det),
    precision = if (sum(df$n_det)) sum(tp_core) / sum(df$n_det) else NA_real_)
  for (cls in classes) {
    nc <- df[[paste0("n_", cls)]]; rc <- df[[paste0("rec_", cls)]]
    tp <- round(rc * nc); tp[is.na(tp)] <- 0
    nref <- sum(nc, na.rm = TRUE)
    out[[cls]] <- data.frame(scope = cls, n_ref = nref, TP = sum(tp),
      recall = if (nref) sum(tp) / nref else NA_real_,
      n_det = NA_integer_, precision = NA_real_)
  }
  for (b in hbands) {
    nc <- df[[paste0("n_h_", b)]]; rc <- df[[paste0("rec_h_", b)]]
    if (is.null(nc)) next
    tp <- round(rc * nc); tp[is.na(tp)] <- 0
    nref <- sum(nc, na.rm = TRUE)
    out[[paste0("h_", b)]] <- data.frame(scope = paste0("h_", b),
      n_ref = nref, TP = sum(tp),
      recall = if (nref) sum(tp) / nref else NA_real_,
      n_det = NA_integer_, precision = NA_real_)
  }
  do.call(rbind, out)
}

# Pool the cached DECIMATED 2-rung the same way (rung==2,res==0.5,a==0.10),
# restricted to a plot set so the comparison is paired.
pool_decimated <- function(site, plots) {
  f <- file.path(JOB, "neon", site, "sweep_results.csv")
  if (!file.exists(f)) return(NULL)
  d <- read.csv(f, stringsAsFactors = FALSE)
  d <- d[d$rung == "2" & d$chm_res == 0.5 & d$vwf_a == 0.10, ]
  if (!is.null(plots)) d <- d[d$plot %in% plots, ]
  if (!nrow(d)) return(NULL)
  pool_native(d)
}

# multichm counterpart (issue #39): pool the cached MULTICHM decimated-2 rung.
# multichm has no chm_res/vwf_a grid -- one row per plot at rung==2, its res
# density-derived (0.5 m at pdens=2) -- so we filter on rung only and pool the
# same paired plot set. This is the NEON baseline the native multichm arm is
# tested against, mirroring pool_decimated for CHM-VWF.
# On the frozen paper runs the multichm rows live in lidrplugins_results.csv.
pool_decimated_multichm <- function(site, plots) {
  f <- file.path(JOB, "neon", site, "multichm_sweep_results.csv")
  if (!file.exists(f)) {
    f <- file.path(JOB, "neon", site, "lidrplugins_results.csv")
    if (!file.exists(f)) return(NULL)
    d <- read.csv(f, stringsAsFactors = FALSE)
    d <- d[d$detector == "multichm", ]
  } else d <- read.csv(f, stringsAsFactors = FALSE)
  d <- d[d$rung == "2", ]
  if (!is.null(plots)) d <- d[d$plot %in% plots, ]
  if (!nrow(d)) return(NULL)
  pool_native(d)
}

## ---- main -----------------------------------------------------------------
all_native <- list(); all_cmp <- list()
for (site in SITES) {
  nv <- tryCatch(run_site(site), ql2_read_error = function(e) stop(e), error = function(e) {
    cat("  ", site, " errored: ", conditionMessage(e), "\n"); NULL })
  if (is.null(nv) || !nrow(nv)) next
  all_native[[site]] <- nv
  scls <- nv$site_class[1]

  # The equivalence test depends on the site class:
  #  native_ql2 -> compare native_full (== native QL2) vs neon_dec2
  #  dense      -> there is NO native QL2; compare the dense survey decimated to
  #                2 (native_dec2) vs neon_dec2 as a cross-source diagnostic.
  test_variant <- if (scls == "native_ql2") "native_full" else "native_dec2"

  # Per detector (issue #39): pool that detector's variants and compare its
  # native arm to its OWN cached NEON dec2 baseline (CHM-VWF -> sweep_results;
  # multichm -> multichm_sweep_results). The comparison is always within
  # detector, so a detector-specific delta is never confounded by the other.
  for (dn in c("chm_vwf", "multichm")) {
    nvd <- nv[nv$detector == dn, ]
    if (!nrow(nvd)) next
    test_plots <- unique(nvd$plot[nvd$variant == test_variant])

    pools <- list()
    for (vn in unique(nvd$variant)) {
      sub <- nvd[nvd$variant == vn, ]
      pv  <- pool_native(sub); pv$engine <- vn
      pv$n_plots <- length(unique(sub$plot))
      pools[[vn]] <- pv
    }
    pd <- if (dn == "chm_vwf") pool_decimated(site, test_plots)
          else pool_decimated_multichm(site, test_plots)
    if (!is.null(pd)) { pd$engine <- "neon_dec2"; pd$n_plots <- length(test_plots) }

    site_tbl <- do.call(rbind, c(pools, list(neon_dec2 = pd)))
    site_tbl$detector <- dn
    site_tbl$site <- site
    site_tbl$site_class <- scls
    site_tbl$native_frdens_median <- nvd$native_frdens_median[1]
    site_tbl$test_variant <- test_variant
    all_cmp[[paste(site, dn, sep = "_")]] <- site_tbl

    cat(sprintf("\n=== %s [%s] pooled  (class=%s, native median fr=%.2f, n=%d plots) ===\n",
                site, dn, scls, nvd$native_frdens_median[1],
                length(unique(nvd$plot))))
    print(site_tbl[, c("engine", "scope", "n_plots", "n_ref", "TP", "recall",
                       "precision")], row.names = FALSE)

    if (!is.null(pd) && test_variant %in% names(pools)) {
      nt <- pools[[test_variant]]
      eqv <- merge(nt[, c("scope", "recall", "n_ref", "TP")],
                   pd[, c("scope", "recall", "n_ref", "TP")],
                   by = "scope", suffixes = c("_native", "_neonDec2"))
      eqv$delta_recall <- eqv$recall_native - eqv$recall_neonDec2
      lab <- if (scls == "native_ql2") "native_QL2 vs neon_dec2"
             else "native_dec2(cross-source) vs neon_dec2"
      cat(sprintf("\n--- %s [%s] EQUIVALENCE: %s ---\n", site, dn, lab))
      print(eqv, row.names = FALSE, digits = 3)
    }
  }
}

if (length(all_cmp)) {
  comb <- do.call(rbind, all_cmp)
  outf <- file.path(JOB, "neon", "native_ql2_vs_decimated.csv")
  write.csv(comb, outf, row.names = FALSE)
  cat("\nWROTE", outf, "\n")
}
cat("\nDONE native_ql2_crosscheck\n")
