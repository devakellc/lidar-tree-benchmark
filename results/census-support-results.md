# Censused-Subplot Support for the Paper Population

Checked on 1 October 2026. Pooled precision over the nominal plot boxes is a
lower bound: an apex in an unsampled part of a box counts as a false positive.
This study prepares event-specific census support for the declared plot
population of the sealed frozen-clip root
([freeze_clips.R](../scripts/freeze_clips.R)) under the
[reference-support protocol](../docs/neon-reference-support-protocol.md), so
that precision can be computed only inside surveyed, censused subplots.

**Status: preparation and admission review only.** No support bundle is
admitted and no detector has been scored. Admission needs a reviewed
declaration (datum, flight provenance and, for some plots, a missing-reference
policy), and scoring needs detections persisted on the sealed frozen root,
which the arm re-runs produce.

## Preparation

`neon_reference_support.R` ran for SJER, SOAP, TEAK, WREF and ABBY and every
census year from 2019 to 2024, on the cached RELEASE-2026 woody-vegetation
data. It joins measurements to census events on plot and event, keeps the
latest mapping, builds each sampled footprint from the surveyed named-point
corners and erodes it by the largest anchor or mapping uncertainty plus 0.6 m.
Of 1,096 named points needed, NEON's location service defines 859; the other
237 are in-between grid points it does not survey.

Two preparation details matter at these sites:

- **Distributed plots list four 100 m² subplots.** Recent events record a
  distributed plot as `31_100|32_100|40_100|41_100` (400 m²), but only the
  plot's outer corners and centre are surveyed, so the 100 m² squares cannot
  be drawn. A complete 2 × 2 block is the same 20 m square as the 400 m²
  subplot anchored at its first corner, which other events use for the same
  plots; the protocol now draws it from those surveyed corners. **Such events
  census the whole distributed plot**, so the nominal ±10 m box is fully
  censused in them.
- **One WREF census spans the year boundary.** The 2020 tower census, whose
  plot records are dated July 2020, measured its 2,575 records from September
  2020 to April 2021. The protocol's measurement-year join keeps none of them
  in 2020 and rejects them as an epoch mismatch in 2021. An opt-in
  census-event join (`JOIN=census_event`) keeps every measurement of the
  year's census events. No other site has such events, so the two joins
  differ only at WREF.

## Admission review

`review_census_support.R` reports, for every plot of the declared population,
the bundle from the exact LiDAR-year census (the protocol's rule) and, as an
alternative, from the nearest all-growth-forms census within four years.
"Review only" bundles are held back only by the datum and flight-provenance
review that every bundle carries. "Missing-reference policy" bundles also
have target records excluded for missing or flagged mappings, which need a
declared missing-reference policy before admission. Counts are plots with
selected interior references in brackets, `adopted` population, census-event
join.

| Site | Plots | Exact 2021: review only | Exact 2021: missing-reference policy | Nearest census: review only | Nearest census: missing-reference policy | Nearest census: not admissible |
| --- | --- | --- | --- | --- | --- | --- |
| SJER | 6 | 0 | 0 | 0 | 6 (25) | 0 |
| SOAP | 18 | 0 | 1 (28) | 0 | 7 (122) | 11 |
| TEAK | 19 | 2 (34) | 1 (61) | 8 (95) | 4 (87) | 7 |
| WREF | 38 | 3 (139) | 1 (28) | 20 (460) | 10 (402) | 8 |
| ABBY | 25 | 7 (256) | 3 (155) | 14 (355) | 7 (251) | 4 |
| **Total** | **106** | **12 (429)** | **6 (272)** | **42 (910)** | **34 (887)** | **30** |

- **Exact LiDAR year:** 18 tower plots, holding 787 of the 2,525 core stems
  (31%), could be admitted; no distributed plot was censused in 2021. Of the
  other 88 plots, 63 had no 2021 census, 19 only a dendrometer census, 4
  have a mapped stem outside its recorded subplot beyond its uncertainty, and
  2 (ABBY_074 and ABBY_075) list 800 m² of subplots against a 400 m² total.
- **Nearest census within four years:** 76 plots (45 tower, 31 distributed),
  holding 2,051 core stems (81%), could be admitted. Offsets from 2021 range
  from −1 to +3 years (15, 18, 23, 6 and 14 plots at −1, 0, +1, +2 and +3).
  Twenty plots have no all-growth-forms census in the window; the 2019 and
  2020 events at SOAP and WREF carry no `dataCollected` field and fail closed.
  Without the census-event join, WREF drops to 21 plots and the total to 67.
- Under the `all_mapped` and `relaxed` populations the exact rule again gives
  18 plots; the nearest-census rule gives 81 of 116 and 92 of 149.
- The support reference is the census event's own target records, not the
  population's nearest-measurement stems: in the admissible plots, 72% of the
  population's core stems were measured in the support event's year. Scores
  are therefore reported side by side, not as a correction of one another.
- Tower interiors cover 631–783 m² of the 1,600 m² nominal box; distributed
  interiors 299–383 m² of 400 m².

### The 2015 tower census

Forty-seven tower plots carry live stems of at least 10 cm DBH measured in the
2015 census. Every 2015 event declares 800 m² of sampled tree area but lists
no subplots, while the stem records of most SOAP and TEAK tower plots fall in
three or four of the 400 m² quadrants. The records thus contradict the
declared area, and the 2015 census cannot be admitted as support; a 2015
reference epoch would need its own declared footprint.

## Scoring step

`score_census_support.R` scores persisted detections only. For each plot a
reviewed declaration admits (`neon_admit_support()`, which accepts only the
exact bundle identity and only review blockers), every arm and rung is scored
inside the interior: recall uses the matching tolerance around it, precision
counts interior detections only. The nominal-box score of the same detections
against the declared population is kept alongside (`rect_*`), and pooling sums
counts over cells every arm scored, with support identities preserved.
Detections are read, in this order, from `<arm>_detections/<plot>__<rung>.csv`
(apexes an arm persists), the arm's instance clouds (SegmentAnyTree, AMS3D,
ptrees, Li 2012, Treeiso; SegmentAnyTree heights through the frozen DTM) and
`best_treetop_cache`. Every directory must carry the sealed root's stamp.

## Reproduce

```sh
export CLAUDE_JOB_DIR=/path/to/paper_runs   # links ground truth and the root
for JOIN in measurement_year census_event; do
  ROOT=$CLAUDE_JOB_DIR/reference_support_$JOIN
  for S in SJER SOAP TEAK WREF ABBY; do for Y in 2019 2020 2021 2022 2023 2024; do
    Rscript scripts/neon_reference_support.R SITE=$S YEAR=$Y JOIN=$JOIN \
      OUT=$ROOT/${S}_$Y LOCATION_CACHE=$CLAUDE_JOB_DIR/neon_location_cache
  done; done
  Rscript scripts/review_census_support.R SUPPORT=$ROOT
done
# after a reviewed declaration and the arm re-runs:
Rscript scripts/score_census_support.R DECLARATION=reviewed.json \
  SUPPORT=$CLAUDE_JOB_DIR/reference_support_census_event
```

Years without a census event stop with "No census events in declared year".
`review_census_support.R` writes the per-plot table, the counts and a draft
declaration listing the 12 exact-year bundles held back only by review
blockers; `score_census_support.R` refuses a draft.

## Caveats

- Admission is a decision, not a computation: the datum review (NEON field
  points and the 2021 tiles share each site's WGS84 UTM frame; NEON's AOP
  specification names ITRF00) and the flight provenance remain to be
  declared, and choosing the nearest-census rule trades up to three years of
  growth and mortality for coverage.
- Unmatched interior detections can still be real trees outside the target
  population (below 10 cm DBH, or unmapped); censused precision is relative to
  the reference, not verified all-tree precision.
- Credited F1 from the [coverage-gap study](coverage-gap-results.md) is a
  separate correction and stays a bracket with its sensitivity grid.
