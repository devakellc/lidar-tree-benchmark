# Unit tests for the multichm_depth confirmation driver
# (scripts/confirm_multichm_depth.R, section A8 of the addendum). Sourcing the
# script defines its helpers without running a stage (guarded by
# `if (sys.nframe() == 0L) cfd_main()`); it sources the depth study's driver,
# which pulls in the gated study's driver, both libraries and the master-table
# resamples. The campaign's library is sourced too, to compare its contrast row
# with the one used here. Synthetic data only: no LiDAR, no NEON data, no file
# of a study or campaign run.
source(file.path("..", "..", "scripts", "confirm_multichm_depth.R"), local = TRUE)
source(file.path("..", "..", "scripts", "multichm_gated_confirm_lib.R"), local = TRUE)

S_LAB <- "k4_r2.5_z5_f5_l0_c0.6"
S_LOW <- "k4_r2.5_z3_f3_l0_c0.6"

## ---- synthetic inputs -----------------------------------------------------------------------
# A study directory with a declared_depth_config.json.
syn_declared <- function(dir = tempfile("cfd_study_"), label = S_LAB, id = 52L,
                         low = list(exists = TRUE, config_id = 58L, label = S_LOW),
                         constants = cd_constants_digest(), grid = cd_grid_digest()) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(list(config_id = id, label = label, low_floor = low,
                            constants_sha256 = constants, grid_sha256 = grid),
                       file.path(dir, "declared_depth_config.json"), auto_unbox = TRUE)
  dir
}

# Scored cells of `labels` on plots of `sites` (name = number of plots) at one
# rung; the stems (n_ref) depend on the plot only, the counts on both.
syn_cells <- function(sites = c(SJER = 12, WREF = 6), rung = "3.2",
                      labels = c("Sx", "Sl", CD_REFERENCES)) {
  out <- list()
  for (s in names(sites)) for (i in seq_len(sites[[s]])) for (k in seq_along(labels)) {
    TP <- 5 + (i %% 4) + k
    nd <- 12 + i %% 5 + 2 * k
    out[[length(out) + 1L]] <- data.frame(
      site = s, plot = sprintf("%s_%03d", s, i), plotType = "tower", rung = rung,
      config = labels[k], n_ref = 14 + i %% 3, n_over = 10, n_under = 4 + i %% 3, n_det = nd,
      TP = TP, tp_core = TP - 1, tp_over = TP - 2, tp_under = 1, n_det0 = nd,
      TP0 = 2 + k / 10 + i / 50, tp_core0 = 2 + k / 10, tp_over0 = 1, tp_under0 = 0.5,
      stringsAsFactors = FALSE)
  }
  x <- do.call(rbind, out)
  rownames(x) <- NULL
  x
}

# One contrast-like row with every metric's d_, lo_ and hi_.
syn_con_row <- function(unit, scope, d, lo, hi, subset = "all plots", pair = CFD_CHECK,
                        n_plots = 20L, n_ref = 100) {
  x <- data.frame(unit = unit, subset = subset, scope = scope, pair = pair, rung = "native",
                  config_a = CD_DECLARED, config_b = "stock", n_plots = n_plots, n_ref = n_ref,
                  a_n_det = 90, b_n_det = 95, stringsAsFactors = FALSE)
  for (m in CFD_CHECK_METRICS) {
    x[[paste0("d_", m)]] <- d; x[[paste0("lo_", m)]] <- lo; x[[paste0("hi_", m)]] <- hi
  }
  x
}

# The rows the A8 reading reads: T1 at the four ladder rungs (validation half),
# then T2, T3 and T4 in each subset.
syn_a8 <- function(t1 = c("not worse", "inconclusive", "not worse", "not worse"),
                   t2 = c("not worse", "not worse"), t3 = c("better", "not worse"),
                   t4 = c("inconclusive", "inconclusive"))
  data.frame(test = c(rep("T1", 4), rep(c("T2", "T3", "T4"), each = 2)),
             subset = c(rep("validation half", 4), rep(CFD_SUBSETS, 3)),
             rung = c(CFD_LADDER_RUNGS, rep("3.2", 2), rep("native", 4)),
             verdict_cF1 = c(t1, t2, t3, t4), verdict_note_cF1 = "", stringsAsFactors = FALSE)

## ---- arguments and datasets -----------------------------------------------------------------
test_that("sourcing runs nothing; arguments parse as KEY=VALUE with at most 8 workers", {
  expect_true(is.function(cfd_main))
  w <- tempfile("cfd_work_")
  S <- cfd_settings(character(), work = w)
  expect_identical(S$STAGE, "all")
  expect_identical(S$DATASETS, CFD_DATASETS$name)
  expect_identical(c(S$CORES, S$N_BOOT), c(4L, MT_N_BOOT))
  # WORK and OUT in canonical absolute form; the defaults hang from WORK
  wc <- file.path(normalizePath(dirname(w)), basename(w))
  expect_identical(S$WORK, wc)
  expect_identical(S$OUT, file.path(wc, "multichm_depth_runs", "confirm"))
  expect_identical(S$STUDY, file.path(wc, "multichm_depth_runs", "neon", "multichm_depth"))
  expect_identical(S$CAMPAIGN, file.path(wc, "multichm_gated_confirmation"))
  S2 <- cfd_settings(c("CORES=8", "DATASETS=ql2,ca2017", "STAGE=contrasts", "N_BOOT=50"), work = w)
  expect_identical(S2[c("CORES", "DATASETS", "STAGE", "N_BOOT")],
                   list(CORES = 8L, DATASETS = c("ql2", "ca2017"), STAGE = "contrasts",
                        N_BOOT = 50L))
  expect_error(cfd_settings("CORES=9", work = w), "at most 8")
  expect_error(cfd_settings("CORES=0", work = w), "whole numbers")
  expect_error(cfd_settings("CORES=2.5", work = w), "whole numbers")
  expect_error(cfd_settings("N_BOOT=x", work = w), "whole numbers")
  expect_error(cfd_settings("STAGE=candidates", work = w), "STAGE must be")
  expect_error(cfd_settings("DATASETS=ql2,harv", work = w), "DATASETS must be")
  expect_error(cfd_settings("DATASETS=ql2,ql2", work = w), "DATASETS must be")
  # outputs never go into (or around) the study, the campaign or a frozen root
  for (o in c(file.path(w, "multichm_gated_confirmation", "x"),
              file.path(w, "multichm_depth_runs", "neon", "multichm_depth"),
              file.path(w, "neon", "frozen_2021"), file.path(w, "sparse_2017"), w))
    expect_error(cfd_settings(paste0("OUT=", o), work = w), "overlaps a read-only input")
})

test_that("paths are compared in canonical form: relative, `..` and symbolic links resolved", {
  skip_on_os("windows")
  root <- tempfile("cfd_tree_")
  for (d in c(CFD_STUDY_DIR, "multichm_gated_confirmation"))
    dir.create(file.path(root, "work", d), recursive = TRUE)
  root <- normalizePath(root)
  W <- file.path(root, "work")
  withr::local_dir(root)
  file.symlink(W, file.path(root, "alias"))
  file.symlink(file.path(W, CFD_STUDY_DIR), file.path(root, "study_link"))
  file.symlink(file.path(root, "nowhere"), file.path(root, "dangling"))
  # absolute against the working directory; ".", empty components and a
  # trailing slash dropped; `..` below a missing component applied
  expect_identical(cfd_canon_path("work/a/b"), file.path(W, "a", "b"))
  expect_identical(cfd_canon_path("work/./a//b/"), file.path(W, "a", "b"))
  expect_identical(cfd_canon_path("work/zz/../a"), file.path(W, "a"))
  expect_identical(cfd_canon_path(file.path(W, "zz", "..", "..", "x")), file.path(root, "x"))
  expect_identical(cfd_canon_path(file.path(W, "multichm_depth_runs", "..", "x")),
                   file.path(W, "x"))
  # a symbolic link in the existing part is followed, also behind a `..`
  expect_identical(cfd_canon_path("alias/multichm_depth_runs/new"),
                   file.path(W, "multichm_depth_runs", "new"))
  expect_identical(cfd_canon_path("alias/zz/../multichm_depth_runs"),
                   file.path(W, "multichm_depth_runs"))
  expect_identical(cfd_canon_path("work/zz/../../study_link/x"), file.path(W, CFD_STUDY_DIR, "x"))
  expect_error(cfd_canon_path("dangling/x"), "points nowhere")
  expect_identical(cfd_canon_path("/"), "/")
  expect_true(cfd_path_overlap("/a/b", "/a/b/c"))
  expect_true(cfd_path_overlap("/a/b/c", "/a/b"))
  expect_true(cfd_path_overlap("/a/b", "/a/b"))
  expect_false(cfd_path_overlap("/a/b", "/a/bc"))
  expect_true(cfd_path_overlap("/", "/a"))
  for (wk in list(W, "work")) {
    # a relative OUT that does not exist yet and lies inside the study
    expect_error(cfd_settings("OUT=work/multichm_depth_runs/neon/multichm_depth/x", work = wk),
                 "overlaps a read-only input \\(the study")
    # an OUT with `..`, relative or absolute
    for (o in c("work/multichm_depth_runs/zz/../neon/multichm_depth",
                file.path(W, "multichm_depth_runs", "zz", "..", "confirm"),
                "work/multichm_depth_runs/zz/../confirm_new"))
      expect_error(cfd_settings(paste0("OUT=", o), work = wk), "has a `..` component")
    # STUDY= elsewhere: the study's run of record stays read-only
    expect_error(cfd_settings(c("STUDY=elsewhere",
                                "OUT=work/multichm_depth_runs/neon/multichm_depth"), work = wk),
                 "the study's run of record")
    expect_error(cfd_settings(c("STUDY=elsewhere", paste0("OUT=", W)), work = wk),
                 "the study's run of record")
    # a symbolic link in an existing part is followed
    expect_error(cfd_settings("OUT=alias/multichm_depth_runs/neon/multichm_depth/x", work = wk),
                 "overlaps a read-only input \\(the study")
    expect_error(cfd_settings("OUT=study_link/x", work = wk), "overlaps a read-only input")
    expect_error(cfd_settings("OUT=alias", work = wk), "overlaps a read-only input")
    expect_error(cfd_settings("OUT=alias/multichm_gated_confirmation/x", work = wk),
                 "the campaign")
    # a legitimate new relative OUT: accepted, canonical, nothing written
    S <- cfd_settings("OUT=work/multichm_depth_runs/confirm_new", work = wk)
    expect_identical(S$OUT, file.path(W, "multichm_depth_runs", "confirm_new"))
    expect_false(dir.exists(S$OUT))
    expect_identical(cfd_settings("OUT=alias/multichm_depth_runs/confirm_new", work = wk)$OUT,
                     S$OUT)
    # the default OUT is kept canonical
    expect_identical(cfd_settings(character(), work = wk)$OUT, file.path(W, CFD_CONFIRM_DIR))
  }
  # messages print paths under the repository relative to it
  expect_identical(cfd_rel(file.path(.ROOT, "work", "x")), file.path("work", "x"))
  expect_identical(cfd_rel(c("/elsewhere/x", .ROOT)), c("/elsewhere/x", "."))
  # the helpers are the study driver's, under both names
  expect_identical(cfd_canon_path, cd_canon_path)
  expect_identical(cfd_check_out, cd_check_out)
  expect_identical(cfd_rel, cd_rel)
})

test_that("every key the driver reads is accepted; any other stops with the list of keys", {
  w <- tempfile("cfd_work_")
  wc <- file.path(normalizePath(dirname(w)), basename(w))
  expect_identical(CFD_KEYS, c("STAGE", "DATASETS", "CORES", "N_BOOT", "WORK", "STUDY",
                               "CAMPAIGN", "OUT"))
  every <- c("STAGE=contrasts", "DATASETS=ql2", "CORES=2", "N_BOOT=10", paste0("WORK=", w),
             "STUDY=/s", "CAMPAIGN=/c", paste0("OUT=", file.path(w, "o")))
  expect_identical(sub("=.*", "", every), CFD_KEYS)
  S <- cfd_settings(every, work = "/elsewhere")
  expect_identical(S[c("WORK", "STAGE", "DATASETS", "CORES", "N_BOOT", "STUDY", "CAMPAIGN", "OUT")],
                   list(WORK = wc, STAGE = "contrasts", DATASETS = "ql2", CORES = 2L, N_BOOT = 10L,
                        STUDY = "/s", CAMPAIGN = "/c", OUT = file.path(wc, "o")))
  # a mistyped key no longer falls back to the run of record
  keys <- paste(CFD_KEYS, collapse = ", ")
  expect_error(cfd_settings("OUTDIR=/tmp/x", work = w),
               paste0("unknown argument OUTDIR; the keys are ", keys), fixed = TRUE)
  for (k in c("OUTPUT=x", "CONFIRM=x", "UNBLIND=1", "GATED=x", "work=x", "DATASET=ql2"))
    expect_error(cfd_settings(c("STAGE=contrasts", k), work = w),
                 paste0("unknown argument ", sub("=.*", "", k), ";"), fixed = TRUE)
  expect_error(cfd_settings(c("A=1", "B=2"), work = w), "unknown argument A, B;", fixed = TRUE)
})

test_that("OUT stays out of the directories each dataset's stems and plot centroids link to", {
  skip_on_os("windows")
  root <- normalizePath(tempfile("cfd_ref_"), mustWork = FALSE)
  W <- file.path(root, "work")
  dir.create(file.path(W, CFD_STUDY_DIR), recursive = TRUE)
  put <- function(f) { dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
                       writeLines("x", f); f }
  link <- function(target, job, site, file) {
    s <- file.path(job, "neon", site)
    dir.create(s, recursive = TRUE, showWarnings = FALSE)
    file.symlink(target, file.path(s, file))
  }
  job <- function(nm) cfd_dataset(cfd_settings(character(), work = W), nm)$job
  # ql2's SJER stems link into ql2ref/SJER; wa2019's WREF centroids link into
  # mid/WREF, whose file links (relative target) into final/WREF; ca2017's SJER
  # stems point nowhere
  link(put(file.path(root, "ql2ref", "SJER", CD_REF_FILES[1])), job("ql2"), "SJER",
       CD_REF_FILES[1])
  put(file.path(root, "final", "WREF", CD_REF_FILES[2]))
  dir.create(file.path(root, "mid", "WREF"), recursive = TRUE)
  file.symlink(file.path("..", "..", "final", "WREF", CD_REF_FILES[2]),
               file.path(root, "mid", "WREF", CD_REF_FILES[2]))
  link(file.path(root, "mid", "WREF", CD_REF_FILES[2]), job("wa2019"), "WREF", CD_REF_FILES[2])
  link(file.path(root, "nowhere", CD_REF_FILES[1]), job("ca2017"), "SJER", CD_REF_FILES[1])
  expect_identical(cfd_reference_dirs, cd_reference_dirs)
  withr::local_dir(root)
  ro <- "overlaps a read-only input (the stems and plot centroids"
  for (o in c("ql2ref/SJER", "ql2ref/SJER/x", "ql2ref", "mid/WREF/x", "final/WREF", "final"))
    expect_error(cfd_settings(paste0("OUT=", o), work = W), ro, fixed = TRUE)
  expect_error(cfd_settings(paste0("OUT=", file.path(root, "final", "WREF", "x")), work = W), ro,
               fixed = TRUE)
  # through a symbolic link to a protected directory
  file.symlink(file.path(root, "ql2ref"), file.path(root, "ql2_link"))
  expect_error(cfd_settings("OUT=ql2_link/SJER/x", work = W), ro, fixed = TRUE)
  # only the datasets of the run: a dataset not scored, a site without a link
  expect_identical(cfd_settings(c("DATASETS=wa2019", "OUT=ql2ref/SJER/x"), work = W)$OUT,
                   file.path(root, "ql2ref", "SJER", "x"))
  expect_error(cfd_settings(c("DATASETS=wa2019", "OUT=final/WREF/x"), work = W), ro, fixed = TRUE)
  for (o in c("ql2ref/WREF", "mid/SJER", "nowhere/x")) {
    S <- cfd_settings(paste0("OUT=", o), work = W)
    expect_identical(S$OUT, file.path(root, o))
    expect_false(dir.exists(S$OUT))
  }
  # the default OUT passes
  expect_identical(cfd_settings(character(), work = W)$OUT, file.path(W, CFD_CONFIRM_DIR))
})

test_that("WORK is canonical before defaults are derived; `..` is refused in a given OUT only", {
  skip_on_os("windows")
  root <- normalizePath(tempfile("cfd_rel_"), mustWork = FALSE)
  W <- file.path(root, "work")
  dir.create(file.path(W, CFD_STUDY_DIR), recursive = TRUE)
  dir.create(file.path(root, "scripts"))
  withr::local_dir(file.path(root, "scripts"))
  # WORK=../work from a subdirectory: every default from its canonical form
  for (S in list(cfd_settings("WORK=../work", work = "/elsewhere"),
                 cfd_settings(character(), work = "../work"),
                 cfd_settings("WORK=../scripts/../work", work = "/elsewhere"))) {
    expect_identical(S$WORK, W)
    expect_identical(S$OUT, file.path(W, CFD_CONFIRM_DIR))
    expect_identical(S$STUDY, file.path(W, CFD_STUDY_DIR))
    expect_identical(S$CAMPAIGN, file.path(W, "multichm_gated_confirmation"))
    expect_identical(cfd_dataset(S, "ql2")$root, file.path(W, "neon", "frozen_2021_ql2"))
  }
  # the run of record under the canonical WORK stays read-only
  expect_error(cfd_settings(c("WORK=../work", paste0("OUT=", file.path(W, CFD_STUDY_DIR, "x")))),
               "overlaps a read-only input (the study", fixed = TRUE)
  # an OUT the user gave with `..` is refused, a relative one without is not
  expect_error(cfd_settings(c("WORK=../work", "OUT=../work/multichm_depth_runs/x")),
               "has a `..` component", fixed = TRUE)
  expect_identical(cfd_settings(c("WORK=../work", "OUT=fresh"))$OUT,
                   file.path(root, "scripts", "fresh"))
  # the guard itself: `..` is tested only in an OUT given by the user
  expect_identical(cfd_check_out(file.path(W, "zz", "..", "x"), character(), given = FALSE),
                   file.path(W, "x"))
  expect_error(cfd_check_out(file.path(W, "zz", "..", "x"), character()), "has a `..` component")
  expect_error(cfd_check_out(file.path(W, "zz", "..", CFD_STUDY_DIR),
                             cfd_named("the study", file.path(W, CFD_STUDY_DIR)), given = FALSE),
               "overlaps a read-only input (the study", fixed = TRUE)
})

test_that("the datasets name the campaign's runs, roots, sites and rungs; T4 pools two", {
  S <- cfd_settings(character(), work = "/w")
  q <- cfd_dataset(S, "ql2")
  expect_identical(q[c("dir", "cdir", "job", "root", "rung", "out")],
                   list(dir = "/w/multichm_gated_confirmation/ql2",
                        cdir = "/w/multichm_gated_confirmation/ql2/candidates",
                        job = "/w/multichm_gated_confirmation/ql2/job",
                        root = "/w/neon/frozen_2021_ql2", rung = "3.2",
                        out = "/w/multichm_depth_runs/confirm/ql2"))
  expect_identical(q$sites, CV_FIVE)
  roots <- vapply(CFD_DATASETS$name, function(n) cfd_dataset(S, n)$root, "")
  expect_identical(unname(roots), c("/w/neon/frozen_2021_ql2",
                                    "/w/epoch_wa_2019/neon/frozen_2019", "/w/neon/frozen_2021",
                                    "/w/sparse_2018/neon/frozen_2018",
                                    "/w/sparse_2017/neon/frozen_2017", "/w/neon/frozen_2021"))
  expect_identical(cfd_dataset(S, "wa2019")$dir, "/w/multichm_gated_confirmation/epoch_wa/epoch_2019")
  expect_identical(cfd_dataset(S, "ca2021_shared")$sites, c("SJER", "SOAP", "TEAK"))
  expect_identical(cfd_dataset(S, "ca2021_shared")$rung, "native")
  expect_identical(cfd_dataset(S, "ca2018")$sites, c("SOAP", "TEAK"))
  expect_error(cfd_dataset(S, "harv"), "unknown dataset")
  # every dataset is in exactly one unit; T4 pools the two sparse flights
  parts <- unlist(strsplit(CFD_UNITS$parts, ","))
  expect_setequal(parts, CFD_DATASETS$name)
  expect_identical(anyDuplicated(parts), 0L)
  expect_identical(CFD_UNITS$parts[CFD_UNITS$unit == "ca_sparse_pooled"], "ca2018,ca2017")
  expect_identical(CFD_UNITS$test, c("T2", "T3", "T3", "T4", "T4"))
  expect_identical(CFD_UNITS$role, c("test", "test", "comparison", "test", "comparison"))
  # each unit's reading scope is its widest one, and one it can form
  for (u in seq_len(nrow(CFD_UNITS))) {
    sites <- unique(unlist(lapply(strsplit(CFD_UNITS$parts[u], ",")[[1]], function(p)
      cfd_dataset(S, p)$sites)))
    expect_identical(CFD_UNITS$reading_scope[u], names(cfd_scopes(sites))[1])
  }
})

## ---- fixed configurations, split, scopes, subsets, pairs ------------------------------------
test_that("S and S_low are read from the study's record and must be its grid rows", {
  d <- syn_declared()
  D <- cfd_read_declared(d)
  expect_identical(D[c("S", "S_id", "S_low", "S_low_id")],
                   list(S = S_LAB, S_id = 52L, S_low = S_LOW, S_low_id = 58L))
  expect_identical(D$grid$label, c(S_LAB, S_LOW))
  expect_identical(D$grid$config_id, c(52L, 58L))
  expect_identical(D$grid[, names(D$grid) != "config_id"],
                   {g <- mcd_grid()[c(52, 58), names(mcd_grid()) != "config_id"]
                    rownames(g) <- NULL; g})
  expect_identical(D$sha256, digest::digest(file = file.path(d, "declared_depth_config.json"),
                                            algo = "sha256"))
  D0 <- cfd_read_declared(syn_declared(low = list(exists = FALSE)))
  expect_null(D0$S_low)
  expect_null(D0$S_low_id)
  expect_identical(D0$grid$label, S_LAB)
  expect_error(cfd_read_declared(syn_declared(label = "k9_r2.5_z5_f5_l0_c0.6")), "not a label")
  expect_error(cfd_read_declared(syn_declared(id = 53L)), "is not config_id 53")
  expect_error(cfd_read_declared(syn_declared(low = list(exists = TRUE, config_id = 58L,
                                                         label = "k4_r9_z3_f3_l0_c0.6"))),
               "S_low is not a label")
  expect_error(cfd_read_declared(syn_declared(low = list(exists = TRUE, config_id = 52L,
                                                         label = S_LAB))), "S_low equals S")
  expect_error(cfd_read_declared(syn_declared(low = NULL)), "no low_floor record")
  expect_error(cfd_read_declared(syn_declared(constants = "x")), "other constants")
  expect_error(cfd_read_declared(syn_declared(grid = "x")), "another grid")
  expect_error(cfd_read_declared(tempfile("cfd_none_")), "no declared depth configuration")
})

test_that("the contrasts stage refuses cells scored under other constants, grids or inputs", {
  root <- normalizePath(tempfile("cfd_scored_"), mustWork = FALSE)
  S <- cfd_settings(character(), work = file.path(root, "work"))
  D <- cfd_read_declared(syn_declared())
  ds <- cfd_dataset(S, "ql2")
  for (d in c(ds$root, ds$dir, ds$out)) dir.create(d, recursive = TRUE)
  writeLines(c("file,sha256", "a.laz,0"), file.path(ds$root, "clip_manifest.csv"))
  camp <- file.path(ds$dir, "cells.csv")
  writeLines("site,plot", camp)
  cells <- syn_cells(c(SJER = 2, WREF = 1))
  write.csv(cells, file.path(ds$out, "cells.csv"), row.names = FALSE)
  rec <- list(dataset = "ql2", clip_manifest_sha256 = frozen_root_id(ds$root),
              dataset_cells_csv_sha256 = cd_file_sha(camp), gated_grid_sha256 = cv_grid_digest(),
              depth_grid_sha256 = cd_grid_digest(), constants_sha256 = cd_constants_digest(),
              declared_depth_config = list(sha256 = D$sha256, S = D$S, S_id = D$S_id,
                                           S_low = D$S_low, S_low_id = D$S_low_id),
              S1 = list(status = "pass", n = 24L))
  put <- function(r) cd_write_json(r, file.path(ds$out, "cells.config.json"))
  refused <- function(r, pattern) {
    put(r)
    expect_error(cfd_read_scored(S, ds, D), pattern, fixed = TRUE)
    put(rec)
  }
  put(rec)
  x <- cfd_read_scored(S, ds, D)
  expect_identical(nrow(x$cells), nrow(cells))
  expect_identical(unique(x$cells$rung), "3.2")
  # another digest, or none, of the constants, the depth grid or the gated grid
  msg <- "ql2: the cells were scored with other constants or grids; re-run STAGE=score"
  for (k in c("constants_sha256", "depth_grid_sha256", "gated_grid_sha256")) {
    refused(utils::modifyList(rec, stats::setNames(list("x"), k)), msg)
    refused(rec[setdiff(names(rec), k)], msg)
  }
  # the declared configurations and S1, the dataset's cells.csv and root
  refused(utils::modifyList(rec, list(S1 = list(status = "fail"))), "without a passed S1")
  refused(utils::modifyList(rec, list(declared_depth_config = list(S = S_LOW))),
          "other declared configurations")
  refused(utils::modifyList(rec, list(clip_manifest_sha256 = "x")), "cells.csv or root changed")
  cat("x\n", file = camp, append = TRUE)
  expect_error(cfd_read_scored(S, ds, D), "cells.csv or root changed", fixed = TRUE)
  writeLines("site,plot", camp)
  expect_identical(nrow(cfd_read_scored(S, ds, D)$cells), nrow(cells))
  unlink(file.path(ds$out, "cells.config.json"))
  expect_error(cfd_read_scored(S, ds, D), "ql2: no scored cells record at")
})

test_that("the validation half is the side `valid` of the study's split.csv", {
  d <- tempfile("cfd_split_"); dir.create(d)
  sp <- data.frame(site = c("SJER", "SJER", "WREF"), plot = c("SJER_1", "SJER_2", "WREF_9"),
                   split = c("calib", "valid", "valid"))
  write.csv(sp, file.path(d, "split.csv"), row.names = FALSE)
  expect_identical(cfd_valid_ids(d), c("SJER::SJER_2", "WREF::WREF_9"))
  write.csv(transform(sp, split = c("calib", "valid", NA)), file.path(d, "split.csv"),
            row.names = FALSE)
  expect_error(cfd_valid_ids(d), "not a split table")
  write.csv(sp[c(1, 1, 2), ], file.path(d, "split.csv"), row.names = FALSE)
  expect_error(cfd_valid_ids(d), "lists a plot twice")
  expect_error(cfd_valid_ids(tempfile("cfd_none_")), "no split")
})

test_that("scopes are those a unit can form; subsets and pairs are those of A8", {
  expect_identical(names(cfd_scopes(CV_FIVE)),
                   c("Five sites", "California", "Washington", CV_FIVE))
  expect_identical(cfd_scopes(CV_FIVE)$California, c("SJER", "SOAP", "TEAK"))
  expect_identical(names(cfd_scopes(c("ABBY", "WREF"))), c("Washington", "WREF", "ABBY"))
  expect_identical(names(cfd_scopes(c("TEAK", "SOAP", "SJER"))),
                   c("California", "SJER", "SOAP", "TEAK"))
  # a region needs all of its sites
  expect_identical(names(cfd_scopes(c("SOAP", "TEAK"))), c("SOAP", "TEAK"))
  expect_identical(cfd_scopes(c("SOAP", "TEAK"))$SOAP, "SOAP")
  ids <- c("SJER::a", "SJER::b", "WREF::c")
  s <- cfd_subset_ids(ids, c("SJER::b", "WREF::c", "ABBY::z"))
  expect_identical(names(s), c("validation half", "all plots"))
  expect_identical(s[["validation half"]], c("SJER::b", "WREF::c"))
  expect_identical(s[["all plots"]], ids)
  p <- cfd_pairs("Sx", "Sl")
  expect_identical(p$pair, c("S_minus_declared", "S_minus_stock", "S_low_minus_declared",
                             "S_low_minus_S", "declared_minus_stock"))
  expect_identical(p$a, c("Sx", "Sx", "Sl", "Sl", CD_DECLARED))
  expect_identical(p$b, c(CD_DECLARED, "stock", CD_DECLARED, "Sx", "stock"))
  expect_identical(cfd_pairs("Sx")$pair, c("S_minus_declared", "S_minus_stock",
                                           "declared_minus_stock"))
})

## ---- identities -----------------------------------------------------------------------------
test_that("the identities are checked per prepared clip, closed and open", {
  las <- synth_closed_stand(1)
  P <- mcg_prepare(las, 0.5)
  f <- mcd_features(P$cand, las, 5)
  x <- cfd_identities_cell(P, f)
  expect_true(x$A && x$B)
  expect_identical(x$B_n_gated, as.numeric(nrow(mcg_apply(P, MCG_STOCK))))
  expect_identical(x$A_n_gated, as.numeric(nrow(mcg_apply(P, mcd_identities()$A$gated))))
  expect_identical(x$A_n_depth, x$A_n_gated)
  # the gated accepted set is mcg_apply's
  acc <- cfd_gated_accepted(P, MCG_DECLARED)
  expect_identical(sum(acc), nrow(mcg_apply(P, MCG_DECLARED)))
  for (cover in c(0.6, 0.5999, 0.2)) {
    y <- cfd_identities_cell(replace(P, "cover", list(cover)), f)
    expect_true(y$A && y$B)
  }
  # a clip without candidates
  P0 <- P; P0$cand <- P$cand[0]
  z <- cfd_identities_cell(P0, f[0])
  expect_true(z$A && z$B)
  expect_identical(c(z$A_n_depth, z$B_n_gated), c(0, 0))
  # a feature table of other candidates is refused, not compared
  expect_error(cfd_identities_cell(P, f[rev(seq_len(nrow(f)))]), "differs")
})

## ---- contrasts ------------------------------------------------------------------------------
test_that("a unit's contrasts cover its subsets, scopes and pairs with the A2 reading", {
  cells <- syn_cells()
  ids <- unique(cv_ids(cells))
  valid <- ids[c(TRUE, FALSE)]
  unit <- data.frame(unit = "u", test = "T2", role = "test", reading_scope = "SJER",
                     stringsAsFactors = FALSE)
  v <- cfd_unit_contrasts(cells, unit, "3.2", valid, cfd_pairs("Sx", "Sl"), n_boot = 50)
  expect_identical(nrow(v), 2L * 2L * 5L)
  expect_identical(unique(v$subset), CFD_SUBSETS)
  expect_identical(unique(v$scope), c("SJER", "WREF"))
  expect_identical(v$split, v$subset)
  expect_identical(v$reading, v$scope == "SJER")
  n <- function(su, sc) unique(v$n_plots[v$subset == su & v$scope == sc])
  expect_identical(c(n("all plots", "SJER"), n("validation half", "SJER"), n("all plots", "WREF"),
                     n("validation half", "WREF")), c(12L, 6L, 6L, 3L))
  # a scope under 10 plots is reported and not read
  expect_true(all(v$verdict_cF1[v$n_plots < 10] == CD_NOT_READ))
  expect_true(all(v$verdict_cF1[v$n_plots >= 10] %in%
                    c("better", "worse", "not worse", "inconclusive")))
  expect_identical(v$verdict_cF1[v$n_plots >= 10],
                   cd_verdict(v$lo_cF1, v$hi_cF1)[v$n_plots >= 10])
  # each row is the study's cv_contrast_row on those plots
  sj <- ids[startsWith(ids, "SJER")]
  r <- cv_contrast_row(cells, sj, "3.2", "Sx", CD_DECLARED, 50, MT_SEED, data.frame(x = 1))
  w <- v[v$subset == "all plots" & v$scope == "SJER" & v$pair == CFD_PRIMARY, ]
  for (k in c("d_cF1", "lo_cF1", "hi_cF1", "d_recall", "hi_precision", "a_n_det", "b_cF1"))
    expect_identical(w[[k]], r[[k]])
  # and, for declared minus stock, the campaign's contrast row (mcgc_contrast_row,
  # plots sorted) gives the same numbers: one bootstrap over the same plots
  m <- mcgc_contrast_row(cells, cv_ids(cells), rev(sj), CD_DECLARED, "stock", 50, MT_SEED)
  w2 <- v[v$subset == "all plots" & v$scope == "SJER" & v$pair == CFD_CHECK, ]
  for (mt in CFD_CHECK_METRICS) for (p in c("d_", "lo_", "hi_"))
    expect_identical(w2[[paste0(p, mt)]], m[[paste0(p, mt)]])
  # without S_low's rows its pairs give no row
  v0 <- cfd_unit_contrasts(cells[cells$config != "Sl", ], unit, "3.2", valid,
                           cfd_pairs("Sx", "Sl"), n_boot = 20)
  expect_false(any(grepl("S_low", v0$pair)))
  expect_null(cfd_unit_contrasts(cells, unit, "native", valid, cfd_pairs("Sx", "Sl"), n_boot = 20))
})

test_that("pooled datasets must not share plots", {
  a <- syn_cells(c(SOAP = 2), rung = "native", labels = c("stock", CD_DECLARED))
  b <- syn_cells(c(SJER = 1), rung = "native", labels = c("stock", CD_DECLARED))
  expect_identical(nrow(cfd_pool_cells(list(a, b))), 6L)
  expect_error(cfd_pool_cells(list(a, b, a)), "share plots: SOAP::SOAP_001")
})

test_that("the campaign check pairs declared minus stock on all plots by data, level and scope", {
  con <- rbind(syn_con_row("wa2019", "Washington", 0.03, 0.01, 0.05),
               syn_con_row("wa2019", "WREF", 0.02, -0.01, 0.04),
               syn_con_row("wa2019", "Washington", 0.5, 0.4, 0.6, subset = "validation half"),
               syn_con_row("wa2019", "Washington", 0.9, 0.8, 1, pair = CFD_PRIMARY))
  camp <- syn_con_row("x", "Washington", 0.03 + 1e-12, 0.01, 0.05 + 2e-12)
  camp$dataset <- "Washington 2019 flight"; camp$level <- "native"
  camp$contrast <- CFD_CAMPAIGN_PAIR
  other <- transform(camp, scope = "ABBY", d_cF1 = 9)       # a row of no counterpart here
  chk <- cfd_campaign_check(con, rbind(camp, other))
  expect_identical(nrow(chk), 2L)                           # declared minus stock, all plots
  expect_identical(chk$scope, c("Washington", "WREF"))
  expect_identical(chk$matched, c(TRUE, FALSE))
  expect_true(chk$same_plots_stems_dets[1])
  expect_equal(chk$abs_d[1], 1e-12, tolerance = 1e-6)
  expect_identical(chk$abs_lo[1], 0)
  expect_equal(chk$abs_hi[1], 2e-12, tolerance = 1e-6)
  expect_equal(chk$max_abs_other[1], 2e-12, tolerance = 1e-6)
  expect_true(is.na(chk$abs_d[2]))
  # another stem count or another level is not the same data
  expect_false(cfd_campaign_check(con, transform(camp, n_ref = 101))$same_plots_stems_dets[1])
  expect_false(cfd_campaign_check(con, transform(camp, level = "8"))$matched[1])
  expect_error(cfd_campaign_check(con, rbind(camp, camp)), "holds 2 rows")
})

## ---- T1 and the reading of A8 ---------------------------------------------------------------
test_that("T1 is the study's ladder of S minus declared on the validation plots", {
  lad <- data.frame(analysis = c("ladder", "ladder", "ladder", "low_floor_ladder", "ladder",
                                 "ladder", "ladder"),
                    config_a = c("Sx", "Sx", "Sx", "Sx", "Sx", "Sx", "Sy"),
                    config_b = c(CD_DECLARED, CD_DECLARED, "stock", CD_DECLARED, CD_DECLARED,
                                 CD_DECLARED, CD_DECLARED),
                    split = "valid", rung = c("1", "8", "8", "8", "native", "4", "2"),
                    scope = c("Five sites", "Five sites", "Five sites", "Five sites",
                              "Five sites", "California", "Five sites"),
                    stringsAsFactors = FALSE)
  t1 <- cfd_t1(lad, "Sx")
  expect_identical(t1$rung, c("8", "1", "4"))
  expect_identical(t1$scope, c("Five sites", "Five sites", "California"))
  expect_identical(nrow(cfd_t1(transform(lad, split = "calib"), "Sx")), 0L)
})

test_that("the A8 rows are T1's Five sites rows and each test unit's reading scope", {
  t1 <- data.frame(scope = c("Five sites", "Five sites", "California"), rung = c("4", "8", "8"),
                   n_plots = 49L, d_cF1 = 0.01, lo_cF1 = -0.01, hi_cF1 = 0.03,
                   verdict_cF1 = "not worse", verdict_note_cF1 = NA, stringsAsFactors = FALSE)
  con <- data.frame(unit = c("ql2", "ql2", "wa2021_shared", "wa2019", "ca_sparse_pooled",
                             "wa2019"),
                    test = c("T2", "T2", "T3", "T3", "T4", "T3"), subset = "all plots",
                    scope = c("Five sites", "California", "Washington", "Washington",
                              "California", "WREF"),
                    rung = c("3.2", "3.2", "native", "native", "native", "native"),
                    pair = c(rep(CFD_PRIMARY, 5), CFD_PRIMARY), n_plots = 20L, d_cF1 = 0,
                    lo_cF1 = 0, hi_cF1 = 0, verdict_cF1 = "better", verdict_note_cF1 = "",
                    stringsAsFactors = FALSE)
  con <- rbind(con, transform(con[1, ], pair = CFD_CHECK))
  r <- cfd_a8_rows(t1, con)
  expect_identical(names(r), CFD_A8_COLS)
  expect_identical(r$test, c("T1", "T1", "T2", "T3", "T4"))
  expect_identical(r$unit, c("study ladder", "study ladder", "ql2", "wa2019", "ca_sparse_pooled"))
  expect_identical(r$rung[1:2], c("8", "4"))
  expect_identical(r$scope, c("Five sites", "Five sites", "Five sites", "Washington",
                              "California"))
  expect_identical(r$verdict_note_cF1[1:2], c("", ""))
})

test_that("A8: T2 and T3 must be better or not worse, no test worse, in either subset", {
  a <- cfd_a8_reading(syn_a8(), "Sx")
  expect_true(a$carries)
  expect_identical(a$failing, character())
  expect_match(a$sentence, "The selection `Sx` carries over \\(A8\\)")
  a <- cfd_a8_reading(syn_a8(t2 = c("not worse", "inconclusive")), "Sx")
  expect_false(a$carries)
  expect_identical(a$failing, "T2 (all plots: inconclusive)")
  expect_match(a$sentence, "2021 native clips only. Failing tests: T2 \\(all plots")
  a <- cfd_a8_reading(syn_a8(t3 = c(CD_NOT_READ, "better")))
  expect_identical(a$failing, sprintf("T3 (validation half: %s)", CD_NOT_READ))
  # inconclusive on T1 or T4 passes, worse there fails
  a <- cfd_a8_reading(syn_a8(t1 = c("not worse", "worse", "inconclusive", "better"),
                             t4 = c("worse", "inconclusive")))
  expect_identical(a$failing, c("T1 (validation half, rung 4: worse)",
                                "T4 (validation half: worse)"))
  a <- cfd_a8_reading(syn_a8(t2 = c("worse", "better"), t4 = c("better", "worse")))
  expect_identical(a$failing, c("T2 (validation half: worse)", "T4 (all plots: worse)"))
  # the margin note travels with a "worse"
  r <- syn_a8(t2 = c("worse", "better"))
  r$verdict_note_cF1[r$test == "T2" & r$subset == "validation half"] <- CD_MARGIN_NOTE
  expect_identical(cfd_a8_reading(r)$failing,
                   "T2 (validation half: worse (within the 0.02 margin))")
  # a missing row fails its test
  r <- syn_a8(); r <- r[!(r$test == "T3" & r$subset == "all plots"), ]
  expect_identical(cfd_a8_reading(r)$failing, "T3 (all plots: no contrast)")
  r <- syn_a8(); r <- r[!(r$test == "T1" & r$rung == "2"), ]
  expect_identical(cfd_a8_reading(r)$failing, "T1 (validation half: no single row at rung 2)")
  r <- syn_a8(); r <- r[!(r$test == "T4" & r$subset == "validation half"), ]
  expect_identical(cfd_a8_reading(r)$failing, "T4 (validation half: no contrast)")
  # several failures of one test are named together
  a <- cfd_a8_reading(syn_a8(t2 = c("inconclusive", "worse")))
  expect_identical(a$failing, "T2 (validation half: inconclusive; all plots: worse)")
})
