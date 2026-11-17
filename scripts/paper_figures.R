#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("model_bench_lib.R"))

# The paper's figures, from the master tables, the study outputs of the paper
# runs and the detectors' persisted detections. Base graphics (grid for the
# schematic), so the reproduction image needs nothing more. Each figure is
# written twice by one drawing function: a 200-dpi PNG for the markdown and a
# vector PDF (cairo_pdf) for LaTeX. Both are drawn at the width the figure
# prints at in the IEEE version, so 8-point text prints at 8 points:
# paper_to_ieee.py sets a figure at the width of its PDF, as a share of the
# text width (7.16 in; the supplement's is 6.925 in, and its figures are drawn
# for 6.9 in), rounded up to hundredths. Every figure but the schematic also
# writes the numbers it plots (figure_<id>.csv), which the reproduction
# compares like any table.
#   1   sites: (a) map of the five sites, (b) stems by crown class, (c) native
#       pulse density with the QL1 and QL2 floors, (d) stem heights
#   2   schematic: the evaluation protocol and the density-routed pipeline
#   3   F1, recall, precision and chance-corrected F1 against pulse density,
#       the eight detectors run at every density
#   4   each detector's rank across the density series, with the rank
#       correlations
#   5   overstory and understory recall against pulse density
#   6   native sparse flights against the thinned 2021 levels
#   7   detections on one plot: CHM-VWF, ForestFormer3D and SegmentAnyTree at
#       native density, the QL2 level and the sparsest level
#   s1  nominal-box and censused precision per detector (native), with the
#       credited bracket
#   s2  sensitivity: match radius, matcher, stem-position jitter, chance null
#   Rscript scripts/paper_figures.R [FIGURES=1,2,3,4,5,6,7,s1,s2] [OUT=<dir>]
#     [FROZEN_ROOT=...] [SPARSE_REPORT=<dir>] [MASTER=<master_tables dir>]
#     [QL2_JOB=<dir>] [QL2_ROOT=<dir>] [QL2_SENSITIVITY=<dir>]
#     [EXAMPLE_PLOT=<plotID>] [NE_COUNTRIES=<ne_10m_admin_0_countries.shp>]
# CLAUDE_JOB_DIR is the paper-run job directory (master_tables/, sensitivity/,
# neon/<SITE>/ with coverage_gap.csv, plot_centroids.csv and the persisted
# detections). The QL2 level is frozen in its own root and scored in its own
# job directory: QL2_JOB defaults to <job dir>/../paper_runs_ql2, QL2_ROOT to
# <QL2_JOB>/neon/frozen_2021_ql2 and QL2_SENSITIVITY, its null and matcher
# re-scores, to <QL2_JOB>/sensitivity. SPARSE_REPORT defaults to
# <job dir>/../sparse_2018/compare_report. The map reads the Natural Earth
# extract committed under paper/figures/data (README there);
# NE_COUNTRIES=<path> rebuilds that extract from the Natural Earth shapefile
# before drawing.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
d <- .job_dir()
ALL_FIGS <- c("1", "2", "3", "4", "5", "6", "7", "s1", "s2")
FIGS <- strsplit(if (is.null(A$FIGURES)) paste(ALL_FIGS, collapse = ",") else A$FIGURES, ",")[[1]]
if (length(setdiff(FIGS, ALL_FIGS))) stop("Unknown figures: ", paste(setdiff(FIGS, ALL_FIGS), collapse = ", "))
OUT <- if (is.null(A$OUT)) file.path(d, "figures") else A$OUT
ROOT <- frozen_root(d, A$FROZEN_ROOT)
MT <- if (is.null(A$MASTER)) file.path(d, "master_tables") else A$MASTER
SPARSE <- if (is.null(A$SPARSE_REPORT)) file.path(dirname(d), "sparse_2018", "compare_report") else A$SPARSE_REPORT
QL2_JOB <- if (is.null(A$QL2_JOB)) file.path(dirname(d), "paper_runs_ql2") else A$QL2_JOB
QL2_ROOT <- if (is.null(A$QL2_ROOT)) file.path(QL2_JOB, "neon", "frozen_2021_ql2") else A$QL2_ROOT
QL2S <- if (is.null(A$QL2_SENSITIVITY)) file.path(QL2_JOB, "sensitivity") else A$QL2_SENSITIVITY
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
SITES <- c("SJER", "SOAP", "TEAK", "WREF", "ABBY")

ARMS <- c(chm_vwf = "CHM-VWF", multichm = "multichm", lmfauto = "lmfauto", ptrees = "ptrees",
          ams3d = "AMS3D", li2012 = "Li 2012", forestformer3d = "ForestFormer3D",
          treeisonet = "TreeisoNet", segmentanytree = "SegmentAnyTree",
          deepforest = "DeepForest", detectree2 = "Detectree2", sam2point = "SAM2Point")
# The eight detectors run at every density (the density series).
LADDER <- c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d", "forestformer3d",
            "treeisonet", "segmentanytree")
COL <- c(chm_vwf = "#000000", multichm = "#E69F00", lmfauto = "#999999", ptrees = "#56B4E9",
         ams3d = "#009E73", li2012 = "#8C564B", forestformer3d = "#D55E00",
         treeisonet = "#CC79A7", segmentanytree = "#0072B2", deepforest = "#6A3D9A",
         detectree2 = "#B15928", sam2point = "#7F7F7F")
PCH <- setNames(c(16, 17, 15, 18, 1, 2, 16, 17, 15, 0, 5, 6), names(ARMS))
QL <- c(QL2 = 2, QL1 = 8)                       # USGS aggregate nominal pulse density

read_mt <- function(f) read.csv(file.path(MT, f), stringsAsFactors = FALSE,
                                colClasses = c(rung = "character"))
long <- read_mt("master_long.csv")
long <- long[long$status == "included", , drop = FALSE]
dens <- read_mt("rung_density.csv")
pulses <- setNames(dens$pulses_median[dens$scope == "five sites"], dens$rung[dens$scope == "five sites"])

## ---- devices -------------------------------------------------------------------------
PT <- 8                    # device point size: text at cex 1 prints at 8 pt
TEXT_W <- 7.16             # IEEE text width (in); the supplement's is 6.925 in
SUPP_W <- 6.9
# Draws one figure into a 200-dpi PNG and a cairo PDF of the same size.
render <- function(id, w, h, draw) {
  base <- file.path(OUT, paste0("figure_", id))
  png(paste0(base, ".png"), width = w, height = h, units = "in", res = 200, pointsize = PT,
      type = "cairo")
  tryCatch(draw(), finally = dev.off())
  grDevices::cairo_pdf(paste0(base, ".pdf"), width = w, height = h, pointsize = PT)
  tryCatch(draw(), finally = dev.off())
  invisible(base)
}
# Text sizes at print size: titles 8.8 pt bold, axis titles 8 pt, tick labels
# and legends 7.2 pt. layout() and mfrow shrink cex, so this runs after them.
fig_par <- function(...) par(cex = 1, cex.main = 1.1, cex.lab = 1, cex.axis = 0.9,
                             font.main = 2, mgp = c(1.8, 0.45, 0), tcl = -0.3, ...)
LEG_CEX <- 0.9
save_data <- function(id, x) write.csv(x, file.path(OUT, sprintf("figure_%s.csv", id)), row.names = FALSE)
ql_lines <- function() {
  abline(v = QL, lty = 3, col = "grey40")
  text(QL, par("usr")[4], names(QL), pos = 1, cex = LEG_CEX, col = "grey30")
}
# Density axis with a tick at each level's five-site median, labelled as the
# text labels the levels (9.8, 4.7, 2.5, 2.0, 1.3, 0.6 pulses/m²). No label is
# thinned. 2.5 and 2.0 sit close: where two neighbouring labels would stand
# less than an em apart, each is moved away from the other along the axis by
# half the shortfall, still over its own tick; ticks and data keep their places.
dens_axis <- function() {
  lab <- formatC(pulses, format = "f", digits = 1)
  axis(1, at = pulses, labels = FALSE)
  xin <- grconvertX(pulses, "user", "inches")
  w <- strwidth(lab, "inches", cex = par("cex.axis"))
  em <- strwidth("M", "inches", cex = par("cex.axis"))
  hadj <- rep(0.5, length(lab))
  o <- order(xin)
  for (k in seq_len(length(o) - 1L)) {
    i <- o[k]; j <- o[k + 1L]
    short <- em - ((xin[j] - xin[i]) - (w[i] + w[j]) / 2)
    if (short > 0) {
      hadj[i] <- min(0.9, hadj[i] + short / 2 / w[i])
      hadj[j] <- max(0.1, hadj[j] - short / 2 / w[j])
    }
  }
  for (h in unique(hadj))
    axis(1, at = pulses[hadj == h], labels = lab[hadj == h], tick = FALSE, hadj = h, gap.axis = 0)
}
legend_arms <- function(arms, where = "bottomleft", ...)
  legend(where, legend = ARMS[arms], col = COL[arms], pch = PCH[arms], lty = 1, bty = "n",
         cex = LEG_CEX, ...)
# A legend in a panel of its own (a strip or a column beside the plots).
legend_panel <- function(...) {
  par(mar = c(0, 0, 0, 0)); plot.new()
  legend("center", bty = "n", cex = LEG_CEX, ...)
}
ladder_rows <- function(tab, scope = "five sites", metric = "F1", arms = LADDER) {
  x <- long[long$table == tab & long$scope == scope & long$metric == metric &
              long$detector %in% arms & long$rung %in% names(pulses), , drop = FALSE]
  x$pulses <- unname(pulses[x$rung])
  x[order(x$detector, -x$pulses), ]
}
ci_lines <- function(x, y, lo, hi, col) segments(x, lo, x, hi, col = adjustcolor(col, 0.6))
# The chance-agreement outputs (paper_sensitivity.R MODE=null): the main
# series' file and, when present, the QL2 level's, read from its own
# sensitivity directory.
read_null <- function(f) {
  x <- read.csv(file.path(d, "sensitivity", f), stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  q <- file.path(QL2S, f)
  if (file.exists(q)) x <- rbind(x, read.csv(q, stringsAsFactors = FALSE, colClasses = c(rung = "character")))
  x
}

## ---- 1: sites -----------------------------------------------------------------------
# (a) Locations on the U.S. Pacific coast, from a Natural Earth 1:10m Admin 0
# extract (public domain) committed with the paper; there are no state
# outlines, so the regions are labelled. A site is placed at the mean of its
# population plots' centroids (plot_centroids.csv, UTM in the population's
# EPSG). (b) to (d): stems by crown class, native pulse density with the QL1
# and QL2 floors, stem heights.
MAP_DATA <- file.path(.ROOT, "paper", "figures", "data", "ne_10m_admin_0_countries_pacific.geojson")
MAP_CRS <- "+proj=aea +lat_0=40 +lon_0=-120 +lat_1=34 +lat_2=46 +datum=WGS84 +units=m +no_defs"
# The area the frame must hold. The frame drawn is larger, about 128.8 to
# 111.2 W and 28.7 to 52.9 N: the panel is taller than this area at one scale
# on both axes, and the meridians converge northward.
MAP_LONLAT <- c(xmin = -126.4, ymin = 31.6, xmax = -113.6, ymax = 50.0)
# The extract's crop box, wider than the frame on every side: draw_map stops
# when the frame reaches past the map data, which would end the land in false
# straight lines.
MAP_EXTRACT <- c(xmin = -132, ymin = 26, xmax = -106, ymax = 56)
REGION <- c(SJER = "California", SOAP = "California", TEAK = "California",
            WREF = "Washington", ABBY = "Washington")
REGION_COL <- c(California = "#D55E00", Washington = "#0072B2")

# Rebuilds the extract: USA, Canada and Mexico cropped to MAP_EXTRACT around
# the U.S. Pacific coast, simplified to 0.01 degree (about 1 km, below a
# printed line width) and written as RFC 7946 GeoJSON with four decimals.
make_map_extract <- function(shp, out = MAP_DATA) {
  s2 <- suppressMessages(sf::sf_use_s2(FALSE))
  on.exit(suppressMessages(sf::sf_use_s2(s2)), add = TRUE)
  ne <- sf::st_read(shp, quiet = TRUE)
  ne <- ne[ne$ISO_A3 %in% c("USA", "CAN", "MEX"), c("NAME", "ISO_A3")]
  bb <- sf::st_bbox(MAP_EXTRACT, crs = sf::st_crs(4326))
  x <- suppressWarnings(suppressMessages(sf::st_crop(ne, bb)))
  x <- suppressWarnings(sf::st_simplify(x, preserveTopology = TRUE, dTolerance = 0.01))
  x <- sf::st_cast(x, "MULTIPOLYGON")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  unlink(out)
  sf::st_write(x, out, layer_options = c("RFC7946=YES", "COORDINATE_PRECISION=4"), quiet = TRUE)
  cat(sprintf("map extract -> %s (%d bytes)\n", out, file.size(out)))
}

site_positions <- function(pop) {
  do.call(rbind, lapply(SITES, function(s) {
    pc <- read.csv(file.path(d, "neon", s, "plot_centroids.csv"), stringsAsFactors = FALSE)
    p <- pop[pop$site == s & pop$in_adopted, ]
    i <- match(p$plotID, pc$plotID)
    if (anyNA(i)) stop("population plots missing from ", s, " plot_centroids.csv")
    if (any(abs(pc$easting[i] - p$easting) > 0.01 | abs(pc$northing[i] - p$northing) > 0.01))
      stop("plot_centroids.csv and population.csv disagree for ", s)
    epsg <- unique(p$epsg)
    if (length(epsg) != 1L) stop("more than one EPSG among the plots of ", s)
    m <- sf::st_sfc(sf::st_point(c(mean(pc$easting[i]), mean(pc$northing[i]))), crs = epsg)
    ll <- sf::st_coordinates(sf::st_transform(m, 4326))
    data.frame(site = s, longitude = ll[1, 1], latitude = ll[1, 2], plots = length(i),
               stringsAsFactors = FALSE)
  }))
}

# The box a map label covers (a polygon in the map's coordinates, which have
# one scale on both axes), placed as text() places it, as measured on the
# figure's devices: at pos 1 to 4 beside the point, `offset` character heights
# away, with the point a third of the cap height above the baseline at pos 2
# and 4 and the cap line a sixth of the cap height above (point - offset) at
# pos 1; otherwise centred on the point (one line on its ink, several lines on
# their block) and turned by srt degrees about it. The box runs from the
# descenders, when the label has any, to the cap line of its first line and is
# padded by a tenth of the cap height.
text_box <- function(x, y, s, cex, font = 1, pos = NULL, offset = 0.5, srt = 0) {
  w <- strwidth(s, cex = cex, font = font); h <- strheight(s, cex = cex, font = font)
  m <- strheight("M", cex = cex, font = font)
  dsc <- if (grepl("[gjpqy(),;]", s)) 0.3 * m else 0
  off <- offset * par("cin")[2] * par("cex") * diff(par("usr")[1:2]) / par("pin")[1]
  l <- -w / 2; b <- if (grepl("\n", s)) -h / 2 else -(h - dsc) / 2   # left edge, last baseline
  if (!is.null(pos)) {
    if (pos == 1) b <- -off - 5 / 6 * h
    if (pos == 2) { l <- -off - w; b <- -h / 3 }
    if (pos == 3) b <- off
    if (pos == 4) { l <- off; b <- -h / 3 }
  }
  pad <- 0.1 * m
  xy <- cbind(c(l - pad, l + w + pad, l + w + pad, l - pad, l - pad),
              c(b - dsc - pad, b - dsc - pad, b + h + pad, b + h + pad, b - dsc - pad))
  a <- srt * pi / 180
  xy <- xy %*% rbind(c(cos(a), sin(a)), c(-sin(a), cos(a)))
  sf::st_polygon(list(sweep(xy, 2, c(x, y), "+")))
}

draw_map <- function(sp) {
  s2 <- suppressMessages(sf::sf_use_s2(FALSE))
  on.exit(suppressMessages(sf::sf_use_s2(s2)), add = TRUE)
  ne <- sf::st_read(MAP_DATA, quiet = TRUE)
  # The area to hold, densified so that its projected bounding box holds the
  # curved parallels.
  lon <- seq(MAP_LONLAT[["xmin"]], MAP_LONLAT[["xmax"]], length.out = 60)
  lat <- seq(MAP_LONLAT[["ymin"]], MAP_LONLAT[["ymax"]], length.out = 60)
  ring <- rbind(cbind(lon, lat[1]), cbind(lon[60], lat), cbind(rev(lon), lat[60]), cbind(lon[1], rev(lat)))
  area <- sf::st_sfc(sf::st_polygon(list(rbind(ring, ring[1, ]))), crs = 4326)
  bb <- sf::st_bbox(sf::st_transform(area, MAP_CRS))
  par(mar = c(1.3, 1.6, 1.6, 0.4))
  plot.new()
  plot.window(xlim = bb[c("xmin", "xmax")], ylim = bb[c("ymin", "ymax")], asp = 1, xaxs = "i", yaxs = "i")
  u <- par("usr")
  box_poly <- sf::st_sfc(sf::st_polygon(list(rbind(u[c(1, 3)], u[c(2, 3)], u[c(2, 4)], u[c(1, 4)],
                                                   u[c(1, 3)]))), crs = MAP_CRS)
  frame <- sf::st_cast(box_poly, "LINESTRING")
  # The frame (its edges densified, as they curve in longitude and latitude)
  # must lie inside the map data, or the land would end in straight lines at
  # the extract's crop box.
  fr <- sf::st_bbox(sf::st_transform(sf::st_segmentize(box_poly, 5000), 4326))
  ex <- sf::st_bbox(ne)
  if (fr[["xmin"]] < ex[["xmin"]] || fr[["xmax"]] > ex[["xmax"]] ||
      fr[["ymin"]] < ex[["ymin"]] || fr[["ymax"]] > ex[["ymax"]])
    stop(sprintf(paste("figure 1(a): the frame spans longitude %.2f to %.2f and latitude %.2f to %.2f, past",
                       "the map data (%.2f to %.2f, %.2f to %.2f); rebuild the extract wider (MAP_EXTRACT)"),
                 fr[["xmin"]], fr[["xmax"]], fr[["ymin"]], fr[["ymax"]],
                 ex[["xmin"]], ex[["xmax"]], ex[["ymin"]], ex[["ymax"]]))
  # Natural Earth's edges are straight in longitude and latitude (the border
  # along 49°N is a single edge), so they are cut into pieces of at most 0.1°
  # there before projecting, to follow the parallels. Only the land inside the
  # frame is drawn, so the PDF holds no hidden paths.
  g <- sf::st_set_crs(sf::st_segmentize(sf::st_set_crs(sf::st_geometry(ne), NA), 0.1), 4326)
  land <- suppressWarnings(suppressMessages(sf::st_crop(sf::st_transform(g, MAP_CRS), sf::st_bbox(box_poly))))
  rect(u[1], u[3], u[2], u[4], col = "#F4F8FB", border = NA)
  # Graticule every 5 degrees, drawn under the land so that it shows on the sea
  # only, and labelled where it leaves the frame.
  gr <- sf::st_graticule(box_poly, lon = seq(-130, -110, 5), lat = seq(30, 50, 5),
                         datum = sf::st_crs(4326), ndiscr = 200)
  plot(sf::st_geometry(gr), col = "grey70", lwd = 0.4, lty = 3, add = TRUE)
  plot(land, col = "grey90", border = "grey45", lwd = 0.5, add = TRUE)
  for (i in seq_len(nrow(gr))) {
    p <- suppressWarnings(sf::st_cast(sf::st_intersection(sf::st_geometry(gr)[i], frame), "POINT"))
    if (!length(p)) next
    xy <- sf::st_coordinates(p)
    lab <- if (gr$type[i] == "E") sprintf("%d°W", abs(gr$degree[i])) else sprintf("%d°N", gr$degree[i])
    if (gr$type[i] == "E") {             # meridian: label at the bottom edge
      k <- which(abs(xy[, 2] - u[3]) < 1)
      if (length(k)) axis(1, at = xy[k[1], 1], labels = lab, tick = FALSE, line = -0.25)
    } else {                             # parallel: label at the left edge
      k <- which(abs(xy[, 1] - u[1]) < 1)
      if (length(k)) axis(2, at = xy[k[1], 2], labels = lab, tick = FALSE, line = -0.25)
    }
  }
  lab_at <- function(lon, lat) sf::st_coordinates(sf::st_transform(
    sf::st_sfc(sf::st_point(c(lon, lat)), crs = 4326), MAP_CRS))[1, 1:2]
  # Every label is drawn through label(), which keeps its box for the check
  # below. Text is at least 7.2 pt (LEG_CEX) at print size.
  boxes <- list(); owner <- character()
  label <- function(xy, s, cex = LEG_CEX, font = 1, pos = NULL, offset = 0.5, srt = 0, site = "", ...) {
    text(xy[1], xy[2], s, cex = cex, font = font, pos = pos, offset = offset, srt = srt, ...)
    boxes[[gsub("\n", " ", s)]] <<- text_box(xy[1], xy[2], s, cex, font, pos, offset, srt)
    owner[[gsub("\n", " ", s)]] <<- site
  }
  label(lab_at(-122.6, 33.0), "Pacific\nOcean", font = 3, col = "grey40")
  label(lab_at(-119.6, 49.55), "CANADA", col = "grey40")
  # Mexico's land in the frame is the Baja California peninsula and a sliver
  # of Sonora, too narrow for a level label, so the name runs down the
  # peninsula.
  label(lab_at(-115.45, 31.15), "MEXICO", col = "grey40", srt = -75)
  pts <- sf::st_coordinates(sf::st_transform(sf::st_as_sf(sp, coords = c("longitude", "latitude"),
                                                         crs = 4326), MAP_CRS))
  cl <- REGION_COL[REGION[sp$site]]
  # Site codes beside their points: SJER, SOAP and TEAK lie within 70 km of
  # each other and WREF and ABBY within 30 km, and a code to the left of SJER
  # or ABBY would cross the coast.
  pos <- c(SJER = 1, SOAP = 3, TEAK = 4, WREF = 4, ABBY = 1)[sp$site]
  points(pts[, 1], pts[, 2], pch = 21, bg = cl, col = "black", cex = 1.1, lwd = 0.6)
  for (i in seq_len(nrow(sp)))
    label(pts[i, 1:2], sp$site[i], font = 2, pos = pos[[i]], offset = 0.6, col = cl[[i]], site = sp$site[i])
  # Region labels inland.
  label(lab_at(-116.8, 35.3), "California\n(development)", col = REGION_COL[["California"]])
  label(lab_at(-119.3, 47.4), "Washington\n(replication)", col = REGION_COL[["Washington"]])
  # 200 km scale bar on the open sea between the graticule lines (Albers
  # equal-area: the scale is within about 1% between 34 and 46°N).
  sb <- lab_at(-124.35, 31.2)
  segments(sb[1], sb[2], sb[1] + 2e5, sb[2], lwd = 1.5, lend = 1)
  tk <- 0.008 * diff(u[3:4])
  segments(c(sb[1], sb[1] + 2e5), sb[2], c(sb[1], sb[1] + 2e5), sb[2] + tk, lwd = 1)
  label(c(sb[1] + 1e5, sb[2]), "200 km", pos = 3, offset = 0.35, site = "scale")
  boxes[["scale bar"]] <- sf::st_polygon(list(rbind(c(sb[1], sb[2] - tk), c(sb[1] + 2e5, sb[2] - tk),
                                                     c(sb[1] + 2e5, sb[2] + tk), c(sb[1], sb[2] + tk),
                                                     c(sb[1], sb[2] - tk))))
  owner[["scale bar"]] <- "scale"
  box(lwd = 0.6)
  title(main = "(a) Sites")
  # No label may touch the coastline or a border, the graticule on the sea,
  # the frame, another site's point or another label.
  bx <- sf::st_sfc(boxes, crs = MAP_CRS)
  sea_grid <- suppressWarnings(sf::st_difference(sf::st_union(sf::st_geometry(gr)), sf::st_union(land)))
  linework <- c(sf::st_cast(sf::st_boundary(land), "MULTILINESTRING"),   # coasts and borders
                sf::st_cast(sea_grid, "MULTILINESTRING"), sf::st_cast(frame, "MULTILINESTRING"))
  # A site's point (pch 21 at cex 1.1) prints 0.062 in across, its outline
  # included.
  r_pt <- 0.031 * diff(u[1:2]) / par("pin")[1]
  dots <- sf::st_buffer(sf::st_sfc(lapply(seq_len(nrow(pts)), function(i) sf::st_point(pts[i, 1:2])),
                                   crs = MAP_CRS), r_pt)
  bad <- character()
  for (i in seq_along(bx)) {
    nm <- names(boxes)[i]
    if (any(sf::st_intersects(bx[i], linework, sparse = FALSE))) bad <- c(bad, paste(nm, "crosses a line"))
    if (any(sf::st_intersects(bx[i], dots[sp$site != owner[[nm]]], sparse = FALSE)))
      bad <- c(bad, paste(nm, "covers another site's point"))
    same <- nzchar(owner[[nm]]) & owner == owner[[nm]]       # a scale bar and its label
    j <- which(sf::st_intersects(bx[i], bx, sparse = FALSE)[1, ] & !same & seq_along(bx) != i)
    if (length(j)) bad <- c(bad, paste(nm, "overlaps", paste(names(boxes)[j], collapse = ", ")))
  }
  if (length(bad)) warning("figure 1(a): ", paste(unique(bad), collapse = "; "))
}

fig1 <- function() {
  if (!is.null(A$NE_COUNTRIES)) make_map_extract(A$NE_COUNTRIES)
  if (!file.exists(MAP_DATA)) stop("Natural Earth extract not found: ", MAP_DATA)
  st <- read.csv(file.path(ROOT, "population_stems.csv"), stringsAsFactors = FALSE)
  st <- st[st$population == "adopted", ]
  cm <- frozen_clip_manifest(ROOT)
  pop <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
  nat <- cm[cm$rung == "native" & cm$status == "ok" &
              paste(cm$site, cm$plot) %in% paste(pop$site, pop$plotID)[pop$in_adopted], ]
  cls <- c("dominant", "codominant", "intermediate", "suppressed")
  tab <- sapply(SITES, function(s) table(factor(st$crown_class[st$site == s], cls)))
  sp <- site_positions(pop)
  save_data("1", rbind(
    data.frame(panel = "stems", site = rep(SITES, each = 4), key = rep(cls, 5), value = as.vector(tab)),
    data.frame(panel = "native_pulses", site = nat$site, key = nat$plot, value = nat$frdens),
    data.frame(panel = "height", site = st$site, key = st$individualID, value = st$height),
    data.frame(panel = "map", site = rep(sp$site, 3),
               key = rep(c("longitude", "latitude", "plots"), each = nrow(sp)),
               value = c(sp$longitude, sp$latitude, sp$plots))))
  ccol <- c("#1B9E77", "#66C2A5", "#FC8D62", "#E78AC3")
  render("1", TEXT_W, 4.3, function() {
    layout(matrix(c(1, 2, 2, 1, 3, 4), 2, byrow = TRUE), widths = c(2.06, 2.55, 2.55))
    fig_par()
    draw_map(sp)
    par(mar = c(2.2, 3.2, 1.6, 0.6))
    barplot(tab, col = ccol, ylab = "Stems", main = "(b) Stems by crown class")
    legend("topleft", legend = cls, fill = ccol, bty = "n", cex = LEG_CEX)
    # Site names drawn without thinning (five fit the panel width).
    sites_axis <- function() axis(1, at = seq_along(SITES), labels = SITES, gap.axis = 0)
    ylim <- range(c(nat$frdens, QL)) * c(0.85, 1.1)
    par(mar = c(2.2, 3.2, 1.6, 1.8))
    boxplot(frdens ~ factor(site, SITES), data = nat, log = "y", ylim = ylim, xlab = "", xaxt = "n",
            ylab = "First-return pulses/m²", main = "(c) Native pulse density",
            outcex = 0.6)
    sites_axis()
    abline(h = QL, lty = 3, col = "grey40")
    mtext(names(QL), side = 4, at = QL, las = 1, line = 0.2, cex = LEG_CEX, col = "grey30")
    par(mar = c(2.2, 3.2, 1.6, 0.6))
    boxplot(height ~ factor(site, SITES), data = st, xlab = "", xaxt = "n", ylab = "Stem height (m)",
            main = "(d) Reference stem heights", outcex = 0.5)
    sites_axis()
  })
}

## ---- 2: the evaluation protocol and the density-routed pipeline -----------------------
# A schematic (no data file): the protocol every detector is scored by, and the
# pipeline that routes a new tile to a detector by its measured density. The
# detector boxes stay generic; the caption cites the decision table.
fig2 <- function() {
  # The schematic plots no numbers: remove the old Figure 2's data file (now
  # Figure 3's), so that a figures folder never pairs it with the schematic.
  unlink(file.path(OUT, "figure_2.csv"))
  W <- TEXT_W
  bw <- 1.25; gap <- (W - 0.08 - 5 * bw) / 4
  cx <- 0.04 + bw / 2 + (0:4) * (bw + gap)
  # Bottom up: a margin, row (b), the space between the rows (the title of (b)
  # and the dashed connector with its label), row (a) and the title of (a).
  # Each title stands about 0.1 in above its row.
  bh <- 0.97; mb <- 0.05; between <- 0.54; mt <- 0.27
  H <- mb + 2 * bh + between + mt               # 2.8 in
  yb <- mb + bh / 2; ya <- yb + bh + between
  pa <- list(fill = "#E8F1FA", col = "#0072B2"); pb <- list(fill = "#FDEFE3", col = "#D55E00")
  a_txt <- c("NEON 2021 tiles\nat five sites,\nfield-mapped stems",
             "Fixed evaluation clips:\nnative density and\nfive thinned levels\n(hashed)",
             "Eleven detectors:\nthree zero-shot\nlearned, six classical,\ntwo RGB",
             "One-to-one matching\nto field stems\n(4 m, height gate);\n200 random\ntoroidal shifts",
             "Pooled F1,\nchance-corrected F1,\nplot bootstrap")
  b_txt <- c("New airborne\nLiDAR tile",
             "Measure\nfirst-return\ndensity",
             NA,
             "Detector chosen\nfor the band and\nthe compute budget\n(GPU or CPU only)",
             "Detections\n(tree tops)")
  bands <- c("≥ 8: QL1 or denser", "2–8: QL2 to QL1", "< 2: below QL2")
  # The band box: its heading, then three bands 0.19 in high, 0.245 in apart.
  band_head <- yb + bh / 2 - 0.125
  band_y <- yb + bh / 2 - 0.31 - (0:2) * 0.245; band_h <- 0.19; band_w <- bw - 0.14
  title_a <- c(x = 0.04, y = H - 0.1); title_b <- c(x = 0.04, y = yb + bh / 2 + 0.17)
  # The protocol's scores select the decision table (development region) and
  # check it (replication region): a dashed connector from the last box of (a)
  # to the detector box of (b), its label above its level part.
  yl <- yb + bh / 2 + 0.2
  conn_lab <- "Selected on the development region,\nchecked on the replication region"
  lab_at <- c(x = cx[5] - 0.1, y = yl + 0.05)
  library(grid, warn.conflicts = FALSE)
  render("2", W, H, function() {
    grid.newpage()
    pushViewport(viewport(xscale = c(0, W), yscale = c(0, H)))
    nat <- function(v) unit(v, "native")
    box <- function(x, y, w, h, p, lwd = 0.9)
      grid.roundrect(nat(x), nat(y), unit(w, "native"), unit(h, "native"), r = unit(0.06, "in"),
                     gp = gpar(fill = p$fill, col = p$col, lwd = lwd))
    label <- function(s, x, y, size = PT, face = 1, just = "centre", col = "black")
      grid.text(s, nat(x), nat(y), just = just, gp = gpar(fontsize = size, fontface = face,
                                                          lineheight = 1.0, col = col))
    arrow_h <- function(x0, x1, y, col = "grey25", lty = 1)
      grid.lines(nat(c(x0, x1)), nat(c(y, y)), arrow = arrow(length = unit(0.065, "in"), type = "closed"),
                 gp = gpar(col = col, fill = col, lwd = 1, lty = lty))
    # Layout check, in inches: every text inside its box with a margin, across
    # and down, and the titles, the boxes, the connector and its label clear of
    # each other. A text's ink box (x0, y0, x1, y1) follows grid's placement:
    # the box from the last baseline to the first line's ascent is justified,
    # and descenders hang below it.
    ink <- function(s, x, y, size = PT, face = 1, just = "centre") {
      pushViewport(viewport(gp = gpar(fontsize = size, fontface = face, lineheight = 1.0)))
      on.exit(popViewport())
      g <- textGrob(s)
      w <- convertWidth(grobWidth(g), "in", valueOnly = TRUE)
      h <- convertHeight(grobHeight(g), "in", valueOnly = TRUE)
      d <- convertHeight(grobDescent(g), "in", valueOnly = TRUE)
      hj <- c(left = 0, centre = 0.5, right = 1)[[if (just[1] %in% c("bottom", "top")) "centre" else just[1]]]
      v <- if (length(just) > 1) just[2] else if (just[1] %in% c("bottom", "top")) just[1] else "centre"
      vj <- c(bottom = 0, centre = 0.5, top = 1)[[v]]
      c(x - hj * w, y - vj * h - d, x + (1 - hj) * w, y + (1 - vj) * h)
    }
    rect_at <- function(x, y, w, h) c(x - w / 2, y - h / 2, x + w / 2, y + h / 2)
    inside <- function(r, b, m) all(r[1:2] >= b[1:2] + m, r[3:4] <= b[3:4] - m)
    apart <- function(r, s, m = 0.02) r[3] + m <= s[1] || s[3] + m <= r[1] || r[4] + m <= s[2] || s[4] + m <= r[2]
    issues <- character()
    boxes <- c(lapply(cx, rect_at, y = ya, w = bw, h = bh), lapply(cx, rect_at, y = yb, w = bw, h = bh))
    texts <- c(a_txt, b_txt)
    for (i in seq_along(boxes)) if (!is.na(texts[i]) && !inside(ink(texts[i], mean(boxes[[i]][c(1, 3)]),
                                                                    mean(boxes[[i]][c(2, 4)])), boxes[[i]], 0.05))
      issues <- c(issues, paste("text outside its box:", gsub("\n", " ", texts[i])))
    head_ink <- ink("Band (pulses/m²)", cx[3], band_head, face = 2)
    band_r <- lapply(band_y, rect_at, x = cx[3], w = band_w, h = band_h)
    if (!inside(head_ink, boxes[[8]], 0.04) || !apart(head_ink, band_r[[1]]))
      issues <- c(issues, "band heading outside its box or on the first band")
    for (k in 1:3) if (!inside(band_r[[k]], boxes[[8]], 0.04) ||
                       !inside(ink(bands[k], cx[3], band_y[k], size = PT - 0.5), band_r[[k]], 0.03))
      issues <- c(issues, paste("band outside the box, or its text outside the band:", bands[k]))
    conn <- list(c(cx[5], yl, cx[5], ya - bh / 2), c(cx[4], yl, cx[5], yl), c(cx[4], yb + bh / 2, cx[4], yl))
    lab_ink <- ink(conn_lab, lab_at[["x"]], lab_at[["y"]], size = PT - 0.5, just = c("right", "bottom"))
    ta <- ink("(a) Evaluation protocol", title_a[["x"]], title_a[["y"]], size = PT + 1, face = 2, just = "left")
    tb <- ink("(b) Density-routed pipeline", title_b[["x"]], title_b[["y"]], size = PT + 1, face = 2, just = "left")
    for (r in list(ta, tb, lab_ink)) {
      if (!all(vapply(boxes, apart, TRUE, r = r))) issues <- c(issues, "a title or the connector's label touches a box")
      if (!all(vapply(conn, apart, TRUE, r = r))) issues <- c(issues, "the connector crosses a title or its label")
    }
    if (!apart(tb, lab_ink)) issues <- c(issues, "the connector's label touches the title of (b)")
    if (ta[4] > H || min(vapply(boxes, `[`, 0, 2)) < 0) issues <- c(issues, "the schematic leaves the figure")
    if (length(issues)) warning("schematic layout: ", paste(unique(issues), collapse = " | "))
    label("(a) Evaluation protocol", title_a[["x"]], title_a[["y"]], size = PT + 1, face = 2, just = "left")
    label("(b) Density-routed pipeline", title_b[["x"]], title_b[["y"]], size = PT + 1, face = 2, just = "left")
    for (i in 1:5) {
      box(cx[i], ya, bw, bh, pa)
      label(a_txt[i], cx[i], ya)
      if (i < 5) arrow_h(cx[i] + bw / 2, cx[i + 1] - bw / 2, ya)
    }
    for (i in 1:5) {
      box(cx[i], yb, bw, bh, pb)
      if (i == 3) {
        label("Band (pulses/m²)", cx[i], band_head, face = 2)
        for (k in 1:3) {
          grid.rect(nat(cx[i]), nat(band_y[k]), unit(band_w, "native"), unit(band_h, "native"),
                    gp = gpar(fill = "white", col = pb$col, lwd = 0.6))
          label(bands[k], cx[i], band_y[k], size = PT - 0.5)
        }
      } else {
        label(b_txt[i], cx[i], yb)
      }
      if (i < 5) arrow_h(cx[i] + bw / 2, cx[i + 1] - bw / 2, yb)
    }
    grid.lines(nat(c(cx[5], cx[5], cx[4], cx[4])), nat(c(ya - bh / 2, yl, yl, yb + bh / 2)),
               arrow = arrow(length = unit(0.065, "in"), type = "closed"),
               gp = gpar(col = "grey25", fill = "grey25", lwd = 1, lty = 2))
    label(conn_lab, lab_at[["x"]], lab_at[["y"]], size = PT - 0.5, just = c("right", "bottom"), col = "grey15")
    popViewport()
  })
}

## ---- 3: F1, recall, precision against pulse density --------------------------------
fig3 <- function() {
  x <- do.call(rbind, lapply(c("F1", "recall", "precision"), function(m) ladder_rows("nominal box", metric = m)))
  # Chance-corrected F1, (F1 - null) / (1 - null) at the 4 m radius, from the null
  # re-scores of the main density series and of the QL2 level.
  nd <- read_null("null_delta.csv")
  nd <- nd[nd$scope == "five sites" & nd$stratum == "all" & nd$metric == "F1_scaled" &
             nd$detector %in% LADDER & nd$rung %in% names(pulses), ]
  cf <- data.frame(table = "nominal box", scope = "five sites", detector = nd$detector, rung = nd$rung,
                   metric = "F1_corrected", estimate = nd$estimate, lower = nd$lower, upper = nd$upper,
                   pulses = unname(pulses[nd$rung]), stringsAsFactors = FALSE)
  x <- rbind(x[, names(cf)], cf)
  nsf <- file.path(d, "sensitivity", "baseline_smoothing_pooled.csv")
  ns <- if (file.exists(nsf)) {
    b <- read.csv(nsf, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    b <- b[b$detector == "chm_vwf_unsmoothed" & b$rung %in% names(pulses), ]
    data.frame(detector = "chm_vwf_unsmoothed", rung = b$rung, pulses = unname(pulses[b$rung]), metric = b$metric,
               estimate = b$estimate, lower = b$lower, upper = b$upper, stringsAsFactors = FALSE)
  } else NULL
  save_data("3", rbind(x[, c("detector", "rung", "pulses", "metric", "estimate", "lower", "upper")], ns))
  mains <- c(F1 = "(a) F1", recall = "(b) Recall", precision = "(c) Precision",
             F1_corrected = "(d) F1 corrected for chance (4 m)")
  render("3", TEXT_W, 4.4, function() {
    layout(matrix(c(1, 2, 5, 3, 4, 5), 2, byrow = TRUE), widths = c(2.9, 2.9, 1.36))
    fig_par(mar = c(2.8, 2.9, 1.5, 0.5))
    for (m in names(mains)) {
      y <- x[x$metric == m, ]
      # Headroom above the intervals keeps the QL1 and QL2 labels clear of the data.
      plot(NA, xlim = rev(range(y$pulses)) * c(1.1, 0.9), ylim = c(0, 1.1 * max(y$upper, na.rm = TRUE)),
           log = "x", xaxt = "n", xlab = "First-return pulses/m²",
           ylab = if (m == "F1_corrected") "Corrected F1" else c(F1 = "F1", recall = "Recall", precision = "Precision")[[m]],
           main = mains[[m]])
      dens_axis(); ql_lines()
      for (a in LADDER) {
        z <- y[y$detector == a, ]; z <- z[order(-z$pulses), ]
        ci_lines(z$pulses, z$estimate, z$lower, z$upper, COL[a])
        lines(z$pulses, z$estimate, col = COL[a], type = "o", pch = PCH[a], cex = 0.8)
      }
      # The baseline without its sub-8 pulses/m² smoothing (a sensitivity run,
      # baseline_smoothing_sensitivity.R), dashed, where that output exists.
      if (!is.null(ns) && m != "F1_corrected") {
        z <- ns[ns$metric == m, ]; z <- z[order(-z$pulses), ]
        lines(z$pulses, z$estimate, col = COL["chm_vwf"], lty = 2, type = "o", pch = 1, cex = 0.8)
      }
    }
    legend_panel(legend = c(ARMS[LADDER], if (!is.null(ns)) "CHM-VWF, no smoothing"),
                 col = c(COL[LADDER], if (!is.null(ns)) COL["chm_vwf"]),
                 pch = c(PCH[LADDER], if (!is.null(ns)) 1), lty = c(rep(1, length(LADDER)), if (!is.null(ns)) 2),
                 y.intersp = 1.25)
  })
}

## ---- 4: rank across the density series ------------------------------------------------
fig4 <- function() {
  x <- ladder_rows("nominal box")
  x <- x[x$detector %in% names(which(table(x$detector) == length(unique(x$rung)))), ]
  x$rank <- ave(-x$estimate, x$rung, FUN = function(v) rank(v, ties.method = "min"))
  rs <- read.csv(file.path(MT, "master_rank_stability.csv"), stringsAsFactors = FALSE,
                 colClasses = c(from = "character", to = "character"))
  rs <- rs[rs$table == "nominal box", ]
  # The two detectors that move most below the QL2 floor, left out together.
  lo <- read.csv(file.path(MT, "master_rank_leave_out.csv"), stringsAsFactors = FALSE,
                 colClasses = c(from = "character", to = "character"))
  lo <- lo[lo$table == "nominal box" & lo$left_out == "segmentanytree+ams3d", ]
  save_data("4", rbind(data.frame(kind = "rank", detector = x$detector, rung = x$rung, pulses = x$pulses,
                                  value = x$rank, lower = NA, upper = NA),
                       data.frame(kind = "spearman", detector = NA, rung = rs$to, pulses = unname(pulses[rs$to]),
                                  value = rs$estimate, lower = rs$lower, upper = rs$upper),
                       data.frame(kind = "spearman_without_segmentanytree_ams3d", detector = NA, rung = lo$to,
                                  pulses = unname(pulses[lo$to]), value = lo$estimate, lower = lo$lower,
                                  upper = lo$upper)))
  rs$pulses <- unname(pulses[rs$to])
  lo$pulses <- unname(pulses[lo$to]) * 0.92        # offset so the intervals do not overlap
  render("4", TEXT_W, 3.9, function() {
    layout(matrix(c(1, 2, 3, 3), 2, byrow = TRUE), widths = c(2, 1), heights = c(5, 0.75))
    fig_par(mar = c(2.8, 2.9, 1.5, 0.6))
    plot(NA, xlim = rev(range(x$pulses)) * c(1.1, 0.9), ylim = c(max(x$rank) + 0.5, 0.5), log = "x", xaxt = "n",
         xlab = "First-return pulses/m²", ylab = "Rank by F1 (1 = best)",
         main = "(a) Rank across the density series")
    dens_axis(); ql_lines()
    for (a in unique(x$detector)) {
      z <- x[x$detector == a, ]
      lines(z$pulses, z$rank, col = COL[a], type = "o", pch = PCH[a], lwd = 1.5)
    }
    # The density axis of (a), labelled at the levels; the native level lies
    # outside this panel, which plots no point there.
    plot(rs$pulses, rs$estimate, log = "x", xlim = rev(range(rs$pulses)) * c(1.1, 0.85), ylim = c(-1, 1),
         xaxt = "n", pch = 16, xlab = "First-return pulses/m²", ylab = "Spearman ρ with native rank",
         main = "(b) Rank stability")
    dens_axis()
    segments(rs$pulses, rs$lower, rs$pulses, rs$upper); abline(h = 0, lty = 2)
    points(lo$pulses, lo$estimate, pch = 1, col = "grey35")
    segments(lo$pulses, lo$lower, lo$pulses, lo$upper, col = "grey35", lty = 1)
    legend("bottomleft", legend = c("All eight detectors", "Without SegmentAnyTree and AMS3D"),
           pch = c(16, 1), col = c("black", "grey35"), bty = "n", cex = LEG_CEX)
    # Neither panel has a free corner for the detectors; their legend runs below both.
    legend_panel(legend = ARMS[unique(x$detector)], col = COL[unique(x$detector)],
                 pch = PCH[unique(x$detector)], lty = 1, ncol = 4)
  })
}

## ---- 5: overstory and understory recall ---------------------------------------------
fig5 <- function() {
  s <- read_mt("master_strata.csv")
  s <- s[s$table == "nominal box" & s$scope == "five sites" & s$stratum %in% c("overstory", "understory") &
           s$detector %in% LADDER & s$rung %in% names(pulses), ]
  s$pulses <- unname(pulses[s$rung])
  save_data("5", s[, c("detector", "rung", "pulses", "stratum", "n_ref", "estimate", "lower", "upper")])
  render("5", TEXT_W, 2.95, function() {
    layout(matrix(1:3, 1), widths = c(2.9, 2.9, 1.36))
    fig_par(mar = c(2.8, 2.9, 1.5, 0.5))
    for (k in c("overstory", "understory")) {
      y <- s[s$stratum == k, ]
      plot(NA, xlim = rev(range(y$pulses)) * c(1.1, 0.9), ylim = c(0, 1), log = "x", xaxt = "n",
           xlab = "First-return pulses/m²", ylab = "Recall",
           main = sprintf("(%s) %s recall (%s stems)", c(overstory = "a", understory = "b")[[k]],
                          tools::toTitleCase(k), format(y$n_ref[1], big.mark = ",")))
      dens_axis(); ql_lines()
      for (a in LADDER) {
        z <- y[y$detector == a, ]; z <- z[order(-z$pulses), ]
        ci_lines(z$pulses, z$estimate, z$lower, z$upper, COL[a])
        lines(z$pulses, z$estimate, col = COL[a], type = "o", pch = PCH[a], cex = 0.8)
      }
    }
    legend_panel(legend = ARMS[LADDER], col = COL[LADDER], pch = PCH[LADDER], lty = 1, y.intersp = 1.25)
  })
}

## ---- 6: native sparse flights ------------------------------------------------------------
fig6 <- function() {
  f <- file.path(SPARSE, "sparse_vs_2021.csv")
  if (!file.exists(f)) { message("no sparse report at ", SPARSE); return(invisible()) }
  x <- read.csv(f, stringsAsFactors = FALSE)
  x <- x[x$stratum == "shared" & x$site == "D17", ]
  x$cell <- factor(paste(x$side, x$rung), c("2021 4", "sparse native", "2021 8", "2021 native"))
  arms <- intersect(c("chm_vwf", "multichm", "forestformer3d", "treeisonet", "segmentanytree"), x$arm)
  keep <- c("arm", "cell", "frdens_median", "recall", "rec_overstory", "rec_understory", "F1")
  save_data("6", x[x$arm %in% arms, keep])
  render("6", TEXT_W, 2.9, function() {
    par(mfrow = c(1, 3))
    fig_par(mar = c(4.7, 2.9, 1.5, 0.5))
    for (m in c("recall", "rec_overstory", "rec_understory")) {
      plot(NA, xlim = c(0.5, 4.5), ylim = c(0, 1), xaxt = "n", xlab = "", ylab = "Recall",
           main = c(recall = "(a) All stems", rec_overstory = "(b) Overstory",
                    rec_understory = "(c) Understory")[m])
      # Cloud and its first-return pulse density: the 2021 cloud thinned to
      # about 2.9 and 5.4 pulses/m² on these plots, the natively sparse flights
      # (3.9 to 5.0) and the 2021 cloud at native density.
      axis(1, at = 1:4, labels = c("2021,\n2.9", "sparse\nflight,\n3.9–5.0", "2021,\n5.4", "2021,\nnative"),
           padj = 0.5, gap.axis = 0, mgp = c(1.8, 0.35, 0))
      mtext("Cloud, first-return pulses/m²", side = 1, line = 3.6, cex = 1)
      for (a in arms) {
        z <- x[x$arm == a, ]; z <- z[order(z$cell), ]
        lines(as.integer(z$cell), z[[m]], type = "o", col = COL[a], pch = PCH[a])
      }
      # The data under the top-left corner stay below 0.6, so the legend
      # takes that free band.
      if (m == "recall") legend_arms(arms, "topleft")
    }
  })
}

## ---- 7: detections on one plot --------------------------------------------------------------
# CHM-VWF, ForestFormer3D and SegmentAnyTree on one plot at native density, at
# the QL2 level (frozen in its own root) and at the sparsest level, re-scored
# from their persisted detections with the loaders and matcher of
# paper_sensitivity.R (greedy one-to-one, 4 m, height gate); every panel's
# counts must equal that cell's baseline row of the null re-scores. The plot
# is the one whose nine per-cell F1 values are closest (Euclidean distance) to
# the five-site pooled F1 of the same detector and level, among plots with at
# least 10 reference stems and a core detection in every panel: it shows the
# typical pattern, SegmentAnyTree's collapse at the sparsest level included,
# rather than an extreme one. EXAMPLE_PLOT= draws another plot. The background
# is the canopy height model of each panel's normalised clip (a first-return
# TIN at 0.5 m; one grey scale for all panels, capped at the 99.5th
# percentile), repeated by nearest neighbour so the embedded image has at
# least 600 dpi at its printed size; the key, in a column at the right of the
# panels with the legend, is one image of the same grey scale at the same
# resolution.
EX_ARMS <- c("chm_vwf", "forestformer3d", "segmentanytree")
EX_LEVELS <- c(native = "native", ql2 = "3.2", sparsest = "1")
EX_LEVEL_NAME <- c(native = "Native density", ql2 = "QL2 level", sparsest = "Sparsest level")
EX_TOL <- 4; EX_TZ <- 8; EX_MIN_STEMS <- 10
EX_CHM_RES <- 0.5
EX_DPI <- 600
EX_COL <- c(matched = "#56B4E9", error = "#E69F00")

# Field stems are circles and detections triangles. Matched ones are filled
# (blue); missed stems and unmatched detections in the core are open (an orange
# outline cased in black), so the two read apart in greyscale as well as in
# colour; unmatched detections in the margin outside the core, which are not
# scored, are small and white.
ex_points <- function(x, y, kind, status) {
  pch <- c(stem = 21L, detection = 24L)[[kind]]; cex <- c(stem = 0.95, detection = 0.75)[[kind]]
  open <- c(stem = 1L, detection = 2L)[[kind]]          # the same circle and triangle, unfilled
  f <- status == "matched"; o <- status %in% c("missed", "false_positive"); m <- status == "outside_core"
  points(x[m], y[m], pch = pch, cex = 0.6, lwd = 0.6, col = "black", bg = "white")
  points(x[o], y[o], pch = open, cex = cex, lwd = 1.9, col = "black")
  points(x[o], y[o], pch = open, cex = cex, lwd = 1.0, col = EX_COL[["error"]])
  points(x[f], y[f], pch = pch, cex = cex, lwd = 0.6, col = "black", bg = EX_COL[["matched"]])
}

# The scoring code of paper_sensitivity.R. io_bridge.R finds its own
# dependency from the working directory and redefines .find, so the libraries
# are read from the repository root and the bootstrap's .find is put back.
load_scoring <- function() {
  options(lidR.progress = FALSE)
  if (exists("census_cell_detections", mode = "function")) return(invisible())
  find0 <- .find
  wd <- setwd(.ROOT); on.exit(setwd(wd), add = TRUE)
  for (f in c("sweep_lib.R", "io_bridge.R", "census_support_lib.R", "coverage_lib.R")) {
    source(find0(f))
    assign(".find", find0, envir = globalenv())
  }
}

# Plots ranked by the distance of their nine per-cell F1 values to the pooled
# F1 of each detector and level (null_cells.csv, baseline rows).
example_ranking <- function(cells) {
  f1 <- function(tp, nref, tpc, ndet) {
    r <- tp / nref; p <- ifelse(ndet > 0, tpc / ndet, NA_real_)
    ifelse(r + p > 0, 2 * r * p / (r + p), 0)
  }
  pooled <- aggregate(cbind(TP, n_ref, tp_core, n_det) ~ detector + rung, cells, sum)
  pooled$F1 <- f1(pooled$TP, pooled$n_ref, pooled$tp_core, pooled$n_det)
  cells$F1 <- f1(cells$TP, cells$n_ref, cells$tp_core, cells$n_det)
  cells$F1_pooled <- pooled$F1[match(paste(cells$detector, cells$rung), paste(pooled$detector, pooled$rung))]
  ok <- tapply(cells$n_det > 0 & cells$n_ref >= EX_MIN_STEMS, cells$plot, all) &
    tapply(cells$detector, cells$plot, length) == length(EX_ARMS) * length(EX_LEVELS)
  dist <- tapply((cells$F1 - cells$F1_pooled)^2, cells$plot, function(v) sqrt(sum(v)))
  sort(dist[names(ok)[ok]])
}

# Reading LAZ prints a progress line even with lidR.progress off, and the
# learned arms' instance clouds carry no return numbers, which lidR warns
# about; both are kept out of the log.
quietly <- function(expr) {
  val <- NULL
  utils::capture.output(val <- suppressWarnings(expr))
  val
}

example_panels <- function(site, pid, cells) {
  jobs <- list(native = list(job = d, root = ROOT), ql2 = list(job = QL2_JOB, root = QL2_ROOT),
               sparsest = list(job = d, root = ROOT))
  out <- list()
  for (lv in names(EX_LEVELS)) {
    j <- jobs[[lv]]; rl <- EX_LEVELS[[lv]]
    rv <- if (rl == "native") NA_real_ else as.numeric(rl)
    nd <- file.path(j$job, "neon", site)
    gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
    fz <- frozen_scope(j$job, site, list(FROZEN_ROOT = j$root), gt)
    if (!pid %in% fz$plots) stop(pid, " is not in the population of ", j$root)
    pp <- frozen_population(fz$root, site)
    epsg <- pp$epsg[pp$plotID == pid]
    ci <- pc[pc$plotID == pid, ][1, ]
    cx <- ci$easting; cy <- ci$northing; ph <- plot_half(ci$plotType)
    stems <- fz$gt[fz$gt$plotID == pid & abs(fz$gt$E - cx) <= ph & abs(fz$gt$N - cy) <= ph, , drop = FALSE]
    cell <- frozen_clip(NULL, site, pid, rv, cx, cy, ph, fz$root)
    if (is.null(cell)) stop("no frozen cell for ", pid, " at ", rl)
    las <- quietly(lidR::readLAS(cell$normalized))
    chm <- suppressWarnings(lidR::rasterize_canopy(las, res = EX_CHM_RES, algorithm = lidR::dsmtin()))
    R <- ph + EX_TOL
    chm <- terra::crop(chm, terra::ext(cx - R, cx + R, cy - R, cy + R), snap = "out")
    for (arm in EX_ARMS) {
      det <- quietly(census_cell_detections(nd, arm, site, pid, rv, fz$root, cell))
      if (is.null(det)) stop("no persisted detections for ", arm, " ", pid, " ", rl)
      sc <- score_plot(stems, det, tol_xy = EX_TOL, core_cx = cx, core_cy = cy, core_half = ph,
                       method = "greedy", tol_z_up = EX_TZ)
      # The same match, kept per stem and detection for drawing (score_plot's
      # region and matcher call).
      reg <- abs(det$x - cx) <= R & abs(det$y - cy) <= R
      dr <- det[reg, , drop = FALSE]
      core <- abs(dr$x - cx) <= ph & abs(dr$y - cy) <= ph
      m <- greedy_match(stems$E, stems$N, dr$x, dr$y, EX_TOL, az = stems$height, bz = dr$z,
                        tol_z_up = EX_TZ)
      hit <- seq_len(nrow(dr)) %in% m[m > 0]
      cnt <- c(n_ref = nrow(stems), n_det = sum(core), TP = sum(m > 0), tp_core = sum(core[m[m > 0]]))
      own <- c(n_ref = sc$n_ref, n_det = sc$n_det, TP = sc$TP,
               tp_core = if (sc$n_det > 0) round(sc$precision * sc$n_det) else 0)
      ref <- cells[cells$plot == pid & cells$rung == rl & cells$detector == arm, ]
      if (nrow(ref) != 1L) stop("no baseline row for ", arm, " ", pid, " ", rl)
      base <- as.numeric(unlist(ref[, c("n_ref", "n_det", "TP", "tp_core")]))
      if (any(as.numeric(cnt) != as.numeric(own)) || any(as.numeric(cnt) != base))
        stop(sprintf("%s %s %s: counts %s differ from score_plot (%s) or the null baseline (%s)",
                     arm, pid, rl, paste(cnt, collapse = "/"), paste(own, collapse = "/"),
                     paste(unlist(ref[, c("n_ref", "n_det", "TP", "tp_core")]), collapse = "/")))
      out[[paste(arm, lv)]] <- list(
        arm = arm, level = lv, rung = rl, frdens = cell$frdens, cx = cx, cy = cy, ph = ph, epsg = epsg,
        chm = chm, cnt = cnt, recall = cnt[["TP"]] / cnt[["n_ref"]],
        precision = if (cnt[["n_det"]] > 0) cnt[["tp_core"]] / cnt[["n_det"]] else NA_real_,
        stems = data.frame(x = stems$E - cx, y = stems$N - cy, height = stems$height,
                           status = ifelse(m > 0, "matched", "missed")),
        dets = data.frame(x = dr$x - cx, y = dr$y - cy, height = dr$z,
                          status = ifelse(hit, "matched", ifelse(core, "false_positive", "outside_core"))),
        pairs = data.frame(x0 = stems$E[m > 0] - cx, y0 = stems$N[m > 0] - cy,
                           x1 = dr$x[m[m > 0]] - cx, y1 = dr$y[m[m > 0]] - cy))
    }
  }
  out
}

fig7 <- function() {
  load_scoring()
  cells <- read_null("null_cells.csv")
  cells <- cells[cells$variant == "baseline" & cells$detector %in% EX_ARMS & cells$rung %in% EX_LEVELS, ]
  rk <- example_ranking(cells)
  pid <- if (is.null(A$EXAMPLE_PLOT)) names(rk)[1] else A$EXAMPLE_PLOT
  site <- unique(cells$site[cells$plot == pid])
  if (length(site) != 1L) stop("unknown example plot: ", pid)
  cat(sprintf("figure 7: %s (distance to the pooled F1 %.3f; next %s)\n", pid, rk[pid],
              paste(sprintf("%s %.3f", names(rk)[2:4], rk[2:4]), collapse = ", ")))
  P <- example_panels(site, pid, cells)
  key <- function(p) data.frame(site = site, plot = pid, detector = p$arm, level = p$level, rung = p$rung,
                                stringsAsFactors = FALSE)
  save_data("7", do.call(rbind, lapply(P, function(p) {
    pan <- cbind(key(p), row_type = "panel", x = NA, y = NA, height = NA, status = NA,
                 frdens = p$frdens, n_ref = p$cnt[["n_ref"]], n_det = p$cnt[["n_det"]], TP = p$cnt[["TP"]],
                 tp_core = p$cnt[["tp_core"]], recall = p$recall, precision = p$precision,
                 centre_easting = p$cx, centre_northing = p$cy, epsg = p$epsg,
                 distance_to_pooled_F1 = unname(rk[pid]))
    pts <- rbind(cbind(row_type = "stem", p$stems), cbind(row_type = "detection", p$dets))
    pts <- cbind(key(p)[rep(1, nrow(pts)), ], pts, frdens = NA, n_ref = NA, n_det = NA, TP = NA,
                 tp_core = NA, recall = NA, precision = NA, centre_easting = NA, centre_northing = NA,
                 epsg = NA, distance_to_pooled_F1 = NA)
    rbind(pan, pts[, names(pan)])
  })))
  # One grey scale for all panels, capped at the 99.5th percentile of the
  # canopy heights (rounded up to 5 m); the few taller cells show as the cap.
  zall <- unlist(lapply(P, function(p) terra::values(p$chm)))
  zmax <- 5 * ceiling(stats::quantile(zall, 0.995, na.rm = TRUE) / 5)
  capped <- max(zall, na.rm = TRUE) > zmax
  pal <- grey(seq(0.18, 0.97, length.out = 256))
  R <- P[[1]]$ph + EX_TOL
  # The panels are square, 1.576 in, the size they had when the legend ran
  # under them at 0.72 of the text width. The legend, the scale bar and the
  # canopy-height key stand in a column at the right of the panels, so the
  # figure takes the full text width and is 0.76 in less tall.
  ln <- PT * 1.2 / 72
  mar <- c(1.25, 0.25, 0.25, 0.25)
  side <- (0.72 * TEXT_W - 1.7 * ln) / 3 - (mar[2] + mar[4]) * ln
  W <- TEXT_W; oma <- c(0, 1.5, 1.5, 0)
  oma[4] <- (W - 3 * (side + (mar[2] + mar[4]) * ln)) / ln - oma[2]
  H <- 3 * (side + (mar[1] + mar[3]) * ln) + (oma[1] + oma[3]) * ln
  draw_chm <- function(r) {
    v <- terra::as.matrix(r, wide = TRUE)
    v[!is.finite(v)] <- 0
    i <- 1 + round(pmin(pmax(v, 0), zmax) / zmax * (length(pal) - 1))
    img <- matrix(pal[i], nrow(v))
    k <- max(1L, as.integer(ceiling(EX_DPI * par("pin")[1] / (2 * R / EX_CHM_RES))))
    img <- img[rep(seq_len(nrow(img)), each = k), rep(seq_len(ncol(img)), each = k), drop = FALSE]
    e <- as.vector(terra::ext(r))
    rasterImage(as.raster(img), e[["xmin"]] - P[[1]]$cx, e[["ymin"]] - P[[1]]$cy,
                e[["xmax"]] - P[[1]]$cx, e[["ymax"]] - P[[1]]$cy, interpolate = FALSE)
  }
  render("7", W, H, function() {
    par(mfrow = c(3, 3), oma = oma)
    fig_par(mar = mar, xpd = NA)
    for (arm in EX_ARMS) for (lv in names(EX_LEVELS)) {
      p <- P[[paste(arm, lv)]]
      plot.new()
      plot.window(xlim = c(-R, R), ylim = c(-R, R), xaxs = "i", yaxs = "i", asp = 1)
      par(xpd = FALSE)                  # the canopy image is clipped to the panel
      draw_chm(p$chm)
      par(xpd = NA)
      rect(-p$ph, -p$ph, p$ph, p$ph, border = "white", lty = 2, lwd = 0.8)
      if (nrow(p$pairs)) {
        segments(p$pairs$x0, p$pairs$y0, p$pairs$x1, p$pairs$y1, col = "white", lwd = 2.2)
        segments(p$pairs$x0, p$pairs$y0, p$pairs$x1, p$pairs$y1, col = "black", lwd = 0.8)
      }
      ex_points(p$stems$x, p$stems$y, "stem", p$stems$status)
      ex_points(p$dets$x, p$dets$y, "detection", p$dets$status)
      box(lwd = 0.6)
      mtext(sprintf("Recall %.2f, precision %.2f", p$recall, p$precision), side = 1, line = 0.15,
            cex = LEG_CEX)
      if (lv == "native") mtext(ARMS[[arm]], side = 2, line = 0.35, font = 2)
      if (arm == EX_ARMS[1]) mtext(sprintf("%s, %.1f pulses/m²", EX_LEVEL_NAME[[lv]], p$frdens),
                                   side = 3, line = 0.3, font = 2)
    }
    # The column at the right, in inches: the legend beside the first row of
    # panels, its symbols drawn as in the panels, and the canopy-height key
    # beside the other two.
    par(fig = c(0, 1, 0, 1), oma = c(0, 0, 0, 0), mar = c(0, 0, 0, 0), new = TRUE)
    plot.new(); plot.window(c(0, W), c(0, H), xaxs = "i", yaxs = "i")
    xl <- W - oma[4] * ln                         # the column's left edge
    xs <- xl + 0.12; xt <- xs + 0.15              # symbols, texts
    top <- H - (oma[3] + mar[3]) * ln             # the top of the first row of panels
    row <- 1.2 * LEG_CEX * ln; grp <- 0.06        # rows, and the space between groups
    yk <- top - row / 2 - c(0:2 * row, 3:5 * row + grp, 6:7 * row + 2 * grp)
    t1 <- c("Field stem, matched", "Field stem, missed", "Match (4 m, height gate)")
    t2 <- c("Detection, matched", "Detection in the core, unmatched", "Detection outside the core, unmatched")
    core_lab <- sprintf("Plot core, %g m × %g m", 2 * P[[1]]$ph, 2 * P[[1]]$ph)
    if (xt + max(strwidth(c(t1, t2, core_lab), cex = LEG_CEX)) > W - 0.02)
      warning("figure 7 legend wider than its column")
    ex_points(rep(xs, 2), yk[1:2], "stem", c("matched", "missed"))
    segments(xs - 0.07, yk[3], xs + 0.07, yk[3], col = "black", lwd = 0.8)
    ex_points(rep(xs, 3), yk[4:6], "detection", c("matched", "false_positive", "outside_core"))
    rect(xs - 0.1, yk[7] - 0.045, xs + 0.1, yk[7] + 0.045, border = "black", lty = 2, lwd = 0.8)
    text(xt, yk[1:7], c(t1, t2, core_lab), adj = c(0, 0.5), cex = LEG_CEX)
    bar <- 10 * side / (2 * R)        # 10 m at the panels' scale
    segments(xs - 0.1, yk[8], xs - 0.1 + bar, yk[8], lwd = 1.5, lend = 1)
    segments(c(xs - 0.1, xs - 0.1 + bar), yk[8] - 0.025, c(xs - 0.1, xs - 0.1 + bar), yk[8] + 0.025, lwd = 0.8)
    text(xs - 0.1 + bar + 0.05, yk[8], "10 m", adj = c(0, 0.5), cex = LEG_CEX)
    # Canopy-height key: its title at the top of the second row of panels,
    # then one image of the grey scale, highest at the top (adjacent
    # rectangles would show seams in PDF viewers), each value repeated by
    # nearest neighbour to EX_DPI as in the panels, down to the bottom of the
    # third row; its ticks and labels on the right.
    kb <- (oma[1] + mar[1]) * ln
    kt <- top - side - (mar[1] + mar[3]) * ln - 0.2
    x0 <- xs - 0.07; x1 <- xs + 0.07
    text(x0, kt + 0.14, "Canopy height (m)", adj = c(0, 0.5), cex = LEG_CEX)
    kx <- as.integer(ceiling(EX_DPI * (x1 - x0))); ky <- as.integer(ceiling(EX_DPI * (kt - kb) / length(pal)))
    rasterImage(as.raster(matrix(rep(rev(pal), each = ky), nrow = ky * length(pal), ncol = kx)), x0, kb, x1, kt,
                interpolate = FALSE)
    rect(x0, kb, x1, kt, border = "black", lwd = 0.5)
    tk <- seq(0, zmax, by = if (zmax > 30) 10 else 5)
    tl <- as.character(tk); if (capped) tl[length(tl)] <- paste("\u2265", tl[length(tl)])
    ty <- kb + tk / zmax * (kt - kb)
    segments(x1, ty, x1 + 0.035, ty, lwd = 0.5)
    text(x1 + 0.07, ty, tl, adj = c(0, 0.5), cex = LEG_CEX)
  })
}

## ---- S1: nominal, censused and credited precision -------------------------------------
figs1 <- function() {
  g <- function(tab) {
    z <- long[long$table == tab & long$scope == "five sites" & long$rung == "native" & long$metric == "precision", ]
    z[match(names(ARMS), z$detector), c("detector", "estimate", "lower", "upper")]
  }
  nom <- g("nominal box"); cen <- g("census, nearest census (headline)")
  cg <- do.call(rbind, lapply(SITES, function(s) {
    f <- file.path(d, "neon", s, "coverage_gap.csv")
    if (file.exists(f)) read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character")) }))
  # The coverage-gap study scores each detector at its selected configuration
  # (CHM-VWF also down its native density series): the credited bracket runs
  # from raw to credited precision on those cells, CHM-VWF's at native density.
  cg <- cg[cg$detector != "chm_vwf" &
             (cg$detector != "chm_vwf_ladder" | cg$rung == "native"), ]
  cg$detector[cg$detector == "chm_vwf_ladder"] <- "chm_vwf"
  cg$tp_core <- ifelse(cg$n_det > 0, round(cg$precision * cg$n_det), 0)
  cred <- aggregate(cbind(tp_core, fp_credited, n_det) ~ detector, cg, sum)
  cred$raw <- cred$tp_core / cred$n_det
  # Credited false positives leave the precision denominator, floored at the
  # pooled true positives (pool() in model_bench_lib.R; coverage-gap study).
  cred$credited <- cred$tp_core / pmax(cred$n_det - cred$fp_credited, cred$tp_core)
  # SAM2Point is not analysed in the paper and has no credited value.
  arms <- setdiff(names(ARMS), "sam2point")
  i <- match(arms, cred$detector)
  out <- data.frame(detector = arms, nominal = nom$estimate[match(arms, nom$detector)],
                    nominal_lo = nom$lower[match(arms, nom$detector)],
                    nominal_hi = nom$upper[match(arms, nom$detector)],
                    censused = cen$estimate[match(arms, cen$detector)],
                    censused_lo = cen$lower[match(arms, cen$detector)],
                    censused_hi = cen$upper[match(arms, cen$detector)],
                    selected_raw = cred$raw[i], selected_credited = cred$credited[i])
  save_data("s1", out)
  render("s1", SUPP_W, 4.2, function() {
    fig_par(mar = c(2.9, 7.2, 1.5, 0.6))
    o <- order(out$nominal); y <- seq_along(o)
    plot(NA, xlim = c(0, 1), ylim = c(0.5, length(o) + 0.5), yaxt = "n", ylab = "",
         xlab = "Precision", main = "Precision by reference")
    axis(2, at = y, labels = ARMS[out$detector[o]], las = 1, cex.axis = 1)
    segments(out$nominal_lo[o], y - 0.12, out$nominal_hi[o], y - 0.12, col = "grey40")
    points(out$nominal[o], y - 0.12, pch = 16, col = "grey20")
    segments(out$censused_lo[o], y + 0.12, out$censused_hi[o], y + 0.12, col = "#0072B2")
    points(out$censused[o], y + 0.12, pch = 17, col = "#0072B2")
    arrows(out$selected_raw[o], y, out$selected_credited[o], y, length = 0.05, col = "#D55E00")
    legend("topleft", legend = c("Nominal plot core, native", "Censused subplots, native",
                                 "Raw to credited, best density per site"),
           pch = c(16, 17, NA), lty = c(NA, NA, 1), col = c("grey20", "#0072B2", "#D55E00"),
           bty = "n", cex = LEG_CEX)
  })
}

## ---- S2: sensitivity -------------------------------------------------------------------------
figs2 <- function() {
  sd <- file.path(d, "sensitivity")
  mp <- read.csv(file.path(sd, "matcher_pooled.csv"), stringsAsFactors = FALSE)
  mp <- mp[mp$scope == "five sites" & mp$rung == "native" & mp$metric == "F1", ]
  md <- read.csv(file.path(sd, "matcher_delta.csv"), stringsAsFactors = FALSE)
  md <- md[md$scope == "five sites" & md$rung == "native" & md$metric == "F1" &
             md$variant %in% c("scaled", "optimal", "optimal_scaled", "soft3d"), ]
  jb <- read.csv(file.path(sd, "jitter_bands.csv"), stringsAsFactors = FALSE)
  jb <- jb[jb$scope == "five sites" & jb$rung == "native", ]
  nb <- long[long$table == "nominal box" & long$scope == "five sites" & long$rung == "native" &
               long$metric == "F1", ]
  grid <- mp[grepl("^grid_tx[0-9]+_tz8$", mp$variant), ]
  grid$radius <- as.numeric(sub("grid_tx([0-9]+)_tz8", "\\1", grid$variant))
  # Observed and null F1 per detector at native density, at the 4 m and 2 m radii.
  np <- rbind(cbind(radius = 4, read_null("null_pooled.csv")), cbind(radius = 2, read_null("null_tol2_pooled.csv")))
  np <- np[np$scope == "five sites" & np$rung == "native" & np$metric == "F1" &
             np$variant %in% c("baseline", "null") & np$detector != "sam2point", ]
  save_data("s2", rbind(
    data.frame(panel = "radius", detector = grid$detector, key = grid$radius, value = grid$estimate,
               lower = grid$lower, upper = grid$upper),
    data.frame(panel = "chance", detector = np$detector, key = paste(np$variant, np$radius, "m"),
               value = np$estimate, lower = np$lower, upper = np$upper),
    data.frame(panel = "matcher", detector = md$detector, key = md$variant, value = md$estimate,
               lower = md$lower, upper = md$upper),
    data.frame(panel = "jitter_width", detector = jb$detector, key = "p95-p05",
               value = jb$F1_p95 - jb$F1_p05, lower = NA, upper = NA),
    data.frame(panel = "bootstrap_width", detector = nb$detector, key = "95% interval",
               value = nb$upper - nb$lower, lower = NA, upper = NA)))
  vs <- c("scaled", "optimal", "optimal_scaled", "soft3d")
  w <- merge(data.frame(detector = jb$detector, jitter = jb$F1_p95 - jb$F1_p05),
             data.frame(detector = nb$detector, boot = nb$upper - nb$lower))
  # (d) Observed F1 against the F1 of randomly shifted copies of the same
  # detections, per detector, at both radii; ordered by observed F1 at 4 m.
  ob <- np[np$variant == "baseline" & np$radius == 4, ]
  arms <- ob$detector[order(ob$estimate)]
  render("s2", 0.72 * SUPP_W, 5.9, function() {
    # The right column is wider: (d) needs a wide margin for the detectors'
    # names and room for its legend at 7.2 pt, and (b) for its labels.
    layout(matrix(c(1, 2, 3, 4, 5, 5), 3, byrow = TRUE), widths = c(0.92, 1.08), heights = c(1, 1, 0.36))
    fig_par(mar = c(2.8, 2.9, 1.5, 0.4))
    plot(NA, xlim = c(2, 5), ylim = range(grid$estimate), xlab = "Match radius (m)", ylab = "F1",
         main = "(a) Match radius")
    for (a in names(ARMS)) { z <- grid[grid$detector == a, ]; z <- z[order(z$radius), ]
      lines(z$radius, z$estimate, type = "o", col = COL[a], pch = PCH[a], cex = 0.8) }
    abline(v = 4, lty = 2)
    # The four alternatives sit about 0.6 in apart, so that their 7.2-pt labels
    # stand clear of each other; the detectors' points spread 0.22 either side
    # of each.
    plot(NA, xlim = c(0.7, 4.3), ylim = range(c(md$lower, md$upper)), xaxt = "n", xlab = "",
         ylab = "Change in F1 from greedy 4 m", main = "(b) Matcher")
    axis(1, at = 1:4, labels = c("crown-\nscaled", "Hungarian", "Hungarian,\nscaled", "soft\n3-D"),
         padj = 0.5, gap.axis = 0, mgp = c(1.8, 0.3, 0))
    abline(h = 0, lty = 2)
    for (i in seq_along(names(ARMS))) { a <- names(ARMS)[i]; z <- md[md$detector == a, ]
      xx <- match(z$variant, vs) + (i - 6.5) * 0.04
      segments(xx, z$lower, xx, z$upper, col = COL[a]); points(xx, z$estimate, col = COL[a], pch = PCH[a], cex = 0.8) }
    plot(w$boot, w$jitter, xlim = c(0, max(w$boot) * 1.05), ylim = c(0, max(w$boot) * 1.05),
         col = COL[w$detector], pch = PCH[w$detector], xlab = "Plot-bootstrap 95% interval width (F1)",
         ylab = "Stem-jitter 90% band width (F1)", main = "(c) Jitter against plot sampling")
    abline(0, 1, lty = 2)
    par(mar = c(2.8, 6.4, 1.5, 0.4))
    # A free band above the top row holds the legend.
    plot(NA, xlim = c(0, max(np$upper) * 1.02), ylim = c(0.5, length(arms) + 2.0), yaxt = "n",
         xlab = "F1, native density", ylab = "", main = "(d) Observed and null F1")
    axis(2, at = seq_along(arms), labels = ARMS[arms], las = 1, cex.axis = LEG_CEX)
    for (i in seq_along(arms)) for (r in c(4, 2)) {
      yy <- i + if (r == 4) 0.15 else -0.15
      o <- np[np$detector == arms[i] & np$radius == r & np$variant == "baseline", ]
      n <- np[np$detector == arms[i] & np$radius == r & np$variant == "null", ]
      cl <- if (r == 4) "black" else "grey45"
      segments(n$estimate, yy, o$estimate, yy, col = cl)
      points(n$estimate, yy, pch = 1, col = cl, cex = 0.8); points(o$estimate, yy, pch = 16, col = cl, cex = 0.8)
    }
    legend("top", legend = c("Observed, 4 m", "Null, 4 m", "Observed, 2 m", "Null, 2 m"),
           pch = c(16, 1, 16, 1), col = c("black", "black", "grey45", "grey45"), bty = "n", cex = LEG_CEX,
           pt.cex = 0.8, ncol = 2, x.intersp = 0.6)
    # (a) to (c) share the detectors' colours and symbols.
    legend_panel(legend = ARMS, col = COL[names(ARMS)], pch = PCH[names(ARMS)], lty = 1, ncol = 4,
                 title = "Detectors in (a) to (c)")
  })
}

for (id in FIGS) {
  get(paste0("fig", id))()
  cat(sprintf("figure %s -> %s.{png,pdf}\n", id, file.path(OUT, paste0("figure_", id))))
}
