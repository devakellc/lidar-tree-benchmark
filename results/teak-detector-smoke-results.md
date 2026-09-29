# Native TEAK detector compatibility smoke

CHM-VWF, SegmentAnyTree and ForestFormer3D completed on their first attempts
on 2026-09-28, using the historical TEAK_043 development plot. The study uses
the verified [native pilot](teak-native-pilot-results.md) and the fixed
[smoke protocol](../docs/teak-detector-smoke-protocol.md). It establishes
execution and export behavior only. No published image boxes or point labels
are detector inputs, and no real accuracy metric is calculated.

## Data and fixed configuration

The native context is 90 by 90 m in EPSG:32611, surrounding the 40 by 40 m
image core with 25 m on every side. All 43,460 points enter each arm,
including 23,669 ground-class points and five noise-class points. The
TIN-normalized parent retains all 29 negative heights. No thinning,
height-based input removal or new normalization occurs.

Measured context density is 3.75284 first returns/m² and 5.36543 total
returns/m². The existing rule therefore selects a 1 m CHM with a three-cell
mean filter, variable-window slope 0.10, 3–5 m windows and 2 m minimum
height. Native instance arms retain their existing configurations. Their
unchanged postfilter requires at least 40 points and 1.5 m native raw-Z
extent. That extent is not AGL height.

The [declaration](../docs/teak-detector-smoke.json) pins both parent receipts,
the two image identities and checkpoints, and installed ForestFormer3D
patches. Preparation additionally records 193 implementation/configuration
file hashes, 57 copied ForestFormer3D source files, the isolated lasR runtime
and 52 parent or linked payload identities. The lasR revision is
`97dd5fb85fada7de0dbd024246751a9941daedaf`. No environment or checkpoint was
installed or replaced.

The run uses an NVIDIA GeForce RTX 5090 with 32,607 MiB device memory and
driver 595.84. Host Python is 3.12.3, with laspy 2.7.0, lazrs 0.8.1,
numpy 2.4.4, scipy 1.17.1, pyproj 3.7.2 and PyYAML 6.0.3. Neural runtime
dependencies remain supplied by the pinned images.

## Observed execution

Every cell finished as `successful_nonempty`. The common input contains
43,460 context points, of which 8,655 lie inside the image core. The core
counts below use the declared image footprint and do not score its
surrounding ring.

| Arm | Context outputs | Apexes in image core | Detector wall time (s) |
| --- | ---: | ---: | ---: |
| CHM-VWF | 77 treetops | 9 | 2.17 |
| SegmentAnyTree | 90 retained instances | 14 | 383.85 |
| ForestFormer3D | 138 retained instances | 16 | 81.78 |

Counts are diagnostics, not a ranking. The native instance filter acts on
the full context before image clipping; no threshold was selected from these
outputs.

| Instance arm | Raw instances | Removed by fixed filter | Raw background points | Filtered background points | Positive-area image proxy boxes | Outside-image proxies |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| SegmentAnyTree | 149 | 59 | 31,924 | 33,419 | 18 | 72 |
| ForestFormer3D | 170 | 32 | 25,844 | 26,746 | 26 | 112 |

Neither arm has a degenerate retained box. Proxy intersection and apex
membership count different things, so the image-box counts need not equal
the in-core apex counts. No box is compared with a published annotation.

| Arm | Peak model-process host RSS (MiB) | Peak CUDA allocated (MiB) | Peak CUDA reserved (MiB) |
| --- | ---: | ---: | ---: |
| CHM-VWF | 258.6 | Not applicable | Not applicable |
| SegmentAnyTree | 2,558.9 | 149.4 | 166.0 |
| ForestFormer3D | 2,474.0 | 264.8 | 324.0 |

Wall times cover the bounded detector subprocess, including its adapter and
container overhead. Preparation and final export verification are outside
that timer. Host RSS is the R process for CHM and the native model process
for the neural arms. CUDA counters cover PyTorch allocations, not all device
memory. These measurements describe one small context on this host.

## Point and export contracts

Model transport uses a reversible local translation with origin
`(321009.503, 4096686.105, 2127.826)`. Absolute native Z is translated for
the neural arms; CHM transport retains the pilot's normalized heights.
Local files have no geographic CRS declaration. Ordered source-row IDs,
integer coordinates, scales and return fields bind predictions back to
the original points. Other transport attributes carry no reference labels.

Neural products copy the native and normalized parent records and append
`raw_pred_instance` and `pred_instance`. Background remains zero and the
filter preserves retained instance IDs. Final products retain EPSG:32611,
native flightline PointSourceID values 12, 13 and 14, original UserData,
classifications, RGB, GPS times, source fields and normalized `Zref`.
ForestFormer3D's internal use of PointSourceID for instance labels does not
overwrite those original fields in the final products.

Maximum-AGL apexes are diagnostic points derived from each retained
instance. XY extrema are labelled **sparse point-extent box proxies**, with
unclipped context bounds, image intersection and explicit outside/degenerate
status. They are not canopy outlines or validated crown boxes. An instance
whose apex is outside the image may still have a proxy intersecting it.
CHM-VWF emits treetops only and has no instance-box product.

## Reproduction and verification

Accepted artifacts are under
`work/teak-detector-smoke-output/run-v1/` in the original checkout. Each
neural arm contains raw adapter output under `model_io/`, plus
`native_predictions.laz`, `normalized_predictions.laz` and
`diagnostics.json`. CHM output is `raw_treetops.csv` and its separate
`diagnostics.json`. All generated files remain ignored working data.

```text
preparation.json SHA-256:
253852c44d6bdc4208532cf256a86d38874501aa5919edfd76c7ea63da4327e8
receipt.json SHA-256:
3a4f162c78713b9772026b8d2356731376a66cfb9cd4326896e28235169dde03
attempt.json SHA-256:
586cf5407432eb0a115a7c967ecfd8949866f15f6e258095cc2c6a9bf028be27
```

The receipt inventories 2,733 output files. Execution and a separate
verification-only invocation both report `compatibility_true=true`,
`evaluation_ready=false` and `real_scores=false`. An independent check
compares every source dimension across all four exported clouds, recomputes
the fixed filter from integer native Z extents and checks maximum-AGL apex
row identities. All checks pass: each cloud has exactly 43,460 rows,
preserving 21 original native or 22 original normalized dimensions.
The original checkout's sixteen existing modified files remain unchanged.

Use the commands in the [protocol](../docs/teak-detector-smoke-protocol.md).
`--execute` consumes one persistent claim for this fixed comparison before the
first cell; another output directory cannot bypass that claim. `--verify`
rehashes the inputs, code, runtime and outputs and checks the derived exports
against the raw predictions without rerunning inference. Preserve the
shared claim directory when retaining the output package.

Independent reviews covered scientific support, runtime behavior and
provenance. Full command validation, preparation/receipt metadata checks,
failure evidence, cross-directory attempt reuse and out-of-context CHM
admission were corrected and confirmed by the reviewers.

The 17 focused Python tests pass. The existing Python suite runs 102 tests,
with 100 passing and two optional upstream-checkout fixtures skipped because
they are absent from the isolated worktree. Three RGB tests pass in system
Python, which has `rasterio`; the existing GPU virtualenv does not.
The R suite passes with three skips:
the gated live FF3D fixture, an unsupported empty-LAS writer fixture and
missing Python `plyfile`. It also reports an inaccessible R-universe index
and a libxml build/runtime version warning. No dependency was installed to
hide these limitations.

## Interpretation and next gate

This is one historically used development plot. All eleven reserved
candidates remain unprocessed, and `evaluation_ready` and `real_scores`
remain false. TEAK_043 is now model-observed; subsequent reference review
using these predictions cannot be described as blind to them.

The [canopy comparison policy](teak-canopy-policy-results.md) still requires
human reference review, acquisition/imagery temporal agreement and resolved
checkpoint-exposure evidence before admitting a real comparison. These
image boxes cannot establish apex, height, understory or 3D crown-mask
accuracy. Point-extent proxies need an explicit reference-compatible product
policy before they can support canopy-box claims. No tuning, calibration,
fusion, routing or new default selection follows from the smoke.

The upstream logs may show evaluation counters computed from dummy labels.
They are not TEAK reference scores and are excluded from this report.
ForestFormer3D remains the previously selected default, without a new claim
of transfer accuracy on USGS-like mixed-conifer ALS.
