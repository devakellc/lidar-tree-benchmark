# Unit tests for the post hoc analyses behind the multichm_depth arm's
# configuration (scripts/posthoc_multichm_depth.R). Sourcing the script defines
# its helpers without running a stage (guarded by
# `if (sys.nframe() == 0L) ph_main()`); it sources the confirmation driver,
# which pulls in the depth study's driver, the gated study's driver, both
# libraries and the master-table resamples. Synthetic data only: no LiDAR, no
# NEON data, no file of a study or confirmation run.
source(file.path("..", "..", "scripts", "posthoc_multichm_depth.R"), local = TRUE)

S_LAB <- "k4_r2.5_z5_f5_l0_c0.6"
S_LOW <- "k4_r2.5_z3_f3_l0_c0.6"

## ---- synthetic inputs -----------------------------------------------------------------------
# Scored cells of `labels` on plots of `sites` (name = number of plots) at one
# rung; the stems (n_ref) depend on the plot only, the counts on both; every
# second plot is a closed stand (cover 0.7).
syn_cells <- function(sites = c(SJER = 12, WREF = 6), rung = "native",
                      labels = ph_configs(S_LAB, S_LOW)$label, prefix = NULL) {
  out <- list()
  for (s in names(sites)) for (i in seq_len(sites[[s]])) for (k in seq_along(labels)) {
    TP <- 5 + (i %% 4) + k %% 3
    nd <- 12 + i %% 5 + 2 * (k %% 4)
    out[[length(out) + 1L]] <- data.frame(
      site = s, plot = sprintf("%s_%s%03d", s, if (is.null(prefix)) "" else prefix, i),
      plotType = "tower", rung = rung, cover = if (i %% 2) 0.7 else 0.4, config = labels[k],
      n_ref = 14 + i %% 3, n_over = 10, n_under = 4 + i %% 3, n_det = nd, TP = TP,
      tp_core = TP - 1, tp_over = TP - 2, tp_under = 1, n_det0 = nd,
      TP0 = 2 + k / 10 + i / 50, tp_core0 = 2 + k / 10, tp_over0 = 1, tp_under0 = 0.5,
      stringsAsFactors = FALSE)
  }
  x <- do.call(rbind, out)
  rownames(x) <- NULL
  x
}

# Scored cells of `labels` (grid labels, references or chm_vwf) on `plots`
# ("site::plot") at one rung, every plot alike: a configuration's counts grow
# with its score (TP = tp_core = 3 + score of 14 stems, 12 detections, a
# fixed shift null), so its cF1 does too and equal scores tie exactly.
syn_scored <- function(labels, scores, plots = c("SJER::SJER_001", "SJER::SJER_002",
                                                 "WREF::WREF_001"), rung = "native",
                       grid = mcd_grid()) {
  out <- list()
  for (p in plots) for (k in seq_along(labels)) {
    l <- labels[k]
    id <- grid$config_id[match(l, grid$label)]
    out[[length(out) + 1L]] <- data.frame(
      site = sub("::.*", "", p), plot = sub(".*::", "", p), plotType = "tower", rung = rung,
      family = if (l == CD_CHM) "chm_vwf" else if (is.na(id)) "gated" else "depth", config = l,
      config_id = id, n_ref = 14, n_over = 10, n_under = 4, n_det = 12, TP = 3 + scores[k],
      tp_core = 3 + scores[k], tp_over = 1, tp_under = 1, n_det0 = 12, TP0 = 1, tp_core0 = 1,
      tp_over0 = 0.5, tp_under0 = 0.5, stringsAsFactors = FALSE)
  }
  x <- do.call(rbind, out)
  rownames(x) <- NULL
  x
}

# A small grid (the six named depth configurations and grid rows 1 and 2) and
# its cells on three plots: S and row 1 tie at the top, arm and depth tie; the
# declared gated arm scores between S_low and arm, stock below the grid.
syn_grid <- function() {
  cf <- ph_configs(S_LAB, S_LOW)
  g <- mcd_grid()
  gl <- c(ph_label(cf, c("S", "alt", "S_low", "arm", "depth", "space")), g$label[1:2])
  labs <- c(gl, CD_REFERENCES, CD_CHM)
  sc <- c(5, 4, 3, 2, 2, 1, 5, 0, -1, 0.5, 1.5, 2.5, 6)
  list(cf = cf, grid = g[match(gl, g$label), ], labels = gl,
       cells = rbind(syn_scored(labs, sc), syn_scored(labs, rev(sc), rung = "8")),
       valid = c("SJER::SJER_002", "WREF::WREF_001"))
}

# A temporary tree with empty runs of record under work/ (never the real one).
syn_tree <- function() {
  root <- tempfile("ph_tree_")
  for (d in c(CFD_STUDY_DIR, CFD_CONFIRM_DIR, "multichm_gated_confirmation", PH_STUDY_JOB,
              PH_STUDY_ROOT))
    dir.create(file.path(root, "work", d), recursive = TRUE)
  normalizePath(root)
}

# A contrast-like row of S minus declared with its three cF1 numbers.
syn_p2 <- function(unit, scope, d, lo, hi, subset = "validation half", rung = "native")
  data.frame(unit = unit, subset = subset, scope = scope, rung = rung, config_a = S_LAB,
             config_b = CD_DECLARED, d_cF1 = d, lo_cF1 = lo, hi_cF1 = hi,
             stringsAsFactors = FALSE)

## ---- arguments ------------------------------------------------------------------------------
test_that("sourcing runs nothing; KEY=VALUE arguments with at most 8 workers, no unknown key", {
  expect_true(is.function(ph_main))
  w <- tempfile("ph_work_")
  S <- ph_settings(character(), work = w)
  expect_identical(S$STAGE, "all")
  expect_identical(S$DATASETS, CFD_DATASETS$name)
  expect_identical(c(S$CORES, S$N_BOOT), c(4L, MT_N_BOOT))
  # WORK and OUT in canonical absolute form; the defaults hang from WORK
  wc <- file.path(normalizePath(dirname(w)), basename(w))
  expect_identical(S$WORK, wc)
  expect_identical(S$OUT, file.path(wc, "multichm_depth_runs", "posthoc"))
  expect_identical(S$CONFIRM, file.path(wc, "multichm_depth_runs", "confirm"))
  expect_identical(S$STUDY, file.path(wc, "multichm_depth_runs", "neon", "multichm_depth"))
  expect_identical(S$CAMPAIGN, file.path(wc, "multichm_gated_confirmation"))
  S2 <- ph_settings(c("STAGE=analyze", "CORES=8", "DATASETS=ql2,ca2017", "N_BOOT=50",
                      "CONFIRM=/c", "OUT=/o/p"), work = w)
  expect_identical(S2[c("STAGE", "CORES", "DATASETS", "N_BOOT", "CONFIRM", "OUT")],
                   list(STAGE = "analyze", CORES = 8L, DATASETS = c("ql2", "ca2017"),
                        N_BOOT = 50L, CONFIRM = "/c", OUT = "/o/p"))
  # WORK moves every default
  S3 <- ph_settings("WORK=/w2", work = w)
  expect_identical(c(S3$OUT, S3$CONFIRM), c("/w2/multichm_depth_runs/posthoc",
                                            "/w2/multichm_depth_runs/confirm"))
  expect_error(ph_settings("CORES=9", work = w), "at most 8")
  expect_error(ph_settings("CORES=0", work = w), "whole numbers")
  expect_error(ph_settings("STAGE=contrasts", work = w), "STAGE must be all, score or analyze")
  expect_error(ph_settings("DATASETS=ql2,harv", work = w), "DATASETS must be")
  expect_error(ph_settings("UNBLIND=1", work = w), "unknown argument UNBLIND")
  expect_error(ph_settings(c("CORES=2", "CORES=3"), work = w), "given twice")
  # a key that extends OUT is not OUT (and is unknown); OUT= itself is read
  expect_error(ph_settings("OUTPUT=/x", work = w), "unknown argument OUTPUT")
  expect_error(ph_settings("OUTTAG=x", work = w), "unknown argument OUTTAG")
  expect_identical(ph_settings(c("OUT=/x/y", "CONFIRM=/z"), work = w)$OUT, "/x/y")
  # outputs never go into (or around) a read-only input
  for (o in c(file.path(w, "multichm_depth_runs", "confirm"),
              file.path(w, "multichm_depth_runs", "confirm", "x"),
              file.path(w, "multichm_depth_runs", "neon", "multichm_depth"),
              file.path(w, "multichm_gated_runs", "neon"), file.path(w, "neon", "frozen_2021"),
              file.path(w, "multichm_gated_confirmation"), w))
    expect_error(ph_settings(paste0("OUT=", o), work = w), "overlaps a read-only input")
})

test_that("OUT cannot reach a run of record by a relative path, `..` or a symbolic link", {
  skip_on_os("windows")
  root <- syn_tree()
  W <- file.path(root, "work")
  withr::local_dir(root)
  copy <- file.path(root, "copy")
  dir.create(copy)
  file.symlink(W, file.path(root, "alias"))
  file.symlink(file.path(W, CFD_CONFIRM_DIR), file.path(root, "confirm_link"))
  for (wk in list(W, "work")) {
    # a relative OUT that does not exist yet, inside CONFIRM or STUDY
    expect_error(ph_settings("OUT=work/multichm_depth_runs/confirm/posthoc", work = wk),
                 "overlaps a read-only input \\(the confirmation run")
    expect_error(ph_settings("OUT=work/multichm_depth_runs/neon/multichm_depth/posthoc",
                             work = wk), "overlaps a read-only input \\(the study")
    # an OUT with `..`, relative or absolute
    for (o in c("work/multichm_depth_runs/zz/../confirm",
                file.path(W, "multichm_depth_runs", "zz", "..", "confirm"),
                "work/multichm_depth_runs/zz/../neon/multichm_depth",
                file.path(W, "multichm_depth_runs", "zz", "..", "neon", "multichm_depth"),
                "work/multichm_depth_runs/zz/../fresh"))
      expect_error(ph_settings(paste0("OUT=", o), work = wk), "has a `..` component")
    # CONFIRM= or STUDY= elsewhere: the default runs of record stay read-only
    expect_error(ph_settings(c(paste0("CONFIRM=", copy), "OUT=work/multichm_depth_runs/confirm"),
                             work = wk), "the confirmation run of record")
    expect_error(ph_settings(c(paste0("CONFIRM=", copy),
                               paste0("OUT=", file.path(W, CFD_CONFIRM_DIR, "x"))), work = wk),
                 "the confirmation run of record")
    expect_error(ph_settings(c(paste0("STUDY=", copy),
                               "OUT=work/multichm_depth_runs/neon/multichm_depth"), work = wk),
                 "the study's run of record")
    # a symbolic link in an existing part is followed
    expect_error(ph_settings("OUT=alias/multichm_depth_runs/confirm/posthoc", work = wk),
                 "the confirmation run")
    expect_error(ph_settings("OUT=confirm_link/new", work = wk), "the confirmation run")
    expect_error(ph_settings("OUT=alias", work = wk), "overlaps a read-only input")
    # a legitimate new relative OUT: accepted, canonical, nothing written
    S <- ph_settings("OUT=work/multichm_depth_runs/scratch_new/out", work = wk)
    expect_identical(S$OUT, file.path(W, "multichm_depth_runs", "scratch_new", "out"))
    expect_false(dir.exists(file.path(W, "multichm_depth_runs", "scratch_new")))
    expect_identical(ph_settings("OUT=alias/multichm_depth_runs/fresh", work = wk)$OUT,
                     file.path(W, "multichm_depth_runs", "fresh"))
  }
  # WORK= elsewhere: the runs of record under the repository's work directory
  # (`work`) stay read-only too
  expect_error(ph_settings(c(paste0("WORK=", copy), "OUT=work/multichm_depth_runs/confirm/x"),
                           work = W), "the confirmation run of record")
  expect_identical(ph_settings(c(paste0("WORK=", copy), "OUT=out_x"), work = W)$OUT,
                   file.path(root, "out_x"))
})

test_that("WORK=../work from a subdirectory derives every default from its canonical form", {
  skip_on_os("windows")
  root <- syn_tree()
  W <- file.path(root, "work")
  dir.create(file.path(root, "scripts"))
  withr::local_dir(file.path(root, "scripts"))
  for (S in list(ph_settings("WORK=../work", work = "/elsewhere"),
                 ph_settings(character(), work = "../work"))) {
    expect_identical(S$WORK, W)
    expect_identical(S$OUT, file.path(W, "multichm_depth_runs", "posthoc"))
    expect_identical(S$CONFIRM, file.path(W, CFD_CONFIRM_DIR))
    expect_identical(S$STUDY, file.path(W, CFD_STUDY_DIR))
    expect_identical(S$CAMPAIGN, file.path(W, "multichm_gated_confirmation"))
  }
  # the runs of record under the canonical WORK stay read-only
  expect_error(ph_settings(c("WORK=../work", paste0("OUT=", file.path(W, CFD_CONFIRM_DIR, "x"))),
                           work = "/elsewhere"), "the confirmation run", fixed = TRUE)
  # a `..` is refused in an OUT the user gave, never in a default
  expect_error(ph_settings(c("WORK=../work", "OUT=../work/multichm_depth_runs/x"),
                           work = "/elsewhere"), "has a `..` component", fixed = TRUE)
  expect_identical(ph_settings(c("WORK=../work", "OUT=fresh"), work = "/elsewhere")$OUT,
                   file.path(root, "scripts", "fresh"))
})

test_that("the directories the stems and plot centroids resolve to are read-only", {
  skip_on_os("windows")
  root <- syn_tree()
  W <- file.path(root, "work")
  withr::local_dir(root)
  put <- function(f) { dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
                       writeLines("x", f); f }
  link <- function(target, job, site, file) {
    d <- file.path(job, "neon", site)
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    file.symlink(target, file.path(d, file))
  }
  job <- file.path(W, PH_STUDY_JOB)
  # the study's job directory: SJER's two files link into paper/neon/SJER, WREF's
  # stems into paper/neon/WREF and its centroids into other/WREF; SOAP's stems
  # link into mid/SOAP, whose file links (relative target) into final/SOAP, as
  # the study's stems link into a run whose files link into the reference
  # directory; TEAK's stems point nowhere, ABBY's centroids are a plain file
  for (f in PH_REF_FILES) link(put(file.path(root, "paper", "neon", "SJER", f)), job, "SJER", f)
  link(put(file.path(root, "paper", "neon", "WREF", PH_REF_FILES[1])), job, "WREF",
       PH_REF_FILES[1])
  link(put(file.path(root, "other", "WREF", PH_REF_FILES[2])), job, "WREF", PH_REF_FILES[2])
  put(file.path(root, "final", "SOAP", "stems.csv"))
  dir.create(file.path(root, "mid", "SOAP"), recursive = TRUE)
  file.symlink(file.path("..", "..", "final", "SOAP", "stems.csv"),
               file.path(root, "mid", "SOAP", "stems.csv"))
  link(file.path(root, "mid", "SOAP", "stems.csv"), job, "SOAP", PH_REF_FILES[1])
  link(file.path(root, "nowhere", "stems.csv"), job, "TEAK", PH_REF_FILES[1])
  put(file.path(job, "neon", "ABBY", PH_REF_FILES[2]))
  # a dataset's job directory: ql2's SJER stems link into ql2ref/SJER
  qjob <- file.path(W, "multichm_gated_confirmation", "ql2", "job")
  link(put(file.path(root, "ql2ref", "SJER", PH_REF_FILES[1])), qjob, "SJER", PH_REF_FILES[1])
  # every hop's directory, from the job's own to the final target's
  jn <- function(s) file.path(job, "neon", s)
  expect_identical(ph_reference_dirs(list(list(job = job, sites = CV_FIVE))),
                   c(jn("SJER"), file.path(root, "paper", "neon", "SJER"), jn("SOAP"),
                     file.path(root, c("mid/SOAP", "final/SOAP")), jn("WREF"),
                     file.path(root, c("paper/neon/WREF", "other/WREF")), jn("ABBY")))
  expect_identical(ph_reference_dirs(list(list(job = qjob, sites = CV_FIVE))),
                   c(file.path(qjob, "neon", "SJER"), file.path(root, "ql2ref", "SJER")))
  expect_identical(ph_reference_dirs(list(list(job = file.path(root, "none"), sites = "SJER"))),
                   character())
  ro <- "overlaps a read-only input (the stems and plot centroids"
  for (o in c("paper/neon/SJER", "paper/neon/SJER/x", "paper", "paper/neon",
              file.path(root, "paper", "neon", "WREF", "new"), "other/WREF/x", "ql2ref/SJER/x",
              "mid/SOAP/x", "final/SOAP", "final"))
    expect_error(ph_settings(paste0("OUT=", o), work = W), ro, fixed = TRUE)
  # a site the run does not read, a dataset it does not score, a sibling directory
  for (o in c("paper/neon/SOAP", "other/SJER", "ql2ref/WREF", "mid/TEAK")) {
    S <- ph_settings(paste0("OUT=", o), work = W)
    expect_identical(S$OUT, file.path(root, o))
    expect_false(dir.exists(S$OUT))
  }
  expect_error(ph_settings("OUT=ql2ref/SJER/x", work = W), ro, fixed = TRUE)
  expect_identical(ph_settings(c("DATASETS=wa2019", "OUT=ql2ref/SJER/x"), work = W)$OUT,
                   file.path(root, "ql2ref", "SJER", "x"))
  expect_error(ph_settings(c("DATASETS=wa2019", "OUT=paper/neon/SJER/x"), work = W), ro,
               fixed = TRUE)
  # a link to the protected directory is followed
  file.symlink(file.path(root, "paper"), file.path(root, "paper_link"))
  expect_error(ph_settings("OUT=paper_link/neon/SJER/x", work = W), ro, fixed = TRUE)
})

## ---- configurations and pairs ---------------------------------------------------------------
test_that("the configurations are derived from S, MCD_ARM and the gated arm as grid rows", {
  cf <- ph_configs(S_LAB, S_LOW)
  expect_identical(cf$name, PH_NAMES)
  expect_identical(cf$label, c("stock", "z5_s0_c0.6_e1", "z5_s0.75_c0.6_e1_d8",
                               "k4_r0_z5_f0_l0_c0.6", "k4_r2.5_z5_f0_l0_c0.6", S_LAB,
                               "k4_r0_z5_f5_l0_c0.6", "k4_r0_z3_f3_l0_c0.6", S_LOW))
  expect_identical(cf$family, c(rep("gated", 3), rep("depth", 6)))
  g <- mcd_grid()
  expect_identical(cf$config_id, c(NA, NA, NA, g$config_id[match(cf$label[4:9], g$label)]))
  expect_identical(cf$label[cf$name == "arm"], mcd_config_label(MCD_ARM))
  expect_identical(cf$config_id[cf$name == "arm"], 28L)
  expect_identical(cf$label[cf$name == "declared"], CD_DECLARED)
  expect_true(all(cf$label[cf$family == "gated"] %in% CD_REFERENCES))
  expect_true(all(cf$label[cf$family == "depth"] %in% g$label))
  # the parameters are the grid's
  d <- cf[cf$family == "depth", ]
  gg <- g[match(d$label, g$label), ]
  for (k in MCD_FIELDS) expect_identical(d[[k]], gg[[k]])
  expect_true(all(is.na(cf$depth_max[cf$family == "gated"])))
  # without S_low the table has eight rows
  expect_identical(ph_configs(S_LAB)$name, setdiff(PH_NAMES, "S_low"))
  # another selection moves every derived label with it
  o <- ph_configs("k3_r3_z3_f0_l1_c0")
  expect_identical(o$label[match(c("depth", "space", "S", "alt"), o$name)],
                   c("k3_r0_z5_f0_l1_c0", "k3_r3_z5_f0_l1_c0", "k3_r3_z3_f0_l1_c0",
                     "k4_r0_z3_f0_l0_c0.6"))
  # a selection, a sibling or a derived configuration outside the grid stops
  expect_error(ph_configs("k9_r2.5_z5_f5_l0_c0.6"), "the selection S .* is not a label")
  expect_error(ph_configs(S_LAB, "k4_r9_z3_f3_l0_c0.6"), "S_low .* is not a label")
  expect_error(ph_configs(c(S_LAB, S_LOW)), "is not a label")
  expect_error(ph_configs(S_LAB, arm = mcd_config(4, 0, 3, 3, FALSE, 0.5)),
               "configuration alt .* is not a row of mcd_grid")
  expect_error(ph_configs(S_LAB, gated = mcg_config(5, 0.75, 0.6, TRUE, 9)),
               "is labelled z5_s0.75_c0.6_e1_d9")
  # two names with one label stop
  expect_error(ph_configs("k4_r0_z5_f0_l0_c0.6"),
               "depth, space, S, alt share the label k4_r0_z5_f0_l0_c0.6")
})

test_that("the pairs are the walk then the arm's, every a and b a configuration's label", {
  cf <- ph_configs(S_LAB, S_LOW)
  p <- ph_pairs(cf)
  expect_identical(p$pair, c("gate_minus_floor", "depth_minus_floor", "depth_minus_declared",
                             "space_minus_depth", "S_minus_space", "S_minus_declared",
                             "arm_minus_declared", "arm_minus_stock", "arm_minus_S",
                             "arm_minus_depth", "arm_minus_alt", "alt_minus_declared",
                             "S_minus_alt"))
  expect_identical(p$group, c(rep("walk", 6), rep("arm", 7)))
  expect_true(all(c(p$a_name, p$b_name) %in% cf$name))
  expect_identical(p$a, cf$label[match(p$a_name, cf$name)])
  expect_identical(p$b, cf$label[match(p$b_name, cf$name)])
  expect_identical(p$a_name[p$pair == CFD_PRIMARY], "S")
  expect_identical(p$b[p$pair == CFD_PRIMARY], CD_DECLARED)
  expect_identical(unname(unlist(p[p$pair == "arm_minus_S", c("a", "b")])),
                   c("k4_r0_z3_f3_l0_c0.6", S_LAB))
  # each pair is the difference of two configurations, never one with itself
  expect_false(any(p$a == p$b))
  # without S_low nothing breaks: the same pairs and labels
  p0 <- ph_pairs(ph_configs(S_LAB))
  expect_identical(p0, p)
  expect_error(ph_pairs(ph_configs(S_LAB)[-2, ]), "no configuration named floor_exempt")
  # the depth configurations scored per dataset: the six grid rows, S and S_low among them
  g <- ph_depth_grid(cf)
  expect_identical(g$label, cf$label[cf$family == "depth"])
  expect_true(all(c(S_LAB, S_LOW) %in% g$label))
  expect_identical(ph_p1_labels(list(S = S_LAB, S_low = S_LOW)), c(S_LAB, S_LOW, CD_REFERENCES))
  expect_identical(ph_p1_labels(list(S = S_LAB, S_low = NULL)), c(S_LAB, CD_REFERENCES))
  # the lowest-tree configurations: S has the role cd_stem_job needs
  lc <- ph_lowest_configs(cf)
  expect_identical(vapply(lc, `[[`, "", "role"),
                   c("stock", "declared", "depth", "selected", "alt", "arm"))
  expect_identical(vapply(lc, `[[`, "", "label"), ph_label(cf, names(PH_LOW_ROLES)))
  expect_identical(lc[[2]]$cfg, MCG_DECLARED)
  expect_identical(lc[[6]]$cfg, MCD_ARM)
})

## ---- checks ---------------------------------------------------------------------------------
test_that("P1 compares the re-scored rows with the confirmation run's, cell by cell", {
  labs <- c(S_LAB, S_LOW, CD_REFERENCES)
  conf <- syn_cells(c(SJER = 3), rung = "3.2", labels = labs)
  mine <- syn_cells(c(SJER = 3), rung = "3.2",
                    labels = c(labs, "k4_r0_z3_f3_l0_c0.6"))[, c("site", "plot", "rung", "config",
                                                                 CD_OBS_COLS, CD_NULL_COLS)]
  # mine holds the same rows for the labels compared (k is the label's position)
  for (l in labs) mine[mine$config == l, c(CD_OBS_COLS, CD_NULL_COLS)] <-
    conf[conf$config == l, c(CD_OBS_COLS, CD_NULL_COLS)]
  r <- ph_p1_compare(mine, conf, labs, 3)
  expect_true(r$pass)
  expect_identical(c(r$n, r$want, r$n_bad), c(18L, 18L, 0L))
  expect_identical(r$max_null_diff, 0)
  # a count off by one
  m1 <- mine; m1$TP[m1$config == S_LOW][2] <- m1$TP[m1$config == S_LOW][2] + 1
  r1 <- ph_p1_compare(m1, conf, labs, 3)
  expect_false(r1$pass)
  expect_identical(r1$n_bad, 1L)
  expect_identical(r1$bad$config, S_LOW)
  # a null mean off by 2e-9 fails, by 5e-10 passes
  m2 <- mine; m2$TP0[m2$config == "stock"][1] <- m2$TP0[m2$config == "stock"][1] + 2e-9
  r2 <- ph_p1_compare(m2, conf, labs, 3)
  expect_false(r2$pass)
  expect_identical(r2$n_bad, 1L)
  expect_equal(r2$max_null_diff, 2e-9, tolerance = 1e-3)
  m3 <- mine; m3$TP0[m3$config == "stock"][1] <- m3$TP0[m3$config == "stock"][1] + 5e-10
  expect_true(ph_p1_compare(m3, conf, labs, 3)$pass)
  # a missing row, or a cell count that does not match, fails
  expect_false(ph_p1_compare(mine[-1, ], conf, labs, 3)$pass)
  expect_false(ph_p1_compare(mine, conf, labs, 4)$pass)
})

test_that("P2 compares the three cF1 numbers within 1e-12 and misses no row", {
  ref <- rbind(syn_p2("native", "Five sites", 0.03, 0.01, 0.05),
               syn_p2("ql2", "California", -0.01, -0.03, 0.02, rung = "3.2"))
  r <- ph_p2_compare(ref[2:1, ], ref)
  expect_identical(c(r$n, r$n_bad), c(2L, 0L))
  expect_identical(r$max_abs_diff, 0)
  # 1e-9 is far outside 1e-12
  m <- ref; m$hi_cF1[1] <- m$hi_cF1[1] + 1e-9
  r <- ph_p2_compare(m, ref)
  expect_identical(r$n_bad, 1L)
  expect_equal(r$max_abs_diff, 1e-9, tolerance = 1e-3)
  expect_identical(r$bad$unit, "native")
  m <- ref; m$d_cF1[2] <- m$d_cF1[2] + 1e-13
  expect_identical(ph_p2_compare(m, ref)$n_bad, 0L)
  # a missing row on either side
  r <- ph_p2_compare(ref[1, ], ref)
  expect_identical(c(r$n, r$n_bad), c(2L, 1L))
  expect_identical(r$bad$unit, "ql2")
  expect_identical(ph_p2_compare(ref, ref[2, ])$n_bad, 1L)
  # other labels are another row
  m <- ref; m$config_a[1] <- S_LOW
  expect_identical(ph_p2_compare(m, ref)$n_bad, 2L)
  # an undefined interval on one side only fails; on both it is equal
  m <- ref; m$lo_cF1[1] <- NA
  expect_identical(ph_p2_compare(m, ref)$n_bad, 1L)
  expect_identical(ph_p2_compare(m, m)$n_bad, 0L)
  expect_error(ph_p2_compare(rbind(ref, ref), ref), "duplicate rows")
})

test_that("P2's three parts read the study's primary and ladder rows and the confirmation's", {
  con <- rbind(syn_p2("native", "Five sites", 0.03, 0.01, 0.05),
               syn_p2("native", "California", 0.02, 0, 0.04),
               syn_p2("rung8", "Five sites", 0.01, -0.01, 0.03, rung = "8"),
               syn_p2("rung1", "Five sites", 0.04, 0.02, 0.06, rung = "1"),
               syn_p2("ql2", "Five sites", 0.02, 0.01, 0.03, rung = "3.2"),
               syn_p2("ql2", "Five sites", 0.025, 0.01, 0.03, subset = "all plots", rung = "3.2"))
  con$pair <- CFD_PRIMARY
  con <- rbind(con, transform(con[1, ], pair = "arm_minus_declared", d_cF1 = 9))
  validation <- transform(con[1:2, ], primary = c(TRUE, FALSE), analysis = "validation")
  ladder <- data.frame(analysis = "ladder", config_a = S_LAB, config_b = CD_DECLARED,
                       split = "valid", rung = c("8", "1", "8"),
                       scope = c("Five sites", "Five sites", "California"),
                       d_cF1 = c(0.01, 0.04, 0.5), lo_cF1 = c(-0.01, 0.02, 0.5),
                       hi_cF1 = c(0.03, 0.06, 0.5), stringsAsFactors = FALSE)
  conf <- con[con$unit == "ql2", ]
  p <- ph_p2_parts(con, validation, ladder, conf, S_LAB)
  expect_identical(c(p$a$n, p$a$n_bad, p$b$n, p$b$n_bad, p$c$n, p$c$n_bad),
                   c(1L, 0L, 2L, 0L, 2L, 0L))
  expect_identical(p$want, c(a = 1L, b = 2L, c = 4L))
  # a ladder row that differs, a confirmation row that is missing here
  p <- ph_p2_parts(con, validation, transform(ladder, d_cF1 = d_cF1 + 1e-9), conf, S_LAB)
  expect_identical(p$c$n_bad, 2L)
  p <- ph_p2_parts(con[!(con$unit == "ql2" & con$subset == "all plots"), ], validation, ladder,
                   conf, S_LAB)
  expect_identical(p$b$n_bad, 1L)
})

test_that("P3's stem check matches stems, matched and tp0 per configuration", {
  st <- data.frame(site = "SJER", plot = "SJER_1", stem_id = c("a", "b", "a", "b"),
                   config = c("stock", "stock", S_LAB, S_LAB), matched = c(TRUE, FALSE, TRUE, TRUE),
                   tp0 = c(0.5, 0.25, 0.75, 0.1), stringsAsFactors = FALSE)
  r <- ph_stem_compare(st, st[4:1, ], c("stock", S_LAB))
  expect_identical(c(r$n, r$n_bad), c(4L, 0L))
  m <- st; m$tp0[2] <- m$tp0[2] + 2e-9; m$matched[3] <- FALSE
  r <- ph_stem_compare(m, st, c("stock", S_LAB))
  expect_identical(r$n_bad, 2L)
  expect_identical(ph_stem_compare(st[-1, ], st, "stock")$n_bad, 1L)
  expect_identical(ph_stem_compare(st[-1, ], st, S_LAB)$n_bad, 0L)
  expect_error(ph_stem_compare(rbind(st, st), st, "stock"), "listed twice")
})

## ---- units and contrasts --------------------------------------------------------------------
test_that("units: the study's rungs and the confirmation units, the sparse flights pooled", {
  labs <- c("stock", CD_DECLARED)
  study <- do.call(rbind, lapply(PH_STUDY_UNITS$rung, function(r)
    syn_cells(c(SJER = 2, WREF = 1), rung = r, labels = labs)))
  scored <- list(
    ql2 = syn_cells(c(SJER = 2, WREF = 1), rung = "3.2", labels = labs),
    wa2019 = syn_cells(c(WREF = 2, ABBY = 1), labels = labs),
    wa2021_shared = syn_cells(c(WREF = 2, ABBY = 1), labels = labs),
    ca2018 = syn_cells(c(SOAP = 2, TEAK = 1), labels = labs),
    ca2017 = syn_cells(c(SJER = 2), labels = labs),
    ca2021_shared = syn_cells(c(SJER = 2, SOAP = 2, TEAK = 1), labels = labs))
  u <- ph_units(study, scored)
  expect_identical(names(u), c(PH_STUDY_UNITS$unit, CFD_UNITS$unit))
  expect_identical(vapply(u, `[[`, "", "rung"),
                   stats::setNames(c("native", "8", "4", "2", "1", "3.2", rep("native", 4)),
                                   names(u)))
  expect_identical(unique(u$rung4$cells$rung), "4")
  expect_identical(nrow(u$native$cells), 6L)
  expect_identical(u$rung1$unit$test, "T1")
  expect_identical(u$native$unit$test, "study")
  expect_identical(u$wa2019$unit$reading_scope, "Washington")
  # T4: the two sparse flights pooled
  p <- u$ca_sparse_pooled$cells
  expect_identical(nrow(p), nrow(scored$ca2018) + nrow(scored$ca2017))
  expect_setequal(unique(p$site), c("SJER", "SOAP", "TEAK"))
  expect_identical(u$ca_sparse_pooled$unit$test, "T4")
  # a plot shared by the two flights stops; a missing dataset or rung stops
  bad <- scored; bad$ca2017 <- syn_cells(c(SOAP = 1), labels = labs)
  expect_error(ph_units(study, bad), "share plots: SOAP::SOAP_001")
  expect_error(ph_units(study, scored[-5]), "ca_sparse_pooled: dataset ca2017 is not scored")
  expect_error(ph_units(study[study$rung != "2", ], scored), "no cell at rung 2")
  two <- scored; two$ql2$rung[1] <- "native"
  expect_error(ph_units(study, two), "ql2: cells of several rungs")
})

test_that("a unit's contrasts carry the pair's group and names, native adds the stands", {
  cf <- ph_configs(S_LAB, S_LOW)
  pairs <- ph_pairs(cf)
  cells <- syn_cells(c(SJER = 12, WREF = 6))
  ids <- unique(cv_ids(cells))
  valid <- ids[c(TRUE, TRUE, FALSE)]               # closed and open plots in each subset
  unit <- PH_STUDY_UNITS[1, PH_UNIT_COLS]
  v <- ph_unit_contrasts(cells, unit, "native", valid, pairs, stands = TRUE, n_boot = 20)
  expect_identical(names(v)[seq_along(PH_CON_LEAD)], PH_CON_LEAD)
  expect_identical(unique(v$status), PH_STATUS)
  # 2 subsets x (2 sites + 2 stands) x 13 pairs
  expect_identical(nrow(v), 2L * 4L * nrow(pairs))
  expect_identical(unique(v$scope), c("SJER", "WREF", CD_STAND_SCOPES))
  expect_identical(unique(v$subset), CFD_SUBSETS)
  expect_identical(v$pair[1:13], pairs$pair)
  expect_identical(v$group, pairs$group[match(v$pair, pairs$pair)])
  expect_identical(v$name_a, pairs$a_name[match(v$pair, pairs$pair)])
  expect_identical(v$config_b, pairs$b[match(v$pair, pairs$pair)])
  expect_identical(v$widest_scope, v$scope == "Five sites")
  # a stand row is cv_contrast_row on the stand's plots of the subset
  sp <- cd_stand_plots(cells, valid)
  w <- v[v$subset == "validation half" & v$scope == "Closed stands" &
           v$pair == "arm_minus_declared", ]
  r <- cv_contrast_row(cells, sp$`Closed stands`, "native", ph_label(cf, "arm"), CD_DECLARED, 20,
                       MT_SEED, data.frame(x = 1))
  for (k in c("n_plots", "n_ref", "d_cF1", "lo_cF1", "hi_cF1", "d_recall"))
    expect_identical(w[[k]], r[[k]])
  expect_identical(w$verdict_cF1, CD_NOT_READ)            # 6 plots: reported, not read
  # every other row is the confirmation driver's
  c0 <- cfd_unit_contrasts(cells, unit, "native", valid, pairs, 20, MT_SEED)
  v0 <- v[!v$scope %in% CD_STAND_SCOPES, ]
  key <- function(x) paste(x$subset, x$scope, x$pair)
  c0 <- c0[match(key(v0), key(c0)), ]
  for (k in c("n_plots", "d_cF1", "lo_cF1", "hi_cF1", "a_n_det", "verdict_cF1"))
    expect_identical(v0[[k]], c0[[k]])
  # without stands no stand row
  expect_false(any(ph_unit_contrasts(cells, unit, "native", valid, pairs, n_boot = 20)$scope %in%
                     CD_STAND_SCOPES))
})

## ---- lowest trees ---------------------------------------------------------------------------
test_that("stems by field height: bands with edges at 3, 5, 10 and 20 m, raw counts", {
  h <- c(2.9, 3, 4.99, 5, 9.9, 10, 19.99, 20, 35, NA, -1)
  expect_identical(ph_height_band(h),
                   c("under 3 m", "3 to 5 m", "3 to 5 m", "5 to 10 m", "5 to 10 m",
                     "10 to 20 m", "10 to 20 m", "20 m and more", "20 m and more", "unknown",
                     "unknown"))
  expect_identical(ph_height_band(c(0, Inf, "x")), c("under 3 m", "unknown", "unknown"))
  base <- data.frame(site = "SJER", plot = rep(c("SJER_1", "SJER_2"), c(6, 5)),
                     stem_id = sprintf("s%02d", seq_along(h)), height = h,
                     stringsAsFactors = FALSE)
  m <- list(stock = c(1, 1, 0, 1, 1, 1, 1, 1, 1, 0, 0),
            declared = c(0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0),
            S = c(0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0), arm = c(1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 1))
  labs <- c(stock = "stock", declared = CD_DECLARED, S = S_LAB, arm = "k4_r0_z3_f3_l0_c0.6")
  st <- do.call(rbind, lapply(names(labs), function(n)
    cbind(base, config = labs[[n]], matched = as.logical(m[[n]]), stringsAsFactors = FALSE)))
  x <- ph_stem_heights(st, list(`validation half` = "SJER::SJER_2",
                                `all plots` = c("SJER::SJER_1", "SJER::SJER_2")), labs)
  expect_identical(unique(x$status), PH_STATUS)
  a <- x[x$subset == "all plots", ]
  expect_identical(a$band, c(PH_HEIGHT_BANDS, "all heights"))
  expect_identical(a$stems, c(1L, 2L, 2L, 2L, 2L, 2L, 11L))
  expect_identical(a$matched_stock, c(1L, 1L, 2L, 2L, 2L, 0L, 8L))
  expect_identical(a$matched_declared, c(0L, 1L, 1L, 2L, 2L, 1L, 7L))
  expect_identical(a$matched_S, c(0L, 0L, 2L, 2L, 1L, 0L, 5L))
  expect_identical(a$matched_arm, c(1L, 2L, 2L, 1L, 2L, 1L, 9L))
  expect_identical(unique(a$n_plots), 2L)
  v <- x[x$subset == "validation half", ]
  expect_identical(v$stems, c(0L, 0L, 0L, 1L, 2L, 2L, 5L))     # 19.99, 20, 35, NA, -1
  expect_identical(v$matched_stock, c(0L, 0L, 0L, 1L, 2L, 0L, 3L))
  # every configuration must hold the same stems
  expect_error(ph_stem_heights(st[-1, ], list(all = "SJER::SJER_1"), labs),
               "declared holds other stems than stock")
})

test_that("the lowest-tree table reads each stratum once, the unknown band apart from the class", {
  cf <- ph_configs(S_LAB, S_LOW)
  st <- data.frame(type = c("all", "band", "band_pooled", "class"),
                   stratum = c("all", "unknown", "[0,10)", "unknown"),
                   v = c(0.25, 0.125, 0.0625, 0.5), stringsAsFactors = FALSE)
  sc <- do.call(rbind, lapply(seq_along(PH_LOW_TABLE), function(k)
    data.frame(subset = "all plots", kind = "score", type = st$type, stratum = st$stratum,
               config = ph_label(cf, PH_LOW_TABLE[k]), stems = 40L, cRecall = st$v + k / 1000,
               cRecall_lo = st$v - 0.1, cRecall_hi = st$v + 0.1, stringsAsFactors = FALSE)))
  ct <- do.call(rbind, lapply(c("declared", "S"), function(b)
    data.frame(subset = "all plots", kind = "contrast", type = st$type, stratum = st$stratum,
               config_a = ph_label(cf, "arm"), config_b = ph_label(cf, b),
               d_cRecall = st$v / 10, lo_cRecall = -st$v / 10, hi_cRecall = st$v / 5,
               stringsAsFactors = FALSE)))
  low <- as.data.frame(data.table::rbindlist(list(sc, ct), fill = TRUE))
  md <- ph_md_lowest(low, cf, "all plots")
  rows <- md[startsWith(md, "| ") & !startsWith(md, "| Stratum")]
  expect_identical(length(rows), 3L)                     # all, unknown (band), [0,10); no class
  u <- rows[startsWith(rows, "| unknown |")]
  expect_identical(u, paste("| unknown | 40 |",
                            paste(sprintf("%.3f [0.025, 0.225]", 0.125 + (1:6) / 1000),
                                  collapse = " | "),
                            "| +0.013 [-0.013, +0.025] | +0.013 [-0.013, +0.025] |"))
  expect_identical(ph_md_lowest(low, cf, "validation half"),
                   cd_md(c("Stratum (field height, m)", "Stems", PH_LOW_TABLE, "arm − declared",
                           "arm − S"), character()))
})

## ---- the analyze stage's inputs -------------------------------------------------------------
test_that("the analyze stage refuses scored cells whose record, labels or inputs changed", {
  root <- tempfile("ph_scored_")
  dir.create(root)
  W <- file.path(normalizePath(root), "work")
  S <- ph_settings(character(), work = W)
  cf <- ph_configs(S_LAB, S_LOW)
  ds <- cfd_dataset(S, "ql2")
  dc <- ph_confirm_dataset(S, "ql2")
  for (d in c(ds$root, ds$dir, dc$out, ds$out)) dir.create(d, recursive = TRUE)
  writeLines(c("file,sha256", "a.laz,0"), file.path(ds$root, "clip_manifest.csv"))
  camp <- file.path(ds$dir, "cells.csv")
  conf <- file.path(dc$out, "cells.csv")
  writeLines("site,plot", camp)
  writeLines("site,plot", conf)
  camp_rec <- list(K = 200L, tol = 4, population = CFD_POP,
                   clip_manifest_sha256 = frozen_root_id(ds$root), grid_sha256 = cv_grid_digest())
  cd_write_json(camp_rec, file.path(ds$dir, "cells.config.json"))
  cells <- syn_cells(c(SJER = 2, WREF = 1), rung = "3.2")     # every configuration in 3 cells
  write.csv(cells, file.path(ds$out, "cells.csv"), row.names = FALSE)
  rec <- list(status = PH_STATUS, dataset = "ql2", clip_manifest_sha256 = frozen_root_id(ds$root),
              K = 200L, tol = 4, labels = as.list(stats::setNames(cf$label, cf$name)),
              dataset_cells_csv_sha256 = cd_file_sha(camp),
              confirm_cells_csv_sha256 = cd_file_sha(conf),
              constants_sha256 = cd_constants_digest(), depth_grid_sha256 = cd_grid_digest(),
              gated_grid_sha256 = cv_grid_digest(), n_cells = 3L,
              P1 = list(status = "pass", n = 18L))
  put <- function(r) cd_write_json(r, file.path(ds$out, "cells.config.json"))
  refused <- function(mod, pattern) {
    put(utils::modifyList(rec, mod))
    expect_error(ph_read_scored(S, ds, cf), pattern)
    put(rec)
  }
  edited <- function(f, pattern) {
    old <- readLines(f)
    cat("x\n", file = f, append = TRUE)
    expect_error(ph_read_scored(S, ds, cf), pattern)
    writeLines(old, f)
  }
  put(rec)
  x <- ph_read_scored(S, ds, cf)
  expect_identical(nrow(x$cells), 27L)
  expect_identical(x$record$K, 200L)
  # the record missing
  unlink(file.path(ds$out, "cells.config.json"))
  expect_error(ph_read_scored(S, ds, cf), "ql2: no scored cells record at .*run STAGE=score")
  # P1 not passed, other labels, another constants digest
  refused(list(P1 = list(status = "fail")), "CHECK P1 did not pass")
  refused(list(labels = list(arm = ph_label(cf, "alt"))), "scored for other configurations")
  refused(list(labels = list(S_low = NULL)), "scored for other configurations")
  refused(list(constants_sha256 = "x"), "other constants or grids")
  refused(list(depth_grid_sha256 = "x"), "other constants or grids")
  # the confirmation run's cells.csv or the campaign dataset's cells.csv edited
  edited(conf, "the confirmation run's cells.csv or the frozen root changed")
  edited(camp, "the campaign dataset's cells.csv .* changed since scoring")
  # another K or TOL than the campaign dataset's record
  refused(list(K = 100L),
          "scored with K = 100 and TOL = 4, the campaign dataset's record gives K = 200")
  refused(list(tol = 3), "TOL = 3, the campaign dataset's record gives K = 200 and TOL = 4")
  cd_write_json(utils::modifyList(camp_rec, list(K = 150L)), file.path(ds$dir, "cells.config.json"))
  expect_error(ph_read_scored(S, ds, cf), "record gives K = 150")
  cd_write_json(camp_rec, file.path(ds$dir, "cells.config.json"))
  # a configuration's rows missing
  write.csv(cells[cells$config != ph_label(cf, "arm"), ], file.path(ds$out, "cells.csv"),
            row.names = FALSE)
  expect_error(ph_read_scored(S, ds, cf), "does not hold every configuration in every cell")
  write.csv(cells[-1, ], file.path(ds$out, "cells.csv"), row.names = FALSE)
  expect_error(ph_read_scored(S, ds, cf), "does not hold every configuration in every cell")
  write.csv(cells, file.path(ds$out, "cells.csv"), row.names = FALSE)
  # restored, it reads again
  expect_identical(nrow(ph_read_scored(S, ds, cf)$cells), 27L)
})

test_that("the study's selection is re-derived from its calibration plots and must be S", {
  g <- mcd_grid()
  study <- tempfile("ph_study_")
  dir.create(study)
  ids <- c("SJER::SJER_001", "SJER::SJER_002", "SJER::SJER_003", "SJER::SJER_004")
  write.csv(data.frame(site = "SJER", plot = sub(".*::", "", ids),
                       split = c("calib", "calib", "valid", "valid")),
            file.path(study, "split.csv"), row.names = FALSE)
  labs <- c(S_LAB, g$label[1:2], "stock", CD_DECLARED)
  D <- list(S = S_LAB, S_id = 52L)
  cal <- function(sc) syn_scored(labs, sc, ids[1:2])
  val <- function(sc) syn_scored(labs, sc, ids[3:4])
  # S best on the calibration plots (row 1 best on the validation plots only)
  sel <- ph_study_selection(rbind(cal(c(5, 3, 1, 0, 2)), val(c(1, 9, 1, 0, 2))), study, D)
  expect_identical(c(sel$label, as.character(sel$config_id)), c(S_LAB, "52"))
  expect_identical(sel$plots, ids[1:2])
  # another configuration best on the calibration plots stops
  expect_error(ph_study_selection(rbind(cal(c(2, 4, 1, 0, 2)), val(c(5, 3, 1, 0, 2))), study, D),
               paste0("the study's cells select ", g$label[1], ", not the recorded S ", S_LAB),
               fixed = TRUE)
})

## ---- the grid on the study's plots ----------------------------------------------------------
test_that("ranks: 1 = highest, ties within 1e-12 share the smallest rank", {
  expect_identical(ph_rank(c(0.3, 0.3 + 1e-13, 0.2, 0.5, 0.3 + 2e-12)), c(3L, 3L, 5L, 1L, 2L))
  expect_identical(ph_rank(c(1, 1, 1)), c(1L, 1L, 1L))
  expect_error(ph_rank(c(0.1, NA)), "undefined")
})

test_that("the grid: pooled counts, ranks with a tie, references unranked, counts above", {
  m <- syn_grid()
  gv <- ph_grid_validation(m$cells, m$valid, m$grid)
  expect_identical(names(gv), PH_GRID_COLS)
  expect_identical(unique(gv$subset), CFD_SUBSETS)
  expect_identical(unique(gv$status), PH_STATUS)
  a <- gv[gv$subset == "all plots", ]
  expect_identical(a$family, c(rep("depth", 8), rep("gated", 4), "chm_vwf"))
  d <- a[a$family == "depth", ]
  # ordered by rank, then config_id; S and grid row 1 share rank 1, arm and depth rank 5
  expect_identical(d$rank, c(1L, 1L, 3L, 4L, 5L, 5L, 7L, 8L))
  expect_identical(d$rank[match(m$labels, d$label)], c(1L, 3L, 4L, 5L, 5L, 7L, 1L, 8L))
  expect_identical(d$config_id[1:2], sort(c(1L, 52L)))
  # the six parameters are the grid's
  for (k in MCD_FIELDS) expect_identical(d[[k]], m$grid[[k]][match(d$label, m$grid$label)])
  # references (and chm_vwf) have no rank, config_id or parameters
  r <- a[a$family != "depth", ]
  expect_identical(r$label, c(CD_REFERENCES, CD_CHM))
  expect_true(all(is.na(r$rank)) && all(is.na(r$config_id)) && all(is.na(r$depth_max)))
  # pooled by summed counts over the subset's native plots (rung 8 is not read)
  expect_identical(a$n_plots, rep(3L, 13))
  expect_identical(a$TP[a$label == S_LAB], 24)
  expect_identical(gv$n_plots[gv$subset == "validation half"], rep(2L, 13))
  nat <- m$cells[m$cells$rung == "native" & m$cells$config == S_LAB, ]
  expect_identical(a$cF1[a$label == S_LAB], mcg_pool(nat)$cF1)
  # the counts above a reference, and the named configurations' ranks
  gs <- ph_grid_summary(gv, m$cf)
  expect_identical(gs$counts$subset, CFD_SUBSETS)
  expect_identical(gs$counts$n_grid, c(8L, 8L))
  expect_identical(gs$counts$above_declared, c(4L, 4L))           # S, row 1, alt, S_low
  expect_identical(gs$counts$above_stock, c(8L, 8L))
  expect_identical(gs$counts$n_plots, c(2L, 3L))
  expect_identical(gs$counts$n_stems, c(28, 42))
  v <- gs$ranks[gs$ranks$subset == "all plots", ]
  expect_identical(v$name, PH_GRID_NAMES)
  expect_identical(v$rank, c(1L, 4L, 3L, 5L, 5L, 7L))
  expect_identical(v$sharing_rank, c(2L, 1L, 1L, 2L, 2L, 1L))
  # a grid configuration within 1e-12 of the reference is not counted above it
  tie <- gv
  vh <- tie$subset == "validation half"
  tie$cF1[vh & tie$label == CD_DECLARED] <- tie$cF1[vh & tie$label == ph_label(m$cf, "S_low")] -
    1e-13
  expect_identical(ph_grid_summary(tie, m$cf)$counts$above_declared, c(3L, 4L))
  # every grid configuration, stock and the declared arm must cover every plot
  x <- m$cells
  expect_error(ph_grid_validation(x[-1, ], m$valid, m$grid), "not every one of the 8")
  expect_error(ph_grid_validation(x[x$config != "stock", ], m$valid, m$grid),
               "stock and the declared gated arm must cover every plot")
  y <- x; y$config[y$config == S_LAB] <- ph_label(m$cf, "alt")
  expect_error(ph_grid_validation(y, m$valid, m$grid), "is not labelled as mcd_grid\\(\\)")
  expect_error(ph_grid_validation(rbind(x, x[1, ]), m$valid, m$grid), "scored twice")
  expect_error(ph_grid_summary(gv, ph_configs("k3_r3_z3_f0_l1_c0")), "is not a grid row")
})

## ---- tables.md ------------------------------------------------------------------------------
test_that("tables.md: prose within 80 characters, every table labelled, no absolute path", {
  m <- syn_grid()
  cf <- m$cf
  pairs <- ph_pairs(cf)
  units <- c(lapply(seq_len(nrow(PH_STUDY_UNITS)), function(i)
    list(unit = PH_STUDY_UNITS[i, PH_UNIT_COLS], rung = PH_STUDY_UNITS$rung[i])),
    lapply(seq_len(nrow(CFD_UNITS)), function(i)
      list(unit = CFD_UNITS[i, PH_UNIT_COLS], rung = "native")))
  names(units) <- c(PH_STUDY_UNITS$unit, CFD_UNITS$unit)
  con <- expand.grid(unit = names(units), subset = CFD_SUBSETS, scope = PH_SCOPE_ORDER,
                     pair = pairs$pair, stringsAsFactors = FALSE)
  con$n_plots <- 20L
  con$n_ref <- 400
  for (k in c("cF1", "recall", "precision", "det_per_ref")) {
    con[[paste0("d_", k)]] <- 0.012; con[[paste0("lo_", k)]] <- -0.006
    con[[paste0("hi_", k)]] <- 0.029
  }
  stems <- data.frame(site = "SJER", plot = rep(c("SJER_001", "SJER_002"), c(3, 2)),
                      stem_id = sprintf("s%d", 1:5), height = c(2, 4, 8, 15, 25),
                      stringsAsFactors = FALSE)
  hl <- stats::setNames(ph_label(cf, PH_HEIGHT_NAMES), PH_HEIGHT_NAMES)
  st <- do.call(rbind, lapply(hl, function(l)
    cbind(stems, config = l, matched = c(TRUE, FALSE, TRUE, TRUE, FALSE),
          stringsAsFactors = FALSE)))
  subs <- list(`validation half` = "SJER::SJER_002", `all plots` = c("SJER::SJER_001",
                                                                     "SJER::SJER_002"))
  low <- do.call(rbind, lapply(CFD_SUBSETS, function(su) rbind(
    data.frame(subset = su, kind = "score", type = "all", stratum = "all",
               config = ph_label(cf, PH_LOW_TABLE), stems = 5L, cRecall = 0.2, cRecall_lo = 0.1,
               cRecall_hi = 0.3, config_a = NA, config_b = NA, d_cRecall = NA, lo_cRecall = NA,
               hi_cRecall = NA, stringsAsFactors = FALSE),
    data.frame(subset = su, kind = "contrast", type = "all", stratum = "all", config = NA,
               stems = 5L, cRecall = NA, cRecall_lo = NA, cRecall_hi = NA,
               config_a = ph_label(cf, "arm"), config_b = ph_label(cf, c("declared", "S")),
               d_cRecall = 0.01, lo_cRecall = -0.01, hi_cRecall = 0.03,
               stringsAsFactors = FALSE))))
  L <- list(lowest = low, heights = ph_stem_heights(st, subs, hl), subsets = subs)
  checks <- list(P1 = list(ql2 = list(rows = 636L, cells = 106L, max_null_diff = 0)),
                 P2 = list(study_primary_rows = 1L, confirmation_rows = 44L,
                           study_ladder_rows = 4L, max_abs_diff = 2e-16),
                 P3 = list(cells = 106L, configurations = 6L, max_tp0_diff = 2e-14,
                           zrep_cells = 106L, stem_rows_compared = 7575L, stem_max_tp0_diff = 0))
  D <- list(S = S_LAB, S_id = 52L, S_low = S_LOW, S_low_id = 58L,
            file = file.path(tempdir(), "study", "declared_depth_config.json"))
  meta <- list(N_BOOT = MT_N_BOOT, seed = MT_SEED, K = 200L, tol = 4)
  gs <- ph_grid_summary(ph_grid_validation(m$cells, m$valid, m$grid), cf)
  md <- ph_tables_md(cf, pairs, con, L, units, subs[[1]], checks, D, meta, gs)
  tab <- startsWith(md, "|")
  # prose (every line outside a table) within 80 characters
  expect_true(all(nchar(md[!tab]) <= 80))
  # every table is preceded by the descriptive label
  heads <- which(tab & !c(FALSE, tab[-length(tab)]))
  expect_identical(length(heads), 14L)
  label_of <- function(i) {
    j <- i - 1L
    while (j > 1L && !nzchar(md[j])) j <- j - 1L
    k <- j
    while (k > 1L && nzchar(md[k - 1L])) k <- k - 1L
    paste(md[k:j], collapse = " ")
  }
  for (i in heads) expect_match(label_of(i), "post hoc, descriptive", fixed = TRUE, info = md[i])
  # no absolute path
  expect_false(any(grepl(tempdir(), md, fixed = TRUE)))
  expect_false(any(grepl(.ROOT, md, fixed = TRUE)))
  expect_false(any(grepl("(^|[\\s(\\[`])/[\\w.-]+/", md, perl = TRUE)))
  # the grid's section: counts above the references, then the named ranks
  expect_true("## 6. The grid on the validation plots and on all plots" %in% md)
  expect_true("## 7. Checks" %in% md)
  expect_true("| all plots | 3 | 42 | 8 | 0.375 | 4 | 0.083 | 8 |" %in% md)
  expect_true(sprintf("| validation half | S | `%s` | 52 | 0.583 | 1 | 2 |", S_LAB) %in% md)
  expect_true(sprintf("| all plots | arm | `%s` | 28 | 0.333 | 5 | 2 |", ph_label(cf, "arm")) %in%
                md)
})

## ---- formatting -----------------------------------------------------------------------------
test_that("numbers have three decimals, differences a sign, intervals in brackets", {
  expect_identical(ph_sgn(c(0.0123, -0.0061, 0, NA, 0.0296)),
                   c("+0.012", "-0.006", "+0.000", "NA", "+0.030"))
  expect_identical(ph_div(0.012, -0.006, 0.029), "+0.012 [-0.006, +0.029]")
  expect_identical(ph_div(c(0.012, NA), c(-0.006, NA), c(0.029, NA)),
                   c("+0.012 [-0.006, +0.029]", "NA [NA, NA]"))
  expect_identical(ph_riv(0.2362, 0.1916, 0.2932), "0.236 [0.192, 0.293]")
  expect_identical(ph_riv(-0.188, -0.3, 0.05), "-0.188 [-0.300, 0.050]")
  p <- ph_pairs(ph_configs(S_LAB, S_LOW))
  expect_identical(ph_pair_text(p, c("arm_minus_S", "gate_minus_floor")),
                   c("arm − S", "declared − floor_exempt"))
  expect_identical(ph_rel(file.path(.ROOT, "work", "x")), file.path("work", "x"))
  expect_identical(ph_rel("/elsewhere/x"), "/elsewhere/x")
  # the provenance sentence, word for word
  expect_identical(PH_PROVENANCE, paste(
    "Post hoc and descriptive. The arm's configuration was chosen after the held-out results of",
    "the study and of its confirmation on other densities and flights had been read, and with a",
    "referee-only check on plots outside the benchmark that have no field reference. The rows",
    "of the selection against the declared gated arm repeat the protocol's own rows where the",
    "protocol has them (the validation plots of the study's clips at the scopes it reads, and",
    "the confirmation datasets), as a check. Every other contrast below was not declared in the",
    "protocol (docs/multichm-depth-protocol.md), which reads the calibration's selection and",
    "its low-floor sibling only; that includes the all-plots rows of the study's clips, which",
    "hold the calibration plots the selection was made on. The validation-half rows are",
    "therefore not held-out evidence for the arm's configuration."))
  # the old sentences are gone; the pair it now names is the one P2 checks
  expect_false(grepl("None of the contrasts", PH_PROVENANCE, fixed = TRUE))
  expect_false(grepl("Apart from", PH_PROVENANCE, fixed = TRUE))
  expect_false(grepl("repeats the protocol's own rows", PH_PROVENANCE, fixed = TRUE))
  expect_identical(CFD_PRIMARY, "S_minus_declared")
  expect_true(CFD_PRIMARY %in% PH_PAIRS$pair)
  # prose is wrapped at 80 characters
  expect_true(all(nchar(cd_para(PH_PROVENANCE)) <= 80))
})
