# A sealed frozen root holding SOAP_001 native + rung 8 cells (placeholder
# bytes; frozen_read only hashes them) and an upsampled rung 4.
sealed_root <- function(env, root) {
  cells <- data.frame(site = "SOAP", plot = "SOAP_001", rung = c("native", "8", "4"),
                      status = c("ok", "ok", "upsampled"), cx = 0, cy = 0,
                      core_half = 20, buffer = 25, stringsAsFactors = FALSE)
  for (r in c("native", "8")) {
    rdir <- get("frozen_dir", envir = env)(root, "SOAP", "SOAP_001", r)
    dir.create(rdir, recursive = TRUE)
    for (f in c("clip_rawground.laz", "clip_normalized.laz", "ground_dtm.tif"))
      writeLines(r, file.path(rdir, f))
    jsonlite::write_json(list(pdens = 10, frdens = 5, seed = 1L),
                         file.path(rdir, "manifest.json"), auto_unbox = TRUE)
  }
  get("frozen_seal", envir = env)(root, cells)
}

test_that("deep-model crown arm reads hash-verified DTMs from the sealed root", {
  env <- new.env(parent = globalenv())
  source(file.path("..", "..", "scripts", "crown_metrics_deepmodel.R"),
         local = env)

  root <- tempfile("frozen")
  sealed_root(env, root)
  expect_equal(
    env$frozen_dtm(root, "SOAP", "SOAP_001", "native", 0, 0, 20),
    file.path(root, "SOAP", "SOAP_001", "native", "ground_dtm.tif"))
  expect_equal(
    env$frozen_dtm(root, "SOAP", "SOAP_001", "8", 0, 0, 20),
    file.path(root, "SOAP", "SOAP_001", "8", "ground_dtm.tif"))
  expect_null(env$frozen_dtm(root, "SOAP", "SOAP_001", "4", 0, 0, 20))
  writeLines("tampered", file.path(root, "SOAP", "SOAP_001", "8", "ground_dtm.tif"))
  expect_error(env$frozen_dtm(root, "SOAP", "SOAP_001", "8", 0, 0, 20), "bytes differ")
})

test_that("deep-model crown rows preserve their source rung", {
  env <- new.env(parent = globalenv())
  source(file.path("..", "..", "scripts", "crown_metrics_deepmodel.R"),
         local = env)

  env$RUNGS <- c("native", "8")
  env$plot_half <- function(plotType) 20
  env$det_to_agl <- function(apex, dtm) apex
  env$score_crowns_against_field <- function(diam_table, apex, stems, field_cd,
                                             tol, site, plot, algo) {
    data.frame(site = site, plot = plot, algo = algo,
               crown_class = "dominant", individualID = "T1",
               d_eq = 2, d_caliper = 3, area = pi,
               field_maxCD = 4, field_ninetyCD = 2,
               stringsAsFactors = FALSE)
  }

  nd <- tempfile("deepmodel")
  idir <- file.path(nd, "instances")
  dir.create(idir, recursive = TRUE)
  file.create(file.path(idir, "SOAP_001_native.laz"))
  file.create(file.path(idir, "SOAP_001_8.laz"))
  root <- file.path(nd, "frozen_2021")
  sealed_root(env, root)

  model <- list(dir = "instances", load = function(path) {
    list(diam = data.frame(id = 1L, n_pts = 6L, d_eq = 2, d_caliper = 3),
         apex = data.frame(id = 1L, x = 0, y = 0, z = 10))
  })
  pc <- data.frame(plotID = "SOAP_001", easting = 0, northing = 0,
                   plotType = "tower")
  gt <- data.frame(plotID = "SOAP_001", E = 0, N = 0, height = 10,
                   crown_class = "dominant", individualID = "T1")
  fc <- data.frame(individualID = "T1", maxCrownDiameter = 4,
                   ninetyCrownDiameter = 2)

  res <- env$run_plot_model("SOAP", "SOAP_001", "segmentanytree", model,
                            pc, gt, fc, nd, root)
  expect_identical(names(res)[1:3], c("site", "plot", "rung"))
  expect_equal(res$rung, c("native", "8"))
})
