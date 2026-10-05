#!/usr/bin/env Rscript
# Rewrites every .rds file under a directory as plain R vectors, in place.
# neonUtilities stores NEON tables through arrow, whose string columns
# serialize as arrow ALTREP objects: they unserialize only where arrow is
# installed and come back as empty vectors elsewhere, with a warning. Every
# object is rebuilt from fresh vectors, checked to be identical to the
# original, and saved.
#   Rscript scripts/portable_rds.R <dir>
dir <- commandArgs(TRUE)[1]
if (is.na(dir) || !dir.exists(dir)) stop("usage: portable_rds.R <dir>")

plain <- function(x) {
  if (is.data.frame(x) || (is.list(x) && is.null(attr(x, "class")))) {
    y <- lapply(x, plain)
    attributes(y) <- attributes(x)
    return(y)
  }
  if (is.atomic(x) && length(x)) {
    y <- vector(typeof(x), length(x))
    y[seq_along(x)] <- x
    attributes(y) <- attributes(x)
    return(y)
  }
  x
}
files <- list.files(dir, pattern = "\\.rds$", recursive = TRUE, full.names = TRUE)
changed <- 0L
for (f in files) {
  x <- readRDS(f)
  y <- plain(x)
  if (!identical(x, y)) stop("Rebuilt object differs from the original: ", f)
  saveRDS(y, f)
  changed <- changed + 1L
}
cat(sprintf("portable_rds: %d .rds files rewritten as plain vectors\n", changed))
