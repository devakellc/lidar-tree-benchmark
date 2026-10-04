# Censused-Subplot Support for the Paper Population

Checked on 1 October 2026. Pooled precision over the nominal plot boxes is a
lower bound: an apex in an unsampled part of a box counts as a false positive.
This study scores detections only inside surveyed, censused subplots for the
declared plot population of the [frozen-clip study](frozen-clips-results.md),
under the [reference-support protocol](../docs/neon-reference-support-protocol.md).

**Declared rules** (accepted on 1 October 2026):

- **Headline:** for each plot, the nearest all-growth-forms census within four
  years of the 2021 flights, joined by census event. **Check:** the exact 2021
  census, reported beside it.
- **Missing references:** subplot exclusion. Every subplot holding a census
  target without a usable mapped position leaves the precision interior;
  recall keeps the references in the remaining interior; a missing target in
  an unknown subplot fails the plot closed. A target with a position but no
  usable height stays a reference, matched on position alone. Excluding
  heightless targets too is kept as a declared sensitivity.
- **Datum and flight provenance** are resolved by a reviewed declaration with
  written evidence ([evidence](../docs/census-support-evidence.json),
  [headline declaration](../docs/census-support-declaration-nearest.json),
  [check declaration](../docs/census-support-declaration-exact.json)).

Under the headline rule **57 of the 106 adopted plots** (33 tower, 24
distributed) are scored, holding 1,607 of the 2,525 core stems (64%); the
check admits 16 tower plots (680 stems). On identical detections, censused
precision is 0.08–0.34 higher than nominal-box precision for every arm and
rung; CHM-VWF at native density rises from 0.48 to 0.78.

## Preparation

`neon_reference_support.R` ran for SJER, SOAP, TEAK, WREF and ABBY and every
census year from 2019 to 2024, on the cached RELEASE-2026 woody-vegetation
data. It joins measurements to census events on plot and event, keeps the
latest mapping, builds each sampled footprint from the surveyed named-point
corners and erodes it by the largest anchor or mapping uncertainty plus 0.6 m.
Of 1,096 named points needed, NEON's location service defines 859; the other
237 are in-between grid points it does not survey.

- **Distributed plots list four 100 m² subplots.** Recent events record a
  distributed plot as `31_100|32_100|40_100|41_100` (400 m²), but only the
  plot's outer corners and centre are surveyed. A complete 2 × 2 block is the
  same 20 m square as the 400 m² subplot other events use for the same plots,
  so it is drawn from those surveyed corners. Such events census the whole
  distributed plot.
- **One WREF census spans the year boundary.** The 2020 tower census, whose
  plot records are dated July 2020, measured its 2,575 records between
  September 2020 and April 2021. Joining by measurement year keeps none of
  them; joining by census event (`JOIN=census_event`, the headline join) keeps
  them all. Only WREF has such events.

## Missing-reference policy

A census target without a usable mapped position still stands in its
subplot, where a correct detection would count as a false positive. Subplot
exclusion removes each such subplot before erosion; for a distributed plot
drawn as one block, that removes the whole plot. Missing means no mapped
coordinates, an unusable or flagged mapping, an unknown or unlisted subplot,
or an unresolved duplicate record. A target with a position but no usable
height stays a reference: its height is treated as missing, so the matcher
pairs it on position alone (the height gate needs a stem height), and it is
flagged `height_unknown`. The strict sensitivity also excludes the subplots
of heightless targets.

Under the headline rule, by site (candidate plots of the `adopted`
population; lost = plots the policy alone makes unscorable):

| Site | Touched (strict) | Missing / targets | Strict missing / targets | Interior, m² | Strict interior, m² | Lost (strict) |
| --- | --- | --- | --- | --- | --- | --- |
| SJER | 4 (6) | 10 / 49 | 42 / 71 | 2,868 → 1,040 | 4,298 → 1,384 | 2 (4) |
| SOAP | 7 (7) | 46 / 177 | 47 / 177 | 4,961 → 991 | 4,961 → 991 | 6 (6) |
| TEAK | 5 (7) | 29 / 151 | 36 / 194 | 2,396 → 719 | 3,055 → 719 | 4 (5) |
| WREF | 8 (11) | 17 / 405 | 22 / 532 | 5,065 → 1,948 | 6,798 → 2,304 | 2 (4) |
| ABBY | 7 (7) | 10 / 291 | 11 / 291 | 3,674 → 1,097 | 3,674 → 1,097 | 4 (4) |
| **Total** | **31 (38)** | **112 / 1,073** | **158 / 1,265** | **18,964 → 5,795** | **22,786 → 6,495** | **18 (23)** |

The 112 missing targets are 70 without mapped coordinates, 28 with a flagged
mapping, 7 duplicate records and 7 in an unlisted or unknown subplot; the 46
heightless targets the strict variant also counts stay references, 23 of them
in admitted plots. Narrowing the policy recovers most at SJER (10 missing
targets instead of 42) and little at SOAP, where SOAP_050 alone has 24 of 51
targets without a usable position and is emptied either way. Under the exact
2021 check the policy touches 7 plots (13 of 362 targets missing), removes
2,950 of 5,075 m² and costs 2 plots; the strict variant gives the same 16
admitted plots.

## Admission

Plots of the `adopted` population scored under each rule, after the policy:

| Site | Plots | Headline: admitted (tower / distributed) | Headline stems | Headline: not admitted | Check: admitted | Check stems |
| --- | --- | --- | --- | --- | --- | --- |
| SJER | 6 | 2 (2 / 0) | 31 | 4 | 0 | 0 |
| SOAP | 18 | 1 (1 / 0) | 16 | 17 | 0 | 0 |
| TEAK | 19 | 9 (2 / 7) | 149 | 10 | 2 | 48 |
| WREF | 38 | 28 (18 / 10) | 842 | 10 | 4 | 174 |
| ABBY | 25 | 17 (10 / 7) | 569 | 8 | 10 | 458 |
| **Total** | **106** | **57 (33 / 24)** | **1,607** | **49** | **16** | **680** |

Stems are the population's core stems in the admitted plots. Under the
headline rule the 49 plots not admitted break down as: 20 without an
all-growth-forms census in the window (the 2019 and 2020 SOAP and WREF events
carry no `dataCollected` field and fail closed), 18 lost to the
missing-reference policy, 7 with a mapped stem outside its recorded subplot
or the sampled footprint, and 4 whose geometry fails (missing corner
uncertainty, an invalid polygon or a quality-flagged event). The admitted
censuses lie −1 to +3 years from 2021 (14, 16, 18, 1 and 8 plots at −1, 0,
+1, +2 and +3). Joining by measurement year instead would admit 48 plots
rather than 57. The strict sensitivity admits 54. Under the check rule no
distributed plot qualifies, because none was censused in 2021.

### Declaration evidence

Field named points come from NEON's location service in WGS84 and each site's
UTM zone, the zone the 2021 tiles also declare; NEON's processing reports
reference the LiDAR products to ITRF00. The two realizations differ at the
centimetre level, far below the 4 m matching tolerance and the 0.5–1 m
uncertainty margin of every footprint. Every clip comes from the 2021 tiles of
one flight campaign per site:

| Site | Campaign | Sensor | 2021 flight days |
| --- | --- | --- | --- |
| SJER | 2021_SJER_5 | RIEGL Q780 (payload P3C1) | 31 March |
| SOAP | 2021_SOAP_5 | Optech Galaxy Prime (P1C2) | 12–13 July |
| TEAK | 2021_TEAK_5 | Optech Galaxy Prime (P1C2) | 13–14 July |
| WREF | 2021_WREF_4 | Optech Galaxy Prime (P1C2) | 18, 19, 23 and 24 July |
| ABBY | 2021_ABBY_4 | Optech Galaxy Prime (P1C2) | 19 and 24 July |

Per NEON's L3 processing report, SJER was flown in 2021 with a RIEGL Q780
lidar (payload P3C1), not the Optech Galaxy Prime of the other four sites.

### The 2015 tower census

Forty-seven tower plots carry live stems of at least 10 cm DBH measured in the
2015 census. Every 2015 event declares 800 m² of sampled tree area but lists
no subplots, while the stem records of most SOAP and TEAK tower plots fall in
three or four of the 400 m² quadrants. The records thus contradict the
declared area, and the 2015 census cannot be admitted as support.

## Censused versus nominal-box scores

`score_census_support.R` scores persisted detections only: no detector was
re-run for scoring. Each cell is scored inside the admitted interior
(precision from interior detections, recall with the 4 m tolerance around the
interior; heightless references match on position alone) and, on the same
detections, against the population's references in the nominal box. Pooled
counts over the 57 headline plots (1,190 censused references, 1,607 nominal)
at every rung where every arm has a cell:

| Arm | Rung | Recall | Precision | F1 | Nominal recall | Nominal precision | Nominal F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CHM-VWF | native | 0.50 | 0.78 | 0.61 | 0.49 | 0.48 | 0.49 |
| CHM-VWF | 8 | 0.35 | 0.86 | 0.50 | 0.34 | 0.52 | 0.41 |
| CHM-VWF | 4 | 0.36 | 0.86 | 0.50 | 0.34 | 0.53 | 0.41 |
| CHM-VWF | 2 | 0.33 | 0.86 | 0.48 | 0.32 | 0.52 | 0.40 |
| CHM-VWF | 1 | 0.33 | 0.87 | 0.47 | 0.30 | 0.53 | 0.39 |
| multichm | native | 0.56 | 0.64 | 0.60 | 0.55 | 0.41 | 0.47 |
| multichm | 8 | 0.57 | 0.63 | 0.60 | 0.56 | 0.40 | 0.46 |
| multichm | 4 | 0.56 | 0.62 | 0.59 | 0.54 | 0.39 | 0.45 |
| multichm | 2 | 0.54 | 0.60 | 0.57 | 0.53 | 0.39 | 0.45 |
| multichm | 1 | 0.52 | 0.62 | 0.57 | 0.50 | 0.39 | 0.44 |
| lmfauto | native | 0.60 | 0.49 | 0.54 | 0.59 | 0.31 | 0.40 |
| lmfauto | 8 | 0.61 | 0.39 | 0.48 | 0.62 | 0.25 | 0.36 |
| lmfauto | 4 | 0.65 | 0.30 | 0.41 | 0.66 | 0.18 | 0.28 |
| lmfauto | 2 | 0.74 | 0.26 | 0.39 | 0.74 | 0.16 | 0.26 |
| lmfauto | 1 | 0.78 | 0.26 | 0.39 | 0.80 | 0.16 | 0.26 |
| ptrees | native | 0.74 | 0.37 | 0.50 | 0.75 | 0.23 | 0.36 |
| ptrees | 8 | 0.56 | 0.64 | 0.60 | 0.56 | 0.41 | 0.48 |
| ptrees | 4 | 0.44 | 0.75 | 0.56 | 0.43 | 0.47 | 0.45 |
| ptrees | 2 | 0.31 | 0.80 | 0.45 | 0.30 | 0.51 | 0.38 |
| ptrees | 1 | 0.22 | 0.83 | 0.34 | 0.20 | 0.50 | 0.28 |
| AMS3D | native | 0.72 | 0.24 | 0.36 | 0.73 | 0.16 | 0.26 |
| AMS3D | 8 | 0.71 | 0.34 | 0.46 | 0.73 | 0.22 | 0.34 |
| AMS3D | 4 | 0.68 | 0.47 | 0.56 | 0.71 | 0.29 | 0.41 |
| AMS3D | 2 | 0.60 | 0.68 | 0.64 | 0.61 | 0.40 | 0.49 |
| AMS3D | 1 | 0.43 | 0.82 | 0.56 | 0.42 | 0.50 | 0.46 |
| Li 2012 | native | 0.59 | 0.69 | 0.64 | 0.59 | 0.44 | 0.51 |
| ForestFormer3D | native | 0.66 | 0.67 | 0.67 | 0.64 | 0.43 | 0.51 |
| ForestFormer3D | 8 | 0.63 | 0.69 | 0.66 | 0.61 | 0.44 | 0.51 |
| ForestFormer3D | 4 | 0.57 | 0.66 | 0.61 | 0.57 | 0.42 | 0.48 |
| ForestFormer3D | 2 | 0.53 | 0.66 | 0.59 | 0.52 | 0.42 | 0.46 |
| ForestFormer3D | 1 | 0.48 | 0.69 | 0.57 | 0.46 | 0.44 | 0.45 |
| TreeisoNet | native | 0.55 | 0.72 | 0.62 | 0.54 | 0.45 | 0.49 |
| TreeisoNet | 8 | 0.55 | 0.72 | 0.62 | 0.55 | 0.44 | 0.49 |
| TreeisoNet | 4 | 0.56 | 0.74 | 0.63 | 0.55 | 0.45 | 0.50 |
| TreeisoNet | 2 | 0.52 | 0.75 | 0.62 | 0.53 | 0.45 | 0.49 |
| TreeisoNet | 1 | 0.48 | 0.78 | 0.59 | 0.48 | 0.47 | 0.48 |
| SegmentAnyTree | native | 0.64 | 0.72 | 0.68 | 0.62 | 0.46 | 0.53 |
| SegmentAnyTree | 8 | 0.59 | 0.73 | 0.66 | 0.58 | 0.46 | 0.51 |
| SegmentAnyTree | 4 | 0.53 | 0.76 | 0.63 | 0.52 | 0.46 | 0.49 |
| SegmentAnyTree | 2 | 0.32 | 0.79 | 0.45 | 0.32 | 0.50 | 0.39 |
| SegmentAnyTree | 1 | 0.08 | 0.86 | 0.15 | 0.08 | 0.52 | 0.13 |

The exact 2021 check (16 tower plots, 495 censused references) moves in the
same direction: CHM-VWF native 0.79 against 0.44, TreeisoNet 0.79 against
0.43, SegmentAnyTree 0.77 against 0.44, ForestFormer3D 0.75 against 0.42,
multichm 0.67 against 0.39, Li 2012 0.69 against 0.41, AMS3D 0.27 against
0.16. The strict sensitivity (54 plots)
gives native precision about 0.01 below the headline for every arm (CHM-VWF
0.77 against 0.47, SegmentAnyTree 0.71 against 0.44, TreeisoNet 0.71 against
0.43, ForestFormer3D 0.66 against 0.41). Per site, CHM-VWF native censused
precision is 0.81 at ABBY, 0.80 at WREF and 0.65 at TEAK; SJER (2 plots) and
SOAP (1 plot) are too small to read.

- Recall barely moves, because the censused references are a subset of the
  same stems; precision moves because unsampled area no longer counts.
- SegmentAnyTree has the highest censused F1 at native density (0.68), just
  ahead of ForestFormer3D (0.67), but it falls to 0.45 at 2 and 0.15 at
  1 point/m², where its recall collapses.
- ForestFormer3D, from the corrected whole-scene re-run, ties SegmentAnyTree at
  8 points/m² (0.66). Its
  censused precision stays at 0.66–0.69 on every rung while its recall falls
  with density.
- TreeisoNet follows at 0.62, behind Li 2012 (0.64) and ahead of CHM-VWF
  (0.61). Its censused precision is the highest of the learned arms
  (0.72–0.78) and its F1 holds at 0.59–0.63 down to 1 point/m².
- At native density the F1 order of the classical arms is the same in both
  scorings (Li 2012, CHM-VWF, multichm, lmfauto, ptrees, AMS3D). At sparser
  rungs arms within about 0.02 F1 swap places; at 1 point/m² multichm
  passes AMS3D and lmfauto passes ptrees. CHM-VWF's censused precision rises
  toward sparse rungs (0.78 native, 0.86–0.87 at 8 to 1 points/m²). Arms with
  dense apexes (lmfauto, AMS3D at native density) keep low censused
  precision, so most of their commission is real.
- The [coverage-gap study](coverage-gap-results.md) credits isolated
  detections co-found by other arm families instead. Recomputed on the
  paper population, its F1 gain is +0.065 to +0.142 per arm at the default
  rule and +0.106 to +0.135 pooled across its rule grid (+0.09 to +0.26 on the
  historical D17 population). It remains a separate bracket from the censused
  scores.

ForestFormer3D is scored from the labelled clouds its re-run persisted,
reduced exactly as its sweep reduces them; TreeisoNet from the apexes its
re-run persisted, which reproduce its earlier results exactly; SegmentAnyTree
from the instance clouds of its re-run on the sealed root.

## Reproduce

```sh
export CLAUDE_JOB_DIR=/path/to/paper_runs   # links ground truth and the root
for JOIN in census_event measurement_year; do
  ROOT=$CLAUDE_JOB_DIR/reference_support_$JOIN
  for S in SJER SOAP TEAK WREF ABBY; do for Y in 2019 2020 2021 2022 2023 2024; do
    Rscript scripts/neon_reference_support.R SITE=$S YEAR=$Y JOIN=$JOIN \
      OUT=$ROOT/${S}_$Y LOCATION_CACHE=$CLAUDE_JOB_DIR/neon_location_cache
  done; done
done
for POLICY in subplot_exclusion subplot_exclusion_strict; do
  Rscript scripts/review_census_support.R POLICY=$POLICY \
    SUPPORT=$CLAUDE_JOB_DIR/reference_support_census_event \
    EVIDENCE=docs/census-support-evidence.json \
    OUT=$CLAUDE_JOB_DIR/reference_support_census_event/admission_$POLICY
done
for S in SJER SOAP TEAK WREF ABBY; do
  Rscript scripts/detect_lidrplugins_sweep.R SITE=$S CORES=16   # + AMS3D, Li 2012
done
# ForestFormer3D, TreeisoNet and SegmentAnyTree: their re-runs on the sealed
# root persist the clouds and apexes the scorer reads.
O=$CLAUDE_JOB_DIR/census_support_scores
for RULE in nearest exact; do
  D=docs/census-support-declaration-$RULE.json
  Rscript scripts/score_census_support.R DECLARATION=$D \
    ARMS=chm_vwf,lmfauto,multichm,ptrees,ams3d,forestformer3d,treeisonet,segmentanytree \
    OUT=$O/${RULE}_ladder
  Rscript scripts/score_census_support.R DECLARATION=$D \
    ARMS=chm_vwf,ptrees,ams3d,li2012 RUNGS=native OUT=$O/${RULE}_native
done
```

Years without a census event stop with "No census events in declared year".
The declarations bind the exact support identities prepared under
`reference_support_census_event`; a new preparation needs a new review. The
`-strict` declarations under `docs/` are the strict sensitivity.
`detect_lidrplugins_sweep.R` persists each detector's apexes per cell in
`<arm>_detections/`; its `chm_vwf` is the model benchmark's configuration
(density-derived CHM resolution, `a` = 0.10).

## Caveats

- The headline rule trades up to three years of growth and mortality between
  census and flight for coverage; the exact 2021 check keeps that offset at
  zero on 16 tower plots.
- Unmatched interior detections can still be real trees outside the target
  population (below 10 cm DBH, or unmapped); censused precision is relative to
  the reference, not verified all-tree precision.
- The censused reference is the census event's own records, not the
  population's nearest-measurement stems, so censused and nominal scores are
  reported side by side rather than one correcting the other.
