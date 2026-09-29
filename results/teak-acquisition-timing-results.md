# Historical TEAK acquisition timing

Camera metadata leaves two plausible capture days for the published TEAK_043
image: June 14 and June 15, 2018. The local LiDAR groups associate with June 14
conditional on the reported mission/week anchor. The camera footprints do
not identify the source of individual mosaic pixels, so exact cross-sensor
timing remains unresolved. This metadata-only audit produces no accuracy
score and does not admit an evaluation plot.

The [audit protocol](../docs/teak-acquisition-timing-protocol.md) fixes the
already-used historical pilot, source identities, interval matching and
interpretation limits. The
[native pilot](teak-native-pilot-results.md) supplies verified GPS groups and
image correspondence. Its subsequent
[detector smoke](teak-detector-smoke-results.md) is development evidence;
TEAK_043 cannot become an independent held-out plot through this audit.

## Local LiDAR timing

The original LAS declares GPS week-time, rather than complete absolute dates.
All 43,460 context points belong to three PointSourceID groups. Searching the
complete L1 report's trajectory intervals gives one association per group,
all in mission `2018061416`. L3 processed intervals corroborate these matches.
PointSourceIDs are not assumed to equal the report's trajectory or LMS IDs.
The complete inventories contain 213 L1 rows and 118 L3 rows. The L3 table
has 35 repeated line labels; each interval retains its source row and page
instead of treating those labels as unique identifiers.

| PointSourceID | Points | GPS-week seconds | Trajectory strip | LMS line | Conditional UTC on June 14, 2018 |
| --- | ---: | --- | ---: | --- | --- |
| 12 | 16,576 | 411274.553760–411276.398753 | 9 | 13-1 | 18:14:16.554–18:14:18.399 |
| 13 | 14,522 | 411690.178057–411691.929590 | 10 | 14-1 | 18:21:12.178–18:21:13.930 |
| 14 | 12,362 | 412085.915599–412087.510171 | 11 | 15-1 | 18:27:47.916–18:27:49.510 |

The conversion uses GPS week 2005, starting June 10, and subtracts 18 seconds
to express UTC. The mission/report context supplies the week; LAS week seconds
alone do not establish it. The L1 report repeats
`Flight Date: 10-Jun-2018` across five mission blocks despite June 14–16 mission
identifiers. June 10 is the week's Sunday, but the report does not define the
field as a week start. That contradiction remains recorded and unresolved.

## Camera footprints and competing metadata variants

The released June 2018 L1 and L3 camera inventories each list two different
payloads named `2018_TEAK_3_mosaic.kmz`. They live under `Camera/Reports/` and
`Camera/kmz/`; basename alone cannot identify one. The
[source manifest](../docs/teak-acquisition-timing-sources.json) pins all four
downloads, both product snapshots and the retrieval receipt. Corresponding
variants are byte-identical across products.

| Camera metadata location | Bytes | Image-frame footprints | Core candidates | Context candidates | Frames absent from released L1 inventory |
| --- | ---: | ---: | ---: | ---: | ---: |
| Reports | 23,807,048 | 5,216 | 21 | 23 | 0 |
| kmz | 24,120,301 | 5,285 | 21 | 23 | 69 |

The larger variant adds 69 `TEST` frame records absent from the released L1
image inventory. None intersects the pilot context. Both variants contain
identical local candidate records. Candidate counts use actual polygons
projected into EPSG:32611 and include boundary touches; camera-position
points and short numeric placemark names are not used as footprints or IDs.

| Filename-derived UTC capture day | Core candidate frames | Context candidate frames | Context candidate time range, UTC |
| --- | ---: | ---: | --- |
| June 14, 2018 | 17 | 19 | 18:15:36–20:23:09 |
| June 15, 2018 | 4 | 4 | 18:07:56–18:08:04 |

No June 16 frame footprint intersects the context. Frames from **both June 14
and June 15 individually cover the whole image core**. The four June 15
filenames end in `-0739`, `-0740`, `-0741` and `-0742`; the middle two cover
the entire core. Full mission, camera and timestamp identities are preserved
in the generated tables, so repeated numeric suffixes cannot conflate frames.

The timestamp interpretation comes from the
[NEON camera-image location guide](https://www.neonscience.org/sites/default/files/biblio-files/TM007-UserGuide_for_locating_NEON_Camera_Images_0.pdf).
These are filename-derived UTC candidate exposures. The
[NEON RGB mosaic guide](https://data.neonscience.org/api/v0/documents/quick-start-guides/NEON.QSG.DP3.30010.001v1?fallback=html&inline=true)
describes selecting pixels from overlapping orthorectified source images.
The KMZ contains no source-image index that maps the pilot's final mosaic
pixels to those candidates. The presence of both days therefore establishes
neither a single-day mosaic nor an actual mixture of those days in the core.

## Remaining comparison requirements

The previously established equality of all 480,000 decoded RGB samples links
the published crop to the native mosaic, not to a specific L1 frame. The
native TIFF timestamp `2018:07:22 13:40:39` is a file timestamp, not an exposure
time. Exact RGB pixel provenance and LiDAR–RGB lag remain unknown; local
registration has not been measured. The published/native CHM discrepancy
also remains unresolved.

The next timing evidence needed is a source-image index, seamline record with
verified frame attribution, or equivalent provenance for the released mosaic
covering the pilot. Independently review stable visible features for local
registration and the published boxes for reference completeness under the
[canopy scoring policy](../docs/teak-canopy-scoring-protocol.md). If exact
source attribution is unavailable, retain the limitation explicitly instead
of assuming concurrent pixels from general sensor concurrency.

All evaluation flags remain false. Checkpoint exposure remains unknown and
human reference review remains pending. The eleven reserved plots stay
unprocessed and unadmitted. This audit changes no detector, matching rule,
calibration, frozen baseline or ensemble recommendation.

## Reproduction and verification

The [audit entry point](../scripts/audit_teak_acquisition_timing.R) consumes
the pinned native archive, accepted pilot and camera metadata archive. The
protocol provides the exact command and dependencies. Only the LAS header,
existing GPS summary, processing-report text, inventories and KMZ metadata
are interpreted; cloud points, camera pixels and model outputs are not
processed. Generated artifacts remain ignored working data.

The accepted output is `work/teak-acquisition-timing-output/final-run/`.
Its receipt binds 25 source inputs, three manifests, four executable files
and nine generated outputs. The receipt SHA-256 is
`41ebec99909fe29719bb52c5e1606738980132cbbf416ae608aa52fd78653bec`.
Independent Python checks rehashed those inputs and products, recomputed UTC
from raw GPS ranges, and checked camera counts, membership and false gates.
Both KMZ variants have the same 23 local records. Every LiDAR group has one
L3 interval with the same normalized LMS line as its unique L1 association;
`l3_corroboration_complete` is true.

`VERIFY=1` successfully recomputed all nine outputs and the receipt byte for
byte without changing the accepted files or their modification times.
Entrypoint checks rejected an existing output directory, output inside an
input archive, and a changed source byte before creating output. Verification
also rejected a changed evaluation flag after its advertised output checksum
was updated. The accepted artifact remained unchanged throughout these tests.

Three Sol reviews covered camera evidence, implementation contracts and
scientific interpretation. Astra fixed real-source parsing failures caused
by repeated L3 line labels, multiline KML descriptions and duplicate KMZ
basenames. Further fixes validate declaration semantics, complete interval
inventories, mission-week anchors and explicit L3 corroboration. Regression
fixtures exercise those failures and preserve ambiguous cases as unknown.

The full R suite passed, including 84 focused timing assertions. Three
existing checks were skipped: the opt-in live ForestFormer3D smoke, an
empty-LAS fixture unsupported by this lidR build, and Python PLY reading
because `plyfile` is unavailable. The environment also reported an
inaccessible R-universe package index and a libxml compiled/runtime version
warning. No Python or GPU implementation changed and no detector was rerun.

README now indexes the audit, requirements, result and eligibility limits.
Repository-wide Markdown lint, whitespace checks and all 164 local links in
README and the new documents passed. The complete seven-file change was
reviewed against its intended base; generated sources and outputs stay
outside version control.
The original checkout's 16 changed files retain their original hashes.
