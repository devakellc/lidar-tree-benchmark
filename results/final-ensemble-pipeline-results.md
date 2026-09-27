# Native FGI-EMIT ensemble pipeline results

The [pipeline](../docs/final-ensemble-pipeline.md) connects verified detector
outputs to explicit fusion comparisons, separate treetop/instance products
and count-pooled evaluation. Its default is the
[frozen FF3D policy](../docs/fgiemit-frozen-policy.md). The supported real-data
scope is the declared native FGI-EMIT population, with unknown upstream
checkpoint overlap and unverified independent AGL accuracy.

Execution date: 27 September 2026. All new runs and products live outside the
protected development root. No historical, development or reserve-input
artifact was overwritten.

## Development comparison

All 30 sealed development cells were reused without inference. Independent
assembly scoring reproduced every single-arm TP, FP, FN and denominator.
The comparison uses all ten plots and 841 original annotated references.
Fusion uses the existing 2 m XY/5 m height-gated cross-arm clustering and
highest-point representative, with fixed membership and one vote per arm.

| Detection product | Predictions | TP | FP | FN | Precision | Recall | F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| CHM-VWF | 375 | 312 | 63 | 529 | 0.8320 | 0.3710 | 0.5132 |
| SAT | 795 | 599 | 196 | 242 | 0.7535 | 0.7122 | 0.7323 |
| FF3D | 830 | 676 | 154 | 165 | 0.8145 | 0.8038 | 0.8091 |
| All-arm union | 871 | 578 | 293 | 263 | 0.6636 | 0.6873 | 0.6752 |
| Two-of-three consensus | 534 | 479 | 55 | 362 | 0.8970 | 0.5696 | 0.6967 |
| SAT/FF3D union | 845 | 594 | 251 | 247 | 0.7030 | 0.7063 | 0.7046 |
| SAT/FF3D consensus | 520 | 480 | 40 | 361 | 0.9231 | 0.5707 | 0.7054 |

These fixed fusion settings do not improve development F1 over FF3D. Consensus
raises precision while substantially reducing recall. Union is not guaranteed
to preserve a constituent detector's matches: the existing transitive
cross-arm clusters can join multiple nearby detections and keep only their
highest point. These are descriptive development comparisons, not a search
for the best possible fusion method or independent held-out fusion evidence.
No reserve outcome is used to alter the default.

Weighted all-arm fusion has complete calibration support on only two of ten
plots. The other cells are explicitly blocked by unavailable scores or
first-/all-return density outside the nine training plots' observed ranges.
No missing probability is clipped, imputed or silently dropped. The incomplete
candidate has no pooled primary score and is not promoted.

## Execution and product verification

All nine declared reserve cells completed successfully on their first and
only attempts: plots 1003, 1010 and 1023, each with CHM-VWF, SAT and FF3D.
All six instance-mask cells passed whole-row admission. Every arm used the
same 10,941,159 retained points and all 257 original references. There were
no failed, missing or excluded cells, no density thinning, and no reserve
fusion, calibration fitting, policy adjustment or parameter rescue.
The existing semantic-class-5 exclusion remains exactly 500,232 source rows;
no reference tree was removed for height, edge status or death.

The runner replayed the entire frozen parent chain after execution. The
[assembly entry point](../docs/final-ensemble-pipeline.md) reused that accepted
run and independently rescored all primary apex controls, reproducing their
exact counts. The earlier policy and preparation receipts retain their
original execution-disabled scope; this run has its own admission receipt.

### Primary apex results

Counts are pooled over all three plots and 257 original references. The
unchanged greedy one-to-one matcher uses 4 m XY and 5 m absolute height
gates with maximum-AGL apexes. No per-plot rate is averaged.

| Arm | Predictions | TP | FP | FN | Precision | Recall | F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CHM-VWF | 120 | 92 | 28 | 165 | 0.7667 | 0.3580 | 0.4881 |
| SAT | 271 | 197 | 74 | 60 | 0.7269 | 0.7665 | 0.7462 |
| FF3D | 279 | 208 | 71 | 49 | 0.7455 | 0.8093 | 0.7761 |

| Plot | Arm | References | Predictions | TP | FP | FN | Apex F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1003 | CHM-VWF | 54 | 21 | 19 | 2 | 35 | 0.5067 |
| 1003 | SAT | 54 | 59 | 43 | 16 | 11 | 0.7611 |
| 1003 | FF3D | 54 | 49 | 34 | 15 | 20 | 0.6602 |
| 1010 | CHM-VWF | 155 | 55 | 45 | 10 | 110 | 0.4286 |
| 1010 | SAT | 155 | 132 | 110 | 22 | 45 | 0.7666 |
| 1010 | FF3D | 155 | 160 | 134 | 26 | 21 | 0.8508 |
| 1023 | CHM-VWF | 48 | 44 | 28 | 16 | 20 | 0.6087 |
| 1023 | SAT | 48 | 80 | 44 | 36 | 4 | 0.6875 |
| 1023 | FF3D | 48 | 70 | 40 | 30 | 8 | 0.6780 |

### Separate instance-mask results

SAT and FF3D are scored against the original manual point-instance labels
at IoU 0.5. CHM has no instance-mask metric. Coverage and PQ use pooled
IoU accumulators and counts from the sealed scorer, not mean plot rates.

| Arm | TP | FP | FN | Precision | Recall | F1 | Coverage | SQ | PQ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SAT | 152 | 119 | 105 | 0.5609 | 0.5914 | 0.5758 | 0.5426 | 0.7803 | 0.4493 |
| FF3D | 174 | 105 | 83 | 0.6237 | 0.6770 | 0.6493 | 0.6527 | 0.8569 | 0.5564 |

| Original category | SAT matched/reference; recall | FF3D matched/reference; recall |
| --- | --- | --- |
| A | 86/100; 0.8600 | 85/100; 0.8500 |
| B | 28/58; 0.4828 | 35/58; 0.6034 |
| C | 33/74; 0.4459 | 43/74; 0.5811 |
| D | 5/25; 0.2000 | 11/25; 0.4400 |

| Plot | Arm | TP | FP | FN | Mask F1 |
| --- | --- | --- | --- | --- | --- |
| 1003 | SAT | 28 | 31 | 26 | 0.4956 |
| 1003 | FF3D | 21 | 28 | 33 | 0.4078 |
| 1010 | SAT | 87 | 45 | 68 | 0.6063 |
| 1010 | FF3D | 115 | 45 | 40 | 0.7302 |
| 1023 | SAT | 37 | 43 | 11 | 0.5781 |
| 1023 | FF3D | 38 | 32 | 10 | 0.6441 |

### Fixed height diagnostics

These profiles are uncalibrated sensitivity checks, separate from the
maximum-AGL primary result. They do not select or modify the policy.

| Arm | Apex profile | TP | FP | FN | F1 |
| --- | --- | --- | --- | --- | --- |
| SAT | max_agl | 197 | 74 | 60 | 0.7462 |
| SAT | isolated_top_agl | 197 | 74 | 60 | 0.7462 |
| SAT | historical_raw | 198 | 73 | 59 | 0.7500 |
| FF3D | max_agl | 208 | 71 | 49 | 0.7761 |
| FF3D | isolated_top_agl | 208 | 71 | 49 | 0.7761 |
| FF3D | historical_raw | 208 | 71 | 49 | 0.7761 |

### Observed resources

Each cell ran once, sequentially, within the 3,600-second detector limit.
Detector wall time excludes host scoring and shared preflight verification.
Host RSS is the native model process maximum, or the R process for CHM;
CUDA figures are model allocator peaks, not total device memory. Runs used
the existing RTX 5090 and unchanged model environments.

| Arm | Total detector wall, s | Maximum cell wall, s | Maximum host RSS, MiB | Maximum CUDA allocated, MiB | Maximum CUDA reserved, MiB |
| --- | --- | --- | --- | --- | --- |
| CHM-VWF | 13.8 | 5.9 | 1212.9 | not used | not used |
| SAT | 456.4 | 201.1 | 3444.5 | 631.3 | 812.0 |
| FF3D | 1557.6 | 796.3 | 5847.3 | 8034.0 | 9960.0 |

The largest plot, 1023, completed FF3D on all 5,280,951 retained points
in 796.3 seconds, with no outer tiling, thinning, retry
or parameter rescue. This is one observed whole-scene run, not a
guarantee for larger scenes or a measure of run-to-run stability.

FF3D has the higher pooled reserve apex and mask F1, but SAT has higher apex
F1 on plots 1003 and 1023 and higher mask F1 on plot 1003. These differences
do not authorize a per-plot oracle or a new router. Original categories A–D
retain their neighborhood-based definitions; category D denotes trees beneath
a taller neighbor. Both instance arms still miss most category-D references.
The default remains the policy frozen before these results were observed.

The [input report](fgiemit-reserve-input-results.md) remains part of the
interpretation: 8.2141% of plot 1010's points lie outside the geometric ground
hull, versus a development maximum of 0.6284%. Maximum-AGL/published-height
differences reach 5.018 m on plot 1003 and 4.068 m on plot 1010. The unchanged
isolated-top profile does not improve the pooled apex counts. These diagnostics
do not independently establish terrain or AGL accuracy, and no normalization
or reference correction was made after evaluation.

## Reserve products and provenance

The public R entry point completed with `EXECUTE=true` against the accepted
run, reusing all nine cells without another inference attempt. A subsequent
`VERIFY=true` invocation replayed every parent and all 22 product-file hashes.
The final manifest reports `product_ready=true` and retains the frozen FF3D
policy and all unsupported-scope flags.

Independent checks read the three exported clouds and compared their complete
XYZ, source-row, return-number and instance-label arrays with the prepared
geometry and accepted predictions. All 10,941,159 points match. The products
contain 279 treetops and 279 instances: 49 on plot 1003, 160 on plot 1010 and
70 on plot 1023. Treetop instance IDs match the mask IDs, background stays
zero, and no reference labels or invented EPSG are introduced. Heights remain
geometric AGL in each plot's own local metric frame.

The detector run is `fgiemit-reserve-run-v1`; final exports are
`fgiemit-reserve-products-v1`. Both are siblings of the original preparation
under the shared working directory. These SHA-256 values identify the
completed receipts; each receipt binds its own parents, code and outputs.

| Receipt relative to working directory | SHA-256 |
| --- | --- |
| `fgiemit-reserve-run-v1/run.json` | `434e78b6e0c2ac303c1bda99094921d60bc02ca751b527731bf2b07069df0e9a` |
| `fgiemit-reserve-products-v1/manifest.json` | `e1284b13d8f516c4611ab7fbbc19948ee53f9ff5dced4f8ed0e7d294f1a9604a` |
| `fgiemit-development-ensemble-v2/manifest.json` | `64d2d0e476c5d25490782ae3e2bee7e3146c7dd4be96d9168ccb5ec4c3d8fae6` |
| `fgiemit-development-consensus-v2/manifest.json` | `b1fc3f6211ed8c8b6ddee52b19cc1b77bc3bfc29336140d8b8ab0f81333463b2` |

## Development products

The final default and consensus exports both passed the real R entry point,
full parent replay and independent cloud/header checks. Each contains ten
plots and 32,445,937 retained points. The default exports 830 FF3D treetops
and 830 predicted instances. Explicit SAT/FF3D consensus exports 520 treetops
and the same separate 830 FF3D instances; it does not claim fused or refined
masks. Every mask cloud preserves source rows, original accepted instance IDs
and zero background. It contains no reference `tree_index` field and declares
no invented CRS.

Final output directories are `fgiemit-development-ensemble-v2` and
`fgiemit-development-consensus-v2` under the shared working directory. The
earlier `v1` smoke products remain preserved. The final revision checks invalid
product locations before permitting reserve execution; no detector inference
was repeated to rebuild development products.

## Reproduction and checks

Use the existing environments and the commands in the
[pipeline guide](../docs/final-ensemble-pipeline.md). Add
`STAGE=development METHOD=consensus_point` and a fresh `OUT` to export the
development consensus product. `VERIFY=true` replays all parent and output
hashes, including accepted native predictions, preparation receipts and the
frozen policy. Large clouds and generated tables remain in ignored working
directories, outside version control.

~~~sh
Rscript tests/run_tests.R
/home/alex/projects/lidar_tree_benchmarks/gpu/.venv/bin/python \
  -m unittest discover -s tests -p 'test_*.py'
rumdl check --no-cache .
git diff --check
~~~

The full R suite passed with three explicit skips: the optional live cylinder
fixture needs `FF3D_REPO`/`FF3D_CKPT`, this lidR build cannot write an empty LAS
fixture, and the default Python lacks `plyfile`. An existing bootstrap check
also warned that the sandbox could not reach the R-universe package index.
No test failed. The final Python suite ran 80 tests: 78 passed and two optional
upstream fixtures were skipped because their source checkouts were absent
from the isolated worktree. Real whole-scene inference is verified separately
from these optional unit fixtures.

Regression coverage includes stop-on-failure behavior, retained denominators,
no retries, annotation-free model mounts, exact adapter algorithm parity,
count/IoU pooling, whole-plot calibration identity, blocked score/density
support, full-row instance exports, fixed reserve policy and invalid output
paths rejected before GPU execution. Markdown and whitespace checks pass.
A one-file whitespace attribute preserves the already sealed reserve
adapter's terminal blank line, keeping its accepted code hash reproducible.

## Readiness and limits

The native FGI-EMIT workflow supports bounded execution, verified reuse,
explicit development ensemble comparisons, separate treetop/instance products
and reproducible count-pooled evaluation. FF3D remains the frozen default;
none of the measured fusion candidates is promoted. Weighted fusion stays
unavailable wherever its declared calibration support is incomplete.

This does not establish general site/density routing, independent checkpoint
generalization, independently validated AGL, fused crown refinement, crown
diameter, DBH, species or biomass performance. Those require separately
admitted data and evidence. The three reserve plots support descriptive
pooled and per-plot results, without a primary bootstrap uncertainty claim.
