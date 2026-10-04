# Master tables, reference populations and bootstrap intervals

Checked on 2 October 2026; ForestFormer3D and TreeisoNet added on
3 October, SegmentAnyTree, DeepForest, Detectree2 and SAM2Point on 4 October.
This study
builds the tables the paper reports from: one reference population per site,
one long-form table of every arm, site and density rung on equal support, and
paired plot-level bootstrap intervals on every pooled number and on every
arm-versus-arm difference.

**Status: all twelve arms are in.** The six classical arms (CHM-VWF,
`multichm`, `lmfauto`, `ptrees`, AMS3D and Li 2012), the three learned point
arms (ForestFormer3D, TreeisoNet and SegmentAnyTree), the two RGB arms
(DeepForest and Detectree2) and the CHM-VWF-seeded SAM2Point refiner are
scored on the sealed frozen clips. SAM2Point runs at native density only, with
up to 40 height-ranked CHM-VWF prompts per plot.

The RGB arms have no density ladder. They are scored once per plot, with apex
heights from the native frozen canopy model, and appear in the native rung.
Detectree2's plot crops were corrected before this run: the earlier crops
were too small for its 40 m tiling grid, so it had never scored the
distributed plots or the full tower cores.

## One reference per site

Earlier reports used different reference counts for the same three sites.
Every paper table now uses the declared `adopted` population of the
[frozen-clip study](frozen-clips-results.md): live mapped stems of at least
10 cm DBH inside the plot-type core (tower ±20 m, distributed ±10 m), in
plots holding at least six such trees. The other rows explain each historical
count and the two sensitivity populations. Cells are plots / stems.

| Reference | Status | SJER | SOAP | TEAK | WREF | ABBY | Total |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `adopted` | headline | 6 / 57 | 18 / 231 | 19 / 374 | 38 / 1,063 | 25 / 800 | 106 / 2,525 |
| `all_mapped` | sensitivity | 8 / 71 | 18 / 232 | 20 / 396 | 38 / 1,081 | 32 / 1,074 | 116 / 2,854 |
| `relaxed` | sensitivity | 21 / 89 | 27 / 251 | 36 / 419 | 39 / 1,068 | 26 / 801 | 149 / 2,628 |
| `hist_sweep` | historical | 8 / 71 | 18 / 232 | 20 / 396 | — | — | 46 / 699 |
| `hist_native_ql2` | historical | 8 / 71 | 16 / 222 | 19 / 392 | — | — | 43 / 685 |
| `hist_iou` | historical | 8 / 69 | 18 / 231 | 20 / 386 | — | — | 46 / 686 |
| `hist_temporal` | historical | 0 / 0 | 2 / 48 | 5 / 189 | — | — | 7 / 237 |
| `hist_crown` | historical | 4 / 28 | 17 / 221 | 20 / 384 | — | — | 41 / 633 |
| `adopted_crown` | crown sub-population | 3 / 22 | 17 / 220 | 19 / 366 | 38 / 1,029 | 25 / 796 | 102 / 2,433 |
| `census_nearest` | headline censused precision | 2 / 14 | 1 / 2 | 9 / 119 | 28 / 642 | 17 / 413 | 57 / 1,190 |
| `census_nearest_box` | comparison | 2 / 31 | 1 / 16 | 9 / 149 | 28 / 842 | 17 / 569 | 57 / 1,607 |
| `census_exact` | check | 0 / 0 | 0 / 0 | 2 / 34 | 4 / 147 | 10 / 314 | 16 / 495 |
| `census_exact_box` | comparison | 0 / 0 | 0 / 0 | 2 / 48 | 4 / 174 | 10 / 458 | 16 / 680 |

- `hist_sweep` (232 / 71 / 396, 699 in all) is the population of the
  [density-ladder sweep](density-ladder-sweep-results.md), the
  [model benchmark](model-benchmark-results.md), the
  [point-cloud detector study](pointcloud-detector-results.md), the matcher,
  fusion and coverage-gap studies: live mapped stems in the core, plots with
  at least six live mapped trees counted over the whole plot. It equals
  `all_mapped` at D17.
- `hist_native_ql2` (222 / 71 / 392) is the
  [native 3DEP cross-check](native-ql2-crosscheck-results.md). It counts the
  six stems inside the core instead of over the whole plot, which drops two
  SOAP plots (10 stems) and one TEAK plot (4 stems).
- `hist_iou` (686) is the [instance IoU/PQ scorer](instance-iou-pq-results.md).
  It keeps `hist_sweep` stems that captured at least one canopy point in the
  Voronoi-on-stems mask proxy; 13 stems without a point are excluded. The
  count depends on the old instance clouds and is taken from that report.
- `hist_temporal` is the [temporal-sensitivity](temporal-sensitivity-results.md)
  exact-2021 cut: `hist_sweep` stems measured in 2021, with the six-stem gate
  applied after the cut. SJER has no 2021 measurement.
- `hist_crown` is the [crown benchmark](crown-segmentation-results.md):
  live mapped stems with a NEON field crown diameter (the VST record nearest
  2021) in plots with at least six such trees. That report's 225 is the
  number of matched stems, not the reference. `adopted_crown` is the same
  rule on the declared population, which the crown arms now use.
- `census_*` rows are the [censused-subplot](census-support-results.md)
  reference: census-event records inside the eroded censused interior of
  admitted plots, and, for comparison, the adopted stems of the same plots'
  nominal cores. The headline rule is the nearest census within four years;
  the exact-2021 rule is a check.

## Method

- **Inputs.** Each arm's results come from one re-run job directory on the
  sealed frozen root. An arm is included only when it covers every usable
  site × plot × rung cell of the declared population and its outputs carry
  the root's stamp (the instance or detection directory stamp, or the resume
  sidecar). Every included row must have exactly the population's stems as
  its reference; the assembler stops otherwise.
- **Equal support.** Within each rung the canonical `equal_set_guard()` keeps
  only cells every included arm scored; with complete arms nothing is
  dropped. Census scores get the same guard on their admitted plots.
- **Pooling.** Rates come from summed counts: recall is ΣTP / Σn_ref,
  precision Σtp_core / Σn_det, and F1 is computed from the pooled rates, never
  averaged over plots.
- **Intervals.** A paired plot-level percentile bootstrap, adapted from the
  FGI-EMIT paired whole-plot bootstrap: plots are resampled with replacement
  within each site (sites are fixed strata), 1,000 draws with seed 20261002.
  One set of draws is shared by every arm, rung and metric, so arm-versus-arm
  differences are paired and get their own intervals. Intervals are the 2.5th
  and 97.5th percentiles. Census tables draw their own resamples over the
  admitted plots with the same seed.
- **What the intervals do not cover.** They express plot sampling only.
  Positional-jitter bands from the Monte-Carlo positional study, decimation
  noise measured in the [frozen-clip study](frozen-clips-results.md) and lasR
  run-to-run jitter are separate uncertainty sources and are not merged in.

## Headline tables

Nominal plot box, adopted population, five sites pooled (106 plots, 2,525
stems), with 95% intervals:

| Arm | Rung | Recall | Precision | F1 |
| --- | --- | --- | --- | --- |
| CHM-VWF | native | 0.464 [0.422, 0.512] | 0.438 [0.403, 0.473] | 0.450 [0.423, 0.478] |
| `multichm` | native | 0.541 [0.509, 0.574] | 0.394 [0.365, 0.426] | 0.456 [0.435, 0.477] |
| `lmfauto` | native | 0.555 [0.501, 0.609] | 0.296 [0.259, 0.343] | 0.386 [0.352, 0.421] |
| `ptrees` | native | 0.712 [0.662, 0.759] | 0.215 [0.187, 0.249] | 0.331 [0.296, 0.369] |
| AMS3D | native | 0.713 [0.665, 0.762] | 0.145 [0.126, 0.165] | 0.240 [0.214, 0.267] |
| Li 2012 | native | 0.561 [0.510, 0.613] | 0.384 [0.352, 0.417] | 0.456 [0.426, 0.483] |
| ForestFormer3D | native | 0.621 [0.585, 0.655] | 0.416 [0.386, 0.447] | 0.498 [0.478, 0.520] |
| TreeisoNet | native | 0.514 [0.469, 0.562] | 0.394 [0.365, 0.424] | 0.446 [0.420, 0.470] |
| SegmentAnyTree | native | 0.604 [0.554, 0.652] | 0.419 [0.386, 0.451] | 0.495 [0.466, 0.522] |
| DeepForest (RGB) | native | 0.545 [0.505, 0.585] | 0.390 [0.358, 0.423] | 0.454 [0.428, 0.478] |
| Detectree2 (RGB) | native | 0.309 [0.276, 0.345] | 0.435 [0.398, 0.474] | 0.362 [0.334, 0.390] |
| SAM2Point (seeded) | native | 0.077 [0.063, 0.093] | 0.471 [0.415, 0.530] | 0.132 [0.110, 0.157] |
| CHM-VWF | 1 | 0.296 [0.272, 0.326] | 0.506 [0.476, 0.542] | 0.374 [0.353, 0.396] |
| `multichm` | 1 | 0.506 [0.476, 0.536] | 0.380 [0.353, 0.410] | 0.434 [0.415, 0.453] |
| `lmfauto` | 1 | 0.768 [0.717, 0.814] | 0.163 [0.144, 0.190] | 0.269 [0.243, 0.302] |
| `ptrees` | 1 | 0.191 [0.170, 0.212] | 0.468 [0.433, 0.502] | 0.271 [0.250, 0.293] |
| AMS3D | 1 | 0.399 [0.364, 0.431] | 0.483 [0.447, 0.520] | 0.437 [0.409, 0.462] |
| ForestFormer3D | 1 | 0.451 [0.420, 0.484] | 0.394 [0.364, 0.428] | 0.421 [0.401, 0.441] |
| TreeisoNet | 1 | 0.454 [0.404, 0.505] | 0.426 [0.395, 0.456] | 0.440 [0.410, 0.468] |
| SegmentAnyTree | 1 | 0.074 [0.063, 0.085] | 0.494 [0.431, 0.556] | 0.128 [0.110, 0.147] |

Censused subplots, nearest census, the same arms on the 57 admitted plots
(1,190 censused references):

| Arm | Rung | Recall | Precision | F1 |
| --- | --- | --- | --- | --- |
| CHM-VWF | native | 0.499 [0.447, 0.554] | 0.779 [0.731, 0.828] | 0.608 [0.566, 0.651] |
| `multichm` | native | 0.563 [0.525, 0.605] | 0.636 [0.589, 0.683] | 0.597 [0.570, 0.626] |
| `lmfauto` | native | 0.596 [0.537, 0.661] | 0.492 [0.425, 0.586] | 0.539 [0.494, 0.594] |
| `ptrees` | native | 0.742 [0.701, 0.787] | 0.372 [0.311, 0.443] | 0.496 [0.439, 0.554] |
| AMS3D | native | 0.720 [0.657, 0.779] | 0.243 [0.208, 0.282] | 0.364 [0.322, 0.404] |
| Li 2012 | native | 0.592 [0.535, 0.651] | 0.692 [0.644, 0.747] | 0.638 [0.599, 0.676] |
| ForestFormer3D | native | 0.661 [0.621, 0.704] | 0.675 [0.627, 0.728] | 0.668 [0.640, 0.695] |
| TreeisoNet | native | 0.547 [0.493, 0.603] | 0.720 [0.673, 0.765] | 0.622 [0.581, 0.663] |
| SegmentAnyTree | native | 0.640 [0.601, 0.681] | 0.718 [0.673, 0.766] | 0.677 [0.644, 0.708] |
| CHM-VWF | 1 | 0.327 [0.296, 0.362] | 0.867 [0.831, 0.905] | 0.475 [0.440, 0.511] |
| `multichm` | 1 | 0.524 [0.488, 0.561] | 0.615 [0.566, 0.670] | 0.566 [0.539, 0.590] |
| `lmfauto` | 1 | 0.782 [0.730, 0.837] | 0.261 [0.233, 0.299] | 0.392 [0.359, 0.430] |
| `ptrees` | 1 | 0.215 [0.190, 0.244] | 0.828 [0.768, 0.885] | 0.342 [0.308, 0.378] |
| AMS3D | 1 | 0.428 [0.385, 0.474] | 0.820 [0.778, 0.861] | 0.562 [0.522, 0.601] |
| ForestFormer3D | 1 | 0.479 [0.439, 0.524] | 0.693 [0.642, 0.745] | 0.566 [0.532, 0.603] |
| TreeisoNet | 1 | 0.476 [0.411, 0.543] | 0.781 [0.742, 0.820] | 0.592 [0.535, 0.643] |
| SegmentAnyTree | 1 | 0.080 [0.065, 0.096] | 0.857 [0.765, 0.938] | 0.146 [0.120, 0.173] |

Paired F1 differences against CHM-VWF, nominal box, five sites:

| Arm − CHM-VWF | Native | 1 point/m² |
| --- | --- | --- |
| `multichm` | +0.006 [−0.018, +0.028] | +0.060 [+0.036, +0.082] |
| Li 2012 | +0.006 [−0.009, +0.019] | — |
| `lmfauto` | −0.064 [−0.095, −0.030] | −0.105 [−0.148, −0.063] |
| `ptrees` | −0.120 [−0.154, −0.085] | −0.103 [−0.122, −0.083] |
| AMS3D | −0.210 [−0.240, −0.180] | +0.063 [+0.033, +0.093] |
| ForestFormer3D | +0.048 [+0.028, +0.069] | +0.047 [+0.022, +0.069] |
| TreeisoNet | −0.004 [−0.018, +0.009] | +0.066 [+0.037, +0.093] |
| SegmentAnyTree | +0.044 [+0.021, +0.067] | −0.246 [−0.268, −0.223] |
| DeepForest (RGB) | +0.004 [−0.014, +0.022] | — |
| Detectree2 (RGB) | −0.089 [−0.120, −0.060] | — |
| SAM2Point (seeded) | −0.318 [−0.352, −0.279] | — |

- At native density CHM-VWF, `multichm`, Li 2012, TreeisoNet and DeepForest
  are indistinguishable on F1. ForestFormer3D (+0.048) and SegmentAnyTree
  (+0.044) are ahead of CHM-VWF with intervals excluding zero and
  indistinguishable from each other (SegmentAnyTree −0.004 [−0.023, +0.015]).
  Detectree2 is behind (−0.089).
- SegmentAnyTree collapses at 1 point/m² (F1 0.128, recall 0.07); the other
  learned arms keep F1 0.42–0.44 there.
- SAM2Point loses most of its seeds: its CHM-VWF prompts alone score F1 0.405
  (recall 0.354) on the same plots, while the refined masks reduce to a third
  as many trees (recall 0.077). Its voxel size is 0.02 of the clip's unit cube,
  about 1.4–1.8 m, so neighbouring crowns share voxels and prompts merge; the
  setting is untuned, as in its two-plot proof of concept.
- At 1 point/m² `multichm`, AMS3D, TreeisoNet and ForestFormer3D are all ahead
  of CHM-VWF, with intervals excluding zero. TreeisoNet and ForestFormer3D
  are then indistinguishable (+0.019 [−0.004, +0.040] for TreeisoNet).
- On the censused subplots SegmentAnyTree (+0.068 [+0.036, +0.100] over
  CHM-VWF) and ForestFormer3D (+0.059 [+0.020, +0.099]) lead at native
  density and are indistinguishable from each other (+0.009 [−0.021,
  +0.040]); ForestFormer3D's lead over Li 2012 (+0.029 [−0.007, +0.068]) is
  no longer distinguishable from zero. The RGB arms are not in the census
  scorer.
- On the same 57 plots, restricting precision to censused subplots raises it
  by 0.29 to 0.34 for CHM-VWF across rungs and by 0.08 to 0.32 for the other
  arms, while recall moves by at most 0.024. The native-density F1 order
  (SegmentAnyTree, ForestFormer3D, Li 2012, TreeisoNet, CHM-VWF, `multichm`,
  `lmfauto`, `ptrees`, AMS3D) is the same in both scorings.
- Per-site intervals are wide at SJER (6 plots): CHM-VWF native F1 0.307
  [0.169, 0.471]. The full per-site and per-rung tables, every contrast and
  the census exact-2021 check are in the generated CSV files.

## Sensitivity populations

The six classical arms were re-run on the two sensitivity populations of the
frozen root, each in its own job directory: `all_mapped` (116 plots,
2,854 stems; the historical stem gate) and `relaxed` (149 plots, 2,628 stems;
no six-stem plot gate). The learned and RGB arms have not been run on them.
Paired F1 differences against CHM-VWF, nominal box, five sites:

| Population | `multichm`, native | Li 2012, native | `multichm`, 1 point/m² | AMS3D, 1 point/m² |
| --- | --- | --- | --- | --- |
| `adopted` (headline) | +0.005 [−0.018, +0.028] | +0.006 [−0.009, +0.019] | +0.060 [+0.036, +0.082] | +0.063 [+0.033, +0.093] |
| `all_mapped` | −0.003 [−0.026, +0.019] | +0.011 [−0.005, +0.029] | +0.067 [+0.044, +0.087] | +0.048 [+0.019, +0.080] |
| `relaxed` | −0.001 [−0.022, +0.019] | −0.007 [−0.019, +0.005] | +0.031 [+0.008, +0.053] | +0.045 [+0.018, +0.072] |

The classical conclusions hold in all three populations: at native density
CHM-VWF, `multichm` and Li 2012 are indistinguishable, and at 1 point/m²
`multichm` and AMS3D are ahead of CHM-VWF. The `relaxed` population lowers
every arm's F1 (CHM-VWF native 0.408 against 0.450), because the plots it
adds hold few mapped stems, so more detections fall on unmapped trees.

A population can lack a cell at one rung (two SJER cells at 8 points/m² would
need upsampling), so each rung is resampled over its own plots. In the
headline population every rung shares the plots and the draws are unchanged.

## Next steps

Every arm is complete on the headline population. The reports still to
update from these tables: the density-ladder study (CHM-VWF and
`multichm` ladder on the adopted population with intervals, replacing the
historical D17 tables as the paper numbers), the model benchmark (every arm on
equal support, intervals and paired contrasts), and the
calibration/validation study (held-out F1 on the adopted population, with
intervals over validation plots). The learned and RGB arms are not yet run on
the `all_mapped` and `relaxed` sensitivity populations.

## Reproduce

```sh
export CLAUDE_JOB_DIR=/path/to/paper_runs   # arm outputs on the sealed root
Rscript scripts/master_tables.R              # writes $CLAUDE_JOB_DIR/master_tables
# sensitivity populations: the arms re-run with POP= in their own job
# directories (ground truth, plot centroids and vst caches linked), then
CLAUDE_JOB_DIR=/path/to/paper_runs_all_mapped Rscript scripts/master_tables.R POP=all_mapped
CLAUDE_JOB_DIR=/path/to/paper_runs_relaxed Rscript scripts/master_tables.R POP=relaxed
```

Outputs: `master_long.csv` (one row per table, scope, arm, rung and metric,
with counts, estimate, interval and status), `master_contrasts.csv`,
`reference_population.csv`, `arm_status.csv`, `master_tables.md` and
`master_contract.json` (seed, draws, root digest and code checksums).

## Caveats

- Censused precision rests mostly on WREF and ABBY (1,055 of the 1,190
  censused references); SOAP keeps one admitted plot and SJER two.
- Bootstrap intervals assume plots are exchangeable within a site. Tower and
  distributed plots are resampled together.
- The historical IoU reference is quoted, not recomputed; it changes when the
  instance clouds are regenerated on the frozen clips.
