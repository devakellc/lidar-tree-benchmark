# Paper draft

This folder holds the draft of the benchmark paper described in the [paper
proposal](../docs/paper-proposal.md), written on 6 October 2026 from the
committed study reports, extended on 20 October 2026 with the ForestMamba run
(now Section S23 of the supplement) and restructured for IEEE JSTARS on
22 October 2026.

- [manuscript.md](manuscript.md): the main text, with eight tables and seven
  figures.
- [supplement.md](supplement.md): supplementary tables and figures and the
  studies the main text only summarises (Sections S1 to S25).
- [figures](figures/): the nine figures drawn by `scripts/paper_figures.R`,
  seven for the manuscript and two for the supplement, each as a PNG for the
  markdown and a vector PDF for LaTeX; [figures/data](figures/data/README.md)
  holds the public-domain Natural Earth extract of the site map.
- [ieee](ieee/README.md): the LaTeX version for IEEE JSTARS, generated from
  these files by `scripts/paper_to_ieee.py` for editing on Overleaf.

## Status

The draft is complete in content and follows a review of JSTARS's record
(length, density of the text, missing standard figures, framing as research
questions). It answers four research questions and contributes a
density-routed detection pipeline, a decision table of which detector to run at
each USGS quality level with or without a GPU. The pipeline was designed after
the five-site results were known and is labelled post hoc throughout. The main
text has about 9,800 words of prose and the IEEE version 19 pages, the body
ending on page 17. The [IEEE version](ieee/README.md) uses JSTARS's template,
replaces the highlights and keywords with Index Terms, lays out every table for
the column width, generates the numbered reference list in IEEE style and puts
the AI-use statement, which names the system, the sections and the level of
use, in the Acknowledgment. Before submission:

- Complete the IEEE author block: affiliations, e-mail and the funding
  footnote. JSTARS also asks for a brief biography and a photograph of each
  author and an ORCID to submit. IEEE takes the declaration of competing
  interest in the submission form and prints no CRediT statement; the markdown
  keeps both for other journals.
- Read and revise the whole text: the AI-use statement says that every section
  was drafted with Claude Code and revised by the author.
- If the journal or a reviewer asks for 18 pages or fewer, cut Section 4 first;
  it is the section most over its budget.
- Confirm JSTARS's limits at submission, including the abstract length (226
  words) and the six Index Terms.
- Re-run the repository checks of Section 2.3 and Section S24 on submission
  day and restate their date: SegmentAnyTreeV2, SelectAnyTree, ForestQuery,
  ForPT's instance checkpoint and ITS-Net's checkpoint were all absent on
  21 October 2026.
- Re-stage the archive from this branch, because the chance-agreement null and
  its seed and minimum-shift checks, the leave-out and corrected-F1 rank
  correlations, the unsmoothed-baseline sensitivity, the instance audit, the
  density routing and the redrawn figures were added after the last
  clean-container rebuild; then deposit it and replace "DOI to be assigned at
  deposit" in the availability statement.
- Decide whether the re-staged archive carries the ForestMamba runs of Section
  S23. They are not in the staged archive and the one-command rebuild does not
  cover them, as Section S23 and the availability statement say, and neither
  `docs/model-provenance.json` nor the models table of
  `docs/data-code-availability.md` records the ForestMamba checkpoint. If the
  runs go in, drop those sentences, add the checkpoint to the provenance
  records, and drop the availability statement's clause that the repository
  lists ForestMamba's sources and hashes, because `scripts/stage_archive.sh`
  copies `docs/model-provenance.json` into the archive, which would then list
  them too.
- ForestMamba stays outside the result tables, figures, abstract counts and
  density routing by design, and Section S23 says so: adding it to Table 4 or
  Figure 4 would re-open the rank statistics of Sections 4.4 and 5.2, which are
  stated for eight detectors. Only Table S15 carries its settings.
- After re-staging and the clean-container rebuild, replace the 1,221 rebuilt
  files of Section 4.8 (and the counts in docs/reproduction-archive.md) with
  the new rebuild's count, and drop the sentence on the earlier staging.
- If a preprint is posted, add IEEE's notice to it at submission: "This work
  has been submitted to the IEEE for possible publication. Copyright may be
  transferred without notice, after which this version may no longer be
  accessible."
- The supplement is numbered in topical order, not in order of first citation;
  renumber if the journal asks.
- Replace the supplement's `Source:` links to repository reports with citations
  of the archived reports in the deposit.
- Once editing moves to Overleaf, carry any content change back to the markdown
  or record that the Overleaf project has become the source.

## Where the numbers come from

Every number in the manuscript is quoted from a committed report or from the
generated tables that report documents. The archive rebuilds those tables with
`scripts/reproduce_paper_tables.sh`.

| Manuscript section | Source |
| --- | --- |
| 1, 2 Introduction and related work | [paper proposal](../docs/paper-proposal.md), which records the literature scan and the dates of the weight checks |
| 3.1–3.3 Sites, reference, evaluation clips and density levels | [frozen clips](../results/frozen-clips-results.md), [Pacific Northwest preflight](../results/pacific-northwest-extension-results.md), [QL2 rung declaration](../docs/ql2-rung-declaration.md), [master tables](../results/master-tables-results.md) |
| 3.4, 4.6, 5.6 Decimation checks | [native sparse epochs](../results/native-sparse-epoch-results.md), [native 3DEP cross-check](../results/native-ql2-crosscheck-results.md) |
| 3.5, 4.6, 5.7 Dense-domain control | [native pipeline](../results/final-ensemble-pipeline-results.md), [FGI-EMIT thinning](../results/fgiemit-thinning-results.md), [transfer audit](../results/frozen-transfer-audit-results.md), [checkpoint overlap](../results/fgiemit-checkpoint-overlap-results.md), [model comparison](../results/model-benchmark-results.md) |
| 4.1 Detectors, with the compute column of Table 2 | [detector table](../results/detector-table.md), [compute cost](../results/compute-cost-results.md) |
| 4.2, 5.1–5.4 Chance agreement | [matcher robustness](../results/matcher-robustness-results.md#chance-agreement) |
| 4.1, 5.2, 6.1, 6.4 Baseline smoothing sensitivity | [baseline smoothing sensitivity](../results/baseline-smoothing-sensitivity-results.md) |
| 3.1, 4.1, 6.2 Stands, apex floor, dead stems, instance assignment | [instance audit](../results/instance-audit-results.md) |
| 4.3, 5.5 Reference completeness | [censused subplots](../results/census-support-results.md), [coverage gap](../results/coverage-gap-results.md) |
| 4.5, 5.3 Regions | [configuration provenance](../docs/configuration-provenance.md), [master tables](../results/master-tables-results.md), [density ladder](../results/density-ladder-sweep-results.md) |
| 4.4, 5.1, 5.2, 5.4 Accuracy, density, rank stability, crown classes | [master tables](../results/master-tables-results.md), [model comparison](../results/model-benchmark-results.md) |
| 4.7, 5.8, 6.1, 7 and Table 7 Density-routed pipeline | [density routing](../results/density-routing-results.md) |
| 4.8 Implementation and reproducibility | [reproduction archive](../docs/reproduction-archive.md) |
| 4.4, 4.6, 5.1 Uncertainty and sensitivity | [matcher robustness](../results/matcher-robustness-results.md), [positional uncertainty](../results/positional-uncertainty-results.md), [temporal sensitivity](../results/temporal-sensitivity-results.md), [calibration/validation](../results/calibration-validation-results.md) |
| 6, 7 Discussion and conclusion; Table 8 | the reports of the sections they summarise |
| 2.3, 6.4 and the availability statement: ForestMamba, added after the tables were fixed | [ForestMamba benchmark](../results/forestmamba-results.md), [ForestMamba runtime](../gpu/forestmamba-sm120/README.md) |
| 2.1–2.3, 4.2, 6.3: the dated repository checks and the precedents added on 21 October 2026 (Yu 2004, Hirata 2004, Hamraz 2016, Hershey 2022, Destouches 2026, Gominski 2025, ForestQuery, and the chance-null, double-observer, leakage, rank-stability and model-transferability lineages) | the cited sources; the [paper proposal](../docs/paper-proposal.md) records the repository checks and Yu 2004 |
| Supplement S1, S3, S13, S17 | [master tables](../results/master-tables-results.md) |
| Supplement S2, S19 | [model comparison](../results/model-benchmark-results.md), [master tables](../results/master-tables-results.md), [configuration provenance](../docs/configuration-provenance.md) |
| Supplement S4, S5, S20 | [censused subplots](../results/census-support-results.md), [coverage gap](../results/coverage-gap-results.md) |
| Supplement S6–S8 | [fusion](../results/detector-fusion-results.md), [crown benchmark](../results/crown-segmentation-results.md), [instance IoU](../results/instance-iou-pq-results.md), [proxy validation](../results/fgiemit-proxy-validation-results.md) |
| Supplement S9–S11 | [calibration/validation](../results/calibration-validation-results.md), [master tables](../results/master-tables-results.md), [configuration provenance](../docs/configuration-provenance.md), [detector table](../results/detector-table.md) |
| Supplement S12 | [matcher robustness](../results/matcher-robustness-results.md#chance-agreement) |
| Supplement S14, S18 | [instance audit](../results/instance-audit-results.md) |
| Supplement S15 | [detector table](../results/detector-table.md), [configuration provenance](../docs/configuration-provenance.md) |
| Supplement S16 | [baseline smoothing sensitivity](../results/baseline-smoothing-sensitivity-results.md) |
| Supplement S21 | [matcher robustness](../results/matcher-robustness-results.md), [positional uncertainty](../results/positional-uncertainty-results.md), [temporal sensitivity](../results/temporal-sensitivity-results.md), [calibration/validation](../results/calibration-validation-results.md) |
| Supplement S22 | [compute cost](../results/compute-cost-results.md) |
| Supplement S23 | [ForestMamba benchmark](../results/forestmamba-results.md) |
| Supplement S24 | [paper proposal](../docs/paper-proposal.md) |
| Supplement S25 | [density routing](../results/density-routing-results.md) |

Table 1's crown-class counts and stem heights come from `figure_1.csv`, the data
file of Figure 1; Figure 7's per-panel recall and precision come from
`figure_7.csv`, which the figure script checks against the per-cell counts of
the chance-agreement study.

## Conventions

- Density is measured first-return pulse density, in pulses/m². The paper
  calls the thinned densities density levels; the reports call them rungs and
  name them by their all-return decimation target (8, 4, 3.2, 2 and 1
  points/m²). The manuscript gives their medians over the 106 plots (4.7, 2.5,
  2.0, 1.3 and 0.6 pulses/m²).
- Square brackets hold 95% plot-bootstrap intervals unless a sentence says
  otherwise.
- The nominal plot core on all 106 plots carries the main tables; censused
  subplots are the reference-completeness bracket.
- Corrected F1 is (F1 − null F1) / (1 − null F1), where the null scores randomly
  shifted copies of each detector's detections; a corrected lead is a
  difference of corrected F1.
- "Marginal" (in the reports, "weak") marks a contrast whose 95% interval
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
