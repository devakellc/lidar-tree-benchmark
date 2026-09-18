# LiDAR Tree Benchmarks

<!-- HTML preserves the centered header and explicit image width. -->
<!-- rumdl-disable MD033 -->

<p align="center">
  <img src="assets/intelifore-promo-lidar.gif"
       alt="Animated LiDAR point-cloud forest scene"
       width="720">
</p>

<p align="center">
  <strong>Benchmarking individual-tree detection and crown delineation from
  airborne LiDAR.</strong><br>
  Classical CHM methods · Point-cloud segmentation · Deep models · RGB · Fusion
</p>

<p align="center">
  <a href="#methods-and-results">Methods &amp; results</a> ·
  <a href="#start-here">Quick start</a> ·
  <a href="#reproduce-a-workflow">Reproduce</a> ·
  <a href="#script-reference">Scripts</a>
</p>

<!-- rumdl-enable MD033 -->

---

This is a field-grounded comparison of tree-top detectors and crown
delineators: a bundled LiDAR tile for fast checks, a USGS 3DEP area of interest
for production-scale processing, field-mapped NEON stems at SJER, SOAP, and
TEAK, and manually annotated FGI-EMIT instances for external validation.

| 🌲 Tree detection | 🧩 Crown delineation | 📏 Evaluation |
| --- | --- | --- |
| CHM local maxima, point-cloud detectors, deep models, RGB, and fusion | Region growing, Dalponte, Silva, watershed, random walker, and 3-D instances | Apex matching, crown-diameter error, uncertainty, IoU, Coverage, and PQ proxy metrics |

## Methods and results

### Tree-top detection

NEON detection metrics use one-to-one matching against mapped field stems.
Historical three-site comparisons and the newer paired SOAP fusion study use
different reference populations; their scores are not directly interchangeable.
The eastern preflight also found partial tower-subplot sampling. Historical
NEON scores below are unchanged; their event-specific scoring footprints need
an audit before being treated as complete-census precision estimates. The
[event-specific support audit](results/neon-reference-support-results.md)
also identifies dendrometer-only events and unresolved reference records;
it does not regrade historical scores.

| Method family | Implementations in this repository | Headline result | Best fit |
| --- | --- | --- | --- |
| CHM local maxima | lasR and lidR variable-window filtering (CHM-VWF) | With the same CHM, the engines agree closely (Jaccard 0.95). At native density, CHM-VWF reaches F1 0.365 over 699 stems. | Transparent, reproducible baseline and large-area CHM workflows. |
| Multi-layer CHM | multichm and lmfauto | multichm reaches native F1 0.412 over the same three-site population and is the most stable LiDAR arm across sparse rungs. | A robust classical default, especially when point density is modest. |
| Point-cloud detectors | lidR point LMF, Li 2012, and lasR point local maximum | Li 2012 raises understory recall to 0.257 versus 0.200 for CHM-VWF, but pooled F1 is 0.346. | Recovering additional sub-canopy trees when precision trade-off is acceptable. |
| Point/instance models | SegmentAnyTree, TreeisoNet, ForestFormer3D, AMS3D, ptrees, and Treeiso | SegmentAnyTree is the strongest native single arm in the pooled comparison: F1 0.443 and understory recall 0.448. | High-density ALS where compute and model setup are available. |
| RGB detection | DeepForest and Detectree2 | DeepForest reaches F1 0.457 and understory recall 0.356 on the paired SOAP set of 232 core stems. Historical standalone F1 was 0.368 over 253 stems; Detectree2 scored 0.255 over its separate 147-stem set. | An optional optical complement; the different reference populations are not a paired model comparison. |
| Historical LiDAR fusion | Union, majority, layered, and k-of-N consensus | Three-site union recall reaches 0.764 and understory recall 0.600, with F1 0.349. Incomplete stem mapping complicates precision and F1. | Recall-oriented inventories with explicit precision trade-offs. |
| Paired RGB-LiDAR fusion | RGB union, agreement, calibrated voting, and non-maximum suppression | On 18 SOAP plots at 1 pt/m2, RGB union raises recall from 0.677 to 0.741 and understory recall from 0.556 to 0.578, but F1 falls from 0.414 to 0.406. | Optional sparse-rung recall support, not a universal optical-dominant routing rule. |

The [paired RGB-LiDAR study](results/rgb-lidar-fusion-results.md) covers five
density rungs on the same 232 SOAP core stems. Optical boxes and native-CHM
heights remain fixed across rungs, so this is not a wholly sparse-input test.
Weighted fusion reaches F1 0.463 at 1 pt/m2, but its raw-score control reaches
0.465; that gain cannot be attributed to calibration.

[Confidence calibration](results/confidence-calibration-results.md) now holds
out whole plots for both scaling and fitting. Native-density validation covers
5,643 detections across six arms and 46 plots; DeepForest contributes SOAP
only. Calibration reduces held-out calibration error for every arm, but does
not improve precision at every operating point or site. Its ranking recall
counts labelled detections, not unique stems after spatial fusion.

### Crown delineation

The crown benchmark compares predicted crown diameter with NEON field diameter.
Equivalent-circle diameter (d_eq) is compared with ninetyCrownDiameter, while
max-caliper diameter is compared with maxCrownDiameter. Those are different
geometric targets, so their RMSE values should not be mixed.

| Method | Crown representation | Headline result | Interpretation |
| --- | --- | --- | --- |
| Random walker with per-crown stop rule | CHM regions stopped at a fraction of seed height | Lowest pooled RMSE in the shared-seed classical test: 2.42 m for d_eq and 3.57 m for max-caliper. | Current best classical diameter fit when its Matrix-based workflow is available. |
| lasR region growing | CHM regions converted to polygons | 2.62 m d_eq RMSE and 3.72 m max-caliper RMSE over 225 matched stems. | A strong, compact, engine-native CHM baseline. |
| Dalponte and Silva | Seeded CHM segmenters | Dalponte: 2.70 m d_eq RMSE; Silva: 2.79 m. | Competitive alternatives; seed source and diameter definition matter. |
| AMS3D and ptrees | 3-D point-instance crowns | d_eq RMSE 2.97 m and 3.03 m, respectively; they match 1.4–2.1× more stems than the CHM controls. | Better sub-canopy reach, with different matched populations and a modest RMSE trade-off. |
| Li 2012 | 3-D point-cloud segments | 5.23 m d_eq RMSE and substantial positive diameter bias. | Useful for detection coverage, not the current crown-width choice. |

The [crown-segmentation results](results/crown-segmentation-results.md) include
matched-tree counts, bias, MAE, R², density sensitivity, and the full
three-dimensional comparison. Crown methods should be chosen on that crown
metric, not on the F1 of the detector that supplied their seeds.

### External instance validation

The [FGI-EMIT frozen transfer study](results/fgi-emit-external-results.md)
evaluates four existing detector configurations on six boreal test plots and
463 manually annotated trees. It uses genuine point-set instance IoU at 0.5,
not NEON apex-distance matching or stem-Voronoi proxies. SegmentAnyTree leads
this historical frozen comparison with F1 0.566, but matches only six of 58
category-D trees beneath taller neighbors; strong understory transfer is not
demonstrated.

The [training-only adapter audit](results/frozen-transfer-audit-results.md)
then checks two separate training plots with 141 reference trees. Correcting
ForestFormer3D's inference route and exports raises pooled F1 from 0.089 to
0.570, versus 0.629 for unchanged SegmentAnyTree. The original six-plot test
results remain unchanged; corrected held-out transfer has not been measured.

The [whole-scene follow-up](results/forestformer-scene-assembly-results.md)
removes the redundant outer merge and preserves all 6.71 million source rows
on those same training plots. Pooled ForestFormer3D mask F1 rises to **0.754**;
category-D matches rise from 1/20 to 7/20. This clears its adapter-assembly gate
for **optional controlled comparison using whole-scene outputs**, not default
ensemble admission or held-out transfer. Native assembly still has its own
overlap policy and errors; larger-scene resource behavior remains untested.

Fresh native confidence features are exported, but no calibrator is fitted on
the audit labels. Do not reuse calibration based on the former score broadcast.
TreeisoNet remains **deferred** after export corrections leave fragmentation.
SAT and classical Treeiso remain comparators, with Treeiso's annotation-assisted
semantic exclusions disclosed. These findings do not establish architecture
rankings, fusion benefit, strong understory generalization, or final routing
thresholds. HARV development and BART held-out work still require score-blind
availability, CRS and acquisition-epoch preflight.

### Choosing a method

These starting points apply to the measured benchmark conditions, not a claim
of production readiness. Use the external audit's eligibility limits when
selecting members for a new ensemble.

| Goal | Recommended starting point | Why |
| --- | --- | --- |
| Simple, inspectable tree-top baseline | CHM-VWF | The lasR/lidR same-CHM test shows the peak finder is not the material engine difference. |
| Reliable classical detector at varied density | multichm | It is the strongest stable classical LiDAR arm in the benchmark. |
| Maximum high-density detection F1 | SegmentAnyTree | Best pooled native F1 and understory recall among the evaluated single arms. |
| More understory trees | SegmentAnyTree, Li 2012, or a fusion operating point | These methods raise coverage; choose the precision/recall point explicitly. |
| Optical or sparse-LiDAR complement | Optional DeepForest support | Paired SOAP results support added recall at 1 pt/m2, with a precision cost; a universal threshold below 2 pt/m2 is not established. |
| Best classical crown diameter | Random walker with the per-crown stop rule | It has the lowest pooled crown-diameter RMSE in the shared-seed test. |
| Straightforward CHM crown product | lasR region growing or Dalponte | They are close in diameter accuracy and easier to inspect and reproduce. |

Detailed evidence:

- [Cross-model detection benchmark](results/model-benchmark-results.md)
- [Classical and 3-D crown benchmark](results/crown-segmentation-results.md)
- [Point-cloud detector comparison](results/pointcloud-detector-results.md)
- [RGB detectors and paired fusion](results/rgb-lidar-fusion-results.md)
- [Plot-held-out confidence calibration](results/confidence-calibration-results.md)
- [Detector-fusion results](results/detector-fusion-results.md)
- [Frozen external instance validation](results/fgi-emit-external-results.md)
- [Training-only transfer audit](results/frozen-transfer-audit-results.md)
- [Whole-scene assembly comparison](results/forestformer-scene-assembly-results.md)
- [lasR versus lidR implementation comparison](results/treetop-lasr-vs-lidr-comparison.md)

## Benchmark design

The methods are evaluated on a bundled tile, a USGS 3DEP AOI, and 2021 NEON
LiDAR paired with field-mapped stems from three contrasting forest structures.
The NEON experiment holds data preparation and matching rules constant, then
tests methods over native, 8, 4, 2, and 1 pts/m² rungs where a method remains
meaningful. Density is therefore an evaluation condition, not the subject of
the repository.

- CHM resolution, local-maximum window, and smoothing are derived from measured
  density rather than copied as fixed parameters between acquisitions.
- Detection uses one-to-one apex matching; crown delineation uses field crown
  widths. NEON instance metrics use a labelled Voronoi-on-stems proxy;
  FGI-EMIT uses manual 3D instance annotations and its original A-D categories.
- Results pool counts or error sums before calculating rates and RMSE, so small
  plots do not dominate a site-level result.
- Calibration and paired RGB weights hold out the target plot. External test
  scores and training-only adapter diagnostics remain separate experiments;
  an observed test set is not a fresh holdout for changes motivated by it.

Read the [methodology](docs/treetop-detection-approach.md) for the parameter
rules and [NEON site notes](docs/neon-lidar-sites.md) for the data context.

## Start here

Run the bundled comparison to inspect the two CHM local-maximum implementations.
It needs no data download:

~~~sh
export CLAUDE_JOB_DIR="$PWD/work"
mkdir -p "$CLAUDE_JOB_DIR"

Rscript scripts/detect_lasr.R
Rscript scripts/detect_lidr.R
Rscript scripts/compare.R \
  "$CLAUDE_JOB_DIR/tops_lasr.csv" \
  "$CLAUDE_JOB_DIR/tops_lidr.csv"
Rscript scripts/shared_chm.R
~~~

| If you want to... | Start with |
| --- | --- |
| Compare detector families and results | [Methods and results](#methods-and-results) |
| Reproduce crown-diameter metrics | [Crown workflow](#bundled-toy-tile) and [crown benchmark](results/crown-segmentation-results.md) |
| Process a real USGS 3DEP AOI | [USGS 3DEP workflow](#usgs-3dep-aoi) |
| Reproduce the field benchmark | [NEON method benchmark](#neon-method-benchmark) |
| Compare optical and LiDAR fusion | [Paired RGB-LiDAR workflow](#paired-rgb-lidar-fusion) |
| Inspect external transfer and adapter limits | [External validation and audit](#external-validation-and-audit) |
| Find every runnable entry point | [Script reference](#script-reference) |

## Reproduce a workflow

Run these examples from the repository root and set `CLAUDE_JOB_DIR`
explicitly. The shared R path helper defaults to the repository's `work/`
directory. Most R drivers accept `KEY=VALUE` arguments; comparison scripts may
take positional paths, and Python helpers use their documented command-line
flags. Check each entry point's usage before changing its invocation.

### Bundled toy tile

The [quick-start commands](#start-here) run the two density-first detection
paths. Run the remaining steps to sweep parameters and create crown products:

~~~sh
Rscript scripts/sweep.R
Rscript scripts/segment_lasr.R
Rscript scripts/segment_lidr.R
Rscript scripts/compare_crowns.R \
  "$CLAUDE_JOB_DIR/crowns_lasr.gpkg" \
  "$CLAUDE_JOB_DIR/crowns_lidr.gpkg"
~~~

The bundled MixedConifer.las file is provided by the lasR installation; it is
not a field-ground-truth benchmark. It is intended for fast, reproducible
pipeline and engine checks.

### USGS 3DEP AOI

The PDAL extraction clips the public EPT and reprojects it from Web Mercator to
UTM before metric-sensitive processing. From the repository root:

~~~sh
REPO_ROOT="$(git rev-parse --show-toplevel)"
(cd "$CLAUDE_JOB_DIR" && pdal pipeline "$REPO_ROOT/scripts/extract.json")

Rscript scripts/detect_lasr_aoi.R
Rscript scripts/detect_lidr_aoi.R
Rscript scripts/shared_chm_aoi.R
Rscript scripts/pc_vs_chm.R
Rscript scripts/segment_lasr_aoi.R
Rscript scripts/segment_lidr_aoi.R
~~~

For a native lasR remote-EPT acquisition path, run
scripts/detect_lasr_ept_aoi.R instead. That path remains in EPSG:3857 and is
best used for acquisition/streaming experiments, not metric-faithful parameter
selection. See the [AOI comparison](results/treetop-lasr-vs-lidr-comparison.md).

### NEON method benchmark

This is the primary field-ground-truth benchmark. It downloads the needed NEON
field and LiDAR data, evaluates the CHM-VWF detector over density rungs, and
creates the data products consumed by the other method arms. A full three-site
run needs network access, a configured `NEON_TOKEN`, several GB of working
storage, and meaningful compute time. Keep the token in the environment or
user-managed `~/.Renviron`, never in the repository. See
[NEON's token setup](https://www.neonscience.org/resources/learning-hub/tutorials/api-token-setup).

~~~sh
for SITE in SJER SOAP TEAK; do
  Rscript scripts/neon_ground_truth.R SITE="$SITE"
  Rscript scripts/neon_download_lidar.R SITE="$SITE" YEAR=2021
  Rscript scripts/run_sweep.R SITE="$SITE" PLOTS=ALL CORES=8
  Rscript scripts/analyze_sweep.R SITE="$SITE"
done
Rscript scripts/compare_sites.R
~~~

Use a distinct OUT value when running an exact-year temporal subset so that it
does not replace the default ±4-year ground-truth baseline:

~~~sh
Rscript scripts/run_sweep.R SITE=SOAP MEAS_YEAR=2021 \
  OUT="$CLAUDE_JOB_DIR/neon/SOAP/sweep_results_2021.csv"
~~~

New reference and download runs record acquisition-year/CRS manifests. The
ground-truth defaults remain `YEAR=2021 MAX_YEAR_GAP=4`; `dist_aop` follows the
chosen year, while `dist21` retains its historical meaning. New runs reject
unversioned or incompatible reference, acquisition, frozen-clip and RGB-box
caches. Use a fresh `CLAUDE_JOB_DIR` for regeneration; do not delete or relabel
the historical artifacts. Read-only analysis of existing results is unchanged.

### Eastern-site preflight

HARV development and BART held-out validation are declared, but **no eastern
detector results or eligible plot split are available yet**. August 2022 field
and released-file inventories are complete. HARV_033 has matching EPSG:32618
field/LiDAR/RGB headers and leaf-on RGB; its buffered normalized clip measures
12.825 all-return and 4.864 first-return points/m2. BART uses EPSG:32619 and has
not had spatial tiles downloaded. All ten count/tile candidates sample only
800 m2 of their nominal 1600 m2 tower boxes. Their measured footprints are now
reconstructed, but reference-unit policy, spatial uncertainty and unresolved
datum/flight provenance still block calibration, scoring and split freezing.
See the [preflight findings](results/eastern-broadleaf-results.md) and
[score-blind protocol](docs/eastern-preflight-protocol.md).

~~~sh
export CLAUDE_JOB_DIR="$PWD/work/eastern-study-2022"
Rscript scripts/preflight_eastern_sites.R
~~~

The command archives public metadata without a token or detector run. With
`NEON_TOKEN` configured, build exact-year references in that separate directory:

~~~sh
for SITE in HARV BART; do
  Rscript scripts/neon_ground_truth.R SITE="$SITE" YEAR=2022 MAX_YEAR_GAP=0
done
Rscript scripts/preflight_eastern_sites.R MODE=references
AUDIT="$CLAUDE_JOB_DIR/authenticated_preflight_v2"
Rscript scripts/preflight_eastern_coverage.R MODE=coverage OUT="$AUDIT"
~~~

These commands list count/tile candidates and census sampling metadata, not
a validated or frozen split. Released file snapshots omit signed cloud URLs.
The first score-blind selection was HARV_033; the bounded spatial diagnostic is:

~~~sh
Rscript scripts/neon_download_lidar.R SITE=HARV YEAR=2022 PLOTS=HARV_033
Rscript scripts/neon_download_aop.R SITE=HARV YEAR=2022 PLOTS=HARV_033
Rscript scripts/preflight_harv_smoke.R AUDIT="$AUDIT"
~~~

The smoke clips and normalizes data without a detector or scoring call. It does
not approve the nominal box as a scoring footprint. Use new output roots after
protocol/code changes; old manifests fail closed. The historical native-QL2
cross-check stays D17-only; fixed-2021 crown joins reject other reference years.

### Event-specific reference support

The [support audit](results/neon-reference-support-results.md) joins exact census
events and exports measured-corner polygons, conservative interiors and every
reference exclusion. The original HARV/BART bole-level diagnostics contain
204/226 selected interior references, but **no real support bundle is
evaluation-ready**. The optional polygon scorer and support-aware pooling are
tested synthetically; historical
rectangular scoring remains unchanged. Existing model runners are not migrated
automatically. See the [support protocol](docs/neon-reference-support-protocol.md).

The [record-resolution audit](results/neon-reference-resolution-results.md)
explains 42 of 43 per-bole exclusions through multi-bole/broken-bole measurement
rules, without filling values or admitting support. HARV time/schedule evidence
points to August 4, 2022, but exact source-flight attribution and field-marker
accuracy remain unresolved.

The separate [individual-level policy comparison](results/neon-individual-reference-results.md)
produces 206 HARV and 226 BART diagnostic references on unchanged interiors.
It records explicit location/height donors, retains all previously selected
individuals and adds two height-resolved HARV individuals. Four target
individuals remain unresolved; the [declared policy](docs/neon-individual-reference-protocol.md)
does not clear admission blockers or define crown-instance ground truth.

The [positional follow-up](results/neon-positional-evidence-results.md) finds
that a true-north offset hypothesis could explain the two marginal HARV subplot
conflicts, but no correction is applied. Archived trajectory times corroborate
the August 4 mission candidate, not exact flightline attribution. The
[NEON evidence request](docs/neon-evidence-request.md) is prepared but unsent;
all four individual cases and admission gates remain unresolved.

~~~sh
export CLAUDE_JOB_DIR="$PWD/work/reference-support-study"
for SITE in HARV BART; do
  Rscript scripts/neon_reference_support.R SITE="$SITE" YEAR=2022 \
    OUT="$CLAUDE_JOB_DIR/reference_support_v2/$SITE"
done
Rscript scripts/review_neon_reference_support.R \
  SUPPORT="$CLAUDE_JOB_DIR/reference_support_v2/HARV/support_bundles.rds"
Rscript scripts/audit_neon_reference_history.R SOURCE=/path/to/historical/work
~~~

Preparation downloads pinned field data and named-point metadata only. The
review script fetches only the previously declared HARV RGB tile. API tokens
stay outside the repository; signed URLs are never archived. Replay checks
input/code hashes and output receipts; use a new output root after revisions.

For the resolution follow-up, run `collect_neon_reference_evidence.R` with
`OUT=` and explicit `HARV_LIDAR=TRUE` for the declared HARV tile, then
`audit_neon_reference_resolution.R SOURCE=... SUPPORT=... EVIDENCE=... OUT=...`.
The [resolution protocol](docs/neon-reference-resolution-protocol.md) and
[results](results/neon-reference-resolution-results.md#reproduction-and-verification)
define the read-only inputs, bounded downloads and reproducible commands.

Prepare the separate individual-level comparison from pinned field snapshots:

~~~sh
Rscript scripts/prepare_neon_individual_references.R \
  SOURCE="$CLAUDE_JOB_DIR" SUPPORT="$CLAUDE_JOB_DIR/reference_support_v2" \
  OUT="$CLAUDE_JOB_DIR/individual_reference_v2"
~~~

This step makes no downloads and runs no detector. It preserves the old support,
exports a complete source-to-individual crosswalk and verifies hashes on replay.

The bounded positional follow-up uses those archived snapshots and requires
`pdftotext` plus the existing `sf`/PROJ installation; it makes no downloads:

~~~sh
Rscript scripts/audit_neon_positional_evidence.R \
  SOURCE="$CLAUDE_JOB_DIR" OUT="$CLAUDE_JOB_DIR/positional_evidence_v1"
~~~

The [follow-up protocol](docs/neon-positional-evidence-protocol.md) fixes its
scope and stop rule. Coordinate hypotheses do not update scoring references.

### Paired RGB-LiDAR fusion

This workflow requires the frozen NEON cells, persisted LiDAR instance outputs,
completed DeepForest tile predictions, and cached labelled detections. See the
[RGB-LiDAR report](results/rgb-lidar-fusion-results.md) for preparation and the
fixed operating points. Use `CORES=1` because lasR execution under fork can
drop dense cells.

~~~sh
Rscript scripts/calibrate_confidence.R SITES=SOAP,SJER,TEAK FROM_CACHE=1
Rscript scripts/fuse_detectors.R SITE=SOAP RUNGS=native,8,4,2,1 CORES=1
~~~

`RGB=0` retains the LiDAR-only controls. A bounded smoke run can use
`PLOTS=SOAP_031,SOAP_021 RUNGS=native,1 OUT=work/fusion-rgb-smoke.csv`.
Outputs include `fusion_results.csv` and the equal-set `fusion_rgb_summary.csv`.
Full-data deployment lookups must not score their own training plots; the
paired benchmark fits optical weights excluding each target plot.

### External validation and audit

Start with the [external protocol and results](results/fgi-emit-external-results.md)
for pinned acquisition, evaluator setup, and the historical frozen configuration.
The audit's [declaration](docs/frozen-transfer-audit-protocol.md),
[runtime note](docs/frozen-transfer-audit-runtime-note.md), and
[reproduction steps](results/frozen-transfer-audit-results.md#reproduction-and-artifacts)
describe its separate training controls, prerequisites, and protected artifacts.

`download_external_fgiemit.R` acquires the pinned release;
`detect_external_fgiemit.R` runs and scores selected arms. The audit driver,
`audit_frozen_transfer.R`, supports `MODE=infer` and `MODE=analyze` only on the
two predeclared training plots, after its declaration and frozen preparation.
Generated artifacts live under `work/external/fgiemit/`, with audit outputs
under `audit/`.

The [scene-assembly protocol](docs/forestformer-scene-assembly-protocol.md)
and [results](results/forestformer-scene-assembly-results.md) describe the
whole-scene follow-up. `audit_scene_assembly.R` reuses the two prepared training
plots and archived outer-cylinder outputs, writing only under `scene_assembly/`.
It requires its own sealed declaration before `MODE=infer` or `MODE=analyze`.
`FF_LAYOUT=whole_scene` selects indexed native export in the external driver;
the historical cylinder layout remains its default. Neither mode authorizes
a fresh test-set evaluation or reuse of incompatible calibration artifacts.

Current adapters include the audit corrections and will not reproduce the
historical frozen baseline unchanged. Use the documented frozen checkout for
that baseline, and a distinct `OUT_DIR` for a separately declared experiment.
Do not overwrite archived test predictions or tune on their labels.

## Requirements

| Scope | Requirements |
| --- | --- |
| Core toy and AOI workflows | R with lasR, lidR, terra, sf, and data.table |
| Required lasR build | r-lidar/lasR pre-devel; the released 0.21.0 build rejects the variable-window function used by the detection scripts |
| NEON workflows | neonUtilities, jsonlite, curl and digest; public metadata is open, data downloads need network access and `NEON_TOKEN` |
| EPT extraction | PDAL 2.9 or later |
| Optional analyses | clue, rpart, crownsegmentr, and lidRplugins as required by the corresponding arm |
| GPU/vision arms | The documented container, conda environment, or virtualenv under [gpu](gpu/) for that specific model |
| External instance validation | Existing detector runtimes, R dbscan and yaml, and the pinned official Python evaluator described in the external report |
| Tests | testthat |
| Markdown checks | rumdl with [.rumdl.toml](.rumdl.toml) |

The [lasR setup notes](results/density-ladder-sweep-results.md) document the
pre-development build requirement and the feature check behind it.
The model-specific setup instructions live alongside each runtime under
[gpu](gpu/) and in the linked result documents.

There is an important engine distinction: lasR uses a TIN plus post-hoc
pit_fill step, while lidR uses its Khosravipour pitfree method. They should not
be described as the same CHM algorithm.

## Data and reproducibility

- Tracked geographic context lives in [data](data) as GeoJSON site, plot, stem,
  and AOI layers.
- Downloaded LiDAR, rasters, tables, GeoPackages, model weights, and working
  files are intentionally gitignored. Regenerate them in CLAUDE_JOB_DIR.
- The NEON scorer pools counts before calculating rates; it does not average
  plot-level recall or precision. This prevents small plots from dominating a
  site result.
- NEON field stems support an apex/detection benchmark and clearly labelled
  Voronoi-on-stems instance proxies. External FGI-EMIT scores use manual point
  labels; neither score should be presented as the other metric.
- Cache reuse must match selected density/configuration, source and input
  provenance, and successful output receipts where required. Missing or
  ambiguous cache variants are not interchangeable with completed empty runs.

## Script reference

Run the driver scripts below directly. Supporting libraries are listed last;
they are sourced by drivers and covered by tests rather than run as standalone
workflows.

### Core detection and crown workflows

| Scripts | Purpose |
| --- | --- |
| detect_lasr.R / detect_lidr.R | Density-first detection on the bundled tile |
| compare.R / shared_chm.R / sweep.R | Compare top locations, isolate the same-CHM test, and sweep toy parameters |
| segment_lasr.R / segment_lidr.R / compare_crowns.R | Delineate toy crowns, calculate metrics, and compare polygons |
| detect_lasr_aoi.R / detect_lidr_aoi.R / shared_chm_aoi.R | Run and fairly compare the corresponding USGS AOI paths |
| segment_lasr_aoi.R / segment_lidr_aoi.R / pc_vs_chm.R | AOI crown products and high-density CHM-versus-point-cloud comparison |
| extract.json / extract_big.json | PDAL EPT clip and reproject pipelines |
| detect_lasr_ept_aoi.R | lasR-native remote-EPT acquisition and detection |
| tile_aoi.R / detect_lasr_catalog.R / detect_lidr_catalog.R | Retile an AOI and test multi-tile streaming behavior |
| density_cost.R / li2012_16core.R | Detection density/cost and multi-core Li 2012 throughput studies |
| bench_lasr_ept_acquisition.R / sweep_lasr_ept_params.R / sweep_lasr_ept_partitions.R | EPT throughput, parameter, and partition studies |

### Field data and validation studies

| Scripts | Purpose |
| --- | --- |
| neon_ground_truth.R / verify_geolocation.R | Build acquisition-year-aware field references and audit stem geolocation |
| neon_download_lidar.R / neon_download_aop.R | Token-authenticated, year/CRS-checked NEON LiDAR and RGB downloads; optional `PLOTS=` subset |
| preflight_eastern_sites.R | Archive score-blind HARV/BART metadata and inventory local exact-year field candidates |
| preflight_eastern_coverage.R | Archive released file identities, audit tile availability and census sampled areas; no split freeze |
| preflight_harv_smoke.R | Inspect the declared HARV-only LiDAR/RGB clip, density and normalization without detector inference |
| neon_reference_support.R / review_neon_reference_support.R | Exact-event reference audit, measured sampled-subplot polygons and HARV-only RGB geometry review; no evaluation admission |
| audit_neon_reference_history.R | Read-only census-support and artifact-integrity audit of archived D17 references |
| collect_neon_reference_evidence.R / audit_neon_reference_resolution.R | Archive official field/flight evidence and explain bole-level exclusions without changing or admitting references |
| prepare_neon_individual_references.R | Apply the declared individual-level policy to pinned field records; export source donors and compare diagnostic selection on unchanged support |
| audit_neon_positional_evidence.R | Read-only case histories, anchor metadata, offset hypotheses and archived trajectory compatibility; no corrections or admission |
| run_sweep.R / analyze_sweep.R / compare_sites.R | Run, pool, and compare the core CHM-VWF field benchmark |
| calval_split.R / calval_multichm.R | Held-out parameter calibration/validation |
| ept_discovery.R / native_ql2_crosscheck.R | Find covering 3DEP projects and test native-versus-decimated performance |
| validate_heights.R / temporal_sensitivity.R | Height validation and field-to-LiDAR temporal sensitivity |
| detect_pc_sweep.R / detect_pc_ladder.R | Point-cloud detector comparison at native and selected sparse rungs |
| matcher_robustness.R / mc_positional_uncertainty.R | Matching-rule and stem-position-uncertainty sensitivity |

### Model, fusion, and crown analyses

| Scripts | Purpose |
| --- | --- |
| detect_ams3d_sweep.R | Adaptive mean-shift crown segmentation arm |
| detect_lidrplugins_sweep.R / detect_multichm_sweep.R / analyze_multichm_sweep.R | lmfauto, ptrees, and multichm arms and their paired analysis |
| detect_li2012_native.R / detect_treeiso_sweep.R | Native point-cloud segmentation baselines |
| detect_treeisonet_sweep.R / detect_treeisonet_crowns.R | TreeisoNet apex and tree-offset crown arms |
| detect_segmentanytree_sweep.R / detect_forestformer3d_sweep.R | GPU point/instance segmentation arms |
| download_external_fgiemit.R / detect_external_fgiemit.R | Checksum-pinned external dataset and frozen detector transfer evaluation |
| audit_frozen_transfer.R | Declared training-only adapter inference and official-metric, export, and scene-assembly diagnostics |
| audit_scene_assembly.R | Bounded native whole-scene inference, protected-output checks and archived outer-cylinder comparison |
| detect_deepforest_sweep.R / detect_detectree2_sweep.R | RGB detector and crown-width arms |
| detect_sam2point_sweep.R | Promptable seed-to-refine point-cloud arm |
| analyze_model_benchmark.R / compare_model_sites.R | Equal-set-guarded model synthesis and cross-site results |
| score_instances_iou.R / compare_matching_rules.R | Point-set IoU, Coverage, PQ, and metric-ranking sensitivity |
| fuse_detectors.R / calibrate_confidence.R / route_detectors.R | LiDAR and paired RGB fusion, plot-held-out score calibration, and per-cell routing experiments |
| coverage_gap.R | Re-grade isolated likely-real false positives using cross-family agreement |
| crown_metrics_sweep.R / analyze_crown_metrics.R | Field crown-diameter benchmark and analysis |
| crown_allometry.R | Crown width and height to DBH/biomass analysis |

### Exports and supporting libraries

| Scripts | Purpose |
| --- | --- |
| export_geojson.R / export_stems_ground_truth_geojson.R / export_best_treetops_geojson.R | Export benchmark geography, field stems, and best detections as GeoJSON |
| bootstrap.R / repo_paths.R | Locate the repository and working directory consistently |
| neon_spatial_lib.R / eastern_preflight_lib.R / neon_acquisition_lib.R | NEON CRS, epoch and cache guards; authenticated tile queries, availability and sampling-support audits |
| neon_reference_support_lib.R | Census-event joins, surveyed footprints, reference exclusions, opt-in polygon scoring and support-aware pooling guards |
| neon_reference_resolution_lib.R | Exact-event bole-family evidence, immutable receipts and conservative flight/time attribution checks |
| neon_individual_reference_lib.R | Unique apparent-individual units, explicit measurement donors and separate diagnostic support identities |
| neon_positional_evidence_lib.R | PROJ-based offset hypotheses, strict trajectory extraction and named-point evidence limits |
| sweep_lib.R / calval_lib.R / pc_detect_lib.R | Shared density-ladder, split, and point-cloud detection helpers |
| model_bench_lib.R / model_runner.R / io_bridge.R | Shared model scoring, runtime, and point-instance I/O helpers |
| route_lib.R / coverage_lib.R / allometry_lib.R | Pure helpers for routing, coverage credit, and allometry |
| crown_metrics_3d.R / crown_metrics_deepmodel.R | Shared crown-metric helpers |
| external_fgiemit_lib.R / transfer_audit_lib.R | External reference projection, official metrics, protected provenance, and transfer diagnostics |
| gpu/prepare_fgiemit_reference.py / gpu/evaluate_fgiemit.py | Lossless reference-label conversion and official Python evaluator bridge |
| gpu/declare_transfer_audit.py / gpu/export_treeisonet_audit.py | Protected-file declaration and same-forward-pass diagnostic exports |

## Documentation and result index

| Read this | For |
| --- | --- |
| [Tree-top detection approach](docs/treetop-detection-approach.md) | Method, parameter rules, tooling, and pitfalls |
| [NEON LiDAR sites](docs/neon-lidar-sites.md) | Site, field-stem, LiDAR, and 3DEP context |
| [Eastern preflight findings](results/eastern-broadleaf-results.md) | HARV/BART field and file inventories, HARV smoke measurements and sampled-subplot blocker |
| [Eastern preflight protocol](docs/eastern-preflight-protocol.md) | Score-blind acquisition, coverage, smoke-plot and held-out split rules |
| [Reference-support findings](results/neon-reference-support-results.md) | Measured eastern footprints, unresolved target references and read-only historical census audit |
| [Reference-support protocol](docs/neon-reference-support-protocol.md) | Target population, exact events, geometry, uncertainty margins and evaluation-admission boundaries |
| [Reference-resolution findings](results/neon-reference-resolution-results.md) | Multi-bole measurement explanations, marginal subplot discrepancies and unresolved datum/flight evidence |
| [Reference-resolution protocol](docs/neon-reference-resolution-protocol.md) | Source-preserving record review, bounded HARV provenance checks and no automatic admission |
| [Individual-reference comparison](results/neon-individual-reference-results.md) | Paired bole/individual counts, donor provenance and four unresolved target individuals |
| [Individual-reference policy](docs/neon-individual-reference-protocol.md) | Declared population, family identity, location/height donors and unchanged spatial support |
| [Positional evidence findings](results/neon-positional-evidence-results.md) | Quantified coordinate-convention ambiguity and remaining source-evidence questions |
| [Positional follow-up protocol](docs/neon-positional-evidence-protocol.md) | Bounded, read-only comparison and stop rule pending authoritative clarification |
| [NEON evidence request](docs/neon-evidence-request.md) | Unsent inquiry with exact field and flight identifiers; no contact assumed |
| [Dataset and sweep plan](docs/dataset-research-and-sweep-plan.md) | Benchmark design and evaluation rationale |
| [lasR vs lidR comparison](results/treetop-lasr-vs-lidr-comparison.md) | Toy tile, AOI, same-CHM, crowns, and streaming results |
| [Density-ladder results](results/density-ladder-sweep-results.md) | Cross-density, crown-class, and site results |
| [Model benchmark](results/model-benchmark-results.md) | Classical and deep detector comparison |
| [Crown-segmentation results](results/crown-segmentation-results.md) | Field crown-width error for delineation methods |
| [Point-cloud detector results](results/pointcloud-detector-results.md) | Native-density CHM and point-cloud detector comparison |
| [Instance IoU, Coverage, and PQ](results/instance-iou-pq-results.md) | Mask-aware proxy evaluation |
| [RGB-LiDAR fusion](results/rgb-lidar-fusion-results.md) | Standalone optical results and paired, calibrated five-rung SOAP fusion |
| [Frozen external transfer](results/fgi-emit-external-results.md) | Six-plot FGI-EMIT historical baseline with manual instance labels |
| [Frozen transfer audit](results/frozen-transfer-audit-results.md) | Training-only adapter corrections, scene-assembly diagnostics, and arm eligibility |
| [Scene-assembly results](results/forestformer-scene-assembly-results.md) | Whole-scene identity, resource use, common-support metrics and eligibility |
| [Scene-assembly protocol](docs/forestformer-scene-assembly-protocol.md) | Fixed training comparison and row-identity acceptance contracts |
| [Audit protocol](docs/frozen-transfer-audit-protocol.md) | Predeclared comparisons, protected test artifacts, and follow-on validation split |
| [Audit runtime note](docs/frozen-transfer-audit-runtime-note.md) | Bounded memory and empty-output handling exceptions |
| [Agent guidance](AGENTS.md) / [Detailed repository guidance](CLAUDE.md) | Working conventions, methodology invariants, and completion checks |

Additional targeted analyses:

- [Calibration/validation](results/calibration-validation-results.md),
  [native QL2](results/native-ql2-crosscheck-results.md), and
  [temporal sensitivity](results/temporal-sensitivity-results.md)
- [Detector fusion](results/detector-fusion-results.md),
  [confidence calibration](results/confidence-calibration-results.md), and
  [detector routing](results/detector-routing-results.md)
- [Matcher robustness](results/matcher-robustness-results.md),
  [positional uncertainty](results/positional-uncertainty-results.md), and
  [coverage-gap crediting](results/coverage-gap-results.md)
- [Crown allometry](results/crown-allometry-results.md) and
  [SAM2Point seed-to-refine](results/sam2point-promptable-refine-results.md)

## Tests

Run the library test suite from the repository root:

~~~sh
Rscript tests/run_tests.R
~~~

The tests cover the shared scoring, pooling, detector-extractor, instance-I/O,
model-runner, routing, allometry, uncertainty, calibration, RGB fusion, and
external-transfer helpers. Unit fixtures do not require the large generated
LiDAR working set; optional live tests report their environment requirements.

For the Python reference and export tests, use the configured model environment
with NumPy, laspy, and a LAZ backend. The optional upstream fixtures also need
Torch, numpy_indexed, and the local TreeAIBox checkout:

~~~sh
gpu/.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
~~~

Before publication, check the final documentation and diff:

~~~sh
rumdl check --no-cache .
git diff --check
~~~
