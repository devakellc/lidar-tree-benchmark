#!/usr/bin/env Rscript
# CHM execution and unchanged R scoring for explicitly local development plots.
args <- commandArgs(TRUE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
source(file.path(dirname(script), "repo_paths.R"))
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
source(.find("transfer_audit_lib.R"))
suppressMessages(library(data.table))

if (args[1] == "chm") {
  config <- jsonlite::read_json(args[3], simplifyVector = TRUE)
  d <- detect_lasr(args[2], res = config$resolution_m, a = config$vwf_slope,
                  dens = config$frdens)
  if (nrow(d)) d <- d[order(d$x, d$y, d$z), , drop = FALSE]
  d$instance <- seq_len(nrow(d))
  d$policy <- rep("max_agl", nrow(d))
  d$confidence <- d$z
  write.csv(d, args[4], row.names = FALSE)
} else if (args[1] == "score") {
  pred <- read.csv(args[2]); ref <- read.csv(args[3])
  policies <- if (args[4] == "chm_vwf") "max_agl" else
    c("max_agl", "isolated_top_agl", "historical_raw")
  detection <- lapply(policies, function(policy) {
    p <- pred[pred$policy == policy, , drop = FALSE]
    r <- ref[ref$policy == policy, , drop = FALSE]
    p <- p[order(p$instance), , drop = FALSE]
    r <- r[order(r$instance), , drop = FALSE]
    cbind(data.frame(policy = policy), audit_apex_match(p, r))
  })
  mask <- NULL
  if (args[4] != "chm_vwf") {
    labels <- data.table::fread(args[5])$pred_instance
    cloud <- lidR::readLAS(args[6])
    if (is.null(cloud) || length(labels) != lidR::npoints(cloud))
      stop("Scoring rows differ from the validated reference")
    r <- cloud$tree_index; r[r == 0] <- NA_integer_
    labels[labels == 0] <- NA_integer_
    rr <- ref[ref$policy == "max_agl", ]
    classes <- setNames(rr$category, as.character(rr$instance))
    mask <- score_instance_cell(labels, r, classes, gate = .5,
                                classes = c("A", "B", "C", "D"))
    # Every labelled tree must be a reference apex, and the mask counts each
    # tree with at least one point. On a native cloud that is every reference
    # tree; on a thinned one a small tree can keep no point and has no mask.
    ids <- unique(r[!is.na(r)])
    stopifnot(all(as.character(ids) %in% names(classes)), mask$n_ref == length(ids))
  }
  jsonlite::write_json(list(detection = do.call(rbind, detection), mask = mask),
                       args[7], auto_unbox = TRUE, pretty = TRUE, na = "null")
} else stop("Unknown cell operation")
