# Chance Agreement inside Censused Subplots

Checked on 17 November 2026. This analysis is post hoc: it was added after all
five-site results were known and after an internal review of the paper. It
computes the paper's chance-agreement null inside the censused subplots of the
[censused-subplot study](census-support-results.md), which the null had not
covered.

The [chance-agreement null](matcher-robustness-results.md#chance-agreement)
shifts each cell's detections together by a random toroidal offset and scores
the shifted copies in the nominal plot box. The censused scores that the paper
reports beside the nominal ones therefore had no chance correction. Here the
same shifted copies are scored by the censused scorer on the 57 plots that the
headline declaration admits (1,190 censused references), with the same
offsets, matcher, pooling and plot resamples as the paper.

Pooled over the five sites, at native density and a 4 m radius unless stated:

- The null is as large inside the censused subplots as in the nominal box. It
  reaches 0.72 to 0.83 of every arm's censused F1, against 0.71 to 0.81 of the
  nominal-box F1 on the same plots.
- SegmentAnyTree's censused lead over CHM-VWF is mostly not chance agreement:
  +0.063 [+0.016, +0.108] above the null, against +0.068 [+0.036, +0.100]
  observed. Two sensitivities bring its lower limit to zero: under the strict
  declaration the interval just includes it (+0.052 [−0.002, +0.100]), and
  without the plots that hold a reference outside the nominal box it narrowly
  excludes it (+0.052 [+0.002, +0.098]).
- ForestFormer3D's censused lead halves under the correction, from +0.059
  [+0.020, +0.099] to +0.030 [−0.016, +0.074]. Li 2012's goes from +0.030 to
  +0.025 [−0.004, +0.057], TreeisoNet is level with CHM-VWF and `multichm` falls
  below it (−0.043 [−0.082, −0.008]).
- At a 2 m radius SegmentAnyTree keeps a corrected censused lead of +0.034
  [+0.006, +0.063]; ForestFormer3D's is +0.011 [−0.021, +0.044].
- At 4 m SegmentAnyTree's corrected censused lead is about the same in
  California (+0.067, 12 plots, interval −0.042 to +0.167) and Washington
  (+0.058 [+0.005, +0.105], 45 plots), whereas the nominal null puts the
  segmenters' leads above chance only in California. The Washington lead
  narrowly excludes zero under the headline declaration only: it is +0.046
  [−0.017, +0.097] under the strict declaration, +0.040 [−0.017, +0.088] without
  the plots that hold a reference outside the nominal box (eight of the nine are
  in Washington) and +0.026 [−0.005, +0.056] at 2 m. At 2 m the leads are larger
  in California again; the difference between the regions was not tested.
- Below native density, CHM-VWF's censused corrected F1 falls from 0.303 to
  0.203–0.227, and corrected censused leads that exclude zero are more common
  than in the nominal box: TreeisoNet's at every thinned rung (+0.060 to
  +0.093), SegmentAnyTree's at rungs 8, 4 and 3.2, ForestFormer3D's at 8, 3.2
  and 2. At the QL2 rung (3.2 points/m²) they are +0.053, +0.069 and +0.093,
  where the paper's nominal leads are +0.014 to +0.017, none excluding zero.
  Four of these fifteen leads, SegmentAnyTree's at the QL2 rung among them, do
  not exclude zero without the nine plots that hold a reference outside the
  nominal box ([sensitivities](#sensitivities)).
- These thinned-level leads come from the declared baseline's smoothing. CHM-VWF
  run without its sub-8 pulses/m² smoothing keeps a censused corrected F1 of
  0.268 to 0.313 below native density, and over it no detector has a positive
  corrected censused lead that excludes zero at any thinned level at 4 m. At
  native density SegmentAnyTree's lead over it is +0.057 [+0.009, +0.104].

Censused F1 is higher than nominal-box F1 for every arm, and so is corrected
F1, so the same relative advantage gives a larger absolute lead inside the
censused subplots. Relative to CHM-VWF's corrected F1 at native density and
4 m, SegmentAnyTree's corrected lead is 21% inside the censused subplots, 14%
in the nominal box on the same plots and 17% on all 106 plots; ForestFormer3D's
is 10%, 0% and 10%.

## Why the censused interior

In a 40 m tower plot NEON maps trees in two of the four 20 m subplots. Of the
1,649 adopted reference stems in the cores of the 52 tower plots, 1,622
(98.4%) lie in the two fullest 20 m quadrants of their core, and in 46 of the
52 plots these two quadrants hold 95% or more. Two tower plots have stems in a
single quadrant, 33 in two, 16 in three and one in four. Tower cores make up
8.32 of the 10.48 ha of nominal core (79%), so about two-fifths of the area
in which the paper counts observed and null detections (half of every tower
core) holds no mapped reference. A detection there can only be a false
positive, in the observed score and in the null alike. The 54 distributed
plots are a single 20 m subplot; when censused, they are censused whole.

The censused interior of an admitted plot is its sampled subplots, eroded by the
positional uncertainty ([censused-subplot study](census-support-results.md)). It
averages 572 m² on the 33 admitted tower plots (304 to 752 m²) and 341 m² on the
24 admitted distributed plots (299 to 383 m²). The 57 interiors total 27,038 m²,
against 62,400 m² of nominal boxes.

## Method

`paper_census_null.R` reads every arm's persisted detections, as the censused
scorer does, and repeats the null of `paper_sensitivity.R MODE=null` without
changing it:

- Per admitted plot, K = 200 offsets
  `null_offset(2 (ph + TOL), seed_for(site, plot, "null") + SEED × 1000003 + k,
  min_shift = 8)`, with half-width ph = 20 m (tower) or 10 m (distributed),
  TOL = 4 m and SEED = 0. The same offsets serve every arm and rung.
- Each shift moves the detections within ph + TOL of the plot centre together
  and wraps them at the edges of that square (`shift_detections`).
- Each shifted copy is scored by `census_score_cell` with the greedy matcher at
  radius TOL and the height gate. This gives the censused counts (references
  in the interior, detections in the interior, true positives and interior
  true positives) and the nominal-box counts of the same detections.
- A cell's null is its mean counts over the 200 shifts. Pooling sums counts
  over plots, never rates. Corrected F1 is (F1 − null F1) / (1 − null F1), for
  the estimate and for every draw of the master tables' paired plot bootstrap
  (1,000 resamples, seed 20261002, plots resampled within sites, drawn on each
  rung's admitted plots). A lead is an arm minus CHM-VWF, paired.
- At 2 m, TOL = 2 enters the offsets, the shift window and the matcher, as in
  `paper_sensitivity.R TOL=2`.

The run stops unless its parity checks pass, and writes a check file either
way:

- **A. Observed censused counts.** Every cell's observed censused and
  nominal-box counts at 4 m equal the committed censused scores
  (`census_support_scores/nearest_ladder` and `nearest_native`; for the QL2
  rung, those of its own job directory), with the same support identity and
  detection source, and no committed cell is left unscored. Result: 2,337
  cells on the native and thinned rungs and 456 at the QL2 rung, all equal
  (the 2 m runs also score each cell at 4 m for this check).
- **C. Nominal-box null.** Every cell's nominal-box observed counts and null
  mean counts equal the paper's null cells (`sensitivity/null_cells.csv` at
  4 m, `null_tol2_cells.csv` at 2 m, and the QL2 rung's own). Result: all
  equal, at both radii and on every rung. The nominal-box null reported here is
  therefore the paper's own null, restricted to the 57 admitted plots.

A third check runs for the headline declaration at 4 m: the observed censused
and nominal-box F1 leads over CHM-VWF equal the master tables' contrasts
(`master_contrasts.csv`) in every scope and rung. Result: 576 rows on the native
and thinned rungs and 112 at the QL2 rung, all equal within the check's
tolerance of 10⁻⁹. At native density SegmentAnyTree's observed censused lead is
+0.068 [+0.036, +0.100], ForestFormer3D's +0.059 [+0.020, +0.099] and Li 2012's
+0.030 [+0.011, +0.049], as in the paper's Table 5.

## Native density, 4 m

57 plots, 1,190 censused references (1,607 nominal-box stems on the same
plots). Null share is null F1 divided by observed F1. The last column gives,
for context, the paper's corrected lead in the nominal box on all 106 plots
(`sensitivity/null_leads.csv`).

| Arm | Censused F1 | Censused null F1 | Null share | Censused corrected F1 | Censused corrected lead | Censused observed lead | Nominal box, same plots: corrected lead | Nominal box, 106 plots: corrected lead |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.677 | 0.490 | 0.724 | 0.366 [0.324, 0.409] | +0.063 [+0.016, +0.108] | +0.068 [+0.036, +0.100] | +0.029 [+0.000, +0.059] | +0.034 [+0.008, +0.057] |
| ForestFormer3D | 0.668 | 0.502 | 0.752 | 0.333 [0.285, 0.385] | +0.030 [−0.016, +0.074] | +0.059 [+0.020, +0.099] | +0.000 [−0.030, +0.030] | +0.020 [−0.002, +0.041] |
| Li 2012 | 0.638 | 0.462 | 0.724 | 0.328 [0.287, 0.371] | +0.025 [−0.004, +0.057] | +0.030 [+0.011, +0.049] | +0.016 [+0.000, +0.034] | +0.000 [−0.015, +0.014] |
| TreeisoNet | 0.622 | 0.457 | 0.735 | 0.303 [0.261, 0.346] | +0.000 [−0.033, +0.030] | +0.013 [−0.009, +0.034] | −0.005 [−0.028, +0.014] | −0.011 [−0.029, +0.005] |
| CHM-VWF | 0.608 | 0.438 | 0.720 | 0.303 [0.260, 0.346] | — | — | — | — |
| `multichm` | 0.597 | 0.456 | 0.763 | 0.260 [0.220, 0.305] | −0.043 [−0.082, −0.008] | −0.011 [−0.047, +0.026] | −0.038 [−0.061, −0.014] | −0.017 [−0.039, +0.005] |
| `lmfauto` | 0.539 | 0.401 | 0.745 | 0.229 [0.180, 0.294] | −0.073 [−0.127, −0.012] | −0.070 [−0.117, −0.017] | −0.067 [−0.097, −0.030] | −0.056 [−0.079, −0.034] |
| `ptrees` | 0.496 | 0.389 | 0.785 | 0.175 [0.114, 0.245] | −0.128 [−0.201, −0.058] | −0.113 [−0.181, −0.046] | −0.104 [−0.142, −0.067] | −0.095 [−0.123, −0.067] |
| AMS3D | 0.364 | 0.300 | 0.826 | 0.090 [0.060, 0.126] | −0.212 [−0.257, −0.166] | −0.245 [−0.298, −0.188] | −0.148 [−0.179, −0.119] | −0.132 [−0.159, −0.107] |

- In the nominal box on the same 57 plots the null reaches 0.709 (Li 2012) to
  0.807 (AMS3D) of each arm's F1. Corrected F1 there is 0.242 [0.217, 0.268]
  for SegmentAnyTree, 0.229 for Li 2012, 0.213 for ForestFormer3D and CHM-VWF,
  and 0.207 for TreeisoNet.
- Censusing raises observed F1 by removing unmapped area from precision, and
  raises the null F1 about as much. The null puts as many detections into the
  interior as the observed detections do (null over observed 0.95 for AMS3D,
  0.99 to 1.04 for the other arms), so the null's precision rises with the
  censused reference density just as the observed precision does.
- SegmentAnyTree's observed censused lead (+0.068) is larger than its nominal
  lead on the same plots (+0.041 [+0.018, +0.066]), and nearly all of it stays
  above the null. ForestFormer3D's observed censused lead is of the same size
  (+0.059), but its shifted copies score higher (censused null F1 0.502,
  against 0.490 for SegmentAnyTree's and 0.438 for CHM-VWF's), so only +0.030
  remains after correction.
- In corrected censused F1 the order above CHM-VWF is SegmentAnyTree,
  ForestFormer3D and Li 2012 (0.366, 0.333 and 0.328), with TreeisoNet level
  with CHM-VWF (0.303 both). The three leaders' intervals overlap.

## 2 m radius

The same plots and offsets with TOL = 2 in the offsets, the shift window and
the matcher. Each observed score here is the arm's 2 m score.

| Arm | Censused F1 | Censused null F1 | Null share | Censused corrected F1 | Censused corrected lead | Censused observed lead | Nominal box, same plots: corrected lead | Nominal box, 106 plots: corrected lead |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.522 | 0.270 | 0.516 | 0.346 [0.299, 0.394] | +0.034 [+0.006, +0.063] | +0.047 [+0.021, +0.074] | +0.008 [−0.015, +0.031] | +0.017 [−0.001, +0.033] |
| ForestFormer3D | 0.496 | 0.255 | 0.514 | 0.323 [0.279, 0.365] | +0.011 [−0.021, +0.044] | +0.021 [−0.011, +0.054] | −0.008 [−0.034, +0.019] | +0.003 [−0.014, +0.021] |
| Li 2012 | 0.506 | 0.266 | 0.525 | 0.327 [0.278, 0.374] | +0.015 [−0.008, +0.038] | +0.031 [+0.013, +0.048] | −0.000 [−0.014, +0.015] | −0.006 [−0.019, +0.008] |
| TreeisoNet | 0.480 | 0.254 | 0.529 | 0.303 [0.251, 0.355] | −0.009 [−0.034, +0.015] | +0.005 [−0.016, +0.026] | −0.012 [−0.029, +0.004] | −0.010 [−0.023, +0.002] |
| CHM-VWF | 0.475 | 0.237 | 0.499 | 0.312 [0.266, 0.359] | — | — | — | — |
| `multichm` | 0.425 | 0.221 | 0.520 | 0.262 [0.220, 0.306] | −0.050 [−0.080, −0.018] | −0.050 [−0.080, −0.016] | −0.049 [−0.072, −0.025] | −0.031 [−0.050, −0.012] |
| `lmfauto` | 0.444 | 0.258 | 0.580 | 0.251 [0.207, 0.304] | −0.061 [−0.102, −0.018] | −0.031 [−0.063, +0.005] | −0.067 [−0.095, −0.037] | −0.052 [−0.073, −0.031] |
| `ptrees` | 0.394 | 0.231 | 0.586 | 0.212 [0.163, 0.267] | −0.100 [−0.144, −0.050] | −0.081 [−0.126, −0.034] | −0.097 [−0.129, −0.065] | −0.081 [−0.105, −0.057] |
| AMS3D | 0.292 | 0.184 | 0.629 | 0.133 [0.104, 0.162] | −0.179 [−0.221, −0.137] | −0.183 [−0.228, −0.138] | −0.145 [−0.175, −0.114] | −0.125 [−0.150, −0.102] |

- The null falls to about half of each arm's censused F1 (0.50 to 0.63; 0.50
  to 0.61 in the nominal box on the same plots). Corrected F1 changes little
  from 4 m for the leading arms (SegmentAnyTree 0.346 against 0.366,
  ForestFormer3D 0.323 against 0.333), while CHM-VWF's rises from 0.303 to
  0.312, so the leads shrink.
- SegmentAnyTree's corrected censused lead halves to +0.034 [+0.006, +0.063]
  but still excludes zero. ForestFormer3D's is +0.011 [−0.021, +0.044] and Li
  2012's +0.015 [−0.008, +0.038]. In the nominal box on the same plots the two
  segmenters' corrected leads are +0.008 and −0.008.

## Regions

Native density, 4 m. California has 12 admitted plots (SJER 2, SOAP 1, TEAK
9), Washington 45 (WREF 28, ABBY 17). The last two columns are the paper's
nominal-box corrected leads on all 106 plots (43 and 63).

| Arm | Censused corrected F1, California | Censused corrected F1, Washington | Censused corrected lead, California | Censused corrected lead, Washington | Censused observed lead, California | Censused observed lead, Washington | Nominal box, 106 plots: corrected lead, California | Nominal box, 106 plots: corrected lead, Washington |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.473 [0.388, 0.557] | 0.341 [0.293, 0.389] | +0.067 [−0.042, +0.167] | +0.058 [+0.005, +0.105] | +0.085 [+0.001, +0.158] | +0.066 [+0.030, +0.099] | +0.061 [+0.015, +0.103] | +0.017 [−0.014, +0.042] |
| ForestFormer3D | 0.440 [0.337, 0.552] | 0.313 [0.257, 0.368] | +0.034 [−0.057, +0.129] | +0.030 [−0.022, +0.078] | +0.061 [−0.005, +0.129] | +0.059 [+0.013, +0.104] | +0.060 [+0.026, +0.094] | +0.004 [−0.026, +0.029] |
| Li 2012 | 0.380 [0.324, 0.444] | 0.317 [0.271, 0.364] | −0.027 [−0.065, +0.007] | +0.034 [−0.002, +0.070] | −0.012 [−0.041, +0.013] | +0.036 [+0.014, +0.056] | −0.034 [−0.061, −0.010] | +0.017 [−0.002, +0.035] |
| TreeisoNet | 0.371 [0.290, 0.452] | 0.289 [0.240, 0.339] | −0.035 [−0.109, +0.040] | +0.005 [−0.030, +0.038] | −0.030 [−0.087, +0.025] | +0.019 [−0.005, +0.041] | −0.017 [−0.044, +0.008] | −0.008 [−0.032, +0.013] |
| CHM-VWF | 0.406 [0.339, 0.487] | 0.283 [0.236, 0.332] | — | — | — | — | — | — |
| `multichm` | 0.445 [0.363, 0.528] | 0.228 [0.183, 0.277] | +0.039 [−0.055, +0.113] | −0.055 [−0.098, −0.015] | +0.062 [−0.007, +0.116] | −0.021 [−0.061, +0.021] | +0.021 [−0.022, +0.062] | −0.034 [−0.060, −0.009] |
| `lmfauto` | 0.363 [0.289, 0.455] | 0.213 [0.162, 0.282] | −0.044 [−0.093, +0.004] | −0.070 [−0.129, −0.003] | −0.032 [−0.069, +0.004] | −0.074 [−0.127, −0.016] | −0.036 [−0.061, −0.011] | −0.060 [−0.088, −0.030] |
| `ptrees` | 0.245 [0.155, 0.366] | 0.164 [0.095, 0.240] | −0.161 [−0.268, −0.053] | −0.120 [−0.202, −0.041] | −0.127 [−0.232, −0.035] | −0.111 [−0.188, −0.036] | −0.107 [−0.143, −0.069] | −0.089 [−0.128, −0.051] |
| AMS3D | 0.181 [0.136, 0.248] | 0.078 [0.045, 0.118] | −0.225 [−0.318, −0.135] | −0.205 [−0.253, −0.153] | −0.182 [−0.281, −0.086] | −0.253 [−0.310, −0.185] | −0.128 [−0.173, −0.081] | −0.134 [−0.166, −0.104] |

- The null takes 0.48 to 0.65 of each arm's censused F1 in California and 0.75
  to 0.85 in Washington (nominal box on the same plots: 0.44 to 0.61 and 0.74
  to 0.84). It takes more in Washington's denser stands in both scorings.
- In the nominal box the two segmenters lead CHM-VWF above chance only in
  California. Inside the censused subplots at 4 m SegmentAnyTree's corrected
  lead is about the same in both regions (+0.067 and +0.058) and excludes zero
  in Washington, where its corrected lead in the nominal box on the same 45
  plots is +0.019 [−0.013, +0.053]. ForestFormer3D's is +0.034 and +0.030,
  excluding zero in neither.
- At 2 m the regional contrast returns: the corrected censused leads are
  +0.076 [+0.010, +0.143] (SegmentAnyTree) and +0.064 [+0.024, +0.106]
  (ForestFormer3D) in California, and +0.026 [−0.005, +0.056] and +0.002
  [−0.034, +0.039] in Washington.
- The California estimates rest on 12 plots, 9 of them at TEAK, and their
  intervals are wide.

## Density series

The eight ladder arms on the decimated rungs (8, 4, 2 and 1 points/m²) and on
the QL2 rung (3.2 points/m², 2.0 pulses/m², frozen in its own root and run
from its own job directory). Each rung pools the same 57 plots; each rung's
resamples are drawn on its own plots, as in the master tables. Corrected
censused lead over CHM-VWF, 4 m (last row: CHM-VWF's corrected censused F1):

| Arm | native | 8 | 4 | 3.2 | 2 | 1 |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | +0.063 [+0.016, +0.108] | +0.122 [+0.076, +0.170] | +0.085 [+0.041, +0.125] | +0.053 [+0.009, +0.091] | −0.043 [−0.093, +0.005] | −0.169 [−0.212, −0.128] |
| ForestFormer3D | +0.030 [−0.016, +0.074] | +0.109 [+0.054, +0.165] | +0.045 [−0.010, +0.097] | +0.069 [+0.026, +0.113] | +0.060 [+0.012, +0.107] | +0.026 [−0.015, +0.067] |
| TreeisoNet | +0.000 [−0.033, +0.030] | +0.079 [+0.043, +0.113] | +0.092 [+0.049, +0.132] | +0.093 [+0.050, +0.136] | +0.092 [+0.053, +0.132] | +0.060 [+0.018, +0.098] |
| `multichm` | −0.043 [−0.082, −0.008] | +0.043 [−0.001, +0.090] | +0.016 [−0.031, +0.062] | +0.049 [+0.006, +0.096] | +0.010 [−0.038, +0.058] | −0.003 [−0.048, +0.038] |
| `lmfauto` | −0.073 [−0.127, −0.012] | −0.052 [−0.111, +0.017] | −0.091 [−0.146, −0.031] | −0.091 [−0.142, −0.038] | −0.079 [−0.131, −0.014] | −0.099 [−0.139, −0.059] |
| `ptrees` | −0.128 [−0.201, −0.058] | +0.043 [+0.004, +0.084] | +0.024 [−0.023, +0.073] | +0.015 [−0.023, +0.055] | −0.018 [−0.052, +0.016] | −0.088 [−0.125, −0.054] |
| AMS3D | −0.212 [−0.257, −0.166] | −0.076 [−0.125, −0.026] | +0.001 [−0.053, +0.055] | +0.040 [−0.018, +0.091] | +0.117 [+0.056, +0.174] | +0.050 [+0.008, +0.089] |
| CHM-VWF corrected F1 | 0.303 [0.260, 0.346] | 0.223 [0.180, 0.271] | 0.227 [0.184, 0.271] | 0.217 [0.171, 0.262] | 0.203 [0.162, 0.247] | 0.217 [0.179, 0.256] |

The learned arms' corrected leads, 4 m, in the three scorings: censused,
nominal box on the same 57 plots, and the paper's nominal box on all 106
plots.

| Arm, scoring | native | 8 | 4 | 3.2 | 2 | 1 |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree, censused | +0.063 [+0.016, +0.108] | +0.122 [+0.076, +0.170] | +0.085 [+0.041, +0.125] | +0.053 [+0.009, +0.091] | −0.043 [−0.093, +0.005] | −0.169 [−0.212, −0.128] |
| SegmentAnyTree, box, 57 plots | +0.029 [+0.000, +0.059] | +0.071 [+0.043, +0.098] | +0.041 [+0.006, +0.075] | +0.020 [−0.008, +0.045] | −0.006 [−0.039, +0.027] | −0.112 [−0.140, −0.084] |
| SegmentAnyTree, box, 106 plots | +0.034 [+0.008, +0.057] | +0.053 [+0.026, +0.080] | +0.033 [+0.005, +0.060] | +0.017 [−0.008, +0.041] | −0.011 [−0.039, +0.018] | −0.117 [−0.139, −0.097] |
| ForestFormer3D, censused | +0.030 [−0.016, +0.074] | +0.109 [+0.054, +0.165] | +0.045 [−0.010, +0.097] | +0.069 [+0.026, +0.113] | +0.060 [+0.012, +0.107] | +0.026 [−0.015, +0.067] |
| ForestFormer3D, box, 57 plots | +0.000 [−0.030, +0.030] | +0.059 [+0.028, +0.092] | +0.023 [−0.009, +0.056] | +0.035 [+0.006, +0.066] | +0.031 [−0.000, +0.063] | +0.018 [−0.008, +0.044] |
| ForestFormer3D, box, 106 plots | +0.020 [−0.002, +0.041] | +0.041 [+0.014, +0.069] | +0.011 [−0.014, +0.037] | +0.014 [−0.012, +0.040] | +0.016 [−0.010, +0.041] | +0.000 [−0.024, +0.022] |
| TreeisoNet, censused | +0.000 [−0.033, +0.030] | +0.079 [+0.043, +0.113] | +0.092 [+0.049, +0.132] | +0.093 [+0.050, +0.136] | +0.092 [+0.053, +0.132] | +0.060 [+0.018, +0.098] |
| TreeisoNet, box, 57 plots | −0.005 [−0.028, +0.014] | +0.044 [+0.020, +0.070] | +0.045 [+0.020, +0.071] | +0.046 [+0.021, +0.070] | +0.050 [+0.026, +0.074] | +0.042 [+0.013, +0.073] |
| TreeisoNet, box, 106 plots | −0.011 [−0.029, +0.005] | +0.018 [−0.004, +0.041] | +0.016 [−0.003, +0.039] | +0.016 [−0.006, +0.039] | +0.020 [−0.001, +0.043] | +0.021 [−0.005, +0.046] |

Corrected censused lead, 2 m:

| Arm | native | 8 | 4 | 3.2 | 2 | 1 |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | +0.034 [+0.006, +0.063] | +0.079 [+0.043, +0.117] | +0.038 [−0.007, +0.084] | −0.011 [−0.046, +0.022] | −0.050 [−0.086, −0.010] | −0.152 [−0.190, −0.117] |
| ForestFormer3D | +0.011 [−0.021, +0.044] | +0.065 [+0.024, +0.107] | +0.008 [−0.032, +0.047] | +0.031 [−0.001, +0.066] | +0.016 [−0.022, +0.056] | +0.020 [−0.013, +0.057] |
| TreeisoNet | −0.009 [−0.034, +0.015] | +0.079 [+0.045, +0.110] | +0.074 [+0.043, +0.105] | +0.080 [+0.047, +0.117] | +0.078 [+0.041, +0.114] | +0.063 [+0.019, +0.105] |
| `multichm` | −0.050 [−0.080, −0.018] | +0.008 [−0.027, +0.046] | −0.006 [−0.046, +0.036] | −0.001 [−0.037, +0.036] | −0.003 [−0.042, +0.038] | +0.003 [−0.030, +0.038] |
| `lmfauto` | −0.061 [−0.102, −0.018] | −0.029 [−0.077, +0.029] | −0.077 [−0.125, −0.026] | −0.082 [−0.126, −0.036] | −0.070 [−0.120, −0.012] | −0.059 [−0.097, −0.022] |
| `ptrees` | −0.100 [−0.144, −0.050] | +0.056 [+0.020, +0.092] | +0.014 [−0.021, +0.049] | +0.012 [−0.018, +0.040] | −0.014 [−0.051, +0.020] | −0.074 [−0.105, −0.043] |
| AMS3D | −0.179 [−0.221, −0.137] | −0.050 [−0.097, −0.004] | +0.012 [−0.030, +0.055] | +0.030 [−0.016, +0.073] | +0.062 [+0.018, +0.110] | +0.045 [+0.008, +0.085] |
| CHM-VWF corrected F1 | 0.312 [0.266, 0.359] | 0.234 [0.187, 0.286] | 0.239 [0.192, 0.287] | 0.234 [0.190, 0.281] | 0.219 [0.175, 0.266] | 0.201 [0.164, 0.239] |

- The null's share of censused F1 stays at 0.69 to 0.83 on every rung at 4 m and
  0.45 to 0.66 at 2 m (nominal box on the same plots: 0.70 to 0.81 and 0.46 to
  0.67).
- CHM-VWF's observed censused F1 falls from 0.608 at native density to 0.475 to
  0.504 below it, as its coarser, smoothed canopy model loses recall, and its
  corrected censused F1 from 0.303 to 0.203–0.227. The other arms lose less, so
  most corrected leads grow below native density.
- Inside the censused subplots more positive leads exclude zero than in the
  nominal box. At 4 m: TreeisoNet's at every thinned rung, SegmentAnyTree's at
  rungs 8, 4 and 3.2, ForestFormer3D's at 8, 3.2 and 2, `multichm`'s at 3.2,
  `ptrees`'s at 8 and AMS3D's at 2 and 1. On all 106 plots in the nominal box
  only SegmentAnyTree's at 8 and 4 and ForestFormer3D's at 8 do.
- At the QL2 rung the corrected censused leads of SegmentAnyTree,
  ForestFormer3D, TreeisoNet and `multichm` are +0.053, +0.069, +0.093 and
  +0.049, all excluding zero at 4 m on the 57 plots (SegmentAnyTree's and
  `multichm`'s do not without the nine plots that hold a reference outside the
  nominal box); at 2 m only TreeisoNet's does (+0.080 [+0.047, +0.117]), with
  ForestFormer3D at +0.031 [−0.001, +0.066] and SegmentAnyTree at −0.011.
- SegmentAnyTree's collapse is not chance either: its corrected censused F1
  falls from 0.366 at native density to 0.270 at QL2, 0.159 at rung 2 and 0.048
  at rung 1, and its corrected lead is −0.169 [−0.212, −0.128] at rung 1.

## Leads over the unsmoothed baseline

The declared CHM-VWF smooths its canopy model below 8 first returns/m²; the
[baseline smoothing study](baseline-smoothing-sensitivity-results.md) re-ran it
on the same sealed clips without the smoothing, in its own job directories, and
found that on the nominal cores no detector leads the unsmoothed baseline above
chance below native density. The same comparison inside the censused subplots
was added here after those results were known, so it is post hoc like the rest
of this study.

The unsmoothed baseline's persisted detections were scored by
`score_census_support.R` (headline declaration, `ARMS=chm_vwf`) and given the
censused null by `paper_census_null.R` in its job directories, with checks A and
C passing: 285 cells on the native and thinned rungs and 57 at the QL2 rung
equal its committed censused scores and its own nominal-box null cells (check B
is skipped with `CHECK_MASTER=0`, as the master tables hold no rows for this
arm). `paper_census_null_unsmoothed.R` then pools it with the eight ladder
detectors and Li 2012 on the same 57 plots and resamples, with the unsmoothed
baseline as the comparator. It stops unless every run's checks passed; the runs
used the same declaration, radius, 200 shifts, seed offset and minimum shift;
the 46 cells whose detections are byte-identical in the two baselines have
identical null counts; every arm shares the cells' reference counts and support
identity; and every arm's pooled rows equal those of its own run (within 10⁻¹²).
At native density the two baselines differ in 11 of the 57 censused plots,
exactly the admitted plots below 8 pulses/m² (18 of the 106 plots are below it);
9 of the 11 differ inside the censused interior. On the thinned levels 56 or 57
of the 57 plots differ.

The two baselines, five sites, 4 m (F1, null F1, null share; the last three
columns are the nominal box on the same plots):

| Level | Smoothed: F1 / null F1 / null share | Smoothed: corrected F1 | Unsmoothed: F1 / null F1 / null share | Unsmoothed: corrected F1 | Smoothed minus unsmoothed | Box: smoothed corrected F1 | Box: unsmoothed corrected F1 | Box: smoothed minus unsmoothed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| native | 0.608 / 0.438 / 0.720 | 0.303 [0.260, 0.346] | 0.619 / 0.449 / 0.725 | 0.309 [0.265, 0.354] | −0.006 [−0.016, +0.003] | 0.213 | 0.215 | −0.003 [−0.012, +0.007] |
| 8 | 0.502 / 0.359 / 0.716 | 0.223 [0.180, 0.271] | 0.623 / 0.453 / 0.727 | 0.312 [0.265, 0.361] | −0.089 [−0.131, −0.052] | 0.161 | 0.224 | −0.063 [−0.085, −0.042] |
| 4 | 0.504 / 0.358 / 0.711 | 0.227 [0.184, 0.271] | 0.606 / 0.441 / 0.728 | 0.295 [0.250, 0.341] | −0.067 [−0.107, −0.028] | 0.167 | 0.212 | −0.045 [−0.069, −0.021] |
| 3.2 (QL2) | 0.495 / 0.355 / 0.717 | 0.217 [0.171, 0.262] | 0.612 / 0.443 / 0.723 | 0.304 [0.260, 0.353] | −0.087 [−0.128, −0.049] | 0.160 | 0.202 | −0.043 [−0.068, −0.020] |
| 2 | 0.481 / 0.349 / 0.726 | 0.203 [0.162, 0.247] | 0.613 / 0.437 / 0.713 | 0.313 [0.268, 0.356] | −0.110 [−0.148, −0.072] | 0.151 | 0.209 | −0.058 [−0.079, −0.038] |
| 1 | 0.475 / 0.329 / 0.694 | 0.217 [0.179, 0.256] | 0.569 / 0.411 / 0.723 | 0.268 [0.223, 0.312] | −0.051 [−0.088, −0.015] | 0.156 | 0.191 | −0.036 [−0.056, −0.014] |

Corrected censused lead over the unsmoothed baseline, five sites, 4 m:

| Arm | native | 8 | 4 | 3.2 (QL2) | 2 | 1 |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | +0.057 [+0.009, +0.104] | +0.033 [−0.016, +0.085] | +0.018 [−0.027, +0.057] | −0.034 [−0.083, +0.012] | −0.153 [−0.195, −0.112] | −0.220 [−0.273, −0.171] |
| ForestFormer3D | +0.024 [−0.026, +0.071] | +0.021 [−0.036, +0.074] | −0.022 [−0.073, +0.028] | −0.018 [−0.068, +0.028] | −0.050 [−0.100, −0.002] | −0.024 [−0.068, +0.021] |
| Li 2012 | +0.019 [−0.013, +0.052] | — | — | — | — | — |
| TreeisoNet | −0.006 [−0.042, +0.026] | −0.010 [−0.042, +0.020] | +0.024 [−0.015, +0.055] | +0.006 [−0.027, +0.035] | −0.018 [−0.047, +0.012] | +0.009 [−0.029, +0.046] |
| CHM-VWF, smoothed | −0.006 [−0.016, +0.003] | −0.089 [−0.131, −0.052] | −0.067 [−0.107, −0.028] | −0.087 [−0.128, −0.049] | −0.110 [−0.148, −0.072] | −0.051 [−0.088, −0.015] |
| `multichm` | −0.049 [−0.089, −0.012] | −0.046 [−0.089, +0.001] | −0.052 [−0.093, −0.010] | −0.039 [−0.088, +0.008] | −0.100 [−0.144, −0.057] | −0.054 [−0.098, −0.013] |
| `lmfauto` | −0.080 [−0.135, −0.017] | −0.141 [−0.200, −0.078] | −0.159 [−0.208, −0.107] | −0.179 [−0.231, −0.128] | −0.189 [−0.247, −0.128] | −0.150 [−0.206, −0.095] |
| `ptrees` | −0.134 [−0.207, −0.063] | −0.045 [−0.086, −0.011] | −0.043 [−0.083, −0.006] | −0.072 [−0.103, −0.043] | −0.128 [−0.172, −0.088] | −0.139 [−0.179, −0.099] |
| AMS3D | −0.219 [−0.264, −0.171] | −0.165 [−0.214, −0.115] | −0.066 [−0.116, −0.022] | −0.048 [−0.101, −0.000] | +0.007 [−0.043, +0.056] | −0.001 [−0.052, +0.050] |

Observed censused F1 lead over the unsmoothed baseline, five sites, 4 m:

| Arm | native | 8 | 4 | 3.2 (QL2) | 2 | 1 |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | +0.058 [+0.024, +0.090] | +0.032 [−0.004, +0.068] | +0.021 [−0.006, +0.045] | −0.018 [−0.051, +0.016] | −0.160 [−0.186, −0.136] | −0.423 [−0.466, −0.378] |
| ForestFormer3D | +0.049 [+0.009, +0.092] | +0.034 [−0.007, +0.077] | +0.008 [−0.026, +0.045] | +0.002 [−0.035, +0.039] | −0.025 [−0.060, +0.011] | −0.003 [−0.031, +0.027] |
| Li 2012 | +0.019 [−0.001, +0.040] | — | — | — | — | — |
| TreeisoNet | +0.003 [−0.018, +0.022] | −0.000 [−0.018, +0.017] | +0.029 [+0.007, +0.047] | +0.017 [−0.002, +0.033] | +0.003 [−0.017, +0.023] | +0.023 [−0.008, +0.051] |
| CHM-VWF, smoothed | −0.011 [−0.020, −0.003] | −0.122 [−0.166, −0.082] | −0.101 [−0.140, −0.065] | −0.118 [−0.157, −0.082] | −0.132 [−0.165, −0.101] | −0.094 [−0.118, −0.067] |
| `multichm` | −0.022 [−0.057, +0.015] | −0.020 [−0.062, +0.021] | −0.016 [−0.053, +0.024] | −0.010 [−0.051, +0.031] | −0.045 [−0.084, −0.004] | −0.003 [−0.039, +0.035] |
| `lmfauto` | −0.080 [−0.128, −0.024] | −0.148 [−0.203, −0.085] | −0.199 [−0.256, −0.134] | −0.222 [−0.280, −0.156] | −0.228 [−0.295, −0.151] | −0.177 [−0.242, −0.107] |
| `ptrees` | −0.123 [−0.191, −0.057] | −0.026 [−0.053, −0.003] | −0.051 [−0.077, −0.026] | −0.086 [−0.111, −0.060] | −0.167 [−0.202, −0.132] | −0.227 [−0.263, −0.194] |
| AMS3D | −0.256 [−0.308, −0.198] | −0.160 [−0.207, −0.112] | −0.045 [−0.086, −0.007] | −0.023 [−0.066, +0.014] | +0.022 [−0.013, +0.053] | −0.007 [−0.056, +0.041] |

Corrected censused lead over the unsmoothed baseline by region, 4 m:

| Arm, region | native | 8 | 4 | 3.2 (QL2) | 2 | 1 |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree, California | +0.065 [−0.044, +0.166] | +0.061 [−0.045, +0.150] | +0.022 [−0.108, +0.117] | −0.028 [−0.165, +0.106] | −0.123 [−0.199, −0.054] | −0.257 [−0.363, −0.178] |
| SegmentAnyTree, Washington | +0.051 [−0.004, +0.100] | +0.023 [−0.036, +0.078] | +0.015 [−0.032, +0.057] | −0.037 [−0.092, +0.010] | −0.157 [−0.206, −0.110] | −0.211 [−0.271, −0.155] |
| ForestFormer3D, California | +0.032 [−0.058, +0.125] | +0.077 [−0.046, +0.202] | −0.009 [−0.139, +0.101] | +0.016 [−0.111, +0.142] | −0.025 [−0.098, +0.043] | +0.026 [−0.051, +0.101] |
| ForestFormer3D, Washington | +0.023 [−0.031, +0.074] | +0.009 [−0.057, +0.069] | −0.025 [−0.079, +0.027] | −0.025 [−0.082, +0.026] | −0.055 [−0.109, −0.003] | −0.037 [−0.087, +0.014] |
| TreeisoNet, California | −0.037 [−0.111, +0.040] | −0.004 [−0.079, +0.076] | +0.047 [−0.024, +0.116] | +0.010 [−0.066, +0.089] | +0.019 [−0.032, +0.074] | +0.020 [−0.019, +0.054] |
| TreeisoNet, Washington | −0.002 [−0.041, +0.036] | −0.014 [−0.049, +0.022] | +0.016 [−0.027, +0.050] | +0.003 [−0.033, +0.034] | −0.027 [−0.058, +0.007] | +0.004 [−0.039, +0.047] |
| `multichm`, California | +0.036 [−0.056, +0.110] | +0.052 [−0.029, +0.131] | −0.009 [−0.128, +0.075] | +0.025 [−0.073, +0.105] | −0.026 [−0.144, +0.063] | +0.018 [−0.083, +0.114] |
| `multichm`, Washington | −0.062 [−0.106, −0.020] | −0.063 [−0.113, −0.011] | −0.059 [−0.102, −0.012] | −0.050 [−0.104, +0.002] | −0.112 [−0.160, −0.063] | −0.067 [−0.117, −0.021] |

- Without its smoothing the baseline's censused corrected F1 stays at 0.268 to
  0.313 below native density (0.309 at native density), where the declared
  baseline's falls to 0.203 to 0.227. The declared baseline trails the
  unsmoothed one by 0.051 to 0.110 in censused corrected F1 on every thinned
  level, each interval excluding zero (0.036 to 0.063 in the nominal box on the
  same plots).
- Over the unsmoothed baseline no detector has a positive corrected censused
  lead that excludes zero at any thinned level at 4 m. The largest are
  SegmentAnyTree's +0.033 [−0.016, +0.085] at rung 8, TreeisoNet's +0.024
  [−0.015, +0.055] at rung 4 and ForestFormer3D's +0.021 [−0.036, +0.074] at
  rung 8. Over the declared baseline 15 positive leads excluded zero on the
  thinned levels: TreeisoNet's at all five, SegmentAnyTree's at 8, 4 and 3.2,
  ForestFormer3D's at 8, 3.2 and 2, `multichm`'s at 3.2, `ptrees`'s at 8 and
  AMS3D's at 2 and 1. The positive censused leads of up to +0.12 below native
  density are therefore explained by the declared baseline's smoothing rule, not
  by an advantage over an unsmoothed canopy-model baseline.
- Several corrected leads over the unsmoothed baseline are negative and exclude
  zero: SegmentAnyTree's at rungs 2 and 1 (−0.153 and −0.220), ForestFormer3D's
  at rung 2 (−0.050 [−0.100, −0.002]), `multichm`'s at native density and rungs
  4, 2 and 1, and those of `lmfauto`, `ptrees` and AMS3D on most levels.
- Among the observed censused leads below native density only TreeisoNet's at
  rung 4 excludes zero (+0.029 [+0.007, +0.047]); corrected it is +0.024
  [−0.015, +0.055].
- In the nominal box on the same plots no positive corrected lead over the
  unsmoothed baseline excludes zero on any level, native density included
  (SegmentAnyTree +0.027 [−0.005, +0.059] at native density).
- Inside the censused subplots no positive corrected lead over the unsmoothed
  baseline excludes zero in either region alone at 4 m (in the nominal box of
  the twelve California plots ForestFormer3D's does at rungs 8 and 2). The
  regions differ in sign for `multichm` (positive in California at four levels,
  negative in Washington at all six and excluding zero at five) and for
  ForestFormer3D at rungs 3.2 and 1 (+0.016 and +0.026 in California, −0.025 and
  −0.037 in Washington).
- At native density the unsmoothed baseline's censused corrected F1 is 0.006
  above the declared one's (−0.006 [−0.016, +0.003] for declared minus
  unsmoothed), so every native lead is 0.006 smaller over it: SegmentAnyTree
  +0.057 [+0.009, +0.104] (+0.063 over the declared baseline), ForestFormer3D
  +0.024 (+0.030), Li 2012 +0.019 (+0.025), TreeisoNet −0.006 (+0.000) and
  `multichm` −0.049 (−0.043). SegmentAnyTree's native lead still excludes zero
  on the five sites, but in neither region alone (California +0.065 [−0.044,
  +0.166], Washington +0.051 [−0.004, +0.100]).

At 2 m the unsmoothed baseline's censused corrected F1 is 0.312 at native
density (the same as the declared baseline's) and 0.255 to 0.296 below it,
where the declared baseline's is 0.201 to 0.239. Corrected censused lead over
the unsmoothed baseline, five sites, 2 m:

| Arm | native | 8 | 4 | 3.2 (QL2) | 2 | 1 |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | +0.035 [+0.003, +0.067] | +0.029 [−0.004, +0.060] | −0.013 [−0.047, +0.022] | −0.073 [−0.110, −0.039] | −0.117 [−0.156, −0.082] | −0.206 [−0.255, −0.160] |
| ForestFormer3D | +0.012 [−0.021, +0.042] | +0.014 [−0.023, +0.051] | −0.043 [−0.081, −0.007] | −0.031 [−0.061, +0.002] | −0.051 [−0.090, −0.014] | −0.034 [−0.070, +0.004] |
| Li 2012 | +0.016 [−0.007, +0.038] | — | — | — | — | — |
| TreeisoNet | −0.009 [−0.036, +0.018] | +0.029 [+0.005, +0.049] | +0.023 [−0.004, +0.049] | +0.018 [−0.011, +0.045] | +0.011 [−0.015, +0.034] | +0.009 [−0.024, +0.043] |
| CHM-VWF, smoothed | +0.000 [−0.012, +0.014] | −0.050 [−0.078, −0.025] | −0.051 [−0.083, −0.021] | −0.062 [−0.093, −0.033] | −0.067 [−0.096, −0.035] | −0.054 [−0.082, −0.025] |
| `multichm` | −0.050 [−0.078, −0.018] | −0.042 [−0.072, −0.012] | −0.057 [−0.095, −0.020] | −0.063 [−0.099, −0.027] | −0.070 [−0.116, −0.030] | −0.051 [−0.085, −0.018] |
| `lmfauto` | −0.061 [−0.098, −0.020] | −0.079 [−0.119, −0.035] | −0.128 [−0.177, −0.080] | −0.143 [−0.190, −0.096] | −0.136 [−0.193, −0.082] | −0.113 [−0.153, −0.074] |
| `ptrees` | −0.099 [−0.146, −0.047] | +0.005 [−0.022, +0.031] | −0.037 [−0.066, −0.007] | −0.050 [−0.084, −0.021] | −0.081 [−0.121, −0.045] | −0.128 [−0.159, −0.097] |
| AMS3D | −0.179 [−0.223, −0.130] | −0.100 [−0.141, −0.061] | −0.039 [−0.076, −0.006] | −0.032 [−0.076, +0.009] | −0.004 [−0.041, +0.031] | −0.008 [−0.047, +0.028] |

At 2 m one positive corrected lead below native density excludes zero:
TreeisoNet's at rung 8 (+0.029 [+0.005, +0.049]); its observed censused leads
exclude zero at rungs 8 to 2 (+0.026 to +0.036). SegmentAnyTree keeps +0.035
[+0.003, +0.067] at native density. The pooled rows, leads and generated
tables are `sensitivity/census_null/census_null_unsmoothed[_tol2]_*`.

## Plot types

`paper_null_subsets.R` pools the paper's nominal-box null cells (106 plots; no
shifts repeated) on subsets of plots, with the master tables' resamples drawn on
each subset's plots. On all 106 plots it reproduces the paper's
`null_pooled.csv`, `null_delta.csv` and `null_leads.csv` rows of every scope at
native density, at 4 m and at 2 m (576, 288 and 792 rows at each radius, equal
within 10⁻⁹; the cells are read back from CSV). Five sites, native density, 4 m,
52 tower plots (1,649 stems) and 54 distributed plots (876 stems; SJER has no
distributed plot in the population, so that pool holds four sites):

| Arm | Tower: null share | Tower: corrected F1 | Tower: corrected lead | Distributed: null share | Distributed: corrected F1 | Distributed: corrected lead | All 106: corrected lead |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.697 | 0.215 [0.186, 0.241] | +0.042 [+0.015, +0.068] | 0.698 | 0.279 [0.217, 0.345] | +0.022 [−0.028, +0.074] | +0.034 [+0.008, +0.057] |
| ForestFormer3D | 0.727 | 0.194 [0.168, 0.220] | +0.021 [−0.003, +0.046] | 0.721 | 0.284 [0.236, 0.336] | +0.027 [−0.021, +0.072] | +0.020 [−0.002, +0.041] |
| Li 2012 | 0.720 | 0.178 [0.152, 0.203] | +0.005 [−0.011, +0.021] | 0.699 | 0.249 [0.204, 0.297] | −0.008 [−0.051, +0.030] | +0.000 [−0.015, +0.014] |
| TreeisoNet | 0.734 | 0.168 [0.143, 0.193] | −0.005 [−0.023, +0.012] | 0.695 | 0.230 [0.190, 0.274] | −0.027 [−0.069, +0.011] | −0.011 [−0.029, +0.005] |
| CHM-VWF | 0.727 | 0.173 [0.145, 0.203] | — | 0.658 | 0.257 [0.206, 0.320] | — | — |
| DeepForest | 0.726 | 0.170 [0.144, 0.197] | −0.003 [−0.023, +0.017] | 0.717 | 0.251 [0.199, 0.305] | −0.006 [−0.056, +0.039] | −0.007 [−0.028, +0.012] |
| `multichm` | 0.753 | 0.151 [0.126, 0.174] | −0.022 [−0.043, −0.002] | 0.728 | 0.258 [0.212, 0.311] | +0.001 [−0.053, +0.054] | −0.017 [−0.039, +0.005] |
| Detectree2 | 0.727 | 0.131 [0.107, 0.159] | −0.042 [−0.081, −0.003] | 0.671 | 0.168 [0.121, 0.228] | −0.089 [−0.138, −0.040] | −0.054 [−0.088, −0.021] |
| `lmfauto` | 0.750 | 0.122 [0.098, 0.152] | −0.051 [−0.073, −0.025] | 0.742 | 0.200 [0.157, 0.252] | −0.057 [−0.109, −0.008] | −0.056 [−0.079, −0.034] |
| `ptrees` | 0.783 | 0.085 [0.065, 0.107] | −0.088 [−0.115, −0.060] | 0.763 | 0.153 [0.104, 0.211] | −0.104 [−0.173, −0.037] | −0.095 [−0.123, −0.067] |
| AMS3D | 0.791 | 0.055 [0.043, 0.069] | −0.118 [−0.143, −0.092] | 0.788 | 0.095 [0.071, 0.123] | −0.162 [−0.231, −0.101] | −0.132 [−0.159, −0.107] |
| SAM2Point | 0.376 | 0.054 [0.038, 0.071] | −0.119 [−0.150, −0.090] | 0.490 | 0.124 [0.090, 0.167] | −0.133 [−0.185, −0.083] | −0.116 [−0.143, −0.089] |

- The null's share of F1 is slightly larger on tower plots, where half of each
  box is unsampled, than on distributed plots, which are censused whole when
  censused: for 10 of the 12 arms, by 0.003 to 0.039 for eight of them
  (ForestFormer3D 0.727 and 0.721, TreeisoNet 0.734 and 0.695), by 0.056 for
  Detectree2 and by 0.069 for CHM-VWF (0.727 and 0.658). SegmentAnyTree's is the
  same (0.697 and 0.698) and SAM2Point's smaller. Unsampled area lowers observed
  and null precision together, which keeps the shares close.
- SegmentAnyTree's corrected lead is +0.042 [+0.015, +0.068] on tower plots and
  +0.022 [−0.028, +0.074] on distributed plots; ForestFormer3D's is +0.021
  [−0.003, +0.046] and +0.027 [−0.021, +0.072]. With 876 of the 2,525 stems, the
  distributed plots give intervals about twice as wide. The half-mapped tower
  plots thus do not show the smaller lead that an unsampled half would produce
  on its own: SegmentAnyTree's lead is larger there and ForestFormer3D's
  slightly smaller. The two plot types differ in more than sampling (size,
  position and stand).
- At 2 m the corrected leads are +0.021 [−0.000, +0.041] (SegmentAnyTree) and
  −0.002 [−0.022, +0.019] (ForestFormer3D) on tower plots and +0.009 [−0.023,
  +0.040] and +0.020 [−0.015, +0.058] on distributed plots.

## Fire-plot exclusion

SOAP_002, SOAP_008 and SOAP_013 lie inside the perimeter of the 2020 Creek
Fire, and their 22 reference stems were all measured in 2019, before the fire
and two years before the 2021 flights. None of them is among the 57 censused
plots (SOAP's only admitted plot is SOAP_046), so the censused results above do
not depend on them. Without them, the nominal-box null gives these corrected
leads over CHM-VWF (native density, 4 m):

| Arm | Five sites, 106 plots | Five sites, 103 plots | California, 43 plots | California, 40 plots | SOAP, 18 plots | SOAP, 15 plots |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | +0.034 [+0.008, +0.057] | +0.033 [+0.008, +0.057] | +0.061 [+0.015, +0.103] | +0.060 [+0.010, +0.100] | +0.072 [+0.004, +0.131] | +0.065 [−0.013, +0.123] |
| ForestFormer3D | +0.020 [−0.002, +0.041] | +0.021 [−0.000, +0.043] | +0.060 [+0.026, +0.094] | +0.064 [+0.031, +0.098] | +0.061 [+0.006, +0.106] | +0.072 [+0.020, +0.118] |
| Li 2012 | +0.000 [−0.015, +0.014] | +0.001 [−0.015, +0.016] | −0.034 [−0.061, −0.010] | −0.033 [−0.062, −0.009] | −0.049 [−0.107, −0.012] | −0.046 [−0.107, −0.006] |
| TreeisoNet | −0.011 [−0.029, +0.005] | −0.011 [−0.029, +0.004] | −0.017 [−0.044, +0.008] | −0.016 [−0.047, +0.011] | −0.010 [−0.059, +0.035] | −0.006 [−0.056, +0.044] |
| DeepForest | −0.007 [−0.028, +0.012] | −0.006 [−0.027, +0.013] | +0.045 [+0.003, +0.081] | +0.049 [+0.005, +0.085] | +0.073 [+0.001, +0.133] | +0.085 [+0.004, +0.144] |
| `multichm` | −0.017 [−0.039, +0.005] | −0.018 [−0.039, +0.005] | +0.021 [−0.022, +0.062] | +0.019 [−0.024, +0.059] | +0.027 [−0.050, +0.086] | +0.024 [−0.064, +0.087] |
| Detectree2 | −0.054 [−0.088, −0.021] | −0.052 [−0.086, −0.021] | −0.013 [−0.075, +0.041] | −0.007 [−0.068, +0.050] | +0.040 [−0.053, +0.127] | +0.059 [−0.028, +0.142] |
| `lmfauto` | −0.056 [−0.079, −0.034] | −0.055 [−0.079, −0.032] | −0.036 [−0.061, −0.011] | −0.034 [−0.060, −0.010] | −0.062 [−0.115, −0.017] | −0.058 [−0.118, −0.013] |
| `ptrees` | −0.095 [−0.123, −0.067] | −0.094 [−0.122, −0.066] | −0.107 [−0.143, −0.069] | −0.102 [−0.144, −0.064] | −0.107 [−0.183, −0.060] | −0.093 [−0.155, −0.042] |
| AMS3D | −0.132 [−0.159, −0.107] | −0.131 [−0.156, −0.104] | −0.128 [−0.173, −0.081] | −0.123 [−0.169, −0.079] | −0.136 [−0.206, −0.080] | −0.120 [−0.184, −0.063] |
| SAM2Point | −0.116 [−0.143, −0.089] | −0.117 [−0.145, −0.090] | −0.082 [−0.134, −0.033] | −0.083 [−0.137, −0.033] | −0.014 [−0.095, +0.058] | −0.010 [−0.100, +0.063] |

- On the five sites the largest move of a corrected lead is 0.0017 at 4 m and
  0.0021 at 2 m (SegmentAnyTree +0.017 to +0.015 at 2 m). In California the
  two segmenters' leads move by 0.001 and 0.004 at 4 m and by 0.002 and 0.001
  at 2 m.
- At SOAP alone SegmentAnyTree's corrected lead falls from +0.072 to +0.065
  and its lower limit to −0.013, while ForestFormer3D's rises from +0.061 to
  +0.072. CHM-VWF's corrected F1 at SOAP falls from 0.208 to 0.186.

## Sensitivities

**References outside the nominal box.** 20 of the 1,190 censused references,
in 9 plots, lie outside the nominal box, by up to 2.34 m: one in TEAK_013, 14 in
WREF_004, WREF_007, WREF_012, WREF_073 and WREF_075, and 5 in ABBY_061,
ABBY_063 and ABBY_077. Part of their match disc lies beyond the shift window,
where observed detections can lie but shifted ones never do, which can only
lower their null. Every pooled row is repeated without these 9 plots (48
plots; `plot_set` `inside_box` in the output):

| Arm | Censused corrected F1, 57 plots | Censused corrected F1, 48 plots | Censused corrected lead, 57 plots | Censused corrected lead, 48 plots | 2 m: censused corrected lead, 57 plots | 2 m: censused corrected lead, 48 plots |
| --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.366 [0.324, 0.409] | 0.368 [0.324, 0.411] | +0.063 [+0.016, +0.108] | +0.052 [+0.002, +0.098] | +0.034 [+0.006, +0.063] | +0.035 [−0.001, +0.069] |
| ForestFormer3D | 0.333 [0.285, 0.385] | 0.354 [0.300, 0.408] | +0.030 [−0.016, +0.074] | +0.038 [−0.015, +0.089] | +0.011 [−0.021, +0.044] | +0.019 [−0.019, +0.054] |
| Li 2012 | 0.328 [0.287, 0.371] | 0.335 [0.290, 0.387] | +0.025 [−0.004, +0.057] | +0.019 [−0.013, +0.052] | +0.015 [−0.008, +0.038] | +0.019 [−0.005, +0.046] |
| TreeisoNet | 0.303 [0.261, 0.346] | 0.313 [0.274, 0.354] | +0.000 [−0.033, +0.030] | −0.003 [−0.042, +0.033] | −0.009 [−0.034, +0.015] | −0.001 [−0.032, +0.027] |
| CHM-VWF | 0.303 [0.260, 0.346] | 0.316 [0.270, 0.366] | — | — | — | — |
| `multichm` | 0.260 [0.220, 0.305] | 0.274 [0.226, 0.323] | −0.043 [−0.082, −0.008] | −0.043 [−0.087, +0.001] | −0.050 [−0.080, −0.018] | −0.058 [−0.092, −0.027] |
| `lmfauto` | 0.229 [0.180, 0.294] | 0.229 [0.169, 0.308] | −0.073 [−0.127, −0.012] | −0.087 [−0.150, −0.011] | −0.061 [−0.102, −0.018] | −0.068 [−0.117, −0.017] |
| `ptrees` | 0.175 [0.114, 0.245] | 0.163 [0.100, 0.245] | −0.128 [−0.201, −0.058] | −0.153 [−0.228, −0.064] | −0.100 [−0.144, −0.050] | −0.112 [−0.163, −0.056] |
| AMS3D | 0.090 [0.060, 0.126] | 0.081 [0.050, 0.116] | −0.212 [−0.257, −0.166] | −0.235 [−0.277, −0.188] | −0.179 [−0.221, −0.137] | −0.189 [−0.236, −0.147] |

SegmentAnyTree's native 4 m lead falls from +0.063 to +0.052 and its lower limit
to +0.002; ForestFormer3D's rises from +0.030 to +0.038. On every rung the 4 m
corrected leads change by at most 0.035 (`lmfauto` at rung 2). Below native
density four of the fifteen positive leads that exclude zero on the 57 plots no
longer do on the 48: SegmentAnyTree's at the QL2 rung (+0.053 [+0.009, +0.091]
becomes +0.033 [−0.016, +0.079]), ForestFormer3D's at rung 2 (+0.060 [+0.012,
+0.107] becomes +0.039 [−0.015, +0.090]), `multichm`'s at the QL2 rung (+0.049
[+0.006, +0.096] becomes +0.034 [−0.021, +0.084]) and `ptrees`'s at rung 8
(+0.043 [+0.004, +0.084] becomes +0.030 [−0.018, +0.074]). The other eleven
still exclude zero: SegmentAnyTree's at rungs 8 and 4 (+0.094 and +0.078),
ForestFormer3D's at rungs 8 and 3.2, TreeisoNet's at every thinned rung (+0.059
to +0.075) and AMS3D's at rungs 2 and 1. In Washington SegmentAnyTree's native
lead is +0.040 [−0.017, +0.088] on the 37 remaining plots (+0.058 [+0.005,
+0.105] on all 45). At 2 m, 15.9 m² of censused interior in three plots lies
beyond the smaller shift window (of 27,038 m² in all). Two of the three are
among the nine plots; the 48-plot set keeps the third (TEAK_043, 9.1 m²), whose
effect was not computed.

**Strict declaration.** The strict missing-reference policy also removes the
subplots of heightless census targets. It admits 54 plots (SJER_050,
TEAK_012, WREF_013 and WREF_080 leave, SJER_052 joins) with 1,070 censused
references. Native density, 4 m:

| Arm | Censused F1 | Null share | Censused corrected F1 | Censused corrected lead | Censused observed lead | Corrected lead, California | Corrected lead, Washington |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SegmentAnyTree | 0.672 | 0.721 | 0.364 [0.319, 0.405] | +0.052 [−0.002, +0.100] | +0.059 [+0.022, +0.094] | +0.062 [−0.065, +0.176] | +0.046 [−0.017, +0.097] |
| ForestFormer3D | 0.668 | 0.749 | 0.336 [0.289, 0.383] | +0.024 [−0.029, +0.073] | +0.055 [+0.011, +0.100] | +0.072 [−0.020, +0.153] | +0.018 [−0.041, +0.070] |
| Li 2012 | 0.638 | 0.718 | 0.332 [0.291, 0.376] | +0.020 [−0.012, +0.052] | +0.025 [+0.004, +0.045] | −0.038 [−0.079, +0.004] | +0.029 [−0.006, +0.064] |
| TreeisoNet | 0.624 | 0.733 | 0.307 [0.261, 0.355] | −0.005 [−0.042, +0.028] | +0.011 [−0.014, +0.032] | −0.035 [−0.119, +0.051] | −0.003 [−0.046, +0.032] |
| CHM-VWF | 0.613 | 0.715 | 0.312 [0.267, 0.360] | — | — | — | — |
| `multichm` | 0.595 | 0.760 | 0.261 [0.220, 0.311] | −0.050 [−0.096, −0.010] | −0.018 [−0.060, +0.027] | +0.041 [−0.069, +0.126] | −0.062 [−0.108, −0.020] |
| `lmfauto` | 0.532 | 0.742 | 0.227 [0.175, 0.295] | −0.085 [−0.141, −0.025] | −0.081 [−0.130, −0.027] | −0.028 [−0.069, +0.010] | −0.084 [−0.146, −0.019] |
| `ptrees` | 0.495 | 0.764 | 0.188 [0.122, 0.261] | −0.124 [−0.199, −0.042] | −0.118 [−0.189, −0.043] | −0.147 [−0.266, −0.027] | −0.119 [−0.203, −0.029] |
| AMS3D | 0.359 | 0.805 | 0.099 [0.068, 0.139] | −0.213 [−0.262, −0.165] | −0.254 [−0.309, −0.191] | −0.218 [−0.334, −0.119] | −0.208 [−0.260, −0.155] |

Under the strict declaration SegmentAnyTree's corrected censused lead is
+0.052 and its interval just includes zero; the other arms move by up to
0.012. Checks A and C pass for this run as well (486 cells).

**Monte Carlo error.** Across the 200 shifts the pooled censused null F1 of an
arm on the five sites has a standard deviation of 0.008 to 0.013 at native
density and 4 m, so the standard error of the 200-shift mean is 0.0006 to 0.0009
(0.0005 to 0.0010 on every rung; 0.0003 to 0.0007 for the nominal box at native
density). On the 12 California plots it is 0.0017 to 0.0030 on any rung, except
for SegmentAnyTree at rung 1, where some shifts leave no detection in the
interior and the error is not defined.

**Runs not made.** Other seeds and minimum shifts were not repeated inside the
censused subplots; in the nominal box they move the five-site corrected leads by
at most 0.002 ([chance
agreement](matcher-robustness-results.md#chance-agreement)).

## Limits

- **The interior is a small part of the shift window.** The window is the
  nominal box plus the match radius (2,304 m² for a tower plot at 4 m). The
  censused interior covers 25% of it on tower plots (13% to 33%) and 43% on
  distributed plots (38% to 49%); the nominal box covers 69% and 51%. Of the
  null detections that land in the interior, 76% to 78% crossed the window edge
  under the wrap (CHM-VWF 0.783 on tower plots and 0.736 on distributed
  plots). Most null detections in the interior therefore come from elsewhere
  in the window, including unsampled subplots and the ring around the box. The
  null keeps their number: observed detection density in the interior equals
  the density over the whole window within 0.004 per m² for every arm. The
  paper's nominal null uses the same mechanism.
- **Match discs beyond the window.** At 4 m no interior extends beyond the
  window, but the 20 references outside the nominal box have part of their
  4 m match disc beyond it (see the sensitivity above). At 2 m the window is
  the box plus 2 m: three plots have interior beyond it (TEAK_013, TEAK_043
  and WREF_073, 15.9 m² in total), and one reference (TEAK_013) lies beyond it,
  so no shifted detection can match it.
- **The null is held fixed in the bootstrap.** As in the paper, the plot
  bootstrap resamples plots with each cell's null mean held fixed, so the
  Monte Carlo error of the null is not in the intervals. It is 0.0006 to
  0.0009 in pooled null F1, an order of magnitude below the interval widths.
- **Few California plots.** The headline declaration admits 12 California
  plots (SJER 2, SOAP 1, TEAK 9), against 43 in the nominal analyses, so the
  regional comparison inside the censused subplots rests mostly on TEAK.
- **Scale.** Corrected leads inside the censused subplots are larger in part
  because censused F1 is larger; compare scorings by the relative leads given
  at the top, not by the absolute differences.
- **Censused precision is relative to the reference.** Unmatched interior
  detections can still be real trees below 10 cm DBH or unmapped; the null
  does not change that.
- **Post hoc.** The analysis was specified after the five-site results and the
  paper's nominal null were known. The 57 plots are those of the declaration
  reviewed for the censused-subplot study; the strict declaration is the only
  alternative run here.

## Reproduce

From the repository root, with the paper's job directories (the QL2 rung has
its own):

```sh
P=/path/to/paper_runs; PQ=/path/to/paper_runs_ql2
ROOT_QL2=/path/to/neon/frozen_2021_ql2
DN=docs/census-support-declaration-nearest.json
QL2_ARMS=chm_vwf,lmfauto,multichm,ptrees,ams3d,forestformer3d,treeisonet
QL2_ARMS=$QL2_ARMS,segmentanytree
# Native density and rungs 8, 4, 2 and 1 (Li 2012 at native density only),
# 4 m and 2 m; writes $P/sensitivity/census_null/census_null[_tol2]_*.
for T in 4 2; do
  CLAUDE_JOB_DIR=$P Rscript scripts/paper_census_null.R DECLARATION=$DN \
    TOL=$T K=200 CORES=8
done
# The QL2 rung from its own root; the master tables hold its contrasts.
for T in 4 2; do
  CLAUDE_JOB_DIR=$PQ Rscript scripts/paper_census_null.R DECLARATION=$DN \
    RUNGS=3.2 TOL=$T FROZEN_ROOT=$ROOT_QL2 ARMS=$QL2_ARMS \
    MASTER_TABLES=$P/master_tables/master_contrasts.csv K=200 CORES=8
done
# The strict declaration at native density.
CLAUDE_JOB_DIR=$P Rscript scripts/paper_census_null.R RUNGS=native K=200 \
  DECLARATION=docs/census-support-declaration-nearest-strict.json CORES=8
# The unsmoothed baseline (its own job directories; re-scored from its
# persisted detections): censused scores, its censused null (check B does not
# apply to it), then the leads over it.
NS=/path/to/paper_runs_nosmooth; NSQ=/path/to/paper_runs_nosmooth_ql2
SUP=$P/reference_support_census_event
CLAUDE_JOB_DIR=$NS Rscript scripts/score_census_support.R DECLARATION=$DN \
  ARMS=chm_vwf SUPPORT=$SUP OUT=$NS/census_support_scores/nearest_ladder
CLAUDE_JOB_DIR=$NSQ Rscript scripts/score_census_support.R DECLARATION=$DN \
  ARMS=chm_vwf RUNGS=3.2 FROZEN_ROOT=$ROOT_QL2 SUPPORT=$SUP \
  OUT=$NSQ/census_support_scores/nearest_ladder
for T in 4 2; do
  CLAUDE_JOB_DIR=$NS Rscript scripts/paper_census_null.R DECLARATION=$DN \
    ARMS=chm_vwf TOL=$T SUPPORT=$SUP CHECK_MASTER=0 K=200 CORES=8
  CLAUDE_JOB_DIR=$NSQ Rscript scripts/paper_census_null.R DECLARATION=$DN \
    ARMS=chm_vwf RUNGS=3.2 TOL=$T FROZEN_ROOT=$ROOT_QL2 SUPPORT=$SUP \
    CHECK_MASTER=0 K=200 CORES=8
  CLAUDE_JOB_DIR=$P Rscript scripts/paper_census_null_unsmoothed.R TOL=$T \
    JOBS=$P,$PQ NOSMOOTH=$NS,$NSQ
done
# The nominal-box null on plot subsets; writes $P/sensitivity/null_subsets.
CLAUDE_JOB_DIR=$P Rscript scripts/paper_null_subsets.R \
  EXCLUDE=SOAP_002,SOAP_008,SOAP_013
```

The censused runs need the committed censused scores
(`score_census_support.R`), the paper's null cells
(`paper_sensitivity.R MODE=null`, with `TOL=2` for the 2 m runs) and, for the
third check, the master tables. On 8 cores of a shared machine the 4 m run of
every rung took 26 minutes, the 2 m run 19 minutes, each QL2 run and the
strict run 4 to 5 minutes, and the subsets 10 seconds. Each censused run
writes, with the prefix `census_null` (plus `_nearest_strict` and `_tol2`
where they apply): `cells.csv` (observed and null mean counts per cell,
censused and nominal box), `pooled.csv`, `leads.csv`, `geometry.csv`,
`detections.csv`, `mcse.csv`, `checks.txt` and `tables.md` (every generated
table); `DRAWS=1` also writes the per-shift counts. `paper_null_subsets.R`
writes `null_subsets_pooled.csv`, `null_subsets_leads.csv`,
`null_subsets_plots.csv` (per plot, with the tower quadrant counts),
`null_subsets_checks.txt` and `null_subsets_tables.md`.
