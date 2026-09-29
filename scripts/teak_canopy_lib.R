# Preparation helpers only: no detector, scoring or admission path.
canopy_hash <- function(p) unname(vapply(p, digest::digest, character(1),
                                        file = TRUE, algo = "sha256"))

canopy_check_paths <- function(paths) {
  if (anyNA(paths) || anyDuplicated(paths) || any(!nzchar(paths)) ||
      any(grepl("(^/|\\\\|(^|/)\\.\\.?(/|$))", paths)))
    stop("Unsafe or duplicate manifest paths")
}

canopy_resolve <- function(p) {
  if (file.exists(p)) return(normalizePath(p, mustWork = TRUE))
  file.path(canopy_resolve(dirname(p)), basename(p))
}

canopy_boxes <- function(path, rgb) {
  doc <- xml2::read_xml(path)
  scalar <- function(xpath) {
    node <- xml2::xml_find_all(doc, xpath)
    if (length(node) != 1L) stop("Missing or duplicate XML metadata")
    xml2::xml_text(node)
  }
  if (scalar("/annotation/filename") != basename(terra::sources(rgb)[1]) ||
      as.numeric(scalar("/annotation/size/width")) != ncol(rgb) ||
      as.numeric(scalar("/annotation/size/height")) != nrow(rgb) ||
      as.numeric(scalar("/annotation/size/depth")) != terra::nlyr(rgb))
    stop("XML and RGB identity/dimensions disagree")
  nodes <- xml2::xml_find_all(doc, "/annotation/object")
  fields <- c("xmin", "ymin", "xmax", "ymax")
  boxes <- as.data.frame(setNames(lapply(fields, function(f) {
    vapply(nodes, function(n) {
      z <- xml2::xml_find_all(n, paste0("bndbox/", f))
      if (length(z) != 1L) stop("Incomplete bounding box")
      as.numeric(xml2::xml_text(z))
    }, numeric(1))
  }), fields))
  if (!length(nodes) || any(!is.finite(as.matrix(boxes))) ||
      any(boxes$xmin < 0 | boxes$ymin < 0 | boxes$xmax > ncol(rgb) |
          boxes$ymax > nrow(rgb) | boxes$xmin >= boxes$xmax |
          boxes$ymin >= boxes$ymax)) stop("Invalid or empty annotation boxes")
  boxes$object_index <- seq_len(nrow(boxes))
  boxes$name <- vapply(nodes, function(n) xml2::xml_text(
    xml2::xml_find_first(n, "name")), character(1))
  if (anyNA(boxes$name) || any(boxes$name != "Tree")) stop("Unexpected class")
  boxes
}

canopy_project_boxes <- function(boxes, rgb) {
  crs <- sf::st_crs(terra::crs(rgb))
  if (is.na(crs) || crs$epsg != 32611L || terra::is.rotated(rgb))
    stop("Expected unrotated TEAK WGS84 UTM 11N RGB")
  # Publisher convention: zero-origin pixel edges, origin at top left.
  rr <- terra::res(rgb)
  geom <- lapply(seq_len(nrow(boxes)), function(i) {
    b <- boxes[i, ]
    x <- terra::xmin(rgb) + c(b$xmin, b$xmax) * rr[1]
    y <- terra::ymax(rgb) - c(b$ymax, b$ymin) * rr[2]
    sf::st_polygon(list(matrix(c(x[1], y[1], x[2], y[1], x[2], y[2],
                                x[1], y[2], x[1], y[1]), ncol = 2, byrow = TRUE)))
  })
  sf::st_sf(boxes, geometry = sf::st_sfc(geom, crs = crs))
}

canopy_point_quality <- function(points, area) {
  required <- c("X", "Y", "Z", "ReturnNumber", "NumberOfReturns", "label")
  if (!all(required %in% names(points)) || !is.finite(area) || area <= 0 ||
      any(!is.finite(as.matrix(points[, c("X", "Y", "Z"), drop = FALSE]))))
    stop("Missing or invalid point fields/area")
  rn <- points$ReturnNumber; nr <- points$NumberOfReturns
  bad <- !is.finite(rn) | !is.finite(nr) | rn < 1 | nr < 1 |
    rn != floor(rn) | nr != floor(nr) | rn > nr
  data.frame(n_points = nrow(points), invalid_return_rows = sum(bad),
    stored_first_return_count = sum(rn == 1, na.rm = TRUE),
    stored_point_count_per_rgb_m2 = nrow(points) / area,
    # Deliberately not usable as native frdens/pdens parameter inputs.
    native_frdens = NA_real_, native_pdens = NA_real_,
    x_min = min(points$X), x_max = max(points$X),
    y_min = min(points$Y), y_max = max(points$Y),
    z_min = min(points$Z), z_max = max(points$Z),
    positive_label_points = sum(is.finite(points$label) & points$label > 0),
    unique_positive_labels = length(unique(points$label[
      is.finite(points$label) & points$label > 0])),
    xml_label_correspondence = "unknown",
    zero_label_points = sum(points$label == 0, na.rm = TRUE),
    missing_label_points = sum(!is.finite(points$label)))
}

canopy_plot_id <- function(x) {
  x <- as.character(x)
  short <- !is.na(x) & grepl("^[0-9]{3}$", x)
  x[short] <- paste0("TEAK_", x[short])
  x
}

canopy_local_use <- function(ids, inventory) {
  if (anyDuplicated(inventory$plotID) || anyNA(inventory$local_derived_evidence))
    stop("Invalid local exposure inventory")
  k <- match(ids, inventory$plotID)
  ifelse(is.na(k), "not_in_local_inventory", ifelse(
    inventory$local_derived_evidence[k], "historical_use",
    "no_use_in_pinned_local_inventory"))
}

# Bounds differences describe footprints, not demonstrated registration error.
canopy_raster_pair <- function(rgb, chm) {
  re <- as.vector(terra::ext(rgb)); ce <- as.vector(terra::ext(chm))
  bounds <- c("xmin", "xmax", "ymin", "ymax")
  z <- c(setNames(re, paste0("rgb_", bounds)),
         setNames(ce, paste0("chm_", bounds)),
         setNames(ce - re, paste0("chm_minus_rgb_", bounds, "_m")))
  data.frame(chm_epsg = sf::st_crs(terra::crs(chm))$epsg,
    chm_extent_matches_rgb = identical(re, ce),
    as.list(z), check.names = FALSE)
}
