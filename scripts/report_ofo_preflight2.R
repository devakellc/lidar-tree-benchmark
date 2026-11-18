#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
# The first report's formatting, markdown and section helpers (rep_*); that
# script runs its own main only when executed directly.
source(.find("report_ofo_preflight.R"), local = TRUE)

# Report tables of the Open Forest Observatory second preflight
# (docs/ofo-preflight-protocol-2.md), for results/ofo-preflight-2-results.md:
# (a) crown-frame truth per plot, (b) test units per signal with crown and
# zero errors, (c) the pass rule per signal and subset, (d) registration of
# the candidate plots of groups A and B under the new gates, (e) disturbance
# records and canopy presence per plot, (f) decision per group, gate costs,
# cells and reference stems, (g) the inputs with their SHA-256. Read-only;
# no number is typed by hand. A table whose input is missing, or lacks a
# column, keeps its heading and says what is missing.
# Inputs (P2 = $CLAUDE_JOB_DIR/ofo/preflight2): crown_truth.csv,
#   crowntruth_units.csv, crowntruth_test.json, registration.csv,
#   conditions.csv, disturbance.csv, disturbance_records_detail.csv,
#   cells.csv, plot_admission.csv, group_summary.csv, group_decision.csv,
#   registration_tests.json.
# Output: P2/report_tables.md (or OUT=, a .md file under OFO or outside the job
#   directory, never in the NEON root) and the headline numbers on stdout.
#   Rscript scripts/report_ofo_preflight2.R [OUT=<file>]

REP2_CSV <- c("crown_truth.csv", "crowntruth_units.csv", "registration.csv", "conditions.csv",
              "disturbance.csv", "disturbance_records_detail.csv", "cells.csv",
              "plot_admission.csv", "group_summary.csv", "group_decision.csv")
REP2_CT <- "crowntruth_test.json"
REP2_JSON <- c(REP2_CT, "registration_tests.json")
REP2_SIGNALS <- c("height", "rank")
# Where a per-signal block of crowntruth_test.json may sit, in the order tried.
REP2_SIGNAL_PATHS <- list(character(), "signals", "signal", "tests", "test", "by_signal",
                          "results")

## ---- helpers (pure) --------------------------------------------------------------

# Scalar leaves of a parsed JSON list as a named character vector, names the
# key paths joined by ".", unnamed list members numbered; arrays of scalars
# joined by ", ".
rep2_flatten <- function(x, prefix = character()) {
  if (is.null(x)) return(character())
  if (!is.list(x)) {
    v <- unlist(x, use.names = FALSE)
    s <- if (!length(v)) ""
         else if (is.logical(v)) ifelse(is.na(v), "null", ifelse(v, "true", "false"))
         else if (is.numeric(v)) format(v, digits = 6, trim = TRUE) else as.character(v)
    return(stats::setNames(paste(s, collapse = ", "), paste(prefix, collapse = ".")))
  }
  nm <- names(x)
  if (is.null(nm)) nm <- as.character(seq_along(x))
  nm[!nzchar(nm)] <- as.character(which(!nzchar(nm)))
  unlist(lapply(seq_along(x), function(i) rep2_flatten(x[[i]], c(prefix, nm[i]))),
         use.names = TRUE)
}

# The per-signal block of the crown-frame test: the first of
# REP2_SIGNAL_PATHS holding the signal as a list.
rep2_signal_block <- function(js, signal) {
  for (p in REP2_SIGNAL_PATHS) {
    b <- rep_json_get(js, c(p, signal))
    if (is.list(b)) return(list(block = b, where = paste(c(p, signal), collapse = ".")))
  }
  NULL
}

rep2_dxdy <- function(dx, dy, digits = 2)
  ifelse(is.finite(rep_num_of(dx)) & is.finite(rep_num_of(dy)),
         sprintf("%s, %s", rep_num(dx, digits), rep_num(dy, digits)), REP_DASH)

rep2_need_json <- function(tabs, file) {
  if (is.null(tabs[[file]])) sprintf("Not produced: `%s` is missing.", file) else NULL
}

# "height yes, rank no" from an `admitted` object; a null value (a test not
# final yet) prints as a dash.
rep2_admitted <- function(adm)
  paste(sprintf("%s %s", names(adm), vapply(adm, function(v)
    rep_yes(if (is.null(v) || !length(v)) NA else v[[1]]), character(1))), collapse = ", ")

## ---- (a) crown-frame truth ---------------------------------------------------------

REP2_TRUTH_COLS <- c("plot", "site", "annotation", "ann_year", "source", "n_boxes",
                     "n_truth_stems", "truth_dx", "truth_dy", "truth_on_edge", "s90_truth_m",
                     "tie_dx", "tie_dy", "tie_ncc", "tie_on_edge", "truth_m_dx", "truth_m_dy",
                     "dist_mapped_m", "credible", "reason")

rep2_sec_truth <- function(tabs) {
  msg <- rep_need(tabs, list(crown_truth.csv = REP2_TRUTH_COLS))
  body <- if (!is.null(msg)) msg else {
    t <- tabs$crown_truth.csv
    t <- t[rep_order(t$source, t$site, t$plot, t$ann_year), , drop = FALSE]
    cr <- rep_lgl_of(t$credible) %in% TRUE
    c(rep_md_table(rep_df(
      Plot = t$plot, Site = t$site, Source = t$source, Year = rep_year(t$ann_year),
      Boxes = rep_int(t$n_boxes), "Truth stems" = rep_int(t$n_truth_stems),
      "Truth dx, dy (image), m" = rep2_dxdy(t$truth_dx, t$truth_dy),
      "On edge" = rep_yes(t$truth_on_edge), "s90, m" = rep_num(t$s90_truth_m, 2),
      "Tie dx, dy, m" = rep2_dxdy(t$tie_dx, t$tie_dy), "Tie NCC" = rep_num(t$tie_ncc, 2),
      "Tie on edge" = rep_yes(t$tie_on_edge),
      "Truth dx, dy (method frame), m" = rep2_dxdy(t$truth_m_dx, t$truth_m_dy),
      "Mapped stems to crowns (method frame), m" = rep_num(t$dist_mapped_m, 2),
      Credible = rep_yes(t$credible), Reason = t$reason), "No annotated plot."), "",
      rep_note(sprintf(paste("Source: `crown_truth.csv`. %s of %s annotations credible. The",
                             "distance from the mapped stems to the annotated crowns, in the",
                             "frame of the method's surface, is reported, not tested."),
                       rep_int(sum(cr)), rep_int(nrow(t)))))
  }
  rep_block("(a) Crown-frame truth per plot", body)
}

## ---- (b) test units ------------------------------------------------------------------

REP2_UNIT_COLS <- c("source", "half", "plot", "signal", "variant", "n_signal", "at_min_stems",
                    "accepted", "est_dx", "est_dy", "truth_m_dx", "truth_m_dy", "credible",
                    "error_crown_m", "error_zero_m", "in_test")

rep2_sec_units <- function(tabs) {
  msg <- rep_need(tabs, list(crowntruth_units.csv = REP2_UNIT_COLS))
  body <- if (!is.null(msg)) msg else {
    u <- tabs$crowntruth_units.csv
    out <- character()
    for (s in unique(c(REP2_SIGNALS, sort(unique(u$signal), method = "radix")))) {
      x <- u[u$signal %in% s, , drop = FALSE]
      if (!nrow(x)) next
      it <- rep_lgl_of(x$in_test) %in% TRUE
      x <- x[rep_order(!it, x$source, x$half, x$plot), , drop = FALSE]
      it <- rep_lgl_of(x$in_test) %in% TRUE
      out <- c(out, sprintf("Signal `%s`: %s units, %s in the test.", s, rep_int(nrow(x)),
                            rep_int(sum(it))), "",
               rep_md_table(rep_df(
                 Source = x$source, Half = x$half, Plot = x$plot, Variant = x$variant,
                 Stems = rep_int(x$n_signal), "At smallest count" = rep_yes(x$at_min_stems),
                 Accepted = rep_yes(x$accepted),
                 "Estimate dx, dy, m" = rep2_dxdy(x$est_dx, x$est_dy),
                 "Truth dx, dy, m" = rep2_dxdy(x$truth_m_dx, x$truth_m_dy),
                 Credible = rep_yes(x$credible), "Crown error, m" = rep_num(x$error_crown_m, 2),
                 "Zero error, m" = rep_num(x$error_zero_m, 2), "In test" = rep_yes(x$in_test))),
               "")
    }
    if (!length(out)) out <- c("No test unit.", "")
    c(out, rep_note("Source: `crowntruth_units.csv`. The crown error is the distance from the ",
                    "estimate (shift plus known offset) to the plot's credible crown-frame ",
                    "truth; the zero error is its distance to the zero shift, the truth of ",
                    "the earlier tests. A unit is in the test when its truth is credible, it ",
                    "has at least the smallest stem count and the frozen gate accepts it."))
  }
  rep_block("(b) Test units per signal", body)
}

## ---- (c) pass rule -------------------------------------------------------------------

rep2_sec_pass <- function(tabs) {
  js <- tabs[[REP2_CT]]
  body <- if (is.null(js)) rep2_need_json(tabs, REP2_CT) else {
    blocks <- lapply(stats::setNames(REP2_SIGNALS, REP2_SIGNALS), function(s)
      rep2_signal_block(js, s))
    found <- !vapply(blocks, is.null, logical(1))
    adm <- rep_json_get(js, "admitted")
    adm_line <- if (is.null(adm)) sprintf("`%s` has no top-level `admitted`.", REP2_CT) else
      paste0("Admitted (top-level `admitted`, the final admission): ", rep2_admitted(adm), ".")
    rule <- rep_sc(rep_json_get(js, "rule"))
    tab <- if (!any(found)) sprintf(paste("Not produced: `%s` holds no per-signal block for",
                                          "height or rank (looked at the top level and under",
                                          "%s)."), REP2_CT,
                                    paste0("`", unlist(REP2_SIGNAL_PATHS), "`", collapse = ", "))
    else {
      flat <- lapply(blocks[found], function(b) rep2_flatten(b$block))
      keys <- unique(unlist(lapply(flat, names)))
      df <- rep_df(Statistic = keys)
      for (s in names(flat)) df[[sprintf("%s (`%s`)", s, blocks[[s]]$where)]] <-
        unname(flat[[s]][keys])
      rep_md_table(df)
    }
    c(adm_line, "", tab, "",
      if (!is.na(rule)) c(rep_note("Rule: ", rule), ""),
      rep_note("Source: `", REP2_CT, "`, every field of each signal's block as written ",
               "there, subsets included (benchmark development, benchmark confirmation, ",
               "NIWO)."))
  }
  rep_block("(c) Pass rule per signal and subset", body)
}

## ---- (d) registration of the candidate plots -------------------------------------------

REP2_REG_COLS <- c("plot_id", "project_name", "group", "signal_used", "signal_admitted",
                   "n_signal", "dx", "dy", "flight_admitted", "accepted", "at_min_stems",
                   "second_peak", "second_peak_ok", "rank_accepted", "agreement_m",
                   "agreement_ok", "registered", "reason")

rep2_sec_registration <- function(tabs) {
  msg <- rep_need(tabs, list(registration.csv = REP2_REG_COLS))
  body <- if (!is.null(msg)) msg else {
    r <- tabs$registration.csv
    r <- r[rep_order(rep_group_rank(r$group), r$plot_id), , drop = FALSE]
    fa <- rep_lgl_of(r$flight_admitted) %in% TRUE
    funnel <- do.call(rbind, lapply(unique(r$group), function(g) {
      x <- r[r$group == g, , drop = FALSE]
      f <- rep_lgl_of(x$flight_admitted) %in% TRUE
      a <- f & rep_lgl_of(x$accepted) %in% TRUE & rep_lgl_of(x$at_min_stems) %in% TRUE
      p <- a & rep_lgl_of(x$second_peak_ok) %in% TRUE
      rep_df(Group = g, Signal = x$signal_used[1],
             "Signal admitted" = rep_yes(x$signal_admitted[1]), Candidates = rep_int(nrow(x)),
             "Flight admitted" = rep_int(sum(f)), "Accepted by the frozen gate" = rep_int(sum(a)),
             "One clear peak" = rep_int(sum(p)),
             "Signals agree" = rep_int(sum(p & rep_lgl_of(x$agreement_ok) %in% TRUE)),
             Registered = rep_int(sum(rep_lgl_of(x$registered) %in% TRUE)))
    }))
    x <- r[fa, , drop = FALSE]
    c(rep_md_table(funnel), "",
      rep_md_table(rep_df(
        Plot = x$plot_id, Project = x$project_name, Group = x$group, Signal = x$signal_used,
        Stems = rep_int(x$n_signal), "dx, dy, m" = rep2_dxdy(x$dx, x$dy),
        "Frozen gate" = rep_yes(x$accepted), "second_peak" = rep_num(x$second_peak, 3),
        "One clear peak" = rep_yes(x$second_peak_ok),
        "Diameter accepted (A)" = rep_yes(x$rank_accepted),
        "Height to diameter, m" = rep_num(x$agreement_m, 2),
        "Signals agree" = rep_yes(x$agreement_ok), Registered = rep_yes(x$registered),
        Reason = x$reason), "No candidate plot with an admitted flight."), "",
      rep_note("Source: `registration.csv` of the second protocol (method-2 estimates from ",
               "the first protocol's `registration_catalog.csv`). The plot table lists the ",
               "candidates with an admitted flight; the funnel counts each gate on top of the ",
               "earlier ones. second_peak passes at 0.8 or less; in group A the height and ",
               "diameter estimates must lie within 2.0 m where the diameter estimate is also ",
               "accepted."))
  }
  rep_block("(d) Registration of the candidate plots of groups A and B", body)
}

## ---- (e) disturbance -------------------------------------------------------------------

REP2_DIST_COLS <- c("plot_id", "project_name", "group", "interval_start", "interval_end",
                    "n_fire_records", "fire_names", "fire_clear", "n_activity_records",
                    "activity_names", "nfs_records_source", "activities_clear",
                    "presence_test_stems", "presence_missing", "presence_missing_share",
                    "presence_status", "disturbance_admitted", "disturbance_reason")

rep2_sec_disturbance <- function(tabs) {
  msg <- rep_need(tabs, list(disturbance.csv = REP2_DIST_COLS))
  body <- if (!is.null(msg)) msg else {
    d <- tabs$disturbance.csv
    d <- d[rep_order(rep_group_rank(d$group), d$plot_id), , drop = FALSE]
    fa <- if ("flight_admitted" %in% names(d)) rep_yes(d$flight_admitted) else
      rep(REP_DASH, nrow(d))
    iv <- ifelse(rep_blank(d$interval_start) | rep_blank(d$interval_end), REP_DASH,
                 paste0(d$interval_start, " to ", d$interval_end))
    names_tab <- d[!rep_blank(d$fire_names) | !rep_blank(d$activity_names), , drop = FALSE]
    st <- table(factor(d$presence_status, levels = c("pass", "fail", "not_checked", "not_run")))
    c(rep_md_table(rep_df(
        Plot = d$plot_id, Project = d$project_name, Group = d$group, "Flight admitted" = fa,
        Interval = iv, "Fire records" = rep_int(d$n_fire_records),
        "Fire clear" = rep_yes(d$fire_clear), "Activity records" = rep_int(d$n_activity_records),
        "National Forest land" = rep_yes(d$nfs_records_source),
        "Activities clear" = rep_yes(d$activities_clear),
        "Test stems" = rep_int(d$presence_test_stems), Missing = rep_int(d$presence_missing),
        "Missing share" = rep_pct(d$presence_missing_share), Canopy = d$presence_status,
        Cleared = rep_yes(d$disturbance_admitted), Reason = d$disturbance_reason)), "",
      if (nrow(names_tab)) c(rep_md_table(rep_df(
        Plot = names_tab$plot_id, "Fire records in the interval" = names_tab$fire_names,
        "Activity records in the interval" = names_tab$activity_names)), ""),
      rep_note(sprintf(paste("Source: `disturbance.csv` (per plot) built from the kept",
                             "responses (`records/records_sources.json`). Canopy check:",
                             "pass %s, fail %s, not checked %s, not run %s. The interval runs",
                             "from 1 January of the survey year to the last flight day; fire",
                             "perimeters count within 50 m of the polygon, Forest Service",
                             "activities on the polygon, where those records exist (National",
                             "Forest land)."), rep_int(st[["pass"]]), rep_int(st[["fail"]]),
                       rep_int(st[["not_checked"]]), rep_int(st[["not_run"]]))))
  }
  rep_block("(e) Disturbance records and canopy over mapped trees", body)
}

# Fire perimeters near the plots with an admitted flight that do not count:
# outside the 50 m buffer or outside the interval.
rep2_sec_near <- function(tabs) {
  msg <- rep_need(tabs, list(disturbance_records_detail.csv = c("plot_id", "source", "record",
    "name", "event_date", "event_year", "in_interval", "hit", "distance_m"),
    disturbance.csv = c("plot_id")))
  body <- if (!is.null(msg)) msg else {
    x <- tabs$disturbance_records_detail.csv
    d <- tabs$disturbance.csv
    adm <- if ("flight_admitted" %in% names(d)) d$plot_id[rep_lgl_of(d$flight_admitted) %in% TRUE]
           else d$plot_id
    x <- x[x$record %in% "fire" & x$plot_id %in% adm & rep_num_of(x$distance_m) <= 1000, ,
           drop = FALSE]
    x <- x[rep_order(x$plot_id, rep_num_of(x$distance_m)), , drop = FALSE]
    when <- ifelse(rep_blank(x$event_date), rep_year(x$event_year), x$event_date)
    c(rep_md_table(rep_df(Plot = x$plot_id, Source = x$source, Fire = x$name, Date = when,
                          "In the interval" = rep_yes(x$in_interval),
                          "Within 50 m" = rep_yes(x$hit),
                          "Distance to the polygon, m" = rep_int(x$distance_m)),
                   "No fire perimeter within 1 km of a plot with an admitted flight."), "",
      rep_note("Source: `disturbance_records_detail.csv`; every fire perimeter of either ",
               "fire layer within 1 km of a plot with an admitted flight, whether it counts ",
               "or not."))
  }
  rep_block("Fire perimeters near the plots with an admitted flight", body)
}

## ---- (g) inputs ------------------------------------------------------------------------

rep2_sec_inputs <- function(info) {
  if (is.null(info)) return("Not recorded.")
  rep_md_table(rep_df(File = info$file, Rows = rep_int(info$rows),
                      "Modified (UTC)" = info$mtime, "SHA-256" = info$sha256))
}

## ---- document ----------------------------------------------------------------------------

rep2_document <- function(tabs, info = NULL) {
  c("# OFO second preflight: report tables", "",
    rep_note("Generated by `scripts/report_ofo_preflight2.R` from the stage outputs under ",
             "`<job>/ofo/preflight2`. Every number below is computed from those files; a ",
             "table whose input is missing says so."), "",
    "## 1. Decision (groups A and B)", "", rep_sec_decision(tabs),
    "## 2. Crown-frame test", "", rep2_sec_truth(tabs), rep2_sec_units(tabs),
    rep2_sec_pass(tabs),
    "## 3. Registering catalogue plots", "", rep2_sec_registration(tabs),
    "## 4. Disturbance between survey and flight", "", rep2_sec_disturbance(tabs),
    rep2_sec_near(tabs),
    "## 5. Decision, gate costs, cells and reference stems", "", rep_sec_gates(tabs),
    rep_sec_cells(tabs),
    "## Inputs", "", rep2_sec_inputs(info))
}

rep2_headlines <- function(tabs) {
  na <- function(f) sprintf("n/a (%s missing)", f)
  adm <- rep_json_get(tabs[[REP2_CT]], "admitted")
  r <- tabs$registration.csv; d <- tabs$disturbance.csv; g <- tabs$group_decision.csv
  by <- function(x, v) paste(sprintf("%s %s", sort(unique(x$group)), vapply(sort(unique(x$group)),
    function(k) rep_int(sum(v[x$group == k])), "")), collapse = ", ")
  out <- c(
    "Signals admitted (crown-frame test)" = if (is.null(adm)) na(REP2_CT) else rep2_admitted(adm),
    "Registered candidate plots by group" = if (is.null(r)) na("registration.csv") else
      by(r, rep_lgl_of(r$registered) %in% TRUE),
    "Plots cleared of disturbance by group" = if (is.null(d)) na("disturbance.csv") else
      by(d, rep_lgl_of(d$disturbance_admitted) %in% TRUE),
    "Decisions" = if (is.null(g)) na("group_decision.csv") else
      paste(sprintf("%s %s", g$group, g$decision), collapse = ", "))
  sprintf("%s: %s", names(out), out)
}

## ---- I/O (driver only) -------------------------------------------------------------------

rep2_load <- function(p2) {
  tabs <- stats::setNames(lapply(file.path(p2, REP2_CSV), rep_read_csv), REP2_CSV)
  for (f in REP2_JSON) {
    p <- file.path(p2, f)
    tabs[f] <- list(if (file.exists(p))
      tryCatch(jsonlite::read_json(p, simplifyVector = FALSE), error = function(e) NULL))
  }
  files <- c(REP2_CSV, REP2_JSON)
  paths <- file.path(p2, files)
  ex <- file.exists(paths)
  info <- data.frame(
    file = files,
    rows = vapply(files, function(f) if (is.data.frame(tabs[[f]])) nrow(tabs[[f]]) else NA_real_,
                  numeric(1)),
    mtime = ifelse(ex, format(file.mtime(paths), "%Y-%m-%d %H:%M:%S", tz = "UTC"), "missing"),
    sha256 = vapply(seq_along(paths), function(i) if (ex[i])
      digest::digest(file = paths[i], algo = "sha256") else REP_DASH, character(1)),
    stringsAsFactors = FALSE)
  list(tabs = tabs, info = info)
}

rep2_main <- function(args = commandArgs(TRUE)) {
  a <- strsplit(args, "=", fixed = TRUE)
  A <- stats::setNames(lapply(a, function(x) paste(x[-1], collapse = "=")),
                       vapply(a, `[`, character(1), 1))
  unknown <- setdiff(names(A), "OUT")
  if (length(unknown)) stop("Unknown argument(s): ", paste(unknown, collapse = ", "),
                            "; report_ofo_preflight2.R takes only OUT=", call. = FALSE)
  job <- normalizePath(.job_dir(), mustWork = FALSE)
  p2 <- file.path(job, "ofo", "preflight2")
  out <- if (is.null(A$OUT) || !nzchar(A$OUT)) file.path(p2, "report_tables.md") else A$OUT
  rep_check_out(out, job, file.path(job, "ofo"))
  out_n <- ofo_path_resolve(out)
  ld <- rep2_load(p2)
  doc <- rep2_document(ld$tabs, ld$info)
  dir.create(dirname(out_n), recursive = TRUE, showWarnings = FALSE)
  writeLines(doc, out_n, useBytes = TRUE)
  miss <- grep("^Not produced", doc, value = TRUE)
  cat(sprintf("wrote %s (%d lines, %d tables)\n", out_n, length(doc),
              sum(grepl("^\\| --- ", doc))))
  cat("\nheadline numbers:\n")
  cat(paste0("  ", rep2_headlines(ld$tabs), "\n"), sep = "")
  if (length(miss)) cat("\nsections with missing inputs:\n", paste0("  ", miss, "\n"), sep = "")
  invisible(out_n)
}

if (sys.nframe() == 0L) rep2_main()
