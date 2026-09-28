#!/usr/bin/env Rscript
# Summarize only complete detector support, using existing benchmark pooling.
args <- commandArgs(TRUE)
if (length(args) != 2L) stop("Usage: summarize_fgiemit_development.R cells.csv outdir")
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
source(file.path(dirname(script), "repo_paths.R"))
source(.find("model_bench_lib.R"))
source(.find("fgiemit_development_summary_lib.R"))
rows <- read.csv(args[1], colClasses = c(plot = "character"), check.names = FALSE)
result <- fgi_summarize_complete(rows)
for (name in names(result))
  write.csv(result[[name]], file.path(args[2], paste0(name, ".csv")), row.names = FALSE,
            na = "NA")
jsonlite::write_json(list(resamples = 1000L, seed = 20260923L,
  unit = "paired_whole_plot", interval = "95_percentile_type7",
  RNG = c("Mersenne-Twister", "Inversion", "Rejection"),
  plot_order = FGI_DEVELOPMENT_PLOTS, R = as.character(getRversion()),
  mask_pooling = "pool_pq", cell_accumulator_digits = 4L),
  file.path(args[2], "analysis.json"), pretty = TRUE, auto_unbox = TRUE)
