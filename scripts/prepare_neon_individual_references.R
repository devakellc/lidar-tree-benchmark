#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_reference_support_lib.R"))
source(.find("neon_reference_resolution_lib.R"))
source(.find("neon_individual_reference_lib.R"))
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
if (is.null(A$SOURCE) || is.null(A$SUPPORT) || is.null(A$OUT))
  stop("SOURCE, SUPPORT and a separate OUT directory are required")
root <- normalizePath(A$SOURCE, mustWork = TRUE)
support_root <- normalizePath(A$SUPPORT, mustWork = TRUE)
sites <- if (is.null(A$SITE)) c("HARV", "BART") else A$SITE
if (!all(sites %in% c("HARV", "BART"))) stop("Only HARV/BART field metadata is supported")
out <- if (dir.exists(A$OUT)) normalizePath(A$OUT, mustWork = TRUE) else
  file.path(normalizePath(dirname(A$OUT), mustWork = TRUE), basename(A$OUT))
protected <- c(file.path(root, "neon"), support_root)
if (any(out == protected | startsWith(out, paste0(protected, "/"))))
  stop("OUT must be separate from protected inputs")
contract_path <- file.path(out, "input_contract.json")
if (dir.exists(out) && !file.exists(contract_path) &&
    length(list.files(out, all.files = TRUE, no.. = TRUE))) stop("OUT must be empty or a matching replay")

sources <- character()
for (site in sites) {
  d <- file.path(support_root, site)
  for (name in c("input_contract.json", "completion.json")) {
    path <- file.path(d, name)
    sources <- c(sources, path, neon_verify_receipt(path))
  }
  input <- normalizePath(file.path(root, "neon", site, "vst", paste0(tolower(site), "_vst_allyears.rds")),
                         mustWork = TRUE)
  declared <- jsonlite::read_json(file.path(d, "input_contract.json"), simplifyVector = TRUE)$files
  if (!input %in% normalizePath(declared, mustWork = TRUE)) stop("SOURCE differs from predecessor")
}
code <- vapply(c("prepare_neon_individual_references.R", "neon_individual_reference_lib.R",
  "neon_reference_resolution_lib.R", "neon_reference_support_lib.R", "neon_spatial_lib.R"), .find, character(1))
sources <- sort(unique(c(sources, code, file.path(.ROOT, "docs/neon-individual-reference-protocol.md"))))
before <- unname(tools::md5sum(sources))
policy <- neon_individual_policy()
contract <- list(schema = 1L, files = sources, md5 = before, policy = policy,
                 sites = sites, software = neon_support_software())
dir.create(out, recursive = TRUE, showWarnings = FALSE)
neon_check_manifest(contract_path, contract)
receipt <- file.path(out, "completion.json")
if (file.exists(receipt)) {
  neon_verify_receipt(receipt)
  cat("Individual-reference replay passed; no input or output changed.\n")
  quit(status = 0L)
}

all_support <- list(); members <- list(); comparisons <- list(); units <- list()
for (site in sites) {
  bundles <- readRDS(file.path(support_root, site, "support_bundles.rds"))
  dat <- readRDS(file.path(root, "neon", site, "vst", paste0(tolower(site), "_vst_allyears.rds")))
  if (!length(bundles) || anyDuplicated(names(bundles))) stop("Missing or duplicate predecessor bundles")
  for (key in sort(names(bundles))) {
    b <- bundles[[key]]
    if (key != neon_support_key(b$plot, b$event) || substr(b$plot, 1, 4) != site)
      stop("Predecessor bundle identity mismatch")
    x <- neon_individual_references(b, dat$vst_mappingandtagging, policy)
    x$support$input_contract <- contract
    x$comparison$support_id <- neon_support_identity(x$support)
    all_support[[key]] <- x$support
    members[[key]] <- cbind(site = site, x$members)
    comparisons[[key]] <- cbind(site = site, x$comparison)
    units[[key]] <- cbind(site = site, x$support$references)
  }
}
write.csv(do.call(rbind, units), file.path(out, "individual_references.csv"), row.names = FALSE)
write.csv(do.call(rbind, members), file.path(out, "source_crosswalk.csv"), row.names = FALSE)
comparison <- do.call(rbind, comparisons)
write.csv(comparison, file.path(out, "policy_comparison.csv"), row.names = FALSE)
saveRDS(all_support, file.path(out, "individual_support_bundles.rds"))
after <- unname(tools::md5sum(sources))
if (!identical(before, after)) stop("Protected predecessor inputs changed")
jsonlite::write_json(list(protected_files_hashed = length(sources), integrity = "unchanged",
  source_values_changed = FALSE, geometry_changed = FALSE, detector_runs = 0L,
  evaluation_ready = FALSE, scope = "HARV/BART field records only"),
  file.path(out, "integrity_summary.json"), auto_unbox = TRUE, pretty = TRUE)
outputs <- file.path(out, c("individual_references.csv", "source_crosswalk.csv", "policy_comparison.csv",
                            "individual_support_bundles.rds", "integrity_summary.json"))
neon_check_manifest(receipt, list(files = outputs, md5 = unname(tools::md5sum(outputs))))
print(comparison[, c("site", "plot", "n_source_selected_boles", "n_target_individuals",
                     "n_unresolved_target_individuals", "n_selected_individuals")], row.names = FALSE)
cat("Individual policy compared on unchanged support; every bundle remains diagnostic.\n")
