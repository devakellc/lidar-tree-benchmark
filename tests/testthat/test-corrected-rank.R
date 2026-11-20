# corrected_rank_stability.R pairs each detector's per-draw corrected F1 at
# native density with its own value at another rung, whatever order the two
# job directories' files list the detectors in (the QL2 rung's file follows the
# order of its run's ARMS=).

ladder <- c("chm_vwf", "multichm", "lmfauto", "ptrees", "ams3d", "forestformer3d",
            "treeisonet", "segmentanytree")

cr_write <- function(dir, rungs, order, seed, drop = NULL) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  set.seed(seed)
  for (pre in c("null", "null_tol2")) {
    dr <- do.call(rbind, lapply(rungs, function(r) do.call(rbind, lapply(1:30, function(k)
      data.frame(draw = k, rung = r, detector = order, value = round(runif(length(order)), 6))))))
    if (!is.null(drop)) dr <- dr[!(dr$draw == 1 & dr$detector == drop), ]
    write.csv(dr, file.path(dir, paste0(pre, "_corrected_draws.csv")), row.names = FALSE)
    de <- do.call(rbind, lapply(rungs, function(r)
      data.frame(scope = "five sites", stratum = "all", metric = "F1_scaled", detector = order,
                 rung = r, estimate = round(runif(length(order)), 6))))
    write.csv(de, file.path(dir, paste0(pre, "_delta.csv")), row.names = FALSE)
  }
}

cr_run <- function(job, ql2, out) {
  root <- normalizePath(file.path("..", ".."))
  dir.create(out, showWarnings = FALSE)
  res <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    shQuote(c(file.path(root, "scripts", "corrected_rank_stability.R"),
              paste0("QL2_SENSITIVITY=", ql2), paste0("OUT=", out))),
    stdout = TRUE, stderr = TRUE, env = paste0("CLAUDE_JOB_DIR=", job)))
  list(status = attr(res, "status"), text = paste(res, collapse = "\n"),
       file = file.path(out, "null_corrected_rank.csv"))
}

test_that("the corrected rank interval does not depend on the detectors' order in the files", {
  base <- tempfile("corrected_rank")
  on.exit(unlink(base, recursive = TRUE))
  job <- file.path(base, "paper_runs")
  cr_write(file.path(job, "sensitivity"), c("native", "8"), ladder, seed = 1)
  shuffled <- ladder[c(1, 3, 2, 8, 4, 7, 5, 6)]
  cr_write(file.path(base, "ql2_ordered"), "3.2", ladder, seed = 2)
  cr_write(file.path(base, "ql2_shuffled"), "3.2", ladder, seed = 2)
  # The same values listed in another detector order.
  for (pre in c("null", "null_tol2")) {
    for (f in paste0(pre, c("_corrected_draws.csv", "_delta.csv"))) {
      x <- read.csv(file.path(base, "ql2_ordered", f), stringsAsFactors = FALSE)
      x <- x[order(x[[if ("draw" %in% names(x)) "draw" else "rung"]], match(x$detector, shuffled)), ]
      write.csv(x, file.path(base, "ql2_shuffled", f), row.names = FALSE)
    }
  }
  a <- cr_run(job, file.path(base, "ql2_ordered"), file.path(base, "out_a"))
  b <- cr_run(job, file.path(base, "ql2_shuffled"), file.path(base, "out_b"))
  expect_null(a$status, info = a$text)
  expect_null(b$status, info = b$text)
  ra <- read.csv(a$file, colClasses = c(to = "character"))
  rb <- read.csv(b$file, colClasses = c(to = "character"))
  expect_identical(ra, rb)
  expect_setequal(ra$to, c("8", "3.2"))
})

test_that("a detector missing from a draw stops the corrected rank script", {
  base <- tempfile("corrected_rank_missing")
  on.exit(unlink(base, recursive = TRUE))
  job <- file.path(base, "paper_runs")
  cr_write(file.path(job, "sensitivity"), c("native", "8"), ladder, seed = 3)
  cr_write(file.path(base, "ql2"), "3.2", ladder, seed = 4, drop = "ptrees")
  r <- cr_run(job, file.path(base, "ql2"), file.path(base, "out"))
  expect_false(is.null(r$status))
  expect_match(r$text, "missing from a draw at rung 3.2")
})
