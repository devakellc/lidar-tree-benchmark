# Pilot diagnostics preserve all points and never admit evaluation.
pilot_xy_inside <- function(p, extent) {
  p$X >= extent[1] & p$X <= extent[2] & p$Y >= extent[3] & p$Y <= extent[4]
}

pilot_return_checks <- function(p) {
  required <- c("X", "Y", "Z", "ReturnNumber", "NumberOfReturns",
                "PointSourceID", "gpstime", "Classification", "Withheld_flag")
  if (!all(required %in% names(p)) || !nrow(p) ||
      any(!is.finite(as.matrix(p[, c("X", "Y", "Z", "gpstime")]))))
    stop("Missing or invalid native point fields")
  rn <- p$ReturnNumber; nr <- p$NumberOfReturns
  if (anyNA(rn) || anyNA(nr) || any(rn < 1 | rn > nr | nr > 7 |
      rn != floor(rn) | nr != floor(nr))) stop("Invalid native LAS 1.3 return fields")
  invisible(TRUE)
}

pilot_point_keys <- function(p) {
  # Both source files declare 0.001 m XY scales. This matches source-coordinate
  # tuples; it does not assign the missing published CRS or identify tree IDs.
  sprintf("%.0f:%.0f:%d:%d", round(p$X * 1000), round(p$Y * 1000),
          p$PointSourceID, p$ReturnNumber)
}

pilot_point_correspondence <- function(published, native) {
  pk <- pilot_point_keys(published); nk <- pilot_point_keys(native)
  pc <- table(pk); nc <- table(nk)
  pn <- unname(pc[pk]); nn <- as.integer(nc[pk]); nn[is.na(nn)] <- 0L
  unique_match <- pn == 1L & nn == 1L
  target <- match(pk, nk)
  target[!unique_match] <- NA_integer_
  data.frame(published_row = seq_along(pk) - 1L,
    native_context_row = target - 1L, coordinate_key = pk,
    published_key_count = as.integer(pn), native_key_count = nn,
    status = ifelse(nn == 0L, "unmatched", ifelse(unique_match,
      "unique_coordinate_tuple", "ambiguous_duplicate_tuple")))
}

pilot_density <- function(p, extent, label) {
  p <- p[pilot_xy_inside(p, extent), , drop = FALSE]
  area <- (extent[2] - extent[1]) * (extent[4] - extent[3])
  if (!is.finite(area) || area <= 0) stop("Invalid density footprint")
  data.frame(footprint = label, area_m2 = area, n_points = nrow(p),
    first_returns = sum(p$ReturnNumber == 1L), ground_points = sum(p$Classification == 2L),
    noise_class7 = sum(p$Classification == 7L), withheld = sum(p$Withheld_flag),
    frdens = sum(p$ReturnNumber == 1L) / area, pdens = nrow(p) / area)
}

pilot_density_grid <- function(p, extent, size = 10) {
  nx <- (extent[2] - extent[1]) / size; ny <- (extent[4] - extent[3]) / size
  if (any(!is.finite(c(nx, ny))) || nx <= 0 || ny <= 0 ||
      nx != round(nx) || ny != round(ny) || any(!pilot_xy_inside(p, extent)))
    stop("Density grid must completely cover the native clip")
  grid <- expand.grid(ix = seq_len(nx) - 1L, iy = seq_len(ny) - 1L)
  ix <- pmin(nx - 1L, floor((p$X - extent[1]) / size))
  iy <- pmin(ny - 1L, floor((p$Y - extent[3]) / size))
  cell <- ix + nx * iy + 1L
  grid$n_points <- tabulate(cell, nbins = nrow(grid))
  grid$first_returns <- tabulate(cell[p$ReturnNumber == 1L], nbins = nrow(grid))
  grid$ground_points <- tabulate(cell[p$Classification == 2L], nbins = nrow(grid))
  grid$xmin <- extent[1] + grid$ix * size; grid$ymin <- extent[3] + grid$iy * size
  grid$xmax <- grid$xmin + size; grid$ymax <- grid$ymin + size
  grid$frdens <- grid$first_returns / size^2; grid$pdens <- grid$n_points / size^2
  grid
}

pilot_preserved <- function(before, after, z_tolerance = NULL) {
  if (nrow(before) != nrow(after) || !all(names(before) %in% names(after)))
    stop("Point rows or source fields were lost")
  same <- setdiff(names(before), "Z")
  if (!isTRUE(all.equal(before[, same, drop = FALSE], after[, same, drop = FALSE],
                       tolerance = 0, check.attributes = FALSE)))
    stop("Point order or non-height fields changed")
  if (any(!is.finite(after$Z))) stop("Normalization produced unknown heights")
  if (!is.null(z_tolerance) && any(abs(before$Z - after$Z) > z_tolerance))
    stop("Exported Z differs beyond LAS precision")
  invisible(TRUE)
}

pilot_compare_chm <- function(published, native) {
  cropped <- terra::crop(native, published, snap = "near")
  if (!isTRUE(terra::compareGeom(published, cropped, stopOnError = FALSE)))
    stop("CHM comparison grids differ")
  p <- as.vector(terra::values(published)); n <- as.vector(terra::values(cropped))
  valid <- is.finite(p) & is.finite(n)
  list(cells = length(p), valid_pairs = sum(valid),
    missingness_disagreements = sum(is.na(p) != is.na(n)),
    equal_values = sum(p[valid] == n[valid]),
    max_abs_difference_m = max(abs(p[valid] - n[valid])),
    mean_signed_difference_m = mean(p[valid] - n[valid]),
    identical_values = identical(p, n))
}


pilot_add_rows <- function(las) {
  if (any(c("pilot_row", "Zref") %in% names(las@data)))
    stop("Native source collides with reserved pilot fields")
  lidR::add_lasattribute(las, seq_len(nrow(las@data)) - 1L, "pilot_row",
                        "Zero-based native context row")
}

pilot_normalize <- function(las) {
  if ("Zref" %in% names(las@data))
    stop("Native source collides with reserved pilot fields")
  normalized <- lidR::normalize_height(las, lidR::tin(), use_class = 2L,
                                       na.rm = FALSE)
  if (!identical(normalized$Zref, las$Z))
    stop("Normalization did not preserve absolute source elevation")
  # normalize_height creates Zref in memory. Register it as double extra bytes
  # so writeLAS preserves the original absolute elevation without quantization.
  lidR::add_lasattribute_manual(normalized, name = "Zref",
    desc = "Original absolute elevation", type = "double")
}


pilot_field_discrepancies <- function(published, native, correspondence) {
  matched <- which(correspondence$status == "unique_coordinate_tuple")
  target <- correspondence$native_context_row[matched] + 1L
  fields <- union(names(published), setdiff(names(native), "pilot_row"))
  do.call(rbind, lapply(fields, function(field) {
    common <- field %in% names(published) && field %in% names(native)
    a <- published[[field]][matched]; b <- native[[field]][target]
    valid <- if (common) !is.na(a) & !is.na(b) else logical()
    data.frame(field = field, published_present = field %in% names(published),
      native_present = field %in% names(native),
      unique_tuple_pairs = if (common) length(matched) else 0L,
      valid_pairs = sum(valid),
      missingness_disagreements = if (common) sum(is.na(a) != is.na(b)) else NA_integer_,
      equal_values = if (common) sum(a[valid] == b[valid]) else NA_integer_,
      differing_values = if (common) sum(a[valid] != b[valid]) else NA_integer_,
      interpretation = if (field == "Z") "different_height_frames" else
        "coordinate_tuple_comparison_not_identity")
  }))
}
