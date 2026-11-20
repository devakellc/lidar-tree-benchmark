# NEWFOR Alpine validation of gated multichm: protocol

Fixed on 19 November 2026, after the release was inventoried and before any
tree detector was run on it. It was amended once the same day, still before any
detector ran, after the code was reviewed against it; the
[last section](#amendments-before-the-run) lists what changed. The report that
follows it links back here; this file is not edited once the detectors have
run.

## Question

The [gated multichm study](../results/multichm-gated-results.md) selected the
thresholds of `multichm_gated` on NEON plots in California and Washington.
NEON's field census covers part of each plot, so its precision is bracketed,
not measured. The NEWFOR benchmark supplies fully callipered plots in Alpine
forest. This study asks whether the declared gated configuration detects trees
better than stock `multichm` there, on identical plots, stems and matching.

The arm stays post hoc and outside the paper's twelve. No threshold of the arm
is tuned here.

## Release

Monnet and Eysn, *Airborne laser scanning single tree detection NEWFOR
benchmark dataset*, Recherche Data Gouv, version 1.0, released 17 March 2023,
[doi:10.57745/BXJBVH](https://doi.org/10.57745/BXJBVH), Etalab Open Licence
2.0. It holds 123 files for 14 study areas of the benchmark of
[Eysn et al. (2015)](https://doi.org/10.3390/f6051721): a point cloud, a
terrain raster, an inventory shapefile, a scoring polygon and a plot sheet per
area. Areas 05 and 12 to 14 of the paper are not in the release. The download
is checked against the repository's MD5 of every file and recorded with
SHA-256. The data are not redistributed here.

Facts transcribed from the plot sheets and the paper are in
[newfor-area-metadata.json](newfor-area-metadata.json).

## What was looked at before this protocol was fixed

Only inputs, never a detector's output or a score:

- the file list and checksums, the plot sheets and the paper;
- every inventory field, its range and the stems outside the polygon;
- cloud headers, return numbers, class codes and point densities;
- heights above the released terrain, their upper tail and, where a ground
  class exists, its residual against the terrain;
- the registration diagnostic defined below, on every area;
- the first-return density range of the NEON clips the arm was developed on.

The admission thresholds below were set with those values in view. They were
set without any detection.

## Study areas

Dates are year and month; the gap is flight minus field survey.

| Area | Forest | Country | Polygon | Field | Flight | Gap (months) | Caliper (cm) |
| --- | --- | --- | --- | --- | --- | ---: | ---: |
| 01 | Saint-Agnan | France | rectangle, 1.01 ha | 2010-07 | 2010-09 | +2 | 7.5 |
| 02 | Cotolivier | Italy | circle, 0.13 ha | 2012-11 | 2012-07 | −4 | 4 |
| 03 | Cotolivier | Italy | circle, 0.13 ha | 2013-06 | 2012-07 | −11 | 4 |
| 04 | Cotolivier | Italy | circle, 0.13 ha | 2012-10 | 2012-07 | −3 | 4 |
| 06 | Montafon | Austria | square, 0.25 ha | 2009-06 | 2011-09 | +27 | 10 |
| 07 | Pellizzano | Italy | circle, 0.13 ha | 2013-08 | 2012-09 | −11 | 5 |
| 08 | Pellizzano | Italy | circle, 0.13 ha | 2013-08 | 2012-09 | −11 | 5 |
| 09 | Asiago | Italy | circle, 0.13 ha | 2012-10 | 2012-07 | −3 | 5 |
| 10 | Asiago | Italy | circle, 0.13 ha | 2012-10 | 2012-07 | −3 | 5 |
| 11 | Asiago | Italy | circle, 0.13 ha | 2012-10 | 2012-07 | −3 | 5 |
| 15 | Leskova dolina | Slovenia | circle, 0.20 ha | 2008-11 | 2009-10 | +11 | 10 |
| 16 | Leskova dolina | Slovenia | circle, 0.20 ha | 2008-11 | 2009-10 | +11 | 10 |
| 17 | Leskova dolina | Slovenia | circle, 0.20 ha | 2008-11 | 2009-10 | +11 | 10 |
| 18 | Leskova dolina | Slovenia | circle, 0.20 ha | 2008-11 | 2009-10 | +11 | 10 |

The Montafon plot sheet lists two flights, 2004 and 2011. Table 1 of the paper
gives September 2011 at 22 points/m², which the released cloud's density
matches. Only the Saint-Agnan sheet says that dead trees were not inventoried;
the other sheets do not say. The inventories carry no status, species or
identifier field, so live status cannot be filtered.

## Inputs

One clip per area, built once and sealed with SHA-256 in a root of its own. No
arm reads the raw release, and nothing is written to the NEON roots.

- **Extent.** The bounding box of the scoring polygon, widened by 25 m on
  every side, as the NEON clips are (plot core plus 25 m). Where the cloud
  ends sooner, the clip ends with it, and the reach beyond the polygon's
  bounding box is recorded per side.
- **Points dropped.** Classes 7 and 18, points flagged withheld, and points
  where the terrain raster has no value.
- **Heights.** Elevation minus the released terrain raster, read by bilinear
  interpolation at each point. The clouds' ground class is not used: Montafon
  has none, and in Leskova dolina class 2 is not ground. Points below −1 m or
  at 80 m and above are dropped, as in the NEON clips.
- **Order.** The canonical point order and coordinate snapping of the NEON
  frozen clips, on one lidR thread.
- **CRS.** The plot sheet's projected system is assigned to the clip and the
  polygon. No coordinate is transformed. The released clouds and shapefiles
  carry none.
- **Density.** First-return and all-return density are measured twice: inside
  the scoring polygon, and over the clip. The clip's area is that of the convex
  hull of its points: the Leskova dolina clouds are discs of about 50 m radius
  and Montafon's is irregular, so they leave the corners of their boxes empty.
  The clip-wide first-return density sets the detector's raster resolution, as
  on NEON (0.25 m at 8 first returns per m² or more, otherwise 0.5 m).

## Reference

- **Units.** `DBHRef` is in metres in all 14 files, although the plot sheets
  describe centimetres or millimetres. Each file's range fits its caliper
  threshold only in metres (Saint-Agnan: 0.07 to 0.77 at a 7.5 cm threshold).
  Diameter in centimetres is `100 × DBHRef`, rounded to six decimals.
  `HRef` is in metres.
- **Inside.** A stem counts when the scoring polygon covers it, boundary
  included. Stems outside are counted in the admission table and not scored,
  as in the benchmark paper.
- **Primary population.** Stems inside with a diameter of at least 10 cm and a
  positive height: the benchmark's adopted gate without the live filter, which
  the data cannot support.
- **Inventoried population.** Every stem inside with a positive height,
  whatever its diameter. It is a sensitivity row: against a complete inventory
  a detection without a stem is a commission.
- **Missing diameter.** A diameter of zero or less is missing. Such a stem is
  outside the primary population and inside the inventoried one.
- **Crown class.** None is recorded. Recall is reported by height band
  instead, as the benchmark's scoring cuts the bands: up to 8 m, above 8 m up
  to 15 m, above 15 m.

## Registration diagnostic

Independent of any detector. For each area:

1. A canopy raster at 0.5 m holds the highest first return of each cell of the
   clip. The canopy top at a position is the maximum of that raster within
   1.5 m.
2. A primary stem is locally dominant when no primary stem within 4 m is
   taller.
3. For every offset on a 0.5 m lattice within ±8 m in x and y, the statistic
   is the mean absolute difference between field height and canopy top at the
   offset position, over the locally dominant stems.
4. The estimated offset minimises the statistic. Ties go to the shortest
   offset. An area with fewer than three locally dominant stems gets no
   estimate.

The paper states a plot location accuracy of ±2.0 m after its authors'
manual co-registration to the canopy model. The estimate has a lattice step of
0.5 m and a flat minimum on several plots, so it is not used to correct the
primary positions.

## Admission

An area enters the primary pool when all of these hold. Every area is run and
reported; an area that fails is kept out of the pooled contrasts and shown on
its own.

| Rule | Criterion |
| --- | --- |
| Files | All files present; MD5 equals the repository's. |
| Returns | Return numbers present, so first returns can be identified. |
| Terrain | Under 1% of the cloud's points in the clip's box lack a terrain value. |
| Buffer | The cloud's extent reaches at least 10 m beyond the polygon's bounding box on every side. |
| Heights | Every stem inside with a diameter of at least 10 cm has a positive field height. |
| Time gap | Flight and field survey are at most 4 years apart, the benchmark's limit. |
| Stems | At least 6 stems in the primary population. |
| Registration | An offset is estimated and is at most 4.0 m, the matching tolerance. |

The buffer rule follows from the detector: a detection that can matter lies
within 4 m of the polygon, and its largest window has a radius of 2.5 m. The
registration rule follows from the matcher: beyond 4 m a tree-top above its
own stem can no longer match it, so matches are chance, and chance favours the
arm with more detections.

Known at the time of writing: Cotolivier plot 02 has an estimated offset of
4.6 m with a sharp minimum (the statistic falls from 3.39 m to 2.07 m) and
fails the registration rule. The other 13 areas have estimates of 0.5 to
2.5 m and pass every rule. Their primary population is 1,244 stems; plot 02
holds 96 more. Montafon's terrain raster ends 0.15 m short of its cloud on the
north side, which leaves 12 points without a value. In every area the polygon
widened by 10 m is covered by the cloud.

## Detector

Pinned before the comparison:

- `scripts/multichm_gated_lib.R` at commit `9c2f2ed`, git blob
  `5a83e4afbc2491337e2826800cedcfda38bf85d8`, with lidRplugins 0.4.0 and
  lidR 4.3.2 on one thread;
- window coefficient `a = 0.10`, as on NEON;
- **stock**: `MCG_STOCK`, which reproduces `lidRplugins::multichm`. Each
  clip's stock detections are checked against the package itself;
- **declared**: `MCG_DECLARED`, label `z5_s0.75_c0.6_e1_d8`: a 5 m floor on
  deeper-layer peaks, surface peaks exempt from the distance filter where
  cover is at least 0.6, and a first-return share of 0.75 required of
  deeper-layer peaks where the stand is also at least 8 m in crown spacing.

Three further configurations decompose the declared one. They carry no
decision:

| Label | What it adds to stock |
| --- | --- |
| `z5_s0_c0_e0` | the 5 m floor |
| `z5_s0_c0.6_e1` | the floor and the surface exemption |
| `z5_s0.75_c0.6_e1` | those and the share gate in every closed stand |

The gate's stand features (cover, crown spacing) are measured on the clip, as
on NEON.

## Scoring

The benchmark's matcher, unchanged: greedy one-to-one by distance within 4 m,
with the height gate (a detection matches a stem only between half the stem's
height and 8 m above it). The scoring footprint is the release's polygon.
Detections within 4 m outside it may match a stem inside; only detections
inside count towards precision.

Chance agreement is measured as on NEON, adapted to a polygon. The detections
inside the polygon's bounding box widened by the matching radius (4 m; 2 m
where a 2 m radius is scored) are shifted together by a random offset and
wrapped at the box's edges, 200 times per plot, with shifts closer than 8 m to
no shift rejected. The same shifts serve every configuration.
Chance-corrected rates are the excess over the null, scaled by the null's
headroom.

Counts are pooled by summing over plots, never by averaging rates.

## Analysis

**Primary contrast.** Pooled F1 of the declared configuration minus stock, on
the admitted areas and the primary population, with a 95% percentile interval
from 1,000 resamples of plots (one stratum, seed 20261002).

**Reading.** Fixed in advance:

- *better*: the interval's lower bound is above zero;
- *worse*: its upper bound is below zero;
- *not worse*: neither, and the lower bound is above −0.02;
- *inconclusive*: otherwise.

**Secondary, declared in advance.** None changes the reading.

1. Chance-corrected F1, precision and recall, plain precision and recall, and
   detections per reference stem, for the same contrast.
2. Each decomposition configuration against stock, and the declared
   configuration against the floor with exemption (the share gate's own
   change).
3. Per plot: reference stems, detections, matches and F1 of both
   configurations, with the plot's cover, crown spacing and gate state, so
   that the stands that gain or lose detections can be read off.
4. By gate state under the declared configuration: gated, closed but not
   gated, open. Each group gets its own contrast.
5. By density: areas whose clip-wide first-return density lies inside the
   range of the NEON clips the arm was developed on (5.2 to 17.8 per m²,
   bounds included), and areas outside it, each group with its own contrast.
   Outside are Pellizzano (about 49 and 57), Montafon (about 20) and Leskova
   dolina plots 15 and 17 (about 20 and 19).
6. The inventoried population.
7. Registration: every area, plot 02 included, with stems and polygon moved
   together by the area's estimated offset, which is computed by moving the
   detections the opposite way; and the primary positions with plot 02
   included.
8. Leaving out one forest at a time, the range of the primary contrast.
9. A 2 m matching radius.
10. Recall by height band.

Intervals are given for a contrast over five plots or more; smaller groups are
given as estimates.

## Limits known in advance

- Fourteen plots in six forests are few. One hectare at Saint-Agnan and the
  pole forest of Pellizzano area 1 hold a third of the stems. The
  leave-one-forest-out range shows what rests on one forest.
- `multichm` implements the multi-layer method that the benchmark's authors
  entered in it, so stock runs on the data it was designed around. The paper
  reports that method with as many detections as reference trees and a
  commission rate of 61%, under another matcher and every callipered stem.
- These are Alpine mixed and conifer forests, most on steep slopes. They are
  not the Pacific coast forests the benchmark addresses.
- Dead stems may be in 13 of the 14 inventories.
- The release's authors moved some plots to fit the canopy model by eye. The
  stems are therefore not independent of the LiDAR in position.
- Nothing here re-tunes the arm, and a result on 13 plots does not establish
  its thresholds.

## Deviations

Any departure from this protocol is listed in the report with its reason.

## Amendments before the run

The first version was fixed at 11:20 UTC on 19 November 2026. The code was
then reviewed against it, with no detector run on the release and no score
seen. These changes followed, and the file was fixed again before the freeze
and the detector runs:

- **Clip-wide density.** The first version divided by the rectangle the cloud
  spans. Five clouds do not fill that rectangle, which understated their
  density by 15 to 21%. The area is now the convex hull of the clip's points.
  No area changes resolution. Montafon and Leskova dolina plots 15 and 17 move
  outside the NEON development range, so the group outside it holds five plots
  instead of two.
- **Height bands.** The first version said below 8 m, 8 to 15 m, 15 m and
  above. The benchmark's scoring, used unchanged, puts a stem of exactly 8 m
  in the short band and one of exactly 15 m in the middle band. Five primary
  stems of the admitted areas sit on an edge.
- **Admission wording.** The terrain rule is the share of points without a
  value alone: read literally, "the raster covers the clip" would have failed
  Montafon over 0.15 m. The heights rule now names the stems it tests, since
  the primary population has heights by definition. The buffer rule names the
  cloud's extent. The registration rule and the diagnostic now say that fewer
  than three locally dominant stems give no estimate. No area's admission
  changes.
- **Null window.** It is widened by the matching radius in use, so by 2 m for
  the 2 m radius.
- **Registration scenario.** Stems and polygon move together.
- **Groups.** By gate state and by density, each group gets its own contrast;
  no contrast between groups is computed.
