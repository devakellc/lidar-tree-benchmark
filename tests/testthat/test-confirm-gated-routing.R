# Unit tests for scripts/confirm_gated_routing.R (check R6 of the
# multichm_gated confirmation protocol: the paper's density routing with one
# gated configuration added as a candidate): arguments and the output guard,
# the candidate's cells from the gated files, cell parity, the selection
# ranking, the comparison with reference tables, Table 7 extraction, and (when
# the paper branch's density_routing_lib.R is available) the routing with and
# without the candidate, shared draws, scores, contrasts, picks, margins, the
# Table 7 rows and the requested tables. Sourcing the script defines its
# helpers without running it. Synthetic counts only.
source(file.path("..", "..", "scripts", "confirm_gated_routing.R"), local = TRUE)

# The routing library lives on the paper branch, not on this one: tests that
# need it skip when it cannot be found (ROUTING_LIB= overrides the default).
cgr_lib <- Sys.getenv("ROUTING_LIB", file.path("..", "..", "work", "paper-novelty-checkout", "scripts",
                                               "density_routing_lib.R"))
have_lib <- file.exists(cgr_lib)
if (have_lib) source(cgr_lib, local = TRUE)
need_lib <- function() skip_if_not(have_lib, "density_routing_lib.R (paper branch) is not available")

## ---- synthetic data -------------------------------------------------------------------------------
SYN_SITES <- c("SJER", "SOAP", "TEAK", "WREF", "ABBY")
SYN_GPU <- c("forestformer3d", "segmentanytree", "treeisonet", "multichm", "chm_vwf", "ams3d", "ptrees",
             "lmfauto")
SYN_CPU <- c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d")
SYN_SCOPES <- list(`five sites` = SYN_SITES, California = c("SJER", "SOAP", "TEAK"),
                   Washington = c("WREF", "ABBY"))
syn_band <- function(fr) c("C", "B", "A")[findInterval(fr, c(0, 2, 8))]
# Two plots per site at two levels; every site has a cell in each band.
syn_dens <- function() {
  x <- expand.grid(k = 1:2, site = SYN_SITES, level = c("native", "1"), stringsAsFactors = FALSE)
  x$plot <- sprintf("%s_%d", x$site, x$k)
  x$frdens <- ifelse(x$level == "native", ifelse(x$k == 1, 10, 5), ifelse(x$k == 1, 3, 1))
  x$pdens <- 1.6 * x$frdens
  x$band <- syn_band(x$frdens)
  x$region <- ifelse(x$site %in% c("WREF", "ABBY"), "Washington", "California")
  x$status <- "ok"
  x[c("site", "plot", "level", "status", "pdens", "frdens", "band", "region")]
}
# Counts per detector: a bonus makes `best[band]` the best of its band.
syn_cells <- function(dens, dets, best = c(A = "segmentanytree", B = "forestformer3d", C = "multichm"),
                      bonus = 6) {
  do.call(rbind, lapply(c("baseline", "null"), function(v) do.call(rbind, lapply(seq_along(dets), function(j) {
    a <- dets[j]
    tp <- 4 + j %% 4 + ifelse(best[dens$band] == a, bonus, 0) + seq_len(nrow(dens)) %% 3
    if (a == "gated") tp <- tp + ifelse(dens$band == "C", 9, 0)
    if (v == "null") tp <- 0.3 * tp
    data.frame(variant = v, site = dens$site, plot = dens$plot, level = dens$level, detector = a,
               frdens = dens$frdens, band = dens$band, TP = tp, n_ref = 20, n_det = 22 + j,
               tp_core = tp, stringsAsFactors = FALSE)
  }))))
}
syn_W <- function(dens, n = 60) mt_plot_weights(dens$site, dens$plot, n, 7L)

## ---- arguments, output guard, cells -------------------------------------------------------------------
test_that("arguments are KEY=VALUE, values may hold '=' and unknown keys stop", {
  A <- cgr_args(c("CONFIG=z5_s0.5", "SELECTION=a=b", "HELD_OUT=yes"))
  expect_identical(A$CONFIG, "z5_s0.5"); expect_identical(A$SELECTION, "a=b")
  expect_length(cgr_args(character()), 0)
  expect_error(cgr_args("NOPE=1"), "Unknown arguments: NOPE")
  expect_error(cgr_args(c("OUT=a", "OUT=b")), "Repeated")
})

test_that("OUT may not lie under the paper runs, the calibration runs, a frozen root or a protected dir", {
  tmp <- tempfile("cgr")
  dir.create(file.path(tmp, "work", "paper_runs"), recursive = TRUE)
  dir.create(file.path(tmp, "checkout"), recursive = TRUE)
  for (p in c(file.path(tmp, "work", "paper_runs", "x"), file.path(tmp, "work", "paper_runs_ql2", "y"),
              file.path(tmp, "work", "multichm_gated_runs", "neon"), file.path(tmp, "neon", "frozen_2021", "z")))
    expect_error(cgr_check_out(p), "protected")
  expect_error(cgr_check_out(file.path(tmp, "checkout", "out"), file.path(tmp, "checkout")), "protected")
  ok <- cgr_check_out(file.path(tmp, "work", "multichm_gated_confirmation", "routing", "a"),
                      file.path(tmp, "checkout"))
  expect_true(endsWith(ok, file.path("multichm_gated_confirmation", "routing", "a")))
  # a symlink into a protected directory is resolved
  if (file.symlink(file.path(tmp, "work", "paper_runs"), file.path(tmp, "link")))
    expect_error(cgr_check_out(file.path(tmp, "link", "out")), "protected")
})

syn_gated <- function() {
  data.frame(site = "SJER", plot = c("SJER_1", "SJER_1", "SJER_2", "SJER_1"),
             rung = c("native", "1", "native", "native"), config = c("c1", "c1", "c1", "stock"),
             config_id = c(5L, 5L, 5L, 1L), n_ref = 20, n_det = c(30, 28, 31, 33), TP = c(10, 9, 11, 8),
             tp_core = c(9, 8, 10, 7), n_det0 = c(29.5, 27.2, 30.1, 32), TP0 = c(3.1, 2.5, 3.3, 2.9),
             tp_core0 = c(2.8, 2.2, 3.0, 2.5), pdens = 16, frdens = 10, stringsAsFactors = FALSE)
}

test_that("the candidate's rows carry the observed counts and the null means", {
  r <- cgr_gated_rows(syn_gated(), "c1", "gated")
  expect_equal(nrow(r), 6)
  b <- r[r$variant == "baseline", ]; n <- r[r$variant == "null", ]
  expect_true(all(r$detector == "gated"))
  expect_equal(b$n_det, c(30, 28, 31)); expect_equal(b$TP, c(10, 9, 11)); expect_equal(b$tp_core, c(9, 8, 10))
  expect_equal(n$n_det, c(29.5, 27.2, 30.1)); expect_equal(n$TP, c(3.1, 2.5, 3.3))
  expect_equal(n$tp_core, c(2.8, 2.2, 3.0)); expect_equal(n$n_ref, b$n_ref)
  expect_identical(b$level, c("native", "1", "native"))
  expect_error(cgr_gated_rows(syn_gated(), "c9", "gated"), "not in the gated cells")
  expect_error(cgr_gated_rows(rbind(syn_gated(), syn_gated()[1, ]), "c1", "gated"), "Duplicate")
  expect_error(cgr_gated_rows(syn_gated()[, -which(names(syn_gated()) == "TP0")], "c1", "gated"), "TP0")
})

test_that("cell parity reports the largest difference and the cells that differ or are missing", {
  a <- cgr_gated_rows(syn_gated(), "c1", "gated")
  p <- cgr_cell_parity(a, a)
  expect_true(all(p$differing == 0) && all(p$max_abs_diff == 0) && all(p$missing == 0))
  expect_setequal(paste(p$variant, p$level), c("baseline native", "baseline 1", "null native", "null 1"))
  b <- a; b$TP[b$variant == "null"][1] <- b$TP[b$variant == "null"][1] + 1e-6
  p <- cgr_cell_parity(a, b)
  hit <- p[p$variant == "null" & p$level == "native" & p$count == "TP", ]
  expect_equal(hit$differing, 1); expect_equal(hit$max_abs_diff, 1e-6, tolerance = 1e-9)
  expect_equal(sum(p$differing), 1)
  p <- cgr_cell_parity(a, a[-1, ])
  expect_true(all(p$missing[p$variant == "baseline" & p$level == "native"] == 1))
})

test_that("the selection ranks configurations by pooled corrected F1, ties to the smallest config_id", {
  g <- rbind(transform(syn_gated()[1:3, ], config = "c7", config_id = 7L), syn_gated()[1:3, ],
             transform(syn_gated()[1:3, ], config = "chm_vwf", config_id = NA_integer_))
  g$site <- "SJER"
  s <- cgr_selection(g, "SJER", "native")
  expect_identical(s$config, c("c1", "c7"))                  # tie: smallest config_id first, no NA config
  expect_equal(s$rank, 1:2)
  x <- syn_gated()[c(1, 3), ]
  f1 <- function(r, p) 2 * r * p / (r + p)
  F1 <- f1(sum(x$TP) / sum(x$n_ref), sum(x$tp_core) / sum(x$n_det))
  F0 <- f1(sum(x$TP0) / sum(x$n_ref), sum(x$tp_core0) / sum(x$n_det0))
  expect_equal(s$F1[1], F1); expect_equal(s$F1_corrected[1], (F1 - F0) / (1 - F0))
  g2 <- g; g2$TP[g2$config == "c7"] <- g2$TP[g2$config == "c7"] + 1
  expect_identical(cgr_selection(g2, "SJER", "native")$config[1], "c7")
  expect_error(cgr_selection(g[-1, ], "SJER", "native"), "different plots")
})

test_that("tables are compared column by column on their keys", {
  ref <- data.frame(k = c("a", "b"), x = c(1, Inf), y = c("p", NA), z = c(TRUE, FALSE), stringsAsFactors = FALSE)
  same <- cgr_compare(ref[2:1, ], ref, "k", table = "t")
  expect_true(all(same$differing == 0)); expect_true(all(same$rows_differing == 0))
  expect_false(same$same_row_order[1])
  h <- ref; h$x[1] <- 1 + 1e-8
  expect_equal(cgr_compare(h, ref, "k")$differing[1], 1)
  h <- ref; h$x[1] <- 1 + 1e-10
  expect_equal(sum(cgr_compare(h, ref, "k")$differing), 0)
  h <- ref; h$y[2] <- "q"
  expect_equal(cgr_compare(h, ref, "k")$rows_differing[1], 1)
  h <- ref; h$k[2] <- "c"
  expect_equal(cgr_compare(h, ref, "k")$keys_unmatched[1], 2)
  expect_error(cgr_compare(ref[1:3], ref, "k"), "columns differ")
})

test_that("the body rows of Table 7 are read from the manuscript", {
  lines <- c("text", "**Table 7.** The pipeline.", "more caption", "",
             "| Band | Compute |", "| --- | --- |", "| A | GPU |", "| B | CPU |", "", "| other |")
  expect_identical(cgr_manuscript_table7(lines), c("| A | GPU |", "| B | CPU |"))
  expect_error(cgr_manuscript_table7(lines[-2]), "not found")
})

## ---- the routing (needs the paper branch's library) ----------------------------------------------------
test_that("the routing picks per band, and adding a candidate leaves every other score and draw unchanged", {
  need_lib()
  dens <- syn_dens(); W <- syn_W(dens)
  base <- syn_cells(dens, SYN_GPU)
  run0 <- cgr_route(base, W, SYN_SCOPES, list(gpu = SYN_GPU, cpu = SYN_CPU))
  expect_identical(run0$routes$gpu$pick, c("segmentanytree", "forestformer3d", "multichm"))
  expect_true(all(run0$routes$cpu$pick %in% SYN_CPU))
  cells <- syn_cells(dens, c(SYN_GPU, "gated"))
  kept <- cells[cells$detector != "gated", ]; rownames(kept) <- NULL
  expect_identical(kept, base)
  cand <- list(gpu = c(SYN_GPU, "gated"), cpu = c(SYN_CPU, "gated"))
  extra <- list(paper_gpu_route = run0$routes$gpu, paper_cpu_route = run0$routes$cpu)
  run1 <- cgr_route(cells, W, SYN_SCOPES, cand, extra)
  expect_identical(run1$routes$gpu$pick[3], "gated")              # the candidate wins band C
  expect_identical(run1$routes$cpu$pick[3], "gated")
  expect_true(all(c("paper_gpu_route", "paper_cpu_route") %in% names(run1$policies)))
  for (sc in names(SYN_SCOPES)) {
    g0 <- run0$S[[sc]]$groups
    keep <- grepl(paste0("\\|(", paste(SYN_GPU, collapse = "|"), ")\\|"), g0)
    expect_identical(unname(run0$S[[sc]]$draws$F1[, g0[keep]]), unname(run1$S[[sc]]$draws$F1[, g0[keep]]))
    gr <- g0[grepl("\\|gpu_route\\|", g0)]
    expect_identical(unname(run0$S[[sc]]$draws$F1[, gr]),
                     unname(run1$S[[sc]]$draws$F1[, sub("|gpu_route|", "|paper_gpu_route|", gr, fixed = TRUE)]))
  }
  expect_error(cgr_route(base, W, SYN_SCOPES, cand), "exactly the candidates")
  expect_error(cgr_route(cells, W, SYN_SCOPES, cand, list(gpu_route = run0$routes$gpu)), "distinct")
  expect_error(cgr_route(cells, W, SYN_SCOPES, list(cpu = SYN_CPU, gpu = SYN_GPU)), "list\\(gpu")
})

syn_run <- function() {
  dens <- syn_dens(); W <- syn_W(dens)
  run0 <- cgr_route(syn_cells(dens, SYN_GPU), W, SYN_SCOPES, list(gpu = SYN_GPU, cpu = SYN_CPU))
  cand <- list(gpu = c(SYN_GPU, "gated"), cpu = c(SYN_CPU, "gated"))
  cells <- syn_cells(dens, cand$gpu)
  run <- cgr_route(cells, W, SYN_SCOPES, cand,
                   list(paper_gpu_route = run0$routes$gpu, paper_cpu_route = run0$routes$cpu))
  scores <- cgr_scores(run, dens, SYN_SCOPES)
  more <- data.frame(policy = rep(c("gpu_route", "cpu_route"), each = 2),
                     versus = rep(c("paper_gpu_route", "paper_cpu_route"), 2), stringsAsFactors = FALSE)
  contrasts <- cgr_contrasts(run$S, SYN_SCOPES, cgr_pairs(cand$gpu, more), c(DR_BANDS$band, "all"))
  picks <- cgr_margins(cgr_picks(run, scores, contrasts), contrasts)
  list(dens = dens, cells = cells, run = run, scores = scores, contrasts = contrasts, picks = picks, cand = cand)
}

test_that("scores, contrasts, picks and margins agree with each other", {
  need_lib()
  x <- syn_run()
  sc <- x$scores
  expect_true(all(c("scope", "role", "kind", "policy", "slice", "metric", "estimate", "lower", "upper") %in% names(sc)))
  expect_identical(unique(sc$kind[sc$policy == "gated"]), "detector")
  expect_identical(unique(sc$kind[sc$policy == "paper_gpu_route"]), "policy")
  g <- function(p, s, m = "F1", scope = "Washington") cgr_get(sc, scope = scope, policy = p, slice = s, metric = m)$estimate
  # in band C the route is the candidate; in band A the paper's route equals the new one
  expect_equal(g("gpu_route", "C"), g("gated", "C"))
  d <- cgr_get(x$contrasts, scope = "Washington", slice = "A", policy = "gpu_route", versus = "paper_gpu_route",
               metric = "F1_corrected")
  expect_equal(c(d$estimate, d$lower, d$upper), c(0, 0, 0))
  d <- cgr_get(x$contrasts, scope = "five sites", slice = "all", policy = "gpu_route", versus = "multichm", metric = "F1")
  expect_equal(d$estimate, g("gpu_route", "all", scope = "five sites") - g("multichm", "all", scope = "five sites"))
  # corrected F1 is (F1 - null F1) / (1 - null F1) of the pooled counts
  f <- g("gated", "B"); f0 <- g("gated", "B", "F1_null")
  expect_equal(g("gated", "B", "F1_corrected"), (f - f0) / (1 - f0))
  p <- x$picks
  expect_identical(p$pick[p$route == "gpu"], c("segmentanytree", "forestformer3d", "gated"))
  expect_true(all(p$ca_margin > 0))
  expect_true(all(p$ca_margin_lower <= p$ca_margin_upper))
  m <- cgr_get(x$contrasts, scope = "California", slice = "B", policy = "gpu_route",
               versus = p$ca_runner_up[p$route == "gpu" & p$band == "B"], metric = "F1")
  expect_equal(m$lower, p$ca_margin_lower[p$route == "gpu" & p$band == "B"])
  bands <- cgr_bands_out(x$dens, x$cells, SYN_SCOPES, c("native", "1"))
  expect_equal(unname(bands$cells[bands$scope == "five sites"]), c(5, 10, 5))
  co <- cgr_cells_out(x$dens, c("native", "1"), c(native = 7.5, `1` = 2), x$run$policies)
  expect_identical(co$gpu_route[co$band == "C"][1], "gated")
  expect_identical(co$paper_gpu_route[co$band == "C"][1], "multichm")
})

test_that("Table 7 rows carry the band text, the margin, the level candidates and the best", {
  need_lib()
  x <- syn_run()
  t7 <- cgr_table7(x$picks, x$contrasts, x$cand, c(CGR_NAMES, gated = "`gated`"))
  expect_identical(t7$route, rep(c("gpu", "cpu"), 3))
  expect_identical(t7$band, rep(c("A", "B", "C"), each = 2))
  expect_true(startsWith(t7$row[1], "| QL1 or denser (A: ≥ 8) | GPU | SegmentAnyTree | "))
  expect_true(startsWith(t7$row[3], "| QL2 to QL1 (B: 2 to < 8) | GPU | ForestFormer3D | "))
  expect_true(startsWith(t7$row[5], "| Below QL2 (C: < 2) | GPU | `gated` | "))
  ru <- x$picks$ca_runner_up[x$picks$route == "gpu" & x$picks$band == "A"]
  expect_match(t7$row[1], paste0(" over ", CGR_NAMES[[ru]], " | "), fixed = TRUE)
  p <- x$picks
  for (i in seq_len(nrow(t7))) {
    pk <- p[p$route == t7$route[i] & p$band == t7$band[i], ]
    expect_identical(endsWith(t7$row[i], "| — |"), identical(pk$pick, pk$wa_best))
  }
  # level candidates: those whose paired Washington F1 difference to the pick includes zero
  ct <- x$contrasts[x$contrasts$scope == "Washington" & x$contrasts$slice == "C" &
                      x$contrasts$policy == "cpu_route" & x$contrasts$metric == "F1" &
                      x$contrasts$versus %in% setdiff(x$cand$cpu, "gated"), ]
  lev <- ct$versus[ct$lower <= 0 & ct$upper >= 0]
  cells7 <- strsplit(t7$row[6], " | ", fixed = TRUE)[[1]]
  expect_identical(cells7[7], if (length(lev)) paste(CGR_NAMES[x$cand$cpu[x$cand$cpu %in% lev]], collapse = ", ")
                   else "none")
})

test_that("the requested tables pair the route and the candidate with the others", {
  need_lib()
  x <- syn_run()
  wb <- cgr_band_table(x$run, x$scores, x$contrasts, "Washington")
  expect_equal(nrow(wb), 3 * (length(x$cand$gpu) + length(x$cand$cpu)))
  expect_true(all(wb$pick_minus_F1[wb$is_pick] == 0))
  expect_equal(sum(wb$is_scope_best), 6)
  i <- which(wb$route == "gpu" & wb$band == "A" & wb$candidate == "treeisonet")
  expect_equal(wb$pick_minus_F1[i], wb$F1[wb$route == "gpu" & wb$band == "A" & wb$is_pick] - wb$F1[i])
  rv <- cgr_route_versus(x$scores, x$contrasts, c("gpu_route", "cpu_route"),
                         c("paper_gpu_route", "paper_cpu_route", "gated", "multichm"))
  expect_equal(nrow(rv), 3 * 2 * 4)
  expect_equal(rv$diff_F1, rv$route_F1 - rv$versus_F1)
  expect_equal(rv$diff_F1c, rv$route_F1c - rv$versus_F1c)
  sl <- c("level native", "level 1", "all")
  cc <- cgr_contrasts(x$run$S, SYN_SCOPES, data.frame(policy = "gated", versus = SYN_GPU, stringsAsFactors = FALSE), sl)
  cl <- cgr_candidate_levels(x$scores, cc, "gated", SYN_GPU, sl)
  expect_equal(nrow(cl), 3 * 3 * length(SYN_GPU))
  expect_equal(cl$diff_F1, cl$cand_F1 - cl$versus_F1)
  expect_equal(unique(cl$n_plots[cl$scope == "Washington"]), 4)
})

test_that("the gated files' densities are compared with the routing's and banded separately", {
  need_lib()
  dens <- syn_dens()
  gd <- dens[c("site", "plot", "level", "pdens", "frdens")]
  a <- cgr_density_agreement(gd, dens, dr_band)
  expect_true(all(a$band_agrees)); expect_true(all(a$frdens_diff == 0))
  gd$frdens[1] <- 7.9                                           # 10 -> band B in the gated copy only
  a <- cgr_density_agreement(gd, dens, dr_band)
  expect_equal(sum(!a$band_agrees), 1)
  expect_equal(min(a$frdens_diff), -2.1)
  expect_error(cgr_density_agreement(gd[-1, ], dens, dr_band), "different cells")
})
