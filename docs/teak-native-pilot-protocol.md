# Native TEAK input pilot

This pilot establishes an acquisition and preparation path for the published
TEAK canopy-reference track. It runs no detector and assigns no evaluation
split. The pilot plot is TEAK_043: the first sorted plot with historical use
in the pinned canopy package. It is a development diagnostic, never a fresh
holdout. The other eleven candidate plots remain outside pilot processing.

Use the published image footprint as the 40 m square core and add 25 m on
each side for a 90 m square context clip. This matches the existing context
buffer without replacing field-census geometry. All measured densities must
state their footprint and distinguish first returns from all returns.

The initial acquisition candidate is the released June 2018 TEAK tile at
321000/4096000, selected from the image name and location only. Those clues
are not proof of source identity. Compare native RGB pixels and CHM values
against the published clips, retain native acquisition/flight evidence and
check correspondence between archived and native points before making any
source-year claim. Preserve alternative or unresolved interpretations.

Verify native projected metric CRS and height datum, intact return fields,
point coverage and source-point identity. Retain original classifications,
withheld/background flags and the complete native context clip. Derive a
separate TIN-normalized version from the native ground classification only
when all selected points can be accounted for; do not silently drop failed
interpolation or apply a height filter. Normalization is a processing check,
not independent proof of AGL accuracy. Registration previews are diagnostic;
no coordinate offset may be fitted using detector or reference scores.

In parallel, identify the exact installed FF3D and SegmentAnyTree checkpoints
and their documented pretraining, training and model-selection support.
Missing training identities remain unknown. Public evaluation labels and
absence from a scanned local-use inventory do not prove non-exposure.

The completed deliverable must include original-file provenance, native and
normalized clips, density/quality inventories, an image/height overlay,
point-preservation evidence, and a readiness decision. It cannot authorize
scoring while checkpoint exposure, reference completeness, image-edge policy
and a separately declared canopy-box matching/split policy remain unresolved.

## Implementation and reproduction

The native 1 km tile and three source metadata inventories are pinned by
the [source manifest](teak-native-pilot-sources.json). Published inputs are
bound to the prior canopy-source manifest. Hash all inputs before reading
and again before writing a successful receipt. A failed attempt remains an
incomplete output directory; use a new output directory for a corrected run.
Never overwrite a completed artifact or a hash-mismatched download.

Retain both native and TIN-normalized context clouds. A zero-based `pilot_row`
identifies the extracted native clip's row, not a tree or a global source-tile
row. Preserve original fields, row order and absolute elevations through
normalization and LAS serialization. Keep missing or ambiguous published
point correspondence unknown; do not assign one duplicate to an arbitrary
native row. Comparison tuples use both files' declared millimetre XY scales,
return numbers and PointSourceID, without transferring reference labels.
Register original absolute elevations as double `Zref` extra bytes so the
LAS writer cannot silently discard them. Reject input collisions with the
reserved `pilot_row` and `Zref` names. Compare all shared original fields
on uniquely matched published/native tuples and retain missing fields,
discrepancies and invalid published return counts. Coordinate correspondence
must not be presented as whole-point attribute identity.

Decoded RGB comparison uses Python 3, `rasterio` and `numpy` from the existing
host environment to read unmasked uint8 samples. Source nodata declarations
are reported separately. Pixel-grid, coverage and CRS checks precede value
comparison. The shared R environment supplies `lidR`, `terra`, `sf`, `xml2`,
`digest` and `jsonlite`. No model environment or checkpoint is modified.

```sh
Rscript scripts/prepare_teak_native_pilot.R \
  CACHE=/home/alex/projects/lidar_tree_benchmarks/work/teak-native-pilot \
  PUBLISHED=/home/alex/projects/lidar_tree_benchmarks/work/teak-canopy-reference/sources \
  OUT=/home/alex/projects/lidar_tree_benchmarks/work/teak-native-pilot-output/replay-new
```

`OUT` must be new and outside both input archives. Optional `FETCH=1` retrieves
missing declared native payloads using the existing external `NEON_TOKEN`
configuration. Released site/month/product and filename must match; exact
byte count and SHA-256 must pass before a partial download is finalized.
It does not reconstruct the archived metadata, checkpoint review or parent
published package. Those pinned inputs must already be available. Public
release changes require a new explicit source audit.

Run verification from the repository root:

```sh
Rscript tests/run_tests.R
python3 tests/test_teak_rgb.py
rumdl check --no-cache .
git diff --check
```
