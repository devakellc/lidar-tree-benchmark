source(file.path("..", "..", "scripts", "ofo_reference_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_preflight_lib.R"), local = TRUE)   # stage records

## ---- synthetic geometry -------------------------------------------------------
OX <- 500000; OY <- 4200000         # both multiples of 40 m
ofo_sq <- function(x0, y0, w, h = w, crs = 32610)
  sf::st_sfc(sf::st_polygon(list(matrix(c(x0, y0, x0 + w, y0, x0 + w, y0 + h, x0, y0 + h,
                                          x0, y0), ncol = 2, byrow = TRUE))), crs = crs)
ofo_circle <- function(r, cx = OX, cy = OY)
  sf::st_buffer(sf::st_sfc(sf::st_point(c(cx, cy)), crs = 32610), r, nQuadSegs = 360)
ofo_poly <- function(xy) sf::st_sfc(sf::st_polygon(list(matrix(xy, ncol = 2, byrow = TRUE))),
                                    crs = 32610)

test_that("cells: circles, squares and rectangles give the declared counts", {
  r_small <- sqrt(2920 / pi)                       # 0.292 ha
  expect_equal(nrow(ofo_cells(ofo_circle(r_small))), 1L)
  expect_equal(nrow(ofo_cells(ofo_circle(r_small, OX + 12.3, OY + 7.7))), 1L)
  one_ha <- ofo_cells(ofo_circle(56.42))
  expect_equal(nrow(one_ha), 4L)
  # The 2 x 2 block misses the circle by a sliver far below 1%.
  expect_true(all(one_ha$inside_share < 1 & one_ha$inside_share > 0.999))
  expect_equal(nrow(ofo_cells(ofo_circle(56.42, OX + 12.3, OY + 7.7))), 4L)
  expect_equal(nrow(ofo_cells(ofo_sq(OX, OY, 100))), 4L)
  expect_equal(nrow(ofo_cells(ofo_sq(OX, OY, 100, 200))), 10L)
  # Off the 5 m lattice a 200 m side holds only four rows of cells.
  expect_equal(nrow(ofo_cells(ofo_sq(OX + 1.7, OY + 3.1, 100, 200))), 8L)
})

test_that("cells: an L-shaped polygon and one too small for any cell", {
  L <- ofo_poly(c(OX, OY, OX + 80, OY, OX + 80, OY + 40, OX + 40, OY + 40, OX + 40, OY + 80,
                  OX, OY + 80, OX, OY))
  ce <- ofo_cells(L)
  expect_equal(nrow(ce), 3L)
  # Numbered by cy, then cx.
  expect_equal(ce$cx, OX + c(20, 60, 20))
  expect_equal(ce$cy, OY + c(20, 20, 60))
  expect_equal(ce$k, 1:3)
  expect_equal(nrow(ofo_cells(ofo_sq(OX, OY, 39.9))), 1L)   # 99.5% of a cell
  expect_equal(nrow(ofo_cells(ofo_sq(OX, OY, 39.7))), 0L)   # 98.5%
  expect_equal(nrow(ofo_cells(ofo_circle(sqrt(400 / pi)))), 0L)   # 0.04 ha
  expect_named(ofo_cells(ofo_sq(OX, OY, 30)), c("k", "cx", "cy", "inside_share"))
})

test_that("cells: offset ties go to the smallest ox, then oy", {
  # Every offset 0..20 admits four cells in an aligned 100 m square: pick (0, 0).
  a <- ofo_cells(ofo_sq(OX, OY, 100))
  expect_equal(unname(attr(a, "offset")), c(0, 0))
  expect_equal(a$cx, OX + c(20, 60, 20, 60))
  # Shifted by 3 m: offsets 5..20 admit four; 5 is the smallest in both axes.
  b <- ofo_cells(ofo_sq(OX + 3, OY + 3, 100))
  expect_equal(unname(attr(b, "offset")), c(5, 5))
  expect_equal(b$cx, OX + c(25, 65, 25, 65))
  # Different slack per axis: x fits only at offset 10, y at 0..15 (pick 0).
  c3 <- ofo_cells(ofo_sq(OX + 8, OY, 82, 95))
  expect_equal(unname(attr(c3, "offset")), c(10, 0))
})

test_that("cells: admission at exactly 99% inside", {
  notch <- function(w, h) ofo_poly(c(OX, OY, OX + 40, OY, OX + 40, OY + 40 - h,
                                     OX + 40 - w, OY + 40 - h, OX + 40 - w, OY + 40, OX, OY + 40,
                                     OX, OY))
  expect_equal(nrow(ofo_cells(notch(4, 4))), 1L)       # 16 m2 out: 99.0%
  expect_equal(nrow(ofo_cells(notch(4, 4.25))), 0L)    # 17 m2 out
  expect_error(ofo_cells(sf::st_transform(ofo_sq(OX, OY, 100), 4326)), "projected")
})

test_that("shifted polygons keep their frame and move rigidly", {
  p <- ofo_shift_polygon(ofo_sq(OX, OY, 100), 2.5, -1)
  expect_equal(sf::st_crs(p)$epsg, 32610L)
  expect_equal(unname(as.numeric(sf::st_bbox(p))), c(OX + 2.5, OY - 1, OX + 102.5, OY + 99))
  expect_error(ofo_shift_polygon(p, NA, 0), "finite")
})

test_that("stems go to the lower cell on a shared edge and never outside the polygon", {
  poly <- ofo_poly(c(OX, OY, OX + 80, OY, OX + 80, OY + 76, OX + 76, OY + 76, OX + 76, OY + 80,
                     OX, OY + 80, OX, OY))              # 16 m2 notch in the top-right cell
  ce <- ofo_cells(poly)
  expect_equal(nrow(ce), 4L)
  x <- OX + c(10, 40, 40, 80, 79, 81, 20, NA, 0)
  y <- OY + c(10, 10, 40, 10, 79, 10, 81, 10, 0)
  k <- ofo_assign_cells(x, y, ce, poly)
  # interior; edge 1|2; corner of all four; outer edge; notch (outside polygon);
  # outside the cells; outside; no position; outer corner.
  expect_equal(k, c(1L, 1L, 1L, 2L, NA, NA, NA, NA, 1L))
  expect_equal(ofo_assign_cells(x, y, ce[0, ], poly), rep(NA_integer_, length(x)))
})

## ---- crown class ----------------------------------------------------------------
test_that("crown positions map to classes and NEON labels", {
  cc <- ofo_crown_class(c(1, 2, 3, 4, 5, 0, 6, NA), rep(NA, 8), rep("p", 8))
  expect_equal(cc$crown_class, c("dominant", "dominant", "codominant", "intermediate",
                                 "suppressed", NA, NA, NA))
  expect_equal(cc$crown_source, c(rep("canopyPosition", 5), rep("none", 3)))
  expect_true(all(nzchar(cc$canopyPosition[1:5])))
  expect_true(all(is.na(cc$canopyPosition[6:8])))
  # The NEON label maps back to the same class through neon_ground_truth.R's table.
  neon <- c("Open grown" = "dominant", "Full sun" = "dominant",
            "Partially shaded" = "codominant", "Mostly shaded" = "intermediate",
            "Full shade" = "suppressed")
  expect_equal(unname(neon[cc$canopyPosition[1:5]]), cc$crown_class[1:5])
})

test_that("height fallback follows neon_ground_truth.R and needs four stems per plot", {
  h <- c(5, 10, 15, 20, 25, 30, 12, 14, 16)
  p <- c(rep("a", 6), rep("b", 3))
  cp <- c(NA, NA, NA, NA, NA, 2, NA, NA, NA)
  cc <- ofo_crown_class(cp, h, p)
  # Plot a: five unclassified stems with heights; quantiles over those five.
  q <- quantile(h[1:5], c(.33, .66, .9))
  want <- as.character(cut(h[1:5], c(-Inf, q, Inf),
                           labels = c("suppressed", "intermediate", "codominant", "dominant")))
  expect_equal(cc$crown_class[1:5], want)
  expect_equal(cc$crown_source[1:6], c(rep("height_fallback", 5), "canopyPosition"))
  expect_true(all(is.na(cc$canopyPosition[1:5])))
  # Plot b: three stems, fewer than four -> no class.
  expect_true(all(is.na(cc$crown_class[7:9])))
  expect_equal(cc$crown_source[7:9], rep("none", 3))
  # Stems without a height never take a fallback class.
  cc2 <- ofo_crown_class(rep(NA, 5), c(1, 2, 3, 4, NA), rep("c", 5))
  expect_equal(cc2$crown_source, c(rep("height_fallback", 4), "none"))
  # Tied quantiles (rounded heights) do not abort, where cut() would.
  cc3 <- ofo_crown_class(rep(NA, 6), c(10, 10, 10, 10, 10, 20), rep("d", 6))
  expect_equal(cc3$crown_class, c(rep("suppressed", 5), "dominant"))
})

test_that("without the fallback a class comes from a recorded crown position only", {
  h <- c(5, 10, 15, 20, 25, 30, 12, 14, 16, 18, 20)
  p <- c(rep("a", 6), rep("b", 5))
  cp <- c(NA, NA, NA, NA, NA, 2, NA, 4, NA, NA, NA)
  off <- ofo_crown_class(cp, h, p, fallback = FALSE)
  expect_equal(off$crown_class, c(NA, NA, NA, NA, NA, "dominant", NA, "intermediate",
                                  NA, NA, NA))
  expect_equal(off$crown_source, ifelse(is.na(cp), "none", "canopyPosition"))
  expect_equal(off$canopyPosition[c(6, 8)], c("Full sun", "Mostly shaded"))
  # Per stem: plot b keeps its fallback, plot a has none, and a's heights stay
  # out of b's quantiles (b's classes equal those of b alone).
  mix <- ofo_crown_class(cp, h, p, fallback = p == "b")
  expect_equal(mix$crown_source[1:6], off$crown_source[1:6])
  alone <- ofo_crown_class(cp[7:11], h[7:11], p[7:11])
  expect_equal(mix$crown_class[7:11], alone$crown_class)
  expect_equal(mix$crown_source[c(7, 9, 10, 11)], rep("height_fallback", 4))
  # The default is unchanged.
  expect_identical(ofo_crown_class(cp, h, p), ofo_crown_class(cp, h, p, fallback = TRUE))
})

## ---- admission and floors ----------------------------------------------------------
adm_fixture <- function() {
  ids <- sprintf("%04d", 1:9)
  plots <- data.frame(plot_id = ids,
    project_name = c(rep("P1", 7), "NEON2023", "P2"),
    screen = c(rep("none", 7), "in_benchmark", "not_exhaustive"),
    group = c("A", "A", "A", "A", "A", "C", "C", NA, NA), stringsAsFactors = FALSE)
  flights <- data.frame(plot_id = ids, flight_admitted = c(TRUE, TRUE, TRUE, TRUE, FALSE,
    TRUE, TRUE, TRUE, TRUE), flight_reason = c(NA, NA, NA, NA, "gap", NA, NA, NA, NA))
  geometry <- data.frame(plot_id = ids, geometry_consistent = c(TRUE, TRUE, TRUE, TRUE, TRUE,
    TRUE, NA, TRUE, TRUE))
  conditions <- data.frame(plot_id = ids[-9],
    disturbance_status = c("undisturbed", "not_checked", "undisturbed", "disturbed",
                           "not_checked", "undisturbed", "undisturbed", "undisturbed"),
    interval_covered = c(TRUE, NA, TRUE, TRUE, NA, FALSE, TRUE, TRUE),
    same_year = FALSE,
    disturbance_admitted = c(TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE),
    snow_status = c("not_winter", "not_winter", "unknown", "not_winter", "not_winter",
                    "snow_free", "not_winter", "not_winter"),
    leafoff_status = "leaf_on",
    conditions_admitted = c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE),
    conditions_reason = NA, stringsAsFactors = FALSE)
  registration <- data.frame(plot_id = ids[c(1:4, 6)], registered = c(TRUE, TRUE, TRUE, TRUE,
    TRUE), reason = NA)
  list(plots = plots, flights = flights, geometry = geometry, conditions = conditions,
       registration = registration)
}

test_that("admission joins the gates, names failures and marks unchecked-only plots", {
  f <- adm_fixture()
  a <- ofo_plot_admission(f$plots, f$flights, f$geometry, f$conditions, f$registration)
  expect_false("0008" %in% a$plot_id)                     # NEON2023 excluded
  expect_equal(names(a)[1:11], c("plot_id", "project_name", "group", "screen", OFO_GATES,
                                 "admitted", "reason"))
  expect_equal(a$admitted, c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_equal(a$reason, c("", "conditions_admitted", "conditions_admitted",
    "conditions_admitted", "flight_admitted;conditions_admitted;registered",
    "conditions_admitted", "geometry_consistent;registered",
    "screen_ok;conditions_admitted;registered"))
  expect_equal(a$conditions_check, c("pass", "unchecked", "unchecked", "evidence", "unchecked",
                                     "unchecked", "pass", "missing"))
  # Only plots whose sole failure is an unchecked condition can make a group hold.
  expect_equal(a$unchecked_only, c(FALSE, TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE))
  # Lead's ruling: a disturbance check that failed on our side counts as
  # unchecked (it can make a group hold) ...
  f$conditions$conditions_reason[2] <- "disturbance_check_failed"
  a2 <- ofo_plot_admission(f$plots, f$flights, f$geometry, f$conditions, f$registration)
  expect_equal(a2$conditions_check[2], "unchecked")
  expect_true(a2$unchecked_only[2])
  # ... while a flight failing only on a missing flight date is a failure on
  # evidence, never unchecked.
  f$flights$flight_admitted[3] <- FALSE
  f$flights$flight_reason[3] <- "no_flight_date"
  f$conditions[3, c("snow_status", "conditions_admitted")] <- list("not_winter", TRUE)
  a3 <- ofo_plot_admission(f$plots, f$flights, f$geometry, f$conditions, f$registration)
  expect_equal(a3$reason[3], "flight_admitted")
  expect_false(a3$unchecked_only[3])
})

test_that("conditions sub-status separates evidence from checks not made", {
  cnd <- data.frame(
    disturbance_status = c("unresolved", "undisturbed", "undisturbed", "not_checked",
                           "undisturbed", "undisturbed"),
    disturbance_admitted = c(FALSE, TRUE, TRUE, TRUE, TRUE, TRUE),
    snow_status = c("not_winter", "snow", "unknown", "not_winter", "snow_free", "unknown"),
    leafoff_status = c("leaf_on", "leaf_on", "leaf_off_held", "leaf_on", "leaf_off_minor",
                       "leaf_on"),
    conditions_admitted = c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE), stringsAsFactors = FALSE)
  # not_checked but admitted (same-year flight) passes; a pass that its own
  # columns contradict is flagged.
  expect_equal(ofo_conditions_check(cnd), c("evidence", "evidence", "evidence", "pass", "pass",
                                            "inconsistent"))
  cnd$snow_status[1] <- "deep"
  expect_error(ofo_conditions_check(cnd), "unknown status")
})

test_that("group floors come from admitted plots only", {
  x <- data.frame(group = c("A", "C", "C", "C", "D", "B"),
                  admitted = c(TRUE, TRUE, FALSE, TRUE, FALSE, FALSE),
                  live_floor_cm = c(5, 12.7, 30, 15.2, 20, 0))
  fl <- ofo_group_floors(x)
  expect_equal(fl$group, c("A", "B", "C", "D"))
  expect_equal(fl$floor_cm, c(10, 10, 15.2, NA))
  expect_equal(fl$n_admitted, c(1L, 0L, 2L, 0L))
  expect_equal(ofo_plot_floor(c("C", "D", NA), fl, c(D = 20)), c(15.2, 20, 10))
})

test_that("reference flag needs live, tree, inside and a diameter at the floor", {
  t <- data.frame(live = c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE),
                  is_tree = c(TRUE, TRUE, TRUE, FALSE, TRUE, TRUE),
                  inside = c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE),
                  dbh = c(10, 9.9, 30, 30, 30, NA))
  expect_equal(ofo_reference_flag(t, 10), c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_equal(ofo_reference_flag(t, NA), rep(FALSE, 6))
  # A floor computed in inches (5 * 2.54) still admits a stem recorded at 12.7.
  t1 <- data.frame(live = TRUE, is_tree = TRUE, inside = TRUE, dbh = 12.7)
  expect_true(ofo_reference_flag(t1, 5 * 2.54))
})

## ---- decision ------------------------------------------------------------------------
dec_adm <- function(n_admitted, stems, group = "A", unchecked = integer(),
                    licence = "CC BY 4.0") {
  n <- n_admitted + length(unchecked)
  per <- if (n_admitted) diff(round(seq(0, stems, length.out = n_admitted + 1))) else integer()
  data.frame(group = group, admitted = c(rep(TRUE, n_admitted), rep(FALSE, length(unchecked))),
             unchecked_only = c(rep(FALSE, n_admitted), rep(TRUE, length(unchecked))),
             n_ref_headline = c(per, rep(0L, length(unchecked))),
             n_ref_headline_hold = c(per, unchecked),
             license_short = licence, stringsAsFactors = FALSE)
}
both <- c(height = TRUE, rank = TRUE)

test_that("go needs three admitted plots and 100 headline stems, at the boundaries", {
  d <- function(...) ofo_group_decision(dec_adm(...), both)
  expect_equal(d(3, 100)$decision[1], "go")
  expect_equal(d(3, 99)$decision[1], "no-go")
  expect_equal(d(2, 500)$decision[1], "no-go")
  expect_equal(d(4, 100)$decision[1], "go")
  r <- d(3, 99)
  expect_match(r$reasons[1], "99 reference stems")
  expect_match(r$reasons[1], "3 admitted plots \\(need 3\\), 3 with a headline cell")
  expect_false(r$rule_population[1])
  # Rule 2 counts admitted plots, not plots holding a headline cell; the
  # latter is reported beside it.
  z <- dec_adm(3, 100); z$n_ref_headline <- c(60L, 40L, 0L); z$n_ref_headline_hold <- 0L
  rz <- ofo_group_decision(z, both)
  expect_equal(rz$decision[1], "go")
  expect_equal(rz$plots_admitted[1], 3L)
  expect_equal(rz$plots_with_headline[1], 2L)
  expect_match(rz$reasons[1], "3 admitted plots \\(need 3\\), 2 with a headline cell")
  # Groups without plots are always reported, as no-go.
  expect_equal(r$group, OFO_GROUPS)
  expect_equal(r$decision[2:4], rep("no-go", 3))
  expect_true(all(nzchar(r$reasons)))
})

test_that("hold only when unchecked plots would meet the population rule", {
  # 2 admitted plots + 1 unchecked-only plot adding 10 stems: 3 plots, 105 stems.
  h <- ofo_group_decision(dec_adm(2, 95, unchecked = 10L), both)
  expect_equal(h$decision[1], "hold")
  expect_equal(h$plots_if_unchecked[1], 3L)
  expect_equal(h$ref_headline_if_unchecked[1], 105L)
  # Still short with them admitted: no-go.
  expect_equal(ofo_group_decision(dec_adm(2, 85, unchecked = 10L), both)$decision[1], "no-go")
  expect_equal(ofo_group_decision(dec_adm(1, 95, unchecked = 4L), both)$decision[1], "no-go")
  # Exactly at the boundary with them: hold.
  expect_equal(ofo_group_decision(dec_adm(2, 90, unchecked = 10L), both)$decision[1], "hold")
  # A signal that is not admitted is no-go whatever the plots.
  ns <- c(height = FALSE, rank = TRUE)
  expect_equal(ofo_group_decision(dec_adm(2, 95, unchecked = 10L), ns)$decision[1], "no-go")
  expect_equal(ofo_group_decision(dec_adm(5, 500), ns)$decision[1], "no-go")
})

test_that("signal per group and licence handling enter the decision", {
  b <- dec_adm(3, 120, group = "B")
  expect_equal(ofo_group_decision(b, c(height = TRUE, rank = FALSE))$decision[2], "no-go")
  expect_equal(ofo_group_decision(b, c(height = FALSE, rank = TRUE))$decision[2], "go")
  sa <- dec_adm(3, 120, licence = "CC BY NC SA 4.0")
  r <- ofo_group_decision(sa, both)
  expect_equal(r$decision[1], "go")
  expect_equal(r$rebuild_only_plots[1], 3L)
  expect_match(r$reasons[1], "rebuild-only 3")
  unk <- dec_adm(3, 120, licence = NA)
  r <- ofo_group_decision(unk, both)
  expect_false(r$rule_licence[1])
  expect_equal(r$decision[1], "hold")
  expect_equal(ofo_archive_mode(c("CC BY 4.0", "CC0 1.0", "Public domain", "CC BY SA 4.0",
                                  "CC BY NC SA 4.0", "MIT", NA)),
               c(rep("redistribute", 3), rep("rebuild_only", 2), NA, NA))
  expect_equal(ofo_archive_mode(c(" cc by  4.0", "public domain")), rep("redistribute", 2))
})

test_that("admitted signals come from the top-level `admitted` key only", {
  want <- c(height = TRUE, rank = FALSE)
  expect_equal(ofo_signals_admitted(list(admitted = list(height = TRUE, rank = FALSE))), want)
  expect_equal(ofo_signals_admitted(list(admitted = list(rank = TRUE, height = FALSE))),
               c(height = FALSE, rank = TRUE))
  # Extra blocks (the declared tests, Amendment 1's development and
  # confirmation) never stand in for the final admission, even when they
  # carry `admitted` or `pass` fields of their own that disagree with it.
  rich <- list(status = "complete",
               admitted = list(height = FALSE, rank = FALSE, method = "amendment_1b"),
               signals_admitted = "height", height = list(admitted = TRUE),
               test1_known_truth = list(height = list(pass = TRUE)),
               amendment1 = list(confirmation = list(height = list(admitted = TRUE)),
                                 admitted = list(height = TRUE, rank = TRUE)))
  expect_equal(ofo_signals_admitted(rich), c(height = FALSE, rank = FALSE))
  # The same report read back from JSON, as the driver reads it.
  f <- tempfile(fileext = ".json")
  on.exit(unlink(f), add = TRUE)
  jsonlite::write_json(rich, f, auto_unbox = TRUE)
  expect_equal(ofo_signals_admitted(jsonlite::read_json(f, simplifyVector = TRUE)),
               c(height = FALSE, rank = FALSE))
  # Without the key the reader stops, whatever else the report holds.
  expect_error(ofo_signals_admitted(rich[names(rich) != "admitted"]),
               "no top-level `admitted` key")
  expect_error(ofo_signals_admitted(list(signals_admitted = "height")), "no top-level")
  expect_error(ofo_signals_admitted(list(height = list(admitted = TRUE),
                                         rank = list(admitted = FALSE))), "no top-level")
  expect_error(ofo_signals_admitted(list()), "no top-level")
  # Other shapes of the key itself are refused, not guessed.
  expect_error(ofo_signals_admitted(list(admitted = "height")), "height and rank")
  expect_error(ofo_signals_admitted(list(admitted = list(height = TRUE))), "for rank")
  expect_error(ofo_signals_admitted(list(admitted = list(height = NA, rank = FALSE))),
               "for height")
  expect_error(ofo_signals_admitted(list(admitted = list(height = "true", rank = FALSE))),
               "for height")
  expect_error(ofo_signals_admitted(list(admitted = list(height = list(admitted = TRUE),
                                                         rank = FALSE))), "for height")
})

## ---- a synthetic catalogue in the brief's contracts --------------------------------
fx_square_wkt <- function(x0, y0, w, h = w)
  sprintf("POLYGON ((%s %s, %s %s, %s %s, %s %s, %s %s))", x0, y0, x0 + w, y0, x0 + w,
          y0 + h, x0, y0 + h, x0, y0)

# Plots on 100 m squares (four 40 m cells each), stems on a 7 m grid at their
# registered positions, cycling diameters and statuses.
ofo_world <- function() {
  P <- data.frame(
    plot_id = c("0101", "0102", "0103", "0201", "0202", "0301", "0401", "0901"),
    project_name = c("PRJA", "PRJA", "PRJA", "PRJC", "PRJC", "PRJB", "PRJX", "NEON2023"),
    screen = c("none", "none", "none", "none", "none", "none", "not_exhaustive",
               "in_benchmark"),
    group = c("A", "A", "A", "C", "C", "B", NA, NA),
    live_floor_cm = c(5, 10.2, 0, 12.7, 25.4, 7.6, 5, 1),
    license_short = c("CC BY 4.0", "CC BY SA 4.0", "CC0 1.0", "CC BY 4.0", "CC BY 4.0",
                      "CC BY NC SA 4.0", "CC BY 4.0", "CC BY 4.0"),
    withhold_from_training = c(FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
    survey_year = c(2019L, 2019L, 2020L, 2018L, 2018L, 2021L, 2019L, 2023L),
    epsg = 32610L, x0 = OX + 1000 * (0:7), y0 = OY, stringsAsFactors = FALSE)
  P$polygon_wkt <- fx_square_wkt(P$x0, P$y0, 100)
  P$polygon_area_m2 <- 10000
  reg <- data.frame(plot_id = P$plot_id[1:6], group = P$group[1:6],
                    signal_used = c("height", "height", "height", "height", "height", "rank"),
                    signal_admitted = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
                    dx = c(2, -3.5, 0, 1, 0, 0), dy = c(-1, 0.5, 0, 2, 0, 0),
                    residual_m = c(0.3, 0.8, 1.2, 0.4, 0.5, NA),
                    registered = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE), reason = NA,
                    pos_unc = c(0.5, 0.8, 1.2, 0.5, 0.5, NA), stringsAsFactors = FALSE)
  trees <- do.call(rbind, lapply(seq_len(nrow(P)), function(i) {
    r <- reg[match(P$plot_id[i], reg$plot_id), ]
    dx <- if (is.na(r$dx)) 0 else r$dx; dy <- if (is.na(r$dy)) 0 else r$dy
    g <- expand.grid(E = P$x0[i] + dx + seq(3.5, 99, by = 7),
                     N = P$y0[i] + dy + seq(3.5, 99, by = 7))
    n <- nrow(g)
    dbh <- rep(c(5, 8, 12, 15, 20, 30, 40, 11), length.out = n)
    ld <- rep(c("L", "L", "L", "M", "L", "D", "L", "L", "L"), length.out = n)
    gf <- rep(c("tree", "tree", "tree", "intermediate", NA, "tree", "shrub", "tree", "tree",
                "tree", "tree"), length.out = n)
    data.frame(plot_id = P$plot_id[i], tree_n = seq_len(n),
               individual_id = sprintf("OFO.%s.%d", P$plot_id[i], seq_len(n)),
               contributor_tree_id = seq_len(n), x = g$E - dx, y = g$N - dy, dbh = dbh,
               height = if (P$group[i] %in% "B") NA_real_ else
                 ifelse(seq_len(n) %% 13 == 0, NA_real_, 2 + 0.6 * dbh),
               height_allometric = 99, species_code = "PSME", growth_form = gf,
               live_dead = ld,
               crown_position = rep(c(1, 2, 3, 4, 5, NA, NA), length.out = n),
               crown_width_1 = rep(c(3, NA, 6), length.out = n),
               crown_width_2 = rep(c(5, 4, 2), length.out = n),
               live = ld %in% c("L", "M"), is_tree = gf %in% c("tree", "intermediate") | is.na(gf),
               inside = TRUE, stringsAsFactors = FALSE)
  }))
  fl <- P$live_floor_cm[match(trees$plot_id, P$plot_id)]
  trees$ref <- trees$live & trees$is_tree & trees$inside & trees$dbh >= pmax(10, fl)
  flights <- data.frame(plot_id = P$plot_id[1:7], project_name = P$project_name[1:7],
                        flight_year = c(2020L, 2020L, 2020L, 2019L, 2019L, 2021L, 2020L),
                        flight_admitted = TRUE, flight_reason = NA)
  geometry <- data.frame(plot_id = P$plot_id, geometry_consistent = TRUE)
  licences <- data.frame(plot_id = P$plot_id, project_name = P$project_name,
                         license_short = P$license_short,
                         redistribute_reference =
                           ofo_archive_mode(P$license_short) == "redistribute")
  conditions <- data.frame(plot_id = P$plot_id[1:7], project_name = P$project_name[1:7],
    disturbance_status = c(rep("undisturbed", 4), "disturbed", "undisturbed", "undisturbed"),
    interval_covered = TRUE, same_year = FALSE,
    disturbance_admitted = c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE),
    snow_status = "not_winter", leafoff_status = "leaf_on",
    conditions_admitted = c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE),
    conditions_reason = c(NA, NA, NA, NA, "disturbed", NA, NA), stringsAsFactors = FALSE)
  list(plots = P[, setdiff(names(P), c("x0", "y0"))], trees = trees, flights = flights,
       geometry = geometry, licences = licences, registration = reg, conditions = conditions,
       tests = list(admitted = list(height = TRUE, rank = FALSE)))
}

# The library path of preflight_ofo_decision.R for groups A and C.
world_reference <- function(w = ofo_world()) {
  adm <- ofo_plot_admission(w$plots, w$flights, w$geometry, w$conditions, w$registration)
  adm$live_floor_cm <- w$plots$live_floor_cm[match(adm$plot_id, w$plots$plot_id)]
  loc <- ofo_locate(w$plots, w$trees, w$registration)
  floors <- ofo_group_floors(adm)
  pf <- setNames(ofo_plot_floor(adm$group, floors, c(C = 25.4)), adm$plot_id)
  cells <- ofo_count_cells(loc$cells, loc$stems, pf)
  take <- adm$plot_id[adm$admitted]
  cells_a <- cells[cells$plot_id %in% take, ]
  list(adm = adm, loc = loc, floors = floors, cells = cells, cells_a = cells_a,
       gt = ofo_ground_truth(loc$stems, w$plots, w$flights, cells_a, floors),
       pc = ofo_plot_centroids(cells_a, w$plots, w$flights), world = w)
}

test_that("ground truth follows the neon_ground_truth.R schema and the reference rules", {
  r <- world_reference()
  gt <- r$gt
  expect_equal(names(gt), c(OFO_GT_COLUMNS, OFO_GT_EXTRA))
  expect_equal(sort(unique(gt$ofo_plot_id)), c("0101", "0102", "0103", "0201"))
  expect_true(all(r$adm$admitted == (r$adm$plot_id %in% c("0101", "0102", "0103", "0201"))))
  # Registered position = raw position + plot shift; pos_unc from registration.
  i <- gt$ofo_plot_id == "0102"
  expect_equal(gt$E[i] - gt$E_raw[i], rep(-3.5, sum(i)))
  expect_equal(gt$N[i] - gt$N_raw[i], rep(0.5, sum(i)))
  expect_equal(unique(gt$pos_unc[i]), 0.8)
  expect_equal(unique(gt$plotID[gt$ofo_plot_id == "0101"]), sprintf("0101_%d", 1:4))
  # Group A keeps every tree in its cells (dead, shrubs, small); C only >= floor.
  a <- gt[gt$group == "A", ]
  expect_true(any(!a$live) && any(!a$is_tree) && any(a$stemDiameter < 10))
  cgt <- gt[gt$group == "C", ]
  expect_equal(r$floors$floor_cm[r$floors$group == "C"], 12.7)   # 0202 is not admitted
  expect_true(all(cgt$stemDiameter >= 12.7))
  # Measured height only, never the allometric one; status strings; crowns.
  expect_false(any(gt$height == 99, na.rm = TRUE))
  # Groups A and C keep their heights; height_recorded repeats them.
  expect_identical(gt$height_recorded, gt$height)
  expect_true(anyNA(gt$height) && any(!is.na(gt$height)))
  # Without a site plan each row is named by its project.
  expect_equal(gt$site, gt$project)
  expect_equal(r$pc$site, r$pc$project)
  expect_equal(sort(unique(gt$plantStatus)), c("Live", "Live, marginal", "Standing dead"))
  expect_equal(gt$live, grepl("Live", gt$plantStatus))
  w <- !is.na(gt$maxCrownDiameter)
  expect_true(all(gt$maxCrownDiameter[w] >= gt$ninetyCrownDiameter[w]))
  expect_true(all(is.na(gt$ninetyCrownDiameter[!w])))
  expect_equal(unique(gt$dist_aop[gt$ofo_plot_id == "0201"]), 1)
  expect_equal(gt$dist21, gt$dist_aop)
  expect_equal(unique(gt$utmZone), "10N")
  expect_equal(unique(gt$taxonID), "PSME")
  expect_equal(gt$withhold_from_training, gt$ofo_plot_id == "0102")
  # Benchmark gate counts equal the cell reference counts.
  big <- gt$live & gt$is_tree & gt$stemDiameter >= 10
  n <- table(factor(gt$plotID[big], levels = r$cells_a$cell_id))
  expect_equal(as.integer(n), r$cells_a$n_ref)
  expect_true(all(r$cells_a$headline == (r$cells_a$n_ref >= 6)))
})

test_that("plot centroids carry one tower plot per admitted cell", {
  r <- world_reference()
  pc <- r$pc
  expect_equal(names(pc)[1:9], c("plotID", "plotType", "easting", "northing", "utmZone",
                                 "plot_meas_year", "epsg", "datum", "acquisition_year"))
  expect_equal(nrow(pc), nrow(r$cells_a))
  expect_true(all(pc$plotType == "tower"))
  expect_setequal(pc$plotID, r$cells_a$cell_id)
  c1 <- pc[pc$plotID == "0101_1", ]
  # 0101 moved by (2, -1): x fits at offset 5, y at offset 0.
  expect_equal(c(c1$easting, c1$northing), c(OX + 25, OY + 20))
})

test_that("the hold recount uses the floor of the larger plot set", {
  w <- ofo_world()
  # 0202 (floor 25.4) fails only an unchecked condition: no usable drone model.
  i <- w$conditions$plot_id == "0202"
  w$conditions$disturbance_status[i] <- "not_checked"
  w$conditions$conditions_reason[i] <- "no_usable_drone_model"
  adm <- ofo_plot_admission(w$plots, w$flights, w$geometry, w$conditions, w$registration)
  expect_equal(adm$plot_id[adm$unchecked_only], "0202")
  adm$live_floor_cm <- w$plots$live_floor_cm[match(adm$plot_id, w$plots$plot_id)]
  loc <- ofo_locate(w$plots, w$trees, w$registration)
  area <- setNames(rep(1e4, nrow(adm)), adm$plot_id)
  main <- ofo_counts_under(adm, loc, adm$admitted, area)
  hold <- ofo_counts_under(adm, loc, adm$admitted | adm$unchecked_only, area)
  expect_equal(main$floors$floor_cm[3], 12.7)
  expect_equal(hold$floors$floor_cm[3], 25.4)
  s <- loc$stems[loc$stems$plot_id == "0201" & !is.na(loc$stems$cell_id), ]
  big <- s$live & s$is_tree & s$dbh >= 25.4
  n <- table(factor(s$cell_id[big], levels = hold$cells$cell_id[hold$cells$plot_id == "0201"]))
  expect_equal(hold$counts$n_ref_cells[hold$counts$plot_id == "0201"], sum(big))
  expect_equal(hold$counts$n_ref_headline[hold$counts$plot_id == "0201"], sum(n[n >= 6]))
  expect_lt(hold$counts$n_ref_cells[hold$counts$plot_id == "0201"],
            main$counts$n_ref_cells[main$counts$plot_id == "0201"])
  # A and B keep the 10 cm floor in both sets.
  expect_equal(hold$floors$floor_cm[1:2], c(10, 10))
})

## ---- groups without a height gate --------------------------------------------------
# The world with plot 0301 registered and admitted in group `g`, its trees
# carrying some recorded heights (a B or D plot may record a few).
world_no_height <- function(g) {
  w <- ofo_world()
  i <- w$plots$plot_id == "0301"
  w$plots$group[i] <- g
  if (g %in% c("C", "D")) w$plots$live_floor_cm[i] <- 12.7
  t <- which(w$trees$plot_id == "0301")
  w$trees$height[t] <- ifelse(seq_along(t) %% 5 == 0, NA, 2 + 0.6 * w$trees$dbh[t])
  r <- w$registration$plot_id == "0301"
  w$registration[r, c("registered", "residual_m", "pos_unc")] <- list(TRUE, 0.6, 0.6)
  w
}
reference_of <- function(w, plots_kept) {
  adm <- ofo_plot_admission(w$plots, w$flights, w$geometry, w$conditions, w$registration)
  adm$live_floor_cm <- w$plots$live_floor_cm[match(adm$plot_id, w$plots$plot_id)]
  loc <- ofo_locate(w$plots, w$trees, w$registration)
  floors <- ofo_group_floors(adm)
  pf <- setNames(ofo_plot_floor(adm$group, floors), adm$plot_id)
  cells <- ofo_count_cells(loc$cells, loc$stems, pf)
  cells <- cells[cells$plot_id %in% plots_kept, , drop = FALSE]
  list(adm = adm, cells = cells, floors = floors,
       gt = ofo_ground_truth(loc$stems, w$plots, w$flights, cells, floors),
       pc = ofo_plot_centroids(cells, w$plots, w$flights))
}

test_that("groups B and D carry no height and no crown class", {
  for (g in c("B", "D")) {
    w <- world_no_height(g)
    r <- reference_of(w, c("0101", "0301"))
    expect_true(r$adm$admitted[r$adm$plot_id == "0301"], info = g)
    b <- r$gt[r$gt$group == g, ]
    a <- r$gt[r$gt$group == "A", ]
    expect_gt(nrow(b), 30)
    # Position alone: no height on any row; the recorded value is kept apart.
    expect_true(all(is.na(b$height)), info = g)
    src <- w$trees[match(b$individualID, w$trees$individual_id), ]
    expect_equal(b$height_recorded, src$height)
    expect_true(any(!is.na(b$height_recorded)) && anyNA(b$height_recorded))
    expect_identical(a$height_recorded, a$height)
    # No crown class at all (protocol "Missing heights"), neither from a
    # recorded position nor from the fallback, although these stems carry
    # both and A rows of the same table take them; the recorded position is
    # kept apart in every group.
    expect_true(all(is.na(b$crown_class)) && all(is.na(b$canopyPosition)), info = g)
    expect_equal(b$crown_source, rep("none", nrow(b)))
    expect_true(any(src$crown_position %in% 1:5))
    expect_equal(b$crown_position_recorded, as.integer(src$crown_position))
    srca <- w$trees[match(a$individualID, w$trees$individual_id), ]
    expect_equal(a$crown_position_recorded, as.integer(srca$crown_position))
    expect_true(any(a$crown_source == "height_fallback"))
    expect_true(any(a$crown_source == "canopyPosition"))
    # A B/D table carrying a class is refused as the arms would read it.
    pc <- r$pc[r$pc$group == g, ]
    bb <- b; bb$site <- "S"; pc$site <- "S"
    expect_silent(ofo_check_site_tables(bb, pc, "S"))
    bb$crown_class[1] <- "dominant"
    expect_error(ofo_check_site_tables(bb, pc, "S"), "carry a crown class")
    if (g == "D") expect_true(all(b$stemDiameter >= 12.7))
    # Group A rows with heights are unaffected by the B/D plot in the same call.
    ra <- reference_of(w, "0101")
    for (col in c("individualID", "height", "crown_class", "crown_source"))
      expect_identical(ra$gt[[col]], a[[col]], info = col)
  }
})

## ---- reference directories --------------------------------------------------------
site_fixture <- function() {
  adm <- data.frame(plot_id = sprintf("%04d", 1:10),
    project_name = c("P1", "P1", "P1", "P1", "P2", "P2", "P3", "P3", "P3", "P4"),
    group = c("C", "C", "D", "D", "A", "A", "C", "C", "C", "B"),
    admitted = c(TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    stringsAsFactors = FALSE)
  fl <- data.frame(plot_id = adm$plot_id,
                   flight_year = c(2021L, 2021L, 2022L, 2019L, 2022L, 2022L, 2018L, 2021L,
                                   2021L, NA))
  list(adm = adm, fl = fl)
}

test_that("reference directories hold one project, group and flight year each", {
  f <- site_fixture()
  p <- ofo_site_plan(f$adm, f$fl, c("A", "C", "D"))
  # P1 has admitted plots in two go groups: <PROJECT>_<GROUP> for both. P2:
  # one group, one year. P3: one group flown in two years: <NAME>_<YEAR>.
  # Not admitted (0004) and not go (0010, group B) stay out.
  expect_equal(p$plot_id, c("0001", "0002", "0003", "0005", "0006", "0007", "0008", "0009"))
  expect_equal(p$site, c("P1_C", "P1_C", "P1_D", "P2", "P2", "P3_2018", "P3_2021", "P3_2021"))
  expect_equal(p$split_group, c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_equal(p$split_year, c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE))
  expect_true(all(grepl(OFO_SITE_PATTERN, p$site)))
  # Every directory has one project, group and year.
  k <- unique(p[, c("site", "project_name", "group", "acquisition_year")])
  expect_false(anyDuplicated(k$site) > 0)
  # Deterministic: row order and the order of the go groups do not matter.
  o <- rev(seq_len(nrow(f$adm)))
  expect_identical(ofo_site_plan(f$adm[o, ], f$fl[o, ], c("D", "A", "C")), p)
  # D not go: P1 holds one go group and keeps its project name.
  p2 <- ofo_site_plan(f$adm, f$fl, c("A", "C"))
  expect_equal(unique(p2$site[p2$project_name == "P1"]), "P1")
  # A D plot that is not admitted does not split P1 either.
  adm3 <- f$adm; adm3$admitted[3] <- FALSE
  p3 <- ofo_site_plan(adm3, f$fl, c("A", "C", "D"))
  expect_equal(unique(p3$site[p3$project_name == "P1"]), "P1")
  # Group and year splits combine.
  fl4 <- f$fl; fl4$flight_year[2] <- 2020L
  p4 <- ofo_site_plan(f$adm, fl4, c("A", "C", "D"))
  expect_equal(p4$site[p4$project_name == "P1"], c("P1_C_2020", "P1_C_2021", "P1_D"))
  expect_equal(p4$plot_id[p4$project_name == "P1"], c("0002", "0001", "0003"))
  # No go group: an empty plan.
  expect_equal(nrow(ofo_site_plan(f$adm, f$fl, character())), 0L)
  # Directory table: plots and cells per site.
  pc <- data.frame(site = c("P1_C", "P1_C", "P2", "P3_2021"), headline = c(TRUE, FALSE, TRUE, TRUE))
  st <- ofo_site_table(p, pc)
  expect_equal(st$site, c("P1_C", "P1_D", "P2", "P3_2018", "P3_2021"))
  expect_equal(st$n_plots, c(2L, 1L, 2L, 1L, 2L))
  expect_equal(st$plot_ids[1], "0001;0002")
  expect_equal(st$n_cells, c(2L, 0L, 1L, 0L, 1L))
  expect_equal(st$n_headline_cells, c(1L, 0L, 1L, 0L, 1L))
  expect_equal(st$acquisition_year, c(2021L, 2022L, 2022L, 2018L, 2021L))
})

test_that("reference directory names must be safe, distinct and dated", {
  f <- site_fixture()
  # A project named like another project's group directory collides.
  adm <- rbind(f$adm, data.frame(plot_id = "0011", project_name = "P1_C", group = "A",
                                 admitted = TRUE))
  fl <- rbind(f$fl, data.frame(plot_id = "0011", flight_year = 2021L))
  expect_error(ofo_site_plan(adm, fl, c("A", "C", "D")), "collide.*P1_C")
  # So do names that differ only in case.
  adm2 <- f$adm; adm2$project_name[adm2$project_name == "P2"] <- "p3"
  adm2$project_name[adm2$project_name == "P3"] <- "P3"
  fl2 <- f$fl; fl2$flight_year[7] <- 2021L                     # P3 in one year
  expect_error(ofo_site_plan(adm2, fl2, c("A", "C", "D")), "collide")
  # Unsafe project names stop rather than being rewritten.
  for (bad in c("P 2", "../P2", "P2,P3", "_P2", "P2=x")) {
    adm3 <- f$adm; adm3$project_name[adm3$project_name == "P2"] <- bad
    expect_error(ofo_site_plan(adm3, f$fl, c("A", "C", "D")), "unsafe", info = bad)
  }
  # An admitted plot needs its flight year.
  fl5 <- f$fl; fl5$flight_year[5] <- NA
  expect_error(ofo_site_plan(f$adm, fl5, c("A", "C", "D")), "without a flight year: 0005")
})

test_that("a directory's tables are checked against its name", {
  w <- world_no_height("B")
  r <- reference_of(w, c("0101", "0301"))
  site <- c("0101" = "PRJA", "0301" = "PRJB")
  loc <- ofo_locate(w$plots, w$trees, w$registration)
  gt <- ofo_ground_truth(loc$stems, w$plots, w$flights, r$cells, r$floors, site)
  pc <- ofo_plot_centroids(r$cells, w$plots, w$flights, site)
  expect_equal(sort(unique(gt$site)), c("PRJA", "PRJB"))
  expect_equal(gt$site, unname(site[gt$ofo_plot_id]))
  expect_equal(pc$site, unname(site[pc$ofo_plot_id]))
  expect_error(ofo_ground_truth(loc$stems, w$plots, w$flights, r$cells, r$floors,
                                c("0101" = "PRJA")), "No reference directory for plot\\(s\\): 0301")
  one <- function(s) list(gt = gt[gt$site == s, ], pc = pc[pc$site == s, ])
  a <- one("PRJA"); b <- one("PRJB")
  id <- ofo_check_site_tables(a$gt, a$pc, "PRJA")
  expect_equal(id, list(site = "PRJA", project = "PRJA", group = "A",
                        acquisition_year = 2020L, epsg = 32610L))
  expect_equal(ofo_check_site_tables(b$gt, b$pc, "PRJB")$group, "B")
  expect_error(ofo_check_site_tables(gt, pc, "PRJA"), "rows of another site")
  mixed <- a; mixed$gt$acquisition_year[1] <- 2021L
  expect_error(ofo_check_site_tables(mixed$gt, mixed$pc, "PRJA"), "not one acquisition year")
  hg <- b; hg$gt$height[1] <- 20
  expect_error(ofo_check_site_tables(hg$gt, hg$pc, "PRJB"), "group B rows carry heights")
  lost <- a; lost$pc <- lost$pc[-1, ]
  expect_error(ofo_check_site_tables(lost$gt, lost$pc, "PRJA"), "outside the listed cells")
  expect_error(ofo_check_site_tables(a$gt[0, ], a$pc, "PRJA"), "no rows")
  expect_error(ofo_check_site_tables(a$gt, a$pc, "PR JA"), "unsafe")
})

test_that("outputs go under OFO or outside the job directory, never elsewhere in it", {
  job <- tempfile("ofo-job-")
  scratch <- tempfile("ofo-scratch-")
  dir.create(file.path(job, "ofo", "preflight"), recursive = TRUE)
  dir.create(file.path(job, "neon"))
  dir.create(scratch)
  on.exit(unlink(c(job, scratch), recursive = TRUE), add = TRUE)
  ofo <- file.path(job, "ofo")
  ok <- function(p) ofo_output_allowed(p, job, ofo)
  expect_true(ok(file.path(ofo, "preflight")))
  expect_true(ok(file.path(ofo, "smoke", "new", "deeper")))   # need not exist
  expect_true(ok(ofo))
  expect_true(ok(file.path(scratch, "out")))
  expect_false(ok(job))
  expect_false(ok(file.path(job, "neon", "x")))
  expect_false(ok(file.path(job, "other")))
  expect_false(ok(paste0(ofo, "-sibling")))                     # a prefix is not a parent
  expect_false(ok(file.path(ofo, "new", "..", "..", "neon")))   # `..` refused
  expect_false(ok("")); expect_false(ok(NA_character_))
  # Relative paths resolve against the working directory.
  old <- setwd(job); on.exit(setwd(old), add = TRUE)
  expect_false(ok("neon/x"))
  expect_true(ok("ofo/x"))
  # A symlink from outside into the job directory is followed.
  link <- file.path(scratch, "into-job")
  if (isTRUE(file.symlink(file.path(job, "neon"), link))) {
    expect_false(ok(file.path(link, "x")))
  }
})

test_that("inputs: registration.csv needs a shift and an uncertainty where registered", {
  w <- ofo_world()
  reg <- w$registration
  expect_length(ofo_check_inputs(w$plots, w$trees, w$flights, w$geometry, w$licences, reg), 0)
  # `group` is optional (checked when present); extra columns are ignored.
  reg2 <- reg[, setdiff(names(reg), "group")]; reg2$method <- "amendment_1b"
  expect_length(ofo_check_inputs(w$plots, w$trees, w$flights, w$geometry, w$licences, reg2), 0)
  reg3 <- reg; reg3$group[1] <- "C"
  expect_match(ofo_check_inputs(w$plots, w$trees, w$flights, w$geometry, w$licences, reg3),
               "group differs")
  reg4 <- reg; reg4$dx[2] <- NA; reg4$pos_unc[3] <- NA; reg4$residual_m[3] <- NA
  m <- ofo_check_inputs(w$plots, w$trees, w$flights, w$geometry, w$licences, reg4)
  expect_true(any(grepl("registered without a finite dx/dy: 0102", m)))
  expect_true(any(grepl("registered without pos_unc or residual_m: 0103", m)))
  # Unregistered rows may lack them.
  reg5 <- reg; reg5$dx[6] <- NA; reg5$pos_unc[6] <- NA
  expect_length(ofo_check_inputs(w$plots, w$trees, w$flights, w$geometry, w$licences, reg5), 0)
})

## ---- schema compatibility with the benchmark's own functions --------------------
test_that("written tables read back as the arms read them and pass the repo's checks", {
  source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
  source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
  r <- world_reference()
  d <- file.path(tempfile("ofo-ref-"), "neon", "PRJA")
  dir.create(d, recursive = TRUE)
  on.exit(unlink(dirname(dirname(d)), recursive = TRUE), add = TRUE)
  write.csv(r$gt[r$gt$project == "PRJA", ], file.path(d, "ground_truth_stems.csv"),
            row.names = FALSE)
  write.csv(r$pc[r$pc$project == "PRJA", ], file.path(d, "plot_centroids.csv"), row.names = FALSE)
  # freeze_clips.R field() reads with stringsAsFactors = FALSE; run_sweep.R plainly.
  gt <- read.csv(file.path(d, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(d, "plot_centroids.csv"), stringsAsFactors = FALSE)
  gt2 <- read.csv(file.path(d, "ground_truth_stems.csv"))
  expect_identical(gt, gt2)
  expect_type(gt$plotID, "character")
  expect_type(gt$individualID, "character")
  expect_type(pc$plotID, "character")
  expect_type(gt$live, "logical")
  expect_type(gt$is_tree, "logical")
  # Missing crown classes stay NA (not ""), so ext_crown_source() reads them.
  expect_true(anyNA(gt$crown_class) && anyNA(gt$canopyPosition))
  expect_false(any(gt$crown_class == "" | gt$canopyPosition == "", na.rm = TRUE))
  expect_equal(ext_crown_source(gt), gt$crown_source)
  live <- ext_live_trees(gt)
  expect_equal(neon_validate_inputs(live, pc), 32610L)
  expect_equal(neon_validate_inputs(gt, pc), 32610L)          # run_sweep.R's form
  expect_equal(neon_field_epsg(pc), 32610L)
  # One acquisition year per directory, as freeze_clips.R checks it (YEAR=2020).
  expect_equal(neon_reference_epoch(gt, 2020L), 2020L)
  expect_error(neon_reference_epoch(gt, 2021L), "acquisition year differ")
  expect_equal(ofo_check_site_tables(gt, pc, "PRJA")$acquisition_year, 2020L)
  expect_type(gt$site, "character")
  expect_type(gt$height_recorded, "double")
  ref <- frozen_reference(gt, "adopted")
  expect_true(all(ref$stemDiameter >= 10 & ref$live & ref$is_tree))
  inv <- ext_plot_inventory(ref, pc, frozen_population_spec("adopted")$min_trees)
  want <- pc$n_ref[match(inv$plotID, pc$plotID)]
  expect_equal(inv$n_core, want)
  expect_equal(inv$n_live, want)
  expect_equal(inv$admitted, want >= 6)
  expect_true(all(inv$core_half == 20))
  cs <- ext_core_stems(ref, inv)
  expect_equal(nrow(cs), sum(want[want >= 6]))
  expect_true(all(c("canopyPosition", "height_fallback") %in% ext_crown_source(cs)))
  # score_plot on one cell, matching with and without heights.
  cell <- pc[pc$plotID == "0101_1", ]
  stems <- cs[cs$plotID == "0101_1", ]
  det <- data.frame(x = stems$E + 1, y = stems$N - 1,
                    z = ifelse(is.na(stems$height), 20, stems$height + 0.5))
  v <- which(!is.na(stems$height))[1]
  det$z[v] <- 0.3 * stems$height[v]                    # height-inconsistent apex
  # A commission apex at the centre of a lattice square, 4.95 m from any stem.
  det <- rbind(det, data.frame(x = OX + 23, y = OY + 20, z = 30))
  sc <- score_plot(stems, det, tol_xy = 4, core_cx = cell$easting, core_cy = cell$northing,
                   core_half = plot_half(cell$plotType))
  expect_equal(sc$n_ref, nrow(stems))
  expect_equal(sc$TP, nrow(stems) - 1L)
  nohgt <- stems; nohgt$height <- NA
  sc2 <- score_plot(nohgt, det, tol_xy = 4, core_cx = cell$easting, core_cy = cell$northing,
                    core_half = 20)
  expect_equal(sc2$TP, nrow(stems))
  expect_true(is.na(sc2$height_rmse))
  # Per-class counts come from the written crown classes.
  expect_equal(sc$n_dominant, sum(stems$crown_class == "dominant", na.rm = TRUE))
})

test_that("a group B table reads back and scores on position alone in the arms' code", {
  source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
  source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
  w <- world_no_height("B")
  r <- reference_of(w, "0301")
  d <- file.path(tempfile("ofo-refb-"), "neon", "PRJB")
  dir.create(d, recursive = TRUE)
  on.exit(unlink(dirname(dirname(d)), recursive = TRUE), add = TRUE)
  write.csv(r$gt, file.path(d, "ground_truth_stems.csv"), row.names = FALSE)
  write.csv(r$pc, file.path(d, "plot_centroids.csv"), row.names = FALSE)
  gt <- read.csv(file.path(d, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(d, "plot_centroids.csv"), stringsAsFactors = FALSE)
  # An all-NA height column reads back as logical NA; the readers accept it.
  expect_true(all(is.na(gt$height)))
  expect_true(any(!is.na(gt$height_recorded)))
  expect_equal(ofo_check_site_tables(gt, pc, "PRJB")$group, "B")
  expect_equal(neon_reference_epoch(gt, 2021L), 2021L)
  expect_equal(neon_validate_inputs(ext_live_trees(gt), pc), 32610L)
  ref <- frozen_reference(gt, "adopted")
  inv <- ext_plot_inventory(ref, pc, frozen_population_spec("adopted")$min_trees)
  expect_equal(inv$n_core, pc$n_ref[match(inv$plotID, pc$plotID)])
  cs <- ext_core_stems(ref, inv)
  expect_false(any(ext_crown_source(cs) == "height_fallback"))
  expect_equal(ext_crown_source(cs), cs$crown_source)
  # Detections at heights far from the recorded ones still match: no gate.
  cell <- pc[pc$plotID == "0301_1", ]
  stems <- cs[cs$plotID == "0301_1", ]
  det <- data.frame(x = stems$E + 1, y = stems$N - 1, z = 3)
  sc <- score_plot(stems, det, tol_xy = 4, core_cx = cell$easting, core_cy = cell$northing,
                   core_half = plot_half(cell$plotType))
  expect_equal(sc$TP, nrow(stems))
  expect_true(is.na(sc$height_rmse))
  # Had the recorded heights been written, the gate would have rejected them.
  withh <- stems; withh$height <- withh$height_recorded
  sc2 <- score_plot(withh, det, tol_xy = 4, core_cx = cell$easting, core_cy = cell$northing,
                    core_half = 20)
  expect_lt(sc2$TP, nrow(stems))
})

## ---- drivers end to end on synthetic inputs ----------------------------------------
run_driver <- function(script, job, args = character()) {
  out <- suppressWarnings(system2("Rscript", c(normalizePath(file.path("..", "..", "scripts",
    script)), args), env = paste0("CLAUDE_JOB_DIR=", job), stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"),
       out = paste(out, collapse = "\n"))
}

# The records the stages write beside their tables (digests of what each read
# and wrote), as for tables computed from the current inputs.
write_records <- function(pre) {
  rec <- function(stage, inputs, outputs, file)
    ofo_write_record(ofo_stage_record(stage, pre, ofo_sha256(pre, inputs), outputs),
                     file.path(pre, file))
  rec("catalog flights", "plots.csv", "flights.csv", "flights_record.json")
  rec("catalog geometry", c("plots.csv", "trees.csv"), "geometry_audit.csv",
      "geometry_record.json")
  rec("conditions", c("plots.csv", "trees.csv", "flights.csv"), "conditions.csv",
      "conditions_record.json")
  rec("registration catalog", c("plots.csv", "trees.csv", "flights.csv"),
      c("registration.csv", "registration_tests.json"), "registration_catalog_record.json")
}

write_world <- function(w, job) {
  pre <- file.path(job, "ofo", "preflight")
  dir.create(pre, recursive = TRUE)
  for (nm in c("plots", "trees", "flights", "licences", "registration", "conditions"))
    data.table::fwrite(w[[nm]], file.path(pre, paste0(nm, ".csv")))
  data.table::fwrite(w$geometry, file.path(pre, "geometry_audit.csv"))
  jsonlite::write_json(w$tests, file.path(pre, "registration_tests.json"), auto_unbox = TRUE)
  write_records(pre)
  pre
}

test_that("decision and reference drivers run on contract tables and guard their outputs", {
  job <- tempfile("ofo-job-")
  on.exit(unlink(job, recursive = TRUE), add = TRUE)
  w <- ofo_world()
  pre <- write_world(w, job)
  # A missing column is named.
  bad <- w$flights; bad$flight_year <- NULL
  data.table::fwrite(bad, file.path(pre, "flights.csv"))
  write_records(pre)
  r0 <- run_driver("preflight_ofo_decision.R", job)
  expect_true(r0$status != 0)
  expect_match(r0$out, "flights.csv lacks column\\(s\\): flight_year")
  data.table::fwrite(w$flights, file.path(pre, "flights.csv"))
  # Tables computed from superseded inputs are refused, naming the stage.
  r_old <- run_driver("preflight_ofo_decision.R", job)
  expect_true(r_old$status != 0)
  expect_match(r_old$out, "conditions_record.json \\(conditions\\): flights.csv differs")
  expect_match(r_old$out, "registration_catalog_record.json")
  expect_false(file.exists(file.path(pre, "group_decision.csv")))
  write_records(pre)
  cnd <- w$conditions; cnd$conditions_reason[1] <- "edited"
  data.table::fwrite(cnd, file.path(pre, "conditions.csv"))
  r_cnd <- run_driver("preflight_ofo_decision.R", job)
  expect_true(r_cnd$status != 0)
  expect_match(r_cnd$out, "conditions.csv differs from the one it wrote")
  expect_match(r_cnd$out, "rerun preflight_ofo_conditions.R")
  unlink(file.path(pre, "geometry_record.json"))
  r_geo <- run_driver("preflight_ofo_decision.R", job)
  expect_match(r_geo$out, "geometry_record.json is missing")
  data.table::fwrite(w$conditions, file.path(pre, "conditions.csv"))
  write_records(pre)
  r1 <- run_driver("preflight_ofo_decision.R", job)
  expect_equal(r1$status, 0L, info = r1$out)
  rd <- function(f) as.data.frame(data.table::fread(file.path(pre, f),
                                                   colClasses = list(character = "plot_id")))
  dec <- read.csv(file.path(pre, "group_decision.csv"), stringsAsFactors = FALSE)
  expect_equal(dec$decision, c("go", "no-go", "no-go", "no-go"))
  cells <- rd("cells.csv")
  expect_equal(names(cells)[1:11], c("plot_id", "project_name", "group", "cell", "cell_id",
                                     "cx", "cy", "epsg", "inside_share", "n_ref", "headline"))
  # Cells for every registered plot, admitted (0101-0103, 0201) or not (0202).
  expect_setequal(unique(cells$plot_id), c("0101", "0102", "0103", "0201", "0202"))
  pa <- rd("plot_admission.csv")
  expect_equal(nrow(pa), 7L)                               # NEON2023 excluded
  expect_equal(pa$reason[pa$plot_id == "0202"], "conditions_admitted")
  expect_equal(pa$reason[pa$plot_id == "0301"], "registered")
  gs <- read.csv(file.path(pre, "group_summary.csv"), stringsAsFactors = FALSE)
  expect_equal(gs$admitted[gs$group == "A" & gs$project_name == "ALL"], 3L)
  expect_equal(gs$ref_headline[gs$group == "A" & gs$project_name == "ALL"],
               dec$ref_headline[dec$group == "A"])
  # Hold and no-go groups authorise nothing.
  r2 <- run_driver("prepare_ofo_reference.R", job, "GROUPS=A,C")
  expect_true(r2$status != 0)
  expect_match(r2$out, "C=no-go")
  r3 <- run_driver("prepare_ofo_reference.R", job)
  expect_equal(r3$status, 0L, info = r3$out)
  rdir <- file.path(job, "ofo", "reference", "neon", "PRJA")
  expect_true(all(file.exists(file.path(rdir, c("ground_truth_stems.csv", "plot_centroids.csv")))))
  expect_false(dir.exists(file.path(job, "ofo", "reference", "neon", "PRJC")))
  expect_false(dir.exists(file.path(job, "neon")))
  sa <- as.data.frame(data.table::fread(file.path(job, "ofo", "reference", "stems_all.csv"),
                                        colClasses = list(character = "plot_id")))
  expect_equal(nrow(sa), sum(w$trees$plot_id != "0901"))
  gt <- read.csv(file.path(rdir, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  expect_equal(sum(sa$in_reference), nrow(gt))
  expect_true(all(is.na(sa$E[sa$plot_id == "0301"])))       # not registered
  # One project with one go group and one flight year keeps its name.
  expect_equal(unique(gt$site), "PRJA")
  # stems_all.csv: the site of every plot in a directory, empty elsewhere.
  expect_equal(sort(unique(sa$site[!is.na(sa$site) & nzchar(sa$site)])), "PRJA")
  expect_equal(sort(unique(sa$plot_id[sa$site %in% "PRJA"])), c("0101", "0102", "0103"))
  rec <- jsonlite::read_json(file.path(job, "ofo", "reference", "reference_record.json"),
                             simplifyVector = TRUE)
  expect_equal(rec$sites[, c("site", "project_name", "group", "acquisition_year", "written")],
               data.frame(site = "PRJA", project_name = "PRJA", group = "A",
                          acquisition_year = 2020L, written = TRUE))
  expect_equal(sort(rec$plots$plot_id), c("0101", "0102", "0103"))
  # No silent overwrite.
  r4 <- run_driver("prepare_ofo_reference.R", job)
  expect_true(r4$status != 0)
  expect_match(r4$out, "FORCE=TRUE")
  expect_equal(run_driver("prepare_ofo_reference.R", job, "FORCE=TRUE")$status, 0L)
  # The decision's inputs and outputs must be current: a conditions table
  # regenerated after the decision (records and all) leaves it stale.
  cnd <- w$conditions; cnd$conditions_reason[1] <- "rerun"
  data.table::fwrite(cnd, file.path(pre, "conditions.csv"))
  write_records(pre)
  r5 <- run_driver("prepare_ofo_reference.R", job, "FORCE=TRUE")
  expect_true(r5$status != 0)
  expect_match(r5$out, "decision is not current")
  expect_match(r5$out, "conditions.csv differs")
  expect_equal(run_driver("preflight_ofo_decision.R", job)$status, 0L)
  pa <- file.path(pre, "plot_admission.csv")
  writeLines(sub("TRUE", "FALSE", readLines(pa)), pa)
  r6 <- run_driver("prepare_ofo_reference.R", job, "FORCE=TRUE")
  expect_match(r6$out, "plot_admission.csv differs from the one it wrote")
  expect_equal(run_driver("preflight_ofo_decision.R", job)$status, 0L)
  expect_equal(run_driver("prepare_ofo_reference.R", job, "FORCE=TRUE")$status, 0L)
})

test_that("reference driver: a symlink under OFO into the NEON root is refused", {
  job <- tempfile("ofo-job-")
  on.exit(unlink(job, recursive = TRUE), add = TRUE)
  pre <- write_world(ofo_world(), job)
  expect_equal(run_driver("preflight_ofo_decision.R", job)$status, 0L)
  root <- file.path(job, "neon", "frozen_2021")
  dir.create(root, recursive = TRUE)
  if (!isTRUE(file.symlink(root, file.path(job, "ofo", "reference")))) skip("no symlinks")
  r <- run_driver("prepare_ofo_reference.R", job)
  expect_true(r$status != 0)
  expect_match(r$out, "Refusing to write outside")
  expect_length(list.files(root, recursive = TRUE, all.files = TRUE), 0)
})

test_that("paths under a root are resolved before the check", {
  base <- tempfile("ofo-paths-")
  dir.create(file.path(base, "ofo"), recursive = TRUE)
  dir.create(file.path(base, "neon"))
  on.exit(unlink(base, recursive = TRUE), add = TRUE)
  ofo <- file.path(base, "ofo")
  expect_true(ofo_path_under(file.path(ofo, "a", "b.csv"), ofo))
  expect_false(ofo_path_under(ofo, ofo))                          # strictly under
  expect_false(ofo_path_under(file.path(ofo, "..", "neon", "x"), ofo))
  expect_false(ofo_path_under(file.path(base, "neon", "x"), ofo))
  expect_false(ofo_path_under(NA_character_, ofo))
  if (isTRUE(file.symlink(file.path(base, "neon"), file.path(ofo, "link")))) {
    expect_false(ofo_path_under(file.path(ofo, "link", "new", "x.csv"), ofo))
    expect_false(ofo_path_under(file.path(ofo, "link"), ofo))
  }
  old <- setwd(base); on.exit(setwd(old), add = TRUE)
  expect_true(ofo_path_under("ofo/x", ofo))
  expect_false(ofo_path_under("neon/x", ofo))
})

test_that("decision driver: OUT=, extra registration columns, final admission only", {
  job <- tempfile("ofo-job-")
  out <- tempfile("ofo-out-")
  on.exit(unlink(c(job, out), recursive = TRUE), add = TRUE)
  w <- ofo_world()
  # The redesigned registration stage may drop `group` and add `method`; its
  # report carries more blocks than the final `admitted`.
  w$registration$group <- NULL
  w$registration$method <- "amendment_1b"
  w$tests <- list(status = "complete", admitted = list(height = TRUE, rank = FALSE),
                  test1_known_truth = list(height = list(pass = FALSE)),
                  amendment1 = list(confirmation = list(rank = list(admitted = TRUE))))
  pre <- write_world(w, job)
  before <- list.files(pre)
  r1 <- run_driver("preflight_ofo_decision.R", job, paste0("OUT=", out))
  expect_equal(r1$status, 0L, info = r1$out)
  expect_match(r1$out, "signals admitted: height TRUE, rank FALSE")
  expect_match(r1$out, "with a headline cell")
  # Outputs go to OUT only; the inputs directory gains nothing.
  expect_true(all(file.exists(file.path(out, c("cells.csv", "plot_admission.csv",
    "group_summary.csv", "group_decision.csv", "decision_record.json")))))
  expect_setequal(list.files(pre), before)
  dec <- read.csv(file.path(out, "group_decision.csv"), stringsAsFactors = FALSE)
  expect_equal(dec$decision, c("go", "no-go", "no-go", "no-go"))
  expect_true("plots_with_headline" %in% names(dec))
  rec <- jsonlite::read_json(file.path(out, "decision_record.json"), simplifyVector = TRUE)
  expect_equal(rec$inputs_dir, normalizePath(pre))
  # The same inputs with the default OUT give the same decision in place.
  r2 <- run_driver("preflight_ofo_decision.R", job)
  expect_equal(r2$status, 0L, info = r2$out)
  expect_identical(readLines(file.path(pre, "group_decision.csv")),
                   readLines(file.path(out, "group_decision.csv")))
  # OUT may not lie in the job directory outside OFO; unknown arguments stop.
  r3 <- run_driver("preflight_ofo_decision.R", job, paste0("OUT=", file.path(job, "neon", "x")))
  expect_true(r3$status != 0)
  expect_match(r3$out, "OUT must lie under")
  expect_false(dir.exists(file.path(job, "neon")))
  r4 <- run_driver("preflight_ofo_decision.R", job, "SITE=x")
  expect_true(r4$status != 0)
  expect_match(r4$out, "Unknown argument\\(s\\): SITE")
  # A report without the final `admitted` stops, naming the key.
  w$tests$admitted <- NULL
  jsonlite::write_json(w$tests, file.path(pre, "registration_tests.json"), auto_unbox = TRUE)
  write_records(pre)
  r5 <- run_driver("preflight_ofo_decision.R", job, paste0("OUT=", out))
  expect_true(r5$status != 0)
  expect_match(r5$out, "no top-level `admitted` key")
})

# PRJA holds go plots of group A (0101-0103, flown in 2020 and 2021) and of
# group C (0201, 0202, 0401, all flown in 2019).
ofo_world_mixed <- function() {
  w <- ofo_world()
  P <- w$plots
  P$project_name[P$plot_id %in% c("0201", "0202", "0401")] <- "PRJA"
  j <- P$plot_id == "0401"
  P$screen[j] <- "none"; P$group[j] <- "C"; P$survey_year[j] <- 2019L
  P$live_floor_cm[P$plot_id %in% c("0202", "0401")] <- 12.7
  w$plots <- P
  pn <- function(ids) P$project_name[match(ids, P$plot_id)]
  w$licences$project_name <- pn(w$licences$plot_id)
  w$flights$project_name <- pn(w$flights$plot_id)
  w$flights$flight_year[w$flights$plot_id == "0103"] <- 2021L
  w$flights$flight_year[w$flights$plot_id == "0401"] <- 2019L
  w$conditions$project_name <- pn(w$conditions$plot_id)
  k <- w$conditions$plot_id == "0202"
  w$conditions[k, c("disturbance_status", "disturbance_admitted", "conditions_admitted",
                    "conditions_reason")] <- list("undisturbed", TRUE, TRUE, NA)
  w$registration <- rbind(w$registration, data.frame(plot_id = "0401", group = "C",
    signal_used = "height", signal_admitted = TRUE, dx = 0, dy = 0, residual_m = 0.4,
    registered = TRUE, reason = NA, pos_unc = 0.5, stringsAsFactors = FALSE))
  w
}

test_that("reference driver: no directory mixes groups or flight years", {
  source(file.path("..", "..", "scripts", "neon_spatial_lib.R"), local = TRUE)
  job <- tempfile("ofo-job-")
  on.exit(unlink(job, recursive = TRUE), add = TRUE)
  w <- ofo_world_mixed()
  pre <- write_world(w, job)
  r1 <- run_driver("preflight_ofo_decision.R", job)
  expect_equal(r1$status, 0L, info = r1$out)
  dec <- read.csv(file.path(pre, "group_decision.csv"), stringsAsFactors = FALSE)
  expect_equal(dec$decision, c("go", "no-go", "go", "no-go"), info = r1$out)
  nd <- file.path(job, "ofo", "reference", "neon")
  # A partial run already uses the names of the full go set.
  r2 <- run_driver("prepare_ofo_reference.R", job, "GROUPS=C")
  expect_equal(r2$status, 0L, info = r2$out)
  expect_equal(list.files(nd), "PRJA_C")
  r3 <- run_driver("prepare_ofo_reference.R", job, "FORCE=TRUE")
  expect_equal(r3$status, 0L, info = r3$out)
  want <- c("PRJA_A_2020", "PRJA_A_2021", "PRJA_C")
  expect_equal(sort(list.files(nd)), want)
  for (s in want) {
    gt <- read.csv(file.path(nd, s, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    pc <- read.csv(file.path(nd, s, "plot_centroids.csv"), stringsAsFactors = FALSE)
    id <- ofo_check_site_tables(gt, pc, s)
    expect_equal(c(id$project, id$group), c("PRJA", if (s == "PRJA_C") "C" else "A"))
    expect_equal(id$acquisition_year, c(PRJA_A_2020 = 2020L, PRJA_A_2021 = 2021L,
                                        PRJA_C = 2019L)[[s]])
    expect_equal(neon_reference_epoch(gt, id$acquisition_year), id$acquisition_year)
    expect_equal(neon_validate_inputs(gt, pc), 32610L)
    expect_equal(sort(unique(gt$ofo_plot_id)), sort(unique(pc$ofo_plot_id)))
  }
  rec <- jsonlite::read_json(file.path(job, "ofo", "reference", "reference_record.json"),
                             simplifyVector = TRUE)
  expect_equal(rec$sites$site, want)
  expect_equal(rec$sites$project_name, rep("PRJA", 3))
  expect_equal(rec$sites$group, c("A", "A", "C"))
  expect_equal(rec$sites$acquisition_year, c(2020L, 2021L, 2019L))
  expect_equal(rec$sites$split_group, rep(TRUE, 3))
  expect_equal(rec$sites$split_year, c(TRUE, TRUE, FALSE))
  expect_equal(rec$sites$plot_ids, c("0101;0102", "0103", "0201;0202;0401"))
  expect_true(all(rec$sites$written))
  expect_equal(rec$go_groups, c("A", "C"))
  # A directory the current naming does not produce stops the run, FORCE or not.
  dir.create(file.path(nd, "PRJA"))
  file.copy(file.path(nd, "PRJA_C", "ground_truth_stems.csv"), file.path(nd, "PRJA"))
  r4 <- run_driver("prepare_ofo_reference.R", job, "FORCE=TRUE")
  expect_true(r4$status != 0)
  expect_match(r4$out, "move them aside")
})

test_that("a dangling symlink is followed, so a write cannot land outside ofo through it", {
  job <- file.path(tempfile("ofo_dangle_"), "job")
  ofo <- file.path(job, "ofo"); root <- file.path(job, "neon", "frozen_2021")
  dir.create(file.path(ofo, "reference"), recursive = TRUE); dir.create(root, recursive = TRUE)
  on.exit(unlink(dirname(job), recursive = TRUE), add = TRUE)
  # Absolute and relative dangling links, each aimed at a new file in the NEON root.
  abs_link <- file.path(ofo, "reference", "stems_all.csv")
  rel_link <- file.path(ofo, "rel.md")
  skip_if_not(file.symlink(file.path(root, "planted.csv"), abs_link))
  skip_if_not(file.symlink(file.path("..", "neon", "frozen_2021", "rel.md"), rel_link))
  expect_false(file.exists(abs_link))                       # dangling: the target is absent
  expect_identical(ofo_path_resolve(abs_link),
                   file.path(normalizePath(root), "planted.csv"))
  expect_false(ofo_output_allowed(abs_link, job, ofo))
  expect_false(ofo_output_allowed(rel_link, job, ofo))
  expect_false(ofo_path_under(abs_link, ofo))
  # A dangling link that stays inside ofo is still allowed.
  ok_link <- file.path(ofo, "inside.md")
  skip_if_not(file.symlink(file.path(ofo, "reference", "new.md"), ok_link))
  expect_true(ofo_output_allowed(ok_link, job, ofo))
  # A link pointing at itself must stop, not loop.
  loop <- file.path(ofo, "loop.md")
  skip_if_not(file.symlink(loop, loop))
  expect_error(ofo_path_resolve(loop), "Too many symbolic links")
})
