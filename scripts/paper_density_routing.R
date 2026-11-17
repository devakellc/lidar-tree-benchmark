#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("model_bench_lib.R"))
source(.find("master_tables_lib.R"))
source(.find("density_routing_lib.R"))

# Density-routed detection pipeline. Designed after the five-site results
# were known, so it is a post hoc analysis of the paper runs; no detector is
# re-run. Each cell (one plot at one density level) falls in a band of its
# measured first-return density: A at 8 pulses/m² or more (QL1 or denser), B
# from 2 to below 8 (QL2 to QL1), C below 2 (below QL2). In each band a route
# runs the candidate with the highest pooled F1 on the California
# (development) cells: the GPU route chooses among the eight detectors run at
# every density level, the CPU route among the five classical ones. The
# native-only choice is each route's California best at the native level,
# used at every density; the single choice is its California best over all
# cells. Washington (the replication region) is the held-out check; there,
# the best candidate of each band is chosen on the same data and is
# descriptive only. Counts are the chance-agreement re-scores
# (paper_sensitivity.R MODE=null): the observed ("baseline") counts and each
# cell's mean counts over the 200 random shifts ("null"), pooled by summing
# counts; corrected F1 is (F1 - null F1) / (1 - null F1). Every score and
# paired difference carries a 95% percentile interval over the master tables'
# plot resamples (plots resampled within site, one set of draws shared by
# every detector, level, band and route; a plot's cells move together). The
# run stops unless every detector's per-level F1 equals the master tables and
# its corrected F1 equals the null re-score, estimate and interval, to 1e-9.
#   CLAUDE_JOB_DIR=<paper_runs> Rscript scripts/paper_density_routing.R
#     [POP=adopted] [FROZEN_ROOT=...] [RUNG_JOBS=<job dir>:<root>,...]
#     [MASTER=<master_tables dir>] [N_BOOT=1000] [SEED=20261002] [OUT=<dir>]
# RUNG_JOBS adds the levels frozen in their own root (the QL2 level), as for
# master_tables.R; it defaults to <job dir>/../paper_runs_ql2 with the root
# <job dir>/../neon/frozen_2021_ql2. Reads <job>/sensitivity/null_cells.csv
# of every part, each root's clip_manifest.csv and population.csv, and the
# master tables (master_long.csv, master_contract.json, rung_density.csv).
# Writes to OUT (default $CLAUDE_JOB_DIR/density_routing): routing_cells.csv,
# routing_bands.csv, routing_picks.csv, routing_scores.csv,
# routing_contrasts.csv, routing_check.csv, density_routing.md and
# routing_contract.json.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
KNOWN <- c("POP", "FROZEN_ROOT", "RUNG_JOBS", "MASTER", "N_BOOT", "SEED", "OUT")
if (length(setdiff(names(A), KNOWN)))
  stop("Unknown arguments: ", paste(setdiff(names(A), KNOWN), collapse = ", "))
arg <- function(k, default) if (is.null(A[[k]]) || !nzchar(A[[k]])) default else A[[k]]
d       <- .job_dir()
POP     <- arg("POP", "adopted")
ROOT    <- frozen_root(d, A[["FROZEN_ROOT"]])
MASTER  <- arg("MASTER", file.path(d, "master_tables"))
OUT     <- arg("OUT", file.path(d, "density_routing"))
N_BOOT  <- as.integer(arg("N_BOOT", MT_N_BOOT))
SEED    <- as.integer(arg("SEED", MT_SEED))
RUNG_JOBS <- strsplit(arg("RUNG_JOBS", paste0(file.path(dirname(d), "paper_runs_ql2"), ":",
                                              file.path(dirname(d), "neon", "frozen_2021_ql2"))),
                      ",", fixed = TRUE)[[1]]
TOL <- 1e-9
GPU <- DR_CANDIDATES$gpu                 # every candidate
SCOPES <- c(list(`five sites` = unlist(MT_REGIONS, use.names = FALSE)), MT_REGIONS)
ROLE <- c(`five sites` = "both regions", California = "selection data, in sample",
          Washington = "held out")
NAMES <- c(forestformer3d = "ForestFormer3D", segmentanytree = "SegmentAnyTree",
           treeisonet = "TreeisoNet", multichm = "`multichm`", chm_vwf = "CHM-VWF",
           ams3d = "AMS3D", ptrees = "`ptrees`", lmfauto = "`lmfauto`")
if (!frozen_sealed(ROOT)) stop("No sealed frozen root at ", ROOT)
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

## ---- inputs: one part per frozen root ---------------------------------------------
parts <- list(list(dir = d, root = ROOT, rungs = MT_RUNGS))
for (x in RUNG_JOBS) {
  p <- strsplit(x, ":", fixed = TRUE)[[1]]
  if (length(p) != 2) stop("RUNG_JOBS entries are <job dir>:<root>")
  if (!frozen_sealed(p[2])) stop("No sealed frozen root at ", p[2], " (set RUNG_JOBS=)")
  if (!identical(frozen_sha256(file.path(p[2], "population.csv")),
                 frozen_sha256(file.path(ROOT, "population.csv"))))
    stop("Root ", p[2], " declares a different population from ", ROOT)
  rr <- as.character(frozen_root_rungs(p[2]))
  if (any(rr %in% MT_RUNGS)) stop("Root ", p[2], " repeats levels of ", ROOT)
  parts[[length(parts) + 1]] <- list(dir = p[1], root = p[2], rungs = rr)
}
LEVELS <- c("native", as.character(sort(unique(as.numeric(c(
  MT_RUNGS[-1], unlist(lapply(parts[-1], `[[`, "rungs"))))), decreasing = TRUE)))
null_file <- function(part) file.path(part$dir, "sensitivity", "null_cells.csv")
read_part <- function(part) {
  f <- null_file(part)
  if (!file.exists(f)) stop("No chance-agreement cells at ", f,
                            "; run paper_sensitivity.R MODE=null K=200 first")
  x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  x <- x[x$rung %in% part$rungs & x$detector %in% GPU, , drop = FALSE]
  cm <- frozen_clip_manifest(part$root)
  cm <- cm[cm$rung %in% part$rungs, c("site", "plot", "rung", "status", "pdens", "frdens")]
  list(cells = x, manifest = cm)
}
raw <- lapply(parts, read_part)
cells <- do.call(rbind, lapply(raw, `[[`, "cells"))
manifest <- do.call(rbind, lapply(raw, `[[`, "manifest"))
names(cells)[names(cells) == "rung"] <- "level"
names(manifest)[names(manifest) == "rung"] <- "level"

# The master tables this analysis must reproduce: same population, resamples
# and sealed roots.
contract <- jsonlite::read_json(file.path(MASTER, "master_contract.json"), simplifyVector = TRUE)
if (!identical(contract$population, POP))
  stop("The master tables in ", MASTER, " are for population ", contract$population)
if (!identical(contract$clip_manifest_sha256, frozen_root_id(ROOT)))
  stop("The master tables were built on another root than ", ROOT)
for (part in parts[-1]) {
  rr <- contract$rung_roots
  hit <- if (is.null(rr)) integer() else
    which(vapply(seq_len(NROW(rr)), function(i) identical(as.character(unlist(rr$rungs[i])), part$rungs),
                 logical(1)))
  if (length(hit) != 1 || !identical(rr$clip_manifest_sha256[hit], frozen_root_id(part$root)))
    stop("The master tables do not record the root ", part$root, " for levels ",
         paste(part$rungs, collapse = ","))
}
interval_check <- N_BOOT == contract$n_boot && SEED == contract$seed

## ---- cells, population and bands -------------------------------------------------------
pop <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
inpop <- pop[pop[[paste0("in_", POP)]], , drop = FALSE]
plots <- sort(unique(paste(inpop$site, inpop$plotID, sep = "::")))
if (!setequal(unique(paste(cells$site, cells$plot, sep = "::")), plots))
  stop("The chance-agreement cells do not cover the declared ", POP, " population")
if (!setequal(unique(cells$variant), c("baseline", "null"))) stop("Expected baseline and null variants")
grid <- expand.grid(variant = c("baseline", "null"), plot = plots, level = LEVELS, detector = GPU,
                    stringsAsFactors = FALSE)
have <- paste(cells$variant, paste(cells$site, cells$plot, sep = "::"), cells$level, cells$detector)
want <- paste(grid$variant, grid$plot, grid$level, grid$detector)
if (anyDuplicated(have)) stop("Duplicate chance-agreement cells")
if (!setequal(have, want))
  stop("Incomplete chance-agreement cells: ", length(setdiff(want, have)), " missing, e.g. ",
       paste(head(setdiff(want, have), 3), collapse = "; "))
# The reference is the same stems for every detector, variant and level.
nref <- tapply(cells$n_ref, paste(cells$site, cells$plot), function(v) length(unique(v)))
if (any(nref != 1)) stop("A plot's reference differs between detectors, variants or levels")

dens <- merge(unique(cells[c("site", "plot", "level")]), manifest, by = c("site", "plot", "level"),
              all.x = TRUE)
if (anyNA(dens$status) || any(dens$status != "ok"))
  stop("A scored cell is not an ok cell of its root's clip manifest")
dens$band <- dr_band(dens$frdens)
dens$region <- ifelse(dens$site %in% MT_REGIONS$California, "California",
                      ifelse(dens$site %in% MT_REGIONS$Washington, "Washington", NA))
if (anyNA(dens$region)) stop("A site belongs to no region")
cells <- merge(cells, dens[c("site", "plot", "level", "frdens", "band")],
               by = c("site", "plot", "level"))
cells <- cells[c("variant", "site", "plot", "level", "detector", "frdens", "band", DR_COUNTS)]

# Five-site median density of each level, as rung_density.csv of the master tables.
level_pulses <- tapply(dens$frdens, dens$level, median)[LEVELS]
rd <- read.csv(file.path(MASTER, "rung_density.csv"), stringsAsFactors = FALSE,
               colClasses = c(rung = "character"))
rd <- rd[rd$scope == "five sites", , drop = FALSE]
rd_pulses <- rd$pulses_median[match(LEVELS, rd$rung)]
if (anyNA(rd_pulses) || any(abs(rd_pulses - level_pulses) > TOL))
  stop("Level densities differ from the master tables' rung_density.csv")
level_label <- function(l) sprintf("%.1f", level_pulses[l])

## ---- scoring ------------------------------------------------------------------------------
W <- mt_plot_weights(sub("::.*$", "", plots), sub("^[^:]*::", "", plots), N_BOOT, SEED)
GROUP <- c("variant", "policy", "slice")
# Each cell is scored in three slices: its band, "all" (every cell of the
# scope) and its density level ("level <name>", for the check below).
slices <- function(x) rbind(transform(x, slice = band), transform(x, slice = "all"),
                            transform(x, slice = paste("level", level)))
score_scope <- function(rows, sites) {
  keep <- sub("::.*$", "", rownames(W)) %in% sites
  Ws <- W[keep, , drop = FALSE]
  x <- slices(rows[rows$site %in% sites, , drop = FALSE])
  mt_boot_scores(dr_plot_rows(x, GROUP, rownames(Ws)), Ws, GROUP)
}
fixed <- transform(cells, policy = detector)
f1_of <- function(s, policy, slice) dr_metric(s, paste(policy, slice, sep = "|"), "F1")$e
band_scores <- function(s, slice_of = function(b) b, bands = DR_BANDS$band)
  do.call(rbind, lapply(bands, function(b) data.frame(
    band = b, detector = GPU, F1 = vapply(GPU, function(a) f1_of(s, a, slice_of(b)), numeric(1)),
    stringsAsFactors = FALSE)))

## ---- selection on the development region ------------------------------------------------
fixed_ca <- score_scope(fixed, SCOPES$California)
fixed_wa <- score_scope(fixed, SCOPES$Washington)
sel <- band_scores(fixed_ca)
routes <- lapply(DR_CANDIDATES, function(cand) dr_pick(sel, cand))
one_choice <- function(slice, cand) {
  p <- dr_pick(band_scores(fixed_ca, function(b) slice, "all"), cand)
  list(choice = p, picks = data.frame(band = DR_BANDS$band, pick = p$pick, stringsAsFactors = FALSE))
}
native <- lapply(DR_CANDIDATES, function(cand) one_choice("level native", cand))
single <- lapply(DR_CANDIDATES, function(cand) one_choice("all", cand))
wa_best <- lapply(DR_CANDIDATES, function(cand) dr_pick(band_scores(fixed_wa), cand))
POLICIES <- list(gpu_route = routes$gpu, cpu_route = routes$cpu,
                 gpu_native = native$gpu$picks, cpu_native = native$cpu$picks,
                 gpu_single = single$gpu$picks, cpu_single = single$cpu$picks,
                 gpu_wa_best = wa_best$gpu, cpu_wa_best = wa_best$cpu)
POLICY_LABEL <- c(gpu_route = "GPU route", cpu_route = "CPU route",
                  gpu_native = "Native-only choice, GPU", cpu_native = "Native-only choice, CPU",
                  gpu_single = "Single choice, GPU", cpu_single = "Single choice, CPU",
                  gpu_wa_best = "Washington best per band, GPU (descriptive)",
                  cpu_wa_best = "Washington best per band, CPU (descriptive)")
routed <- do.call(rbind, lapply(names(POLICIES), function(p) dr_route_cells(cells, POLICIES[[p]], p)))
S <- lapply(SCOPES, function(sites) score_scope(rbind(fixed, routed), sites))
# The selection scores are the California scores of the full run.
if (max(abs(sel$F1 - band_scores(S$California)$F1)) > 1e-12) stop("Selection scores changed")

## ---- the master tables and the null re-score must be reproduced ----------------------------
ml <- read.csv(file.path(MASTER, "master_long.csv"), stringsAsFactors = FALSE,
               colClasses = c(rung = "character"))
ml <- ml[ml$table == "nominal box" & ml$population == POP & ml$metric == "F1" &
           ml$status == "included" & ml$scope %in% names(SCOPES) & ml$detector %in% GPU, , drop = FALSE]
nd <- do.call(rbind, lapply(parts, function(part) {
  f <- file.path(part$dir, "sensitivity", "null_delta.csv")
  if (!file.exists(f)) stop("No null re-score table at ", f)
  x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  x[x$rung %in% part$rungs & x$stratum == "all" & x$metric == "F1_scaled" &
      x$scope %in% names(SCOPES) & x$detector %in% GPU, , drop = FALSE]
}))
here <- do.call(rbind, lapply(names(SCOPES), function(sc) do.call(rbind, lapply(GPU, function(a)
  do.call(rbind, lapply(LEVELS, function(l) {
    k <- paste(a, paste("level", l), sep = "|")
    f <- dr_estimate(S[[sc]], k, "F1"); cf <- dr_estimate(S[[sc]], k, "F1_corrected")
    data.frame(scope = sc, detector = a, level = l, F1 = f$estimate, F1_lower = f$lower,
               F1_upper = f$upper, F1c = cf$estimate, F1c_lower = cf$lower, F1c_upper = cf$upper,
               stringsAsFactors = FALSE)
  }))))))
ref_master <- data.frame(scope = ml$scope, detector = ml$detector, level = ml$rung,
                         F1 = ml$estimate, F1_lower = ml$lower, F1_upper = ml$upper,
                         stringsAsFactors = FALSE)
ref_null <- data.frame(scope = nd$scope, detector = nd$detector, level = nd$rung,
                       F1c = nd$estimate, F1c_lower = nd$lower, F1c_upper = nd$upper,
                       stringsAsFactors = FALSE)
cols_f1 <- if (interval_check) c("F1", "F1_lower", "F1_upper") else "F1"
cols_c <- if (interval_check) c("F1c", "F1c_lower", "F1c_upper") else "F1c"
bad_master <- dr_mismatch(here[c("scope", "detector", "level", cols_f1)], ref_master[c(
  "scope", "detector", "level", cols_f1)], c("scope", "detector", "level"), cols_f1, TOL)
bad_null <- dr_mismatch(here[c("scope", "detector", "level", cols_c)], ref_null[c(
  "scope", "detector", "level", cols_c)], c("scope", "detector", "level"), cols_c, TOL)
chk <- merge(merge(here, setNames(ref_master, c("scope", "detector", "level", "master_F1",
                                                "master_F1_lower", "master_F1_upper")),
                   all = TRUE), setNames(ref_null, c("scope", "detector", "level", "null_F1c",
                                                     "null_F1c_lower", "null_F1c_upper")), all = TRUE)
chk$max_abs_diff_F1 <- pmax(abs(chk$F1 - chk$master_F1), abs(chk$F1_lower - chk$master_F1_lower),
                            abs(chk$F1_upper - chk$master_F1_upper))
chk$max_abs_diff_F1c <- pmax(abs(chk$F1c - chk$null_F1c), abs(chk$F1c_lower - chk$null_F1c_lower),
                             abs(chk$F1c_upper - chk$null_F1c_upper))
chk <- chk[order(match(chk$scope, names(SCOPES)), match(chk$detector, GPU), match(chk$level, LEVELS)), ]
write.csv(chk, file.path(OUT, "routing_check.csv"), row.names = FALSE)
cat(sprintf("check: %d detector x level x scope rows; %d differ from the master tables, %d from the null re-score%s\n",
            nrow(here), nrow(bad_master), nrow(bad_null),
            if (interval_check) " (estimates and intervals)" else " (estimates only: other resamples)"))
if (nrow(bad_master) || nrow(bad_null)) {
  print(utils::head(rbind(bad_master[intersect(names(bad_master), c("scope", "detector", "level"))],
                          bad_null[intersect(names(bad_null), c("scope", "detector", "level"))]), 20))
  stop("The routing scores do not reproduce the master tables or the null re-score; see routing_check.csv")
}

## ---- outputs: cells and bands --------------------------------------------------------------
cell_out <- dens[order(dens$site, dens$plot, match(dens$level, LEVELS)),
                 c("site", "plot", "region", "level", "pdens", "frdens", "band")]
cell_out$level_pulses <- as.numeric(level_pulses[cell_out$level])
for (p in names(POLICIES)) cell_out[[p]] <- POLICIES[[p]]$pick[match(cell_out$band, POLICIES[[p]]$band)]
write.csv(cell_out, file.path(OUT, "routing_cells.csv"), row.names = FALSE)
nref_cell <- unique(cells[cells$variant == "baseline", c("site", "plot", "level", "n_ref")])
band_rows <- do.call(rbind, lapply(names(SCOPES), function(sc) do.call(rbind, lapply(DR_BANDS$band,
  function(b) {
    x <- dens[dens$site %in% SCOPES[[sc]] & dens$band == b, , drop = FALSE]
    r <- nref_cell[paste(nref_cell$site, nref_cell$plot, nref_cell$level) %in%
                     paste(x$site, x$plot, x$level), , drop = FALSE]
    out <- data.frame(scope = sc, band = b, label = DR_BANDS$label[DR_BANDS$band == b],
                      lower = DR_BANDS$lower[DR_BANDS$band == b], upper = DR_BANDS$upper[DR_BANDS$band == b],
                      cells = nrow(x), plots = length(unique(paste(x$site, x$plot))),
                      stems = sum(r$n_ref), frdens_median = median(x$frdens),
                      frdens_min = min(x$frdens), frdens_max = max(x$frdens), stringsAsFactors = FALSE)
    for (l in LEVELS) out[[paste0("cells_level_", l)]] <- sum(x$level == l)
    out
  }))))
write.csv(band_rows, file.path(OUT, "routing_bands.csv"), row.names = FALSE)

## ---- outputs: scores of every detector and policy ----------------------------------------
keys_of <- function(s) unique(sub("^[^|]*\\|", "", s$groups))
# Plots with a cell in a slice of a scope: all the scope's plots over every
# cell ("all") and at each level, fewer in a band. The pooled rows zero-fill
# a band's other plots, which mt_boot_scores()'s own n_plots counts too.
slice_plots <- function(sc, slice) {
  x <- dens[dens$site %in% SCOPES[[sc]], , drop = FALSE]
  keep <- if (slice %in% DR_BANDS$band) x$band == slice else
    if (startsWith(slice, "level ")) x$level == sub("^level ", "", slice) else
      if (identical(slice, "all")) rep(TRUE, nrow(x)) else stop("Unknown slice: ", slice)
  length(unique(paste(x$site, x$plot)[keep]))
}
# Pooled counts of each row: the observed (baseline) counts, except on the
# null F1 rows, which carry the null variant's own (each cell's mean counts
# over the random shifts).
scores <- do.call(rbind, lapply(names(SCOPES), function(sc) {
  s <- S[[sc]]
  est <- split(s$estimate, s$estimate$variant)
  do.call(rbind, lapply(keys_of(s), function(k) do.call(rbind, lapply(DR_METRICS, function(m) {
    v <- est[[if (m == "F1_null") "null" else "baseline"]]
    e <- v[paste(v$policy, v$slice, sep = "|") == k, , drop = FALSE]
    if (nrow(e) != 1) stop("Expected one pooled row for ", k)
    cbind(data.frame(scope = sc, role = ROLE[[sc]], policy = e$policy, slice = e$slice,
                     n_plots = slice_plots(sc, e$slice), n_ref = e$n_ref, n_det = e$n_det,
                     TP = e$TP, stringsAsFactors = FALSE), dr_estimate(s, k, m))
  }))))
}))
scores$kind <- ifelse(scores$policy %in% GPU, "detector", "policy")
scores <- scores[c("scope", "role", "kind", "policy", "slice", "n_plots", "n_ref", "n_det", "TP",
                   "metric", "estimate", "lower", "upper", "defined_draws")]
rownames(scores) <- NULL
write.csv(scores, file.path(OUT, "routing_scores.csv"), row.names = FALSE)
sc_get <- function(scope, policy, slice, metric = "F1")
  scores[scores$scope == scope & scores$policy == policy & scores$slice == slice &
           scores$metric == metric, , drop = FALSE]

## ---- outputs: paired differences ------------------------------------------------------------
MAIN <- c("gpu_route", "cpu_route", "gpu_native", "cpu_native", "gpu_single", "cpu_single")
pairs <- rbind(expand.grid(policy = MAIN, versus = GPU, stringsAsFactors = FALSE),
               data.frame(policy = c("gpu_route", "cpu_route", "gpu_route", "gpu_route", "cpu_route",
                                     "gpu_route", "cpu_route"),
                          versus = c("gpu_native", "cpu_native", "cpu_route", "gpu_single",
                                     "cpu_single", "gpu_wa_best", "cpu_wa_best"),
                          stringsAsFactors = FALSE))
SLICES <- c(DR_BANDS$band, "all")
contrasts <- do.call(rbind, lapply(names(SCOPES), function(sc) do.call(rbind, lapply(SLICES,
  function(sl) do.call(rbind, lapply(seq_len(nrow(pairs)), function(i) do.call(rbind, lapply(
    c("F1", "F1_corrected"), function(m) cbind(
      data.frame(scope = sc, role = ROLE[[sc]], slice = sl, policy = pairs$policy[i],
                 versus = pairs$versus[i], stringsAsFactors = FALSE),
      dr_contrast(S[[sc]], paste(pairs$policy[i], sl, sep = "|"),
                  paste(pairs$versus[i], sl, sep = "|"), m))))))))))
contrasts$descriptive <- grepl("_wa_best$", contrasts$versus)
rownames(contrasts) <- NULL
write.csv(contrasts, file.path(OUT, "routing_contrasts.csv"), row.names = FALSE)
ct_get <- function(scope, slice, policy, versus, metric = "F1")
  contrasts[contrasts$scope == scope & contrasts$slice == slice & contrasts$policy == policy &
              contrasts$versus == versus & contrasts$metric == metric, , drop = FALSE]

## ---- outputs: the picks and the held-out check ------------------------------------------------
picks <- do.call(rbind, lapply(names(DR_CANDIDATES), function(r) {
  p <- routes[[r]]; wb <- wa_best[[r]]
  do.call(rbind, lapply(seq_len(nrow(p)), function(i) {
    b <- p$band[i]; a <- p$pick[i]; best <- wb$pick[wb$band == b]
    g <- function(scope, det, m) sc_get(scope, det, b, m)
    ca <- g("California", a, "F1"); wa <- g("Washington", a, "F1"); wac <- g("Washington", a, "F1_corrected")
    fv <- g("five sites", a, "F1"); bw <- g("Washington", best, "F1"); bwc <- g("Washington", best, "F1_corrected")
    df <- ct_get("Washington", b, paste0(r, "_route"), paste0(r, "_wa_best"))
    dfc <- ct_get("Washington", b, paste0(r, "_route"), paste0(r, "_wa_best"), "F1_corrected")
    data.frame(route = r, band = b, label = DR_BANDS$label[DR_BANDS$band == b], pick = a,
               ca_F1 = ca$estimate, ca_F1_lower = ca$lower, ca_F1_upper = ca$upper,
               ca_runner_up = p$runner_up[i], ca_runner_up_F1 = p$runner_up_value[i],
               ca_margin = p$margin[i],
               wa_F1 = wa$estimate, wa_F1_lower = wa$lower, wa_F1_upper = wa$upper,
               wa_F1c = wac$estimate, wa_F1c_lower = wac$lower, wa_F1c_upper = wac$upper,
               wa_best = best, wa_best_F1 = bw$estimate, wa_best_F1_lower = bw$lower,
               wa_best_F1_upper = bw$upper, wa_best_F1c = bwc$estimate,
               wa_best_F1c_lower = bwc$lower, wa_best_F1c_upper = bwc$upper,
               pick_minus_best = df$estimate, pick_minus_best_lower = df$lower,
               pick_minus_best_upper = df$upper, pick_minus_best_c = dfc$estimate,
               pick_minus_best_c_lower = dfc$lower, pick_minus_best_c_upper = dfc$upper,
               five_F1 = fv$estimate, five_F1_lower = fv$lower, five_F1_upper = fv$upper,
               stringsAsFactors = FALSE)
  }))
}))
write.csv(picks, file.path(OUT, "routing_picks.csv"), row.names = FALSE)
choices <- do.call(rbind, c(
  lapply(names(DR_CANDIDATES), function(r) cbind(policy = paste0(r, "_native"),
    selected_on = "California, native level", native[[r]]$choice[c("pick", "value", "runner_up",
                                                                 "runner_up_value", "margin")])),
  lapply(names(DR_CANDIDATES), function(r) cbind(policy = paste0(r, "_single"),
    selected_on = "California, all cells", single[[r]]$choice[c("pick", "value", "runner_up",
                                                              "runner_up_value", "margin")]))))

## ---- markdown ---------------------------------------------------------------------------------
nm <- function(a) unname(NAMES[a])
fmt <- function(x, signed = FALSE) dr_fmt(x$estimate, x$lower, x$upper, signed)
num <- function(v, signed = FALSE) gsub("-", "−", sprintf(if (signed) "%+.3f" else "%.3f", v),
                                        fixed = TRUE)
md <- c("<!-- generated by scripts/paper_density_routing.R -->", "",
        "Post hoc: designed after the five-site results were known. Selection uses the",
        "California (development) cells only; Washington is the held-out check.", "")
bt <- band_rows
md <- c(md, "### Bands of measured first-return density", "",
        paste0("| Band | Pulses/m² | Scope | Cells | Plots | Stems | Median pulses/m² [range] | ",
               paste(sprintf("Cells at %s", level_label(LEVELS)), collapse = " | "), " |"),
        paste0("| --- | --- | --- | ---: | ---: | ---: | --- |", strrep(" ---: |", length(LEVELS))),
        sprintf("| %s (%s) | %s | %s | %d | %d | %s | %.1f [%.2f, %.2f] | %s |", bt$band, bt$label,
                ifelse(is.infinite(bt$upper), sprintf("≥ %g", bt$lower),
                       ifelse(bt$lower == 0, sprintf("< %g", bt$upper), sprintf("%g to < %g", bt$lower, bt$upper))),
                bt$scope, bt$cells, bt$plots, formatC(bt$stems, big.mark = ",", format = "d"),
                bt$frdens_median, bt$frdens_min, bt$frdens_max,
                apply(bt[paste0("cells_level_", LEVELS)], 1, paste, collapse = " | ")), "")
md <- c(md, "### Decision table and held-out check", "",
        paste("Pick: highest pooled F1 on the California cells of the band. Washington best:",
              "chosen on the Washington cells themselves (descriptive). Corrected F1 at 4 m."), "",
        paste("| Band | Route | Pick | California F1 | Runner-up (margin) | Washington F1 |",
              "Washington corrected F1 | Washington best | Its F1 | Pick minus best, F1 |",
              "Pick minus best, corrected F1 |"),
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        sprintf("| %s | %s | %s | %s | %s (%s) | %s | %s | %s | %s | %s | %s |", picks$band,
                toupper(picks$route), nm(picks$pick),
                dr_fmt(picks$ca_F1, picks$ca_F1_lower, picks$ca_F1_upper),
                nm(picks$ca_runner_up), num(picks$ca_margin, TRUE),
                dr_fmt(picks$wa_F1, picks$wa_F1_lower, picks$wa_F1_upper),
                dr_fmt(picks$wa_F1c, picks$wa_F1c_lower, picks$wa_F1c_upper), nm(picks$wa_best),
                dr_fmt(picks$wa_best_F1, picks$wa_best_F1_lower, picks$wa_best_F1_upper),
                dr_fmt(picks$pick_minus_best, picks$pick_minus_best_lower, picks$pick_minus_best_upper, TRUE),
                dr_fmt(picks$pick_minus_best_c, picks$pick_minus_best_c_lower, picks$pick_minus_best_c_upper, TRUE)),
        "")
md <- c(md, "### Choices made once for every density", "",
        "| Choice | Candidates | Selected on | Pick | Its F1 | Runner-up (margin) |",
        "| --- | --- | --- | --- | --- | --- |",
        sprintf("| %s | %s | %s | %s | %s | %s (%s) |", sub(", (GPU|CPU)$", "", POLICY_LABEL[choices$policy]),
                toupper(sub("_.*", "", choices$policy)), choices$selected_on, nm(choices$pick),
                num(choices$value), nm(choices$runner_up), num(choices$margin, TRUE)), "")
for (sc in names(SCOPES)) {
  rows <- vapply(GPU, function(a) paste(vapply(DR_BANDS$band, function(b)
    paste(fmt(sc_get(sc, a, b, "F1")), fmt(sc_get(sc, a, b, "F1_corrected")), sep = " | "),
    character(1)), collapse = " | "), character(1))
  mark <- function(a) paste(c(if (a %in% routes$gpu$pick) paste0("GPU ", paste(routes$gpu$band[routes$gpu$pick == a], collapse = "")),
                              if (a %in% routes$cpu$pick) paste0("CPU ", paste(routes$cpu$band[routes$cpu$pick == a], collapse = ""))),
                            collapse = ", ")
  md <- c(md, sprintf("### Every candidate by band, %s (%s)", sc, ROLE[[sc]]), "",
          "| Detector | Picked in | A: F1 | A: corrected F1 | B: F1 | B: corrected F1 | C: F1 | C: corrected F1 |",
          "| --- | --- | --- | --- | --- | --- | --- | --- |",
          sprintf("| %s | %s | %s |", nm(GPU), vapply(GPU, mark, character(1)), rows), "")
}
wa_rows <- do.call(rbind, lapply(names(DR_CANDIDATES), function(r) do.call(rbind, lapply(DR_BANDS$band,
  function(b) {
    a <- routes[[r]]$pick[routes[[r]]$band == b]
    do.call(rbind, lapply(setdiff(DR_CANDIDATES[[r]], a), function(v) data.frame(
      band = b, route = toupper(r), pick = nm(a), versus = nm(v),
      best = v == wa_best[[r]]$pick[wa_best[[r]]$band == b],
      F1 = fmt(ct_get("Washington", b, paste0(r, "_route"), v), TRUE),
      F1c = fmt(ct_get("Washington", b, paste0(r, "_route"), v, "F1_corrected"), TRUE),
      stringsAsFactors = FALSE)))
  }))))
md <- c(md, "### Washington: each pick against every other candidate of its band", "",
        "Paired differences, pick minus candidate; the Washington best is marked (descriptive).", "",
        "| Band | Route | Pick | Versus | Pick minus candidate, F1 | Pick minus candidate, corrected F1 |",
        "| --- | --- | --- | --- | --- | --- |",
        sprintf("| %s | %s | %s | %s%s | %s | %s |", wa_rows$band, wa_rows$route, wa_rows$pick,
                wa_rows$versus, ifelse(wa_rows$best, " (Washington best)", ""), wa_rows$F1, wa_rows$F1c), "")
pol_rows <- c(MAIN, "gpu_wa_best", "cpu_wa_best", GPU)
lab <- function(p) ifelse(p %in% GPU, nm(p), POLICY_LABEL[p])
md <- c(md, "### Every cell pooled: policies and fixed detectors", "",
        "| Policy or detector | Five sites, F1 | Five sites, corrected F1 | California, F1 | California, corrected F1 | Washington, F1 | Washington, corrected F1 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
        sprintf("| %s | %s |", lab(pol_rows), vapply(pol_rows, function(p) paste(unlist(lapply(names(SCOPES),
          function(sc) c(fmt(sc_get(sc, p, "all", "F1")), fmt(sc_get(sc, p, "all", "F1_corrected"))))),
          collapse = " | "), character(1))), "")
for (p in MAIN[1:4]) {
  vs <- c(GPU, if (p == "gpu_route") c("gpu_native", "cpu_route", "gpu_single", "gpu_wa_best"),
          if (p == "cpu_route") c("cpu_native", "cpu_single", "cpu_wa_best"))
  md <- c(md, sprintf("### %s: against fixed detectors and other choices, every cell", POLICY_LABEL[p]), "",
          "| Versus | Five sites, F1 | Five sites, corrected F1 | California, F1 | California, corrected F1 | Washington, F1 | Washington, corrected F1 |",
          "| --- | --- | --- | --- | --- | --- | --- |",
          sprintf("| %s | %s |", lab(vs), vapply(vs, function(v) paste(unlist(lapply(names(SCOPES),
            function(sc) c(fmt(ct_get(sc, "all", p, v), TRUE), fmt(ct_get(sc, "all", p, v, "F1_corrected"), TRUE)))),
            collapse = " | "), character(1))), "")
}
md <- c(md, "### Native-only choice against the route, by band", "",
        "| Band | Compute | Native-only choice | Route's pick | Scope | Route minus native-only, F1 | Route minus native-only, corrected F1 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
        unlist(lapply(names(DR_CANDIDATES), function(r) unlist(lapply(DR_BANDS$band, function(b)
          vapply(names(SCOPES), function(sc) sprintf("| %s | %s | %s | %s | %s | %s | %s |", b, toupper(r),
            nm(native[[r]]$choice$pick), nm(routes[[r]]$pick[routes[[r]]$band == b]), sc,
            fmt(ct_get(sc, b, paste0(r, "_route"), paste0(r, "_native")), TRUE),
            fmt(ct_get(sc, b, paste0(r, "_route"), paste0(r, "_native"), "F1_corrected"), TRUE)),
            character(1)))))), "")
writeLines(md, file.path(OUT, "density_routing.md"))

## ---- contract -----------------------------------------------------------------------------------
code <- vapply(c("paper_density_routing.R", "density_routing_lib.R", "master_tables_lib.R"), .find,
               character(1))
# Inputs by role and hash, not by path, so a rebuilt copy compares equal.
part_inputs <- do.call(rbind, lapply(parts, function(part) {
  lv <- paste(part$rungs, collapse = ",")
  data.frame(input = paste0(c("null_cells.csv", "null_delta.csv", "clip_manifest.csv"), ", levels ", lv),
             sha256 = vapply(c(null_file(part), file.path(part$dir, "sensitivity", "null_delta.csv"),
                               file.path(part$root, "clip_manifest.csv")), frozen_sha256, character(1)),
             row.names = NULL, stringsAsFactors = FALSE)
}))
mt_files <- c("master_long.csv", "master_contract.json", "rung_density.csv")
inputs <- rbind(part_inputs, data.frame(input = paste("master tables,", mt_files),
  sha256 = vapply(file.path(MASTER, mt_files), frozen_sha256, character(1)), row.names = NULL,
  stringsAsFactors = FALSE), data.frame(input = "population.csv",
  sha256 = frozen_sha256(file.path(ROOT, "population.csv")), stringsAsFactors = FALSE))
jsonlite::write_json(list(
  post_hoc = TRUE, population = POP, n_boot = N_BOOT, seed = SEED, levels = LEVELS,
  bands = DR_BANDS, candidates = DR_CANDIDATES, selection = "highest pooled F1 on the California cells",
  picks = lapply(POLICIES, function(p) setNames(as.list(p$pick), p$band)),
  check = list(rows = nrow(here), intervals = interval_check, tolerance = TOL),
  inputs = inputs, code_md5 = unname(tools::md5sum(code))),
  file.path(OUT, "routing_contract.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)

print(picks[c("route", "band", "pick", "ca_F1", "ca_runner_up", "ca_margin", "wa_F1", "wa_best",
              "wa_best_F1", "pick_minus_best", "pick_minus_best_lower", "pick_minus_best_upper")],
      row.names = FALSE, digits = 3)
print(choices, row.names = FALSE, digits = 3)
cat(sprintf("wrote %s\n", paste(file.path(OUT, c("routing_cells.csv", "routing_bands.csv", "routing_picks.csv",
                                                 "routing_scores.csv", "routing_contrasts.csv",
                                                 "routing_check.csv", "density_routing.md",
                                                 "routing_contract.json")), collapse = "\n      ")))
