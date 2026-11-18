#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("ofo_preflight_lib.R"))
source(.find("ofo_conditions_lib.R"))

# Site conditions of the OFO preflight (docs/ofo-preflight-protocol.md,
# "Disturbance, snow and leaf-off"), one row per non-NEON plot with a 3DEP
# cloud. Disturbance compares the 3DEP canopy (TIN-normalised plot cloud,
# kept returns: classes 7 and 18 and withheld returns dropped) with the nadir
# drone canopy height model closest in time to the survey, both as the
# maximum per 5 m cell of the project-frame grid inside the plot; the drone
# model is read through GDAL /vsicurl/ for the plot window only. Snow reads
# SNODAS depth at the plot centroid on each winter flight date (flights.csv
# `flight_days`: the days with returns in the plot); leaf-off takes the
# winter-deciduous share of the plot's reference stems when any flight date
# falls in the leaf-off window. Runs no detector and scores nothing.
# Inputs (under $CLAUDE_JOB_DIR/ofo): preflight/{plots,trees,flights,clouds}.csv,
#   clouds/<plot_id>.laz, sources/ofo_drone-missions.gpkg (else read-only from
#   $CLAUDE_JOB_DIR/ofo-preflight/sources). Network: OFO drone models, NSIDC
#   SNODAS daily tars (cached under ofo/snodas).
# Outputs: ofo/preflight/conditions.csv, conditions_record.json (SHA-256 of
#   the tables read and of conditions.csv; the decision stage refuses a
#   conditions table older than its inputs), snodas_sources.json,
#   ofo/snodas/<YYYY>/SNODAS_<YYYYMMDD>.tar.
#   Rscript scripts/preflight_ofo_conditions.R [CORES=4] [PLOTS=0001,0002]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
cores <- as.integer(if (is.null(A$CORES)) 4 else A$CORES)
plots_arg <- if (is.null(A$PLOTS) || toupper(A$PLOTS) == "ALL") NULL else
  strsplit(A$PLOTS, ",", fixed = TRUE)[[1]]
suppressMessages(library(data.table))
options(lidR.progress = FALSE)

job <- .job_dir()
OFO <- file.path(job, "ofo")
pre <- file.path(OFO, "preflight")
in_files <- c("plots.csv", "trees.csv", "flights.csv", "clouds.csv")
need <- file.path(pre, in_files)
if (any(!file.exists(need))) stop("Missing catalog outputs: ",
                                  paste(need[!file.exists(need)], collapse = ", "))
in_sha <- ofo_sha256(pre, in_files)
rd <- function(f, ...) fread(file.path(pre, f), colClasses = list(character = "plot_id"), ...)
plots <- rd("plots.csv")
trees <- rd("trees.csv", select = c("plot_id", "species_code", "ref"))
flights <- fread(file.path(pre, "flights.csv"),
                 colClasses = list(character = c("plot_id", "flight_days")))
clouds <- rd("clouds.csv")
if (!"flight_days" %in% names(flights))
  stop("flights.csv has no flight_days column; rerun preflight_ofo_catalog.R STEPS=flights")

pop <- flights[cloud_status == "ok" & project_name != "NEON2023"]
if (!is.null(plots_arg)) pop <- pop[plot_id %in% plots_arg]
if (!nrow(pop)) stop("No plot with a cloud in the selection")
pop <- merge(pop[, .(plot_id, project_name, flown_from = as.Date(flown_from),
                     flown_to = as.Date(flown_to), flight_year, flight_days)],
             plots[, .(plot_id, epsg, polygon_wkt, survey_date = as.Date(survey_date),
                       survey_year)], by = "plot_id", all.x = TRUE)
pop <- merge(pop, clouds[, .(plot_id, cloud_path = path)], by = "plot_id", all.x = TRUE)
if (anyNA(pop$polygon_wkt)) stop("Plots without a polygon: ",
                                 paste(pop[is.na(polygon_wkt), plot_id], collapse = ","))
pop[, laz := file.path(OFO, cloud_path)]
gone <- pop[is.na(cloud_path) | !file.exists(laz), plot_id]
if (length(gone)) stop("Cloud files missing for plots: ", paste(gone, collapse = ","))
setorder(pop, plot_id)

mpath <- Find(file.exists, c(file.path(OFO, "sources", "ofo_drone-missions.gpkg"),
                             file.path(job, "ofo-preflight", "sources",
                                       "ofo_drone-missions.gpkg")))
if (!length(mpath)) stop("ofo_drone-missions.gpkg not found")
missions <- sf::st_read(mpath, quiet = TRUE)
message(sprintf("%d plots, missions from %s", nrow(pop), mpath))

# Window reads only: no directory listing, retries on transient HTTP errors.
Sys.setenv(GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR", CPL_VSIL_CURL_ALLOWED_EXTENSIONS = ".tif",
           GDAL_HTTP_MAX_RETRY = "4", GDAL_HTTP_RETRY_DELAY = "3", GDAL_HTTP_TIMEOUT = "120")

# ---- Disturbance --------------------------------------------------------------

# 3DEP canopy: the plot cloud's kept returns normalised with a TIN of their
# class-2 points, heights in [0, 110] m, maximum per grid cell.
dep_surface <- function(laz, cells, epsg) {
  las <- suppressMessages(ofo_read_las(laz, "xyzc"))
  if (lidR::is.empty(las)) stop("empty cloud")
  cep <- sf::st_crs(las)$epsg
  if (!is.na(cep) && cep != epsg) stop(sprintf("cloud EPSG %d, project frame %d", cep, epsg))
  if (!any(las$Classification == 2L)) stop("no class-2 ground points")
  las <- suppressMessages(suppressWarnings(
    lidR::normalize_height(las, lidR::tin(), use_class = 2L)))
  k <- las$Z >= OFO_HMIN & las$Z <= OFO_HMAX
  ofo_cell_max(las$X[k], las$Y[k], las$Z[k], cells)
}

# Drone canopy: the plot window of the model, its CRS and units read from the
# file, pixel centres carried to the project frame, maximum per grid cell.
drone_surface <- function(mission_id, poly, cells, epsg) {
  url <- ofo_chm_url(mission_id)
  r <- terra::rast(paste0("/vsicurl/", url))
  sc <- sf::st_crs(terra::crs(r))
  if (is.na(sc)) stop("model has no CRS")
  if (!identical(sc$units_gdal, "metre")) stop("model CRS units: ", sc$units_gdal)
  zu <- terra::units(r)[1]
  bb <- sf::st_bbox(sf::st_buffer(sf::st_transform(poly, sc), 2 * OFO_CELL))
  e <- terra::ext(bb[["xmin"]], bb[["xmax"]], bb[["ymin"]], bb[["ymax"]])
  if (is.null(tryCatch(terra::intersect(terra::ext(r), e), error = function(e) NULL)))
    return(NULL)
  w <- terra::crop(r, e, snap = "out")
  v <- terra::values(w, mat = FALSE)
  ok <- which(!is.na(v))
  if (!length(ok)) return(NULL)
  xy <- terra::xyFromCell(w, ok)
  if (is.na(sc$epsg) || sc$epsg != epsg)
    xy <- sf::sf_project(from = sc, to = sf::st_crs(epsg), pts = xy)
  z <- ofo_cell_max(xy[, 1], xy[, 2], v[ok], cells)
  list(z = z, url = url, epsg = sc$epsg, xy_unit = sc$units_gdal,
       z_unit = if (is.na(zu) || !nzchar(zu)) "unstated" else zu,
       res_m = terra::res(r)[1], max_m = max(v[ok]))
}

disturb_one <- function(r) {
  lidR::set_lidr_threads(1L)
  data.table::setDTthreads(1L)
  poly <- sf::st_as_sfc(r$polygon_wkt, crs = r$epsg)
  cells <- ofo_plot_cells(poly)
  covers <- ofo_missions_covering(missions, poly)
  cand <- ofo_mission_candidates(sf::st_drop_geometry(missions), covers, r$survey_date)
  out <- list(plot_id = r$plot_id, n_plot_cells = nrow(cells),
              n_missions_covering = sum(covers), n_candidates = nrow(cand))
  dep <- tryCatch(dep_surface(r$laz, cells, r$epsg), error = function(e) e)
  if (inherits(dep, "error")) {
    out$note <- paste("3dep surface:", conditionMessage(dep))
    return(out)
  }
  # A model is usable when it is readable and shares at least one cell with
  # the 3DEP surface.
  reader <- function(id) {
    d <- drone_surface(id, poly, cells, r$epsg)
    if (is.null(d) || !any(!is.na(d$z) & !is.na(dep))) return(NULL)
    d
  }
  ch <- ofo_choose_mission(cand, reader)
  out$missions_tried <- paste(ch$tried, collapse = ";")
  if (length(ch$errors))
    out$read_errors <- paste(sprintf("%s: %s", names(ch$errors), ch$errors), collapse = " | ")
  if (is.null(ch$row)) return(out)
  d <- ch$surface
  drone_first <- ch$row$mission_date < r$flown_from
  sh <- if (drone_first) ofo_change_shares(d$z, dep) else ofo_change_shares(dep, d$z)
  c(out, list(mission_id = ch$row$mission_id, mission_date = format(ch$row$mission_date),
              mission_pitch = ch$row$pitch, chm_url = d$url,
              early_surface = if (drone_first) "drone" else "3dep",
              n_compared = sh$n_compared, n_canopy_cells_early = sh$n_canopy_early,
              n_canopy_cells_late = sh$n_canopy_late, loss_share = sh$loss_share,
              reverse_share = sh$reverse_share, chm_epsg = d$epsg, chm_xy_unit = d$xy_unit,
              chm_z_unit = d$z_unit, chm_res_m = d$res_m, chm_max_m = d$max_m))
}

rows <- split(pop, seq_len(nrow(pop)))
res <- parallel::mclapply(rows, function(r) {
  t0 <- Sys.time()
  o <- tryCatch(disturb_one(r), error = function(e)
    list(plot_id = r$plot_id, note = paste("error:", conditionMessage(e))))
  message(sprintf("%s %s %.0fs", r$plot_id, if (is.null(o$mission_id)) "no model" else
    o$mission_id, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  o
}, mc.cores = cores, mc.preschedule = FALSE)
bad <- vapply(res, function(x) !is.list(x) || is.null(x$plot_id), logical(1))
if (any(bad)) stop("Disturbance workers failed for plots: ",
                   paste(pop$plot_id[bad], collapse = ","))
dist <- rbindlist(lapply(res, as.data.table), fill = TRUE)
chr <- c("mission_id", "mission_date", "chm_url", "early_surface", "missions_tried",
         "read_errors", "note", "chm_xy_unit", "chm_z_unit")
num <- c("mission_pitch", "n_compared", "n_canopy_cells_early", "n_canopy_cells_late",
         "loss_share", "reverse_share", "chm_epsg", "chm_res_m", "chm_max_m")
for (col in setdiff(chr, names(dist))) dist[, (col) := NA_character_]
for (col in setdiff(num, names(dist))) dist[, (col) := NA_real_]
D <- merge(pop, dist, by = "plot_id", all.x = TRUE)
setorder(D, plot_id)
D[, check_failed := !is.na(note)]
D[, disturbance_status := ofo_disturbance_status(!is.na(mission_id), loss_share,
                                                 reverse_share)]
D[, interval_covered := ofo_interval_covered(as.Date(mission_date), survey_date, flown_from)]
D[, same_year := !is.na(flight_year) & !is.na(survey_year) & flight_year == survey_year]
D[, disturbance_admitted := ofo_disturbance_admitted(disturbance_status, interval_covered,
                                                     flight_year, survey_year, check_failed)]

# ---- Flight dates, snow and leaf-off windows -------------------------------------

fdates <- lapply(D$flight_days, ofo_flight_dates)
# flown_from / flown_to are the first and last flight dates.
ends <- vapply(seq_along(fdates), function(i) {
  d <- fdates[[i]]
  !length(d) || (isTRUE(min(d) == D$flown_from[i]) && isTRUE(max(d) == D$flown_to[i]))
}, logical(1))
if (!all(ends)) stop("flight_days disagrees with flown_from/flown_to for plots: ",
                     paste(D$plot_id[!ends], collapse = ","))
sdates <- lapply(fdates, ofo_snow_dates)
known <- lengths(fdates) > 0
D[, snow_window := lengths(sdates) > 0]
D[, snow_dates_checked := vapply(sdates, function(d) paste(format(d), collapse = ";"),
                                 character(1))]
# Unknown flight dates cannot rule either window out.
D[, leafoff_window := ifelse(known, vapply(fdates, ofo_leafoff_window, logical(1)), NA)]
cent <- t(vapply(seq_len(nrow(D)), function(i) {
  p <- sf::st_centroid(sf::st_as_sfc(D$polygon_wkt[i], crs = D$epsg[i]))
  sf::st_coordinates(sf::st_transform(p, 4326))[1, 1:2]
}, numeric(2)))
D[, `:=`(centroid_lon = cent[, 1], centroid_lat = cent[, 2])]

# ---- SNODAS ---------------------------------------------------------------------

snow_dir <- file.path(OFO, "snodas")
src_json <- file.path(pre, "snodas_sources.json")
prior <- if (file.exists(src_json)) tryCatch(jsonlite::fromJSON(src_json)$files,
                                             error = function(e) NULL)
# Cache one daily tar; a partial download never reaches the cache name.
fetch_snodas <- function(d) {
  url <- snodas_url(d)
  path <- file.path(snow_dir, format(d, "%Y"), basename(url))
  rel <- substring(path, nchar(OFO) + 2)
  when <- NA_character_
  if (!file.exists(path)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    part <- paste0(path, ".part")
    ok <- tryCatch({ curl::curl_download(url, part, quiet = TRUE); TRUE },
                   error = function(e) conditionMessage(e))
    if (!isTRUE(ok)) {
      unlink(part)
      return(list(date = format(d), url = url, file = rel, status = "unavailable",
                  error = ok))
    }
    file.rename(part, path)
    when <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }
  sha <- digest::digest(file = path, algo = "sha256")
  if (is.na(when)) {
    hit <- if (is.data.frame(prior) && all(c("file", "sha256") %in% names(prior)))
      which(prior$file == rel & prior$sha256 == sha) else integer()
    when <- if (length(hit)) prior$retrieved_utc[hit[1]] else
      paste(format(file.mtime(path), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "(file time)")
  }
  list(date = format(d), url = url, file = rel, status = "ok",
       bytes = file.size(path), sha256 = sha, retrieved_utc = when)
}

# Real-data check of the reader before it is trusted: 15 March 2023, a record
# Sierra snowpack, at the Central Sierra Snow Lab (deep snow) and in
# Sacramento (none).
sanity_date <- as.Date("2023-03-15")
sanity_pts <- data.frame(place = c("Central Sierra Snow Lab, Donner Pass", "Sacramento"),
                         lon = c(-120.3676, -121.4944), lat = c(39.3256, 38.5816),
                         expect = c("depth > 1 m", "depth 0"))
plot_dates <- sort(unique(as.Date(unlist(lapply(sdates, format)))))
all_dates <- sort(unique(c(sanity_date, plot_dates)))
srcs <- parallel::mclapply(as.list(all_dates), function(d)
  tryCatch(fetch_snodas(d), error = function(e)
    list(date = format(d), url = snodas_url(d), status = "unavailable",
         error = conditionMessage(e))), mc.cores = min(cores, 4))
names(srcs) <- format(all_dates)
read_depths <- function(d, lon, lat) {
  s <- srcs[[format(d)]]
  if (!is.list(s) || !identical(s$status, "ok")) return(rep(NA_real_, length(lon)))
  tryCatch(snodas_depth_from_tar(file.path(OFO, s$file), lon, lat),
           error = function(e) {
             message("SNODAS ", format(d), ": ", conditionMessage(e))
             rep(NA_real_, length(lon))
           })
}
sanity_pts$depth_m <- read_depths(sanity_date, sanity_pts$lon, sanity_pts$lat)
sanity_pass <- if (anyNA(sanity_pts$depth_m)) NA else
  sanity_pts$depth_m[1] > 1 && sanity_pts$depth_m[2] == 0
if (isFALSE(sanity_pass)) stop("SNODAS reader failed its real-data check")
message(sprintf("SNODAS check %s: %s", format(sanity_date),
                paste(sprintf("%s %.3f m", sanity_pts$place, sanity_pts$depth_m),
                      collapse = "; ")))

depths <- vector("list", nrow(D))
for (d in format(plot_dates)) {
  idx <- which(vapply(sdates, function(x) d %in% format(x), logical(1)))
  v <- read_depths(as.Date(d), D$centroid_lon[idx], D$centroid_lat[idx])
  for (k in seq_along(idx)) depths[[idx[k]]] <- c(depths[[idx[k]]], setNames(v[k], d))
}
snow_st <- vapply(seq_len(nrow(D)), function(i) {
  if (!known[i]) return("unknown")
  ofo_snow_status(D$snow_window[i], unname(depths[[i]]))
}, character(1))
D[, snow_status := snow_st]
D[, snow_depth_max_m := vapply(depths, function(v)
  if (!length(v) || all(is.na(v))) NA_real_ else max(v, na.rm = TRUE), numeric(1))]
D[, snow_depths := vapply(depths, function(v)
  paste(sprintf("%s:%s", names(v), ifelse(is.na(v), "NA", format(v))), collapse = ";"),
  character(1))]

jsonlite::write_json(list(
  dataset = "NSIDC G02158 SNODAS, masked, daily; product 1036 (snow depth)",
  base_url = OFO_SNODAS_BASE,
  sanity_check = list(date = format(sanity_date), points = sanity_pts,
                      passed = sanity_pass),
  files = unname(srcs)), src_json, auto_unbox = TRUE, pretty = TRUE, na = "null",
  digits = NA)

# ---- Leaf-off -------------------------------------------------------------------

lt <- trees[plot_id %in% D$plot_id]
lt[, ref := as.logical(ref)]
lo <- lt[, .(deciduous_share = ofo_deciduous_share(species_code, ref),
             n_ref = sum(ref %in% TRUE),
             n_ref_deciduous = sum(ref %in% TRUE & species_code %in% OFO_WINTER_DECIDUOUS),
             n_ref_unidentified = sum(ref %in% TRUE & (is.na(species_code) |
               species_code %in% c("", "UNK or UNCL")))), by = plot_id]
D <- merge(D, lo, by = "plot_id", all.x = TRUE)
D[is.na(n_ref), `:=`(n_ref = 0L, n_ref_deciduous = 0L, n_ref_unidentified = 0L)]
D[, leafoff_status := ofo_leafoff_status(is.na(leafoff_window) | leafoff_window,
                                          deciduous_share)]

# ---- Admission and output -------------------------------------------------------

D[, conditions_admitted := ofo_conditions_admitted(disturbance_admitted, snow_status,
                                                    leafoff_status)]
D[, conditions_reason := ofo_conditions_reason(disturbance_status, disturbance_admitted,
                                                snow_status, leafoff_status, check_failed)]
cols <- c("plot_id", "project_name", "mission_id", "mission_date", "mission_pitch", "chm_url",
          "n_canopy_cells_early", "loss_share", "reverse_share", "interval_covered",
          "disturbance_status", "same_year", "disturbance_admitted", "snow_window",
          "snow_dates_checked", "snow_depth_max_m", "snow_status", "deciduous_share",
          "leafoff_window", "leafoff_status", "conditions_admitted", "conditions_reason",
          # extras
          "survey_date", "survey_year", "flown_from", "flown_to", "flight_year", "flight_days",
          "early_surface", "n_plot_cells", "n_compared", "n_canopy_cells_late",
          "n_missions_covering", "n_candidates", "missions_tried", "read_errors",
          "chm_epsg", "chm_xy_unit", "chm_z_unit", "chm_res_m", "chm_max_m",
          "centroid_lon", "centroid_lat", "snow_depths", "n_ref", "n_ref_deciduous",
          "n_ref_unidentified", "check_failed", "note")
out <- D[, ..cols]
setorder(out, plot_id)
# The inputs must not have moved under the run.
now_sha <- ofo_sha256(pre, in_files)
if (!identical(now_sha, in_sha))
  stop("Inputs changed during the run: ", paste(in_files[now_sha != in_sha], collapse = ", "))
fwrite(out, file.path(pre, "conditions.csv"))
ofo_write_record(ofo_stage_record("conditions", pre, in_sha, "conditions.csv",
                                  list(plots = if (is.null(plots_arg)) "all" else plots_arg)),
                 file.path(pre, "conditions_record.json"))
message(sprintf("Wrote %s (%d plots; %d admitted)", file.path(pre, "conditions.csv"),
                nrow(out), sum(out$conditions_admitted)))
print(out[, .N, by = .(disturbance_status, snow_status, leafoff_status, conditions_admitted)])
