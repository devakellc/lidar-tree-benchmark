# Unit tests for the plot-subset helpers of census_null_lib.R used by
# paper_null_subsets.R (the paper's nominal-box null pooled on plot subsets).
# All synthetic; no NEON data.
source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "census_null_lib.R"), local = TRUE)

plots <- data.frame(site = c("SOAP", "SOAP", "SOAP", "WREF", "WREF"),
                    plot = c("SOAP_002", "SOAP_005", "SOAP_008", "WREF_001", "WREF_070"),
                    plotType = c("distributed", "tower", "tower", "tower", "distributed"),
                    stringsAsFactors = FALSE)

test_that("subsets select plot types or drop the excluded plots", {
  expect_identical(ns_subset_keys(plots, "all"), sort(paste(plots$site, plots$plot, sep = "::")))
  expect_identical(ns_subset_keys(plots, "tower"), c("SOAP::SOAP_005", "SOAP::SOAP_008", "WREF::WREF_001"))
  expect_identical(ns_subset_keys(plots, "distributed"), c("SOAP::SOAP_002", "WREF::WREF_070"))
  expect_identical(ns_subset_keys(plots, "exclude", c("SOAP_002", "SOAP_008")),
                   c("SOAP::SOAP_005", "WREF::WREF_001", "WREF::WREF_070"))
  expect_error(ns_subset_keys(plots, "exclude", "SOAP_099"), "not in the population")
  expect_error(ns_subset_keys(plots, "burnt"), "Unknown subset")
})

test_that("quadrant counts find the two fullest 20 m quadrants of a tower core", {
  q <- ns_quadrants(dx = c(5, 6, 7, -3, -4, 2, 0), dy = c(5, -6, 7, 3, 4, -2, 0))
  # NE: (5,5) (7,7) (0,0); SE: (6,-6) (2,-2); NW: (-3,3) (-4,4); SW: none.
  expect_equal(q$stems, 7L)
  expect_equal(q$quadrants_with_stems, 3L)
  expect_equal(q$top2_stems, 5)
  one <- ns_quadrants(dx = c(1, 2), dy = c(1, 2))
  expect_equal(c(one$quadrants_with_stems, one$top2_stems), c(1, 2))
})

test_that("a subset pools only its plots, on resamples drawn over its plots", {
  cell <- function(variant, plot, arm, TP, n_det) data.frame(variant = variant,
    site = sub("_.*", "", plot), plot = plot, rung = "native", detector = arm, n_ref = 10,
    n_det = n_det, TP = TP, tp_core = TP, stringsAsFactors = FALSE)
  arms <- c("chm_vwf", "segmentanytree")
  x <- do.call(rbind, lapply(seq_len(nrow(plots)), function(i) do.call(rbind, lapply(arms, function(a) {
    b <- if (a == "chm_vwf") 0 else 1
    rbind(cell("observed", plots$plot[i], a, 4 + i + b, 9 + b), cell("null", plots$plot[i], a, 2 + b / 2, 9 + b))
  }))))
  keys <- ns_subset_keys(plots, "tower")
  xs <- x[paste(x$site, x$plot, sep = "::") %in% keys, ]
  W <- mt_plot_weights(xs$site, xs$plot, n_boot = 100, seed = 20261002)
  expect_identical(rownames(W), keys)
  p <- cn_pool(xs, W, list(`five sites` = c("SOAP", "WREF")))
  o <- p$est[p$est$detector == "chm_vwf" & p$est$variant == "observed" & p$est$metric == "recall", ]
  expect_equal(o$estimate, sum(c(6, 7, 8)) / 30)      # tower plots 2, 3 and 4 only
  expect_equal(o$n_plots, 3L)
  # The whole set pooled on its own resamples is unaffected by the subset.
  Wa <- mt_plot_weights(x$site, x$plot, n_boot = 100, seed = 20261002)
  pa <- cn_pool(x, Wa, list(`five sites` = c("SOAP", "WREF")))
  oa <- pa$est[pa$est$detector == "chm_vwf" & pa$est$variant == "observed" & pa$est$metric == "recall", ]
  expect_equal(oa$estimate, sum(5:9) / 50)
  expect_false(isTRUE(all.equal(oa$lower, o$lower)))
})
