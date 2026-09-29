# TEAK candidate reference-support reconstruction

Completed 28 September 2026 for the seven distributed plots identified in the
[TEAK validation audit](teak-validation-audit.md), using exact 2022 census
events and archived public location histories. The
[declared reconstruction policy](../docs/teak-reference-protocol.md) preserves
all seven plots and the existing mapped-bole and measured-subplot rules.

**No candidate is ready for a detector comparison under this policy.**
The public API does not supply four required sampled-subplot grid points per
plot. Mapping-quality flags and structurally absent secondary-bole heights
also reduce 29 target records to 12 preliminarily usable boles across three
plots, before geometry. Final interior-selected counts are unavailable,
not zero. No model was run and no detector metric was regenerated.

## Reference-record findings

The archived RELEASE-2026 tables contain 236 exact-year apparent-individual
records across these seven events. Most are outside the declared live,
single/multi-bole, DBH-at-least-10-cm target. The following table separates
that target from records passing non-spatial checks:

| Plot | Target bole records | Mapping quality exclusions | Missing-height exclusions | Usable before geometry | Selected within verified interior |
| --- | --- | --- | --- | --- | --- |
| TEAK_004 | 0 | 0 | 0 | 0 | unavailable |
| TEAK_005 | 13 | 10 | 3 | 0 | unavailable |
| TEAK_010 | 4 | 0 | 0 | 4 | unavailable |
| TEAK_016 | 4 | 0 | 0 | 4 | unavailable |
| TEAK_018 | 4 | 0 | 0 | 4 | unavailable |
| TEAK_024 | 0 | 0 | 0 | 0 | unavailable |
| TEAK_025 | 4 | 3 | 1 | 0 | unavailable |
| Total | 29 | 13 | 4 | 12 | unavailable |

The 13 mapping exclusions carry NEON's `multi-plot duplicate` quality flag.
They are retained in the audit rather than accepted as unique mapped boles.
The four missing heights occur on additional multi-bole identifiers:
`TEAK.03016B`, `TEAK.03016C`, `TEAK.03028A` and `TEAK.03010A` (each prefixed
`NEON.PLA.D17.` in the source). Their exclusions are disjoint from the 13
mapping-quality exclusions.

The [NEON vegetation-structure guide, revision G](https://data.neonscience.org/api/v0/documents/NEON_vegStructure_userGuide_vG?inline=true),
Section 6.3 and Table 5, explains that height and crown attributes for a
multi-bole tree are recorded on its largest bole. These gaps therefore match
the collection protocol; they must not be silently imputed or described as
four arbitrary measurement failures. A future one-tree evaluation would
need a separately declared family/individual identity and measurement-donor
policy. Qualifying bole records are not an interchangeable tree denominator.

TEAK_004 and TEAK_024 contain other growth forms despite having no target
boles. Their zero target counts do not establish empty forest or valid
all-tree negative controls. Even complete support would yield reference-
relative detection metrics for a restricted field population, not independent
crown-mask, all-tree precision, biomass or species validation.

## Mapping dates and location histories

The eight mappings previously flagged as later than the plot-event date
have a narrower explanation:

- TEAK_018 has a plot-event date of 7 September 2022; its four target
  measurements and mappings are dated 8 September.
- TEAK_025 has a plot-event/measurement date of 30 June 2022 and mappings
  dated 6 July.

These differences alone do not demonstrate tree movement or bad coordinates.
The workflow retains all three dates and exports mapping and measurement
histories. It uses the latest unambiguous released mapping as recommended in
the guide, while preserving the quality exclusions above.

Revision G, Section 3.5.1, recommends requesting location history and matching
the coordinate epoch to sampling. The final run requests `?history=true`,
verifies the archived response-body SHA-256, and reparses that body as the
source of coordinates. It requires a unique history interval covering the
whole event date and compatible anchor coordinates at measurement/mapping
dates. Ambiguous, missing or changed histories stay explicit failures; there
is no fallback to today's top-level coordinates.

All 36 available history records contain one interval beginning on
1 January 2010 with no end date. They cover the required dates under that
rule and report WGS84 UTM zone 11N. This resolves the returned records'
coordinate-epoch check; it does not independently establish coordinate
accuracy or alignment to the USGS NAD83(2011)/NAVD88 acquisition.

## Geometry result and its precise limit

The seven events each list four 100 m² subplots:
`31_100|32_100|40_100|41_100`. Their nominal sampled area is 400 m². The
existing measured-quadrilateral policy requires the nine grid points
`31, 32, 33, 40, 41, 42, 49, 50, 51` for each plot.

The complete historical-location retrieval comprises **64 requests**:
63 required corner records plus one additional mapped anchor. Of these,
36 returned HTTP 200 and 28 returned HTTP 400 with `Location not found`.
For every plot the unavailable points are `32`, `40`, `42` and `50`.

The outer corners `31`, `33`, `49`, `51` and centre `41` are available.
The four missing points are edge midpoints needed to reconstruct the four
individual sampled-subplot quadrilaterals under the declared policy. This
result leaves an outer-corner envelope as a possible separate diagnostic;
it does not justify inventing midpoint coordinates, declaring the interior
surveyed, or dropping the subplot-consistency check.

All seven status rows therefore report `geometry_failed`. Measured subplot
areas, conservative interiors, boundary decisions and final selected counts
remain unknown. No support bundle or geometry export was produced. The
reference CSV retains known population/quality/height outcomes while using
missing values for geometry-dependent flags. Failed support is not encoded
as a completed empty plot or zero model detections.

The earlier current-location lookup is preserved as an intermediate
collection; the final result uses the historical responses. The historical
lookup confirmed the same four unavailable points per plot. No statement
here establishes that missing point records do not exist in another source.

## Decision

Do not run or calibrate the ensemble on these seven plots as a new benchmark.
The 12 preliminarily usable boles are too limited, and no measured support
has been admitted. Retain the reconstruction and parent audit as evidence
for designing a better reference set.

If TEAK remains the chosen field-reference route, the next methodological
work is an explicitly declared comparison of an outer-corner support policy
with the current subplot policy, plus resolution of mapping-quality and
multi-bole population questions. Available outer coordinates alone do not
clear those other reference limitations. Any inquiries for additional survey
records require a separate instruction; none was sent during this study.

For deployment validation, prioritize representative user-like native ALS
with independently verified detection references and enough separate plots
for development and evaluation. Actual user tiles have not been supplied,
so their density and acquisition compatibility remain unknown. Crown-mask
validation still needs genuine manual instance/crown annotations. Existing
FGI-EMIT results remain supplementary evidence for that separate task.

## Reproduction and verification

The [preparation entry point](../scripts/prepare_teak_reference_support.R)
checks the pinned parent audit, field/code hashes and complete historical
exposure path inventory. It fetches only public named-point metadata with
`FETCH=1`; it does not acquire clouds or invoke detectors. Reuse the archived
responses for an offline run into a new output directory:

```sh
Rscript scripts/prepare_teak_reference_support.R \
  SOURCE=/home/alex/projects/lidar_tree_benchmarks/work \
  AUDIT=/home/alex/projects/lidar_tree_benchmarks/work/teak-validation-audit/derived-v3 \
  LOCATIONS=/home/alex/projects/lidar_tree_benchmarks/work/teak-reference-support/history-locations \
  OUT=/home/alex/projects/lidar_tree_benchmarks/work/teak-reference-support/replay-new
```

For a fresh metadata snapshot, omit `LOCATIONS` and add `FETCH=1`. The result
may differ if public records change. Every attempt and HTTP failure remains
in its archive. The [evidence manifest](../docs/teak-reference-sources.json)
pins the accepted preparation, public guide and response archive. Raw records,
derived CSVs, complete receipts and review notes remain under
`work/teak-reference-support/`. A code-only checkout lacks those local inputs.

Final preparation and a separate offline replay reproduce the scientific
inventories. Three independent review lenses covered reference science,
primary sources/geometry and reproducibility. Confirmed findings were fixed:
historical coordinate selection, raw-response integrity, explicit per-plot
failure handling and unknown geometry flags. README priorities, workflow
entries and report links reflect the negative admission result.

The full R suite passed, including 44 focused reconstruction assertions.
Three skips remain explicit: optional live FF3D inference, an empty-LAS writer
fixture limitation and unavailable Python `plyfile`. A restricted-network
R-universe package-index warning occurred. No Python/GPU implementation changed
and no live model smoke was run. Both completed runs verified 145 input and
nine output hashes; their nine non-receipt artifacts match byte for byte.
Source manifests, document links, complete diff, repository Markdown lint and
whitespace checks passed. The original checkout's 16 dirty paths were preserved.
