# FGI-EMIT thinned to the NEON densities

Run on 5 October 2026 under the
[declared thinning protocol](../docs/fgiemit-thinning-protocol.md), on the ten
FGI-EMIT development plots (841 reference trees). The evaluation reserve and
the historical test plots were not read. These are development diagnostics
under the [frozen policy](../docs/fgiemit-frozen-policy.md).

On the development plots at native density ForestFormer3D and SegmentAnyTree
lead CHM-VWF by 0.30 and 0.22 apex F1. On NEON the leads are about 0.05
([master tables](master-tables-results.md)). The two datasets differ in
density, forest type and reference completeness. This study thins FGI-EMIT
to the NEON ladder and scores against its true labels, so that density
changes alone.

**Answer: for ForestFormer3D, density explains the contrast at NEON's native
density and not below it; for SegmentAnyTree it does not even there.** At
11.3 pulses/m², the level paired with native NEON, ForestFormer3D's lead over
CHM-VWF falls from 0.30 to 0.08 [0.03, 0.13], against 0.05 [0.03, 0.07] on
NEON, with overlapping intervals; SegmentAnyTree's lead falls only to 0.16
[0.09, 0.21], against 0.04 on NEON. From 5.4 pulses/m² down
ForestFormer3D's lead returns to 0.17 to 0.21 apex F1, two to four
times its lead on NEON at the corresponding rungs; part of that gap is
CHM-VWF's own loss of 0.14 where the NEON rule switches to the 0.5 m canopy
model. Under the protocol's reading, the paper reports FGI-EMIT and NEON as a
contrast between datasets, not as a controlled density effect.
SegmentAnyTree's density pattern does replicate against true labels: it
holds down to about 3 pulses/m² and collapses below 2, as on NEON.

## Densities

Seeded `homogenize` at 5 m, the NEON provider's decimation, with the target
divided by each plot's share of first returns. Measured first-return density
over the ten plots, and the reference trees that keep at least one point
(the mask reference; apex scoring always uses all 841 dense apexes):

| Target (NEON rung) | Pulses/m², median [range] | Trees with points |
| --- | --- | ---: |
| native | 1,309 [1,005, 1,684] | 841 |
| 9.8 (native) | 11.3 [11.1, 12.0] | 822 |
| 4.7 (8) | 5.4 [5.3, 5.7] | 809 |
| 2.5 (4) | 2.9 [2.8, 3.1] | 782 |
| 1.3 (2) | 1.5 [1.5, 1.6] | 722 |
| 0.6 (1) | 0.7 [0.7, 0.7] | 654 |

The measured densities are about 15% above the targets: `homogenize` fills
every 5 m cell to the target count, including the cells only partly inside a
plot's hull. They still sit beside the NEON rungs they stand for.

## Apex F1

Pooled over the ten plots by summed counts. CHM-VWF follows the NEON paper
rule (0.25 m canopy model at 8 or more pulses/m², else 0.5 m with
smoothing). The learned arms are scored under the NEON reduction (every
instance whose top is at least 2 m above ground, the rule of the NEON runs)
and under the development matrix's fixed filter (at least 40 points and
1.5 m vertical extent):

| Pulses/m² | CHM-VWF | ForestFormer3D | SegmentAnyTree | ForestFormer3D, fixed filter | SegmentAnyTree, fixed filter |
| --- | --- | --- | --- | --- | --- |
| native | 0.513 | 0.811 | 0.729 | 0.809 | 0.732 |
| 11.3 | 0.507 | 0.590 | 0.666 | 0.588 | 0.641 |
| 5.4 | 0.366 | 0.569 | 0.605 | 0.569 | 0.567 |
| 2.9 | 0.354 | 0.565 | 0.543 | 0.532 | 0.435 |
| 1.5 | 0.361 | 0.544 | 0.393 | 0.318 | 0.110 |
| 0.7 | 0.344 | 0.515 | 0.116 | 0.005 | 0.002 |

Lead over CHM-VWF, NEON reduction, with paired whole-plot bootstrap
intervals (1,000 resamples, seed 20260923), next to the five-site NEON lead at
the corresponding rung (nominal box):

| Pulses/m² | ForestFormer3D | NEON | SegmentAnyTree | NEON |
| --- | --- | --- | --- | --- |
| native | +0.298 [+0.181, +0.385] | +0.048 | +0.216 [+0.110, +0.288] | +0.044 |
| 11.3 | +0.083 [+0.034, +0.126] | +0.048 | +0.159 [+0.092, +0.206] | +0.044 |
| 5.4 | +0.203 [+0.174, +0.229] | +0.092 | +0.239 [+0.196, +0.276] | +0.091 |
| 2.9 | +0.210 [+0.175, +0.243] | +0.062 | +0.189 [+0.156, +0.221] | +0.073 |
| 1.5 | +0.184 [+0.143, +0.218] | +0.055 | +0.032 [−0.036, +0.096] | −0.007 |
| 0.7 | +0.171 [+0.127, +0.214] | +0.047 | −0.228 [−0.308, −0.162] | −0.246 |

The NEON column pairs 11.3 pulses/m² with native NEON (9.8), 5.4 with rung 8
(4.7), 2.9 with rung 4 (2.5), 1.5 with rung 2 (1.3) and 0.7 with rung 1 (0.6).

## Readings

- **ForestFormer3D's lead falls to NEON's level at 11 pulses/m² and stays
  large below; SegmentAnyTree's does not fall to it.** ForestFormer3D's lead
  over CHM-VWF falls from 0.30 at native density to 0.08 [0.03, 0.13] at
  11.3 pulses/m², against 0.05 on NEON. From 5.4 pulses/m² down it sits at
  0.17–0.21, and its change from native there spans zero below
  11.3 pulses/m² (−0.088 [−0.198, +0.032] at 2.9), while on NEON the same arm
  leads by 0.05 to 0.09: ratios of 2.2 at 5.4 pulses/m² and 3.3 to 3.6
  below. The protocol's threshold was a fall to about 0.05; ForestFormer3D's
  lead meets it at 11.3 pulses/m² and keeps two to four times that below.
  SegmentAnyTree's lead at 11.3 pulses/m² is 0.16 [0.09, 0.21] against 0.04
  on NEON, 3.6 times NEON's lead with an interval that excludes it. Below
  11 pulses/m² the FGI-EMIT and NEON leads differ through forest structure,
  reference completeness and CHM-VWF's own response to the rule switch, not
  through density alone.
- **SegmentAnyTree's collapse replicates.** Its lead holds to 2.9 pulses/m²
  (change from native within ±0.06, intervals reaching zero), vanishes at 1.5
  (+0.032 [−0.036, +0.096]) and reverses at 0.7 (−0.228). On NEON it crosses
  CHM-VWF between 2.0 and 1.3 pulses/m²
  ([master tables](master-tables-results.md#the-ql2-rung)). Against true
  labels, the collapse belongs to the model at these densities, not to
  NEON's references.
- **The biggest loss is from dense ALS to 11 pulses/m².** ForestFormer3D
  loses 0.22 apex F1 and 0.26 mask F1 between 1,300 and 11.3 pulses/m², and
  only 0.08 more down to 0.7. CHM-VWF barely changes over that first step
  (0.513 to 0.507) and loses 0.14 where the NEON rule switches to the 0.5 m
  smoothed canopy model, so the leads are smallest at 11.3 pulses/m².
- **The dense-cloud filter fails on sparse clouds.** The fixed filter's
  40-point minimum removes most crowns below 3 pulses/m². At 0.7 pulses/m² it
  keeps 4 ForestFormer3D and 1 SegmentAnyTree detections over the ten plots,
  where the NEON reduction keeps 378 and 56. Of the 100 learned cells, 18
  returned no tree after the fixed filter, 17 of them at 0.7 pulses/m². They
  are scored as results.

## Masks

Mask F1 at IoU 0.5 against the true labels of the retained points:

| Pulses/m² | ForestFormer3D | SegmentAnyTree | ForestFormer3D, fixed filter | SegmentAnyTree, fixed filter |
| --- | --- | --- | --- | --- |
| native | 0.713 | 0.607 | 0.713 | 0.612 |
| 11.3 | 0.457 | 0.507 | 0.456 | 0.502 |
| 5.4 | 0.412 | 0.466 | 0.411 | 0.441 |
| 2.9 | 0.379 | 0.393 | 0.367 | 0.340 |
| 1.5 | 0.317 | 0.250 | 0.196 | 0.101 |
| 0.7 | 0.302 | 0.093 | 0.006 | 0.003 |

Masks lose more than apexes: ForestFormer3D keeps 0.30 mask F1 at
0.7 pulses/m² against 0.51 apex F1. CHM-VWF has no masks.

## Deviations and checks

- **Scorer check.** The first learned cell (plot 1001, 11.3 pulses/m²,
  SegmentAnyTree) stopped the run at a check written for native clouds: the
  mask had to count every reference tree, and two of the plot's 133 trees
  kept no point. `score_instance_cell` already counts trees with at least one
  point. The check now requires every labelled tree to be a reference apex
  and the mask to count each of them. The cell's saved predictions were
  scored again without running the model a second time. No other cell
  failed.
- **Smoke test.** Before the full run, the runner was tried on plot 1005's
  CHM-VWF cells and one of its scores was read. Those outputs were deleted,
  every cell was produced once in the full run, and no choice depended on
  the smoke test.
- The native cells are the development matrix's (CHM-VWF at 0.25 m, the NEON
  rule at that density), with the NEON reduction applied to their saved
  predictions.

## Reproduce

FGI-EMIT is licensed CC BY-NC-SA 4.0 and is not redistributed. With the
development inputs under `<root>` and outputs outside it:

```sh
Rscript scripts/fgiemit_thin_select.R ROOT=<root> OUT=<out>/select
python scripts/fgiemit_thin_write.py <root> <out>/select
python scripts/run_fgiemit_thinning.py <root> <out>/select <out> <runtime> chm_vwf
python scripts/run_fgiemit_thinning.py <root> <out>/select <out> <runtime> \
    segmentanytree,forestformer3d
python scripts/run_fgiemit_thinning.py <root> <out>/select <out> <runtime> \
    segmentanytree,forestformer3d MODE=native
Rscript scripts/fgiemit_thinning_summary.R ROOT=<root> THIN=<out> \
    SELECT=<out>/select OUT=<summary>
```

The summary writes `thinning_cells.csv` (one row per plot, density, arm and
rule), `thinning_pooled.csv`, `thinning_leads.csv`, `thinning_change.csv` and
`thinning_lead_change.csv`.
