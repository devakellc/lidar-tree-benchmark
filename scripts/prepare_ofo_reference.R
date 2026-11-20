#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("ofo_reference_lib.R"))
source(.find("ofo_preflight_lib.R"))   # stage records
source(.find("neon_spatial_lib.R"))
source(.find("site_extension_lib.R"))

# Writes the field reference of the Open Forest Observatory groups decided go
# by preflight_ofo_decision.R, in the schema of scripts/neon_ground_truth.R, so
# the benchmark's arms can read it unchanged (one "tower" plot per 40 m
# scoring cell). Each reference directory is one SITE= of the arms and holds
# one project, one group and one acquisition year (ofo_site_plan()): named by
# project, by <PROJECT>_<GROUP> when the project has admitted plots in more
# than one go group, and suffixed _<YEAR> when its plots were flown in more
# than one year. Groups B and D carry no heights (match on position alone).
# Hold and no-go groups authorise nothing: asking for one stops. Never writes
# outside OFO (every output path is resolved, symlinks included, before the
# check); an existing reference directory or stems table is replaced
# only with FORCE=TRUE, and a reference directory that the current naming does
# not produce stops the run (move it aside), so stale sites cannot be pooled.
# The decision must be current: every input and output digest in
# decision_record.json must match the files now in OFO/preflight.
# Inputs (OFO = $CLAUDE_JOB_DIR/ofo): OFO/preflight/{group_decision,
#   plot_admission,cells,plots,trees,flights,registration}.csv and
#   decision_record.json.
# Outputs: OFO/reference/neon/<SITE>/{ground_truth_stems,plot_centroids}.csv,
#   OFO/reference/stems_all.csv (every catalogue tree of every non-NEON plot,
#   registered position where available, flags) and
#   OFO/reference/reference_record.json (project, group, year and name of every
#   directory, written or not).
# PRE=<dir> (the second protocol, docs/ofo-preflight-protocol-2.md): the decision
#   directory, OFO/preflight2 say, where preflight_ofo_decision.R IN2= OUT=<dir>
#   wrote decision_record.json, group_decision.csv, plot_admission.csv and
#   cells.csv. plots, trees and flights are still read from OFO/preflight (the
#   record's inputs_dir) and registration.csv from the record's inputs2_dir;
#   every digest of the record must match, and its outputs_dir must be <dir>.
#   The reference is then written under <dir>/reference instead, and
#   reference_record.json names the decision directory. Without PRE= nothing
#   changes.
#   Rscript scripts/prepare_ofo_reference.R [GROUPS=<go groups>] [FORCE=FALSE] [PRE=<dir>]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
unknown <- setdiff(names(A), c("GROUPS", "FORCE", "PRE"))
if (length(unknown)) stop("Unknown argument(s): ", paste(unknown, collapse = ", "))
FORCE <- isTRUE(as.logical(if (is.null(A$FORCE)) "FALSE" else A$FORCE))
OFO <- normalizePath(file.path(.job_dir(), "ofo"), mustWork = FALSE)
pre <- file.path(OFO, "preflight")
ref <- file.path(OFO, "reference")
dec <- pre
if (!is.null(A$PRE) && nzchar(A$PRE) &&
    !identical(ofo_path_resolve(A$PRE), ofo_path_resolve(pre))) {
  if (!ofo_path_under(A$PRE, OFO)) stop("PRE must lie under ", OFO, ": ", A$PRE)
  if (!dir.exists(A$PRE)) stop("PRE is not a directory: ", A$PRE)
  dec <- normalizePath(A$PRE)
  ref <- file.path(dec, "reference")
}

## ---- decision and inputs -----------------------------------------------------
# The decision tables must describe the current inputs: plot_admission.csv is
# not trusted once any table it was computed from has changed.
rec_path <- file.path(dec, "decision_record.json")
if (!file.exists(rec_path)) stop("Missing ", rec_path, "; run preflight_ofo_decision.R")
rec <- jsonlite::read_json(rec_path)
if (is.null(rec$inputs_dir) ||
    !identical(ofo_path_resolve(rec$inputs_dir), ofo_path_resolve(pre)))
  stop("decision_record.json describes inputs in ", rec$inputs_dir, ", not ", pre,
       "; rerun preflight_ofo_decision.R")
if (!identical(dec, pre) && (is.null(rec$outputs_dir) ||
    !identical(ofo_path_resolve(rec$outputs_dir), ofo_path_resolve(dec))))
  stop("decision_record.json describes outputs in ", rec$outputs_dir, ", not ", dec,
       "; rerun preflight_ofo_decision.R")
if (!length(rec$inputs) || !length(rec$outputs))
  stop("decision_record.json lacks input or output digests; rerun preflight_ofo_decision.R")
# Inputs under OFO/preflight, outputs in the decision directory (the same by
# default), and the second protocol's inputs where the record says.
bad <- c(ofo_record_mismatch(list(inputs = rec$inputs), pre),
         ofo_record_mismatch(list(outputs = rec$outputs), dec))
reg_dir <- pre
if (!is.null(rec$inputs2_dir)) {
  reg_dir <- rec$inputs2_dir
  bad <- c(bad, ofo_record_mismatch(list(inputs = rec$inputs2), reg_dir))
  if (!"registration.csv" %in% names(rec$inputs2))
    bad <- c(bad, "registration.csv is not among the record's inputs2")
}
if (length(bad))
  stop("The decision is not current; rerun preflight_ofo_decision.R:\n  ",
       paste(bad, collapse = "\n  "))
decision <- ofo_read_input(dec, "group_decision.csv", c("group", "decision", "floor_cm"))
adm <- ofo_read_input(dec, "plot_admission.csv", c("plot_id", "project_name", "group",
                                                   "admitted", "floor_cm"))
cells_dec <- ofo_read_input(dec, "cells.csv", c("plot_id", "project_name", "group", "cell",
  "cell_id", "cx", "cy", "epsg", "inside_share", "n_ref", "headline"))
go <- decision$group[decision$decision == "go"]
groups <- if (is.null(A$GROUPS)) go else strsplit(A$GROUPS, ",", fixed = TRUE)[[1]]
if (any(!groups %in% OFO_GROUPS)) stop("GROUPS must be among ", paste(OFO_GROUPS, collapse = ","))
if (any(!groups %in% go))
  stop("Not go (hold and no-go authorise nothing): ", paste(sprintf("%s=%s",
       setdiff(groups, go), decision$decision[match(setdiff(groups, go), decision$group)]),
       collapse = ", "))
if (!length(groups)) {
  cat("No go group in group_decision.csv; nothing written.\n")
  quit(save = "no", status = 0)
}

plots <- ofo_read_input(pre, "plots.csv")
trees <- ofo_read_input(pre, "trees.csv")
flights <- ofo_read_input(pre, "flights.csv")
registration <- ofo_read_input(reg_dir, "registration.csv")

## ---- rebuild cells and check them against the decision ------------------------
loc <- ofo_locate(plots, trees, registration)
adm$admitted <- ofo_lgl(adm$admitted) %in% TRUE
floors <- ofo_group_floors(transform(adm, live_floor_cm =
  as.numeric(plots$live_floor_cm[match(adm$plot_id, plots$plot_id)])))
fd <- decision$floor_cm[match(floors$group, decision$group)]
if (!isTRUE(all.equal(floors$floor_cm[floors$group %in% groups], fd[floors$group %in% groups])))
  stop("Group floors differ from group_decision.csv; rerun preflight_ofo_decision.R")
plot_floor <- setNames(as.numeric(adm$floor_cm), adm$plot_id)
cells <- ofo_count_cells(loc$cells, loc$stems, plot_floor)
take <- adm$plot_id[adm$admitted & adm$group %in% groups]
cells <- cells[cells$plot_id %in% take, , drop = FALSE]
cd <- cells_dec[cells_dec$plot_id %in% take, , drop = FALSE]
key <- function(x) paste(x$cell_id, round(x$cx, 3), round(x$cy, 3), x$n_ref)
if (!setequal(key(cells), key(cd)))
  stop("Cells differ from cells.csv (inputs changed?); rerun preflight_ofo_decision.R")
if (!nrow(cells)) stop("The go groups hold no scoring cell; nothing to write")

## ---- reference directories: one project, group and year each ----------------------
# Named over every go group, so a GROUPS= subset writes the same names.
plan <- ofo_site_plan(adm, flights, go)
site_of <- setNames(plan$site, plan$plot_id)
gt <- ofo_ground_truth(loc$stems, plots, flights, cells, floors, site_of)
pc <- ofo_plot_centroids(cells, plots, flights, site_of)
sites <- ofo_site_table(plan, pc)
sites$written <- sites$group %in% groups & sites$n_cells > 0
sites$note <- ifelse(sites$written, "",
                     ifelse(!sites$group %in% groups, "group not requested", "no scoring cell"))
write_sites <- sites$site[sites$written]

## ---- guards: paths inside OFO, no silent overwrite, no stale site --------------------
dirs <- file.path(ref, "neon", write_sites)
# Every path written, resolved through its deepest existing ancestor (a
# symlink under OFO pointing into the NEON root is refused), lies under OFO.
targets <- c(dirs, file.path(dirs, "ground_truth_stems.csv"),
             file.path(dirs, "plot_centroids.csv"), file.path(ref, "stems_all.csv"),
             file.path(ref, "reference_record.json"))
neon_root <- ofo_path_resolve(file.path(.job_dir(), "neon"))
out_ok <- vapply(targets, function(p) ofo_path_under(p, OFO) &&
                   !ofo_path_within(ofo_path_resolve(p), neon_root), logical(1))
if (!all(out_ok))
  stop("Refusing to write outside ", OFO, ": ", paste(targets[!out_ok], collapse = ", "))
old <- list.dirs(file.path(ref, "neon"), full.names = FALSE, recursive = FALSE)
old <- old[file.exists(file.path(ref, "neon", old, "ground_truth_stems.csv"))]
# Directories of go groups not requested now stay valid; anything else is stale.
valid <- sites$site[sites$written | !sites$group %in% groups]
stale <- setdiff(old, valid)
if (length(stale))
  stop("Reference directories outside the current naming exist; move them aside: ",
       paste(file.path(ref, "neon", stale), collapse = ", "))
exists <- c(dirs[dir.exists(dirs)], file.path(ref, "stems_all.csv")[file.exists(
  file.path(ref, "stems_all.csv"))])
if (length(exists) && !FORCE)
  stop("Reference output exists; pass FORCE=TRUE to replace it: ",
       paste(exists, collapse = ", "))

## ---- per site, validated as the arms read it, before anything is written ---------
for (s in write_sites) {
  g <- gt[gt$site == s, , drop = FALSE]
  c0 <- pc[pc$site == s, , drop = FALSE]
  id <- ofo_check_site_tables(g, c0, s)
  i <- match(s, sites$site)
  if (!identical(c(id$project, id$group), c(sites$project_name[i], sites$group[i])) ||
      id$acquisition_year != sites$acquisition_year[i])
    stop(s, ": tables disagree with the directory plan")
  # The checks freeze_clips.R (live trees) and run_sweep.R (all rows) apply.
  neon_reference_epoch(g, id$acquisition_year)
  neon_validate_inputs(ext_live_trees(g), c0)
  neon_validate_inputs(g, c0)
  inv <- ext_plot_inventory(ext_gate(ext_live_trees(g), "dbh10"), c0)
  want <- c0$n_ref[match(inv$plotID, c0$plotID)]
  if (any(inv$n_core != want)) stop(s, ": benchmark gate counts differ from cell n_ref")
}
for (k in seq_along(write_sites)) {
  s <- write_sites[k]
  dir.create(dirs[k], recursive = TRUE, showWarnings = FALSE)
  # write.csv as neon_ground_truth.R does: NA as "NA", so read.csv keeps
  # missing character fields (crown_class, canopyPosition) as NA, not "".
  write.csv(pc[pc$site == s, , drop = FALSE], file.path(dirs[k], "plot_centroids.csv"),
            row.names = FALSE)
  write.csv(gt[gt$site == s, , drop = FALSE], file.path(dirs[k], "ground_truth_stems.csv"),
            row.names = FALSE)
}

## ---- every catalogue tree with its flags ----------------------------------------
st <- loc$stems
pa <- adm[match(st$plot_id, adm$plot_id), , drop = FALSE]
st$project_name <- plots$project_name[match(st$plot_id, plots$plot_id)]
st$group <- pa$group
# Reference under the plot's floor from plot_admission.csv (group floor; 10 cm
# for plots without a group).
st$ref <- ofo_reference_flag(st, plot_floor[st$plot_id])
st$headline <- st$cell_id %in% cells_dec$cell_id[ofo_lgl(cells_dec$headline) %in% TRUE]
st$admitted <- pa$admitted %in% TRUE
st$in_reference <- st$individual_id %in% gt$individualID[gt$site %in% write_sites]
st$site <- unname(site_of[st$plot_id])
stems_all <- st[, c("plot_id", "project_name", "group", "individual_id", "tree_n",
                    "contributor_tree_id", "x", "y", "shift_dx", "shift_dy", "E", "N",
                    "pos_unc", "dbh", "height", "live_dead", "live", "is_tree", "inside",
                    "in_polygon", "ref", "cell_id", "headline", "admitted", "in_reference",
                    "site")]
dir.create(ref, recursive = TRUE, showWarnings = FALSE)
data.table::fwrite(stems_all, file.path(ref, "stems_all.csv"))

files <- c(file.path(dirs, "ground_truth_stems.csv"), file.path(dirs, "plot_centroids.csv"),
           file.path(ref, "stems_all.csv"))
naming <- paste("one directory per project; <PROJECT>_<GROUP> for every group of a project",
                "with admitted plots in more than one go group; _<YEAR> (flight year)",
                "appended when a directory's admitted plots were flown in more than one year")
record <- list(groups = groups, go_groups = go, floors = floors, naming = naming,
               sites = sites, plots = plan[, c("plot_id", "site", "project_name", "group",
                                               "acquisition_year")],
               decision_sha256 = digest::digest(file = file.path(dec, "group_decision.csv"),
                                                algo = "sha256"),
               outputs = setNames(lapply(files, function(f) digest::digest(file = f,
                 algo = "sha256")), sub(paste0("^", OFO, "/"), "", files)))
if (!identical(dec, pre)) record$decision_dir <- dec
jsonlite::write_json(record, file.path(ref, "reference_record.json"), auto_unbox = TRUE,
                     pretty = TRUE, digits = NA)

## ---- report --------------------------------------------------------------------
tab <- do.call(rbind, lapply(write_sites, function(s) {
  g <- gt[gt$site == s, , drop = FALSE]; c0 <- pc[pc$site == s, , drop = FALSE]
  data.frame(site = s, project = c0$project[1], group = c0$group[1],
             acquisition_year = c0$acquisition_year[1], epsg = c0$epsg[1],
             plots = length(unique(c0$ofo_plot_id)), cells = nrow(c0),
             headline_cells = sum(c0$headline), rows = nrow(g),
             live_dbh10 = sum(g$live & g$is_tree & !is.na(g$stemDiameter) & g$stemDiameter >= 10),
             heights = sum(!is.na(g$height)))
}))
print(tab, row.names = FALSE)
if (any(!sites$written))
  cat(sprintf("not written: %s\n", paste(sprintf("%s (%s)", sites$site[!sites$written],
                                                 sites$note[!sites$written]), collapse = ", ")))
cat("Each directory is one SITE=; freeze one acquisition year per run (YEAR=).\n")
cat(sprintf("wrote %d site reference(s) under %s and %s\n", length(write_sites),
            file.path(ref, "neon"), file.path(ref, "stems_all.csv")))
