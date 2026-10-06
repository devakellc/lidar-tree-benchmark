# Supplementary material

Supplement to the draft manuscript [Native-density performance does not
guarantee sparse-density performance](manuscript.md). Each section names the
study report its numbers come from. Density is median first-return pulse density
over the 106 plots: 9.8 pulses/m² at native density and 4.7, 2.5, 2.0, 1.3 and
0.6 pulses/m² on the decimated rungs.

## S1. Recall by crown class

Native density, five sites, nominal plot core, with 95% plot-bootstrap
intervals: 1,872 overstory stems (dominant and codominant) and 592 understory
stems (intermediate and suppressed), 404 of the latter at WREF. Detections carry
no crown class, so the strata have recall only. Source: [master
tables](../results/master-tables-results.md).

**Table S1.** Recall by crown class at native density.

| Detector | Overstory | Understory |
| --- | --- | --- |
| AMS3D | 0.735 [0.686, 0.777] | 0.627 [0.560, 0.701] |
| `ptrees` | 0.786 [0.746, 0.827] | 0.459 [0.365, 0.555] |
| ForestFormer3D | 0.674 [0.645, 0.704] | 0.454 [0.387, 0.522] |
| `multichm` | 0.599 [0.568, 0.632] | 0.340 [0.291, 0.396] |
| SegmentAnyTree | 0.698 [0.657, 0.739] | 0.291 [0.218, 0.364] |
| DeepForest (RGB) | 0.630 [0.594, 0.667] | 0.262 [0.206, 0.323] |
| Li 2012 | 0.663 [0.617, 0.710] | 0.228 [0.159, 0.298] |
| `lmfauto` | 0.658 [0.605, 0.708] | 0.225 [0.149, 0.300] |
| TreeisoNet | 0.606 [0.562, 0.650] | 0.193 [0.131, 0.256] |
| CHM-VWF | 0.554 [0.511, 0.601] | 0.171 [0.118, 0.226] |
| Detectree2 (RGB) | 0.365 [0.325, 0.403] | 0.123 [0.089, 0.162] |

## S2. Accuracy by site

Source: [model comparison](../results/model-benchmark-results.md). Intervals are
in the archived master tables; SJER has six plots and wide intervals (0.169 to
0.471 for CHM-VWF).

**Table S2.** Native-density F1 by site, nominal plot core.

| Detector | SJER | SOAP | TEAK | WREF | ABBY |
| --- | --- | --- | --- | --- | --- |
| ForestFormer3D | 0.325 | 0.454 | 0.495 | 0.491 | 0.542 |
| SegmentAnyTree | 0.274 | 0.469 | 0.517 | 0.463 | 0.559 |
| `multichm` | 0.342 | 0.437 | 0.449 | 0.452 | 0.489 |
| Li 2012 | 0.257 | 0.356 | 0.393 | 0.432 | 0.557 |
| DeepForest (RGB) | 0.261 | 0.451 | 0.461 | 0.423 | 0.510 |
| CHM-VWF | 0.307 | 0.382 | 0.388 | 0.392 | 0.557 |
| TreeisoNet | 0.280 | 0.390 | 0.373 | 0.393 | 0.571 |
| `lmfauto` | 0.301 | 0.337 | 0.373 | 0.425 | 0.384 |
| Detectree2 (RGB) | 0.250 | 0.405 | 0.337 | 0.314 | 0.426 |
| `ptrees` | 0.164 | 0.259 | 0.305 | 0.302 | 0.446 |
| AMS3D | 0.100 | 0.190 | 0.342 | 0.258 | 0.244 |

DeepForest's SJER and TEAK scores are not zero-shot: its training annotations
include imagery of those two sites.

## S3. Sensitivity populations

Every detector was also scored on a population without the 10 cm DBH floor (116
plots, 2,854 stems) and on one without the six-tree plot rule (149 plots, 2,628
stems). Source: [master tables](../results/master-tables-results.md).

**Table S3.** Paired F1 difference from CHM-VWF at native density under the
three populations.

| Population | ForestFormer3D | SegmentAnyTree | TreeisoNet | `multichm` | Li 2012 |
| --- | --- | --- | --- | --- | --- |
| Headline | +0.048 [+0.028, +0.069] | +0.044 [+0.021, +0.067] | −0.004 [−0.018, +0.009] | +0.005 [−0.018, +0.028] | +0.006 [−0.009, +0.019] |
| No DBH floor | +0.038 [+0.015, +0.060] | +0.035 [+0.009, +0.059] | −0.008 [−0.025, +0.009] | −0.003 [−0.026, +0.019] | +0.011 [−0.005, +0.029] |
| No six-tree rule | +0.033 [+0.009, +0.054] | — | −0.013 [−0.027, −0.001] | −0.001 [−0.022, +0.019] | −0.007 [−0.019, +0.005] |

SegmentAnyTree has no row for the third population because its inference fails
on one sparse clip there, which is left missing and not scored as empty. At 0.6
pulses/m², `multichm` leads CHM-VWF by +0.060, +0.067 and +0.031 under the three
populations, and AMS3D by +0.063, +0.048 and +0.045, all with intervals that
exclude zero. These are observed leads; corrected for chance in the headline
population they are −0.008 [−0.031, +0.011] for `multichm` and +0.020 [−0.006,
+0.045] for AMS3D (Table 4 of the manuscript), and the null was not computed for
the sensitivity populations.

## S4. Censused subplots

Source: [censused-subplot study](../results/census-support-results.md).

**Table S4.** Plots admitted to censused-subplot scoring, tower / distributed in
brackets.

| Site | Plots | Nearest census within four years | Stems in those plots | Exact 2021 census | Stems |
| --- | ---: | --- | ---: | ---: | ---: |
| SJER | 6 | 2 (2 / 0) | 31 | 0 | 0 |
| SOAP | 18 | 1 (1 / 0) | 16 | 0 | 0 |
| TEAK | 19 | 9 (2 / 7) | 149 | 2 | 48 |
| WREF | 38 | 28 (18 / 10) | 842 | 4 | 174 |
| ABBY | 25 | 17 (10 / 7) | 569 | 10 | 458 |
| All | 106 | 57 (33 / 24) | 1,607 | 16 | 680 |

The admitted censuses lie between one year before and three years after the
flights. The exact 2021 check gives the same direction as the headline rule:
native precision of 0.79 against 0.44 in the nominal plot core for CHM-VWF, 0.77
against 0.44 for SegmentAnyTree and 0.75 against 0.42 for ForestFormer3D. The
stricter exclusion rule admits 54 plots and gives native precision about 0.01
below the headline rule for every detector.

## S5. Co-detection credit

An isolated false positive is credited when detectors from at least two other
families leave an isolated false positive within 2 m. Each detector is scored at
its best tested density per site, so the raw values differ from the
native-density table of the manuscript. Source: [coverage-gap
study](../results/coverage-gap-results.md).

**Table S5.** Raw and credited scores, five sites pooled.

| Detector | Recall | Precision | F1 | Credited precision | Credited F1 | Gain |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.590 | 0.438 | 0.503 | 0.648 | 0.618 | +0.115 |
| ForestFormer3D | 0.616 | 0.416 | 0.497 | 0.609 | 0.613 | +0.116 |
| Li 2012 | 0.561 | 0.384 | 0.456 | 0.641 | 0.598 | +0.142 |
| CHM-VWF | 0.492 | 0.458 | 0.474 | 0.763 | 0.598 | +0.124 |
| TreeisoNet | 0.521 | 0.420 | 0.465 | 0.694 | 0.595 | +0.130 |
| DeepForest (RGB) | 0.545 | 0.390 | 0.454 | 0.611 | 0.576 | +0.122 |
| `multichm` | 0.546 | 0.393 | 0.457 | 0.599 | 0.571 | +0.114 |
| AMS3D | 0.590 | 0.392 | 0.471 | 0.548 | 0.568 | +0.097 |
| `ptrees` | 0.539 | 0.384 | 0.448 | 0.598 | 0.567 | +0.119 |
| `lmfauto` | 0.604 | 0.295 | 0.396 | 0.431 | 0.503 | +0.107 |
| Detectree2 (RGB) | 0.309 | 0.435 | 0.362 | 0.688 | 0.427 | +0.065 |

CHM-VWF's row pools 104 plots and 2,496 stems, because two TEAK plots lack its
selected configuration; every other row pools 106 plots and 2,525 stems. Across
radii of 1.5 to 3 m and one or two witnessing families, the pooled gain is
+0.106 to +0.135.

## S6. Detector fusion

Detections of eight LiDAR detectors and DeepForest were clustered across
detectors and kept by union, by majority and by agreement of at least k
detectors. The value of k is chosen on the same plots, so the gains are in
sample. Source: [fusion study](../results/detector-fusion-results.md).

**Table S6.** F1 of fused modes against the best single detector, 106 plots per
density.

| Pulses/m² | Best single detector | Union | Majority | Best agreement rule | Difference |
| --- | --- | ---: | ---: | --- | ---: |
| 9.8 | ForestFormer3D 0.498 | 0.321 | 0.472 | k = 3, 0.489 | −0.009 |
| 4.7 | ForestFormer3D 0.487 | 0.392 | 0.462 | k = 2, 0.496 | +0.009 |
| 2.5 | SegmentAnyTree 0.469 | 0.427 | 0.450 | k = 2, 0.490 | +0.021 |
| 1.3 | AMS3D 0.459 | 0.434 | 0.426 | k = 2, 0.481 | +0.022 |
| 0.6 | DeepForest (RGB) 0.454 | 0.446 | 0.359 | k = 2, 0.473 | +0.019 |

The fusion study did not include the rung at 2.0 pulses/m². The union raises
recall to 0.85 at native density at a precision of 0.20. At 0.6 pulses/m² the
best single detector is the RGB one, whose accuracy does not depend on point
density.

## S7. Crown delineation

Crown diameters from every segmenter, among them a random walker
[@grady2006random] and the methods of @dalponte2016treecentric and
@silva2016imputation, were compared with NEON field crown diameters on the plots
with at least six such stems. The equivalent-circle diameter is compared with
the field ninety-degree diameter and the widest axis with the field maximum
diameter. Source: [crown benchmark](../results/crown-segmentation-results.md).

**Table S7.** Crown diameter error at native density on the 790 stems matched by
every listed segmenter.

| Segmenter | Equivalent diameter RMSE (m) | Bias (m) | Widest axis RMSE (m) | Bias (m) |
| --- | ---: | ---: | ---: | ---: |
| Random walker with a stop rule | 1.71 | +0.46 | 2.83 | +1.67 |
| SegmentAnyTree | 1.74 | +0.37 | 2.38 | +0.88 |
| lasR region growing | 1.87 | +0.80 | 2.95 | +1.90 |
| Dalponte 2016 | 1.90 | +0.84 | 3.49 | +2.36 |
| ForestFormer3D | 1.92 | +0.82 | 2.56 | +1.18 |
| Silva 2016 | 2.01 | +0.93 | 3.45 | +2.45 |
| `ptrees` | 2.28 | +0.02 | 3.00 | +0.76 |
| AMS3D | 3.11 | +0.27 | 3.91 | +0.86 |
| Li 2012 | 3.70 | +2.07 | 5.48 | +3.70 |

For the stop-rule random walker the equivalent-diameter RMSE is 1.76 m at native
density, 1.65 to 1.76 m down to 1.3 pulses/m² and 1.91 m at 0.6 pulses/m²: crown
width tolerates sparser data than stem detection does.

## S8. Mask scores on NEON and the proxy reference

NEON has no per-point tree labels. Mask scores use a proxy reference in which
each canopy point is assigned to the nearest mapped stem within that stem's
field crown radius. Source: [instance IoU
study](../results/instance-iou-pq-results.md).

**Table S8.** Mask scores against the proxy at native density, five sites, IoU
threshold 0.5.

| Detector | Precision | Recall | F1 | Panoptic quality |
| --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.119 | 0.211 | 0.152 | 0.098 |
| ForestFormer3D | 0.104 | 0.192 | 0.135 | 0.087 |
| Li 2012 | 0.099 | 0.185 | 0.129 | 0.083 |
| `ptrees` | 0.055 | 0.208 | 0.087 | 0.056 |
| AMS3D | 0.035 | 0.183 | 0.058 | 0.038 |
| TreeisoNet | 0.026 | 0.020 | 0.023 | 0.015 |

TreeisoNet's masks are reported at its checkpoint voxel, the setting fixed
before the runs; at the coarser voxel of its apex pass its mask F1 is 0.138, a
sensitivity computed after the results were seen. Kendall's τ between the apex
ranking and the mask ranking of the six detectors is 0.60.

The proxy was validated on FGI-EMIT, where true labels exist, by building it
from the true trees ([proxy
validation](../results/fgiemit-proxy-validation-results.md)). Scored as if it
were a prediction, the proxy reaches a mask F1 of 0.60 against the truth with
measured crown radii and 0.44 with the 2 m fallback radius used when a field
width is missing; its median tree IoU is 0.74 for free-standing trees and 0.17
for trees beneath a taller neighbour. On the ten development plots, against the
proxy, ForestFormer3D's mask F1 falls from 0.72 to 0.49 (−0.230 [−0.292,
−0.161]) and SegmentAnyTree's from 0.62 to 0.47 (−0.147 [−0.195, −0.097]). The
proxy keeps the order of the two models and compresses their difference from
0.10 to 0.02. NEON mask scores are therefore a ranking, not a measure of mask
quality.

## S9. Calibration and validation of the baseline

The baseline's canopy-model resolution (0.25, 0.5 or 1.0 m) and window slope
(0.05, 0.10 or 0.15) were tuned on a stratified half of each site's plots and
scored on the other half, over ten seeds. Source: [calibration/validation
study](../results/calibration-validation-results.md).

**Table S9.** Held-out F1 after tuning, median and range over ten seeds, with
the share of seeds that selected 0.5 m.

| Site | 9.8 pulses/m² | 0.5 m chosen | 4.7 pulses/m² | 0.5 m chosen | 0.6 pulses/m² | 0.5 m chosen |
| --- | --- | --- | --- | --- | --- | --- |
| SJER | 0.301 [0.182, 0.444] | 3 / 10 | 0.349 [0.185, 0.430] | 2 / 10 | 0.357 [0.203, 0.413] | 3 / 10 |
| SOAP | 0.392 [0.335, 0.417] | 8 / 10 | 0.377 [0.338, 0.406] | 10 / 10 | 0.402 [0.348, 0.437] | 9 / 10 |
| TEAK | 0.422 [0.358, 0.476] | 4 / 10 | 0.393 [0.354, 0.421] | 10 / 10 | 0.397 [0.364, 0.434] | 10 / 10 |
| WREF | 0.403 [0.365, 0.447] | 6 / 10 | 0.357 [0.343, 0.398] | 10 / 10 | 0.342 [0.324, 0.369] | 10 / 10 |
| ABBY | 0.549 [0.472, 0.578] | 6 / 10 | 0.486 [0.452, 0.508] | 10 / 10 | 0.431 [0.412, 0.448] | 10 / 10 |

Held-out F1 after tuning is within a few hundredths of the fixed configuration's
F1 on all of a site's plots (for example 0.549 against 0.557 at ABBY at native
density). The paper does not tune the baseline; the regional split of the
manuscript is its held-out test.

## S10. Arm not analysed and historical studies

A promptable refiner, SAM2Point [@guo2024sam2point], built on SAM 2
[@ravi2024sam] and seeded with up to 40 CHM-VWF tops per plot scored F1 0.132 at
native density, against 0.405 for its own seeds on the same plots. It keeps 81%
of its seeds as trees in plots with up to 15 prompts and 20% in plots with 31 to
40, because early masks absorb their neighbours' points. It is reported in the
[master tables](../results/master-tables-results.md) and not analysed further.

Per-detection confidence calibration, per-cell routing between detectors and the
paired fusion of RGB and LiDAR detections were studied on the earlier three-site
population only and found small effects. Their reports are marked historical and
are not part of the paper's evidence.

## S11. Configuration provenance

The [configuration provenance record](../docs/configuration-provenance.md) lists
every tunable setting of every detector, the data it was chosen on and the
commit that fixed it, against the time the Washington sites were first scored.
The [detector table](../results/detector-table.md) gives checkpoint hashes,
image identifiers and licences.

## S12. Chance agreement

The null shifts each plot's detections within the core and its matching margin
by each of 200 random offsets, the same for every detector and density, and
scores the mean counts over the 200 shifts like the observed detections (Section
4.2 of the manuscript). It is the score of copies with no skill at placing trees
and tends to overstate the chance part of a score. Corrected F1 is (F1 − null
F1) / (1 − null F1); a corrected lead is a difference of corrected F1 with a
paired 95% interval. The rung at the QL2 floor (2.0 pulses/m²) was scored from
its own root with the same offsets and resamples. Source: [matcher-robustness
study](../results/matcher-robustness-results.md).

**Table S12a.** Native density, five sites: observed and null F1 at radii of 4
and 2 m, corrected F1, and at 4 m the plain difference above the null.

| Detector | F1, 4 m | Null F1, 4 m | Corrected F1, 4 m | F1 − null F1, 4 m | F1, 2 m | Null F1, 2 m | Corrected F1, 2 m |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.495 | 0.345 | 0.229 [0.201, 0.255] | 0.150 [0.131, 0.168] | 0.371 | 0.185 | 0.228 [0.204, 0.251] |
| ForestFormer3D | 0.498 | 0.361 | 0.215 [0.191, 0.239] | 0.138 [0.121, 0.154] | 0.357 | 0.181 | 0.214 [0.190, 0.239] |
| CHM-VWF | 0.450 | 0.318 | 0.195 [0.169, 0.222] | 0.133 [0.114, 0.154] | 0.345 | 0.169 | 0.211 [0.186, 0.235] |
| Li 2012 | 0.456 | 0.325 | 0.195 [0.172, 0.217] | 0.132 [0.115, 0.149] | 0.352 | 0.184 | 0.206 [0.183, 0.228] |
| DeepForest (RGB) | 0.454 | 0.328 | 0.188 [0.163, 0.212] | 0.126 [0.109, 0.143] | 0.314 | 0.177 | 0.166 [0.143, 0.188] |
| TreeisoNet | 0.446 | 0.322 | 0.183 [0.161, 0.205] | 0.124 [0.108, 0.141] | 0.342 | 0.176 | 0.201 [0.178, 0.226] |
| `multichm` | 0.456 | 0.338 | 0.178 [0.158, 0.202] | 0.118 [0.104, 0.134] | 0.313 | 0.162 | 0.181 [0.161, 0.201] |
| Detectree2 (RGB) | 0.362 | 0.257 | 0.141 [0.118, 0.165] | 0.105 [0.088, 0.122] | 0.220 | 0.117 | 0.116 [0.094, 0.139] |
| `lmfauto` | 0.386 | 0.288 | 0.138 [0.115, 0.165] | 0.099 [0.082, 0.117] | 0.310 | 0.179 | 0.159 [0.136, 0.185] |
| `ptrees` | 0.331 | 0.257 | 0.099 [0.080, 0.124] | 0.074 [0.060, 0.091] | 0.259 | 0.148 | 0.130 [0.112, 0.149] |
| AMS3D | 0.240 | 0.190 | 0.063 [0.051, 0.075] | 0.051 [0.042, 0.060] | 0.191 | 0.115 | 0.086 [0.074, 0.100] |

**Table S12b.** Corrected F1 by density at 4 m, five sites. Columns give the
median first-return density in pulses/m²; 2.0 is the rung at the QL2 floor.

| Detector | 9.8 | 4.7 | 2.5 | 2.0 | 1.3 | 0.6 |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.229 | 0.222 | 0.205 | 0.185 | 0.150 | 0.047 |
| ForestFormer3D | 0.215 | 0.211 | 0.183 | 0.182 | 0.177 | 0.164 |
| CHM-VWF | 0.195 | 0.170 | 0.172 | 0.168 | 0.161 | 0.164 |
| TreeisoNet | 0.183 | 0.188 | 0.188 | 0.184 | 0.180 | 0.185 |
| `multichm` | 0.178 | 0.171 | 0.158 | 0.169 | 0.162 | 0.156 |
| `lmfauto` | 0.138 | 0.112 | 0.084 | 0.080 | 0.072 | 0.073 |
| `ptrees` | 0.099 | 0.182 | 0.166 | 0.169 | 0.154 | 0.103 |
| AMS3D | 0.063 | 0.091 | 0.134 | 0.147 | 0.183 | 0.184 |

**Table S12c.** Corrected lead over CHM-VWF by density and radius, five sites;
2.0 is the rung at the QL2 floor.

| Detector | Radius | 9.8 | 4.7 | 2.5 | 2.0 | 1.3 | 0.6 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 4 m | +0.034 [+0.008, +0.057] | +0.053 [+0.026, +0.080] | +0.033 [+0.005, +0.060] | +0.017 [−0.008, +0.041] | −0.011 [−0.039, +0.018] | −0.117 [−0.139, −0.097] |
| SegmentAnyTree | 2 m | +0.017 [−0.001, +0.033] | +0.036 [+0.014, +0.059] | +0.019 [−0.010, +0.045] | −0.005 [−0.027, +0.018] | −0.014 [−0.038, +0.009] | −0.111 [−0.134, −0.090] |
| ForestFormer3D | 4 m | +0.020 [−0.002, +0.041] | +0.041 [+0.014, +0.069] | +0.011 [−0.014, +0.037] | +0.014 [−0.012, +0.040] | +0.016 [−0.010, +0.041] | +0.000 [−0.024, +0.022] |
| ForestFormer3D | 2 m | +0.003 [−0.014, +0.021] | +0.020 [−0.003, +0.042] | +0.013 [−0.011, +0.036] | +0.008 [−0.012, +0.028] | +0.000 [−0.021, +0.019] | +0.001 [−0.022, +0.022] |
| TreeisoNet | 4 m | −0.011 [−0.029, +0.005] | +0.018 [−0.004, +0.041] | +0.016 [−0.003, +0.039] | +0.016 [−0.006, +0.039] | +0.020 [−0.001, +0.043] | +0.021 [−0.005, +0.046] |
| TreeisoNet | 2 m | −0.010 [−0.023, +0.002] | +0.024 [+0.006, +0.043] | +0.027 [+0.008, +0.044] | +0.024 [+0.004, +0.042] | +0.035 [+0.015, +0.053] | +0.024 [+0.002, +0.042] |
| `multichm` | 4 m | −0.017 [−0.039, +0.005] | +0.001 [−0.025, +0.027] | −0.013 [−0.037, +0.010] | +0.001 [−0.025, +0.030] | +0.001 [−0.023, +0.026] | −0.008 [−0.031, +0.011] |
| `multichm` | 2 m | −0.031 [−0.050, −0.012] | −0.012 [−0.033, +0.008] | −0.012 [−0.036, +0.010] | −0.023 [−0.044, −0.001] | −0.006 [−0.026, +0.014] | −0.009 [−0.028, +0.008] |
| AMS3D | 4 m | −0.132 [−0.159, −0.107] | −0.079 [−0.107, −0.052] | −0.037 [−0.067, −0.009] | −0.022 [−0.048, +0.005] | +0.022 [−0.010, +0.052] | +0.020 [−0.006, +0.045] |
| AMS3D | 2 m | −0.125 [−0.150, −0.102] | −0.068 [−0.093, −0.044] | −0.028 [−0.054, −0.001] | −0.010 [−0.034, +0.013] | +0.014 [−0.011, +0.036] | +0.023 [+0.003, +0.044] |
| `ptrees` | 4 m | −0.095 [−0.123, −0.067] | +0.012 [−0.014, +0.037] | −0.006 [−0.030, +0.019] | +0.000 [−0.022, +0.022] | −0.007 [−0.026, +0.011] | −0.061 [−0.083, −0.040] |
| `ptrees` | 2 m | −0.081 [−0.105, −0.057] | +0.004 [−0.017, +0.024] | +0.001 [−0.019, +0.020] | +0.002 [−0.021, +0.023] | −0.008 [−0.028, +0.013] | −0.056 [−0.073, −0.040] |
| `lmfauto` | 4 m | −0.056 [−0.079, −0.034] | −0.057 [−0.085, −0.027] | −0.088 [−0.115, −0.061] | −0.088 [−0.113, −0.061] | −0.088 [−0.113, −0.061] | −0.091 [−0.116, −0.068] |
| `lmfauto` | 2 m | −0.052 [−0.073, −0.031] | −0.049 [−0.075, −0.022] | −0.074 [−0.104, −0.046] | −0.081 [−0.102, −0.055] | −0.073 [−0.098, −0.047] | −0.065 [−0.087, −0.044] |

At native density the null reproduces 70 to 79% of each detector's F1 at 4 m,
pooled over the five sites (52 to 66% in California and 75 to 84% in
Washington), and 79 to 97% of its understory recall and 68 to 80% of its
overstory recall. Understory recall above the null is 0.094 for AMS3D and
ForestFormer3D, 0.061 for SegmentAnyTree, 0.047 for `ptrees`, 0.040 for
`multichm` and 0.016 [−0.012, 0.050] for CHM-VWF at 4 m, and 0.153, 0.108,
0.064, 0.090, 0.042 and 0.042 at 2 m.

**Table S12d.** Corrected lead over CHM-VWF by region at 4 m, at native density
and at 4.7 pulses/m², with the California minus Washington difference.

| Detector | Pulses/m² | California | Washington | Difference |
| --- | --- | --- | --- | --- |
| ForestFormer3D | 9.8 | +0.060 [+0.026, +0.094] | +0.004 [−0.026, +0.029] | +0.056 [+0.014, +0.099] |
| ForestFormer3D | 4.7 | +0.041 [−0.016, +0.091] | +0.040 [+0.010, +0.073] | +0.001 [−0.060, +0.060] |
| SegmentAnyTree | 9.8 | +0.061 [+0.015, +0.103] | +0.017 [−0.014, +0.042] | +0.044 [−0.007, +0.094] |
| SegmentAnyTree | 4.7 | +0.036 [−0.025, +0.090] | +0.056 [+0.027, +0.083] | −0.020 [−0.088, +0.036] |
| TreeisoNet | 9.8 | −0.017 [−0.044, +0.008] | −0.008 [−0.032, +0.013] | −0.009 [−0.042, +0.025] |
| TreeisoNet | 4.7 | −0.019 [−0.067, +0.028] | +0.034 [+0.010, +0.058] | −0.052 [−0.106, −0.000] |

At native density the Washington estimates are carried by ABBY (ForestFormer3D
−0.043 [−0.092, +0.004], SegmentAnyTree −0.002 [−0.054, +0.038]); at WREF they
are +0.035 [−0.000, +0.066] and +0.033 [−0.005, +0.067].

## S13. Rank stability with detectors left out

Spearman correlation between the native-density ranking and the ranking at each
rung, recomputed on every bootstrap draw with the named detectors removed,
nominal plot core, five sites. The pair SegmentAnyTree and AMS3D was chosen
after seeing the results. Source: [master
tables](../results/master-tables-results.md).

**Table S13.** Rank correlation with native density, with 95% intervals. Columns
give the median first-return density in pulses/m².

| Left out | 4.7 | 2.5 | 2.0 | 1.3 | 0.6 |
| --- | --- | --- | --- | --- | --- |
| None (eight detectors) | 0.83 [0.69, 0.93] | 0.76 [0.55, 0.88] | 0.71 [0.38, 0.81] | −0.05 [−0.17, 0.26] | −0.19 [−0.36, 0.14] |
| CHM-VWF | 0.93 [0.75, 0.96] | 0.82 [0.71, 0.89] | 0.86 [0.54, 0.86] | −0.11 [−0.25, 0.25] | −0.25 [−0.46, 0.18] |
| `multichm` | 0.82 [0.71, 0.89] | 0.71 [0.46, 0.82] | 0.57 [0.36, 0.75] | −0.04 [−0.21, 0.18] | −0.18 [−0.43, 0.07] |
| `lmfauto` | 0.82 [0.64, 0.96] | 0.79 [0.50, 0.93] | 0.75 [0.25, 0.86] | −0.29 [−0.46, 0.14] | −0.36 [−0.54, 0.07] |
| `ptrees` | 0.89 [0.82, 1.00] | 0.82 [0.57, 0.93] | 0.82 [0.36, 0.89] | −0.29 [−0.36, 0.18] | −0.36 [−0.54, 0.07] |
| AMS3D | 0.75 [0.54, 0.89] | 0.71 [0.50, 0.89] | 0.82 [0.29, 0.89] | 0.43 [0.21, 0.75] | 0.11 [−0.11, 0.36] |
| ForestFormer3D | 0.75 [0.54, 0.89] | 0.68 [0.43, 0.82] | 0.57 [0.25, 0.75] | −0.11 [−0.29, 0.18] | −0.32 [−0.43, 0.00] |
| TreeisoNet | 0.89 [0.71, 0.89] | 0.79 [0.57, 0.86] | 0.68 [0.43, 0.79] | 0.04 [−0.21, 0.25] | −0.21 [−0.43, 0.18] |
| SegmentAnyTree | 0.75 [0.54, 0.89] | 0.68 [0.39, 0.82] | 0.57 [0.29, 0.75] | −0.04 [−0.11, 0.43] | 0.07 [−0.07, 0.57] |
| SegmentAnyTree and AMS3D | 0.60 [0.26, 0.83] | 0.60 [0.31, 0.83] | 0.71 [0.26, 0.89] | 0.54 [0.43, 0.89] | 0.54 [0.43, 0.89] |
| SegmentAnyTree and AMS3D, censused subplots | 0.71 [0.37, 0.94] | 0.66 [0.43, 0.89] | 0.66 [0.43, 0.89] | 0.83 [0.54, 0.94] | 0.89 [0.54, 0.94] |

With six or seven detectors the correlation takes few values, so a point
estimate can sit at the end of its interval.
