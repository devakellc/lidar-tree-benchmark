#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_reference_support_lib.R"))
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
site <- if (is.null(A$SITE)) "HARV" else A$SITE
if (!site %in% c("HARV", "BART")) stop("This score-blind preparation is restricted to HARV/BART")
year <- neon_year(if (is.null(A$YEAR)) 2022L else A$YEAR)
nd <- file.path(.job_dir(), "neon", site)
out <- if (is.null(A$OUT)) file.path(.job_dir(), "reference_support", site) else A$OUT
metadata <- file.path(out, "locations")
dir.create(metadata, recursive = TRUE, showWarnings = FALSE)
inputs <- file.path(nd, paste0("vst/", tolower(site), "_vst_allyears.rds"))
if (!file.exists(inputs)) {
  options(timeout = 1200)
  dat <- neonUtilities::loadByProduct(dpID = "DP1.10098.001", site = site,
    package = "basic", release = "RELEASE-2026", check.size = FALSE,
    progress = FALSE, token = neon_token())
  dir.create(dirname(inputs), recursive = TRUE, showWarnings = FALSE)
  saveRDS(dat, inputs)
} else dat <- readRDS(inputs)
points <- data.frame(ptloc = character(), easting = numeric(), northing = numeric(),
                      zone = character(), unc = numeric(), epsg = integer())
pp <- unique(as.data.frame(dat$vst_perplotperyear))
events <- pp[!is.na(pp$date) & substr(as.character(pp$date), 1, 4) == year, ]
if (!nrow(events)) stop("No census events in declared year")
epsg <- neon_field_epsg(events)
ai <- dat$vst_apparentindividual
ai <- ai[!is.na(ai$date) & substr(as.character(ai$date), 1, 4) == year, ]
maps <- neon_latest_mapping(dat$vst_mappingandtagging)
maps <- maps[neon_support_key(maps$plotID, maps$individualID) %in%
               neon_support_key(ai$plotID, ai$individualID), ]
needed <- paste(maps$namedLocation[!is.na(maps$pointID)], maps$pointID[!is.na(maps$pointID)], sep = ".")
for (i in seq_len(nrow(events))) {
  corners <- tryCatch(neon_event_subplots(events[i, ]), error = function(e) NULL)
  needed <- c(needed, paste(events$namedLocation[i], unlist(corners), sep = "."))
}
needed <- sort(unique(needed))
needed <- needed[grepl("^[A-Z]{4}_[0-9]+[.]basePlot[.]vst[.][0-9]+$", needed)]
for (name in setdiff(needed, points$ptloc)) {
  path <- file.path(metadata, paste0(name, ".json"))
  if (!file.exists(path)) {
    response <- curl::curl_fetch_memory(paste0("https://data.neonscience.org/api/v0/locations/", name),
                                        curl::new_handle(timeout = 60))
    record <- list(location = name, status = response$status_code,
                   retrieved_utc = format(Sys.time(), tz = "UTC", usetz = TRUE))
    if (response$status_code == 200L) record$data <- jsonlite::fromJSON(rawToChar(response$content))$data
    jsonlite::write_json(record, path, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  }
  record <- jsonlite::read_json(path, simplifyVector = TRUE)
  if (!identical(record$location, name)) stop("Cached location identity mismatch")
  if (record$status != 200L) next
  loc <- record$data
  if (!identical(loc$locationName, name)) stop("NEON returned a different location")
  frame <- neon_location_frame(loc)
  if (frame$epsg != epsg) stop("Location frame differs from site")
  props <- loc$locationProperties
  unc <- props$locationPropertyValue[props$locationPropertyName == "Value for Coordinate uncertainty"]
  unc <- if (length(unc) == 1L) as.numeric(unc) else NA_real_
  points <- rbind(points, data.frame(ptloc = name, easting = loc$locationUtmEasting,
    northing = loc$locationUtmNorthing, zone = paste0(loc$locationUtmZone, loc$locationUtmHemisphere),
    unc = unc, epsg = frame$epsg))
}
sources <- c(inputs, list.files(metadata, "[.]json$", full.names = TRUE),
             .find("neon_reference_support.R"), .find("neon_reference_support_lib.R"),
             .find("neon_spatial_lib.R"), file.path(.ROOT, "docs/neon-reference-support-protocol.md"))
contract <- list(schema = 1L, site = site, year = year, epsg = epsg,
  files = sources, md5 = unname(tools::md5sum(sources)),
  software = neon_support_software(),
  population = "live_mapped_boles_dbh_ge_10cm", policy = "measured_subplots_uncertainty_interior_v1")
neon_check_manifest(file.path(out, "input_contract.json"), contract)
receipt <- file.path(out, "completion.json")
if (file.exists(receipt)) {
  old <- jsonlite::read_json(receipt, simplifyVector = TRUE)
  if (!all(file.exists(old$files))) stop("Incomplete support artifacts; use a new output directory")
  neon_check_manifest(receipt, list(files = old$files, md5 = unname(tools::md5sum(old$files))))
  cat("Support input and output integrity replay passed; no data or scores changed.\n")
  quit(status = 0L)
}
references <- neon_event_references(dat$vst_apparentindividual, pp, dat$vst_mappingandtagging,
                                    points, year, epsg)
for (column in c("inside_sampled", "inside_interior", "boundary_uncertain", "subplot_conflict", "reference_selected"))
  references[[column]] <- FALSE
keys <- neon_support_key(events$plotID, events$eventID)
summaries <- list(); bundles <- list()
for (key in unique(keys)) {
  event <- events[keys == key, ]
  built <- tryCatch({
    if (nrow(event) != 1L) stop("Ambiguous census event")
    neon_build_support(event, references, points, epsg)
  }, error = function(e) e)
  if (inherits(built, "error")) {
    summaries[[key]] <- data.frame(plot = event$plotID[1], event = event$eventID[1],
      geometry_status = conditionMessage(built), nominal_area_m2 = NA_real_, measured_area_m2 = NA_real_,
      interior_area_m2 = NA_real_, boundary_margin_m = NA_real_, n_target = NA_integer_,
      n_eligible = NA_integer_, n_selected = NA_integer_, n_boundary = NA_integer_,
      n_outside = NA_integer_, n_subplot_conflict = NA_integer_, support_id = NA_character_, evaluation_ready = FALSE)
    next
  }
  built$input_contract <- contract
  id <- neon_support_identity(built)
  bundles[[key]] <- built
  refs <- built$references
  cols <- c("inside_sampled", "inside_interior", "boundary_uncertain", "subplot_conflict", "reference_selected")
  references[match(refs$reference_row, references$reference_row), cols] <- refs[cols]
  summaries[[key]] <- data.frame(plot = built$plot, event = built$event,
    geometry_status = "measured_corners", nominal_area_m2 = built$nominal_area_m2,
    measured_area_m2 = built$measured_area_m2, interior_area_m2 = built$interior_area_m2,
    boundary_margin_m = built$boundary_margin_m, n_target = sum(refs$target_population),
    n_eligible = sum(refs$reference_eligible), n_selected = sum(refs$reference_selected),
    n_boundary = sum(refs$boundary_uncertain),
    n_outside = sum(refs$reference_eligible & !refs$inside_sampled),
    n_subplot_conflict = sum(refs$subplot_conflict), support_id = id,
    evaluation_ready = FALSE)
}
write.csv(do.call(rbind, summaries), file.path(out, "event_support_summary.csv"), row.names = FALSE)
write.csv(references, file.path(out, "reference_audit.csv"), row.names = FALSE)
write.csv(events, file.path(out, "census_events.csv"), row.names = FALSE)
write.csv(points[points$ptloc %in% needed, ], file.path(out, "named_points.csv"), row.names = FALSE)
saveRDS(bundles, file.path(out, "support_bundles.rds"))
if (length(bundles)) {
  footprint <- do.call(rbind, lapply(bundles, function(b)
    sf::st_sf(plot = b$plot, event = b$event, support_id = neon_support_identity(b),
              evaluation_ready = FALSE, geometry = b$footprint)))
  core <- do.call(rbind, lapply(bundles, function(b)
    sf::st_sf(plot = b$plot, event = b$event, margin_m = b$boundary_margin_m,
              evaluation_ready = FALSE, geometry = b$core)))
  gpkg <- file.path(out, "support_geometry.gpkg")
  sf::st_write(footprint, gpkg, layer = "measured_footprints", quiet = TRUE)
  sf::st_write(core, gpkg, layer = "conservative_interiors", quiet = TRUE)
  sf::st_write(sf::st_transform(footprint, 4326), file.path(out, "support_footprints.geojson"), quiet = TRUE)
}
outputs <- list.files(out, "[.](csv|rds|gpkg|geojson)$", full.names = TRUE)
neon_check_manifest(receipt, list(files = outputs, md5 = unname(tools::md5sum(outputs))))
print(do.call(rbind, summaries), row.names = FALSE)
cat("Diagnostic support only. Datum, flight and reference-completeness gates remain; no scoring run.\n")
