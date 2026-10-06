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

strata_cells <- function(arm, plot, rec_dom, n_dom, rec_sup, n_sup) {
  x <- cells(arm, "A", plot, TP = 0, n_ref = n_dom + n_sup, tp_core = 0, n_det = 0)
  for (k in c("dominant", "codominant", "intermediate", "suppressed", "h_short",
              "h_mid", "h_tall")) { x[[paste0("rec_", k)]] <- NA_real_; x[[paste0("n_", k)]] <- 0L }
  x$rec_dominant <- rec_dom; x$n_dominant <- n_dom
  x$rec_suppressed <- rec_sup; x$n_suppressed <- n_sup
  x
}

test_that("stratum rows recover per-class true positives and pool classes by counts", {
  x <- rbind(strata_cells("a", "p1", 2 / 3, 3L, 0.5, 2L), strata_cells("a", "p2", NA, 0L, 1, 1L))
  s <- mt_stratum_rows(x)
  expect_setequal(unique(s$stratum), names(MT_STRATA))
  dom <- s[s$stratum == "dominant", ]
  expect_equal(dom$TP, c(2, 0)); expect_equal(dom$n_ref, c(3, 0))
  under <- s[s$stratum == "understory", ]
  expect_equal(under$TP, c(1, 1)); expect_equal(under$n_ref, c(2, 1))
  expect_null(mt_stratum_rows(x[, setdiff(names(x), "rec_h_tall")]))
})

test_that("rank stability is the Spearman correlation of arm F1 between rungs", {
  arms <- c("a", "b", "c", "d")
  mk <- function(rung, tps) do.call(rbind, lapply(seq_along(arms), function(i) rbind(
    cells(arms[i], "A", "p1", tps[i], 10, tps[i], 10, rung),
    cells(arms[i], "A", "p2", tps[i], 10, tps[i], 10, rung),
    cells(arms[i], "B", "p3", tps[i], 10, tps[i], 10, rung))))
  same <- mt_rank_stability(rbind(mk("native", 1:4), mk("8", 2:5)), "native", "8", n_boot = 50)
  expect_equal(same$estimate, 1); expect_equal(same$arms, 4L); expect_equal(same$lower, 1)
  flip <- mt_rank_stability(rbind(mk("native", 1:4), mk("8", 4:1)), "native", "8", n_boot = 50)
  expect_equal(flip$estimate, -1)
  expect_null(mt_rank_stability(rbind(mk("native", 1:4)[1:6, ], mk("8", 1:4)[1:6, ]),
                                "native", "8", n_boot = 10))
  # Leaving out the one arm that moves restores the order of the others.
  moved <- rbind(mk("native", 1:4), mk("8", c(5, 2, 3, 4)))
  expect_lt(mt_rank_stability(moved, "native", "8", n_boot = 20)$estimate, 0.5)
  left <- mt_rank_stability(moved, "native", "8", n_boot = 20, exclude = "a")
  expect_equal(left$estimate, 1); expect_equal(left$arms, 3L)
  expect_null(mt_rank_stability(moved, "native", "8", n_boot = 10, exclude = c("a", "b")))
})

test_that("regional leads difference the lead over a base arm between regions", {
  x <- rbind(cells("base", "SJER", "s1", 5, 10, 5, 10), cells("arm", "SJER", "s1", 8, 10, 8, 10),
             cells("base", "WREF", "w1", 5, 10, 5, 10), cells("arm", "WREF", "w1", 6, 10, 6, 10))
  W <- mt_plot_weights(x$site, x$plot, n_boot = 20)
  r <- mt_region_leads(x, W, "base", list(California = "SJER", Washington = "WREF"))
  expect_equal(r$lead_california, 0.3); expect_equal(r$lead_washington, 0.1)
  expect_equal(r$estimate, 0.2); expect_equal(c(r$lower, r$upper), c(0.2, 0.2))
  expect_null(mt_region_leads(x[x$site == "SJER", ], W[1, , drop = FALSE], "base",
                              list(California = "SJER", Washington = "WREF")))
})

test_that("rung contrasts pair each arm's rungs on their shared plots", {
  x <- rbind(cells("a", "A", "p1", 6, 10, 6, 10), cells("a", "A", "p2", 4, 10, 4, 10),
             cells("a", "A", "p1", 3, 10, 3, 10, "8"), cells("a", "A", "p2", 2, 10, 2, 10, "8"),
             cells("a", "A", "p3", 9, 10, 9, 10, "8"))
  r <- mt_rung_contrasts(x, list(all = "A"), n_boot = 50)
  rec <- r[r$metric == "recall", ]
  expect_equal(rec$rung, "8"); expect_equal(rec$estimate, (5 - 10) / 20)
  expect_true(rec$lower <= rec$estimate && rec$upper >= rec$estimate)
  expect_null(mt_rung_contrasts(x[x$rung == "8", ], list(all = "A")))
})
