# FGI-EMIT frozen detector transfer

This experiment evaluates the existing NEON detector configurations against
manual 3D instance annotations from an external boreal forest dataset. It does
not train models, tune thresholds, or fit calibration on FGI-EMIT test labels.

## Dataset and split

The [public release](https://doi.org/10.5281/zenodo.19351234) contains 19 plots
and 1,561 annotated trees, acquired in Espoo, Finland with helicopter
multispectral ALS in July 2023. Data access is open under CC-BY-NC-SA-4.0.
This is ALS, not ULS. The supplied files contain plot-local metric coordinates
without a CRS; no geographic reprojection is applied.

The test plots are **1002, 1004, 1008, 1012, 1018, and 1028**, comprising
**463 trees: A=204, B=73, C=128, D=58**. Training plot 1001 is reserved for the
technical preflight and excluded from the reported test scores.

A-D are the dataset's neighborhood-based crown categories: isolated/dominant,
similar-height neighbors, alongside a taller neighbor, and beneath a taller
neighbor. They are not substituted for NEON dominant/codominant/intermediate/
suppressed labels. Definitions and reference statistics come from the
[dataset paper](https://doi.org/10.1016/j.isprsjprs.2026.04.021).

## Frozen protocol

- All model inputs use geometry only. Existing checkpoints, confidence
  thresholds, voxel settings, and ForestFormer3D cylinder/merge parameters are
  unchanged from the repository runners. No FGI-EMIT training is performed.
- Ignore boundary category 5 before inference and scoring. For classical
  Treeiso only, exclude buildings, vehicles, and poles (classes 2-4), following
  the published protocol. Do not filter to annotated tree points.
- Remove annotation fields from model inputs. Estimate ground geometrically
  with CSF defaults; class 2 in the original file means building. TreeisoNet
  receives TIN-normalized heights; the other arms retain the raw local frame.
  Normalization retains the full point substrate, including negative residuals.
- Preserve `tree_index` through a lossless `laspy` reference conversion. This
  avoids the installed R LAS reader's limit on later extra dimensions. The
  conversion does not change integer coordinates, scales, offsets, or labels.
- Project predictions back to the full reference using nearest neighbors in
  **XYZ**, with a fixed 0.5 m distance limit. Unassigned source points remain
  in the search. TreeisoNet uses the corresponding normalized query coordinates.
- Remove predicted instances with fewer than 40 reference points or less than
  1.5 m vertical extent. Match with point-set IoU at least 0.5, not apex distance.
  Compute recall, precision, F1, Coverage, and supplementary PQ. Pool counts and
  IoU sums over shared plots, never average plot-level rates.
- Cross-check precision, recall, F1, Coverage, and A-D recall with the archived
  [official evaluator](https://github.com/ruoppa/fgi_emit/tree/main/accuracy).
  AP is not reported because the four adapters do not share an instance-score
  contract. Failed cells are recorded separately, never scored as zero detections.

The run manifest pins source/model files and container IDs. Cached scores also
require matching reference and labelled-output checksums. ForestFormer3D gets
an isolated writable model checkout, preserving previous benchmark artifacts.

| Arm | Frozen configuration |
|---|---|
| SegmentAnyTree | Existing `sat-sm120-test` image and inference driver; bundled checkpoint |
| ForestFormer3D | `epoch_3000_fix.pth`; 16 m cylinders, 24 m grid spacing, 2 m apex merge |
| TreeisoNet | ALS treeLoc/treeOff checkpoints; confidence 0.22, height cutoff 2 m, checkpoint-native voxels |
| Treeiso | Vendored runner; 0.05 m decimation, regularization 1/20, neighbor counts 5/20 |

The checkpoint MD5s are `c340ded5f01f0b03c2c717e0a0519323` for ForestFormer3D,
`1e3cffea8d16a784aa03ccad88b0642f` for treeLoc, and
`541c1abb3a309097efca3a3578d44bc9` for treeOff. Full container IDs and source
checksums are recorded in `run_manifest.json`. Learned arms run on an NVIDIA
RTX 5090; classical Treeiso runs on CPU.

## Results

Generated on 2026-09-15. All **24 plot-by-arm cells succeeded**. Each pooled
row covers the same six test plots and 463 reference trees. Precision, recall,
F1, Coverage, and all A-D recalls agree with the archived official evaluator
within a tolerance of 1e-8 on the fractional scale.

| Frozen arm | TP | FP | FN | Precision | Recall | F1 | Coverage | PQ |
|---|--:|--:|--:|--:|--:|--:|--:|--:|
| SegmentAnyTree | 256 | 185 | 207 | 0.580 | 0.553 | **0.566** | 0.524 | 0.475 |
| Treeiso | 89 | 161 | 374 | 0.356 | 0.192 | 0.250 | 0.262 | 0.191 |
| TreeisoNet | 127 | 2,206 | 336 | 0.054 | 0.274 | 0.091 | 0.356 | 0.063 |
| ForestFormer3D | 9 | 250 | 454 | 0.035 | 0.019 | 0.025 | 0.079 | 0.017 |

### Crown-category recall

| Frozen arm | A (204) | B (73) | C (128) | D (58) |
|---|--:|--:|--:|--:|
| SegmentAnyTree | 0.902 | 0.425 | 0.273 | 0.103 |
| Treeiso | 0.407 | 0.041 | 0.023 | 0.000 |
| TreeisoNet | 0.328 | 0.493 | 0.188 | 0.000 |
| ForestFormer3D | 0.034 | 0.014 | 0.008 | 0.000 |

### Per-plot F1

| Plot | Reference trees | SegmentAnyTree | Treeiso | TreeisoNet | ForestFormer3D |
|---|--:|--:|--:|--:|--:|
| 1002 | 93 | 0.639 | 0.244 | 0.215 | 0.072 |
| 1004 | 58 | 0.468 | 0.233 | 0.027 | 0.060 |
| 1008 | 34 | 0.648 | 0.200 | 0.035 | 0.000 |
| 1012 | 31 | 0.759 | 0.476 | 0.050 | 0.000 |
| 1018 | 216 | 0.512 | 0.170 | 0.134 | 0.007 |
| 1028 | 31 | 0.518 | 0.346 | 0.044 | 0.000 |

SegmentAnyTree is strongest in this frozen comparison, matching 184 of 204
category-A trees. However, it matches only **6 of 58 category-D trees**; the
other arms match none. Strong understory transfer is therefore not demonstrated.

TreeisoNet produces 2,206 false-positive instances, while ForestFormer3D has
very weak complete-tree overlap. Every reference point has a source neighbor
within 0.5 m for both SegmentAnyTree and ForestFormer3D on every plot, ruling
out a gross coordinate-frame displacement as the cause of that discrepancy.
This experiment does not separate checkpoint transfer from adapter effects.
Investigate those effects before treating the scores as intrinsic rankings of
the model architectures or using them to set routing thresholds.

The full R suite passes with three existing skips and one package-index network
warning. Both Python reference-bridge tests pass. The non-test preflight and
its cache-only rerun also agree with the official evaluator; cache reuse leaves
the inference receipts unchanged.

Artifact SHA-256 checksums:

```text
scores.csv        386748c1ffeedc3117017b10723fe996dc75339f8387f7cface040d5a448e79b
summary.csv       709f74a2ff8318d2d67083c485237cc74bd35e9f8b069350bbe74e019d2be555
run_manifest.json 1cf149163106ea248a5ca21eadecbf3cf00d4fdcf8524e169a5eee467bfe8509
```

## Interpretation limits

These are full-point instance metrics, not NEON apex-distance F1 or
stem-Voronoi proxy scores. Native-density transfer does not validate a sparse
density ladder, RGB fusion, or final routing thresholds.

Category D is concentrated in test plot 1018, which contains 43 of its 58
trees. Pooled D recall therefore does not establish consistent performance
across forest conditions; the six-plot sample remains limited.

The experiment preserves each adapter's existing behavior: TreeisoNet exports
assigned points above its cutoff in a minimum-shifted normalized frame. Its
`HMIN=2` therefore does not mean exactly 2 m above estimated ground when
normalization leaves negative residuals. ForestFormer3D uses the existing
cross-cylinder apex deduplication. Those choices can affect complete-tree IoU.
The permitted semantic exclusions also make this a benchmark protocol, not an
annotation-free deployment test. No model is retrained here, but the original
checkpoint training inventories have not been independently audited for overlap.

## Published reference results

These are **context, not a like-for-like leaderboard ranking**: the paper trained
its deep models and optimized classical parameters on FGI-EMIT. Our experiment
transfers the existing checkpoints and settings without target-dataset tuning.

| Published setup | Precision | Recall | F1 | Coverage |
|---|--:|--:|--:|--:|
| Treeiso, optimized | 0.540 | 0.449 | 0.491 | 0.449 |
| Treeiso, annotated-tree-only input | 0.624 | 0.456 | 0.527 | 0.468 |
| SegmentAnyTree, trained on FGI-EMIT | 0.681 | 0.618 | 0.648 | 0.596 |
| ForestFormer3D, trained on FGI-EMIT | 0.789 | 0.685 | 0.733 | 0.649 |

Source: Table 7 of the
[published paper](https://aaltodoc.aalto.fi/server/api/core/bitstreams/b7ec2ab5-6154-430e-aaba-42afe567b8fe/content).
The often-cited Treeiso F1 of 0.527 uses annotation-assisted input filtering;
the unassisted optimized baseline is 0.491. TreeisoNet is a separate learned
method, not the classical Treeiso entry in that table.

## Reproduction

Use the existing detector environments and images described by their repository
[SegmentAnyTree setup](../gpu/segmentanytree-sm120/README.md),
[ForestFormer3D setup](../gpu/forestformer3d-sm120/README.md), and
[TreeisoNet setup](../gpu/setup_treeisonet_env.sh). Classical Treeiso uses the
existing `treeiso` conda environment, or a `TREEISO_PYTHON=...` override.
The R adapter also requires `dbscan` and `yaml`. The external evaluator needs
its own pinned Python environment; it does not modify the GPU environments.

```sh
export CLAUDE_JOB_DIR="$(pwd)/work"
Rscript scripts/download_external_fgiemit.R SPLITS=test,training
uv venv work/external/fgiemit/eval-env
uv pip install --python work/external/fgiemit/eval-env/bin/python \
  -r work/external/fgiemit/source/accuracy/requirements.txt

# Non-test technical preflight, written separately from test results.
Rscript scripts/detect_external_fgiemit.R SPLIT=training PLOTS=1001 \
  EVAL_PYTHON=work/external/fgiemit/eval-env/bin/python

# Published test split; all four arms, serial GPU execution.
Rscript scripts/detect_external_fgiemit.R \
  EVAL_PYTHON=work/external/fgiemit/eval-env/bin/python

Rscript tests/run_tests.R
work/external/fgiemit/eval-env/bin/python tests/test_fgiemit_reference.py
```

Outputs under `work/external/fgiemit/` include `scores.csv`, `summary.csv`,
`status.csv`, `run_manifest.json`, `official_*.json`, and aligned labelled
clouds under `instances/`. Native model outputs remain under `runs/`.
`PLOTS=...` limits a run; `OUT_DIR=...` separates experiments with different
configuration or code provenance. All generated data remains untracked.
