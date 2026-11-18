source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_preflight_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_registration_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_reference_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_disturbance_lib.R"), local = TRUE)

# Protocol 2 names a signal test with too few units inconclusive, apart from
# one that failed. The second preflight reads the first as a check that could
# not be made, which leaves its group eligible for hold; a failed test makes
# it no-go. Protocol 1 inputs carry neither field and keep the
# old rule.

adm_fixture <- function(registered, reg_check, cond_admitted, cond_check) {
  n <- length(registered)
  plots <- data.frame(plot_id = sprintf("%04d", seq_len(n)), project_name = "P",
                      group = "A", screen = "none", stringsAsFactors = FALSE)
  flights <- data.frame(plot_id = plots$plot_id, flight_admitted = TRUE,
                        flight_reason = "", stringsAsFactors = FALSE)
  geometry <- data.frame(plot_id = plots$plot_id, geometry_consistent = TRUE)
  conditions <- data.frame(plot_id = plots$plot_id, conditions_admitted = cond_admitted,
                           disturbance_status = ifelse(cond_check == "unchecked",
                                                       "not_checked",
                                                       ifelse(cond_admitted, "undisturbed",
                                                              "disturbed")),
                           disturbance_admitted = cond_admitted,
                           snow_status = "not_winter", leafoff_status = "leaf_on",
                           conditions_reason = "", stringsAsFactors = FALSE)
  registration <- data.frame(plot_id = plots$plot_id, registered = registered,
                             reason = "", stringsAsFactors = FALSE)
  if (!is.null(reg_check)) registration$registration_check <- reg_check
  list(plots = plots, flights = flights, geometry = geometry, conditions = conditions,
       registration = registration)
}

test_that("an unchecked registration makes a plot hold-eligible only with no evidence failure", {
  f <- adm_fixture(registered = c(FALSE, FALSE, FALSE, FALSE, TRUE),
                   reg_check = c("unchecked", "unchecked", "evidence", "unchecked", "registered"),
                   cond_admitted = c(TRUE, FALSE, TRUE, FALSE, FALSE),
                   cond_check = c("admitted", "unchecked", "admitted", "evidence", "unchecked"))
  a <- ofo_plot_admission(f$plots, f$flights, f$geometry, f$conditions, f$registration)
  expect_identical(a$registration_check,
                   c("unchecked", "unchecked", "evidence", "unchecked", "registered"))
  # 1: registration unchecked, conditions pass -> eligible
  # 2: both unchecked -> eligible
  # 3: registration failed on evidence -> not eligible
  # 4: conditions failed on evidence -> not eligible
  # 5: registered, conditions unchecked -> eligible (protocol 1's case)
  expect_identical(a$unchecked_only, c(TRUE, TRUE, FALSE, FALSE, TRUE))
  expect_true(all(!a$admitted))
})

test_that("without a registration_check column the protocol-1 rule and columns are unchanged", {
  f <- adm_fixture(registered = c(FALSE, TRUE, TRUE), reg_check = NULL,
                   cond_admitted = c(FALSE, FALSE, TRUE),
                   cond_check = c("unchecked", "unchecked", "admitted"))
  a <- ofo_plot_admission(f$plots, f$flights, f$geometry, f$conditions, f$registration)
  expect_false("registration_check" %in% names(a))
  # A registration failure is evidence; only a registered plot with unchecked
  # conditions is eligible, as before.
  expect_identical(a$unchecked_only, c(FALSE, TRUE, FALSE))
  expect_identical(a$admitted, c(FALSE, FALSE, TRUE))
})

decision_fixture <- function(n_admitted, n_unchecked, stems_each = 50) {
  n <- n_admitted + n_unchecked
  data.frame(plot_id = sprintf("%04d", seq_len(n)), group = "A",
             admitted = c(rep(TRUE, n_admitted), rep(FALSE, n_unchecked)),
             unchecked_only = c(rep(FALSE, n_admitted), rep(TRUE, n_unchecked)),
             n_ref_headline = c(rep(stems_each, n_admitted), rep(0, n_unchecked)),
             n_ref_headline_hold = rep(stems_each, n),
             license_short = "CC BY 4.0", stringsAsFactors = FALSE)
}

test_that("an inconclusive signal test allows hold; a failed one is no-go", {
  adm <- decision_fixture(0, 3)
  sig <- c(height = FALSE, rank = FALSE)
  d_inc <- ofo_group_decision(adm, sig, inconclusive = c(height = TRUE, rank = TRUE))
  expect_identical(d_inc$decision[d_inc$group == "A"], "hold")
  expect_true(d_inc$signal_inconclusive[d_inc$group == "A"])
  expect_match(d_inc$reasons[d_inc$group == "A"], "inconclusive")
  d_fail <- ofo_group_decision(adm, sig, inconclusive = c(height = FALSE, rank = FALSE))
  expect_identical(d_fail$decision[d_fail$group == "A"], "no-go")
  # Hold still needs rule 2 over the eligible plots: two plots are too few.
  d_few <- ofo_group_decision(decision_fixture(0, 2), sig,
                              inconclusive = c(height = TRUE, rank = TRUE))
  expect_identical(d_few$decision[d_few$group == "A"], "no-go")
})

test_that("protocol 1 (no inconclusive record) keeps hold behind an admitted signal", {
  adm <- decision_fixture(0, 3)
  d <- ofo_group_decision(adm, c(height = FALSE, rank = FALSE))
  expect_identical(d$decision[d$group == "A"], "no-go")
  expect_false("signal_inconclusive" %in% names(d))
  d2 <- ofo_group_decision(adm, c(height = TRUE, rank = FALSE))
  expect_identical(d2$decision[d2$group == "A"], "hold")
})

test_that("catalogue rows are unchecked only when the inconclusive signal is their sole failure", {
  plots <- data.frame(plot_id = c("0001", "0002", "0003"), project_name = "P", group = "A",
                      screen = "none", stringsAsFactors = FALSE)
  flights <- data.frame(plot_id = plots$plot_id, flight_admitted = c(TRUE, TRUE, FALSE),
                        cloud_status = "ok", stringsAsFactors = FALSE)
  cat <- data.frame(plot_id = rep(plots$plot_id, each = 2), signal = c("height", "rank"),
                    method = "amendment1", set = "candidate", n_signal = 100,
                    dx = c(1, 1.2, 1, 1, 1, 1), dy = 0, shift_m = 1, residual_m = 0.5,
                    contrast = 0.3, accepted = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
                    reject_reason = "", sub_p90_m = 0.2, on_edge = FALSE,
                    second_peak = c(0.5, 0.5, 0.9, 0.5, 0.5, 0.5), stringsAsFactors = FALSE)
  r <- ofo_p2_registration(plots, flights, cat, c(height = FALSE, rank = FALSE),
                           groups = "A", inconclusive = c(height = TRUE, rank = TRUE))
  # 0001 passes its own gates; 0002 fails one clear peak; 0003 has no admitted flight
  expect_identical(r$registration_check, c("unchecked", "evidence", "evidence"))
  expect_true(all(!r$registered))
  r2 <- ofo_p2_registration(plots, flights, cat, c(height = FALSE, rank = FALSE), groups = "A")
  expect_identical(r2$registration_check, c("evidence", "evidence", "evidence"))
  r3 <- ofo_p2_registration(plots, flights, cat, c(height = TRUE, rank = TRUE), groups = "A")
  expect_identical(r3$registration_check, c("registered", "evidence", "evidence"))
})

test_that("a frozen-gate rejection, a disagreement or too few stems is evidence", {
  ids <- c("0001", "0002", "0003", "0004")
  plots <- data.frame(plot_id = ids, project_name = "P", group = "A", screen = "none",
                      stringsAsFactors = FALSE)
  flights <- data.frame(plot_id = ids, flight_admitted = TRUE, cloud_status = "ok",
                        stringsAsFactors = FALSE)
  cat <- data.frame(plot_id = rep(ids, each = 2), signal = c("height", "rank"),
                    method = "amendment1", set = "candidate",
                    n_signal = c(100, 100, 100, 100, 100, 100, 5, 100),
                    dx = c(1, 1, 1, 1, 1, 4, 1, 1), dy = 0, shift_m = 1, residual_m = 0.5,
                    contrast = 0.3,
                    accepted = c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE),
                    reject_reason = c("", "", "on_edge", "", "", "", "", ""),
                    sub_p90_m = 0.2, on_edge = c(FALSE, FALSE, TRUE, rep(FALSE, 5)),
                    second_peak = 0.5, stringsAsFactors = FALSE)
  r <- ofo_p2_registration(plots, flights, cat, c(height = FALSE, rank = FALSE),
                           groups = "A", inconclusive = c(height = TRUE, rank = TRUE))
  # 0001 clean; 0002 rejected on edge; 0003 signals 3 m apart; 0004 five stems
  expect_identical(r$registration_check, c("unchecked", "evidence", "evidence", "evidence"))
})

test_that("an unchecked registration with a screen, flight or geometry failure is not eligible", {
  f <- adm_fixture(registered = rep(FALSE, 4), reg_check = rep("unchecked", 4),
                   cond_admitted = c(TRUE, TRUE, FALSE, TRUE),
                   cond_check = c("admitted", "admitted", "unchecked", "admitted"))
  f$geometry$geometry_consistent <- c(TRUE, FALSE, TRUE, TRUE)
  f$flights$flight_admitted <- c(TRUE, TRUE, FALSE, TRUE)
  f$plots$screen[4] <- "nested_hyperplot"
  a <- ofo_plot_admission(f$plots, f$flights, f$geometry, f$conditions, f$registration)
  # 1 clean; 2 geometry; 3 no admitted flight; 4 screened out
  expect_identical(a$unchecked_only, c(TRUE, FALSE, FALSE, FALSE))
})
