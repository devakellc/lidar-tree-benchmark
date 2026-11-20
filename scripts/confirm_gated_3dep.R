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

# Confirmation test C4 of the multichm_gated arm
# (docs/multichm-gated-confirmation-protocol.md): five frozen configurations of
# the detector scored on USGS 3DEP point clouds over the benchmark's plots,
# against the benchmark's 2021 field stems, at the 3DEP cloud's own density and
# thinned to 2 points/m2. 3DEP is another programme flown with other
# instruments than the NEON flights the detector was calibrated on.
#
# Plots: the declared population (POP=, default adopted) of the sealed frozen
# root; stems and plot centroids from REF_JOB/neon/<SITE>/ (the paper runs).
# Every input outside OUT is read only.
#
# Stages (STAGE=all runs them in this order; each reads the previous one's
# files under OUT):
#   discover  the public entwine/USGS 3DEP boundary index (the one
#             ept_discovery.R reads; INDEX= takes a local copy) against each
#             plot's clip box, nominal core plus BUFFER (25 m), in the site's
#             UTM frame (neon_field_epsg). A tile set covers a plot when its
#             footprint covers the whole box. Per plot the covering tile set
#             ranked first by ept_discovery.R's score_candidate() (then by the
#             number of the site's plots it covers, then by name) is used;
#             EPT_<SITE>=<ept.json url> forces one. -> ept_candidates.csv,
#             coverage.csv (one row per plot; plots no tile set covers are
#             recorded there and left out).
#   pull      per covered plot, PDAL readers.ept over the box's bounding box in
#             the EPT's SRS (1 m margin), noise classes 7 and 18 and withheld
#             points dropped, reprojected to the site frame, written as LAS 1.4
#             point format 6 (GPS time kept as adjusted standard time). Cached
#             under clouds/<SITE>/<plot>.laz with a manifest of the request; a
#             cloud whose manifest differs is pulled again. -> pulls.csv.
#   clips     the frozen-clip definition (model_bench_lib.R frozen_clip): the
#             box clipped from the pulled cloud read as a catalogue
#             (clip_rectangle), made canonical (frozen_canonical: coordinates
#             snapped to the LAS grid, GPS time rounded to the microsecond,
#             points sorted by GPS time, return number, X, Y, Z), at least 10
#             ground points, TIN DTM and TIN height normalisation, heights kept
#             in [-1, 80), lidR on one thread. Variant 3dep_native keeps every
#             point; 3dep_dec2 is the same canonical clip thinned with
#             decimate_points(homogenize(density = RUNG, res = 5)) after
#             set.seed(seed_for(site, plot, SEED_KEY)), the decimation of the
#             benchmark ladder and of the native QL2 cross-check, whose seed key
#             "3DEP-2" this keeps; a plot whose native all-return density is at
#             or below RUNG gets no thinned clip (the ladder's no-upsampling
#             guard). Per clip: the tile set, the source tiles under the box
#             (ept-sources manifest) with their instrument (LAS system id) and
#             file creation dates, the acquisition dates read from GPS time,
#             all-return and first-return density, returns per pulse, whether
#             return numbers are populated (at least 99% of the points carry a
#             return number and a number of returns of at least 1) and the
#             counts of invalid return records, which are kept unchanged. ->
#             clips/<SITE>/<plot>/<variant>/, clips_index.csv, sources.csv.
#   score     per clip, as calval_multichm_gated.R cv_candidates_job and
#             cv_score_job do for a cell: canopy-model resolution 0.25 m at 8
#             first returns per m2 or more, else 0.5 m; lidRplugins::multichm on
#             the clip (a failure skips the cell, as the stock arm skips it, and
#             is recorded); mcg_prepare(las, res, a = 0.10); the stock
#             configuration's parity with the package; mcg_apply(prep, cfg) for
#             the five configurations (CONFIGS=, grid labels of mcg_grid());
#             mcg_score_cell(stems, det, cx, cy, half, offsets, tol = TOL) with
#             mcg_null_offsets(site, plot, half, tol = TOL, k = K). A clip
#             without populated return numbers is left out for every
#             configuration (the gated configurations read them). ->
#             cells_native.csv, cells_dec2.csv (the columns of the calibration
#             study's cells.csv, rung "3dep_native" / "3dep_dec2"),
#             clips.csv (clips_index plus the stand features, the deeper-layer
#             first-return shares and the 2021 NEON values of the same plot
#             from the calibration study's candidates), candidates/*.rds (the
#             prepared cells), skipped.csv, summary.csv (mcg_pool per variant,
#             scope and configuration) and transfer.csv (closed and widely
#             spaced plots on the 3DEP and the 2021 clips).
#   harness   the cell pipeline above run on the 2021 NEON frozen clips
#             (HARNESS=ALL, or a number of plots per site, or a comma list of
#             plots; HARNESS_RUNGS=native,2) and compared with the calibration
#             study's cells (CAL_OUT/cells.csv): every count column, the null
#             means, cover, top height, crown spacing and densities, for the
#             five configurations. -> harness.csv.
#   xcheck    the native QL2 cross-check's own clip definition as it was
#             before that study's correction of 17 November 2026 (its cached
#             PAD=45 clouds under XCHECK_CACHE/neon/<SITE>/ql2, read as they
#             are, its seeded thinning and normalisation) run through the
#             stock configuration and scored as that study scored, against
#             its multichm rows in
#             XCHECK_JOB/neon/<SITE>/ql2/ql2_detect_results.csv; and, beside it,
#             this study's stock counts on its own clips. -> xcheck.csv.
#
# Usage:
#   export CLAUDE_JOB_DIR=$(pwd)/work
#   Rscript scripts/confirm_gated_3dep.R [STAGE=all|discover|pull|clips|score|harness|xcheck]
#     [SITES=SJER,SOAP,TEAK,WREF,ABBY] [POP=adopted] [CORES=6] [K=200] [TOL=4]
#     [RUNG=2] [SEED_KEY=3DEP-2] [BUFFER=25] [CONFIGS=stock,z5_s0_c0_e0,...]
#     [REF_JOB=$CLAUDE_JOB_DIR/paper_runs] [FROZEN_ROOT=$CLAUDE_JOB_DIR/neon/frozen_2021]
#     [CAL_OUT=$CLAUDE_JOB_DIR/multichm_gated_runs/neon/multichm_gated]
#     [OUT=$CLAUDE_JOB_DIR/multichm_gated_confirmation/3dep] [INDEX=<resources.geojson>]
#     [EPT_<SITE>=<ept.json url>] [PDAL_THREADS=2] [HARNESS=ALL] [HARNESS_RUNGS=native,2]
#     [XCHECK_JOB=$CLAUDE_JOB_DIR/paper_runs] [XCHECK_CACHE=$CLAUDE_JOB_DIR]
# Network: the public 3DEP boundary index (raw.githubusercontent.com/hobuinc/
# usgs-lidar) and the public usgs-lidar-public EPT bucket only.
suppressMessages({ library(lidR); library(lidRplugins); library(sf)
                   library(data.table); library(jsonlite); library(parallel) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))           # plot_half, score_plot, ws_factory, plot_lapply
source(.find("model_bench_lib.R"))     # frozen_*, seed_for, assert_detection_contract
source(.find("multichm_gated_lib.R"))  # mcg_* detector, scoring and pooling
source(.find("ept_discovery.R"))       # INDEX_URLS, score_candidate

C3_SITES   <- c("SJER", "SOAP", "TEAK", "WREF", "ABBY")
C3_REGIONS <- list(California = c("SJER", "SOAP", "TEAK"), Washington = c("WREF", "ABBY"))
C3_CLASSES <- c("dominant", "codominant", "intermediate", "suppressed")
C3_A       <- 0.10
# The five frozen configurations of the protocol, by their mcg_grid() labels.
C3_CONFIGS <- c("stock", "z5_s0_c0_e0", "z5_s0_c0.6_e1", "z5_s0.75_c0.6_e1_d8",
                "z5_s0.75_c0.6_e1")
C3_VARIANTS <- c("3dep_native", "3dep_dec2")
C3_CELL_COLS <- c("site", "plot", "plotType", "rung", "cover", "top_height", "crown_spacing",
                  "pdens", "frdens", "config", "config_id", "zmin", "min_share", "cover_min",
                  "surface_exempt", "spacing_min", "n_dominant", "n_codominant",
                  "n_intermediate", "n_suppressed", MCG_COUNT_COLS)
C3_EPT_BUCKET <- "https://s3-us-west-2.amazonaws.com/usgs-lidar-public"
C3_GPS_EPOCH  <- as.POSIXct("1980-01-06 00:00:00", tz = "UTC")
C3_CLOSED_COVER <- 0.6   # the closed-stand threshold of the gated configurations
C3_WIDE_SPACING <- 8     # the declared configuration's crown-spacing threshold (m)

## ---- arguments ----------------------------------------------------------------------------
c3_settings <- function(args = commandArgs(TRUE), d = .job_dir()) {
  a <- strsplit(args, "=", fixed = TRUE)
  A <- stats::setNames(lapply(a, function(z) paste(z[-1], collapse = "=")),
                       vapply(a, `[`, character(1), 1))
  arg <- function(k, default) if (is.null(A[[k]]) || !nzchar(A[[k]])) default else A[[k]]
  split <- function(x) strsplit(x, ",", fixed = TRUE)[[1]]
  S <- list(
    A = A, d = d,
    STAGE = arg("STAGE", "all"),
    SITES = split(arg("SITES", paste(C3_SITES, collapse = ","))),
    POP = arg("POP", "adopted"),
    CORES = as.integer(arg("CORES", "6")),
    K = as.integer(arg("K", "200")),
    TOL = as.numeric(arg("TOL", "4")),
    RUNG = as.numeric(arg("RUNG", "2")),
    SEED_KEY = arg("SEED_KEY", "3DEP-2"),
    BUFFER = as.numeric(arg("BUFFER", as.character(BUF))),
    CONFIGS = split(arg("CONFIGS", paste(C3_CONFIGS, collapse = ","))),
    PDAL_THREADS = as.integer(arg("PDAL_THREADS", "2")),
    REF_JOB = arg("REF_JOB", file.path(d, "paper_runs")),
    FROZEN_ROOT = arg("FROZEN_ROOT", file.path(d, "neon", "frozen_2021")),
    CAL_OUT = arg("CAL_OUT", file.path(d, "multichm_gated_runs", "neon", "multichm_gated")),
    OUT = arg("OUT", file.path(d, "multichm_gated_confirmation", "3dep")),
    INDEX = arg("INDEX", NA_character_),
    HARNESS = arg("HARNESS", "ALL"),
    HARNESS_RUNGS = split(arg("HARNESS_RUNGS", "native,2")),
    XCHECK_JOB = arg("XCHECK_JOB", file.path(d, "paper_runs")),
    XCHECK_CACHE = arg("XCHECK_CACHE", d))
  if (!S$STAGE %in% c("all", "discover", "pull", "clips", "score", "harness", "xcheck"))
    stop("STAGE must be all, discover, pull, clips, score, harness or xcheck", call. = FALSE)
  if (!all(S$SITES %in% C3_SITES)) stop("SITES must be among ", paste(C3_SITES, collapse = ","),
                                        call. = FALSE)
  if (anyNA(c(S$CORES, S$K, S$TOL, S$RUNG, S$BUFFER, S$PDAL_THREADS)) || S$CORES < 1 ||
      S$K < 1 || S$TOL <= 0 || S$RUNG <= 0 || S$BUFFER < 0 || S$PDAL_THREADS < 1)
    stop("invalid numeric argument (CORES, K, TOL, RUNG, BUFFER, PDAL_THREADS)", call. = FALSE)
  c3_config_table(S$CONFIGS)               # stops on a label outside the grid
  c3_check_out(S$OUT)
  S
}

# The output root must not lie in a read-only input tree of the benchmark.
c3_check_out <- function(out) {
  p <- normalizePath(out, mustWork = FALSE)
  bad <- c("paper_runs[^/]*", "neon/frozen_[^/]*", "multichm_gated_runs[^/]*")
  if (any(vapply(bad, function(b) grepl(paste0("/work/", b, "(/|$)"), p), logical(1))))
    stop("OUT lies in a read-only input tree: ", p, call. = FALSE)
  invisible(p)
}

# The configurations to score: rows of mcg_grid() for `labels`, in that order.
c3_config_table <- function(labels = C3_CONFIGS, grid = mcg_grid()) {
  i <- match(labels, grid$label)
  if (anyNA(i)) stop("not grid labels: ", paste(labels[is.na(i)], collapse = ","), call. = FALSE)
  g <- grid[i, , drop = FALSE]
  rownames(g) <- NULL
  g
}

## ---- plots and stems ----------------------------------------------------------------------
# The declared plots of each site with at least one gated stem in the core, as
# calval_multichm_gated.R cv_jobs builds them (centroids from plot_centroids.csv,
# which must agree with the frozen root's population.csv).
c3_plots <- function(S) {
  out <- list()
  A <- list(FROZEN_ROOT = S$FROZEN_ROOT, POP = S$POP)
  pop <- read.csv(file.path(S$FROZEN_ROOT, "population.csv"), stringsAsFactors = FALSE)
  for (site in S$SITES) {
    nd <- file.path(S$REF_JOB, "neon", site)
    gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
    fz <- frozen_scope(S$REF_JOB, site, A, gt)
    epsg <- neon_validate_inputs(fz$gt, pc)
    for (pid in intersect(fz$plots, pc$plotID)) {
      ci <- pc[pc$plotID == pid, ][1, ]
      pr <- pop[pop$site == site & pop$plotID == pid, , drop = FALSE]
      if (nrow(pr) != 1L || abs(pr$easting - ci$easting) > 1e-6 ||
          abs(pr$northing - ci$northing) > 1e-6 || pr$epsg != epsg)
        stop("plot geometry differs between plot_centroids.csv and the frozen root: ", pid,
             call. = FALSE)
      ph <- plot_half(ci$plotType)
      stems <- fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - ci$easting) <= ph &
                       abs(fz$gt$N - ci$northing) <= ph, , drop = FALSE]
      if (nrow(stems) < 1) next
      out[[length(out) + 1L]] <- list(site = site, plot = pid, plotType = ci$plotType,
                                      cx = ci$easting, cy = ci$northing, half = ph,
                                      epsg = as.integer(epsg), population = fz$population,
                                      stems = stems)
    }
  }
  out
}
c3_plot_frame <- function(plots)
  data.frame(site = vapply(plots, `[[`, "", "site"), plot = vapply(plots, `[[`, "", "plot"),
             plotType = vapply(plots, `[[`, "", "plotType"),
             cx = vapply(plots, `[[`, 0, "cx"), cy = vapply(plots, `[[`, 0, "cy"),
             half = vapply(plots, `[[`, 0, "half"), epsg = vapply(plots, `[[`, 0L, "epsg"),
             n_stems = vapply(plots, function(p) nrow(p$stems), 0L), stringsAsFactors = FALSE)

## ---- geometry -----------------------------------------------------------------------------
# The clip box: nominal core half-width plus the buffer, around the centroid.
c3_clip_box <- function(cx, cy, core_half, buffer = BUF) {
  h <- core_half + buffer
  c(xmin = cx - h, ymin = cy - h, xmax = cx + h, ymax = cy + h)
}

# The box as an sfc polygon in `epsg`.
c3_box_polygon <- function(box, epsg)
  sf::st_sfc(sf::st_polygon(list(rbind(c(box[["xmin"]], box[["ymin"]]),
                                       c(box[["xmax"]], box[["ymin"]]),
                                       c(box[["xmax"]], box[["ymax"]]),
                                       c(box[["xmin"]], box[["ymax"]]),
                                       c(box[["xmin"]], box[["ymin"]])))), crs = epsg)

# Bounding box of `box` (in `from`) transformed to `to`, the box densified so
# that curved edges are covered, widened by `margin` (units of `to`).
c3_box_in <- function(box, from, to, margin = 0) {
  p <- sf::st_segmentize(c3_box_polygon(box, from), dfMaxLength = 5)
  b <- sf::st_bbox(sf::st_transform(p, to))
  c(xmin = b[["xmin"]] - margin, ymin = b[["ymin"]] - margin,
    xmax = b[["xmax"]] + margin, ymax = b[["ymax"]] + margin)
}

# readers.ept bounds string for a bbox.
c3_bounds_string <- function(b)
  sprintf("([%.3f, %.3f], [%.3f, %.3f])", b[["xmin"]], b[["xmax"]], b[["ymin"]], b[["ymax"]])

## ---- discovery ----------------------------------------------------------------------------
c3_index_path <- function(S) {
  if (!is.na(S$INDEX)) {
    if (!file.exists(S$INDEX)) stop("INDEX not found: ", S$INDEX, call. = FALSE)
    return(S$INDEX)
  }
  dest <- file.path(S$OUT, "ept_index", "resources.geojson")
  if (file.exists(dest) && file.info(dest)$size > 1e6) return(dest)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  for (u in INDEX_URLS) {
    ok <- tryCatch({
      utils::download.file(u, dest, quiet = TRUE, mode = "wb")
      file.exists(dest) && file.info(dest)$size > 1e6
    }, error = function(e) FALSE)
    if (ok) {
      writeLines(c(u, format(Sys.time(), tz = "UTC", usetz = TRUE)), paste0(dest, ".source"))
      return(dest)
    }
  }
  stop("could not fetch the EPT boundary index", call. = FALSE)
}

# Candidate tile sets per plot: one row per plot x index entry whose footprint
# meets the plot's clip box, with `covers` (the footprint covers the whole box).
c3_candidates <- function(pf, bnd, buffer) {
  s2 <- sf::sf_use_s2(); on.exit(suppressMessages(sf::sf_use_s2(s2)), add = TRUE)
  suppressMessages(sf::sf_use_s2(FALSE))
  rows <- list()
  for (i in seq_len(nrow(pf))) {
    box <- c3_clip_box(pf$cx[i], pf$cy[i], pf$half[i], buffer)
    poly <- sf::st_transform(sf::st_segmentize(c3_box_polygon(box, pf$epsg[i]), 5), 4326)
    hit <- suppressMessages(which(sf::st_intersects(bnd, poly, sparse = FALSE)[, 1]))
    if (!length(hit)) next
    cov <- suppressMessages(sf::st_covers(bnd[hit, ], poly, sparse = FALSE)[, 1])
    rows[[length(rows) + 1L]] <- data.frame(site = pf$site[i], plot = pf$plot[i],
                                            name = as.character(bnd$name[hit]),
                                            url = as.character(bnd$url[hit]), covers = cov,
                                            stringsAsFactors = FALSE)
  }
  if (!length(rows))
    return(data.frame(site = character(), plot = character(), name = character(),
                      url = character(), covers = logical(), stringsAsFactors = FALSE))
  do.call(rbind, rows)
}

# The tile set of each plot: among the tile sets that cover its whole box, the
# first by score_candidate() (ept_discovery.R), then by the number of the
# site's plots it covers, then by name. `override` maps a site to an EPT url
# that is used for every plot of that site. Returns one row per plot of `pf`:
# tileset, url (NA when none covers it), n_covering and the other covering
# tile sets.
c3_choose_tileset <- function(pf, cand, override = list(), score = score_candidate) {
  out <- lapply(seq_len(nrow(pf)), function(i) {
    s <- pf$site[i]; p <- pf$plot[i]
    ov <- override[[s]]
    if (!is.null(ov) && !is.na(ov) && nzchar(ov))
      return(data.frame(site = s, plot = p, tileset = basename(dirname(ov)), url = ov,
                        n_covering = NA_integer_, others = "", rule = "override",
                        stringsAsFactors = FALSE))
    c <- cand[cand$site == s & cand$plot == p & cand$covers, , drop = FALSE]
    if (!nrow(c))
      return(data.frame(site = s, plot = p, tileset = NA_character_, url = NA_character_,
                        n_covering = 0L, others = "", rule = "none covers the clip box",
                        stringsAsFactors = FALSE))
    site_cov <- table(cand$name[cand$site == s & cand$covers])
    c$score <- vapply(c$name, score, numeric(1))
    c$n_site <- as.integer(site_cov[c$name])
    c <- c[order(-c$score, -c$n_site, c$name), , drop = FALSE]
    data.frame(site = s, plot = p, tileset = c$name[1], url = c$url[1], n_covering = nrow(c),
               others = paste(c$name[-1], collapse = ";"), rule = "score_candidate",
               stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

c3_overrides <- function(S)
  stats::setNames(lapply(S$SITES, function(s) S$A[[paste0("EPT_", s)]]), S$SITES)

c3_stage_discover <- function(S) {
  pf <- c3_plot_frame(c3_plots(S))
  idx <- c3_index_path(S)
  bnd <- sf::st_read(idx, quiet = TRUE)
  if (is.na(sf::st_crs(bnd))) sf::st_crs(bnd) <- 4326
  bnd <- sf::st_make_valid(bnd)
  cand <- c3_candidates(pf, bnd, S$BUFFER)
  ch <- c3_choose_tileset(pf, cand, c3_overrides(S))
  cov <- merge(pf, ch, by = c("site", "plot"), sort = FALSE)
  cov <- cov[order(match(cov$site, C3_SITES), cov$plot), , drop = FALSE]
  cov$index_sha256 <- digest::digest(file = idx, algo = "sha256")
  write.csv(cand, file.path(S$OUT, "ept_candidates.csv"), row.names = FALSE)
  write.csv(cov, file.path(S$OUT, "coverage.csv"), row.names = FALSE)
  for (s in S$SITES) {
    x <- cov[cov$site == s, , drop = FALSE]
    cat(sprintf("[discover] %s: %d plots, %d covered (%s)\n", s, nrow(x), sum(!is.na(x$url)),
                paste(unique(stats::na.omit(x$tileset)), collapse = ", ")))
  }
  invisible(cov)
}

## ---- EPT metadata -------------------------------------------------------------------------
c3_fetch <- function(url, dest) {
  if (file.exists(dest) && file.info(dest)$size > 0) return(dest)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(dest, ".part")
  utils::download.file(url, tmp, quiet = TRUE, mode = "wb")
  if (!file.rename(tmp, dest)) stop("could not write ", dest)
  dest
}
c3_meta_dir <- function(S, tileset) file.path(S$OUT, "ept_meta", tileset)
c3_ept_json <- function(S, tileset, url)
  jsonlite::fromJSON(c3_fetch(url, file.path(c3_meta_dir(S, tileset), "ept.json")))
c3_ept_srs <- function(ej) {
  s <- ej$srs
  if (is.null(s$horizontal) || !nzchar(as.character(s$horizontal)))
    stop("the EPT declares no horizontal EPSG code", call. = FALSE)
  as.integer(s$horizontal)
}
c3_sources_manifest <- function(S, tileset, url) {
  f <- c3_fetch(sub("ept\\.json$", "ept-sources/manifest.json", url),
                file.path(c3_meta_dir(S, tileset), "manifest.json"))
  m <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  data.frame(path = vapply(m, function(x) as.character(x$path), ""),
             metadataPath = vapply(m, function(x)
               if (is.null(x$metadataPath)) NA_character_ else as.character(x$metadataPath), ""),
             xmin = vapply(m, function(x) as.numeric(x$bounds[[1]]), 0),
             ymin = vapply(m, function(x) as.numeric(x$bounds[[2]]), 0),
             xmax = vapply(m, function(x) as.numeric(x$bounds[[4]]), 0),
             ymax = vapply(m, function(x) as.numeric(x$bounds[[5]]), 0),
             points = vapply(m, function(x) as.numeric(x$points), 0), stringsAsFactors = FALSE)
}
# Header fields of one source tile (readers.las metadata of the EPT build).
c3_source_header <- function(S, tileset, url, metadata_path) {
  f <- c3_fetch(sub("ept\\.json$", paste0("ept-sources/", metadata_path), url),
                file.path(c3_meta_dir(S, tileset), "sources", metadata_path))
  m <- jsonlite::fromJSON(f, simplifyVector = FALSE)$metadata$readers.las
  g <- function(k) if (is.null(m[[k]])) NA else m[[k]]
  data.frame(system_id = as.character(g("system_id")), software_id = as.character(g("software_id")),
             creation_year = as.integer(g("creation_year")),
             creation_doy = as.integer(g("creation_doy")),
             global_encoding = as.integer(g("global_encoding")),
             dataformat_id = as.integer(g("dataformat_id")), stringsAsFactors = FALSE)
}
# Sources of `man` whose bounds meet bbox `b` (both in the EPT's SRS).
c3_sources_under <- function(man, b)
  man[man$xmax >= b[["xmin"]] & man$xmin <= b[["xmax"]] & man$ymax >= b[["ymin"]] &
        man$ymin <= b[["ymax"]], , drop = FALSE]

## ---- pull ---------------------------------------------------------------------------------
# The PDAL pipeline of one pull (a list, written as JSON).
c3_pdal_pipeline <- function(ept_url, bounds, out_srs, out_file, threads = 2L)
  list(list(type = "readers.ept", filename = ept_url, bounds = bounds,
            threads = as.integer(threads)),
       list(type = "filters.range",                     # drop noise and withheld points
            limits = "Classification![7:7],Classification![18:18],Withheld![1:1]"),
       list(type = "filters.reprojection", out_srs = out_srs),
       list(type = "writers.las", filename = out_file, compression = "laszip",
            minor_version = 4L, dataformat_id = 6L, global_encoding = 17L,
            scale_x = 0.01, scale_y = 0.01, scale_z = 0.01,
            offset_x = 0, offset_y = 0, offset_z = 0))

c3_cloud_file <- function(S, site, plot) file.path(S$OUT, "clouds", site, paste0(plot, ".laz"))

# The request a pulled cloud was made with (its cache key).
c3_pull_request <- function(ept_url, bounds, out_srs, buffer)
  list(ept_url = ept_url, bounds = bounds, out_srs = out_srs, buffer = buffer,
       filter = "Classification![7:7],Classification![18:18],Withheld![1:1]",
       format = "LAS 1.4 PDRF 6, scale 0.01, offset 0, global_encoding 17")

c3_pull_job <- function(j, S) {
  f <- c3_cloud_file(S, j$site, j$plot)
  req <- c3_pull_request(j$url, j$bounds, paste0("EPSG:", j$epsg), S$BUFFER)
  mf <- paste0(f, ".json")
  if (file.exists(f) && file.exists(mf)) {
    old <- jsonlite::read_json(mf, simplifyVector = TRUE)
    if (identical(old$request, jsonlite::fromJSON(jsonlite::toJSON(req, auto_unbox = TRUE,
                                                                   digits = NA))) &&
        identical(old$sha256, digest::digest(file = f, algo = "sha256")))
      return(data.frame(site = j$site, plot = j$plot, status = "cached",
                        seconds = as.numeric(old$seconds), bytes = file.info(f)$size,
                        http_bytes = if (is.null(old$http_bytes)) NA_real_ else old$http_bytes,
                        http_gets = if (is.null(old$http_gets)) NA_real_ else old$http_gets,
                        sha256 = old$sha256, stringsAsFactors = FALSE))
  }
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(f, ".part.laz")
  pj <- tempfile(fileext = ".json")
  on.exit(unlink(c(pj, tmp)), add = TRUE)
  writeLines(jsonlite::toJSON(c3_pdal_pipeline(j$url, j$bounds, req$out_srs, tmp,
                                               S$PDAL_THREADS),
                              auto_unbox = TRUE, pretty = TRUE, digits = NA), pj)
  t0 <- Sys.time()
  # ARBITER_VERBOSE makes PDAL's HTTP layer log each request and response
  # header, from which the transferred volume is summed (c3_http_volume)
  rc <- suppressWarnings(system2("pdal", c("pipeline", shQuote(pj)), stdout = TRUE,
                                 stderr = TRUE, env = "ARBITER_VERBOSE=1"))
  sec <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  st <- attr(rc, "status")
  vol <- c3_http_volume(rc)
  if ((!is.null(st) && st != 0) || !file.exists(tmp) || file.info(tmp)$size < 500)
    return(data.frame(site = j$site, plot = j$plot,
                      status = paste("failed:", paste(utils::tail(rc, 3), collapse = " | ")),
                      seconds = sec, bytes = NA_real_, http_bytes = vol[["bytes"]],
                      http_gets = vol[["gets"]], sha256 = NA_character_,
                      stringsAsFactors = FALSE))
  if (!file.rename(tmp, f)) stop("could not write ", f)
  sha <- digest::digest(file = f, algo = "sha256")
  jsonlite::write_json(list(request = req, sha256 = sha,
                            pulled_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
                            pdal = system2("pdal", "--version", stdout = TRUE)[2],
                            seconds = sec, http_bytes = vol[["bytes"]],
                            http_gets = vol[["gets"]]),
                       mf, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  data.frame(site = j$site, plot = j$plot, status = "pulled", seconds = sec,
             bytes = file.info(f)$size, http_bytes = vol[["bytes"]], http_gets = vol[["gets"]],
             sha256 = sha, stringsAsFactors = FALSE)
}

# The HTTP volume of one PDAL run from its ARBITER_VERBOSE log: the number of
# GET requests and the sum of the response Content-Length headers.
c3_http_volume <- function(log) {
  cl <- grep("^< content-length:", log, ignore.case = TRUE, value = TRUE)
  c(gets = sum(grepl("^> GET ", log)),
    bytes = sum(as.numeric(sub("^< content-length:\\s*", "", trimws(cl), ignore.case = TRUE))))
}

c3_read_coverage <- function(S) {
  f <- file.path(S$OUT, "coverage.csv")
  if (!file.exists(f)) stop("no coverage.csv in ", S$OUT, "; run STAGE=discover", call. = FALSE)
  cov <- read.csv(f, stringsAsFactors = FALSE)
  cov[cov$site %in% S$SITES, , drop = FALSE]
}

c3_stage_pull <- function(S) {
  cov <- c3_read_coverage(S)
  cov <- cov[!is.na(cov$url), , drop = FALSE]
  if (!nrow(cov)) { cat("[pull] no covered plot\n"); return(invisible(NULL)) }
  jobs <- lapply(seq_len(nrow(cov)), function(i) {
    ej <- c3_ept_json(S, cov$tileset[i], cov$url[i])
    srs <- c3_ept_srs(ej)
    box <- c3_clip_box(cov$cx[i], cov$cy[i], cov$half[i], S$BUFFER)
    list(site = cov$site[i], plot = cov$plot[i], url = cov$url[i], epsg = cov$epsg[i],
         bounds = c3_bounds_string(c3_box_in(box, cov$epsg[i], srs, margin = 1)))
  })
  cat(sprintf("[pull] %d plots, %d at a time, %d PDAL threads each\n", length(jobs),
              max(1L, S$CORES %/% S$PDAL_THREADS), S$PDAL_THREADS))
  t0 <- Sys.time()
  res <- plot_lapply(jobs, c3_pull_job, S = S, mc.cores = max(1L, S$CORES %/% S$PDAL_THREADS))
  wall <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  bad <- !vapply(res, is.data.frame, logical(1))
  if (any(bad)) stop("pull workers failed: ", paste(vapply(jobs[bad], `[[`, "", "plot"),
                                                     collapse = ","), call. = FALSE)
  pulls <- do.call(rbind, res)
  pulls$bounds <- vapply(jobs, `[[`, "", "bounds")
  pulls$url <- vapply(jobs, `[[`, "", "url")
  write.csv(pulls, file.path(S$OUT, "pulls.csv"), row.names = FALSE)
  jsonlite::write_json(list(minutes_this_run = wall, plots = nrow(pulls),
                            pulled = sum(pulls$status == "pulled"),
                            cached = sum(pulls$status == "cached"),
                            pull_seconds = sum(pulls$seconds, na.rm = TRUE),
                            http_gets = sum(pulls$http_gets, na.rm = TRUE),
                            http_bytes = sum(pulls$http_bytes, na.rm = TRUE),
                            laz_bytes = sum(pulls$bytes, na.rm = TRUE)),
                       file.path(S$OUT, "pull_volume.json"), auto_unbox = TRUE, pretty = TRUE,
                       digits = NA)
  cat(sprintf("[pull] %d pulled, %d cached, %d failed in %.1f min; %.0f MB over %d HTTP GETs (pulls of this and earlier runs), %.0f MB of LAZ\n",
              sum(pulls$status == "pulled"), sum(pulls$status == "cached"),
              sum(grepl("^failed", pulls$status)), wall,
              sum(pulls$http_bytes, na.rm = TRUE) / 1e6, sum(pulls$http_gets, na.rm = TRUE),
              sum(pulls$bytes, na.rm = TRUE) / 1e6))
  invisible(pulls)
}

## ---- clips --------------------------------------------------------------------------------
# Return numbers are populated when at least `min_share` of the points carry a
# return number and a number of returns of at least 1 (the cloud has them; a
# cloud without them has zeros throughout). Invalid records (a zero, or a
# return number above the number of returns) are counted by c3_clip_stats and
# kept as they are: the detector reads ReturnNumber == 1 as first, as on every
# clip, and no value is changed.
C3_MIN_VALID_RETURNS <- 0.99
c3_valid_returns <- function(rn, nr) !is.na(rn) & !is.na(nr) & rn >= 1L & nr >= 1L
c3_returns_populated <- function(rn, nr, min_share = C3_MIN_VALID_RETURNS)
  length(rn) > 0 && mean(c3_valid_returns(rn, nr)) >= min_share

# Density and return structure of a normalized clip over `area` (m2).
c3_clip_stats <- function(rn, nr, area) {
  n <- length(rn); fr <- sum(rn == 1L, na.rm = TRUE)
  list(n = n, n_first = fr, pdens = n / area, frdens = fr / area,
       returns_per_pulse = if (fr > 0) n / fr else NA_real_,
       mean_returns_first = if (fr > 0) mean(nr[rn == 1L]) else NA_real_,
       returns_populated = c3_returns_populated(rn, nr),
       share_valid_returns = if (n) mean(c3_valid_returns(rn, nr)) else NA_real_,
       n_return_zero = sum(rn == 0L, na.rm = TRUE),
       n_number_zero = sum(nr == 0L, na.rm = TRUE),
       n_return_gt_number = sum(rn > nr, na.rm = TRUE))
}

# Acquisition dates from adjusted standard GPS time (seconds since the GPS
# epoch minus 1e9; leap seconds ignored, which cannot move a date by more than
# 18 s). NULL when the time is GPS week time (`adjusted` FALSE) or absent.
c3_gps_dates <- function(gpstime, adjusted = TRUE) {
  if (!isTRUE(adjusted) || !length(gpstime) || all(is.na(gpstime))) return(NULL)
  as.Date(C3_GPS_EPOCH + (gpstime + 1e9), tz = "UTC")
}
c3_date_summary <- function(dates) {
  if (is.null(dates) || !length(dates))
    return(list(acq_first = NA_character_, acq_last = NA_character_,
                acq_years = NA_character_, acq_days = NA_integer_))
  u <- sort(unique(dates))
  list(acq_first = format(min(u)), acq_last = format(max(u)),
       acq_years = paste(sort(unique(format(u, "%Y"))), collapse = ";"),
       acq_days = length(u))
}

c3_clip_dir <- function(S, site, plot, variant) file.path(S$OUT, "clips", site, plot, variant)

# One plot's two clips from its pulled cloud, as frozen_clip() makes a cell.
# Returns one row per variant (status ok, upsampled or unusable).
c3_clip_job <- function(j, S) {
  threads <- lidR::get_lidr_threads()
  lidR::set_lidr_threads(FROZEN_LIDR_THREADS)
  on.exit(lidR::set_lidr_threads(threads), add = TRUE)
  raw <- c3_cloud_file(S, j$site, j$plot)
  raw_sha <- digest::digest(file = raw, algo = "sha256")
  box <- c3_clip_box(j$cx, j$cy, j$half, S$BUFFER)
  half <- j$half + S$BUFFER; area <- (2 * half)^2
  seed <- seed_for(j$site, j$plot, S$SEED_KEY)
  row <- function(variant, status, extra = list())
    as.data.frame(c(list(site = j$site, plot = j$plot, plotType = j$plotType, rung = variant,
                         status = status, cx = j$cx, cy = j$cy, core_half = j$half,
                         clip_half = half, epsg = j$epsg, tileset = j$tileset, ept_url = j$url,
                         seed = if (variant == "3dep_dec2") seed else NA_integer_,
                         seed_key = if (variant == "3dep_dec2") S$SEED_KEY else NA_character_,
                         decimation = if (variant == "3dep_dec2")
                           sprintf("homogenize(density = %g, res = 5)", S$RUNG) else "none",
                         raw_sha256 = raw_sha), extra), stringsAsFactors = FALSE)
  ctg <- lidR::readLAScatalog(raw)
  lidR::opt_progress(ctg) <- FALSE
  neon_assert_crs(ctg, j$epsg, "3DEP cloud")
  las <- lidR::clip_rectangle(ctg, box[["xmin"]], box[["ymin"]], box[["xmax"]], box[["ymax"]])
  if (lidR::is.empty(las) || lidR::npoints(las) < 100)
    return(rbind(row("3dep_native", "unusable: fewer than 100 points in the box"),
                 row("3dep_dec2", "unusable: no native clip")))
  frozen_canonical(las)
  key <- las@data[, intersect(FROZEN_POINT_ORDER, names(las@data)), with = FALSE]
  n_tied <- sum(duplicated(key))
  # whole-clip provenance: acquisition dates (GPS time) and overlap share
  dates <- c3_date_summary(c3_gps_dates(las@data$gpstime, isTRUE(j$gps_adjusted)))
  overlap <- if ("Overlap_flag" %in% names(las@data)) mean(las@data$Overlap_flag) else NA_real_
  common <- c(list(n_box = lidR::npoints(las), n_tied_keys = n_tied, overlap_share = overlap),
              dates)
  out <- list(); native_pdens <- NA_real_
  for (variant in C3_VARIANTS) {
    l <- las
    if (variant == "3dep_dec2") {
      if (is.na(native_pdens)) { out[[variant]] <- row(variant, "unusable: no native clip", common); next }
      if (S$RUNG >= native_pdens) {
        out[[variant]] <- row(variant, "upsampled", common); next
      }
      set.seed(seed)
      l <- lidR::decimate_points(las, lidR::homogenize(density = S$RUNG, res = 5))
    }
    n_ground <- sum(l$Classification == 2L)
    if (n_ground < 10) {
      out[[variant]] <- row(variant, "unusable: fewer than 10 ground points", common); next
    }
    dir <- c3_clip_dir(S, j$site, j$plot, variant)
    fp <- frozen_files(dir)
    mfile <- fp$manifest
    want <- list(raw_sha256 = raw_sha, seed = if (variant == "3dep_dec2") seed else NA,
                 rung = if (variant == "3dep_dec2") S$RUNG else NA, buffer = S$BUFFER,
                 lidr_threads = FROZEN_LIDR_THREADS, point_order = FROZEN_POINT_ORDER)
    cached <- file.exists(mfile) && all(file.exists(unlist(fp[c("rawground", "normalized")]))) &&
      isTRUE(all.equal(jsonlite::read_json(mfile, simplifyVector = TRUE)$request,
                       jsonlite::fromJSON(jsonlite::toJSON(want, auto_unbox = TRUE,
                                                           digits = NA))))
    if (!cached) {
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      dtm <- lidR::rasterize_terrain(l, res = 1, algorithm = lidR::tin())
      nrm <- lidR::normalize_height(l, lidR::tin(), na.rm = TRUE)
      nrm <- lidR::filter_poi(nrm, Z >= -1, Z < 80)
      lidR::writeLAS(l, fp$rawground)
      lidR::writeLAS(nrm, fp$normalized)
      terra::writeRaster(dtm, fp$dtm, overwrite = TRUE)
      jsonlite::write_json(list(request = want, site = j$site, plot = j$plot, variant = variant,
                                n_raw = lidR::npoints(l), n_norm = lidR::npoints(nrm),
                                n_ground = n_ground, sha256_normalized =
                                  digest::digest(file = fp$normalized, algo = "sha256")),
                           mfile, auto_unbox = TRUE, pretty = TRUE, digits = NA)
    }
    mf <- jsonlite::read_json(mfile, simplifyVector = TRUE)
    # densities and returns from the stored clip, as the scorer reads it
    h <- suppressWarnings(lidR::readLAS(fp$normalized, select = "rn"))
    st <- c3_clip_stats(h@data$ReturnNumber, h@data$NumberOfReturns, area)
    if (variant == "3dep_native") native_pdens <- st$pdens
    out[[variant]] <- row(variant, "ok", c(common, list(
      n_raw = mf$n_raw, n_norm = st$n, n_ground = mf$n_ground), st[setdiff(names(st), "n")],
      list(normalized = fp$normalized)))
  }
  data.table::rbindlist(out, fill = TRUE)
}

# The source tiles under each covered plot's box and their header fields.
c3_source_table <- function(S, cov) {
  rows <- list()
  for (ts in unique(cov$tileset)) {
    x <- cov[cov$tileset == ts, , drop = FALSE]
    url <- x$url[1]
    ej <- c3_ept_json(S, ts, url); srs <- c3_ept_srs(ej)
    man <- c3_sources_manifest(S, ts, url)
    for (i in seq_len(nrow(x))) {
      b <- c3_box_in(c3_clip_box(x$cx[i], x$cy[i], x$half[i], S$BUFFER), x$epsg[i], srs)
      u <- c3_sources_under(man, b)
      hdr <- do.call(rbind, lapply(u$metadataPath, function(m) c3_source_header(S, ts, url, m)))
      wu <- unique(sub("^.*/Projects/([^/]+)/.*$", "\\1", u$path))
      rows[[length(rows) + 1L]] <- data.frame(
        site = x$site[i], plot = x$plot[i], tileset = ts, ept_srs = srs,
        n_source_tiles = nrow(u), source_tiles = paste(basename(u$path), collapse = ";"),
        work_units = paste(wu, collapse = ";"),
        system_id = paste(sort(unique(hdr$system_id)), collapse = ";"),
        software_id = paste(sort(unique(hdr$software_id)), collapse = ";"),
        file_created = paste(sort(unique(sprintf("%d-%03d", hdr$creation_year,
                                                 hdr$creation_doy))), collapse = ";"),
        gps_adjusted = nrow(hdr) > 0 && all(bitwAnd(hdr$global_encoding, 1L) == 1L),
        source_pdrf = paste(sort(unique(hdr$dataformat_id)), collapse = ";"),
        stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) return(NULL)
  do.call(rbind, rows)
}

c3_stage_clips <- function(S) {
  cov <- c3_read_coverage(S)
  cov <- cov[!is.na(cov$url), , drop = FALSE]
  if (!nrow(cov)) { cat("[clips] no covered plot\n"); return(invisible(NULL)) }
  pulls <- read.csv(file.path(S$OUT, "pulls.csv"), stringsAsFactors = FALSE)
  ok <- paste(pulls$site, pulls$plot)[pulls$status %in% c("pulled", "cached")]
  cov <- cov[paste(cov$site, cov$plot) %in% ok, , drop = FALSE]
  src <- c3_source_table(S, cov)
  write.csv(src, file.path(S$OUT, "sources.csv"), row.names = FALSE)
  jobs <- lapply(seq_len(nrow(cov)), function(i) {
    s <- src[src$site == cov$site[i] & src$plot == cov$plot[i], , drop = FALSE]
    list(site = cov$site[i], plot = cov$plot[i], plotType = cov$plotType[i], cx = cov$cx[i],
         cy = cov$cy[i], half = cov$half[i], epsg = cov$epsg[i], tileset = cov$tileset[i],
         url = cov$url[i], gps_adjusted = isTRUE(s$gps_adjusted[1]))
  })
  cat(sprintf("[clips] %d plots\n", length(jobs)))
  t0 <- Sys.time()
  res <- plot_lapply(jobs, function(j, S) tryCatch(c3_clip_job(j, S), error = function(e) e),
                     S = S, mc.cores = S$CORES)
  bad <- vapply(res, function(r) inherits(r, "error"), logical(1))
  if (any(bad)) stop("clip jobs failed: ", paste(vapply(which(bad), function(i)
    paste0(jobs[[i]]$plot, " (", conditionMessage(res[[i]]), ")"), ""), collapse = "; "),
    call. = FALSE)
  idx <- as.data.frame(data.table::rbindlist(res, fill = TRUE))
  idx <- merge(idx, src[, setdiff(names(src), c("tileset")), drop = FALSE],
               by = c("site", "plot"), all.x = TRUE, sort = FALSE)
  idx <- idx[order(match(idx$site, C3_SITES), idx$plot, match(idx$rung, C3_VARIANTS)), ,
             drop = FALSE]
  write.csv(idx, file.path(S$OUT, "clips_index.csv"), row.names = FALSE)
  cat(sprintf("[clips] %d clips ok of %d in %.1f min\n", sum(idx$status == "ok"), nrow(idx),
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  invisible(idx)
}

## ---- cells --------------------------------------------------------------------------------
# locate_trees() sf -> the x, y, z detection contract (calval_multichm_gated.R
# cv_tops_to_det, repeated here because that script is not sourced).
c3_tops_to_det <- function(tt) {
  if (is.null(tt) || !nrow(tt)) return(data.frame(x = numeric(), y = numeric(), z = numeric()))
  co <- sf::st_coordinates(tt)
  z <- if (ncol(co) >= 3) co[, 3] else if (!is.null(tt$Z)) tt$Z else co[, 2] * 0
  data.frame(x = unname(co[, 1]), y = unname(co[, 2]), z = unname(z))
}
# Same points (count, then coordinates and heights within tol after sorting),
# as cv_same_dets.
c3_same_dets <- function(a, b, tol = 1e-6) {
  if (nrow(a) != nrow(b)) return(FALSE)
  if (!nrow(a)) return(TRUE)
  a <- a[order(a$x, a$y, a$z), c("x", "y", "z")]
  b <- b[order(b$x, b$y, b$z), c("x", "y", "z")]
  isTRUE(max(abs(as.matrix(a) - as.matrix(b))) <= tol)
}

# The canopy-model resolution of the calibration study.
c3_res <- function(frdens) if (frdens >= 8) 0.25 else 0.5

# Deeper-layer candidates and their first-return shares (recorded beside the
# stand features; the share decides only under a share gate).
c3_deep_shares <- function(cand, min_share = 0.75) {
  d <- cand[cand$layer > 1L, , drop = FALSE]
  list(n_cand = nrow(cand), n_deep = nrow(d),
       deep_share_median = if (nrow(d)) stats::median(d$share, na.rm = TRUE) else NA_real_,
       deep_share_ge = if (nrow(d)) mean(!is.na(d$share) & d$share >= min_share) else NA_real_)
}

# One cell: the package run, the preparation and the scores of `cfgs` (rows of
# c3_config_table). Returns list(skipped) when the package fails on the clip,
# else list(prep, res, parity, n_package, rows) with one row per configuration
# (C3_CELL_COLS).
c3_cell <- function(las, frdens, pdens, j, rung, cfgs, offs, tol = 4, a = C3_A) {
  res <- c3_res(frdens)
  pkg <- tryCatch(c3_tops_to_det(suppressWarnings(lidR::locate_trees(
    las, lidRplugins::multichm(res = res, ws = ws_factory(a))))), error = function(e) e)
  if (inherits(pkg, "error")) return(list(skipped = conditionMessage(pkg), res = res))
  prep <- mcg_prepare(las, res, a)
  stock <- mcg_apply(prep, MCG_STOCK)
  ncls <- vapply(C3_CLASSES, function(k) sum(j$stems$crown_class == k, na.rm = TRUE), numeric(1))
  memo <- new.env(parent = emptyenv())
  score <- function(det) {
    key <- digest::digest(list(det$x, det$y, det$z))
    if (is.null(memo[[key]]))
      memo[[key]] <- mcg_score_cell(j$stems, det, j$cx, j$cy, j$half, offs, tol = tol)
    memo[[key]]
  }
  rows <- lapply(seq_len(nrow(cfgs)), function(g) {
    cfg <- mcg_config(cfgs$zmin[g], cfgs$min_share[g], cfgs$cover_min[g],
                      cfgs$surface_exempt[g], cfgs$spacing_min[g])
    cbind(data.frame(site = j$site, plot = j$plot, plotType = j$plotType, rung = rung,
                     cover = prep$cover, top_height = prep$top_height,
                     crown_spacing = as.numeric(prep$crown_spacing), pdens = pdens,
                     frdens = frdens, config = cfgs$label[g], config_id = cfgs$config_id[g],
                     zmin = cfgs$zmin[g], min_share = cfgs$min_share[g],
                     cover_min = cfgs$cover_min[g], surface_exempt = cfgs$surface_exempt[g],
                     spacing_min = cfgs$spacing_min[g], n_dominant = ncls[["dominant"]],
                     n_codominant = ncls[["codominant"]],
                     n_intermediate = ncls[["intermediate"]],
                     n_suppressed = ncls[["suppressed"]], stringsAsFactors = FALSE),
          score(mcg_apply(prep, cfg)))
  })
  list(prep = prep, res = res, parity = c3_same_dets(stock, pkg, tol = 1e-9),
       n_package = nrow(pkg), n_stock = nrow(stock), rows = do.call(rbind, rows))
}

c3_score_job <- function(j, S, cfgs) {
  offs <- mcg_null_offsets(j$site, j$plot, j$half, tol = S$TOL, k = S$K)
  out <- list(); meta <- list()
  for (k in seq_len(nrow(j$clips))) {
    m <- j$clips[k, ]
    base <- list(site = j$site, plot = j$plot, rung = m$rung)
    if (!isTRUE(as.logical(m$returns_populated))) {
      meta[[length(meta) + 1L]] <- as.data.frame(c(base, list(
        scored = FALSE, reason = "return numbers not populated")), stringsAsFactors = FALSE)
      next
    }
    las <- lidR::readLAS(m$normalized)
    cell <- c3_cell(las, m$frdens, m$pdens, j, m$rung, cfgs, offs, tol = S$TOL)
    if (!is.null(cell$skipped)) {
      meta[[length(meta) + 1L]] <- as.data.frame(c(base, list(
        scored = FALSE, reason = paste("lidRplugins::multichm failed:", cell$skipped),
        res = cell$res)), stringsAsFactors = FALSE)
      next
    }
    f <- file.path(S$OUT, "candidates", sprintf("%s__%s__%s.rds", j$site, j$plot, m$rung))
    dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
    saveRDS(list(meta = m, prep = cell$prep, parity = cell$parity), f)
    p <- cell$prep
    meta[[length(meta) + 1L]] <- as.data.frame(c(base, list(
      scored = TRUE, reason = "", res = cell$res, cover = p$cover, top_height = p$top_height,
      crown_spacing = as.numeric(p$crown_spacing), n_crowns = p$n_crowns,
      crown_area = p$crown_area, n_layers = if (nrow(p$cand)) max(p$cand$layer) else 0L,
      n_stock = cell$n_stock, n_package = cell$n_package, parity = cell$parity),
      c3_deep_shares(p$cand)), stringsAsFactors = FALSE)
    out[[length(out) + 1L]] <- cell$rows
  }
  list(rows = if (length(out)) do.call(rbind, out),
       meta = as.data.frame(data.table::rbindlist(meta, fill = TRUE)))
}

# Plots whose clip of a variant lacks populated return numbers are left out of
# that variant for every configuration (the gated configurations read them);
# returns the plots to drop per variant.
c3_no_returns <- function(idx)
  idx[idx$status == "ok" & !as.logical(idx$returns_populated), c("site", "plot", "rung"),
      drop = FALSE]

# The 2021 NEON values of each plot from the calibration study's candidates
# (rung native and the thinned rung), and its deeper-layer shares from its
# prepared cells.
c3_neon_values <- function(S, keys) {
  cand <- read.csv(file.path(S$CAL_OUT, "candidates.csv"), stringsAsFactors = FALSE,
                   colClasses = c(rung = "character"))
  pick <- function(rung, prefix) {
    x <- cand[cand$rung == rung, c("site", "plot", "pdens", "frdens", "res", "cover",
                                   "top_height", "crown_spacing", "n_crowns", "n_cand",
                                   "file"), drop = FALSE]
    sh <- lapply(seq_len(nrow(x)), function(i) {
      f <- file.path(S$CAL_OUT, "candidates", x$file[i])
      if (!file.exists(f)) return(c3_deep_shares(data.frame(layer = integer(), share = numeric())))
      c3_deep_shares(readRDS(f)$prep$cand)
    })
    x$returns_per_pulse <- x$pdens / x$frdens
    x$n_deep <- vapply(sh, `[[`, 0L, "n_deep")
    x$deep_share_median <- vapply(sh, `[[`, 0, "deep_share_median")
    x$deep_share_ge <- vapply(sh, `[[`, 0, "deep_share_ge")
    x$file <- NULL
    names(x)[-(1:2)] <- paste0(prefix, names(x)[-(1:2)])
    x
  }
  nat <- pick("native", "neon_native_")
  thin <- pick(format(S$RUNG), "neon_rung2_")
  v <- merge(nat, thin, by = c("site", "plot"), all = TRUE)
  merge(keys, v, by = c("site", "plot"), all.x = TRUE, sort = FALSE)
}

# Closed (cover >= 0.6) and widely spaced (crown spacing >= 8 m) per clip.
c3_state <- function(cover, spacing)
  data.frame(closed = !is.na(cover) & cover >= C3_CLOSED_COVER,
             spaced = !is.na(spacing) & spacing >= C3_WIDE_SPACING,
             gated = !is.na(cover) & cover >= C3_CLOSED_COVER &
               !is.na(spacing) & spacing >= C3_WIDE_SPACING)

# Per site and variant: closed / spaced / both on the 3DEP clip and on the 2021
# clip (native against native, thinned against the 2021 thinned rung), and how
# many plots change each state.
c3_transfer <- function(clips) {
  x <- clips[clips$scored %in% TRUE, , drop = FALSE]
  if (!nrow(x)) return(NULL)
  ref_cover <- ifelse(x$rung == "3dep_native", x$neon_native_cover, x$neon_rung2_cover)
  ref_spacing <- ifelse(x$rung == "3dep_native", x$neon_native_crown_spacing,
                        x$neon_rung2_crown_spacing)
  a <- c3_state(x$cover, x$crown_spacing); b <- c3_state(ref_cover, ref_spacing)
  scopes <- c(stats::setNames(as.list(unique(x$site)), unique(x$site)), C3_REGIONS)
  out <- list()
  for (v in unique(x$rung)) for (sc in names(scopes)) {
    k <- x$rung == v & x$site %in% scopes[[sc]]
    if (!any(k)) next
    out[[length(out) + 1L]] <- data.frame(
      variant = v, scope = sc, plots = sum(k),
      closed_3dep = sum(a$closed[k]), closed_2021 = sum(b$closed[k]),
      closed_changed = sum(a$closed[k] != b$closed[k]),
      spaced_3dep = sum(a$spaced[k]), spaced_2021 = sum(b$spaced[k]),
      spaced_changed = sum(a$spaced[k] != b$spaced[k]),
      gated_3dep = sum(a$gated[k]), gated_2021 = sum(b$gated[k]),
      gated_changed = sum(a$gated[k] != b$gated[k]), stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

# Pooled counts and rates (mcg_pool) per variant, scope (each site, each region,
# all) and configuration.
c3_summary <- function(cells) {
  scopes <- c(stats::setNames(as.list(unique(cells$site)), unique(cells$site)), C3_REGIONS,
              list(all = unique(cells$site)))
  out <- list()
  for (sc in names(scopes)) {
    x <- cells[cells$site %in% scopes[[sc]], , drop = FALSE]
    if (!nrow(x)) next
    p <- mcg_pool(x, c("rung", "config"))
    n <- tapply(paste(x$site, x$plot), paste(x$rung, x$config), function(v) length(unique(v)))
    p$n_plots <- as.integer(n[paste(p$rung, p$config)])
    p$scope <- sc
    out[[length(out) + 1L]] <- p
  }
  s <- as.data.frame(data.table::rbindlist(out, fill = TRUE))
  s[order(s$rung, match(s$scope, names(scopes)), match(s$config, C3_CONFIGS)),
    c("rung", "scope", "config", "n_plots", setdiff(names(s), c("rung", "scope", "config",
                                                                 "n_plots"))), drop = FALSE]
}

c3_stage_score <- function(S) {
  f <- file.path(S$OUT, "clips_index.csv")
  idx <- if (file.exists(f)) read.csv(f, stringsAsFactors = FALSE)
  if (!is.null(idx)) idx <- idx[idx$site %in% S$SITES, , drop = FALSE]
  if (is.null(idx) || !any(idx$status == "ok")) {
    cat("[score] no usable clip of the requested sites\n"); return(invisible(NULL))
  }
  cfgs <- c3_config_table(S$CONFIGS)
  plots <- c3_plots(S)
  keys <- paste(vapply(plots, `[[`, "", "site"), vapply(plots, `[[`, "", "plot"))
  ok <- idx[idx$status == "ok", , drop = FALSE]
  jobs <- lapply(unique(paste(ok$site, ok$plot)), function(k) {
    j <- plots[[match(k, keys)]]
    j$clips <- ok[paste(ok$site, ok$plot) == k, , drop = FALSE]
    j
  })
  cat(sprintf("[score] %d clips of %d plots x %d configurations, K = %d, TOL = %g\n", nrow(ok),
              length(jobs), nrow(cfgs), S$K, S$TOL))
  frozen_stamp(file.path(S$OUT, "candidates"), S$FROZEN_ROOT)
  t0 <- Sys.time()
  res <- plot_lapply(jobs, function(j, S, cfgs) tryCatch(c3_score_job(j, S, cfgs),
                                                        error = function(e) e),
                     S = S, cfgs = cfgs, mc.cores = S$CORES)
  bad <- vapply(res, function(r) inherits(r, "error"), logical(1))
  if (any(bad)) stop("score jobs failed: ", paste(vapply(which(bad), function(i)
    paste0(jobs[[i]]$plot, " (", conditionMessage(res[[i]]), ")"), ""), collapse = "; "),
    call. = FALSE)
  cells <- as.data.frame(data.table::rbindlist(lapply(res, `[[`, "rows")))
  meta <- as.data.frame(data.table::rbindlist(lapply(res, `[[`, "meta"), fill = TRUE))
  # equal plot sets: every configuration covers every scored plot of a variant
  chk <- tapply(paste(cells$site, cells$plot), paste(cells$rung, cells$config),
                function(v) paste(sort(unique(v)), collapse = ","))
  for (v in unique(cells$rung)) {
    s <- chk[startsWith(names(chk), paste0(v, " "))]
    if (length(unique(s)) != 1L) stop("configurations cover different plots in ", v,
                                      call. = FALSE)
  }
  cells <- cells[, C3_CELL_COLS]
  write.csv(cells[cells$rung == "3dep_native", ], file.path(S$OUT, "cells_native.csv"),
            row.names = FALSE)
  write.csv(cells[cells$rung == "3dep_dec2", ], file.path(S$OUT, "cells_dec2.csv"),
            row.names = FALSE)
  # clips.csv: the clip record, the stand features and the 2021 values
  clips <- merge(idx, meta, by = c("site", "plot", "rung"), all.x = TRUE, sort = FALSE)
  clips$scored[is.na(clips$scored)] <- FALSE
  clips$reason[clips$status != "ok"] <- clips$status[clips$status != "ok"]
  clips <- c3_neon_values(S, clips)
  st <- c3_state(clips$cover, clips$crown_spacing)
  clips$closed <- st$closed; clips$spaced <- st$spaced; clips$gated <- st$gated
  clips <- clips[order(match(clips$site, C3_SITES), clips$plot,
                       match(clips$rung, C3_VARIANTS)), , drop = FALSE]
  write.csv(clips, file.path(S$OUT, "clips.csv"), row.names = FALSE)
  skipped <- clips[!clips$scored, c("site", "plot", "rung", "reason"), drop = FALSE]
  write.csv(skipped, file.path(S$OUT, "skipped.csv"), row.names = FALSE)
  if (nrow(cells)) write.csv(c3_summary(cells), file.path(S$OUT, "summary.csv"),
                             row.names = FALSE)
  tr <- c3_transfer(clips)
  if (!is.null(tr)) write.csv(tr, file.path(S$OUT, "transfer.csv"), row.names = FALSE)
  jsonlite::write_json(list(K = S$K, tol = S$TOL, population = S$POP,
                            clip_manifest_sha256 = frozen_root_id(S$FROZEN_ROOT),
                            configs = S$CONFIGS, rung = S$RUNG, seed_key = S$SEED_KEY,
                            buffer = S$BUFFER, a = C3_A,
                            lidR = as.character(utils::packageVersion("lidR")),
                            lidRplugins = as.character(utils::packageVersion("lidRplugins")),
                            library_md5 = unname(tools::md5sum(.find("multichm_gated_lib.R"))),
                            script_md5 = unname(tools::md5sum(.find("confirm_gated_3dep.R")))),
                       file.path(S$OUT, "cells.config.json"), auto_unbox = TRUE, pretty = TRUE,
                       digits = NA)
  cat(sprintf("[score] %d rows (%d native, %d thinned) in %.1f min; parity TRUE in %d of %d scored clips; %d clips not scored\n",
              nrow(cells), sum(cells$rung == "3dep_native"), sum(cells$rung == "3dep_dec2"),
              as.numeric(difftime(Sys.time(), t0, units = "mins")),
              sum(clips$parity %in% TRUE), sum(clips$scored), sum(!clips$scored)))
  invisible(cells)
}

## ---- harness: the 2021 NEON frozen clips --------------------------------------------------
# Compare this pipeline's rows with the calibration study's cells: the largest
# absolute difference over the count columns and the features, per cell and
# configuration.
C3_HARNESS_COLS <- c("cover", "top_height", "crown_spacing", "pdens", "frdens", MCG_COUNT_COLS)
c3_compare_cells <- function(mine, ref, cols = C3_HARNESS_COLS) {
  key <- c("site", "plot", "rung", "config")
  m <- merge(mine[, c(key, cols)], ref[, c(key, cols)], by = key, suffixes = c("", ".ref"),
             all.x = TRUE)
  d <- vapply(cols, function(k) abs(as.numeric(m[[k]]) - as.numeric(m[[paste0(k, ".ref")]])),
              numeric(nrow(m)))
  if (!is.matrix(d)) d <- matrix(d, nrow = nrow(m), dimnames = list(NULL, cols))
  m$found <- !is.na(m$n_ref.ref)
  m$max_abs_diff <- apply(d, 1, function(r) if (all(is.na(r))) NA_real_ else max(r, na.rm = TRUE))
  m$cols_differing <- apply(d, 1, function(r) paste(cols[!is.na(r) & r > 1e-9], collapse = ";"))
  m
}

c3_harness_plots <- function(plots, spec) {
  if (identical(toupper(spec), "ALL")) return(plots)
  ids <- vapply(plots, `[[`, "", "plot")
  n <- suppressWarnings(as.integer(spec))
  if (!is.na(n)) {
    site <- vapply(plots, `[[`, "", "site")
    keep <- unlist(lapply(split(seq_along(plots), factor(site, unique(site))),
                          function(i) utils::head(i, n)))
    return(plots[sort(keep)])
  }
  want <- strsplit(spec, ",", fixed = TRUE)[[1]]
  plots[ids %in% want]
}

c3_stage_harness <- function(S) {
  cfgs <- c3_config_table(S$CONFIGS)
  plots <- c3_harness_plots(c3_plots(S), S$HARNESS)
  cat(sprintf("[harness] %d plots x rungs %s on the 2021 NEON frozen clips\n", length(plots),
              paste(S$HARNESS_RUNGS, collapse = ",")))
  t0 <- Sys.time()
  job <- function(j, S, cfgs) tryCatch({
    offs <- mcg_null_offsets(j$site, j$plot, j$half, tol = S$TOL, k = S$K)
    out <- list()
    for (rl in S$HARNESS_RUNGS) {
      rung <- if (rl == "native") NA else as.numeric(rl)
      clip <- frozen_clip(NULL, j$site, j$plot, rung, j$cx, j$cy, j$half, S$FROZEN_ROOT)
      if (is.null(clip)) next
      las <- lidR::readLAS(clip$normalized)
      cell <- c3_cell(las, clip$frdens, clip$pdens, j, rl, cfgs, offs, tol = S$TOL)
      if (!is.null(cell$skipped)) next
      r <- cell$rows; r$parity <- cell$parity
      out[[length(out) + 1L]] <- r
    }
    if (length(out)) do.call(rbind, out)
  }, error = function(e) e)
  res <- plot_lapply(plots, job, S = S, cfgs = cfgs, mc.cores = S$CORES)
  bad <- vapply(res, function(r) inherits(r, "error"), logical(1))
  if (any(bad)) stop("harness jobs failed: ", paste(vapply(which(bad), function(i)
    paste0(plots[[i]]$plot, " (", conditionMessage(res[[i]]), ")"), ""), collapse = "; "),
    call. = FALSE)
  mine <- as.data.frame(data.table::rbindlist(Filter(Negate(is.null), res)))
  ref <- data.table::fread(file.path(S$CAL_OUT, "cells.csv"), colClasses = c(rung = "character"))
  ref <- as.data.frame(ref[ref$config %in% S$CONFIGS & ref$rung %in% S$HARNESS_RUNGS &
                             ref$site %in% S$SITES])
  cmp <- c3_compare_cells(mine, ref)
  cmp$parity <- mine$parity[match(paste(cmp$site, cmp$plot, cmp$rung, cmp$config),
                                  paste(mine$site, mine$plot, mine$rung, mine$config))]
  write.csv(cmp, file.path(S$OUT, "harness.csv"), row.names = FALSE)
  exact <- cmp$found & !is.na(cmp$max_abs_diff) & cmp$max_abs_diff <= 1e-9
  cat(sprintf("[harness] %d cells x configurations in %.1f min: %d found in the calibration cells, %d identical (max |diff| <= 1e-9), largest difference %.3g\n",
              nrow(cmp), as.numeric(difftime(Sys.time(), t0, units = "mins")), sum(cmp$found),
              sum(exact), max(cmp$max_abs_diff, na.rm = TRUE)))
  for (s in unique(cmp$site)) {
    x <- cmp[cmp$site == s, , drop = FALSE]
    cat(sprintf("  %s: %d plots, %d rows, %d identical\n", s, length(unique(x$plot)), nrow(x),
                sum(x$found & x$max_abs_diff <= 1e-9, na.rm = TRUE)))
  }
  invisible(cmp)
}

## ---- xcheck: the native QL2 cross-check's own clips ---------------------------------------
# The cross-check's per-plot preparation (native_ql2_crosscheck.R
# detect_on_multichm) as it was when this stage was run, on 16 November 2026:
# its cached cloud over the +/-PAD box, read as it is, thinned with its
# seed when `rung` is given, normalized by TIN, heights in [-1, 80), densities
# over (2 PAD)^2, res 0.25 m at >= 8 first returns per m2 else 0.5 m. Then the
# stock configuration of this library, scored as that study scored (no null).
# The stage then equalled all 86 of that study's multichm rows. On 17 November
# 2026 the cross-check was corrected: it drops noise-class and withheld points
# when it reads a cached cloud and counts densities inside the box, so 57 of
# its 86 current rows (SOAP and TEAK) differ from this stage's in their counts
# (n_ref, n_det, TP or tp_core).
c3_xcheck_cell <- function(laz, j, rung, pad, seed, tol) {
  l <- lidR::readLAS(laz)
  area0 <- (2 * pad)^2
  if (!is.na(rung)) {
    if (lidR::npoints(l) / area0 <= rung) return(NULL)
    set.seed(seed)
    l <- lidR::decimate_points(l, lidR::homogenize(density = rung, res = 5))
  }
  if (sum(l$Classification == 2L) < 10) return(NULL)
  nrm <- tryCatch(lidR::normalize_height(l, lidR::tin(), na.rm = TRUE), error = function(e) NULL)
  if (is.null(nrm)) return(NULL)
  nrm <- lidR::filter_poi(nrm, Z >= -1, Z < 80)
  frdn <- sum(nrm$ReturnNumber == 1L) / area0
  det <- mcg_apply(mcg_prepare(nrm, c3_res(frdn), C3_A), MCG_STOCK)
  sc <- score_plot(j$stems, det, tol_xy = tol, core_cx = j$cx, core_cy = j$cy,
                   core_half = j$half)
  data.frame(n_ref = sc$n_ref, n_det = sc$n_det, TP = sc$TP,
             tp_core = if (sc$n_det > 0) round(sc$precision * sc$n_det) else 0,
             frdens = frdn)
}

c3_stage_xcheck <- function(S) {
  plots <- c3_plots(S)
  plots <- plots[vapply(plots, function(p) p$site %in% c("SJER", "SOAP", "TEAK"), logical(1))]
  rows <- list()
  for (site in unique(vapply(plots, `[[`, "", "site"))) {
    f <- file.path(S$XCHECK_JOB, "neon", site, "ql2", "ql2_detect_results.csv")
    if (!file.exists(f)) next
    q <- read.csv(f, stringsAsFactors = FALSE)
    rows[[site]] <- q[q$detector == "multichm", , drop = FALSE]
  }
  q <- do.call(rbind, rows)
  if (is.null(q) || !nrow(q)) { cat("[xcheck] no cross-check rows\n"); return(invisible(NULL)) }
  q$tp_core <- ifelse(q$n_det > 0, round(q$precision * q$n_det), 0)
  keys <- paste(vapply(plots, `[[`, "", "site"), vapply(plots, `[[`, "", "plot"))
  jobs <- lapply(seq_len(nrow(q)), function(i) {
    j <- plots[[match(paste(q$site[i], q$plot[i]), keys)]]
    j$variant <- q$variant[i]
    j
  })
  job <- function(j, S) tryCatch({
    laz <- file.path(S$XCHECK_CACHE, "neon", j$site, "ql2", paste0(j$plot, ".laz"))
    mf <- jsonlite::read_json(paste0(laz, ".json"), simplifyVector = TRUE)
    rung <- if (j$variant == "native_dec2") 2 else NA
    seed <- if (is.na(rung)) NA else seed_for(j$site, j$plot, "3DEP-2")
    r <- c3_xcheck_cell(laz, j, rung, as.numeric(mf$pad), seed, S$TOL)
    if (is.null(r)) NULL else cbind(data.frame(site = j$site, plot = j$plot,
                                               variant = j$variant, pad = mf$pad,
                                               ept_url = mf$ept_url, stringsAsFactors = FALSE), r)
  }, error = function(e) e)
  res <- plot_lapply(jobs, job, S = S, mc.cores = S$CORES)
  bad <- vapply(res, function(r) inherits(r, "error"), logical(1))
  if (any(bad)) stop("xcheck jobs failed: ", conditionMessage(res[[which(bad)[1]]]), call. = FALSE)
  mine <- as.data.frame(data.table::rbindlist(Filter(Negate(is.null), res)))
  m <- merge(mine, q[, c("site", "plot", "variant", "n_ref", "n_det", "TP", "tp_core")],
             by = c("site", "plot", "variant"), suffixes = c("", ".xcheck"), all = TRUE)
  m$identical <- with(m, n_ref == n_ref.xcheck & n_det == n_det.xcheck & TP == TP.xcheck &
                        tp_core == tp_core.xcheck)
  # this study's stock counts on its own clips, beside them
  own <- list()
  for (v in c("native", "dec2")) {
    f <- file.path(S$OUT, sprintf("cells_%s.csv", v))
    if (!file.exists(f)) next
    x <- read.csv(f, stringsAsFactors = FALSE)
    x <- x[x$config == "stock", c("site", "plot", "n_ref", "n_det", "TP", "tp_core")]
    x$variant <- if (v == "native") "native_full" else "native_dec2"
    own[[v]] <- x
  }
  if (length(own)) {
    own <- do.call(rbind, own)
    names(own)[3:6] <- paste0(names(own)[3:6], ".c4")
    m <- merge(m, own, by = c("site", "plot", "variant"), all.x = TRUE)
  }
  write.csv(m, file.path(S$OUT, "xcheck.csv"), row.names = FALSE)
  for (v in unique(m$variant)) {
    x <- m[m$variant == v, , drop = FALSE]
    cat(sprintf("[xcheck] %s: %d plots, %d identical to the cross-check's multichm counts (n_ref, n_det, TP, tp_core)\n",
                v, nrow(x), sum(x$identical, na.rm = TRUE)))
  }
  invisible(m)
}

## ---- main ---------------------------------------------------------------------------------
run_main <- function() {
  S <- c3_settings()
  dir.create(S$OUT, recursive = TRUE, showWarnings = FALSE)
  t0 <- Sys.time()
  if (S$STAGE %in% c("all", "discover")) c3_stage_discover(S)
  if (S$STAGE %in% c("all", "pull")) c3_stage_pull(S)
  if (S$STAGE %in% c("all", "clips")) c3_stage_clips(S)
  if (S$STAGE %in% c("all", "score")) c3_stage_score(S)
  if (S$STAGE %in% c("all", "harness")) c3_stage_harness(S)
  if (S$STAGE %in% c("all", "xcheck")) c3_stage_xcheck(S)
  cat(sprintf("[done] %s in %.1f min -> %s\n", S$STAGE,
              as.numeric(difftime(Sys.time(), t0, units = "mins")), S$OUT))
  invisible()
}

if (sys.nframe() == 0L) run_main()
