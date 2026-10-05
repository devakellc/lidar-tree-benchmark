# Paper proposal: tree detectors on national-mapping airborne LiDAR

Prepared 2026-09-30 from the committed study reports and a literature scan of
about ninety primary sources. Revised 2026-10-05, after every arm was re-run
on the frozen five-site population. This document records which part of the
repository is proposed for a peer-reviewed paper, the outline of that paper,
and the work that must be completed before submission. Task tracking lives in
the GitHub issues labelled `pre-paper`; this document stays free of tracker
identifiers.

## Recommendation

The strongest paper is the NEON five-site density-ladder benchmark: zero-shot
deep 3D tree segmenters against classical detectors on national-mapping-density
airborne laser scanning (ALS), scored against field-mapped stems, with the
native FGI-EMIT work as a dense-domain control. The literature scan found no
published evaluation of SegmentAnyTree or ForestFormer3D on 1 to 8 pulses/m²
native ALS with field stems, and no test of whether decimation predicts native
sparse behaviour. The repository contains both: the benchmark on one frozen
population of 106 plots and 2,525 field stems, and a decimation test against
earlier, sparser flights over 39 of the California plots.

The re-runs changed the expected result. The first version of this proposal
expected deep segmenters to win at native density and to collapse when the
cloud is sparse. With corrected adapters and five sites, the two best
segmenters lead the classical baseline by about 0.05 F1 at native density, and
only one of the three learned point models collapses down the ladder. The
thesis, contributions and evidence below are rewritten to match. The data and
methods sections can be drafted now; the results sections wait for the
[remaining steps](#remaining-steps).

## What is publishable

| Candidate | Evidence in the repository | Novelty against the literature | Verdict |
| --- | --- | --- | --- |
| Density-ladder cross-model benchmark | 106 plots, 2,525 stems, five sites in two regions; eight full-ladder arms plus Li 2012 and two RGB detectors; paired plot-level bootstrap intervals | Closest prior work is FGI-EMIT: one boreal site subsampled from above 1,000 pts/m². Nothing at 1 to 8 pulses/m² with field stems | Primary paper |
| Reference-completeness scoring | precision inside censused subplots on 57 plots, the nominal plot box as a lower bound, co-detection crediting as a second bracket | No published critique of NEON stems as ground truth | Core section of the primary paper |
| Evaluation sensitivity kit | matcher and tolerance grid, stem-jitter bands, temporal gap, checkpoint provenance; all but the provenance audit still on the historical three-site population | No forestry greedy-versus-Hungarian comparison, no checkpoint leakage audit | Section of the primary paper once regenerated, plus a methods spin-off |
| Apex versus mask scoring | mask scores against a proxy built from stems; the five-site board lacks SegmentAnyTree; FGI-EMIT's true masks show a far smaller apex-to-mask gap | Moderate, but it rests on a proxy reference | Main text only if the proxy is validated; otherwise supplement |
| Crown delineation | five-site re-run: SegmentAnyTree matches the best CHM arm on equivalent width and leads on the widest axis; stop rule matters more than algorithm; crown width holds to 1.3 pulses/m² | Moderate | Supplement, and a second short paper |
| FGI-EMIT preregistered comparison | frozen policy, development/reserve split, bootstrap intervals | One site, within-dataset, checkpoint overlap unknown; the dataset authors already published trained-from-scratch comparisons | Positive control inside the primary paper |
| Fusion (including RGB plus LiDAR modes), routing, calibration | five-site fusion: no fused mode beats the best single arm at native density, and two-arm agreement gains 0.01 to 0.02 F1 at sparser rungs, in sample; router and calibration gains are small on the historical population | Sparse prior art, but effects are small | Supplement and one discussion paragraph |
| TEAK canopy boxes, eastern preflight, EPT throughput, SAM2Point, engine comparison | blocked, engineering-only, or (SAM2Point) a refiner that loses most of its seeds | none | Excluded; one methods sentence at most |

## Recommended paper

**Working title.** Native-density performance does not predict sparse-density
performance: benchmarking classical and zero-shot deep tree detectors on
national-mapping airborne LiDAR with field-mapped stems.

**Venue.** ISPRS Journal of Photogrammetry and Remote Sensing first, where
FGI-EMIT and ITS-Net appeared in 2026. Remote Sensing of Environment is the
alternative. IJAEOG or Remote Sensing are fallbacks.

**Thesis.** On national-mapping ALS the advantage of dense-trained deep
segmenters over classical detectors is small, and the response to point
density belongs to the individual model, not to its method family. At native
density (about 10 pulses/m²) ForestFormer3D and SegmentAnyTree lead the CHM
variable-window baseline (CHM-VWF) by about 0.05 F1; the same checkpoints lead
it by 0.26 to 0.29 on the dense FGI-EMIT reserve plots. Down the ladder
SegmentAnyTree collapses, ForestFormer3D declines slowly and TreeisoNet stays
flat. The classical detectors differ as much: AMS3D's F1 rises as the cloud
thins, while `ptrees` loses three quarters of its recall. On the decimated
ladder the ranking at native density carries over to about 2.5 pulses/m² and
shows no relation to the ranking at the two rungs below the USGS QL2 floor of
2 pulses/m². Site sets the level: ForestFormer3D's native F1 runs from 0.33
at the open oak woodland site to 0.54 at the managed conifer site.

The dense and sparse datasets differ in forest type, reference completeness
and tree-size gate as well as in density. The paper therefore presents the
0.05 against 0.26 to 0.29 comparison as a contrast, not as a controlled
effect, unless the thinning experiment in the remaining steps is run.

Two parts of the thesis are provisional. The rank comparison covers eight
arms and has no interval yet. Every rung below the native sparse flights at 4
to 5 pulses/m² is decimated, and decimation was optimistic for the one learned
arm tested on those flights. The sparse behaviour of ForestFormer3D and
TreeisoNet is therefore an upper bound until they run on the same flights.

**Contributions**, in the order of the results section:

1. Equal-support benchmark of three zero-shot 3D instance segmenters, six
   classical detectors and two RGB detectors at five sites in two regions, on
   sealed seeded clips, pooled by counts with paired plot-level bootstrap
   intervals and stratified by field crown class.
2. Reference-completeness scoring: precision inside censused subplots, the
   nominal plot box as a lower bound, and co-detection crediting as a second
   bracket. Nominal-box precision is 0.08 to 0.34 below censused precision on
   identical detections.
3. Density response by model: one segmenter's density cliff, the slow or flat
   responses of the others, the rank-stability analysis, the decomposition by
   site, and the understory floor.
4. Decimation checked against native sparse flights of the same sensor family
   over the same plots, and cross-sensor against USGS 3DEP surveys. Decimation
   is mildly optimistic for CHM detectors and more so for the learned arm
   tested.
5. Dense-domain positive control: the same checkpoints and adapters, used
   zero-shot, reach mask F1 of 0.58 and 0.65 on the three FGI-EMIT reserve
   plots. The dataset paper reports 0.65 and 0.73 for the same two
   architectures trained on FGI-EMIT and scored on other plots, which is
   context and not a like-for-like comparison (see the
   [FGI-EMIT transfer report](../results/fgi-emit-external-results.md)). The
   control exposed an adapter defect, and the re-runs a voxel setting, that
   had both looked like domain shift. The paper reports them as a caution for
   zero-shot benchmarks, with the checkpoint provenance audit alongside.
6. Evaluation sensitivity: matching rule, tolerance, stem-position jitter and
   temporal gap.
7. Apex versus mask scoring, in the main text only if the stem-derived mask
   proxy is validated against true instance masks.
8. Open harness with frozen seeded clips, pinned checkpoints and hash
   receipts.

**Primary accuracy.** Recall and its crown-class strata are reported on the
full population. Precision and F1 are reported inside censused subplots, with
the nominal-box values on the same 57 plots beside them as lower bounds. Of
the 1,190 censused references, 1,055 are at WREF and ABBY; SJER keeps two
admitted plots and SOAP one. The censused table is therefore mainly a Pacific
Northwest result, and the paper says so. On those 57 plots the nine LiDAR
arms keep the same F1 order at native density in both scorings. In the full
106-plot nominal table the F1 order differs: ForestFormer3D is ahead of
SegmentAnyTree, and TreeisoNet, CHM-VWF and `multichm` appear in the reverse
order.

**Development and replication regions.** WREF and ABBY in Washington were
added after the detectors had been run on the three California sites, and
they hold 74% of the reference stems. The working assumption is that every
detector setting was fixed on the California sites or on FGI-EMIT before the
Washington sites were scored. If the configuration-provenance check in the
remaining steps confirms it, the paper reports California as the development
region and Washington as the replication region, in place of the earlier
plot-level calibration/validation table.

## Evidence available today

Values on the frozen five-site population, unless a row says otherwise.
Density is the median first-return density of the frozen clips: 9.8 pulses/m²
at native density and 4.7, 2.5, 1.3 and 0.6 at rungs 8, 4, 2 and 1.

| Result | Value | Report |
| --- | --- | --- |
| Native F1: ForestFormer3D / SegmentAnyTree / CHM-VWF | 0.498 / 0.495 / 0.450 | [master tables](../results/master-tables-results.md) |
| Lead over CHM-VWF, native F1: ForestFormer3D / SegmentAnyTree | +0.048 [+0.028, +0.069] / +0.044 [+0.021, +0.067] | [master tables](../results/master-tables-results.md) |
| Arms indistinguishable from CHM-VWF at native density | `multichm`, Li 2012, TreeisoNet, DeepForest | [master tables](../results/master-tables-results.md) |
| SegmentAnyTree F1, native vs rung 1 | 0.495 vs 0.128 | [master tables](../results/master-tables-results.md) |
| F1, native vs rung 1: ForestFormer3D / TreeisoNet / `multichm` / AMS3D | 0.498 vs 0.421 / 0.446 vs 0.440 / 0.456 vs 0.434 / 0.240 vs 0.437 | [master tables](../results/master-tables-results.md) |
| CHM-VWF native precision, censused subplots vs nominal box, same 57 plots | 0.78 vs 0.48 | [censused subplots](../results/census-support-results.md) |
| Censused native F1: SegmentAnyTree / ForestFormer3D / Li 2012 / CHM-VWF | 0.68 / 0.67 / 0.64 / 0.61 | [master tables](../results/master-tables-results.md) |
| ForestFormer3D lead over Li 2012, censused native F1 | +0.029 [−0.007, +0.068] | [master tables](../results/master-tables-results.md) |
| F1 gain after co-detection crediting, per arm | +0.07 to +0.14 | [coverage gap](../results/coverage-gap-results.md) |
| Native sparse flight vs decimated rungs, recall: CHM-VWF and `multichm` / SegmentAnyTree (three California sites) | 0.03 to 0.05 lower / 0.06 to 0.19 lower | [native sparse epochs](../results/native-sparse-epoch-results.md) |
| Decimation noise, per-site CHM-VWF F1, SD over 11 seeds (three California sites, historical stem gate) | 0.005 to 0.028 | [frozen clips](../results/frozen-clips-results.md) |
| ForestFormer3D native F1 before and after the adapter fix: SJER / SOAP / TEAK | 0.23 to 0.33 / 0.26 to 0.45 / 0.33 to 0.50 | [model benchmark](../results/model-benchmark-results.md) |
| TreeisoNet native F1, checkpoint voxel vs 0.8 m voxel: SJER / TEAK | 0.08 vs 0.28 / 0.12 vs 0.37 | [model benchmark](../results/model-benchmark-results.md) |
| Understory recall at native density: ForestFormer3D / TreeisoNet | 0.45 / 0.19 | [model benchmark](../results/model-benchmark-results.md) |
| FGI-EMIT reserve apex F1, 257 trees: CHM-VWF / SegmentAnyTree / ForestFormer3D | 0.49 / 0.75 / 0.78 | [native pipeline](../results/final-ensemble-pipeline-results.md) |
| ForestFormer3D mask F1 at IoU 0.5: FGI-EMIT true masks / NEON proxy masks | 0.65 / 0.135 | [native pipeline](../results/final-ensemble-pipeline-results.md), [instance IoU/PQ](../results/instance-iou-pq-results.md) |
| Best fused mode minus best single arm, F1: native / rungs 8 to 1 | −0.009 / +0.009 to +0.022, in sample | [fusion study](../results/detector-fusion-results.md) |
| Crown diameter RMSE, 790 common stems: stop-rule random walker / SegmentAnyTree | 1.71 m / 1.74 m | [crown benchmark](../results/crown-segmentation-results.md) |

Values still on the historical three-site populations (43 to 46 plots, 685 to
699 stems; the master tables explain each count). They are regenerated in the
remaining steps before the paper quotes them, and the 3DEP cross-check stays
a three-site result:

| Result | Value | Report |
| --- | --- | --- |
| F1 across the matching-tolerance grid | 0.21 to 0.42 | [matcher robustness](../results/matcher-robustness-results.md) |
| CHM-VWF core false positives with no matched stem within 4 m | 94% | [matcher robustness](../results/matcher-robustness-results.md) |
| Monte-Carlo F1 band width under stem-position jitter | 0.014 to 0.037 | [positional uncertainty](../results/positional-uncertainty-results.md) |
| Kendall τ between distance and mask leaderboards | 0.47 to 0.73 | [instance IoU/PQ](../results/instance-iou-pq-results.md) |
| `multichm` beats CHM-VWF on held-out plots, SOAP / TEAK | 100% / 96% of seed-by-rung splits | [calibration/validation](../results/calibration-validation-results.md) |
| Decimated vs native-sensor 3DEP pooled recall gap | within 0.07 | [native 3DEP cross-check](../results/native-ql2-crosscheck-results.md) |

The held-out row no longer holds as stated. On five sites `multichm` is
indistinguishable from CHM-VWF at native density (+0.006 [−0.018, +0.028])
and ahead only at sparse rungs (+0.060 [+0.036, +0.082] at rung 1).

Provisional readings, derived from the generated per-rung and per-arm tables
of the paper runs. They are not in a report yet; the remaining steps publish
them with intervals:

- Rank correlation (Spearman) between native F1 and F1 at 4.7, 2.5, 1.3 and
  0.6 pulses/m², over the eight full-ladder arms: 0.83, 0.76, −0.05 and −0.19
  on the nominal box, and 0.86, 0.64, 0.02 and 0.12 inside censused subplots.
  Eight arms is a small sample.
- SegmentAnyTree's F1 down the ladder is 0.495, 0.487, 0.469, 0.376 and
  0.128, so its cliff lies between 2.5 and 0.6 pulses/m².
- Understory recall at native density, over 592 intermediate and suppressed
  stems: AMS3D 0.63 and `ptrees` 0.46, at precision of 0.15 and 0.22;
  ForestFormer3D 0.45; `multichm` 0.34; SegmentAnyTree 0.29; TreeisoNet 0.19;
  CHM-VWF 0.17.
- By region, ForestFormer3D and SegmentAnyTree lead CHM-VWF at native density
  by about 0.09 F1 on the California sites and 0.03 on the Washington sites.
  SegmentAnyTree's F1 at rung 1 is 0.11 and 0.13.
- At ABBY, the managed conifer site, CHM-VWF's native F1 (0.56) is level with
  the three learned arms (0.54 to 0.57).

## Literature positioning

Open 3D instance benchmarks are all dense. FOR-instance collections range from
about 500 to 9,500 pts/m²
([Puliti et al. 2023](https://arxiv.org/abs/2309.01279)), FGI-EMIT exceeds
1,000 pts/m² ([Ruoppa et al. 2026](https://doi.org/10.1016/j.isprsjprs.2026.04.021)),
and FOR-instance v3, introduced with SegmentAnyTreeV2, states a floor of
10 pts/m² from subsampled scenes
([Wielgosz et al. 2026](https://arxiv.org/abs/2606.08206)). NeonTreeEvaluation
is the only sparse-ALS benchmark and uses field stems for recall only
([Weinstein et al. 2021](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1009180)).

Density studies split by community. Classical work lives at 1 to 25 pulses/m²
([Jakubowski et al. 2013](https://www.sciencedirect.com/science/article/abs/pii/S0034425712004567),
[Kaartinen et al. 2012](https://www.mdpi.com/2072-4292/4/4/950),
[Sparks et al. 2022](https://doi.org/10.3390/rs14143480)). Deep-model studies
live at 10 to 10,000 pts/m², with the sparsest levels subsampled from dense
acquisitions ([Wielgosz et al. 2024](https://arxiv.org/abs/2401.15739),
[Xiang et al. 2025](https://arxiv.org/abs/2506.16991),
ITS-Net, [Li et al. 2026](https://doi.org/10.1016/j.isprsjprs.2025.11.019)). No paper
found evaluates a pretrained 3D segmenter on native 1 to 2 pulses/m² ALS or
validates decimation against a native sparse acquisition of the same stand.

Understory recall by crown class is reported mainly for classical methods on
dense ALS ([Hamraz et al. 2017](https://www.nature.com/articles/s41598-017-07200-0),
[Cao et al. 2023](https://doi.org/10.1016/j.jag.2023.103490)) and for no deep
model below 50 pts/m². Matching rules are rarely compared: the dense-cloud
community uses IoU 0.5 one-to-one matching, stem benchmarks use restricted
nearest neighbours ([Eysn et al. 2015](https://www.mdpi.com/1999-4907/6/5/1721)),
and no forestry paper contrasts greedy with optimal assignment. No checkpoint
leakage audit exists; overlap handling is self-reported. The nearest prior art
for combining detectors is RGB plus LiDAR voting
([Pleşoianu et al. 2020](https://www.mdpi.com/2072-4292/12/15/2426)); no
density-gated routing or calibration study of tree detectors was found.

Current state of the art to cite: SegmentAnyTreeV2
([Wielgosz et al. 2026](https://arxiv.org/abs/2606.08206)) and SelectAnyTree
([Nguyen et al. 2026](https://arxiv.org/abs/2606.27491)) from June 2026, ForPT
([Yue et al. 2026](https://arxiv.org/abs/2609.24787)) and ITS-Net
([Li et al. 2026](https://doi.org/10.1016/j.isprsjprs.2025.11.019)).
None reports 1 to 8 pulses/m² performance. SegmentAnyTreeV2 is not evaluated
here: its preprint promises the weights on acceptance, and none were public
on 2026-10-01. USGS 3DEP quality levels frame the target regime: QL2 requires
at least 2 pulses/m² and QL1 at least 8
([USGS](https://www.usgs.gov/3d-elevation-program/topographic-data-quality-levels-qls)).

The paper's own native acquisitions are the 2021 flights at about 10
pulses/m² and the 2017 and 2018 flights at 4 to 5. Below that, including the
QL2 floor, the evidence is decimation, which the earlier flights show to be
optimistic.

## Proposed structure

1. Introduction: national-mapping ALS as the deployment regime, the density
   gap between the classical and deep literatures, and the three practical
   questions the README asks.
2. Related work: benchmarks, density studies, understory detection, evaluation
   conventions, and detector fusion.
3. Data: five sites, plots and stems by crown class with measured pulse
   densities; the decimation ladder; the native sparse flights; the native
   3DEP cross-check clouds; the FGI-EMIT control plots.
4. Methods: the detector table with type, input, training data and checkpoint
   hash; the density-first CHM pipeline; sealed clips; matching, pooling and
   the equal-set guard; censused-subplot scoring; development and replication
   regions; uncertainty.
5. Results, one subsection per contribution.
6. Discussion: implications for USGS 3DEP users, what separates the segmenter
   that collapses from the two that do not, the understory floor, what fusion
   buys, limitations.
7. Conclusion, data and code availability.

Figures:

- Figure 1: site and canopy-structure overview.
- Figure 2: F1, recall and precision versus pulse density, five sites by all
  ladder arms, with the QL1 and QL2 floors marked.
- Figure 3: rank of each arm across the ladder, with the rank correlations.
- Figure 4: overstory and understory recall versus density.
- Figure 5: censused against nominal-box precision per arm, with the credited
  bracket.
- Figure 6: native sparse flights against decimated rungs, by arm and crown
  class.
- Figure 7: sensitivity panel with tolerance grid, matcher variants and jitter
  bands.

Tables:

- Table 1: sites, plots, stems by crown class, measured pulse densities.
- Table 2: detectors with type, input, training data and checkpoint hash.
- Table 3: master table, censused and nominal, with plot-level bootstrap
  intervals; RGB detectors as native-only rows.
- Table 4: California development region against Washington replication
  region.
- Table 5: the same checkpoints on the FGI-EMIT reserve and on NEON.
- Table 6: compute cost per plot.

Fusion, routing, calibration, crown diameters, allometry, the temporal check
and, unless the proxy is validated, mask scoring go to the supplement.

## Work before submission

### Outcome of the first plan

The plan of 2026-09-30 had ten steps. Their outcomes:

| Step | Outcome | Report |
| --- | --- | --- |
| 1. Decide on and prepare NEON WREF and ABBY | Both admitted; under the adopted stem gate the reference grows from 662 to 2,525 stems | [Pacific Northwest preflight](../results/pacific-northwest-extension-results.md) |
| 2. Freeze the plot population and the clips | Done: stems of at least 10 cm DBH, six-stem plot gate kept, one sealed clip root for every arm | [frozen clips](../results/frozen-clips-results.md) |
| 3. Re-run ForestFormer3D and TreeisoNet with corrected adapters | Done at five sites on the full ladder | [model benchmark](../results/model-benchmark-results.md) |
| 4. Add SegmentAnyTreeV2 | Not possible: no public weights. The first SegmentAnyTree stays | — |
| 5. Precision inside censused subplots | Done: 57 of 106 plots admitted | [censused subplots](../results/census-support-results.md) |
| 6. Native sparse validation | Done for CHM-VWF, `multichm` and SegmentAnyTree. Hand-annotated canopy boxes stay a supplementary reference | [native sparse epochs](../results/native-sparse-epoch-results.md) |
| 7. Fill or drop pending items | Done: crown and fusion results on the frozen population | [crown benchmark](../results/crown-segmentation-results.md), [fusion study](../results/detector-fusion-results.md) |
| 8. Master tables and bootstrap intervals | Tables done. The density-ladder, model-benchmark and calibration/validation reports still show the historical population | [master tables](../results/master-tables-results.md) |
| 9. Publication hygiene | Licence, bibliography and availability statement done. Pulse-density reporting, the archive and the reproduction script remain | [availability](data-code-availability.md) |
| 10. Optional fine-tuning of SegmentAnyTree | Not pursued. Zero-shot use of published checkpoints is the stated scope | — |

### Remaining steps

In execution order, numbered on from the first plan. Each is tracked as a
GitHub issue labelled `pre-paper`.

11. **Run ForestFormer3D and TreeisoNet on the native sparse flights.** The
    [native sparse study](../results/native-sparse-epoch-results.md) ran
    CHM-VWF, `multichm` and SegmentAnyTree only, and found decimation
    optimistic by up to 0.19 recall for the learned arm. Until the other two
    learned arms run on the 2017 and 2018 flights, the claim that they hold up
    when sparse rests on decimation alone.
12. **Add a rung at the QL2 floor.** The QL2 floor of 2 pulses/m² falls
    between the rungs at 2.5 and 1.3 pulses/m², where SegmentAnyTree's F1
    drops from 0.47 to 0.38. Freeze one more rung at 2.0 pulses/m² in a new
    root and score every ladder arm on it.
13. **Regenerate the reports that still use the historical population.** The
    density-ladder report, the body of the model benchmark, the matcher and
    tolerance grid, the positional-jitter bands, the temporal check and the
    distance-versus-mask rank comparison are re-scored from the persisted
    paper-run detections. The calibration/validation table is either re-run
    on the adopted population or replaced by the regional split of step 14.
    The native 3DEP cross-check cannot be re-scored from those detections:
    its detector is re-run on 3DEP clouds against the adopted stems of the
    three California sites, and it stays a three-site result. Clouds are
    cached for 40 of the 43 adopted plots; three need a new pull. Every
    regenerated report gives its rungs as measured pulses/m².
14. **Extend the master tables.** Add crown-class and height-band strata with
    intervals, the California and Washington regional tables, the
    rank-stability statistic with a plot-bootstrap interval, and the
    configuration-provenance check that the regional framing depends on.
15. **Settle mask scoring and bridge the dense control.** Add SegmentAnyTree
    to the five-site mask board and declare the TreeisoNet mask voxel. On the
    FGI-EMIT development plots, under a new declared protocol that leaves the
    reserve sealed, validate the stem-derived mask proxy against the true
    masks and thin the clouds to the NEON ladder densities. The thinning
    separates density from the forest and reference differences that confound
    the dense-against-sparse contrast.
16. **Build the figures, the detector table and the compute-cost table.** One
    script per figure, reading the master outputs. Only TreeisoNet's paper
    runs logged per-plot time, so the cost table needs timed runs.
17. **Finish the archive.** Record image digests and checkpoint hashes for
    every arm from run manifests, deposit the frozen clips, stems, hashes and
    result tables on Zenodo, add the one-command reproduction, and check once
    more for released SegmentAnyTreeV2 weights before submission.

## Reference population

Every paper table uses the declared `adopted` population of the
[frozen-clip study](../results/frozen-clips-results.md): live mapped stems of
at least 10 cm DBH inside the plot core, in plots holding at least six such
trees.

| Site | Plots | Stems | Censused plots | Censused references |
| --- | ---: | ---: | ---: | ---: |
| SJER | 6 | 57 | 2 | 14 |
| SOAP | 18 | 231 | 1 | 2 |
| TEAK | 19 | 374 | 9 | 119 |
| WREF | 38 | 1,063 | 28 | 642 |
| ABBY | 25 | 800 | 17 | 413 |
| Total | 106 | 2,525 | 57 | 1,190 |

Two sensitivity populations are scored alongside: the historical stem gate
(116 plots, 2,854 stems) and no six-stem plot gate (149 plots, 2,628 stems).
The [master tables](../results/master-tables-results.md) explain every earlier
per-report count. NEON censuses sample 800 m² of each 1,600 m² tower plot,
and no census is held in every plot every year, so precision inside sampled,
censused subplots stays necessary.

## Reviewer risks and mitigations

- Zero-shot unfairness: zero-shot use of published checkpoints is the stated
  scope, because NEON provides stems and not instance labels to train on. The
  dense-domain control shows that the checkpoints and adapters work.
- Newer models: no public checkpoint of SegmentAnyTreeV2, ForPT or ITS-Net
  was found on 2026-10-01. The harness takes a new arm without new
  infrastructure, and the check is repeated before submission.
- Incomplete stems: censused subplots, with credited F1 as a second bracket.
- Decimation versus native: the native sparse flights at 4 to 5 pulses/m² and
  the cross-sensor check. Below that density the evidence is decimation alone,
  so sparse-rung results are stated as upper bounds.
- Dense against sparse is confounded by forest and reference: the thinning of
  FGI-EMIT, or an explicit statement that the comparison is a contrast.
- Geography: oak woodland and conifer sites in California and Washington plus
  the boreal control. No eastern broadleaf site; stated as scope.
- A generous 4 m tolerance: the tolerance grid and the jitter bands,
  regenerated on the five-site population.
- Settings tuned on evaluation plots: the California and Washington split,
  after the provenance check.
- Proxy masks: validated on FGI-EMIT or moved to the supplement.
- Small SJER sample: six plots and 57 stems, reported with its intervals and
  not interpreted alone.
- Integration errors: the positive control and the run manifests; the two
  defects found are reported.

## Timeline

The re-runs that the first plan budgeted at three to four weeks, and the
WREF and ABBY extension, were finished within a week. The remaining steps are
mostly re-scoring from persisted detections, plus GPU runs on 39 sparse-epoch
plots, one extra rung and the FGI-EMIT thinning, and the figure scripts. That
is an estimated two to three weeks. Writing needs four to six weeks.
Submission in about two months is realistic.

## Spin-offs

- Methods paper for Methods in Ecology and Evolution: reference incompleteness,
  matching rules and positional uncertainty in field-stem benchmarks.
- Short crown-delineation paper: the deep-model crown section is now complete
  on five sites.
