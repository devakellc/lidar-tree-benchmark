#!/usr/bin/env Rscript
.bs_ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (!is.null(.bs_ofile) && length(.bs_ofile) && nzchar(.bs_ofile))
    file.path(dirname(.bs_ofile), "bootstrap.R"),
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])),
                                  "bootstrap.R"),
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_ofile, .bs_file)

# Post hoc analyses behind the configuration the `multichm_depth` arm uses
# (MCD_ARM, k4_r0_z3_f3_l0_c0.6, multichm_depth_lib.R). The arm's configuration
# was chosen by hand after the held-out results of the calibration/validation
# study (calval_multichm_depth.R) and of its confirmation on other densities and
# flights (confirm_multichm_depth.R) had been read. The protocol
# (docs/multichm-depth-protocol.md) reads only the calibration's selection S and
# its low-floor sibling S_low against the declared gated arm, so every number
# this script writes is DESCRIPTIVE, not held-out evidence: every table says so
# (PH_PROVENANCE), the result CSVs of the analyze stage have the column
# `status`, and so do the records (cells.config.json, arm_config.json). The
# per-dataset cells.csv of the score stage keep the study's columns and have no
# `status`; nor have the failure listings of the checks (p*_failures.csv).
#
# Configurations (ph_configs; labels derived, never typed): stock multichm; the
# declared gated arm's floor and exemption without its share gate
# (floor_exempt); the declared gated arm (declared); S's depth rule with the
# gated arm's floors and filter (depth); depth plus S's horizontal rule (space);
# S; the arm's rules with S's floors (alt); the arm (arm); S_low when the study
# recorded one. S and S_low are read from the study's record
# (declared_depth_config.json); every depth label must be a row of mcd_grid().
# The pairs (ph_pairs) walk from the declared gated arm to S in three steps
# (group "walk") and set the arm against its neighbours (group "arm").
#
# Stages (STAGE=score|analyze|all):
#   score    per confirmation dataset (DATASETS=, CFD_DATASETS): every cell of
#            the dataset's candidates index scored exactly as the confirmation
#            driver scored it (cd_score_job: the grid rows of the depth
#            configurations, the dataset's cached candidates, the confirmation
#            run's features, K and TOL of the dataset's record, its core stems,
#            the plot's null shifts), which also re-derives the four gated
#            references. CHECK P1 stops the stage unless the rows of S, S_low and
#            the four references equal the confirmation run's rows of the same
#            cell and label (observed counts exactly, null means within 1e-9).
#            -> OUT/<dataset>/cells.csv (the study's columns),
#            OUT/<dataset>/cells.config.json (K, TOL, the labels, the hashes of
#            the confirmation run's cells.csv and of the study's record, P1, the
#            constants' and grid digests)
#   analyze  stops unless the study's held-out run (STUDY/tables.md,
#            STUDY/validation.csv) and the confirmation's contrasts
#            (CONFIRM/contrasts.csv) exist. Units: the study's cells at native
#            density and at rungs 8, 4, 2 and 1 (STUDY/cells.csv, 106 plots) and
#            the confirmation units (CFD_UNITS, the two sparse flights pooled)
#            from the score stage's cells. Contrasts: per unit, plot subset
#            (validation half of the study's headline split, all plots), scope
#            (cfd_scopes; and, for native, the closed and open stands of A5) and
#            pair, the confirmation driver's cfd_unit_contrasts (cv_contrast_row,
#            paired plot bootstrap, N_BOOT draws, MT_SEED, cd_add_verdicts).
#            CHECK P2 stops unless the S minus declared rows reproduce the study's
#            primary row (validation.csv), its ladder rows (ladder.csv, Five
#            sites) and every S minus declared row of CONFIRM/contrasts.csv
#            within 1e-12. Lowest trees (study, native density, 106 plots):
#            per-stem matches of stock, declared, depth, S, alt and arm
#            (cd_stem_job); CHECK P3 stops unless they give every cell's TP and
#            TP0 of STUDY/cells.csv (cd_s3_compare) and the rows of stock,
#            declared and S equal STUDY/stem_matches.csv. Then per subset the
#            lowest-tree scores and the arm's lowest-tree contrasts, and the
#            reference stems by field-height band with the matches of stock,
#            declared, S and arm (raw counts). The grid (study, native density,
#            per subset): every one of the 240 grid configurations and every
#            reference pooled by summed counts (mcg_pool), the grid ranked by
#            cF1 (ph_rank), and how many grid configurations score above the
#            declared gated arm and above stock.
#            -> OUT/contrasts.csv, OUT/lowest_trees.csv, OUT/stem_heights.csv,
#            OUT/stem_matches.csv, OUT/grid_validation.csv, OUT/arm_config.json,
#            OUT/tables.md
#
# Inputs (read only): the study's run (STUDY: cells.csv, split.csv,
# declared_depth_config.json, cells.config.json, validation.csv, ladder.csv,
# stem_matches.csv, features/), its job directory ($WORK/multichm_gated_runs:
# stems, the gated candidates) and frozen root ($WORK/neon/frozen_2021); the
# confirmation run (CONFIRM: <dataset>/cells.csv, <dataset>/features/,
# contrasts.csv); the confirmation campaign's datasets (CAMPAIGN) and their
# frozen roots. Nothing is written outside OUT.
#
# Usage (from the repository root):
#   Rscript scripts/posthoc_multichm_depth.R [STAGE=all|score|analyze]
#     [DATASETS=ql2,wa2019,wa2021_shared,ca2018,ca2017,ca2021_shared]
#     [CORES=4 (at most 8)] [N_BOOT=1000] [WORK=work]
#     [STUDY=$WORK/multichm_depth_runs/neon/multichm_depth]
#     [CONFIRM=$WORK/multichm_depth_runs/confirm]
#     [CAMPAIGN=$WORK/multichm_gated_confirmation]
#     [OUT=$WORK/multichm_depth_runs/posthoc]
# The analyze stage reads every confirmation dataset, so it needs every dataset
# scored. CHECK P2 compares with runs made with N_BOOT = 1000 (MT_N_BOOT);
# another N_BOOT changes the intervals and stops it. OUT has no `..` component
# and does not equal, lie inside or contain STUDY, CONFIRM, CAMPAIGN, the
# study's job directory and frozen root, the frozen roots of the datasets, or
# the two runs of record under WORK whatever STUDY= and CONFIRM= say (compared
# in canonical absolute form, cfd_check_out).
suppressMessages({ library(lidR); library(lidRplugins); library(sf)
                   library(data.table); library(parallel) })
options(lidR.progress = FALSE)
# The confirmation driver: sourcing it runs nothing (it ends with
# `if (sys.nframe() == 0L) cfd_main()`); it sources the depth study's driver,
# which sources the gated study's driver (and through it sweep_lib.R,
# model_bench_lib.R, calval_lib.R, master_tables_lib.R and multichm_gated_lib.R)
# and multichm_depth_lib.R.
source(.find("confirm_multichm_depth.R"))

## ---- constants ----------------------------------------------------------------------------
PH_KEYS       <- c("STAGE", "DATASETS", "CORES", "N_BOOT", "WORK", "STUDY", "CONFIRM", "CAMPAIGN",
                   "OUT")
PH_STAGES     <- c("all", "score", "analyze")
PH_STATUS     <- "post hoc, descriptive"     # the column `status` of the analyze CSVs
PH_STUDY_JOB  <- "multichm_gated_runs"       # under WORK: the study's job directory
PH_STUDY_ROOT <- file.path("neon", "frozen_2021")   # under WORK: the study's frozen root
PH_P1_TOL     <- 1e-9                        # null means (cd_s1_compare)
PH_P2_TOL     <- 1e-12
PH_P2_COLS    <- c("d_cF1", "lo_cF1", "hi_cF1")
PH_P2_KEYS    <- c("unit", "subset", "scope", "rung", "config_a", "config_b")
PH_P3_TOL     <- 1e-9
PH_FIVE       <- "Five sites"
PH_SCOPE_ORDER <- c(names(CFD_SCOPES), CD_STAND_SCOPES)
PH_PROVENANCE <- paste(
  "Post hoc and descriptive. The arm's configuration was chosen after the",
  "held-out results of the study and of its confirmation on other densities and",
  "flights had been read, and with a referee-only check on plots outside the",
  "benchmark that have no field reference. None of the contrasts below was",
  "declared in the protocol (docs/multichm-depth-protocol.md), which reads the",
  "calibration's selection and its low-floor sibling only. The validation-half",
  "rows are therefore not held-out evidence for the arm's configuration.")

# The configurations by name, in table order; S_low only when the study has one.
PH_NAMES <- c("stock", "floor_exempt", "declared", "depth", "space", "S", "alt", "arm", "S_low")
PH_WHAT <- c(
  stock = "stock lidRplugins::multichm",
  floor_exempt = "the declared gated arm's floor and surface exemption without its share gate",
  declared = "the declared gated arm",
  depth = paste("S's depth rule, cover threshold and lit union with the declared gated arm's",
                "floors (deeper zmin, surface 0) and filter (near_2d 0)"),
  space = "depth plus S's horizontal spacing rule (near_2d)",
  S = "the calibration's selection",
  alt = "the arm's rules with S's floors",
  arm = "the arm's configuration (MCD_ARM)",
  S_low = "the calibration's low-floor sibling")

# The pairs (a minus b), in order.
PH_PAIRS <- data.frame(
  pair = c("gate_minus_floor", "depth_minus_floor", "depth_minus_declared", "space_minus_depth",
           "S_minus_space", "S_minus_declared", "arm_minus_declared", "arm_minus_stock",
           "arm_minus_S", "arm_minus_depth", "arm_minus_alt", "alt_minus_declared",
           "S_minus_alt"),
  a_name = c("declared", "depth", "depth", "space", "S", "S", "arm", "arm", "arm", "arm", "arm",
             "alt", "S"),
  b_name = c("floor_exempt", "floor_exempt", "declared", "depth", "space", "declared",
             "declared", "stock", "S", "depth", "alt", "declared", "alt"),
  group = c(rep("walk", 6), rep("arm", 7)),
  what = c("what the share gate and the spacing switch add to floor and exemption",
           "what the depth rule adds to the same base",
           "step 1: the depth rule in place of the share gate and the switch",
           "step 2: plus the horizontal rule",
           "step 3: plus the surface floor",
           "the three steps together (the study's primary pair)",
           "the arm against the declared gated arm",
           "the arm against stock multichm",
           "the arm against the calibration's selection",
           "the arm's 3 m floors against the gated arm's floors",
           "the arm's 3 m floors against 5 m floors",
           "the 5 m variant against the declared gated arm",
           "what the horizontal rule adds at 5 m floors"),
  stringsAsFactors = FALSE)

# The study's units: its cells at native density and down the ladder.
PH_STUDY_UNITS <- data.frame(
  unit = c("native", "rung8", "rung4", "rung2", "rung1"),
  rung = c("native", "8", "4", "2", "1"),
  test = c("study", "T1", "T1", "T1", "T1"),
  role = c("study", "test", "test", "test", "test"),
  label = c("Study clips, native density", "Study clips decimated to 8 pts/m2",
            "Study clips decimated to 4 pts/m2", "Study clips decimated to 2 pts/m2",
            "Study clips decimated to 1 pt/m2"),
  reading_scope = PH_FIVE, stringsAsFactors = FALSE)
PH_UNIT_COLS <- c("unit", "test", "role", "label", "reading_scope")
# The columns of the walk and arm tables (tables.md).
PH_TABLE_UNITS <- c("native", "rung2", "ql2", "wa2019", "ca_sparse_pooled")
PH_NATIVE_SCOPES <- c(PH_FIVE, "California", "Washington", CD_STAND_SCOPES)
PH_NATIVE_PAIRS  <- c("arm_minus_declared", "arm_minus_stock", "arm_minus_S", "arm_minus_depth")
PH_LADDER_PAIRS  <- c("arm_minus_declared", "arm_minus_stock")

# The lowest-tree configurations: name -> the role cd_stem_job() records (S
# is "selected", as cd_stem_job needs), in order; the arm's lowest-tree
# contrasts (arm minus each); the configurations of the height-band counts.
PH_LOW_ROLES <- c(stock = "stock", declared = "declared", depth = "depth", S = "selected",
                  alt = "alt", arm = "arm")
PH_LOW_TABLE <- c("stock", "declared", "S", "depth", "alt", "arm")
PH_LOW_B     <- c("declared", "stock", "S", "depth", "alt")
PH_STEM_CHECK <- c("stock", "declared", "S")        # rows equal to STUDY/stem_matches.csv
PH_HEIGHT_NAMES <- c("stock", "declared", "S", "arm")

# Field-height bands of the reference stems (left-closed: 3 m is "3 to 5 m").
PH_HEIGHT_BREAKS <- c(0, 3, 5, 10, 20, Inf)
PH_HEIGHT_BANDS  <- c("under 3 m", "3 to 5 m", "5 to 10 m", "10 to 20 m", "20 m and more",
                      "unknown")

# The grid on the study's plots: the configurations whose cF1 and rank are
# reported, the tolerance of the rank (mcg_select's tie rule: cF1 within 1e-12
# is a tie) and the columns of grid_validation.csv.
PH_GRID_NAMES <- c("S", "S_low", "alt", "arm", "depth", "space")
PH_RANK_TOL   <- 1e-12
PH_GRID_COLS  <- c("status", "subset", "family", "config_id", "label", MCD_FIELDS, "n_plots",
                   MCG_COUNT_COLS, "recall", "precision", "F1", "null_F1", "cF1", "det_per_ref",
                   "rank")

## ---- arguments ----------------------------------------------------------------------------
# KEY=VALUE positional arguments -> the run's settings (read with A[["KEY"]],
# never A$KEY). Unknown keys stop. The shared keys are validated by
# cfd_settings (DATASETS, CORES at most 8, N_BOOT, and OUT kept out of the
# study, the campaign and the frozen roots). OUT must also stay out of CONFIRM,
# of the study's job directory and frozen root, and of the two runs of record
# under WORK (and under `work`, the repository's work directory by default)
# whatever STUDY= and CONFIRM= say; it has no `..` component and is kept in
# canonical absolute form (cfd_check_out).
ph_settings <- function(args = commandArgs(TRUE), work = file.path(.ROOT, "work")) {
  a <- strsplit(args, "=")
  A <- stats::setNames(lapply(a, `[`, 2), vapply(a, `[`, character(1), 1))
  bad <- setdiff(names(A), PH_KEYS)
  if (length(bad))
    stop("unknown argument ", paste(bad, collapse = ", "), "; the keys are ",
         paste(PH_KEYS, collapse = ", "), call. = FALSE)
  if (anyDuplicated(names(A))) stop("an argument is given twice", call. = FALSE)
  given <- function(k) !is.null(A[[k]]) && !is.na(A[[k]]) && nzchar(A[[k]])
  get <- function(k, default) if (given(k)) A[[k]] else default
  stage <- get("STAGE", "all")
  if (!stage %in% PH_STAGES) stop("STAGE must be all, score or analyze", call. = FALSE)
  w <- get("WORK", work)
  out <- get("OUT", file.path(w, "multichm_depth_runs", "posthoc"))
  shared <- c("WORK", "DATASETS", "CORES", "N_BOOT", "STUDY", "CAMPAIGN")
  pass <- unlist(lapply(shared, function(k) if (given(k)) paste0(k, "=", A[[k]])))
  S <- cfd_settings(c(pass, paste0("OUT=", out)), work = work)
  S$A <- A
  S$STAGE <- stage
  S$CONFIRM <- get("CONFIRM", file.path(S$WORK, CFD_CONFIRM_DIR))
  works <- unique(c(S$WORK, work))
  S$OUT <- cfd_check_out(S$OUT, c(
    cfd_named("the confirmation run", S$CONFIRM),
    cfd_named("the confirmation run of record", file.path(works, CFD_CONFIRM_DIR)),
    cfd_named("the study", S$STUDY),
    cfd_named("the study's run of record", file.path(works, CFD_STUDY_DIR)),
    cfd_named("the campaign", S$CAMPAIGN),
    cfd_named("the study's job directory", file.path(S$WORK, PH_STUDY_JOB)),
    cfd_named("the study's frozen root", file.path(S$WORK, PH_STUDY_ROOT))))
  S
}

# A path for messages: relative to the repository root when under it
# (cfd_rel).
ph_rel <- function(p) cfd_rel(p)

## ---- configurations and pairs (pure) ------------------------------------------------------
# The configurations by name (PH_NAMES): the selection s (and its low-floor
# sibling s_low, NULL when there is none) as labels of `grid`, the arm `arm`
# (an mcd_config) and the declared gated arm `gated` (an mcg_config). Gated
# labels must be among the references cd_score_job re-derives (CD_REFERENCES)
# and the declared one CD_DECLARED; every depth label must be a row of `grid`,
# and no two names may share a label. Returns a data.frame: name, label,
# family ("gated" / "depth"), config_id (NA for gated), the six depth
# parameters (NA for gated) and what.
ph_configs <- function(s, s_low = NULL, arm = MCD_ARM, gated = MCG_DECLARED, grid = mcd_grid()) {
  row_of <- function(label, what) {
    if (!is.character(label) || length(label) != 1L || !label %in% grid$label)
      stop(what, " ", paste(label, collapse = ","), " is not a label of mcd_grid()",
           call. = FALSE)
    match(label, grid$label)
  }
  sc <- mcd_grid_config(grid, row_of(s, "the selection S"))
  if (!is.null(s_low)) row_of(s_low, "the low-floor sibling S_low")
  ac <- .mcd_check_config(arm)
  gc <- .mcg_check_config(gated)
  dcf <- list(
    depth = mcd_config(sc$depth_max, 0, gc$zmin, 0, sc$lit_union, sc$cover_min),
    space = mcd_config(sc$depth_max, sc$near_2d, gc$zmin, 0, sc$lit_union, sc$cover_min),
    S = sc,
    alt = mcd_config(ac$depth_max, ac$near_2d, sc$zmin, sc$zmin_surface, ac$lit_union,
                     ac$cover_min),
    arm = ac)
  if (!is.null(s_low)) dcf$S_low <- mcd_grid_config(grid, match(s_low, grid$label))
  glab <- c(stock = mcg_config_label(MCG_STOCK),
            floor_exempt = mcg_config_label(mcg_config(zmin = gc$zmin, min_share = 0,
                                                       cover_min = gc$cover_min,
                                                       surface_exempt = gc$surface_exempt)),
            declared = mcg_config_label(gc))
  if (!identical(glab[["declared"]], CD_DECLARED))
    stop("the declared gated arm is labelled ", glab[["declared"]], ", not ", CD_DECLARED,
         call. = FALSE)
  miss <- glab[!glab %in% CD_REFERENCES]
  if (length(miss))
    stop("the gated configuration ", names(miss)[1], " (", miss[[1]], ") is not one of the ",
         "references cd_score_job re-derives", call. = FALSE)
  dlab <- vapply(dcf, mcd_config_label, character(1))
  off <- dlab[!dlab %in% grid$label]
  if (length(off))
    stop("the configuration ", names(off)[1], " (", off[[1]], ") is not a row of mcd_grid()",
         call. = FALSE)
  nm <- intersect(PH_NAMES, c(names(glab), names(dlab)))
  lab <- c(glab, dlab)[nm]
  if (anyDuplicated(lab)) {
    dup <- lab[duplicated(lab)][1]
    stop("the configurations ", paste(nm[lab == dup], collapse = ", "), " share the label ", dup,
         call. = FALSE)
  }
  family <- ifelse(nm %in% names(glab), "gated", "depth")
  gi <- match(lab, grid$label)
  pick <- function(k) ifelse(family == "depth", grid[[k]][gi], NA)
  data.frame(name = nm, label = unname(lab), family = family,
             config_id = as.integer(ifelse(family == "depth", grid$config_id[gi], NA)),
             depth_max = as.numeric(pick("depth_max")), near_2d = as.numeric(pick("near_2d")),
             zmin = as.numeric(pick("zmin")), zmin_surface = as.numeric(pick("zmin_surface")),
             lit_union = as.logical(pick("lit_union")), cover_min = as.numeric(pick("cover_min")),
             what = unname(PH_WHAT[nm]), stringsAsFactors = FALSE)
}

# The label of a configuration name; stops when cf has no such name.
ph_label <- function(cf, name) {
  k <- match(name, cf$name)
  if (anyNA(k)) stop("no configuration named ", paste(name[is.na(k)], collapse = ","),
                     call. = FALSE)
  cf$label[k]
}

# The pairs (PH_PAIRS, in order) with the labels a and b of their names in cf.
ph_pairs <- function(cf) {
  p <- PH_PAIRS
  p$a <- ph_label(cf, p$a_name)
  p$b <- ph_label(cf, p$b_name)
  p[c("pair", "a_name", "b_name", "a", "b", "group", "what")]
}

# The grid rows of the depth configurations of cf (score stage), in cf's order.
ph_depth_grid <- function(cf, grid = mcd_grid()) {
  d <- cf[cf$family == "depth", , drop = FALSE]
  g <- grid[match(d$label, grid$label), , drop = FALSE]
  if (anyNA(g$config_id)) stop("a depth configuration is not in the grid", call. = FALSE)
  rownames(g) <- NULL
  g
}

# The labels CHECK P1 compares with the confirmation run: S, S_low and the four
# gated references.
ph_p1_labels <- function(D) c(D$S, D$S_low, CD_REFERENCES)

## ---- checks (pure) ------------------------------------------------------------------------
# CHECK P1: the rows of `labels` scored here (mine) against the confirmation
# run's rows (conf) of the same cell and label, through cd_s1_compare (observed
# count columns exactly, null means within `tol`). pass: every one of the
# n_cells x labels rows is on both sides and none differs.
ph_p1_compare <- function(mine, conf, labels, n_cells, tol = PH_P1_TOL) {
  a <- as.data.frame(mine)[mine$config %in% labels, , drop = FALSE]
  b <- as.data.frame(conf)[conf$config %in% labels, , drop = FALSE]
  r <- cd_s1_compare(a, b, tol)
  r$want <- as.integer(n_cells) * length(labels)
  r$pass <- r$n == r$want && r$n_bad == 0L
  r
}

# CHECK P2 (one part): the rows of `mine` against the reference rows `ref`,
# matched on `keys`: each of `cols` within `tol` (both NA counts as equal); a
# row on one side only is a failure. Returns list(n (rows compared), n_bad,
# max_abs_diff, bad).
ph_p2_compare <- function(mine, ref, keys = PH_P2_KEYS, cols = PH_P2_COLS, tol = PH_P2_TOL) {
  a <- as.data.frame(mine)[c(keys, cols)]
  b <- as.data.frame(ref)[c(keys, cols)]
  for (k in keys) { a[[k]] <- as.character(a[[k]]); b[[k]] <- as.character(b[[k]]) }
  if (anyDuplicated(do.call(paste, a[keys])) || anyDuplicated(do.call(paste, b[keys])))
    stop("CHECK P2: duplicate rows of one key", call. = FALSE)
  a$.mine <- TRUE; b$.ref <- TRUE
  m <- merge(a, b, by = keys, all = TRUE, suffixes = c("", ".ref"))
  bad <- is.na(m$.mine) | is.na(m$.ref)
  md <- 0
  for (k in cols) {
    x <- as.numeric(m[[k]]); y <- as.numeric(m[[paste0(k, ".ref")]])
    d <- abs(x - y)
    bad <- bad | xor(is.na(x), is.na(y)) | (!is.na(d) & d > tol)
    if (any(!is.na(d))) md <- max(md, d, na.rm = TRUE)
  }
  list(n = nrow(m), n_bad = sum(bad), max_abs_diff = md,
       bad = m[bad, setdiff(names(m), c(".mine", ".ref")), drop = FALSE])
}

# The three parts of CHECK P2 from this run's contrasts (con) and the runs of
# record: (a) the study's primary row (validation.csv, `primary`), unit native;
# (b) every S minus declared row of the confirmation's contrasts.csv (conf);
# (c) the study's ladder rows of S minus the declared arm on its validation
# plots, Five sites (ladder.csv), units rung8 to rung1. Each against this run's
# S_minus_declared rows of the same unit, subset, scope, rung and labels.
ph_p2_parts <- function(con, validation, ladder, conf, s) {
  mine <- con[con$pair == CFD_PRIMARY, , drop = FALSE]
  va <- validation[as.logical(validation$primary) %in% TRUE, , drop = FALSE]
  a_ref <- data.frame(unit = rep("native", nrow(va)), subset = rep(CFD_SUBSETS[1], nrow(va)),
                      scope = va$scope, rung = as.character(va$rung), config_a = va$config_a,
                      config_b = va$config_b, va[PH_P2_COLS], stringsAsFactors = FALSE)
  a_mine <- mine[mine$unit == "native" & mine$subset == CFD_SUBSETS[1] & mine$scope == PH_FIVE, ,
                 drop = FALSE]
  b_ref <- conf[conf$pair == CFD_PRIMARY, , drop = FALSE]
  b_mine <- mine[mine$unit %in% CFD_UNITS$unit, , drop = FALSE]
  lr <- cfd_t1(ladder, s)
  lr <- lr[lr$scope == PH_FIVE, , drop = FALSE]
  c_ref <- data.frame(unit = paste0("rung", lr$rung), subset = rep(CFD_SUBSETS[1], nrow(lr)),
                      scope = lr$scope, rung = as.character(lr$rung), config_a = lr$config_a,
                      config_b = lr$config_b, lr[PH_P2_COLS], stringsAsFactors = FALSE)
  c_mine <- mine[mine$unit %in% paste0("rung", CFD_LADDER_RUNGS) &
                   mine$subset == CFD_SUBSETS[1] & mine$scope == PH_FIVE, , drop = FALSE]
  list(a = ph_p2_compare(a_mine, a_ref), b = ph_p2_compare(b_mine, b_ref),
       c = ph_p2_compare(c_mine, c_ref),
       want = c(a = 1L, b = nrow(b_ref), c = length(CFD_LADDER_RUNGS)))
}

# CHECK P3 (second part): the rows of `configs` in this run's stem table (mine)
# against the study's stem_matches.csv (ref): the same stems (site, plot,
# stem_id, config), matched equal, tp0 within `tol`.
ph_stem_compare <- function(mine, ref, configs, tol = PH_P3_TOL) {
  key <- c("site", "plot", "stem_id", "config")
  a <- as.data.frame(mine)[mine$config %in% configs, c(key, "matched", "tp0"), drop = FALSE]
  b <- as.data.frame(ref)[ref$config %in% configs, c(key, "matched", "tp0"), drop = FALSE]
  for (k in key) { a[[k]] <- as.character(a[[k]]); b[[k]] <- as.character(b[[k]]) }
  if (anyDuplicated(do.call(paste, a[key])) || anyDuplicated(do.call(paste, b[key])))
    stop("CHECK P3: a stem is listed twice for one configuration", call. = FALSE)
  m <- merge(a, b, by = key, all = TRUE, suffixes = c("", ".ref"))
  x <- as.logical(m$matched); y <- as.logical(m$matched.ref)
  d <- abs(as.numeric(m$tp0) - as.numeric(m$tp0.ref))
  bad <- is.na(x) | is.na(y) | x != y | xor(is.na(m$tp0), is.na(m$tp0.ref)) |
    (!is.na(d) & d > tol)
  list(n = nrow(m), n_bad = sum(bad), max_tp0_diff = if (any(!is.na(d))) max(d, na.rm = TRUE)
       else NA_real_, bad = m[bad, , drop = FALSE])
}

## ---- units and contrasts (pure) -----------------------------------------------------------
# The units the contrasts read: the study's cells at each rung of study_units
# and each confirmation unit of conf_units, its datasets' cells (scored, a
# named list of cells by dataset) pooled with cfd_pool_cells (their plots must
# be disjoint). A named list of list(unit (one row: unit, test, role, label,
# reading_scope), rung, cells).
ph_units <- function(study, scored, study_units = PH_STUDY_UNITS, conf_units = CFD_UNITS) {
  out <- list()
  for (i in seq_len(nrow(study_units))) {
    u <- study_units[i, , drop = FALSE]
    x <- study[as.character(study$rung) == u$rung, , drop = FALSE]
    if (!nrow(x)) stop("the study holds no cell at rung ", u$rung, call. = FALSE)
    rownames(x) <- NULL
    out[[u$unit]] <- list(unit = u[PH_UNIT_COLS], rung = u$rung, cells = x)
  }
  for (i in seq_len(nrow(conf_units))) {
    u <- conf_units[i, , drop = FALSE]
    parts <- strsplit(u$parts, ",")[[1]]
    miss <- setdiff(parts, names(scored))
    if (length(miss)) stop(u$unit, ": dataset ", paste(miss, collapse = ","), " is not scored",
                           call. = FALSE)
    x <- cfd_pool_cells(unname(scored[parts]))
    rung <- unique(as.character(x$rung))
    if (length(rung) != 1L) stop(u$unit, ": cells of several rungs", call. = FALSE)
    out[[u$unit]] <- list(unit = u[PH_UNIT_COLS], rung = rung, cells = x)
  }
  out
}

# The closed- and open-stand rows of one unit (A5, native density only): per
# subset, stand and pair one cv_contrast_row on the stand's plots of the
# subset (cd_stand_plots), tagged as cfd_unit_contrasts tags its rows.
ph_stand_contrasts <- function(cells, unit, rung, valid, pairs, n_boot = MT_N_BOOT,
                               seed = MT_SEED) {
  ids <- unique(cv_ids(cells[cells$rung == rung, , drop = FALSE]))
  subs <- cfd_subset_ids(ids, valid)
  out <- list()
  for (su in names(subs)) {
    stands <- cd_stand_plots(cells, subs[[su]])
    for (sc in names(stands)) for (k in seq_len(nrow(pairs))) {
      if (!length(stands[[sc]])) next
      tag <- data.frame(unit = unit$unit, test = unit$test, role = unit$role, subset = su,
                        split = su, scope = sc, pair = pairs$pair[k], stringsAsFactors = FALSE)
      r <- cv_contrast_row(cells, stands[[sc]], rung, pairs$a[k], pairs$b[k], n_boot, seed, tag)
      if (!is.null(r)) out[[length(out) + 1L]] <- r
    }
  }
  if (!length(out)) return(NULL)
  v <- do.call(rbind, out)
  rownames(v) <- NULL
  v <- cd_add_verdicts(v)
  v$reading <- FALSE
  v
}

PH_CON_LEAD <- c("status", "unit", "test", "role", "subset", "split", "scope", "rung", "pair",
                 "group", "name_a", "name_b", "config_a", "config_b")
# The contrasts of one unit: cfd_unit_contrasts (every subset, scope it can
# form and pair) and, with stands, the closed and open stands; ordered by
# subset, scope and pair, with the pair's group and names. The flag of the
# unit's widest scope (cfd_unit_contrasts' `reading`) is `widest_scope`.
ph_unit_contrasts <- function(cells, unit, rung, valid, pairs, stands = FALSE,
                              n_boot = MT_N_BOOT, seed = MT_SEED) {
  v <- cfd_unit_contrasts(cells, unit, rung, valid, pairs, n_boot, seed)
  if (stands) v <- rbind(v, ph_stand_contrasts(cells, unit, rung, valid, pairs, n_boot, seed))
  if (is.null(v) || !nrow(v)) return(NULL)
  v <- v[order(match(v$subset, CFD_SUBSETS), match(v$scope, PH_SCOPE_ORDER),
               match(v$pair, pairs$pair)), , drop = FALSE]
  k <- match(v$pair, pairs$pair)
  v$group <- pairs$group[k]; v$name_a <- pairs$a_name[k]; v$name_b <- pairs$b_name[k]
  names(v)[names(v) == "reading"] <- "widest_scope"
  v$status <- PH_STATUS
  rownames(v) <- NULL
  v[c(PH_CON_LEAD, setdiff(names(v), PH_CON_LEAD))]
}

## ---- lowest trees (pure parts) ------------------------------------------------------------
# The lowest-tree configurations in cd_stem_job()'s form: list(role, label,
# kind, cfg) for the names of PH_LOW_ROLES (S with role "selected").
ph_lowest_configs <- function(cf, grid = mcd_grid()) {
  refs <- cd_ref_configs()
  lapply(names(PH_LOW_ROLES), function(n) {
    r <- cf[cf$name == n, , drop = FALSE]
    if (nrow(r) != 1L) stop("no configuration named ", n, call. = FALSE)
    cfg <- if (r$family == "gated") refs[[r$label]] else
      mcd_grid_config(grid, which(grid$config_id == r$config_id))
    if (is.null(cfg)) stop("no gated reference ", r$label, call. = FALSE)
    list(role = PH_LOW_ROLES[[n]], label = r$label, kind = r$family, cfg = cfg)
  })
}

# Field-height band of a reference stem (PH_HEIGHT_BANDS): left-closed bands
# with edges at 3, 5, 10 and 20 m; "unknown" for a missing, negative or
# infinite height.
ph_height_band <- function(h) {
  h <- suppressWarnings(as.numeric(h))
  b <- rep("unknown", length(h))
  ok <- is.finite(h) & h >= 0
  b[ok] <- as.character(cut(h[ok], PH_HEIGHT_BREAKS, right = FALSE,
                            labels = PH_HEIGHT_BANDS[-length(PH_HEIGHT_BANDS)]))
  b
}

# The reference stems by field-height band and how many of each band each of
# `labels` (named: name -> label) matches, per subset (subsets: a named list
# of plot ids), raw counts: one row per subset and band, then the subset's
# total ("all heights"). Every configuration must hold the same stems.
ph_stem_heights <- function(st, subsets, labels) {
  st <- as.data.frame(st)
  out <- list()
  for (su in names(subsets)) {
    u <- st[cv_ids(st) %in% subsets[[su]], , drop = FALSE]
    rows <- lapply(labels, function(l) u[u$config == l, , drop = FALSE])
    key <- function(x) paste(x$site, x$plot, x$stem_id)
    ref <- rows[[1]]
    for (n in names(rows))
      if (!identical(key(rows[[n]]), key(ref)))
        stop("ph_stem_heights: ", n, " holds other stems than ", names(rows)[1], call. = FALSE)
    band <- ph_height_band(ref$height)
    one <- function(b, sel) {
      r <- data.frame(status = PH_STATUS, subset = su, band = b,
                      n_plots = length(unique(cv_ids(ref))), stems = sum(sel),
                      stringsAsFactors = FALSE)
      for (n in names(rows)) r[[paste0("matched_", n)]] <- sum(as.logical(rows[[n]]$matched)[sel])
      r
    }
    out <- c(out, lapply(PH_HEIGHT_BANDS, function(b) one(b, band == b)),
             list(one("all heights", rep(TRUE, nrow(ref)))))
  }
  x <- do.call(rbind, out)
  rownames(x) <- NULL
  x
}

# The lowest-tree tables of one subset: every configuration's scores per
# stratum (cd_lowest_scores) and the arm minus each of PH_LOW_B
# (cd_lowest_contrast), with the subset.
ph_lowest_tables <- function(st, plots, subset, split, cf, n_boot = MT_N_BOOT, seed = MT_SEED) {
  arm <- ph_label(cf, "arm")
  parts <- c(list(cd_lowest_scores(st, plots, split, n_boot, seed)),
             lapply(PH_LOW_B, function(b)
               cd_lowest_contrast(st, plots, arm, ph_label(cf, b), split, n_boot, seed)))
  x <- as.data.frame(data.table::rbindlist(parts, fill = TRUE))
  cbind(data.frame(status = PH_STATUS, subset = subset, stringsAsFactors = FALSE), x)
}

## ---- the grid on the study's plots (pure) -------------------------------------------------
# The rank of each of x by value (1 = highest): one more than the number of
# values above it by more than `tol`, so that tied values (within `tol`, the
# tie rule of mcg_select) share the smallest rank. An undefined value stops.
ph_rank <- function(x, tol = PH_RANK_TOL) {
  if (anyNA(x)) stop("ph_rank: an undefined value", call. = FALSE)
  vapply(x, function(v) 1L + sum(x > v + tol), integer(1), USE.NAMES = FALSE)
}

# The grid on one set of plots: the study's cells at native density on
# `plots` pooled by summed counts (mcg_pool), one row per grid configuration
# with its rank by cF1 among the grid (ph_rank), ordered by rank and config_id,
# then one row per reference present (stock, the gated references, chm_vwf;
# no config_id, parameters or rank). Every grid configuration, stock and the
# declared gated arm must cover every plot once; a depth row must carry the
# grid's label of its config_id.
ph_grid_scores <- function(cells, plots, subset, grid = mcd_grid()) {
  nat <- cells[as.character(cells$rung) == "native", , drop = FALSE]
  plots <- intersect(unique(plots), unique(cv_ids(nat)))
  if (!length(plots)) stop("the grid (", subset, "): no native cell on its plots", call. = FALSE)
  nat <- nat[cv_ids(nat) %in% plots, , drop = FALSE]
  d <- nat[nat$family == "depth", , drop = FALSE]
  gl <- grid$label[match(d$config_id, grid$config_id)]
  if (anyNA(gl) || any(gl != d$config))
    stop("the grid (", subset, "): a depth row is not labelled as mcd_grid() labels its config_id",
         call. = FALSE)
  if (anyDuplicated(paste(d$config, cv_ids(d))) || anyDuplicated(paste(nat$config, cv_ids(nat))))
    stop("the grid (", subset, "): a plot is scored twice for one configuration", call. = FALSE)
  P <- mcg_pool(d, "config_id")
  if (!setequal(P$config_id, grid$config_id) || any(P$n_cells != length(plots)))
    stop(sprintf("the grid (%s): not every one of the %d configurations covers the %d plots",
                 subset, nrow(grid), length(plots)), call. = FALSE)
  P <- merge(grid, P, by = "config_id")
  P$rank <- ph_rank(P$cF1)
  P <- P[order(P$rank, P$config_id), , drop = FALSE]
  P$family <- "depth"
  R <- mcg_pool(nat[nat$family != "depth", , drop = FALSE], "config")
  R <- R[match(intersect(c(CD_REFERENCES, CD_CHM), R$config), R$config), , drop = FALSE]
  need <- c("stock", CD_DECLARED)
  if (!all(need %in% R$config) || any(R$n_cells[match(need, R$config)] != length(plots)))
    stop("the grid (", subset, "): stock and the declared gated arm must cover every plot",
         call. = FALSE)
  R$family <- ifelse(R$config == CD_CHM, "chm_vwf", "gated")
  R$label <- R$config
  R$config_id <- NA_integer_
  for (k in MCD_FIELDS) R[[k]] <- NA
  R$rank <- NA_integer_
  keep <- setdiff(PH_GRID_COLS, c("status", "subset", "n_plots"))
  x <- rbind(P[c(keep, "n_cells")], R[c(keep, "n_cells")])
  x$status <- PH_STATUS
  x$subset <- subset
  x$n_plots <- x$n_cells
  rownames(x) <- NULL
  x[PH_GRID_COLS]
}

# The grid on each plot subset of the study (the validation half of its
# headline split, `valid`, and all plots): ph_grid_scores, stacked.
ph_grid_validation <- function(cells, valid, grid = mcd_grid()) {
  ids <- unique(cv_ids(cells[as.character(cells$rung) == "native", , drop = FALSE]))
  subs <- cfd_subset_ids(ids, valid)
  x <- do.call(rbind, lapply(names(subs), function(su) ph_grid_scores(cells, subs[[su]], su,
                                                                      grid)))
  rownames(x) <- NULL
  x
}

# The grid table read per subset: `counts`, one row per subset (plots, stems,
# grid configurations, the cF1 of the declared gated arm and of stock and how
# many grid configurations score above each: by more than `tol`, the rule of
# the rank); `ranks`, one row per subset and name of `which` that cf holds
# (label, config_id, cF1, rank and how many grid configurations share it).
ph_grid_summary <- function(gv, cf, which = PH_GRID_NAMES, tol = PH_RANK_TOL) {
  counts <- list(); ranks <- list()
  nm <- intersect(which, cf$name)
  for (su in unique(gv$subset)) {
    x <- gv[gv$subset == su, , drop = FALSE]
    g <- x[x$family == "depth", , drop = FALSE]
    ref <- function(l) {
      y <- x[x$family != "depth" & x$label == l, , drop = FALSE]
      if (nrow(y) != 1L) stop("the grid (", su, "): no single row of ", l, call. = FALSE)
      y
    }
    dec <- ref(CD_DECLARED); sto <- ref("stock")
    counts[[su]] <- data.frame(status = PH_STATUS, subset = su, n_plots = sto$n_plots,
                               n_stems = sto$n_ref, n_grid = nrow(g), declared_cF1 = dec$cF1,
                               above_declared = sum(g$cF1 > dec$cF1 + tol), stock_cF1 = sto$cF1,
                               above_stock = sum(g$cF1 > sto$cF1 + tol), stringsAsFactors = FALSE)
    k <- match(ph_label(cf, nm), g$label)
    if (anyNA(k))
      stop("the grid (", su, "): ", paste(nm[is.na(k)], collapse = ", "), " is not a grid row",
           call. = FALSE)
    ranks[[su]] <- data.frame(status = PH_STATUS, subset = su, name = nm, label = g$label[k],
                              config_id = g$config_id[k], cF1 = g$cF1[k], rank = g$rank[k],
                              sharing_rank = vapply(g$rank[k], function(r) sum(g$rank == r),
                                                    integer(1)), stringsAsFactors = FALSE)
  }
  out <- list(counts = do.call(rbind, counts), ranks = do.call(rbind, ranks))
  for (k in names(out)) rownames(out[[k]]) <- NULL
  out
}

## ---- stage: score -------------------------------------------------------------------------
# The confirmation run's view of a dataset (its OUT is CONFIRM).
ph_confirm_dataset <- function(S, name) cfd_dataset(utils::modifyList(S, list(OUT = S$CONFIRM)),
                                                    name)

ph_stage_score <- function(S, ds, D, cf) {
  G <- cfd_dataset_record(ds)
  idx <- cfd_index(ds)
  dc <- ph_confirm_dataset(S, ds$name)
  cd_read_features(list(OUT = dc$out, root = ds$root), idx)   # stamp and every cell present
  conf <- cfd_read_scored(S, dc, D)$cells                     # S1 passed, same S and S_low
  stems <- cfd_stems(ds)
  jobs <- cd_plot_jobs(idx, stems)
  grid <- ph_depth_grid(cf)
  dir.create(ds$out, recursive = TRUE, showWarnings = FALSE)
  cfgf <- file.path(ds$out, "cells.config.json")
  unlink(cfgf)                         # cells.csv and its record are written together
  cat(sprintf(paste("[score] %s: %d cells of %d plots x (%s) + %d references, K = %d, TOL = %g,",
                    "%d workers\n"), ds$name, nrow(idx), length(jobs),
              paste(grid$label, collapse = ", "), length(CD_REFERENCES), G$K, G$tol,
              min(S$CORES, length(jobs))))
  t0 <- Sys.time()
  res <- plot_lapply(jobs, cd_score_worker, grid = grid, cdir = ds$cdir,
                     fdir = file.path(dc$out, "features"), K = G$K, tol = G$tol,
                     mc.cores = S$CORES)
  failed <- vapply(res, function(r) inherits(r, "error"), logical(1))
  if (any(failed))
    stop(ds$name, ": plots failed: ", paste(vapply(jobs[failed], function(j)
      paste(j$site, j$plot, sep = "/"), ""), collapse = ","), call. = FALSE)
  cells <- as.data.frame(data.table::rbindlist(res))
  keys <- unique(paste(cells$site, cells$plot, cells$rung))
  if (length(keys) != nrow(idx))
    stop(ds$name, ": scored ", length(keys), " cells of ", nrow(idx), call. = FALSE)
  ## CHECK P1
  labs <- ph_p1_labels(D)
  p1 <- ph_p1_compare(cells, conf, labs, length(keys))
  if (!p1$pass) {
    write.csv(p1$bad, file.path(ds$out, "p1_failures.csv"), row.names = FALSE)
    stop(sprintf(paste("%s: CHECK P1 failed: %d of %d rows differ from the confirmation run's",
                       "cells.csv (expected %d rows); see %s"), ds$name, p1$n_bad, p1$n, p1$want,
                 ph_rel(file.path(ds$out, "p1_failures.csv"))), call. = FALSE)
  }
  unlink(file.path(ds$out, "p1_failures.csv"))
  cv_pass(paste("CHECK P1 %s: %d rows (%d cells x %d: %s) equal the confirmation run's cells.csv",
                "rows: observed counts exactly, null means within 1e-9 (max |diff| %.3g)"),
          ds$name, p1$n, length(keys), length(labs), paste(labs, collapse = ", "),
          p1$max_null_diff)
  cells <- cd_order_cells(cells)
  write.csv(cells, file.path(ds$out, "cells.csv"), row.names = FALSE)
  rec <- list(status = PH_STATUS, dataset = ds$name, test = ds$test, role = ds$role,
              population = CFD_POP, sites = I(ds$sites), rung = ds$rung,
              clip_manifest_sha256 = frozen_root_id(ds$root), K = G$K, tol = G$tol,
              labels = as.list(stats::setNames(cf$label, cf$name)),
              depth_labels_scored = I(grid$label), references = I(CD_REFERENCES),
              dataset_cells_csv_sha256 = G$cells_sha256,
              confirm_cells_csv_sha256 = cd_file_sha(file.path(dc$out, "cells.csv")),
              declared_depth_config = list(sha256 = D$sha256, S = D$S, S_id = D$S_id,
                                           S_low = if (is.null(D$S_low)) NA else D$S_low,
                                           S_low_id = if (is.null(D$S_low_id)) NA else
                                             D$S_low_id),
              constants = mcd_constants(), constants_sha256 = cd_constants_digest(),
              depth_grid_sha256 = cd_grid_digest(), gated_grid_sha256 = cv_grid_digest(),
              n_cells = length(keys), n_plots = length(unique(cv_ids(cells))),
              P1 = list(status = "pass", n = p1$n, n_cells = length(keys), labels = I(labs),
                        n_bad = p1$n_bad, max_null_diff = p1$max_null_diff))
  cd_write_json(rec, cfgf)
  cat(sprintf("[score] %s: %d rows (%d cells) in %.1f min -> %s\n", ds$name, nrow(cells),
              length(keys), as.numeric(difftime(Sys.time(), t0, units = "mins")),
              ph_rel(file.path(ds$out, "cells.csv"))))
  invisible(cells)
}

## ---- stage: analyze -----------------------------------------------------------------------
# One dataset's cells scored here, refused unless its record exists, P1
# passed, its labels are the current ones, it was scored with the current
# constants and grid, neither the confirmation run's cells.csv nor the
# dataset's frozen root changed since, the campaign dataset's cells.csv still
# has the recorded hash and its record (cfd_dataset_record) still gives the
# recorded K and TOL, and cells.csv holds every configuration in every cell.
# Returns list(cells, record).
ph_read_scored <- function(S, ds, cf) {
  f <- file.path(ds$out, "cells.config.json")
  if (!file.exists(f))
    stop(ds$name, ": no scored cells record at ", ph_rel(f), "; run STAGE=score", call. = FALSE)
  r <- jsonlite::read_json(f, simplifyVector = TRUE)
  if (!identical(r$P1$status, "pass"))
    stop(ds$name, ": CHECK P1 did not pass; re-run STAGE=score", call. = FALSE)
  want <- stats::setNames(cf$label, cf$name)
  got <- unlist(r$labels)
  if (!identical(got[names(want)], want) || length(got) != length(want))
    stop(ds$name, ": the cells were scored for other configurations; re-run STAGE=score",
         call. = FALSE)
  if (!identical(r$constants_sha256, cd_constants_digest()) ||
      !identical(r$depth_grid_sha256, cd_grid_digest()) ||
      !identical(r$gated_grid_sha256, cv_grid_digest()))
    stop(ds$name, ": the cells were scored with other constants or grids; re-run STAGE=score",
         call. = FALSE)
  dc <- ph_confirm_dataset(S, ds$name)
  if (!identical(r$confirm_cells_csv_sha256, cd_file_sha(file.path(dc$out, "cells.csv"))) ||
      !identical(r$clip_manifest_sha256, frozen_root_id(ds$root)))
    stop(ds$name, ": the confirmation run's cells.csv or the frozen root changed since scoring; ",
         "re-run STAGE=score", call. = FALSE)
  G <- cfd_dataset_record(ds)
  if (!identical(r$dataset_cells_csv_sha256, G$cells_sha256))
    stop(ds$name, ": the campaign dataset's cells.csv (", ph_rel(file.path(ds$dir, "cells.csv")),
         ") changed since scoring; re-run STAGE=score", call. = FALSE)
  if (!identical(as.integer(r$K), G$K) || !identical(as.numeric(r$tol), G$tol))
    stop(sprintf(paste("%s: the cells were scored with K = %s and TOL = %s, the campaign dataset's",
                       "record gives K = %d and TOL = %g; re-run STAGE=score"), ds$name,
                 paste(r$K, collapse = ","), paste(r$tol, collapse = ","), G$K, G$tol),
         call. = FALSE)
  cf_csv <- file.path(ds$out, "cells.csv")
  if (!file.exists(cf_csv))
    stop(ds$name, ": no scored cells at ", ph_rel(cf_csv), "; re-run STAGE=score", call. = FALSE)
  cells <- cd_read_cells_file(cf_csv)
  n <- table(factor(cells$config, levels = c(cf$label)))
  if (any(n != r$n_cells) || nrow(cells) != r$n_cells * length(unique(cells$config)))
    stop(ds$name, ": cells.csv does not hold every configuration in every cell; re-run ",
         "STAGE=score", call. = FALSE)
  list(cells = cells, record = r)
}

# The study's job directory, frozen root and gated run, derived from WORK and
# checked against the study's cells record (population, root, gated cells,
# constants, grid; every plot scored). Returns its K, TOL and paths.
ph_study_inputs <- function(S) {
  f <- file.path(S$STUDY, CD_CELLS_CONFIG)
  if (!file.exists(f)) stop("no study cells record at ", ph_rel(f), call. = FALSE)
  r <- jsonlite::read_json(f, simplifyVector = TRUE)
  d <- file.path(S$WORK, PH_STUDY_JOB)
  root <- file.path(S$WORK, PH_STUDY_ROOT)
  gated <- file.path(d, "neon", "multichm_gated")
  ok <- c(population = identical(r$population, CFD_POP),
          root = identical(r$clip_manifest_sha256, frozen_root_id(root)),
          gated_cells = identical(r$gated$cells_csv_sha256,
                                  cd_file_sha(file.path(gated, "cells.csv"))),
          constants = identical(r$constants_sha256, cd_constants_digest()),
          grid = identical(r$grid_sha256, cd_grid_digest()),
          every_plot = isFALSE(r$blind))
  if (!all(ok))
    stop("the study's cells record does not match ", paste(names(ok)[!ok], collapse = ", "),
         " of this run (job directory ", ph_rel(d), ", root ", ph_rel(root), ")", call. = FALSE)
  K <- as.integer(r$K); tol <- as.numeric(r$tol)
  if (!isTRUE(K >= 1L) || !isTRUE(tol > 0)) stop(ph_rel(f), ": invalid K or TOL", call. = FALSE)
  frozen_stamp_check(file.path(S$STUDY, "features"), root)
  list(K = K, tol = tol, d = d, root = root, gated = gated, cdir = file.path(gated, "candidates"),
       fdir = file.path(S$STUDY, "features"), cells_sha256 = cd_file_sha(file.path(S$STUDY,
                                                                                   "cells.csv")))
}

# The study's selection as its driver derives it (cd_select on the calibration
# plots of split.csv at native density); stops unless it is the recorded S.
ph_study_selection <- function(cells, study, D, grid = mcd_grid()) {
  x <- read.csv(file.path(study, "split.csv"), stringsAsFactors = FALSE)
  sel <- cd_select(cells, cv_ids(x[x$split == "calib", , drop = FALSE]), grid)
  if (!identical(sel$label, D$S) || !identical(sel$config_id, D$S_id))
    stop("the study's cells select ", sel$label, ", not the recorded S ", D$S, call. = FALSE)
  sel
}

# Per-stem matches of the lowest-tree configurations on the study's native
# cells of `plots`, CHECK P3, and the tables of each subset.
ph_lowest <- function(S, si, study, sel, cf, valid) {
  Sg <- list(CANDIDATES = si$gated, OUT = si$gated, root = si$root, POP = CFD_POP,
             SITES = CV_FIVE, RUNGS = "native")
  idx <- cv_read_index(Sg)
  sk <- cv_read_skipped(Sg)
  if (nrow(sk)) cv_report_skipped(sk, "[study]")
  stems <- cd_read_stems(list(d = si$d, A = list(FROZEN_ROOT = si$root, POP = CFD_POP),
                              root = si$root), CV_FIVE)
  nat <- study[study$rung == "native", , drop = FALSE]
  plots <- unique(cv_ids(nat))
  sj <- cd_stem_jobs(idx, stems, plots)
  if (length(sj) != length(plots))
    stop("lowest trees: ", length(sj), " native cells in the index for ", length(plots), " plots",
         call. = FALSE)
  cfgs <- ph_lowest_configs(cf)
  cat(sprintf("[analyze] lowest trees: %d native cells x %d configurations (%s), %d workers\n",
              length(sj), length(cfgs), paste(vapply(cfgs, `[[`, "", "label"), collapse = ", "),
              min(S$CORES, length(sj))))
  t0 <- Sys.time()
  rs <- plot_lapply(sj, cd_stem_worker, cfgs = cfgs, sel = sel, cdir = si$cdir, fdir = si$fdir,
                    K = si$K, tol = si$tol, mc.cores = S$CORES)
  failed <- vapply(rs, function(r) inherits(r, "error"), logical(1))
  if (any(failed))
    stop("stem matches failed for plots: ", paste(vapply(sj[failed], function(j)
      paste(j$site, j$plot, sep = "/"), ""), collapse = ","), call. = FALSE)
  st <- as.data.frame(data.table::rbindlist(lapply(rs, `[[`, "stems")))
  zchk <- as.data.frame(data.table::rbindlist(lapply(rs, `[[`, "zrep_check")))
  ## CHECK P3
  s3 <- cd_s3_compare(st, nat, zchk)
  ref <- read.csv(file.path(S$STUDY, "stem_matches.csv"), stringsAsFactors = FALSE)
  sm <- ph_stem_compare(st, ref, ph_label(cf, PH_STEM_CHECK))
  want <- length(sj) * length(cfgs)
  n_ref_rows <- sum(ref$config %in% ph_label(cf, PH_STEM_CHECK))
  if (s3$n != want || s3$n_bad || s3$n_zrep_bad || sm$n_bad || sm$n != n_ref_rows) {
    write.csv(s3$bad, file.path(S$OUT, "p3_failures.csv"), row.names = FALSE)
    write.csv(sm$bad, file.path(S$OUT, "p3_stem_failures.csv"), row.names = FALSE)
    stop(sprintf(paste("CHECK P3 failed: %d of %d cell x configuration rows differ (expected %d);",
                       "%d of %d zrep cells differ; %d of %d stem rows differ from the study's",
                       "stem_matches.csv"), s3$n_bad, s3$n, want, s3$n_zrep_bad, s3$n_zrep,
                 sm$n_bad, sm$n), call. = FALSE)
  }
  unlink(file.path(S$OUT, c("p3_failures.csv", "p3_stem_failures.csv")))
  cv_pass(paste("CHECK P3: in %d native cells x %d configurations sum(matched) = TP, stems =",
                "n_ref and summed null means = TP0 of the study's cells.csv (max |diff| %.3g);",
                "zrep matches = TP in %d cells; %d stem rows of %s equal the study's",
                "stem_matches.csv (max tp0 diff %.3g) (%.1f min)"),
          length(sj), length(cfgs), s3$max_tp0_diff, s3$n_zrep, sm$n,
          paste(PH_STEM_CHECK, collapse = ", "), sm$max_tp0_diff,
          as.numeric(difftime(Sys.time(), t0, units = "mins")))
  subs <- cfd_subset_ids(plots, valid)
  splits <- stats::setNames(c("valid", "all"), CFD_SUBSETS)
  low <- as.data.frame(data.table::rbindlist(lapply(names(subs), function(su)
    ph_lowest_tables(st, subs[[su]], su, splits[[su]], cf, S$N_BOOT, MT_SEED)), fill = TRUE))
  hts <- ph_stem_heights(st, subs, stats::setNames(ph_label(cf, PH_HEIGHT_NAMES),
                                                   PH_HEIGHT_NAMES))
  st <- cbind(data.frame(status = rep(PH_STATUS, nrow(st)), stringsAsFactors = FALSE), st)
  list(stems = st, lowest = low, heights = hts, plots = plots, subsets = subs,
       P3 = list(status = "pass", cells = length(sj), configurations = length(cfgs), rows = s3$n,
                 max_tp0_diff = s3$max_tp0_diff, zrep_cells = s3$n_zrep,
                 stem_rows_compared = sm$n, stem_configs = I(ph_label(cf, PH_STEM_CHECK)),
                 stem_max_tp0_diff = sm$max_tp0_diff))
}

ph_stage_analyze <- function(S, D, cf) {
  need <- c(file.path(S$STUDY, c("tables.md", "validation.csv", "cells.csv", "split.csv",
                                 "ladder.csv", "stem_matches.csv")),
            file.path(S$CONFIRM, "contrasts.csv"))
  miss <- need[!file.exists(need)]
  if (length(miss))
    stop("the analyze stage needs the study's held-out run and the confirmation's contrasts; ",
         "missing: ", paste(ph_rel(miss), collapse = ", "), call. = FALSE)
  spec <- cd_spec_record()
  pairs <- ph_pairs(cf)
  valid <- cfd_valid_ids(S$STUDY)
  t0 <- Sys.time()
  ## the study's cells (its selection re-derived from them, the grid on each
  ## subset, then the named configurations only)
  si <- ph_study_inputs(S)
  all_cells <- cd_read_cells_file(file.path(S$STUDY, "cells.csv"))
  sel <- ph_study_selection(all_cells, S$STUDY, D)
  gv <- ph_grid_validation(all_cells, valid)
  gs <- ph_grid_summary(gv, cf)
  for (i in seq_len(nrow(gs$counts)))
    cat(sprintf(paste("[analyze] the grid, %s (%d plots): %d of %d configurations above the",
                      "declared gated arm, %d above stock\n"), gs$counts$subset[i],
                as.integer(gs$counts$n_plots[i]), gs$counts$above_declared[i],
                gs$counts$n_grid[i], gs$counts$above_stock[i]))
  study <- all_cells[all_cells$config %in% cf$label, , drop = FALSE]
  rm(all_cells)
  rownames(study) <- NULL
  ## the confirmation datasets scored here
  scored <- list(); recs <- list()
  for (nm in CFD_DATASETS$name) {
    x <- ph_read_scored(S, cfd_dataset(S, nm), cf)
    scored[[nm]] <- x$cells; recs[[nm]] <- x$record
  }
  units <- ph_units(study, scored)
  ## contrasts
  con <- list()
  for (u in names(units)) {
    U <- units[[u]]
    v <- ph_unit_contrasts(U$cells, U$unit, U$rung, valid, pairs, stands = identical(u, "native"),
                           S$N_BOOT, MT_SEED)
    ids <- unique(cv_ids(U$cells))
    cat(sprintf("[analyze] %s (%s): %d plots (%d validation), rung %s, %d rows\n", u, U$unit$test,
                length(ids), length(intersect(ids, valid)), U$rung,
                if (is.null(v)) 0L else nrow(v)))
    con[[u]] <- v
  }
  con <- as.data.frame(data.table::rbindlist(con, fill = TRUE))
  ## CHECK P2
  validation <- read.csv(file.path(S$STUDY, "validation.csv"), stringsAsFactors = FALSE,
                         colClasses = c(rung = "character"))
  ladder <- read.csv(file.path(S$STUDY, "ladder.csv"), stringsAsFactors = FALSE,
                     colClasses = c(rung = "character"))
  confc <- read.csv(file.path(S$CONFIRM, "contrasts.csv"), stringsAsFactors = FALSE,
                    colClasses = c(rung = "character"))
  p2 <- ph_p2_parts(con, validation, ladder, confc, D$S)
  p2_bad <- vapply(c("a", "b", "c"), function(k) p2[[k]]$n_bad > 0 || p2[[k]]$n != p2$want[[k]],
                   logical(1))
  p2_max <- max(vapply(c("a", "b", "c"), function(k) p2[[k]]$max_abs_diff, numeric(1)))
  if (any(p2_bad)) {
    bad <- as.data.frame(data.table::rbindlist(lapply(c("a", "b", "c"), function(k)
      if (nrow(p2[[k]]$bad)) cbind(part = k, p2[[k]]$bad)), fill = TRUE))
    write.csv(bad, file.path(S$OUT, "p2_failures.csv"), row.names = FALSE)
    stop(sprintf(paste("CHECK P2 failed in part(s) %s: (a) %d of %d, (b) %d of %d, (c) %d of %d",
                       "rows differ (expected %d, %d, %d); see %s. N_BOOT must be %d, as in the",
                       "runs of record"), paste(names(p2_bad)[p2_bad], collapse = ", "),
                 p2$a$n_bad, p2$a$n, p2$b$n_bad, p2$b$n, p2$c$n_bad, p2$c$n, p2$want[["a"]],
                 p2$want[["b"]], p2$want[["c"]], ph_rel(file.path(S$OUT, "p2_failures.csv")),
                 MT_N_BOOT),
         call. = FALSE)
  }
  unlink(file.path(S$OUT, "p2_failures.csv"))
  cv_pass(paste("CHECK P2: S minus declared reproduces (a) the study's primary row (%d row),",
                "(b) the confirmation's contrasts.csv (%d rows) and (c) the study's ladder.csv",
                "(%d rows, Five sites) in d_cF1, lo_cF1 and hi_cF1 within 1e-12 (max |diff| %.3g)"),
          p2$a$n, p2$b$n, p2$c$n, p2_max)
  ## lowest trees
  L <- ph_lowest(S, si, study, sel, cf, valid)
  ## files
  w <- function(x, f) write.csv(x, file.path(S$OUT, f), row.names = FALSE)
  w(con, "contrasts.csv")
  w(L$lowest, "lowest_trees.csv")
  w(L$heights, "stem_heights.csv")
  w(L$stems, "stem_matches.csv")
  w(gv, "grid_validation.csv")
  checks <- list(
    P1 = lapply(recs, function(r) list(status = r$P1$status, rows = r$P1$n, cells = r$P1$n_cells,
                                       labels = I(r$P1$labels),
                                       max_null_diff = r$P1$max_null_diff)),
    P2 = list(status = "pass", tol = PH_P2_TOL, columns = I(PH_P2_COLS),
              study_primary_rows = p2$a$n, confirmation_rows = p2$b$n, study_ladder_rows = p2$c$n,
              max_abs_diff = p2_max),
    P3 = L$P3)
  meta <- list(N_BOOT = S$N_BOOT, seed = MT_SEED, K = si$K, tol = si$tol, valid = valid,
               study_cells_sha256 = si$cells_sha256)
  cd_write_json(ph_arm_config(cf, D, units, valid, L, checks, spec, meta, gs),
                file.path(S$OUT, "arm_config.json"))
  writeLines(ph_tables_md(cf, pairs, con, L, units, valid, checks, D, meta, gs),
             file.path(S$OUT, "tables.md"))
  cat(sprintf("[analyze] %d contrast rows, %d lowest-tree rows in %.1f min -> %s\n", nrow(con),
              nrow(L$lowest), as.numeric(difftime(Sys.time(), t0, units = "mins")),
              ph_rel(file.path(S$OUT, "tables.md"))))
  invisible(list(contrasts = con, lowest = L, checks = checks, grid = gv))
}

# The grid element of arm_config.json: per subset (ph_grid_summary) the plots,
# stems, grid configurations, the cF1 of the declared gated arm and of stock,
# how many grid configurations score above each, and the cF1 and rank of the
# named configurations.
ph_grid_record <- function(gs) {
  subs <- lapply(seq_len(nrow(gs$counts)), function(i) {
    k <- gs$counts[i, ]
    r <- gs$ranks[gs$ranks$subset == k$subset, , drop = FALSE]
    list(plots = k$n_plots, stems = k$n_stems, grid_configurations = k$n_grid,
         declared_cF1 = k$declared_cF1, above_declared = k$above_declared,
         stock_cF1 = k$stock_cF1, above_stock = k$above_stock,
         configurations = stats::setNames(lapply(seq_len(nrow(r)), function(j)
           list(label = r$label[j], config_id = r$config_id[j], cF1 = r$cF1[j],
                rank = r$rank[j], sharing_rank = r$sharing_rank[j])), r$name))
  })
  list(status = PH_STATUS, file = "grid_validation.csv",
       source = "the study's cells.csv at native density, pooled by summed counts",
       rank_rule = sprintf(paste("rank by cF1 among the grid configurations, 1 = highest: one",
                                 "more than the number scoring above by more than %g, so ties",
                                 "share the smallest rank; above a reference = by more than %g"),
                           PH_RANK_TOL, PH_RANK_TOL),
       subsets = stats::setNames(subs, gs$counts$subset))
}

# The record of the arm's configuration (arm_config.json).
ph_arm_config <- function(cf, D, units, valid, L, checks, spec, meta, gs) {
  a <- cf[cf$name == "arm", , drop = FALSE]
  unit_counts <- lapply(units, function(U) {
    ids <- unique(cv_ids(U$cells))
    st <- U$cells[U$cells$config == "stock", , drop = FALSE]
    list(rung = U$rung, plots = length(ids), validation_plots = length(intersect(ids, valid)),
         stems = sum(st$n_ref))
  })
  list(status = PH_STATUS, chosen = PH_PROVENANCE,
       arm = list(name = "arm", label = a$label, config_id = a$config_id,
                  depth_max = a$depth_max, near_2d = a$near_2d, zmin = a$zmin,
                  zmin_surface = a$zmin_surface, lit_union = a$lit_union,
                  cover_min = a$cover_min),
       constants = mcd_constants(), constants_sha256 = cd_constants_digest(),
       grid_sha256 = cd_grid_digest(),
       study_selection = list(label = D$S, config_id = D$S_id),
       study_low_floor = if (is.null(D$S_low)) list(exists = FALSE) else
         list(exists = TRUE, label = D$S_low, config_id = D$S_low_id),
       declared_gated = CD_DECLARED,
       study_declared_record_sha256 = D$sha256, study_cells_csv_sha256 = meta$study_cells_sha256,
       K = meta$K, tol = meta$tol, n_boot = meta$N_BOOT, bootstrap_seed = meta$seed,
       configurations = lapply(seq_len(nrow(cf)), function(i) as.list(cf[i, ])),
       plots = list(study = length(L$plots),
                    study_validation_half = length(L$subsets[[CFD_SUBSETS[1]]]),
                    units = unit_counts),
       grid = ph_grid_record(gs), protocol = spec, checks = checks)
}

## ---- Markdown -----------------------------------------------------------------------------
# A difference with three decimals and its sign ("+0.012"); "NA" when missing.
ph_sgn <- function(x) ifelse(is.na(x), "NA", sprintf("%+.3f", x))
# A difference with its interval: "+0.012 [-0.006, +0.029]".
ph_div <- function(d, lo, hi) sprintf("%s [%s, %s]", ph_sgn(d), ph_sgn(lo), ph_sgn(hi))
# A rate with its interval: "0.236 [0.192, 0.293]".
ph_riv <- function(x, lo, hi) sprintf("%s [%s, %s]", cd_f3(x), cd_f3(lo), cd_f3(hi))
# "a − b" of a pair's names.
ph_pair_text <- function(pairs, p) {
  k <- match(p, pairs$pair)
  sprintf("%s − %s", pairs$a_name[k], pairs$b_name[k])
}
# The widest scope of a unit: its reading scope.
ph_widest <- function(units, u) units[[u]]$unit$reading_scope

# One wide table: rows = pairs (`which`), columns = units (`cols`), each cell
# the ΔcF1 with its interval on the unit's widest scope in `subset`; the
# header names each column's unit, scope, plots and stems.
ph_md_wide <- function(con, pairs, which, cols, units, subset) {
  head <- character(); cell <- list()
  for (u in cols) {
    sc <- ph_widest(units, u)
    x <- con[con$unit == u & con$subset == subset & con$scope == sc, , drop = FALSE]
    np <- unique(x$n_plots); ns <- unique(x$n_ref)
    head <- c(head, if (length(np) == 1L && length(ns) == 1L)
      sprintf("%s: %s, %d plots, %d stems", u, sc, as.integer(np), as.integer(ns)) else
        sprintf("%s: %s", u, sc))
    cell[[u]] <- x
  }
  rows <- vapply(which, function(p) {
    v <- vapply(cols, function(u) {
      x <- cell[[u]][cell[[u]]$pair == p, , drop = FALSE]
      if (nrow(x) == 1L) ph_div(x$d_cF1, x$lo_cF1, x$hi_cF1) else "–"
    }, character(1))
    sprintf("| `%s` | %s | %s |", p, ph_pair_text(pairs, p), paste(v, collapse = " | "))
  }, character(1), USE.NAMES = FALSE)
  cd_md(c("Pair", "A − B", head), rows)
}

# The native unit by scope: per subset, scope and pair (PH_NATIVE_SCOPES,
# PH_NATIVE_PAIRS) ΔcF1, Δrecall, Δprecision and Δdet/ref with intervals.
ph_md_native <- function(con, pairs) {
  x <- con[con$unit == "native" & con$scope %in% PH_NATIVE_SCOPES &
             con$pair %in% PH_NATIVE_PAIRS, , drop = FALSE]
  x <- x[order(match(x$subset, CFD_SUBSETS), match(x$scope, PH_NATIVE_SCOPES),
               match(x$pair, PH_NATIVE_PAIRS)), , drop = FALSE]
  if (!nrow(x)) return(c("(no rows)", ""))
  dl <- function(m) ph_div(x[[paste0("d_", m)]], x[[paste0("lo_", m)]], x[[paste0("hi_", m)]])
  cd_md(c("Subset", "Scope", "A − B", "Plots", "Stems", "ΔcF1 [95% interval]",
          "Δrecall [95% interval]", "Δprecision [95% interval]", "Δdet/ref [95% interval]"),
        sprintf("| %s | %s | %s | %d | %d | %s | %s | %s | %s |", x$subset, x$scope,
                ph_pair_text(pairs, x$pair), as.integer(x$n_plots), as.integer(x$n_ref),
                dl("cF1"), dl("recall"), dl("precision"), dl("det_per_ref")))
}

# The density ladder: per subset and study unit (native, rung8 to rung1), Five
# sites, ΔcF1 of each of PH_LADDER_PAIRS.
ph_md_ladder <- function(con, pairs) {
  us <- PH_STUDY_UNITS$unit
  rows <- character()
  for (su in CFD_SUBSETS) for (u in us) {
    x <- con[con$unit == u & con$subset == su & con$scope == PH_FIVE &
               con$pair %in% PH_LADDER_PAIRS, , drop = FALSE]
    if (!nrow(x)) next
    v <- vapply(PH_LADDER_PAIRS, function(p) {
      y <- x[x$pair == p, , drop = FALSE]
      if (nrow(y) == 1L) ph_div(y$d_cF1, y$lo_cF1, y$hi_cF1) else "–"
    }, character(1))
    rows <- c(rows, sprintf("| %s | %s | %s | %d | %d | %s |", su, u,
                            PH_STUDY_UNITS$rung[PH_STUDY_UNITS$unit == u],
                            as.integer(x$n_plots[1]), as.integer(x$n_ref[1]),
                            paste(v, collapse = " | ")))
  }
  cd_md(c("Subset", "Unit", "Rung", "Plots", "Stems",
          paste("ΔcF1", ph_pair_text(pairs, PH_LADDER_PAIRS), "[95% interval]")), rows)
}

# The lowest trees of one subset: per stratum (all, the height bands, the two
# lowest pooled) the chance-corrected recall with its interval of each of
# PH_LOW_TABLE and the arm minus the declared arm and minus S.
ph_md_lowest <- function(low, cf, subset) {
  x <- low[low$subset == subset, , drop = FALSE]
  sc <- x[x$kind == "score" & x$type %in% c("all", "band", "band_pooled"), , drop = FALSE]
  strata <- unique(sc$stratum)
  arm <- ph_label(cf, "arm")
  rows <- vapply(strata, function(s) {
    v <- vapply(PH_LOW_TABLE, function(n) {
      y <- sc[sc$stratum == s & sc$config == ph_label(cf, n), , drop = FALSE]
      if (nrow(y) == 1L) ph_riv(y$cRecall, y$cRecall_lo, y$cRecall_hi) else "–"
    }, character(1))
    k <- vapply(c("declared", "S"), function(b) {
      y <- x[x$kind == "contrast" & x$type %in% c("all", "band", "band_pooled") &
               x$stratum == s & x$config_a == arm & x$config_b == ph_label(cf, b), ,
             drop = FALSE]
      if (nrow(y) == 1L) ph_div(y$d_cRecall, y$lo_cRecall, y$hi_cRecall) else "–"
    }, character(1))
    n <- sc$stems[sc$stratum == s][1]
    sprintf("| %s | %d | %s | %s |", s, as.integer(n), paste(v, collapse = " | "),
            paste(k, collapse = " | "))
  }, character(1), USE.NAMES = FALSE)
  cd_md(c("Stratum (field height, m)", "Stems", PH_LOW_TABLE, "arm − declared", "arm − S"),
        rows)
}

ph_md_heights <- function(h) {
  cols <- paste0("matched_", PH_HEIGHT_NAMES)
  cd_md(c("Subset", "Field height", "Plots", "Stems", paste("Matched by", PH_HEIGHT_NAMES)),
        sprintf("| %s | %s | %d | %d | %s |", h$subset, h$band, as.integer(h$n_plots),
                as.integer(h$stems),
                apply(as.matrix(h[cols]), 1, function(r) paste(as.integer(r), collapse = " | "))))
}

# The grid on the study's plots (ph_grid_summary): per subset the grid
# configurations above the declared gated arm and above stock; then the cF1
# and rank of the named configurations.
ph_md_grid <- function(gs) {
  k <- gs$counts; r <- gs$ranks
  c(cd_para(paste("Grid configurations above the declared gated arm and above stock",
                  "(post hoc, descriptive):")),
    cd_md(c("Subset", "Plots", "Stems", "Grid configurations", "cF1 declared", "Above declared",
            "cF1 stock", "Above stock"),
          sprintf("| %s | %d | %d | %d | %s | %d | %s | %d |", k$subset, as.integer(k$n_plots),
                  as.integer(k$n_stems), as.integer(k$n_grid), cd_f3(k$declared_cF1),
                  as.integer(k$above_declared), cd_f3(k$stock_cF1), as.integer(k$above_stock))),
    cd_para("The cF1 and rank of the named configurations (post hoc, descriptive):"),
    cd_md(c("Subset", "Name", "Configuration", "config_id", "cF1", "Rank",
            "Grid configurations sharing the rank"),
          sprintf("| %s | %s | `%s` | %d | %s | %d | %d |", r$subset, r$name, r$label,
                  as.integer(r$config_id), cd_f3(r$cF1), as.integer(r$rank),
                  as.integer(r$sharing_rank))))
}

ph_tables_md <- function(cf, pairs, con, L, units, valid, checks, D, meta, gs) {
  walk <- pairs$pair[pairs$group == "walk"]
  armp <- pairs$pair[pairs$group == "arm"]
  wide <- function(which, su) ph_md_wide(con, pairs, which, PH_TABLE_UNITS, units, su)
  nsub <- vapply(L$subsets, length, integer(1))
  stems_of <- function(su) {
    h <- L$heights[L$heights$subset == su & L$heights$band == "all heights", , drop = FALSE]
    as.integer(h$stems[1])
  }
  p1 <- checks$P1
  p2 <- checks$P2
  p3 <- checks$P3
  c("# multichm_depth: the arm's configuration (post hoc, descriptive)", "",
    "<!-- generated by scripts/posthoc_multichm_depth.R -->", "",
    cd_para(PH_PROVENANCE),
    cd_para(sprintf(paste("Every table below is post hoc and descriptive. Contrasts are A − B in",
                          "pooled counts (sums of TP, detections and the shift null over plots),",
                          "with the paired plot bootstrap of the study (plots resampled within",
                          "site, %d draws, seed %d) and the study's scorer, K = %d shifts and",
                          "match radius %g m. Validation half: the plots of a unit that are",
                          "validation plots of the study's headline split (%d plots in all);",
                          "all plots: every plot of the unit. The calibration's selection is",
                          "S = `%s` (config_id %d)%s."), meta$N_BOOT, meta$seed, meta$K,
                    meta$tol, length(valid), D$S, D$S_id,
                    if (is.null(D$S_low)) ", without a low-floor sibling" else
                      sprintf(", its low-floor sibling S_low = `%s` (config_id %d)", D$S_low,
                              D$S_low_id))),
    "## 1. Configurations", "",
    "The configurations compared (post hoc, descriptive):", "",
    cd_md(c("Name", "Configuration", "Family", "config_id", "What it is"),
          sprintf("| %s | `%s` | %s | %s | %s |", cf$name, cf$label, cf$family,
                  ifelse(is.na(cf$config_id), "", as.character(cf$config_id)), cf$what)),
    cd_para("Pairs (A − B; post hoc, descriptive):"),
    cd_md(c("Pair", "A − B", "Group", "What it shows"),
          sprintf("| `%s` | %s | %s | %s |", pairs$pair, ph_pair_text(pairs, pairs$pair),
                  pairs$group, pairs$what)),
    cd_para(sprintf(paste("Units: the study's 2021 clips at native density (native) and",
                          "decimated to 8, 4, 2 and 1 pts/m2 (rung8 to rung1); the confirmation",
                          "units %s."),
                    paste(sprintf("%s: %s", CFD_UNITS$unit, CFD_UNITS$label), collapse = "; "))),
    "## 2. The walk from the declared gated arm to the selection", "",
    cd_para(paste("ΔcF1 [95% interval] on each unit's widest scope (post hoc, descriptive);",
                  "each column names its unit, scope, plots and stems.")),
    sprintf("Validation half (post hoc, descriptive):"), "",
    wide(walk, CFD_SUBSETS[1]),
    "All plots (post hoc, descriptive):", "",
    wide(walk, CFD_SUBSETS[2]),
    "## 3. The arm's configuration", "",
    cd_para("ΔcF1 [95% interval] on each unit's widest scope (post hoc, descriptive)."),
    "Validation half (post hoc, descriptive):", "",
    wide(armp, CFD_SUBSETS[1]),
    "All plots (post hoc, descriptive):", "",
    wide(armp, CFD_SUBSETS[2]),
    cd_para(sprintf(paste("Unit native (the study's clips at native density, %d plots, %d in",
                          "the validation half) by scope, with recall, precision and detections",
                          "per reference stem beside cF1 (post hoc, descriptive). %s"),
                    nsub[[CFD_SUBSETS[2]]], nsub[[CFD_SUBSETS[1]]], CD_STANDS_TEXT)),
    ph_md_native(con, pairs),
    "## 4. The density ladder", "",
    cd_para(paste("The study's clips at native density and decimated (units native, rung8 to",
                  "rung1), Five sites, ΔcF1 [95% interval] (post hoc, descriptive).")),
    ph_md_ladder(con, pairs),
    "## 5. Lowest trees", "",
    cd_para(paste("The study's clips at native density. Each configuration's chance-corrected",
                  "recall (TP − TP0) / (n − TP0) of the reference stems in each stratum with",
                  "its 95% plot-bootstrap interval, and the arm minus the declared gated arm",
                  "and minus S in that recall (post hoc, descriptive). Strata by field height",
                  "(m); [0,10) pools the two lowest bands.")),
    sprintf("Validation half (%d plots, %d stems; post hoc, descriptive):",
            nsub[[CFD_SUBSETS[1]]], stems_of(CFD_SUBSETS[1])), "",
    ph_md_lowest(L$lowest, cf, CFD_SUBSETS[1]),
    sprintf("All plots (%d plots, %d stems; post hoc, descriptive):",
            nsub[[CFD_SUBSETS[2]]], stems_of(CFD_SUBSETS[2])), "",
    ph_md_lowest(L$lowest, cf, CFD_SUBSETS[2]),
    cd_para(paste("The reference stems by field height and how many of each band stock, the",
                  "declared gated arm, S and the arm match (raw counts; post hoc,",
                  "descriptive). Bands include their lower edge: a stem of 3 m is in \"3 to",
                  "5 m\".")),
    ph_md_heights(L$heights),
    "## 6. The grid on the validation plots and on all plots", "",
    cd_para(sprintf(paste("The %d grid configurations of the study and its references on the",
                          "study's clips at native density (the study's cells.csv), pooled",
                          "over the plots of each subset by summed counts; the full table is",
                          "grid_validation.csv. Rank by cF1 among the grid configurations (1 =",
                          "highest): one more than the number that score above it by more",
                          "than %g, so ties share the smallest rank; \"above\" a reference",
                          "likewise means by more than %g. Post hoc and descriptive: the",
                          "validation half was read before the arm's configuration was",
                          "chosen."), max(gs$counts$n_grid), PH_RANK_TOL, PH_RANK_TOL)),
    ph_md_grid(gs),
    "## 7. Checks", "",
    cd_para(paste("P1 (post hoc, descriptive): per confirmation dataset, the rows of S, S_low",
                  "and the four gated references re-scored here equal the confirmation run's",
                  "rows of the same cell and label (observed counts exactly, null means",
                  "within 1e-9).")),
    cd_md(c("Dataset", "Rows", "Cells", "Max abs. null diff"),
          vapply(names(p1), function(n) sprintf("| %s | %d | %d | %.3g |", n,
                                                as.integer(p1[[n]]$rows),
                                                as.integer(p1[[n]]$cells),
                                                p1[[n]]$max_null_diff), character(1))),
    cd_para(sprintf(paste("P2: the S minus declared rows reproduce d_cF1, lo_cF1 and hi_cF1 of",
                          "the study's primary row (%d row), every S minus declared row of the",
                          "confirmation's contrasts.csv (%d rows) and the study's ladder rows",
                          "on its validation plots, Five sites (%d rows), within 1e-12; largest",
                          "absolute difference %.3g."), p2$study_primary_rows,
                    p2$confirmation_rows, p2$study_ladder_rows, p2$max_abs_diff)),
    cd_para(sprintf(paste("P3: in %d native cells x %d configurations the per-stem matches give",
                          "each cell's TP, stems and TP0 of the study's cells.csv (max TP0",
                          "difference %.3g); the selection reported with zrep matches its TP in",
                          "%d cells; %d stem rows of stock, declared and S equal the study's",
                          "stem_matches.csv (matched exactly, tp0 within 1e-9; max difference",
                          "%.3g)."), as.integer(p3$cells), as.integer(p3$configurations),
                    p3$max_tp0_diff, as.integer(p3$zrep_cells),
                    as.integer(p3$stem_rows_compared), p3$stem_max_tp0_diff)))
}

## ---- main ---------------------------------------------------------------------------------
ph_main <- function() {
  S <- ph_settings()
  lidR::set_lidr_threads(1L)            # one thread; parallelism by processes
  dir.create(S$OUT, recursive = TRUE, showWarnings = FALSE)
  D <- cfd_read_declared(S$STUDY)
  cf <- ph_configs(D$S, D$S_low)
  cat(sprintf("[posthoc_multichm_depth] STAGE=%s CORES=%d N_BOOT=%d DATASETS=%s; OUT %s\n",
              S$STAGE, S$CORES, S$N_BOOT, paste(S$DATASETS, collapse = ","), ph_rel(S$OUT)))
  cat(sprintf("  %-13s %s\n", cf$name, cf$label), sep = "")
  if (S$STAGE %in% c("all", "score"))
    for (nm in S$DATASETS) ph_stage_score(S, cfd_dataset(S, nm), D, cf)
  if (S$STAGE %in% c("all", "analyze")) ph_stage_analyze(S, D, cf)
  invisible()
}

if (sys.nframe() == 0L) ph_main()
