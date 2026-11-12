# Gated multichm: calibration and validation

Checked on 12 November 2026 on the frozen five-site `adopted` population (106
plots, 2,525 stems). `multichm_gated` is a post hoc arm. It is not one of the
paper's twelve arms, the master tables do not include it, and the declared
`multichm` arm is unchanged.

`multichm` (lidRplugins) finds local maxima on the canopy surface, strips the
top of the cloud and searches again, layer by layer. It then keeps a peak unless
a taller kept peak lies within 3 m horizontally or within 5 m in three
dimensions. The arm rests on two premises about closed stands, both from an
exploratory pass. Peaks found after stripping (the deeper layers) often sit
inside the crowns of trees already found; the study does not measure this. And
the distance filter removes neighbouring surface peaks of similar height, which
in a dense stand are often separate trees.

## The arm

The arm keeps the package's candidate search and changes what is accepted:

- **Height floor.** A deeper-layer peak must be at least `zmin` high, in every
  stand.
- **First-return share.** In a closed stand a deeper-layer peak is kept only
  when at least `min_share` of the returns around it are first returns, so the
  spot is lit from above. The returns counted lie within 1 m of the peak
  horizontally and within 1 m of its own top return vertically.
- **Surface exemption.** In a closed stand, surface-layer peaks skip the
  distance filter when `surface_exempt` is on. They still exclude lower
  deeper-layer peaks near them; a taller deeper-layer peak and an exempt
  surface peak beside it are both kept.
- **Closed stand.** A clip (plot core plus 25 m buffer) is closed when its
  canopy cover, the share of first returns higher than 2 m, is at least
  `cover_min`.

With all four switched off the arm is `multichm`: it returns the same tree tops
as the paper runs in all 530 cells (106 plots at five densities), and its
scores and chance null equal theirs cell by cell. The candidate search runs on
one lidR thread, because lidR breaks tied heights differently from call to call
on several. The declared configuration needs return numbers: a configuration
that reads the first-return share or the canopy cover stops on a cloud without
them.

## Calibration

The thresholds come from a grid of 87 configurations: `zmin` 0, 5 or 8 m;
`min_share` 0, 0.5, 0.75 or 0.9; `cover_min` 0 (every stand counts as closed),
0.6, 0.7 or 0.8; `surface_exempt` off or on. Each site's plots are split into
calibration and validation halves by the stratified split of the
[calibration/validation study](calibration-validation-results.md) (seed 1),
giving 57 calibration and 49 validation plots. The configuration with the
highest chance-corrected F1 at native density on the calibration plots is
selected; ties go to the configuration that changes least.

Chance-corrected F1 is (F1 − null F1) / (1 − null F1). The null is the score of
the same detections under 200 random shifts per plot, as in the
[chance-agreement study](matcher-robustness-results.md#chance-agreement).
Plain F1 is not the criterion because it rewards the number of detections:
shifted copies reach 70 to 79% of the F1 of every arm but one at native
density. The selection under plain F1 is reported
[below](#selecting-on-plain-f1).

The selected configuration is `zmin` 5 m, `min_share` 0.75, `cover_min` 0.6 and
`surface_exempt` on. It is the arm's declared configuration (`MCG_DECLARED` in
[multichm_gated_lib.R](../scripts/multichm_gated_lib.R)). On the calibration
plots it raises corrected F1 from 0.187 to 0.214; that figure is in sample.

**Exploratory provenance.** The form of the gate, the grid values and the
criterion were fixed after an exploratory pass over all 106 plots, validation
plots included, and before the calibration was run. The held-out scores below
therefore test only the selection within the grid, not the grid's values or the
choice of features. They could hardly have come out negative: on the validation
plots 82 of the 86 non-stock grid configurations score above stock in corrected
F1 (median +0.019; 32 intervals lie above zero and none below), and the
selected one (+0.034) ranks fifth of the 87 configurations. What the validation
half does test is whether the calibration ranking carries over: across the grid
the calibration and validation changes correlate at 0.81. An untouched test
needs plots outside these five sites.

## Held-out scores

Validation plots only, the declared configuration against stock `multichm`,
nominal plot core. Intervals are paired plot-bootstrap percentiles (1,000 draws,
plots resampled within site, the same draws for both arms and for observed and
null counts). "Corrected" means corrected for chance as above.

At native density (9.8 pulses/m²):

| Scope | Plots | Stems | Detections, gated / stock | F1, gated / stock | Corrected F1, gated / stock | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Five sites | 49 | 1,172 | 1,264 / 1,472 | 0.484 / 0.468 | 0.200 / 0.166 | +0.034 [+0.005, +0.059] | +0.050 [+0.020, +0.079] | +0.003 [−0.033, +0.036] |
| California | 19 | 266 | 330 / 382 | 0.435 / 0.436 | 0.260 / 0.246 | +0.013 [−0.006, +0.028] | +0.022 [+0.009, +0.036] | −0.020 [−0.059, +0.003] |
| Washington | 30 | 906 | 934 / 1,090 | 0.499 / 0.479 | 0.177 / 0.133 | +0.044 [+0.008, +0.074] | +0.064 [+0.026, +0.106] | +0.012 [−0.036, +0.052] |

By site, on each site's validation plots:

| Site | Plots | Stems | Detections, gated / stock | Change in F1 | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SJER | 3 | 23 | 64 / 82 | +0.044 [+0.022, +0.063] | +0.047 [+0.026, +0.070] | +0.041 [+0.022, +0.061] | −0.099 [−0.178, +0.000] |
| SOAP | 8 | 89 | 141 / 161 | +0.002 [−0.038, +0.020] | +0.012 [−0.026, +0.034] | +0.016 [−0.010, +0.032] | −0.031 [−0.097, +0.006] |
| TEAK | 8 | 154 | 125 / 139 | −0.020 [−0.074, +0.014] | +0.002 [−0.047, +0.027] | +0.010 [−0.022, +0.058] | −0.003 [−0.052, +0.017] |
| WREF | 18 | 565 | 404 / 675 | −0.021 [−0.067, +0.012] | +0.033 [−0.026, +0.076] | +0.136 [+0.077, +0.195] | −0.048 [−0.119, −0.002] |
| ABBY | 12 | 341 | 530 / 415 | +0.063 [+0.005, +0.110] | +0.066 [+0.022, +0.109] | +0.035 [−0.005, +0.073] | +0.165 [+0.062, +0.287] |

Change in corrected F1 down the ladder, with the five-site detection counts and
the difference between the regions (both regions resampled together):

| Pulses/m² | Five sites | California | Washington | Washington minus California | Detections, gated / stock |
| --- | --- | --- | --- | --- | --- |
| 9.8 (native) | +0.034 [+0.005, +0.059] | +0.013 [−0.006, +0.028] | +0.044 [+0.008, +0.074] | +0.030 [−0.008, +0.064] | 1,264 / 1,472 |
| 4.7 | +0.021 [−0.007, +0.048] | −0.009 [−0.042, +0.013] | +0.032 [−0.003, +0.068] | +0.041 [+0.001, +0.087] | 1,277 / 1,518 |
| 2.5 | +0.042 [+0.022, +0.064] | +0.020 [+0.002, +0.047] | +0.050 [+0.024, +0.076] | +0.030 [−0.007, +0.064] | 1,327 / 1,467 |
| 1.3 | +0.012 [−0.012, +0.034] | −0.013 [−0.043, +0.010] | +0.023 [−0.009, +0.052] | +0.036 [−0.002, +0.075] | 1,407 / 1,425 |
| 0.6 | +0.029 [+0.005, +0.058] | −0.012 [−0.036, +0.003] | +0.048 [+0.015, +0.084] | +0.060 [+0.026, +0.104] | 1,608 / 1,371 |

**Readings.**

- At native density held-out corrected F1 rises from 0.166 to 0.200 (+0.034
  [+0.005, +0.059]). The gain is in corrected precision (+0.050); pooled
  corrected recall stays where stock has it (+0.003 [−0.033, +0.036]), with 14%
  fewer detections (1,264 against 1,472). Plain F1 changes by +0.015 [−0.012,
  +0.042], which does not exclude zero.
- The change is +0.044 [+0.008, +0.074] in Washington and +0.013 [−0.006,
  +0.028] in California. The difference between the regions, +0.030 [−0.008,
  +0.064], includes zero at native density; down the ladder it excludes zero at
  4.7 and 0.6 pulses/m². At native density 61 of the 63 Washington plots are
  closed at a cover of 0.6, against 8 of the 43 California plots.
- The two Washington sites move in opposite directions. At WREF, old-growth
  Douglas-fir and western hemlock, the arm keeps 404 of 675 detections:
  corrected precision rises by 0.136 and corrected recall falls by 0.048 [0.002,
  0.119]. At ABBY, managed Douglas-fir, it places 530 detections against 415:
  corrected recall rises by 0.165 [0.062, 0.287]. The unchanged pooled recall
  is the sum of these two changes. Only ABBY's change in corrected F1 excludes
  zero among the larger sites; SJER's validation half holds 3 plots, too few
  for its interval to carry weight.
- Down the ladder the five-site change stays positive (+0.012 to +0.042) and
  excludes zero at 2.5 and 0.6 pulses/m² as well as at native density.
  California's change is negative on three of the four decimated rungs (−0.009
  to −0.013), never excluding zero, with lower corrected recall (−0.063
  [−0.119, −0.029] at 4.7 pulses/m²).
- At 0.6 pulses/m² the arm places more detections than stock (1,608 against
  1,371): the exemption admits more surface peaks than the gate removes.
  Corrected recall rises by 0.066 [+0.033, +0.101] there and corrected precision
  by 0.014 [−0.010, +0.044].
- On all 106 plots at native density the declared configuration scores F1 0.473
  and corrected F1 0.208, against 0.456 and 0.178 for stock (+0.030 [+0.013,
  +0.045] corrected, +0.017 [−0.001, +0.034] plain). This is not a held-out
  score: 57 of those plots selected the configuration. By site it changes the
  detection count from 1,312 to 791 at WREF, 894 to 1,125 at ABBY, 388 to 342
  at SOAP, 385 to 329 at TEAK and 178 to 146 at SJER. On the 38 WREF plots
  plain F1 falls by 0.029 [0.001, 0.062].

## What each part does

Validation plots, native density, five sites. First each reduced configuration
against stock `multichm` (1,472 detections):

| Configuration | Detections | Change in F1 | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- |
| Floor only | 1,332 | +0.019 [+0.013, +0.024] | +0.015 [+0.009, +0.021] | +0.022 [+0.015, +0.031] | −0.003 [−0.010, +0.004] |
| Floor and share gate | 965 | −0.019 [−0.045, +0.002] | +0.027 [+0.001, +0.049] | +0.077 [+0.051, +0.106] | −0.039 [−0.068, −0.015] |
| Floor and exemption | 1,575 | +0.037 [+0.021, +0.055] | +0.028 [+0.015, +0.040] | +0.016 [+0.003, +0.027] | +0.056 [+0.031, +0.084] |
| Exemption only | 1,682 | +0.023 [+0.008, +0.040] | +0.015 [+0.003, +0.027] | +0.000 [−0.012, +0.010] | +0.059 [+0.035, +0.087] |
| All three (declared) | 1,264 | +0.015 [−0.012, +0.042] | +0.034 [+0.005, +0.059] | +0.050 [+0.020, +0.079] | +0.003 [−0.033, +0.036] |

Then what each part adds to the other two: the declared configuration against
the declared configuration without that part.

| Part | Detections, with / without | Change in F1 | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- |
| Floor | 1,264 / 1,325 | +0.009 [+0.005, +0.013] | +0.008 [+0.004, +0.013] | +0.014 [+0.007, +0.023] | −0.001 [−0.005, +0.002] |
| Share gate | 1,264 / 1,575 | −0.022 [−0.041, −0.005] | +0.007 [−0.018, +0.027] | +0.034 [+0.012, +0.061] | −0.053 [−0.085, −0.027] |
| Exemption | 1,264 / 965 | +0.035 [+0.013, +0.058] | +0.007 [−0.008, +0.022] | −0.028 [−0.053, −0.005] | +0.043 [+0.022, +0.063] |

- The floor is the only part whose own contribution to corrected F1 excludes
  zero (+0.008 [+0.004, +0.013]). It removes 61 detections at no cost in
  recall.
- The share gate removes 311 of 1,575 detections. Corrected precision rises by
  0.034 and corrected recall falls by 0.053, so some of what it removes are
  real trees, and plain F1 falls by 0.022 [0.005, 0.041]. Its own change in
  corrected F1, +0.007 [−0.018, +0.027], is not separable from zero. It is
  +0.006 [−0.009, +0.022] on the calibration plots, so the criterion preferred
  a share gate by a margin it cannot resolve.
- The exemption adds 299 detections to the floor and share gate. Corrected
  recall rises by 0.043 and corrected precision falls by 0.028. Its own change
  in corrected F1 is +0.007 [−0.008, +0.022] on the validation plots and +0.017
  [+0.005, +0.028] on the calibration plots. Alone against stock it adds 210
  detections and 0.059 corrected recall at unchanged corrected precision, so
  the distance filter had been removing real neighbouring trees.
- The share gate and the exemption trade precision against recall. Corrected F1
  does not separate the declared configuration from the floor with either one
  of them: +0.028 [+0.015, +0.040] with the exemption, +0.027 [+0.001, +0.049]
  with the share gate. Those two differ in plain F1 (+0.037 against −0.019)
  and in the number of detections (1,575 against 965).

## Stability

Two hundred splits (seeds 1 to 200), each selecting on its own calibration
plots and scored on its own validation plots at native density, five sites.
Values selected, with the number of splits selecting each:

| Parameter | Values selected |
| --- | --- |
| `zmin` | 5 m in 187, 8 m in 13 |
| `min_share` | none in 15, 0.5 in 86, 0.75 in 79, 0.9 in 20 |
| `cover_min` | 0.6 in 164, 0.7 in 28, 0.8 in 8 |
| `surface_exempt` | on in 199, off in 1 |

Leaving one site out: the configuration is selected on all plots of the other
four sites and scored on the held-out site at native density.

| Held-out site | Plots | `zmin` | `min_share` | `cover_min` | `surface_exempt` | Detections, gated / stock | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SJER | 6 | 5 | 0.5 | 0.6 | on | 146 / 178 | +0.024 [−0.007, +0.054] | +0.025 [+0.008, +0.045] | −0.072 [−0.115, −0.014] |
| SOAP | 18 | 5 | 0.75 | 0.6 | on | 342 / 388 | +0.012 [−0.014, +0.037] | +0.018 [+0.000, +0.039] | −0.030 [−0.078, +0.018] |
| TEAK | 19 | 5 | 0.75 | 0.6 | on | 329 / 385 | +0.012 [−0.012, +0.032] | +0.031 [+0.004, +0.066] | −0.010 [−0.034, +0.005] |
| WREF | 38 | 5 | 0.5 | 0.6 | on | 942 / 1,312 | +0.020 [−0.004, +0.041] | +0.067 [+0.042, +0.095] | −0.037 [−0.070, −0.014] |
| ABBY | 25 | 5 | 0.75 | 0.6 | on | 1,125 / 894 | +0.062 [+0.034, +0.087] | +0.031 [+0.006, +0.057] | +0.144 [+0.078, +0.220] |

**Readings.**

- The declared configuration is selected in 48 of the 200 splits. The most
  frequent selection, in 76, is the same configuration with `min_share` 0.5.
- Every split selects a floor and all but one the exemption. The share
  threshold is not identified: 0.5 in 86 splits, 0.75 in 79, 0.9 in 20 and none
  in 15.
- The held-out change in corrected F1 of each split's own selection is positive
  in all 200 splits (+0.004 to +0.045, median +0.027) and its interval excludes
  zero in 147. Seed 1, the repository's default split, gives +0.034, which 27
  of the 200 splits reach. The splits share plots, so they are not independent
  tests.
- With a site left out the change is positive at every site but excludes zero
  only at ABBY (+0.062 [+0.034, +0.087]), where the detection count rises by a
  quarter and corrected recall by 0.144. At WREF the configuration selected
  without it removes 28% of the detections for +0.067 corrected precision and
  −0.037 corrected recall.

## Censused subplots

The scores above are for the nominal plot core, where precision is a lower
bound: part of each plot was never censused, and a detection there counts as
false. The [censused-subplot study](census-support-results.md) scores
detections only inside surveyed subplots. The arm's persisted detections at the
declared configuration were scored that way on the 57 plots that study admits,
at native density, against the paper runs' `multichm`. These are plain scores:
the censused scorer has no chance null. Intervals are paired plot-bootstrap
percentiles as above.

| Scope | Plots | Stems | Detections, gated / stock | Precision, gated / stock | Recall, gated / stock | F1, gated / stock | Change in F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| All admitted plots | 57 | 1,190 | 720 / 866 | 0.749 / 0.636 | 0.538 / 0.563 | 0.626 / 0.597 | +0.029 [−0.006, +0.062] |
| Validation plots among them | 31 | 706 | 413 / 488 | 0.772 / 0.678 | 0.528 / 0.561 | 0.627 / 0.614 | +0.013 [−0.034, +0.059] |
| California, all admitted | 12 | 135 | 96 / 108 | 0.635 / 0.630 | 0.578 / 0.630 | 0.605 / 0.630 | −0.024 [−0.064, +0.008] |
| WREF, all admitted | 28 | 642 | 271 / 463 | 0.768 / 0.624 | 0.375 / 0.526 | 0.504 / 0.571 | −0.067 [−0.100, −0.029] |
| ABBY, all admitted | 17 | 413 | 353 / 295 | 0.765 / 0.658 | 0.777 / 0.598 | 0.771 / 0.626 | +0.145 [+0.097, +0.192] |

Every row but the second includes calibration plots and is in sample for the
selection.

- Precision rises from 0.636 to 0.749 (+0.112 [+0.072, +0.160]) on all admitted
  plots, and by 0.094 [0.027, 0.149] on the validation plots among them. The
  precision gain of the nominal-core scores is not an artefact of the
  uncensused area.
- F1 changes by +0.029 [−0.006, +0.062] on all admitted plots and by +0.013
  [−0.034, +0.059] on the validation plots. Neither excludes zero, as with
  plain F1 in the nominal core.
- The two Washington sites differ more sharply here than in the nominal core.
  At WREF the arm keeps 271 of 463 detections; recall falls from 0.526 to 0.375
  and F1 by 0.067 [0.029, 0.100]. At ABBY it places 353 detections against
  295; recall rises from 0.598 to 0.777 and F1 by 0.145 [0.097, 0.192]. On the
  validation plots alone the same holds: −0.091 [−0.143, −0.042] at WREF (15
  plots) and +0.140 [+0.063, +0.196] at ABBY (9 plots).

## Against CHM-VWF

Validation plots, five sites. CHM-VWF is scored from the paper runs' persisted
detections on the same shifts:

| Pulses/m² | Corrected F1, CHM-VWF | Stock `multichm` | Gated | Gated minus CHM-VWF | Stock minus CHM-VWF |
| --- | --- | --- | --- | --- | --- |
| 9.8 (native) | 0.189 | 0.166 | 0.200 | +0.011 [−0.015, +0.033] | −0.024 [−0.054, +0.005] |
| 4.7 | 0.150 | 0.167 | 0.188 | +0.038 [+0.009, +0.069] | +0.017 [−0.017, +0.053] |
| 2.5 | 0.155 | 0.142 | 0.184 | +0.029 [+0.000, +0.057] | −0.013 [−0.045, +0.019] |
| 1.3 | 0.153 | 0.155 | 0.167 | +0.015 [−0.013, +0.044] | +0.002 [−0.025, +0.032] |
| 0.6 | 0.157 | 0.142 | 0.171 | +0.013 [−0.023, +0.044] | −0.015 [−0.052, +0.016] |

At native density the gated arm is level with CHM-VWF (+0.011 [−0.015,
+0.033]), where stock `multichm` is 0.024 behind it; neither interval excludes
zero. Below native density the baseline is the paper's declared CHM-VWF, which
smooths its canopy model there and under-detects (see the
[baseline smoothing sensitivity](baseline-smoothing-sensitivity-results.md)).
The gated arm's corrected lead over it excludes zero at 4.7 pulses/m². At 2.5
pulses/m² the lower bound sits on zero (+0.0003, inside the bootstrap's Monte
Carlo error).

## Selecting on plain F1

With plain F1 as the criterion the same calibration plots select `zmin` 5 m,
no share gate, `cover_min` 0.6 and the exemption. On the validation plots at
native density that configuration places more detections than stock (1,575
against 1,472) and changes F1 by +0.037 [+0.021, +0.055] and corrected F1 by
+0.028 [+0.015, +0.040]. Plain F1 keeps the floor and the exemption and drops
the share gate.

Selecting on all 106 plots, which is not a held-out result, gives `min_share`
0.5 in place of 0.75 and the other three values unchanged.

## Limits

- **Features chosen on all plots.** See the exploratory provenance above.
- **The share gate is not established.** Its own change in corrected F1 is not
  separable from zero, it lowers plain F1 and recall, and the splits do not
  agree on its threshold. The declared configuration keeps it because the
  calibration selected it; dropping it now would be a selection on the
  validation plots.
- **Cover and region are confounded.** Site median cover at native density is
  0.91 at WREF and 0.85 at ABBY against 0.50 at TEAK, 0.41 at SOAP and 0.31 at
  SJER. The switch may stand for forest type rather than canopy closure; only
  8 California plots are closed and 2 Washington plots open.
- **Cover on the decimated rungs.** Cover is measured on each rung's own clip.
  The ladder's decimation equalizes point density over 5 m cells, which removes
  a larger share of returns from canopy than from open ground. Measured cover
  is 0.05 to 0.06 lower on the decimated rungs than at native density (lower in
  105 of 106 plots at 4.7 pulses/m²), and 62 or 63 plots count as closed there
  against 69 at native density. A natively sparse flight has no such bias, and
  the arm has not been run on one.
- **Sensor.** The first-return share depends on how many returns per pulse a
  sensor records. All 69 closed plots were flown with one instrument (Optech
  Galaxy Prime, July 2021). SJER, the only site flown with another lidar (RIEGL
  Q780), has no closed plot, so the share gate and the exemption are untested
  on a second sensor.
- **One switch per clip.** A clip that mixes open and closed patches is treated
  as one stand.
- **Reference.** The reference holds live stems of at least 10 cm DBH, so the
  5 m floor says nothing about smaller trees. The null is conservative, as the
  chance-agreement study explains. Outside the censused-subplot section the
  scores are for the nominal plot core.

## Outputs

Under `work/multichm_gated_runs/neon/multichm_gated/`:

- `cells.csv` holds the observed and null counts of every cell and
  configuration, and CHM-VWF.
- `selection.csv` and `validation.csv` hold every selection and contrast above,
  every split included.
- `region_differences.csv` holds the differences between the regions,
  `grid_contrasts.csv` every grid configuration against stock, and
  `census_scores.csv` and `census_contrasts.csv` the censused-subplot scores.
- `declared_config.json` holds the declared configuration, and `tables.md` the
  tables in full.

The arm's own rows and detections at the declared configuration are in
`work/multichm_gated_runs/neon/<SITE>/multichm_gated_results.csv` and
`multichm_gated_detections/`; they equal the declared configuration's rows of
`cells.csv` in every cell.

## Reproduce

```sh
J=$PWD/work/multichm_gated_runs; B=$PWD/work/paper_runs
mkdir -p $J/neon; ln -sfn $PWD/work/neon/frozen_2021 $J/neon/frozen_2021
for s in SJER SOAP TEAK WREF ABBY; do
  mkdir -p $J/neon/$s
  for f in ground_truth_stems.csv plot_centroids.csv; do ln -sfn $B/neon/$s/$f $J/neon/$s/$f; done
done
CLAUDE_JOB_DIR=$J Rscript scripts/calval_multichm_gated.R CORES=24 BASE=$B
for s in SJER SOAP TEAK WREF ABBY; do
  CLAUDE_JOB_DIR=$J Rscript scripts/detect_multichm_gated_sweep.R SITE=$s CORES=6
done
CLAUDE_JOB_DIR=$J Rscript scripts/score_census_support.R ARMS=multichm_gated \
  DECLARATION=docs/census-support-declaration-nearest.json \
  SUPPORT=$B/reference_support_census_event \
  OUT=$J/census_support_scores/nearest_ladder
CLAUDE_JOB_DIR=$J Rscript scripts/calval_multichm_gated.R STAGE=analyze BASE=$B
```

The study takes about six minutes on 24 cores. With `BASE` it also checks
that the stock configuration reproduces the paper runs' `multichm` detections
and null in every cell, and stops if it does not. The censused-subplot scores
need the arm's persisted detections, so the scorer runs after the arm, and the
last command adds them to the analysis; `STAGE=analyze` re-runs the selections
and tables from `cells.csv` in under a minute.
[calval_multichm_gated.R](../scripts/calval_multichm_gated.R) is the study,
[detect_multichm_gated_sweep.R](../scripts/detect_multichm_gated_sweep.R) the
arm and [multichm_gated_lib.R](../scripts/multichm_gated_lib.R) the detector.
