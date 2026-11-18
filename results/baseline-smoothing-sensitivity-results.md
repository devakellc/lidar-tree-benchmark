# Baseline smoothing sensitivity

Checked on 7 October 2026 on the frozen five-site `adopted` population (106
plots, 2,525 stems), and extended on 17 November 2026, after an internal
review, with the QL2 rung and a chance-agreement correction of the unsmoothed
baseline. The paper's CHM-VWF derives its canopy-model resolution from measured
density (0.25 m at 8 or more first returns/m², else 0.5 m) and, below 8 first
returns/m², smooths the 0.5 m model with a circular 3 m moving mean (lasR
`focal(size = 3)`). The rule was fixed before the runs (configuration
provenance) and never tested without the smoothing: the calibration/validation
grid varies resolution and window slope only, and every headline plot below 8
pulses/m² is smoothed. A reviewer of the paper draft pointed out that the
baseline's loss at the first decimated rung (recall 0.464 to 0.327) follows the
rule switch rather than the density, while `multichm`, which switches to the
same resolution with the same window but no smoothing, loses nothing.

This study re-runs CHM-VWF on the same sealed clips with the smoothing disabled
(`detect_lidrplugins_sweep.R SITE=<site> ARMS=chm_vwf SMOOTH_BELOW=0 CORES=1`,
in its own job directory `paper_runs_nosmooth` with the ground truth, plot
centroids and sealed root linked; lasR runs single-threaded per site) and pools
it against the declared baseline and the leading arms with the master-table
resamples (`baseline_smoothing_sensitivity.R`). The QL2 rung (an all-return
target of 3.2 points/m², median 2.0 pulses/m²), frozen in its own root, is run
the same way in the job directory `paper_runs_nosmooth_ql2`, linked to that
root. At native density only the 18 plots whose clips hold fewer than 8
pulses/m² differ between the declared and unsmoothed runs; the rule reads the
density of the whole clip.

Densities in this report are whole-clip medians (4.7, 2.5, 2.0, 1.3 and 0.6
pulses/m² on the five thinned levels). The paper names the same levels by the
medians inside the scored plot cores, 4.4, 2.2, 1.8, 1.1 and 0.6 ([core
density](core-density-results.md)).

The run, its QL2 rung and the chance-agreement correction are all post hoc,
added after the five-site results were known: the headline tables keep the
declared rule, because a baseline re-declared after seeing the results would be
tuned on the test set. The unsmoothed baseline is a sensitivity row, not a
benchmark arm.

## CHM-VWF with and without the smoothing

Five sites, nominal plot core, paired plot-bootstrap intervals (1,000 draws,
plots resampled within site); dominant-class recall over the 347 dominant stems:

| Rung | Pulses/m² | F1, declared | Recall | Precision | Detections | Dominant recall | F1, no smoothing | Recall | Precision | Detections | Dominant recall | Change in F1 | Change in recall | Change in precision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| native | 9.8 | 0.450 [0.423, 0.478] | 0.464 | 0.438 | 2475 | 0.71 | 0.454 [0.426, 0.480] | 0.480 | 0.430 | 2611 | 0.71 | +0.003 [−0.002, +0.009] | +0.015 [+0.006, +0.028] | −0.007 [−0.017, −0.001] |
| 8 | 4.7 | 0.395 [0.370, 0.420] | 0.327 | 0.500 | 1510 | 0.56 | 0.463 [0.437, 0.489] | 0.497 | 0.434 | 2653 | 0.71 | +0.068 [+0.047, +0.091] | +0.171 [+0.143, +0.198] | −0.066 [−0.084, −0.046] |
| 4 | 2.5 | 0.396 [0.371, 0.421] | 0.328 | 0.499 | 1498 | 0.54 | 0.453 [0.427, 0.479] | 0.478 | 0.431 | 2571 | 0.69 | +0.058 [+0.037, +0.079] | +0.150 [+0.127, +0.175] | −0.068 [−0.087, −0.048] |
| 3.2 (QL2) | 2.0 | 0.392 [0.365, 0.416] | 0.321 | 0.502 | 1463 | 0.55 | 0.448 [0.423, 0.473] | 0.469 | 0.430 | 2529 | 0.70 | +0.057 [+0.036, +0.079] | +0.147 [+0.124, +0.173] | −0.072 [−0.095, −0.049] |
| 2 | 1.3 | 0.383 [0.357, 0.408] | 0.311 | 0.499 | 1424 | 0.54 | 0.449 [0.424, 0.473] | 0.463 | 0.436 | 2449 | 0.69 | +0.066 [+0.049, +0.084] | +0.152 [+0.130, +0.176] | −0.063 [−0.082, −0.044] |
| 1 | 0.6 | 0.374 [0.353, 0.396] | 0.296 | 0.506 | 1337 | 0.54 | 0.431 [0.406, 0.456] | 0.419 | 0.445 | 2152 | 0.65 | +0.058 [+0.040, +0.074] | +0.122 [+0.101, +0.142] | −0.061 [−0.082, −0.042] |

## Chance agreement of the two baselines

The chance null re-scores each cell's persisted detections after 200 random
toroidal shifts within the plot core plus the match radius
(`paper_sensitivity.R MODE=null`, the matcher-robustness study). The shifts are
drawn per plot, the same for every detector, rung and job directory, so the
unsmoothed baseline's null pairs with every other detector's. Null F1 is the
F1 of the shifted detections (each cell's mean counts over the shifts, pooled);
the null share is null F1 over F1; corrected F1 is (F1 − null F1) / (1 − null
F1). The change in corrected F1 is unsmoothed minus declared, with a paired
interval.

At the 4 m match radius:

| Rung | Pulses/m² | F1, declared | Null F1 | Null share | Corrected F1 | F1, no smoothing | Null F1 | Null share | Corrected F1 | Change in corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| native | 9.8 | 0.450 | 0.318 | 0.70 | 0.195 [0.169, 0.222] | 0.454 | 0.321 | 0.71 | 0.195 [0.171, 0.222] | +0.001 [−0.006, +0.007] |
| 8 | 4.7 | 0.395 | 0.272 | 0.69 | 0.170 [0.144, 0.196] | 0.463 | 0.323 | 0.70 | 0.207 [0.180, 0.232] | +0.037 [+0.017, +0.057] |
| 4 | 2.5 | 0.396 | 0.270 | 0.68 | 0.172 [0.147, 0.199] | 0.453 | 0.319 | 0.70 | 0.197 [0.171, 0.223] | +0.026 [+0.007, +0.046] |
| 3.2 (QL2) | 2.0 | 0.392 | 0.268 | 0.69 | 0.168 [0.141, 0.194] | 0.448 | 0.318 | 0.71 | 0.191 [0.168, 0.214] | +0.023 [+0.001, +0.043] |
| 2 | 1.3 | 0.383 | 0.265 | 0.69 | 0.161 [0.136, 0.186] | 0.449 | 0.316 | 0.70 | 0.195 [0.173, 0.218] | +0.034 [+0.016, +0.052] |
| 1 | 0.6 | 0.374 | 0.251 | 0.67 | 0.164 [0.142, 0.190] | 0.431 | 0.303 | 0.70 | 0.184 [0.158, 0.212] | +0.020 [−0.000, +0.039] |

At the 2 m match radius:

| Rung | Pulses/m² | F1, declared | Null F1 | Null share | Corrected F1 | F1, no smoothing | Null F1 | Null share | Corrected F1 | Change in corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| native | 9.8 | 0.345 | 0.169 | 0.49 | 0.211 [0.186, 0.235] | 0.348 | 0.172 | 0.49 | 0.212 [0.187, 0.238] | +0.001 [−0.006, +0.007] |
| 8 | 4.7 | 0.284 | 0.127 | 0.45 | 0.180 [0.155, 0.205] | 0.338 | 0.174 | 0.51 | 0.198 [0.174, 0.222] | +0.019 [+0.001, +0.036] |
| 4 | 2.5 | 0.282 | 0.128 | 0.45 | 0.177 [0.152, 0.205] | 0.338 | 0.168 | 0.50 | 0.204 [0.181, 0.227] | +0.027 [+0.009, +0.043] |
| 3.2 (QL2) | 2.0 | 0.280 | 0.124 | 0.44 | 0.178 [0.155, 0.201] | 0.331 | 0.166 | 0.50 | 0.198 [0.174, 0.223] | +0.020 [+0.003, +0.036] |
| 2 | 1.3 | 0.266 | 0.121 | 0.46 | 0.165 [0.142, 0.189] | 0.324 | 0.162 | 0.50 | 0.193 [0.169, 0.218] | +0.029 [+0.013, +0.044] |
| 1 | 0.6 | 0.247 | 0.113 | 0.46 | 0.151 [0.129, 0.174] | 0.296 | 0.149 | 0.50 | 0.172 [0.146, 0.199] | +0.021 [+0.002, +0.038] |

## Leads over either baseline

Observed F1 lead of the leading arms over the declared baseline / over the
unsmoothed baseline, at 4 m, by median pulses/m²:

| Arm | 9.8 | 4.7 | 2.5 | 2.0 (QL2) | 1.3 | 0.6 |
| --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | +0.048 [+0.028, +0.069] / +0.045 [+0.023, +0.065] | +0.092 [+0.065, +0.120] / +0.024 [+0.003, +0.046] | +0.062 [+0.035, +0.088] / +0.004 [−0.015, +0.025] | +0.060 [+0.035, +0.088] / +0.004 [−0.016, +0.024] | +0.055 [+0.029, +0.079] / −0.011 [−0.032, +0.007] | +0.047 [+0.022, +0.069] / −0.011 [−0.031, +0.009] |
| SegmentAnyTree | +0.044 [+0.021, +0.067] / +0.041 [+0.017, +0.063] | +0.091 [+0.064, +0.117] / +0.023 [+0.004, +0.042] | +0.073 [+0.046, +0.099] / +0.015 [−0.003, +0.034] | +0.058 [+0.036, +0.081] / +0.001 [−0.018, +0.020] | −0.007 [−0.030, +0.016] / −0.073 [−0.091, −0.056] | −0.246 [−0.268, −0.223] / −0.303 [−0.329, −0.274] |
| TreeisoNet | −0.004 [−0.018, +0.009] / −0.007 [−0.020, +0.006] | +0.056 [+0.032, +0.082] / −0.012 [−0.024, +0.001] | +0.057 [+0.034, +0.081] / −0.001 [−0.014, +0.013] | +0.057 [+0.033, +0.083] / +0.001 [−0.012, +0.013] | +0.061 [+0.038, +0.086] / −0.004 [−0.018, +0.009] | +0.066 [+0.037, +0.093] / +0.008 [−0.014, +0.029] |
| `multichm` | +0.005 [−0.018, +0.028] / +0.002 [−0.020, +0.025] | +0.056 [+0.028, +0.083] / −0.013 [−0.038, +0.014] | +0.045 [+0.020, +0.071] / −0.013 [−0.034, +0.011] | +0.058 [+0.032, +0.085] / +0.001 [−0.022, +0.025] | +0.057 [+0.031, +0.084] / −0.009 [−0.034, +0.016] | +0.060 [+0.036, +0.082] / +0.002 [−0.019, +0.025] |

Every detector run at all six levels against the unsmoothed baseline, observed
F1 lead / lead in corrected F1, five sites, at 4 m:

| Detector | 9.8 | 4.7 | 2.5 | 2.0 (QL2) | 1.3 | 0.6 |
| --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | +0.045 [+0.023, +0.065] / +0.020 [−0.003, +0.040] | +0.024 [+0.003, +0.046] / +0.004 [−0.017, +0.026] | +0.004 [−0.015, +0.025] / −0.014 [−0.035, +0.008] | +0.004 [−0.016, +0.024] / −0.009 [−0.030, +0.011] | −0.011 [−0.032, +0.007] / −0.018 [−0.042, +0.002] | −0.011 [−0.031, +0.009] / −0.020 [−0.043, +0.003] |
| SegmentAnyTree | +0.041 [+0.017, +0.063] / +0.034 [+0.005, +0.059] | +0.023 [+0.004, +0.042] / +0.015 [−0.005, +0.037] | +0.015 [−0.003, +0.034] / +0.007 [−0.014, +0.028] | +0.001 [−0.018, +0.020] / −0.006 [−0.029, +0.018] | −0.073 [−0.091, −0.056] / −0.045 [−0.069, −0.021] | −0.303 [−0.329, −0.274] / −0.137 [−0.163, −0.111] |
| TreeisoNet | −0.007 [−0.020, +0.006] / −0.012 [−0.029, +0.005] | −0.012 [−0.024, +0.001] / −0.019 [−0.035, −0.004] | −0.001 [−0.014, +0.013] / −0.009 [−0.026, +0.008] | +0.001 [−0.012, +0.013] / −0.007 [−0.024, +0.009] | −0.004 [−0.018, +0.009] / −0.014 [−0.030, +0.001] | +0.008 [−0.014, +0.029] / +0.001 [−0.021, +0.022] |
| `multichm` | +0.002 [−0.020, +0.025] / −0.018 [−0.039, +0.003] | −0.013 [−0.038, +0.014] / −0.036 [−0.059, −0.012] | −0.013 [−0.034, +0.011] / −0.039 [−0.061, −0.016] | +0.001 [−0.022, +0.025] / −0.022 [−0.043, +0.000] | −0.009 [−0.034, +0.016] / −0.033 [−0.053, −0.011] | +0.002 [−0.019, +0.025] / −0.028 [−0.053, −0.004] |
| AMS3D | −0.213 [−0.244, −0.183] / −0.133 [−0.161, −0.108] | −0.150 [−0.176, −0.122] / −0.116 [−0.138, −0.093] | −0.065 [−0.093, −0.036] / −0.063 [−0.087, −0.036] | −0.036 [−0.063, −0.010] / −0.045 [−0.068, −0.021] | +0.010 [−0.014, +0.034] / −0.012 [−0.038, +0.015] | +0.005 [−0.022, +0.033] / −0.000 [−0.027, +0.027] |
| `ptrees` | −0.123 [−0.157, −0.087] / −0.096 [−0.123, −0.067] | −0.020 [−0.035, −0.004] / −0.025 [−0.042, −0.006] | −0.040 [−0.054, −0.025] / −0.031 [−0.049, −0.014] | −0.043 [−0.062, −0.026] / −0.022 [−0.042, −0.001] | −0.088 [−0.108, −0.070] / −0.041 [−0.061, −0.021] | −0.160 [−0.182, −0.138] / −0.081 [−0.106, −0.057] |
| `lmfauto` | −0.067 [−0.098, −0.032] / −0.057 [−0.079, −0.036] | −0.124 [−0.158, −0.081] / −0.095 [−0.114, −0.072] | −0.170 [−0.208, −0.125] / −0.114 [−0.137, −0.089] | −0.175 [−0.214, −0.132] / −0.111 [−0.131, −0.088] | −0.187 [−0.228, −0.142] / −0.122 [−0.145, −0.098] | −0.163 [−0.202, −0.115] / −0.111 [−0.137, −0.085] |
| CHM-VWF, declared | −0.003 [−0.009, +0.002] / −0.001 [−0.007, +0.006] | −0.068 [−0.091, −0.047] / −0.037 [−0.057, −0.017] | −0.058 [−0.079, −0.037] / −0.026 [−0.046, −0.007] | −0.057 [−0.079, −0.036] / −0.023 [−0.043, −0.001] | −0.066 [−0.084, −0.049] / −0.034 [−0.052, −0.016] | −0.058 [−0.074, −0.040] / −0.020 [−0.039, +0.000] |

The same at 2 m:

| Detector | 9.8 | 4.7 | 2.5 | 2.0 (QL2) | 1.3 | 0.6 |
| --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | +0.009 [−0.010, +0.027] / +0.002 [−0.016, +0.020] | +0.000 [−0.019, +0.021] / +0.001 [−0.017, +0.021] | −0.015 [−0.032, +0.004] / −0.014 [−0.030, +0.004] | −0.013 [−0.032, +0.006] / −0.011 [−0.029, +0.005] | −0.030 [−0.050, −0.011] / −0.028 [−0.049, −0.010] | −0.017 [−0.036, +0.003] / −0.020 [−0.041, +0.001] |
| SegmentAnyTree | +0.023 [+0.005, +0.040] / +0.016 [−0.003, +0.033] | +0.018 [+0.000, +0.038] / +0.018 [−0.001, +0.036] | −0.005 [−0.023, +0.015] / −0.008 [−0.028, +0.013] | −0.021 [−0.041, −0.000] / −0.025 [−0.046, −0.003] | −0.063 [−0.080, −0.045] / −0.043 [−0.061, −0.022] | −0.220 [−0.246, −0.195] / −0.132 [−0.158, −0.107] |
| TreeisoNet | −0.006 [−0.021, +0.006] / −0.011 [−0.027, +0.002] | +0.009 [−0.005, +0.021] / +0.005 [−0.008, +0.018] | +0.010 [−0.003, +0.022] / +0.001 [−0.012, +0.014] | +0.014 [+0.000, +0.026] / +0.004 [−0.011, +0.018] | +0.016 [+0.003, +0.028] / +0.006 [−0.008, +0.020] | +0.017 [−0.001, +0.035] / +0.003 [−0.015, +0.021] |
| `multichm` | −0.035 [−0.055, −0.015] / −0.032 [−0.050, −0.014] | −0.035 [−0.055, −0.014] / −0.031 [−0.049, −0.013] | −0.040 [−0.061, −0.018] / −0.039 [−0.057, −0.019] | −0.040 [−0.060, −0.019] / −0.043 [−0.062, −0.024] | −0.034 [−0.058, −0.011] / −0.035 [−0.055, −0.014] | −0.021 [−0.042, +0.000] / −0.030 [−0.050, −0.010] |
| AMS3D | −0.157 [−0.183, −0.129] / −0.126 [−0.152, −0.101] | −0.093 [−0.113, −0.072] / −0.087 [−0.107, −0.066] | −0.036 [−0.058, −0.013] / −0.055 [−0.074, −0.032] | −0.009 [−0.031, +0.014] / −0.030 [−0.053, −0.006] | +0.010 [−0.010, +0.030] / −0.015 [−0.036, +0.005] | +0.004 [−0.021, +0.030] / +0.002 [−0.022, +0.026] |
| `ptrees` | −0.089 [−0.117, −0.062] / −0.082 [−0.107, −0.058] | −0.017 [−0.032, −0.002] / −0.015 [−0.031, +0.002] | −0.040 [−0.055, −0.024] / −0.026 [−0.043, −0.008] | −0.039 [−0.059, −0.019] / −0.018 [−0.038, +0.003] | −0.072 [−0.092, −0.052] / −0.037 [−0.056, −0.017] | −0.124 [−0.145, −0.102] / −0.077 [−0.098, −0.055] |
| `lmfauto` | −0.038 [−0.061, −0.012] / −0.053 [−0.071, −0.034] | −0.061 [−0.088, −0.031] / −0.068 [−0.089, −0.046] | −0.101 [−0.132, −0.063] / −0.101 [−0.124, −0.075] | −0.102 [−0.135, −0.064] / −0.101 [−0.124, −0.073] | −0.105 [−0.137, −0.068] / −0.102 [−0.127, −0.076] | −0.079 [−0.109, −0.046] / −0.086 [−0.111, −0.061] |
| CHM-VWF, declared | −0.003 [−0.008, +0.001] / −0.001 [−0.007, +0.006] | −0.053 [−0.073, −0.035] / −0.019 [−0.036, −0.001] | −0.056 [−0.072, −0.037] / −0.027 [−0.043, −0.009] | −0.051 [−0.070, −0.032] / −0.020 [−0.036, −0.003] | −0.058 [−0.074, −0.042] / −0.029 [−0.044, −0.013] | −0.049 [−0.066, −0.031] / −0.021 [−0.038, −0.002] |

By region at 4 m, observed lead / corrected lead over the unsmoothed baseline
(California is the development region, Washington the replication region):

| Detector | Region | 9.8 | 4.7 | 2.5 | 2.0 (QL2) | 1.3 | 0.6 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | California | +0.090 [+0.060, +0.122] / +0.066 [+0.035, +0.098] | +0.061 [+0.035, +0.090] / +0.040 [+0.011, +0.070] | +0.052 [+0.017, +0.085] / +0.040 [−0.001, +0.075] | +0.027 [−0.000, +0.055] / +0.013 [−0.017, +0.044] | +0.018 [−0.015, +0.051] / +0.011 [−0.027, +0.046] | −0.006 [−0.042, +0.024] / −0.006 [−0.046, +0.026] |
| ForestFormer3D | Washington | +0.026 [−0.002, +0.053] / +0.000 [−0.031, +0.026] | +0.009 [−0.018, +0.039] / −0.013 [−0.040, +0.015] | −0.014 [−0.036, +0.009] / −0.040 [−0.068, −0.013] | −0.004 [−0.029, +0.021] / −0.021 [−0.046, +0.007] | −0.019 [−0.043, +0.005] / −0.032 [−0.061, −0.007] | −0.008 [−0.033, +0.016] / −0.029 [−0.058, +0.000] |
| SegmentAnyTree | California | +0.091 [+0.046, +0.134] / +0.068 [+0.023, +0.109] | +0.057 [+0.022, +0.091] / +0.035 [+0.004, +0.069] | +0.040 [+0.011, +0.071] / +0.043 [+0.009, +0.075] | +0.011 [−0.019, +0.045] / +0.012 [−0.025, +0.053] | −0.046 [−0.089, −0.005] / −0.012 [−0.058, +0.034] | −0.260 [−0.309, −0.212] / −0.141 [−0.194, −0.092] |
| SegmentAnyTree | Washington | +0.024 [−0.001, +0.046] / +0.014 [−0.018, +0.042] | +0.012 [−0.009, +0.034] / +0.003 [−0.022, +0.028] | +0.005 [−0.018, +0.028] / −0.010 [−0.039, +0.017] | −0.004 [−0.028, +0.019] / −0.014 [−0.046, +0.016] | −0.084 [−0.106, −0.066] / −0.059 [−0.088, −0.031] | −0.320 [−0.351, −0.288] / −0.134 [−0.165, −0.101] |
| TreeisoNet | California | −0.009 [−0.027, +0.010] / −0.011 [−0.034, +0.011] | −0.016 [−0.041, +0.010] / −0.019 [−0.050, +0.011] | −0.009 [−0.036, +0.015] / −0.009 [−0.042, +0.021] | −0.018 [−0.045, +0.011] / −0.020 [−0.051, +0.011] | −0.020 [−0.046, +0.007] / −0.025 [−0.055, +0.006] | +0.018 [−0.012, +0.044] / +0.016 [−0.018, +0.048] |
| TreeisoNet | Washington | −0.002 [−0.019, +0.014] / −0.012 [−0.035, +0.010] | −0.005 [−0.019, +0.009] / −0.020 [−0.037, −0.003] | +0.007 [−0.008, +0.021] / −0.010 [−0.029, +0.010] | +0.012 [−0.002, +0.024] / −0.002 [−0.023, +0.017] | +0.006 [−0.009, +0.022] / −0.009 [−0.026, +0.010] | +0.007 [−0.022, +0.033] / −0.010 [−0.039, +0.020] |
| `multichm` | California | +0.058 [+0.029, +0.087] / +0.027 [−0.009, +0.063] | +0.042 [+0.006, +0.077] / +0.006 [−0.034, +0.044] | +0.052 [+0.018, +0.087] / +0.020 [−0.019, +0.056] | +0.053 [+0.023, +0.089] / +0.022 [−0.013, +0.062] | +0.036 [+0.009, +0.071] / +0.006 [−0.026, +0.045] | +0.054 [+0.019, +0.088] / +0.021 [−0.021, +0.059] |
| `multichm` | Washington | −0.019 [−0.045, +0.009] / −0.038 [−0.062, −0.014] | −0.033 [−0.064, −0.000] / −0.056 [−0.082, −0.028] | −0.037 [−0.064, −0.009] / −0.066 [−0.093, −0.040] | −0.019 [−0.049, +0.010] / −0.043 [−0.071, −0.018] | −0.026 [−0.055, +0.006] / −0.051 [−0.077, −0.026] | −0.017 [−0.043, +0.011] / −0.051 [−0.079, −0.023] |
| CHM-VWF, declared | California | +0.004 [−0.005, +0.015] / +0.006 [−0.003, +0.019] | −0.025 [−0.058, +0.009] / −0.001 [−0.035, +0.035] | −0.015 [−0.045, +0.017] / +0.017 [−0.020, +0.055] | −0.022 [−0.053, +0.009] / +0.003 [−0.033, +0.038] | −0.024 [−0.053, +0.005] / −0.003 [−0.037, +0.031] | −0.008 [−0.042, +0.024] / +0.020 [−0.021, +0.057] |
| CHM-VWF, declared | Washington | −0.006 [−0.013, −0.001] / −0.004 [−0.013, +0.004] | −0.085 [−0.112, −0.060] / −0.053 [−0.077, −0.030] | −0.075 [−0.100, −0.052] / −0.043 [−0.068, −0.022] | −0.071 [−0.097, −0.046] / −0.032 [−0.057, −0.010] | −0.082 [−0.104, −0.062] / −0.045 [−0.068, −0.026] | −0.077 [−0.094, −0.057] / −0.036 [−0.056, −0.016] |

The same at 2 m:

| Detector | Region | 9.8 | 4.7 | 2.5 | 2.0 (QL2) | 1.3 | 0.6 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | California | +0.060 [+0.039, +0.082] / +0.047 [+0.027, +0.067] | +0.044 [+0.021, +0.071] / +0.035 [+0.010, +0.063] | +0.048 [+0.023, +0.075] / +0.042 [+0.015, +0.071] | +0.035 [+0.009, +0.060] / +0.029 [+0.003, +0.054] | +0.026 [−0.001, +0.051] / +0.024 [−0.005, +0.051] | +0.008 [−0.025, +0.035] / +0.007 [−0.025, +0.035] |
| ForestFormer3D | Washington | −0.013 [−0.038, +0.012] / −0.018 [−0.043, +0.005] | −0.016 [−0.041, +0.010] / −0.014 [−0.039, +0.013] | −0.038 [−0.059, −0.016] / −0.039 [−0.059, −0.016] | −0.031 [−0.054, −0.007] / −0.029 [−0.052, −0.008] | −0.049 [−0.073, −0.025] / −0.051 [−0.079, −0.025] | −0.022 [−0.046, +0.003] / −0.031 [−0.058, −0.003] |
| SegmentAnyTree | California | +0.071 [+0.036, +0.102] / +0.051 [+0.019, +0.080] | +0.046 [+0.020, +0.076] / +0.032 [+0.005, +0.064] | +0.035 [+0.007, +0.068] / +0.034 [+0.005, +0.068] | +0.000 [−0.036, +0.043] / −0.001 [−0.040, +0.045] | −0.033 [−0.066, −0.000] / −0.015 [−0.049, +0.020] | −0.161 [−0.207, −0.124] / −0.110 [−0.158, −0.070] |
| SegmentAnyTree | Washington | +0.009 [−0.011, +0.027] / +0.000 [−0.023, +0.020] | +0.010 [−0.012, +0.033] / +0.011 [−0.014, +0.035] | −0.020 [−0.045, +0.006] / −0.027 [−0.053, +0.001] | −0.030 [−0.055, −0.006] / −0.036 [−0.062, −0.010] | −0.076 [−0.098, −0.054] / −0.056 [−0.080, −0.032] | −0.243 [−0.273, −0.212] / −0.141 [−0.173, −0.110] |
| TreeisoNet | California | +0.006 [−0.012, +0.024] / +0.001 [−0.016, +0.018] | +0.011 [−0.011, +0.036] / +0.007 [−0.015, +0.031] | +0.019 [−0.001, +0.039] / +0.014 [−0.005, +0.033] | +0.015 [−0.014, +0.046] / +0.011 [−0.020, +0.042] | +0.023 [−0.000, +0.048] / +0.020 [−0.005, +0.047] | +0.020 [−0.007, +0.044] / +0.011 [−0.015, +0.036] |
| TreeisoNet | Washington | −0.006 [−0.024, +0.010] / −0.014 [−0.034, +0.004] | +0.014 [−0.002, +0.029] / +0.007 [−0.011, +0.024] | +0.011 [−0.004, +0.027] / −0.003 [−0.021, +0.014] | +0.017 [+0.003, +0.030] / +0.002 [−0.014, +0.018] | +0.018 [+0.002, +0.033] / +0.002 [−0.013, +0.018] | +0.020 [−0.005, +0.043] / +0.000 [−0.023, +0.024] |
| `multichm` | California | +0.032 [+0.007, +0.057] / +0.021 [−0.006, +0.050] | +0.021 [−0.004, +0.051] / +0.006 [−0.020, +0.038] | +0.041 [+0.013, +0.068] / +0.029 [−0.001, +0.058] | +0.007 [−0.021, +0.034] / −0.011 [−0.042, +0.019] | +0.024 [−0.003, +0.054] / +0.011 [−0.018, +0.043] | +0.033 [+0.005, +0.061] / +0.016 [−0.014, +0.044] |
| `multichm` | Washington | −0.060 [−0.083, −0.036] / −0.055 [−0.077, −0.032] | −0.056 [−0.081, −0.030] / −0.048 [−0.071, −0.025] | −0.071 [−0.095, −0.044] / −0.069 [−0.091, −0.046] | −0.058 [−0.084, −0.031] / −0.057 [−0.081, −0.032] | −0.055 [−0.084, −0.026] / −0.055 [−0.082, −0.029] | −0.042 [−0.069, −0.015] / −0.050 [−0.077, −0.024] |
| CHM-VWF, declared | California | −0.003 [−0.014, +0.004] / −0.002 [−0.013, +0.005] | −0.023 [−0.049, +0.006] / −0.006 [−0.035, +0.024] | −0.016 [−0.044, +0.014] / +0.001 [−0.030, +0.033] | −0.026 [−0.056, +0.002] / −0.010 [−0.044, +0.023] | −0.009 [−0.039, +0.026] / +0.006 [−0.026, +0.043] | −0.014 [−0.046, +0.016] / −0.003 [−0.038, +0.031] |
| CHM-VWF, declared | Washington | −0.003 [−0.009, +0.001] / −0.000 [−0.009, +0.009] | −0.066 [−0.088, −0.044] / −0.025 [−0.046, −0.004] | −0.073 [−0.094, −0.052] / −0.040 [−0.059, −0.021] | −0.062 [−0.084, −0.041] / −0.025 [−0.043, −0.007] | −0.078 [−0.095, −0.061] / −0.044 [−0.061, −0.027] | −0.062 [−0.082, −0.042] / −0.029 [−0.049, −0.008] |

A lead narrowly excludes zero when its 95% interval excludes zero but ends
within 0.01 of it. Several printed bounds of ±0.000 lie within 0.0006 of zero;
the readings below say on which side.

**Readings.**

- Without the smoothing the baseline is flat down the ladder: F1 0.454, 0.463,
  0.453, 0.448, 0.449 and 0.431 at native density and at 4.7, 2.5, 2.0 (QL2),
  1.3 and 0.6 pulses/m², so 0.431 to 0.463 across the series with the QL2 rung
  added, against 0.450, 0.395, 0.396, 0.392, 0.383 and 0.374 as declared. The
  smoothing costs 0.057 to 0.068 F1 on each of the five thinned levels, through
  recall (−0.12 to −0.17) with a smaller gain in precision (+0.06 to +0.07); the
  unsmoothed baseline places 2,152 to 2,653 core detections on the thinned
  levels against 1,337 to 1,510.
- Against the unsmoothed baseline the observed leads of ForestFormer3D,
  TreeisoNet and `multichm` below native density, and SegmentAnyTree's at 4.7,
  2.5 and 2.0 pulses/m², are −0.013 to +0.024; at the QL2 rung they are +0.001
  to +0.004, none excluding zero. Only the two segmenters' leads at 4.7
  pulses/m² exclude zero, both narrowly (+0.024 [+0.003, +0.046] and +0.023
  [+0.004, +0.042]). Below the QL2 floor SegmentAnyTree, which collapses, is
  0.073 and 0.303 behind the unsmoothed baseline. Every lead over CHM-VWF below
  native density in the paper's Table 4 is therefore a lead over a configuration
  that under-detects by about 0.06 F1, which agrees with the chance-agreement
  correction (matcher-robustness study): corrected for chance, the same leads
  are −0.008 to +0.021 at 0.6 pulses/m².
- The null takes nearly the same share of both baselines' F1: 0.67 to 0.70 of
  the declared baseline's and 0.70 to 0.71 of the unsmoothed one's at 4 m, 0.44
  to 0.49 and 0.49 to 0.51 at 2 m, so the unsmoothed baseline's extra detections
  earn chance matches roughly in proportion. Its corrected F1 at 4 m is 0.184 to
  0.207 over the six levels (0.191 [0.168, 0.214] at the QL2 rung), against
  0.161 to 0.195 for the declared baseline. Above chance the smoothing still
  costs 0.020 to 0.037 at 4 m on the thinned levels, excluding zero at 4.7 and
  1.3 pulses/m² and narrowly at 2.5 and 2.0 (+0.023 [+0.001, +0.043] at the QL2
  rung), but not at 0.6 (+0.020, lower bound −0.00004); at 2 m it costs 0.019 to
  0.029 and excludes zero on all five thinned levels, narrowly except at 1.3
  pulses/m².
- Corrected for chance at 4 m, no detector leads the unsmoothed baseline below
  native density: the largest corrected lead there is SegmentAnyTree's +0.015
  [−0.005, +0.037] at 4.7 pulses/m²; ForestFormer3D's are −0.020 to +0.004 and
  TreeisoNet's −0.019 to +0.001. The only positive corrected lead that excludes
  zero is SegmentAnyTree's at native density, narrowly (+0.034 [+0.005,
  +0.059]). Below native density the exclusions are deficits: `multichm` at 4.7,
  2.5, 1.3 and 0.6 pulses/m² (−0.028 to −0.039, narrowly at 0.6; at 2.0, −0.022
  with an upper bound of +0.00002), TreeisoNet at 4.7, narrowly (−0.019 [−0.035,
  −0.004]), SegmentAnyTree at 1.3 and 0.6, AMS3D down to 2.0, `ptrees` (narrowly
  at 4.7 and 2.0) and `lmfauto` everywhere, and the declared baseline at 4.7,
  2.5, 2.0 and 1.3 (narrowly at 2.5 and 2.0). At the QL2 rung the four leading
  detectors' corrected leads are −0.022 to −0.006, none excluding zero.
- At 2 m, observed leads over the unsmoothed baseline narrowly exclude zero for
  SegmentAnyTree at native density (+0.023 [+0.005, +0.040]) and 4.7 pulses/m²
  (+0.018, lower bound +0.0003), and for TreeisoNet at 2.0 (+0.014, lower bound
  +0.0003) and 1.3 pulses/m² (+0.016 [+0.003, +0.028]). Corrected for chance, no
  lead excludes zero at 2 m on any level; the largest are SegmentAnyTree's
  +0.016 and +0.018 at native density and 4.7 pulses/m² and TreeisoNet's +0.001
  to +0.006 below native density. At 2 m `multichm` trails the unsmoothed
  baseline on every level, in observed F1 (−0.021 to −0.040, every interval
  excluding zero but the one at 0.6 pulses/m², whose upper bound is +0.0002) and
  in corrected F1 (−0.030 to −0.043, every interval excluding zero);
  ForestFormer3D trails it at 1.3 pulses/m² and SegmentAnyTree from the QL2 rung
  down, in both.
- The five-site leads pool regions of opposite sign. In California, the
  development region, `multichm` leads the unsmoothed baseline in observed F1 on
  every level at 4 m (+0.036 to +0.058) but not above chance (+0.006 to +0.027,
  none excluding zero), while above chance ForestFormer3D leads at native
  density and 4.7 pulses/m² and SegmentAnyTree at native density, 4.7 and 2.5
  pulses/m² (narrowly at the last two); at 2 m ForestFormer3D's corrected lead
  excludes zero from native density down to the QL2 rung (+0.029 to +0.047). In
  Washington, the replication region, no detector leads the unsmoothed baseline
  at 4 m on any level, observed or corrected, and above chance `multichm` trails
  it on every level (−0.038 to −0.066), ForestFormer3D at 2.5 and, narrowly, 1.3
  pulses/m², TreeisoNet at 4.7, narrowly, and SegmentAnyTree below the QL2
  floor; at 2 m only TreeisoNet's observed leads at 2.0 and 1.3 pulses/m²
  exclude zero, narrowly, and no corrected lead does. The smoothing's cost is a
  Washington effect: in California the declared baseline is level with the
  unsmoothed one on every thinned level at 4 m, observed (−0.025 to −0.008) and
  corrected (−0.003 to +0.020), while in Washington it trails by 0.071 to 0.085
  observed and 0.032 to 0.053 corrected, every interval excluding zero.
- Dominant-class recall shows the mechanism: the declared baseline keeps 0.54 to
  0.56 of the 347 dominant stems on the thinned levels (0.55 at the QL2 rung)
  against 0.71 at native density; the unsmoothed one keeps 0.65 to 0.71 (0.70 at
  the QL2 rung).
- These readings are on the nominal plot cores. Inside the censused subplots of
  the 57 admitted plots the comparison gives the same answer: no positive
  corrected lead over the unsmoothed baseline excludes zero on any thinned level
  at 4 m, and the declared baseline trails the unsmoothed one by 0.051 to 0.110
  in censused corrected F1, every interval excluding zero; see the [censused
  chance agreement
  study](censused-chance-agreement-results.md#leads-over-the-unsmoothed-baseline).

## Run-to-run variation

lasR's canopy-model maxima vary slightly between runs, single-threaded too. To
see whether that moves either baseline, every cell was detected three more
times on 17 November 2026, with and without the smoothing: 1,184 cell
configurations, the 88 native cells at 8 or more pulses/m² (which no smoothing
touches) and the 548 others each way. The apexes changed in 12 configurations
(one dense native cell, six smoothed and five unsmoothed 0.5 m cells), and the
scored counts in one: SJER_053 at native density without the smoothing, whose
core detections were 22 or 23 with 9 stems matched every time. That moves the
unsmoothed baseline's pooled native F1 by 0.0001 (0.4534 to 0.4535); every
other pooled F1 of either baseline was the same in every repeat, and the scored
counts of every cell of both runs are among the repeats. The same cell's apex
count differs by one between the main unsmoothed run and the native cells of
the QL2 job directory (93 and 92), with the same scored counts. The script
therefore requires the QL2 job directories' native cells to repeat the main
runs' reference and matched stems exactly and their core detections to within
one. A rebuild from scratch can change that one cell, and the pooled native F1
in the fourth decimal; the persisted apexes and per-cell rows of both runs are
the reference.

`paper_runs/sensitivity/baseline_smoothing_{pooled,contrasts,dominant}.csv` hold
every arm and rung, the QL2 rung's rows last;
`baseline_smoothing_corrected.csv` holds each detector's F1, null F1, null share
and corrected F1, and `baseline_smoothing_corrected_leads.csv` each observed and
corrected lead over either baseline, at 4 and 2 m, for five sites and each
region. The unsmoothed run's per-plot rows are in
`paper_runs_nosmooth{,_ql2}/neon/<SITE>/lidrplugins_results.csv`, its persisted
apexes in `chm_vwf_detections/` beside them, and its observed and null counts
per cell in `paper_runs_nosmooth{,_ql2}/sensitivity/null{,_tol2}_cells.csv`.
The script stops unless every corrected F1 and every lead over the declared
baseline equal those of the null re-scores (`null_delta.csv` and
`null_leads.csv` of each job directory), the observed F1 equals the pooled
result rows, and the QL2 job directories' native cells repeat the main runs'
counts (core detections within one).

## Reproduce

```sh
W=$PWD/work; P=$W/paper_runs
for JR in paper_runs_nosmooth:frozen_2021 paper_runs_nosmooth_ql2:frozen_2021_ql2; do
  J=$W/${JR%%:*}; R=${JR#*:}; mkdir -p $J/neon; ln -sfn $W/neon/$R $J/neon/$R
  for s in SJER SOAP TEAK WREF ABBY; do
    mkdir -p $J/neon/$s
    for f in ground_truth_stems.csv plot_centroids.csv; do ln -sfn $P/neon/$s/$f $J/neon/$s/$f; done
    CLAUDE_JOB_DIR=$J Rscript scripts/detect_lidrplugins_sweep.R SITE=$s ARMS=chm_vwf SMOOTH_BELOW=0 \
      CORES=1 FROZEN_ROOT=$W/neon/$R
  done
done
for t in 4 2; do
  CLAUDE_JOB_DIR=$W/paper_runs_nosmooth Rscript scripts/paper_sensitivity.R MODE=null K=200 TOL=$t \
    ARMS=chm_vwf CORES=8
  CLAUDE_JOB_DIR=$W/paper_runs_nosmooth_ql2 Rscript scripts/paper_sensitivity.R MODE=null K=200 TOL=$t \
    ARMS=chm_vwf RUNGS=3.2 FROZEN_ROOT=$W/neon/frozen_2021_ql2 CORES=8
done
CLAUDE_JOB_DIR=$P Rscript scripts/baseline_smoothing_sensitivity.R NOSMOOTH=$W/paper_runs_nosmooth
```

The script takes the QL2 job directories from `QL2=` (default `paper_runs_ql2`
beside the job directory; `QL2=none` leaves the rung out) and `NOSMOOTH_QL2=`
(default `<NOSMOOTH>_ql2`), and the null radii from `NULL_TOLS=` (default
`4,2`); without those inputs it writes the three observed tables as before.

A note on the sweep script: `detect_lidrplugins_sweep.R` read its window slope
with `A$A`, which R's partial matching resolves to `ARMS=` when that argument is
given, so a run with `ARMS=` and no explicit `A=` had a missing slope and
detected nothing. The paper's lidrplugins runs did not pass `ARMS=` and the
compute-cost cells call the detector directly, so neither was affected; the
script now matches the argument exactly.
