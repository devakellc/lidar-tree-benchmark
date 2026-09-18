#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_acquisition_lib.R"))
source(.find("eastern_preflight_lib.R"))

# Released file availability only. MODE=coverage also inventories local field
# references and census support. Neither mode downloads spatial tiles or freezes
# a validation split. A coverage candidate is not a verified scoring footprint.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
mode <- if (is.null(A$MODE)) "metadata" else A$MODE
if (!mode %in% c("metadata", "coverage")) stop("MODE must be metadata or coverage")
out <- if (is.null(A$OUT)) file.path(.job_dir(), "authenticated_preflight") else A$OUT
dir.create(out, recursive = TRUE, showWarnings = FALSE)
month <- "2022-08"; release <- "RELEASE-2026"
products <- c(lidar = "DP1.30003.001", rgb = "DP3.30010.001")
rows <- list(); candidates <- list(); support <- list(); snapshot_paths <- character()
for (site in c("HARV", "BART")) {
  tiles <- list()
  for (kind in names(products)) {
    path <- file.path(out, paste0(site, "_", kind, "_files.json"))
    if (!file.exists(path)) {
      listing <- neon_released_files(products[[kind]], site, month, release)
      neon_archive_listing(listing, path)
      rm(listing) # Signed URLs remain in memory only for the live request.
    }
    snapshot <- jsonlite::read_json(path, simplifyVector = TRUE)
    if (!identical(snapshot$product, products[[kind]]) || !identical(snapshot$site, site) ||
        !identical(snapshot$month, month) || !identical(snapshot$release, release))
      stop("Cached file list does not match the declared acquisition")
    tiles[[kind]] <- neon_tile_index(snapshot$files, products[[kind]])
    snapshot_paths <- c(snapshot_paths, path)
    rows[[length(rows) + 1L]] <- data.frame(site = site, product = products[[kind]],
      month = month, release = release, files = nrow(snapshot$files),
      spatial_tiles = nrow(tiles[[kind]]), total_bytes = sum(as.numeric(snapshot$files$size)),
      retrieved_utc = format(file.info(path)$mtime, tz = "UTC", usetz = TRUE))
  }
  if (mode == "coverage") {
    nd <- file.path(.job_dir(), "neon", site)
    gt <- read.csv(file.path(nd, "ground_truth_stems.csv"))
    pc <- read.csv(file.path(nd, "plot_centroids.csv"))
    c <- eastern_tile_coverage(eastern_field_candidates(gt, pc, 2022L), pc,
                               tiles$lidar, tiles$rgb)
    vst_path <- file.path(nd, "vst", paste0(tolower(site), "_vst_allyears.rds"))
    s <- eastern_sampling_support(pc, readRDS(vst_path)$vst_perplotperyear, 2022L)
    s$site <- site
    support[[site]] <- s
    c <- merge(c, s[, setdiff(names(s), "site")], by = "plot", sort = TRUE)
    c$site <- site
    c$role <- if (site == "HARV") "development" else "held_out"
    candidates[[site]] <- c
    snapshot_paths <- c(snapshot_paths, vst_path,
                       file.path(nd, c("ground_truth_stems.csv", "plot_centroids.csv")))
  }
}
neon_check_manifest(file.path(out, paste0(mode, "_contract.json")),
  list(month = month, release = release, files = snapshot_paths,
       md5 = unname(tools::md5sum(snapshot_paths)),
       protocol_md5 = unname(tools::md5sum(file.path(.ROOT, "docs", "eastern-preflight-protocol.md"))),
       code_md5 = unname(tools::md5sum(vapply(c("preflight_eastern_coverage.R",
         "neon_acquisition_lib.R", "eastern_preflight_lib.R", "neon_spatial_lib.R"), .find, character(1))))))
write.csv(do.call(rbind, rows), file.path(out, "released_availability.csv"), row.names = FALSE)
if (mode == "coverage") {
  all <- do.call(rbind, candidates)
  write.csv(all, file.path(out, "plot_coverage_candidates.csv"), row.names = FALSE)
  write.csv(do.call(rbind, support), file.path(out, "sampling_support.csv"), row.names = FALSE)
  print(aggregate(cbind(n_exact_core, field_candidate, coverage_candidate) ~ site, all, sum), row.names = FALSE)
  eligible <- candidates$HARV$plot[candidates$HARV$coverage_candidate]
  if (length(eligible)) {
    smoke <- sort(eligible)[1]
    selected <- list(site = "HARV", plot = smoke, month = month, release = release,
                     selection = "lexicographically_first_field_and_listed_coverage_candidate",
                     coverage_md5 = unname(tools::md5sum(file.path(out, "plot_coverage_candidates.csv"))))
    neon_check_manifest(file.path(out, "smoke_selection.json"), selected)
    cat("Metadata-selected HARV smoke plot:", smoke, "\n")
  } else cat("No HARV plot meets the declared field and listed tile-coverage rules.\n")
}
cat("Released file metadata archived without signed URLs. Actual tile coverage, headers,\n")
cat("leaf-on and density checks are still required. Census area is not proof of a complete\n")
cat("scoring footprint; inspect sampling_support.csv. The eligible split is not frozen.\n")
