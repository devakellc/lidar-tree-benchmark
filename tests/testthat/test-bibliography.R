# Guards for docs/references.bib and for unresolved chat-export citation
# tokens. Base R only: the .bib parser below handles the subset of BibTeX the
# file uses (brace- or quote-delimited values and bare numbers).

repo_root <- file.path("..", "..")
bib_path <- file.path(repo_root, "docs", "references.bib")

bib_or <- function(x, y) if (is.null(x)) y else x

# Index of the brace that closes the one opened at `open` (both 1-based).
bib_match_brace <- function(chars, open) {
  depth <- 0L
  for (i in seq.int(open, length(chars))) {
    if (chars[i] == "{") depth <- depth + 1L
    if (chars[i] == "}") {
      depth <- depth - 1L
      if (depth == 0L) return(i)
    }
  }
  stop("unbalanced braces after position ", open, call. = FALSE)
}

bib_parse_fields <- function(body) {
  chars <- strsplit(body, "", fixed = TRUE)[[1]]
  fields <- list()
  i <- 1L
  n <- length(chars)
  while (i <= n) {
    rest <- paste(chars[i:n], collapse = "")
    m <- regexpr("^[\\s,]*([A-Za-z][A-Za-z0-9_-]*)\\s*=\\s*", rest, perl = TRUE)
    if (m == -1L) break
    name <- tolower(sub("^[\\s,]*([A-Za-z][A-Za-z0-9_-]*).*$", "\\1",
                        regmatches(rest, m), perl = TRUE))
    i <- i + attr(m, "match.length")
    if (chars[i] == "{") {
      close <- bib_match_brace(chars, i)
      value <- paste(chars[seq.int(i + 1L, length.out = close - i - 1L)],
                     collapse = "")
      i <- close + 1L
    } else if (chars[i] == "\"") {
      close <- i + regexpr("\"", paste(chars[(i + 1L):n], collapse = ""))
      value <- paste(chars[seq.int(i + 1L, length.out = close - i - 1L)],
                     collapse = "")
      i <- close + 1L
    } else {
      value <- sub("^([^,\\s]*).*$", "\\1", paste(chars[i:n], collapse = ""),
                   perl = TRUE)
      i <- i + nchar(value)
    }
    fields[[name]] <- gsub("\\s+", " ", trimws(value))
  }
  fields
}

parse_bib <- function(path) {
  text <- paste(readLines(path, encoding = "UTF-8", warn = FALSE),
                collapse = "\n")
  # Drop whole-line comments; '%' inside values is escaped as '\%'.
  text <- gsub("(^|\n)[ \t]*%[^\n]*", "\\1", text, perl = TRUE)
  chars <- strsplit(text, "", fixed = TRUE)[[1]]
  starts <- gregexpr("@[A-Za-z]+\\s*\\{", text, perl = TRUE)[[1]]
  if (starts[1] == -1L) return(list())
  lapply(seq_along(starts), function(k) {
    s <- starts[k]
    open <- s + attr(starts, "match.length")[k] - 1L
    close <- bib_match_brace(chars, open)
    inner <- paste(chars[(open + 1L):(close - 1L)], collapse = "")
    key <- trimws(sub(",.*$", "", inner))
    list(type = tolower(sub("^@([A-Za-z]+).*$", "\\1",
                            substr(text, s, open))),
         key = key,
         fields = bib_parse_fields(sub("^[^,]*,", "", inner)))
  })
}

test_that("the bibliography parses into keyed entries", {
  expect_true(file.exists(bib_path))
  entries <- parse_bib(bib_path)
  expect_gt(length(entries), 0L)
  keys <- vapply(entries, `[[`, "", "key")
  expect_true(all(grepl("^[a-z0-9]+$", keys)), info = paste(keys, collapse = " "))
})

test_that("bibliography keys are unique", {
  keys <- vapply(parse_bib(bib_path), `[[`, "", "key")
  expect_equal(anyDuplicated(keys), 0L,
               info = paste(keys[duplicated(keys)], collapse = ", "))
})

test_that("every entry has a title, an author or organization, and a year", {
  for (e in parse_bib(bib_path)) {
    f <- e$fields
    expect_true(nzchar(bib_or(f$title, "")), info = e$key)
    expect_true(nzchar(bib_or(f$author, bib_or(f$organization, ""))),
                info = e$key)
    expect_true(grepl("^[0-9]{4}$", bib_or(f$year, "")), info = e$key)
  }
})

test_that("every doi is a bare DOI without a resolver prefix", {
  dois <- unlist(lapply(parse_bib(bib_path), function(e) e$fields$doi))
  expect_gt(length(dois), 0L)
  bad <- dois[!grepl("^10\\.\\d{4,9}/\\S+$", dois, perl = TRUE)]
  expect_equal(length(bad), 0L, info = paste(bad, collapse = ", "))
})

test_that("the parser rejects a malformed DOI and a missing year", {
  tmp <- tempfile(fileext = ".bib")
  on.exit(unlink(tmp))
  writeLines(c("@article{x2020a,", "  author = {A, B},",
               "  title = {T {with} braces},",
               "  doi = {https://doi.org/10.1000/xyz},", "}"), tmp)
  e <- parse_bib(tmp)[[1]]
  expect_equal(e$fields$title, "T {with} braces")
  expect_null(e$fields$year)
  expect_false(grepl("^10\\.\\d{4,9}/\\S+$", e$fields$doi, perl = TRUE))
})

test_that("no document keeps private-use citation tokens from chat exports", {
  text_ext <- "\\.(md|json|bib|txt|csv|tsv|ya?ml|html?)$"
  files <- c(file.path(repo_root, "README.md"),
             list.files(file.path(repo_root, c("docs", "results")),
                        pattern = text_ext, recursive = TRUE,
                        full.names = TRUE, ignore.case = TRUE))
  expect_gt(length(files), 1L)
  # UTF-8 encodings of U+E200..U+E202, matched bytewise so the check does
  # not depend on the session locale.
  pua <- "\\xEE\\x88[\\x80-\\x82]"
  hits <- Filter(function(p) {
    any(grepl(pua, readLines(p, warn = FALSE), perl = TRUE, useBytes = TRUE))
  }, files)
  expect_equal(length(hits), 0L, info = paste(basename(hits), collapse = ", "))
})
