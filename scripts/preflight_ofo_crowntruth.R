#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages({ library(data.table); library(parallel) })
source(.find("model_bench_lib.R"))
source(.find("ofo_registration_lib.R"))
source(.find("ofo_preflight_lib.R"))     # stage-record writer
source(.find("ofo_reference_lib.R"))     # output-location guard
source(.find("ofo_crowntruth_lib.R"))

# Crown-frame truth of the second Open Forest Observatory preflight
# (docs/ofo-preflight-protocol-2.md, "Crown-frame truth", "Test units" and
# "Pass rule"). Score-blind: no detector runs, nothing is scored, and the
# frozen registration method is not rerun; its estimates come from the first
# protocol's tables.
#   STAGE=fetch     resolves the NeonTreeEvaluation repository's current
#                   commit (gh api .../commits/master; COMMIT=<sha> pins one
#                   instead) and takes, at that commit, every annotation
#                   annotations/<SITE>_<NNN>_<YEAR>.xml of ABBY, WREF, SOAP,
#                   TEAK, SJER and NIWO with its image evaluation/RGB/<id>.tif
#                   and its year's canopy height model
#                   evaluation/CHM/<id>_CHM.tif, plus LICENSE. A file is copied
#                   from the read-only caches <job>/sparse_2018/nte or
#                   <job>/teak-canopy-reference/sources/nte only when its git
#                   blob SHA-1 equals the commit's tree entry (the same bytes,
#                   so the same SHA-256); otherwise it is downloaded from
#                   raw.githubusercontent.com at the commit and checked against
#                   that entry. Writes P2/nte/ and P2/nte/nte_sources.json
#                   (repo, commit, and per file and API response its URL,
#                   retrieval time, bytes and SHA-256).
#   STAGE=truth     the truth of each eligible annotation: benchmark plots of
#                   the sealed root's adopted population (stems from
#                   <job>/neon/<SITE>/ground_truth_stems.csv, the method's
#                   surface from the native 2021 cell through frozen_read();
#                   both read-only, the clip manifest's SHA-256 checked before
#                   and after), and NIWO plots when P2/niwo_units.csv and
#                   P2/niwo/neon/NIWO/ground_truth_stems.csv exist (else NIWO is
#                   skipped). Writes P2/crown_truth.csv, crown_truth_stems.csv,
#                   crown_truth_boxes.csv and crowntruth_truth_record.json.
#   STAGE=evaluate  test units from <job>/ofo/preflight/registration_dev.csv and
#                   registration_confirm.csv (frozen variants, single plots) for
#                   the annotated benchmark plots, plus P2/registration_niwo.csv
#                   when it exists; the pass rule per signal. Writes
#                   P2/crowntruth_units.csv, P2/crowntruth_test.json and
#                   crowntruth_evaluate_record.json. Without NIWO units the
#                   result is provisional: `admitted` holds nulls and the
#                   figures sit under `provisional_admitted`.
# P2 = <job>/ofo/preflight2 (P2=<dir> for trials: under <job>/ofo or outside the
# job directory). Nothing is written under <job>/neon or <job>/ofo/preflight.
# Results do not depend on CORES: every random draw is seeded per plot.
#   Rscript scripts/preflight_ofo_crowntruth.R STAGE=fetch|truth|evaluate [CORES=8] \
#     [COMMIT=<sha>] [P2=<dir>]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
STAGE <- if (is.null(A$STAGE)) "" else A$STAGE
if (!STAGE %in% c("fetch", "truth", "evaluate")) stop("STAGE must be fetch, truth or evaluate")
CORES <- as.integer(if (is.null(A$CORES)) 8 else A$CORES)
d <- .job_dir()
OFO <- file.path(d, "ofo")
PRE <- file.path(OFO, "preflight")
P2 <- if (is.null(A$P2) || !nzchar(A$P2)) file.path(OFO, "preflight2") else A$P2
if (!ofo_output_allowed(P2, d, OFO) || ofo_path_within(ofo_path_resolve(P2),
                                                        ofo_path_resolve(PRE)))
  stop("P2 must lie under <job>/ofo (not in its preflight directory) or outside the job ",
       "directory: ", P2)
NTE <- file.path(P2, "nte")
REPO <- "weecology/NeonTreeEvaluation"
CACHES <- file.path(d, c("sparse_2018/nte", "teak-canopy-reference/sources/nte"))
NIWO_UNITS <- file.path(P2, "niwo_units.csv")
NIWO_STEMS <- file.path(P2, "niwo", "neon", "NIWO", "ground_truth_stems.csv")
NIWO_REG <- file.path(P2, "registration_niwo.csv")
options(lidR.progress = FALSE)

now_utc <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
sha256 <- function(f) digest::digest(file = f, algo = "sha256")
write_json_file <- function(x, path)
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null",
                       null = "null")
# A path as recorded: relative to the job directory when under it.
rel <- function(p) {
  p <- normalizePath(p, mustWork = FALSE)
  root <- paste0(normalizePath(d), "/")
  ifelse(startsWith(p, root), substring(p, nchar(root) + 1L), p)
}
abs_path <- function(p) ifelse(startsWith(p, "/"), p, file.path(d, p))
digests <- function(paths) {
  paths <- unique(paths)
  setNames(as.list(vapply(paths, function(p)
    if (file.exists(p)) sha256(p) else NA_character_, "")), rel(paths))
}
# A stage record (as ofo_stage_record) whose paths are relative to the job
# directory, or absolute outside it: P2 may lie outside for trials.
write_record <- function(stage, inputs, outputs, extra, path)
  ofo_write_record(c(list(stage = stage, created_utc = now_utc(), dir = d, inputs = inputs,
                          outputs = digests(outputs)), extra), path)
stale <- function(record_path) {
  if (!file.exists(record_path)) return(paste(basename(record_path), "is missing"))
  r <- jsonlite::read_json(record_path)
  bad <- names(r$outputs)[vapply(names(r$outputs), function(p) {
    f <- abs_path(p)
    !file.exists(f) || !identical(sha256(f), r$outputs[[p]])
  }, logical(1))]
  if (length(bad)) paste("changed since", r$stage, "wrote them:", paste(bad, collapse = ", "))
  else character()
}

# Runs f over xs in forked workers; a failed worker stops the run.
par_map <- function(xs, f) {
  out <- mclapply(xs, f, mc.cores = CORES, mc.preschedule = FALSE)
  bad <- vapply(out, inherits, logical(1), "try-error")
  if (any(bad)) stop("Worker failed: ", as.character(out[[which(bad)[1]]]))
  out
}

# readLAS writes a progress line to stdout; the NEON clips are read with no
# filter, as the registration stages read them.
read_las <- function(f, select) {
  las <- NULL
  invisible(utils::capture.output(las <- lidR::readLAS(f, select = select)))
  las
}

## ---- STAGE=fetch ------------------------------------------------------------------------------
# One GitHub API response, stored as received and recorded.
gh_api <- function(endpoint, dest) {
  tmp <- paste0(dest, ".part")
  st <- system2("gh", c("api", shQuote(endpoint)), stdout = tmp, stderr = "")
  if (!identical(as.integer(st), 0L) || !file.exists(tmp) || file.size(tmp) == 0) {
    unlink(tmp); stop("gh api ", endpoint, " failed (status ", st, ")")
  }
  file.rename(tmp, dest)
  list(path = basename(dest), url = paste0("https://api.github.com/", endpoint),
       retrieved_utc = now_utc(), bytes = file.size(dest), sha256 = sha256(dest))
}

# Download to a temporary name, then rename: an interrupted run never leaves a
# partial file that a later run would take as complete.
fetch_url <- function(url, dest, tries = 3) {
  tmp <- paste0(dest, ".part")
  for (i in seq_len(tries)) {
    ok <- tryCatch({ curl::curl_download(url, tmp, quiet = TRUE); TRUE },
                   error = function(e) { message("  download failed (", i, "): ",
                                                 conditionMessage(e)); FALSE })
    if (ok) return(tmp)
    Sys.sleep(5 * i)
  }
  unlink(tmp); stop("could not download ", url)
}

nte_sources_path <- function() file.path(NTE, "nte_sources.json")

stage_fetch <- function() {
  dir.create(NTE, recursive = TRUE, showWarnings = FALSE)
  old <- if (file.exists(nte_sources_path())) jsonlite::read_json(nte_sources_path()) else NULL
  responses <- list()
  sha <- A$COMMIT
  fresh <- NULL
  if (is.null(sha) || !nzchar(sha)) {
    # kept aside until checked: a moved master must not replace the recorded response
    fresh <- file.path(NTE, "nte_commit.json.new")
    responses$commit <- gh_api(sprintf("repos/%s/commits/master", REPO), fresh)
    sha <- jsonlite::read_json(fresh)$sha
  }
  if (!grepl("^[0-9a-f]{40}$", sha)) stop("Not a commit SHA: ", sha)
  if (!is.null(old) && !identical(old$commit, sha)) {
    if (!is.null(fresh)) unlink(fresh)
    stop("P2/nte holds files of commit ", old$commit, " but the requested commit is ", sha,
         "; pass COMMIT=", old$commit, " to complete it, or move P2/nte aside")
  }
  if (!is.null(fresh)) {
    file.rename(fresh, file.path(NTE, "nte_commit.json"))
    responses$commit$path <- "nte_commit.json"
  }
  responses$tree <- gh_api(sprintf("repos/%s/git/trees/%s?recursive=1", REPO, sha),
                           file.path(NTE, "nte_tree.json"))
  tree <- jsonlite::fromJSON(file.path(NTE, "nte_tree.json"))
  if (isTRUE(tree$truncated)) stop("The repository tree listing is truncated")
  blobs <- tree$tree[tree$tree$type == "blob", c("path", "sha", "size")]
  ann <- ofo_ct_nte_files(blobs$path)
  want <- c(ann$xml, ann$rgb[ann$has_rgb], ann$chm[ann$has_chm], "LICENSE")
  missing <- c(ann$rgb[!ann$has_rgb], ann$chm[!ann$has_chm],
               if (!"LICENSE" %in% blobs$path) "LICENSE")
  prev <- if (is.null(old)) list() else
    setNames(old$files, vapply(old$files, `[[`, "", "path"))
  message(sprintf("STAGE=fetch: commit %s, %d annotations (%s), %d files", sha, nrow(ann),
                  paste(names(table(ann$site)), table(ann$site), sep = ":", collapse = " "),
                  length(want)))
  files <- lapply(want[want %in% blobs$path], function(p) {
    blob <- blobs$sha[match(p, blobs$path)]
    dest <- file.path(NTE, p)
    url <- sprintf("https://raw.githubusercontent.com/%s/%s/%s", REPO, sha, p)
    if (file.exists(dest) && identical(ofo_git_blob_sha1(dest), blob) && !is.null(prev[[p]]) &&
        identical(prev[[p]]$sha256, sha256(dest)))
      return(prev[[p]])                                 # unchanged: keep its record
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    hit <- Find(function(f) file.exists(f) && identical(ofo_git_blob_sha1(f), blob),
                file.path(CACHES, p))
    if (length(hit)) {
      file.copy(hit, dest, overwrite = TRUE)
      how <- "cache"
    } else {
      tmp <- fetch_url(url, dest)
      if (!identical(ofo_git_blob_sha1(tmp), blob)) {
        unlink(tmp); stop("Downloaded bytes differ from the commit's tree entry: ", p)
      }
      file.rename(tmp, dest)
      how <- "download"
    }
    if (!identical(ofo_git_blob_sha1(dest), blob)) stop("Stored bytes differ from the tree: ", p)
    c(list(path = p, url = url, retrieved_utc = now_utc(), obtained = how,
           bytes = file.size(dest), sha256 = sha256(dest), git_blob_sha1 = blob),
      if (length(hit)) list(cache_path = rel(hit)))
  })
  commit <- if (file.exists(file.path(NTE, "nte_commit.json")))
    jsonlite::read_json(file.path(NTE, "nte_commit.json")) else NULL
  # A run pinned with COMMIT= keeps the commit response of the run that resolved it.
  if (is.null(responses$commit) && !is.null(old$responses$commit))
    responses$commit <- old$responses$commit
  doc <- list(
    repo = REPO, commit = sha,
    commit_date = if (!is.null(commit) && identical(commit$sha, sha))
      commit$commit$committer$date else NA,
    written_utc = now_utc(),
    selection = paste("annotations/<SITE>_<NNN>_<YEAR>.xml for SITE in",
                      paste(OFO_CT$sites, collapse = ", "), "with evaluation/RGB/<id>.tif",
                      "and evaluation/CHM/<id>_CHM.tif, plus LICENSE"),
    reuse = paste("a cached copy is used only when its git blob SHA-1 equals the commit's",
                  "tree entry (identical bytes, hence the pinned file's SHA-256)"),
    responses = responses[intersect(c("commit", "tree"), names(responses))],
    annotations = ann, missing = as.list(missing), files = files)
  write_json_file(doc, nte_sources_path())
  used <- unlist(lapply(files, `[[`, "cache_path"))
  write_record("crowntruth fetch", digests(file.path(d, used)),
               file.path(NTE, c("nte_sources.json", "nte_commit.json", "nte_tree.json")),
               list(nte_commit = sha, note = paste("inputs: the cached files copied; every",
                                                   "network response is in nte_sources.json")),
               file.path(P2, "crowntruth_fetch_record.json"))
  ob <- table(vapply(files, `[[`, "", "obtained"))
  message(sprintf("wrote %s: %d files (%s); missing at the commit: %s", nte_sources_path(),
                  length(files), paste(names(ob), ob, sep = " ", collapse = ", "),
                  if (length(missing)) paste(missing, collapse = ", ") else "none"))
  invisible(doc)
}

## ---- STAGE=truth ------------------------------------------------------------------------------
# The fetched files, each checked against its recorded SHA-256 before use.
read_sources <- function() {
  if (!file.exists(nte_sources_path())) stop("Run STAGE=fetch first: ", nte_sources_path())
  src <- jsonlite::read_json(nte_sources_path())
  files <- rbindlist(lapply(src$files, function(f) f[c("path", "sha256")]))
  ann <- rbindlist(src$annotations)
  for (i in seq_len(nrow(files))) {
    f <- file.path(NTE, files$path[i])
    if (!file.exists(f) || !identical(sha256(f), files$sha256[i]))
      stop("NeonTreeEvaluation file differs from its record: ", files$path[i])
  }
  list(commit = src$commit, files = files, ann = as.data.frame(ann))
}

# Hashes of what <job>/neon holds for this stage, taken before and after it.
neon_digests <- function(root, sites) {
  p <- c(file.path(root, c("clip_manifest.csv", "population.csv")),
         file.path(d, "neon", sites, "ground_truth_stems.csv"))
  digests(p)
}

# NIWO inputs written by the NIWO part of protocol 2, when present.
niwo_inputs <- function() {
  if (!file.exists(NIWO_UNITS) || !file.exists(NIWO_STEMS)) {
    message("NIWO skipped: ", paste(c(NIWO_UNITS, NIWO_STEMS)[!file.exists(
      c(NIWO_UNITS, NIWO_STEMS))], collapse = " and "), " absent")
    return(NULL)
  }
  u <- as.data.frame(fread(NIWO_UNITS, na.strings = ""))
  need <- c("plot", "cx", "cy", "core_half", "epsg", "clip_root", "normalized_laz")
  if (length(setdiff(need, names(u))))
    stop("niwo_units.csv lacks ", paste(setdiff(need, names(u)), collapse = ", "))
  list(units = u, stems = read.csv(NIWO_STEMS, stringsAsFactors = FALSE))
}

# A path written by another stage: absolute, or relative to P2, OFO or the job.
resolve_input <- function(p) {
  if (is.na(p) || !nzchar(p)) return(NA_character_)
  if (startsWith(p, "/")) return(p)
  hit <- Find(file.exists, file.path(c(P2, OFO, d), p))
  if (length(hit)) hit else NA_character_
}

# The normalised clip of a NIWO unit: through frozen_read() when its root is
# sealed (bytes checked against the clip manifest), else the named file.
niwo_clip <- function(u) {
  root <- resolve_input(u$clip_root)
  if (!is.na(root) && frozen_sealed(root)) {
    cell <- frozen_read(root, "NIWO", u$plot, NA, u$cx, u$cy, u$core_half)
    if (is.null(cell)) return(NULL)
    return(cell$normalized)
  }
  p <- resolve_input(u$normalized_laz)
  if (is.na(p) || !file.exists(p)) NULL else p
}

TRUTH_COLS <- c("plot", "site", "annotation", "ann_year", "source", "n_boxes", "n_truth_stems",
                "truth_dx", "truth_dy", "truth_on_edge", "s90_truth_m", "tie_dx", "tie_dy",
                "tie_ncc", "tie_on_edge", "truth_m_dx", "truth_m_dy", "dist_mapped_m",
                "credible", "reason")

# The truth of one annotation. `job` holds the annotation's files, source and
# expected EPSG; `st` the plot's stems; `clip` its normalised clip (or NULL).
truth_plot <- function(job, st, clip) {
  if (!isTRUE(job$has_rgb)) stop(job$annotation, ": the repository holds no image for it")
  rgb <- terra::rast(file.path(NTE, job$rgb))
  e <- as.vector(terra::ext(rgb)); r <- terra::res(rgb)
  code <- terra::crs(rgb, describe = TRUE)$code
  if (!identical(as.character(code), as.character(job$epsg)))
    stop(job$annotation, ": image CRS ", code, " is not EPSG:", job$epsg)
  px <- ofo_ct_read_voc(file.path(NTE, job$xml))
  size_ok <- isTRUE(attr(px, "width") == terra::ncol(rgb)) &&
    isTRUE(attr(px, "height") == terra::nrow(rgb))
  bx <- ofo_ct_boxes_map(px, e[1], e[4], r[1], r[2])
  rule <- ofo_ct_truth_rule(st, e)
  k <- nzchar(rule)
  tr <- ofo_ct_truth(st$E[k], st$N[k], bx, job$plot)
  tie <- list(dx = NA_real_, dy = NA_real_, ncc = NA_real_, on_edge = NA, n_cells = 0L)
  why <- character()
  if (is.null(clip)) why <- "no_clip" else if (!isTRUE(job$has_chm)) why <- "no_chm" else {
    las <- read_las(clip, "xyz")
    lcrs <- lidR::st_crs(las)$epsg
    if (is.finite(lcrs) && !identical(as.character(lcrs), as.character(job$epsg)))
      stop(job$annotation, ": clip CRS ", lcrs, " is not EPSG:", job$epsg)
    S <- ofo_ct_method_surface(las)
    chm <- terra::rast(file.path(NTE, job$chm))
    ccode <- terra::crs(chm, describe = TRUE)$code
    if (!identical(as.character(ccode), as.character(job$epsg)))
      stop(job$annotation, ": CHM CRS ", ccode, " is not EPSG:", job$epsg)
    tie <- ofo_ct_tie(ofo_ct_chm_cells(chm, e), S)
  }
  cr <- ofo_ct_credible(sum(k), tr$on_edge, tr$s90_m, tie$ncc, tie$on_edge)
  tmx <- tr$dx + tie$dx; tmy <- tr$dy + tie$dy
  row <- data.frame(
    plot = job$plot, site = job$site, annotation = job$annotation, ann_year = job$ann_year,
    source = job$source, n_boxes = nrow(bx), n_truth_stems = sum(k), truth_dx = tr$dx,
    truth_dy = tr$dy, truth_on_edge = tr$on_edge, s90_truth_m = tr$s90_m, tie_dx = tie$dx,
    tie_dy = tie$dy, tie_ncc = tie$ncc, tie_on_edge = tie$on_edge, truth_m_dx = tmx,
    truth_m_dy = tmy, dist_mapped_m = sqrt(tmx^2 + tmy^2), credible = cr$credible,
    reason = paste(c(why, if (nzchar(cr$reason)) cr$reason), collapse = ";"),
    # diagnostics, not used by the test
    dist_annotation_m = sqrt(tr$dx^2 + tr$dy^2), truth_objective = tr$objective,
    n_live10_in_image = attr(rule, "n_live10_in_image"), n_by_position = sum(rule == "position"),
    n_by_height = sum(rule == "height"), tallest_live_m = attr(rule, "tallest_live_m"),
    tie_n_cells = tie$n_cells, image_centre_dx = (e[1] + e[2]) / 2 - job$cx,
    image_centre_dy = (e[3] + e[4]) / 2 - job$cy, xml_size_matches_image = size_ok,
    box_names = paste(sort(unique(px$name)), collapse = ";"), epsg = job$epsg,
    clip = if (is.null(clip)) "" else rel(clip), stringsAsFactors = FALSE)
  # rep(): a plot can have no truth stem (NIWO_042 has none of 10 cm or more).
  stems <- data.frame(plot = rep(job$plot, sum(k)), individualID = st$individualID[k], E = st$E[k],
                      N = st$N[k], stemDiameter = st$stemDiameter[k], height = st$height[k],
                      canopyPosition = st$canopyPosition[k], rule = rule[k],
                      stringsAsFactors = FALSE)
  boxes <- cbind(data.frame(plot = rep(job$plot, nrow(px)), box = seq_len(nrow(px))),
                 px[, c("name", "xmin", "ymin", "xmax", "ymax")], bx)
  list(row = row, stems = stems, boxes = boxes,
       inputs = file.path(NTE, c(job$xml, job$rgb, if (isTRUE(job$has_chm)) job$chm)))
}

stage_truth <- function() {
  src <- read_sources()
  root <- frozen_root(d)
  if (!frozen_sealed(root)) stop("No sealed frozen root at ", root)
  sites <- setdiff(OFO_CT$sites, "NIWO")
  before <- neon_digests(root, sites)
  manifest <- frozen_clip_manifest(root)
  pop <- read.csv(file.path(root, "population.csv"), stringsAsFactors = FALSE)
  ann <- src$ann
  ann <- ann[ann$site %in% sites & ann$plot %in% pop$plotID[pop$in_adopted %in% TRUE], ,
             drop = FALSE]
  p <- pop[match(ann$plot, pop$plotID), ]
  bench <- data.frame(ann, source = "benchmark", epsg = p$epsg, cx = p$easting, cy = p$northing,
                      core_half = p$core_half, stringsAsFactors = FALSE)
  gts <- setNames(lapply(sites, function(s)
    read.csv(file.path(d, "neon", s, "ground_truth_stems.csv"), stringsAsFactors = FALSE)),
    sites)
  niwo <- niwo_inputs()
  jobs <- bench
  extra_inputs <- character()
  if (!is.null(niwo)) {
    na <- src$ann[src$ann$site == "NIWO" & src$ann$plot %in% niwo$units$plot, , drop = FALSE]
    u <- niwo$units[match(na$plot, niwo$units$plot), ]
    jobs <- rbind(jobs, data.frame(na, source = "niwo", epsg = u$epsg, cx = u$cx, cy = u$cy,
                                   core_half = u$core_half, stringsAsFactors = FALSE))
    extra_inputs <- c(NIWO_UNITS, NIWO_STEMS)
    nn <- setdiff(niwo$units$plot, na$plot)
    if (length(nn))
      message("NIWO units without an eligible annotation: ", paste(nn, collapse = ","))
  }
  # The protocol gives a plot one truth; two annotation years would give two.
  if (anyDuplicated(jobs$plot))
    stop("A plot has several eligible annotations: ",
         paste(unique(jobs$plot[duplicated(jobs$plot)]), collapse = ","))
  message(sprintf("STAGE=truth: %d benchmark and %d NIWO annotations, %d cores",
                  sum(jobs$source == "benchmark"), sum(jobs$source == "niwo"), CORES))
  out <- par_map(seq_len(nrow(jobs)), function(i) {
    job <- jobs[i, ]
    if (job$source == "benchmark") {
      st <- gts[[job$site]]
      st <- st[st$plotID == job$plot, , drop = FALSE]
      cell <- frozen_read(root, job$site, job$plot, NA, job$cx, job$cy, job$core_half,
                          manifest = manifest)
      clip <- if (is.null(cell)) NULL else cell$normalized
    } else {
      st <- niwo$stems[niwo$stems$plotID == job$plot, , drop = FALSE]
      clip <- niwo_clip(niwo$units[niwo$units$plot == job$plot, ][1, ])
    }
    res <- truth_plot(job, st, clip)
    res$clip <- clip
    res
  })
  after <- neon_digests(root, sites)
  if (!identical(before, after))
    stop("<job>/neon changed during the run: ",
         paste(names(before)[!mapply(identical, before, after)], collapse = ", "))
  tab <- do.call(rbind, lapply(out, `[[`, "row"))
  tab <- tab[order(match(tab$source, c("benchmark", "niwo")), tab$plot), ]
  tab <- tab[, c(TRUTH_COLS, setdiff(names(tab), TRUTH_COLS))]
  stems <- do.call(rbind, lapply(out, `[[`, "stems"))
  boxes <- do.call(rbind, lapply(out, `[[`, "boxes"))
  dir.create(P2, recursive = TRUE, showWarnings = FALSE)
  f_out <- file.path(P2, c("crown_truth.csv", "crown_truth_stems.csv", "crown_truth_boxes.csv"))
  fwrite(tab, f_out[1]); fwrite(stems, f_out[2]); fwrite(boxes, f_out[3])
  clips <- vapply(out, function(x) if (is.null(x$clip)) NA_character_ else x$clip, "")
  niwo_clips <- clips[jobs$source == "niwo" & !is.na(clips)]   # benchmark clips: manifest
  inputs <- c(before, digests(c(nte_sources_path(), unlist(lapply(out, `[[`, "inputs")),
                                extra_inputs, niwo_clips)))
  write_record("crowntruth truth", inputs, f_out, list(
    protocol = "docs/ofo-preflight-protocol-2.md (Crown-frame truth)",
    nte_commit = src$commit, constants = OFO_CT, method_digest = ofo2_config_digest(),
    clip_manifest_sha256 = list(before = before[[rel(file.path(root, "clip_manifest.csv"))]],
                                after = after[[rel(file.path(root, "clip_manifest.csv"))]]),
    neon_unchanged = identical(before, after),
    niwo = if (is.null(niwo)) "skipped: niwo_units.csv or the NIWO stems are absent" else
      sprintf("%d annotated NIWO plots", sum(jobs$source == "niwo"))),
    file.path(P2, "crowntruth_truth_record.json"))
  print_truth(tab)
  invisible(tab)
}

print_truth <- function(tab) {
  cat("\nCrown-frame truth per plot (truth and tie in m; truth_m = truth + tie):\n")
  x <- tab[, c("plot", "source", "n_boxes", "n_truth_stems", "truth_dx", "truth_dy",
               "s90_truth_m", "tie_dx", "tie_dy", "tie_ncc", "truth_m_dx", "truth_m_dy",
               "dist_mapped_m", "credible", "reason")]
  num <- vapply(x, is.numeric, TRUE) & !names(x) %in% c("n_boxes", "n_truth_stems")
  x[num] <- lapply(x[num], round, 2)
  print(x, row.names = FALSE)
  cat(sprintf("\n%d of %d truths credible\n", sum(tab$credible), nrow(tab)))
}

## ---- STAGE=evaluate -----------------------------------------------------------------------------
read_reg <- function(f) {
  if (!file.exists(f)) stop("Missing registration table: ", f)
  as.data.frame(fread(f, na.strings = ""))
}

stage_evaluate <- function() {
  rec <- file.path(P2, "crowntruth_truth_record.json")
  s <- stale(rec)
  if (length(s)) stop("crown_truth.csv is not current (", s, "); rerun STAGE=truth")
  f_truth <- file.path(P2, "crown_truth.csv")
  f_dev <- file.path(PRE, "registration_dev.csv")
  f_con <- file.path(PRE, "registration_confirm.csv")
  has_niwo <- file.exists(NIWO_REG)
  inputs <- digests(c(f_truth, f_dev, f_con, if (has_niwo) NIWO_REG))
  truth <- as.data.frame(fread(f_truth, na.strings = ""))
  truth$reason[is.na(truth$reason)] <- ""
  bt <- truth[truth$source == "benchmark", , drop = FALSE]
  nt <- truth[truth$source == "niwo", , drop = FALSE]
  if (has_niwo && !nrow(nt))
    stop("registration_niwo.csv exists but crown_truth.csv has no NIWO plot; rerun STAGE=truth")
  dev <- read_reg(f_dev); con <- read_reg(f_con)
  u_dev <- ofo_ct_units(dev, "benchmark", "development", bt)
  u_con <- ofo_ct_units(con, "benchmark", "confirmation", bt)
  u_niwo <- if (has_niwo) ofo_ct_units(read_reg(NIWO_REG), "niwo", "niwo", nt)
  units <- rbind(u_dev, u_con, u_niwo)
  # every annotated benchmark plot is one unit of one half, with both signals
  k <- table(factor(units$plot[units$source == "benchmark"], levels = bt$plot))
  if (any(k != 2L)) stop("Benchmark plots without exactly two frozen rows: ",
                         paste(names(k)[k != 2L], collapse = ","))
  if (length(intersect(u_dev$plot, u_con$plot))) stop("A plot is in both halves")
  dropped <- if (has_niwo) {
    nr <- read_reg(NIWO_REG)
    setdiff(unique(nr$unit[nr$frozen_variant %in% TRUE & nr$kind == "plot"]), nt$plot)
  } else character()
  if (length(dropped)) message("NIWO units without a truth row (left out): ",
                               paste(dropped, collapse = ","))
  missing_niwo <- if (has_niwo) setdiff(nt$plot, units$plot[units$source == "niwo"]) else
    nt$plot
  units <- units[order(match(units$source, c("benchmark", "niwo")),
                       match(units$half, c("development", "confirmation", "niwo")),
                       units$plot, match(units$signal, c("height", "rank"))), ]
  units <- units[, c(OFO_CT_UNIT_COLS, setdiff(names(units), OFO_CT_UNIT_COLS))]
  rownames(units) <- NULL
  test <- ofo_ct_test(units)
  final <- has_niwo
  adm <- lapply(test, `[[`, "admitted")
  doc <- list(
    protocol = "docs/ofo-preflight-protocol-2.md (Crown-frame truth, Test units, Pass rule)",
    created_utc = now_utc(),
    status = if (final) "complete" else
      "provisional: P2/registration_niwo.csv is absent, so no NIWO unit is included",
    final = final,
    rule = paste("per signal, over the units with a credible truth, at least the frozen smallest",
                 "stem count and acceptance by the frozen gate: at least 10 units, a median",
                 "error of at most 1.0 m and at least 90% of units within 2.0 m; fewer than 10",
                 "units is inconclusive and the signal is not admitted. Error: the distance",
                 "from the estimate plus the known offset to the truth in the method's frame"),
    method_digest = ofo2_config_digest(),
    signals = test,
    niwo = list(included = has_niwo,
                units = length(unique(units$plot[units$source == "niwo"])),
                truths = nrow(nt), truths_without_units = as.list(missing_niwo),
                units_without_truth = as.list(dropped)),
    truths = list(
      n = nrow(truth), n_credible = sum(truth$credible %in% TRUE),
      not_credible = truth[!truth$credible %in% TRUE, c("plot", "source", "reason")],
      mapped_to_crowns = truth[, c("plot", "source", "credible", "dist_mapped_m",
                                   "dist_annotation_m")],
      note = "distances from mapped stems to annotated crowns: reported, not tested"),
    inputs = inputs,
    # Without NIWO units nothing here is the protocol's admission: null (read
    # as not admitted), the figures over the units present kept apart.
    admitted = if (final) adm else list(height = NA, rank = NA))
  if (!final) doc$provisional_admitted <- adm
  # digests were taken before reading; the tables must not have moved under the run
  if (!identical(inputs, digests(c(f_truth, f_dev, f_con, if (has_niwo) NIWO_REG))))
    stop("An input table changed during the run; rerun STAGE=evaluate")
  f_units <- file.path(P2, "crowntruth_units.csv")
  f_test <- file.path(P2, "crowntruth_test.json")
  fwrite(units, f_units)
  write_json_file(doc, f_test)
  write_record("crowntruth evaluate", inputs, c(f_units, f_test),
               list(method_digest = ofo2_config_digest(), final = final),
               file.path(P2, "crowntruth_evaluate_record.json"))
  print_evaluate(units, test, final)
  invisible(units)
}

print_evaluate <- function(units, test, final) {
  cat("\nTest units (estimate = dx + offset; errors in m):\n")
  x <- units[, c("half", "plot", "signal", "n_signal", "at_min_stems", "accepted", "credible",
                 "est_dx", "est_dy", "truth_m_dx", "truth_m_dy", "error_crown_m",
                 "error_zero_m", "in_test")]
  num <- c("est_dx", "est_dy", "truth_m_dx", "truth_m_dy", "error_crown_m", "error_zero_m")
  x[num] <- lapply(x[num], round, 2)
  print(x, row.names = FALSE)
  cat(sprintf("\nPass rule per signal%s:\n", if (final) "" else
    " (PROVISIONAL: no NIWO units; not the protocol's admission)"))
  for (s in names(test)) with(test[[s]], {
    cat(sprintf(paste("  %-6s units %d, median error %s m, within 2 m %d (%s): %s\n"), s, units,
                if (units) sprintf("%.3f", median_error_m) else "NA", n_within_2m,
                if (units) sprintf("%.1f%%", 100 * share_within_2m) else "NA",
                if (inconclusive) "INCONCLUSIVE" else if (pass) "PASS" else "FAIL"))
    for (k in names(subsets)) with(subsets[[k]], cat(sprintf(
      "      %-24s units %d, median %s m, within 2 m %d\n", k, units,
      if (units) sprintf("%.3f", median_error_m) else "NA", n_within_2m)))
    with(error_zero_same_units, cat(sprintf(
      "      %-24s units %d, median %s m, within 2 m %d\n", "error to zero (protocol 1)",
      units, if (units) sprintf("%.3f", median_error_m) else "NA", n_within_2m)))
  })
}

if (STAGE == "fetch") stage_fetch()
if (STAGE == "truth") stage_truth()
if (STAGE == "evaluate") stage_evaluate()
