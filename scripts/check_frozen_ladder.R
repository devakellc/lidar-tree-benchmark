#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)

# Acceptance check for the frozen clips: does the CHM-VWF ladder regenerated on
# the frozen root reproduce the cached, unseeded sweep within decimation noise?
# Decimation noise is measured, not assumed: the frozen run (salt 0) and the
# replicate roots (SEED_SALT=1..K, freeze_clips.R) are independent seeded
# realizations of the same plots, so their spread per site x rung is the
# realization noise of a pooled metric. The cached value is one more
# realization; z = (cached - mean) / (sd * sqrt(1 + 1/n)) follows Student's t
# with n - 1 degrees of freedom, and each |z| must stay inside the two-sided
# 99% prediction bound. Native clips are not decimated; their seeded runs
# differ only by lasR's own nondeterminism, and the cached native rows also
# carry the old multi-threaded normalization, so they must agree within 0.01
# or the same prediction bound, whichever is wider. The historical sweep dropped random cells (lasR failures in
# forked workers), so every run is cut to the cells all runs share before
# pooling, and the dropped cells are reported; every plot must carry the same
# stems in every run.
#   Rscript scripts/check_frozen_ladder.R [SITES=SJER,SOAP,TEAK]
#     [FROZEN=sweep_results_frozen_all_mapped.csv] [SALTS=1,...,10]
#     [NOISE_ROOT=$CLAUDE_JOB_DIR/neon/frozen_2021_noise] [OUT=...]
# Inputs per site: <nd>/sweep_results.csv (cached), <nd>/<FROZEN> and
# <NOISE_ROOT>/salt_<k>/<SITE>_sweep_results.csv (run_sweep.R POP=all_mapped).
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d <- .job_dir()
SITES  <- split_arg(A$SITES, "SJER,SOAP,TEAK")
FROZEN <- if (is.null(A$FROZEN)) "sweep_results_frozen_all_mapped.csv" else A$FROZEN
SALTS  <- as.integer(split_arg(A$SALTS, paste(1:10, collapse = ",")))
NOISE  <- if (is.null(A$NOISE_ROOT)) file.path(d, "neon", "frozen_2021_noise") else A$NOISE_ROOT
OUT    <- if (is.null(A$OUT)) file.path(d, "neon", "frozen_2021_check") else A$OUT
RUNGS  <- c("native", "8", "4", "2", "1")
METRICS <- c("recall", "precision", "F1")
NATIVE_TOL <- 0.01
T_BOUND <- qt(0.995, df = length(SALTS))     # n = SALTS + the frozen run

# Two CHM-VWF configurations: the headline (res 0.5 m, a 0.10) and the
# density-derived res (0.25 m at >= 8 first returns per m2, else 0.5 m).
# run_sweep.R emits 0.25 m rows only for cells at >= 8 first returns per m2
# (unrounded), so the density-derived res is read from the rows a cell has,
# not from the rounded frdens column.
CONFIGS <- list(
  headline = function(x) x$chm_res == 0.5 & x$vwf_a == 0.10,
  density_res = function(x) {
    fine <- paste(x$plot, x$rung) %in% unique(paste(x$plot, x$rung)[x$chm_res == 0.25])
    x$vwf_a == 0.10 & x$chm_res == ifelse(fine, 0.25, 0.5)
  })

pool_rows <- function(x) {
  tp_core <- round(x$precision * x$n_det)
  recall <- sum(x$TP) / sum(x$n_ref)
  precision <- if (sum(x$n_det) > 0) sum(tp_core, na.rm = TRUE) / sum(x$n_det) else NA_real_
  data.frame(n_plots = length(unique(x$plot)), n_ref = sum(x$n_ref), n_det = sum(x$n_det),
             recall = recall, precision = precision,
             F1 = if (!is.na(precision) && recall + precision > 0)
               2 * recall * precision / (recall + precision) else NA_real_)
}
pooled <- function(df, source, site) {
  do.call(rbind, lapply(names(CONFIGS), function(cf) {
    s <- df[CONFIGS[[cf]](df), , drop = FALSE]
    do.call(rbind, lapply(RUNGS, function(r) {
      x <- s[s$rung == r, , drop = FALSE]
      if (!nrow(x)) return(NULL)
      data.frame(site = site, config = cf, rung = r, source = source, pool_rows(x))
    }))
  }))
}
read_run <- function(path) {
  if (!file.exists(path)) stop("Missing sweep output: ", path)
  x <- read.csv(path, stringsAsFactors = FALSE); x$rung <- as.character(x$rung); x
}

runs <- list(); cells <- list()
for (site in SITES) {
  nd <- file.path(d, "neon", site)
  src <- c(list(cached = read_run(file.path(nd, "sweep_results.csv")),
                frozen = read_run(file.path(nd, FROZEN))),
           setNames(lapply(SALTS, function(k)
             read_run(file.path(NOISE, paste0("salt_", k), paste0(site, "_sweep_results.csv")))),
             paste0("salt_", SALTS)))
  # Every plot must carry the same stems in every run.
  stems_of <- function(x) unique(paste(x$plot, x$n_ref))
  same_stems <- vapply(src, function(x) all(stems_of(x) %in% stems_of(src$cached)) &&
                         all(stems_of(src$cached) %in% stems_of(x)), logical(1))
  # Cut every run to the (plot, rung, chm_res, vwf_a) cells all runs share.
  cell <- function(x) paste(x$plot, x$rung, x$chm_res, x$vwf_a)
  common <- Reduce(intersect, lapply(src, cell))
  every <- Reduce(union, lapply(src, cell))
  cells[[site]] <- data.frame(site = site, run = names(src), same_stems = same_stems,
                              cells = vapply(src, nrow, integer(1)),
                              missing = vapply(src, function(x)
                                sum(!every %in% cell(x)), integer(1)),
                              union = length(every), common = length(common))
  for (n in names(src)) src[[n]] <- src[[n]][cell(src[[n]]) %in% common, , drop = FALSE]
  pooled_site <- do.call(rbind, lapply(names(src), function(n) pooled(src[[n]], n, site)))
  runs[[site]] <- pooled_site
}
long <- do.call(rbind, runs)
# D17 pooled over sites, by summing the per-site counts.
d17 <- do.call(rbind, lapply(split(long, paste(long$config, long$rung, long$source)), function(x) {
  tp <- x$recall * x$n_ref; tpc <- x$precision * x$n_det
  r <- sum(tp) / sum(x$n_ref); p <- sum(tpc) / sum(x$n_det)
  data.frame(site = "D17", config = x$config[1], rung = x$rung[1], source = x$source[1],
             n_plots = sum(x$n_plots), n_ref = sum(x$n_ref), n_det = sum(x$n_det),
             recall = r, precision = p, F1 = 2 * r * p / (r + p))
}))
long <- rbind(long, d17)

seeded <- c("frozen", paste0("salt_", SALTS))
summ <- do.call(rbind, lapply(split(long, paste(long$site, long$config, long$rung)), function(x) {
  c0 <- x[x$source == "cached", ]; f0 <- x[x$source == "frozen", ]; s <- x[x$source %in% seeded, ]
  row <- data.frame(site = x$site[1], config = x$config[1], rung = x$rung[1],
                    n_plots = c0$n_plots, n_ref = c0$n_ref,
                    same_reference = all(s$n_plots == c0$n_plots & s$n_ref == c0$n_ref),
                    n_seeded = nrow(s))
  for (m in METRICS) {
    mu <- mean(s[[m]]); sdv <- sd(s[[m]])
    row[[paste0(m, "_cached")]] <- c0[[m]]
    row[[paste0(m, "_frozen")]] <- f0[[m]]
    row[[paste0(m, "_mean")]] <- mu
    row[[paste0(m, "_noise_sd")]] <- sdv
    # With no seeded spread, the cached value must equal the seeded one.
    row[[paste0(m, "_z")]] <- if (is.finite(sdv) && sdv > 0)
      (c0[[m]] - mu) / (sdv * sqrt(1 + 1 / nrow(s)))
      else if (isTRUE(all.equal(c0[[m]], mu))) 0 else Inf
  }
  row
}))
summ <- summ[order(summ$config, match(summ$site, c(SITES, "D17")), match(summ$rung, RUNGS)), ]
nat <- summ$rung == "native"
dec <- !nat
zcols <- paste0(METRICS, "_z")
gap <- function(m) abs(summ[[paste0(m, "_cached")]] - summ[[paste0(m, "_mean")]])
bound <- function(m) {
  b <- T_BOUND * summ[[paste0(m, "_noise_sd")]] * sqrt(1 + 1 / summ$n_seeded)
  ifelse(is.finite(b), b, 0)
}
native_ok <- all(vapply(METRICS, function(m)
  all(gap(m)[nat] <= pmax(NATIVE_TOL, bound(m)[nat])), logical(1)))
z_ok <- all(abs(as.matrix(summ[dec, zcols])) <= T_BOUND)
cells <- do.call(rbind, cells)
ref_ok <- all(summ$same_reference) && all(cells$same_stems)

dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
write.csv(long, file.path(OUT, "ladder_pooled_runs.csv"), row.names = FALSE)
write.csv(summ, file.path(OUT, "ladder_check.csv"), row.names = FALSE)
write.csv(cells, file.path(OUT, "ladder_cells.csv"), row.names = FALSE)

fmt <- function(v, k = 2) ifelse(is.na(v), "—", formatC(v, format = "f", digits = k))
zf <- function(v) ifelse(nat, "—", fmt(v, 1))   # native rows are judged by the gap
md <- c(paste("| Config | Site | Rung | Plots | Stems | F1 cached | F1 frozen | F1 seeded mean |",
              "F1 seeded SD | ΔF1 cached − mean | z recall | z precision | z F1 |"),
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        sprintf("| %s | %s | %s | %d | %d | %s | %s | %s | %s | %s | %s | %s | %s |", summ$config,
                summ$site, summ$rung, summ$n_plots, summ$n_ref, fmt(summ$F1_cached, 3),
                fmt(summ$F1_frozen, 3), fmt(summ$F1_mean, 3), fmt(summ$F1_noise_sd, 3),
                sprintf("%+.3f", summ$F1_cached - summ$F1_mean), zf(summ$recall_z),
                zf(summ$precision_z), zf(summ$F1_z)))
writeLines(md, file.path(OUT, "ladder_check.md"))
cat(md, sep = "\n")
print(cells, row.names = FALSE)
cat(sprintf("\nsame plots and stems in every run: %s\n", ref_ok))
cat(sprintf("native rows within max(%.2f, 99%% prediction bound): %s\n", NATIVE_TOL, native_ok))
zd <- abs(as.matrix(summ[dec, zcols]))
cat(sprintf(paste("decimated rows within |z| <= %.2f (t, %d df, 99%%): %s (max |z| %.2f;",
                  "%d of %d metric cells beyond the 95%% bound %.2f)\n"),
            T_BOUND, length(SALTS), z_ok, max(zd, na.rm = TRUE),
            sum(zd > qt(0.975, length(SALTS)), na.rm = TRUE), sum(is.finite(zd)),
            qt(0.975, length(SALTS))))
cat(sprintf("VERDICT: %s\n", if (ref_ok && native_ok && z_ok) "PASS" else "FAIL"))
