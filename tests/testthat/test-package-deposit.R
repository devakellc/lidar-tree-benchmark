# The deposit packager (package_deposit.sh) run on a tiny staged archive in a
# temporary directory: the archive tar's top-level name, symlink and owners,
# the source snapshot of CODE_COMMIT, the deposit's checksums and the runs it
# refuses. Then the clean-checkout guard of stage_archive.sh, read from the
# script's text (staging is not run).
pd_root <- normalizePath(file.path("..", ".."))

pd_git <- function(...) suppressWarnings(system2("git", c("-C", shQuote(pd_root), ...),
                                                 stdout = TRUE, stderr = FALSE))

# The worktree's HEAD, or a skip when the tools or a git checkout are missing.
pd_head <- function() {
  for (tool in c("bash", "git", "tar", "gzip", "sha256sum"))
    skip_if(Sys.which(tool) == "", paste(tool, "not on PATH"))
  head <- pd_git("rev-parse", "--verify", "HEAD")
  skip_if(!is.null(attr(head, "status")) || length(head) != 1 ||
            !grepl("^[0-9a-f]{40}$", head[1]), "the repository root is not a git checkout")
  head
}

pd_sh <- function(cmd) suppressWarnings(system2("bash", c("-c", shQuote(cmd)),
                                                stdout = FALSE, stderr = FALSE))

# SHA256SUMS over every file, as stage_archive.sh writes it.
pd_seal <- function(a) stopifnot(pd_sh(paste("cd", shQuote(a),
  "&& find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS")) == 0)

# Two clip files, a job directory's relative link to them, README.md and
# CODE_COMMIT, under a name other than the one the tar gives the archive.
pd_fixture <- function(base, commit) {
  a <- file.path(base, "staged_copy")
  dir.create(file.path(a, "neon", "frozen_2021"), recursive = TRUE)
  dir.create(file.path(a, "paper_runs", "neon"), recursive = TRUE)
  writeLines(c("file,sha256", "SJER_001_native.laz,0"),
             file.path(a, "neon", "frozen_2021", "clip_manifest.csv"))
  writeLines(c("plot", "SJER_001"), file.path(a, "neon", "frozen_2021", "population.csv"))
  stopifnot(file.symlink(file.path("..", "..", "neon", "frozen_2021"),
                         file.path(a, "paper_runs", "neon", "frozen_2021")))
  writeLines("# Reproduction archive", file.path(a, "README.md"))
  writeLines(commit, file.path(a, "CODE_COMMIT"))
  pd_seal(a)
  a
}

pd_run <- function(...) {
  res <- suppressWarnings(system2("bash",
    shQuote(c(file.path(pd_root, "scripts", "package_deposit.sh"), ...)),
    stdout = TRUE, stderr = TRUE, env = "PIGZ=-p2"))
  list(status = if (is.null(attr(res, "status"))) 0L else attr(res, "status"),
       text = paste(res, collapse = "\n"))
}

pd_tar <- function(tarball, ...) system2("tar", c(..., shQuote(tarball)), stdout = TRUE)

test_that("the deposit holds the archive tar, the source snapshot and their checksums", {
  head <- pd_head()
  base <- tempfile("deposit"); dir.create(base); on.exit(unlink(base, recursive = TRUE))
  a <- pd_fixture(base, head)
  report <- file.path(base, "report.csv"); writeLines(c("path,status", "x.csv,identical"), report)
  log <- file.path(base, "console.log"); writeLines("DONE  figures", log)
  out <- file.path(base, "deposit")
  r <- pd_run(paste0("ARCHIVE=", a), paste0("OUT=", out), paste0("REPORT=", report),
              paste0("LOG=", log))
  expect_equal(r$status, 0L, info = r$text)
  short <- substr(head, 1, 7)
  code <- paste0("lidar-tree-benchmark-code-", short, ".tar.gz")
  arch <- "lidar-tree-benchmark-archive.tar.gz"
  expect_setequal(list.files(out, all.files = TRUE, no.. = TRUE),
                  c(arch, code, "README.md", "reproduction_report.csv",
                    "reproduction_console.log", "SHA256SUMS"))

  # One top-level directory whatever the staged one is called; the job
  # directory's link stays a relative symlink; owner and group 0, no names.
  members <- pd_tar(file.path(out, arch), "-tzf")
  expect_setequal(unique(sub("/.*", "", members)), "lidar-tree-benchmark-archive")
  expect_true("lidar-tree-benchmark-archive/neon/frozen_2021/population.csv" %in% members)
  listing <- pd_tar(file.path(out, arch), "--numeric-owner", "-tvzf")
  link <- grep("/paper_runs/neon/frozen_2021", listing, fixed = TRUE, value = TRUE)
  expect_length(link, 1)
  expect_match(link, "^l")
  expect_true(endsWith(link, "frozen_2021 -> ../../neon/frozen_2021"), info = link)
  expect_true(all(grepl("^\\S+ 0/0 ", listing)), info = paste(listing, collapse = "\n"))
  expect_true(all(grepl("^\\S+ 0/0 ", pd_tar(file.path(out, arch), "-tvzf"))))

  # The source snapshot of CODE_COMMIT under its prefix.
  snap <- pd_tar(file.path(out, code), "-tzf")
  expect_setequal(unique(sub("/.*", "", snap)), paste0("lidar-tree-benchmark-", short))
  in_head <- is.null(attr(pd_git("cat-file", "-e", "HEAD:scripts/package_deposit.sh"), "status"))
  want <- if (in_head) "package_deposit.sh" else "stage_archive.sh"
  expect_true(paste0("lidar-tree-benchmark-", short, "/scripts/", want) %in% snap)

  expect_identical(readLines(file.path(out, "README.md")), readLines(file.path(a, "README.md")))
  expect_identical(readLines(file.path(out, "reproduction_report.csv")), readLines(report))
  expect_identical(readLines(file.path(out, "reproduction_console.log")), readLines(log))
  sums <- readLines(file.path(out, "SHA256SUMS"))
  expect_identical(sub("^[0-9a-f]{64}  ", "", sums),
                   sort(setdiff(list.files(out), "SHA256SUMS"), method = "radix"))
  expect_equal(pd_sh(paste("cd", shQuote(out), "&& sha256sum --quiet -c SHA256SUMS")), 0L)

  # A second run into the same OUT is refused and leaves it as it was.
  before <- tools::md5sum(list.files(out, full.names = TRUE))
  again <- pd_run(paste0("ARCHIVE=", a), paste0("OUT=", out))
  expect_false(again$status == 0L)
  expect_match(again$text, "OUT exists")
  expect_identical(tools::md5sum(names(before)), before)
})

test_that("a corrupted archive, an unknown commit or a failed step leaves no deposit", {
  head <- pd_head()
  base <- tempfile("deposit"); dir.create(base); on.exit(unlink(base, recursive = TRUE))
  a <- pd_fixture(base, head)
  refused <- function(out, pattern, ...) {
    r <- pd_run(paste0("ARCHIVE=", a), paste0("OUT=", out), ...)
    expect_false(r$status == 0L, info = r$text)
    expect_match(r$text, pattern)
    expect_false(file.exists(out))
  }
  clip <- file.path(a, "neon", "frozen_2021", "population.csv")
  writeLines(c("plot", "SJER_002"), clip)                           # no longer its checksum
  refused(file.path(base, "corrupt"), "does not match its SHA256SUMS")
  writeLines(c("plot", "SJER_001"), clip)

  # Re-sealed, so only the commit is wrong: one this repository does not hold,
  # and a ref name that would name no fixed commit.
  writeLines(strrep("0123456789", 4), file.path(a, "CODE_COMMIT")); pd_seal(a)
  refused(file.path(base, "unknown"), "is not a commit of")
  writeLines("HEAD", file.path(a, "CODE_COMMIT")); pd_seal(a)
  refused(file.path(base, "ref"), "full commit id")
  writeLines(head, file.path(a, "CODE_COMMIT")); pd_seal(a)

  refused(file.path(base, "report"), "REPORT is not a file", paste0("REPORT=", base))
  refused(file.path(a, "inside"), "outside ARCHIVE")

  # A step failing after OUT is made (tar cannot read a file) removes OUT.
  skip_if(Sys.info()[["effective_user"]] == "root", "root reads unreadable files")
  Sys.chmod(clip, "000")
  refused(file.path(base, "unreadable"), "removed", "VERIFY=0")
  Sys.chmod(clip, "644")
})

test_that("stage_archive.sh stops on uncommitted code before it writes anything", {
  src <- readLines(file.path(pd_root, "scripts", "stage_archive.sh"))
  guard <- grep('git -C "$REPO" status --porcelain -- scripts docs reproduce', src, fixed = TRUE)
  expect_length(guard, 1)
  expect_gt(guard, grep("OUT exists", src, fixed = TRUE)[1])        # after the arguments
  expect_lt(guard, grep('mkdir -p "$OUT/neon"', src, fixed = TRUE)[1])
  expect_match(paste(src[guard:(guard + 3)], collapse = "\n"), "exit 1")
})
