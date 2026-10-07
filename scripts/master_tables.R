#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("model_bench_lib.R"))
source(.find("master_tables_lib.R"))

# Master tables for the paper. Reads every arm's results from one job
# directory run on the sealed frozen root, keeps an arm only when it covers
# every usable (site, plot, rung) cell of the declared population and its
# outputs carry the root's stamp, enforces equal support per rung, pools by
# summed counts and attaches paired plot-level bootstrap intervals (plots
# resampled within site, 1,000 seeded draws shared by every arm and rung).
# Census-support scores (score_census_support.R) get the same treatment on
# their admitted plots. Arms not yet re-run on the root are listed as pending,
# never filled from older outputs. Positional-jitter bands
# (mc_positional_uncertainty.R) are a separate uncertainty source and are not
# merged here. Also writes the reference-population table that explains every
# historical reference count.
#   Rscript scripts/master_tables.R [SITES=SJER,SOAP,TEAK,WREF,ABBY] [POP=adopted]
#     [FROZEN_ROOT=...] [N_BOOT=1000] [SEED=20261002] [OUT=...]
#     [RUNG_JOBS=<job dir>:<root>,...]
# CLAUDE_JOB_DIR is the re-run job directory (arm outputs under neon/<SITE>).
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d      <- .job_dir()
SITES  <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
POP    <- if (is.null(A$POP)) "adopted" else A$POP
ROOT   <- frozen_root(d, A$FROZEN_ROOT)
N_BOOT <- as.integer(if (is.null(A$N_BOOT)) MT_N_BOOT else A$N_BOOT)
SEED   <- as.integer(if (is.null(A$SEED)) MT_SEED else A$SEED)
OUT    <- if (is.null(A$OUT)) file.path(d, "master_tables") else A$OUT
if (!frozen_sealed(ROOT)) stop("No sealed frozen root at ", ROOT)
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

## ---- arms ------------------------------------------------------------------
# MT_ARMS (master_tables_lib.R): one row per arm with its results file, rungs
# and provenance.

pop  <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
pst  <- read.csv(file.path(ROOT, "population_stems.csv"), stringsAsFactors = FALSE)
cm   <- frozen_clip_manifest(ROOT)
inpop <- pop[pop$site %in% SITES & pop[[paste0("in_", POP)]], , drop = FALSE]
nref_plot <- table(paste(pst$site[pst$population == POP], pst$plotID[pst$population == POP],
                         sep = "::"))
root_id <- frozen_root_id(ROOT)

# RUNG_JOBS=<job dir>:<root>[,...] adds rungs frozen into their own root (the
# QL2 rung, for one) and run in their own job directory. The root must declare
# this root's population and only new rungs; the ladder arms are read there at
# its rungs, and each part carries its own status.
parts <- list(list(dir = d, root = ROOT, id = root_id, cm = cm, rungs = NULL))
for (x in split_arg(A$RUNG_JOBS, "")) {
  p <- strsplit(x, ":", fixed = TRUE)[[1]]
  if (length(p) != 2) stop("RUNG_JOBS entries are <job dir>:<root>")
  if (!frozen_sealed(p[2])) stop("No sealed frozen root at ", p[2])
  if (!identical(frozen_sha256(file.path(p[2], "population.csv")),
                 frozen_sha256(file.path(ROOT, "population.csv"))))
    stop("Root ", p[2], " declares a different population from ", ROOT)
  rr <- as.character(frozen_root_rungs(p[2]))
  if (any(rr %in% MT_RUNGS)) stop("Root ", p[2], " repeats rungs of ", ROOT)
  parts[[length(parts) + 1]] <- list(dir = p[1], root = p[2], id = frozen_root_id(p[2]),
                                     cm = frozen_clip_manifest(p[2]), rungs = rr)
}
RUNG_ORDER <- c("native", as.character(sort(unique(as.numeric(c(
  MT_RUNGS[-1], unlist(lapply(parts, `[[`, "rungs"))))), decreasing = TRUE)))
cm_all <- do.call(rbind, lapply(parts, function(x)
  if (is.null(x$rungs)) x$cm else x$cm[x$cm$rung %in% x$rungs, , drop = FALSE]))

provenance_ok <- function(part, site, what) {
  path <- file.path(part$dir, "neon", site, what)
  if (grepl("\\.frozen$", what)) {
    if (!file.exists(path)) return(FALSE)
    id <- jsonlite::read_json(path, simplifyVector = TRUE)
    return(identical(id$clip_manifest_sha256, part$id) && identical(id$population, POP))
  }
  dir.exists(path) && frozen_stamp_check(path, part$root, strict = FALSE)
}
# Results re-scored from persisted detections (rescore_population.R) carry no
# artifact directory of their own; their <results>.frozen sidecar ties them to
# the root and to this population instead.
sidecar_ok <- function(part, site, file) provenance_ok(part, site, paste0(file, ".frozen"))

load_part <- function(a, part, rungs) {
  need <- part$cm[part$cm$status == "ok" & part$cm$rung %in% rungs &
                    paste(part$cm$site, part$cm$plot) %in% paste(inpop$site, inpop$plotID), , drop = FALSE]
  need_key <- paste(need$site, need$plot, need$rung, sep = "::")
  rows <- do.call(rbind, lapply(SITES, function(site) {
    f <- file.path(part$dir, "neon", site, a$file)
    if (!file.exists(f)) return(NULL)
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x <- x[x$detector == a$detector, , drop = FALSE]
    x$detector <- rep(a$arm, nrow(x))
    if (!is.na(a$result_rung)) x$rung[x$rung == a$result_rung] <- "native"
    if (nrow(x) && is.null(x$site)) x$site <- site
    x
  }))
  have <- if (is.null(rows)) character() else paste(rows$site, rows$plot, rows$rung, sep = "::")
  stamped <- all(vapply(SITES, function(site)
    provenance_ok(part, site, a$provenance) || sidecar_ok(part, site, a$file), logical(1)))
  missing <- setdiff(need_key, have)
  status <- if (is.null(rows)) "pending re-run: no output on the root" else
    if (!stamped) "pending re-run: outputs not stamped with the sealed root" else
    if (length(missing)) sprintf("pending re-run: %d of %d cells", length(intersect(need_key, have)),
                                 length(need_key)) else "included"
  if (status == "included") {
    rows <- rows[paste(rows$site, rows$plot, rows$rung, sep = "::") %in% need_key, , drop = FALSE]
    if (anyDuplicated(paste(rows$site, rows$plot, rows$rung)))
      stop("Duplicate cells for ", a$arm)
    if (is.null(rows$tp_core))                 # as pool() recovers it
      rows$tp_core <- ifelse(rows$n_det > 0, round(rows$precision * rows$n_det), 0)
    expect <- as.integer(nref_plot[paste(rows$site, rows$plot, sep = "::")])
    if (any(is.na(expect) | rows$n_ref != expect))
      stop("Reference of ", a$arm, " differs from the declared ", POP, " population")
  }
  list(status = data.frame(arm = a$arm, file = a$file, rungs = paste(rungs, collapse = ","),
                           status = status, cells_present = length(intersect(need_key, have)),
                           cells_required = length(need_key), stringsAsFactors = FALSE),
       rows = if (status == "included") rows else NULL)
}
# The headline root's part decides whether an arm is included; added rungs
# join only for the full-ladder arms, each part on its own.
load_arm <- function(a) {
  rungs <- strsplit(a$rungs, ",")[[1]]
  out <- list(load_part(a, parts[[1]], rungs))
  if ("1" %in% rungs) for (part in parts[-1]) out[[length(out) + 1]] <- load_part(a, part, part$rungs)
  keep <- function(r) {                      # scores plus the recall strata
    for (k in setdiff(MT_STRATUM_COLS, names(r))) r[[k]] <- NA_real_
    r[, c("site", "plot", "rung", "detector", "n_ref", "n_det", "TP", "precision",
          "tp_core", MT_STRATUM_COLS)]
  }
  list(status = do.call(rbind, lapply(out, `[[`, "status")),
       rows = if (is.null(out[[1]]$rows)) NULL else do.call(rbind, lapply(out, function(x)
         if (is.null(x$rows)) NULL else keep(x$rows))))
}

loaded <- lapply(split(MT_ARMS, seq_len(nrow(MT_ARMS))), load_arm)
arm_status <- do.call(rbind, lapply(loaded, `[[`, "status"))
rows <- do.call(rbind, lapply(loaded, `[[`, "rows"))
included <- arm_status$arm[arm_status$status == "included" & !duplicated(arm_status$arm)]
if (!length(included)) stop("No arm is complete on the sealed root yet")

## ---- nominal-box scores with paired intervals --------------------------------
eq <- mt_equal_support(rows, included)
if (length(attr(eq, "dropped")))
  stop("Included arms disagree on support: ", paste(head(attr(eq, "dropped")), collapse = ", "))

score_scope <- function(x, W, table, scope) {
  s <- mt_boot_scores(x, W, c("detector", "rung"))
  long <- mt_intervals(s)
  long <- cbind(table = table, population = POP, scope = scope, long)
  con <- do.call(rbind, lapply(unique(x$rung), function(r) {
    arms <- unique(x$detector[x$rung == r])
    if (length(arms) < 2) return(NULL)
    pairs <- combn(sort(arms), 2)
    do.call(rbind, lapply(seq_len(ncol(pairs)), function(i) do.call(rbind, lapply(
      c("recall", "precision", "F1"), function(m) cbind(rung = r, mt_contrast(
        s, paste(pairs[1, i], r, sep = "|"), paste(pairs[2, i], r, sep = "|"), m))))))
  }))
  if (!is.null(con)) con <- cbind(table = table, population = POP, scope = scope, con)
  list(long = long, contrasts = con)
}
# Five sites pooled, each region (when both are present) and each site.
scope_runs <- function(x, W, table) {
  res <- list(score_scope(x, W, table, "five sites"))
  site_of <- sub("::.*", "", rownames(W))
  for (rg in names(MT_REGIONS)) {
    sites <- intersect(MT_REGIONS[[rg]], unique(x$site))
    if (!length(sites) || setequal(sites, unique(x$site))) next
    keep <- site_of %in% sites
    res[[rg]] <- score_scope(x[x$site %in% sites, , drop = FALSE], W[keep, , drop = FALSE],
                             table, rg)
  }
  for (site in intersect(SITES, unique(x$site))) {
    keep <- grepl(paste0("^", site, "::"), rownames(W))
    res[[site]] <- score_scope(x[x$site == site, , drop = FALSE], W[keep, , drop = FALSE],
                               table, site)
  }
  list(long = do.call(rbind, lapply(res, `[[`, "long")),
       contrasts = do.call(rbind, lapply(res, `[[`, "contrasts")))
}
# Each rung is scored on its own equal set and resampled over its own plots:
# a sensitivity population can lack a few cells at one rung (a decimation that
# would upsample). Where every rung shares the plots, as in the headline
# population, every rung gets the same draws.
scope_by_rung <- function(x, table) {
  parts <- lapply(unique(x$rung), function(r) {
    xr <- x[x$rung == r, , drop = FALSE]
    scope_runs(xr, mt_plot_weights(xr$site, xr$plot, N_BOOT, SEED), table)
  })
  list(long = do.call(rbind, lapply(parts, `[[`, "long")),
       contrasts = do.call(rbind, lapply(parts, `[[`, "contrasts")))
}
nominal <- scope_by_rung(eq, "nominal box")

## ---- census-support scores ----------------------------------------------------
# score_census_support.R writes <rule>_ladder (the ladder arms, every rung)
# and <rule>_native (adds Li 2012); a cell scored in both is kept once.
# An added-rung part's job directory contributes its own rungs only.
census_rows <- function(rule) {
  x <- do.call(rbind, lapply(parts, function(part) {
    files <- file.path(part$dir, "census_support_scores", paste0(rule, c("_ladder", "_native")),
                       "census_support_scores.csv")
    y <- do.call(rbind, lapply(files[file.exists(files)], function(f)
      read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))))
    if (!is.null(y) && !is.null(part$rungs)) y <- y[y$rung %in% part$rungs, , drop = FALSE]
    y
  }))
  if (is.null(x)) return(NULL)
  x <- x[!duplicated(paste(x$site, x$plot, x$rung, x$detector)), , drop = FALSE]
  x[x$site %in% SITES & x$detector %in% included, , drop = FALSE]
}
census <- list(); census_counts <- list(); census_eq <- list()
for (rule in c("nearest", "exact")) {
  x <- census_rows(rule)
  if (is.null(x) || !nrow(x)) next
  cx <- mt_equal_support(x, unique(x$detector))
  census_eq[[rule]] <- cx
  label <- if (rule == "nearest") "census, nearest census (headline)" else
    "census, exact 2021 (check)"
  census[[rule]] <- scope_by_rung(cx, label)
  box <- transform(cx, TP = rect_TP, n_ref = rect_n_ref, n_det = rect_n_det,
                   tp_core = rect_tp_core, precision = rect_precision)
  census[[paste0(rule, "_box")]] <- scope_by_rung(box, paste(label, "- nominal box on the same plots"))
  one <- cx[cx$detector == cx$detector[1] & cx$rung == "native", , drop = FALSE]
  census_counts[[rule]] <- one
}

long <- do.call(rbind, c(list(nominal$long), lapply(census, `[[`, "long")))
long$status <- "included"
contrasts <- do.call(rbind, c(list(nominal$contrasts), lapply(census, `[[`, "contrasts")))
# Arms not yet complete on the root stay visible as explicit pending rows.
# A pending added-rung part names its rungs; a pending arm has no rung.
added <- duplicated(arm_status$arm)
pending <- arm_status[arm_status$status != "included", , drop = FALSE]
if (nrow(pending)) {
  pend <- long[rep(1, nrow(pending)), , drop = FALSE]
  pend[] <- NA
  pend$table <- "nominal box"; pend$population <- POP; pend$scope <- "five sites"
  pend$detector <- pending$arm; pend$status <- pending$status
  pend$rung <- ifelse(added[arm_status$status != "included"], pending$rungs, NA)
  long <- rbind(long, pend)
}
rownames(long) <- NULL
write.csv(long, file.path(OUT, "master_long.csv"), row.names = FALSE)
write.csv(contrasts, file.path(OUT, "master_contrasts.csv"), row.names = FALSE)
write.csv(arm_status, file.path(OUT, "arm_status.csv"), row.names = FALSE)

## ---- reference-population table -------------------------------------------------
field <- function(site) {
  nd <- file.path(d, "neon", site)
  list(gt = read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE),
       pc = read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE),
       vst = file.path(nd, "vst", paste0(tolower(site), "_vst_allyears.rds")))
}
fields <- setNames(lapply(SITES, field), SITES)
d17 <- intersect(c("SJER", "SOAP", "TEAK"), SITES)
ref_row <- function(id, study, rule, status, counts, source = "recomputed") {
  out <- data.frame(id = id, study = study, rule = rule, status = status, source = source,
                    stringsAsFactors = FALSE)
  for (site in SITES) {
    cnt <- counts[[site]]
    out[[paste0(site, "_plots")]] <- if (is.null(cnt)) NA_integer_ else cnt[1]
    out[[paste0(site, "_stems")]] <- if (is.null(cnt)) NA_integer_ else cnt[2]
  }
  out$total_plots <- sum(unlist(out[paste0(SITES, "_plots")]), na.rm = TRUE)
  out$total_stems <- sum(unlist(out[paste0(SITES, "_stems")]), na.rm = TRUE)
  out
}
by_site <- function(sites, fun) setNames(lapply(sites, function(s) {
  x <- fun(s); c(nrow(x), sum(x$n_core))
}), sites)
crown_gt <- function(s, gate = "all_mapped") {
  f <- fields[[s]]
  ids <- mt_field_crown_ids(f$vst)
  g <- ext_gate(ext_live_trees(f$gt), gate)
  g[g$individualID %in% ids, , drop = FALSE]
}
pop_counts <- function(p) setNames(lapply(SITES, function(s) {
  x <- pst[pst$population == p & pst$site == s, , drop = FALSE]
  c(length(unique(x$plotID)), nrow(x))
}), SITES)
iou <- list(SJER = c(8L, 69L), SOAP = c(18L, 231L), TEAK = c(20L, 386L))
ref <- rbind(
  ref_row("adopted", "Every paper table (headline)",
          "live mapped stems with DBH >= 10 cm in the plot-type core; plots with >= 6 such trees over the whole plot",
          "headline", pop_counts("adopted"), "population_stems.csv"),
  ref_row("all_mapped", "Sensitivity row; equals the historical D17 sweep at D17",
          "live mapped stems in the core; plots with >= 6 live mapped trees over the whole plot",
          "sensitivity", pop_counts("all_mapped"), "population_stems.csv"),
  ref_row("relaxed", "Sensitivity row: no six-stem plot gate",
          "as adopted, plots with >= 1 such tree", "sensitivity", pop_counts("relaxed"),
          "population_stems.csv"),
  ref_row("hist_sweep", "Density-ladder sweep, model benchmark, point-cloud study, matcher robustness, fusion, coverage gap (D17, June runs)",
          "as all_mapped", "historical",
          by_site(d17, function(s) mt_reference_counts(fields[[s]]$gt, fields[[s]]$pc, "all_mapped", 6L, "whole"))),
  ref_row("hist_native_ql2", "Native 3DEP cross-check (D17)",
          "live mapped stems in the core; plots with >= 6 of them inside the core (not the whole plot)",
          "historical",
          by_site(d17, function(s) mt_reference_counts(fields[[s]]$gt, fields[[s]]$pc, "all_mapped", 6L, "core"))),
  ref_row("hist_iou", "Instance IoU/PQ scorer (D17, June instance clouds)",
          "hist_sweep stems that captured at least one canopy point in the Voronoi-on-stems mask proxy (13 stems without a point excluded)",
          "historical", iou, "instance IoU/PQ report (depends on the old instance clouds)"),
  ref_row("hist_temporal", "Temporal sensitivity, exact-2021 cut (D17)",
          "hist_sweep stems measured in 2021, six-stem gate re-applied after the cut",
          "historical",
          by_site(d17, function(s) { g <- fields[[s]]$gt
            mt_reference_counts(g[!is.na(g$meas_year) & g$meas_year == 2021, , drop = FALSE],
                                fields[[s]]$pc, "all_mapped", 6L, "whole") })),
  ref_row("hist_crown", "Crown-diameter benchmark (D17)",
          "live mapped stems with a NEON field crown diameter (VST record nearest 2021); plots with >= 6 such trees over the whole plot",
          "historical",
          by_site(d17, function(s) mt_reference_counts(crown_gt(s), fields[[s]]$pc, "all_mapped", 6L, "whole"))),
  ref_row("adopted_crown", "Crown-diameter arms on the declared population",
          "adopted stems with a field crown diameter; adopted plots with >= 6 such trees",
          "crown sub-population",
          by_site(SITES, function(s) { x <- mt_reference_counts(crown_gt(s, "dbh10"), fields[[s]]$pc, "dbh10", 6L, "whole")
            x[x$plotID %in% pop$plotID[pop$site == s & pop$in_adopted], , drop = FALSE] })))
for (rule in names(census_counts)) {
  one <- census_counts[[rule]]
  lab <- if (rule == "nearest") "census_nearest" else "census_exact"
  cnt <- setNames(lapply(SITES, function(s) { x <- one[one$site == s, , drop = FALSE]
    if (!nrow(x)) c(0L, 0L) else c(nrow(x), sum(x$n_ref)) }), SITES)
  box <- setNames(lapply(SITES, function(s) { x <- one[one$site == s, , drop = FALSE]
    if (!nrow(x)) c(0L, 0L) else c(nrow(x), sum(x$rect_n_ref)) }), SITES)
  what <- if (rule == "nearest") "nearest all-growth-forms census within 4 years, census-event join, subplot exclusion" else
    "exact 2021 census"
  ref <- rbind(ref,
    ref_row(lab, "Censused-subplot precision", paste("census-event references inside the eroded censused interior of admitted plots;", what),
            if (rule == "nearest") "headline censused precision" else "check", cnt,
            "census_support_scores"),
    ref_row(paste0(lab, "_box"), "The same admitted plots, nominal-box reference",
            "adopted stems in the nominal core of the admitted plots", "comparison", box,
            "census_support_scores"))
}
write.csv(ref, file.path(OUT, "reference_population.csv"), row.names = FALSE)

## ---- measured density per rung ------------------------------------------------------
# Rungs are named by their all-return decimation target (points/m²); densities
# are reported as measured first-return pulses/m². Both are measured per cell in
# the clip manifest, over the population's usable cells.
pop_cells <- cm_all[cm_all$status == "ok" &
                  paste(cm_all$site, cm_all$plot) %in% paste(inpop$site, inpop$plotID), , drop = FALSE]
dens_row <- function(x, scope) data.frame(scope = scope, rung = x$rung[1], cells = nrow(x),
  points_median = median(x$pdens), pulses_median = median(x$frdens),
  pulses_q25 = unname(quantile(x$frdens, 0.25)), pulses_q75 = unname(quantile(x$frdens, 0.75)),
  stringsAsFactors = FALSE)
dens <- do.call(rbind, lapply(RUNG_ORDER, function(r) {
  x <- pop_cells[pop_cells$rung == r, , drop = FALSE]
  if (!nrow(x)) return(NULL)
  rbind(dens_row(x, "five sites"), do.call(rbind, lapply(SITES, function(s) {
    y <- x[x$site == s, , drop = FALSE]
    if (nrow(y)) dens_row(y, s) })))
}))
write.csv(dens, file.path(OUT, "rung_density.csv"), row.names = FALSE)
pooled_pulses <- setNames(dens$pulses_median[dens$scope == "five sites"],
                          dens$rung[dens$scope == "five sites"])

## ---- recall by crown class and height band ---------------------------------------
# On the nominal box's equal support and the same plot resamples as its scores.
# Detections carry no crown class, so strata have recall only.
stratum_scores <- function(x, table) do.call(rbind, lapply(unique(x$rung), function(r) {
  xr <- x[x$rung == r, , drop = FALSE]
  st <- do.call(rbind, lapply(split(xr, xr$detector), mt_stratum_rows))
  if (is.null(st)) return(NULL)
  bad <- unique(st$detector[is.na(st$TP) | is.na(st$n_ref)])
  st <- st[!st$detector %in% bad, , drop = FALSE]
  if (!nrow(st)) return(NULL)
  W <- mt_plot_weights(xr$site, xr$plot, N_BOOT, SEED)
  site_of <- sub("::.*", "", rownames(W))
  scopes <- c(list(`five sites` = SITES), MT_REGIONS)
  do.call(rbind, lapply(names(scopes), function(sc) {
    sites <- intersect(scopes[[sc]], unique(st$site))
    if (!length(sites) || (sc != "five sites" && setequal(sites, unique(st$site)))) return(NULL)
    s <- mt_boot_scores(st[st$site %in% sites, , drop = FALSE],
                        W[site_of %in% sites, , drop = FALSE], c("detector", "rung", "stratum"))
    cbind(table = table, population = POP, scope = sc, mt_intervals(s, "recall"))
  }))
}))
strata <- rbind(stratum_scores(eq, "nominal box"),
                if (!is.null(census_eq$nearest))
                  stratum_scores(census_eq$nearest, "census, nearest census (headline)"))
write.csv(strata, file.path(OUT, "master_strata.csv"), row.names = FALSE)

## ---- regions ------------------------------------------------------------------------
# Each arm's lead over CHM-VWF in California and in Washington, and their
# difference, paired over the plot resamples of the five-site scores.
region_leads <- function(x, table) do.call(rbind, lapply(unique(x$rung), function(r) {
  xr <- x[x$rung == r, , drop = FALSE]
  if (!"chm_vwf" %in% xr$detector) return(NULL)
  W <- mt_plot_weights(xr$site, xr$plot, N_BOOT, SEED)
  do.call(rbind, lapply(c("recall", "precision", "F1"), function(m) {
    z <- mt_region_leads(xr, W, "chm_vwf", metric = m)
    if (!is.null(z)) cbind(table = table, population = POP, z)
  }))
}))
leads <- rbind(region_leads(eq, "nominal box"),
               if (!is.null(census_eq$nearest))
                 region_leads(census_eq$nearest, "census, nearest census (headline)"))
write.csv(leads, file.path(OUT, "master_region_leads.csv"), row.names = FALSE)

## ---- rank stability -------------------------------------------------------------------
# Spearman correlation of the full-ladder arms' F1 at native density with
# their F1 at each decimated rung, with a plot-bootstrap interval.
rank_rows <- function(x, table) do.call(rbind, lapply(setdiff(RUNG_ORDER, "native"), function(r) {
  z <- mt_rank_stability(x, "native", r, N_BOOT, SEED)
  if (!is.null(z)) cbind(table = table, population = POP, z)
}))
rank <- rbind(rank_rows(eq, "nominal box"),
              if (!is.null(census_eq$nearest))
                rank_rows(census_eq$nearest, "census, nearest census (headline)"))
write.csv(rank, file.path(OUT, "master_rank_stability.csv"), row.names = FALSE)
# The interval resamples plots, not arms. Leave-out rows recompute each
# correlation without one full-ladder arm, and without the pair of arms whose
# changes are largest below the QL2 floor (SegmentAnyTree and AMS3D).
ladder_arms <- MT_ARMS$arm[MT_ARMS$rungs == "native,8,4,2,1"]
leave_sets <- c(as.list(ladder_arms), list(c("segmentanytree", "ams3d")))
leave_rows <- function(x, table) do.call(rbind, lapply(leave_sets, function(ex)
  do.call(rbind, lapply(setdiff(RUNG_ORDER, "native"), function(r) {
    z <- mt_rank_stability(x, "native", r, N_BOOT, SEED, exclude = ex)
    if (!is.null(z)) cbind(table = table, population = POP, left_out = paste(ex, collapse = "+"), z)
  }))))
leave <- rbind(leave_rows(eq, "nominal box"),
               if (!is.null(census_eq$nearest))
                 leave_rows(census_eq$nearest, "census, nearest census (headline)"))
write.csv(leave, file.path(OUT, "master_rank_leave_out.csv"), row.names = FALSE)

## ---- change across the ladder ----------------------------------------------------------
# Each arm's change from native density to every rung, paired on shared plots,
# over five sites, each region and each site.
ladder_scopes <- c(list(`five sites` = SITES), MT_REGIONS, setNames(as.list(SITES), SITES))
ladder_rows <- function(x, table) {
  z <- mt_rung_contrasts(x, ladder_scopes, n_boot = N_BOOT, seed = SEED)
  if (is.null(z)) NULL else cbind(table = table, population = POP, z)
}
ladder <- rbind(ladder_rows(eq, "nominal box"),
                if (!is.null(census_eq$nearest))
                  ladder_rows(census_eq$nearest, "census, nearest census (headline)"))
write.csv(ladder, file.path(OUT, "master_rung_contrasts.csv"), row.names = FALSE)

## ---- markdown --------------------------------------------------------------------
fmt <- function(e, l, u) ifelse(is.na(e), "—", sprintf("%.3f [%.3f, %.3f]", e, l, u))
md <- c("<!-- generated by scripts/master_tables.R -->", "")
headline <- function(tab, scope, title) {
  x <- long[long$table == tab & long$scope == scope & long$status == "included", , drop = FALSE]
  if (!nrow(x)) return(character())
  out <- c(paste0("### ", title), "",
           "| Arm | Rung | Pulses/m² | Plots | Stems | Recall | Precision | F1 |",
           "| --- | --- | --- | --- | --- | --- | --- | --- |")
  for (r in RUNG_ORDER) for (a in included) {
    y <- x[x$detector == a & x$rung == r, , drop = FALSE]
    if (!nrow(y)) next
    g <- function(m) { z <- y[y$metric == m, ]; fmt(z$estimate, z$lower, z$upper) }
    out <- c(out, sprintf("| %s | %s | %.1f | %d | %d | %s | %s | %s |", a, r,
                          pooled_pulses[[r]], y$n_plots[1], y$n_ref[1],
                          g("recall"), g("precision"), g("F1")))
  }
  c(out, "")
}
md <- c(md, headline("nominal box", "five sites", "Nominal box, five sites pooled"),
        headline("census, nearest census (headline)", "five sites",
                 "Censused subplots, nearest census, five sites pooled"))
md <- c(md, "### Measured density per rung", "",
        paste("Rung = all-return decimation target (points/m²); Pulses/m² = measured",
              "first-return density, median [interquartile range] over the population's cells.",
              "The Pulses/m² column of the tables above is the five-site median."), "",
        "| Scope | Rung | Cells | Points/m² (median) | Pulses/m² median [IQR] |",
        "| --- | --- | --- | --- | --- |",
        sprintf("| %s | %s | %d | %.1f | %.1f [%.1f, %.1f] |", dens$scope, dens$rung, dens$cells,
                dens$points_median, dens$pulses_median, dens$pulses_q25, dens$pulses_q75), "")
strata_md <- function(tab, rung, title) {
  x <- strata[strata$table == tab & strata$scope == "five sites" & strata$rung == rung, , drop = FALSE]
  if (is.null(x) || !nrow(x)) return(character())
  cols <- c("overstory", "understory", "dominant", "codominant", "intermediate", "suppressed")
  out <- c(paste0("### ", title), "",
           paste0("| Arm | ", paste(sprintf("%s (n = %d)", cols, vapply(cols, function(k)
             as.integer(x$n_ref[x$stratum == k][1]), integer(1))), collapse = " | "), " |"),
           paste0("| --- |", strrep(" --- |", length(cols))))
  for (a in intersect(included, x$detector)) {
    y <- x[x$detector == a, , drop = FALSE]
    out <- c(out, paste0("| ", a, " | ", paste(vapply(cols, function(k) {
      z <- y[y$stratum == k, ]; fmt(z$estimate, z$lower, z$upper) }, ""), collapse = " | "), " |"))
  }
  c(out, "")
}
md <- c(md, strata_md("nominal box", "native", "Recall by crown class, nominal box, native density, five sites"))
if (!is.null(leads) && nrow(leads)) {
  z <- leads[leads$table == "nominal box" & leads$rung == "native" & leads$metric == "F1", , drop = FALSE]
  if (nrow(z)) md <- c(md, "### F1 lead over CHM-VWF by region, nominal box, native density", "",
    "| Arm | California | Washington | California minus Washington |", "| --- | --- | --- | --- |",
    sprintf("| %s | %+.3f | %+.3f | %+.3f [%+.3f, %+.3f] |", z$arm, z$lead_california,
            z$lead_washington, z$estimate, z$lower, z$upper), "")
}
if (!is.null(rank) && nrow(rank))
  md <- c(md, "### Rank stability of the full-ladder arms", "",
          "Spearman correlation of F1 at native density with F1 at each rung.", "",
          "| Table | Rung | Arms | Plots | Spearman [95% interval] |", "| --- | --- | --- | --- | --- |",
          sprintf("| %s | %s | %d | %d | %s |", rank$table, rank$to, rank$arms, rank$n_plots,
                  fmt(rank$estimate, rank$lower, rank$upper)), "")
md <- c(md, "### Arm status", "", "| Arm | Status | Cells |", "| --- | --- | --- |",
        sprintf("| %s | %s | %d / %d |", arm_status$arm, arm_status$status,
                arm_status$cells_present, arm_status$cells_required), "")
writeLines(md, file.path(OUT, "master_tables.md"))

code <- vapply(c("master_tables.R", "master_tables_lib.R", "model_bench_lib.R"), .find, character(1))
contract <- list(population = POP, sites = SITES, n_boot = N_BOOT, seed = SEED,
                 clip_manifest_sha256 = root_id, included = included,
                 code_md5 = unname(tools::md5sum(code)))
if (length(parts) > 1)                       # rungs from their own roots (RUNG_JOBS)
  contract$rung_roots <- lapply(parts[-1], function(x)
    list(rungs = I(x$rungs), clip_manifest_sha256 = x$id))
jsonlite::write_json(contract, file.path(OUT, "master_contract.json"), auto_unbox = TRUE,
                     pretty = TRUE)
print(arm_status, row.names = FALSE)
cat(sprintf("wrote %s (%d rows), contrasts (%d rows), reference_population (%d rows)\n",
            file.path(OUT, "master_long.csv"), nrow(long), nrow(contrasts), nrow(ref)))
