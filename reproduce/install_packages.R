# Installs the R packages of the benchmark tables into the reproduction image.
# Packages that compute results are pinned to the versions the tables were
# made with and built from CRAN sources; the remaining dependencies come from
# the dated Posit Package Manager snapshot set in Rprofile.site. lasR and
# lidRplugins are built from their pinned GitHub commits (Dockerfile).
pins <- c(
  data.table = "1.18.4", terra = "1.8-29", sf = "1.0-19", s2 = "1.1.7", units = "0.8-6",
  wk = "0.9.4", lwgeom = "0.2-16", sp = "2.2-1", raster = "3.6-32", rlas = "1.9.2",
  lidR = "4.3.2", crownsegmentr = "1.0.1", clue = "0.3-68", dbscan = "1.2.4",
  fpc = "2.2-14", RMCC = "0.1.2", jsonlite = "2.0.0", digest = "0.6.37")
cran <- "https://cloud.r-project.org"
ppm <- getOption("repos")[["CRAN"]]

install.packages(c("remotes", "testthat", "BH", "Rcpp", "RcppArmadillo", "progress",
                   "assertthat", "glue", "lazyeval"))
db <- available.packages(repos = ppm)
need <- tools::package_dependencies(names(pins), db = db,
                                    which = c("Depends", "Imports", "LinkingTo"),
                                    recursive = TRUE)
need <- setdiff(unique(unlist(need)), c(names(pins), rownames(installed.packages())))
if (length(need)) install.packages(need)

# Pins go in dependency order, so each builds against the pinned versions of
# the pins it needs.
pin_deps <- lapply(tools::package_dependencies(names(pins), db = db, recursive = TRUE,
                                               which = c("Depends", "Imports", "LinkingTo")),
                   intersect, names(pins))
order <- character()
while (length(order) < length(pins)) {
  ready <- setdiff(names(pins)[vapply(pin_deps, function(d) all(d %in% order), TRUE)], order)
  if (!length(ready)) stop("circular dependencies among pinned packages")
  order <- c(order, ready)
}
for (p in order)
  remotes::install_version(p, pins[[p]], repos = cran, dependencies = FALSE,
                           upgrade = "never", type = "source")

got <- vapply(names(pins), function(p) as.character(packageVersion(p)), "")
want <- vapply(pins, function(v) as.character(package_version(v)), "")
if (any(got != want))
  stop("pinned versions not installed: ", paste(names(pins)[got != want], collapse = ", "))
cat("pinned packages installed\n")
