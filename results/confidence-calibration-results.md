# Per-detection confidence calibration (#P4)

This study maps detector scores to empirical field-match precision using
isotonic calibration. Results were regenerated on 2026-09-15 for #98 and #95:
validation now holds out whole plots, and DeepForest's native detector score
joins the five LiDAR arms. These numbers supersede the earlier experiment
that split individual detections across folds.

Regenerate:

```sh
export CLAUDE_JOB_DIR=$(pwd)/work
Rscript scripts/calibrate_confidence.R SITES=SOAP,SJER,TEAK
# Reuse existing labelled detections; materialize DeepForest if absent:
Rscript scripts/calibrate_confidence.R SITES=SOAP,SJER,TEAK FROM_CACHE=1
# -> work/neon/<SITE>/confidence_calibration.csv (one row per labelled detection)
#    work/neon/<SITE>/confidence_lookup.csv      (per-arm isotonic knots for #P1)
```

## What this is

Per-arm raw confidence, materialized on the same native frozen cells as #P1 and
labelled TP/FP with `greedy_match` restricted to the plot core (mirroring
`score_plot`'s precision denominator):

- **forestformer3d** — the **native** per-instance mask score: mean `ff3d_score`
  over the instance's points. `ff3d_arm.py` writes this extra dim and the R
  loaders ignored it; this exposes it (the issue's explicit ask).
- **segmentanytree** — crown point count (`run_segmentanytree.py` writes no score
  field): a size proxy.
- **chm_vwf / multichm / li2012** — apex CHM height (AGL): the classical-arm
  proxy (taller apices are more often real dominant trees).
- **deepforest** — the detector's RGB box score, with apex height sampled from
  the native frozen CHM. RGB coverage is currently SOAP only.

Every site/plot group is held out in turn across all arms and density rungs.
Both the per-arm min-max scale and the isotonic fit use only the other plots.
Held-out scores outside the training range are clipped to its endpoints.
An arm present in only one plot receives no held-out prediction, rather than a
prediction trained on its own labels. Constant-score training samples return
their empirical base rate. Precision-at-recall includes whole tied-score groups,
so each reported operating point corresponds to a realizable threshold.

`confidence_calibration.csv` now includes `rung`, `fold`, `prob_cv`, and `cal`.
Optical rows also record `rgb_year`; consumers must require a matching RGB epoch.
The deployment lookup carries `arm`, `rung`, `raw_min`, `raw_max`, `raw_prob`,
and `calibrated`; `apply_confidence_lookup()` can reproduce predictions without
the training table. The full-data deployment fit must not score the same plots
used to train it. Fusion benchmarks must refit DeepForest excluding each target
plot, using its cached labelled detections; integration is tracked in #95.

## Generated tables

Native density, 46 plots across three sites, 5,643 labelled detections. All
detections have held-out predictions. The first five arms retain their original
5,340 detections; DeepForest contributes 303 core detections from SOAP.

### Per-arm calibration

| arm | n | base precision | ECE_raw | ECE_cal (CV) | ΔECE |
|---|--:|--:|--:|--:|--:|
| chm_vwf | 763 | 0.336 | 0.167 | 0.042 | -0.125 |
| multichm | 1023 | 0.333 | 0.186 | 0.059 | -0.126 |
| li2012 | 1189 | 0.266 | 0.129 | 0.063 | -0.066 |
| segmentanytree | 1245 | 0.334 | 0.264 | 0.037 | -0.227 |
| forestformer3d | 1120 | 0.224 | 0.125 | 0.010 | -0.116 |
| deepforest | 303 | 0.389 | 0.154 | 0.058 | -0.096 |

### Ensemble precision @ fixed recall (pooled multi-arm, held-out)

Ranking the pooled six-arm detection set by calibrated versus normalized raw
score. Here recall is the fraction of labelled positive detections retained,
not unique field-stem recall after spatial fusion.

| recall | P_raw | P_calib | gain |
|--:|--:|--:|--:|
| 0.50 | 0.338 | 0.383 | +0.046 |
| 0.60 | 0.341 | 0.352 | +0.010 |
| 0.70 | 0.334 | 0.355 | +0.021 |
| 0.80 | 0.330 | 0.340 | +0.010 |
| 0.90 | 0.322 | 0.320 | -0.002 |

### Per-site ensemble gain @ recall 0.70 (held-out)

| site | n_det | P_raw | P_calib | gain |
|---|--:|--:|--:|--:|
| SOAP | 2340 | 0.356 | 0.397 | +0.041 |
| SJER | 1203 | 0.214 | 0.204 | -0.011 |
| TEAK | 2100 | 0.377 | 0.382 | +0.004 |

### SegmentAnyTree raw reliability (the worst-ECE arm, 5 bins)

| confidence bin | n | mean score | observed precision |
|--:|--:|--:|--:|
| 1 (0.0–0.2) | 1130 | 0.060 | 0.327 |
| 2 (0.2–0.4) | 88 | 0.271 | 0.375 |
| 3 (0.4–0.6) | 17 | 0.505 | 0.588 |
| 4 (0.6–0.8) | 5 | 0.689 | 0.600 |
| 5 (0.8–1.0) | 5 | 0.940 | 0.000 |

## Readings

- Calibration reduces held-out ECE for all six arms. The plot-held-out ECE
  range, 0.010-0.063, is higher than the earlier detection-split estimates.
- **"Bigger mask = more confident" is false at the extreme.** SegmentAnyTree's
  reliability diagram is non-monotone at the top: its five largest-point-count
  masks (mean score 0.94) have **observed precision 0.000** — the biggest masks
  are usually over-grown / merged over-segmentation, not the most certain trees.
  Isotonic calibration caps that high end to empirical precision, which is exactly
  the correction a weighted vote needs.
- Calibration helps pooled ranking at 50-80% recall, but loses 0.002 precision
  at 90% recall. At 70% recall it helps SOAP and TEAK and hurts SJER. The
  earlier claim of improvement at every operating point and site is withdrawn.
- **The shipped lookup is fit on all data.** `confidence_lookup.csv` carries each
  arm's isotonic knots fit on the full per-arm sample (max data for downstream
  use); the ECE/precision numbers above are the honest held-out estimates of how
  well that mapping generalizes.

## Caveats

- **Labels are apex-proximity TP/FP** (`greedy_match`, 4 m + height gate), so a
  detection of a real-but-unmapped tree is labelled FP. Calibration
  targets *this* precision; absolute precision is a lower bound, but the
  raw-vs-calibrated comparison is internally consistent (same labels both ways).
- **Proxies for four of six arms.** ForestFormer3D and DeepForest expose learned
  scores; SegmentAnyTree's `run_segmentanytree.py` writes none
  (point count is a stand-in until a mask score is persisted on the next run), and
  the CHM/classical arms use apex height. Calibration makes them *comparable*, not
  equally *informative* — a better raw signal (e.g. local-maximum prominence) would
  raise the ceiling.
- **Native density only**; the calibrators are fit at native and would need
  re-fitting per rung for a density-stratified weighting.
