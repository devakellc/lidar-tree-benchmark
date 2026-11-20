source(file.path("..", "..", "scripts", "model_bench_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "ofo_registration_lib.R"), local = TRUE)
suppressMessages(library(lidR))

# A synthetic canopy raster: steep cones (20 m per m) with apexes on 0.5 m cell
# centres, so a 0.5 m miss falls far outside the height tolerance. Diameters
# rise with height. 36 trees on a jittered 12 m grid inside [30, 90] m.
cone_canopy <- function(seed = 1) {
  set.seed(seed)
  r <- terra::rast(xmin = 0, xmax = 120, ymin = 0, ymax = 120, resolution = 0.5,
                   crs = "EPSG:32611")
  g <- expand.grid(x = seq(30, 90, by = 12), y = seq(30, 90, by = 12))
  snap <- function(v) floor(v / 0.5) * 0.5 + 0.25
  x <- snap(g$x + runif(nrow(g), -3, 3)); y <- snap(g$y + runif(nrow(g), -3, 3))
  h <- runif(nrow(g), 12, 40)
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  v <- numeric(nrow(xy))
  for (i in seq_along(x))
    v <- pmax(v, h[i] - 20 * sqrt((xy[, 1] - x[i])^2 + (xy[, 2] - y[i])^2))
  terra::values(r) <- pmax(v, 0)
  list(M = r, x = x, y = y, h = h, d = 2 * h + 5)
}

grid <- ofo_shift_grid()

test_that("the shift grid holds 2,401 shifts over +/-12 m at 0.5 m", {
  expect_equal(nrow(grid), 2401L)
  expect_equal(range(grid$dx), c(-12, 12))
  expect_equal(sort(unique(grid$dy)), seq(-12, 12, by = 0.5))
  expect_equal(anyDuplicated(paste(grid$dx, grid$dy)), 0L)
})

test_that("both signals recover a known shift within one grid step", {
  cc <- cone_canopy()
  off <- c(3.3, -4.8)                       # stems displaced; truth undoes it
  x <- cc$x + off[1]; y <- cc$y + off[2]
  k <- ofo_height_stems(rep(TRUE, length(cc$h)), cc$h)
  expect_gte(sum(k), 15L)
  rh <- ofo_register(ofo_signal_matrix(cc$M, x[k], y[k], grid), cc$h[k], grid,
                     "height", "SYN_1")
  rr <- ofo_register(ofo_signal_matrix(cc$M, x, y, grid), cc$d, grid, "rank", "SYN_1")
  for (r in list(rh, rr)) {
    expect_lte(sqrt((r$dx + off[1])^2 + (r$dy + off[2])^2), 0.5)
    expect_true(r$accepted)
    expect_identical(r$reject_reason, "")
    expect_false(r$on_edge)
    expect_equal(r$residual_m, 0)
  }
  expect_equal(rh$objective_best, 1)
  expect_equal(rr$objective_best, 1)
  expect_equal(rh$contrast, rh$objective_best - rh$objective_median)
  expect_equal(rh$n_signal, sum(k))
  expect_equal(rr$n_signal, length(cc$h))
})

test_that("the rank objective is the Spearman correlation per shift", {
  set.seed(4)
  V <- matrix(sample(0:6, 30 * 7, replace = TRUE), 30, 7)   # many ties
  V[, 7] <- 3                                               # no variance
  d <- sample(c(10, 12, 12, 15, 20, 25), 30, replace = TRUE)
  o <- ofo_objective_rank(V, d)
  ref <- suppressWarnings(apply(V, 2, function(v) cor(d, v, method = "spearman")))
  expect_equal(o[1:6], ref[1:6])
  expect_true(is.na(o[7]))
})

test_that("the height objective counts stems within max(2 m, 15% of height)", {
  h <- c(10, 20, 40)
  V <- cbind(c(12, 20, 46), c(12.01, 22.5, 46.01), c(0, 0, 0))
  expect_equal(ofo_objective_height(V, h), c(1, 1 / 3, 0))
})

test_that("ties go to the shortest shift, then the smallest dx, then dy", {
  obj <- rep(0.5, nrow(grid))
  at <- function(dx, dy) which(grid$dx == dx & grid$dy == dy)
  obj[c(at(3, 4), at(-3, 4), at(0, 5), at(-3, -4), at(2, 1))] <- 0.9
  b <- ofo_best_shift(obj, grid)
  expect_identical(c(b$dx, b$dy), c(2, 1))
  obj[at(2, 1)] <- 0.5
  b <- ofo_best_shift(obj, grid)
  expect_identical(c(b$dx, b$dy), c(-3, -4))
  obj[at(-3, -4)] <- 0.9 - 1e-15                       # rounding-level tie
  expect_identical(unlist(ofo_best_shift(obj, grid)[c("dx", "dy")]), c(dx = -3, dy = -4))
  # NA counts as -Inf; an all-NA objective falls to the zero shift.
  obj2 <- rep(NA_real_, nrow(grid)); obj2[at(5, 5)] <- -0.2
  expect_identical(unlist(ofo_best_shift(obj2, grid)[c("dx", "dy")]), c(dx = 5, dy = 5))
  b0 <- ofo_best_shift(rep(NA_real_, nrow(grid)), grid)
  expect_identical(c(b0$dx, b0$dy), c(0, 0))
  expect_true(is.na(b0$objective))
})

test_that("a flat objective returns the zero shift and is rejected for contrast", {
  flat <- terra::rast(xmin = 0, xmax = 60, ymin = 0, ymax = 60, resolution = 0.5)
  terra::values(flat) <- 0
  set.seed(2)
  x <- runif(20, 20, 40); y <- runif(20, 20, 40); h <- runif(20, 15, 30)
  V <- ofo_signal_matrix(flat, x, y, grid)
  rh <- ofo_register(V, h, grid, "height", "FLAT")
  expect_identical(c(rh$dx, rh$dy), c(0, 0))
  expect_equal(rh$contrast, 0)
  expect_false(rh$accepted)
  expect_identical(rh$reject_reason, "contrast")
  rr <- ofo_register(V, h, grid, "rank", "FLAT")           # no variance: all NA
  expect_identical(c(rr$dx, rr$dy), c(0, 0))
  expect_true(is.na(rr$contrast))
  expect_true(is.na(rr$objective_median))
  expect_identical(rr$reject_reason, "contrast")
})

test_that("an estimate on the window's edge is flagged and rejected", {
  cc <- cone_canopy()
  x <- cc$x - 12; y <- cc$y + 3                          # truth (12, -3)
  k <- ofo_height_stems(rep(TRUE, length(cc$h)), cc$h)
  r <- ofo_register(ofo_signal_matrix(cc$M, x[k], y[k], grid), cc$h[k], grid, "height", "EDGE")
  expect_identical(c(r$dx, r$dy), c(12, -3))
  expect_true(r$on_edge)
  expect_false(r$accepted)
  expect_match(r$reject_reason, "on_edge")
})

test_that("plots with fewer than 15 signal stems are not run", {
  cc <- cone_canopy()
  V <- ofo_signal_matrix(cc$M, cc$x[1:14], cc$y[1:14], grid)
  r <- ofo_register(V, cc$d[1:14], grid, "rank", "FEW")
  expect_false(r$accepted)
  expect_identical(r$reject_reason, "n")
  expect_true(is.na(r$dx) && is.na(r$residual_m))
  expect_identical(r$n_signal, 14L)
})

test_that("half-splits use the declared seeds", {
  expect_identical(ofo_split_seed("0042", 3), seed_for("registration", "0042", NA, 3L))
  expect_false(ofo_split_seed("0042", 3) == ofo_split_seed("0042", 4))
  s <- seed_for("registration", "0042", NA, 7L)
  h <- ofo_half_split(31, s)
  set.seed(s); perm <- sample.int(31)
  expect_identical(h$a, perm[1:15])
  expect_identical(h$b, perm[16:31])
  expect_identical(sort(c(h$a, h$b)), 1:31)
})

test_that("the residual is deterministic for a plot key and changes with the key", {
  set.seed(9)
  noise <- terra::rast(xmin = 0, xmax = 80, ymin = 0, ymax = 80, resolution = 0.5)
  terra::values(noise) <- runif(terra::ncell(noise), 0, 40)
  x <- runif(40, 25, 55); y <- runif(40, 25, 55); h <- runif(40, 10, 35)
  V <- ofo_signal_matrix(noise, x, y, grid)
  d1 <- ofo_split_distances(V, h, grid, "height", "P1")
  expect_length(d1, 20L)
  expect_identical(ofo_split_distances(V, h, grid, "height", "P1"), d1)
  d2 <- ofo_split_distances(V, h, grid, "height", "P2")
  expect_false(identical(d1, d2))
  # The residual is the median over the declared splits, recomputed by hand.
  manual <- vapply(1:20, function(k) {
    set.seed(seed_for("registration", "P1", NA, k)); perm <- sample.int(40)
    a <- ofo_best_shift(ofo_objective_height(V[perm[1:20], ], h[perm[1:20]]), grid)
    b <- ofo_best_shift(ofo_objective_height(V[perm[21:40], ], h[perm[21:40]]), grid)
    sqrt((a$dx - b$dx)^2 + (a$dy - b$dy)^2)
  }, numeric(1))
  expect_identical(d1, manual)
  r1 <- ofo_register(V, h, grid, "height", "P1")
  expect_identical(r1$residual_m, stats::median(d1))
  expect_identical(ofo_register(V, h, grid, "height", "P1"), r1)
  expect_false(identical(r1$residual_m, ofo_register(V, h, grid, "height", "P2")$residual_m))
})

test_that("acceptance lists every failed rule at its boundary", {
  expect_identical(ofo_accept(15, FALSE, 0.10, 2.0), list(accepted = TRUE, reason = ""))
  expect_true(ofo_accept(15, FALSE, 0.6 - 0.5, 2.0)$accepted)   # 0.0999999999999999
  expect_identical(ofo_accept(14, FALSE, 0.5, 1)$reason, "n")
  expect_identical(ofo_accept(20, TRUE, 0.5, 1)$reason, "on_edge")
  expect_identical(ofo_accept(20, FALSE, 0.0999, 1)$reason, "contrast")
  expect_identical(ofo_accept(20, FALSE, NA, 1)$reason, "contrast")
  expect_identical(ofo_accept(20, FALSE, 0.5, 2.01)$reason, "residual")
  expect_identical(ofo_accept(10, TRUE, 0.05, 3)$reason, "n;on_edge;contrast;residual")
})

test_that("positions outside the raster count as 0", {
  M <- terra::rast(xmin = 0, xmax = 10, ymin = 0, ymax = 10, resolution = 0.5)
  terra::values(M) <- 5
  M[terra::cellFromXY(M, cbind(1.2, 1.2))] <- NA          # empty cell
  g <- data.frame(dx = c(0, -2, 0, 9.5, 0, 0), dy = c(0, 0, -2, 0, 8.5, 8.9))
  V <- ofo_signal_matrix(M, c(1, 1.2), c(1, 1.2), g)
  expect_equal(V[1, ], c(5, 0, 0, 0, 5, 5))  # x = -1, y = -1 and x = 10.5 fall outside
  expect_equal(V[2, ], c(0, 0, 0, 0, 5, 0))  # an empty (NA) cell and y = 10.1 give 0
  # Inside the raster the lookup agrees with terra::extract.
  set.seed(3)
  cc <- cone_canopy()
  px <- runif(50, 1, 119); py <- runif(50, 1, 119)
  V0 <- ofo_signal_matrix(cc$M, px, py, data.frame(dx = 0, dy = 0))
  expect_equal(V0[, 1], terra::extract(cc$M, cbind(px, py))[, 1])
})

test_that("the canopy top is the 5 x 5 moving maximum with empty cells 0", {
  r <- terra::rast(xmin = 0, xmax = 10, ymin = 0, ymax = 10, resolution = 0.5)
  terra::values(r) <- NA
  r[terra::cellFromXY(r, cbind(5.25, 5.25))] <- 30
  r[terra::cellFromXY(r, cbind(0.25, 9.75))] <- -1
  M <- ofo_canopy_top(r)
  expect_false(anyNA(terra::values(M)))
  expect_equal(sum(terra::values(M) == 30), 25L)
  expect_equal(terra::extract(M, cbind(c(4.25, 6.25, 3.75), c(4.25, 6.25, 5.25)))[, 1],
               c(30, 30, 0))
  expect_equal(min(terra::values(M)), 0)
  # From an already-normalised cloud: a 0.5 m highest-return raster.
  las <- LAS(data.frame(X = c(5.1, 5.2, 8.3, 2), Y = c(5.1, 5.2, 2.2, 2),
                        Z = c(12, 20, 7, -0.5)))
  Ml <- ofo_canopy_top(las)
  expect_equal(terra::res(Ml), c(0.5, 0.5))
  expect_equal(terra::extract(Ml, cbind(5.2, 5.2))[, 1], 20)
  expect_equal(terra::extract(Ml, cbind(8.3, 2.2))[, 1], 7)
})

test_that("a raw cloud is normalised on its ground, or stops without ground", {
  g <- expand.grid(X = seq(0, 30, by = 2), Y = seq(0, 30, by = 2))
  pts <- rbind(transform(g, Z = 100, Classification = 2L),
               transform(g, Z = 115, Classification = 5L),
               data.frame(X = 15, Y = 15, Z = 300, Classification = 5L))
  las <- LAS(pts)
  n <- ofo_normalize(las)
  expect_equal(range(n$Z), c(0, 15))                       # 200 m noise dropped
  few <- LAS(rbind(head(pts[pts$Classification == 2L, ], 9), pts[pts$Classification == 5L, ]))
  expect_error(ofo_normalize(few), "no_ground")
})

test_that("height-signal stems clear max(10 m, the plot's median live height)", {
  live <- c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE)
  h <- c(5, 8, 12, 20, 30, NA, 50)
  expect_identical(ofo_height_stems(live, h), c(FALSE, FALSE, TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_identical(ofo_height_stems(rep(TRUE, 3), c(4, 6, 8)), rep(FALSE, 3))
  expect_identical(ofo_height_stems(rep(TRUE, 2), c(NA, NA)), rep(FALSE, 2))
})

test_that("catalogue stems treat every stem as live where no status was recorded", {
  tr <- data.frame(x = c(1, 2, 3, 4, NA), y = c(1, 2, 3, 4, 5),
                   height = c(20, 25, NA, 30, 40), dbh = c(9, 12, 20, NA, 30),
                   live = c(FALSE, FALSE, FALSE, FALSE, FALSE),
                   is_tree = c(TRUE, TRUE, FALSE, TRUE, TRUE),
                   inside = c(TRUE, TRUE, TRUE, TRUE, TRUE),
                   ref = c(FALSE, FALSE, FALSE, FALSE, FALSE))
  s <- ofo_catalog_stems(tr, status_recorded = FALSE, live_floor_cm = NA)
  expect_equal(nrow(s), 4L)                                # no position: dropped
  expect_true(all(s$live))
  expect_identical(s$ref, c(FALSE, TRUE, FALSE, FALSE))     # tree, dbh >= 10, inside
  expect_identical(s$rank_stem, s$ref)
  expect_identical(s$height_stem, c(FALSE, TRUE, FALSE, TRUE))
  s15 <- ofo_catalog_stems(tr, status_recorded = FALSE, live_floor_cm = 15)
  expect_identical(s15$ref, c(FALSE, FALSE, FALSE, FALSE))
  tr$live <- c(TRUE, TRUE, TRUE, FALSE, TRUE); tr$ref <- c(FALSE, TRUE, FALSE, FALSE, TRUE)
  k <- ofo_catalog_stems(tr, status_recorded = TRUE, live_floor_cm = 10)
  expect_identical(k$live, c(TRUE, TRUE, TRUE, FALSE))
  expect_identical(k$ref, c(FALSE, TRUE, FALSE, FALSE))
})

test_that("test 1 passes at exactly 20 accepted, 90% within 2 m and median 1.0 m", {
  e <- c(rep(0.5, 9), 1, 1, rep(1.5, 7), 3, 3)
  t <- ofo_known_truth_signal(rep(TRUE, 20), e)
  expect_equal(t$median_error_m, 1)
  expect_equal(t$share_within_2m, 0.9)
  expect_true(t$pass)
  expect_false(ofo_known_truth_signal(rep(TRUE, 19), e[-1])$pass)        # 19 accepted
  e2 <- e; e2[18] <- 2.5                                                  # 85%
  expect_false(ofo_known_truth_signal(rep(TRUE, 20), e2)$pass)
  e3 <- e; e3[10:11] <- 1.0001                                            # median > 1
  expect_false(ofo_known_truth_signal(rep(TRUE, 20), e3)$pass)
  # Rejected plots do not count, whatever their error.
  t4 <- ofo_known_truth_signal(c(rep(TRUE, 20), FALSE), c(e, 0))
  expect_identical(c(t4$n_plots, t4$n_accepted), c(21L, 20L))
  expect_true(t4$pass)
  neon <- data.frame(signal = rep(c("height", "rank"), each = 20), n_signal = 20,
                     accepted = TRUE, error_m = c(e, e2))
  kt <- ofo_known_truth_test(neon)
  expect_true(kt$height$pass)
  expect_false(kt$rank$pass)
})

test_that("test 3 passes at exactly 80% agreement on exactly 10 plots", {
  expect_true(ofo_agreement_test(c(rep(1, 8), 2, 2.5))$pass)
  expect_false(ofo_agreement_test(c(rep(1, 7), 2.1, 3, 4))$pass)         # 70%
  expect_false(ofo_agreement_test(rep(0.5, 9))$pass)                      # 9 plots
  t <- ofo_agreement_test(c(rep(1, 8), 3, 3))
  expect_identical(c(t$n_plots, t$n_within_2m), c(10L, 8L))
  rc <- data.frame(plot_id = rep(c("0001", "0002", "0003"), each = 2),
                   signal = rep(c("height", "rank"), 3),
                   dx = c(1, 2.5, 0, 0, 3, 3), dy = c(1, 1, 0, 0, 0, 0),
                   accepted = c(TRUE, TRUE, TRUE, FALSE, TRUE, TRUE))
  p <- ofo_agreement_pairs(rc, measured = c("0001", "0002"))
  expect_identical(p$plot_id, "0001")
  expect_equal(p$distance_m, 1.5)
})

test_that("the rank signal needs tests 1 and 3; the height signal test 1 only", {
  t1 <- list(height = list(pass = TRUE), rank = list(pass = TRUE))
  expect_identical(ofo_admitted_signals(t1, list(pass = FALSE)),
                   list(height = TRUE, rank = FALSE))
  expect_identical(ofo_admitted_signals(t1, list(pass = TRUE)),
                   list(height = TRUE, rank = TRUE))
  t1$height$pass <- FALSE
  expect_identical(ofo_admitted_signals(t1, list(pass = TRUE)),
                   list(height = FALSE, rank = TRUE))
})

## ==== Amendment 1: split, composites and method 2 ===============================

test_that("three plots or more form groups of three; a remainder joins the last group", {
  expect_identical(ofo_group_threes(0L), integer())
  expect_identical(ofo_group_threes(1L), NA_integer_)      # a lone plot: no composite
  expect_identical(ofo_group_threes(2L), c(1L, 1L))        # two plots: one composite of two
  expect_identical(ofo_group_threes(3L), c(1L, 1L, 1L))
  expect_identical(ofo_group_threes(4L), rep(1L, 4))       # remainder of one joins
  expect_identical(ofo_group_threes(5L), rep(1L, 5))       # remainder of two joins
  expect_identical(ofo_group_threes(6L), rep(1:2, each = 3))
  expect_identical(ofo_group_threes(7L), c(1L, 1L, 1L, 2L, 2L, 2L, 2L))
  expect_identical(ofo_group_threes(8L), c(1L, 1L, 1L, rep(2L, 5)))
  expect_identical(ofo_group_threes(9L), rep(1:3, each = 3))
})

# Synthetic population: two sites, two plot types, IDs that are not real plots.
syn_pop <- function()
  data.frame(site = c(rep("AAAA", 7), rep("BBBB", 4)),
             plot = c(sprintf("AAAA_%03d", 1:7), sprintf("BBBB_%03d", 11:14)),
             plot_type = c(rep("tower", 4), rep("distributed", 3), "tower", rep("distributed", 3)),
             stringsAsFactors = FALSE)

test_that("the split takes odd seed ranks within site x plot type as development plots", {
  pop <- syn_pop()
  sp <- ofo_split_plots(pop)
  expect_setequal(sp$plot, pop$plot)
  for (key in unique(paste(pop$site, pop$plot_type))) {
    x <- pop[paste(pop$site, pop$plot_type) == key, ]
    seeds <- vapply(x$plot, function(p) seed_for("split", p, NA), integer(1))
    ord <- x$plot[order(seeds, x$plot)]
    got <- sp[paste(sp$site, sp$plot_type) == key, ]
    expect_identical(got$plot, ord)
    expect_identical(got$split_rank, seq_along(ord))
    expect_identical(got$set, ifelse(seq_along(ord) %% 2 == 1, "development", "confirmation"))
  }
  # A single tower plot at BBBB is rank 1: development.
  expect_identical(sp$set[sp$plot == "BBBB_011"], "development")
})

test_that("split ties are broken by plot ID", {
  env <- environment(ofo_split_plots)
  real <- get("seed_for", envir = env)
  assign("seed_for", function(...) 7L, envir = env)                # every seed equal
  on.exit(assign("seed_for", real, envir = env), add = TRUE)
  sp <- ofo_split_plots(data.frame(site = "S", plot = c("S_3", "S_1", "S_2", "S_4"),
                                   plot_type = "tower"))
  expect_identical(sp$plot, c("S_1", "S_2", "S_3", "S_4"))
  expect_identical(sp$set, c("development", "confirmation", "development", "confirmation"))
  co <- ofo_composites(sp)
  expect_identical(co$members, c("S_1;S_3", "S_2;S_4"))           # ties by ID again
})

test_that("composites group each half of each site by the composite seed", {
  sp <- ofo_split_plots(syn_pop())
  co <- ofo_composites(sp)
  for (key in unique(paste(sp$set, sp$site))) {
    x <- sp[paste(sp$set, sp$site) == key, ]
    seeds <- vapply(x$plot, function(p) seed_for("composite", p, NA), integer(1))
    ord <- x$plot[order(seeds, x$plot)]
    got <- co[paste(co$set, co$site) == key, ]
    if (length(ord) <= 1) { expect_equal(nrow(got), 0L); next }
    expect_identical(unlist(strsplit(got$members, ";")), ord)       # all, in order, once
    g <- ofo_group_threes(length(ord))
    expect_identical(got$members, unname(vapply(split(ord, g), paste, "", collapse = ";")))
    expect_identical(got$offset_key, vapply(strsplit(got$members, ";"), `[`, "", 1))
    expect_identical(got$unit, paste0("C-", got$offset_key))
  }
  # AAAA: 4 development plots (one composite of 4), 3 confirmation (one of 3).
  # BBBB: its lone tower plot and two distributed plots are development (one
  # composite of 3); its one confirmation plot forms none.
  expect_identical(as.integer(table(co$site)), c(2L, 1L))
  expect_identical(sort(co$n_members), c(3L, 3L, 4L))
  expect_true(all(co$n_members %in% c(2L, 3L, 4L)))
  u <- ofo_units(syn_pop())
  expect_identical(sum(u$kind == "plot"), 11L)
  expect_identical(sum(u$kind == "composite"), nrow(co))
  expect_identical(u$set[u$kind == "plot"], sp$set[match(u$unit[u$kind == "plot"], sp$plot)])
  # A half-site of one plot forms no composite.
  one <- data.frame(site = c("C", "C"), plot = c("C_1", "C_2"), plot_type = "tower")
  expect_equal(nrow(ofo_composites(ofo_split_plots(one))), 0L)
})

test_that("unit offsets use the offset2 seed of the plot or first member", {
  set.seed(seed_for("offset2", "AAAA_001", NA))
  ref <- stats::runif(2, -8, 8)
  expect_identical(ofo_unit_offset("AAAA_001"), ref)
  o <- ofo_unit_offset("AAAA_002")
  expect_true(all(abs(o) <= 8))
  expect_false(identical(o, ofo_unit_offset("AAAA_001")))
})

# A synthetic canopy of paraboloid crowns on a 0.5 m grid; apexes off the cell
# centres. Returns the surface, stems with heights and diameters.
crown_plot <- function(seed = 1, x0 = 0, y0 = 0, n_side = 7, spacing = 8) {
  set.seed(seed)
  r <- terra::rast(xmin = x0, xmax = x0 + 120, ymin = y0, ymax = y0 + 120, resolution = 0.5)
  g <- expand.grid(x = seq(30, 30 + spacing * (n_side - 1), by = spacing),
                   y = seq(30, 30 + spacing * (n_side - 1), by = spacing))
  x <- x0 + g$x + runif(nrow(g), -2.5, 2.5); y <- y0 + g$y + runif(nrow(g), -2.5, 2.5)
  h <- runif(nrow(g), 12, 40)
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  v <- numeric(nrow(xy))
  for (i in seq_along(x)) {
    rad <- 0.5 + 0.1 * h[i]
    v <- pmax(v, h[i] * pmax(0, 1 - ((xy[, 1] - x[i])^2 + (xy[, 2] - y[i])^2) / rad^2))
  }
  terra::values(r) <- v
  list(r = r, stems = data.frame(x = x, y = y, height = h, dbh = 2 * h + 5))
}

plots_of <- function(...) {
  cps <- list(...)
  lapply(cps, function(cp) list(stems = cp$stems,
                                surf = list(raw = ofo2_surface(cp$r, "raw"),
                                            max5 = ofo2_surface(cp$r, "max5"),
                                            gauss1 = ofo2_surface(cp$r, "gauss1"))))
}

test_that("the NCC objective equals a brute-force masked correlation at every lag", {
  cp <- crown_plot(3)
  S <- ofo2_surface(cp$r, "raw")
  cfg <- OFO_REG2_VARIANTS$height$ncc
  st <- cp$stems[1:12, ]
  g <- data.frame(dx = c(0, 1.5, -2, 0.5, -12, 12), dy = c(0, -1, 3.5, 12, -12, 0))
  full <- ofo_shift_grid()
  mem <- list(list(S = S, x = st$x, y = st$y, size = st$height))
  o <- ofo2_prepare(mem, cfg, full)$objective()
  # Brute force: render on the surface grid, sample the moved surface per cell.
  xc <- S$xmin + (seq_len(ncol(S$m)) - 0.5) * S$res
  yc <- S$ymax - (seq_len(nrow(S$m)) - 0.5) * S$res
  X <- matrix(xc, nrow(S$m), ncol(S$m), byrow = TRUE); Y <- matrix(yc, nrow(S$m), ncol(S$m))
  R <- matrix(0, nrow(S$m), ncol(S$m)); M <- matrix(FALSE, nrow(S$m), ncol(S$m))
  for (i in seq_len(nrow(st))) {
    d2 <- (X - st$x[i])^2 + (Y - st$y[i])^2
    rad <- max(1, cfg$r0 + cfg$r1 * st$height[i])
    R <- pmax(R, st$height[i] * pmax(0, 1 - d2 / rad^2))
    M <- M | d2 <= cfg$mask_m^2
  }
  for (k in seq_len(nrow(g))) {
    ci <- which(M, arr.ind = TRUE)
    rr <- ci[, 1] - round(g$dy[k] / 0.5); cc <- ci[, 2] + round(g$dx[k] / 0.5)
    ok <- rr >= 1 & rr <= nrow(S$m) & cc >= 1 & cc <= ncol(S$m)
    cv <- numeric(nrow(ci)); cv[ok] <- S$m[cbind(rr[ok], cc[ok])]
    j <- which(abs(full$dx - g$dx[k]) < 1e-9 & abs(full$dy - g$dy[k]) < 1e-9)
    expect_equal(o[j], stats::cor(R[ci], cv), tolerance = 1e-9)
  }
})

test_that("method 2 recovers a known shift with both signals and pools a composite", {
  a <- crown_plot(1); b <- crown_plot(2, x0 = 500, y0 = 900)
  P <- plots_of(A = a, B = b)
  off <- c(3.3, -4.8)
  for (s in c("height", "rank")) {
    r <- ofo2_run_unit("A", "A", P, s, OFO_REG2[[s]]$cfg, off)
    expect_lt(r$error_m, 0.1)
    expect_false(r$on_edge)
    expect_lt(r$residual_m, 0.5)
    expect_lt(r$sub_p90_m, 0.5)
    expect_identical(r$n_signal, nrow(a$stems))
    cmp <- ofo2_run_unit("C-A", c("A", "B"), P, s, OFO_REG2[[s]]$cfg, off)
    expect_identical(cmp$n_signal, nrow(a$stems) + nrow(b$stems))
    expect_lt(cmp$error_m, 0.1)
  }
  # Pooling: the composite objective is the NCC of the summed statistics.
  cfg <- OFO_REG2$height$cfg
  grid <- ofo_shift_grid()
  ma <- ofo2_unit_members("A", P, "height", "raw", off)
  mb <- ofo2_unit_members("B", P, "height", "raw", off)
  L <- 24L
  sa <- ofo2_ncc_stats(ofo2_ncc_member(ma[[1]]$S, ma[[1]]$x, ma[[1]]$y, ma[[1]]$size, cfg, L),
                       seq_along(ma[[1]]$x))
  sb <- ofo2_ncc_stats(ofo2_ncc_member(mb[[1]]$S, mb[[1]]$x, mb[[1]]$y, mb[[1]]$size, cfg, L),
                       seq_along(mb[[1]]$x))
  pooled <- ofo2_ncc_value(Map(`+`, sa, sb))
  idx <- cbind(as.integer(round(-grid$dy / 0.5)) + L + 1L,
               as.integer(round(grid$dx / 0.5)) + L + 1L)
  expect_equal(ofo2_prepare(c(ma, mb), cfg, grid)$objective(), pooled[idx])
  # A unit under OFO_REG2_MIN_RUN stems is not run.
  P$A$stems <- P$A$stems[1:3, ]
  r3 <- ofo2_run_unit("A", "A", P, "height", cfg, off)
  expect_true(is.na(r3$dx) && is.na(r3$error_m))
  expect_identical(r3$n_signal, 3L)
})

test_that("method 2 is translation-equivariant on the search grid", {
  a <- crown_plot(5); b <- crown_plot(6, x0 = 300, y0 = 300)
  P <- plots_of(A = a, B = b)
  base <- c(-2.7, 4.1)
  # Every peak-estimator variant (the centroid's window-median threshold is not
  # equivariant and is never selected).
  cfgs <- c(list(OFO_REG2$height$cfg, OFO_REG2$rank$cfg),
            OFO_REG2_VARIANTS$height[c("kern_raw", "corr_gauss1", "share_max5_peak",
                                       "ncc_unit")])
  sig <- c("height", "rank", "height", "height", "height", "height")
  for (k in seq_along(cfgs)) for (d in list(c(1.5, -2), c(-3, 0.5), c(0, 4))) {
    for (m in list("A", c("A", "B"))) {
      r1 <- ofo2_run_unit("U", m, P, sig[k], cfgs[[k]], base)
      r2 <- ofo2_run_unit("U", m, P, sig[k], cfgs[[k]], base + d)
      expect_false(r1$on_edge || r2$on_edge)
      expect_equal(c(r2$dx, r2$dy), c(r1$dx, r1$dy) - d, tolerance = 1e-9)
      expect_equal(r2$residual_m, r1$residual_m, tolerance = 1e-9)
      expect_equal(r2$sub_p90_m, r1$sub_p90_m, tolerance = 1e-9)
      expect_equal(r2$error_m, r1$error_m, tolerance = 1e-9)
    }
  }
  # Exact ties take the centre of the tied shifts, which moves with them.
  grid <- ofo_shift_grid()
  at <- function(dx, dy) which(grid$dx == dx & grid$dy == dy)
  o <- rep(0, nrow(grid)); o[c(at(1, 1), at(2, 1), at(3, 2))] <- 1
  e <- ofo2_estimate(o, grid)
  expect_equal(c(e$dx, e$dy), c(2, 4 / 3))
  o2 <- rep(0, nrow(grid)); o2[c(at(-2, 0), at(-1, 0), at(0, 1))] <- 1
  e2 <- ofo2_estimate(o2, grid)
  expect_equal(c(e2$dx, e2$dy), c(e$dx, e$dy) - c(3, 1))
})

test_that("the peak estimate is refined between grid steps and flags the edge", {
  grid <- ofo_shift_grid()
  o <- -((grid$dx - 1.2)^2 + (grid$dy + 3.7)^2)              # a paraboloid: exact vertex
  e <- ofo2_estimate(o, grid)
  expect_equal(c(e$dx, e$dy), c(1.2, -3.7), tolerance = 1e-9)
  expect_false(e$on_edge)
  oe <- -((grid$dx - 14)^2 + grid$dy^2)                       # maximum beyond the window
  ee <- ofo2_estimate(oe, grid)
  expect_true(ee$on_edge)
  expect_equal(ee$dx, 12)                                     # no refinement past the edge
  c1 <- ofo2_estimate(o, grid, "centroid")
  expect_equal(c(c1$dx, c1$dy), c(1, -3.5), tolerance = 0.3)
  expect_true(is.na(ofo2_estimate(rep(NA_real_, nrow(grid)), grid)$dx))
})

test_that("the method-2 surface fills empty cells and smooths as asked", {
  r <- terra::rast(xmin = 0, xmax = 10, ymin = 0, ymax = 10, resolution = 0.5)
  terra::values(r) <- 10
  r[terra::cellFromXY(r, cbind(5.25, 5.25))] <- NA            # a hole inside a crown
  r[terra::cellFromXY(r, cbind(1.25, 1.25))] <- -0.4          # below ground: 0
  s <- ofo2_surface(r)
  v <- function(S, x, y) S$m[floor((S$ymax - y) / S$res) + 1, floor((x - S$xmin) / S$res) + 1]
  expect_equal(v(s, 5.25, 5.25), 10)
  expect_equal(v(s, 1.25, 1.25), 0)
  expect_false(anyNA(s$m))
  expect_equal(v(ofo2_surface(r, "max3"), 1.25, 1.25), 10)
  g <- ofo2_surface(r, "gauss1")
  expect_true(v(g, 1.25, 1.25) > 0 && v(g, 1.25, 1.25) < 10)
  expect_equal(v(g, 8.25, 8.25), 10, tolerance = 1e-9)        # normalised: flat stays flat
  expect_error(ofo2_surface(r, "median3"), "Unknown surface")
})

test_that("method-2 gates and the confirmation rule hold at their boundaries", {
  g <- list(stat = "sub_p90_m", threshold = 2, min_stems = 20L)
  expect_identical(ofo2_accept(20, FALSE, 2, g), list(accepted = TRUE, reason = ""))
  expect_identical(ofo2_accept(19, FALSE, 1, g)$reason, "n")
  expect_identical(ofo2_accept(25, TRUE, 1, g)$reason, "on_edge")
  expect_identical(ofo2_accept(25, NA, 1, g)$reason, "on_edge")
  expect_identical(ofo2_accept(25, FALSE, 2.01, g)$reason, "sub_p90_m")
  expect_identical(ofo2_accept(25, FALSE, NA, g)$reason, "sub_p90_m")
  gz <- list(stat = "z", threshold = 3.5, min_stems = 10L)
  expect_true(ofo2_accept(10, FALSE, 3.5, gz)$accepted)
  expect_identical(ofo2_accept(5, TRUE, 3.4, gz)$reason, "n;on_edge;z")
  e <- c(rep(0.5, 4), 1, 1, rep(1.5, 3), 3)                   # 10 accepted, median 1.0, 90%
  t <- ofo2_confirmation_test(rep(30, 10), rep(TRUE, 10), e, 20)
  expect_true(t$pass)
  expect_identical(c(t$n_accepted, t$n_within_2m), c(10L, 9L))
  expect_false(ofo2_confirmation_test(rep(30, 9), rep(TRUE, 9), e[-1], 20)$pass)  # 9 accepted
  e2 <- e; e2[5:6] <- 1.01
  expect_false(ofo2_confirmation_test(rep(30, 10), rep(TRUE, 10), e2, 20)$pass)  # median
  e3 <- e; e3[9] <- 2.5
  expect_false(ofo2_confirmation_test(rep(30, 10), rep(TRUE, 10), e3, 20)$pass)  # 80%
  # Units under the smallest stem count do not count, accepted or not.
  t2 <- ofo2_confirmation_test(c(rep(30, 10), 5, 5), c(rep(TRUE, 10), TRUE, FALSE),
                               c(e, 9, 9), 20)
  expect_true(t2$pass)
  expect_identical(c(t2$n_units, t2$n_at_min_stems), c(12L, 10L))
})

test_that("the confirmation refuses without CONFIRM=YES, after a run, or before the freeze", {
  d <- ofo2_config_digest()
  ok_txt <- c("## Amendment 1b: frozen registration", paste("Digest", d))
  expect_true(ofo2_confirm_guard("YES", FALSE, TRUE, ok_txt))
  expect_error(ofo2_confirm_guard(NULL, FALSE, TRUE, ok_txt), "CONFIRM=YES")
  expect_error(ofo2_confirm_guard("yes", FALSE, TRUE, ok_txt), "CONFIRM=YES")
  expect_error(ofo2_confirm_guard("YES", TRUE, TRUE, ok_txt), "never re-run")
  expect_error(ofo2_confirm_guard("YES", FALSE, FALSE, ok_txt), "not frozen")
  expect_error(ofo2_confirm_guard("YES", FALSE, TRUE, "## Amendment 1b"), "digest")
  expect_error(ofo2_confirm_guard("YES", FALSE, TRUE, paste("Digest", d)), "Amendment 1b")
  # The digest moves with any frozen constant.
  x <- OFO_REG2; x$height$gate$threshold <- 2.5
  expect_false(identical(ofo2_config_digest(x), d))
  expect_match(d, "^[0-9a-f]{64}$")
})

test_that("the frozen configuration is a development variant and selectable", {
  for (s in c("height", "rank")) {
    expect_identical(OFO_REG2[[s]]$cfg, OFO_REG2_VARIANTS[[s]][[OFO_REG2[[s]]$variant]])
    expect_true(OFO_REG2[[s]]$gate$stat %in% OFO_REG2_SELECTABLE_STATS)
  }
  expect_true(ofo2_frozen())
})

# A synthetic development table: errors that the gate statistic predicts.
dev_table <- function(seed = 1, n = 60) {
  set.seed(seed)
  good <- runif(n) < 0.8
  data.frame(variant = "v1", signal = "height", unit = sprintf("U%02d", seq_len(n)),
             kind = rep(c("plot", "composite"), length.out = n),
             n_signal = sample(8:120, n, replace = TRUE), dx = 0,
             error_m = ifelse(good, runif(n, 0.1, 1.2), runif(n, 2.5, 12)),
             residual_m = ifelse(good, runif(n, 0, 1.4), runif(n, 1, 9)),
             sub_p90_m = ifelse(good, runif(n, 0, 0.9), runif(n, 0.6, 9)),
             second_peak = runif(n), z = runif(n, 2, 6), on_edge = FALSE,
             accepted = FALSE, stringsAsFactors = FALSE)
}

test_that("the gate sweep counts accepted units and applies the selection rule", {
  x <- dev_table()
  sw <- ofo2_gate_sweep(x, boot = FALSE)
  n_stats <- sum(lengths(OFO_REG2_GATE_GRID[names(OFO_REG2_GATE_STATS)]))
  expect_equal(nrow(sw), n_stats * length(OFO_REG2_GATE_GRID$min_stems))
  row <- sw[sw$gate_stat == "residual_m" & sw$threshold == 1.5 & sw$min_stems == 20, ]
  y <- x[x$n_signal >= 20, ]
  a <- y$residual_m <= 1.5
  expect_identical(c(row$units_run, row$accepted), c(nrow(y), sum(a)))
  expect_equal(row$median_error_accepted_m, stats::median(y$error_m[a]))
  expect_equal(row$share_within_2m, mean(y$error_m[a] <= 2))
  expect_equal(nrow(ofo2_select(sw)), 0L)                    # no estimator column: none
  x$estimator <- "peak"
  sw <- ofo2_gate_sweep(x, boot = FALSE)
  sel <- ofo2_select(sw)
  expect_true(all(sel$gate_stat %in% OFO_REG2_SELECTABLE_STATS))
  expect_true(all(sel$accepted >= 10))
  if (any(sel$basis == "margins")) {
    m <- sw[sw$meets_dev_margins & sw$gate_stat %in% OFO_REG2_SELECTABLE_STATS &
              sw$accepted >= 10, ]
    expect_equal(sel$accepted[1], max(m$accepted))
  }
  # No configuration meets the margins: fall back to the bootstrap chance.
  xc <- x; xc$estimator <- "centroid"
  expect_equal(nrow(ofo2_select(ofo2_gate_sweep(xc, boot = FALSE))), 0L)
  x2 <- x; x2$error_m <- x2$error_m + 0.5
  sw2 <- ofo2_gate_sweep(x2, boot = FALSE)
  sw2$meets_dev_margins <- FALSE
  sw2$p_pass_bootstrap <- seq_len(nrow(sw2)) / nrow(sw2)
  sel2 <- ofo2_select(sw2)
  if (nrow(sel2)) {
    expect_true(all(sel2$basis == "confirmation_bootstrap"))
    expect_true(all(sel2$meets_confirm_limits))
    expect_identical(sel2$p_pass_bootstrap, sort(sel2$p_pass_bootstrap, decreasing = TRUE))
  }
  # The bootstrap chance is a seeded probability.
  p <- ofo2_pass_bootstrap(x$residual_m <= 1.5, x$error_m, "k", B = 200L)
  expect_identical(p, ofo2_pass_bootstrap(x$residual_m <= 1.5, x$error_m, "k", B = 200L))
  expect_true(p >= 0 && p <= 1)
  expect_identical(ofo2_pass_bootstrap(rep(FALSE, 20), x$error_m[1:20], "k", B = 50L), 0)
})

test_that("the development summary pools by band and kind", {
  x <- dev_table(2)
  x$accepted <- x$sub_p90_m <= 1
  sm <- ofo2_dev_summary(x)
  all <- sm[sm$kind == "all" & sm$band == "all", ]
  expect_identical(all$units_run, nrow(x))
  expect_identical(all$accepted, sum(x$accepted))
  expect_equal(all$median_error_accepted_m, stats::median(x$error_m[x$accepted]))
  expect_equal(all$median_error_all_m, stats::median(x$error_m))
  bands <- sm[sm$kind == "all" & sm$band != "all", ]
  expect_identical(sum(bands$units_run), nrow(x))
  expect_identical(sum(sm$units_run[sm$kind == "plot" & sm$band == "all"]),
                   sum(x$kind == "plot"))
})

## ---- the driver's Amendment-1 stages on a synthetic job directory -------------------
driver <- normalizePath(file.path("..", "..", "scripts", "preflight_ofo_registration.R"))
run_driver <- function(job, ...) {
  out <- suppressWarnings(system2("Rscript", c(driver, ...), stdout = TRUE, stderr = TRUE,
                                  env = paste0("CLAUDE_JOB_DIR=", job)))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = out)
}

# A synthetic catalogue of three plots with clouds whose stems are displaced
# by `off` from their crowns: 0001 (group C, heights), 0002 (group B, no
# heights), 0003 (screened out: held out).
write_catalog_fixture <- function(job, off = c(2.5, -1.5)) {
  pre <- file.path(job, "ofo", "preflight"); dir.create(pre, recursive = TRUE)
  dir.create(file.path(job, "ofo", "clouds"))
  ids <- c("0001", "0002", "0003")
  trees <- list()
  for (k in seq_along(ids)) {
    cp <- crown_plot(10 + k, x0 = 1000 * k, y0 = 5000)
    set.seed(20 + k)
    e <- terra::ext(cp$r)
    n <- 60000
    px <- runif(n, e[1], e[2]); py <- runif(n, e[3], e[4])
    z <- terra::extract(cp$r, cbind(px, py))[, 1]
    ground <- 100 + 0.02 * (px - e[1])
    g <- expand.grid(X = seq(e[1], e[2], by = 2), Y = seq(e[3], e[4], by = 2))
    pts <- rbind(data.frame(X = px, Y = py, Z = ground + z,
                            Classification = ifelse(z > 0.5, 5L, 2L)),
                 data.frame(X = g$X, Y = g$Y, Z = 100 + 0.02 * (g$X - e[1]),
                            Classification = 2L))
    las <- suppressMessages(lidR::LAS(pts))
    lidR::writeLAS(las, file.path(job, "ofo", "clouds", paste0(ids[k], ".las")))
    st <- cp$stems
    trees[[k]] <- data.frame(plot_id = ids[k], tree_n = seq_len(nrow(st)), x = st$x + off[1],
                             y = st$y + off[2], height = st$height, dbh = st$dbh, live = TRUE,
                             is_tree = TRUE, inside = TRUE, ref = TRUE)
  }
  # A live shrub with a height: never a height-signal stem under method 2.
  trees[[1]] <- rbind(trees[[1]], data.frame(plot_id = "0001", tree_n = 50L, x = 1060,
                                             y = 5060, height = 3, dbh = NA, live = TRUE,
                                             is_tree = FALSE, inside = TRUE, ref = FALSE))
  data.table::fwrite(data.frame(plot_id = ids, project_name = "PRJ",
                                screen = c("none", "none", "not_exhaustive"),
                                group = c("C", "B", ""), heights_measured = c(TRUE, FALSE, TRUE),
                                status_recorded = TRUE, live_floor_cm = 10),
                     file.path(pre, "plots.csv"))
  data.table::fwrite(do.call(rbind, trees), file.path(pre, "trees.csv"))
  data.table::fwrite(data.frame(plot_id = ids, project_name = "PRJ", cloud_status = "ok",
                                flight_admitted = c(TRUE, TRUE, FALSE), ql = "QL 1",
                                flight_year = 2020, gap_years = 1),
                     file.path(pre, "flights.csv"))
  data.table::fwrite(data.frame(plot_id = ids, path = file.path("clouds", paste0(ids, ".las"))),
                     file.path(pre, "clouds.csv"))
  # What STAGE=neon would have left: a small test-1 table and its JSON block.
  neon <- data.frame(site = "SYN", plot = rep(c("SYN_1", "SYN_2"), each = 2),
                     signal = rep(c("height", "rank"), 2), n_signal = 20L,
                     accepted = c(TRUE, FALSE, TRUE, TRUE),
                     reject_reason = c("", "residual", "", ""),
                     error_m = c(0.5, 3, 1.5, 0.7))
  data.table::fwrite(neon, file.path(pre, "registration_neon.csv"))
  jsonlite::write_json(list(protocol = "synthetic", status = "test 1 only",
                            frozen_root_clip_manifest_sha256 = "abc",
                            test1_known_truth = list(population = "adopted", n_plots = 2,
                                                     offset = "o", error = "e",
                                                     by_accepted = list(), by_stem_count = list(),
                                                     reasons = list())),
                       file.path(pre, "registration_tests.json"), auto_unbox = TRUE)
  pre
}

test_that("STAGE=confirm refuses before touching any data", {
  skip_if(Sys.which("Rscript") == "")
  job <- tempfile("ofo_confirm_"); pre <- file.path(job, "ofo", "preflight")
  dir.create(pre, recursive = TRUE)
  r <- run_driver(job, "STAGE=confirm")
  expect_false(r$status == 0L)
  expect_true(any(grepl("CONFIRM=YES", r$out)))
  file.create(file.path(pre, "registration_confirm.csv"))
  r2 <- run_driver(job, "STAGE=confirm", "CONFIRM=YES")
  expect_false(r2$status == 0L)
  expect_true(any(grepl("never re-run", r2$out)))
  unlink(file.path(pre, "registration_confirm.csv"))
  r3 <- run_driver(job, "STAGE=confirm", "CONFIRM=YES")     # no Amendment 1b or no root
  expect_false(r3$status == 0L)
  expect_false(file.exists(file.path(pre, "registration_confirm.csv")))
  expect_identical(list.files(pre), character())
  unlink(job, recursive = TRUE)
})

test_that("STAGE=catalog keeps the declared results and adds method 2 after the amendment", {
  skip_if(Sys.which("Rscript") == "")
  job <- tempfile("ofo_catalog_")
  off <- c(2.5, -1.5)
  pre <- write_catalog_fixture(job, off)
  r <- run_driver(job, "STAGE=catalog", "CORES=1")
  expect_identical(r$status, 0L)
  rd <- function(f) data.table::fread(file.path(pre, f), colClasses = list(character = "plot_id"),
                                      na.strings = "")
  cat_decl <- rd("registration_catalog.csv"); reg_decl <- rd("registration.csv")
  json_decl <- jsonlite::read_json(file.path(pre, "registration_tests.json"))
  expect_false("method" %in% names(cat_decl))                  # behaves as before
  expect_identical(json_decl$status, "complete")
  # The confirmation's amendment block (as STAGE=confirm writes it), both
  # signals passing their confirmation.
  jsonlite::write_json(list(status = "amendment 1: confirmation run", declared = json_decl,
                            amendment1 = list(confirmation = list(height = list(pass = TRUE),
                                                                  rank = list(pass = TRUE)),
                                              admitted_confirmation = list(height = TRUE,
                                                                           rank = TRUE)),
                            admitted = list(height = TRUE, rank = FALSE)),
                       file.path(pre, "registration_tests.json"), auto_unbox = TRUE,
                       digits = NA, null = "null", na = "null")
  json_decl <- jsonlite::read_json(file.path(pre, "registration_tests.json"))$declared
  for (pass in 1:2) {                                          # a re-run changes nothing
    r2 <- run_driver(job, "STAGE=catalog", "CORES=1")
    expect_identical(r2$status, 0L)
    rc <- as.data.frame(rd("registration_catalog.csv"))
    contract <- c("plot_id", "project_name", "set", "signal", "n_signal", "dx", "dy", "shift_m",
                  "objective_zero", "objective_best", "objective_median", "contrast",
                  "residual_m", "on_edge", "accepted", "reject_reason")
    expect_identical(names(rc)[1:17], c(contract, "method"))
    dec <- rc[rc$method == "declared", names(cat_decl)]
    expect_equal(dec, as.data.frame(cat_decl), ignore_attr = TRUE)
    m2 <- rc[rc$method == "amendment1", ]
    expect_identical(paste(m2$plot_id, m2$signal),
                     c("0001 height", "0001 rank", "0002 rank", "0003 height", "0003 rank"))
    expect_identical(m2$n_signal, rep(49L, 5))
    expect_true(all(abs(m2$dx + off[1]) < 0.3 & abs(m2$dy + off[2]) < 0.3))
    expect_true(all(m2$accepted))
    expect_identical(m2$set, c("candidate", "candidate", "candidate", "heldout", "heldout"))
    reg <- as.data.frame(rd("registration.csv"))
    expect_identical(names(reg)[ncol(reg)], "method")
    expect_true(all(reg$method == "amendment1"))
    # Test 3 cannot pass on three plots, so the rank signal is not admitted.
    expect_identical(reg$registered, c(TRUE, FALSE))
    expect_match(reg$reason[2], "signal_not_admitted")
    expect_equal(reg$pos_unc[1], max(0.5, m2$residual_m[1]))
    js <- jsonlite::read_json(file.path(pre, "registration_tests.json"))
    expect_identical(js$admitted, list(height = TRUE, rank = FALSE))
    expect_identical(js$declared, json_decl)
    expect_false(js$amendment1$catalog$test3_agreement$pass)
    expect_identical(js$amendment1$admitted_confirmation, list(height = TRUE, rank = TRUE))
    expect_equal(as.data.frame(rd("registration_declared.csv")), as.data.frame(reg_decl),
                 ignore_attr = TRUE)
  }
  unlink(job, recursive = TRUE)
})
