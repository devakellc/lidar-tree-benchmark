# Event-specific reference preparation. No detector imports or API calls.
neon_support_require <- function(x, columns, label) {
  if (!is.data.frame(x) || !all(columns %in% names(x)))
    stop(label, " lacks required columns: ", paste(setdiff(columns, names(x)), collapse = ", "))
}

neon_support_key <- function(plot, event) paste(plot, event, sep = "::")
neon_support_flagged <- function(x) !is.na(x) & !trimws(as.character(x)) %in% c("", "0")

neon_subplot_corners <- function(id) {
  parts <- strsplit(id, "_", fixed = TRUE)[[1]]
  if (length(parts) != 2L || !all(grepl("^[0-9]+$", parts)))
    stop("Unsupported or nested subplot encoding: ", id)
  anchor <- as.integer(parts[1]); area <- as.integer(parts[2])
  step <- if (area == 100L) 1L else if (area == 400L) 2L else
    stop("Unsupported tree subplot area: ", id)
  grid <- outer(c(21L, 30L, 39L, 48L, 57L), 0:4, `+`)
  at <- which(grid == anchor, arr.ind = TRUE)
  if (nrow(at) != 1L || any(at[1, ] + step > 5L)) stop("Invalid subplot anchor: ", id)
  as.character(anchor + c(0L, step, 10L * step, 9L * step))
}

neon_event_subplots <- function(event) {
  neon_support_require(event, c("plotID", "eventID", "namedLocation", "subplotsSampled",
    "totalSampledAreaTrees", "samplingImpractical", "dataCollected", "samplingProtocolVersion",
    "dataQF"), "Census event")
  if (nrow(event) != 1L || anyNA(event[, c("plotID", "eventID", "namedLocation",
      "subplotsSampled", "samplingProtocolVersion")])) stop("Missing or ambiguous census event")
  if (!tolower(event$samplingImpractical) %in% "ok" || !event$dataCollected %in% "allGrowthForms" ||
      neon_support_flagged(event$dataQF)) stop("Incomplete or quality-flagged census event")
  ids <- trimws(strsplit(event$subplotsSampled, "|", fixed = TRUE)[[1]])
  if (!length(ids) || anyDuplicated(ids) || any(!nzchar(ids))) stop("Missing or duplicate subplots")
  corners <- lapply(ids, neon_subplot_corners)
  areas <- as.numeric(vapply(strsplit(ids, "_", fixed = TRUE), `[`, character(1), 2))
  if (!is.finite(event$totalSampledAreaTrees) ||
      abs(sum(areas) - event$totalSampledAreaTrees) > 1e-6) stop("Census sampled-area mismatch")
  names(corners) <- ids
  corners
}

neon_event_geometry <- function(event, locations, epsg) {
  corners <- neon_event_subplots(event)
  neon_support_require(locations, c("ptloc", "easting", "northing", "epsg", "unc"), "Named points")
  if (anyDuplicated(locations$ptloc)) stop("Ambiguous named-point coordinates")
  used <- list()
  polygons <- lapply(names(corners), function(id) {
    names <- paste(event$namedLocation, corners[[id]], sep = ".")
    p <- locations[match(names, locations$ptloc), ]
    if (anyNA(p$ptloc) || any(!is.finite(p$easting) | !is.finite(p$northing)))
      stop("Missing subplot corner: ", id)
    if (anyNA(p$epsg) || any(p$epsg != epsg)) stop("Subplot corner CRS mismatch")
    if (any(!is.finite(p$unc) | p$unc < 0)) stop("Missing corner uncertainty")
    used[[id]] <<- p
    xy <- as.matrix(p[, c("easting", "northing")])
    sf::st_polygon(list(rbind(xy, xy[1, ])))
  })
  g <- sf::st_sfc(polygons, crs = epsg)
  neon_assert_crs(g)
  if (any(!sf::st_is_valid(g)) || any(as.numeric(sf::st_area(g)) <= 0))
    stop("Invalid subplot geometry")
  union <- sf::st_union(g)
  if (abs(sum(as.numeric(sf::st_area(g))) - as.numeric(sf::st_area(union))) > 1e-5)
    stop("Overlapping sampled subplots")
  list(footprint = union, subplots = sf::st_sf(subplotID = names(corners), geometry = g),
       anchors = unique(do.call(rbind, used)), nominal_area = event$totalSampledAreaTrees)
}

neon_latest_mapping <- function(mt) {
  neon_support_require(mt, c("plotID", "individualID", "date", "namedLocation", "pointID",
    "stemDistance", "stemAzimuth", "dataQF"), "Mapping records")
  mt <- unique(as.data.frame(mt))
  key <- neon_support_key(mt$plotID, mt$individualID)
  selected <- lapply(split(seq_len(nrow(mt)), key), function(i) {
    dates <- as.Date(mt$date[i])
    if (anyNA(dates)) return(NULL)
    newest <- i[dates == max(dates)]
    if (length(newest) != 1L) return(NULL)
    mt[newest, , drop = FALSE]
  })
  out <- do.call(rbind, selected)
  if (is.null(out)) mt[FALSE, , drop = FALSE] else out
}

neon_event_references <- function(ai, pp, mt, locations, year, epsg) {
  neon_support_require(ai, c("plotID", "individualID", "date", "eventID", "subplotID",
    "growthForm", "plantStatus", "stemDiameter", "height", "canopyPosition", "dataQF"), "Measurements")
  neon_support_require(pp, c("plotID", "eventID", "date", "subplotsSampled"), "Census records")
  neon_support_require(locations, c("ptloc", "easting", "northing", "epsg", "unc"), "Named points")
  if (anyDuplicated(locations$ptloc)) stop("Ambiguous named-point coordinates")
  year <- neon_year(year)
  a <- as.data.frame(ai[!is.na(ai$date) & substr(as.character(ai$date), 1, 4) == year, ])
  a$reference_row <- seq_len(nrow(a))
  a$measurement_date <- as.character(a$date)
  a$exclusion <- rep("", nrow(a))
  exclude <- function(condition, reason) {
    i <- which(condition %in% TRUE & a$exclusion == "")
    a$exclusion[i] <<- reason
  }
  key <- neon_support_key(a$plotID, a$eventID)
  pp <- unique(as.data.frame(pp))
  pk <- neon_support_key(pp$plotID, pp$eventID)
  dup <- duplicated(pk) | duplicated(pk, fromLast = TRUE)
  idx <- match(key, pk)
  a$census_date <- as.character(pp$date[idx])
  for (field in intersect(c("samplingProtocolVersion", "subplotsSampled", "totalSampledAreaTrees",
      "samplingImpractical", "dataCollected", "eventType", "dataQF"), names(pp)))
    a[[paste0("census_", field)]] <- pp[[field]][idx]
  exclude(is.na(idx) | key %in% pk[dup] | is.na(a$eventID), "missing_or_ambiguous_event")
  exclude(is.na(a$census_date) | substr(a$census_date, 1, 4) != year, "census_epoch_mismatch")
  individual_key <- paste(key, a$individualID, sep = "::")
  exclude(is.na(a$individualID) | duplicated(individual_key) |
            duplicated(individual_key, fromLast = TRUE), "missing_or_duplicate_individual")
  event_ok <- vapply(seq_len(nrow(pp)), function(i)
    !inherits(try(neon_event_subplots(pp[i, , drop = FALSE]), silent = TRUE), "try-error"), logical(1))
  exclude(!event_ok[idx], "unsupported_census_scope")
  a$target_population <- a$growthForm %in% c("single bole tree", "multi-bole tree") &
    is.finite(a$stemDiameter) & a$stemDiameter >= 10 &
    !is.na(a$plantStatus) & grepl("^Live($|[ ,;])", a$plantStatus)
  exclude(!a$target_population, "outside_target_population")
  known_subplot <- vapply(seq_len(nrow(a)), function(i) {
    if (is.na(idx[i]) || is.na(a$subplotID[i]) || is.na(pp$subplotsSampled[idx[i]])) return(FALSE)
    a$subplotID[i] %in% trimws(strsplit(pp$subplotsSampled[idx[i]], "|", fixed = TRUE)[[1]])
  }, logical(1))
  exclude(!known_subplot, "unresolved_measurement_subplot")
  exclude(neon_support_flagged(a$dataQF), "measurement_quality_flag")
  m <- neon_latest_mapping(mt)
  mi <- match(neon_support_key(a$plotID, a$individualID), neon_support_key(m$plotID, m$individualID))
  a$mapping_date <- as.character(m$date[mi])
  a$mapping_dataQF <- m$dataQF[mi]
  a$mapping_point <- paste(m$namedLocation[mi], m$pointID[mi], sep = ".")
  loc <- locations[match(a$mapping_point, locations$ptloc), ]
  az <- m$stemAzimuth[mi] * pi / 180
  distance <- m$stemDistance[mi]
  a$E <- loc$easting + distance * sin(az)
  a$N <- loc$northing + distance * cos(az)
  a$pos_unc <- loc$unc + 0.6
  a$epsg <- loc$epsg
  exclude(is.na(mi), "missing_or_ambiguous_mapping")
  exclude(neon_support_flagged(a$mapping_dataQF), "mapping_quality_flag")
  exclude(!is.finite(distance) | distance < 0 | !is.finite(az) |
            !is.finite(a$E) | !is.finite(a$N), "missing_mapping_coordinates")
  exclude(is.na(a$epsg) | a$epsg != epsg, "mapping_crs_mismatch")
  exclude(!is.finite(a$pos_unc) | a$pos_unc < 0.6, "missing_mapping_uncertainty")
  exclude(!is.finite(a$height) | a$height <= 0, "invalid_height")
  cc <- c("Open grown" = "dominant", "Full sun" = "dominant", "Partially shaded" = "codominant",
          "Mostly shaded" = "intermediate", "Full shade" = "suppressed")
  a$crown_class <- unname(cc[a$canopyPosition])
  a$reference_eligible <- a$exclusion == ""
  a
}

neon_support_inside <- function(x, y, geometry) {
  ok <- is.finite(x) & is.finite(y)
  inside <- rep(FALSE, length(x))
  if (any(ok)) {
    p <- sf::st_as_sf(data.frame(x = x[ok], y = y[ok]), coords = c("x", "y"), crs = sf::st_crs(geometry))
    inside[ok] <- lengths(sf::st_covered_by(p, geometry)) > 0L
  }
  inside
}

neon_build_support <- function(event, references, locations, epsg) {
  geometry <- neon_event_geometry(event, locations, epsg)
  refs <- references[references$plotID %in% event$plotID & references$eventID %in% event$eventID, ]
  valid <- refs$reference_eligible
  margin <- max(c(geometry$anchors$unc + 0.6,
                  refs$pos_unc[refs$target_population & is.finite(refs$pos_unc)]))
  core <- sf::st_buffer(geometry$footprint, -margin)
  if (any(sf::st_is_empty(core))) stop("Uncertainty margin leaves no scoring interior")
  refs$inside_sampled <- neon_support_inside(refs$E, refs$N, geometry$footprint)
  refs$inside_interior <- neon_support_inside(refs$E, refs$N, core)
  refs$boundary_uncertain <- valid & !refs$inside_interior &
    neon_support_inside(refs$E, refs$N, sf::st_buffer(geometry$footprint, margin))
  refs$subplot_conflict <- FALSE
  for (i in which(valid)) {
    subplot <- sf::st_geometry(geometry$subplots[geometry$subplots$subplotID == refs$subplotID[i], ])
    refs$subplot_conflict[i] <- !neon_support_inside(refs$E[i], refs$N[i],
                                                    sf::st_buffer(subplot, refs$pos_unc[i]))
  }
  refs$reference_selected <- valid & refs$inside_interior & !refs$subplot_conflict
  blockers <- c("datum_review_pending", "flight_provenance_pending")
  if (any(refs$target_population & !valid)) blockers <- c(blockers, "incomplete_target_references")
  if (any(refs$subplot_conflict)) blockers <- c(blockers, "measurement_subplot_conflict")
  if (any(valid & !refs$inside_sampled & !refs$boundary_uncertain))
    blockers <- c(blockers, "references_outside_sampled_footprint")
  if (!any(refs$reference_selected)) blockers <- c(blockers, "empty_reference_interior")
  list(schema = 1L, plot = event$plotID, event = event$eventID, epsg = epsg,
    population = "live_mapped_boles_dbh_ge_10cm", policy = "measured_subplots_uncertainty_interior_v1",
    event_metadata = event, references = refs, footprint = geometry$footprint,
    subplots = geometry$subplots, core = core, anchors = geometry$anchors,
    boundary_margin_m = margin, nominal_area_m2 = geometry$nominal_area,
    measured_area_m2 = as.numeric(sf::st_area(geometry$footprint)),
    interior_area_m2 = as.numeric(sf::st_area(core)), blockers = blockers,
    evaluation_ready = FALSE)
}

neon_support_identity <- function(support) {
  digest::digest(support, algo = "sha256", serialize = TRUE)
}

neon_support_software <- function() {
  list(R = R.version.string, sf = as.character(packageVersion("sf")),
       digest = as.character(packageVersion("digest")))
}

neon_check_support_rows <- function(df) {
  if (!any(c("support_id", "support_policy", "reference_population") %in% names(df)))
    return(invisible(TRUE))
  required <- c("site", "plot", "rung", "support_id", "support_policy", "reference_population")
  neon_support_require(df, required, "Support-tagged results")
  if (anyNA(df[required]) || any(!nzchar(as.matrix(df[required]))))
    stop("Missing support identity; do not mix rectangular and support-aware rows")
  if (length(unique(df$support_policy)) != 1L || length(unique(df$reference_population)) != 1L)
    stop("Mixed reference-support policies or populations")
  key <- paste(df$site, df$plot, sep = "::")
  if (any(vapply(split(df$support_id, key), function(x) length(unique(x)) != 1L, logical(1))))
    stop("Different reference support within the same plot")
  invisible(TRUE)
}

score_neon_support <- function(support, det, det_epsg = NULL, tol_xy = 4, ...) {
  if (!isTRUE(support$evaluation_ready) || length(support$blockers))
    stop("Reference support is diagnostic only; admission checks remain unresolved")
  refs <- support$references[support$references$reference_selected, , drop = FALSE]
  if (!nrow(refs)) stop("No supported references")
  neon_assert_crs(support$core, support$epsg)
  if (length(det_epsg) != 1L || is.na(det_epsg) || det_epsg != support$epsg)
    stop("Missing or mismatched detection CRS")
  neon_support_require(det, c("x", "y", "z"), "Detections")
  if (any(!is.finite(as.matrix(det[, c("x", "y", "z")])))) stop("Invalid detection coordinates")
  if (!length(tol_xy) %in% c(1L, nrow(refs)) || any(!is.finite(tol_xy) | tol_xy <= 0))
    stop("Invalid matching tolerance")
  if (anyNA(refs$epsg) || any(refs$epsg != support$epsg)) stop("Reference support CRS mismatch")
  result <- score_plot(refs, det, tol_xy = tol_xy, core_cx = NA_real_, core_cy = NA_real_,
                       core_geometry = support$core, ...)
  result$support_id <- neon_support_identity(support)
  result$support_policy <- support$policy
  result$reference_population <- support$population
  result$n_reference_excluded <- nrow(support$references) - nrow(refs)
  result$support_area_m2 <- support$interior_area_m2
  result
}

neon_historical_support <- function(gt, pc, dat, site) {
  neon_support_require(gt, c("plotID", "individualID", "meas_year", "E", "N", "live", "is_tree"),
                        "Historical references")
  plot <- pc[match(gt$plotID, pc$plotID), ]
  half <- ifelse(plot$plotType == "tower", 20, 10)
  keep <- gt$live %in% TRUE & gt$is_tree %in% TRUE & is.finite(gt$E) & is.finite(gt$N) &
    abs(gt$E - plot$easting) <= half & abs(gt$N - plot$northing) <= half
  g <- gt[which(keep), ]
  a <- as.data.frame(dat$vst_apparentindividual)
  key <- function(p, i, y) paste(p, i, y, sep = "::")
  ak <- key(a$plotID, a$individualID, substr(a$date, 1, 4))
  gk <- key(g$plotID, g$individualID, g$meas_year)
  idx <- match(gk, ak)
  ambiguous <- gk %in% ak[duplicated(ak) | duplicated(ak, fromLast = TRUE)]
  g$event_id <- as.character(a$eventID[idx])
  g$event_id[is.na(idx) | ambiguous | is.na(g$event_id)] <- "unresolved"
  pp <- unique(as.data.frame(dat$vst_perplotperyear))
  groups <- split(seq_len(nrow(g)), paste(g$plotID, g$meas_year, g$event_id, sep = "::"))
  if (!length(groups)) stop("No historical core references")
  do.call(rbind, lapply(groups, function(i) {
    p <- g$plotID[i[1]]; ev <- g$event_id[i[1]]
    event <- pp[pp$plotID %in% p & pp$eventID %in% ev, ]
    nominal <- if (pc$plotType[match(p, pc$plotID)] == "tower") 1600 else 400
    status <- if (nrow(event) != 1L || ev == "unresolved") "unresolved_census_event" else
      if (event$dataCollected %in% "dendrometerOnly") "dendrometer_only" else
      if (is.na(event$totalSampledAreaTrees)) "missing_sampled_area" else
      if (event$totalSampledAreaTrees < nominal) "partial_nominal_area" else "footprint_audit_required"
    data.frame(site = site, plot = p, meas_year = g$meas_year[i[1]], event_id = ev,
      n_historical_core = length(i), nominal_area_m2 = nominal,
      sampled_area_m2 = if (nrow(event) == 1L) event$totalSampledAreaTrees else NA_real_,
      data_collected = if (nrow(event) == 1L) event$dataCollected else NA_character_,
      subplots_sampled = if (nrow(event) == 1L) event$subplotsSampled else NA_character_,
      status = status, detector_rescored = FALSE)
  }))
}
