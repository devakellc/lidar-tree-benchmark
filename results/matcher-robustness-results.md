# Matcher robustness: scaled tolerance + Hungarian re-score

## Five sites, every arm

Checked on 5 October 2026 on the frozen five-site `adopted` population (106
plots, 2,525 stems), for all twelve arms. `paper_sensitivity.R MODE=matcher`
re-scores every arm's persisted detections on the sealed clips under the
matcher configurations below and the greedy `tol_xy` × `tol_z_up` grid; the
re-scored baseline reproduces every arm's own result rows (4,664 cells, no
difference). Change in native F1 from the baseline (greedy, flat 4 m, height
band [0.5h, h + 8 m]), five sites, paired plot-bootstrap intervals:

| Arm | Baseline F1 | Crown-scaled tolerance | Hungarian | Hungarian, scaled | Soft 3-D cost |
| --- | --- | --- | --- | --- | --- |
| ForestFormer3D | 0.498 | +0.008 [+0.005, +0.011] | +0.021 [+0.016, +0.027] | +0.031 [+0.026, +0.038] | −0.007 [−0.015, +0.001] |
| SegmentAnyTree | 0.495 | +0.007 [+0.004, +0.011] | +0.029 [+0.022, +0.036] | +0.038 [+0.031, +0.045] | +0.005 [−0.006, +0.013] |
| Li 2012 | 0.456 | +0.006 [+0.003, +0.009] | +0.020 [+0.015, +0.025] | +0.028 [+0.022, +0.034] | +0.006 [−0.001, +0.013] |
| `multichm` | 0.456 | +0.007 [+0.005, +0.011] | +0.013 [+0.009, +0.017] | +0.021 [+0.016, +0.027] | −0.012 [−0.024, −0.001] |
| DeepForest | 0.454 | +0.007 [+0.004, +0.010] | +0.029 [+0.023, +0.034] | +0.036 [+0.030, +0.042] | +0.008 [−0.001, +0.017] |
| CHM-VWF | 0.450 | +0.006 [+0.003, +0.009] | +0.023 [+0.016, +0.029] | +0.029 [+0.022, +0.036] | +0.008 [−0.003, +0.017] |
| TreeisoNet | 0.446 | +0.007 [+0.004, +0.010] | +0.023 [+0.017, +0.029] | +0.031 [+0.024, +0.038] | +0.003 [−0.006, +0.011] |
| `lmfauto` | 0.386 | +0.006 [+0.003, +0.009] | +0.010 [+0.006, +0.015] | +0.016 [+0.011, +0.022] | +0.000 [−0.005, +0.006] |
| Detectree2 | 0.362 | +0.011 [+0.007, +0.016] | +0.008 [+0.004, +0.011] | +0.019 [+0.013, +0.025] | −0.010 [−0.021, 0.000] |
| `ptrees` | 0.331 | +0.003 [+0.001, +0.004] | +0.015 [+0.011, +0.020] | +0.018 [+0.014, +0.023] | +0.001 [−0.004, +0.007] |
| AMS3D | 0.240 | +0.003 [+0.002, +0.005] | +0.010 [+0.007, +0.014] | +0.013 [+0.010, +0.017] | +0.003 [−0.001, +0.008] |
| SAM2Point | 0.132 | +0.005 [+0.002, +0.009] | +0.001 [+0.000, +0.002] | +0.006 [+0.003, +0.010] | −0.017 [−0.025, −0.010] |

The lead of the two learned segmenters over CHM-VWF, native F1, under each
matcher and three cells of the tolerance grid, with Kendall τ between each
matcher's twelve-arm ranking and the baseline's:

| Matcher | ForestFormer3D − CHM-VWF | SegmentAnyTree − CHM-VWF | τ with baseline |
| --- | --- | --- | --- |
| Baseline (greedy, 4 m) | +0.048 | +0.044 | 1.00 |
| Crown-scaled tolerance | +0.050 | +0.046 | 0.97 |
| Hungarian | +0.046 | +0.051 | 0.85 |
| Hungarian, scaled | +0.050 | +0.054 | 0.88 |
| Soft 3-D cost | +0.033 | +0.041 | 0.85 |
| Greedy, 2 m | +0.012 | +0.026 | 0.79 |
| Greedy, 3 m | +0.040 | +0.037 | 0.85 |
| Greedy, 5 m | +0.055 | +0.046 | 0.91 |

**Readings.**

- The alternative matchers do not change the observed leads. Hungarian
  assignment raises every arm's F1 by at most 0.03 at native density, 0.04
  with crown-scaled tolerance, and the soft 3-D cost moves arms by −0.02 to
  +0.01. The two learned segmenters lead CHM-VWF by 0.03 to 0.06 under every
  matcher and at radii of 3 to 5 m, and over that range the ranking of all
  twelve arms keeps τ ≥ 0.85 with the baseline's.
- The match radius is the lever that matters. With the default height band,
  over all arms and rungs, a 2 m radius lowers F1 by 0.04 to 0.16 (0.05 to
  0.14 at native density) and 3 m by 0.01 to 0.06, while 5 m raises it by
  0.01 to 0.04. Every arm moves the same way but not by the same amount: at
  2 m ForestFormer3D's lead falls to +0.012 and τ to 0.79 (below).
- Most false positives are isolated rather than near a matched stem: 81–93 %
  for every arm except the point segmenters (AMS3D and `ptrees` 64–65 %,
  `lmfauto` 74 %), which over-segment crowns. Isolated false positives are
  where unmapped real trees hide (see the
  [coverage-gap study](coverage-gap-results.md)).

### Leads by radius and region

Native F1 leads over CHM-VWF with paired plot-bootstrap intervals
(`matcher_leads.csv`, greedy matcher, default height band):

| Radius | Scope | ForestFormer3D | SegmentAnyTree | `multichm` |
| --- | --- | --- | --- | --- |
| 4 m | Five sites | +0.048 [+0.028, +0.069] | +0.044 [+0.021, +0.067] | +0.005 [−0.018, +0.028] |
| 3 m | Five sites | +0.040 [+0.018, +0.061] | +0.037 [+0.014, +0.058] | −0.011 [−0.035, +0.011] |
| 2 m | Five sites | +0.012 [−0.008, +0.031] | +0.026 [+0.009, +0.043] | −0.032 [−0.053, −0.011] |
| 4 m | California | +0.086 [+0.054, +0.120] | +0.087 [+0.041, +0.131] | +0.054 [+0.020, +0.086] |
| 3 m | California | +0.076 [+0.047, +0.105] | +0.084 [+0.036, +0.127] | +0.048 [+0.017, +0.076] |
| 2 m | California | +0.063 [+0.040, +0.087] | +0.074 [+0.040, +0.105] | +0.035 [+0.008, +0.062] |
| 4 m | Washington | +0.032 [+0.005, +0.059] | +0.030 [+0.006, +0.050] | −0.013 [−0.040, +0.015] |
| 3 m | Washington | +0.024 [−0.004, +0.051] | +0.022 [−0.001, +0.042] | −0.034 [−0.062, −0.008] |
| 2 m | Washington | −0.010 [−0.036, +0.016] | +0.012 [−0.008, +0.029] | −0.057 [−0.080, −0.032] |

The loss at tight radii is in Washington: at 2 m ForestFormer3D falls behind
the baseline there, while both leads stay at 0.06 to 0.07 in California.
Kendall τ of the twelve-arm ranking with the 4 m ranking is 0.79 at 2 m on
five sites (0.73 in Washington, 0.91 in California). `multichm` depends most
on the radius: at rung 4 (2.5 pulses/m²) its lead falls from +0.045
[+0.020, +0.071] at 4 m to +0.026 [+0.000, +0.051] at 3 m and +0.016
[−0.007, +0.039] at 2 m, while ForestFormer3D, TreeisoNet and SegmentAnyTree
keep +0.041, +0.065 and +0.051 at 2 m. The grid covers rungs native, 8, 4, 2 and
1; the QL2 rung, run from its own root with `RUNGS=3.2`
(`paper_runs_ql2/sensitivity/matcher_*.csv`), gives the same picture:
`multichm`'s lead falls from +0.058 at 4 m to +0.043 at 3 m and +0.011 [−0.010,
+0.033] at 2 m, while ForestFormer3D, TreeisoNet and SegmentAnyTree keep +0.038,
+0.065 and +0.030 at 2 m.

## Chance agreement

Checked on 6 October 2026 on the same population and persisted detections.
`paper_sensitivity.R MODE=null` keeps each cell's detections and breaks their
relation to the stems: in each plot the detections within the core and its
matching margin are shifted together by a random offset, wrapped at the edges of
that square (a toroidal shift) and at least 8 m from no shift, and scored with
the greedy matcher. The same 200 offsets serve every arm and rung, so the null
is paired like the observed scores. A cell's null is its mean counts over the
200 shifts, pooled by summed counts on the same plots and resamples. The null is
the score of copies with no skill at placing trees, not an estimate of the
chance part of a score: subtracting it is conservative, because a detection that
makes a real match cannot also match by chance, so it tends to overstate the
chance part. Corrected F1 is (F1 − null F1) / (1 − null F1), the excess over the
null scaled by the headroom to a perfect score, as Cohen's kappa corrects
agreement for chance; if a share s of stems is found by skill and the rest can
match only by chance, recall = s + (1 − s) × null, so s = (recall − null) / (1 −
null). Against an incomplete reference a perfect score is not attainable, so
corrected F1 compares arms rather than measuring an attainable share. A
corrected lead is a difference of corrected F1 with a paired interval. `TOL=2`
repeats the null at a 2 m radius. The re-scored baseline reproduces every arm's
own result rows (4,664 cells). Native density, five sites:

| Arm | F1, 4 m | Null, 4 m | Corrected, 4 m | Corrected lead, 4 m | F1, 2 m | Null, 2 m | Corrected, 2 m | Corrected lead, 2 m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.495 | 0.345 | 0.229 [0.201, 0.255] | +0.034 [+0.008, +0.057] | 0.371 | 0.185 | 0.228 [0.204, 0.251] | +0.017 [−0.001, +0.033] |
| ForestFormer3D | 0.498 | 0.361 | 0.215 [0.191, 0.239] | +0.020 [−0.002, +0.041] | 0.357 | 0.181 | 0.214 [0.190, 0.239] | +0.003 [−0.014, +0.021] |
| CHM-VWF | 0.450 | 0.318 | 0.195 [0.169, 0.222] | — | 0.345 | 0.169 | 0.211 [0.186, 0.235] | — |
| Li 2012 | 0.456 | 0.325 | 0.195 [0.172, 0.217] | +0.000 [−0.015, +0.014] | 0.352 | 0.184 | 0.206 [0.183, 0.228] | −0.006 [−0.019, +0.008] |
| DeepForest | 0.454 | 0.328 | 0.188 [0.163, 0.212] | −0.007 [−0.028, +0.012] | 0.314 | 0.177 | 0.166 [0.143, 0.188] | −0.045 [−0.065, −0.025] |
| TreeisoNet | 0.446 | 0.322 | 0.183 [0.161, 0.205] | −0.011 [−0.029, +0.005] | 0.342 | 0.176 | 0.201 [0.178, 0.226] | −0.010 [−0.023, +0.002] |
| `multichm` | 0.456 | 0.338 | 0.178 [0.158, 0.202] | −0.017 [−0.039, +0.005] | 0.313 | 0.162 | 0.181 [0.161, 0.201] | −0.031 [−0.050, −0.012] |
| Detectree2 | 0.362 | 0.257 | 0.141 [0.118, 0.165] | −0.054 [−0.088, −0.021] | 0.220 | 0.117 | 0.116 [0.094, 0.139] | −0.095 [−0.122, −0.071] |
| `lmfauto` | 0.386 | 0.288 | 0.138 [0.115, 0.165] | −0.056 [−0.079, −0.034] | 0.310 | 0.179 | 0.159 [0.136, 0.185] | −0.052 [−0.073, −0.031] |
| `ptrees` | 0.331 | 0.257 | 0.099 [0.080, 0.124] | −0.095 [−0.123, −0.067] | 0.259 | 0.148 | 0.130 [0.112, 0.149] | −0.081 [−0.105, −0.057] |
| AMS3D | 0.240 | 0.190 | 0.063 [0.051, 0.075] | −0.132 [−0.159, −0.107] | 0.191 | 0.115 | 0.086 [0.074, 0.100] | −0.125 [−0.150, −0.102] |
| SAM2Point | 0.132 | 0.058 | 0.078 [0.062, 0.098] | −0.116 [−0.143, −0.089] | 0.077 | 0.021 | 0.057 [0.044, 0.072] | −0.154 [−0.176, −0.129] |

**Readings.**

- Randomly shifted copies reach 70 to 79% of every arm's native F1 at 4 m and 49
  to 60% at 2 m, SAM2Point aside (44% and 27%), pooled over the five sites; by
  region 52 to 66% in California and 75 to 84% in Washington, and on the
  decimated rungs 67 to 79% and 44 to 66%. The plot cores hold 1.21 stems per 50
  m² (a 4 m circle), and the arms place 0.8 (Detectree2) to 5.7 (AMS3D) core
  detections in the same area, so a detection usually has a stem within 4 m.
- Every match within 2 m is also a match within 4 m (no cell has more matches at
  2 m), yet the excess above the null grows from 4 to 2 m for ten of the eleven
  analysed arms (CHM-VWF 0.133 to 0.176), so the 4 m null over-subtracts. The
  corrected F1 of the two segmenters barely depends on the radius (0.229 and
  0.228 for SegmentAnyTree, 0.215 and 0.214 for ForestFormer3D at 4 and 2 m),
  but CHM-VWF's rises from 0.195 to 0.211 and the other arms' change by up to
  0.03, so the segmenters' corrected leads shrink at 2 m.
- Randomly shifted copies of the segmenters' detections already lead CHM-VWF by
  0.043 and 0.027. The number of detections is part of the reason (1.65 and 1.61
  per 50 m² against 1.19 for CHM-VWF), not all of it: Li 2012 places as many
  (1.66) and its null F1 is 0.325 against 0.361 for ForestFormer3D. Corrected,
  ForestFormer3D's lead is +0.020 at 4 m and +0.003 at 2 m and SegmentAnyTree's
  +0.034 and +0.017; the plain differences above the null are +0.005 and 0.000,
  +0.017 and +0.010. Only SegmentAnyTree's corrected lead at 4 m excludes zero,
  and only weakly (lower limit +0.008).
- By region (corrected leads, 4 m): ForestFormer3D +0.060 [+0.026, +0.094] and
  SegmentAnyTree +0.061 [+0.015, +0.103] in California, +0.004 [−0.026, +0.029]
  and +0.017 [−0.014, +0.042] in Washington, where Li 2012 is level with them
  (+0.017 [−0.002, +0.035]). The California minus Washington difference is
  +0.056 [+0.014, +0.099] and +0.044 [−0.007, +0.094] at 4 m and +0.067 [+0.035,
  +0.101] and +0.053 [+0.020, +0.089] at 2 m (scope "California minus
  Washington" in `*_leads.csv`). At 4 m the Washington estimate is carried by
  ABBY (−0.043 and −0.002; WREF +0.035 and +0.033). At rung 8 the contrast
  disappears: +0.041 and +0.036 in California, +0.040 [+0.010, +0.073] and
  +0.056 [+0.027, +0.083] in Washington, where CHM-VWF loses 0.07 F1 at its
  switch to the coarser canopy model.
- Below native density CHM-VWF's coarse, smoothed canopy model places 0.64 to
  0.72 detections per 50 m² (1.19 at native density) and so earns fewer chance
  matches. The observed leads of 0.05 to 0.07 that ForestFormer3D, TreeisoNet,
  `multichm` and AMS3D hold at rung 1 are −0.008 to +0.021 corrected, none
  excluding zero, and CHM-VWF's corrected F1 changes only from 0.195 to
  0.161–0.172 on the rungs. Corrected leads that exclude zero at 4 m are
  SegmentAnyTree's at native density and rungs 8 and 4 (+0.034, +0.053, +0.033)
  and ForestFormer3D's at rung 8 (+0.041); at 2 m, SegmentAnyTree's at rung 8
  (+0.036), TreeisoNet's at rungs 8 to 1 (+0.024 to +0.035, all but one weakly)
  and AMS3D's at rung 1 (+0.023). SegmentAnyTree's collapse is not chance: its
  corrected F1 falls from 0.229 to 0.150 at rung 2 and 0.047 at rung 1.
- At the QL2 rung (3.2 points/m², 2.0 pulses/m²), run from its own root with
  `RUNGS=3.2`, the observed leads of ForestFormer3D, SegmentAnyTree, TreeisoNet
  and `multichm` (0.057 to 0.060) are +0.014, +0.017, +0.016 and +0.001
  corrected at 4 m, none excluding zero, and +0.008, −0.005, +0.024 [+0.004,
  +0.042] and −0.023 [−0.044, −0.001] at 2 m. The null reaches 69 to 77% of each
  arm's F1 there at 4 m and 44 to 64% at 2 m
  (`paper_runs_ql2/sensitivity/null_*.csv`).
- Understory recall is the most exposed score: the null reaches 79 to 97% of
  each arm's understory recall at 4 m (SAM2Point aside), against 68 to 80% of
  overstory recall. Above the null, AMS3D and ForestFormer3D recall 0.094 of
  understory stems at 4 m (0.153 and 0.108 at 2 m), SegmentAnyTree 0.061,
  `multichm` 0.040 and CHM-VWF 0.016 [−0.012, +0.050] (0.042 [+0.015, +0.071] at
  2 m); the larger excess at 2 m shows that the 4 m subtraction also removes
  real matches. ForestFormer3D's understory recall lead over CHM-VWF above the
  null is +0.078 [+0.037, +0.119] at 4 m.

`null_*.csv` (4 m) and `null_tol2_*.csv` (2 m) in `paper_runs/sensitivity` hold
every arm, rung, scope and stratum: pooled observed and null scores, observed
minus null and corrected F1 (`*_delta.csv`), and the leads over CHM-VWF
observed, under the null, above it and corrected (`*_leads.csv`), with the
California minus Washington difference. The same files for the QL2 rung are in
`paper_runs_ql2/sensitivity`. The null covers the nominal box only.

`paper_runs/sensitivity/matcher_*.csv` holds every rung, scope and grid cell.
The sections below are the historical June 2026 study of CHM-VWF on the
three-site population.

## Historical study (June 2026)

The whole benchmark grades detections with `greedy_match`: a greedy
nearest-distance 1:1 assignment within a **flat** 4 m radius, gated by a hard
height band `bz in [0.5*az, az + 8]`. Two known weaknesses motivate this arm:
(1) the apex↔stem-base horizontal offset grows with height, crown size, lean,
and slope (SOAP/TEAK are steep), so a flat 4 m is too tight for tall dominants
and too loose for dense understory; (2) greedy-by-distance is globally
suboptimal in dense clusters. This re-scores the CHM-VWF detector on the **same**
frozen clips with hardened matchers and reports whether any pooled rate moves.

The matchers are added to [`sweep_lib.R`](../scripts/sweep_lib.R) and unit-tested
(`tests/testthat/test-matcher-robustness.R`):

- `match_tol()` — per-stem `tol_i = max(base_tol, k·maxCrownDiameter/2, pos_unc)`
  (both fields already carried in `ground_truth_stems.csv`); the flat-4 m path is
  the back-compat default.
- `optimal_match()` — optimal 1:1 assignment (Hungarian, `clue::solve_LSAP`) on
  a finite-sentinel-gated cost matrix with dummy padding for non-square sets and
  unmatched stems; a drop-in for `greedy_match`.
- a soft scaled-3D cost `d = sqrt(dxy² + (λ·dz)²)` that replaces the hard height
  band, gated by a 3-D radius (`d ≤ tol`, so it still rejects height-impossible
  pairs), threaded through `optimal_match`/`score_plot`.
- `fp_structure()` — splits core false positives into *near a matched stem*
  (over-segmentation) vs *isolated* (real understory / field-map gap).

Regenerate:

```sh
export CLAUDE_JOB_DIR=$(pwd)/work
# CORES=1: detect_lasr uses lasR exec, which can drop dense-native cells under fork
Rscript scripts/matcher_robustness.R SITES=SOAP,SJER,TEAK CORES=1
# -> work/neon/<SITE>/matcher_robustness.csv (one row per plot x rung x config)
```

## What this is

For each plot the CHM-VWF detector is regenerated **deterministically** from the
cached frozen normalized clip (`detect_lasr` at the canonical density-derived
`chm_res`, `vwf_a = 0.10`), so every matcher scores identical apexes. Native
density, three sites, 699 pooled field stems. Pooled with the canonical `pool()`
(sum counts, never average rates). The baseline row reproduces the benchmark's
CHM-VWF native recall/F1 (0.40/0.37 pooled), confirming the harness is unchanged.

## Generated tables

### Matcher configs, all sites combined (pooled by SUM)

`hRMSE` = TP-weighted pooled apex-height RMSE over matched pairs — a matcher that
"recovers" matches by admitting height-implausible pairs inflates it.

| config | recall | precision | F1 | ΔF1 | hRMSE (m) | rec_understory |
|---|--:|--:|--:|--:|--:|--:|
| baseline | 0.401 | 0.336 | 0.365 | +0.000 | 3.17 | 0.200 |
| scaled | 0.411 | 0.343 | 0.374 | +0.009 | 3.20 | 0.200 |
| optimal | 0.413 | 0.342 | 0.374 | +0.009 | 3.17 | 0.200 |
| **optimal_scaled** | **0.425** | **0.351** | **0.385** | **+0.019** | 3.20 | 0.200 |
| soft3d | 0.382 | 0.318 | 0.347 | −0.018 | **2.35** | 0.162 |

### Per site: ΔF1 vs baseline (optimal_scaled and soft3d)

| site | n_ref | base F1 | optimal_scaled ΔF1 | soft3d ΔF1 | soft3d hRMSE | base hRMSE |
|---|--:|--:|--:|--:|--:|--:|
| SOAP | 232 | 0.382 | +0.028 | −0.036 | 2.34 | 3.30 |
| SJER | 71 | 0.319 | +0.019 | +0.009 | 1.91 | 2.04 |
| TEAK | 396 | 0.367 | +0.013 | −0.012 | 2.47 | 3.29 |

### tol_xy × tol_z_up sensitivity, combined (greedy F1)

| tol_xy | tz=5 | tz=8 | tz=12 |
|--:|--:|--:|--:|
| 2 | 0.214 | 0.227 | 0.247 |
| 3 | 0.288 | 0.308 | 0.330 |
| 4 | 0.337 | 0.365 | 0.384 |
| 5 | 0.373 | 0.399 | 0.418 |

### False-positive error structure (baseline, core FPs, combined)

near-a-matched-stem (over-segmentation) = **29 (5.7 %)**; isolated (real
understory / field-map gap) = **478 (94.3 %)**.

| class (nearest stem) | near (over-seg) | isolated |
|---|--:|--:|
| dominant | 12 | 171 |
| codominant | 16 | 214 |
| intermediate | 1 | 30 |
| suppressed | 0 | 0 |

## Readings

- **Modest but consistent gains — close to the "greedy is adequate" the issue
  anticipated.** The best principled variant is **optimal_scaled** (Hungarian
  optimal assignment + per-stem size/uncertainty-scaled tolerance): +0.019 F1
  pooled, and it is the only variant positive at every site (+0.028 SOAP, +0.019
  SJER, +0.013 TEAK) with no height-RMSE cost (3.20 vs 3.17 m). Scaled tolerance
  and optimal assignment each contribute ~+0.009 F1 and compose to +0.019. None
  of the increments is dramatic: the flat-4 m greedy baseline is already close to
  adequate, and the hardened matcher is worth adopting for the steady gain and
  the dropped magic numbers, not for a step change.
- **The soft 3-D cost buys height fidelity, not recall.** Replacing the hard
  `[0.5·az, az+8]` band with `sqrt(dxy² + (λ·dz)²)` gated by a 3-D radius
  (`d3 ≤ tol`, which still rejects height-impossible pairs — capping |dz| at
  tol/λ) slightly *lowers* recall/F1 (−0.018) but gives the **best matched-pair
  height RMSE of any variant, 2.35 m vs the baseline's 3.17 m**. It declines the
  marginal, height-implausible matches the hard band let through, trading a hair
  of recall for cleaner geometry — useful where matched-apex height quality
  matters (e.g. feeding the stem-jitter error bars), not as a recall booster.
  (An earlier revision of this arm reported soft3d as a large F1 winner; that was
  a bug — the soft path had dropped the height gate entirely and was scoring
  height-impossible matches as true positives, which a self-review caught.
  The 3-D-radius gate is the fix.)
- **The flat-4 m / gate-8 baseline sits on a rising slope.** F1 climbs
  monotonically across the whole tol_xy {2→5} × tol_z_up {5→12} grid, so the
  benchmark's defaults are on the tight side. The principled fix is the per-stem
  scaled tolerance (loosen for big crowns, not globally, and capped at 12 m so a
  corrupt field record — SOAP carries a 344 m `maxCrownDiameter` — cannot blow up
  the radius), since a globally larger flat radius would eventually inflate true
  positives with spurious matches.
- **Low precision is a ground-truth coverage gap, not over-segmentation.**
  94.3 % of core false positives are *isolated* (no matched stem within 4 m);
  only 5.7 % sit beside a matched tree. The benchmark's modest precision is
  dominated by detections of real-but-unmapped trees (regeneration, unmeasured
  neighbours), not by the detector splitting one crown into many. This is the
  signal the router and fusion studies need: isolated detections should be
  treated as probably-real, not suppressed as commission.

## Caveats

- **Scoring is apex-proximity**, which the IoU/PQ study shows overstates
  instance quality for the mask-capable arms; for
  SegmentAnyTree/ForestFormer3D prefer the point-set IoU/PQ scorer
  (`results/instance-iou-pq-results.md`).
  This arm hardens the proximity matcher the CHM/apex detectors still rely on,
  and the same `match_tol`/height-gate logic feeds the fusion dedup.
- **The per-class FP attribution is by nearest stem**, so it locates each false
  positive in a crown-class neighbourhood rather than labelling the (unmapped)
  detection itself; the near/isolated split is the primary signal.
- **Native density only**; the driver accepts a `RUNGS=` list and extends to the
  sparse ladder once those detections are wanted. Soft-3D `λ` defaults to 0.5
  (tunable via `LAMBDA=`), and the scaled tolerance is capped at 12 m
  (`TOL_CAP=`); the sensitivity grid above uses the greedy hard-gate path.
