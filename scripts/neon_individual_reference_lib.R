# A separate apparent-individual diagnostic; source bole records stay immutable.
neon_individual_policy <- function() {
  list(schema = 1L, id = "individual_reference_v1",
    population = "apparent_individuals_with_live_tree_bole_dbh_ge_10cm",
    identity = "same_plot_event_permanent_bole_family",
    location = "living_unsuffixed_primary_latest_mapping",
    height = "unique_live_height_primary_or_intact_relative_of_broken_primary",
    geometry = "unchanged_predecessor_interior", evaluation_ready = FALSE)
}

neon_individual_references <- function(b, mt, policy = neon_individual_policy()) {
  if (!identical(policy, neon_individual_policy())) stop("Unsupported individual policy")
  if (isTRUE(b$evaluation_ready) || !length(b$blockers))
    stop("Individual preparation requires a diagnostic predecessor")
  neon_event_subplots(b$event_metadata)
  if (length(b$event_metadata$date) != 1L || is.na(as.Date(b$event_metadata$date)))
    stop("Missing census date")
  for (g in c("footprint", "core", "subplots")) neon_assert_crs(b[[g]], b$epsg)
  a <- as.data.frame(b$references)
  required <- c("uid", "plotID", "eventID", "individualID", "date", "growthForm",
    "plantStatus", "stemDiameter", "height", "heightQualifier", "breakHeight", "subplotID",
    "dataQF", "E", "N", "epsg", "pos_unc", "crown_class", "mapping_date",
    "target_population", "reference_eligible", "reference_selected", "subplot_conflict", "exclusion")
  neon_support_require(a, required, "Source references")
  if (!nrow(a) || anyNA(a[, c("uid", "plotID", "eventID")]) || any(!nzchar(a$uid)) ||
      anyDuplicated(a$uid)) stop("Missing or duplicate measurement provenance")
  if (any(a$plotID != b$plot | a$eventID != b$event)) stop("Source plot/event mismatch")
  if (anyNA(a[, c("target_population", "reference_eligible", "reference_selected", "subplot_conflict")]))
    stop("Missing predecessor flags")
  neon_support_require(mt, c("uid", "recordType"), "Mapping provenance")
  m <- neon_latest_mapping(mt)
  mi <- match(neon_support_key(a$plotID, a$individualID),
              neon_support_key(m$plotID, m$individualID))
  identity <- neon_bole_identity(a$individualID, a$growthForm)
  family <- identity$family_id
  family[is.na(family)] <- paste0("unresolved_uid:", a$uid[is.na(family)])
  keys <- paste(a$plotID, a$eventID, family, sep = "::")
  tree <- a$growthForm %in% c("single bole tree", "multi-bole tree")
  live <- !is.na(a$plantStatus) & grepl("^Live($|[ ,;])", a$plantStatus)
  broken <- grepl("broken", a$plantStatus, fixed = TRUE)
  groups <- split(seq_len(nrow(a)), keys)
  groups <- groups[vapply(groups, function(i) any(tree[i]), logical(1))]
  if (!length(groups)) stop("No tree groups in predecessor")

  units <- lapply(names(groups), function(key) {
    i <- groups[[key]]
    i <- i[order(a$individualID[i], a$uid[i], na.last = TRUE)]
    reasons <- character()
    flag <- function(condition, reason) if (isTRUE(condition)) reasons <<- c(reasons, reason)
    qualifies <- i[tree[i] & live[i] & is.finite(a$stemDiameter[i]) & a$stemDiameter[i] >= 10]
    uncertain <- any(tree[i] & (is.na(a$plantStatus[i]) |
      (live[i] & (!is.finite(a$stemDiameter[i]) | a$stemDiameter[i] <= 0))))
    status <- if (length(qualifies)) "target" else if (uncertain) "undetermined" else "outside"
    flag(status == "undetermined", "population_undetermined")
    primary <- i[which(!is.na(identity$family_id[i]) & a$individualID[i] == identity$family_id[i])]
    p <- if (length(primary) == 1L) primary else NA_integer_
    id_ok <- !is.na(identity$family_id[i]) & substring(a$individualID[i], 14, 17) == substr(b$plot, 1, 4)
    id_ok <- id_ok & !(a$growthForm[i] %in% "single bole tree" & grepl("[A-Z]$", a$individualID[i]))
    flag(!all(id_ok), "unsupported_identity")
    flag(length(primary) != 1L, "missing_or_ambiguous_primary")
    flag(anyDuplicated(a$individualID[i]) > 0L, "duplicate_bole_records")
    flag(!all(tree[i]) || length(unique(a$growthForm[i])) != 1L, "inconsistent_growth_forms")
    year <- substr(as.character(b$event_metadata$date), 1, 4)
    flag(anyNA(a$date[i]) || any(substr(as.character(a$date[i]), 1, 4) != year), "measurement_epoch_mismatch")
    flag(any(neon_support_flagged(a$dataQF[i])), "measurement_quality_flag")
    flag(any(is.na(mi[i])) || any(is.na(m$uid[mi[i]]) | !nzchar(m$uid[mi[i]])),
         "missing_or_ambiguous_mapping")
    flag(anyDuplicated(m$uid[mi[i]][!is.na(mi[i])]) > 0L, "duplicate_mapping_provenance")
    flag(any(neon_support_flagged(m$dataQF[mi[i]])), "mapping_quality_flag")
    subplot_ok <- !anyNA(a$subplotID[i]) && length(unique(a$subplotID[i])) == 1L &&
      a$subplotID[i[1]] %in% b$subplots$subplotID
    flag(!subplot_ok, "inconsistent_or_unsampled_subplot")
    flag(any(a$subplot_conflict[i]), "inherited_subplot_conflict")

    primary_live <- !is.na(p) && live[p]
    location_ok <- FALSE
    E <- N <- pos_unc <- distance <- NA_real_
    if (!is.na(p)) {
      flag(!primary_live, "primary_not_live")
      flag(!m$recordType[mi[p]] %in% "map and tag", "primary_not_mapped")
      flag(!is.finite(a$E[p]) || !is.finite(a$N[p]), "missing_primary_coordinates")
      flag(is.na(a$epsg[p]) || a$epsg[p] != b$epsg, "primary_crs_mismatch")
      flag(!is.finite(a$pos_unc[p]) || a$pos_unc[p] < 0.6, "missing_primary_uncertainty")
      location_ok <- primary_live && !is.na(mi[p]) && m$recordType[mi[p]] %in% "map and tag" &&
        is.finite(a$E[p]) && is.finite(a$N[p]) && !is.na(a$epsg[p]) && a$epsg[p] == b$epsg &&
        is.finite(a$pos_unc[p]) && a$pos_unc[p] >= 0.6
      if (location_ok) {
        E <- a$E[p]; N <- a$N[p]; pos_unc <- a$pos_unc[p]
        if (subplot_ok) {
          g <- sf::st_geometry(b$subplots)[which(b$subplots$subplotID == a$subplotID[p])]
          point <- sf::st_sfc(sf::st_point(c(E, N)), crs = b$epsg)
          distance <- as.numeric(sf::st_distance(point, g))
          flag(distance > pos_unc, "primary_subplot_conflict")
        }
      }
    }

    height_rows <- i[live[i] & is.finite(a$height[i]) & a$height[i] > 0]
    invalid <- live[i] & !is.na(a$height[i]) & (!is.finite(a$height[i]) | a$height[i] <= 0)
    flag(any(invalid), "invalid_recorded_height")
    flag(any(neon_support_flagged(a$heightQualifier[i[live[i]]])), "height_qualifier_review")
    h <- NA_integer_
    height_rule <- "unresolved"
    if (length(height_rows) == 1L && primary_live) {
      candidate <- height_rows[1]
      if (candidate == p) {
        h <- p; height_rule <- "primary_recorded_height"
      } else if (broken[p] && is.na(a$height[p]) && is.finite(a$breakHeight[p]) &&
                 a$breakHeight[p] > 0 && !broken[candidate]) {
        h <- candidate; height_rule <- "intact_relative_of_live_broken_primary"
      }
    }
    flag(length(height_rows) == 0L, "missing_live_height")
    flag(length(height_rows) > 1L, "multiple_live_height_records")
    flag(length(height_rows) == 1L && is.na(h), "height_source_requires_review")
    eligible <- status == "target" && !length(reasons)
    inside <- neon_support_inside(E, N, b$core)
    old_selected <- i[a$reference_selected[i]]
    data.frame(reference_unit_id = key, plotID = b$plot, eventID = b$event,
      individualID = if (!is.na(identity$family_id[i[1]])) identity$family_id[i[1]] else NA_character_,
      n_boles = length(i), population_status = status, target_population = status == "target",
      qualifying_bole_ids = paste(a$individualID[qualifies], collapse = "|"),
      qualifying_measurement_uids = paste(a$uid[qualifies], collapse = "|"),
      max_live_bole_dbh = if (any(live[i] & is.finite(a$stemDiameter[i])))
        max(a$stemDiameter[i][live[i] & is.finite(a$stemDiameter[i])]) else NA_real_,
      primary_id = a$individualID[p], primary_status = a$plantStatus[p],
      primary_measurement_uid = a$uid[p], primary_mapping_uid = m$uid[mi[p]],
      location_source_uid = if (location_ok) a$uid[p] else NA_character_,
      location_mapping_uid = if (location_ok) m$uid[mi[p]] else NA_character_,
      location_mapping_date = if (location_ok) a$mapping_date[p] else NA_character_,
      E = E, N = N, pos_unc = pos_unc, epsg = b$epsg,
      subplotID = if (subplot_ok) a$subplotID[i[1]] else NA_character_,
      distance_to_subplot_m = distance,
      height = a$height[h], height_source_id = a$individualID[h], height_source_uid = a$uid[h],
      height_source_dbh = a$stemDiameter[h], height_rule = height_rule, crown_class = a$crown_class[h],
      crown_class_source_uid = a$uid[h],
      n_source_selected_boles = length(old_selected),
      source_selected_uids = paste(a$uid[old_selected], collapse = "|"),
      reference_eligible = eligible, inside_interior = inside,
      reference_selected = eligible && inside,
      exclusion = if (status == "outside") paste(c("outside_target_population", reasons), collapse = "|") else
        paste(reasons, collapse = "|"), evaluation_ready = FALSE)
  })
  units <- do.call(rbind, units)
  rownames(units) <- NULL
  if (anyDuplicated(units$reference_unit_id)) stop("Duplicate individual units")
  members <- a
  members$reference_unit_id <- ifelse(keys %in% units$reference_unit_id, keys, NA_character_)
  members$source_mapping_uid <- m$uid[mi]
  members$individual_location_source <- members$uid %in% units$location_source_uid
  members$individual_height_source <- members$uid %in% units$height_source_uid
  members <- members[order(members$uid), ]
  rownames(members) <- NULL
  derived <- b
  derived$source_support_id <- neon_support_identity(b)
  derived$population <- policy$population
  derived$policy <- policy$id
  derived$individual_policy <- policy
  derived$references <- units
  derived$inherited_blockers <- b$blockers
  derived$blockers <- unique(c(b$blockers, "individual_policy_review_pending",
    "physical_coverage_pending", "native_density_pending",
    if (any(units$population_status == "undetermined")) "individual_population_undetermined",
    if (any(units$target_population & !units$reference_eligible)) "unresolved_individual_references"))
  derived$evaluation_ready <- FALSE
  comparison <- data.frame(plot = b$plot, event = b$event,
    n_source_target_boles = sum(a$target_population), n_source_selected_boles = sum(a$reference_selected),
    n_target_individuals = sum(units$target_population),
    n_population_undetermined = sum(units$population_status == "undetermined"),
    n_unresolved_target_individuals = sum(units$target_population & !units$reference_eligible),
    n_eligible_individuals = sum(units$reference_eligible),
    n_selected_individuals = sum(units$reference_selected),
    n_old_selected_units = sum(units$n_source_selected_boles > 0),
    n_retained_selected_units = sum(units$n_source_selected_boles > 0 & units$reference_selected),
    n_new_selected_units = sum(units$n_source_selected_boles == 0 & units$reference_selected),
    n_lost_selected_units = sum(units$n_source_selected_boles > 0 & !units$reference_selected),
    n_multiple_old_selected_boles = sum(units$n_source_selected_boles > 1),
    source_support_id = derived$source_support_id, support_id = neon_support_identity(derived),
    evaluation_ready = FALSE)
  list(support = derived, members = members, comparison = comparison)
}
