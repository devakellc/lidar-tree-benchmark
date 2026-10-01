# Site-extension preflight helpers: count the field-stem reference a new NEON
# site would add under the sweep's own gates (run_sweep.R), check that listed
# LiDAR tiles cover every admitted clip, and summarise one tile header, before
# any arm runs. Pure functions; the driver is preflight_site_extension.R.

EXT_MIN_TREES <- 6L   # run_sweep.R MINTREES: live mapped trees per plot
EXT_CLIP_BUF  <- 25   # sweep_lib.R BUF: clip buffer beyond the plot core

# Nominal core half-extent, as sweep_lib.R plot_half(): tower +/-20 m,
# distributed +/-10 m. A nominal box is not proof of a complete census.
ext_core_half <- function(plotType) ifelse(plotType == "tower", 20, 10)

# Live mapped trees exactly as run_sweep.R admits them.
ext_live_trees <- function(gt) {
  gt[gt$live & gt$is_tree & is.finite(gt$E) & is.finite(gt$N), , drop = FALSE]
}

# Reference gates. "all_mapped" is the historical sweep population;
# "dbh10" drops stems below 10 cm DBH (or without a DBH) before the six-stem
# gate, the size class holding 96% of the D17 core reference (673 of 699).
EXT_GATES <- c("all_mapped", "dbh10")
ext_gate <- function(gt, gate = EXT_GATES) {
  gate <- match.arg(gate)
  if (gate == "all_mapped") return(gt)
  gt[!is.na(gt$stemDiameter) & gt$stemDiameter >= 10, , drop = FALSE]
}

# Crown-class provenance: NEON canopyPosition, the within-plot height-quantile
# fallback in neon_ground_truth.R, or none.
ext_crown_source <- function(gt) {
  cp <- !is.na(gt$canopyPosition) & nzchar(gt$canopyPosition)
  ifelse(cp & !is.na(gt$crown_class), "canopyPosition",
         ifelse(!is.na(gt$crown_class), "height_fallback", "none"))
}

# One row per plot holding at least one live mapped tree. `admitted` applies the
# sweep gate (whole-plot live-tree count); n_core counts the stems the scorer
# uses (inside the nominal core box), which is the per-plot n_ref.
ext_plot_inventory <- function(gt, pc, min_trees = EXT_MIN_TREES) {
  lt <- ext_live_trees(gt)
  if (any(!lt$plotID %in% pc$plotID)) stop("Live trees lack plot centroids")
  if (!nrow(lt)) return(data.frame(plotID = character(), plotType = character(),
    easting = numeric(), northing = numeric(), core_half = numeric(), n_live = integer(),
    n_live_dbh10 = integer(), n_core = integer(), n_core_dbh10 = integer(),
    n_core_canopy_position = integer(), n_core_height_fallback = integer(),
    n_core_no_class = integer(), admitted = logical()))
  src <- ext_crown_source(lt)
  plots <- sort(unique(lt$plotID))
  do.call(rbind, lapply(plots, function(p) {
    i <- lt$plotID == p
    ci <- pc[match(p, pc$plotID), ]
    half <- ext_core_half(ci$plotType)
    core <- i & abs(lt$E - ci$easting) <= half & abs(lt$N - ci$northing) <= half
    big <- !is.na(lt$stemDiameter) & lt$stemDiameter >= 10
    data.frame(plotID = p, plotType = ci$plotType, easting = ci$easting,
               northing = ci$northing, core_half = half,
               n_live = sum(i), n_live_dbh10 = sum(i & big),
               n_core = sum(core), n_core_dbh10 = sum(core & big),
               n_core_canopy_position = sum(core & src == "canopyPosition"),
               n_core_height_fallback = sum(core & src == "height_fallback"),
               n_core_no_class = sum(core & src == "none"),
               admitted = sum(i) >= min_trees, stringsAsFactors = FALSE)
  }))
}

# Site totals. stems_core_admitted is the pooled recall denominator the ladder
# would score; it is comparable with the D17 n_ref sums.
ext_site_summary <- function(inv, site, gate = "all_mapped") {
  a <- inv[inv$admitted, , drop = FALSE]
  data.frame(site = site, gate = gate, plots_with_live = nrow(inv), live_mapped = sum(inv$n_live),
             live_mapped_dbh10 = sum(inv$n_live_dbh10),
             plots_admitted = nrow(a),
             plots_admitted_tower = sum(a$plotType == "tower"),
             plots_admitted_distributed = sum(a$plotType == "distributed"),
             stems_admitted = sum(a$n_live), stems_core_admitted = sum(a$n_core),
             stems_core_admitted_dbh10 = sum(a$n_core_dbh10),
             core_canopy_position = sum(a$n_core_canopy_position),
             core_height_fallback = sum(a$n_core_height_fallback),
             core_no_class = sum(a$n_core_no_class),
             canopy_position_share = if (sum(a$n_core)) sum(a$n_core_canopy_position) /
               sum(a$n_core) else NA_real_)
}

# Live mapped stems inside the cores of admitted plots: the scored reference.
ext_core_stems <- function(gt, inv) {
  lt <- ext_live_trees(gt)
  a <- inv[inv$admitted, , drop = FALSE]
  m <- match(lt$plotID, a$plotID)
  keep <- !is.na(m) & abs(lt$E - a$easting[m]) <= a$core_half[m] &
    abs(lt$N - a$northing[m]) <= a$core_half[m]
  out <- lt[keep, , drop = FALSE]
  out$crown_source <- ext_crown_source(out)
  out
}

# Listed coverage of every admitted clip (core + sweep buffer). `tiles` is a
# neon_tile_index() table; a plot is covered only if every intersected 1 km
# tile is listed.
ext_tile_coverage <- function(inv, tiles, buffer = EXT_CLIP_BUF) {
  inv$tiles_needed <- vapply(seq_len(nrow(inv)), function(i)
    paste(neon_required_tiles(inv$easting[i], inv$northing[i],
                              inv$core_half[i] + buffer), collapse = ";"),
    character(1))
  inv$tiles_listed <- vapply(strsplit(inv$tiles_needed, ";", fixed = TRUE),
                             function(k) all(k %in% tiles$key), logical(1))
  inv
}

# The header tile: the listed tile wholly containing the most admitted clips,
# ties broken by core stems and then key, so the choice is reproducible.
# NULL when no admitted clip lies inside a single listed tile.
ext_header_tile <- function(inv, listed, buffer = EXT_CLIP_BUF) {
  a <- inv[inv$admitted, , drop = FALSE]
  if (!nrow(a)) return(NULL)
  one <- vapply(seq_len(nrow(a)), function(i) {
    k <- neon_required_tiles(a$easting[i], a$northing[i], a$core_half[i] + buffer)
    if (length(k) == 1L && k %in% listed) k else NA_character_
  }, character(1))
  if (all(is.na(one))) return(NULL)
  d <- data.frame(key = one, stems = a$n_core)[!is.na(one), , drop = FALSE]
  s <- do.call(rbind, lapply(split(d, d$key), function(x)
    data.frame(key = x$key[1], plots = nrow(x), stems = sum(x$stems))))
  s <- s[order(-s$plots, -s$stems, s$key), ]
  list(key = s$key[1], plots = a$plotID[!is.na(one) & one == s$key[1]])
}

# Sensor and format fields from a lidR LASheader, plus whole-tile densities
# over the occupied area (count of `res` m cells holding a point), so a partly
# flown edge tile is not diluted by empty ground.
ext_header_row <- function(hdr, site, file) {
  phb <- hdr@PHB
  by_ret <- phb[["Number of points by return"]]
  data.frame(site = site, file = basename(file),
             las_version = paste0(phb[["Version Major"]], ".", phb[["Version Minor"]]),
             point_format = phb[["Point Data Format ID"]],
             system_identifier = trimws(phb[["System Identifier"]]),
             generating_software = trimws(phb[["Generating Software"]]),
             creation = sprintf("%d-%03d", phb[["File Creation Year"]],
                                phb[["File Creation Day of Year"]]),
             epsg = sf::st_crs(hdr)$epsg,
             n_points = phb[["Number of point records"]],
             n_first_header = if (length(by_ret)) by_ret[1] else NA_real_,
             stringsAsFactors = FALSE)
}

ext_occupied_density <- function(x, y, return_number, res = 5) {
  if (!length(x)) stop("Empty point set")
  cell <- paste(floor(x / res), floor(y / res))
  area <- length(unique(cell)) * res^2
  c(occupied_m2 = area, all_returns = length(x) / area,
    first_returns = sum(return_number == 1L) / area)
}

# NEON listings drop leading zeros from crc32c ("79f3c9f" for 079f3c9f).
ext_crc_norm <- function(x) {
  x <- tolower(as.character(x))
  paste0(strrep("0", pmax(0L, 8L - nchar(x))), x)
}

# A downloaded file matches its listing row by size and by crc32c (NEON cloud
# listings) or md5, whichever the listing carries.
ext_file_matches <- function(path, row) {
  if (!file.exists(path) || file.size(path) != as.numeric(row$size)) return(FALSE)
  crc <- if (is.null(row$crc32c)) NA_character_ else row$crc32c
  md5 <- if (is.null(row$md5)) NA_character_ else row$md5
  if (!is.na(crc)) {
    got <- digest::digest(file = path, algo = "crc32c")
    return(identical(ext_crc_norm(got), ext_crc_norm(crc)))
  }
  if (!is.na(md5)) return(identical(unname(tools::md5sum(path)), tolower(md5)))
  stop("Listing carries no checksum for ", basename(path))
}

# Downloaded tiles against the archived listing: each file must be listed and
# match its checksum, and every tile an admitted clip needs must be present.
ext_download_audit <- function(files, tiles, needed) {
  rows <- tiles[match(basename(files), tiles$name), , drop = FALSE]
  got <- data.frame(name = basename(files), key = rows$key,
                    stringsAsFactors = FALSE)
  got$listed <- !is.na(got$key)
  got$verified <- vapply(seq_along(files), function(i)
    got$listed[i] && ext_file_matches(files[i], rows[i, , drop = FALSE]), logical(1))
  got$needed <- !is.na(got$key) & got$key %in% needed
  list(files = got, missing = sort(setdiff(needed, got$key[got$verified])))
}

# Census remarks recording forest management. Word-bounded so that, e.g.,
# "No longer falls within reduced nested size" is not read as thinning, and
# tolerant of the misspellings in the ABBY records ("Thining", "thinnng").
# Self-thinning and crown or branch condition notes are not management.
EXT_DISTURBANCE <- paste0("\\bthin+(i?n+g|ed)\\b|\\bharvest(ed|ing)?\\b|\\blogg(ed|ing)\\b|",
                          "clear.?cut|\\bclearing\\b|\\bsever(ed)?\\b|\\bbole cut\\b|^cut\\.?$|",
                          "\\bcut (down|during|from)\\b|\\bfelled\\b")
EXT_NOT_DISTURBANCE <- "self-thinning|^\\s*thinning (crown|branches|lower branches)"
ext_is_disturbance <- function(remarks) {
  !is.na(remarks) & grepl(EXT_DISTURBANCE, remarks, ignore.case = TRUE) &
    !grepl(EXT_NOT_DISTURBANCE, remarks, ignore.case = TRUE)
}

# Per plot, before `cutoff` (a Date): records whose remarks match
# EXT_DISTURBANCE, and individuals recorded as removed, with how many of those
# ever reached 10 cm DBH and their tallest height on any record.
ext_disturbance_by_plot <- function(ai, plots, cutoff) {
  d <- as.Date(substr(ai$date, 1, 10))
  pre <- ai[!is.na(d) & d < cutoff & ai$plotID %in% plots, , drop = FALSE]
  pre_d <- d[!is.na(d) & d < cutoff & ai$plotID %in% plots]
  hit <- ext_is_disturbance(pre$remarks)
  rem <- grepl("^Removed", pre$plantStatus)
  big <- unique(ai$individualID[!is.na(ai$stemDiameter) & ai$stemDiameter >= 10])
  do.call(rbind, lapply(sort(unique(plots)), function(p) {
    i <- pre$plotID == p
    k <- i & hit
    removed <- unique(pre$individualID[i & rem])
    h <- ai$height[ai$individualID %in% removed & !is.na(ai$height)]
    data.frame(plotID = p, disturbance_records = sum(k),
               first_disturbance = if (any(k)) as.character(min(pre_d[k])) else NA_character_,
               last_disturbance = if (any(k)) as.character(max(pre_d[k])) else NA_character_,
               removed_individuals = length(removed),
               removed_dbh10 = length(intersect(removed, big)),
               removed_max_height = if (length(h)) max(h) else NA_real_, stringsAsFactors = FALSE)
  }))
}

# Status history of the scored reference before `cutoff`. The nearest-record
# rule in neon_ground_truth.R scores a stem as live from its record nearest
# the acquisition year, so flag stems that (a) have any earlier non-live
# record, (b) whose last record before the cutoff is not live, and (c) whose
# scored year ends before their plot's last disturbance remark.
ext_core_status_history <- function(ai, cs, disturb, cutoff) {
  a <- ai[ai$individualID %in% cs$individualID, , drop = FALSE]
  a$d <- as.Date(substr(a$date, 1, 10))
  a <- a[!is.na(a$d), , drop = FALSE]
  pre <- a[a$d < cutoff, , drop = FALSE]
  # One row per bole: a tree is live on a date if any of its boles is.
  pre$live <- grepl("^Live", pre$plantStatus)
  pre <- pre[order(pre$individualID, pre$d, pre$live), , drop = FALSE]
  key <- paste(pre$individualID, pre$d)
  day_live <- tapply(pre$live, key, any)
  day <- pre[!duplicated(key, fromLast = TRUE), , drop = FALSE]  # Live bole last
  nonlive <- tapply(!day_live[paste(day$individualID, day$d)], day$individualID, any)
  last <- day[!duplicated(day$individualID, fromLast = TRUE), , drop = FALSE]
  scored <- a[as.integer(format(a$d, "%Y")) == cs$meas_year[match(a$individualID, cs$individualID)], ,
              drop = FALSE]
  scored_end <- tapply(scored$d, scored$individualID, max)
  out <- data.frame(individualID = cs$individualID, plotID = cs$plotID, meas_year = cs$meas_year,
                    stringsAsFactors = FALSE)
  out$any_nonlive_before <- nonlive[out$individualID] %in% TRUE
  out$last_before_status <- last$plantStatus[match(out$individualID, last$individualID)]
  out$last_before_nonlive <- !is.na(out$last_before_status) &
    !grepl("^Live", out$last_before_status)
  end <- as.Date(as.numeric(scored_end[out$individualID]), origin = "1970-01-01")
  ld <- as.Date(disturb$last_disturbance[match(out$plotID, disturb$plotID)])
  out$scored_before_disturbance <- !is.na(ld) & !is.na(end) & end < ld
  out
}
