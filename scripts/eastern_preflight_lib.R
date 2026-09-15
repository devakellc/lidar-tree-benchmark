# Score-blind metadata inventory and field eligibility, with no detector imports.
neon_product_months <- function(site, product) {
  products <- site$dataProducts
  row <- which(products$dataProductCode == product)
  if (length(row) != 1L) stop("Missing or ambiguous product availability: ", product)
  months <- products$availableMonths[[row]]
  if (!length(months) || anyNA(months) || any(!grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", months)))
    stop("Invalid acquisition-month metadata")
  sort(unique(months))
}

eastern_inventory <- function(sites, locations, minimum_year = 2021L) {
  if (!identical(sort(names(sites)), c("BART", "HARV")) ||
      !identical(sort(names(locations)), c("BART", "HARV")))
    stop("Preflight requires HARV and BART metadata")
  products <- c(lidar = "DP1.30003.001", rgb = "DP3.30010.001", field = "DP1.10098.001")
  months <- do.call(rbind, lapply(c("HARV", "BART"), function(site)
    do.call(rbind, lapply(names(products), function(kind)
      data.frame(site = site, kind = kind, product = products[[kind]],
                 month = neon_product_months(sites[[site]], products[[kind]]))))))
  aop <- months[months$kind != "field", ]
  aop$year <- as.integer(substr(aop$month, 1, 4))
  common <- Reduce(intersect, split(aop$year, paste(aop$site, aop$kind)))
  common <- sort(common[common >= neon_year(minimum_year)])
  if (!length(common)) stop("No common LiDAR/RGB year at or after minimum year")
  year <- common[1]
  inventory <- do.call(rbind, lapply(c("HARV", "BART"), function(site) {
    frame <- neon_location_frame(locations[[site]])
    selected <- months[months$site == site & substr(months$month, 1, 4) == year, ]
    data.frame(site = site, role = if (site == "HARV") "development" else "held_out",
      acquisition_year = year, epsg = frame$epsg, datum = frame$datum,
      lidar_months = paste(selected$month[selected$kind == "lidar"], collapse = ","),
      rgb_months = paste(selected$month[selected$kind == "rgb"], collapse = ","),
      field_months = paste(selected$month[selected$kind == "field"], collapse = ","),
      field_coverage = "pending", leaf_on = "pending", native_pdens = NA_real_,
      native_frdens = NA_real_, eligible_plots_frozen = FALSE)
  }))
  list(inventory = inventory, months = months, year = year)
}

eastern_field_candidates <- function(gt, pc, year) {
  neon_validate_inputs(gt, pc)
  neon_reference_epoch(gt, year)
  required <- c("live", "is_tree", "height", "meas_year")
  if (!all(required %in% names(gt)) || !"plotType" %in% names(pc))
    stop("Missing field eligibility columns")
  valid <- gt$live %in% TRUE & gt$is_tree %in% TRUE & is.finite(gt$E) &
    is.finite(gt$N) & is.finite(gt$height) & gt$height > 0 &
    !is.na(gt$meas_year) & gt$meas_year == year
  do.call(rbind, lapply(order(pc$plotID), function(i) {
    known <- pc$plotType[i] %in% c("tower", "distributed")
    half <- if (pc$plotType[i] %in% "tower") 20 else 10
    n <- sum(valid & gt$plotID == pc$plotID[i] &
               abs(gt$E - pc$easting[i]) <= half & abs(gt$N - pc$northing[i]) <= half,
             na.rm = TRUE)
    data.frame(plot = pc$plotID[i], plot_type = pc$plotType[i], n_exact_core = n,
      field_candidate = known && n >= 6L,
      reason = if (!known) "unknown_plot_type" else if (n < 6L) "fewer_than_six_exact_trees" else "field_only",
      lidar_coverage = "pending", rgb_coverage = "pending", split_frozen = FALSE)
  }))
}
