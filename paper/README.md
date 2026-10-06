# Paper draft

This folder holds the draft of the benchmark paper described in the [paper
proposal](../docs/paper-proposal.md), written on 6 October 2026 from the
committed study reports.

- [manuscript.md](manuscript.md): the main text, with seven tables and seven
  figures.
- [supplement.md](supplement.md): supplementary tables and the studies the main
  text only summarises.
- [figures](figures/): copies of the seven figures drawn by
  `scripts/paper_figures.R`.

## Status

The draft is complete in content and is not yet formatted for a journal. Before
submission:

- Complete the author list, affiliations, the corresponding author's address and
  e-mail, the CRediT statement, the declaration of competing interest and the
  funding statement.
- Confirm the journal's limits: the abstract has 250 words, the highlights at
  most 84 characters each and the keyword list seven entries.
- Re-stage the archive from this branch, because the chance-agreement null, the
  leave-out rank correlations and the figures were added after the last
  clean-container rebuild; then deposit it and replace "DOI to be assigned at
  deposit" in the availability statement.
- Check once more for released SegmentAnyTreeV2 weights; none were public on 6
  October 2026.
- Convert to the journal's template and generate the reference list.

## Where the numbers come from

Every number in the manuscript is quoted from a committed report or from the
generated tables that report documents. The archive rebuilds those tables with
`scripts/reproduce_paper_tables.sh`.

| Manuscript section | Source |
| --- | --- |
| 1, 2 Introduction and related work | [paper proposal](../docs/paper-proposal.md), which records the literature scan and the dates of the weight checks |
| 3.1–3.3 Sites, reference, clips and the ladder | [frozen clips](../results/frozen-clips-results.md), [Pacific Northwest preflight](../results/pacific-northwest-extension-results.md), [QL2 rung declaration](../docs/ql2-rung-declaration.md), [master tables](../results/master-tables-results.md) |
| 3.4, 5.6 Decimation checks | [native sparse epochs](../results/native-sparse-epoch-results.md), [native 3DEP cross-check](../results/native-ql2-crosscheck-results.md) |
| 3.5, 4.9, 5.7 Dense-domain control | [native pipeline](../results/final-ensemble-pipeline-results.md), [FGI-EMIT thinning](../results/fgiemit-thinning-results.md), [transfer audit](../results/frozen-transfer-audit-results.md), [checkpoint overlap](../results/fgiemit-checkpoint-overlap-results.md), [model comparison](../results/model-benchmark-results.md) |
| 4.1 Detectors, 5.9 Compute cost | [detector table](../results/detector-table.md), [compute cost](../results/compute-cost-results.md) |
| 4.2, 5.1–5.4, 5.8 Chance agreement | [matcher robustness](../results/matcher-robustness-results.md#chance-agreement) |
| 4.3, 5.5 Reference completeness | [censused subplots](../results/census-support-results.md), [coverage gap](../results/coverage-gap-results.md) |
| 4.6, 5.3 Regions | [configuration provenance](../docs/configuration-provenance.md), [master tables](../results/master-tables-results.md), [density ladder](../results/density-ladder-sweep-results.md) |
| 4.5, 5.1, 5.2, 5.4 Accuracy, density, rank stability, crown classes | [master tables](../results/master-tables-results.md), [model comparison](../results/model-benchmark-results.md) |
| 4.10 Implementation and reproducibility | [reproduction archive](../docs/reproduction-archive.md) |
| 5.8 Sensitivity | [matcher robustness](../results/matcher-robustness-results.md), [positional uncertainty](../results/positional-uncertainty-results.md), [temporal sensitivity](../results/temporal-sensitivity-results.md), [calibration/validation](../results/calibration-validation-results.md) |
| Supplement S1, S3, S13 | [master tables](../results/master-tables-results.md) |
| Supplement S2 | [model comparison](../results/model-benchmark-results.md) |
| Supplement S4, S5 | [censused subplots](../results/census-support-results.md), [coverage gap](../results/coverage-gap-results.md) |
| Supplement S6–S8 | [fusion](../results/detector-fusion-results.md), [crown benchmark](../results/crown-segmentation-results.md), [instance IoU](../results/instance-iou-pq-results.md), [proxy validation](../results/fgiemit-proxy-validation-results.md) |
| Supplement S9–S11 | [calibration/validation](../results/calibration-validation-results.md), [master tables](../results/master-tables-results.md), [configuration provenance](../docs/configuration-provenance.md), [detector table](../results/detector-table.md) |
| Supplement S12 | [matcher robustness](../results/matcher-robustness-results.md#chance-agreement) |

Table 1's crown-class counts and stem heights come from `figure_1.csv`, the data
file of Figure 1.

## Conventions

- Density is measured first-return pulse density, in pulses/m². Rungs are named
  in the reports by their all-return decimation target (8, 4, 3.2, 2 and 1
  points/m²); the manuscript gives their medians over the 106 plots (4.7, 2.5,
  2.0, 1.3 and 0.6 pulses/m²).
- Square brackets hold 95% plot-bootstrap intervals unless a sentence says
  otherwise.
- The nominal plot core on all 106 plots is the headline; censused subplots are
  the reference-completeness bracket.
- Corrected F1 is (F1 − null F1) / (1 − null F1), where the null scores randomly
  shifted copies of each detector's detections; a corrected lead is a difference
  of corrected F1.

## Figures

The figures are drawn from the master tables and study outputs, and each has a
data file with the numbers it plots:

```sh
CLAUDE_JOB_DIR=/path/to/paper_runs Rscript scripts/paper_figures.R
cp /path/to/paper_runs/figures/figure_[1-7].png paper/figures/
```

## Building a formatted copy

Citations use pandoc syntax with the keys of
[references.bib](../docs/references.bib):

```sh
pandoc paper/manuscript.md --citeproc --bibliography docs/references.bib \
  --resource-path paper -o manuscript.pdf
```
