#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(lidR); library(parallel) })
options(lidR.progress = FALSE)
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))

# Declares the plot population and freezes one seeded clip per site x plot x
# density rung, before any arm runs. Every arm then reads this root through
# frozen_scope() / frozen_clip() and never touches the LiDAR tiles, so all
# arms score identical bytes on identical plots. The root holds:
#   population.csv        one row per plot: geometry, core counts, membership
#   population_stems.csv  the scored core reference of each population
#   <SITE>/<plot>/<rung>/ frozen_clip() cells (raw + normalized LAZ, DTM, JSON)
#   clip_manifest.csv     one row per cell with status, densities and SHA-256
#                         of every file; its presence seals the root
#   frozen_record.json    contract, versions and digests of the two tables
# Rungs at or above a plot's native all-return density are recorded as
# "upsampled" and not written, so no reader can score them by accident.
# SEED_SALT draws an independent decimation realization into a separate root,
# for decimation-noise replicates; 0 is the canonical freeze. YEAR is the
# acquisition epoch of the job directory's references and tiles (2021 for the
# benchmark; an earlier epoch freezes into its own job directory and OUT=).
#   Rscript scripts/freeze_clips.R [SITES=SJER,SOAP,TEAK,WREF,ABBY] [CORES=8]
#     [POPULATIONS=adopted,all_mapped,relaxed] [SEED_SALT=0] [YEAR=2021] [OUT=...]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
split_arg <- function(x, default) strsplit(if (is.null(x)) default else x, ",")[[1]]
d <- .job_dir()
SITES <- split_arg(A$SITES, "SJER,SOAP,TEAK,WREF,ABBY")
POPS  <- split_arg(A$POPULATIONS, paste(FROZEN_POPULATIONS$population, collapse = ","))
invisible(lapply(POPS, frozen_population_spec))
CORES <- as.integer(if (is.null(A$CORES)) 8 else A$CORES)
SALT  <- as.integer(if (is.null(A$SEED_SALT)) 0 else A$SEED_SALT)
YEAR  <- neon_year(if (is.null(A$YEAR)) 2021 else A$YEAR)
OUT   <- if (is.null(A$OUT)) frozen_root(d) else A$OUT
if (SALT != 0L && is.null(A$OUT)) stop("SEED_SALT needs its own OUT=; the canonical root is salt 0")
if (YEAR != 2021L && is.null(A$OUT)) stop("YEAR other than 2021 needs its own OUT=")
if (frozen_sealed(OUT)) stop("Frozen root is sealed; use a separate OUT=: ", OUT)

## ---- population ----------------------------------------------------------
field <- function(site) {
  nd <- file.path(d, "neon", site)
  gt <- read.csv(file.path(nd, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
  pc <- read.csv(file.path(nd, "plot_centroids.csv"), stringsAsFactors = FALSE)
  neon_reference_epoch(gt, YEAR)
  live <- ext_live_trees(gt)
  epsg <- neon_validate_inputs(live, pc)
  list(gt = gt, pc = pc, epsg = epsg, nd = nd,
       inputs = file.path(nd, c("ground_truth_stems.csv", "plot_centroids.csv")))
}
population_rows <- function(site, f) {
  invs <- lapply(POPS, function(p) {
    spec <- frozen_population_spec(p)
    inv <- ext_plot_inventory(frozen_reference(f$gt, p), f$pc, spec$min_trees)
    inv$member <- inv$admitted & inv$n_core > 0
    inv
  })
  names(invs) <- POPS
  plots <- sort(unique(unlist(lapply(invs, function(x) x$plotID[x$member]))))
  all <- ext_plot_inventory(f$gt, f$pc, EXT_MIN_TREES)
  all <- all[match(plots, all$plotID), , drop = FALSE]
  out <- data.frame(site = site, plotID = plots, plotType = all$plotType,
                    easting = all$easting, northing = all$northing,
                    core_half = plot_half(all$plotType), epsg = f$epsg,
                    n_live = all$n_live, n_live_dbh10 = all$n_live_dbh10,
                    n_core = all$n_core, n_core_dbh10 = all$n_core_dbh10,
                    stringsAsFactors = FALSE)
  for (p in POPS) out[[paste0("in_", p)]] <- plots %in% invs[[p]]$plotID[invs[[p]]$member]
  out
}
stem_rows <- function(site, f, pop) {
  rows <- lapply(POPS, function(p) {
    plots <- pop[pop[[paste0("in_", p)]], , drop = FALSE]
    inv <- data.frame(plotID = plots$plotID, easting = plots$easting,
                      northing = plots$northing, core_half = plots$core_half, admitted = TRUE)
    cs <- ext_core_stems(frozen_reference(f$gt, p), inv)
    if (!nrow(cs)) return(NULL)
    data.frame(site = site, population = p, plotID = cs$plotID,
               individualID = cs$individualID, crown_class = cs$crown_class,
               stemDiameter = cs$stemDiameter, height = cs$height, E = cs$E, N = cs$N,
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

fields <- setNames(lapply(SITES, field), SITES)
pop <- do.call(rbind, lapply(SITES, function(s) population_rows(s, fields[[s]])))
stems <- do.call(rbind, lapply(SITES, function(s)
  stem_rows(s, fields[[s]], pop[pop$site == s, , drop = FALSE])))

code <- vapply(c("freeze_clips.R", "model_bench_lib.R", "sweep_lib.R", "site_extension_lib.R",
                 "neon_spatial_lib.R"), .find, character(1))
inputs <- unlist(lapply(fields, `[[`, "inputs"), use.names = FALSE)
contract <- list(sites = SITES, populations = FROZEN_POPULATIONS[FROZEN_POPULATIONS$population %in% POPS, ],
                 year = YEAR, rungs = FROZEN_RUNGS, buffer = BUF, seed_salt = SALT,
                 lidr_threads = FROZEN_LIDR_THREADS, point_order = FROZEN_POINT_ORDER,
                 versions = list(R = R.version.string,
                                 lidR = as.character(packageVersion("lidR")),
                                 rlas = as.character(packageVersion("rlas")),
                                 terra = as.character(packageVersion("terra"))),
                 input_md5 = unname(tools::md5sum(inputs)),
                 code_md5 = unname(tools::md5sum(code)))
# Compare the contract as JSON reads it back (named vectors, row names, types).
contract <- jsonlite::fromJSON(jsonlite::toJSON(contract, auto_unbox = TRUE, digits = NA))
neon_check_manifest(file.path(OUT, "freeze_contract.json"), contract,
                    list.files(OUT, recursive = TRUE, full.names = TRUE))
write.csv(pop, file.path(OUT, "population.csv"), row.names = FALSE)
write.csv(stems, file.path(OUT, "population_stems.csv"), row.names = FALSE)

## ---- clips ---------------------------------------------------------------
cell_row <- function(site, ci, rung, status, prep = NULL, native = NULL) {
  data.frame(site = site, plot = ci$plotID, rung = if (is.na(rung)) "native" else as.character(rung),
             status = status, cx = ci$easting, cy = ci$northing, core_half = ci$core_half,
             buffer = BUF, seed = seed_for(site, ci$plotID, rung, SALT), seed_salt = SALT,
             pdens = if (is.null(prep)) NA_real_ else prep$pdens,
             frdens = if (is.null(prep)) NA_real_ else prep$frdens,
             native_pdens = if (is.null(native)) NA_real_ else native$pdens,
             native_frdens = if (is.null(native)) NA_real_ else native$frdens,
             stringsAsFactors = FALSE)
}
freeze_plot <- function(site, ctg, ci) {
  clip <- function(rung) frozen_clip(ctg, site, ci$plotID, rung, ci$easting, ci$northing,
                                     ci$core_half, OUT, BUF, SALT)
  native <- clip(NA)
  rows <- list(cell_row(site, ci, NA, if (is.null(native)) "unusable" else "ok", native, native))
  for (rung in FROZEN_RUNGS) {
    # The sweep's no-upsampling guard, against native all-return density.
    rows[[length(rows) + 1]] <- if (is.null(native)) cell_row(site, ci, rung, "no_native")
      else if (rung >= native$pdens) cell_row(site, ci, rung, "upsampled", native = native)
      else {
        prep <- clip(rung)
        cell_row(site, ci, rung, if (is.null(prep)) "unusable" else "ok", prep, native)
      }
  }
  do.call(rbind, rows)
}

t0 <- Sys.time()
cells <- list(); failed <- character()
for (site in SITES) {
  f <- fields[[site]]
  laz <- list.files(file.path(f$nd, "lidar"), pattern = "\\.laz$", recursive = TRUE,
                    full.names = TRUE)
  ctg <- neon_read_catalog(laz, ext_live_trees(f$gt), f$pc, file.path(f$nd, "lidar"))
  opt_progress(ctg) <- FALSE
  plots <- pop[pop$site == site, , drop = FALSE]
  # Fresh worker processes: forked workers share the parent's GDAL state.
  res <- plot_lapply(seq_len(nrow(plots)), function(i)
    tryCatch(freeze_plot(site, ctg, plots[i, ]),
             error = function(e) structure(conditionMessage(e), class = "freeze_error")),
    mc.cores = CORES)
  bad <- !vapply(res, is.data.frame, logical(1))   # caught errors and dead workers
  for (i in which(bad)) message(sprintf("%s %s failed: %s", site, plots$plotID[i],
                                        paste(format(res[[i]]), collapse = " ")))
  if (any(bad)) failed <- c(failed, paste(site, plots$plotID[bad]))
  cells[[site]] <- do.call(rbind, res[!bad])
  cat(sprintf("[%s] %d plots, %d ok cells (%.1f min)\n", site, nrow(plots),
              sum(cells[[site]]$status == "ok"), as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
if (length(failed)) stop("Not sealing; failed plots: ", paste(failed, collapse = ", "))

cm <- frozen_seal(OUT, do.call(rbind, cells))

digest_of <- function(name) frozen_sha256(file.path(OUT, name))
pop_counts <- do.call(rbind, lapply(POPS, function(p) {
  s <- stems[stems$population == p, , drop = FALSE]
  do.call(rbind, lapply(SITES, function(site) {
    x <- pop[pop$site == site & pop[[paste0("in_", p)]], , drop = FALSE]
    data.frame(population = p, site = site, plots = nrow(x),
               tower = sum(x$plotType == "tower"), distributed = sum(x$plotType == "distributed"),
               core_stems = sum(s$site == site))
  }))
}))
record <- list(contract = contract,
               digests = list(population_csv = digest_of("population.csv"),
                              population_stems_csv = digest_of("population_stems.csv"),
                              clip_manifest_csv = digest_of("clip_manifest.csv")),
               cells = as.list(table(cm$status)),
               populations = pop_counts,
               plots = lapply(setNames(POPS, POPS), function(p)
                 lapply(setNames(SITES, SITES), function(site)
                   pop$plotID[pop$site == site & pop[[paste0("in_", p)]]])))
jsonlite::write_json(record, file.path(OUT, "frozen_record.json"), auto_unbox = TRUE,
                     pretty = TRUE, digits = NA)
print(pop_counts, row.names = FALSE)
print(table(site = cm$site, status = cm$status))
cat(sprintf("sealed %s: %d cells, clip_manifest.csv sha256 %s\n", OUT, nrow(cm),
            record$digests$clip_manifest_csv))
