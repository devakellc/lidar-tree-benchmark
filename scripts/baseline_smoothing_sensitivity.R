#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("sweep_lib.R")); source(.find("model_bench_lib.R")); source(.find("master_tables_lib.R"))

# Baseline smoothing sensitivity. The paper's CHM-VWF smooths its 0.5 m canopy
# model with a circular 3 m moving mean below 8 first returns/m² (a rule fixed
# before the runs and never tested without the smoothing). This pools a second
# CHM-VWF run on the same sealed clips with the smoothing disabled
# (detect_lidrplugins_sweep.R ARMS=chm_vwf SMOOTH_BELOW=0, in its own job
# directory) against the paper's CHM-VWF and the leading arms, per rung, with
# the master-table resamples: the unsmoothed minus smoothed change in recall,
# precision and F1, each arm's lead over either baseline, and the dominant-class
# recall of both baselines. A post hoc sensitivity, not a change of baseline.
# The QL2 rung (frozen in its own root) is pooled the same way from its own job
# directories when both exist: the paper's (QL2=, default
# <job dir>/../paper_runs_ql2) and the unsmoothed run on that root
# (NOSMOOTH_QL2=, default <NOSMOOTH>_ql2); QL2=none leaves it out. Their native
# rows must repeat the main job directories' counts, up to lasR's run-to-run
# variation (bs_native_mismatch).
# Chance agreement, where the null re-scores of both baselines exist
# (paper_sensitivity.R MODE=null K=200 [TOL=2] ARMS=chm_vwf in each unsmoothed
# job directory, beside the paper's own nulls; the shifts are per plot, so the
# nulls pair): for the eight detectors run at every rung and the unsmoothed
# baseline, the null F1, the null share (null F1 / F1) and the corrected F1,
# (F1 - null F1) / (1 - null F1), and each detector's observed and corrected
# lead over either baseline, with paired intervals over the master-table
# resamples, for five sites and each region, at each radius of NULL_TOLS. The
# script stops unless every corrected F1 and every lead over the smoothed
# baseline equal the null re-scores' own (null_delta.csv, null_leads.csv) and
# the observed scores equal the pooled result rows, to 1e-9.
#   CLAUDE_JOB_DIR=<paper_runs> Rscript scripts/baseline_smoothing_sensitivity.R
#     NOSMOOTH=<job dir of the unsmoothed run> [QL2=<job dir>|none]
#     [NOSMOOTH_QL2=<job dir>] [NULL_TOLS=4,2] [OUT=<dir>]
# Writes <OUT>/baseline_smoothing_{pooled,contrasts,dominant}.csv (the QL2
# rung's rows after the others) and, with the nulls,
# <OUT>/baseline_smoothing_corrected.csv and _corrected_leads.csv; OUT defaults
# to $CLAUDE_JOB_DIR/sensitivity.
SITES <- c("SJER", "SOAP", "TEAK", "WREF", "ABBY")
ARMS <- c("multichm", "forestformer3d", "treeisonet", "segmentanytree")
# The eight detectors run at every rung, the unsmoothed baseline's label, the
# levels in density order and the pooled scopes of the corrected tables.
LADDER <- MT_ARMS$arm[MT_ARMS$rungs == paste(MT_RUNGS, collapse = ",")]
UNSMOOTHED <- "chm_vwf_unsmoothed"
BS_ORDER <- c("native", "8", "4", "3.2", "2", "1")
BS_SCOPES <- c(list(`five sites` = SITES), MT_REGIONS)
BS_TOL <- 1e-9

## ---- observed rows ---------------------------------------------------------------
# One arm's per-plot result rows from a job directory, relabelled; `rungs`
# keeps only those rungs (NULL keeps every rung the file holds).
bs_read_arm <- function(job, file, det, label, rungs = NULL, sites = SITES)
  do.call(rbind, lapply(sites, function(s) {
    f <- file.path(job, "neon", s, file); if (!file.exists(f)) return(NULL)
    x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
    x <- x[x$detector == det, c("site", "plot", "rung", "n_ref", "n_det", "TP", "precision",
                                "rec_dominant", "n_dominant")]
    if (!is.null(rungs)) x <- x[x$rung %in% rungs, , drop = FALSE]
    x$detector <- label; x
  }))

# The six arms of one job pair: the unsmoothed run and the paper's.
bs_read_rows <- function(job, nosmooth, rungs = NULL)
  rbind(bs_read_arm(nosmooth, "lidrplugins_results.csv", "chm_vwf", UNSMOOTHED, rungs),
        bs_read_arm(job, "lidrplugins_results.csv", "chm_vwf", "chm_vwf", rungs),
        bs_read_arm(job, "lidrplugins_results.csv", "multichm", "multichm", rungs),
        bs_read_arm(job, "forestformer3d_results.csv", "forestformer3d", "forestformer3d", rungs),
        bs_read_arm(job, "treeisonet_results.csv", "treeisonet", "treeisonet", rungs),
        bs_read_arm(job, "segmentanytree_results.csv", "segmentanytree", "segmentanytree", rungs))

# A rung frozen in its own root runs from its own job directories, which also
# score the root's native cells, the same clips as the main runs. Returns the
# cells of `other` whose counts differ from the same detector's cell in `main`
# beyond lasR's run-to-run variation: the reference and the true positives must
# be equal, the core detections and their matched share within `slack` (three
# repeats of every cell moved one core detection in one cell of 1,184 and never
# a true positive); cells absent from `main` count as differing. Attribute
# "within_slack" counts the cells that differ only within the slack.
bs_native_mismatch <- function(main, other, rung = "native", slack = 1) {
  cols <- c("site", "plot", "detector", "n_ref", "n_det", "TP", "precision")
  a <- main[main$rung == rung, cols, drop = FALSE]
  b <- other[other$rung == rung, cols, drop = FALSE]
  if (!nrow(b)) return(structure(b, within_slack = 0L))
  m <- merge(b, a, by = c("site", "plot", "detector"), all.x = TRUE, suffixes = c("", ".main"))
  tp_core <- function(p, n) ifelse(n > 0, round(p * n), 0)
  d_det <- abs(m$n_det - m$n_det.main)
  d_tpc <- abs(tp_core(m$precision, m$n_det) - tp_core(m$precision.main, m$n_det.main))
  ok <- !is.na(m$n_ref.main) & m$n_ref == m$n_ref.main & m$TP == m$TP.main &
    d_det <= slack & d_tpc <= slack
  structure(m[!ok, , drop = FALSE], within_slack = sum(ok & (d_det > 0 | d_tpc > 0)))
}

# Pooled scores, contrasts and dominant-class recall of one rung's rows, on the
# plots every arm scored, with the master-table resamples.
bs_observed_rung <- function(x) {
  r <- x$rung[1]
  key <- paste(x$site, x$plot, sep = "::")
  common <- Reduce(intersect, lapply(split(key, x$detector), unique))
  x <- x[key %in% common, ]
  W <- mt_plot_weights(x$site, x$plot, MT_N_BOOT, MT_SEED)
  s <- mt_boot_scores(x, W, c("detector", "rung"))
  est <- cbind(scope = "five sites", mt_intervals(s))
  g <- function(a) paste(a, r, sep = "|")
  con <- rbind(
    do.call(rbind, lapply(c("recall", "precision", "F1"), function(m)
      cbind(contrast = "unsmoothed minus smoothed", mt_contrast(s, g("chm_vwf"), g(UNSMOOTHED), m)))),
    do.call(rbind, lapply(ARMS, function(a)
      rbind(cbind(contrast = "lead over smoothed", mt_contrast(s, g("chm_vwf"), g(a), "F1")),
            cbind(contrast = "lead over unsmoothed", mt_contrast(s, g(UNSMOOTHED), g(a), "F1"))))))
  con <- cbind(scope = "five sites", rung = r, n_plots = nrow(W), con)
  b <- x[x$detector %in% c("chm_vwf", UNSMOOTHED) & !is.na(x$rec_dominant), ]
  dom <- aggregate(cbind(tp = round(rec_dominant * n_dominant), n = n_dominant) ~ detector, b, sum)
  dom <- cbind(scope = "five sites", rung = r, dom); dom$recall <- dom$tp / dom$n
  list(est = est, con = con, dom = dom)
}

## ---- chance agreement --------------------------------------------------------------
# paper_sensitivity.R MODE=null writes null_cells.csv at the 4 m radius and
# null_tol<TOL>_cells.csv at another (default shift and seed).
bs_null_file <- function(job, tol, what = "cells")
  file.path(job, "sensitivity", sprintf("null%s_%s.csv", if (tol == 4) "" else sprintf("_tol%g", tol), what))

# The observed ("baseline") and null cells of `detectors` at `rungs` from a job
# directory's null re-score, or NULL when it has none; `label` renames a single
# detector (the unsmoothed run's chm_vwf).
bs_read_null <- function(job, tol, detectors, rungs, label = NULL) {
  f <- bs_null_file(job, tol)
  if (!file.exists(f)) return(NULL)
  x <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  x <- x[x$detector %in% detectors & x$rung %in% rungs,
         c("variant", "site", "plot", "rung", "detector", "n_ref", "n_det", "TP", "tp_core"), drop = FALSE]
  if (!is.null(label)) {
    if (length(detectors) != 1) stop("A label renames one detector")
    x$detector <- rep(label, nrow(x))
  }
  if (!nrow(x)) NULL else x
}

# Corrected F1 of one rung's null cells (variants "baseline" and "null", one
# rung) and the leads over each reference present, per scope, on the plots
# every detector and variant scored. Corrected F1 is (F1 - null F1) / (1 - null
# F1), per resample as paper_sensitivity.R computes it; the null share is null
# F1 / F1; a corrected lead is the paired difference of corrected F1.
bs_corrected_rung <- function(x, refs = c(smoothed = "chm_vwf", unsmoothed = UNSMOOTHED),
                              scopes = BS_SCOPES, n_boot = MT_N_BOOT, seed = MT_SEED) {
  r <- unique(x$rung)
  if (length(r) != 1) stop("One rung at a time")
  if (!setequal(unique(x$variant), c("baseline", "null"))) stop("Expected baseline and null variants")
  key <- paste(x$site, x$plot, sep = "::")
  common <- Reduce(intersect, lapply(split(key, paste(x$variant, x$detector)), unique))
  x <- x[key %in% common, , drop = FALSE]
  W <- mt_plot_weights(x$site, x$plot, n_boot, seed)
  site_of <- sub("::.*", "", rownames(W))
  g <- function(v, a) paste(v, a, r, sep = "|")
  corr <- function(o, n) (o - n) / (1 - n)
  arms <- unique(x$detector)
  sc_rows <- list(); ld_rows <- list()
  for (sc in names(scopes)) {
    keep <- site_of %in% scopes[[sc]]
    if (!any(keep)) next
    s <- mt_boot_scores(x[x$site %in% scopes[[sc]], , drop = FALSE], W[keep, , drop = FALSE],
                        c("variant", "detector", "rung"))
    E <- s$estimate$F1; names(E) <- s$groups; D <- s$draws$F1
    val <- function(a) {
      o <- list(e = unname(E[g("baseline", a)]), d = D[, g("baseline", a)])
      n <- list(e = unname(E[g("null", a)]), d = D[, g("null", a)])
      list(F1 = o, null_F1 = n, null_share = list(e = n$e / o$e, d = n$d / o$d),
           F1_corrected = list(e = corr(o$e, n$e), d = corr(o$d, n$d)))
    }
    v <- lapply(setNames(nm = arms), val)
    for (a in arms) for (m in names(v[[a]]))
      sc_rows[[length(sc_rows) + 1]] <- cbind(
        data.frame(scope = sc, rung = r, n_plots = sum(keep), detector = a, metric = m,
                   estimate = v[[a]][[m]]$e, stringsAsFactors = FALSE), mt_interval(v[[a]][[m]]$d))
    for (rn in names(refs)) {
      ref <- refs[[rn]]
      if (!ref %in% arms) next
      kinds <- c(observed = "F1", corrected = "F1_corrected")
      for (a in setdiff(arms, ref)) for (kn in names(kinds)) {
        k <- kinds[[kn]]
        e <- v[[a]][[k]]$e - v[[ref]][[k]]$e
        ld_rows[[length(ld_rows) + 1]] <- cbind(
          data.frame(scope = sc, rung = r, n_plots = sum(keep), contrast = paste("lead over", rn),
                     kind = kn, from = paste(ref, r, sep = "|"), to = paste(a, r, sep = "|"),
                     metric = "F1", estimate = e, stringsAsFactors = FALSE),
          mt_interval(v[[a]][[k]]$d - v[[ref]][[k]]$d))
      }
    }
  }
  list(scores = do.call(rbind, sc_rows), leads = do.call(rbind, ld_rows))
}

# Joins `ours` to `ref` on `by` and returns the largest absolute difference of
# estimate, lower and upper, Inf when a row of `ours` has no match.
bs_max_diff <- function(ours, ref, by) {
  if (!nrow(ours)) return(0)
  m <- merge(ours[, c(by, "estimate", "lower", "upper")], ref[, c(by, "estimate", "lower", "upper")],
             by = by, all.x = TRUE, suffixes = c("", ".ref"))
  if (anyNA(m$estimate.ref)) return(Inf)
  max(abs(c(m$estimate - m$estimate.ref, m$lower - m$lower.ref, m$upper - m$upper.ref)))
}

# The null re-score's own corrected F1 (null_delta.csv, F1_scaled) and leads
# over its CHM-VWF (null_leads.csv, observed and above_null_scaled), relabelled
# as the corrected tables name them; `label` renames chm_vwf.
bs_null_reference <- function(job, tol, rungs, label = "chm_vwf") {
  fd <- bs_null_file(job, tol, "delta"); fl <- bs_null_file(job, tol, "leads")
  if (!file.exists(fd)) stop("No null re-score summary at ", fd)
  dl <- read.csv(fd, stringsAsFactors = FALSE, colClasses = c(rung = "character"))
  dl <- dl[dl$stratum == "all" & dl$metric == "F1_scaled" & dl$rung %in% rungs, , drop = FALSE]
  dl$detector[dl$detector == "chm_vwf"] <- label
  # A re-score of CHM-VWF alone writes an empty leads file.
  ld <- if (file.exists(fl)) tryCatch(suppressWarnings(
    read.csv(fl, stringsAsFactors = FALSE, colClasses = c(rung = "character"))), error = function(e) NULL)
  if (!is.null(ld) && !all(c("kind", "detector", "rung") %in% names(ld))) ld <- NULL
  if (!is.null(ld)) {
    ld <- ld[ld$stratum == "all" & ld$metric == "F1" & ld$rung %in% rungs &
               ld$kind %in% c("observed", "above_null_scaled"), , drop = FALSE]
    ld$kind[ld$kind == "above_null_scaled"] <- "corrected"
    ld$to <- paste(ld$detector, ld$rung, sep = "|")
  }
  list(delta = dl, leads = ld)
}

## ---- run -----------------------------------------------------------------------------
if (sys.nframe() == 0L) {
  args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
  A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
  d <- .job_dir()
  NS <- A[["NOSMOOTH"]]; if (is.null(NS)) stop("NOSMOOTH=<job dir> is required")
  OUT <- if (is.null(A[["OUT"]])) file.path(d, "sensitivity") else A[["OUT"]]
  dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
  QL2 <- if (is.null(A[["QL2"]])) file.path(dirname(d), "paper_runs_ql2") else A[["QL2"]]
  NSQ <- if (is.null(A[["NOSMOOTH_QL2"]])) paste0(sub("/+$", "", NS), "_ql2") else A[["NOSMOOTH_QL2"]]
  NULL_TOLS <- as.numeric(strsplit(if (is.null(A[["NULL_TOLS"]])) "4,2" else A[["NULL_TOLS"]], ",")[[1]])

  rows <- bs_read_rows(d, NS)
  if (!any(rows$detector == UNSMOOTHED)) stop("No unsmoothed CHM-VWF results under ", NS)
  rows$tp_core <- round(rows$precision * rows$n_det)
  out <- lapply(split(rows, rows$rung), bs_observed_rung)

  # The QL2 rung from its own job directories: the rungs they hold beyond the
  # main ladder, after their native rows are checked against the main runs.
  QRUNGS <- character()
  want_ql2 <- !identical(QL2, "none")
  if (want_ql2 && dir.exists(QL2) && dir.exists(NSQ)) {
    q <- bs_read_rows(QL2, NSQ)
    if (is.null(q) || !any(q$detector == UNSMOOTHED) || !any(q$detector == "chm_vwf")) {
      message("No CHM-VWF results under ", QL2, " and ", NSQ, "; the QL2 rung is left out")
    } else {
      bad <- bs_native_mismatch(rows, q)
      if (nrow(bad)) {
        print(utils::head(bad, 20), row.names = FALSE)
        stop(nrow(bad), " native cells of ", QL2, " or ", NSQ, " differ from the main runs")
      }
      QRUNGS <- setdiff(unique(q$rung), MT_RUNGS)
      q <- q[q$rung %in% QRUNGS, , drop = FALSE]
      q$tp_core <- round(q$precision * q$n_det)
      out <- c(out, lapply(split(q, q$rung), bs_observed_rung))
      cat(sprintf("QL2 rung %s from %s and %s (native cells repeat the main runs; %d within one detection)\n",
                  paste(QRUNGS, collapse = ","), QL2, NSQ, attr(bad, "within_slack")))
    }
  } else if (want_ql2) {
    if (!is.null(A[["QL2"]]) || !is.null(A[["NOSMOOTH_QL2"]]))
      stop("No QL2 job directories at ", QL2, " and ", NSQ)
    message("No QL2 job directories at ", QL2, " and ", NSQ, "; the QL2 rung is left out")
  }
  est <- do.call(rbind, lapply(out, `[[`, "est")); con <- do.call(rbind, lapply(out, `[[`, "con"))
  dom <- do.call(rbind, lapply(out, `[[`, "dom"))
  write.csv(est, file.path(OUT, "baseline_smoothing_pooled.csv"), row.names = FALSE)
  write.csv(con, file.path(OUT, "baseline_smoothing_contrasts.csv"), row.names = FALSE)
  write.csv(dom, file.path(OUT, "baseline_smoothing_dominant.csv"), row.names = FALSE)
  ord <- BS_ORDER
  cat("\n== pooled scores by rung (five sites)\n")
  for (r in intersect(ord, est$rung)) for (a in c("chm_vwf", UNSMOOTHED, ARMS)) {
    e <- est[est$detector == a & est$rung == r, ]
    if (nrow(e)) cat(sprintf("%-7s %-19s F1 %.3f [%.3f, %.3f]  recall %.3f  precision %.3f  n_det %d\n", r, a,
                             e$estimate[e$metric == "F1"], e$lower[e$metric == "F1"], e$upper[e$metric == "F1"],
                             e$estimate[e$metric == "recall"], e$estimate[e$metric == "precision"], e$n_det[1]))
  }
  cat("\n== contrasts\n")
  for (r in intersect(ord, con$rung)) { z <- con[con$rung == r, ]
    for (i in seq_len(nrow(z))) cat(sprintf("%-7s %-26s %-28s %-9s %+.3f [%+.3f, %+.3f]\n", r, z$contrast[i],
                                            z$to[i], z$metric[i], z$estimate[i], z$lower[i], z$upper[i])) }
  cat("\n== dominant-class recall of the two baselines\n"); print(dom, row.names = FALSE, digits = 3)
  cat(sprintf("wrote %s\n", file.path(OUT, "baseline_smoothing_{pooled,contrasts,dominant}.csv")))

  ## Chance agreement: corrected F1 and leads over either baseline, per radius.
  corr_sc <- list(); corr_ld <- list()
  for (tol in NULL_TOLS) {
    parts <- list(list(job = d, ns = NS, rungs = MT_RUNGS))
    if (length(QRUNGS)) parts[[2]] <- list(job = QL2, ns = NSQ, rungs = QRUNGS)
    cells <- list(); refs <- list()
    for (p in parts) {
      sm <- bs_read_null(p$job, tol, LADDER, p$rungs)
      un <- bs_read_null(p$ns, tol, "chm_vwf", p$rungs, UNSMOOTHED)
      if (is.null(sm) || is.null(un)) {
        message(sprintf("No null re-scores at %g m for %s and %s; rungs %s left out", tol, p$job, p$ns,
                        paste(p$rungs, collapse = ",")))
        next
      }
      cells[[length(cells) + 1]] <- rbind(sm, un)
      refs[[length(refs) + 1]] <- list(sm = bs_null_reference(p$job, tol, p$rungs),
                                       un = bs_null_reference(p$ns, tol, p$rungs, UNSMOOTHED))
    }
    if (!length(cells)) next
    cells <- do.call(rbind, cells)
    res <- lapply(split(cells, cells$rung), bs_corrected_rung)
    sc <- do.call(rbind, lapply(res, `[[`, "scores")); ld <- do.call(rbind, lapply(res, `[[`, "leads"))
    # Checks: every corrected F1 equals its null re-score's; every lead over
    # the smoothed baseline equals the paper's null leads; the observed F1
    # equals the pooled result rows.
    rd <- do.call(rbind, lapply(refs, function(z) rbind(z$sm$delta, z$un$delta)))
    rl <- do.call(rbind, lapply(refs, function(z) z$sm$leads))
    chk <- c(
      corrected_F1 = bs_max_diff(sc[sc$metric == "F1_corrected", ], rd, c("scope", "detector", "rung")),
      leads_over_smoothed = bs_max_diff(
        ld[ld$contrast == "lead over smoothed" & sub("\\|.*", "", ld$to) %in% LADDER, ], rl,
        c("scope", "rung", "kind", "to")),
      observed_F1 = if (tol == 4) bs_max_diff(
        sc[sc$metric == "F1" & sc$scope == "five sites" & sc$detector %in% c("chm_vwf", UNSMOOTHED, ARMS), ],
        est[est$metric == "F1", ], c("scope", "detector", "rung")) else 0)
    cat(sprintf("\ncheck at %g m: %s\n", tol, paste(sprintf("%s max |diff| %.2g", names(chk), chk), collapse = "; ")))
    if (any(chk > BS_TOL)) stop("The corrected tables at ", tol, " m differ from the null re-scores or results")
    corr_sc[[length(corr_sc) + 1]] <- cbind(radius_m = tol, sc)
    corr_ld[[length(corr_ld) + 1]] <- cbind(radius_m = tol, ld)
  }
  if (length(corr_sc)) {
    ok <- function(x) x[order(-x$radius_m, match(x$scope, names(BS_SCOPES)), match(x$rung, BS_ORDER)), ]
    sc <- ok(do.call(rbind, corr_sc)); ld <- ok(do.call(rbind, corr_ld))
    write.csv(sc, file.path(OUT, "baseline_smoothing_corrected.csv"), row.names = FALSE)
    write.csv(ld, file.path(OUT, "baseline_smoothing_corrected_leads.csv"), row.names = FALSE)
    for (tol in unique(sc$radius_m)) {
      cat(sprintf("\n== the two baselines at %g m (five sites): F1, null F1, null share, corrected F1\n", tol))
      for (r in intersect(BS_ORDER, sc$rung)) for (a in c("chm_vwf", UNSMOOTHED)) {
        z <- sc[sc$radius_m == tol & sc$scope == "five sites" & sc$rung == r & sc$detector == a, ]
        f <- function(m) z[z$metric == m, ]
        cat(sprintf("%-7s %-19s %.3f  %.3f  %.2f  %.3f [%.3f, %.3f]\n", r, a, f("F1")$estimate,
                    f("null_F1")$estimate, f("null_share")$estimate, f("F1_corrected")$estimate,
                    f("F1_corrected")$lower, f("F1_corrected")$upper))
      }
      cat(sprintf("\n== leads over the unsmoothed baseline at %g m: observed / corrected\n", tol))
      z <- ld[ld$radius_m == tol & ld$contrast == "lead over unsmoothed", ]
      for (s in names(BS_SCOPES)) for (r in intersect(BS_ORDER, z$rung)) {
        zz <- z[z$scope == s & z$rung == r, ]
        for (a in unique(sub("\\|.*", "", zz$to))) {
          o <- zz[zz$kind == "observed" & sub("\\|.*", "", zz$to) == a, ]
          k <- zz[zz$kind == "corrected" & sub("\\|.*", "", zz$to) == a, ]
          cat(sprintf("%-10s %-7s %-15s %+.3f [%+.3f, %+.3f] / %+.3f [%+.3f, %+.3f]\n", s, r, a,
                      o$estimate, o$lower, o$upper, k$estimate, k$lower, k$upper))
        }
      }
    }
    cat(sprintf("wrote %s\n", file.path(OUT, "baseline_smoothing_corrected{,_leads}.csv")))
  }
}
