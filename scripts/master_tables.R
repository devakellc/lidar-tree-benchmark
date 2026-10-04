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
# One row per benchmark arm: the results file it writes, the rungs it is run
# at, and the stamped directory or resume sidecar that ties it to the root.
MT_ARMS <- data.frame(
  arm = c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d", "li2012",
          "forestformer3d", "treeisonet", "segmentanytree", "deepforest",
          "detectree2", "sam2point"),
  file = c(rep("lidrplugins_results.csv", 4), "ams3d_results.csv", "li2012_results.csv",
           "forestformer3d_results.csv", "treeisonet_results.csv",
           "segmentanytree_results.csv", "deepforest_results.csv",
           "detectree2_results.csv", "sam2point_results.csv"),
  rungs = c(rep("native,8,4,2,1", 5), "native", rep("native,8,4,2,1", 3),
            "native", "native", "native"),
  provenance = c("chm_vwf_detections", "multichm_detections", "lmfauto_detections",
                 "ptrees_detections", "ams3d_instances", "li2012_instances",
                 "forestformer3d_results.csv.frozen", "treeisonet_instances",
                 "segmentanytree_results.csv.frozen", "deepforest_results.csv.frozen",
                 "detectree2_results.csv.frozen", "sam2point_instances"),
  # The RGB arms have no density ladder: they write rung "rgb", scored once
  # per plot against the same reference, and join the native rung here.
  result_rung = c(rep(NA, 9), "rgb", "rgb", NA),
  # SAM2Point writes its arm as "sam2point_seeded", next to the bare CHM-VWF
  # seeds it was prompted with ("chm_vwf_seeds", a diagnostic, not an arm).
  detector = c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d", "li2012",
               "forestformer3d", "treeisonet", "segmentanytree", "deepforest",
               "detectree2", "sam2point_seeded"),
  stringsAsFactors = FALSE)

pop  <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
pst  <- read.csv(file.path(ROOT, "population_stems.csv"), stringsAsFactors = FALSE)
cm   <- frozen_clip_manifest(ROOT)
inpop <- pop[pop$site %in% SITES & pop[[paste0("in_", POP)]], , drop = FALSE]
nref_plot <- table(paste(pst$site[pst$population == POP], pst$plotID[pst$population == POP],
                         sep = "::"))
root_id <- frozen_root_id(ROOT)

provenance_ok <- function(site, what) {
  path <- file.path(d, "neon", site, what)
  if (grepl("\\.frozen$", what)) {
    if (!file.exists(path)) return(FALSE)
    id <- jsonlite::read_json(path, simplifyVector = TRUE)
    return(identical(id$clip_manifest_sha256, root_id) && identical(id$population, POP))
  }
  dir.exists(path) && frozen_stamp_check(path, ROOT, strict = FALSE)
}

load_arm <- function(a) {
  rungs <- strsplit(a$rungs, ",")[[1]]
  need <- cm[cm$status == "ok" & cm$rung %in% rungs &
               paste(cm$site, cm$plot) %in% paste(inpop$site, inpop$plotID), , drop = FALSE]
  need_key <- paste(need$site, need$plot, need$rung, sep = "::")
  rows <- do.call(rbind, lapply(SITES, function(site) {
    f <- file.path(d, "neon", site, a$file)
    if (!file.exists(f)) return(NULL)
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x <- x[x$detector == a$detector, , drop = FALSE]
    x$detector <- rep(a$arm, nrow(x))
    if (!is.na(a$result_rung)) x$rung[x$rung == a$result_rung] <- "native"
    if (nrow(x) && is.null(x$site)) x$site <- site
    x
  }))
  have <- if (is.null(rows)) character() else paste(rows$site, rows$plot, rows$rung, sep = "::")
  stamped <- all(vapply(SITES, provenance_ok, logical(1), what = a$provenance))
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
  list(status = data.frame(arm = a$arm, file = a$file, rungs = a$rungs, status = status,
                           cells_present = length(intersect(need_key, have)),
                           cells_required = length(need_key), stringsAsFactors = FALSE),
       rows = if (status == "included") rows else NULL)
}

loaded <- lapply(split(MT_ARMS, seq_len(nrow(MT_ARMS))), load_arm)
arm_status <- do.call(rbind, lapply(loaded, `[[`, "status"))
rows <- do.call(rbind, lapply(loaded, function(x)
  if (is.null(x$rows)) NULL else x$rows[, c("site", "plot", "rung", "detector", "n_ref",
                                             "n_det", "TP", "precision", "tp_core")]))
included <- arm_status$arm[arm_status$status == "included"]
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
scope_runs <- function(x, W, table) {
  res <- list(score_scope(x, W, table, "five sites"))
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
census_rows <- function(rule) {
  files <- file.path(d, "census_support_scores", paste0(rule, c("_ladder", "_native")),
                     "census_support_scores.csv")
  x <- do.call(rbind, lapply(files[file.exists(files)], function(f)
    read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))))
  if (is.null(x)) return(NULL)
  x <- x[!duplicated(paste(x$site, x$plot, x$rung, x$detector)), , drop = FALSE]
  x[x$site %in% SITES & x$detector %in% included, , drop = FALSE]
}
census <- list(); census_counts <- list()
for (rule in c("nearest", "exact")) {
  x <- census_rows(rule)
  if (is.null(x) || !nrow(x)) next
  cx <- mt_equal_support(x, unique(x$detector))
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
pending <- arm_status[arm_status$status != "included", , drop = FALSE]
if (nrow(pending)) {
  pend <- long[rep(1, nrow(pending)), , drop = FALSE]
  pend[] <- NA
  pend$table <- "nominal box"; pend$population <- POP; pend$scope <- "five sites"
  pend$detector <- pending$arm; pend$status <- pending$status
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

## ---- markdown --------------------------------------------------------------------
fmt <- function(e, l, u) ifelse(is.na(e), "—", sprintf("%.3f [%.3f, %.3f]", e, l, u))
md <- c("<!-- generated by scripts/master_tables.R -->", "")
headline <- function(tab, scope, title) {
  x <- long[long$table == tab & long$scope == scope & long$status == "included", , drop = FALSE]
  if (!nrow(x)) return(character())
  out <- c(paste0("### ", title), "",
           "| Arm | Rung | Plots | Stems | Recall | Precision | F1 |",
           "| --- | --- | --- | --- | --- | --- | --- |")
  for (r in MT_RUNGS) for (a in included) {
    y <- x[x$detector == a & x$rung == r, , drop = FALSE]
    if (!nrow(y)) next
    g <- function(m) { z <- y[y$metric == m, ]; fmt(z$estimate, z$lower, z$upper) }
    out <- c(out, sprintf("| %s | %s | %d | %d | %s | %s | %s |", a, r, y$n_plots[1],
                          y$n_ref[1], g("recall"), g("precision"), g("F1")))
  }
  c(out, "")
}
md <- c(md, headline("nominal box", "five sites", "Nominal box, five sites pooled"),
        headline("census, nearest census (headline)", "five sites",
                 "Censused subplots, nearest census, five sites pooled"))
md <- c(md, "### Arm status", "", "| Arm | Status | Cells |", "| --- | --- | --- |",
        sprintf("| %s | %s | %d / %d |", arm_status$arm, arm_status$status,
                arm_status$cells_present, arm_status$cells_required), "")
writeLines(md, file.path(OUT, "master_tables.md"))

code <- vapply(c("master_tables.R", "master_tables_lib.R", "model_bench_lib.R"), .find, character(1))
jsonlite::write_json(list(population = POP, sites = SITES, n_boot = N_BOOT, seed = SEED,
                          clip_manifest_sha256 = root_id, included = included,
                          code_md5 = unname(tools::md5sum(code))),
                     file.path(OUT, "master_contract.json"), auto_unbox = TRUE, pretty = TRUE)
print(arm_status, row.names = FALSE)
cat(sprintf("wrote %s (%d rows), contrasts (%d rows), reference_population (%d rows)\n",
            file.path(OUT, "master_long.csv"), nrow(long), nrow(contrasts), nrow(ref)))
