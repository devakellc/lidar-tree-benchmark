source(file.path("..", "..", "scripts", "normalize_fgiemit_development.R"))

test_that("geometric normalization preserves original rows and return fields", {
  xy <- expand.grid(X = 0:10, Y = 0:10)
  d <- rbind(data.frame(xy, Z = 0), data.frame(X = 5, Y = 5, Z = 2:8))
  d$Classification <- 1L
  d$ReturnNumber <- rep(c(1L, 2L), length.out = nrow(d))
  d$NumberOfReturns <- 2L
  cloud <- lidR::LAS(d)
  cloud <- lidR::add_lasattribute(cloud, seq_len(nrow(d)) - 1L,
                                "source_row", "Original zero-based row")
  directory <- tempfile(); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  input <- file.path(directory, "raw.las")
  output <- file.path(directory, "normalized.laz")
  receipt <- file.path(directory, "receipt.json")
  lidR::writeLAS(cloud, input)
  normalize_fgi_development(input, output, receipt)
  result <- lidR::readLAS(output)
  for (name in c("X", "Y", "source_row", "ReturnNumber", "NumberOfReturns"))
    expect_equal(result@data[[name]], cloud@data[[name]])
  expect_true(all(is.finite(result$Z)))
  expect_true(sum(result$Classification == 2L) >= 10L)
  expect_false(jsonlite::fromJSON(receipt)$independently_validated_AGL)
  expect_error(normalize_fgi_development(input, output, receipt), "Preserve")
})

test_that("the normalizer rejects original semantic labels as ground classes", {
  d <- expand.grid(X = 1:4, Y = 1:4)
  d$X <- as.numeric(d$X); d$Y <- as.numeric(d$Y)
  d$Z <- 0; d$Classification <- 2L
  d$ReturnNumber <- 1L; d$NumberOfReturns <- 1L
  cloud <- lidR::LAS(d)
  cloud <- lidR::add_lasattribute(cloud, seq_len(nrow(d)) - 1L,
                                "source_row", "Original zero-based row")
  directory <- tempfile(); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  input <- file.path(directory, "raw.las")
  lidR::writeLAS(cloud, input)
  expect_error(normalize_fgi_development(input, file.path(directory, "out.laz"),
    file.path(directory, "receipt.json")), "label-free")
})
