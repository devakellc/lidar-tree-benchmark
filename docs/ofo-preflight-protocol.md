# Open Forest Observatory stem maps: preflight protocol

Declared on 17 November 2026, before any registration test, clip freeze or
detector run on these plots. This stage is score-blind: no detector under
test is run and nothing is scored. It decides, per plot group, whether stem
maps of the [Open Forest Observatory data catalog](https://doi.org/10.5281/zenodo.23402904)
paired with public USGS 3DEP point clouds can extend the benchmark's field
reference. The findings are in the
[preflight results](../results/ofo-preflight-results.md).

An earlier catalogue check on 16 November 2026 counted plots, flights and
densities and ran a best-of-grid position diagnostic on 14 plots. That
diagnostic chose the best of 2,401 shifts per plot and is not a registration
method. It informed the rules below; none of its numbers is a result.

## Scope and separation

- Every output of this study lives under `<job>/ofo`, where `<job>` is
  `CLAUDE_JOB_DIR`. Nothing is written under `<job>/neon`. The sealed NEON
  root `neon/frozen_2021` is read, never written.
- Results on these plots are reported apart from the NEON results and are
  never pooled with them. Groups defined below are never pooled together.
- The 62 catalogue plots of project `NEON2023` are NEON plots already in the
  benchmark. They are excluded from every population here.
- A group marked go may have its reference written and its clips frozen to a
  new root. Detector runs start only after that, classical arms first.
- A change to a rule after its first use is a dated amendment in this file
  with its reason. Results obtained before the change stay reported.

## Sources

| Source | Use | Pin |
| --- | --- | --- |
| Catalogue record 23402904 on Zenodo | Plot polygons, tally rules, trees, licences, drone missions | MD5 of each file from the record |
| USGS 3DEP Entwine index (`resources.geojson`) | Which public point clouds cover a plot | Retrieval time and SHA-256 |
| USGS work-unit table (`WESM.csv`) | Quality level and collection window per work unit | Retrieval time and SHA-256 |
| 3DEP Entwine point clouds | Density, flight dates, canopy surface, later the clips | Resource URL per plot |
| Catalogue drone canopy height models | Disturbance check | Mission ID and URL per plot |
| SNODAS daily snow depth | Snow check for winter flights | File name and SHA-256 per date |

Retrieval times and digests are written to
[ofo-preflight-sources.json](ofo-preflight-sources.json).

## Plot groups and reference populations

A plot is first screened out when it is part of a nested hyperplot, was not
surveyed exhaustively, records no live or dead status, or has no diameter
floor (trees tallied by height alone). The live diameter floor is
`min_dbh_live` where given, otherwise `min_dbh`. Heights count as measured
when at least 90% of the plot's live stems of 10 cm diameter or more carry a
measured height (of all its live stems, where no such stem has a diameter).

| Group | Rule | Reference population |
| --- | --- | --- |
| A | Floor at most 10.2 cm, heights measured | Live stems of at least 10 cm diameter: the benchmark's `adopted` gate |
| B | Floor at most 10.2 cm, heights not measured | As A; no height gate, see below |
| C | Floor above 10.2 cm, heights measured | Overstory only: live stems at or above the group floor |
| D | Floor above 10.2 cm, heights not measured | Overstory only, no height gate |

- A stem is live when `live_dead` is `L` or `M`. Growth forms `tree` and
  `intermediate`, and stems without a growth form, count as trees; `shrub`
  does not.
- The group floor of C and of D is the largest live diameter floor among the
  group's admitted plots, so every plot of the group is complete above it.
- In groups C and D the reference is incomplete below the floor. A detection
  that matches no reference stem is therefore not always an error. These
  groups report recall of the overstory population as the headline and
  precision only as a labelled lower bound.
- Trees recorded below a group's gate stay in the full tree table and are
  never reference stems.

## Admitted flights

- Only 3DEP work units of quality level 1 or better with a public Entwine
  resource are admitted.
- Flight dates come from the GPS times of the returns inside the plot, not
  from the work-unit window. The time gap is the absolute difference between
  flight year and survey year and must be at most four years, the
  benchmark's limit. Survey dates are approximate for nearly every plot, so
  the gap is not resolved below a year.
- Returns of classes 7 and 18 are dropped. All-return and first-return
  density are measured inside the plot polygon over its geodesic area and
  reported separately.
- The flight must cover the plot: at least 99% of the 5 m cells of the
  polygon buffered by 25 m hold a return.
- When several flights qualify, the order is better quality level, smaller
  gap, later flight, then work-unit name. One flight serves a plot; flights
  are never mixed in a clip. A plot whose returns span more than 365 days is
  not admitted.
- Density rungs follow the benchmark: a rung at or above a plot's native
  all-return density is not produced. The 3DEP clouds are about twice as
  dense as NEON's, so the native rung is not compared across sources.

## Frames

Catalogue positions are WGS 84 longitude and latitude. Each project takes one
UTM frame, the zone of its median plot longitude (EPSG:32610 or EPSG:32611),
and all its plots use it, including plots just across 120° W. The 3DEP
resources are in EPSG:3857; points are reprojected to the project frame on
extraction and no metric quantity is computed in EPSG:3857. The difference
between the WGS 84 and NAD83(2011) realizations, about 1 to 1.5 m here, is
not resolved from metadata. The registration step absorbs it.

## Geometry audit

Per plot and per project the audit reports polygon validity, polygon area
against `plot_area_ha`, the share of stems outside the polygon and how far
outside, duplicate positions, overlap between plots, hyperplots and subplots.

- A plot is geometry-consistent when at least 95% of its reference stems lie
  inside the polygon buffered by 1 m. Other plots are held.
- A stem outside its plot polygon is never a reference stem.

## Registration

The catalogue states that plots are within about 10 m of true position; the
benchmark matches at 4 m. Each plot therefore gets one rigid shift, estimated
without any detector under test, from the agreement between the stem map and
the canopy surface of the admitted flight.

**Surface.** The native cloud is height-normalised with a TIN of its
classified ground. A 0.5 m raster holds the highest return per cell (0.2 m
subcircle, empty cells 0). The local canopy top `M` is the moving maximum of
that raster over 5 × 5 cells.

**Signals.** For a shift `s`, `M_i(s)` is `M` at stem `i` moved by `s`.

- *Height signal*, for plots with measured heights. Stems: live, measured
  height at least the larger of 10 m and the plot's median measured live
  height. Objective: the share of stems with `|M_i(s) - h_i|` at most the
  larger of 2 m and 15% of `h_i`.
- *Diameter-rank signal*, for plots without measured heights. Stems: the
  plot's reference stems. Objective: the Spearman rank correlation between
  diameter and `M_i(s)`.

**Estimate.** Shifts run over ±12 m in both axes at 0.5 m steps (2,401
shifts). The estimate is the shift with the highest objective; ties go to the
shortest shift.

**Residual.** The stems are split into two random halves 20 times, with seeds
from `seed_for("registration", plot, NA, k)` for `k` in 1 to 20. Each half
gives its own estimate. The residual is the median distance between the two
estimates over the 20 splits.

**Contrast.** The contrast is the objective at the estimate minus the median
objective over all shifts. A flat objective has no contrast, whatever the
tie rule returns.

**Acceptance.** A plot is registered when it has at least 15 signal stems,
its estimate is not on the edge of the search window, its contrast is at
least 0.10 and its residual is at most 2.0 m. A plot that is not registered
is not scored, at any shift.

**Positional uncertainty.** Every stem of a registered plot carries a
`pos_unc` equal to the larger of 0.5 m and the plot's residual.

### Tests of the registration

The method above is fixed before these tests and is not tuned on them.

1. **Known truth.** The NEON plots of the benchmark's `adopted` population
   are registered against their own native clips from the sealed root. NEON
   stems and NEON clouds share a frame, so their true shift is zero. Because
   ties go to the shortest shift, a zero truth would flatter the method, so
   each plot's stems are first displaced by a known offset, drawn uniformly
   within ±8 m in each axis with seed `seed_for("offset", plot, NA)`. The
   error is the distance between the estimate and the shift that undoes the
   offset. Both signals are run on every plot with at least 15 signal stems;
   the diameter-rank signal ignores the heights. A signal passes when at
   least 20 plots are accepted, the median error of accepted plots is at
   most 1.0 m, and at least 90% of accepted plots have an error of at most
   2.0 m. Errors of rejected plots and errors by stem count are reported
   too.
2. **Held-out catalogue plots.** Catalogue plots that fail the population
   rules, and so are never scored, are registered with the same method on
   their best available flight, admitted or not. Where no live or dead
   status was recorded, every stem counts as live for this test only.
   Shift, residual and acceptance are reported per plot.
3. **Agreement of the two signals.** On catalogue plots with measured
   heights where both signals are accepted, the two estimates must lie
   within 2.0 m of each other on at least 80% of the plots, and there must
   be at least 10 such plots.

The height signal is admitted when it passes test 1. The diameter-rank
signal is admitted when it passes tests 1 and 3. A group whose signal is not
admitted is no-go. Once a signal is admitted, the candidate plots are
registered with it, and shift, residual and acceptance are reported for
every plot.

## Disturbance, snow and leaf-off

- **Disturbance.** Among drone missions whose footprint covers the plot and
  whose camera pitch is at most 10° from nadir, the one closest in time to
  the survey is used. Its point-cloud canopy height model and the 3DEP
  canopy height are reduced to the maximum per 5 m cell inside the plot. A
  canopy cell is at least 5 m tall. The loss share is the share of canopy
  cells of the earlier surface whose later height is below half the earlier
  height. The reverse share, computed the other way round, measures
  disagreement that cannot be canopy loss. A plot is unresolved when the
  reverse share exceeds 0.10, and otherwise disturbed when the loss share
  exceeds 0.10.
  The check covers the interval between flight and survey when the drone
  mission lies within one year of the survey or beyond it. Disturbed and
  unresolved plots are held. A plot without a usable drone model is admitted
  only when flight and survey fall in the same calendar year.
- **Snow.** For flights between 1 November and 30 April, the SNODAS snow
  depth at the plot centroid is read for each flight date. The plot is
  admitted when the depth is zero on every date and held otherwise.
- **Leaf-off.** Flights between 15 October and 30 April are leaf-off for
  winter-deciduous species. A plot is held when such species make up 10% or
  more of its reference stems.

## Scoring cells

Plots run from 0.04 ha to 4 ha. Each registered plot is cut into square
cells of 40 m, the core of a NEON tower plot, so that clips, edge effects
and the six-stem gate match the benchmark and its arms run unchanged.

- Cells lie on a grid aligned with the project frame. The grid offset is the
  one, among multiples of 5 m in each axis, that admits the most cells; ties
  go to the smallest offset in x, then y.
- A cell is admitted when at least 99% of its area lies inside the
  registered plot polygon. Its reference stems are the plot's reference
  stems inside both the cell and the polygon.
- A cell enters the headline population when it holds at least six
  reference stems. Cells with fewer form the `relaxed` sensitivity
  population.
- Each cell is clipped with the benchmark's 25 m buffer. Stems and area
  outside the admitted cells are reported as unscored.
- Counts are summed over cells within a project and within a group; rates
  are never averaged. Every pooled row is shown beside its per-project rows,
  and intervals resample whole plots, not cells.

## Reference schema

The tree table is mapped to the columns of `ground_truth_stems.csv`, one
table per project, with one row per reference-eligible stem.

| Column | Source |
| --- | --- |
| `individualID` | `OFO.<plot_id>.<n>`, `n` the row order of the tree within its plot in the pinned file |
| `plotID` | Scoring cell, `<plot_id>_<k>` |
| `E`, `N` | Catalogue position in the project frame plus the plot shift |
| `pos_unc` | The larger of 0.5 m and the plot's registration residual |
| `height` | Measured `height` only; `height_allometric` is never copied in |
| `stemDiameter` | `dbh` |
| `maxCrownDiameter`, `ninetyCrownDiameter` | Larger and smaller of the two crown widths, where recorded |
| `canopyPosition`, `crown_class` | `crown_position` 1 and 2 dominant, 3 codominant, 4 intermediate, 5 suppressed |
| `live`, `is_tree` | Rules of the plot groups above |
| `meas_year`, `acquisition_year` | Survey year and flight year |

Where `crown_position` is missing and heights are measured, the crown class
falls back to within-plot height quantiles, as for NEON, and is labelled as
a fallback. Where both are missing the stem has no crown class.

## Missing heights

In groups B and D the scorer's height-consistency gate cannot run, so stems
match on position alone. Height bands, height error and crown class are not
reported for them. Their results always carry the label "no height gate"
and are never pooled with groups A or C. Group A is also scored once with
its heights withheld, so the effect of the missing gate can be read there.

## Plots outside the public 3DEP clouds

For plots with no admitted 3DEP flight on the Oregon and Washington coast,
state and federal sources are checked from metadata only: collection,
year, stated density or quality level, access and licence. No point cloud
is acquired here. A plot gains a flight only through an amendment that
names the collection and applies every rule above to it.

## Licences and independence

Licences are per plot and are recorded with each plot. Derived reference
tables are redistributed only for plots under CC BY 4.0, CC0 or the public
domain, with attribution to the contributors and acknowledgment of the
catalogue. For share-alike and non-commercial plots the archive holds plot
shifts, cell definitions and tree identifiers, and a script rebuilds the
tables from the catalogue record. The 3DEP clips are public domain.

Plots flagged `withhold_from_training` are reserved by the catalogue for
model testing; this study only evaluates. A learned arm is run only after
its training data have been checked against the catalogue, because field
points from this catalogue are part of at least one public training set.

## Decision per group

A group is **go** when all of these hold:

1. Its registration signal is admitted.
2. At least three of its plots are admitted on every rule above and
   registered, and their headline cells hold at least 100 reference stems.
3. Its licences allow the planned use and archive handling.

A group is **hold** when it fails only for checks that could not be made,
and **no-go** otherwise. Hold and no-go authorise nothing further.

## Amendment 1: registration redesign (17 November 2026)

**Reason.** The registration declared above failed its known-truth test for
both signals (8 and 5 accepted plots, median errors of 1.9 m and 2.9 m). No
signal was admitted, so under the rules above every group is no-go. Those
results stay reported. Two faults of the declared method were identified
from the test, not from any catalogue result:

- The moving maximum and the height tolerance make the objective flat near
  its top, and ties went to the shortest shift. The estimate was therefore
  pulled toward zero by up to the width of the flat top, and both halves of
  a split shared the pull, so the residual did not see it.
- NEON plots are small. Few reach 15 signal stems, while most catalogue
  plots hold from 60 to several hundred. The test said little about plots
  of catalogue size.

This amendment was written after that test and before any work on a new
method. The method stays score-blind: one rigid shift per plot, from stem
positions with heights or diameters and the canopy surface of the admitted
flight, and no detector under test.

**Development and confirmation plots.** The 106 NEON plots of test 1 are
split in two. Within each site and plot type, plots are ordered by
`seed_for("split", plot, NA)`; odd ranks are development plots and even
ranks confirmation plots. Only pooled results of test 1 had been seen when
this split was declared, except for one named plot.

**Composite plots.** To test at catalogue stem counts with known truth,
plots of one site are also grouped into composites. Within each half and
site, plots ordered by `seed_for("composite", plot, NA)` form consecutive
groups of three; a remainder of one or two joins the last group. All member
plots of a composite are displaced by one common offset, and one shift is
estimated from their pooled stems, each plot on its own surface. Offsets are
drawn as in test 1, with seed `seed_for("offset2", unit, NA)`, where the unit
is the plot or the composite's first plot.

**Development.** The estimator, the acceptance gate and its thresholds, and
the smallest stem count a signal is used at are redesigned on the
development plots and their composites alone. Held-out catalogue plots may
be used for diagnostics that need no truth. The estimator must be
translation-equivariant: displacing the stems by an offset must move the
estimate by exactly the opposite, away from the window edge. The variants
tried and their development results are reported.

**Freeze.** The chosen estimator, gate, thresholds and smallest stem count
are written below as Amendment 1b before any confirmation unit is run.

**Confirmation.** The frozen method is run once on the confirmation plots
and their composites. A signal is admitted when, among confirmation units
at or above the frozen smallest stem count, at least 10 are accepted, the
median error of accepted units is at most 1.0 m, and at least 90% of them
have an error of at most 2.0 m. The accuracy limits are those of test 1; the
count is halved with the sample. The diameter-rank signal must also pass
test 3 with the frozen method. If a signal fails, it is not admitted and
its groups are no-go; no further redesign is made under this protocol.

**Use.** An admitted signal registers a catalogue plot only when the plot
has at least the frozen smallest stem count and passes the frozen gate.
Everything else in this protocol is unchanged.

## Amendment 1b: frozen registration method (17 November 2026)

The method below was chosen on the development half of Amendment 1 alone:
55 plots and 17 composites, each displaced by its known offset. No
confirmation unit was registered before this freeze. Its constants are
`OFO_REG2` in `scripts/ofo_registration_lib.R`. Their SHA-256
(`ofo2_config_digest()`) is
eede36eb4afc37a385dc3b204f0dcf660c29cc60bcf893293c8a546bb54803b6, and the
confirmation does not run unless this section quotes it.

**Surface.** As declared, the cloud is height-normalised with a TIN of its
classified ground, and a 0.5 m raster holds the highest return per cell
(0.2 m subcircle). Heights below 0 count as 0. An empty cell takes the mean
of its non-empty neighbours in 3 × 3 cells, and is 0 when it has none. The
surface has no moving maximum and no smoothing.

**Stems.** The height signal uses every live tree with a measured height,
not only the tall half. The diameter signal uses the reference stems with
their diameters and ignores heights. A composite pools the stems of its
member plots, each member on its own surface.

**Stem map.** Each stem is drawn on the surface's cells as a paraboloid
crown, `a · max(0, 1 − d²/r²)`, where `d` is the distance from the stem.
Where crowns overlap, the map keeps their maximum. For the height signal,
`a` is the height and `r` is the larger of 1 m and 0.5 m plus a tenth of the
height. For the diameter signal, `a` is the diameter and `r` is 2 m. The
mask holds every cell whose centre lies within 4 m of a stem.

**Objective.** The search runs over the declared 2,401 shifts: ±12 m in
0.5 m steps. For each shift, the objective is the Pearson correlation over
the mask cells between the stem map and the surface moved by that shift.
Outside the cloud the surface counts as 0. For a composite, six sums are
added over the members before the correlation is formed: the cell count,
the map, its square, the surface, its square, and their product.

**Estimate.** The estimate is the shift with the highest correlation. Each
axis is refined to the vertex of the parabola through that shift and its
two neighbours, by at most half a step. Exact ties take the centre of the
tied shifts. Displacing the stems by any multiple of the step moves the
estimate by exactly the opposite, as long as it stays off the window's
edge.

**Residual.** As declared, the stems are split into two random halves 20
times, with seeds `seed_for("registration", unit, NA, k)`. The residual is
the median distance between the two halves' estimates. The unit is the
plot ID, or for a composite `C-` followed by its first plot. The residual
sets `pos_unc`.

**Stability.** The stems are subsampled 20 times, each subsample holding
80% of them (rounded up), with seeds `seed_for("subsample", unit, NA, k)`.
Each subsample gives its own estimate. The stability `s90` is the 90th
percentile (type 7) of the distances from those estimates to the full
estimate.

**Acceptance.** A unit with fewer than 4 signal stems is not run. A unit is
registered when its estimate is off the window's edge, it has at least the
smallest stem count, and `s90` passes:

| Signal | Smallest stem count | Gate |
| --- | --- | --- |
| Height | 20 | `s90` at most 2.0 m |
| Diameter | 10 | `s90` at most 1.0 m |

The declared contrast and residual gates no longer apply.

**Selection.** The development sweep covered 2,652 configurations:

- 34 estimator variants: tolerance share, height kernel, size correlation,
  and cross-correlation with other radii, masks, amplitudes, surfaces and
  estimators;
- 13 gate thresholds on four gate statistics;
- 6 smallest stem counts.

Three limits on eligible configurations were set during development and
are accepted here. The estimate must be the peak, because a centre of the
near-maximal shifts was found not to be translation-equivariant. The gate
must use the residual or the stability, because statistics measured
against the whole window depend on where the truth lies in it. At least 10
development units must be accepted. Among configurations meeting a median
error of 0.8 m or less with at least 95% within 2 m, the one with the most
accepted units was taken.

- Height: 31 of 46 development units at 20 stems or more were accepted,
  with a median error of 0.73 m and 30 within 2 m. A smoothed surface tied
  at 31 accepted units; the raw surface was kept as the simpler.
- Diameter: no configuration met those margins. Among those meeting the
  confirmation limits, the one with the highest bootstrap chance of passing
  was taken (0.90; this figure is optimistic). 30 of 61 development units
  were accepted, with a median error of 0.96 m and 29 within 2 m.

The one failure of each signal is plot ABBY_062. Under both signals its
stems sit about 3 m from the canopy.

**Known limits of the confirmation, stated before it is run.** A NEON stem
map that is truly offset from its canopy counts as an error of the method.
A composite contains plots that are also units, so the units are not
independent. Offsets of up to 8 m put the truth off-centre in the window,
unlike catalogue plots. Under this method both signals share the surface
and most stems, so test 3 says less than it did. The pass rule is applied
as declared all the same.

## Amendment 2: withheld returns (17 November 2026)

**Reason.** A review of this study, made after the confirmation, found that
the catalogue clouds had been measured with the returns flagged withheld.
The benchmark's other LiDAR readers drop those returns, and on some plots
they are a large share of the cloud.

**Rule.** Returns flagged withheld are dropped, like classes 7 and 18,
wherever a catalogue cloud is read or measured: densities, coverage, flight
dates, and the canopy surfaces of the registration and of the disturbance
check. The stored clouds keep the flag. The NEON clips of the registration
tests are not affected, so those tests stand as run.

## Corrections (17 November 2026)

The same review found the points below. None changes a rule; each is
recorded here instead of editing the dated text above.

- Amendment 1 says that one named plot had been seen before the split. The
  plot is `ABBY_070`, quoted to the author as an accepted plot with a large
  error. The split placed it in the confirmation half.
- Amendment 1 says that few NEON plots reach 15 signal stems. That holds
  for the height signal (30 of 106 plots) and not for the diameter signal
  (64 of 106). What is rare is a plot of catalogue size: none reaches 60
  height stems and 8 reach 60 diameter stems.
- "Registration" says the catalogue places plots within about 10 m of true
  position. The catalogue's statement concerns its drone missions: plots
  are not necessarily co-registered with them and should lie within about
  10 m of them. It gives no bound against the 3DEP clouds.
- The snow rule reads the depth on each flight date. The first run read
  every day between the first and last return of a flight lasting up to
  seven days, and so held one plot for snow on a day without returns. The
  code now reads the days that have returns.
- Plot polygons had been stored with seven significant digits, which moved
  their boundaries by up to 0.5 m. They are now stored in full precision.
- The conditions table of the first run was computed before the final
  clouds were written. The catalogue, registration, conditions and decision
  stages now record digests of the tables they read, and the decision stage
  stops when they are stale. The collection search records none.
- The search for other public collections covered the plots of `OHDS2024`
  and `SSMT2024` without an admitted flight. That set was chosen by project,
  not by the declared scope of the Oregon and Washington coast: it includes
  inland `SSMT2024` plots, and the `DS2024` plots, which also have no
  admitted flight, were not searched.

Every table of the results was recomputed after these corrections, except
the collection table: that search ran on the earlier polygons, and its 14
plots are unchanged. The known-truth test, the development runs and the
confirmation were not rerun. The declared method's rows for catalogue plots
were recomputed, which turned its test 3 from a pass (15 of 18 plots) into
a fail (11 of 14); test 1 had already failed.
