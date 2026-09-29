# Historical TEAK acquisition-timing audit

Audit acquisition metadata for the already-used TEAK_043 development pilot.
The [native input pilot](../results/teak-native-pilot-results.md) establishes
source identity and local GPS-time groups; the
[detector smoke](../results/teak-detector-smoke-results.md) has already made
this plot model-observed. This audit runs no detector and admits no plot for
evaluation. It does not change the
[canopy scoring policy](teak-canopy-scoring-protocol.md).

## Inputs and scope

The [source declaration](teak-acquisition-timing-sources.json) pins the native
pilot receipt, its source manifests, four camera KMZ downloads, two sanitized
released-product inventories and their retrieval receipt. Two same-name KMZ
variants occur in each of the TEAK June 2018 L1 and L3 camera inventories under
`RELEASE-2026`. Keep both variants, their full stable source URLs, sizes and
hashes. Do not collapse them by basename or retain signed access URLs.

Use the original classified LAS and L1/L3 processing reports from the native
archive. Rehash all 14 accepted pilot outputs and their receipt before using
the pilot's GPS group table. Read only the original LAS header; do not
decompress cloud points, reinterpret model outputs, or open RGB pixels.
Parse only `doc.kml` within each distinct camera KMZ, leaving embedded browse
images unused. The eleven reserved candidate plots remain unprocessed.

## LiDAR association and conditional calendar time

Check the LAS GPS Time Type bit and retain raw GPS-week seconds. Parse all
L1 Table 10 trajectory/LMS intervals and all L3 Table 4 processed intervals,
including repeated processed-line names. For each local PointSourceID group,
retain every interval containing its entire minimum-to-maximum time range.
Use closed boundaries. A PointSourceID is not an LMS line identifier.
Unmatched or ambiguous L1 associations retain unknown calendar times.
Require the pinned 213 L1 rows, 118 L3 rows and five-mission inventory;
reject unparsed row-like text. L3 corroboration requires a unique interval
whose normalized line identifier agrees with the unique L1 association.
Missing, ambiguous or disagreeing L3 evidence remains explicitly unknown.

The declared calendar anchor is GPS week 2005, starting June 10, 2018.
Mission/report context supplies that week; week seconds alone cannot do so.
Subtract the historical GPS-minus-UTC offset of 18 seconds when expressing
conditional UTC. Retain the L1 report's contradictory
`Flight Date: 10-Jun-2018` verbatim. Do not silently reinterpret it as a
week-start field or a verified flight date.

The [USNO time-transfer reference](https://www.cnmoc.usff.navy.mil/our-commands/united-states-naval-observatory/precise-time-department/global-positioning-system/usno-gps-time-transfer/)
documents the GPS epoch and time-scale relationship. The
[IERS leap-second table](https://hpiers.obspm.fr/iers/bul/bulc/Leap_Second.dat)
records TAI minus UTC as 37 seconds from January 2017; GPS remains 19 seconds
behind TAI. These support the 18-second correction for this 2018 acquisition.

## Camera candidates and interpretation

Use full filename identities from each image-style placemark's `Snippet`,
checking its description's filename. Short placemark names can repeat across
missions. Parse the actual `Polygon`, not the accompanying camera-position
`Point`. Transform KML longitude/latitude coordinates into EPSG:32611 before
intersection with the fixed core and context rectangles. Closed intersections
include edge touches; report whole-core coverage separately.

The core bounds are 321034.5–321074.5 m east and
4096711.1–4096751.1 m north. The context extends each bound by 25 m.
Both derive from the accepted native pilot; neither is fitted to imagery.
Inventory all frame IDs and their released L1 product membership, including
nonlocal and missing-product frames. Compare local candidates across both
KMZ variants and retain any disagreement.

The [NEON camera-image location guide](https://www.neonscience.org/sites/default/files/biblio-files/TM007-UserGuide_for_locating_NEON_Camera_Images_0.pdf)
identifies the parenthesized filename timestamp as UTC collection time.
Label it **filename-derived UTC capture time**, rather than an independently
read sensor-clock attribute. A footprint intersection establishes a candidate
exposure only. The [NEON RGB mosaic guide](https://data.neonscience.org/api/v0/documents/quick-start-guides/NEON.QSG.DP3.30010.001v1?fallback=html&inline=true)
describes per-pixel selection among overlapping source images. The KMZ does
not establish which images supplied the released mosaic's pixels.

Keep exact mosaic exposure, LiDAR–RGB lag and measured registration unknown.
The TIFF file timestamp is not a camera exposure. This audit also establishes
no new acquisition linkage for the differing CHM. Reference review,
checkpoint exposure and all real-evaluation flags retain their prior state.

## Reproduction and verification

Run offline from the checkout root with R packages `sf`, `xml2`, `jsonlite`
and `digest`, plus Poppler `pdftotext`. Use the archived files named in the
source declaration and an accepted native pilot. The inventory JSONs retain
product, site, month, release and file identities without access credentials.
They are pinned retrieval snapshots, not promises that a future API response
will have identical bytes. Generated archives and outputs remain under
`work/` and outside version control.

```sh
Rscript scripts/audit_teak_acquisition_timing.R \
  NATIVE=/home/alex/projects/lidar_tree_benchmarks/work/teak-native-pilot \
  PILOT=/home/alex/projects/lidar_tree_benchmarks/work/teak-native-pilot-output/final-run \
  ARCHIVE=/home/alex/projects/lidar_tree_benchmarks/work/teak-acquisition-timing/sources \
  OUT=/home/alex/projects/lidar_tree_benchmarks/work/teak-acquisition-timing-output/new-run
```

The output directory must be fresh and outside all inputs. To verify it,
repeat the command with the same paths and append `VERIFY=1`. Verification
rehashes the pinned inputs, recomputes all tables and assertions, and compares
the complete expected output and receipt bytes without writing files.

Outputs include complete L1/L3 interval inventories, every local GPS interval
association, full camera-frame inventories, context candidates, variant and
product-membership counts, a summary and an input/code/output receipt. The
receipt records package versions and the `pdftotext` executable identity.
These products document metadata evidence; they contain no accuracy score,
new annotation, checkpoint-exposure claim or evaluation admission.
