#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(data.table); library(parallel) })
source(.find("model_bench_lib.R"))       # seed_for, frozen_clip/read/seal; NEON spatial checks
source(.find("neon_acquisition_lib.R"))  # neon_required_tiles, neon_tile_index
source(.find("ofo_registration_lib.R"))  # the frozen method (OFO_REG2) and its unit offsets
source(.find("ofo_preflight_lib.R"))     # stage records
source(.find("ofo_reference_lib.R"))     # output-path guards

# Second preflight of the Open Forest Observatory stem maps
# (docs/ofo-preflight-protocol-2.md), "Test units": the Niwot Ridge (NIWO) units.
# Score-blind: no detector runs and nothing is scored. The frozen registration
# method of Amendment 1b of the first protocol (OFO_REG2; its digest is checked)
# runs once, both signals, on each NIWO plot that the NeonTreeEvaluation
# benchmark annotated, its stems displaced by the offset seeded
# seed_for("offset2", plot, NA) and drawn as in Amendment 1. Crown truths and
# errors against them are another stage's work.
# Everything NIWO lives in its own job directory P2/niwo (P2 = <job>/ofo/preflight2):
# the repo's NEON scripts run there, so they write P2/niwo/neon/NIWO/, and every
# stage proves that <job>/neon did not change (P2/niwo/neon_untouched_<stage>.json).
# neon_download_lidar.R runs unchanged. neon_ground_truth.R stops on NIWO data
# (its crown-class fallback calls cut() on tied height quantiles in NIWO_061), so
# it runs as a copy, P2/niwo/patched/neon_ground_truth.R, with one guard added
# that leaves such a plot's fallback class empty (niwo_patch_ground_truth());
# nothing the registration reads depends on that class, the copy is made only
# from the inspected version (SHA-256 pinned) and both digests are recorded.
# The network calls of those scripts are
# recorded in P2/niwo/downloads.json (URL with signed query strings dropped,
# HTTP status, bytes, SHA-256, UTC time); the NEON token travels in a header and
# is never written (every written file is checked for it).
#   STAGE=reference  lists the benchmark repository at one commit (NTE_COMMIT=,
#                    else the commit pinned in P2/nte/nte_sources.json, else the
#                    head of its default branch) and keeps the NIWO plots whose
#                    annotation file is named <plot>_<year>.xml:
#                    P2/niwo/annotated_plots.csv. Runs neon_ground_truth.R
#                    SITE=NIWO YEAR=2020 (default MAX_YEAR_GAP 4), retrying while
#                    rate-limited point locations are still being geolocated:
#                    P2/niwo/reference_summary.csv (plot record, plot type, live
#                    mapped stems: all, DBH >= 10 cm, with a height, with a canopy
#                    position).
#   STAGE=lidar      runs neon_download_lidar.R SITE=NIWO YEAR=2020 PLOTS=<annotated
#                    plots with a plot record>, then checks the acquisition
#                    manifest, the CRS of every tile header and that every clip
#                    box (core plus 25 m) lies on downloaded tiles:
#                    P2/niwo/tiles.csv, P2/niwo/coverage.csv. Tiles already
#                    present and covering every box are not fetched again.
#   STAGE=clips      one native clip per covered annotated plot with the
#                    benchmark's provider frozen_clip() (lidR single-threaded)
#                    into P2/niwo/neon/frozen_niwo_2020, then sealed with
#                    frozen_seal() (clip_manifest.csv holds the SHA-256 of every
#                    file): P2/niwo/clips.csv (status, all-return and
#                    first-return densities, digests).
#   STAGE=register   first proves the path: the same code, on benchmark plots
#                    (EQUIV=, read-only from the sealed root through
#                    frozen_read()) with their own offsets, must reproduce their
#                    rows of the first protocol's registration_dev.csv or
#                    registration_confirm.csv byte for byte
#                    (P2/niwo/path_equivalence.csv); then runs the frozen method
#                    on each annotated NIWO plot: P2/registration_niwo.csv (the
#                    columns of registration_confirm.csv; error_m is the
#                    zero-truth error) and P2/niwo_units.csv. A rerun must
#                    reproduce an existing registration_niwo.csv exactly.
# Every stage writes P2/niwo/<stage>_record.json (SHA-256 of what it read and
# wrote; paths relative to the job directory, as are the paths in the tables).
#   Rscript scripts/preflight_ofo_niwo.R STAGE=reference|lidar|clips|register [CORES=8]
#     [EQUIV=SOAP_048,WREF_014,SJER_047] [NTE_COMMIT=<40-hex commit>]

NIWO_SITE <- "NIWO"
NIWO_YEAR <- 2020L          # the site's flight nearest the benchmark's 2021 flights
NIWO_BUFFER <- 25           # the benchmark's clip buffer beyond the core (sweep_lib.R BUF)
NIWO_ROOT_NAME <- "frozen_niwo_2020"
NIWO_STAGES <- c("reference", "lidar", "clips", "register")
NIWO_SIGNALS <- c("height", "rank")
# The plots named by the task; the repository listing governs and any
# difference is reported.
NIWO_TASK_PLOTS <- sprintf("NIWO_%03d", c(1, 2, 4, 5, 10, 11, 12, 14, 15, 16, 17, 42))
# Benchmark plots of the path-equivalence proof: a development plot accepted
# under both signals, a confirmation plot accepted under both, and a
# development plot whose height unit is not run and whose rank unit is rejected
# on three rules, from three sites.
NIWO_EQUIV <- c("SOAP_048", "WREF_014", "SJER_047")
NTE_REPO <- "weecology/NeonTreeEvaluation"
NTE_BRANCH <- "master"
NIWO_DIGEST <- "eede36eb4afc37a385dc3b204f0dcf660c29cc60bcf893293c8a546bb54803b6"
NIWO_USER_AGENT <- "R-curl preflight"
# Columns of the first protocol's registration_confirm.csv, in its order.
NIWO_REG_COLUMNS <- c("variant", "signal", "unit", "kind", "site", "n_signal", "offset_dx",
                      "offset_dy", "dx", "dy", "error_m", "residual_m", "z", "second_peak",
                      "sub_p90_m", "contrast", "objective_best", "objective_median",
                      "objective_zero", "shift_m", "on_edge", "resample_reach_m", "estimator",
                      "accepted", "reject_reason", "frozen_variant", "at_min_stems")
NIWO_UNIT_COLUMNS <- c("plot", "plot_type", "cx", "cy", "core_half", "epsg", "n_live_height",
                       "n_dbh10", "offset_dx", "offset_dy", "clip_root", "normalized_laz")
# The surfaces the frozen configurations use ("raw" for both).
NIWO_SMOOTHS <- unique(vapply(NIWO_SIGNALS, function(s) OFO_REG2[[s]]$cfg$surface, ""))
# neon_ground_truth.R as inspected for this study, and the one guard its NIWO
# copy adds: the fallback of a plot whose 33/66/90% height quantiles tie
# cannot form four classes (cut() stops on non-unique breaks), so it is skipped.
NIWO_GT_SHA256 <- "d5864a3b02ef77cfb4b7c5cc4852f0825826277b88fd490021574b9ad21bd3b0"
NIWO_GT_TARGET <- "    if (length(idx) >= 4) {"
NIWO_GT_GUARD <- paste0("    if (length(idx) >= 4 && !anyDuplicated(quantile(g$height[idx], ",
                        "c(.33, .66, .9), na.rm = TRUE))) {")

## ---- plots, geometry, stems ---------------------------------------------------------
# NIWO plots of the benchmark's crown annotations. A plot is eligible when its
# annotation file is named <plot>_<year>.xml (protocol 2, "Annotations"); other
# files under annotations/ (training crops such as 2018_NIWO_2_..._crop.xml)
# name no plot. One row per plot, its annotation files and years ";"-joined.
niwo_annotated_plots <- function(paths, site = NIWO_SITE) {
  pat <- sprintf("^annotations/(%s_[0-9]{3})_([0-9]{4})[.]xml$", site)
  m <- regmatches(paths, regexec(pat, paths))
  ok <- lengths(m) == 3L
  if (!any(ok))
    return(data.frame(plot = character(), annotation = character(), ann_year = character(),
                      stringsAsFactors = FALSE))
  a <- data.frame(plot = vapply(m[ok], `[`, "", 2L), year = vapply(m[ok], `[`, "", 3L),
                  path = paths[ok], stringsAsFactors = FALSE)
  a <- a[order(a$plot, a$year), , drop = FALSE]
  out <- do.call(rbind, lapply(split(a, a$plot), function(x)
    data.frame(plot = x$plot[1], annotation = paste(x$path, collapse = ";"),
               ann_year = paste(x$year, collapse = ";"), stringsAsFactors = FALSE)))
  rownames(out) <- NULL
  out
}

# The frozen-clip geometry of each plot, as freeze_clips.R declares it: the
# plot centroid of plot_centroids.csv, the nominal core half-extent (tower
# 20 m, distributed 10 m) and the 25 m buffer, with the 1 km tiles the clip box
# touches. A plot without a plot record has no geometry (NA).
niwo_clip_geometry <- function(plots, pc, buffer = NIWO_BUFFER) {
  ci <- pc[match(plots, pc$plotID), , drop = FALSE]
  has <- !is.na(ci$plotID) & is.finite(ci$easting) & is.finite(ci$northing)
  half <- ifelse(has, ext_core_half(ci$plotType), NA_real_)
  tiles <- vapply(seq_along(plots), function(i)
    if (has[i]) paste(neon_required_tiles(ci$easting[i], ci$northing[i], half[i] + buffer),
                      collapse = ";") else NA_character_, character(1))
  data.frame(plot = plots, plot_type = ifelse(has, ci$plotType, NA_character_),
             cx = ifelse(has, ci$easting, NA_real_), cy = ifelse(has, ci$northing, NA_real_),
             core_half = half, epsg = ifelse(has, as.integer(ci$epsg), NA_integer_),
             buffer = buffer, tiles = tiles, stringsAsFactors = FALSE)
}

# The stem pool of the first protocol's tests (preflight_ofo_registration.R,
# neon_stems()): live trees with a mapped position, in file order (the order
# fixes which stems each seeded half-split and subsample draws).
niwo_stems <- function(gt, plot) {
  st <- gt[gt$plotID == plot & gt$live %in% TRUE & gt$is_tree %in% TRUE &
             is.finite(gt$E) & is.finite(gt$N), , drop = FALSE]
  data.frame(x = st$E, y = st$N, height = st$height, dbh = st$stemDiameter)
}

# The known offset of a NIWO unit: Amendment 1's draw with seed
# seed_for("offset2", plot, NA), uniform within +/-8 m per axis.
niwo_offset <- function(plot) ofo_unit_offset(plot, max = OFO_REG2$offset_max)

## ---- the method on one plot unit -------------------------------------------------------
# The method's surfaces of one normalized clip, as STAGE=dev/confirm build them
# (load_neon_plots()): the clip read with no filter, a 0.5 m highest-return
# raster (0.2 m subcircle) single-threaded, then ofo2_surface().
niwo_surfaces <- function(normalized, smooths = NIWO_SMOOTHS) {
  las <- NULL
  invisible(utils::capture.output(las <- lidR::readLAS(normalized, select = "xyz")))
  threads <- lidR::get_lidr_threads()
  lidR::set_lidr_threads(1L)
  on.exit(lidR::set_lidr_threads(threads), add = TRUE)
  chm <- lidR::rasterize_canopy(las, res = OFO_REG2_SEARCH$res,
                                algorithm = lidR::p2r(OFO_REG2_SEARCH$subcircle))
  stats::setNames(lapply(smooths, function(s) ofo2_surface(chm, s)), smooths)
}

# Column order of run_units(), the frozen gate of gate_rows() and the
# at_min_stems flag of STAGE=confirm (preflight_ofo_registration.R), applied
# to rows of ofo2_run_unit() bound to variant, estimator, kind and site.
niwo_finish_rows <- function(res) {
  cols <- NIWO_REG_COLUMNS[seq_len(match("estimator", NIWO_REG_COLUMNS))]
  res <- res[order(match(res$signal, NIWO_SIGNALS), res$variant, res$kind != "plot", res$unit),
             cols]
  out <- do.call(rbind, lapply(split(res, res$signal), function(x) {
    y <- ofo2_apply_gate(x, OFO_REG2[[x$signal[1]]]$gate)
    y$accepted[!is.finite(y$dx)] <- FALSE
    y$reject_reason[!is.finite(y$dx)] <- "not_run"
    y
  }))
  out$frozen_variant <- out$variant == vapply(out$signal, function(s) OFO_REG2[[s]]$variant, "")
  out <- out[order(match(out$signal, NIWO_SIGNALS), out$variant, out$kind != "plot", out$unit), ]
  out$at_min_stems <- out$n_signal >=
    vapply(out$signal, function(s) OFO_REG2[[s]]$gate$min_stems, integer(1))
  rownames(out) <- NULL
  out
}

# One plot unit under the frozen configuration of each signal: the rows that
# STAGE=confirm writes for a plot unit. `stems` from niwo_stems(), `surf` from
# niwo_surfaces(), `off` the known offset. error_m is the distance between the
# estimate and the shift that undoes the offset (the zero-truth error).
niwo_unit_rows <- function(unit, site, stems, surf, off, grid = ofo_shift_grid()) {
  P <- stats::setNames(list(list(stems = stems, surf = surf)), unit)
  res <- do.call(rbind, lapply(NIWO_SIGNALS, function(s) {
    cfg <- OFO_REG2[[s]]$cfg
    r <- ofo2_run_unit(unit, unit, P, s, cfg, off, grid)
    cbind(data.frame(variant = OFO_REG2[[s]]$variant, estimator = cfg$estimator, kind = "plot",
                     site = site, stringsAsFactors = FALSE), r)
  }))
  niwo_finish_rows(res)
}

# The NIWO path: surfaces of the plot's normalized clip, then its unit rows.
niwo_register_plot <- function(unit, site, stems, normalized, off, grid = ofo_shift_grid())
  niwo_unit_rows(unit, site, stems, niwo_surfaces(normalized), off, grid)

# Rows of a plot that has no clip to register against: estimates missing,
# rejected with `reason` (no_plot_record, no_tiles or no_clip).
niwo_unrun_rows <- function(unit, site, stems, off, reason) {
  res <- do.call(rbind, lapply(NIWO_SIGNALS, function(s) {
    data.frame(variant = OFO_REG2[[s]]$variant, signal = s, unit = unit, kind = "plot",
               site = site, n_signal = as.integer(sum(ofo2_signal_stems(stems, s))),
               offset_dx = off[1], offset_dy = off[2], dx = NA_real_, dy = NA_real_,
               error_m = NA_real_, residual_m = NA_real_, z = NA_real_, second_peak = NA_real_,
               sub_p90_m = NA_real_, contrast = NA_real_, objective_best = NA_real_,
               objective_median = NA_real_, objective_zero = NA_real_, shift_m = NA_real_,
               on_edge = NA, resample_reach_m = NA_real_,
               estimator = OFO_REG2[[s]]$cfg$estimator, stringsAsFactors = FALSE)
  }))
  out <- niwo_finish_rows(res)
  out$reject_reason <- reason
  out
}

# One row per NIWO plot (the contract's columns, then extras): geometry, stem
# counts that need no registration (as build_units() counts them), the known
# offset and the clip. `geo` from niwo_clip_geometry(), `clips` from
# STAGE=clips (plot, status, normalized_laz, pdens, frdens), `ann` from
# annotated_plots.csv; paths relative to the job directory.
niwo_units_table <- function(geo, gt, clips, ann, clip_root) {
  do.call(rbind, lapply(seq_len(nrow(geo)), function(i) {
    p <- geo$plot[i]
    st <- niwo_stems(gt, p)
    off <- niwo_offset(p)
    k <- match(p, clips$plot); a <- match(p, ann$plot)
    ok <- !is.na(k) && identical(clips$status[k], "ok")
    data.frame(plot = p, plot_type = geo$plot_type[i], cx = geo$cx[i], cy = geo$cy[i],
               core_half = geo$core_half[i], epsg = geo$epsg[i],
               n_live_height = as.integer(sum(ofo2_signal_stems(st, "height"))),
               n_dbh10 = as.integer(sum(ofo2_signal_stems(st, "rank"))),
               offset_dx = off[1], offset_dy = off[2], clip_root = clip_root,
               normalized_laz = if (ok) clips$normalized_laz[k] else NA_character_,
               annotation = if (is.na(a)) NA_character_ else ann$annotation[a],
               ann_year = if (is.na(a)) NA_character_ else as.character(ann$ann_year[a]),
               n_live = nrow(st),
               clip_status = if (is.na(k)) niwo_missing_reason(geo[i, ]) else clips$status[k],
               pdens = if (ok) clips$pdens[k] else NA_real_,
               frdens = if (ok) clips$frdens[k] else NA_real_, stringsAsFactors = FALSE)
  }))
}

niwo_missing_reason <- function(g) if (is.na(g$cx)) "no_plot_record" else "no_tiles"

## ---- download records ----------------------------------------------------------------
# A URL as recorded: a query string carrying a signature, credential, key,
# token or expiry (signed cloud-storage URLs are credentials) is dropped whole;
# other query strings (such as ?release=) are kept. Self-contained: the runner
# inlines its source into the NEON scripts' processes.
niwo_safe_url <- function(u, signed = paste0(
  "^(x-goog-.*|x-amz-.*|signature|sig|credential|token|apikey|api_key|key|expires|policy|",
  "googleaccessid|awsaccesskeyid)$")) {
  vapply(as.character(u), function(x) {
    if (is.na(x) || !nzchar(x) || !grepl("?", x, fixed = TRUE)) return(x)
    keys <- tolower(sub("=.*$", "", strsplit(sub("^[^?]*[?]", "", x), "&", fixed = TRUE)[[1]]))
    if (any(grepl(signed, keys))) sub("[?].*$", "", x) else x
  }, character(1), USE.NAMES = FALSE)
}

# Installs recorders, in the current R process, on the network calls the NEON
# scripts make: httr::GET and httr::HEAD (neonUtilities API queries, after the
# call: final URL, status and the bytes received), downloader::download
# (neonUtilities file downloads: the file as written) and jsonlite::fromJSON on
# a URL (the locations API of neon_ground_truth.R: the URL is fetched once
# here, recorded, and the recorded bytes are what fromJSON parses; an HTTP
# error stops as jsonlite's connection does). Each call appends one JSON line
# to `log`. Self-contained (base, curl, digest, jsonlite, httr, downloader).
niwo_install_traces <- function(log, safe) {
  force(log); force(safe)
  now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
  put <- function(x) cat(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA, na = "null",
                                          null = "null"), "\n", sep = "", file = log,
                         append = TRUE)
  one <- function(x) if (is.null(x) || !length(x)) NA_character_ else as.character(x)[1]
  rec <- function(kind, url, final = NULL, status = NA_integer_, ok = TRUE, content = NULL,
                  file = NULL) {
    tryCatch({
      u <- one(url); f <- one(final); fl <- one(file)
      bytes <- NA_real_; sha <- NA_character_
      if (!is.na(fl) && file.exists(fl)) {
        bytes <- file.size(fl); sha <- digest::digest(file = fl, algo = "sha256")
      } else if (!is.null(content)) {
        bytes <- length(content)
        sha <- digest::digest(content, algo = "sha256", serialize = FALSE)
      }
      put(list(kind = kind, url = safe(u), query_dropped = !identical(safe(u), u),
               final_url = safe(f), status = as.integer(status), ok = isTRUE(ok), bytes = bytes,
               sha256 = sha, file = fl, retrieved_utc = now()))
    }, error = function(e) put(list(kind = kind, record_error = conditionMessage(e),
                                    retrieved_utc = now())))
    invisible(NULL)
  }
  http <- function(method, url, r) {
    if (inherits(r, "response")) rec(paste0("http_", method), url, r$url, r$status_code,
                                     r$status_code < 400, content = r$content)
    else rec(paste0("http_", method), url, ok = FALSE)
  }
  dl <- function(url, a, r) {
    nm <- names(a)
    dest <- if (!is.null(a$destfile)) a$destfile else
      a[[if (is.null(nm)) 1L else which(!nzchar(nm))[1]]]
    rec("download", url, ok = identical(suppressWarnings(as.integer(r)), 0L), file = dest)
  }
  json <- function(txt) {
    if (!(is.character(txt) && length(txt) == 1L && !is.na(txt) &&
          grepl("^https?://", txt, useBytes = TRUE) && nchar(txt, type = "bytes") < 2084))
      return(txt)
    h <- curl::new_handle(useragent = paste("jsonlite /", R.version.string))
    curl::handle_setheaders(h, Accept = "application/json, text/*, */*")
    r <- tryCatch(curl::curl_fetch_memory(txt, handle = h), error = function(e) e)
    if (inherits(r, "error")) { rec("json", txt, ok = FALSE); stop(r) }
    rec("json", txt, r$url, r$status_code, r$status_code < 400, content = r$content)
    if (r$status_code >= 400) stop("HTTP error ", r$status_code, ".", call. = FALSE)
    out <- rawToChar(r$content)
    Encoding(out) <- "UTF-8"
    out
  }
  for (p in c("httr", "downloader", "jsonlite", "curl", "digest")) loadNamespace(p)
  q <- function(e) invisible(suppressMessages(e))
  q(trace("GET", where = asNamespace("httr"), print = FALSE,
          exit = bquote(.(http)("GET", url, returnValue(default = NULL)))))
  q(trace("HEAD", where = asNamespace("httr"), print = FALSE,
          exit = bquote(.(http)("HEAD", url, returnValue(default = NULL)))))
  q(trace("download", where = asNamespace("downloader"), print = FALSE,
          exit = bquote(.(dl)(url, list(...), returnValue(default = -1L)))))
  q(trace("fromJSON", where = asNamespace("jsonlite"), print = FALSE,
          tracer = bquote(txt <- .(json)(txt))))
  invisible(TRUE)
}

# R code for a fresh Rscript process: the recorders, then the NEON script
# sourced unchanged (it reads its KEY=VALUE arguments from the command line).
niwo_runner_expr <- function(script, trace_log)
  paste(c(paste0(".niwo_safe <- ", paste(deparse(niwo_safe_url), collapse = "\n")),
          paste0(".niwo_trace <- ", paste(deparse(niwo_install_traces), collapse = "\n")),
          sprintf(".niwo_trace(%s, .niwo_safe)", deparse(trace_log)),
          "rm(.niwo_safe, .niwo_trace)",
          sprintf("source(%s)", deparse(script))), collapse = "\n")

# Lines of a recorder log as a table (one row per call). Files are given
# relative to the job directory when they lie in it; other files (the
# temporary zips of loadByProduct) by name, kept = FALSE.
niwo_read_trace <- function(path, d) {
  if (!file.exists(path)) return(NULL)
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(lines)]
  if (!length(lines)) return(NULL)
  x <- rbindlist(lapply(lines, function(l) as.data.table(lapply(
    jsonlite::fromJSON(l, simplifyVector = TRUE), function(v) if (is.null(v)) NA else v))),
    fill = TRUE)
  if (!"file" %in% names(x)) x[, file := NA_character_]
  x[, file := as.character(file)]                  # all-NA when nothing was written
  inside <- !is.na(x$file) & startsWith(x$file, paste0(d, "/"))
  x[, kept := inside & file.exists(ifelse(is.na(file), "", file))]
  x[inside, file := substring(file, nchar(d) + 2L)]
  x[!inside & !is.na(file), file := basename(file)]
  x[]
}

niwo_downloads_path <- function(ctx) file.path(ctx$nj, "downloads.json")

# Name of a recorder log: the stage and script it belongs to and a UTC stamp.
niwo_calls_log <- function(ctx, stage, script)
  file.path(ctx$nj, "logs", sprintf("calls_%s__%s__%s.jsonl", stage, sub("[.]R$", "", script),
                                    format(Sys.time(), "%Y%m%dT%H%M%OS3Z", tz = "UTC")))

# Brings every recorder log under P2/niwo/logs into downloads.json, so that a
# call is recorded even when the driver stopped after the script ran.
niwo_sync_downloads <- function(ctx) {
  logs <- sort(list.files(file.path(ctx$nj, "logs"), "^calls_.*__.*__.*[.]jsonl$",
                          full.names = TRUE))
  for (f in logs) {
    parts <- strsplit(sub("^calls_", "", basename(f)), "__", fixed = TRUE)[[1]]
    calls <- niwo_read_trace(f, ctx$d)
    if (NROW(calls)) calls[, calls_log := niwo_rel(ctx, f)]
    niwo_append_downloads(ctx, calls, parts[1], paste0(parts[2], ".R"))
  }
  invisible(niwo_downloads_path(ctx))
}

# Adds records to P2/niwo/downloads.json with the stage and the script that
# made them. Never rewritten: a rerun adds its own calls, and a call already
# held (same kind, URL, time and digest) is not added twice.
niwo_append_downloads <- function(ctx, entries, stage, script) {
  path <- niwo_downloads_path(ctx)
  old <- if (file.exists(path)) as.data.table(jsonlite::read_json(
    path, simplifyVector = TRUE)$downloads) else NULL
  if (!NROW(entries)) return(invisible(path))
  entries <- as.data.table(entries)
  entries[, `:=`(stage = stage, script = script)]
  all <- rbindlist(list(old, entries), fill = TRUE)
  key <- paste(all$kind, all$url, all$retrieved_utc, all$sha256, sep = "|")
  all <- all[!duplicated(key)]
  out <- list(
    note = paste("Every network call of this study's NIWO stages: URL (a query string",
                 "carrying a signature, credential, key, token or expiry is dropped),",
                 "final URL after redirects, HTTP status, bytes and SHA-256 of what was",
                 "received (of the file as written for downloads) and the UTC time. The",
                 "NEON token was sent in a header and is not recorded. kept: the file is",
                 "still on disk under the job directory (loadByProduct deletes its",
                 "temporary zips once stacked into the RDS)."),
    updated_utc = niwo_now(), downloads = all)
  jsonlite::write_json(out, path, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null",
                       null = "null")
  niwo_assert_no_token(path)
  invisible(path)
}

# One GET made by this driver (the benchmark repository listing), recorded
# through a recorder log like the scripts' calls; the answer is kept at `dest`.
niwo_fetch <- function(ctx, url, dest, stage) {
  h <- curl::new_handle(useragent = NIWO_USER_AGENT)
  curl::handle_setheaders(h, Accept = "application/vnd.github+json")
  r <- curl::curl_fetch_memory(url, handle = h)
  ok <- r$status_code == 200L
  if (ok) {
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    writeBin(r$content, dest)
  }
  log <- niwo_calls_log(ctx, stage, "preflight_ofo_niwo.R")
  dir.create(dirname(log), recursive = TRUE, showWarnings = FALSE)
  cat(jsonlite::toJSON(list(
    kind = "http_GET", url = niwo_safe_url(url),
    query_dropped = !identical(niwo_safe_url(url), url),
    final_url = niwo_safe_url(r$url), status = r$status_code, ok = ok, bytes = length(r$content),
    sha256 = digest::digest(r$content, algo = "sha256", serialize = FALSE),
    file = if (ok) dest else NA_character_,
    retrieved_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")),
    auto_unbox = TRUE, digits = NA, na = "null"), "\n", sep = "", file = log)
  niwo_sync_downloads(ctx)
  if (!ok) stop("HTTP ", r$status_code, " from ", url)
  r
}

# Stops (after scrubbing the file) if the NEON token appears in any of `paths`.
niwo_assert_no_token <- function(paths) {
  tok <- Sys.getenv("NEON_TOKEN", unset = "")
  if (!nzchar(tok)) return(invisible(TRUE))
  for (p in paths[file.exists(paths)]) {
    txt <- readChar(p, file.size(p), useBytes = TRUE)
    if (length(txt) && grepl(tok, txt, fixed = TRUE, useBytes = TRUE)) {
      writeChar(gsub(tok, "<token removed>", txt, fixed = TRUE, useBytes = TRUE), p, eos = NULL,
                useBytes = TRUE)
      stop("The NEON token appeared in ", p, " and was removed; check what wrote it")
    }
  }
  invisible(TRUE)
}

## ---- running the repo's NEON scripts -----------------------------------------------------
# The lines of neon_ground_truth.R with the guard in place of the one line it
# replaces; stops unless that line occurs exactly once.
niwo_patch_ground_truth <- function(lines) {
  hit <- which(lines == NIWO_GT_TARGET)
  if (length(hit) != 1L)
    stop("neon_ground_truth.R: the crown-class fallback is not as inspected; review the patch")
  lines[hit] <- NIWO_GT_GUARD
  lines
}

# The script the reference stage runs: the repository's own when it already
# holds the guard, else the guarded copy of the inspected version.
niwo_ground_truth_script <- function(ctx) {
  orig <- .find("neon_ground_truth.R")
  sha <- frozen_sha256(orig)
  lines <- readLines(orig, warn = FALSE)
  if (any(lines == NIWO_GT_GUARD))
    return(list(path = orig, patched = FALSE, original_sha256 = sha))
  if (!identical(sha, NIWO_GT_SHA256))
    stop("neon_ground_truth.R is not the version the NIWO guard was written for; review it")
  dest <- file.path(ctx$nj, "patched", "neon_ground_truth.R")
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  writeLines(niwo_patch_ground_truth(lines), dest)
  list(path = dest, patched = TRUE, original_sha256 = sha, patched_sha256 = frozen_sha256(dest),
       copy = niwo_rel(ctx, dest), line_replaced = NIWO_GT_TARGET, line_added = NIWO_GT_GUARD)
}

# Runs a NEON script (scripts/<script>, or `path`) in a fresh Rscript process
# with CLAUDE_JOB_DIR = the NIWO job directory and the working directory at
# the repository root, the recorders installed; output to P2/niwo/logs/. Its
# network calls are appended to downloads.json.
niwo_run_script <- function(ctx, stage, script, args, path = .find(script)) {
  logs <- file.path(ctx$nj, "logs")
  dir.create(logs, recursive = TRUE, showWarnings = FALSE)
  stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  trace_log <- niwo_calls_log(ctx, stage, script)
  out_log <- file.path(logs, sprintf("%s_%s_%s.log", stage, sub("[.]R$", "", script), stamp))
  expr <- niwo_runner_expr(normalizePath(path), trace_log)
  old <- Sys.getenv("CLAUDE_JOB_DIR", unset = NA)
  owd <- setwd(.ROOT)
  on.exit({
    setwd(owd)
    if (is.na(old)) Sys.unsetenv("CLAUDE_JOB_DIR") else Sys.setenv(CLAUDE_JOB_DIR = old)
  }, add = TRUE)
  Sys.setenv(CLAUDE_JOB_DIR = ctx$nj)
  message(sprintf("[%s] Rscript %s %s (CLAUDE_JOB_DIR=%s)", stage, script,
                  paste(args, collapse = " "), niwo_rel(ctx, ctx$nj)))
  status <- system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(expr), args),
                    stdout = out_log, stderr = out_log)
  niwo_assert_no_token(c(out_log, trace_log))
  calls <- niwo_read_trace(trace_log, ctx$d)
  niwo_sync_downloads(ctx)
  cat(utils::tail(readLines(out_log, warn = FALSE), 25), sep = "\n")
  if (!identical(as.integer(status), 0L))
    stop(script, " failed (exit ", status, "); see ", out_log)
  invisible(list(log = out_log, calls = calls))
}

## ---- evidence that <job>/neon is untouched -------------------------------------------
# path, size and mtime of every entry under <job>/neon (recursive, with
# directories): any write there changes this listing.
niwo_neon_listing <- function(d) {
  root <- file.path(d, "neon")
  rel <- sort(list.files(root, recursive = TRUE, all.files = TRUE, include.dirs = TRUE,
                         no.. = TRUE))
  info <- file.info(file.path(root, rel), extra_cols = FALSE)
  data.frame(path = rel, size = info$size, mtime = sprintf("%.6f", as.numeric(info$mtime)),
             stringsAsFactors = FALSE)
}

niwo_listing_digest <- function(l)
  digest::digest(paste(l$path, l$size, l$mtime, sep = "\t", collapse = "\n"), algo = "sha256",
                 serialize = FALSE)

# Writes P2/niwo/neon_untouched_<stage>.json and stops when the listing moved.
niwo_neon_evidence <- function(ctx, before, stage) {
  after <- niwo_neon_listing(ctx$d)
  key <- function(l) paste(l$path, l$size, l$mtime, sep = "\t")
  changed <- sort(unique(c(setdiff(key(before), key(after)), setdiff(key(after), key(before)))))
  ev <- list(checked_utc = niwo_now(), stage = stage, root = "neon",
             fields = "path, size, mtime (recursive, with directories)",
             identical = identical(before, after), n_entries_before = nrow(before),
             n_entries_after = nrow(after), sha256_before = niwo_listing_digest(before),
             sha256_after = niwo_listing_digest(after),
             changed = utils::head(sub("\t.*$", "", changed), 50))
  niwo_write_json(ev, file.path(ctx$nj, sprintf("neon_untouched_%s.json", stage)))
  if (!isTRUE(ev$identical))
    stop("<job>/neon changed during STAGE=", stage, "; see neon_untouched_", stage, ".json")
  invisible(ev)
}

## ---- small helpers ----------------------------------------------------------------------
niwo_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

niwo_write_json <- function(x, path)
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null",
                       null = "null")

# A path relative to the job directory (paths are built from it).
niwo_rel <- function(ctx, path) {
  pre <- paste0(ctx$d, "/")
  ifelse(startsWith(path, pre), substring(path, nchar(pre) + 1L), path)
}

niwo_sha <- function(ctx, rel) ofo_sha256(ctx$d, rel)

niwo_record <- function(ctx, stage, inputs, outputs, extra = list()) {
  path <- file.path(ctx$nj, paste0(stage, "_record.json"))
  ofo_write_record(ofo_stage_record(stage, ctx$d, inputs, outputs,
                                    c(list(method_digest = ofo2_config_digest()), extra)), path)
  niwo_assert_no_token(path)
  invisible(path)
}

niwo_context <- function(d, A = list()) {
  ofo <- file.path(d, "ofo")
  p2 <- file.path(ofo, "preflight2")
  nj <- file.path(p2, "niwo")
  nd <- file.path(nj, "neon", NIWO_SITE)
  ctx <- list(d = d, ofo = ofo, pre = file.path(ofo, "preflight"), p2 = p2, nj = nj, nd = nd,
              lidar = file.path(nd, "lidar"), root = file.path(nj, "neon", NIWO_ROOT_NAME),
              cores = as.integer(if (is.null(A$CORES)) 8 else A$CORES),
              equiv = if (is.null(A$EQUIV)) NIWO_EQUIV else strsplit(A$EQUIV, ",")[[1]],
              nte_commit = A$NTE_COMMIT)
  niwo_check_paths(ctx)
  ctx
}

# Outputs go under <job>/ofo, never under <job>/neon (symlinks resolved).
niwo_check_paths <- function(ctx) {
  neon <- ofo_path_resolve(file.path(ctx$d, "neon"))
  for (p in c(ctx$p2, ctx$nj, ctx$root)) {
    if (!ofo_path_under(p, ctx$ofo)) stop("Outputs must lie under ", ctx$ofo, ": ", p)
    if (ofo_path_within(ofo_path_resolve(p), neon)) stop("Nothing may be written under ", neon)
  }
  invisible(TRUE)
}

niwo_field <- function(ctx) {
  gt_path <- file.path(ctx$nd, "ground_truth_stems.csv")
  pc_path <- file.path(ctx$nd, "plot_centroids.csv")
  if (!file.exists(gt_path) || !file.exists(pc_path)) stop("Run STAGE=reference first")
  gt <- read.csv(gt_path, stringsAsFactors = FALSE)
  pc <- read.csv(pc_path, stringsAsFactors = FALSE)
  neon_reference_epoch(gt, NIWO_YEAR)
  list(gt = gt, pc = pc, epsg = neon_validate_inputs(ext_live_trees(gt), pc),
       files = niwo_rel(ctx, c(gt_path, pc_path)))
}

niwo_read_annotated <- function(ctx) {
  f <- file.path(ctx$nj, "annotated_plots.csv")
  if (!file.exists(f)) stop("Run STAGE=reference first: ", f, " is missing")
  read.csv(f, stringsAsFactors = FALSE, colClasses = c(ann_year = "character"))
}

niwo_par_map <- function(xs, f, cores) {
  out <- mclapply(xs, f, mc.cores = cores, mc.preschedule = FALSE)
  bad <- vapply(out, inherits, logical(1), "try-error")
  if (any(bad)) stop("Worker failed: ", as.character(out[[which(bad)[1]]]))
  out
}

## ---- STAGE=reference -------------------------------------------------------------------
# The commit the annotation list is taken at: NTE_COMMIT=, else the commit
# recorded in P2/nte/nte_sources.json (the crown-truth stage's pin), else the
# head of the default branch (queried and recorded).
niwo_nte_commit <- function(ctx) {
  is_sha <- function(x) is.character(x) && length(x) == 1L && grepl("^[0-9a-f]{40}$", x)
  if (!is.null(ctx$nte_commit)) {
    if (!is_sha(ctx$nte_commit)) stop("NTE_COMMIT must be a 40-character commit SHA")
    return(list(commit = ctx$nte_commit, source = "NTE_COMMIT argument"))
  }
  src <- file.path(ctx$p2, "nte", "nte_sources.json")
  if (file.exists(src)) {
    j <- jsonlite::read_json(src)
    cand <- unlist(j[grepl("commit", names(j), ignore.case = TRUE)])
    cand <- cand[vapply(cand, is_sha, logical(1))]
    if (length(unique(cand)) == 1L)
      return(list(commit = unname(cand[1]), source = niwo_rel(ctx, src),
                  source_sha256 = frozen_sha256(src)))
  }
  r <- niwo_fetch(ctx, sprintf("https://api.github.com/repos/%s/commits/%s", NTE_REPO, NTE_BRANCH),
                  file.path(ctx$nj, "sources", sprintf("nte_commit_%s.json", NTE_BRANCH)),
                  "reference")
  sha <- jsonlite::fromJSON(rawToChar(r$content))$sha
  if (!is_sha(sha)) stop("No commit SHA in the repository's answer")
  list(commit = sha, source = sprintf("head of %s/%s at %s", NTE_REPO, NTE_BRANCH, niwo_now()))
}

niwo_list_annotations <- function(ctx) {
  pin <- niwo_nte_commit(ctx)
  dest <- file.path(ctx$nj, "sources", sprintf("nte_tree_%s.json", pin$commit))
  r <- niwo_fetch(ctx, sprintf("https://api.github.com/repos/%s/git/trees/%s?recursive=1",
                               NTE_REPO, pin$commit), dest, "reference")
  tr <- jsonlite::fromJSON(rawToChar(r$content))
  if (isTRUE(tr$truncated)) stop("The repository listing is truncated")
  paths <- tr$tree$path[tr$tree$type == "blob"]
  ann <- niwo_annotated_plots(paths, NIWO_SITE)
  if (!nrow(ann)) stop("No NIWO annotation named <plot>_<year>.xml at ", pin$commit)
  ann$nte_commit <- pin$commit
  ann$in_task_list <- ann$plot %in% NIWO_TASK_PLOTS
  list(ann = ann, pin = pin, tree = niwo_rel(ctx, dest),
       other_niwo_annotations = grep(sprintf("^annotations/.*%s.*[.]xml$", NIWO_SITE),
                                     setdiff(paths, unlist(strsplit(ann$annotation, ";"))),
                                     value = TRUE))
}

# "geolocated <n> / <m> stems" from a neon_ground_truth.R log.
niwo_geolocated <- function(log) {
  l <- grep("^geolocated [0-9]+ / [0-9]+ stems", readLines(log, warn = FALSE), value = TRUE)
  if (!length(l)) return(NULL)
  as.integer(regmatches(l[1], gregexpr("[0-9]+", l[1]))[[1]][1:2])
}

# Per annotated plot: whether the woody vegetation data hold it, its plot
# record and type, and its live mapped stems (all, DBH >= 10 cm, with a
# measured height, with a canopy position).
niwo_reference_summary <- function(ann, gt, pc, vst_plots) {
  do.call(rbind, lapply(ann$plot, function(p) {
    st <- gt[gt$plotID == p & gt$live %in% TRUE & gt$is_tree %in% TRUE &
               is.finite(gt$E) & is.finite(gt$N), , drop = FALSE]
    d10 <- is.finite(st$stemDiameter) & st$stemDiameter >= OFO_REG$dbh_floor
    h <- is.finite(st$height) & st$height > 0
    cp <- !is.na(st$canopyPosition) & nzchar(st$canopyPosition)
    k <- match(p, pc$plotID)
    data.frame(plot = p, in_vst = p %in% vst_plots, plot_record = !is.na(k),
               plot_type = if (is.na(k)) NA_character_ else pc$plotType[k],
               plot_meas_year = if (is.na(k)) NA_integer_ else pc$plot_meas_year[k],
               n_mapped = sum(gt$plotID == p), n_live_mapped = nrow(st), n_dbh10 = sum(d10),
               n_height = sum(h), n_canopy_position = sum(cp), n_dbh10_height = sum(d10 & h),
               n_dbh10_canopy_position = sum(d10 & cp), stringsAsFactors = FALSE)
  }))
}

niwo_stage_reference <- function(ctx) {
  dir.create(ctx$nj, recursive = TRUE, showWarnings = FALSE)
  before <- niwo_neon_listing(ctx$d)
  lst <- niwo_list_annotations(ctx)
  ann <- lst$ann
  fwrite(ann, file.path(ctx$nj, "annotated_plots.csv"))
  miss <- setdiff(NIWO_TASK_PLOTS, ann$plot); extra <- setdiff(ann$plot, NIWO_TASK_PLOTS)
  message(sprintf("[reference] %d NIWO plots annotated as <plot>_<year>.xml at %s%s", nrow(ann),
                  substr(lst$pin$commit, 1, 12),
                  if (length(miss) || length(extra)) sprintf(" (task list: missing %s; extra %s)",
                    paste(miss, collapse = ","), paste(extra, collapse = ",")) else
                    "; identical to the task's list"))
  # neon_ground_truth.R geolocates stems through the public locations API one
  # call per point; calls refused under its rate limit leave stems
  # unlocated, and a rerun fetches only those (the script caches the rest).
  gts <- niwo_ground_truth_script(ctx)
  runs <- list(); last <- -1L
  for (attempt in 1:5) {
    runs[[attempt]] <- niwo_run_script(ctx, "reference", "neon_ground_truth.R",
                                       c(paste0("SITE=", NIWO_SITE), paste0("YEAR=", NIWO_YEAR)),
                                       path = gts$path)
    g <- niwo_geolocated(runs[[attempt]]$log)
    cl <- runs[[attempt]]$calls
    # Only refusals under the rate limit (429) or failed connections can pass
    # on a retry; a location the API rejects (400) stays unlocated.
    limited <- NROW(cl) && any(cl$kind == "json" & !cl$ok & (is.na(cl$status) | cl$status == 429L))
    if (is.null(g) || g[1] >= g[2] || g[1] <= last || !limited) break
    last <- g[1]
    message(sprintf("[reference] geolocated %d of %d stems; retrying the rest in 90 s",
                    g[1], g[2]))
    Sys.sleep(90)
  }
  f <- niwo_field(ctx)
  rds <- file.path(ctx$nd, "vst", sprintf("%s_vst_allyears.rds", tolower(NIWO_SITE)))
  dat <- readRDS(rds)
  vst_plots <- unique(c(dat$vst_perplotperyear$plotID, dat$vst_mappingandtagging$plotID,
                        dat$vst_apparentindividual$plotID))
  summ <- niwo_reference_summary(ann, f$gt, f$pc, vst_plots)
  fwrite(summ, file.path(ctx$nj, "reference_summary.csv"))
  niwo_neon_evidence(ctx, before, "reference")
  outs <- niwo_rel(ctx, c(file.path(ctx$nj, c("annotated_plots.csv", "reference_summary.csv")),
                          file.path(ctx$nd, c("ground_truth_stems.csv", "plot_centroids.csv",
                                              "tiles_needed.csv", "point_locations.csv",
                                              "reference_manifest.json")), rds,
                          if (gts$patched) gts$path))
  niwo_record(ctx, "reference", niwo_sha(ctx, lst$tree), outs, list(
    nte = c(list(repo = NTE_REPO), lst$pin, list(tree_listing = lst$tree)),
    task_plots = NIWO_TASK_PLOTS, annotated_plots = ann$plot,
    task_list_missing = miss, task_list_extra = extra,
    other_niwo_annotations = lst$other_niwo_annotations,
    ground_truth = list(script = "scripts/neon_ground_truth.R",
                        run_as = gts[setdiff(names(gts), "path")],
                        args = c(paste0("SITE=", NIWO_SITE), paste0("YEAR=", NIWO_YEAR)),
                        max_year_gap = 4, runs = length(runs),
                        geolocated = niwo_geolocated(runs[[length(runs)]]$log),
                        logs = niwo_rel(ctx, vapply(runs, `[[`, "", "log")))))
  print_reference(summ, f$gt)
  invisible(summ)
}

print_reference <- function(summ, gt) {
  cat(sprintf(paste("\nNIWO annotated plots: %d; in the woody vegetation data %d; with a plot",
                    "record %d\n"), nrow(summ), sum(summ$in_vst), sum(summ$plot_record)))
  print(summ, row.names = FALSE)
  cat(sprintf("Totals over annotated plots: live mapped %d, DBH >= 10 cm %d, with height %d,",
              sum(summ$n_live_mapped), sum(summ$n_dbh10), sum(summ$n_height)),
      sprintf("with canopy position %d\n", sum(summ$n_canopy_position)))
}

## ---- STAGE=lidar -----------------------------------------------------------------------
niwo_laz <- function(ctx)
  sort(list.files(ctx$lidar, pattern = "[.]laz$", recursive = TRUE, full.names = TRUE))

# One row per downloaded tile: its file, 1 km key, bytes and SHA-256
# (neon_tile_index() stops on two files for one tile; it is given two identity
# columns so that its row subset stays a data frame).
niwo_tile_table <- function(ctx, laz) {
  idx <- neon_tile_index(data.frame(name = basename(laz), size = file.size(laz),
                                    stringsAsFactors = FALSE), "DP1.30003.001")
  f <- laz[match(idx$name, basename(laz))]
  data.frame(file = niwo_rel(ctx, f), key = idx$key, bytes = file.size(f),
             sha256 = vapply(f, frozen_sha256, "", USE.NAMES = FALSE), stringsAsFactors = FALSE)
}

niwo_coverage <- function(geo, keys) {
  need <- strsplit(ifelse(is.na(geo$tiles), "", geo$tiles), ";", fixed = TRUE)
  geo$tiles_missing <- vapply(need, function(k) paste(setdiff(k, keys), collapse = ";"), "")
  geo$covered <- !is.na(geo$tiles) & !nzchar(geo$tiles_missing)
  geo
}

niwo_stage_lidar <- function(ctx) {
  ann <- niwo_read_annotated(ctx)
  f <- niwo_field(ctx)
  geo <- niwo_clip_geometry(ann$plot, f$pc)
  framed <- geo$plot[!is.na(geo$cx)]
  if (!length(framed)) stop("No annotated plot has a plot record")
  before <- niwo_neon_listing(ctx$d)
  have <- niwo_laz(ctx)
  keys0 <- if (length(have)) niwo_tile_table(ctx, have)$key else character()
  run <- NULL
  if (all(niwo_coverage(geo[!is.na(geo$cx), ], keys0)$covered) &&
      file.exists(file.path(ctx$lidar, "acquisition_manifest.json"))) {
    message("[lidar] tiles present and covering every clip box; nothing fetched")
  } else {
    run <- niwo_run_script(ctx, "lidar", "neon_download_lidar.R",
                           c(paste0("SITE=", NIWO_SITE), paste0("YEAR=", NIWO_YEAR),
                             paste0("PLOTS=", paste(framed, collapse = ","))))
  }
  laz <- niwo_laz(ctx)
  if (!length(laz)) stop("No tiles downloaded")
  # The checks the repo applies before freezing clips (neon_read_catalog()).
  neon_validate_acquisition(ctx$lidar, f$gt, f$pc, "DP1.30003.001")
  neon_validate_files(laz, f$epsg)
  tiles <- niwo_tile_table(ctx, laz)
  cov <- niwo_coverage(geo, tiles$key)
  live <- unique(ext_live_trees(f$gt)$plotID)
  cov$live_trees <- cov$plot %in% live
  fwrite(tiles, file.path(ctx$nj, "tiles.csv"))
  fwrite(cov, file.path(ctx$nj, "coverage.csv"))
  niwo_neon_evidence(ctx, before, "lidar")
  mf <- file.path(ctx$lidar, "acquisition_manifest.json")
  niwo_record(ctx, "lidar", niwo_sha(ctx, f$files),
              niwo_rel(ctx, c(file.path(ctx$nj, c("tiles.csv", "coverage.csv")), mf)), list(
    script = "scripts/neon_download_lidar.R", fetched = !is.null(run),
    log = if (is.null(run)) NULL else niwo_rel(ctx, run$log),
    acquisition_manifest = jsonlite::read_json(mf),
    crs_checked = list(epsg = f$epsg, files = nrow(tiles)),
    tiles = tiles, n_tiles = nrow(tiles), bytes = sum(tiles$bytes),
    plots_not_covered = cov$plot[!cov$covered]))
  cat(sprintf("\nTiles: %d (%.1f MB), EPSG:%d checked on every header\n", nrow(tiles),
              sum(tiles$bytes) / 1e6, f$epsg))
  print(cov[, c("plot", "plot_type", "cx", "cy", "core_half", "tiles", "covered",
                "live_trees")], row.names = FALSE)
  invisible(cov)
}

## ---- STAGE=clips -----------------------------------------------------------------------
# A clip_manifest.csv row of freeze_clips.R for a native cell.
niwo_cell_row <- function(g, status, prep) {
  data.frame(site = NIWO_SITE, plot = g$plot, rung = "native", status = status, cx = g$cx,
             cy = g$cy, core_half = g$core_half, buffer = NIWO_BUFFER,
             seed = seed_for(NIWO_SITE, g$plot, NA), seed_salt = 0L,
             pdens = if (is.null(prep)) NA_real_ else prep$pdens,
             frdens = if (is.null(prep)) NA_real_ else prep$frdens,
             native_pdens = if (is.null(prep)) NA_real_ else prep$pdens,
             native_frdens = if (is.null(prep)) NA_real_ else prep$frdens,
             stringsAsFactors = FALSE)
}

niwo_stage_clips <- function(ctx) {
  ann <- niwo_read_annotated(ctx)
  f <- niwo_field(ctx)
  cov_path <- file.path(ctx$nj, "coverage.csv")
  if (!file.exists(cov_path)) stop("Run STAGE=lidar first")
  geo <- niwo_clip_geometry(ann$plot, f$pc)
  laz <- niwo_laz(ctx)
  cov <- niwo_coverage(geo, niwo_tile_table(ctx, laz)$key)
  todo <- cov[cov$covered, , drop = FALSE]
  before <- niwo_neon_listing(ctx$d)
  root <- ctx$root
  if (frozen_sealed(root)) {
    message("[clips] ", niwo_rel(ctx, root), " is sealed: reading its cells")
  } else {
    ctg <- neon_read_catalog(laz, ext_live_trees(f$gt), f$pc, ctx$lidar)
    lidR::opt_progress(ctg) <- FALSE
    cells <- do.call(rbind, lapply(seq_len(nrow(todo)), function(i) {
      g <- todo[i, ]
      cl <- frozen_clip(ctg, NIWO_SITE, g$plot, NA, g$cx, g$cy, g$core_half, root,
                        buffer = NIWO_BUFFER)
      message(sprintf("[clips] %s %s", g$plot, if (is.null(cl)) "unusable" else
        sprintf("pdens %.2f frdens %.2f", cl$pdens, cl$frdens)))
      niwo_cell_row(g, if (is.null(cl)) "unusable" else "ok", cl)
    }))
    if (is.null(cells)) stop("No annotated plot lies on the downloaded tiles")
    dir.create(root, recursive = TRUE, showWarnings = FALSE)
    frozen_seal(root, cells)
  }
  man <- frozen_clip_manifest(root)
  clips <- do.call(rbind, lapply(seq_len(nrow(cov)), function(i) {
    g <- cov[i, ]
    k <- match(g$plot, man$plot)
    if (is.na(k))
      return(data.frame(plot = g$plot, status = niwo_missing_reason(g), cx = g$cx, cy = g$cy,
                        core_half = g$core_half, buffer = NIWO_BUFFER, seed = NA_integer_,
                        pdens = NA_real_, frdens = NA_real_, n_raw = NA_integer_,
                        n_norm = NA_integer_, normalized_laz = NA_character_,
                        rawground_sha256 = NA_character_, normalized_sha256 = NA_character_,
                        dtm_sha256 = NA_character_, manifest_sha256 = NA_character_,
                        stringsAsFactors = FALSE))
    m <- man[k, ]
    cell <- frozen_read(root, NIWO_SITE, g$plot, NA, g$cx, g$cy, g$core_half, NIWO_BUFFER,
                        manifest = man)
    mf <- if (is.null(cell)) NULL else jsonlite::read_json(cell$manifest, simplifyVector = TRUE)
    data.frame(plot = g$plot, status = m$status, cx = m$cx, cy = m$cy, core_half = m$core_half,
               buffer = m$buffer, seed = m$seed, pdens = m$pdens, frdens = m$frdens,
               n_raw = if (is.null(mf)) NA_integer_ else as.integer(mf$n_raw),
               n_norm = if (is.null(mf)) NA_integer_ else as.integer(mf$n_norm),
               normalized_laz = if (is.null(cell)) NA_character_ else
                 niwo_rel(ctx, cell$normalized),
               rawground_sha256 = m$rawground_sha256, normalized_sha256 = m$normalized_sha256,
               dtm_sha256 = m$dtm_sha256, manifest_sha256 = m$manifest_sha256,
               stringsAsFactors = FALSE)
  }))
  fwrite(clips, file.path(ctx$nj, "clips.csv"))
  niwo_neon_evidence(ctx, before, "clips")
  niwo_record(ctx, "clips", niwo_sha(ctx, c(f$files, niwo_rel(ctx, c(
                cov_path, file.path(ctx$nj, "tiles.csv"))))),
              niwo_rel(ctx, c(file.path(ctx$nj, "clips.csv"),
                              file.path(root, "clip_manifest.csv"))), list(
    provider = "frozen_clip(ctg, 'NIWO', plot, NA, cx, cy, core_half, out_root, buffer = 25)",
    out_root = niwo_rel(ctx, root), lidr_threads = FROZEN_LIDR_THREADS,
    clip_manifest_sha256 = frozen_root_id(root),
    versions = list(R = R.version.string, lidR = as.character(utils::packageVersion("lidR")),
                    rlas = as.character(utils::packageVersion("rlas")),
                    terra = as.character(utils::packageVersion("terra")))))
  cat("\nNIWO clips (native):\n")
  print(clips[, c("plot", "status", "core_half", "pdens", "frdens", "n_raw", "n_norm")],
        row.names = FALSE, digits = 4)
  invisible(clips)
}

## ---- STAGE=register --------------------------------------------------------------------
# fwrite() lines of a table: the text a CSV row of these values has.
niwo_csv_lines <- function(df) {
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f))
  fwrite(df, f)
  readLines(f)
}

# The path-equivalence proof. For each benchmark plot, the NIWO path
# (niwo_stems(), its native clip read through frozen_read() from the sealed
# root, the plot's own Amendment 1 offset, niwo_register_plot()) must give the
# text of its frozen-variant rows in the first protocol's table of its half,
# byte for byte. Read-only: the sealed root, the benchmark's references and
# the first protocol's tables are only read.
niwo_equivalence <- function(ctx, plots) {
  root <- frozen_root(ctx$d)
  if (!frozen_sealed(root)) stop("No sealed frozen root at ", root)
  man <- frozen_clip_manifest(root)
  units <- read.csv(file.path(ctx$pre, "registration_units.csv"), stringsAsFactors = FALSE)
  tabs <- c(development = "registration_dev.csv", confirmation = "registration_confirm.csv")
  lines <- lapply(tabs, function(t) readLines(file.path(ctx$pre, t), warn = FALSE))
  sites <- unique(sub("_[0-9]+$", "", plots))
  gts <- stats::setNames(lapply(sites, function(s) read.csv(
    file.path(ctx$d, "neon", s, "ground_truth_stems.csv"), stringsAsFactors = FALSE)), sites)
  rows <- niwo_par_map(plots, function(p) {
    site <- sub("_[0-9]+$", "", p)
    pop <- frozen_population(root, site, "adopted")
    row <- pop[pop$plotID == p, , drop = FALSE]
    u <- units[units$unit == p & units$kind == "plot", , drop = FALSE]
    if (nrow(row) != 1L || nrow(u) != 1L) stop(p, " is not a plot unit of the first protocol")
    cell <- frozen_read(root, site, p, NA, row$easting, row$northing, row$core_half,
                        manifest = man)
    off <- niwo_offset(p)
    mine <- niwo_register_plot(p, site, niwo_stems(gts[[site]], p), cell$normalized, off)
    ref <- lines[[u$set]]
    cols <- strsplit(ref[1], ",", fixed = TRUE)[[1]]
    got <- niwo_csv_lines(mine[, cols])
    if (!identical(got[1], ref[1])) stop("Header differs from ", tabs[[u$set]])
    p1 <- fread(text = ref[c(1L, which(startsWith(ref, paste0(OFO_REG2$height$variant,
                                                              ",height,", p, ",")) |
                                       startsWith(ref, paste0(OFO_REG2$rank$variant, ",rank,",
                                                              p, ","))))],
                na.strings = "")
    do.call(rbind, lapply(seq_len(nrow(mine)), function(i) {
      key <- paste(mine$variant[i], mine$signal[i], p, "", sep = ",")
      r_line <- ref[startsWith(ref, key)]
      m_line <- got[startsWith(got, key)]
      j <- match(mine$signal[i], p1$signal)
      data.frame(plot = p, site = site, half = u$set, table = tabs[[u$set]],
                 signal = mine$signal[i], variant = mine$variant[i],
                 offset_dx = off[1], offset_dy = off[2],
                 offset_matches_units = isTRUE(all.equal(c(u$offset_dx, u$offset_dy), off,
                                                         tolerance = 1e-12)),
                 n_signal_p1 = p1$n_signal[j], n_signal = mine$n_signal[i],
                 dx_p1 = p1$dx[j], dx = mine$dx[i], dy_p1 = p1$dy[j], dy = mine$dy[i],
                 residual_m_p1 = p1$residual_m[j], residual_m = mine$residual_m[i],
                 sub_p90_m_p1 = p1$sub_p90_m[j], sub_p90_m = mine$sub_p90_m[i],
                 accepted_p1 = p1$accepted[j], accepted = mine$accepted[i],
                 reject_reason_p1 = p1$reject_reason[j], reject_reason = mine$reject_reason[i],
                 rows_in_table = length(r_line),
                 identical_row = length(r_line) == 1L && length(m_line) == 1L &&
                   identical(r_line, m_line), stringsAsFactors = FALSE)
    }))
  }, ctx$cores)
  do.call(rbind, rows)
}

# The tables the equivalence proof reads, relative to the job directory.
niwo_equivalence_inputs <- function(ctx, plots) {
  root <- frozen_root(ctx$d)
  c(niwo_rel(ctx, file.path(ctx$pre, c("registration_dev.csv", "registration_confirm.csv",
                                       "registration_units.csv"))),
    niwo_rel(ctx, file.path(root, c("clip_manifest.csv", "population.csv"))),
    niwo_rel(ctx, file.path(ctx$d, "neon", unique(sub("_[0-9]+$", "", plots)),
                            "ground_truth_stems.csv")))
}

niwo_stage_register <- function(ctx) {
  if (!identical(ofo2_config_digest(), NIWO_DIGEST) || !ofo2_frozen())
    stop("The frozen method's digest is not ", NIWO_DIGEST, ": OFO_REG2 changed")
  ann <- niwo_read_annotated(ctx)
  f <- niwo_field(ctx)
  clips_path <- file.path(ctx$nj, "clips.csv")
  if (!file.exists(clips_path) || !frozen_sealed(ctx$root)) stop("Run STAGE=clips first")
  clips <- read.csv(clips_path, stringsAsFactors = FALSE)
  in_files <- c(f$files, niwo_rel(ctx, c(clips_path, file.path(ctx$nj, "annotated_plots.csv"),
                                         file.path(ctx$root, "clip_manifest.csv"))),
                niwo_equivalence_inputs(ctx, ctx$equiv))
  in_sha <- niwo_sha(ctx, in_files)          # taken before reading; must not move
  before <- niwo_neon_listing(ctx$d)
  # 1. the path-equivalence proof, before any NIWO unit is registered
  eq <- list(table = niwo_equivalence(ctx, ctx$equiv))
  fwrite(eq$table, file.path(ctx$nj, "path_equivalence.csv"))
  eq_ok <- all(eq$table$identical_row) && all(eq$table$offset_matches_units)
  print_equivalence(eq$table)
  if (!eq_ok) {
    niwo_neon_evidence(ctx, before, "register")
    stop("The NIWO path does not reproduce the first protocol's rows; NIWO not registered")
  }
  # 2. the frozen method once on each annotated NIWO plot
  geo <- niwo_clip_geometry(ann$plot, f$pc)
  man <- frozen_clip_manifest(ctx$root)
  rows <- niwo_par_map(seq_len(nrow(geo)), function(i) {
    g <- geo[i, ]
    st <- niwo_stems(f$gt, g$plot)
    off <- niwo_offset(g$plot)
    k <- match(g$plot, clips$plot)
    status <- if (is.na(k)) niwo_missing_reason(g) else clips$status[k]
    if (!identical(status, "ok"))
      return(niwo_unrun_rows(g$plot, NIWO_SITE, st, off,
                             if (status == "unusable") "no_clip" else status))
    cell <- frozen_read(ctx$root, NIWO_SITE, g$plot, NA, g$cx, g$cy, g$core_half, NIWO_BUFFER,
                        manifest = man)
    niwo_register_plot(g$plot, NIWO_SITE, st, cell$normalized, off)
  }, ctx$cores)
  res <- do.call(rbind, rows)
  res <- res[order(match(res$signal, NIWO_SIGNALS), res$unit), NIWO_REG_COLUMNS]
  rownames(res) <- NULL
  units <- niwo_units_table(geo, f$gt, clips, ann, niwo_rel(ctx, ctx$root))
  reg_path <- file.path(ctx$p2, "registration_niwo.csv")
  units_path <- file.path(ctx$p2, "niwo_units.csv")
  if (!identical(niwo_sha(ctx, in_files), in_sha))
    stop("Inputs changed during the run: ",
         paste(in_files[niwo_sha(ctx, in_files) != in_sha], collapse = ", "))
  niwo_write_once(res, reg_path)
  fwrite(units, units_path)
  niwo_neon_evidence(ctx, before, "register")
  niwo_record(ctx, "register", in_sha,
              niwo_rel(ctx, c(reg_path, units_path, file.path(ctx$nj, "path_equivalence.csv"))),
              list(frozen = list(
                     height = OFO_REG2$height, rank = OFO_REG2$rank,
                     offset = "set.seed(seed_for('offset2', plot, NA)); runif(2, -8, 8)",
                     shifts = nrow(ofo_shift_grid())),
                   path_equivalence = list(plots = ctx$equiv, identical = eq_ok,
                                           rows = nrow(eq$table)),
                   units = nrow(units)))
  print_register(res, units)
  invisible(res)
}

# The method runs once: a rerun must reproduce an existing table exactly, and
# a table that would differ is never overwritten.
niwo_write_once <- function(res, path) {
  new <- niwo_csv_lines(res)
  if (file.exists(path)) {
    old <- readLines(path, warn = FALSE)
    if (!identical(old, new))
      stop(path, " exists and this run differs from it; it is never overwritten")
    message("[register] ", basename(path), " exists and this run reproduces it exactly")
    return(invisible(path))
  }
  fwrite(res, path)
  invisible(path)
}

print_equivalence <- function(eq) {
  cat("\nPath equivalence (NIWO path on benchmark plots vs the first protocol's rows):\n")
  print(eq[, c("plot", "half", "signal", "n_signal", "dx", "dy", "residual_m", "sub_p90_m",
               "accepted", "reject_reason", "identical_row")], row.names = FALSE, digits = 6)
  cat(sprintf("  %d of %d rows byte-identical; offsets equal to registration_units.csv: %s\n",
              sum(eq$identical_row), nrow(eq), all(eq$offset_matches_units)))
}

print_register <- function(res, units) {
  cat("\nNIWO units under the frozen method (zero-truth error shown for comparison only):\n")
  print(res[, c("signal", "unit", "n_signal", "offset_dx", "offset_dy", "dx", "dy", "error_m",
                "sub_p90_m", "second_peak", "accepted", "reject_reason", "at_min_stems")],
        row.names = FALSE, digits = 3)
  for (s in NIWO_SIGNALS) {
    x <- res[res$signal == s, ]
    cat(sprintf("  %-6s units %d, run %d, at >= %d stems %d, accepted %d\n", s, nrow(x),
                sum(is.finite(x$dx)), OFO_REG2[[s]]$gate$min_stems, sum(x$at_min_stems),
                sum(x$accepted)))
  }
}

## ---- main ---------------------------------------------------------------------------
niwo_main <- function() {
  args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
  A <- stats::setNames(lapply(args, function(x) paste(x[-1], collapse = "=")),
                       vapply(args, `[`, "", 1))
  stage <- A$STAGE
  if (is.null(stage) || !stage %in% NIWO_STAGES)
    stop("STAGE must be one of ", paste(NIWO_STAGES, collapse = ", "))
  options(lidR.progress = FALSE)
  ctx <- niwo_context(.job_dir(), A)
  switch(stage, reference = niwo_stage_reference(ctx), lidar = niwo_stage_lidar(ctx),
         clips = niwo_stage_clips(ctx), register = niwo_stage_register(ctx))
  invisible(NULL)
}

if (sys.nframe() == 0L) niwo_main()
