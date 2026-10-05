# QL2 rung declaration

Declared on 5 October 2026, before any arm ran on the rung. Only densities
were measured to choose it; no detector was run or scored.

## Why

The USGS 3DEP QL2 specification sets an aggregate nominal pulse density of at
least 2 pulses/m². On the frozen five-site population the existing rungs put
that floor in a gap: rung 4 has a median of 2.5 first-return pulses/m² and
rung 2 a median of 1.3. A rung at the floor shows on which side of it each
arm's accuracy changes.

## Rung

The rung is an all-return decimation target of **3.2 points/m²**, decimated
exactly as the existing rungs: the frozen provider's seeded
`homogenize(density = 3.2, res = 5)` on each plot's canonical clip. The target
was chosen so that the median first-return density over the 106 plots of the
adopted population is 2.0 pulses/m². `scripts/calibrate_rung_target.R`
decimated every sealed native clip at three candidate targets with the
provider's seeds and measured them:

| Target (points/m²) | Cells | Median points/m² | Median pulses/m² | Pulses/m², range |
| ---: | ---: | ---: | ---: | --- |
| 3.0 | 106 | 3.31 | 1.88 | 1.50–2.67 |
| **3.2** | 106 | 3.51 | **1.99** | 1.59–2.84 |
| 3.4 | 106 | 3.72 | 2.12 | 1.71–3.03 |

An all-return target keeps the rung comparable with the rest of the ladder.
Per plot, the first-return density ranges from 1.6 to 2.8 pulses/m², so about
half the plots sit below the QL2 floor and half above it; the reports give the
rung's measured densities beside the other rungs.

## Freeze and runs

- The rung is frozen with `freeze_clips.R RUNGS=3.2` into its own root,
  `work/neon/frozen_2021_ql2`, from the same tiles, references, populations,
  seeds and provider as `frozen_2021`. The canonical root is not written
  again. The new root's `population.csv` and native clips must be
  byte-identical to the canonical root's.
- The eight full-ladder arms (CHM-VWF, `multichm`, `lmfauto`, `ptrees`, AMS3D,
  ForestFormer3D, TreeisoNet, SegmentAnyTree) run on the rung in their own job
  directory, `work/paper_runs_ql2`, with the configurations of the paper runs.
  The classical arms also score the root's native cells there, which repeat
  the paper runs' native cells.
- The master tables take the rung through `RUNG_JOBS=<job dir>:<root>`, with
  the root's own provenance stamps and equal-support guard. The censused
  precision scorer runs on the rung in the same job directory.

## Results

The freeze verified, and every arm completed all 106 cells. The results are
in the [master tables](../results/master-tables-results.md#the-ql2-rung), the
[density-ladder study](../results/density-ladder-sweep-results.md) and the
[model comparison](../results/model-benchmark-results.md).
