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

# Download of the NEWFOR benchmark release for the Alpine validation of the
# gated multichm arm (docs/newfor-validation-protocol.md, section Release).
#
# The release is pinned file by file in docs/newfor-release-files.json: the
# repository's file id, size and MD5, and the SHA-256 computed once the MD5
# matched. For each pinned file in that order: a file already in RAW with the
# pinned size, MD5 and SHA-256 is kept (status "present"); otherwise it is
# fetched from the repository's access API
# (https://entrepot.recherche.data.gouv.fr/api/access/datafile/<id>?format=original)
# into <file>.part in the same folder, checked against all three, and only then
# renamed to its own name (status "downloaded"), which replaces a file that
# failed the check. A file gets three attempts. A partial or unverified
# download never sits under the file's own name: the .part file is removed
# after every failed attempt. Requests carry a generic user agent
# ("research-client") and nothing else about the user or the machine.
#
# The manifest <RAW>/../download_manifest.csv (filename, id, bytes, md5,
# sha256, status) is written only when every pinned file verifies, so a
# manifest on disk always describes a complete release; one left by an earlier
# run is removed before any file is checked. When a file still fails after its
# attempts, the run carries on with the other files and then stops naming
# every file that failed and why.
#
# The data are not redistributed by the repository (Etalab Open Licence 2.0).
#
# Usage:
#   Rscript scripts/download_external_newfor.R [RAW=<dir>] [FILES=<json>]
# Defaults: RAW = $CLAUDE_JOB_DIR/external/newfor/raw,
#           FILES = docs/newfor-release-files.json of the repository.
source(.find("model_bench_lib.R"))   # frozen_sha256
source(.find("newfor_lib.R"))        # newfor_release_files, newfor_verify_raw

# The repository's access URL of one file id: the file as deposited.
newfor_download_url <- function(id)
  sprintf("https://entrepot.recherche.data.gouv.fr/api/access/datafile/%s?format=original",
          format(id, scientific = FALSE, trim = TRUE))

# The default fetcher: url to the file dest over HTTPS, following redirects,
# with the generic user agent; stops unless the final status is 200. It stops
# a transfer that stalls (under 1 kB/s for two minutes), not a slow one.
newfor_curl_fetch <- function(url, dest) {
  h <- curl::new_handle(useragent = "research-client", followlocation = TRUE,
                        connecttimeout = 60, low_speed_limit = 1000, low_speed_time = 120)
  r <- curl::curl_fetch_disk(url, dest, handle = h)
  if (!identical(as.integer(r$status_code), 200L))
    stop(sprintf("HTTP status %s", r$status_code), call. = FALSE)
  invisible(dest)
}

# What failed in one newfor_verify_raw() row: "" when the file verifies.
.newfor_dl_problem <- function(v) {
  if (!isTRUE(v$present)) return("absent")
  bad <- c(size = !isTRUE(v$bytes_ok), md5 = !isTRUE(v$md5_ok), sha256 = !isTRUE(v$sha256_ok))
  if (any(bad)) paste(paste(names(bad)[bad], "differ"), collapse = ", ") else ""
}

# One pinned file (a row of newfor_release_files) into raw: fetch(url, dest)
# to <file>.part, verified, then renamed. Returns "" on success, else the last
# attempt's problem.
.newfor_dl_one <- function(raw, row, fetch, attempts, pause) {
  part <- paste0(row$filename, ".part")
  part_path <- file.path(raw, part)
  on.exit(unlink(part_path), add = TRUE)
  problem <- "no attempt"
  for (k in seq_len(attempts)) {
    if (k > 1L && pause > 0) Sys.sleep(pause)
    unlink(part_path)
    got <- tryCatch({ fetch(newfor_download_url(row$id), part_path); "" },
                    error = function(e) paste("fetch failed:", conditionMessage(e)))
    if (!nzchar(got)) {
      check <- row; check$filename <- part
      got <- .newfor_dl_problem(newfor_verify_raw(raw, check))
      if (!nzchar(got)) {
        if (!file.rename(part_path, file.path(raw, row$filename)))
          got <- "could not rename the verified download"
        else return("")
      }
    }
    problem <- got
    message(sprintf("newfor: %s, attempt %d of %d: %s", row$filename, k, attempts, problem))
  }
  problem
}

# Brings raw up to the pinned file list `files` (newfor_release_files) and
# writes the manifest when every file verifies (see the header). fetch(url,
# dest) is the fetcher (newfor_curl_fetch by default; tests inject their own);
# pause: seconds between attempts. Returns the manifest data.frame invisibly;
# stops naming the files that failed.
newfor_download <- function(raw, files, fetch = newfor_curl_fetch, attempts = 3L, pause = 5,
                            manifest = file.path(dirname(raw), "download_manifest.csv")) {
  if (!is.function(fetch)) stop("newfor: fetch must be a function(url, dest)", call. = FALSE)
  if (!nrow(files)) stop("newfor: the pinned file list is empty", call. = FALSE)
  dir.create(raw, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(raw)) stop("newfor: cannot create ", raw, call. = FALSE)
  unlink(manifest)
  v <- newfor_verify_raw(raw, files)
  status <- ifelse(v$present & v$bytes_ok & v$md5_ok & v$sha256_ok, "present", NA_character_)
  problems <- character()
  for (i in which(is.na(status))) {
    row <- files[i, , drop = FALSE]
    p <- .newfor_dl_one(raw, row, fetch, attempts, pause)
    if (nzchar(p)) problems[[row$filename]] <- p else {
      status[i] <- "downloaded"
      cat(sprintf("newfor: %s downloaded and verified\n", row$filename))
    }
  }
  if (length(problems))
    stop(sprintf(paste("newfor: %d of %d pinned files failed after %d attempts each",
                       "(no manifest written): %s"), length(problems), nrow(files), attempts,
                 paste(sprintf("%s (%s)", names(problems), problems), collapse = "; ")),
         call. = FALSE)
  m <- data.frame(filename = files$filename, id = files$id, bytes = files$bytes, md5 = files$md5,
                  sha256 = files$sha256, status = status, stringsAsFactors = FALSE)
  tmp <- paste0(manifest, ".part")
  utils::write.csv(m, tmp, row.names = FALSE)
  if (!file.rename(tmp, manifest)) stop("newfor: cannot write ", manifest, call. = FALSE)
  cat(sprintf("newfor: %d pinned files verified in %s (%d present, %d downloaded); manifest %s\n",
              nrow(m), raw, sum(status == "present"), sum(status == "downloaded"), manifest))
  invisible(m)
}

# KEY=VALUE arguments as a named list (read with A[["KEY"]]), split at the
# first "=": the rest of the value is kept verbatim, "=" included. An argument
# without "=", or an unknown, repeated or empty key, stops instead of being
# ignored.
.newfor_dl_args <- function(args = commandArgs(TRUE)) {
  if (any(!grepl("=", args, fixed = TRUE)))
    stop("newfor: arguments are KEY=VALUE, not ",
         paste(args[!grepl("=", args, fixed = TRUE)], collapse = " "), call. = FALSE)
  A <- stats::setNames(as.list(sub("^[^=]*=", "", args)), sub("=.*$", "", args))
  known <- c("RAW", "FILES")
  bad <- setdiff(names(A), known)
  if (length(bad)) stop("newfor: unknown argument ", paste0(bad, "=", collapse = " "),
                        "; known: ", paste0(known, "=", collapse = " "), call. = FALSE)
  if (anyDuplicated(names(A))) stop("newfor: an argument is given twice", call. = FALSE)
  empty <- names(A)[!nzchar(unlist(A))]
  if (length(empty)) stop("newfor: ", paste0(empty, "=", collapse = " "), " needs a value",
                          call. = FALSE)
  A
}

run_main <- function() {
  A <- .newfor_dl_args()
  raw <- if (is.null(A[["RAW"]])) file.path(.job_dir(), "external", "newfor", "raw") else A[["RAW"]]
  lst <- if (is.null(A[["FILES"]])) file.path(.ROOT, "docs", "newfor-release-files.json") else
    A[["FILES"]]
  raw <- normalizePath(raw, mustWork = FALSE)
  newfor_download(raw, newfor_release_files(lst))
}

if (sys.nframe() == 0L) run_main()
