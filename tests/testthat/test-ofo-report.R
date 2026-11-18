source(file.path("..", "..", "scripts", "report_ofo_preflight.R"), local = TRUE)

# Synthetic catalogue tables in the contract's shape (every field a string, as
# the report reads them).
fake_plots <- function() {
  data.frame(
    plot_id = c("0001", "0002", "0003", "0004", "0005", "0006"),
    project_name = c("VP2022", "VP2022", "CRBLDG2022", "Cambria2021", "NEON2023", "ab2020"),
    contributor_plot_id = c("p1", "p|2", "c1", "h1", "n1", "a1"),
    screen = c("none", "none", "none", "nested_hyperplot", "in_benchmark", "none"),
    group = c("C", "C", "D", NA, NA, "A"),
    survey_year = c("2022", "2022", "2022", "2021", "2019", "2020"),
    plot_area_ha = c("0.29", "0.29", "1", "0.02", "0.04", "4"),
    live_floor_cm = c("25.4", "25.4", "11.4", NA, "10", "5"),
    heights_measured = c("TRUE", "TRUE", "FALSE", "FALSE", "TRUE", "TRUE"),
    n_trees = c("100", "1200", "300", "20", "40", "5000"),
    n_live_dbh10 = c("80", "1000", "250", "10", "30", "4000"),
    n_ref = c("60", "900", "250", "0", "30", "4000"),
    license_short = c("CC BY NC SA 4.0", "CC BY NC SA 4.0", "CC BY 4.0", "CC BY 4.0", "CC0 1.0",
                      "CC BY 4.0"),
    stringsAsFactors = FALSE)
}

fake_flights <- function() {
  p <- fake_plots(); p <- p[p$project_name != "NEON2023", ]
  data.frame(plot_id = p$plot_id, project_name = p$project_name,
             ept = c("SN4", "SN4", "SN2", "FEMA", "SN11"),
             workunit = c("SN4", "SN4", "SN2", "FEMA", "SN11"),
             ql = c("QL 1", "QL 1", "QL 1", "QL 2", "QL 1"),
             cloud_status = "ok", n_candidates = "1",
             dens_all = c("30.04", "40", "50", "6", "20"),
             dens_first = c("15", "20", "25", "4", "10"),
             flown_from = c("2021-11-05", "2021-11-03", "2022-06-01", "2018-01-27", "2022-06-10"),
             flown_to = c("2021-11-05", "2021-11-08", "2022-06-01", "2018-01-27", "2022-06-10"),
             gap_years = c("1", "1", "0", "3", "2"),
             flight_admitted = c("TRUE", "TRUE", "TRUE", "FALSE", "TRUE"),
             flight_reason = c(NA, NA, NA, "quality_level", NA), stringsAsFactors = FALSE)
}

test_that("counts, decimals and shares format as the report specifies", {
  expect_equal(rep_int(c(1234567, 0, NA, 12.6, "45")), c("1,234,567", "0", REP_DASH, "13", "45"))
  expect_equal(rep_num(c(1.26, 0, 0.04, -0.04, NA, 1234.56, Inf)),
               c("1.3", "0.0", "<0.1", ">-0.1", REP_DASH, "1,234.6", REP_DASH))
  expect_equal(rep_num(0.123, 2), "0.12")
  expect_equal(rep_pct(c(0.5, 1, 0.0004, NA, "0.25")),
               c("50.0%", "100.0%", "<0.1%", REP_DASH, "25.0%"))
  expect_equal(rep_yes(c("TRUE", "FALSE", NA, "x")), c("yes", "no", REP_DASH, REP_DASH))
  expect_equal(rep_year(c("2022", NA)), c("2022", REP_DASH))   # no thousands separator
  expect_equal(rep_range(c(3, 1, NA)), paste0("1.0", REP_NDASH, "3.0"))
  expect_equal(rep_range(c(5, 5)), "5.0")
  expect_equal(rep_range(c(NA, NA)), REP_DASH)
  expect_equal(rep_med_range(c(3, 1, 2, NA)), paste0("2.0 (1.0", REP_NDASH, "3.0)"))
  expect_equal(rep_tally(c("b", "a", "b", NA, "")), "a (1), b (2)")
  expect_equal(rep_tally(rep(NA, 2)), REP_DASH)
  expect_equal(rep_uniq_num(c("10.2", NA, "25.4", "10.2")), "10.2, 25.4, none")
  expect_equal(rep_uniq(c("b", "B", "a", NA)), "B, a, b")      # C-locale order
})

test_that("markdown tables escape pipes and handle one and zero rows", {
  t <- rep_md_table(data.frame(a = c("x|y", NA), "b c" = c("1", ""), check.names = FALSE))
  expect_equal(t, c("| a | b c |", "| --- | --- |",
                    paste0("| x\\|y | 1 |"), paste0("| ", REP_DASH, " | ", REP_DASH, " |")))
  expect_equal(rep_md_table(data.frame(a = "1")), c("| a |", "| --- |", "| 1 |"))
  expect_equal(rep_md_table(data.frame(a = character()), "None."), "None.")
  expect_equal(rep_md_table(NULL), "No rows.")
})

test_that("a section with a missing input keeps its heading and names what is missing", {
  expect_equal(rep_sec_decision(list()),
               c("### Decision per group", "",
                 "Not produced: `group_decision.csv` is missing.", ""))
  d <- data.frame(group = "A", decision = "go", reasons = "r", signal = "height",
                  signal_admitted = "TRUE", plots_admitted = "3", plots_with_headline = "3",
                  ref_headline = "120", stringsAsFactors = FALSE)
  out <- rep_sec_decision(list(group_decision.csv = d))
  expect_equal(out[3], "Not produced: `group_decision.csv` lacks column(s) `floor_cm`.")
  expect_match(rep_sec_known_truth(list())[3], "registration_tests.json` is missing")
  expect_match(rep_sec_agreement(list(registration_tests.json = list(admitted = list())))[3],
               "lacks `test3_agreement`")
  # The appendix still renders from plots and flights and names the missing tables.
  ap <- rep_sec_appendix(list(plots.csv = fake_plots(), flights.csv = fake_flights()))
  expect_true(any(grepl("`plot_admission.csv` is missing", ap)))
  expect_true(any(grepl("`registration.csv` is missing", ap)))
  expect_equal(sum(grepl("^\\| 000[0-9] \\|", ap)), 5L)        # NEON2023 left out
  expect_true(any(grepl("| p\\|2 |", ap, fixed = TRUE)))
})

test_that("the whole document builds from no input at all", {
  doc <- rep_document(list())
  expect_true(all(c("## 1. Decision", "### Decision per group", "### Flights by project",
                    "### Appendix: every non-NEON plot", "### What each gate costs")
                  %in% doc))
  heads <- grep("^### ", doc)
  # Every table heading is followed by a blank line and then a "Not produced" line.
  expect_true(all(grepl("^Not produced", doc[heads + 2])))
})

test_that("rows are ordered deterministically whatever the input order", {
  p <- fake_plots()
  set.seed(3)
  a <- rep_sec_catalogue(list(plots.csv = p))
  b <- rep_sec_catalogue(list(plots.csv = p[sample(nrow(p)), ]))
  expect_identical(a, b)
  proj <- sub("^\\| ([^ ]+) .*$", "\\1", grep("^\\| [A-Za-z]", a, value = TRUE))[-1]
  expect_equal(proj[1:5], c("CRBLDG2022", "Cambria2021", "NEON2023", "VP2022", "ab2020"))
  d <- data.frame(group = c("D", "B", "A", "C"), decision = "no-go", reasons = "r",
                  signal = "rank", signal_admitted = "FALSE", plots_admitted = "0",
                  plots_with_headline = "0", ref_headline = "0", floor_cm = NA,
                  stringsAsFactors = FALSE)
  out <- rep_sec_decision(list(group_decision.csv = d))
  expect_equal(substr(grep("^\\| [A-D] ", out, value = TRUE), 3, 3), c("A", "B", "C", "D"))
  g <- rep_sec_groups(list(plots.csv = p, flights.csv = fake_flights()))
  rows <- grep("^\\| [A-D] \\|", g, value = TRUE)
  expect_equal(substr(rows, 3, 3), c("A", "C", "D"))
  expect_match(rows[2], "| C | VP2022 (2) | 2 | 2 | 960 |", fixed = TRUE)
})

test_that("flight rows summarise densities, months and reasons", {
  f <- rep_sec_flights(list(flights.csv = fake_flights()))
  vp <- grep("^\\| VP2022 ", f, value = TRUE)
  expect_match(vp, "| SN4 (2) | QL 1 (2) | 2021-11 | 1 | 35.0 (30.0", fixed = TRUE)
  cam <- grep("^\\| Cambria2021 ", f, value = TRUE)
  expect_match(cam, "| 0 | quality_level (1) |", fixed = TRUE)
  expect_true(any(grepl("NEON comparison not added", f)))
})

test_that("NEON plot-clip densities are quoted cell by cell", {
  lines <- c("Intro.", "",
             "| Site | Forest | Plot clips, all returns per m² | Plot clips, first returns per m² |",
             "| --- | --- | --- | --- |",
             "| WREF | Old | median 17.9, range 10.2–25.8 | median 9.8, range 5.3–15.2 |",
             "| D17, for comparison | Mixed | median 18.2 | median 11.5 |", "", "Text.")
  q <- rep_quote_neon_density(lines)
  expect_equal(q$site, c("WREF", "D17, for comparison"))
  expect_equal(q$all, c("median 17.9, range 10.2–25.8", "median 18.2"))
  expect_equal(q$first, c("median 9.8, range 5.3–15.2", "median 11.5"))
  expect_null(rep_quote_neon_density(c("| a | b |", "| --- | --- |")))
  expect_null(rep_quote_neon_density(NULL))
})

test_that("citations are taken from the licence text only where it gives one", {
  lic <- c("CC BY 4.0",
           "Public. If you use these data please use the following citation: Doe, J. 2021. X.",
           "CC BY NC SA 4.0 license. The entity to acknowledge for dataset attribution is Org",
           "CC BY 4.0; Roe, R. (2023). Data. Dryad.", NA)
  expect_equal(rep_citation(lic, c("CC BY 4.0", "Public domain", "CC BY NC SA 4.0",
                                   "CC BY 4.0", NA)),
               c(NA, "Doe, J. 2021. X.", "Acknowledge Org", "Roe, R. (2023). Data. Dryad.", NA))
})

test_that("failed gates carry their own stage's reason", {
  a <- data.frame(reason = c("", "screen_ok;registered", "flight_admitted;geometry_consistent"),
                  screen = c("none", "no_status", "none"),
                  flight_reason = c(NA, NA, "gap"), conditions_reason = NA,
                  registration_reason = c(NA, "signal_not_admitted", NA),
                  stringsAsFactors = FALSE)
  expect_equal(rep_gate_reasons(a),
               c(REP_DASH, "screen_ok (no_status); registered (signal_not_admitted)",
                 "flight_admitted (gap); geometry_consistent"))
})

test_that("Amendment 1 tables are summarised when present, whatever their file names", {
  units <- data.frame(unit = c("ABBY_001", "ABBY_002", "C-ABBY_001"),
                      set = c("development", "confirmation", "development"),
                      kind = c("plot", "plot", "composite"), site = "ABBY",
                      n_members = c("1", "1", "3"), stringsAsFactors = FALSE)
  dev <- data.frame(unit = c("u1", "u2", "u3", "u4"), set = "development",
                    method = c("m2", "m1", "m1", "m1"), signal = "height",
                    accepted = c("TRUE", "TRUE", "FALSE", "TRUE"),
                    error_m = c("0.5", "1.5", "4", "3"), stringsAsFactors = FALSE)
  js <- list(amendment1 = list(frozen = list(min_stems = 30L),
                               units = list(list(a = 1), list(a = 2))))
  out <- rep_sec_amendment(list(registration_units.csv = units, registration_dev_a.csv = dev,
                                registration_tests.json = js))
  expect_true("### Registration, Amendment 1: units" %in% out)
  expect_true("| development | plot | ABBY | 1 | 1 |" %in% out)
  expect_true("### Registration, Amendment 1: dev_a" %in% out)
  # Methods in C-locale order; accepted errors summarised, unaccepted ignored.
  rows <- grep("^\\| development \\| m", out, value = TRUE)
  expect_equal(rows, c("| development | m1 | height | 3 | 3 | 3.0 | 2 | 2.2 | 1 (50.0%) |",
                       "| development | m2 | height | 1 | 1 | 0.5 | 1 | 0.5 | 1 (100.0%) |"))
  expect_true("| frozen.min_stems | 30 |" %in% out)
  expect_match(paste(out, collapse = " "), "2 array entries left out", fixed = TRUE)
  # Without a gate column the run units are summarised; other tables as written.
  ungated <- rep_sec_amendment(list(registration_dev.csv = dev[, -5]))
  expect_true("| development | m2 | height | 1 | 1 | 0.5 | 1 (100.0%) |" %in% ungated)
  sweep <- data.frame(stat = c("z", "residual_m"), threshold = c("3", "1.25"),
                      n_accepted = c("12", "9"), share = c("0.5", "0.75"),
                      keep = c("TRUE", "FALSE"), unit = c("0001", "0002"),
                      stringsAsFactors = FALSE)
  v <- rep_sec_amendment(list(registration_dev_gates.csv = sweep))
  expect_true("| stat | threshold | n_accepted | share | keep | unit |" %in% v)
  expect_true("| z | 3.00 | 12 | 0.50 | yes | 0001 |" %in% v)
  expect_equal(nrow(rep_verbatim(sweep[rep(1:2, 50), ], max_rows = 80)), 80L)
  expect_match(rep_sec_amendment(list())[3], "^Not produced: no `registration_units.csv`")
})

test_that("test records are found at the top level and under Amendment 1's blocks", {
  rec <- list(height = list(n_plots = 106, n_run = 30, n_accepted = 8, median_error_m = 1.9,
                            n_within_2m = 4, share_within_2m = 0.5, pass = FALSE))
  rules <- list(known_truth = list(min_accepted = 20, max_median_error = 1, min_share = 0.9))
  top <- rep_sec_known_truth(list(registration_tests.json =
                                    list(test1_known_truth = rec, pass_rules = rules)))
  expect_true("| height | 106 | 30 | 8 | 1.9 | 50.0% (4 of 8) | fail |" %in% top)
  expect_true(paste("| Pass rule |", REP_DASH, "|", REP_DASH, "| at least 20 | at most 1.0 |",
                    "at least 90.0% |", REP_DASH, "|") %in% top)
  moved <- list(declared = list(test1_known_truth = rec, pass_rules = rules),
                amendment1 = list(test1_known_truth = list(height = modifyList(
                  rec$height, list(n_accepted = 12, pass = TRUE)))))
  both <- rep_sec_known_truth(list(registration_tests.json = moved))
  expect_true("| declared | height | 106 | 30 | 8 | 1.9 | 50.0% (4 of 8) | fail |" %in% both)
  expect_true("| amendment1 | height | 106 | 30 | 12 | 1.9 | 50.0% (4 of 12) | pass |" %in% both)
  expect_match(rep_sec_known_truth(list(registration_tests.json = list(
    test1_known_truth = list(height = list(n_run = 1)))))[3], "lacks per-signal field")
})

test_that("gate costs follow the file's gate order and count plots left", {
  a <- data.frame(plot_id = c("0001", "0002", "0003", "0004"), project_name = "P",
                  group = c("A", "A", "A", NA),
                  screen_ok = c("TRUE", "TRUE", "TRUE", "FALSE"),
                  flight_admitted = c("TRUE", "FALSE", "TRUE", "TRUE"),
                  registered = c("TRUE", "TRUE", "FALSE", "FALSE"),
                  admitted = c("TRUE", "FALSE", "FALSE", "FALSE"), reason = "",
                  stringsAsFactors = FALSE)
  g <- rep_sec_gates(list(plot_admission.csv = a))
  expect_true(paste("| Group | Step | Gate | Failing this gate, at any step |",
                    "Removed at this step | Plots left |") %in% g)
  expect_true("| A | 2 | flight_admitted | 1 | 1 | 2 |" %in% g)
  expect_true("| A | 3 | registered | 1 | 1 | 1 |" %in% g)
  expect_true(paste0("| ", REP_DASH, " | 1 | screen_ok | 1 | 1 | 0 |") %in% g)
  # A plot failing a gate after an earlier one is counted there, not removed again.
  expect_true(paste0("| ", REP_DASH, " | 3 | registered | 1 | 0 | 0 |") %in% g)
  expect_true("| all groups | 0 | plots | — | — | 3 |" %in% g)
})

test_that("flights: an admitted-flights row and the withheld share", {
  ff <- fake_flights()
  ff$withheld_share <- c("0.02", "0.30", "0.05", "0.5", "0.12")
  f <- rep_sec_flights(list(flights.csv = ff))
  i <- grep("^\\| Admitted flights \\| 4 \\| 3 work units", f)
  expect_length(i, 1)
  expect_match(f[i], "| Admitted flights | 4 | 3 work units | QL 1 (4) |", fixed = TRUE)
  expect_match(f[i], paste0("| 35.0 (20.0", REP_NDASH, "50.0) |"), fixed = TRUE)
  # Right after the all-plots row (so above the NEON rows when they are quoted).
  expect_equal(grep("^\\| All non-NEON plots ", f) + 1L, i)
  expect_true("| Flights | Plots | Median withheld share | Maximum (plot) | Plots above 10% |"
              %in% f)
  expect_true("| Plots with a cloud | 5 | 12.0% | 50.0% (0004) | 3 |" %in% f)
  expect_true("| Admitted flights | 4 | 8.5% | 30.0% (0002) | 2 |" %in% f)
  expect_match(rep_sec_flights(list(flights.csv = fake_flights())),
               "withheld-share table needs `withheld_share`", all = FALSE)
})

test_that("headline numbers carry the admitted flights' densities", {
  ff <- fake_flights()
  ff$dens_first[5] <- "7.5"
  ff$n_points_polygon_raw <- c("4000", "5000", "6000", "700", "3000")
  ff$polygon_area_m2 <- "100"
  h <- rep_headlines(list(flights.csv = ff))
  expect_true("Admitted flights: median returns per m², all and first: 35.0 and 17.5" %in% h)
  expect_true("Admitted flights: median returns per m² counting withheld returns: 45.0" %in% h)
  expect_true("Admitted flights below 8 returns per m², all and first: 0 and 1" %in% h)
  expect_match(rep_headlines(list())[1], "n/a")
})

test_that("development tables: by variant ungated, and under the frozen configuration", {
  dev <- data.frame(
    variant = c("v1", "v1", "v1", "v2", "v2", "v1"),
    signal = c("height", "height", "height", "height", "height", "rank"),
    unit = c("u1", "u2", "u3", "u1", "u2", "u1"),
    n_signal = c("20", "30", "10", "20", "30", "20"), dx = c("1", "1", "1", "1", NA, "1"),
    error_m = c("0.5", "3", "0.1", "0.4", NA, "1.0"), stringsAsFactors = FALSE)
  v <- rep_sec_dev_variants(list(registration_dev.csv = dev))
  rows <- grep("^\\| (height|rank) ", v, value = TRUE)
  expect_equal(rows, c("| height | v2 | 1 | 0.40 | 100.0% |", "| height | v1 | 2 | 1.75 | 50.0% |",
                       "| rank | v1 | 1 | 1.00 | 100.0% |"))
  expect_match(rep_sec_dev_variants(list())[3], "^Not produced")

  d2 <- data.frame(
    variant = "v1", signal = "height", unit = c("ABBY_1", "C-ABBY_1", "ABBY_2", "ABBY_3"),
    kind = c("plot", "composite", "plot", "plot"), site = "ABBY",
    n_signal = c("25", "60", "15", "22"), offset_dx = c("1", "0", "0", "0"),
    offset_dy = c("2", "0", "0", "0"), dx = c("-1", "0.3", "0", "5"),
    dy = c("-2", "3", "0", "0"), error_m = c("0.5", "3.015", "0.2", "5"),
    residual_m = "0.4", sub_p90_m = "0.5", accepted = c("TRUE", "TRUE", "FALSE", "FALSE"),
    stringsAsFactors = FALSE)
  units <- data.frame(unit = c("ABBY_1", "C-ABBY_1"), members = c("ABBY_1", "ABBY_1;ABBY_2"),
                      stringsAsFactors = FALSE)
  js <- list(amendment1 = list(method = list(frozen = list(height = list(
    variant = "v1", gate = list(stat = "sub_p90_m", threshold = 2, min_stems = 20))))))
  fz <- rep_sec_dev_frozen(list(registration_dev.csv = d2, registration_units.csv = units,
                                registration_tests.json = js))
  expect_true("| height | v1 | `sub_p90_m` at most 2.0 m | 20 | 3 | 2 | 1.76 | 1 (50.0%) |"
              %in% fz)
  expect_true(paste("| height | C-ABBY_1 | composite | ABBY_1, ABBY_2 | ABBY | 60 | 3.02 |",
                    "0.30 | 3.00 | 0.40 | 0.50 |") %in% fz)
  # Without the test record the frozen constants of the library are used.
  lib <- rep_sec_dev_frozen(list(registration_dev.csv = d2))
  expect_true(any(startsWith(lib, sprintf("| height | %s | `sub_p90_m` at most %s m | %s | 0 | 0 |",
                                          OFO_REG2$height$variant,
                                          rep_num(OFO_REG2$height$gate$threshold),
                                          OFO_REG2$height$gate$min_stems))))
  expect_true("No accepted development unit has an error above 2 m." %in% lib)
  expect_equal(rep_members(units, c("C-ABBY_1", "ABBY_1", "C-X"),
                           c("composite", "plot", "composite")),
               c("ABBY_1, ABBY_2", REP_DASH, REP_DASH))
  expect_equal(rep_members(NULL, "C-ABBY_1", "composite"), REP_DASH)
})

test_that("indicative cells follow the tiling rule on the unshifted polygon", {
  sqw <- paste("POLYGON ((500000 4200000, 500100 4200000, 500100 4200100, 500000 4200100,",
               "500000 4200000))")
  circ <- sf::st_as_text(sf::st_buffer(sf::st_sfc(sf::st_point(c(501000, 4200000)), crs = 32610),
                                       11.3), digits = 15)
  p <- data.frame(plot_id = c("0001", "0002", "0003", "0004"),
                  project_name = c("P1", "P2", "P1", "P1"), group = c("C", "C", "C", NA),
                  epsg = "32610", polygon_wkt = c(sqw, circ, sqw, sqw),
                  polygon_area_m2 = c("10000", "402", "10000", "10000"), stringsAsFactors = FALSE)
  fl <- data.frame(plot_id = p$plot_id, flight_admitted = c("TRUE", "TRUE", "FALSE", "TRUE"),
                   stringsAsFactors = FALSE)
  x <- rep_cells_possible(p, fl)
  expect_equal(x$plot_id, c("0001", "0002"))
  expect_equal(x$n_cells, c(4L, 0L))
  s <- rep_sec_cells_possible(list(plots.csv = p, flights.csv = fl))
  expect_true("| C | P1 | 1 | 1 | 4 | 10,000 |" %in% s)
  expect_true("| C | P2 | 1 | 0 | 0 | 402 |" %in% s)
  expect_true(paste0("| C | all projects | 2 | 1 | 4 | 402", REP_NDASH, "10,000 |") %in% s)
  expect_match(paste(s, collapse = " "), "Indicative only")
})

test_that("conditions: dates of held plots and the order of the surfaces", {
  p <- fake_plots()
  fl <- fake_flights()
  c0 <- data.frame(
    plot_id = c("0001", "0006", "0003", "0002"), project_name = "X",
    disturbance_status = c("undisturbed", "undisturbed", "disturbed", "not_checked"),
    mission_date = c("2023-06-01", "2025-05-01", "2019-06-01", NA),
    early_surface = c("3dep", "3dep", "drone", NA), survey_year = c("2022", "2020", "2022", "2022"),
    flight_year = c("2021", "2022", "2022", "2021"), survey_date = "2022-07-01",
    flown_from = "2021-11-05", interval_covered = c("FALSE", "FALSE", "TRUE", NA),
    loss_share = "0.01", reverse_share = "0", snow_status = "not_winter", snow_depth_max_m = NA,
    leafoff_status = "leaf_on", deciduous_share = "0",
    conditions_admitted = c("TRUE", "FALSE", "FALSE", "FALSE"),
    conditions_reason = c(NA, "interval_not_covered", "disturbed", "no_usable_drone_model"),
    stringsAsFactors = FALSE)
  tabs <- list(conditions.csv = c0, plots.csv = p, flights.csv = fl)
  o <- rep_sec_disturbance_order(tabs)
  expect_true(paste0("| All checked plots | 3 | 2 | 1 | 1", REP_NDASH, "5 | 2", REP_NDASH,
                     "3 |") %in% o)
  expect_true("| Groups A and B with an admitted flight | 1 | 1 | 0 | 5 | 3 |" %in% o)
  h <- rep_sec_conditions_held(tabs)
  expect_match(h[3], "| Survey date | Flight date | Mission date | Interval covered |",
               fixed = TRUE)
  expect_true(any(startsWith(h, paste("| 0006 | X | A | yes | 2022-07-01 | 2021-11-05 |",
                                      "2025-05-01 | no |"))))
})

test_that("known-truth plots are counted by signal stems", {
  n <- data.frame(plot = rep(c("p1", "p2", "p3", "p4"), 2),
                  signal = rep(c("height", "rank"), each = 4),
                  n_signal = c("10", "15", "30", "60", "14", "15", "16", "100"),
                  stringsAsFactors = FALSE)
  k <- rep_sec_known_truth_stems(list(registration_neon.csv = n))
  expect_true(paste("| Signal | Plots | At least 15 signal stems | At least 30 signal stems |",
                    "At least 60 signal stems |") %in% k)
  expect_true("| height | 4 | 3 | 2 | 1 |" %in% k)
  expect_true("| rank | 4 | 3 | 1 | 1 |" %in% k)
})

test_that("held-out catalogue plots are listed per plot, signal and method", {
  rc <- data.frame(plot_id = c("0300", "0100", "0100", "0200"),
                   project_name = c("P3", "P1", "P1", "P2"),
                   set = c("heldout", "heldout", "heldout", "candidate"),
                   signal = c("rank", "rank", "rank", "height"),
                   method = c("amendment1", "declared", "amendment1", "amendment1"),
                   screen = c("no_status", "nested_hyperplot", "nested_hyperplot", "none"),
                   n_signal = c(40, 25, 25, 90), dx = c(12, -1.26, 0.5, 1), dy = c(0.5, 2, -0.25, 1),
                   shift_m = c(12.01, 2.36, 0.56, 1.41), residual_m = c(3.2, 1.1, 0.4, 0.2),
                   on_edge = c(TRUE, FALSE, FALSE, FALSE), accepted = c(FALSE, TRUE, TRUE, TRUE),
                   reject_reason = c("on_edge", "", "", ""),
                   flight_admitted = c(FALSE, FALSE, FALSE, TRUE), stringsAsFactors = FALSE)
  out <- rep_sec_heldout(list(registration_catalog.csv = rc))
  expect_identical(out[1], "### Registration: held-out catalogue plots")
  rows <- grep("^\\| 0", out, value = TRUE)
  # The candidate plot is left out; rows sort by plot, signal and method.
  expect_length(rows, 3)
  expect_match(rows[1], "^\\| 0100 \\| P1 \\| nested_hyperplot \\| rank \\| amendment1 \\| 25 \\| 0.5 \\|")
  expect_match(rows[2], "\\| declared \\| 25 \\| -1.3 \\| 2.0 \\| 2.4 \\| 1.1 \\| no \\| yes \\|")
  # On edge no, accepted yes, no reason, flight not admitted.
  expect_match(rows[1], "\\| no \\| yes \\| — \\| no \\|$")
  expect_match(rows[3], "^\\| 0300 .* \\| 12.0 \\| 0.5 \\| 12.0 \\| 3.2 \\| yes \\| no \\| on_edge \\| no \\|$")
  # Older tables without the optional columns still give a table.
  old <- rc[, setdiff(names(rc), c("method", "screen", "on_edge", "flight_admitted"))]
  expect_length(grep("^\\| 0", rep_sec_heldout(list(registration_catalog.csv = old))), 3)
  expect_match(paste(rep_sec_heldout(list()), collapse = " "), "is missing")
})

test_that("OUT may not reach the job directory outside OFO by any path", {
  job <- tempfile("rep-job-")
  scratch <- tempfile("rep-out-")
  dir.create(file.path(job, "ofo", "preflight"), recursive = TRUE)
  dir.create(file.path(job, "neon", "frozen_2021"), recursive = TRUE)
  dir.create(scratch)
  on.exit(unlink(c(job, scratch), recursive = TRUE), add = TRUE)
  ofo <- file.path(job, "ofo")
  ok <- function(p) isTRUE(tryCatch(rep_check_out(p, job, ofo), error = function(e) FALSE))
  expect_true(ok(file.path(ofo, "preflight", "r.md")))
  expect_true(ok(file.path(scratch, "r.md")))
  expect_false(ok(file.path(ofo, "preflight", "r.txt")))
  expect_false(ok(file.path(job, "neon", "frozen_2021", "x.md")))
  expect_false(ok(file.path(ofo, "..", "neon", "frozen_2021", "x.md")))
  expect_false(ok(file.path(job, "x.md")))
  old <- setwd(job); on.exit(setwd(old), add = TRUE)
  expect_false(ok("neon/frozen_2021/x.md"))
  expect_true(ok("ofo/x.md"))
  setwd(ofo)
  expect_false(ok("../neon/frozen_2021/x.md"))
  link <- file.path(scratch, "into-neon")
  if (isTRUE(file.symlink(file.path(job, "neon"), link))) {
    expect_false(ok(file.path(link, "new", "x.md")))
  }
  expect_error(rep_check_out(file.path(job, "neon", "x.md"), job, ofo), "OUT must lie under")
})
