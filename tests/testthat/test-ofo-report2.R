source(file.path("..", "..", "scripts", "report_ofo_preflight2.R"), local = TRUE)

# Synthetic second-protocol tables in the contracts' shape, every field a
# string as the report reads them.
chr_df <- function(...) {
  x <- data.frame(..., stringsAsFactors = FALSE, check.names = FALSE)
  x[] <- lapply(x, as.character)
  x
}

fake_truth <- function() chr_df(
  plot = c("SJER_046", "ABBY_063", "NIWO_001"), site = c("SJER", "ABBY", "NIWO"),
  annotation = c("SJER_046_2018.xml", "ABBY_063_2019.xml", "NIWO_001_2020.xml"),
  ann_year = c(2018, 2019, 2020), source = c("benchmark", "benchmark", "niwo"),
  n_boxes = c(40, 55, 30), n_truth_stems = c(5, 12, 9), truth_dx = c(0.25, -1.5, NA),
  truth_dy = c(0, 2.75, NA), truth_on_edge = c(FALSE, FALSE, NA), s90_truth_m = c(1.4, 0.6, NA),
  tie_dx = c(0, 0.25, NA), tie_dy = c(0, -0.5, NA), tie_ncc = c(0.8, 0.71, NA),
  tie_on_edge = c(FALSE, FALSE, NA), truth_m_dx = c(0.25, -1.25, NA),
  truth_m_dy = c(0, 2.25, NA), dist_mapped_m = c(0.25, 2.97, NA),
  credible = c(FALSE, TRUE, FALSE), reason = c("n;s90", "", "no_truth"))

fake_units <- function() chr_df(
  source = c("benchmark", "benchmark", "benchmark", "niwo"),
  half = c("development", "confirmation", "confirmation", "niwo"),
  plot = c("ABBY_063", "SJER_046", "ABBY_063", "NIWO_001"),
  signal = c("height", "height", "rank", "rank"), variant = c("ncc", "ncc", "ncc_r2", "ncc_r2"),
  n_signal = c(25, 12, 40, 30), at_min_stems = c(TRUE, FALSE, TRUE, TRUE),
  accepted = c(TRUE, FALSE, TRUE, TRUE), est_dx = c(-1, NA, -1.2, 0.3),
  est_dy = c(2, NA, 2.1, 0.1), truth_m_dx = c(-1.25, 0.25, -1.25, NA),
  truth_m_dy = c(2.25, 0, 2.25, NA), credible = c(TRUE, FALSE, TRUE, FALSE),
  error_crown_m = c(0.35, NA, 0.16, NA), error_zero_m = c(2.24, NA, 2.42, 0.32),
  in_test = c(TRUE, FALSE, TRUE, FALSE))

fake_test <- function() list(
  rule = "per signal: at least 10 units, median error at most 1.0 m, 90% within 2.0 m",
  signals = list(height = list(units = 12, median_error_m = 0.61, pass = TRUE,
                               subsets = list(niwo = list(units = 4, median_error_m = NULL))),
                 rank = list(units = 8, median_error_m = 0.9, pass = FALSE, inconclusive = TRUE)),
  admitted = list(height = TRUE, rank = FALSE))

fake_reg <- function() chr_df(
  plot_id = c("0068", "0084", "0073", "0200", "0271"),
  project_name = c("EP", "JL", "ST", "MN", "OH"),
  group = c("A", "A", "B", "B", "B"), signal_used = c("height", "height", "rank", "rank", "rank"),
  signal_admitted = c(TRUE, TRUE, FALSE, FALSE, FALSE), n_signal = c(1841, 725, 309, 59, NA),
  dx = c(1.77, -0.75, 0, -12, NA), dy = c(-1.06, -0.71, 0.13, -5.06, NA),
  flight_admitted = c(TRUE, TRUE, TRUE, TRUE, FALSE), accepted = c(TRUE, TRUE, TRUE, FALSE, FALSE),
  at_min_stems = c(TRUE, TRUE, TRUE, TRUE, FALSE), second_peak = c(0.656, 0.831, 0.611, 0.812, NA),
  second_peak_ok = c(TRUE, FALSE, TRUE, FALSE, FALSE), rank_accepted = c(TRUE, TRUE, NA, NA, NA),
  agreement_m = c(0.12, 1.42, NA, NA, NA), agreement_ok = c(TRUE, TRUE, TRUE, TRUE, TRUE),
  registered = c(TRUE, FALSE, FALSE, FALSE, FALSE),
  reason = c("", "second_peak", "signal_not_admitted", "signal_not_admitted;on_edge;second_peak",
             "flight_not_admitted;no_cloud;signal_not_admitted"))

fake_dist <- function() chr_df(
  plot_id = c("0068", "0077", "0271"), project_name = c("EP", "ST", "OH"),
  group = c("A", "B", "B"), interval_start = c("2019-01-01", "2018-01-01", "2019-01-01"),
  interval_end = c("2022-08-19", "2022-06-14", NA), n_fire_records = c(0, 0, NA),
  fire_names = c(NA, NA, NA), fire_clear = c(TRUE, TRUE, NA), n_activity_records = c(0, 5, NA),
  activity_names = c(NA, "Salvage Cut (2018-06-01, harvest_2011_2020)", NA),
  nfs_records_source = c(FALSE, TRUE, TRUE), activities_clear = c(TRUE, FALSE, NA),
  presence_test_stems = c(400, 120, 30), presence_missing = c(12, NA, NA),
  presence_missing_share = c(0.03, NA, NA), presence_status = c("pass", "not_run", "not_run"),
  disturbance_admitted = c(TRUE, FALSE, FALSE),
  disturbance_reason = c("", "activity;presence_not_run",
                         "fire_unchecked;activity_unchecked;presence_not_run"),
  flight_admitted = c(TRUE, TRUE, FALSE))

fake_detail <- function() chr_df(
  plot_id = c("0068", "0068", "0197", "0271"), source = c("fire_history", "fire_wfigs",
                                                          "fire_wfigs", "fire_history"),
  record = "fire", name = c("OLD", "NEAR", "Dexter", "X"),
  event_date = c(NA, "2021-07-02", "2021-07-02", NA), event_year = c(1950, 2021, 2021, 2010),
  in_interval = c(FALSE, TRUE, TRUE, NA), hit = c(FALSE, FALSE, FALSE, TRUE),
  distance_m = c(1200, 97.4, 138, 0))

test_that("JSON blocks flatten to key paths, wherever the per-signal block sits", {
  f <- rep2_flatten(list(a = 1, b = list(c = TRUE, d = NULL, e = c(1, 2)), g = "x",
                         h = list(list(k = 2))))
  expect_equal(f, c(a = "1", b.c = "true", b.e = "1, 2", g = "x", h.1.k = "2"))
  expect_equal(rep2_flatten(list(n = NA)), c(n = "null"))
  js <- fake_test()
  expect_equal(rep2_signal_block(js, "height")$where, "signals.height")
  expect_equal(rep2_signal_block(list(rank = list(units = 1)), "rank")$where, "rank")
  expect_null(rep2_signal_block(list(signals = list(height = 1)), "height"))   # not a block
  expect_null(rep2_signal_block(list(), "rank"))
  expect_equal(rep2_admitted(list(height = TRUE, rank = NULL)),
               paste0("height yes, rank ", REP_DASH))
})

test_that("the pass rule lists every field of each signal and the final admission", {
  out <- rep2_sec_pass(list(crowntruth_test.json = fake_test()))
  expect_equal(out[1], "### (c) Pass rule per signal and subset")
  expect_true(any(grepl("final admission\\): height yes, rank no\\.", out)))
  expect_true("| Statistic | height (`signals.height`) | rank (`signals.rank`) |" %in% out)
  expect_true("| median_error_m | 0.61 | 0.9 |" %in% out)
  expect_true(any(grepl(paste0("^\\| inconclusive \\| ", REP_DASH, " \\| true \\|$"), out)))
  expect_true(any(grepl("^\\| subsets.niwo.units \\| 4 \\| ", out)))
  expect_true(any(grepl("^Rule: per signal", out)))
  none <- rep2_sec_pass(list(crowntruth_test.json = list(admitted = list(height = FALSE,
                                                                          rank = FALSE))))
  expect_true(any(grepl("holds no per-signal block", none)))
  miss <- rep2_sec_pass(list())
  expect_true(any(grepl("Not produced: `crowntruth_test.json` is missing.", miss, fixed = TRUE)))
})

test_that("crown truth and test units: one row per annotation and per unit", {
  tr <- rep2_sec_truth(list(crown_truth.csv = fake_truth()))
  expect_equal(sum(grepl("^\\| (SJER|ABBY|NIWO)_", tr)), 3L)
  expect_true(any(grepl(paste0("^\\| ABBY_063 \\| ABBY \\| benchmark \\| 2019 \\| 55 \\| 12 ",
                               "\\| -1.50, 2.75 \\|"), tr)))
  expect_true(any(grepl("1 of 3 annotations credible", tr)))
  bad <- fake_truth(); bad$tie_ncc <- NULL
  expect_true(any(grepl("lacks column\\(s\\) `tie_ncc`",
                        rep2_sec_truth(list(crown_truth.csv = bad)))))
  expect_true(any(grepl("`crown_truth.csv` is missing", rep2_sec_truth(list()))))
  un <- rep2_sec_units(list(crowntruth_units.csv = fake_units()))
  expect_true("Signal `height`: 2 units, 1 in the test." %in% un)
  expect_true("Signal `rank`: 2 units, 1 in the test." %in% un)
  # Units in the test first.
  h <- grep("^\\| benchmark \\| ", un, value = TRUE)
  expect_match(h[1], "ABBY_063 \\| ncc \\| 25 ")
  expect_true(any(grepl("\\| 0.35 \\| 2.24 \\| yes \\|$", un)))
})

test_that("registration: the gate funnel per group and the plots with an admitted flight", {
  out <- rep2_sec_registration(list(registration.csv = fake_reg()))
  expect_true(any(grepl(paste("^\\| A \\| height \\| yes \\| 2 \\| 2 \\| 2 \\| 1 \\| 1 \\| 1 \\|$"),
                        out)))
  expect_true(any(grepl("^\\| B \\| rank \\| no \\| 3 \\| 2 \\| 1 \\| 1 \\| 1 \\| 0 \\|$", out)))
  rows <- grep("^\\| 0[0-9]{3} ", out, value = TRUE)
  expect_equal(substr(rows, 3, 6), c("0068", "0084", "0073", "0200"))   # 0271: no flight
  expect_match(rows[2], "\\| 0.831 \\| no \\| yes \\| 1.42 \\| yes \\| no \\| second_peak \\|$")
})

test_that("disturbance: the checks per plot, records named, near fires listed", {
  out <- rep2_sec_disturbance(list(disturbance.csv = fake_dist()))
  expect_true(any(grepl(paste0("^\\| 0068 \\| EP \\| A \\| yes \\| 2019-01-01 to 2022-08-19 ",
                               "\\| 0 \\| yes \\| 0 \\| no \\| yes \\| 400 \\| 12 \\| 3.0% ",
                               "\\| pass \\| yes \\|"), out)))
  expect_true(any(grepl(paste0("^\\| 0271 \\| OH \\| B \\| no \\| ", REP_DASH), out)))
  expect_true(any(grepl("^\\| 0077 \\| ", out) & grepl("Salvage Cut", out)))
  expect_match(paste(out, collapse = " "), "pass 1, fail 0, not checked 0, not run 2")
  near <- rep2_sec_near(list(disturbance_records_detail.csv = fake_detail(),
                             disturbance.csv = fake_dist()))
  rows <- grep("^\\| 0", near, value = TRUE)
  expect_equal(length(rows), 1L)                        # 0068 within 1 km; 0197, 0271 not shown
  expect_match(rows[1], "\\| 0068 \\| fire_wfigs \\| NEAR \\| 2021-07-02 \\| yes \\| no \\| 97 \\|")
})

test_that("the document builds from no input at all, every section saying what is missing", {
  doc <- rep2_document(list())
  heads <- grep("^#", doc, value = TRUE)
  expect_true(all(c("## 1. Decision (groups A and B)", "## 2. Crown-frame test",
                    "## 3. Registering catalogue plots",
                    "## 4. Disturbance between survey and flight",
                    "## 5. Decision, gate costs, cells and reference stems",
                    "## Inputs") %in% heads))
  expect_true(all(c("### (a) Crown-frame truth per plot", "### (b) Test units per signal",
                    "### (c) Pass rule per signal and subset",
                    "### (d) Registration of the candidate plots of groups A and B",
                    "### (e) Disturbance records and canopy over mapped trees",
                    "### What each gate costs") %in% heads))
  expect_gte(sum(grepl("^Not produced", doc)), 8L)
  expect_true("Not recorded." %in% doc)
  expect_false(any(nchar(doc[!startsWith(doc, "|")]) > 80))
})

test_that("the driver writes P2/report_tables.md with the inputs' SHA-256 and guards OUT", {
  job <- tempfile("ofo-rep2-")
  p2 <- file.path(job, "ofo", "preflight2")
  dir.create(p2, recursive = TRUE)
  on.exit(unlink(job, recursive = TRUE), add = TRUE)
  data.table::fwrite(fake_reg(), file.path(p2, "registration.csv"))
  data.table::fwrite(fake_dist(), file.path(p2, "disturbance.csv"))
  jsonlite::write_json(fake_test(), file.path(p2, "crowntruth_test.json"), auto_unbox = TRUE,
                       null = "null")
  run <- function(args = character()) {
    out <- suppressWarnings(system2("Rscript", c(normalizePath(file.path("..", "..", "scripts",
      "report_ofo_preflight2.R")), args), env = paste0("CLAUDE_JOB_DIR=", job), stdout = TRUE,
      stderr = TRUE))
    list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"),
         out = paste(out, collapse = "\n"))
  }
  r <- run()
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "Signals admitted \\(crown-frame test\\): height yes, rank no")
  expect_match(r$out, "Registered candidate plots by group: A 1, B 0")
  doc <- readLines(file.path(p2, "report_tables.md"), encoding = "UTF-8")
  sha <- digest::digest(file = file.path(p2, "registration.csv"), algo = "sha256")
  expect_true(any(grepl(paste0("^\\| registration.csv \\| 5 \\| .* \\| ", sha, " \\|$"), doc)))
  expect_true(any(grepl("^\\| group_decision.csv \\| .* \\| missing \\|", doc)))
  expect_true(any(grepl("^\\| 0068 \\| EP \\| A \\| height \\|", doc)))
  r2 <- run(paste0("OUT=", file.path(job, "neon", "x.md")))
  expect_true(r2$status != 0); expect_match(r2$out, "OUT must lie under")
  r3 <- run("SITE=x")
  expect_true(r3$status != 0); expect_match(r3$out, "takes only OUT=")
  expect_false(dir.exists(file.path(job, "neon")))
})
