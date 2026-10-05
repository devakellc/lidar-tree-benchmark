# How much of the NEON mask gap is the proxy reference?

Checked on 5 October 2026 under the
[declared protocol](../docs/fgiemit-proxy-validation-protocol.md), on the ten
FGI-EMIT development plots (841 reference trees). The evaluation reserve and
the historical test plots were not read. These are development diagnostics
under the [frozen policy](../docs/fgiemit-frozen-policy.md).

NEON has no per-point tree labels, so its mask scores use a proxy reference:
canopy points assigned to the nearest mapped stem within its crown radius.
ForestFormer3D's mask F1 is 0.71 against FGI-EMIT's true labels and 0.135
against the NEON proxy on the
[five-site board](instance-iou-pq-results.md#corrected-adapter-re-runs-on-the-frozen-clips).
Here the same proxy is built on FGI-EMIT from the true trees, and the
development matrix's predictions are scored against both references.

## Method

- **Proxy.** Canopy points (at least 2 m above ground) are assigned to the
  nearest published tree position and kept within that tree's radius
  (`assign_points_to_stems`, as `score_instances_iou.R` does on NEON). The
  radius is half the largest horizontal extent of the tree's true canopy
  points, the analogue of NEON's field `maxCrownDiameter` (median 2.1 m,
  interquartile range 1.3–3.2 m). A sensitivity gives every tree NEON's 2 m
  fallback radius.
- **This proxy is favourable.** FGI-EMIT's published positions are crown
  centroids of the top 3 m, and the radii are measured from the true crowns.
  NEON's proxy uses stem bases, which sit off the crown centre, and taped
  crown widths. Its gap to the truth is at least as large as the one below.
- **Scoring.** `score_instance_cell` (IoU gate 0.5) on the canopy domain,
  pooled by counts. Predictions are the development matrix's SegmentAnyTree
  and ForestFormer3D labels, unchanged; recomputing the full-support scores
  reproduces the published development values exactly (F1 0.612 and 0.713).
  Paired whole-plot bootstrap, 1,000 resamples, seed 20260923.

```sh
Rscript scripts/fgiemit_proxy_validation.R ROOT=work/external/fgiemit \
    OUT=work/fgiemit-proxy-validation
Rscript scripts/fgiemit_proxy_validation.R ROOT=work/external/fgiemit \
    OUT=work/fgiemit-proxy-validation-fixed2 RADIUS=fixed2
```

## Results

The proxy against the truth, as if it were a prediction:

| Proxy radius | Precision | Recall | Mask F1 | SQ | PQ | Tree IoU, median | Trees with IoU ≥ 0.5 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Measured crown | 0.600 | 0.599 | 0.600 | 0.746 | 0.448 | 0.577 | 60 % |
| 2 m fallback | 0.443 | 0.442 | 0.443 | 0.701 | 0.310 | 0.450 | 44 % |

Median proxy IoU by FGI-EMIT category (measured radius): A, isolated or
dominant, 0.74 (307 trees); B, similar-height neighbours, 0.68 (177); C,
alongside a taller neighbour, 0.39 (249); D, beneath a taller neighbour, 0.17
(108). The proxy describes free-standing crowns well and suppressed crowns
poorly.

Each arm's mask F1 on the canopy domain against the truth and against the
proxy:

| Arm | Against truth | Against proxy, measured radius | Change [95%] | Against proxy, 2 m | Change [95%] |
| --- | --- | --- | --- | --- | --- |
| ForestFormer3D | 0.722 | 0.492 | −0.230 [−0.292, −0.161] | 0.365 | −0.357 [−0.432, −0.300] |
| SegmentAnyTree | 0.619 | 0.473 | −0.147 [−0.195, −0.097] | 0.352 | −0.268 [−0.336, −0.213] |

## Readings

- **The proxy alone costs about a third of the mask F1.** Even with crown
  centroids and measured crown widths, ForestFormer3D's mask F1 falls from
  0.72 to 0.49; with NEON's fallback radius it falls to 0.37. Matched-pair
  quality drops with it (SQ 0.88 against the truth, 0.75 against the proxy).
- **The proxy keeps the order but compresses the gap.** ForestFormer3D stays
  ahead of SegmentAnyTree against both references, but its lead shrinks from
  0.10 to 0.02: a proxy board ranks arms, it does not measure their distance.
- **The rest of the NEON gap is not the proxy.** On NEON, ForestFormer3D's
  mask F1 is 0.135 against an apex F1 of 0.50. A favourable proxy explains a
  fall from 0.72 to 0.49 on dense, fully labelled FGI-EMIT; the remaining
  drop to 0.135 combines a harsher proxy (stem bases, taped widths, unmapped
  trees counted as false instances), a two-orders-of-magnitude sparser cloud
  and a different forest. The study cannot separate those.
- **Decision for the paper.** Mask scores on NEON stay in the supplement,
  with this proxy validation beside them. The main text reports apex F1 for
  NEON and true-mask F1 for FGI-EMIT, and makes no claim that apex matching
  overstates NEON instance quality by a measured amount.

Outputs: `proxy_cells.csv` (plot × arm × reference), `proxy_pooled.csv`,
`proxy_delta.csv` and `proxy_trees.csv` (per-tree radius and proxy IoU) in
each output directory.
