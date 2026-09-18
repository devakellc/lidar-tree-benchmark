#!/usr/bin/env Rscript
.bs_ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (!is.null(.bs_ofile) && length(.bs_ofile) && nzchar(.bs_ofile))
    file.path(dirname(.bs_ofile), "bootstrap.R"),
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_ofile, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("eastern_preflight_lib.R"))

# Public metadata only by default. MODE=references inventories local exact-year
# stems without selecting a smoke plot, freezing the split, or running detectors.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
mode <- if (is.null(A$MODE)) "metadata" else A$MODE
if (!mode %in% c("metadata", "references")) stop("MODE must be metadata or references")
out <- if (is.null(A$OUT)) file.path(.job_dir(), "eastern_preflight") else A$OUT
rawdir <- file.path(out, "metadata")
dir.create(rawdir, recursive = TRUE, showWarnings = FALSE)
sites <- c("HARV", "BART")
paths <- unlist(lapply(sites, function(s) file.path(rawdir, paste0(c("sites_", "locations_"), s, ".json"))))
urls <- unlist(lapply(sites, function(s) paste0("https://data.neonscience.org/api/v0/", c("sites/", "locations/"), s)))
provenance <- file.path(out, "metadata_manifest.json")
if (file.exists(provenance)) {
  mf <- jsonlite::read_json(provenance, simplifyVector = TRUE)
  if (any(!file.exists(paths)) || !identical(unname(tools::md5sum(paths)), mf$md5))
    stop("Archived metadata changed or is incomplete; use a separate OUT")
} else {
  if (any(file.exists(paths))) stop("Partial metadata snapshot; use a separate OUT")
  options(timeout = 120)
  for (i in seq_along(paths)) {
    utils::download.file(urls[i], paths[i], quiet = TRUE, mode = "wb")
    if (is.null(jsonlite::fromJSON(paths[i])$data)) stop("Empty NEON metadata response")
  }
  mf <- list(retrieved_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
             urls = urls, files = basename(paths), md5 = unname(tools::md5sum(paths)))
  jsonlite::write_json(mf, provenance, auto_unbox = TRUE, pretty = TRUE)
}
read_meta <- function(kind) setNames(lapply(sites, function(s)
  jsonlite::fromJSON(file.path(rawdir, paste0(kind, "_", s, ".json")))$data), sites)
inventory <- eastern_inventory(read_meta("sites"), read_meta("locations"))
protocol <- file.path(.ROOT, "docs", "eastern-preflight-protocol.md")
declaration <- list(schema_version = 1L, acquisition_year = inventory$year,
  field_release = "RELEASE-2026", roles = c(HARV = "development", BART = "held_out"),
  minimum_exact_core_trees = 6L, candidate_rungs = c("native", "8", "4", "2", "1"),
  protocol_md5 = unname(tools::md5sum(protocol)),
  source_md5 = unname(tools::md5sum(c(.find("preflight_eastern_sites.R"),
                                    .find("eastern_preflight_lib.R"), .find("neon_spatial_lib.R")))))
# Named vectors are serialized as arrays by jsonlite; use a named list for roles.
declaration$roles <- as.list(declaration$roles)
neon_check_manifest(file.path(out, "declaration.json"), declaration)
write.csv(inventory$inventory, file.path(out, "site_inventory.csv"), row.names = FALSE)
write.csv(inventory$months, file.path(out, "available_months.csv"), row.names = FALSE)
if (mode == "references") {
  for (site in sites) {
    nd <- file.path(.job_dir(), "neon", site)
    gt <- read.csv(file.path(nd, "ground_truth_stems.csv"))
    pc <- read.csv(file.path(nd, "plot_centroids.csv"))
    candidates <- eastern_field_candidates(gt, pc, inventory$year)
    write.csv(candidates, file.path(out, paste0(site, "_field_candidates.csv")), row.names = FALSE)
  }
}
print(inventory$inventory, row.names = FALSE)
cat("Archived metadata:", mf$retrieved_utc, "\n")
cat("NEON_TOKEN configured:", nzchar(trimws(Sys.getenv("NEON_TOKEN"))), "\n")
cat("Preflight incomplete: verify files, leaf-on, density and plot coverage before freezing the split.\n")
cat("No detector runs, density measurements or held-out performance inspection performed.\n")
