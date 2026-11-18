#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(lidR); library(parallel) })
options(lidR.progress = FALSE)
source(.find("model_bench_lib.R"))
source(.find("master_tables_lib.R"))
source(.find("core_density_lib.R"))

# First-return and all-return density of the scored area. The clip manifests
# record each clip's density over the whole evaluation clip (nominal plot core
# plus the 25 m buffer); detections are scored inside the nominal core only,
# and thinning leaves the clip's outer cells denser than its interior. For
# every usable cell of the declared population in the sealed roots, this reads
# the normalized clip (frozen_read(): geometry and SHA-256 checked against the
# clip manifest), applies the provider's height filter (Z from -1 to below 80
# m) and counts first returns and all returns inside the nominal core (half
# side 20 m on tower plots, 10 m on distributed plots), in the clip's outer
# 5 m ring and over the whole clip. It stops unless the recomputed whole clip
# is the manifest's in every cell: the same all-return count as manifest.json
# and the same densities to the 15 significant digits both manifests store.
# Read-only on every root.
# The native sparse flights: for the plots of the sparse-epoch comparison
# (compare_sparse_epoch.R, shared stems), the same counts for each sparse
# flight's native clip and the 2021 clips it is compared with.
#   CLAUDE_JOB_DIR=<paper_runs> Rscript scripts/core_density.R [POP=adopted]
#     [FROZEN_ROOT=<root>] [RUNG_ROOTS=<root>,...] [CORES=4] [OUT=<dir>]
#     [EPOCHS=SJER:<sparse job>:2017,SOAP:<sparse job>:2018,...|none]
#     [C21=<2021 comparison job dir>]
# FROZEN_ROOT defaults to <job dir>/neon/frozen_2021 (native and the rungs of
# its freeze contract); RUNG_ROOTS adds roots frozen at other rungs (default
# <job dir>/../neon/frozen_2021_ql2, the QL2 rung), whose native cells repeat
# the main root's and are skipped. EPOCHS and C21 default to the sparse-epoch
# roots beside the job directory, as reproduce_paper_tables.sh step 7 names
# them. Writes to OUT (default <job dir>/core_density): core_density.csv,
# core_density_summary.csv, core_density_sparse_epoch.csv,
# core_density_sparse_epoch_summary.csv and core_density_contract.json.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
KNOWN <- c("POP", "FROZEN_ROOT", "RUNG_ROOTS", "CORES", "OUT", "EPOCHS", "C21")
if (length(setdiff(names(A), KNOWN)))
  stop("Unknown arguments: ", paste(setdiff(names(A), KNOWN), collapse = ", "))
arg <- function(k, default) if (is.null(A[[k]]) || !nzchar(A[[k]])) default else A[[k]]
d     <- .job_dir()
W     <- dirname(d)
POP   <- arg("POP", "adopted")
ROOT  <- frozen_root(d, A[["FROZEN_ROOT"]])
RUNG_ROOTS <- strsplit(arg("RUNG_ROOTS", file.path(W, "neon", "frozen_2021_ql2")), ",", fixed = TRUE)[[1]]
CORES <- as.integer(arg("CORES", 4))
OUT   <- arg("OUT", file.path(d, "core_density"))
EPOCHS <- arg("EPOCHS", paste0("SJER:", file.path(W, "sparse_2017"), ":2017,SOAP:",
                               file.path(W, "sparse_2018"), ":2018,TEAK:",
                               file.path(W, "sparse_2018"), ":2018"))
C21 <- arg("C21", file.path(W, "sparse_compare_2021"))
if (is.na(CORES) || CORES < 1 || CORES > 8) stop("CORES must be 1 to 8")
frozen_population_spec(POP)
SCOPES <- c(list(`five sites` = unlist(MT_REGIONS, use.names = FALSE)), MT_REGIONS,
            setNames(as.list(unlist(MT_REGIONS, use.names = FALSE)), unlist(MT_REGIONS, use.names = FALSE)))
region_of <- function(site) ifelse(site %in% MT_REGIONS$California, "California",
                                   ifelse(site %in% MT_REGIONS$Washington, "Washington", NA_character_))
for (r in c(ROOT, RUNG_ROOTS)) if (!frozen_sealed(r)) stop("No sealed frozen root at ", r)
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
t0 <- Sys.time()

## ---- cells: one per site x plot x rung of the population ------------------------------
pop <- read.csv(file.path(ROOT, "population.csv"), stringsAsFactors = FALSE)
inpop <- pop[pop[[paste0("in_", POP)]], , drop = FALSE]
if (any(inpop$core_half != ifelse(inpop$plotType == "tower", 20, 10)))
  stop("A plot's core half-side does not follow its plot type")
roots <- list(list(root = ROOT, rungs = c("native", as.character(frozen_root_rungs(ROOT)))))
for (r in RUNG_ROOTS) {
  if (!identical(frozen_sha256(file.path(r, "population.csv")), frozen_sha256(file.path(ROOT, "population.csv"))))
    stop("Root ", r, " declares a different population from ", ROOT)
  rr <- as.character(frozen_root_rungs(r))
  if (any(rr %in% roots[[1]]$rungs)) stop("Root ", r, " repeats rungs of ", ROOT)
  roots[[length(roots) + 1]] <- list(root = r, rungs = rr)
}
RUNGS <- unlist(lapply(roots, `[[`, "rungs"))
RUNGS <- c("native", as.character(sort(as.numeric(RUNGS[RUNGS != "native"]), decreasing = TRUE)))
todo <- do.call(rbind, lapply(roots, function(p) {
  cm <- frozen_clip_manifest(p$root)
  cm <- cm[cm$rung %in% p$rungs & paste(cm$site, cm$plot) %in% paste(inpop$site, inpop$plotID), , drop = FALSE]
  if (any(cm$status != "ok"))
    message(sprintf("%s: %d population cells not ok (%s); skipped", p$root, sum(cm$status != "ok"),
                    paste(unique(cm$status[cm$status != "ok"]), collapse = ", ")))
  cm <- cm[cm$status == "ok", , drop = FALSE]
  cm$root <- p$root
  cm$clip_manifest_sha256 <- frozen_root_id(p$root)
  cm
}))
miss <- setdiff(paste(rep(paste(inpop$site, inpop$plotID), each = length(RUNGS)), RUNGS),
                paste(todo$site, todo$plot, todo$rung))
if (length(miss)) stop("Population cells missing from the roots: ", paste(head(miss), collapse = "; "))

# One cell: verified read, the provider's filter, counts. The full-precision
# manifest densities come from the cell's manifest.json (frozen_read()).
read_cell <- function(i, cm) {
  r <- cm[i, ]
  lidR::set_lidr_threads(1L)
  fp <- frozen_read(r$root, r$site, r$plot, r$rung, r$cx, r$cy, r$core_half, r$buffer)
  if (is.null(fp)) stop("Cell is not ok: ", r$site, "/", r$plot, "/", r$rung)
  las <- suppressWarnings(lidR::readLAS(fp$normalized, select = "xyzr"))
  cnt <- cd_counts_las(las, r$cx, r$cy, r$core_half, r$buffer)
  mf <- jsonlite::read_json(fp$manifest, simplifyVector = TRUE)
  cbind(data.frame(site = r$site, plot = r$plot, rung = r$rung, cx = r$cx, cy = r$cy,
                   core_half = r$core_half, buffer = r$buffer, json_n_norm = mf$n_norm,
                   json_pdens = fp$pdens, json_frdens = fp$frdens, stringsAsFactors = FALSE), cnt)
}
read_all <- function(cm) {
  res <- parallel::mclapply(seq_len(nrow(cm)), read_cell, cm = cm, mc.cores = CORES,
                            mc.preschedule = FALSE)
  bad <- vapply(res, function(z) !is.data.frame(z), logical(1))
  if (any(bad)) stop("Failed cells: ", paste(head(vapply(res[bad], function(z) paste(as.character(z), collapse = " "),
                                                         character(1)), 3), collapse = " | "))
  do.call(rbind, res)
}
# The recomputed whole clip must be the manifest's: the all-return count must
# equal manifest.json's n_norm exactly, each recorded density times the
# nominal clip area must round to the recomputed count, and the densities
# must agree to a relative 1e-13. Both manifests store densities to 15
# significant digits (jsonlite digits = NA, write.csv), so exact equality of
# the doubles is not available; 1e-13 is far below one point over a clip
# (1 / 8,100 m² for a tower plot). Returns the largest absolute differences.
check_manifest <- function(x, label) {
  area <- (2 * (x$core_half + x$buffer))^2
  b0 <- which(x$n_all_clip != x$json_n_norm |
                round(x$json_frdens * area) != x$n_fr_clip | round(x$json_pdens * area) != x$n_all_clip |
                round(x$manifest_frdens * area) != x$n_fr_clip |
                round(x$manifest_pdens * area) != x$n_all_clip)
  b1 <- cd_mismatch(x, x$json_frdens, x$json_pdens, tol = 1e-13, relative = TRUE)
  b2 <- cd_mismatch(x, x$manifest_frdens, x$manifest_pdens, tol = 1e-13, relative = TRUE)
  bad <- unique(c(b0, b1, b2))
  if (length(bad)) {
    print(utils::head(x[bad, c("site", "plot", "rung", "json_n_norm", "n_all_clip", "json_frdens",
                               "manifest_frdens", "clip_frdens", "json_pdens", "clip_pdens")], 10))
    stop(label, ": recomputed whole clip differs from the clip manifest in ", length(bad), " cells")
  }
  c(json = max(abs(c(x$clip_frdens - x$json_frdens, x$clip_pdens - x$json_pdens))),
    csv = max(abs(c(x$clip_frdens - x$manifest_frdens, x$clip_pdens - x$manifest_pdens))),
    rel = max(abs(c(x$clip_frdens / x$json_frdens - 1, x$clip_frdens / x$manifest_frdens - 1,
                    x$clip_pdens / x$json_pdens - 1, x$clip_pdens / x$manifest_pdens - 1))))
}

cat(sprintf("reading %d cells of the %s population (%d plots) with %d cores\n", nrow(todo), POP,
            nrow(inpop), CORES))
x <- read_all(todo)
key <- function(z) paste(z$site, z$plot, z$rung)
m <- todo[match(key(x), key(todo)), ]
x$manifest_pdens <- m$pdens; x$manifest_frdens <- m$frdens
x$root <- m$root; x$clip_manifest_sha256 <- m$clip_manifest_sha256
x$normalized_sha256 <- m$normalized_sha256
pp <- inpop[match(paste(x$site, x$plot), paste(inpop$site, inpop$plotID)), ]
x$plot_type <- pp$plotType; x$region <- region_of(x$site)
if (anyNA(x$region)) stop("A site belongs to no region")
if (any(abs(x$core_half - pp$core_half) > 1e-9)) stop("A cell's core differs from its plot's")
diff_main <- check_manifest(x, "frozen roots")
x <- x[order(match(x$site, unlist(MT_REGIONS)), x$plot, match(x$rung, RUNGS)), ]
COLS <- c("site", "plot", "plot_type", "region", "rung", "cx", "cy", "core_half", "buffer",
          "manifest_pdens", "manifest_frdens", "clip_pdens", "clip_frdens", "core_pdens", "core_frdens",
          "ring_pdens", "ring_frdens", "n_all_clip", "n_fr_clip", "n_all_core", "n_fr_core",
          "n_all_ring", "n_fr_ring", "n_dropped_z", "root", "clip_manifest_sha256", "normalized_sha256")
x$root <- basename(normalizePath(x$root))
write.csv(x[COLS], file.path(OUT, "core_density.csv"), row.names = FALSE)
summ <- cd_summary(x, SCOPES, RUNGS)
write.csv(summ, file.path(OUT, "core_density_summary.csv"), row.names = FALSE)
cat(sprintf(paste("checked %d cells: recomputed whole-clip counts equal the manifests; density max |diff|",
                  "%.3g (manifest.json), %.3g (clip_manifest.csv), max relative %.3g\n"),
            nrow(x), diff_main[["json"]], diff_main[["csv"]], diff_main[["rel"]]))
print(summ[summ$scope == "five sites", c("rung", "cells", "core_frdens_median", "clip_frdens_median",
                                          "core_pdens_median", "clip_pdens_median", "ring_pdens_median",
                                          "cores_below_2", "clips_below_2", "cores_below_8",
                                          "clips_below_8", "core_over_clip_median")], digits = 4,
      row.names = FALSE)

## ---- the native sparse flights -----------------------------------------------------------
sparse_rows <- NULL; sparse_summ <- NULL; sparse_inputs <- NULL
if (!identical(EPOCHS, "none")) {
  ep <- do.call(rbind, lapply(strsplit(strsplit(EPOCHS, ",", fixed = TRUE)[[1]], ":", fixed = TRUE),
    function(z) data.frame(site = z[1], job = z[2], year = as.integer(z[3]), stringsAsFactors = FALSE)))
  # The compared plots: those of the shared-stem references, which must agree
  # between the sparse job and the 2021 comparison job.
  cells <- do.call(rbind, lapply(seq_len(nrow(ep)), function(i) {
    s <- ep$site[i]
    sroot <- file.path(ep$job[i], "neon", sprintf("frozen_%d", ep$year[i]))
    if (!frozen_sealed(sroot)) stop("No sealed sparse-epoch root at ", sroot)
    g1 <- read.csv(file.path(ep$job[i], "compare_shared", "neon", s, "ground_truth_stems.csv"),
                   stringsAsFactors = FALSE)
    g2 <- read.csv(file.path(C21, "shared", "neon", s, "ground_truth_stems.csv"), stringsAsFactors = FALSE)
    plots <- sort(unique(g1$plotID))
    if (!setequal(plots, unique(g2$plotID)))
      stop(s, ": the sparse and 2021 shared-stem references cover different plots")
    cs <- frozen_clip_manifest(sroot); c21 <- frozen_clip_manifest(ROOT)
    one <- function(cm, root, rung, cell, year) {
      r <- cm[cm$site == s & cm$plot %in% plots & cm$rung == rung, , drop = FALSE]
      if (nrow(r) != length(plots) || any(r$status != "ok"))
        stop(s, ": not every compared plot has an ok ", cell, " cell in ", root)
      r$root <- root; r$cell <- cell; r$year <- year
      r$clip_manifest_sha256 <- frozen_root_id(root)
      r
    }
    z <- rbind(one(cs, sroot, "native", "sparse native", ep$year[i]),
               one(c21, ROOT, "native", "2021 native", 2021L),
               one(c21, ROOT, "8", "2021 8", 2021L), one(c21, ROOT, "4", "2021 4", 2021L))
    # The cores coincide on every compared plot.
    g <- tapply(seq_len(nrow(z)), z$plot, function(k)
      max(abs(z$cx[k] - z$cx[k[1]]), abs(z$cy[k] - z$cy[k[1]]), abs(z$core_half[k] - z$core_half[k[1]])))
    if (any(g > 1e-6)) stop(s, ": the compared clips do not share one core on every plot")
    z
  }))
  cat(sprintf("sparse-epoch comparison: %d plots, %d cells\n", length(unique(paste(cells$site, cells$plot))),
              nrow(cells)))
  # Rows come back in the order of `cells` (the native cells of the two
  # epochs share site, plot and rung, so they are joined by position).
  y <- read_all(cells)
  if (!identical(paste(y$site, y$plot, y$rung), paste(cells$site, cells$plot, cells$rung)))
    stop("Sparse-epoch rows out of order")
  y$cell <- cells$cell; y$year <- cells$year; y$root <- basename(normalizePath(cells$root))
  y$clip_manifest_sha256 <- cells$clip_manifest_sha256; y$normalized_sha256 <- cells$normalized_sha256
  y$manifest_pdens <- cells$pdens; y$manifest_frdens <- cells$frdens
  y$plot_type <- ifelse(y$core_half == 20, "tower", "distributed")
  diff_sparse <- check_manifest(y, "sparse-epoch comparison")
  y <- y[order(match(y$site, MT_REGIONS$California), y$plot,
               match(y$cell, c("sparse native", "2021 native", "2021 8", "2021 4"))), ]
  sparse_rows <- y[c("site", "plot", "plot_type", "cell", "year", "rung", "cx", "cy", "core_half", "buffer",
                     "manifest_pdens", "manifest_frdens", "clip_pdens", "clip_frdens", "core_pdens",
                     "core_frdens", "ring_pdens", "ring_frdens", "n_all_clip", "n_fr_clip", "n_all_core",
                     "n_fr_core", "n_all_ring", "n_fr_ring", "n_dropped_z", "root", "clip_manifest_sha256",
                     "normalized_sha256")]
  write.csv(sparse_rows, file.path(OUT, "core_density_sparse_epoch.csv"), row.names = FALSE)
  sites <- unique(ep$site)
  sparse_summ <- cd_sparse_summary(sparse_rows, c(list(`all compared plots` = sites),
                                                  setNames(as.list(sites), sites)))
  write.csv(sparse_summ, file.path(OUT, "core_density_sparse_epoch_summary.csv"), row.names = FALSE)
  cat(sprintf("checked %d sparse-epoch cells against their manifests (max |diff| %.3g json, %.3g csv, relative %.3g)\n",
              nrow(y), diff_sparse[["json"]], diff_sparse[["csv"]], diff_sparse[["rel"]]))
  print(sparse_summ, digits = 3, row.names = FALSE)
  sparse_inputs <- unique(data.frame(input = paste("clip_manifest.csv,", basename(normalizePath(cells$root))),
                                     sha256 = cells$clip_manifest_sha256, stringsAsFactors = FALSE))
}

## ---- contract ----------------------------------------------------------------------------
code <- vapply(c("core_density.R", "core_density_lib.R", "model_bench_lib.R"), .find, character(1))
inputs <- unique(rbind(unique(data.frame(input = paste("clip_manifest.csv,", basename(normalizePath(todo$root))),
                                  sha256 = todo$clip_manifest_sha256, stringsAsFactors = FALSE)),
                data.frame(input = "population.csv", sha256 = frozen_sha256(file.path(ROOT, "population.csv")),
                           stringsAsFactors = FALSE),
                sparse_inputs))
rownames(inputs) <- NULL
jsonlite::write_json(list(
  population = POP, rungs = RUNGS, cells = nrow(x),
  definition = list(
    core = "nominal plot core: |x - cx| <= core_half and |y - cy| <= core_half (20 m tower, 10 m distributed)",
    clip = "whole evaluation clip: core plus buffer, the area the clip manifest divides by",
    ring = sprintf("outer %g m of the clip", CD_RING),
    height_filter = sprintf("Z >= %g and Z < %g on the normalized clip, as the frozen-clip provider", CD_Z_MIN, CD_Z_MAX),
    first_returns = "ReturnNumber == 1"),
  check = list(counts = "all-return count equals manifest.json n_norm; recorded densities x clip area round to the counts",
               relative_tolerance = 1e-13,
               why = "both manifests store densities to 15 significant digits",
               max_abs_diff_json = diff_main[["json"]], max_abs_diff_csv = diff_main[["csv"]],
               max_rel_diff = diff_main[["rel"]],
               sparse_max_rel_diff = if (exists("diff_sparse")) diff_sparse[["rel"]] else NULL),
  inputs = inputs, code_md5 = unname(tools::md5sum(code))),
  file.path(OUT, "core_density_contract.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat(sprintf("wrote %s in %.1f min\n", OUT, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
