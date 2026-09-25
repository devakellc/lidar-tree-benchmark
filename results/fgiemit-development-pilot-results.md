# FGI-EMIT Bounded Development Pilot

This pilot follows the frozen
[comparison contract](../docs/fgiemit-comparison-protocol.md), using development
plots 1001, 1019 and 1027 and the declared CHM-VWF, SegmentAnyTree and
ForestFormer3D order. The runner executes one cell at a time with a
3,600-second detector wall limit and stops on the first failure. Calibration
and reserve evaluation remain disabled. Upstream checkpoint overlap remains
unknown; these are conditional development observations.

The corrected attempt stopped after four accepted cells and a SAT export
failure. Four pilot cells remain unrun; this is an incomplete comparison.

## Pilot Support

Every arm uses the same retained rows at native density. Densities below are
original first/all returns per square metre of the retained XY convex hull.
Frames are plot-local metric coordinates with local elevations; no EPSG is
invented. Background and original edge/dead reference trees remain included.

| Plot | Retained points | References | First-return density | All-return density |
| --- | ---: | ---: | ---: | ---: |
| 1001 | 2,946,895 | 133 | 1,497.59 | 2,346.00 |
| 1019 | 3,759,456 | 8 | 1,284.10 | 1,329.85 |
| 1027 | 3,975,927 | 96 | 1,684.07 | 2,025.49 |

There are 10,682,278 unique retained points and 237 reference trees in this
pilot. The remaining development plots are 1005, 1009, 1013, 1020, 1022, 1024
and 1031: 604 reference trees and 21 detector cells outside this attempt.
None of the 50 declared calibration cells is fitted by this runner.

## Runtime and Point Correspondence

The classical arm uses an isolated build of
[`r-lidar/lasR@pre-devel`](https://github.com/r-lidar/lasR/tree/97dd5fb85fada7de0dbd024246751a9941daedaf),
revision `97dd5fb85fada7de0dbd024246751a9941daedaf`. Its source archive SHA-256
is `cc37ff380542d487b5ec152129f518c366a91f88932b2aa79521e1b2e2b4d129`.
The build receipt hashes all installed package files and probes the required
variable-window constructor. Only classical detector subprocesses select
this library; the existing R installation and earlier receipts remain intact.
The measured-density CHM resolution, smoothing, window and height threshold
are unchanged from the declaration.

The GPU arms retain the installed checkpoint and immutable image identities
verified during [input preparation](fgiemit-development-input-results.md).
Containers have no network and receive only their plot's prepared geometry,
adapter code and private output directory. ForestFormer3D receives a private
copy of its model source and a read-only checkpoint. Reference annotations
are read by scoring outside model containers.

The initial `development_pilot` attempt was interrupted during review because
its output-directory mount also exposed the reference-apex CSV. The model
drivers did not read that CSV, but visibility violated the annotation-isolation
contract. Its outputs and original code snapshot are preserved with an
`admission-review.json` marking every result ineligible. Five cells had reached
scoring and the sixth was interrupted. None is reused or selected by score.
The corrected `development_pilot_v2` attempt mounts only a fresh `model_io`
child directory; scoring references remain outside every container mount.
A regression test checks this boundary for both model arms with an actual
reference file present beside that child directory. Live inspection of both
model containers also confirmed the restricted mounts, absent reference CSV
and disabled networking.

SegmentAnyTree's full-cloud tracker already calculates labels for every raw
point, including background. The new adapter adds a row-index attribute during
raw-data construction and captures these existing labels before the final
visualization drops background. It checks that every retained row is present
exactly once, in order, with the exact float32 localized XYZ used by SAT.
Labels are then written onto the original integer-coordinate LAS rows, keeping
their scales, offsets, original return fields and `source_row` IDs.

This changes export bookkeeping only. SAT's native interpolation, one-metre
distance gate, semantic background assignment and native small-instance filter
remain unchanged. The benchmark subsequently applies its frozen 40-point and
1.5 m raw-Z-extent filter, identically for mask and apex scoring. No external
nearest-neighbor projection or coordinate-string merge establishes support.
The adapter records before/after hashes of its two export-only source patches;
the immutable image and installed source checkout are preserved.

The CPU fixture reproduces the historical merge's duplicate-row problem: four
input rows become six after coordinate-string outer joins. The new native
export keeps exactly four rows, including two coincident points with different
labels and background. The check uses the installed localization, source reader
and raw-cloud fusion code; it supplies no reference features or model weights.

ForestFormer3D retains its existing indexed whole-scene exporter and native
mask policy. The runner rejects incomplete rows, changed coordinates/returns,
multiple outer scenes, invalid confidence or nonzero background confidence.
For both instance arms, failed admission produces a failed cell, never a
fabricated empty prediction set. Exact coincident points retain distinct row
identities and can carry distinct labels.

Accepted instance masks use the same source-row AGL reducer as references.
All three declared height profiles are scored with the existing FGI matcher;
the unchanged IoU matcher scores masks separately. The full reference
population stays in each denominator. A successful empty cell and a failed
cell have distinct recorded states. Missing/planned cells are explicit.
Upstream console metrics use dummy labels for inference-only scenes; reported
benchmark metrics come exclusively from the external annotated scoring step.

## Observed Pilot Outcomes

Run on 2026-09-25 on one NVIDIA GeForce RTX 5090 (32,607 MiB,
driver 595.84). Four cells passed output admission and external scoring.
SAT on plot 1019 failed; the remaining four pilot cells stayed planned.
There were no successful-empty cells. The pilot is incomplete and expansion
is stopped. Both accepted instance exports preserve every source row and
original integer coordinates, scales, offsets and return fields.

| Plot | CHM-VWF | SAT | FF3D | References per arm |
| --- | --- | --- | --- | ---: |
| 1001 | Successful, nonempty | Successful, nonempty | Successful, nonempty | 133 |
| 1019 | Successful, nonempty | Failed export | Planned, not run | 8 |
| 1027 | Planned, not run | Planned, not run | Planned, not run | 96 |

Independent receipt replay passed after the stop. The receipt seals
43 cell files, including accepted predictions/scores and failure logs,
eight execution-code files and 232 inventoried prior metadata files,
plus comparison/runtime parents. The rejected first attempt remains intact.

### Failure Investigation

SAT completed all 69 inference batches on plot 1019, then crashed in the
upstream semantic ASCII PLY writer before full instance interpolation and
our native export hook. `numpy.savetxt` raised
`TypeError: cannot create 'WriteWrap' instances`; Python subsequently failed
its `type_traverse` assertion during shutdown. The model process exited 134,
its wrapper exited 1, and the detector command took 170.6 seconds.
No complete native row/label receipt or admitted prediction file exists for
this cell. Partial visualization files are retained as failure evidence and
are never scored. Peak memory for this failed cell is unavailable.

A bounded CPU-only check in the unchanged image wrote a synthetic
3,759,456-row PLY with the same XYZ/prediction/reference-field schema through
the same ASCII writer. It completed in 37.3 seconds with NumPy 2.2.5.
This did not reproduce the crash or establish its root cause. No package,
checkpoint, inference parameter or export policy was changed to force a pass.

The next execution step is to isolate the writer failure in the inference
context and validate any correction before declaring a fresh pilot attempt.
This attempt is preserved without retry or mixing results from another run.
Only plot 1001 has common completed support across all three arms; plot 1019
has only a CHM result. The full matrix still has 26 cells without accepted
results: one failed, four unrun pilot cells and 21 outside-pilot cells.

### Default Derived-AGL Apex Detection

Each row uses the unchanged 4 m XY / 5 m height matcher. These are per-cell
development observations; there is no pooled primary ranking.

| Plot | Arm | References | Predictions | TP | FP | FN | F1 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1001 | CHM-VWF | 133 | 38 | 36 | 2 | 97 | 0.4211 |
| 1001 | SAT | 133 | 109 | 96 | 13 | 37 | 0.7934 |
| 1001 | FF3D | 133 | 126 | 113 | 13 | 20 | 0.8726 |
| 1019 | CHM-VWF | 8 | 10 | 8 | 2 | 0 | 0.8889 |

### Instance Masks

Mask matching uses IoU 0.5 and the same fixed-filter masks as apex extraction.
Coverage is mean maximum IoU over every reference instance. PQ is a separate
segmentation statistic. CHM supplies no instance masks.

| Plot | Arm | TP | FP | FN | Precision | Recall | F1 | Coverage | PQ |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1001 | SAT | 77 | 32 | 56 | 0.7064 | 0.5789 | 0.6364 | 0.5538 | 0.5305 |
| 1001 | FF3D | 100 | 26 | 33 | 0.7937 | 0.7519 | 0.7722 | 0.7021 | 0.6683 |

Original A–D category recalls are shown as matched/reference counts.
Categories with no reference trees remain undefined.

| Plot | Arm | A | B | C | D |
| --- | --- | ---: | ---: | ---: | ---: |
| 1001 | SAT | 35/38 | 18/23 | 22/52 | 2/20 |
| 1001 | FF3D | 38/38 | 19/23 | 36/52 | 7/20 |

### Paired Height Diagnostics

Cells show TP / F1; diagnostic parentheses give changes from the default.
The retained instances and reference population are identical across profiles.
The default remains maximum AGL regardless of the diagnostic result. Mask
metrics above are unaffected by these height profiles.

| Plot | Arm | Maximum AGL | Isolated-top AGL | Historical raw Z |
| --- | --- | ---: | ---: | ---: |
| 1001 | SAT | 96 / 0.7934 | 97 / 0.8017 (+1 / +0.0083) | 97 / 0.8017 (+1 / +0.0083) |
| 1001 | FF3D | 113 / 0.8726 | 113 / 0.8726 (+0 / +0.0000) | 113 / 0.8726 (+0 / +0.0000) |

### Measured Resources

| Plot | Arm | Detector wall (s) | Peak host RSS (MiB) | GPU allocated peak (MiB) | GPU reserved peak (MiB) |
| --- | --- | ---: | ---: | ---: | ---: |
| 1001 | CHM-VWF | 3.9 | 678.5 | not used | not used |
| 1001 | SAT | 173.4 | 3141.0 | 605.9 | 888.0 |
| 1001 | FF3D | 549.7 | 4634.2 | 9956.7 | 12314.0 |
| 1019 | CHM-VWF | 4.7 | 945.6 | not used | not used |

## Resource and Interpretation Limits

Detector wall time includes command startup, model staging, inference and
export. It excludes host-side scoring and receipt hashing; ForestFormer3D's
private source copy also precedes that timer. Host RSS is the maximum of the
native model process (the R process for CHM), not the sum of a process tree.
GPU peaks are PyTorch allocated/reserved memory, not total device use. Native
settings and checkpoint identities are unchanged; stochastic upstream runs
are not claimed to be bitwise reproducible.

The pilot declares three of ten development plots; only plot 1001 completed
all three arms. Primary pooled comparisons and calibration remain unavailable
until the full declared support is complete. Apex matching is an annotated
point-cloud proxy using shared geometric AGL, whose independent accuracy is
unverified. Unknown upstream training overlap prevents an unseen-data claim.
The three reserve plots remain closed.

## Verification

- Full Python discovery passed: 47 tests, 45 passed and two optional upstream
  checkout tests skipped in the isolated worktree. New coverage includes
  coincident points, background labels/scores, missing and permuted rows,
  coordinate/return preservation, fixed-filter boundaries, actual R mask/apex
  scoring, stopping after failure without inventing an empty result, and local
  process-group termination on timeout.
- Full R suite passed with three existing skips: the gated legacy-cylinder
  GPU smoke, unsupported empty-LAS fixture and default Python's missing
  `plyfile`. The existing package-index network warning remains.
- The SAT CPU staging/merge reproduction passed in the installed model image.
- The isolated lasR build and installed-file replay passed. Its source revision
  is pinned; the earlier manually installed library remains unchanged.
- Independent pilot replay verified accepted outputs, the failed/planned state
  sequence, unchanged execution code and protected prior artifacts.
- README workflow, requirements and indexes, and the SAT adapter documentation
  are updated. Repository-wide Markdown and whitespace checks passed on the
  final worktree before publication.

## Reproduction

Use the existing Python environment, model images and checkpoints. The local
lasR repository must contain the pinned source commit; building installs no
new dependencies and does not replace the normal R library.

```sh
PYTHON=/path/to/lidar_tree_benchmarks/gpu/.venv/bin/python
ROOT=/path/to/work/external/fgiemit
RUNTIME=/path/to/work/fgiemit-pilot-runtime
"$PYTHON" scripts/prepare_fgiemit_pilot_runtime.py \
  --lasr-repo /path/to/lasR --out "$RUNTIME"
"$PYTHON" scripts/prepare_fgiemit_pilot_runtime.py --out "$RUNTIME" --verify
OUT="$ROOT/development_pilot_v2"
"$PYTHON" scripts/run_fgiemit_pilot.py \
  --root "$ROOT" --out "$OUT" --runtime "$RUNTIME"
"$PYTHON" scripts/run_fgiemit_pilot.py \
  --root "$ROOT" --out "$OUT" --runtime "$RUNTIME" --verify
```

Creation requires new runtime and pilot directories. The runner checks the
original comparison receipt before execution and on replay. Its receipt seals
runtime and comparison parents, prior artifacts, execution code, accepted
predictions, metrics and logs. Model scratch data remain in the attempt root.
Replay validates recorded states and hashes; it does not turn a failed or
incomplete pilot into a completed comparison. Inspect `complete_pilot` and
the per-cell states in `pilot.json` before considering any expansion.
A timed-out cell stops its own Docker container and local process group.
Failed attempts are preserved; implementation changes require a new root.

The CPU-only SAT staging and historical-merge check runs inside the existing
image with a four-point fixture, without model loading or GPU access:

```sh
GPU_CODE="$PWD/gpu"
docker run --rm --network none --cap-drop ALL \
  --security-opt no-new-privileges \
  -v "$GPU_CODE:/adapter:ro" \
  -e PYTHONPATH=/adapter/sat_compat:/adapter:/opt/segment-any-tree \
  --entrypoint python3 \
  sha256:27ce258d8a5ab70bdc457523d373848d5065e7b8044d3ef7891ff9e53dee2bd2 \
  /adapter/check_fgiemit_sat_staging.py
```

The separate synthetic ASCII-writer probe used no model or source data:

```sh
docker run --rm --network none -i --entrypoint python3 \
  sha256:27ce258d8a5ab70bdc457523d373848d5065e7b8044d3ef7891ff9e53dee2bd2 - <<'PY'
import time
import numpy as np
from plyfile import PlyData, PlyElement
n = 3759456
v = np.zeros(n, dtype=[('x', 'f4'), ('y', 'f4'), ('z', 'f4'),
                       ('preds', 'i2'), ('gt', 'i2')])
v['x'] = np.arange(n, dtype=np.float32) * .0001
v['y'] = 8
v['z'] = 1
started = time.monotonic()
PlyData([PlyElement.describe(v, 'vertex')], text=True).write('/tmp/probe.ply')
print(n, np.__version__, time.monotonic() - started)
PY
```
