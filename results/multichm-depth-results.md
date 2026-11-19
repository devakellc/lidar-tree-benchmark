# Depth-gated multichm: calibration, validation and the arm's configuration

Checked on 19 November 2026 on the frozen five-site `adopted` population (106
plots, 2,525 stems). `multichm_depth` is a post hoc arm that follows
[`multichm_gated`](multichm-gated-results.md). It is not one of the paper's
twelve arms, the master tables do not include it, and the declared `multichm`
and `multichm_gated` arms are unchanged. The study follows a
[protocol](../docs/multichm-depth-protocol.md) fixed before its runs.

`multichm_gated` keeps a deeper-layer peak of `multichm` when enough of the
returns around its top are first returns, and only in closed stands whose
crowns are at least 8 m apart. Its
[confirmation tests](multichm-gated-confirmation-results.md) left three
weaknesses. The 8 m switch is a step on a noisy per-clip number. The
first-return share depends on the flight. And the exemption admits surface
peaks at any distance from a taller one. This study replaces the share gate
and the switch with one measurement in metres: how far a deeper-layer peak
sits under the canopy surface above it.

**Outcome.** The study has two results, and they do not have the same
standing.

- **The family, tested as specified.** A grid of 240 configurations was scored
  on the 57 calibration plots, and the best one was set against the declared
  gated arm once, on the 49 held-out plots. Corrected F1 rises from 0.200 to
  **0.234** (+0.034 [+0.014, +0.055]) with 8% fewer detections. By the
  protocol's rule the selection is better than the declared gated arm. Against
  stock `multichm` it gains +0.068 [+0.044, +0.092]. The gain holds in
  California and in Washington, in closed and in open stands, and at the QL2
  level. On a 2019 flight of the Washington sites and on the sparse California
  flights the selection is not worse.
- **The arm's configuration, chosen afterwards.** The arm does not run that
  selection. It keeps the selection's depth rule, leaves out its spacing rule
  and sets both height floors to 3 m (`k4_r0_z3_f3_l0_c0.6`). The choice was
  made after every result below had been read, so its scores are descriptive.
  Against the declared gated arm it is better or not worse on all eight
  datasets tried, and better over all plots at the QL2 level (+0.013 [+0.004,
  +0.022]) and at 2.5 and 0.6 pulses/m². At native density it is level with
  that arm (+0.006 [−0.004, +0.017] over all plots) and 0.021 below the
  selection. What it offers over the gated arm is not a higher score on these
  plots: it drops the crown-spacing switch and the first-return share with no
  loss measured on any dataset.

What the study carries, part by part:

- **The depth rule.** It replaces the share gate and the crown-spacing switch
  and needs neither return numbers nor a per-clip crown count.
  On the held-out plots it adds +0.011 [−0.006, +0.028] over what it
  replaces. Over all plots it is better at 2.5 and 0.6 pulses/m² and level
  elsewhere, except on the sparse California flights, where its interval is
  too wide to read (−0.010 [−0.025, +0.002]). It finds fewer of the stems of
  20 m and more than the gated arm does.
- **The floor on surface peaks.** A 5 m floor in place of none is the one
  change that is established on its own: +0.015 [+0.009, +0.022] on the
  held-out plots, and positive with an interval above zero on every other
  dataset. Most of it is in open stands (+0.039 [+0.023, +0.057], against
  +0.008 [+0.002, +0.015] in closed stands). A reference of stems of 10 cm
  diameter or more seldom credits a detection under 5 m, so the gain says as
  much about the reference as about the detector.
- **The spacing rule.** One horizontal rule of 2.5 m for every top was
  selected in 176 of 200 splits, yet its own contribution spans zero on the
  held-out plots (+0.007 [−0.004, +0.019]).
  Outside the 2021 native clips it adds nothing: its change lies between
  −0.012 and +0.007 on the thinned clips, at the QL2 level and on the two
  other flights, and every one of those intervals reaches zero.
- **The lowest trees.** No configuration, stock included, finds the reference
  stems under 5 m above the chance rate; there are 74 of them, 11 under 3 m.
  Stems of 5 to 10 m are found above chance by every configuration. The floor
  is therefore a statement of what counts as a tree, which these plots cannot
  test.
- **Intermediate crowns.** Their chance-corrected recall is 0.04 to 0.08 under
  every configuration, stock included. The limit lies in which peaks
  `multichm` proposes, not in which of them are kept.
- **Not tested.** Censused subplots, 3DEP clouds, complete labels and density
  routing, which the gated arm's studies covered, and any stand outside the
  benchmark with a field count.

## The family

`multichm` (lidRplugins) finds local maxima on the canopy surface, strips the
top of the cloud and searches again, layer by layer. It then keeps a peak
unless a taller kept peak lies within 3 m horizontally or within 5 m in three
dimensions. The family starts from the same candidates as `multichm_gated`:
every layer's peaks before that distance filter. A peak of the first layer is
a surface peak, any other a deeper-layer peak.

Each candidate gets one new feature. Its **depth** is the height of the
highest return in a vertical column around it, minus its own height. The
column has a radius of 1 m, widened at low density so that it holds eight
first returns on average: it is 1 m at about 2.5 pulses/m² or more and reaches
1.2 to 1.6 m at 1.3 pulses/m² and 1.7 to 2.2 m at 0.6. The depth reads heights
only. It uses no return numbers, so it does not depend on how many returns the
instrument records per pulse.

A configuration has six parameters:

| Parameter | What it sets | Grid values |
| --- | --- | --- |
| `depth_max` | In a closed stand a deeper-layer peak is kept when its depth is at most this | 4, 3 and 2 m |
| `lit_union` | In a closed stand a deeper-layer peak is also kept when its first-return share is at least 0.75 and its depth at most 5 m | on, off |
| `zmin`, `zmin_surface` | Height floors of deeper-layer and of surface peaks, in every stand | 5 and 0, 5 and 3, 5 and 5, 3 and 0, 3 and 3 m |
| `near_2d` | The distance filter of a closed stand. At 0 it is the gated arm's: surface peaks are exempt and deeper-layer peaks pass the package's filter. Otherwise every peak, surface or deeper, needs this horizontal distance to each taller accepted peak, and no other test applies | 0, 2.5, 3 and 3.5 m |
| `cover_min` | Canopy cover at or above which a stand counts as closed | 0.6, and 0 for every stand |

Open stands keep the package's distance filter. The grid is every combination,
240 configurations. A label reads
`k<depth_max>_r<near_2d>_z<zmin>_f<zmin_surface>_l<lit_union>_c<cover_min>`.

Three configurations recur below, beside the declared gated arm:

| | Deeper-layer peaks of a closed stand | Height floors | Distance filter of a closed stand |
| --- | --- | --- | --- |
| Declared gated arm, `z5_s0.75_c0.6_e1_d8` | Kept when lit from above (first-return share at least 0.75), and that only where crowns are at least 8 m apart | 5 m on deeper-layer peaks | Surface peaks exempt |
| The selection, `k4_r2.5_z5_f5_l0_c0.6` | Kept when at most 4 m deep | 5 m on every peak | 2.5 m horizontally between any two tops |
| Its low-floor sibling, `k4_r2.5_z3_f3_l0_c0.6` | As the selection | 3 m on every peak | As the selection |
| The arm's configuration, `k4_r0_z3_f3_l0_c0.6` | Kept when at most 4 m deep | 3 m on every peak | Surface peaks exempt |

Two identities tie the family to the gated arm, and both hold on all 530
clips of the study. Without a depth limit and with the gated arm's floors and
filter, the family accepts exactly the peaks of the gated arm's floor and
exemption. With nothing switched on it accepts exactly stock `multichm`'s.
The study's clips hold 325,118 candidates, 223,849 of them in deeper layers.

## What was fixed beforehand

The [protocol](../docs/multichm-depth-protocol.md) reproduces the
specification. In short:

- **Data and scoring.** The plots, clips, stems, split, matcher, null and
  bootstrap are those of the
  [gated multichm study](multichm-gated-results.md): 57 calibration and 49
  validation plots, a 4 m match radius, and corrected F1 = (F1 − null F1) /
  (1 − null F1), where the null is the score of the same detections under 200
  random shifts per plot. The study scores the gated study's cached
  candidates, and its re-derived stock and gated rows equal that study's in
  every cell.
- **Selection.** The grid configuration with the highest corrected F1 at
  native density on the calibration plots, ties to the configuration listed
  first.
- **Blindness.** The validation plots were scored with the family's rules
  once, after the code had been reviewed.
- **Reading.** A change in corrected F1 is "better" when its 95% interval
  lies above zero, "worse" when it lies below, "not worse" when its lower
  bound is above −0.02, and "inconclusive" otherwise. A scope of fewer than
  10 plots is reported and not read.
- **Added before the validation plots were scored.** How the lowest trees are
  read, a low-floor sibling of the selection, closed and open stands as
  scopes, and the datasets of the confirmation.

The validation plots are not untouched. They are the held-out plots of the
gated study, whose results on every plot had been read before this
specification was written. The family's form, its constants and its grid
values came from an exploratory look at 60 plots outside the benchmark that
have no field reference, with three ML segmenters as referees. The held-out
score therefore tests the selection within this grid, as the gated study's
did.

Intervals are paired plot-bootstrap percentiles (1,000 draws, plots resampled
within site, the same draws for both configurations and for observed and null
counts). They are not adjusted for the number of contrasts. A bound within
about 0.001 of zero is read below as sitting on zero.

## Calibration

The six best configurations on the calibration plots, and the references:

| Rank | Configuration | Corrected F1 | F1 | Precision | Recall | Detections per stem |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `k4_r2.5_z5_f5_l0_c0.6` | 0.245 | 0.498 | 0.469 | 0.531 | 1.04 |
| 2 | `k4_r2.5_z5_f5_l1_c0.6` | 0.245 | 0.498 | 0.468 | 0.531 | 1.04 |
| 3 | `k3_r2.5_z5_f5_l1_c0.6` | 0.244 | 0.495 | 0.471 | 0.521 | 1.02 |
| 4 | `k2_r2.5_z5_f5_l1_c0.6` | 0.243 | 0.490 | 0.471 | 0.510 | 1.00 |
| 5 | `k3_r2.5_z5_f5_l0_c0.6` | 0.243 | 0.493 | 0.470 | 0.519 | 1.01 |
| 6 | `k2_r2.5_z5_f5_l0_c0.6` | 0.241 | 0.487 | 0.471 | 0.504 | 0.99 |
|  | Declared gated arm (`z5_s0.75_c0.6_e1_d8`) | 0.224 | 0.482 | 0.430 | 0.548 | 1.17 |
|  | Share gate in every closed stand (`z5_s0.75_c0.6_e1`) | 0.214 | 0.463 | 0.428 | 0.505 | 1.09 |
|  | Floor and exemption (`z5_s0_c0.6_e1`) | 0.208 | 0.479 | 0.407 | 0.584 | 1.32 |
|  | CHM-VWF | 0.199 | 0.437 | 0.428 | 0.446 | 0.96 |
|  | Stock `multichm` | 0.187 | 0.445 | 0.385 | 0.528 | 1.25 |

The six differ in the depth limit and the lit union only. All use the 2.5 m
spacing rule, 5 m floors on every peak and the 0.6 cover threshold, and the
first configuration with other floors ranks 18th. The selection is
`k4_r2.5_z5_f5_l0_c0.6`. Of the 240 configurations, 67 score above the
declared gated arm on these plots.

In sample, the selection against the declared gated arm:

| Scope | Plots | Stems | Detections, selection / declared | Change in corrected F1 |
| --- | --- | --- | --- | --- |
| Five sites | 57 | 1,353 | 1,408 / 1,579 | +0.022 [+0.007, +0.036] |
| California | 24 | 396 | 427 / 487 | +0.043 [+0.028, +0.062] |
| Washington | 33 | 957 | 981 / 1,092 | +0.011 [−0.007, +0.029] |
| Closed stands | 37 | 1,024 | 1,019 / 1,126 | +0.014 [−0.005, +0.032] |
| Open stands | 20 | 329 | 389 / 453 | +0.042 [+0.030, +0.058] |

Most of the in-sample gain is in open stands, where only the floors act. In
closed stands, where the depth rule and the spacing rule act, the interval
spans zero.

## Held-out scores

Validation plots only, at native density (9.8 pulses/m²), nominal plot core.
The selection against each reference:

| Against | Detections, selection / other | F1, selection / other | Corrected F1, selection / other | Change in corrected F1 | Change in recall | Change in precision | Reading |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Declared gated arm | 1,267 / 1,372 | 0.520 / 0.501 | 0.234 / 0.200 | +0.034 [+0.014, +0.055] | −0.005 [−0.029, +0.017] | +0.036 [+0.019, +0.054] | better |
| Stock `multichm` | 1,267 / 1,472 | 0.520 / 0.468 | 0.234 / 0.166 | +0.068 [+0.044, +0.092] | +0.008 [−0.039, +0.054] | +0.079 [+0.050, +0.110] | better |
| Floor and exemption | 1,267 / 1,575 | 0.520 / 0.506 | 0.234 / 0.194 | +0.040 [+0.017, +0.062] | −0.057 [−0.086, −0.031] | +0.057 [+0.033, +0.083] | better |
| Share gate in every closed stand | 1,267 / 1,264 | 0.520 / 0.484 | 0.234 / 0.200 | +0.034 [+0.016, +0.053] | +0.040 [+0.025, +0.057] | +0.034 [+0.014, +0.053] | better |
| CHM-VWF | 1,267 / 1,172 | 0.520 / 0.466 | 0.234 / 0.189 | +0.044 [+0.019, +0.067] | +0.078 [+0.057, +0.098] | +0.036 [+0.012, +0.057] | better |

Against the declared gated arm the selection keeps recall and raises
precision, with 1,267 detections against 1,372. Against the gated arm's floor
and exemption, which is the same arm without its share gate, it trades recall
for precision. Against the share gate applied in every closed stand it gains
both.

The selection against the declared gated arm by scope:

| Scope | Plots | Stems | Detections, selection / declared | Corrected F1, selection / declared | Change in corrected F1 | Change in corrected precision | Change in corrected recall | Reading |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Five sites | 49 | 1,172 | 1,267 / 1,372 | 0.234 / 0.200 | +0.034 [+0.014, +0.055] | +0.040 [+0.018, +0.066] | +0.021 [−0.004, +0.046] | better |
| California | 19 | 266 | 289 / 330 | 0.310 / 0.260 | +0.050 [+0.029, +0.084] | +0.059 [+0.040, +0.095] | +0.025 [−0.003, +0.066] | better |
| Washington | 30 | 906 | 978 / 1,042 | 0.206 / 0.178 | +0.029 [+0.003, +0.054] | +0.034 [+0.005, +0.064] | +0.020 [−0.013, +0.051] | better |
| SJER | 3 | 23 | 54 / 64 | 0.303 / 0.275 | +0.028 [−0.045, +0.067] | +0.028 [−0.025, +0.055] | −0.043 [−0.143, +0.033] | not read |
| SOAP | 8 | 89 | 121 / 141 | 0.305 / 0.233 | +0.073 [+0.034, +0.140] | +0.065 [+0.041, +0.125] | +0.055 [−0.031, +0.150] | not read |
| TEAK | 8 | 154 | 114 / 125 | 0.323 / 0.284 | +0.039 [+0.023, +0.071] | +0.068 [+0.038, +0.181] | +0.017 [−0.000, +0.043] | not read |
| WREF | 18 | 565 | 461 / 495 | 0.226 / 0.208 | +0.018 [−0.017, +0.048] | +0.033 [−0.010, +0.079] | +0.010 [−0.029, +0.040] | not worse |
| ABBY | 12 | 341 | 517 / 547 | 0.173 / 0.131 | +0.042 [−0.006, +0.092] | +0.031 [−0.006, +0.083] | +0.059 [−0.012, +0.124] | not worse |
| Closed stands | 32 | 922 | 965 / 1,024 | 0.217 / 0.184 | +0.033 [+0.006, +0.059] | +0.039 [+0.010, +0.072] | +0.025 [−0.010, +0.053] | better |
| Open stands | 17 | 250 | 302 / 348 | 0.283 / 0.244 | +0.039 [+0.023, +0.057] | +0.044 [+0.030, +0.063] | +0.011 [−0.009, +0.029] | better |

The two Washington sites are each "not worse" and together "better". The three
California sites have fewer than 10 validation plots each. Closed and open
stands gain alike in the point estimate.

Down the density ladder, the same contrast on the validation plots:

| Pulses/m² | Five sites, against the declared gated arm | Reading | California | Washington | Five sites, against stock | Detections, selection / declared |
| --- | --- | --- | --- | --- | --- | --- |
| 9.8 (native) | +0.034 [+0.014, +0.055] | better | +0.050 [+0.029, +0.084] | +0.029 [+0.003, +0.054] | +0.068 [+0.044, +0.092] | 1,267 / 1,372 |
| 4.7 | +0.019 [+0.003, +0.037] | better | +0.040 [+0.027, +0.060] | +0.013 [−0.008, +0.037] | +0.047 [+0.025, +0.070] | 1,315 / 1,385 |
| 2.5 | +0.015 [−0.010, +0.039] | not worse | +0.028 [+0.004, +0.045] | +0.012 [−0.019, +0.045] | +0.050 [+0.022, +0.084] | 1,339 / 1,407 |
| 1.3 | +0.012 [−0.003, +0.027] | not worse | +0.031 [+0.015, +0.047] | +0.005 [−0.013, +0.025] | +0.029 [+0.009, +0.049] | 1,341 / 1,485 |
| 0.6 | +0.034 [+0.020, +0.047] | better | +0.014 [−0.007, +0.038] | +0.040 [+0.025, +0.056] | +0.052 [+0.032, +0.077] | 1,319 / 1,669 |

The selection is better than the declared gated arm at 4.7 and 0.6 pulses/m²
and not worse at 2.5 and 1.3. Against stock it is better at every level. At
0.6 pulses/m² the declared gated arm places 1,669 detections where the
selection places 1,319.

**Stability.** Over 200 splits, each with its own selection, the gain over the
declared gated arm has a median of +0.024 and is above zero in 199. Every
split selects 5 m floors on every peak and the 0.6 cover threshold. The 2.5 m
spacing rule is selected in 176, a 3 m rule in 21 and the gated arm's filter
in 3; a depth limit of 4 m in 176 and of 3 m in 24. The lit union is selected
in 106, and at the selected configuration it changes no detection on the
validation plots. On the headline split the selection is also the best of the
240 configurations on the validation plots, where 159 of them score above the
declared gated arm and all 240 above stock.

Selecting on four sites and scoring every plot of the fifth:

| Held-out site | Plots | Stems | Selected on the other four sites | Against the declared gated arm | Against stock |
| --- | --- | --- | --- | --- | --- |
| SJER | 6 | 57 | `k4_r2.5_z5_f5_l0_c0.6` | +0.049 [+0.009, +0.086] | +0.073 [+0.027, +0.124] |
| SOAP | 18 | 231 | `k4_r2.5_z5_f5_l0_c0.6` | +0.067 [+0.040, +0.108] | +0.079 [+0.039, +0.127] |
| TEAK | 19 | 374 | `k4_r2.5_z5_f5_l0_c0.6` | +0.029 [+0.016, +0.043] | +0.041 [+0.021, +0.057] |
| WREF | 38 | 1,063 | `k2_r2.5_z5_f5_l1_c0.6` | +0.001 [−0.025, +0.025] | +0.038 [+0.002, +0.070] |
| ABBY | 25 | 800 | `k4_r2.5_z5_f5_l0_c0.6` | +0.027 [−0.002, +0.053] | +0.090 [+0.064, +0.115] |

The gain is positive at each site. It is nil at WREF, where the other four
sites select a depth limit of 2 m.

## What each rule adds

The protocol's components set the selection against itself with one parameter
changed. A positive change means the selection's value is the better one:

| The selection minus the selection with | Configuration | Detections, selection / other | Change in corrected F1 | Change in recall | Change in precision |
| --- | --- | --- | --- | --- | --- |
| the gated arm's filter in place of the 2.5 m spacing rule | `k4_r0_z5_f5_l0_c0.6` | 1,267 / 1,205 | +0.007 [−0.004, +0.019] | +0.023 [+0.012, +0.035] | −0.002 [−0.012, +0.007] |
| a 3 m spacing rule | `k4_r3_z5_f5_l0_c0.6` | 1,267 / 1,148 | +0.004 [−0.008, +0.016] | +0.034 [+0.019, +0.051] | −0.013 [−0.022, −0.003] |
| a 3.5 m spacing rule | `k4_r3.5_z5_f5_l0_c0.6` | 1,267 / 1,020 | +0.012 [−0.005, +0.029] | +0.082 [+0.053, +0.112] | −0.020 [−0.042, −0.000] |
| a depth limit of 3 m | `k3_r2.5_z5_f5_l0_c0.6` | 1,267 / 1,228 | +0.005 [−0.002, +0.012] | +0.016 [+0.010, +0.023] | −0.002 [−0.007, +0.002] |
| a depth limit of 2 m | `k2_r2.5_z5_f5_l0_c0.6` | 1,267 / 1,176 | +0.015 [+0.003, +0.028] | +0.039 [+0.028, +0.052] | −0.000 [−0.007, +0.007] |
| floors of 5 / 0 m (deeper / surface) | `k4_r2.5_z5_f0_l0_c0.6` | 1,267 / 1,354 | +0.015 [+0.009, +0.022] | −0.003 [−0.007, −0.001] | +0.028 [+0.019, +0.038] |
| floors of 5 / 3 m (deeper / surface) | `k4_r2.5_z5_f3_l0_c0.6` | 1,267 / 1,323 | +0.011 [+0.006, +0.016] | −0.003 [−0.006, +0.000] | +0.018 [+0.011, +0.026] |
| floors of 3 / 0 m (deeper / surface) | `k4_r2.5_z3_f0_l0_c0.6` | 1,267 / 1,411 | +0.018 [+0.009, +0.027] | −0.010 [−0.017, −0.005] | +0.041 [+0.029, +0.053] |
| floors of 3 / 3 m (deeper / surface) | `k4_r2.5_z3_f3_l0_c0.6` | 1,267 / 1,381 | +0.014 [+0.006, +0.021] | −0.009 [−0.015, −0.004] | +0.032 [+0.022, +0.042] |
| the lit union | `k4_r2.5_z5_f5_l1_c0.6` | 1,267 / 1,267 | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| every stand treated as closed | `k4_r2.5_z5_f5_l0_c0` | 1,267 / 1,360 | +0.017 [+0.010, +0.024] | −0.007 [−0.032, +0.013] | +0.027 [+0.014, +0.046] |

- **Floors.** Every lower floor scores below the selection's, by 0.011 to
  0.018 with each interval above zero. A floor of 5 m on surface peaks in
  place of none is worth +0.015 [+0.009, +0.022]. Lower floors add detections
  and cost precision, and recall barely moves.
- **Depth limit.** Limits of 4 and 3 m are level. A limit of 2 m loses recall
  and corrected F1.
- **Spacing rule.** The 2.5 m rule adds 62 detections and recall over the
  gated arm's filter, and its change in corrected F1 spans zero. Wider rules
  remove detections and recall.
- **Lit union.** It changes nothing.
- **Cover threshold.** Applying the rules in every stand is worse than
  applying them where cover is at least 0.6.

The components do not say what the depth rule adds over the gated arm's share
gate and switch, because the grid holds no configuration without a depth
limit. The walk below does. It is post hoc: it was computed after the held-out
results had been read, and it is where the arm's configuration comes from.
Each step changes one rule on the way from the declared gated arm to the
selection, on the validation half of each dataset:

| Data | Scope | Plots | 1. Depth rule in place of the share gate and the switch | 2. Plus the 2.5 m spacing rule | 3. Plus the 5 m floor on surface peaks | All three: the selection minus the declared gated arm |
| --- | --- | --- | --- | --- | --- | --- |
| 2021 clips, 9.8 pulses/m² (native) | Five sites | 49 | +0.011 [−0.006, +0.028] | +0.008 [−0.003, +0.019] | +0.015 [+0.009, +0.022] | +0.034 [+0.014, +0.055] |
| 2021 clips thinned to 4.7 pulses/m² | Five sites | 49 | +0.007 [−0.003, +0.017] | −0.003 [−0.015, +0.009] | +0.016 [+0.010, +0.022] | +0.019 [+0.003, +0.037] |
| 2021 clips thinned to 2.5 pulses/m² | Five sites | 49 | +0.013 [−0.000, +0.028] | −0.012 [−0.027, +0.002] | +0.014 [+0.008, +0.020] | +0.015 [−0.010, +0.039] |
| 2021 clips thinned to 1.3 pulses/m² | Five sites | 49 | −0.002 [−0.013, +0.006] | −0.000 [−0.008, +0.009] | +0.014 [+0.007, +0.022] | +0.012 [−0.003, +0.027] |
| 2021 clips thinned to 0.6 pulses/m² | Five sites | 49 | +0.016 [+0.005, +0.027] | +0.007 [−0.001, +0.015] | +0.012 [+0.002, +0.022] | +0.034 [+0.020, +0.047] |
| QL2 level, about 2 pulses/m² | Five sites | 49 | +0.011 [−0.000, +0.022] | +0.000 [−0.012, +0.012] | +0.016 [+0.009, +0.024] | +0.027 [+0.008, +0.047] |
| Washington, 2019 flight | Washington | 26 | +0.021 [−0.002, +0.044] | −0.003 [−0.014, +0.011] | +0.009 [+0.002, +0.017] | +0.026 [−0.002, +0.058] |
| California, 2017 and 2018 flights | California | 16 | −0.003 [−0.017, +0.013] | +0.005 [−0.010, +0.022] | +0.010 [+0.001, +0.022] | +0.012 [−0.012, +0.041] |

Over all plots:

| Data | Scope | Plots | 1. Depth rule in place of the share gate and the switch | 2. Plus the 2.5 m spacing rule | 3. Plus the 5 m floor on surface peaks | All three: the selection minus the declared gated arm |
| --- | --- | --- | --- | --- | --- | --- |
| 2021 clips, 9.8 pulses/m² (native) | Five sites | 106 | +0.002 [−0.008, +0.012] | +0.009 [+0.002, +0.016] | +0.017 [+0.012, +0.022] | +0.027 [+0.015, +0.040] |
| 2021 clips thinned to 4.7 pulses/m² | Five sites | 106 | +0.000 [−0.007, +0.007] | +0.000 [−0.007, +0.008] | +0.017 [+0.012, +0.021] | +0.017 [+0.006, +0.029] |
| 2021 clips thinned to 2.5 pulses/m² | Five sites | 106 | +0.009 [+0.001, +0.017] | −0.008 [−0.016, +0.000] | +0.014 [+0.009, +0.019] | +0.014 [−0.000, +0.029] |
| 2021 clips thinned to 1.3 pulses/m² | Five sites | 106 | +0.001 [−0.006, +0.008] | −0.003 [−0.009, +0.004] | +0.015 [+0.009, +0.022] | +0.014 [+0.002, +0.026] |
| 2021 clips thinned to 0.6 pulses/m² | Five sites | 106 | +0.010 [+0.004, +0.016] | +0.004 [−0.002, +0.010] | +0.016 [+0.008, +0.025] | +0.030 [+0.019, +0.041] |
| QL2 level, about 2 pulses/m² | Five sites | 106 | +0.008 [+0.000, +0.016] | −0.003 [−0.011, +0.005] | +0.015 [+0.010, +0.021] | +0.020 [+0.006, +0.034] |
| Washington, 2019 flight | Washington | 56 | +0.010 [−0.004, +0.026] | −0.001 [−0.011, +0.009] | +0.010 [+0.005, +0.016] | +0.019 [+0.000, +0.038] |
| California, 2017 and 2018 flights | California | 39 | −0.010 [−0.025, +0.002] | +0.005 [−0.004, +0.014] | +0.013 [+0.007, +0.020] | +0.008 [−0.012, +0.027] |

- **Step 1, the depth rule.** On the validation half it is positive on six of
  the eight datasets, and its interval excludes zero on one, the ladder at 0.6
  pulses/m². Over all plots it is better at 2.5 and 0.6 pulses/m², its lower
  bound sits on zero at the QL2 level, and on the sparse California flights it
  is negative with an interval too wide to read. At native density over all
  plots it is level with what it replaces. The declared gated arm was itself
  selected on the calibration half of those plots.
- **Step 2, the spacing rule.** It gains on the native 2021 clips, where the
  family was calibrated (+0.009 [+0.002, +0.016] over all plots), and nowhere
  else.
- **Step 3, the floor on surface peaks.** It gains on every dataset in both
  subsets, each interval above zero.

## The lowest trees

The reference holds live stems of 10 cm diameter or more. Of its 2,525 stems,
74 are under 5 m tall and 11 under 3 m. With so few low stems, and with a
detector that places about one detection per stem, most matches of a low stem
are chance matches: under random shifts the selection still "finds" 21% of the
stems under 5 m and 39% of those of 5 to 10 m. The protocol therefore reads
low trees by chance-corrected recall, (matched − matched by chance) / (stems −
matched by chance). On the validation plots:

| Field height (m) | Stems | Share matched by chance, selection | Stock | Declared gated arm | Selection | Low-floor sibling |
| --- | --- | --- | --- | --- | --- | --- |
| Under 5 | 26 | 0.210 | 0.146 [−0.084, 0.346] (not above chance) | 0.022 [−0.102, 0.170] (not above chance) | 0.075 [−0.074, 0.221] (not above chance) | 0.025 [−0.157, 0.177] (not above chance) |
| 5 to 10 | 321 | 0.386 | 0.138 [0.070, 0.211] | 0.170 [0.100, 0.245] | 0.188 [0.117, 0.265] | 0.190 [0.112, 0.270] |
| 10 to 20 | 494 | 0.422 | 0.132 [0.091, 0.195] | 0.157 [0.096, 0.228] | 0.184 [0.121, 0.252] | 0.187 [0.130, 0.252] |
| 20 and more | 303 | 0.428 | 0.512 [0.392, 0.665] | 0.483 [0.391, 0.582] | 0.481 [0.400, 0.574] | 0.481 [0.400, 0.574] |
| All stems | 1,172 | 0.409 | 0.214 [0.173, 0.267] | 0.239 [0.201, 0.285] | 0.260 [0.224, 0.301] | 0.262 [0.226, 0.304] |

- **Under 5 m.** No configuration is above chance, stock included.
- **From 5 to 20 m.** Every configuration is above chance. The selection has
  the highest point estimate and stock the lowest, with overlapping intervals.
- **At 20 m and more.** The three are level, and stock is nominally highest.
  Over all plots the configurations with a depth rule find fewer of these
  stems than the declared gated arm, as the section on the arm's configuration
  shows.

The protocol's guard asks whether the selection loses stems under 10 m against
the declared gated arm. Raw recall changes by −0.009 [−0.029, +0.011] (347
stems), which is not flagged. Chance-corrected recall changes by +0.020
[−0.012, +0.059], and the share matched by chance falls from 0.399 to 0.373.
By the protocol's reading there is no detectable loss of low trees.

By crown class:

| Crown class | Stems | Stock | Declared gated arm | Selection | Low-floor sibling |
| --- | --- | --- | --- | --- | --- |
| Dominant | 168 | 0.576 [0.437, 0.716] | 0.591 [0.467, 0.715] | 0.602 [0.480, 0.724] | 0.591 [0.463, 0.719] |
| Codominant | 708 | 0.194 [0.140, 0.265] | 0.245 [0.179, 0.324] | 0.282 [0.217, 0.344] | 0.289 [0.223, 0.360] |
| Intermediate | 263 | 0.077 [−0.006, 0.164] (not above chance) | 0.057 [−0.011, 0.122] (not above chance) | 0.067 [−0.009, 0.140] (not above chance) | 0.067 [−0.017, 0.143] (not above chance) |
| Suppressed | 8 | −0.025 [−0.413, 0.307] (not above chance) | 0.090 [−0.105, 0.334] (not above chance) | −0.006 [−0.158, 0.257] (not above chance) | −0.013 [−0.176, 0.254] (not above chance) |

Dominant and codominant stems are found above chance by every configuration.
Intermediate stems, 263 of the 1,172 validation stems, are not: their
chance-corrected recall is 0.06 to 0.08 with intervals that reach zero. On the
calibration plots the same values clear zero by 0.004 to 0.020. Stock is no
better than the others.

**The low-floor sibling.** Among the selection and its four floor variants,
the protocol takes the one with the highest chance-corrected recall of stems
under 10 m on the calibration plots. That is the variant with 3 m floors on
every peak, `k4_r2.5_z3_f3_l0_c0.6`. On the validation plots:

| Scope | Plots | Against the declared gated arm | Reading | Against the selection | Reading | Detections, sibling / selection |
| --- | --- | --- | --- | --- | --- | --- |
| Five sites | 49 | +0.020 [−0.001, +0.041] | not worse | −0.014 [−0.021, −0.006] | worse | 1,381 / 1,267 |
| California | 19 | +0.007 [−0.012, +0.031] | not worse | −0.044 [−0.065, −0.029] | worse | 340 / 289 |
| Washington | 30 | +0.025 [−0.002, +0.051] | not worse | −0.003 [−0.013, +0.006] | not worse | 1,041 / 978 |
| Closed stands | 32 | +0.032 [+0.005, +0.057] | better | −0.002 [−0.010, +0.007] | not worse | 1,019 / 965 |
| Open stands | 17 | −0.010 [−0.024, −0.001] | worse | −0.049 [−0.070, −0.033] | worse | 362 / 302 |

The sibling is not worse than the declared gated arm, and it is better in
closed stands. It is worse than the selection, and all of that is in open
stands: in closed stands the two are level. It does not find more low trees:
its chance-corrected recall of stems under 10 m differs from the selection's
by −0.002 [−0.029, +0.026]. By the protocol's reading the floor is a matter of
what counts as a tree, not of accuracy. A floor of 3 m adds 114 detections,
and a reference with 26 stems under 5 m can credit few of them.

**Heights.** A detection's height is the candidate's own. For deeper-layer
peaks matched to a stem with a field height it is 0.87 m too low on average
(147 pairs, RMSE 3.61 m), and for surface peaks 0.46 m too high (495 pairs,
RMSE 2.36 m). Re-measuring the height as the top of the contiguous column of
returns above the peak moves the deeper-layer error to +0.59 m (RMSE 3.12 m)
and costs corrected F1 (−0.007 [−0.015, −0.000]), because the matcher reads
heights. The arm reports the candidate's height.

## Other densities and flights

The protocol's addendum fixed a confirmation on the clips that the gated
arm's [confirmation tests](multichm-gated-confirmation-results.md) had
prepared. The selection is not re-selected there. The calibration half of the
plots took part in the selection, on other clips of the same plots and stems,
so the validation half is the primary subset. The selection against the
declared gated arm:

| Test | Data | Scope | Validation half: plots | Change in corrected F1 | Reading | All plots: plots | Change in corrected F1 | Reading |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | Density ladder, 4.7 pulses/m² | Five sites | 49 | +0.019 [+0.003, +0.037] | better |  |  |  |
| T1 | Density ladder, 2.5 pulses/m² | Five sites | 49 | +0.015 [−0.010, +0.039] | not worse |  |  |  |
| T1 | Density ladder, 1.3 pulses/m² | Five sites | 49 | +0.012 [−0.003, +0.027] | not worse |  |  |  |
| T1 | Density ladder, 0.6 pulses/m² | Five sites | 49 | +0.034 [+0.020, +0.047] | better |  |  |  |
| T2 | QL2 level, about 2 pulses/m² | Five sites | 49 | +0.027 [+0.008, +0.047] | better | 106 | +0.020 [+0.006, +0.034] | better |
| T3 | Washington, 2019 flight | Washington | 26 | +0.026 [−0.002, +0.058] | not worse | 56 | +0.019 [+0.000, +0.038] | better |
| T4 | California, 2017 and 2018 flights | California | 16 | +0.012 [−0.012, +0.041] | not worse | 39 | +0.008 [−0.012, +0.027] | not worse |

The addendum's rule reads the selection as carrying over when it is better or
not worse on the QL2 level and on the 2019 flight and worse on no test. It
carries over. On the 2019 flight the lower bound over all plots is +0.0002,
which sits on zero. The other pairs, with the same stems on the 2021 clips for
comparison:

| Data | Scope | Plots, validation half / all | Selection minus declared | Selection minus stock | Low-floor sibling minus declared | Declared minus stock |
| --- | --- | --- | --- | --- | --- | --- |
| QL2 level | Five sites | 49 (validation half) | +0.027 [+0.008, +0.047] | +0.042 [+0.015, +0.068] | +0.013 [−0.005, +0.031] | +0.015 [−0.003, +0.034] |
| QL2 level | Five sites | 106 (all plots) | +0.020 [+0.006, +0.034] | +0.045 [+0.027, +0.062] | +0.008 [−0.006, +0.020] | +0.025 [+0.012, +0.037] |
| Washington, 2019 flight | Washington | 26 (validation half) | +0.026 [−0.002, +0.058] | +0.063 [+0.032, +0.093] | +0.014 [−0.013, +0.045] | +0.037 [+0.008, +0.064] |
| Washington, 2019 flight | Washington | 56 (all plots) | +0.019 [+0.000, +0.038] | +0.042 [+0.019, +0.066] | +0.005 [−0.013, +0.023] | +0.023 [+0.000, +0.045] |
| The same Washington stems on the 2021 clips | Washington | 26 (validation half) | +0.022 [−0.005, +0.048] | +0.061 [+0.026, +0.091] | +0.020 [−0.008, +0.047] | +0.039 [+0.009, +0.064] |
| The same Washington stems on the 2021 clips | Washington | 56 (all plots) | +0.014 [−0.002, +0.031] | +0.054 [+0.035, +0.075] | +0.008 [−0.008, +0.025] | +0.040 [+0.022, +0.058] |
| California, 2017 and 2018 flights | California | 16 (validation half) | +0.012 [−0.012, +0.041] | +0.021 [−0.015, +0.063] | −0.001 [−0.034, +0.040] | +0.009 [−0.015, +0.028] |
| California, 2017 and 2018 flights | California | 39 (all plots) | +0.008 [−0.012, +0.027] | +0.018 [−0.005, +0.042] | −0.001 [−0.023, +0.024] | +0.010 [−0.013, +0.034] |
| The same California stems on the 2021 clips | California | 16 (validation half) | +0.051 [+0.030, +0.083] | +0.059 [+0.038, +0.087] | +0.016 [+0.001, +0.041] | +0.007 [−0.015, +0.024] |
| The same California stems on the 2021 clips | California | 39 (all plots) | +0.046 [+0.032, +0.064] | +0.059 [+0.042, +0.079] | +0.016 [+0.003, +0.030] | +0.013 [+0.000, +0.027] |

- **Against stock.** The selection is better at the QL2 level and on the 2019
  flight, and not worse on the sparse California flights.
- **The sparse California flights.** The selection gains less there than on
  the 2021 clips of the same stems: +0.012 over the declared gated arm where
  the 2021 clips give +0.051, on the validation half.
- **The low-floor sibling.** It is not worse than the declared gated arm at
  the QL2 level and on the 2019 flight, and inconclusive on the sparse
  California flights.
- **A check of the wiring.** The declared gated arm against stock, recomputed
  here, equals the gated arm's confirmation tests in every scope those tests
  report, to rounding error.

## The arm's configuration

Everything in this section is post hoc. It was computed after the held-out
results and the confirmation had been read, and none of it was declared in the
protocol. The choice also drew on a referee-only check on plots outside the
benchmark that have no field reference. The validation-half figures are shown
because the sections above use them. They are not held-out evidence for the
choices made here.
[posthoc_multichm_depth.R](../scripts/posthoc_multichm_depth.R) computes all
of it and reproduces the protocol's own rows as a check of its wiring.

The arm's configuration is `k4_r0_z3_f3_l0_c0.6`, `MCD_ARM` in
[multichm_depth_lib.R](../scripts/multichm_depth_lib.R). It comes from three
choices on the way from the declared gated arm to the selection:

- **Keep the depth rule.** It is the part the study was built for. It removes
  the crown-spacing switch, which
  [changes state](multichm-gated-confirmation-results.md#r4-noise-in-the-crown-spacing-switch)
  in 8 of 69 closed plots when the grid is shifted by less than a metre, and
  the first-return share, which added nothing on the 2019 flight. By the walk
  it costs no corrected F1 on any dataset and gains at two density levels. It
  does lose tall stems, as shown below.
- **Leave out the spacing rule.** Its gain is confined to the clips the family
  was calibrated on. On the plots outside the benchmark, three ML segmenters
  agreed with few of the tops it adds.
- **Set both floors to 3 m.** The reference stems start near 3 m: 11 of the
  2,525 are shorter and 63 lie between 3 and 5 m. A 5 m floor scores higher on
  these plots, by 0.005 to 0.016 on every dataset, because it removes
  detections that this reference seldom credits. In closed stands the two
  floors are level (−0.004 [−0.012, +0.004] on the validation half, −0.005
  [−0.011, +0.001] over all plots), and the difference lies in open stands
  (−0.049 [−0.070, −0.033] on the validation half). On the plots outside the
  benchmark the 3 m floors kept low trees that the ML segmenters see. The
  floor states which trees count, and these plots cannot test it.

The arm's configuration against the other configurations, on the validation
half of each dataset:

| Data | Scope | Plots | Against the declared gated arm | Against stock | Against the selection | 3 m floors in place of the gated arm's floors | 3 m floors in place of 5 m floors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2021 clips, 9.8 pulses/m² (native) | Five sites | 49 | +0.012 [−0.006, +0.030] | +0.046 [+0.019, +0.071] | −0.022 [−0.035, −0.009] | +0.001 [−0.005, +0.006] | −0.015 [−0.023, −0.008] |
| 2021 clips thinned to 4.7 pulses/m² | Five sites | 49 | +0.011 [−0.002, +0.024] | +0.038 [+0.016, +0.063] | −0.009 [−0.023, +0.005] | +0.004 [−0.003, +0.011] | −0.014 [−0.022, −0.006] |
| 2021 clips thinned to 2.5 pulses/m² | Five sites | 49 | +0.014 [−0.000, +0.031] | +0.049 [+0.028, +0.077] | −0.001 [−0.020, +0.017] | +0.001 [−0.006, +0.007] | −0.015 [−0.023, −0.007] |
| 2021 clips thinned to 1.3 pulses/m² | Five sites | 49 | −0.000 [−0.013, +0.012] | +0.017 [−0.005, +0.039] | −0.012 [−0.025, +0.000] | +0.002 [−0.005, +0.009] | −0.015 [−0.025, −0.007] |
| 2021 clips thinned to 0.6 pulses/m² | Five sites | 49 | +0.022 [+0.011, +0.034] | +0.040 [+0.018, +0.066] | −0.012 [−0.023, −0.000] | +0.007 [+0.002, +0.012] | −0.009 [−0.017, −0.000] |
| QL2 level, about 2 pulses/m² | Five sites | 49 | +0.014 [−0.000, +0.026] | +0.028 [+0.009, +0.050] | −0.014 [−0.028, −0.000] | +0.003 [−0.003, +0.009] | −0.016 [−0.023, −0.009] |
| Washington, 2019 flight | Washington | 26 | +0.020 [−0.005, +0.043] | +0.056 [+0.028, +0.082] | −0.007 [−0.025, +0.009] | −0.001 [−0.008, +0.005] | −0.011 [−0.021, −0.003] |
| California, 2017 and 2018 flights | California | 16 | −0.004 [−0.019, +0.013] | +0.005 [−0.024, +0.035] | −0.016 [−0.031, −0.003] | −0.001 [−0.007, +0.005] | −0.011 [−0.020, −0.003] |

Over all plots:

| Data | Scope | Plots | Against the declared gated arm | Against stock | Against the selection | 3 m floors in place of the gated arm's floors | 3 m floors in place of 5 m floors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2021 clips, 9.8 pulses/m² (native) | Five sites | 106 | +0.006 [−0.004, +0.017] | +0.041 [+0.025, +0.056] | −0.021 [−0.030, −0.012] | +0.004 [−0.001, +0.009] | −0.014 [−0.020, −0.007] |
| 2021 clips thinned to 4.7 pulses/m² | Five sites | 106 | +0.005 [−0.004, +0.012] | +0.036 [+0.023, +0.051] | −0.013 [−0.023, −0.003] | +0.004 [−0.000, +0.009] | −0.014 [−0.019, −0.009] |
| 2021 clips thinned to 2.5 pulses/m² | Five sites | 106 | +0.016 [+0.006, +0.026] | +0.047 [+0.032, +0.061] | +0.002 [−0.009, +0.012] | +0.007 [+0.002, +0.012] | −0.008 [−0.015, −0.002] |
| 2021 clips thinned to 1.3 pulses/m² | Five sites | 106 | +0.006 [−0.002, +0.014] | +0.028 [+0.012, +0.045] | −0.007 [−0.017, +0.002] | +0.005 [+0.001, +0.010] | −0.013 [−0.020, −0.006] |
| 2021 clips thinned to 0.6 pulses/m² | Five sites | 106 | +0.017 [+0.010, +0.024] | +0.043 [+0.028, +0.059] | −0.013 [−0.022, −0.004] | +0.007 [+0.004, +0.011] | −0.014 [−0.022, −0.006] |
| QL2 level, about 2 pulses/m² | Five sites | 106 | +0.013 [+0.004, +0.022] | +0.038 [+0.022, +0.052] | −0.007 [−0.018, +0.003] | +0.004 [+0.000, +0.009] | −0.013 [−0.018, −0.007] |
| Washington, 2019 flight | Washington | 56 | +0.009 [−0.006, +0.026] | +0.033 [+0.008, +0.058] | −0.010 [−0.022, +0.003] | −0.001 [−0.006, +0.003] | −0.012 [−0.020, −0.005] |
| California, 2017 and 2018 flights | California | 39 | −0.004 [−0.019, +0.015] | +0.007 [−0.012, +0.026] | −0.011 [−0.024, +0.001] | +0.007 [−0.001, +0.016] | −0.005 [−0.017, +0.007] |

- **Against the declared gated arm.** It is better or not worse on every
  dataset. The interval excludes zero at 0.6 pulses/m² in both subsets, and at
  2.5 pulses/m² and the QL2 level over all plots. At native density the two
  are level. On the sparse California flights the lower bound sits at the 0.02
  margin.
- **Against stock.** It is better on every dataset but two: the ladder at 1.3
  pulses/m² on the validation half and the sparse California flights.
- **Against the selection.** It is lower on nearly every dataset: by 0.021 at
  native density, where the selection's spacing rule and its 5 m floors both
  gain, and by up to 0.016 elsewhere.
- **The floors.** Against the gated arm's floors the 3 m floors are level or
  slightly ahead. Against 5 m floors they are behind on every dataset.
- **Within the grid.** By corrected F1 at native density the arm's
  configuration ranks 64th of the 240 configurations on the validation plots
  and 62nd over all plots. The 5 m variant ranks 8th and 9th, and the
  selection first in both.

At native density by scope:

| Plots | Scope | Number | Stems | Detections, arm / declared | Corrected F1, arm / declared | Against the declared gated arm | Change in recall | Change in precision | Against the selection |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Validation half | Five sites | 49 | 1,172 | 1,312 / 1,372 | 0.212 / 0.200 | +0.012 [−0.006, +0.030] | −0.020 [−0.045, +0.003] | +0.006 [−0.008, +0.019] | −0.022 [−0.035, −0.009] |
| Validation half | California | 19 | 266 | 337 / 330 | 0.260 / 0.260 | +0.000 [−0.014, +0.017] | +0.011 [+0.000, +0.030] | +0.001 [−0.015, +0.014] | −0.050 [−0.075, −0.034] |
| Validation half | Washington | 30 | 906 | 975 / 1,042 | 0.194 / 0.178 | +0.016 [−0.007, +0.037] | −0.030 [−0.059, +0.000] | +0.010 [−0.007, +0.026] | −0.013 [−0.030, +0.006] |
| Validation half | Closed stands | 32 | 922 | 950 / 1,024 | 0.204 / 0.184 | +0.020 [−0.004, +0.042] | −0.028 [−0.055, +0.000] | +0.015 [−0.000, +0.032] | −0.013 [−0.031, +0.004] |
| Validation half | Open stands | 17 | 250 | 362 / 348 | 0.234 / 0.244 | −0.010 [−0.024, −0.001] | +0.008 [+0.004, +0.016] | −0.009 [−0.026, +0.003] | −0.049 [−0.070, −0.033] |
| All plots | Five sites | 106 | 2,525 | 2,805 / 2,951 | 0.219 / 0.213 | +0.006 [−0.004, +0.017] | −0.022 [−0.036, −0.006] | +0.006 [−0.003, +0.015] | −0.021 [−0.030, −0.012] |
| All plots | California | 43 | 662 | 837 / 817 | 0.256 / 0.248 | +0.008 [−0.004, +0.021] | +0.020 [+0.008, +0.033] | +0.006 [−0.006, +0.017] | −0.037 [−0.057, −0.021] |
| All plots | Washington | 63 | 1,863 | 1,968 / 2,134 | 0.202 / 0.198 | +0.004 [−0.010, +0.019] | −0.037 [−0.055, −0.016] | +0.009 [−0.002, +0.020] | −0.015 [−0.026, −0.003] |
| All plots | Closed stands | 69 | 1,946 | 1,979 / 2,150 | 0.208 / 0.201 | +0.007 [−0.008, +0.021] | −0.034 [−0.051, −0.014] | +0.012 [+0.001, +0.024] | −0.016 [−0.026, −0.005] |
| All plots | Open stands | 37 | 579 | 826 / 801 | 0.245 / 0.242 | +0.003 [−0.010, +0.016] | +0.017 [+0.007, +0.029] | +0.000 [−0.013, +0.011] | −0.038 [−0.053, −0.022] |

Against the declared gated arm the arm's configuration places 4 to 5% fewer
detections, with lower recall and higher precision. In closed stands the
change in corrected F1 is +0.020 [−0.004, +0.042] on the validation half and
+0.007 [−0.008, +0.021] over all plots. In open stands it reads worse on the
validation half and level over all plots.

**The lowest trees under the arm's configuration.** Chance-corrected recall
by field height over all plots, then the raw counts:

| Field height (m) | Stems | Share matched by chance, arm | Stock | Declared gated arm | Selection | Arm's configuration |
| --- | --- | --- | --- | --- | --- | --- |
| Under 5 | 74 | 0.228 | 0.064 [−0.086, 0.229] (not above chance) | 0.018 [−0.075, 0.123] (not above chance) | 0.039 [−0.056, 0.119] (not above chance) | 0.038 [−0.080, 0.155] (not above chance) |
| 5 to 10 | 745 | 0.384 | 0.119 [0.066, 0.176] | 0.147 [0.089, 0.208] | 0.158 [0.098, 0.225] | 0.155 [0.092, 0.221] |
| 10 to 20 | 1,015 | 0.388 | 0.162 [0.121, 0.207] | 0.207 [0.151, 0.270] | 0.235 [0.175, 0.301] | 0.203 [0.151, 0.265] |
| 20 and more | 629 | 0.383 | 0.538 [0.448, 0.628] | 0.496 [0.427, 0.568] | 0.458 [0.393, 0.527] | 0.446 [0.383, 0.518] |
| All stems | 2,525 | 0.382 | 0.227 [0.195, 0.262] | 0.254 [0.220, 0.293] | 0.262 [0.228, 0.300] | 0.248 [0.213, 0.287] |

| Field height (m) | Stems | Matched by stock | By the declared gated arm | By the selection | By the arm's configuration |
| --- | --- | --- | --- | --- | --- |
| Under 3 | 11 | 3 | 2 | 1 | 2 |
| 3 to 5 | 63 | 23 | 16 | 14 | 17 |
| 5 to 10 | 745 | 333 | 358 | 348 | 357 |
| 10 to 20 | 1,015 | 479 | 546 | 554 | 520 |
| 20 and more | 629 | 485 | 447 | 423 | 414 |
| Unknown | 62 | 43 | 39 | 39 | 42 |
| All stems | 2,525 | 1,366 | 1,408 | 1,379 | 1,352 |

- **Under 5 m.** The arm's configuration is no different from the others:
  none is above chance.
- **From 5 to 20 m.** It is level with the declared gated arm.
- **At 20 m and more.** It finds fewer stems than the declared gated arm, 414
  of 629 against 447. Chance-corrected recall changes by −0.050 [−0.091,
  −0.008]. This comes with the depth rule, whatever the floors, and the
  selection shows it too. Stock finds the most tall stems of all.
- **Intermediate crowns.** Chance-corrected recall is 0.050 [0.006, 0.097],
  as low as under every other configuration.

**Which configuration for which use.**

| Purpose | Configuration | What supports it |
| --- | --- | --- |
| The arm's default: trees from 3 m up | `k4_r0_z3_f3_l0_c0.6` | Post hoc. Better or not worse than the declared gated arm on eight datasets |
| A reference like this one, stems of 10 cm diameter or more | `k4_r0_z5_f5_l0_c0.6` | Post hoc. Better than the declared gated arm on seven of eight datasets in both subsets; the table follows |
| The configuration with a held-out test | `k4_r2.5_z5_f5_l0_c0.6` | Selected on the calibration plots and better on the held-out plots. Its spacing rule gains on the 2021 native clips only |

The 5 m variant against the declared gated arm, and what the spacing rule adds
to it:

| Data | Scope | 5 m variant minus the declared gated arm, validation half | All plots | Selection minus the 5 m variant, validation half | All plots |
| --- | --- | --- | --- | --- | --- |
| 2021 clips, 9.8 pulses/m² (native) | Five sites | +0.027 [+0.009, +0.045] | +0.019 [+0.009, +0.031] | +0.007 [−0.004, +0.019] | +0.008 [+0.000, +0.016] |
| 2021 clips thinned to 4.7 pulses/m² | Five sites | +0.025 [+0.012, +0.037] | +0.019 [+0.010, +0.027] | −0.005 [−0.017, +0.008] | −0.001 [−0.009, +0.007] |
| 2021 clips thinned to 2.5 pulses/m² | Five sites | +0.029 [+0.013, +0.046] | +0.024 [+0.014, +0.035] | −0.014 [−0.029, +0.000] | −0.010 [−0.018, −0.001] |
| 2021 clips thinned to 1.3 pulses/m² | Five sites | +0.015 [+0.001, +0.028] | +0.020 [+0.010, +0.030] | −0.003 [−0.012, +0.006] | −0.006 [−0.013, +0.002] |
| 2021 clips thinned to 0.6 pulses/m² | Five sites | +0.031 [+0.016, +0.046] | +0.031 [+0.020, +0.042] | +0.003 [−0.005, +0.012] | −0.001 [−0.009, +0.006] |
| QL2 level, about 2 pulses/m² | Five sites | +0.029 [+0.016, +0.042] | +0.025 [+0.015, +0.036] | −0.002 [−0.014, +0.012] | −0.005 [−0.013, +0.003] |
| Washington, 2019 flight | Washington | +0.030 [+0.007, +0.056] | +0.021 [+0.005, +0.038] | −0.004 [−0.015, +0.010] | −0.002 [−0.012, +0.008] |
| California, 2017 and 2018 flights | California | +0.007 [−0.008, +0.025] | +0.002 [−0.014, +0.016] | +0.005 [−0.010, +0.023] | +0.006 [−0.004, +0.017] |

`detect_multichm_depth(las, res, frdens)` runs the arm's configuration on one
height-normalized clip. `res` is the resolution of the candidate search (the
drivers use 0.25 m at 8 first returns per m² or more and 0.5 m below) and
`frdens` the clip's first-return density. Another configuration is passed as
`cfg = mcd_config(...)`.

## Limits

- **The held-out plots had been read.** They are the gated study's held-out
  plots. Their scores under stock and the gated configurations were known,
  and so were the heights of their reference stems. The held-out score tests
  the selection within the grid.
- **The arm's configuration is post hoc.** The held-out test is of the
  selection. The arm's configuration shares its depth rule and nothing else,
  and its scores on the validation half are descriptive.
- **Nominal plot cores.** Commission is counted against a reference that is
  not a complete census. The gated study also scored inside censused subplots;
  this study did not.
- **Low trees.** The reference has 74 stems under 5 m and no configuration
  finds them above chance. Neither floor can be tested on these plots, and the
  gated arm's tests on complete labels found that a 5 m floor removes labelled
  small trees.
- **Suppressed and intermediate trees.** They are found barely above chance
  or not at all. Changing which candidates are kept cannot find trees that
  have no candidate.
- **Density.** Below 2.5 pulses/m² the column widens and the depth is measured
  over a larger footprint. The ladder covers this by decimation, and native
  sparse flights by 39 California plots, where no configuration is
  distinguishable from the declared gated arm.
- **Cover is measured on each clip.** As in the gated arm, a stand is closed
  when its own clip has cover of at least 0.6. Cover reads lower on decimated
  clips and differs between flights, so a stand near the threshold can change
  state.
- **Other instruments.** One flight of another year and instrument was tested,
  over the Washington sites. 3DEP clouds were not.
- **Stands outside the benchmark.** A referee-only check on plots without a
  field reference informed the arm's configuration. It is not part of this
  repository and no field count has been compared.
- **Many contrasts.** The intervals are not adjusted for their number, and
  bounds near zero move with the bootstrap draws.

## Outputs

Under `work/multichm_depth_runs/`:

- `neon/multichm_depth/` holds the study. `cells.csv` has the observed and
  null counts of every clip under each of the 240 configurations, the four
  gated references and CHM-VWF. `selection.csv` and
  `declared_depth_config.json` hold the selection and its low-floor sibling,
  `calibration.csv` and `validation.csv` every contrast in and out of sample,
  `ladder.csv`, `components.csv`, `seeds.csv`, `seed_summary.csv` and
  `site_out.csv` the analyses named above, `lowest_trees.csv` and
  `heights.csv` the low-tree and height tables, and `tables.md` every table in
  full.
- `confirm/` holds the confirmation: per dataset the scored cells, and
  `contrasts.csv`, `a8_reading.csv`, `campaign_check.csv` and `tables.md`.
- `posthoc/` holds the walk and the arm's configuration: `contrasts.csv`,
  `lowest_trees.csv`, `stem_heights.csv`, `grid_validation.csv` (every grid
  configuration on the validation plots and on all plots), `arm_config.json`
  and `tables.md`.

## Reproduce

The study reads the gated study's run, so that run comes first, prepared as
[its report](multichm-gated-results.md#reproduce) says. The confirmation reads
the datasets of the gated arm's
[confirmation tests](multichm-gated-confirmation-results.md#reproduce).

```sh
J=$PWD/work/multichm_gated_runs
CLAUDE_JOB_DIR=$J Rscript scripts/calval_multichm_depth.R STAGE=features CORES=8
CLAUDE_JOB_DIR=$J Rscript scripts/calval_multichm_depth.R STAGE=score CORES=8
CLAUDE_JOB_DIR=$J Rscript scripts/calval_multichm_depth.R STAGE=analyze
# the validation plots
CLAUDE_JOB_DIR=$J Rscript scripts/calval_multichm_depth.R STAGE=score UNBLIND=1 CORES=8
CLAUDE_JOB_DIR=$J Rscript scripts/calval_multichm_depth.R STAGE=analyze UNBLIND=1
Rscript scripts/confirm_multichm_depth.R STAGE=all CORES=8
Rscript scripts/posthoc_multichm_depth.R STAGE=all CORES=8
```

The study takes about 25 minutes on 8 cores, nearly all of it scoring the 240
configurations on the 530 clips. The analyses run from `cells.csv` in under a
minute. Without `UNBLIND=1` only the calibration plots are scored and read.
The confirmation takes about three minutes and the post hoc analysis about
two and a half.
[calval_multichm_depth.R](../scripts/calval_multichm_depth.R) is the study,
[confirm_multichm_depth.R](../scripts/confirm_multichm_depth.R) the
confirmation,
[posthoc_multichm_depth.R](../scripts/posthoc_multichm_depth.R) the walk and
the arm's configuration, and
[multichm_depth_lib.R](../scripts/multichm_depth_lib.R) the detector.
