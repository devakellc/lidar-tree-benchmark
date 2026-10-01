#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(terra); library(xml2) })

# Score-blind audit of the native sparse epochs against the 2021 benchmark:
# native plot-clip densities next to the 2021 ladder, the sparse references
# split into 2015-only and re-measured stems, an annualized mortality bound
# for the 2015-only stratum, and the footprint of the pinned
# NeonTreeEvaluation canopy boxes over the declared scoring cores. Run after
# prepare_sparse_epoch.R and freeze_clips.R YEAR=<year> in each epoch's job
# directory. Downloads only the pinned annotation XML and RGB files of plots
# in the 2021 `adopted` or `all_mapped` populations.
#   Rscript scripts/audit_sparse_epoch.R EPOCHS=SJER:<job dir>:2017,SOAP:<job dir>:2018,... \
#     [ROOT2021=<work>/neon/frozen_2021] [OUT=<dir>]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
ep <- do.call(rbind, lapply(strsplit(strsplit(A$EPOCHS, ",")[[1]], ":"), function(x)
  data.frame(site = x[1], job = x[2], year = as.integer(x[3]), stringsAsFactors = FALSE)))
root21 <- if (is.null(A$ROOT2021)) file.path(.job_dir(), "neon", "frozen_2021") else A$ROOT2021
out <- if (is.null(A$OUT)) file.path(ep$job[1], "audit") else A$OUT
dir.create(out, recursive = TRUE, showWarnings = FALSE)
NTE_REV <- "96b29d566ca7ea9f604de3e1235c503ab101cb8a"   # as the TEAK canopy package

cells <- function(root) {
  cm <- read.csv(file.path(root, "clip_manifest.csv"), colClasses = c(rung = "character"))
  pop <- read.csv(file.path(root, "population.csv"))
  merge(cm, pop[, c("site", "plotID", "plotType")], by.x = c("site", "plot"), by.y = c("site", "plotID"))
}
c21 <- cells(root21)
pop21 <- read.csv(file.path(root21, "population.csv"))
stems21 <- read.csv(file.path(root21, "population_stems.csv"))
mid <- function(v) sprintf("%.1f (%.1f-%.1f)", median(v), min(v), max(v))

dens <- list(); strata <- list(); mort <- list()
for (i in seq_len(nrow(ep))) {
  s <- ep$site[i]; nd <- file.path(ep$job[i], "neon", s); yr <- ep$year[i]
  root <- file.path(ep$job[i], "neon", sprintf("frozen_%d", yr))
  cs <- cells(root); nat <- cs[cs$site == s & cs$rung == "native" & cs$status == "ok", ]
  n21 <- c21[c21$site == s & c21$rung == "native", ]
  common <- intersect(nat$plot, n21$plot)
  for (t in unique(nat$plotType)) {
    x <- nat[nat$plotType == t, ]
    dens[[paste(s, t)]] <- data.frame(site = s, epoch = yr, plotType = t, plots = nrow(x),
      all_returns = mid(x$pdens), first_returns = mid(x$frdens))
  }
  r21 <- c21[c21$site == s & c21$status == "ok" & c21$plot %in% common, ]
  dens[[paste(s, "match")]] <- data.frame(site = s, epoch = yr, plotType = "common with 2021",
    plots = length(common), all_returns = mid(nat$pdens[nat$plot %in% common]),
    first_returns = mid(nat$frdens[nat$plot %in% common]))
  for (r in c("native", "8", "4")) {
    x <- r21[r21$rung == r, ]
    dens[[paste(s, r)]] <- data.frame(site = s, epoch = 2021, plotType = paste("2021", r), plots = nrow(x),
      all_returns = mid(x$pdens), first_returns = mid(x$frdens))
  }

  # Reference strata: a stem is "2015-only" when no record after 2015 exists.
  vst <- readRDS(file.path(nd, "vst", sprintf("%s_vst_allyears.rds", tolower(s))))
  ai <- vst$vst_apparentindividual
  ai$y <- as.integer(substr(ai$date, 1, 4)); ai$live <- grepl("^Live", ai$plantStatus)
  st <- aggregate(live ~ individualID + y, ai, any)            # a tree lives if a bole does
  last <- tapply(st$y, st$individualID, max)
  ps <- read.csv(file.path(root, "population_stems.csv")); ps <- ps[ps$site == s, ]
  for (p in c("adopted", "all_mapped")) {
    x <- ps[ps$population == p, ]
    only15 <- as.integer(last[x$individualID]) <= 2015
    strata[[paste(s, p)]] <- data.frame(site = s, epoch = yr, population = p,
      plots = length(unique(x$plotID)), core_stems = nrow(x), only_2015 = sum(only15),
      remeasured_after_2015 = sum(!only15),
      plots_in_2021_population = length(intersect(unique(x$plotID), pop21$plotID[pop21$site == s &
        pop21[[paste0("in_", p)]]])))
  }
  # Annualized mortality: trees live in 2015, status at their next record.
  l15 <- st$individualID[st$y == 2015 & st$live]
  later <- st[st$individualID %in% l15 & st$y > 2015, ]
  later <- later[order(later$individualID, later$y), ]
  nx <- later[!duplicated(later$individualID), ]; dt <- nx$y - 2015
  nll <- function(m) -sum(ifelse(nx$live, dt * log(1 - m), log(1 - (1 - m)^dt)))
  if (nrow(nx)) {
    m <- optimize(nll, c(1e-6, 0.5))$minimum
    grid <- seq(1e-4, 0.4, by = 1e-4)
    ci <- range(grid[vapply(grid, nll, numeric(1)) - nll(m) <= qchisq(0.95, 1) / 2])
    gap <- yr - 2015
    mort[[s]] <- data.frame(site = s, epoch = yr, trees = nrow(nx), dead_at_next_record = sum(!nx$live),
      next_record_years = paste(sort(unique(nx$y)), collapse = " "), annual = round(m, 4),
      annual_lo = round(ci[1], 4), annual_hi = round(ci[2], 4), years_2015_to_flight = gap,
      dead_by_flight = round(1 - (1 - m)^gap, 3), dead_by_flight_hi = round(1 - (1 - ci[2])^gap, 3))
  }
}

# NeonTreeEvaluation boxes over the scoring cores of the declared populations.
tree <- jsonlite::fromJSON(sprintf(
  "https://api.github.com/repos/weecology/NeonTreeEvaluation/git/trees/%s?recursive=1", NTE_REV))$tree
ann <- grep("^annotations/(SJER|SOAP|TEAK)_[0-9]{3}_[0-9]{4}[.]xml$", tree$path, value = TRUE)
ids <- sub("^annotations/(.*)[.]xml$", "\\1", ann)
plots <- sub("_[0-9]{4}$", "", ids)
listed <- data.frame(annotation = ids, plotID = plots, site = substr(plots, 1, 4),
  in_adopted = plots %in% pop21$plotID[pop21$in_adopted],
  in_all_mapped = plots %in% pop21$plotID[pop21$in_all_mapped],
  in_relaxed = plots %in% pop21$plotID[pop21$in_relaxed])
nte <- file.path(out, "nte"); files <- list()
fp <- list()
for (k in which(listed$in_adopted | listed$in_all_mapped)) {
  id <- listed$annotation[k]
  for (p in c(sprintf("annotations/%s.xml", id), sprintf("evaluation/RGB/%s.tif", id))) {
    dest <- file.path(nte, p); dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    if (!file.exists(dest)) utils::download.file(sprintf(
      "https://raw.githubusercontent.com/weecology/NeonTreeEvaluation/%s/%s", NTE_REV, p),
      dest, mode = "wb", quiet = TRUE)
    files[[p]] <- data.frame(path = p, bytes = file.size(dest),
                             sha256 = digest::digest(file = dest, algo = "sha256"))
  }
  r <- rast(file.path(nte, sprintf("evaluation/RGB/%s.tif", id))); e <- ext(r); rs <- res(r)[1]
  p <- pop21[pop21$plotID == listed$plotID[k], ]; h <- p$core_half
  cover <- max(0, min(e[2], p$easting + h) - max(e[1], p$easting - h)) *
    max(0, min(e[4], p$northing + h) - max(e[3], p$northing - h)) / (2 * h)^2
  b <- xml_find_all(read_xml(file.path(nte, sprintf("annotations/%s.xml", id))), ".//object/bndbox")
  v <- function(n) as.numeric(xml_text(xml_find_first(b, n)))
  bx <- e[1] + (v("xmin") + v("xmax")) / 2 * rs; by <- e[4] - (v("ymin") + v("ymax")) / 2 * rs
  fp[[id]] <- data.frame(annotation = id, plotType = p$plotType, epsg = crs(r, describe = TRUE)$code,
    image_m = sprintf("%.0f x %.0f", e[2] - e[1], e[4] - e[3]), core_covered = round(cover, 3),
    boxes = length(b), boxes_in_core = sum(abs(bx - p$easting) <= h & abs(by - p$northing) <= h),
    stems_adopted = sum(stems21$plotID == p$plotID & stems21$population == "adopted"),
    stems_all_mapped = sum(stems21$plotID == p$plotID & stems21$population == "all_mapped"))
}

save <- function(x, f) { x <- do.call(rbind, x); write.csv(x, file.path(out, f), row.names = FALSE); x }
print(save(dens, "density.csv"), row.names = FALSE)
print(save(strata, "reference_strata.csv"), row.names = FALSE)
print(save(mort, "mortality.csv"), row.names = FALSE)
write.csv(listed, file.path(out, "nte_listed.csv"), row.names = FALSE)
print(aggregate(cbind(annotations = 1, in_adopted, in_all_mapped, in_relaxed) ~ site, listed, sum), row.names = FALSE)
print(save(fp, "nte_footprint.csv"), row.names = FALSE)
invisible(save(files, "nte_files.csv"))
cat("NeonTreeEvaluation revision", NTE_REV, "\n")
