# Gated multichm: calibration and validation

Checked on 13 November 2026 on the frozen five-site `adopted` population (106
plots, 2,525 stems). `multichm_gated` is a post hoc arm. It is not one of the
paper's twelve arms, the master tables do not include it, and the declared
`multichm` arm is unchanged.

`multichm` (lidRplugins) finds local maxima on the canopy surface, strips the
top of the cloud and searches again, layer by layer. It then keeps a peak unless
a taller kept peak lies within 3 m horizontally or within 5 m in three
dimensions. The arm rests on three premises about closed stands, none of which
the study measures directly. Two come from a first exploratory pass. Peaks
found after stripping (the deeper layers) often sit inside the crowns of trees
already found. And the distance filter removes neighbouring surface peaks of
similar height, which in a dense stand are often separate trees. The third
comes from later passes: the first premise holds mainly where crowns are large
and far apart, and where they are small and close together many deeper-layer
peaks are trees.

## The arm

The arm keeps the package's candidate search and changes what is accepted:

- **Height floor.** A deeper-layer peak must be at least `zmin` high, in every
  stand.
- **First-return share.** In a closed stand of widely spaced crowns, a
  deeper-layer peak is kept only when at least `min_share` of the returns
  around it are first returns, so the spot is lit from above. The returns
  counted lie within 1 m of the peak horizontally and within 1 m of its own
  top return vertically.
- **Surface exemption.** In a closed stand, whatever its crown spacing,
  surface-layer peaks skip the distance filter when `surface_exempt` is on.
  They still exclude lower deeper-layer peaks near them; a taller deeper-layer
  peak and an exempt surface peak beside it are both kept.
- **Closed stand.** A clip (plot core plus 25 m buffer) is closed when its
  canopy cover, the share of first returns higher than 2 m, is at least
  `cover_min`.
- **Widely spaced crowns.** A clip's crowns are widely spaced when its crown
  spacing is at least `spacing_min`. Crown spacing is the side of the square
  each crown would occupy, √(area / crowns). The crowns are counted on a canopy
  surface with 1 m cells, triangulated from the highest first return of each
  cell: a crown is a local maximum of that surface, at least 2 m high, within
  a circular window 5 m across. Only maxima whose whole window lies on the
  surface are counted, and the area is that of the cells whose whole window
  does, so no crown is judged on a window cut short by the clip's edge. With
  `spacing_min` 0 the share gate applies in every closed stand.

Crown spacing describes the canopy surface, not the stems. A window 5 m across
does not separate crowns closer than about 2.5 m, and trees under the canopy do
not count. At native density it runs from 5.0 to 12.8 m over the 106 plots, on
35 to 259 crowns per clip. Among the closed plots the median is 6.3 m at ABBY
and 8.5 m at WREF.

With all of these switched off the arm is `multichm`: it returns the same tree
tops as the paper runs in all 530 cells (106 plots at five densities), and its
scores and chance null equal theirs cell by cell. The candidate search runs on
one lidR thread, because lidR breaks tied heights differently from call to call
on several; the crown count is pinned to one thread too. The declared
configuration needs
return numbers: a configuration that reads the first-return share, the canopy
cover or the crown spacing stops on a cloud without them.

## Calibration

The thresholds come from a grid of 447 configurations. The first 87 have no
spacing condition: `zmin` 0, 5 or 8 m; `min_share` 0, 0.5, 0.75 or 0.9;
`cover_min` 0 (every stand counts as closed), 0.6, 0.7 or 0.8;
`surface_exempt` off or on. Without a share gate and without the exemption
the cover decides nothing, so those configurations appear once per `zmin`,
which leaves 87 of the 96 combinations. The other 360 are the 72 of those with
a share gate, each at `spacing_min` 7, 7.5, 8, 8.5 and 9 m. Each site's plots
are split into calibration and validation halves by the stratified split of the
[calibration/validation study](calibration-validation-results.md) (seed 1),
giving 57 calibration and 49 validation plots. The configuration with the
highest chance-corrected F1 at native density on the calibration plots is
selected. Ties go to the configuration listed first in the grid, where those
without a spacing condition come before those with one.

Chance-corrected F1 is (F1 − null F1) / (1 − null F1). The null is the score of
the same detections under 200 random shifts per plot, as in the
[chance-agreement study](matcher-robustness-results.md#chance-agreement).
Plain F1 is not the criterion because it rewards the number of detections:
shifted copies reach 70 to 79% of the F1 of every arm but one at native
density. The selection under plain F1 is reported
[below](#selecting-on-plain-f1).

The selected configuration is `zmin` 5 m, `min_share` 0.75, `cover_min` 0.6,
`surface_exempt` on and `spacing_min` 8 m. It is the arm's declared
configuration (`MCG_DECLARED` in
[multichm_gated_lib.R](../scripts/multichm_gated_lib.R)). On the calibration
plots it raises corrected F1 from 0.187 to 0.224; that figure is in sample. At
native density 69 of the 106 plots are closed and 36 of those have crowns at
least 8 m apart, so the share gate applies in 36 plots: 23 at WREF, 5 each at
ABBY and TEAK and 3 at SOAP. The 33 closed plots it leaves out are 18 at ABBY
and 15 at WREF.

**Exploratory provenance.** Several exploratory passes shaped the arm, and all
of them read the validation plots.

- The form of the gate, the first 87 grid configurations and the criterion
  were fixed after a pass over all 106 plots and before any calibration was
  run.
- The crown-spacing switch, its measure and its five grid values were added
  after later passes. The configuration declared until then had the same
  floor, share threshold, cover threshold and exemption, with the share gate
  in every closed stand (`z5_s0.75_c0.6_e1`). Those passes read its scores on
  all 106 plots, in the nominal plot cores and inside the censused subplots,
  first by stand top height and then by crown density.
- They also read the arm's detection counts on four closed Douglas-fir plots
  outside the benchmark, which have no field reference. A switch on stand top
  height was tried first. Calibrated on the same plots, it applied the share
  gate in closed stands at least 45 m tall, which left it off on those four
  plots (28 to 37 m tall), where the arm placed about twice as many tree tops
  inside the plots as a point-cloud local-maximum filter (89 against 37 over
  the four). Crown spacing took its place because it puts those plots, with
  crowns 8.9 to 10.5 m apart, with the tall NEON stands. No score decided
  between the two features: the height switch gave the same held-out change
  in corrected F1 (+0.034) and a higher plain F1 inside the censused subplots
  (0.669 against 0.657 on all admitted plots). Neither the four plots nor the
  height switch's code are in the repository, so the four plots' heights,
  crown spacings and counts and the height switch's two scores (+0.034 and
  0.669) cannot be regenerated from it.

The held-out scores below therefore test only the selection within the grid,
not the grid's values or the choice of features. For the crown-spacing switch
they test less than that: the passes that suggested it had seen how the gate
scored on the validation plots.

The held-out scores could hardly have come out negative. On the validation
plots 434 of the 446 non-stock grid configurations score above stock in
corrected F1 (median +0.021; the lower bound of 255 intervals is above zero,
by more than its Monte Carlo error in 247, and no interval lies below zero),
and the selected one (+0.034) ranks 43rd of the 447 configurations. What the
validation half does test is whether the calibration ranking carries over:
across the grid the calibration and validation changes correlate at 0.73. Over
the 200 splits of the [Stability](#stability) section that correlation has a
median of 0.63 (0.44 to 0.75 for the middle 80% of the splits; 29 splits
exceed the default split's 0.73). A split's own selection ranks at a median of
49th of 447 on its validation half, and a median of 430 of the 446
configurations score above stock there (301 at the fewest). An untouched test
needs plots outside these five sites.

## Held-out scores

Validation plots only, the declared configuration against stock `multichm`,
nominal plot core. Intervals are paired plot-bootstrap percentiles (1,000 draws,
plots resampled within site, the same draws for both arms and for observed and
null counts). They are not adjusted for the number of contrasts. With 1,000
draws the Monte Carlo standard error of a bound is about 2% of the interval's
width, and a bound that close to zero is read below as sitting on zero.
"Corrected" means corrected for chance as above.

At native density (9.8 pulses/m²):

| Scope | Plots | Stems | Detections, gated / stock | F1, gated / stock | Corrected F1, gated / stock | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Five sites | 49 | 1,172 | 1,372 / 1,472 | 0.501 / 0.468 | 0.200 / 0.166 | +0.034 [+0.014, +0.053] | +0.037 [+0.014, +0.061] | +0.025 [−0.006, +0.056] |
| California | 19 | 266 | 330 / 382 | 0.435 / 0.436 | 0.260 / 0.246 | +0.013 [−0.006, +0.028] | +0.022 [+0.009, +0.036] | −0.020 [−0.059, +0.003] |
| Washington | 30 | 906 | 1,042 / 1,090 | 0.521 / 0.479 | 0.178 / 0.133 | +0.044 [+0.019, +0.068] | +0.046 [+0.017, +0.077] | +0.038 [−0.002, +0.077] |

By site, on each site's validation plots:

| Site | Plots | Stems | Detections, gated / stock | Change in F1 | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SJER | 3 | 23 | 64 / 82 | +0.044 [+0.022, +0.063] | +0.047 [+0.026, +0.070] | +0.041 [+0.022, +0.061] | −0.099 [−0.178, +0.000] |
| SOAP | 8 | 89 | 141 / 161 | +0.002 [−0.038, +0.020] | +0.012 [−0.026, +0.034] | +0.016 [−0.010, +0.032] | −0.031 [−0.097, +0.006] |
| TEAK | 8 | 154 | 125 / 139 | −0.020 [−0.074, +0.014] | +0.002 [−0.047, +0.027] | +0.010 [−0.022, +0.058] | −0.003 [−0.052, +0.017] |
| WREF | 18 | 565 | 495 / 675 | +0.023 [−0.009, +0.049] | +0.042 [+0.009, +0.072] | +0.094 [+0.045, +0.165] | −0.016 [−0.067, +0.017] |
| ABBY | 12 | 341 | 547 / 415 | +0.062 [+0.002, +0.109] | +0.058 [+0.012, +0.098] | +0.028 [−0.017, +0.063] | +0.166 [+0.054, +0.300] |

Change in corrected F1 down the ladder, with the five-site detection counts and
the difference between the regions (both regions resampled together):

| Pulses/m² | Five sites | California | Washington | Washington minus California | Detections, gated / stock |
| --- | --- | --- | --- | --- | --- |
| 9.8 (native) | +0.034 [+0.014, +0.053] | +0.013 [−0.006, +0.028] | +0.044 [+0.019, +0.068] | +0.031 [+0.000, +0.059] | 1,372 / 1,472 |
| 4.7 | +0.027 [+0.001, +0.053] | −0.009 [−0.042, +0.013] | +0.042 [+0.007, +0.074] | +0.050 [+0.013, +0.097] | 1,385 / 1,518 |
| 2.5 | +0.035 [+0.017, +0.057] | +0.020 [+0.002, +0.047] | +0.042 [+0.018, +0.065] | +0.022 [−0.013, +0.056] | 1,407 / 1,467 |
| 1.3 | +0.017 [−0.007, +0.041] | −0.013 [−0.043, +0.010] | +0.030 [−0.001, +0.060] | +0.043 [+0.005, +0.084] | 1,485 / 1,425 |
| 0.6 | +0.018 [−0.003, +0.044] | −0.012 [−0.036, +0.003] | +0.034 [+0.006, +0.066] | +0.047 [+0.014, +0.087] | 1,669 / 1,371 |

**Readings.**

- At native density held-out corrected F1 rises from 0.166 to 0.200 (+0.034
  [+0.014, +0.053]). Corrected precision rises by 0.037 [0.014, 0.061]; the
  change in corrected recall, +0.025 [−0.006, +0.056], includes zero. The arm
  places 7% fewer detections than stock (1,372 against 1,472), and plain F1
  rises by 0.032 [0.010, 0.057]. With the share gate in every closed stand,
  as declared before the crown-spacing switch, the same floor, gate and
  exemption gave the same +0.034 ([+0.005, +0.059]) and +0.015 [−0.012,
  +0.042] in plain F1. The switch was added after later passes had read these
  plots; see
  [What the crown-spacing switch changes](#what-the-crown-spacing-switch-changes).
- The change is +0.044 [+0.019, +0.068] in Washington and +0.013 [−0.006,
  +0.028] in California, where its interval includes zero. The difference
  between the regions, +0.031 [+0.000, +0.059], has its lower bound on zero at
  native density. It excludes zero at 4.7, 1.3 and 0.6 pulses/m² (+0.043 to
  +0.050) and includes it at 2.5. At native density 61 of the 63 Washington
  plots are closed at a cover of 0.6, against 8 of the 43 California plots.
- The two Washington sites gain in different ways. At WREF, Douglas-fir and
  western hemlock up to old growth (clip top heights from 15 to 58 m), the arm
  places 495 detections against 675: corrected precision rises by 0.094
  [0.045, 0.165], plain recall falls from 0.542 to 0.481, and the change in
  corrected recall, −0.016 [−0.067, +0.017], includes zero. At ABBY, managed
  Douglas-fir, it places 547 detections against 415 and corrected recall
  rises by 0.166 [0.054, 0.300]. The change in corrected F1 excludes zero at
  WREF and ABBY, and at neither SOAP nor TEAK. SJER's interval excludes zero
  too, but its validation half holds 3 plots, too few for the interval to
  carry weight.
- Down the ladder the five-site change stays positive (+0.017 to +0.035). It
  excludes zero at native density and at 2.5 pulses/m²; at 4.7 its lower bound
  sits on zero, and at 1.3 and 0.6 the interval includes zero. California's
  change is negative on three of the four decimated rungs (−0.009 to −0.013),
  none of the three excluding zero, with lower corrected recall (−0.063
  [−0.119, −0.029] at 4.7 pulses/m²).
- At 0.6 pulses/m² the arm places more detections than stock (1,669 against
  1,371): the exemption admits more surface peaks than the floor and the gate
  remove. Corrected recall rises by 0.061 [0.030, 0.096] there and corrected
  precision does not move (+0.003 [−0.018, +0.029]).
- On all 106 plots at native density the declared configuration scores F1 0.491
  and corrected F1 0.213, against 0.456 and 0.178 for stock (+0.035 [+0.022,
  +0.047] corrected, +0.035 [+0.020, +0.049] plain). This is not a held-out
  score: 57 of those plots selected the configuration. By site it changes the
  detection count from 1,312 to 964 at WREF, 894 to 1,170 at ABBY, 388 to 342
  at SOAP, 385 to 329 at TEAK and 178 to 146 at SJER.

## What each part does

Validation plots, native density, five sites. First each reduced configuration
against stock `multichm` (1,472 detections). The fourth row is the
configuration declared before the crown-spacing switch:

| Configuration | Detections | Change in F1 | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- |
| Floor only | 1,332 | +0.019 [+0.013, +0.024] | +0.015 [+0.009, +0.021] | +0.022 [+0.015, +0.031] | −0.003 [−0.010, +0.004] |
| Floor and exemption | 1,575 | +0.037 [+0.021, +0.055] | +0.028 [+0.015, +0.040] | +0.016 [+0.003, +0.027] | +0.056 [+0.031, +0.084] |
| Floor and spacing-switched share gate | 1,124 | +0.011 [−0.009, +0.027] | +0.021 [+0.006, +0.038] | +0.050 [+0.028, +0.077] | −0.026 [−0.045, −0.009] |
| Floor, share gate in every closed stand, exemption | 1,264 | +0.015 [−0.012, +0.042] | +0.034 [+0.005, +0.059] | +0.050 [+0.020, +0.079] | +0.003 [−0.033, +0.036] |
| Exemption only | 1,682 | +0.023 [+0.008, +0.040] | +0.015 [+0.003, +0.027] | +0.000 [−0.012, +0.010] | +0.059 [+0.035, +0.087] |
| All four (declared) | 1,372 | +0.032 [+0.010, +0.057] | +0.034 [+0.014, +0.053] | +0.037 [+0.014, +0.061] | +0.025 [−0.006, +0.056] |

Then what each part adds: the declared configuration against a reduction of
it. The first three rows take one part away. The cover switch row applies the
same gate and exemption in every stand (`cover_min` 0, the gate still only
where crowns are at least 8 m apart). The spacing switch row applies the share
gate in every closed stand (`spacing_min` 0). The last row reduces the declared
configuration to its floor alone.

| Part | Detections, declared / reduced | Change in F1 | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- |
| Floor | 1,372 / 1,461 | +0.012 [+0.008, +0.017] | +0.010 [+0.005, +0.016] | +0.016 [+0.010, +0.025] | −0.004 [−0.011, +0.001] |
| Share gate | 1,372 / 1,575 | −0.005 [−0.019, +0.009] | +0.006 [−0.008, +0.023] | +0.021 [+0.004, +0.043] | −0.031 [−0.053, −0.013] |
| Exemption | 1,372 / 1,124 | +0.022 [+0.004, +0.040] | +0.013 [−0.003, +0.027] | −0.013 [−0.034, +0.005] | +0.051 [+0.028, +0.075] |
| Cover switch | 1,372 / 1,421 | +0.013 [+0.005, +0.021] | +0.014 [+0.004, +0.024] | +0.013 [+0.004, +0.025] | +0.014 [−0.010, +0.032] |
| Spacing switch | 1,372 / 1,264 | +0.017 [+0.007, +0.031] | −0.000 [−0.016, +0.017] | −0.013 [−0.031, +0.004] | +0.022 [+0.004, +0.045] |
| Share gate and exemption together | 1,372 / 1,332 | +0.014 [−0.010, +0.038] | +0.019 [−0.002, +0.039] | +0.014 [−0.012, +0.042] | +0.028 [−0.003, +0.056] |

The detection counts in the bullets below are net changes. The distance filter
runs after the gate, so a peak the gate removes can let a lower neighbour
through, and an exempted surface peak can exclude one.

- The floor's own contribution to corrected F1 excludes zero on the validation
  plots (+0.010 [+0.005, +0.016]) and on the calibration plots (+0.008
  [+0.002, +0.015]). It removes 89 detections at no cost in corrected recall.
- The share gate, confined to closed stands of widely spaced crowns, removes
  203 of 1,575 detections. Corrected precision rises by 0.021 [0.004, 0.043]
  and corrected recall falls by 0.031 [0.013, 0.053]. Its own change in
  corrected F1, +0.006 [−0.008, +0.023], is not separable from zero on the
  validation plots; on the calibration plots it is +0.016 [+0.006, +0.027].
- The exemption adds 248 detections to the floor and share gate. Corrected
  recall rises by 0.051 [0.028, 0.075] and corrected precision does not move
  (−0.013 [−0.034, +0.005]). Its own change in corrected F1 is +0.013 [−0.003,
  +0.027] on the validation plots and +0.012 [−0.002, +0.026] on the
  calibration plots. Alone against stock it adds 210 detections and 0.059
  corrected recall at unchanged corrected precision, so the distance filter
  had been removing real neighbouring trees.
- The cover switch adds +0.014 [+0.004, +0.024] on the validation plots and
  +0.012 [+0.001, +0.024] on the calibration plots. The two configurations
  differ only on open plots, and 35 of the 37 open plots are in California
  (see [Limits](#limits)), so the switch cannot be told from the region. At
  native density 33 of the 37 open plots have crowns at least 8 m apart, so
  without the cover threshold the share gate would apply in most of them.
- The spacing switch adds 108 detections. Corrected recall rises by 0.022
  [0.004, 0.045], the change in corrected precision (−0.013 [−0.031, +0.004])
  includes zero, and corrected F1 does not move (−0.000 [−0.016, +0.017]). On
  the calibration plots its own change is +0.010 [+0.001, +0.019], which is in
  sample. The [next section](#what-the-crown-spacing-switch-changes) looks at
  it more closely.
- Together the share gate and the exemption add +0.019 [−0.002, +0.039] in
  corrected F1 to the floor alone on the validation plots, which includes
  zero, and +0.027 [+0.011, +0.047] on the calibration plots. Plain F1 does
  not move on the validation plots (+0.014 [−0.010, +0.038]). The validation
  plots do not establish a gain beyond the floor's.

The crown-spacing switch changes little of what the other parts add. The table
sets each part's own change in corrected F1 under the declared configuration
against the same part under the reference configuration, which has the share
gate in every closed stand (`z5_s0.75_c0.6_e1`). Validation plots, native
density:

| Part | With the spacing switch | Without it |
| --- | --- | --- |
| Floor | +0.010 [+0.005, +0.016] | +0.008 [+0.004, +0.013] |
| Share gate | +0.006 [−0.008, +0.023] | +0.007 [−0.018, +0.027] |
| Exemption | +0.013 [−0.003, +0.027] | +0.007 [−0.008, +0.022] |
| Cover switch | +0.014 [+0.004, +0.024] | +0.014 [+0.004, +0.025] |
| Share gate and exemption together | +0.019 [−0.002, +0.039] | +0.020 [−0.010, +0.046] |

- What the share gate and the exemption add to the floor together has nearly
  the same point estimate either way (+0.019 and +0.020), and neither interval
  excludes zero.
- The share gate's own change is as small with the switch as without it. With
  the switch the gate removes 203 detections instead of 311.

The same contrasts down the ladder, as the change in corrected F1 on the
validation plots:

| Pulses/m² | Floor | Share gate | Exemption | Cover switch | Spacing switch | Share gate and exemption together |
| --- | --- | --- | --- | --- | --- | --- |
| 9.8 (native) | +0.010 [+0.005, +0.016] | +0.006 [−0.008, +0.023] | +0.013 [−0.003, +0.027] | +0.014 [+0.004, +0.024] | −0.000 [−0.016, +0.017] | +0.019 [−0.002, +0.039] |
| 4.7 | +0.002 [−0.007, +0.009] | +0.014 [−0.006, +0.035] | +0.015 [−0.002, +0.034] | +0.014 [−0.000, +0.030] | +0.006 [−0.003, +0.017] | +0.025 [−0.001, +0.051] |
| 2.5 | +0.009 [+0.003, +0.015] | +0.014 [+0.000, +0.032] | +0.012 [−0.002, +0.028] | +0.013 [+0.004, +0.023] | −0.006 [−0.017, +0.004] | +0.027 [+0.008, +0.050] |
| 1.3 | +0.005 [−0.001, +0.012] | +0.007 [−0.005, +0.019] | +0.010 [−0.009, +0.029] | +0.013 [−0.000, +0.029] | +0.005 [+0.001, +0.011] | +0.012 [−0.012, +0.035] |
| 0.6 | +0.002 [−0.002, +0.006] | +0.007 [−0.002, +0.017] | +0.011 [−0.009, +0.036] | +0.016 [+0.002, +0.033] | −0.010 [−0.021, −0.001] | +0.015 [−0.006, +0.040] |

- No part's own contribution excludes zero on every rung. The floor's does at
  native density and at 2.5 pulses/m². The cover switch's does at native
  density, 2.5 and 0.6, and its lower bound sits on zero at 4.7 and 1.3. The
  share gate's and the exemption's do on none; the share gate's lower bound
  sits on zero at 2.5.
- The spacing switch's own contribution has no steady sign (−0.010 to +0.006).
  It narrowly excludes zero twice, in opposite directions: +0.005 [+0.001,
  +0.011] at 1.3 pulses/m² and −0.010 [−0.021, −0.001] at 0.6.
- Together the share gate and the exemption add to the floor alone on every
  rung in the point estimate (+0.012 to +0.027). The interval excludes zero at
  2.5 pulses/m² only, and at 4.7 its lower bound sits on zero. Without the
  spacing switch it also excludes zero at 2.5 only, with its lower bound on
  zero at 0.6.
- Without the spacing switch the share gate's own change excludes zero at 2.5
  and 0.6 pulses/m² (+0.021 [+0.003, +0.040] and +0.017 [+0.005, +0.030]).
  With it the gate applies in fewer plots and its change excludes zero on no
  rung.

## What the crown-spacing switch changes

The reference here is the configuration declared before the crown-spacing
switch: the same floor, share threshold, cover threshold and exemption, with
the share gate in every closed stand (`z5_s0.75_c0.6_e1`). In the nominal plot
core both configurations are scored from the same cells. For the censused
subplots the arm was run once with each configuration, and its persisted
detections were scored the same way. The later exploratory passes read these
validation plots, in the nominal core as inside the censused subplots, so for
the switch none of the scores in this section is held out.

Declared minus reference on the validation plots at native density, nominal
plot core. California is left out: every closed plot there has crowns at least
8 m apart, so the two configurations place the same detections on all 43
California plots, on every rung.

| Scope | Plots | Detections, declared / reference | Change in F1 | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- | --- |
| Five sites | 49 | 1,372 / 1,264 | +0.017 [+0.007, +0.031] | −0.000 [−0.016, +0.017] | −0.013 [−0.031, +0.004] | +0.022 [+0.004, +0.045] |
| Washington | 30 | 1,042 / 934 | +0.021 [+0.007, +0.041] | +0.000 [−0.019, +0.026] | −0.018 [−0.044, +0.006] | +0.026 [+0.001, +0.060] |
| WREF | 18 | 495 / 404 | +0.044 [+0.017, +0.083] | +0.008 [−0.022, +0.056] | −0.042 [−0.090, +0.010] | +0.032 [+0.004, +0.077] |
| ABBY | 12 | 547 / 530 | −0.001 [−0.006, +0.005] | −0.008 [−0.036, +0.009] | −0.008 [−0.030, +0.005] | +0.001 [−0.037, +0.042] |

The same down the ladder, five sites:

| Pulses/m² | Detections, declared / reference | Change in F1 | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- |
| 9.8 (native) | 1,372 / 1,264 | +0.017 [+0.007, +0.031] | −0.000 [−0.016, +0.017] | −0.013 [−0.031, +0.004] | +0.022 [+0.004, +0.045] |
| 4.7 | 1,385 / 1,277 | +0.019 [+0.008, +0.032] | +0.006 [−0.003, +0.017] | −0.004 [−0.012, +0.004] | +0.025 [+0.008, +0.045] |
| 2.5 | 1,407 / 1,327 | +0.008 [+0.001, +0.017] | −0.006 [−0.017, +0.004] | −0.011 [−0.024, −0.001] | +0.003 [−0.007, +0.015] |
| 1.3 | 1,485 / 1,407 | +0.015 [+0.007, +0.024] | +0.005 [+0.001, +0.011] | −0.000 [−0.005, +0.005] | +0.019 [+0.008, +0.031] |
| 0.6 | 1,669 / 1,608 | +0.002 [−0.003, +0.008] | −0.010 [−0.021, −0.001] | −0.011 [−0.021, −0.002] | −0.005 [−0.016, +0.006] |

Inside the censused subplots at native density (plain scores; see
[Censused subplots](#censused-subplots) for the scoring):

| Scope | Plots | Stems | Detections, declared / reference | Precision, declared / reference | Recall, declared / reference | F1, declared / reference | Change in F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| All admitted plots | 57 | 1,190 | 809 / 720 | 0.733 / 0.749 | 0.595 / 0.538 | 0.657 / 0.626 | +0.031 [+0.016, +0.047] |
| Validation plots among them | 31 | 706 | 459 / 413 | 0.763 / 0.772 | 0.585 / 0.528 | 0.662 / 0.627 | +0.035 [+0.012, +0.061] |
| California, all admitted | 12 | 135 | 96 / 96 | 0.635 / 0.635 | 0.578 / 0.578 | 0.605 / 0.605 | +0.000 [+0.000, +0.000] |
| WREF, all admitted | 28 | 642 | 338 / 271 | 0.751 / 0.768 | 0.469 / 0.375 | 0.577 / 0.504 | +0.073 [+0.040, +0.102] |
| ABBY, all admitted | 17 | 413 | 375 / 353 | 0.741 / 0.765 | 0.797 / 0.777 | 0.768 / 0.771 | −0.003 [−0.012, +0.005] |

**Readings.**

- By the study's criterion the two configurations are level. Corrected F1 on
  the validation plots is 0.200 for both (−0.000 [−0.016, +0.017]), and each
  gains +0.034 on stock. The interval of that gain is [+0.014, +0.053] with
  the switch and [+0.005, +0.059] without it.
- The switch moves the arm along the trade between precision and recall. It
  places 108 more detections (9%). Corrected recall rises by 0.022 [0.004,
  0.045], the change in corrected precision (−0.013 [−0.031, +0.004]) includes
  zero, and plain F1 rises by 0.017 [0.007, 0.031]. Chance rises as much as
  the score: the null F1 goes from 0.355 to 0.376 and F1 from 0.484 to 0.501,
  which leaves corrected F1 where it was.
- The change is WREF's. The gate applies in 10 of its 18 validation plots
  instead of all 18, and the arm places 495 detections against 404. Plain
  recall rises from 0.396 to 0.481 and corrected recall by 0.032 [0.004,
  0.077]; the change in corrected precision (−0.042 [−0.090, +0.010]) includes
  zero, and corrected F1 does not move (+0.008 [−0.022, +0.056]). At ABBY the
  gate applies in 2 of the 11 closed validation plots instead of all 11, yet
  the arm places 547 detections against 530: the gate had removed few
  detections from ABBY's closed plots. Corrected F1 does not move there
  either (−0.008 [−0.036, +0.009]).
- Down the ladder the change in corrected F1 has no steady sign. It narrowly
  excludes zero twice, in opposite directions: +0.005 [+0.001, +0.011] at 1.3
  pulses/m² and −0.010 [−0.021, −0.001] at 0.6, where corrected precision
  falls (−0.011 [−0.021, −0.002]) without a gain in corrected recall. Plain F1
  is higher on every rung; its interval excludes zero on the first four
  (+0.008 to +0.019) and not at 0.6 pulses/m² (+0.002 [−0.003, +0.008]).
- Inside the censused subplots F1 is higher by 0.031 [0.016, 0.047] on all
  admitted plots and by 0.035 [0.012, 0.061] on the validation plots among
  them. Recall rises from 0.538 to 0.595 (+0.057 [+0.036, +0.080]) and
  precision falls from 0.749 to 0.733 (−0.016 [−0.031, −0.003]). At WREF
  recall rises from 0.375 to 0.469 and F1 by 0.073 [0.040, 0.102]; on its 15
  validation plots F1 rises by 0.081 [0.032, 0.128]. ABBY's F1 is unchanged,
  and on the California plots the two configurations are the same.
- The censused scores are plain scores, with no chance null, and they agree
  with plain F1 in the nominal core. Like the nominal-core scores above, they
  were read by the exploratory passes, so they are in sample for the choice of
  the switch even on the validation plots. The corrected scores of the nominal
  core are the only ones here that correct for chance, and they do not
  separate the two configurations.

**Other thresholds.** The readings above are for 8 m, the value the default
split selects. The table sets the declared configuration at each of the
grid's values of `spacing_min` against stock, and the declared 8 m against
each of them, as the change in corrected F1 at native density. It is a look at
the validation plots, not a selection.

| `spacing_min` | Closed plots gated, all / validation | Against stock, validation | Against stock, calibration | 8 m minus this, validation | 8 m minus this, calibration |
| --- | --- | --- | --- | --- | --- |
| none | 69 / 32 | +0.034 [+0.005, +0.059] | +0.026 [+0.007, +0.046] | −0.000 [−0.016, +0.017] | +0.010 [+0.001, +0.019] |
| 7 m | 50 / 21 | +0.040 [+0.017, +0.062] | +0.030 [+0.009, +0.051] | −0.006 [−0.018, +0.005] | +0.006 [−0.001, +0.015] |
| 7.5 m | 48 / 20 | +0.038 [+0.015, +0.058] | +0.032 [+0.012, +0.052] | −0.004 [−0.014, +0.007] | +0.005 [−0.003, +0.012] |
| 8 m (declared) | 36 / 15 | +0.034 [+0.014, +0.053] | +0.036 [+0.020, +0.054] | — | — |
| 8.5 m | 26 / 10 | +0.039 [+0.021, +0.057] | +0.033 [+0.017, +0.051] | −0.005 [−0.013, +0.002] | +0.003 [−0.001, +0.008] |
| 9 m | 20 / 6 | +0.031 [+0.015, +0.046] | +0.031 [+0.016, +0.049] | +0.003 [−0.008, +0.017] | +0.005 [+0.001, +0.011] |

- On the calibration plots 8 m scores highest, by margins it cannot resolve
  against its neighbours: +0.005 [−0.003, +0.012] over 7.5 m and +0.003
  [−0.001, +0.008] over 8.5 m. Its margins over no switch and over 9 m
  narrowly exclude zero.
- On the validation plots the order is different. 7 m scores highest against
  stock (+0.040, sixth of the 447 configurations), 8.5 m next (+0.039, tenth)
  and the declared 8 m lower (+0.034, 43rd). No difference between 8 m and
  another value excludes zero there (−0.006 to +0.003).
- The values gate very different numbers of plots: 50 of the 69 closed plots
  at 7 m, 36 at 8 m and 20 at 9 m.
- So the readings above hold for 8 m, and the validation plots do not say
  which threshold is better.

## Stability

Two hundred splits (seeds 1 to 200), each selecting on its own calibration
plots and scored on its own validation plots at native density, five sites.
Values selected, with the number of splits selecting each:

| Parameter | Values selected |
| --- | --- |
| `zmin` | 5 m in 196, 8 m in 4 |
| `min_share` | 0.5 in 54, 0.75 in 84, 0.9 in 62 |
| `cover_min` | 0.6 in 173, 0.7 in 23, 0.8 in 4 |
| `surface_exempt` | on in 198, off in 2 |
| `spacing_min` | none in 2, 7 m in 29, 7.5 m in 28, 8 m in 70, 8.5 m in 70, 9 m in 1 |

Leaving one site out: the configuration is selected on all plots of the other
four sites and scored on the held-out site at native density.

| Held-out site | Plots | `zmin` | `min_share` | `cover_min` | `surface_exempt` | `spacing_min` | Detections, gated / stock | Change in corrected F1 | Change in corrected precision | Change in corrected recall |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SJER | 6 | 5 | 0.75 | 0.6 | on | 8.5 | 146 / 178 | +0.024 [−0.007, +0.054] | +0.025 [+0.008, +0.045] | −0.072 [−0.115, −0.014] |
| SOAP | 18 | 5 | 0.75 | 0.6 | on | 8.5 | 343 / 388 | +0.007 [−0.018, +0.028] | +0.015 [−0.002, +0.033] | −0.036 [−0.082, +0.009] |
| TEAK | 19 | 5 | 0.75 | 0.6 | on | 8 | 329 / 385 | +0.012 [−0.012, +0.032] | +0.031 [+0.004, +0.066] | −0.010 [−0.034, +0.005] |
| WREF | 38 | 5 | 0.5 | 0.6 | on | 7 | 951 / 1,312 | +0.024 [+0.004, +0.043] | +0.070 [+0.045, +0.096] | −0.033 [−0.061, −0.013] |
| ABBY | 25 | 5 | 0.75 | 0.6 | on | 8.5 | 1,178 / 894 | +0.063 [+0.035, +0.089] | +0.028 [+0.003, +0.054] | +0.167 [+0.092, +0.251] |

**Readings.**

- The declared configuration is selected in 21 of the 200 splits. The most
  frequent selection, in 33, is the same configuration with `min_share` 0.5.
- A spacing switch is selected in 198 of the 200 splits, but its threshold is
  not identified: 8 m and 8.5 m in 70 splits each, 7 m in 29 and 7.5 m in 28.
  At native density 50 of the 69 closed plots have crowns at least 7 m apart,
  36 at least 8 m and 26 at least 8.5 m, so the frequent thresholds gate
  different numbers of plots.
- Every split selects a floor and a share gate, and all but two the
  exemption. The share threshold is not identified either: 0.75 in 84 splits,
  0.9 in 62 and 0.5 in 54.
- The held-out change in corrected F1 of each split's own selection is positive
  in all 200 splits (+0.010 to +0.051, median +0.030), and the lower bound of
  its interval is above zero in 186, by more than its Monte Carlo error in
  183. Seed 1, the repository's default split, gives +0.034, which 71 of the
  200 splits reach. The splits share plots, so they are not independent
  tests.
- With a site left out every selection has a spacing switch: at 8.5 m for
  three sites, at 8 m when TEAK is left out and at 7 m when WREF is. The
  change is positive at every site and excludes zero at ABBY (+0.063 [+0.035,
  +0.089]) and at WREF (+0.024 [+0.004, +0.043]). At ABBY the detection count
  rises by 32% and corrected recall by 0.167. At WREF the configuration
  selected without it removes 28% of the detections for +0.070 corrected
  precision and −0.033 corrected recall.

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
| All admitted plots | 57 | 1,190 | 809 / 866 | 0.733 / 0.636 | 0.595 / 0.563 | 0.657 / 0.597 | +0.059 [+0.031, +0.087] |
| Validation plots among them | 31 | 706 | 459 / 488 | 0.763 / 0.678 | 0.585 / 0.561 | 0.662 / 0.614 | +0.048 [+0.007, +0.086] |
| California, all admitted | 12 | 135 | 96 / 108 | 0.635 / 0.630 | 0.578 / 0.630 | 0.605 / 0.630 | −0.024 [−0.064, +0.008] |
| WREF, all admitted | 28 | 642 | 338 / 463 | 0.751 / 0.624 | 0.469 / 0.526 | 0.577 / 0.571 | +0.006 [−0.025, +0.032] |
| ABBY, all admitted | 17 | 413 | 375 / 295 | 0.741 / 0.658 | 0.797 / 0.598 | 0.768 / 0.626 | +0.142 [+0.095, +0.190] |

Every row but the second includes calibration plots and is in sample for the
selection. All of them are in sample for the crown-spacing switch, as the
[provenance](#calibration) explains.

- Precision rises from 0.636 to 0.733 (+0.097 [+0.056, +0.142]) on all admitted
  plots, and by 0.084 [0.021, 0.138] on the validation plots among them. The
  precision gain of the nominal-core scores is not an artefact of the
  uncensused area. It is Washington's: +0.109 [+0.066, +0.160] on its 45
  plots, while on the 12 California plots precision does not move (0.635
  against 0.630).
- Recall does not move on all admitted plots (0.595 against 0.563, +0.032
  [−0.006, +0.070]). It rises at ABBY and falls elsewhere: by 0.058 [0.023,
  0.102] at WREF and by 0.052 [0.007, 0.101] on the California plots.
- F1 rises by 0.059 [0.031, 0.087] on all admitted plots and by 0.048 [0.007,
  0.086] on the validation plots among them. The gain is ABBY's.
- At WREF the arm places 338 detections against 463: precision rises from
  0.624 to 0.751, recall falls from 0.526 to 0.469, and F1 does not move
  (+0.006 [−0.025, +0.032]). At ABBY it places 375 detections against 295;
  recall rises from 0.598 to 0.797 and F1 by 0.142 [0.095, 0.190]. On the
  validation plots alone F1 changes by −0.010 [−0.058, +0.025] at WREF (15
  plots) and by +0.138 [+0.053, +0.200] at ABBY (9 plots).
- On the 12 California plots the arm places 96 detections against 108 and F1
  is lower in the point estimate (0.605 against 0.630, −0.024 [−0.064,
  +0.008]).

## Against CHM-VWF

Validation plots, five sites. CHM-VWF is scored from the paper runs' persisted
detections on the same shifts:

| Pulses/m² | Corrected F1, CHM-VWF | Stock `multichm` | Gated | Gated minus CHM-VWF | Stock minus CHM-VWF |
| --- | --- | --- | --- | --- | --- |
| 9.8 (native) | 0.189 | 0.166 | 0.200 | +0.011 [−0.018, +0.038] | −0.024 [−0.054, +0.005] |
| 4.7 | 0.150 | 0.167 | 0.194 | +0.044 [+0.015, +0.076] | +0.017 [−0.017, +0.053] |
| 2.5 | 0.155 | 0.142 | 0.178 | +0.023 [−0.007, +0.053] | −0.013 [−0.045, +0.019] |
| 1.3 | 0.153 | 0.155 | 0.172 | +0.020 [−0.009, +0.051] | +0.002 [−0.025, +0.032] |
| 0.6 | 0.157 | 0.142 | 0.160 | +0.003 [−0.032, +0.034] | −0.015 [−0.052, +0.016] |

At native density the gated arm is level with CHM-VWF (+0.011 [−0.018,
+0.038]), where stock `multichm` is 0.024 behind it; neither interval excludes
zero. Below native density the baseline is the paper's declared CHM-VWF, which
smooths its canopy model there and under-detects (see the
[baseline smoothing sensitivity](baseline-smoothing-sensitivity-results.md)).
The gated arm's corrected lead over it excludes zero at 4.7 pulses/m² only.

## Selecting on plain F1

With plain F1 as the criterion the same calibration plots select `spacing_min`
8.5 m in place of 8 m, with the other four values unchanged. On the validation
plots that configuration gains +0.039 [+0.021, +0.057] in corrected F1 and
+0.042 [+0.022, +0.064] in plain F1 on stock, with 1,418 detections.

Selecting on all 106 plots, which is not a held-out result, gives 8.5 m as
well.

## Limits

- **Features chosen on all plots.** See the exploratory provenance above.
- **The crown-spacing switch is not established by the held-out criterion.**
  In corrected F1 on the validation plots it changes nothing (−0.000 [−0.016,
  +0.017]). The calibration preferred it by +0.010 [+0.001, +0.019], in
  sample; the splits do not agree on its threshold, and the validation plots
  rank the thresholds differently from the calibration plots. At 8 m it trades
  corrected precision for corrected recall and raises plain F1. Both the
  nominal-core and the censused scores were read before it was added. Inside
  the censused subplots the switch raises F1 at WREF by 0.073 [0.040, 0.102],
  in sample, which brings the arm level with stock there. On the California
  plots it changes nothing: the arm is below stock there in the point
  estimate with or without it. The declared configuration has the switch
  because the calibration selected it.
- **Crown spacing may stand for something else.** Of the 36 plots the share
  gate applies in at native density, 23 are at WREF, and the 33 closed plots
  it leaves out are at ABBY and WREF. Among the closed plots crown spacing
  rises with top height (rank correlation 0.80): the gate applies in 20 of
  the 21 closed plots at least 45 m tall, in 16 of the 37 between 30 and 45 m
  and in none of the 11 under 30 m. So on these sites widely spaced crowns
  cannot be told from a tall stand, and the shortest of the four outside
  plots that suggested the measure, 28 m tall with crowns 8.9 m apart, has no
  counterpart in the benchmark. The reading behind the switch is that widely
  spaced
  surface maxima mean few, large crowns, inside which deeper-layer peaks are
  parts of crowns already found. The study measures neither crown size nor
  stocking, and nothing shows that the peaks the gate removes on the outside
  plots are not trees.
- **The measure has its own scale.** The surface has 1 m cells and the window
  is 5 m across, so the count stops rising where crowns are closer than about
  2.5 m. The benchmark's clips are 70 or 90 m across and hold 35 to 259 crowns
  at native density; the measure has not been tried on smaller clips, where
  fewer crowns are counted. The surface near a clip's edge is triangulated
  from returns inside the clip only, so the edge can still add or remove a
  crown.
- **Plots near the threshold.** The crowns are counted on a 1 m grid fixed by
  the clip's coordinates, so a clip's crown spacing carries an error of its
  own: where the grid falls, or a slightly different clip, changes the count.
  The study does not measure that error. At native density 12 of the 69
  closed plots lie within 0.25 m of 8 m, 10 of them at WREF, and the gate
  state of such plots is partly set by the grid rather than by the stand. The
  switch is a step: a closed plot just under the threshold keeps every
  deeper-layer peak above the floor, and one just over it loses those not lit
  from above.
- **The share gate is not established.** With the crown-spacing switch its own
  change in corrected F1 is not separable from zero at native density (+0.006
  [−0.008, +0.023]), it lowers corrected recall, and the splits do not agree
  on its threshold. On the validation plots it applies in 15 of the 49 plots,
  10 of them at WREF. On the decimated rungs its own change excludes zero on
  none; without the switch it does on two (2.5 and 0.6 pulses/m²).
- **Cover and region are confounded.** Site median cover at native density is
  0.91 at WREF and 0.85 at ABBY against 0.50 at TEAK, 0.41 at SOAP and 0.31 at
  SJER. The switch may stand for forest type rather than canopy closure; only
  8 California plots are closed and 2 Washington plots open.
- **Cover and crown spacing on the decimated rungs.** Both are measured on
  each rung's own clip. The ladder's decimation equalizes point density over
  5 m cells, which removes a larger share of returns from canopy than from
  open ground. Measured cover is 0.04 to 0.05 lower on the decimated rungs
  than at native density (lower in 105 of 106 plots at 4.7 pulses/m²), and 62
  or 63 plots count as closed there against 69 at native density. A natively
  sparse flight has no such bias in cover. Crown spacing is read from a
  surface of first returns, so it may depend on their density as such, not
  only on how the ladder thins. It is 0.1 m lower at the median at 4.7, 2.5
  and 1.3 pulses/m² and unchanged at 0.6, with single plots moving by up to
  1.1 m down and 1.0 m up. The share gate applies in 30 to 33 plots against
  36 at native density, and 5, 6, 9 and 10 plots change gate state at 4.7,
  2.5, 1.3 and 0.6 pulses/m². The 8 m threshold was selected at native
  density, and the arm has not been run on a natively sparse flight.
- **Sensor.** The first-return share depends on how many returns per pulse a
  sensor records. All 69 closed plots were flown with one instrument (Optech
  Galaxy Prime, July 2021). SJER, the only site flown with another lidar (RIEGL
  Q780), has no closed plot, so the share gate and the exemption are untested
  on a second sensor.
- **One switch per clip.** A clip that mixes open and closed patches, or
  crowded and widely spaced crowns, is treated as one stand.
- **Reference.** The reference holds live stems of at least 10 cm DBH, so the
  5 m floor says nothing about smaller trees. The null is conservative, as the
  chance-agreement study explains. Outside the censused-subplot tables the
  scores are for the nominal plot core.

## Outputs

Under `work/multichm_gated_runs/neon/multichm_gated/`:

- `cells.csv` holds the observed and null counts of every cell and
  configuration, and CHM-VWF. `candidates.csv` holds each clip's canopy cover,
  its crown spacing with the number of crowns and their area, and its top
  height, which is recorded and decides nothing.
- `selection.csv` and `validation.csv` hold every selection and, apart from
  those in the files named next, every contrast above, every split included.
- `region_differences.csv` holds the differences between the regions,
  `grid_contrasts.csv` every grid configuration against stock, `seed_grid.csv`
  how each split's calibration ranking carries over to its validation plots,
  `census_scores.csv` and `census_contrasts.csv` the censused-subplot scores
  against stock, and `census_reference_scores.csv` and
  `census_reference_contrasts.csv` those against the reference configuration.
- `declared_config.json` holds the declared configuration, and `tables.md` the
  tables in full.

The arm's own rows and detections at the declared configuration are in
`work/multichm_gated_runs/neon/<SITE>/multichm_gated_results.csv` and
`multichm_gated_detections/`; they equal the declared configuration's rows of
`cells.csv` in every cell. The reference configuration's are under
`work/multichm_gated_reference_runs` in the same layout.

## Reproduce

```sh
J=$PWD/work/multichm_gated_runs; B=$PWD/work/paper_runs
R=$PWD/work/multichm_gated_reference_runs
for d in $J $R; do
  mkdir -p $d/neon; ln -sfn $PWD/work/neon/frozen_2021 $d/neon/frozen_2021
  for s in SJER SOAP TEAK WREF ABBY; do
    mkdir -p $d/neon/$s
    for f in ground_truth_stems.csv plot_centroids.csv; do ln -sfn $B/neon/$s/$f $d/neon/$s/$f; done
  done
done
CLAUDE_JOB_DIR=$J Rscript scripts/calval_multichm_gated.R CORES=24 BASE=$B
for s in SJER SOAP TEAK WREF ABBY; do
  CLAUDE_JOB_DIR=$J Rscript scripts/detect_multichm_gated_sweep.R SITE=$s CORES=6
  CLAUDE_JOB_DIR=$R Rscript scripts/detect_multichm_gated_sweep.R SITE=$s CORES=6 \
    ZMIN=5 MIN_SHARE=0.75 COVER_MIN=0.6 SURFACE_EXEMPT=TRUE SPACING_MIN=0
done
for d in $J $R; do
  CLAUDE_JOB_DIR=$d Rscript scripts/score_census_support.R ARMS=multichm_gated \
    DECLARATION=docs/census-support-declaration-nearest.json \
    SUPPORT=$B/reference_support_census_event \
    OUT=$d/census_support_scores/nearest_ladder
done
CLAUDE_JOB_DIR=$J Rscript scripts/calval_multichm_gated.R STAGE=analyze BASE=$B \
  REFERENCE=z5_s0.75_c0.6_e1 \
  REFERENCE_CENSUS=$R/census_support_scores/nearest_ladder/census_support_scores.csv
```

The study takes about eight minutes on 24 cores. With `BASE` it also checks
that the stock configuration reproduces the paper runs' `multichm` detections
and null in every cell, and stops if it does not. The censused-subplot scores
need the arm's persisted detections, so the scorer runs after the arm, and the
last command adds them to the analysis; `STAGE=analyze` re-runs the selections
and tables from `cells.csv` in under three minutes. `REFERENCE` names the grid
configuration the declared one is set against, and `REFERENCE_CENSUS` the
censused scores of the arm run with it in the second job directory.
[calval_multichm_gated.R](../scripts/calval_multichm_gated.R) is the study,
[detect_multichm_gated_sweep.R](../scripts/detect_multichm_gated_sweep.R) the
arm and [multichm_gated_lib.R](../scripts/multichm_gated_lib.R) the detector.
