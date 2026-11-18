#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)

# Public lidar collections over OFO plots without an admitted 3DEP flight
# (docs/ofo-preflight-protocol.md, "Plots outside the public 3DEP clouds"),
# from metadata only: no point cloud is read or downloaded. For the plots of
# PROJECTS (default SSMT2024, OHDS2024) it queries the footprint services of
# four sources with the plot polygon and tests coverage locally:
#   usgs_3dep_lpc  3DEP work-unit footprints (3DEP Elevation Index, layer
#                  "Lidar Point Cloud") and LPC tiles from the TNM Access API;
#   wa_dnr         Washington Lidar Portal: its own area query (tiles
#                  intersecting the plot) and hillshade pixels at plot points;
#   or_dogami      DOGAMI lidar project-area polygons (OLC and other);
#   noaa_dc        NOAA Digital Coast (Data Access Viewer) lidar footprints,
#                  the dataset tile index, and the InPort metadata record.
# A row is "verified" when coverage was established against a footprint, tile
# index or data raster; otherwise it is a lead.
# Inputs (under $CLAUDE_JOB_DIR/ofo): preflight/plots.csv, preflight/flights.csv
#   (else the 16 November table work/ofo-preflight/derived/
#   ofo_pairing_consolidated.csv picks the plots), lidar-index/resources.geojson.
# Outputs: ofo/preflight/state_lidar.csv, ofo/preflight/state_lidar_sources.json
#   Rscript scripts/preflight_ofo_state_lidar.R [PROJECTS=SSMT2024,OHDS2024] [PLOTS=...]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
projects <- strsplit(if (is.null(A$PROJECTS)) "SSMT2024,OHDS2024" else A$PROJECTS, ",")[[1]]
plots_arg <- if (is.null(A$PLOTS)) NULL else strsplit(A$PLOTS, ",", fixed = TRUE)[[1]]
suppressMessages(library(data.table))
sf::sf_use_s2(TRUE)

job <- .job_dir()
OFO <- file.path(job, "ofo")
pre <- file.path(OFO, "preflight")
rd <- function(f) fread(f, colClasses = list(character = "plot_id"))
plots <- rd(file.path(pre, "plots.csv"))[project_name %in% projects]

# Population: plots of these projects without an admitted flight.
fl_path <- file.path(pre, "flights.csv")
fl <- if (file.exists(fl_path)) rd(fl_path)[project_name %in% projects] else NULL
if (!is.null(fl) && all(plots$plot_id %in% fl$plot_id)) {
  pop_src <- "ofo/preflight/flights.csv"
  pop <- plots[!plot_id %in% fl[flight_admitted %in% TRUE, plot_id]]
  pop <- merge(pop, fl[, .(plot_id, flight_ept = ept, flight_ql = ql, flight_year,
                           flight_reason)], by = "plot_id", all.x = TRUE)
} else {
  pop_src <- "ofo-preflight/derived/ofo_pairing_consolidated.csv (16 November)"
  old <- rd(file.path(job, "ofo-preflight", "derived", "ofo_pairing_consolidated.csv"))
  ok <- old[has %in% TRUE & ql %in% c("QL 0", "QL 1") & abs(fy - yr) <= 4, plot_id]
  pop <- plots[!plot_id %in% ok]
  pop <- merge(pop, old[, .(plot_id, flight_ept = ept, flight_ql = ql, flight_year = fy,
                            flight_reason = NA_character_)], by = "plot_id", all.x = TRUE)
}
if (!is.null(plots_arg)) pop <- pop[plot_id %in% plots_arg]
setorder(pop, plot_id)
message(sprintf("%d plots from %s", nrow(pop), pop_src))

# ---- HTTP with a provenance log ---------------------------------------------------

LOG <- new.env()
LOG$req <- list()
http <- function(url, query = NULL, post = NULL, what = "", timeout = 90) {
  if (length(query)) url <- paste0(url, "?", paste(names(query),
    vapply(query, function(v) curl::curl_escape(as.character(v)), ""), sep = "=", collapse = "&"))
  h <- curl::new_handle(timeout = timeout, connecttimeout = 20,
                        useragent = "ofo-preflight (R curl)")
  t0 <- Sys.time()
  on.exit(if (as.numeric(difftime(Sys.time(), t0, units = "secs")) > 20)
    message(sprintf("  slow request (%.0fs): %s", as.numeric(difftime(Sys.time(), t0,
                                                                       units = "secs")), what)))
  if (!is.null(post)) {
    body <- paste(names(post), vapply(post, curl::curl_escape, ""), sep = "=", collapse = "&")
    curl::handle_setopt(h, postfields = body)
    curl::handle_setheaders(h, "Content-Type" = "application/x-www-form-urlencoded")
  }
  r <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) e)
  rec <- list(what = what, url = url, method = if (is.null(post)) "GET" else "POST",
              post = post, retrieved_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  if (inherits(r, "error")) {
    rec$error <- conditionMessage(r)
    LOG$req[[length(LOG$req) + 1]] <- rec
    return(NULL)
  }
  rec$status <- r$status_code
  rec$bytes <- length(r$content)
  rec$sha256 <- digest::digest(r$content, algo = "sha256", serialize = FALSE)
  LOG$req[[length(LOG$req) + 1]] <- rec
  if (r$status_code >= 400) return(NULL)
  rawToChar(r$content)
}
json <- function(txt) if (is.null(txt)) NULL else
  tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
geojson_sf <- function(txt) {
  if (is.null(txt) || !grepl("FeatureCollection", substr(txt, 1, 200), fixed = TRUE)) return(NULL)
  g <- tryCatch(sf::st_read(txt, quiet = TRUE), error = function(e) NULL)
  if (is.null(g) || !nrow(g)) NULL else g
}

# ArcGIS layer query by the plot envelope, geometry returned in WGS 84.
arcgis <- function(layer_url, bb, fields = "*", where = "1=1", what = "") {
  geojson_sf(http(paste0(layer_url, "/query"), list(
    where = where, geometry = paste(bb, collapse = ","), geometryType = "esriGeometryEnvelope",
    inSR = 4326, outSR = 4326, spatialRel = "esriSpatialRelIntersects", outFields = fields,
    returnGeometry = "true", geometryPrecision = 7, f = "geojson"), what = what))
}

# Coverage of the plot polygon by footprints: covers, partial or none.
# Tested in the plot's project frame with GEOS: some published footprints have
# crossing rings that the spherical (s2) engine rejects.
FRAME <- NA_integer_
coverage <- function(fp, poly) {
  if (is.null(fp) || !length(fp)) return("none")
  tryCatch({
    pf <- sf::st_transform(poly, FRAME)
    u <- sf::st_union(sf::st_make_valid(sf::st_transform(sf::st_geometry(fp), FRAME)))
    if (isTRUE(sf::st_covers(u, pf, sparse = FALSE)[1, 1])) "covers" else
      if (isTRUE(sf::st_intersects(u, pf, sparse = FALSE)[1, 1])) "partial" else "none"
  }, error = function(e) paste("error:", conditionMessage(e)))
}
yrs <- function(...) {
  y <- unlist(regmatches(paste(..., collapse = " "),
                         gregexpr("(19|20)[0-9]{2}", paste(..., collapse = " "))))
  paste(sort(unique(y)), collapse = ";")
}
ms_date <- function(v) if (is.null(v) || is.na(v)) NA_character_ else
  format(as.POSIXct(as.numeric(v) / 1000, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d")
row <- function(...) as.data.table(list(...))

# ---- Static lookups ---------------------------------------------------------------

res_path <- Find(file.exists, c(file.path(OFO, "lidar-index", "resources.geojson"),
                                file.path(job, "ofo-preflight", "lidar-index",
                                          "resources.geojson")))
ept_res <- sf::st_read(res_path, quiet = TRUE)
wadnr_projects <- json(http("https://lidarportal.dnr.wa.gov/project", what = "wa_dnr projects"))
wadnr_layer <- list()   # hillshade raster layer name -> project, dataset kind
for (p in wadnr_projects) for (d in p$datasets)
  if (!is.null(d$layers)) for (l in strsplit(d$layers, ",")[[1]])
    wadnr_layer[[l]] <- list(project = p$name, dataset = d$name)

WESM_LAYER <- paste0("https://index.nationalmap.gov/arcgis/rest/services/",
                     "3DEPElevationIndex/MapServer/8")
DOGAMI <- paste0("https://gis.dogami.oregon.gov/arcgis/rest/services/lidar/",
                 "DOGAMI_Lidar_Project_Status/MapServer")
WADNR_HS <- "https://lidarportal.dnr.wa.gov/arcgis/rest/services/lidar/wadnr_hillshade/MapServer"
DOGAMI_LAYERS <- c(`0` = "In progress OLC lidar projects", `1` = "Completed OLC lidar projects",
                   `2` = "Other completed lidar projects (non-OLC)",
                   `3` = "Other In progress (non-OLC)")
DAV <- "https://coast.noaa.gov/arcgis/rest/services/DAV/DAV_footprints/MapServer/0"
NOAA_S3 <- "https://noaa-nos-coastal-lidar-pds.s3.amazonaws.com"

LIC <- list(
  usgs = "USGS 3DEP: public domain, no use restrictions (credit U.S. Geological Survey)",
  wadnr = paste("No licence stated on the portal; WA DNR 'Disclaimers and Citation",
                "Guidelines' (dnr.wa.gov/node/118): free for any use if the original",
                "dataset and the portal are cited; no warranty"),
  dogami = paste("DOGAMI lidar is public domain, reference DOGAMI (data.gov listing",
                 "'Oregon Department of Geology and Mineral Industries Lidar Program Data');",
                 "point clouds are not served by the Lidar Data Viewer"))

# ---- Per-plot queries -------------------------------------------------------------

usgs_rows <- function(p, poly, bb) {
  out <- list()
  wu <- arcgis(WESM_LAYER, bb, paste("workunit,workunit_id,project,collect_start,collect_end,ql",
                                     "spec,lpc_category,lpc_reason,lpc_link,metadata_link",
                                     sep = ","), what = sprintf("%s 3dep workunits", p$plot_id))
  tnm <- json(http("https://tnmaccess.nationalmap.gov/api/v1/products", list(
    datasets = "Lidar Point Cloud (LPC)", bbox = paste(bb, collapse = ","), max = 500,
    outputFormat = "JSON"), what = sprintf("%s tnm lpc tiles", p$plot_id)))
  tiles <- if (is.null(tnm)) list() else tnm$items
  tdt <- rbindlist(lapply(tiles, function(t) {
    u <- t$downloadLazURL %||% t$downloadURL
    folder <- sub("^.*/Projects/(.*)/(laz|LAZ)/[^/]+$", "\\1", u)
    data.table(title = t$title, url = u, folder = folder,
               workunit = sub("^USGS_LPC_", "", basename(folder)),
               xmin = t$boundingBox$minX, xmax = t$boundingBox$maxX,
               ymin = t$boundingBox$minY, ymax = t$boundingBox$maxY)
  }))
  wus <- unique(c(if (!is.null(wu)) wu$workunit, if (nrow(tdt)) tdt$workunit))
  for (w in wus) {
    f <- if (!is.null(wu)) wu[wu$workunit == w, ] else NULL
    cov_fp <- if (!is.null(f) && nrow(f)) coverage(sf::st_geometry(f), poly) else NA
    tw <- if (nrow(tdt)) tdt[workunit == w] else tdt
    cov_tile <- if (nrow(tw)) coverage(do.call(c, lapply(seq_len(nrow(tw)), function(i)
      sf::st_as_sfc(sf::st_bbox(c(xmin = tw$xmin[i], ymin = tw$ymin[i], xmax = tw$xmax[i],
                                  ymax = tw$ymax[i]), crs = 4326)))), poly) else NA
    # Entwine names add prefixes and suffixes to the work unit (for example
    # USGS_LPC_WA_Olympic_Peninsula_2013_LAS_2015), so match by containment.
    has_ept <- grepl(w, ept_res$name, fixed = TRUE) |
      ept_res$name %in% (if (nrow(tw)) basename(tw$folder) else character())
    ept_cov <- if (any(has_ept)) coverage(sf::st_geometry(ept_res[has_ept, ]), poly) else NA
    a <- if (!is.null(f) && nrow(f)) sf::st_drop_geometry(f)[1, ] else NULL
    basis <- c(if (!is.na(cov_fp)) sprintf("3DEP work-unit footprint: %s", cov_fp),
               if (!is.na(cov_tile)) sprintf("TNM LPC tile bounding boxes (%d tiles): %s",
                                             nrow(tw), cov_tile))
    cov <- if (identical(cov_tile, "covers") || identical(cov_fp, "covers")) "covers" else
      if ("partial" %in% c(cov_fp, cov_tile)) "partial" else "none"
    out[[length(out) + 1]] <- row(
      source = "usgs_3dep_lpc", collection = w,
      collection_detail = if (!is.null(a)) a$project else NA_character_,
      acquisition_years = if (!is.null(a)) yrs(ms_date(a$collect_start), ms_date(a$collect_end))
        else yrs(w),
      acquisition_dates = if (!is.null(a)) paste(ms_date(a$collect_start), ms_date(a$collect_end),
                                                  sep = "/") else NA_character_,
      density_or_ql = if (!is.null(a)) paste0(a$ql, if (!is.null(a$spec) && !is.na(a$spec))
        paste0(" (", a$spec, ")")) else NA_character_,
      access_route = if (nrow(tw)) paste0("TNM LAZ tiles, e.g. ", tw$url[1]) else
        if (!is.null(a) && !is.na(a$lpc_link)) a$lpc_link else "no LPC tiles listed",
      lpc_status = if (!is.null(a)) paste(a$lpc_category, a$lpc_reason, sep = ": ") else NA,
      entwine_resource = if (any(has_ept)) paste(ept_res$name[has_ept], collapse = ";") else
        "none",
      entwine_covers = ept_cov, n_tiles = nrow(tw), licence_terms = LIC$usgs,
      coverage = cov, verified = cov %in% c("covers", "partial"),
      coverage_basis = paste(basis, collapse = "; "))
  }
  rbindlist(out, fill = TRUE)
}

wadnr_rows <- function(p, poly, pts) {
  # Exterior ring of the (first) plot polygon.
  cc <- sf::st_coordinates(poly)
  ring <- cc[cc[, "L1"] == 1 & cc[, ncol(cc)] == 1, 1:2, drop = FALSE]
  gj <- jsonlite::toJSON(list(type = "Polygon", coordinates = list(unname(ring))),
                         auto_unbox = TRUE, digits = 6)
  q <- json(http("https://lidarportal.dnr.wa.gov/query", post = list(geojson = gj),
                 what = sprintf("%s wa_dnr area query", p$plot_id)))
  if (is.null(q) || !length(q)) return(NULL)
  qd <- rbindlist(lapply(q, function(x) data.table(project = x$project_name,
    dataset = x$dataset_name, dataset_id = x$dataset_id, files = x$files, bytes = x$bytes)))
  # Pixel check: hillshade value (not NoData) at the centroid and boundary
  # points. The identify service intermittently answers with no layers at all
  # or times out, so it is retried and only answered points count.
  hits <- rbindlist(lapply(seq_len(nrow(pts)), function(i) {
    for (k in 1:3) {
      ident <- json(http(paste0(WADNR_HS, "/identify"),
        list(geometry = sprintf("%.7f,%.7f", pts[i, 1], pts[i, 2]),
             geometryType = "esriGeometryPoint", sr = 4326, layers = "all", tolerance = 0,
             mapExtent = sprintf("%.6f,%.6f,%.6f,%.6f", pts[i, 1] - 0.01, pts[i, 2] - 0.01,
                                 pts[i, 1] + 0.01, pts[i, 2] + 0.01),
             imageDisplay = "400,400,96", returnGeometry = "false", f = "json"),
        what = sprintf("%s wa_dnr hillshade identify %d try %d", p$plot_id, i, k),
        timeout = 30))
      if (!is.null(ident) && length(ident$results)) break
    }
    if (is.null(ident) || !length(ident$results)) return(NULL)
    rbindlist(lapply(ident$results, function(r) {
      m <- wadnr_layer[[r$layerName]]
      if (is.null(m)) return(NULL)
      v <- r$attributes[["Stretch.Pixel Value"]] %||% r$attributes[["Pixel Value"]]
      data.table(pt = i, project = m$project, dataset = m$dataset,
                 data = !is.null(v) && !identical(v, "NoData"))
    }))
  }), fill = TRUE)
  answered <- if (nrow(hits)) sort(unique(hits$pt)) else integer()
  rbindlist(lapply(unique(qd$project), function(pr) {
    d <- qd[project == pr]
    pc <- d[dataset == "Point Cloud"]
    md <- d[dataset == "Metadata"]
    h <- if (nrow(hits)) hits[project == pr & grepl("Hillshade", dataset)] else hits
    hs <- if (nrow(h) && any(h$dataset == "DTM Hillshade")) "DTM Hillshade" else
      if (nrow(h)) h$dataset[1] else NA_character_
    if (nrow(h)) h <- h[dataset == hs]
    share <- if (nrow(h) && length(answered)) mean(vapply(answered, function(i)
      any(h[pt == i, data]), logical(1))) else NA_real_
    cov <- if (is.na(share)) "intersects_tiles" else if (share == 1) "covers" else
      if (share > 0) "partial" else "none"
    row(source = "wa_dnr", collection = pr, collection_detail = paste(d$dataset, collapse = ";"),
        acquisition_years = yrs(pr), acquisition_dates = NA_character_,
        density_or_ql = paste0("not in the portal's queryable metadata; see the project's ",
                               "Metadata download", if (nrow(md)) sprintf(" (dataset %d)",
                               md$dataset_id[1]) else " (none listed)"),
        access_route = if (nrow(pc)) sprintf(paste0(
          "https://lidarportal.dnr.wa.gov/download?geojson=<AOI>&ids=%d (Point Cloud, %d files ",
          "intersect the plot, %.0f MB)"), pc$dataset_id[1], pc$files[1], pc$bytes[1] / 1e6)
          else "no Point Cloud dataset listed for the plot area",
        lpc_status = NA_character_, entwine_resource = NA_character_, entwine_covers = NA,
        n_tiles = if (nrow(pc)) pc$files[1] else 0L, licence_terms = LIC$wadnr,
        coverage = cov, verified = cov %in% c("covers", "partial"),
        coverage_basis = sprintf(paste0("portal area query lists %d dataset(s) with tiles ",
          "intersecting the plot; %s has data at %s of %d answered plot points ",
          "(centroid and boundary; %d asked)"), nrow(d), if (is.na(hs)) "no hillshade" else hs,
          if (is.na(share)) "NA" else format(round(share * length(answered))),
          length(answered), nrow(pts)))
  }))
}

dogami_rows <- function(p, poly, bb) {
  rbindlist(lapply(names(DOGAMI_LAYERS), function(k) {
    g <- arcgis(paste0(DOGAMI, "/", k), bb, what = sprintf("%s dogami layer %s", p$plot_id, k))
    if (is.null(g)) return(NULL)
    rbindlist(lapply(seq_len(nrow(g)), function(i) {
      a <- sf::st_drop_geometry(g)[i, , drop = FALSE]
      cov <- coverage(sf::st_geometry(g)[i], poly)
      get <- function(n) if (n %in% names(a)) as.character(a[[n]]) else NA_character_
      dens <- get("Pulse_Dens")
      row(source = "or_dogami", collection = get("Project"),
          collection_detail = paste0(DOGAMI_LAYERS[[k]], if (!is.na(get("Program")))
            paste0("; program ", get("Program"))),
          acquisition_years = yrs(get("Year"), get("ACQ_DATES"), get("Aqc_Date"), get("Project")),
          acquisition_dates = paste(na.omit(c(get("ACQ_DATES"), get("Aqc_Date"))), collapse = "; "),
          density_or_ql = if (!is.na(dens) && nzchar(dens)) paste("pulse density", dens) else
            "not stated in the project layer",
          access_route = paste("DOGAMI on request (no point-cloud download in the Lidar Data",
                               "Viewer); see noaa_dc rows for a Digital Coast copy"),
          lpc_status = NA_character_, entwine_resource = NA_character_, entwine_covers = NA,
          n_tiles = NA_integer_, licence_terms = LIC$dogami, coverage = cov,
          verified = cov %in% c("covers", "partial"),
          coverage_basis = sprintf("DOGAMI project-area polygon (layer %s): %s", k, cov))
    }), fill = TRUE)
  }), fill = TRUE)
}

inport_cache <- new.env()
inport <- function(url) {
  id <- sub("^.*/item/([0-9]+).*$", "\\1", url)
  if (!grepl("^[0-9]+$", id)) return(NULL)
  if (!is.null(inport_cache[[id]])) return(inport_cache[[id]])
  x <- http(sprintf("https://www.fisheries.noaa.gov/inport/item/%s/inport-xml", id),
            what = sprintf("noaa inport %s", id))
  if (is.null(x)) return(NULL)
  tag <- function(t) {
    m <- regmatches(x, regexpr(sprintf("<%s>[^<]*", t), x))
    if (length(m)) trimws(sub(sprintf("<%s>", t), "", m)) else NA_character_
  }
  pat <- paste0("[^.<>]{0,120}([0-9.]+ ?(pulses|points|pts|returns)[ /]*(per )?(square )?",
                "(m|meter|metre)[^.<>]{0,60}|QL ?[0-9][^.<>]{0,40}|[Qq]uality [Ll]evel ?[0-9])")
  d <- unique(trimws(regmatches(x, gregexpr(pat, x, perl = TRUE))[[1]]))
  out <- list(start = tag("start-date-time"), end = tag("end-date-time"),
              access = tag("data-access-constraints"), use = tag("data-use-constraints"),
              density = paste(head(d, 3), collapse = " | "))
  inport_cache[[id]] <- out
  out
}

noaa_rows <- function(p, poly, bb) {
  g <- arcgis(DAV, bb, where = "data_type='Lidar'", what = sprintf("%s noaa dav footprints",
                                                                    p$plot_id))
  if (is.null(g)) return(NULL)
  rbindlist(lapply(seq_len(nrow(g)), function(i) {
    a <- sf::st_drop_geometry(g)[i, , drop = FALSE]
    cov_fp <- coverage(sf::st_geometry(g)[i], poly)
    # Dataset tile index (GeoPackage), read for the plot window only.
    keys <- http(NOAA_S3, list(`list-type` = 2, prefix = sprintf("laz/geoid18/%s/tileindex",
                                                                  a$id)),
                 what = sprintf("noaa tileindex listing %s", a$id))
    key <- if (is.null(keys)) character() else
      regmatches(keys, gregexpr("laz/geoid18/[0-9]+/tileindex[^<]*\\.gpkg", keys))[[1]]
    cov_tile <- NA_character_
    nt <- NA_integer_
    if (length(key)) {
      # The spatial filter must be in the index's own CRS.
      dsn <- paste0("/vsicurl/", NOAA_S3, "/", key[1])
      ti <- tryCatch({
        lay <- sf::st_layers(dsn)
        filt <- sf::st_as_text(sf::st_geometry(sf::st_transform(poly, lay$crs[[1]]))[[1]])
        sf::st_read(dsn, layer = lay$name[1], quiet = TRUE, wkt_filter = filt)
      }, error = function(e) NULL)
      if (!is.null(ti)) {
        nt <- nrow(ti)
        cov_tile <- if (nrow(ti)) coverage(sf::st_transform(sf::st_geometry(ti), 4326), poly)
          else "none"
        LOG$req[[length(LOG$req) + 1]] <- list(what = sprintf("noaa tileindex %s (window read)",
          a$id), url = paste0(NOAA_S3, "/", key[1]), method = "GDAL vsicurl",
          retrieved_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), n_tiles = nt)
      }
    }
    im <- inport(a$metadata)
    cov <- if (!is.na(cov_tile)) cov_tile else cov_fp
    row(source = "noaa_dc", collection = a$title, collection_detail = sprintf("DAV id %s", a$id),
        acquisition_years = yrs(a$title, im$start, im$end),
        acquisition_dates = if (!is.null(im)) paste(im$start, im$end, sep = "/") else NA,
        density_or_ql = if (!is.null(im) && nzchar(im$density)) paste("InPort:", im$density)
          else "not found in the InPort record",
        access_route = sprintf("%s/laz/geoid18/%s/index.html (bulk LAZ/COPC); %s", NOAA_S3,
                               a$id, a$dav_link),
        lpc_status = NA_character_, entwine_resource = NA_character_, entwine_covers = NA,
        n_tiles = nt, licence_terms = if (!is.null(im)) paste0("InPort access: ", im$access,
          "; use: ", substr(im$use, 1, 200)) else "InPort record unavailable",
        coverage = cov, verified = !is.na(cov_tile) && cov %in% c("covers", "partial"),
        coverage_basis = paste0("DAV generalized footprint: ", cov_fp,
          if (!is.na(cov_tile)) sprintf("; dataset tile index (%d tiles): %s", nt, cov_tile)
          else "; no tile index read"),
        metadata_url = a$metadata)
  }), fill = TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

res <- rbindlist(lapply(seq_len(nrow(pop)), function(i) {
  p <- pop[i]
  poly <- sf::st_transform(sf::st_as_sfc(p$polygon_wkt, crs = p$epsg), 4326)
  poly <- sf::st_make_valid(sf::st_union(poly))
  FRAME <<- p$epsg
  bb <- as.numeric(sf::st_bbox(poly))
  # Centroid plus four boundary vertices for the WA DNR pixel check (the
  # closing vertex repeats the first, so it is dropped).
  v <- sf::st_coordinates(poly)[, 1:2]
  v <- v[-nrow(v), , drop = FALSE]
  v <- v[unique(round(seq(1, nrow(v), length.out = min(4, nrow(v))))), , drop = FALSE]
  pts <- rbind(sf::st_coordinates(sf::st_centroid(poly))[, 1:2], v)
  # Every source is asked for every plot; the state label (Columbia River
  # border near 46 N for these plots) is for reading only.
  state <- if (p$plot_lat > 46.0) "WA" else "OR"
  message(sprintf("%s (%s, %.4f %.4f)", p$plot_id, state, p$plot_lon, p$plot_lat))
  timed <- function(lbl, expr) {
    t0 <- Sys.time()
    v <- expr
    message(sprintf("  %-6s %3d rows %4.0fs", lbl, if (is.null(v)) 0L else nrow(v),
                    as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    v
  }
  r <- rbindlist(list(timed("usgs", usgs_rows(p, poly, bb)),
                      timed("wadnr", wadnr_rows(p, poly, pts)),
                      timed("dogami", dogami_rows(p, poly, bb)),
                      timed("noaa", noaa_rows(p, poly, bb))), fill = TRUE)
  if (!nrow(r)) r <- row(source = "none", collection = NA_character_, coverage = "none",
                         verified = FALSE, coverage_basis = "no source listed the plot")
  cbind(data.table(plot_id = p$plot_id, project_name = p$project_name, state = state,
                   plot_lon = p$plot_lon, plot_lat = p$plot_lat, survey_year = p$survey_year,
                   admitted_flight = FALSE, flight_ept = p$flight_ept, flight_ql = p$flight_ql,
                   flight_year = p$flight_year, flight_reason = p$flight_reason), r)
}), fill = TRUE)

cols <- c("plot_id", "project_name", "state", "source", "collection", "collection_detail",
          "acquisition_years", "acquisition_dates", "density_or_ql", "access_route",
          "licence_terms", "coverage", "verified", "coverage_basis", "n_tiles",
          "entwine_resource", "entwine_covers", "lpc_status", "metadata_url", "plot_lon",
          "plot_lat", "survey_year", "flight_ept", "flight_ql", "flight_year", "flight_reason")
for (c in setdiff(cols, names(res))) res[, (c) := NA]
res <- res[, ..cols]
res[, src_order := match(source, c("usgs_3dep_lpc", "wa_dnr", "or_dogami", "noaa_dc", "none"))]
setorder(res, plot_id, src_order, collection)
res[, src_order := NULL]
fwrite(res, file.path(pre, "state_lidar.csv"))
jsonlite::write_json(list(
  population_source = pop_src, projects = projects, plots = pop$plot_id,
  note = "Metadata only: footprints, tile indexes, raster identify and metadata records.",
  sources = list(
    usgs = c(WESM_LAYER, "https://tnmaccess.nationalmap.gov/api/v1/products"),
    wa_dnr = c("https://lidarportal.dnr.wa.gov/project", "https://lidarportal.dnr.wa.gov/query",
               WADNR_HS,
               "https://dnr.wa.gov/node/118"),
    or_dogami = DOGAMI, noaa_dc = c(DAV, NOAA_S3, "https://www.fisheries.noaa.gov/inport")),
  ept_resources = res_path, requests = LOG$req),
  file.path(pre, "state_lidar_sources.json"), auto_unbox = TRUE, pretty = TRUE, na = "null",
  null = "null")
message(sprintf("Wrote %s (%d rows, %d plots)", file.path(pre, "state_lidar.csv"), nrow(res),
                uniqueN(res$plot_id)))
print(res[, .(plot_id, source, collection, acquisition_years, coverage, verified)], nrows = 500)
