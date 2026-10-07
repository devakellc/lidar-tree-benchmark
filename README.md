# LiDAR Tree Benchmarks

<!-- HTML preserves the centered header and explicit image width. -->
<!-- rumdl-disable MD033 -->

<p align="center">
  <img src="assets/intelifore-promo-lidar.gif"
       alt="Animated LiDAR point-cloud forest scene"
       width="720">
</p>

<p align="center">
  <strong>Individual-tree detection and crown delineation from airborne
  LiDAR.</strong><br>
  Classical CHM methods · Point-cloud segmentation · Deep models · RGB fusion
</p>

<p align="center">
  <a href="#results-at-a-glance">At a glance</a> ·
  <a href="#methods-and-results">Results</a> ·
  <a href="#start-here">Quick start</a> ·
  <a href="#reproduce-a-workflow">Workflows</a> ·
  <a href="#script-reference">Scripts</a>
</p>

<!-- rumdl-enable MD033 -->

This research repository compares tree detectors and crown segmenters across
point densities, forest types, and reference annotations. It contains
standalone R scripts, Python/GPU model adapters, evaluation tools, and reports.
Outputs include treetop coordinates, crown polygons, labelled point clouds,
and detection and delineation metrics.

The main questions are practical: how much does sparse LiDAR change detection,
which methods recover understory trees, and when does combining detectors help?
Start with the results below, or run the bundled tile to explore the methods
without downloading a benchmark dataset.

## Results at a glance

![F1, recall, precision and chance-corrected F1 against pulse density](paper/figures/figure_2.png)

*Figure 2 of the [draft paper](paper/manuscript.md). (a) F1, (b) recall,
(c) precision and (d) F1 corrected for chance agreement at the 4 m match
radius, for the eight detectors with a full density ladder, against median
first-return pulse density, five NEON sites, nominal plot core, with 95%
plot-bootstrap intervals; the rung at the QL2 floor is included. Dotted lines
mark the USGS QL1 (8 pulses/m²) and QL2 (2 pulses/m²) floors. The dashed line
with open circles in (a) to (c) is CHM-VWF run without its sub-8 pulses/m²
smoothing, a post hoc sensitivity; it was not run on the QL2 rung, so that
segment has no point at 2.0, and it has no null, so it is absent from (d).*

### Accuracy by detector

Eleven detectors scored against 2,525 field-mapped stems in 106 plots
(nominal plot core, greedy 4 m matching with a height gate). The three learned
point detectors run zero-shot with their published checkpoints; DeepForest's
training annotations include SJER and TEAK, so it is not zero-shot at those
two sites. Li 2012 and the two RGB detectors have no density ladder, and the
RGB detectors are not in the censused scorer. Corrected F1 removes the score
that randomly shifted copies of the same detections earn,
(F1 − null) / (1 − null). Censused F1 is scored inside the censused subplots
of 57 plots (1,190 references). Values are from Tables 3, 4 and 6 of the draft
paper.

| Detector | Type | F1, native (9.8 pulses/m²) | F1, QL2 floor (2.0) | F1, 0.6 pulses/m² | Lead over CHM-VWF, native | Corrected lead, native | Censused F1, native |
| --- | --- | --- | ---: | ---: | --- | --- | ---: |
| ForestFormer3D | Learned, transformer instance segmentation | 0.498 [0.478, 0.520] | 0.452 | 0.421 | +0.048 [+0.028, +0.069] | +0.020 [−0.002, +0.041] | 0.668 |
| SegmentAnyTree | Learned, sparse-convolutional instance segmentation | 0.495 [0.466, 0.522] | 0.449 | 0.128 | +0.044 [+0.021, +0.067] | +0.034 [+0.008, +0.057] | 0.677 |
| `multichm` | Classical, local maxima over height-sliced CHMs | 0.456 [0.435, 0.477] | 0.449 | 0.434 | +0.005 [−0.018, +0.028] | −0.017 [−0.039, +0.005] | 0.597 |
| Li 2012 | Classical, point-cloud region growing | 0.456 [0.426, 0.483] | — | — | +0.006 [−0.009, +0.019] | +0.000 [−0.015, +0.014] | 0.638 |
| DeepForest | RGB crown boxes | 0.454 [0.428, 0.478] | — | — | +0.004 [−0.014, +0.022] | −0.007 [−0.028, +0.012] | — |
| CHM-VWF | Classical, CHM local maxima with a height-dependent window | 0.450 [0.423, 0.478] | 0.392 | 0.374 | — | — | 0.608 |
| TreeisoNet | Learned, tree localisation and offset networks | 0.446 [0.420, 0.470] | 0.449 | 0.440 | −0.004 [−0.018, +0.009] | −0.011 [−0.029, +0.005] | 0.622 |
| `lmfauto` | Classical, point local maxima with an automatic window | 0.386 [0.352, 0.421] | 0.273 | 0.269 | −0.064 [−0.095, −0.030] | −0.056 [−0.079, −0.034] | 0.539 |
| Detectree2 | RGB crown polygons | 0.362 [0.334, 0.390] | — | — | −0.089 [−0.120, −0.060] | −0.054 [−0.088, −0.021] | — |
| `ptrees` | Classical, multi-scale point segmentation | 0.331 [0.296, 0.369] | 0.405 | 0.271 | −0.120 [−0.154, −0.085] | −0.095 [−0.123, −0.067] | 0.496 |
| AMS3D | Classical, adaptive mean shift in 3D | 0.240 [0.214, 0.267] | 0.412 | 0.437 | −0.210 [−0.240, −0.180] | −0.132 [−0.159, −0.107] | 0.364 |

At 0.6 pulses/m² ForestFormer3D, TreeisoNet, `multichm` and AMS3D lead CHM-VWF
by 0.05 to 0.07 F1, but corrected for chance those leads are −0.008 to +0.021
and none excludes zero. The baseline's sub-8 pulses/m² smoothing rule costs it
0.06 to 0.07 F1 on each of the four decimated rungs it was re-run on without
the rule ([baseline smoothing
sensitivity](results/baseline-smoothing-sensitivity-results.md)).

SAM2Point, prompted with up to 40 CHM-VWF tops per plot, scores F1 0.132 at
native density against 0.405 for its own seeds. It appears in the
[master tables](results/master-tables-results.md) and the sensitivity studies
but is not analysed further; the
[SAM2Point study](results/sam2point-promptable-refine-results.md) describes the
method and a two-plot pilot. The [detector table](results/detector-table.md)
gives each detector's type, input, training data, hashes and licence.

### Experiments in the paper

One row per study of the [draft paper](paper/manuscript.md). Earlier studies
on the three-site population are described under
[Methods and results](#methods-and-results).

| Experiment | Question | Data | Main result | Report |
| --- | --- | --- | --- | --- |
| Density ladder | How does accuracy change from native density to 0.6 pulses/m²? | 5 NEON sites, 106 plots, 2,525 stems; 8 detectors at 6 densities | ForestFormer3D loses 0.08 F1 over the ladder and TreeisoNet stays flat; SegmentAnyTree falls from 0.495 to 0.128; below native density the leads over CHM-VWF rest on its smoothing rule (next row) | [master tables](results/master-tables-results.md#headline-tables), [model comparison](results/model-benchmark-results.md#five-sites-every-arm-paper-numbers) |
| Baseline smoothing | Does CHM-VWF's sub-8 pulses/m² smoothing rule drive the sparse-density leads? | CHM-VWF re-run without the rule on the four decimated rungs other than the QL2 rung; post hoc | The rule costs CHM-VWF 0.06–0.07 F1 on each rung; against the unsmoothed baseline the leads of ForestFormer3D, TreeisoNet and `multichm` below native density, and SegmentAnyTree's at 4.7 and 2.5 pulses/m², are −0.013 to +0.024 (only the two segmenters' at 4.7 pulses/m² exclude zero, both weakly); the headline keeps the declared rule | [baseline smoothing](results/baseline-smoothing-sensitivity-results.md) |
| QL2 floor | On which side of 2 pulses/m² does each detector change? | A sixth rung at 2.0 pulses/m², declared and frozen in its own root | SegmentAnyTree is level with the leaders at the floor, having lost almost a quarter of its recall, and collapses below it; native rank predicts rank down to the floor (Spearman 0.71) and not below (−0.05), and the break survives the chance correction | [QL2 rung](results/master-tables-results.md#the-ql2-rung), [rank stability](results/master-tables-results.md#rank-stability-across-density), [chance agreement](results/matcher-robustness-results.md#chance-agreement) |
| Collapse mechanism | Why does SegmentAnyTree collapse below the QL2 floor? | Persisted instance clouds of the two segmenters at native density and the four decimated rungs other than the QL2 rung | Its semantic head still labels 70–89% of core points as tree, but the share of them grouped into instances falls from 0.86 to 0.05: a 0.3 m grouping radius against a point spacing that grows to 0.95 m | [instance audit](results/instance-audit-results.md) |
| Chance agreement | How much F1 do randomly shifted detections earn? | 200 shared random shifts per plot, 4 m and 2 m radius | The null reaches 70–79% of every detector's F1 at 4 m; the two segmenters' corrected leads are 0.00–0.03 | [matcher robustness](results/matcher-robustness-results.md#chance-agreement) |
| Regions | Do the California findings replicate in Washington? | 43 California plots (development), 63 Washington plots (replication) | Leads over CHM-VWF are about 0.09 in California and 0.03 in Washington; above chance at native density only in California; at 4.7 pulses/m² the two segmenters' corrected leads do not separate the regions | [regions](results/master-tables-results.md#development-and-replication-regions), [chance agreement](results/matcher-robustness-results.md#chance-agreement) |
| Population rule | Do the leads depend on the DBH floor or the six-tree plot rule? | Populations without the 10 cm DBH floor (116 plots, 2,854 stems) and without the six-tree rule (149 plots, 2,628 stems) | ForestFormer3D's lead holds in both (+0.038, and +0.033 weakly) and SegmentAnyTree's without the DBH floor (+0.035, weakly); SegmentAnyTree's inference fails on one clip of the other population | [sensitivity populations](results/master-tables-results.md#sensitivity-populations) |
| Understory | Which detectors find intermediate and suppressed stems? | 592 understory and 1,872 overstory stems | AMS3D recalls 0.63, `ptrees` 0.46, ForestFormer3D 0.45, CHM-VWF 0.17; above the null, AMS3D and ForestFormer3D add 0.09 at 4 m | [crown classes](results/master-tables-results.md#recall-by-crown-class), [chance agreement](results/matcher-robustness-results.md#chance-agreement) |
| Reference completeness | How much do unmapped trees understate precision? | Censused subplots of 57 plots; co-detection credit on all 106 | Censused precision is 0.08–0.34 higher; censused F1 0.68 (SegmentAnyTree), 0.67 (ForestFormer3D), 0.61 (CHM-VWF); co-detection credit, taken at each detector's best density per site and so in sample, adds 0.07–0.14 F1 | [censused subplots](results/census-support-results.md), [coverage gap](results/coverage-gap-results.md) |
| Native sparse flights | Does decimation predict a natively sparse acquisition? | SJER 2017, SOAP and TEAK 2018 flights; 586 stems on 39 plots | Native flights give lower recall than the bracketing decimated rungs: 0.03–0.05 for CHM-VWF, `multichm`, ForestFormer3D and TreeisoNet, 0.06–0.19 for SegmentAnyTree | [native sparse epochs](results/native-sparse-epoch-results.md) |
| Cross-sensor check | Does another sensor, decimated alike, give the same scores? | USGS 3DEP clouds over the 43 California plots | CHM-VWF −0.014 [−0.047, +0.016], `multichm` −0.030 [−0.055, −0.006] F1 | [native 3DEP cross-check](results/native-ql2-crosscheck-results.md) |
| Matcher and stem position | Do the leads depend on the matcher or on stem-position error? | Hungarian assignment, a crown-scaled tolerance, both together and a soft 3-D cost; 2–5 m radii; 200 jitter draws | The leads hold under every matcher at 3–5 m (Kendall τ ≥ 0.85); at 2 m ForestFormer3D's falls to +0.012; jitter bands ≤ 0.008 F1 | [matcher robustness](results/matcher-robustness-results.md), [positional uncertainty](results/positional-uncertainty-results.md) |
| Temporal gap | Do results hold against stems measured in the flight year only? | 44 plots with 2021 measurements | SegmentAnyTree keeps +0.039 [+0.008, +0.069]; ForestFormer3D's lead vanishes (+0.000) | [temporal sensitivity](results/temporal-sensitivity-results.md) |
| Calibration | Does tuning CHM-VWF help on held-out plots? | Stratified calibration and validation halves, 10 seeds | Held-out F1 within a few hundredths of the fixed setting; the best grid cell gains 0.006–0.016 in sample | [calibration/validation](results/calibration-validation-results.md) |
| Crown diameters | Which segmenters match field crown widths? | 790 stems matched by every segmenter | Lowest equivalent-circle RMSE: random walker with per-crown stop 1.71 m, SegmentAnyTree 1.74 m | [crown benchmark](results/crown-segmentation-results.md) |
| Instance masks | How good are point-level masks on NEON? | Stem-based proxy masks; proxy checked on FGI-EMIT's true labels | Mask F1 0.152 (SegmentAnyTree) and 0.135 (ForestFormer3D); the proxy costs a quarter to a third of mask F1, so these scores rank only | [instance IoU](results/instance-iou-pq-results.md), [proxy validation](results/fgiemit-proxy-validation-results.md) |
| Detector fusion | Does combining detectors help? | Union, majority and k-of-n agreement over nine detectors | No fused mode beats the best single detector at native density; 0.01–0.02 F1 at sparser densities, in sample | [fusion](results/detector-fusion-results.md) |
| Dense control | Do the checkpoints work on dense ALS with manual labels? | FGI-EMIT reserve: 3 plots, 257 trees | Apex F1 0.78 (ForestFormer3D), 0.75 (SegmentAnyTree), 0.49 (CHM-VWF) | [FGI-EMIT pipeline](results/final-ensemble-pipeline-results.md) |
| Dense control thinned | Does density explain the FGI-EMIT and NEON contrast? | 10 FGI-EMIT development plots thinned to the NEON densities | At 11 pulses/m² ForestFormer3D's lead (0.08) agrees with NEON's (0.05) within the intervals; from 5 pulses/m² down it stays at 0.17–0.21, so the datasets are a contrast; SegmentAnyTree's collapse replicates | [thinning](results/fgiemit-thinning-results.md) |
| Compute cost | What does each detector cost per plot? | 9 plots on an i9-14900K and an RTX 5090 | Classical detectors take seconds; ForestFormer3D 64–104 s; SegmentAnyTree 251–445 s | [compute cost](results/compute-cost-results.md) |
| Reproduction | Can every table be rebuilt from the archive? | 5.5 GB archive of clips, detections and provenance | One command rebuilds the NEON tables on CPU; clean-container rebuilds on 5 and 6 October 2026 gave 1,221 files, none differing beyond declared tolerances. The chance-agreement null and its variants, the leave-out and chance-corrected rank correlations, the baseline smoothing sensitivity and the instance audit were added afterwards, and the figures have been redrawn since; these await the next rebuild | [archive guide](docs/reproduction-archive.md) |

## Methods and results

### Detection across point densities

The paper's numbers come from the [master tables](results/master-tables-results.md):
every arm on one declared population of five NEON sites (SJER, SOAP and TEAK
in California; WREF and ABBY in Washington; 106 plots and 2,525 field stems).
The [frozen-clip study](results/frozen-clips-results.md) fixes hash-verified
clips at native density (median 9.8 first-return pulses/m²) and at four
decimated rungs (4.7, 2.5, 1.3 and 0.6 pulses/m²), plus a rung at the USGS
QL2 floor (2.0 pulses/m²) frozen in its own root. Every pooled number and
arm-versus-arm difference carries a paired plot-bootstrap interval.

![Reference stems, native pulse density and stem heights](paper/figures/figure_1.png)

*Figure 1 of the draft paper. The reference population. Left: classed stems
by field crown class at each site; the 61 stems without a crown class, 29 of
them at SJER, are not shown. Centre: first-return pulse density of the native
plot clips; the dotted line is the QL1 floor of 8 pulses/m². Right: field
heights of the reference stems.*

- At native density ForestFormer3D (F1 **0.498**) and SegmentAnyTree
  (**0.495**) lead CHM variable-window filtering (CHM-VWF, **0.450**) by
  **+0.048 [+0.028, +0.069]** and **+0.044 [+0.021, +0.067]**. `multichm`,
  Li 2012, DeepForest and TreeisoNet are indistinguishable from CHM-VWF.
- Randomly shifted copies of each arm's detections reach 70–79% of its
  native F1 at the 4 m match radius, a zero-skill score that tends to
  overstate the chance part. Corrected for chance, ForestFormer3D's lead is
  **+0.020 [−0.002, +0.041]** and SegmentAnyTree's **+0.034 [+0.008,
  +0.057]** (+0.003 and +0.017 at 2 m); see the
  [matcher-robustness study](results/matcher-robustness-results.md#chance-agreement).
- SegmentAnyTree stays level with the leading arms at the QL2 floor (F1
  **0.449** at 2.0 pulses/m², with almost a quarter of its recall lost) and
  collapses below it (**0.38** at 1.3 and **0.13** at 0.6 pulses/m²).
  TreeisoNet, `multichm` and ForestFormer3D hold and lead CHM-VWF by 0.05–0.07
  at 0.6 pulses/m², but corrected for chance those leads are −0.008 to +0.021,
  and against CHM-VWF run without its sub-8 pulses/m² smoothing (a post hoc
  sensitivity on the four decimated rungs other than the QL2 rung) they are
  within 0.03 of zero; see the
  [baseline smoothing
  sensitivity](results/baseline-smoothing-sensitivity-results.md).
  SegmentAnyTree's collapse is a failure of its instance grouping, not of its
  semantic head ([instance audit](results/instance-audit-results.md)). Native
  rank predicts rank down to the QL2 floor (Spearman 0.71) and not below (−0.05
  at 1.3 pulses/m²); SegmentAnyTree and AMS3D carry the break, and without them
  the other six keep 0.54.
- CHM-VWF is flat across density on the California sites but loses
  0.07–0.10 F1 in Washington; one density curve does not describe every site.
  See the [density-ladder study](results/density-ladder-sweep-results.md).
- The point segmenters find understory stems best: AMS3D recalls **0.63** of
  592 intermediate and suppressed stems, against **0.17** for CHM-VWF, at a
  large precision cost. The null reaches 79–97% of every arm's understory
  recall at 4 m; above it AMS3D and ForestFormer3D recall 0.09 (0.15 and
  0.11 at 2 m).
- ForestFormer3D and SegmentAnyTree lead CHM-VWF in both regions, by about
  0.09 in California and 0.03 in Washington, where Li 2012 is level with
  them; the [configuration provenance](docs/configuration-provenance.md)
  shows that no detector setting was chosen from Washington scores. Corrected
  for chance at native density, both leads are clear in California and not
  in Washington. On the
  exact-2021 reference SegmentAnyTree's lead holds overall and in California
  and is positive but not distinguishable from zero in Washington, while
  ForestFormer3D's holds in California and is negative in Washington, within
  an interval that spans zero (−0.018 [−0.061, +0.020] on 33 plots;
  [temporal-sensitivity study](results/temporal-sensitivity-results.md)).

![Rank of each detector down the ladder](paper/figures/figure_3.png)

*Figure 3 of the draft paper. Left: rank by F1 of the eight ladder detectors
at each density. Right: Spearman correlation between the ranking at native
density and the ranking at each rung, with 95% plot-bootstrap intervals, for
all eight detectors and for the six left when SegmentAnyTree and AMS3D are
removed.*

![Overstory and understory recall against pulse density](paper/figures/figure_4.png)

*Figure 4 of the draft paper. Recall of overstory (dominant and codominant)
and understory (intermediate and suppressed) stems against median first-return
pulse density, five sites, with 95% intervals.*

![Sensitivity to match radius, matcher, stem jitter and chance agreement](paper/figures/figure_7.png)

*Figure 7 of the draft paper. Sensitivity of the evaluation at native density,
five sites. (a) F1 against the match radius. (b) Change in F1 from the default
greedy 4 m matcher under four alternatives (a crown-scaled tolerance,
Hungarian assignment, both together and a soft 3-D cost), with 95% intervals.
(c) Width of the 90% stem-jitter band against the width of the 95%
plot-bootstrap interval for each detector. (d) Observed F1 and the F1 of
randomly shifted copies of the same detections (the chance-agreement null) at
the 4 m and 2 m radii; the segment between the open and the filled symbol is
the excess above the null. SAM2Point is shown in (a) to (c) for
completeness.*

The [model comparison](results/model-benchmark-results.md#five-sites-every-arm-paper-numbers)
gives every arm by rung and site; the [detector table](results/detector-table.md)
gives each arm's type, input, training data, hashes and licence, and the
[compute-cost table](results/compute-cost-results.md) its wall time and memory
per plot (seconds for the classical arms, TreeisoNet and Detectree2; one to
seven minutes for the other learned arms). The
[native sparse epoch study](results/native-sparse-epoch-results.md) compares
earlier, sparser NEON flights (SJER 2017, SOAP and TEAK 2018, about 4–5 first
returns per m²) with the 2021 clouds decimated to the bracketing rungs, on the
same 586 stems. Decimation is mildly optimistic for CHM-VWF and `multichm`
(recall **0.03–0.05** higher than the native flight) and more so for
SegmentAnyTree (**0.06** at rung 4 and **0.19** at rung 8, about 2.9 and
5.4 pulses/m² on those California plots), so its sparse-rung recall is an
upper bound.

![Recall on native sparse flights and decimated rungs](paper/figures/figure_6.png)

*Figure 6 of the draft paper. Recall on the natively sparse 2017 and 2018
flights and on the 2021 clouds at two decimated rungs and at native density,
for the 586 stems live in both epochs on 39 California plots: all stems,
overstory and understory. Rung densities are medians over these plots, which
are denser than the five-site medians of 2.5 and 4.7 pulses/m².*

All scores in this section are field-stem detection scores, and incomplete
mapping limits their
reading as complete-census precision; the
[reference-support audit](results/neon-reference-support-results.md)
documents those limits. The
[censused-subplot study](results/census-support-results.md) therefore scores
precision only inside surveyed, censused subplots, from each plot's nearest
full census within four years of the 2021 flights. It scores 57 of the 106
plots. On identical detections, censused precision is 0.08–0.34 higher than
nominal-box precision (CHM-VWF at native density: 0.78 against 0.48). At native
density SegmentAnyTree (**0.68**) and ForestFormer3D (**0.67**) have the
highest censused F1, against **0.61** for CHM-VWF. The
[coverage-gap study](results/coverage-gap-results.md) brackets the same bias
from the other side: crediting detections that two other arm families also
find raises F1 by **+0.07 to +0.14** per arm.

![Precision under three references](paper/figures/figure_5.png)

*Figure 5 of the draft paper. Precision under three references. Circles:
nominal plot core at native density, 106 plots, with 95% intervals. Triangles:
censused subplots at native density, 57 plots, with 95% intervals. Arrows: raw
to co-detection-credited precision at the density each detector scores best at
per site, except CHM-VWF, whose arrow is at native density. For the other LiDAR
detectors except Li 2012 that density is a sparser rung at one or more sites,
and the arrows of AMS3D, `ptrees`, TreeisoNet and SegmentAnyTree start visibly
away from the native-density circle. Circles and triangles are on different
plot sets; on the same 57 plots CHM-VWF's nominal precision is 0.48.*

ForestFormer3D and TreeisoNet were re-run on all five sites with corrected
adapters; the
[re-run comparison](results/model-benchmark-results.md#corrected-adapter-re-runs-on-the-frozen-clips)
supersedes their June 2026 rows. The historical June study on SOAP (18 plots,
232 stems), the paired [RGB-LiDAR study](results/rgb-lidar-fusion-results.md)
and the other three-site reports use separate reference populations; compare
methods within each study.

The [point-cloud detector study](results/pointcloud-detector-results.md)
compares native-density understory recovery by crown class, with a separate
two-rung density-ladder extension.

### Crown delineation

The [crown benchmark](results/crown-segmentation-results.md) compares growing
rules on a shared canopy-height model (CHM) and common seed basis, and the
deep instance segmenters, against NEON field crown diameters. On the frozen
five-site population, over the 790 stems every arm matched, the random walker
with a per-crown stopping rule and SegmentAnyTree have the lowest
equivalent-circle diameter RMSE (**1.71 m** and **1.74 m**), and SegmentAnyTree
the lowest maximum-caliper RMSE (**2.38 m**, against **2.83 m** for the random
walker). Crown width holds to 2 points/m² and degrades slightly at 1.

Diameter definitions matter: equivalent-circle diameter is compared with
`ninetyCrownDiameter`, and maximum-caliper diameter with `maxCrownDiameter`.
These errors measure crown size, separately from detection F1 or point-mask IoU.
The [NEON instance study](results/instance-iou-pq-results.md) uses
Voronoi-on-stems proxy masks, not manually delineated crowns.

### Native FGI-EMIT pipeline

The [native pipeline study](results/final-ensemble-pipeline-results.md) compares
CHM-VWF, SegmentAnyTree (SAT), and ForestFormer3D (FF3D) against manual point
instances. It separates ten development plots from three reserve plots.
FF3D was selected on development data before the reserve was evaluated.

| Detector | Reserve apex F1 | Reserve instance F1 at IoU 0.5 |
| --- | ---: | ---: |
| CHM-VWF | 0.4881 | — |
| SegmentAnyTree | 0.7462 | 0.5758 |
| ForestFormer3D | 0.7761 | 0.6493 |

All three reserve plots and 257 reference trees contribute to these pooled
scores. CHM-VWF has no instance-mask score. FF3D has the highest pooled F1,
although per-plot rankings vary.

The fixed fusion candidates did not beat FF3D on development F1, so the
pipeline's default remains the frozen single-model policy. It exports
separate treetop and instance products; general site/density routing and fused
crown refinement are not validated. Upstream checkpoint training exposure is
unknown, and independent above-ground-height accuracy is unverified. These
results therefore support a conditional within-dataset comparison, not proof
of performance on unseen USGS or NEON data.

Two development diagnostics bridge FGI-EMIT to the NEON benchmark. The
[proxy validation](results/fgiemit-proxy-validation-results.md) builds NEON's
Voronoi-on-stems mask reference from FGI-EMIT's true trees: it keeps the arms'
order and compresses their mask scores. The
[thinning study](results/fgiemit-thinning-results.md) thins the development
plots to the NEON densities: at 11 pulses/m² ForestFormer3D's lead over
CHM-VWF falls to 0.08, close to its NEON lead, and from 5 pulses/m² down it
stays at 0.17–0.21, two to four times the NEON lead, so the two datasets are
reported as a contrast rather than a controlled density effect.
SegmentAnyTree collapses below 2 pulses/m² on the thinned plots, as on NEON.

### TEAK and USGS-like data

The [USGS 3DEP example](#usgs-3dep-aoi) demonstrates acquisition and processing.
The historical NEON results provide field-stem comparisons in western forests,
including TEAK. Neither alone validates a detector for a new survey.

The [TEAK canopy comparison](results/teak-comparison-workflow-results.md)
provides a review workflow for historical RGB boxes and native LiDAR. Real
accuracy comparison remains blocked by reference review, registration, and
validated crown-box adapters. Its detector compatibility runs establish that
the models execute; they do not establish a TEAK crown-accuracy ranking.

## Benchmark design

The [methodology](docs/treetop-detection-approach.md) explains the processing
and evaluation choices. The main principles are:

- Measure density first. First-return density (`frdens`) controls CHM
  resolution, window size, and smoothing; all-return density (`pdens`)
  controls thinning and prevents requests to upsample sparse inputs.
- Report density as first-return pulses/m². Rungs are named by their
  all-return decimation target (8, 4, 2 and 1 points/m²); on the frozen
  five-site population these give medians of 4.7, 2.5, 1.3 and 0.6
  pulses/m², and the native clouds 9.8 (all-return 17.9 points/m²). The
  [master tables](results/master-tables-results.md) list the measured density
  of every rung and site.
- Compare equivalent support. Keep site, plot, density, and reference support
  aligned across methods, and report missing or failed cells explicitly. All
  NEON arms read one declared plot population and one sealed set of frozen
  clips.
- Match detections one-to-one within the mapped plot core, with a height gate.
  Pool counts before calculating rates, and error sums before calculating RMSE.
- Keep calibration and evaluation plots separate. Density variants of one
  plot stay together, and frozen reserve results do not select parameters.
- Distinguish field stems, proxy masks, manual point instances, and image
  boxes. They support different claims and cannot share an accuracy ranking.
- Use metric coordinates and explicit height datums. lasR's TIN-based
  `pit_fill` and lidR's `pitfree()` construct different CHMs; the
  [engine comparison](results/treetop-lasr-vs-lidr-comparison.md) includes a
  shared-CHM test to separate surface construction from peak finding.

## Start here

Run commands from the repository root. The core examples need R with **lasR
from `r-lidar/lasR@pre-devel`**, lidR, terra, sf, and data.table. The variable
window used here requires that lasR build; see the
[setup notes](results/density-ladder-sweep-results.md). Model-specific
containers, checkpoints, and environments are documented under [gpu](gpu/).

The following comparison uses `MixedConifer.las` from the lasR installation;
no additional data download is needed:

```sh
export CLAUDE_JOB_DIR="$PWD/work/demo"
mkdir -p "$CLAUDE_JOB_DIR"
Rscript scripts/detect_lasr.R
Rscript scripts/detect_lidr.R
Rscript scripts/compare.R
Rscript scripts/shared_chm.R
```

The two detection scripts write treetop CSVs. `compare.R` compares their
locations, while `shared_chm.R` runs both peak finders on the same CHM. This
tile is an implementation example, not a field-ground-truth accuracy test.

For crown polygons and their comparison, continue with:

```sh
Rscript scripts/segment_lasr.R
Rscript scripts/segment_lidr.R
Rscript scripts/compare_crowns.R \
  "$CLAUDE_JOB_DIR/crowns_lasr.gpkg" \
  "$CLAUDE_JOB_DIR/crowns_lidr.gpkg"
```

## Reproduce a workflow

Use a distinct `CLAUDE_JOB_DIR` for each experiment. Downloaded data, model
resources, and accepted-run artifacts are prerequisites for the larger
studies; a clone does not include them. Most R drivers use `KEY=VALUE`
arguments, while Python drivers use flags. Check the selected script's parser
and linked study instructions before changing its invocation.

### Rebuild the paper tables

The reproduction archive holds the sealed frozen clips, plot populations,
every arm's per-cell results and persisted detections, and the census and
sparse-epoch inputs. One command rebuilds every table of the frozen-clip
benchmark from it on CPU, without inference, downloads or a NEON token, and
checks each rebuilt file against the archived copy:

```sh
docker build -t lidar-tree-benchmark-reproduce reproduce
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/repo:ro \
  -v /path/to/archive:/archive:ro -v /path/to/scratch:/out \
  lidar-tree-benchmark-reproduce \
  bash scripts/reproduce_paper_tables.sh ARCHIVE=/archive OUT=/out/run CORES=8
```

The image pins R 4.3.3, lasR, lidR and the geometry packages to the versions
the tables were computed with. The [archive guide](docs/reproduction-archive.md)
lists its layout and what it leaves out;
[model-provenance.json](docs/model-provenance.json) records the checkpoint
hashes, image IDs and source commits of the learned arms.
`scripts/stage_archive.sh` builds the archive from a working directory.

### USGS 3DEP AOI

With PDAL 2.9 or later, extract the fixed example area of interest (AOI) from a
public EPT source. The extraction reprojects Web Mercator to UTM before metric
processing. After setting `CLAUDE_JOB_DIR` to a new directory and creating it:

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"
(cd "$CLAUDE_JOB_DIR" && pdal pipeline "$REPO_ROOT/scripts/extract.json")
Rscript scripts/detect_lasr_aoi.R
Rscript scripts/detect_lidr_aoi.R
Rscript scripts/shared_chm_aoi.R
```

Inspect [extract.json](scripts/extract.json) for the source, bounds, and target
CRS. The [AOI report](results/treetop-lasr-vs-lidr-comparison.md) covers the
comparison and larger-area experiments.

### Field and instance benchmarks

| Workflow | Instructions and results |
| --- | --- |
| Plot population and frozen clips | [Frozen-clip study](results/frozen-clips-results.md); run it before any NEON arm |
| Precision inside censused subplots | [Censused-subplot study](results/census-support-results.md) and its reviewed declarations under `docs/` |
| NEON field-stem density ladder | [Density-ladder study](results/density-ladder-sweep-results.md) and [cross-model comparison](results/model-benchmark-results.md) |
| Crown diameters and segmentation | [Crown benchmark](results/crown-segmentation-results.md) |
| Paired optical/LiDAR fusion | [RGB-LiDAR comparison](results/rgb-lidar-fusion-results.md) and [confidence calibration](results/confidence-calibration-results.md) |
| Native FGI-EMIT products | [Current execution guide](docs/final-ensemble-pipeline-v2.md) and [development/reserve results](results/final-ensemble-pipeline-results.md) |
| Historical TEAK canopy review | [Review protocol](docs/teak-comparison-workflow-protocol.md) and [current eligibility limits](results/teak-comparison-workflow-results.md) |

NEON acquisition also needs `neonUtilities`, `jsonlite`, `curl`, `digest`,
network access, and `NEON_TOKEN` for downloads. GPU arms require their existing
model environments and weights; use the corresponding runtime guide rather
than a single environment for every detector.

The native FGI-EMIT entry point verifies prepared inputs, a frozen policy, and
accepted inference before assembling products. Follow its guide to supply
those resources and choose a fresh output directory. To explore the assembly
interfaces without models or benchmark data, use the synthetic example:

```sh
Rscript scripts/assemble_metapipeline_v2.R MODE=synthetic \
  OUT="$CLAUDE_JOB_DIR/synthetic-assembly"
```

This needs the core R packages plus `jsonlite` and `digest`, and an output path
that does not exist. It illustrates completed, empty, failed, and unsupported
inputs; it computes no real-data accuracy metrics. See the
[assembly contracts](docs/metapipeline-contracts.md).

## Script reference

These are the main entry points; each study above documents its supporting
scripts and configuration.

| Task | Entry points |
| --- | --- |
| Toy detection and engine comparison | [detect_lasr.R](scripts/detect_lasr.R), [detect_lidr.R](scripts/detect_lidr.R), [compare.R](scripts/compare.R), [shared_chm.R](scripts/shared_chm.R) |
| Toy crown products | [segment_lasr.R](scripts/segment_lasr.R), [segment_lidr.R](scripts/segment_lidr.R), [compare_crowns.R](scripts/compare_crowns.R) |
| USGS extraction and detection | [extract.json](scripts/extract.json), [detect_lasr_aoi.R](scripts/detect_lasr_aoi.R), [detect_lidr_aoi.R](scripts/detect_lidr_aoi.R), [shared_chm_aoi.R](scripts/shared_chm_aoi.R) |
| Tiled point-cloud processing | [tile_aoi.R](scripts/tile_aoi.R), [detect_lasr_catalog.R](scripts/detect_lasr_catalog.R), [detect_lidr_catalog.R](scripts/detect_lidr_catalog.R) |
| NEON acquisition and references | [neon_ground_truth.R](scripts/neon_ground_truth.R), [neon_download_lidar.R](scripts/neon_download_lidar.R), [neon_download_aop.R](scripts/neon_download_aop.R), [preflight_site_extension.R](scripts/preflight_site_extension.R) |
| NEON population and frozen clips | [freeze_clips.R](scripts/freeze_clips.R), [check_frozen_ladder.R](scripts/check_frozen_ladder.R) |
| NEON master tables and intervals | [master_tables.R](scripts/master_tables.R), [master_tables_lib.R](scripts/master_tables_lib.R) |
| Paper sensitivities, figures and compute cost | [paper_sensitivity.R](scripts/paper_sensitivity.R), [corrected_rank_stability.R](scripts/corrected_rank_stability.R), [baseline_smoothing_sensitivity.R](scripts/baseline_smoothing_sensitivity.R), [instance_audit.R](scripts/instance_audit.R), [paper_figures.R](scripts/paper_figures.R), [compute_cost.sh](scripts/compute_cost.sh), [compute_cost_cell.R](scripts/compute_cost_cell.R) |
| Native 3DEP cross-check | [native_ql2_crosscheck.R](scripts/native_ql2_crosscheck.R), [native_ql2_paired.R](scripts/native_ql2_paired.R), [ept_discovery.R](scripts/ept_discovery.R) |
| Reproduction archive and table rebuild | [stage_archive.sh](scripts/stage_archive.sh), [reproduce_paper_tables.sh](scripts/reproduce_paper_tables.sh), [compare_reproduction.R](scripts/compare_reproduction.R), [reproduce/Dockerfile](reproduce/Dockerfile) |
| NEON censused-subplot precision | [neon_reference_support.R](scripts/neon_reference_support.R), [review_census_support.R](scripts/review_census_support.R), [score_census_support.R](scripts/score_census_support.R) |
| Native sparse epochs | [prepare_sparse_epoch.R](scripts/prepare_sparse_epoch.R), [audit_sparse_epoch.R](scripts/audit_sparse_epoch.R), [compare_sparse_epoch.R](scripts/compare_sparse_epoch.R) |
| NEON density ladder | [run_sweep.R](scripts/run_sweep.R), [analyze_sweep.R](scripts/analyze_sweep.R), [compare_sites.R](scripts/compare_sites.R) |
| Point-cloud understory detection | [detect_pc_sweep.R](scripts/detect_pc_sweep.R), [detect_pc_ladder.R](scripts/detect_pc_ladder.R) |
| Cross-model detection analysis | [analyze_model_benchmark.R](scripts/analyze_model_benchmark.R), [compare_model_sites.R](scripts/compare_model_sites.R) |
| Crown-diameter evaluation | [crown_metrics_sweep.R](scripts/crown_metrics_sweep.R), [crown_metrics_3d.R](scripts/crown_metrics_3d.R), [crown_metrics_deepmodel.R](scripts/crown_metrics_deepmodel.R), [analyze_crown_metrics.R](scripts/analyze_crown_metrics.R) |
| Instance masks, credited F1 and re-scoring | [score_instances_iou.R](scripts/score_instances_iou.R), [compare_matching_rules.R](scripts/compare_matching_rules.R), [coverage_gap.R](scripts/coverage_gap.R), [export_best_treetops_geojson.R](scripts/export_best_treetops_geojson.R), [rescore_population.R](scripts/rescore_population.R), [compare_adapter_reruns.R](scripts/compare_adapter_reruns.R) |
| Calibration/validation and the historical sensitivity studies | [calval_split.R](scripts/calval_split.R), [matcher_robustness.R](scripts/matcher_robustness.R), [mc_positional_uncertainty.R](scripts/mc_positional_uncertainty.R), [temporal_sensitivity.R](scripts/temporal_sensitivity.R) |
| FGI-EMIT proxy validation and thinning | [fgiemit_proxy_validation.R](scripts/fgiemit_proxy_validation.R), [fgiemit_thin_select.R](scripts/fgiemit_thin_select.R), [fgiemit_thin_write.py](scripts/fgiemit_thin_write.py), [run_fgiemit_thinning.py](scripts/run_fgiemit_thinning.py), [fgiemit_thinning_summary.R](scripts/fgiemit_thinning_summary.R) |
| Detection fusion and calibration | [fuse_detectors.R](scripts/fuse_detectors.R), [calibrate_confidence.R](scripts/calibrate_confidence.R) |
| Native and synthetic product assembly | [assemble_metapipeline_v2.R](scripts/assemble_metapipeline_v2.R), [run_ensemble_pipeline_v2.py](scripts/run_ensemble_pipeline_v2.py) |
| TEAK review preparation and eligibility | [run_teak_comparison_workflow.R](scripts/run_teak_comparison_workflow.R) |

## Repository contents

- [scripts](scripts/) — acquisition, processing, scoring, and export drivers.
- [gpu](gpu/) — model adapters and runtime setup instructions.
- [results](results/) — committed study reports and interpretation limits.
- [docs](docs/) — methodology, study protocols, execution guides, and the
  [paper proposal](docs/paper-proposal.md).
- [paper](paper/) — the draft manuscript of the benchmark paper, its
  supplement and figures.
- [Data and code availability](docs/data-code-availability.md) — data
  sources, model licences and what the archive holds; the
  [bibliography](docs/references.bib) holds the verified references.
- [data](data/) — tracked GeoJSON site, plot, stem, and AOI context.
- [tests](tests/) — regression tests for scoring, data handling, and workflows.

Generated clouds, rasters, tables, review packets, logs, model weights, and
local environments are ignored by Git. Their paths in reports identify local
artifacts, not files available through GitHub. R scripts use
`CLAUDE_JOB_DIR`, defaulting to `work/`; preserve existing results and use fresh
locations for changed experiments.

For R regression tests and documentation checks:

```sh
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
```

Python/GPU tests use the environment required by the affected model or workflow;
raster tests additionally require `rasterio`. Test success checks implementation
contracts; performance claims require the corresponding data and study runs.

## License

The code and documentation in this repository are released under the
[MIT License](LICENSE). Components and data keep their own terms:

- [external/treeiso](external/treeiso/) is vendored under its own MIT License
  ([LICENSE](external/treeiso/LICENSE)).
- NEON field and airborne data are released under CC0 1.0; USGS 3DEP point
  clouds are public domain.
- FGI-EMIT data are licensed CC BY-NC-SA 4.0 and are not redistributed here.
- Model checkpoints and container images used by the GPU arms remain under
  their upstream licences; this repository pins their hashes but does not
  redistribute them.
