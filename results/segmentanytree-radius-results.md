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

Regenerate into a fresh `OUT` (the GPU step needs the `sat-sm120-test` image,
see the [SegmentAnyTree runtime](../gpu/segmentanytree-sm120/README.md)):

```sh
RUNS=$(pwd)/work/paper_runs OUT=$(pwd)/work/sat_radius_check
Rscript scripts/sat_radius_check.R MODE=prep RUNS=$RUNS OUT=$OUT
bash gpu/run_sat_radius_check.sh $OUT 4
Rscript scripts/sat_radius_check.R MODE=score RUNS=$RUNS OUT=$OUT
```

The run reported here wrote to `work/sat_radius_pilot`. Its GPU jobs ran
through the first version of the runner, with the same container command and
compatibility shims. The committed `MODE=prep` reproduces its clips, cells and
jobs byte for byte, the committed `MODE=score` reproduces its tables exactly,
and one job re-run through the committed runner reproduced its instance cloud
point for point.

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
  ([usercustomize.py](../gpu/sat_compat/usercustomize.py)), which leaves every
  run without it unchanged; the checkpoint, every other setting and the clips
  are the paper's.
- **Runs.** One container per job
  ([run_sat_radius_check.sh](../gpu/run_sat_radius_check.sh)): the clip is
  copied in and the instance cloud copied out, no host directory mounted. An
  output is kept only when the container exits 0 and its log shows the shim's
  line for exactly the job's radius, or no override for a control job;
  `MODE=score` checks the logs again. Every job passed.
- **Control.** Two cells re-run with the upstream radius through the same
  route; `MODE=score` stops unless they reproduce the paper's rows.
- **Scoring.** As the SegmentAnyTree sweep scores a cell (instance apexes,
  height above the clip's terrain model, greedy matching at 4 m on the plot
  core), with the paper's chance null of 200 shifted copies per plot for the
  corrected F1, (F1 − null F1)/(1 − null F1). Scores pool summed counts over
  the 10 plots; intervals are 95% paired plot-bootstrap intervals (2,000
  draws).

### Criteria

Written after the first control job and before any changed-radius job had
finished, in these words:

> - Control: the upstream-radius re-runs must reproduce the paper's rows (same
>   TP, detections and core TP). If not, the pilot is void.
> - Go for the full run if the better arm, at both levels, gains at least 0.05
>   F1 over zero-shot SegmentAnyTree with a paired interval above zero, and at
>   1 point/m2 at least 0.10.
> - A strong go if that arm is also within 0.03 F1 of the better of
>   ForestFormer3D and multichm on the same cells at both levels.
> - No-go otherwise; the result then goes into the reply to reviewers, not the
>   paper.
> - Whatever the outcome, the radius rule for the paper is chosen on California
>   only and checked on Washington; the pilot does not choose it alone.

The result is a no-go. The fourth rule was then set aside: the paper's account
of the collapse had leaned on the fixed radius, which the check contradicts, so
the author chose to report the check in the supplement and to correct the
account rather than leave it for the reply to reviewers. The fifth rule applies
only to a go.

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

Every contrast the check computes:

| Level | Contrast | F1 | Corrected F1 |
| --- | --- | --- | --- |
| 2 points/m² | Scaled minus zero-shot | +0.008 [−0.015, +0.036] | +0.002 [−0.019, +0.033] |
| 2 points/m² | Double minus zero-shot | −0.019 [−0.105, +0.058] | +0.021 [−0.076, +0.107] |
| 2 points/m² | Scaled minus ForestFormer3D | −0.025 [−0.149, +0.079] | −0.014 [−0.142, +0.083] |
| 2 points/m² | Scaled minus `multichm` | −0.038 [−0.161, +0.068] | −0.001 [−0.137, +0.105] |
| 2 points/m² | Double minus ForestFormer3D | −0.052 [−0.214, +0.096] | +0.004 [−0.143, +0.131] |
| 2 points/m² | Double minus `multichm` | −0.065 [−0.208, +0.068] | +0.017 [−0.107, +0.134] |
| 1 point/m² | Scaled minus zero-shot | +0.013 [−0.026, +0.054] | −0.009 [−0.051, +0.032] |
| 1 point/m² | Double minus zero-shot | +0.027 [−0.041, +0.117] | +0.020 [−0.049, +0.120] |
| 1 point/m² | Scaled minus ForestFormer3D | −0.162 [−0.283, −0.037] | −0.092 [−0.193, +0.007] |
| 1 point/m² | Scaled minus `multichm` | −0.187 [−0.331, −0.047] | −0.076 [−0.209, +0.045] |
| 1 point/m² | Double minus ForestFormer3D | −0.148 [−0.301, +0.030] | −0.062 [−0.200, +0.095] |
| 1 point/m² | Double minus `multichm` | −0.173 [−0.355, +0.026] | −0.046 [−0.212, +0.130] |

On 10 plots only the scaled radius at 1 point/m² is clearly below
ForestFormer3D and `multichm`, and only in F1.

### Grouping of the core points

Core points of the 10 plots pooled; the tree points are those the semantic head
labels as tree, the same in every arm. An instance holds a stem when the stem's
mapped position lies inside the convex hull of the instance's core points. The
zero-shot clouds of the same plots at native density and at 8 and 4 points/m²
(five-site medians of 9.8, 4.7 and 2.5 first-return pulses/m²) give the
baseline of the stem test.

| Level | Arm | Tree points in an instance | Core instances | Points per instance | Instances holding 2+ stems | Their share of grouped points | Most stems in one instance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Native | Zero-shot | 0.952 | 373 | 243.4 | 25 | 0.138 | 6 |
| 8 points/m² | Zero-shot | 0.836 | 333 | 87.3 | 18 | 0.094 | 6 |
| 4 points/m² | Zero-shot | 0.621 | 280 | 41.8 | 10 | 0.058 | 4 |
| 2 points/m² | Zero-shot | 0.229 | 126 | 20.8 | 0 | 0.000 | 1 |
| 2 points/m² | Scaled | 0.272 | 133 | 23.4 | 1 | 0.015 | 2 |
| 2 points/m² | Double | 0.652 | 90 | 82.7 | 16 | 0.472 | 21 |
| 1 point/m² | Zero-shot | 0.050 | 31 | 12.1 | 0 | 0.000 | 1 |
| 1 point/m² | Scaled | 0.099 | 46 | 16.1 | 0 | 0.000 | 1 |
| 1 point/m² | Double | 0.401 | 49 | 61.7 | 7 | 0.493 | 17 |

## Readings

- **Scaling the radius with the point spacing does not restore SegmentAnyTree
  on sparse clouds.** F1 changes by −0.019 to +0.027 and corrected F1 by
  −0.009 to +0.021, every interval including zero, and the core detections
  stay at a tenth to under half of ForestFormer3D's. No arm meets the go
  criterion, so no full run follows.
- **The scaled radius changes little; the doubled one groups more tree points
  but merges trees.** With 1.5 times the spacing the share of tree points in an
  instance rises from 0.23 to 0.27 at 2 points/m² and from 0.05 to 0.10 at 1
  point/m², and almost no instance holds two mapped stems. With 3 times the
  spacing it rises to 0.65 and 0.40, but the instance count falls from 126 to 90
  at 2 points/m² and rises only from 31 to 49 at 1 point/m², while the instances
  grow to 83 and 62 points each; 16 of 90 and 7 of 49 hold two or more mapped
  stems, the largest 21 and 17, and they carry about half of the grouped points,
  against 0.14 in the zero-shot clouds at native density, whose instances hold
  at most 6. A radius small enough to keep trees apart does not join one tree's
  points, and one large enough to join them merges trees. This is consistent
  with offsets that, at these densities, no longer gather a tree's points near
  its centre; the check does not test the offsets directly.
- **For the paper.** The collapse remains a failure of the grouping, not of
  the semantic labels, but the fixed 0.3 m radius does not explain it alone.
  Section 6.2 and the note to Table S18a say so, and S18 gives these results.

## Caveats

- Post hoc and small: 10 plots of the development region at two density
  levels, chosen by rule before any result. The intervals are wide: the
  doubled radius's at 1 point/m² reaches +0.117 F1, so 10 plots cannot exclude
  a gain of that size, though the estimate is +0.027 and half of the points
  that arm groups sit in instances holding two or more mapped stems.
- The stem test counts only the mapped reference stems (live, DBH ≥ 10 cm), so
  it misses merges with unmapped trees; it can also flag a single crown whose
  hull covers a neighbouring or understory stem, which is why the zero-shot
  clouds flag 0.14 of their grouped points at native density. The doubled
  radius's flagged instances, holding up to 21 mapped stems, are merges.
- One setting changed: the region-growing radius. The 10-point minimum cluster
  size, the embedding clustering, the score network and the non-maximum
  suppression keep their upstream values.
- Not in the reproduction archive, like the ForestMamba runs; the instance
  clouds, logs and tables are regenerated with the commands above.

## Outputs

Under `OUT`: `manifest.csv` (cells, densities, radii), `jobs.tsv`, `in/` (the
clips as PLY), `out/` (one instance cloud per job), `logs/` (one per job, with
the shim's radius line), `progress.log` (one line and the wall time per job),
`scores.csv` (one row per job and per comparison cell, with null and grouping
counts), `control.csv`, `summary.csv`, `contrasts.csv` and `grouping.csv`.
Each job took 256 to 453 s, about six minutes on average with four containers
running at once on an RTX 5090.
