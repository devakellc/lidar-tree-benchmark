#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
# ofo_output_allowed() (OUT guard), ofo_polygon() and ofo_cells() (the tiling
# rule); OFO_REG2 and its gate directions (the frozen method of Amendment 1b).
source(.find("ofo_reference_lib.R"))
source(.find("ofo_registration_lib.R"))

# Report tables of the Open Forest Observatory (OFO) preflight
# (docs/ofo-preflight-protocol.md). Turns the stage outputs under OFO/preflight
# into the markdown tables of results/ofo-preflight-results.md, so that no
# number in them is typed by hand; the prose is written around them. Read-only:
# it reads the CSV/JSON outputs, quotes NEON native density from
# results/pacific-northwest-extension-results.md, and writes one markdown file.
# A table whose input is missing, or lacks a column, keeps its heading and
# carries one line naming what is missing, so the report runs at every stage.
# Inputs (OFO = $CLAUDE_JOB_DIR/ofo): OFO/preflight/{plots,flights,
#   geometry_audit,geometry_by_project,licences,registration_neon,
#   registration_catalog,registration,conditions,state_lidar,cells,
#   plot_admission,group_summary,group_decision}.csv, registration_tests.json
#   and, when present, the Amendment 1 tables registration_units.csv,
#   registration_dev*.csv and registration_confirm.csv.
# Output: OFO/preflight/report_tables.md (or OUT=, a .md file under OFO or
#   outside the job directory: relative paths, `..` and symlinked ancestors
#   are resolved as ofo_output_allowed() does) and the headline numbers on
#   stdout.
#   Rscript scripts/report_ofo_preflight.R [OUT=<file>]

REP_DASH <- "—"
REP_NDASH <- "–"
REP_GROUPS <- c("A", "B", "C", "D")
REP_NEON_PROJECT <- "NEON2023"
REP_EPS <- 1e-9          # threshold comparisons, as the registration stage makes them
REP_WITHIN_M <- 2        # protocol test 1: share of accepted plots within 2.0 m
REP_WITHHELD_HI <- 0.10  # withheld shares above this are counted per plot
REP_LOW_DENS <- 8        # returns per m²: the benchmark's highest decimated rung
REP_DEV_MIN_STEMS <- 15  # development by variant: units with at least this many stems
REP_KT_STEMS <- c(15, 30, 60)   # known-truth plots by signal-stem count
REP_CSV <- c("plots.csv", "flights.csv", "geometry_audit.csv", "geometry_by_project.csv",
             "licences.csv", "registration_neon.csv", "registration_catalog.csv",
             "registration.csv", "conditions.csv", "state_lidar.csv", "cells.csv",
             "plot_admission.csv", "group_summary.csv", "group_decision.csv")
REP_AMEND_CSV <- "^registration_(units|dev.*|confirm)\\.csv$"
REP_TESTS <- "registration_tests.json"
REP_PNW <- "pacific-northwest-extension-results.md"
# Status levels of the conditions contract, in report order.
REP_COND <- list(
  disturbance_status = c(undisturbed = "Undisturbed", disturbed = "Disturbed",
                         unresolved = "Unresolved", not_checked = "Disturbance not checked"),
  snow_status = c(not_winter = "Not winter", snow_free = "Snow-free", snow = "Snow",
                  unknown = "Snow unknown"),
  leafoff_status = c(leaf_on = "Leaf-on", leaf_off_minor = "Leaf-off minor",
                     leaf_off_held = "Leaf-off held"))

## ---- formatting (pure) --------------------------------------------------------

rep_num_of <- function(x) suppressWarnings(as.numeric(x))

rep_lgl_of <- function(x) {
  if (is.logical(x)) return(x)
  s <- toupper(trimws(as.character(x)))
  out <- rep(NA, length(s))
  out[s %in% c("TRUE", "T")] <- TRUE
  out[s %in% c("FALSE", "F")] <- FALSE
  out
}

rep_blank <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))

# Counts: integers with thousands separators; missing is a dash.
rep_int <- function(x) {
  v <- rep_num_of(x)
  out <- rep(REP_DASH, length(v))
  ok <- is.finite(v)
  out[ok] <- formatC(round(v[ok]), format = "d", big.mark = ",")
  out
}

# Densities, distances, areas: fixed decimals. A non-zero value that would
# print as zero prints as "<0.1" so a coarse rounding never reads as none.
rep_num <- function(x, digits = 1) {
  v <- rep_num_of(x)
  out <- rep(REP_DASH, length(v))
  ok <- is.finite(v)
  out[ok] <- formatC(v[ok], format = "f", digits = digits, big.mark = ",")
  unit <- formatC(10^-digits, format = "f", digits = digits)
  tiny <- ok & v != 0 & abs(v) < 0.5 * 10^-digits
  out[tiny & v > 0] <- paste0("<", unit)
  out[tiny & v < 0] <- paste0(">-", unit)
  out
}

# Shares as percentages with one decimal.
rep_pct <- function(x, digits = 1) {
  out <- rep_num(100 * rep_num_of(x), digits)
  ok <- out != REP_DASH
  out[ok] <- paste0(out[ok], "%")
  out
}

rep_yes <- function(x) {
  v <- rep_lgl_of(x)
  ifelse(is.na(v), REP_DASH, ifelse(v, "yes", "no"))
}

rep_year <- function(x) {
  v <- rep_num_of(x)
  ifelse(is.finite(v), as.character(round(v)), REP_DASH)
}

# "min-max" of the finite values (one value when they agree).
rep_range <- function(x, fmt = rep_num) {
  v <- rep_num_of(x); v <- v[is.finite(v)]
  if (!length(v)) return(REP_DASH)
  lo <- fmt(min(v)); hi <- fmt(max(v))
  if (identical(lo, hi)) lo else paste0(lo, REP_NDASH, hi)
}

rep_med_range <- function(x, fmt = rep_num) {
  v <- rep_num_of(x); v <- v[is.finite(v)]
  if (!length(v)) return(REP_DASH)
  sprintf("%s (%s)", fmt(stats::median(v)), rep_range(v, fmt))
}

rep_median <- function(x, fmt = rep_num) {
  v <- rep_num_of(x); v <- v[is.finite(v)]
  if (!length(v)) REP_DASH else fmt(stats::median(v))
}

# Distinct non-missing values, sorted in C-locale order.
rep_uniq <- function(x, sep = ", ") {
  x <- as.character(x); x <- x[!rep_blank(x)]
  if (!length(x)) return(REP_DASH)
  paste(sort(unique(x), method = "radix"), collapse = sep)
}

# Distinct numeric values in numeric order; "none" marks missing values.
rep_uniq_num <- function(x, fmt = rep_num, sep = ", ") {
  v <- rep_num_of(x)
  u <- sort(unique(v[is.finite(v)]))
  s <- c(if (length(u)) fmt(u), if (any(!is.finite(v))) "none")
  if (!length(s)) REP_DASH else paste(s, collapse = sep)
}

# "value (count)" for each distinct non-missing value, in C-locale order.
rep_tally <- function(x, sep = ", ") {
  x <- as.character(x); x <- x[!rep_blank(x)]
  if (!length(x)) return(REP_DASH)
  k <- sort(unique(x), method = "radix")
  n <- vapply(k, function(v) sum(x == v), integer(1))
  paste(sprintf("%s (%s)", k, rep_int(n)), collapse = sep)
}

rep_group_label <- function(g) ifelse(rep_blank(g), REP_DASH, as.character(g))

# Sort key of a group: A-D first, ungrouped last.
rep_group_rank <- function(g) {
  r <- match(as.character(g), REP_GROUPS)
  r[is.na(r)] <- length(REP_GROUPS) + 1L
  r
}

rep_order <- function(...) order(..., method = "radix")

## ---- markdown (pure) -----------------------------------------------------------

rep_cell <- function(x) {
  s <- as.character(x)
  s[rep_blank(s)] <- REP_DASH
  s <- gsub("[\r\n]+", " ", s)
  # Bare URLs (licence citations) as autolinks, trailing punctuation outside.
  s <- gsub("(https?://[^ <>|]*[^ <>|.,;:)])", "<\\1>", s, perl = TRUE)
  gsub("|", "\\|", s, fixed = TRUE)
}

# GitHub-flavoured table of a data frame whose columns are already formatted.
rep_md_table <- function(df, empty = "No rows.") {
  if (is.null(df) || !nrow(df)) return(empty)
  body <- vapply(df, rep_cell, character(nrow(df)))
  if (!is.matrix(body)) body <- matrix(body, nrow = nrow(df))
  hdr <- rep_cell(names(df))
  c(paste0("| ", paste(hdr, collapse = " | "), " |"),
    paste0("| ", paste(rep("---", length(hdr)), collapse = " | "), " |"),
    apply(body, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}

rep_note <- function(...) strwrap(paste0(...), width = 80)

# A heading and its lines; prose lines (not table rows) wrap at 80 characters.
rep_block <- function(title, lines, level = 3) {
  wrap <- unlist(lapply(lines, function(l)
    if (nchar(l) > 80 && !startsWith(l, "|")) strwrap(l, width = 80) else l))
  c(paste(strrep("#", level), title), "", wrap, "")
}

# NULL when every input is present with its columns; else one line naming
# what is missing. `req` maps an input name to its required columns.
rep_need <- function(tabs, req) {
  msg <- character()
  for (f in names(req)) {
    t <- tabs[[f]]
    if (is.null(t)) {
      msg <- c(msg, sprintf("`%s` is missing", f))
    } else {
      miss <- setdiff(req[[f]], names(t))
      if (length(miss))
        msg <- c(msg, sprintf("`%s` lacks column(s) %s", f,
                              paste0("`", miss, "`", collapse = ", ")))
    }
  }
  if (length(msg)) paste0("Not produced: ", paste(msg, collapse = "; "), ".") else NULL
}

# Value at a key path of a parsed JSON list, or NULL.
rep_json_get <- function(x, path) {
  for (k in path) {
    if (!is.list(x) || is.null(x[[k]])) return(NULL)
    x <- x[[k]]
  }
  x
}

# As rep_need for a key path (and the fields of each entry under it).
rep_need_json <- function(tabs, path, fields = NULL, entries = NULL) {
  js <- tabs[[REP_TESTS]]
  if (is.null(js)) return(sprintf("Not produced: `%s` is missing.", REP_TESTS))
  x <- rep_json_get(js, path)
  where <- paste(path, collapse = ".")
  if (is.null(x)) return(sprintf("Not produced: `%s` lacks `%s`.", REP_TESTS, where))
  miss <- character()
  for (e in entries) {
    xe <- x[[e]]
    if (is.null(xe)) miss <- c(miss, sprintf("`%s.%s`", where, e))
    else miss <- c(miss, sprintf("`%s.%s.%s`", where, e, setdiff(fields, names(xe))))
  }
  if (is.null(entries) && length(fields))
    miss <- sprintf("`%s.%s`", where, setdiff(fields, names(x)))
  if (length(miss)) sprintf("Not produced: `%s` lacks %s.", REP_TESTS,
                            paste(miss, collapse = ", "))
  else NULL
}

# Records (a JSON array of objects) as a character data frame.
rep_records <- function(x) {
  if (!length(x)) return(NULL)
  keys <- unique(unlist(lapply(x, names)))
  as.data.frame(lapply(stats::setNames(keys, keys), function(k)
    vapply(x, function(r) {
      v <- r[[k]]
      if (is.null(v) || !length(v)) NA_character_ else as.character(v[[1]])
    }, character(1))), stringsAsFactors = FALSE, check.names = FALSE)
}

# One summary row per distinct key combination of `df`; `fun` maps the rows
# of one combination to a one-row data frame.
rep_by <- function(df, keys, fun) {
  if (!nrow(df)) return(NULL)
  id <- do.call(paste, c(lapply(df[keys], function(v) ifelse(is.na(v), "\001", v)),
                         sep = "\r"))
  first <- which(!duplicated(id))
  out <- do.call(rbind, lapply(first, function(i)
    cbind(df[i, keys, drop = FALSE], fun(df[id == id[i], , drop = FALSE]))))
  rownames(out) <- NULL
  out
}

rep_group_of <- function(plots, ids) {
  g <- if (is.null(plots)) rep(NA_character_, length(ids))
       else as.character(plots$group[match(ids, plots$plot_id)])
  g[rep_blank(g)] <- NA_character_
  g
}

rep_df <- function(...) data.frame(..., check.names = FALSE, stringsAsFactors = FALSE)

# A JSON scalar (NULL or empty -> NA).
rep_sc <- function(v) if (is.null(v) || !length(v)) NA else v[[1]]

## ---- 1. decision ------------------------------------------------------------------

rep_sec_decision <- function(tabs) {
  f <- "group_decision.csv"
  req <- list(c("group", "decision", "reasons", "signal", "signal_admitted",
                "plots_admitted", "plots_with_headline", "ref_headline", "floor_cm"))
  names(req) <- f
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    d <- tabs[[f]]
    d <- d[rep_order(rep_group_rank(d$group), d$group), , drop = FALSE]
    c(rep_md_table(rep_df(
      Group = rep_group_label(d$group), Decision = d$decision, Signal = d$signal,
      "Signal admitted" = rep_yes(d$signal_admitted),
      "Plots admitted" = rep_int(d$plots_admitted),
      "Plots with headline cells" = rep_int(d$plots_with_headline),
      "Reference stems in headline cells" = rep_int(d$ref_headline),
      "Group floor, cm" = rep_num(d$floor_cm), Reasons = d$reasons)),
      "", rep_note("Source: `group_decision.csv` (decision stage)."))
  }
  rep_block("Decision per group", body)
}

## ---- 2. catalogue -----------------------------------------------------------------

rep_catalogue_row <- function(x, label) {
  rep_df(Project = label, Plots = rep_int(nrow(x)), Screen = rep_tally(x$screen),
         "Group(s)" = rep_tally(x$group),
         "Survey years" = rep_uniq_num(x$survey_year, rep_year),
         "Plot area, ha (range)" = rep_range(x$plot_area_ha, function(v) rep_num(v, 2)),
         "Total area, ha" = rep_num(sum(rep_num_of(x$plot_area_ha), na.rm = TRUE), 2),
         "Live diameter floor(s), cm" = rep_uniq_num(x$live_floor_cm),
         "Plots with heights measured" =
           if (nrow(x)) rep_pct(mean(rep_lgl_of(x$heights_measured) %in% TRUE)) else REP_DASH,
         Trees = rep_int(sum(rep_num_of(x$n_trees), na.rm = TRUE)),
         "Live stems of at least 10 cm" = rep_int(sum(rep_num_of(x$n_live_dbh10), na.rm = TRUE)),
         Licence = rep_uniq(x$license_short))
}

rep_sec_catalogue <- function(tabs) {
  req <- list(plots.csv = c("plot_id", "project_name", "screen", "group", "survey_year",
                            "plot_area_ha", "live_floor_cm", "heights_measured", "n_trees",
                            "n_live_dbh10", "license_short"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    p <- tabs$plots.csv
    projs <- sort(unique(p$project_name), method = "radix")
    rows <- lapply(projs, function(k) rep_catalogue_row(p[p$project_name %in% k, ], k))
    rows <- c(rows, list(
      rep_catalogue_row(p[!p$project_name %in% REP_NEON_PROJECT, ], "All non-NEON projects"),
      rep_catalogue_row(p, "Whole catalogue")))
    c(rep_md_table(do.call(rbind, rows)), "",
      rep_note("Source: `plots.csv`. Plot area is the catalogue's `plot_area_ha`; the ",
               "diameter floor is `live_floor_cm` (\"none\": no floor recorded); heights ",
               "count as measured under the protocol's 90% rule."))
  }
  rep_block("Catalogue by project", body)
}

rep_sec_groups <- function(tabs) {
  req <- list(plots.csv = c("plot_id", "project_name", "group", "n_ref"),
              flights.csv = c("plot_id", "flight_admitted"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    p <- tabs$plots.csv
    p <- p[!rep_blank(p$group), , drop = FALSE]
    fl <- tabs$flights.csv
    p$fa <- rep_lgl_of(fl$flight_admitted[match(p$plot_id, fl$plot_id)]) %in% TRUE
    row <- function(x, label)
      rep_df(Group = label, "Projects (plots)" = rep_tally(x$project_name),
             Plots = rep_int(nrow(x)), "Plots with an admitted flight" = rep_int(sum(x$fa)),
             "Reference stems in them" = rep_int(sum(rep_num_of(x$n_ref[x$fa]), na.rm = TRUE)))
    gs <- unique(p$group); gs <- gs[rep_order(rep_group_rank(gs), gs)]
    rows <- c(lapply(gs, function(g) row(p[p$group == g, ], g)), list(row(p, "All groups")))
    c(rep_md_table(do.call(rbind, rows)), "",
      rep_note("Source: `plots.csv` (group, `n_ref`: reference stems under each plot's ",
               "own gate, before group floors are harmonised) and `flights.csv`."))
  }
  rep_block("Plot groups", body)
}

## ---- 3. flights -------------------------------------------------------------------

# Plot-clip densities of the NEON table in the Pacific Northwest results,
# quoted cell by cell: data frame site, all, first; NULL when not found.
rep_quote_neon_density <- function(lines) {
  if (is.null(lines)) return(NULL)
  split_row <- function(l) trimws(strsplit(sub("^\\s*\\|", "", sub("\\|\\s*$", "", l)),
                                           "|", fixed = TRUE)[[1]])
  h <- grep("^\\s*\\|.*Plot clips, all returns.*Plot clips, first returns", lines)
  if (!length(h)) return(NULL)
  hdr <- split_row(lines[h[1]])
  ia <- grep("^Plot clips, all returns", hdr); iff <- grep("^Plot clips, first returns", hdr)
  if (length(ia) != 1 || length(iff) != 1) return(NULL)
  rows <- list()
  i <- h[1] + 1
  while (i <= length(lines) && grepl("^\\s*\\|", lines[i])) {
    r <- split_row(lines[i])
    if (!all(grepl("^:?-+:?$", r)) && length(r) == length(hdr))
      rows[[length(rows) + 1]] <- data.frame(site = r[1], all = r[ia], first = r[iff],
                                             stringsAsFactors = FALSE)
    i <- i + 1
  }
  if (length(rows)) do.call(rbind, rows) else NULL
}

rep_flight_row <- function(x, label, wu, total = FALSE) {
  adm <- rep_lgl_of(x$flight_admitted) %in% TRUE
  why <- x$flight_reason[!adm]; why[rep_blank(why)] <- "unrecorded"
  months <- substr(x$flown_from[!rep_blank(x$flown_from)], 1, 7)
  units <- x[[wu]][!rep_blank(x[[wu]])]
  rep_df(Project = label, Plots = rep_int(nrow(x)),
         "Selected work unit(s) (plots)" =
           if (total) sprintf("%s work units", rep_int(length(unique(units))))
           else rep_tally(units),
         "Quality level (plots)" = rep_tally(x$ql),
         "Flight months" = if (!length(months)) REP_DASH
           else if (total) paste0(min(months), " to ", max(months)) else rep_uniq(months),
         "Gap, years" = rep_uniq_num(x$gap_years[!rep_blank(x$gap_years)], rep_int),
         "All returns per m², median (range)" = rep_med_range(x$dens_all),
         "First returns per m², median (range)" = rep_med_range(x$dens_first),
         "Plots with an admitted flight" = rep_int(sum(adm)),
         "Other plots by reason" = rep_tally(why))
}

rep_sec_flights <- function(tabs) {
  req <- list(flights.csv = c("plot_id", "project_name", "ept", "ql", "cloud_status",
                              "dens_all", "dens_first", "flown_from", "gap_years",
                              "flight_admitted", "flight_reason"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    f <- tabs$flights.csv
    wu <- if ("workunit" %in% names(f)) "workunit" else "ept"
    projs <- sort(unique(f$project_name), method = "radix")
    adm <- rep_lgl_of(f$flight_admitted) %in% TRUE
    rows <- c(lapply(projs, function(k) rep_flight_row(f[f$project_name %in% k, ], k, wu)),
              list(rep_flight_row(f, "All non-NEON plots", wu, total = TRUE),
                   rep_flight_row(f[adm, , drop = FALSE], "Admitted flights", wu,
                                  total = TRUE)))
    tab <- do.call(rbind, rows)
    neon <- rep_quote_neon_density(tabs[[REP_PNW]])
    note <- if (is.null(neon))
      sprintf("NEON comparison not added: no plot-clip density table found in `%s`.", REP_PNW)
    else {
      nr <- tab[rep(1, nrow(neon)), , drop = FALSE]
      nr[] <- REP_DASH
      nr$Project <- sprintf("NEON %s (quoted)", neon$site)
      nr[["All returns per m², median (range)"]] <- neon$all
      nr[["First returns per m², median (range)"]] <- neon$first
      tab <- rbind(tab, nr)
      sprintf(paste("NEON rows quote the plot-clip densities of `results/%s`",
                    "(native clips, nominal core plus 25 m) verbatim."), REP_PNW)
    }
    c(rep_md_table(tab), "",
      rep_note("Source: `flights.csv`, the selected flight of each non-NEON plot. ",
               "Densities are inside the plot polygon over its geodesic area, classes 7 ",
               "and 18 and returns flagged withheld dropped; flight months are those of ",
               "`flown_from`. \"Admitted flights\" summarises the plots whose flight is ",
               "admitted. "),
      rep_note(note), "", rep_withheld_table(f))
  }
  rep_block("Flights by project", body)
}

# Share of a plot's returns (inside the polygon) flagged withheld, over the
# plots with a cloud and over the admitted flights: median, maximum with its
# plot, and plots above REP_WITHHELD_HI.
rep_withheld_table <- function(f) {
  need <- c("plot_id", "cloud_status", "flight_admitted", "withheld_share")
  if (length(setdiff(need, names(f))))
    return(sprintf("Not produced: the withheld-share table needs %s in `flights.csv`.",
                   paste0("`", setdiff(need, names(f)), "`", collapse = ", ")))
  w <- rep_num_of(f$withheld_share)
  row <- function(k, label) {
    k <- k & is.finite(w)
    i <- which(k)
    top <- if (length(i)) i[rep_order(-w[i], f$plot_id[i])][1] else NA
    out <- rep_df(Flights = label, Plots = rep_int(length(i)),
                  "Median withheld share" = rep_median(w[i], rep_pct),
                  "Maximum (plot)" = if (is.na(top)) REP_DASH
                    else sprintf("%s (%s)", rep_pct(w[top]), f$plot_id[top]),
                  above = rep_int(sum(w[i] > REP_WITHHELD_HI + REP_EPS)))
    names(out)[5] <- sprintf("Plots above %s", rep_pct(REP_WITHHELD_HI, 0))
    out
  }
  c(rep_md_table(rbind(row(f$cloud_status %in% "ok", "Plots with a cloud"),
                       row(rep_lgl_of(f$flight_admitted) %in% TRUE, "Admitted flights"))), "",
    rep_note("Source: `flights.csv` (`withheld_share`: returns flagged withheld among all ",
             "stored returns inside the plot polygon; they are dropped from every ",
             "measurement)."))
}

## ---- 4. geometry ------------------------------------------------------------------

rep_sec_geometry <- function(tabs) {
  req <- list(geometry_by_project.csv = c("project_name", "n_plots", "n_trees", "share_outside",
                                          "n_geometry_held", "n_geometry_na", "n_duplicate_xy",
                                          "n_plots_overlapping", "coord_step_m_max"),
              geometry_audit.csv = c("plot_id", "project_name", "geometry_consistent",
                                     "ref_share_inside_1m"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    g <- tabs$geometry_by_project.csv
    a <- tabs$geometry_audit.csv
    g <- g[rep_order(g$project_name), , drop = FALSE]
    held <- a[rep_lgl_of(a$geometry_consistent) %in% FALSE, , drop = FALSE]
    held <- held[rep_order(held$plot_id), , drop = FALSE]
    ids <- vapply(g$project_name, function(k) {
      h <- held[held$project_name %in% k, , drop = FALSE]
      if (!nrow(h)) REP_DASH
      else paste(sprintf("%s (%s)", h$plot_id, rep_pct(h$ref_share_inside_1m)), collapse = ", ")
    }, character(1), USE.NAMES = FALSE)
    n_tr <- rep_num_of(g$n_trees)
    n_out <- round(rep_num_of(g$share_outside) * n_tr)
    tot <- function(v) sum(rep_num_of(v), na.rm = TRUE)
    nn <- !g$project_name %in% REP_NEON_PROJECT
    row <- function(k, label, ids_text)
      rep_df(Project = label, Plots = rep_int(tot(g$n_plots[k])), Trees = rep_int(sum(n_tr[k])),
             "Stems outside the polygon" = rep_pct(sum(n_out[k]) / sum(n_tr[k])),
             "Plots failing the 95% rule" = rep_int(tot(g$n_geometry_held[k])),
             "Failing plots (reference stems within 1 m)" = ids_text,
             "Plots without reference stems" = rep_int(tot(g$n_geometry_na[k])),
             "Duplicate positions" = rep_int(tot(g$n_duplicate_xy[k])),
             "Plots overlapping another" = rep_int(tot(g$n_plots_overlapping[k])),
             "Coordinate step, m" =
               rep_num(suppressWarnings(max(rep_num_of(g$coord_step_m_max[k]), na.rm = TRUE))))
    rows <- c(lapply(seq_len(nrow(g)), function(i) row(i, g$project_name[i], ids[i])),
              list(row(nn, "All non-NEON projects", REP_DASH),
                   row(rep(TRUE, nrow(g)), "Whole catalogue", REP_DASH)))
    c(rep_md_table(do.call(rbind, rows)), "",
      rep_note("Source: `geometry_by_project.csv` and `geometry_audit.csv`. A plot fails ",
               "the 95% rule when fewer than 95% of its reference stems lie inside the ",
               "polygon buffered by 1 m. The coordinate step is the coarsest positional ",
               "step implied by the stored decimals."))
  }
  rep_block("Geometry by project", body)
}

## ---- 5. registration --------------------------------------------------------------

rep_signals_in <- function(x) {
  if (!is.list(x) || is.null(names(x))) return(character())
  s <- names(x)[vapply(x, function(e) is.list(e) && !is.null(e$n_run), logical(1))]
  s[rep_order(match(s, c("height", "rank")), s)]
}

# Prefixes under which a test record `key` lives in registration_tests.json:
# the top level, and the "declared" and "amendment1" blocks of Amendment 1
# (which moves the declared record under "declared"). Identical copies count
# once.
rep_json_where <- function(js, key) {
  out <- list(); seen <- list()
  for (w in list(character(), "declared", "amendment1", c("amendment1", "catalog"))) {
    x <- rep_json_get(js, c(w, key))
    if (is.null(x) || any(vapply(seen, identical, logical(1), x))) next
    out[[length(out) + 1]] <- w; seen[[length(seen) + 1]] <- x
  }
  out
}

rep_where_label <- function(w) if (length(w)) paste(w, collapse = ".") else "top level"

rep_key <- function(...) paste(c(...), collapse = ".")

rep_sec_known_truth <- function(tabs) {
  fields <- c("n_plots", "n_run", "n_accepted", "median_error_m", "n_within_2m",
              "share_within_2m", "pass")
  js <- tabs[[REP_TESTS]]
  where <- rep_json_where(js, "test1_known_truth")
  rows <- list(); bad <- character(); check <- NULL; ms <- NULL
  for (w in where) {
    t1 <- rep_json_get(js, c(w, "test1_known_truth"))
    sig <- rep_signals_in(t1)
    miss <- unlist(lapply(sig, function(s) setdiff(fields, names(t1[[s]]))))
    if (!length(sig) || length(miss)) {
      bad <- c(bad, sprintf("`%s` lacks per-signal field(s) %s", rep_key(w, "test1_known_truth"),
                            if (length(miss)) paste0("`", unique(miss), "`", collapse = ", ")
                            else "(no signal entry)"))
      next
    }
    for (s in sig) {
      e <- lapply(t1[[s]], rep_sc)
      rows[[length(rows) + 1]] <- rep_df(
        Record = rep_where_label(w), Signal = s, Plots = rep_int(e$n_plots),
        Run = rep_int(e$n_run), Accepted = rep_int(e$n_accepted),
        "Median error of accepted, m" = rep_num(e$median_error_m),
        "Accepted within 2 m" = sprintf("%s (%s of %s)", rep_pct(e$share_within_2m),
                                        rep_int(e$n_within_2m), rep_int(e$n_accepted)),
        Result = if (isTRUE(e$pass)) "pass" else "fail")
    }
    pr <- rep_json_get(js, c(w, "pass_rules", "known_truth"))
    if (!is.null(pr)) {
      pr <- lapply(pr, rep_sc)
      rule <- rows[[length(rows)]]; rule[] <- REP_DASH
      rule$Record <- rep_where_label(w); rule$Signal <- "Pass rule"
      rule$Accepted <- paste0("at least ", rep_int(pr$min_accepted))
      rule[["Median error of accepted, m"]] <- paste0("at most ", rep_num(pr$max_median_error))
      rule[["Accepted within 2 m"]] <- paste0("at least ", rep_pct(pr$min_share))
      rows[[length(rows) + 1]] <- rule
    }
    if (is.null(ms)) ms <- rep_json_get(js, c(w, "method", "min_stems"))
    # registration_neon.csv holds the declared method's rows.
    if (is.null(check) && !identical(w, "amendment1"))
      check <- rep_known_truth_check(tabs$registration_neon.csv, t1, sig)
  }
  body <- if (!length(rows)) {
    if (is.null(js)) sprintf("Not produced: `%s` is missing.", REP_TESTS)
    else if (!length(where)) sprintf("Not produced: `%s` lacks `test1_known_truth`.", REP_TESTS)
    else sprintf("Not produced: %s.", paste(bad, collapse = "; "))
  } else {
    tab <- do.call(rbind, rows)
    if (length(where) < 2) tab$Record <- NULL
    c(rep_md_table(tab), "",
      rep_note("Source: `registration_tests.json`, test 1 (record per block; the ",
               "declared method's record is the top level, or `declared` once Amendment 1 ",
               "is confirmed). Run: plots with an estimate",
               if (!is.null(ms)) sprintf(", at least %s signal stems under the declared method",
                                         rep_sc(ms)), "."),
      if (length(bad)) c("", rep_note(paste(bad, collapse = "; "), ".")), check)
  }
  rep_block("Registration: known-truth test", body)
}

# Recounts run and accepted plots from registration_neon.csv (declared rows
# only when a method column marks them); a line when they differ from the
# record (stale tables).
rep_known_truth_check <- function(neon, t1, sig) {
  if (is.null(neon) || !all(c("signal", "accepted", "error_m") %in% names(neon)))
    return(NULL)
  if ("method" %in% names(neon)) neon <- neon[neon$method %in% "declared", , drop = FALSE]
  bad <- character()
  for (s in sig) {
    x <- neon[neon$signal %in% s, , drop = FALSE]
    run <- is.finite(rep_num_of(x$error_m))
    acc <- sum(run & rep_lgl_of(x$accepted) %in% TRUE)
    if (!identical(as.numeric(sum(run)), rep_num_of(rep_sc(t1[[s]]$n_run))) ||
        !identical(as.numeric(acc), rep_num_of(rep_sc(t1[[s]]$n_accepted))))
      bad <- c(bad, sprintf("%s: %d run, %d accepted in the CSV", s, sum(run), acc))
  }
  if (length(bad)) c("", rep_note("Warning: `registration_neon.csv` disagrees with ",
                                  "`registration_tests.json` (", paste(bad, collapse = "; "),
                                  ")."))
}

rep_sec_known_truth_detail <- function(tabs) {
  js <- tabs[[REP_TESTS]]
  where <- rep_json_where(js, "test1_known_truth")
  hit <- Filter(function(w) !is.null(rep_json_get(js, c(w, "test1_known_truth", "by_accepted"))),
                where)
  w <- if (length(hit)) hit[[1]] else character()
  ba <- rep_records(rep_json_get(js, c(w, "test1_known_truth", "by_accepted")))
  bs <- rep_records(rep_json_get(js, c(w, "test1_known_truth", "by_stem_count")))
  req <- list(by_accepted = c("signal", "accepted", "n", "median_error_m", "p90_error_m",
                              "n_within_2m", "max_error_m"),
              by_stem_count = c("signal", "stems", "n_run", "n_accepted",
                                "median_error_all_m", "median_error_accepted_m"))
  msg <- rep_need(list(by_accepted = ba, by_stem_count = bs), req)
  body <- if (is.null(js)) sprintf("Not produced: `%s` is missing.", REP_TESTS)
  else if (!is.null(msg)) gsub("`(by_[a-z_]+)`", sprintf("`%s` entry `%s`", REP_TESTS,
                                                       rep_key(w, "test1_known_truth", "\\1")), msg)
  else {
    ba <- ba[rep_order(match(ba$signal, c("height", "rank")), ba$signal,
                       rep_lgl_of(ba$accepted)), , drop = FALSE]
    bs <- bs[rep_order(match(bs$signal, c("height", "rank")), bs$signal,
                       rep_num_of(sub("[^0-9].*$", "", bs$stems))), , drop = FALSE]
    c(rep_md_table(rep_df(
      Signal = ba$signal, Accepted = rep_yes(ba$accepted), "Plots run" = rep_int(ba$n),
      "Median error, m" = rep_num(ba$median_error_m),
      "90th percentile, m" = rep_num(ba$p90_error_m), "Maximum, m" = rep_num(ba$max_error_m),
      "Within 2 m" = sprintf("%s (%s)", rep_int(ba$n_within_2m),
                             rep_pct(rep_num_of(ba$n_within_2m) / rep_num_of(ba$n))))),
      "",
      rep_md_table(rep_df(
        Signal = bs$signal, "Signal stems" = bs$stems, Run = rep_int(bs$n_run),
        Accepted = rep_int(bs$n_accepted),
        "Median error of run plots, m" = rep_num(bs$median_error_all_m),
        "Median error of accepted plots, m" = rep_num(bs$median_error_accepted_m))),
      "", rep_note(sprintf("Source: `registration_tests.json`, `%s` (errors of run plots ",
                           rep_key(w, "test1_known_truth")),
                   "by acceptance, then by signal-stem count)."))
  }
  rep_block("Registration: known-truth errors by acceptance and stem count", body)
}


rep_sec_known_truth_sites <- function(tabs) {
  req <- list(registration_neon.csv = c("site", "plot", "signal", "n_signal", "accepted",
                                        "error_m"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    n <- tabs$registration_neon.csv
    n$run <- is.finite(rep_num_of(n$error_m))
    n$acc <- n$run & rep_lgl_of(n$accepted) %in% TRUE
    # A redesigned method may add rows to this table; keep them apart.
    keys <- c(intersect(c("method", "set"), names(n)), "signal", "site")
    tab <- rep_by(n, keys, function(x) {
      e <- rep_num_of(x$error_m[x$acc])
      rep_df(Plots = rep_int(nrow(x)), Run = rep_int(sum(x$run)), Accepted = rep_int(sum(x$acc)),
             "Median error of accepted, m" = rep_median(e),
             "Accepted within 2 m" = rep_int(sum(e <= REP_WITHIN_M + REP_EPS)))
    })
    o <- c(unname(as.list(tab[setdiff(keys, c("signal", "site"))])),
           list(match(tab$signal, c("height", "rank")), tab$signal, tab$site))
    tab <- tab[do.call(rep_order, o), , drop = FALSE]
    names(tab)[seq_along(keys)] <- tools::toTitleCase(keys)
    c(rep_md_table(tab), "",
      rep_note("Source: `registration_neon.csv` (test 1; run = an estimate exists)."))
  }
  rep_block("Registration: known-truth test by site", body)
}

# How many known-truth plots reach a given number of signal stems (test 1,
# the declared method's stem selection), per signal.
rep_sec_known_truth_stems <- function(tabs) {
  req <- list(registration_neon.csv = c("plot", "signal", "n_signal"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    n <- tabs$registration_neon.csv
    if ("method" %in% names(n)) n <- n[n$method %in% "declared", , drop = FALSE]
    sig <- unique(n$signal); sig <- sig[rep_order(match(sig, c("height", "rank")), sig)]
    tab <- do.call(rbind, lapply(sig, function(s) {
      x <- n[n$signal %in% s, , drop = FALSE]
      k <- rep_num_of(x$n_signal)
      out <- rep_df(Signal = s, Plots = rep_int(length(unique(x$plot))))
      for (b in REP_KT_STEMS)
        out[[sprintf("At least %s signal stems", rep_int(b))]] <- rep_int(sum(k >= b, na.rm = TRUE))
      out
    }))
    c(rep_md_table(tab), "",
      rep_note(sprintf(paste("Source: `registration_neon.csv` (test 1; signal stems as the",
                             "declared method selects them: height, live stems with a measured",
                             "height at least the larger of %s m and the plot's median; rank,",
                             "live trees of %s cm diameter or more)."),
                       rep_num(OFO_REG$height_floor, 0), rep_num(OFO_REG$dbh_floor, 0))))
  }
  rep_block("Known-truth test: plots by signal-stem count", body)
}

# Keys that split a per-unit table of Amendment 1, in report order.
REP_UNIT_KEYS <- c("set", "kind", "method", "variant", "signal")

# Per-unit known-truth rows (signal, error_m; accepted when a gate was
# applied) summarised per set, kind, method, variant and signal.
rep_unit_summary <- function(x) {
  x$run <- is.finite(rep_num_of(x$error_m))
  gated <- "accepted" %in% names(x)
  x$acc <- x$run & (if (gated) rep_lgl_of(x$accepted) %in% TRUE else TRUE)
  within <- function(e) if (!length(e)) REP_DASH else
    sprintf("%s (%s)", rep_int(sum(e <= REP_WITHIN_M + REP_EPS)),
            rep_pct(mean(e <= REP_WITHIN_M + REP_EPS)))
  keys <- intersect(REP_UNIT_KEYS, names(x))
  tab <- rep_by(x, keys, function(r) {
    out <- rep_df(Units = rep_int(nrow(r)), Run = rep_int(sum(r$run)),
                  "Median error of run, m" = rep_median(r$error_m[r$run]))
    e <- rep_num_of(r$error_m[r$acc])
    if (gated) cbind(out, rep_df(Accepted = rep_int(sum(r$acc)),
                                 "Median error of accepted, m" = rep_median(e),
                                 "Accepted within 2 m" = within(e)))
    else cbind(out, rep_df("Run within 2 m" = within(e)))
  })
  o <- lapply(keys, function(k) switch(k, set = match(tab[[k]], c("development", "confirmation")),
                                       kind = match(tab[[k]], c("plot", "composite")),
                                       signal = match(tab[[k]], c("height", "rank")), tab[[k]]))
  tab <- tab[do.call(rep_order, c(o, unname(as.list(tab[keys])))), , drop = FALSE]
  names(tab)[seq_along(keys)] <- tools::toTitleCase(keys)
  tab
}

# A table written by another stage, shown as it is: logical columns as yes/no,
# numeric columns as counts (whole numbers) or two decimals, identifiers with
# leading zeros kept as text. At most `max_rows` rows.
rep_verbatim <- function(x, max_rows = 80) {
  fmt <- lapply(x, function(v) {
    s <- as.character(v); blank <- rep_blank(s)
    if (all(blank)) return(rep(REP_DASH, length(s)))
    if (all(blank | toupper(s) %in% c("TRUE", "FALSE"))) return(rep_yes(s))
    n <- rep_num_of(s)
    if (any(grepl("^0[0-9]", s)) || !all(blank | is.finite(n))) return(s)
    if (all(blank | n == round(n))) rep_int(n) else rep_num(n, 2)
  })
  out <- as.data.frame(fmt, check.names = FALSE, stringsAsFactors = FALSE)
  names(out) <- names(x)
  if (nrow(out) > max_rows) out <- out[seq_len(max_rows), , drop = FALSE]
  out
}

# Amendment 1: the units, each per-unit development or confirmation table
# summarised, every other table (summaries, gate sweep, equivariance) as
# written, and the scalars of the amendment block of registration_tests.json.
rep_sec_amendment <- function(tabs) {
  present <- names(tabs)[!vapply(tabs, is.null, logical(1))]
  files <- sort(as.character(grep(REP_AMEND_CSV, present, value = TRUE)), method = "radix")
  out <- character()
  if ("registration_units.csv" %in% files) {
    req <- list(registration_units.csv = c("unit", "set", "kind", "site", "n_members"))
    msg <- rep_need(tabs, req)
    body <- if (!is.null(msg)) msg else {
      u <- tabs$registration_units.csv
      tab <- rep_by(u, c("set", "kind", "site"), function(x)
        rep_df(Units = rep_int(nrow(x)), "Member plots" = rep_int(sum(rep_num_of(x$n_members)))))
      tab <- tab[rep_order(match(tab$set, c("development", "confirmation")), tab$set,
                           match(tab$kind, c("plot", "composite")), tab$kind, tab$site), ,
                 drop = FALSE]
      names(tab)[1:3] <- c("Set", "Kind", "Site")
      c(rep_md_table(tab), "", rep_note("Source: `registration_units.csv`."))
    }
    out <- c(out, rep_block("Registration, Amendment 1: units", body))
  }
  for (f in setdiff(files, "registration_units.csv")) {
    x <- tabs[[f]]
    body <- if (all(c("signal", "error_m") %in% names(x))) {
      c(rep_md_table(rep_unit_summary(x)), "",
        rep_note(sprintf("Source: `%s`, one row per unit summarised (run: an estimate ", f),
                 "exists; accepted: passes the gate recorded in the table, where there is ",
                 "one)."))
    } else {
      v <- rep_verbatim(x)
      c(rep_md_table(v), "",
        rep_note(sprintf("Source: `%s`, as written", f),
                 if (nrow(x) > nrow(v)) sprintf(" (first %s of %s rows)", rep_int(nrow(v)),
                                                rep_int(nrow(x))), "."))
    }
    out <- c(out, rep_block(sprintf("Registration, Amendment 1: %s",
                                    sub("\\.csv$", "", sub("^registration_", "", f))), body))
  }
  blk <- rep_json_get(tabs[[REP_TESTS]], "amendment1")
  if (!is.null(blk)) {
    # Scalars only: entries of arrays (per-unit lists) belong to the CSV tables.
    fl <- rep_json_flat(blk)
    arr <- grepl("(^|\\.)[0-9]+(\\.|$)", fl$Key)
    out <- c(out, rep_block("Registration, Amendment 1: test record", c(
      rep_md_table(fl[!arr, , drop = FALSE]), "",
      rep_note("Source: the `amendment1` block of `", REP_TESTS, "`, flattened",
               if (any(arr)) sprintf("; %s array entries left out", rep_int(sum(arr))), "."))))
  }
  if (!length(out))
    out <- rep_block("Registration, Amendment 1", sprintf(paste(
      "Not produced: no `registration_units.csv`, `registration_dev*.csv`,",
      "`registration_confirm.csv` or `amendment1` block in `%s`."), REP_TESTS))
  out
}

# Amendment 1 confirmation: the pass rule per signal from the test record, the
# accepted units by site, and every accepted unit whose error exceeds 2 m with
# its east and north components (estimate plus the known offset).
rep_sec_confirmation <- function(tabs) {
  title <- "Registration, Amendment 1: confirmation"
  conf <- rep_json_get(tabs[[REP_TESTS]], c("amendment1", "confirmation"))
  req <- list(registration_confirm.csv = c("signal", "unit", "kind", "site", "n_signal",
                                           "offset_dx", "offset_dy", "dx", "dy", "error_m",
                                           "residual_m", "sub_p90_m", "accepted"))
  msg <- rep_need(tabs, req)
  if (is.null(conf) || !is.null(msg))
    return(rep_block(title, if (!is.null(msg)) msg else sprintf(
      "Not produced: no `amendment1.confirmation` block in `%s`.", REP_TESTS)))
  sig <- intersect(c("height", "rank"), names(conf))
  rule <- do.call(rbind, lapply(sig, function(s) {
    r <- conf[[s]]
    rep_df(Signal = s, Units = rep_int(rep_sc(r$n_units)),
           "At or above the smallest stem count" = sprintf("%s (at least %s stems)",
             rep_int(rep_sc(r$n_at_min_stems)), rep_int(rep_sc(r$min_stems))),
           Accepted = rep_int(rep_sc(r$n_accepted)),
           "Median error of accepted, m" = rep_num(rep_num_of(rep_sc(r$median_error_m)), 2),
           "Accepted within 2 m" = sprintf("%s (%s)", rep_int(rep_sc(r$n_within_2m)),
                                           rep_pct(rep_num_of(rep_sc(r$share_within_2m)))),
           Result = if (isTRUE(rep_sc(r$pass))) "pass" else "fail")
  }))
  # The pass rule as recorded with the frozen method (else OFO_REG2_PASS).
  pr <- rep_json_get(tabs[[REP_TESTS]], c("amendment1", "method", "frozen", "pass_rules"))
  if (is.null(pr)) pr <- OFO_REG2_PASS
  pr <- lapply(pr, function(v) rep_num_of(rep_sc(v)))
  rule <- rbind(rule, rep_df(Signal = "Pass rule", Units = REP_DASH,
                             "At or above the smallest stem count" = REP_DASH,
                             Accepted = paste("at least", rep_int(pr$min_accepted)),
                             "Median error of accepted, m" =
                               paste("at most", rep_num(pr$max_median_error)),
                             "Accepted within 2 m" = paste("at least", rep_pct(pr$min_share)),
                             Result = REP_DASH))
  x <- tabs$registration_confirm.csv
  x$err <- rep_num_of(x$error_m)
  a <- x[rep_lgl_of(x$accepted) %in% TRUE & is.finite(x$err), , drop = FALSE]
  site <- rep_by(a, c("signal", "site"), function(r) rep_df(
    "Accepted units" = rep_int(nrow(r)), "Median error, m" = rep_num(stats::median(r$err), 2),
    "Within 2 m" = rep_int(sum(r$err <= REP_WITHIN_M + REP_EPS))))
  site <- site[rep_order(match(site$signal, c("height", "rank")), site$site), , drop = FALSE]
  names(site)[1:2] <- c("Signal", "Site")
  # The same counts with one site left out at a time: does any single site
  # carry the failure?
  sites <- sort(unique(as.character(a$site)), method = "radix")
  out1 <- do.call(rbind, lapply(intersect(c("height", "rank"), unique(a$signal)), function(s)
    do.call(rbind, lapply(c(NA, sites), function(k) {
      r <- a[a$signal == s & (is.na(k) | a$site != k), , drop = FALSE]
      w <- sum(r$err <= REP_WITHIN_M + REP_EPS)
      rep_df(Signal = s, "Site left out" = if (is.na(k)) "none" else k,
             "Accepted units" = rep_int(nrow(r)),
             "Median error, m" = if (nrow(r)) rep_num(stats::median(r$err), 2) else REP_DASH,
             "Within 2 m" = if (nrow(r)) sprintf("%s (%s)", rep_int(w), rep_pct(w / nrow(r)))
                            else REP_DASH)
    }))))
  rep_block(title, c(
    rep_md_table(rule), "", rep_md_table(site), "",
    rep_md_table(rep_far_units(a, tabs$registration_units.csv)), "",
    rep_md_table(out1), "",
    rep_note("Source: the `amendment1.confirmation` block of `", REP_TESTS, "` (pass rule) and ",
             "`registration_confirm.csv` (accepted units by site; accepted units with an error ",
             "above 2 m, where the east and north errors are the estimate plus the known ",
             "offset; members of composites from `registration_units.csv`; the same accepted ",
             "units with one site left out at a time, which is a reading after the fact and ",
             "not a test).")))
}

# Member plots of each unit: the ";"-joined members of a composite from
# registration_units.csv, a dash for a single plot (or when the units table
# is missing).
rep_members <- function(units, unit, kind) {
  m <- if (is.null(units) || !all(c("unit", "members") %in% names(units)))
    rep(NA_character_, length(unit)) else units$members[match(unit, units$unit)]
  ifelse(kind %in% "composite" & !rep_blank(m), gsub(";", ", ", m, fixed = TRUE), REP_DASH)
}

# Accepted known-truth units whose error exceeds 2 m: east and north errors
# are the estimate plus the known offset (positive north: the canopy lies north
# of the mapped stems). `a` holds accepted rows of a per-unit table.
rep_far_units <- function(a, units) {
  a$err <- rep_num_of(a$error_m)
  far <- a[is.finite(a$err) & a$err > REP_WITHIN_M + REP_EPS, , drop = FALSE]
  far <- far[rep_order(match(far$signal, c("height", "rank")), -far$err, far$unit), , drop = FALSE]
  rep_df(Signal = far$signal, Unit = far$unit, Kind = far$kind,
         Members = rep_members(units, far$unit, far$kind), Site = far$site,
         Stems = rep_int(far$n_signal), "Error, m" = rep_num(far$err, 2),
         "Error east, m" = rep_num(rep_num_of(far$dx) + rep_num_of(far$offset_dx), 2),
         "Error north, m" = rep_num(rep_num_of(far$dy) + rep_num_of(far$offset_dy), 2),
         "Residual, m" = rep_num(rep_num_of(far$residual_m), 2),
         "Stability, m" = rep_num(rep_num_of(far$sub_p90_m), 2))
}

# Development of Amendment 1 by variant, ungated: every run unit with at least
# REP_DEV_MIN_STEMS signal stems, per signal and variant, sorted by signal then
# median error.
rep_sec_dev_variants <- function(tabs) {
  req <- list(registration_dev.csv = c("variant", "signal", "unit", "n_signal", "dx", "error_m"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    x <- tabs$registration_dev.csv
    x <- x[is.finite(rep_num_of(x$dx)) & rep_num_of(x$n_signal) >= REP_DEV_MIN_STEMS, ,
           drop = FALSE]
    tab <- rep_by(x, c("signal", "variant"), function(r) {
      e <- rep_num_of(r$error_m); e <- e[is.finite(e)]
      data.frame(n = length(e), med = if (length(e)) stats::median(e) else NA_real_,
                 share = if (length(e)) mean(e <= REP_WITHIN_M + REP_EPS) else NA_real_)
    })
    if (!is.null(tab))
      tab <- tab[rep_order(match(tab$signal, c("height", "rank")), tab$signal, tab$med,
                           tab$variant), , drop = FALSE]
    c(rep_md_table(if (!is.null(tab)) rep_df(
      Signal = tab$signal, Variant = tab$variant, "Units run" = rep_int(tab$n),
      "Median error, m" = rep_num(tab$med, 2), "Share within 2 m" = rep_pct(tab$share))), "",
      rep_note(sprintf(paste("Source: `registration_dev.csv`: development units (plots and",
                             "composites) with at least %s signal stems and an estimate, every",
                             "variant, no gate applied (run = an estimate exists)."),
                       rep_int(REP_DEV_MIN_STEMS))))
  }
  rep_block("Registration, Amendment 1: development by variant", body)
}

# The frozen configuration of each signal (Amendment 1b): from the test record
# `amendment1.method.frozen` when present, else OFO_REG2.
rep_frozen <- function(tabs) {
  fr <- rep_json_get(tabs[[REP_TESTS]], c("amendment1", "method", "frozen"))
  src <- "`amendment1.method.frozen` of `registration_tests.json`"
  if (is.null(fr)) { fr <- OFO_REG2; src <- "`OFO_REG2` in `scripts/ofo_registration_lib.R`" }
  sig <- intersect(c("height", "rank"), names(fr))
  list(src = src, cfg = lapply(stats::setNames(sig, sig), function(s) list(
    variant = rep_sc(fr[[s]]$variant), stat = rep_sc(fr[[s]]$gate$stat),
    threshold = rep_num_of(rep_sc(fr[[s]]$gate$threshold)),
    min_stems = rep_num_of(rep_sc(fr[[s]]$gate$min_stems)))))
}

# The development units under the frozen configuration: per signal, units at
# or above the smallest stem count, accepted under the frozen gate, and the
# accuracy of accepted units; then the accepted units with an error above 2 m.
rep_sec_dev_frozen <- function(tabs) {
  title <- "Registration, Amendment 1: development under the frozen configuration"
  req <- list(registration_dev.csv = c("variant", "signal", "unit", "kind", "site", "n_signal",
                                       "offset_dx", "offset_dy", "dx", "dy", "error_m",
                                       "residual_m", "sub_p90_m", "accepted"))
  msg <- rep_need(tabs, req)
  if (!is.null(msg)) return(rep_block(title, msg))
  fr <- rep_frozen(tabs)
  x <- tabs$registration_dev.csv
  rows <- list(); acc_rows <- list()
  for (s in names(fr$cfg)) {
    g <- fr$cfg[[s]]
    y <- x[x$signal %in% s & x$variant %in% g$variant, , drop = FALSE]
    at <- rep_num_of(y$n_signal) >= g$min_stems - REP_EPS
    e <- rep_num_of(y$error_m)
    acc <- at & rep_lgl_of(y$accepted) %in% TRUE & is.finite(e)
    dir <- unname(OFO_REG2_GATE_STATS[g$stat])
    num2 <- function(v) rep_num(v, 2)
    rows[[s]] <- rep_df(
      Signal = s, Variant = g$variant,
      Gate = sprintf("`%s` %s %s%s", g$stat, if (identical(dir, "min")) "at least"
                     else "at most", rep_num(g$threshold), if (grepl("_m$", g$stat)) " m" else ""),
      "Smallest stem count" = rep_int(g$min_stems), "Units at or above it" = rep_int(sum(at)),
      Accepted = rep_int(sum(acc)), "Median error of accepted, m" = rep_median(e[acc], num2),
      "Accepted within 2 m" = if (!any(acc)) REP_DASH else
        sprintf("%s (%s)", rep_int(sum(e[acc] <= REP_WITHIN_M + REP_EPS)),
                rep_pct(mean(e[acc] <= REP_WITHIN_M + REP_EPS))))
    acc_rows[[s]] <- y[acc, , drop = FALSE]
  }
  if (!length(rows))
    return(rep_block(title, sprintf("Not produced: no frozen configuration in %s.", fr$src)))
  a <- do.call(rbind, acc_rows)
  rep_block(title, c(
    rep_md_table(do.call(rbind, unname(rows))), "",
    rep_md_table(rep_far_units(a, tabs$registration_units.csv),
                 "No accepted development unit has an error above 2 m."), "",
    rep_note("Source: `registration_dev.csv` (rows of the frozen variant; accepted under the ",
             "frozen gate, as recorded in the table) with the frozen configuration from ",
             fr$src, ". The second table lists the accepted development units with an error ",
             "above 2 m, as for the confirmation (east and north errors: estimate plus the ",
             "known offset; members of composites from `registration_units.csv`).")))
}

# Scalar leaves of a nested list as a key path / value table.
rep_json_flat <- function(x, prefix = character()) {
  if (!is.list(x)) {
    v <- if (!length(x)) REP_DASH else paste(as.character(x), collapse = ", ")
    return(rep_df(Key = paste(prefix, collapse = "."), Value = v))
  }
  nm <- names(x); if (is.null(nm)) nm <- as.character(seq_along(x))
  if (!length(x)) return(rep_df(Key = paste(prefix, collapse = "."), Value = REP_DASH))
  do.call(rbind, lapply(seq_along(x), function(i) rep_json_flat(x[[i]], c(prefix, nm[i]))))
}


rep_sec_catalog_registration <- function(tabs) {
  req <- list(registration_catalog.csv = c("plot_id", "project_name", "set", "signal",
                                           "n_signal", "dx", "shift_m", "residual_m",
                                           "accepted"),
              plots.csv = c("plot_id", "group"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    r <- tabs$registration_catalog.csv
    r$group <- rep_group_label(rep_group_of(tabs$plots.csv, r$plot_id))
    r$run <- is.finite(rep_num_of(r$dx))
    r$acc <- r$run & rep_lgl_of(r$accepted) %in% TRUE
    has_m <- "method" %in% names(r)
    fun <- function(x) rep_df(
      Plots = rep_int(length(unique(x$plot_id))), Run = rep_int(sum(x$run)),
      Accepted = rep_int(sum(x$acc)),
      "Median shift of accepted, m" = rep_median(x$shift_m[x$acc]),
      "Median residual of run, m" = rep_median(x$residual_m[x$run]))
    keys <- c("set", "group", "project_name", if (has_m) "method", "signal")
    tab <- rep_by(r, keys, fun)
    tab$tot <- 0L
    r_all <- r; r_all$group <- "all"; r_all$project_name <- "all projects"
    tot <- rep_by(r_all, keys, fun); tot$tot <- 1L
    tab <- rbind(tab, tot)
    o <- list(tab$set, tab$tot, rep_group_rank(tab$group), tab$group, tab$project_name)
    if (has_m) o <- c(o, list(tab$method))
    o <- c(o, list(match(tab$signal, c("height", "rank")), tab$signal))
    tab <- tab[do.call(rep_order, o), setdiff(names(tab), "tot"), drop = FALSE]
    names(tab)[seq_along(keys)] <- c("Set", "Group", "Project", if (has_m) "Method", "Signal")
    c(rep_md_table(tab), "",
      rep_note("Source: `registration_catalog.csv` (one row per plot and signal run). ",
               "Candidate: screened in with a group and an admitted flight; held-out: every ",
               "other non-NEON plot with a cloud (test 2). Run = an estimate exists."))
  }
  rep_block("Registration: catalogue plots by set, group and project", body)
}

rep_sec_agreement <- function(tabs) {
  fields <- c("n_plots", "n_within_2m", "share_within_2m", "pass")
  js <- tabs[[REP_TESTS]]
  where <- rep_json_where(js, "test3_agreement")
  sums <- list(); per <- character(); bad <- character()
  for (w in where) {
    t3 <- rep_json_get(js, c(w, "test3_agreement"))
    key <- rep_key(w, "test3_agreement")
    miss <- setdiff(fields, names(t3))
    if (length(miss)) {
      bad <- c(bad, sprintf("`%s` lacks %s", key, paste0("`", miss, "`", collapse = ", ")))
      next
    }
    pl <- rep_records(t3$plots)
    t3 <- lapply(t3[setdiff(names(t3), "plots")], rep_sc)
    rec <- rep_where_label(w)
    sums[[length(sums) + 1]] <- rep_df(
      Record = rec, "Plots with both signals accepted" = rep_int(t3$n_plots),
      "Within 2 m" = sprintf("%s (%s)", rep_int(t3$n_within_2m), rep_pct(t3$share_within_2m)),
      Result = if (isTRUE(t3$pass)) "pass" else "fail")
    pr <- rep_json_get(js, c(w, "pass_rules", "agreement"))
    if (!is.null(pr)) {
      pr <- lapply(pr, rep_sc)
      sums[[length(sums) + 1]] <- rep_df(
        Record = rec, "Plots with both signals accepted" =
          paste0("Pass rule: at least ", rep_int(pr$min_plots)),
        "Within 2 m" = paste0("at least ", rep_pct(pr$min_share)), Result = REP_DASH)
    }
    need <- c("plot_id", "dx_height", "dy_height", "dx_rank", "dy_rank", "distance_m")
    lab <- if (length(where) > 1) c(sprintf("Plots of the %s record:", rec), "") else NULL
    per <- c(per, lab, if (is.null(pl)) "No plots." else if (length(setdiff(need, names(pl))))
      sprintf("Not produced: `%s.plots` lacks %s.", key,
              paste0("`", setdiff(need, names(pl)), "`", collapse = ", "))
    else {
      pl <- pl[rep_order(pl$plot_id), , drop = FALSE]
      proj <- if (is.null(tabs$plots.csv)) rep(NA, nrow(pl))
              else tabs$plots.csv$project_name[match(pl$plot_id, tabs$plots.csv$plot_id)]
      rep_md_table(rep_df(Plot = pl$plot_id, Project = proj,
                          "Height signal dx, dy (m)" = paste(rep_num(pl$dx_height),
                                                             rep_num(pl$dy_height), sep = ", "),
                          "Rank signal dx, dy (m)" = paste(rep_num(pl$dx_rank),
                                                           rep_num(pl$dy_rank), sep = ", "),
                          "Distance, m" = rep_num(pl$distance_m)))
    }, "")
  }
  body <- if (!length(sums)) {
    if (is.null(js)) sprintf("Not produced: `%s` is missing.", REP_TESTS)
    else if (!length(where)) sprintf("Not produced: `%s` lacks `test3_agreement`.", REP_TESTS)
    else sprintf("Not produced: %s.", paste(bad, collapse = "; "))
  } else {
    sm <- do.call(rbind, sums)
    if (length(where) < 2) sm$Record <- NULL
    c(rep_md_table(sm), "", per,
      rep_note("Source: `registration_tests.json`, test 3 (catalogue plots with measured ",
               "heights where both signals are accepted; record per block)."),
      if (length(bad)) c("", rep_note(paste(bad, collapse = "; "), ".")))
  }
  rep_block("Registration: agreement of the two signals", body)
}

# Columns of registration.csv under the declared method; any other column
# (a gate statistic of a redesigned method) is shown in the candidate table.
REP_REG_COLS <- c("plot_id", "project_name", "group", "signal_used", "signal_admitted", "dx",
                  "dy", "shift_m", "residual_m", "contrast", "n_signal", "registered", "reason",
                  "pos_unc", "flight_admitted", "set", "method")

rep_sec_candidates <- function(tabs) {
  req <- list(registration.csv = c("plot_id", "project_name", "group", "signal_used",
                                   "n_signal", "dx", "dy", "shift_m", "residual_m",
                                   "registered", "reason"),
              flights.csv = c("plot_id", "flight_admitted"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    r <- tabs$registration.csv
    fl <- tabs$flights.csv
    fa <- rep_lgl_of(fl$flight_admitted[match(r$plot_id, fl$plot_id)]) %in% TRUE
    r <- r[fa & r$group %in% c("A", "B", "D"), , drop = FALSE]
    r <- r[rep_order(rep_group_rank(r$group), r$plot_id), , drop = FALSE]
    rc <- tabs$registration_catalog.csv
    by_m <- "method" %in% names(r) && "method" %in% names(rc)
    key <- function(x, sig) paste(x$plot_id, sig, if (by_m) x$method)
    acc <- if (is.null(rc) || !all(c("plot_id", "signal", "accepted") %in% names(rc)))
      rep(NA, nrow(r))
    else rc$accepted[match(key(r, r$signal_used), key(rc, rc$signal))]
    tab <- rep_df(Plot = r$plot_id, Project = r$project_name, Group = r$group,
                  Signal = r$signal_used, Stems = rep_int(r$n_signal),
                  "dx, m" = rep_num(r$dx), "dy, m" = rep_num(r$dy),
                  "Shift, m" = rep_num(r$shift_m), "Residual, m" = rep_num(r$residual_m))
    if ("method" %in% names(r)) tab <- cbind(tab[, 1:4], rep_df(Method = r$method), tab[, -(1:4)])
    if ("contrast" %in% names(r)) tab$Contrast <- rep_num(r$contrast, 2)
    for (k in setdiff(names(r), REP_REG_COLS)) {
      v <- r[[k]]
      num <- all(rep_blank(v) | is.finite(rep_num_of(v)))
      tab[[k]] <- if (num) rep_num(v, 2) else rep_cell(v)
    }
    tab <- cbind(tab, rep_df(Accepted = rep_yes(acc), Registered = rep_yes(r$registered),
                             Reason = r$reason))
    c(rep_md_table(tab, "No candidate plots in groups A, B and D."), "",
      rep_note("Source: `registration.csv` (the signal each plot uses; columns after ",
               "Residual are its gate statistics) and `registration_catalog.csv` (whether ",
               "that signal's own gate accepts it). Candidate plots: screened in, group A, ",
               "B or D, admitted flight."))
  }
  rep_block("Registration: candidate plots of groups A, B and D", body)
}

# Test 2 of the protocol: held-out catalogue plots, one row per plot, signal
# and method (shift, residual and acceptance per plot).
rep_sec_heldout <- function(tabs) {
  req <- list(registration_catalog.csv = c("plot_id", "project_name", "set", "signal",
                                           "n_signal", "dx", "dy", "shift_m", "residual_m",
                                           "accepted", "reject_reason"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    r <- tabs$registration_catalog.csv
    r <- r[r$set %in% "heldout", , drop = FALSE]
    opt <- function(k) if (k %in% names(r)) r[[k]] else rep(NA, nrow(r))
    method <- opt("method")
    r <- r[rep_order(r$plot_id, r$signal, as.character(method)), , drop = FALSE]
    tab <- rep_df(Plot = r$plot_id, Project = r$project_name, Screen = opt("screen"),
                  Signal = r$signal, Method = opt("method"), Stems = rep_int(r$n_signal),
                  "dx, m" = rep_num(r$dx), "dy, m" = rep_num(r$dy),
                  "Shift, m" = rep_num(r$shift_m), "Residual, m" = rep_num(r$residual_m),
                  "On edge" = rep_yes(opt("on_edge")), Accepted = rep_yes(r$accepted),
                  Reason = r$reject_reason, "Flight admitted" = rep_yes(opt("flight_admitted")))
    c(rep_md_table(tab, "No held-out catalogue plots."), "",
      rep_note("Source: `registration_catalog.csv`, set `heldout`: catalogue plots that fail ",
               "the population rules (Screen) and are never scored, registered on their ",
               "best available flight, admitted or not. One row per plot, signal and ",
               "method; `declared` is the first method, kept for the record."))
  }
  rep_block("Registration: held-out catalogue plots", body)
}

## ---- 6. conditions ----------------------------------------------------------------

rep_sec_conditions <- function(tabs) {
  req <- list(conditions.csv = c("plot_id", "project_name", names(REP_COND),
                                 "conditions_admitted"),
              plots.csv = c("plot_id", "group"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    c0 <- tabs$conditions.csv
    c0$group <- rep_group_label(rep_group_of(tabs$plots.csv, c0$plot_id))
    other <- Reduce(`|`, lapply(names(REP_COND), function(k)
      !c0[[k]] %in% names(REP_COND[[k]])))
    fun <- function(x) {
      cols <- unlist(lapply(names(REP_COND), function(k)
        lapply(names(REP_COND[[k]]), function(v) rep_int(sum(x[[k]] %in% v)))), recursive = FALSE)
      names(cols) <- unlist(lapply(REP_COND, unname))
      out <- cbind(rep_df("Plots with a cloud" = rep_int(nrow(x))), as.data.frame(cols,
                   check.names = FALSE, stringsAsFactors = FALSE),
                   rep_df("Conditions admitted" =
                            rep_int(sum(rep_lgl_of(x$conditions_admitted) %in% TRUE))))
      if (any(other)) out[["Other status"]] <- rep_int(sum(other[c0$plot_id %in% x$plot_id]))
      out
    }
    tab <- rep_by(c0, c("group", "project_name"), fun); tab$tot <- 0L
    ca <- c0; ca$project_name <- "all projects"
    tot <- rep_by(ca, c("group", "project_name"), fun); tot$tot <- 1L
    tab <- rbind(tab, tot)
    tab <- tab[rep_order(rep_group_rank(tab$group), tab$group, tab$tot, tab$project_name),
               setdiff(names(tab), "tot"), drop = FALSE]
    names(tab)[1:2] <- c("Group", "Project")
    c(rep_md_table(tab), "",
      rep_note("Source: `conditions.csv` (non-NEON plots with a cloud) and the group of ",
               "`plots.csv`."))
  }
  rep_block("Disturbance, snow and leaf-off by group and project", body)
}

rep_sec_conditions_held <- function(tabs) {
  req <- list(conditions.csv = c("plot_id", "project_name", "disturbance_status", "loss_share",
                                 "reverse_share", "snow_status", "snow_depth_max_m",
                                 "leafoff_status", "deciduous_share", "conditions_admitted",
                                 "conditions_reason", "survey_date", "flown_from",
                                 "mission_date", "interval_covered"),
              plots.csv = c("plot_id", "group"), flights.csv = c("plot_id", "flight_admitted"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    c0 <- tabs$conditions.csv
    c0$group <- rep_group_of(tabs$plots.csv, c0$plot_id)
    h <- c0[rep_lgl_of(c0$conditions_admitted) %in% FALSE & c0$group %in% c("A", "B", "D"), ,
            drop = FALSE]
    h <- h[rep_order(rep_group_rank(h$group), h$plot_id), , drop = FALSE]
    fl <- tabs$flights.csv
    c(rep_md_table(rep_df(
      Plot = h$plot_id, Project = h$project_name, Group = h$group,
      "Flight admitted" = rep_yes(fl$flight_admitted[match(h$plot_id, fl$plot_id)]),
      "Survey date" = h$survey_date, "Flight date" = h$flown_from,
      "Mission date" = h$mission_date, "Interval covered" = rep_yes(h$interval_covered),
      Disturbance = h$disturbance_status, "Loss share" = rep_pct(h$loss_share),
      "Reverse share" = rep_pct(h$reverse_share), Snow = h$snow_status,
      "Snow depth, mm (max)" = rep_int(1000 * rep_num_of(h$snow_depth_max_m)),
      "Leaf-off" = h$leafoff_status, "Deciduous share" = rep_pct(h$deciduous_share),
      Reason = h$conditions_reason), "No held plots in groups A, B and D."), "",
      rep_note("Source: `conditions.csv`; plots of groups A, B and D whose conditions ",
               "are not admitted. The survey date is the catalogue's representative date ",
               "(mid-month or 1 July where only a month or year is recorded); the flight ",
               "date is the first flight date (`flown_from`)."))
  }
  rep_block("Conditions: held plots of groups A, B and D", body)
}

# Which surface came first in the disturbance check, and how far the drone
# missions lie from survey and flight, in calendar years.
rep_sec_disturbance_order <- function(tabs) {
  req <- list(conditions.csv = c("plot_id", "disturbance_status", "mission_date",
                                 "early_surface", "survey_year", "flight_year"),
              plots.csv = c("plot_id", "group"), flights.csv = c("plot_id", "flight_admitted"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    c0 <- tabs$conditions.csv
    c0 <- c0[!rep_blank(c0$disturbance_status) & !c0$disturbance_status %in% "not_checked", ,
             drop = FALSE]
    g <- rep_group_of(tabs$plots.csv, c0$plot_id)
    fa <- rep_lgl_of(tabs$flights.csv$flight_admitted[match(c0$plot_id,
                                                              tabs$flights.csv$plot_id)]) %in% TRUE
    my <- rep_num_of(substr(c0$mission_date, 1, 4))
    row <- function(k, label) {
      after <- k & c0$early_surface %in% "3dep"
      rep_df(Set = label, "Plots checked" = rep_int(sum(k)),
             "3DEP flight earlier" = rep_int(sum(after)),
             "Drone mission earlier" = rep_int(sum(k & c0$early_surface %in% "drone")),
             "Mission year minus survey year" =
               rep_range(my[after] - rep_num_of(c0$survey_year[after]), rep_int),
             "Mission year minus flight year" =
               rep_range(my[after] - rep_num_of(c0$flight_year[after]), rep_int))
    }
    c(rep_md_table(rbind(row(rep(TRUE, nrow(c0)), "All checked plots"),
                         row(g %in% c("A", "B") & fa,
                             "Groups A and B with an admitted flight"))), "",
      rep_note("Source: `conditions.csv` (`early_surface`: the earlier of the 3DEP flight ",
               "and the drone mission), the group of `plots.csv` and `flights.csv`. Checked: ",
               "a usable drone model was compared. The year differences are over the plots ",
               "whose mission is after the flight, in calendar years."))
  }
  rep_block("Disturbance check: order of the surfaces", body)
}

## ---- 7. cells -------------------------------------------------------------------------

# Cells the protocol's tiling rule (ofo_cells()) admits in each grouped plot
# with an admitted flight, on its UNSHIFTED polygon: one row per plot with the
# cell count (NA when the polygon cannot be read) and the polygon area.
rep_cells_possible <- function(plots, flights) {
  p <- plots[!rep_blank(plots$group) & !plots$project_name %in% REP_NEON_PROJECT, , drop = FALSE]
  fa <- rep_lgl_of(flights$flight_admitted[match(p$plot_id, flights$plot_id)]) %in% TRUE
  p <- p[fa, , drop = FALSE]
  n <- vapply(seq_len(nrow(p)), function(i) tryCatch(
    nrow(ofo_cells(ofo_polygon(p$polygon_wkt[i], as.integer(p$epsg[i])))),
    error = function(e) NA_integer_), integer(1))
  data.frame(plot_id = p$plot_id, project_name = p$project_name, group = p$group,
             n_cells = n, area_m2 = rep_num_of(p$polygon_area_m2), stringsAsFactors = FALSE)
}

rep_sec_cells_possible <- function(tabs) {
  req <- list(plots.csv = c("plot_id", "project_name", "group", "epsg", "polygon_wkt",
                            "polygon_area_m2"),
              flights.csv = c("plot_id", "flight_admitted"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    x <- rep_cells_possible(tabs$plots.csv, tabs$flights.csv)
    fun <- function(r) rep_df(
      "Plots with an admitted flight" = rep_int(nrow(r)),
      "Plots that can hold a cell" = rep_int(sum(r$n_cells > 0, na.rm = TRUE)),
      Cells = rep_int(sum(r$n_cells, na.rm = TRUE)),
      "Plot polygon area, m² (range)" = rep_range(r$area_m2, rep_int))
    tab <- rep_by(x, c("group", "project_name"), fun)
    if (!is.null(tab)) {
      tab$tot <- 0L
      xa <- x; xa$project_name <- "all projects"
      tot <- rep_by(xa, c("group", "project_name"), fun); tot$tot <- 1L
      tab <- rbind(tab, tot)
      tab <- tab[rep_order(rep_group_rank(tab$group), tab$group, tab$tot, tab$project_name),
                 setdiff(names(tab), "tot"), drop = FALSE]
      names(tab)[1:2] <- c("Group", "Project")
    }
    bad <- sum(is.na(x$n_cells))
    c(rep_md_table(tab, "No grouped plot has an admitted flight."), "",
      rep_note(sprintf(paste("Source: `plots.csv` (unshifted polygon in the project frame) and",
                             "`flights.csv`. Indicative only: no plot is registered, so the",
                             "tiling rule of the protocol (%s m cells on a grid of %s m",
                             "offsets, at least %s inside the polygon) is applied with zero",
                             "shift; a registered plot's cells follow its shifted polygon."),
                       rep_int(OFO_CELL_SIZE), rep_int(OFO_CELL_STEP),
                       rep_pct(OFO_CELL_MIN_INSIDE, 0)),
               if (bad) sprintf(" %s polygon(s) could not be read and count no cell.",
                                rep_int(bad))))
  }
  rep_block("Scoring cells: plots that could hold a cell", body)
}

rep_sec_cells <- function(tabs) {
  req <- list(group_summary.csv = c("group", "project_name", "admitted", "cells",
                                    "headline_cells", "ref_plot", "ref_cells", "ref_headline",
                                    "area_plot_m2", "area_cells_m2"),
              cells.csv = c("plot_id", "project_name", "group", "cell_id", "headline"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    s <- tabs$group_summary.csv
    ce <- tabs$cells.csv
    all <- s$project_name %in% "ALL"
    s <- s[rep_order(rep_group_rank(s$group), s$group, all, s$project_name), , drop = FALSE]
    all <- s$project_name %in% "ALL"
    hd <- rep_lgl_of(ce$headline) %in% TRUE
    # The second protocol also places plots whose registration is only
    # unchecked, for its hold count; their cells are not cells of registered
    # plots and are shown apart.
    has_prov <- "provisional" %in% names(ce)
    prov <- if (has_prov) rep_lgl_of(ce$provisional) %in% TRUE else rep(FALSE, nrow(ce))
    of <- function(g, p) ce$group %in% g & (p %in% "ALL" | ce$project_name %in% p)
    reg_cells <- function(g, p, head) rep_int(sum(of(g, p) & !prov & (!head | hd)))
    prov_cells <- function(g, p, head) rep_int(sum(of(g, p) & prov & (!head | hd)))
    prov_stems <- function(g, p) rep_int(sum(rep_num_of(ce$n_ref)[of(g, p) & prov & hd]))
    ha <- function(v) rep_num(rep_num_of(v) / 1e4, 2)
    tab <- rep_df(
      Group = s$group, Project = ifelse(all, "all projects", s$project_name),
      "Plots admitted" = rep_int(s$admitted), Cells = rep_int(s$cells),
      "Headline cells" = rep_int(s$headline_cells),
      "Relaxed cells" = rep_int(rep_num_of(s$cells) - rep_num_of(s$headline_cells)),
      "Reference stems in plots" = rep_int(s$ref_plot),
      "In cells" = rep_int(s$ref_cells), "In headline cells" = rep_int(s$ref_headline),
      "Plot area, ha" = ha(s$area_plot_m2), "Cell area, ha" = ha(s$area_cells_m2),
      "Cells of registered plots" = mapply(reg_cells, s$group, s$project_name, FALSE),
      "Headline cells of registered plots" = mapply(reg_cells, s$group, s$project_name, TRUE))
    if (has_prov && "n_ref" %in% names(ce)) tab <- cbind(tab, rep_df(
      "Cells of provisionally placed plots" = mapply(prov_cells, s$group, s$project_name, FALSE),
      "Headline cells of provisionally placed plots" =
        mapply(prov_cells, s$group, s$project_name, TRUE),
      "Reference stems in those headline cells" = mapply(prov_stems, s$group, s$project_name)))
    c(rep_md_table(tab),
      "",
      rep_note("Source: `group_summary.csv` (admitted plots) and `cells.csv` (every cell ",
               "of a registered plot, admitted or not). Headline cells hold at least six ",
               "reference stems; the others form the relaxed population.",
               if (has_prov) paste0(
                 " Provisionally placed: plots whose registration failed only because ",
                 "the test of their signal could not be made, placed at the method's ",
                 "estimate so that the hold rule can count them. They are not ",
                 "registered and their cells are no reference. Plots among them ",
                 "that also fail a gate on evidence are counted here but not by ",
                 "the hold rule (`unchecked_only` in `plot_admission.csv`).")))
  }
  rep_block("Scoring cells and reference stems by group and project", body)
}

rep_sec_gates <- function(tabs) {
  req <- list(plot_admission.csv = c("plot_id", "group", "admitted"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    a <- tabs$plot_admission.csv
    nm <- names(a)
    gates <- if (match("admitted", nm) > match("group", nm) + 1)
      nm[(match("group", nm) + 1):(match("admitted", nm) - 1)] else character()
    if (!length(gates)) {
      "Not produced: `plot_admission.csv` has no gate columns between `group` and `admitted`."
    } else {
      a$g <- rep_group_label(a$group)
      gs <- unique(a$g); gs <- gs[rep_order(rep_group_rank(gs), gs)]
      rows <- list()
      for (g in c(gs, "all groups")) {
        x <- a[if (g == "all groups") a$g != REP_DASH else a$g == g, , drop = FALSE]
        left <- rep(TRUE, nrow(x))
        rows[[length(rows) + 1]] <- rep_df(Group = g, Step = "0", Gate = "plots",
                                           "Failing this gate, at any step" = REP_DASH,
                                           "Removed at this step" = REP_DASH,
                                           "Plots left" = rep_int(nrow(x)))
        for (i in seq_along(gates)) {
          pass <- rep_lgl_of(x[[gates[i]]]) %in% TRUE
          removed <- left & !pass
          left <- left & pass
          rows[[length(rows) + 1]] <- rep_df(Group = g, Step = as.character(i), Gate = gates[i],
                                             "Failing this gate, at any step" = rep_int(sum(!pass)),
                                             "Removed at this step" = rep_int(sum(removed)),
                                             "Plots left" = rep_int(sum(left)))
        }
        rows[[length(rows) + 1]] <- rep_df(Group = g, Step = REP_DASH, Gate = "admitted",
          "Failing this gate, at any step" = REP_DASH, "Removed at this step" = REP_DASH,
          "Plots left" = rep_int(sum(rep_lgl_of(x$admitted) %in% TRUE)))
      }
      c(rep_md_table(do.call(rbind, rows)), "",
        rep_note("Source: `plot_admission.csv`, gates in the file's column order. ",
                 "\"Failing this gate, at any step\" counts every plot failing that gate; ",
                 "\"Removed at this step\" counts plots that passed every earlier gate and ",
                 "fail this one; \"left\" counts plots passing it and every earlier gate. ",
                 "The ungrouped row (", REP_DASH, ") holds the screened-out plots; ",
                 "\"all groups\" excludes them."))
    }
  }
  rep_block("What each gate costs", body)
}

## ---- 8. state lidar -------------------------------------------------------------------

rep_sec_state_lidar <- function(tabs) {
  req <- list(state_lidar.csv = c("plot_id", "project_name", "source", "collection",
                                  "acquisition_years", "density_or_ql", "coverage",
                                  "verified", "survey_year"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    s <- tabs$state_lidar.csv
    s <- s[rep_order(s$plot_id, s$source, s$collection), , drop = FALSE]
    v <- rep_lgl_of(s$verified)
    c(rep_md_table(rep_df(
      Plot = s$plot_id, Project = s$project_name, "Survey year" = rep_year(s$survey_year),
      Source = s$source, Collection = s$collection,
      Years = gsub(";", ", ", s$acquisition_years, fixed = TRUE),
      "Density or quality level" = s$density_or_ql, Coverage = s$coverage,
      Status = ifelse(is.na(v), REP_DASH, ifelse(v, "verified", "lead")))), "",
      rep_note("Source: `state_lidar.csv` (metadata only; no point cloud acquired). ",
               "\"Verified\": coverage checked against the source's own footprint or tile ",
               "index; \"lead\": listed but not confirmed."))
  }
  rep_block("Plots outside the public 3DEP clouds", body)
}

# One row per plot: the verified collections with an acquisition year within
# `gap` years of the survey, by source, and how many other candidates there are.
rep_sec_state_lidar_digest <- function(tabs, gap = 4) {
  req <- list(state_lidar.csv = c("plot_id", "project_name", "source", "collection",
                                  "acquisition_years", "verified", "survey_year"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    s <- tabs$state_lidar.csv
    s <- s[rep_order(s$plot_id, s$source, s$collection), , drop = FALSE]
    yrs <- lapply(strsplit(as.character(s$acquisition_years), ";", fixed = TRUE), rep_num_of)
    sy <- rep_num_of(s$survey_year)
    s$near <- rep_lgl_of(s$verified) %in% TRUE & vapply(seq_along(yrs), function(i)
      any(is.finite(yrs[[i]]) & abs(yrs[[i]] - sy[i]) <= gap), logical(1))
    s$label <- sprintf("%s (%s)", s$collection, gsub(";", ", ", s$acquisition_years, fixed = TRUE))
    src <- c(usgs_3dep_lpc = "USGS tiles without an Entwine resource", wa_dnr = "Washington DNR",
             or_dogami = "Oregon DOGAMI", noaa_dc = "NOAA Digital Coast")
    tab <- rep_by(s, c("plot_id", "project_name"), function(x) {
      cols <- lapply(names(src), function(k) {
        l <- x$label[x$near & x$source == k]
        if (length(l)) paste(l, collapse = "; ") else REP_DASH
      })
      names(cols) <- unname(src)
      cbind(rep_df("Survey year" = rep_year(x$survey_year[1])),
            as.data.frame(cols, check.names = FALSE, stringsAsFactors = FALSE),
            rep_df("Other candidates" = rep_int(sum(!x$near))))
    })
    tab <- tab[rep_order(tab$plot_id), , drop = FALSE]
    names(tab)[1:2] <- c("Plot", "Project")
    c(rep_md_table(tab), "",
      rep_note(sprintf(paste("Source: `state_lidar.csv`. Listed: collections whose coverage of",
                             "the plot was verified and that have an acquisition year within %d",
                             "years of the survey. Other candidates: older, newer or unverified",
                             "collections."), gap)))
  }
  rep_block("Plots outside the public 3DEP clouds: collections near the survey year", body)
}

## ---- 9. licences ----------------------------------------------------------------------

# Citation a licence text asks for, or NA: the text after "please use the
# following citation:", the attribution entity, or what follows a leading
# "<licence>;".
rep_citation <- function(license, license_short = NA) {
  vapply(seq_along(license), function(i) {
    t <- trimws(as.character(license[i]))
    if (rep_blank(t)) return(NA_character_)
    m <- regexpr("following citation:\\s*", t, ignore.case = TRUE)
    if (m > 0) return(trimws(substring(t, m + attr(m, "match.length"))))
    m <- regexpr("entity to acknowledge for dataset attribution is\\s*", t, ignore.case = TRUE)
    if (m > 0) return(paste("Acknowledge", trimws(substring(t, m + attr(m, "match.length")))))
    ls <- trimws(as.character(rep_len(license_short, length(license))[i]))
    if (!rep_blank(ls) && startsWith(t, paste0(ls, ";")))
      return(trimws(substring(t, nchar(ls) + 2)))
    NA_character_
  }, character(1))
}

rep_sec_licences <- function(tabs) {
  req <- list(licences.csv = c("plot_id", "project_name", "license_short", "license",
                               "investigator_names", "withhold_from_training",
                               "redistribute_reference"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    l <- tabs$licences.csv
    red_text <- function(v) {
      v <- rep_lgl_of(v)
      if (all(v %in% TRUE)) "yes" else if (all(v %in% FALSE)) "no"
      else sprintf("%s of %s plots", rep_int(sum(v %in% TRUE)), rep_int(length(v)))
    }
    row <- function(x, label, total = FALSE)
      rep_df(Project = label, Plots = rep_int(nrow(x)),
             Licence = if (total) rep_tally(x$license_short) else rep_uniq(x$license_short, "; "),
             Contributors = if (total) REP_DASH else rep_uniq(x$investigator_names, "; "),
             "Required citation" = if (total) REP_DASH
               else rep_uniq(rep_citation(x$license, x$license_short), " / "),
             "Withheld from training" =
               rep_int(sum(rep_lgl_of(x$withhold_from_training) %in% TRUE)),
             "Reference tables redistributable" = red_text(x$redistribute_reference))
    projs <- sort(unique(l$project_name), method = "radix")
    rows <- c(lapply(projs, function(k) row(l[l$project_name %in% k, ], k)),
              list(row(l[!l$project_name %in% REP_NEON_PROJECT, ], "All non-NEON projects",
                       TRUE),
                   row(l, "Whole catalogue", TRUE)))
    c(rep_md_table(do.call(rbind, rows)), "",
      rep_note("Source: `licences.csv`. The citation is quoted from the licence text ",
               "where it names one. Redistributable: CC BY 4.0, CC0 1.0 or public domain; ",
               "otherwise the archive holds shifts, cells and tree identifiers only."))
  }
  rep_block("Licences by project", body)
}

## ---- 10. appendix ---------------------------------------------------------------------

# Failed gates of one plot_admission row with each gate's own reason.
rep_gate_reasons <- function(a) {
  sub_col <- c(screen_ok = "screen", flight_admitted = "flight_reason",
               conditions_admitted = "conditions_reason", registered = "registration_reason")
  vapply(seq_len(nrow(a)), function(i) {
    g <- strsplit(as.character(a$reason[i]), ";", fixed = TRUE)[[1]]
    g <- g[nzchar(g) & !is.na(g)]
    if (!length(g)) return(REP_DASH)
    paste(vapply(g, function(k) {
      col <- sub_col[k]
      why <- if (!is.na(col) && col %in% names(a)) a[[col]][i] else NA
      if (rep_blank(why)) k else sprintf("%s (%s)", k, why)
    }, character(1)), collapse = "; ")
  }, character(1))
}

rep_sec_appendix <- function(tabs) {
  req <- list(plots.csv = c("plot_id", "project_name", "contributor_plot_id", "screen", "group",
                            "survey_year", "plot_area_ha", "license_short"),
              flights.csv = c("plot_id", "ept", "ql", "flown_from", "flown_to", "gap_years",
                              "dens_all", "dens_first"))
  msg <- rep_need(tabs, req)
  body <- if (!is.null(msg)) msg else {
    p <- tabs$plots.csv
    p <- p[!p$project_name %in% REP_NEON_PROJECT, , drop = FALSE]
    p <- p[rep_order(p$plot_id), , drop = FALSE]
    f <- tabs$flights.csv[match(p$plot_id, tabs$flights.csv$plot_id), , drop = FALSE]
    wu <- if ("workunit" %in% names(f)) f$workunit else f$ept
    dates <- ifelse(rep_blank(f$flown_from), REP_DASH,
                    ifelse(rep_blank(f$flown_to) | f$flown_to == f$flown_from, f$flown_from,
                           paste(f$flown_from, "to", f$flown_to)))
    notes <- character()
    r <- tabs$registration.csv
    r_need <- rep_need(tabs, list(registration.csv = c("plot_id", "registered", "shift_m",
                                                       "residual_m")))
    shift <- resid <- rep(NA, nrow(p))
    if (is.null(r_need)) {
      m <- match(p$plot_id, r$plot_id)
      reg <- rep_lgl_of(r$registered[m]) %in% TRUE
      shift[reg] <- r$shift_m[m][reg]; resid[reg] <- r$residual_m[m][reg]
    } else notes <- c(notes, sub("^Not produced", "Shift and residual not filled", r_need))
    a <- tabs$plot_admission.csv
    a_need <- rep_need(tabs, list(plot_admission.csv = c("plot_id", "admitted", "reason")))
    adm <- why <- rep(REP_DASH, nrow(p))
    if (is.null(a_need)) {
      a <- a[match(p$plot_id, a$plot_id), , drop = FALSE]
      adm <- rep_yes(a$admitted)
      why <- rep_gate_reasons(a)
    } else notes <- c(notes, sub("^Not produced", "Admission not filled", a_need))
    c(rep_md_table(rep_df(
      Plot = p$plot_id, Project = p$project_name, "Contributor plot ID" = p$contributor_plot_id,
      "Group or screen" = ifelse(rep_blank(p$group), p$screen, p$group),
      "Survey year" = rep_year(p$survey_year), "Area, ha" = rep_num(p$plot_area_ha, 2),
      "Work unit" = wu, QL = f$ql, "Flight date(s)" = dates, "Gap, years" = rep_int(f$gap_years),
      "All returns per m²" = rep_num(f$dens_all), "First returns per m²" = rep_num(f$dens_first),
      Licence = p$license_short, "Shift, m" = rep_num(shift), "Residual, m" = rep_num(resid),
      Admitted = adm, Reason = why)), "",
      rep_note("Source: `plots.csv`, `flights.csv` (selected flight), `registration.csv` ",
               "(shift and residual of registered plots only) and `plot_admission.csv` ",
               "(failed gates, each with its own reason)."), notes)
  }
  rep_block("Appendix: every non-NEON plot", body)
}

## ---- document and headline numbers -------------------------------------------------

rep_sec_inputs <- function(info) {
  if (is.null(info)) return("Not recorded.")
  rep_md_table(rep_df(File = info$file, Rows = rep_int(info$rows),
                      "Modified (UTC)" = info$mtime, MD5 = info$md5))
}

rep_document <- function(tabs, info = NULL) {
  c("# OFO preflight: report tables", "",
    rep_note("Generated by `scripts/report_ofo_preflight.R` from the stage outputs ",
             "under `<job>/ofo/preflight`. Every number below is computed from those ",
             "files; a table whose input is missing says so."), "",
    "## 1. Decision", "", rep_sec_decision(tabs),
    "## 2. Catalogue", "", rep_sec_catalogue(tabs), rep_sec_groups(tabs),
    "## 3. Flights", "", rep_sec_flights(tabs),
    "## 4. Geometry", "", rep_sec_geometry(tabs),
    "## 5. Registration", "", rep_sec_known_truth(tabs), rep_sec_known_truth_detail(tabs),
    rep_sec_known_truth_sites(tabs), rep_sec_known_truth_stems(tabs), rep_sec_amendment(tabs),
    rep_sec_dev_variants(tabs), rep_sec_dev_frozen(tabs), rep_sec_confirmation(tabs),
    rep_sec_catalog_registration(tabs), rep_sec_agreement(tabs), rep_sec_candidates(tabs),
    rep_sec_heldout(tabs),
    "## 6. Disturbance, snow and leaf-off", "", rep_sec_conditions(tabs),
    rep_sec_conditions_held(tabs), rep_sec_disturbance_order(tabs),
    "## 7. Scoring cells", "", rep_sec_cells_possible(tabs), rep_sec_cells(tabs),
    rep_sec_gates(tabs),
    "## 8. Plots outside the public 3DEP clouds", "", rep_sec_state_lidar_digest(tabs),
    rep_sec_state_lidar(tabs),
    "## 9. Licences", "", rep_sec_licences(tabs),
    "## 10. Appendix", "", rep_sec_appendix(tabs),
    "## Inputs", "", rep_sec_inputs(info))
}

# Numbers the lead quotes, one "label: value" line each.
rep_headlines <- function(tabs) {
  p <- tabs$plots.csv; f <- tabs$flights.csv
  na <- function(file) sprintf("n/a (%s missing)", file)
  by_group <- function(g, v) {
    g <- rep_group_label(g)
    gs <- unique(g); gs <- gs[rep_order(rep_group_rank(gs), gs)]
    paste(sprintf("%s %s", ifelse(gs == REP_DASH, "no group", gs),
                  vapply(gs, function(k) rep_int(sum(v[g == k])), character(1))),
          collapse = ", ")
  }
  out <- c(
    "Catalogue plots" = if (is.null(p)) na("plots.csv") else rep_int(nrow(p)),
    "Catalogue trees" = if (is.null(p)) na("plots.csv")
                        else rep_int(sum(rep_num_of(p$n_trees), na.rm = TRUE)),
    "Non-NEON plots" = if (is.null(p)) na("plots.csv")
                       else rep_int(sum(!p$project_name %in% REP_NEON_PROJECT)),
    "Screened in, by group" = if (is.null(p)) na("plots.csv")
      else { q <- p[!rep_blank(p$group), ]; by_group(q$group, rep(TRUE, nrow(q))) },
    "Plots with a 3DEP candidate" = if (is.null(f)) na("flights.csv")
      else rep_int(sum(rep_num_of(f$n_candidates) > 0, na.rm = TRUE)),
    "Plots with a cloud" = if (is.null(f)) na("flights.csv")
      else rep_int(sum(f$cloud_status %in% "ok")),
    "Admitted flights" = if (is.null(f)) na("flights.csv")
      else rep_int(sum(rep_lgl_of(f$flight_admitted) %in% TRUE)),
    "Admitted flights by group" = if (is.null(f) || is.null(p)) na("flights.csv or plots.csv")
      else by_group(rep_group_of(p, f$plot_id), rep_lgl_of(f$flight_admitted) %in% TRUE))
  if (is.null(f)) {
    out["Admitted flights: densities"] <- na("flights.csv")
  } else {
    fa <- rep_lgl_of(f$flight_admitted) %in% TRUE
    da <- rep_num_of(f$dens_all[fa]); df <- rep_num_of(f$dens_first[fa])
    out["Admitted flights: median returns per m², all and first"] <-
      sprintf("%s and %s", rep_median(da), rep_median(df))
    out["Admitted flights: median returns per m² counting withheld returns"] <-
      if (all(c("n_points_polygon_raw", "polygon_area_m2") %in% names(f)))
        rep_median(rep_num_of(f$n_points_polygon_raw[fa]) / rep_num_of(f$polygon_area_m2[fa]))
      else "n/a (flights.csv lacks n_points_polygon_raw)"
    out[sprintf("Admitted flights below %s returns per m², all and first",
                rep_int(REP_LOW_DENS))] <-
      sprintf("%s and %s", rep_int(sum(da < REP_LOW_DENS, na.rm = TRUE)),
              rep_int(sum(df < REP_LOW_DENS, na.rm = TRUE)))
  }
  js <- tabs[[REP_TESTS]]
  adm <- rep_json_get(js, "admitted")
  out["Signals admitted"] <- if (is.null(adm)) na(REP_TESTS)
    else paste(sprintf("%s %s", names(adm), vapply(adm, function(v) rep_yes(v), character(1))),
               collapse = ", ")
  r <- tabs$registration.csv
  out["Registered candidate plots by group"] <- if (is.null(r)) na("registration.csv")
    else by_group(r$group, rep_lgl_of(r$registered) %in% TRUE)
  cnd <- tabs$conditions.csv
  out["Conditions admitted"] <- if (is.null(cnd)) na("conditions.csv")
    else sprintf("%s of %s plots with a cloud",
                 rep_int(sum(rep_lgl_of(cnd$conditions_admitted) %in% TRUE)), rep_int(nrow(cnd)))
  a <- tabs$plot_admission.csv
  out["Plots admitted by group"] <- if (is.null(a)) na("plot_admission.csv")
    else by_group(a$group, rep_lgl_of(a$admitted) %in% TRUE)
  d <- tabs$group_decision.csv
  out["Decisions"] <- if (is.null(d)) na("group_decision.csv")
    else paste(sprintf("%s %s", d$group, d$decision)[rep_order(rep_group_rank(d$group))],
               collapse = ", ")
  sprintf("%s: %s", names(out), out)
}

## ---- I/O (driver only) -------------------------------------------------------------

# The OUT guard: one markdown file, under OFO or outside the job directory,
# never elsewhere in it (so never in the NEON root). Relative paths resolve
# against the working directory, `..` is refused and the deepest existing
# ancestor is resolved through symlinks (ofo_output_allowed()). Stops or
# returns TRUE.
rep_check_out <- function(out, job, ofo) {
  if (length(out) != 1L || is.na(out) || !grepl("\\.md$", out))
    stop("OUT must be a .md file: ", out, call. = FALSE)
  if (!ofo_output_allowed(out, job, ofo))
    stop("OUT must lie under ", ofo, " or outside the job directory (no `..`): ", out,
         call. = FALSE)
  invisible(TRUE)
}

rep_read_csv <- function(path) {
  if (!file.exists(path)) return(NULL)
  as.data.frame(data.table::fread(path, colClasses = "character", na.strings = c("", "NA"),
                                  showProgress = FALSE, encoding = "UTF-8"),
                stringsAsFactors = FALSE)
}

rep_load <- function(pre, pnw_path) {
  amend <- list.files(pre, pattern = REP_AMEND_CSV)
  files <- unique(c(REP_CSV, sort(amend, method = "radix")))
  tabs <- stats::setNames(lapply(file.path(pre, files), rep_read_csv), files)
  tp <- file.path(pre, REP_TESTS)
  tabs[REP_TESTS] <- list(if (file.exists(tp))
    tryCatch(jsonlite::read_json(tp, simplifyVector = FALSE), error = function(e) NULL))
  tabs[REP_PNW] <- list(if (file.exists(pnw_path)) readLines(pnw_path, warn = FALSE,
                                                             encoding = "UTF-8"))
  paths <- c(file.path(pre, c(files, REP_TESTS)), pnw_path)
  ex <- file.exists(paths)
  info <- data.frame(
    file = c(files, REP_TESTS, file.path("results", REP_PNW)),
    rows = c(vapply(files, function(f) if (is.null(tabs[[f]])) NA_real_ else nrow(tabs[[f]]),
                    numeric(1)), NA, NA),
    mtime = ifelse(ex, format(file.mtime(paths), "%Y-%m-%d %H:%M:%S", tz = "UTC"), "missing"),
    md5 = ifelse(ex, unname(tools::md5sum(paths)), REP_DASH),
    stringsAsFactors = FALSE)
  list(tabs = tabs, info = info)
}

rep_main <- function(args = commandArgs(TRUE)) {
  a <- strsplit(args, "=", fixed = TRUE)
  A <- stats::setNames(lapply(a, function(x) paste(x[-1], collapse = "=")),
                       vapply(a, `[`, character(1), 1))
  unknown <- setdiff(names(A), "OUT")
  if (length(unknown)) stop("Unknown argument(s): ", paste(unknown, collapse = ", "),
                            "; report_ofo_preflight.R takes only OUT=", call. = FALSE)
  job <- normalizePath(.job_dir(), mustWork = FALSE)
  pre <- file.path(job, "ofo", "preflight")
  out <- if (is.null(A$OUT) || !nzchar(A$OUT)) file.path(pre, "report_tables.md") else A$OUT
  rep_check_out(out, job, file.path(job, "ofo"))
  out_n <- ofo_path_resolve(out)
  ld <- rep_load(pre, file.path(.ROOT, "results", REP_PNW))
  doc <- rep_document(ld$tabs, ld$info)
  dir.create(dirname(out_n), recursive = TRUE, showWarnings = FALSE)
  writeLines(doc, out_n, useBytes = TRUE)
  # A skip note is the paragraph that starts with one of these phrases.
  first <- grep(paste0("^(Not produced|NEON comparison not added|",
                       "Shift and residual not filled|Admission not filled)"), doc)
  skipped <- vapply(first, function(i) {
    j <- i
    while (j < length(doc) && nzchar(doc[j + 1]) && !startsWith(doc[j + 1], "#")) j <- j + 1
    paste(doc[i:j], collapse = " ")
  }, character(1))
  cat(sprintf("wrote %s (%d lines, %d tables)\n", out_n, length(doc),
              sum(grepl("^\\| --- ", doc))))
  cat("\nheadline numbers:\n")
  cat(paste0("  ", rep_headlines(ld$tabs), "\n"), sep = "")
  if (length(skipped)) {
    cat("\nsections with missing inputs:\n")
    hi <- grep("^### ", doc)
    hit <- vapply(first, function(i) {
      h <- hi[hi < i]
      if (!length(h)) "" else sub("^### ", "", doc[max(h)])
    }, character(1))
    cat(sprintf("  %s: %s\n", hit, skipped), sep = "")
  }
  invisible(out_n)
}

if (sys.nframe() == 0L) rep_main()
