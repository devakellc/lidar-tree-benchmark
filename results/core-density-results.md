# Density of the scored plot cores

Checked on 17 November 2026. This measurement was added after an internal review
of the paper. Until then the paper's density labels, the [QL2
level](../docs/ql2-rung-declaration.md) and the bands of the [density-routed
pipeline](density-routing-results.md) all used first-return density measured
over the whole evaluation clip: the nominal plot core plus a 25 m buffer, the
area the clip manifest divides by. Detections are scored inside the nominal core
only. This study measures density on the scored area.

**Finding: the scored cores are about 10% sparser than those labels at every
thinned level.** Over the 106 plots of the `adopted` population, the five-site
median first-return density inside the cores is 4.37, 2.20, 1.77, 1.11 and 0.56
pulses/m² at the levels labelled 4.7, 2.5, 2.0, 1.3 and 0.6; native density
agrees (9.80 in the cores, 9.77 over the clip). The thinning meets its
all-return targets inside the cores; the excess sits in the clip's outer cells,
which are never scored.

**Consequences.** The QL2 level, declared at a whole-clip median of 2.0
pulses/m², holds 1.77 in the cores, and 79 of its 106 cores lie below the QL2
floor of 2 pulses/m² (54 by whole-clip density). The paper now names the thinned
levels by their core medians. The density-routed pipeline is re-banded on core
density, and its band-B pick with a GPU changes from ForestFormer3D to
SegmentAnyTree. No detector is re-run and no score changes: the detectors'
density gates read the clip manifest, as in the runs.

## What was measured

[core_density.R](../scripts/core_density.R) reads every usable cell of the
`adopted` population in the two sealed roots: native density and the
all-return targets 8, 4, 2 and 1 points/m² in
[frozen_2021](frozen-clips-results.md), and the QL2 level (target 3.2) in its
own root, 636 cells in all. Each cell is read through the root's verified
reader, so its geometry and the SHA-256 of every file are checked against the
clip manifest. On the height-normalized clip it applies the frozen-clip
provider's own height filter (Z from −1 m to below 80 m) and counts first
returns (return number 1) and all returns in three areas:

- **Core**: the nominal plot core, a square of half-side 20 m on tower plots
  and 10 m on distributed plots, bounds included, as detections are scored.
- **Whole clip**: the core plus the 25 m buffer, over the nominal clip area,
  as in the clip manifest.
- **Outer ring**: the clip's outer 5 m, the width of the thinning grid's
  cells.

**Check.** The recomputed whole clip is the manifest's in every cell: the
all-return count equals the `n_norm` that each cell's `manifest.json`
records, and both recorded densities times the clip area round to the
recomputed counts. Both manifests store densities to 15 significant digits,
so the doubles cannot be compared exactly; the recomputed densities agree to
a relative 4.7 × 10⁻¹⁵ (largest absolute difference 5.0 × 10⁻¹⁴ pulses/m²),
and the script stops at a relative 10⁻¹³, far below one point over a clip
(1 / 8,100 m² for a tower plot). The 156 cells of the sparse-flight
comparison below pass the same check.

## Mechanism

The provider thins with lidR's `decimate_points(las, homogenize(density, res
= 5))`, which keeps at most `density × 25` points in each cell of a 5 m grid,
and all of a cell's points when it holds fewer. That grid is not aligned with
the clip, so the cells cut by the clip boundary are smaller than 25 m² but
may keep as many points as a full cell, or all their points at native
density. The clip's outer ring therefore stays denser than the target, and
every whole-clip density is too high for the interior. The data show it
directly: the five-site median all-return density is 7.99, 4.00, 3.20, 2.00
and 1.00 points/m² in the cores at the targets 8, 4, 3.2, 2 and 1, against
9.68, 5.50, 4.55, 2.98 and 1.54 in the outer 5 m ring.

At native density nothing is thinned, and the core and the clip agree at the
median (ratio 0.996). Per plot, flight-line overlap can still make a 20 m or
40 m core denser or sparser than its clip: the native ratio ranges from 0.61
to 1.49.

## Levels: core against whole clip

Five-site medians of first-return density in pulses/m², with quartiles, over
the 106 `adopted` plots; all-return density in points/m². The last four
columns count cores and whole clips below the QL2 floor (2 pulses/m²) and
the QL1 floor (8 pulses/m²).

| Level (all-return target) | Cells | Core pulses/m², median [IQR] | Whole clip, median [IQR] | Core/clip, median | Core points/m² | Clip points/m² | Outer-ring points/m² | Cores < 2 | Clips < 2 | Cores < 8 | Clips < 8 |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| native | 106 | 9.80 [8.17, 12.01] | 9.77 [8.52, 11.59] | 0.996 | 18.69 | 17.93 | 17.24 | 0 | 0 | 25 | 18 |
| 8 | 106 | 4.37 [4.08, 4.83] | 4.72 [4.36, 5.40] | 0.939 | 7.99 | 8.39 | 9.68 | 0 | 0 | 106 | 106 |
| 4 | 106 | 2.20 [2.05, 2.47] | 2.49 [2.27, 2.79] | 0.902 | 4.00 | 4.36 | 5.50 | 20 | 1 | 106 | 106 |
| 3.2 (QL2 level) | 106 | 1.77 [1.64, 2.00] | 1.99 [1.84, 2.26] | 0.895 | 3.20 | 3.51 | 4.55 | 79 | 54 | 106 | 106 |
| 2 | 106 | 1.11 [1.03, 1.23] | 1.27 [1.16, 1.41] | 0.890 | 2.00 | 2.22 | 2.98 | 106 | 106 | 106 | 106 |
| 1 | 106 | 0.56 [0.52, 0.64] | 0.64 [0.58, 0.72] | 0.877 | 1.00 | 1.11 | 1.54 | 106 | 106 | 106 | 106 |

The gap widens as the target falls, from 6% at 8 points/m² to 12% at 1: a
boundary cell can keep at most its native density, which is a smaller
multiple of a high target than of a low one. Tower cores lose a little less
than distributed cores (at the QL2 level a median core/clip ratio of 0.91
against 0.89), because the outer ring is a smaller share of a tower clip
(21% of its area against 27%).

## Per site

Median first-return density, core / whole clip, in pulses/m²:

| Level | California | Washington | SJER | SOAP | TEAK | WREF | ABBY |
| --- | --- | --- | --- | --- | --- | --- | --- |
| native | 11.23 / 11.68 | 9.45 / 9.29 | 10.54 / 9.62 | 12.16 / 12.17 | 10.19 / 11.68 | 8.66 / 8.79 | 10.00 / 10.21 |
| 8 | 5.03 / 5.56 | 4.19 / 4.44 | 4.84 / 5.61 | 5.33 / 5.63 | 4.81 / 5.48 | 4.16 / 4.39 | 4.25 / 4.60 |
| 4 | 2.62 / 2.91 | 2.08 / 2.31 | 2.69 / 3.16 | 2.70 / 2.91 | 2.42 / 2.90 | 2.08 / 2.29 | 2.15 / 2.38 |
| 3.2 (QL2 level) | 2.10 / 2.35 | 1.68 / 1.86 | 2.14 / 2.54 | 2.13 / 2.36 | 1.96 / 2.32 | 1.66 / 1.85 | 1.72 / 1.90 |
| 2 | 1.25 / 1.49 | 1.04 / 1.18 | 1.33 / 1.61 | 1.35 / 1.50 | 1.20 / 1.46 | 1.04 / 1.17 | 1.05 / 1.19 |
| 1 | 0.65 / 0.76 | 0.53 / 0.59 | 0.66 / 0.82 | 0.66 / 0.77 | 0.61 / 0.74 | 0.53 / 0.59 | 0.54 / 0.61 |

At the QL2 level, 20 of the 43 California cores lie below 2 pulses/m² (3 by
whole-clip density) and 59 of the 63 Washington cores (51). At the level
thinned to 4 points/m², 2 California and 18 Washington cores lie below 2
(none and 1 by whole clip). At native density, 8 California and 17
Washington cores lie below 8 pulses/m² (6 and 12 by whole clip).

## Native sparse flights

The [native sparse-epoch comparison](native-sparse-epoch-results.md) scores
earlier, sparser NEON flights over 39 California plots (4 SJER, 18 SOAP, 17
TEAK) against the 2021 clouds thinned to the all-return targets 8 and 4,
which were described as bracketing the sparse flights' density. The same
counts on those clips (the compared plots are those of the shared-stem
reference; every compared cell shares one core), in pulses/m²:

| Scope | Plots | Sparse flight, core / clip | 2021 native, core / clip | 2021 target 8, core / clip | 2021 target 4, core / clip | Sparse denser than target 8, core / clip | Sparse sparser than target 4, core / clip | Bracketed, core / clip |
| --- | ---: | --- | --- | --- | --- | --- | --- | --- |
| All compared | 39 | 4.64 / 4.57 | 11.23 / 11.68 | 4.85 / 5.53 | 2.48 / 2.89 | 13 / 10 | 1 / 2 | 25 / 27 |
| SJER | 4 | 3.12 / 4.18 | 8.53 / 8.35 | 4.57 / 5.09 | 2.52 / 2.86 | 1 / 1 | 1 / 0 | 2 / 3 |
| SOAP | 18 | 5.03 / 5.03 | 12.16 / 12.17 | 5.33 / 5.63 | 2.70 / 2.91 | 8 / 7 | 0 / 0 | 10 / 11 |
| TEAK | 17 | 4.06 / 3.88 | 10.19 / 11.68 | 4.80 / 5.40 | 2.41 / 2.76 | 4 / 2 | 0 / 2 | 13 / 13 |

By whole-clip density, 10 of the 39 sparse clouds are denser than their
target-8 clip and 2 sparser than their target-4 clip; in the cores the counts
are 13 and 1. The sparse flights are not thinned, so their core and clip
densities agree at the median (4.64 against 4.57 pulses/m²), while the 2021
target-8 clips are sparser in the cores (median 4.85 against 5.53). In the
cores the
sparse flights' median sits just below the target-8 level, not midway
between the two targets: the comparison with the target-8 clips is close to
density-matched. SJER's four sparse cores (3.12 against 4.18 over the clip)
show the flight-line effect of the previous section at small sample size.

## Consequences

Statements that depend on the density definition:

- **Level labels.** Before this measurement the paper labelled the thinned
  levels by their whole-clip medians, 4.7, 2.5, 2.0, 1.3 and 0.6 pulses/m², as
  the earlier reports still do; on the scored area they are 4.4, 2.2, 1.8, 1.1
  and 0.6, the labels the paper and the density-routing report now use. Native
  density is 9.8 either way. The all-return targets that name the levels are met
  in the cores.
- **The QL2 level.** It was [declared](../docs/ql2-rung-declaration.md) at a
  whole-clip median of 1.995 pulses/m². In the plot cores the median is 1.77,
  and 79 of the 106 cores lie below the QL2 floor: the level sits below the
  floor in most plots, and in all but 4 Washington plots, rather than at it. The
  level thinned to 4 points/m² (2.2 in the cores) has 20 cores below the floor.
- **QL1 at native density.** 25 of the 106 native cores lie below 8 pulses/m²
  (18 clips).
- **Density routing.** The [density-routed pipeline](density-routing-results.md)
  now bands each cell by its core density: per band, California holds 35, 115
  and 108 cells (whole clip: 37, 132 and 89) and Washington 46, 129 and 203 (51,
  149 and 178). The band-B GPU pick changes from ForestFormer3D to
  SegmentAnyTree, at a pooled California F1 of 0.433 against ForestFormer3D's
  0.431; neither choice separates from the other.
- **Sparse-flight bracketing.** As above: in the cores the sparse flights sit
  near the target-8 level, and 13 of 39 lie above it.

## What does not change

- **Detections and scores.** No detector is re-run, and every recall,
  precision and F1 in the reports is unchanged; so are the master tables'
  per-level scores, which the routing analysis reproduces exactly in both
  density definitions.
- **The detectors' density gates.** CHM-VWF's canopy-model resolution
  (0.25 m at 8 pulses/m² or more, else 0.5 m) and its smoothing rule below
  8 pulses/m², and the canopy-model resolution of `multichm` and the other
  CHM-based arms, are gated on the whole-clip density of the clip manifest,
  which the runs read. That is how the paper's detections were made. Had
  the gates read core density, 9 native cells would have taken
  the other branch (8 with a clip at or above 8 pulses/m² but a core below,
  1 the reverse); no thinned cell reaches 8 pulses/m² by either measure, so
  every thinned cell takes the same branch either way.

## Regenerate

```sh
CLAUDE_JOB_DIR=$(pwd)/work/paper_runs Rscript scripts/core_density.R CORES=8
# -> work/paper_runs/core_density/: core_density.csv,
#    core_density_summary.csv, core_density_sparse_epoch.csv,
#    core_density_sparse_epoch_summary.csv, core_density_contract.json
```

The script reads the canonical root (`FROZEN_ROOT=`, default
`<job dir>/neon/frozen_2021`), the QL2 level's root (`RUNG_ROOTS=`, default
`work/neon/frozen_2021_ql2`) and, for the sparse-flight table, the
sparse-epoch roots and the 2021 comparison job directory (`EPOCHS=` and
`C21=`, as `compare_sparse_epoch.R` takes them; `EPOCHS=none` skips it). It
writes nothing to any root and runs in about 10 seconds on 8 cores. The
counting helpers are in `scripts/core_density_lib.R`, tested by
`tests/testthat/test-core-density.R`. The routing analysis reads
`core_density.csv` (`DENSITY=core`, the default of
`paper_density_routing.R`).

## Outputs

Under `work/paper_runs/core_density/`:

- `core_density.csv`: one row per cell with its plot type and region, the
  manifest's and the recomputed whole-clip densities, the core and
  outer-ring densities (first returns and all returns), the counts behind
  them, and the root and file hashes.
- `core_density_summary.csv`: per level and scope (five sites, each region,
  each site), the median, quartiles and range of core and whole-clip
  first-return density, the median all-return density of the core, the clip
  and the outer ring, the cores and clips below 2 and below 8 pulses/m², and
  the median core/clip ratio.
- `core_density_sparse_epoch.csv` and `core_density_sparse_epoch_summary.csv`:
  the same per plot for the sparse flights and the 2021 native, target-8 and
  target-4 clips they are compared with, and the medians and bracketing
  counts above.
- `core_density_contract.json`: the definitions, the check and its
  tolerance, the hashes of the inputs and the checksums of the code.

## Caveats

- **The nominal core.** The core is the nominal plot box, the area every
  nominal-box score uses. The censused-subplot scores use a smaller area
  inside it, whose density is not measured separately; it lies inside the
  core, away from the clip edge.
- **Small areas.** A 20 m core holds about 400 m², so flight-line overlap
  moves its density as well as the thinning does; the per-plot core/clip
  ratio at native density ranges from 0.61 to 1.49.
- **Thinning removes returns.** The levels thin all returns to a target,
  not pulses; first-return density is measured, not targeted, and differs
  by site.
