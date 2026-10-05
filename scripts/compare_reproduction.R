#!/usr/bin/env Rscript
# Compares the outputs reproduce_paper_tables.sh rebuilt with the archived
# copies. Every path listed in PATHS (relative to both roots; a directory
# stands for every file under it) is matched file by file:
#   identical  byte-for-byte equal
#   equal      CSV/JSON/GeoJSON with the same structure and text values, and
#              numbers within a relative tolerance of TOL (default 1e-8);
#              CSV rows are compared after sorting, as parallel steps may
#              write them in a different order
#   differs    anything else, with the first difference found
#   missing    archived but not rebuilt; extra: rebuilt but not archived
# Absolute paths inside tables are compared from the first archive top-level
# directory they name, so the archive's original location does not matter.
#   Rscript scripts/compare_reproduction.R ARCHIVE=<dir> OUT=<dir> PATHS=<file>
#     [REPORT=<csv>] [TOL=1e-8]
# Exits 1 when any file differs, is missing or is extra.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
for (k in c("ARCHIVE", "OUT", "PATHS")) if (is.null(A[[k]])) stop(k, "= is required")
TOL <- if (is.null(A$TOL)) 1e-8 else as.numeric(A$TOL)
TOPS <- list.dirs(A$ARCHIVE, recursive = FALSE, full.names = FALSE)

files_under <- function(root, rel) {
  p <- file.path(root, rel)
  if (dir.exists(p)) file.path(rel, list.files(p, recursive = TRUE, all.files = TRUE))
  else if (file.exists(p)) rel else character()
}

# "/any/prefix/paper_runs/neon/SJER/x.csv" -> "paper_runs/neon/SJER/x.csv"
strip_root <- function(x) {
  pat <- paste0("^/.*?/((", paste(TOPS, collapse = "|"), ")/)")
  ifelse(!is.na(x) & startsWith(x, "/"), sub(pat, "\\1", x, perl = TRUE), x)
}

num_diff <- function(a, b) {
  if (!identical(is.na(a), is.na(b))) return("missing values differ")
  ok <- !is.na(a)
  rel <- abs(a[ok] - b[ok]) / pmax(1, abs(a[ok]))
  if (length(rel) && max(rel) > TOL) sprintf("max relative difference %.3g", max(rel)) else ""
}

compare_csv <- function(fa, fb) {
  a <- read.csv(fa, stringsAsFactors = FALSE, check.names = FALSE)
  b <- read.csv(fb, stringsAsFactors = FALSE, check.names = FALSE)
  if (!identical(names(a), names(b))) return("columns differ")
  if (nrow(a) != nrow(b)) return(sprintf("%d rows archived, %d rebuilt", nrow(a), nrow(b)))
  if (!nrow(a)) return("")
  for (j in seq_along(a)) if (is.character(a[[j]])) {
    a[[j]] <- strip_root(a[[j]]); b[[j]] <- strip_root(b[[j]])
  }
  key <- function(x) do.call(order, c(unname(lapply(x, function(v)
    if (is.numeric(v)) signif(v, 6) else v)), list(na.last = TRUE)))
  a <- a[key(a), , drop = FALSE]; b <- b[key(b), , drop = FALSE]
  for (j in names(a)) {
    if (is.numeric(a[[j]]) && is.numeric(b[[j]])) {
      d <- num_diff(a[[j]], b[[j]])
      if (nzchar(d)) return(paste0(j, ": ", d))
    } else if (!identical(as.character(a[[j]]), as.character(b[[j]]))) {
      i <- which(as.character(a[[j]]) != as.character(b[[j]]) |
                   xor(is.na(a[[j]]), is.na(b[[j]])))[1]
      return(sprintf("%s: row %d '%s' vs '%s'", j, i, a[[j]][i], b[[j]][i]))
    }
  }
  ""
}

compare_json <- function(fa, fb) {
  a <- jsonlite::read_json(fa, simplifyVector = TRUE)
  b <- jsonlite::read_json(fb, simplifyVector = TRUE)
  r <- all.equal(a, b, tolerance = TOL)
  if (isTRUE(r)) "" else paste(head(r, 3), collapse = "; ")
}

compare_file <- function(rel) {
  fa <- file.path(A$ARCHIVE, rel); fb <- file.path(A$OUT, rel)
  if (!file.exists(fb)) return(c("missing", ""))
  if (!file.exists(fa)) return(c("extra", ""))
  if (unname(tools::md5sum(fa)) == unname(tools::md5sum(fb))) return(c("identical", ""))
  ext <- tolower(tools::file_ext(rel))
  d <- tryCatch(switch(ext, csv = compare_csv(fa, fb),
                       json = , geojson = compare_json(fa, fb),
                       "bytes differ"),
                error = function(e) paste("unreadable:", conditionMessage(e)))
  if (nzchar(d)) c("differs", d) else c("equal", "")
}

paths <- readLines(A$PATHS)
rels <- sort(unique(unlist(lapply(paths, function(p)
  c(files_under(A$ARCHIVE, p), files_under(A$OUT, p))))))
res <- do.call(rbind, lapply(rels, function(r) {
  x <- compare_file(r)
  data.frame(path = r, status = x[1], detail = x[2], stringsAsFactors = FALSE)
}))
if (!is.null(A$REPORT)) write.csv(res, A$REPORT, row.names = FALSE)
tab <- table(factor(res$status, c("identical", "equal", "differs", "missing", "extra")))
cat(sprintf("%d files: %s\n", nrow(res), paste(names(tab), tab, sep = " ", collapse = ", ")))
bad <- res[res$status %in% c("differs", "missing", "extra"), , drop = FALSE]
if (nrow(bad)) {
  print(utils::head(bad, 40), row.names = FALSE)
  quit(status = 1)
}
cat("Every rebuilt table matches the archive.\n")
