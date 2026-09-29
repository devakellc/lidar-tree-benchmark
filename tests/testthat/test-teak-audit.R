# Load only the audit's standalone provenance functions; never execute the audit.
teak_audit_functions <- function() {
  env <- new.env(parent = globalenv())
  exprs <- parse(file.path("..", "..", "scripts", "audit_teak_validation.R"))
  for (expr in exprs) {
    if (is.call(expr) && identical(expr[[1]], as.name("<-")) &&
        identical(expr[[2]], as.name(".bs_file"))) break
    eval(expr, env)
  }
  env
}

test_that("audit retains pre-read hashes when an input is registered again", {
  audit <- teak_audit_functions()
  path <- tempfile()
  on.exit(unlink(path))
  writeLines("before", path)
  audit$record(path)
  audit$verify_inputs()
  writeLines("after!", path) # Same byte count; content hash must detect the edit.
  audit$record(path)
  expect_equal(nrow(audit$initial_inputs), 1L)
  expect_error(audit$verify_inputs(), "Read inputs changed")
})

test_that("audit detects additions and removals from both exposure path sets", {
  audit <- teak_audit_functions()
  root <- tempfile()
  nd <- file.path(root, "neon/TEAK")
  dir.create(file.path(nd, "frozen"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE))
  csv <- file.path(nd, "exposure.csv")
  artifact <- file.path(nd, "frozen/TEAK_004.bin")
  writeLines("plot", csv)
  before <- audit$scan_paths(root)
  audit$verify_paths(before, root)
  file.create(artifact)
  expect_error(audit$verify_paths(before, root), "Scanned paths changed")
  with_artifact <- audit$scan_paths(root)
  unlink(artifact)
  expect_error(audit$verify_paths(with_artifact, root), "Scanned paths changed")
  unlink(csv)
  expect_error(audit$verify_paths(before, root), "Scanned paths changed")
  file.create(file.path(root, "neon/new_shared.csv"))
  expect_error(audit$verify_paths(before, root), "Scanned paths changed")
})
