#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(if (length(.bs_file))
  file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"), "scripts/bootstrap.R"))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("neon_spatial_lib.R"))
source(.find("neon_reference_support_lib.R"))

# Score-blind admission review of censused-subplot support for the declared
# plot population. For every plot of the sealed frozen root it takes two
# candidate bundles from neon_reference_support.R outputs: the nearest
# all-growth-forms census within WINDOW years of the LiDAR year (the headline
# rule) and the exact LiDAR-year census (a check), applies the declared
# missing-reference policy (subplot exclusion) and reports whether each bundle
# would be admitted, what the policy removed, and what the 2015 tower census
# says about its subplots. With EVIDENCE=<json> it writes the reviewed
# declarations for both rules, admitting exactly the bundles held back only by
# the datum and flight-provenance review that the evidence resolves.
#   Rscript scripts/review_census_support.R [SITES=SJER,SOAP,TEAK,WREF,ABBY]
#     [YEARS=2019,...,2024] [TARGET_YEAR=2021] [WINDOW=4]
#     [SUPPORT=$CLAUDE_JOB_DIR/reference_support_census_event]
#     [POLICY=subplot_exclusion|subplot_exclusion_strict|none]
#     [EVIDENCE=docs/census-support-evidence.json]
#     [FROZEN_ROOT=...] [OUT=<SUPPORT>/admission]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d <- .job_dir()
SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
YEARS <- as.integer(split_arg(A$YEARS, paste(2019:2024, collapse = ",")))
TARGET <- as.integer(if (is.null(A$TARGET_YEAR)) 2021 else A$TARGET_YEAR)
WINDOW <- as.integer(if (is.null(A$WINDOW)) 4 else A$WINDOW)
SUPPORT <- if (is.null(A$SUPPORT)) file.path(d, "reference_support_census_event") else A$SUPPORT
POLICY <- if (is.null(A$POLICY)) "subplot_exclusion" else A$POLICY
ROOT <- if (is.null(A$FROZEN_ROOT)) file.path(d, "neon", "frozen_2021") else A$FROZEN_ROOT
OUT <- if (is.null(A$OUT)) file.path(SUPPORT, "admission") else A$OUT

pop <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
stems <- read.csv(file.path(ROOT, "population_stems.csv"), stringsAsFactors = FALSE)
pops <- sub("^in_", "", grep("^in_", names(pop), value = TRUE))

if (!POLICY %in% c("none", NEON_MISSING_POLICIES)) stop("Unknown missing-reference policy: ", POLICY)
apply_policy <- function(b) if (identical(POLICY, "none")) b else
  neon_subplot_exclusion(b, strict = identical(POLICY, "subplot_exclusion_strict"))
bundle_status <- function(b) {
  if (is.null(b)) return("no_bundle")
  left <- setdiff(b$blockers, NEON_RESOLVABLE_BLOCKERS)
  if (!length(left)) "admissible" else paste0("blocked: ", paste(left, collapse = ";"))
}

# Every built bundle of a site, with its year, before and after the policy.
site_bundles <- function(site) {
  out <- list()
  for (y in YEARS) {
    f <- file.path(SUPPORT, paste0(site, "_", y), "support_bundles.rds")
    if (!file.exists(f)) next
    for (b in readRDS(f)) out[[length(out) + 1]] <- list(year = y, plot = b$plot, event = b$event,
                                                          raw = b, policy = apply_policy(b))
  }
  out
}
geometry_errors <- function(site) {
  rows <- lapply(YEARS, function(y) {
    f <- file.path(SUPPORT, paste0(site, "_", y), "event_support_summary.csv")
    if (!file.exists(f)) return(NULL)
    s <- read.csv(f, stringsAsFactors = FALSE)
    s <- s[s$geometry_status != "measured_corners", c("plot", "event", "geometry_status"), drop = FALSE]
    if (nrow(s)) cbind(year = y, s) else NULL
  })
  do.call(rbind, rows)
}

candidate_cols <- function(prefix, cand, status) {
  b <- if (is.null(cand)) NULL else cand$policy
  pol <- if (is.null(b)) NULL else b$missing_reference_policy
  out <- data.frame(
    year = if (is.null(cand)) NA_integer_ else cand$year,
    event = if (is.null(cand)) NA_character_ else cand$event,
    status = status,
    support_id = if (is.null(b)) NA_character_ else neon_support_identity(b),
    interior_before_m2 = if (is.null(b)) NA_real_ else cand$raw$interior_area_m2,
    interior_m2 = if (is.null(b)) NA_real_ else b$interior_area_m2,
    n_target = if (is.null(b)) NA_integer_ else sum(b$references$target_population),
    n_missing = if (is.null(pol)) NA_integer_ else pol$n_missing_targets,
    n_height_unknown = if (is.null(pol)) NA_integer_ else pol$n_height_unknown,
    n_unlocatable = if (is.null(pol)) NA_integer_ else pol$n_unlocatable,
    excluded_subplots = if (is.null(pol)) NA_character_ else paste(pol$excluded_subplots, collapse = ";"),
    n_selected = if (is.null(b)) NA_integer_ else sum(b$references$reference_selected),
    blockers = if (is.null(b)) NA_character_ else paste(b$blockers, collapse = ";"),
    stringsAsFactors = FALSE)
  names(out) <- paste0(prefix, "_", names(out))
  out
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
  bundles <- site_bundles(site)
  errors <- geometry_errors(site)
  plots <- pop[pop$site == site, , drop = FALSE]
  do.call(rbind, lapply(seq_len(nrow(plots)), function(i) {
    p <- plots$plotID[i]
    ev <- pp[pp$plotID == p & pp$year %in% (TARGET - WINDOW):(TARGET + WINDOW), , drop = FALSE]
    ev <- ev[order(abs(ev$year - TARGET), -ev$year), , drop = FALSE]
    mine <- Filter(function(b) b$plot == p, bundles)
    # Nearest rule: the closest full census whose bundle holds target records.
    usable <- Filter(function(b) abs(b$year - TARGET) <= WINDOW &&
                       sum(b$raw$references$target_population) > 0, mine)
    near <- if (length(usable)) usable[[order(vapply(usable, function(b) abs(b$year - TARGET), 0),
                                              -vapply(usable, `[[`, 0, "year"))[1]]] else NULL
    exact <- Filter(function(b) b$year == TARGET, mine)
    exact <- if (length(exact)) exact[[1]] else NULL
    exact_events <- ev[ev$year == TARGET, , drop = FALSE]
    err <- if (!is.null(errors)) errors[errors$plot == p, , drop = FALSE] else NULL
    exact_status <- if (!nrow(exact_events)) "no_census_event" else
      if (!any(exact_events$dataCollected %in% "allGrowthForms"))
        paste0("not_full_census: ", paste(unique(exact_events$dataCollected), collapse = ";")) else
      if (is.null(exact)) {
        e <- if (!is.null(err)) err$geometry_status[err$year == TARGET] else character()
        if (length(e)) paste0("geometry_failed: ", e[1]) else "no_bundle"
      } else bundle_status(exact$policy)
    near_status <- if (!is.null(near)) bundle_status(near$policy) else
      if (any(ev$dataCollected %in% "allGrowthForms")) {
        e <- if (!is.null(err)) err$geometry_status[abs(err$year - TARGET) <= WINDOW] else character()
        if (length(e)) paste0("geometry_failed: ", e[1]) else "no_bundle"
      } else "no_full_census_in_window"
    ref <- stems[stems$site == site & stems$plotID == p & stems$population == "adopted", ]
    ref_year <- gt$meas_year[match(paste(ref$plotID, ref$individualID),
                                   paste(gt$plotID, gt$individualID))]
    t15 <- target_2015 & ai$plotID == p
    out <- data.frame(site = site, plot = p, plotType = plots$plotType[i],
      n_core_dbh10 = plots$n_core_dbh10[i],
      events_in_window = paste(sprintf("%d:%s", ev$year, ifelse(is.na(ev$dataCollected), "NA",
                                                                ev$dataCollected)), collapse = ";"),
      candidate_cols("nearest", near, near_status),
      candidate_cols("exact", exact, exact_status),
      ref_share_in_nearest_year = if (length(ref_year) && !is.null(near))
        mean(ref_year %in% near$year) else NA_real_,
      census_2015_area_m2 = if (any(pp$plotID == p & pp$year == 2015L))
        pp$totalSampledAreaTrees[pp$plotID == p & pp$year == 2015L][1] else NA_real_,
      census_2015_target_records = sum(t15),
      census_2015_quadrants_400 = sum(grepl("^[0-9]+_400$", unique(ai$subplotID[t15]))),
      stringsAsFactors = FALSE)
    for (q in pops) out[[paste0("in_", q)]] <- plots[[paste0("in_", q)]][i]
    out
  }))
}

tab <- do.call(rbind, lapply(SITES, review_site))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
write.csv(tab, file.path(OUT, "census_support_admission.csv"), row.names = FALSE)

simple <- function(x) sub(":.*$", "", x)
counts <- do.call(rbind, lapply(pops, function(q) {
  x <- tab[tab[[paste0("in_", q)]], , drop = FALSE]
  rbind(data.frame(population = q, rule = "nearest", site = x$site, status = simple(x$nearest_status)),
        data.frame(population = q, rule = "exact", site = x$site, status = simple(x$exact_status)))
}))
agg <- aggregate(list(plots = rep(1L, nrow(counts))), counts[, c("population", "rule", "site", "status")], sum)
agg <- agg[order(agg$population, agg$rule, match(agg$site, SITES), agg$status), ]
write.csv(agg, file.path(OUT, "census_support_admission_counts.csv"), row.names = FALSE)

# Reviewed declarations: the evidence resolves the datum and flight review;
# the policy has already cleared missing target references.
if (!is.null(A$EVIDENCE)) {
  evidence <- jsonlite::read_json(A$EVIDENCE, simplifyVector = TRUE)
  joins <- unique(unlist(lapply(SITES, function(s) lapply(site_bundles(s), function(b) b$raw$join))))
  for (rule in c("nearest", "exact")) {
    ok <- tab[tab[[paste0(rule, "_status")]] == "admissible", , drop = FALSE]
    decl <- list(name = sprintf("paper-%d-census-support-%s-%s", TARGET,
                                if (rule == "nearest") "nearest" else "exact",
                                if (POLICY == "subplot_exclusion") "v2" else POLICY),
      rule = if (rule == "nearest") sprintf("nearest all-growth-forms census within %d years of %d", WINDOW, TARGET)
             else sprintf("exact %d census", TARGET),
      role = if (rule == "nearest") "headline" else "check",
      policy = "measured_subplots_uncertainty_interior_v1",
      join = if (length(joins) == 1L) joins else "mixed",
      missing_reference_policy = POLICY,
      resolved_blockers = NEON_RESOLVABLE_BLOCKERS,
      evidence = evidence,
      admitted = data.frame(site = ok$site, plot = ok$plot, event = ok[[paste0(rule, "_event")]],
                            year = ok[[paste0(rule, "_year")]],
                            support_id = ok[[paste0(rule, "_support_id")]]))
    jsonlite::write_json(decl, file.path(OUT, sprintf("declaration_%s.json", rule)),
                         auto_unbox = TRUE, pretty = TRUE, digits = NA)
  }
}
print(agg[agg$population == "adopted", ], row.names = FALSE)
cat("Score-blind review; detectors are scored only by score_census_support.R.\n")
