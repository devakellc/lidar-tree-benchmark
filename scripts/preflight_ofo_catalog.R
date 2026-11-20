#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("ofo_preflight_lib.R"))

# CATALOG stage of the Open Forest Observatory preflight
# (docs/ofo-preflight-protocol.md: Sources, Plot groups, Admitted flights,
# Frames, Geometry audit). Score-blind: no detector runs here.
#   fetch     pins Zenodo record 23402904 (MD5-verified; reuses a cached copy
#             with the record's MD5), the 3DEP Entwine index and WESM.csv;
#             writes OFO/preflight/sources.json.
#   inventory plots.csv, trees.csv, licences.csv (frames, screen, groups).
#   flights   ept_candidates.csv; pulls each non-NEON plot's ranked 3DEP
#             candidates with PDAL (resumable, CORES at a time) into
#             OFO/clouds/candidates and links the selected one to
#             OFO/clouds/<plot_id>.laz; flights.csv, clouds.csv and
#             flights_record.json (digests read and written). Candidates are
#             pulled in rank order while one could still be admitted or
#             outrank the best pulled so far (empty pulls fall through); the
#             selected flight is the best admitted one, else the best pulled.
#             Measurements use the kept returns (classes 7 and 18 and
#             withheld returns dropped; the stored clouds keep the flag).
#             REMEASURE=TRUE recomputes every pulled candidate from its stored
#             LAZ with the current plots.csv polygon and reruns the selection;
#             it pulls only a candidate the selection now asks for and that
#             was never pulled, and names each such pull and every plot whose
#             selected flight or admission changed.
#   geometry  geometry_audit.csv, geometry_by_project.csv, geometry_record.json.
# OFO = $CLAUDE_JOB_DIR/ofo; nothing is written elsewhere. Inputs: the
# network, and optionally a cache directory of the record files (CACHE=).
# PLOTS= restricts the flights step, and the rows of flights.csv and
# clouds.csv, to those plots (for trials; a full run rewrites them).
#   Rscript scripts/preflight_ofo_catalog.R [STEPS=fetch,inventory,flights,geometry] \
#     [CORES=8] [PLOTS=0001,0002] [REFRESH=FALSE] [CACHE=<dir>] [REMEASURE=FALSE]
suppressMessages({ library(data.table); library(sf) })
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
arg <- function(k, d) if (is.null(A[[k]]) || !nzchar(A[[k]])) d else A[[k]]
steps <- strsplit(arg("STEPS", "fetch,inventory,flights,geometry"), ",")[[1]]
cores <- as.integer(arg("CORES", "8"))
refresh <- isTRUE(as.logical(arg("REFRESH", "FALSE")))
remeasure <- isTRUE(as.logical(arg("REMEASURE", "FALSE")))
sel <- if (is.null(A$PLOTS)) NULL else
  sprintf("%04d", as.integer(strsplit(A$PLOTS, ",")[[1]]))
cache <- arg("CACHE", file.path(.job_dir(), "ofo-preflight", "sources"))

RECORD <- "23402904"
RECORD_URL <- sprintf("https://zenodo.org/api/records/%s", RECORD)
INDEX_URLS <- c(
  resources.geojson = paste0("https://raw.githubusercontent.com/hobuinc/usgs-lidar/",
                             "master/boundaries/resources.geojson"),
  WESM.csv = paste0("https://rockyweb.usgs.gov/vdelivery/Datasets/Staged/Elevation/",
                    "metadata/WESM.csv"))
OFO <- file.path(.job_dir(), "ofo")
D_SRC <- file.path(OFO, "sources"); D_IDX <- file.path(OFO, "lidar-index")
D_PRE <- file.path(OFO, "preflight"); D_CLD <- file.path(OFO, "clouds")
D_CAND <- file.path(D_CLD, "candidates"); D_EPT <- file.path(D_IDX, "ept")
for (d in c(D_SRC, D_IDX, D_PRE, D_CLD, D_CAND, D_EPT))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
NEON_PROJECT <- "NEON2023"
F_SOURCES <- file.path(D_PRE, "sources.json")

now_utc <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
sha256 <- function(f) digest::digest(file = f, algo = "sha256")
md5 <- function(f) digest::digest(file = f, algo = "md5")
read_pid <- function(f) fread(f, colClasses = list(character = "plot_id"), na.strings = "")
put <- function(x, f) { fwrite(x, f, na = ""); message("wrote ", f, " (", nrow(x), " rows)") }

# Download to a temporary name, then rename: an interrupted run never leaves
# a partial file that a later run would take as complete.
fetch_url <- function(url, dest, tries = 3) {
  tmp <- paste0(dest, ".part")
  for (i in seq_len(tries)) {
    ok <- tryCatch({ curl::curl_download(url, tmp, quiet = TRUE); TRUE },
                   error = function(e) { message("  download failed (", i, "): ",
                                                 conditionMessage(e)); FALSE })
    if (ok) { file.rename(tmp, dest); return(invisible(dest)) }
    Sys.sleep(5 * i)
  }
  unlink(tmp); stop("could not download ", url)
}

# sources.json keeps one entry per file; an entry is reused while its file
# is unchanged so the retrieval time stays the original one.
sources_read <- function() {
  if (!file.exists(F_SOURCES)) return(list())
  s <- jsonlite::fromJSON(F_SOURCES, simplifyVector = FALSE)$files
  setNames(s, vapply(s, `[[`, "", "path"))
}
sources_write <- function(entries) {
  entries <- entries[order(names(entries))]
  doc <- list(written_utc = now_utc(), record = RECORD, record_url = RECORD_URL,
              files = unname(entries))
  writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE, null = "null"), F_SOURCES)
  message("wrote ", F_SOURCES, " (", length(entries), " files)")
}
source_entry <- function(path, url, how, prev = NULL, extra = list()) {
  rel <- sub(paste0("^", normalizePath(OFO), "/"), "", normalizePath(path))
  h <- sha256(path)
  if (!is.null(prev) && identical(prev$sha256, h) && identical(how, "present")) return(prev)
  c(list(path = rel, url = url, retrieved_utc = now_utc(), obtained = how,
         bytes = file.size(path), sha256 = h), Filter(Negate(is.null), extra))
}

# ---- fetch ----------------------------------------------------------------
step_fetch <- function() {
  prev <- sources_read(); out <- list()
  rec_f <- file.path(D_SRC, "zenodo-record.json")
  how <- if (refresh || !file.exists(rec_f)) { fetch_url(RECORD_URL, rec_f); "download" } else
    "present"
  key <- "sources/zenodo-record.json"
  out[[key]] <- source_entry(rec_f, RECORD_URL, how, prev[[key]])
  rec <- jsonlite::fromJSON(rec_f, simplifyVector = FALSE)
  for (f in rec$files) {
    dest <- file.path(D_SRC, f$key); want <- sub("^md5:", "", f$checksum)
    url <- f$links$self; key <- file.path("sources", f$key)
    how <- "present"
    if (refresh || !file.exists(dest) || md5(dest) != want) {
      cached <- file.path(cache, f$key)
      if (!refresh && file.exists(cached) && md5(cached) == want) {
        file.copy(cached, dest, overwrite = TRUE); how <- "copy"
      } else { fetch_url(url, dest); how <- "download" }
    }
    got <- md5(dest)
    if (got != want) stop(sprintf("MD5 mismatch for %s: %s vs record %s", f$key, got, want))
    out[[key]] <- source_entry(dest, url, how, prev[[key]],
                               list(md5 = got, md5_record = want, md5_matches_record = TRUE,
                                    copied_from = if (how == "copy") cache else NULL))
    message(sprintf("  %-45s %s  md5 ok", f$key, how))
  }
  for (k in names(INDEX_URLS)) {
    dest <- file.path(D_IDX, k); key <- file.path("lidar-index", k)
    how <- if (refresh || !file.exists(dest)) { fetch_url(INDEX_URLS[[k]], dest); "download" } else
      "present"
    out[[key]] <- source_entry(dest, INDEX_URLS[[k]], how, prev[[key]])
    message(sprintf("  %-45s %s", k, how))
  }
  # Entwine resource descriptions fetched by the flights step stay listed.
  for (k in grep("^lidar-index/ept/", names(prev), value = TRUE)) out[[k]] <- prev[[k]]
  sources_write(out)
}

# ---- catalogue ------------------------------------------------------------
read_catalog <- function() {
  pl <- st_read(file.path(D_SRC, "ofo_ground-reference_plots.gpkg"), quiet = TRUE,
                fid_column_name = "fid")
  tr <- st_read(file.path(D_SRC, "ofo_ground-reference_trees.gpkg"), quiet = TRUE,
                fid_column_name = "fid")
  tr <- tr[order(tr$fid), ]
  pl$polygon_valid <- st_is_valid(pl)
  if (!all(pl$polygon_valid)) pl <- st_make_valid(pl)
  pl$survey_year <- ofo_survey_year(pl$survey_date)
  fr <- ofo_project_frames(st_drop_geometry(pl))
  pl$epsg <- fr$epsg[match(pl$project_name, fr$project_name)]
  # Geodesic (ellipsoidal) area: s2 off routes st_area through lwgeom.
  old <- suppressMessages(sf_use_s2(FALSE))
  pl$polygon_area_m2 <- as.numeric(st_area(pl))
  suppressMessages(sf_use_s2(old))
  list(plots = pl, trees = tr, frames = fr)
}

step_inventory <- function() {
  cat_ <- read_catalog(); pl <- cat_$plots; tr <- cat_$trees
  # Full precision: every polygon test downstream reads this WKT.
  pl$polygon_wkt <- ofo_frame_wkt(pl)
  tr$tree_n <- ave(seq_len(nrow(tr)), tr$plot_id, FUN = seq_along)
  ll <- st_coordinates(tr)
  tr$lon <- ll[, 1]; tr$lat <- ll[, 2]
  tr$epsg <- pl$epsg[match(tr$plot_id, pl$plot_id)]
  tr$x <- NA_real_; tr$y <- NA_real_; tr$inside <- NA; tr$outside_m <- NA_real_
  for (e in unique(tr$epsg)) {
    i <- which(tr$epsg == e)
    pts <- st_transform(tr[i, "plot_id"], e)
    xy <- st_coordinates(pts); tr$x[i] <- xy[, 1]; tr$y[i] <- xy[, 2]
    polys <- st_as_sf(data.frame(plot_id = pl$plot_id[pl$epsg == e]),
                      geometry = st_as_sfc(pl$polygon_wkt[pl$epsg == e], crs = e))
    pos <- ofo_tree_position(pts, polys)
    tr$inside[i] <- pos$inside; tr$outside_m[i] <- pos$outside_m
  }
  P <- as.data.table(st_drop_geometry(pl))
  P[, hyperplot := !is.na(hyperplot_id) & nzchar(hyperplot_id)]
  T <- as.data.table(st_drop_geometry(tr))
  I <- ofo_plot_inventory(P, T[, .(plot_id, dbh, height, live_dead, growth_form,
                                   crown_position, inside)])
  I[, `:=`(survey_date_raw = sprintf("%.0f", survey_date),
           survey_date = format(ofo_survey_date(survey_date)))]
  plots_cols <- c("plot_id", "project_name", "contributor_plot_id", "survey_date_raw",
                  "survey_year", "survey_date", "survey_date_approx", "plot_shape",
                  "plot_area_ha", "hyperplot", "subplots", "exhaustive_survey", "min_dbh",
                  "min_dbh_live", "min_ht", "live_floor_cm", "height_measured_catalog",
                  "includes_snags", "num_ohvis_trees_excluded", "license_short", "license",
                  "investigator_names", "withhold_from_training", "plot_lon", "plot_lat",
                  "epsg", "polygon_wkt", "polygon_area_m2", "n_trees", "n_live",
                  "n_live_dbh10", "n_ref", "height_share", "heights_measured",
                  "crown_position_share", "status_recorded", "screen", "group", "top_species",
                  "ref_floor_cm", "hyperplot_id", "polygon_valid")
  setnames(I, "height_measured", "height_measured_catalog")
  I <- I[order(plot_id), ..plots_cols]
  put(I, file.path(D_PRE, "plots.csv"))

  T <- merge(T, I[, .(plot_id, ref_floor_cm)], by = "plot_id")
  fl <- ofo_tree_flags(T$live_dead, T$growth_form, T$dbh, T$inside, T$ref_floor_cm)
  T[, `:=`(live = fl$live, is_tree = fl$is_tree, ref = fl$ref,
           individual_id = sprintf("OFO.%s.%d", plot_id, tree_n))]
  tree_cols <- c("plot_id", "tree_n", "individual_id", "contributor_tree_id", "lon", "lat",
                 "x", "y", "dbh", "height", "height_allometric", "species_code",
                 "growth_form", "live_dead", "crown_position", "crown_width_1",
                 "crown_width_2", "live", "is_tree", "inside", "outside_m", "ref", "epsg",
                 "fid", "subplot_id", "ohvis")
  T <- T[order(plot_id, tree_n), ..tree_cols]
  put(T, file.path(D_PRE, "trees.csv"))

  L <- I[, .(plot_id, project_name, license_short, license, investigator_names,
             withhold_from_training, redistribute_reference = ofo_redistributable(license_short))]
  put(L, file.path(D_PRE, "licences.csv"))
  print(dcast(I[, .N, by = .(project_name, cls = fifelse(is.na(group), screen, group))],
              project_name ~ cls, value.var = "N", fill = 0L))
}

# ---- flights --------------------------------------------------------------
ept_srs <- function(urls) {
  prev <- sources_read(); add <- list()
  srs <- vapply(urls, function(u) {
    nm <- basename(dirname(u)); f <- file.path(D_EPT, paste0(nm, ".json"))
    if (refresh || !file.exists(f)) fetch_url(u, f)
    key <- file.path("lidar-index", "ept", basename(f))
    add[[key]] <<- source_entry(f, u, if (is.null(prev[[key]])) "download" else "present",
                                prev[[key]])
    s <- jsonlite::fromJSON(f, simplifyVector = FALSE)$srs
    if (!is.null(s$authority) && !is.null(s$horizontal))
      paste0(s$authority, ":", s$horizontal) else s$wkt
  }, character(1))
  if (length(add)) { prev[names(add)] <- add; sources_write(prev) }
  srs
}

read_json1 <- function(f) jsonlite::fromJSON(f, simplifyVector = FALSE)
nz <- function(x, d = NA) if (is.null(x)) d else x
to_json <- function(x, f) {
  writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null",
                              null = "null"), f)
}

run_pdal <- function(pipe, json, log, tries = 3) {
  writeLines(jsonlite::toJSON(pipe, auto_unbox = TRUE, pretty = TRUE, digits = NA), json)
  out <- pipe[[length(pipe)]]$filename
  for (i in seq_len(tries)) {
    unlink(out)
    rc <- suppressWarnings(system2("pdal", c("pipeline", shQuote(json)), stdout = log,
                                   stderr = log, timeout = 3600))
    if (identical(as.integer(rc), 0L) && file.exists(out)) return(TRUE)
    if (i < tries) Sys.sleep(15 * i)
  }
  FALSE
}

LAS_COLS <- c("X", "Y", "Z", "gpstime", "Intensity", "ReturnNumber", "NumberOfReturns",
              "Classification", "Withheld_flag")

# One candidate: PDAL pull into OFO/clouds/candidates as uncompressed LAS,
# measured there, then compressed to LAZ and checked field by field against
# the LAS before the LAS is deleted. A sidecar JSON per candidate makes the
# pull resumable; failed pulls are retried on the next run.
pull_candidate <- function(pid, cand, poly, epsg, area_m2, survey_year, srs) {
  base <- file.path(D_CAND, sprintf("%s__%s", pid, cand$ept))
  laz <- paste0(base, ".laz"); js <- paste0(base, ".json"); log <- paste0(base, ".log")
  if (file.exists(js)) {
    r <- read_json1(js)
    if (identical(r$status, "empty") || (identical(r$status, "ok") && file.exists(laz)))
      return(r)
  }
  bb <- as.numeric(st_bbox(poly)) + c(-30, -30, 30, 30)
  bounds <- ofo_bounds_in_srs(bb, epsg, srs)
  tmp <- paste0(base, ".part.las"); tmpz <- paste0(base, ".part.laz")
  r <- list(plot_id = pid, ept = cand$ept, ept_url = cand$ept_url, workunit = cand$workunit,
            ql = cand$ql, collect_start = cand$collect_start, collect_end = cand$collect_end,
            gap_window_years = cand$gap_window_years, rank = cand$rank,
            retrieved_utc = now_utc(), ept_srs = srs, epsg = epsg)
  fail <- function(msg) {
    r$status <- "failed"; r$msg <- msg; unlink(c(tmp, tmpz)); to_json(r, js); r
  }
  t0 <- Sys.time()
  ok <- run_pdal(ofo_pdal_pipeline(cand$ept_url, bounds, epsg, bb, tmp),
                 paste0(base, ".pipeline.json"), log)
  r$pdal_seconds <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  if (!ok) return(fail(paste(tail(readLines(log, warn = FALSE), 3), collapse = " | ")))
  D <- tryCatch(as.data.table(rlas::read.las(tmp, select = "xyztircnw")),
                error = function(e) NULL)
  if (is.null(D)) return(fail("pulled LAS unreadable"))
  r$n_points <- nrow(D)
  if (!nrow(D)) {
    r$status <- "empty"; unlink(tmp); to_json(r, js)
    return(r)
  }
  if (any(D$Classification %in% c(7L, 18L))) return(fail("classes 7/18 not dropped"))
  m <- ofo_measure_cloud(D, poly, area_m2, survey_year)
  r[names(m)] <- m
  r$gps_time_type <- if (all(D$gpstime >= 1e6)) "adjusted_standard" else "week_or_mixed"
  r$max_return_number <- max(D$ReturnNumber, D$NumberOfReturns)
  r$max_class <- max(D$Classification)
  ok <- run_pdal(ofo_pdal_laz_pipeline(tmp, tmpz, bb, r$gps_time_type == "adjusted_standard"),
                 paste0(base, ".laz.pipeline.json"), log, tries = 1)
  if (!ok) return(fail("LAZ conversion failed"))
  Z <- tryCatch(as.data.table(rlas::read.las(tmpz, select = "xyztircnw")),
                error = function(e) NULL)
  same <- !is.null(Z) && nrow(Z) == nrow(D) &&
    all(vapply(LAS_COLS, function(k) isTRUE(all.equal(D[[k]], Z[[k]], tolerance = 0)), TRUE))
  if (!same) return(fail("LAZ differs from the pulled LAS"))
  r$status <- "ok"; r$laz_point_format <- 1L; r$laz_verified <- TRUE
  file.rename(tmpz, laz); unlink(tmp); r$sha256 <- sha256(laz)
  to_json(r, js)
  r
}

# A pulled candidate's measurements recomputed from its stored LAZ (the file
# its pull record names, checked by SHA-256) with the current polygon and the
# kept-return rule. Pull metadata stay as recorded.
remeasure_candidate <- function(pid, ept, poly, area_m2, survey_year) {
  base <- file.path(D_CAND, sprintf("%s__%s", pid, ept))
  js <- paste0(base, ".json"); laz <- paste0(base, ".laz")
  if (!file.exists(js)) return(NULL)
  r <- read_json1(js)
  if (!identical(r$status, "ok") || !file.exists(laz)) return(r)
  if (!identical(sha256(laz), r$sha256)) stop("stored cloud differs from its pull record: ", laz)
  D <- as.data.table(rlas::read.las(laz, select = "xyztircnw"))
  m <- ofo_measure_cloud(D, poly, area_m2, survey_year)
  r[names(m)] <- m
  r$remeasured_utc <- now_utc()
  to_json(r, js)
  r
}

# Whether a candidate has a usable pull on disk (pull_candidate returns it).
candidate_cached <- function(pid, ept) {
  base <- file.path(D_CAND, sprintf("%s__%s", pid, ept))
  js <- paste0(base, ".json")
  if (!file.exists(js)) return(FALSE)
  r <- read_json1(js)
  identical(r$status, "empty") || (identical(r$status, "ok") && file.exists(paste0(base, ".laz")))
}

admit_row <- function(r) {
  ofo_flight_admission(if (identical(r$status, "ok")) "ok" else nz(r$status, "failed"),
                       nz(r$ql), nz(r$gap_years), nz(r$coverage_share), nz(r$span_days),
                       if (is.null(r$flown_from) || identical(r$flown_from, "NA")) NA else
                         r$flown_from)
}

# Order of pulled candidates: admitted first, then the protocol's order with
# measured gap and end where a flight date exists, the window otherwise.
order_attempts <- function(at) {
  X <- rbindlist(lapply(at, function(r) {
    a <- admit_row(r)
    data.table(i = r$.i, admitted = a$flight_admitted, ql_num = ofo_ql_num(r$ql),
               gap = if (!is.null(r$gap_years) && !is.na(r$gap_years)) r$gap_years else
                 r$gap_window_years,
               end = if (!is.null(r$flown_to) && !is.na(r$flown_to) && r$flown_to != "NA")
                 as.Date(r$flown_to) else as.Date(gsub("/", "-", r$collect_end)),
               workunit = nz(r$workunit, ""), ept = r$ept)
  }))
  setorder(X, -admitted, ql_num, gap, -end, workunit, ept)
  X
}

# Could an unpulled candidate outrank the current best? Measured flight
# years lie inside the work-unit window, so its window gap bounds its
# measured gap from below and its window end bounds its flight end above.
could_beat <- function(cand, best) {
  if (cand$ql_num != best$ql_num) return(cand$ql_num < best$ql_num)
  if (cand$gap_window_years != best$gap) return(cand$gap_window_years < best$gap)
  as.Date(gsub("/", "-", cand$collect_end)) >= best$end
}
could_admit <- function(cand) cand$ql_num <= OFO_MAX_QL && cand$gap_window_years <= OFO_MAX_GAP

process_plot <- function(pid, R, plots, srs_map, remeasure = FALSE) {
  side <- file.path(D_CLD, paste0(pid, ".json")); laz <- file.path(D_CLD, paste0(pid, ".laz"))
  C <- R[plot_id == pid & !is.na(rank)][order(rank)]
  if (file.exists(side) && !remeasure) {
    s <- read_json1(side)
    same <- identical(as.character(unlist(s$candidates)), C$ept)
    done <- (identical(s$status, "ok") && file.exists(laz)) ||
      s$status %in% c("empty", "no_candidate")
    if (same && done) return(s)
  }
  p <- plots[plot_id == pid]
  poly <- st_as_sfc(p$polygon_wkt, crs = p$epsg)
  # Every pulled candidate is measured afresh before the selection reruns.
  if (remeasure)
    for (e in C$ept) remeasure_candidate(pid, e, poly, p$polygon_area_m2, p$survey_year)
  at <- list(); new_pulls <- character()
  for (k in seq_len(nrow(C))) {
    cand <- C[k]
    ok <- Filter(function(r) identical(r$status, "ok"), at)
    if (length(ok)) {
      best <- order_attempts(ok)[1]
      need <- if (best$admitted) could_beat(cand, best) else
        could_admit(cand) || could_beat(cand, best)
      if (!need) next
    }
    if (remeasure && !candidate_cached(pid, cand$ept)) {
      message(sprintf("  %s: pulling %s, never pulled before, which the corrected numbers ",
                      pid, cand$ept), "make eligible to beat the selected flight")
      new_pulls <- c(new_pulls, cand$ept)
    }
    r <- pull_candidate(pid, cand, poly, p$epsg, p$polygon_area_m2, p$survey_year,
                        srs_map[[cand$ept_url]])
    r$.i <- length(at) + 1L
    at[[length(at) + 1L]] <- r
  }
  ok <- Filter(function(r) identical(r$status, "ok"), at)
  status <- if (!nrow(C)) "no_candidate" else if (length(ok)) "ok" else
    if (any(vapply(at, function(r) identical(r$status, "failed"), TRUE))) "failed" else "empty"
  sel <- if (length(ok)) at[[order_attempts(ok)$i[1]]] else NULL
  if (!is.null(sel)) {
    src <- file.path(D_CAND, sprintf("%s__%s.laz", pid, sel$ept))
    unlink(laz)
    if (!suppressWarnings(file.link(src, laz))) file.copy(src, laz, overwrite = TRUE)
  } else unlink(laz)
  s <- list(plot_id = pid, status = status, candidates = as.list(C$ept),
            selected = if (is.null(sel)) NULL else sel$ept,
            attempts = lapply(at, function(r) { r$.i <- NULL; r }), written_utc = now_utc())
  if (remeasure) s$remeasure <- list(utc = now_utc(), new_pulls = as.list(new_pulls))
  to_json(s, side)
  s
}

step_flights <- function() {
  pl <- read_catalog()$plots
  plots <- read_pid(file.path(D_PRE, "plots.csv"))
  pl$survey_year <- plots$survey_year[match(pl$plot_id, plots$plot_id)]
  ept <- st_read(file.path(D_IDX, "resources.geojson"), quiet = TRUE)
  wesm <- fread(file.path(D_IDX, "WESM.csv"), colClasses = "character")
  cand <- ofo_ept_candidates(pl, ept, wesm)
  R <- ofo_rank_flights(cand)
  setcolorder(R, c("plot_id", "project_name", "ept", "ept_url", "workunit", "ql",
                   "collect_start", "collect_end", "gap_window_years"))
  put(R[order(plot_id, rank, ept, na.last = TRUE)], file.path(D_PRE, "ept_candidates.csv"))
  un <- unique(R[wesm_rule != "workunit", .(ept, wesm_rule, workunit, ql)])
  if (nrow(un)) { message("Entwine names resolved by fallback:"); print(un) }

  todo <- plots[project_name != NEON_PROJECT, plot_id]
  if (!is.null(sel)) todo <- intersect(todo, sel)
  urls <- unique(R[plot_id %in% todo & !is.na(rank), ept_url])
  srs_map <- as.list(ept_srs(urls))
  plots_sha <- ofo_sha256(D_PRE, "plots.csv")
  f_old <- file.path(D_PRE, "flights.csv")
  old <- if (remeasure && file.exists(f_old)) read_pid(f_old) else NULL
  message(sprintf("flights: %d plots, %d resources, %d cores%s", length(todo), length(urls),
                  cores, if (remeasure) ", re-measuring the stored clouds" else ""))
  res <- parallel::mclapply(todo, function(pid) {
    tryCatch(process_plot(pid, R, plots, srs_map, remeasure), error = function(e)
      list(plot_id = pid, status = "failed", msg = conditionMessage(e)))
  }, mc.cores = cores, mc.preschedule = FALSE)
  bad <- Filter(function(s) !is.null(s$msg), res)
  for (s in bad) message("  ", s$plot_id, " failed: ", s$msg)
  if (remeasure && length(bad)) stop("Re-measure failed for ", length(bad), " plots")
  Fl <- assemble_flights(plots[plot_id %in% todo], R)
  pulls <- unlist(lapply(res, function(s) if (length(s$remeasure$new_pulls))
    sprintf("%s:%s", s$plot_id, unlist(s$remeasure$new_pulls))))
  ofo_write_record(ofo_stage_record(
    "catalog flights", D_PRE, plots_sha, c("flights.csv", "clouds.csv", "ept_candidates.csv"),
    list(plots = if (is.null(sel)) "all" else sel, remeasure = remeasure,
         new_pulls = as.list(pulls))), file.path(D_PRE, "flights_record.json"))
  if (!is.null(old)) report_remeasure(old, Fl, pulls)
}

# What a re-measure changed: new pulls, selected flights, admission and reasons.
report_remeasure <- function(old, new, pulls) {
  cat(sprintf("\n== re-measure: %d new pull(s)%s\n", length(pulls),
              if (length(pulls)) paste0(": ", paste(pulls, collapse = ", ")) else ""))
  txt <- function(v) { v <- as.character(v); v[is.na(v)] <- ""; v }
  m <- merge(old[, .(plot_id, ept_old = txt(ept), adm_old = as.logical(flight_admitted),
                     why_old = txt(flight_reason))],
             new[, .(plot_id, ept_new = txt(ept), adm_new = as.logical(flight_admitted),
                     why_new = txt(flight_reason))], by = "plot_id")
  ch <- m[ept_old != ept_new | adm_old != adm_new | why_old != why_new]
  cat(sprintf("plots whose selected flight, admission or reason changed: %d\n", nrow(ch)))
  if (nrow(ch)) print(ch, row.names = FALSE)
}

# flights.csv and clouds.csv from the per-plot sidecars.
assemble_flights <- function(plots, R) {
  rows <- lapply(plots$plot_id, function(pid) {
    side <- file.path(D_CLD, paste0(pid, ".json"))
    s <- if (file.exists(side)) read_json1(side) else list(status = "failed", attempts = list())
    C <- R[plot_id == pid & !is.na(rank)][order(rank)]
    best_q <- R[plot_id == pid][order(ofo_ql_num(ql))]
    at <- s$attempts
    sel <- if (!is.null(s$selected))
      Find(function(r) identical(r$ept, s$selected), at) else NULL
    top <- if (!is.null(sel)) sel else if (nrow(C)) as.list(C[1]) else
      if (nrow(best_q)) as.list(best_q[1]) else list()
    a <- admit_row(c(top, list(status = s$status)))
    data.table(
      plot_id = pid, project_name = plots[plot_id == pid, project_name],
      ept = nz(top$ept), ept_url = nz(top$ept_url), ql = nz(top$ql),
      collect_start = nz(top$collect_start), collect_end = nz(top$collect_end),
      n_candidates = nrow(C), cloud_status = s$status,
      n_points_polygon = nz(sel$n_points_polygon), n_first_polygon = nz(sel$n_first_polygon),
      dens_all = nz(sel$dens_all), dens_first = nz(sel$dens_first),
      gps_min = nz(sel$gps_min), gps_max = nz(sel$gps_max),
      flown_from = nz(sel$flown_from), flown_to = nz(sel$flown_to),
      span_days = nz(sel$span_days), flight_year = nz(sel$flight_year),
      survey_year = plots[plot_id == pid, survey_year], gap_years = nz(sel$gap_years),
      coverage_share = nz(sel$coverage_share),
      flight_admitted = a$flight_admitted, flight_reason = a$flight_reason,
      workunit = nz(top$workunit), gap_window_years = nz(top$gap_window_years),
      selected_rank = nz(top$rank), n_pulled = length(at),
      pulled = paste(vapply(at, function(r) sprintf("%s:%s", r$ept, r$status), ""),
                     collapse = ";"),
      flight_year_to = nz(sel$flight_year_to), flown_median = nz(sel$flown_median),
      n_withheld_polygon = nz(sel$n_withheld_polygon),
      coverage_cells = nz(sel$coverage_cells), polygon_area_m2 = nz(sel$polygon_area_m2),
      flight_days = nz(sel$flight_days), withheld_share = nz(sel$withheld_share),
      n_points_polygon_raw = nz(sel$n_points_polygon_raw),
      n_flight_days = nz(sel$n_flight_days))
  })
  Fl <- rbindlist(rows, fill = TRUE)
  Fl[flown_from == "NA", flown_from := NA][flown_to == "NA", flown_to := NA]
  Fl[!is.na(flight_days) & !nzchar(flight_days), flight_days := NA]
  put(Fl, file.path(D_PRE, "flights.csv"))
  Cl <- rbindlist(lapply(plots$plot_id, function(pid) {
    side <- file.path(D_CLD, paste0(pid, ".json"))
    s <- if (file.exists(side)) read_json1(side) else list(status = "failed")
    sel <- if (!is.null(s$selected))
      Find(function(r) identical(r$ept, s$selected), s$attempts) else NULL
    f <- file.path(D_CLD, paste0(pid, ".laz"))
    data.table(plot_id = pid, path = if (!is.null(sel)) file.path("clouds", basename(f)) else NA,
               epsg = plots[plot_id == pid, epsg], n_points = nz(sel$n_points),
               n_ground = nz(sel$n_ground), xmin = nz(sel$xmin), ymin = nz(sel$ymin),
               xmax = nz(sel$xmax), ymax = nz(sel$ymax), ept = nz(sel$ept),
               ept_url = nz(sel$ept_url),
               sha256 = if (!is.null(sel) && file.exists(f)) sha256(f) else NA,
               status = s$status, n_points_raw = nz(sel$n_points_raw),
               n_withheld = nz(sel$n_withheld_cloud))
  }), fill = TRUE)
  put(Cl, file.path(D_PRE, "clouds.csv"))
  invisible(Fl)
}

# ---- geometry -------------------------------------------------------------
step_geometry <- function() {
  pl <- read_catalog()$plots
  inputs <- ofo_sha256(D_PRE, c("plots.csv", "trees.csv"))
  plots <- read_pid(file.path(D_PRE, "plots.csv"))
  trees <- read_pid(file.path(D_PRE, "trees.csv"))
  old <- suppressMessages(sf_use_s2(FALSE))
  ov <- ofo_plot_overlaps(pl[, "plot_id"], min_area = 1)
  suppressMessages(sf_use_s2(old))
  P <- copy(plots)
  P[, polygon_valid := pl$polygon_valid[match(plot_id, pl$plot_id)]]
  P[, overlaps_plots := ov[plot_id]]
  trees <- merge(trees, P[, .(plot_id, ref_floor_cm)], by = "plot_id")
  fl <- ofo_tree_flags(trees$live_dead, trees$growth_form, trees$dbh, trees$inside,
                       trees$ref_floor_cm)
  trees[, wref := fl$wref]
  G <- ofo_geometry_audit(P, trees)
  put(G, file.path(D_PRE, "geometry_audit.csv"))
  put(ofo_geometry_by_project(G, trees), file.path(D_PRE, "geometry_by_project.csv"))
  ofo_write_record(ofo_stage_record("catalog geometry", D_PRE, inputs,
                                    c("geometry_audit.csv", "geometry_by_project.csv")),
                   file.path(D_PRE, "geometry_record.json"))
}

# ---- summary --------------------------------------------------------------
summary_print <- function() {
  f <- file.path(D_PRE, "plots.csv"); if (!file.exists(f)) return(invisible())
  P <- read_pid(f)
  S <- P[, .(plots = .N, screen = paste(sprintf("%s:%d", names(table(screen)), table(screen)),
                                        collapse = " "),
             group = paste(sprintf("%s:%d", names(table(group)), table(group)), collapse = " ")),
         by = project_name]
  ff <- file.path(D_PRE, "flights.csv")
  if (file.exists(ff)) {
    Fl <- read_pid(ff)
    G <- Fl[, .(ql = paste(sprintf("%s:%d", names(table(ql)), table(ql)), collapse = " "),
                clouds = sum(cloud_status == "ok"),
                dens_all_med = round(stats::median(dens_all, na.rm = TRUE), 1),
                dens_first_med = round(stats::median(dens_first, na.rm = TRUE), 1),
                months = paste(sort(unique(na.omit(substr(flown_from, 1, 7)))), collapse = ","),
                admitted = sum(flight_admitted)), by = project_name]
    S <- merge(S, G, by = "project_name", all.x = TRUE)
  }
  cat("\n== per-project summary\n")
  fwrite(S[order(project_name)], sep = "\t", na = "")
}

t0 <- Sys.time()
if ("fetch" %in% steps) { message("== fetch"); step_fetch() }
if ("inventory" %in% steps) { message("== inventory"); step_inventory() }
if ("flights" %in% steps) { message("== flights"); step_flights() }
if ("geometry" %in% steps) { message("== geometry"); step_geometry() }
summary_print()
message(sprintf("done in %.1f min", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
