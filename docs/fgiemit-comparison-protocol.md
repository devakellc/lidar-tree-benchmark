# FGI-EMIT Development Comparison Contract

Frozen on 2026-09-23 after the
[input validation](../results/fgiemit-development-input-results.md), before
new detector inference or calibration. This is a development comparison of
fixed methods, with upstream training overlap unknown. It is not independent
held-out validation. The original ten development plots, ten whole-plot folds,
three reserve plots and six historical-test plots remain unchanged.

## Fixed Comparison Matrix

There are 30 planned native-density cells: ten development plots times three
arms. Each arm runs once per plot. No hyperparameter sweep, density thinning,
second-pass segmentation, species inference or optical input is included.

| Arm | Input and configuration | Tracks | Confidence feature |
| --- | --- | --- | --- |
| CHM-VWF | Prepared normalized geometry; lasR TIN of first returns, `pit_fill`, and `local_maximum_raster`. Resolution and smoothing derive from measured first-return density. `ws_factory(0.10, 3, 5)`, minimum height 2 m. | Derived-apex detection only | Detected AGL height; a proxy, not a probability |
| SegmentAnyTree | Prepared local-elevation XYZ with ground; the verified installed checkpoint/image and existing configuration. No original semantic labels or reference heights. | Instance masks and derived-apex detection | Retained instance point count; a size proxy |
| ForestFormer3D | Same local-elevation XYZ support; verified checkpoint/image; exactly one indexed whole-scene invocation and the existing native mask-assignment policy. | Instance masks and derived-apex detection | Mean native `ff3d_score` over assigned instance rows |

CHM resolution is 0.25 m for first-return density at least 8/m², 0.5 m for
at least 4/m², otherwise 1 m. Apply the existing 3-by-3 mean smoothing only
below 8/m². Reject density below 1/m². These declarations therefore select
0.25 m and no smoothing on all ten current plots. Use the measured all-return
density for the no-upsampling check; do not substitute it for first returns.
The window is `min(max(0.10 * h + 3, 3), 5)` metres. This lasR TIN/pit-fill
construction is distinct from lidR's Khosravipour pitfree algorithm.

Freeze candidate driver, matching and configuration identities in the receipt.
Record installed R package identities and the lasR variable-window constructor
probe. Missing lasR source-revision metadata remains explicit; constructor
acceptance alone does not certify build lineage. A runner must establish the
documented `r-lidar/lasR@pre-devel` build before executing the classical arm.
Retain existing upstream stochastic settings; record realized seeds where
available and do not claim bitwise repeatability. There is no best-of-several
run selection. TreeisoNet and classical Treeiso are outside this matrix.

## Common Support and Output Contracts

All arms use the same retained classes 0–4 and the same plot-local metric
frame. No rectangular NEON core or invented EPSG may replace this support.
Buildings, vehicles, poles and unassigned background remain in scoring.
Original annotations are accessible only to reference construction/scoring.
Every development reference remains in the denominator, including edge and
dead trees and low-height references. No class is dropped to improve a score.

Mask predictions must resolve to exactly one label per retained source row,
including background 0 and coincident points. Prefer explicit `source_row`
identity. Any alternative correspondence must prove complete, unambiguous row
coverage and preserve coordinates within the declared export precision.
Nearest-neighbor projection from incomplete outputs is not accepted. An
unresolved SegmentAnyTree correspondence is a failed cell, not permission to
copy the historical 0.5 m transfer. This contract requires a runner/adapter
check before execution; the declaration alone does not establish compliance.

For both instance arms, retain predicted instances with at least 40 assigned
points and at least 1.5 m raw local-Z extent, matching the existing external
scorer. Removed instances become background on their original rows. Apply
these same retained masks to both tracks. CHM detections use only their fixed
2 m height threshold and receive no invented masks or instance-size filter.

## Height and Reference Rules

The primary segmentation result uses unchanged reference instance masks and
the existing one-to-one point-set IoU matcher at 0.5. Report pooled TP, FP, FN,
precision, recall, F1, coverage and original A–D recalls. Supplementary PQ
remains separate. Height extraction does not modify these masks or matches.

The shared detection proxy uses **maximum pointwise AGL** per reference
instance. Extract prediction apexes from the same normalized source rows
assigned to each retained mask; CHM already supplies AGL detections. For ties,
choose the smallest original `source_row`. Keep the selected row's X, Y and Z
together. Background rows never generate reference or instance apexes.

Use the existing FGI diagnostic matcher, `audit_apex_match`: global nearest-XY
greedy one-to-one assignment, XY distance at most 4 m and absolute height
difference at most 5 m. Sort references by tree ID and predictions by instance
ID; sort CHM detections lexicographically by X, Y, Z. This is an annotated
point-cloud apex proxy, not a field-stem or publisher-centroid metric.

Two paired diagnostics are mandatory for the instance arms, on the same
predictions and reference population:

1. **Historical raw maximum:** select each instance's maximum raw local Z and
   run the same 4 m/5 m matcher. This preserves the former FGI diagnostic
   convention as the explicit comparator for the change to common AGL.
2. **Isolated-top AGL:** if the two highest AGL rows differ by strictly more
   than 0.25 m, select the second-highest row once. Apply this identically to
   predicted and reference instances. A singleton keeps its only row; equal
   heights or a gap of exactly 0.25 m retain the maximum. Move XY with the
   selected row. Report changes in matches and F1 beside the default; never
   choose the better result after inspection or use this diagnostic to tune.

The [publisher's procedure](https://arxiv.org/html/2511.00653v1#S3.SS3.SSS3)
applies its outlier rule to raw Z, then uses local non-tree minima and a crown
centroid. Our AGL diagnostic is explicitly different. Published centroid/height
metadata are not substituted for derived apexes, supplied to models or used
to reclassify A–D categories. The shared terrain estimate enables consistent
comparison but does not prove independent AGL accuracy. Report that limitation.

## Calibration Matrix

Freeze five arm/target combinations: all three arms for the default derived
AGL-apex match, and the two instance arms separately for mask IoU 0.5. Never
reuse one target's probabilities for another. The two height diagnostics are
uncalibrated robustness checks and cannot train either target's calibrator.

Each of ten outer folds fits on the other nine development plots only, using
the declared arm confidence feature. This gives 50 planned validation cells.
Use weighted isotonic regression, aggregating equal raw scores by count and
TP sum before PAVA. Persist raw-score knots and linearly interpolate fitted
probabilities. At least two distinct training scores and both TP/FP labels
are required. Otherwise mark calibration unavailable. Validation scores outside
the training range stay uncalibrated and are counted explicitly; no endpoint
fallback probabilities or validation-derived normalization bounds are allowed.

Report validation Brier score and count-weighted ECE with ten fixed equal-width
bins, plus calibrated/unavailable counts. Baseline performance retains all
fixed-filter predictions; there is no calibrated threshold search, fusion,
cross-arm raw-score ranking or deployment lookup export in this comparison.
Cross-validation holds out post-hoc calibration only; it cannot remove unknown
upstream checkpoint overlap. No calibrator is fitted by the declaration tool.

## Execution Order, Failures and Claims

Before a full run, test the new runner's frame, correspondence and resource
contracts on development plots 1001, 1019 and 1027, in that order. These cover
the earlier dense/sparse adapter inputs and the largest prepared development
cloud. Run CHM-VWF, SegmentAnyTree and ForestFormer3D sequentially per plot.
Use one cell at a time and a 3,600-second wall limit. Preserve native memory
settings and measure wall time, host RSS and available GPU peak statistics.
No automatic retries, fallback tiling, checkpoint changes or parameter rescue.

Successful pilot cells may count in the full matrix only with identical sealed
runner/configuration/input hashes; run them once. Any failed output contract
stops expansion until investigated. A changed implementation creates a new
attempt root and records the change; it must not overwrite or silently mix
cells from different configurations.

Distinguish planned, failed, missing, successful-empty and successful-nonempty
cells. A failure is not zero detections. Primary pooled comparisons require
all declared cells for their track; otherwise report the missing cells and
reference counts, with no primary ranking. Any common-subset analysis must be
labelled diagnostic with its exact excluded plots and denominators.

Pool counts and error sums, never per-plot rates or RMSEs. Use paired whole-plot
bootstrap intervals with 1,000 resamples and seed 20260923 only on complete
comparisons; resample the same plot indices across arms. Category metrics with
no references stay undefined. Do not pool overlapping regions as independent
plots. Calibration coverage must accompany every calibration summary.

Unknown checkpoint overlap permits this explicitly conditional development
comparison, not an unseen-data claim. Reserve evaluation remains closed until
a separate frozen development policy and overlap decision exist. The current
declaration creates reference tables and planned cells only: no detector run,
calibration fit, model ranking or reserve release. A simpler single-arm result
remains acceptable; this matrix supplies no presumption of fusion benefit.
