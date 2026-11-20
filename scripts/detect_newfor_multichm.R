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

# Detection and scoring of the NEWFOR Alpine validation of the gated multichm
# arm (docs/newfor-validation-protocol.md is the contract; newfor_lib.R holds
# the populations, the polygon scoring and the detection wrapper).
#
# Every area of a sealed freeze root (freeze_newfor.R) is run, admitted or not.
# Its four files are checked against the root's manifest, its clip is prepared
# once with the pinned detector (multichm_gated_lib.R) at the resolution its
# clip-wide first-return density gives (0.25 m at 8 per m2 or more, else 0.5 m),
# and each configuration of newfor_configs() is applied: stock, declared and
# the three that decompose declared. The stock detections are checked against
# lidRplugins::multichm itself on the same clip (a package error is recorded,
# not raised). Detection is sequential, on one lidR thread. Each area is then
# scored for every configuration in four scenarios:
#   primary      primary stems, detections as detected, tolerance 4 m;
#   inventoried  every inventoried stem whatever its diameter, as detected, 4 m;
#   registered   primary stems, detections moved by minus the area's
#                registration estimate (the same as moving stems and polygon by
#                it); an area without an estimate is scored unmoved, 4 m;
#   tol2         primary stems, as detected, 2 m.
# The chance-agreement null of a cell shifts its detections K times within the
# polygon's bounding box widened by the tolerance (newfor_score_cell). The
# shifts depend on the area and that window only, so every configuration of a
# scenario, and every scenario of one tolerance, share them. CORES= scores the
# areas in forked workers (parallel::mclapply); the scores do not depend on it.
# A failed area stops the run: the population is never silently smaller.
#
# The detector is pinned: the run stops before any work unless the git blob of
# multichm_gated_lib.R is the protocol's (NFD_PIN_BLOB) and lidR and
# lidRplugins are the protocol's versions (NFD_PIN_VERSIONS), except with
# ALLOW_UNPINNED=1 (for tests; recorded in run.json). The freeze root must hold
# a freeze.json, sealed with it, that records the SHA-256 of the run's protocol
# file; a root frozen under another protocol is refused, with no override.
# run.json is written before any detection; besides the pins it records the
# SHA-256 of every other R file the run sources, directly or through another
# file (sources, by base name: NFD_SOURCES; one that cannot be found stops the
# run before anything is written), the areas run, every frozen area of the
# root (root_areas), the git commit and whether scripts/, docs/ and tests/ are
# clean (git_clean: NA without git).
# An OUT whose run.json records another protocol, freeze root, detector library
# or configuration set is refused, as is an OUT that holds files but no
# run.json; move it aside to start fresh. A run into an OUT with the same pins
# first removes the earlier run's features.csv, cells.csv, detections/ and
# analysis/. Unknown arguments are refused, so a misspelt FROZEN= cannot fall
# back to the default root.
#
# Usage:
#   Rscript scripts/detect_newfor_multichm.R [FROZEN=<root>] [OUT=<run root>]
#       [AREAS=ALL|01,02] [CORES=1] [PROTOCOL=<md>] [K=200] [ALLOW_UNPINNED=1]
# Defaults: FROZEN=$CLAUDE_JOB_DIR/newfor/frozen_v1,
# OUT=$CLAUDE_JOB_DIR/newfor/multichm_runs and
# PROTOCOL=docs/newfor-validation-protocol.md of the repository.
# Output under OUT:
#   run.json                       pins and constants, written first
#   detections/<area>/<label>.csv  x, y, z of one configuration over the whole
#                                  clip, each number the shortest decimal that
#                                  reads back as the same double
#   features.csv                   one row per area: admission and its stem
#                                  counts, the polygon's and the covered area,
#                                  densities, the stand features, the parity
#                                  check and the registration estimate
#   cells.csv                      one row per area x configuration x scenario
# analyze_newfor_multichm.R pools them into OUT/analysis/.
suppressMessages({ library(lidR); library(lidRplugins); library(sf); library(terra)
                   library(data.table); library(jsonlite); library(parallel) })
options(lidR.progress = FALSE)
d <- .job_dir()
source(.find("sweep_lib.R"))           # score_plot, ws_factory
source(.find("model_bench_lib.R"))     # seed_for, frozen_*, assert_detection_contract
source(.find("multichm_gated_lib.R"))  # the pinned detector, MCG_* constants
source(.find("newfor_lib.R"))          # NEWFOR_* constants, frozen areas, scoring, detection

## ---- pins and constants ------------------------------------------------------------------------
# Git blob of multichm_gated_lib.R and package versions that the protocol pins.
NFD_PIN_BLOB <- "5a83e4afbc2491337e2826800cedcfda38bf85d8"
NFD_PIN_VERSIONS <- c(lidR = "4.3.2", lidRplugins = "0.4.0")
NFD_KEYS <- c("FROZEN", "OUT", "AREAS", "CORES", "PROTOCOL", "K", "ALLOW_UNPINNED")
# The scoring scenarios, in their output order: the stem population, whether
# the detections are moved against the registration estimate, the tolerance.
NFD_SCENARIOS <- data.frame(scenario = c("primary", "inventoried", "registered", "tol2"),
                            population = c("primary", "inventoried", "primary", "primary"),
                            registered = c(FALSE, FALSE, TRUE, FALSE),
                            tol = c(NEWFOR_TOL, NEWFOR_TOL, NEWFOR_TOL, 2),
                            stringsAsFactors = FALSE)
# The R files the run sources other than the pinned library (recorded under
# detector_library), by base name, in the order the run first sources them
# (depth first): this script; bootstrap.R and the repo_paths.R it sources;
# sweep_lib.R and the neon_spatial_lib.R and neon_reference_support_lib.R it
# sources; model_bench_lib.R and the site_extension_lib.R it adds;
# newfor_lib.R. run.json's sources holds the SHA-256 of each.
# tests/testthat/test-newfor-detect.R checks the list against the source() calls.
NFD_SOURCES <- c("detect_newfor_multichm.R", "bootstrap.R", "repo_paths.R", "sweep_lib.R",
                 "neon_spatial_lib.R", "neon_reference_support_lib.R", "model_bench_lib.R",
                 "site_extension_lib.R", "newfor_lib.R")

## ---- arguments ---------------------------------------------------------------------------------
# KEY=VALUE arguments as a named list, split at the first "=" (a path may hold
# one). An argument without "=", without a value, given twice or not in
# NFD_KEYS stops.
nfd_args <- function(x = commandArgs(TRUE)) {
  if (!length(x)) return(list())
  if (any(!grepl("=", x, fixed = TRUE)))
    stop("newfor: arguments are KEY=VALUE, not ", paste(x[!grepl("=", x, fixed = TRUE)],
                                                          collapse = " "), call. = FALSE)
  key <- sub("=.*$", "", x); val <- sub("^[^=]*=", "", x)
  bad <- setdiff(key, NFD_KEYS)
  if (length(bad))
    stop("newfor: unknown argument ", paste0(bad, "=", collapse = " "), " (known: ",
         paste0(NFD_KEYS, "=", collapse = " "), ")", call. = FALSE)
  if (anyDuplicated(key)) stop("newfor: ", key[duplicated(key)][1], "= is given twice",
                               call. = FALSE)
  if (any(!nzchar(val))) stop("newfor: ", key[!nzchar(val)][1], "= needs a value", call. = FALSE)
  stats::setNames(as.list(val), key)
}

# A file of the repository (protocol default): found from the repository root,
# the working directory or tests/testthat.
.nfd_repo_file <- function(rel) {
  hit <- Find(file.exists, c(file.path(.ROOT, rel), rel, file.path("..", "..", rel)))
  if (is.null(hit)) stop("newfor: ", rel, " not found in the repository", call. = FALSE)
  hit
}

# The run's settings from the parsed arguments: frozen, out, protocol (paths),
# areas (NULL = all), cores, K, allow_unpinned.
nfd_options <- function(A) {
  int <- function(key, default, lo) {
    v <- A[[key]]
    if (is.null(v)) return(as.integer(default))
    n <- suppressWarnings(as.numeric(v))
    if (!is.finite(n) || n != round(n) || n < lo || n > .Machine$integer.max)
      stop(sprintf("newfor: %s= must be a whole number of at least %d, not '%s'", key, lo, v),
           call. = FALSE)
    as.integer(n)
  }
  allow <- A[["ALLOW_UNPINNED"]]
  if (!is.null(allow) && !allow %in% c("0", "1"))
    stop("newfor: ALLOW_UNPINNED= must be 0 or 1", call. = FALSE)
  areas <- A[["AREAS"]]
  areas <- if (is.null(areas) || identical(areas, "ALL")) NULL
           else unique(trimws(strsplit(areas, ",", fixed = TRUE)[[1]]))
  if (!is.null(areas) && (!length(areas) || any(!nzchar(areas))))
    stop("newfor: AREAS= is ALL or a comma-separated list of area ids", call. = FALSE)
  list(frozen = if (is.null(A[["FROZEN"]])) file.path(d, "newfor", "frozen_v1") else A[["FROZEN"]],
       out = if (is.null(A[["OUT"]])) file.path(d, "newfor", "multichm_runs") else A[["OUT"]],
       protocol = if (is.null(A[["PROTOCOL"]]))
         .nfd_repo_file(file.path("docs", "newfor-validation-protocol.md")) else A[["PROTOCOL"]],
       areas = areas, cores = int("CORES", 1L, 1L), K = int("K", NEWFOR_NULL_K, 0L),
       allow_unpinned = identical(allow, "1"))
}

## ---- the freeze root ---------------------------------------------------------------------------
# The areas of a sealed root: ids (the area folders its manifest lists, in id
# order), its admission table (admission.csv, checked against the manifest) and
# not_frozen (areas of the admission table without a folder, which cannot be
# run: their cloud could not be read). A frozen area missing from the
# admission table stops.
nfd_frozen_areas <- function(frozen) {
  if (!dir.exists(frozen)) stop("newfor: no freeze root at ", frozen, call. = FALSE)
  if (!newfor_sealed(frozen))
    stop("newfor: the freeze root is not sealed: ", frozen, call. = FALSE)
  m <- utils::read.csv(file.path(frozen, "freeze_manifest.csv"), colClasses = "character")
  ids <- sort(sub("/cell\\.json$", "", grep("^[^/]+/cell\\.json$", m$file, value = TRUE)),
              method = "radix")
  adm <- newfor_frozen_admission(frozen)
  if (anyDuplicated(adm$area)) stop("newfor: admission.csv lists an area twice", call. = FALSE)
  miss <- setdiff(ids, adm$area)
  if (length(miss)) stop("newfor: frozen areas missing from admission.csv: ",
                         paste(miss, collapse = ", "), call. = FALSE)
  if (!length(ids)) stop("newfor: the freeze root holds no area: ", frozen, call. = FALSE)
  list(ids = ids, admission = adm, not_frozen = sort(setdiff(adm$area, ids), method = "radix"))
}

## ---- run record --------------------------------------------------------------------------------
# What `git hash-object` gives for a file without filters: the SHA-1 of
# "blob <bytes>\0" followed by its bytes (no git needed).
nfd_git_blob <- function(path) {
  n <- file.size(path)
  if (is.na(n)) stop("newfor: no file at ", path, call. = FALSE)
  digest::digest(c(charToRaw(sprintf("blob %.0f", n)), as.raw(0L), readBin(path, "raw", n)),
                 algo = "sha1", serialize = FALSE)
}

# The detector library's identity; stops unless its git blob is the pinned one
# or allow_unpinned is TRUE.
nfd_check_pin <- function(lib, allow_unpinned = FALSE, pin = NFD_PIN_BLOB) {
  blob <- nfd_git_blob(lib)
  if (!identical(blob, pin) && !isTRUE(allow_unpinned))
    stop(sprintf(paste0("newfor: the detector pin changed: %s has git blob %s, the protocol pins ",
                        "%s; restore the pinned library (ALLOW_UNPINNED=1 is for tests only)"),
                 lib, blob, pin), call. = FALSE)
  list(file = normalizePath(lib, mustWork = TRUE), sha256 = frozen_sha256(lib), git_blob = blob,
       pinned_blob = pin, pin_matches = identical(blob, pin),
       allow_unpinned = isTRUE(allow_unpinned))
}

# The installed version of a package as a string.
.nfd_installed <- function(pkg) as.character(utils::packageVersion(pkg))

# The packages' versions against the protocol's: list(pinned, installed (both
# named lists), versions_match). Stops naming each package whose installed
# version differs from its pin, unless allow_unpinned is TRUE. installed(pkg)
# gives a package's version (tests inject their own).
nfd_check_versions <- function(allow_unpinned = FALSE, pin = NFD_PIN_VERSIONS,
                               installed = .nfd_installed) {
  got <- vapply(names(pin), function(p) as.character(installed(p)), character(1))
  bad <- names(pin)[got != pin]
  if (length(bad) && !isTRUE(allow_unpinned))
    stop(sprintf(paste0("newfor: the package versions differ from the protocol's: %s; install ",
                        "the pinned versions (ALLOW_UNPINNED=1 is for tests only)"),
                 paste(sprintf("%s is %s, the protocol pins %s", bad, got[bad], pin[bad]),
                       collapse = "; ")), call. = FALSE)
  list(pinned = as.list(pin), installed = as.list(got), versions_match = !length(bad))
}

# The configurations as a table: name, label (mcg_config_label) and fields.
nfd_config_table <- function(configs) {
  fld <- function(k) unname(vapply(configs, function(cfg) as.numeric(cfg[[k]]), numeric(1)))
  data.frame(name = names(configs), label = unname(vapply(configs, mcg_config_label, "")),
             zmin = fld("zmin"), min_share = fld("min_share"), cover_min = fld("cover_min"),
             surface_exempt = unname(vapply(configs, function(cfg) cfg$surface_exempt, TRUE)),
             spacing_min = fld("spacing_min"), stringsAsFactors = FALSE)
}

# Output lines of `git -C root <args>`, or NULL when git fails or is missing.
.nfd_git <- function(args, root = .ROOT) {
  out <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(root), args), stdout = TRUE,
                                           stderr = FALSE)),
                  error = function(e) NULL)
  if (is.null(out) || !is.null(attr(out, "status"))) NULL else out
}

# The repository's commit, NA when git or the repository is unavailable.
.nfd_git_head <- function(root = .ROOT) {
  h <- .nfd_git(c("rev-parse", "HEAD"), root)
  if (length(h) == 1L && grepl("^[0-9a-f]{40}$", h)) h else NA_character_
}

# TRUE when `git status --porcelain -- scripts docs tests` prints nothing (no
# modified, staged or untracked file there), FALSE when it prints something,
# NA when git or the repository is unavailable.
.nfd_git_clean <- function(root = .ROOT) {
  s <- .nfd_git(c("status", "--porcelain", "--", "scripts", "docs", "tests"), root)
  if (is.null(s)) NA else !length(s)
}

# run.json's content. The pin checks run here (the library's git blob, then
# the package versions against pin_versions), before anything is written.
nfd_run_record <- function(o, fz, ids, configs, lib = .find("multichm_gated_lib.R"),
                           pin_versions = NFD_PIN_VERSIONS) {
  if (!file.exists(o$protocol)) stop("newfor: protocol not found: ", o$protocol, call. = FALSE)
  pin <- nfd_check_pin(lib, o$allow_unpinned)
  pv <- nfd_check_versions(o$allow_unpinned, pin_versions)
  src <- newfor_code_sha256(NFD_SOURCES, .find)      # stops when a file is missing
  ver <- function(p) as.character(utils::packageVersion(p))
  list(study = "NEWFOR validation of gated multichm",
       protocol = list(file = normalizePath(o$protocol), sha256 = frozen_sha256(o$protocol)),
       frozen = list(root = normalizePath(o$frozen), root_id = newfor_root_id(o$frozen)),
       detector_library = pin, sources = as.list(src),
       versions = list(R = paste(R.version$major, R.version$minor, sep = "."), lidR = ver("lidR"),
                       lidRplugins = ver("lidRplugins"), terra = ver("terra"), sf = ver("sf"),
                       data.table = ver("data.table")),
       pinned_versions = pv$pinned, versions_match = pv$versions_match,
       configurations = nfd_config_table(configs), a = NEWFOR_A, tol = NEWFOR_TOL, K = o$K,
       null_min_shift = NEWFOR_NULL_MIN_SHIFT, res_gate = NEWFOR_RES_GATE,
       scenarios = NFD_SCENARIOS,
       features = list(radius = MCG_RADIUS, half_dz = MCG_HALF_DZ,
                       cover_height = MCG_COVER_HEIGHT, top_prob = MCG_TOP_PROB,
                       crown_res = MCG_CROWN_RES, crown_ws = MCG_CROWN_WS),
       site = NEWFOR_SITE, areas = I(ids), root_areas = I(fz$ids), not_frozen = I(fz$not_frozen),
       lidr_threads = 1L, git_head = .nfd_git_head(), git_clean = .nfd_git_clean())
}

# Stops unless the freeze root's freeze.json (checked against its manifest)
# records the SHA-256 of the run's protocol file, protocol_sha256.
nfd_check_freeze_protocol <- function(frozen, protocol_sha256) {
  fj <- newfor_frozen_record(frozen)
  got <- fj$protocol_sha256
  got <- if (is.character(got) && length(got) == 1L && !is.na(got)) got else "none"
  if (!identical(got, as.character(protocol_sha256)))
    stop(sprintf(paste0("newfor: the root was frozen under another protocol: its freeze.json ",
                        "records protocol %s, the run's protocol file is %s; freeze a new root ",
                        "under this protocol or run with the protocol it was frozen under"),
                 substr(got, 1, 12), substr(protocol_sha256, 1, 12)), call. = FALSE)
  invisible(TRUE)
}

.nfd_json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA, na = "null")

# Refuses an OUT whose run.json records another protocol, freeze root, detector
# library or configuration set, or that holds files without a run.json.
nfd_check_out <- function(out, record) {
  f <- file.path(out, "run.json")
  if (!file.exists(f)) {
    if (length(list.files(out, all.files = TRUE, no.. = TRUE)))
      stop("newfor: ", out, " holds files but no run.json; move it aside to start fresh",
           call. = FALSE)
    return(invisible(TRUE))
  }
  old <- tryCatch(jsonlite::read_json(f, simplifyVector = TRUE), error = function(e) NULL)
  if (!is.list(old)) stop("newfor: ", f, " cannot be read; move it aside to start fresh",
                          call. = FALSE)
  new <- jsonlite::fromJSON(.nfd_json(record))        # as it reads back from run.json
  same <- function(a, b) isTRUE(all.equal(a, b))
  diff <- c("protocol"[!same(old$protocol$sha256, new$protocol$sha256)],
            "freeze root"[!same(old$frozen$root_id, new$frozen$root_id)],
            "detector library"[!same(old$detector_library[c("sha256", "git_blob")],
                                     new$detector_library[c("sha256", "git_blob")])],
            "configuration set"[!same(old$configurations, new$configurations)])
  if (length(diff))
    stop(sprintf("newfor: %s holds a run with another %s; move it aside to start fresh", out,
                 paste(diff, collapse = ", ")), call. = FALSE)
  invisible(TRUE)
}

## ---- detections --------------------------------------------------------------------------------
# The shortest of 15, 16 or 17 significant digits that reads back as the same
# double.
.nfd_num_text <- function(v) {
  out <- sprintf("%.15g", v)
  for (k in 16:17) {
    redo <- is.finite(v) & suppressWarnings(as.numeric(out)) != v
    redo[is.na(redo)] <- FALSE
    if (!any(redo)) break
    out[redo] <- sprintf(paste0("%.", k, "g"), v[redo])
  }
  out
}

# Writes one detection set (x, y, z) atomically, every number at full precision.
nfd_write_detections <- function(det, file) {
  assert_detection_contract(det)
  lines <- c("x,y,z", if (nrow(det)) paste(.nfd_num_text(det$x), .nfd_num_text(det$y),
                                           .nfd_num_text(det$z), sep = ","))
  tmp <- paste0(file, ".part")
  writeLines(lines, tmp)
  if (!file.rename(tmp, file)) stop("newfor: could not write ", file, call. = FALSE)
  invisible(file)
}

nfd_read_detections <- function(file) {
  x <- utils::read.csv(file, colClasses = "numeric")
  if (!identical(names(x), c("x", "y", "z"))) stop("newfor: ", file, " is not x, y, z",
                                                   call. = FALSE)
  x
}

.nfd_num <- function(v) if (is.null(v) || !length(v)) NA_real_ else as.numeric(v)

# Detects one frozen area with every configuration. adm: the area's row of the
# root's admission table, which must agree with its cell.json. Returns list(id,
# forest, admitted, aoi, stems, det, reg = c(dx, dy, offset), features = one
# row, warnings = lidR's warnings when reading the clip). features: the
# admission row's stem counts and values, aoi_area and the polygon's densities,
# covered_area (the kept points' convex hull, cell.json) and the clip-wide
# densities, newfor_detect's features, the parity check and the registration
# estimate.
nfd_detect_area <- function(frozen, id, adm, configs, a = NEWFOR_A) {
  fa <- newfor_frozen_area(frozen, id, verify = TRUE)
  cell <- fa$cell
  if (nrow(adm) != 1L) stop("newfor: area ", id, " needs one admission row", call. = FALSE)
  if (!identical(as.logical(cell$admission$admitted), adm$admitted) ||
      !identical(as.character(cell$admission$failed), adm$failed))
    stop("newfor: area ", id, ": admission.csv and cell.json disagree", call. = FALSE)
  warns <- character()
  las <- withCallingHandlers(lidR::readLAS(fa$las_file), warning = function(w) {
    warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning")
  })
  if (lidR::is.empty(las)) stop("newfor: the frozen clip of area ", id, " is empty", call. = FALSE)
  dens <- cell$density
  out <- newfor_detect(las, .nfd_num(dens$frdens_clip), configs, a = a, parity = TRUE)
  if (!identical(out$res, .nfd_num(cell$res)))
    stop("newfor: area ", id, ": the resolution differs from the frozen record", call. = FALSE)
  reg <- c(dx = .nfd_num(cell$registration$dx), dy = .nfd_num(cell$registration$dy),
           offset = .nfd_num(cell$registration$offset))
  p <- out$parity
  features <- cbind(
    adm[c("area", "forest", "admitted", "failed", "n_rows", "n_inside", "n_outside", "n_primary",
          "n_inventoried", "n_missing_dbh", "n_below_caliper", "gap_months", "reach_min",
          "terrain_na_share")],
    data.frame(aoi_area = .nfd_num(dens$aoi_area), pdens_aoi = .nfd_num(dens$pdens_aoi),
               frdens_aoi = .nfd_num(dens$frdens_aoi), covered_area = .nfd_num(cell$covered_area),
               pdens_clip = .nfd_num(dens$pdens_clip), frdens_clip = .nfd_num(dens$frdens_clip)),
    out$features,
    data.frame(parity_ok = as.logical(p$ok), parity_n_package = as.integer(p$n_package),
               parity_n_stock = as.integer(p$n_stock), parity_max_abs_diff = p$max_abs_diff,
               parity_error = as.character(p$error), dx = reg[["dx"]], dy = reg[["dy"]],
               offset = reg[["offset"]], stringsAsFactors = FALSE))
  rownames(features) <- NULL
  list(id = id, forest = adm$forest, admitted = adm$admitted, aoi = fa$aoi, stems = fa$stems,
       det = out$det, reg = reg, features = features, warnings = warns)
}

# Detects the areas in order and writes their detections under
# <out>/detections/<area>/<label>.csv. Returns the areas' records.
nfd_detect_all <- function(frozen, ids, admission, configs, out, a = NEWFOR_A) {
  items <- list()
  for (id in ids) {
    t0 <- Sys.time()
    it <- nfd_detect_area(frozen, id, admission[admission$area == id, , drop = FALSE], configs, a)
    dir <- file.path(out, "detections", id)
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    for (nm in names(configs))
      nfd_write_detections(it$det[[nm]], file.path(dir, paste0(mcg_config_label(configs[[nm]]),
                                                               ".csv")))
    f <- it$features
    cat(sprintf(paste("area %s (%s, %s): res %.2f m, cover %.3f, crown spacing %.2f m, gate %s;",
                      "detections %s; parity %s (%.1f s)\n"),
                id, it$forest, if (isTRUE(it$admitted)) "admitted" else "not admitted", f$res,
                f$cover, f$crown_spacing, f$gate_state,
                paste(names(configs), vapply(it$det, nrow, 0L), sep = " ", collapse = ", "),
                if (isTRUE(f$parity_ok)) "ok" else if (is.na(f$parity_ok))
                  paste("not checked:", f$parity_error) else "FAILED",
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    for (w in unique(it$warnings)) cat(sprintf("  area %s: warning reading the clip: %s\n", id, w))
    items[[id]] <- it
  }
  items
}

## ---- scoring -----------------------------------------------------------------------------------
# The move of the detections in a scenario: minus the registration estimate
# when the scenario is registered and the area has one, else none.
nfd_registration_shift <- function(registered, reg) {
  if (!isTRUE(registered) || !is.finite(reg[["dx"]]) || !is.finite(reg[["dy"]])) return(c(0, 0))
  -c(reg[["dx"]], reg[["dy"]])
}

# Every cell of one area: one row per scenario x configuration (scenario order,
# then configuration order), with site, plot, forest, admitted, config (label),
# config_name, scenario, tol, n_apex (every detection on the clip), shift_x and
# shift_y (the move applied to the detections) and the newfor_score_cell
# columns. One set of K null offsets per tolerance (the window depends on it).
nfd_score_area <- function(item, configs, K, scenarios = NFD_SCENARIOS) {
  offsets <- list()
  rows <- list()
  for (i in seq_len(nrow(scenarios))) {
    sc <- scenarios[i, ]
    key <- format(sc$tol, digits = 15)
    if (is.null(offsets[[key]])) {
      win <- newfor_window(item$aoi, sc$tol)
      offsets[[key]] <- newfor_null_offsets(item$id, win$w, win$h, k = K)
    }
    stems <- newfor_stems(item$stems, sc$population)
    shift <- nfd_registration_shift(sc$registered, item$reg)
    for (nm in names(configs)) {
      det <- item$det[[nm]]
      moved <- det
      if (any(shift != 0)) { moved$x <- det$x + shift[1]; moved$y <- det$y + shift[2] }
      rows[[length(rows) + 1L]] <- cbind(
        data.frame(site = NEWFOR_SITE, plot = item$id, forest = item$forest,
                   admitted = item$admitted, config = mcg_config_label(configs[[nm]]),
                   config_name = nm, scenario = sc$scenario, tol = sc$tol, n_apex = nrow(det),
                   shift_x = shift[1], shift_y = shift[2], stringsAsFactors = FALSE),
        newfor_score_cell(stems, moved, item$aoi, item$id, tol = sc$tol,
                          offsets = offsets[[key]]))
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# Scores every area, in forked workers when cores > 1; an area that fails
# stops the run.
nfd_score_all <- function(items, configs, K, cores = 1L) {
  f <- function(it) nfd_score_area(it, configs, K)
  res <- if (cores > 1L && length(items) > 1L)
    parallel::mclapply(items, f, mc.cores = min(cores, length(items)), mc.preschedule = FALSE)
  else lapply(items, function(it) tryCatch(f(it), error = function(e) e))
  bad <- !vapply(res, is.data.frame, logical(1))
  if (any(bad)) {
    why <- vapply(res[bad], function(r)
      if (inherits(r, "condition")) conditionMessage(r)
      else if (inherits(r, "try-error")) conditionMessage(attr(r, "condition"))
      else "the worker returned no result", character(1))
    stop("newfor: scoring failed for area ", paste(names(items)[bad], why, sep = ": ",
                                                   collapse = "; "), call. = FALSE)
  }
  out <- do.call(rbind, unname(res))
  rownames(out) <- NULL
  out
}

# Pooled counts and rates of every configuration over the admitted areas, per
# scenario (sums of counts, mcg_pool).
nfd_print_pooled <- function(cells, configs) {
  adm <- cells[cells$admitted %in% TRUE, , drop = FALSE]
  if (!nrow(adm)) {
    cat("\nno admitted area: nothing to pool\n")
    return(invisible())
  }
  labels <- vapply(configs, mcg_config_label, "")
  for (s in unique(cells$scenario)) {
    P <- mcg_pool(adm[adm$scenario == s, , drop = FALSE], "config")
    P <- P[order(match(P$config, labels)), , drop = FALSE]
    cat(sprintf("\nscenario %s: %d admitted areas, pooled\n", s, P$n_cells[1]))
    print(data.frame(config = names(labels)[match(P$config, labels)], label = P$config,
                     n_ref = P$n_ref, n_det = P$n_det, TP = P$TP, tp_core = P$tp_core,
                     recall = P$recall, precision = P$precision, F1 = P$F1, cF1 = P$cF1),
          row.names = FALSE, digits = 3)
  }
  invisible()
}

.nfd_write_csv <- function(x, path) {
  tmp <- paste0(path, ".part")
  utils::write.csv(x, tmp, row.names = FALSE)
  if (!file.rename(tmp, path)) stop("newfor: could not write ", path, call. = FALSE)
  invisible(path)
}

## ---- main --------------------------------------------------------------------------------------
run_main <- function(A = nfd_args()) {
  o <- nfd_options(A)
  threads <- lidR::get_lidr_threads()
  lidR::set_lidr_threads(1L)
  on.exit(lidR::set_lidr_threads(threads), add = TRUE)
  configs <- newfor_configs()                       # stops when a pinned label changed
  fz <- nfd_frozen_areas(o$frozen)
  ids <- fz$ids
  if (!is.null(o$areas)) {
    miss <- setdiff(o$areas, ids)
    if (length(miss)) stop("newfor: AREAS= names areas that are not frozen in ", o$frozen, ": ",
                           paste(miss, collapse = ", "), call. = FALSE)
    ids <- ids[ids %in% o$areas]
  }
  record <- nfd_run_record(o, fz, ids, configs)    # stops when the detector pins changed
  nfd_check_out(o$out, record)
  nfd_check_freeze_protocol(o$frozen, record$protocol$sha256)
  dir.create(o$out, recursive = TRUE, showWarnings = FALSE)
  # a run with the same pins starts afresh: no result of an earlier run, or of a
  # run that fails part way, is left beside this run.json
  unlink(file.path(o$out, c("features.csv", "cells.csv", "detections", "analysis")),
         recursive = TRUE)
  jsonlite::write_json(record, file.path(o$out, "run.json"), auto_unbox = TRUE, pretty = TRUE,
                       digits = NA, na = "null")
  cat(sprintf("NEWFOR multichm: %d areas (%s) of root %s\n", length(ids),
              paste(ids, collapse = ","), record$frozen$root_id))
  if (length(fz$not_frozen))
    cat("not frozen, so not run:", paste(fz$not_frozen, collapse = ", "), "\n")
  cat(sprintf("detector library blob %s (%s); lidR %s, lidRplugins %s (%s)\n",
              record$detector_library$git_blob,
              if (record$detector_library$pin_matches) "pinned" else "UNPINNED, allowed",
              record$versions$lidR, record$versions$lidRplugins,
              if (record$versions_match) "pinned" else "UNPINNED, allowed"))
  cat(sprintf("configurations %s; K = %d; CORES = %d\n",
              paste(record$configurations$label, collapse = ", "), o$K, o$cores))
  t0 <- Sys.time()
  items <- nfd_detect_all(o$frozen, ids, fz$admission, configs, o$out)
  features <- do.call(rbind, lapply(unname(items), `[[`, "features"))
  .nfd_write_csv(features, file.path(o$out, "features.csv"))
  t1 <- Sys.time()
  cells <- nfd_score_all(items, configs, o$K, o$cores)
  .nfd_write_csv(cells, file.path(o$out, "cells.csv"))
  cat(sprintf("\ndetection %.1f min, scoring %.1f min; %d cells -> %s\n",
              as.numeric(difftime(t1, t0, units = "mins")),
              as.numeric(difftime(Sys.time(), t1, units = "mins")), nrow(cells), o$out))
  failed <- features$area[!features$parity_ok %in% TRUE]
  if (length(failed)) cat("stock parity with lidRplugins::multichm NOT confirmed for:",
                          paste(failed, collapse = ", "), "\n")
  nfd_print_pooled(cells, configs)
  invisible(list(features = features, cells = cells))
}

if (sys.nframe() == 0L) run_main()
