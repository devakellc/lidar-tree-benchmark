#!/usr/bin/env Rscript
.bs_ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (!is.null(.bs_ofile) && length(.bs_ofile) && nzchar(.bs_ofile))
    file.path(dirname(.bs_ofile), "bootstrap.R"),
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])),
                                  "bootstrap.R"),
  file.path("scripts", "bootstrap.R"),
  file.path("..", "..", "scripts", "bootstrap.R"),
  file.path(getwd(), "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found", call. = FALSE)
source(bs[1]); rm(bs, .bs_ofile, .bs_file)

# Freeze of the NEWFOR study areas for the Alpine validation of the gated
# multichm arm (docs/newfor-validation-protocol.md, sections Inputs, Reference,
# Registration diagnostic and Admission). Score-blind: no detector runs here.
#
# Every study area of META (or those of AREAS=) is frozen, in id order and on
# one lidR thread, into a new root OUT through newfor_freeze_area()
# (newfor_lib.R holds the clip, the reference flags, the densities, the
# registration diagnostic, the admission rules and the area folder's layout).
# The raw files of those areas are verified against FILES first. An area whose
# files fail is still frozen as usual when its cloud, terrain raster and
# shapefiles can be read (its admission row then fails rule_files); when they
# cannot, it gets an admission row without a clip (rule_files and the rules
# that need a clip fail; the reference counts are given when its shapefiles
# can be read), no area folder and no registration_scan.csv rows, and freeze.json
# names it under areas_not_frozen with the error (RAW written as <RAW>). An
# area whose files verify but which cannot be frozen stops the run before the
# root is sealed.
#
# The root, beside the area folders:
#   admission.csv          one newfor_admission() row per area, in id order
#   registration_scan.csv  area, dx, dy, stat: every lattice offset of every
#                          frozen area's registration scan
#   freeze.json            the run record: release doi and version; sha256 of
#                          META, FILES and PROTOCOL; code_sha256, the sha256 of
#                          every R file the freeze sources, directly or through
#                          another file, by base name in the order the freeze
#                          first sources them (.FREEZE_CODE: freeze_newfor.R,
#                          bootstrap.R, repo_paths.R, model_bench_lib.R,
#                          neon_spatial_lib.R, neon_reference_support_lib.R,
#                          site_extension_lib.R, newfor_lib.R; one that cannot
#                          be found stops the freeze before anything is
#                          written); versions of R, lidR, terra, sf and sf's
#                          GEOS, GDAL and PROJ; lidr_threads; every NEWFOR_*
#                          constant of the library; the areas asked for, those
#                          frozen and those not frozen. It holds no time, no
#                          path and no git commit (code_sha256 identifies the R
#                          code, versions the packages), so two freezes of the
#                          same input with the same code and package versions
#                          give the same bytes, whichever commit is checked out.
#   freeze_manifest.csv    written last by newfor_seal(): it seals the root
# The root's identity is the sha256 of freeze_manifest.csv (newfor_root_id).
# OUT must not exist or be an empty folder: a new freeze goes to a new root.
# The start time and the duration are printed, not recorded.
#
# Usage:
#   Rscript scripts/freeze_newfor.R [RAW=<dir>] [OUT=<root>] [AREAS=ALL|01,02]
#       [META=<json>] [FILES=<json>] [PROTOCOL=<md>]
# Defaults: RAW = $CLAUDE_JOB_DIR/external/newfor/raw,
#           OUT = $CLAUDE_JOB_DIR/newfor/frozen_v1, AREAS = ALL,
#           META = docs/newfor-area-metadata.json,
#           FILES = docs/newfor-release-files.json,
#           PROTOCOL = docs/newfor-validation-protocol.md (of the repository).
suppressMessages({ library(lidR); library(sf); library(terra); library(data.table)
                   library(jsonlite) })
options(lidR.progress = FALSE)
source(.find("model_bench_lib.R"))   # frozen_canonical, frozen_sha256, FROZEN_POINT_ORDER
source(.find("newfor_lib.R"))        # newfor_* (the freeze, the seal, the admission rules)

.FREEZE_KEYS <- c("RAW", "OUT", "AREAS", "META", "FILES", "PROTOCOL")
# The R files the freeze runs, by base name, in the order it first sources
# them (depth first): this script; bootstrap.R and the repo_paths.R it
# sources; model_bench_lib.R and the neon_spatial_lib.R,
# neon_reference_support_lib.R and site_extension_lib.R it sources;
# newfor_lib.R. freeze.json's code_sha256 holds the SHA-256 of each.
# tests/testthat/test-newfor-detect.R checks the list against the source() calls.
.FREEZE_CODE <- c("freeze_newfor.R", "bootstrap.R", "repo_paths.R", "model_bench_lib.R",
                  "neon_spatial_lib.R", "neon_reference_support_lib.R", "site_extension_lib.R",
                  "newfor_lib.R")

# KEY=VALUE arguments as a named list (read with A[["KEY"]]), split at the
# first "=": the rest of the value is kept verbatim, "=" included. An argument
# without "=", or an unknown, repeated or empty key, stops instead of being
# ignored.
.freeze_args <- function(args = commandArgs(TRUE)) {
  if (any(!grepl("=", args, fixed = TRUE)))
    stop("newfor: arguments are KEY=VALUE, not ",
         paste(args[!grepl("=", args, fixed = TRUE)], collapse = " "), call. = FALSE)
  A <- stats::setNames(as.list(sub("^[^=]*=", "", args)), sub("=.*$", "", args))
  bad <- setdiff(names(A), .FREEZE_KEYS)
  if (length(bad)) stop("newfor: unknown argument ", paste0(bad, "=", collapse = " "),
                        "; known: ", paste0(.FREEZE_KEYS, "=", collapse = " "), call. = FALSE)
  if (anyDuplicated(names(A))) stop("newfor: an argument is given twice", call. = FALSE)
  empty <- names(A)[!nzchar(unlist(A))]
  if (length(empty)) stop("newfor: ", paste0(empty, "=", collapse = " "), " needs a value",
                          call. = FALSE)
  A
}

# A file of the repository (docs/...): under .ROOT, else relative to the
# working directory or two levels up (as .find does for scripts).
.freeze_repo_file <- function(rel) {
  hit <- Find(file.exists, c(file.path(.ROOT, rel), rel, file.path("..", "..", rel)))
  if (is.null(hit)) file.path(.ROOT, rel) else hit
}

# The run's inputs from the parsed arguments, defaults filled in.
.freeze_inputs <- function(A) {
  arg <- function(k, default) if (is.null(A[[k]])) default() else A[[k]]
  list(raw = arg("RAW", function() file.path(.job_dir(), "external", "newfor", "raw")),
       out = arg("OUT", function() file.path(.job_dir(), "newfor", "frozen_v1")),
       areas = if (is.null(A[["AREAS"]]) || identical(A[["AREAS"]], "ALL")) NULL else
         trimws(strsplit(A[["AREAS"]], ",", fixed = TRUE)[[1]]),
       meta = arg("META", function() .freeze_repo_file("docs/newfor-area-metadata.json")),
       files = arg("FILES", function() .freeze_repo_file("docs/newfor-release-files.json")),
       protocol = arg("PROTOCOL",
                      function() .freeze_repo_file("docs/newfor-validation-protocol.md")))
}

# Every NEWFOR_* constant of the library, by name in C-locale order.
.freeze_constants <- function() {
  env <- environment(newfor_freeze_area)
  nm <- sort(ls(env, pattern = "^NEWFOR_"), method = "radix")
  Filter(Negate(is.function), mget(nm, envir = env))
}

# An area of the metadata that cannot be frozen: its admission row without a
# clip, with the reference flags when its shapefiles can be read (on the
# polygon as aoi.wkt would store it, as newfor_freeze_area does).
.freeze_unfrozen_row <- function(raw, area, verify) {
  ref <- tryCatch({
    rd <- newfor_read_area(raw, area)
    aoi <- sf::st_as_sfc(sf::st_as_text(rd$aoi, digits = 15), crs = as.integer(area$epsg))
    newfor_reference(rd$ref, aoi, area$caliper_cm)
  }, error = function(e) NULL)
  newfor_admission(area, verify, NULL, NULL, ref, NULL)
}

# Freezes the areas (all of META's when `areas` is NULL) into the new root
# `out`, writes admission.csv, registration_scan.csv and freeze.json, and
# seals it (see the header). Returns list(admission, scan, record, root_id)
# invisibly.
newfor_freeze <- function(raw, out, meta, files, protocol, areas = NULL) {
  for (p in c(meta, files, protocol))
    if (!file.exists(p)) stop("newfor: input not found: ", p, call. = FALSE)
  if (!dir.exists(raw)) stop("newfor: no raw release at ", raw, call. = FALSE)
  if (file.exists(out) && (!dir.exists(out) ||
                           length(list.files(out, all.files = TRUE, no.. = TRUE))))
    stop("newfor: OUT already holds something; a new freeze goes to a new root: ", out,
         call. = FALSE)
  code <- newfor_code_sha256(.FREEZE_CODE, .find)   # a missing file stops before any write
  M <- newfor_metadata(meta)
  pinned <- newfor_release_files(files)
  fj <- jsonlite::read_json(files)
  for (k in c("doi", "version"))
    if (!is.null(fj[[k]]) && !identical(as.character(fj[[k]]), as.character(M$release[[k]])))
      stop(sprintf("newfor: %s gives %s %s, %s gives %s", files, k, fj[[k]], meta,
                   M$release[[k]]), call. = FALSE)
  ids <- sort(M$areas$id, method = "radix")
  if (!is.null(areas)) {
    unknown <- setdiff(areas, ids)
    if (length(unknown) || !length(areas) || anyDuplicated(areas))
      stop("newfor: AREAS= must name distinct areas of ", meta, "; unknown: ",
           paste(unknown, collapse = ", "), "; known: ", paste(ids, collapse = ","),
           call. = FALSE)
    ids <- sort(areas, method = "radix")
  }
  areas_df <- M$areas[match(ids, M$areas$id), , drop = FALSE]
  threads <- lidR::get_lidr_threads()
  lidR::set_lidr_threads(1L)
  on.exit(lidR::set_lidr_threads(threads), add = TRUE)
  t0 <- Sys.time()
  cat(sprintf("newfor: freeze of %d area(s) (%s) started %s\n  raw  %s\n  root %s\n",
              length(ids), paste(ids, collapse = ","), format(t0, "%Y-%m-%d %H:%M:%S %Z"),
              raw, out))

  # The raw files first: those of the areas asked for; a file the pinned list
  # lacks fails.
  need <- unique(unlist(lapply(seq_along(ids), function(i)
    newfor_area_files(ids[i], areas_df$sheet[i]))))
  verify <- newfor_verify_raw(raw, pinned[pinned$filename %in% need, , drop = FALSE])
  v <- verify[match(need, verify$filename), , drop = FALSE]
  ok_file <- stats::setNames(!is.na(v$filename) & v$present & v$bytes_ok & v$md5_ok &
                               v$sha256_ok, need)
  cat(sprintf("newfor: %d of %d raw files verify (size, MD5, SHA-256)%s\n", sum(ok_file),
              length(ok_file), if (all(ok_file)) "" else
                paste0("; failing: ", paste(need[!ok_file], collapse = ", "))))

  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  adm <- list(); scan <- list(); cells <- list(); not_frozen <- list()
  for (i in seq_along(ids)) {
    area <- areas_df[i, , drop = FALSE]
    id <- ids[i]
    files_ok <- all(ok_file[newfor_area_files(id, area$sheet)])
    t1 <- Sys.time()
    r <- tryCatch(newfor_freeze_area(raw, area, pinned, out), error = function(e) e)
    if (inherits(r, "error")) {
      if (files_ok)
        stop(sprintf(paste("newfor: area %s, whose raw files verify, could not be frozen: %s.",
                           "The unsealed root %s is left for inspection; freeze into a new root."),
                     id, conditionMessage(r), out), call. = FALSE)
      msg <- gsub(raw, "<RAW>", conditionMessage(r), fixed = TRUE)
      cat(sprintf("newfor: area %s not frozen (its raw files fail): %s\n", id, msg))
      adm[[id]] <- .freeze_unfrozen_row(raw, area, verify)
      not_frozen[[length(not_frozen) + 1L]] <- list(area = id, error = msg)
      next
    }
    adm[[id]] <- r$admission
    scan[[id]] <- r$scan
    cells[[id]] <- jsonlite::read_json(file.path(out, id, "cell.json"), simplifyVector = TRUE)
    cat(sprintf("newfor: area %s frozen in %.1f s\n", id,
                as.numeric(difftime(Sys.time(), t1, units = "secs"))))
  }
  adm <- do.call(rbind, unname(adm))
  scan <- if (length(scan)) do.call(rbind, unname(scan)) else
    data.frame(area = character(), dx = numeric(), dy = numeric(), stat = numeric())
  rownames(adm) <- NULL; rownames(scan) <- NULL
  utils::write.csv(adm, file.path(out, "admission.csv"), row.names = FALSE)
  utils::write.csv(scan, file.path(out, "registration_scan.csv"), row.names = FALSE)

  ext <- sf::sf_extSoftVersion()
  record <- list(
    release = list(doi = M$release$doi, version = M$release$version),
    meta_sha256 = frozen_sha256(meta), files_sha256 = frozen_sha256(files),
    protocol_sha256 = frozen_sha256(protocol), code_sha256 = as.list(code),
    versions = list(R = paste(R.version$major, R.version$minor, sep = "."),
                    lidR = as.character(utils::packageVersion("lidR")),
                    terra = as.character(utils::packageVersion("terra")),
                    sf = as.character(utils::packageVersion("sf")),
                    GEOS = ext[["GEOS"]], GDAL = ext[["GDAL"]], PROJ = ext[["proj.4"]]),
    lidr_threads = 1L,
    constants = .freeze_constants(),
    areas = I(ids), areas_frozen = I(as.character(names(cells))),
    areas_not_frozen = not_frozen,
    n_admitted = sum(adm$admitted))
  jsonlite::write_json(record, file.path(out, "freeze.json"), auto_unbox = TRUE, pretty = TRUE,
                       digits = NA, na = "null")
  newfor_seal(out)
  root_id <- newfor_root_id(out)

  cat("\nnewfor: admission\n")
  print(adm[, c("area", "forest", "n_rows", "n_inside", "n_primary", "n_inventoried",
                "gap_months", "reach_min", "terrain_na_share", "offset", "admitted", "failed")],
        row.names = FALSE, digits = 4)
  if (length(cells)) {
    cat(paste0("\nnewfor: densities (per m2; clip-wide over covered_area, the kept points' ",
               "convex hull; clip_area is the clip rectangle) and registration\n"))
    dens <- do.call(rbind, lapply(cells, function(c) data.frame(
      area = c$id, pdens_aoi = c$density$pdens_aoi, frdens_aoi = c$density$frdens_aoi,
      clip_area = c$clip_area, covered_area = c$covered_area,
      pdens_clip = c$density$pdens_clip, frdens_clip = c$density$frdens_clip, res = c$res,
      dx = c$registration$dx, dy = c$registration$dy, offset = c$registration$offset,
      stat_zero = c$registration$stat_zero, stat_best = c$registration$stat_best,
      n_dominant = c$registration$n_dominant, stringsAsFactors = FALSE)))
    print(dens, row.names = FALSE, digits = 4)
  }
  cat(sprintf("\nnewfor: %d of %d area(s) admitted; root %s sealed, id %s; %.1f min\n",
              sum(adm$admitted), nrow(adm), out, root_id,
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  invisible(list(admission = adm, scan = scan, record = record, root_id = root_id))
}

run_main <- function() {
  x <- .freeze_inputs(.freeze_args())
  newfor_freeze(normalizePath(x$raw, mustWork = FALSE), normalizePath(x$out, mustWork = FALSE),
                x$meta, x$files, x$protocol, x$areas)
}

if (sys.nframe() == 0L) run_main()
