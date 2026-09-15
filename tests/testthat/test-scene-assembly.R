source(file.path("..", "..", "scripts", "model_bench_lib.R"))
source(file.path("..", "..", "scripts", "external_fgiemit_lib.R"))
source(file.path("..", "..", "scripts", "scene_assembly_lib.R"))

test_that("explicit row identity keeps duplicate XYZ, background and vertical instances", {
  query <- data.frame(X = c(0, 0, 0, 2), Y = 0, Z = c(3, 3, 20, 3))
  src <- transform(query, crown_id = c(0L, 1L, 2L, 3L), ff3d_row = 0:3)
  expected <- c(NA_integer_, 1L, 2L, 3L)
  expect_identical(fgi_indexed_labels(src, query)$labels, expected)
  expect_identical(fgi_indexed_labels(src[c(3, 1, 4, 2), ], query)$labels, expected)
  expect_equal(unname(fgi_indexed_labels(src, query)$distance), rep(0, 4))
  # These apexes would collapse transitively through a different outer block.
  pts <- data.frame(block = c(0, 1, 0), inst = c(1, 1, 2), X = 0:2, Y = 0, Z = c(3, 20, 3))
  expect_equal(length(unique(dedup_blocks(pts, 2)$global_id)), 1)
  src <- transform(pts, crown_id = 1:3, ff3d_row = 0:2)
  expect_identical(fgi_indexed_labels(src, pts)$labels, 1:3)
})

test_that("partial, repeated, invalid or mismatched source rows fail closed", {
  query <- data.frame(X = 1:3, Y = 0, Z = 2)
  src <- transform(query, crown_id = 1:3, ff3d_row = 0:2)
  for (rows in list(c(0, 0, 2), c(0, 1, 3), c(-1, 1, 2), c(0, .5, 2),
                    c(0, NA, 2), c(0, Inf, 2))) {
    bad <- src; bad$ff3d_row <- rows
    expect_error(fgi_indexed_labels(bad, query), "source row IDs")
  }
  expect_error(fgi_indexed_labels(src[-1, ], query), "source row IDs")
  expect_error(fgi_indexed_labels(src[, names(src) != "ff3d_row"], query), "source row IDs")
  bad <- src; bad$ff3d_row <- 2:0
  expect_error(fgi_indexed_labels(bad, query), "order or coordinates")
  expect_length(fgi_indexed_labels(src[0, ], query[0, ])$labels, 0)
})

test_that("native confidence uses matched rows and records filtered instances", {
  query <- data.frame(X = c(0, 0, 1, 2), Y = 0, Z = c(0, 3, 8, 4))
  src <- transform(query, crown_id = c(0, 1, 1, 2), ff3d_row = 0:3,
                    ff3d_score = c(0, .8, .6, .2))
  out <- scene_confidence(src[c(3, 4, 1, 2), ], query, c(NA, 1, 1, NA))
  expect_equal(out$crown_id, c(1, 2))
  expect_equal(out$points, c(2, 1))
  expect_equal(out$score_mean, c(.7, .2))
  expect_equal(out$score_min, c(.6, .2))
  expect_equal(out$score_max, c(.8, .2))
  expect_equal(out$apex_z, c(8, 4))
  expect_equal(out$retained, c(TRUE, FALSE))
  bad <- src; bad$ff3d_score[1] <- .9
  expect_error(scene_confidence(bad, query, numeric()), "confidence")
  bad <- src; bad$ff3d_score[2] <- NA
  expect_error(scene_confidence(bad, query, numeric()), "confidence")
  src$crown_id <- 0; src$ff3d_score <- 0
  expect_warning(empty <- scene_confidence(src, query, numeric()), NA)
  expect_equal(nrow(empty), 0)
})

test_that("archived comparisons fail on changed scores or support", {
  old <- data.frame(TP = 2, n_ref = 3, support_points = 80)
  expect_silent(scene_check_reproduction(old, old, names(old)))
  changed <- old; changed$support_points <- 79
  expect_error(scene_check_reproduction(changed, old, names(old)), "comparison changed")
  expect_error(scene_check_reproduction(old, old[0, ], names(old)), "comparison changed")
})

test_that("official checks distinguish absent categories from missing metrics", {
  row <- data.frame(n_A = 8, n_B = 0, n_C = 0, n_D = 0,
                    rec_A = 1, rec_B = NA_real_, rec_C = NA_real_, rec_D = NA_real_)
  expect_equal(scene_official_keys(row), c("precision", "recall", "f1", "cov", "recall_a"))
  row$rec_D <- 0
  expect_error(scene_official_keys(row), "must be undefined")
})
