#!/usr/bin/env Rscript
suppressMessages({ library(data.table); library(jsonlite) })

# Pool the FGI-EMIT thinning cells (docs/fgiemit-thinning-protocol.md): apex
# and mask F1 by density, arm and post-processing rule, from summed counts over
# the ten development plots, with a paired whole-plot bootstrap of each learned
# arm's apex lead over CHM-VWF and of each density's change from native.
# Native cells are the development matrix's (fixed filter; CHM-VWF at 0.25 m,
# the NEON rule at that density) plus the NEON reduction of their saved
# predictions. A density whose cells are not all present is reported as
# pending, not pooled. Reads development plots only; writes outside the root.
#   Rscript scripts/fgiemit_thinning_summary.R ROOT=<fgiemit root>
#     THIN=<thinning out dir> SELECT=<selection dir> OUT=<new dir>
#     [N_BOOT=1000] [SEED=20260923]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
ROOT <- normalizePath(A$ROOT, mustWork = TRUE)
THIN <- normalizePath(A$THIN, mustWork = TRUE)
SELECT <- normalizePath(A$SELECT, mustWork = TRUE)
OUT <- normalizePath(A$OUT, mustWork = FALSE)
for (p in c(THIN, OUT)) if (startsWith(p, paste0(ROOT, "/"))) stop("Outputs must be outside the FGI-EMIT root")
N_BOOT <- as.integer(if (is.null(A$N_BOOT)) 1000 else A$N_BOOT)
SEED <- as.integer(if (is.null(A$SEED)) 20260923 else A$SEED)
DEV <- c("1001", "1005", "1009", "1013", "1019", "1020", "1022", "1024", "1027", "1031")
PILOT <- c("1001", "1019", "1027")
LEARNED <- c("segmentanytree", "forestformer3d")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

dens <- fread(file.path(SELECT, "thinning_densities.csv"), colClasses = c(plot = "character"))
if (length(setdiff(dens$plot, DEV))) stop("Not a development plot in the selection")
LABELS <- c("native", dens[label != "native", unique(label)][order(-as.numeric(sub("pulses_", "",
  dens[label != "native", unique(label)])))])

read_cell <- function(file, plot, label, arm, rule) {
  if (!file.exists(file)) return(NULL)
  m <- fromJSON(file, simplifyVector = FALSE)
  det <- Filter(function(d) d$policy == "max_agl", m$detection)
  if (!length(det)) stop("No max_agl detection score in ", file)
  d <- det[[1]]
  mk <- if (length(m$mask)) m$mask[[1]] else NULL
  data.table(plot = plot, label = label, arm = arm, rule = rule,
             apex_TP = d$apex_TP, apex_FP = d$apex_FP, apex_FN = d$apex_FN,
             mask_TP = if (is.null(mk)) NA_integer_ else mk$TP,
             mask_FP = if (is.null(mk)) NA_integer_ else mk$FP,
             mask_FN = if (is.null(mk)) NA_integer_ else mk$FN)
}

cells <- rbindlist(lapply(DEV, function(p) {
  run <- if (p %in% PILOT) "development_pilot_v3" else "development_detector_run"
  native <- list(read_cell(file.path(ROOT, run, p, "chm_vwf", "metrics.json"), p, "native",
                           "chm_vwf", "NEON paper rule"))
  for (a in LEARNED) native <- c(native, list(
    read_cell(file.path(ROOT, run, p, a, "metrics.json"), p, "native", a, "fixed filter"),
    read_cell(file.path(THIN, "native", p, "native", a, "metrics_neon.json"), p, "native", a,
              "NEON reduction")))
  thinned <- lapply(setdiff(LABELS, "native"), function(l) {
    d <- file.path(THIN, "run", p, l)
    c(list(read_cell(file.path(d, "chm_vwf", "metrics.json"), p, l, "chm_vwf", "NEON paper rule")),
      unlist(lapply(LEARNED, function(a) list(
        read_cell(file.path(d, a, "metrics.json"), p, l, a, "fixed filter"),
        read_cell(file.path(d, a, "metrics_neon.json"), p, l, a, "NEON reduction"))),
        recursive = FALSE))
  })
  rbindlist(c(native, unlist(thinned, recursive = FALSE)))
}))
cells <- merge(cells, dens[, .(plot, label, frdens)], by = c("plot", "label"), all.x = TRUE)
fwrite(cells, file.path(OUT, "thinning_cells.csv"))

f1 <- function(tp, fp, fn) as.numeric(ifelse(2 * tp + fp + fn > 0, 2 * tp / (2 * tp + fp + fn), NA_real_))
pool <- function(x) x[, .(plots = .N, frdens = median(frdens),
  apex_TP = sum(apex_TP), apex_FP = sum(apex_FP), apex_FN = sum(apex_FN),
  apex_F1 = f1(sum(apex_TP), sum(apex_FP), sum(apex_FN)),
  mask_F1 = f1(sum(mask_TP), sum(mask_FP), sum(mask_FN))), by = .(label, arm, rule)]
pooled <- pool(cells)
pooled[, complete := plots == length(DEV)]
pooled[, label := factor(label, LABELS)]
setorder(pooled, label, arm, rule)
fwrite(pooled, file.path(OUT, "thinning_pooled.csv"))
expected <- CJ(label = factor(LABELS, LABELS), k = 1:5)[, `:=`(
  arm = c("chm_vwf", rep(LEARNED, each = 2))[k],
  rule = c("NEON paper rule", rep(c("fixed filter", "NEON reduction"), 2))[k])][, k := NULL]
pending <- merge(expected, pooled[, .(label, arm, rule, plots)], by = c("label", "arm", "rule"), all.x = TRUE)[
  is.na(plots) | plots < length(DEV)][is.na(plots), plots := 0L]
done <- pooled[complete == TRUE]

# Paired whole-plot bootstrap: resample plots once per draw and pool every
# complete cell group from the same draw.
set.seed(SEED)
draws <- replicate(N_BOOT, sample(DEV, replace = TRUE), simplify = FALSE)
boot <- rbindlist(lapply(seq_along(draws), function(b) {
  idx <- data.table(plot = draws[[b]])[, .(w = .N), by = plot]
  x <- merge(cells, idx, by = "plot")
  x[, .(draw = b, apex_F1 = f1(sum(w * apex_TP), sum(w * apex_FP), sum(w * apex_FN)),
        mask_F1 = f1(sum(w * mask_TP), sum(w * mask_FP), sum(w * mask_FN))),
    by = .(label, arm, rule)]
}))
boot <- boot[paste(label, arm, rule) %in% done[, paste(label, arm, rule)]]
ci <- function(v) as.list(quantile(v, c(0.025, 0.975), na.rm = TRUE, names = FALSE))

chm <- boot[arm == "chm_vwf", .(label, draw, chm_F1 = apex_F1)]
lead_b <- merge(boot[arm != "chm_vwf"], chm, by = c("label", "draw"))
lead_b[, lead := apex_F1 - chm_F1]
leads <- lead_b[, c(.(draws = .N), setNames(ci(lead), c("lower", "upper"))), by = .(label, arm, rule)]
pt <- merge(done[arm != "chm_vwf", .(label, arm, rule, apex_F1)],
            done[arm == "chm_vwf", .(label, chm_F1 = apex_F1)], by = "label")
leads <- merge(pt[, .(label, arm, rule, apex_F1, chm_F1, lead = apex_F1 - chm_F1)], leads,
               by = c("label", "arm", "rule"))
leads[, label := factor(label, LABELS)]; setorder(leads, arm, rule, label)
fwrite(leads, file.path(OUT, "thinning_leads.csv"))

nat <- boot[label == "native", .(arm, rule, draw, apex0 = apex_F1, mask0 = mask_F1)]
chg_b <- merge(boot[label != "native"], nat, by = c("arm", "rule", "draw"))
chg <- chg_b[, c(setNames(ci(apex_F1 - apex0), c("apex_lower", "apex_upper")),
                 setNames(ci(mask_F1 - mask0), c("mask_lower", "mask_upper"))), by = .(label, arm, rule)]
pn <- done[label == "native", .(arm, rule, apex0 = apex_F1, mask0 = mask_F1)]
chg <- merge(merge(done[label != "native", .(label, arm, rule, apex_F1, mask_F1)], pn,
                   by = c("arm", "rule"))[, .(label, arm, rule, apex_change = apex_F1 - apex0,
                                             mask_change = mask_F1 - mask0)],
             chg, by = c("label", "arm", "rule"))
chg[, label := factor(label, LABELS)]; setorder(chg, arm, rule, label)
fwrite(chg, file.path(OUT, "thinning_change.csv"))

# Lead change from native to each density, per arm and rule.
lc_b <- merge(lead_b[label != "native", .(label, arm, rule, draw, lead)],
              lead_b[label == "native", .(arm, rule, draw, lead0 = lead)], by = c("arm", "rule", "draw"))
lc <- lc_b[, c(setNames(ci(lead - lead0), c("lower", "upper"))), by = .(label, arm, rule)]
l0 <- leads[label == "native", .(arm, rule, lead0 = lead)]
lc <- merge(merge(leads[label != "native", .(label, arm, rule, lead)], l0, by = c("arm", "rule"))[
  , .(label, arm, rule, lead_change = lead - lead0)], lc, by = c("label", "arm", "rule"))
lc[, label := factor(label, LABELS)]; setorder(lc, arm, rule, label)
fwrite(lc, file.path(OUT, "thinning_lead_change.csv"))

options(width = 160)
cat("Pooled F1 by density\n"); print(done[, .(label, frdens = round(frdens, 2), arm, rule,
  apex_F1 = round(apex_F1, 3), mask_F1 = round(mask_F1, 3))], row.names = FALSE)
cat("\nLead over CHM-VWF (apex F1)\n"); print(leads[, .(label, arm, rule, lead = round(lead, 3),
  lower = round(lower, 3), upper = round(upper, 3))], row.names = FALSE)
cat("\nLead change from native\n"); print(lc[, lapply(.SD, function(v) if (is.numeric(v)) round(v, 3) else v)],
  row.names = FALSE)
if (nrow(pending)) { cat("\nPending (incomplete) groups\n"); print(pending[, .(label, arm, rule, plots)], row.names = FALSE) }
