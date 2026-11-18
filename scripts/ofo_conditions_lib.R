# Site-condition checks of the Open Forest Observatory (OFO) preflight
# (docs/ofo-preflight-protocol.md, "Disturbance, snow and leaf-off"): canopy
# change between the 3DEP flight and a nadir drone canopy height model, SNODAS
# snow depth on winter flight dates, and the winter-deciduous share of the
# reference stems on leaf-off flights. Pure functions; network and file reads
# take explicit paths or readers. The driver is preflight_ofo_conditions.R.

OFO_PITCH_MAX   <- 10     # camera pitch, degrees from nadir
OFO_CELL        <- 5      # comparison grid, m, aligned with the project frame
OFO_CANOPY_MIN  <- 5      # a canopy cell is at least this tall, m
OFO_SHARE_MAX   <- 0.10   # loss and reverse shares above this hold a plot
OFO_COVER_DAYS  <- 365    # a mission within this of the survey covers the gap
OFO_DECID_MAX   <- 0.10   # deciduous share at or above this holds a plot
OFO_HMIN        <- 0      # normalised 3DEP heights kept, m
OFO_HMAX        <- 110
OFO_SNOW_WINDOW <- c("11-01", "04-30")   # month-day, crosses the new year
OFO_LEAF_WINDOW <- c("10-15", "04-30")

OFO_CHM_URL <- paste0("https://js2.jetstream-cloud.org:8001/ofo-public/drone/missions_03/",
                      "%s/photogrammetry_03/full/%s_chm-ptcloud.tif")
# NSIDC G02158 masked daily archive. The host named in the brief
# (noaadata.apl.washington.edu) does not resolve; NSIDC's dataset page lists
# noaadata.apps.nsidc.org, which serves the same path layout.
OFO_SNODAS_BASE <- "https://noaadata.apps.nsidc.org/NOAA/G02158/masked"

# Winter-deciduous broadleaf trees and larch, as the USDA PLANTS symbols (and
# OFO supplementary codes) found in the catalogue's tree table. Every other
# code in that table is evergreen, a shrub-only taxon, semi-evergreen or
# unidentified, and is left out (see the driver's report). AECA is summer-
# deciduous but bare from late summer to late winter, so it is leafless on
# most flights of the leaf-off window.
OFO_WINTER_DECIDUOUS <- c(
  "ACCI",    # Acer circinatum, vine maple
  "ACMA3",   # Acer macrophyllum, bigleaf maple
  "ACNE2",   # Acer negundo, box elder
  "ACRU",    # Acer rubrum, red maple
  "AECA",    # Aesculus californica, California buckeye
  "ALRU2",   # Alnus rubra, red alder
  "AMAL2",   # Amelanchier alnifolia, Saskatoon serviceberry
  "BEOC",    # Betula occidentalis, water birch
  "CONU4",   # Cornus nuttallii, Pacific dogwood
  "FRLA",    # Fraxinus latifolia, Oregon ash
  "FRPU7",   # Frangula purshiana, cascara
  "LAOC",    # Larix occidentalis, western larch
  "POBAT",   # Populus balsamifera ssp. trichocarpa, black cottonwood
  "POTR5",   # Populus tremuloides, quaking aspen
  "PREM",    # Prunus emarginata, bitter cherry
  "QUDE",    # OFO code: deciduous oak, species unknown
  "QUDO",    # Quercus douglasii, blue oak
  "QUGA4",   # Quercus garryana, Oregon white oak
  "QUKE",    # Quercus kelloggii, California black oak
  "RHPU",    # Rhamnus purshiana (synonym of FRPU7), cascara
  "SALIX",   # OFO code: willow, species unknown
  "SASC")    # Salix scouleriana, Scouler's willow

# ---- Drone missions --------------------------------------------------------

# Pitch in degrees from nadir: the EXIF-derived value when it parses as a
# number, else the largest programmed value of a multi-value nominal entry.
ofo_mission_pitch <- function(derived, nominal) {
  d <- suppressWarnings(as.numeric(as.character(derived)))
  nom <- vapply(strsplit(as.character(nominal), ",", fixed = TRUE), function(v) {
    v <- suppressWarnings(as.numeric(trimws(v)))
    if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE)
  }, numeric(1))
  ifelse(is.na(d), nom, d)
}

# Mission date: the earliest image date, else the contributor's first date
# (the earliest when several are listed).
ofo_mission_date <- function(earliest_derived, date) {
  d <- as.Date(as.character(earliest_derived), optional = TRUE)
  nom <- vapply(strsplit(as.character(date), ",", fixed = TRUE), function(v) {
    v <- as.Date(trimws(v), optional = TRUE)
    if (all(is.na(v))) NA_real_ else as.numeric(min(v, na.rm = TRUE))
  }, numeric(1))
  out <- ifelse(is.na(d), nom, as.numeric(d))
  as.Date(out, origin = "1970-01-01")
}

# Logical per mission: its valid footprint covers the plot polygon. Both are
# compared in WGS 84 (sf's spherical predicates).
ofo_missions_covering <- function(missions, plot_poly) {
  fp <- sf::st_make_valid(sf::st_transform(sf::st_geometry(missions), 4326))
  pg <- sf::st_make_valid(sf::st_transform(sf::st_geometry(plot_poly), 4326))
  pg <- sf::st_union(pg)
  as.vector(sf::st_covers(fp, pg, sparse = FALSE)[, 1])
}

# Candidate missions in the order they are tried: footprint covers the plot,
# pitch within 10 degrees of nadir, a mission date; closest to the survey
# first, ties to the lower mission ID. A mission without a readable pitch is
# never a candidate (nadir cannot be shown).
ofo_mission_candidates <- function(missions, covers, survey_date,
                                   pitch_max = OFO_PITCH_MAX) {
  m <- as.data.frame(missions)
  m$pitch <- ofo_mission_pitch(m$camera_pitch_derived, m$camera_pitch_nominal)
  m$mission_date <- ofo_mission_date(m$earliest_date_derived, m$date)
  keep <- covers & !is.na(m$pitch) & m$pitch <= pitch_max & !is.na(m$mission_date)
  m <- m[keep, c("mission_id", "pitch", "mission_date"), drop = FALSE]
  m$dt_days <- abs(as.numeric(m$mission_date - as.Date(survey_date)))
  m[order(m$dt_days, m$mission_id), , drop = FALSE]
}

# Try candidates in order; `reader(mission_id)` returns a usable surface or
# NULL (or fails). Returns the first usable one with the attempts made and
# the read errors by mission.
ofo_choose_mission <- function(cands, reader) {
  tried <- character()
  errors <- character()
  for (i in seq_len(nrow(cands))) {
    id <- cands$mission_id[i]
    s <- tryCatch(reader(id), error = function(e) {
      errors[[id]] <<- conditionMessage(e)
      NULL
    })
    ok <- is.list(s) && length(s) > 0
    tried <- c(tried, sprintf("%s:%s", id, if (ok) "used" else
      if (id %in% names(errors)) "error" else "unusable"))
    if (ok) return(list(row = cands[i, , drop = FALSE], surface = s, tried = tried,
                        errors = errors))
  }
  list(row = NULL, surface = NULL, tried = tried, errors = errors)
}

ofo_chm_url <- function(mission_id) sprintf(OFO_CHM_URL, mission_id, mission_id)

# ---- 5 m comparison grid ----------------------------------------------------

# Grid cells (aligned with the project frame at multiples of `cell`) whose
# centre lies inside the plot polygon. `poly` is an sfc in the project frame.
ofo_plot_cells <- function(poly, cell = OFO_CELL) {
  bb <- sf::st_bbox(poly)
  ix <- seq(floor(bb[["xmin"]] / cell), floor(bb[["xmax"]] / cell))
  iy <- seq(floor(bb[["ymin"]] / cell), floor(bb[["ymax"]] / cell))
  g <- expand.grid(ix = ix, iy = iy)
  g$cx <- (g$ix + 0.5) * cell
  g$cy <- (g$iy + 0.5) * cell
  pts <- sf::st_as_sf(g, coords = c("cx", "cy"), crs = sf::st_crs(poly), remove = FALSE)
  inside <- lengths(sf::st_intersects(pts, sf::st_union(poly))) > 0
  g <- g[inside, , drop = FALSE]
  g$key <- paste(g$ix, g$iy)
  rownames(g) <- NULL
  g
}

# Maximum of z per grid cell, aligned with `cells` (NA where no value falls).
# Values are assigned to cells by their own position (point or pixel centre).
ofo_cell_max <- function(x, y, z, cells, cell = OFO_CELL) {
  ok <- is.finite(x) & is.finite(y) & is.finite(z)
  key <- paste(floor(x[ok] / cell), floor(y[ok] / cell))
  hit <- key %in% cells$key
  if (!any(hit)) return(rep(NA_real_, nrow(cells)))
  mx <- tapply(z[ok][hit], key[hit], max)
  unname(as.numeric(mx[cells$key]))
}

# Loss share: canopy cells of the earlier surface whose later height is below
# half the earlier; reverse share the same from the later surface. Cells
# missing in either surface are excluded; a share without canopy cells is NA.
ofo_change_shares <- function(early, late, canopy = OFO_CANOPY_MIN) {
  both <- !is.na(early) & !is.na(late)
  e <- early[both]
  l <- late[both]
  ce <- e >= canopy
  cl <- l >= canopy
  share <- function(n, k) if (k == 0) NA_real_ else n / k
  list(n_compared = sum(both), n_canopy_early = sum(ce), n_canopy_late = sum(cl),
       loss_share = share(sum(l[ce] < 0.5 * e[ce]), sum(ce)),
       reverse_share = share(sum(e[cl] < 0.5 * l[cl]), sum(cl)))
}

# Unresolved takes precedence over disturbed; an NA share (no canopy cells)
# exceeds nothing.
ofo_disturbance_status <- function(usable, loss_share, reverse_share,
                                   max_share = OFO_SHARE_MAX) {
  gt <- function(v) !is.na(v) & v > max_share
  ifelse(!usable, "not_checked",
         ifelse(gt(reverse_share), "unresolved",
                ifelse(gt(loss_share), "disturbed", "undisturbed")))
}

# The comparison covers the flight-to-survey interval when the mission is
# within a year of the survey, or the survey lies between flight and mission.
ofo_interval_covered <- function(mission_date, survey_date, flight_date,
                                 days = OFO_COVER_DAYS) {
  m <- as.Date(mission_date)
  s <- as.Date(survey_date)
  f <- as.Date(flight_date)
  near <- abs(as.numeric(m - s)) <= days
  between <- s >= pmin(m, f) & s <= pmax(m, f)
  out <- (!is.na(near) & near) | (!is.na(between) & between)
  out[is.na(m) | is.na(s)] <- NA
  out
}

# `failed` marks plots whose check broke on our side (3DEP surface or worker
# error): not a missing drone model, so the same-year route does not apply.
ofo_disturbance_admitted <- function(status, covered, flight_year, survey_year,
                                     failed = FALSE) {
  same <- !is.na(flight_year) & !is.na(survey_year) & flight_year == survey_year
  cov <- !is.na(covered) & covered
  ((status == "undisturbed" & cov) |
     ((status == "not_checked" | !cov) & !status %in% c("disturbed", "unresolved") & same)) &
    !failed
}

# ---- Flight dates and seasonal windows -----------------------------------------

# Dates checked for one flight: exactly its flight dates, the distinct UTC
# days of the GPS times of the kept returns inside the plot (flights.csv
# `flight_days`, ISO dates joined by ";"), never the days between them
# (protocol "Admitted flights" and "Snow": "for each flight date").
ofo_flight_dates <- function(flight_days) {
  if (length(flight_days) != 1L || is.na(flight_days) || !nzchar(trimws(flight_days)))
    return(as.Date(character()))
  d <- as.Date(trimws(strsplit(as.character(flight_days), ";", fixed = TRUE)[[1]]),
               optional = TRUE)
  if (anyNA(d)) stop("flight_days holds a value that is not an ISO date: ", flight_days)
  sort(unique(d))
}

# Month-day window that may cross the new year (start after end).
ofo_in_window <- function(dates, window) {
  md <- format(as.Date(dates), "%m-%d")
  if (window[1] <= window[2]) md >= window[1] & md <= window[2]
  else md >= window[1] | md <= window[2]
}

ofo_snow_dates <- function(dates) dates[ofo_in_window(dates, OFO_SNOW_WINDOW)]
# Leaf-off when any flight date falls in the window.
ofo_leafoff_window <- function(dates) any(ofo_in_window(dates, OFO_LEAF_WINDOW))

# Snow status from the depths (m) read on the window dates (NA = file or cell
# unavailable). Any snow is decisive; otherwise one unreadable date leaves the
# plot unknown.
ofo_snow_status <- function(in_window, depths) {
  if (!in_window) return("not_winter")
  if (any(!is.na(depths) & depths > 0)) return("snow")
  if (!length(depths) || anyNA(depths)) return("unknown")
  "snow_free"
}

ofo_deciduous_share <- function(species, ref, deciduous = OFO_WINTER_DECIDUOUS) {
  ref <- !is.na(ref) & ref
  if (!any(ref)) return(NA_real_)
  mean(!is.na(species[ref]) & species[ref] %in% deciduous)
}

# A plot without reference stems has no deciduous share and is not held here.
ofo_leafoff_status <- function(in_window, share, max_share = OFO_DECID_MAX) {
  ifelse(!in_window, "leaf_on",
         ifelse(!is.na(share) & share >= max_share, "leaf_off_held", "leaf_off_minor"))
}

# ---- Admission ----------------------------------------------------------------

ofo_conditions_admitted <- function(disturbance_admitted, snow_status, leafoff_status) {
  (!is.na(disturbance_admitted) & disturbance_admitted) &
    snow_status %in% c("not_winter", "snow_free") & leafoff_status != "leaf_off_held"
}

# Semicolon-joined failed checks, empty when admitted. A plot not admitted on
# disturbance without being disturbed or unresolved has flight and survey in
# different calendar years and no check covering that interval: either no
# usable drone model, or a model that does not cover the interval.
ofo_conditions_reason <- function(disturbance_status, disturbance_admitted, snow_status,
                                  leafoff_status, failed = FALSE) {
  n <- length(disturbance_status)
  failed <- rep_len(failed, n)
  vapply(seq_len(n), function(i) {
    r <- character()
    ds <- disturbance_status[i]
    da <- !is.na(disturbance_admitted[i]) && disturbance_admitted[i]
    if (failed[i]) r <- c(r, "disturbance_check_failed")
    else if (ds %in% c("disturbed", "unresolved")) r <- c(r, ds)
    else if (!da) r <- c(r, if (ds == "not_checked") "no_usable_drone_model"
                          else "interval_not_covered")
    if (snow_status[i] == "snow") r <- c(r, "snow")
    if (snow_status[i] == "unknown") r <- c(r, "snow_unknown")
    if (leafoff_status[i] == "leaf_off_held") r <- c(r, "leaf_off")
    paste(r, collapse = ";")
  }, character(1))
}

# ---- SNODAS -------------------------------------------------------------------

snodas_url <- function(date, base = OFO_SNODAS_BASE) {
  d <- as.Date(date)
  sprintf("%s/%s/%s/SNODAS_%s.tar", base, format(d, "%Y"), format(d, "%m_%b"),
          format(d, "%Y%m%d"))
}

# Member of a daily tar holding product `code` (snow depth = 1036), data or
# header. The header's own "Product code" field is not the product code, so
# the file name (us_ssmv1<code>...) identifies the member.
snodas_member <- function(files, code = "1036", ext = c("dat", "txt")) {
  ext <- match.arg(ext)
  hit <- grep(sprintf("^us_ssmv1%s.*\\.%s(\\.gz)?$", code, ext), basename(files), value = TRUE)
  if (length(hit) != 1) stop(sprintf("expected one %s member for product %s, found %d",
                                     ext, code, length(hit)))
  files[basename(files) == hit]
}

# NOHRSC raster header ("Key: value" lines) as a named list of strings.
snodas_parse_header <- function(lines) {
  lines <- lines[grepl(":", lines, fixed = TRUE)]
  key <- trimws(sub(":.*$", "", lines))
  val <- trimws(sub("^[^:]*:", "", lines))
  setNames(as.list(val), key)
}

# Grid geometry and scaling read from the header, refusing anything the
# reader does not handle.
snodas_grid <- function(h) {
  num <- function(k) {
    if (is.null(h[[k]])) stop("SNODAS header lacks '", k, "'")
    as.numeric(h[[k]])
  }
  if (!identical(tolower(h[["Data type"]]), "integer")) stop("SNODAS data type not integer")
  units <- h[["Data units"]]
  if (is.null(units) || !grepl("^meters", tolower(units))) stop("SNODAS units not metres: ", units)
  div <- if (grepl("/", units, fixed = TRUE)) as.numeric(trimws(sub("^.*/", "", units))) else 1
  g <- list(ncol = num("Number of columns"), nrow = num("Number of rows"),
            xmin = num("Minimum x-axis coordinate"), ymax = num("Maximum y-axis coordinate"),
            xres = num("X-axis resolution"), yres = num("Y-axis resolution"),
            nodata = num("No data value"), slope = num("Data slope"),
            intercept = num("Data intercept"), bytes = num("Data bytes per pixel"),
            divisor = div, description = h[["Description"]])
  if (g$bytes != 2) stop("SNODAS reader expects 2 bytes per pixel")
  g
}

# 0-based (row, col) of lon/lat in the grid, NA outside it.
snodas_cell <- function(g, lon, lat) {
  col <- floor((lon - g$xmin) / g$xres)
  row <- floor((g$ymax - lat) / g$yres)
  bad <- is.na(col) | is.na(row) | col < 0 | col >= g$ncol | row < 0 | row >= g$nrow
  col[bad] <- NA
  row[bad] <- NA
  list(row = row, col = col)
}

# Values (m) at lon/lat from a gzipped (or plain) big-endian 16-bit grid.
# The whole grid is read so its size is checked against the header.
snodas_read_values <- function(dat_path, g, lon, lat) {
  n <- g$ncol * g$nrow * g$bytes
  con <- if (grepl("\\.gz$", dat_path)) gzfile(dat_path, "rb") else file(dat_path, "rb")
  on.exit(close(con))
  raw <- readBin(con, "raw", n = n + 1)
  if (length(raw) != n) stop(sprintf("SNODAS grid holds %d bytes, header implies %d",
                                     length(raw), n))
  rc <- snodas_cell(g, lon, lat)
  off <- (rc$row * g$ncol + rc$col) * 2
  out <- rep(NA_real_, length(lon))
  ok <- !is.na(off)
  if (any(ok)) {
    v <- as.integer(raw[off[ok] + 1]) * 256L + as.integer(raw[off[ok] + 2])
    v <- ifelse(v >= 32768L, v - 65536L, v)
    val <- ifelse(v == g$nodata, NA_real_, (v * g$slope + g$intercept) / g$divisor)
    out[ok] <- val
  }
  out
}

# Snow depth (m) at lon/lat from one daily tar. Extracts the depth members
# to `tmp` and checks the header describes snow thickness.
snodas_depth_from_tar <- function(tar_path, lon, lat, tmp = tempfile("snodas_")) {
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE))
  files <- utils::untar(tar_path, list = TRUE)
  hdr <- snodas_member(files, ext = "txt")
  dat <- snodas_member(files, ext = "dat")
  utils::untar(tar_path, files = c(hdr, dat), exdir = tmp)
  hp <- file.path(tmp, hdr)
  lines <- readLines(if (grepl("\\.gz$", hp)) gzfile(hp) else hp, warn = FALSE)
  g <- snodas_grid(snodas_parse_header(lines))
  if (!grepl("snow layer thickness", tolower(g$description), fixed = TRUE))
    stop("SNODAS member is not snow depth: ", g$description)
  snodas_read_values(file.path(tmp, dat), g, lon, lat)
}
