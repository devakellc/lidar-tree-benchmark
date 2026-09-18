# ForestFormer3D Scene Assembly Protocol

Declared before new inference. This bounded follow-up compares native
whole-scene inference with the archived redundant outer-cylinder adapter.
It is an integration experiment, not model selection or a new held-out test.

## Fixed Scope

- Use only FGI-EMIT training plots 1001 and 1019, the same 141 reference trees
  as the [adapter audit](../results/frozen-transfer-audit-results.md).
- Reuse the audited checkpoint, container, native 0.2 m voxels, radius 16 m,
  inner-region traversal, query count, score/mask thresholds, and exact
  nearest-neighbor row batch of 2,048. Do not alter the upstream model.
- Read the archived corrected outer-cylinder outputs as the baseline. Do not
  rerun or overwrite the previous audit, training controls, or six-plot test.
- Run one whole-scene invocation per training plot using the same prepared
  geometry-only raw cloud. Preserve original input order, integer coordinates,
  scales, offsets, background and native per-point confidence on export.
- Record source, model, configuration, input, container and output provenance.
  Seal prior artifacts and this protocol before inference. New outputs live
  separately under `work/external/fgiemit/scene_assembly/`.

## Identity and Conflict Policy

The native model already assembles its internal overlapping regions using
source-row indices, score-ordered mask suppression and its existing overlap
policy. Retain that policy unchanged and record its limitations; do not claim
bitwise repeatability across GPU kernels or random query sampling.

The adapter must consume the complete saved scene, validate the staged input
and returned coordinate sequence, and carry an explicit zero-based source-row
identifier into the output. Exactly one record is permitted per source row.
Coincident coordinates do not identify the same input row. At the adapter
boundary there is no additional cross-cylinder merge, confidence winner,
background fill, or nearest-neighbor projection. Invalid or missing row IDs,
coordinate disagreement, or incomplete output are failures, not empty runs.

Prefer this path if it satisfies the resource and export contracts, regardless
of whether every score improves. Outer tiling remains a historical comparator,
not an automatic fallback. If native whole-scene inference fails its resource
contract, retain the failure and stop for a separately declared deterministic
tiling experiment; do not choose a fallback or threshold by observed scores.

## Comparisons and Metrics

- Report both whole-plot outputs against identical reference rows using the
  existing official IoU 0.5 matching, 40-point/1.5 m prediction filters,
  Coverage, supplementary PQ and the original A-D categories.
- Verify official precision, recall, F1, Coverage and A-D recalls, per plot and
  pooled. Pool counts and sums over plots, never overlapping cylinders.
- Reuse the prior local-cylinder/common-support diagnostic regions. Compare
  archived local and stitched predictions with the whole-scene result on each
  identical region; retain reference truncation counts. Separate changes in
  model context from removal of adapter assembly and projection.
- Report pre/post-filter instance counts, assigned/background support,
  overlap-based split/merge errors, cloud-apex matches (4 m XY, 5 m Z),
  duplicate-coordinate conflicts, row completeness, and runtime/resource use.
- Export fresh per-instance confidence features from the whole-scene output
  and their source provenance. Do not overwrite or fit deployment calibrators
  using these audit labels. Any later calibration uses declared development
  folds and a compatible score target.

## Completion and Limits

Regressions must cover vertical overlap, the historical transitive
same-cylinder collision, duplicate XYZ with distinct row identities,
background conflicts, permuted/missing/duplicate rows, coordinate restoration,
and valid empty/full-scene exports.

Record whether assembly degradation is resolved, reduced or remains uncertain,
and the resulting eligibility for controlled comparisons. Standalone training
F1 does not demonstrate fusion benefit, strong understory transfer, crown
quality on a fresh holdout, or production readiness. The originally proposed
HARV development and BART validation follow-on is now
[retired](harv-bart-closeout.md); it is not an active assembly dependency.
Review README and run final full-repository Markdown lint before publication.
