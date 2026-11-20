#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("model_bench_lib.R"))
source(.find("master_tables_lib.R"))
source(.find("chance_simulation_lib.R"))
source(.find("census_support_lib.R"))      # census_admitted_plots

# How clustered the benchmark's reference stems are, beside the stand
# structures of the chance-correction simulation (simulate_chance_correction.R,
# scenario 4; post hoc). Reads the sealed root's population and stems; writes
# nothing there.
#
# Mapped area: NEON's design censuses a distributed plot whole, a 20 m square,
# which is the population's core box for that plot. A tower plot's 40 m box
# holds the stems of the sampled 20 m quadrants, and which quadrants were
# sampled cannot be read from the stems (an empty sampled quadrant looks
# unsampled, and some tower references mix censuses), so tower plots are left
# out: the statistic covers the distributed plots of the population only. The
# distributed plots whose event-specific census support the headline census
# declaration admits (census_admitted_plots: the archived support bundles
# under SUPPORT, as score_census_support.R reads them) are pooled again as a
# second group, "all sites, admitted census support", beside the rows of every
# distributed plot; the script stops when the bundles are missing or admit
# none of them.
#
# Statistic: per plot, the pairs of reference stems at most d apart (d = 2 and
# 4 m) and the pairs that the same number of stems placed at random in the
# same 20 m box would give (cs_window_pairs). Pooled per site by summing:
# mean other stems within d of a stem 2 sum(pairs) / sum(n), its random value
# 2 sum(expected) / sum(n), the ratio sum(pairs) / sum(expected) and the
# excess, observed minus random mean, each of the last two with a 95%
# interval from the master tables' plot resamples (within sites; the same
# resamples for both). For a cluster process with clusters of a fixed size
# the excess does not depend on how many clusters there are, while the ratio
# falls as density rises; mapping a random share of the trees scales the
# excess by that share and leaves the ratio unchanged.
# The simulated patterns get the same statistic on the four 20 m quadrants of
# each simulated core (the scenario-4 plots at 240 and 400 trees/ha, same ids
# and seeds), with every tree mapped (p = 1) and with p = 0.6, over every
# window and over the windows holding at least MIN_STEMS stems (the
# population's six-stem gate).
#   Rscript scripts/reference_stem_clustering.R [POP=adopted] [FROZEN_ROOT=...]
#     [N=200] [SEED=0] [MIN_STEMS=6] [OUT=$CLAUDE_JOB_DIR/sensitivity/chance_simulation]
#     [DECLARATION=docs/census-support-declaration-nearest.json]
#     [SUPPORT=$CLAUDE_JOB_DIR/reference_support_census_event] [YEARS=2019,...,2024]
# Writes OUT/reference_clustering_{plots,summary}.csv and
# reference_clustering_tables.md; the outputs hold nothing that varies between
# runs with the same arguments.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
d <- .job_dir()
POP  <- if (is.null(A$POP)) "adopted" else A$POP
N    <- as.integer(if (is.null(A$N)) 200 else A$N)
SEED <- as.integer(if (is.null(A$SEED)) 0 else A$SEED)
MIN_STEMS <- as.integer(if (is.null(A$MIN_STEMS)) 6 else A$MIN_STEMS)
OUT  <- if (is.null(A$OUT)) file.path(d, "sensitivity", "chance_simulation") else A$OUT
DECLARATION <- if (is.null(A$DECLARATION))
  file.path(.ROOT, "docs", "census-support-declaration-nearest.json") else A$DECLARATION
declaration <- jsonlite::read_json(DECLARATION, simplifyVector = TRUE)
if (grepl("DRAFT", declaration$name)) stop("Refusing a draft declaration; review and rename it first")
SUPPORT <- if (is.null(A$SUPPORT)) file.path(d, "reference_support_census_event") else A$SUPPORT
YEARS <- as.integer(strsplit(if (is.null(A$YEARS)) paste(2019:2024, collapse = ",") else A$YEARS,
                             ",")[[1]])
ADMITTED <- "all sites, admitted census support"
DIST <- c(2, 4)
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

## ---- benchmark: distributed plots of the population ---------------------------------
root <- frozen_root(d, A$FROZEN_ROOT)
if (!frozen_sealed(root)) stop("No sealed frozen root at ", root)
pop <- read.csv(file.path(root, "population.csv"), stringsAsFactors = FALSE)
col <- paste0("in_", POP)
if (!col %in% names(pop)) stop("Population not declared: ", POP)
pop <- pop[pop[[col]], , drop = FALSE]
stems <- read.csv(file.path(root, "population_stems.csv"), stringsAsFactors = FALSE)
stems <- stems[stems$population == POP, , drop = FALSE]
dist_plots <- pop[pop$plotType == "distributed", , drop = FALSE]
if (any(dist_plots$core_half != 10)) stop("A distributed plot's core is not a 20 m square")
bench <- do.call(rbind, lapply(seq_len(nrow(dist_plots)), function(i) {
  pl <- dist_plots[i, ]
  st <- stems[stems$site == pl$site & stems$plotID == pl$plotID, , drop = FALSE]
  inside <- abs(st$E - pl$easting) <= pl$core_half & abs(st$N - pl$northing) <= pl$core_half
  if (!all(inside)) stop("Reference stem outside the core of ", pl$plotID)
  data.frame(source = "benchmark", group = pl$site, stratum = pl$site, unit = pl$plotID,
             window = pl$plotID, cs_window_pairs(st$E, st$N, DIST, 2 * pl$core_half),
             stringsAsFactors = FALSE)
}))
n_tower <- sum(pop$plotType == "tower")
dist_plots$admitted <- census_admitted_plots(dist_plots, SUPPORT, declaration, YEARS)

## ---- simulated patterns: 20 m quadrants of the simulated cores ----------------------
sim <- do.call(rbind, lapply(names(CS_PATTERNS), function(pt) do.call(rbind, lapply(c(240, 400), function(D)
  do.call(rbind, lapply(seq_len(N), function(i) {
    pid <- cs_plot_id(D, i, pt)
    pl <- cs_plot(D, cs_seed(seed_for("chance_sim", pid, "plot"), SEED), pattern = pt)
    do.call(rbind, lapply(c(1, 0.6), function(p) {
      st <- cs_reference(pl, "complete", p = p)
      q <- cs_quadrant(st$E, st$N)
      do.call(rbind, lapply(1:4, function(k)
        data.frame(source = "simulation", group = sprintf("%s D=%d p=%g", pt, D, p),
                   stratum = paste(pt, D), unit = pid, window = paste0(pid, "_q", k),
                   cs_window_pairs(st$E[q == k], st$N[q == k], DIST, CS_PH),
                   stringsAsFactors = FALSE)))
    }))
  }))))))
rows <- rbind(bench, sim)
write.csv(rows, file.path(OUT, "reference_clustering_plots.csv"), row.names = FALSE)

## ---- pooled -------------------------------------------------------------------------
sites <- unique(bench$group)
all_sites <- transform(bench, group = "all sites")
admitted <- transform(bench[bench$unit %in% dist_plots$plotID[dist_plots$admitted], ], group = ADMITTED)
gated <- transform(sim[sim$n >= MIN_STEMS, ], group = paste0(group, " gated"))
summ <- cs_pool_pairs(rbind(bench, all_sites, admitted, sim, gated))
summ$area_ha <- ifelse(summ$group %in% c(sites, "all sites", ADMITTED), 0.04, (CS_PH / 1e2)^2)
summ$stems_per_ha <- summ$n / (summ$windows * summ$area_ha)
write.csv(summ, file.path(OUT, "reference_clustering_summary.csv"), row.names = FALSE)

f2 <- function(x) sprintf("%.2f", x)
fx <- function(r) sprintf("%+.2f [%+.2f, %+.2f]", r$excess, r$excess_lower, r$excess_upper)
md_rows <- lapply(unique(summ$group), function(g) {
  a <- summ[summ$group == g & summ$d == 2, ]; b <- summ[summ$group == g & summ$d == 4, ]
  paste("|", paste(c(g, a$units, a$windows, a$n, sprintf("%.0f", a$stems_per_ha),
                     f2(a$mean_observed), f2(a$mean_random),
                     sprintf("%s [%s, %s]", f2(a$ratio), f2(a$ratio_lower), f2(a$ratio_upper)),
                     fx(a), f2(b$mean_observed), f2(b$mean_random),
                     sprintf("%s [%s, %s]", f2(b$ratio), f2(b$ratio_lower), f2(b$ratio_upper)),
                     fx(b)),
                   collapse = " | "), "|")
})
md <- c("# Reference-stem clustering", "",
        sprintf(paste("Generated by reference_stem_clustering.R: population %s, %d distributed plots",
                      "(%d tower plots left out), %d of them with event-specific census support",
                      "admitted by the declaration %s (the group \"%s\"); simulated: N = %d plots per pattern and density,",
                      "SEED = %d, four 20 m quadrants per core; gated = windows with at least %d stems;",
                      "excess = observed minus random mean; %d bootstrap resamples (seed %d)."),
                POP, nrow(dist_plots), n_tower, sum(dist_plots$admitted), declaration$name, ADMITTED,
                N, SEED, MIN_STEMS, MT_N_BOOT, MT_SEED), "",
        paste("| Group | Plots | Windows | Stems | Stems/ha | Within 2 m: observed | Within 2 m: random |",
              "Within 2 m: ratio [95% CI] | Within 2 m: excess [95% CI] | Within 4 m: observed |",
              "Within 4 m: random | Within 4 m: ratio [95% CI] | Within 4 m: excess [95% CI] |"),
        paste("|", paste(rep("---", 13), collapse = " | "), "|"),
        unlist(md_rows), "")
writeLines(md, file.path(OUT, "reference_clustering_tables.md"))
cat(sprintf("wrote %s\n", file.path(OUT, "reference_clustering_tables.md")))
