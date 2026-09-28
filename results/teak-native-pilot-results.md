# Native TEAK input pilot

The TEAK_043 pilot recovers a usable native-cloud preparation path for the
[published canopy-reference package](teak-canopy-reference-results.md).
Released NEON data supply intact coordinates, return metadata, acquisition
times and ground classification missing or altered in the benchmark clip.
The pilot is on an already-used plot, chosen before viewing model outputs.
It does not consume an evaluation candidate or produce a detector score.

The [pilot declaration](../docs/teak-native-pilot-protocol.md) fixes a 40 m
image core and 25 m context on each side. The result is an input-processing
check. Independent evaluation admission remains false: checkpoint exposure,
manual reference review and the canopy-box scoring/split policy are unresolved.

## Recovered source data

The released TEAK June 2018 inventories were queried for native classified
LiDAR, RGB camera mosaics and CHM, using `RELEASE-2026`. Six payloads total
126,311,401 bytes: the three spatial tiles at 321000/4096000, L1 and L3
processing reports, and a flightline boundary file. Original payloads are
retained alongside stable file identities, retrieval times and SHA-256
hashes in the [source manifest](../docs/teak-native-pilot-sources.json).
Signed access URLs and credentials are not archived.

The native classified tile contains 5,400,441 points and declares LAS 1.3,
millimetre coordinate scales and horizontal EPSG:32611. Elevations are
absolute, unlike the published normalized benchmark clip. The acquisition's
L1 report describes `ITRF00_UTM_Zone_11N_Geoid12A`; the LAS header has no
explicit vertical CRS. These are distinct pieces of evidence, not proof of
independent datum accuracy or a reason to silently change the header.

The source products are [NEON classified LiDAR](https://data.neonscience.org/data-products/DP1.30003.001),
[RGB mosaics](https://data.neonscience.org/data-products/DP3.30010.001) and
[canopy height](https://data.neonscience.org/data-products/DP3.30015.001).
The published crop's 2018 filename was initially only a selection clue.
The following content comparisons establish much stronger correspondence.

## Correspondence with the published package

**RGB:** all 480,000 decoded colour samples match the corresponding native
mosaic window, on the same pixel grid and CRS. The published TIFF marks 255
as nodata; 39,465 samples have that value. The native mosaic has no nodata
value. A comparison that discards masked pixels would therefore miss part
of the image. The new reader compares unmasked samples and reports nodata
interpretation separately. Neither file is rewritten to force a match.

**LiDAR:** all 8,660 published X/Y, return-number and PointSourceID tuples
occur in the native tile at the declared millimetre coordinate precision.
Of these, 8,658 tuples have unique row correspondence. Two rows share a
duplicate tuple and retain unknown individual row assignments. No nearest
neighbour projection, arbitrary duplicate choice or tree-label transfer is
used. This is coordinate/attribute correspondence, not authentication of
every lost original attribute or of a labelled tree instance.

The field-discrepancy inventory makes that limit concrete. Within the 8,658
unique pairs, `NumberOfReturns` differs on 3,102 rows and classification
on 5,390; all GPS times, intensities and RGB attributes differ. The published
clip retains 1,709 invalid return-number rows. Z values are explicitly in
different height frames. The pilot preserves the released native attributes
and reports these differences instead of repairing the published cloud.

The native image-core footprint contains 8,655 points. Its difference from
the published count is preserved, not equalized by trimming or adding points.
The full native context remains the source for normalization and later
development work. It contains no imported reference instance labels.

**CHM:** the grids match, but only 1,141 of 1,600 cell values are equal;
459 differ, with maximum absolute difference 34.01 m. The workflow retains
that discrepancy and the two rasters. It does not assume the published CHM
is an unchanged subset of the retrieved product or fit a spatial shift.

## Native quality and measured density

The context cloud preserves all 43,460 extracted points, including five
class-7 noise points. Return numbers are valid; there are no withheld points.
Density is measured directly before any normalization, with closed outer
boundaries and the full stated area as denominator:

| Footprint | Area m² | Points | First returns | Ground points | First-return density m⁻² | All-return density m⁻² |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Image core, 40 by 40 m | 1,600 | 8,655 | 6,946 | 6,039 | 4.341 | 5.409 |
| Context, 90 by 90 m | 8,100 | 43,460 | 30,398 | 23,669 | 3.753 | 5.365 |

Across 81 context cells of 10 by 10 m, first-return density ranges from 1.93
to 6.01 m⁻² and all-return density from 2.24 to 10.16 m⁻². Every cell has
points and ground returns. This establishes coarse local coverage, not
uniform sub-metre support. Measured density does not assign a USGS quality
level or establish the density of the user's still-unsupplied deployment data.

Normalization uses the native class-2 ground points and the repository's
existing TIN approach, retaining every point and recording its input-row ID.
A separate 1 m terrain raster is diagnostic; no CHM detector, smoothing,
decimation or height filter is applied. Heights span -0.219 to 40.773 m in
the exported clip, with no points outside the historical -1 to 80 m filter.
The largest absolute normalized height among ground-classified points is
0.039 m. That is an internal interpolation check, not independent AGL RMSE.
All 29 negative heights remain. Original absolute elevations are retained as
double `Zref` extra bytes in the normalized export, alongside the 20 original
point fields and the added row identifier.

## What the timing evidence does and does not resolve

The three PointSourceID groups 12, 13 and 14 have GPS week-time ranges
411274.6–411276.4, 411690.2–411691.9 and 412085.9–412087.5 seconds. They
fall within L1 report Table 10 intervals for mission `2018061416`, LMS
lines 13-1, 14-1 and 15-1 respectively. This is a time-interval association;
PointSourceIDs are not assumed to equal LMS line identifiers.

The L3 report independently lists June 14–16 mission names, while the L1
report repeats a contradictory `Flight Date: 10-Jun-2018` field. The
flightline KML has no labelled line-to-PointSourceID mapping. The native
RGB's July 22 TIFF date is a processing timestamp, not an exposure date.
Content identity links the published image to the retrieved mosaic, but the
original RGB exposure day and exact cross-sensor timing remain unverified.
The report preserves the contradictory source fields rather than resolving
them by assumption.

## Exact checkpoint review

Both checkpoint identities were rehashed without loading their serialized
objects or running inference:

| Arm | SHA-256 | Verification |
| --- | --- | --- |
| ForestFormer3D | `01037a648596832238ac72ea2f5eef87ceaf5aeb399e56ff4b760ba1ed1c777e` | Direct hash of the installed `epoch_3000_fix.pth` |
| SegmentAnyTree | `0b4d74b4644e37a16f59008ad0f5c62894fc4d2d906f3abd803bbfc5b5dd803a` | Direct hash in the pinned reserve image, read-only with networking disabled |

The pinned [ForestFormer3D paper](https://openaccess.thecvf.com/content/ICCV2025/papers/Xiang_ForestFormer3D_A_Unified_Framework_for_End-to-End_Segmentation_of_Forest_LiDAR_ICCV_2025_paper.pdf)
and [supplement](https://openaccess.thecvf.com/content/ICCV2025/supplemental/Xiang_ForestFormer3D_A_Unified_ICCV_2025_supplemental.pdf)
describe FOR-instanceV2 training and head pretraining. The committed split
lists have 47 training, 16 validation and 28 test entries, with no TEAK or
NeonTreeEvaluation names. They are not an exhaustive checkpoint-bound input
manifest: for example, BlueCat appears in the paper but not those lists.

The [SegmentAnyTree paper](https://arxiv.org/abs/2401.15739) describes
FOR-instance, Norwegian mobile laser scanning and augmented training
scenarios. Its documented data geography differs from TEAK. The installed
file lacks a verified exhaustive plot-level exposure record and conclusive
mapping to the paper's selected scenario.

No documented TEAK overlap was found. Nevertheless, pretraining, training,
model-selection and later fine-tuning exposure remain **unknown for both
exact checkpoints** on all eleven candidate plots. Geographic descriptions
and absent name matches cannot establish independent holdouts.

## Readiness and next use

The native acquisition and preparation path now has a concrete historical
pilot, measured density, preserved point fields and review overlays. Use it
for development input-compatibility work. The eleven candidate plots remain
unprocessed by this pilot and no detector or calibration run occurred.

Before a performance comparison, review reference completeness and ambiguous
edge crowns, declare box-compatible matching and whole-plot roles, resolve
cross-sensor timing/registration, and determine whether checkpoint provenance
supports an independent claim or only an explicitly conditional diagnostic.
Published image boxes remain unsuitable for independent 3D-mask, apex-height
or all-tree accuracy claims. No evaluation support is admitted here.

## Reproduction and verification

The [preparation script](../scripts/prepare_teak_native_pilot.R) takes pinned
pilot and published source archives and a fresh output directory. The
protocol documents dependencies, commands and the optional native-file fetch.
Input/output receipts separate source bytes, executable code and generated
clouds, density grids, correspondences and previews. The accepted run and
independent offline replay are `final-run` and `final-replay` under
`work/teak-native-pilot-output/`. Each receipt verifies 24 inputs, eight
executable files, two source manifests and 14 generated outputs. All 15
files, including the receipt, are byte-identical between runs.

Three Sol reviews covered acquisition evidence, checkpoint provenance and
implementation correctness. Astra fixes preserve serialized absolute
elevations, restrict TIN ground support to class 2, reject reserved-field
collisions and inventory published/native field discrepancies. Readback
checks retain all 43,460 rows, all 20 original point fields and unchanged
non-height values; original absolute Z survives as double `Zref`.

The full R suite passed, including 45 focused pilot assertions. All three
Python RGB tests passed. Three existing checks were skipped: the opt-in
live ForestFormer3D smoke, an empty-LAS fixture unsupported by this lidR
build, and Python PLY reading because `plyfile` is unavailable. The run
also reported an inaccessible R-universe package index and a libxml
compiled/runtime version warning. No GPU inference was run.

Entrypoint checks rejected an existing output directory, an output inside
the input archive and a corrupted source before output creation. Repository
Markdown lint, whitespace and document-link checks passed; the complete
change was reviewed against its intended base. README now indexes the
pilot, its measured result and its eligibility limits. Generated data and
model resources remain outside version control. The original checkout's
16 pre-existing changed files were verified unchanged by hash.
