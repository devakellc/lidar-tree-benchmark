# Master tables, reference populations and bootstrap intervals

Checked on 2 October 2026. This study builds the tables the paper reports
from: one reference population per site, one long-form table of every arm,
site and density rung on equal support, and paired plot-level bootstrap
intervals on every pooled number and on every arm-versus-arm difference.

**Status: the infrastructure is complete; six of twelve arms are in.** The
six classical arms re-run on the sealed frozen clips (CHM-VWF, `multichm`,
`lmfauto`, `ptrees`, AMS3D and Li 2012) are scored here. ForestFormer3D and
TreeisoNet are being re-run with the corrected adapters; SegmentAnyTree,
DeepForest, Detectree2 and SAM2Point have not yet been re-run on the frozen
clips. They appear as pending rows, never filled from older outputs, and slot
in when their outputs on the frozen root are complete.

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
| CHM-VWF | 1 | 0.296 [0.272, 0.326] | 0.506 [0.476, 0.542] | 0.374 [0.353, 0.396] |
| `multichm` | 1 | 0.506 [0.476, 0.536] | 0.380 [0.353, 0.410] | 0.434 [0.415, 0.453] |
| `lmfauto` | 1 | 0.768 [0.717, 0.814] | 0.163 [0.144, 0.190] | 0.269 [0.243, 0.302] |
| `ptrees` | 1 | 0.191 [0.170, 0.212] | 0.468 [0.433, 0.502] | 0.271 [0.250, 0.293] |
| AMS3D | 1 | 0.399 [0.364, 0.431] | 0.483 [0.447, 0.520] | 0.437 [0.409, 0.462] |

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
| CHM-VWF | 1 | 0.327 [0.296, 0.362] | 0.867 [0.831, 0.905] | 0.475 [0.440, 0.511] |
| `multichm` | 1 | 0.524 [0.488, 0.561] | 0.615 [0.566, 0.670] | 0.566 [0.539, 0.590] |
| `lmfauto` | 1 | 0.782 [0.730, 0.837] | 0.261 [0.233, 0.299] | 0.392 [0.359, 0.430] |
| `ptrees` | 1 | 0.215 [0.190, 0.244] | 0.828 [0.768, 0.885] | 0.342 [0.308, 0.378] |
| AMS3D | 1 | 0.428 [0.385, 0.474] | 0.820 [0.778, 0.861] | 0.562 [0.522, 0.601] |

Paired F1 differences against CHM-VWF, nominal box, five sites:

| Arm − CHM-VWF | Native | 1 point/m² |
| --- | --- | --- |
| `multichm` | +0.006 [−0.018, +0.028] | +0.060 [+0.036, +0.082] |
| Li 2012 | +0.006 [−0.009, +0.019] | — |
| `lmfauto` | −0.064 [−0.095, −0.030] | −0.105 [−0.148, −0.063] |
| `ptrees` | −0.120 [−0.154, −0.085] | −0.103 [−0.122, −0.083] |
| AMS3D | −0.210 [−0.240, −0.180] | +0.063 [+0.033, +0.093] |

- At native density CHM-VWF, `multichm` and Li 2012 are indistinguishable on
  F1; at 1 point/m² `multichm` and AMS3D are ahead of CHM-VWF, both with
  intervals excluding zero.
- On the same 57 plots, restricting precision to censused subplots raises it
  by 0.29 to 0.34 for CHM-VWF across rungs and by 0.08 to 0.32 for the other
  arms, while recall moves by at most 0.024. The native-density F1 order (Li
  2012, CHM-VWF, `multichm`, `lmfauto`, `ptrees`, AMS3D) is the same in both
  scorings.
- Per-site intervals are wide at SJER (6 plots): CHM-VWF native F1 0.307
  [0.169, 0.471]. The full per-site and per-rung tables, every contrast and
  the census exact-2021 check are in the generated CSV files.

## Pending arms

| Arm | Status |
| --- | --- |
| ForestFormer3D | re-run in progress (329 of 530 cells at the time of writing) |
| TreeisoNet | re-run queued after ForestFormer3D |
| SegmentAnyTree | not yet re-run on the frozen clips |
| DeepForest, Detectree2 | not yet re-run on the frozen clips |
| SAM2Point | not yet re-run on the frozen clips |

When they land, the assembler includes them without code changes. The
reports still to update then: the density-ladder study (CHM-VWF and
`multichm` ladder on the adopted population with intervals, replacing the
historical D17 tables as the paper numbers), the model benchmark (every arm on
equal support, intervals and paired contrasts), and the
calibration/validation study (held-out F1 on the adopted population, with
intervals over validation plots). The `all_mapped` and `relaxed` sensitivity
rows need the arms re-run with `POP=` in their own job directories.

## Reproduce

```sh
export CLAUDE_JOB_DIR=/path/to/paper_runs   # arm outputs on the sealed root
Rscript scripts/master_tables.R              # writes $CLAUDE_JOB_DIR/master_tables
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
