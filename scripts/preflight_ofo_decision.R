#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("ofo_reference_lib.R"))
source(.find("ofo_preflight_lib.R"))   # stage records

# Decision stage of the Open Forest Observatory preflight
# (docs/ofo-preflight-protocol.md, "Scoring cells", "Plot groups" and
# "Decision per group"). Score-blind: joins the gates of the catalogue,
# registration and conditions stages per plot, cuts every registered candidate
# plot into 40 m scoring cells, counts reference stems under each group's
# floor and decides go / hold / no-go per group. Counts for the decision use
# admitted plots only; cells of registered plots that fail a gate are kept so
# the summary shows what each gate costs.
# Inputs (OFO = $CLAUDE_JOB_DIR/ofo): OFO/preflight/{plots,trees,flights,
#   geometry_audit,licences,registration,conditions}.csv and
#   registration_tests.json (the final admission is its top-level `admitted`).
#   The run stops unless the records of the earlier stages (flights_record,
#   geometry_record, conditions_record, registration_catalog_record .json)
#   match the current files: each stage's tables must come from the current
#   plots, trees, flights and clouds.
# Outputs: <OUT>/{cells,plot_admission,group_summary,group_decision}.csv and
#   decision_record.json (input and output digests, signals, floors). OUT defaults to
#   OFO/preflight; another OUT (a smoke run) must lie under OFO or outside the
#   job directory. prepare_ofo_reference.R reads the default location unless
#   given PRE=<OUT>.
# Second protocol (docs/ofo-preflight-protocol-2.md):
#   IN2=<dir>   registration.csv, conditions.csv and registration_tests.json are
#               read from <dir>, where preflight_ofo2_assemble.R writes them with
#               assemble_record.json; the run stops unless that record lists them
#               among its outputs and matches the files now in <dir> and, for its
#               `inputs_preflight`, in OFO/preflight. The other tables still come
#               from OFO/preflight. OUT must then lie elsewhere than OFO/preflight,
#               whose decision is never rewritten. decision_record.json adds
#               inputs2_dir and inputs2 (the digests of the three files).
#   GROUPS=A,B  the output tables keep the plots, cells and rows of these groups
#               only (every number is computed as without it); the record adds
#               `groups`.
# Without IN2 and GROUPS the run, its outputs and its record are unchanged.
#   Rscript scripts/preflight_ofo_decision.R [OUT=<dir>] [IN2=<dir>] [GROUPS=A,B]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
unknown <- setdiff(names(A), c("OUT", "IN2", "GROUPS"))
if (length(unknown)) stop("Unknown argument(s): ", paste(unknown, collapse = ", "),
                          "; preflight_ofo_decision.R takes OUT=, IN2= and GROUPS=")
job <- normalizePath(.job_dir(), mustWork = FALSE)
OFO <- file.path(job, "ofo")
pre <- file.path(OFO, "preflight")
out_dir <- if (is.null(A$OUT) || !nzchar(A$OUT)) pre else A$OUT
# Nothing of this study is written under the job directory outside OFO.
if (!ofo_output_allowed(out_dir, job, OFO))
  stop("OUT must lie under ", OFO, " or outside the job directory (no `..`): ", out_dir)
in2 <- if (is.null(A$IN2) || !nzchar(A$IN2)) NULL else A$IN2
if (!is.null(in2)) {
  if (!dir.exists(in2)) stop("IN2 is not a directory: ", in2)
  in2 <- normalizePath(in2)
  if (identical(ofo_path_resolve(out_dir), ofo_path_resolve(pre)))
    stop("With IN2= pass an OUT= other than ", pre, ": the first protocol's decision is ",
         "never rewritten")
}
groups <- if (is.null(A$GROUPS) || !nzchar(A$GROUPS)) NULL else
  strsplit(A$GROUPS, ",", fixed = TRUE)[[1]]
if (!is.null(groups) && (!length(groups) || any(!groups %in% OFO_GROUPS) ||
                         anyDuplicated(groups)))
  stop("GROUPS must be distinct groups among ", paste(OFO_GROUPS, collapse = ","), ": ",
       A$GROUPS)

## ---- inputs ------------------------------------------------------------------
# Every stage table must have been computed from the current upstream tables
# (a conditions table older than the clouds it describes is refused).
stale <- ofo_check_records(pre, c(
  flights_record.json = "preflight_ofo_catalog.R STEPS=flights",
  geometry_record.json = "preflight_ofo_catalog.R STEPS=geometry",
  conditions_record.json = "preflight_ofo_conditions.R",
  registration_catalog_record.json = "preflight_ofo_registration.R STAGE=catalog"))
IN2_FILES <- c("registration.csv", "conditions.csv", "registration_tests.json")
if (!is.null(in2)) {
  arec_path <- file.path(in2, "assemble_record.json")
  arec <- if (file.exists(arec_path)) tryCatch(jsonlite::read_json(arec_path),
                                               error = function(e) NULL)
  bad <- if (!file.exists(arec_path)) "is missing" else if (is.null(arec)) "is unreadable" else {
    b <- ofo_record_mismatch(arec, in2)
    if (length(arec$inputs_preflight)) {
      if (is.null(arec$preflight_dir) ||
          !identical(ofo_path_resolve(arec$preflight_dir), ofo_path_resolve(pre)))
        b <- c(b, sprintf("its first-protocol inputs were read in %s, not %s",
                          arec$preflight_dir, pre))
      b <- c(b, ofo_record_mismatch(list(inputs = arec$inputs_preflight), pre))
    }
    miss <- setdiff(IN2_FILES, names(arec$outputs))
    if (length(miss)) b <- c(b, sprintf("%s not among its outputs", paste(miss, collapse = ", ")))
    b
  }
  if (length(bad))
    stale <- c(stale, sprintf("assemble_record.json in %s: %s; rerun preflight_ofo2_assemble.R",
                              in2, paste(bad, collapse = "; ")))
}
if (length(stale))
  stop("Stage outputs do not match the current inputs:\n  ", paste(stale, collapse = "\n  "),
       call. = FALSE)
if (is.null(in2)) {
  in_sha <- ofo_sha256(pre, c(names(OFO_INPUT_COLUMNS), "registration_tests.json"))
} else {
  in_sha <- ofo_sha256(pre, setdiff(names(OFO_INPUT_COLUMNS), IN2_FILES))
  in_sha2 <- ofo_sha256(in2, IN2_FILES)
}
reg_dir <- if (is.null(in2)) pre else in2
plots <- ofo_read_input(pre, "plots.csv")
trees <- ofo_read_input(pre, "trees.csv")
flights <- ofo_read_input(pre, "flights.csv")
geometry <- ofo_read_input(pre, "geometry_audit.csv")
licences <- ofo_read_input(pre, "licences.csv")
registration <- ofo_read_input(reg_dir, "registration.csv")
conditions <- ofo_read_input(reg_dir, "conditions.csv")
tests_path <- file.path(reg_dir, "registration_tests.json")
if (!file.exists(tests_path)) stop("Missing input ", tests_path, call. = FALSE)
tests_js <- jsonlite::read_json(tests_path, simplifyVector = TRUE)
signals <- ofo_signals_admitted(tests_js)
# Protocol 2 records which signals' tests could not be made; protocol 1 has no
# such key, and the decision rule is then unchanged.
inconclusive <- if (is.null(tests_js$inconclusive)) NULL else
  vapply(c("height", "rank"), function(s) isTRUE(tests_js$inconclusive[[s]]), logical(1))
bad <- ofo_check_inputs(plots, trees, flights, geometry, licences, registration)
if (length(bad)) stop("Inconsistent inputs:\n  ", paste(bad, collapse = "\n  "), call. = FALSE)
cat(sprintf("inputs: %d plots, %d trees, %d flights, %d registration rows, %d conditions rows\n",
            nrow(plots), nrow(trees), nrow(flights), nrow(registration), nrow(conditions)))
cat(sprintf("signals admitted: height %s, rank %s\n", signals[["height"]], signals[["rank"]]))

## ---- admission -----------------------------------------------------------------
adm <- ofo_plot_admission(plots, flights, geometry, conditions, registration)
pidx <- match(adm$plot_id, plots$plot_id)
adm$live_floor_cm <- as.numeric(plots$live_floor_cm[pidx])
lic <- licences$license_short[match(adm$plot_id, licences$plot_id)]
adm$license_short <- ifelse(is.na(lic), plots$license_short[pidx], lic)
adm$archive_mode <- ofo_archive_mode(adm$license_short)
sel <- if (is.null(groups)) TRUE else adm$group %in% groups
odd <- sel & (adm$conditions_check %in% c("unattributed", "inconsistent") |
  (adm$conditions_check == "missing" & adm$flight_admitted))
if (any(odd))
  warning(sprintf("conditions gate not attributable for %d plot(s): %s", sum(odd),
                  paste(sprintf("%s(%s)", adm$plot_id[odd], adm$conditions_check[odd]),
                        collapse = ", ")), call. = FALSE)

## ---- cells and counts --------------------------------------------------------
loc <- ofo_locate(plots, trees, registration)
# C/D groups without an admitted plot have no floor; for display only, their
# plots are counted at the group's largest live floor.
grp_plots <- plots[plots$group %in% OFO_GROUPS & plots$project_name != OFO_NEON_PROJECT, ]
fallback <- tapply(as.numeric(grp_plots$live_floor_cm), grp_plots$group,
                   function(v) if (any(is.finite(v))) max(v, na.rm = TRUE) else NA_real_)
area <- setNames(as.numeric(plots$polygon_area_m2[pidx]), adm$plot_id)
main <- ofo_counts_under(adm, loc, adm$admitted, area, fallback)
# The hold rule: plots failing only unchecked conditions admitted too, with
# the C/D floors of that larger set.
hold <- ofo_counts_under(adm, loc, adm$admitted | adm$unchecked_only, area, fallback)
adm$floor_cm <- main$plot_floor
adm$floor_basis <- ifelse(is.na(adm$group), "ungrouped",
  ifelse(is.na(main$floors$floor_cm[match(adm$group, main$floors$group)]),
         "group_plots", "admitted_plots"))
adm <- cbind(adm, main$counts[, -1])
adm$n_ref_headline_hold <- hold$counts$n_ref_headline

summary <- ofo_group_summary(adm)
decision <- ofo_group_decision(adm, signals, main$floors, hold$floors,
                               inconclusive = inconclusive)
# GROUPS=: the same numbers, the tables restricted to those groups.
if (!is.null(groups)) {
  adm <- adm[adm$group %in% groups, , drop = FALSE]
  summary <- summary[summary$group %in% groups, , drop = FALSE]
  decision <- decision[decision$group %in% groups, , drop = FALSE]
}

## ---- outputs -----------------------------------------------------------------
cells <- main$cells
if (!is.null(groups)) cells <- cells[cells$plot_id %in% adm$plot_id, , drop = FALSE]
cells$plot_admitted <- adm$admitted[match(cells$plot_id, adm$plot_id)]
cells$floor_cm <- main$plot_floor[cells$plot_id]
cells <- cells[, c("plot_id", "project_name", "group", "cell", "cell_id", "cx", "cy", "epsg",
                   "inside_share", "n_ref", "headline", "plot_admitted", "floor_cm",
                   "offset_x", "offset_y")]
adm_out <- adm[, c("plot_id", "project_name", "group", OFO_GATES, "admitted", "reason",
                   "n_cells", "n_cells_headline", "n_ref_plot", "n_ref_cells",
                   "n_ref_headline", "area_plot_m2", "area_cells_m2", "screen",
                   "conditions_check", "unchecked_only", "floor_cm", "floor_basis",
                   "live_floor_cm", "license_short", "archive_mode", "n_ref_headline_hold",
                   "flight_reason", "conditions_reason", "registration_reason")]
# Protocol 2: whether a failed registration is evidence or only unchecked, and
# which cells belong to plots placed provisionally (at their method estimate,
# for the hold count only). Protocol 1's tables keep their columns.
if ("registration_check" %in% names(adm)) {
  adm_out$registration_check <- adm$registration_check
  cells$provisional <- adm$registration_check[match(cells$plot_id, adm$plot_id)] %in% "unchecked"
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
data.table::fwrite(cells, file.path(out_dir, "cells.csv"))
data.table::fwrite(adm_out, file.path(out_dir, "plot_admission.csv"))
data.table::fwrite(summary, file.path(out_dir, "group_summary.csv"))
data.table::fwrite(decision, file.path(out_dir, "group_decision.csv"))
if (!identical(ofo_sha256(pre, names(in_sha)), in_sha) ||
    (!is.null(in2) && !identical(ofo_sha256(in2, names(in_sha2)), in_sha2)))
  stop("Inputs changed during the run; rerun preflight_ofo_decision.R", call. = FALSE)
outs <- c("cells.csv", "plot_admission.csv", "group_summary.csv", "group_decision.csv")
record <- list(
  inputs_dir = pre,
  inputs = as.list(in_sha),
  outputs_dir = out_dir,
  outputs = as.list(ofo_sha256(out_dir, outs)),
  code_sha256 = setNames(lapply(c("preflight_ofo_decision.R", "ofo_reference_lib.R"),
    function(f) digest::digest(file = .find(f), algo = "sha256")),
    c("preflight_ofo_decision.R", "ofo_reference_lib.R")),
  signals_admitted = as.list(signals), floors = main$floors, floors_if_unchecked = hold$floors,
  cell = list(size_m = OFO_CELL_SIZE, step_m = OFO_CELL_STEP, min_inside = OFO_CELL_MIN_INSIDE,
              headline_min_stems = OFO_HEADLINE_MIN),
  decision = decision[, c("group", "decision")])
if (!is.null(in2))
  record <- append(record, list(inputs2_dir = in2, inputs2 = as.list(in_sha2)), after = 2L)
if (!is.null(groups)) record$groups <- groups
jsonlite::write_json(record, file.path(out_dir, "decision_record.json"), auto_unbox = TRUE,
                     pretty = TRUE, digits = NA)

## ---- report ------------------------------------------------------------------
cat(sprintf("\nnon-NEON plots %d; with a group %d; registered %d; admitted %d; ",
            nrow(adm), sum(adm$group %in% OFO_GROUPS), sum(adm$registered), sum(adm$admitted)))
cat(sprintf("failing only unchecked conditions %d\n", sum(adm$unchecked_only)))
prov <- if ("provisional" %in% names(cells)) cells$provisional %in% TRUE else
  rep(FALSE, nrow(cells))
cat(sprintf("cells of registered plots %d (headline %d); of admitted plots %d (headline %d)\n",
            sum(!prov), sum(cells$headline & !prov),
            sum(cells$plot_admitted), sum(cells$headline & cells$plot_admitted)))
if ("provisional" %in% names(cells))
  cat(sprintf("provisional cells (unchecked registrations, hold count only) %d (headline %d)\n",
              sum(cells$provisional), sum(cells$headline & cells$provisional)))
cat("\ngroup x project (cells/stems/area: admitted plots; *_registered: all registered):\n")
show <- c("group", "project_name", "plots", "flight_admitted", "geometry_consistent",
          "conditions_admitted", "registered", "admitted", "plots_with_headline",
          "unchecked_only", "floor_cm", "cells", "headline_cells", "ref_headline",
          "cells_registered", "ref_headline_registered")
print(summary[, show], row.names = FALSE)
# Rule 2 counts admitted plots; the reasons also give how many hold a headline cell.
cat("\ndecision per group:\n")
for (i in seq_len(nrow(decision)))
  cat(sprintf("  %s  %-5s  %s\n", decision$group[i], decision$decision[i], decision$reasons[i]))
cat(sprintf("\nwrote %s/{cells,plot_admission,group_summary,group_decision}.csv\n", out_dir))
