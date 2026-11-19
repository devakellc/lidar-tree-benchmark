#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages(library(data.table))
source(.find("ofo_preflight_lib.R"))      # kept-return reader, stage records
source(.find("ofo_reference_lib.R"))      # contracts, path guards, group signals
source(.find("ofo_registration_lib.R"))   # the frozen method's surface (OFO_REG2)
source(.find("ofo_conditions_lib.R"))     # flight dates
source(.find("ofo_disturbance_lib.R"))

# Disturbance between survey and flight for groups A and B of the Open Forest
# Observatory second preflight (docs/ofo-preflight-protocol-2.md). Score-blind:
# no detector runs; the canopy check reads the frozen method's surface.
#   STAGE=records   for every plot of groups A and B, the interval from 1
#                   January of the survey year to the last flight day, and the
#                   records of its envelope (the polygon buffered by 1 km, WGS
#                   84): interagency fire perimeter history and WFIGS
#                   perimeters (polygon buffered by 50 m), Forest Service
#                   timber harvest, completed hazardous-fuel treatments and
#                   timber stand improvement (polygon itself), and the Forest
#                   Service surface-ownership parcels (whether those records
#                   cover the plot). Intersections are tested in the project
#                   frame. Every response is kept with its URL, retrieval time,
#                   bytes and SHA-256; so are the layers' metadata, against
#                   which the date fields are checked. A second online run
#                   needs REQUERY=TRUE (the kept responses move aside, under
#                   records_superseded_<UTC time>); OFFLINE=TRUE re-evaluates
#                   the kept responses, their digests checked, without network.
#   STAGE=presence  canopy over mapped trees at the registered positions (raw
#                   position plus the plot's method-2 shift) on the method's
#                   surface of the plot cloud (kept returns, TIN-normalised as
#                   the catalogue registration does), for plots whose group's
#                   signal is admitted by the crown-frame test
#                   (crowntruth_test.json) and that the second protocol's
#                   gates register; other plots are "not_run". Then joins the
#                   three checks into disturbance.csv.
#   STAGE=all       both, in that order.
# Inputs (OFO = $CLAUDE_JOB_DIR/ofo, read-only): OFO/preflight/{plots,flights}.csv
#   (records); plus {trees,clouds,registration_catalog}.csv, clouds/<plot>.laz
#   and OFO/preflight2/crowntruth_test.json (presence). Network (records):
#   services3.arcgis.com (fire perimeters), apps.fs.usda.gov (EDW layers).
# Outputs (P2 = OFO/preflight2): records/<plot>/<source>.json,
#   records/layers/<source>.json, records/records_sources.json,
#   disturbance_records.csv, disturbance_records_detail.csv, records_record.json
#   (records); presence.csv, presence_stems.csv, disturbance.csv,
#   disturbance_record.json (presence). Nothing is written outside P2.
#   Rscript scripts/preflight_ofo_disturbance.R STAGE=records [CORES=4]
#     [OFFLINE=TRUE | REQUERY=TRUE]
#   Rscript scripts/preflight_ofo_disturbance.R STAGE=presence [CORES=4]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
unknown <- setdiff(names(A), c("STAGE", "CORES", "OFFLINE", "REQUERY"))
if (length(unknown)) stop("Unknown argument(s): ", paste(unknown, collapse = ", "))
STAGE <- if (is.null(A$STAGE)) "all" else A$STAGE
if (!STAGE %in% c("records", "presence", "all")) stop("STAGE must be records, presence or all")
CORES <- as.integer(if (is.null(A$CORES)) 4 else A$CORES)
flag <- function(k) isTRUE(as.logical(if (is.null(A[[k]])) "FALSE" else A[[k]]))
OFFLINE <- flag("OFFLINE"); REQUERY <- flag("REQUERY")
if (OFFLINE && REQUERY) stop("OFFLINE=TRUE and REQUERY=TRUE exclude each other")
options(lidR.progress = FALSE)

job <- normalizePath(.job_dir(), mustWork = FALSE)
OFO <- file.path(job, "ofo")
PRE <- file.path(OFO, "preflight")
P2 <- file.path(OFO, "preflight2")
REC <- file.path(P2, "records")
SOURCES_JSON <- file.path(REC, "records_sources.json")
neon_root <- ofo_path_resolve(file.path(job, "neon"))
# Every path written lies under P2, resolved through symlinks, never in the NEON tree.
guard <- function(path) {
  p <- ofo_path_resolve(path)
  ok <- ofo_path_under(path, OFO) && ofo_path_within(p, ofo_path_resolve(P2)) &&
    !ofo_path_within(p, neon_root)
  if (!ok) stop("Refusing to write outside ", P2, ": ", path, call. = FALSE)
  invisible(path)
}
guard(P2)
utc_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
write_json <- function(x, path) {
  guard(path)
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null",
                       null = "null")
}
write_csv <- function(x, name) {
  guard(file.path(P2, name))
  fwrite(x, file.path(P2, name))
}
read_flights <- function()
  as.data.frame(fread(file.path(PRE, "flights.csv"), na.strings = c("", "NA"),
                      colClasses = list(character = c("plot_id", "flight_days"))))

# The plots of groups A and B (screened in, not NEON2023) with their interval.
ab_plots <- function(plots, flights) {
  p <- plots[plots$screen %in% "none" & plots$group %in% OFO_DIST_GROUPS &
               plots$project_name != OFO_NEON_PROJECT, , drop = FALSE]
  p <- p[order(p$plot_id), , drop = FALSE]
  iv <- ofo_dist_interval(p$survey_year, flights$flight_days[match(p$plot_id, flights$plot_id)])
  cbind(p, iv)
}

## ==== STAGE=records ============================================================

# One GET with retries; the body is kept only when it is a JSON object without
# an "error" member. Returns the response's record.
fetch <- function(url, path, tries = 4L) {
  last <- "no attempt"
  for (k in seq_len(tries)) {
    r <- tryCatch(curl::curl_fetch_memory(url, handle = curl::new_handle(
      timeout = 600, connecttimeout = 60)), error = function(e) e)
    if (inherits(r, "error")) {
      last <- conditionMessage(r)
    } else if (r$status_code != 200) {
      last <- sprintf("HTTP %d", r$status_code)
    } else {
      js <- tryCatch(jsonlite::fromJSON(rawToChar(r$content), simplifyVector = FALSE),
                     error = function(e) NULL)
      if (!is.list(js)) last <- "not JSON"
      else if (!is.null(js$error)) last <- paste("service error", js$error$code, js$error$message)
      else {
        guard(path)
        dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
        part <- paste0(path, ".part")
        writeBin(r$content, part)
        file.rename(part, path)
        return(list(status = "ok", http_status = r$status_code, retrieved_utc = utc_now(),
                    bytes = length(r$content),
                    sha256 = digest::digest(file = path, algo = "sha256"),
                    n_features = length(js$features),
                    exceeded_transfer_limit = isTRUE(js$exceededTransferLimit), error = NA))
      }
    }
    if (k < tries) Sys.sleep(5 * k)
  }
  list(status = "failed", http_status = NA, retrieved_utc = utc_now(), bytes = NA, sha256 = NA,
       n_features = NA, exceeded_transfer_limit = NA, error = last)
}

rel <- function(path) substring(path, nchar(P2) + 2)

# Layer metadata (fields and their types), kept so the date fields chosen
# are on record; the run stops when a chosen field is missing or not a date.
fetch_layers <- function() {
  out <- lapply(seq_len(nrow(OFO_DIST_SOURCES)), function(i) {
    s <- OFO_DIST_SOURCES[i, ]
    path <- file.path(REC, "layers", paste0(s$source, ".json"))
    m <- fetch(paste0(s$url, "?f=json"), path)
    c(list(source = s$source, url = paste0(s$url, "?f=json"), file = rel(path)), m)
  })
  check_layers(out)
  out
}

check_layers <- function(layers) {
  for (L in layers) {
    s <- OFO_DIST_SOURCES[OFO_DIST_SOURCES$source == L$source, ]
    if (!identical(L$status, "ok")) stop("Layer metadata unavailable: ", L$source, ": ", L$error)
    js <- jsonlite::read_json(file.path(P2, L$file), simplifyVector = TRUE)
    f <- js$fields
    want <- c(s$date_field, s$name_field, s$oid)
    want <- want[nzchar(want)]
    miss <- want[!tolower(want) %in% tolower(f$name)]
    if (length(miss)) stop(L$source, ": layer lacks field(s) ", paste(miss, collapse = ", "))
    if (s$date_rule %in% c("discovery_date", "date_completed")) {
      ty <- f$type[match(tolower(s$date_field), tolower(f$name))]
      if (!identical(ty, "esriFieldTypeDate")) stop(L$source, ": ", s$date_field, " is ", ty)
    }
  }
  invisible(TRUE)
}

# Every source of one plot, pages included (resultOffset while the server says
# the transfer limit was exceeded).
query_plot <- function(p) {
  poly <- ofo_polygon(p$polygon_wkt, p$epsg)
  env <- ofo_dist_envelope(poly)
  out <- list()
  for (i in seq_len(nrow(OFO_DIST_SOURCES))) {
    s <- OFO_DIST_SOURCES[i, ]
    offset <- 0L; page <- 1L
    repeat {
      url <- ofo_dist_query_url(s$url, env, s$oid, offset)
      path <- file.path(REC, p$plot_id, sprintf("%s%s.json", s$source,
                                                if (page > 1L) paste0(".p", page) else ""))
      m <- fetch(url, path)
      env_txt <- paste(sprintf("%.7f", env), collapse = ",")
      out[[length(out) + 1L]] <- c(list(plot_id = p$plot_id, source = s$source, page = page,
                                        url = url, file = rel(path), envelope_wgs84 = env_txt), m)
      if (!identical(m$status, "ok") || !isTRUE(m$exceeded_transfer_limit) ||
          !isTRUE(m$n_features > 0)) break
      offset <- offset + m$n_features; page <- page + 1L
    }
  }
  out
}

# The kept responses as a table; OFFLINE runs check each file's digest.
responses_table <- function(resp) {
  x <- rbindlist(lapply(resp, function(r) as.data.table(lapply(r, function(v)
    if (is.null(v)) NA else v))), fill = TRUE)
  as.data.frame(x)
}

verify_kept <- function(tab) {
  ok <- tab$status %in% "ok"
  cur <- vapply(file.path(P2, tab$file[ok]), function(f)
    if (file.exists(f)) digest::digest(file = f, algo = "sha256") else NA_character_,
    character(1))
  bad <- tab$file[ok][is.na(cur) | cur != tab$sha256[ok]]
  if (length(bad)) stop("Kept responses differ from records_sources.json: ",
                        paste(utils::head(bad, 10), collapse = ", "), call. = FALSE)
  invisible(TRUE)
}

# Detail rows of every source of every plot, and the failed queries.
evaluate <- function(pop, tab) {
  det <- list(); fail <- list()
  for (i in seq_len(nrow(pop))) {
    p <- pop[i, ]
    poly <- ofo_polygon(p$polygon_wkt, p$epsg)
    for (j in seq_len(nrow(OFO_DIST_SOURCES))) {
      s <- OFO_DIST_SOURCES[j, ]
      r <- tab[tab$plot_id == p$plot_id & tab$source == s$source, , drop = FALSE]
      r <- r[order(r$page), , drop = FALSE]
      last <- r[nrow(r), , drop = FALSE]
      if (!nrow(r) || any(!r$status %in% "ok") ||
          isTRUE(as.logical(last$exceeded_transfer_limit))) {
        fail[[length(fail) + 1L]] <- data.frame(plot_id = p$plot_id, source = s$source)
        next
      }
      pages <- lapply(file.path(P2, r$file), ofo_dist_read_response)
      resp <- list(attrs = as.data.frame(rbindlist(lapply(pages, `[[`, "attrs"), fill = TRUE)),
                   geom = do.call(c, lapply(pages, `[[`, "geom")))
      if (!length(resp$geom)) resp$geom <- sf::st_sfc(crs = 4326)
      latest <- as.Date(substr(r$retrieved_utc[1], 1, 10))
      d <- ofo_dist_features(resp, s, poly, p$plot_id, p$interval_start, p$interval_end, latest)
      if (nrow(d)) det[[length(det) + 1L]] <- d
    }
  }
  det <- if (length(det)) do.call(rbind, det) else
    as.data.frame(stats::setNames(replicate(length(OFO_DIST_DETAIL_COLS), character(),
                                            simplify = FALSE), OFO_DIST_DETAIL_COLS))
  fail <- if (length(fail)) do.call(rbind, fail) else data.frame(plot_id = character(),
                                                                  source = character())
  list(det = det, fail = fail)
}

stage_records <- function() {
  in_pre <- c("plots.csv", "flights.csv")
  sha_pre <- ofo_sha256(PRE, in_pre)
  if (anyNA(sha_pre)) stop("Missing first-protocol input(s): ",
                           paste(in_pre[is.na(sha_pre)], collapse = ", "))
  plots <- ofo_read_input(PRE, "plots.csv")
  flights <- read_flights()
  pop <- ab_plots(plots, flights)
  if (!nrow(pop)) stop("No plot of groups A and B in plots.csv")
  if (OFFLINE) {
    if (!file.exists(SOURCES_JSON)) stop("OFFLINE=TRUE needs ", SOURCES_JSON)
    src <- jsonlite::read_json(SOURCES_JSON, simplifyVector = TRUE)
    tab <- as.data.frame(src$responses, stringsAsFactors = FALSE)
    lay <- as.data.frame(src$layers, stringsAsFactors = FALSE)
    verify_kept(tab); verify_kept(lay)
    check_layers(lapply(seq_len(nrow(lay)), function(i) as.list(lay[i, ])))
    if (!setequal(unique(tab$plot_id), pop$plot_id))
      stop("The kept responses are for other plots than plots.csv's groups A and B")
    message(sprintf("OFFLINE: %d kept responses for %d plots", nrow(tab), nrow(pop)))
  } else {
    if (file.exists(SOURCES_JSON) && !REQUERY)
      stop("Records were queried before (", SOURCES_JSON, "); pass OFFLINE=TRUE to ",
           "re-evaluate them or REQUERY=TRUE to query again", call. = FALSE)
    if (dir.exists(REC)) {
      old <- file.path(P2, paste0("records_superseded_", format(Sys.time(), "%Y%m%dT%H%M%SZ",
                                                                tz = "UTC")))
      guard(old)
      if (!file.rename(REC, old)) stop("Could not move ", REC, " aside")
      message("previous records moved to ", old)
    }
    dir.create(REC, recursive = TRUE, showWarnings = FALSE)
    message(sprintf("STAGE=records: %d plots x %d layers, %d workers", nrow(pop),
                    nrow(OFO_DIST_SOURCES), CORES))
    layers <- fetch_layers()
    res <- parallel::mclapply(seq_len(nrow(pop)), function(i) {
      o <- tryCatch(query_plot(pop[i, ]), error = function(e) e)
      message(sprintf("  %s %s", pop$plot_id[i], if (inherits(o, "error"))
        paste("error:", conditionMessage(o)) else
        sprintf("%d responses, %d failed", length(o), sum(vapply(o, function(r)
          !identical(r$status, "ok"), logical(1))))))
      o
    }, mc.cores = CORES, mc.preschedule = FALSE)
    bad <- vapply(res, function(x) inherits(x, "error") || inherits(x, "try-error"), logical(1))
    if (any(bad)) stop("Query workers failed for plots: ", paste(pop$plot_id[bad], collapse = ","))
    tab <- responses_table(unlist(res, recursive = FALSE))
    lay <- responses_table(layers)
    write_json(list(
      created_utc = utc_now(),
      protocol = "docs/ofo-preflight-protocol-2.md (Disturbance between survey and flight)",
      query = list(
        envelope = sprintf(paste("WGS 84 envelope of the plot polygon buffered by %d m in the",
                                 "project frame (densified before the transform)"),
                           OFO_DIST_QUERY_BUFFER_M),
        parameters = paste("where=1=1, geometryType=esriGeometryEnvelope, inSR=4326,",
                           "spatialRel=esriSpatialRelIntersects, outFields=*,",
                           "returnGeometry=true, outSR=4326, orderByFields=<object id>, f=json;",
                           "resultOffset pages while exceededTransferLimit"),
        intersection = sprintf(paste("project frame: fire perimeters against the plot polygon",
                                     "buffered by %d m, activity and ownership features against",
                                     "the polygon itself"), OFO_DIST_FIRE_BUFFER_M)),
      date_rules = list(
        fire_history = paste("FIRE_YEAR_INT, else the FIRE_YEAR string; the placeholders",
                             "0, 1000 and 9999 and years after the retrieval year are",
                             "unknown, years before 1800 are years;",
                             "in the interval when within its calendar years"),
        fire_wfigs = paste("attr_FireDiscoveryDateTime (epoch ms) as a UTC date; in the",
                           "interval when between its start and end, both included"),
        activities = paste("date_completed (the completion date, FACTS DATE_ACCOMPLISHED)",
                           "of the timber harvest, hazardous-fuel (Treatments - Completed)",
                           "and timber stand improvement layers, as a UTC date; dates before",
                           "1800 or after the retrieval date are unknown")),
      nfs = paste("EDW_SurfaceOwnership_01 layer 0 (Land Status Record System surface",
                  "ownership parcels): the plot polygon intersects a parcel whose",
                  "ownerclassification is USDA FOREST SERVICE"),
      sources = OFO_DIST_SOURCES, layers = lay, responses = tab), SOURCES_JSON)
  }
  ev <- evaluate(pop, tab)
  rt <- ofo_dist_record_table(pop, ev$det, ev$fail)
  fl <- flights[match(rt$plot_id, flights$plot_id), , drop = FALSE]
  rt$survey_year <- as.integer(pop$survey_year[match(rt$plot_id, pop$plot_id)])
  rt$flight_days <- fl$flight_days
  rt$flight_admitted <- ofo_lgl(fl$flight_admitted) %in% TRUE
  rt$cloud_status <- fl$cloud_status
  write_csv(rt, "disturbance_records.csv")
  write_csv(ev$det, "disturbance_records_detail.csv")
  if (!identical(ofo_sha256(PRE, in_pre), sha_pre))
    stop("Inputs changed during the run; rerun STAGE=records", call. = FALSE)
  rec <- ofo_p2_record("disturbance records", P2, character(),
                       c("disturbance_records.csv", "disturbance_records_detail.csv",
                         "records/records_sources.json"), PRE, sha_pre,
                       list(offline = OFFLINE, n_plots = nrow(pop), n_responses = nrow(tab),
                            n_failed = sum(!tab$status %in% "ok")))
  ofo_write_record(rec, guard(file.path(P2, "records_record.json")))
  print_records(rt, ev)
  invisible(rt)
}

print_records <- function(rt, ev) {
  cat(sprintf("\nrecords: %d plots; failed queries %d\n", nrow(rt), nrow(ev$fail)))
  show <- c("plot_id", "group", "interval_start", "interval_end", "n_fire_records",
            "fire_clear", "n_activity_records", "activities_clear", "nfs_records_source",
            "n_fire_intersecting", "n_activity_intersecting", "flight_admitted")
  print(rt[, show], row.names = FALSE)
  hit <- ev$det[ev$det$hit %in% TRUE & ev$det$record != "ownership", , drop = FALSE]
  if (nrow(hit)) {
    cat("\nintersecting fire and activity records:\n")
    print(hit[, c("plot_id", "source", "name", "event_date", "event_year", "in_interval")],
          row.names = FALSE)
  }
}

## ==== STAGE=presence ===========================================================

# The method's surface of one plot cloud: kept returns, TIN-normalised with
# its class-2 returns, highest return per 0.5 m cell, gaps filled; the
# catalogue registration stage's code path (catalog_plot2()).
plot_surface <- function(laz, signal) {
  nrm <- ofo_normalize(ofo_read_las(laz, "xyzc"))
  lidR::set_lidr_threads(1L)
  chm <- lidR::rasterize_canopy(nrm, res = OFO_REG2_SEARCH$res,
                                algorithm = lidR::p2r(OFO_REG2_SEARCH$subcircle))
  ofo2_surface(chm, OFO_REG2[[signal]]$cfg$surface)
}

presence_plot <- function(pid, group, tr, laz, dx, dy, signal) {
  test <- ofo_presence_test_stems(group, ofo_lgl(tr$live), ofo_lgl(tr$ref),
                                  as.numeric(tr$height), as.numeric(tr$dbh))
  s <- tr[test, , drop = FALSE]
  S <- plot_surface(laz, signal)
  E <- as.numeric(s$x) + dx; N <- as.numeric(s$y) + dy
  cmax <- ofo_presence_canopy_max(S, E, N)
  need <- if (group == "A") OFO_PRESENCE$height_share * as.numeric(s$height) else
    rep(OFO_PRESENCE$min_canopy_m, nrow(s))
  present <- ofo_presence_present(group, cmax, as.numeric(s$height))
  list(stems = data.frame(plot_id = rep(pid, nrow(s)), individual_id = s$individual_id,
                          tree_n = s$tree_n, x = s$x, y = s$y, E = E, N = N,
                          height = s$height, dbh = s$dbh, canopy_max_m = cmax,
                          threshold_m = need, present = present, stringsAsFactors = FALSE),
       n_test = nrow(s), n_missing = sum(!present))
}

stage_presence <- function() {
  rr_path <- file.path(P2, "records_record.json")
  if (!file.exists(rr_path)) stop("Run STAGE=records first: ", rr_path, " is missing")
  bad <- ofo_p2_record_mismatch(jsonlite::read_json(rr_path), P2, PRE)
  if (length(bad)) stop("The record checks are not current; rerun STAGE=records:\n  ",
                        paste(bad, collapse = "\n  "), call. = FALSE)
  stale <- ofo_check_records(PRE, c(
    flights_record.json = "preflight_ofo_catalog.R STEPS=flights",
    registration_catalog_record.json = "preflight_ofo_registration.R STAGE=catalog"))
  if (length(stale)) stop("First-protocol outputs are not current:\n  ",
                          paste(stale, collapse = "\n  "), call. = FALSE)
  in_pre <- c("plots.csv", "trees.csv", "flights.csv", "clouds.csv", "registration_catalog.csv")
  in_p2 <- c("crowntruth_test.json", "disturbance_records.csv")
  sha_pre <- ofo_sha256(PRE, in_pre); sha_p2 <- ofo_sha256(P2, in_p2)
  if (is.na(sha_p2[["crowntruth_test.json"]]))
    stop("Missing ", file.path(P2, "crowntruth_test.json"),
         ": the crown-frame test decides which signals are admitted", call. = FALSE)
  if (anyNA(sha_pre)) stop("Missing first-protocol input(s): ",
                           paste(in_pre[is.na(sha_pre)], collapse = ", "))
  admitted <- ofo_signals_admitted(jsonlite::read_json(file.path(P2, "crowntruth_test.json"),
                                                       simplifyVector = TRUE))
  plots <- ofo_read_input(PRE, "plots.csv")
  flights <- read_flights()
  rd <- function(f) as.data.frame(fread(file.path(PRE, f), na.strings = c("", "NA"),
                                        colClasses = list(character = "plot_id")))
  cat_tab <- rd("registration_catalog.csv")
  clouds <- rd("clouds.csv")
  trees <- ofo_read_input(PRE, "trees.csv")
  rec <- as.data.frame(fread(file.path(P2, "disturbance_records.csv"), na.strings = c("", "NA"),
                             colClasses = list(character = c("plot_id", "interval_start",
                                                             "interval_end"))))
  reg <- ofo_p2_registration(plots, flights, cat_tab, admitted)
  if (!setequal(reg$plot_id, rec$plot_id))
    stop("disturbance_records.csv covers other plots than the candidates of groups A and B")
  pres <- data.frame(plot_id = rec$plot_id, group = rec$group,
                     signal = unname(OFO_GROUP_SIGNAL[rec$group]), stringsAsFactors = FALSE)
  rg <- reg[match(pres$plot_id, reg$plot_id), , drop = FALSE]
  pres$signal_admitted <- unname(admitted[pres$signal])
  pres$registered <- rg$registered
  pres$shift_dx <- ifelse(rg$registered, rg$dx, NA_real_)
  pres$shift_dy <- ifelse(rg$registered, rg$dy, NA_real_)
  pres$presence_test_stems <- vapply(seq_len(nrow(pres)), function(i) {
    tr <- trees[trees$plot_id == pres$plot_id[i], , drop = FALSE]
    sum(ofo_presence_test_stems(pres$group[i], ofo_lgl(tr$live), ofo_lgl(tr$ref),
                                as.numeric(tr$height), as.numeric(tr$dbh)))
  }, integer(1))
  pres$presence_note <- ifelse(!pres$signal_admitted, "signal_not_admitted",
                               ifelse(!pres$registered, "not_registered", ""))
  run <- which(pres$signal_admitted & pres$registered)
  cl <- clouds[match(pres$plot_id[run], clouds$plot_id), , drop = FALSE]
  laz <- file.path(OFO, cl$path)
  miss <- pres$plot_id[run][is.na(cl$path) | !file.exists(laz)]
  if (length(miss)) stop("Clouds missing for registered plots: ", paste(miss, collapse = ", "))
  cloud_sha <- vapply(laz, function(f) digest::digest(file = f, algo = "sha256"), character(1))
  diff <- !is.na(cl$sha256) & cloud_sha != cl$sha256
  if (any(diff)) stop("Clouds differ from clouds.csv: ", paste(pres$plot_id[run][diff],
                                                              collapse = ", "))
  message(sprintf("STAGE=presence: signals admitted height %s, rank %s; %d of %d plots run",
                  admitted[["height"]], admitted[["rank"]], length(run), nrow(pres)))
  out <- parallel::mclapply(seq_along(run), function(k) {
    i <- run[k]
    tryCatch(presence_plot(pres$plot_id[i], pres$group[i],
                           trees[trees$plot_id == pres$plot_id[i], , drop = FALSE], laz[k],
                           pres$shift_dx[i], pres$shift_dy[i], pres$signal[i]),
             error = function(e) e)
  }, mc.cores = max(1L, min(CORES, length(run))), mc.preschedule = FALSE)
  err <- vapply(out, function(o) inherits(o, "error") || inherits(o, "try-error"), logical(1))
  if (any(err)) stop("Presence failed for plots: ", paste(sprintf("%s (%s)", pres$plot_id[run][err],
    vapply(out[err], function(o) conditionMessage(o), "")), collapse = ", "))
  pres$presence_missing <- NA_integer_
  pres$presence_status <- "not_run"
  pres$cloud_sha256 <- NA_character_
  for (k in seq_along(run)) {
    i <- run[k]
    pres$presence_missing[i] <- out[[k]]$n_missing
    pres$presence_status[i] <- ofo_presence_status(out[[k]]$n_test, out[[k]]$n_missing)
    pres$cloud_sha256[i] <- cloud_sha[k]
  }
  stems <- if (length(out)) do.call(rbind, lapply(out, `[[`, "stems")) else
    data.frame(plot_id = character(), individual_id = character())
  dist <- ofo_dist_table(rec, pres[, c("plot_id", "presence_test_stems", "presence_missing",
                                       "presence_status", "presence_note", "signal",
                                       "signal_admitted", "registered", "shift_dx",
                                       "shift_dy")])
  write_csv(pres, "presence.csv")
  write_csv(stems, "presence_stems.csv")
  write_csv(dist, "disturbance.csv")
  if (!identical(ofo_sha256(PRE, in_pre), sha_pre) || !identical(ofo_sha256(P2, in_p2), sha_p2))
    stop("Inputs changed during the run; rerun STAGE=presence", call. = FALSE)
  rec_out <- ofo_p2_record("disturbance presence", P2, sha_p2,
                           c("presence.csv", "presence_stems.csv", "disturbance.csv"), PRE,
                           sha_pre, list(signals_admitted = as.list(admitted),
                                         presence = OFO_PRESENCE,
                                         clouds = as.list(stats::setNames(cloud_sha,
                                                                          pres$plot_id[run]))))
  ofo_write_record(rec_out, guard(file.path(P2, "disturbance_record.json")))
  cat("\npresence and disturbance per plot:\n")
  print(dist[, c("plot_id", "group", "fire_clear", "activities_clear", "presence_test_stems",
                 "presence_missing", "presence_status", "disturbance_admitted",
                 "disturbance_reason")], row.names = FALSE)
  invisible(dist)
}

dir.create(P2, recursive = TRUE, showWarnings = FALSE)
if (STAGE %in% c("records", "all")) stage_records()
if (STAGE %in% c("presence", "all")) stage_presence()
