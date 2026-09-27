# FGI-EMIT prospective reserve input validation

Completed on 2026-09-27 under the
[reserve input protocol](../docs/fgiemit-reserve-input-protocol.md), after the
[development policy freeze](../docs/fgiemit-frozen-policy.md). All three
original reserve plots passed structural validation, preserving **10,941,159
points and all 257 annotated trees**. A separate execution contract seals nine
detector cells and 15 primary scoring cells. No reserve detector, scorer or
calibration was run. The reserve now has validated inputs; it has no observed
detector performance.

The complete frozen development chain replayed before and after preparation
and during independent verification. Earlier source files, predictions,
scores, policies and closed-reserve receipts remain unchanged. New artifacts
are outside the sealed development data root.

## Support and measured density

Only semantic class 5 is excluded: 500,232 of 11,441,391 source points. All
other rows, including background and coincident XYZ, retain their original
row IDs and return fields. Separate reference exports preserve positive
instance labels and edge/dead flags. Model geometry contains no reference
annotations, spectral features or source semantic classes. Normalization
preserves XY, row order and return identity exactly.

The 257 references include 100 category-A, 58 category-B, 74 category-C and
25 category-D trees. No tree is removed for height, edge status or death.
Each plot keeps its own local metric coordinate frame and receives no invented
EPSG identifier. Areas below are retained-point XY convex hulls, not a newly
verified census boundary. First-return counts are not an independently
verified emitted-pulse inventory.

| Plot | Source points | Retained points | Class-5 exclusions | References | Footprint, m² | First returns/m² | All returns/m² |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1003 | 2,308,748 | 2,099,883 | 208,865 | 54 | 1,254.860 | 1,212.887 | 1,673.401 |
| 1010 | 3,622,071 | 3,560,325 | 61,746 | 155 | 1,962.897 | 1,476.415 | 1,813.811 |
| 1023 | 5,510,572 | 5,280,951 | 229,621 | 48 | 2,826.778 | 1,476.941 | 1,868.188 |

These measured first-return densities produce the unchanged 0.25 m CHM rule
with no mean smoothing on every plot. They provide no sparse-density evidence.
Plot 1023 has more retained points than any development plot; the development
maximum was 3,975,927. Input preparation does not establish whole-scene GPU
resource feasibility on this larger cloud.

## Normalization and height limits

The unchanged normalizer uses lidR 4.3.2, RCSF 1.0.2, geometric CSF defaults
with all returns, one thread, and TIN with its default edge extrapolator.
All heights are finite. Negative heights remain in the prepared support.
Preparation, exports and diagnostics took 6.25, 65.01 and 16.05 seconds for
plots 1003, 1010 and 1023, respectively: 87.31 seconds total, excluding shared
parent verification. Each normalization completed within its 600-second
limit. These are local CPU observations, not detector timing estimates.

| Plot | Negative AGL, % of points | Below -0.5 m, % of points | Outside ground hull, % of points | Median max-AGL minus published height, m | Largest absolute height difference, m |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1003 | 0.0842 | 0.0214 | 0.0737 | -0.101 | 5.018 |
| 1010 | 0.2171 | 0.1851 | 8.2141 | -0.178 | 4.068 |
| 1023 | 0.0014 | 0.0012 | 0.0931 | -0.100 | 0.943 |

Plot 1010 has materially more support outside its geometric ground hull than
the development maximum of 0.6284%. Its 8.2141% outside-hull fraction requires
the unchanged TIN edge extrapolator. This is a height-reference limitation,
not proof of invalid geometry or independently accurate AGL.

The largest discrepancies are tree 35 in plot 1003, with maximum AGL 15.201 m
versus published height 10.183 m, and tree 102 in plot 1010, with 18.979 m
versus 14.911 m. Their top AGL gaps are only 0.0042 m and 0.0010 m. The existing
isolated-top diagnostic therefore does not change either maximum; a single
isolated highest point does not explain these differences. No correction,
height-based exclusion or normalization tuning was introduced.

The primary reference remains the maximum-AGL source point, using the same
reducer for later predictions. The 771 reference-profile rows also retain
isolated-top AGL and historical raw-Z diagnostics, with each selected point's
XY, category and original row identity. Independent terrain and height
accuracy remain unverified.

## Sealed execution plan

The plan retains FF3D as the development-selected arm for apex and mask
products, with CHM-VWF and SAT as fixed controls. It binds input/reference
hashes, measured densities, support, method configurations, execution-core
hashes and the already verified lasR runtime. It changes no filter, matcher,
checkpoint, score threshold or calibration policy.

Order remains plots 1003, 1010, 1023, each with CHM-VWF, SAT and FF3D. There
are nine primary apex cells and six primary mask cells, with separate height
diagnostics. The frozen resource rule permits one concurrent cell, one attempt
and 3,600 seconds per detector cell, stopping at the first failure without
automatic retry or fallback tiling. Primary count-pooled comparisons require
all declared cells; missing, failed and completed-empty outcomes stay explicit.

Execution is still disabled. The next implementation is a reserve-specific
runner that replays this contract, preserves the development-only guards,
isolates reference files from model containers and writes outputs to another
fresh directory. No performance metric or primary uncertainty interval can be
reported from input validation. Unknown upstream checkpoint overlap still
limits future results to conditional within-dataset policy evaluation.

## Reproduction and verification

From this checkout, use the existing environment and original data root:

~~~sh
export CLAUDE_JOB_DIR="/home/alex/projects/lidar_tree_benchmarks/work"
PYTHON="/home/alex/projects/lidar_tree_benchmarks/gpu/.venv/bin/python"
ROOT="$CLAUDE_JOB_DIR/external/fgiemit"
RESERVE="$CLAUDE_JOB_DIR/fgiemit-reserve-v1"
"$PYTHON" scripts/prepare_fgiemit_reserve.py --root "$ROOT" --out "$RESERVE"
"$PYTHON" scripts/prepare_fgiemit_reserve.py --root "$ROOT" --out "$RESERVE" --verify
~~~

The creation command refuses an existing output directory. Replay the second
command against this preserved run; any authorized new attempt needs a fresh
directory. The receipt records Python 3.12.3, numpy 2.4.4, scipy 1.17.1,
laspy 2.7.0 and PyYAML 6.0.3. No environment or model was installed.

The manifest seals 30 generated files. Independent replay passed original
source hashes, full source-row/return/reference equality, annotation isolation,
normalization identity, recomputed densities and diagnostics, all 771 reference
profiles and reconstruction of the fixed execution contract. Parent replay
also verified checkpoint identities and the pinned lasR installation.

| Artifact | SHA-256 |
| --- | --- |
| Reserve manifest | `1d18474041d4ceae9a0c90323c1037d83d0a7adb4008de1fa65779c32665f9ee` |
| Execution matrix | `c48a7e9881f7c63a8fb601e62d4da57673ecf075d3402e14c550fee47f627353` |
| Reference profiles | `1488d2199d28eb8f8cdbec59c8ea987b443acfd77e68ed613220938e4908bc56` |

Full Python discovery passed 70 tests, with two optional upstream-checkout
integration tests skipped because the pinned FF3D and TreeAIBox checkouts are
absent from this isolated checkout. Seven new tests cover scope and digest
guards, complete replay, failed preparation without retries or admission,
source identity and annotation corruption, support changes, altered contract
settings, parent drift and symlinked artifacts. No R code changed; the
unchanged R normalizer was exercised on all three real reserve plots. The
R unit suite and GPU inference were not run in this stage. Repository-wide
Markdown lint and whitespace checks passed. README workflow, requirements,
script and report indexes were updated.

~~~sh
"$PYTHON" -m unittest discover -s tests -p 'test_*.py'
rumdl check --no-cache .
git diff --check
~~~
