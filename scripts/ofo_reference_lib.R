# Open Forest Observatory (OFO) preflight, decision stage: scoring cells, plot
# admission, group floors, the per-group go/hold/no-go decision and the mapping
# of the catalogue tree table to the benchmark's ground_truth_stems.csv /
# plot_centroids.csv schema (scripts/neon_ground_truth.R). Implements the
# sections "Scoring cells", "Reference schema", "Plot groups and reference
# populations" (group floor) and "Decision per group" of
# docs/ofo-preflight-protocol.md. Pure functions; the drivers are
# preflight_ofo_decision.R and prepare_ofo_reference.R. Score-blind: nothing
# here detects trees or scores detections.

OFO_GROUPS <- c("A", "B", "C", "D")
# Groups A and C carry measured heights; B and D register on diameter rank.
OFO_GROUP_SIGNAL <- c(A = "height", B = "rank", C = "height", D = "rank")
# Groups whose stems match on position alone (protocol "Missing heights"): their
# reference tables carry no height, so the scorer's height gate cannot run.
OFO_NO_HEIGHT_GROUPS <- c("B", "D")
# A reference directory name is the SITE= of the arms and a path component.
OFO_SITE_PATTERN <- "^[A-Za-z0-9][A-Za-z0-9_-]*$"
OFO_CELL_SIZE <- 40        # m, the core of a NEON tower plot
OFO_CELL_STEP <- 5         # m, grid offset increments
OFO_CELL_MIN_INSIDE <- 0.99
OFO_HEADLINE_MIN <- 6L     # reference stems for a headline cell (six-stem gate)
OFO_GO_PLOTS <- 3L
OFO_GO_STEMS <- 100L
OFO_AB_FLOOR <- 10         # cm, the benchmark's `adopted` gate
OFO_NEON_PROJECT <- "NEON2023"
OFO_EPS <- 1e-9            # diameters at a floor, as the catalogue stage compares them
# Gates of plot admission, in report order.
OFO_GATES <- c("screen_ok", "flight_admitted", "geometry_consistent",
               "conditions_admitted", "registered")
# Licences of the catalogue and their archive mode (protocol "Licences").
OFO_LICENCES <- data.frame(
  license_short = c("CC BY 4.0", "CC0 1.0", "Public domain", "CC BY SA 4.0",
                    "CC BY NC SA 4.0"),
  archive_mode = c("redistribute", "redistribute", "redistribute", "rebuild_only",
                   "rebuild_only"),
  stringsAsFactors = FALSE)
# Column order of scripts/neon_ground_truth.R's ground_truth_stems.csv.
OFO_GT_COLUMNS <- c("individualID", "plotID", "tile", "tile_e", "tile_n", "E", "N",
                    "pos_unc", "taxonID", "scientificName", "height", "stemDiameter",
                    "maxCrownDiameter", "ninetyCrownDiameter", "plantStatus",
                    "canopyPosition", "crown_class", "live", "is_tree", "meas_year",
                    "dist21", "dist_aop", "acquisition_year", "utmZone", "epsg")
OFO_GT_EXTRA <- c("ofo_plot_id", "project", "group", "E_raw", "N_raw", "shift_dx",
                  "shift_dy", "crown_source", "license_short", "withhold_from_training",
                  "height_recorded", "site", "crown_position_recorded")
# NEON canopyPosition labels whose crown class (neon_ground_truth.R cc_map)
# equals the OFO crown_position class, so a recorded position reads as one.
OFO_CANOPY_LABEL <- c("Open grown", "Full sun", "Partially shaded", "Mostly shaded",
                      "Full shade")
OFO_CROWN_CLASS <- c("dominant", "dominant", "codominant", "intermediate", "suppressed")

## ---- geometry ----------------------------------------------------------------

# Plot polygon (WKT in the project frame) as a single-geometry sfc.
ofo_polygon <- function(wkt, epsg) {
  if (length(wkt) != 1L || is.na(wkt) || !nzchar(wkt)) stop("Missing plot polygon WKT")
  g <- sf::st_as_sfc(wkt, crs = as.integer(epsg))
  if (length(g) != 1L || any(sf::st_is_empty(g))) stop("Plot polygon WKT is empty")
  if (!all(sf::st_is_valid(g))) stop("Plot polygon is not valid")
  g
}

# Rigid shift of a polygon; sf arithmetic drops the CRS, so it is restored.
ofo_shift_polygon <- function(polygon, dx, dy) {
  if (!is.finite(dx) || !is.finite(dy)) stop("Plot shift must be finite")
  crs <- sf::st_crs(polygon)
  sf::st_set_crs(sf::st_geometry(polygon) + c(dx, dy), crs)
}

ofo_check_projected <- function(polygon) {
  if (!is.na(sf::st_crs(polygon)) && isTRUE(sf::st_is_longlat(polygon)))
    stop("OFO cells need a polygon in a projected metric frame")
  invisible(TRUE)
}

ofo_square <- function(x0, y0, size)
  sf::st_polygon(list(matrix(c(x0, y0, x0 + size, y0, x0 + size, y0 + size,
                               x0, y0 + size, x0, y0), ncol = 2, byrow = TRUE)))

# Scoring cells of one registered plot (protocol "Scoring cells"). Grid lines
# lie at offset + size * i in the project frame; the offset runs over multiples
# of `step` in [0, size). A cell is admitted when at least `min_inside` of its
# area lies inside the polygon. The offset admitting most cells wins, ties to
# the smallest ox, then oy. Cells are numbered by cy, then cx. Returns k, cx,
# cy, inside_share (attribute "offset" = c(ox, oy)).
ofo_cells <- function(polygon, size = OFO_CELL_SIZE, step = OFO_CELL_STEP,
                      min_inside = OFO_CELL_MIN_INSIDE) {
  polygon <- sf::st_union(sf::st_geometry(polygon))
  ofo_check_projected(polygon)
  crs <- sf::st_crs(polygon)
  empty <- data.frame(k = integer(), cx = numeric(), cy = numeric(),
                      inside_share = numeric())
  if (!length(polygon) || all(sf::st_is_empty(polygon))) return(empty)
  bb <- as.numeric(sf::st_bbox(polygon))
  offs <- step * seq(0, ceiling(size / step) - 1)
  cand <- do.call(rbind, lapply(offs, function(ox) do.call(rbind, lapply(offs, function(oy) {
    ix <- seq(floor((bb[1] - ox) / size), ceiling((bb[3] - ox) / size) - 1)
    iy <- seq(floor((bb[2] - oy) / size), ceiling((bb[4] - oy) / size) - 1)
    g <- expand.grid(ix = ix, iy = iy)
    data.frame(ox = ox, oy = oy, x0 = ox + size * g$ix, y0 = oy + size * g$iy)
  }))))
  sq <- sf::st_sfc(lapply(seq_len(nrow(cand)), function(i)
    ofo_square(cand$x0[i], cand$y0[i], size)), crs = crs)
  ii <- sf::st_intersection(sq, polygon)
  share <- numeric(nrow(cand))
  if (length(ii)) {
    a <- as.numeric(sf::st_area(ii)) / size^2
    share <- as.numeric(tapply(c(a, numeric(nrow(cand))),
                               c(attr(ii, "idx")[, 1], seq_len(nrow(cand))), sum))
  }
  # GEOS areas carry rounding error far below the 1% admission margin.
  cand$share <- pmin(1, share)
  cand$admit <- cand$share >= min_inside - 1e-9
  n <- aggregate(admit ~ ox + oy, data = cand, FUN = sum)
  n <- n[order(-n$admit, n$ox, n$oy), , drop = FALSE]
  best <- n[1, ]
  out <- cand[cand$admit & cand$ox == best$ox & cand$oy == best$oy, , drop = FALSE]
  out <- out[order(out$y0, out$x0), , drop = FALSE]
  res <- if (nrow(out)) data.frame(k = seq_len(nrow(out)), cx = out$x0 + size / 2,
                                   cy = out$y0 + size / 2, inside_share = out$share)
         else empty
  attr(res, "offset") <- c(ox = best$ox, oy = best$oy)
  res
}

# Stems covered by the polygon (boundary counts as inside).
ofo_in_polygon <- function(x, y, polygon) {
  out <- logical(length(x))
  ok <- is.finite(x) & is.finite(y)
  if (!any(ok)) return(out)
  pts <- sf::st_as_sf(data.frame(x = x[ok], y = y[ok]), coords = c("x", "y"),
                      crs = sf::st_crs(polygon))
  out[ok] <- lengths(sf::st_intersects(pts, sf::st_union(sf::st_geometry(polygon)))) > 0
  out
}

# Cell k of each stem: inside both the (closed) cell square and the polygon. A
# stem exactly on an edge shared by two cells goes to the lower k. NA outside.
ofo_assign_cells <- function(x, y, cells, polygon, size = OFO_CELL_SIZE) {
  k <- rep(NA_integer_, length(x))
  if (!nrow(cells) || !length(x)) return(k)
  inside <- ofo_in_polygon(x, y, polygon)
  h <- size / 2
  # Highest k first, so a lower k overwrites it on a shared edge.
  for (i in order(cells$k, decreasing = TRUE)) {
    hit <- inside & abs(x - cells$cx[i]) <= h & abs(y - cells$cy[i]) <= h
    k[hit %in% TRUE] <- as.integer(cells$k[i])
  }
  k
}

## ---- admission, floors and reference --------------------------------------------

ofo_lgl <- function(x) {
  if (is.logical(x)) return(x)
  if (is.numeric(x)) return(as.logical(x))
  v <- toupper(trimws(as.character(x)))
  ifelse(v %in% c("TRUE", "T", "1"), TRUE, ifelse(v %in% c("FALSE", "F", "0"), FALSE, NA))
}

ofo_blank <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))

# Sub-status of the conditions gate. "unchecked" is a failure only because a
# check could not be made: disturbance not checked (or the interval not
# covered) without a same-year flight, or snow depth unknown. "evidence" is a
# failure on evidence (disturbed, unresolved, snow, leaf-off held).
OFO_DISTURBANCE <- c("undisturbed", "disturbed", "unresolved", "not_checked")
OFO_SNOW <- c("not_winter", "snow_free", "snow", "unknown")
OFO_LEAFOFF <- c("leaf_on", "leaf_off_minor", "leaf_off_held")
ofo_conditions_check <- function(conditions) {
  ds <- as.character(conditions$disturbance_status)
  ss <- as.character(conditions$snow_status)
  ls <- as.character(conditions$leafoff_status)
  bad <- c(setdiff(ds, OFO_DISTURBANCE), setdiff(ss, OFO_SNOW), setdiff(ls, OFO_LEAFOFF))
  if (length(bad))
    stop("conditions.csv: unknown status values: ", paste(unique(bad), collapse = ", "))
  dist_ok <- ofo_lgl(conditions$disturbance_admitted) %in% TRUE
  admitted <- ofo_lgl(conditions$conditions_admitted) %in% TRUE
  evidence <- ds %in% c("disturbed", "unresolved") | ss == "snow" | ls == "leaf_off_held"
  unchecked <- (!dist_ok & !ds %in% c("disturbed", "unresolved")) | ss == "unknown"
  status <- ifelse(admitted, "pass", ifelse(evidence, "evidence",
                   ifelse(unchecked, "unchecked", "unattributed")))
  # A pass that contradicts its own status columns is reported, not trusted.
  status[admitted & (evidence | unchecked)] <- "inconsistent"
  status
}

# Admission of every non-NEON plot (protocol "Decision per group", rule 2):
# screened in with a group, admitted flight, consistent geometry, admitted
# conditions, registered. A missing row fails its gate. `unchecked_only` marks
# plots whose only failure is an unchecked conditions check (the hold rule).
ofo_plot_admission <- function(plots, flights, geometry, conditions, registration) {
  p <- plots[plots$project_name != OFO_NEON_PROJECT, , drop = FALSE]
  get <- function(tab, col) {
    v <- tab[[col]][match(p$plot_id, tab$plot_id)]
    if (is.null(v)) rep(NA, nrow(p)) else v
  }
  grp <- as.character(p$group); grp[ofo_blank(grp)] <- NA_character_
  out <- data.frame(plot_id = p$plot_id, project_name = p$project_name, group = grp,
                    screen = p$screen, stringsAsFactors = FALSE)
  out$screen_ok <- out$screen %in% "none" & out$group %in% OFO_GROUPS
  out$flight_admitted <- ofo_lgl(get(flights, "flight_admitted")) %in% TRUE
  out$geometry_consistent <- ofo_lgl(get(geometry, "geometry_consistent")) %in% TRUE
  out$conditions_admitted <- ofo_lgl(get(conditions, "conditions_admitted")) %in% TRUE
  out$registered <- ofo_lgl(get(registration, "registered")) %in% TRUE
  gates <- as.matrix(out[, OFO_GATES, drop = FALSE])
  out$admitted <- rowSums(!gates) == 0
  out$reason <- vapply(seq_len(nrow(gates)), function(i)
    paste(OFO_GATES[!gates[i, ]], collapse = ";"), character(1))
  m <- match(out$plot_id, conditions$plot_id)
  chk <- rep("missing", nrow(out))
  if (nrow(conditions)) chk[!is.na(m)] <- ofo_conditions_check(conditions)[m[!is.na(m)]]
  out$conditions_check <- chk
  # Protocol 2: a registration failing only because its signal's test could
  # not be made (registration_check "unchecked") is unchecked too. Without
  # that column (protocol 1) every registration failure is evidence.
  has_rc <- "registration_check" %in% names(registration)
  rc <- if (has_rc) get(registration, "registration_check") else rep(NA_character_, nrow(out))
  reg_unchecked <- !out$registered & rc %in% "unchecked"
  # The column is reported only where the input carries it, so protocol 1's
  # tables keep their columns.
  if (has_rc) out$registration_check <- ifelse(out$registered, "registered",
                                               ifelse(reg_unchecked, "unchecked", "evidence"))
  cond_unchecked <- out$conditions_check == "unchecked"
  evidence_ok <- out$screen_ok & out$flight_admitted & out$geometry_consistent
  out$unchecked_only <- !out$admitted & evidence_ok &
    (out$registered | reg_unchecked) & (out$conditions_admitted | cond_unchecked) &
    (reg_unchecked | cond_unchecked)
  out$flight_reason <- get(flights, "flight_reason")
  out$conditions_reason <- get(conditions, "conditions_reason")
  out$registration_reason <- get(registration, "reason")
  out
}

# Group floors (protocol "Plot groups"): A and B at 10 cm; C and D at the
# largest live diameter floor among the group's admitted plots (NA when the
# group has none). `x` holds group, admitted and live_floor_cm per plot.
ofo_group_floors <- function(x) {
  do.call(rbind, lapply(OFO_GROUPS, function(g) {
    a <- x[x$group %in% g & x$admitted %in% TRUE, , drop = FALSE]
    fl <- if (g %in% c("A", "B")) OFO_AB_FLOOR
          else if (nrow(a) && any(is.finite(a$live_floor_cm))) max(a$live_floor_cm, na.rm = TRUE)
          else NA_real_
    data.frame(group = g, floor_cm = fl, n_admitted = nrow(a), stringsAsFactors = FALSE)
  }))
}

# Reference stems under a floor: live, a tree, inside the plot polygon and a
# diameter at or above the floor (a missing diameter or floor never passes).
ofo_reference_flag <- function(trees, floor_cm) {
  floor_cm <- rep_len(floor_cm, nrow(trees))
  (trees$live %in% TRUE) & (trees$is_tree %in% TRUE) & (trees$inside %in% TRUE) &
    !is.na(trees$dbh) & !is.na(floor_cm) & trees$dbh >= floor_cm - OFO_EPS
}

## ---- crown class ------------------------------------------------------------------

# Crown class from crown_position (1, 2 dominant; 3 codominant; 4 intermediate;
# 5 suppressed), else the within-plot height-quantile fallback of
# neon_ground_truth.R: per plot, the stems lacking a class but carrying a
# height, when at least four, cut at the 0.33/0.66/0.9 quantiles.
# canopyPosition holds the matching NEON label only where crown_position gave
# the class, so ext_crown_source() reads it as a recorded position. Stems with
# `fallback` FALSE take a class from a recorded position only and stay out of
# the quantile pool (ofo_ground_truth() then reports no class at all for
# groups B and D).
ofo_crown_class <- function(crown_position, height, plot, fallback = TRUE) {
  cp <- suppressWarnings(as.integer(crown_position))
  cp[!cp %in% 1:5] <- NA_integer_
  cls <- OFO_CROWN_CLASS[cp]
  label <- OFO_CANOPY_LABEL[cp]
  height <- suppressWarnings(as.numeric(height))
  fallback <- rep_len(as.logical(fallback), length(cp)) %in% TRUE
  src <- ifelse(is.na(cls), "none", "canopyPosition")
  need <- is.na(cls) & !is.na(height) & fallback
  for (p in unique(plot[need])) {
    idx <- which(plot == p & need)
    if (length(idx) >= 4) {
      q <- quantile(height[idx], c(.33, .66, .9), na.rm = TRUE)
      # The right-closed intervals of cut(c(-Inf, q, Inf)), counted directly:
      # identical classes, but tied quantiles (rounded heights) cannot abort.
      b <- 1L + (height[idx] > q[1]) + (height[idx] > q[2]) + (height[idx] > q[3])
      cls[idx] <- c("suppressed", "intermediate", "codominant", "dominant")[b]
      src[idx] <- "height_fallback"
    }
  }
  data.frame(canopyPosition = label, crown_class = cls, crown_source = src,
             stringsAsFactors = FALSE)
}

## ---- licences -----------------------------------------------------------------------

# Archive mode per plot licence: redistribute (CC BY 4.0, CC0 1.0, Public
# domain), rebuild_only (share-alike, non-commercial) or NA (not a catalogue
# licence, so handling is unknown).
ofo_archive_mode <- function(license_short) {
  norm <- function(x) toupper(gsub("\\s+", " ", trimws(as.character(x))))
  OFO_LICENCES$archive_mode[match(norm(license_short), norm(OFO_LICENCES$license_short))]
}

## ---- registration signals -------------------------------------------------------

# Which registration signals are admitted, from registration_tests.json
# (parsed with simplifyVector = TRUE). The final admission is the top-level
# `admitted: {height: true|false, rank: true|false}` and nothing else: the
# report also carries per-test and per-amendment blocks (some with their own
# `admitted` or `pass` fields) that must never stand in for it. Other keys,
# at the top level or inside `admitted`, are ignored. Returns c(height, rank).
ofo_signals_admitted <- function(tests) {
  hint <- "expected {\"admitted\": {\"height\": true|false, \"rank\": true|false}}"
  if (!is.list(tests) || !"admitted" %in% names(tests))
    stop("registration_tests.json has no top-level `admitted` key (the final admission ",
         "of the registration stage; is the stage complete?); ", hint, call. = FALSE)
  a <- tests[["admitted"]]
  one <- function(k) is.list(a) && k %in% names(a) && is.logical(a[[k]]) &&
    length(a[[k]]) == 1L && !is.na(a[[k]])
  bad <- c("height", "rank")[!c(one("height"), one("rank"))]
  if (length(bad))
    stop("registration_tests.json: `admitted` lacks a true/false value for ",
         paste(bad, collapse = " and "), "; ", hint, call. = FALSE)
  c(height = a[["height"]], rank = a[["rank"]])
}

## ---- locating stems in registered plots -------------------------------------------

# For each registered plot: shifted polygon, scoring cells and the cell of every
# stem. Returns list(cells, stems): cells of every registered plot (admitted or
# not), and all trees of the non-NEON plots with E/N (registered position; NA
# when the plot is not registered), the shift, polygon membership and cell.
ofo_locate <- function(plots, trees, registration, size = OFO_CELL_SIZE,
                       step = OFO_CELL_STEP, min_inside = OFO_CELL_MIN_INSIDE) {
  keep_plots <- plots$plot_id[plots$project_name != OFO_NEON_PROJECT]
  st <- trees[trees$plot_id %in% keep_plots, , drop = FALSE]
  st$E <- NA_real_; st$N <- NA_real_
  st$shift_dx <- NA_real_; st$shift_dy <- NA_real_; st$pos_unc <- NA_real_
  st$in_polygon <- NA; st$cell <- NA_integer_; st$cell_id <- NA_character_
  # Protocol 2 also places plots whose registration is only unchecked, at
  # their method estimate, so that the hold rule can count their cells; they
  # are never admitted on that basis.
  located <- ofo_lgl(registration$registered) %in% TRUE |
    (if ("registration_check" %in% names(registration))
      registration$registration_check %in% "unchecked" else FALSE)
  reg <- registration[located & registration$plot_id %in% keep_plots, , drop = FALSE]
  cells <- list()
  for (i in seq_len(nrow(reg))) {
    pid <- reg$plot_id[i]
    pr <- plots[match(pid, plots$plot_id), ]
    dx <- as.numeric(reg$dx[i]); dy <- as.numeric(reg$dy[i])
    poly <- tryCatch(ofo_shift_polygon(ofo_polygon(pr$polygon_wkt, pr$epsg), dx, dy),
                     error = function(e) stop("plot ", pid, ": ", conditionMessage(e),
                                              call. = FALSE))
    ce <- ofo_cells(poly, size, step, min_inside)
    if (nrow(ce)) {
      cells[[pid]] <- data.frame(plot_id = pid, project_name = pr$project_name,
        group = pr$group, cell = ce$k, cell_id = sprintf("%s_%d", pid, ce$k),
        cx = ce$cx, cy = ce$cy, epsg = as.integer(pr$epsg),
        inside_share = ce$inside_share, offset_x = attr(ce, "offset")[["ox"]],
        offset_y = attr(ce, "offset")[["oy"]], stringsAsFactors = FALSE)
    }
    j <- which(st$plot_id == pid)
    if (!length(j)) next
    pu <- as.numeric(reg$pos_unc[i])
    if (!is.finite(pu)) pu <- max(0.5, as.numeric(reg$residual_m[i]))
    st$E[j] <- st$x[j] + dx; st$N[j] <- st$y[j] + dy
    st$shift_dx[j] <- dx; st$shift_dy[j] <- dy; st$pos_unc[j] <- pu
    st$in_polygon[j] <- ofo_in_polygon(st$E[j], st$N[j], poly)
    k <- ofo_assign_cells(st$E[j], st$N[j], ce, poly, size)
    st$cell[j] <- k
    st$cell_id[j] <- ifelse(is.na(k), NA_character_, sprintf("%s_%d", pid, k))
  }
  cells <- if (length(cells)) do.call(rbind, cells) else
    data.frame(plot_id = character(), project_name = character(), group = character(),
               cell = integer(), cell_id = character(), cx = numeric(), cy = numeric(),
               epsg = integer(), inside_share = numeric(), offset_x = numeric(),
               offset_y = numeric(), stringsAsFactors = FALSE)
  rownames(cells) <- NULL
  list(cells = cells, stems = st)
}

# Per-plot floor: the group floor, falling back for display to `fallback`
# (C/D groups with no admitted plot); ungrouped plots use 10 cm.
ofo_plot_floor <- function(group, floors, fallback = NULL) {
  f <- floors$floor_cm[match(group, floors$group)]
  if (!is.null(fallback)) {
    fb <- fallback[match(group, names(fallback))]
    f[is.na(f) & !is.na(fb)] <- fb[is.na(f) & !is.na(fb)]
  }
  f[is.na(group)] <- OFO_AB_FLOOR
  f
}

# Reference stems per cell under each plot's floor; headline at >= 6.
ofo_count_cells <- function(cells, stems, plot_floor) {
  if (!nrow(cells)) return(transform(cells, n_ref = integer(), headline = logical()))
  ref <- ofo_reference_flag(stems, plot_floor[stems$plot_id]) &
    stems$in_polygon %in% TRUE & !is.na(stems$cell_id)
  n <- table(factor(stems$cell_id[ref], levels = cells$cell_id))
  cells$n_ref <- as.integer(n[cells$cell_id])
  cells$headline <- cells$n_ref >= OFO_HEADLINE_MIN
  cells
}

# Per-plot counts: cells, headline cells, reference stems in the plot / in
# cells / in headline cells, polygon area and cell area.
ofo_plot_counts <- function(plot_ids, cells, stems, plot_floor, plot_area_m2,
                            size = OFO_CELL_SIZE) {
  ref <- ofo_reference_flag(stems, plot_floor[stems$plot_id])
  in_cell <- ref & stems$in_polygon %in% TRUE & !is.na(stems$cell_id)
  head_ids <- cells$cell_id[cells$headline %in% TRUE]
  cnt <- function(v) as.integer(table(factor(stems$plot_id[v], levels = plot_ids)))
  nc <- table(factor(cells$plot_id, levels = plot_ids))
  nh <- table(factor(cells$plot_id[cells$headline %in% TRUE], levels = plot_ids))
  data.frame(plot_id = plot_ids, n_cells = as.integer(nc), n_cells_headline = as.integer(nh),
             n_ref_plot = cnt(ref), n_ref_cells = cnt(in_cell),
             n_ref_headline = cnt(in_cell & stems$cell_id %in% head_ids),
             area_plot_m2 = as.numeric(plot_area_m2[plot_ids]),
             area_cells_m2 = as.integer(nc) * size^2, stringsAsFactors = FALSE)
}

# Cells and per-plot counts when `admitted` marks the admitted plots: the
# group floors follow that set (the decision uses the admitted plots; the hold
# rule adds the plots failing only unchecked conditions). `adm` holds
# plot_id, group, live_floor_cm; `area` is polygon area by plot_id; `fallback`
# a display floor by group for C/D groups with no plot in the set.
ofo_counts_under <- function(adm, loc, admitted, area, fallback = NULL) {
  x <- adm; x$admitted <- admitted
  fl <- ofo_group_floors(x)
  pf <- setNames(ofo_plot_floor(adm$group, fl, fallback), adm$plot_id)
  ce <- ofo_count_cells(loc$cells, loc$stems, pf)
  list(floors = fl, plot_floor = pf, cells = ce,
       counts = ofo_plot_counts(adm$plot_id, ce, loc$stems, pf, area))
}

## ---- summary and decision ---------------------------------------------------------

ofo_licence_text <- function(x) {
  x <- x[!is.na(x)]
  if (!length(x)) return("")
  t <- table(x)
  paste(sprintf("%s (%d)", names(t), as.integer(t)), collapse = "; ")
}

# Per group x project and per group (project "ALL"): plots of the group, plots
# passing each gate, registered, admitted, hold-eligible, then cells, stems and
# area of the admitted plots, cells and headline stems of all registered plots
# (what each gate costs) and the admitted plots' licences. `adm` is the plot
# admission table with the per-plot counts and license_short.
ofo_group_summary <- function(adm) {
  a <- adm[adm$group %in% OFO_GROUPS, , drop = FALSE]
  one <- function(x, g, proj) {
    ad <- x[x$admitted, , drop = FALSE]
    rg <- x[x$registered, , drop = FALSE]
    data.frame(group = g, project_name = proj, plots = nrow(x),
               screen_ok = sum(x$screen_ok), flight_admitted = sum(x$flight_admitted),
               geometry_consistent = sum(x$geometry_consistent),
               conditions_admitted = sum(x$conditions_admitted),
               registered = nrow(rg), admitted = nrow(ad),
               unchecked_only = sum(x$unchecked_only),
               floor_cm = if (nrow(x)) x$floor_cm[1] else NA_real_,
               cells = sum(ad$n_cells), headline_cells = sum(ad$n_cells_headline),
               plots_with_headline = sum(ad$n_cells_headline > 0),
               ref_plot = sum(ad$n_ref_plot), ref_cells = sum(ad$n_ref_cells),
               ref_headline = sum(ad$n_ref_headline),
               area_plot_m2 = sum(ad$area_plot_m2, na.rm = TRUE),
               area_cells_m2 = sum(ad$area_cells_m2),
               cells_registered = sum(rg$n_cells),
               headline_cells_registered = sum(rg$n_cells_headline),
               ref_headline_registered = sum(rg$n_ref_headline),
               licences = ofo_licence_text(ad$license_short), stringsAsFactors = FALSE)
  }
  rows <- list()
  for (g in OFO_GROUPS) {
    x <- a[a$group == g, , drop = FALSE]
    for (p in sort(unique(x$project_name)))
      rows[[length(rows) + 1]] <- one(x[x$project_name == p, , drop = FALSE], g, p)
    rows[[length(rows) + 1]] <- one(x, g, "ALL")
  }
  do.call(rbind, rows)
}

# Decision per group (protocol "Decision per group"). go: (1) the group's
# signal is admitted, (2) at least three admitted plots whose headline cells
# hold at least 100 reference stems, (3) licence handling known for every
# admitted plot. hold: not go, signal admitted, and rule 2 met when the plots
# failing only unchecked gates are admitted too (`n_ref_headline_hold`, counted
# under the floor of that larger set). no-go otherwise. `adm` holds group,
# admitted, unchecked_only, n_ref_headline, n_ref_headline_hold, license_short.
# `inconclusive` (protocol 2): signals whose test had too few units. Such a
# signal is not admitted, so its group cannot be go. The second protocol does
# not say how an inconclusive test enters the group rule; the second preflight
# reads it as a check that could not be made, so the group may be held (its
# results state this as a reading). NULL (protocol 1) keeps the rule that hold
# needs an admitted signal.
ofo_group_decision <- function(adm, signals, floors = NULL, floors_hold = NULL,
                               min_plots = OFO_GO_PLOTS, min_stems = OFO_GO_STEMS,
                               inconclusive = NULL) {
  do.call(rbind, lapply(OFO_GROUPS, function(g) {
    x <- adm[adm$group %in% g, , drop = FALSE]
    ad <- x[x$admitted %in% TRUE, , drop = FALSE]
    hx <- x[(x$admitted | x$unchecked_only) %in% TRUE, , drop = FALSE]
    sig <- OFO_GROUP_SIGNAL[[g]]
    r1 <- isTRUE(signals[[sig]])
    r1_open <- !r1 && isTRUE(inconclusive[[sig]])
    n_plots <- nrow(ad); n_stems <- sum(ad$n_ref_headline)
    # Rule 2 counts admitted plots; how many hold a headline cell is reported.
    n_head <- sum(ad$n_ref_headline > 0)
    r2 <- n_plots >= min_plots && n_stems >= min_stems
    mode <- ofo_archive_mode(ad$license_short)
    r3 <- !anyNA(mode)
    n_hold <- nrow(hx); s_hold <- sum(hx$n_ref_headline_hold)
    r2_hold <- n_hold >= min_plots && s_hold >= min_stems
    decision <- if (r1 && r2 && r3) "go" else if ((r1 || r1_open) && r2_hold) "hold" else "no-go"
    why <- c(
      sprintf("signal %s %s", sig, if (r1) "admitted" else if (r1_open)
        "not admitted: its test was inconclusive (read as a check that could not be made)"
        else "not admitted"),
      sprintf("%d admitted plots (need %d), %d with a headline cell", n_plots, min_plots,
              n_head),
      sprintf("%d reference stems in their headline cells (need %d)", n_stems, min_stems),
      if (!n_plots) "no admitted plot whose licence to check"
      else if (r3) sprintf(paste("licence handling known for all admitted plots",
                                 "(redistribute %d, rebuild-only %d)"),
                           sum(mode == "redistribute"), sum(mode == "rebuild_only"))
      else sprintf("licence handling unknown for %d admitted plots (%s)", sum(is.na(mode)),
                   paste(unique(ad$license_short[is.na(mode)]), collapse = ", ")))
    if (decision != "go" && nrow(hx) > nrow(ad))
      why <- c(why, sprintf("with %d plots failing only unchecked %s: %d plots, %d stems",
                            nrow(hx) - nrow(ad), if (is.null(inconclusive)) "conditions"
                            else "checks", n_hold, s_hold))
    fl <- function(f) if (is.null(f)) NA_real_ else f$floor_cm[match(g, f$group)]
    out <- data.frame(group = g, decision = decision, reasons = paste(why, collapse = "; "),
               signal = sig, signal_admitted = r1,
               plots_admitted = n_plots,
               plots_with_headline = n_head,
               ref_headline = n_stems, rule_signal = r1, rule_population = r2,
               rule_licence = r3, floor_cm = fl(floors),
               plots_unchecked_only = nrow(hx) - nrow(ad), plots_if_unchecked = n_hold,
               ref_headline_if_unchecked = s_hold, floor_cm_if_unchecked = fl(floors_hold),
               redistribute_plots = sum(mode %in% "redistribute"),
               rebuild_only_plots = sum(mode %in% "rebuild_only"),
               stringsAsFactors = FALSE)
    # Reported only where the decision got an inconclusive record (protocol 2).
    if (!is.null(inconclusive))
      out <- cbind(out[, 1:5], signal_inconclusive = r1_open, out[, -(1:5)])
    out
  }))
}

## ---- reference tables (neon_ground_truth.R schema) ----------------------------

ofo_utm_zone <- function(epsg) {
  epsg <- as.integer(epsg)
  if (anyNA(epsg) || any(!(epsg %/% 100L) %in% c(326L, 327L)))
    stop("OFO project frames must be WGS 84 UTM (EPSG:326zz or 327zz)")
  paste0(epsg %% 100L, ifelse(epsg %/% 100L == 326L, "N", "S"))
}

# plantStatus strings: NEON's live test is grepl("Live", plantStatus), so a
# marginal tree (counted live) reads "Live, marginal" and a dead one does not.
ofo_plant_status <- function(live_dead) {
  v <- toupper(trimws(as.character(live_dead)))
  c(L = "Live", D = "Standing dead", M = "Live, marginal")[v]
}

# Reference directory of each plot: `site` (plot_id -> name, ofo_site_plan())
# or, when NULL, the project name.
ofo_site_of <- function(plot_id, project, site = NULL) {
  if (is.null(site)) return(as.character(project))
  v <- unname(site[as.character(plot_id)])
  if (anyNA(v)) stop("No reference directory for plot(s): ",
                     paste(unique(plot_id[is.na(v)]), collapse = ", "))
  v
}

# Ground truth for the plots of `cells` (admitted cells of admitted plots of the
# groups being written), in the column order of neon_ground_truth.R plus
# OFO_GT_EXTRA. `stems` are ofo_locate() stems (all trees of those plots, so
# the crown-class fallback sees the whole plot); `plots` plots.csv,
# `flights` flights.csv; `floors` ofo_group_floors() of the admitted plots;
# `site` the reference directory by plot_id (NULL: the project).
# Rows: trees inside an admitted cell and the polygon; in groups C and D only
# trees at or above the group floor. Groups B and D match on position alone
# (protocol "Missing heights": height bands, height error and crown class are
# not reported for them): `height`, `crown_class` and `canopyPosition` are NA
# on all their rows and `crown_source` is "none". The recorded height is kept
# in `height_recorded` (equal to `height` in A and C) and the catalogue's
# crown_position in `crown_position_recorded` (every group).
ofo_ground_truth <- function(stems, plots, flights, cells, floors, site = NULL) {
  pids <- unique(cells$plot_id)
  s <- stems[stems$plot_id %in% pids, , drop = FALSE]
  if (!nrow(s)) stop("No stems for the plots of the given cells")
  pr <- plots[match(s$plot_id, plots$plot_id), , drop = FALSE]
  grp <- as.character(pr$group)
  nohgt <- grp %in% OFO_NO_HEIGHT_GROUPS
  cc <- ofo_crown_class(s$crown_position, s$height, s$plot_id, fallback = !nohgt)
  cc$crown_class[nohgt] <- NA_character_
  cc$canopyPosition[nohgt] <- NA_character_
  cc$crown_source[nohgt] <- "none"
  fl <- ofo_plot_floor(grp, floors)
  keep <- s$cell_id %in% cells$cell_id & s$in_polygon %in% TRUE & s$inside %in% TRUE &
    is.finite(s$E) & is.finite(s$N)
  cd <- grp %in% c("C", "D")
  keep <- keep & (!cd | (!is.na(s$dbh) & !is.na(fl) & s$dbh >= fl - OFO_EPS))
  if (any(cd & is.na(fl))) stop("Groups C/D need a group floor from admitted plots")
  s <- s[keep, , drop = FALSE]; cc <- cc[keep, , drop = FALSE]
  pr <- pr[keep, , drop = FALSE]; grp <- grp[keep]; nohgt <- nohgt[keep]
  h <- suppressWarnings(as.numeric(s$height))
  fy <- as.integer(flights$flight_year[match(s$plot_id, flights$plot_id)])
  sy <- as.integer(pr$survey_year)
  if (anyNA(fy) || anyNA(sy)) stop("Reference plots need survey and flight years")
  w1 <- suppressWarnings(as.numeric(s$crown_width_1))
  w2 <- suppressWarnings(as.numeric(s$crown_width_2))
  both <- is.finite(w1) & is.finite(w2)
  # Integer metres, so write.csv does not print 5e+05.
  tile_e <- as.integer(floor(s$E / 1000) * 1000)
  tile_n <- as.integer(floor(s$N / 1000) * 1000)
  out <- data.frame(
    individualID = s$individual_id, plotID = s$cell_id,
    tile = sprintf("%d_%d", tile_e, tile_n),
    tile_e = tile_e, tile_n = tile_n, E = s$E, N = s$N, pos_unc = s$pos_unc,
    taxonID = s$species_code, scientificName = NA_character_,
    height = ifelse(nohgt, NA_real_, h),
    stemDiameter = suppressWarnings(as.numeric(s$dbh)),
    maxCrownDiameter = ifelse(both, pmax(w1, w2), NA_real_),
    ninetyCrownDiameter = ifelse(both, pmin(w1, w2), NA_real_),
    plantStatus = unname(ofo_plant_status(s$live_dead)),
    canopyPosition = cc$canopyPosition, crown_class = cc$crown_class,
    live = s$live %in% TRUE, is_tree = s$is_tree %in% TRUE, meas_year = sy,
    dist21 = abs(sy - fy), dist_aop = abs(sy - fy), acquisition_year = fy,
    utmZone = ofo_utm_zone(pr$epsg), epsg = as.integer(pr$epsg),
    ofo_plot_id = s$plot_id, project = pr$project_name, group = grp,
    E_raw = s$x, N_raw = s$y, shift_dx = s$shift_dx, shift_dy = s$shift_dy,
    crown_source = cc$crown_source, license_short = pr$license_short,
    withhold_from_training = ofo_lgl(pr$withhold_from_training),
    height_recorded = h, site = ofo_site_of(s$plot_id, pr$project_name, site),
    crown_position_recorded = suppressWarnings(as.integer(s$crown_position)),
    stringsAsFactors = FALSE)
  if (anyNA(out$pos_unc)) stop("Reference stems lack a registered position")
  out <- out[order(out$plotID, as.integer(s$tree_n)), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# plot_centroids.csv for the cells: one "tower" plot per cell (the arms derive
# the +/-20 m core from plotType), in neon_ground_truth.R's pp1 column order
# plus OFO extras. `cells` carry n_ref / headline (ofo_count_cells); `site`
# as for ofo_ground_truth().
ofo_plot_centroids <- function(cells, plots, flights, site = NULL) {
  pr <- plots[match(cells$plot_id, plots$plot_id), , drop = FALSE]
  out <- data.frame(plotID = cells$cell_id, plotType = "tower", easting = cells$cx,
                    northing = cells$cy, utmZone = ofo_utm_zone(cells$epsg),
                    plot_meas_year = as.integer(pr$survey_year),
                    epsg = as.integer(cells$epsg), datum = "WGS84",
                    acquisition_year = as.integer(flights$flight_year[
                      match(cells$plot_id, flights$plot_id)]),
                    ofo_plot_id = cells$plot_id, project = pr$project_name,
                    group = pr$group, cell = cells$cell, inside_share = cells$inside_share,
                    n_ref = cells$n_ref, headline = cells$headline,
                    site = ofo_site_of(cells$plot_id, pr$project_name, site),
                    stringsAsFactors = FALSE)
  out <- out[order(out$plotID), , drop = FALSE]
  rownames(out) <- NULL
  out
}

## ---- reference directories ------------------------------------------------------

# Reference directories (the arms' SITE=) of the admitted plots of the go
# groups. One per project; a project with admitted plots in more than one go
# group takes <PROJECT>_<GROUP> for each of its groups, so no directory mixes
# groups (they are never pooled). A directory whose plots were flown in more
# than one year is split into <NAME>_<YEAR>, since neon_reference_epoch()
# takes one acquisition year per reference. Names follow from all go groups,
# not from the groups being written, so a partial run writes the same
# directories as a full one. `adm` holds plot_id, project_name, group,
# admitted; `flights` plot_id, flight_year. One row per plot, ordered by site.
ofo_site_plan <- function(adm, flights, go_groups) {
  take <- ofo_lgl(adm$admitted) %in% TRUE & adm$group %in% intersect(go_groups, OFO_GROUPS)
  x <- data.frame(plot_id = as.character(adm$plot_id[take]),
                  project_name = as.character(adm$project_name[take]),
                  group = as.character(adm$group[take]), stringsAsFactors = FALSE)
  x$acquisition_year <- suppressWarnings(as.integer(
    flights$flight_year[match(x$plot_id, flights$plot_id)]))
  if (anyNA(x$acquisition_year))
    stop("Admitted plots without a flight year: ",
         paste(x$plot_id[is.na(x$acquisition_year)], collapse = ", "))
  unsafe <- is.na(x$project_name) | !grepl(OFO_SITE_PATTERN, x$project_name)
  if (any(unsafe))
    stop("Project names unsafe as directory names: ",
         paste(unique(x$project_name[unsafe]), collapse = ", "))
  n_groups <- tapply(x$group, x$project_name, function(g) length(unique(g)))
  x$split_group <- as.vector(n_groups[x$project_name]) > 1
  base <- ifelse(x$split_group, paste0(x$project_name, "_", x$group), x$project_name)
  n_years <- tapply(x$acquisition_year, base, function(y) length(unique(y)))
  x$split_year <- as.vector(n_years[base]) > 1
  x$site <- ifelse(x$split_year, paste0(base, "_", x$acquisition_year), base)
  # One (project, group, year) per name, also on a case-blind file system.
  key <- unique(x[, c("site", "project_name", "group", "acquisition_year")])
  clash <- key$site[duplicated(tolower(key$site)) | duplicated(tolower(key$site),
                                                                fromLast = TRUE)]
  if (length(clash))
    stop("Reference directory names collide: ", paste(unique(clash), collapse = ", "))
  x <- x[order(x$site, x$plot_id), , drop = FALSE]
  rownames(x) <- NULL
  x
}

# One row per reference directory of a plan, with its plots and, from the
# plot_centroids rows `pc` (column `site`), its cells.
ofo_site_table <- function(plan, pc) {
  cols <- c("site", "project_name", "group", "acquisition_year", "split_group", "split_year")
  s <- unique(plan[, cols, drop = FALSE])
  rownames(s) <- NULL
  lv <- s$site
  s$n_plots <- as.integer(table(factor(plan$site, levels = lv)))
  s$plot_ids <- vapply(lv, function(z) paste(plan$plot_id[plan$site == z], collapse = ";"),
                       character(1), USE.NAMES = FALSE)
  s$n_cells <- as.integer(table(factor(pc$site, levels = lv)))
  s$n_headline_cells <- as.integer(table(factor(pc$site[pc$headline %in% TRUE], levels = lv)))
  s
}

# Checks that one directory's tables are what its name says and what the arms'
# readers assume: rows present, every row of this site, one project, group,
# acquisition year and frame, cells unique, every stem in a listed cell, no
# heights in groups B and D. Stops naming the site; returns the identity.
ofo_check_site_tables <- function(gt, pc, site) {
  fail <- function(...) stop("reference ", site, ": ", ..., call. = FALSE)
  if (!grepl(OFO_SITE_PATTERN, site)) fail("unsafe directory name")
  if (!nrow(gt) || !nrow(pc)) fail("no rows")
  if (!all(gt$site %in% site) || !all(pc$site %in% site)) fail("rows of another site")
  one <- function(v, what) {
    u <- unique(v)
    if (length(u) != 1L || anyNA(u)) fail("not one ", what, ": ", paste(u, collapse = ", "))
    u
  }
  out <- list(site = site, project = one(c(gt$project, pc$project), "project"),
              group = one(c(gt$group, pc$group), "group"),
              acquisition_year = as.integer(one(c(gt$acquisition_year, pc$acquisition_year),
                                                "acquisition year")),
              epsg = as.integer(one(c(gt$epsg, pc$epsg), "frame")))
  if (anyDuplicated(pc$plotID)) fail("duplicate cells in plot_centroids")
  if (anyDuplicated(gt$individualID)) fail("duplicate stems")
  if (any(!gt$plotID %in% pc$plotID)) fail("stems outside the listed cells")
  if (out$group %in% OFO_NO_HEIGHT_GROUPS && any(!is.na(gt$height)))
    fail("group ", out$group, " rows carry heights")
  if (out$group %in% OFO_NO_HEIGHT_GROUPS &&
      any(!is.na(gt$crown_class) | !is.na(gt$canopyPosition)))
    fail("group ", out$group, " rows carry a crown class")
  out
}

## ---- output location --------------------------------------------------------------

# Whether `path` may receive this study's outputs: anywhere under `ofo`, or
# outside `job` altogether (a scratch directory), never elsewhere in the job
# directory (the sealed NEON root lives there). The path need not exist: its
# deepest existing ancestor is resolved (symlinks included) and the rest
# appended; a `..` component is refused, since it is resolved only on creation.
ofo_output_allowed <- function(path, job, ofo) {
  if (!ofo_path_ok(path)) return(FALSE)
  p <- ofo_path_resolve(path)
  # Never in the NEON root, wherever <job>/neon resolves: it may be a symlink
  # to another disk, and then lies outside the resolved job directory.
  if (ofo_path_within(p, ofo_path_resolve(file.path(job, "neon")))) return(FALSE)
  ofo_path_within(p, ofo_path_resolve(ofo)) || !ofo_path_within(p, ofo_path_resolve(job))
}

# A path this study may name for writing: one non-empty string without a `..`
# component (resolved only on creation, so never trusted).
ofo_path_ok <- function(path) {
  length(path) == 1L && !is.na(path) && nzchar(path) &&
    !any(strsplit(path, "/", fixed = TRUE)[[1]] == "..")
}

# Absolute form of a path that need not exist: relative paths against the
# working directory, the deepest existing ancestor resolved (symlinks
# included), the rest appended.
ofo_path_resolve <- function(p) {
  if (!startsWith(p, "/")) p <- file.path(getwd(), p)
  tail <- character(); hops <- 0L
  while (!file.exists(p) && dirname(p) != p) {
    # A dangling symlink does not exist for file.exists(), yet a write would
    # follow it: resolve its target instead of keeping its name.
    l <- Sys.readlink(p)
    if (!is.na(l) && nzchar(l)) {
      if ((hops <- hops + 1L) > 40L) stop("Too many symbolic links: ", p, call. = FALSE)
      p <- if (startsWith(l, "/")) l else file.path(dirname(p), l)
      next
    }
    tail <- c(basename(p), tail); p <- dirname(p)
  }
  sub("/+$", "", do.call(file.path, as.list(c(normalizePath(p), tail))))
}

ofo_path_within <- function(p, root) p == root || startsWith(p, paste0(root, "/"))

# Whether `path` lies strictly under `root` once resolved (prepare_ofo_reference.R
# writes nowhere else): a symlink inside `root` pointing elsewhere is refused.
ofo_path_under <- function(path, root) {
  if (!ofo_path_ok(path)) return(FALSE)
  p <- ofo_path_resolve(path); r <- ofo_path_resolve(root)
  p != r && ofo_path_within(p, r)
}

## ---- input validation -------------------------------------------------------------

# Columns each driver reads from the other stages' tables (brief contracts).
OFO_INPUT_COLUMNS <- list(
  plots.csv = c("plot_id", "project_name", "survey_year", "live_floor_cm",
                "license_short", "withhold_from_training", "epsg", "polygon_wkt",
                "polygon_area_m2", "screen", "group"),
  trees.csv = c("plot_id", "tree_n", "individual_id", "contributor_tree_id", "x", "y",
                "dbh", "height",
                "species_code", "live_dead", "crown_position", "crown_width_1",
                "crown_width_2", "live", "is_tree", "inside", "ref"),
  flights.csv = c("plot_id", "project_name", "flight_year", "flight_admitted",
                  "flight_reason"),
  geometry_audit.csv = c("plot_id", "geometry_consistent"),
  licences.csv = c("plot_id", "license_short", "redistribute_reference"),
  # The registration stage's contract; `group`, `method` and other columns are
  # optional (group is cross-checked against plots.csv when present).
  registration.csv = c("plot_id", "signal_used", "dx", "dy", "residual_m",
                       "registered", "reason", "pos_unc"),
  conditions.csv = c("plot_id", "disturbance_status", "interval_covered", "same_year",
                     "disturbance_admitted", "snow_status", "leafoff_status",
                     "conditions_admitted", "conditions_reason"))

# Reads one contract CSV: plot_id as a string, empty fields as NA. Stops with a
# message naming the file or the missing columns.
ofo_read_input <- function(dir, name, required = OFO_INPUT_COLUMNS[[name]]) {
  path <- file.path(dir, name)
  if (!file.exists(path)) stop("Missing input ", path, call. = FALSE)
  cc <- if ("plot_id" %in% required) list(character = "plot_id")
  x <- data.table::fread(path, colClasses = cc, na.strings = c("", "NA"), showProgress = FALSE)
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  miss <- setdiff(required, names(x))
  if (length(miss)) stop(name, " lacks column(s): ", paste(miss, collapse = ", "), call. = FALSE)
  if ("plot_id" %in% required && anyNA(x$plot_id))
    stop(name, " has rows without plot_id", call. = FALSE)
  x
}

# Cross-table consistency the decision relies on; returns the messages.
ofo_check_inputs <- function(plots, trees, flights, geometry, licences, registration) {
  msg <- character()
  if (anyDuplicated(plots$plot_id)) msg <- c(msg, "plots.csv: duplicate plot_id")
  for (nm in c("flights", "geometry", "licences", "registration")) {
    t <- get(nm)
    if (anyDuplicated(t$plot_id)) msg <- c(msg, sprintf("%s: duplicate plot_id", nm))
    if (any(!t$plot_id %in% plots$plot_id)) msg <- c(msg, sprintf("%s: unknown plot_id", nm))
  }
  if (any(!trees$plot_id %in% plots$plot_id)) msg <- c(msg, "trees.csv: unknown plot_id")
  if (anyDuplicated(trees$individual_id)) msg <- c(msg, "trees.csv: duplicate individual_id")
  if ("group" %in% names(registration)) {
    rg <- plots$group[match(registration$plot_id, plots$plot_id)]
    if (any(!ofo_blank(registration$group) & registration$group != rg, na.rm = TRUE))
      msg <- c(msg, "registration.csv: group differs from plots.csv")
  }
  # A registered plot needs its shift; ofo_locate() would stop on it later.
  reg <- ofo_lgl(registration$registered) %in% TRUE
  noshift <- reg & !(is.finite(suppressWarnings(as.numeric(registration$dx))) &
                     is.finite(suppressWarnings(as.numeric(registration$dy))))
  if (any(noshift))
    msg <- c(msg, sprintf("registration.csv: registered without a finite dx/dy: %s",
                          paste(registration$plot_id[noshift], collapse = ", ")))
  num <- function(v) is.finite(suppressWarnings(as.numeric(v)))
  nounc <- reg & !num(registration$pos_unc) & !num(registration$residual_m)
  if (any(nounc))
    msg <- c(msg, sprintf("registration.csv: registered without pos_unc or residual_m: %s",
                          paste(registration$plot_id[nounc], collapse = ", ")))
  lm <- match(licences$plot_id, plots$plot_id)
  mode <- ofo_archive_mode(licences$license_short)
  red <- ofo_lgl(licences$redistribute_reference)
  if (any(!is.na(mode) & !is.na(red) & (mode == "redistribute") != red))
    msg <- c(msg, "licences.csv: redistribute_reference disagrees with the protocol's licence list")
  if (any(!is.na(lm) & trimws(licences$license_short) != trimws(plots$license_short[lm]),
          na.rm = TRUE))
    msg <- c(msg, "licences.csv: license_short differs from plots.csv")
  msg
}
