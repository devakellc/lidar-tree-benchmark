# SegmentAnyTree with a grouping radius scaled to the point spacing

Checked on 23 October 2026, after the paper's tables were fixed, on the fixed
evaluation clips of the paper and its zero-shot SegmentAnyTree runs; no table
of the paper changes. The [instance audit](instance-audit-results.md) found
that SegmentAnyTree's semantic head keeps labelling most points of sparse clouds
as tree while the share of those points it groups into trees falls towards
zero. Its clustering region-grows the offset-shifted tree points within
`cluster_radius_search`, 1.5 grid cells (0.3 m at its 0.2 m grid), while the
mean point spacing grows to 0.95 m on the sparsest clips. The check asks
whether widening that radius with the point spacing restores the detector on
sparse clouds. It does not.

Regenerate (the GPU step needs the `sat-sm120-test` image, see the
[SegmentAnyTree runtime](../gpu/segmentanytree-sm120/README.md)):

```sh
RUNS=$(pwd)/work/paper_runs OUT=$(pwd)/work/sat_radius_check
Rscript scripts/sat_radius_check.R MODE=prep RUNS=$RUNS OUT=$OUT
bash gpu/run_sat_radius_check.sh $OUT 4
Rscript scripts/sat_radius_check.R MODE=score RUNS=$RUNS OUT=$OUT
```

## Design

- **Cells.** 10 California plots of the adopted population, per site evenly
  spaced in plot-ID order among the plots with zero-shot results at both levels
  (SJER_046 and SJER_053; SOAP_001, SOAP_013, SOAP_031 and SOAP_057; TEAK_001,
  TEAK_012, TEAK_020 and TEAK_052), at the 2 and 1 point/m² density levels: 2.1
  to 2.3 and 1.06 to 1.15 points/m² of all returns on these clips (five-site
  medians of 1.3 and 0.6 first-return pulses/m²). The Washington plots were not
  used.
- **Arms.** The upstream radius, 0.3 m (the paper's zero-shot runs); `scaled`,
  1.5 × max(0.2 m, s), where s = 1/√(all-return density) is the clip's mean
  point spacing, so 1.5 grid cells with the cell widened to the spacing: 0.99 to
  1.03 m at 2 and 1.40 to 1.46 m at 1 point/m²; and `double`, twice that, 1.99
  to 2.91 m (1.0 to 2.9 m over both arms). Only the radius of the region growing
  changes, through the opt-in `SAT_CLUSTER_RADIUS` of the compatibility shims
  ([usercustomize.py](../gpu/sat_compat/usercustomize.py)); the checkpoint,
  every other setting and the clips are the paper's. Every job with a changed
  radius logged it.
- **Control.** Two cells re-run with the upstream radius through the same route:
  each clip is copied into its container and the instance cloud copied out, no
  host directory mounted
  ([run_sat_radius_check.sh](../gpu/run_sat_radius_check.sh)).
- **Scoring.** As the SegmentAnyTree sweep scores a cell (instance apexes,
  height above the clip's terrain model, greedy matching at 4 m on the plot
  core), with the paper's chance null of 200 shifted copies per plot for the
  corrected F1, (F1 − null F1)/(1 − null F1). Scores pool summed counts over
  the 10 plots; intervals are 95% paired plot-bootstrap intervals (2,000
  draws).
- **Criteria, set before any changed-radius job had finished.** The control
  must reproduce the paper's rows. Go for a full run if the better arm gains at
  least 0.05 F1 over the zero-shot run at both levels with a paired interval
  above zero, and at least 0.10 at 1 point/m²; otherwise no-go.

## Results

The control reproduces the paper's rows exactly: SOAP_001 at 1 point/m² has no
core detection in either run, and TEAK_001 at 2 points/m² has 2 matched stems,
1 core detection, F1 0.364 and the same null counts in both.

### Pooled scores on the 10 cells per level

| Level | Arm | Core detections | Recall | Precision | F1 | Corrected F1 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 2 points/m² | Zero-shot (0.3 m) | 111 | 0.333 | 0.342 | 0.338 | 0.190 |
| 2 points/m² | Scaled (about 1.0 m) | 114 | 0.341 | 0.351 | 0.346 | 0.192 |
| 2 points/m² | Double (about 2.0 m) | 69 | 0.242 | 0.464 | 0.318 | 0.210 |
| 2 points/m² | ForestFormer3D | 268 | 0.598 | 0.269 | 0.371 | 0.206 |
| 2 points/m² | `multichm` | 234 | 0.598 | 0.282 | 0.383 | 0.194 |
| 2 points/m² | CHM-VWF | 119 | 0.371 | 0.395 | 0.383 | 0.244 |
| 1 point/m² | Zero-shot (0.3 m) | 28 | 0.114 | 0.536 | 0.188 | 0.131 |
| 1 point/m² | Scaled (about 1.4 m) | 38 | 0.129 | 0.447 | 0.200 | 0.121 |
| 1 point/m² | Double (about 2.8 m) | 36 | 0.136 | 0.500 | 0.214 | 0.151 |
| 1 point/m² | ForestFormer3D | 265 | 0.576 | 0.264 | 0.362 | 0.214 |
| 1 point/m² | `multichm` | 238 | 0.583 | 0.290 | 0.387 | 0.198 |
| 1 point/m² | CHM-VWF | 119 | 0.394 | 0.412 | 0.403 | 0.266 |

### Paired differences

| Level | Contrast | F1 | Corrected F1 |
| --- | --- | --- | --- |
| 2 points/m² | Scaled minus zero-shot | +0.008 [−0.015, +0.036] | +0.002 [−0.019, +0.033] |
| 2 points/m² | Double minus zero-shot | −0.019 [−0.105, +0.058] | +0.021 [−0.076, +0.107] |
| 1 point/m² | Scaled minus zero-shot | +0.013 [−0.026, +0.054] | −0.009 [−0.051, +0.032] |
| 1 point/m² | Double minus zero-shot | +0.027 [−0.041, +0.117] | +0.020 [−0.049, +0.120] |
| 1 point/m² | Scaled minus ForestFormer3D | −0.162 [−0.283, −0.037] | −0.092 [−0.193, +0.007] |
| 1 point/m² | Scaled minus `multichm` | −0.187 [−0.331, −0.047] | −0.076 [−0.209, +0.045] |

The contrasts of both arms with ForestFormer3D and `multichm` at both levels
are in `contrasts.csv`.

### Grouping of the core points

Core points of the 10 plots pooled; the tree points are those the semantic head
labels as tree, the same in every arm. An instance holds a stem when the stem's
mapped position lies inside the convex hull of the instance's core points;
instances holding two or more of the mapped reference stems have merged trees.

| Level | Arm | Tree points in an instance | Core instances | Points per instance | Instances holding 2+ stems | Their share of grouped points |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 2 points/m² | Zero-shot | 0.229 | 126 | 20.8 | 0 | 0.000 |
| 2 points/m² | Scaled | 0.272 | 133 | 23.4 | 1 | 0.015 |
| 2 points/m² | Double | 0.652 | 90 | 82.7 | 16 | 0.472 |
| 1 point/m² | Zero-shot | 0.050 | 31 | 12.1 | 0 | 0.000 |
| 1 point/m² | Scaled | 0.099 | 46 | 16.1 | 0 | 0.000 |
| 1 point/m² | Double | 0.401 | 49 | 61.7 | 7 | 0.493 |

## Readings

- **Scaling the radius with the point spacing does not restore SegmentAnyTree
  on sparse clouds.** F1 changes by −0.019 to +0.027 and corrected F1 by
  −0.009 to +0.021, every interval including zero, and the core detections
  stay at a tenth to under half of ForestFormer3D's. No arm meets the go
  criterion, so no full run follows.
- **A wider radius groups more of the tree points, but merges trees.** At 1
  point/m² the doubled radius puts 0.40 of the tree points in an instance
  instead of 0.05, yet the instances rise only from 31 to 49 and grow from 12
  to 62 points each; at 2 points/m² they fall from 126 to 90. With the doubled
  radius 7 of 49 and 16 of 90 instances hold two or more mapped stems, and
  they carry about half of the grouped points; with the upstream radius none
  do, and with the scaled radius one. A radius small enough to keep trees apart
  does not join one tree's points, and one large enough to join them merges
  trees. This is consistent with offsets that, at these densities, no longer
  gather a tree's points near its centre; the check does not test the offsets
  directly.
- **For the paper.** The collapse remains a failure of the grouping, not of
  the semantic labels, but the fixed 0.3 m radius does not explain it alone.
  Section 6.2 and the note to Table S18a say so, and give these two results.

## Caveats

- Post hoc and small: 10 plots of the development region at two density
  levels, chosen by rule before any result. The intervals are wide: the
  doubled radius's at 1 point/m² reaches +0.117 F1, so 10 plots cannot exclude
  a gain of that size, though the estimate is +0.027 and half of the points
  that arm groups sit in instances holding two or more mapped stems.
- The stem count uses the mapped reference stems only (live, DBH ≥ 10 cm), so
  it misses merges with unmapped trees and undercounts merging.
- One setting changed: the region-growing radius. The 10-point minimum cluster
  size, the embedding clustering, the score network and the non-maximum
  suppression keep their upstream values.
- Not in the reproduction archive, like the ForestMamba runs; the instance
  clouds, logs and tables are regenerated with the commands above.

## Outputs

Under `OUT`: `manifest.csv` (cells, densities, radii), `jobs.tsv`, `in/` (the
clips as PLY), `out/` (one instance cloud per job), `logs/`, `scores.csv` (one
row per job and per comparison cell, with null and grouping counts),
`control.csv`, `summary.csv`, `contrasts.csv` and `grouping.csv`. Each job took
256 to 453 s, about six minutes on average with four containers running at
once on an RTX 5090.
