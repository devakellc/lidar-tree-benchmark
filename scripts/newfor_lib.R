# Library of the NEWFOR Alpine validation of the gated multichm arm
# (docs/newfor-validation-protocol.md is the contract): the pinned release and
# its per-area metadata, one study area read from the raw release, its
# reference stems and their populations, the clip normalized on the released
# terrain raster, point densities, the detector-free registration diagnostic,
# the admission rules, the sealed freeze root and its read-back, scoring on the
# release's polygon with a chance-agreement null adapted to it, and the
# detection wrapper around the pinned detector (multichm_gated_lib.R).
#
# Units and populations. DBHRef is in metres in every file of the release
# (each file's range fits its caliper threshold only in metres), so the
# diameter in centimetres is 100 x DBHRef rounded to six decimals; HRef is in
# metres. A stem is inside when the scoring polygon covers it, boundary
# included. Primary: inside, a positive height and a diameter of at least
# 10 cm. Inventoried: inside with a positive height, whatever the diameter. A
# diameter of zero or less (or none) is missing: outside the primary
# population, inside the inventoried one. The release records no crown class,
# so recall is reported by height band. The bands are score_plot's, used
# unchanged: cut() at 8 and 15 m with right-closed intervals, so short is up to
# 8 m, mid above 8 up to 15 m and tall above 15 m; a stem of exactly 8.0 m
# (15.0 m) counts as short (mid), one band lower than the protocol's wording.
#
# The clip and the CRS. The clip is the polygon's bounding box widened by
# NEWFOR_BUFFER on every side, cut where the cloud ends; heights are elevations
# minus the released terrain raster read by bilinear interpolation. Clip-wide
# densities are counts over the area of the convex hull of the kept points
# (covered_area), not over the clip rectangle (clip_area): some released clouds
# are discs that do not fill the box, so the rectangle would understate their
# density. The plot
# sheet's projected CRS is assigned to the clip and the polygon and nothing is
# transformed: the released clouds and shapefiles carry none, and the terrain
# rasters of two areas carry a wrong one, so a raster's CRS is ignored and its
# coordinates are used as they are.
#
# The freeze root (one folder per area, sealed by freeze_manifest.csv):
#   <root>/<id>/normalized.laz       the clip, heights above terrain, canonical
#                                    point order (frozen_canonical), CRS assigned
#   <root>/<id>/aoi.wkt              the scoring polygon, one WKT line at 15
#                                    significant digits (the polygon every value
#                                    of the area was computed on)
#   <root>/<id>/reference_stems.csv  every inventory row with its flags
#                                    (newfor_reference)
#   <root>/<id>/cell.json            id, forest, epsg, buffer, box, clip, reach,
#                                    covered_area, clip_area, n_box, dropped,
#                                    n_points,
#                                    terrain_na_share, density (newfor_density),
#                                    res, registration (newfor_registration
#                                    without its scan), admission (the
#                                    newfor_admission row), raw_sha256 (the
#                                    area's nine raw files), read_warnings (lidR's
#                                    warnings when reading the raw cloud),
#                                    lidr_threads, point_order
#   <root>/freeze_manifest.csv       file (relative path), bytes, sha256 of every
#                                    other file under the root, sorted by path;
#                                    written last, it seals the root
# Other root files (admission.csv, registration_scan.csv, freeze.json) are
# written by the freeze driver before it seals; newfor_frozen_admission and
# newfor_frozen_record read the first and the last back.
#
# Sourced, not run. No side effects. The caller sources sweep_lib.R
# (score_plot, ws_factory), model_bench_lib.R (seed_for, frozen_canonical,
# frozen_sha256, FROZEN_POINT_ORDER, assert_detection_contract) and
# multichm_gated_lib.R (mcg_config, mcg_prepare, mcg_apply, mcg_closed,
# mcg_spaced, MCG_STOCK, MCG_DECLARED, MCG_COUNT_COLS) first; the analysis also
# master_tables_lib.R. The caller attaches lidR, lidRplugins, sf, terra,
# data.table and jsonlite.

## ---- constants -----------------------------------------------------------------------------
NEWFOR_SITE            <- "NEWFOR"   # one bootstrap stratum
NEWFOR_BUFFER          <- 25         # m beyond the polygon's bounding box
NEWFOR_Z_MIN           <- -1         # keep Z >= this
NEWFOR_Z_MAX           <- 80         # keep Z <  this
NEWFOR_DROP_CLASSES    <- c(7L, 18L)
NEWFOR_MIN_DBH_CM      <- 10
NEWFOR_TOL             <- 4          # matching tolerance (m)
NEWFOR_A               <- 0.10       # window coefficient
NEWFOR_RES_GATE        <- 8          # first returns per m2: >= gives 0.25 m, else 0.5 m
NEWFOR_MIN_REACH       <- 10         # admission: clip reach beyond the polygon bbox (m)
NEWFOR_MAX_TERRAIN_NA  <- 0.01       # admission: share of box points without terrain, must be below
NEWFOR_MAX_GAP_MONTHS  <- 48
NEWFOR_MIN_STEMS       <- 6
NEWFOR_MAX_OFFSET      <- 4.0        # admission: registration estimate (m), at most
NEWFOR_REG_RES         <- 0.5
NEWFOR_REG_TOP_RADIUS  <- 1.5
NEWFOR_REG_DOM_RADIUS  <- 4
NEWFOR_REG_RANGE       <- 8
NEWFOR_REG_STEP        <- 0.5
NEWFOR_DEV_FRDENS      <- c(5.2, 17.8)  # NEON development range, clip-wide first returns per m2
NEWFOR_NULL_K          <- 200
NEWFOR_NULL_MIN_SHIFT  <- 8
NEWFOR_HEIGHT_BANDS    <- c("short", "mid", "tall")   # score_plot's bands: <= 8, (8, 15], > 15 m

# The four files of an area folder (relative to it) and the seal of a root.
.NEWFOR_AREA_FILES <- c("normalized.laz", "aoi.wkt", "reference_stems.csv", "cell.json")
.NEWFOR_MANIFEST   <- "freeze_manifest.csv"
.NEWFOR_RULES <- c("rule_files", "rule_returns", "rule_terrain", "rule_buffer", "rule_heights",
                   "rule_gap", "rule_stems", "rule_registration")

## ---- configurations ------------------------------------------------------------------------
# The five configurations of the study, in this order: stock and declared (the
# pinned pair of the primary contrast) and the three that decompose declared.
# A changed pin in multichm_gated_lib.R (MCG_STOCK, MCG_DECLARED or the labels
# it gives) stops here instead of running another comparison.
newfor_configs <- function() {
  cfg <- list(stock = mcg_config(),
              declared = mcg_config(zmin = 5, min_share = 0.75, cover_min = 0.6,
                                    surface_exempt = TRUE, spacing_min = 8),
              floor = mcg_config(zmin = 5),
              floor_exempt = mcg_config(zmin = 5, cover_min = 0.6, surface_exempt = TRUE),
              gate_all = mcg_config(zmin = 5, min_share = 0.75, cover_min = 0.6,
                                    surface_exempt = TRUE))
  if (!identical(cfg$stock, MCG_STOCK))
    stop("newfor: MCG_STOCK is not the stock configuration this study pinned", call. = FALSE)
  if (!identical(cfg$declared, MCG_DECLARED))
    stop("newfor: MCG_DECLARED is not the declared configuration this study pinned",
         call. = FALSE)
  want <- c(stock = "stock", declared = "z5_s0.75_c0.6_e1_d8", floor = "z5_s0_c0_e0",
            floor_exempt = "z5_s0_c0.6_e1", gate_all = "z5_s0.75_c0.6_e1")
  got <- vapply(cfg, mcg_config_label, character(1))
  if (!identical(got, want))
    stop("newfor: the library labels the configurations ", paste(got, collapse = ", "),
         ", not the pinned ", paste(want, collapse = ", "), call. = FALSE)
  cfg
}

## ---- metadata and files --------------------------------------------------------------------
# Months since year 0 of "YYYY-MM" dates.
.newfor_months <- function(d) as.integer(substr(d, 1, 4)) * 12L + as.integer(substr(d, 6, 7))

# The pinned per-area facts: list(release, areas). Ids stay character ("01").
# Stops on duplicate or non-character ids, a missing field, an EPSG code that is
# not a positive whole number, a caliper that is not positive, or a date that is
# not YYYY-MM. Adds gap_months = flight minus field survey, in whole months.
newfor_metadata <- function(path) {
  if (!file.exists(path)) stop("newfor: metadata file not found: ", path, call. = FALSE)
  j <- jsonlite::read_json(path, simplifyVector = TRUE)
  bad <- function(...) stop("newfor: ", path, ": ", ..., call. = FALSE)
  if (!is.list(j$release) || !all(c("doi", "version") %in% names(j$release)))
    bad("the release record needs doi and version")
  a <- j$areas
  if (!is.data.frame(a) || !nrow(a)) bad("no areas")
  need <- c("id", "forest", "sheet", "epsg", "field_date", "flight_date", "caliper_cm")
  miss <- setdiff(need, names(a))
  if (length(miss)) bad("areas lack ", paste(miss, collapse = ", "))
  if (!is.character(a$id) || anyNA(a$id) || any(!nzchar(a$id)))
    bad("area ids must be non-empty strings")
  if (anyDuplicated(a$id)) bad("duplicate area ids: ", paste(unique(a$id[duplicated(a$id)]),
                                                            collapse = ", "))
  for (k in c("forest", "sheet"))
    if (!is.character(a[[k]]) || anyNA(a[[k]]) || any(!nzchar(a[[k]])))
      bad(k, " must be a non-empty string for every area")
  if (!is.numeric(a$epsg) || any(!is.finite(a$epsg)) || any(a$epsg <= 0) ||
      any(a$epsg != round(a$epsg)))
    bad("epsg must be a positive whole number for every area")
  a$epsg <- as.integer(a$epsg)
  if (!is.numeric(a$caliper_cm) || any(!is.finite(a$caliper_cm)) || any(a$caliper_cm <= 0))
    bad("caliper_cm must be positive for every area")
  for (k in c("field_date", "flight_date"))
    if (!is.character(a[[k]]) || any(!grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", a[[k]])))
      bad(k, " must be YYYY-MM for every area")
  a$gap_months <- .newfor_months(a$flight_date) - .newfor_months(a$field_date)
  list(release = j$release, areas = a)
}

# The pinned file list: data.frame filename, id, bytes, md5, sha256 (lower case).
newfor_release_files <- function(path) {
  if (!file.exists(path)) stop("newfor: file list not found: ", path, call. = FALSE)
  j <- jsonlite::read_json(path, simplifyVector = TRUE)
  f <- j$files
  need <- c("filename", "id", "bytes", "md5", "sha256")
  if (!is.data.frame(f) || !all(need %in% names(f)))
    stop("newfor: ", path, ": files need ", paste(need, collapse = ", "), call. = FALSE)
  f <- data.frame(filename = as.character(f$filename), id = f$id, bytes = as.numeric(f$bytes),
                  md5 = tolower(f$md5), sha256 = tolower(f$sha256), stringsAsFactors = FALSE)
  if (anyNA(f$filename) || anyDuplicated(f$filename))
    stop("newfor: ", path, ": missing or duplicate file names", call. = FALSE)
  if (!all(grepl("^[0-9a-f]{32}$", f$md5)) || !all(grepl("^[0-9a-f]{64}$", f$sha256)))
    stop("newfor: ", path, ": every file needs an md5 and a sha256 in hex", call. = FALSE)
  if (!is.null(j$n_files) && j$n_files != nrow(f))
    stop(sprintf("newfor: %s lists %d files but says n_files = %s", path, nrow(f),
                 format(j$n_files)), call. = FALSE)
  f
}

# The nine files an area needs: cloud, terrain raster, inventory and polygon
# shapefiles, and its plot sheet (shared by several areas).
newfor_area_files <- function(id, sheet)
  c(paste0(id, c("_ALS.laz", "_DTM.tif", "_Ref.shp", "_Ref.shx", "_Ref.dbf", "_AoI.shp",
                 "_AoI.shx", "_AoI.dbf")), sheet)

# Presence, size, MD5 and SHA-256 of files on disk (NA where absent).
.newfor_hash_files <- function(raw_dir, filenames) {
  p <- file.path(raw_dir, filenames)
  present <- file.exists(p) & !dir.exists(p)
  data.frame(filename = filenames, present = present,
             bytes = ifelse(present, file.size(p), NA_real_),
             md5 = ifelse(present, unname(tools::md5sum(p)), NA_character_),
             sha256 = vapply(seq_along(p), function(i)
               if (present[i]) frozen_sha256(p[i]) else NA_character_, character(1)),
             stringsAsFactors = FALSE)
}

# Checks the files of `files` (newfor_release_files rows) under raw_dir against
# their pinned size and checksums: data.frame filename, present, bytes_ok,
# md5_ok, sha256_ok (all FALSE for an absent file).
newfor_verify_raw <- function(raw_dir, files) {
  h <- .newfor_hash_files(raw_dir, files$filename)
  eq <- function(a, b) h$present & !is.na(a) & !is.na(b) & a == b
  data.frame(filename = files$filename, present = h$present,
             bytes_ok = eq(h$bytes, files$bytes), md5_ok = eq(h$md5, tolower(files$md5)),
             sha256_ok = eq(h$sha256, tolower(files$sha256)), stringsAsFactors = FALSE)
}

## ---- reading one area ----------------------------------------------------------------------
# One row of the metadata's areas as a list (a one-row data.frame or a list).
.newfor_area <- function(area) {
  if (is.data.frame(area)) {
    if (nrow(area) != 1L) stop("newfor: pass one area (one row of the areas table)",
                               call. = FALSE)
    area <- as.list(area)
  }
  if (is.null(area$id) || is.null(area$epsg))
    stop("newfor: an area needs at least id and epsg", call. = FALSE)
  area
}

# Geometry of a shapefile with the area's CRS assigned. The release's
# shapefiles carry none; one that carries another CRS stops (nothing is ever
# transformed).
.newfor_assign_crs <- function(x, epsg, label) {
  crs <- sf::st_crs(x)
  if (!is.na(crs) && !isTRUE(crs == sf::st_crs(epsg)))
    stop(sprintf("newfor: %s carries a CRS other than EPSG:%d; nothing is transformed", label,
                 as.integer(epsg)), call. = FALSE)
  sf::st_set_crs(sf::st_set_crs(sf::st_geometry(x), NA), as.integer(epsg))
}

# One area of the raw release: list(aoi, ref, las_file, dtm_file). aoi: the
# union of the polygon shapefile's features as an sfc of length 1, CRS
# area$epsg assigned. ref: one row per inventory row: row (1-based row in the
# shapefile), E, N (NA for a row without a position), dbh_m (DBHRef), dbh_cm
# (round(100 * DBHRef, 6)), height (HRef), vol (VolRef, NA when absent). Field
# names are matched case-insensitively; DBHRef and HRef are required.
newfor_read_area <- function(raw_dir, area) {
  area <- .newfor_area(area)
  f <- function(suffix) file.path(raw_dir, paste0(area$id, suffix))
  aoi_sf <- sf::st_read(f("_AoI.shp"), quiet = TRUE)
  if (!nrow(aoi_sf) || all(sf::st_is_empty(aoi_sf)))
    stop("newfor: ", basename(f("_AoI.shp")), " holds no polygon", call. = FALSE)
  aoi <- sf::st_union(.newfor_assign_crs(aoi_sf, area$epsg, basename(f("_AoI.shp"))))
  if (!all(as.character(sf::st_geometry_type(aoi)) %in% c("POLYGON", "MULTIPOLYGON")))
    stop("newfor: ", basename(f("_AoI.shp")), " is not a polygon layer", call. = FALSE)
  r <- sf::st_read(f("_Ref.shp"), quiet = TRUE)
  geom <- .newfor_assign_crs(r, area$epsg, basename(f("_Ref.shp")))
  ok <- !sf::st_is_empty(geom)
  if (!all(as.character(sf::st_geometry_type(geom[ok])) == "POINT"))
    stop("newfor: ", basename(f("_Ref.shp")), " is not a point layer", call. = FALSE)
  xy <- matrix(NA_real_, length(geom), 2L)
  if (any(ok)) xy[ok, ] <- sf::st_coordinates(geom[ok])[, 1:2, drop = FALSE]
  d <- sf::st_drop_geometry(r)
  field <- function(nm, required) {
    k <- which(tolower(names(d)) == tolower(nm))
    if (length(k) > 1L)
      stop(sprintf("newfor: %s has %d fields named %s", basename(f("_Ref.shp")), length(k), nm),
           call. = FALSE)
    if (!length(k)) {
      if (required) stop(sprintf("newfor: %s has no field %s", basename(f("_Ref.shp")), nm),
                         call. = FALSE)
      return(rep(NA_real_, nrow(d)))
    }
    as.numeric(d[[k]])
  }
  dbh <- field("DBHRef", TRUE)
  ref <- data.frame(row = seq_len(nrow(d)), E = xy[, 1], N = xy[, 2], dbh_m = dbh,
                    dbh_cm = round(100 * dbh, 6), height = field("HRef", TRUE),
                    vol = field("VolRef", FALSE))
  list(aoi = aoi, ref = ref, las_file = f("_ALS.laz"), dtm_file = f("_DTM.tif"))
}

# The reference flags of newfor_read_area()'s ref: inside (the polygon covers
# the stem, boundary included), dbh_status ("missing": dbh_cm <= 0 or NA;
# "below_caliper": 0 < dbh_cm < caliper_cm - 0.5; else "ok"), has_height
# (finite and > 0), primary (inside, has_height, not missing, dbh_cm >= 10) and
# inventoried (inside, has_height).
newfor_reference <- function(ref, aoi, caliper_cm) {
  d <- ref$dbh_cm
  ref$inside <- neon_support_inside(ref$E, ref$N, aoi)
  ref$dbh_status <- ifelse(is.na(d) | d <= 0, "missing",
                           ifelse(d < caliper_cm - 0.5, "below_caliper", "ok"))
  ref$has_height <- is.finite(ref$height) & ref$height > 0
  ref$primary <- ref$inside & ref$has_height & ref$dbh_status != "missing" & !is.na(d) &
    d >= NEWFOR_MIN_DBH_CM
  ref$inventoried <- ref$inside & ref$has_height
  ref
}

## ---- clip ----------------------------------------------------------------------------------
# lidR on one thread; returns the caller's setting for on.exit().
.newfor_one_thread <- function() {
  threads <- lidR::get_lidr_threads()
  lidR::set_lidr_threads(1L)
  threads
}

# The area (m2) of the convex hull of the points (x, y), rounded to 1e-6 m2 so
# that its value in cell.json (15 significant digits) reads back exactly; 0 for
# fewer than three points or a degenerate hull. The shoelace sum runs on
# coordinates taken relative to the first hull vertex, which avoids cancellation
# at projected magnitudes.
newfor_covered_area <- function(x, y) {
  if (length(x) < 3L) return(0)
  h <- grDevices::chull(x, y)
  if (length(h) < 3L) return(0)
  hx <- x[h] - x[h[1L]]; hy <- y[h] - y[h[1L]]
  round(abs(sum(hx * c(hy[-1L], hy[1L]) - c(hx[-1L], hx[1L]) * hy)) / 2, 6)
}

# The normalized clip of one area. las: the raw cloud with every attribute;
# dtm: the terrain raster (its CRS is ignored). box = the polygon's bounding box
# widened by `buffer`; clip = box cut to the X/Y range of the raw cloud's points
# (dropped points included); reach = c(west, south, east, north), the distance
# from each side of the polygon's bounding box to the same side of clip;
# clip_area = the area of clip (0 when the cloud misses the box). Points with X
# and Y in box (closed) are kept, then dropped and counted in this order: class
# in NEWFOR_DROP_CLASSES, Withheld_flag (when present), no terrain value
# (bilinear), height below NEWFOR_Z_MIN, height at or above NEWFOR_Z_MAX. The
# clip gets the CRS assigned, the canonical point order and coordinate snapping
# of the NEON frozen clips (frozen_canonical; Z is snapped after the height
# filter) and an updated header. covered_area = newfor_covered_area of the kept
# points' snapped X and Y, so the written clip gives it back exactly; it is the
# clip-wide densities' denominator, because a cloud that is a disc leaves the
# corners of clip empty. Scan angles above 90 degrees, which some clouds hold,
# are kept: they fit the attribute's signed byte and writeLAS writes them back
# unchanged. box and clip are c(xmin, ymin, xmax, ymax). Returns list(las, box,
# clip, reach, covered_area, clip_area, n_box, dropped = c(class, withheld,
# no_terrain, below, above), terrain_na_share = no_terrain / n_box).
newfor_clip <- function(las, dtm, aoi, epsg, buffer = NEWFOR_BUFFER) {
  if (!methods::is(las, "LAS")) stop("newfor: las must be a lidR LAS object", call. = FALSE)
  if (lidR::is.empty(las)) stop("newfor: the cloud holds no points", call. = FALSE)
  threads <- .newfor_one_thread()
  on.exit(lidR::set_lidr_threads(threads), add = TRUE)
  bb <- sf::st_bbox(aoi)
  box <- c(xmin = bb[["xmin"]] - buffer, ymin = bb[["ymin"]] - buffer,
           xmax = bb[["xmax"]] + buffer, ymax = bb[["ymax"]] + buffer)
  P <- las@data
  clip <- c(xmin = max(box[["xmin"]], min(P$X)), ymin = max(box[["ymin"]], min(P$Y)),
            xmax = min(box[["xmax"]], max(P$X)), ymax = min(box[["ymax"]], max(P$Y)))
  reach <- c(west = bb[["xmin"]] - clip[["xmin"]], south = bb[["ymin"]] - clip[["ymin"]],
             east = clip[["xmax"]] - bb[["xmax"]], north = clip[["ymax"]] - bb[["ymax"]])
  clip_area <- max(0, clip[["xmax"]] - clip[["xmin"]]) * max(0, clip[["ymax"]] - clip[["ymin"]])
  D <- P[P$X >= box[["xmin"]] & P$X <= box[["xmax"]] & P$Y >= box[["ymin"]] & P$Y <= box[["ymax"]]]
  n_box <- nrow(D)
  drop <- D$Classification %in% NEWFOR_DROP_CLASSES
  n_class <- sum(drop); D <- D[!drop]
  n_withheld <- 0L
  if ("Withheld_flag" %in% names(D)) {
    drop <- D$Withheld_flag %in% TRUE
    n_withheld <- sum(drop); D <- D[!drop]
  }
  g <- if (nrow(D)) terra::extract(dtm, cbind(D$X, D$Y), method = "bilinear")[, 1] else numeric()
  drop <- is.na(g)
  n_terrain <- sum(drop); D <- D[!drop]; g <- g[!drop]
  data.table::set(D, j = "Z", value = D$Z - g)
  below <- D$Z < NEWFOR_Z_MIN; above <- D$Z >= NEWFOR_Z_MAX
  D <- D[!below & !above]
  las@data <- D
  sf::st_crs(las) <- as.integer(epsg)
  if (nrow(D)) frozen_canonical(las)                 # nothing to snap or order in an empty clip
  las <- lidR::las_update(las)
  covered_area <- newfor_covered_area(las@data$X, las@data$Y)   # on the snapped coordinates
  list(las = las, box = box, clip = clip, reach = reach, covered_area = covered_area,
       clip_area = clip_area, n_box = n_box,
       dropped = c(class = n_class, withheld = n_withheld, no_terrain = n_terrain,
                   below = sum(below), above = sum(above)),
       terrain_na_share = if (n_box > 0) n_terrain / n_box else NA_real_)
}

## ---- density -------------------------------------------------------------------------------
# Point densities of a normalized clip, inside the scoring polygon (boundary
# included) and over the clip: the clip-wide counts are divided by
# covered_area, the area of the kept points' convex hull (newfor_clip), not by
# the clip rectangle, which a disc-shaped cloud does not fill. A first return
# is ReturnNumber == 1; without ReturnNumber the first-return counts and
# densities are NA. Densities are NA for a zero area. Returns list(n_aoi,
# n_first_aoi, aoi_area, pdens_aoi, frdens_aoi, n_clip, n_first_clip,
# pdens_clip, frdens_clip).
newfor_density <- function(las, aoi, covered_area) {
  P <- las@data
  fr <- if ("ReturnNumber" %in% names(P)) P$ReturnNumber %in% 1L else NULL
  bb <- sf::st_bbox(aoi)
  cand <- which(P$X >= bb[["xmin"]] & P$X <= bb[["xmax"]] & P$Y >= bb[["ymin"]] &
                P$Y <= bb[["ymax"]])
  inside <- logical(nrow(P))
  inside[cand] <- neon_support_inside(P$X[cand], P$Y[cand], aoi)
  aoi_area <- as.numeric(sf::st_area(aoi))
  per <- function(n, a) if (is.finite(a) && a > 0) n / a else NA_real_
  n_first_aoi <- if (is.null(fr)) NA_integer_ else sum(inside & fr)
  n_first_clip <- if (is.null(fr)) NA_integer_ else sum(fr)
  list(n_aoi = sum(inside), n_first_aoi = n_first_aoi, aoi_area = aoi_area,
       pdens_aoi = per(sum(inside), aoi_area), frdens_aoi = per(n_first_aoi, aoi_area),
       n_clip = nrow(P), n_first_clip = n_first_clip,
       pdens_clip = per(nrow(P), covered_area), frdens_clip = per(n_first_clip, covered_area))
}

# The detector's raster resolution from the clip-wide first-return density:
# 0.25 m at NEWFOR_RES_GATE or more, otherwise 0.5 m; NA for an unknown density.
newfor_res <- function(frdens_clip)
  ifelse(is.finite(frdens_clip), ifelse(frdens_clip >= NEWFOR_RES_GATE, 0.25, 0.5), NA_real_)

## ---- registration diagnostic ---------------------------------------------------------------
# Detector-free estimate of the offset between the stems and the canopy. las:
# the normalized clip; stems: the primary stems (E, N, height); box: the
# uncropped box of newfor_clip (c(xmin, ymin, xmax, ymax) or a list with those
# names). A 0.5 m raster over the box, its edges rounded outwards to whole
# metres, holds the highest first return of each cell; the canopy top at a
# position is the cell value of its focal maximum within 1.5 m (circular
# window, terra::focalMat). A stem is locally dominant when no primary stem
# within 4 m (squared distance <= 16, itself included) is taller. For every
# offset (dx, dy) on the 0.5 m lattice within +-8 m the statistic is the mean
# absolute difference between the dominant stems' heights and the canopy top
# at (E + dx, N + dy), NA positions left out. The estimate minimises it; ties
# within 1e-12 go to the shortest offset, then the smallest dx, then the
# smallest dy (a max filter makes the minimum flat within its radius on
# isolated crowns, so ties are common). Returns list(dx, dy, offset, stat_zero,
# stat_best, ratio = stat_best / stat_zero, n_dominant, scan = data.frame(dx,
# dy, stat)), scan in lattice order (dx outer, dy inner). With fewer than three
# dominant stems, or no first return, every value but n_dominant is NA and
# scan has NA statistics.
newfor_registration <- function(las, stems, box) {
  L <- seq(-NEWFOR_REG_RANGE, NEWFOR_REG_RANGE, NEWFOR_REG_STEP)
  scan <- data.frame(dx = rep(L, each = length(L)), dy = rep(L, times = length(L)),
                     stat = NA_real_)
  E <- stems$E; N <- stems$N; h <- stems$height
  dom <- vapply(seq_along(E), function(i)
    isTRUE(h[i] >= max(h[(E - E[i])^2 + (N - N[i])^2 <= NEWFOR_REG_DOM_RADIUS^2])), logical(1))
  out <- list(dx = NA_real_, dy = NA_real_, offset = NA_real_, stat_zero = NA_real_,
              stat_best = NA_real_, ratio = NA_real_, n_dominant = sum(dom), scan = scan)
  P <- las@data
  fr <- if ("ReturnNumber" %in% names(P)) P$ReturnNumber %in% 1L else logical(nrow(P))
  if (sum(dom) < 3L || !any(fr)) return(out)
  r <- terra::rast(xmin = floor(box[["xmin"]]), xmax = ceiling(box[["xmax"]]),
                   ymin = floor(box[["ymin"]]), ymax = ceiling(box[["ymax"]]),
                   resolution = NEWFOR_REG_RES, crs = "")
  chm <- terra::rasterize(cbind(P$X[fr], P$Y[fr]), r, values = P$Z[fr], fun = max)
  w <- terra::focalMat(chm, NEWFOR_REG_TOP_RADIUS, "circle")
  w[w > 0] <- 1; w[w == 0] <- NA
  top <- terra::focal(chm, w = w, fun = "max", na.rm = TRUE)
  sx <- E[dom]; sy <- N[dom]; sh <- h[dom]; nd <- length(sx); no <- nrow(scan)
  v <- terra::extract(top, cbind(rep(sx, no) + rep(scan$dx, each = nd),
                                 rep(sy, no) + rep(scan$dy, each = nd)))[, 1]
  V <- matrix(v, nrow = nd)
  stat <- vapply(seq_len(no), function(j) mean(abs(sh - V[, j]), na.rm = TRUE), numeric(1))
  stat[is.nan(stat)] <- NA_real_
  out$scan$stat <- stat
  if (all(is.na(stat))) return(out)
  best <- which(stat <= min(stat, na.rm = TRUE) + 1e-12)
  len <- sqrt(scan$dx^2 + scan$dy^2)
  b <- best[order(len[best], scan$dx[best], scan$dy[best])[1L]]
  zero <- which(scan$dx == 0 & scan$dy == 0)
  out$dx <- scan$dx[b]; out$dy <- scan$dy[b]; out$offset <- len[b]
  out$stat_zero <- stat[zero]; out$stat_best <- stat[b]; out$ratio <- stat[b] / stat[zero]
  out
}

## ---- admission -----------------------------------------------------------------------------
# One area's admission row (protocol, section Admission). verify: rows of
# newfor_verify_raw (the area's nine files are picked by name; a file without a
# row fails rule_files); clip: newfor_clip; density: newfor_density; ref:
# newfor_reference; reg: newfor_registration. clip, density, ref and reg may be
# NULL (an area whose cloud or inventory cannot be read): the rules that need
# them fail and their counts are NA. n_missing_dbh and n_below_caliper count
# stems inside the polygon. failed: the names of the failed rules joined by
# ";", "" when admitted.
newfor_admission <- function(area, verify, clip, density, ref, reg) {
  area <- .newfor_area(area)
  files <- newfor_area_files(area$id, area$sheet)
  v <- verify[match(files, verify$filename), , drop = FALSE]
  rule_files <- !anyNA(v$filename) && all(v$present %in% TRUE & v$md5_ok %in% TRUE)
  rn <- if (!is.null(clip)) clip$las@data[["ReturnNumber"]]
  rule_returns <- !is.null(rn) && !anyNA(rn) && isTRUE(density$n_first_clip >= 1)
  reach_min <- if (is.null(clip)) NA_real_ else min(clip$reach)
  terrain_na <- if (is.null(clip)) NA_real_ else clip$terrain_na_share
  gap <- if (is.null(area$gap_months))
    .newfor_months(area$flight_date) - .newfor_months(area$field_date) else area$gap_months
  offset <- if (is.null(reg)) NA_real_ else reg$offset
  cnt <- function(x) if (is.null(ref)) NA_integer_ else sum(x)
  big <- if (!is.null(ref)) ref$inside & !is.na(ref$dbh_cm) & ref$dbh_cm >= NEWFOR_MIN_DBH_CM
  row <- data.frame(area = as.character(area$id),
                    forest = if (is.null(area$forest)) NA_character_ else area$forest,
                    n_rows = if (is.null(ref)) NA_integer_ else nrow(ref),
                    n_inside = cnt(ref$inside), n_outside = cnt(!ref$inside),
                    n_primary = cnt(ref$primary), n_inventoried = cnt(ref$inventoried),
                    n_missing_dbh = cnt(ref$inside & ref$dbh_status == "missing"),
                    n_below_caliper = cnt(ref$inside & ref$dbh_status == "below_caliper"),
                    gap_months = as.integer(gap), reach_min = reach_min,
                    terrain_na_share = terrain_na, offset = offset,
                    rule_files = rule_files, rule_returns = rule_returns,
                    rule_terrain = isTRUE(terrain_na < NEWFOR_MAX_TERRAIN_NA),
                    rule_buffer = isTRUE(reach_min >= NEWFOR_MIN_REACH),
                    rule_heights = !is.null(ref) && all(ref$has_height[big]),
                    rule_gap = isTRUE(abs(gap) <= NEWFOR_MAX_GAP_MONTHS),
                    rule_stems = !is.null(ref) && sum(ref$primary) >= NEWFOR_MIN_STEMS,
                    rule_registration = is.finite(offset) && offset <= NEWFOR_MAX_OFFSET,
                    stringsAsFactors = FALSE)
  ok <- unlist(row[.NEWFOR_RULES])
  row$admitted <- all(ok)
  row$failed <- paste(.NEWFOR_RULES[!ok], collapse = ";")
  row
}

## ---- freezing one area, sealing, reading back ----------------------------------------------
# Freezes one area into <out_root>/<id>: read, reference, clip, density,
# registration, admission, then writes normalized.laz, aoi.wkt,
# reference_stems.csv and cell.json (layout in the header). files: the pinned
# file list (newfor_release_files), whose rows for the area's nine files are
# verified; a mismatch fails rule_files but the area is frozen as usual. Refuses
# a sealed root and an existing area folder; on error the area folder is
# removed. The written cloud is read back and must give identical X, Y, Z,
# ReturnNumber, NumberOfReturns and Classification and the assigned CRS. lidR
# runs on one thread; the caller's setting is restored. Returns
# list(admission = <one row>, scan = <the registration scan with an area
# column first>).
newfor_freeze_area <- function(raw_dir, area, files, out_root) {
  area <- .newfor_area(area)
  id <- as.character(area$id)
  if (newfor_sealed(out_root))
    stop("newfor: the root is sealed; freeze into a new root: ", out_root, call. = FALSE)
  dir <- file.path(out_root, id)
  if (file.exists(dir))
    stop("newfor: the area folder already exists; freeze into a new root: ", dir, call. = FALSE)
  threads <- .newfor_one_thread()
  on.exit(lidR::set_lidr_threads(threads), add = TRUE)
  area_files <- newfor_area_files(id, area$sheet)
  hashes <- .newfor_hash_files(raw_dir, area_files)
  verify <- newfor_verify_raw(raw_dir, files[files$filename %in% area_files, , drop = FALSE])
  rd <- newfor_read_area(raw_dir, area)
  # Every step uses the polygon as aoi.wkt stores it (15 significant digits, which
  # moves the release's vertices by nanometres), so that the frozen files give
  # back exactly the flags and densities recorded here.
  wkt <- sf::st_as_text(rd$aoi, digits = 15)
  aoi <- sf::st_as_sfc(wkt, crs = as.integer(area$epsg))
  ref <- newfor_reference(rd$ref, aoi, area$caliper_cm)
  warns <- character()
  las <- withCallingHandlers(lidR::readLAS(rd$las_file), warning = function(w) {
    warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning")
  })
  clip <- newfor_clip(las, terra::rast(rd$dtm_file), aoi, area$epsg)
  rm(las)
  if (lidR::is.empty(clip$las))
    stop("newfor: area ", id, ": no point of the cloud is kept in the box", call. = FALSE)
  density <- newfor_density(clip$las, aoi, clip$covered_area)
  reg <- newfor_registration(clip$las, ref[ref$primary, c("E", "N", "height")], clip$box)
  adm <- newfor_admission(area, verify, clip, density, ref, reg)
  done <- FALSE
  dir.create(dir, recursive = TRUE)
  on.exit(if (!done) unlink(dir, recursive = TRUE), add = TRUE)
  laz <- file.path(dir, "normalized.laz")
  lidR::writeLAS(clip$las, laz)
  back <- lidR::readLAS(laz, select = "xyzrnc")
  for (k in c("X", "Y", "Z", "ReturnNumber", "NumberOfReturns", "Classification"))
    if (!identical(back@data[[k]], clip$las@data[[k]]))
      stop("newfor: area ", id, ": ", k, " of the written clip does not read back unchanged",
           call. = FALSE)
  if (!isTRUE(sf::st_crs(back) == sf::st_crs(as.integer(area$epsg))))
    stop("newfor: area ", id, ": the written clip does not read back with its CRS", call. = FALSE)
  writeLines(wkt, file.path(dir, "aoi.wkt"))
  utils::write.csv(ref, file.path(dir, "reference_stems.csv"), row.names = FALSE)
  cell <- list(id = id, forest = area$forest, epsg = as.integer(area$epsg),
               buffer = NEWFOR_BUFFER, box = as.list(clip$box), clip = as.list(clip$clip),
               reach = as.list(clip$reach), covered_area = clip$covered_area,
               clip_area = clip$clip_area, n_box = clip$n_box,
               dropped = as.list(clip$dropped), n_points = lidR::npoints(clip$las),
               terrain_na_share = clip$terrain_na_share, density = density,
               res = newfor_res(density$frdens_clip),
               registration = reg[setdiff(names(reg), "scan")], admission = as.list(adm),
               raw_sha256 = as.list(stats::setNames(hashes$sha256, hashes$filename)),
               read_warnings = warns, lidr_threads = 1L, point_order = FROZEN_POINT_ORDER)
  jsonlite::write_json(cell, file.path(dir, "cell.json"), auto_unbox = TRUE, pretty = TRUE,
                       digits = NA, na = "null")
  done <- TRUE
  list(admission = adm, scan = cbind(area = id, reg$scan, stringsAsFactors = FALSE))
}

newfor_sealed <- function(out_root) file.exists(file.path(out_root, .NEWFOR_MANIFEST))

# Seals a root: freeze_manifest.csv lists every other file under it (path
# relative to the root, bytes, sha256), sorted by path (C locale).
newfor_seal <- function(out_root) {
  if (!dir.exists(out_root)) stop("newfor: no root at ", out_root, call. = FALSE)
  if (newfor_sealed(out_root)) stop("newfor: the root is already sealed: ", out_root,
                                    call. = FALSE)
  f <- list.files(out_root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  f <- sort(setdiff(f, .NEWFOR_MANIFEST), method = "radix")
  p <- file.path(out_root, f)
  m <- data.frame(file = f, bytes = as.integer(file.size(p)),
                  sha256 = vapply(p, frozen_sha256, character(1), USE.NAMES = FALSE),
                  stringsAsFactors = FALSE)
  if (anyNA(m$bytes)) stop("newfor: a file under the root is too large to record", call. = FALSE)
  utils::write.csv(m, file.path(out_root, .NEWFOR_MANIFEST), row.names = FALSE)
  invisible(m)
}

# The root's identity: the SHA-256 of its manifest (NA when unsealed).
newfor_root_id <- function(out_root) frozen_sha256(file.path(out_root, .NEWFOR_MANIFEST))

# Checks root files (paths relative to the root) against the manifest.
.newfor_check_sealed <- function(out_root, rel) {
  if (!newfor_sealed(out_root)) stop("newfor: the root is not sealed: ", out_root, call. = FALSE)
  m <- utils::read.csv(file.path(out_root, .NEWFOR_MANIFEST), stringsAsFactors = FALSE,
                       colClasses = c(file = "character", bytes = "numeric",
                                      sha256 = "character"))
  for (f in rel) {
    row <- m[m$file == f, , drop = FALSE]
    if (nrow(row) != 1L) stop("newfor: ", f, " is not in the root's manifest", call. = FALSE)
    p <- file.path(out_root, f)
    if (!file.exists(p) || file.size(p) != row$bytes || !identical(frozen_sha256(p), row$sha256))
      stop("newfor: ", f, " differs from the root's manifest", call. = FALSE)
  }
  invisible(TRUE)
}

# One frozen area: list(id, epsg, aoi (sfc with the CRS), stems (the rows of
# reference_stems.csv), cell (parsed cell.json), las_file). With verify = TRUE
# the root must be sealed and the area's four files must match the manifest.
# Stops when the stored inside flags disagree with the polygon read back.
newfor_frozen_area <- function(out_root, id, verify = TRUE) {
  id <- as.character(id)
  rel <- file.path(id, .NEWFOR_AREA_FILES)
  if (verify) .newfor_check_sealed(out_root, rel)
  p <- stats::setNames(file.path(out_root, rel), .NEWFOR_AREA_FILES)
  if (!all(file.exists(p))) stop("newfor: area ", id, " is not frozen under ", out_root,
                                 call. = FALSE)
  cell <- jsonlite::read_json(p[["cell.json"]], simplifyVector = TRUE)
  if (!identical(as.character(cell$id), id))
    stop("newfor: ", p[["cell.json"]], " belongs to area ", cell$id, call. = FALSE)
  epsg <- as.integer(cell$epsg)
  aoi <- sf::st_as_sfc(readLines(p[["aoi.wkt"]], warn = FALSE), crs = epsg)
  stems <- utils::read.csv(p[["reference_stems.csv"]], stringsAsFactors = FALSE,
                           colClasses = c(dbh_status = "character"))
  if (!identical(neon_support_inside(stems$E, stems$N, aoi), stems$inside))
    stop("newfor: area ", id, ": the polygon read back does not hold the frozen inside flags",
         call. = FALSE)
  list(id = id, epsg = epsg, aoi = aoi, stems = stems, cell = cell,
       las_file = p[["normalized.laz"]])
}

# admission.csv of a root (written by the freeze driver), checked against the
# manifest when the root is sealed: area and forest as character, failed as
# character ("" when admitted), the rules and admitted as logical.
newfor_frozen_admission <- function(out_root) {
  f <- file.path(out_root, "admission.csv")
  if (!file.exists(f)) stop("newfor: no admission.csv under ", out_root, call. = FALSE)
  if (newfor_sealed(out_root)) .newfor_check_sealed(out_root, "admission.csv")
  a <- utils::read.csv(f, stringsAsFactors = FALSE,
                       colClasses = c(area = "character", forest = "character",
                                      failed = "character"))
  for (k in intersect(c(.NEWFOR_RULES, "admitted"), names(a))) a[[k]] <- as.logical(a[[k]])
  a
}

# freeze.json of a sealed root (written by the freeze driver), parsed, after it
# is checked against the manifest. Stops when the root is not sealed, holds no
# freeze.json, or its freeze.json is not listed in the manifest or differs.
newfor_frozen_record <- function(out_root) {
  f <- file.path(out_root, "freeze.json")
  if (!newfor_sealed(out_root)) stop("newfor: the root is not sealed: ", out_root, call. = FALSE)
  if (!file.exists(f)) stop("newfor: the root holds no freeze.json: ", out_root, call. = FALSE)
  .newfor_check_sealed(out_root, "freeze.json")
  jsonlite::read_json(f, simplifyVector = TRUE)
}

# The SHA-256 of the R files a run record names, as a character vector named
# by the base names in `files`, in their order. find(name) gives a file's path
# or NULL (the drivers pass .find of repo_paths.R). A file that cannot be found
# stops, so a record never holds a missing hash.
newfor_code_sha256 <- function(files, find) {
  paths <- lapply(files, find)
  found <- vapply(paths, function(p) length(p) == 1L && !is.na(p) && file.exists(p), TRUE)
  if (!all(found))
    stop("newfor: an R file the run record must hash is not found: ",
         paste(files[!found], collapse = ", "), call. = FALSE)
  stats::setNames(vapply(paths, frozen_sha256, character(1)), files)
}

## ---- scoring on a polygon ------------------------------------------------------------------
# The stems of one population in the shape score_plot wants: E, N, height and
# a crown_class of NA (the release records none).
newfor_stems <- function(ref, population = c("primary", "inventoried")) {
  population <- match.arg(population)
  sel <- ref[[population]] %in% TRUE
  data.frame(E = ref$E[sel], N = ref$N[sel], height = ref$height[sel],
             crown_class = rep(NA_character_, sum(sel)), stringsAsFactors = FALSE)
}

# The null's window: the polygon's bounding box widened by tol, as
# list(xmin, ymin, w, h).
newfor_window <- function(aoi, tol) {
  bb <- sf::st_bbox(aoi)
  list(xmin = bb[["xmin"]] - tol, ymin = bb[["ymin"]] - tol,
       w = bb[["xmax"]] - bb[["xmin"]] + 2 * tol, h = bb[["ymax"]] - bb[["ymin"]] + 2 * tol)
}

# The null's k shifts of one plot on a w x h torus: offset i is drawn with
# set.seed(seed_for(NEWFOR_SITE, plot, "null") + i) by rejection, ox ~ U(0, w)
# then oy ~ U(0, h) per attempt, accepted when its toroidal distance from no
# shift, sqrt(min(ox, w - ox)^2 + min(oy, h - oy)^2), is at least min_shift.
# The shifts depend on the plot and the window only, so every configuration of
# a plot shares them. Draws use R's default generators (Mersenne-Twister,
# Inversion, Rejection) whatever the caller set; the caller's RNG kind and state
# are restored. Returns a list of k vectors c(ox, oy).
newfor_null_offsets <- function(plot, w, h, k = NEWFOR_NULL_K,
                                min_shift = NEWFOR_NULL_MIN_SHIFT) {
  if (!is.numeric(w) || !is.numeric(h) || length(w) != 1L || length(h) != 1L ||
      !is.finite(w) || !is.finite(h) || w <= 0 || h <= 0)
    stop("newfor: the null's window needs a positive width and height", call. = FALSE)
  if (min_shift >= sqrt((w / 2)^2 + (h / 2)^2))
    stop(sprintf("newfor: min_shift %g is too large for a %g x %g window", min_shift, w, h),
         call. = FALSE)
  base <- seed_for(NEWFOR_SITE, plot, "null")
  if (as.numeric(base) + k > .Machine$integer.max)
    stop("newfor: the null seeds of plot ", plot, " overflow", call. = FALSE)
  old_kind <- RNGkind()
  old_seed <- get0(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
        rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", old_seed, envir = .GlobalEnv)
  }, add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  lapply(seq_len(k), function(i) {
    set.seed(base + i)
    repeat {
      ox <- stats::runif(1, 0, w)
      oy <- stats::runif(1, 0, h)
      if (sqrt(min(ox, w - ox)^2 + min(oy, h - oy)^2) >= min_shift) return(c(ox, oy))
    }
  })
}

# Detections inside the window (closed), shifted together by offset and wrapped
# into it; detections outside it are dropped (the matcher never reads them).
newfor_shift <- function(det, win, offset) {
  x0 <- win$xmin; y0 <- win$ymin
  out <- det[det$x >= x0 & det$x <= x0 + win$w & det$y >= y0 & det$y <= y0 + win$h, ,
             drop = FALSE]
  out$x <- x0 + (out$x - x0 + offset[1]) %% win$w
  out$y <- y0 + (out$y - y0 + offset[2]) %% win$h
  out
}

# Counts of one score_plot() call on the polygon, unchanged: n_ref, n_det (the
# detections inside the polygon), TP, tp_core (those of them that matched),
# then n_h_<band> per band and tp_h_<band> = round(rec_h_<band> * n_h_<band>)
# per band (0 for an empty band). Stems must lie inside the polygon and the
# polygon must carry a projected metric CRS (score_plot stops otherwise).
newfor_score <- function(stems, det, aoi, tol) {
  sc <- score_plot(stems, det, tol_xy = tol, core_cx = NA, core_cy = NA, core_geometry = aoi)
  b <- NEWFOR_HEIGHT_BANDS
  n_h <- vapply(b, function(k) as.numeric(sc[[paste0("n_h_", k)]]), numeric(1))
  r_h <- vapply(b, function(k) as.numeric(sc[[paste0("rec_h_", k)]]), numeric(1))
  tp_h <- ifelse(n_h > 0 & is.finite(r_h), round(r_h * n_h), 0)
  c(n_ref = sc$n_ref, n_det = sc$n_det, TP = sc$TP, tp_core = sc$tp_core,
    stats::setNames(n_h, paste0("n_h_", b)), stats::setNames(tp_h, paste0("tp_h_", b)))
}

# One cell (area x detection set): MCG_COUNT_COLS (the crown-class counts
# n_over, n_under, tp_over, tp_under, tp_over0, tp_under0 are 0: the release
# records no crown class), then n_h_<band>, tp_h_<band> and tp_h_<band>0 per
# band (in NEWFOR_HEIGHT_BANDS order within each group). The *0 columns are
# means over the shifted copies of the detections (newfor_shift within
# newfor_window(aoi, tol)); offsets default to newfor_null_offsets(plot, w, h)
# of that window, and an empty list gives NA. An empty detection set scores 0
# everywhere. Add site, plot and config to feed mcg_rates/mcg_pool/mcg_contrast.
newfor_score_cell <- function(stems, det, aoi, plot, tol = NEWFOR_TOL, offsets = NULL) {
  win <- newfor_window(aoi, tol)
  if (is.null(offsets)) offsets <- newfor_null_offsets(plot, win$w, win$h)
  o <- newfor_score(stems, det, aoi, tol)
  nul <- if (!length(offsets)) stats::setNames(rep(NA_real_, length(o)), names(o))
    else if (!nrow(newfor_shift(det, win, c(0, 0)))) newfor_score(stems, det[0, , drop = FALSE],
                                                                  aoi, tol)
    else rowMeans(vapply(offsets, function(of)
      newfor_score(stems, newfor_shift(det, win, of), aoi, tol), numeric(length(o))))
  out <- data.frame(n_ref = o[["n_ref"]], n_over = 0, n_under = 0, n_det = o[["n_det"]],
                    TP = o[["TP"]], tp_core = o[["tp_core"]], tp_over = 0, tp_under = 0,
                    n_det0 = nul[["n_det"]], TP0 = nul[["TP"]], tp_core0 = nul[["tp_core"]],
                    tp_over0 = 0, tp_under0 = 0)
  b <- NEWFOR_HEIGHT_BANDS
  for (k in b) out[[paste0("n_h_", k)]] <- o[[paste0("n_h_", k)]]
  for (k in b) out[[paste0("tp_h_", k)]] <- o[[paste0("tp_h_", k)]]
  for (k in b) out[[paste0("tp_h_", k, "0")]] <- nul[[paste0("tp_h_", k)]]
  out
}

## ---- detection -----------------------------------------------------------------------------
# Stock detections against lidRplugins::multichm itself on the same clip, res
# and window, on one thread: list(ok, n_package, n_stock, max_abs_diff, error).
# ok: the two (x, y) sets are identical; max_abs_diff: the largest coordinate
# difference after sorting both by (x, y) (NA when the counts differ). A package
# error is caught and recorded with ok = NA.
.newfor_parity <- function(las, res, a, stock) {
  out <- list(ok = NA, n_package = NA_integer_, n_stock = nrow(stock), max_abs_diff = NA_real_,
              error = NA_character_)
  threads <- .newfor_one_thread()
  on.exit(lidR::set_lidr_threads(threads), add = TRUE)
  tt <- tryCatch(suppressWarnings(lidR::locate_trees(
    las, lidRplugins::multichm(res = res, ws = ws_factory(a)))), error = function(e) e)
  if (inherits(tt, "error")) {
    out$error <- conditionMessage(tt)
    return(out)
  }
  co <- sf::st_coordinates(tt)
  pk <- if (nrow(co)) data.frame(x = unname(co[, 1]), y = unname(co[, 2]))
        else data.frame(x = numeric(), y = numeric())
  out$n_package <- nrow(pk)
  if (nrow(pk) != nrow(stock)) {
    out$ok <- FALSE
    return(out)
  }
  p <- pk[order(pk$x, pk$y), ]; s <- stock[order(stock$x, stock$y), ]
  out$max_abs_diff <- if (nrow(p)) max(abs(c(p$x - s$x, p$y - s$y))) else 0
  out$ok <- out$max_abs_diff == 0
  out
}

# Detections of every configuration on one normalized clip, on one thread.
# res = newfor_res(frdens_clip); the clip is prepared once (mcg_prepare) and
# each configuration applied (mcg_apply). features: one row with res, cover,
# top_height, crown_spacing, n_crowns, crown_area, n_candidates, n_surface,
# n_deeper and, under MCG_DECLARED, closed (mcg_closed), spaced (mcg_spaced)
# and gate_state ("gated": closed and spaced; "closed": closed, not spaced;
# "open": not closed; NA when unknown). det: a named list of x, y, z
# data.frames in the order of configs. parity (NULL with parity = FALSE): the
# stock detections (configs$stock, or MCG_STOCK when configs has none) against
# the package (.newfor_parity). Returns list(res, features, det, parity).
newfor_detect <- function(las, frdens_clip, configs = newfor_configs(), a = NEWFOR_A,
                          parity = TRUE) {
  res <- newfor_res(frdens_clip)
  if (length(res) != 1L || is.na(res))
    stop("newfor: the clip-wide first-return density is unknown, so is the resolution",
         call. = FALSE)
  if (!is.list(configs) || !length(configs) || is.null(names(configs)) ||
      any(!nzchar(names(configs))) || anyDuplicated(names(configs)))
    stop("newfor: configs must be a list of configurations with distinct names", call. = FALSE)
  threads <- .newfor_one_thread()
  on.exit(lidR::set_lidr_threads(threads), add = TRUE)
  prep <- mcg_prepare(las, res, a)
  det <- lapply(configs, function(cfg) mcg_apply(prep, cfg))
  closed <- mcg_closed(prep$cover, MCG_DECLARED)
  spaced <- mcg_spaced(prep$crown_spacing, MCG_DECLARED)
  gate_state <- if (isTRUE(closed) && isTRUE(spaced)) "gated"
    else if (isTRUE(closed) && isFALSE(spaced)) "closed"
    else if (isFALSE(closed)) "open" else NA_character_
  layer <- prep$cand$layer
  features <- data.frame(res = res, cover = prep$cover, top_height = prep$top_height,
                         crown_spacing = prep$crown_spacing, n_crowns = prep$n_crowns,
                         crown_area = prep$crown_area, n_candidates = length(layer),
                         n_surface = sum(layer == 1L), n_deeper = sum(layer > 1L),
                         closed = closed, spaced = spaced, gate_state = gate_state,
                         stringsAsFactors = FALSE)
  par <- if (parity)
    .newfor_parity(las, res, a, if (!is.null(det$stock)) det$stock else mcg_apply(prep, MCG_STOCK))
  list(res = res, features = features, det = det, parity = par)
}
