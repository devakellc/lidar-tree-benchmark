#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_reference_support_lib.R"))

# Score-blind admission review of censused-subplot support for the declared
# plot population. For every plot of the sealed frozen root it reports the
# census events near the LiDAR year, the support bundle built by
# neon_reference_support.R from the exact-year event (the protocol's rule) and,
# as a separate option, from the nearest all-growth-forms event within WINDOW
# years, with the blockers that keep each bundle diagnostic. It also records
# what the 2015 tower census says about its subplots. Nothing is scored and no
# bundle is admitted: the draft declaration lists the exact-year bundles whose
# only blockers are review blockers, for a reviewer to accept or reject.
#   Rscript scripts/review_census_support.R [SITES=SJER,SOAP,TEAK,WREF,ABBY]
#     [YEARS=2019,...,2024] [TARGET_YEAR=2021] [WINDOW=4]
#     [SUPPORT=$CLAUDE_JOB_DIR/reference_support_v1] [FROZEN_ROOT=...] [OUT=...]
# SUPPORT holds one neon_reference_support.R output per <SITE>_<YEAR>.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d <- .job_dir()
SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
YEARS <- as.integer(split_arg(A$YEARS, paste(2019:2024, collapse = ",")))
TARGET <- as.integer(if (is.null(A$TARGET_YEAR)) 2021 else A$TARGET_YEAR)
WINDOW <- as.integer(if (is.null(A$WINDOW)) 4 else A$WINDOW)
SUPPORT <- if (is.null(A$SUPPORT)) file.path(d, "reference_support_v1") else A$SUPPORT
ROOT <- if (is.null(A$FROZEN_ROOT)) file.path(d, "neon", "frozen_2021") else A$FROZEN_ROOT
OUT <- if (is.null(A$OUT)) file.path(SUPPORT, "admission") else A$OUT
REVIEW_ONLY <- c("datum_review_pending", "flight_provenance_pending")

pop <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
stems <- read.csv(file.path(ROOT, "population_stems.csv"), stringsAsFactors = FALSE)
pops <- sub("^in_", "", grep("^in_", names(pop), value = TRUE))

# One bundle summary per site x year x plot from the preparation outputs.
support_runs <- function(site) {
  rows <- lapply(YEARS, function(y) {
    dir <- file.path(SUPPORT, paste0(site, "_", y))
    if (!file.exists(file.path(dir, "completion.json"))) return(NULL)
    s <- read.csv(file.path(dir, "event_support_summary.csv"), stringsAsFactors = FALSE)
    b <- readRDS(file.path(dir, "support_bundles.rds"))
    s$year <- y
    s$blockers <- vapply(seq_len(nrow(s)), function(i) {
      k <- neon_support_key(s$plot[i], s$event[i])
      if (is.null(b[[k]])) NA_character_ else paste(b[[k]]$blockers, collapse = ";")
    }, character(1))
    s
  })
  do.call(rbind, rows)
}

bundle_status <- function(geometry, blockers) {
  if (is.na(geometry)) return("no_bundle")
  if (geometry != "measured_corners") return(paste0("geometry_failed: ", geometry))
  b <- strsplit(blockers, ";", fixed = TRUE)[[1]]
  if (all(b %in% REVIEW_ONLY)) return("admissible_on_declaration")
  if (all(b %in% NEON_RESOLVABLE_BLOCKERS))
    return("admissible_with_missing_reference_policy")
  paste0("blocked: ", paste(setdiff(b, NEON_RESOLVABLE_BLOCKERS), collapse = ";"))
}

review_site <- function(site) {
  nd <- file.path(d, "neon", site)
  dat <- readRDS(file.path(nd, "vst", paste0(tolower(site), "_vst_allyears.rds")))
  pp <- unique(as.data.frame(dat$vst_perplotperyear))
  pp$year <- as.integer(substr(as.character(pp$date), 1, 4))
  ai <- as.data.frame(dat$vst_apparentindividual)
  ai$year <- as.integer(substr(as.character(ai$date), 1, 4))
  target_2015 <- ai$year == 2015L & grepl("^Live", ai$plantStatus) &
    ai$growthForm %in% c("single bole tree", "multi-bole tree") &
    is.finite(ai$stemDiameter) & ai$stemDiameter >= 10
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  runs <- support_runs(site)
  plots <- pop[pop$site == site, , drop = FALSE]
  do.call(rbind, lapply(seq_len(nrow(plots)), function(i) {
    p <- plots$plotID[i]
    ev <- pp[pp$plotID == p & pp$year %in% (TARGET - WINDOW):(TARGET + WINDOW), , drop = FALSE]
    ev <- ev[order(abs(ev$year - TARGET), -ev$year), , drop = FALSE]
    full <- ev[ev$dataCollected %in% "allGrowthForms", , drop = FALSE]
    r <- if (is.null(runs)) NULL else runs[runs$plot == p, , drop = FALSE]
    exact <- if (!is.null(r)) r[r$year == TARGET, , drop = FALSE] else NULL
    exact_events <- ev[ev$year == TARGET, , drop = FALSE]
    exact_status <- if (!nrow(exact_events)) "no_census_event" else
      if (!any(exact_events$dataCollected %in% "allGrowthForms"))
        paste0("not_full_census: ", paste(unique(exact_events$dataCollected), collapse = ";")) else
      if (is.null(exact) || !nrow(exact)) "no_bundle" else
      bundle_status(exact$geometry_status[1], exact$blockers[1])
    near <- if (!is.null(r) && nrow(r)) r[r$geometry_status == "measured_corners" &
      abs(r$year - TARGET) <= WINDOW, , drop = FALSE] else NULL
    near <- if (!is.null(near) && nrow(near)) near[order(abs(near$year - TARGET), -near$year)[1], ] else NULL
    ref <- stems[stems$site == site & stems$plotID == p & stems$population == "adopted", ]
    ref_year <- gt$meas_year[match(paste(ref$plotID, ref$individualID),
                                   paste(gt$plotID, gt$individualID))]
    t15 <- target_2015 & ai$plotID == p
    sub15 <- unique(ai$subplotID[t15])
    out <- data.frame(site = site, plot = p, plotType = plots$plotType[i],
      n_core_dbh10 = plots$n_core_dbh10[i],
      events_in_window = paste(sprintf("%d:%s", ev$year, ifelse(is.na(ev$dataCollected), "NA",
                                                                ev$dataCollected)), collapse = ";"),
      exact_event = if (nrow(exact_events)) exact_events$eventID[1] else NA_character_,
      exact_sampled_area_m2 = if (nrow(exact_events)) exact_events$totalSampledAreaTrees[1] else NA_real_,
      exact_subplots = if (nrow(exact_events)) exact_events$subplotsSampled[1] else NA_character_,
      exact_status = exact_status,
      exact_measured_area_m2 = if (!is.null(exact) && nrow(exact)) exact$measured_area_m2[1] else NA_real_,
      exact_interior_area_m2 = if (!is.null(exact) && nrow(exact)) exact$interior_area_m2[1] else NA_real_,
      exact_n_target = if (!is.null(exact) && nrow(exact)) exact$n_target[1] else NA_integer_,
      exact_n_selected = if (!is.null(exact) && nrow(exact)) exact$n_selected[1] else NA_integer_,
      exact_support_id = if (!is.null(exact) && nrow(exact)) exact$support_id[1] else NA_character_,
      exact_blockers = if (!is.null(exact) && nrow(exact)) exact$blockers[1] else NA_character_,
      nearest_full_year = if (!is.null(near)) near$year else NA_integer_,
      nearest_offset_yr = if (!is.null(near)) near$year - TARGET else NA_integer_,
      nearest_event = if (!is.null(near)) near$event else NA_character_,
      nearest_interior_area_m2 = if (!is.null(near)) near$interior_area_m2 else NA_real_,
      nearest_n_selected = if (!is.null(near)) near$n_selected else NA_integer_,
      nearest_status = if (!is.null(near)) bundle_status(near$geometry_status, near$blockers) else
        if (nrow(full)) "no_bundle" else "no_full_census_in_window",
      ref_share_in_exact_year = if (length(ref_year)) mean(ref_year %in% TARGET) else NA_real_,
      ref_share_in_nearest_year = if (length(ref_year) && !is.null(near))
        mean(ref_year %in% near$year) else NA_real_,
      census_2015_area_m2 = if (any(pp$plotID == p & pp$year == 2015L))
        pp$totalSampledAreaTrees[pp$plotID == p & pp$year == 2015L][1] else NA_real_,
      census_2015_target_records = sum(t15),
      census_2015_quadrants_400 = sum(grepl("_400$", sub15)),
      stringsAsFactors = FALSE)
    for (q in pops) out[[paste0("in_", q)]] <- plots[[paste0("in_", q)]][i]
    out
  }))
}

tab <- do.call(rbind, lapply(SITES, review_site))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
write.csv(tab, file.path(OUT, "census_support_admission.csv"), row.names = FALSE)

# Counts per site, population and status, for the exact-year and nearest rules.
simple <- function(x) sub(":.*$", "", x)
counts <- do.call(rbind, lapply(pops, function(q) {
  x <- tab[tab[[paste0("in_", q)]], , drop = FALSE]
  rbind(data.frame(population = q, rule = "exact_year", site = x$site, status = simple(x$exact_status)),
        data.frame(population = q, rule = "nearest_full_census", site = x$site,
                   status = simple(x$nearest_status)))
}))
agg <- aggregate(list(plots = rep(1L, nrow(counts))), counts[, c("population", "rule", "site", "status")], sum)
agg <- agg[order(agg$population, agg$rule, match(agg$site, SITES), agg$status), ]
write.csv(agg, file.path(OUT, "census_support_admission_counts.csv"), row.names = FALSE)

# Draft declaration: exact-year bundles held back only by review blockers.
cand <- tab[tab$exact_status == "admissible_on_declaration", , drop = FALSE]
draft <- list(name = sprintf("paper-%d-census-support (DRAFT, not reviewed)", TARGET),
              policy = "measured_subplots_uncertainty_interior_v1",
              resolved_blockers = REVIEW_ONLY,
              evidence = list(datum = "TO REVIEW: field named points and 2021 AOP tiles share the site's WGS84 UTM EPSG; NEON AOP specifies ITRF00",
                              flight = "TO REVIEW: 2021 flight days per site from the NEON L3 processing reports"),
              admitted = cand[, c("site", "plot", "exact_event", "exact_support_id")])
names(draft$admitted) <- c("site", "plot", "event", "support_id")
jsonlite::write_json(draft, file.path(OUT, "declaration_draft.json"), auto_unbox = TRUE,
                     pretty = TRUE, digits = NA)
print(agg, row.names = FALSE)
cat(sprintf("exact-year bundles held back only by review blockers: %d plots\n", nrow(cand)))
cat("Score-blind review; no bundle admitted and no detector scored.\n")
