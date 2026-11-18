source(file.path("..", "..", "scripts", "baseline_smoothing_sensitivity.R"), local = TRUE)

# Synthetic null cells: two sites of two plots, one rung, observed
# ("baseline") and null variants. `twin` repeats the unsmoothed baseline.
synth_null_cells <- function() {
  cell <- function(variant, det, site, plot, n_ref, n_det, TP, tp_core)
    data.frame(variant = variant, site = site, plot = plot, rung = "4", detector = det,
               n_ref = n_ref, n_det = n_det, TP = TP, tp_core = tp_core, stringsAsFactors = FALSE)
  plots <- data.frame(site = c("A", "A", "B", "B"), plot = c("A_1", "A_2", "B_1", "B_2"),
                      n_ref = c(10, 8, 12, 6))
  counts <- list(
    chm_vwf            = list(baseline = c(6, 4, 7, 3), null = c(3, 2, 4, 1.5), det = c(9, 7, 10, 5)),
    chm_vwf_unsmoothed = list(baseline = c(8, 5, 9, 4), null = c(4.5, 2.5, 5, 2), det = c(14, 10, 15, 8)),
    multichm           = list(baseline = c(8, 6, 9, 4), null = c(4, 3, 5, 2), det = c(13, 11, 14, 7)),
    twin               = list(baseline = c(8, 5, 9, 4), null = c(4.5, 2.5, 5, 2), det = c(14, 10, 15, 8)))
  do.call(rbind, lapply(names(counts), function(det) do.call(rbind, lapply(c("baseline", "null"), function(v)
    cell(v, det, plots$site, plots$plot, plots$n_ref, counts[[det]]$det, counts[[det]][[v]],
         counts[[det]][[v]])))))
}
pooled_f1 <- function(x) {
  r <- sum(x$TP) / sum(x$n_ref); p <- sum(x$tp_core) / sum(x$n_det)
  2 * r * p / (r + p)
}
SCOPES <- list(both = c("A", "B"), first = "A", second = "B")

test_that("the null file names follow paper_sensitivity.R", {
  expect_equal(bs_null_file("j", 4), file.path("j", "sensitivity", "null_cells.csv"))
  expect_equal(bs_null_file("j", 2), file.path("j", "sensitivity", "null_tol2_cells.csv"))
  expect_equal(bs_null_file("j", 2.5, "delta"), file.path("j", "sensitivity", "null_tol2.5_delta.csv"))
})

test_that("corrected F1 and the null share come from pooled counts", {
  x <- synth_null_cells()
  res <- bs_corrected_rung(x, scopes = SCOPES, n_boot = 50, seed = 1)
  sc <- res$scores
  for (a in c("chm_vwf", "chm_vwf_unsmoothed", "multichm")) {
    o <- pooled_f1(x[x$detector == a & x$variant == "baseline", ])
    n <- pooled_f1(x[x$detector == a & x$variant == "null", ])
    got <- function(m) sc$estimate[sc$scope == "both" & sc$detector == a & sc$metric == m]
    expect_equal(got("F1"), o)
    expect_equal(got("null_F1"), n)
    expect_equal(got("null_share"), n / o)
    expect_equal(got("F1_corrected"), (o - n) / (1 - n))
  }
  # Regional scopes pool their own sites only.
  a1 <- x[x$detector == "multichm" & x$site == "A", ]
  expect_equal(sc$estimate[sc$scope == "first" & sc$detector == "multichm" & sc$metric == "F1"],
               pooled_f1(a1[a1$variant == "baseline", ]))
  expect_equal(unique(sc$n_plots[sc$scope == "both"]), 4)
  expect_equal(unique(sc$n_plots[sc$scope == "second"]), 2)
  expect_true(all(sc$lower <= sc$estimate + 1e-12 & sc$estimate <= sc$upper + 1e-12))
})

test_that("leads over either baseline are paired differences, observed and corrected", {
  x <- synth_null_cells()
  res <- bs_corrected_rung(x, scopes = SCOPES, n_boot = 50, seed = 1)
  sc <- res$scores; ld <- res$leads
  e <- function(a, m) sc$estimate[sc$scope == "both" & sc$detector == a & sc$metric == m]
  l <- function(ref, a, kind) ld[ld$scope == "both" & ld$from == paste(ref, "4", sep = "|") &
                                   ld$to == paste(a, "4", sep = "|") & ld$kind == kind, ]
  expect_equal(l("chm_vwf_unsmoothed", "multichm", "observed")$estimate,
               e("multichm", "F1") - e("chm_vwf_unsmoothed", "F1"))
  expect_equal(l("chm_vwf_unsmoothed", "multichm", "corrected")$estimate,
               e("multichm", "F1_corrected") - e("chm_vwf_unsmoothed", "F1_corrected"))
  expect_equal(l("chm_vwf", "chm_vwf_unsmoothed", "corrected")$estimate,
               e("chm_vwf_unsmoothed", "F1_corrected") - e("chm_vwf", "F1_corrected"))
  expect_equal(unique(l("chm_vwf_unsmoothed", "multichm", "observed")$contrast), "lead over unsmoothed")
  # A detector with the reference's counts leads it by zero in every resample.
  tw <- l("chm_vwf_unsmoothed", "twin", "corrected")
  expect_equal(c(tw$estimate, tw$lower, tw$upper), c(0, 0, 0))
  # No lead of a reference over itself; a missing reference gives no leads.
  expect_false(any(ld$from == ld$to))
  r2 <- bs_corrected_rung(x[x$detector != "chm_vwf", ], scopes = SCOPES, n_boot = 50, seed = 1)
  expect_false(any(r2$leads$contrast == "lead over smoothed"))
})

test_that("the corrected tables use the plots every detector and variant scored", {
  x <- synth_null_cells()
  x <- x[!(x$detector == "multichm" & x$variant == "null" & x$plot == "B_2"), ]
  res <- bs_corrected_rung(x, scopes = SCOPES, n_boot = 50, seed = 1)
  expect_equal(unique(res$scores$n_plots[res$scores$scope == "both"]), 3)
  kept <- x[x$detector == "chm_vwf" & x$variant == "baseline" & x$plot != "B_2", ]
  expect_equal(res$scores$estimate[res$scores$scope == "both" & res$scores$detector == "chm_vwf" &
                                     res$scores$metric == "F1"], pooled_f1(kept))
  expect_error(bs_corrected_rung(rbind(x, transform(x, rung = "2")), scopes = SCOPES, n_boot = 5),
               "One rung")
  expect_error(bs_corrected_rung(x[x$variant == "baseline", ], scopes = SCOPES, n_boot = 5),
               "baseline and null")
})

test_that("null cells are read per radius, filtered and relabelled", {
  job <- tempfile("bsjob"); dir.create(file.path(job, "sensitivity"), recursive = TRUE)
  on.exit(unlink(job, recursive = TRUE))
  x <- synth_null_cells()
  x$detector[x$detector == "chm_vwf_unsmoothed"] <- "lmfauto"
  write.csv(x, bs_null_file(job, 2), row.names = FALSE)
  expect_null(bs_read_null(job, 4, "chm_vwf", "4"))
  got <- bs_read_null(job, 2, "chm_vwf", c("4", "3.2"), label = UNSMOOTHED)
  expect_equal(unique(got$detector), UNSMOOTHED)
  expect_equal(nrow(got), 8)
  expect_type(got$rung, "character")
  expect_null(bs_read_null(job, 2, "chm_vwf", "3.2"))
  expect_error(bs_read_null(job, 2, c("chm_vwf", "multichm"), "4", label = "x"), "one detector")
})

test_that("a rung's own job directories must repeat the main native cells", {
  main <- data.frame(site = "A", plot = c("A_1", "A_2"), rung = "native", detector = "chm_vwf",
                     n_ref = c(10, 8), n_det = c(9, 7), TP = c(6, 4), precision = c(6 / 9, 4 / 7),
                     stringsAsFactors = FALSE)
  other <- rbind(main, transform(main, rung = "3.2", TP = c(1, 1)))
  expect_equal(nrow(bs_native_mismatch(main, other)), 0)
  expect_equal(attr(bs_native_mismatch(main, other), "within_slack"), 0)
  # One more core detection, unmatched: within lasR's run-to-run variation.
  one <- other; one$n_det[2] <- 8; one$precision[2] <- 4 / 8
  expect_equal(nrow(bs_native_mismatch(main, one)), 0)
  expect_equal(attr(bs_native_mismatch(main, one), "within_slack"), 1)
  two <- other; two$n_det[2] <- 9; two$precision[2] <- 4 / 9
  expect_equal(bs_native_mismatch(main, two)$plot, "A_2")
  expect_equal(nrow(bs_native_mismatch(main, two, slack = 2)), 0)
  other$TP[1] <- 5
  expect_equal(bs_native_mismatch(main, other)$plot, "A_1")
  extra <- rbind(main, transform(main[1, ], plot = "A_9"))
  expect_equal(bs_native_mismatch(main, extra)$plot, "A_9")
  expect_equal(nrow(bs_native_mismatch(main, other[other$rung == "3.2", ])), 0)
})

test_that("bs_max_diff compares estimates and intervals and flags missing rows", {
  a <- data.frame(scope = "s", rung = c("1", "2"), estimate = c(0.1, 0.2), lower = 0, upper = 1)
  expect_equal(bs_max_diff(a, a, c("scope", "rung")), 0)
  b <- transform(a, upper = upper + c(0, 1e-6))
  expect_equal(bs_max_diff(a, b, c("scope", "rung")), 1e-6)
  expect_equal(bs_max_diff(a, a[1, ], c("scope", "rung")), Inf)
  expect_equal(bs_max_diff(a[0, ], a, c("scope", "rung")), 0)
})

test_that("the null re-score's own corrected F1 and leads are read and relabelled", {
  job <- tempfile("bsref"); dir.create(file.path(job, "sensitivity"), recursive = TRUE)
  on.exit(unlink(job, recursive = TRUE))
  dl <- data.frame(scope = "five sites", stratum = c("all", "all", "overstory"), detector = "chm_vwf",
                   rung = c("4", "4", "4"), from = "f", to = "t", metric = c("F1_scaled", "F1", "F1_scaled"),
                   estimate = c(0.2, 0.4, 0.3), lower = 0.1, upper = 0.3, defined_draws = 10)
  write.csv(dl, bs_null_file(job, 4, "delta"), row.names = FALSE)
  writeLines('""', bs_null_file(job, 4, "leads"))        # a re-score of CHM-VWF alone
  r <- bs_null_reference(job, 4, "4", UNSMOOTHED)
  expect_equal(r$delta$estimate, 0.2)
  expect_equal(r$delta$detector, UNSMOOTHED)
  expect_null(r$leads)
  ld <- data.frame(scope = "five sites", stratum = "all", detector = "multichm", rung = "4", metric = "F1",
                   kind = c("observed", "null", "above_null", "above_null_scaled"),
                   estimate = 1:4, lower = 0, upper = 5, defined_draws = 10)
  write.csv(ld, bs_null_file(job, 4, "leads"), row.names = FALSE)
  r <- bs_null_reference(job, 4, "4")
  expect_equal(r$leads$kind, c("observed", "corrected"))
  expect_equal(r$leads$estimate, c(1, 4))
  expect_equal(unique(r$leads$to), "multichm|4")
  expect_error(bs_null_reference(file.path(job, "none"), 4, "4"), "No null re-score summary")
})

test_that("the observed rung tables pool the six arms and the dominant stems", {
  set.seed(3)
  dets <- c(UNSMOOTHED, "chm_vwf", ARMS)
  rows <- do.call(rbind, lapply(dets, function(a) data.frame(
    site = rep(c("A", "B"), each = 3), plot = paste0("p", 1:6), rung = "3.2", detector = a,
    n_ref = 10, n_det = 12, TP = sample(3:8, 6, TRUE), precision = 0.5,
    rec_dominant = 0.5, n_dominant = 4, stringsAsFactors = FALSE)))
  rows$tp_core <- round(rows$precision * rows$n_det)
  o <- bs_observed_rung(rows)
  expect_setequal(unique(o$est$detector), dets)
  expect_equal(nrow(o$con), 3 + 2 * length(ARMS))
  expect_equal(unique(o$con$rung), "3.2")
  f1 <- function(a) o$est$estimate[o$est$detector == a & o$est$metric == "F1"]
  u <- o$con[o$con$contrast == "unsmoothed minus smoothed" & o$con$metric == "F1", ]
  expect_equal(u$estimate, f1(UNSMOOTHED) - f1("chm_vwf"))
  expect_equal(o$dom$tp, c(12, 12)); expect_equal(o$dom$recall, c(0.5, 0.5))
})
