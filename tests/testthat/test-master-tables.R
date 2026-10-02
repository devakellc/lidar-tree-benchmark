source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)

cells <- function(arm, site, plot, TP, n_ref, tp_core, n_det, rung = "native")
  data.frame(site = site, plot = plot, rung = rung, detector = arm, TP = TP,
             n_ref = n_ref, tp_core = tp_core, n_det = n_det,
             precision = ifelse(n_det > 0, tp_core / n_det, NA_real_),
             stringsAsFactors = FALSE)

test_that("plot resamples are seeded, stratified by site and leave the RNG alone", {
  site <- c(rep("A", 3), rep("B", 5)); plot <- paste0("p", 1:8)
  set.seed(99); before <- runif(1); set.seed(99)
  W1 <- mt_plot_weights(site, plot, n_boot = 50, seed = 7)
  expect_identical(runif(1), before)                 # caller's stream untouched
  W2 <- mt_plot_weights(rev(site), rev(plot), n_boot = 50, seed = 7)
  expect_identical(W1, W2)                           # order of input does not matter
  expect_false(identical(W1, mt_plot_weights(site, plot, n_boot = 50, seed = 8)))
  a <- grepl("^A::", rownames(W1))
  expect_true(all(colSums(W1[a, ]) == 3) && all(colSums(W1[!a, ]) == 5))
})

test_that("pooled scores sum counts and match pool()", {
  rows <- rbind(cells("x", "A", "p1", 1, 2, 1, 10), cells("x", "A", "p2", 30, 40, 20, 25))
  W <- mt_plot_weights(rows$site, rows$plot, n_boot = 20, seed = 1)
  s <- mt_boot_scores(rows, W, c("detector", "rung"))
  expect_equal(s$estimate$recall, 31 / 42)           # not mean(0.5, 0.75)
  expect_equal(s$estimate$precision, 21 / 35)
  ref <- pool(transform(rows, F1 = NA, recall = TP / n_ref,
                        n_dominant = 0, n_codominant = 0, n_intermediate = 0, n_suppressed = 0,
                        rec_dominant = NA, rec_codominant = NA, rec_intermediate = NA,
                        rec_suppressed = NA))
  expect_equal(s$estimate$recall, ref$recall)
  expect_equal(s$estimate$precision, ref$precision)
  expect_equal(s$estimate$F1, ref$F1)
  expect_equal(dim(s$draws$F1), c(20L, 1L))
})

test_that("contrasts are paired: identical arms give a zero interval", {
  base <- rbind(cells("x", "A", "p1", 3, 5, 3, 6), cells("x", "A", "p2", 1, 9, 2, 4),
                cells("x", "B", "p3", 4, 4, 4, 9))
  rows <- rbind(base, transform(base, detector = "y"),
                transform(base, detector = "z", TP = TP - c(1, 0, 1)))
  W <- mt_plot_weights(rows$site, rows$plot, n_boot = 200, seed = 3)
  s <- mt_boot_scores(rows, W, c("detector", "rung"))
  same <- mt_contrast(s, "x|native", "y|native", "recall")
  expect_equal(c(same$estimate, same$lower, same$upper), c(0, 0, 0))
  worse <- mt_contrast(s, "x|native", "z|native", "recall")
  expect_lt(worse$estimate, 0)
  expect_lte(worse$upper, 0)                          # z never beats x in any draw
  ci <- mt_intervals(s)
  expect_setequal(unique(ci$metric), c("recall", "precision", "F1"))
  expect_true(all(ci$lower <= ci$estimate + 1e-12 & ci$estimate <= ci$upper + 1e-12, na.rm = TRUE))
})

test_that("unequal support is refused and equal_set_guard trims it per rung", {
  rows <- rbind(cells("x", "A", "p1", 1, 2, 1, 2), cells("x", "A", "p2", 1, 2, 1, 2),
                cells("y", "A", "p1", 1, 2, 1, 2))
  W <- mt_plot_weights(rows$site, rows$plot, n_boot = 5, seed = 1)
  expect_error(mt_boot_scores(rows, W, c("detector", "rung")), "equal support")
  eq <- mt_equal_support(rows, c("x", "y"))
  expect_setequal(eq$plot, "p1")
  expect_identical(attr(eq, "dropped"), "A::p2::native")
  expect_error(mt_boot_scores(rbind(rows[1, ], rows[1, ]), W, c("detector", "rung")),
               "Duplicate")
})

test_that("reference rules: whole-plot six-stem gate versus six core stems", {
  pc <- data.frame(plotID = c("P1", "P2"), plotType = "distributed",
                   easting = c(0, 100), northing = 0, stringsAsFactors = FALSE)
  # P1: 6 live trees, 4 in the +/-10 m core; P2: 7 trees, all in the core.
  gt <- data.frame(plotID = c(rep("P1", 6), rep("P2", 7)),
                   E = c(0, 1, 2, 3, 15, 16, rep(100, 7)), N = 0, live = TRUE,
                   is_tree = TRUE, stemDiameter = c(5, 12, 12, 12, 12, 12, rep(20, 7)),
                   canopyPosition = NA, crown_class = "dominant", stringsAsFactors = FALSE)
  whole <- mt_reference_counts(gt, pc, "all_mapped", 6L, "whole")
  expect_identical(whole$plotID, c("P1", "P2")); expect_identical(whole$n_core, c(4L, 7L))
  core <- mt_reference_counts(gt, pc, "all_mapped", 6L, "core")
  expect_identical(core$plotID, "P2")
  dbh <- mt_reference_counts(gt, pc, "dbh10", 6L, "whole")
  expect_identical(dbh$plotID, "P2")                 # P1 has only 5 trees >= 10 cm
})
