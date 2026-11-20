# Unit tests for chance_simulation_lib.R: the synthetic plots, detectors,
# references and truth counts of the chance-correction simulation
# (simulate_chance_correction.R), its stand structures, incomplete
# references, split-crown detector and paired leads, and the neighbour
# statistics of reference_stem_clustering.R. All synthetic; no NEON data.
source(file.path("..", "..", "scripts", "sweep_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "master_tables_lib.R"), local = TRUE)
source(file.path("..", "..", "scripts", "chance_simulation_lib.R"), local = TRUE)

test_that("the pattern holds the declared density and the minimum spacing", {
  n <- vapply(1:200, function(k) cs_with_seed(k, nrow(cs_pattern(240))), 1)
  expected <- 240 / 1e4 * (2 * CS_SIM_HALF)^2          # 86.4 trees
  expect_lt(abs(mean(n) - expected), 4 * sqrt(expected / 200))
  for (D in c(60, 300)) {
    p <- cs_with_seed(7, cs_pattern(D))
    dd <- as.matrix(dist(p[c("x", "y")]))
    diag(dd) <- Inf
    expect_gte(min(dd), CS_R_MIN)
    expect_true(all(abs(c(p$x, p$y)) <= CS_SIM_HALF))
  }
  expect_error(cs_with_seed(1, cs_pattern(20000, half = 10, max_tries = 50L)), "Inhibition")
})

test_that("a seed reproduces a plot and leaves the caller's RNG untouched", {
  set.seed(99); before <- .Random.seed
  a <- cs_plot(240, 123); b <- cs_plot(240, 123)
  expect_identical(.Random.seed, before)
  expect_identical(a, b)
  expect_false(identical(a$trees, cs_plot(240, 124)$trees))
  expect_true(all(a$trees$h >= CS_H_RANGE[1] & a$trees$h <= CS_H_RANGE[2]))
  # The commission pool's first rows do not depend on its size.
  expect_identical(cs_plot(240, 123, f_max = 1)$pool,
                   a$pool[seq_len(nrow(cs_plot(240, 123, f_max = 1)$pool)), ])
})

test_that("the detector nests by skill and commission and takes its offsets", {
  pl <- cs_plot(240, 5)
  n <- nrow(pl$trees)
  d1 <- cs_detector(pl, 0.4, 0.3); d2 <- cs_detector(pl, 0.6, 1.0)
  expect_equal(sum(d1$tree > 0), sum(pl$u < 0.4))
  expect_equal(sum(d1$tree == 0), round(0.3 * n))
  expect_true(all(d1$tree[d1$tree > 0] %in% d2$tree[d2$tree > 0]))
  i <- d1$tree[d1$tree > 0][1]
  expect_equal(d1$x[d1$tree == i], pl$trees$x[i] + CS_SIGMA * pl$zx[i])
  expect_equal(d1$z[d1$tree == i], pl$trees$h[i] + CS_SIGMA_Z * pl$zz[i])
  expect_equal(nrow(cs_detector(pl, 0, 1)), round(n))
  expect_error(cs_detector(pl, 0.5, CS_F_MAX + 1), "pool")
})

test_that("the half reference keeps only the two sampled quadrants of the core", {
  for (seed in 1:20) {
    pl <- cs_plot(240, seed)
    full <- cs_reference(pl, "complete")
    half <- cs_reference(pl, "half")
    expect_true(all(abs(c(full$E, full$N)) <= CS_PH))
    expect_length(pl$quadrants, 2)
    q <- cs_quadrant(half$E, half$N)
    expect_true(all(q %in% pl$quadrants))
    expect_setequal(half$tree, full$tree[cs_quadrant(full$E, full$N) %in% pl$quadrants])
  }
  expect_equal(cs_quadrant(c(-1, 1, -1, 1), c(-1, -1, 1, 1)), 1:4)
})

test_that("the skilled share counts a stem's own detection within r only", {
  st <- data.frame(E = c(0, 10, -10, 19), N = c(0, 0, 0, 19), height = 15,
                   crown_class = "codominant", tree = 1:4)
  det <- data.frame(x = c(1.5, 13, 5, 21, -10), y = c(0, 0, 5, 19, 0),
                    z = 15, tree = c(1L, 2L, 3L, 4L, 0L))
  # Tree 1 at 1.5 m, tree 2 at 3 m, tree 3 at 15.8 m (a commission point sits
  # on it but is not its own), tree 4 at 2 m with its detection outside the core.
  expect_equal(cs_true_skilled(st, det, 4), c(ref = 3, det = 2))
  expect_equal(cs_true_skilled(st, det, 2), c(ref = 2, det = 1))
  expect_equal(cs_true_skilled(st, det[det$tree == 0, ], 4), c(ref = 0, det = 0))
  # At 4 m only tree 3 is missed, and the commission point 0 m from it
  # matches it; at 2 m tree 2 is missed too and its own detection (3 m away)
  # is out of reach.
  expect_equal(cs_missed_matches(st, det, 4), c(n = 1, tp = 1, tp_all = 4))
  expect_equal(cs_missed_matches(st, det, 2), c(n = 2, tp = 1, tp_all = 3))
})

test_that("one plot is scored with the paper's matcher, offsets and shifts", {
  pl <- cs_plot(240, 11)
  dets <- data.frame(detector = c("x", "zero"), s = c(0.6, 0), f = c(0.5, 1))
  seeds <- function(k) 1000L + k
  r <- cs_score_plot(pl, dets, c("complete", "half"), c(4, 2), K = 3, null_seed = seeds)
  expect_equal(nrow(r), 2 * 2 * 2 * 3)
  st <- cs_reference(pl, "complete"); det <- cs_detector(pl, 0.6, 0.5)
  sc <- score_plot(st, det, tol_xy = 2, core_cx = 0, core_cy = 0, core_half = 20)
  o <- r[r$ref == "complete" & r$tol == 2 & r$detector == "x", ]
  expect_equal(o$TP[o$variant == "observed"], sc$TP)
  expect_equal(o$tp_core[o$variant == "observed"], round(sc$precision * sc$n_det))
  nul <- vapply(1:3, function(k) score_plot(
    st, shift_detections(det, 0, 0, 22, null_offset(44, 1000L + k, 8)), tol_xy = 2,
    core_cx = 0, core_cy = 0, core_half = 20)$TP, 1)
  expect_equal(o$TP[o$variant == "null"], mean(nul))
  expect_equal(o$TP[o$variant == "truth"], cs_true_skilled(st, det, 2)[["ref"]])
  mm <- cs_missed_matches(st, det, 2)
  expect_equal(o$n_missed[o$variant == "observed"], mm[["n"]])
  expect_equal(o$tp_missed[o$variant == "observed"], mm[["tp"]])
  expect_true(all(is.na(o$tp_missed[o$variant != "observed"])))
  expect_equal(cs_corrected(0.6, 0.2), 0.5)
})

## ---- structure scenario ----------------------------------------------------------
# P(distance <= t) for two independent uniform points in a disc of radius R.
disc_cdf <- function(t, R) {
  s <- t / R
  1 + 2 / pi * (s^2 - 1) * acos(s / 2) - s / pi * (1 + s^2 / 2) * sqrt(1 - s^2 / 4)
}

test_that("the clustered patterns hold the declared density and cluster as declared", {
  for (pt in c("clustered_4m", "clustered_8m")) {
    cfg <- CS_PATTERNS[[pt]]
    n <- vapply(1:300, function(k) cs_with_seed(k, nrow(cs_pattern_matern(240, cfg$R, cfg$mu))), 1)
    expected <- 240 / 1e4 * (2 * CS_SIM_HALF)^2
    expect_lt(abs(mean(n) - expected), 4 * sd(n) / sqrt(length(n)))
    p <- cs_with_seed(3, cs_pattern_matern(240, cfg$R, cfg$mu))
    expect_true(all(abs(c(p$x, p$y)) <= CS_SIM_HALF))
    expect_equal(p$id, seq_len(nrow(p)))
    # Mean other trees within d of a tree: lambda pi d^2 + mu P(D <= d).
    nb <- rowSums(vapply(1:150, function(i) cs_neighbours(cs_plot(240, i, pattern = pt)),
                         numeric(3)))
    for (d in c(2, 4)) {
      theory <- 240 / 1e4 * pi * d^2 + cfg$mu * disc_cdf(d, cfg$R)
      expect_lt(abs(nb[[paste0("nb", d)]] / nb[["n_ref"]] - theory), 0.1 * theory)
    }
  }
  # The inhibited pattern holds fewer neighbours than a random one, none within 1.5 m.
  nb <- rowSums(vapply(1:60, function(i) cs_neighbours(cs_plot(240, i)), numeric(3)))
  expect_lt(nb[["nb4"]] / nb[["n_ref"]], 240 / 1e4 * pi * 16)
  pl <- cs_plot(240, 9)
  expect_equal(cs_neighbours(pl, d = 1.4)[["nb1.4"]], 0)
  expect_error(cs_plot(240, 1, pattern = "poisson"), "Unknown pattern")
  expect_error(cs_neighbours(pl, d = 11), "beyond")
  expect_identical(cs_plot(240, 77), cs_plot(240, 77, pattern = "inhibited"))
})

test_that("the edge-free neighbour count counts other mapped trees around core stems", {
  pl <- list(trees = data.frame(id = 1:5, x = c(0, 1, 3, 25, 22), y = c(0, 0, 0, 0, 0)),
             v = c(0.1, 0.9, 0.2, 0.3, 0.1))
  # Core stems (|x|, |y| <= 20): trees 1-3. All mapped: tree 1 has 1 within
  # 2 m and 2 within 4 m; tree 2 has 2 and 2; tree 3 has 1 and 2 (tree 4 at
  # 22 m lies outside the core but counts as a neighbour of no core stem;
  # tree 5 at 19 m from tree 3 is too far).
  expect_equal(cs_neighbours(pl), c(n_ref = 3, nb2 = 4, nb4 = 6))
  # At p = 0.5 tree 2 is not mapped: stems 1 and 3, 3 m apart.
  expect_equal(cs_neighbours(pl, p = 0.5), c(n_ref = 2, nb2 = 0, nb4 = 2))
})

test_that("an incomplete reference keeps a nested share p of the trees, all detectable", {
  share <- c(0, 0)
  for (seed in 1:30) {
    pl <- cs_plot(240, seed, pattern = "clustered_4m")
    full <- cs_reference(pl, "complete")
    r8 <- cs_reference(pl, "complete", p = 0.8)
    r6 <- cs_reference(pl, "complete", p = 0.6)
    expect_true(all(r6$tree %in% r8$tree) && all(r8$tree %in% full$tree))
    expect_true(all(pl$v[r6$tree] < 0.6))
    expect_setequal(r6$tree, full$tree[pl$v[full$tree] < 0.6])
    h6 <- cs_reference(pl, "half", p = 0.6)
    expect_setequal(h6$tree, intersect(r6$tree, cs_reference(pl, "half")$tree))
    share <- share + c(nrow(r6), nrow(full))
    # The ordinary detector acts on every tree, mapped or not.
    det <- cs_detector(pl, 1, 0)
    expect_setequal(det$tree, pl$trees$id)
  }
  expect_lt(abs(share[1] / share[2] - 0.6), 0.05)
  pl <- cs_plot(240, 4)
  expect_identical(cs_reference(pl, "complete", p = 1), cs_reference(pl, "complete"))
  expect_error(cs_reference(pl, "complete", p = 0), "p must")
  expect_error(cs_reference(pl, "complete", p = 1.2), "p must")
})

test_that("the detectors without skill on the reference have no own detection within r", {
  pl <- cs_plot(240, 21, pattern = "clustered_8m")
  n <- nrow(pl$trees)
  un <- cs_detector(pl, 0.8, 0.3, mode = "unmapped", p = 0.6)
  dp <- cs_detector(pl, 0.8, 0.3, mode = "displaced")
  al <- cs_detector(pl, 0.8, 0.3)
  expect_setequal(un$tree[un$tree > 0], which(pl$u < 0.8 & pl$v >= 0.6))
  expect_identical(as.list(un[un$tree == 0, ]), as.list(al[al$tree == 0, ]))
  expect_equal(sum(cs_detector(pl, 0.8, 0.3, mode = "unmapped", p = 1)$tree > 0), 0)
  src <- dp$tree[dp$tree > 0]
  d <- sqrt((dp$x[dp$tree > 0] - pl$trees$x[src])^2 + (dp$y[dp$tree > 0] - pl$trees$y[src])^2)
  expect_true(all(d >= CS_RING[1] - 1e-9 & d <= CS_RING[2] + 1e-9))
  expect_setequal(src, which(pl$u < 0.8))
  for (r in c(4, 2)) {
    st <- cs_reference(pl, "complete", p = 0.6)
    expect_equal(cs_true_skilled(st, un, r)[["ref"]], 0)
    expect_equal(cs_true_skilled(st, dp, r)[["ref"]], 0)
    expect_equal(cs_true_skilled(cs_reference(pl, "complete"), dp, r)[["ref"]], 0)
  }
})

test_that("the structure scorer matches the first scorer on the common rows", {
  pl <- cs_plot(240, 11)
  seeds <- function(k) 1000L + k
  dets <- data.frame(detector = c("x", "u"), s = c(0.6, 0.8), f = c(0.5, 0.3),
                     mode = c("all", "unmapped"))
  refs <- data.frame(ref = c("complete", "half", "complete"), p = c(1, 1, 0.6))
  r <- cs_score_structure(pl, dets, refs, c(4, 2), K = 3, null_seed = seeds)
  expect_equal(nrow(r), 2 * 3 * 2 * 3)
  old <- cs_score_plot(pl, dets[1, 1:3], c("complete", "half"), c(4, 2), K = 3, null_seed = seeds)
  new <- r[r$detector == "x" & r$p == 1, names(old)]
  new <- new[order(new$ref, -new$tol, new$variant), ]
  old <- old[order(old$ref, -old$tol, old$variant), ]
  rownames(new) <- NULL; rownames(old) <- NULL
  expect_equal(new, old)
  # The unmapped-only detector has no truth anywhere, and its detections at
  # p = 1 are commission only.
  expect_true(all(r$TP[r$detector == "u" & r$variant == "truth"] == 0))
  st <- cs_reference(pl, "complete", p = 0.6)
  det <- cs_detector(pl, 0.8, 0.3, mode = "unmapped", p = 0.6)
  o <- r[r$detector == "u" & r$p == 0.6 & r$tol == 2 & r$variant == "observed", ]
  expect_equal(o$TP, score_plot(st, det, tol_xy = 2, core_cx = 0, core_cy = 0,
                                core_half = 20)$TP)
})

## ---- split crowns and paired leads ------------------------------------------------
# The plot generator as it was before the split-crown draws were added,
# verbatim; `after` draws further from the same stream after the ring draws.
cs_plot_before_split <- function(D, seed, f_max = CS_F_MAX, pattern = "inhibited",
                                 after = NULL) {
  pat <- CS_PATTERNS[[pattern]]
  if (is.null(pat)) stop("Unknown pattern: ", pattern)
  cs_with_seed(seed, {
    quads <- CS_QUAD_PAIRS[, sample.int(ncol(CS_QUAD_PAIRS), 1)]
    tr <- if (pat$type == "inhibited") cs_pattern(D) else cs_pattern_matern(D, pat$R, pat$mu)
    n <- nrow(tr)
    tr$h <- cs_heights(stats::runif(n))
    u <- stats::runif(n)
    zx <- stats::rnorm(n); zy <- stats::rnorm(n); zz <- stats::rnorm(n)
    M <- ceiling(f_max * n)
    pu <- matrix(stats::runif(3 * M), ncol = 3, byrow = TRUE)
    pool <- data.frame(x = -CS_SIM_HALF + 2 * CS_SIM_HALF * pu[, 1],
                       y = -CS_SIM_HALF + 2 * CS_SIM_HALF * pu[, 2],
                       z = cs_heights(pu[, 3]))
    v <- stats::runif(n)
    ring_d <- sqrt(stats::runif(n, CS_RING[1]^2, CS_RING[2]^2))
    ring_a <- stats::runif(n, 0, 2 * pi)
    out <- list(D = D, seed = seed, pattern = pattern, quadrants = quads, trees = tr, u = u,
                zx = zx, zy = zy, zz = zz, pool = pool, v = v, ring_d = ring_d, ring_a = ring_a)
    if (!is.null(after)) out$after <- after(n)
    out
  })
}

test_that("the split-crown draws come last and leave every earlier draw unchanged", {
  split_draws <- function(n) list(split_w = runif(n), split_d = runif(n, 1.5, 4),
                                  split_a = runif(n, 0, 2 * pi), split_z = rnorm(n))
  for (pt in names(CS_PATTERNS)) for (D in c(240, 400)) for (seed in c(3L, 1234567L)) {
    new <- cs_plot(D, seed, pattern = pt)
    old <- cs_plot_before_split(D, seed, pattern = pt, after = split_draws)
    after <- old$after; old$after <- NULL
    expect_identical(new[names(old)], old)
    expect_identical(setdiff(names(new), names(old)), names(after))
    expect_identical(new[names(after)], after)
  }
  expect_true(all(new$split_d >= CS_SPLIT[1] & new$split_d <= CS_SPLIT[2]))
  # A plot without the split-crown draws cannot give split crowns.
  expect_error(cs_detector(cs_plot_before_split(240, 3), 0.45, 0.45, mode = "split", rate = 0.5),
               "split-crown draws")
})

test_that("the split-crown detector adds one detection beside a share rate of the detected trees", {
  pl <- cs_plot(240, 31, pattern = "clustered_8m")
  al <- cs_detector(pl, 0.45, 0.45)
  expect_identical(cs_detector(pl, 0.45, 0.45, mode = "split", rate = 0), al)
  expect_identical(cs_detector(pl, 0.45, 0.45, mode = "split"), al)
  prev <- integer(0)
  for (rate in c(0.5, 0.8, 1)) {
    sp <- cs_detector(pl, 0.45, 0.45, mode = "split", rate = rate)
    # The first rows are mode "all"'s detections; the rest are split crowns.
    expect_identical(as.list(sp[seq_len(nrow(al)), ]), as.list(al))
    ex <- sp[-seq_len(nrow(al)), ]
    src <- which(pl$u < 0.45 & pl$split_w < rate)
    expect_equal(nrow(ex), length(src))
    expect_true(all(ex$tree == 0L))
    # Each lies 1.5-4 m from a tree the detector detects, at that tree's
    # height plus the height error.
    expect_true(all(src %in% al$tree[al$tree > 0]))
    d <- sqrt((ex$x - pl$trees$x[src])^2 + (ex$y - pl$trees$y[src])^2)
    expect_equal(d, pl$split_d[src])
    expect_true(all(d >= CS_SPLIT[1] & d <= CS_SPLIT[2]))
    expect_equal(ex$z, pl$trees$h[src] + CS_SIGMA_Z * pl$split_z[src])
    # Split crowns nest across rates.
    expect_true(all(prev %in% src)); prev <- src
    # They are commission: the truth and the oracle count the same own
    # detections as for mode "all".
    for (r in c(4, 2)) for (p in c(1, 0.6)) {
      st <- cs_reference(pl, "complete", p = p)
      expect_identical(cs_true_skilled(st, sp, r), cs_true_skilled(st, al, r))
    }
  }
  expect_equal(nrow(ex), sum(pl$u < 0.45))          # rate 1: every detected tree
  # Over many plots the share of detected trees with a split crown follows rate.
  for (rate in c(0.5, 0.8)) {
    cnt <- rowSums(vapply(1:40, function(i) {
      q <- cs_plot(240, 500 + i)
      c(sum(cs_detector(q, 0.45, 0.45, mode = "split", rate = rate)$tree == 0) -
          round(0.45 * nrow(q$trees)), sum(q$u < 0.45))
    }, numeric(2)))
    expect_lt(abs(cnt[1] / cnt[2] - rate), 4 * sqrt(rate * (1 - rate) / cnt[2]))
  }
  expect_error(cs_detector(pl, 0.45, 0.45, mode = "split", rate = 1.5), "rate")
  expect_error(cs_detector(pl, 0.45, 0.45, mode = "split", rate = NA_real_), "rate")
  # The structure scorer passes the rate: same truth as the baseline, more
  # detections, and a missing rate column means rate 0.
  seeds <- function(k) 1000L + k
  dets <- data.frame(detector = c("base", "split"), s = 0.45, f = 0.45,
                     mode = c("all", "split"), rate = c(0, 0.8))
  refs <- data.frame(ref = "complete", p = c(1, 0.6))
  r <- cs_score_structure(pl, dets, refs, 4, K = 2, null_seed = seeds)
  g <- function(det, v, col) r[[col]][r$detector == det & r$variant == v]
  expect_equal(g("split", "truth", "TP"), g("base", "truth", "TP"))
  expect_equal(g("split", "truth", "tp_core"), g("base", "truth", "tp_core"))
  expect_true(all(g("split", "observed", "n_det") > g("base", "observed", "n_det")))
  r0 <- cs_score_structure(pl, dets[1, 1:4], refs, 4, K = 2, null_seed = seeds)
  rb <- r[r$detector == "base", ]
  rownames(rb) <- NULL; rownames(r0) <- NULL
  expect_equal(r0, rb)
})

test_that("a paired lead differences leader and base over the shared plot resamples", {
  # Six plots in two sites, the three variants of four detectors: the
  # displaced and uniform detectors without skill (truth 0), the baseline and
  # a twin that repeats the baseline's counts.
  cells <- expand.grid(plot = paste0("p", 1:6), variant = c("observed", "null", "truth"),
                       detector = c("baseline", "zero_skill", "zero_displaced", "twin"),
                       stringsAsFactors = FALSE)
  cells$site <- ifelse(cells$plot %in% c("p1", "p2", "p3"), "A", "B")
  cells$n_ref <- 20 + as.integer(sub("p", "", cells$plot))
  cells$n_det <- 24
  cells$TP <- cs_with_seed(2, sample(3:15, nrow(cells), replace = TRUE))
  cells$tp_core <- cs_with_seed(3, sample(2:14, nrow(cells), replace = TRUE))
  nul <- cells$variant == "truth" & cells$detector %in% c("zero_skill", "zero_displaced")
  cells$TP[nul] <- 0; cells$tp_core[nul] <- 0
  tw <- cells$detector == "twin"
  cells[tw, c("TP", "tp_core")] <- cells[cells$detector == "baseline", c("TP", "tp_core")]
  W <- mt_plot_weights(cells$site, cells$plot, 200, 7)
  s <- mt_boot_scores(cells, W, c("variant", "detector"))
  cmp <- data.frame(comparison = c("e_pair", "twin_pair", "missing"),
                    leader = c("zero_displaced", "twin", "split_050"),
                    base = c("zero_skill", "baseline", "baseline"), stringsAsFactors = FALSE)
  key <- data.frame(pattern = "clustered_8m", ref = "complete", tol = 4)
  L <- cs_paired_leads(s, cmp, key)
  # A comparison whose leader is not scored is skipped.
  expect_equal(L$comparison, c("e_pair", "twin_pair"))
  expect_equal(L$plots, c(6L, 6L))
  expect_equal(L$pattern, rep("clustered_8m", 2))
  # The lead: the leader's corrected F1 minus its base's, from summed counts.
  tot <- function(det, v, col) sum(cells[[col]][cells$detector == det & cells$variant == v])
  f1 <- function(det, v) {
    r <- tot(det, v, "TP") / tot(det, v, "n_ref"); p <- tot(det, v, "tp_core") / tot(det, v, "n_det")
    2 * r * p / (r + p)
  }
  cf <- function(det) cs_corrected(f1(det, "observed"), f1(det, "null"))
  expect_equal(L$corr_F1_lead[1], cf("zero_displaced") - cf("zero_skill"))
  expect_equal(L$obs_F1_lead[1], f1("zero_displaced", "observed") - f1("zero_skill", "observed"))
  expect_equal(L$true_diff[1], 0)
  # Neither detector without skill has an own detection, so neither has an
  # oracle F1.
  expect_true(is.na(L$oracle_F1_lead[1]))
  # The interval is the percentile interval of the paired differences.
  dr <- function(det) cs_corrected(s$draws$F1[, paste0("observed|", det)],
                                   s$draws$F1[, paste0("null|", det)])
  iv <- mt_interval(dr("zero_displaced") - dr("zero_skill"))
  expect_equal(c(L$corr_F1_lead_lower[1], L$corr_F1_lead_upper[1]), c(iv$lower, iv$upper))
  # A leader identical to its base leads by zero in every resample.
  z <- unlist(L[2, grep("_lead|true_diff", names(L))])
  expect_true(all(z == 0))
  expect_null(cs_paired_leads(s, cmp[3, ], key))
})

test_that("window pair counts and their random expectation are right", {
  # Closed form against a Monte Carlo estimate.
  set.seed(5)
  x1 <- runif(4e5, 0, 20); y1 <- runif(4e5, 0, 20); x2 <- runif(4e5, 0, 20); y2 <- runif(4e5, 0, 20)
  dd <- sqrt((x1 - x2)^2 + (y1 - y2)^2)
  for (d in c(2, 4)) expect_lt(abs(cs_square_pair_prob(d, 20) - mean(dd <= d)), 0.002)
  expect_error(cs_square_pair_prob(25, 20), "exceed")
  w <- cs_window_pairs(c(0, 1, 3, 10), c(0, 0, 0, 0), c(2, 4), 20)
  expect_equal(w$pairs, c(2, 3))
  expect_equal(w$expected, 6 * cs_square_pair_prob(c(2, 4), 20))
  expect_equal(cs_window_pairs(1, 1, 4, 20)$pairs, 0)
  # A random pattern gives a ratio near one.
  r <- rowSums(vapply(1:400, function(k) cs_with_seed(k, {
    n <- rpois(1, 16); w <- cs_window_pairs(runif(n, 0, 20), runif(n, 0, 20), 4, 20)
    c(w$pairs, w$expected)
  }), numeric(2)))
  expect_lt(abs(r[1] / r[2] - 1), 0.05)
})

test_that("window pairs pool by summing counts, resampling plots within strata", {
  rows <- data.frame(group = "g", stratum = c("A", "A", "A", "B"), unit = c("p1", "p1", "p2", "p3"),
                     d = 4, n = c(10, 6, 20, 4), pairs = c(6, 1, 30, 0),
                     expected = c(4, 2, 20, 1))
  s <- cs_pool_pairs(rows, n_boot = 200, seed = 1)
  expect_equal(s$units, 3); expect_equal(s$windows, 4); expect_equal(s$n, 40)
  expect_equal(s$ratio, 37 / 27)
  expect_equal(s$mean_observed, 2 * 37 / 40)
  expect_equal(s$mean_random, 2 * 27 / 40)
  expect_true(s$ratio_lower <= s$ratio && s$ratio <= s$ratio_upper)
  # The excess: observed minus random mean, with an interval from the same
  # resamples as the ratio's.
  expect_equal(s$excess, 2 * (37 - 27) / 40)
  expect_equal(s$excess, s$mean_observed - s$mean_random)
  W <- mt_plot_weights(rows$stratum, rows$unit, 200, 1)
  agg <- rowsum(as.matrix(rows[c("n", "pairs", "expected")]),
                paste(rows$stratum, rows$unit, sep = "::"))[rownames(W), ]
  ex <- 2 * (crossprod(W, agg[, "pairs"]) - crossprod(W, agg[, "expected"])) /
    crossprod(W, agg[, "n"])
  iv <- mt_interval(as.vector(ex))
  expect_equal(c(s$excess_lower, s$excess_upper), c(iv$lower, iv$upper))
  expect_true(s$excess_lower <= s$excess && s$excess <= s$excess_upper)
  # Stratum B holds one plot, which every resample keeps once: a group of it
  # alone has no spread.
  b <- cs_pool_pairs(rows[rows$stratum == "B", ], n_boot = 50, seed = 1)
  expect_equal(c(b$ratio_lower, b$ratio_upper), c(0, 0))
  expect_equal(c(b$excess, b$excess_lower, b$excess_upper), rep(2 * (0 - 1) / 4, 3))
  expect_identical(cs_pool_pairs(rows, n_boot = 200, seed = 1), s)
  # Plot ids of the simulation.
  expect_equal(cs_plot_id(240, 7), "D240_0007")
  expect_equal(cs_plot_id(400, 12, "clustered_8m"), "M8_D400_0012")
})
