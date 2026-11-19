# Depth-gated multichm: study protocol

This is the specification of the
[depth-gated multichm study](../results/multichm-depth-results.md), as it was
fixed before the runs it governs. The study asks whether a family of rules
that judges `multichm`'s deeper-layer peaks by their depth under the canopy
surface does at least as well as the declared `multichm_gated` arm on held-out
NEON plots, and what it does to the lowest reference trees. Like
`multichm_gated`, the family is post hoc and is not one of the paper's twelve
arms.

The specification was written in two working files on 18 November 2026. Their
text was copied into this document afterwards, when the study was added to the
repository.

| Part | Written | Before | SHA-256 of the working file |
| --- | --- | --- | --- |
| Specification | 15:25 | The first features (16:04) and the first scores of the family (16:20, calibration plots only) | `671ca6aac794ba8ae34688d75ae1717bc054d53265fd82791ef17bce186fbc4a` |
| Addendum 1 | 17:14 | The scoring of the validation plots (18:06) and the confirmation runs that followed it | `e9b854f821f2956538640057de6ff10af4a7654aa4fa2da1b8c532cd483924e7` |

The times are local file times of that day and the hashes are those of the
working files. No outside registry holds either. The study's record of its
selection (`declared_depth_config.json`) carries the two hashes.

## What had been seen

When the specification was written:

- **The gated arm on every NEON plot.** Every result of the
  [gated multichm study](../results/multichm-gated-results.md) and of its
  [confirmation tests](../results/multichm-gated-confirmation-results.md) had
  been read, the validation plots included: the scores of stock `multichm`
  and of the gated configurations by site, stand, density level and flight,
  and the peaks the share gate removes inside censused subplots. The three
  weaknesses the specification names come from those results.
- **The heights of the reference stems.** About 3% of the NEON reference
  stems are under 5 m and the lowest percent starts near 4 m. That is why the
  grid carries 3 m floors beside 5 m ones.
- **Plots outside the benchmark.** An exploratory look at 60 plots that have
  no field reference, with three ML segmenters as referees, suggested the
  family's form, its constants and its grid values.
- **No score of the family's rules on any NEON plot.**

The validation plots are therefore not untouched. They are the held-out plots
of the gated study, whose own exploratory passes had read them. The held-out
score of this study tests the selection within the family's grid, as the gated
study's did.

When the addendum was written, every calibration-plot result of the first run
had been read (the selection, its in-sample contrasts, the components and the
lowest-tree tables), and so had three reviews of the code. Of the validation
plots, only their identity and the features that do not depend on a
configuration had been computed.

## What is left out

The two blocks below are copied from the working files line for line, with
three kinds of passage left out and marked `[...]`:

- instructions to the implementers on which files to write and how to report
  back;
- a note on the workstation;
- in one sentence of the addendum, a description of plots outside the
  benchmark. Its replacement stands in square brackets.

Nothing that fixes a feature, a rule, the grid, the selection, an analysis or
a reading rule is left out or reworded. "The main session" is the author's
working session, and "agents" are the assistants that wrote the code from this
text. Paths under `work/` name the working files and the run outputs, which
are not in the repository.

## What came after

The configuration the arm uses, `k4_r0_z3_f3_l0_c0.6`, is not the selection
this protocol tests. It was chosen after the held-out results had been read.
The [report](../results/multichm-depth-results.md) says how, and marks every
result that concerns it as post hoc.

## Specification

```text
SPECIFICATION: multichm_depth (a depth-gated variant of the multichm_gated arm)
================================================================================
Written 2026-11-18 by the main session, before any NEON score of these rules
was computed. [...]

0. PURPOSE
----------
The declared multichm_gated arm (scripts/multichm_gated_lib.R, configuration
z5_s0.75_c0.6_e1_d8) keeps a deeper-layer candidate when the share of first
returns around its top is at least 0.75, and only in closed stands whose crown
spacing is at least 8 m; surface peaks skip the package's distance filter in
closed stands. Three weaknesses motivate this variant:
  - the 8 m switch is a step on a noisy per-clip statistic;
  - the first-return share depends on the flight (sensor, return multiplicity);
  - the exemption admits surface peaks at any distance from a taller top.
The variant judges each deeper candidate by how far it sits under the local
canopy surface (in metres), uses one horizontal spacing rule for all tops in
closed stands, and can report re-measured heights. The question: on NEON census
plots, is the best configuration of this family, selected on calibration plots,
at least as good as the declared arm on held-out validation plots, and what
does it do to the lowest reference trees?

1. HARD CONSTRAINTS
-------------------
  [...]
  - lidR on ONE thread (set_lidr_threads(1L)); parallelism by processes, at
    most 8 R workers in total. [...]
  - Follow the conventions of scripts/multichm_gated_lib.R and
    scripts/calval_multichm_gated.R (bootstrap header, KEY=VALUE arguments,
    pooling by summed counts, never averaged rates; plain R, data.table).
  - The grid, the features, the constants and the selection criterion below are
    FIXED. Do not tune them. If something is ambiguous or looks wrong, implement
    the literal text, and report the issue in your hand-back.

2. FEATURES (per candidate, independent of the configuration)
-------------------------------------------------------------
Candidates are those of mcg_candidates() / mcg_prepare() (columns X, Y, Z,
layer, ztop, share), made from the cell's normalized clip `las`.

  MCD_RADIUS    = 1      m
  MCD_MIN_FIRST = 8      expected first returns in the column
  MCD_GAP       = 1.5    m
  MCD_LIT_SHARE = 0.75
  MCD_LIT_DEPTH = 5      m

  frdens   first returns per m2 of the cell's clip (the value the gated study
           records per cell: column `frdens` of candidates.csv / clip$frdens)
  r_col    = max(MCD_RADIUS, sqrt(MCD_MIN_FIRST / (pi * frdens)))
  column   the clip's returns (every return number) with
           (x - X)^2 + (y - Y)^2 <= r_col^2
  col_top  = max z of the column
  depth    = col_top - Z            (Z: the candidate's layer value, as the
                                     package reports it)
  zrep     = top of the contiguous column: sort the column's returns with
             z > ztop ascending; start at ztop; while the next return is at
             most MCD_GAP above the current height, move to it; zrep is the
             last height reached (ztop if the first step exceeds MCD_GAP or
             nothing lies above ztop).
A candidate's own cell lies inside the column, so col_top >= ztop >= Z and
depth >= 0. If a column is empty all the same, col_top = ztop.

  mcd_features(cand, las, frdens) -> cand with r_col (one value), col_top,
  depth, zrep added. Exact arithmetic as written (binning on a grid is fine,
  the exact distance test must apply).

3. CONFIGURATION AND RULES
--------------------------
  mcd_config(depth_max, near_2d, zmin, zmin_surface, lit_union, cover_min)
    depth_max     > 0 (Inf allowed: no depth rule)
    near_2d       >= 0 (0: the declared arm's filter, see below)
    zmin          >= 0, floor of deeper candidates (layer > 1), every stand
    zmin_surface  >= 0, floor of surface candidates (layer 1), every stand
    lit_union     TRUE / FALSE
    cover_min     >= 0 (0: every stand counts as closed; a value above 1, Inf
                  included: no stand is closed)
  closed  <- cover >= cover_min  (cover: mcg_canopy_cover, prep$cover; an
             unknown cover with 0 < cover_min <= 1 is an error, as in the
             gated library)

  keep, every stand:
    surface candidate:  Z >= zmin_surface
    deeper candidate:   Z >= zmin, and in a closed stand also
                        ( depth <= depth_max
                          or ( lit_union and share is not NA
                               and share >= MCD_LIT_SHARE
                               and depth <= MCD_LIT_DEPTH ) )
  filter over the kept candidates in descending Z, exactly the order
  mcg_filter() uses (order(-Z, method = "radix") over the table's rows):
    closed stand, near_2d > 0:
        accepted iff no accepted top has d2 < near_2d^2 (horizontal only),
        whatever the candidate's layer. No 3-D rule, no exemption.
    closed stand, near_2d == 0:
        the declared arm's filter: a kept surface candidate is accepted
        unconditionally; a kept deeper candidate iff no accepted top has
        d2 < 3^2 and none has d2 + dz^2 < 5^2.
    open stand (any near_2d):
        the package rule for every kept candidate (d2 < 3^2 or
        d2 + dz^2 < 5^2 rejects); no exemption.
  detections: data.frame x = X, y = Y, z = Z in descending Z (report = "z",
  the default) or z = zrep (report = "zrep"; the filter still runs on Z).

  mcd_apply(prep, feat, cfg, report = "z"), mcd_gate(), mcd_filter(),
  mcd_config_label(cfg): "k<depth_max>_r<near_2d>_z<zmin>_f<zmin_surface>_l<0|1>_c<cover_min>"
  (numbers printed with %g).

  IDENTITIES (must hold on every cached cell; they are acceptance checks):
    A. mcd_config(Inf, 0, 5, 0, FALSE, 0.6) accepts exactly the candidates
       the gated configuration z5_s0_c0.6_e1 accepts.
    B. mcd_config(Inf, 0, 0, 0, FALSE, Inf) accepts exactly the stock set
       (MCG_STOCK).

4. GRID (mcd_grid(): 240 configurations, config_id = row number)
----------------------------------------------------------------
  cover_min              {0.6, 0}
  near_2d                {0, 2.5, 3, 3.5}
  lit_union              {TRUE, FALSE}
  (zmin, zmin_surface)   {(5, 0), (5, 3), (5, 5), (3, 0), (3, 3)}
  depth_max              {4, 3, 2}
Order: nested loops with cover_min outermost, then near_2d, lit_union, the
floor pair, depth_max innermost, each in the order listed (config_id 1 is
k4_r0_z5_f0_l1_c0.6). Ties in the selection go to the smaller config_id.

5. STUDY (scripts/calval_multichm_depth.R)
------------------------------------------
Inputs it reuses (read only):
  - the gated study's run: work/multichm_gated_runs/neon/multichm_gated/
    (candidates/*.rds with list(meta, prep, parity); candidates.csv;
    cells.csv with 530 cells x 447 gated configurations + chm_vwf;
    cells.config.json: K 200, TOL 4, population adopted, sealed root
    4567a247...; selection.csv, validation.csv, declared_config.json);
    its log work/multichm_gated_runs/calval.log shows how it was invoked
    (job directory work/multichm_gated_runs, 24 workers then; use <= 8);
  - scripts/calval_multichm_gated.R can be source()d without running
    (it ends with `if (sys.nframe() == 0L) run_main()`); reuse its cv_*
    helpers (cv_settings pattern, cv_jobs, frozen clips, cv_split, scopes,
    contrast rows) and the library's mcg_score_cell, mcg_null_offsets,
    mcg_pool, mcg_select, mcg_split, mcg_contrast.

Stages (STAGE=features|score|analyze|all), default OUT
work/multichm_depth_runs/neon/multichm_depth:

  features  For every cell of the gated candidates index: read the same
            frozen clip the candidates were made from (as cv_candidates_job
            does: frozen_clip(NULL, site, plot, rung, cx, cy, half, root),
            lidR::readLAS(clip$normalized)), compute mcd_features for every
            candidate, write OUT/features/<site>__<plot>__<rung>.rds
            (the candidate table with the feature columns, plus r_col and
            frdens) and OUT/features.csv (one row per cell: counts, r_col,
            quantiles of depth). Check that the clip gives back the cell's
            recorded number of candidates' source (npoints > 0) and that the
            candidate table read from the gated cache has the recorded
            n_cand rows.

  score     Every cell x every grid configuration, scored exactly as the
            gated study scores (mcg_score_cell with the cell's stems, K and
            TOL from the gated cells.config.json, the plot's
            mcg_null_offsets, memoised per detection set), plus four
            reference configurations re-derived through the gated library
            from the same candidates: "stock", "z5_s0_c0.6_e1",
            "z5_s0.75_c0.6_e1", "z5_s0.75_c0.6_e1_d8". chm_vwf rows are
            copied from the gated cells.csv (not re-scored).
            -> OUT/cells.csv with the gated cells.csv's columns where they
            apply (site, plot, plotType, rung, cover, top_height,
            crown_spacing, pdens, frdens, config, config_id, n_dominant ...
            n_suppressed, the 13 count columns) plus depth_max, near_2d,
            zmin, zmin_surface, lit_union, cover_min (NA on reference rows)
            and `family` ("depth", "gated", "chm_vwf"); OUT/grid.csv;
            OUT/cells.config.json (K, TOL, root, a digest of the grid and of
            the constants, the blind state, the gated run read).
            CHECK S1 (the stage stops when it fails): every re-derived
            reference row equals the gated cells.csv row of the same cell
            and label: the observed count columns exactly, the null means
            within 1e-9.
            BLIND RULE: with UNBLIND=0 (the default) the stage scores only
            the cells of the CALIBRATION plots of the headline split (seed
            1, frac 0.5; mcg_split / cv_split, the gated study's split). No
            validation cell of the depth family may be scored, printed or
            written before UNBLIND=1 is given. With UNBLIND=1 it scores the
            remaining cells and appends them.

  analyze   UNBLIND=0: the split (CHECK S2: its calibration and validation
            plot ids equal the gated study's, 57 and 49 plots); the
            selection: the grid configuration with the highest pooled
            chance-corrected F1 (cF1) at native density on the calibration
            plots (mcg_select; ties to the smaller config_id); in-sample
            tables on the calibration plots only: the selection against each
            reference (mcg_contrast, MT_N_BOOT draws, MT_SEED), the
            components (below), the calibration ranking of the grid (every
            configuration's pooled cF1, F1, precision, recall, det_per_ref),
            the lowest-tree tables (below) and the height tables (below).
            -> OUT/selection.csv, OUT/declared_depth_config.json,
            OUT/calibration.csv, OUT/grid_calibration.csv,
            OUT/components.csv, OUT/lowest_trees.csv, OUT/heights.csv,
            OUT/tables_blind.md.
            UNBLIND=1 adds, on the VALIDATION plots:
              a. primary contrast at native density, all five sites:
                 selection minus z5_s0.75_c0.6_e1_d8 (declared), metrics
                 cF1, F1, cPrecision, cRecall, precision, recall,
                 det_per_ref, with the paired plot-bootstrap interval;
              b. the same against stock, z5_s0_c0.6_e1, z5_s0.75_c0.6_e1
                 and chm_vwf;
              c. scopes: all sites, California (SJER, SOAP, TEAK),
                 Washington (WREF, ABBY), each site;
              d. the ladder: a and "minus stock" at rungs 8, 4, 2, 1;
              e. components on the validation plots;
              f. seeds 1..200: for each split, the selection on its
                 calibration plots and the point estimates of selection
                 minus declared and selection minus stock (cF1, F1, recall,
                 precision) on its validation plots; summary: median, share
                 of splits above 0, how often each value of each of the five
                 grid parameters is selected;
              g. leave one site out: select on the calibration plots of the
                 other four sites, contrast against declared and stock on
                 all plots of the held-out site;
              h. the lowest-tree tables and the height tables on the
                 validation plots.
            -> OUT/validation.csv, OUT/ladder.csv, OUT/seeds.csv,
            OUT/seed_summary.csv, OUT/site_out.csv, and OUT/tables.md with
            every table and the provenance text of section 7.

  Components (at the selected configuration S, native density): S minus S
  with one parameter changed to each other grid value (near_2d, depth_max,
  the floor pair, lit_union, cover_min), each a grid configuration.

  Lowest trees (native density): per-stem matches of stock, the declared
  gated configuration, S, and S with each other floor pair. Implement
  mcd_stem_matches(stems, det, cx, cy, half, tol) returning one row per
  reference stem (matched TRUE/FALSE) with the SAME matching score_plot()
  uses (scripts/sweep_lib.R: its region, greedy_match with heights and
  tol_z_up as score_plot calls it). CHECK S3: for every cell and
  configuration used, sum(matched) equals that row's TP in cells.csv.
  Tables: by field-height band of the reference stem ([0,5), [5,10),
  [10,20), [20,Inf), unknown height) and by crown class: stems, matched,
  recall, the mean matched over the K shifted copies (TP0 per band) and
  (TP - TP0) / (n - TP0); S minus declared and S minus stock per band with
  a paired plot-bootstrap interval (plots resampled within site, as
  mcg_contrast does). Also the height quantiles of the reference stems per
  site (min, 1%, 5%, 10%, median).

  Heights (native density, configuration S): for detections matched to a
  stem with a field height, the error (detection height minus field height)
  with z = Z and with z = zrep, by layer class (surface; deeper): n, mean,
  median, RMSE. And the contrast S reported with zrep minus S reported with
  Z (cF1, F1, recall, precision), scored like any other pair.

6. READING RULE (fixed before any score)
----------------------------------------
Primary: selection minus declared gated, cF1, native density, validation
plots of the five sites. "better": the 95% interval lies above 0; "not
worse": its lower bound is above -0.02; "worse": the interval lies below 0;
otherwise "inconclusive". Guard for the lowest trees: recall of reference
stems under 10 m (the two lowest bands pooled), selection minus declared,
reported with its interval; flagged when the interval lies below 0.

7. PROVENANCE (repeat in declared_depth_config.json and tables.md)
------------------------------------------------------------------
"The family's form, its constants and its grid values were informed by an
exploratory look at 60 plots outside the benchmark that have no field
reference (three ML segmenters as referees). No NEON score of these rules
was read before the features, the grid and the selection criterion were
fixed (work/multichm_depth/SPEC.txt). The split, the scoring and the
reference configurations are those of the multichm_gated study, whose own
provenance stands. Validation cells of the depth family were scored only
after the code had been reviewed (UNBLIND=1)."

8. ACCEPTANCE
-------------
Library agent:
  L1 identities A and B on ALL 530 cached cells (accepted row sets equal
     mcg_filter's for the matching gated configuration); report the counts.
  L2 unit tests (testthat, run with `Rscript tests/run_tests.R` or the
     harness's way of running one file; say which you used): configuration
     validation and label; grid: 240 unique labels, ids 1..240, the declared
     order (config_id 1, 2, 4, 16 ... spot values written in the test);
     features on a hand-computable synthetic cloud (depth, zrep with a gap
     just under and just over MCD_GAP, r_col at frdens 16, 2 and 0.5); the
     filter on a hand-made candidate table (a pair exactly near_2d apart is
     accepted, just under is rejected; the exemption path at near_2d 0; the
     open-stand path); floors in open and closed stands; lit_union with an
     NA share; report = "zrep".
  L3 mcd_features equals a brute-force computation on three real cells of
     different sites and rungs (max abs difference 0).
Study agent:
  S1, S2, S3 as above (on the calibration cells while blind).
  S4 a blind run of all stages on the five sites; then report the selection
     and the calibration tables. Do NOT run UNBLIND=1.
  Unit tests of the pure helpers (blind filter of cells, stem matches on a
     hand-made plot, band assignment, the components' neighbours).
Both: the existing tests of the gated arm must still pass
(tests/testthat/test-multichm-gated-lib.R at least); say what you ran.

9. HAND-BACK
------------
[...]
```

## Addendum 1

```text
ADDENDUM 1 to work/multichm_depth/SPEC.txt (multichm_depth)
================================================================================
Written 2026-11-18 by the main session, AFTER the blind calibration run and the
three code reviews had been read, and BEFORE any validation cell of the depth
family was scored (UNBLIND=1 has never been run; OUT/cells.csv holds the 57
calibration plots only, sha256 656c38cc...). SPEC.txt (sha256 671ca6aa...)
stays as stamped; where this addendum and SPEC.txt differ, this addendum wins.

What had been seen when this was written: every calibration-plot (in-sample)
result of the blind run, among them the selection S = k4_r2.5_z5_f5_l0_c0.6
(config_id 52), its in-sample contrast against the declared gated arm
(+0.022 [+0.007, +0.036] cF1), the components and the lowest-tree tables of
the calibration plots. Nothing of a validation plot but its identity and its
configuration-independent features.

A1. THE BLIND SPLIT IS NOT AN ARGUMENT
--------------------------------------
The headline split is the gated study's: seed and calibration fraction as
recorded in the gated run's declared_config.json (seed 1, frac 0.5). The
driver takes them from that file. SEED= and FRAC= are accepted only when they
equal the recorded values; any other value stops the run, whatever UNBLIND is.
SEEDS= (analysis f) is unchanged. cells.config.json records the split's seed
and frac; the analyze stage and the UNBLIND=1 append stop when the record's
seed, frac or plot sets differ from the headline split's.

A2. READING RULE: PRECEDENCE
----------------------------
Section 6 left one case open (an interval wholly below 0 whose lower bound is
above -0.02). The outcomes are evaluated in this order:
  "better"        the 95% interval lies above 0            (lower > 0)
  "worse"         the interval lies below 0                (upper < 0)
  "not worse"     its lower bound is above -0.02           (lower > -0.02)
  "inconclusive"  otherwise
So an interval wholly below 0 reads "worse" whatever its lower bound; when the
lower bound is above -0.02 the tables add "(within the 0.02 margin)". A scope
with fewer than 10 plots is reported and not read.

A3. LOWEST TREES: HOW THE GUARD IS READ
---------------------------------------
The review showed that on the calibration plots 80 to 96% of the matches of
reference stems under 10 m are chance matches (the shift null gives 0.15 to
0.27 "recall" under 5 m and 0.35 to 0.38 at 5 to 10 m to every configuration),
so raw recall of low stems follows the number of detections.
  a. The guard of section 6 stays as fixed: raw recall of reference stems
     under 10 m, selection minus declared, on the validation plots, flagged
     when its interval lies below 0.
  b. Read with it, from numbers the analysis already computes: the same
     contrast in chance-corrected recall, (TP - TP0) / (n - TP0), with its
     interval, and the change in null recall TP0 / n.
  c. Reading: the selection "loses low trees" only when the chance-corrected
     contrast's interval lies below 0. A flag in (a) with a chance-corrected
     interval that spans 0 reads "fewer chance matches, no detectable loss".
  d. Per configuration of the lowest-tree tables and per height band ([0,5),
     [5,10), [0,10), [10,20), [20,Inf)): the chance-corrected recall with a
     95% interval of the same plot bootstrap (plots resampled within site,
     counts summed, MT_N_BOOT draws, MT_SEED). A configuration "finds the
     band's trees above chance" when that interval lies above 0. This is the
     statement about how low each configuration finds trees.

A4. THE LOW-FLOOR SIBLING (secondary)
-------------------------------------
S_low: among S and its four floor-pair siblings (S's other four parameters
kept), the configuration with the highest chance-corrected recall of
reference stems under 10 m on the CALIBRATION plots at native density; ties
to the smaller zmin, then to the smaller zmin_surface. When that is S itself
there is no S_low and the analyses below are skipped. (On the blind run it is
floor 3/3: k4_r2.5_z3_f3_l0_c0.6, config_id 58; the driver derives it, it is
not hard-coded.)
On the validation plots, added to the unblinded analyses:
  - S_low minus declared, minus stock and minus S: the metrics of analysis a,
    native density, every scope (analysis tag "low_floor"), and down the
    ladder in the scopes analysis d uses;
  - lowest-tree contrasts per stratum (raw and chance-corrected recall):
    S_low minus declared, S_low minus S, S_low minus stock.
Reading: S_low is offered as "the lowest-tree variant" when (i) S_low minus
declared in cF1 at native density over the five sites reads "better" or "not
worse" (A2), and (ii) the chance-corrected recall of stems under 10 m, S_low
minus S, has an interval above 0. With (i) and not (ii), the floor is reported
as a matter of what counts as a tree, not of accuracy. Without (i), no
low-floor variant is offered.

A5. CLOSED AND OPEN STANDS (secondary scopes)
---------------------------------------------
Two more scopes for analyses a and b (and for A4): "Closed stands", the plots
whose native cell has cover >= 0.6, and "Open stands", the others (cover as
recorded in cells.csv for the native rung). They are plot sets, used at
native density only. Descriptive: the family's rules beyond the floors act in
closed stands only.

A6. LITERAL BEHAVIOURS KEPT (no code change, no score changes)
--------------------------------------------------------------
  - Section 2's claim "col_top >= ztop >= Z, depth >= 0" is wrong for
    candidates whose ztop fell back to Z at the clip's edge (9 of 325,118
    candidates in 5 cells, all at least 20.7 m outside the scored window).
    The formula depth = col_top - Z stays literal; such a depth is negative.
  - Comparisons with MCD_GAP, depth_max and MCD_LIT_DEPTH are made in double
    precision on the stored heights; at decimal-exact ties (6 zrep climbs, 8
    depths over all cells) the result can differ from decimal arithmetic. No
    accepted set changes with either reading on this grid.
  - "Every return" of the column includes noise classes (class 7 in 177
    clips); the candidates were made from the same unfiltered clips. No
    accepted set of the 240 configurations changes without them.
  - The driver needs the working-tree version of calval_multichm_gated.R (the
    confirmation campaign's uncommitted changes).

A7. ROBUSTNESS FIXES TO THE DRIVER (no score changes)
-----------------------------------------------------
Features carry the constants' digest and are refused when it differs or when
r_col is not mcd_col_radius(frdens); a missing SPEC.txt or addendum stops the
analyze stage; a stale s3_failures.csv is removed after a pass; the cells
check counts chm_vwf rows; tests pin the selection criterion (cF1, not F1),
the blind check of the analysed cells and the score memo's key. A blind
re-run after these fixes must reproduce cells.csv byte for byte and the
selection, the calibration contrasts, the components and the ranking exactly.

A8. CONFIRMATION ON OTHER DENSITIES AND FLIGHTS (after UNBLIND=1)
-----------------------------------------------------------------
Fixed configurations, never re-selected: S, S_low (if any), the declared
gated arm, stock. Same scorer, K, TOL, null and bootstrap as the study.
  T1  Density ladder: analysis d (rungs 8, 4, 2, 1) on the validation plots.
  T2  QL2 level: the confirmation campaign's frozen QL2 clips of the 106
      plots (work/multichm_gated_confirmation/ql2, rung 3.2).
  T3  Washington, another year's flight: the campaign's 2019 clips of 56
      plots against the stems live in both epochs
      (work/multichm_gated_confirmation/epoch_wa/epoch_2019), with the same
      stems on the 2021 clips beside it (.../shared_2021).
  T4  California sparse flights (.../sparse_ca: 2017 and 2018, 39 plots,
      pooled), with the same stems on the 2021 clips beside it.
Contrasts on each: S minus declared (primary), S minus stock, S_low minus
declared, in cF1 with the other metrics of analysis a. Plot subsets: the
plots of the headline VALIDATION half (primary: the calibration half took
part in the selection, on other clips of the same plots and stems) and all
plots (secondary). Scopes as each dataset has them (five sites, California,
Washington, each site); a scope under 10 plots is reported and not read.
Reading (A2 on each primary contrast): the selection "carries over" when it
is "better" or "not worse" against the declared arm on T2 and on T3 and
"worse" on none of T1 to T4, in either subset. Otherwise the result is
stated for the 2021 native clips only, with the failing tests named.
[Plots outside the benchmark] have no field reference;
their re-check with S is descriptive and decides nothing here.

A9. PROVENANCE (added to the text of section 7, repeated in the outputs)
------------------------------------------------------------------------
"The precedence of the reading rule, the chance-corrected reading of the
lowest-tree guard, the low-floor sibling, the closed- and open-stand scopes
and the confirmation datasets were fixed in
work/multichm_depth/SPEC_ADDENDUM_1.txt after the blind calibration results
and the code review had been read, and before any validation cell of the
depth family was scored."
```
