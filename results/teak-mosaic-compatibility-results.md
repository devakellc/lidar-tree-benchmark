# Historical TEAK mosaic compatibility

Exact RGB comparison does not resolve the historical TEAK_043 mosaic's
capture date. Of 160,000 image-core pixels, 158,116 have no exact RGB-triplet
match in the 23 declared candidate frames. The remaining 1,884 pixels include
ambiguous matches across frames and dates. Both source frames and mosaic are
JPEG encoded, so these observations neither exclude a contributing frame nor
establish misregistration. Exact exposure and LiDAR–RGB lag remain unknown.

The [protocol](../docs/teak-mosaic-compatibility-protocol.md) fixes the source
set and grid before comparison. This continues the
[timing audit](teak-acquisition-timing-results.md) on an already-used
development plot. It does not run models, revise annotations, admit plots
or calculate a detector accuracy score.

## Available provenance and source recovery

The inspected TEAK June 2018 released L1/L3 inventories and camera KMZs
provide image identities and footprints, but no per-pixel selected-frame
index or seamline attribution. The target L3 TIFF's exposed tag directory
contains image/storage/georeferencing metadata and generic processing tags,
without a frame-selection map. This is a finding about the inspected records, not
proof that NEON has no retained production records.

The official [Camera Mosaic ATBD](https://data.neonscience.org/api/v0/documents/NEON.DOC.005052vB)
describes selection using per-pixel viewing geometry. It explicitly allows
an overlapping frame to contribute no pixels. Its KMZ describes image/tile
locations and browse imagery. We archived revision B, dated March 2022, as
general algorithm documentation; it does not authenticate the exact 2018
processing configuration or identify this tile's selected frames.

All 23 distinct context candidates were downloaded from the declared
`RELEASE-2026` L1 inventory and hashed in full: 669,643,369 bytes in total.
The [source declaration](../docs/teak-mosaic-provenance-sources.json) records
their exact identities and binds the prior pilot/timing receipts. It includes
the two context-only frames alongside the 21 whose KMZ polygons intersect the
40 m core. No frame was chosen or removed based on pixel similarity.

The original L3 tile and all 23 L1 TIFFs are three-band uint8 RGB in
EPSG:32611, with north-up 0.1 m pixels on the same grid. All use JPEG
compression; their exposed masks are all-valid and they declare no nodata
value. Only each frame's intersection with the fixed 90 m historical context
was requested. Full-file archival does not mean that the surrounding images
or reserved plot windows were analyzed.

## Fixed-grid results

The audit preserves raw RGB values and uses exact equality of all three
channels. It fits no spatial shift, changes no color values and performs no
resampling. Geometric coverage and mask validity are recorded separately from
all-zero or achromatic triplets. All 255-valued samples remain in the test.

| Pixel accounting | 40 m core | 90 m context |
| --- | ---: | ---: |
| Total pixels | 160,000 | 810,000 |
| No exact candidate match | 158,116 | 801,203 |
| Exactly one matching frame | 1,536 | 7,884 |
| More than one matching frame | 348 | 913 |
| Matches confined to June 14 candidates | 1,750 | 8,407 |
| Matches confined to June 15 candidates | 81 | 215 |
| Matches include both days | 53 | 175 |

The first three match bins partition every pixel. The three date bins
partition only pixels with at least one match; they describe matching frame
sets, not verified exposure assignments. Every target pixel has at least one
geometrically covering candidate and at least one mask-valid comparison.
Native mosaic pixels have no all-zero triplets, so raw and nonzero match
counts agree in this run.

Only 1.1775% of core pixels match any candidate exactly. Of those 1,884
pixels, 760 have achromatic RGB triplets and 1,379 have at least one channel
equal to 255. These groups overlap. Common or saturated-looking values can
agree without identifying the original frame. A frame with many more matches
than another is not thereby authenticated as the mosaic source.

Independent JPEG encoding is a plausible reason that a contributing frame
would not preserve exact decoded values, but this audit does not reconstruct
the production encoder chain. A mismatch is therefore not an exclusion rule.
The complete declared candidate input inventory has been tested; complete
production lineage has not been established.

## Consequences for the comparison

Do not choose a capture date, compute a precise LiDAR–RGB lag or fit an image
shift from these match counts. Further similarity searches alone cannot
supply missing production provenance. A selected-frame index, verified
seamline attribution or equivalent release-specific processing record would
be needed to establish exact source lineage.

Local registration is a separate task requiring independently reviewed stable
ground correspondences visible in both sensors, with positional uncertainty.
Native point colors may come from the same camera product; they are not
independent control. Canopy differences, shadow patterns and detector offsets
also cannot establish a ground registration correction.

The software and historical detector compatibility checks are available.
The next work needed for a defensible accuracy comparison is reference
completeness review, independent registration evidence, and explicit treatment
of checkpoint exposure and unresolved RGB exposure/temporal agreement under
the [canopy comparison policy](../docs/teak-canopy-scoring-protocol.md). A
frozen admitted comparison must use equal support; any conditional diagnostic
requires a separate declaration. All evaluation flags remain false, and the
eleven reserved plots remain unused for pixel analysis or inference.

## Reproduction and verification

The [entry point](../scripts/audit_teak_mosaic_provenance.py) takes the pinned
native archive, native pilot, timing package, L1 source archive and fresh
output path. The protocol provides the exact command and dependencies.
Outputs include header and frame inventories, a full-ID/bit crosswalk,
per-pixel geometry, validity and match bitsets, a native-pixel status array,
summary and an input/code/output receipt. Bitsets preserve every declared
candidate; no best-frame choice replaces them.

The accepted output is `work/teak-mosaic-provenance-output/final-run/`.
Its receipt binds 57 input records, executable/declaration identities and
nine generated products. The receipt SHA-256 is
`b6301ab5ad88d476321768683f531235b38b309dda1955fd8d9234774da65692`.
All ten files, including the receipt, are byte-identical to the initial run.
The `--verify` replay recomputed them successfully without writing outputs.

An independent core-only reader used pixel-center coordinates to reproduce
the overall counts and every frame's valid-pair and exact-match counts.
Separate checks rehashed every advertised input and output, reconstructed
summary counts from the bitsets, and verified that match sets are subsets
of valid coverage. Entrypoint checks rejected an existing output, output
inside an input archive, a changed source byte, and an altered eligibility
flag whose local output checksum had been updated. Accepted files retained
their bytes and modification times during the tamper tests.

Three Sol reviews covered official source evidence, scientific interpretation
and implementation contracts. Astra addressed their follow-ups, including
formal tests showing that external `.msk` and PAM `.aux.xml` sidecars cannot
change the decoded audit products while internal TIFF masks remain effective.
All 13 new tests and three existing RGB tests passed. No R or GPU code
changed; those suites were not rerun and no detector was executed.

README now includes the result, protocol, requirements and entry point.
Repository-wide Markdown lint and whitespace checks passed. Generated TIFFs,
arrays, receipts and review evidence remain outside version control; the
original checkout's 16 pre-existing changed files were preserved.
