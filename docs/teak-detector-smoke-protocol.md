# Historical TEAK detector compatibility smoke

Run the existing CHM-VWF, SegmentAnyTree and ForestFormer3D paths on the
verified native TEAK_043 context. This is an implementation and export check
on an already-used development plot. It consumes no reference annotations
and calculates no real accuracy metric. The
[canopy comparison policy](teak-canopy-scoring-protocol.md) and its unresolved
admission conditions remain unchanged. All eleven reserved plots stay unused.

## Fixed inputs and model behavior

Use the accepted [native pilot](../results/teak-native-pilot-results.md):
43,460 points in a 90 by 90 m context around the 40 m published image core.
Its measured context density is 3.75284 first returns/m² and 5.36543 total
returns/m². Preserve ground, noise, background and negative normalized
heights. No thinning, height filtering, re-normalization or new acquisition
occurs. Native classifications remain unchanged in the source and products.

Create model transport files by a reversible translation of native XYZ into
a local metric frame. Native absolute elevations become relative elevations
through subtraction of one fixed origin; they do not become AGL. Carry an
ordered zero-based source-row identity and original return fields. Remove
geographic CRS declarations from local transport coordinates. Keep the
original native and TIN-normalized source clouds intact for product export.
Transport classification is uniformly 1, with other nongeometry attributes
zeroed, so native class labels do not become model inputs.
No published point labels, image boxes or invented reference heights enter
the model inputs.

The CHM path uses the existing density rule and TIN/pit-fill implementation:
1.0 m cells, a 3-cell mean filter, variable-window slope 0.10, a 3–5 m window
and 2 m minimum height. It uses the prepared normalized heights and first
returns. This is lasR's TIN-based `pit_fill`, not `lidR::pitfree()`.
The pinned pre-devel runtime is verified before use.

Instance arms retain the existing checkpoints, container identities, native
configuration and indexed full-cloud adapters. SegmentAnyTree retains its
native interpolation and filtering. ForestFormer3D uses one whole scene,
its native internal regions and the existing 2,048-row distance batch size.
No outer tiling, added confidence cutoff, top-k selection or parameter
search is introduced. Installed checkpoint exposure remains unknown.

Apply the unchanged 40-point and 1.5 m raw-Z extent filter to native instance
labels on the full context before image clipping. This reproduces an existing
operating policy; its suitability for sparse TEAK ALS is not established by
this smoke. Raw-Z extent is not normalized tree height. Record unfiltered and
filtered counts separately, without choosing settings from the result.

## Execution and isolation

The [machine-readable declaration](teak-detector-smoke.json) fixes the plot,
parents, three arms, model identities, failure policy and unsupported claims.
Preparation binds source/code/configuration identities and stages inputs in
a fresh directory outside the protected parent packages and model store.
Image/checkpoint probes and runtime verification do not run inference.

Execute CHM-VWF, SegmentAnyTree and ForestFormer3D sequentially, once each,
with a 3,600-second wall limit for each detector subprocess. Preparation,
export validation and verification run separately from that timer. Claim the
attempt before starting inference. Stop at the first execution or
output-contract failure and keep the failed cell's logs and remaining planned
cells. Missing and failed outputs remain unknown; a successful empty result
is recorded explicitly. No retry,
replacement model, fallback tile or settings change is automatic.

A persistent claim under the canonical model checkout's
`work/teak-detector-smoke-attempts/` directory binds the scientific input and
model contract to its first output directory. Choosing another output path
or editing incidental code does not provide a second attempt. Keep that
claim alongside the accepted or failed run; verification checks both records.

Containers receive only staged geometry, a fresh model-output workspace,
the checkout's adapter files and the required model code/checkpoint. They
have networking disabled. They cannot see the parent annotation packages.
ForestFormer3D works in a disposable copy of its existing model checkout;
the installed model store is not modified.

Verification reuses the recorded predictions and regenerates expected export
content for comparison without another inference call. It checks the source
parents, declaration, implementation identities, output hashes and ordered
point identities. An execution flag on this compatibility receipt does not
change the earlier packages' evaluation flags.

## Products and interpretation

Keep raw adapter outputs alongside final products. Validate complete row
coverage, exact local coordinates and return fields, native instance IDs and
zero background before applying the fixed filter. Partial predictions are
never projected onto unsupported points.

Build final native and normalized labelled clouds by copying their original
source records and appending prediction fields. ForestFormer3D's internal
transport uses PointSourceID for predicted labels; do not copy that overwrite
onto the georeferenced product. Original flightline IDs, UserData, absolute
elevations, normalized `Zref`, source fields and row order must survive.

Export maximum-AGL instance apexes with source-row identity and image-core
membership. CHM detections are separate treetop outputs; they do not provide
instance masks and must not be expanded into invented crown boxes.

For instance arms, inventory raw XY extrema as **point-extent box proxies**.
Retain instance IDs, full-context support and the unclipped bounds; intersect
with the fixed image footprint for diagnostic pixel-coordinate output.
Preserve outside and zero-area cases with explicit reasons. Do not invent a
positive width, silently remove an instance, or describe these extrema as
measured canopy outlines or validated crown boxes. Instances near the outer
context boundary may have truncated support.

Report execution status, point/instance counts, observed resources and export
checks. Do not report TP/FP/FN, precision, recall, F1, reference IoU, calibrated
probabilities, fusion, routing, crown accuracy or deployment transfer. Counts
from different arms are not a ranking. ForestFormer3D remains the previously
selected default; this run does not select a TEAK winner.

The upstream model logs may print evaluation counters against their dummy
input labels. Those counters are not TEAK reference scores and must not be
used in the comparison. The smoke exports only predictions and execution
diagnostics; no published reference labels enter the containers.

TEAK_043 becomes model-observed in this new run. Any subsequent review that
uses its predictions cannot be described as blind to those predictions.
Keep the original annotation-review queue pending, and do not promote the
historical pilot into an independent validation plot.

## Reproduction

Use the existing host Python environment and installed model/runtime paths.
The Python environment needs LAZ-enabled `laspy`, `numpy`, `scipy`, `pyproj`
and `PyYAML`, including imports of the reused benchmark helpers. Existing
Docker images supply the GPU dependencies; do not install another model
version to reproduce this smoke.

```sh
/home/alex/projects/lidar_tree_benchmarks/gpu/.venv/bin/python scripts/run_teak_detector_smoke.py --prepare \
  --pilot /home/alex/projects/lidar_tree_benchmarks/work/teak-native-pilot-output/final-run \
  --policy /home/alex/projects/lidar_tree_benchmarks/work/teak-canopy-policy-output/final-run \
  --gpu /home/alex/projects/lidar_tree_benchmarks/gpu \
  --runtime /home/alex/projects/lidar_tree_benchmarks/work/fgiemit-pilot-runtime \
  --out /home/alex/projects/lidar_tree_benchmarks/work/teak-detector-smoke-output/run-new
```

Run from the checkout root, using the absolute path to `gpu/.venv/bin/python`
when its environment is in the original checkout. Execute and verify take only
the sealed output path:

```sh
/home/alex/projects/lidar_tree_benchmarks/gpu/.venv/bin/python scripts/run_teak_detector_smoke.py --execute \
  --out /home/alex/projects/lidar_tree_benchmarks/work/teak-detector-smoke-output/run-new
/home/alex/projects/lidar_tree_benchmarks/gpu/.venv/bin/python scripts/run_teak_detector_smoke.py --verify \
  --out /home/alex/projects/lidar_tree_benchmarks/work/teak-detector-smoke-output/run-new
```

Verification checks accepted artifacts without rerunning detectors. Keep
failed attempts and their records. Generated clouds, predictions and model
workspaces remain ignored working data.
