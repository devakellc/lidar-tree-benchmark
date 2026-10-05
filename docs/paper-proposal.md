# Paper proposal: tree detectors on national-mapping airborne LiDAR

Prepared 2026-09-30 from the committed study reports and a literature scan of
about ninety primary sources. This document records which part of the
repository is proposed for a peer-reviewed paper, the outline of that paper,
and the work that must be completed before submission. Task tracking lives in
the GitHub issues labelled `pre-paper`; this document stays free of tracker
identifiers.

## Recommendation

The strongest paper is the NEON three-site density-ladder benchmark: zero-shot
deep 3D tree segmenters against classical detectors on national-mapping-density
airborne laser scanning (ALS), scored against field-mapped stems, with the
native FGI-EMIT work as a dense-domain control. The literature scan found no
published evaluation of SegmentAnyTree or ForestFormer3D on 1 to 8 pulses/m²
native ALS with field stems, and no test of whether decimation predicts native
sparse behaviour. The repository already contains both.

Two corrections are required before any number is quoted. The NEON
ForestFormer3D and TreeisoNet results predate the adapter defects documented in
the [frozen transfer audit](../results/frozen-transfer-audit-results.md), and
precision is currently computed over partly censused plots, as recorded in the
[reference-support audit](../results/neon-reference-support-results.md).

## What is publishable

| Candidate | Evidence in the repository | Novelty against the literature | Verdict |
| --- | --- | --- | --- |
| Density-ladder cross-model benchmark | 46 plots, 699 stems, three canopy structures, seven full-ladder arms plus ForestFormer3D, Li 2012 and Treeiso | Closest prior work is FGI-EMIT: one boreal site subsampled from above 1,000 pts/m². Nothing at 1 to 8 pulses/m² with field stems | Primary paper |
| Evaluation sensitivity kit | apex versus mask scoring, matcher and tolerance grid, stem-jitter bands, temporal gap, coverage-gap crediting, checkpoint provenance | No forestry greedy-versus-Hungarian comparison, no checkpoint leakage audit, no published critique of NEON stems as ground truth | Section of the primary paper, plus a methods spin-off |
| Crown delineation | stop rule matters more than algorithm; crown width stable to 1 pt/m²; height, not width, predicts DBH | Moderate | Second short paper once deep-model crowns are regenerated |
| FGI-EMIT preregistered comparison | frozen policy, development/reserve split, bootstrap intervals | One site, within-dataset, checkpoint overlap unknown; the dataset authors already published trained-from-scratch comparisons | Control experiment inside the primary paper |
| Fusion, routing, calibration, RGB | union trades F1 for recall; learned router gains nothing over a fixed default; calibration gains small | Sparse prior art, but effects are small or negative | Supplement and one discussion paragraph |
| TEAK canopy boxes, eastern preflight, EPT throughput, SAM2Point, engine comparison | blocked or engineering-only | none | Excluded; one methods sentence at most |

## Recommended paper

**Working title.** Native-density performance does not predict sparse-density
performance: benchmarking classical and zero-shot deep tree detectors on
national-mapping airborne LiDAR with field-mapped stems.

**Venue.** ISPRS Journal of Photogrammetry and Remote Sensing first, where
FGI-EMIT and ITS-Net appeared in 2026. Remote Sensing of Environment is the
alternative. IJAEOG or Remote Sensing are fallbacks.

**Thesis.** Forest structure sets the level of detection accuracy and point
density sets the slope. The slope differs by method family: deep segmenters
trained on dense ULS win at native density but collapse below roughly
3 pulses/m², where multi-layer CHM detectors are flat.

**Contributions**, in the order of the results section:

1. Equal-support benchmark of three zero-shot 3D instance segmenters and five
   classical detectors on sparse ALS across three canopy structures, pooled by
   counts and stratified by field crown class.
2. Density-by-structure decomposition, with site-invariant response shapes and
   the understory occlusion floor.
3. The density cliff and crossover map: which detector wins at which density,
   out of sample.
4. Decimation validated cross-sensor against native USGS 3DEP surveys over the
   same plots.
5. Apex versus mask scoring: apex matching overstates instance quality two to
   three fold, and the two leaderboards only moderately agree.
6. Evaluation sensitivity: matching rule, tolerance, stem-position jitter,
   temporal gap, and reference-completeness crediting.
7. Dense-domain control: the same checkpoints and adapters reach
   published-level accuracy on FGI-EMIT, so the sparse-ALS collapse is a domain
   effect, not an integration failure. The checkpoint provenance audit is
   reported alongside.
8. Open harness with frozen seeded clips, pinned checkpoints and hash receipts.

## Evidence available today

| Result | Value | Report |
| --- | --- | --- |
| SegmentAnyTree F1, SOAP, native vs 1 pt/m² | 0.48 vs 0.13 | [model benchmark](../results/model-benchmark-results.md) |
| multichm F1 across the ladder, SOAP | 0.42 to 0.47 | [model benchmark](../results/model-benchmark-results.md) |
| CHM-VWF F1 across the ladder, SOAP | 0.38 to 0.40 | [model benchmark](../results/model-benchmark-results.md) |
| Overstory recall SJER / SOAP / TEAK, native density | 0.71 / 0.57 / 0.40 | [density ladder](../results/density-ladder-sweep-results.md) |
| Best classical understory recall, native, 105 stems | 0.26 | [point-cloud detectors](../results/pointcloud-detector-results.md) |
| Decimated vs native-sensor pooled recall gap | within 0.07; dominant class 0.06 to 0.12 optimistic | [native 3DEP cross-check](../results/native-ql2-crosscheck-results.md) |
| multichm beats CHM-VWF on held-out plots, SOAP / TEAK | 100% / 96% of seed-by-rung splits | [calibration/validation](../results/calibration-validation-results.md) |
| SegmentAnyTree recall, apex matching vs IoU ≥ 0.5 masks | 0.66 vs 0.21 | [instance IoU/PQ](../results/instance-iou-pq-results.md) |
| Kendall τ between distance and mask leaderboards | 0.47 to 0.73 | [instance IoU/PQ](../results/instance-iou-pq-results.md) |
| F1 across the matching-tolerance grid | 0.21 to 0.42 | [matcher robustness](../results/matcher-robustness-results.md) |
| CHM-VWF false positives with no mapped stem nearby | 94% | [matcher robustness](../results/matcher-robustness-results.md) |
| Monte-Carlo F1 band width under stem-position jitter | 0.014 to 0.037 | [positional uncertainty](../results/positional-uncertainty-results.md) |
| F1 gain after co-detection crediting | +0.04 to +0.22 | [coverage gap](../results/coverage-gap-results.md) |
| ForestFormer3D apex F1, FGI-EMIT reserve vs NEON native, old adapter | 0.78 vs 0.25 to 0.30 | [native pipeline](../results/final-ensemble-pipeline-results.md), [model benchmark](../results/model-benchmark-results.md) |
| Crown diameter RMSE, random walker with stop rule | 2.42 m, flat to 1 pt/m² | [crown benchmark](../results/crown-segmentation-results.md) |

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
None reports 1 to 8 pulses/m² performance. USGS 3DEP quality levels frame the
target regime: QL2 requires at least 2 pulses/m² and QL1 at least 8
([USGS](https://www.usgs.gov/3d-elevation-program/topographic-data-quality-levels-qls)).

## Proposed structure

1. Introduction: national-mapping ALS as the deployment regime, the density
   gap between the classical and deep literatures, and the three practical
   questions the README asks.
2. Related work: benchmarks, density studies, understory detection, evaluation
   conventions, and detector fusion.
3. Data: sites, plots and stems by crown class with measured pulse densities;
   the decimation ladder; the native 3DEP cross-check clouds; the FGI-EMIT
   control plots.
4. Methods: the detector table with type, input, training data and checkpoint
   hash; the density-first CHM pipeline; matching, pooling and the equal-set
   guard; calibration and validation splits; uncertainty.
5. Results, one subsection per contribution.
6. Discussion: implications for USGS 3DEP users, why dense-trained segmenters
   collapse, the occlusion floor, what fusion and routing buy, limitations.
7. Conclusion, data and code availability.

Figures:

- Figure 1: site and canopy-structure overview.
- Figure 2: F1, recall and precision versus pulse density, three sites by all
  arms.
- Figure 3: overstory and understory recall versus density.
- Figure 4: native-sensor versus decimated recall by crown class.
- Figure 5: distance F1 against mask PQ per arm.
- Figure 6: sensitivity panel with tolerance grid, matcher variants, jitter
  bands and credited F1.
- Figure 7: FGI-EMIT development and reserve F1 for the same checkpoints.

Tables:

- Table 1: sites, plots, stems by crown class, measured pulse densities.
- Table 2: detectors with type, input, training data and checkpoint hash.
- Table 3: master ladder table with plot-level bootstrap intervals.
- Table 4: held-out results.
- Table 5: compute cost per plot; ForestFormer3D takes minutes per plot on an
  RTX 5090 while the CHM path takes seconds.

Fusion Pareto, routing, calibration, RGB, crown diameters, allometry and the
temporal check go to the supplement.

## Work before submission

The order below is the execution order, revised on 2026-09-30 so that the
plot population is decided and frozen before any arm re-runs. Each step is
tracked as a GitHub issue labelled `pre-paper`.

1. **Decide on and prepare NEON WREF and ABBY.** Both Washington sites have
   2021 LiDAR in the same tile-size class as SOAP, census bouts in 2021 and
   2022, and about 1,150 and 840 live mapped stems with DBH of at least 10 cm
   in 63 plots above the six-stem gate. The decision is cheap: one tile header
   per site, the ground-truth build and a crown-class coverage check. If it is
   a go, the extension roughly quadruples the field-stem reference, adds a
   second region and two canopy structures, and every later step runs over
   five sites. The same census-footprint audit applies.
2. **Freeze the plot population and the frozen clips.** Decide on the six-stem
   gate, which admits 40 small plots holding 88 core stems, and put every arm,
   including the CHM-VWF ladder, on the seeded frozen-clip provider before any
   arm re-runs.
3. **Re-run ForestFormer3D and TreeisoNet with the corrected adapters** on
   every admitted site. The
   [scene-assembly study](../results/forestformer-scene-assembly-results.md)
   and the [transfer audit](../results/frozen-transfer-audit-results.md) show
   the old cylinder route and export defects; the June NEON runs predate both
   fixes. Extend ForestFormer3D to the full ladder if compute allows.
4. **Add SegmentAnyTreeV2 as an arm** on every admitted site. Released June
   2026 and trained at 10 to 50,000 pts/m²; reviewers will ask for it. ITS-Net
   or ForPT are optional if weights are public.
5. **Compute precision only inside censused subplots**, for every site and
   alongside steps 3 and 4. Apply the event-specific census-support tooling
   from the [reference-support protocol](neon-reference-support-protocol.md)
   to the 2021 events. Report credited F1 from the
   [coverage-gap study](../results/coverage-gap-results.md) as a bracket with
   its sensitivity grid.
6. **Native sparse validation.** NEON's 2017 and 2018 SOAP and TEAK flights
   have classified tiles about a third the size of the 2021 tiles, consistent
   with the 4 to 6 pts/m² Gemini era. Pair them with the 2015 tower census,
   which holds 291 SOAP and 499 TEAK stems never remeasured, under a declared
   policy for those stems, and compare with the decimated 2021 rungs at
   matched first-return density. Check whether NeonTreeEvaluation's
   hand-annotated crowns cover any of the 46 plots, which would give a
   complete crown reference for precision.
7. **Fill or drop pending items.** The SegmentAnyTree and ForestFormer3D
   crown-diameter section is marked pending in the
   [crown benchmark](../results/crown-segmentation-results.md); the seven-arm
   cross-site fusion is unfinished in the
   [fusion study](../results/detector-fusion-results.md).
8. **Master tables, reference-population table and bootstrap intervals.**
   Publish one reference-population table with exclusions and add paired
   plot-level bootstrap intervals to every headline table, reusing the
   FGI-EMIT bootstrap code.
9. **Publication hygiene.** Add a LICENSE on day one; archive frozen clips,
   stems, checkpoint hashes and result CSVs on Zenodo with a one-command
   reproduction as the last step; rebuild the bibliography, since the
   [deep-research report](deep-research-report.md) has unresolved citation
   placeholders; use pulses/m² on every density axis.
10. **Optional: leave-one-site-out fine-tuning of SegmentAnyTree** with
    sparsification augmentation, to pre-empt the objection that zero-shot
    evaluation is unfair to learned models.

## Reference-count check

Checked on 2026-09-30 against the tracked GeoJSON and the NEON data API. The
D17 ground truth holds 864 live, mapped stems measured within four years of
2021, and the 46 swept plots use 699 of them; the unswept plots hold one to
five stems each. Tile sizes below are a density proxy from the classified
point-cloud listings and need one header check per site.

| Lever | Live mapped stems added | Cost | Caveat |
| --- | --- | --- | --- |
| Relax the six-stem plot gate in D17 | 88 core stems in 40 plots | Trivial | Marginal gain, more tiny plots |
| Add NEON WREF and ABBY | about 1,150 and 840 stems in 63 plots; 2021 tiles 161 and 145 MB against SOAP's 165 MB | Two sites through the full ladder | Same census-footprint audit as D17 |
| 2017 or 2018 epoch at SOAP and TEAK with the 2015 census | 291 and 499 stems last seen alive in 2015; tiles 50 to 70 MB against 157 to 165 MB in 2021 | Old tiles, all arms at native sparse density | Fate after 2015 unknown; needs a declared policy |
| Standing-dead stems as a stratum | 291 with a measurement within four years | Scoring only | Different target; supplementary |

NEON per-plot census records list 800 m² sampled in tower plots and 400 m² in
distributed plots in every year checked, at D17 and at WREF and ABBY alike. No
plot is a complete census, so precision inside sampled subplots stays
necessary whichever way the reference grows.

## Reviewer risks and mitigations

- Zero-shot unfairness: the dense-domain control and the optional fine-tuning.
- Incomplete stems: censused subplots, credited F1 and a crown reference.
- Decimation versus native: the cross-sensor check and the pre-2021 flights.
- One region: three canopy structures plus the boreal control, stated as scope;
  the WREF and ABBY extension adds a second region.
- A generous 4 m tolerance: the tolerance grid and the jitter bands.
- Modest stem count against FGI-EMIT's 1,561 trees: the D17 pool is exhausted,
  so extend to WREF and ABBY and, optionally, add the 2018 epoch at SOAP and
  TEAK, as in the reference-count check above.

## Timeline

Reruns and SegmentAnyTreeV2 need three to four weeks of GPU and wall time.
Reference support and intervals need about two weeks. The WREF and ABBY
extension adds roughly three to four weeks of acquisition and compute. Writing
needs four to six weeks. Submission in about four months is realistic with the
extension, three without.

## Spin-offs

- Methods paper for Methods in Ecology and Evolution: reference incompleteness,
  matching rules and positional uncertainty in field-stem benchmarks.
- Short crown-delineation paper once the deep-model crown section is complete.
