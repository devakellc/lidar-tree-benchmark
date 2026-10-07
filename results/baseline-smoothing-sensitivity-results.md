# Baseline smoothing sensitivity

Checked on 7 October 2026 on the frozen five-site `adopted` population (106
plots, 2,525 stems). The paper's CHM-VWF derives its canopy-model resolution
from measured density (0.25 m at 8 or more first returns/m², else 0.5 m) and,
below 8 first returns/m², smooths the 0.5 m model with a circular 3 m moving
mean (lasR `focal(size = 3)`). The rule was fixed before the runs (configuration
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
resamples (`baseline_smoothing_sensitivity.R`). It is a post hoc sensitivity:
the headline tables keep the declared rule, because a baseline re-declared after
seeing the results would be tuned on the test set. The QL2 rung, frozen in its
own root, was not run. At native density only the 18 plots below 8 pulses/m²
differ between the two runs.

## CHM-VWF with and without the smoothing

Five sites, nominal plot core, paired plot-bootstrap intervals (1,000 draws,
plots resampled within site); dominant-class recall over the 347 dominant stems:

| Rung | Pulses/m² | F1, declared | Recall | Precision | Detections | Dominant recall | F1, no smoothing | Recall | Precision | Detections | Dominant recall | Change in F1 | Change in recall | Change in precision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| native | 9.8 | 0.450 [0.423, 0.478] | 0.464 | 0.438 | 2475 | 0.71 | 0.454 [0.426, 0.480] | 0.480 | 0.430 | 2611 | 0.71 | +0.003 [−0.002, +0.009] | +0.015 [+0.006, +0.028] | −0.007 [−0.017, −0.001] |
| 8 | 4.7 | 0.395 [0.370, 0.420] | 0.327 | 0.500 | 1510 | 0.56 | 0.463 [0.437, 0.489] | 0.497 | 0.434 | 2653 | 0.71 | +0.068 [+0.047, +0.091] | +0.171 [+0.143, +0.198] | −0.066 [−0.084, −0.046] |
| 4 | 2.5 | 0.396 [0.371, 0.421] | 0.328 | 0.499 | 1498 | 0.54 | 0.453 [0.427, 0.479] | 0.478 | 0.431 | 2571 | 0.69 | +0.058 [+0.037, +0.079] | +0.150 [+0.127, +0.175] | −0.068 [−0.087, −0.048] |
| 2 | 1.3 | 0.383 [0.357, 0.408] | 0.311 | 0.499 | 1424 | 0.54 | 0.449 [0.424, 0.473] | 0.463 | 0.436 | 2449 | 0.69 | +0.066 [+0.049, +0.084] | +0.152 [+0.130, +0.176] | −0.063 [−0.082, −0.044] |
| 1 | 0.6 | 0.374 [0.353, 0.396] | 0.296 | 0.506 | 1337 | 0.54 | 0.431 [0.406, 0.456] | 0.419 | 0.445 | 2152 | 0.65 | +0.058 [+0.040, +0.074] | +0.122 [+0.101, +0.142] | −0.061 [−0.082, −0.042] |

## Leads of the leading arms over either baseline

Observed F1 lead over the declared baseline / over the unsmoothed baseline:

| Arm | 9.8 | 4.7 | 2.5 | 1.3 | 0.6 |
| --- | --- | --- | --- | --- | --- |
| ForestFormer3D | +0.048 [+0.028, +0.069] / +0.045 [+0.023, +0.065] | +0.092 [+0.065, +0.120] / +0.024 [+0.003, +0.046] | +0.062 [+0.035, +0.088] / +0.004 [−0.015, +0.025] | +0.055 [+0.029, +0.079] / −0.011 [−0.032, +0.007] | +0.047 [+0.022, +0.069] / −0.011 [−0.031, +0.009] |
| SegmentAnyTree | +0.044 [+0.021, +0.067] / +0.041 [+0.017, +0.063] | +0.091 [+0.064, +0.117] / +0.023 [+0.004, +0.042] | +0.073 [+0.046, +0.099] / +0.015 [−0.003, +0.034] | −0.007 [−0.030, +0.016] / −0.073 [−0.091, −0.056] | −0.246 [−0.268, −0.223] / −0.303 [−0.329, −0.274] |
| TreeisoNet | −0.004 [−0.018, +0.009] / −0.007 [−0.020, +0.006] | +0.056 [+0.032, +0.082] / −0.012 [−0.024, +0.001] | +0.057 [+0.034, +0.081] / −0.001 [−0.014, +0.013] | +0.061 [+0.038, +0.086] / −0.004 [−0.018, +0.009] | +0.066 [+0.037, +0.093] / +0.008 [−0.014, +0.029] |
| `multichm` | +0.005 [−0.018, +0.028] / +0.002 [−0.020, +0.025] | +0.056 [+0.028, +0.083] / −0.013 [−0.038, +0.014] | +0.045 [+0.020, +0.071] / −0.013 [−0.034, +0.011] | +0.057 [+0.031, +0.084] / −0.009 [−0.034, +0.016] | +0.060 [+0.036, +0.082] / +0.002 [−0.019, +0.025] |

**Readings.**

- Without the smoothing the baseline is flat down the ladder: F1 0.454, 0.463,
  0.453, 0.449 and 0.431 from native density to 0.6 pulses/m², against 0.450,
  0.395, 0.396, 0.383 and 0.374 as declared. The smoothing costs 0.06 to 0.07 F1
  on every decimated rung, through recall (−0.12 to −0.17) with a smaller gain
  in precision (+0.06 to +0.07); the unsmoothed baseline places 2,152 to 2,653
  core detections on the rungs against 1,337 to 1,510.
- Against the unsmoothed baseline the observed leads of ForestFormer3D,
  SegmentAnyTree, TreeisoNet and `multichm` below native density are −0.013 to
  +0.024; only the two segmenters' leads at 4.7 pulses/m² exclude zero (+0.024
  [+0.003, +0.046] and +0.023 [+0.004, +0.042]). SegmentAnyTree is 0.073 and
  0.303 behind it at 1.3 and 0.6 pulses/m². Every lead over CHM-VWF below native
  density in the paper's Table 4 is therefore a lead over a configuration that
  under-detects by about 0.06 F1, which agrees with the chance-agreement
  correction (matcher-robustness study): corrected for chance, the same leads
  are −0.008 to +0.021 at 0.6 pulses/m².
- Dominant-class recall shows the mechanism: the declared baseline keeps 0.56 to
  0.54 of the 347 dominant stems on the rungs against 0.71 at native density;
  the unsmoothed one keeps 0.65 to 0.71.

`paper_runs/sensitivity/baseline_smoothing_{pooled,contrasts,dominant}.csv` hold
every arm and rung; the unsmoothed run's per-plot rows are in
`paper_runs_nosmooth/neon/<SITE>/lidrplugins_results.csv`.

## Reproduce

```sh
J=work/paper_runs_nosmooth; mkdir -p $J/neon; ln -sfn $PWD/work/neon/frozen_2021 $J/neon/frozen_2021
for s in SJER SOAP TEAK WREF ABBY; do
  mkdir -p $J/neon/$s
  for f in ground_truth_stems.csv plot_centroids.csv; do ln -sfn $PWD/work/paper_runs/neon/$s/$f $J/neon/$s/$f; done
  CLAUDE_JOB_DIR=$J Rscript scripts/detect_lidrplugins_sweep.R SITE=$s ARMS=chm_vwf SMOOTH_BELOW=0 CORES=1
done
CLAUDE_JOB_DIR=work/paper_runs Rscript scripts/baseline_smoothing_sensitivity.R NOSMOOTH=$J
```

A note on the sweep script: `detect_lidrplugins_sweep.R` read its window slope
with `A$A`, which R's partial matching resolves to `ARMS=` when that argument is
given, so a run with `ARMS=` and no explicit `A=` had a missing slope and
detected nothing. The paper's lidrplugins runs did not pass `ARMS=` and the
compute-cost cells call the detector directly, so neither was affected; the
script now matches the argument exactly.
