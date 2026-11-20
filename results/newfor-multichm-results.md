# Gated multichm on the NEWFOR Alpine plots

Checked on 19 November 2026 on 13 fully callipered plots of the NEWFOR
benchmark, 1,244 stems of at least 10 cm. The rules were fixed in a
[protocol](../docs/newfor-validation-protocol.md) before any detector ran on
the data. No threshold of the arm was tuned here. `multichm_gated` remains a
post hoc arm, outside the twelve arms of this repository's paper.

The declared gated configuration scores a pooled F1 of 0.615 against 0.632
for stock `multichm`: −0.017 [−0.041, +0.015]. By the reading fixed in advance
this is **inconclusive**. The interval includes zero, and its lower bound is
below the −0.02 that "not worse" required. The gain measured on NEON's
held-out plots (+0.032 in plain F1) lies above the interval.

The secondary analyses, which decide nothing, show this:

- The arm trades recall for precision. Precision rises by 0.072 [0.047,
  0.088]. Recall falls by 0.061 [0.003, 0.111]. The arm places 19% fewer
  detections inside the polygons.
- The 5 m floor and the surface exemption keep the sign they had on NEON, not
  the size: together they raise F1 by 0.014 [0.007, 0.020], against +0.037
  there.
- The share gate does not gain. Against the same configuration without it, F1
  is lower by 0.030 [0.002, 0.052] and corrected F1 by 0.020, with an
  interval that includes zero. In the seven plots where it applies it removes
  158 detections inside the polygons, and 84 matched stems go with them.
- One plot was excluded by a registration check fixed in advance. Checked
  after the run, the detections do not bear that check out. With the plot
  included the result is the same (−0.015 [−0.037, +0.015]).

## What was tested

The [gated multichm study](multichm-gated-results.md) selected the arm's
thresholds on NEON plots in California and Washington. NEON's census covers
part of each plot, so precision there is measured only inside the censused
subplots. NEWFOR supplies plots in which every stem above a caliper threshold
was measured. The question was whether the declared configuration detects
trees better than stock on such plots, with identical plots, stems and
matching.

The two configurations compared:

- **stock**: the arm with everything switched off, which is
  `lidRplugins::multichm`;
- **gated**: the declared configuration `z5_s0.75_c0.6_e1_d8`. Deeper-layer
  peaks below 5 m are dropped everywhere. Where canopy cover is at least 0.6,
  surface peaks skip the distance filter. Where crowns are also at least 8 m
  apart, a deeper-layer peak is kept only if at least 0.75 of the returns
  around it are first returns (the share gate).

Three further configurations take the gated one apart: the floor alone, the
floor with the exemption, and the share gate in every closed stand. They were
declared in advance as secondary.

## Data

Monnet and Eysn, *Airborne laser scanning single tree detection NEWFOR
benchmark dataset*, version 1.0 of 17 March 2023,
[doi:10.57745/BXJBVH](https://doi.org/10.57745/BXJBVH), Etalab Open Licence
2.0. It is the public part of the benchmark of
[Eysn et al. (2015)](https://doi.org/10.3390/f6051721): 14 study areas in six
Alpine forests, each with a point cloud, a terrain raster, a stem inventory
with heights and a scoring polygon. All 123 files matched the repository's
checksums. The data are not redistributed here.

`DBHRef` is in metres in every inventory, whatever the plot sheets say, so
the 10 cm cutoff is 0.10. The inventories carry no status or species, so live
trees cannot be selected. The **primary population** is every stem inside the
polygon with a diameter of at least 10 cm. The **inventoried population** is
every stem inside, whatever its diameter.

### Admission

The rules and their reasons are in the protocol. Every stem inside a polygon
has a field height. In every area under 0.01% of the cloud's points lack a
terrain value, and return numbers are present.

| Area | Forest | Polygon (ha) | Inventory rows | Outside polygon | Inside, under 10 cm or no diameter | Primary stems | Flight minus survey (months) | Least reach of cloud (m) | Registration offset (m) | Admitted |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 01 | Saint-Agnan | 1.01 | 359 | 7 | 31 | 321 | +2 | 25.0 | 1.6 | yes |
| 02 | Cotolivier | 0.13 | 106 | 0 | 10 | 96 | −4 | 25.0 | 4.6 | no |
| 03 | Cotolivier | 0.13 | 49 | 0 | 11 | 38 | −11 | 25.0 | 0.7 | yes |
| 04 | Cotolivier | 0.13 | 22 | 0 | 6 | 16 | −3 | 25.0 | 2.5 | yes |
| 06 | Montafon | 0.25 | 107 | 6 | 24 | 77 | +27 | 24.9 | 1.1 | yes |
| 07 | Pellizzano | 0.13 | 49 | 2 | 5 | 42 | −11 | 25.0 | 1.1 | yes |
| 08 | Pellizzano | 0.13 | 235 | 0 | 86 | 149 | −11 | 25.0 | 2.1 | yes |
| 09 | Asiago | 0.13 | 80 | 1 | 1 | 78 | −3 | 25.0 | 1.1 | yes |
| 10 | Asiago | 0.13 | 110 | 3 | 27 | 80 | −3 | 25.0 | 1.0 | yes |
| 11 | Asiago | 0.13 | 183 | 14 | 25 | 144 | −3 | 25.0 | 0.5 | yes |
| 15 | Leskova dolina | 0.20 | 53 | 0 | 0 | 53 | +11 | 24.7 | 0.7 | yes |
| 16 | Leskova dolina | 0.20 | 37 | 0 | 0 | 37 | +11 | 24.7 | 2.2 | yes |
| 17 | Leskova dolina | 0.20 | 117 | 0 | 0 | 117 | +11 | 24.7 | 2.5 | yes |
| 18 | Leskova dolina | 0.20 | 92 | 0 | 0 | 92 | +11 | 16.2 | 2.5 | yes |

Of 1,599 inventory rows, 33 lie outside their polygon and 226 inside are
under 10 cm or, in one case, have no diameter. That leaves 1,340 primary
stems, 1,244 of them in admitted areas.

**Cotolivier plot 02 is not admitted.** A check that uses no detector
compares the field heights of locally dominant stems with the canopy top at
shifted positions. For plot 02 the best fit is 4.6 m away, beyond the 4 m
matching radius, and the misfit falls from 3.39 m to 2.07 m there. The plot
therefore fails the registration rule fixed in advance. The other 13 areas
have estimates of 0.5 to 2.5 m and pass every rule.

**The check does not hold up.** After the run, the stock detections were
scored at a 2 m radius at the released positions and again moved by each
area's estimate:

- At the released positions stock matches 39 of plot 02's 96 stems. None of
  the 200 shifted copies of its detections matches more than 32. Moved by the
  estimate it matches 26, which 69 of the 200 copies reach.
- Over the 13 admitted areas the move lowers the matched stems from 479 to
  434. It lowers them in 8 areas and raises them in 4. In area 03 the moved
  positions match at chance level (10 stems, against 21 as released).

So the released positions of plot 02 fit the canopy, and the rule excluded a
plot it should not have. The exclusion stands because the rule was fixed in
advance. The plot is still run, and the row that includes it gives the same
reading. Why a height-based check misleads here was not investigated.

### Point density

Density was measured inside each scoring polygon and over each clip, the
polygon's bounding box widened by 25 m. The clip's area is the convex hull of
its points, because five clouds do not fill their box.

| Area | Forest | First returns/m², polygon | All returns/m², polygon | First returns/m², clip | All returns/m², clip | Raster cell (m) | NEON range |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| 01 | Saint-Agnan | 6.7 | 10.3 | 7.6 | 11.9 | 0.50 | inside |
| 02 | Cotolivier | 6.8 | 11.3 | 7.3 | 11.3 | 0.50 | inside |
| 03 | Cotolivier | 5.6 | 8.4 | 6.5 | 9.6 | 0.50 | inside |
| 04 | Cotolivier | 9.1 | 11.4 | 8.8 | 11.6 | 0.25 | inside |
| 06 | Montafon | 21.3 | 24.6 | 19.6 | 22.5 | 0.25 | outside |
| 07 | Pellizzano | 50.7 | 104.3 | 49.4 | 92.7 | 0.25 | outside |
| 08 | Pellizzano | 60.1 | 136.9 | 57.2 | 126.5 | 0.25 | outside |
| 09 | Asiago | 8.0 | 10.2 | 8.4 | 11.1 | 0.25 | inside |
| 10 | Asiago | 10.7 | 14.5 | 8.8 | 12.0 | 0.25 | inside |
| 11 | Asiago | 7.7 | 8.7 | 10.2 | 12.1 | 0.25 | inside |
| 15 | Leskova dolina | 21.5 | 29.2 | 20.5 | 28.8 | 0.25 | outside |
| 16 | Leskova dolina | 13.8 | 17.5 | 17.1 | 23.3 | 0.25 | inside |
| 17 | Leskova dolina | 18.2 | 30.9 | 19.2 | 32.1 | 0.25 | outside |
| 18 | Leskova dolina | 17.4 | 25.1 | 17.2 | 25.4 | 0.25 | inside |

The last column says whether the clip's first-return density lies inside the
range of the NEON clips the arm was selected on, 5.2 to 17.8 per m². The
detector's raster cell follows the same density, as on NEON: 0.25 m at 8 first
returns per m² or more, otherwise 0.5 m.

## How it was run

- **Clips.** One per area, sealed with SHA-256 in a root of its own. Points
  of classes 7 and 18 and withheld points are dropped. Heights are elevations
  minus the released terrain raster. The clouds' ground class is not used:
  Montafon has none, and in Leskova dolina class 2 is not ground.
- **Detector.** `scripts/multichm_gated_lib.R` at git blob
  `5a83e4afbc2491337e2826800cedcfda38bf85d8`, with lidRplugins 0.4.0 and
  lidR 4.3.2 on one thread and the window coefficient used on NEON, 0.10. The
  run stops if the library or either package differs. On all 14 clips the
  stock configuration returned exactly the tree-tops of
  `lidRplugins::multichm`.
- **Matching.** This repository's matcher, as used on NEON: greedy one-to-one
  within 4 m, a detection matching a stem only between half the stem's height
  and 8 m above it. A detection up to 4 m outside the polygon may match a
  stem inside. Only detections inside count towards precision.
- **Chance.** The detections around each polygon are shifted together 200
  times and scored again. "Corrected" below means the excess over that null,
  scaled by the null's headroom.
- **Pooling and intervals.** Counts are summed over plots. Intervals are 95%
  percentile intervals over 1,000 resamples of plots, the same draws for both
  configurations and for observed and null counts. They are not adjusted for
  the number of contrasts. With 1,000 draws the Monte Carlo standard error of
  a bound is about 2% of the interval's width, and a bound that close to zero
  is read below as sitting on zero.

An independent scorer, written from the protocol's text, reproduces the
counts of all 280 cells, and a second run reproduces every output byte for
byte.

## Result

The 13 admitted areas, primary population:

| Configuration | Detections inside polygons | Per stem | Matched stems | Recall | Precision | F1 | Null F1 | Corrected F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Stock | 919 | 0.74 | 705 | 0.567 | 0.714 | 0.632 | 0.471 | 0.304 |
| Gated | 741 | 0.60 | 629 | 0.506 | 0.785 | 0.615 | 0.453 | 0.297 |
| Floor | 867 | 0.70 | 697 | 0.560 | 0.747 | 0.640 | 0.479 | 0.310 |
| Floor and exemption | 899 | 0.72 | 713 | 0.573 | 0.739 | 0.645 | 0.481 | 0.316 |
| Gate in every closed stand | 687 | 0.55 | 583 | 0.469 | 0.789 | 0.588 | 0.420 | 0.290 |

Precision is the share of detections inside the polygons that matched: 656 of
919 for stock and 582 of 741 for the gated configuration.

**The primary contrast.** Pooled F1, gated minus stock: **−0.017 [−0.041,
+0.015]**. The reading rules were: better if the lower bound is above zero,
worse if the upper bound is below zero, not worse if neither and the lower
bound is above −0.02, inconclusive otherwise. The result is inconclusive.

The other measures of the same contrast:

| Measure | Gated minus stock |
| --- | --- |
| Corrected F1 | −0.008 [−0.027, +0.017] |
| Precision | +0.072 [+0.047, +0.088] |
| Recall | −0.061 [−0.111, −0.003] |
| Corrected precision | +0.109 [+0.077, +0.143] |
| Corrected recall | −0.039 [−0.080, −0.005] |
| Detections per stem | −0.143 [−0.237, −0.034] |

Chance agreement is high at a 4 m radius in stands this dense. Shifted
detections reach an F1 of 0.47, so about a quarter of plain F1 is above
chance. The gated configuration's null is lower than stock's (0.453 against
0.471), which is why the corrected difference is smaller than the plain one.
The null does not follow the detection count alone: the floor places 52 fewer
detections than stock and has a higher null (0.479).

## What each part does

Each configuration against stock, and the gated configuration against the
floor with the exemption, which isolates the share gate as declared:

| Contrast | F1 | Corrected F1 | Precision | Recall |
| --- | --- | --- | --- | --- |
| Floor − stock | +0.009 [+0.001, +0.015] | +0.006 [−0.005, +0.019] | +0.034 [+0.016, +0.047] | −0.006 [−0.011, −0.001] |
| Floor and exemption − stock | +0.014 [+0.007, +0.020] | +0.012 [+0.001, +0.023] | +0.025 [+0.012, +0.042] | +0.006 [−0.001, +0.015] |
| Gate in every closed stand − stock | −0.044 [−0.075, −0.011] | −0.014 [−0.034, +0.008] | +0.075 [+0.057, +0.093] | −0.098 [−0.134, −0.046] |
| Gated − floor and exemption | −0.030 [−0.052, −0.002] | −0.020 [−0.036, +0.001] | +0.047 [+0.022, +0.062] | −0.068 [−0.116, −0.012] |

- The floor with the exemption is better than stock, in plain F1 and, more
  narrowly, in corrected F1. The floor alone removes 52 detections for 8
  matched stems.
- The share gate's own change is −0.030 in F1 and −0.020 in corrected F1. The
  first interval excludes zero narrowly, and only while plots are the
  resampling unit (see [Limits](#limits)); the second has its upper bound on
  zero. The gate raises precision by 0.047 and costs 0.068 of recall: 158
  detections fewer and 84 matched stems fewer.
- With the share gate in every closed stand, as the arm stood before its
  crown-spacing switch, F1 is lower than stock by 0.044 [0.011, 0.075]. The
  switch confines the gate to seven plots and limits the loss; it does not
  turn it into a gain.

## Which stands gain or lose

Cover is the share of first returns above 2 m and crown spacing the side of
the square each crown occupies, both measured on the clip as on NEON. All 14
clips lie inside the NEON clips' range of cover (0.16 to 0.99) and of crown
spacing (5.0 to 12.8 m). Rates of single plots are for reading only.

| Area | Forest | Cover | Crown spacing (m) | Share gate | Stems | Detections, gated / stock | Matched stems, gated / stock | Recall, gated / stock | Precision, gated / stock | F1, gated / stock | Change in F1 |
| --- | --- | ---: | ---: | --- | ---: | --- | --- | --- | --- | --- | ---: |
| 01 | Saint-Agnan | 0.89 | 8.4 | on | 321 | 239 / 337 | 176 / 221 | 0.55 / 0.69 | 0.71 / 0.64 | 0.619 / 0.664 | −0.045 |
| 02 | Cotolivier | 0.89 | 7.2 | off, closed | 96 | 56 / 56 | 52 / 52 | 0.54 / 0.54 | 0.86 / 0.84 | 0.664 / 0.658 | +0.005 |
| 03 | Cotolivier | 0.73 | 8.3 | on | 38 | 31 / 36 | 30 / 31 | 0.79 / 0.82 | 0.84 / 0.75 | 0.813 / 0.782 | +0.032 |
| 04 | Cotolivier | 0.64 | 10.3 | on | 16 | 13 / 22 | 10 / 11 | 0.62 / 0.69 | 0.62 / 0.41 | 0.620 / 0.513 | +0.107 |
| 06 | Montafon | 0.42 | 8.7 | off, open | 77 | 49 / 57 | 39 / 39 | 0.51 / 0.51 | 0.80 / 0.68 | 0.619 / 0.582 | +0.037 |
| 07 | Pellizzano | 0.80 | 8.7 | on | 42 | 25 / 35 | 27 / 33 | 0.64 / 0.79 | 0.96 / 0.83 | 0.770 / 0.807 | −0.037 |
| 08 | Pellizzano | 0.98 | 7.1 | off, closed | 149 | 50 / 51 | 53 / 54 | 0.36 / 0.36 | 0.90 / 0.90 | 0.510 / 0.517 | −0.007 |
| 09 | Asiago | 0.91 | 6.4 | off, closed | 78 | 46 / 44 | 45 / 43 | 0.58 / 0.55 | 0.89 / 0.89 | 0.700 / 0.680 | +0.021 |
| 10 | Asiago | 0.91 | 7.3 | off, closed | 80 | 44 / 45 | 44 / 44 | 0.55 / 0.55 | 0.84 / 0.80 | 0.665 / 0.652 | +0.013 |
| 11 | Asiago | 0.97 | 7.3 | off, closed | 144 | 43 / 39 | 50 / 46 | 0.35 / 0.32 | 1.00 / 1.00 | 0.515 / 0.484 | +0.031 |
| 15 | Leskova dolina | 0.85 | 9.1 | on | 53 | 38 / 52 | 27 / 33 | 0.51 / 0.62 | 0.68 / 0.62 | 0.584 / 0.619 | −0.035 |
| 16 | Leskova dolina | 0.82 | 9.4 | on | 37 | 44 / 54 | 24 / 28 | 0.65 / 0.76 | 0.52 / 0.50 | 0.579 / 0.602 | −0.023 |
| 17 | Leskova dolina | 0.96 | 7.9 | off, closed | 117 | 74 / 73 | 64 / 62 | 0.55 / 0.53 | 0.84 / 0.82 | 0.662 / 0.644 | +0.018 |
| 18 | Leskova dolina | 0.93 | 8.5 | on | 92 | 45 / 74 | 40 / 60 | 0.43 / 0.65 | 0.84 / 0.77 | 0.574 / 0.706 | −0.132 |

Seven admitted plots gain and six lose. Five of the six that lose have the
share gate on: plots 01, 07, 15, 16 and 18. The two Cotolivier plots with the
gate on, 03 and 04, gain. Pooled by what the arm does in the stand:

| Stands | Plots | Stems | Detections, gated / stock | F1, gated / stock | Change in F1 | Change in corrected F1 | Change in precision | Change in recall |
| --- | ---: | ---: | --- | --- | --- | --- | --- | --- |
| Share gate on | 7 | 599 | 435 / 610 | 0.630 / 0.673 | −0.043 [−0.082, +0.001] | −0.021 [−0.061, +0.018] | +0.073 [+0.051, +0.109] | −0.139 [−0.178, −0.092] |
| Closed, gate off | 5 | 568 | 257 / 252 | 0.598 / 0.584 | +0.014 [+0.002, +0.025] | +0.003 [−0.014, +0.025] | +0.014 [+0.002, +0.028] | +0.012 [−0.002, +0.024] |
| Open | 1 | 77 | 49 / 57 | 0.619 / 0.582 | +0.037 | +0.056 | +0.112 | +0.000 |

- **Where the share gate is on**, the arm places 29% fewer detections (435
  against 610) and matches 83 fewer stems (334 against 417). Recall falls from
  0.696 to 0.558 and precision rises from 0.651 to 0.724. The gate's own
  change there, against the floor with the exemption, is −0.053 [−0.087,
  −0.008] in F1 and −0.032 [−0.067, +0.009] in corrected F1.
- **In closed stands with crowns under 8 m apart** only the floor and the
  exemption act, and F1 rises by 0.014 [0.002, 0.025]. Stock finds fewer
  than half the stems there (recall 0.438 at a precision of 0.873). Applying
  the share gate in these stands as well would have lowered F1 to 0.528,
  against stock by −0.055 [−0.116, −0.003].
- **Montafon**, the one open stand, gains from the floor alone: 8 fewer
  detections and the same 39 matched stems.

In the estimates the share gate lowers plain F1 on both sides of the
crown-spacing switch, on seven plots and on five. These plots give no sign
that the gate pays where crowns are large and far apart, which was the
premise behind the switch.

## By point density

| Clip density | Plots | Stems | Detections, gated / stock | F1, gated / stock | Change in F1 | Change in corrected F1 |
| --- | ---: | ---: | --- | --- | --- | --- |
| Inside the NEON range | 8 | 806 | 505 / 651 | 0.619 / 0.643 | −0.024 [−0.055, +0.026] | −0.013 [−0.043, +0.018] |
| Above it | 5 | 438 | 236 / 268 | 0.608 / 0.609 | −0.001 [−0.029, +0.022] | +0.004 [−0.026, +0.037] |

Both intervals include zero. The five plots above the range (Montafon, both
Pellizzano plots, Leskova dolina 15 and 17) do not drive the result: the
point estimate is lower on the eight plots inside it.

## Sensitivity

| Scoring | Plots | Stems | F1, gated / stock | Change in F1 | Corrected F1, gated / stock | Change in corrected F1 |
| --- | ---: | ---: | --- | --- | --- | --- |
| Primary | 13 | 1,244 | 0.615 / 0.632 | −0.017 [−0.041, +0.015] | 0.297 / 0.304 | −0.008 [−0.027, +0.017] |
| With Cotolivier plot 02 | 14 | 1,340 | 0.619 / 0.634 | −0.015 [−0.037, +0.015] | 0.293 / 0.300 | −0.007 [−0.026, +0.018] |
| Moved by the registration estimate | 13 | 1,244 | 0.618 / 0.630 | −0.012 [−0.034, +0.018] | 0.304 / 0.304 | +0.000 [−0.019, +0.026] |
| Moved by the registration estimate, with plot 02 | 14 | 1,340 | 0.621 / 0.631 | −0.010 [−0.030, +0.019] | 0.301 / 0.298 | +0.003 [−0.018, +0.028] |
| Inventoried population | 13 | 1,460 | 0.566 / 0.600 | −0.034 [−0.059, +0.001] | 0.251 / 0.278 | −0.027 [−0.047, −0.001] |
| 2 m matching radius | 13 | 1,244 | 0.439 / 0.436 | +0.003 [−0.013, +0.026] | 0.292 / 0.282 | +0.010 [−0.003, +0.029] |

The two "moved" rows move each area's stems and polygon by its estimated
registration offset. The move is not a correction, as the
[admission section](#admission) shows; the rows are kept because the protocol
declared them.

- No row gives an interval above zero. Including plot 02 or moving positions
  by the estimate changes the F1 difference by 0.007 at most and the
  corrected F1 difference by about 0.01.
- Adding the 216 stems under 10 cm or without a diameter lowers both
  configurations' scores and widens the gap to −0.034. The upper bound sits
  on zero in plain F1 and is just below it in corrected F1.
- At a 2 m radius both differences turn positive, and both intervals include
  zero. The recall the arm gives up halves (−0.030 against −0.061): its net
  loss of matched stems falls from 76 (705 to 629) to 37 (479 to 442).

**Leaving out one forest.** The F1 difference ranges from −0.027 (without
Asiago) to −0.005 (without Saint-Agnan), and every interval includes zero:

| Left out | Plots | Change in F1 | Change in corrected F1 |
| --- | ---: | --- | --- |
| Asiago | 10 | −0.027 [−0.052, +0.007] | −0.010 [−0.035, +0.020] |
| Cotolivier | 11 | −0.021 [−0.045, +0.012] | −0.012 [−0.032, +0.012] |
| Leskova dolina | 9 | −0.008 [−0.030, +0.028] | +0.000 [−0.016, +0.033] |
| Montafon | 12 | −0.020 [−0.046, +0.013] | −0.014 [−0.032, +0.008] |
| Pellizzano | 11 | −0.016 [−0.042, +0.021] | −0.005 [−0.026, +0.026] |
| Saint-Agnan | 12 | −0.005 [−0.038, +0.021] | −0.003 [−0.030, +0.026] |

**Recall by height band**, primary population, as stock / floor and
exemption / gated:

| Stem height | Stems | Recall | Recall of the null | Corrected recall |
| --- | ---: | --- | --- | --- |
| Up to 8 m | 87 | 0.287 / 0.241 / 0.161 | 0.250 / 0.211 / 0.157 | 0.050 / 0.039 / 0.005 |
| Above 8 m, up to 15 m | 326 | 0.356 / 0.328 / 0.252 | 0.265 / 0.261 / 0.201 | 0.124 / 0.091 / 0.064 |
| Above 15 m | 831 | 0.679 / 0.704 / 0.641 | 0.505 / 0.521 / 0.468 | 0.350 / 0.382 / 0.326 |

Stems up to 8 m are matched barely above chance by any configuration. The
floor with the exemption raises the recall of stems above 15 m from 0.679 to
0.704. The share gate then takes recall from every band. Of the 84 matched
stems it loses, 52 are above 15 m, 25 in the middle band and 7 in the lowest;
most are tall because most matched stems are. In the seven plots where it
applies, that is 52 of 346 matches above 15 m, 25 of 60 in the middle band
and 7 of 12 in the lowest.

## Beside the NEON result

On NEON's 49 held-out plots at native density the same configuration raised
corrected F1 by 0.034 [0.014, 0.053] and plain F1 by 0.032 [0.010, 0.057],
scored on the nominal plot cores. Here corrected F1 changes by −0.008
[−0.027, +0.017] and plain F1 by −0.017 [−0.041, +0.015]. The plain intervals
overlap only between +0.010 and +0.015.

The closest NEON counterpart is the score inside censused subplots, where
every stem is mapped as it is here. Stock detects at the same rate in both:
0.69 detections per stem on NEON's 31 validation plots (488 for 706), 0.74
here. There the gated configuration raised F1 by 0.048 [0.007, 0.086]. That
gain came from ABBY, managed Douglas-fir, where the arm adds detections. At
WREF, Douglas-fir and hemlock up to old growth, on its 28 censused plots with
calibration plots among them, the arm placed fewer detections (338 against
463), precision rose from 0.624 to 0.751, recall fell from 0.526 to 0.469 and
F1 did not move (+0.006 [−0.025, +0.032]). The NEWFOR plots behave like WREF:
fewer detections, higher precision, lower recall, and no change in F1 that
the data separate from zero. The censused-subplot scores are in sample for
the crown-spacing switch.

Each part's change in the two settings, against stock, or for the share gate
against the floor with the exemption. The NEON columns are the held-out plots
on nominal cores:

| Part | NEON held-out, F1 | NEON held-out, corrected F1 | NEWFOR, F1 | NEWFOR, corrected F1 |
| --- | --- | --- | --- | --- |
| Floor | +0.019 [+0.013, +0.024] | +0.015 [+0.009, +0.021] | +0.009 [+0.001, +0.015] | +0.006 [−0.005, +0.019] |
| Floor and exemption | +0.037 [+0.021, +0.055] | +0.028 [+0.015, +0.040] | +0.014 [+0.007, +0.020] | +0.012 [+0.001, +0.023] |
| Share gate's own change | −0.005 [−0.019, +0.009] | +0.006 [−0.008, +0.023] | −0.030 [−0.052, −0.002] | −0.020 [−0.036, +0.001] |

The floor and the exemption gain in both, by less here. The share gate's own
change was not separable from zero on NEON's held-out plots. Here its
estimate is negative in both measures. The F1 interval ends just short of
zero, and reaches it when forests are resampled instead of plots; the
corrected interval includes zero.

The settings differ in ways this study cannot separate:

- **The forest.** These are Alpine mixed and conifer stands, most on steep
  slopes, several of them multi-layered. The arm was shaped on Douglas-fir
  and hemlock in Washington and on three sites of California's Sierra
  Nevada.
- **The sensors.** NEON's closed plots were all flown with one instrument.
  These plots were flown with three others (RIEGL LMS-Q560, RIEGL LMS-Q680i,
  Optech ALTM 3100EA), and the first-return share depends on how many returns
  per pulse an instrument records. Seen after the results, on single-plot
  rates: of the seven plots with the share gate on, the two that gain (38 and
  16 stems) are the two flown with the Optech instrument. They are also the
  two Cotolivier plots, so sensor and forest cannot be told apart.
- **The reference.** NEON's reference holds live stems. Here dead stems may
  be among the reference in 13 of the 14 inventories.

## Limits

- Thirteen plots in six forests are few, and the intervals are wide.
  Saint-Agnan and Pellizzano plot 08 hold 38% of the primary stems.
- Intervals resample plots as independent units, as the protocol fixed. The
  plots sit in six forests whose plots share a flight, a sensor and a survey.
  Resampling the six forests instead, a check made after the run, leaves the
  primary contrast inconclusive (−0.017 [−0.038, +0.020]) and the floor with
  the exemption above zero (+0.014 [+0.007, +0.022]). It moves the upper
  bounds of the recall loss and of the share gate's own change in F1 to
  +0.001. Neither is established.
- The decomposition, the groups and the sensitivity rows are secondary and
  many, and their intervals are not adjusted for that.
- The registration check that excluded plot 02 is not reliable, as the
  admission section shows. Nothing in the primary scoring uses its estimates.
- `multichm` implements the multi-layer method that the benchmark's authors
  entered in their own comparison, so stock runs on the data the method was
  designed around. The paper reports that entry with as many detections as
  reference trees, under another matcher and every callipered stem. The
  package with this repository's window setting places 0.63 detections per
  inventoried stem.
- A detection on a tree under 10 cm counts as a commission in the primary
  population. The inventoried population removes that, at the cost of asking
  an airborne detector for stems that are mostly 4 to 10 cm thick.
- The benchmark's authors moved some plots by eye to fit the canopy model, so
  stem positions are not independent of the LiDAR. They state an accuracy of
  ±2 m.
- Flight and field survey are up to 27 months apart (Montafon).
- At a 4 m radius three quarters of plain F1 is within reach of chance in
  these stands. The corrected scores and the 2 m row are the guard against
  reading detection counts as skill.
- Nothing here re-tunes the arm. The result neither establishes nor
  overturns its thresholds, and it says nothing about decimated densities.

## Deviations from the protocol

None in the run or in the primary contrast. The protocol was amended once,
before the freeze and the detector runs, after the code had been reviewed
against its first version; its last section lists the changes. Four of them
reach a table here. The clip's area is the convex hull of the points, which
puts Montafon and Leskova dolina plots 15 and 17 above the NEON density
range, so that group holds five plots instead of two. The "moved" rows move
the polygon with the stems. The 2 m row's null window is widened by 2 m. And
the height bands are cut as the scoring cuts them.

Reported beyond the protocol's list, none of it deciding anything:

- the share gate's own change and the gate in every closed stand within the
  gate-state groups, which come from the declared contrasts but are not named
  in the protocol;
- the "moved" row without plot 02;
- the comparison with the NEON study;
- three checks made after the results were seen: the 2 m scoring of the
  registration estimates, the intervals with forests resampled, and the
  sensors of the plots with the share gate on;
- the reading of a bound within one Monte Carlo standard error of zero as
  sitting on zero.

Two statements of the protocol do not hold up. Its registration check was
meant to find misplaced plots, and the detections show it does not. And its
opening says NEON's precision is bracketed, not measured; inside NEON's
censused subplots it is measured, and the gated study reports it.

## Outputs

- `work/newfor/frozen_v1/` is the sealed freeze root, id `6d4212110614…`.
  Each area folder holds `normalized.laz`, `aoi.wkt`, `reference_stems.csv`
  and `cell.json`. `admission.csv` holds every rule per area,
  `registration_scan.csv` the registration check at every offset, and
  `freeze.json` the hashes of the inputs, the protocol and every script the
  freeze sources. The id does not depend on the commit checked out.
- `work/newfor/multichm_runs/` holds `run.json` (the pins, the constants and
  the hashes of the scripts), `detections/<area>/<configuration>.csv`,
  `features.csv` (one row per area) and `cells.csv` (observed and null counts
  of every area, configuration and scoring).
- `work/newfor/multichm_runs/analysis/` holds `pooled.csv`, `contrasts.csv`,
  `reading.csv`, `per_plot.csv`, `leave_one_forest_out.csv`, `pools.csv` and
  `tables.md`, which has the declared tables in full.
- `work/newfor/multichm_runs/after_run/` holds the two checks made after the
  run, kept apart from the declared analysis: `registration_moves.csv` (the
  2 m scoring as released and moved by the registration estimates),
  `forest_resampled.csv` (the intervals with forests resampled) and
  `after_run.json` (their settings and code hashes). The sensors are in
  [newfor-area-metadata.json](../docs/newfor-area-metadata.json).

## Reproduce

```sh
export CLAUDE_JOB_DIR=$PWD/work
Rscript scripts/download_external_newfor.R    # 123 files, 60 MB, checksummed
Rscript scripts/freeze_newfor.R               # no detector; seals the root
Rscript scripts/detect_newfor_multichm.R CORES=6
Rscript scripts/analyze_newfor_multichm.R
Rscript scripts/check_newfor_run.R            # the checks made after the run
```

The freeze takes under a minute, detection about three and scoring about
three on six cores. The detection script refuses a freeze root made under
another protocol file, a changed detector library and other package versions.
The scores do not depend on `CORES`.
