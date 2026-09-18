# Frozen detector transfer audit

Completed training-only integration audit on 2026-09-15. All 20 full-plot
comparison rows succeeded; all **80 official metric checks passed**. Real
adapter defects explain much of ForestFormer3D's earlier weakness, but its
outer scene assembly still degrades predictions. TreeisoNet's corrections do
not resolve its weak transfer. Neither result establishes ensemble benefit.

## Scope and integrity

The [predeclared protocol](../docs/frozen-transfer-audit-protocol.md) restricts
inference to FGI-EMIT training plots 1001 and 1019. The second plot was selected
from metadata before its detector scores were inspected. Plot 1001 contains
133 trees (A/B/C/D: 38/23/52/20), dense conifer canopy and substantial understory.
Plot 1019 is the sparsest training plot by stem density, with eight isolated
category-A trees, deciduous dominance and minimal understory. Its eight trees
are a structural contrast, not independent evidence of generalization. See the
[dataset release](https://doi.org/10.5281/zenodo.19351234) and
[forest-type descriptions](https://doi.org/10.1016/j.isprsjprs.2026.04.021).

The previous six-plot test results remain a historical baseline. No test plot
was inferred, rescored, used to select parameters, or overwritten in this audit.
The declaration protects 60 files with SHA-256, including all 24 aligned test
predictions, 24 score receipts, pooled results, input plots and model files.
The original [external results report](fgi-emit-external-results.md) is unchanged.
Any later test rescore must be a separate experiment, not an untouched holdout.

SAT and classical Treeiso are unchanged controls. The existing 1001 preflight
is reused; the second plot uses the same frozen source revision and settings.
The learned-model comparisons use existing weights and native-density inputs,
without a parameter sweep, retraining, new architecture, or voxel tuning.

## Results

Plot 1001 has 133 reference trees; plot 1019 has eight. All values below are
fractions. Apex F1 is a separate location diagnostic, not the official mask F1.
"Corrected TreeisoNet" means physical-height, support-masked, aligned export.

| Plot | Arm | Predicted | TP | FP | Mask F1 | Coverage | Apex F1 |
|---|---|---:|---:|---:|---:|---:|---:|
| 1001 | SAT, unchanged | 109 | 76 | 33 | 0.628 | 0.558 | 0.818 |
| 1001 | Treeiso, unchanged | 59 | 37 | 22 | 0.385 | 0.298 | 0.583 |
| 1001 | ForestFormer3D, frozen | 16 | 3 | 13 | 0.040 | 0.042 | 0.174 |
| 1001 | ForestFormer3D, native path | 78 | 59 | 19 | 0.559 | 0.435 | 0.701 |
| 1001 | TreeisoNet, frozen | 293 | 63 | 230 | 0.296 | 0.464 | 0.512 |
| 1001 | TreeisoNet, corrected | 287 | 61 | 226 | 0.290 | 0.457 | 0.519 |
| 1019 | SAT, unchanged | 17 | 8 | 9 | 0.640 | 0.933 | 0.640 |
| 1019 | Treeiso, unchanged | 15 | 8 | 7 | 0.696 | 0.970 | 0.696 |
| 1019 | ForestFormer3D, frozen | 23 | 5 | 18 | 0.323 | 0.480 | 0.516 |
| 1019 | ForestFormer3D, native path | 16 | 8 | 8 | 0.667 | 0.969 | 0.667 |
| 1019 | TreeisoNet, frozen | 80 | 0 | 80 | 0.000 | 0.316 | 0.182 |
| 1019 | TreeisoNet, corrected | 72 | 0 | 72 | 0.000 | 0.315 | 0.200 |

The current variants pooled over the same **141 reference trees**:

| Arm | TP / FP / FN | Precision | Recall | F1 | Coverage | D recall |
|---|---|---:|---:|---:|---:|---:|
| SAT, unchanged | 84 / 42 / 57 | 0.667 | 0.596 | 0.629 | 0.579 | 0.100 |
| Treeiso, unchanged | 45 / 29 / 96 | 0.608 | 0.319 | 0.419 | 0.336 | 0.000 |
| ForestFormer3D, native path | 67 / 27 / 74 | 0.713 | 0.475 | 0.570 | 0.465 | 0.050 |
| TreeisoNet, corrected | 61 / 298 / 80 | 0.170 | 0.433 | 0.244 | 0.448 | 0.000 |

Frozen pooled F1 was 0.089 for ForestFormer3D and 0.245 for TreeisoNet. All
20 category-D references are in plot 1001: SAT matched two, native-path
ForestFormer3D one, and the other arms none. The route correction therefore
does **not** establish strong understory transfer.

### Same-pass TreeisoNet comparisons

The legacy shifted/assigned export reproduces the archived metric rows on both
plots. The following changes are derived from one raw forward pass per plot;
they are not independently rerun or selected by which yields the highest F1.

| Export | 1001 predicted / TP | 1001 F1 | 1019 predicted / TP | 1019 F1 |
|---|---:|---:|---:|---:|
| Shifted cutoff, assigned-only projection | 293 / 63 | 0.2958 | 80 / 0 | 0.0000 |
| Physical cutoff, assigned-only projection | 288 / 63 | 0.2993 | 73 / 0 | 0.0000 |
| Shifted cutoff, aligned background | 292 / 63 | 0.2965 | 77 / 0 | 0.0000 |
| Physical cutoff, aligned background | 287 / 61 | 0.2905 | 72 / 0 | 0.0000 |
| Physical cutoff, aligned and support-masked | 287 / 61 | 0.2905 | 72 / 0 | 0.0000 |

Minimum normalized heights were -0.724 m and -1.008 m. Correcting the cutoff
changes 19,623 and 10,719 point assignments respectively. Both plots have
**zero unsupported points**: the out-of-volume bug is proven synthetically but
does not explain their observed failures. The final export retains every input
row, including background; that is 100% row support, not 100% tree assignment.
After filtering, assigned fractions are 83.55% and 9.47% of all reference points.

There are 335 and 444 post-peak treeLoc seeds. With the physical cutoff, 308
and 88 IDs retain points; the official filters remove 21 and 16, leaving 287
and 72. Frozen comparison files were already filtered, so their "before filter"
counts in the diagnostic CSV must not be interpreted as raw model counts.

On plot 1001, meaningful-overlap split references fall from 59 to 56 and merged
predictions from 24 to 23. Background-majority predictions fall from 13 to 9;
assigned-background fraction falls from 0.964% to 0.537%. On plot 1019, all eight
references remain split, with no merge edges; background-majority predictions
fall from 10 to 3 and assigned-background fraction from 2.047% to 0.561%.
The corrected sparse-plot output has eight apex matches but **zero IoU matches**.
Location proximity, excessive fragmentation and correct instance masks are
therefore demonstrably different outcomes. Selecting the slightly higher-F1
assigned-only variant would preserve the export defect rather than resolve it.

### Cylinder and projection diagnostics

There are 25 outer cylinders: nine for plot 1001 and 16 for plot 1019. All
100 route/mode diagnostic rows use verified common reference-point support.
Native per-cylinder F1 exceeds stitched/projected F1 in **all nine** dense-plot
regions. On the sparse plot it exceeds stitched F1 in seven regions and equals
it in four; five regions have undefined F1 because both sets are empty.

For the dense central cylinder, both methods see 111 reference instances, 45
of them truncated by the cylinder boundary. Local native output has 62 TP and
F1 0.639; stitched/projected output on exactly that support has 49 TP and
F1 0.554. Across the dense cylinders, 9-45 reference instances are truncated;
the sparse range is 0-4. These overlapping counts are not pooled as plots.

| Plot / route | Local identities | Stitched identities before filters | Same-cylinder collisions | Groups with >5 m apex-Z spread |
|---|---:|---:|---:|---:|
| 1001 / frozen | 110 | 29 | 3 | 3 |
| 1001 / native | 277 | 80 | 25 | 22 |
| 1019 / frozen | 65 | 46 | 5 | 1 |
| 1019 / native | 38 | 16 | 0 | 0 |

The height-spread flags are not all proven false merges: a partial view can
have a lower apex. Same-cylinder collisions violate the intended identity
constraint, but do not individually prove distinct physical trees. The paired
scores locate degradation in **combined stitching and reference projection**;
they do not isolate each merge or tie-break's causal contribution.

Native ForestFormer3D covers every reference coordinate within 0.002 m, with
maximum nearest distances below 0.001 m. Nevertheless, 338,457 dense-plot and
40,447 sparse-plot duplicate-coordinate groups carry conflicting labels after
identity merging, including assigned/background conflicts. Perfect geometric
overlap is not sufficient. The aligned TreeisoNet outputs have 671 and 414
duplicate-coordinate groups, but no conflicting labels in these runs; row
identity is still retained rather than assumed interchangeable.

The final native-path cell times were 605.8 s and 332.0 s, including staging
and export but excluding this analysis. TreeisoNet took 13.5 s and 11.9 s.
Three sparse-plot cylinders exercised the validated empty-return workaround;
none did on the dense plot. All 25 full-scene exports passed correspondence
checks. These times are implementation observations, not matched latency trials.

## Arm eligibility

| Arm | Status | Condition for further work |
|---|---|---|
| SAT | Candidate for controlled comparison | Keep as the unchanged learned baseline; validate complementary errors and calibration on declared development folds |
| Classical Treeiso | Candidate for controlled comparison | Retain as a comparator; account for annotation-assisted semantic exclusion and weak dense-plot recall |
| ForestFormer3D | Experimental | Resolve redundant outer assembly or cross-cylinder identity/projection conflicts before default ensemble admission; regenerate confidence features from corrected outputs |
| TreeisoNet | Deferred | The bounded fixes are complete, but segmentation remains weak and heavily fragmented; further checkpoint/domain work requires a separately declared experiment |

Proceed with detection-only pipeline contracts and controlled comparisons of
eligible arms. A focused ForestFormer3D scene-assembly follow-up should compare
native whole-scene inference with any necessary outer tiling, preserve source
point identity, and prevent transitive same-cylinder collisions. Do not reuse
confidence calibration fitted to the former ForestFormer3D candidate-score
broadcast. This follow-up gates that arm, not unrelated pipeline plumbing.
The formerly proposed eastern-site preflight follow-on is now
[retired](../docs/harv-bart-closeout.md). No new architecture sweep is warranted
by these adapter findings alone.

## Verified integration findings

### ForestFormer3D

The pinned upstream `predict()` checks whether `lidar_path` contains `test`.
Previously staged `cyl_*` names selected the fallback branch, which takes the
first query features rather than the native learned-query, overlapping-region
test path. This is a demonstrated adapter-route defect, not evidence of a
fundamental architecture limitation.

The corrected driver stages `test_cyl_*` names and checks the actual sample
path. Native inference returns only its last inner region through the data
sample, but writes a complete-scene PLY separately. The driver now consumes
that PLY, verifies its length and point order against the staged input, restores
coordinates in float64, and maps upstream background -1 to LAS background 0.
There is no silent `min(point_count, label_count)` truncation. Out-of-range LAS
instance/block IDs fail instead of clipping into collisions.

The old confidence broadcast assumed panoptic IDs retained candidate-score
ordering, although upstream sorts and relabels those instances. The corrected
export reads aligned per-point confidence from the full-scene output instead.
This audit does not claim calibrated probabilities or comparable AP scores.

The first native attempt exhausted GPU memory on a 28.56 GiB distance matrix.
The [runtime note](../docs/frozen-transfer-audit-runtime-note.md) records the
retry with the existing exact nearest-neighbor row batch reduced from 20,000
to 2,048. No point subsampling or predictive threshold changed. The failed
attempt is retained and is not scored as an empty detection. Single-run GPU
results are not a claim of bitwise repeatability across kernels or query
sampling; the failed run is not a second scored replicate.

A subsequent attempt completed plot 1001 but stopped on a valid all-background
cylinder in plot 1019: upstream saved the scene, then a typed property rejected
its `None` last-region return. The adapter handles only that exact assertion,
after full-scene validation and only with all-background labels. It does not
convert arbitrary model failures into zero detections. Both training plots are
rerun under the final implementation, with earlier attempts kept separately.

The existing outer-cylinder XY-apex merge is deliberately unchanged. Synthetic
fixtures show that it can merge vertically separated instances and transitively
join two instances from one cylinder through another cylinder. Duplicate XYZ
points with conflicting labels cannot be disambiguated by nearest-neighbor
distance alone. These limitations are measured separately below, not hidden by
selecting a new merge radius on the audit plots.

### TreeisoNet

Three boundaries are separated using counterfactual exports from the **same
forward pass**, with confidence 0.22, native voxels, and a 2 m height cutoff:

- The previous cutoff used `Z - min(Z)` after an internal coordinate shift.
  Negative normalized input heights therefore admitted points below 2 m. The
  corrected cutoff uses the original normalized-height frame.
- The upstream treeOff initializes all labels to zero, predicts only points
  inside each voxel block, then adds one globally. Unsupported points therefore
  become instance 1. A CPU fixture runs the actual installed upstream function
  with a stub network, reproduces this behavior, and verifies the wrapper's
  support mask. The wrapper restores unsupported points to background without
  editing the model checkout or changing voxel resolution.
- Assigned-only CSV export removes nearby background before reference
  projection. The external adapter now exports all input rows with explicit
  background and checks row correspondence, rather than projecting only the
  assigned subset. This preserves distinct rows even at duplicate coordinates.

The comparison includes shifted/physical cutoffs with assigned-only projection
and aligned export, plus the final support-masked aligned export. Detector
counts and official size/height filters are reported separately. These are
integration fixes, not a new treeLoc/treeOff model or evidence of useful fusion.

## Checkpoint and input provenance

| Arm | Checkpoint identity (MD5) | Input contract and source evidence |
|---|---|---|
| SAT | `PointGroup-PAPER.pt`: `1dcaceec9608d53308810fce8d3ca747` | XYZ with ground; upstream localization, no external height normalization; bundled official model family |
| ForestFormer3D | `epoch_3000_fix.pth`: `c340ded5f01f0b03c2c717e0a0519323` | XYZ with ground, per-cylinder mean XY/min Z centering, upstream native 0.2 m voxels and radius 16 m; FOR-instanceV2 release |
| TreeisoNet treeLoc | `als_treeloc.pth`: `1e3cffea8d16a784aa03ccad88b0642f` | XYZ, CSF/TIN normalized heights, internal minimum shift, voxel occupancy input; ALS reclamation model family |
| TreeisoNet treeOff | `als_treeoff.pth`: `541c1abb3a309097efca3a3578d44bc9` | Occupancy plus treeLoc seeds; same normalized input and native configuration |
| Classical Treeiso | No learned checkpoint | Frozen geometric baseline; existing semantic exclusion and parameters unchanged |

The installed ForestFormer3D weight matches the member of the cached official
archive. The archive MD5 `553d67379331966509076f3fbb409e57` matches the
[published release](https://zenodo.org/records/16742708). This verifies the
installed checkpoint's identity, not a complete scene-level training inventory.

SAT is pinned to source `a3561ed8447bbb7938f059ba65a3e9c97d6e2ee9` and Docker
image `sha256:27ce258d8a5ab70bdc457523d373848d5065e7b8044d3ef7891ff9e53dee2bd2`.
The [upstream repository](https://github.com/SmartForest-no/SegmentAnyTree)
documents the model and inference pipeline. ForestFormer3D is pinned to source
`6a75c3735e4a4108d02ee944a8b93177f2360a4f` and image
`sha256:fd60f5cdc5ae880af13b339f4aa1f1e891a3809c7f39fb15d2b5ff04978799f3`.
Existing compatibility/configuration patches are included in the source hashes.

TreeAIBox is pinned to `5380ddec2799f55adb43b63407dd12ccf7abefae`. Both installed
configuration files have MD5 `3e14861b5818bae1429614693eb4b77a`, specifying
128 x 128 x 128 voxels at 0.1 x 0.1 x 0.2 m. Their physical volume is therefore
**12.8 x 12.8 x 25.6 m**, not a 12.8 m vertical span. The model-zoo filenames
identify the reclamation family; the
[available documentation](https://github.com/NRCan/TreeAIBox) does not establish
the exact installed models' training plots. Native voxel compatibility does
not establish that this forest's structure matches their training domain.

FGI-EMIT overlap with complete source training inventories remains **unknown**
for the learned checkpoints. None was trained on FGI-EMIT by this repository.
No RGB or intensity channel is introduced; annotation fields are stripped from
deep-model inputs. Plot-local metric coordinates are not misrepresented as UTM.
Classical Treeiso retains the original annotation-assisted semantic exclusion,
so it is not an annotation-free deployment control.

## Metric definitions

Primary metrics use official point-set IoU matching at 0.5, minimum 40 predicted
points and 1.5 m vertical extent, class-5 exclusion, background 0, and the
original A-D reference categories. Pooled rates use summed counts, never a
mean of plot-level rates. Precision, recall, F1, Coverage and A-D recall are
cross-checked against the archived official evaluator. PQ is supplementary.

Location diagnostics use each filtered instance's maximum-Z point on the same
reference substrate. Matches are greedy, globally increasing XY distance,
one-to-one, within **4 m XY and absolute 5 m Z**; ties use reference/prediction
order. These are cloud-apex matches, not field-stem matches or proof of correct
crown geometry.

Split/merge diagnostics count overlap edges holding at least 10% of **both**
the predicted and reference instance. A split has more than one such prediction
per reference; a merge has more than one such reference per prediction. A
background-majority prediction has more than 50% of its points on reference
background. Assigned-background fraction uses all assigned points as its
denominator. These explanatory counts are not replacements for official IoU.

Cylinder comparisons restrict every method to the same reference points whose
XYZ distance to the cylinder input support is at most 0.002 m, allowing for
millimeter LAS quantization. Equality of this support across inference routes
is checked. Reference instances extending beyond that support are counted as
truncated. Overlapping cylinder scores are not pooled as independent plots.

## Follow-on validation

The proposed HARV-development/BART-validation follow-on was
[retired on 2026-09-18](../docs/harv-bart-closeout.md). No eastern validation
claim or replacement site is implied. Synthetic detection-pipeline contracts
can proceed independently. A future real-data comparison needs a separately
declared development dataset, eligible reference support, whole-plot folds and
held-out evaluation. The observed FGI-EMIT test set is not a fresh holdout.

Field-stem detection transfer would not validate crown-mask quality. Crown
promotion needs genuine instance annotations and its own holdout. No standalone
F1 improvement in this audit demonstrates complementary errors, fusion benefit,
universal sparse/RGB routing, or production readiness.

## Reproduction and artifacts

This audit requires the already downloaded release, installed model resources,
archived training preflight and frozen test artifacts. `CLAUDE_JOB_DIR` selects
their shared work directory. The declaration is created **once**, before new
inference, and refuses to overwrite an existing declaration:

```sh
python3 gpu/declare_transfer_audit.py \
  --root "$CLAUDE_JOB_DIR/external/fgiemit"
```

The unchanged second-plot baseline was run from frozen revision
`79c683adbc968c8424208b5570d99b0230a6003c`, with that checkout's existing model
resources. Do not substitute the corrected driver when reproducing the frozen
control:

```sh
# Run from the frozen checkout.
Rscript scripts/detect_external_fgiemit.R SPLIT=training PLOTS=1019 \
  OUT_DIR="$CLAUDE_JOB_DIR/external/fgiemit/audit/baseline_1019" \
  EVAL_PYTHON=/tmp/fgi-eval-venv/bin/python

# Run from the audit checkout, after the frozen preparation has completed.
Rscript scripts/audit_frozen_transfer.R MODE=infer \
  EVAL_PYTHON=/tmp/fgi-eval-venv/bin/python
Rscript scripts/audit_frozen_transfer.R MODE=analyze \
  EVAL_PYTHON=/tmp/fgi-eval-venv/bin/python
python3 gpu/declare_transfer_audit.py \
  --root "$CLAUDE_JOB_DIR/external/fgiemit" --verify
```

Both modes reject plots other than the two declared training plots. Inference
reuse requires identical source/configuration/preparation provenance and
unchanged successful output checksums. Analysis checks successful receipts,
prepared inputs and source hashes before scoring. The corrected TreeisoNet
production export is checked against the same-pass diagnostic export.

Generated files live under `work/external/fgiemit/audit/` and are not committed:

- `declaration.json`: timestamp and protected SHA-256 inventory.
- `baseline_1019/`: unchanged controls, receipts and official checks.
- `native-memory-failure/` and its log: unscored failed native attempt.
- `native-empty-return-failure/` and its log: interrupted empty-return attempt,
  excluded from the final numerical comparison.
- `corrected/run_manifest.json`: source, model, environment and input pins.
- `corrected/runs/`: full-scene cylinder outputs, export receipts, TreeisoNet
  raw forward arrays, aligned labels and counterfactual exports.
- `analysis/scores.csv` and `summary.csv`: per-plot and pooled point-set metrics.
- `analysis/cylinders.csv`: common-support local/stitched metrics and truncation.
- `analysis/projection.csv`, `stitching.csv` and `duplicates.csv`: support,
  merge and duplicate-coordinate diagnostics.
- `analysis/instances/` and `official_*.json`: aligned evaluator inputs and
  independently checked official metrics.
- `analysis/analysis_manifest.json`: analysis source and input receipt hashes.

Verification commands:

```sh
Rscript tests/run_tests.R
gpu/.venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v
rumdl check --no-cache docs/frozen-transfer-audit-*.md \
  results/frozen-transfer-audit-results.md gpu/forestformer3d-sm120/README.md
git diff --check
```

The full R suite passed with three existing skips: the environment-gated live
projected-coordinate smoke test, lidR's unsupported empty-LAS fixture, and the
default Python environment's missing `plyfile` smoke dependency. Its existing
package-index probe emitted one offline r-universe warning. All 12 Python
tests passed in the installed TreeisoNet environment, including the upstream
CPU-stub integration test. The optional PLY library remains available in the
ForestFormer3D container used for actual scene validation. A request to run
the audit on test plot 1002 was rejected before inference.

Cache-only replay succeeded with all four inference receipt timestamps
unchanged. The final SHA-256 check verified all 60 protected files. Intermediate
ForestFormer3D clouds also produce lidR warnings about zero return-number
fields; those unused attributes do not enter the XYZ/instance scoring contract.
The original test report and preceding benchmark checkout are unchanged.
