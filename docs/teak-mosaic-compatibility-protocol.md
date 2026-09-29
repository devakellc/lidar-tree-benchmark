# Historical TEAK mosaic compatibility audit

Compare the historical TEAK_043 mosaic with every released L1 camera frame
whose footprint intersects its fixed context. This follows the
[acquisition-timing audit](../results/teak-acquisition-timing-results.md),
which found candidate exposures on June 14 and June 15, 2018. The study tests
decoded RGB compatibility on the existing grid. It does not assign a verified
capture date, measure registration, or admit a plot for accuracy evaluation.

## Frozen input scope

The [source declaration](teak-mosaic-provenance-sources.json) binds the
accepted native pilot and timing receipts, their source declarations, the
original L3 RGB tile, and all 23 distinct L1 context candidates. The two KMZ
variants must agree on the complete local candidate records. Both context-only
frames remain included alongside the 21 frames intersecting the image core.
Frame selection uses the prior footprint inventory, before RGB comparison.

Use TEAK June 2018 `RELEASE-2026` product `DP1.30010.001` for L1 frames and
the already-pinned `DP3.30010.001` mosaic. The 23 original TIFFs total
669,643,369 bytes. Preserve their full filenames, stable object URLs, byte
counts, retrieval times and complete-file SHA-256 hashes. Signed access URLs
remain transient. Rehash all consumed sources before analysis and again
before accepting outputs. Never replace a mismatched or incomplete source.

The target is the original uint8 L3 tile
`2018_TEAK_3_321000_4096000_image.tif`. Read only its 90 by 90 m historical
context: eastings 321009.5–321099.5 and northings 4096686.1–4096776.1,
in EPSG:32611. Its 40 by 40 m core is inset by 25 m on every side.
The core contains 400 by 400 pixels, and the context 900 by 900 pixels.
Neither rectangle is fitted to source imagery or detector output.

Full source files are archived to establish byte identity. Analysis requests
only the intersection of each L1 image with the fixed context. TIFF decoding
may internally read compressed strips extending beyond the requested window;
those extra pixels are not exported or analyzed. No reserved plot window,
cloud point, detector prediction or annotation enters this comparison.

## Fixed-grid comparison

Require matching projected CRS, north-up 0.1 m pixels, uint8 RGB bands and
integer pixel-grid alignment. Check affine transforms and window coverage
before decoding. Unsupported or shifted grids fail; do not resample, fit a
translation, adjust brightness, choose a color tolerance, or interpolate
missing coverage. Disable unpinned external sidecar interpretation.

Keep geometric raster coverage, raster masks, declared nodata and all-zero
triplets distinct. A padded zero outside an image is never an observed pixel.
NEON documents black no-data borders, but zero values alone do not establish
a valid or invalid physical feature. Report the effect of zero-triplet
ambiguity separately. Preserve all 255-valued samples: the native L3 tile
has no nodata value, unlike the published benchmark crop's 255 declaration.

For every target pixel, retain the candidate set with valid samples and the
set with exactly equal decoded RGB triplets. Use a stable full-frame-ID
crosswalk for compact bitsets. Count no-match, one-match and multiple-match
cases, and distinguish matching candidates confined to one filename date
from candidates on both dates. Report core and context separately and retain
every pixel in the accounting. Achromatic and all-zero agreements need
separate diagnostics; common RGB values do not identify an exposure.

Each frame's summary records its tested support and exact-match counts.
Unequal frame coverage must not become a ranking of likely contributors.
Keep unmatched and unsupported samples explicit. Missing frames block a
complete audit; they cannot silently become zero matches.

## Interpretation and registration limits

The [Camera Mosaic ATBD](https://data.neonscience.org/api/v0/documents/NEON.DOC.005052vB)
describes choosing source pixels using viewing geometry and notes that an
overlapping image can contribute no pixels. Its image-location KMZ is not a
selected-frame map. Revision B is dated March 2022; it describes the general
processing approach, not the exact configuration of this 2018 production run.

Both the inspected L1 frames and L3 mosaic use JPEG compression. Independent
encoding can change decoded values, so a mismatch cannot exclude a true
contributor. Conversely, equal triplets can occur in multiple frames or by
coincidence. A unique match is **source compatibility**, not authenticated
pixel lineage. Keep exact mosaic exposure and LiDAR–RGB lag unknown without
independent production provenance. Do not infer a plot-wide capture day
from the most matches or the closest-looking image.

Grid agreement and image similarity also do not establish RGB–LiDAR
registration. Native point colors can derive from the same camera product,
making them unsuitable as independent control. A later assessment needs
independently reviewed, stable ground features visible in both sensors and
explicit positional uncertainty. Crown or detector offsets cannot substitute
for those correspondences. This audit fits no spatial correction.

All evaluation, reference-review, exact-provenance, temporal-agreement and
registration flags remain false. Checkpoint exposure remains unknown. The
eleven reserved candidates remain unused for pixel analysis or inference.
The [canopy comparison policy](teak-canopy-scoring-protocol.md) still governs
any future admitted accuracy study.

## Reproduction

Use the existing host Python environment with `numpy` and `rasterio`, the
pinned native/timing packages, and the complete L1 archive. Keep the pinned
`acquisition-plan.json` immediately beside that archive directory, and the
official ATBD PDF and its retrieval receipt under the archive's `docs/`.
Those documentary inputs are hashed alongside the image inputs. No GPU or
model environment is needed. Run from the checkout root:

```sh
python3 scripts/audit_teak_mosaic_provenance.py \
  --native /home/alex/projects/lidar_tree_benchmarks/work/teak-native-pilot \
  --pilot /home/alex/projects/lidar_tree_benchmarks/work/teak-native-pilot-output/final-run \
  --timing /home/alex/projects/lidar_tree_benchmarks/work/teak-acquisition-timing-output/final-run \
  --archive /home/alex/projects/lidar_tree_benchmarks/work/teak-mosaic-provenance/sources \
  --out /home/alex/projects/lidar_tree_benchmarks/work/teak-mosaic-provenance-output/new-run
```

The output must be fresh and outside all protected inputs. Repeat with
`--verify` to recompute the outputs and receipt without writing files.
Receipts bind source bytes, declarations, executable code, decoder versions
and generated products. Source archives, arrays and other generated files
remain ignored working data. Public-release changes require a new explicit
source audit rather than rewriting the frozen declaration.
