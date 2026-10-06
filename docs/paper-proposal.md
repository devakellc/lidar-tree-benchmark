# Paper proposal: tree detectors on national-mapping airborne LiDAR

Prepared 2026-09-30 from the committed study reports and a literature scan of
about ninety primary sources. Revised 2026-10-05 after every arm was re-run on
the frozen five-site population, and 2026-10-06 after the remaining
pre-submission steps were completed. This document records which part of the
repository is proposed for a peer-reviewed paper, the outline of that paper,
and the state of the work. Task tracking lives in the GitHub issues labelled
`pre-paper`; this document stays free of tracker identifiers.

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

The evidence is complete. Every step of the pre-submission plan below is
done except the archive deposit, every number the paper needs sits in a
committed report with a plot-bootstrap interval, and the tables rebuild from
the staged archive in a clean container. Writing can start on every section.

The results changed the expected story twice. The first version of this
proposal expected deep segmenters to win at native density and collapse when
the cloud is sparse. The five-site re-runs showed a lead of about 0.05 F1 at
native density and a collapse for one of the three learned point models. The
dense-control thinning then showed that density explains the small NEON lead
at native density and not below it. The thesis below is the one the evidence
supports.

## What is publishable

| Candidate | Evidence in the repository | Novelty against the literature | Verdict |
| --- | --- | --- | --- |
| Density-ladder cross-model benchmark | 106 plots, 2,525 stems, five sites in two regions; eight full-ladder arms on six rungs, including one at the USGS QL2 floor, plus Li 2012 and two RGB detectors; paired plot-level bootstrap intervals | Closest prior work is FGI-EMIT: one boreal site subsampled from above 1,000 pts/m². Nothing at 1 to 8 pulses/m² with field stems | Primary paper |
| Reference-completeness scoring | precision inside censused subplots on 57 plots, the nominal plot box as a lower bound, co-detection crediting as a second bracket | No published critique of NEON stems as ground truth | Core section of the primary paper |
| Evaluation sensitivity kit | matcher and tolerance grid, stem-jitter bands and exact-2021 cut for every arm on five sites; checkpoint and configuration provenance | No forestry greedy-versus-Hungarian comparison, no checkpoint leakage audit | Section of the primary paper, plus a methods spin-off |
| Dense-domain control and thinning | FGI-EMIT frozen policy, development/reserve split, and the development plots thinned to the NEON densities against true labels | The dataset authors published trained-from-scratch comparisons; no zero-shot thinning of a dense ALS benchmark | Positive control and dataset contrast inside the primary paper |
| Apex versus mask scoring | NEON mask scores against a stem-derived proxy; the proxy validated on FGI-EMIT costs about a third of mask F1 and compresses gaps | Moderate; the proxy ranks arms and does not measure them | Supplement |
| Crown delineation | five-site re-run: SegmentAnyTree matches the best CHM arm on equivalent width and leads on the widest axis; stop rule matters more than algorithm; crown width holds to 1.3 pulses/m² | Moderate | Supplement, and a second short paper |
| Fusion (including RGB plus LiDAR modes), routing, calibration | five-site fusion: no fused mode beats the best single arm at native density, and two-arm agreement gains 0.01 to 0.02 F1 at sparser rungs, in sample; router and calibration gains are small on the historical population | Sparse prior art, but effects are small | Supplement and one discussion paragraph |
| TEAK canopy boxes, eastern preflight, EPT throughput, SAM2Point, engine comparison | blocked, engineering-only, or (SAM2Point) a refiner that loses most of its seeds | none | Excluded; one methods sentence at most |

## Recommended paper

**Working title.** Native-density performance does not predict sparse-density
performance: benchmarking classical and zero-shot deep tree detectors on
national-mapping airborne LiDAR with field-mapped stems. The claim holds
below the USGS QL2 floor, and the title can say so.

**Venue.** ISPRS Journal of Photogrammetry and Remote Sensing first, where
FGI-EMIT and ITS-Net appeared in 2026. Remote Sensing of Environment is the
alternative. IJAEOG or Remote Sensing are fallbacks.

**Thesis.** On the NEON benchmark the two best zero-shot deep segmenters lead
the CHM variable-window baseline (CHM-VWF) by about 0.05 F1 at native density
(about 10 pulses/m²). Thinning FGI-EMIT to 11 pulses/m² cuts ForestFormer3D's
lead over CHM-VWF from 0.30 to 0.08 [0.03, 0.13], close to NEON's 0.05, but
from 5 pulses/m² down the FGI-EMIT lead returns to 0.17 to 0.21 while NEON's
stays at 0.05 to 0.09, so the paper reports the two datasets as a contrast
rather than a controlled density effect. The response to point density
belongs to the individual model, not to its method family. SegmentAnyTree
holds to the QL2 floor of 2 pulses/m²
and collapses below it, a pattern that replicates against FGI-EMIT's true
labels; ForestFormer3D declines slowly and TreeisoNet stays flat; among the
classical detectors AMS3D's F1 rises as the cloud thins, while `ptrees` loses
three quarters of its recall. The rank of the eight ladder arms at native
density predicts their rank down to the QL2 floor (Spearman 0.71
[0.38, 0.81]) and not below it (−0.05 [−0.17, 0.26] at 1.3 pulses/m²). Site
sets the level: ForestFormer3D's native F1 runs from 0.33 at the open oak
woodland site to 0.54 at the managed conifer site, and the Washington sites
replicate the California ranking at the top.

These readings hold under every matcher (the learned lead stays 0.03 to 0.06
and the twelve-arm ranking keeps Kendall τ ≥ 0.85), under stem-position
jitter (90% bands at most 0.008 F1 wide), inside censused subplots, in both
regions, and on the native sparse flights for all three learned arms, where
decimation overstates recall by 0.03 to 0.05 for ForestFormer3D and TreeisoNet
and by up to 0.19 for SegmentAnyTree. Two qualifications travel with them: on
the exact-2021 subset of 44 plots ForestFormer3D's lead over CHM-VWF holds in
California and reverses in Washington while SegmentAnyTree's holds in both,
and DeepForest is not zero-shot at SJER and TEAK, whose imagery is in its
training annotations.

**Contributions**, in the order of the results section:

1. Equal-support benchmark of three zero-shot 3D instance segmenters, six
   classical detectors and two RGB detectors at five sites in two regions, on
   sealed seeded clips at six densities including the QL2 floor, pooled by
   counts with paired plot-level bootstrap intervals and stratified by field
   crown class.
2. Reference-completeness scoring: precision inside censused subplots, the
   nominal plot box as a lower bound, and co-detection crediting as a second
   bracket. Nominal-box precision is 0.08 to 0.34 below censused precision on
   identical detections.
3. Density response by model: one segmenter's cliff below the QL2 floor, the
   slow or flat responses of the others, rank stability with intervals, the
   decomposition by site (CHM-VWF is flat in California and loses 0.07 to
   0.10 F1 in Washington), and the understory floor (AMS3D recalls 0.63 of
   592 understory stems against 0.17 for CHM-VWF, at a large precision cost).
4. Decimation checked against native sparse flights of the same sensor family
   over the same plots for every learned arm, and cross-sensor against USGS
   3DEP surveys.
5. Dense-domain control and dataset contrast: the same checkpoints and
   adapters on the FGI-EMIT reserve, the development plots thinned to the NEON
   densities, and the integration defects the control exposed, reported as a
   caution for zero-shot benchmarks with the checkpoint provenance audit
   alongside.
6. Evaluation sensitivity: matching rule, tolerance, stem-position jitter,
   temporal gap, configuration provenance and regional replication.
7. Open harness: frozen seeded clips, pinned checkpoints, hash receipts, and
   an archive whose tables rebuild with one command in a clean container.

**Primary accuracy.** Recall, precision, F1 and the crown-class strata are
reported on the full 106-plot population in the nominal plot box, the
headline table of the master tables and the README, with its precision read
as a lower bound. Precision and F1 inside censused subplots are reported
beside them as the reference-support bracket, with the nominal-box values on
the same 57 plots alongside; at native density the censused leads over
CHM-VWF are +0.068 [+0.036, +0.100] for SegmentAnyTree and +0.059 [+0.020,
+0.099] for ForestFormer3D. Of the 1,190 censused references, 1,055 are at
WREF and ABBY; SJER keeps two admitted plots and SOAP one. The censused table
is therefore mainly a Pacific Northwest result, and the paper says so. On
those 57 plots the nine LiDAR arms keep the same F1 order at native density
in both scorings. In the full 106-plot nominal table the F1 order differs:
ForestFormer3D is ahead of SegmentAnyTree, and TreeisoNet, CHM-VWF and
`multichm` appear in the reverse order. The subplot-exclusion rule of the
censused scoring was narrowed after censused scores that included Washington
existed, so the paper reports the broader rule as a strict sensitivity beside
the bracket; native precision differs by about 0.01 between the two.

**Development and replication regions.** WREF and ABBY in Washington were
added after the detectors had been run on the three California sites, and
they hold 74% of the reference stems. The
[configuration provenance](configuration-provenance.md) record shows that
every setting behind the master tables was fixed before Washington was
scored, from California data, FGI-EMIT, the literature or package defaults;
the four later changes are defect fixes or throughput. The paper therefore
reports California as the development region and Washington as the
replication region, in place of a plot-level calibration/validation table.
Credited F1 and fusion select per-site configurations in sample and stay
outside that comparison.

## Evidence available today

Values on the frozen five-site population unless a row says otherwise.
Density is the median first-return density of the frozen clips: 9.8 pulses/m²
at native density and 4.7, 2.5, 2.0 (the QL2 rung), 1.3 and 0.6 at the
decimated rungs.

| Result | Value | Report |
| --- | --- | --- |
| Native F1: ForestFormer3D / SegmentAnyTree / CHM-VWF | 0.498 / 0.495 / 0.450 | [master tables](../results/master-tables-results.md) |
| Lead over CHM-VWF, native F1: ForestFormer3D / SegmentAnyTree | +0.048 [+0.028, +0.069] / +0.044 [+0.021, +0.067] | [master tables](../results/master-tables-results.md) |
| Arms indistinguishable from CHM-VWF at native density | `multichm`, Li 2012, TreeisoNet, DeepForest | [master tables](../results/master-tables-results.md) |
| SegmentAnyTree F1: native / 2.0 / 1.3 / 0.6 pulses/m² | 0.495 / 0.449 / 0.376 / 0.128 | [master tables](../results/master-tables-results.md) |
| SegmentAnyTree − CHM-VWF, F1: 2.0 / 1.3 pulses/m² | +0.058 [+0.036, +0.081] / −0.007 [−0.030, +0.016] | [master tables](../results/master-tables-results.md) |
| F1, native vs 0.6 pulses/m²: ForestFormer3D / TreeisoNet / `multichm` / AMS3D | 0.498 vs 0.421 / 0.446 vs 0.440 / 0.456 vs 0.434 / 0.240 vs 0.437 | [master tables](../results/master-tables-results.md) |
| Spearman, native rank vs rank at 4.7 / 2.5 / 2.0 / 1.3 / 0.6 pulses/m² | 0.83 / 0.76 / 0.71 [0.38, 0.81] / −0.05 [−0.17, 0.26] / −0.19 | [master tables](../results/master-tables-results.md) |
| Understory recall, native, 592 stems: AMS3D / ForestFormer3D / `multichm` / SegmentAnyTree / CHM-VWF | 0.63 / 0.45 / 0.34 / 0.29 / 0.17 | [master tables](../results/master-tables-results.md) |
| ForestFormer3D lead over CHM-VWF: California / Washington; difference | +0.086 / +0.032; +0.054 [+0.013, +0.098] | [master tables](../results/master-tables-results.md) |
| The same leads inside censused subplots | +0.061 / +0.059 | [master tables](../results/master-tables-results.md) |
| CHM-VWF native precision, censused subplots vs nominal box, same 57 plots | 0.78 vs 0.48 | [censused subplots](../results/census-support-results.md) |
| Censused native F1: SegmentAnyTree / ForestFormer3D / Li 2012 / CHM-VWF | 0.68 / 0.67 / 0.64 / 0.61 | [master tables](../results/master-tables-results.md) |
| F1 gain after co-detection crediting, per arm | +0.07 to +0.14 | [coverage gap](../results/coverage-gap-results.md) |
| CHM-VWF F1 change, native to 4.7 pulses/m²: California / Washington | −0.018 [−0.054, +0.017] / −0.070 [−0.098, −0.044] | [density ladder](../results/density-ladder-sweep-results.md) |
| Native sparse flight vs decimated rungs, recall: CHM arms / ForestFormer3D and TreeisoNet / SegmentAnyTree (three California sites) | 0.03 to 0.05 lower / 0.03 to 0.05 lower / 0.06 to 0.19 lower | [native sparse epochs](../results/native-sparse-epoch-results.md) |
| Decimated 3DEP minus decimated NEON, F1, 43 California plots: CHM-VWF / `multichm` | −0.014 [−0.047, +0.016] / −0.030 [−0.055, −0.006] | [native 3DEP cross-check](../results/native-ql2-crosscheck-results.md) |
| FGI-EMIT reserve apex F1, 257 trees: CHM-VWF / SegmentAnyTree / ForestFormer3D | 0.49 / 0.75 / 0.78 | [native pipeline](../results/final-ensemble-pipeline-results.md) |
| ForestFormer3D lead over CHM-VWF on FGI-EMIT thinned to 11.3 / 5.4 / 2.9 / 1.5 / 0.7 pulses/m² | +0.08 / +0.20 / +0.21 / +0.18 / +0.17 | [FGI-EMIT thinning](../results/fgiemit-thinning-results.md) |
| SegmentAnyTree lead over CHM-VWF on thinned FGI-EMIT: 2.9 / 1.5 / 0.7 pulses/m² | +0.19 / +0.03 [−0.04, +0.10] / −0.23 | [FGI-EMIT thinning](../results/fgiemit-thinning-results.md) |
| Mask F1 against the stem-derived proxy on FGI-EMIT, ForestFormer3D: truth / proxy | 0.72 / 0.49 (−0.230 [−0.292, −0.161]) | [proxy validation](../results/fgiemit-proxy-validation-results.md) |
| ForestFormer3D native F1 before and after the adapter fix: SJER / SOAP / TEAK | 0.23 to 0.33 / 0.26 to 0.45 / 0.33 to 0.50 | [model benchmark](../results/model-benchmark-results.md) |
| TreeisoNet native F1, checkpoint voxel vs 0.8 m voxel: SJER / TEAK | 0.08 vs 0.28 / 0.12 vs 0.37 | [model benchmark](../results/model-benchmark-results.md) |
| Learned lead over CHM-VWF under five matchers and a 3 to 5 m radius | +0.03 to +0.06; Kendall τ with the baseline ranking ≥ 0.85 | [matcher robustness](../results/matcher-robustness-results.md) |
| Hungarian assignment, change in native F1, any arm | at most +0.03 (+0.04 with crown-scaled tolerance) | [matcher robustness](../results/matcher-robustness-results.md) |
| Stem-jitter 90% band width, F1, 200 draws | at most 0.008 | [positional uncertainty](../results/positional-uncertainty-results.md) |
| Exact-2021 cut, 44 plots, 1,318 stems: recall change / ForestFormer3D F1 change | +0.01 to +0.04 for most arms / −0.049 | [temporal sensitivity](../results/temporal-sensitivity-results.md) |
| Held-out F1 after tuning CHM-VWF against the declared configuration | within a few hundredths | [calibration/validation](../results/calibration-validation-results.md) |
| Decimation noise, per-site CHM-VWF F1, SD over 11 seeds (three California sites, historical stem gate) | 0.005 to 0.028 | [frozen clips](../results/frozen-clips-results.md) |
| Best fused mode minus best single arm, F1: native / rungs 8 to 1 | −0.009 / +0.009 to +0.022, in sample | [fusion study](../results/detector-fusion-results.md) |
| Crown diameter RMSE, 790 common stems: stop-rule random walker / SegmentAnyTree | 1.71 m / 1.74 m | [crown benchmark](../results/crown-segmentation-results.md) |
| Wall time per plot, native density: classical arms / ForestFormer3D / SegmentAnyTree | seconds / 64 to 104 s / 251 to 445 s | [compute cost](../results/compute-cost-results.md) |
| Clean-container rebuild of the archive, 5 October 2026 | 1,207 of 1,221 files byte-identical, none differing | [archive guide](reproduction-archive.md) |

Every report the paper cites now opens with its five-site section; the
historical three-site sections are marked as such and stay for the record.

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
mildly optimistic for every arm but SegmentAnyTree, and the thinned FGI-EMIT
plots, which replicate SegmentAnyTree's collapse against true labels.

## Proposed structure

1. Introduction: national-mapping ALS as the deployment regime, the density
   gap between the classical and deep literatures, and the three practical
   questions the README asks.
2. Related work: benchmarks, density studies, understory detection, evaluation
   conventions, and detector fusion.
3. Data: five sites, plots and stems by crown class with measured pulse
   densities; the decimation ladder and the QL2 rung; the native sparse
   flights; the native 3DEP cross-check clouds; the FGI-EMIT control plots.
4. Methods: the detector table with type, input, training data and checkpoint
   hash; the density-first CHM pipeline; sealed clips; matching, pooling and
   the equal-set guard; censused-subplot scoring; development and replication
   regions; the thinning protocol; uncertainty.
5. Results, one subsection per contribution.
6. Discussion: implications for USGS 3DEP users, what separates the segmenter
   that collapses from the two that do not, why the NEON lead is small when
   the FGI-EMIT lead is not, the understory floor, what fusion buys,
   limitations.
7. Conclusion, data and code availability.

Figures, as drawn by `paper_figures.R` from the master tables and the study
outputs, each with the numbers it plots in a CSV:

- Figure 1: sites, stems by crown class, native pulse density and stem
  heights.
- Figure 2: F1, recall and precision versus pulse density, five sites by all
  ladder arms, with the QL1 and QL2 floors marked.
- Figure 3: rank of each arm down the ladder, with the rank correlations and
  their intervals.
- Figure 4: recall by crown class versus density.
- Figure 5: censused against nominal-box precision per arm, with the credited
  bracket.
- Figure 6: native sparse flights against decimated rungs, by arm and crown
  class.
- Figure 7: sensitivity panel with the match radius, the matcher variants and
  the jitter bands against plot sampling.

Tables:

- Table 1: sites, plots, stems by crown class, measured pulse densities.
- Table 2: detectors with type, input, training data, hash and licence (the
  [detector table](../results/detector-table.md)).
- Table 3: master table, censused and nominal, with plot-level bootstrap
  intervals; RGB detectors as native-only rows.
- Table 4: California development region against Washington replication
  region.
- Table 5: the same checkpoints on the FGI-EMIT reserve, on FGI-EMIT thinned
  to the NEON densities, and on NEON.
- Table 6: compute cost per plot (the
  [compute-cost table](../results/compute-cost-results.md)).

Fusion, routing, calibration, crown diameters, allometry, the temporal check
and mask scoring with its proxy validation go to the supplement.

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
| 6. Native sparse validation | Done for CHM-VWF, `multichm` and SegmentAnyTree, then for the other learned arms in step 11. Hand-annotated canopy boxes stay a supplementary reference | [native sparse epochs](../results/native-sparse-epoch-results.md) |
| 7. Fill or drop pending items | Done: crown and fusion results on the frozen population | [crown benchmark](../results/crown-segmentation-results.md), [fusion study](../results/detector-fusion-results.md) |
| 8. Master tables and bootstrap intervals | Done, and extended in step 14 | [master tables](../results/master-tables-results.md) |
| 9. Publication hygiene | Licence, bibliography, availability statement, pulse-density units, archive staging and a clean-container rebuild done. The deposit remains | [availability](data-code-availability.md) |
| 10. Optional fine-tuning of SegmentAnyTree | Not pursued. Zero-shot use of published checkpoints is the stated scope | — |

### Outcome of the remaining steps

The seven steps added on 2026-10-05, numbered on from the first plan:

| Step | Outcome | Report |
| --- | --- | --- |
| 11. ForestFormer3D and TreeisoNet on the native sparse flights | Done. Their native sparse recall is 0.03 to 0.05 below the decimated rungs, as for the CHM arms; ForestFormer3D's F1 is level with both rungs and TreeisoNet's about 0.04 below | [native sparse epochs](../results/native-sparse-epoch-results.md) |
| 12. A rung at the QL2 floor | Done: declared before any run, frozen in its own root at 2.0 pulses/m², scored by all eight ladder arms. SegmentAnyTree holds there and collapses below | [QL2 rung declaration](ql2-rung-declaration.md), [master tables](../results/master-tables-results.md) |
| 13. Regenerate the historical-population reports | Done: every paper-cited report opens with a five-site section for every arm, in pulses/m²; the 3DEP cross-check runs against the adopted stems of the 43 California plots | [density ladder](../results/density-ladder-sweep-results.md), [model benchmark](../results/model-benchmark-results.md) and the sensitivity reports |
| 14. Extend the master tables | Done: crown-class and height-band strata, regional tables and leads, rank stability with intervals, and the configuration provenance record | [master tables](../results/master-tables-results.md), [configuration provenance](configuration-provenance.md) |
| 15. Settle mask scoring and bridge the dense control | Done. SegmentAnyTree is on the five-site mask board and the TreeisoNet mask voxel is declared; the proxy costs about a third of mask F1 on FGI-EMIT, so mask scores go to the supplement; thinning matches the NEON lead at 11 pulses/m² and keeps 0.17 to 0.21 below it, so the datasets are a contrast | [proxy validation](../results/fgiemit-proxy-validation-results.md), [FGI-EMIT thinning](../results/fgiemit-thinning-results.md) |
| 16. Figures, detector table and compute cost | Done: seven figures with their numbers, the detector table with verified training data, and timed runs of every arm | [detector table](../results/detector-table.md), [compute cost](../results/compute-cost-results.md) |
| 17. Archive and reproduction | Staged (5.5 GB) and rebuilt in a clean container with no differing file; the deposit remains | [archive guide](reproduction-archive.md) |

### Before submission

1. Deposit the staged archive on Zenodo and record the DOI in the
   availability statement and the README.
2. Replace the frozen-clip study's reference to the commit the canonical root
   was frozen at, which is not in the public history, with the archive's
   recorded code commit.
3. Check once more for released SegmentAnyTreeV2 weights.
4. Write the paper.

## Reference population

Every paper table uses the declared `adopted` population of the
[frozen-clip study](../results/frozen-clips-results.md): live mapped stems of
at least 10 cm DBH inside the plot core, in plots holding at least six such
trees. The QL2 rung's root carries the same population and native clips.

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
  dense-domain control shows that the checkpoints and adapters work, and the
  thinning shows that density alone does not remove their advantage.
- Newer models: no public checkpoint of SegmentAnyTreeV2, ForPT or ITS-Net
  was found on 2026-10-01. The harness takes a new arm without new
  infrastructure, and the check is repeated before submission.
- Incomplete stems: censused subplots, with credited F1 as a second bracket,
  and the strict exclusion rule as a sensitivity.
- Decimation versus native: native sparse flights at 4 to 5 pulses/m² for
  every learned arm, the cross-sensor check, and the thinned FGI-EMIT plots
  against true labels. SegmentAnyTree's sparse-rung recall is an upper bound
  by up to 0.19 and is reported as such.
- Dense against sparse: reported as a dataset contrast, because the thinning
  matches the NEON lead at native density and not below it.
- Geography: oak woodland and conifer sites in California and Washington plus
  the boreal control. No eastern broadleaf site; stated as scope.
- A generous 4 m tolerance: the tolerance grid and the jitter bands on five
  sites for every arm; the radius shifts the board without reordering its
  top.
- Settings tuned on evaluation plots: the configuration provenance record and
  the California against Washington split.
- Temporal gap: the exact-2021 cut on 44 plots, where ForestFormer3D's lead
  disappears, is reported beside the headline.
- Training leakage: DeepForest's annotations include SJER and TEAK; its rows
  say so, and it is an RGB context arm, not a headline one.
- Proxy masks: validated on FGI-EMIT and kept to the supplement as a ranking.
- Small SJER sample: six plots and 57 stems, reported with its intervals and
  not interpreted alone.
- Integration errors: the positive control and the run manifests; the two
  defects found are reported.

## Timeline

Every pre-submission step is complete except the Zenodo deposit, which takes
a day once the final archive is approved. Writing needs four to six weeks.

## Spin-offs

- Methods paper for Methods in Ecology and Evolution: reference incompleteness,
  matching rules and positional uncertainty in field-stem benchmarks.
- Short crown-delineation paper: the deep-model crown section is now complete
  on five sites.
