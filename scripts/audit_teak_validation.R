#!/usr/bin/env Rscript
# Offline metadata audit: no inference, calibration, scoring or data acquisition.
inputs <- character()
initial_inputs <- data.frame(path = character(), bytes = numeric(), sha256 = character())
hash_inputs <- function(paths = inputs) data.frame(path = paths,
  bytes = file.info(paths)$size,
  sha256 = unname(vapply(paths, digest::digest, character(1), file = TRUE, algo = "sha256")))
record <- function(p) {
  p <- normalizePath(p, mustWork = TRUE)
  if (!p %in% inputs) {
    initial_inputs <<- rbind(initial_inputs, hash_inputs(p))
    inputs <<- c(inputs, p)
  }
  p
}
verify_inputs <- function() {
  if (!identical(initial_inputs, hash_inputs())) stop("Read inputs changed during audit")
}
scan_paths <- function(root) {
  nd <- file.path(root, "neon/TEAK")
  csv <- sort(unique(c(list.files(nd, "[.]csv$", full.names = TRUE),
    file.path(nd, "ql2/ql2_detect_results.csv"),
    list.files(file.path(root, "neon"), "[.]csv$", full.names = TRUE))))
  csv <- csv[file.exists(csv) & !basename(csv) %in% c("ground_truth_stems.csv",
    "plot_centroids.csv", "point_locations.csv", "tiles_needed.csv")]
  roots <- unique(c(file.path(nd, c("best_treetop_cache", "frozen")),
    list.dirs(nd, recursive = FALSE, full.names = TRUE)))
  roots <- roots[grepl("(cache|frozen|instances)$", roots)]
  paths <- sort(unique(unlist(lapply(roots, list.files, recursive = TRUE,
                                    full.names = TRUE))))
  list(csv = csv, artifacts = as.character(paths))
}
verify_paths <- function(before, root) {
  if (!identical(before, scan_paths(root))) stop("Scanned paths changed during audit")
}
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
# Register executable sources before sourcing, including transitive helpers.
record(sub("^--file=", "", .bs_file[1]))
record(file.path(dirname(bs[1]), "repo_paths.R"))
source(record(bs[1])); rm(bs, .bs_file)
source(record(.find("neon_reference_support_lib.R")))
record(.find("neon_spatial_lib.R"))
source(record(.find("ept_discovery.R")))
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$SOURCE) || is.null(A$METADATA) || is.null(A$OUT))
  stop("Required: SOURCE=historical_job_dir METADATA=archived_sources OUT=new_directory")
root <- normalizePath(A$SOURCE, mustWork = TRUE)
metadata <- normalizePath(A$METADATA, mustWork = TRUE)
out <- path.expand(A$OUT)
# Resolve existing ancestors before any mkdir; disallow writes into input trees.
resolve_new <- function(p) {
  if (file.exists(p) || dir.exists(p)) return(normalizePath(p, mustWork = TRUE))
  file.path(resolve_new(dirname(p)), basename(p))
}
out <- resolve_new(out)
protected <- c(file.path(root, "neon"), metadata)
if (any(out == protected | startsWith(out, paste0(protected, "/"))))
  stop("OUT must be outside the source NEON and metadata trees")
if (file.exists(out) || dir.exists(out)) stop("OUT must not already exist")
nd <- file.path(root, "neon/TEAK")
scanned_paths <- scan_paths(root)
# Read only named metadata columns from CSVs; detector outcome values are skipped.
read_columns <- function(p, wanted) {
  p <- record(p)
  header <- names(read.csv(p, nrows = 0, check.names = FALSE))
  classes <- ifelse(header %in% wanted, NA_character_, "NULL")
  if (!any(header %in% wanted)) return(data.frame())
  read.csv(p, colClasses = classes, check.names = FALSE)
}
pc <- read.csv(record(file.path(nd, "plot_centroids.csv")))
if (anyDuplicated(pc$plotID) || any(!grepl("^TEAK_[0-9]{3}$", pc$plotID)))
  stop("Invalid TEAK plot inventory")
dat <- readRDS(record(file.path(nd, "vst/teak_vst_allyears.rds")))
pp <- unique(as.data.frame(dat$vst_perplotperyear))
pp$year <- substr(pp$date, 1, 4)
if (any(!pp$plotID %in% pc$plotID)) stop("Census plots absent from centroid inventory")
pp$metadata_status <- vapply(seq_len(nrow(pp)), function(i) {
  tryCatch({neon_event_subplots(pp[i, ]); "subplot_metadata_consistent"},
           error = function(e) conditionMessage(e))
}, character(1))
pp$nominal_box_area_m2 <- ifelse(pp$plotType == "tower", 1600, 400)
pp$area_fraction <- pp$totalSampledAreaTrees / pp$nominal_box_area_m2
pp$evaluation_ready <- FALSE
ai <- as.data.frame(dat$vst_apparentindividual)
mt <- neon_latest_mapping(dat$vst_mappingandtagging)
points <- read.csv(record(file.path(nd, "point_locations.csv")))
# Counts describe source records, not geometry-admitted references or trees.
refs <- do.call(rbind, lapply(seq_len(nrow(pp)), function(i) {
  event <- pp[i, ]
  rows <- ai[which(ai$plotID == event$plotID & ai$eventID == event$eventID &
                    substr(ai$date, 1, 4) == event$year), ]
  target <- rows$growthForm %in% c("single bole tree", "multi-bole tree") &
    is.finite(rows$stemDiameter) & rows$stemDiameter >= 10 &
    !is.na(rows$plantStatus) & grepl("^Live($|[ ,;])", rows$plantStatus)
  rows <- rows[which(target), ]
  mapping <- mt[match(neon_support_key(rows$plotID, rows$individualID),
                      neon_support_key(mt$plotID, mt$individualID)), ]
  subplots <- strsplit(as.character(event$subplotsSampled), "|", fixed = TRUE)[[1]]
  needed <- tryCatch(unique(paste(event$namedLocation,
    unlist(neon_event_subplots(event)), sep = ".")), error = function(e) character())
  data.frame(plotID = event$plotID, eventID = event$eventID, year = event$year,
    census_type = event$dataCollected, n_target_records = nrow(rows),
    n_invalid_height = sum(!is.finite(rows$height) | rows$height <= 0),
    n_unresolved_subplot = sum(!rows$subplotID %in% subplots),
    n_missing_mapping = sum(is.na(mapping$individualID)),
    n_mapping_after_event = sum(as.Date(mapping$date) > as.Date(event$date), na.rm = TRUE),
    n_corners_required = if (length(needed)) length(needed) else NA_integer_,
    n_corners_cached = if (length(needed)) sum(needed %in% points$ptloc) else NA_integer_,
    evaluation_ready = FALSE)
}))
# All direct TEAK derived CSVs, the QL2 results, and shared NEON CSVs.
# Original reference/centroid/location inventories are not outcome exposure.
files <- scanned_paths$csv
evidence <- data.frame(plot = character(), file = character(), kind = character())
for (p in files[file.exists(files)]) {
  x <- read_columns(p, c("plot", "plotID"))
  ids <- unique(as.character(unlist(x)))
  ids <- ids[grepl("^TEAK_[0-9]{3}$", ids)]
  if (length(ids)) evidence <- rbind(evidence,
    data.frame(plot = ids, file = p, kind = "derived_csv_membership"))
}
# Inventory known prediction/instance/frozen trees by path, without reading arrays.
paths <- scanned_paths$artifacts
for (p in paths) {
  ids <- unique(regmatches(p, gregexpr("TEAK_[0-9]{3}", p))[[1]])
  if (length(ids)) evidence <- rbind(evidence,
    data.frame(plot = ids, file = p, kind = "prediction_or_frozen_path"))
}
if (any(!evidence$plot %in% pc$plotID)) stop("Exposed plot absent from inventory")
pc$local_derived_evidence <- pc$plotID %in% evidence$plot
pc$role <- ifelse(pc$local_derived_evidence, "historical_development_only",
                  "candidate_no_evidence_in_scanned_inventory")
pc$evaluation_ready <- FALSE
native <- read_columns(file.path(nd, "sweep_results.csv"),
                       c("plot", "rung", "pdens", "frdens"))
native <- unique(native[native$rung == "native", ])
ql2 <- read_columns(file.path(nd, "ql2/ql2_detect_results.csv"),
                    c("plot", "native_pdens", "native_frdens", "ept_url"))
ql2 <- unique(ql2)
site <- jsonlite::read_json(record(file.path(metadata, "teak-site.json")))$data
products <- site$dataProducts
months <- do.call(rbind, lapply(products, function(p) {
  if (!p$dataProductCode %in% c("DP1.30003.001", "DP1.10098.001")) return(NULL)
  data.frame(product = p$dataProductCode, month = unlist(p$availableMonths))
}))
index <- record(file.path(metadata, "ept-resources.geojson"))
gt <- read.csv(record(file.path(nd, "ground_truth_stems.csv")))
history <- neon_historical_support(gt, pc, dat, "TEAK")
# Each input was hashed at first registration, before reading it. Prediction
# arrays are path-inventoried only; their contents are not verified.
dir.create(out, recursive = TRUE)
write.csv(pc, file.path(out, "plot_inventory.csv"), row.names = FALSE)
write.csv(evidence, file.path(out, "local_use_evidence.csv"), row.names = FALSE)
write.csv(pp[, c("plotID", "plotType", "eventID", "date", "year", "dataCollected",
  "subplotsSampled", "totalSampledAreaTrees", "nominal_box_area_m2", "area_fraction",
  "samplingProtocolVersion", "samplingImpractical", "dataQF", "metadata_status",
  "release", "evaluation_ready")], file.path(out, "census_event_inventory.csv"), row.names = FALSE)
write.csv(refs, file.path(out, "reference_record_inventory.csv"), row.names = FALSE)
write.csv(history, file.path(out, "historical_support_audit.csv"), row.names = FALSE)
write.csv(native, file.path(out, "historical_neon_density.csv"), row.names = FALSE)
write.csv(ql2, file.path(out, "historical_3dep_density.csv"), row.names = FALSE)
write.csv(months, file.path(out, "published_product_months.csv"), row.names = FALSE)
# Existing discovery helper writes only into the fresh OUT tree.
dir.create(file.path(out, "neon/TEAK"), recursive = TRUE)
write.csv(pc[, c("plotID", "plotType", "easting", "northing", "utmZone")],
          file.path(out, "neon/TEAK/plot_centroids.csv"), row.names = FALSE)
discover_ept("TEAK", out, index_local = index)
verify_inputs()
verify_paths(scanned_paths, root)
write.csv(data.frame(path = c(scanned_paths$csv, scanned_paths$artifacts),
  kind = c(rep("csv", length(scanned_paths$csv)),
           rep("artifact_path", length(scanned_paths$artifacts)))),
  file.path(out, "scanned_paths.csv"), row.names = FALSE)
write.csv(initial_inputs, file.path(out, "input_manifest.csv"), row.names = FALSE)
outputs <- sort(list.files(out, recursive = TRUE, full.names = TRUE))
jsonlite::write_json(list(schema_version = 1L, evaluation_ready = FALSE,
  detector_run = FALSE, scoring_run = FALSE, plot_count = nrow(pc),
  locally_observed = sum(pc$local_derived_evidence),
  candidate_unobserved_in_inventory = sum(!pc$local_derived_evidence),
  exposure_scope = "Direct TEAK/shared NEON derived CSV plot columns; TEAK prediction/frozen paths only",
  inputs = initial_inputs, outputs = data.frame(path = outputs,
    sha256 = vapply(outputs, digest::digest, character(1), file = TRUE, algo = "sha256")),
  software = list(R = R.version.string, sf = as.character(packageVersion("sf")),
                  jsonlite = as.character(packageVersion("jsonlite")),
                  digest = as.character(packageVersion("digest")))),
  file.path(out, "completion.json"), auto_unbox = TRUE, pretty = TRUE)
print(table(pc$role))
print(table(pp$year, pp$dataCollected, useNA = "ifany"))
cat("Metadata audit only. No plot admitted, model run, or score regenerated.\n")
