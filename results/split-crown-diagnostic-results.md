# Split-Crown Diagnostic

Checked on 18 November 2026. This analysis is post hoc: it was added after all
benchmark results were known and after an internal review of the paper. It uses
no new inference; it re-reads the detections every arm persisted for the
paper's scores.

The [chance-correction simulation](chance-correction-simulation-results.md)
found that chance-corrected leads overstate skill when a detector's extra
detections lie beside trees rather than on them. Its example is a split crown:
a second detection of one crown, 1.5 to 4 m from the tree. In its loosely
clustered stands, the simulated pattern nearest to the reference stems of all
54 distributed plots, split
crowns at rate 0.8 per detected tree, about the segmenters' surplus of
detections, reproduce the point-cloud segmenters' corrected recall lead over
CHM-VWF of about 0.11 at 4 m (rate 0.5 gives about two-thirds of it), but not a
positive corrected F1 lead. This diagnostic asks how often the benchmark's own
detectors place such detections, and whether the segmenters place them more
often than the canopy-model detectors.

## Findings

Native density, five sites, the adopted population; "all plots" are the 106
scored plots in their nominal cores, "censused" the 57 plots of the
[censused-subplot study](census-support-results.md) inside their censused
interiors, the scope of the paper's censused chance null.

- **Close pairs alone do not show splitting.** Of the mapped reference stems,
  0.82 stand 1.5 to 4 m from another mapped stem. SegmentAnyTree's and
  ForestFormer3D's detections have such a neighbour at rates of 0.69 to 0.76,
  CHM-VWF's at 0.54 to 0.55, whose variable window forbids a second top within
  1.5 to 2.5 m (Table 1).
- **The segmenters' close pairs more often lie on one crown.** With no drop of
  more than 1 m in the native canopy model between them, 25% (SegmentAnyTree)
  and 36% (ForestFormer3D) of their close pairs on all plots, against 7% for
  CHM-VWF; on a pit-free canopy model 46%, 56% and 19% (Table 2).
- **Split-crown candidates are rare relative to the simulated rates.** An
  unmatched detection 1.5 to 4 m from a matched detection of the same arm, with
  no valley between them, occurs 0.08 to 0.20 times per detected tree for
  SegmentAnyTree and 0.11 to 0.19 for ForestFormer3D on all plots, over the two
  canopy models and six thresholds, against 0.01 to 0.08 for CHM-VWF (Table 3).
  Inside the censused subplots the segmenters' rates are 0.05 to 0.17.
- **Their excess over CHM-VWF corresponds to a split rate of about 0.15 to
  0.45.** In the four settings of Table 5 the segmenters lead CHM-VWF by 0.08
  to 0.14 candidates per detected tree on all plots and 0.05 to 0.13 inside the
  censused subplots. Applied to the simulation's own plots, the same count
  rises by 0.31 per unit of split rate in the loose clusters, so these leads
  equal split rates of 0.26 to 0.43 (SegmentAnyTree 0.26 to 0.39,
  ForestFormer3D 0.35 to 0.43) on all plots and 0.16 to 0.40 inside the
  censused subplots: below the simulated 0.5 and well below 0.8, with upper
  interval limits of at most 0.57 in any of the twelve valley settings.
- **Split crowns can explain part of the corrected recall leads, not all of
  them.** In the loose clusters the simulated split crowns raise corrected
  recall by 0.12 to 0.17 per unit of split rate. At the rates above that is
  0.03 to 0.07 of SegmentAnyTree's corrected recall lead of +0.112 on all plots
  (0.02 to 0.05 of +0.113 inside the censused subplots) and 0.04 to 0.07 of
  ForestFormer3D's +0.108 (+0.102): a sixth to two-thirds, on a reading that
  counts every candidate as a split crown.
- **Arms that split as often do not get the lead.** TreeisoNet places as many
  candidates as the segmenters, more than SegmentAnyTree in every setting, and
  `multichm` about as many; their corrected recall leads are +0.024 and +0.030
  on all plots, against SegmentAnyTree's +0.112. Li 2012 places almost none on
  the paper's canopy model and leads by +0.060.
- **Corrected F1 leads are not explained.** In the loose clusters split crowns
  at rate 0.5 give a corrected F1 lead of at most +0.011 with every tree mapped,
  and negative ones with fewer mapped, against SegmentAnyTree's +0.034 on all
  plots and +0.063 inside the censused subplots.

**Judgment.** The point-cloud segmenters do split crowns, and more often than
the canopy-model detectors: by every measure here SegmentAnyTree,
ForestFormer3D and TreeisoNet place more second detections on one canopy crown
than CHM-VWF, which by construction rarely places two. But by the candidate
count they do so at an equivalent rate of about 0.15 to 0.45, below the
simulated 0.5 and 0.8; only an upper-bound view that also counts neighbouring
trees the arm resolves reaches 0.6 for SegmentAnyTree (Table 7). And
TreeisoNet, which places as many candidates as the two segmenters, has almost
no corrected recall lead. Split crowns therefore probably inflate part of the
segmenters' corrected recall leads, about a sixth to two-thirds of them on the
simulation's reading at the point estimates of Table 5's valley settings (up
to about seven-tenths over all twelve valley settings and nine-tenths or
more at their upper interval limits) and a seventh to two-fifths if the arms that
split as often are the guide (Table 5), and do not explain those leads or
their corrected F1 leads.

Confidence is moderate. The direction holds across both canopy models, six
valley thresholds, both scopes and the window-free pairs of Table 6. The size of
the inflated part is uncertain by a factor of two to three: the valley test
cannot tell a split piece from a neighbouring tree whose crown merges with the
first in the canopy model, and the translation into corrected recall rests on
the simulation's loose clusters standing in for the benchmark's stands.

## Method

`split_crown_diagnostic.R` reads every arm's persisted native-density
detections as the paper's scorers read them (`census_cell_detections`: the
apexes an arm wrote, or the highest point of each instance of its instance
cloud), on the sealed root's adopted population. Nine arms: the eight ladder
arms (CHM-VWF, `multichm`, `lmfauto`, `ptrees`, AMS3D, ForestFormer3D,
TreeisoNet, SegmentAnyTree) and Li 2012, the point-cloud segmenter scored at
native density only, whose corrected recall lead over CHM-VWF is +0.060.

- **Matching.** On all plots, the paper's baseline: greedy 1:1 matching within
  4 m with the height gate, against the core stems, as `paper_sensitivity.R`
  scores it. Inside the censused subplots, the censused scorer
  (`score_neon_support`) of the headline declaration. The run stops unless
  every cell's reference, detection and true-positive counts equal the arms'
  own results (954 cells) and the committed censused scores (513 cells); both
  checks pass.
- **Close pairs.** Pairs of one arm's detections 1.5 to 4 m apart (the
  simulation's split distance and the matching radius) inside the scoring
  region (the scored area plus 4 m), at least one of them a counted
  detection: in the nominal core, or in the censused interior. The close-pair
  rate is the share of counted detections with such a neighbour. For the
  reference stems, the share of scored stems with another mapped stem 1.5 to
  4 m away.
- **Valley test.** The canopy model is sampled at 41 points along the segment
  between the two detections (every 0.1 m or less); empty cells are skipped,
  and a profile with fewer than half its samples on the model gives no verdict
  (0.1% of pairs on the p2r model, none on the pit-free model). The valley
  depth is the lower of the two ends minus the lowest sample. A pair has no
  valley when the depth is at most a threshold: 0.5, 1 or 2 m, or 5%, 10% or
  20% of the lower end's height. A detection more than 2 m below the canopy
  surface at its own position lies beneath the canopy (an understory tree, or
  a lower part of a crown).
- **Canopy models.** Two models of the native normalized clip at 0.5 m: the
  highest point per cell, as the paper builds the canopy model for the optical
  arms ("p2r"), and lidR's pit-free model (layers at 0, 2, 5, 10 and 15 m,
  maximum edge 0 and 1.5 m, subcircle 0.15 m). The first keeps laser pits,
  which read as valleys and so classify a split crown as two crowns; the second
  closes pits but also fills some narrow valleys between crowns. The two are
  meant to bracket the truth.
- **Split-crown candidates.** Counted detections that the matcher leaves
  unmatched (the arm's false positives) lying 1.5 to 4 m from a matched
  detection of the same arm with no valley between them, per detected tree
  (true positive). "Distance only" drops the valley test.
- **Pooling.** Counts are summed over plots and ratios taken of the sums.
  Intervals are 95% percentile intervals of the master tables' paired plot
  bootstrap (1,000 resamples, seed 20261002, plots resampled within sites,
  drawn on each scope's plots), shared by every arm, so leads over CHM-VWF are
  paired.
- **Calibration.** The same counts, by distance only, on the
  [simulation's](chance-correction-simulation-results.md) own plots (200 per
  stand structure, 240 trees/ha, every tree mapped, the simulation's seeds),
  for its baseline detector (skill 0.45, commission 0.45) and its split
  crowns at rates 0.5 and 0.8, matched in the 40 m core. The rise of
  candidates per detected tree over rate 0 is the count's response to splitting.
  An arm's **equivalent split rate** is its lead over CHM-VWF in candidates per
  detected tree divided by the loose clusters' response per unit rate, the
  least-squares slope through the origin of the rises at 0.5 and 0.8 (0.313).
  The slope's Monte Carlo error is not propagated.

## Results

### Table 1. Close pairs

Share of counted detections with another detection of the same arm 1.5 to 4 m
away. The last column is the share with one closer than 1.5 m (all plots).

| Arm | All plots: detections | Close-pair rate | Lead over CHM-VWF | Censused: detections | Close-pair rate | Lead over CHM-VWF | Closer than 1.5 m |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 3,349 | 0.763 [0.726, 0.795] | +0.215 [+0.169, +0.271] | 871 | 0.746 [0.695, 0.791] | +0.207 [+0.135, +0.285] | 0.098 |
| ForestFormer3D | 3,441 | 0.693 [0.665, 0.715] | +0.145 [+0.087, +0.216] | 963 | 0.726 [0.696, 0.759] | +0.187 [+0.110, +0.278] | 0.079 |
| Li 2012 | 3,458 | 0.712 [0.655, 0.756] | +0.164 [+0.129, +0.211] | 874 | 0.693 [0.608, 0.760] | +0.154 [+0.097, +0.217] | 0.000 |
| TreeisoNet | 3,032 | 0.729 [0.680, 0.770] | +0.180 [+0.133, +0.232] | 761 | 0.696 [0.629, 0.755] | +0.158 [+0.092, +0.232] | 0.000 |
| CHM-VWF | 2,475 | 0.548 [0.472, 0.609] | — | 642 | 0.539 [0.447, 0.618] | — | 0.000 |
| `multichm` | 3,157 | 0.556 [0.534, 0.579] | +0.008 [−0.056, +0.089] | 866 | 0.577 [0.536, 0.613] | +0.038 [−0.061, +0.145] | 0.000 |
| `lmfauto` | 4,440 | 0.780 [0.709, 0.827] | +0.232 [+0.188, +0.282] | 1,257 | 0.804 [0.720, 0.858] | +0.265 [+0.196, +0.333] | 0.242 |
| `ptrees` | 7,847 | 0.942 [0.927, 0.954] | +0.394 [+0.336, +0.464] | 2,090 | 0.939 [0.916, 0.958] | +0.400 [+0.319, +0.490] | 0.466 |
| AMS3D | 11,781 | 0.973 [0.965, 0.979] | +0.424 [+0.367, +0.495] | 3,117 | 0.974 [0.963, 0.984] | +0.435 [+0.364, +0.521] | 0.670 |
| Reference stems | 2,525 | 0.825 [0.787, 0.857] | — | 1,190 | 0.808 [0.749, 0.855] | — | 0.293 |

- Real trees stand 1.5 to 4 m apart routinely: the mapped stems, which leave
  out trees below 10 cm DBH and dead trees, have a higher close-pair rate than
  every arm except `ptrees` and AMS3D, which over-segment.
  A higher close-pair rate is therefore what more complete detection would give
  as well; the valley test is needed to tell the two apart.
- CHM-VWF's variable window (3 to 5 m, from 0.1 × height + 3 m) forbids two
  maxima closer than half the lower top's window, so it has no pair closer
  than 1.5 m and few closer than 2.5 m (Table 6). ForestFormer3D's reader merges
  instances of neighbouring blocks whose centres lie within 2 m, which also
  removes some close pairs.

### Table 2. Valley test

Share of close pairs with no valley, at the 1 m threshold and across all six
thresholds (0.5, 1 and 2 m; 5%, 10% and 20%). "Beneath" is the share of the
pairs without a valley at 1 m whose lower detection lies more than 2 m below
the canopy surface (p2r model).

| Arm | All plots: close pairs | p2r, 1 m | p2r, range | Pit-free, 1 m | Pit-free, range | Beneath | Censused: p2r, 1 m | Pit-free, 1 m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 2,851 | 0.253 [0.211, 0.304] | 0.204–0.400 | 0.463 [0.415, 0.518] | 0.353–0.708 | 0.33 | 0.213 [0.169, 0.269] | 0.396 [0.332, 0.474] |
| ForestFormer3D | 2,132 | 0.358 [0.313, 0.404] | 0.318–0.516 | 0.560 [0.509, 0.613] | 0.477–0.743 | 0.70 | 0.371 [0.316, 0.427] | 0.548 [0.490, 0.606] |
| Li 2012 | 3,278 | 0.091 [0.066, 0.123] | 0.022–0.286 | 0.340 [0.293, 0.392] | 0.141–0.685 | 0.00 | 0.034 [0.021, 0.048] | 0.221 [0.182, 0.262] |
| TreeisoNet | 2,314 | 0.279 [0.230, 0.337] | 0.193–0.437 | 0.493 [0.437, 0.554] | 0.377–0.725 | 0.00 | 0.202 [0.153, 0.256] | 0.387 [0.324, 0.454] |
| CHM-VWF | 1,468 | 0.072 [0.051, 0.100] | 0.028–0.223 | 0.193 [0.155, 0.242] | 0.067–0.556 | 0.07 | 0.049 [0.025, 0.078] | 0.146 [0.103, 0.202] |
| `multichm` | 1,317 | 0.375 [0.342, 0.411] | 0.311–0.569 | 0.615 [0.582, 0.655] | 0.521–0.816 | 0.93 | 0.359 [0.304, 0.411] | 0.612 [0.558, 0.667] |
| `lmfauto` | 9,130 | 0.196 [0.171, 0.217] | 0.060–0.419 | 0.542 [0.495, 0.579] | 0.296–0.799 | 0.00 | 0.192 [0.149, 0.226] | 0.527 [0.461, 0.579] |
| `ptrees` | 30,950 | 0.502 [0.463, 0.536] | 0.417–0.645 | 0.713 [0.686, 0.735] | 0.612–0.860 | 0.46 | 0.453 [0.408, 0.490] | 0.674 [0.632, 0.704] |
| AMS3D | 53,898 | 0.497 [0.473, 0.521] | 0.314–0.657 | 0.740 [0.719, 0.761] | 0.537–0.868 | 0.34 | 0.466 [0.440, 0.493] | 0.712 [0.686, 0.735] |

- The canopy model matters as much as the threshold: closing the pits raises
  CHM-VWF's share at 1 m from 0.07 to 0.19 and the segmenters' from 0.25 and
  0.36 to 0.46 and 0.56. The ordering does not change: in every setting the
  segmenters' pairs lie on one crown more often than CHM-VWF's, by a factor of
  1.3 (pit-free model, 2 m) to 13 (p2r model, 5%) on all plots.
- CHM-VWF's tops are maxima of its own pit-filled canopy model (smoothed only
  on the 18 native cells below 8 pulses/m²), so a valley between two of them
  is close to guaranteed there; their low share is partly mechanical.
- Many of ForestFormer3D's and `multichm`'s pairs without a valley hold a
  detection well beneath the canopy surface: an understory instance under a
  neighbour's crown, or a lower part of the same tree. The canopy model cannot
  tell these apart. TreeisoNet's, Li 2012's and `lmfauto`'s detections sit on
  the surface.

### Table 3. Split-crown candidates per detected tree

Unmatched counted detections 1.5 to 4 m from a matched detection of the same
arm, per true positive; "distance only" without the valley test, the other
columns with no valley at the threshold given.

| Arm | All plots: detected trees | Distance only | p2r, 1 m | Pit-free, 1 m | Pit-free, 2 m | Censused: detected trees | Distance only | p2r, 1 m | Pit-free, 1 m | Pit-free, 2 m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 1,525 | 0.233 [0.203, 0.265] | 0.094 [0.075, 0.116] | 0.154 [0.130, 0.180] | 0.199 [0.173, 0.227] | 762 | 0.160 [0.126, 0.197] | 0.060 [0.042, 0.081] | 0.104 [0.078, 0.135] | 0.135 [0.107, 0.166] |
| ForestFormer3D | 1,569 | 0.227 [0.193, 0.265] | 0.121 [0.095, 0.149] | 0.171 [0.140, 0.204] | 0.194 [0.162, 0.229] | 786 | 0.198 [0.160, 0.236] | 0.111 [0.082, 0.142] | 0.153 [0.120, 0.189] | 0.173 [0.138, 0.207] |
| Li 2012 | 1,417 | 0.239 [0.198, 0.288] | 0.027 [0.017, 0.039] | 0.111 [0.088, 0.139] | 0.193 [0.160, 0.233] | 705 | 0.173 [0.125, 0.225] | 0.013 [0.005, 0.022] | 0.077 [0.053, 0.101] | 0.140 [0.098, 0.185] |
| TreeisoNet | 1,298 | 0.250 [0.206, 0.294] | 0.108 [0.081, 0.134] | 0.166 [0.130, 0.202] | 0.210 [0.169, 0.249] | 651 | 0.167 [0.137, 0.203] | 0.069 [0.043, 0.100] | 0.108 [0.076, 0.144] | 0.137 [0.106, 0.171] |
| CHM-VWF | 1,172 | 0.115 [0.087, 0.147] | 0.013 [0.007, 0.020] | 0.036 [0.023, 0.051] | 0.078 [0.058, 0.101] | 594 | 0.082 [0.050, 0.120] | 0.012 [0.005, 0.020] | 0.027 [0.012, 0.042] | 0.052 [0.029, 0.079] |
| `multichm` | 1,366 | 0.228 [0.200, 0.257] | 0.100 [0.082, 0.118] | 0.157 [0.134, 0.183] | 0.189 [0.165, 0.216] | 670 | 0.181 [0.148, 0.212] | 0.075 [0.051, 0.099] | 0.128 [0.099, 0.159] | 0.152 [0.121, 0.184] |
| `lmfauto` | 1,401 | 0.570 [0.411, 0.734] | 0.200 [0.137, 0.266] | 0.397 [0.275, 0.521] | 0.500 [0.357, 0.648] | 709 | 0.612 [0.379, 0.830] | 0.219 [0.129, 0.305] | 0.433 [0.268, 0.593] | 0.549 [0.334, 0.751] |
| `ptrees` | 1,797 | 1.174 [0.918, 1.454] | 0.712 [0.525, 0.928] | 0.938 [0.711, 1.188] | 1.057 [0.815, 1.323] | 883 | 0.954 [0.681, 1.276] | 0.596 [0.389, 0.839] | 0.775 [0.530, 1.072] | 0.864 [0.603, 1.166] |
| AMS3D | 1,801 | 1.952 [1.695, 2.233] | 1.303 [1.120, 1.500] | 1.660 [1.433, 1.906] | 1.823 [1.583, 2.099] | 857 | 1.774 [1.471, 2.100] | 1.172 [0.969, 1.383] | 1.505 [1.254, 1.789] | 1.659 [1.371, 1.963] |

- The relative thresholds give values close to the absolute ones, 5% near
  0.5 m and 20% near 2 m (`split_crowns_tables.md`). With the 2 m pit-free
  setting, the most generous one, the three learned segmenters place 0.19 to
  0.21 candidates per detected tree on all plots and 0.14 to 0.17 inside the
  censused subplots, and Li 2012 as many; CHM-VWF places 0.08 and 0.05.
- Inside the censused subplots the candidates are 19% (SegmentAnyTree) to 28%
  (ForestFormer3D) of the segmenters' false positives on the p2r model at 1 m,
  42% and 44% on the pit-free model at 2 m; for CHM-VWF 5% and 22%.
- Of the segmenters' surplus of counted detections over CHM-VWF, 35% and 39%
  on all plots, candidates make up 15% (SegmentAnyTree) and 18%
  (ForestFormer3D) on the p2r model at 1 m and 25% and 23% by distance only
  (`split_crowns_surplus.csv`).

### Table 4. Calibration on the simulation's plots

The diagnostic's counts by distance only, on 200 simulated plots per stand
structure at 240 trees/ha with every tree mapped. "Minus rate 0" is the rise
over the same detector without split crowns.

| Stand | Split rate | Candidates per detected tree | Minus rate 0 | Trees with a candidate | Matched pairs per detected tree | Minus rate 0 | Split pieces matched |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Unclustered | 0 | 0.228 [0.214, 0.243] | — | 0.247 | 0.232 | — | — |
| Unclustered | 0.5 | 0.401 [0.384, 0.418] | +0.173 [+0.161, +0.185] | 0.419 | 0.306 | +0.074 [+0.064, +0.083] | 0.391 |
| Unclustered | 0.8 | 0.510 [0.491, 0.529] | +0.282 [+0.267, +0.296] | 0.509 | 0.337 | +0.105 [+0.093, +0.115] | 0.376 |
| Loose clusters | 0 | 0.191 [0.180, 0.202] | — | 0.237 | 0.422 | — | — |
| Loose clusters | 0.5 | 0.335 [0.320, 0.351] | +0.144 [+0.133, +0.156] | 0.419 | 0.573 | +0.151 [+0.134, +0.169] | 0.493 |
| Loose clusters | 0.8 | 0.449 [0.432, 0.466] | +0.258 [+0.244, +0.272] | 0.534 | 0.627 | +0.206 [+0.187, +0.226] | 0.453 |
| Tight clusters | 0 | 0.149 [0.137, 0.160] | — | 0.194 | 0.793 | — | — |
| Tight clusters | 0.5 | 0.272 [0.258, 0.287] | +0.124 [+0.113, +0.135] | 0.412 | 1.086 | +0.293 [+0.265, +0.323] | 0.610 |
| Tight clusters | 0.8 | 0.348 [0.331, 0.364] | +0.199 [+0.185, +0.213] | 0.520 | 1.226 | +0.432 [+0.397, +0.467] | 0.591 |

- The count rises by about 0.3 per unit of split rate, not by the rate itself,
  for two reasons. Two-fifths to three-fifths of the split pieces end up
  matched (last column): the piece lies nearer to its own stem than the tree's
  own detection does and takes the match, or it matches a neighbouring stem,
  the mechanism by which split crowns lift corrected recall. And a piece placed
  1.5 to 4 m from its tree can lie outside 1.5 to 4 m of the tree's own
  detection.
- The rise in matched pairs counts pieces that matched a neighbouring stem
  while the tree's own detection kept its own; it is largest in the tight
  clusters. The benchmark's counterpart is Table 7.

### Table 5. Equivalent split rate

Each arm's lead over CHM-VWF in candidates per detected tree (Table 3), and
that lead divided by the loose clusters' response, 0.313 per unit split rate.

| Arm | Scope | Distance only | p2r, 1 m | Pit-free, 1 m | Pit-free, 2 m |
| --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | All plots | +0.118 [+0.084, +0.157]; 0.38 [0.27, 0.50] | +0.081 [+0.062, +0.103]; 0.26 [0.20, 0.33] | +0.118 [+0.090, +0.146]; 0.38 [0.29, 0.47] | +0.122 [+0.094, +0.151]; 0.39 [0.30, 0.48] |
| ForestFormer3D | All plots | +0.112 [+0.069, +0.157]; 0.36 [0.22, 0.50] | +0.108 [+0.082, +0.137]; 0.35 [0.26, 0.44] | +0.135 [+0.101, +0.171]; 0.43 [0.32, 0.55] | +0.116 [+0.081, +0.157]; 0.37 [0.26, 0.50] |
| Li 2012 | All plots | +0.123 [+0.093, +0.159]; 0.39 [0.30, 0.51] | +0.014 [+0.005, +0.024]; 0.05 [0.02, 0.08] | +0.075 [+0.056, +0.100]; 0.24 [0.18, 0.32] | +0.115 [+0.091, +0.143]; 0.37 [0.29, 0.46] |
| TreeisoNet | All plots | +0.135 [+0.094, +0.177]; 0.43 [0.30, 0.57] | +0.095 [+0.071, +0.120]; 0.30 [0.23, 0.38] | +0.131 [+0.096, +0.165]; 0.42 [0.31, 0.53] | +0.132 [+0.095, +0.170]; 0.42 [0.30, 0.54] |
| `multichm` | All plots | +0.112 [+0.074, +0.154]; 0.36 [0.24, 0.49] | +0.087 [+0.068, +0.106]; 0.28 [0.22, 0.34] | +0.122 [+0.095, +0.150]; 0.39 [0.30, 0.48] | +0.111 [+0.079, +0.144]; 0.36 [0.25, 0.46] |
| SegmentAnyTree | Censused | +0.078 [+0.041, +0.117]; 0.25 [0.13, 0.38] | +0.049 [+0.029, +0.070]; 0.16 [0.09, 0.22] | +0.077 [+0.046, +0.111]; 0.25 [0.15, 0.35] | +0.083 [+0.052, +0.118]; 0.27 [0.17, 0.38] |
| ForestFormer3D | Censused | +0.116 [+0.068, +0.167]; 0.37 [0.22, 0.53] | +0.099 [+0.071, +0.130]; 0.32 [0.23, 0.41] | +0.126 [+0.092, +0.164]; 0.40 [0.29, 0.52] | +0.121 [+0.081, +0.161]; 0.39 [0.26, 0.52] |
| Li 2012 | Censused | +0.091 [+0.055, +0.126]; 0.29 [0.18, 0.40] | +0.001 [−0.008, +0.010]; 0.00 [−0.03, 0.03] | +0.050 [+0.031, +0.068]; 0.16 [0.10, 0.22] | +0.088 [+0.057, +0.118]; 0.28 [0.18, 0.38] |
| TreeisoNet | Censused | +0.085 [+0.046, +0.130]; 0.27 [0.15, 0.41] | +0.057 [+0.032, +0.088]; 0.18 [0.10, 0.28] | +0.081 [+0.048, +0.117]; 0.26 [0.15, 0.37] | +0.085 [+0.049, +0.125]; 0.27 [0.16, 0.40] |
| `multichm` | Censused | +0.098 [+0.051, +0.149]; 0.31 [0.16, 0.48] | +0.063 [+0.040, +0.085]; 0.20 [0.13, 0.27] | +0.101 [+0.072, +0.135]; 0.32 [0.23, 0.43] | +0.100 [+0.065, +0.138]; 0.32 [0.21, 0.44] |

- `lmfauto`, `ptrees` and AMS3D split far more often (equivalent rates 0.6 to
  5.9; `split_crowns_equivalent.csv`), with negative corrected F1 leads.
- In the loose clusters the simulated split crowns raise corrected recall by
  +0.086 at rate 0.5 and +0.126 at 0.8 with every tree mapped, and by +0.066
  to +0.115 with 80% or 60% of the trees mapped at 240 trees/ha
  ([simulation](chance-correction-simulation-results.md), Table 7): 0.12 to 0.17
  per unit of split rate. Multiplied by the equivalent rates of the three valley
  settings, that is +0.030 to +0.067 for SegmentAnyTree on all plots and +0.018
  to +0.046 inside the censused subplots, and +0.041 to +0.074 and +0.037 to
  +0.069 for ForestFormer3D. Their corrected recall leads are +0.112 [+0.079,
  +0.145] and +0.108 [+0.079, +0.139] on all plots
  ([chance agreement](matcher-robustness-results.md#chance-agreement)), and
  +0.113 [+0.072, +0.149] and +0.102 [+0.058, +0.150] inside the censused
  subplots ([censused chance agreement](censused-chance-agreement-results.md)).
- On the same reading TreeisoNet and `multichm` would gain +0.033 to +0.073 in
  corrected recall from splitting alone; their leads are +0.024 [+0.004,
  +0.044] and +0.030 [+0.002, +0.059]. Either their candidates lift corrected
  recall less than the simulated split crowns do, or the arms lose about as
  much elsewhere. Either way, splitting at the segmenters' rate does not by
  itself give a corrected recall lead of 0.11. If the whole corrected recall
  lead of TreeisoNet or `multichm` came from their candidates, splitting would
  be worth 0.06 to 0.11 of corrected recall per unit of equivalent rate, and
  the segmenters' candidates +0.015 to +0.047 on all plots: a seventh to
  two-fifths of their leads.

### Table 6. Pairs 2.5 to 4 m apart

The same counts with the inner radius at 2.5 m, beyond CHM-VWF's smallest
half-window of 1.5 m and its usual 2 to 2.5 m (`split_crowns/rmin2.5`). The
loose clusters' response falls to 0.263 per unit split rate.

| Arm | All plots: close-pair rate | Lead in candidates, p2r 1 m | Equivalent rate | Lead, pit-free 1 m | Equivalent rate | Censused: lead, p2r 1 m | Equivalent rate | Lead, pit-free 1 m | Equivalent rate |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.684 [0.643, 0.721] | +0.057 [+0.043, +0.073] | 0.22 [0.16, 0.28] | +0.080 [+0.058, +0.103] | 0.31 [0.22, 0.39] | +0.033 [+0.018, +0.050] | 0.13 [0.07, 0.19] | +0.058 [+0.034, +0.084] | 0.22 [0.13, 0.32] |
| ForestFormer3D | 0.615 [0.586, 0.638] | +0.081 [+0.060, +0.104] | 0.31 [0.23, 0.40] | +0.101 [+0.072, +0.133] | 0.39 [0.28, 0.51] | +0.064 [+0.041, +0.089] | 0.24 [0.16, 0.34] | +0.086 [+0.058, +0.115] | 0.33 [0.22, 0.44] |
| TreeisoNet | 0.722 [0.671, 0.763] | +0.092 [+0.069, +0.116] | 0.35 [0.26, 0.44] | +0.129 [+0.095, +0.164] | 0.49 [0.36, 0.63] | +0.056 [+0.032, +0.086] | 0.21 [0.12, 0.33] | +0.081 [+0.050, +0.117] | 0.31 [0.19, 0.45] |
| CHM-VWF | 0.528 [0.454, 0.589] | — | — | — | — | — | — | — | — |

- CHM-VWF's close-pair rate barely moves (0.548 to 0.528): its close pairs lie
  beyond its window. The segmenters' fall by 0.08. Their leads in candidates
  shrink by a quarter to a third and the simulation's response by a sixth, so
  the equivalent rates fall a little (SegmentAnyTree 0.22 to 0.31 on all
  plots, against 0.26 to 0.38 at 1.5 to 4 m). The window's suppression of close
  pairs does not drive the comparison.

### Table 7. Matched pairs on one crown

Pairs of two matched detections 1.5 to 4 m apart, per detected tree; on one
crown means no valley at 1 m. Such a pair is either two mapped trees whose
crowns merge in the canopy model, resolved by the arm, or a split piece that
took a neighbouring stem's match.

| Arm | All plots: all matched pairs | On one crown, p2r | Lead over CHM-VWF | On one crown, pit-free | Lead over CHM-VWF | Censused: on one crown, p2r | Lead over CHM-VWF |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.479 [0.406, 0.540] | 0.096 [0.069, 0.124] | +0.090 [+0.061, +0.119] | 0.188 [0.150, 0.228] | +0.159 [+0.122, +0.199] | 0.064 [0.044, 0.085] | +0.061 [+0.040, +0.082] |
| ForestFormer3D | 0.330 [0.291, 0.368] | 0.091 [0.072, 0.109] | +0.084 [+0.063, +0.103] | 0.152 [0.127, 0.178] | +0.123 [+0.096, +0.151] | 0.084 [0.062, 0.108] | +0.081 [+0.057, +0.106] |
| Li 2012 | 0.519 [0.419, 0.615] | 0.020 [0.011, 0.028] | +0.013 [+0.004, +0.022] | 0.115 [0.089, 0.142] | +0.086 [+0.061, +0.112] | 0.010 [0.001, 0.020] | +0.007 [−0.002, +0.016] |
| TreeisoNet | 0.403 [0.334, 0.466] | 0.072 [0.047, 0.097] | +0.065 [+0.039, +0.092] | 0.132 [0.102, 0.161] | +0.103 [+0.075, +0.133] | 0.043 [0.030, 0.057] | +0.040 [+0.024, +0.054] |
| CHM-VWF | 0.346 [0.263, 0.428] | 0.007 [0.003, 0.011] | — | 0.029 [0.019, 0.038] | — | 0.003 [0.000, 0.008] | — |

- Against the loose clusters' rise in matched pairs (+0.151 at rate 0.5,
  +0.206 at 0.8; Table 4; least-squares slope 0.27 per unit rate),
  SegmentAnyTree's lead on one crown corresponds to a rate of 0.33 on the p2r
  model and 0.59 on the pit-free model, ForestFormer3D's to 0.31 and 0.46.
  This view counts resolved neighbours as splits, so it bounds the split rate
  from above; it is the only one that reaches the simulated 0.5.

## Limits

- **Unmapped trees.** The reference leaves out stems below 10 cm DBH, dead
  trees and census targets without a usable position. A candidate may be such
  a tree standing beside a mapped one, and an arm that finds more small trees
  places more candidates without splitting. The counts are therefore upper
  bounds on splitting, in so far as the valley test passes these trees.
- **Neighbouring crowns.** Two trees whose crowns interlock, or a small tree
  under a neighbour's crown, show no valley in the canopy model. The point-cloud
  segmenters can separate such trees and CHM-VWF cannot, so part of their lead
  in candidates and in matched pairs on one crown may be skill. The "beneath"
  share of Table 2 marks part of this: 33% of SegmentAnyTree's and 70% of
  ForestFormer3D's pairs without a valley hold a detection more than 2 m below
  the canopy surface.
- **Window suppression.** CHM-VWF's window rules out a second top within 1.5 to
  2.5 m, and its tops are maxima of its own canopy model (smoothed on 18 of
  the 106 native cells), so its low counts are partly by construction.
  Table 6 repeats the counts beyond the window; the comparison holds.
- **Canopy-model resolution.** Both models are 0.5 m grids of a native clip of
  a few to about twenty pulses per m². A valley narrower than a cell or two can
  vanish, and a laser pit can read as a valley. The p2r and pit-free models
  bracket these effects; neither is a ground truth for crown boundaries.
- **Calibration.** The equivalent rates and the corrected recall they imply
  assume the loose clusters stand in for the benchmark's stands, as the
  clustering of its reference stems on all 54 distributed plots suggests. On
  the 24 of them with admitted census support the stems lie between the
  unclustered stand and the loose clusters, and a less clustered stand-in
  lowers the lift attributed to split crowns. In the tight clusters the same
  candidates would imply about twice the lift in corrected recall; in the
  unclustered stand about a third. The simulated split pieces lie at the tree's
  height; many of the segmenters' candidates lie lower, where the matcher's
  height gate restricts which stems they can match.
- **Scope.** Native density only; the thinned rungs are not examined.

## Reproduce

From the repository root, with the paper's job directory (the censused scores
of the headline declaration must exist; the reproduction script builds them
first):

```sh
CLAUDE_JOB_DIR=<paper_runs> Rscript scripts/split_crown_diagnostic.R CORES=8
CLAUDE_JOB_DIR=<paper_runs> Rscript scripts/split_crown_diagnostic.R RMIN=2.5 \
  CORES=8 OUT=<paper_runs>/sensitivity/split_crowns/rmin2.5
```

Outputs go to `<paper_runs>/sensitivity/split_crowns/`:
`split_crowns_cells.csv` (per plot, arm, canopy model and threshold),
`split_crowns_pairs.csv` (every close pair with its profile),
`split_crowns_pooled.csv`, `split_crowns_leads.csv`,
`split_crowns_surplus.csv`, `split_crowns_reference.csv`,
`split_crowns_simulation.csv`, `split_crowns_equivalent.csv`,
`split_crowns_checks.txt` and `split_crowns_tables.md`. The run takes under a
minute on 8 cores, and its outputs do not depend on the number of cores.
`reproduce_paper_tables.sh` runs both commands after the chance-correction
simulation. Unit tests: `tests/testthat/test-split-crown.R`.
