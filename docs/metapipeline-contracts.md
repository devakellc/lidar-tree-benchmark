# Synthetic Detection Assembly

The detection assembly entry point exercises interfaces with invented data.
It preserves a declared cell and detector matrix, separates unavailable output
from completed empty output, and checks provenance before applying toy weights.
It runs no detector, fits no calibrator and computes no benchmark metrics.
Its outputs establish software behavior only. New real-data comparisons still
need declared development data, eligible support and held-out evaluation.

## Run the Example

From the repository root, with the existing core R environment:

```sh
export CLAUDE_JOB_DIR="$PWD/work"
Rscript scripts/assemble_metapipeline.R MODE=synthetic \
  OUT="$CLAUDE_JOB_DIR/metapipeline-synthetic"
```

The example declares four cells and three synthetic detector arms. It emits
12 detector states: seven completed, three completed-empty, one failed and one
missing. Fixed two-of-three consensus yields one fused apex in the first cell,
zero in the second, and blocked fusion products in the last two. A short apex
at the same XY location stays separate through the existing height gate.
These are fixtures, not predictions by the named models.

Every invocation requires a fresh output directory. Existing directories,
including interrupted attempts, are preserved. The command also works from
another directory when invoked through its absolute script path.

An optional `INPUT=/path/to/bundle.rds` accepts a trusted local synthetic bundle.
Start from `metapipeline_synthetic()` in `scripts/metapipeline_synthetic.R` and
save the modified list with `saveRDS()`. Only `MODE=synthetic` and schema version
`1L` are accepted. The mode declaration is a caller assertion, not an audit of
the origin of supplied coordinates. Historical caches and GPU runners are not
read by this entry point.

## Input Contract

The bundle contains `schema_version`, `mode`, `cells`, `arms`, `results`,
`ensemble` and `calibrations`. Both declarations are data frames; results and
calibrations are lists. Synthetic values are deliberately explicit so the
same compatibility boundaries can be tested before real adapters are connected.

| Declaration | Required fields and meaning |
| --- | --- |
| Cell identity | `cell_id`, `dataset`, `site`, `plot`, `rung`; cell IDs and dataset/site/plot/rung tuples must be unique. |
| Input and density | `input_id`, `density_support_id`, `frdens`, `pdens`, `native_pdens`; density values must be finite and positive, with first-return density no greater than all-return density. |
| Coordinate frame | `epsg`, `height_datum`; projected metric coordinates and `AGL` heights are required. Geographic, feet-based and Web Mercator frames are rejected through the existing CRS helper. |
| Reference support | `support_id`, `support_policy`, `reference_population`, `census_event`, `support_geometry_id`, `support_admitted`, `support_blockers`; these describe actual declared support rather than a nominal plot box. |
| Detector | `arm`, `model_id`, `config_id`, `runtime_id`, `adapter_id`, `layout`, `score_name`, `score_target`, `score_definition_id`, `mask_type`. |

Numeric rungs cannot exceed measured native all-return density. Native cells
must retain native density, and achieved density cannot exceed native density.
There is no fallback density or automatic routing threshold. Reference support
and native density must agree across rungs of the same plot. IDs are opaque
provenance declarations; the synthetic runner does not survey geometry or
measure density from clouds.

`score_target` is `none`, `apex_distance` or `instance_iou`. The score definition
ID identifies the declared labelling rule, including matching thresholds and
filters; a probability for mask IoU cannot weight apex-distance fusion. A
detector without scores uses `none` for its score name and target, and numeric
`NA` raw scores. Such detectors can enter unweighted modes.

ForestFormer3D declarations require `layout=indexed_whole_scene`. Its historical
outer-cylinder layout is rejected; this check does not prove real adapter
correctness. TreeisoNet remains deferred. Choosing a synthetic arm name confers
no real-data admission or demonstrated ensemble benefit.

## Detector Results and Availability

`mp_result()` records one cell and one detector declaration along with:

- `status`: `completed`, `completed_empty`, `missing` or `failed`;
- `reason`: required for missing/failed results and empty for completed results;
- `source_id`: identity of the source prediction artifact or attempted run;
- `detections`: a table with exactly five columns: unique `detection_id`, finite
  numeric `x/y/z` and numeric `raw_score`;
- `calibration_id`: an explicit toy calibration ID or an empty string;
- `mask`: an optional descriptor.

Each receipt retains its original cell and arm declarations. Assembly rejects
stale declarations, duplicate receipts, unknown cells/arms, invalid coordinates
and contradictory status/count combinations. Importers must not stamp today's
declaration onto an old cache to bypass these checks. Missing receipts become
explicit `missing` rows with unknown detection counts, never zero detections.

`mask_type` is `none`, `predicted_instances` or `reference_proxy`. A completed
result declaring a mask must supply its `type`, `artifact_id`,
`point_identity_id` and numeric `background_label`. Descriptors are preserved
without opening, transforming, merging or scoring mask files. Their row
alignment and instance/background labels are therefore not verified here.
There are no crown products or IoU/PQ estimates in this phase.

## Assembly and Calibration Gates

`ensemble` explicitly names `members`, `controls`, `method`, `merge_tol` and
`z_tol`. Every declared arm must be a member or a single-arm control. Methods
are `union`, `consensus` with a fixed integer `k`, and `weighted` with a fixed
`weight_min`. These reuse `fuse_apexes()` and its existing cross-arm clustering,
height gate and one-vote-per-arm behavior. Clusters retain the highest apex.
The summed calibrated weight is not itself a probability of a valid cluster.

All requested members must complete on a cell before fusion is emitted.
Completed-empty members remain in the declared ensemble; failed/missing
members block that cell rather than changing its consensus threshold.
An arm is optional by declaration, not automatically optional when it fails.
Successful controls remain inspectable even when another member blocks fusion.
Unadmitted support blocks unweighted products while preserving raw receipts.
Attempts to apply calibration to unadmitted support are rejected entirely.

Every completed member of weighted fusion, including completed-empty members,
requires a compatible calibration. A supplied calibration on an unweighted
result is also checked. Each calibration records `id`, `synthetic=TRUE`, an
exact detector declaration, `training_cells`, and a numeric `lookup` table.
The lookup has only `raw_min`, `raw_max`, `raw_prob` and `calibrated` columns,
with strictly increasing knots and nondecreasing probabilities in [0, 1].
The existing normalization and lookup application are reused; values outside
the raw training range follow the existing endpoint-clipping behavior.

Compatibility requires admitted training and target support, matching dataset,
support policy, population and height datum, and an apex-distance score target.
The target site and rung must occur in training, and both measured densities
must lie inside their training ranges for that site/rung. Any training row
from the target dataset/site/plot is leakage, even at another rung. Model,
runtime, configuration, adapter and score-definition mismatches fail. Unsupported
site or density transfer has no fallback. Toy lookups are supplied fixtures;
no scientific calibration or transfer validity is inferred from these checks.

## Outputs and Verification

| Artifact | Contents |
| --- | --- |
| `assembly.rds` | Complete original declarations, result and mask descriptors, calibration fixtures, and assembled tables. |
| `cells.csv`, `arms.csv` | Requested matrix and provenance declarations. |
| `status.csv` | One row per requested cell/arm, including unavailable results and declaration hashes. |
| `apexes.csv` | Original completed detections and any checked toy probabilities. |
| `products.csv` | Every requested control and fusion product, its status, membership, support and detection count; blocked counts remain missing. |
| `fused.csv` | Emitted apex clusters, contributing arms, vote counts and optional summed weights. |
| `manifest.json` | Synthetic scope, bundle hash, code/output SHA-256 hashes and R/package versions; written last after successful output serialization. |

Regression fixtures cover empty, failed and missing states; fixed membership;
single-arm controls; provenance/CRS/density/support rejection; calibration
leakage and target compatibility; and CLI output hashes and overwrite refusal.

```sh
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
```

The existing scientific reports and historical outputs remain unchanged. This
interface does not select a dataset, fit final thresholds, demonstrate fusion
benefit, or finish the broader detection and crown pipeline.
