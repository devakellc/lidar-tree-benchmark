# FGI-EMIT Frozen Development Policy

Frozen on 2026-09-25 after the complete native-density detector comparison
and whole-plot calibration, before reserve point validation or inference.
This policy makes a development selection. It does not establish independent
unseen-data performance. See the
[overlap assessment](../results/fgiemit-checkpoint-overlap-results.md).

## Selection and Products

Select **ForestFormer3D through the indexed whole-scene adapter** for both
maximum-AGL apex detection and genuine instance-mask delineation. Keep their
scores and output products distinct. Use the exact installed checkpoint,
container, native configuration and adapter identities sealed by the
[complete comparison](../results/fgiemit-development-comparison-results.md).
Its development apex F1 is 0.8091 and mask F1 is 0.7133, above the other
admitted arms on the same ten plots and 841 references. This is selection
after development results, not a predeclared winner or an unseen-data claim.

Retain all masks passing the existing 40-point and 1.5 m raw-Z extent filters.
Preserve the upstream native assignment policy and background zero. Add no
confidence cutoff, top-k limit, density router, ensemble fusion, model tuning
or crown refinement. Keep the raw native confidence feature as provenance;
do not apply validation-fold probability mappings to future plots.

The [calibration study](../results/fgiemit-development-calibration-results.md)
provides out-of-fold reliability evidence, with explicit unsupported scores.
It does not select an operating threshold. This policy fits no new calibrator
and exports no all-development probability lookup. A later probability product
would require its own frozen fit, target, training support and validation plan.

## Fixed Prospective Comparison

Keep reserve plots **1003, 1010 and 1023**, in that order, with 54, 155 and
48 published references respectively: 257 total. Preserve historical plots
1002, 1004, 1008, 1012, 1018 and 1028 as already observed results. No reserve
replacement or retrospective inclusion in development is allowed.

The bounded plan has nine detector cells: CHM-VWF, SegmentAnyTree and
ForestFormer3D sequentially on each reserve plot. CHM-VWF and SegmentAnyTree
remain fixed controls; they are not ensemble members or fallback choices.
The primary policy remains ForestFormer3D regardless of reserve outcomes.
There are nine primary apex-scoring cells and six mask-scoring cells.
Preserve the two symmetric height diagnostics as separate robustness checks.

Prepare reserve inputs using the unchanged
[development input contract](fgiemit-input-validation-protocol.md): classes
0–4, every annotated tree, complete source-row and original-return identity,
plot-local metric frames without an invented EPSG, and geometric AGL with
the same ground/normalization settings. Validate annotation support, finite
normalization and every reference count before model execution.

Measure retained-support first-return and all-return densities independently.
Header counts over rounded published areas do not admit CHM parameters or
establish native support. Derive the CHM configuration through the sealed
`chm_parameters(frdens, pdens)` rule. No thinning, upsampling or sparse-density
extrapolation is included. Native instance configurations remain unchanged.

Place all new reserve preparation, execution and scoring artifacts in a new
job root **outside the sealed development data root**. The original audit
checks that root for reserve processing and must remain replayable. Do not
edit its admission flags or bypass its protections to admit a new stage.
Future reserve receipts must bind this policy, the original source hashes and
their separate prepared inputs without changing any earlier receipt.

## Execution and Failure Handling

Before inference, seal the validated reserve inputs and an execution contract
binding every planned cell to its source/configuration identities. The policy
freeze itself reads no reserve point records and authorizes no execution.
Its manifest records all nine cells as requiring input validation.

Use one cell at a time, one attempt per cell and a 3,600-second wall limit.
Stop at the first failed execution or output contract. Preserve its logs and
all completed cells. Report every failed, missing, planned, successful-empty
and successful-nonempty cell explicitly. No automatic retries, changed
checkpoint, parameter rescue, fallback tiling or substitution is allowed.
Any necessary implementation change requires a separate documented attempt;
do not select the best of multiple scored reserve attempts.

Reserve plot 1023 has 5,510,572 source points, more than any development input.
That header count is a resource warning based on observed size, not proof of
failure. It does not justify thinning, splitting the outer scene or dropping
the plot. Preserve native internal region handling and the original indexed
export contract. Unit tests do not demonstrate reserve hardware feasibility.

## Metrics and Claims

Use the existing maximum-AGL reference and prediction rules, 4 m XY/5 m
height-gated one-to-one matcher, and mask IoU 0.5 matcher. Keep A–D reference
categories and their recall denominators. Mask coverage and PQ remain
separate from apex precision, recall and F1. Preserve all fixed-filter
predictions, including those with unsupported calibration scores.

Report per-plot counts and count-pooled metrics over the complete declared
population. Primary cross-arm comparisons require all applicable cells.
Failure is not zero predictions; incomplete support gives status and exact
denominators, without a primary ranking. Any common-subset result must be
labelled diagnostic and list every exclusion. With only three reserve plots,
use per-plot variation and pooled descriptive contrasts; do not promote a
three-plot bootstrap interval to a primary uncertainty claim or copy the
ten-plot development intervals onto reserve results.

The overlap review finds different documented dataset geographies, but no
exhaustive training-history manifest for the exact installed weights.
Upstream overlap remains **unknown**. The prospective claim, once structural
and execution admission pass, is **conditional within-dataset evaluation of
a development-selected policy**. It can test choices frozen in this repository;
it cannot establish that the models never encountered these plots elsewhere.
No independent unseen-data, cross-site, sparse-density or fusion claim is
enabled. Known overlap discovered later must be reported and reassessed,
not hidden by renaming the reserve or changing the checkpoint silently.

## Freeze and Verification

`freeze_fgiemit_policy.py` requires the sealed complete detector summary,
50-cell calibration receipt and archived primary-source evidence. It checks
all parents, checkpoint/release identities and exact split metadata, then
writes `policy.json`, `reserve_plan.csv` and `freeze.json` into a fresh
directory. The receipt seals the policy code, this protocol, source manifest,
parent identities and output hashes. Verification recomputes the exact policy
and checks the archived evidence. Creation or replay never executes a model,
reads reserve point records, mutates previous artifacts or opens the reserve.
