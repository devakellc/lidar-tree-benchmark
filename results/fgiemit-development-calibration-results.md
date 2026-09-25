# FGI-EMIT Whole-Plot Development Calibration

Completed on 2026-09-25: all 50 declared calibration validation cells fitted
successfully. Each fit uses nine development plots and validates on the tenth
whole plot. The stage reads the sealed
[complete detector comparison](fgiemit-development-comparison-results.md)
without new inference or changes to its inputs, settings, predictions or
baseline scores. The three reserve plots remain closed.

This is conditional development evidence. Holding out post-hoc calibration
does not remove unknown upstream checkpoint training overlap. These results
do not establish unseen-data accuracy, a useful deployment threshold or a
fusion benefit.

## Population and Frozen Methods

The development plots are 1001, 1005, 1009, 1013, 1019, 1020, 1022, 1024, 1027
and 1031. All five arm/target combinations retain all ten plots and the same
841-reference population. The input population remains 32,445,937 retained
points, including background, edge trees, dead trees and short references.
The original class-5 exclusion, native densities, geometric AGL estimate and
plot-local metre frames are unchanged. The historical six-plot transfer study
and prospective reserve are separate populations.

The [comparison protocol](../docs/fgiemit-comparison-protocol.md) fixes the
five fits per fold: CHM-VWF, SegmentAnyTree (SAT) and ForestFormer3D (FF3D)
for the maximum-AGL apex target, plus SAT and FF3D separately for mask IoU 0.5.
The isolated-top and historical-height diagnostics never supply calibration
labels or scores. No target shares fitted probabilities with another target.

Apex TP/FP labels preserve the default 4 m XY/5 m height gate, one-to-one
greedy matching and distance/reference-row/prediction-row tie order. Both
input tables are sorted by instance ID, as in the frozen scorer. Every cell's
recovered counts agree with the unchanged default matcher and sealed baseline.
Mask labels reuse `point_set_iou` and `iou_match` on every retained source row,
with label zero as background. Prediction and reference instance populations
must match their sealed apex tables exactly. No partial export, nearest-point
projection, new filtering or reference exclusion is admitted.

The raw features remain CHM AGL height, retained instance point count for SAT,
and mean native FF3D score across each retained instance's assigned rows.
Each fold aggregates equal raw scores by count and TP sum before weighted
PAVA. It persists the raw-score knots and linearly interpolates between them.
At least two distinct training scores and both TP/FP classes are required.
All 50 real fits meet those requirements. Validation data cannot supply
training labels, score normalization or bounds. Scores strictly outside the
training range remain uncalibrated, without endpoint substitution.

## Coverage and Unavailable Scores

There are 50 successful-nonempty validation cells, zero successful-empty
cells, zero failed or missing cells, and zero unavailable fits. Of 3,625
prediction/target records, 3,595 receive out-of-fold probabilities; 30 remain
unavailable because their raw scores fall outside the training range. These
records represent 2,000 unique detector predictions: instance predictions
appear once per target. Unavailable probabilities never remove predictions
from baseline scoring.

| Target | Arm | Predictions | Calibrated | Unavailable | Coverage [95% CI] | TP among unavailable |
| --- | --- | --- | --- | --- | --- | --- |
| Maximum-AGL apex | CHM-VWF | 375 | 359 | 16 | 95.73% [86.69%, 100%] | 13 |
| Maximum-AGL apex | SAT | 795 | 792 | 3 | 99.62% [98.91%, 100%] | 1 |
| Maximum-AGL apex | FF3D | 830 | 826 | 4 | 99.52% [98.79%, 100%] | 0 |
| Mask IoU 0.5 | SAT | 795 | 792 | 3 | 99.62% [98.91%, 100%] | 1 |
| Mask IoU 0.5 | FF3D | 830 | 826 | 4 | 99.52% [98.79%, 100%] | 0 |

CHM's unavailable scores occur on plot 1020 (one) and plot 1024 (15). SAT's
occur on plots 1009 (one) and 1013 (two), for each target. FF3D's occur on
plots 1020 and 1031 (two each), for each target. All other validation cells
have complete calibration coverage. These exclusions are visible in both
the per-prediction reasons and per-fold status table.

The unchanged pooled apex TP/FP/FN counts are 312/63/529 for CHM-VWF,
599/196/242 for SAT and 676/154/165 for FF3D. Mask counts are 501/294/340
for SAT and 596/234/245 for FF3D. Calibration does not improve those counts
or change the original detector comparison.

## Validation Brier Score and Reliability

Brier score is the mean squared error against each available TP/FP label.
ECE uses ten fixed equal-width bins over [0, 1], pooling prediction counts
and probability/label sums before taking bin gaps. Bins include their left
edge; the final bin also includes 1. Empty bins remain explicit. Neither
metric averages per-plot rates, and neither assigns a fallback probability
to unavailable records. Coverage in the table above applies to every metric
below.

| Target | Arm | Brier [95% CI] | ECE [95% CI] |
| --- | --- | --- | --- |
| Maximum-AGL apex | CHM-VWF | 0.1477 [0.0882, 0.2184] | 0.1212 [0.0768, 0.1938] |
| Maximum-AGL apex | SAT | 0.1727 [0.1456, 0.2018] | 0.0984 [0.0608, 0.1706] |
| Maximum-AGL apex | FF3D | 0.1524 [0.1141, 0.2010] | 0.0527 [0.0289, 0.1362] |
| Mask IoU 0.5 | SAT | 0.1870 [0.1614, 0.2149] | 0.0652 [0.0546, 0.1404] |
| Mask IoU 0.5 | FF3D | 0.1806 [0.1542, 0.2050] | 0.0603 [0.0441, 0.1225] |

Intervals use 1,000 paired whole-plot bootstrap draws with seed 20260923,
the exact plot indices used in the detector summary, and 95% percentile
limits with R quantile type 7. Every draw pools the selected plots' fixed
out-of-fold prediction records and recomputes coverage, Brier and ECE.
All 15 intervals have 1,000 defined draws.

These intervals are conditional on the fitted folds and observed detector
outputs. They do not refit calibrators, model cross-validation training-set
dependence, or include model/checkpoint/terrain uncertainty. The analysis
metadata records this restriction explicitly.

Brier score depends on the TP prevalence and discrimination of each arm's
prediction population; these arms have different predictions and unavailable
subsets. A lower Brier score therefore does not rank detector performance or
prove a calibration improvement over an uncalibrated probability baseline.
The raw height/count features are not probabilities. Residual ECE remains
visible, especially for the CHM height proxy, and its intervals are broad.
No fitted probability is treated as a validated deployment cutoff.

## Artifacts and Reproduction

The new `development_calibration/calibration.json` receipt seals the complete
detector run, detector summary and declared calibration matrix; seven code
files; and eleven input/output/log files. The parent verification chain also
checks the earlier pilot, prepared inputs, checkpoint identities and protected
historical metadata. Existing execution and summary files remain unchanged.

The output directory contains `cells.csv` with the frozen baseline counts
and source paths, `folds.csv` with all nine-plot training complements,
`predictions.csv` with target-specific labels/probabilities/reasons, and
`status.csv` with all 50 validation statuses and training support. `knots.csv`
stores 32,430 raw-score knots across the 50 fits. These are validation-fold
artifacts; there is no all-development deployment lookup. `pooled.csv`,
`reliability.csv`, `intervals.csv`, `bootstrap_indices.csv`, `analysis.json`
and `analysis.log` complete the sealed output set.

Use the existing Python environment and the
[README calibration workflow](../README.md#fgi-emit-development-calibration).
Creation requires a new output directory and has a 3,600-second process limit.
The completed artifacts live under
`work/external/fgiemit/development_calibration/`. An error preserves its log
and inputs without writing a success receipt; reruns require a fresh directory.
Receipt verification is read-only. It checks parent identities without model
inference. Clouds, CSVs, knots and logs remain local ignored artifacts.

## Verification and Next Step

- The full R suite passed. Existing skips are the gated legacy-cylinder GPU
  smoke, the unsupported empty-LAS fixture and default Python's missing
  `plyfile`. The existing R-universe package-index network warning remains.
- Full Python discovery passed: 59 tests, 57 passed and two optional upstream
  checkout tests skipped. The existing GPU Python environment was used.
- New regression checks cover tie-weighted PAVA, linear interpolation, exact
  bounds, unavailable fits, empty validation cells, whole-plot exclusion,
  target separation, matching compatibility, pooled ECE and sealed provenance.
- The real CPU run completed all 50 folds and passed independent receipt
  replay. Every reconstructed baseline count agrees with the frozen results.
- An independent SciPy 1.17.1 isotonic calculation reproduced all 32,430 knots
  and 3,625 prediction/target records. Maximum probability error was below
  1e-12; independently recomputed pooled metrics and all 15 interval bounds
  agreed within 1e-12. Saved bootstrap indices exactly match the detector
  summary. The verification script and JSON evidence remain in
  `work/fgiemit-calibration-verification/`.
- README method summaries, workflow, requirements, script entries and report
  links are updated. Full Markdown and whitespace checks precede publication.
  The original dirty checkout is preserved.

The subsequent [frozen policy](../docs/fgiemit-frozen-policy.md) selects the
FF3D detector baseline with fixed controls and the existing filters, following
the [checkpoint-overlap review](fgiemit-checkpoint-overlap-results.md).
This calibration stage selects no threshold, ensemble membership or reserve
release. Independent AGL accuracy, dense-support generalization and unknown
checkpoint training overlap remain unresolved. The new policy requires
separate reserve input validation and an execution contract before inference.
