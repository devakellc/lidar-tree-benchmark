#!/usr/bin/env Rscript
# Scout candidate AOIs on public USGS 3DEP EPTs with lasR (r-lidar/lasR@pre-devel).
# For a square of SIDE metres (ground) around each centre it reports true
# first-return pulse density, the acquisition window from GPS time, and the
# share of first returns per normalized-height band.
#
# EPTs are EPSG:3857, so ground distances are scaled by k = 1/cos(lat): the
# query half-width is SIDE/2 * k and densities from summarise() are per 3857
# unit, i.e. true density = reported * k^2.
#
# Usage: Rscript scripts/scout_3dep_aois.R [AOIS=aois.json] [IDS=a,b] [SIDE=200] [CORES=2]
suppressMessages({ library(lasR); library(jsonlite) })

A <- list(AOIS = "aois.json", IDS = "", SIDE = "200", CORES = "2")
for (kv in strsplit(commandArgs(TRUE), "=", fixed = TRUE))
  if (length(kv) == 2) A[[kv[1]]] <- kv[2]
side <- as.numeric(A$SIDE); cores <- as.integer(A$CORES)

man <- fromJSON(A$AOIS, simplifyDataFrame = TRUE)
aois <- man$aois
if (nzchar(A$IDS)) aois <- aois[aois$id %in% strsplit(A$IDS, ",")[[1]], ]
if (!nrow(aois)) stop("no AOIs selected")

ll2merc <- function(lon, lat)
  c(lon * pi / 180 * 6378137, log(tan(pi / 4 + lat * pi / 360)) * 6378137)
gps_to_date <- function(t)   # adjusted standard GPS time -> UTC date
  as.Date(as.POSIXct(t + 1e9, origin = "1980-01-06", tz = "UTC"))

rows <- list()
for (i in seq_len(nrow(aois))) {
  a <- aois[i, ]
  k <- 1 / cos(a$lat * pi / 180)
  m <- ll2merc(a$lon, a$lat); hw <- side / 2 * k
  url <- sprintf("%s/%s/ept.json", man$ept_base, a$ept)
  rd <- reader_rectangles(m[1] - hw, m[2] - hw, m[1] + hw, m[2] + hw,
                          filter = "-drop_class 7 18 -drop_withheld")
  t0 <- Sys.time()
  res <- tryCatch({
    s0 <- exec(rd + summarise(metrics = c("gpstime_min", "gpstime_max", "count")),
               on = url, ncores = cores)
    s1 <- exec(rd + normalize() + summarise(zwbin = 0.5, filter = keep_first()),
               on = url, ncores = cores)
    list(s0 = s0, s1 = s1)
  }, error = function(e) { message(a$id, ": ", conditionMessage(e)); NULL })
  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (is.null(res) || !isTRUE(res$s1$npoints > 0)) {
    cat(sprintf("%-12s no points (%.0f s)\n", a$id, dt)); next
  }
  zh <- res$s1$z_histogram; br <- as.numeric(names(zh)); n <- as.numeric(zh)
  share <- function(lo, hi) sum(n[br >= lo & br < hi]) / sum(n)
  mt <- res$s0$metrics
  d0 <- gps_to_date(min(mt$gpstime_min, na.rm = TRUE))
  d1 <- gps_to_date(max(mt$gpstime_max, na.rm = TRUE))
  r <- data.frame(id = a$id, ept = a$ept, pulses_m2 = round(res$s1$pulse_density * k^2, 2),
                  first = as.character(d0), last = as.character(d1),
                  gt2m = round(share(2, Inf), 3), h1_5_5 = round(share(1.5, 5), 3),
                  h5_15 = round(share(5, 15), 3), gt15 = round(share(15, Inf), 3),
                  seconds = round(dt))
  print(r, row.names = FALSE)
  rows[[length(rows) + 1]] <- r
}
if (length(rows)) {
  out <- do.call(rbind, rows)
  write.csv(out, "scout_results.csv", row.names = FALSE)
  cat("wrote scout_results.csv\n")
}
