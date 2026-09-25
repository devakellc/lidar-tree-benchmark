# FGI-EMIT Complete Development Detector Comparison

Completed on 2026-09-25: all 30 declared native-density detector cells passed
output admission and external scoring. Nine cells are reused from the admitted
[three-plot pilot](fgiemit-development-pilot-results.md), and 21 are newly run
with identical sealed execution code, inputs and settings. No earlier failed
attempt contributes predictions. Calibration remains unfitted and the three
reserve plots remain closed.

This is a conditional development comparison. Unknown upstream checkpoint
training overlap prevents an unseen-data claim. The historical six-plot
transfer study is a separate population and is not pooled here.

## Population and Fixed Methods

The ten declared development plots are 1001, 1005, 1009, 1013, 1019, 1020,
1022, 1024, 1027 and 1031. Each arm sees the same 32,445,937 retained points
and is scored against all 841 reference trees. Only the original excluded
class 5 is removed; classes 0–4 remain, including background. Edge trees,
dead trees and short references remain. Coordinates use plot-local metre
frames without an assigned EPSG code. There is no density thinning or NEON
rectangular-core substitution.

The [input validation](fgiemit-development-input-results.md) supplies the
original source rows, return fields, measured densities and geometric AGL.
First-return density spans 1,004.7–1,684.1/m² and all-return density spans
1,213.5–2,346.0/m². These densities select 0.25 m CHMs without smoothing on
every plot. The pinned lasR pre-devel runtime, TIN plus `pit_fill`, variable
window and 2 m detection threshold are unchanged.

The [comparison protocol](../docs/fgiemit-comparison-protocol.md) fixes model
checkpoints, native configurations, one-to-one matching and both scoring
tracks. SAT means SegmentAnyTree; FF3D means ForestFormer3D. Model containers
receive only annotation-free geometry. All 20 instance exports passed complete
source-row, coordinate and return-field admission, including background and
coincident points. Retained masks require at least 40 points and 1.5 m raw-Z
extent. These same masks supply both mask scoring and derived apexes.
Upstream console metrics use dummy labels; only the external annotated scorer
supplies the benchmark results below.

There are 30 successful-nonempty cells, zero successful-empty cells, zero
failed cells and zero missing or unrun cells. No plot or reference is excluded
from the primary comparison. Native stochastic settings are retained without
best-of-run selection or a bitwise-repeatability claim.

## Pooling and Uncertainty

All rates below use summed counts; coverage and segmentation quality use their
pooled sums and denominators. No per-plot rate or RMSE is averaged. Mask
pooling calls the existing `pool_pq` helper, preserving its zero-denominator
rules. Reference-category metrics with no support remain undefined.

Bracketed intervals are 95% paired whole-plot percentile bootstrap intervals,
with 1,000 resamples and seed 20260923. Each draw samples ten plots with
replacement and applies the same indices to every arm and height profile.
Rates and arm differences are recomputed after pooling each draw. The R
implementation fixes Mersenne-Twister/Inversion/Rejection and type-7 quantiles;
the selected indices and R version are saved. These are descriptive intervals
over the declared development plots, not evidence of population-wide transfer.
All reported intervals have 1,000 defined draws.

Counts are exact. Existing cell JSON stores IoU sums to four decimal places;
the pooled mask statistics inherit that accumulator precision. No detector or
matching code was changed to produce the summaries.

## Default Derived-AGL Apex Detection

Each reference and retained instance uses its maximum pointwise AGL source
row, breaking ties by lowest source-row ID and keeping XYZ together. The
unchanged matcher uses nearest-XY greedy one-to-one assignment within 4 m XY
and 5 m absolute height difference. CHM supplies detections only.

| Arm | References | Predictions | TP | FP | FN | Precision [95% CI] | Recall [95% CI] | F1 [95% CI] |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CHM-VWF | 841 | 375 | 312 | 63 | 529 | 0.8320 [0.7371, 0.9114] | 0.3710 [0.2715, 0.5125] | 0.5132 [0.4147, 0.6209] |
| SAT | 841 | 795 | 599 | 196 | 242 | 0.7535 [0.6501, 0.8504] | 0.7122 [0.5753, 0.8514] | 0.7323 [0.6639, 0.7903] |
| FF3D | 841 | 830 | 676 | 154 | 165 | 0.8145 [0.7204, 0.8882] | 0.8038 [0.7045, 0.8949] | 0.8091 [0.7635, 0.8568] |

## Instance Masks

Masks use the unchanged point-set IoU 0.5 matcher. Coverage is mean maximum
IoU over all reference instances. PQ is supplementary panoptic quality,
separate from derived-apex detection. CHM has no mask score.

| Arm | TP | FP | FN | Precision [95% CI] | Recall [95% CI] | F1 [95% CI] | Coverage [95% CI] | PQ [95% CI] |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SAT | 501 | 294 | 340 | 0.6302 [0.5465, 0.7066] | 0.5957 [0.4665, 0.7333] | 0.6125 [0.5420, 0.6736] | 0.5605 [0.4515, 0.6715] | 0.5080 [0.4412, 0.5681] |
| FF3D | 596 | 234 | 245 | 0.7181 [0.6430, 0.7808] | 0.7087 [0.6045, 0.8082] | 0.7133 [0.6581, 0.7737] | 0.6724 [0.5871, 0.7497] | 0.6145 [0.5574, 0.6739] |

### Original Crown Categories

A–D retain their original neighborhood-based definitions: isolated/dominant,
similar-height neighbors, alongside a taller neighbor, and beneath a taller
neighbor. They are not recoded as NEON crown classes. See the
[dataset description](fgi-emit-external-results.md#dataset-and-split).
Each row reports matched/reference counts and recall with its paired interval.

| Category | SAT matched/reference; recall [95% CI] | FF3D matched/reference; recall [95% CI] |
| --- | --- | --- |
| A | 271/307; 0.8827 [0.8192, 0.9410] | 284/307; 0.9251 [0.8886, 0.9649] |
| B | 111/177; 0.6271 [0.5089, 0.7637] | 128/177; 0.7232 [0.6279, 0.8101] |
| C | 105/249; 0.4217 [0.3035, 0.6085] | 151/249; 0.6064 [0.4980, 0.7486] |
| D | 14/108; 0.1296 [0.0786, 0.2568] | 33/108; 0.3056 [0.2142, 0.5472] |

Both arms still miss most category-D trees beneath taller neighbors. The
higher FF3D pooled scores do not establish complete understory coverage.

## Paired Arm Differences

Differences subtract the first named arm from the second. The same resampled
plots supply both sides of each difference; these are not differences between
independently sampled or marginal interval endpoints.

| Track | F1 difference | Estimate | 95% CI | Defined draws |
| --- | --- | --- | --- | --- |
| Maximum AGL | SAT minus CHM-VWF | 0.2191 | [0.1163, 0.2893] | 1000 |
| Maximum AGL | FF3D minus CHM-VWF | 0.2959 | [0.1762, 0.3844] | 1000 |
| Maximum AGL | FF3D minus SAT | 0.0768 | [0.0366, 0.1117] | 1000 |
| Mask IoU 0.5 | FF3D minus SAT | 0.1009 | [0.0647, 0.1295] | 1000 |

## Paired Height Diagnostics

Maximum AGL remains the default. Isolated-top AGL selects the second-highest
source row once only when the top gap is strictly greater than 0.25 m; raw-Z
uses the historical maximum-local-Z convention. Each policy is applied
symmetrically to predictions and references with the same retained masks and
reference population. Mask scores are unaffected. No better-looking profile
is selected after inspection.

| Arm | Diagnostic | TP | TP change | F1 | F1 change | Paired 95% CI |
| --- | --- | --- | --- | --- | --- | --- |
| SAT | Isolated-top AGL | 601 | +2 | 0.7347 | 0.0024 | [0.0000, 0.0056] |
| SAT | Historical raw Z | 597 | -2 | 0.7298 | -0.0024 | [-0.0072, 0.0023] |
| FF3D | Isolated-top AGL | 676 | +0 | 0.8091 | 0.0000 | [0.0000, 0.0000] |
| FF3D | Historical raw Z | 677 | +1 | 0.8103 | 0.0012 | [0.0000, 0.0047] |

## Per-Plot Default Apex Results

All rows passed admission. The origin identifies unchanged pilot reuse or a
new cell; it is not an eligibility or weighting distinction.

| Plot | Arm | Origin | References | Predictions | TP | FP | FN | F1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1001 | CHM-VWF | pilot | 133 | 38 | 36 | 2 | 97 | 0.4211 |
| 1001 | SAT | pilot | 133 | 109 | 96 | 13 | 37 | 0.7934 |
| 1001 | FF3D | pilot | 133 | 128 | 113 | 15 | 20 | 0.8659 |
| 1005 | CHM-VWF | new | 87 | 46 | 44 | 2 | 43 | 0.6617 |
| 1005 | SAT | new | 87 | 74 | 65 | 9 | 22 | 0.8075 |
| 1005 | FF3D | new | 87 | 118 | 79 | 39 | 8 | 0.7707 |
| 1009 | CHM-VWF | new | 103 | 48 | 45 | 3 | 58 | 0.5960 |
| 1009 | SAT | new | 103 | 126 | 96 | 30 | 7 | 0.8384 |
| 1009 | FF3D | new | 103 | 112 | 97 | 15 | 6 | 0.9023 |
| 1013 | CHM-VWF | new | 28 | 28 | 17 | 11 | 11 | 0.6071 |
| 1013 | SAT | new | 28 | 35 | 24 | 11 | 4 | 0.7619 |
| 1013 | FF3D | new | 28 | 30 | 26 | 4 | 2 | 0.8966 |
| 1019 | CHM-VWF | pilot | 8 | 10 | 8 | 2 | 0 | 0.8889 |
| 1019 | SAT | pilot | 8 | 17 | 8 | 9 | 0 | 0.6400 |
| 1019 | FF3D | pilot | 8 | 14 | 8 | 6 | 0 | 0.7273 |
| 1020 | CHM-VWF | new | 62 | 43 | 32 | 11 | 30 | 0.6095 |
| 1020 | SAT | new | 62 | 85 | 52 | 33 | 10 | 0.7075 |
| 1020 | FF3D | new | 62 | 59 | 48 | 11 | 14 | 0.7934 |
| 1022 | CHM-VWF | new | 213 | 35 | 35 | 0 | 178 | 0.2823 |
| 1022 | SAT | new | 213 | 92 | 91 | 1 | 122 | 0.5967 |
| 1022 | FF3D | new | 213 | 131 | 128 | 3 | 85 | 0.7442 |
| 1024 | CHM-VWF | new | 62 | 41 | 35 | 6 | 27 | 0.6796 |
| 1024 | SAT | new | 62 | 100 | 54 | 46 | 8 | 0.6667 |
| 1024 | FF3D | new | 62 | 75 | 54 | 21 | 8 | 0.7883 |
| 1027 | CHM-VWF | pilot | 96 | 40 | 33 | 7 | 63 | 0.4853 |
| 1027 | SAT | pilot | 96 | 85 | 73 | 12 | 23 | 0.8066 |
| 1027 | FF3D | pilot | 96 | 93 | 83 | 10 | 13 | 0.8783 |
| 1031 | CHM-VWF | new | 49 | 46 | 27 | 19 | 22 | 0.5684 |
| 1031 | SAT | new | 49 | 72 | 40 | 32 | 9 | 0.6612 |
| 1031 | FF3D | new | 49 | 70 | 40 | 30 | 9 | 0.6723 |

## Resources

All cells ran on the same host, equipped with an NVIDIA GeForce RTX 5090
(32,607 MiB, driver 595.84). CHM-VWF uses the CPU.
The table includes the original nine pilot executions once. Wall times include
command startup, model staging, inference and export, but exclude host-side
scoring, hashing and FF3D's preceding private source copy. Concurrent CPU
verification can affect these observed times; this is not an isolated speed
benchmark. Host RSS is the native model process maximum (R for CHM), not the
sum of the process tree. GPU values are PyTorch allocated/reserved peaks,
not total device use. Exact per-cell measurements are in `status.csv`.

| Arm | Total detector wall (s) | Median per-cell wall (s) | Maximum host RSS (MiB) | Maximum GPU allocated (MiB) | Maximum GPU reserved (MiB) |
| --- | --- | --- | --- | --- | --- |
| CHM-VWF | 48.3 | 4.5 | 945.6 | not used | not used |
| SAT | 1401.2 | 143.5 | 3251.9 | 605.9 | 958.0 |
| FF3D | 4332.2 | 450.3 | 5165.3 | 9954.4 | 13690.0 |

## Provenance, Limits and Next Step

`development_detector_run/run.json` seals 210 new output/log files,
the expansion orchestrator, the unchanged eight pilot execution files, the
comparison/runtime parents and 349 protected prior metadata files. It retains
each pilot cell's original source path and exact record. Both earlier pilot
attempts remain preserved and excluded. Independent receipt replay verifies
the entire chain without rerunning detectors.

`development_detector_summary/summary.json` seals its parent run, four analysis
files and eight output files: status, long-form accumulators, pooled metrics,
metric intervals, paired contrasts, bootstrap indices, analysis metadata and
the R log. The 90 accumulator rows comprise 30 default apex rows, 40 paired
height-diagnostic rows and 20 mask rows. Every primary summary uses all ten
plots. Sealed incomplete or failed runs produce status only, never a primary
ranking or fabricated empty predictions.

The apex track is an annotated point-cloud proxy using a shared terrain
estimate. Independent AGL accuracy is unverified. The fixed support, very high
native densities and unknown upstream training overlap limit generalization.
These results do not establish a deployment threshold, calibration quality,
fusion benefit, sparse-density performance or unseen-data accuracy.

The next declared step is the 50 whole-plot calibration validation cells:
three apex targets and two mask targets across ten folds, training each
calibrator only on the other nine plots. Retain every fixed-filter prediction
in baseline scoring and report unavailable/out-of-range calibration counts.
No calibration is fitted here. Reserve evaluation requires a separate frozen
development policy and overlap decision.

## Verification and Reproduction

- Full Python discovery passed: 55 tests, 53 passed and two optional upstream
  checkout tests skipped in the isolated worktree.
- Full R suite passed with three existing skips: gated legacy-cylinder GPU
  smoke, unsupported empty-LAS fixture and default Python's missing `plyfile`.
  The existing R-universe package-index network warning remains.
- Regression checks cover exact pilot reuse, stop-on-failure, empty versus
  failed cells, support/denominator changes, count-based pooling, deterministic
  paired resampling, undefined metrics and analysis provenance.
- The production R summary CLI also passed a complete synthetic 1,000-draw
  smoke. The real 30-cell run and real summary completed and replayed
  independently. No GPU inference is inferred from unit-test success.
- Independent Python/NumPy recomputation matched all nine pooled groups,
  41 metric intervals and eight paired contrasts using the saved draw indices.
- README methods, workflow, requirements, script entries and report index
  are updated. Repository-wide Markdown and whitespace checks passed before
  publication. The original dirty checkout remains untouched.

Use the existing Python environment, pinned runtime and installed images. The
[README workflow](../README.md#fgi-emit-complete-development-comparison)
gives the creation and independent verification commands. Outputs live under
`work/external/fgiemit/development_detector_run/` and
`work/external/fgiemit/development_detector_summary/`. Creation requires fresh
directories and never overwrites the admitted pilot or another attempt.
Native inputs, clouds, logs, CSVs and runtime files remain local ignored
artifacts; the committed report records the completed results.
