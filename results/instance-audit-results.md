# Instance audit of the learned arms

Checked on 7 October 2026 on the frozen five-site `adopted` population from the
persisted outputs of the paper runs; no detector was run again
(`scripts/instance_audit.R`, outputs in
`paper_runs/sensitivity/instance_audit_*.csv`). Four questions from the review
of the paper draft: whether SegmentAnyTree's collapse on sparse clouds is a
failure of its learned semantics or of its instance grouping; how many of the
learned arms' apexes lie below the 2 m height floor that every classical arm
applies; how much of CHM-VWF's and TreeisoNet's commission falls on mapped dead
stems; and what the reference stands look like per site.

## Instance assignment by density

Points inside the nominal plot cores of the 106 plots, pooled over the five
sites. For SegmentAnyTree the tree share is the share of core points its
semantic head labels as tree (`PredSemantic`); for both segmenters the assigned
share is the share of core points grouped into an instance (`PredInstance` or
`PointSourceID` above zero), and instance sizes count the core points of each
instance. Apexes below 2 m are core detections that the classical arms' height
floor would have removed (CHM-VWF has a 2 m floor by construction).

| Arm | Rung | Tree share | Assigned share | Assigned share of tree points | Core instances | Mean points per instance | Core apexes | Apexes below 2 m | Share |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| segmentanytree | native | 0.721 | 0.618 | 0.857 | 4449 | 272 | 3349 | 0 | 0.0% |
| segmentanytree | 8 | 0.704 | 0.535 | 0.759 | 4064 | 110 | 3063 | 0 | 0.0% |
| segmentanytree | 4 | 0.738 | 0.402 | 0.544 | 3409 | 49 | 2647 | 0 | 0.0% |
| segmentanytree | 2 | 0.798 | 0.183 | 0.230 | 1751 | 22 | 1444 | 0 | 0.0% |
| segmentanytree | 1 | 0.893 | 0.046 | 0.052 | 374 | 13 | 320 | 0 | 0.0% |
| forestformer3d | native | — | 0.669 | — | 4706 | 278 | 3441 | 25 | 0.7% |
| forestformer3d | 8 | — | 0.636 | — | 4437 | 119 | 3246 | 40 | 1.2% |
| forestformer3d | 4 | — | 0.610 | — | 4158 | 62 | 3142 | 81 | 2.6% |
| forestformer3d | 2 | — | 0.572 | — | 3772 | 32 | 2971 | 126 | 4.2% |
| forestformer3d | 1 | — | 0.548 | — | 3243 | 18 | 2623 | 151 | 5.8% |
| treeisonet | native | — | — | — | — | — | 3032 | 2 | 0.1% |
| treeisonet | 8 | — | — | — | — | — | 3091 | 0 | 0.0% |
| treeisonet | 4 | — | — | — | — | — | 3066 | 2 | 0.1% |
| treeisonet | 2 | — | — | — | — | — | 2842 | 4 | 0.1% |
| treeisonet | 1 | — | — | — | — | — | 2448 | 7 | 0.3% |
| chm_vwf | native | — | — | — | — | — | 2475 | 0 | 0.0% |
| chm_vwf | 8 | — | — | — | — | — | 1510 | 0 | 0.0% |
| chm_vwf | 4 | — | — | — | — | — | 1498 | 0 | 0.0% |
| chm_vwf | 2 | — | — | — | — | — | 1424 | 0 | 0.0% |
| chm_vwf | 1 | — | — | — | — | — | 1337 | 0 | 0.0% |

**Readings.**

- SegmentAnyTree's semantic head keeps labelling 70 to 89% of the core points as
  tree down the ladder, while the share of those points it groups into an
  instance falls from 0.86 at native density to 0.76, 0.54, 0.23 and 0.05, and
  the mean points per core instance from 272 to 13. The collapse is a failure of
  instance grouping, not of the learned semantics: the model groups points with
  a search radius of 1.5 grid cells (0.3 m at its 0.2 m grid), and the mean
  point spacing of the clouds grows from 0.24 m at native density to 0.53 m at
  the QL2 rung and 0.95 m at 0.6 pulses/m².
- ForestFormer3D keeps grouping: 0.67 to 0.55 of its core points stay in
  instances, with 278 to 18 points each; its mask decoder keeps instances of at
  least 10 points, so it degrades with the point count instead of collapsing.
- The learned arms carry no height floor on NEON. ForestFormer3D's core apexes
  below 2 m are 0.7% at native density and 1.2, 2.6, 4.2 and 5.8% on the rungs;
  SegmentAnyTree has none and TreeisoNet at most 0.3%. Removing ForestFormer3D's
  as false positives would raise its five-site F1 by +0.002 at native density,
  +0.004 at 4.7, +0.007 at 2.5, +0.011 at 1.3 and +0.013 at 0.6 pulses/m²
  (recomputed from the pooled counts). In the within-rung order by F1 that
  would lift ForestFormer3D to a nominal second at 1.3 pulses/m² (0.449 against
  TreeisoNet's 0.444 and `multichm`'s 0.440) and a nominal third at 0.6
  (0.0002 above `multichm`); the order at the other rungs is unchanged and the
  rank break below the QL2 floor remains. The FGI-EMIT thinning protocol
  applies a 2 m apex rule to the same arms, so its NEON comparison columns are
  scored without a floor the FGI-EMIT rows have.
- SegmentAnyTree returned no core detection in 2 of the 106 plots at 1.3
  pulses/m² and in 19 at 0.6; ForestFormer3D, `ptrees` and AMS3D each in one
  plot at 0.6. Empty cells are scored as zero recall, not dropped.

## Dead stems and commission

Mapped dead stems of at least 10 cm DBH measured within the four-year reference
window (`live` false in `ground_truth_stems.csv`): 498 inside the cores. For
CHM-VWF and TreeisoNet at native density the detections within the core plus 4 m
were matched to the live reference stems with the paper's greedy matcher and
height gate; a core false positive or true positive is near a dead stem when one
lies within the given distance.

| Arm | Core false positives | Within 4 m of a dead stem | Within 2 m | True positives | True positives within 4 m | Live reference stems within 4 m of a dead stem |
| --- | --- | --- | --- | --- | --- | --- |
| treeisonet | 1837 | 155 (8.4%) | 64 (3.5%) | 1195 | 255 (21.3%) | 789 (31.2%) |
| chm_vwf | 1392 | 118 (8.5%) | 51 (3.7%) | 1083 | 224 (20.7%) | 789 (31.2%) |

False positives sit near dead stems less often than true positives do (8%
against 21%), and 31% of the live stems have a dead neighbour within 4 m, so
detections of mapped dead trees are a minor part of the commission; removing
dead-adjacent false positives would raise CHM-VWF's pooled precision by about
0.02 (SOAP about 0.04), against +0.29 to +0.34 from the censused subplots.

## Reference stands

Per site, from the frozen population files: mapped stems and basal area per
hectare of nominal plot core, field heights (with the number of stems that have
one) and diameters, and the three most frequent species with their stem counts.

| Site | Plots | Core area (ha) | Stems | Stems/ha | Basal area (m²/ha) | Median height (m) (n) | Maximum height (m) | Median DBH (cm) | Main species (stems) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SJER | 6 | 0.96 | 57 | 59 | 3.4 | 7.4 (28) | 17.7 | 19.3 | Quercus wislizeni (33); Quercus douglasii (19); Pinus sabiniana (5) |
| SOAP | 18 | 1.56 | 231 | 148 | 13.2 | 10.1 (228) | 51.4 | 24.6 | Calocedrus decurrens (85); Quercus chrysolepis (75); Pinus ponderosa (50) |
| TEAK | 19 | 1.48 | 374 | 253 | 32.1 | 10.3 (368) | 49.3 | 22.2 | Abies magnifica (114); Abies concolor (82); Pinus contorta (74) |
| WREF | 38 | 3.92 | 1063 | 271 | 29.2 | 16.5 (1039) | 63.0 | 21.0 | Tsuga heterophylla (460); Pseudotsuga menziesii (365); Abies amabilis (150) |
| ABBY | 25 | 2.56 | 800 | 312 | 13.2 | 10.7 (800) | 62.6 | 14.3 | Pseudotsuga menziesii (748); Tsuga heterophylla (19); Alnus rubra (17) |

## Reproduce

```sh
CLAUDE_JOB_DIR=work/paper_runs Rscript scripts/instance_audit.R CORES=8
```
