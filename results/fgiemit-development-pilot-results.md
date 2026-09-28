# FGI-EMIT Bounded Development Pilot

This report records the three-plot pilot stage. The subsequent
[complete development comparison](fgiemit-development-comparison-results.md)
reuses its nine accepted cells unchanged and adds the remaining seven plots.

This pilot follows the frozen
[comparison contract](../docs/fgiemit-comparison-protocol.md), using development
plots 1001, 1019 and 1027 and the declared CHM-VWF, SegmentAnyTree and
ForestFormer3D order. The runner executes one cell at a time with a
3,600-second detector wall limit and stops on the first failure. Calibration
and reserve evaluation remain disabled. Upstream checkpoint overlap remains
unknown; these are conditional development observations.

The fresh attempt with binary exports completed all nine pilot cells. At that
stage, the ten-plot comparison and calibration were incomplete. The pilot
established execution and output admission on the three declared plots.

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
The adapter records before/after hashes of its two export-bookkeeping patches
and the auxiliary visualization-writer patch described below. The immutable
image and installed source checkout are preserved.

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

## Earlier Export Failure and Correction

The `development_pilot_v2` attempt accepted four cells, failed on its fifth,
and left four planned. SAT completed all 69 inference batches on plot 1019,
then crashed in the upstream semantic ASCII PLY writer before interpolation and
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
checkpoint or inference parameter was changed.

The subsequent `development_pilot_v3` attempt changes only three auxiliary
panoptic PLY writers from ASCII to binary little-endian encoding. Their arrays,
schemas and row order are unchanged, and native inference does not read these
visualization files back. This avoids the observed `numpy.savetxt` call path;
it does not establish the underlying intermittent Python failure's root cause.
The change was declared before inference, with no checkpoint or parameter
change. Every pilot cell is run afresh; no cells from earlier attempts are
reused or selected by score.

The installed-image CPU fixture exercises the actual three upstream writer
bodies. ASCII and binary outputs decode to identical coordinates, labels and
colors, including coincident rows, background -1 and the int16 boundary 32767.
Input arrays remain unchanged. An injected `savetxt` failure trips each original
writer while each binary writer succeeds. A 3,759,456-row synthetic binary
roundtrip also passes with the ASCII function disabled. These checks validate
the serialization change; fault injection is not a reproduction of the native
Python crash.

On plot 1001, the new SAT output has exactly the same 2,946,895 native instance
labels, source-row IDs and integer XYZ as the completed output from the
previous attempt. This is a direct real-data serialization check, not a claim
of bitwise repeatability for all stochastic model runs.

The stopped attempt is preserved, including its eight sealed execution files.
Its receipt was replayed independently from the historical code checkout.

## Observed Pilot Outcomes

Completed on 2026-09-25 on one NVIDIA GeForce RTX 5090 (32,607 MiB,
driver 595.84). All nine cells in `development_pilot_v3` passed output admission
and external scoring. There were nine successful-nonempty cells and no failed,
empty or unrun pilot cells. All six instance exports preserve every source row
and original integer coordinates, scales, offsets and return fields.
No earlier attempt supplied any prediction or score below.

Independent receipt replay passed after completion. The receipt seals
90 accepted output/log files, eight execution-code files and
273 inventoried prior metadata files, plus comparison/runtime parents.
Both earlier attempts and their original code snapshots remain intact.
The remaining 21 detector cells and all 50 calibration cells are still planned.

### Default Derived-AGL Apex Detection

Each row uses the unchanged 4 m XY / 5 m height matcher. These are per-cell
development observations; there is no pooled primary ranking.

| Plot | Arm | References | Predictions | TP | FP | FN | F1 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1001 | CHM-VWF | 133 | 38 | 36 | 2 | 97 | 0.4211 |
| 1001 | SAT | 133 | 109 | 96 | 13 | 37 | 0.7934 |
| 1001 | FF3D | 133 | 128 | 113 | 15 | 20 | 0.8659 |
| 1019 | CHM-VWF | 8 | 10 | 8 | 2 | 0 | 0.8889 |
| 1019 | SAT | 8 | 17 | 8 | 9 | 0 | 0.6400 |
| 1019 | FF3D | 8 | 14 | 8 | 6 | 0 | 0.7273 |
| 1027 | CHM-VWF | 96 | 40 | 33 | 7 | 63 | 0.4853 |
| 1027 | SAT | 96 | 85 | 73 | 12 | 23 | 0.8066 |
| 1027 | FF3D | 96 | 93 | 83 | 10 | 13 | 0.8783 |

### Instance Masks

Mask matching uses IoU 0.5 and the same fixed-filter masks as apex extraction.
Coverage is mean maximum IoU over every reference instance. PQ is a separate
segmentation statistic. CHM supplies no instance masks.

| Plot | Arm | TP | FP | FN | Precision | Recall | F1 | Coverage | PQ |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1001 | SAT | 77 | 32 | 56 | 0.7064 | 0.5789 | 0.6364 | 0.5538 | 0.5305 |
| 1001 | FF3D | 97 | 31 | 36 | 0.7578 | 0.7293 | 0.7433 | 0.7025 | 0.6510 |
| 1019 | SAT | 8 | 9 | 0 | 0.4706 | 1.0000 | 0.6400 | 0.9332 | 0.5972 |
| 1019 | FF3D | 8 | 6 | 0 | 0.5714 | 1.0000 | 0.7273 | 0.9951 | 0.7237 |
| 1027 | SAT | 66 | 19 | 30 | 0.7765 | 0.6875 | 0.7293 | 0.6669 | 0.6367 |
| 1027 | FF3D | 78 | 15 | 18 | 0.8387 | 0.8125 | 0.8254 | 0.7610 | 0.7289 |

Original A–D category recalls are shown as matched/reference counts.
Categories with no reference trees remain undefined.

| Plot | Arm | A | B | C | D |
| --- | --- | ---: | ---: | ---: | ---: |
| 1001 | SAT | 35/38 | 18/23 | 22/52 | 2/20 |
| 1001 | FF3D | 36/38 | 20/23 | 34/52 | 7/20 |
| 1019 | SAT | 8/8 | undefined (0 refs) | undefined (0 refs) | undefined (0 refs) |
| 1019 | FF3D | 8/8 | undefined (0 refs) | undefined (0 refs) | undefined (0 refs) |
| 1027 | SAT | 39/39 | 4/13 | 19/29 | 4/15 |
| 1027 | FF3D | 39/39 | 9/13 | 24/29 | 6/15 |

### Paired Height Diagnostics

Cells show TP / F1; diagnostic parentheses give changes from the default.
The retained instances and reference population are identical across profiles.
The default remains maximum AGL regardless of the diagnostic result. Mask
metrics above are unaffected by these height profiles.

| Plot | Arm | Maximum AGL | Isolated-top AGL | Historical raw Z |
| --- | --- | ---: | ---: | ---: |
| 1001 | SAT | 96 / 0.7934 | 97 / 0.8017 (+1 / +0.0083) | 97 / 0.8017 (+1 / +0.0083) |
| 1001 | FF3D | 113 / 0.8659 | 113 / 0.8659 (+0 / +0.0000) | 113 / 0.8659 (+0 / +0.0000) |
| 1019 | SAT | 8 / 0.6400 | 8 / 0.6400 (+0 / +0.0000) | 8 / 0.6400 (+0 / +0.0000) |
| 1019 | FF3D | 8 / 0.7273 | 8 / 0.7273 (+0 / +0.0000) | 8 / 0.7273 (+0 / +0.0000) |
| 1027 | SAT | 73 / 0.8066 | 74 / 0.8177 (+1 / +0.0110) | 73 / 0.8066 (+0 / +0.0000) |
| 1027 | FF3D | 83 / 0.8783 | 83 / 0.8783 (+0 / +0.0000) | 83 / 0.8783 (+0 / +0.0000) |

### Measured Resources

| Plot | Arm | Detector wall (s) | Peak host RSS (MiB) | GPU allocated peak (MiB) | GPU reserved peak (MiB) |
| --- | --- | ---: | ---: | ---: | ---: |
| 1001 | CHM-VWF | 3.9 | 678.8 | not used | not used |
| 1001 | SAT | 110.2 | 3157.3 | 605.9 | 888.0 |
| 1001 | FF3D | 548.5 | 4622.2 | 9954.4 | 13690.0 |
| 1019 | CHM-VWF | 4.8 | 945.6 | not used | not used |
| 1019 | SAT | 156.6 | 3216.5 | 383.4 | 406.0 |
| 1019 | FF3D | 222.6 | 4747.9 | 1706.7 | 2298.0 |
| 1027 | CHM-VWF | 4.8 | 920.2 | not used | not used |
| 1027 | SAT | 141.2 | 3204.2 | 515.8 | 666.0 |
| 1027 | FF3D | 473.5 | 5165.3 | 6180.1 | 7574.0 |

## Resource and Interpretation Limits

Detector wall time includes command startup, model staging, inference and
export. It excludes host-side scoring and receipt hashing; ForestFormer3D's
private source copy also precedes that timer. Host RSS is the maximum of the
native model process (the R process for CHM), not the sum of a process tree.
GPU peaks are PyTorch allocated/reserved memory, not total device use. Native
settings and checkpoint identities are unchanged; stochastic upstream runs
are not claimed to be bitwise reproducible.

The pilot completed three of ten development plots across all three arms.
Primary pooled comparisons and calibration remain unavailable
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
  Its three binary-writer comparisons, injected-failure checks and full-size
  synthetic roundtrip passed. Real plot 1019 also produced binary visualization
  headers and a complete 3,759,456-row native export.
- The isolated lasR build and installed-file replay passed. Its source revision
  is pinned; the earlier manually installed library remains unchanged.
- Independent replay verified all nine fresh cells, unchanged execution code
  and protected prior artifacts. The earlier stopped attempt also verified
  independently from its frozen historical code checkout.
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
OUT="$ROOT/development_pilot_v3"
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
