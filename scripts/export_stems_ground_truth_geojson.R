#!/usr/bin/env Rscript
.bs_ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (!is.null(.bs_ofile) && length(.bs_ofile) && nzchar(.bs_ofile))
    file.path(dirname(.bs_ofile), "bootstrap.R"),
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])),
                                  "bootstrap.R"),
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_ofile, .bs_file)

# Export a WGS84 stem reference layer for the treetop benchmark. Unlike the
# original data/stems.geojson, this keeps the stems that were filtered out of the
# detection ground-truth denominator and records why.
#
# Ground-truth inclusion is the declared population of the sealed frozen root
# (freeze_clips.R), exactly as every detector scores it: a stem is used when it
# is in population_stems.csv for POP (default adopted: live mapped tree with
# DBH >= 10 cm, inside the plot-type scoring core of a plot holding >= 6 such
# trees). Each stem also carries its membership in every declared population.
#
# Usage:
#   Rscript scripts/export_stems_ground_truth_geojson.R \
#     [SITES=SJER,SOAP,TEAK] [OUT=work/neon/best_treetops_geojson] \
#     [POP=adopted] [FROZEN_ROOT=...]
# Writes:
#   OUT/stems.geojson
#   OUT/stems_ground_truth_used.geojson
#   OUT/stems_filtered_out.geojson
suppressMessages(library(sf))

d <- .job_dir()
source(.find("sweep_lib.R")) # plot_half()
source(.find("model_bench_lib.R")) # frozen root and populations

args <- strsplit(commandArgs(TRUE), "=")
A <- setNames(lapply(args, `[`, 2), sapply(args, `[`, 1))
SITES <- if (is.null(A$SITES)) c("SJER", "SOAP", "TEAK") else strsplit(A$SITES, ",")[[1]]
OUT <- if (is.null(A$OUT)) file.path(d, "neon", "best_treetops_geojson") else A$OUT
POP <- if (is.null(A$POP)) "adopted" else A$POP
ROOT <- frozen_root(d, A$FROZEN_ROOT)
if (!frozen_sealed(ROOT)) stop("No sealed frozen root at ", ROOT, "; run scripts/freeze_clips.R first")
POP_STEMS <- read.csv(file.path(ROOT, "population_stems.csv"), stringsAsFactors = FALSE)
invisible(frozen_population_spec(POP))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

add_reason <- function(reasons, idx, label) {
  if (!any(idx, na.rm = TRUE)) return(reasons)
  reasons[idx] <- Map(function(x) c(x, label), reasons[idx])
  reasons
}

site_stems <- function(site) {
  nd <- file.path(d, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  # Dead D17 stems sit in plots without centroids; check the frame on live trees.
  epsg <- neon_validate_inputs(ext_live_trees(gt), pc)

  coord_ok <- !is.na(gt$E) & !is.na(gt$N)
  live_tree_coord <- (gt$live %in% TRUE) & (gt$is_tree %in% TRUE) & coord_ok
  stem_key <- paste(gt$plotID, gt$individualID)
  member <- function(p) stem_key %in% with(POP_STEMS[POP_STEMS$site == site &
                                                      POP_STEMS$population == p, ],
                                           paste(plotID, individualID))
  gt$.row <- seq_len(nrow(gt))
  gate_ok <- gt$.row %in% frozen_reference(gt, POP)$.row  # the population's stem gate
  pop_plots <- frozen_population(ROOT, site, POP)$plotID
  live_plot_count <- table(gt$plotID[live_tree_coord])
  n_live_plot <- as.integer(live_plot_count[match(gt$plotID, names(live_plot_count))])
  n_live_plot[is.na(n_live_plot)] <- 0L

  mi <- match(gt$plotID, pc$plotID)
  has_centroid <- !is.na(mi)
  plot_type <- ifelse(has_centroid, pc$plotType[mi], NA_character_)
  cx <- ifelse(has_centroid, pc$easting[mi], NA_real_)
  cy <- ifelse(has_centroid, pc$northing[mi], NA_real_)
  core_half <- ifelse(has_centroid, plot_half(plot_type), NA_real_)
  in_core <- has_centroid & coord_ok &
    abs(gt$E - cx) <= core_half & abs(gt$N - cy) <= core_half
  in_pop_plot <- gt$plotID %in% pop_plots
  ground_truth_used <- member(POP)
  if (any(ground_truth_used & !(live_tree_coord & gate_ok & in_pop_plot & in_core)))
    stop("Population stems disagree with the stem gate, plots or core of ", site)

  reasons <- rep(list(character()), nrow(gt))
  reasons <- add_reason(reasons, !(gt$live %in% TRUE), "not_live_or_stale_measurement")
  reasons <- add_reason(reasons, !(gt$is_tree %in% TRUE), "not_tree_growth_form")
  reasons <- add_reason(reasons, !coord_ok, "missing_coordinates")
  reasons <- add_reason(reasons, !has_centroid, "missing_plot_centroid")
  reasons <- add_reason(reasons, live_tree_coord & !gate_ok,
                        paste0("outside_", POP, "_stem_gate"))
  reasons <- add_reason(reasons, live_tree_coord & has_centroid & !in_pop_plot,
                        paste0("plot_outside_", POP, "_population"))
  reasons <- add_reason(reasons, live_tree_coord & has_centroid & in_pop_plot & !in_core,
                        "outside_scoring_core")
  filter_reason <- vapply(reasons, paste, character(1), collapse = ";")
  filter_reason[ground_truth_used] <- "used_for_ground_truth"

  keep <- coord_ok
  df <- data.frame(
    individualID = gt$individualID[keep],
    site = site,
    plotID = gt$plotID[keep],
    plotType = plot_type[keep],
    taxonID = gt$taxonID[keep],
    scientificName = gt$scientificName[keep],
    height = gt$height[keep],
    stemDiameter = gt$stemDiameter[keep],
    plantStatus = gt$plantStatus[keep],
    canopyPosition = gt$canopyPosition[keep],
    crown_class = gt$crown_class[keep],
    live = gt$live[keep],
    is_tree = gt$is_tree[keep],
    meas_year = gt$meas_year[keep],
    dist21 = gt$dist21[keep],
    pos_unc = gt$pos_unc[keep],
    n_live_tree_plot = n_live_plot[keep],
    scoring_core_half_m = core_half[keep],
    in_scoring_core = in_core[keep],
    population = POP,
    in_adopted = member("adopted")[keep],
    in_all_mapped = member("all_mapped")[keep],
    in_relaxed = member("relaxed")[keep],
    ground_truth_used = ground_truth_used[keep],
    filtered_out = !ground_truth_used[keep],
    filter_reason = filter_reason[keep],
    E = gt$E[keep],
    N = gt$N[keep],
    stringsAsFactors = FALSE)

  sf::st_transform(sf::st_as_sf(df, coords = c("E", "N"), crs = epsg,
                                remove = FALSE), 4326)
}

layers <- lapply(SITES, site_stems)
stems <- do.call(rbind, layers)
used <- stems[stems$ground_truth_used %in% TRUE, ]
filtered <- stems[stems$filtered_out %in% TRUE, ]

write_gj <- function(x, file) {
  sf::st_write(x, file.path(OUT, file), driver = "GeoJSON", delete_dsn = TRUE,
               quiet = TRUE,
               layer_options = c("RFC7946=YES", "COORDINATE_PRECISION=7"))
  cat(sprintf("  %-26s %5d features -> %s\n", file, nrow(x), file.path(OUT, file)))
}

cat(sprintf("Writing stem GeoJSON for %s:\n", paste(SITES, collapse = ", ")))
write_gj(stems, "stems.geojson")
write_gj(used, "stems_ground_truth_used.geojson")
write_gj(filtered, "stems_filtered_out.geojson")
cat(sprintf("ground_truth_used=%d filtered_out=%d total=%d\n",
            sum(stems$ground_truth_used), sum(stems$filtered_out), nrow(stems)))
