# Unit tests for core_density_lib.R: counts of first returns and all returns
# inside the nominal plot core, in the clip's outer ring and over the whole
# clip, with the frozen-clip provider's height filter; the summaries and the
# sparse-flight comparison. Synthetic clouds only.
source(file.path("..", "..", "scripts", "core_density_lib.R"), local = TRUE)

# A distributed-plot clip (core half-side 10 m, buffer 25 m, so a 70 m
# square) centred on (500, 1000). One pulse per 1 m cell centre over the clip
# (4,900 first returns); a second return under each pulse in the outer 5 m
# ring, so the ring is twice as dense in all returns; two returns outside the
# height filter (one at Z = 80, one at Z = -1.5), which every count drops.
synth_clip <- function() {
  g <- expand.grid(X = 500 - 34.5 + 0:69, Y = 1000 - 34.5 + 0:69)
  g$Z <- 10; g$ReturnNumber <- 1L
  ring <- g[abs(g$X - 500) > 30 | abs(g$Y - 1000) > 30, ]
  ring$Z <- 5; ring$ReturnNumber <- 2L
  bad <- data.frame(X = c(500.5, 500.5), Y = c(1000.5, 1000.5), Z = c(80, -1.5),
                    ReturnNumber = c(1L, 1L))
  rbind(g, ring, bad)
}

test_that("counts split the core, the outer ring and the whole clip", {
  p <- synth_clip()
  x <- cd_counts(p$X, p$Y, p$Z, p$ReturnNumber, 500, 1000, 10, 25)
  n_ring <- 70^2 - 60^2                                   # 1 m cells in the outer 5 m
  expect_equal(x$n_fr_clip, 4900)
  expect_equal(x$n_all_clip, 4900 + n_ring)
  expect_equal(x$n_fr_core, 400); expect_equal(x$n_all_core, 400)   # 20 x 20 cells
  expect_equal(x$n_fr_ring, n_ring); expect_equal(x$n_all_ring, 2 * n_ring)
  expect_equal(x$n_dropped_z, 2)
  expect_equal(x$clip_frdens, 1); expect_equal(x$core_frdens, 1); expect_equal(x$core_pdens, 1)
  expect_equal(x$clip_pdens, (4900 + n_ring) / 4900)
  expect_equal(x$ring_pdens, 2); expect_equal(x$ring_frdens, 1)
})

test_that("the core includes its bounds and the height filter matches the provider", {
  p <- data.frame(X = c(510, 510.01, 490, 500, 500, 500), Y = c(1010, 1000, 990, 1000, 1000, 1000),
                  Z = c(1, 1, 1, -1, 79.99, 80), ReturnNumber = c(1L, 1L, 2L, 1L, 1L, 1L))
  x <- cd_counts(p$X, p$Y, p$Z, p$ReturnNumber, 500, 1000, 10, 25)
  expect_equal(x$n_all_core, 4)              # corners on the bound, Z = -1 and 79.99; not 510.01 or Z = 80
  expect_equal(x$n_fr_core, 3)
  expect_equal(x$n_all_clip, 5); expect_equal(x$n_dropped_z, 1)
})

test_that("a wrong centre, bad geometry or ragged input stops", {
  p <- synth_clip()
  expect_error(cd_counts(p$X, p$Y, p$Z, p$ReturnNumber, 490, 1000, 10, 25), "outside the clip")
  expect_error(cd_counts(p$X, p$Y, p$Z, p$ReturnNumber, 500, 1000, 0, 25), "geometry")
  expect_error(cd_counts(p$X, p$Y[-1], p$Z, p$ReturnNumber, 500, 1000, 10, 25), "same length")
  expect_error(cd_counts(p$X, p$Y, replace(p$Z, 1, NA), p$ReturnNumber, 500, 1000, 10, 25), "Missing")
})

test_that("a lidR LAS clip gives the same counts", {
  skip_if_not_installed("lidR")
  p <- synth_clip()
  las <- suppressMessages(suppressWarnings(lidR::LAS(data.frame(
    X = p$X, Y = p$Y, Z = p$Z, ReturnNumber = p$ReturnNumber, NumberOfReturns = 2L))))
  expect_equal(cd_counts_las(las, 500, 1000, 10, 25),
               cd_counts(p$X, p$Y, p$Z, p$ReturnNumber, 500, 1000, 10, 25))
})

test_that("agreement with the recorded whole-clip densities uses a relative tolerance", {
  x <- data.frame(clip_frdens = c(1, 2), clip_pdens = c(3, 4))
  expect_length(cd_mismatch(x, c(1, 2) * (1 + 1e-15), c(3, 4), tol = 1e-13, relative = TRUE), 0)
  expect_identical(cd_mismatch(x, c(1, 2.001), c(3, 4), tol = 1e-13, relative = TRUE), 2L)
  expect_identical(cd_mismatch(x, c(1, NA), c(3, 4)), 2L)
})

test_that("summaries count cores and clips below the floors per rung and scope", {
  x <- data.frame(site = c("S", "S", "T", "S", "S", "T"), rung = rep(c("native", "4"), each = 3),
                  core_frdens = c(9, 7, 12, 1.9, 1.5, 2.5), clip_frdens = c(9.5, 8.2, 12, 2.1, 1.8, 2.6),
                  core_pdens = c(18, 14, 20, 4, 4, 4), clip_pdens = c(19, 15, 20, 4.4, 4.5, 4.3),
                  ring_pdens = c(18, 15, 20, 5.5, 5.4, 5.6), stringsAsFactors = FALSE)
  s <- cd_summary(x, list(all = c("S", "T"), S = "S"), c("native", "4"))
  expect_identical(paste(s$rung, s$scope), c("native all", "native S", "4 all", "4 S"))
  a <- s[s$rung == "4" & s$scope == "all", ]
  expect_equal(a$cells, 3); expect_equal(a$core_frdens_median, 1.9); expect_equal(a$clip_frdens_median, 2.1)
  expect_equal(a$cores_below_2, 2); expect_equal(a$clips_below_2, 1)
  expect_equal(a$core_pdens_median, 4); expect_equal(a$ring_pdens_median, 5.5)
  expect_equal(a$core_over_clip_median, median(c(1.9 / 2.1, 1.5 / 1.8, 2.5 / 2.6)))
  n <- s[s$rung == "native" & s$scope == "all", ]
  expect_equal(n$cores_below_8, 1); expect_equal(n$clips_below_8, 0)
  expect_error(cd_summary(x, list(all = "S"), "native"), "not listed")
})

test_that("the sparse-flight comparison counts clouds outside the bracketing rungs both ways", {
  cells <- c("sparse native", "2021 8", "2021 4")
  x <- data.frame(site = rep(c("S", "S", "T"), each = 3), plot = rep(c("a", "b", "c"), each = 3),
                  cell = rep(cells, 3),
                  clip_frdens = c(5.0, 5.5, 2.9, 6.0, 5.6, 2.8, 2.0, 5.3, 2.7),
                  core_frdens = c(5.0, 4.8, 2.5, 6.0, 5.0, 2.4, 2.0, 4.7, 2.3), stringsAsFactors = FALSE)
  s <- cd_sparse_summary(x, list(all = c("S", "T"), S = "S"))
  a <- s[s$scope == "all", ]
  expect_equal(a$plots, 3)
  expect_equal(a$denser_than_8_clip, 1); expect_equal(a$denser_than_8_core, 2)   # plot a only by core
  expect_equal(a$sparser_than_4_clip, 1); expect_equal(a$sparser_than_4_core, 1)
  expect_equal(a$bracketed_clip, 1); expect_equal(a$bracketed_core, 0)
  expect_equal(a$core_sparse_native, 5); expect_equal(a$clip_2021_8, 5.5)
  expect_equal(s$plots[s$scope == "S"], 2)
  expect_error(cd_sparse_summary(x[x$cell != "2021 4", ], list(all = "S")), "needs the cells")
})
