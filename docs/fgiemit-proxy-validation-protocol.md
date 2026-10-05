# FGI-EMIT proxy-mask validation protocol

Declared on 5 October 2026, before any proxy mask was built or scored. NEON
mask scores use a proxy reference: canopy points assigned to the nearest
mapped stem within its crown radius (Voronoi on stems). Against FGI-EMIT's
true per-point labels, ForestFormer3D reaches mask F1 0.71 on the development
plots; against the NEON proxy it reaches 0.14. This study measures how much
of that gap the proxy itself can cause, by building the same proxy on
FGI-EMIT and scoring the same predictions against both references.

## Scope

- The ten development plots only (1001, 1005, 1009, 1013, 1019, 1020, 1022,
  1024, 1027, 1031; 841 reference trees). The evaluation reserve and the
  historical test plots are not read. No path written by this study names a
  reserve plot.
- No detector runs. The predictions are the existing development matrix's
  SegmentAnyTree and ForestFormer3D instance labels (`prediction_labels.csv`
  of the admitted pilot and development runs), read as they were scored.
- Outputs go to a new directory outside the FGI-EMIT data root; no receipt or
  protected file under the root is written.
- Results are a development diagnostic under the
  [frozen policy](fgiemit-frozen-policy.md): they make no unseen-data or
  sparse-density claim.

## Proxy reference

Built as `score_instances_iou.R` builds the NEON proxy, from the true trees:

- Positions: the published tree positions (`plot_data.yaml`; crown centroids
  of the top 3 m, not stem bases).
- Crown radius: half the largest horizontal extent of the tree's true points
  at least 2 m above ground, the analogue of NEON's field `maxCrownDiameter`.
  A sensitivity uses NEON's 2 m fallback radius for every tree.
- Domain: points at least 2 m above ground (`normalized.laz`), as the NEON
  scorer's canopy substrate. Each point goes to its nearest tree and is kept
  only within that tree's radius (`assign_points_to_stems`).

Because the positions are crown centroids and the radii are measured from
the true crowns, this proxy is at least as favourable as the NEON one, whose
stem bases sit off the crown centre and whose radii come from field tapes.
Its gap to the truth is a lower bound on the NEON proxy's.

## Scores

On the canopy domain, with `score_instance_cell` (IoU gate 0.5, greedy by
IoU) and pooled counts:

1. Proxy against truth: mask precision, recall, F1, coverage, SQ and PQ,
   and the per-tree IoU between a tree's proxy and true masks.
2. Each arm against truth and against the proxy: the same metrics. The full
   support scores of the development comparison are recomputed first as a
   check of the inputs.
3. Paired whole-plot bootstrap (1,000 resamples, seed 20260923) of each arm's
   F1 against the proxy minus against the truth.

The proxy is valid for ranking if it preserves the arms' order and gap; it is
a pessimistic absolute scale if every arm scores lower against it. The
report states both, with numbers.
