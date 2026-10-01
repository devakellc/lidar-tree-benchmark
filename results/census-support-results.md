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
  target tree that is not a usable reference leaves the precision interior;
  recall keeps the references in the remaining interior; a missing target in
  an unknown subplot fails the plot closed.
- **Datum and flight provenance** are resolved by a reviewed declaration with
  written evidence ([evidence](../docs/census-support-evidence.json),
  [headline declaration](../docs/census-support-declaration-nearest.json),
  [check declaration](../docs/census-support-declaration-exact.json)).

Under the headline rule **54 of the 106 adopted plots** (32 tower, 22
distributed) are scored, holding 1,448 of the 2,525 core stems (57%); the
check admits 16 tower plots (680 stems). On identical detections, censused
precision is 0.09–0.35 higher than nominal-box precision for every arm and
rung; CHM-VWF at native density rises from 0.47 to 0.77.

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

A census target that cannot be a reference (no usable mapped position or
height, a flagged or duplicate record) still stands in its subplot, where a
correct detection would count as a false positive. Subplot exclusion removes
each such subplot before erosion. For a distributed plot drawn as one block,
that removes the whole plot. Under the headline rule 38 candidate plots hold
158 missing targets out of 1,265: 70 without mapped coordinates, 46 without a
height, 28 with a flagged mapping, 7 duplicate records and 7 in an unlisted
or unknown subplot.

| Site | Plots with missing targets | Missing / targets | Interior before → after, m² | Plots lost | Plots kept |
| --- | --- | --- | --- | --- | --- |
| SJER | 6 | 42 / 71 | 4,298 → 1,384 | 4 | 2 |
| SOAP | 7 | 47 / 177 | 4,961 → 991 | 6 | 1 |
| TEAK | 7 | 36 / 194 | 3,055 → 719 | 5 | 0 |
| WREF | 11 | 22 / 532 | 6,798 → 2,304 | 4 | 6 |
| ABBY | 7 | 11 / 291 | 3,674 → 1,097 | 4 | 3 |
| **Total** | **38** | **158 / 1,265** | **22,786 → 6,495** | **23** | **12** |

The policy removes 71% of these plots' interior and costs 23 plots outright:
emptied, or failed closed for a missing target without a known subplot (five
plots). SJER and SOAP_050 (25 of 51 targets missing) are the heavy cases.
Under the exact 2021 check it touches 8 plots (14 of 401 targets missing),
removes 3,293 of 5,750 m² and costs 2 plots.

## Admission

Plots of the `adopted` population scored under each rule, after the policy:

| Site | Plots | Headline: admitted (tower / distributed) | Headline: not admitted | Check: admitted |
| --- | --- | --- | --- | --- |
| SJER | 6 | 2 (2 / 0) | 4 | 0 |
| SOAP | 18 | 1 (1 / 0) | 17 | 0 |
| TEAK | 19 | 8 (2 / 6) | 11 | 2 |
| WREF | 38 | 26 (17 / 9) | 12 | 4 |
| ABBY | 25 | 17 (10 / 7) | 8 | 10 |
| **Total** | **106** | **54 (32 / 22)** | **52** | **16** |

Under the headline rule the 52 plots not admitted break down as: 20 without
an all-growth-forms census in the window (the 2019 and 2020 SOAP and WREF
events carry no `dataCollected` field and fail closed), 23 lost to the
missing-reference policy, 5 with a mapped stem outside its recorded subplot,
and 4 whose geometry fails (missing corner uncertainty, an invalid polygon or
a quality-flagged event). The admitted censuses lie −1 to +3 years from 2021
(13, 16, 15, 1 and 9 plots at −1, 0, +1, +2 and +3). Joining by measurement
year instead would admit 46 plots rather than 54. Under the check rule no
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

SJER was flown with a different sensor than the other four sites in 2021.

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
interior) and, on the same detections, against the population's references
in the nominal box. Pooled counts over the 54 headline plots (1,070 censused
references, 1,448 nominal) at every rung where every arm has a cell:

| Arm | Rung | Recall | Precision | F1 | Nominal recall | Nominal precision | Nominal F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CHM-VWF | native | 0.51 | 0.77 | 0.61 | 0.50 | 0.47 | 0.49 |
| CHM-VWF | 8 | 0.36 | 0.84 | 0.51 | 0.34 | 0.50 | 0.41 |
| CHM-VWF | 4 | 0.36 | 0.84 | 0.51 | 0.35 | 0.51 | 0.42 |
| CHM-VWF | 2 | 0.34 | 0.85 | 0.48 | 0.33 | 0.50 | 0.40 |
| CHM-VWF | 1 | 0.33 | 0.86 | 0.48 | 0.31 | 0.52 | 0.39 |
| multichm | native | 0.57 | 0.62 | 0.60 | 0.56 | 0.40 | 0.46 |
| multichm | 8 | 0.58 | 0.62 | 0.60 | 0.57 | 0.38 | 0.46 |
| multichm | 4 | 0.57 | 0.61 | 0.59 | 0.54 | 0.38 | 0.45 |
| multichm | 2 | 0.55 | 0.59 | 0.57 | 0.54 | 0.38 | 0.44 |
| multichm | 1 | 0.53 | 0.61 | 0.57 | 0.51 | 0.38 | 0.43 |
| lmfauto | native | 0.61 | 0.47 | 0.53 | 0.60 | 0.29 | 0.39 |
| lmfauto | 8 | 0.61 | 0.38 | 0.47 | 0.61 | 0.24 | 0.34 |
| lmfauto | 4 | 0.64 | 0.28 | 0.39 | 0.64 | 0.17 | 0.27 |
| lmfauto | 2 | 0.73 | 0.25 | 0.37 | 0.72 | 0.15 | 0.25 |
| lmfauto | 1 | 0.77 | 0.25 | 0.38 | 0.78 | 0.15 | 0.25 |
| ptrees | native | 0.75 | 0.37 | 0.50 | 0.74 | 0.23 | 0.35 |
| ptrees | 8 | 0.57 | 0.62 | 0.60 | 0.58 | 0.40 | 0.47 |
| ptrees | 4 | 0.45 | 0.73 | 0.56 | 0.44 | 0.46 | 0.45 |
| ptrees | 2 | 0.32 | 0.79 | 0.45 | 0.31 | 0.50 | 0.38 |
| ptrees | 1 | 0.22 | 0.81 | 0.34 | 0.20 | 0.49 | 0.29 |
| AMS3D | native | 0.71 | 0.24 | 0.36 | 0.73 | 0.15 | 0.25 |
| AMS3D | 8 | 0.70 | 0.34 | 0.45 | 0.73 | 0.21 | 0.33 |
| AMS3D | 4 | 0.69 | 0.46 | 0.55 | 0.70 | 0.28 | 0.40 |
| AMS3D | 2 | 0.59 | 0.67 | 0.63 | 0.61 | 0.39 | 0.47 |
| AMS3D | 1 | 0.42 | 0.81 | 0.55 | 0.41 | 0.49 | 0.44 |
| Li 2012 | native | 0.60 | 0.68 | 0.64 | 0.60 | 0.42 | 0.50 |

The exact 2021 check (16 tower plots, 495 censused references) moves in the
same direction: CHM-VWF native 0.79 against 0.44, multichm 0.67 against 0.39,
Li 2012 0.69 against 0.41, AMS3D 0.27 against 0.16. Per site, CHM-VWF native
censused precision is 0.81 at ABBY, 0.78 at WREF and 0.63 at TEAK; SJER (2
plots) and SOAP (1 plot) are too small to read.

- Recall barely moves, because the censused references are a subset of the
  same stems; precision moves because unsampled area no longer counts.
- F1 levels rise but the ordering of the classical arms at each rung does
  not change (native: Li 2012, CHM-VWF, multichm, lmfauto, ptrees, AMS3D in
  both scorings). CHM-VWF's censused precision rises toward sparse rungs
  (0.77 native, 0.84–0.86 at 8 to 1 points/m²). Arms with dense apexes
  (lmfauto, AMS3D at native density) keep low censused precision, so most of
  their commission is real.
- The [coverage-gap study](coverage-gap-results.md) credits isolated
  detections co-found by other arm families instead; on the historical D17
  population its pooled F1 gain ranged from +0.09 to +0.26 across its rule
  grid. It remains a separate bracket and has not yet been recomputed on the
  paper population.

ForestFormer3D, TreeisoNet and SegmentAnyTree join this table once their
re-runs on the sealed root persist detections.

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
Rscript scripts/review_census_support.R \
  SUPPORT=$CLAUDE_JOB_DIR/reference_support_census_event \
  EVIDENCE=docs/census-support-evidence.json
for S in SJER SOAP TEAK WREF ABBY; do
  Rscript scripts/detect_lidrplugins_sweep.R SITE=$S CORES=16   # + AMS3D, Li 2012
done
O=$CLAUDE_JOB_DIR/census_support_scores
for RULE in nearest exact; do
  D=docs/census-support-declaration-$RULE.json
  Rscript scripts/score_census_support.R DECLARATION=$D \
    ARMS=chm_vwf,lmfauto,multichm,ptrees,ams3d OUT=$O/${RULE}_ladder
  Rscript scripts/score_census_support.R DECLARATION=$D \
    ARMS=chm_vwf,ptrees,ams3d,li2012 RUNGS=native OUT=$O/${RULE}_native
done
```

Years without a census event stop with "No census events in declared year".
The declarations bind the exact support identities prepared under
`reference_support_census_event`; a new preparation needs a new review.
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
