#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_reference_support_lib.R"))
source(.find("neon_reference_resolution_lib.R"))
source(.find("neon_positional_evidence_lib.R"))
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$SOURCE) || is.null(A$OUT)) stop("SOURCE and a separate OUT are required")
root <- normalizePath(A$SOURCE, mustWork = TRUE)
support <- file.path(root, "reference_support_v2")
individual <- file.path(root, "individual_reference_v2")
resolution <- file.path(root, "reference_resolution_v2")
evidence <- file.path(root, "reference_resolution_evidence_v2")
out <- if (dir.exists(A$OUT)) normalizePath(A$OUT, mustWork = TRUE) else
  file.path(normalizePath(dirname(A$OUT), mustWork = TRUE), basename(A$OUT))
protected <- c(file.path(root, "neon"), support, individual, resolution, evidence)
if (any(out == protected | startsWith(out, paste0(protected, "/")))) stop("OUT overlaps protected inputs")
contract_path <- file.path(out, "input_contract.json")
if (dir.exists(out) && !file.exists(contract_path) &&
    length(list.files(out, all.files = TRUE, no.. = TRUE))) stop("OUT must be empty or a matching replay")
receipts <- c(file.path(individual, c("input_contract.json", "completion.json")),
  file.path(resolution, c("input_contract.json", "completion.json")),
  file.path(evidence, "completion.json"),
  unlist(lapply(c("HARV", "BART"), function(s) file.path(support, s, c("input_contract.json", "completion.json")))))
inputs <- sort(unique(c(receipts, unlist(lapply(receipts, neon_verify_receipt)))))
code <- vapply(c("audit_neon_positional_evidence.R", "neon_positional_evidence_lib.R",
  "neon_reference_support_lib.R", "neon_reference_resolution_lib.R", "neon_spatial_lib.R"), .find, character(1))
inputs <- sort(unique(c(inputs, code, file.path(.ROOT, "docs/neon-positional-evidence-protocol.md"))))
before <- unname(tools::md5sum(inputs))
pdftotext <- Sys.which("pdftotext")
if (!nzchar(pdftotext)) stop("pdftotext is required for archived trajectory reports")
pdf_version <- system2(pdftotext, "-v", stdout = TRUE, stderr = TRUE)
contract <- list(schema = 1L, files = inputs, md5 = before,
  software = c(neon_support_software(), list(spatial = as.list(sf::sf_extSoftVersion()), pdftotext = pdf_version)),
  policy = "bounded_positional_evidence_v1", correction_applied = FALSE, evaluation_ready = FALSE)
dir.create(out, recursive = TRUE, showWarnings = FALSE)
neon_check_manifest(contract_path, contract)
receipt <- file.path(out, "completion.json")
if (file.exists(receipt)) {
  neon_verify_receipt(receipt)
  cat("Positional evidence replay passed; no references or outputs changed.\n")
  quit(status = 0L)
}

units <- read.csv(file.path(individual, "individual_references.csv"))
unresolved <- units[units$target_population & !units$reference_eligible, ]
expected <- c(paste0("NEON.PLA.D01.HARV.", c("05646", "05647", "09167")), "NEON.PLA.D01.BART.05808")
if (nrow(unresolved) != 4L || !setequal(unresolved$individualID, expected))
  stop("Unresolved cases differ from the declared scope")
write.csv(unresolved, file.path(out, "unresolved_individuals.csv"), row.names = FALSE)
cases <- list(
  HARV = data.frame(plotID = c("HARV_033", "HARV_033", "HARV_040", "HARV_040"),
    individualID = paste0("NEON.PLA.D01.HARV.", c("05646", "05647", "09167", "09167A"))),
  BART = data.frame(plotID = "BART_040", individualID = "NEON.PLA.D01.BART.05808"))
history <- list(); mappings <- list(); points <- list(); offsets <- list()
for (site in names(cases)) {
  raw_path <- normalizePath(file.path(root, "neon", site, "vst", paste0(tolower(site), "_vst_allyears.rds")))
  if (!raw_path %in% normalizePath(inputs)) stop("Field source is absent from pinned receipts")
  dat <- readRDS(raw_path)
  wanted <- neon_support_key(cases[[site]]$plotID, cases[[site]]$individualID)
  pick <- function(x, columns) {
    neon_support_require(x, columns, "Released records")
    x <- as.data.frame(x[neon_support_key(x$plotID, x$individualID) %in% wanted, columns])
    if (!setequal(neon_support_key(x$plotID, x$individualID), wanted)) stop("A declared case has no released records")
    x[order(x$plotID, x$individualID, x$date, x$uid), ]
  }
  history[[site]] <- pick(dat$vst_apparentindividual, c("uid", "plotID", "individualID", "eventID", "date",
    "subplotID", "growthForm", "plantStatus", "stemDiameter", "height", "dataQF", "remarks"))
  mappings[[site]] <- pick(dat$vst_mappingandtagging, c("uid", "plotID", "individualID", "date", "recordType",
    "namedLocation", "pointID", "stemDistance", "stemAzimuth", "dataQF", "remarks"))
  paths <- list.files(file.path(support, site, "locations"), "[.]json$", full.names = TRUE)
  points[[site]] <- do.call(rbind, lapply(paths, function(path) {
    if (!path %in% inputs) stop("Unpinned named-point snapshot")
    x <- neon_named_point_evidence(jsonlite::read_json(path, simplifyVector = TRUE))
    if (basename(path) != paste0(x$location, ".json")) stop("Named-point path identity mismatch")
    cbind(site = site, x)
  }))
  if (site != "HARV") next
  b <- readRDS(file.path(support, site, "support_bundles.rds"))[["HARV_033::vst_HARV_2022"]]
  for (id in expected[1:2]) {
    a <- b$references[b$references$individualID == id, ]
    m <- neon_latest_mapping(mappings[[site]])
    m <- m[m$individualID == id & m$plotID == b$plot, ]
    if (nrow(a) != 1L || nrow(m) != 1L) stop("Ambiguous discrepancy source")
    loc <- b$anchors[b$anchors$ptloc == a$mapping_point, ]
    if (nrow(loc) != 1L) stop("Discrepancy anchor is absent")
    x <- neon_offset_hypotheses(loc$easting, loc$northing, m$stemDistance, m$stemAzimuth, b$epsg)
    if (sqrt((x$grid_E - a$E)^2 + (x$grid_N - a$N)^2) > 1e-7) stop("Grid recipe differs from predecessor")
    g <- sf::st_geometry(b$subplots)[which(b$subplots$subplotID == a$subplotID)]
    positions <- sf::st_sfc(sf::st_point(c(x$grid_E, x$grid_N)),
                            sf::st_point(c(x$true_north_E, x$true_north_N)), crs = b$epsg)
    distances <- as.numeric(sf::st_distance(positions, g))
    offsets[[id]] <- cbind(data.frame(individual_id = id, mapping_uid = m$uid,
      point = a$mapping_point, distance_m = m$stemDistance, azimuth_deg = m$stemAzimuth,
      positional_margin_m = a$pos_unc, grid_subplot_distance_m = distances[1],
      true_north_subplot_distance_m = distances[2], grid_within_margin = distances[1] <= a$pos_unc,
      true_north_within_margin = distances[2] <= a$pos_unc), x)
  }
}
write.csv(do.call(rbind, history), file.path(out, "case_measurement_history.csv"), row.names = FALSE)
write.csv(do.call(rbind, mappings), file.path(out, "released_case_mappings.csv"), row.names = FALSE)
write.csv(do.call(rbind, points), file.path(out, "named_point_evidence.csv"), row.names = FALSE)
write.csv(do.call(rbind, offsets), file.path(out, "offset_hypotheses.csv"), row.names = FALSE)
reports <- list.files(evidence, "^2022[0-9]{6}_P3C1_SBET_QAQC[.]pdf$", full.names = TRUE)
if (length(reports) != 4L || !all(reports %in% inputs)) stop("Expected four pinned HARV trajectory reports")
intervals <- do.call(rbind, lapply(reports, function(path) {
  text_path <- file.path(out, sub("[.]pdf$", ".txt", basename(path)))
  status <- system2(pdftotext, c("-layout", shQuote(path), shQuote(text_path)))
  if (status != 0L) stop("Trajectory text extraction failed")
  neon_trajectory_interval(readLines(text_path, warn = FALSE), basename(path))
}))
point_time <- read.csv(file.path(resolution, "HARV_033_point_source_time_audit.csv"))
intervals <- neon_trajectory_compatibility(intervals, point_time)
write.csv(intervals, file.path(out, "trajectory_compatibility.csv"), row.names = FALSE)
if (!identical(before, unname(tools::md5sum(inputs)))) stop("Protected inputs changed during follow-up")
jsonlite::write_json(list(protected_files_hashed = length(inputs), integrity = "unchanged",
  reference_or_geometry_changes = 0L, detector_runs = 0L, downloads = 0L,
  evaluation_ready = FALSE, external_inquiry_sent = FALSE),
  file.path(out, "integrity_summary.json"), pretty = TRUE, auto_unbox = TRUE)
outputs <- sort(list.files(out, "[.]csv$|[.]txt$|^integrity_summary[.]json$", full.names = TRUE))
neon_check_manifest(receipt, list(files = outputs, md5 = unname(tools::md5sum(outputs))))
print(do.call(rbind, offsets), row.names = FALSE)
print(intervals, row.names = FALSE)
cat("Bounded evidence exported. No correction, admission or external submission performed.\n")
