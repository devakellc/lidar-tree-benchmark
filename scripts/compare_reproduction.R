#!/usr/bin/env Rscript
# Compares the outputs reproduce_paper_tables.sh rebuilt with the archived
# copies. Every path listed in PATHS (relative to both roots; a directory
# stands for every file under it) is matched file by file:
#   identical  byte-for-byte equal
#   equal      CSV/JSON/GeoJSON with the same structure and text values, and
#              numbers within a relative tolerance of TOL (default 1e-8);
#              CSV rows are compared after sorting, as parallel steps may
#              write them in a different order
#   length     equal except for lengths in metres (coordinates, heights,
#              diameters and their errors) within LENGTH_TOL (default
#              0.01 m): lasR's canopy-model maxima vary by about a millimetre
#              from run to run, single-threaded too, which moves apex heights
#              and height errors but has not changed a detection or a match.
#              Counts and rates never get this allowance. Summed crown
#              overlaps measured on that canopy model (iou_sum_*) inherit
#              the same noise and are allowed OVERLAP_TOL (default 0.01).
#   differs    anything else, listing the columns that differ
#   missing    archived but not rebuilt; extra: rebuilt but not archived
# A PATHS line starting with "~" marks intermediate outputs (the re-detected
# treetop caches, the native QL2 cross-check's per-plot rows and the figure
# images; reproduce_paper_tables.sh says why): they are compared and reported,
# and a difference there is reported as "intermediate" without failing the
# run. The tables built from them are compared under the rules above.
# Absolute paths inside tables are compared from the first archive top-level
# directory they name, so the archive's original location does not matter.
#   Rscript scripts/compare_reproduction.R ARCHIVE=<dir> OUT=<dir> PATHS=<file>
#     [REPORT=<csv>] [TOL=1e-8] [LENGTH_TOL=0.01] [OVERLAP_TOL=0.01]
# Exits 1 when any file differs, is missing or is extra.
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
for (k in c("ARCHIVE", "OUT", "PATHS")) if (is.null(A[[k]])) stop(k, "= is required")
TOL <- if (is.null(A$TOL)) 1e-8 else as.numeric(A$TOL)
LENGTH_TOL <- if (is.null(A$LENGTH_TOL)) 0.01 else as.numeric(A$LENGTH_TOL)
OVERLAP_TOL <- if (is.null(A$OVERLAP_TOL)) 0.01 else as.numeric(A$OVERLAP_TOL)
# Columns holding lengths in metres; everything else (counts, rates, scores)
# must match within TOL.
LENGTH_COL <- "^(x|y|z|X|Y|Z)$|height|_h$|^h_|rmse|bias|mae|diam|d_eq|d_caliper|_m$"
OVERLAP_COL <- "^iou_sum_"
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

# "" when equal within TOL, "length <diff>" when a length column is within
# LENGTH_TOL, else a description.
num_diff <- function(a, b, name) {
  if (!identical(is.na(a), is.na(b))) return("missing values differ")
  ok <- !is.na(a)
  rel <- abs(a[ok] - b[ok]) / pmax(1, abs(a[ok]))
  if (!length(rel) || max(rel) <= TOL) return("")
  ab <- max(abs(a[ok] - b[ok]))
  if (grepl(LENGTH_COL, name) && ab <= LENGTH_TOL) return(sprintf("length %.2g m", ab))
  if (grepl(OVERLAP_COL, name) && ab <= OVERLAP_TOL) return(sprintf("length %.2g IoU", ab))
  sprintf("max difference %.3g (relative %.3g)", ab, max(rel))
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
  out <- character(); len <- character()
  for (j in names(a)) {
    if (is.numeric(a[[j]]) && is.numeric(b[[j]])) {
      d <- num_diff(a[[j]], b[[j]], j)
      if (startsWith(d, "length ")) len <- c(len, paste(j, sub("^length ", "", d)))
      else if (nzchar(d)) out <- c(out, paste0(j, ": ", d))
    } else if (!identical(as.character(a[[j]]), as.character(b[[j]]))) {
      i <- which(as.character(a[[j]]) != as.character(b[[j]]) |
                   xor(is.na(a[[j]]), is.na(b[[j]])))[1]
      out <- c(out, sprintf("%s: row %d '%s' vs '%s'", j, i, a[[j]][i], b[[j]][i]))
    }
  }
  if (length(out)) paste(out, collapse = "; ")
  else if (length(len)) paste("length:", paste(len, collapse = "; "))
  else ""
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
  if (startsWith(d, "length:")) c("length", sub("^length: ", "", d))
  else if (nzchar(d)) c("differs", d) else c("equal", "")
}

paths <- readLines(A$PATHS)
inter <- startsWith(paths, "~"); paths <- sub("^~", "", paths)
under <- function(ps) sort(unique(unlist(lapply(ps, function(p)
  c(files_under(A$ARCHIVE, p), files_under(A$OUT, p))))))
inter_rels <- under(paths[inter])
rels <- under(paths)
res <- do.call(rbind, lapply(rels, function(r) {
  x <- compare_file(r)
  if (r %in% inter_rels && x[1] %in% c("differs", "length")) x[1] <- "intermediate"
  data.frame(path = r, status = x[1], detail = x[2], stringsAsFactors = FALSE)
}))
if (!is.null(A$REPORT)) write.csv(res, A$REPORT, row.names = FALSE)
tab <- table(factor(res$status, c("identical", "equal", "length", "intermediate", "differs",
                                  "missing", "extra")))
cat(sprintf("%d files: %s\n", nrow(res), paste(names(tab), tab, sep = " ", collapse = ", ")))
bad <- res[res$status %in% c("differs", "missing", "extra"), , drop = FALSE]
if (nrow(bad)) {
  print(utils::head(bad, 40), row.names = FALSE)
  quit(status = 1)
}
cat("Every rebuilt table matches the archive.\n")
