# ForestFormer3D Scene Assembly

Training-only comparison on 2026-09-15, following the
[predeclared protocol](../docs/forestformer-scene-assembly-protocol.md).
The experiment compares one native whole-scene invocation per plot against
the archived corrected outer-cylinder outputs from the
[adapter audit](frozen-transfer-audit-results.md).

## Scope and Identity

Only training plots 1001 and 1019 are used: 133 and eight reference trees,
respectively. The dense plot has A/B/C/D counts of 38/23/52/20; the sparse plot
has eight category-A trees. No held-out plot is inferred or rescored. The
separate declaration protects 1,713 files, including the complete prior audit
and training trees, earlier interrupted attempts, frozen test artifacts,
model resources, the preceding report and the new protocol.

The checkpoint remains `epoch_3000_fix.pth`, MD5
`c340ded5f01f0b03c2c717e0a0519323`, in the existing torch 2.7/CUDA 12.8 container.
Its image ID is
`sha256:fd60f5cdc5ae880af13b339f4aa1f1e891a3809c7f39fb15d2b5ff04978799f3`.
Native voxels remain 0.2 m, internal radius 16 m and nearest-neighbor row batch
2,048. No model, query count, score threshold, mask threshold or checkpoint is
selected using the new scores. The single-scene path is preferred only if its
resource and export contracts pass, regardless of individual metric changes.

The model consumes the same frozen geometry-only raw cloud as before. Its
complete saved PLY must match the staged point sequence. The adapter then
attaches labels and scores to the original LAS records, preserving integer
coordinates, scales and offsets. Each output has one explicit `ff3d_row` per
input row, `UserData=0`, native instance IDs shifted to positive integers and
zero background. Missing, repeated or invalid indices and coordinate changes
fail. Coincident coordinates remain distinct rows, including background rows;
the adapter performs no outer merge, score winner or nearest-neighbor fill.

### Retained Native Conflict Policy

The pinned model already uses source-row indices inside its scene assembly.
Its native mask suppression sorts candidates by descending score and rejects
a mask when more than 30% of its points are already occupied. An accepted
later mask writes all its rows, including overlap with an earlier mask, with
its own instance ID and score. Thus this is not a highest-score-per-point
winner rule. Equal-score candidates retain their input ordering in the sort;
GPU kernels and query sampling can still affect upstream candidate generation.
Unassigned rows remain background. This existing policy is unchanged.

Deterministic adapter row association does not establish bitwise repeatable
model predictions. Whole-scene context and internal traversal also differ
from repeatedly running outer clips, so this comparison cannot attribute all
score changes solely to removal of the former XY-apex merge.

## Resource and Export Result

Both native scenes completed on the existing RTX 5090 without a retry, outer
tiling fallback or new runtime adjustment. All 6,706,351 rows are present
exactly once. Integer XYZ, classification, scales and offsets match each
original prepared LAS exactly; alignment to the prepared input has zero error.
Frozen input preparation had already quantized reference coordinates: maximum
differences against the reference are 0.707 mm and 0.500 mm, within the fixed
1 mm indexed-alignment tolerance. No nearest-neighbor association is used.
Both outputs used the native route and neither exercised the empty-return
workaround. Original background rows remain part of the output substrate.

| Plot | Input/output rows | Native IDs before filters | Background rows before filters | Cell seconds | Peak allocated GiB | Peak reserved GiB |
|---|---:|---:|---:|---:|---:|---:|
| 1001 | 2,946,895 | 129 | 496,323 | 552.4 | 9.72 | 12.55 |
| 1019 | 3,759,456 | 14 | 3,391,437 | 226.3 | 1.67 | 2.14 |

Memory columns are PyTorch peaks during the native pass, not all allocations
in the process or device. Receipts also capture the process host-RSS high
water mark through native export validation, before final LAZ serialization.
Archived outer-cylinder cell times were 605.8 and 332.0 seconds. These are
single implementation observations, not matched latency trials or scalability
guarantees for larger scenes. The existing 3,600-second cell timeout was not
reached. The resource and full-row export contracts favor the whole-scene path
for the declared comparison; no retained outer-tiling design is needed here.

## Whole-Plot Metrics

The official point-set matcher uses IoU 0.5, the existing 40-point/1.5 m
prediction filters and original A-D annotations. Counts and sums are pooled
over the same 141 references, never over overlapping cylinders. All metrics
below are fractions. The sparse plot has no B-D references: those recalls are
undefined, not zero. The unchanged SAT control has pooled F1 0.629; this
training comparison is not a new architecture ranking or held-out result.

| Plot | Assembly | Predictions after filters | TP | FP | FN | Mask F1 | Coverage |
|---|---|---:|---:|---:|---:|---:|---:|
| 1001 | Archived outer cylinders | 78 | 59 | 19 | 74 | 0.5592 | 0.4349 |
| 1001 | Native whole scene | 126 | 98 | 28 | 35 | 0.7568 | 0.6995 |
| 1019 | Archived outer cylinders | 16 | 8 | 8 | 0 | 0.6667 | 0.9687 |
| 1019 | Native whole scene | 14 | 8 | 6 | 0 | 0.7273 | 0.9953 |

| Pooled assembly | TP / FP / FN | Precision | Recall | F1 | Coverage | Supplementary PQ |
|---|---|---:|---:|---:|---:|---:|
| Archived outer cylinders | 67 / 27 / 74 | 0.7128 | 0.4752 | 0.5702 | 0.4652 | 0.4785 |
| Native whole scene | 106 / 34 / 35 | 0.7571 | 0.7518 | 0.7544 | 0.7163 | 0.6669 |

The dense scene has 129 positive IDs before filters and removes three; the
sparse scene retains all 14. Archived stitched output had 80 and 16 positive
IDs before filters, removing two and zero. Native category-D matches rise from
one to seven of 20 on the dense training plot; 13 remain unmatched. There is
no category-D evidence from the sparse plot and no fresh held-out estimate.

### Common-Support Regions

All 25 archived cylinder supports and their reference truncation counts are
reused: nine dense regions and 16 sparse regions. Archived local and stitched
scores reproduce on all 50 rows before adding the 25 whole-scene diagnostic
rows. Each region uses identical reference rows across its three methods.

| Plot | Whole scene versus | Higher F1 | Equal F1 | Lower F1 | Both undefined |
|---|---|---:|---:|---:|---:|
| 1001 | Archived local cylinder | 7 | 0 | 2 | 0 |
| 1001 | Archived stitched/projected | 9 | 0 | 0 | 0 |
| 1019 | Archived local cylinder | 0 | 11 | 0 | 5 |
| 1019 | Archived stitched/projected | 7 | 4 | 0 | 5 |

The five undefined sparse regions contain neither references nor retained
predictions. Dense reference truncation ranges from nine to 45 instances per
region; the sparse range is zero to four. On the dense central support of
1,999,610 points and 111 reference instances, 45 are truncated. Local-cylinder
output has 62 TP and F1 0.6392; stitched output has 49 TP and F1 0.5537; the
whole-scene output has 73 TP and F1 0.7157. These overlapping observations are
not pooled as independent plots or used to select an operating point.

This removes the systematic dense-region degradation relative to stitched
output, but is not a universal gain over local cylinders. Different model
context and internal traversal remain confounded with removal of outer
assembly. The two local-cylinder advantages are retained, not tuned away.

### Identity, Background and Errors

| Plot | Assembly | Output rows | Duplicate-XYZ groups | Groups with conflicting labels |
|---|---|---:|---:|---:|
| 1001 | Archived outer cylinders | 6,138,593 | 2,487,932 | 338,457 |
| 1001 | Native whole scene | 2,946,895 | 671 | 0 |
| 1019 | Archived outer cylinders | 7,850,485 | 3,165,706 | 40,447 |
| 1019 | Native whole scene | 3,759,456 | 414 | 0 |

The remaining coincident coordinates are separate original rows, retained
with explicit identity; their labels happen to agree in these runs. Synthetic
tests retain different labels, including background, on coincident rows.
The former cross-cylinder union-find step is absent, so it cannot transitively
collapse two local identities through a third outer cylinder. This does not
mean that the model never merges distinct physical trees.

The following post-filter diagnostics use the preceding audit's definitions.
Split/merge edges require at least 10% overlap of both instances; apex matching
is a separate one-to-one 4 m XY/5 m Z diagnostic, not mask IoU.

| Plot | Assembly | Split references | Merged predictions | Background-majority predictions | Apex TP | Apex F1 |
|---|---|---:|---:|---:|---:|---:|
| 1001 | Archived outer cylinders | 6 | 21 | 4 | 74 | 0.7014 |
| 1001 | Native whole scene | 7 | 13 | 11 | 111 | 0.8571 |
| 1019 | Archived outer cylinders | 1 | 0 | 6 | 8 | 0.6667 |
| 1019 | Native whole scene | 0 | 0 | 6 | 8 | 0.7273 |

Dense assigned-point fraction rises from 80.84% to 83.15%; assigned tree-point
recall rises from 95.23% to 97.97%. Background is 1.040% versus 1.021% of assigned
points. Sparse assigned-point fraction is 9.80% versus 9.79%; tree-point recall
is 99.972% versus 99.982%, with background 1.530% versus 1.369% of assigned
points. Full row coverage is not full tree assignment or correct segmentation.
Dense false positives rise from 19 to 28, and its split and background-majority
counts worsen despite higher precision, recall and F1. No claim of universal
error reduction is supported.

## Eligibility and Next Work

The redundant outer adapter's identity and projection failure mode is removed
from the indexed whole-scene path. Whole-plot accuracy improves on both
declared training plots. This clears the assembly gate for ForestFormer3D as
an **optional candidate for controlled ensemble comparison**, using this
whole-scene contract and fresh confidence features. It does not establish a
default ensemble member, calibrated probabilities, fusion benefit, strong
understory transfer, fresh held-out mask quality, or production readiness.

Keep the historical outer-cylinder route for reproduction, not admission under
the new evidence. Larger scenes still need a separately declared resource or
tiling assessment if they exceed this path's contract. The retained native
overlap policy, context effects and single-run GPU variability remain limits.
TreeisoNet stays deferred; SAT and classical controls remain relevant.

The proposed HARV/BART follow-on is [retired](../docs/harv-bart-closeout.md).
The next implementation is synthetic detection-only pipeline contracts with
explicit arms and compatibility guards, not an eastern-site comparison.
New real-data work needs separately declared development data, eligible
reference support, whole-plot folds and held-out evaluation. Never tune on the
already observed FGI-EMIT test set. A simpler single-arm product remains valid
if fusion adds no supported benefit. Crown promotion needs genuine crown or
instance annotations and its own held-out evidence.

## Reproduction and Artifacts

First reproduce the acquisition, frozen preparations and corrected outer
outputs described in the [adapter audit](frozen-transfer-audit-results.md#reproduction-and-artifacts).
Use the same existing model checkout, checkpoint and image, plus the official
evaluator environment described in the
[external study](fgi-emit-external-results.md). The implementation worktree
must have access to the documented `gpu/store` resources. No new installation
or model version is needed.

```sh
export CLAUDE_JOB_DIR=/path/to/work
ROOT="$CLAUDE_JOB_DIR/external/fgiemit"
EVAL_PYTHON=/path/to/existing/evaluator/bin/python
python3 gpu/declare_scene_assembly.py --root "$ROOT"
Rscript scripts/audit_scene_assembly.R MODE=infer ROOT="$ROOT" \
  EVAL_PYTHON="$EVAL_PYTHON"
Rscript scripts/audit_scene_assembly.R MODE=analyze ROOT="$ROOT" \
  EVAL_PYTHON="$EVAL_PYTHON"
python3 gpu/declare_scene_assembly.py --root "$ROOT" --verify
```

Create the declaration once, before inference; an existing declaration cannot
be overwritten. Successful inference is reusable only with matching source,
prepared-input, container and output provenance. Unreceipted attempts fail
closed and must be preserved for investigation, not automatically rerun with
an outer-cylinder fallback. The driver accepts only training plots 1001/1019.
Run both plots for the declared pooled comparison; a subset is diagnostic only.

Generated files live under `work/external/fgiemit/scene_assembly/`:

- `declaration.json` seals the protocol and protected prior artifacts.
- `run_manifest.{rds,json}` records source/configuration hashes, prepared
  inputs, package versions, layout, model and container identity.
- `runs/<plot>/forestformer3d/predictions.laz` contains indexed native rows;
  its JSON stores correspondence and resource observations. Receipt files
  record successful output hashes and elapsed cell time.
- `analysis/scores.csv` and `summary.csv` contain full-plot and pooled metrics;
  `cylinders.csv` contains common-support diagnostics, not independent plots.
- `analysis/contracts.csv`, `duplicates.csv` and `confidence_features.csv`
  record export/resource checks, coordinate ambiguity and fresh native scores.
- `analysis/instances/` and `official_*.json` preserve aligned filtered clouds
  and official checks per plot and pooled. `analysis_manifest.json` identifies
  analysis sources, inference receipts and output hashes.

Confidence features include point count, mean/minimum/maximum native score,
cloud apex and a retained-after-filter flag. They are new features, not fitted
probabilities. No deployment lookup is overwritten or calibrated on these
audit labels. Later calibration must use declared development folds and the
correct score target; apex-match calibration is not mask-IoU calibration.
There are 143 fresh instance-feature rows: 129 dense and 14 sparse, including
the three dense instances removed by the unchanged scoring filters.

## Verification

- Both native GPU runs completed; independent LAS round trips verified exact
  prepared integer coordinates, classification, scales, offsets and row IDs.
- All 42 defined official metric checks passed across four per-plot and two
  pooled rows. The six absent B-D plot/arm recalls remain explicitly undefined.
  The two full-plot archived controls and 50 local/stitched region rows reproduce.
- All 1,713 protected SHA-256 hashes passed before and after inference and
  analysis. Analysis source and all 16 output hashes were checked separately.
- Cache replay validated both successful receipts without inference or receipt
  modification. Prior test, audit and calibration artifacts remain unchanged.
- The full R suite passes, including 31 scene-assembly assertions. Three
  existing skips remain: gated legacy-cylinder GPU smoke, an empty LAS fixture
  unsupported by lidR's writer, and the default Python's missing `plyfile`.
  An existing optional R repository lookup warns when network access is absent.
- All 14 transfer-export Python tests and two reference-export tests pass in
  the existing environment. Tests include the pinned native overlap function,
  exact empty/nonempty LAZ round trips and duplicate/background identities.
- Reading archived outer LAZs warns about their zero return-number metadata.
  These historical fields are not model/scoring inputs here and were not
  rewritten; comparisons use validated XYZ, instance IDs and reference labels.
- README results, eligibility, workflow, requirements and indexes were reviewed
  and updated where affected. Full-repository Markdown lint and whitespace
  checks pass before publication; no new dependency installation is required.
