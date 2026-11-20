# Synthetic fixtures shared across tests. No real NEON data is ever required.
suppressMessages({ library(lidR); library(data.table) })

# A labelled point table: two well-separated "trees", each a small vertical
# cluster. Columns X,Y,Z (metres) + a known instance id. Tree A apex (10,10,18),
# tree B apex (40,12,12).
synth_labelled_points <- function() {
  a <- data.table(X = c(10, 10.2, 9.8, 10.1), Y = c(10, 10.1, 9.9, 10.0),
                  Z = c(18, 14, 9, 4),  id = 1L)
  b <- data.table(X = c(40, 40.1, 39.9),       Y = c(12, 12.1, 11.9),
                  Z = c(12, 8, 3),      id = 2L)
  noise <- data.table(X = 25, Y = 25, Z = 1.0,  id = NA_integer_)  # unassigned
  rbind(a, b, noise)
}

# A minimal NORMALIZED LAS (ground at 0) with two clusters, for arm smoke tests.
synth_las_normalized <- function() {
  set.seed(1)
  mk <- function(cx, cy, top, n = 60) {
    data.frame(X = rnorm(n, cx, 0.7), Y = rnorm(n, cy, 0.7),
               Z = runif(n, 0, top))
  }
  df <- rbind(mk(10, 10, 18), mk(40, 12, 12))
  df$Z[1]  <- 18; df$Y[1]  <- 10; df$X[1]  <- 10   # guarantee a tree-A apex
  df$Z[61] <- 12; df$Y[61] <- 12; df$X[61] <- 40   # guarantee a tree-B apex
  las <- LAS(df)
  st_crs(las) <- 32611L
  las
}

# Block-labelled points for cross-block dedup. Columns block, inst, X, Y, Z.
# A (b0,10,10,18) & B (b0,11,10,15): SAME block, 1 m apart -> must stay distinct.
# C (b0,40,40,12) & C' (b1,40.1,40,11.8): DIFFERENT blocks, ~0.1 m -> must merge
# (merged apex = max-Z = 12). D (b1,60,60,10): isolated. inst 0 = unassigned.
synth_block_points <- function() {
  rows <- function(block, inst, x, y, ztop, zmid)
    data.table(block = as.integer(block), inst = as.integer(inst),
               X = c(x, x + 0.1, x), Y = c(y, y, y + 0.1),
               Z = c(ztop, zmid, zmid - 3))
  dt <- rbind(
    rows(0, 1, 10,   10,   18, 12),
    rows(0, 2, 11,   10,   15, 10),
    rows(0, 3, 40,   40,   12,  8),
    rows(1, 1, 40.1, 40.0, 11.8, 7),
    rows(1, 2, 60,   60,   10,  6))
  noise <- data.table(block = 1L, inst = 0L, X = 25, Y = 25, Z = 1)
  rbind(dt, noise)
}

# A closed stand (canopy cover about 0.72) where both closed-stand mechanisms of
# the multichm_gated arm change the detections: two tall crowns 4 m apart at
# similar heights (the distance filter keeps one of them unless surface peaks
# are exempt), and an understory crown under the edge of a wide crown whose
# returns are all later returns (a deeper-layer peak with a low first-return
# share, which the share gate removes).
synth_cone <- function(x, y, h, r, n, rn = 1L) {
  d <- r * sqrt(runif(n)); a <- runif(n, 0, 2 * pi)
  data.frame(X = x + d * cos(a), Y = y + d * sin(a),
             Z = pmax(0, h * (1 - 0.6 * d / r) + rnorm(n, 0, 0.1)), ReturnNumber = rn)
}
SYNTH_CLOSED_TREES <- data.frame(
  x = c(8, 12, 21, 25.5), y = c(8, 8, 21, 21), h = c(24, 23.5, 24, 9), r = c(4, 4, 7, 1.5),
  cls = c("dominant", "dominant", "dominant", "suppressed"))
synth_closed_stand <- function(seed = 1) {
  set.seed(seed)
  t <- SYNTH_CLOSED_TREES
  df <- rbind(synth_cone(t$x[1], t$y[1], t$h[1], t$r[1], 1200),
              synth_cone(t$x[2], t$y[2], t$h[2], t$r[2], 1200),
              synth_cone(t$x[3], t$y[3], t$h[3], t$r[3], 1500),
              synth_cone(t$x[4], t$y[4], t$h[4], t$r[4], 300, rn = 2L),
              data.frame(X = runif(1500, 0, 32), Y = runif(1500, 0, 32),
                         Z = abs(rnorm(1500, 0, 0.05)), ReturnNumber = 1L))
  df$ReturnNumber <- as.integer(df$ReturnNumber)
  las <- suppressWarnings(LAS(df))
  st_crs(las) <- 32611L
  las
}
synth_closed_stems <- function()
  data.frame(E = SYNTH_CLOSED_TREES$x, N = SYNTH_CLOSED_TREES$y, height = SYNTH_CLOSED_TREES$h,
             crown_class = SYNTH_CLOSED_TREES$cls, stringsAsFactors = FALSE)
synth_closed_meta <- function()
  list(site = "SYN", plot = "SYN_002", plotType = "tower", rung = NA, cx = 16, cy = 16,
       half = 16, pdens = 10, frdens = 5)
