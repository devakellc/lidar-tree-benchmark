# FGI-EMIT Development Input Validation

Completed on 2026-09-23 under the
[input-validation protocol](../docs/fgiemit-input-validation-protocol.md).
All ten declared development plots passed reference, row-identity, original
return-field, export and finite-normalization checks. Their prepared support
contains **32,445,937 points and 841 annotated trees**. No detector was run,
no confidence calibration was fitted and no reserve or historical-test point
records were parsed. Overall real-data evaluation admission remains false.

The [original declaration](fgiemit-development-audit-results.md) is unchanged.
Its reserve remains plots 1003, 1010 and 1023. Existing predictions, scores,
calibrations and source files are preserved.

## Point Support, Coordinates and Density

The [release description](https://doi.org/10.5281/zenodo.19351234) distinguishes
tree instances from unassigned boundary trees. This preparation excludes only
class 5: 793,971 points across the development plots. Classes 0–4 remain,
including background, buildings, vehicles and poles. Annotated edge and dead
trees remain references. Every positive instance ID agrees with the tree
metadata, and every class-1 point has a positive instance ID.

Each point keeps its original zero-based `source_row`, even when XYZ duplicates
another row. The separate reference export retains semantic and instance
labels. Model geometry has no tree IDs, original semantic labels or spectral
features. All exports reopen with exact integer XYZ, coordinate scales and
offsets, original return fields and source-row identities. Normalized geometry
also preserves XY and row/return identity exactly; its Z is terrain-subtracted.

Every plot uses its own `FGI-EMIT/19351234/plot_<ID>` metric frame with no EPSG.
Source coordinates are preserved; plots must never share a coordinate frame
merely because their local coordinates overlap. The
[dataset description](https://arxiv.org/html/2511.00653v1#S3.SS3) gives plot
diameters in metres, consistent with the observed coordinate extents.

Densities below use counts from retained original returns divided by their XY
convex-hull area. Hull vertices are archived. This explicit observed footprint
spans interior gaps and is not an independently recovered census boundary.
The source combines three scanners; first-return counts are not a separately
verified emitted-pulse inventory. Rounded published areas are retained in the
receipts for comparison, not used as the density denominator.

| Plot | Retained points | References | Footprint, m² | First returns/m² | All returns/m² |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1001 | 2,946,895 | 133 | 1,256.137 | 1,497.587 | 2,345.998 |
| 1005 | 2,956,697 | 87 | 1,962.988 | 1,234.674 | 1,506.223 |
| 1009 | 3,732,156 | 103 | 1,962.911 | 1,416.959 | 1,901.337 |
| 1013 | 3,552,014 | 28 | 1,963.157 | 1,411.467 | 1,809.338 |
| 1019 | 3,759,456 | 8 | 2,826.975 | 1,284.098 | 1,329.851 |
| 1020 | 3,428,729 | 62 | 2,825.565 | 1,083.166 | 1,213.467 |
| 1022 | 1,637,393 | 213 | 1,256.135 | 1,004.693 | 1,303.517 |
| 1024 | 3,318,817 | 62 | 1,962.153 | 1,297.146 | 1,691.416 |
| 1027 | 3,975,927 | 96 | 1,962.946 | 1,684.067 | 2,025.490 |
| 1031 | 3,137,853 | 49 | 1,962.769 | 1,320.646 | 1,598.687 |

These are native-density development inputs. They provide no evidence for
sparse-density routing or optical fusion. The historical geometry bridge's
placeholder return fields are not used for these measurements.

## Ground and Height Diagnostics

lidR 4.3.2 CSF defaults classify ground from all retained geometry, with
`last_returns=FALSE` and one thread. TIN normalization uses the existing default
edge extrapolator, `knnidw(3, 1, 50)`. No source semantic class is reused as a
ground label: FGI class 2 means buildings, and class 0 mixes ground with other
unassigned objects. No negative heights or inconvenient rows are discarded.

All ten normalizations completed within the declared 600-second limit per
plot. Preparation and diagnostics totaled about 95 seconds, excluding shared
preflight/replay hashing; this is one local CPU observation, not an inference
resource benchmark. All heights are finite, and no row was lost or reordered.
Up to 0.6284% of a plot's points lie outside its ground-point convex hull,
where TIN interpolation needs its edge extrapolator. The largest negative-AGL
fraction is 0.1559%; the largest fraction below -0.5 m is 0.0387%.

| Plot | Median max-AGL minus published height, m | Largest absolute difference, m |
| --- | ---: | ---: |
| 1001 | -0.169 | 0.486 |
| 1005 | -0.151 | 0.558 |
| 1009 | -0.166 | 0.628 |
| 1013 | -0.178 | 0.630 |
| 1019 | -0.122 | 0.271 |
| 1020 | -0.097 | 1.940 |
| 1022 | -0.119 | 0.654 |
| 1024 | -0.201 | 1.579 |
| 1027 | -0.112 | 0.294 |
| 1031 | -0.114 | 3.525 |

These are different height estimators. The
[published height procedure](https://arxiv.org/html/2511.00653v1#S3.SS3.SSS3)
uses local non-tree minima and rejects an isolated highest point when its gap
exceeds 0.25 m. The largest difference is tree 5 in plot 1031: its highest raw
Z is 11.756 m and its second-highest is 8.290 m. The local class-0 minimum is
1.186 m, giving the published 7.104 m height after the outlier rule. Its maximum
pointwise normalized height is 10.629 m. This explains most of the difference
without establishing the geometric terrain estimate's independent accuracy.

The preparation is structurally valid, but independent AGL accuracy remains
unverified. A future detection comparison must explicitly define how its apex
and height estimator relates to these references. Reference-derived heights
must never be inserted into model inputs, and published metadata must not be
silently substituted for inferred heights.

## Installed Checkpoint Provenance

Both existing checkpoints match their upstream artifacts. Inspection reads
serialized pickle opcodes as data; it never executes pickle payloads or loads
models. Read-only containers have no network, GPU or host-data mounts.

| Arm | Identity evidence | Training provenance limit |
| --- | --- | --- |
| ForestFormer3D | Local archive matches the [official release](https://doi.org/10.5281/zenodo.16742708) MD5; installed weights match its member SHA-256. | Embedded configuration names ForAINetV2. Committed upstream lists contain 47 training, 16 validation and 28 test entries, but are not an authenticated manifest of the checkpoint's entire training history. |
| SegmentAnyTree | Installed weights match the [Git LFS SHA-256 at the pinned source commit](https://github.com/SmartForest-no/SegmentAnyTree/blob/a3561ed8447bbb7938f059ba65a3e9c97d6e2ee9/model_file/PointGroup-PAPER.pt). | Embedded metadata names TreeinsFusedDataset and a density-augmentation directory; it contains no exhaustive training-plot inventory. |

The ForestFormer3D working split lists were rewritten by previous inference.
The audit preserves them and reads committed lists only as upstream evidence.
It records hashes of 56 tracked code/configuration/documentation files, the
source revision, working status and immutable image IDs. SegmentAnyTree's
image source commit matches its repository pin.

| Artifact | SHA-256 |
| --- | --- |
| ForestFormer3D checkpoint | `01037a648596832238ac72ea2f5eef87ceaf5aeb399e56ff4b760ba1ed1c777e` |
| SegmentAnyTree checkpoint | `0b4d74b4644e37a16f59008ad0f5c62894fc4d2d906f3abd803bbfc5b5dd803a` |
| ForestFormer3D image | `fd60f5cdc5ae880af13b339f4aa1f1e891a3809c7f39fb15d2b5ff04978799f3` |
| SegmentAnyTree image | `27ce258d8a5ab70bdc457523d373848d5065e7b8044d3ef7891ff9e53dee2bd2` |

FGI-EMIT training overlap remains **unknown**. Upstream identity and dataset
names do not prove plot-level independence. No new checkpoint, model version
or environment was installed.

## Reproduction and Verification

Use the existing Python environment with `laspy`, `numpy`, `scipy` and `PyYAML`,
plus R with `lidR`, `data.table` and `jsonlite`. Run from this checkout:

```sh
GPU=/path/to/lidar_tree_benchmarks/gpu
PYTHON="$GPU/.venv/bin/python"
ROOT=/path/to/work/external/fgiemit
OUT="$ROOT/development_inputs"
"$PYTHON" scripts/prepare_fgiemit_development.py --root "$ROOT" --out "$OUT"
"$PYTHON" scripts/prepare_fgiemit_development.py --root "$ROOT" --out "$OUT" --verify
python3 scripts/audit_fgiemit_checkpoints.py --gpu-root "$GPU" \
  --out "$ROOT/development_checkpoint_provenance_v2.json"
python3 scripts/audit_fgiemit_checkpoints.py --gpu-root "$GPU" \
  --out "$ROOT/development_checkpoint_provenance_v2.json" --verify
```

The original `development_declaration` is required and verified. Output paths
must be new. `--plots` permits only declared development IDs; a subset is
diagnostic and is marked incomplete. Failed attempts retain their files and
receipts; no automatic parameter changes, retries or reserve substitutions
occur. The full run follows a successful one-plot smoke in a separate directory.
The initial checkpoint receipt is also preserved; the final receipt adds
tracked-source hashes and committed split-list evidence.

Each prepared plot contains `geometry.las`, `reference.laz`, `normalized.laz`,
support/hull metadata, normalization logs and receipts, and per-tree height
diagnostics. The full manifest seals **81 outputs and 137 prior artifacts**,
in addition to the parent declaration's source/receipt checks. Replay passed.
The checkpoint provenance audit also passed independent replay.

- Full Python discovery: 31 tests, 29 passed; optional TreeAIBox and
  ForestFormer3D checkout tests skipped in the isolated worktree.
- Full R suite: passed. Existing skips cover the gated legacy-cylinder GPU
  smoke, lidR's unsupported empty-LAS fixture and the default Python's missing
  `plyfile`. The unavailable R package-index warning also remains.
- Real-data preparation: all ten development plots passed structural checks.
- README workflow, requirements and indexes are updated; repository-wide
  Markdown lint and whitespace checks pass before publication.

The next comparison still needs a fixed detector/score/calibration matrix,
an explicit height-reference contract, a policy for unresolved checkpoint
overlap, and measured model resource limits on development data. No held-out
result, ensemble benefit or production-readiness claim follows from this audit.
