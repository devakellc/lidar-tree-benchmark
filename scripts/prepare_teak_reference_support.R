#!/usr/bin/env Rscript
# Seven-plot metadata-only reconstruction; all products remain diagnostic.
inputs <- data.frame(path = character(), bytes = numeric(), sha256 = character())
sha <- function(p) digest::digest(file = p, algo = "sha256")
record <- function(p) {
  p <- normalizePath(p, mustWork = TRUE)
  if (!p %in% inputs$path) inputs <<- rbind(inputs,
    data.frame(path = p, bytes = file.info(p)$size, sha256 = sha(p)))
  p
}
verify <- function(rows) {
  if (any(!file.exists(rows$path)) ||
      !identical(unname(vapply(rows$path, sha, character(1))), as.character(rows$sha256)))
    stop("Input or output content changed")
}
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
invisible(record(script))
script_dir <- dirname(normalizePath(script, mustWork = TRUE))
invisible(record(file.path(script_dir, "repo_paths.R")))
source(record(file.path(script_dir, "bootstrap.R")))
for (lib in c("neon_spatial_lib.R", "neon_reference_support_lib.R", "teak_reference_lib.R"))
  source(record(.find(lib)))
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$SOURCE) || is.null(A$AUDIT) || is.null(A$OUT))
  stop("Required SOURCE=historical_job_dir AUDIT=sealed_teak_audit OUT=fresh_directory")
fetch <- identical(A$FETCH, "1")
root <- normalizePath(A$SOURCE, mustWork = TRUE)
audit <- normalizePath(A$AUDIT, mustWork = TRUE)
resolve <- function(p) {
  if (file.exists(p) || dir.exists(p)) return(normalizePath(p, mustWork = TRUE))
  file.path(resolve(dirname(p)), basename(p))
}
out <- resolve(path.expand(A$OUT))
protected <- c(file.path(root, "neon"), audit)
if (any(out == protected | startsWith(out, paste0(protected, "/")))) stop("OUT is inside protected inputs")
if (file.exists(out) || dir.exists(out)) stop("OUT must be a fresh directory")
locations <- if (is.null(A$LOCATIONS)) file.path(out, "locations") else normalizePath(A$LOCATIONS, mustWork = TRUE)
if (fetch && !is.null(A$LOCATIONS)) stop("FETCH=1 requires a new archive under OUT")
if (!fetch && is.null(A$LOCATIONS)) stop("Supply LOCATIONS for offline replay or FETCH=1")
pin <- jsonlite::read_json(record(file.path(.ROOT, "docs/teak-validation-sources.json")))
parent_file <- record(file.path(audit, "completion.json"))
if (!identical(sha(parent_file), pin$local_audit$receipt_sha256)) stop("Unexpected parent audit receipt")
parent <- jsonlite::read_json(parent_file, simplifyVector = TRUE)
verify(parent$inputs); verify(parent$outputs)
for (p in c(parent$inputs$path, parent$outputs$path)) invisible(record(p))
expected_paths <- read.csv(file.path(audit, "scanned_paths.csv"))
if (!identical(expected_paths, teak_exposure_paths(root))) stop("Historical exposure inventory changed")
field <- record(file.path(root, "neon/TEAK/vst/teak_vst_allyears.rds"))
if (!field %in% parent$inputs$path) stop("Field source differs from audited input")
dat <- readRDS(field)
events <- teak_events(dat)
epsg <- neon_field_epsg(events)
needed <- teak_needed_locations(dat, events)
protocol <- record(file.path(.ROOT, "docs/teak-reference-protocol.md"))
dir.create(out, recursive = TRUE)
if (fetch) dir.create(locations)
points <- data.frame(ptloc = character(), easting = numeric(), northing = numeric(),
                     zone = character(), unc = numeric(), epsg = integer(),
                     epoch_dates = character(), history_indices = character(),
                     history_start = character(), history_end = character())
statuses <- list()
for (name in needed) {
  path <- file.path(locations, paste0(name, ".json"))
  if (fetch) {
    url <- teak_location_url(name)
    response <- tryCatch(curl::curl_fetch_memory(url, curl::new_handle(timeout = 30)), error = function(e) e)
    rec <- list(location = name, url = url, retrieved_utc = format(Sys.time(), tz = "UTC", usetz = TRUE))
    if (inherits(response, "error")) {
      rec$status <- 0L; rec$error <- conditionMessage(response)
    } else {
      rec$status <- response$status_code
      rec$response_body <- rawToChar(response$content)
      rec$response_sha256 <- digest::digest(response$content, algo = "sha256", serialize = FALSE)
      if (response$status_code == 200L)
        rec$data <- tryCatch(jsonlite::fromJSON(rec$response_body)$data, error = function(e) NULL)
    }
    jsonlite::write_json(rec, path, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
  }
  result <- tryCatch({
    rec <- jsonlite::read_json(record(path), simplifyVector = TRUE)
    teak_location_row(rec, name, epsg, teak_location_dates(dat, events, name))
  }, error = function(e) e)
  ok <- !inherits(result, "error")
  if (ok) points <- rbind(points, result)
  statuses[[name]] <- data.frame(location = name, status = if (ok) "verified_metadata" else conditionMessage(result))
}
contract <- list(schema = 1L, site = "TEAK", year = 2022L, plots = teak_plots(),
  parent_receipt_sha256 = sha(parent_file), field_sha256 = sha(field),
  protocol_sha256 = sha(protocol), epsg = epsg,
  population = "live_mapped_boles_dbh_ge_10cm", policy = "measured_subplots_uncertainty_interior_v1",
  coordinate_policy = "unique_full_day_history_equal_event_measurement_mapping_v1",
  source_hashes = inputs, software = neon_support_software(), evaluation_ready = FALSE)
built <- teak_build(dat, events, points, epsg, contract)
write.csv(events, file.path(out, "census_events.csv"), row.names = FALSE)
write.csv(points, file.path(out, "named_points.csv"), row.names = FALSE)
write.csv(do.call(rbind, statuses), file.path(out, "location_status.csv"), row.names = FALSE)
write.csv(built$summaries, file.path(out, "support_summary.csv"), row.names = FALSE)
write.csv(built$references, file.path(out, "reference_audit.csv"), row.names = FALSE)
target <- built$references[built$references$target_population, ]
keys <- neon_support_key(target$plotID, target$individualID)
for (table in c("vst_apparentindividual", "vst_mappingandtagging")) {
  rows <- as.data.frame(dat[[table]])
  rows <- rows[neon_support_key(rows$plotID, rows$individualID) %in% keys, ]
  columns <- intersect(c("uid", "plotID", "individualID", "eventID", "date", "growthForm", "plantStatus",
    "subplotID", "stemDiameter", "height", "pointID", "namedLocation", "stemDistance", "stemAzimuth",
    "supportingStemIndividualID", "previouslyTaggedAs", "dataQF", "remarks", "release"), names(rows))
  name <- if (table == "vst_apparentindividual") "target_measurement_history.csv" else "target_mapping_history.csv"
  write.csv(rows[, columns], file.path(out, name), row.names = FALSE)
}
saveRDS(built$bundles, file.path(out, "support_bundles.rds"))
if (length(built$bundles)) {
  for (layer in c("footprint", "core")) {
    shapes <- do.call(rbind, lapply(built$bundles, function(b)
      sf::st_sf(plot = b$plot, event = b$event, support_id = neon_support_identity(b),
                evaluation_ready = FALSE, geometry = b[[layer]])))
    sf::st_write(shapes, file.path(out, "support_geometry.gpkg"), layer = layer, quiet = TRUE)
    if (layer == "footprint") sf::st_write(sf::st_transform(shapes, 4326),
      file.path(out, "support_footprints.geojson"), quiet = TRUE)
  }
}
verify(inputs)
if (!identical(expected_paths, teak_exposure_paths(root))) stop("Historical exposure inventory changed")
write.csv(inputs, file.path(out, "input_manifest.csv"), row.names = FALSE)
outputs <- list.files(out, recursive = TRUE, full.names = TRUE)
jsonlite::write_json(list(schema = 1L, evaluation_ready = FALSE, detector_run = FALSE,
  scoring_run = FALSE, parent_receipt_sha256 = sha(parent_file), input_contract = contract,
  inputs = inputs, outputs = data.frame(path = outputs,
    sha256 = unname(vapply(outputs, sha, character(1)))),
  plot_status = built$summaries), file.path(out, "completion.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
print(built$summaries, row.names = FALSE)
cat("All seven plots retained. Diagnostic support only; no detector scoring or admission.\n")
