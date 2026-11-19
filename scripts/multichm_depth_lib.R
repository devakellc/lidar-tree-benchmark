# Library of the `multichm_depth` tree-top arm: a depth-gated variant of the
# multichm_gated arm (multichm_gated_lib.R). Both start from the same candidates,
# the local maxima of every layer of lidRplugins::multichm before its distance
# filter (mcg_candidates / mcg_prepare: X, Y, Z, layer, ztop, share), and differ
# in which of them they keep and how the distance filter treats them.
#
# The variant judges a deeper-layer candidate by how far it sits under the
# local canopy surface: its depth is the height of the highest return in a
# vertical column around it minus its own Z, in metres, so it does not depend on
# the flight's return multiplicity the way the first-return share does. The
# column's radius grows at low first-return density so that the column holds at
# least MCD_MIN_FIRST first returns on average. In a closed stand (canopy cover
# >= cover_min) a deeper candidate is kept when it is no deeper than depth_max
# or, with lit_union, when it is lit from above (first-return share >=
# MCD_LIT_SHARE) and no deeper than MCD_LIT_DEPTH; candidates of every stand
# have height floors (zmin for deeper layers, zmin_surface for the surface). In
# a closed stand one horizontal spacing rule (near_2d) applies to every top,
# surface or deeper, in place of the package's distance filter; near_2d 0 keeps
# the declared gated arm's filter (surface peaks exempt). Open stands keep the
# package's filter. A detection's height can be reported as the candidate's Z or
# re-measured as zrep, the top of the contiguous column of returns above the
# candidate's own top.
#
# The features, constants, configurations, rules and grid are those of the
# specification work/multichm_depth/SPEC.txt (sections 2 to 4), fixed before any
# NEON score of these rules was computed. Its provenance (section 7): the
# family's form, its constants and its grid values were informed by an
# exploratory look at 60 plots outside the benchmark that have no field
# reference (three ML segmenters as referees).
#
# Two identities tie the family to the gated arm on any prepared clip
# (mcd_identities()): mcd_config(Inf, 0, 5, 0, FALSE, 0.6) accepts exactly the
# candidates of the gated configuration z5_s0_c0.6_e1, and MCD_STOCK =
# mcd_config(Inf, 0, 0, 0, FALSE, Inf) exactly those of MCG_STOCK (stock
# lidRplugins::multichm).
#
# Sourced, not run. No side effects. The caller sources multichm_gated_lib.R
# and everything it needs first (sweep_lib.R, model_bench_lib.R, calval_lib.R,
# master_tables_lib.R; lidR, lidRplugins and data.table attached): this library
# calls mcg_filter() and assert_detection_contract(), and mcd_identities() calls
# mcg_config(). It reads no file and changes no option or lidR setting.

## ---- constants ----------------------------------------------------------------------------
MCD_RADIUS    <- 1     # minimum horizontal radius (m) of a candidate's column
MCD_MIN_FIRST <- 8     # first returns the column holds on average at the clip's frdens
MCD_GAP       <- 1.5   # largest vertical step (m) zrep climbs from one return to the next
MCD_LIT_SHARE <- 0.75  # first-return share at or above which a deeper candidate is lit
MCD_LIT_DEPTH <- 5     # largest depth (m) at which a lit deeper candidate is kept (lit_union)

# The constants as a named list (for a digest of what a run used).
mcd_constants <- function()
  list(MCD_RADIUS = MCD_RADIUS, MCD_MIN_FIRST = MCD_MIN_FIRST, MCD_GAP = MCD_GAP,
       MCD_LIT_SHARE = MCD_LIT_SHARE, MCD_LIT_DEPTH = MCD_LIT_DEPTH)

## ---- features (per candidate, independent of the configuration) --------------------------
# The column radius of a clip of `frdens` first returns per m^2:
# max(MCD_RADIUS, sqrt(MCD_MIN_FIRST / (pi * frdens))), 1 m at 16 pts/m^2,
# 1.128 m at 2 and 2.257 m at 0.5. frdens must be one finite number above 0.
mcd_col_radius <- function(frdens) {
  if (!is.numeric(frdens) || length(frdens) != 1L || !is.finite(frdens) || frdens <= 0)
    stop("multichm_depth: frdens must be one finite number above 0 (first returns per m^2)",
         call. = FALSE)
  max(MCD_RADIUS, sqrt(MCD_MIN_FIRST / (pi * as.numeric(frdens))))
}

# The top of a contiguous column: z holds the heights of the column's returns,
# zt the candidate's own top (ztop). Climbs from zt through the returns above it
# (z > zt) in ascending order while each step is at most MCD_GAP and returns the
# last height reached: zt when nothing lies above it or the first step is longer.
.mcd_zrep <- function(z, zt) {
  z <- sort(z[z > zt])
  if (!length(z)) return(zt)
  path <- c(zt, z)
  k <- match(TRUE, diff(path) > MCD_GAP)        # the first step that is too long
  if (is.na(k)) path[length(path)] else path[k]
}

# Features of each candidate on the clip it was made from (the cell's
# normalized clip `las`, every return number): adds to a copy of `cand` the
# column radius r_col (one value, mcd_col_radius(frdens), repeated on every
# row), col_top (the highest Z of the clip's returns whose horizontal distance
# to the candidate's X, Y is at most r_col: (x - X)^2 + (y - Y)^2 <= r_col^2),
# depth = col_top - Z and zrep (.mcd_zrep over the column from the candidate's
# ztop). An empty column gives col_top = ztop (and zrep = ztop). Points are
# binned on a grid of cell size r_col (inflated by a relative 1e-9 so rounding
# can never put a qualifying point two cells away); each candidate joins its
# 3 x 3 neighbouring bins, then the exact test applies. cand needs X, Y, Z,
# layer and ztop (mcg_candidates / mcg_prepare); the result is a data.table in
# the row order of cand. frdens is the cell's first-return density as the gated
# study records it (candidates.csv, clip$frdens).
mcd_features <- function(cand, las, frdens) {
  r <- mcd_col_radius(frdens)
  if (!inherits(las, "LAS")) stop("multichm_depth: las must be a lidR LAS object", call. = FALSE)
  need <- c("X", "Y", "Z", "layer", "ztop")
  miss <- setdiff(need, names(cand))
  if (length(miss)) stop("multichm_depth: the candidates lack columns ",
                         paste(miss, collapse = ","), call. = FALSE)
  out <- data.table::as.data.table(cand)            # a copy: cand is never changed
  n <- nrow(out)
  col_top <- as.numeric(out$ztop)                   # the empty column's value
  zrep <- as.numeric(out$ztop)
  if (n && !lidR::is.empty(las)) {
    cell <- r * (1 + 1e-9)
    x0 <- min(las@data$X); y0 <- min(las@data$Y)
    P <- data.table::data.table(px = las@data$X, py = las@data$Y, pz = las@data$Z)
    P[, `:=`(gx = floor((px - x0) / cell), gy = floor((py - y0) / cell))]
    data.table::setkeyv(P, c("gx", "gy"))
    Q <- data.table::data.table(cid = seq_len(n), qx = out$X, qy = out$Y, qz = out$ztop)
    Q[, `:=`(gx0 = floor((qx - x0) / cell), gy0 = floor((qy - y0) / cell))]
    nb <- data.table::CJ(dx = -1:1, dy = -1:1)
    Q9 <- Q[rep(seq_len(n), each = 9L)]
    Q9[, `:=`(gx = gx0 + rep(nb$dx, n), gy = gy0 + rep(nb$dy, n))]
    J <- P[Q9, on = c("gx", "gy"), nomatch = NULL, allow.cartesian = TRUE]
    J <- J[(px - qx)^2 + (py - qy)^2 <= r^2]
    if (nrow(J)) {
      s <- J[, list(col_top = max(pz), zrep = .mcd_zrep(pz, qz[1L])), by = "cid"]
      col_top[s$cid] <- s$col_top
      zrep[s$cid] <- s$zrep
    }
  }
  out[, `:=`(r_col = rep(r, n), col_top = col_top, depth = col_top - as.numeric(out$Z),
             zrep = zrep)]
  out
}

## ---- configuration ------------------------------------------------------------------------
# A validated configuration. depth_max: largest depth (m) of a deeper-layer
# candidate kept in a closed stand (> 0; Inf: no depth rule); near_2d:
# horizontal spacing (m) of every accepted top in a closed stand (>= 0; 0: the
# declared gated arm's filter, surface peaks exempt); zmin: height floor (m) of
# deeper-layer candidates (layer > 1), every stand; zmin_surface: height floor
# (m) of surface candidates (layer 1), every stand; lit_union: a deeper
# candidate in a closed stand is also kept when lit (share >= MCD_LIT_SHARE) and
# no deeper than MCD_LIT_DEPTH; cover_min: canopy cover at or above which a
# stand is closed (>= 0; 0: every stand is closed; above 1, Inf included: no
# stand is closed). near_2d, zmin and zmin_surface must be finite. Values are
# stored as given (no canonical form): two configurations that behave alike on
# every clip (any two with cover_min above 1 and the same floors, say) keep
# their own labels. The defaults are the stock configuration (MCD_STOCK).
mcd_config <- function(depth_max = Inf, near_2d = 0, zmin = 0, zmin_surface = 0,
                       lit_union = FALSE, cover_min = Inf) {
  num <- function(v, nm, lo, open_lo = FALSE, inf_ok = FALSE) {
    ok <- is.numeric(v) && length(v) == 1L && !is.na(v) && (is.finite(v) || (inf_ok && v == Inf))
    if (ok) ok <- if (open_lo) v > lo else v >= lo
    if (!ok)
      stop(sprintf("multichm_depth: %s must be one number %s %g%s", nm,
                   if (open_lo) ">" else ">=", lo, if (inf_ok) " (Inf allowed)" else ", finite"),
           call. = FALSE)
    as.numeric(v)
  }
  if (!is.logical(lit_union) || length(lit_union) != 1L || is.na(lit_union))
    stop("multichm_depth: lit_union must be TRUE or FALSE", call. = FALSE)
  list(depth_max = num(depth_max, "depth_max", 0, open_lo = TRUE, inf_ok = TRUE),
       near_2d = num(near_2d, "near_2d", 0),
       zmin = num(zmin, "zmin", 0),
       zmin_surface = num(zmin_surface, "zmin_surface", 0),
       lit_union = lit_union,
       cover_min = num(cover_min, "cover_min", 0, inf_ok = TRUE))
}
MCD_FIELDS <- c("depth_max", "near_2d", "zmin", "zmin_surface", "lit_union", "cover_min")

.mcd_check_config <- function(cfg) {
  if (is.null(cfg))
    stop("multichm_depth: no configuration; pass one (mcd_config())", call. = FALSE)
  if (!is.list(cfg) || !all(MCD_FIELDS %in% names(cfg)))
    stop("multichm_depth: a configuration is a list(", paste(MCD_FIELDS, collapse = ", "), ")",
         call. = FALSE)
  mcd_config(cfg$depth_max, cfg$near_2d, cfg$zmin, cfg$zmin_surface, cfg$lit_union,
             cfg$cover_min)
}

# The stock configuration: no floor, no closed stand, the package's filter.
MCD_STOCK <- mcd_config(Inf, 0, 0, 0, FALSE, Inf)

# "k<depth_max>_r<near_2d>_z<zmin>_f<zmin_surface>_l<0|1>_c<cover_min>", numbers
# printed with %g: e.g. "k4_r0_z5_f0_l1_c0.6", "kInf_r0_z0_f0_l0_cInf" (stock).
mcd_config_label <- function(cfg) {
  cfg <- .mcd_check_config(cfg)
  sprintf("k%g_r%g_z%g_f%g_l%d_c%g", cfg$depth_max, cfg$near_2d, cfg$zmin, cfg$zmin_surface,
          as.integer(cfg$lit_union), cfg$cover_min)
}

# The two identities with the gated arm (acceptance checks; they must hold on
# every prepared clip): each element pairs a depth configuration with the gated
# configuration that accepts exactly the same candidates. Needs mcg_config().
mcd_identities <- function()
  list(A = list(depth = mcd_config(Inf, 0, 5, 0, FALSE, 0.6),
                gated = mcg_config(zmin = 5, min_share = 0, cover_min = 0.6,
                                   surface_exempt = TRUE)),   # z5_s0_c0.6_e1
       B = list(depth = MCD_STOCK, gated = MCG_STOCK))

## ---- the rules: closed stand, keep, distance filter, detections ---------------------------
# Whether a clip counts as a closed stand: TRUE for every stand when cover_min
# == 0, FALSE for every stand when cover_min > 1, otherwise cover >= cover_min,
# and NA when that cover is unknown (NA or NULL). Never stops: mcd_gate does.
mcd_closed <- function(cover, cfg) {
  cfg <- .mcd_check_config(cfg)
  if (cfg$cover_min == 0) TRUE
  else if (cfg$cover_min > 1) FALSE
  else if (is.null(cover) || length(cover) != 1L || is.na(cover)) NA
  else cover >= cfg$cover_min
}

# keep, every stand: a surface candidate (layer 1) iff Z >= zmin_surface; a
# deeper candidate (layer > 1) iff Z >= zmin and, in a closed stand, also
# depth <= depth_max or (lit_union and its share is known, share >=
# MCD_LIT_SHARE and depth <= MCD_LIT_DEPTH). Returns list(keep, closed) with
# keep in the row order of cand. An unknown cover with 0 < cover_min <= 1
# stops. In a closed stand the deeper candidates need a known depth (column
# `depth`, mcd_features) and, with lit_union, the table needs the column
# `share` (an NA share is simply not lit).
mcd_gate <- function(cand, cover, cfg) {
  cfg <- .mcd_check_config(cfg)
  closed <- mcd_closed(cover, cfg)
  if (is.na(closed))
    stop("multichm_depth: this configuration needs the canopy cover, which is unavailable ",
         "(the clip has no ReturnNumber or no first returns)", call. = FALSE)
  surface <- cand$layer == 1L
  Z <- as.numeric(cand$Z)
  keep_deep <- Z >= cfg$zmin
  if (closed && any(!surface)) {
    depth <- cand[["depth"]]
    if (is.null(depth) || anyNA(depth[!surface]))
      stop("multichm_depth: in a closed stand the deeper candidates need their depth ",
           "(column `depth`, from mcd_features)", call. = FALSE)
    lit <- FALSE
    if (cfg$lit_union) {
      share <- cand[["share"]]
      if (is.null(share))
        stop("multichm_depth: lit_union needs the candidates' first-return share ",
             "(column `share`, from mcg_prepare)", call. = FALSE)
      lit <- !is.na(share) & share >= MCD_LIT_SHARE & depth <= MCD_LIT_DEPTH
    }
    keep_deep <- keep_deep & (depth <= cfg$depth_max | lit)
  }
  keep <- (surface & Z >= cfg$zmin_surface) | (!surface & keep_deep)
  list(keep = keep, closed = closed)
}

# The distance filter over the kept candidates in descending Z, the order
# mcg_filter() uses (it runs the loop): in a closed stand with near_2d > 0 a
# kept candidate, surface or deeper, is accepted iff no accepted top lies within
# near_2d horizontally (d2 < near_2d^2; mcg_filter with dist_3d = 0, whose 3-D
# test d2 + dz^2 < 0 never rejects); in a closed stand with near_2d == 0 the
# declared gated arm's filter (a kept surface candidate is exempt, a kept deeper
# one is accepted iff no accepted top has d2 < 3^2 and none d2 + dz^2 < 5^2);
# in an open stand the package's filter for every kept candidate. closed is
# mcd_gate()'s TRUE / FALSE. Returns `accepted` in the row order of cand.
mcd_filter <- function(cand, keep, closed, cfg) {
  cfg <- .mcd_check_config(cfg)
  if (!is.logical(closed) || length(closed) != 1L || is.na(closed))
    stop("multichm_depth: closed must be TRUE or FALSE (mcd_gate)", call. = FALSE)
  n <- nrow(cand)
  if (length(keep) != n || anyNA(keep))
    stop("multichm_depth: keep needs one TRUE / FALSE per candidate", call. = FALSE)
  none <- rep(FALSE, n)
  if (closed && cfg$near_2d > 0) mcg_filter(cand, keep, none, dist_2d = cfg$near_2d, dist_3d = 0)
  else if (closed) mcg_filter(cand, keep, cand$layer == 1L, dist_2d = 3, dist_3d = 5)
  else mcg_filter(cand, keep, none, dist_2d = 3, dist_3d = 5)
}

# The feature table of a prepared clip must be its candidate table with the
# feature columns added: same rows in the same order (X, Y, Z, layer).
.mcd_check_feat <- function(prep, feat) {
  C <- prep$cand
  if (is.null(feat) || nrow(feat) != nrow(C))
    stop("multichm_depth: the feature table must have one row per candidate of the prepared ",
         "clip (mcd_features(prep$cand, las, frdens))", call. = FALSE)
  for (k in c("X", "Y", "Z", "layer"))
    if (is.null(feat[[k]]) || !identical(as.numeric(feat[[k]]), as.numeric(C[[k]])))
      stop("multichm_depth: the feature table's ", k, " differs from the prepared clip's ",
           "candidates (made from another clip, or reordered)", call. = FALSE)
  invisible(TRUE)
}

# Which candidates of a prepared clip a configuration accepts: a logical vector
# in the row order of prep$cand (and of feat, its feature table). A clip
# without candidates gives logical(0) before the cover is asked for.
mcd_accepted <- function(prep, feat, cfg) {
  cfg <- .mcd_check_config(cfg)
  .mcd_check_feat(prep, feat)
  if (!nrow(feat)) return(logical())
  g <- mcd_gate(feat, prep$cover, cfg)
  mcd_filter(feat, g$keep, g$closed, cfg)
}

# Detections of one configuration on a prepared clip (mcg_prepare) and its
# feature table (mcd_features): data.frame x = X, y = Y and z, in descending Z
# (the accepted candidates sorted by Z as mcg_apply sorts them); z = Z with
# report = "z" (the default), z = zrep with report = "zrep" (the filter still
# runs on Z, and the rows keep their order by Z). 0 rows when nothing is
# detected; a clip without candidates gives 0 rows under any configuration.
mcd_apply <- function(prep, feat, cfg, report = "z") {
  cfg <- .mcd_check_config(cfg)
  if (!is.character(report) || length(report) != 1L || !report %in% c("z", "zrep"))
    stop("multichm_depth: report must be \"z\" or \"zrep\"", call. = FALSE)
  acc <- mcd_accepted(prep, feat, cfg)
  if (report == "zrep" && length(acc) && is.null(feat[["zrep"]]))
    stop("multichm_depth: report = \"zrep\" needs the column `zrep` (mcd_features)",
         call. = FALSE)
  C <- data.table::as.data.table(feat)[acc]
  data.table::setorderv(C, "Z", order = -1L)
  z <- if (report == "z") C$Z else C$zrep
  det <- data.frame(x = as.numeric(C$X), y = as.numeric(C$Y), z = as.numeric(z))
  assert_detection_contract(det)
  det
}

## ---- the declared grid --------------------------------------------------------------------
# 240 configurations, config_id = row number: nested loops with cover_min
# {0.6, 0} outermost, then near_2d {0, 2.5, 3, 3.5}, lit_union {TRUE, FALSE},
# the floor pair (zmin, zmin_surface) {(5, 0), (5, 3), (5, 5), (3, 0), (3, 3)}
# and depth_max {4, 3, 2} innermost, each in that order. config_id 1 is
# k4_r0_z5_f0_l1_c0.6. A selection's ties go to the smaller config_id.
MCD_FLOORS <- data.frame(zmin = c(5, 5, 5, 3, 3), zmin_surface = c(0, 3, 5, 0, 3))
mcd_grid <- function() {
  g <- expand.grid(depth_max = c(4, 3, 2), floor = seq_len(nrow(MCD_FLOORS)),
                   lit_union = c(TRUE, FALSE), near_2d = c(0, 2.5, 3, 3.5),
                   cover_min = c(0.6, 0), KEEP.OUT.ATTRS = FALSE)   # first varies fastest
  g <- data.frame(config_id = seq_len(nrow(g)), depth_max = g$depth_max, near_2d = g$near_2d,
                  zmin = MCD_FLOORS$zmin[g$floor], zmin_surface = MCD_FLOORS$zmin_surface[g$floor],
                  lit_union = g$lit_union, cover_min = g$cover_min, stringsAsFactors = FALSE)
  g$label <- vapply(seq_len(nrow(g)), function(i) mcd_config_label(mcd_grid_config(g, i)),
                    character(1))
  g
}

# The configuration of row i of a grid table (mcd_grid()).
mcd_grid_config <- function(grid, i)
  mcd_config(grid$depth_max[i], grid$near_2d[i], grid$zmin[i], grid$zmin_surface[i],
             grid$lit_union[i], grid$cover_min[i])
