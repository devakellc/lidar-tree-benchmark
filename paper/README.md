# Paper draft

This folder holds the draft of the benchmark paper described in the [paper
proposal](../docs/paper-proposal.md), written on 6 October 2026 from the
committed study reports, extended on 20 October 2026 with the ForestMamba run
(now Section S23 of the supplement), restructured for IEEE JSTARS on 22 October
2026 and revised on 17 November 2026 after a pre-submission review.

- [manuscript.md](manuscript.md): the main text, with eight tables and seven
  figures.
- [supplement.md](supplement.md): supplementary tables and figures and the
  studies the main text only summarises (Sections S1 to S28).
- [figures](figures/): the nine figures drawn by `scripts/paper_figures.R`,
  seven for the manuscript and two for the supplement, each as a PNG for the
  markdown and a vector PDF for LaTeX; [figures/data](figures/data/README.md)
  holds the public-domain Natural Earth extract of the site map.
- [ieee](ieee/README.md): the LaTeX version for IEEE JSTARS, generated from
  these files by `scripts/paper_to_ieee.py` for editing on Overleaf.

## Status

The draft is complete in content and follows a review of JSTARS's record
(length, density of the text, missing standard figures, framing as research
questions). It answers four research questions. The fourth, which detector to
run at each USGS quality level with or without a GPU, is answered as guidance
in the discussion, from a decision table that was designed after the five-site
results were known and is labelled post hoc throughout. Until 18 November 2026
that table was presented as a contribution, a density-routed detection
pipeline; it was demoted because its picks do not separate from their
runners-up, the pick between the QL2 and QL1 floors changes with the
definition of density, and ForestFormer3D run at every density does as well.
Its method, results and table moved to Section S25 of the supplement, Figure 2
lost its second row, and the example-plot figure moved to Section 6.2.

The revision of 17 November 2026 followed a pre-submission review. It names
the density levels by the density inside the scored plot cores, scores the
chance null inside censused subplots as well, adds the QL2 level and the null
to the baseline without its smoothing, re-bands the density routing by core
density, removes noise-class and withheld points from the 3DEP clouds, audits
the reference records and the fires at SOAP, tests the chance correction on
simulated plots (which showed that it can err either way, so that corrected
scores are no longer called conservative), and corrects citations and detector
settings. On 18 November 2026 a count of split crowns in the benchmark's
detections was added (Section S28): the segmenters split crowns at about half
the simulated rate or less, enough for part of their corrected recall lead.
With the routing moved to the supplement, the main text now has about 11,200
words of prose (9,200 before the revision) and the IEEE version 20 pages, the
body ending on page 18 (18 and 16 before); the IEEE supplement has 29 pages
(19 before).

The [IEEE version](ieee/README.md) uses JSTARS's template, replaces the
highlights and keywords with Index Terms, lays out every table for the column
width, generates the numbered reference list in IEEE style and puts the AI-use
statement, which names the system, the sections and the level of use, in the
Acknowledgment. Before submission:

- Complete the IEEE author block: affiliations, e-mail and the funding footnote
  (the ORCID iD is in). JSTARS also asks for a brief biography and a photograph
  of each author. IEEE takes the declaration of competing interest in the
  submission form and prints no CRediT statement; the markdown keeps both for
  other journals.
- Read and revise the whole text: the AI-use statement says that every section
  was drafted with Claude Code and revised by the author.
- Check the length. JSTARS's information for authors, read on 17 November 2026,
  states no page limit and no overlength charge, and asks for an abstract of 150
  to 250 words (the abstract has 237). If a shorter paper is wanted, cut Section
  4, the section most over its budget. Confirm the limits and the six Index
  Terms at submission.
- Re-run the repository checks of Section 2.3 and Section S24 on submission day
  and restate their date: SegmentAnyTreeV2, SelectAnyTree, ForestQuery, ForPT's
  instance checkpoint and ITS-Net's checkpoint were all absent on 16 November
  2026, and a public repository of code and results that overlaps the paper's
  design, whose only commit is dated 11 November 2026, came to notice then
  (Section S24).
- Re-stage the archive from this branch and rebuild it in the clean container:
  the [archive guide](../docs/reproduction-archive.md) lists the analyses added
  since the clean-container rebuild of October. A test rebuild of a staged copy
  on the development machine (17 November 2026) found six differing files; after
  they were put right, a second test the same evening rebuilt 1,483 files with
  none differing. The rebuild in the clean container is still to run. Run
  `scripts/paper_figures.R` with its default output folder first, which removes
  the old Figure 2's data file from `paper_runs/figures`. Then deposit the
  archive and replace "DOI to be assigned at deposit" in the availability
  statement.

Two analyses that the pre-submission review suggested were not run: a repeat run
of ForestFormer3D at native density, which would measure the run-to-run spread
that Table 7 of the manuscript lists as untested (about six GPU-hours), and
thinning by whole pulses against the thinning by returns used here (Section
3.3), at the two sparsest levels.

## Where the numbers come from

Every number in the manuscript is quoted from a committed report or from the
generated tables that report documents. The archive rebuilds those tables with
`scripts/reproduce_paper_tables.sh`.

| Manuscript section | Source |
| --- | --- |
| 1, 2 Introduction and related work | [paper proposal](../docs/paper-proposal.md), which records the literature scan and the dates of the weight checks |
| 3.1–3.3 Sites, reference, evaluation clips and density levels | [frozen clips](../results/frozen-clips-results.md), [Pacific Northwest preflight](../results/pacific-northwest-extension-results.md), [QL2 rung declaration](../docs/ql2-rung-declaration.md), [master tables](../results/master-tables-results.md), [core density](../results/core-density-results.md) for every density and Table 1's pulse densities, [reference audit](../results/reference-population-audit-results.md) for the bole records, crown-class sources and the fire at SOAP |
| 3.4, 4.6, 5.6 Decimation checks | [native sparse epochs](../results/native-sparse-epoch-results.md), [native 3DEP cross-check](../results/native-ql2-crosscheck-results.md) |
| 3.5, 4.6, 5.7 Dense-domain control | [native pipeline](../results/final-ensemble-pipeline-results.md), [FGI-EMIT thinning](../results/fgiemit-thinning-results.md), [transfer audit](../results/frozen-transfer-audit-results.md), [checkpoint overlap](../results/fgiemit-checkpoint-overlap-results.md), [model comparison](../results/model-benchmark-results.md) |
| 4.1 Detectors, with the compute column of Table 2 | [detector table](../results/detector-table.md), [compute cost](../results/compute-cost-results.md) |
| 4.2, 5.1–5.4 Chance agreement | [matcher robustness](../results/matcher-robustness-results.md#chance-agreement); [chance-correction simulation](../results/chance-correction-simulation-results.md) for the simulated behaviour of the correction |
| 4.3, 5.1, 5.3, 5.5 and Table 5: chance agreement inside censused subplots, by plot type and without the fire plots | [censused chance agreement](../results/censused-chance-agreement-results.md) |
| 4.1, 5.2, 6.1, 6.4 Baseline smoothing sensitivity | [baseline smoothing sensitivity](../results/baseline-smoothing-sensitivity-results.md) |
| 3.1, 4.1, 6.2 Stands, apex floor, instance assignment | [instance audit](../results/instance-audit-results.md) |
| 6.2 Grouping radius check (Section S18) | [radius check](../results/segmentanytree-radius-results.md) |
| 4.3, 5.5 Reference completeness | [censused subplots](../results/census-support-results.md), [coverage gap](../results/coverage-gap-results.md) |
| 4.5, 5.3 Regions | [configuration provenance](../docs/configuration-provenance.md), [master tables](../results/master-tables-results.md), [density ladder](../results/density-ladder-sweep-results.md) |
| 4.4, 5.1, 5.2, 5.4 Accuracy, density, rank stability, crown classes | [master tables](../results/master-tables-results.md), [model comparison](../results/model-benchmark-results.md) |
| 6.1, 7 and Section S25 Choosing a detector by density (decision table) | [density routing](../results/density-routing-results.md), banded by [core density](../results/core-density-results.md) |
| 4.7 Implementation and reproducibility | [reproduction archive](../docs/reproduction-archive.md) |
| 4.4, 4.6, 5.1 Uncertainty and sensitivity | [matcher robustness](../results/matcher-robustness-results.md), [positional uncertainty](../results/positional-uncertainty-results.md), [temporal sensitivity](../results/temporal-sensitivity-results.md), [calibration/validation](../results/calibration-validation-results.md) |
| 6, 7 Discussion and conclusion; Table 7 | the reports of the sections they summarise |
| 2.3, 6.4 and the availability statement: ForestMamba, added after the tables were fixed | [ForestMamba benchmark](../results/forestmamba-results.md), [ForestMamba runtime](../gpu/forestmamba-sm120/README.md) |
| 2.1–2.3, 4.2, 6.3: the dated repository checks and the precedents added on 21 October 2026 (Yu 2004, Hirata 2004, Hamraz 2016, Hershey 2022, Destouches 2026, Gominski 2025, ForestQuery, and the chance-null, double-observer, leakage, rank-stability and model-transferability lineages) | the cited sources; the [paper proposal](../docs/paper-proposal.md) records the repository checks and Yu 2004 |
| Supplement S1, S3, S13, S17 | [master tables](../results/master-tables-results.md) |
| Supplement S2, S19 | [model comparison](../results/model-benchmark-results.md), [master tables](../results/master-tables-results.md), [matcher robustness](../results/matcher-robustness-results.md), [coverage gap](../results/coverage-gap-results.md) |
| Supplement S4, S5, S20 | [censused subplots](../results/census-support-results.md), [coverage gap](../results/coverage-gap-results.md), [master tables](../results/master-tables-results.md) |
| Supplement S6–S8 | [fusion](../results/detector-fusion-results.md), [crown benchmark](../results/crown-segmentation-results.md), [instance IoU](../results/instance-iou-pq-results.md), [proxy validation](../results/fgiemit-proxy-validation-results.md) |
| Supplement S9–S11 | [calibration/validation](../results/calibration-validation-results.md), [master tables](../results/master-tables-results.md), [configuration provenance](../docs/configuration-provenance.md), [detector table](../results/detector-table.md) |
| Supplement S12 | [matcher robustness](../results/matcher-robustness-results.md#chance-agreement); Tables S12h to S12k: [censused chance agreement](../results/censused-chance-agreement-results.md) |
| Supplement S14, S18 | [instance audit](../results/instance-audit-results.md); Tables S14b and S14c and the fire at SOAP: [reference audit](../results/reference-population-audit-results.md) |
| Supplement S15 | [detector table](../results/detector-table.md), [configuration provenance](../docs/configuration-provenance.md), [ForestMamba runtime](../gpu/forestmamba-sm120/README.md); noise points in the clips: [native 3DEP cross-check](../results/native-ql2-crosscheck-results.md) |
| Supplement S16 | [baseline smoothing sensitivity](../results/baseline-smoothing-sensitivity-results.md) |
| Supplement S21 | [matcher robustness](../results/matcher-robustness-results.md), [positional uncertainty](../results/positional-uncertainty-results.md), [temporal sensitivity](../results/temporal-sensitivity-results.md), [calibration/validation](../results/calibration-validation-results.md) |
| Supplement S22 | [compute cost](../results/compute-cost-results.md) |
| Supplement S23 | [ForestMamba benchmark](../results/forestmamba-results.md), [ForestMamba runtime](../gpu/forestmamba-sm120/README.md) |
| Supplement S24 | [paper proposal](../docs/paper-proposal.md) |
| Supplement S25 | [density routing](../results/density-routing-results.md) |
| Supplement S26 | [core density](../results/core-density-results.md) |
| Supplement S27 | [chance-correction simulation](../results/chance-correction-simulation-results.md) |
| Supplement S28 | [split-crown diagnostic](../results/split-crown-diagnostic-results.md) |

Table 1's crown-class counts and stem heights come from `figure_1.csv`, the data
file of Figure 1; Figure 7's per-panel recall and precision come from
`figure_7.csv`, which the figure script checks against the per-cell counts of
the chance-agreement study.

## Conventions

- Density is first-return pulse density, in pulses/m², measured inside the
  plot core, the area that is scored. The paper calls the thinned densities
  density levels and names them by their core medians over the 106 plots (4.4,
  2.2, 1.8, 1.1 and 0.6 pulses/m²). The reports call them rungs, name them by
  their all-return decimation target (8, 4, 3.2, 2 and 1 points/m²) and quote
  whole-clip medians (4.7, 2.5, 2.0, 1.3 and 0.6 pulses/m²), which are about
  10% higher; the [core-density study](../results/core-density-results.md)
  gives both.
- Square brackets hold 95% plot-bootstrap intervals unless a sentence says
  otherwise.
- The nominal plot core on all 106 plots carries the main tables; censused
  subplots are the reference-completeness bracket and, since the revision of
  17 November 2026, carry the chance null as well (Table 5).
- Corrected F1 is (F1 − null F1) / (1 − null F1), where the null scores randomly
  shifted copies of each detector's detections; a corrected lead is a
  difference of corrected F1.
- "Narrow" or "narrowly" (in some reports "weak"; "marginal" in drafts before
  17 November 2026, a word readers take to mean just short of significance)
  marks a contrast whose 95% interval
  excludes zero but ends within 0.01 of it.

## Figures

The figures are drawn from the master tables, the study outputs and the
persisted detections, and each but the schematic (Figure 2) has a data file
with the numbers it plots:

```sh
CLAUDE_JOB_DIR=/path/to/paper_runs Rscript scripts/paper_figures.R
cp /path/to/paper_runs/figures/figure_*.png \
  /path/to/paper_runs/figures/figure_*.pdf paper/figures/
```

## Building a formatted copy

Citations use pandoc syntax with the keys of
[references.bib](../docs/references.bib):

```sh
pandoc paper/manuscript.md --citeproc --bibliography docs/references.bib \
  --resource-path paper -o manuscript.pdf
```
