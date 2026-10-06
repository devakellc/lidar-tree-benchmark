#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
source(.find("sweep_lib.R"))
source(.find("model_bench_lib.R"))
suppressMessages({ library(lidR); library(data.table) })

# Proxy-mask validation on the FGI-EMIT development plots
# (docs/fgiemit-proxy-validation-protocol.md). Builds the NEON
# Voronoi-on-stems proxy from the true trees (published positions, crown radius
# = half the largest horizontal extent of the tree's true points >= 2 m above
# ground), then scores the proxy against the true labels and the development
# matrix's SegmentAnyTree and ForestFormer3D labels against both references,
# on the canopy domain (>= 2 m above ground). Development plots only; reads no
# reserve or test plot and writes outside the FGI-EMIT root.
#   Rscript scripts/fgiemit_proxy_validation.R ROOT=<fgiemit root> OUT=<new dir>
#     [RADIUS=measured|fixed2] [N_BOOT=1000] [SEED=20260923]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
ROOT <- normalizePath(A$ROOT, mustWork = TRUE)
OUT <- A$OUT
if (is.null(OUT)) stop("OUT= is required")
OUT <- normalizePath(OUT, mustWork = FALSE)
if (startsWith(OUT, paste0(ROOT, "/"))) stop("OUT must be outside the FGI-EMIT root")
N_BOOT <- as.integer(if (is.null(A$N_BOOT)) 1000 else A$N_BOOT)
SEED <- as.integer(if (is.null(A$SEED)) 20260923 else A$SEED)
DEV <- c(1001, 1005, 1009, 1013, 1019, 1020, 1022, 1024, 1027, 1031)
PILOT <- c(1001, 1019, 1027)                   # admitted pilot cells; the rest ran later
ARMS <- c("segmentanytree", "forestformer3d")
CANOPY_MIN <- 2; FALLBACK_RADIUS <- 2
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
# YAML 1.1 reads a bare `y` key as boolean true; keep `y`/`n` as text.
trees_all <- yaml::read_yaml(file.path(ROOT, "source", "plot_data.yaml"), handlers = list(
  "bool#yes" = function(x) if (tolower(x) == "y") x else TRUE,
  "bool#no" = function(x) if (tolower(x) == "n") x else FALSE))

crown_radius <- function(x, y) {             # half the largest horizontal extent
  if (length(x) < 3) return(NA_real_)
  h <- grDevices::chull(x, y); hx <- x[h]; hy <- y[h]
  sqrt(max(outer(hx, hx, "-")^2 + outer(hy, hy, "-")^2)) / 2
}

plot_scores <- function(pid) {
  dir <- file.path(ROOT, "development_inputs", pid)
  ref <- readLAS(file.path(dir, "reference.laz"))
  nrm <- readLAS(file.path(dir, "normalized.laz"))
  if (!identical(ref$source_row, nrm$source_row)) stop("Row order differs in plot ", pid)
  truth <- ref$tree_index; truth[truth == 0] <- NA_integer_
  tr <- trees_all[[as.character(pid)]]$trees
  ids <- as.integer(names(tr))
  tx <- vapply(tr, `[[`, 0, "x"); ty <- vapply(tr, `[[`, 0, "y")
  classes <- setNames(vapply(tr, `[[`, "", "c"), names(tr))
  canopy <- nrm$Z >= CANOPY_MIN
  rad <- vapply(ids, function(k) {
    i <- which(truth == k & canopy); crown_radius(ref$X[i], ref$Y[i]) }, 0)
  radius <- switch(if (is.null(A$RADIUS)) "measured" else A$RADIUS,
                   measured = ifelse(is.na(rad), FALLBACK_RADIUS, rad),
                   fixed2 = rep(FALLBACK_RADIUS, length(ids)))
  proxy <- rep(NA_integer_, length(truth))
  ci <- which(canopy)
  a <- assign_points_to_stems(ref$X[ci], ref$Y[ci], tx, ty, radius)
  proxy[ci] <- ids[a]
  dom <- function(v) { v[!canopy] <- NA_integer_; v }
  sc <- function(pred, refl, what, arm)
    cbind(data.frame(plot = pid, arm = arm, reference = what, stringsAsFactors = FALSE),
          score_instance_cell(pred, refl, classes, gate = 0.5, classes = c("A", "B", "C", "D")))
  # Per-tree IoU of the proxy mask with the true mask (canopy domain).
  tiou <- vapply(ids, function(k) {
    p <- which(proxy == k); t <- which(dom(truth) == k)
    if (!length(t)) return(NA_real_)
    length(intersect(p, t)) / length(union(p, t)) }, 0)
  rows <- list(sc(proxy, dom(truth), "truth (canopy)", "proxy"))
  for (arm in ARMS) {
    run <- if (pid %in% PILOT) "development_pilot_v3" else "development_detector_run"
    lab <- fread(file.path(ROOT, run, pid, arm, "prediction_labels.csv"))$pred_instance
    if (length(lab) != length(truth)) stop("Label rows differ for ", arm, " on plot ", pid)
    lab[lab == 0] <- NA_integer_
    rows[[length(rows) + 1]] <- sc(lab, truth, "truth (full support)", arm)
    rows[[length(rows) + 1]] <- sc(dom(lab), dom(truth), "truth (canopy)", arm)
    rows[[length(rows) + 1]] <- sc(dom(lab), proxy, "proxy (canopy)", arm)
  }
  list(scores = do.call(rbind, rows),
       trees = data.frame(plot = pid, tree = ids, category = classes, height = vapply(tr, `[[`, 0, "h"),
                          radius = radius, measured_radius = rad, proxy_iou = tiou))
}

res <- lapply(DEV, function(p) { cat("plot", p, "\n"); plot_scores(p) })
cells <- do.call(rbind, lapply(res, `[[`, "scores"))
trees <- do.call(rbind, lapply(res, `[[`, "trees"))
write.csv(cells, file.path(OUT, "proxy_cells.csv"), row.names = FALSE)
write.csv(trees, file.path(OUT, "proxy_trees.csv"), row.names = FALSE)

pooled <- do.call(rbind, lapply(split(cells, paste(cells$arm, cells$reference)), function(x)
  cbind(arm = x$arm[1], reference = x$reference[1], pool_pq(x))))
write.csv(pooled, file.path(OUT, "proxy_pooled.csv"), row.names = FALSE)

# Paired whole-plot bootstrap: F1 against the proxy minus against the truth,
# both on the canopy domain, per arm.
set.seed(SEED)
f1 <- function(x) pool_pq(x)$F1
boot <- do.call(rbind, lapply(ARMS, function(arm) {
  a <- cells[cells$arm == arm & cells$reference == "proxy (canopy)", ]
  b <- cells[cells$arm == arm & cells$reference == "truth (canopy)", ]
  b <- b[match(a$plot, b$plot), ]
  d <- replicate(N_BOOT, { i <- sample(nrow(a), replace = TRUE); f1(a[i, ]) - f1(b[i, ]) })
  data.frame(arm = arm, f1_proxy = f1(a), f1_truth = f1(b), delta = f1(a) - f1(b),
             lower = quantile(d, 0.025), upper = quantile(d, 0.975), row.names = NULL)
}))
write.csv(boot, file.path(OUT, "proxy_delta.csv"), row.names = FALSE)
print(pooled[, c("arm", "reference", "n_pred", "n_ref", "TP", "precision", "recall", "F1", "SQ", "PQ", "coverage")],
      row.names = FALSE, digits = 3)
print(boot, row.names = FALSE, digits = 3)
cat(sprintf("proxy-vs-truth tree IoU: median %.3f, share >= 0.5: %.3f (%d trees)\n",
            median(trees$proxy_iou, na.rm = TRUE), mean(trees$proxy_iou >= 0.5, na.rm = TRUE),
            sum(!is.na(trees$proxy_iou))))
