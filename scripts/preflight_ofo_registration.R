#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(data.table); library(parallel) })
source(.find("model_bench_lib.R"))
source(.find("ofo_registration_lib.R"))
source(.find("ofo_preflight_lib.R"))   # kept-return filter and stage records

# Registration stage of the Open Forest Observatory preflight
# (docs/ofo-preflight-protocol.md, "Registration" and its three tests).
# Score-blind: no detector runs; each plot gets one rigid shift from the
# agreement of its stem map with the canopy top of its flight.
#   STAGE=neon     test 1 (known truth) on the benchmark's adopted NEON plots:
#                  stems displaced by a seeded offset are registered against
#                  their native clips in the sealed root, read-only.
#                  Inputs: <job>/neon/frozen_2021, <job>/neon/<SITE>/
#                  ground_truth_stems.csv. Outputs: <job>/ofo/preflight/
#                  registration_neon.csv, registration_tests.json (test 1),
#                  neon_untouched.json (proof that <job>/neon did not change).
#   STAGE=catalog  tests 2 and 3 and the candidate registrations, from the
#                  catalog stage's plots.csv, trees.csv, flights.csv,
#                  clouds.csv and clouds/<plot_id>.laz under <job>/ofo (kept
#                  returns: classes 7 and 18 and withheld returns dropped; the
#                  NEON clips are read as before).
#                  Outputs: registration_catalog.csv, registration.csv, the
#                  complete registration_tests.json and
#                  registration_catalog_record.json (SHA-256 of the tables read
#                  and written). Needs STAGE=neon first.
#   STAGE=all      both, in that order.
# Amendment 1 (registration redesign; method 2, constants OFO_REG2 in the lib):
#   STAGE=dev      the development harness. Splits the 106 known-truth plots,
#                  forms the composites and writes registration_units.csv
#                  (both halves, stem counts only), then runs every method-2
#                  variant on the DEVELOPMENT plots and composites alone:
#                  registration_dev.csv, registration_dev_summary.csv,
#                  registration_dev_gates.csv (gate sweep and selection rule),
#                  registration_dev_equivariance.csv,
#                  registration_dev_selection.json, neon_untouched_dev.json.
#                  No confirmation unit is loaded.
#   STAGE=confirm  the one confirmation run of the frozen method on the
#                  confirmation plots and composites. Needs CONFIRM=YES and
#                  refuses to run when registration_confirm.csv exists, or
#                  unless the protocol holds Amendment 1b quoting the
#                  method-2 digest (ofo2_config_digest(), printed by
#                  STAGE=dev). Also writes neon_untouched_confirm.json.
#                  Writes registration_confirm.csv and the amendment block of
#                  registration_tests.json (the declared content moves, as it
#                  is, under "declared").
#   STAGE=catalog  once the amendment block exists: catalogue plots are
#                  registered with method 2 (rows with method "amendment1";
#                  earlier declared rows are kept, method "declared"); test 3
#                  is recomputed with method 2 and the top-level `admitted`
#                  holds the final admission. DECLARED=TRUE also recomputes the
#                  declared rows and block from the current inputs.
# Results do not depend on CORES: every random draw is seeded per plot or unit.
#   Rscript scripts/preflight_ofo_registration.R STAGE=neon|catalog|all|dev [CORES=8]
#   Rscript scripts/preflight_ofo_registration.R STAGE=confirm CONFIRM=YES [CORES=8]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
STAGE <- if (is.null(A$STAGE)) "all" else A$STAGE
if (!STAGE %in% c("neon", "catalog", "all", "dev", "confirm"))
  stop("STAGE must be neon, catalog, all, dev or confirm")
CORES <- as.integer(if (is.null(A$CORES)) 8 else A$CORES)
d <- .job_dir()
OFO <- file.path(d, "ofo")
PRE <- file.path(OFO, "preflight")
NEON_SITES <- c("ABBY", "SJER", "SOAP", "TEAK", "WREF")
GRID <- ofo_shift_grid()
OFFSET_MAX <- 8          # test 1: known offset uniform within +/-8 m per axis
options(lidR.progress = FALSE)

# readLAS writes a progress line to stdout; keep the log readable. The NEON
# clips are read with no filter (as in tests 1 and Amendment 1); catalogue
# clouds with the kept-return filter (ofo_read_las()).
read_las <- function(f, select) {
  las <- NULL
  invisible(utils::capture.output(las <- lidR::readLAS(f, select = select)))
  las
}

write_json_file <- function(x, path)
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null",
                       null = "null")

# Runs f over xs in forked workers; a failed worker stops the run.
par_map <- function(xs, f) {
  out <- mclapply(xs, f, mc.cores = CORES, mc.preschedule = FALSE)
  bad <- vapply(out, inherits, logical(1), "try-error")
  if (any(bad)) stop("Worker failed: ", as.character(out[[which(bad)[1]]]))
  out
}

registration_tests_path <- file.path(PRE, "registration_tests.json")
read_tests <- function()
  if (file.exists(registration_tests_path)) jsonlite::read_json(registration_tests_path) else NULL
# The amendment block exists once STAGE=confirm has written its results.
has_amendment <- function(tests) !is.null(tests$amendment1$confirmation)
method_record <- function()
  list(protocol = "docs/ofo-preflight-protocol.md (Registration)",
       method = OFO_REG, pass_rules = OFO_TESTS,
       shifts = nrow(GRID), created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))

## ---- evidence that <job>/neon is untouched -----------------------------------
neon_snapshot <- function() {
  root <- file.path(d, "neon", "frozen_2021")
  rel <- sort(list.files(root, recursive = TRUE, all.files = TRUE, include.dirs = TRUE,
                         no.. = TRUE))
  info <- file.info(file.path(root, rel))
  listing <- data.frame(path = file.path("neon", "frozen_2021", rel), size = info$size,
                        mtime = sprintf("%.6f", as.numeric(info$mtime)),
                        stringsAsFactors = FALSE)
  gt_rel <- file.path("neon", NEON_SITES, "ground_truth_stems.csv")
  gi <- file.info(file.path(d, gt_rel))
  gt <- data.frame(path = gt_rel, size = gi$size, mtime = sprintf("%.6f", as.numeric(gi$mtime)),
                   sha256 = vapply(file.path(d, gt_rel), frozen_sha256, character(1),
                                   USE.NAMES = FALSE),
                   stringsAsFactors = FALSE)
  list(clip_manifest_sha256 = frozen_sha256(file.path(root, "clip_manifest.csv")),
       listing = listing, ground_truth = gt)
}

listing_digest <- function(l)
  digest::digest(paste(l$path, l$size, l$mtime, sep = "\t", collapse = "\n"),
                 algo = "sha256", serialize = FALSE)

neon_evidence <- function(before, after, stage = "neon") {
  same <- identical(before, after)
  list(checked_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
       stage = stage, identical = same,
       clip_manifest_sha256 = list(before = before$clip_manifest_sha256,
                                   after = after$clip_manifest_sha256),
       frozen_root_listing = list(
         root = "neon/frozen_2021", fields = "path, size, mtime (recursive, with directories)",
         n_entries_before = nrow(before$listing), n_entries_after = nrow(after$listing),
         sha256_before = listing_digest(before$listing),
         sha256_after = listing_digest(after$listing)),
       ground_truth_before = before$ground_truth,
       ground_truth_after = after$ground_truth)
}

## ---- STAGE=neon: test 1 (known truth) --------------------------------------------
neon_rows <- function(site, plot, plot_type, off, signal, n, reg, height_floor) {
  reg$error_m <- sqrt((reg$dx + off[1])^2 + (reg$dy + off[2])^2)
  cbind(data.frame(site = site, plot = plot, stringsAsFactors = FALSE),
        reg[, c("signal", "n_signal")],
        data.frame(offset_dx = off[1], offset_dy = off[2]),
        reg[, c("dx", "dy", "shift_m", "objective_zero", "objective_best",
                "objective_median", "contrast", "residual_m", "on_edge", "accepted",
                "reject_reason", "error_m")],
        data.frame(plot_type = plot_type, n_live = n, height_floor_m = height_floor))
}

neon_plot <- function(row, gt, root, manifest) {
  site <- row$site; plot <- row$plotID
  set.seed(seed_for("offset", plot, NA))
  off <- stats::runif(2, -OFFSET_MAX, OFFSET_MAX)
  st <- gt[gt$plotID == plot & gt$live %in% TRUE & gt$is_tree %in% TRUE &
             is.finite(gt$E) & is.finite(gt$N), , drop = FALSE]
  # Height signal from stems with a height; rank signal from the adopted gate
  # (live trees of 10 cm DBH or more), heights ignored.
  sel <- list(height = ofo_height_stems(rep(TRUE, nrow(st)), st$height),
              rank = !is.na(st$stemDiameter) & st$stemDiameter >= OFO_REG$dbh_floor)
  size <- list(height = st$height, rank = st$stemDiameter)
  hm <- st$height[is.finite(st$height)]
  hfloor <- if (length(hm)) max(OFO_REG$height_floor, stats::median(hm)) else NA_real_
  cell <- frozen_read(root, site, plot, NA, row$easting, row$northing, row$core_half,
                      manifest = manifest)
  M <- if (!is.null(cell)) ofo_canopy_top(read_las(cell$normalized, "xyz"))
  x <- st$E + off[1]; y <- st$N + off[2]
  do.call(rbind, lapply(c("height", "rank"), function(s) {
    k <- sel[[s]]
    reg <- if (is.null(M)) {
      r <- ofo_register(matrix(0, 0, nrow(GRID)), numeric(), GRID, s, plot)
      r$n_signal <- sum(k); r$reject_reason <- "no_clip"; r
    } else ofo_register(ofo_signal_matrix(M, x[k], y[k], GRID), size[[s]][k], GRID, s, plot)
    neon_rows(site, plot, row$plotType, off, s, nrow(st), reg,
              if (s == "height") hfloor else NA_real_)
  }))
}

neon_summaries <- function(res) {
  run <- res[res$n_signal >= OFO_REG$min_stems & is.finite(res$error_m), ]
  q <- function(x, p) if (length(x)) unname(stats::quantile(x, p)) else NA_real_
  summ <- function(x) data.frame(n = nrow(x), median_error_m = q(x$error_m, 0.5),
                                 p90_error_m = q(x$error_m, 0.9),
                                 n_within_2m = sum(x$error_m <= 2),
                                 max_error_m = if (nrow(x)) max(x$error_m) else NA_real_)
  by_acc <- do.call(rbind, lapply(split(run, list(run$signal, run$accepted), drop = TRUE),
                                  function(x) cbind(signal = x$signal[1],
                                                    accepted = x$accepted[1], summ(x))))
  run$stems <- cut(run$n_signal, c(14, 29, 59, Inf), labels = c("15-29", "30-59", "60+"))
  by_n <- do.call(rbind, lapply(split(run, list(run$signal, run$stems), drop = TRUE),
                                function(x) {
                                  a <- x[x$accepted, ]
                                  data.frame(signal = x$signal[1], stems = x$stems[1],
                                             n_run = nrow(x), n_accepted = nrow(a),
                                             median_error_all_m = q(x$error_m, 0.5),
                                             median_error_accepted_m = q(a$error_m, 0.5))
                                }))
  reasons <- as.data.frame(table(signal = res$signal,
                                 reason = ifelse(res$accepted, "(accepted)", res$reject_reason)),
                           stringsAsFactors = FALSE)
  list(by_accepted = by_acc[order(by_acc$signal, by_acc$accepted), ],
       by_stem_count = by_n[order(by_n$signal, by_n$stems), ],
       reasons = reasons[reasons$Freq > 0, ])
}

stage_neon <- function() {
  root <- frozen_root(d)
  if (!frozen_sealed(root)) stop("No sealed frozen root at ", root)
  dir.create(PRE, recursive = TRUE, showWarnings = FALSE)
  before <- neon_snapshot()
  manifest <- frozen_clip_manifest(root)
  pop <- do.call(rbind, lapply(NEON_SITES, function(s) frozen_population(root, s, "adopted")))
  gts <- setNames(lapply(NEON_SITES, function(s)
    read.csv(file.path(d, "neon", s, "ground_truth_stems.csv"), stringsAsFactors = FALSE)),
    NEON_SITES)
  message(sprintf("STAGE=neon: %d adopted plots, %d cores", nrow(pop), CORES))
  rows <- par_map(seq_len(nrow(pop)), function(i)
    neon_plot(pop[i, ], gts[[pop$site[i]]], root, manifest))
  res <- do.call(rbind, rows)
  res <- res[order(res$site, res$plot, match(res$signal, c("height", "rank"))), ]
  rownames(res) <- NULL
  after <- neon_snapshot()
  ev <- neon_evidence(before, after)
  write_json_file(ev, file.path(PRE, "neon_untouched.json"))
  if (!isTRUE(ev$identical)) stop("<job>/neon changed during the run; see neon_untouched.json")
  fwrite(res, file.path(PRE, "registration_neon.csv"))
  t1 <- ofo_known_truth_test(res)
  sm <- neon_summaries(res)
  declared <- c(method_record(), list(
    status = "test 1 only; tests 2 and 3 and the admitted signals need STAGE=catalog",
    frozen_root_clip_manifest_sha256 = before$clip_manifest_sha256,
    test1_known_truth = c(list(
      population = "adopted", n_plots = nrow(pop),
      offset = "set.seed(seed_for('offset', plot, NA)); runif(2, -8, 8)",
      error = "distance between the estimate and the shift that undoes the offset"),
      t1, list(by_accepted = sm$by_accepted, by_stem_count = sm$by_stem_count,
               reasons = sm$reasons)),
    test2_heldout = NULL, test3_agreement = NULL, admitted = NULL))
  # Once Amendment 1 has run, the declared content lives under "declared": only
  # its test-1 part is replaced (test 1 is deterministic on the sealed root, so
  # the declared tests 2 and 3 stay valid) and the amendment block is kept.
  tests <- read_tests()
  if (has_amendment(tests)) {
    keep <- c("status", "test2_heldout", "test3_agreement", "admitted")
    old <- tests$declared
    for (k in keep) if (!is.null(old[[k]])) declared[k] <- list(old[[k]])
    tests$declared <- declared
    write_json_file(tests, registration_tests_path)
  } else write_json_file(declared, registration_tests_path)
  print_neon(res, t1, sm)
  invisible(res)
}

print_neon <- function(res, t1, sm) {
  cat("\nTest 1 (known truth), per signal:\n")
  for (s in names(t1)) with(t1[[s]], cat(sprintf(
    "  %-6s plots %d, run %d, accepted %d, median error %.3f m, within 2 m %d (%.1f%%): %s\n",
    s, n_plots, n_run, n_accepted, median_error_m, n_within_2m, 100 * share_within_2m,
    if (pass) "PASS" else "FAIL")))
  cat("\nErrors by signal and acceptance (plots with >= 15 signal stems):\n")
  print(sm$by_accepted, row.names = FALSE, digits = 3)
  cat("\nErrors by signal-stem count:\n")
  print(sm$by_stem_count, row.names = FALSE, digits = 3)
  cat("\nOutcome by reason:\n")
  print(sm$reasons, row.names = FALSE)
}

## ---- STAGE=catalog: tests 2 and 3, candidate registrations ----------------------
read_pre <- function(name) {
  f <- file.path(PRE, name)
  if (!file.exists(f)) stop("Missing catalog-stage input: ", f)
  fread(f, colClasses = list(character = "plot_id"), na.strings = "")
}

CATALOG_INPUTS <- c("plots.csv", "trees.csv", "flights.csv", "clouds.csv")
catalog_inputs <- function() {
  sha <- ofo_sha256(PRE, CATALOG_INPUTS)
  x <- list(plots = read_pre("plots.csv"), trees = read_pre("trees.csv"),
            flights = read_pre("flights.csv"), clouds = read_pre("clouds.csv"), sha = sha)
  ok <- x$flights[cloud_status == "ok" & project_name != "NEON2023", plot_id]
  cl <- x$clouds[match(ok, x$clouds$plot_id)]
  miss <- ok[is.na(cl$path) | !file.exists(file.path(OFO, cl$path))]
  if (length(miss)) stop("Clouds missing for ", length(miss), " plots: ",
                         paste(head(miss, 10), collapse = ","))
  x$ok <- ok
  x
}

# Digests of the catalogue tables read (taken before reading; they must not
# have moved under the run) and of the outputs, in a file of its own: the
# frozen parts of registration_tests.json stay as they are.
write_catalog_record <- function(x, method) {
  now <- ofo_sha256(PRE, CATALOG_INPUTS)
  if (!identical(now, x$sha))
    stop("Inputs changed during the run: ", paste(CATALOG_INPUTS[now != x$sha], collapse = ", "))
  ofo_write_record(ofo_stage_record(
    "registration catalog", PRE, x$sha,
    c("registration_catalog.csv", "registration.csv", "registration_tests.json"),
    list(method = method)), file.path(PRE, "registration_catalog_record.json"))
}

has_group <- function(g) !is.na(g) & nzchar(g)

catalog_plot <- function(id, p, fl, tr, laz) {
  st <- ofo_catalog_stems(tr, p$status_recorded, p$live_floor_cm)
  signals <- c(if (isTRUE(p$heights_measured)) "height", if (any(st$rank_stem)) "rank")
  if (!length(signals)) return(NULL)
  M <- tryCatch(ofo_canopy_top(ofo_normalize(ofo_read_las(laz, "xyzc"))),
                error = function(e) conditionMessage(e))
  set <- if (identical(p$screen, "none") && has_group(p$group) && isTRUE(fl$flight_admitted))
    "candidate" else "heldout"
  do.call(rbind, lapply(signals, function(s) {
    k <- if (s == "height") st$height_stem else st$rank_stem
    size <- if (s == "height") st$height else st$dbh
    reg <- if (is.character(M)) {
      r <- ofo_register(matrix(0, 0, nrow(GRID)), numeric(), GRID, s, id)
      r$n_signal <- sum(k); r$reject_reason <- if (M == "no_ground") M else "surface"; r
    } else ofo_register(ofo_signal_matrix(M, st$x[k], st$y[k], GRID), size[k], GRID, s, id)
    cbind(data.frame(plot_id = id, project_name = p$project_name, set = set,
                     stringsAsFactors = FALSE),
          reg[, c("signal", "n_signal", "dx", "dy", "shift_m", "objective_zero",
                  "objective_best", "objective_median", "contrast", "residual_m",
                  "on_edge", "accepted", "reject_reason")],
          data.frame(screen = p$screen, group = if (has_group(p$group)) p$group else "",
                     heights_measured = isTRUE(p$heights_measured),
                     status_recorded = isTRUE(p$status_recorded), ql = fl$ql,
                     flight_year = fl$flight_year, gap_years = fl$gap_years,
                     flight_admitted = isTRUE(fl$flight_admitted),
                     surface_error = if (is.character(M)) M else "",
                     stringsAsFactors = FALSE))
  }))
}

heldout_summary <- function(rc) {
  h <- rc[rc$set == "heldout", ]
  q <- function(x) if (length(x)) as.list(stats::quantile(x, c(0.5, 0.9))) else NULL
  sapply(c("height", "rank"), function(s) {
    x <- h[h$signal == s, ]
    run <- x[x$n_signal >= OFO_REG$min_stems & is.finite(x$dx), ]
    a <- run[run$accepted, ]
    list(n_plots = nrow(x), n_run = nrow(run), n_accepted = nrow(a),
         shift_m_accepted = q(a$shift_m), residual_m_run = q(run$residual_m),
         reasons = as.list(table(ifelse(x$accepted, "(accepted)", x$reject_reason))))
  }, simplify = FALSE)
}

candidate_table <- function(x, rc, admitted) {
  pl <- x$plots[screen == "none" & has_group(group) & project_name != "NEON2023"]
  fl <- x$flights[match(pl$plot_id, x$flights$plot_id)]
  do.call(rbind, lapply(seq_len(nrow(pl)), function(i) {
    p <- pl[i]; f <- fl[i]
    used <- if (isTRUE(p$heights_measured)) "height" else "rank"
    r <- rc[rc$plot_id == p$plot_id & rc$signal == used, ]
    cand <- isTRUE(f$flight_admitted)
    why <- c(if (!cand) "flight_not_admitted",
             if (!identical(f$cloud_status, "ok")) "no_cloud",
             if (!isTRUE(admitted[[used]])) "signal_not_admitted",
             if (!nrow(r) && identical(f$cloud_status, "ok")) "not_run",
             if (nrow(r) && !r$accepted) strsplit(r$reject_reason, ";")[[1]])
    g <- function(col) if (nrow(r)) r[[col]] else NA
    data.frame(plot_id = p$plot_id, project_name = p$project_name, group = p$group,
               signal_used = used, signal_admitted = isTRUE(admitted[[used]]),
               dx = g("dx"), dy = g("dy"), shift_m = g("shift_m"),
               residual_m = g("residual_m"), contrast = g("contrast"),
               n_signal = if (nrow(r)) r$n_signal else NA_integer_,
               registered = cand && isTRUE(admitted[[used]]) && nrow(r) == 1 &&
                 isTRUE(r$accepted),
               reason = paste(why, collapse = ";"),
               pos_unc = if (nrow(r) && is.finite(r$residual_m))
                 max(0.5, r$residual_m) else NA_real_,
               flight_admitted = cand, set = if (nrow(r)) r$set else "",
               stringsAsFactors = FALSE)
  }))
}

# The declared catalogue pass: rows, candidate table and the complete
# declared block of registration_tests.json. `old` is the declared block that
# STAGE=neon wrote (test 1). Writes nothing.
declared_catalog <- function(x, old) {
  neon_csv <- file.path(PRE, "registration_neon.csv")
  if (!file.exists(neon_csv)) stop("Run STAGE=neon first: ", neon_csv, " is missing")
  neon <- as.data.frame(fread(neon_csv, na.strings = ""))
  neon$reject_reason[is.na(neon$reject_reason)] <- ""
  t1 <- ofo_known_truth_test(neon)
  message(sprintf("STAGE=catalog: %d plots with a cloud, %d cores", length(x$ok), CORES))
  cl <- x$clouds[match(x$ok, x$clouds$plot_id)]
  rows <- par_map(seq_along(x$ok), function(i) {
    id <- x$ok[i]
    catalog_plot(id, x$plots[plot_id == id], x$flights[plot_id == id],
                 x$trees[plot_id == id], file.path(OFO, cl$path[i]))
  })
  rc <- do.call(rbind, rows)
  rc <- rc[order(rc$plot_id, match(rc$signal, c("height", "rank"))), ]
  rownames(rc) <- NULL
  pairs <- ofo_agreement_pairs(rc, x$plots[heights_measured %in% TRUE, plot_id])
  t3 <- ofo_agreement_test(pairs$distance_m)
  admitted <- ofo_admitted_signals(t1, t3)
  reg <- candidate_table(x, rc, admitted)
  block <- c(method_record(), list(
    status = "complete",
    frozen_root_clip_manifest_sha256 = old$frozen_root_clip_manifest_sha256,
    test1_known_truth = c(old$test1_known_truth[c("population", "n_plots", "offset", "error")],
                          t1, old$test1_known_truth[c("by_accepted", "by_stem_count",
                                                      "reasons")]),
    test2_heldout = c(list(rule = "reported only; no pass rule"), heldout_summary(rc)),
    test3_agreement = c(list(rule = paste("plots with measured heights where both signals",
                                          "are accepted: >= 10 plots, >= 80% within 2.0 m")),
                        t3, list(plots = pairs)),
    admitted = admitted))
  list(rc = rc, reg = reg, block = block, t1 = t1, t3 = t3, admitted = admitted)
}

stage_catalog <- function() {
  tests <- read_tests()
  if (has_amendment(tests)) return(stage_catalog2(tests))
  if (!file.exists(file.path(PRE, "registration_neon.csv")) || is.null(tests))
    stop("Run STAGE=neon first: registration_neon.csv or registration_tests.json is missing")
  x <- catalog_inputs()
  out <- declared_catalog(x, tests)
  fwrite(out$rc, file.path(PRE, "registration_catalog.csv"))
  fwrite(out$reg, file.path(PRE, "registration.csv"))
  write_json_file(out$block, registration_tests_path)
  write_catalog_record(x, "declared")
  print_catalog(out$rc, out$t1, out$t3, out$admitted, out$reg)
  invisible(out$rc)
}

print_catalog <- function(rc, t1, t3, admitted, reg) {
  cat("\nRegistration on catalogue plots (set x signal):\n")
  m2 <- !is.null(rc$method)
  rt <- as.data.table(rc)[, .(plots = .N,
                              run = sum((m2 | n_signal >= OFO_REG$min_stems) & is.finite(dx)),
                              accepted = sum(accepted)), by = .(set, signal)]
  print(rt[order(set, signal)], row.names = FALSE)
  if (!is.null(t1))
    cat(sprintf("\nTest 1: height %s, rank %s\n", if (t1$height$pass) "PASS" else "FAIL",
                if (t1$rank$pass) "PASS" else "FAIL"))
  cat(sprintf("Test 3 (agreement): %d plots, %d within 2 m: %s\n", t3$n_plots,
              t3$n_within_2m, if (t3$pass) "PASS" else "FAIL"))
  cat(sprintf("Admitted signals: height %s, rank %s\n", admitted$height, admitted$rank))
  cat(sprintf("Candidate plots (screen none, a group): %d; flight admitted %d; registered %d\n",
              nrow(reg), sum(reg$flight_admitted), sum(reg$registered)))
  print(table(group = reg$group, registered = reg$registered))
}


## ==== Amendment 1: method 2 ======================================================
units_path <- file.path(PRE, "registration_units.csv")
confirm_path <- file.path(PRE, "registration_confirm.csv")
SIGNALS <- c("height", "rank")

neon_inputs <- function() {
  root <- frozen_root(d)
  if (!frozen_sealed(root)) stop("No sealed frozen root at ", root)
  pop <- do.call(rbind, lapply(NEON_SITES, function(s) frozen_population(root, s, "adopted")))
  gts <- setNames(lapply(NEON_SITES, function(s)
    read.csv(file.path(d, "neon", s, "ground_truth_stems.csv"), stringsAsFactors = FALSE)),
    NEON_SITES)
  list(root = root, manifest = frozen_clip_manifest(root), pop = pop, gts = gts)
}

# Live trees of one NEON plot with a position: the stem pool of test 1.
neon_stems <- function(gt, plot) {
  st <- gt[gt$plotID == plot & gt$live %in% TRUE & gt$is_tree %in% TRUE &
             is.finite(gt$E) & is.finite(gt$N), , drop = FALSE]
  data.frame(x = st$E, y = st$N, height = st$height, dbh = st$stemDiameter)
}

# Every unit of Amendment 1 with its known offset and stem counts that need
# no registration (live stems with a height; with a DBH of 10 cm or more).
build_units <- function(inp) {
  pop <- inp$pop
  u <- ofo_units(data.frame(site = pop$site, plot = pop$plotID, plot_type = pop$plotType))
  cnt <- t(vapply(seq_len(nrow(pop)), function(i) {
    st <- neon_stems(inp$gts[[pop$site[i]]], pop$plotID[i])
    c(sum(ofo2_signal_stems(st, "height")), sum(ofo2_signal_stems(st, "rank")))
  }, numeric(2)))
  rownames(cnt) <- pop$plotID
  mem <- strsplit(u$members, ";")
  off <- t(vapply(u$offset_key, ofo_unit_offset, numeric(2), max = OFO_REG2$offset_max))
  data.frame(unit = u$unit, set = u$set, kind = u$kind, site = u$site, members = u$members,
             n_live_height = vapply(mem, function(m) as.integer(sum(cnt[m, 1])), integer(1)),
             n_dbh10 = vapply(mem, function(m) as.integer(sum(cnt[m, 2])), integer(1)),
             offset_key = u$offset_key, n_members = u$n_members, plot_type = u$plot_type,
             split_rank = u$split_rank, offset_dx = off[, 1], offset_dy = off[, 2],
             stringsAsFactors = FALSE)
}

# Stems and surfaces (one per smoothing) of the named plots, from their native
# clips in the sealed root.
load_neon_plots <- function(inp, plots, smooths) {
  pop <- inp$pop[match(plots, inp$pop$plotID), ]
  if (anyNA(pop$plotID)) stop("Unknown plots: ", paste(plots[is.na(pop$plotID)], collapse = ","))
  out <- par_map(seq_len(nrow(pop)), function(i) {
    row <- pop[i, ]
    cell <- frozen_read(inp$root, row$site, row$plotID, NA, row$easting, row$northing,
                        row$core_half, manifest = inp$manifest)
    if (is.null(cell)) stop("No clip for ", row$plotID)
    las <- read_las(cell$normalized, "xyz")
    lidR::set_lidr_threads(1L)
    chm <- lidR::rasterize_canopy(las, res = OFO_REG2_SEARCH$res,
                                  algorithm = lidR::p2r(OFO_REG2_SEARCH$subcircle))
    list(stems = neon_stems(inp$gts[[row$site]], row$plotID),
         surf = setNames(lapply(smooths, function(s) ofo2_surface(chm, s)), smooths))
  })
  setNames(out, pop$plotID)
}

# Runs `variants` (list of list(signal, variant, cfg)) on `units`.
run_units <- function(units, P, variants) {
  jobs <- expand.grid(v = seq_along(variants), u = seq_len(nrow(units)))
  rows <- par_map(seq_len(nrow(jobs)), function(j) {
    v <- variants[[jobs$v[j]]]; u <- units[jobs$u[j], ]
    r <- ofo2_run_unit(u$unit, strsplit(u$members, ";")[[1]], P, v$signal, v$cfg,
                       c(u$offset_dx, u$offset_dy), GRID)
    cbind(data.frame(variant = v$variant, estimator = v$cfg$estimator, kind = u$kind,
                     site = u$site, stringsAsFactors = FALSE), r)
  })
  res <- do.call(rbind, rows)
  cols <- c("variant", "signal", "unit", "kind", "site", "n_signal", "offset_dx", "offset_dy",
            "dx", "dy", "error_m", "residual_m", "z", "second_peak", "sub_p90_m", "contrast",
            "objective_best", "objective_median", "objective_zero", "shift_m", "on_edge",
            "resample_reach_m", "estimator")
  res <- res[order(match(res$signal, SIGNALS), res$variant, res$kind != "plot", res$unit), cols]
  rownames(res) <- NULL
  res
}

variant_list <- function(signals = SIGNALS)
  unlist(lapply(signals, function(s) lapply(names(OFO_REG2_VARIANTS[[s]]), function(v)
    list(signal = s, variant = v, cfg = OFO_REG2_VARIANTS[[s]][[v]]))), recursive = FALSE)

frozen_variants <- function()
  lapply(SIGNALS, function(s) list(signal = s, variant = OFO_REG2[[s]]$variant,
                                   cfg = OFO_REG2[[s]]$cfg))

# Accepted under the frozen (or, before the freeze, the provisional) gate of
# each row's signal; `frozen_variant` marks the configuration of OFO_REG2.
gate_rows <- function(res) {
  out <- do.call(rbind, lapply(split(res, res$signal), function(x) {
    g <- OFO_REG2[[x$signal[1]]]$gate
    y <- ofo2_apply_gate(x, g)
    y$accepted[!is.finite(y$dx)] <- FALSE
    y$reject_reason[!is.finite(y$dx)] <- "not_run"
    y
  }))
  out$frozen_variant <- out$variant == vapply(out$signal, function(s) OFO_REG2[[s]]$variant, "")
  out[order(match(out$signal, SIGNALS), out$variant, out$kind != "plot", out$unit), ]
}

stage_dev <- function() {
  inp <- neon_inputs()
  dir.create(PRE, recursive = TRUE, showWarnings = FALSE)
  before <- neon_snapshot()
  units <- build_units(inp)
  fwrite(units, units_path)
  dev <- units[units$set == "development", ]
  dev_plots <- dev$unit[dev$kind == "plot"]
  if (!all(unlist(strsplit(dev$members, ";")) %in% dev_plots))
    stop("A development composite holds a plot outside the development half")
  smooths <- unique(unlist(lapply(OFO_REG2_VARIANTS, function(v)
    vapply(v, function(cfg) cfg$surface, ""))))
  message(sprintf(paste("STAGE=dev: %d development units (%d plots, %d composites),",
                        "%d variants, %d cores"),
                  nrow(dev), length(dev_plots), sum(dev$kind == "composite"),
                  length(variant_list()), CORES))
  for (sg in SIGNALS)
    if (!identical(OFO_REG2[[sg]]$cfg, OFO_REG2_VARIANTS[[sg]][[OFO_REG2[[sg]]$variant]]))
      stop("OFO_REG2$", sg, " no longer matches its development variant")
  P <- load_neon_plots(inp, dev_plots, smooths)
  res <- gate_rows(run_units(dev, P, variant_list()))
  sweep <- do.call(rbind, par_map(split(res, paste(res$variant, res$signal)), ofo2_gate_sweep))
  sweep <- sweep[order(match(sweep$signal, SIGNALS), sweep$variant), ]
  rownames(sweep) <- NULL
  sel <- ofo2_select(sweep)
  eq <- equivariance_check(dev, P)
  after <- neon_snapshot()
  ev <- neon_evidence(before, after, "dev")
  write_json_file(ev, file.path(PRE, "neon_untouched_dev.json"))
  if (!isTRUE(ev$identical)) stop("<job>/neon changed during the run; see neon_untouched_dev.json")
  fwrite(res, file.path(PRE, "registration_dev.csv"))
  fwrite(ofo2_dev_summary(res), file.path(PRE, "registration_dev_summary.csv"))
  sweep$selection_rank <- NA_integer_
  sweep$selection_rank[as.integer(rownames(sel))] <-
    stats::ave(seq_len(nrow(sel)), sel$signal, FUN = seq_along)
  sweep$selection_basis <- NA_character_
  sweep$selection_basis[as.integer(rownames(sel))] <- sel$basis
  fwrite(sweep, file.path(PRE, "registration_dev_gates.csv"))
  fwrite(eq, file.path(PRE, "registration_dev_equivariance.csv"))
  write_json_file(selection_record(res, sweep, sel, eq),
                  file.path(PRE, "registration_dev_selection.json"))
  print_dev(units, res, sweep, sel, eq)
  invisible(res)
}

# The selection and the frozen configuration's development record.
selection_record <- function(res, sweep, sel, eq) {
  per <- lapply(setNames(SIGNALS, SIGNALS), function(s) {
    g <- OFO_REG2[[s]]$gate
    f <- sweep[sweep$signal == s & sweep$variant == OFO_REG2[[s]]$variant &
                 sweep$gate_stat == g$stat & abs(sweep$threshold - g$threshold) < 1e-9 &
                 sweep$min_stems == g$min_stems, ]
    conf <- sweep[sweep$signal == s & sweep$meets_confirm_limits, ]
    list(n_configurations = sum(sweep$signal == s),
         n_meeting_dev_margins = sum(sweep$signal == s & sweep$meets_dev_margins),
         n_meeting_confirmation_limits = nrow(conf),
         selection_basis = unique(sel$basis[sel$signal == s]),
         top_by_rule = utils::head(sel[sel$signal == s, ], 5),
         top_by_bootstrap_any_stat = utils::head(conf[order(-conf$p_pass_bootstrap,
                                                            -conf$accepted), ], 5),
         frozen = c(OFO_REG2[[s]], list(development = f)),
         frozen_rank_in_selection = match(rownames(f)[1], rownames(sel[sel$signal == s, ])))
  })
  e <- eq[eq$checked %in% TRUE, ]
  list(created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
       rule = paste("peak estimator, gate statistic residual_m or sub_p90_m and >= 10",
                    "accepted development units; among configurations meeting the development",
                    "margins (median error of accepted <= 0.8 m, >= 95% within 2.0 m) at or",
                    "above their smallest stem",
                    "count, the most accepted development units; simpler when close. When none",
                    "meets the margins: among those meeting the confirmation limits, the highest",
                    "bootstrap chance of passing; simpler when close."),
       note = paste("height: ncc and ncc_gauss0.5 tie at 31 accepted; ncc (raw surface) is",
                    "frozen as the simpler."),
       margins = OFO_REG2_DEV_MARGINS, confirmation_limits = OFO_REG2_PASS,
       gate_grid = OFO_REG2_GATE_GRID, digest_sha256 = ofo2_config_digest(),
       signals = per,
       equivariance = list(delta_m = EQ_DELTA, n_checked = nrow(e),
                           max_deviation_m = if (nrow(e)) max(e$deviation_m) else NA_real_))
}

# Translation equivariance on development units: each unit is run again with
# its offset moved by a grid multiple (1.5, -2.0) m; the estimate must move by
# exactly the opposite wherever both the estimate and that opposite lie inside
# the window, off its edge (`checked`). Gate statistics must not change where,
# in addition, no resampled estimate comes near the edge.
EQ_DELTA <- c(1.5, -2.0)
equivariance_check <- function(dev, P) {
  vs <- frozen_variants()
  jobs <- expand.grid(v = seq_along(vs), u = seq_len(nrow(dev)))
  rows <- par_map(seq_len(nrow(jobs)), function(j) {
    v <- vs[[jobs$v[j]]]; u <- dev[jobs$u[j], ]
    m <- strsplit(u$members, ";")[[1]]
    off <- c(u$offset_dx, u$offset_dy)
    a <- ofo2_run_unit(u$unit, m, P, v$signal, v$cfg, off, GRID)
    b <- ofo2_run_unit(u$unit, m, P, v$signal, v$cfg, off + EQ_DELTA, GRID)
    g <- OFO_REG2[[v$signal]]$gate
    data.frame(signal = v$signal, variant = v$variant, unit = u$unit, kind = u$kind,
               n_signal = a$n_signal, dx = a$dx, dy = a$dy, dx_moved = b$dx, dy_moved = b$dy,
               deviation_m = sqrt((b$dx - a$dx + EQ_DELTA[1])^2 + (b$dy - a$dy + EQ_DELTA[2])^2),
               residual_m = a$residual_m, residual_moved_m = b$residual_m,
               gate_stat = a[[g$stat]], gate_stat_moved = b[[g$stat]],
               on_edge = a$on_edge | b$on_edge,
               checked = isFALSE(a$on_edge) && isFALSE(b$on_edge) &&
                 max(abs(c(a$dx - EQ_DELTA[1], a$dy - EQ_DELTA[2]))) <
                   OFO_REG2_SEARCH$max_shift - OFO_REG2_SEARCH$step,
               resample_reach_m = pmax(a$resample_reach_m, b$resample_reach_m),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

print_dev <- function(units, res, sweep, sel, eq) {
  cat("\nUnits of Amendment 1:\n")
  print(table(set = units$set, kind = units$kind))
  sm <- ofo2_dev_summary(res)
  cat("\nDevelopment, all run units at >= 15 signal stems, per variant (no gate):\n")
  x <- res[is.finite(res$dx) & res$n_signal >= 15, ]
  tab <- do.call(rbind, lapply(split(x, list(x$signal, x$variant), drop = TRUE), function(y) {
    a <- ofo2_accuracy(y$error_m)
    data.frame(signal = y$signal[1], variant = y$variant[1], run = a$n,
               median_error_m = round(a$median_error_m, 2),
               share_within_2m = round(a$share_within_2m, 2))
  }))
  print(tab[order(tab$signal, tab$median_error_m), ], row.names = FALSE)
  cat("\nSelection rule (ofo2_select; `basis` says which branch), top 5 per signal:\n")
  for (s in SIGNALS) print(utils::head(sel[sel$signal == s, ], 5), row.names = FALSE)
  cat("\nFrozen configuration (OFO_REG2) on development units:\n")
  f <- res[res$frozen_variant, ]
  for (s in SIGNALS) {
    g <- OFO_REG2[[s]]$gate
    y <- f[f$signal == s & f$n_signal >= g$min_stems, ]
    t <- ofo2_confirmation_test(y$n_signal, y$accepted, y$error_m, g$min_stems)
    cat(sprintf(paste("  %-6s %s, gate %s %s, >= %d stems: %d units, %d accepted,",
                      "median %.3f m, within 2 m %d (%.1f%%)\n"),
                s, OFO_REG2[[s]]$variant, g$stat, format(g$threshold), g$min_stems,
                t$n_at_min_stems, t$n_accepted, t$median_error_m, t$n_within_2m,
                100 * t$share_within_2m))
  }
  e <- eq[eq$checked %in% TRUE, ]
  cat(sprintf(paste("\nEquivariance (delta %.1f, %.1f m): %d of %d unit runs with both estimates",
                    "inside the window, off its edge; max deviation %.3g m\n"),
              EQ_DELTA[1], EQ_DELTA[2], nrow(e), nrow(eq), max(e$deviation_m)))
  # Resampled estimates within max|delta| + a step of the edge can be clipped
  # in one run and not the other; elsewhere the statistics must not move.
  inner <- e[e$resample_reach_m < OFO_REG2_SEARCH$max_shift - max(abs(EQ_DELTA)) -
               OFO_REG2_SEARCH$step, ]
  cat(sprintf(paste("  resamples off the edge in %d of them: max change of the residual %.3g m,",
                    "of the gate statistic %.3g\n"), nrow(inner),
              max(abs(inner$residual_m - inner$residual_moved_m)),
              max(abs(inner$gate_stat - inner$gate_stat_moved))))
  cat(sprintf("\nMethod-2 digest (quote it in Amendment 1b): %s\n", ofo2_config_digest()))
}

## ---- STAGE=confirm: the single confirmation run -----------------------------------------
# Writes the whole file: the declared content (as it stands) under "declared",
# the amendment block and the final admission at the top level.
write_amended_tests <- function(status, amendment, admitted, declared = NULL) {
  old <- read_tests()
  if (is.null(declared))
    declared <- if (is.null(old)) NULL else if (!is.null(old$amendment1)) old$declared else old
  write_json_file(list(status = status, declared = declared, amendment1 = amendment,
                       admitted = admitted), registration_tests_path)
}

frozen_record <- function()
  list(protocol = "docs/ofo-preflight-protocol.md (Amendment 1 and Amendment 1b)",
       digest_sha256 = ofo2_config_digest(), search = OFO_REG2_SEARCH,
       min_run = OFO_REG2_MIN_RUN, frozen = OFO_REG2, shifts = nrow(GRID))

protocol_text <- function() {
  f <- file.path(.ROOT, "docs", "ofo-preflight-protocol.md")
  if (file.exists(f)) readLines(f, warn = FALSE) else character()
}

stage_confirm <- function() {
  ofo2_confirm_guard(A$CONFIRM, file.exists(confirm_path), ofo2_frozen(),
                     protocol_text())
  inp <- neon_inputs()
  before <- neon_snapshot()
  units <- build_units(inp)
  if (file.exists(units_path)) {
    old <- as.data.frame(fread(units_path, na.strings = ""))
    key <- c("unit", "set", "kind", "members")
    if (!identical(old[, key], units[, key]) ||
        max(abs(c(old$offset_dx - units$offset_dx, old$offset_dy - units$offset_dy))) > 1e-9)
      stop("registration_units.csv differs from the split and offsets declared in Amendment 1")
  } else fwrite(units, units_path)
  conf <- units[units$set == "confirmation", ]
  conf_plots <- conf$unit[conf$kind == "plot"]
  if (!all(unlist(strsplit(conf$members, ";")) %in% conf_plots))
    stop("A confirmation composite holds a plot outside the confirmation half")
  message(sprintf("STAGE=confirm: %d confirmation units (%d plots, %d composites), %d cores",
                  nrow(conf), length(conf_plots), sum(conf$kind == "composite"), CORES))
  smooths <- unique(vapply(SIGNALS, function(s) OFO_REG2[[s]]$cfg$surface, ""))
  P <- load_neon_plots(inp, conf_plots, smooths)
  res <- gate_rows(run_units(conf, P, frozen_variants()))
  res$at_min_stems <- res$n_signal >=
    vapply(res$signal, function(s) OFO_REG2[[s]]$gate$min_stems, integer(1))
  after <- neon_snapshot()
  ev <- neon_evidence(before, after, "confirm")
  write_json_file(ev, file.path(PRE, "neon_untouched_confirm.json"))
  if (!isTRUE(ev$identical))
    stop("<job>/neon changed during the run; see neon_untouched_confirm.json")
  fwrite(res, confirm_path)
  conf_tests <- confirmation_tests(res)
  passed <- lapply(conf_tests, `[[`, "pass")
  amendment <- list(
    method = frozen_record(),
    units = list(n_plots = sum(units$kind == "plot"),
                 table = as.data.frame(table(set = units$set, kind = units$kind),
                                       stringsAsFactors = FALSE)),
    offset = "set.seed(seed_for('offset2', <plot or first member>, NA)); runif(2, -8, 8)",
    error = "distance between the estimate and the shift that undoes the offset",
    confirmation = c(conf_tests, list(
      rule = paste("units at or above the smallest stem count: >= 10 accepted,",
                   "median error of accepted <= 1.0 m, >= 90% of accepted within 2.0 m"),
      run_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      frozen_root_clip_manifest_sha256 = before$clip_manifest_sha256,
      by_kind = confirm_by_kind(res))),
    admitted_confirmation = passed,
    catalog = NULL)
  # The rank signal also needs test 3 with method 2, run by STAGE=catalog.
  write_amended_tests(
    "amendment 1: confirmation run; test 3 with method 2 and the catalogue need STAGE=catalog",
    amendment, list(height = isTRUE(passed$height), rank = FALSE))
  print_confirm(conf_tests, res)
  invisible(res)
}

confirmation_tests <- function(res)
  sapply(SIGNALS, function(s) {
    x <- res[res$signal == s, ]
    c(list(variant = OFO_REG2[[s]]$variant, min_stems = OFO_REG2[[s]]$gate$min_stems),
      ofo2_confirmation_test(x$n_signal, x$accepted, x$error_m, OFO_REG2[[s]]$gate$min_stems))
  }, simplify = FALSE)

confirm_by_kind <- function(res) {
  x <- res[res$at_min_stems, ]
  if (!nrow(x)) return(NULL)
  do.call(rbind, lapply(split(x, list(x$signal, x$kind), drop = TRUE), function(y) {
    a <- ofo2_accuracy(y$error_m[y$accepted]); r <- ofo2_accuracy(y$error_m)
    data.frame(signal = y$signal[1], kind = y$kind[1], units = nrow(y), accepted = a$n,
               median_error_accepted_m = a$median_error_m,
               share_within_2m_accepted = a$share_within_2m,
               median_error_all_m = r$median_error_m, stringsAsFactors = FALSE)
  }))
}

print_confirm <- function(conf_tests, res) {
  cat("\nAmendment 1 confirmation, per signal:\n")
  for (s in names(conf_tests)) with(conf_tests[[s]], cat(sprintf(
    paste("  %-6s units %d, at >= %d stems %d, accepted %d, median error %.3f m,",
          "within 2 m %d (%.1f%%): %s\n"),
    s, n_units, min_stems, n_at_min_stems, n_accepted, median_error_m, n_within_2m,
    100 * share_within_2m, if (pass) "PASS" else "FAIL")))
  print(confirm_by_kind(res), row.names = FALSE, digits = 3)
}

## ---- STAGE=catalog after the amendment ------------------------------------------------------
# Method-2 registration of one catalogue plot with the frozen configuration of
# each signal it can run. Height stems: live trees with a measured height, as
# the live tree stems of the NEON development plots; rank stems: the plot's
# reference stems (as declared).
catalog_plot2 <- function(id, p, fl, tr, laz) {
  st <- ofo_catalog_stems(tr, p$status_recorded, p$live_floor_cm)
  is_tree <- as.data.frame(tr)$is_tree[is.finite(tr$x) & is.finite(tr$y)] %in% TRUE
  sel <- list(height = st$live & is_tree & is.finite(st$height) & st$height > 0,
              rank = st$rank_stem)
  signals <- c(if (isTRUE(p$heights_measured)) "height", if (any(st$rank_stem)) "rank")
  if (!length(signals)) return(NULL)
  smooths <- unique(vapply(signals, function(s) OFO_REG2[[s]]$cfg$surface, ""))
  surf <- tryCatch({
    nrm <- ofo_normalize(ofo_read_las(laz, "xyzc"))
    lidR::set_lidr_threads(1L)
    chm <- lidR::rasterize_canopy(nrm, res = OFO_REG2_SEARCH$res,
                                  algorithm = lidR::p2r(OFO_REG2_SEARCH$subcircle))
    setNames(lapply(smooths, function(s) ofo2_surface(chm, s)), smooths)
  }, error = function(e) conditionMessage(e))
  set <- if (identical(p$screen, "none") && has_group(p$group) && isTRUE(fl$flight_admitted))
    "candidate" else "heldout"
  do.call(rbind, lapply(signals, function(s) {
    k <- sel[[s]]
    g <- OFO_REG2[[s]]$gate
    n <- sum(k)
    reg <- if (!is.character(surf) && n >= OFO_REG2_MIN_RUN) {
      mem <- list(list(S = surf[[OFO_REG2[[s]]$cfg$surface]], x = st$x[k], y = st$y[k],
                       size = if (s == "height") st$height[k] else st$dbh[k]))
      ofo2_register_unit(ofo2_prepare(mem, OFO_REG2[[s]]$cfg, GRID), id)
    } else data.frame(n_signal = n, dx = NA_real_, dy = NA_real_, shift_m = NA_real_,
                      objective_zero = NA_real_, objective_best = NA_real_,
                      objective_median = NA_real_, contrast = NA_real_, z = NA_real_,
                        second_peak = NA_real_, residual_m = NA_real_, sub_p90_m = NA_real_,
                      on_edge = NA, resample_reach_m = NA_real_)
    acc <- ofo2_accept(n, reg$on_edge, reg[[g$stat]], g)
    why <- if (is.character(surf)) (if (surf == "no_ground") surf else "surface") else
      if (!is.finite(reg$dx)) "n" else acc$reason
    data.frame(plot_id = id, project_name = p$project_name, set = set, signal = s,
               n_signal = n, dx = reg$dx, dy = reg$dy, shift_m = reg$shift_m,
               objective_zero = reg$objective_zero, objective_best = reg$objective_best,
               objective_median = reg$objective_median, contrast = reg$contrast,
               residual_m = reg$residual_m, on_edge = reg$on_edge,
               accepted = !is.character(surf) && is.finite(reg$dx) && acc$accepted,
               reject_reason = why, method = "amendment1",
               screen = p$screen, group = if (has_group(p$group)) p$group else "",
               heights_measured = isTRUE(p$heights_measured),
               status_recorded = isTRUE(p$status_recorded), ql = fl$ql,
               flight_year = fl$flight_year, gap_years = fl$gap_years,
               flight_admitted = isTRUE(fl$flight_admitted),
               surface_error = if (is.character(surf)) surf else "",
               z = reg$z, second_peak = reg$second_peak, sub_p90_m = reg$sub_p90_m,
               variant = OFO_REG2[[s]]$variant, stringsAsFactors = FALSE)
  }))
}

heldout_summary2 <- function(rc) {
  h <- rc[rc$set == "heldout", ]
  q <- function(x) if (length(x)) as.list(stats::quantile(x, c(0.5, 0.9))) else NULL
  sapply(SIGNALS, function(s) {
    x <- h[h$signal == s, ]
    run <- x[is.finite(x$dx), ]
    a <- run[run$accepted, ]
    list(n_plots = nrow(x), n_run = nrow(run),
         n_at_min_stems = sum(run$n_signal >= OFO_REG2[[s]]$gate$min_stems),
         n_accepted = nrow(a), shift_m_accepted = q(a$shift_m), residual_m_run = q(run$residual_m),
         reasons = as.list(table(ifelse(x$accepted, "(accepted)", x$reject_reason))))
  }, simplify = FALSE)
}

# Declared rows of an existing registration_catalog.csv (all rows when it has
# no method column: they predate the amendment), kept as they were reported.
declared_rows <- function() {
  f <- file.path(PRE, "registration_catalog.csv")
  if (!file.exists(f)) return(NULL)
  old <- fread(f, colClasses = list(character = "plot_id"), na.strings = "")
  if (!"method" %in% names(old)) old[, method := "declared"]
  old <- old[method == "declared"]
  setcolorder(old, c(setdiff(names(old), "method")[1:16], "method"))
  as.data.frame(old)
}

stage_catalog2 <- function(tests) {
  am <- tests$amendment1
  conf <- list(height = isTRUE(am$admitted_confirmation$height),
               rank = isTRUE(am$admitted_confirmation$rank))
  x <- catalog_inputs()
  recompute <- isTRUE(as.logical(A$DECLARED))
  dec <- if (recompute) declared_catalog(x, tests$declared) else NULL
  message(sprintf("STAGE=catalog (amendment 1, method 2): %d plots with a cloud, %d cores",
                  length(x$ok), CORES))
  cl <- x$clouds[match(x$ok, x$clouds$plot_id)]
  rows <- par_map(seq_along(x$ok), function(i) {
    id <- x$ok[i]
    catalog_plot2(id, x$plots[plot_id == id], x$flights[plot_id == id],
                  x$trees[plot_id == id], file.path(OFO, cl$path[i]))
  })
  rc2 <- do.call(rbind, rows)
  rc2 <- rc2[order(rc2$plot_id, match(rc2$signal, SIGNALS)), ]
  rownames(rc2) <- NULL
  old_rows <- if (recompute) {
    r <- dec$rc; r$method <- "declared"
    r[, c(names(r)[1:16], "method", setdiff(names(r)[-(1:16)], "method"))]
  } else declared_rows()
  rc <- as.data.frame(rbindlist(list(old_rows, rc2), fill = TRUE, use.names = TRUE))
  fwrite(rc, file.path(PRE, "registration_catalog.csv"))
  pairs <- ofo_agreement_pairs(rc2, x$plots[heights_measured %in% TRUE, plot_id])
  t3 <- ofo_agreement_test(pairs$distance_m)
  admitted <- list(height = conf$height, rank = conf$rank && isTRUE(t3$pass))
  reg_path <- file.path(PRE, "registration.csv")
  keep <- file.path(PRE, "registration_declared.csv")
  if (recompute) fwrite(dec$reg, keep)
  else if (file.exists(reg_path) && !file.exists(keep) &&
           !"method" %in% names(fread(reg_path, nrows = 1))) file.copy(reg_path, keep)
  reg <- candidate_table(x, rc2, admitted)
  reg$method <- "amendment1"
  fwrite(reg, reg_path)
  am$catalog <- list(
    created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    test2_heldout = c(list(rule = "reported only; no pass rule"), heldout_summary2(rc2)),
    test3_agreement = c(list(rule = paste("method 2; plots with measured heights where both",
                                          "signals are accepted: >= 10 plots, >= 80% within",
                                          "2.0 m")), t3, list(plots = pairs)),
    admitted = admitted)
  write_amended_tests("complete (amendment 1)", am, admitted,
                      declared = if (recompute) dec$block else tests$declared)
  write_catalog_record(x, if (recompute) "amendment1 and declared" else "amendment1")
  cat(sprintf("\nConfirmation: height %s, rank %s\n", if (conf$height) "PASS" else "FAIL",
              if (conf$rank) "PASS" else "FAIL"))
  print_catalog(rc2, NULL, t3, admitted, reg)
  invisible(rc2)
}

if (STAGE %in% c("neon", "all")) stage_neon()
if (STAGE %in% c("catalog", "all")) stage_catalog()
if (STAGE == "dev") stage_dev()
if (STAGE == "confirm") stage_confirm()
