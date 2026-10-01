#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_acquisition_lib.R"))
source(.find("site_extension_lib.R"))

# Go/no-go evidence for adding NEON sites to the density ladder. Counts the
# reference each candidate would add under the sweep's own gates, archives the
# released LiDAR file list (no signed URLs), checks listed tiles cover every
# admitted clip, and reads one 2021 tile per site for sensor, CRS and native
# density. For candidates it also reports pre-acquisition census disturbance
# (thinning/harvest remarks, removals) and the status history of the scored
# reference. REFERENCE sites are inventoried only, for comparison. Run
# neon_ground_truth.R for every site first. Downloads at most one tile per
# candidate site; the full tile set comes from neon_download_lidar.R.
#   Rscript scripts/preflight_site_extension.R SITES=WREF,ABBY YEAR=2021 \
#     MONTH=2021-07 REFERENCE=SJER,SOAP,TEAK [HEADER=TRUE] [OUT=...]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
sites <- split_arg(A$SITES, "WREF,ABBY")
reference <- split_arg(A$REFERENCE, "SJER,SOAP,TEAK")
year <- neon_year(if (is.null(A$YEAR)) 2021 else A$YEAR)
month <- if (is.null(A$MONTH)) sprintf("%d-07", year) else A$MONTH
if (substr(month, 1, 4) != as.character(year)) stop("MONTH must fall in YEAR")
header <- isTRUE(as.logical(if (is.null(A$HEADER)) "TRUE" else A$HEADER))
release <- "RELEASE-2026"; product <- "DP1.30003.001"
cutoff <- as.Date(paste0(month, "-01"))   # census records before the acquisition month
out <- if (is.null(A$OUT)) file.path(.job_dir(), "neon", sprintf("site_extension_%d", year)) else A$OUT
dir.create(out, recursive = TRUE, showWarnings = FALSE)

# Candidates must pass the current frame and epoch checks. Reference sites are
# read as the historical sweep read them: the legacy D17 files predate those
# checks and hold dead stems in plots without centroids, which no gate admits.
field <- function(site, candidate) {
  nd <- file.path(.job_dir(), "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  if (candidate) neon_validate_inputs(gt, pc)
  neon_reference_epoch(gt, year)
  list(gt = gt, pc = pc, files = file.path(nd, c("ground_truth_stems.csv", "plot_centroids.csv")),
       vst = file.path(nd, "vst", paste0(tolower(site), "_vst_allyears.rds")))
}

# A gate that admits nothing yields empty tables, not an abort: "no plots" is
# a valid no-go outcome and must still reach the CSVs.
tab_rows <- function(site, gate, tab) {
  tab <- as.data.frame(tab, stringsAsFactors = FALSE)
  if (nrow(tab)) data.frame(site = site, gate = gate, tab, stringsAsFactors = FALSE)
}
bind_rows0 <- function(rows, cols) {
  rows <- Filter(Negate(is.null), rows)
  if (length(rows)) do.call(rbind, rows) else
    setNames(data.frame(matrix(nrow = 0, ncol = length(cols))), cols)
}

inputs <- character(); fields <- list()
inv_rows <- list(); sum_rows <- list(); class_rows <- list(); year_rows <- list()
dist_rows <- list(); hist_rows <- list()
for (site in c(reference, sites)) {
  f <- fields[[site]] <- field(site, site %in% sites); inputs <- c(inputs, f$files)
  if (site %in% sites) {
    inputs <- c(inputs, f$vst)
    ai <- readRDS(f$vst)$vst_apparentindividual
    adm_any <- character()
  }
  for (gate in EXT_GATES) {
    g <- ext_gate(f$gt, gate)
    inv <- ext_plot_inventory(g, f$pc)
    cs <- ext_core_stems(g, inv)
    if (nrow(inv)) { inv$site <- site; inv$gate <- gate }
    inv_rows[[paste(site, gate)]] <- inv
    sum_rows[[paste(site, gate)]] <- ext_site_summary(inv, site, gate)
    cs$crown_class[is.na(cs$crown_class)] <- "unclassified"
    class_rows[[paste(site, gate)]] <- tab_rows(site, gate,
      table(crown_source = cs$crown_source, crown_class = cs$crown_class))
    year_rows[[paste(site, gate)]] <- tab_rows(site, gate, table(meas_year = cs$meas_year))
    if (site %in% sites) {
      adm <- inv$plotID[inv$admitted]; adm_any <- union(adm_any, adm)
      if (length(adm)) {
        db <- ext_disturbance_by_plot(ai, adm, cutoff)
        h <- ext_core_status_history(ai, cs, db, cutoff)
        if (nrow(h)) hist_rows[[paste(site, gate)]] <- data.frame(site = site, gate = gate, h)
      }
    }
  }
  if (site %in% sites && length(adm_any)) {
    db <- ext_disturbance_by_plot(ai, adm_any, cutoff)
    db$site <- site
    db$admitted_gates <- vapply(db$plotID, function(p) paste(EXT_GATES[vapply(EXT_GATES,
      function(gt) any(inv_rows[[paste(site, gt)]]$admitted &
                       inv_rows[[paste(site, gt)]]$plotID == p), logical(1))], collapse = ";"),
      character(1))
    dist_rows[[site]] <- db
  }
}
inv <- do.call(rbind, Filter(nrow, inv_rows))
inv$tiles_needed <- NA_character_; inv$tiles_listed <- NA
class_tab <- bind_rows0(class_rows, c("site", "gate", "crown_source", "crown_class", "Freq"))
class_tab <- class_tab[class_tab$Freq > 0, , drop = FALSE]

listing_rows <- list(); header_rows <- list(); plot_dens <- list(); live <- list()
dl_rows <- list()
for (site in sites) {
  path <- file.path(out, paste0(site, "_lidar_files.json"))
  if (!file.exists(path)) {
    live[[site]] <- neon_released_files(product, site, month, release)
    neon_archive_listing(live[[site]], path)
  }
  snap <- jsonlite::read_json(path, simplifyVector = TRUE)
  if (!identical(snap$product, product) || !identical(snap$site, site) ||
      !identical(snap$month, month) || !identical(snap$release, release))
    stop("Cached file list does not match the declared acquisition")
  tiles <- neon_tile_index(snap$files, product)
  inputs <- c(inputs, path)
  listing_rows[[site]] <- data.frame(site = site, product = product, month = month,
    release = release, files = nrow(snap$files), spatial_tiles = nrow(tiles),
    median_tile_mb = round(median(as.numeric(tiles$size)) / 1e6, 1),
    retrieved_utc = format(file.info(path)$mtime, tz = "UTC", usetz = TRUE))
  k <- inv$site == site
  cv <- ext_tile_coverage(inv[k, ], tiles)
  inv$tiles_needed[k] <- cv$tiles_needed; inv$tiles_listed[k] <- cv$tiles_listed
  # After neon_download_lidar.R: verify the downloaded set against the listing.
  laz <- list.files(file.path(.job_dir(), "neon", site, "lidar"), "[.]laz$",
                    recursive = TRUE, full.names = TRUE)
  if (length(laz)) {
    needed <- unique(unlist(strsplit(inv$tiles_needed[k & inv$admitted], ";", fixed = TRUE)))
    au <- ext_download_audit(laz, tiles, needed)
    dl_rows[[site]] <- data.frame(site = site, au$files)
    if (length(au$missing)) warning(site, " lacks needed tiles: ", paste(au$missing, collapse = ", "))
  }
  if (!header) next

  # One tile per site: the listed tile wholly containing the most admitted clips.
  a <- inv[k & inv$gate == "all_mapped", ]
  pick <- ext_header_tile(a, listed = tiles$key)
  if (is.null(pick)) {
    warning(site, ": no admitted clip lies inside one listed tile; header check skipped")
    next
  }
  row <- tiles[tiles$key == pick$key, ]
  dest <- file.path(out, site, row$name)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  if (!ext_file_matches(dest, row)) {
    if (is.null(live[[site]])) live[[site]] <- neon_released_files(product, site, month, release)
    url <- live[[site]]$files$url[live[[site]]$files$name == row$name]
    options(timeout = 3600)
    utils::download.file(url, dest, mode = "wb", quiet = TRUE)
    rm(url)
  }
  if (!ext_file_matches(dest, row)) stop("Header tile checksum differs: ", row$name)
  hdr <- lidR::readLASheader(dest)
  neon_assert_crs(hdr, neon_field_epsg(fields[[site]]$pc), row$name)
  las <- lidR::readLAS(dest, select = "xyzrc")
  keep <- !las$Classification %in% c(7L, 18L)       # drop low and high noise
  dens <- ext_occupied_density(las$X[keep], las$Y[keep], las$ReturnNumber[keep])
  header_rows[[site]] <- cbind(ext_header_row(hdr, site, dest),
    data.frame(tile = pick$key, occupied_m2 = dens[["occupied_m2"]],
               all_return_density = dens[["all_returns"]],
               first_return_density = dens[["first_returns"]],
               ground_share = mean(las$Classification[keep] == 2L)))
  rm(las); gc(verbose = FALSE)

  # Native density on the sweep's own clip (sweep_lib.R prepare_clip): the
  # pdens/frdens units that gate the ladder and CHM resolution.
  if (!exists("prepare_clip")) source(.find("sweep_lib.R"))
  if (BUF != EXT_CLIP_BUF) stop("sweep_lib.R BUF differs from EXT_CLIP_BUF")
  ctg <- lidR::readLAScatalog(dest)
  lidR::opt_progress(ctg) <- FALSE
  tmp <- file.path(tempdir(), "site_extension"); dir.create(tmp, showWarnings = FALSE)
  for (p in pick$plots) {
    ci <- a[a$plotID == p, ]
    pr <- prepare_clip(ctg, ci$easting, ci$northing, NA, tmp, core_half = ci$core_half)
    if (is.null(pr)) next
    plot_dens[[paste(site, p)]] <- data.frame(site = site, plotID = p, plotType = ci$plotType,
      tile = pick$key, pdens = pr$pdens, frdens = pr$frdens)
    unlink(pr$file)
  }
}

code <- vapply(c("preflight_site_extension.R", "site_extension_lib.R", "neon_acquisition_lib.R",
                 "neon_spatial_lib.R", "sweep_lib.R"), .find, character(1))
neon_check_manifest(file.path(out, "preflight_contract.json"),
  list(sites = sites, reference = reference, year = year, month = month, release = release,
       header = header, inputs = inputs, input_md5 = unname(tools::md5sum(inputs)),
       code_md5 = unname(tools::md5sum(code))))
# Optional outputs from an earlier run must not survive next to fresh summaries.
unlink(file.path(out, c("header_tiles.csv", "header_plot_density.csv", "downloaded_tiles.csv")))

summ <- do.call(rbind, sum_rows)
write.csv(inv, file.path(out, "plot_inventory.csv"), row.names = FALSE)
write.csv(summ, file.path(out, "site_summary.csv"), row.names = FALSE)
write.csv(class_tab, file.path(out, "core_crown_class.csv"), row.names = FALSE)
write.csv(bind_rows0(year_rows, c("site", "gate", "meas_year", "Freq")),
          file.path(out, "core_measurement_year.csv"), row.names = FALSE)
write.csv(bind_rows0(dist_rows, c("plotID", "disturbance_records", "first_disturbance",
                                  "last_disturbance", "removed_individuals", "removed_dbh10",
                                  "removed_max_height", "site", "admitted_gates")),
          file.path(out, "disturbance_by_plot.csv"), row.names = FALSE)
hist <- bind_rows0(hist_rows, c("site", "gate", "individualID", "plotID", "meas_year",
                                "any_nonlive_before", "last_before_status",
                                "last_before_nonlive", "scored_before_disturbance"))
write.csv(hist, file.path(out, "core_status_history.csv"), row.names = FALSE)
write.csv(do.call(rbind, listing_rows), file.path(out, "released_listing.csv"), row.names = FALSE)
if (length(header_rows))
  write.csv(do.call(rbind, header_rows), file.path(out, "header_tiles.csv"), row.names = FALSE)
if (length(plot_dens))
  write.csv(do.call(rbind, plot_dens), file.path(out, "header_plot_density.csv"), row.names = FALSE)
if (length(dl_rows))
  write.csv(do.call(rbind, dl_rows), file.path(out, "downloaded_tiles.csv"), row.names = FALSE)

print(summ[, c("site", "gate", "plots_admitted", "stems_core_admitted",
               "canopy_position_share")], row.names = FALSE)
cov <- inv[inv$site %in% sites & inv$admitted, ]
cat(sprintf("admitted clips with every tile listed: %d / %d\n",
            sum(cov$tiles_listed), nrow(cov)))
if (length(header_rows)) print(do.call(rbind, header_rows)[, c("site", "tile",
  "system_identifier", "epsg", "all_return_density", "first_return_density")], row.names = FALSE)
if (length(plot_dens)) print(do.call(rbind, plot_dens), row.names = FALSE)
for (d in dist_rows)
  cat(sprintf("%s before %s: %d admitted plots with disturbance remarks, %d removed individuals (%d ever >= 10 cm DBH)\n",
              d$site[1], cutoff, sum(d$disturbance_records > 0), sum(d$removed_individuals),
              sum(d$removed_dbh10)))
if (nrow(hist)) print(aggregate(cbind(stems = 1L, any_nonlive_before, last_before_nonlive,
                                      scored_before_disturbance) ~ site + gate, hist, sum),
                      row.names = FALSE)
for (site in names(dl_rows)) {
  d <- dl_rows[[site]]
  cat(sprintf("%s downloaded tiles: %d, verified %d, needed and verified %d / %d\n", site,
              nrow(d), sum(d$verified), sum(d$needed & d$verified),
              length(unique(unlist(strsplit(inv$tiles_needed[inv$site == site & inv$admitted],
                                            ";", fixed = TRUE))))))
}
cat("Listed tiles are not a physical coverage audit; nominal cores are not census support.\n")
