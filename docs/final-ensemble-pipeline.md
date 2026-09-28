# Native FGI-EMIT ensemble pipeline

The pipeline connects declared inputs, bounded detector execution, verified
cache reuse, development fusion comparisons, separate detection and instance
products, and count-pooled evaluation. It uses the existing model environments.
The supported real-data scope is the declared native FGI-EMIT population.
Synthetic mode remains available for general interface tests.

## One entry point

From the repository root, use the existing environment and absolute data paths:

~~~sh
export CLAUDE_JOB_DIR="/home/alex/projects/lidar_tree_benchmarks/work"
PYTHON="/home/alex/projects/lidar_tree_benchmarks/gpu/.venv/bin/python"
Rscript scripts/assemble_metapipeline.R MODE=fgiemit \
  PYTHON="$PYTHON" ROOT="$CLAUDE_JOB_DIR/external/fgiemit" \
  PREPARED="$CLAUDE_JOB_DIR/fgiemit-reserve-v1" \
  RUN="$CLAUDE_JOB_DIR/fgiemit-reserve-run-v1" \
  OUT="$CLAUDE_JOB_DIR/fgiemit-reserve-products-v1" EXECUTE=true
~~~

The declared reserve inputs must already pass
[input preparation](fgiemit-reserve-input-protocol.md). `EXECUTE=true` runs a
missing reserve detector directory once. An existing directory is verified,
never silently retried. The frozen runner stops at the first failure with a
3,600-second detector limit. Unavailable cells block primary metrics and
products while retaining every denominator and failure receipt. Product output
must be a fresh directory outside the protected development data root.

The same command with `VERIFY=true` checks all parents and product hashes;
omit `EXECUTE=true` when verifying. Direct Python invocation is available via
`scripts/run_ensemble_pipeline.py` with equivalent lowercase flags.

## Development ensemble comparisons

~~~sh
Rscript scripts/assemble_metapipeline.R MODE=fgiemit STAGE=development \
  PYTHON="$PYTHON" ROOT="$CLAUDE_JOB_DIR/external/fgiemit" \
  OUT="$CLAUDE_JOB_DIR/fgiemit-development-ensemble-v2"
~~~

This reuses the complete sealed development detector outputs and whole-plot
calibration. It performs no new detector inference. All three single-arm
controls are independently rescored and checked against their sealed counts.
It compares fixed union and two-vote consensus for all three arms and the
SAT/FF3D pair. Fusion reuses the established cross-arm clustering, 2 m XY and
5 m height gates, highest-point representative and one vote per distinct arm.
It does not replace the detector's fixed instance filter.

Weighted fusion uses the already fitted apex-target probabilities from the
other nine plots, with summed weight at least one. It never uses mask-target
probabilities. Scores outside training range stay unavailable. Target density
must lie within the other nine plots' observed first- and all-return density
ranges. Any unavailable member probability blocks the weighted cell; no point
is silently removed or assigned a fabricated weight. An incomplete candidate
has no pooled primary comparison. The sum of votes is not a calibrated cluster
probability.

For a development-only exported detection product, explicitly set
`METHOD=union_all`, `consensus_2of3`, `union_point`, `consensus_point` or
`weighted_all`. Default `METHOD=selected_policy` retains the frozen FF3D
policy. These comparisons are descriptive development diagnostics, not new
held-out fusion evidence or automatic policy selection. The reserve mode
rejects every fusion override; its controls remain controls.

## Products and provenance

| Output | Meaning |
| --- | --- |
| `status.csv` | Every declared detector cell, including missing/failed status, support, measured densities and source identity. |
| `products.csv`, `pooled.csv` | Per-plot and complete-support apex comparisons; blocked candidates retain status and have no substituted zero metrics. |
| `baseline_cells.csv`, `baseline_metrics.csv` | Separate apex profiles and instance-mask counts, pooled from count and IoU accumulators; original A-D mask categories remain available. |
| `calibration.csv` | Original scores and checked development-only probabilities, including explicit unsupported-score/density reasons. |
| `deliverables.csv` | Requested detection product, separate instance product and availability for each plot. |
| `products/<plot>/treetops.csv` | Local metric X/Y and geometric AGL Z, with explicit plot, product and instance IDs. |
| `products/<plot>/instance_masks.laz` | FF3D fixed-filter predicted instances over every retained normalized point, with original source rows and zero background. |
| `products/<plot>/product.json` | Frame, densities, mask type, product identity, height datum and association/claim limits. |
| `manifest.json` | Parent receipts, code and output hashes, supported scope and completed-product status. |

Mask export independently checks original native point identity and repeats
the unchanged fixed filter before writing. No reference annotations enter
the exported mask cloud. Detection and mask IDs coincide only for the FF3D
single-arm product. Fusion detections do not invent fused masks or imply that
the separate FF3D masks are refined around fused seeds.

Each plot has its own local frame without an invented EPSG. These outputs are
not WGS84 GeoJSON. Predicted instance masks support mask evaluation, but do not
establish crown diameter, DBH, species, biomass or a crown-refinement benefit.
No broad optical/SAM2Point sweep or new architecture is automatically enabled.

## Readiness boundary

Ready means a reproducible benchmark workflow and exported detection/instance
products on the admitted native FGI-EMIT support, with explicit failure and
calibration limits. The frozen policy remains unchanged regardless of reserve
scores. General site/density routing requires separately admitted data and
compatible calibration. Unknown upstream checkpoint overlap and independent
AGL accuracy still limit claims. The reserve's three plots provide descriptive
pooled and per-plot results, not a primary bootstrap uncertainty interval.

Use the [observed pipeline report](../results/final-ensemble-pipeline-results.md)
for completed runs, comparison outcomes and resource limits.
